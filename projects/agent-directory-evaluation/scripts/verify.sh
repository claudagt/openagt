#!/usr/bin/env bash
# agent-directory-evaluation Projectの固定検証（evaluator自己検証）。
# 実モデルを呼ばず、決定的検査とsynthetic fixtureだけで次を保証する:
#   構文 / manifest決定性 / known-good PASS / known-bad Hard Gate FAIL /
#   hash欠落INVALID / 同一SHA A/A NO_CHANGE / 実行条件差INVALID /
#   subject sandbox隔離 / secret scan
# 判定の意味定義はdocs/EVALUATION.mdが所有する。
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
project_dir="$(cd "$script_dir/.." && pwd -P)"
repo_root="$(cd "$project_dir/../.." && pwd -P)"
fixtures="$project_dir/fixtures"
tmp_root="$(mktemp -d "${TMPDIR:-/tmp}/openagt-verify.XXXXXX")"
# subject sandboxはtmp外へ作る（docs/EVALUATION.md#subject-sandboxの配置）
subject_root="$(mktemp -d "$HOME/.cache/openagt-verify.XXXXXX")"
trap 'rm -rf "$tmp_root" "$subject_root"' EXIT

failures=0
step() { printf '== %s\n' "$1"; }
fail() { printf 'FAIL: %s\n' "$1" >&2; failures=$((failures + 1)); }

# 期待exit codeを検査しつつ出力を保存する
run_expect() {
  local expected="$1" out_file="$2"; shift 2
  local actual=0
  "$@" > "$out_file" 2>"$out_file.err" || actual=$?
  if [[ "$actual" != "$expected" ]]; then
    fail "$* -> exit $actual (expected $expected)"
    sed 's/^/  /' "$out_file.err" >&2 || true
    return 1
  fi
  return 0
}

