#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
failures=0
warnings=0
strict=false
full=false
base_ref=''

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
  [[ -f "$file" ]] || return
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

validate_project_contract() {
  local project_file="$1"
  local criterion_heading mode name status description project_dir knowledge_required skill_required
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

  local external_decl_regex='^- 外部リポジトリ: `[^`]+`（作業clone: `[^`]+`。バックアップはこのリポジトリ側が持つ）$'
  local in_constraints decl_line
  while IFS=$'\t' read -r in_constraints decl_line; do
    [[ -n "$decl_line" ]] || continue
    if [[ "$in_constraints" != '1' ]]; then
      fail "$(relative_path "$project_file") declares an external repository outside ## 制約・固定決定"
    elif ! printf '%s\n' "$decl_line" | grep -Eq "$external_decl_regex"; then
      fail "$(relative_path "$project_file") has a malformed external repository declaration: $decl_line"
    fi
  done < <(awk '
    /^## / { in_section = ($0 == "## 制約・固定決定") }
    /^[[:space:]]*-/ && /外部リポジトリ/ { printf "%d\t%s\n", in_section, $0 }
  ' "$project_file")

  validate_declared_references "$project_file"
  validate_required_reference_statuses "$project_file"
  if [[ "$project_file" != "$repo_root/projects/_template/PROJECT.md" ]] && contains_template_placeholder "$project_file"; then
    fail "$(relative_path "$project_file") contains an unresolved placeholder"
  fi
}

validate_project_state() {
  local state_file="$1"
  local contract_targets verification_targets project_file target updated_at project_status project_mode criterion
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
  case "$filename" in
    README.md) ;;
    *[!a-z0-9.-]*|_*|*[A-Z]*) fail "$(relative_path "$page") filename must use lowercase kebab-case" ;;
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
      "$project_dir/" "$repo_root" 2>/dev/null || true)"
  else
    inbound_refs="$(grep -RIlF --exclude-dir=.git --exclude-dir=.agent-cache --exclude-dir=.tmp \
      "$project_dir/" "$repo_root" 2>/dev/null || true)"
  fi
  [[ -z "$inbound_refs" ]] || fail "deleted Project still has inbound reference(s): $project_dir"
}

required_files=(
  'AGENTS.md' 'README.md' 'knowledge/KNOWLEDGE.md' 'knowledge/wiki/index.md' 'knowledge/wiki/log.md'
  'skills/README.md' 'skills/_template/SKILL.md' 'projects/README.md' 'projects/LIFECYCLE.md' 'projects/RECOVERY.md'
  'projects/_template/PROJECT.md' 'projects/_template/STATE.md' 'evals/README.md' 'tools/README.md'
  'tools/BACKUP.md' 'tools/build-context-cache.sh' 'tools/find-context.sh' 'tools/append-knowledge-log.sh'
  'tools/backup-to-github.sh' 'tools/validate-agent-directory.sh'
  'knowledge/wiki/_template/source.md' 'knowledge/wiki/_template/topic.md'
)
for path in "${required_files[@]}"; do require_file "$repo_root/$path"; done

check_size "$repo_root/AGENTS.md" 12288 'AGENTS.md'
check_size "$repo_root/README.md" 32768 'README.md'
check_size "$repo_root/knowledge/KNOWLEDGE.md" 20480 'KNOWLEDGE.md'
check_size "$repo_root/skills/README.md" 12288 'skills README'
check_size "$repo_root/projects/README.md" 20480 'projects README'
check_size "$repo_root/evals/README.md" 24576 'evals README'
check_size "$repo_root/tools/README.md" 20480 'tools README'
check_size "$repo_root/tools/BACKUP.md" 20480 'tools BACKUP.md'
check_size "$repo_root/knowledge/wiki/index.md" 8192 'Knowledge index'
check_size "$repo_root/knowledge/wiki/log.md" 131072 'Knowledge log'
check_heading_warning "$repo_root/AGENTS.md" 20
check_heading_warning "$repo_root/knowledge/KNOWLEDGE.md" 30
check_heading_warning "$repo_root/skills/README.md" 30
check_heading_warning "$repo_root/projects/README.md" 30

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

