#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
failures=0
strict=false

case "${1:-}" in
  '')
    ;;
  --strict)
    strict=true
    ;;
  *)
    printf 'Usage: %s [--strict]\n' "${0##*/}" >&2
    exit 2
    ;;
esac

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  failures=$((failures + 1))
}

require_file() {
  if [[ ! -f "$1" ]]; then
    fail "missing file: ${1#"$repo_root"/}"
  fi
}

require_fixed_line() {
  local file="$1"
  local line="$2"

  if [[ -f "$file" ]] && ! grep -Fqx -- "$line" "$file"; then
    fail "${file#"$repo_root"/} is missing: $line"
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

contains_template_placeholder() {
  grep -Fqf <(
    grep -Eho '<[^>]+>' \
      "$repo_root/projects/_template/PROJECT.md" \
      "$repo_root/projects/_template/STATE.md"
  ) "$1"
}

has_valid_project_criteria() {
  awk -v heading="$2" '
    /^## / {
      in_section = ($0 == heading)
      next
    }
    in_section && /^- / {
      has_item = 1
      if ($0 !~ /^- \*\*PC-(0[1-9]|[1-9][0-9])\*\* .+/) {
        invalid = 1
        next
      }
      id = substr($0, 5, 5)
      if (seen[id]++) {
        invalid = 1
      }
    }
    /^- \*\*PC-/ && !in_section {
      invalid = 1
    }
    END {
      exit !(has_item && !invalid)
    }
  ' "$1"
}

