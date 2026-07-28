#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_dir="$(cd "${script_dir}/.." && pwd)"
summary_path="${1:-${project_dir}/outputs/migration-summary.md}"

test -s "$summary_path"
grep -q '^## Migration Targets$' "$summary_path"
grep -q '^## Verification$' "$summary_path"
grep -q '^## Remaining Issues$' "$summary_path"

while IFS= read -r route; do
  [[ -z "$route" ]] || grep -Fq -- "$route" "$summary_path"
done < "${project_dir}/inputs/routes.txt"

printf 'PASS: %s satisfies the finite project contract\n' "$summary_path"
