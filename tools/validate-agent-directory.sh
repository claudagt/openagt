#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
failures=0
warnings=0
strict=false
full=false
base_ref=''

# 固定Wiki Markdownは大文字名を正本とする。利用者が作るsources/topicsページは対象外。
knowledge_index_path='knowledge/wiki/INDEX.md'
knowledge_log_path='knowledge/wiki/LOG.md'
knowledge_source_template_path='knowledge/wiki/_template/SOURCE.md'
knowledge_topic_template_path='knowledge/wiki/_template/TOPIC.md'
knowledge_index_file="$repo_root/$knowledge_index_path"
knowledge_log_file="$repo_root/$knowledge_log_path"
knowledge_source_template="$repo_root/$knowledge_source_template_path"
knowledge_topic_template="$repo_root/$knowledge_topic_template_path"

usage() {
  printf 'Usage: %s [--strict] [--full] [--base <git-ref>]\n' "${0##*/}" >&2
}

while (( $# > 0 )); do
  case "$1" in
    --strict) strict=true; shift ;;
    --full) full=true; shift ;;
    --base)
      [[ $# -ge 2 ]] || { usage; exit 2; }
      base_ref="$2"
      shift 2
      ;;
    *) usage; exit 2 ;;
  esac
done

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  failures=$((failures + 1))
}

warn() {
  printf 'WARN: %s\n' "$1" >&2
  warnings=$((warnings + 1))
}

relative_path() {
  printf '%s' "${1#"$repo_root"/}"
}

require_file() {
  if [[ ! -f "$1" ]]; then
    fail "missing file: $(relative_path "$1")"
  fi
}

require_fixed_line() {
  local file="$1"
  local line="$2"
  if [[ -f "$file" ]] && ! grep -Fqx -- "$line" "$file"; then
    fail "$(relative_path "$file") is missing: $line"
  fi
}

has_closed_frontmatter() {
  awk '
    NR == 1 && $0 != "---" { exit 1 }
    NR > 1 && $0 == "---" { found = 1; exit }
    END { exit !found }
  ' "$1"
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

value_character_count() {
  printf '%s' "$1" | od -An -tu1 | awk '
    {
      for (i = 1; i <= NF; i++) {
        if ($i < 128 || $i >= 192) count++
      }
    }
    END { print count + 0 }
  '
}

check_size() {
  local file="$1"
  local hard_limit="$2"
  local label="$3"
  local bytes
  [[ -f "$file" ]] || return 0
  bytes="$(wc -c < "$file" | tr -d ' ')"
  if (( bytes > hard_limit )); then
    fail "$(relative_path "$file") exceeds $label hard limit: ${bytes}B > ${hard_limit}B"
  fi
}

check_heading_warning() {
  local file="$1"
  local warning_limit="$2"
  local count
  [[ -f "$file" ]] || return
  count="$(grep -Ec '^#{1,6} ' "$file" || true)"
  if (( count > warning_limit )); then
    warn "$(relative_path "$file") has $count headings; consider delegating details"
  fi
}

contains_template_placeholder() {
  local file="$1"
  grep -Fqf <(
    grep -Eho '<[^>]+>' \
      "$repo_root/projects/_template/PROJECT.md" \
      "$repo_root/projects/_template/STATE.md"
  ) "$file"
}

has_valid_project_criteria() {
  awk -v heading="$2" '
    /^## / { in_section = ($0 == heading); next }
    in_section && /^- / {
      has_item = 1
      if ($0 !~ /^- \*\*PC-(0[1-9]|[1-9][0-9])\*\* .+/) { invalid = 1; next }
      id = substr($0, 5, 5)
      if (seen[id]++) invalid = 1
    }
    /^- \*\*PC-/ && !in_section { invalid = 1 }
    END { exit !(has_item && !invalid) }
  ' "$1"
}

state_section_targets() {
  awk -v heading="$2" -v prefix="$3" '
    $0 == heading { in_section = 1; next }
    in_section && /^## / { exit }
    in_section && index($0, prefix) == 1 {
      target = $0
      sub(/^.*PROJECT\.md#/, "", target)
      sub(/`$/, "", target)
      if (target ~ /^(PC-(0[1-9]|[1-9][0-9])|status)$/) print target
    }
  ' "$1"
}

section_contains() {
  awk -v heading="$2" -v value="$3" '
    $0 == heading { in_section = 1; next }
    in_section && /^## / { exit }
    in_section && index($0, value) > 0 { found = 1 }
    END { exit !found }
  ' "$1"
}

required_reference_count() {
  local file="$1"
  local section="$2"
  awk -v section="$section" '
    /^## / { in_section = ($0 == section); in_required = 0; next }
    in_section && /^### / { in_required = ($0 == "### Required"); next }
    in_section && in_required && /^- / && $0 != "- なし" { count++ }
    END { print count + 0 }
  ' "$file"
}

required_references() {
  awk '
    /^## / {
      in_reference_section = ($0 == "## 使用するKnowledge" || $0 == "## 使用するSkill")
      in_required = 0
      next
    }
    in_reference_section && /^### / {
      in_required = ($0 == "### Required")
      next
    }
    in_reference_section && in_required && /^- `/ {
      value = $0
      sub(/^- `/, "", value)
      sub(/`.*$/, "", value)
      print value
    }
  ' "$1"
}

scope_root_for() {
  local file="$1"
  local rel remainder fixture_name
  rel="$(relative_path "$file")"
  case "$rel" in
    evals/fixtures/*)
      remainder="${rel#evals/fixtures/}"
      fixture_name="${remainder%%/*}"
      printf '%s' "$repo_root/evals/fixtures/$fixture_name"
      ;;
    *) printf '%s' "$repo_root" ;;
  esac
}

validate_declared_references() {
  local file="$1"
  local scope_root reference
  case "$(relative_path "$file")" in
    */_template/*) return 0 ;;
  esac
  scope_root="$(scope_root_for "$file")"
  while IFS= read -r reference; do
    [[ -n "$reference" ]] || continue
    reference="${reference%%#*}"
    if [[ ! -e "$scope_root/$reference" ]]; then
      fail "$(relative_path "$file") references missing path: $reference"
    fi
  done < <(grep -Eo '`(knowledge|skills)/[^`]+`' "$file" 2>/dev/null | tr -d '`' | LC_ALL=C sort -u || true)
}

validate_required_reference_statuses() {
  local file="$1"
  local scope_root reference reference_status
  scope_root="$(scope_root_for "$file")"
  while IFS= read -r reference; do
    [[ -n "$reference" && -f "$scope_root/$reference" ]] || continue
    reference_status="$(frontmatter_value "$scope_root/$reference" 'status')"
    case "$reference" in
      knowledge/*)
        [[ "$reference_status" == 'active' ]] || \
          fail "$(relative_path "$file") Required Knowledge is not active: $reference"
        ;;
      skills/*)
        [[ "$reference_status" == 'active' ]] || \
          fail "$(relative_path "$file") Required Skill is not active: $reference"
        ;;
    esac
  done < <(required_references "$file")
}

check_size_warning() {
  local file="$1"
  local warning_limit="$2"
  local label="$3"
  local bytes
  [[ -f "$file" ]] || return 0
  bytes="$(wc -c < "$file" | tr -d ' ')"
  if (( bytes > warning_limit )); then
    warn "$(relative_path "$file") exceeds the $label soft budget: ${bytes}B > ${warning_limit}B"
  fi
}

# CLAUDE.mdは@AGENTS.mdだけを持つブリッジであり、独自規則を所有してはならない。
validate_claude_bridge() {
  local agents_file="$1"
  local claude_file="${agents_file%/AGENTS.md}/CLAUDE.md"
  if [[ ! -f "$claude_file" ]]; then
    fail "$(relative_path "$agents_file") requires a sibling CLAUDE.md importing @AGENTS.md"
    return 0
  fi
  if ! printf '@AGENTS.md\n' | cmp -s - "$claude_file"; then
    fail "$(relative_path "$claude_file") must contain only @AGENTS.md and own no rules"
  fi
}

# Project差分ファイルは成果契約と現在状態を所有してはならない。
validate_project_agents_file() {
  local agents_file="$1"
  local project_dir repository_mode forbidden
  local forbidden_headings=(
    '## 目的' '## 最終ゴール' '## 完了条件' '## 継続的使命' '## 成功指標' '## 見直し・終了条件'
    '## 現在の到達点' '## 現在の目標' '## 目標の合格条件' '## 検証結果' '## 現在有効な決定'
    '## 未完了・ブロッカー' '## 失敗・却下済み' '## 次の一手' '## 使用するKnowledge' '## 使用するSkill'
  )

  [[ -f "$agents_file" ]] || return 0
  project_dir="$(dirname "$agents_file")"
  check_size "$agents_file" 2048 'Project AGENTS.md'

  repository_mode="$(frontmatter_value "$project_dir/PROJECT.md" 'repository_mode')"
  if [[ "$repository_mode" == 'independent' ]]; then
    fail "$(relative_path "$agents_file") is forbidden in an Independent Project envelope; projects/<name>/repository/ owns it"
  fi
  if [[ "$project_dir" == "$repo_root/projects/_template" ]]; then
    fail 'projects/_template must not carry AGENTS.md; per-Project差分は自動複製しない'
  fi

  for forbidden in "${forbidden_headings[@]}"; do
    if grep -Fqx -- "$forbidden" "$agents_file"; then
      fail "$(relative_path "$agents_file") must not own the contract or state heading: $forbidden"
    fi
  done
  if grep -Eq '^- \*\*PC-' "$agents_file"; then
    fail "$(relative_path "$agents_file") must not restate Project Criterion bullets"
  fi
  grep -Fq 'PROJECT.md' "$agents_file" || \
    fail "$(relative_path "$agents_file") must name PROJECT.md as the contract canon"
  grep -Fq 'STATE.md' "$agents_file" || \
    fail "$(relative_path "$agents_file") must name STATE.md as the state canon"
  if awk '
      index($0, "docs/**") == 0 { next }
      /しない|禁止|避ける|must not|do not|never/ { next }
      { found = 1 }
      END { exit !found }
    ' "$agents_file"; then
    fail "$(relative_path "$agents_file") must not order a bulk docs/** read; list one condition per Domain Canon instead"
  fi

  validate_claude_bridge "$agents_file"
}

# Project Docs Routeの節から、条件付き参照として成立している読込先だけを抜き出す。
# 本文・禁止文・単なる一覧への登場は条件付き参照として数えない。
docs_route_targets() {
  awk '
    function trim(value) { gsub(/^[ \t]+|[ \t]+$/, "", value); return value }
    $0 == "## Project Docs Route" { in_section = 1; next }
    in_section && /^## / { exit }
    !in_section { next }
    /読まない|読み込まない|参照しない|禁止/ { next }
    /^\|/ {
      row = $0
      sub(/^\|/, "", row)
      sub(/\|[ \t]*$/, "", row)
      count = split(row, cell, "|")
      if (count < 2) next
      condition = trim(cell[1])
      target = trim(cell[count])
      if (condition == "" || target == "") next
      if (condition ~ /^:?-+:?$/ || target ~ /^:?-+:?$/) next
      if (condition == "条件") next
      print target
      next
    }
    /^[ \t]*参照:/ {
      value = $0
      sub(/^[ \t]*参照:[ \t]*/, "", value)
      print trim(value)
    }
  ' "$1"
}

# Project docsは大文字Domain Canonを入口とし、下位のフォルダ構造はProjectが決める。
validate_project_docs() {
  local project_dir="$1"
  local project_file="$project_dir/PROJECT.md"
  local agents_file="$project_dir/AGENTS.md"
  local docs_dir="$project_dir/docs"
  local architecture_file="$project_dir/ARCHITECTURE.md"
  local rel_project canon canon_name catch_all detail_dir detail_name
  local has_docs='false' canon_count=0 route_targets=''
  local canon_files=()

  [[ -f "$project_file" ]] || return 0
  [[ "$(frontmatter_value "$project_file" 'repository_mode')" == 'embedded' ]] || return 0
  rel_project="$(relative_path "$project_dir")"

  if [[ -d "$docs_dir" ]]; then
    has_docs='true'
    while IFS= read -r -d '' canon; do
      canon_name="${canon##*/}"
      if [[ ! "$canon_name" =~ ^[A-Z][A-Z0-9]*(_[A-Z0-9]+)*\.md$ ]]; then
        fail "$(relative_path "$canon") is not a Domain Canon; rename it to ^[A-Z][A-Z0-9]*(_[A-Z0-9]+)*\.md\$ (e.g. DESIGN.md, PRODUCT_SENSE.md) or move it into a lowercase detail folder"
        continue
      fi
      case "$canon_name" in
        NOTES.md|MISC.md|OTHER.md|DOCS.md|SENSE.md|SCORE.md)
          fail "$(relative_path "$canon") is too generic to own a canon; name the domain it covers (e.g. DESIGN.md, PRODUCT_SENSE.md, QUALITY_SCORE.md)"
          continue
          ;;
      esac
      canon_files+=("$canon")
      canon_count=$((canon_count + 1))
      check_size "$canon" 24576 'Domain Canon'
    done < <(find "$docs_dir" -mindepth 1 -maxdepth 1 -type f -name '*.md' -print0)

    if (( canon_count == 0 )); then
      fail "$rel_project/docs/ has no Domain Canon entry; add at least one uppercase docs/<DOMAIN>.md (e.g. docs/DESIGN.md) or remove the folder — detail documents must be reached through a canon"
    fi

    while IFS= read -r -d '' catch_all; do
      fail "$(relative_path "$catch_all") is a catch-all docs folder; give it a responsibility-bearing lowercase kebab-case name"
    done < <(find "$docs_dir" -mindepth 1 -maxdepth 1 -type d \
      \( -name misc -o -name other -o -name notes -o -name tmp \) -print0)

    # docs/直下の各詳細フォルダは、少なくとも一つのDomain Canonから案内される。
    if (( canon_count > 0 )); then
      while IFS= read -r -d '' detail_dir; do
        detail_name="${detail_dir##*/}"
        case "$detail_name" in misc|other|notes|tmp) continue ;; esac
        grep -Fq -- "$detail_name/" "${canon_files[@]}" || \
          fail "$(relative_path "$detail_dir") is not referenced by any Domain Canon; name it from the docs/<DOMAIN>.md that owns it (references/ and generated/ need an owning canon too)"
      done < <(find "$docs_dir" -mindepth 1 -maxdepth 1 -type d -print0)
    fi
  fi

  [[ ! -f "$architecture_file" ]] || check_size "$architecture_file" 24576 'ARCHITECTURE.md'

  if [[ "$has_docs" == 'true' || -f "$architecture_file" ]]; then
    if [[ ! -f "$agents_file" ]]; then
      fail "$rel_project has docs/ or ARCHITECTURE.md and therefore requires $rel_project/AGENTS.md carrying the conditional Project Docs Route (and a sibling CLAUDE.md containing only @AGENTS.md)"
      return 0
    fi
    if ! grep -Fqx '## Project Docs Route' "$agents_file"; then
      fail "$(relative_path "$agents_file") must carry the exact heading '## Project Docs Route' listing one condition per canon"
      return 0
    fi
    route_targets="$(docs_route_targets "$agents_file")"
    if [[ -f "$architecture_file" ]] && ! printf '%s\n' "$route_targets" | grep -Fq 'ARCHITECTURE.md'; then
      fail "$(relative_path "$agents_file") must route to ARCHITECTURE.md from a '## Project Docs Route' entry (a '| 条件 | \`ARCHITECTURE.md\` |' table row, or a 条件:/参照: pair); naming it elsewhere in the file does not count"
    fi
    # bash 3.2では空配列の展開が set -u で落ちるため、件数で守る。
    if (( canon_count > 0 )); then
      for canon in "${canon_files[@]}"; do
        canon_name="${canon##*/}"
        printf '%s\n' "$route_targets" | grep -Fq "docs/$canon_name" || \
          fail "$(relative_path "$agents_file") must route to docs/$canon_name from a '## Project Docs Route' entry (a '| 条件 | \`docs/$canon_name\` |' table row, or a 条件:/参照: pair); naming it elsewhere in the file does not count"
      done
    fi
  fi
}

