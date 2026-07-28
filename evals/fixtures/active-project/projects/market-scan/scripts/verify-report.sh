#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_dir="$(cd "${script_dir}/.." && pwd)"
report_path="${1:-${project_dir}/outputs/quarterly-report.md}"

test -s "$report_path"
grep -q '^## Summary$' "$report_path"
grep -q '^## Evidence$' "$report_path"
grep -q '^## Implications$' "$report_path"
grep -Eq '100|120|150' "$report_path"

printf 'PASS: %s satisfies the report contract\n' "$report_path"
