#!/usr/bin/env bash
set -euo pipefail

tool_root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
repo_root="$(cd "${AGENT_DIRECTORY_ROOT:-$tool_root/..}" 2>/dev/null && pwd -P)" || repo_root=''
max_blob_bytes="${AGENT_BACKUP_MAX_BLOB_BYTES:-104857600}"
remote='backup'
branch='main'
dry_run=false

usage() {
  printf 'Usage: %s [--remote <name>] [--branch <name>] [--dry-run]\n' "${0##*/}" >&2
}

blocked() {
  local reason="$1"
  local detail
  shift
  printf 'BACKUP_BLOCKED reason=%s\n' "$reason" >&2
  for detail in "$@"; do
    [[ -n "$detail" ]] || continue
    printf 'DETAIL: %s\n' "$detail" >&2
  done
  exit 1
}

note() {
  printf 'DETAIL: %s\n' "$1" >&2
}

while (( $# > 0 )); do
  case "$1" in
    --remote|--branch)
      [[ $# -ge 2 ]] || { usage; exit 2; }
      case "$1" in
        --remote) remote="$2" ;;
        --branch) branch="$2" ;;
      esac
      shift 2
      ;;
    --dry-run) dry_run=true; shift ;;
    *) usage; exit 2 ;;
  esac
done

if [[ ! "$remote" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]; then
  printf 'ERROR: --remote must be a simple remote name\n' >&2
  exit 2
fi
if [[ ! "$branch" =~ ^[A-Za-z0-9][A-Za-z0-9._/-]*$ ]]; then
  printf 'ERROR: --branch must be a simple branch name\n' >&2
  exit 2
fi
if [[ ! "$max_blob_bytes" =~ ^[1-9][0-9]*$ ]]; then
  printf 'ERROR: AGENT_BACKUP_MAX_BLOB_BYTES must be a positive integer\n' >&2
  exit 2
fi
if ! command -v git >/dev/null 2>&1; then
  printf 'ERROR: Git is required\n' >&2
  exit 2
fi
[[ -n "$repo_root" ]] || blocked 'not-agent-directory-root' "repository root does not exist: ${AGENT_DIRECTORY_ROOT:-$tool_root/..}"

git_top=''
if ! git_top="$(git -C "$repo_root" rev-parse --show-toplevel 2>/dev/null)"; then
  blocked 'not-git-repository' "not inside a Git working tree: $repo_root"
fi
git_top="$(cd "$git_top" && pwd -P)"
if [[ "$git_top" != "$repo_root" ]]; then
  blocked 'not-agent-directory-root' "run from the repository root: $git_top != $repo_root"
fi
if [[ ! -f "$repo_root/AGENTS.md" || ! -f "$repo_root/tools/validate-agent-directory.sh" ]]; then
  blocked 'not-agent-directory-root' "AGENTS.md and tools/validate-agent-directory.sh are required at $repo_root"
fi

head_ref=''
if ! head_ref="$(git -C "$repo_root" symbolic-ref --quiet HEAD 2>/dev/null)"; then
  blocked 'detached-head' 'HEAD is detached; check out the backup branch first'
fi
current_branch="${head_ref#refs/heads/}"
if [[ "$current_branch" != "$branch" ]]; then
  blocked 'branch-mismatch' "current branch is $current_branch, expected $branch"
fi

local_head=''
if ! local_head="$(git -C "$repo_root" rev-parse --verify --quiet HEAD)" || [[ -z "$local_head" ]]; then
  blocked 'empty-history' "$branch has no commit to back up"
fi

if ! git -C "$repo_root" config --get "remote.$remote.url" >/dev/null 2>&1; then
  blocked 'missing-remote' "remote is not configured: $remote"
fi

git -C "$repo_root" diff --cached --quiet -- || \
  blocked 'staged-changes' 'the index holds uncommitted changes; commit or unstage them first'
git -C "$repo_root" diff --quiet -- || \
  blocked 'dirty-working-tree' 'tracked files hold uncommitted changes; commit them first'

untracked="$(git -C "$repo_root" ls-files --others --exclude-standard)"
if [[ -n "$untracked" ]]; then
  blocked 'untracked-files' 'untracked non-ignored files would not be backed up' \
    "$(printf '%s\n' "$untracked" | head -n 10)"
fi

if git -C "$repo_root" rev-parse --verify --quiet refs/stash >/dev/null; then
  blocked 'stash-present' 'stash entries are never sent to a remote; apply or drop them first'
fi

unmerged=''
while IFS= read -r local_branch; do
  [[ -n "$local_branch" && "$local_branch" != "$branch" ]] || continue
  if ! git -C "$repo_root" merge-base --is-ancestor "refs/heads/$local_branch" "$local_head" 2>/dev/null; then
    unmerged="$unmerged $local_branch"
  fi
done < <(git -C "$repo_root" for-each-ref --format='%(refname:short)' refs/heads/)
if [[ -n "$unmerged" ]]; then
  blocked 'unreachable-local-branch' \
    "these local branches are not reachable from $branch and would not be backed up:$unmerged"
fi

forbidden=''
while IFS= read -r tracked; do
  [[ -n "$tracked" ]] || continue
  case "$tracked" in
    .env.example|*/.env.example) continue ;;
    .tmp/*|*/.tmp/*|.agent-cache/*|*/.agent-cache/*|.DS_Store|*/.DS_Store|.env|.env.*|*/.env|*/.env.*)
      forbidden="$forbidden $tracked"
      ;;
  esac
