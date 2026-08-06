#!/usr/bin/env bash
set -euo pipefail

tool_root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="${AGENT_DIRECTORY_ROOT:-$(cd "$tool_root/.." && pwd)}"
cache_dir="${AGENT_CACHE_DIR:-$repo_root/.agent-cache}"
registry_path='projects/REPOSITORIES.md'
sqlite_knowledge_threshold="${AGENT_SQLITE_KNOWLEDGE_THRESHOLD:-1000}"
sqlite_catalog_threshold="${AGENT_SQLITE_CATALOG_THRESHOLD:-5000}"
mode='build'

if (( $# > 1 )); then
  printf 'Usage: %s [--check|--check-routing]\n' "${0##*/}" >&2
  exit 2
fi
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
# stat指紋の同秒編集guardに使う。この秒以降のmtimeを持つsourceがある間は指紋を保存しない。
run_start_epoch="$(date +%s)"

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
  sed -E "s/^\[//; s/\]$//; s/[\"']//g; s/[[:space:]]*,[[:space:]]*/|/g" | clean_field
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

# registry entryを "name<TAB>revision" として1行ずつ出す。コードフェンス内は読まない。
# cacheは派生物なので、壊れたentryは停止せず警告して候補から外す。
registry_records() {
  LC_ALL=C awk '
    function flush_entry() {
      if (current == "") return
      if (revision ~ /^[0-9a-f]{40}$/) print current "\t" revision
      else print "W\t" current
      current = ""
    }
    {
      if (substr($0, 1, 3) == "```") { fence = 1 - fence; next }
      if (fence) next
      if (substr($0, 1, 3) == "## ") {
        flush_entry()
        heading = $0
        revision = ""
        if (heading ~ /^## `[A-Za-z0-9][A-Za-z0-9._-]*`[ \t]*$/) {
          sub(/^## `/, "", heading)
          sub(/`[ \t]*$/, "", heading)
          current = heading
        }
        next
      }
      if (current != "" && $0 ~ /^- revision: `[0-9a-f]*`[ \t]*$/) {
        revision = $0
        sub(/^- revision: `/, "", revision)
        sub(/`[ \t]*$/, "", revision)
      }
    }
    END { flush_entry() }
  ' "$1"
}

# Embedded Projectはfilesystem全件ではなくroot indexを基準に決める。
# Gitの外へ置いた隔離fixture rootだけがfilesystemへfallbackする。
root_index_project_contracts() {
  local top
  if top="$(git -C "$repo_root" rev-parse --show-toplevel 2>/dev/null)" && \
    [[ "$(cd "$top" 2>/dev/null && pwd -P)" == "$(cd "$repo_root" && pwd -P)" ]]; then
    git -C "$repo_root" ls-files -- 'projects/*/PROJECT.md'
  else
    ( cd "$repo_root" && find projects -mindepth 2 -maxdepth 2 -type f -name 'PROJECT.md' 2>/dev/null ) |
      LC_ALL=C sort
  fi
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
  local missing=''

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

  [[ -n "$name" ]] || missing='name'
  [[ -n "$status" ]] || missing="${missing:+$missing, }status"
  if [[ -n "$missing" ]]; then
    printf 'WARN: %s: missing %s; skipping catalog entry\n' \
      "${file#"$repo_root"/}" "$missing" >&2
    return 0
  fi

  append_catalog "$area" "$kind" "$status" "$name" "$aliases" "$description" "$item_mode" "$file"
}

# Independent Projectは採用revisionのfrontmatter metadataだけをcatalogへ入れる。
# content_hashへrevisionを混ぜ、採用revisionの変更が必ずfingerprintへ伝わるようにする。
append_adopted_project() {
  local project_name="$1"
  local revision="$2"
  local adopted_file="$3"
  local name status description item_mode hash
  local missing=''

  name="$(frontmatter_value "$adopted_file" 'name')"
  status="$(frontmatter_value "$adopted_file" 'status')"
  description="$(frontmatter_value "$adopted_file" 'description')"
  item_mode="$(frontmatter_value "$adopted_file" 'mode')"

  [[ -n "$name" ]] || missing='name'
  [[ -n "$status" ]] || missing="${missing:+$missing, }status"
  if [[ -n "$missing" ]]; then
    printf 'WARN: projects/%s/PROJECT.md: missing %s; skipping catalog entry\n' \
      "$project_name" "$missing" >&2
    return 0
  fi

  hash="$( { printf '%s\n' "$revision"; cat "$adopted_file"; } | stream_hash )"
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    'project' 'project' "$status" "$(printf '%s' "$name" | clean_field)" '' \
    "$(printf '%s' "$description" | clean_field)" "$item_mode" \
    "projects/$project_name/PROJECT.md" "$hash" >> "$catalog_unsorted"
}

meta_files=(
  'AGENTS.md|root-policy|最上位ブートローダー、Route判定、Context Loading'
  'README.md|overview|人間向けの導入と全体像'
  'knowledge/KNOWLEDGE.md|knowledge-policy|Knowledge運用規約'
  'skills/SKILLS.md|skill-policy|Skill運用規約'
  'projects/AGENTS.md|project-entry|Project作業共通の入口と読込順序'
  'projects/PROJECTS.md|project-policy|Project運用規約とProject docs契約'
  'projects/LIFECYCLE.md|project-lifecycle|Projectの状態遷移と削除条件'
  'projects/RECOVERY.md|project-recovery|Projectの目的不一致からの復旧'
  'evals/EVALS.md|eval-policy|振る舞いEvalの規約'
  'tools/TOOLS.md|tool-policy|構造保守Toolの規約'
  'tools/BACKUP.md|backup-policy|遠隔バックアップ、復旧、マシン移行の規約'
  'routines/ROUTINES.md|routine-policy|Routine Trigger層とScheduled Maintenanceの規約'
  'routines/maintenance/ROUTINE.md|maintenance-routine|Maintenance Routine固有の契約'
)

# --- --check-routing warm fast path -----------------------------------------------
# 候補集合のpath+size+mtime指紋が前回保存時と一致すれば、本文の再読・再hashなしで
# catalogを新鮮と判定する。指紋の欠損・不一致・stat不能時は従来の全再計算とcmpへ
# fallbackし、判定の正確性はfallback側が保証する。Git HEADは鮮度入力に使わない。

# builderと同じ候補集合を本文を読まずに列挙する。列挙規則を変えたら両方を揃える。
list_stat_candidates() {
  local entry directory file project_relative registry_name registry_revision
  for entry in "${meta_files[@]}"; do
    printf '%s\n' "$repo_root/${entry%%|*}"
  done
  for directory in "$repo_root/knowledge/wiki/sources" "$repo_root/knowledge/wiki/topics"; do
    [[ -d "$directory" ]] || continue
    find "$directory" -type f -name '*.md'
  done
  if [[ -d "$repo_root/skills" ]]; then
    while IFS= read -r -d '' file; do
      [[ "$file" == "$repo_root/skills/_template/"* ]] && continue
      printf '%s\n' "$file"
    done < <(find "$repo_root/skills" -mindepth 2 -maxdepth 2 -type f -name 'SKILL.md' -print0)
  fi
  while IFS= read -r project_relative; do
    [[ -n "$project_relative" ]] || continue
    printf '%s/%s\n' "$repo_root" "$project_relative"
  done < <(root_index_project_contracts)
  printf '%s\n' "$repo_root/$registry_path" "$tool_root/build-context-cache.sh"
  if [[ -f "$repo_root/$registry_path" ]]; then
    # Independent cloneの出現・消滅・HEAD移動もcatalog行を変えるため指紋へ含める。
    while IFS=$'\t' read -r registry_name registry_revision; do
      [[ -n "$registry_name" && "$registry_name" != 'W' ]] || continue
      printf '%s\n' "$repo_root/projects/$registry_name/.git/HEAD"
    done < <(registry_records "$repo_root/$registry_path")
  fi
}

stat_lines_for() {
  # "path<TAB>size<TAB>mtime" を1回のstat実行で出す。GNU statを先に試すのは、
  # GNUの`-f`がfilesystem情報で誤成功するのを避けるためである。
  (( $# > 0 )) || return 0
  stat -c $'%n\t%s\t%Y' "$@" 2>/dev/null && return 0
  stat -f $'%N\t%z\t%m' "$@" 2>/dev/null
}

stat_fingerprint_report() {
  # 1行目に指紋、2行目にsource側最大mtimeを出す。cache派生物は改変検知のため
  # 指紋にだけ入れ、同秒guardの対象へ入れない（buildと同秒のmtimeを常に持つ）。
  stat_existing=()
  stat_missing=()
  local candidate source_lines cache_lines
  while IFS= read -r candidate; do
    [[ -n "$candidate" ]] || continue
    if [[ -e "$candidate" ]]; then
      stat_existing+=("$candidate")
    else
      stat_missing+=("$candidate")
    fi
  done < <(list_stat_candidates | LC_ALL=C sort -u)
  source_lines=''
  if (( ${#stat_existing[@]} > 0 )); then
    source_lines="$(stat_lines_for "${stat_existing[@]}")" || return 1
  fi
  cache_lines=''
  if [[ -f "$cache_dir/catalog.tsv" && -f "$cache_dir/cache.meta" ]]; then
    cache_lines="$(stat_lines_for "$cache_dir/catalog.tsv" "$cache_dir/cache.meta")" || cache_lines=''
  fi
  {
    printf '%s\n' "$source_lines" "$cache_lines"
    if (( ${#stat_missing[@]} > 0 )); then
      printf '%s\tmissing\n' "${stat_missing[@]}"
    fi
  } | LC_ALL=C sort | stream_hash
  printf '%s\n' "$source_lines" | \
    awk -F '\t' 'BEGIN { max = 0 } NF >= 3 && ($3 + 0) > max { max = $3 + 0 } END { print max }'
}

write_stat_meta() {
  # 同秒編集の疑いがある間は指紋を保存せず、fast pathを無効のままにする。
  local report="$1"
  local epoch="$2"
  local fingerprint max_mtime
  fingerprint="$(printf '%s\n' "$report" | sed -n '1p')"
  max_mtime="$(printf '%s\n' "$report" | sed -n '2p')"
  if [[ -n "$fingerprint" && "$max_mtime" =~ ^[0-9]+$ ]] && (( max_mtime < epoch )); then
    printf 'schema_version=1\nstat_fingerprint=%s\n' "$fingerprint" > "$cache_dir/stat.meta"
  else
    rm -f "$cache_dir/stat.meta"
  fi
}

routing_stat_report=''
if [[ "$mode" == 'check-routing' ]]; then
  if ! routing_stat_report="$(stat_fingerprint_report)"; then
    routing_stat_report=''
  fi
  if [[ -n "$routing_stat_report" && -f "$cache_dir/stat.meta" ]] && \
    grep -Fqx 'schema_version=1' "$cache_dir/stat.meta"; then
    stored_fingerprint="$(sed -n 's/^stat_fingerprint=//p' "$cache_dir/stat.meta" | head -n 1)"
    current_fingerprint="$(printf '%s\n' "$routing_stat_report" | sed -n '1p')"
    if [[ -n "$stored_fingerprint" && "$current_fingerprint" == "$stored_fingerprint" ]]; then
      printf 'PASS: routing catalog is current\n'
      exit 0
    fi
  fi
fi

for entry in "${meta_files[@]}"; do
  IFS='|' read -r path name description <<< "$entry"
  append_catalog 'meta' 'policy' 'active' "$name" '' "$description" '' "$repo_root/$path"
done

for directory in "$repo_root/knowledge/wiki/sources" "$repo_root/knowledge/wiki/topics"; do
  [[ -d "$directory" ]] || continue
  while IFS= read -r -d '' file; do
    append_frontmatter_item 'knowledge' 'wiki' "$file"
  done < <(find "$directory" -type f -name '*.md' -print0)
done

if [[ -d "$repo_root/skills" ]]; then
  while IFS= read -r -d '' file; do
    [[ "$file" == "$repo_root/skills/_template/"* ]] && continue
    append_frontmatter_item 'skill' 'skill' "$file"
  done < <(find "$repo_root/skills" -mindepth 2 -maxdepth 2 -type f -name 'SKILL.md' -print0)
fi

# Independent Projectはregistryだけを正本として列挙し、本文ではなく採用revisionのfrontmatterを読む。
independent_names=()
independent_revisions=()
independent_paths="$tmp_root/independent.paths"
: > "$independent_paths"
if [[ -f "$repo_root/$registry_path" ]]; then
  while IFS=$'\t' read -r registry_name registry_revision; do
    [[ -n "$registry_name" ]] || continue
    if [[ "$registry_name" == 'W' ]]; then
      printf 'WARN: %s: `%s` has no valid adopted revision; skipping catalog entry\n' \
        "$registry_path" "$registry_revision" >&2
      continue
    fi
    independent_names+=("$registry_name")
    independent_revisions+=("$registry_revision")
    printf 'projects/%s/PROJECT.md\n' "$registry_name" >> "$independent_paths"
  done < <(registry_records "$repo_root/$registry_path")
fi
independent_count="${#independent_names[@]}"

is_independent_project() {
  local candidate="$1"
  local index=0
  while (( index < independent_count )); do
    [[ "${independent_names[$index]}" != "$candidate" ]] || return 0
    index=$((index + 1))
  done
  return 1
}

while IFS= read -r project_relative; do
  [[ -n "$project_relative" ]] || continue
  case "$project_relative" in projects/_template/*) continue ;; esac
  project_name="${project_relative#projects/}"
  project_name="${project_name%%/*}"
  is_independent_project "$project_name" && continue
  append_frontmatter_item 'project' 'project' "$repo_root/$project_relative"
done < <(root_index_project_contracts)

# 採用revisionのPROJECT.mdだけを読む。working treeの未commit内容はroot cacheへ入れない。
independent_index=0
while (( independent_index < independent_count )); do
  independent_name="${independent_names[$independent_index]}"
  independent_revision="${independent_revisions[$independent_index]}"
  independent_index=$((independent_index + 1))
  adopted_contract="$tmp_root/adopted-$independent_name.md"
  if ! git -C "$repo_root/projects/$independent_name" show \
    "$independent_revision:PROJECT.md" > "$adopted_contract" 2>/dev/null; then
    printf 'WARN: projects/%s/PROJECT.md: adopted revision %s is unavailable; skipping catalog entry\n' \
      "$independent_name" "$independent_revision" >&2
    continue
  fi
  append_adopted_project "$independent_name" "$independent_revision" "$adopted_contract"
done

catalog="$generated_dir/catalog.tsv"
head -n 1 "$catalog_unsorted" > "$catalog"
tail -n +2 "$catalog_unsorted" | LC_ALL=C sort -t $'\t' -k8,8 >> "$catalog"

if [[ "$mode" == 'check-routing' ]]; then
  if [[ -f "$cache_dir/catalog.tsv" ]] && cmp -s "$catalog" "$cache_dir/catalog.tsv"; then
    # 全再計算でPASSした時点の指紋を保存し、次回以降をwarm fast pathにする。
    if [[ -n "$routing_stat_report" ]]; then
      write_stat_meta "$routing_stat_report" "$run_start_epoch"
    fi
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
        # Independent Projectの本文はroot索引へ入れない。metadataだけで候補選択する。
        if grep -Fqx -- "$path" "$independent_paths"; then
          absolute_path=''
        elif [[ ! -f "$absolute_path" ]]; then
          continue
        fi
        q_area="$(printf '%s' "$area" | sql_quote)"
        q_kind="$(printf '%s' "$kind" | sql_quote)"
        q_status="$(printf '%s' "$status" | sql_quote)"
        q_name="$(printf '%s' "$name" | sql_quote)"
        q_aliases="$(printf '%s' "$aliases" | sql_quote)"
        q_description="$(printf '%s' "$description" | sql_quote)"
        q_mode="$(printf '%s' "$item_mode" | sql_quote)"
        q_path="$(printf '%s' "$path" | sql_quote)"
        q_hash="$(printf '%s' "$hash" | sql_quote)"
        if [[ -z "$absolute_path" ]]; then
          printf "INSERT INTO search VALUES('%s','%s','%s','%s','%s','%s','%s','%s','%s','');\n" \
            "$q_area" "$q_kind" "$q_status" "$q_name" "$q_aliases" "$q_description" "$q_mode" "$q_path" "$q_hash"
        else
          q_absolute_path="$(printf '%s' "$absolute_path" | sql_quote)"
          printf "INSERT INTO search VALUES('%s','%s','%s','%s','%s','%s','%s','%s','%s',CAST(readfile('%s') AS TEXT));\n" \
            "$q_area" "$q_kind" "$q_status" "$q_name" "$q_aliases" "$q_description" "$q_mode" "$q_path" "$q_hash" "$q_absolute_path"
        fi
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
    printf 'WARN: scale threshold reached, but sqlite3 with FTS5 trigram is unavailable; recording search_backend=rg-fallback\n' >&2
  fi
fi

routeable_paths="$tmp_root/routeable.paths"
tail -n +2 "$catalog" | awk -F '\t' '{print $8}' | LC_ALL=C sort -u > "$routeable_paths"

manifest_unsorted="$tmp_root/manifest.unsorted"
printf 'path\tkind\tsize_bytes\tcontent_hash\trouteable\timmutable\n' > "$manifest_unsorted"

# Independent ProjectのProject rootはroot cacheの境界外である。`.git`だけでなくdirectory全体を
# pruneし、child側の変更がroot fingerprintへ漏れないようにする。対象はregistry登録名だけなので、
# Embedded Projectや`projects/REPOSITORIES.md`、`projects/.gitignore`は巻き込まない。
manifest_prune=( -name '.git' -o -name '.agent-cache' -o -name '.tmp' )
independent_index=0
while (( independent_index < independent_count )); do
  manifest_prune+=( -o -path "$repo_root/projects/${independent_names[$independent_index]}" )
  independent_index=$((independent_index + 1))
done

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
    knowledge/raw/internal/*) kind='internal-record'; immutable='true' ;;
    knowledge/raw/external/*) kind='external-source'; immutable='true' ;;
    knowledge/raw/*) kind='raw-record'; immutable='true' ;;
    knowledge/wiki/logs/*) kind='closed-log'; immutable='true' ;;
    knowledge/wiki/sources/*|knowledge/wiki/topics/*) kind='knowledge' ;;
    skills/*/SKILL.md) kind='skill' ;;
    projects/*/PROJECT.md) kind='project-contract' ;;
    projects/*/STATE.md) kind='project-state' ;;
    projects/*/ARCHITECTURE.md) kind='project-architecture' ;;
    projects/*/docs/*) kind='project-doc' ;;
    evals/cases/*.yaml) kind='eval' ;;
    routines/ROUTINES.md) kind='routine-policy' ;;
    routines/*/ROUTINE.md) kind='routine-contract' ;;
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
    \( -type d \( "${manifest_prune[@]}" \) \) -prune -o \
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
# stat指紋はwarm fast path専用の派生物であり、--checkの比較対象へ入れない。
if build_stat_report="$(stat_fingerprint_report)"; then
  write_stat_meta "$build_stat_report" "$run_start_epoch"
else
  rm -f "$cache_dir/stat.meta"
fi
printf 'PASS: context cache generated at %s\n' "$cache_dir"