validate_project_contract "$repo_root/projects/_template/PROJECT.md"
validate_project_state "$repo_root/projects/_template/STATE.md"
while IFS= read -r -d '' project_file; do
  [[ "$project_file" == "$repo_root/projects/_template/PROJECT.md" ]] && continue
  validate_project_contract "$project_file"
  validate_project_state "$(dirname "$project_file")/STATE.md"
done < <(find "$repo_root/projects" "$repo_root/evals/fixtures" -type f -name 'PROJECT.md' -print0)

validate_skill "$repo_root/skills/_template/SKILL.md"
while IFS= read -r -d '' skill_file; do
  [[ "$skill_file" == "$repo_root/skills/_template/SKILL.md" ]] && continue
  validate_skill "$skill_file"
done < <(find "$repo_root/skills" "$repo_root/evals/fixtures" -type f -name 'SKILL.md' -print0)

while IFS= read -r -d '' page; do
  case "$page" in */README.md) continue ;; esac
  validate_knowledge_page "$page"
done < <(find \
  "$repo_root/knowledge/wiki/sources" "$repo_root/knowledge/wiki/topics" \
  "$repo_root/evals/fixtures" -type f -name '*.md' \
  \( -path '*/knowledge/wiki/sources/*' -o -path '*/knowledge/wiki/topics/*' \) -print0)
validate_knowledge_page "$repo_root/knowledge/wiki/_template/source.md"
validate_knowledge_page "$repo_root/knowledge/wiki/_template/topic.md"

index_items="$(grep -Ec '^- ' "$repo_root/knowledge/wiki/index.md" || true)"
(( index_items <= 50 )) || fail 'knowledge/wiki/index.md has more than 50 route-map items'
if grep -Eq '^- .*knowledge/(raw|research)/|^## (raw|research)/' "$repo_root/knowledge/wiki/index.md"; then
  fail 'knowledge/wiki/index.md must not register raw/research as an itemized global ledger'
fi

log_records="$(grep -Ec '^[0-9]{4}-[0-9]{2}-[0-9]{2}[[:space:]]+' "$repo_root/knowledge/wiki/log.md" || true)"
(( log_records <= 1000 )) || fail 'knowledge/wiki/log.md has more than 1,000 records and must rotate'
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
  memory-canonical-first project-context-must-read project-correction-recovery project-finite-completion
  project-goal-change-protection project-state-closeout protect-immutable-records protect-paused-project
  route-to-knowledge route-to-project route-to-skill temporary-code-isolation project-delete-requires-retired
  knowledge-bounded-retrieval knowledge-superseded-redirect knowledge-original-escalation
  catalog-failure-fallback project-completed-not-default project-required-only context-budget-stop
  large-file-section-read ambiguous-target-no-broad-scan meta-route-validator-change
  knowledge-log-auto-rotation scale-sqlite-auto-enable
  backup-explicit-only backup-divergence-refusal restore-single-writer project-task-no-backup
  backup-external-repo-boundary external-repo-consolidation-default
)
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

  allowed_git_subcommands='cat-file config diff for-each-ref ls-files ls-remote merge-base push rev-list rev-parse symbolic-ref'
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

grep -Fq 'tools/backup-to-github.sh' "$repo_root/README.md" || \
  fail 'README.md does not register tools/backup-to-github.sh'
grep -Fq 'tools/BACKUP.md' "$repo_root/README.md" || fail 'README.md does not register tools/BACKUP.md'
grep -Fq 'backup-to-github.sh' "$repo_root/tools/README.md" || \
  fail 'tools/README.md does not register backup-to-github.sh'
grep -Fq 'BACKUP.md' "$repo_root/tools/README.md" || fail 'tools/README.md does not register BACKUP.md'
grep -Fq 'tools/BACKUP.md' "$repo_root/AGENTS.md" || \
  fail 'AGENTS.md does not delegate backup details to tools/BACKUP.md'