done < <(git -C "$repo_root" ls-files)
if [[ -n "$forbidden" ]]; then
  blocked 'forbidden-tracked-file' "secrets or disposable paths are tracked:$forbidden"
fi

if git -C "$repo_root" ls-files --stage | awk '$1 == "160000" { found = 1 } END { exit !found }'; then
  blocked 'unsupported-submodule' 'submodule contents are not covered by this backup; resolve manually'
fi
while IFS= read -r attributes_file; do
  [[ -n "$attributes_file" && -f "$repo_root/$attributes_file" ]] || continue
  if grep -Fq 'filter=lfs' "$repo_root/$attributes_file"; then
    blocked 'unsupported-git-lfs' "Git LFS pointers are not covered by this backup: $attributes_file"
  fi
done < <(git -C "$repo_root" ls-files -- '.gitattributes' '*/.gitattributes')

oversized="$(
  git -C "$repo_root" rev-list --objects "$local_head" |
    git -C "$repo_root" cat-file --batch-check='%(objectname) %(objecttype) %(objectsize) %(rest)' |
    awk -v limit="$max_blob_bytes" '
      $2 == "blob" && $3 + 0 >= limit + 0 {
        path = $4
        for (i = 5; i <= NF; i++) path = path " " $i
        if (path == "") path = $1
        printf "%s (%s bytes)\n", path, $3
      }
    '
)"
if [[ -n "$oversized" ]]; then
  blocked 'oversized-git-object' "objects at or above ${max_blob_bytes}B exceed the GitHub hard limit" \
    "$(printf '%s\n' "$oversized" | head -n 10)"
fi

remote_listing=''
if ! remote_listing="$(git -C "$repo_root" ls-remote --heads "$remote" "refs/heads/$branch" 2>&1)"; then
  blocked 'remote-unreachable' "cannot read refs/heads/$branch from $remote" "$remote_listing"
fi
remote_sha="$(printf '%s\n' "$remote_listing" | awk 'NF >= 2 && $1 ~ /^[0-9a-f]{40}$/ { print $1; exit }')"

if [[ -z "$remote_sha" ]]; then
  note "remote branch does not exist yet; this is the initial backup of refs/heads/$branch"
else
  if ! git -C "$repo_root" cat-file -e "${remote_sha}^{commit}" 2>/dev/null; then
    blocked 'remote-diverged' "remote=$remote_sha local=$local_head" \
      'the remote commit does not exist locally; resolve with the user before backing up'
  fi
  if ! git -C "$repo_root" merge-base --is-ancestor "$remote_sha" "$local_head"; then
    blocked 'remote-diverged' "remote=$remote_sha local=$local_head" \
      'the remote branch is ahead of or diverged from local HEAD; resolve with the user before backing up'
  fi
fi

if [[ "$dry_run" == true ]]; then
  note 'dry run performed no remote write'
  printf 'BACKUP_READY remote=%s branch=%s sha=%s\n' "$remote" "$branch" "$local_head"
  exit 0
fi

push_output=''
if ! push_output="$(git -C "$repo_root" push --porcelain "$remote" "HEAD:refs/heads/$branch" 2>&1)"; then
  blocked 'push-failed' "$push_output"
fi
note "$(printf '%s\n' "$push_output" | tr '\n' ' ')"

verify_listing=''
if ! verify_listing="$(git -C "$repo_root" ls-remote --heads "$remote" "refs/heads/$branch" 2>&1)"; then
  blocked 'remote-verification-unreachable' "cannot re-read refs/heads/$branch from $remote" "$verify_listing"
fi
verified_sha="$(printf '%s\n' "$verify_listing" | awk 'NF >= 2 && $1 ~ /^[0-9a-f]{40}$/ { print $1; exit }')"
if [[ "$verified_sha" != "$local_head" ]]; then
  blocked 'remote-verification-mismatch' "remote=${verified_sha:-none} local=$local_head"
fi

printf 'BACKUP_OK remote=%s branch=%s sha=%s\n' "$remote" "$branch" "$local_head"
