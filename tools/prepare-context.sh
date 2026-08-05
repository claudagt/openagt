#!/usr/bin/env bash
set -euo pipefail

# Route確定後の初期読込を1回のTool呼び出しへまとめるContext Packetを出力する。
# Toolは決定的な列挙（Git root、Required/Conditional参照、読込順序、profile候補）だけを
# 行い、Conditionalの成立判断と成果の設計はエージェントが行う。本文は出力しない。

tool_root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="${AGENT_DIRECTORY_ROOT:-$(cd "$tool_root/.." && pwd)}"
route=''
target=''

usage() {
  printf 'Usage: %s --route knowledge|skill|project|meta [--target <repo-relative-path>]\n' \
    "${0##*/}" >&2
}

while (( $# > 0 )); do
  case "$1" in
    --route)
      [[ $# -ge 2 ]] || { usage; exit 2; }
      route="$2"
      shift 2
      ;;
    --target)
      [[ $# -ge 2 ]] || { usage; exit 2; }
      target="$2"
      shift 2
      ;;
    *) usage; exit 2 ;;
  esac
done

case "$route" in knowledge|skill|project|meta) ;; *) usage; exit 2 ;; esac
target="${target%/}"
if [[ "$target" == /* || "$target" == *..* ]]; then
  printf 'ERROR: --target must be a repository-relative path without ..\n' >&2
  exit 2
fi

read_list=''
missing_list=''
conditional_list=''

queue_read() {
  local path="$1"
  [[ -n "$path" ]] || return 0
  if printf '%s\n' "$read_list" | grep -Fqx -- "$path"; then
    return 0
  fi
  if [[ -f "$repo_root/$path" ]]; then
    read_list="${read_list}${path}
"
  else
    printf '%s\n' "$missing_list" | grep -Fqx -- "$path" || missing_list="${missing_list}${path}
"
  fi
}

queue_conditional() {
  # "<条件> -> <path>" の1行。同一行の重複だけを除き、成立判断はエージェントが行う。
  local line="$1"
  printf '%s\n' "$conditional_list" | grep -Fqx -- "$line" || conditional_list="${conditional_list}${line}
"
}

# `### Required`配下のbacktick参照を、コードフェンス外の一覧行から抽出する。
required_refs() {
  LC_ALL=C awk '
    /^```/ { fence = 1 - fence; next }
    fence { next }
    /^## /  { h2 = $0; h3 = "" }
    /^### / { h3 = $0 }
    h2 ~ /^## 使用する/ && h3 == "### Required" && /^- / {
      line = $0
      while (match(line, /`[^`]+`/)) {
        ref = substr(line, RSTART + 1, RLENGTH - 2)
        print ref
        line = substr(line, RSTART + RLENGTH)
      }
    }
  ' "$1"
}

# `### Conditional`配下の「- 条件: … 参照: `path`」対を「条件 -> path」で出す。
conditional_refs() {
  LC_ALL=C awk '
    /^```/ { fence = 1 - fence; next }
    fence { next }
    /^## /  { h2 = $0; h3 = ""; cond = "" }
    /^### / { h3 = $0; cond = "" }
    h2 ~ /^## 使用する/ && h3 == "### Conditional" {
      if ($0 ~ /^- 条件:/) {
        cond = $0
        sub(/^- 条件:[[:space:]]*/, "", cond)
      } else if (cond != "" && /参照:/ && match($0, /`[^`]+`/)) {
        print cond " -> " substr($0, RSTART + 1, RLENGTH - 2)
        cond = ""
      }
    }
  ' "$1"
}

# 個別AGENTS.mdの`## Project Docs Route`表の行を「条件 -> path」で出す。
docs_route_refs() {
  LC_ALL=C awk -F '|' '
    /^```/ { fence = 1 - fence; next }
    fence { next }
    /^## / { in_route = ($0 == "## Project Docs Route") }
    in_route && NF >= 4 && $2 !~ /^[[:space:]]*-+[[:space:]]*$/ && $2 !~ /条件/ {
      cond = $2
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", cond)
      ref = $3
      if (match(ref, /`[^`]+`/)) {
        print cond " -> " substr(ref, RSTART + 1, RLENGTH - 2)
      }
    }
  ' "$1"
}