# Independentの固定pathは普通のcloneであり、`.git`は実directoryでなければならない。
# evals/fixtures配下の静的fixtureは宣言と状態だけを持ち、実cloneを要求しない。
# 実Gitの挙動はvalidator内のintegration fixtureが所有する。
validate_independent_attachment() {
  local project_file="$1"
  local repository_url="$2"
  local project_dir rel_project target child_top child_origin
  project_dir="$(dirname "$project_file")"
  case "$project_dir" in
    "$repo_root"/projects/*) ;;
    *) return 0 ;;
  esac
  rel_project="$(relative_path "$project_dir")"
  target="$project_dir/repository"

  if [[ -L "$project_dir" || -L "$target" ]]; then
    fail "$rel_project/repository must be a real directory, not a symlink"
    return 0
  fi
  if [[ ! -d "$target" ]]; then
    fail "$rel_project declares repository_mode: independent but $rel_project/repository/ is missing; run bash tools/materialize-project-repositories.sh --project ${rel_project##*/}"
    return 0
  fi
  if [[ -L "$target/.git" ]]; then
    fail "$rel_project/repository/.git must be a real directory, not a symlink"
    return 0
  fi
  if [[ -e "$target/.git" && ! -d "$target/.git" ]]; then
    fail "$rel_project/repository/.git must be a real directory; .git files, worktrees and submodules are unsupported"
    return 0
  fi
  if [[ ! -d "$target/.git" ]]; then
    fail "$rel_project/repository must be a normal git clone carrying its own .git directory"
    return 0
  fi
  command -v git >/dev/null 2>&1 || return 0
  if ! child_top="$(git -C "$target" rev-parse --show-toplevel 2>/dev/null)"; then
    fail "$rel_project/repository does not resolve to a Git working tree"
    return 0
  fi
  child_top="$(cd "$child_top" && pwd -P)"
  [[ "$child_top" == "$(cd "$target" && pwd -P)" ]] || \
    fail "$rel_project/repository toplevel must be the fixed path itself, but Git reports $child_top"
  child_origin="$(git -C "$target" config --get remote.origin.url 2>/dev/null || true)"
  [[ "$child_origin" == "$repository_url" ]] || \
    fail "$rel_project/repository remote.origin.url is ${child_origin:-<unset>}, expected $repository_url"
}

validate_project_contract() {
  local project_file="$1"
  local criterion_heading mode name status description project_dir knowledge_required skill_required
  local repository_mode repository_url repository_reason repository_default_branch unexpected_entry
  local headings=(
    '## 目的' '## 判断原則' '## 非ゴール' '## 制約・固定決定' '## 品質基準'
    '## 入力' '## 使用するKnowledge' '## 使用するSkill' '## 成果物' '## 検証方法'
  )

  require_file "$project_file"
  [[ -f "$project_file" ]] || return
  check_size "$project_file" 20480 'PROJECT.md'

  if ! has_closed_frontmatter "$project_file"; then
    fail "$(relative_path "$project_file") has invalid YAML frontmatter boundaries"
  fi

  name="$(frontmatter_value "$project_file" 'name')"
  description="$(frontmatter_value "$project_file" 'description')"
  status="$(frontmatter_value "$project_file" 'status')"
  mode="$(frontmatter_value "$project_file" 'mode')"
  repository_mode="$(frontmatter_value "$project_file" 'repository_mode')"
  repository_url="$(frontmatter_value "$project_file" 'repository_url')"
  repository_reason="$(frontmatter_value "$project_file" 'repository_reason')"
  repository_default_branch="$(frontmatter_value "$project_file" 'repository_default_branch')"
  project_dir="$(basename "$(dirname "$project_file")")"

  [[ -n "$name" ]] || fail "$(relative_path "$project_file") has a missing name"
  [[ -n "$description" ]] || fail "$(relative_path "$project_file") has a missing description"
  if [[ "$project_file" != "$repo_root/projects/_template/PROJECT.md" && "$name" != "$project_dir" ]]; then
    fail "$(relative_path "$project_file") name must match directory: $project_dir"
  fi
  if [[ "$description" == *$'\t'* || "$description" == *$'\n'* || $(value_character_count "$description") -gt 200 ]]; then
    fail "$(relative_path "$project_file") description must be one line, tab-free, and at most 200 characters"
  fi
  case "$status" in active|paused|completed|retired) ;; *) fail "$(relative_path "$project_file") has an invalid status" ;; esac
  case "$mode" in finite|continuous) ;; *) fail "$(relative_path "$project_file") has an invalid mode" ;; esac
  [[ "$(frontmatter_key_count "$project_file" 'repository_mode')" == '1' ]] || \
    fail "$(relative_path "$project_file") must declare repository_mode exactly once"
  case "$repository_mode" in
    embedded)
      if [[ -n "$repository_url$repository_reason$repository_default_branch" ]] || \
        (( $(frontmatter_key_count "$project_file" 'repository_url') + \
           $(frontmatter_key_count "$project_file" 'repository_reason') + \
           $(frontmatter_key_count "$project_file" 'repository_default_branch') > 0 )); then
        fail "$(relative_path "$project_file") embedded Project must not declare Independent repository fields"
      fi
      [[ ! -e "$(dirname "$project_file")/repository" ]] || \
        fail "$(relative_path "$project_file") is embedded but holds a repository/ directory; promote it or remove the clone"
      ;;
    independent)
      for repository_key in repository_url repository_reason repository_default_branch; do
        [[ "$(frontmatter_key_count "$project_file" "$repository_key")" == '1' ]] || \
          fail "$(relative_path "$project_file") must declare $repository_key exactly once for Independent mode"
      done
      if [[ -z "$repository_url" || "$repository_url" =~ [[:space:]\`] || \
            "$repository_url" =~ ^https?://[^/@]+@ ]]; then
        fail "$(relative_path "$project_file") Independent repository_url must be a non-empty, whitespace-free Git URL"
      fi
      case "$repository_reason" in
        automation|distribution|collaboration|access|identity|upstream|retention) ;;
        *) fail "$(relative_path "$project_file") has an invalid repository_reason" ;;
      esac
      if [[ ! "$repository_default_branch" =~ ^[A-Za-z0-9][A-Za-z0-9._/-]*$ ]]; then
        fail "$(relative_path "$project_file") has an invalid repository_default_branch"
      fi
      # root側envelopeが持ってよいのは契約、状態、固定pathのcloneだけである。
      while IFS= read -r unexpected_entry; do
        [[ -n "$unexpected_entry" ]] || continue
        fail "$(relative_path "$project_file") Independent Project envelope may contain only PROJECT.md, STATE.md and repository/: $unexpected_entry"
      done < <(find "$(dirname "$project_file")" -mindepth 1 -maxdepth 1 \
        ! -name PROJECT.md ! -name STATE.md ! -name repository -print 2>/dev/null)
      validate_independent_attachment "$project_file" "$repository_url"
      ;;
    satellite)
      fail "$(relative_path "$project_file") uses the retired satellite mode; migrate it to repository_mode: independent (deprecated-satellite-mode)"
      ;;
    *) fail "$(relative_path "$project_file") has an invalid repository_mode" ;;
  esac

  if ! grep -Eq '^> .+' "$project_file"; then
    fail "$(relative_path "$project_file") is missing a one-line goal or mission"
  fi
  for heading in "${headings[@]}"; do require_fixed_line "$project_file" "$heading"; done

  case "$mode" in
    finite)
      criterion_heading='## 完了条件'
      require_fixed_line "$project_file" '## 最終ゴール'
      require_fixed_line "$project_file" '## 完了条件'
      if grep -Eq '^## (継続的使命|成功指標|見直し・終了条件)$' "$project_file"; then
        fail "$(relative_path "$project_file") mixes finite and continuous contracts"
      fi
      ;;
    continuous)
      criterion_heading='## 成功指標'
      require_fixed_line "$project_file" '## 継続的使命'
      require_fixed_line "$project_file" '## 成功指標'
      require_fixed_line "$project_file" '## 見直し・終了条件'
      if grep -Eq '^## (最終ゴール|完了条件)$' "$project_file"; then
        fail "$(relative_path "$project_file") mixes finite and continuous contracts"
      fi
      [[ "$status" != 'completed' ]] || fail "$(relative_path "$project_file") cannot complete a continuous Project"
      ;;
  esac

  if ! has_valid_project_criteria "$project_file" "$criterion_heading"; then
    fail "$(relative_path "$project_file") must use unique PC-xx bullets only in $criterion_heading"
  fi

  require_fixed_line "$project_file" '### Required'
  require_fixed_line "$project_file" '### Conditional'
  knowledge_required="$(required_reference_count "$project_file" '## 使用するKnowledge')"
  skill_required="$(required_reference_count "$project_file" '## 使用するSkill')"
  if (( knowledge_required + skill_required > 6 )); then
    fail "$(relative_path "$project_file") has more than 6 combined Required Knowledge and Skill references"
  fi

  if grep -Eq '外部リポジトリ:|作業clone:' "$project_file"; then
    fail "$(relative_path "$project_file") uses the retired prose repository declaration; use repository_mode frontmatter"
  fi

  validate_declared_references "$project_file"
  validate_required_reference_statuses "$project_file"
  if [[ "$project_file" != "$repo_root/projects/_template/PROJECT.md" ]] && contains_template_placeholder "$project_file"; then
    fail "$(relative_path "$project_file") contains an unresolved placeholder"
  fi
}

validate_project_state() {
  local state_file="$1"
  local contract_targets verification_targets project_file target updated_at project_status project_mode criterion
  local repository_mode state_revision repository_state_key
  local headings=(
    '## 現在の到達点' '## 現在の目標' '## 目標の合格条件' '## 検証結果'
    '## 未完了・ブロッカー' '## 現在有効な決定' '## 失敗・却下済み' '## 次の一手'
  )

  require_file "$state_file"
  [[ -f "$state_file" ]] || return
  check_size "$state_file" 8192 'STATE.md'

  if ! has_closed_frontmatter "$state_file"; then
    fail "$(relative_path "$state_file") has invalid YAML frontmatter boundaries"
  fi
  updated_at="$(frontmatter_value "$state_file" 'updated_at')"
  if [[ "$state_file" == "$repo_root/projects/_template/STATE.md" ]]; then
    [[ "$updated_at" == '<YYYY-MM-DD>' ]] || fail "$(relative_path "$state_file") has an invalid updated_at placeholder"
  elif [[ ! "$updated_at" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
    fail "$(relative_path "$state_file") has a missing or invalid updated_at"
  fi
  for heading in "${headings[@]}"; do require_fixed_line "$state_file" "$heading"; done

  project_file="$(dirname "$state_file")/PROJECT.md"
  project_status="$(frontmatter_value "$project_file" 'status')"
  project_mode="$(frontmatter_value "$project_file" 'mode')"
  repository_mode="$(frontmatter_value "$project_file" 'repository_mode')"
  contract_targets="$(state_section_targets "$state_file" '## 現在の目標' '対象契約: `PROJECT.md#')"
  if [[ -z "$contract_targets" || "$(printf '%s\n' "$contract_targets" | wc -l | tr -d ' ')" != '1' ]]; then
    fail "$(relative_path "$state_file") must name one current PROJECT.md#PC-xx or #status target"
  fi
  verification_targets="$(state_section_targets "$state_file" '## 検証結果' '- 対象: `PROJECT.md#')"
  [[ -n "$verification_targets" ]] || fail "$(relative_path "$state_file") verification results must reference PROJECT.md#PC-xx or #status"

  for target in $contract_targets $verification_targets; do
    case "$target" in
      status) ;;
      PC-*)
        if [[ -f "$project_file" ]] && ! grep -Fq -- "**$target**" "$project_file"; then
          fail "$(relative_path "$state_file") references missing PROJECT.md#$target"
        fi
        ;;
    esac
  done
  if [[ "$project_status" == 'completed' ]]; then
    [[ "$project_mode" == 'finite' ]] || fail "$(relative_path "$state_file") completed Project must use mode: finite"
    [[ "$contract_targets" == 'status' ]] || \
      fail "$(relative_path "$state_file") completed Project current target must be PROJECT.md#status"
    section_contains "$state_file" '## 現在の目標' 'なし（Project完了）' || \
      fail "$(relative_path "$state_file") completed Project must close the current goal"
    section_contains "$state_file" '## 次の一手' 'なし（Project完了）' || \
      fail "$(relative_path "$state_file") completed Project must close the next action"
    while IFS= read -r criterion; do
      [[ -n "$criterion" ]] || continue
      if ! printf '%s\n' "$verification_targets" | grep -Fqx "$criterion"; then
        fail "$(relative_path "$state_file") completed Project lacks verification evidence for PROJECT.md#$criterion"
      fi
    done < <(grep -Eo '\*\*PC-(0[1-9]|[1-9][0-9])\*\*' "$project_file" | tr -d '*' | LC_ALL=C sort -u)
  fi
  case "$repository_mode" in
    embedded)
      if grep -Fqx '## Repository State' "$state_file"; then
        fail "$(relative_path "$state_file") embedded Project must not declare Repository State"
      fi
      ;;
    independent)
      # Repository Stateは採用revisionだけを持つ。remote URLとbranchはPROJECT.mdが所有する。
      require_fixed_line "$state_file" '## Repository State'
      state_revision="$(repository_state_value "$state_file" 'revision')"
      [[ "$(repository_state_key_count "$state_file" 'revision')" == '1' ]] || \
        fail "$(relative_path "$state_file") must declare Repository State revision exactly once"
      for repository_state_key in repository branch remote_verified_at; do
        [[ "$(repository_state_key_count "$state_file" "$repository_state_key")" == '0' ]] || \
          fail "$(relative_path "$state_file") Repository State must hold only revision; remove the retired $repository_state_key field"
      done
      [[ "$state_revision" =~ ^[0-9a-f]{40}$ ]] || \
        fail "$(relative_path "$state_file") Repository State revision must be a 40-character lowercase commit SHA"
      ;;
  esac
  if [[ "$state_file" != "$repo_root/projects/_template/STATE.md" ]] && contains_template_placeholder "$state_file"; then
    fail "$(relative_path "$state_file") contains an unresolved placeholder"
  fi
}

