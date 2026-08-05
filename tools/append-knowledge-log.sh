#!/usr/bin/env bash
set -euo pipefail

tool_root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="${AGENT_DIRECTORY_ROOT:-$(cd "$tool_root/.." && pwd)}"
log_file="$repo_root/knowledge/wiki/LOG.md"
record_date="$(date +%F)"
record_type=''
record_target=''
record_summary=''

usage() {
  printf 'Usage: %s --type <type> --target <path> --summary <text> [--date YYYY-MM-DD]\n' "${0##*/}" >&2
}

while (( $# > 0 )); do
  case "$1" in
    --date|--type|--target|--summary)
      [[ $# -ge 2 ]] || { usage; exit 2; }
      case "$1" in
        --date) record_date="$2" ;;
        --type) record_type="$2" ;;
        --target) record_target="$2" ;;
        --summary) record_summary="$2" ;;
      esac
      shift 2
      ;;
    *) usage; exit 2 ;;
  esac
done

if [[ ! "$record_date" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
  printf 'ERROR: --date must use YYYY-MM-DD\n' >&2
  exit 2
fi
# 形だけでなく範囲も検査する。範囲外の月はQ5のような不正なarchive名を作る。
date_month=$(( 10#${record_date:5:2} ))
date_day=$(( 10#${record_date:8:2} ))
if (( date_month < 1 || date_month > 12 || date_day < 1 || date_day > 31 )); then
  printf 'ERROR: --date has an out-of-range month or day: %s\n' "$record_date" >&2
  exit 2
fi
case "$record_type" in
  ingest|lint|migration|supersede|archive|retire) ;;
  *) printf 'ERROR: unsupported log type: %s\n' "$record_type" >&2; exit 2 ;;
esac
for value in "$record_target" "$record_summary"; do
  if [[ -z "$value" || "$value" == *$'\t'* || "$value" == *$'\n'* || "$value" == *$'\r'* ]]; then
    printf 'ERROR: target and summary must be non-empty single-line values without tabs\n' >&2
    exit 2
  fi
done
if [[ ! -f "$log_file" ]] || ! grep -Fqx -- '---' "$log_file"; then
  printf 'ERROR: Knowledge log is missing or has no header separator: %s\n' "$log_file" >&2
  exit 1
fi

printf '%s  %-10s  %s  %s\n' "$record_date" "$record_type" "$record_target" "$record_summary" >> "$log_file"

record_count="$(grep -Ec '^[0-9]{4}-[0-9]{2}-[0-9]{2}[[:space:]]+' "$log_file" || true)"
size_bytes="$(wc -c < "$log_file" | tr -d ' ')"
printf 'APPENDED: %s %s\n' "$record_date" "$record_target"

if (( record_count < 1000 && size_bytes < 131072 )); then
  exit 0
fi

year="${record_date:0:4}"
month="${record_date:5:2}"
quarter=$(( (10#$month - 1) / 3 + 1 ))
archive_dir="$repo_root/knowledge/wiki/logs"
mkdir -p "$archive_dir"
archive_file="$archive_dir/${year}-Q${quarter}.md"
sequence=2
while [[ -e "$archive_file" ]]; do
  archive_file="$archive_dir/${year}-Q${quarter}-$(printf '%02d' "$sequence").md"
  sequence=$((sequence + 1))
done

cp "$log_file" "$archive_file"
fresh_log="$(mktemp "$repo_root/knowledge/wiki/.log-current.XXXXXX")"
trap 'rm -f "$fresh_log"' EXIT
awk '{ print } $0 == "---" { exit }' "$log_file" > "$fresh_log"
mv "$fresh_log" "$log_file"
trap - EXIT

printf 'ROTATED: %s (%d records, %d bytes)\n' "${archive_file#"$repo_root"/}" "$record_count" "$size_bytes"