state_section_targets() {
  awk -v heading="$2" -v prefix="$3" '
    $0 == heading {
      in_section = 1
      next
    }
    in_section && /^## / {
      exit
    }
    in_section && index($0, prefix) == 1 {
      target = $0
      sub(/^.*PROJECT\.md#/, "", target)
      sub(/`$/, "", target)
      if (target ~ /^(PC-(0[1-9]|[1-9][0-9])|status)$/) {
        print target
      }
    }
  ' "$1"
}

validate_project_contract() {
  local project_file="$1"
  local heading
  local criterion_heading
  local mode
  local name
  local status
  local headings=(
    '## 目的'
    '## 判断原則'
    '## 非ゴール'
    '## 制約・固定決定'
    '## 品質基準'
    '## 入力'
    '## 使用するKnowledge'
    '## 使用するSkill'
    '## 成果物'
    '## 検証方法'
  )

  require_file "$project_file"
  [[ -f "$project_file" ]] || return

  if ! has_closed_frontmatter "$project_file"; then
    fail "${project_file#"$repo_root"/} has invalid YAML frontmatter boundaries"
  fi

  name="$(frontmatter_value "$project_file" 'name')"
  status="$(frontmatter_value "$project_file" 'status')"
  mode="$(frontmatter_value "$project_file" 'mode')"

  [[ -n "$name" ]] || fail "${project_file#"$repo_root"/} has a missing name"
  case "$status" in
    active|paused|completed|retired) ;;
    *) fail "${project_file#"$repo_root"/} has an invalid or missing status" ;;
  esac
  case "$mode" in
    finite|continuous) ;;
    *) fail "${project_file#"$repo_root"/} has an invalid or missing mode" ;;
  esac

  if ! grep -Eq '^> .+' "$project_file"; then
    fail "${project_file#"$repo_root"/} is missing a one-line goal or continuous mission"
  fi

  for heading in "${headings[@]}"; do
    require_fixed_line "$project_file" "$heading"
  done

  case "$mode" in
    finite)
      criterion_heading='## 完了条件'
      require_fixed_line "$project_file" '## 最終ゴール'
      require_fixed_line "$project_file" '## 完了条件'
      if grep -Fqx '## 継続的使命' "$project_file" ||
        grep -Fqx '## 成功指標' "$project_file" ||
        grep -Fqx '## 見直し・終了条件' "$project_file"; then
        fail "${project_file#"$repo_root"/} mixes finite and continuous contracts"
      fi
      ;;
    continuous)
      criterion_heading='## 成功指標'
      require_fixed_line "$project_file" '## 継続的使命'
      require_fixed_line "$project_file" '## 成功指標'
      require_fixed_line "$project_file" '## 見直し・終了条件'
      if grep -Fqx '## 最終ゴール' "$project_file" ||
        grep -Fqx '## 完了条件' "$project_file"; then
        fail "${project_file#"$repo_root"/} mixes finite and continuous contracts"
      fi
      if [[ "$status" == 'completed' ]]; then
        fail "${project_file#"$repo_root"/} cannot complete a continuous project"
      fi
      ;;
  esac

  if ! has_valid_project_criteria "$project_file" "$criterion_heading"; then
    fail "${project_file#"$repo_root"/} must use unique PC-xx bullets only in $criterion_heading"
  fi

  if [[ "$project_file" != "$repo_root/projects/_template/PROJECT.md" ]] &&
    contains_template_placeholder "$project_file"; then
    fail "${project_file#"$repo_root"/} contains an unresolved placeholder"
  fi
}

validate_project_state() {
  local state_file="$1"
  local contract_targets
  local heading
  local project_file
  local target
  local updated_at
  local verification_targets
  local headings=(
    '## 現在の到達点'
    '## 現在の目標'
    '## 目標の合格条件'
    '## 検証結果'
    '## 未完了・ブロッカー'
    '## 現在有効な決定'
    '## 失敗・却下済み'
    '## 次の一手'
  )

  require_file "$state_file"
  [[ -f "$state_file" ]] || return

  if ! has_closed_frontmatter "$state_file"; then
    fail "${state_file#"$repo_root"/} has invalid YAML frontmatter boundaries"
  fi

  updated_at="$(frontmatter_value "$state_file" 'updated_at')"
  if [[ "$state_file" == "$repo_root/projects/_template/STATE.md" ]]; then
    if [[ "$updated_at" != '<YYYY-MM-DD>' ]]; then
      fail "${state_file#"$repo_root"/} has an invalid updated_at placeholder"
    fi
  elif [[ ! "$updated_at" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
    fail "${state_file#"$repo_root"/} has a missing updated_at value"
  fi

  for heading in "${headings[@]}"; do
    require_fixed_line "$state_file" "$heading"
  done

  project_file="$(dirname "$state_file")/PROJECT.md"
  contract_targets="$(state_section_targets "$state_file" '## 現在の目標' '対象契約: `PROJECT.md#')"
  if [[ "$(wc -l <<<"$contract_targets" | tr -d ' ')" != '1' || -z "$contract_targets" ]]; then
    fail "${state_file#"$repo_root"/} must name one current target as PROJECT.md#PC-xx or PROJECT.md#status"
  fi
  verification_targets="$(state_section_targets "$state_file" '## 検証結果' '- 対象: `PROJECT.md#')"
  if [[ -z "$verification_targets" ]]; then
    fail "${state_file#"$repo_root"/} verification results must reference PROJECT.md#PC-xx or PROJECT.md#status"
  fi

  for target in $contract_targets $verification_targets; do
    case "$target" in
      status) ;;
      PC-*)
        if [[ -f "$project_file" ]] && ! grep -Fq -- "**$target**" "$project_file"; then
          fail "${state_file#"$repo_root"/} references missing PROJECT.md#$target"
        fi
        ;;
    esac
  done

  if [[ "$state_file" != "$repo_root/projects/_template/STATE.md" ]] &&
    contains_template_placeholder "$state_file"; then
    fail "${state_file#"$repo_root"/} contains an unresolved placeholder"
  fi
}

required_root_files=(
  'AGENTS.md'
  'README.md'
  'knowledge/KNOWLEDGE.md'
  'skills/README.md'
  'projects/README.md'
  'projects/_template/PROJECT.md'
  'projects/_template/STATE.md'
  'evals/README.md'
)

for relative_path in "${required_root_files[@]}"; do
  require_file "$repo_root/$relative_path"
done

if [[ "$strict" == true ]] &&
  grep -Eq '<agent-name>|<agent-role>|<agent-mission>|<agent-vision>|<project-dir>' "$repo_root/AGENTS.md"; then
  fail 'AGENTS.md contains unresolved agent definition placeholders'
fi

while IFS= read -r -d '' project_dir; do
  validate_project_contract "$project_dir/PROJECT.md"
  validate_project_state "$project_dir/STATE.md"