validate_skill() {
  local skill_file="$1"
  local name description status directory aliases replaced_by required_count scope_root
  [[ -f "$skill_file" ]] || return
  check_size "$skill_file" 20480 'SKILL.md'
  has_closed_frontmatter "$skill_file" || fail "$(relative_path "$skill_file") has invalid YAML frontmatter"
  name="$(frontmatter_value "$skill_file" 'name')"
  description="$(frontmatter_value "$skill_file" 'description')"
  status="$(frontmatter_value "$skill_file" 'status')"
  aliases="$(frontmatter_value "$skill_file" 'aliases')"
  replaced_by="$(frontmatter_value "$skill_file" 'replaced_by')"
  directory="$(basename "$(dirname "$skill_file")")"

  [[ -n "$name" ]] || fail "$(relative_path "$skill_file") has a missing name"
  [[ -n "$description" ]] || fail "$(relative_path "$skill_file") has a missing description"
  [[ -n "$aliases" ]] || fail "$(relative_path "$skill_file") has missing aliases"
  if [[ "$skill_file" != "$repo_root/skills/_template/SKILL.md" && "$name" != "$directory" ]]; then
    fail "$(relative_path "$skill_file") name must match directory: $directory"
  fi
  case "$status" in active|deprecated|retired) ;; *) fail "$(relative_path "$skill_file") has an invalid status" ;; esac
  if [[ "$status" == 'deprecated' ]]; then
    [[ -n "$replaced_by" ]] || fail "$(relative_path "$skill_file") deprecated Skill requires replaced_by"
    scope_root="$(scope_root_for "$skill_file")"
    if [[ ! -f "$scope_root/$replaced_by" ]]; then
      fail "$(relative_path "$skill_file") replaced_by target is missing: $replaced_by"
    elif [[ "$scope_root/$replaced_by" == "$skill_file" ]]; then
      fail "$(relative_path "$skill_file") must not replace itself"
    elif [[ "$(frontmatter_value "$scope_root/$replaced_by" 'status')" != 'active' ]]; then
      fail "$(relative_path "$skill_file") replaced_by target must be active: $replaced_by"
    fi
  fi
  require_fixed_line "$skill_file" '## 使用するKnowledge'
  require_fixed_line "$skill_file" '### Required'
  require_fixed_line "$skill_file" '### Conditional'
  required_count="$(required_reference_count "$skill_file" '## 使用するKnowledge')"
  (( required_count <= 3 )) || fail "$(relative_path "$skill_file") has more than 3 Required Knowledge references"
  validate_declared_references "$skill_file"
  validate_required_reference_statuses "$skill_file"
}

validate_knowledge_page() {
  local page="$1"
  local summary status aliases superseded_by review_after bytes target_status scope_root filename
  [[ -f "$page" ]] || return
  has_closed_frontmatter "$page" || fail "$(relative_path "$page") has invalid YAML frontmatter"
  summary="$(frontmatter_value "$page" 'summary')"
  status="$(frontmatter_value "$page" 'status')"
  aliases="$(frontmatter_value "$page" 'aliases')"
  superseded_by="$(frontmatter_value "$page" 'superseded_by')"
  review_after="$(frontmatter_value "$page" 'review_after')"
  filename="${page##*/}"

  [[ -n "$summary" ]] || fail "$(relative_path "$page") has a missing summary"
  [[ -n "$aliases" ]] || fail "$(relative_path "$page") has missing aliases"
  if [[ "$summary" == *$'\t'* || $(value_character_count "$summary") -gt 200 ]]; then
    fail "$(relative_path "$page") summary must be tab-free and at most 200 characters"
  fi
  [[ "$aliases" != *$'\t'* ]] || fail "$(relative_path "$page") aliases must not contain tabs"
  case "$status" in active|superseded|archived|retired) ;; *) fail "$(relative_path "$page") has an invalid status" ;; esac
  if [[ "$status" == 'superseded' ]]; then
    [[ -n "$superseded_by" ]] || fail "$(relative_path "$page") superseded Knowledge requires superseded_by"
    scope_root="$(scope_root_for "$page")"
    if [[ "$superseded_by" == "$(relative_path "$page")" ]]; then
      fail "$(relative_path "$page") must not supersede itself"
    elif [[ ! -f "$scope_root/$superseded_by" ]]; then
      fail "$(relative_path "$page") superseded_by target is missing: $superseded_by"
    else
      target_status="$(frontmatter_value "$scope_root/$superseded_by" 'status')"
      [[ "$target_status" == 'active' ]] || fail "$(relative_path "$page") superseded_by target must be active"
    fi
  elif [[ -n "$superseded_by" ]]; then
    fail "$(relative_path "$page") may use superseded_by only with status: superseded"
  fi
  if [[ -n "$review_after" && ! "$review_after" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
    fail "$(relative_path "$page") has invalid review_after"
  fi
  bytes="$(wc -c < "$page" | tr -d ' ')"
  if (( bytes > 65536 )); then
    fail "$(relative_path "$page") exceeds 64KiB Wiki hard limit"
  elif [[ "$status" == 'active' && $bytes -gt 24576 ]] && ! grep -Fqx '## Retrieval Map' "$page"; then
    fail "$(relative_path "$page") exceeds 24KiB and requires ## Retrieval Map"
  fi
  # 大文字名を許すのはテンプレート固定ファイルの2パスだけで、利用者Knowledgeへは広げない。
  case "$(relative_path "$page")" in
    "$knowledge_source_template_path"|"$knowledge_topic_template_path") ;;
    *)
      case "$filename" in
        *[!a-z0-9.-]*|_*|*[A-Z]*) fail "$(relative_path "$page") filename must use lowercase kebab-case" ;;
      esac
      ;;
  esac
  validate_declared_references "$page"
}

validate_deleted_project() {
  local base="$1"
  local project_file="$2"
  local project_dir contract_copy status deletion_approved artifacts_retained_at output_files inbound_refs
  project_dir="${project_file%/PROJECT.md}"

  case "$project_dir" in
    projects/_template|projects/_archive)
      fail "protected Project structure must not be deleted: $project_dir"
      return
      ;;
  esac

  contract_copy="$(mktemp "$cache_test_dir/deleted-project.XXXXXX")"
  if ! git -C "$repo_root" show "$base:$project_file" > "$contract_copy" 2>/dev/null; then
    fail "cannot inspect deleted Project contract at $base:$project_file"
    return
  fi
  status="$(frontmatter_value "$contract_copy" 'status')"
  deletion_approved="$(frontmatter_value "$contract_copy" 'deletion_approved')"
  artifacts_retained_at="$(frontmatter_value "$contract_copy" 'artifacts_retained_at')"

  [[ "$status" == 'retired' ]] || fail "deleted Project was not retired in $base: $project_dir"
  [[ "$deletion_approved" == 'true' ]] || \
    fail "deleted Project lacks deletion_approved: true in $base: $project_dir"
  if [[ -z "$artifacts_retained_at" ]]; then
    fail "deleted Project lacks artifacts_retained_at in $base: $project_dir"
  elif [[ "$artifacts_retained_at" == 'none' ]]; then
    output_files="$(git -C "$repo_root" ls-tree -r --name-only "$base" -- "$project_dir/outputs" || true)"
    [[ -z "$output_files" ]] || \
      fail "deleted Project declares artifacts_retained_at: none but had tracked outputs: $project_dir"
  else
    case "$artifacts_retained_at" in
      /*|../*|*/../*|"$project_dir"/*)
        fail "deleted Project artifacts_retained_at must be a surviving repository-relative path: $artifacts_retained_at"
        ;;
      *)
        [[ -e "$repo_root/$artifacts_retained_at" ]] || \
          fail "deleted Project artifact retention target is missing: $artifacts_retained_at"
        if ! git -C "$repo_root" ls-files --error-unmatch -- "$artifacts_retained_at" >/dev/null 2>&1; then
          fail "deleted Project artifact retention target is not tracked or staged: $artifacts_retained_at"
        fi
        ;;
    esac
  fi

  [[ ! -e "$repo_root/$project_dir" ]] || fail "Project deletion left files behind: $project_dir"
  if command -v rg >/dev/null 2>&1; then
    inbound_refs="$(rg -l -F --hidden --glob '!.git/**' --glob '!.agent-cache/**' --glob '!.tmp/**' \
      --glob '!projects/*/repository/**' "$project_dir/" "$repo_root" 2>/dev/null || true)"
  else
    inbound_refs="$(grep -RIlF --exclude-dir=.git --exclude-dir=.agent-cache --exclude-dir=.tmp \
      --exclude-dir=repository "$project_dir/" "$repo_root" 2>/dev/null || true)"
  fi
  [[ -z "$inbound_refs" ]] || fail "deleted Project still has inbound reference(s): $project_dir"
}

# 宣言済みIndependent repositoryの本体はroot validatorの走査対象外である。directoryごとpruneし、
# 許可された `projects/<name>/repository/.git/` 以外のnested Gitは停止させる。
# 配列は set -u 下でも安全なよう、既存pruneと重複する無害な項目で常に非空にする。
repository_prune=( -path "$repo_root/.git" )
repository_prune_or=( -o -path "$repo_root/.git" )
for declared_contract in "$repo_root"/projects/*/PROJECT.md; do
  [[ -f "$declared_contract" ]] || continue
  [[ "$(frontmatter_value "$declared_contract" 'repository_mode')" == 'independent' ]] || continue
  declared_repository="$(dirname "$declared_contract")/repository"
  [[ -d "$declared_repository" ]] || continue
  repository_prune+=( -o -path "$declared_repository" )
  repository_prune_or+=( -o -path "$declared_repository" )
