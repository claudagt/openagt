#!/usr/bin/env bash
set -euo pipefail

tool_root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="${AGENT_DIRECTORY_ROOT:-$(cd "$tool_root/.." && pwd)}"
cache_dir="${AGENT_CACHE_DIR:-$repo_root/.agent-cache}"
sqlite_knowledge_threshold="${AGENT_SQLITE_KNOWLEDGE_THRESHOLD:-1000}"
sqlite_catalog_threshold="${AGENT_SQLITE_CATALOG_THRESHOLD:-5000}"
mode='build'

case "${1:-}" in
  '') ;;
  --check) mode='check' ;;
  --check-routing) mode='check-routing' ;;
  *)
    printf 'Usage: %s [--check|--check-routing]\n' "${0##*/}" >&2
    exit 2
    ;;
esac

if [[ ! -d "$repo_root" ]]; then
  printf 'ERROR: repository root does not exist: %s\n' "$repo_root" >&2
  exit 2
fi
if [[ ! "$sqlite_knowledge_threshold" =~ ^[1-9][0-9]*$ || ! "$sqlite_catalog_threshold" =~ ^[1-9][0-9]*$ ]]; then
  printf 'ERROR: SQLite thresholds must be positive integers\n' >&2
  exit 2
fi

tmp_root="$(mktemp -d "${TMPDIR:-/tmp}/agent-context-cache.XXXXXX")"
trap 'rm -rf "$tmp_root"' EXIT
generated_dir="$tmp_root/generated"
mkdir -p "$generated_dir"

frontmatter_value() {
  local file="$1"
  local key="$2"
  awk -v key="$key" '
    NR == 1 && $0 != "---" { exit }
    NR > 1 && $0 == "---" { exit }
    index($0, key ":") == 1 {
      sub(/^[^:]+:[[:space:]]*/, "")
      print
      exit
    }
  ' "$file"
}

clean_field() {
  LC_ALL=C tr '\t\r\n' '   ' | sed -E 's/[[:space:]]+/ /g; s/^ //; s/ $//'
}

normalize_aliases() {
  sed -E 's/^\[//; s/\]$//; s/"//g; s/[[:space:]]*,[[:space:]]*/|/g' | clean_field
}

content_hash() {
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | awk '{print $1}'
  else
    cksum "$1" | awk '{print $1 "-" $2}'
  fi
}

stream_hash() {
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 | awk '{print $1}'
  else
    cksum | awk '{print $1 "-" $2}'
  fi
}

sql_quote() {
  sed "s/'/''/g"
}

catalog_unsorted="$tmp_root/catalog.unsorted"
printf 'area\tkind\tstatus\tname\taliases\tdescription\tmode\tpath\tcontent_hash\n' > "$catalog_unsorted"

append_catalog() {
  local area="$1"
  local kind="$2"
  local status="$3"
  local name="$4"
  local aliases="$5"
  local description="$6"
  local item_mode="$7"
  local file="$8"
  local relative_path="${file#"$repo_root"/}"
  local hash

  [[ -f "$file" ]] || return 0
  hash="$(content_hash "$file")"
  name="$(printf '%s' "$name" | clean_field)"
  aliases="$(printf '%s' "$aliases" | normalize_aliases)"
  description="$(printf '%s' "$description" | clean_field)"
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$area" "$kind" "$status" "$name" "$aliases" "$description" "$item_mode" "$relative_path" "$hash" \
    >> "$catalog_unsorted"
}

append_frontmatter_item() {
  local area="$1"
  local kind="$2"
  local file="$3"
  local name status aliases description item_mode

  name="$(frontmatter_value "$file" 'name')"
  status="$(frontmatter_value "$file" 'status')"
  aliases="$(frontmatter_value "$file" 'aliases')"
  description="$(frontmatter_value "$file" 'description')"
  item_mode="$(frontmatter_value "$file" 'mode')"

  if [[ "$area" == 'knowledge' ]]; then
    name="${file##*/}"
    name="${name%.md}"
    description="$(frontmatter_value "$file" 'summary')"
  fi

  [[ -n "$name" && -n "$status" ]] || return
  append_catalog "$area" "$kind" "$status" "$name" "$aliases" "$description" "$item_mode" "$file"
}

meta_files=(
  'AGENTS.md|root-policy|最上位規約とContext Loading Contract'
  'README.md|overview|人間向けの導入と全体像'
  'knowledge/KNOWLEDGE.md|knowledge-policy|Knowledge運用規約'
  'skills/README.md|skill-policy|Skill運用規約'
  'projects/README.md|project-policy|Project運用規約'
  'projects/LIFECYCLE.md|project-lifecycle|Projectの状態遷移と削除条件'
  'projects/RECOVERY.md|project-recovery|Projectの目的不一致からの復旧'
  'evals/README.md|eval-policy|振る舞いEvalの規約'
  'tools/README.md|tool-policy|構造保守Toolの規約'
)