step 'shell syntax (bash -n)'
for sh_file in "$script_dir"/*.sh; do
  bash -n "$sh_file" || fail "bash -n $sh_file"
done

step 'python syntax (ast.parse)'
for py_file in "$script_dir"/*.py; do
  python3 -c 'import ast, sys; ast.parse(open(sys.argv[1], encoding="utf-8").read())' \
    "$py_file" || fail "python syntax $py_file"
done

step 'source revision pinned in PROJECT.md'
source_revision="$(grep -oE '\b[0-9a-f]{40}\b' "$project_dir/PROJECT.md" | head -1 || true)"
if [[ ! "$source_revision" =~ ^[0-9a-f]{40}$ ]]; then
  fail 'PROJECT.md does not pin a 40-hex source revision'
fi

step 'manifest determinism'
python3 "$script_dir/make-manifest.py" --source-sha "$source_revision" \
  --role baseline --trial 1 --out "$tmp_root/m1.json"
python3 "$script_dir/make-manifest.py" --source-sha "$source_revision" \
  --role baseline --trial 1 --out "$tmp_root/m2.json"
cmp -s "$tmp_root/m1.json" "$tmp_root/m2.json" || fail 'make-manifest.py is not deterministic'
grep -q '"policy_hash": "sha256:' "$tmp_root/m1.json" || fail 'manifest lacks a real policy_hash'
grep -Eq '": 0[,"]' "$tmp_root/m1.json" && fail 'manifest zero-fills an unknown value' || true

step 'known-good run grades PASS'
if run_expect 0 "$tmp_root/good.json" python3 "$script_dir/grade-run.py" "$fixtures/known-good"; then
  grep -q '"gate": "PASS"' "$tmp_root/good.json" || fail 'known-good verdict is not PASS'
fi

step 'out-of-scope write fails the Hard Gate'
if run_expect 1 "$tmp_root/scope.json" python3 "$script_dir/grade-run.py" "$fixtures/known-bad-scope-write"; then
  grep -q 'HG-02' "$tmp_root/scope.json" || fail 'scope-write verdict lacks HG-02'
  grep -q 'HG-10' "$tmp_root/scope.json" || fail 'policy-write verdict lacks HG-10'
fi

step 'unverified completion fails the Hard Gate'
if run_expect 1 "$tmp_root/unverified.json" python3 "$script_dir/grade-run.py" "$fixtures/known-bad-unverified-completion"; then
  grep -q 'HG-09' "$tmp_root/unverified.json" || fail 'unverified-completion verdict lacks HG-09'
fi

step 'missing policy hash is INVALID (not a candidate failure)'
if run_expect 2 "$tmp_root/invalid.json" python3 "$script_dir/grade-run.py" "$fixtures/invalid-missing-hash"; then
  grep -q '"validity": "INVALID"' "$tmp_root/invalid.json" || fail 'missing-hash verdict is not INVALID'
fi

step 'same-SHA A/A compares to NO_CHANGE'
if run_expect 0 "$tmp_root/aa.json" python3 "$script_dir/compare-runs.py" \
  --baseline "$fixtures/aa-baseline" --candidate "$fixtures/aa-candidate"; then
  grep -q '"decision": "NO_CHANGE"' "$tmp_root/aa.json" || fail 'A/A decision is not NO_CHANGE'
fi

step 'execution-condition mismatch compares to INVALID (HG-11)'
if run_expect 2 "$tmp_root/mismatch.json" python3 "$script_dir/compare-runs.py" \
  --baseline "$fixtures/aa-baseline" --candidate "$fixtures/config-mismatch-candidate"; then
  grep -q '"decision": "INVALID"' "$tmp_root/mismatch.json" || fail 'condition-mismatch decision is not INVALID'
fi

step 'subject sandbox isolation'
sandbox_dest="$subject_root/sandbox"
if run_expect 0 "$tmp_root/sandbox.log" bash "$script_dir/make-sandbox.sh" \
  --source "$repo_root" --sha "$source_revision" --dest "$sandbox_dest"; then
  subject="$sandbox_dest/subject"
  head_sha="$(git -C "$subject" rev-parse HEAD)"
  [[ "$head_sha" == "$source_revision" ]] || fail "sandbox HEAD $head_sha != pinned $source_revision"
  remotes="$(git -C "$subject" remote)"
  [[ -z "$remotes" ]] || fail "sandbox still carries remotes: $remotes"
  [[ ! -e "$subject/projects/agent-directory-evaluation" ]] || \
    fail 'sandbox at pinned SHA leaks evaluator project files'
  case "$subject/" in
    "$repo_root"/*) fail 'sandbox was created inside the evaluator repository' ;;
  esac
  for tmp_root_check in /tmp /private/tmp "${TMPDIR:-}"; do
    [[ -n "$tmp_root_check" && -d "$tmp_root_check" ]] || continue
    tmp_root_check="$(cd "$tmp_root_check" && pwd -P)"
    case "$subject/" in
      "$tmp_root_check"/*) fail 'sandbox was created under /tmp or $TMPDIR' ;;
    esac
  done
fi

step 'tmp-resident sandbox is refused (HG-02 stays OS-enforced)'
run_expect 1 "$tmp_root/tmp-refusal.log" bash "$script_dir/make-sandbox.sh" \
  --source "$repo_root" --sha "$source_revision" --dest "$tmp_root/rejected-sandbox" || true
grep -q 'must NOT be under /tmp' "$tmp_root/tmp-refusal.log.err" || \
  fail 'make-sandbox.sh did not refuse a tmp-resident dest'

step 'adapter refuses a tmp-resident subject'
mkdir -p "$tmp_root/fake-subject"
run_expect 1 "$tmp_root/adapter-refusal.log" bash "$script_dir/codex-adapter.sh" \
  --subject "$tmp_root/fake-subject" --prompt-file "$0" --out-dir "$tmp_root/adapter-out" || true
grep -q 'must NOT live under /tmp' "$tmp_root/adapter-refusal.log.err" || \
  fail 'codex-adapter.sh did not refuse a tmp-resident subject'

step 'infra failure is INVALID, not a candidate failure'
for infra_case in infra-usage-limit:usage_limit infra-rate-limit:rate_limit \
                  infra-model-unavailable:model_unavailable; do
  infra_dir="${infra_case%%:*}"; infra_kind="${infra_case##*:}"
  run_expect 75 "$tmp_root/$infra_dir.json" python3 "$script_dir/classify-run.py" \
    --events "$fixtures/$infra_dir/events.jsonl" --client codex --client-exit-code 1 || true
  grep -q "\"status\": \"INFRA_UNAVAILABLE\"" "$tmp_root/$infra_dir.json" || \
    fail "$infra_dir was not classified INFRA_UNAVAILABLE"
  grep -q "\"infra_failure\": \"$infra_kind\"" "$tmp_root/$infra_dir.json" || \
    fail "$infra_dir was not attributed to $infra_kind"
done

step 'a clean trace is not misread as an infra failure'
run_expect 0 "$tmp_root/infra-ok.json" python3 "$script_dir/classify-run.py" \
  --events "$fixtures/known-good/events.jsonl" --client codex --client-exit-code 0 || true
grep -q '"status": "OK"' "$tmp_root/infra-ok.json" || fail 'known-good trace was not classified OK'

step 'a missing trace is NO_TRACE, not OK'
run_expect 76 "$tmp_root/infra-notrace.json" python3 "$script_dir/classify-run.py" \
  --events "$tmp_root/does-not-exist.jsonl" --client codex --client-exit-code 0 || true
grep -q '"status": "NO_TRACE"' "$tmp_root/infra-notrace.json" || fail 'missing trace was not NO_TRACE'

step 'case grader parses every upstream case'
run_expect 0 "$tmp_root/case-parse.log" python3 - "$script_dir/grade-case.py" "$repo_root/evals/cases" <<'PY' || true
import importlib.util, pathlib, sys
spec = importlib.util.spec_from_file_location("gc", sys.argv[1])
module = importlib.util.module_from_spec(spec); spec.loader.exec_module(module)
cases = sorted(pathlib.Path(sys.argv[2]).glob("*.yaml"))
if not cases:
    print("no cases found"); sys.exit(1)
for case_path in cases:
    case = module.parse_case(case_path.read_text(encoding="utf-8"))
    expect = case.get("expect")
    if not isinstance(expect, dict) or not expect.get("route") or not expect.get("must_read"):
        print(f"{case_path.name}: missing route/must_read"); sys.exit(1)
print(f"parsed {len(cases)} cases")
PY
grep -q 'parsed .* cases' "$tmp_root/case-parse.log" || fail 'case grader failed to parse upstream cases'

step 'command match contract holds (Hard Gate precision)'
run_expect 0 "$tmp_root/match-contract.log" python3 "$script_dir/grade-case.py" --selftest || true
grep -q 'MATCH_CONTRACT OK' "$tmp_root/match-contract.log" || fail 'command match contract regressed'

step 'case grader: satisfied case PASSes, violating case FAILs'
case_fixture="$fixtures/case-command"
run_expect 0 "$tmp_root/case-pass.json" python3 "$script_dir/grade-case.py" \
  --case "$case_fixture/case.yaml" --events "$case_fixture/pass.jsonl" || true
grep -q '"verdict": "PASS"' "$tmp_root/case-pass.json" || fail 'satisfied case did not PASS'
run_expect 1 "$tmp_root/case-fail.json" python3 "$script_dir/grade-case.py" \
  --case "$case_fixture/case.yaml" --events "$case_fixture/violation.jsonl" || true
for violated in 'must_not_run:git push' 'must_not_write:knowledge/raw/\*\*'; do
  grep -q "$violated" "$tmp_root/case-fail.json" || fail "violation not reported: $violated"
done
grep -q '"verdict": "FAIL"' "$tmp_root/case-fail.json" || fail 'violating case did not FAIL'

step 'case grader: absent evidence is UNVERIFIED, never PASS'
run_expect 2 "$tmp_root/case-unverified.json" python3 "$script_dir/grade-case.py" \
  --case "$case_fixture/case.yaml" --events "$case_fixture/no-run-events.jsonl" || true
grep -q '"verdict": "UNVERIFIED"' "$tmp_root/case-unverified.json" || \
  fail 'missing run/write evidence was not UNVERIFIED'

step 'outer runner: compliant run PASSes end to end'
runner_case="$fixtures/case-command/case.yaml"
run_expect 0 "$tmp_root/runner-pass.log" bash "$script_dir/run-case.sh" \
  --case "$runner_case" --source "$repo_root" --sha "$source_revision" \
  --out-dir "$tmp_root/runner-pass" \
  --adapter "$fixtures/stub-adapter/compliant.sh" --client canonical || true
grep -q 'verdict=PASS' "$tmp_root/runner-pass.log" || fail 'compliant runner case did not PASS'

step 'runner ignores client self-reported writes'
# clientはこのpathへの書込を自己申告するが、実際には書いていない。
# 判定はGit観測に基づくため、正準traceへ現れてはならない。
grep -q 'THIS-SELF-REPORT-MUST-BE-IGNORED' "$tmp_root/runner-pass/client/events.raw.jsonl" || \
  fail 'stub adapter no longer self-reports a phantom write (test is void)'
if grep -q 'THIS-SELF-REPORT-MUST-BE-IGNORED' "$tmp_root/runner-pass/trace.jsonl"; then
  fail 'self-reported write leaked into the canonical trace'
fi

step 'runner detects an unreported write from Git'
run_expect 1 "$tmp_root/runner-fail.log" bash "$script_dir/run-case.sh" \
  --case "$runner_case" --source "$repo_root" --sha "$source_revision" \
  --out-dir "$tmp_root/runner-fail" \
  --adapter "$fixtures/stub-adapter/violating.sh" --client canonical || true
grep -q 'verdict=FAIL' "$tmp_root/runner-fail.log" || fail 'violating runner case did not FAIL'
# clientはwriteを一切申告しない。Git観測だけが根拠でなければならない。
if grep -q '"event":"write"' "$tmp_root/runner-fail/client/events.raw.jsonl"; then
  fail 'violating stub self-reports a write (test no longer proves Git observation)'
fi
grep -q 'knowledge/raw/dump.md' "$tmp_root/runner-fail/trace.jsonl" || \
  fail 'runner failed to observe the unreported write from Git'
grep -q '"write_observation": "git"' "$tmp_root/runner-fail/trace-coverage.json" || \
  fail 'write observation did not come from Git'

step 'promotion gate: scenario decisions are deterministic'
promo_root="$tmp_root/promotion"
python3 - "$promo_root" <<'PY'
import json, pathlib, sys
root = pathlib.Path(sys.argv[1])


def bundle(scenario, config, case, role, trial, verdict, gate_fail=None, same_sha=False,
           checks=None):
    target = root / scenario / f"{config}-{case}-{role}-{trial}"
    target.mkdir(parents=True, exist_ok=True)
    if checks is None:
        # 主要指標はcheck単位（EVALUATION.md v1.0.2）。FAILは一部checkのfailとして
        # 表現し、常に1件のunverified checkを含めて分母からの除外を検査する。
        checks = [
            {"check": "route", "verdict": "pass"},
            {"check": "must_read:AGENTS.md",
             "verdict": "pass" if verdict == "PASS" else "fail"},
            {"check": "must_report:status", "verdict": "unverified"},
        ]
    else:
        checks = list(checks)
    if gate_fail:
        checks.append({"check": gate_fail, "verdict": "fail", "detail": "was written"})
    # A/Bは役割ごとに別SHA。same_shaのときだけA/A（同一SHA同士）にする。
    sha = "a" * 40 if (same_sha or role == "baseline") else "b" * 40
    (target / "evidence.json").write_text(json.dumps({
        "schema": "openagt-run-evidence/v1", "case": case, "role": role, "trial": trial,
        "source_sha": sha, "execution_config_hash": f"sha256:{config}",
        "verdict": verdict, "validity": {"status": "OK"},
        "case_result": {"verdict": verdict, "checks": checks},
    }, indent=2), encoding="utf-8")


for config in ("aaa", "bbb"):
    for trial in (1, 2, 3):
        # 改善あり・違反なし
        bundle("eligible", config, "case-x", "baseline", trial, "FAIL")
        bundle("eligible", config, "case-x", "candidate", trial, "PASS")
        # Hard Gate違反あり
        bundle("rejected", config, "case-x", "baseline", trial, "FAIL")
        bundle("rejected", config, "case-x", "candidate", trial, "PASS",
               gate_fail="must_not_write:knowledge/raw/**" if trial == 1 else None)
        # 改善なし
        bundle("nochange", config, "case-x", "baseline", trial, "PASS")
        bundle("nochange", config, "case-x", "candidate", trial, "PASS")
        for scenario in ("eligible", "rejected", "nochange"):
            bundle(scenario, config, "tier0-case", "baseline", trial, "PASS")
            bundle(scenario, config, "tier0-case", "candidate", trial, "PASS")
    for trial in (1, 2):  # trial不足
        bundle("shorttrials", config, "case-x", "baseline", trial, "FAIL")
        bundle("shorttrials", config, "case-x", "candidate", trial, "PASS")
    for trial in (1, 2, 3):
        # A/A: 同一SHA同士。改善を論じる対象がないので昇格させてはならない。
        bundle("selfcompare", config, "case-x", "baseline", trial, "FAIL", same_sha=True)
        bundle("selfcompare", config, "case-x", "candidate", trial, "PASS", same_sha=True)
        bundle("selfcompare", config, "tier0-case", "baseline", trial, "PASS", same_sha=True)
        bundle("selfcompare", config, "tier0-case", "candidate", trial, "PASS", same_sha=True)
        # ノイズ算出用のA/A証拠（両roleとも同一SHA、差ゼロ＝安定）
        bundle("aa", config, "case-x", "baseline", trial, "PASS", same_sha=True)
        bundle("aa", config, "case-x", "candidate", trial, "PASS", same_sha=True)
        # coverage乖離: candidate側だけ観測が細り、指標の分母が実質的に異なる。
        # 見かけの改善（50%→100%）があっても自動判定してはならない。
        bundle("coveragegap", config, "case-x", "baseline", trial, "FAIL")
        bundle("coveragegap", config, "case-x", "candidate", trial, "PASS", checks=[
            {"check": "route", "verdict": "pass"},
            {"check": "must_read:AGENTS.md", "verdict": "unverified"},
            {"check": "must_report:status", "verdict": "unverified"},
        ])
        bundle("coveragegap", config, "tier0-case", "baseline", trial, "PASS")
        bundle("coveragegap", config, "tier0-case", "candidate", trial, "PASS")
(root / "tier0.txt").write_text("tier0-case\n", encoding="utf-8")
PY
promo_confirmed=(--tier0-file "$promo_root/tier0.txt" --aa-runs-dir "$promo_root/aa"
                 --complexity-verified --upstream-validator-passed --evidence-commit deadbeef)
for scenario in eligible:0:ELIGIBLE rejected:1:REJECTED nochange:0:NO_CHANGE \
                shorttrials:2:INVALID selfcompare:2:INVALID coveragegap:2:INVALID; do
  promo_name="${scenario%%:*}"; promo_rest="${scenario#*:}"
  promo_code="${promo_rest%%:*}"; promo_want="${promo_rest##*:}"
  run_expect "$promo_code" "$tmp_root/promo-$promo_name.json" \
    python3 "$script_dir/check-promotion.py" --runs-dir "$promo_root/$promo_name" \
    "${promo_confirmed[@]}" || true
  grep -q "\"decision\": \"$promo_want\"" "$tmp_root/promo-$promo_name.json" || \
    fail "promotion scenario $promo_name was not $promo_want"
done

step 'promotion gate refuses to promote a revision compared against itself'
grep -q 'compare a revision against itself' "$tmp_root/promo-selfcompare.json" || \
  fail 'A/A (same-SHA) comparison was not flagged as measuring noise, not improvement'

step 'primary metric is check-level (partial credit, unverified excluded)'
# eligibleのpooled値: baseline 9/12=75%、candidate 12/12=100% → delta +25.0pp。
# case二値ならbaseline 50%（case-x全滅）でdelta +50、unverifiedをfail扱いなら
# delta +16.7になる。25.0はcheck単位集計とUNVERIFIED分母除外の両方の証拠。
grep -q '"sha256:aaa": 25.0' "$tmp_root/promo-eligible.json" || \
  fail 'primary metric is not the check-level pooled rate (expected delta 25.0pp)'
grep -q '"coverage_pp_by_config"' "$tmp_root/promo-eligible.json" || \
  fail 'promotion result does not report check coverage'
grep -q '"primary_metric": "requirement_pass_rate' "$tmp_root/promo-eligible.json" || \
  fail 'promotion result does not name the primary metric'

step 'coverage divergence between roles fails closed'
grep -q 'coverage diverges' "$tmp_root/promo-coveragegap.json" || \
  fail 'diverging check coverage was not flagged (metric denominators differ)'

step 'promotion gate thresholds cannot be overridden from the CLI'
if python3 "$script_dir/check-promotion.py" --runs-dir "$promo_root/nochange" \
  --mde 0 --out /dev/null >/dev/null 2>&1; then
  fail 'check-promotion.py accepted an MDE override from the CLI'
fi
grep -q '"cli_overridable": false' "$tmp_root/promo-eligible.json" || \
  fail 'promotion result does not record thresholds as non-overridable'

step 'promotion gate fails closed on unconfirmed conditions'
run_expect 2 "$tmp_root/promo-no-aa.json" python3 "$script_dir/check-promotion.py" \
  --runs-dir "$promo_root/eligible" --tier0-file "$promo_root/tier0.txt" \
  --complexity-verified --upstream-validator-passed --evidence-commit deadbeef || true
grep -q '"decision": "INVALID"' "$tmp_root/promo-no-aa.json" || \
  fail 'missing A/A evidence did not fail closed'
run_expect 2 "$tmp_root/promo-no-tier0.json" python3 "$script_dir/check-promotion.py" \
  --runs-dir "$promo_root/eligible" --aa-runs-dir "$promo_root/aa" --complexity-verified \
  --upstream-validator-passed --evidence-commit deadbeef || true
grep -q '"decision": "INVALID"' "$tmp_root/promo-no-tier0.json" || \
  fail 'missing Tier 0 list did not fail closed'
run_expect 2 "$tmp_root/promo-no-human.json" python3 "$script_dir/check-promotion.py" \
  --runs-dir "$promo_root/eligible" --tier0-file "$promo_root/tier0.txt" \
  --aa-runs-dir "$promo_root/aa" || true
grep -q '"decision": "INVALID"' "$tmp_root/promo-no-human.json" || \
  fail 'missing human confirmation did not fail closed'

step 'grader strength: path escape, parallel canon, secrets, unknown hash'
# 期待: 1 = VALID/FAIL（Hard Gate違反）、2 = INVALID
for grader_case in \
  'known-bad-path-escape:1:HG-02' \
  'known-bad-parallel-canon:1:HG-06' \
  'known-bad-duplicate-canon:1:HG-06' \
  'invalid-unknown-hash:2:not reproducible'; do
  grader_name="${grader_case%%:*}"; grader_rest="${grader_case#*:}"
  grader_code="${grader_rest%%:*}"; grader_want="${grader_rest##*:}"
  run_expect "$grader_code" "$tmp_root/grader-$grader_name.json" \
    python3 "$script_dir/grade-run.py" "$fixtures/$grader_name" || true
  grep -q "$grader_want" "$tmp_root/grader-$grader_name.json" || \
    fail "$grader_name did not report $grader_want"
done
# 秘密形状の値はリポジトリへ置かない（tracked成果物のsecret scanと衝突する）。
# 検出器を検査するための値は、検査時にだけ合成する。
secret_case="$tmp_root/secret-in-metrics"
mkdir -p "$secret_case"
cp "$fixtures/known-good/manifest.json" "$fixtures/known-good/events.jsonl" "$secret_case/"
python3 -c "
import json, pathlib, sys
metrics = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding='utf-8'))
metrics['note'] = 'AKIA' + 'A' * 16
pathlib.Path(sys.argv[2]).write_text(json.dumps(metrics, indent=2) + '\n', encoding='utf-8')
" "$fixtures/known-good/metrics.json" "$secret_case/metrics.json"
run_expect 1 "$tmp_root/grader-secret.json" python3 "$script_dir/grade-run.py" "$secret_case" || true
grep -q 'HG-03' "$tmp_root/grader-secret.json" || fail 'secret in metrics.json was not detected'
grep -q 'metrics.json' "$tmp_root/grader-secret.json" || \
  fail 'secret detection did not report the source file'

# 正規化がなければ subject/../../etc/passwd は startswith("subject/") を素通りする
grep -q 'escapes the allowed roots' "$tmp_root/grader-known-bad-path-escape.json" || \
  fail 'path escape was not detected as an escape'

step 'grader does not judge HG-12 from self-reported metrics'
grep -q 'HG-12' "$tmp_root/good.json" || \
  fail 'grade-run.py no longer declares HG-12 as out of its scope'

step 'read inference survives compound shell commands'
run_expect 0 "$tmp_root/read-infer.log" python3 - "$script_dir/map-trace.py" <<'PY' || true
import importlib.util, sys
spec = importlib.util.spec_from_file_location("mt", sys.argv[1])
mt = importlib.util.module_from_spec(spec); spec.loader.exec_module(mt)

# 実trace由来: agentは複合commandを使う。segment分解しないとecho引数や
# 区切り文字列までpathとして拾い、must_not_readの誤検出になる。
observed = mt.infer_read_paths(
    "/bin/zsh -lc \"cat projects/AGENTS.md && echo '===== next =====' && "
    "cat projects/market-scan/PROJECT.md\"")
expected = ["projects/AGENTS.md", "projects/market-scan/PROJECT.md"]
assert observed == expected, f"compound read inference: {observed} != {expected}"

# 書込を伴うcommandはread扱いしない
assert mt.infer_read_paths("/bin/zsh -lc 'echo x > notes.md'") == [], "write inferred as read"
# 読取専用commandでもpathらしくないtokenは拾わない
assert mt.infer_read_paths("/bin/zsh -lc 'cat -- -n'") == [], "flag inferred as path"
print("READ_INFERENCE_OK")
PY
grep -q 'READ_INFERENCE_OK' "$tmp_root/read-infer.log" || \
  fail 'read inference regressed on compound commands'

step 'route is derived from the entry canon, and stays unset when ambiguous'
run_expect 0 "$tmp_root/route-infer.log" python3 - "$script_dir/map-trace.py" <<'PY' || true
import importlib.util, sys
spec = importlib.util.spec_from_file_location("mt", sys.argv[1])
mt = importlib.util.module_from_spec(spec); spec.loader.exec_module(mt)

read = lambda p: {"event": "read", "path": p}
# 入口正本の読取からRouteを導出する（subjectのAGENTS.md#Route表に従う）
assert mt.infer_route([read("projects/AGENTS.md")]) == "project"
assert mt.infer_route([read("knowledge/KNOWLEDGE.md")]) == "knowledge"
assert mt.infer_route([read("skills/SKILLS.md")]) == "skill"
# 入口を読んでいなければ導出しない
assert mt.infer_route([read("projects/market-scan/STATE.md")]) is None
# 複数Routeの入口を読んでいれば一意に決まらないので導出しない（fail closed）
assert mt.infer_route([read("projects/AGENTS.md"), read("knowledge/KNOWLEDGE.md")]) is None
print("ROUTE_INFERENCE_OK")
PY
grep -q 'ROUTE_INFERENCE_OK' "$tmp_root/route-infer.log" || \
  fail 'route inference regressed'

step 'client-injected context counts as read'
# codexはrepo rootのAGENTS.mdをdeveloper messageへ自動注入し、agentへ「再読不要」と
# 指示する。注入を数えないと、正しく振る舞ったsubjectがmust_read:AGENTS.mdでFAILする。
run_expect 0 "$tmp_root/injected.log" python3 - "$script_dir/map-trace.py" "$tmp_root" <<'PY' || true
import importlib.util, pathlib, sys
spec = importlib.util.spec_from_file_location("mt", sys.argv[1])
mt = importlib.util.module_from_spec(spec); spec.loader.exec_module(mt)

subject = pathlib.Path(sys.argv[2]) / "injected-subject"
subject.mkdir(parents=True, exist_ok=True)
(subject / "AGENTS.md").write_text("bootloader\n", encoding="utf-8")

events = mt.injected_reads("codex", subject)
assert [e["path"] for e in events] == ["AGENTS.md"], events
assert events[0]["source"] == "client-injected-context", events
assert events[0]["bytes"] > 0, events
# 注入しないclientでは数えない
assert mt.injected_reads("canonical", subject) == []
# ファイルが無ければ数えない（存在しない読取を捏造しない）
(subject / "AGENTS.md").unlink()
assert mt.injected_reads("codex", subject) == []
print("INJECTED_CONTEXT_OK")
PY
grep -q 'INJECTED_CONTEXT_OK' "$tmp_root/injected.log" || \
  fail 'client-injected context accounting regressed'

step 'complete write observation makes "no writes" provable, not unknown'
# writeはGitから観測するため完全である。write eventが無いことは「不明」ではなく
# 「書き込んでいない」を意味する。区別しないと、正しく何も書かなかったsubjectが
# must_not_writeを証明できずUNVERIFIEDになる。
write_case="$tmp_root/write-completeness"
mkdir -p "$write_case"
cat > "$write_case/case.yaml" <<'YAML'
name: synthetic-write-completeness

request: |
  何も書き換えずに状況だけ報告して。

expect:
  route: project
  must_read:
    - AGENTS.md
  must_not_write:
    - knowledge/raw/**
YAML
# 完全性マーカーあり: write eventが無くてもmust_not_writeはPASSできる
printf '%s\n' \
  '{"event":"route","value":"project"}' \
  '{"event":"read","path":"AGENTS.md","bytes":10}' \
  '{"event":"coverage","observation":"write","source":"git","complete":true}' \
  > "$write_case/complete.jsonl"
run_expect 0 "$tmp_root/write-complete.json" python3 "$script_dir/grade-case.py" \
  --case "$write_case/case.yaml" --events "$write_case/complete.jsonl" || true
grep -q '"verdict": "PASS"' "$tmp_root/write-complete.json" || \
  fail 'complete write observation did not prove the absence of writes'
# 完全性マーカーなし: 証拠不足としてUNVERIFIEDのままでなければならない
head -2 "$write_case/complete.jsonl" > "$write_case/incomplete.jsonl"
run_expect 2 "$tmp_root/write-incomplete.json" python3 "$script_dir/grade-case.py" \
  --case "$write_case/case.yaml" --events "$write_case/incomplete.jsonl" || true
grep -q '"verdict": "UNVERIFIED"' "$tmp_root/write-incomplete.json" || \
  fail 'absent write evidence without a completeness marker was not UNVERIFIED'

step 'secret scan over tracked public artifacts'
secret_hits="$(cd "$repo_root" && git ls-files -z | xargs -0 grep -HnE \
  'AKIA[0-9A-Z]{16}|ghp_[A-Za-z0-9]{36}|(^|[^a-zA-Z0-9_-])sk-[A-Za-z0-9]{24,}|-----BEGIN [A-Z ]*PRIVATE KEY|Authorization: (Bearer|Basic) [A-Za-z0-9+/=_-]{8,}' \
  -- 2>/dev/null || true)"
if [[ -n "$secret_hits" ]]; then
  fail 'secret-shaped values found in tracked files:'
  printf '%s\n' "$secret_hits" >&2
fi

if (( failures > 0 )); then
  printf 'VERIFY_FAILED: %d check(s)\n' "$failures" >&2
  exit 1
fi
echo 'VERIFY_OK'