done

required_files=(
  'AGENTS.md' 'CLAUDE.md' 'projects/AGENTS.md' 'projects/CLAUDE.md'
  'README.md' 'knowledge/KNOWLEDGE.md' "$knowledge_index_path" "$knowledge_log_path"
  'skills/SKILLS.md' 'skills/_template/SKILL.md' 'projects/PROJECTS.md' 'projects/LIFECYCLE.md' 'projects/RECOVERY.md'
  'projects/_template/PROJECT.md' 'projects/_template/STATE.md' 'evals/EVALS.md' 'tools/TOOLS.md'
  'tools/BACKUP.md' 'tools/build-context-cache.sh' 'tools/find-context.sh' 'tools/append-knowledge-log.sh'
  'tools/backup-to-github.sh' 'tools/validate-agent-directory.sh'
  'tools/materialize-project-repositories.sh' '.gitignore'
  "$knowledge_source_template_path" "$knowledge_topic_template_path"
)
for path in "${required_files[@]}"; do require_file "$repo_root/$path"; done

# 不変原資料は internal/external の二領域だけを持ち、どちらも同じ強さで保護する。
required_directories=(
  'knowledge/raw/internal' 'knowledge/raw/external' 'knowledge/wiki/sources' 'knowledge/wiki/topics'
)
for path in "${required_directories[@]}"; do
  [[ -d "$repo_root/$path" ]] || \
    fail "missing directory: $path (create it and keep it tracked, e.g. touch $path/.gitkeep)"
done

# 旧構造・旧入口は互換コピーを残さず廃止する。
retired_paths=(
  'knowledge/research|外部原資料は knowledge/raw/external/ が所有する'
  'skills/README.md|領域正本は skills/SKILLS.md である'
  'projects/README.md|領域正本は projects/PROJECTS.md である'
  'evals/README.md|領域正本は evals/EVALS.md である'
  'tools/README.md|領域正本は tools/TOOLS.md である'
)
for entry in "${retired_paths[@]}"; do
  retired_path="${entry%%|*}"
  retired_hint="${entry#*|}"
  [[ ! -e "$repo_root/$retired_path" ]] || \
    fail "retired path must not exist: $retired_path — $retired_hint (git rm it; do not keep a compatibility copy)"
done

# 固定Wiki Markdownは大文字名だけを正本とする。case-insensitive filesystemでは -e が
# 大文字の正本にも一致するため、Git indexと実ディレクトリエントリの完全一致だけで旧caseを検出する。
tracked_files_snapshot=''
if git -C "$repo_root" rev-parse --show-toplevel >/dev/null 2>&1; then
  tracked_files_snapshot="$(git -C "$repo_root" ls-files 2>/dev/null || true)"
fi
for entry in \
  "knowledge/wiki/index.md|$knowledge_index_path" \
  "knowledge/wiki/log.md|$knowledge_log_path" \
  "knowledge/wiki/_template/source.md|$knowledge_source_template_path" \
  "knowledge/wiki/_template/topic.md|$knowledge_topic_template_path"; do
  retired_path="${entry%%|*}"
  canonical_path="${entry#*|}"
  if [[ -n "$tracked_files_snapshot" ]] && \
    printf '%s\n' "$tracked_files_snapshot" | grep -Fqx -- "$retired_path"; then
    fail "retired lowercase Knowledge path is tracked in the Git index: $retired_path — the canonical name is $canonical_path"
  fi
  # readdirは実際に保存された名前を返すため、findの -name は case-exact に働く。
  if [[ -d "$repo_root/${retired_path%/*}" ]] && \
    [[ -n "$(find "$repo_root/${retired_path%/*}" -maxdepth 1 -type f -name "${retired_path##*/}" -print -quit)" ]]; then
    fail "retired lowercase Knowledge file exists on disk: $retired_path — the canonical name is $canonical_path"
  fi
done

# Project docsは大文字Domain Canonから入る。外部原資料とinputsの命名は対象外とする。
while IFS= read -r -d '' docs_readme; do
  fail "$(relative_path "$docs_readme") is forbidden; enter docs/ through an uppercase Domain Canon such as docs/DESIGN.md"
done < <(find "$repo_root" \
  \( -type d \( -name '.git' -o -name '.agent-cache' -o -name '.tmp' -o -name 'inputs' \) \
     -o -path "$repo_root/knowledge/raw" "${repository_prune_or[@]}" \) -prune -o \
  -type f -path '*/projects/*/docs/README.md' -print0)

# Project templateへ docs/、ARCHITECTURE.md、AGENTS.md を常設しない。
for template_entry in AGENTS.md CLAUDE.md ARCHITECTURE.md docs; do
  [[ ! -e "$repo_root/projects/_template/$template_entry" ]] || \
    fail "projects/_template must not ship $template_entry; only the Project that needs it creates it"
done

check_size "$repo_root/AGENTS.md" 8192 'root AGENTS.md'
check_size_warning "$repo_root/AGENTS.md" 4096 'root AGENTS.md router'
check_size "$repo_root/projects/AGENTS.md" 2048 'projects AGENTS.md'
check_size "$repo_root/README.md" 32768 'README.md'
check_size "$repo_root/knowledge/KNOWLEDGE.md" 20480 'KNOWLEDGE.md'
check_size "$repo_root/skills/SKILLS.md" 12288 'skills SKILLS.md'
check_size "$repo_root/projects/PROJECTS.md" 24576 'projects PROJECTS.md'
check_size "$repo_root/evals/EVALS.md" 24576 'evals EVALS.md'
check_size "$repo_root/tools/TOOLS.md" 20480 'tools TOOLS.md'
check_size "$repo_root/tools/BACKUP.md" 20480 'tools BACKUP.md'
check_size "$knowledge_index_file" 8192 'Knowledge index'
check_size "$knowledge_log_file" 131072 'Knowledge log'
check_heading_warning "$repo_root/AGENTS.md" 20
check_heading_warning "$repo_root/knowledge/KNOWLEDGE.md" 30
check_heading_warning "$repo_root/skills/SKILLS.md" 30
check_heading_warning "$repo_root/projects/PROJECTS.md" 30

if [[ "$strict" == true ]]; then
  if grep -Eq '<agent-name>|<agent-role>|<agent-mission>|<agent-vision>|<project-dir>' "$repo_root/AGENTS.md"; then
    fail 'AGENTS.md contains unresolved agent definition placeholders'
  fi
  while IFS= read -r -d '' case_file; do
    if grep -Fq '<skill-name>' "$case_file"; then
      fail "$(relative_path "$case_file") contains an unresolved Skill placeholder"
    fi
  done < <(find "$repo_root/evals/cases" -type f -name '*.yaml' -print0)
fi

if [[ -d "$repo_root/projects/_archive" ]]; then
  fail 'projects/_archive is forbidden; use Project status without physical moves'
fi

# ルートはブートローダー兼ルーターであり、Route表と入口ファイルを実在参照で持つ。
validate_claude_bridge "$repo_root/AGENTS.md"
validate_claude_bridge "$repo_root/projects/AGENTS.md"
if [[ -f "$repo_root/AGENTS.md" ]]; then
  for route_token in knowledge skill project meta none; do
    grep -Eq "^\| *\`$route_token\` *\|" "$repo_root/AGENTS.md" || \
      fail "AGENTS.md is missing the Route table row for: $route_token"
  done
  for route_entry in knowledge/KNOWLEDGE.md skills/SKILLS.md projects/AGENTS.md; do
    grep -Fq "$route_entry" "$repo_root/AGENTS.md" || \
      fail "AGENTS.md does not name the Route entry file: $route_entry"
  done
  while IFS= read -r referenced_path; do
    [[ -n "$referenced_path" ]] || continue
    case "$referenced_path" in */*) ;; *) continue ;; esac
    [[ -e "$repo_root/$referenced_path" ]] || \
      fail "AGENTS.md references a missing entry file: $referenced_path"
  done < <(grep -Eo '`[a-z][a-zA-Z0-9_./-]+\.(md|sh)`' "$repo_root/AGENTS.md" | tr -d '`' | LC_ALL=C sort -u)
fi
if [[ -f "$repo_root/projects/AGENTS.md" ]]; then
  for project_entry in PROJECT.md STATE.md projects/PROJECTS.md; do
    grep -Fq "$project_entry" "$repo_root/projects/AGENTS.md" || \
      fail "projects/AGENTS.md does not delegate to: $project_entry"
  done
fi

# 個別ProjectのAGENTS.mdは任意。存在する場合だけ差分ファイルとして検査する。
while IFS= read -r -d '' project_agents_file; do
  [[ -f "$(dirname "$project_agents_file")/PROJECT.md" ]] || continue
  validate_project_agents_file "$project_agents_file"
done < <(find "$repo_root/projects" "$repo_root/evals/fixtures" \
  \( "${repository_prune[@]}" \) -prune -o -type f -name 'AGENTS.md' -print0)

while IFS= read -r -d '' orphan_claude_file; do
  [[ -f "$(dirname "$orphan_claude_file")/PROJECT.md" ]] || continue
  [[ -f "$(dirname "$orphan_claude_file")/AGENTS.md" ]] || \
    fail "$(relative_path "$orphan_claude_file") exists without a sibling AGENTS.md to import"
done < <(find "$repo_root/projects" "$repo_root/evals/fixtures" \
  \( "${repository_prune[@]}" \) -prune -o -type f -name 'CLAUDE.md' -print0)

while IFS= read -r -d '' nested_git; do
  fail "nested Git repository is forbidden unless it is a declared Independent Project clone: $(relative_path "$nested_git")"
done < <(find "$repo_root" \( "${repository_prune[@]}" \) -prune -o \
  -mindepth 2 \( -type d -o -type f \) -name .git -print0)

# root Gitは`repository/`本体を追跡せず、gitlinkもsubmoduleも持たない。
require_fixed_line "$repo_root/.gitignore" 'projects/*/repository/'
if [[ -n "$tracked_files_snapshot" ]]; then
  while IFS= read -r tracked_child; do
    [[ -n "$tracked_child" ]] || continue
    fail "the root repository must not track Independent repository contents: $tracked_child"
  done < <(printf '%s\n' "$tracked_files_snapshot" | grep -E '^projects/[^/]+/repository/' | head -n 5 || true)
fi
if git -C "$repo_root" rev-parse --show-toplevel >/dev/null 2>&1; then
  while IFS= read -r gitlink_path; do
    [[ -n "$gitlink_path" ]] || continue
    fail "root index holds a gitlink (mode 160000): $gitlink_path — Independent repositories are plain clones"
  done < <(git -C "$repo_root" ls-files --stage | awk '$1 == "160000" { print $4 }')
fi
[[ ! -e "$repo_root/.gitmodules" ]] || \
  fail '.gitmodules is forbidden; Independent repositories are plain clones, not submodules'

validate_project_contract "$repo_root/projects/_template/PROJECT.md"
validate_project_state "$repo_root/projects/_template/STATE.md"
while IFS= read -r -d '' project_file; do
  [[ "$project_file" == "$repo_root/projects/_template/PROJECT.md" ]] && continue
  validate_project_contract "$project_file"
  validate_project_state "$(dirname "$project_file")/STATE.md"
  validate_project_docs "$(dirname "$project_file")"
done < <(find "$repo_root/projects" "$repo_root/evals/fixtures" \
  \( "${repository_prune[@]}" \) -prune -o -type f -name 'PROJECT.md' -print0)

validate_skill "$repo_root/skills/_template/SKILL.md"
while IFS= read -r -d '' skill_file; do
  [[ "$skill_file" == "$repo_root/skills/_template/SKILL.md" ]] && continue
  validate_skill "$skill_file"
done < <(find "$repo_root/skills" "$repo_root/evals/fixtures" \
  \( "${repository_prune[@]}" \) -prune -o -type f -name 'SKILL.md' -print0)

while IFS= read -r -d '' page; do
  case "$page" in */README.md) continue ;; esac
  validate_knowledge_page "$page"
done < <(find \
  "$repo_root/knowledge/wiki/sources" "$repo_root/knowledge/wiki/topics" \
  "$repo_root/evals/fixtures" -type f -name '*.md' \
  \( -path '*/knowledge/wiki/sources/*' -o -path '*/knowledge/wiki/topics/*' \) -print0)
validate_knowledge_page "$knowledge_source_template"
validate_knowledge_page "$knowledge_topic_template"

index_items="$(grep -Ec '^- ' "$knowledge_index_file" || true)"
(( index_items <= 50 )) || fail "$knowledge_index_path has more than 50 route-map items"
if grep -Eq '^- .*knowledge/raw/|^## raw/' "$knowledge_index_file"; then
  fail "$knowledge_index_path must not register knowledge/raw/ as an itemized global ledger"
fi

