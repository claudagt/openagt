#!/usr/bin/env bash
# 段階評価driver（docs/EVALUATION.md#段階評価）。
#
# 評価は「判断が要求する測定だけを、要求された時に」行う。本scriptは決定的な
# バッチ実行だけを担い、判定の意味定義はEVALUATION.md、採点はgrade-case.py、
# 昇格判定はcheck-promotion.pyが所有する。対話agentはバッチへ張り付かない。
#
#   gate  : 上流diffに行動関連pathが含まれるかを判定（NO_EVAL / EVAL_REQUIRED）
#   smoke : Tier 0 × 1 trial。FAILがあればTIER0_FAILで終了
#   ab    : A/B case集合 × N trial（逐次round・早期終了）。baseline roleはcache再利用
#
# 逐次trial: 全caseのtrial roundを順に実行し、candidate Tier 0にFAILが出た時点で
# 3/3は不可能＝REJECTED確定なので残roundを実行しない（判定を変えられない測定は行わない）。
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
project_dir="$(cd "$script_dir/.." && pwd -P)"
repo_root="$(cd "$project_dir/../.." && pwd -P)"

usage() {
  cat >&2 <<'USAGE'
Usage:
  run-eval.sh --stage gate  --source <repo> --diff-base <sha> --diff-head <sha>
  run-eval.sh --stage smoke --source <repo|url> --sha <40-hex> [options]
  run-eval.sh --stage ab    --source <repo|url> --baseline-sha <40-hex> --candidate-sha <40-hex> [options]

Options:
  --cases-file <file>    実行するcase名一覧（既定: ab=docs/ab-case-set.txt, smoke=docs/tier0-cases.txt）
  --tier0-file <file>    Tier 0 case名一覧（既定: docs/tier0-cases.txt）
  --cases-dir <dir>      case YAMLのdir（既定: <repo_root>/evals/cases）
  --trials <N>           trial数（既定: ab=3, smoke=1）
  --parallel <N>         並列度（既定: 20）
  --out-dir <dir>        証拠束の出力先（既定: ~/.cache/openagt-eval/eval.XXXXXX）
  --config-label <name>  execution configのラベル（既定: flash。baseline cache keyの一部）
  --model/--provider     run-case.shへの引き渡し
  --bridge               run-case.shへの引き渡し（pro用bridge）
  --adapter <path>       adapter差し替え（harness自己検証用stub等）
  --client <name>        client名（既定: codex）
  --baseline-cache-dir <dir>  既定: ~/.cache/openagt-eval/baseline-cache
  --no-baseline-cache    baseline cacheを使わない
USAGE
  exit 3
}

stage='' source_repo='' sha='' baseline_sha='' candidate_sha=''
diff_base='' diff_head=''
cases_file='' tier0_file="$project_dir/docs/tier0-cases.txt"
cases_dir="$repo_root/evals/cases"
trials='' parallel=20 out_dir='' config_label='flash'
model='' provider='' bridge='no' adapter='' client='codex'
cache_dir="${OPENAGT_BASELINE_CACHE:-$HOME/.cache/openagt-eval/baseline-cache}"
use_cache='yes'

while (( $# > 0 )); do
  case "$1" in
    --stage) stage="${2:-}"; shift 2 ;;
    --source) source_repo="${2:-}"; shift 2 ;;
    --sha) sha="${2:-}"; shift 2 ;;
    --baseline-sha) baseline_sha="${2:-}"; shift 2 ;;
    --candidate-sha) candidate_sha="${2:-}"; shift 2 ;;
    --diff-base) diff_base="${2:-}"; shift 2 ;;
    --diff-head) diff_head="${2:-}"; shift 2 ;;
    --cases-file) cases_file="${2:-}"; shift 2 ;;
    --tier0-file) tier0_file="${2:-}"; shift 2 ;;
    --cases-dir) cases_dir="${2:-}"; shift 2 ;;
    --trials) trials="${2:-}"; shift 2 ;;
    --parallel) parallel="${2:-}"; shift 2 ;;
    --out-dir) out_dir="${2:-}"; shift 2 ;;
    --config-label) config_label="${2:-}"; shift 2 ;;
    --model) model="${2:-}"; shift 2 ;;
    --provider) provider="${2:-}"; shift 2 ;;
    --bridge) bridge='yes'; shift ;;
    --adapter) adapter="${2:-}"; shift 2 ;;
    --client) client="${2:-}"; shift 2 ;;
    --baseline-cache-dir) cache_dir="${2:-}"; shift 2 ;;
    --no-baseline-cache) use_cache='no'; shift ;;
    *) usage ;;
  esac