for entry in "${meta_files[@]}"; do
  IFS='|' read -r path name description <<< "$entry"
  append_catalog 'meta' 'policy' 'active' "$name" '' "$description" '' "$repo_root/$path"
done

for directory in "$repo_root/knowledge/wiki/sources" "$repo_root/knowledge/wiki/topics"; do
  [[ -d "$directory" ]] || continue
  while IFS= read -r -d '' file; do
    [[ "${file##*/}" == 'README.md' ]] && continue
    append_frontmatter_item 'knowledge' 'wiki' "$file"
  done < <(find "$directory" -type f -name '*.md' -print0)
done

if [[ -d "$repo_root/skills" ]]; then
  while IFS= read -r -d '' file; do
    [[ "$file" == "$repo_root/skills/_template/"* ]] && continue
    append_frontmatter_item 'skill' 'skill' "$file"
  done < <(find "$repo_root/skills" -mindepth 2 -maxdepth 2 -type f -name 'SKILL.md' -print0)
fi

if [[ -d "$repo_root/projects" ]]; then
  while IFS= read -r -d '' file; do
    [[ "$file" == "$repo_root/projects/_template/"* ]] && continue
    append_frontmatter_item 'project' 'project' "$file"
  done < <(find "$repo_root/projects" -mindepth 2 -maxdepth 2 -type f -name 'PROJECT.md' -print0)
fi

catalog="$generated_dir/catalog.tsv"
head -n 1 "$catalog_unsorted" > "$catalog"
tail -n +2 "$catalog_unsorted" | LC_ALL=C sort -t $'\t' -k8,8 >> "$catalog"

if [[ "$mode" == 'check-routing' ]]; then
  if [[ -f "$cache_dir/catalog.tsv" ]] && cmp -s "$catalog" "$cache_dir/catalog.tsv"; then
    printf 'PASS: routing catalog is current\n'
    exit 0
  fi
  printf 'STALE: routing catalog must be regenerated\n' >&2
  exit 1
fi

catalog_rows="$(tail -n +2 "$catalog" | grep -c . || true)"
knowledge_rows="$(awk -F '\t' 'NR > 1 && $1 == "knowledge" { count++ } END { print count + 0 }' "$catalog")"
search_backend='lexical'

if (( knowledge_rows >= sqlite_knowledge_threshold || catalog_rows >= sqlite_catalog_threshold )); then
  if command -v sqlite3 >/dev/null 2>&1 && \
    sqlite3 ':memory:' "CREATE VIRTUAL TABLE fts_probe USING fts5(body, tokenize='trigram');" >/dev/null 2>&1; then
    sqlite_sql="$tmp_root/search.sql"
    {
      printf 'PRAGMA journal_mode=OFF;\nPRAGMA synchronous=OFF;\nBEGIN;\n'
      printf "CREATE VIRTUAL TABLE search USING fts5(area UNINDEXED, kind UNINDEXED, status UNINDEXED, name, aliases, description, mode UNINDEXED, path UNINDEXED, content_hash UNINDEXED, body, tokenize='trigram');\n"
      while IFS=$'\x1f' read -r area kind status name aliases description item_mode path hash; do
        [[ "$area" == 'area' ]] && continue
        absolute_path="$repo_root/$path"
        [[ -f "$absolute_path" ]] || continue
        q_area="$(printf '%s' "$area" | sql_quote)"
        q_kind="$(printf '%s' "$kind" | sql_quote)"
        q_status="$(printf '%s' "$status" | sql_quote)"
        q_name="$(printf '%s' "$name" | sql_quote)"
        q_aliases="$(printf '%s' "$aliases" | sql_quote)"
        q_description="$(printf '%s' "$description" | sql_quote)"
        q_mode="$(printf '%s' "$item_mode" | sql_quote)"
        q_path="$(printf '%s' "$path" | sql_quote)"
        q_hash="$(printf '%s' "$hash" | sql_quote)"
        q_absolute_path="$(printf '%s' "$absolute_path" | sql_quote)"
        printf "INSERT INTO search VALUES('%s','%s','%s','%s','%s','%s','%s','%s','%s',CAST(readfile('%s') AS TEXT));\n" \
          "$q_area" "$q_kind" "$q_status" "$q_name" "$q_aliases" "$q_description" "$q_mode" "$q_path" "$q_hash" "$q_absolute_path"
      done < <(awk -F '\t' 'BEGIN { OFS = sprintf("%c", 31) } { print $1,$2,$3,$4,$5,$6,$7,$8,$9 }' "$catalog")
      printf 'COMMIT;\n'
    } > "$sqlite_sql"
    sqlite3 "$generated_dir/search.sqlite" < "$sqlite_sql" >/dev/null
    if [[ "$(sqlite3 "$generated_dir/search.sqlite" 'PRAGMA integrity_check;')" != 'ok' ]]; then
      printf 'ERROR: generated SQLite search index failed integrity_check\n' >&2
      exit 1
    fi
    search_backend='sqlite-fts5'
  else
    search_backend='rg-fallback'
    printf 'WARN: scale threshold reached, but sqlite3 with FTS5 trigram is unavailable; using lexical fallback\n' >&2
  fi