log_records="$(grep -Ec '^[0-9]{4}-[0-9]{2}-[0-9]{2}[[:space:]]+' "$knowledge_log_file" || true)"
(( log_records <= 1000 )) || fail "$knowledge_log_path has more than 1,000 records and must rotate"
if [[ -d "$repo_root/knowledge/wiki/logs" ]]; then
  while IFS= read -r -d '' log_file; do
    filename="${log_file##*/}"
    [[ "$filename" == '.gitkeep' ]] && continue
    if [[ ! "$filename" =~ ^[0-9]{4}-Q[1-4](-[0-9]{2})?\.md$ ]]; then
      fail "$(relative_path "$log_file") has an invalid closed-log filename"
    fi
  done < <(find "$repo_root/knowledge/wiki/logs" -type f -print0)
fi

required_cases=(
  project-correction-recovery project-finite-completion
  project-goal-change-protection project-state-closeout protect-immutable-records protect-paused-project
  route-to-knowledge route-to-project route-to-skill temporary-code-isolation project-delete-requires-retired
  knowledge-bounded-retrieval knowledge-superseded-redirect knowledge-original-escalation
  catalog-failure-fallback project-completed-not-default project-required-only context-budget-stop
  large-file-section-read ambiguous-target-no-broad-scan meta-route-validator-change
  knowledge-log-auto-rotation scale-sqlite-auto-enable
  backup-explicit-only backup-divergence-refusal restore-single-writer
  backup-workspace-repository-boundary independent-consolidation-audit
  independent-promotion-session-boundary independent-repository-materialization
  root-clean-independent-repository-safety
  root-agents-router-scope project-agents-optional project-agents-diff-only
  project-agents-no-contract-copy project-agents-claude-bridge
  knowledge-internal-record-storage knowledge-external-source-storage
  research-question-to-project research-method-to-skill project-research-knowledge-promotion
  project-docs-route-required project-docs-design-entry project-architecture-entry
  project-domain-sense-not-spec project-docs-readme-forbidden independent-root-content-boundary
  canonical-area-entry-names
)

# 改名した旧ケース名が必須一覧や文書へ残っていないことを同じ作業内で保証する。
retired_case_names=(
  backup-external-repo-boundary satellite-consolidation-audit
  satellite-promotion-session-boundary satellite-hub-content-boundary
)
for retired_case in "${retired_case_names[@]}"; do
  [[ ! -e "$repo_root/evals/cases/$retired_case.yaml" ]] || \
    fail "retired eval case must not exist: evals/cases/$retired_case.yaml"
  if [[ -n "$tracked_files_snapshot" ]] && \
    printf '%s\n' "$tracked_files_snapshot" | grep -Fqx -- "evals/cases/$retired_case.yaml"; then
    fail "retired eval case is still tracked in the Git index: evals/cases/$retired_case.yaml"
  fi
done
for case_name in "${required_cases[@]}"; do require_file "$repo_root/evals/cases/$case_name.yaml"; done

while IFS= read -r -d '' case_file; do
  require_fixed_line "$case_file" 'request: |'
  require_fixed_line "$case_file" 'expect:'
  grep -Eq '^name: [a-z0-9-]+$' "$case_file" || fail "$(relative_path "$case_file") has an invalid name"
  grep -Eq '^  route: (knowledge|skill|project|meta|none)([[:space:]]|$)' "$case_file" || \
    fail "$(relative_path "$case_file") has an invalid route"
  grep -Fq '  must_read:' "$case_file" || fail "$(relative_path "$case_file") is missing must_read"

  if grep -Eq '^  route: project([[:space:]]|$)' "$case_file"; then
    if grep -Eq '    - projects/.+/PROJECT\.md' "$case_file"; then
      grep -Eq '    - projects/.+/STATE\.md' "$case_file" || \
        fail "$(relative_path "$case_file") requires a Project contract but not its STATE.md"
    elif ! grep -A3 -F '  must_search:' "$case_file" | grep -Fq 'command: tools/find-context.sh'; then
      fail "$(relative_path "$case_file") Project route must read PROJECT.md/STATE.md or use tools/find-context.sh"
    fi
  fi
  max_candidates="$(sed -n 's/^  max_candidates: //p' "$case_file" | head -n 1)"
  if [[ -n "$max_candidates" ]] && { [[ ! "$max_candidates" =~ ^[1-5]$ ]]; }; then
    fail "$(relative_path "$case_file") max_candidates must be 1..5"
  fi
  fixture_name="$(sed -n 's/^fixture: //p' "$case_file" | head -n 1)"
  if [[ -n "$fixture_name" && ! -d "$repo_root/evals/fixtures/$fixture_name" ]]; then
    fail "$(relative_path "$case_file") references missing fixture: $fixture_name"
  fi
done < <(find "$repo_root/evals/cases" -type f -name '*.yaml' -print0)

duplicate_case_names="$(sed -n 's/^name: //p' "$repo_root"/evals/cases/*.yaml | LC_ALL=C sort | uniq -d)"
[[ -z "$duplicate_case_names" ]] || fail "duplicate eval case names: $duplicate_case_names"

if ! grep -Eq '    - projects/.+/STATE\.md#現在の目標=.+' "$repo_root/evals/cases/project-state-closeout.yaml"; then
  fail 'project-state-closeout does not require advancing the current goal'
fi
grep -Fq 'projects/site-migration/PROJECT.md#status=completed' "$repo_root/evals/cases/project-finite-completion.yaml" || \
  fail 'project-finite-completion does not require status=completed'
grep -Fq 'projects/site-migration/STATE.md#現在の目標=なし（Project完了）' \
  "$repo_root/evals/cases/project-finite-completion.yaml" || \
  fail 'project-finite-completion does not close the current goal'
grep -Fq 'projects/site-migration/STATE.md#次の一手=なし（Project完了）' \
  "$repo_root/evals/cases/project-finite-completion.yaml" || \
  fail 'project-finite-completion does not close the next action'

backup_tool="$repo_root/tools/backup-to-github.sh"
if [[ -d "$repo_root/.github/workflows" ]]; then
  fail '.github/workflows is forbidden; GitHub is a passive backup, not an execution platform'