cache_test_dir="$(mktemp -d "${TMPDIR:-/tmp}/agent-validator-cache.XXXXXX")"
fixture_cache_dir="$(mktemp -d "${TMPDIR:-/tmp}/agent-validator-fixture.XXXXXX")"
sqlite_fixture_cache_dir="$(mktemp -d "${TMPDIR:-/tmp}/agent-validator-sqlite.XXXXXX")"
log_fixture_dir="$(mktemp -d "${TMPDIR:-/tmp}/agent-validator-log.XXXXXX")"
backup_fixture_dir="$(mktemp -d "${TMPDIR:-/tmp}/agent-validator-backup.XXXXXX")"
trap 'rm -rf "$cache_test_dir" "$fixture_cache_dir" "$sqlite_fixture_cache_dir" "$log_fixture_dir" "$backup_fixture_dir"' EXIT
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

mkdir -p "$log_fixture_dir/knowledge/wiki"
{
  printf '# log — fixture\n\n---\n\n'
  i=1
  while (( i <= 999 )); do
    printf '2026-08-02  lint        fixture/%04d  threshold fixture\n' "$i"
    i=$((i + 1))
  done
} > "$log_fixture_dir/knowledge/wiki/log.md"
if ! AGENT_DIRECTORY_ROOT="$log_fixture_dir" bash "$repo_root/tools/append-knowledge-log.sh" \
  --date 2026-08-02 --type lint --target fixture/1000 --summary 'threshold fixture' >/dev/null; then
  fail 'append-knowledge-log.sh failed at the 1,000-record threshold'
elif [[ ! -f "$log_fixture_dir/knowledge/wiki/logs/2026-Q3.md" ]]; then
  fail 'append-knowledge-log.sh did not create the expected quarterly archive'
