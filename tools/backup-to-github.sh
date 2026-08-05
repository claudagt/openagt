#!/usr/bin/env bash
set -euo pipefail

tool_root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
repo_root="$(cd "${AGENT_DIRECTORY_ROOT:-$tool_root/..}" 2>/dev/null && pwd -P)" || repo_root=''
max_blob_bytes="${AGENT_BACKUP_MAX_BLOB_BYTES:-104857600}"
remote='backup'
branch='main'
dry_run=false
root_only=false
independent_verify_root=''
independent_index=0

# 宣言済みIndependent Projectの並行配列。bash 3.2にassociative arrayはない。
independent_names=()
independent_dirs=()
independent_urls=()
independent_revisions=()

usage() {
  printf 'Usage: %s [--remote <name>] [--branch <name>] [--dry-run] [--root-only]\n' "${0##*/}" >&2
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

frontmatter_value() {
  awk -v key="$2" '
    NR == 1 && $0 != "---" { exit }
    NR > 1 && $0 == "---" { exit }
    index($0, key ":") == 1 {
      sub(/^[^:]+:[[:space:]]*/, "")
      print
      exit
    }
  ' "$1"
}

frontmatter_key_count() {
  awk -v key="$2" '
    NR == 1 && $0 != "---" { exit }
    NR > 1 && $0 == "---" { exit }
    index($0, key ":") == 1 { count++ }
    END { print count + 0 }
  ' "$1"
}

repository_state_value() {
  awk -v key="$2" '
    $0 == "## Repository State" { in_section = 1; next }
    in_section && /^## / { exit }
    in_section && index($0, "- " key ": `") == 1 {
      value = $0
      sub("^- " key ": `", "", value)
      sub(/`$/, "", value)
      print value
      exit
    }
  ' "$1"
}

repository_state_key_count() {
  awk -v key="$2" '
    $0 == "## Repository State" { in_section = 1; next }
    in_section && /^## / { exit }
    in_section && index($0, "- " key ": `") == 1 { count++ }
    END { print count + 0 }
  ' "$1"
}

cleanup() {
  if [[ -n "$independent_verify_root" && -d "$independent_verify_root" ]]; then
    rm -rf -- "$independent_verify_root"
  fi
}
trap cleanup EXIT

# --- Independent宣言の静的検査 ------------------------------------------------

validate_independent_declaration() {
  local project_md="$1"
  local repository_url repository_reason repository_branch repository_key

  repository_url="$(frontmatter_value "$repo_root/$project_md" 'repository_url')"
  repository_reason="$(frontmatter_value "$repo_root/$project_md" 'repository_reason')"
  repository_branch="$(frontmatter_value "$repo_root/$project_md" 'repository_default_branch')"
  for repository_key in repository_url repository_reason repository_default_branch; do
    [[ "$(frontmatter_key_count "$repo_root/$project_md" "$repository_key")" == '1' ]] || \
      blocked 'invalid-independent-declaration' "$project_md must declare $repository_key exactly once"
  done
  case "$repository_reason" in
    automation|distribution|collaboration|access|identity|upstream|retention) ;;
    *) blocked 'invalid-independent-declaration' "$project_md has an invalid repository_reason" ;;
  esac
  if [[ -z "$repository_url" || "$repository_url" =~ [[:space:]\`] || \
        "$repository_url" =~ ^https?://[^/@]+@ || \
        ! "$repository_branch" =~ ^[A-Za-z0-9][A-Za-z0-9._/-]*$ ]]; then
    blocked 'invalid-independent-declaration' \
      "$project_md has an invalid repository_url or repository_default_branch"
  fi
  printf '%s' "$repository_url"
}

validate_independent_state() {
  local state_md="$1"
  local state_revision retired_key

  [[ -f "$repo_root/$state_md" ]] || blocked 'invalid-independent-state' "$state_md is required"
  [[ "$(repository_state_key_count "$repo_root/$state_md" 'revision')" == '1' ]] || \
    blocked 'invalid-independent-state' "$state_md must declare Repository State revision exactly once"
  for retired_key in repository branch remote_verified_at; do
    [[ "$(repository_state_key_count "$repo_root/$state_md" "$retired_key")" == '0' ]] || \
      blocked 'invalid-independent-state' \
        "$state_md Repository State must hold only revision; remove the retired $retired_key field"
  done
  state_revision="$(repository_state_value "$repo_root/$state_md" 'revision')"
  [[ "$state_revision" =~ ^[0-9a-f]{40}$ ]] || \
    blocked 'invalid-independent-state' \
      "$state_md must pin a 40-character lowercase commit SHA as the adopted revision"
  printf '%s' "$state_revision"
}

# --- 固定pathへのattachment検査 -----------------------------------------------

validate_independent_attachment() {
  local project_dir="$1"
  local repository_url="$2"
  local target="$repo_root/$project_dir/repository"
  local child_top child_origin

  [[ ! -L "$repo_root/$project_dir" ]] || blocked 'repository-path-symlink' \
    "$project_dir must be a real directory, not a symlink"
  [[ ! -L "$target" ]] || blocked 'repository-path-symlink' \
    "$project_dir/repository must be a real directory, not a symlink"
  [[ -d "$target" ]] || blocked 'missing-independent-repository' \
    "$project_dir/repository is missing; run tools/materialize-project-repositories.sh --all"
  [[ ! -L "$target/.git" ]] || blocked 'repository-path-symlink' \
    "$project_dir/repository/.git must be a real directory, not a symlink"
  if [[ ! -d "$target/.git" ]]; then
    blocked 'repository-gitfile-unsupported' \
      "$project_dir/repository/.git must be a real directory; .git files and worktrees are unsupported"
  fi

  if ! child_top="$(git -C "$target" rev-parse --show-toplevel 2>/dev/null)"; then
    blocked 'repository-toplevel-mismatch' "$project_dir/repository is not a Git working tree"
  fi
  child_top="$(cd "$child_top" && pwd -P)"
  [[ "$child_top" == "$target" ]] || blocked 'repository-toplevel-mismatch' \
    "$project_dir/repository toplevel is $child_top, expected $target"

  child_origin="$(git -C "$target" config --get remote.origin.url 2>/dev/null || true)"
  [[ "$child_origin" == "$repository_url" ]] || blocked 'repository-origin-mismatch' \
    "$project_dir/repository remote.origin.url is ${child_origin:-<unset>}, expected $repository_url"
}

# --- Independent本体のローカル状態監査 ----------------------------------------

audit_independent_repository() {
  local project_dir="$1"
  local target="$repo_root/$project_dir/repository"
  local child_untracked nested_child attributes_file

  # 構造的に非対応な状態を先に判定する。cleanlinessより強い停止理由であり、
  # 未追跡ファイルとして報告してしまうと原因が隠れる。
  if git -C "$target" ls-files --stage | awk '$1 == "160000" { found = 1 } END { exit !found }'; then
    blocked 'independent-submodule-unsupported' \
      "$project_dir/repository contains submodules; their contents are not covered"
  fi
  [[ ! -e "$target/.gitmodules" ]] || blocked 'independent-submodule-unsupported' \
    "$project_dir/repository declares .gitmodules; submodules are unsupported"

  nested_child="$(find "$target" -path "$target/.git" -prune -o \
    -mindepth 2 \( -type d -o -type f \) -name .git -print 2>/dev/null | head -n 5)"
  [[ -z "$nested_child" ]] || blocked 'independent-nested-repository' \
    "$project_dir/repository contains a nested Git repository" "$nested_child"

  if [[ -f "$target/.gitattributes" ]] && grep -Fq 'filter=lfs' "$target/.gitattributes"; then
    blocked 'independent-git-lfs-unsupported' "$project_dir/repository uses Git LFS: .gitattributes"
  fi
  while IFS= read -r attributes_file; do
    [[ -n "$attributes_file" && -f "$target/$attributes_file" ]] || continue
    if grep -Fq 'filter=lfs' "$target/$attributes_file"; then
      blocked 'independent-git-lfs-unsupported' \
        "$project_dir/repository uses Git LFS: $attributes_file"
    fi
  done < <(git -C "$target" ls-files -- '.gitattributes' '*/.gitattributes')

  git -C "$target" diff --cached --quiet -- || blocked 'independent-staged-changes' \
    "$project_dir/repository holds staged changes; commit or unstage them in an Independent session"
  git -C "$target" diff --quiet -- || blocked 'independent-dirty-working-tree' \
    "$project_dir/repository holds uncommitted tracked changes; commit them in an Independent session"
  child_untracked="$(git -C "$target" ls-files --others --exclude-standard)"
  [[ -z "$child_untracked" ]] || blocked 'independent-untracked-files' \
    "$project_dir/repository holds untracked non-ignored files" \
    "$(printf '%s\n' "$child_untracked" | head -n 10)"
  if git -C "$target" rev-parse --verify --quiet refs/stash >/dev/null; then
    blocked 'independent-stash-present' \
      "$project_dir/repository holds stash entries; they are never sent to a remote"
  fi
}

# --- 採用revisionとremote到達性 -----------------------------------------------

# 子cloneを変形せず、隔離した一時bare repositoryだけで到達性を判定する。
verify_independent_revision() {
  local project_dir="$1"
  local repository_url="$2"
  local state_revision="$3"
  local target="$repo_root/$project_dir/repository"
  local head_sha fetch_output

  if [[ -z "$independent_verify_root" ]]; then
    independent_verify_root="$(mktemp -d "${TMPDIR:-/tmp}/agent-independent-verify.XXXXXX")" || \
      blocked 'independent-remote-unreachable' \
        'could not create an isolated Independent verification directory'
  fi
  independent_index=$((independent_index + 1))
  verify_repo="$independent_verify_root/$independent_index.git"
  git init --bare -q "$verify_repo" || blocked 'independent-remote-unreachable' \
    "could not initialize the verification repository for $project_dir"

  if ! fetch_output="$(GIT_TERMINAL_PROMPT=0 GIT_ASKPASS=true GCM_INTERACTIVE=never \
    git -C "$verify_repo" fetch --quiet "$repository_url" \
    "+refs/heads/*:refs/remotes/upstream/*" "+refs/tags/*:refs/tags/*" 2>&1)"; then
    blocked 'independent-remote-unreachable' \
      "$project_dir/repository declared remote is unreachable: $repository_url" "$fetch_output"
  fi
  if ! fetch_output="$(GIT_TERMINAL_PROMPT=0 GIT_ASKPASS=true GCM_INTERACTIVE=never \
    git -C "$verify_repo" fetch --quiet --no-tags "$repository_url" "$state_revision" 2>&1)"; then
    blocked 'independent-revision-unavailable' \
      "$project_dir adopted revision is not fetchable from its declared remote: $state_revision" \
      "$fetch_output"
  fi
  git -C "$verify_repo" cat-file -e "${state_revision}^{commit}" 2>/dev/null || \
    blocked 'independent-revision-unavailable' \
      "$project_dir adopted revision did not resolve to a commit: $state_revision"

  # 採用revisionがremoteに存在することを確かめてから、cloneがそこに固定されているかを見る。
  head_sha="$(git -C "$target" rev-parse --verify --quiet HEAD || true)"
  [[ "$head_sha" == "$state_revision" ]] || blocked 'independent-head-not-adopted' \
    "$project_dir/repository HEAD is ${head_sha:-none}, but STATE.md adopts $state_revision"

  printf '%s' "$verify_repo"
}

verify_local_refs_backed_up() {
  local project_dir="$1"
  local verify_repo="$2"
  local target="$repo_root/$project_dir/repository"
  local fetch_output branch_ref branch_sha tag_ref tag_sha remote_tag_sha unpublished

  if ! fetch_output="$(git -C "$verify_repo" fetch --quiet --no-tags "$target" \
    "+refs/heads/*:refs/remotes/child/*" "+refs/tags/*:refs/childtags/*" "+HEAD:refs/childhead" 2>&1)"; then
    blocked 'independent-unreachable-local-branch' \
      "could not read local refs from $project_dir/repository" "$fetch_output"
  fi

  unpublished="$(git -C "$verify_repo" rev-list --count refs/childhead \
    --not --remotes=upstream --tags 2>/dev/null || printf '0')"
  [[ "$unpublished" == '0' ]] || blocked 'independent-unpushed-commit' \
    "$project_dir/repository HEAD holds $unpublished commit(s) absent from its remote"

  while IFS=' ' read -r branch_ref branch_sha; do
    [[ -n "$branch_ref" && -n "$branch_sha" ]] || continue
    unpublished="$(git -C "$verify_repo" rev-list --count "$branch_sha" \
      --not --remotes=upstream --tags 2>/dev/null || printf '1')"
    [[ "$unpublished" == '0' ]] || blocked 'independent-unreachable-local-branch' \
      "$project_dir/repository local branch ${branch_ref#child/} is not reachable from any remote head or tag"
  done < <(git -C "$verify_repo" for-each-ref --format='%(refname:short) %(objectname)' refs/remotes/child)

  while IFS=' ' read -r tag_ref tag_sha; do
    [[ -n "$tag_ref" && -n "$tag_sha" ]] || continue
    remote_tag_sha="$(git -C "$verify_repo" rev-parse --verify --quiet \
      "refs/tags/${tag_ref#childtags/}" || true)"
    [[ "$remote_tag_sha" == "$tag_sha" ]] || blocked 'independent-unpushed-tag' \
      "$project_dir/repository tag ${tag_ref#childtags/} is missing or different on its remote"
  done < <(git -C "$verify_repo" for-each-ref --format='%(refname:short) %(objectname)' refs/childtags)
}

# --- root側の所有関係 ----------------------------------------------------------

validate_root_repository_ownership() {
  local tracked_under_repository gitlink_paths

  # gitlinkを先に判定する。同じpathを平文追跡した場合と停止reasonを区別する。
  gitlink_paths="$(git -C "$repo_root" ls-files --stage | awk '$1 == "160000" { print $4 }' | head -n 10)"
  [[ -z "$gitlink_paths" ]] || blocked 'unsupported-root-gitlink' \
    'the root index holds a gitlink; Independent repositories are plain clones, not submodules' \
    "$gitlink_paths"

  tracked_under_repository="$(git -C "$repo_root" ls-files -- \
    'projects/*/repository' 'projects/*/repository/*' | head -n 10)"
  [[ -z "$tracked_under_repository" ]] || blocked 'root-tracks-independent-repository' \
    'the root repository must not track anything at or under projects/*/repository/' \
    "$tracked_under_repository"

  if git -C "$repo_root" ls-files --error-unmatch -- '.gitmodules' >/dev/null 2>&1; then
    blocked 'unsupported-submodule' 'submodule contents are not covered by this backup; resolve manually'
  fi

  if (( ${#independent_names[@]} > 0 )); then
    if [[ ! -f "$repo_root/.gitignore" ]] || \
      ! grep -Fqx 'projects/*/repository/' "$repo_root/.gitignore"; then
      blocked 'root-tracks-independent-repository' \
        'root .gitignore must contain the exact line: projects/*/repository/'
    fi
  fi
}

# --- 1. options ----------------------------------------------------------------

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
    --root-only) root_only=true; shift ;;
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

# --- 2. root判定 ----------------------------------------------------------------

[[ -n "$repo_root" ]] || blocked 'not-agent-directory-root' \
  "repository root does not exist: ${AGENT_DIRECTORY_ROOT:-$tool_root/..}"

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

# --- 3. branch／remote -----------------------------------------------------------

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

# --- 4. root clean状態 -----------------------------------------------------------

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

# --- 5. root禁止対象 --------------------------------------------------------------

# 許可するnested Gitを決めるため、宣言の発見だけを先に行う。検証は次段が担当する。
# 旧satellite宣言のcloneもここで発見しておき、移行途中の状態が
# `nested-git-repository`ではなく`deprecated-satellite-mode`として報告されるようにする。
discovered_dirs=()
while IFS= read -r discovered_md; do
  [[ -n "$discovered_md" && -f "$repo_root/$discovered_md" ]] || continue
  case "$(frontmatter_value "$repo_root/$discovered_md" 'repository_mode')" in
    independent|satellite) discovered_dirs+=("${discovered_md%/PROJECT.md}") ;;
    *) continue ;;
  esac
done < <(git -C "$repo_root" ls-files -- 'projects/*/PROJECT.md')

nested_prune=( -path "$repo_root/.git" )
if (( ${#discovered_dirs[@]} > 0 )); then
  scan_index=0
  while (( scan_index < ${#discovered_dirs[@]} )); do
    nested_prune+=( -o -path "$repo_root/${discovered_dirs[$scan_index]}/repository" )
    scan_index=$((scan_index + 1))
  done
fi
nested_git="$(find "$repo_root" \( "${nested_prune[@]}" \) -prune -o \
  -mindepth 2 \( -type d -o -type f \) -name .git -print | head -n 10)"
if [[ -n "$nested_git" ]]; then
  blocked 'nested-git-repository' \
    'nested .git entries are forbidden unless they are declared Independent Project clones' "$nested_git"
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

# --- 6. Project metadataの検証 -----------------------------------------------------

while IFS= read -r project_md; do
  [[ -n "$project_md" && -f "$repo_root/$project_md" ]] || continue
  repository_mode="$(frontmatter_value "$repo_root/$project_md" 'repository_mode')"
  [[ "$(frontmatter_key_count "$repo_root/$project_md" 'repository_mode')" == '1' ]] || \
    blocked 'invalid-project-repository-mode' "$project_md must declare repository_mode exactly once"
  project_dir="${project_md%/PROJECT.md}"
  case "$repository_mode" in
    embedded)
      [[ ! -e "$repo_root/$project_dir/repository" ]] || blocked 'invalid-project-repository-mode' \
        "$project_dir is embedded but holds a repository/ directory"
      continue
      ;;
    independent) ;;
    satellite)
      blocked 'deprecated-satellite-mode' \
        "$project_md uses the retired satellite mode; migrate it to repository_mode: independent"
      ;;
    *) blocked 'invalid-project-repository-mode' \
      "$project_md must declare repository_mode: embedded or repository_mode: independent" ;;
  esac

  project_url="$(validate_independent_declaration "$project_md")"
  project_revision="$(validate_independent_state "$project_dir/STATE.md")"

  # 固定path自体がindexへ入っている場合はroot ownership検査がreasonを切り分ける。
  unexpected_root_contents="$(git -C "$repo_root" ls-files -- "$project_dir" |
    awk -v project_md="$project_md" -v state_md="$project_dir/STATE.md" \
      -v repository="$project_dir/repository" \
      '$0 != project_md && $0 != state_md && $0 != repository')"
  [[ -z "$unexpected_root_contents" ]] || blocked 'root-tracks-independent-repository' \
    "$project_dir may track only PROJECT.md and STATE.md" "$unexpected_root_contents"

  independent_names+=("${project_dir##*/}")
  independent_dirs+=("$project_dir")
  independent_urls+=("$project_url")
  independent_revisions+=("$project_revision")
done < <(git -C "$repo_root" ls-files -- 'projects/*/PROJECT.md')

independent_count="${#independent_names[@]}"

# --- 7. root ownership／gitlink ---------------------------------------------------

validate_root_repository_ownership

# --- 8. workspace scopeならIndependent repositoryを監査 ---------------------------

if [[ "$root_only" == true ]]; then
  note "root-only scope: $independent_count declared Independent repository(ies) were not audited"
else
  audit_index=0
  while (( audit_index < independent_count )); do
    audit_dir="${independent_dirs[$audit_index]}"
    audit_url="${independent_urls[$audit_index]}"
    audit_revision="${independent_revisions[$audit_index]}"
    validate_independent_attachment "$audit_dir" "$audit_url"
    audit_independent_repository "$audit_dir"
    audit_verify_repo="$(verify_independent_revision "$audit_dir" "$audit_url" "$audit_revision")"
    verify_local_refs_backed_up "$audit_dir" "$audit_verify_repo"
    note "independent repository verified: $audit_url@$audit_revision at $audit_dir/repository"
    audit_index=$((audit_index + 1))
  done
  note "declared Independent repositories: $independent_count (audited, never pushed by this tool)"
fi

# --- 9. root remote divergence -----------------------------------------------------

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

# --- 10. dry-runまたはroot push ------------------------------------------------------

if [[ "$dry_run" == true ]]; then
  note 'dry run performed no remote write'
  if [[ "$root_only" == true ]]; then
    printf 'ROOT_BACKUP_READY remote=%s branch=%s sha=%s scope=root-only\n' "$remote" "$branch" "$local_head"
  else
    printf 'WORKSPACE_BACKUP_READY remote=%s branch=%s sha=%s independent=%s\n' \
      "$remote" "$branch" "$local_head" "$independent_count"
  fi
  exit 0
fi

push_output=''
if ! push_output="$(git -C "$repo_root" push --porcelain "$remote" "HEAD:refs/heads/$branch" 2>&1)"; then
  blocked 'push-failed' "$push_output"
fi
note "$(printf '%s\n' "$push_output" | tr '\n' ' ')"

# --- 11. remote SHA再確認 -------------------------------------------------------------

verify_listing=''
if ! verify_listing="$(git -C "$repo_root" ls-remote --heads "$remote" "refs/heads/$branch" 2>&1)"; then
  blocked 'remote-verification-unreachable' "cannot re-read refs/heads/$branch from $remote" "$verify_listing"
fi
verified_sha="$(printf '%s\n' "$verify_listing" | awk 'NF >= 2 && $1 ~ /^[0-9a-f]{40}$/ { print $1; exit }')"
if [[ "$verified_sha" != "$local_head" ]]; then
  blocked 'remote-verification-mismatch' "remote=${verified_sha:-none} local=$local_head"
fi

# --- 12. scope別stdout -----------------------------------------------------------------

if [[ "$root_only" == true ]]; then
  printf 'ROOT_BACKUP_OK remote=%s branch=%s sha=%s scope=root-only\n' "$remote" "$branch" "$local_head"
else
  printf 'WORKSPACE_BACKUP_OK remote=%s branch=%s sha=%s independent=%s\n' \
    "$remote" "$branch" "$local_head" "$independent_count"
fi