done
[[ -n "$stage" && -n "$source_repo" ]] || usage

# --- Stage 0: diff gate -----------------------------------------------------
# 行動関連path（EVALUATION.md#段階評価）に触れない差分へ評価runを割かない。
if [[ "$stage" == 'gate' ]]; then
  [[ -n "$diff_base" && -n "$diff_head" ]] || usage
  changed="$(git -C "$source_repo" diff --name-only "$diff_base..$diff_head")"
  relevant="$(printf '%s\n' "$changed" | grep -Ev \
    '^(README[^/]*|LICENSE[^/]*|\.gitignore|\.gitattributes|docs/.*)$' || true)"
  decision='NO_EVAL'
  [[ -n "$relevant" ]] && decision='EVAL_REQUIRED'
  printf 'GATE_DECISION=%s changed=%d relevant=%d\n' "$decision" \
    "$(printf '%s\n' "$changed" | grep -c . || true)" \
    "$(printf '%s\n' "$relevant" | grep -c . || true)"
  [[ -z "$relevant" ]] || printf '%s\n' "$relevant" | sed 's/^/  relevant: /'
  exit 0
fi

# --- smoke / ab の共通準備 --------------------------------------------------
case "$stage" in
  smoke)
    [[ -n "$sha" ]] || usage
    baseline_sha=''; candidate_sha="$sha"
    : "${trials:=1}"
    : "${cases_file:=$tier0_file}"
    roles=(candidate)
    ;;
  ab)
    [[ -n "$baseline_sha" && -n "$candidate_sha" ]] || usage
    : "${trials:=3}"
    : "${cases_file:=$project_dir/docs/ab-case-set.txt}"
    roles=(baseline candidate)
    ;;
  *) usage ;;
esac
[[ -f "$cases_file" ]] || { echo "ERROR: cases file not found: $cases_file" >&2; exit 3; }
[[ -f "$tier0_file" ]] || { echo "ERROR: tier0 file not found: $tier0_file" >&2; exit 3; }

