#!/usr/bin/env bash
# 外側runner: 1 caseを1 trial実行し、runner側の観測だけで証拠束を作る。
#
# 流れ: sandbox生成 → fixture overlay → baseline commit → request投入 →
#       client trace収集 → 正準traceへ写像（writeはGitから観測） →
#       validity分類 → case採点 → 証拠束出力
#
# subjectの自己申告を判定へ使わない。evaluator rootのpathをsubjectへ渡さない。
# 生logは証拠束へ入れない（docs/EVALUATION.md#traceと公開証拠）。
set -euo pipefail

usage() {
  printf 'Usage: %s --case <file> --source <path|url> --sha <40-hex> --out-dir <dir> [--trial N] [--model M] [--keep-sandbox]\n' "${0##*/}" >&2
  exit 3
}

case_file='' source_repo='' sha='' out_dir='' trial='1' model='' keep_sandbox='no'
# adapterとclientは差し替え可能にする。既定は実clientのcodex。
# harness自己検証は、実モデルを呼ばないstub adapterを注入して同じ経路を通す。
adapter='' client='codex'
while (( $# > 0 )); do
  case "$1" in
    --case) case_file="${2:-}"; shift 2 ;;
    --source) source_repo="${2:-}"; shift 2 ;;
    --sha) sha="${2:-}"; shift 2 ;;
    --out-dir) out_dir="${2:-}"; shift 2 ;;
    --trial) trial="${2:-}"; shift 2 ;;
    --model) model="${2:-}"; shift 2 ;;
    --keep-sandbox) keep_sandbox='yes'; shift ;;
    --adapter) adapter="${2:-}"; shift 2 ;;
    --client) client="${2:-}"; shift 2 ;;
    *) usage ;;
  esac
done
[[ -n "$case_file" && -n "$source_repo" && -n "$sha" && -n "$out_dir" ]] || usage
[[ -f "$case_file" ]] || { echo "ERROR: case not found: $case_file" >&2; exit 3; }

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
[[ -n "$adapter" ]] || adapter="$script_dir/codex-adapter.sh"
repo_root="$(cd "$script_dir/../../.." && pwd -P)"
mkdir -p "$out_dir"; out_dir="$(cd "$out_dir" && pwd -P)"

# caseのparserはgrade-case.pyが単一の正本。ここで別実装を持たない。
read -r fixture_name < <(python3 - "$script_dir/grade-case.py" "$case_file" <<'PY'
import importlib.util, pathlib, sys
spec = importlib.util.spec_from_file_location("gc", sys.argv[1])
gc = importlib.util.module_from_spec(spec); spec.loader.exec_module(gc)
case = gc.parse_case(pathlib.Path(sys.argv[2]).read_text(encoding="utf-8"))
print(case.get("fixture", ""))
PY
)
python3 - "$script_dir/grade-case.py" "$case_file" "$out_dir/request.txt" <<'PY'
import importlib.util, pathlib, sys
spec = importlib.util.spec_from_file_location("gc", sys.argv[1])
gc = importlib.util.module_from_spec(spec); spec.loader.exec_module(gc)
case = gc.parse_case(pathlib.Path(sys.argv[2]).read_text(encoding="utf-8"))
request = case.get("request", "").strip()
if not request:
    print("ERROR: case has no request", file=sys.stderr); sys.exit(3)
pathlib.Path(sys.argv[3]).write_text(request + "\n", encoding="utf-8")
PY

# --- subject sandbox（tmp外。make-sandbox.shが強制する） ---
sandbox_parent="$(mktemp -d "${OPENAGT_SUBJECT_ROOT:-$HOME/.cache/openagt-eval}/run.XXXXXX")"
cleanup() { [[ "$keep_sandbox" == 'yes' ]] || rm -rf "$sandbox_parent"; }
trap cleanup EXIT
bash "$script_dir/make-sandbox.sh" --source "$source_repo" --sha "$sha" --dest "$sandbox_parent" >/dev/null
subject="$sandbox_parent/subject"

# --- fixture overlay ---
fixture_applied='none'
if [[ -n "$fixture_name" ]]; then
  fixture_dir="$repo_root/evals/fixtures/$fixture_name"
  [[ -d "$fixture_dir" ]] || { echo "ERROR: fixture not found: $fixture_dir" >&2; exit 1; }
  cp -R "$fixture_dir"/. "$subject"/
  fixture_applied="$fixture_name"