fi
if [[ -f "$backup_tool" ]]; then
  [[ -x "$backup_tool" ]] || fail 'tools/backup-to-github.sh is not executable'
  bash -n "$backup_tool" 2>/dev/null || fail 'tools/backup-to-github.sh fails bash -n'

  allowed_git_subcommands='cat-file config diff fetch for-each-ref init ls-files ls-remote merge-base push rev-list rev-parse symbolic-ref'
  while IFS= read -r subcommand; do
    [[ -n "$subcommand" ]] || continue
    case " $allowed_git_subcommands " in
      *" $subcommand "*) ;;
      *) fail "tools/backup-to-github.sh uses a git subcommand outside the backup allowlist: $subcommand" ;;
    esac
  done < <(awk '
    {
      line = $0
      sub(/(^|[[:space:]])#.*$/, "", line)
      gsub(/[<>|&;]/, " SEP ", line)
      gsub(/[^A-Za-z0-9_.-]/, " ", line)
      n = split(line, token, /[[:space:]]+/)
      for (i = 1; i <= n; i++) {
        if (token[i] != "git") continue
        j = i + 1
        while (j <= n && (token[j] == "-C" || token[j] == "-c")) j += 2
        while (j <= n && substr(token[j], 1, 1) == "-") j++
        if (j <= n && token[j] != "" && token[j] != "SEP") print token[j]
      }
    }
  ' "$backup_tool" | LC_ALL=C sort -u)

  for forbidden_flag in --force --force-with-lease --mirror --prune --delete; do
    if grep -Fq -- "$forbidden_flag" "$backup_tool"; then
      fail "tools/backup-to-github.sh must not use $forbidden_flag"
    fi
  done

  push_invocations="$(grep -Ec 'git[^#]*[[:space:]]push[[:space:]]' "$backup_tool" || true)"
  if (( push_invocations != 1 )); then
    fail "tools/backup-to-github.sh must contain exactly one git push invocation (found $push_invocations)"
  fi
  if ! grep -Eq 'git[^#]*[[:space:]]push[[:space:]]+--porcelain[[:space:]]+"\$remote"[[:space:]]+"HEAD:refs/heads/\$branch"' \
    "$backup_tool"; then
    fail 'tools/backup-to-github.sh must push only the explicit HEAD:refs/heads/$branch refspec'
  fi
fi

materialize_tool="$repo_root/tools/materialize-project-repositories.sh"
if [[ -f "$materialize_tool" ]]; then
  [[ -x "$materialize_tool" ]] || fail 'tools/materialize-project-repositories.sh is not executable'
  bash -n "$materialize_tool" 2>/dev/null || \
    fail 'tools/materialize-project-repositories.sh fails bash -n'
  for forbidden_flag in --force --mirror --hard; do
    if grep -Fq -- "$forbidden_flag" "$materialize_tool"; then
      fail "tools/materialize-project-repositories.sh must not use $forbidden_flag"
    fi
  done
  # 既存cloneをreset/clean/stash/merge/rebaseで変形しない。
  for forbidden_subcommand in reset clean stash merge rebase pull; do
    if grep -Eq "git[^#]*[[:space:]]$forbidden_subcommand[[:space:]]" "$materialize_tool"; then
      fail "tools/materialize-project-repositories.sh must not run git $forbidden_subcommand"
    fi
  done
  grep -Fq 'MATERIALIZATION_OK' "$materialize_tool" || \
    fail 'tools/materialize-project-repositories.sh does not emit MATERIALIZATION_OK'
  grep -Fq 'MATERIALIZATION_BLOCKED' "$materialize_tool" || \
    fail 'tools/materialize-project-repositories.sh does not emit MATERIALIZATION_BLOCKED'
fi

grep -Fq 'tools/backup-to-github.sh' "$repo_root/README.md" || \
  fail 'README.md does not register tools/backup-to-github.sh'
grep -Fq 'tools/BACKUP.md' "$repo_root/README.md" || fail 'README.md does not register tools/BACKUP.md'
grep -Fq 'tools/materialize-project-repositories.sh' "$repo_root/README.md" || \
  fail 'README.md does not register tools/materialize-project-repositories.sh'
grep -Fq 'backup-to-github.sh' "$repo_root/tools/TOOLS.md" || \
  fail 'tools/TOOLS.md does not register backup-to-github.sh'
grep -Fq 'materialize-project-repositories.sh' "$repo_root/tools/TOOLS.md" || \
  fail 'tools/TOOLS.md does not register materialize-project-repositories.sh'
grep -Fq 'BACKUP.md' "$repo_root/tools/TOOLS.md" || fail 'tools/TOOLS.md does not register BACKUP.md'
for scope_token in WORKSPACE_BACKUP_OK ROOT_BACKUP_OK; do
  grep -Fq "$scope_token" "$repo_root/tools/BACKUP.md" || \
    fail "tools/BACKUP.md does not document the $scope_token result line"
done
if grep -Eq '(^|[^_])BACKUP_(OK|READY)' "$repo_root/tools/backup-to-github.sh"; then
  fail 'tools/backup-to-github.sh must not emit the retired BACKUP_OK/BACKUP_READY result lines'
fi
grep -Fq 'tools/BACKUP.md' "$repo_root/AGENTS.md" || \
  fail 'AGENTS.md does not delegate backup details to tools/BACKUP.md'

cache_test_dir="$(mktemp -d "${TMPDIR:-/tmp}/agent-validator-cache.XXXXXX")"
fixture_cache_dir="$(mktemp -d "${TMPDIR:-/tmp}/agent-validator-fixture.XXXXXX")"
sqlite_fixture_cache_dir="$(mktemp -d "${TMPDIR:-/tmp}/agent-validator-sqlite.XXXXXX")"
log_fixture_dir="$(mktemp -d "${TMPDIR:-/tmp}/agent-validator-log.XXXXXX")"
backup_fixture_dir="$(mktemp -d "${TMPDIR:-/tmp}/agent-validator-backup.XXXXXX")"
malformed_fixture_dir="$(mktemp -d "${TMPDIR:-/tmp}/agent-validator-malformed.XXXXXX")"
malformed_cache_dir="$(mktemp -d "${TMPDIR:-/tmp}/agent-validator-malformed-cache.XXXXXX")"
trap 'rm -rf "$cache_test_dir" "$fixture_cache_dir" "$sqlite_fixture_cache_dir" "$log_fixture_dir" "$backup_fixture_dir" "$malformed_fixture_dir" "$malformed_cache_dir"' EXIT
if ! AGENT_CACHE_DIR="$cache_test_dir" bash "$repo_root/tools/build-context-cache.sh" >/dev/null; then
  fail 'build-context-cache.sh failed to generate a cache'
elif ! AGENT_CACHE_DIR="$cache_test_dir" bash "$repo_root/tools/build-context-cache.sh" --check >/dev/null; then
  fail 'build-context-cache.sh --check reports a freshly generated cache as stale'
elif ! AGENT_CACHE_DIR="$cache_test_dir" bash "$repo_root/tools/build-context-cache.sh" --check-routing >/dev/null; then
  fail 'build-context-cache.sh --check-routing reports a fresh catalog as stale'
fi
if grep -Eq '^head=' "$cache_test_dir/cache.meta"; then
  fail 'cache.meta must not use Git HEAD as a freshness input'
fi
if [[ -f "$cache_test_dir/manifest.tsv" ]]; then
  for immutable_area in knowledge/raw/internal knowledge/raw/external; do
    if awk -F '\t' -v area="$immutable_area/" '
        index($1, area) == 1 && $6 != "true" { bad = 1 }
        END { exit !bad }
      ' "$cache_test_dir/manifest.tsv"; then
      fail "build-context-cache.sh must mark every file under $immutable_area/ as immutable in manifest.tsv"
    fi
  done
fi

mkdir -p "$log_fixture_dir/knowledge/wiki"
{
  printf '# LOG — fixture\n\n---\n\n'
  i=1
  while (( i <= 999 )); do
    printf '2026-08-02  lint        fixture/%04d  threshold fixture\n' "$i"
    i=$((i + 1))
  done
} > "$log_fixture_dir/$knowledge_log_path"
if ! AGENT_DIRECTORY_ROOT="$log_fixture_dir" bash "$repo_root/tools/append-knowledge-log.sh" \
  --date 2026-08-02 --type lint --target fixture/1000 --summary 'threshold fixture' >/dev/null; then
  fail 'append-knowledge-log.sh failed at the 1,000-record threshold'
elif [[ ! -f "$log_fixture_dir/knowledge/wiki/logs/2026-Q3.md" ]]; then
  fail 'append-knowledge-log.sh did not create the expected quarterly archive'
elif [[ "$(grep -Ec '^[0-9]{4}-[0-9]{2}-[0-9]{2}[[:space:]]+' "$log_fixture_dir/$knowledge_log_path" || true)" != '0' ]]; then
  fail 'append-knowledge-log.sh did not reset the current log after rotation'
elif [[ "$(grep -Ec '^[0-9]{4}-[0-9]{2}-[0-9]{2}[[:space:]]+' "$log_fixture_dir/knowledge/wiki/logs/2026-Q3.md" || true)" != '1000' ]]; then
  fail 'append-knowledge-log.sh archive does not contain exactly 1,000 records'
fi
mkdir -p "$log_fixture_dir/nested/.tmp"
printf 'ignore me\n' > "$log_fixture_dir/nested/.tmp/ignored.txt"
printf 'keep me\n' > "$log_fixture_dir/nested/kept.txt"
if ! AGENT_DIRECTORY_ROOT="$log_fixture_dir" AGENT_CACHE_DIR="$fixture_cache_dir" \
  bash "$repo_root/tools/build-context-cache.sh" >/dev/null; then
  fail 'build-context-cache.sh failed on nested .tmp fixture'
elif grep -Fq 'nested/.tmp/' "$fixture_cache_dir/manifest.tsv"; then
  fail 'build-context-cache.sh manifest includes a nested .tmp file'
elif ! grep -Fq $'nested/kept.txt\t' "$fixture_cache_dir/manifest.tsv"; then
  fail 'build-context-cache.sh nested .tmp test did not scan the adjacent durable file'
fi

# frontmatterを欠く正本があってもcache生成を止めず、対象を名指しして警告し、候補から外す。
mkdir -p "$malformed_fixture_dir/projects/good-project" \
  "$malformed_fixture_dir/projects/no-status" \
  "$malformed_fixture_dir/skills/blank-status-skill" \
  "$malformed_fixture_dir/knowledge/wiki/topics"
{
  printf '%s\n' '---' 'name: good-project' 'description: fixture' 'status: active'
  printf '%s\n' 'mode: finite' 'repository_mode: embedded' '---'
} > "$malformed_fixture_dir/projects/good-project/PROJECT.md"
{
  printf '%s\n' '---' 'name: no-status' 'description: fixture' '---'
} > "$malformed_fixture_dir/projects/no-status/PROJECT.md"
{
  printf '%s\n' '---' 'name: blank-status-skill' 'description: fixture' 'status:' '---'
} > "$malformed_fixture_dir/skills/blank-status-skill/SKILL.md"
{
  printf '%s\n' '---' 'summary: fixture' 'aliases: []' '---'
} > "$malformed_fixture_dir/knowledge/wiki/topics/no-status.md"

set +e
malformed_output="$(AGENT_DIRECTORY_ROOT="$malformed_fixture_dir" AGENT_CACHE_DIR="$malformed_cache_dir" \
  bash "$repo_root/tools/build-context-cache.sh" 2>&1)"
malformed_status=$?
set -e
if (( malformed_status != 0 )); then
  fail "build-context-cache.sh aborted on a malformed canon file instead of warning and skipping: $malformed_output"
else
  for malformed_target in \
    'projects/no-status/PROJECT.md' \
    'skills/blank-status-skill/SKILL.md' \
    'knowledge/wiki/topics/no-status.md'; do
    printf '%s\n' "$malformed_output" | grep -Eq "^WARN: $malformed_target: missing .*status" || \
      fail "build-context-cache.sh did not name $malformed_target and its missing key in a WARN line"
    if [[ -f "$malformed_cache_dir/catalog.tsv" ]] && \
      grep -Fq "$malformed_target" "$malformed_cache_dir/catalog.tsv"; then
      fail "build-context-cache.sh registered the malformed canon file in the catalog: $malformed_target"
    fi
  done
  if printf '%s\n' "$malformed_output" | grep -Eq '^WARN: knowledge/wiki/topics/no-status\.md: missing name'; then
    fail 'build-context-cache.sh reported a missing name for a knowledge page whose name comes from the filename'
  fi
  if [[ ! -f "$malformed_cache_dir/catalog.tsv" ]] || \
    ! grep -Fq 'projects/good-project/PROJECT.md' "$malformed_cache_dir/catalog.tsv"; then
    fail 'build-context-cache.sh dropped a well-formed canon file while skipping malformed ones'
  fi
fi
if [[ -f "$cache_test_dir/catalog.tsv" ]]; then
  alias_collisions="$(awk -F '\t' '
    NR == 1 || $3 != "active" || ($1 != "knowledge" && $1 != "skill") { next }
    {
      owner = $8
      key = $1 SUBSEP tolower($4)
      if (seen[key] != "" && seen[key] != owner) print $1 ":" tolower($4)
      seen[key] = owner
      count = split(tolower($5), alias, "|")
      for (i = 1; i <= count; i++) {
        if (alias[i] == "") continue
        key = $1 SUBSEP alias[i]
        if (seen[key] != "" && seen[key] != owner) print $1 ":" alias[i]
        seen[key] = owner
      }
    }
  ' "$cache_test_dir/catalog.tsv" | LC_ALL=C sort -u)"
  [[ -z "$alias_collisions" ]] || fail "active alias collision(s): $alias_collisions"
fi

if [[ -f "$backup_tool" ]] && command -v git >/dev/null 2>&1; then
  backup_work="$backup_fixture_dir/work"
  backup_remote_dir="$backup_fixture_dir/remote.git"
  backup_peer="$backup_fixture_dir/peer"
  independent_seed="$backup_fixture_dir/independent-seed"
  independent_remote_dir="$backup_fixture_dir/independent.git"
  independent_clone="$backup_work/projects/data-pipeline/repository"
  independent_cache_dir="$backup_fixture_dir/independent-cache"
  backup_env=(
    HOME="$backup_fixture_dir" GIT_CONFIG_NOSYSTEM=1
    GIT_AUTHOR_NAME=fixture GIT_AUTHOR_EMAIL=fixture@example.invalid
    GIT_COMMITTER_NAME=fixture GIT_COMMITTER_EMAIL=fixture@example.invalid
  )
  backup_output=''
  backup_status=0

  backup_git() { env "${backup_env[@]}" git -C "$backup_work" "$@"; }
  child_git() { env "${backup_env[@]}" git -C "$independent_clone" "$@"; }
  seed_git() { env "${backup_env[@]}" git -C "$independent_seed" "$@"; }
  backup_run() {
    set +e
    backup_output="$(env "${backup_env[@]}" AGENT_DIRECTORY_ROOT="$backup_work" bash "$backup_tool" "$@" 2>&1)"
    backup_status=$?
    set -e
  }
  materialize_run() {
    set +e
    backup_output="$(env "${backup_env[@]}" AGENT_DIRECTORY_ROOT="$backup_work" \
      bash "$materialize_tool" "$@" 2>&1)"
    backup_status=$?
    set -e
  }
  build_fixture_cache() {
    set +e
    env "${backup_env[@]}" AGENT_DIRECTORY_ROOT="$backup_work" AGENT_CACHE_DIR="$independent_cache_dir" \
      bash "$repo_root/tools/build-context-cache.sh" >/dev/null 2>&1
    backup_status=$?
    set -e
  }
  fixture_fingerprint() {
    sed -n 's/^content_fingerprint=//p' "$independent_cache_dir/cache.meta" | head -n 1
  }
  backup_expect_blocked() {
    if (( backup_status == 0 )); then
      fail "backup fixture: $2 unexpectedly succeeded"
    elif ! printf '%s\n' "$backup_output" | grep -Fqx "BACKUP_BLOCKED reason=$1"; then
      fail "backup fixture: $2 did not report reason=$1: $(printf '%s' "$backup_output" | head -n 2 | tr '\n' ' ')"
    fi
  }
  backup_expect_line() {
    if (( backup_status != 0 )); then
      fail "backup fixture: $2 failed: $backup_output"
    elif ! printf '%s\n' "$backup_output" | grep -Fqx "$1"; then
      fail "backup fixture: $2 did not emit: $1"
    fi
  }
  materialize_expect_blocked() {
    if (( backup_status == 0 )); then
      fail "materializer fixture: $3 unexpectedly succeeded"
    elif ! printf '%s\n' "$backup_output" | grep -Fqx "MATERIALIZATION_BLOCKED reason=$1 project=$2"; then
      fail "materializer fixture: $3 did not report reason=$1: $(printf '%s' "$backup_output" | head -n 2 | tr '\n' ' ')"
    fi
  }
  materialize_expect_line() {
    if (( backup_status != 0 )); then
      fail "materializer fixture: $2 failed: $backup_output"
    elif ! printf '%s\n' "$backup_output" | grep -Fqx "$1"; then
      fail "materializer fixture: $2 did not emit: $1"
    fi
  }
  backup_remote_sha() {
    env "${backup_env[@]}" git -C "$backup_remote_dir" rev-parse --verify --quiet refs/heads/main || true
  }
  independent_remote_sha() {
    env "${backup_env[@]}" git -C "$independent_remote_dir" rev-parse --verify --quiet refs/heads/main || true
  }
  adopt_revision() {
    {
      printf '%s\n' '---' 'updated_at: 2026-08-03' '---' '' '## Repository State' ''
      printf -- '- revision: `%s`\n' "$1"
    } > "$backup_work/projects/data-pipeline/STATE.md"
    backup_git add projects/data-pipeline/STATE.md
    backup_git commit -q -m 'fixture: adopt revision'
  }

  env "${backup_env[@]}" git init -q --bare "$backup_remote_dir"
  env "${backup_env[@]}" git -C "$backup_remote_dir" symbolic-ref HEAD refs/heads/main
  env "${backup_env[@]}" git init -q --bare "$independent_remote_dir"
  env "${backup_env[@]}" git -C "$independent_remote_dir" symbolic-ref HEAD refs/heads/main
  # branchやtagから到達できないcommitを採用する負ケースのため、SHA指定fetchを許可する。
  env "${backup_env[@]}" git -C "$independent_remote_dir" config uploadpack.allowAnySHA1InWant true

  env "${backup_env[@]}" git init -q "$independent_seed"
  seed_git symbolic-ref HEAD refs/heads/main
  printf 'verified independent revision\n' > "$independent_seed/source.txt"
  seed_git add source.txt
  seed_git commit -q -m 'fixture: independent revision'
  seed_git remote add origin "$independent_remote_dir"
  seed_git push -q origin main
  independent_revision="$(seed_git rev-parse HEAD)"

  env "${backup_env[@]}" git init -q "$backup_work"
  backup_git symbolic-ref HEAD refs/heads/main
  mkdir -p "$backup_work/tools" "$backup_work/projects/data-pipeline"
  printf 'fixture agent directory\n' > "$backup_work/AGENTS.md"
  printf '.tmp/\n.agent-cache/\n.env*\n!.env.example\n.DS_Store\nprojects/*/repository/\nignored-dir/\n' \
    > "$backup_work/.gitignore"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$backup_work/tools/validate-agent-directory.sh"
  {
    printf '%s\n' '---' 'name: data-pipeline' 'description: fixture' 'status: active' 'mode: continuous'
    printf '%s\n' 'repository_mode: independent' "repository_url: $independent_remote_dir"
    printf '%s\n' 'repository_reason: automation' 'repository_default_branch: main' '---'
  } > "$backup_work/projects/data-pipeline/PROJECT.md"
  {
    printf '%s\n' '---' 'updated_at: 2026-08-03' '---' '' '## Repository State' ''
    printf -- '- revision: `%s`\n' "$independent_revision"
  } > "$backup_work/projects/data-pipeline/STATE.md"
  backup_git add -A
  backup_git commit -q -m 'fixture: initial commit'
  backup_git remote add backup "$backup_remote_dir"
  backup_head="$(backup_git rev-parse HEAD)"

  # --- 未materialize状態 -------------------------------------------------------
  backup_run --dry-run
  backup_expect_blocked 'missing-independent-repository' 'workspace backup before materialization'
  materialize_run --all --check
  materialize_expect_blocked 'missing-independent-repository' 'data-pipeline' '--check on a missing clone'
  backup_run --root-only --dry-run
  backup_expect_line "ROOT_BACKUP_READY remote=backup branch=main sha=$backup_head scope=root-only" \
    'root-only dry run while the Independent clone is missing'

  # --- materializer ------------------------------------------------------------
  materialize_run --all
  materialize_expect_line 'MATERIALIZATION_OK total=1 cloned=1 verified=0' 'fresh clone'
  [[ -d "$independent_clone/.git" && ! -L "$independent_clone/.git" ]] || \
    fail 'materializer fixture: repository/.git is not a real directory'
  [[ ! -e "$independent_clone/.gitmodules" ]] || \
    fail 'materializer fixture: the clone was materialized as a submodule'
  [[ "$(child_git rev-parse HEAD)" == "$independent_revision" ]] || \
    fail 'materializer fixture: HEAD is not the adopted revision'
  [[ -z "$(child_git symbolic-ref --quiet HEAD 2>/dev/null || true)" ]] || \
    fail 'materializer fixture: the adopted revision was not checked out detached'
  materialize_run --all --check
  materialize_expect_line 'MATERIALIZATION_OK total=1 cloned=0 verified=1' 'idempotent --check'

  # remoteのtipが進んでも採用revisionを勝手に更新しない。
  printf 'later work\n' > "$independent_seed/later.txt"
  seed_git add later.txt
  seed_git commit -q -m 'fixture: newer branch tip'
  seed_git push -q origin main
  independent_tip="$(seed_git rev-parse HEAD)"
  materialize_run --all --check
  materialize_expect_line 'MATERIALIZATION_OK total=1 cloned=0 verified=1' '--check against a newer branch tip'
  [[ "$(child_git rev-parse HEAD)" == "$independent_revision" ]] || \
    fail 'materializer fixture: the clone was advanced to the branch tip instead of the adopted revision'

  # --- 正常なworkspace backup ----------------------------------------------------
  independent_remote_before="$(independent_remote_sha)"
  backup_run --dry-run
  backup_expect_line "WORKSPACE_BACKUP_READY remote=backup branch=main sha=$backup_head independent=1" \
    'workspace dry run on a materialized workspace'
  [[ -z "$(backup_remote_sha)" ]] || fail 'backup fixture: dry run wrote to the root remote'

  backup_run
  backup_expect_line "WORKSPACE_BACKUP_OK remote=backup branch=main sha=$backup_head independent=1" \
    'workspace backup on a materialized workspace'
  [[ "$(backup_remote_sha)" == "$backup_head" ]] || \
    fail 'backup fixture: the root remote does not match local HEAD after push'
  [[ "$(independent_remote_sha)" == "$independent_remote_before" ]] || \
    fail 'backup fixture: the workspace backup pushed to the Independent remote'

  backup_run --root-only --dry-run
  backup_expect_line "ROOT_BACKUP_READY remote=backup branch=main sha=$backup_head scope=root-only" \
    'root-only dry run'
  backup_run --root-only
  backup_expect_line "ROOT_BACKUP_OK remote=backup branch=main sha=$backup_head scope=root-only" \
    'root-only backup'
  [[ "$(independent_remote_sha)" == "$independent_remote_before" ]] || \
    fail 'backup fixture: the root-only backup pushed to the Independent remote'

  # --- cacheの境界 ----------------------------------------------------------------
  build_fixture_cache
  if (( backup_status != 0 )); then
    fail 'cache fixture: build-context-cache.sh failed on a materialized workspace'
  else
    if grep -Fq 'projects/data-pipeline/repository/' "$independent_cache_dir/manifest.tsv"; then
      fail 'cache fixture: manifest.tsv registers Independent repository contents'
    fi
    grep -Fq 'projects/data-pipeline/PROJECT.md' "$independent_cache_dir/catalog.tsv" || \
      fail 'cache fixture: catalog.tsv does not register the root-side PROJECT.md'
    fingerprint_before="$(fixture_fingerprint)"

    printf 'child-only change\n' >> "$independent_clone/source.txt"
    build_fixture_cache
    [[ "$(fixture_fingerprint)" == "$fingerprint_before" ]] || \
      fail 'cache fixture: an Independent body change altered the root cache fingerprint'
    child_git checkout -q -- source.txt

    printf '\n<!-- fixture root metadata change -->\n' >> "$backup_work/projects/data-pipeline/PROJECT.md"
    build_fixture_cache
    [[ "$(fixture_fingerprint)" != "$fingerprint_before" ]] || \
      fail 'cache fixture: a root PROJECT.md change did not alter the cache fingerprint'
    backup_git checkout -q -- projects/data-pipeline/PROJECT.md
  fi

  # --- Independent本体の負ケース ----------------------------------------------------
  mkdir -p "$independent_clone/nested/.git"
  backup_run --dry-run
  backup_expect_blocked 'independent-nested-repository' 'a nested repository inside the Independent clone'
  rm -rf "$independent_clone/nested"

  printf '[submodule "vendor"]\n\tpath = vendor\n' > "$independent_clone/.gitmodules"
  backup_run --dry-run
  backup_expect_blocked 'independent-submodule-unsupported' 'a submodule declaration inside the clone'
  rm -f "$independent_clone/.gitmodules"

  printf '*.bin filter=lfs diff=lfs merge=lfs -text\n' > "$independent_clone/.gitattributes"
  backup_run --dry-run
  backup_expect_blocked 'independent-git-lfs-unsupported' 'Git LFS inside the Independent clone'
  rm -f "$independent_clone/.gitattributes"

  printf 'dirty\n' >> "$independent_clone/source.txt"
  backup_run --dry-run
  backup_expect_blocked 'independent-dirty-working-tree' 'a dirty Independent working tree'
  backup_run --root-only --dry-run
  backup_expect_line "ROOT_BACKUP_READY remote=backup branch=main sha=$backup_head scope=root-only" \
    'root-only scope ignoring a dirty Independent clone'
  child_git checkout -q -- source.txt

  printf 'staged\n' >> "$independent_clone/source.txt"
  child_git add source.txt
  backup_run --dry-run
  backup_expect_blocked 'independent-staged-changes' 'a staged Independent change'
  child_git reset -q --hard HEAD

  printf 'stray\n' > "$independent_clone/stray.txt"
  backup_run --dry-run
  backup_expect_blocked 'independent-untracked-files' 'an untracked Independent file'
  rm -f "$independent_clone/stray.txt"

  printf 'stashed\n' >> "$independent_clone/source.txt"
  child_git stash push -q
  backup_run --dry-run
  backup_expect_blocked 'independent-stash-present' 'an Independent stash entry'
  child_git stash drop -q

  child_git tag fixture-local-only "$independent_revision"
  backup_run --dry-run
  backup_expect_blocked 'independent-unpushed-tag' 'a local-only tag'
  child_git tag -d fixture-local-only >/dev/null

  child_git checkout -q -b fixture-unpublished
  child_git commit -q --allow-empty -m 'fixture: unpublished commit'
  child_git checkout -q --detach "$independent_revision"
  backup_run --dry-run
  backup_expect_blocked 'independent-unreachable-local-branch' 'a local branch absent from the remote'
  child_git branch -q -D fixture-unpublished

  # remoteはobjectを持つが、branchからもtagからも到達できないcommitを採用させる。
  seed_git commit -q --allow-empty -m 'fixture: unreferenced revision'
  unreferenced_revision="$(seed_git rev-parse HEAD)"
  seed_git push -q origin 'HEAD:refs/hidden/unreferenced'
  seed_git checkout -q --detach "$independent_tip"
  child_git fetch -q origin "$unreferenced_revision"
  child_git checkout -q --detach "$unreferenced_revision"
  adopt_revision "$unreferenced_revision"
  backup_run --dry-run
  backup_expect_blocked 'independent-unpushed-commit' 'a HEAD commit no remote head or tag reaches'
  backup_git reset -q --hard HEAD~1
  child_git checkout -q --detach "$independent_revision"

  adopt_revision '0000000000000000000000000000000000000000'
  backup_run --dry-run
  backup_expect_blocked 'independent-revision-unavailable' 'an adopted revision absent from the remote'
  backup_git reset -q --hard HEAD~1

  child_git checkout -q --detach "$independent_tip"
  backup_run --dry-run
  backup_expect_blocked 'independent-head-not-adopted' 'a HEAD that is not the adopted revision'
  child_git checkout -q --detach "$independent_revision"

  child_git remote set-url origin "$backup_remote_dir"
  backup_run --dry-run
  backup_expect_blocked 'repository-origin-mismatch' 'a clone pointing at a different remote'
  child_git remote set-url origin "$independent_remote_dir"

  env "${backup_env[@]}" git -C "$independent_remote_dir" config uploadpack.allowAnySHA1InWant false
  # --- attachmentの負ケース ---------------------------------------------------------
  mv "$independent_clone/.git" "$backup_fixture_dir/detached-git"
  printf 'gitdir: %s\n' "$backup_fixture_dir/detached-git" > "$independent_clone/.git"
  backup_run --dry-run
  backup_expect_blocked 'repository-gitfile-unsupported' 'a .git file instead of a real directory'
  rm -f "$independent_clone/.git"
  mv "$backup_fixture_dir/detached-git" "$independent_clone/.git"

  mv "$independent_clone/.git" "$backup_fixture_dir/relocated-git"
  ln -s "$backup_fixture_dir/relocated-git" "$independent_clone/.git"
  backup_run --dry-run
  backup_expect_blocked 'repository-path-symlink' 'a symlinked .git inside the Independent clone'
  rm -f "$independent_clone/.git"
  mv "$backup_fixture_dir/relocated-git" "$independent_clone/.git"

  # 固定path自体をsymlinkへ置き換えると、`projects/*/repository/` のignoreはdirectoryにしか
  # 一致しないため、attachment検査へ届く前にroot側のuntracked検査が停止させる。
  # 停止することが安全性の要件であり、reasonはrootの検査が先に確定する。
  mv "$independent_clone" "$backup_fixture_dir/moved-clone"
  ln -s "$backup_fixture_dir/moved-clone" "$independent_clone"
  backup_run --dry-run
  backup_expect_blocked 'untracked-files' 'a symlinked Independent clone path'
  rm -f "$independent_clone"
  mv "$backup_fixture_dir/moved-clone" "$independent_clone"

  # --- root ownershipの負ケース -------------------------------------------------------
  # 埋め込みrepository配下は `git add` が拒否するため、indexへ直接blobを登録して再現する。
  # 作業ツリーと同じ内容を登録し、root側がdirtyにならない純粋な所有関係違反にする。
  fixture_tracked_blob="$(backup_git hash-object -w -- projects/data-pipeline/repository/source.txt)"
  backup_git update-index --add \
    --cacheinfo "100644,$fixture_tracked_blob,projects/data-pipeline/repository/source.txt"
  backup_git commit -q -m 'fixture: root tracks the Independent body'
  backup_run --root-only --dry-run
  backup_expect_blocked 'root-tracks-independent-repository' 'the root tracking Independent contents'
  backup_git reset -q --soft HEAD~1
  backup_git reset -q

  backup_git update-index --add --cacheinfo "160000,$independent_revision,projects/data-pipeline/repository"
  backup_git commit -q -m 'fixture: root gitlink'
  backup_run --root-only --dry-run
  backup_expect_blocked 'unsupported-root-gitlink' 'a gitlink in the root index'
  backup_git reset -q --soft HEAD~1
  backup_git reset -q

  # --- 宣言の負ケース -------------------------------------------------------------------
  fixture_project_backup="$backup_fixture_dir/PROJECT.md.orig"
  cp "$backup_work/projects/data-pipeline/PROJECT.md" "$fixture_project_backup"
  {
    printf '%s\n' '---' 'name: data-pipeline' 'description: fixture' 'status: active' 'mode: continuous'
    printf '%s\n' 'repository_mode: independent' "repository_url: $independent_remote_dir"
    printf '%s\n' 'repository_reason: because-we-want-to' 'repository_default_branch: main' '---'
  } > "$backup_work/projects/data-pipeline/PROJECT.md"
  backup_git commit -q -a -m 'fixture: malformed independent declaration'
  backup_run --root-only --dry-run
  backup_expect_blocked 'invalid-independent-declaration' 'an invalid repository_reason'
  backup_git reset -q --hard HEAD~1

  {
    printf '%s\n' '---' 'name: data-pipeline' 'description: fixture' 'status: active' 'mode: continuous'
    printf '%s\n' 'repository_mode: satellite' "repository_url: $independent_remote_dir"
    printf '%s\n' 'repository_reason: automation' 'repository_default_branch: main' '---'
  } > "$backup_work/projects/data-pipeline/PROJECT.md"
  backup_git commit -q -a -m 'fixture: deprecated satellite mode'
  backup_run --root-only --dry-run
  backup_expect_blocked 'deprecated-satellite-mode' 'the retired satellite repository mode'
  backup_git reset -q --hard HEAD~1

  {
    printf '%s\n' '---' 'updated_at: 2026-08-03' '---' '' '## Repository State' ''
    printf -- '- repository: `%s`\n' "$independent_remote_dir"
    printf -- '- revision: `%s`\n' "$independent_revision"
    printf '%s\n' '- branch: `main`' '- remote_verified_at: `2026-08-03`'
  } > "$backup_work/projects/data-pipeline/STATE.md"
  backup_git commit -q -a -m 'fixture: retired Repository State fields'
  backup_run --root-only --dry-run
  backup_expect_blocked 'invalid-independent-state' 'the retired Repository State tuple'
  backup_git reset -q --hard HEAD~1

  cp "$fixture_project_backup" "$backup_work/projects/data-pipeline/PROJECT.md"

  # --- materializerの負ケース -----------------------------------------------------------
  printf 'dirty\n' >> "$independent_clone/source.txt"
  materialize_run --project data-pipeline --check
  materialize_expect_blocked 'repository-dirty' 'data-pipeline' '--check on a dirty target'
  child_git checkout -q -- source.txt

  mv "$independent_clone" "$backup_fixture_dir/parked-clone"
  mkdir -p "$independent_clone"
  printf 'stray\n' > "$independent_clone/stray.txt"
  materialize_run --project data-pipeline
  materialize_expect_blocked 'target-not-empty' 'data-pipeline' 'a non-empty non-repository target'
  rm -rf "$independent_clone"
  mv "$backup_fixture_dir/parked-clone" "$independent_clone"

  # --- 既存のroot側負ケース ---------------------------------------------------------------
  mkdir -p "$backup_work/ignored-dir/nested/.git"
  backup_run --dry-run
  backup_expect_blocked 'nested-git-repository' 'an undeclared ignored nested Git repository'
  rm -rf "$backup_work/ignored-dir"

  printf 'dirty\n' >> "$backup_work/AGENTS.md"
  backup_run --dry-run
  backup_expect_blocked 'dirty-working-tree' 'an uncommitted tracked change'
  backup_git checkout -q -- AGENTS.md

  printf 'staged\n' >> "$backup_work/AGENTS.md"
  backup_git add AGENTS.md
  backup_run --dry-run
  backup_expect_blocked 'staged-changes' 'a staged change'
  backup_git reset -q --hard HEAD

  printf 'stray\n' > "$backup_work/stray.md"
  backup_run --dry-run
  backup_expect_blocked 'untracked-files' 'an untracked non-ignored file'
  rm -f "$backup_work/stray.md"

  printf 'stashed\n' >> "$backup_work/AGENTS.md"
  backup_git stash push -q
  backup_run --dry-run
  backup_expect_blocked 'stash-present' 'a stash entry'
  backup_git stash drop -q

  mkdir -p "$backup_work/.tmp"
  printf 'scratch\n' > "$backup_work/.tmp/scratch"
  backup_git add -f .tmp/scratch
  backup_git commit -q -m 'fixture: forbidden path'
  backup_run --dry-run
  backup_expect_blocked 'forbidden-tracked-file' 'a tracked .tmp path'
  backup_git reset -q --hard HEAD~1
  rm -rf "$backup_work/.tmp"

  backup_git checkout -q -b stray-branch
  printf 'unreachable\n' > "$backup_work/unreachable.md"
  backup_git add -A
  backup_git commit -q -m 'fixture: unreachable commit'
  backup_git checkout -q main
  backup_run --dry-run
  backup_expect_blocked 'unreachable-local-branch' 'a commit unreachable from the backup branch'
  backup_git branch -q -D stray-branch

  printf '%04096d' 0 > "$backup_work/oversized.bin"
  backup_git add -A
  backup_git commit -q -m 'fixture: oversized blob'
  set +e
  backup_output="$(env "${backup_env[@]}" AGENT_DIRECTORY_ROOT="$backup_work" \
    AGENT_BACKUP_MAX_BLOB_BYTES=1024 bash "$backup_tool" --root-only --dry-run 2>&1)"
  backup_status=$?
  set -e
  backup_expect_blocked 'oversized-git-object' 'a blob above the size limit'
  printf '%s\n' "$backup_output" | grep -Fq 'oversized.bin' || \
    fail 'backup fixture: the oversized object report does not name the path'
  backup_git reset -q --hard HEAD~1
  rm -f "$backup_work/oversized.bin"

  env "${backup_env[@]}" git clone -q "$backup_remote_dir" "$backup_peer"
  printf 'peer\n' > "$backup_peer/peer.md"
  env "${backup_env[@]}" git -C "$backup_peer" add -A
  env "${backup_env[@]}" git -C "$backup_peer" commit -q -m 'fixture: peer commit'
  env "${backup_env[@]}" git -C "$backup_peer" push -q origin main
  printf 'local\n' > "$backup_work/local.md"
  backup_git add -A
  backup_git commit -q -m 'fixture: local commit'
  backup_sha_before_divergence="$(backup_remote_sha)"
  backup_run
  backup_expect_blocked 'remote-diverged' 'a diverged remote'
  printf '%s\n' "$backup_output" | grep -Eq "remote=$backup_sha_before_divergence local=[0-9a-f]{40}" || \
    fail 'backup fixture: the divergence report does not name both the remote and local SHA'
  [[ "$(backup_remote_sha)" == "$backup_sha_before_divergence" ]] || \
    fail 'backup fixture: the remote changed while divergence was reported'
  backup_run --dry-run
  backup_expect_blocked 'remote-diverged' 'a diverged remote in dry run'
  [[ "$(backup_remote_sha)" == "$backup_sha_before_divergence" ]] || \
    fail 'backup fixture: the dry run changed the remote'

  # --- root git cleanの危険性は破棄前提のfixtureだけで確かめる -----------------------------
  clean_probe_dir="$backup_fixture_dir/clean-probe"
  mkdir -p "$clean_probe_dir/projects/probe/repository"
  printf 'projects/*/repository/\n' > "$clean_probe_dir/.gitignore"
  printf 'unpushed work\n' > "$clean_probe_dir/projects/probe/repository/unpushed.txt"
  env "${backup_env[@]}" git init -q "$clean_probe_dir"
  env "${backup_env[@]}" git -C "$clean_probe_dir" add -A
  env "${backup_env[@]}" git -C "$clean_probe_dir" commit -q -m 'fixture: clean probe'
  env "${backup_env[@]}" git -C "$clean_probe_dir" clean -q -ffdx
  [[ ! -e "$clean_probe_dir/projects/probe/repository/unpushed.txt" ]] || \
    fail 'clean probe fixture: the ignored Independent path unexpectedly survived git clean -ffdx'
  rm -rf "$clean_probe_dir"

  [[ -z "$(backup_git status --porcelain)" ]] || \
    fail 'backup fixture: the backup tool left the working tree modified'
  [[ -z "$(child_git status --porcelain)" ]] || \
    fail 'backup fixture: the backup tool left the Independent clone modified'
  [[ "$(child_git rev-parse HEAD)" == "$independent_revision" ]] || \
    fail 'backup fixture: the backup tool moved the Independent clone HEAD'
  [[ "$(independent_remote_sha)" == "$independent_remote_before" ]] || \
    fail 'backup fixture: the Independent remote changed during the whole fixture run'
fi

if [[ "$full" == true ]]; then
  fixture_root="$repo_root/evals/fixtures/context-search"
  if ! result="$(AGENT_DIRECTORY_ROOT="$fixture_root" AGENT_CACHE_DIR="$fixture_cache_dir" \
    bash "$repo_root/tools/find-context.sh" --route knowledge --limit 5 -- '資本配分')"; then
    fail 'find-context.sh failed on context-search fixture'
  else
    printf '%s\n' "$result" | grep -Fq 'capital-allocation-current' || fail 'context search did not return active Knowledge'
    if printf '%s\n' "$result" | grep -Fq 'capital-allocation-old'; then
      fail 'context search returned superseded Knowledge by default'
    fi
    result_count="$(printf '%s\n' "$result" | tail -n +2 | grep -c . || true)"
    (( result_count <= 5 )) || fail 'context search returned more than 5 candidates'
  fi
  project_result="$(AGENT_DIRECTORY_ROOT="$fixture_root" AGENT_CACHE_DIR="$fixture_cache_dir" \
    bash "$repo_root/tools/find-context.sh" --route project --limit 5 -- '市場判断' || true)"
  printf '%s\n' "$project_result" | grep -Fq $'project\tproject\tactive\tmarket-review\t' || \
    fail 'context search did not return active Project'
  if printf '%s\n' "$project_result" | grep -Fq 'market-review-2025'; then
    fail 'context search returned completed Project by default'
  fi

  if command -v sqlite3 >/dev/null 2>&1 && \
    sqlite3 ':memory:' "CREATE VIRTUAL TABLE fts_probe USING fts5(body, tokenize='trigram');" >/dev/null 2>&1; then
    if ! AGENT_DIRECTORY_ROOT="$fixture_root" AGENT_CACHE_DIR="$sqlite_fixture_cache_dir" \
      AGENT_SQLITE_KNOWLEDGE_THRESHOLD=1 AGENT_SQLITE_CATALOG_THRESHOLD=1 \
      bash "$repo_root/tools/build-context-cache.sh" >/dev/null; then
      fail 'scale-triggered SQLite cache generation failed'
    elif [[ ! -f "$sqlite_fixture_cache_dir/search.sqlite" ]] || \
      ! grep -Fqx 'search_backend=sqlite-fts5' "$sqlite_fixture_cache_dir/cache.meta"; then
      fail 'scale threshold did not activate SQLite FTS5'
    elif [[ "$(sqlite3 "$sqlite_fixture_cache_dir/search.sqlite" 'PRAGMA integrity_check;')" != 'ok' ]]; then
      fail 'scale-triggered SQLite cache failed integrity_check'
    else
      sqlite_result="$(AGENT_DIRECTORY_ROOT="$fixture_root" AGENT_CACHE_DIR="$sqlite_fixture_cache_dir" \
        AGENT_SQLITE_KNOWLEDGE_THRESHOLD=1 AGENT_SQLITE_CATALOG_THRESHOLD=1 \
        bash "$repo_root/tools/find-context.sh" --route knowledge --limit 5 -- '投下先ごとの期待収益' || true)"
      printf '%s\n' "$sqlite_result" | grep -Fq 'capital-allocation-current' || \
        fail 'SQLite FTS5 did not retrieve body-only Japanese text'
      printf 'corrupted fixture' > "$sqlite_fixture_cache_dir/search.sqlite"
      recovery_result="$(AGENT_DIRECTORY_ROOT="$fixture_root" AGENT_CACHE_DIR="$sqlite_fixture_cache_dir" \
        AGENT_SQLITE_KNOWLEDGE_THRESHOLD=1 AGENT_SQLITE_CATALOG_THRESHOLD=1 \
        bash "$repo_root/tools/find-context.sh" --route knowledge --limit 5 -- '投下先ごとの期待収益' || true)"
      printf '%s\n' "$recovery_result" | grep -Fq 'capital-allocation-current' || \
        fail 'find-context.sh did not rebuild a corrupted SQLite cache'
    fi
  fi
fi

git_root=''
if git_root="$(git -C "$repo_root" rev-parse --show-toplevel 2>/dev/null)" && [[ "$git_root" == "$repo_root" ]]; then
  while IFS= read -r tracked_file; do
    case "$tracked_file" in
      .tmp/*|*/.tmp/*|.agent-cache/*|*/.agent-cache/*|.env*|*/.env*|.DS_Store|*/.DS_Store)
        if [[ "$tracked_file" != '.env.example' && "$tracked_file" != */.env.example ]]; then
          fail "forbidden tracked file: $tracked_file"
        fi
        ;;
    esac
  done < <(git -C "$repo_root" ls-files)

  if [[ -n "$base_ref" ]]; then
    if ! git -C "$repo_root" rev-parse --verify "$base_ref^{commit}" >/dev/null 2>&1; then
      fail "base ref does not resolve to a commit: $base_ref"
    else
      while IFS=$'\t' read -r status old_path new_path; do
        [[ -n "$status" ]] || continue
        case "$status" in
          A) ;;
          *) fail "immutable source changed relative to $base_ref: $status $old_path ${new_path:-}" ;;
        esac
      done < <(git -C "$repo_root" diff --name-status "$base_ref" -- knowledge/raw)
      while IFS=$'\t' read -r status old_path new_path; do
        [[ -n "$status" ]] || continue
        case "$status" in
          A) ;;
          *) fail "closed Knowledge log changed relative to $base_ref: $status $old_path ${new_path:-}" ;;
        esac
      done < <(git -C "$repo_root" diff --name-status "$base_ref" -- knowledge/wiki/logs)
      while IFS=$'\t' read -r status old_path new_path; do
        case "$status" in
          R*) fail "Project physical rename requires an approved migration map: $old_path -> $new_path" ;;
          D)
            case "$old_path" in
              projects/*/PROJECT.md) validate_deleted_project "$base_ref" "$old_path" ;;
            esac
            ;;
        esac
      done < <(git -C "$repo_root" diff --name-status "$base_ref" -- projects)
    fi
  fi
else
  printf 'SKIP: Git tracking and base-diff checks (directory is not a repository root)\n'
fi

if (( failures > 0 )); then
  printf 'FAILED: %d structural issue(s), %d warning(s)\n' "$failures" "$warnings" >&2
  exit 1
fi

printf 'PASS: agent-directory structure is valid (%d warning(s))\n' "$warnings"