# case一覧（コメント・空行を除く）
mapfile -t cases < <(grep -Ev '^\s*(#|$)' "$cases_file")
(( ${#cases[@]} > 0 )) || { echo "ERROR: no cases in $cases_file" >&2; exit 3; }
for case_name in "${cases[@]}"; do
  [[ -f "$cases_dir/$case_name.yaml" ]] || \
    { echo "ERROR: case not found: $cases_dir/$case_name.yaml" >&2; exit 3; }
done

if [[ -z "$out_dir" ]]; then
  out_dir="$(mktemp -d "$HOME/.cache/openagt-eval/eval.XXXXXX")"
fi
mkdir -p "$out_dir"; out_dir="$(cd "$out_dir" && pwd -P)"

# baseline cache key: 実行条件（EVALUATION.md#baseline証拠の再利用）。
# measurement/suite/grader hashはmanifest生成器から取り、二重実装しない。
cache_key=''
if [[ "$stage" == 'ab' && "$use_cache" == 'yes' ]]; then
  manifest_tmp="$out_dir/.cache-key-manifest.json"
  python3 "$script_dir/make-manifest.py" --source-sha "$baseline_sha" \
    --role baseline --trial 1 --out "$manifest_tmp"
  cache_key="$(python3 - "$manifest_tmp" "$cases_dir" "$config_label" "$model" "$provider" \
      "$client" "$bridge" "${cases[@]}" <<'PY'
import hashlib, json, pathlib, sys
manifest = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
cases_dir = pathlib.Path(sys.argv[2])
digest = hashlib.sha256()
for key in ("source_sha", "measurement_hash", "suite_hash", "grader_hash"):
    digest.update(str(manifest.get(key, "unknown")).encode("utf-8")); digest.update(b"\0")
for part in sys.argv[3:8]:
    digest.update(part.encode("utf-8")); digest.update(b"\0")
for name in sorted(sys.argv[8:]):
    digest.update(name.encode("utf-8")); digest.update(b"\0")
    digest.update((cases_dir / f"{name}.yaml").read_bytes()); digest.update(b"\0")
print(digest.hexdigest()[:32])
PY
)"
  mkdir -p "$cache_dir/$cache_key"
fi

# --- 1 run（role × case × trial）の実行 --------------------------------------
run_one() {
  local role="$1" case_name="$2" trial="$3"
  local run_dir="$out_dir/runs/$role/$case_name/trial-$trial"
  local run_sha="$candidate_sha"
  [[ "$role" == 'baseline' ]] && run_sha="$baseline_sha"

  # baseline cache hit: 同一実行条件の再測定は情報を足さない（HG-11はhash一致を
  # 要求するのであって再測定を要求しない）。証拠束をそのまま再利用する。
  if [[ "$role" == 'baseline' && -n "$cache_key" ]]; then
    local cached="$cache_dir/$cache_key/$case_name/trial-$trial"
    if [[ -f "$cached/evidence.json" ]]; then
      mkdir -p "$(dirname "$run_dir")"
      cp -R "$cached" "$run_dir"
      : > "$run_dir/cache-hit"
      return 0
    fi
  fi

  mkdir -p "$run_dir"
  local args=(--case "$cases_dir/$case_name.yaml" --source "$source_repo" --sha "$run_sha"
              --out-dir "$run_dir" --role "$role" --trial "$trial" --client "$client")
  [[ -n "$model" ]] && args+=(--model "$model")
  [[ -n "$provider" ]] && args+=(--provider "$provider")
  [[ "$bridge" == 'yes' ]] && args+=(--bridge)
  [[ -n "$adapter" ]] && args+=(--adapter "$adapter")
  bash "$script_dir/run-case.sh" "${args[@]}" > "$run_dir/runner.log" 2>&1 || true

  # 有効な結果だけをcacheへ蓄積する（INFRA等の未取得trialはcacheしない）
  if [[ "$role" == 'baseline' && -n "$cache_key" && -f "$run_dir/evidence.json" ]]; then
    if python3 - "$run_dir/evidence.json" <<'PY'
import json, sys
e = json.load(open(sys.argv[1]))
ok = e.get("validity", {}).get("status") == "OK" and e.get("verdict") in ("PASS", "FAIL", "UNVERIFIED")
sys.exit(0 if ok else 1)
PY
    then
      mkdir -p "$cache_dir/$cache_key/$case_name"
      cp -R "$run_dir" "$cache_dir/$cache_key/$case_name/trial-$trial"
      rm -f "$cache_dir/$cache_key/$case_name/trial-$trial/cache-hit"
    fi
  fi
}
export -f run_one 2>/dev/null || true

# --- 逐次round実行（round内は並列、round境界で早期終了を判定） -----------------
decision='COMPLETE'
for (( trial=1; trial<=trials; trial++ )); do
  jobs_file="$out_dir/.jobs.round-$trial"
  : > "$jobs_file"
  for role in "${roles[@]}"; do
    for case_name in "${cases[@]}"; do
      printf '%s\t%s\t%s\n' "$role" "$case_name" "$trial" >> "$jobs_file"
    done
  done
  # xargsはexport済み関数を呼べないshellがあるため、自明なwhileループ＋wait方式で
  # 並列化する（依存を増やさない。job数は高々 role×case）。
  active=0
  while IFS=$'\t' read -r role case_name t; do
    run_one "$role" "$case_name" "$t" &
    active=$((active + 1))
    if (( active >= parallel )); then wait -n || true; active=$((active - 1)); fi
  done < "$jobs_file"
  wait || true

  # candidate Tier 0にFAILが出た時点で3/3不可能＝以降のroundは判定を変えられない
  if python3 - "$out_dir/runs" "$tier0_file" <<'PY'
import json, pathlib, sys
runs = pathlib.Path(sys.argv[1])
tier0 = {l.strip() for l in open(sys.argv[2], encoding="utf-8")
         if l.strip() and not l.strip().startswith("#")}
for evidence in runs.glob("candidate/*/trial-*/evidence.json"):
    e = json.loads(evidence.read_text(encoding="utf-8"))
    if e.get("case") in tier0 and e.get("verdict") == "FAIL" \
            and e.get("validity", {}).get("status") == "OK":
        sys.exit(0)  # FAIL found
sys.exit(1)
PY
  then
    if [[ "$stage" == 'smoke' ]]; then decision='TIER0_FAIL'; else decision='REJECTED_EARLY'; fi
    break
  fi
done

# --- 集計（sanitized summary。生logはrunsのdirに残る） ------------------------
summary="$out_dir/summary.json"
python3 - "$out_dir/runs" "$tier0_file" "$stage" "$decision" "$trials" "$summary" <<'PY'
import json, pathlib, sys
runs, tier0_file, stage, decision, trials, out = sys.argv[1:7]
runs = pathlib.Path(runs)
tier0 = {l.strip() for l in open(tier0_file, encoding="utf-8")
         if l.strip() and not l.strip().startswith("#")}
verdicts, executed, cache_hits, infra = {}, 0, 0, 0
for evidence in sorted(runs.glob("*/*/trial-*/evidence.json")):
    e = json.loads(evidence.read_text(encoding="utf-8"))
    role, case = evidence.parts[-4], evidence.parts[-3]
    trial = int(evidence.parent.name.split("-")[-1])
    if (evidence.parent / "cache-hit").exists():
        cache_hits += 1
    else:
        executed += 1
    validity = e.get("validity", {}).get("status")
    verdict = e.get("verdict") if validity == "OK" else f"INVALID:{validity}"
    if validity != "OK":
        infra += 1
    verdicts.setdefault(role, {}).setdefault(case, {})[f"trial-{trial}"] = verdict
smoke_all_pass = all(
    v == "PASS"
    for case, ts in verdicts.get("candidate", {}).items() for v in ts.values()
) if verdicts.get("candidate") else False
if stage == "smoke" and decision == "COMPLETE":
    decision = "SMOKE_PASS" if smoke_all_pass else "SMOKE_UNVERIFIED"
result = {
    "schema": "openagt-eval-summary/v1",
    "stage": stage,
    "decision": decision,
    "trials_planned": int(trials),
    "runs_executed": executed,
    "baseline_cache_hits": cache_hits,
    "runs_not_gradable": infra,
    "tier0_cases": sorted(tier0),
    "verdicts": verdicts,
}
pathlib.Path(out).write_text(
    json.dumps(result, indent=2, sort_keys=True, ensure_ascii=False) + "\n", encoding="utf-8")
print(f"EVAL_DONE stage={stage} decision={decision} "
      f"executed={executed} cache_hits={cache_hits} out={out}")
PY

# exit code: 0 = 完走/合格系, 1 = Tier 0起因の早期確定, 2 = 未取得を含む
final_decision="$(python3 -c "import json;print(json.load(open('$summary'))['decision'])")"
case "$final_decision" in
  TIER0_FAIL|REJECTED_EARLY) exit 1 ;;
  SMOKE_UNVERIFIED) exit 2 ;;
  *) exit 0 ;;
esac
