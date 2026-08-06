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
trap 'rm -rf "$tmp_root"' EXIT

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
sandbox_dest="$tmp_root/sandbox"
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
fi

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
