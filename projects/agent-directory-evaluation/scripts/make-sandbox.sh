#!/usr/bin/env bash
# subject sandbox生成: 明示SHAからのclean cloneをOS一時領域へ作る。
# - evaluator repository内へは作らない（Git root分離）
# - clone後にremoteを除去し、subject側へevaluatorやremoteの情報を残さない
# - HEADが要求SHAと一致することを検証する（branch tipの自動採用をしない）
# 境界の意味定義はdocs/EVALUATION.mdが所有する。
set -euo pipefail

usage() {
  printf 'Usage: %s --source <path|url> --sha <40-hex> [--dest <dir>]\n' "${0##*/}" >&2
  exit 3
}

source_repo='' sha='' dest=''
while (( $# > 0 )); do
  case "$1" in
    --source) source_repo="${2:-}"; shift 2 ;;
    --sha) sha="${2:-}"; shift 2 ;;
    --dest) dest="${2:-}"; shift 2 ;;
    *) usage ;;
  esac
done
[[ -n "$source_repo" && -n "$sha" ]] || usage
[[ "$sha" =~ ^[0-9a-f]{40}$ ]] || { echo 'ERROR: --sha must be 40-hex' >&2; exit 3; }

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
evaluator_root="$(cd "$script_dir/../../.." && pwd -P)"

if [[ -z "$dest" ]]; then
  dest="$(mktemp -d "${TMPDIR:-/tmp}/openagt-subject.XXXXXX")"
fi
mkdir -p "$dest"
dest="$(cd "$dest" && pwd -P)"

case "$dest/" in
  "$evaluator_root"/*)
    echo "ERROR: sandbox dest must be outside the evaluator repository: $dest" >&2
    exit 1
    ;;
esac

subject="$dest/subject"
if [[ -e "$subject" ]]; then
  echo "ERROR: sandbox already exists: $subject" >&2
  exit 1
fi

git clone --quiet --no-hardlinks "$source_repo" "$subject"
if ! git -C "$subject" cat-file -e "$sha^{commit}" 2>/dev/null; then
  echo "ERROR: requested SHA not present in source: $sha" >&2
  exit 1
fi
git -C "$subject" checkout --quiet --detach "$sha"

head_sha="$(git -C "$subject" rev-parse HEAD)"
if [[ "$head_sha" != "$sha" ]]; then
  echo "ERROR: sandbox HEAD $head_sha does not match requested $sha" >&2
  exit 1
fi

# subject側にremote・evaluator位置情報を残さない
for remote in $(git -C "$subject" remote); do
  git -C "$subject" remote remove "$remote"
done

# evaluator rootへ解決されるsymlinkを禁止する
while IFS= read -r link; do
  target="$(cd "$(dirname "$link")" && cd "$(dirname "$(readlink "$link")")" 2>/dev/null && pwd -P || true)"
  case "${target:-}/" in
    "$evaluator_root"/*)
      echo "ERROR: sandbox symlink escapes into evaluator root: $link" >&2
      exit 1
      ;;
  esac
done < <(find "$subject" -type l 2>/dev/null)

printf '{"schema":"openagt-sandbox/v1","source_sha":"%s","subject":"%s"}\n' "$sha" "$subject" \
  > "$dest/sandbox.json"
echo "SANDBOX_OK $subject $sha"
