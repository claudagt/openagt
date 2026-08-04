#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_dir="$(cd "${script_dir}/.." && pwd)"
catalog_path="${1:-${project_dir}/outputs/component-catalog.md}"

test -s "$catalog_path"
grep -q '^## Tokens$' "$catalog_path"
grep -q '^## Primitives$' "$catalog_path"
grep -q '^## Patterns$' "$catalog_path"
grep -q '^## Usage$' "$catalog_path"

while IFS=, read -r product component layer contrast; do
  [[ "$product" == 'product' || -z "$component" ]] && continue
  grep -Fq "\`$component\`" "$catalog_path"
done < "${project_dir}/inputs/current-components.csv"

printf 'PASS: %s satisfies the catalog contract\n' "$catalog_path"