done < <(
  find "$repo_root/projects" -mindepth 1 -maxdepth 1 -type d -print0
)

while IFS= read -r -d '' fixture_dir; do
  if [[ "$(basename "$(dirname "$fixture_dir")")" == 'projects' ]]; then
    validate_project_contract "$fixture_dir/PROJECT.md"
    validate_project_state "$fixture_dir/STATE.md"
  fi
done < <(
  find "$repo_root/evals/fixtures" -type d -print0
)

required_cases=(
  'project-context-must-read'
  'project-goal-change-protection'
  'project-state-closeout'
  'project-correction-recovery'
  'project-finite-completion'
)

for case_name in "${required_cases[@]}"; do
  require_file "$repo_root/evals/cases/$case_name.yaml"
done

while IFS= read -r -d '' case_file; do
  require_fixed_line "$case_file" 'request: |'
  require_fixed_line "$case_file" 'expect:'

  if ! grep -Eq '^name: [a-z0-9-]+$' "$case_file"; then
    fail "${case_file#"$repo_root"/} has an invalid or missing name"
  fi
  if ! grep -Eq '^  route: (knowledge|skill|project|none)([[:space:]]|$)' "$case_file"; then
    fail "${case_file#"$repo_root"/} has an invalid or missing route"
  fi
  if ! grep -Fq '  must_read:' "$case_file"; then
    fail "${case_file#"$repo_root"/} is missing must_read"
  fi

  if grep -Eq '^  route: project([[:space:]]|$)' "$case_file"; then
    if ! grep -Eq '    - projects/.+/PROJECT\.md' "$case_file"; then
      fail "${case_file#"$repo_root"/} does not require the target PROJECT.md"
    fi
    if ! grep -Eq '    - projects/.+/STATE\.md' "$case_file"; then
      fail "${case_file#"$repo_root"/} does not require the target STATE.md"
    fi
  fi

  fixture_name="$(sed -n 's/^fixture: //p' "$case_file" | head -n 1)"
  if [[ -n "$fixture_name" && ! -d "$repo_root/evals/fixtures/$fixture_name" ]]; then
    fail "${case_file#"$repo_root"/} references missing fixture: $fixture_name"
  fi
done < <(find "$repo_root/evals/cases" -type f -name '*.yaml' -print0)

if ! grep -Eq '    - projects/.+/STATE\.md#現在の目標=.+' \
  "$repo_root/evals/cases/project-state-closeout.yaml"; then
  fail 'project-state-closeout does not require advancing the current goal'
fi
if ! grep -Fq 'projects/site-migration/PROJECT.md#status=completed' \
  "$repo_root/evals/cases/project-finite-completion.yaml"; then
  fail 'project-finite-completion does not require status=completed'
fi
if ! grep -Fq 'projects/site-migration/STATE.md#現在の目標=なし（Project完了）' \
  "$repo_root/evals/cases/project-finite-completion.yaml"; then
  fail 'project-finite-completion does not close the current goal'
fi

duplicate_case_names="$(
  sed -n 's/^name: //p' "$repo_root"/evals/cases/*.yaml | sort | uniq -d
)"
if [[ -n "$duplicate_case_names" ]]; then
  fail "duplicate eval case names: $duplicate_case_names"
fi

git_root=''
if git_root="$(git -C "$repo_root" rev-parse --show-toplevel 2>/dev/null)" &&
  [[ "$git_root" == "$repo_root" ]]; then
  while IFS= read -r tracked_file; do
    case "$tracked_file" in
      .tmp/*|*/.tmp/*|.env*|*/.env*|.DS_Store|*/.DS_Store)
        if [[ "$tracked_file" != '.env.example' && "$tracked_file" != */.env.example ]]; then
          fail "forbidden tracked file: $tracked_file"
        fi
        ;;
    esac
  done < <(git -C "$repo_root" ls-files)
else
  printf 'SKIP: Git tracking check (directory is not a repository root)\n'
fi

if (( failures > 0 )); then
  printf 'FAILED: %d structural issue(s)\n' "$failures" >&2
  exit 1
fi

printf 'PASS: agent-directory structure is valid\n'