git_root='.'
repository_owner='root'
validation_profile='default'
backup_profile='root-only'

queue_read 'AGENTS.md'

case "$route" in
  project)
    if [[ -z "$target" || "$target" != projects/* ]]; then
      printf 'ERROR: project route requires --target projects/<name>\n' >&2
      exit 2
    fi
    project_name="${target#projects/}"
    project_name="${project_name%%/*}"
    project_dir="projects/$project_name"
    if [[ ! -d "$repo_root/$project_dir" ]]; then
      printf 'ERROR: project does not exist: %s\n' "$project_dir" >&2
      exit 2
    fi
    queue_read 'projects/AGENTS.md'
    queue_read "$project_dir/AGENTS.md"
    queue_read "$project_dir/PROJECT.md"
    queue_read "$project_dir/STATE.md"
    if toplevel="$(git -C "$repo_root/$project_dir" rev-parse --show-toplevel 2>/dev/null)"; then
      if [[ "$(cd "$toplevel" && pwd -P)" == "$(cd "$repo_root/$project_dir" && pwd -P)" ]]; then
        repository_owner='independent'
        git_root="$project_dir"
        backup_profile='independent-origin'
      fi
    else
      repository_owner='unresolved'
    fi
    contract="$repo_root/$project_dir/PROJECT.md"
    if [[ -f "$contract" ]]; then
      while IFS= read -r ref; do
        queue_read "$ref"
      done < <(required_refs "$contract")
      while IFS= read -r pair; do
        [[ -n "$pair" ]] && queue_conditional "$pair"
      done < <(conditional_refs "$contract")
    fi
    if [[ -f "$repo_root/$project_dir/AGENTS.md" ]]; then
      # Docs Route表のpathはProject相対である。packetでは全pathをrepo相対へ揃える。
      while IFS= read -r pair; do
        [[ -n "$pair" ]] || continue
        ref="${pair##* -> }"
        cond="${pair% -> *}"
        case "$ref" in
          projects/*|knowledge/*|skills/*|tools/*|evals/*) ;;
          *) ref="$project_dir/$ref" ;;
        esac
        queue_conditional "$cond -> $ref"
      done < <(docs_route_refs "$repo_root/$project_dir/AGENTS.md")
    fi
    ;;
  knowledge)
    queue_read 'knowledge/KNOWLEDGE.md'
    [[ -n "$target" ]] && queue_read "$target"
    ;;
  skill)
    queue_read 'skills/SKILLS.md'
    if [[ -n "$target" ]]; then
      case "$target" in
        skills/*/SKILL.md) queue_read "$target" ;;
        skills/*) queue_read "${target}/SKILL.md" ;;
        *) queue_read "$target" ;;
      esac
    fi
    ;;
  meta)
    # metaは影響が広いためfail-safeで広いprofileを既定にする。
    validation_profile='full'
    case "$target" in
      tools/*) queue_read 'tools/TOOLS.md' ;;
      evals/*) queue_read 'evals/EVALS.md' ;;
      projects/*) queue_read 'projects/PROJECTS.md' ;;
      knowledge/*) queue_read 'knowledge/KNOWLEDGE.md' ;;
    esac
    [[ -n "$target" ]] && queue_read "$target"
    ;;
esac

printf 'TASK_CONTEXT v1\n'
printf 'route=%s\n' "$route"
[[ -n "$target" ]] && printf 'target=%s\n' "$target"
printf 'git_root=%s\n' "$git_root"
printf 'repository_owner=%s\n' "$repository_owner"
printf 'validation_profile=%s\n' "$validation_profile"
printf 'backup_profile=%s\n' "$backup_profile"
printf 'READ:\n'
printf '%s' "$read_list"
if [[ -n "$conditional_list" ]]; then
  printf 'CONDITIONAL:\n'
  printf '%s' "$conditional_list"
fi
if [[ -n "$missing_list" ]]; then
  printf 'MISSING:\n'
  printf '%s' "$missing_list"
fi
