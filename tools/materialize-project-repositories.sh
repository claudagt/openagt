#!/usr/bin/env bash
set -euo pipefail

# Independent Projectの宣言と採用revisionから、固定path projects/<name>/repository/ へ
# 通常cloneを再現する。既存cloneは検証だけを行い、reset/clean/stash/merge/rebaseで変形しない。

tool_root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
repo_root="$(cd "${AGENT_DIRECTORY_ROOT:-$tool_root/..}" 2>/dev/null && pwd -P)" || repo_root=''
select_all=false
only_project=''
check_only=false
pending_target=''
# ローカルbare remoteは隔離fixture検証だけで許可する。通常運用では設定しない。
allow_local_repository_url="${AGENT_ALLOW_LOCAL_REPOSITORY_URL:-false}"

usage() {
  printf 'Usage: %s (--all | --project <name>) [--check]\n' "${0##*/}" >&2
}

blocked() {
  local reason="$1"
  local project="$2"
  local detail
  shift 2
  printf 'MATERIALIZATION_BLOCKED reason=%s project=%s\n' "$reason" "$project" >&2
  for detail in "$@"; do
    [[ -n "$detail" ]] || continue
    printf 'DETAIL: %s\n' "$detail" >&2
  done
  exit 1
}

# 途中で失敗したcloneだけを片づける。固定path以外は決して削除しない。
cleanup() {
  local status=$?
  if (( status != 0 )) && [[ -n "$pending_target" && -d "$pending_target" ]]; then
    case "$pending_target" in
      "$repo_root"/projects/*/repository) rm -rf -- "$pending_target" ;;
    esac
  fi
}
trap cleanup EXIT

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

# repository_urlはoption injection、認証情報、query/fragment、file://、ローカルpathを拒否する。
# scp形式の `git@host:path` と `scheme://host/path` だけを通す。
repository_url_is_rejected() {
  local url="$1"
  local authority userinfo
  [[ -n "$url" ]] || return 0
  case "$url" in
    -*) return 0 ;;
    *[[:space:]]*|*'`'*) return 0 ;;
    *'?'*|*'#'*) return 0 ;;
    file://*|FILE://*) return 0 ;;
  esac
  authority="${url#*://}"
  authority="${authority%%/*}"
  case "$authority" in
    *@*)
      userinfo="${authority%%@*}"
      case "$userinfo" in *:*) return 0 ;; esac
      ;;
  esac
  if [[ "$allow_local_repository_url" != 'true' ]]; then
    case "$url" in
      /*|./*|../*|~*) return 0 ;;
      *://*|*:*) ;;
      *) return 0 ;;
    esac
  fi
  return 1
}

# 宣言時に拒否しているが、報告経路でもuserinfoのpassword、query、fragmentを伏せる。
redact_repository_url() {
  printf '%s' "$1" | sed -E 's|(://[^/:@]+):[^/@]*@|\1:***@|; s|\?.*$|?***|; s|#.*$|#***|'
}

# 認証プロンプトで停止しないよう、失敗出力から原因を分類する。
classify_remote_failure() {
  if printf '%s\n' "$1" | grep -Eqi \
    'authentication|could not read Username|could not read Password|terminal prompts disabled|permission denied \(publickey\)|invalid username or password|access denied'; then
    printf 'authentication-required'
  else
    printf 'remote-unreachable'
  fi
}

while (( $# > 0 )); do
  case "$1" in
    --all) select_all=true; shift ;;
    --project)
      [[ $# -ge 2 ]] || { usage; exit 2; }
      only_project="$2"
      shift 2
      ;;
    --check) check_only=true; shift ;;
    *) usage; exit 2 ;;
  esac
done

if [[ "$select_all" == true && -n "$only_project" ]]; then
  usage
  exit 2
fi
if [[ "$select_all" != true && -z "$only_project" ]]; then
  usage
  exit 2
fi
if [[ -n "$only_project" ]] && { [[ ! "$only_project" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || \
  [[ "$only_project" == '.' || "$only_project" == '..' ]]; }; then
  printf 'ERROR: --project must be a plain Project directory name\n' >&2
  exit 2
fi
if ! command -v git >/dev/null 2>&1; then
  printf 'ERROR: Git is required\n' >&2
  exit 2
fi

[[ -n "$repo_root" ]] || blocked 'not-agent-directory-root' '-' \
  "repository root does not exist: ${AGENT_DIRECTORY_ROOT:-$tool_root/..}"

git_top=''
if ! git_top="$(git -C "$repo_root" rev-parse --show-toplevel 2>/dev/null)"; then
  blocked 'not-agent-directory-root' '-' "not inside a Git working tree: $repo_root"
fi
git_top="$(cd "$git_top" && pwd -P)"
if [[ "$git_top" != "$repo_root" ]]; then
  blocked 'not-agent-directory-root' '-' "run from the repository root: $git_top != $repo_root"
fi
if [[ ! -f "$repo_root/AGENTS.md" || ! -f "$repo_root/tools/validate-agent-directory.sh" ]]; then
  blocked 'not-agent-directory-root' '-' \
    "AGENTS.md and tools/validate-agent-directory.sh are required at $repo_root"
fi

if [[ -n "$only_project" ]]; then
  if ! git -C "$repo_root" ls-files --error-unmatch -- "projects/$only_project/PROJECT.md" \
    >/dev/null 2>&1; then
    blocked 'invalid-project' "$only_project" \
      "projects/$only_project/PROJECT.md is not tracked by the root repository"
  fi
fi

total=0
cloned=0
verified=0

while IFS= read -r project_md; do
  [[ -n "$project_md" && -f "$repo_root/$project_md" ]] || continue
  project_dir="${project_md%/PROJECT.md}"
  project_name="${project_dir##*/}"
  [[ -z "$only_project" || "$project_name" == "$only_project" ]] || continue

  repository_mode="$(frontmatter_value "$repo_root/$project_md" 'repository_mode')"
  [[ "$(frontmatter_key_count "$repo_root/$project_md" 'repository_mode')" == '1' ]] || \
    blocked 'invalid-independent-declaration' "$project_name" \
      "$project_md must declare repository_mode exactly once"
  case "$repository_mode" in
    embedded) continue ;;
    independent) ;;
    *) blocked 'invalid-independent-declaration' "$project_name" \
      "$project_md declares an unsupported repository_mode: ${repository_mode:-<empty>}" ;;
  esac

  repository_url="$(frontmatter_value "$repo_root/$project_md" 'repository_url')"
  repository_reason="$(frontmatter_value "$repo_root/$project_md" 'repository_reason')"
  repository_branch="$(frontmatter_value "$repo_root/$project_md" 'repository_default_branch')"
  for repository_key in repository_url repository_reason repository_default_branch; do
    [[ "$(frontmatter_key_count "$repo_root/$project_md" "$repository_key")" == '1' ]] || \
      blocked 'invalid-independent-declaration' "$project_name" \
        "$project_md must declare $repository_key exactly once"
  done
  case "$repository_reason" in
    automation|distribution|collaboration|access|identity|upstream|retention) ;;
    *) blocked 'invalid-independent-declaration' "$project_name" \
      "$project_md has an invalid repository_reason: ${repository_reason:-<empty>}" ;;
  esac
  if repository_url_is_rejected "$repository_url"; then
    blocked 'invalid-independent-declaration' "$project_name" \
      "$project_md repository_url must be a credential-free remote URL without query, fragment or local path: $(redact_repository_url "$repository_url")"
  fi
  if [[ ! "$repository_branch" =~ ^[A-Za-z0-9][A-Za-z0-9._/-]*$ ]] || \
    ! git check-ref-format --branch "$repository_branch" >/dev/null 2>&1; then
    blocked 'invalid-independent-declaration' "$project_name" \
      "$project_md has an invalid repository_default_branch: ${repository_branch:-<empty>}"
  fi

  state_md="$project_dir/STATE.md"
  git -C "$repo_root" ls-files --error-unmatch -- "$state_md" >/dev/null 2>&1 || \
    blocked 'invalid-independent-state' "$project_name" \
      "$state_md must be tracked by the root repository"
  state_revision="$(repository_state_value "$repo_root/$state_md" 'revision')"
  [[ "$(repository_state_key_count "$repo_root/$state_md" 'revision')" == '1' ]] || \
    blocked 'invalid-independent-state' "$project_name" \
      "$state_md must declare Repository State revision exactly once"
  for retired_key in repository branch remote_verified_at; do
    [[ "$(repository_state_key_count "$repo_root/$state_md" "$retired_key")" == '0' ]] || \
      blocked 'invalid-independent-state' "$project_name" \
        "$state_md Repository State must hold only revision; remove the retired $retired_key field"
  done
  [[ "$state_revision" =~ ^[0-9a-f]{40}$ ]] || \
    blocked 'invalid-independent-state' "$project_name" \
      "$state_md Repository State revision must be a 40-character lowercase commit SHA"

  total=$((total + 1))
  parent="$repo_root/$project_dir"
  target="$parent/repository"
  [[ ! -L "$parent" ]] || blocked 'target-path-symlink' "$project_name" \
    "$project_dir must be a real directory, not a symlink"
  [[ ! -L "$target" ]] || blocked 'target-path-symlink' "$project_name" \
    "$project_dir/repository must be a real directory, not a symlink"

  if [[ -e "$target" ]]; then
    [[ -d "$target" ]] || blocked 'target-not-empty' "$project_name" \
      "$project_dir/repository exists but is not a directory"
    [[ ! -L "$target/.git" ]] || blocked 'target-path-symlink' "$project_name" \
      "$project_dir/repository/.git must be a real directory, not a symlink"
    if [[ -e "$target/.git" && ! -d "$target/.git" ]]; then
      blocked 'repository-gitfile-unsupported' "$project_name" \
        "$project_dir/repository/.git must be a real directory; .git files are unsupported"
    fi
    if [[ ! -d "$target/.git" ]]; then
      if [[ -n "$(find "$target" -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null)" ]]; then
        blocked 'target-not-empty' "$project_name" \
          "$project_dir/repository is not empty and is not a Git repository"
      fi
    fi
  fi

  if [[ -d "$target/.git" ]]; then
    child_top=''
    if ! child_top="$(git -C "$target" rev-parse --show-toplevel 2>/dev/null)"; then
      blocked 'repository-gitfile-unsupported' "$project_name" \
        "$project_dir/repository does not resolve to a Git working tree"
    fi
    child_top="$(cd "$child_top" && pwd -P)"
    [[ "$child_top" == "$target" ]] || blocked 'repository-origin-mismatch' "$project_name" \
      "$project_dir/repository toplevel is $child_top, expected $target"

    child_origin="$(git -C "$target" config --get remote.origin.url 2>/dev/null || true)"
    [[ "$child_origin" == "$repository_url" ]] || blocked 'repository-origin-mismatch' "$project_name" \
      "remote.origin.url is ${child_origin:-<unset>}, expected $repository_url"

    git -C "$target" diff --cached --quiet -- || blocked 'repository-staged' "$project_name" \
      "$project_dir/repository holds staged changes; resolve them in an Independent session"
    git -C "$target" diff --quiet -- || blocked 'repository-dirty' "$project_name" \
      "$project_dir/repository holds uncommitted tracked changes; resolve them in an Independent session"
    child_untracked="$(git -C "$target" ls-files --others --exclude-standard)"
    [[ -z "$child_untracked" ]] || blocked 'repository-untracked' "$project_name" \
      "$project_dir/repository holds untracked files" "$(printf '%s\n' "$child_untracked" | head -n 10)"
    if git -C "$target" rev-parse --verify --quiet refs/stash >/dev/null; then
      blocked 'repository-stash-present' "$project_name" \
        "$project_dir/repository holds stash entries; resolve them in an Independent session"
    fi
    git -C "$target" cat-file -e "${state_revision}^{commit}" 2>/dev/null || \
      blocked 'revision-unavailable' "$project_name" \
        "the adopted revision is missing from the existing clone: $state_revision"
    # 採用revisionがcloneに存在するだけでは足りない。HEADがそこに固定されていることまで確かめる。
    # branch上で作業してそのtipを採用する運用も成立するため、detached HEADまでは要求しない。
    child_head="$(git -C "$target" rev-parse --verify --quiet HEAD || true)"
    [[ "$child_head" == "$state_revision" ]] || \
      blocked 'repository-head-not-adopted' "$project_name" \
        "$project_dir/repository HEAD is ${child_head:-none}, but STATE.md adopts $state_revision"

    verified=$((verified + 1))
    continue
  fi

  if [[ "$check_only" == true ]]; then
    blocked 'missing-independent-repository' "$project_name" \
      "$project_dir/repository is missing; run without --check to materialize it"
  fi

  mkdir -p "$parent"
  pending_target="$target"
  clone_output=''
  if ! clone_output="$(GIT_TERMINAL_PROMPT=0 GIT_ASKPASS=true GCM_INTERACTIVE=never \
    git clone --quiet --no-checkout -- "$repository_url" "$target" 2>&1)"; then
    blocked "$(classify_remote_failure "$clone_output")" "$project_name" \
      "could not clone $(redact_repository_url "$repository_url") into $project_dir/repository" "$clone_output"
  fi

  cloned_origin="$(git -C "$target" config --get remote.origin.url 2>/dev/null || true)"
  [[ "$cloned_origin" == "$repository_url" ]] || blocked 'repository-origin-mismatch' "$project_name" \
    "remote.origin.url is ${cloned_origin:-<unset>}, expected $(redact_repository_url "$repository_url")"

  # 宣言したdefault branchがremoteに実在することを、cloneで取得済みのrefで確かめる。
  git -C "$target" rev-parse --verify --quiet "refs/remotes/origin/$repository_branch" >/dev/null || \
    blocked 'default-branch-missing' "$project_name" \
      "$project_md declares repository_default_branch: $repository_branch, but the remote has no such branch"

  if ! git -C "$target" cat-file -e "${state_revision}^{commit}" 2>/dev/null; then
    fetch_output=''
    if ! fetch_output="$(GIT_TERMINAL_PROMPT=0 GIT_ASKPASS=true GCM_INTERACTIVE=never \
      git -C "$target" fetch --quiet --no-tags origin "$state_revision" 2>&1)"; then
      blocked 'revision-unavailable' "$project_name" \
        "the adopted revision is not fetchable from $repository_url: $state_revision" "$fetch_output"
    fi
    git -C "$target" cat-file -e "${state_revision}^{commit}" 2>/dev/null || \
      blocked 'revision-unavailable' "$project_name" \
        "the adopted revision did not resolve to a commit: $state_revision"
  fi

  # default branchのtipではなく、採用revisionだけをdetachedで再現する。
  checkout_output=''
  if ! checkout_output="$(git -C "$target" checkout --quiet --detach "$state_revision" 2>&1)"; then
    blocked 'revision-unavailable' "$project_name" \
      "could not check out the adopted revision: $state_revision" "$checkout_output"
  fi

  pending_target=''
  cloned=$((cloned + 1))
  printf 'DETAIL: materialized %s at %s\n' "$project_dir/repository" "$state_revision" >&2
done < <(git -C "$repo_root" ls-files -- 'projects/*/PROJECT.md')

if [[ -n "$only_project" && $total -eq 0 ]]; then
  blocked 'invalid-project' "$only_project" \
    "projects/$only_project is not declared as repository_mode: independent"
fi

printf 'MATERIALIZATION_OK total=%s cloned=%s verified=%s\n' "$total" "$cloned" "$verified"
