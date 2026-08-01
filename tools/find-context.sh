#!/usr/bin/env bash
set -euo pipefail

tool_root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="${AGENT_DIRECTORY_ROOT:-$(cd "$tool_root/.." && pwd)}"
cache_dir="${AGENT_CACHE_DIR:-$repo_root/.agent-cache}"
route=''
limit=5
include_inactive=false

usage() {
  printf 'Usage: %s --route knowledge|skill|project|meta [--limit 1..5] [--include-inactive] -- <query>\n' "${0##*/}" >&2
}

while (( $# > 0 )); do
  case "$1" in
    --route)
      [[ $# -ge 2 ]] || { usage; exit 2; }
      route="$2"
      shift 2
      ;;
    --limit)
      [[ $# -ge 2 ]] || { usage; exit 2; }
      limit="$2"
      shift 2
      ;;
    --include-inactive)
      include_inactive=true
      shift
      ;;
    --)
      shift
      break
      ;;
    *)
      break
      ;;
  esac
done

case "$route" in knowledge|skill|project|meta) ;; *) usage; exit 2 ;; esac
if [[ ! "$limit" =~ ^[1-5]$ ]]; then
  printf 'ERROR: --limit must be an integer from 1 to 5\n' >&2
  exit 2
fi
query="$*"
if [[ -z "$query" || "$query" == *$'\t'* || "$query" == *$'\n'* ]]; then
  printf 'ERROR: query must be one non-empty line without tabs\n' >&2
  exit 2
fi

cache_current=true
if ! AGENT_DIRECTORY_ROOT="$repo_root" AGENT_CACHE_DIR="$cache_dir" \
  bash "$tool_root/build-context-cache.sh" --check-routing >/dev/null 2>&1; then
  cache_current=false
elif [[ ! -f "$cache_dir/cache.meta" ]]; then
  cache_current=false
else
  configured_backend="$(sed -n 's/^search_backend=//p' "$cache_dir/cache.meta" | head -n 1)"
  case "$configured_backend" in
    lexical|rg-fallback) ;;
    sqlite-fts5)
      if [[ ! -f "$cache_dir/search.sqlite" ]] || ! command -v sqlite3 >/dev/null 2>&1 || \
        [[ "$(sqlite3 "$cache_dir/search.sqlite" 'PRAGMA integrity_check;' 2>/dev/null || true)" != 'ok' ]]; then
        cache_current=false
      fi
      ;;
    *) cache_current=false ;;
  esac
fi
if [[ "$cache_current" != true ]]; then
  AGENT_DIRECTORY_ROOT="$repo_root" AGENT_CACHE_DIR="$cache_dir" \
    bash "$tool_root/build-context-cache.sh" >/dev/null
fi

catalog="$cache_dir/catalog.tsv"
tmp_root="$(mktemp -d "${TMPDIR:-/tmp}/agent-context-query.XXXXXX")"
trap 'rm -rf "$tmp_root"' EXIT
ranked="$tmp_root/ranked.tsv"

awk -F '\t' -v route="$route" -v query="$query" -v include_inactive="$include_inactive" '
  BEGIN { q = tolower(query) }
  NR == 1 { next }
  $1 != route { next }
  include_inactive != "true" && $3 != "active" { next }
  {
    name = tolower($4)
    aliases = tolower($5)
    description = tolower($6)
    path = tolower($8)
    score = 99
    if (name == q) {
      score = 0
    } else {
      count = split(aliases, alias, "|")
      for (i = 1; i <= count; i++) {
        if (alias[i] == q) score = 1
      }
      if (score == 99 && index(name " " aliases " " description " " path, q) > 0) score = 2
    }
    if (score < 99) {
      if (include_inactive == "true" && $3 != "active") score += 10
      print score "\t" $0
    }
  }
' "$catalog" | LC_ALL=C sort -t $'\t' -k1,1n -k9,9 > "$ranked"

if [[ ! -s "$ranked" && -f "$cache_dir/cache.meta" && -f "$cache_dir/search.sqlite" ]] && \
  grep -Fqx 'search_backend=sqlite-fts5' "$cache_dir/cache.meta" && command -v sqlite3 >/dev/null 2>&1; then
  match_query="\"${query//\"/\"\"}\""
  q_match="$(printf '%s' "$match_query" | sed "s/'/''/g")"
  q_route="$(printf '%s' "$route" | sed "s/'/''/g")"
  status_clause="AND status = 'active'"
  if [[ "$include_inactive" == true ]]; then
    status_clause=''
  fi
  sqlite_query="SELECT CASE WHEN status = 'active' THEN 3 ELSE 13 END, area, kind, status, name, aliases, description, mode, path, content_hash FROM search WHERE area = '$q_route' $status_clause AND search MATCH '$q_match' ORDER BY CASE WHEN status = 'active' THEN 0 ELSE 1 END, bm25(search), path LIMIT $limit;"
  if ! sqlite3 -tabs -noheader "$cache_dir/search.sqlite" "$sqlite_query" > "$ranked" 2>/dev/null; then
    : > "$ranked"
  fi
fi

if [[ ! -s "$ranked" ]]; then
  while IFS=$'\x1f' read -r area kind status name aliases description item_mode path hash; do
    [[ "$area" == "$route" ]] || continue
    if [[ "$include_inactive" != true && "$status" != 'active' ]]; then
      continue
    fi
    file="$repo_root/$path"
    [[ -f "$file" ]] || continue
    if command -v rg >/dev/null 2>&1; then
      rg -qi --fixed-strings -- "$query" "$file" || continue
    else
      grep -Fqi -- "$query" "$file" || continue
    fi
    fallback_score=3
    if [[ "$include_inactive" == true && "$status" != 'active' ]]; then
      fallback_score=13
    fi
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
      "$fallback_score" \
      "$area" "$kind" "$status" "$name" "$aliases" "$description" "$item_mode" "$path" "$hash" >> "$ranked"
  done < <(tail -n +2 "$catalog" | awk -F '\t' 'BEGIN { OFS = sprintf("%c", 31) } { print $1,$2,$3,$4,$5,$6,$7,$8,$9 }')
  LC_ALL=C sort -t $'\t' -k1,1n -k9,9 "$ranked" -o "$ranked"
fi

printf 'area\tkind\tstatus\tname\taliases\tdescription\tmode\tpath\n'
head -n "$limit" "$ranked" | cut -f2-9