fi

# baseline commit: 以降のGit差分がsubjectの変更だけを表すようにする
git -C "$subject" -c user.name=openagt -c user.email=openagt@invalid add -A
git -C "$subject" -c user.name=openagt -c user.email=openagt@invalid \
  commit -q --allow-empty -m 'baseline: source + fixture overlay'
baseline_commit="$(git -C "$subject" rev-parse HEAD)"

# --- client実行 ---
adapter_out="$out_dir/client"; mkdir -p "$adapter_out"
adapter_args=(--subject "$subject" --prompt-file "$out_dir/request.txt" --out-dir "$adapter_out")
[[ -n "$model" ]] && adapter_args+=(--model "$model")
set +e
bash "$adapter" "${adapter_args[@]}" >"$out_dir/adapter.log" 2>&1
adapter_rc=$?
set -e

# --- 正準traceへ写像（writeはGitから観測） ---
python3 "$script_dir/map-trace.py" \
  --client "$client" \
  --client-events "$adapter_out/events.raw.jsonl" \
  --subject "$subject" \
  --out "$out_dir/trace.jsonl" \
  --meta-out "$out_dir/trace-coverage.json" 2>>"$out_dir/adapter.log"

# --- runner側のfinal state観測 ---
git -C "$subject" diff --stat HEAD > "$out_dir/diff.stat" 2>/dev/null || true
git -C "$subject" status --porcelain=v1 --untracked-files=all > "$out_dir/final-state.txt" 2>/dev/null || true

# --- validity分類 ---
set +e
python3 "$script_dir/classify-run.py" \
  --events "$adapter_out/events.raw.jsonl" --client "$client" \
  --client-exit-code "$adapter_rc" --out "$out_dir/validity.json" >/dev/null 2>&1
validity_rc=$?
set -e

# --- case採点。実行基盤failureのrunは採点しない（INVALIDをcandidate失敗にしない） ---
if (( validity_rc == 75 || validity_rc == 76 )); then
  verdict='INVALID'
  printf '{"schema":"openagt-case-result/v1","verdict":"INVALID","reason":"run not gradable"}\n' \
    > "$out_dir/case-result.json"
else
  set +e
  python3 "$script_dir/grade-case.py" --case "$case_file" \
    --events "$out_dir/trace.jsonl" --out "$out_dir/case-result.json" >/dev/null 2>&1
  set -e
  verdict="$(python3 -c "import json;print(json.load(open('$out_dir/case-result.json'))['verdict'])")"
fi

# --- 証拠束（sanitized。生logは含めない） ---
python3 - "$out_dir" "$case_file" "$sha" "$trial" "$baseline_commit" "$fixture_applied" "$verdict" <<'PY'
import hashlib, json, pathlib, sys
out, case_file, sha, trial, baseline, fixture, verdict = sys.argv[1:8]
out = pathlib.Path(out)


def load(name, default=None):
    path = out / name
    if not path.is_file():
        return default
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError:
        return default


evidence = {
    "schema": "openagt-run-evidence/v1",
    "case": pathlib.Path(case_file).stem,
    "case_path": case_file,
    "case_sha256": "sha256:" + hashlib.sha256(pathlib.Path(case_file).read_bytes()).hexdigest(),
    "source_sha": sha,
    "trial": int(trial),
    "fixture": fixture,
    "baseline_commit": baseline,
    "verdict": verdict,
    "validity": load("validity.json", {}),
    "trace_coverage": load("trace-coverage.json", {}),
    "case_result": load("case-result.json", {}),
    "final_state": (out / "final-state.txt").read_text(encoding="utf-8").splitlines()
                   if (out / "final-state.txt").is_file() else None,
}
(out / "evidence.json").write_text(
    json.dumps(evidence, indent=2, sort_keys=True, ensure_ascii=False) + "\n", encoding="utf-8")
PY

echo "RUN_DONE verdict=$verdict validity_rc=$validity_rc out=$out_dir"
[[ "$verdict" == 'PASS' ]] && exit 0
[[ "$verdict" == 'INVALID' ]] && exit 2
[[ "$verdict" == 'UNVERIFIED' ]] && exit 2
exit 1