fi

routeable_paths="$tmp_root/routeable.paths"
tail -n +2 "$catalog" | awk -F '\t' '{print $8}' | LC_ALL=C sort -u > "$routeable_paths"

manifest_unsorted="$tmp_root/manifest.unsorted"
printf 'path\tkind\tsize_bytes\tcontent_hash\trouteable\timmutable\n' > "$manifest_unsorted"

while IFS= read -r -d '' file; do
  relative_path="${file#"$repo_root"/}"
  case "$relative_path" in
    .git/*|*/.git/*|.agent-cache/*|*/.agent-cache/*|.tmp/*|*/.tmp/*|.DS_Store|*/.DS_Store|.env|.env.*|*/.env|*/.env.*)
      [[ "$relative_path" == '.env.example' || "$relative_path" == */.env.example ]] || continue
      ;;
  esac

  kind='file'
  immutable='false'
  case "$relative_path" in
    knowledge/raw/*) kind='raw'; immutable='true' ;;
    knowledge/research/*) kind='research'; immutable='true' ;;
    knowledge/wiki/logs/*) kind='closed-log'; immutable='true' ;;
    knowledge/wiki/sources/*|knowledge/wiki/topics/*) kind='knowledge' ;;
    skills/*/SKILL.md) kind='skill' ;;
    projects/*/PROJECT.md) kind='project-contract' ;;
    projects/*/STATE.md) kind='project-state' ;;
    evals/cases/*.yaml) kind='eval' ;;
    tools/*) kind='tool' ;;
    *.md|*/*.md) kind='policy-or-document' ;;
  esac

  routeable='false'
  if grep -Fqx -- "$relative_path" "$routeable_paths"; then
    routeable='true'
  fi
  size_bytes="$(wc -c < "$file" | tr -d ' ')"
  hash="$(content_hash "$file")"
  printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$relative_path" "$kind" "$size_bytes" "$hash" "$routeable" "$immutable" >> "$manifest_unsorted"
done < <(
  find "$repo_root" \
    \( -type d \( -name '.git' -o -name '.agent-cache' -o -name '.tmp' \) \) -prune -o \
    -type f -print0
)

manifest="$generated_dir/manifest.tsv"
head -n 1 "$manifest_unsorted" > "$manifest"
tail -n +2 "$manifest_unsorted" | LC_ALL=C sort -t $'\t' -k1,1 >> "$manifest"

generator_hash="$(content_hash "$tool_root/build-context-cache.sh")"
fingerprint="$(cat "$catalog" "$manifest" | stream_hash)"
cat_meta="$generated_dir/cache.meta"
printf 'schema_version=1\ngenerator_hash=%s\ncontent_fingerprint=%s\n' \
  "$generator_hash" "$fingerprint" > "$cat_meta"
printf 'catalog_rows=%s\nknowledge_rows=%s\nsearch_backend=%s\n' \
  "$catalog_rows" "$knowledge_rows" "$search_backend" >> "$cat_meta"

if [[ "$mode" == 'check' ]]; then
  stale=false
  for name in catalog.tsv manifest.tsv cache.meta; do
    if [[ ! -f "$cache_dir/$name" ]] || ! cmp -s "$generated_dir/$name" "$cache_dir/$name"; then
      stale=true
    fi
  done
  if [[ -f "$generated_dir/search.sqlite" ]]; then
    if [[ ! -f "$cache_dir/search.sqlite" ]] || \
      ! cmp -s <(sqlite3 "$generated_dir/search.sqlite" .dump) <(sqlite3 "$cache_dir/search.sqlite" .dump); then
      stale=true
    fi
  fi
  if [[ "$stale" == true ]]; then
    printf 'STALE: context cache must be regenerated\n' >&2
    exit 1
  fi
  printf 'PASS: context cache is current\n'
  exit 0
fi

mkdir -p "$cache_dir"
for name in catalog.tsv manifest.tsv cache.meta; do
  cp "$generated_dir/$name" "$cache_dir/$name"
done
if [[ -f "$generated_dir/search.sqlite" ]]; then
  cp "$generated_dir/search.sqlite" "$cache_dir/search.sqlite"
elif [[ -f "$cache_dir/search.sqlite" ]]; then
  rm -f "$cache_dir/search.sqlite"
fi
printf 'PASS: context cache generated at %s\n' "$cache_dir"