elif [[ "$(grep -Ec '^[0-9]{4}-[0-9]{2}-[0-9]{2}[[:space:]]+' "$log_fixture_dir/knowledge/wiki/log.md" || true)" != '0' ]]; then
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
  backup_env=(
    HOME="$backup_fixture_dir" GIT_CONFIG_NOSYSTEM=1
    GIT_AUTHOR_NAME=fixture GIT_AUTHOR_EMAIL=fixture@example.invalid
    GIT_COMMITTER_NAME=fixture GIT_COMMITTER_EMAIL=fixture@example.invalid
  )
  backup_output=''
  backup_status=0

  backup_git() { env "${backup_env[@]}" git -C "$backup_work" "$@"; }
  backup_run() {
    set +e
    backup_output="$(env "${backup_env[@]}" AGENT_DIRECTORY_ROOT="$backup_work" bash "$backup_tool" "$@" 2>&1)"
    backup_status=$?
    set -e
  }
  backup_expect_blocked() {
    if (( backup_status == 0 )); then
      fail "backup fixture: $2 unexpectedly succeeded"
    elif ! printf '%s\n' "$backup_output" | grep -Fqx "BACKUP_BLOCKED reason=$1"; then
      fail "backup fixture: $2 did not report reason=$1"
    fi
  }
  backup_remote_sha() {
    env "${backup_env[@]}" git -C "$backup_remote_dir" rev-parse --verify --quiet refs/heads/main || true
  }

  env "${backup_env[@]}" git init -q --bare "$backup_remote_dir"
  env "${backup_env[@]}" git -C "$backup_remote_dir" symbolic-ref HEAD refs/heads/main
  env "${backup_env[@]}" git init -q "$backup_work"
  backup_git symbolic-ref HEAD refs/heads/main
  mkdir -p "$backup_work/tools"
  printf 'fixture agent directory\n' > "$backup_work/AGENTS.md"
  printf '.tmp/\n.agent-cache/\n.env*\n!.env.example\n.DS_Store\n' > "$backup_work/.gitignore"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$backup_work/tools/validate-agent-directory.sh"
  backup_git add -A
  backup_git commit -q -m 'fixture: initial commit'
  backup_git remote add backup "$backup_remote_dir"
  backup_head="$(backup_git rev-parse HEAD)"

  backup_run --remote backup --branch main --dry-run
  if (( backup_status != 0 )); then
    fail "backup fixture: dry run on a clean tree failed: $backup_output"
  elif ! printf '%s\n' "$backup_output" | grep -Fqx "BACKUP_READY remote=backup branch=main sha=$backup_head"; then
    fail 'backup fixture: dry run did not emit the BACKUP_READY result line'
  fi
  [[ -z "$(backup_remote_sha)" ]] || fail 'backup fixture: dry run wrote to the remote'

  backup_run
  if (( backup_status != 0 )); then
    fail "backup fixture: initial push on a clean tree failed: $backup_output"
  elif ! printf '%s\n' "$backup_output" | grep -Eq '^BACKUP_OK remote=backup branch=main sha=[0-9a-f]{40}$'; then
    fail 'backup fixture: successful backup did not emit the BACKUP_OK result line'
  elif ! printf '%s\n' "$backup_output" | grep -Fqx "BACKUP_OK remote=backup branch=main sha=$backup_head"; then
    fail 'backup fixture: BACKUP_OK reported a SHA other than local HEAD'
  fi
  [[ "$(backup_remote_sha)" == "$backup_head" ]] || \
    fail 'backup fixture: remote main does not match local HEAD after push'

  printf 'dirty\n' >> "$backup_work/AGENTS.md"
  backup_run
  backup_expect_blocked 'dirty-working-tree' 'uncommitted tracked change'
  backup_git checkout -q -- AGENTS.md

  printf 'staged\n' >> "$backup_work/AGENTS.md"
  backup_git add AGENTS.md
  backup_run
  backup_expect_blocked 'staged-changes' 'staged change'
  backup_git reset -q --hard HEAD

  printf 'stray\n' > "$backup_work/stray.md"
  backup_run
  backup_expect_blocked 'untracked-files' 'untracked non-ignored file'
  rm -f "$backup_work/stray.md"

  printf 'stashed\n' >> "$backup_work/AGENTS.md"
  backup_git stash push -q
  backup_run
  backup_expect_blocked 'stash-present' 'stash entry'
  backup_git stash drop -q

  mkdir -p "$backup_work/.tmp"
  printf 'scratch\n' > "$backup_work/.tmp/scratch"
  backup_git add -f .tmp/scratch
  backup_git commit -q -m 'fixture: forbidden path'
  backup_run
  backup_expect_blocked 'forbidden-tracked-file' 'tracked .tmp path'
  backup_git reset -q --hard HEAD~1
  rm -rf "$backup_work/.tmp"

  backup_git checkout -q -b stray-branch
  printf 'unreachable\n' > "$backup_work/unreachable.md"
  backup_git add -A
  backup_git commit -q -m 'fixture: unreachable commit'
  backup_git checkout -q main
  backup_run
  backup_expect_blocked 'unreachable-local-branch' 'commit unreachable from the backup branch'
  backup_git branch -q -D stray-branch

  printf '%04096d' 0 > "$backup_work/oversized.bin"
  backup_git add -A
  backup_git commit -q -m 'fixture: oversized blob'
  set +e
  backup_output="$(env "${backup_env[@]}" AGENT_DIRECTORY_ROOT="$backup_work" \
    AGENT_BACKUP_MAX_BLOB_BYTES=1024 bash "$backup_tool" 2>&1)"
  backup_status=$?
  set -e
  backup_expect_blocked 'oversized-git-object' 'blob above the size limit'
  printf '%s\n' "$backup_output" | grep -Fq 'oversized.bin' || \
    fail 'backup fixture: oversized object report does not name the path'
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
  backup_expect_blocked 'remote-diverged' 'diverged remote'
  printf '%s\n' "$backup_output" | grep -Eq "remote=$backup_sha_before_divergence local=[0-9a-f]{40}" || \
    fail 'backup fixture: divergence report does not name both the remote and local SHA'
  [[ "$(backup_remote_sha)" == "$backup_sha_before_divergence" ]] || \
    fail 'backup fixture: remote changed while divergence was reported'
  backup_run --dry-run
  backup_expect_blocked 'remote-diverged' 'diverged remote in dry run'
  [[ "$(backup_remote_sha)" == "$backup_sha_before_divergence" ]] || \
    fail 'backup fixture: dry run changed the remote'

  [[ -z "$(backup_git status --porcelain)" ]] || \
    fail 'backup fixture: the backup tool left the working tree modified'
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
      done < <(git -C "$repo_root" diff --name-status "$base_ref" -- knowledge/raw knowledge/research)
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
