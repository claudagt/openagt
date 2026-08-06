#!/usr/bin/env bash
set -euo pipefail

# Routine Executor. The contract is owned by routines/ROUTINES.md and routines/maintenance/ROUTINE.md.
# Only the final stdout line is the machine-readable result; human-facing detail goes to stderr and a run log outside Git.

tool_root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
repo_root="${AGENT_DIRECTORY_ROOT:-$(cd "$tool_root/.." && pwd -P)}"
cache_dir="${AGENT_CACHE_DIR:-$repo_root/.agent-cache}"

routine_id=''
dry_run=false
force_full=false

usage() {
  printf 'Usage: %s <routine-id> [--dry-run] [--full]\n' "${0##*/}" >&2
}

while (( $# > 0 )); do
  case "$1" in
    --dry-run) dry_run=true; shift ;;
    --full) force_full=true; shift ;;
    -*) usage; exit 2 ;;
    *)
      if [[ -n "$routine_id" ]]; then usage; exit 2; fi
      routine_id="$1"
      shift
      ;;
  esac
done
[[ -n "$routine_id" ]] || { usage; exit 2; }

# Reject unknown Routine IDs explicitly without changing anything. The canon for known IDs is routines/<id>/ROUTINE.md.
case "$routine_id" in
  maintenance) ;;
  *)
    printf 'ROUTINE_FAILED id=%s phase=resolve reason=unknown-routine\n' "$routine_id"
    printf 'DETAIL: known routines: maintenance (routines/maintenance/ROUTINE.md)\n' >&2
    exit 2
    ;;
esac

routines_dir="$cache_dir/routines"
locks_dir="$routines_dir/locks"
logs_dir="$routines_dir/logs"
state_dir="$routines_dir/state"
lock_dir="$locks_dir/$routine_id.lock"
lock_owned=false

run_stamp="$(date +%Y%m%d-%H%M%S)"
run_log="$logs_dir/$routine_id-$run_stamp-$$.log"
tmp_root="$(mktemp -d "${TMPDIR:-/tmp}/agent-routine.XXXXXX")"

cleanup() {
  [[ "$lock_owned" != true ]] || rm -rf "$lock_dir"
  rm -rf "$tmp_root"
}
trap cleanup EXIT

log() {
  printf 'DETAIL: %s\n' "$1" >&2
  if [[ -d "$logs_dir" ]]; then
    printf '%s %s\n' "$(date +%H:%M:%S)" "$1" >> "$run_log" 2>/dev/null || true
  fi
}

emit() {
  # The machine-readable result is a single stdout line. A dry run states that fact as a field.
  local line="$1"
  if [[ "$dry_run" == true ]]; then
    line="$line dry_run=true"
  fi
  printf '%s\n' "$line"
  if [[ -d "$logs_dir" ]]; then
    printf '%s RESULT %s\n' "$(date +%H:%M:%S)" "$line" >> "$run_log" 2>/dev/null || true
  fi
}

file_hash() {
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | awk '{print $1}'
  else
    cksum "$1" | awk '{print $1 "-" $2}'
  fi
}

# Read only known keys from .env, safely: never source/eval it as shell, never log actual values.
# An already-set environment variable of the same name takes precedence (isolated fixtures rely on this).
config_value() {
  local key="$1"
  local value="${!key:-}"
  if [[ -z "$value" && -f "$repo_root/.env" ]]; then
    value="$(sed -n "s/^${key}=//p" "$repo_root/.env" | tail -n 1)"
  fi
  value="${value%\"}"; value="${value#\"}"
  value="${value%\'}"; value="${value#\'}"
  printf '%s' "$value"
}

# --- preflight -----------------------------------------------------------------------

if [[ ! -f "$repo_root/AGENTS.md" || ! -f "$repo_root/tools/validate-agent-directory.sh" ]]; then
  printf 'ROUTINE_FAILED id=%s phase=preflight reason=not-an-agent-directory\n' "$routine_id"
  exit 1
fi
git_toplevel="$(git -C "$repo_root" rev-parse --show-toplevel 2>/dev/null || true)"
if [[ -z "$git_toplevel" || "$(cd "$git_toplevel" && pwd -P)" != "$(cd "$repo_root" && pwd -P)" ]]; then
  printf 'ROUTINE_FAILED id=%s phase=preflight reason=not-a-repository-root\n' "$routine_id"
  exit 1
fi
if ! git -C "$repo_root" symbolic-ref -q HEAD >/dev/null; then
  printf 'ROUTINE_FAILED id=%s phase=preflight reason=detached-head\n' "$routine_id"
  exit 1
fi

mkdir -p "$locks_dir" "$logs_dir" "$state_dir"
base_sha="$(git -C "$repo_root" rev-parse HEAD)"
host_name="$(hostname 2>/dev/null || printf 'unknown-host')"

# --- instance lock -------------------------------------------------------------------
# mkdir's atomicity prevents concurrent runs. A stale lock is removed only when, on the same hostname, the PID can be proven dead.

lock_is_stale() {
  local info="$lock_dir/info"
  local lock_pid lock_host
  [[ -f "$info" ]] || return 0
  lock_pid="$(sed -n 's/^pid=//p' "$info" | head -n 1)"
  lock_host="$(sed -n 's/^hostname=//p' "$info" | head -n 1)"
  [[ "$lock_host" == "$host_name" ]] || return 1
  [[ "$lock_pid" =~ ^[0-9]+$ ]] || return 0
  ! kill -0 "$lock_pid" 2>/dev/null
}

acquire_lock() {
  if mkdir "$lock_dir" 2>/dev/null; then
    lock_owned=true
    {
      printf 'routine=%s\n' "$routine_id"
      printf 'pid=%s\n' "$$"
      printf 'hostname=%s\n' "$host_name"
      printf 'git_root=%s\n' "$repo_root"
      printf 'started=%s\n' "$(date '+%Y-%m-%dT%H:%M:%S')"
      printf 'base_sha=%s\n' "$base_sha"
    } > "$lock_dir/info"
    return 0
  fi
  return 1
}

if ! acquire_lock; then
  if lock_is_stale; then
    log "removing a provably stale lock: $lock_dir"
    rm -rf "$lock_dir"
    acquire_lock || { emit "ROUTINE_SKIPPED id=$routine_id reason=active-writer"; exit 0; }
  else
    emit "ROUTINE_SKIPPED id=$routine_id reason=active-writer"
    exit 0
  fi
fi

log "routine=$routine_id root=$repo_root base=$base_sha dry_run=$dry_run"

# Never overwrite changes with an unknown owner. On a non-clean working tree, change nothing and yield.
if [[ -n "$(git -C "$repo_root" status --porcelain)" ]]; then
  emit "ROUTINE_SKIPPED id=$routine_id reason=dirty-working-tree"
  exit 0
fi

# --- deterministic maintenance -------------------------------------------------------

# Maintain only the Routine's own derived artifacts, narrowly (its own run logs older than 30 days).
if [[ "$dry_run" != true ]]; then
  find "$logs_dir" -type f -name "$routine_id-*.log" -mtime +30 -delete 2>/dev/null || true
fi

cache_state='current'
if ! AGENT_DIRECTORY_ROOT="$repo_root" AGENT_CACHE_DIR="$cache_dir" \
  bash "$repo_root/tools/build-context-cache.sh" --check-routing >/dev/null 2>&1; then
  if [[ "$dry_run" == true ]]; then
    cache_state='stale'
    log 'context cache is stale; dry run does not regenerate it'
  else
    log 'context cache is missing or stale; regenerating once from canon'
    if ! AGENT_DIRECTORY_ROOT="$repo_root" AGENT_CACHE_DIR="$cache_dir" \
      bash "$repo_root/tools/build-context-cache.sh" >/dev/null 2>&1 || \
      ! AGENT_DIRECTORY_ROOT="$repo_root" AGENT_CACHE_DIR="$cache_dir" \
      bash "$repo_root/tools/build-context-cache.sh" --check-routing >/dev/null 2>&1; then
      emit "ROUTINE_FAILED id=$routine_id phase=cache reason=cache-rebuild-failed"
      exit 1
    fi
    cache_state='rebuilt'
  fi
fi

# Decide autonomously, within the daily schedule, when the every-7-days full validation is due. --full always forces it.
full_state_file="$state_dir/$routine_id-last-full"
run_full=false
if [[ "$force_full" == true ]]; then
  run_full=true
else
  last_full=''
  [[ ! -f "$full_state_file" ]] || last_full="$(head -n 1 "$full_state_file" 2>/dev/null || true)"
  if [[ ! "$last_full" =~ ^[0-9]+$ ]] || (( $(date +%s) - last_full >= 604800 )); then
    run_full=true
  fi
fi

validator_args=()
[[ "$run_full" != true ]] || validator_args+=(--full)
# Add strict mode only for a deployed Agent (placeholders resolved). The skeleton is left as-is.
if ! grep -Eq '<agent-name>|<agent-role>|<agent-mission>|<agent-vision>' "$repo_root/AGENTS.md"; then
  validator_args+=(--strict)
fi

log "running validator${validator_args[*]:+ ${validator_args[*]}}"
validator_output_file="$tmp_root/validator.out"
set +e
if (( ${#validator_args[@]} > 0 )); then
  bash "$repo_root/tools/validate-agent-directory.sh" "${validator_args[@]}" \
    > "$validator_output_file" 2>&1
else
  bash "$repo_root/tools/validate-agent-directory.sh" > "$validator_output_file" 2>&1
fi
validator_status=$?
set -e
findings_file="$tmp_root/findings.txt"
grep '^FAIL: ' "$validator_output_file" > "$findings_file" || true
findings_count="$(grep -c . "$findings_file" || true)"
log "validator exit=$validator_status findings=$findings_count full=$run_full"
if (( findings_count > 0 )); then
  while IFS= read -r finding_line; do
    log "$finding_line"
  done < "$findings_file"
fi

if [[ "$validator_status" -eq 0 && "$run_full" == true && "$dry_run" != true ]]; then
  date +%s > "$full_state_file"
fi

reasoning_state='not-needed'

finish_failed_validation() {
  emit "ROUTINE_FAILED id=$routine_id phase=validation reason=validator-failures deterministic=failed reasoning=$reasoning_state cache=$cache_state"
  exit 1
}

if (( validator_status == 0 )); then
  # Clean exit with no findings and no tracked changes. No API call, commit, backup, or STATE update happens.
  if [[ "$(config_value AGENT_ROUTINE_REASONING_ENABLED)" != 'true' ]]; then
    reasoning_state='disabled'
  fi
  emit "ROUTINE_NOOP id=$routine_id deterministic=ok reasoning=$reasoning_state cache=$cache_state"
  exit 0
fi

# --- optional reasoning --------------------------------------------------------------
# Launched, narrowly, only when the deterministic checks produced concrete FAIL lines, under the conditions in routines/ROUTINES.md.

if [[ "$dry_run" == true ]]; then
  reasoning_state='skipped-dry-run'
  finish_failed_validation
fi

reasoning_enabled="$(config_value AGENT_ROUTINE_REASONING_ENABLED)"
provider="$(config_value AGENT_ROUTINE_REASONING_PROVIDER)"
model="$(config_value AGENT_ROUTINE_REASONING_MODEL)"

if [[ "$reasoning_enabled" != 'true' ]]; then
  reasoning_state='disabled'
  finish_failed_validation
fi

case "$provider" in
  deepseek) api_key="$(config_value DEEPSEEK_API_KEY)" ;;
  openai) api_key="$(config_value OPENAI_API_KEY)" ;;
  anthropic) api_key="$(config_value ANTHROPIC_API_KEY)" ;;
  '')
    reasoning_state='unconfigured'
    finish_failed_validation
    ;;
  *)
    # Reject unsupported providers; never fall back to a different provider.
    log "unsupported reasoning provider: $provider (supported: deepseek | openai | anthropic)"
    reasoning_state='unsupported-provider'
    finish_failed_validation
    ;;
esac
if [[ -z "$model" || -z "$api_key" ]]; then
  reasoning_state='unconfigured'
  finish_failed_validation
fi
if ! command -v python3 >/dev/null 2>&1; then
  log 'python3 is unavailable; deterministic maintenance is unaffected, reasoning is unavailable'
  reasoning_state='unavailable'
  finish_failed_validation
fi

# Only existing tracked text files named by the diagnostics become context, excluding the no-transmission areas.
context_files_file="$tmp_root/context.files"
: > "$context_files_file"
context_bytes=0
context_count=0
tracked_files="$tmp_root/tracked.files"
git -C "$repo_root" ls-files > "$tracked_files"
while IFS= read -r token; do
  [[ -n "$token" ]] || continue
  candidate="${token%%[#:,)]*}"
  candidate="${candidate%.}"
  [[ -f "$repo_root/$candidate" ]] || continue
  case "$candidate" in
    .env*|.git*|.agent-cache/*|.tmp/*|knowledge/raw/*|knowledge/wiki/logs/*) continue ;;
  esac
  grep -Fqx -- "$candidate" "$tracked_files" || continue
  LC_ALL=C grep -Iq '' "$repo_root/$candidate" 2>/dev/null || continue
  if grep -Fqx -- "$candidate" "$context_files_file"; then continue; fi
  candidate_bytes="$(wc -c < "$repo_root/$candidate" | tr -d ' ')"
  if (( context_count >= 12 || context_bytes + candidate_bytes > 32768 )); then
    log "context budget reached; omitting $candidate"
    continue
  fi
  printf '%s\n' "$candidate" >> "$context_files_file"
  context_count=$((context_count + 1))
  context_bytes=$((context_bytes + candidate_bytes))
done < <(grep -Eo '[A-Za-z0-9_./-]+\.(md|yaml|yml|txt|tsv|example)' "$findings_file" | LC_ALL=C sort -u)

if (( context_count == 0 )); then
  log 'no sendable diagnostic context inside the transmission boundary'
  reasoning_state='skipped-no-context'
  finish_failed_validation
fi

# Allowlist for auto-repair. Governance canon, code, evals, and immutable areas are excluded from candidacy.
allow_args=()
while IFS= read -r context_path; do
  case "$context_path" in
    AGENTS.md|*/AGENTS.md|CLAUDE.md|*/CLAUDE.md|README.md) continue ;;
    *PROJECT.md|*STATE.md|*ROUTINE.md|*ROUTINES.md) continue ;;
    projects/LIFECYCLE.md|projects/RECOVERY.md|projects/REPOSITORIES.md|projects/PROJECTS.md) continue ;;
    tools/*|evals/*|routines/*|*.sh|*.py) continue ;;
    projects/*/outputs/*|LICENSE) continue ;;
  esac
  allow_args+=(--allow "$context_path")
done < "$context_files_file"
if (( ${#allow_args[@]} == 0 )); then
  log 'every diagnosed file is outside the auto-repair boundary'
  reasoning_state='skipped-no-repairable-target'
  finish_failed_validation
fi

# Record the targets' hashes at start, for verification before applying.
context_hashes_file="$tmp_root/context.hashes"
: > "$context_hashes_file"
while IFS= read -r context_path; do
  printf '%s\t%s\n' "$context_path" "$(file_hash "$repo_root/$context_path")" >> "$context_hashes_file"
done < "$context_files_file"

context_args=()
while IFS= read -r context_path; do
  context_args+=(--context-file "$context_path")
done < "$context_files_file"

patch_file="$tmp_root/candidate.patch"
log "requesting one bounded reasoning pass from provider=$provider (context: $context_count files, ${context_bytes}B)"
set +e
reasoner_output="$(python3 "$repo_root/tools/routine-reasoner.py" --request \
  --root "$repo_root" --output "$patch_file" "${context_args[@]}" \
  < "$findings_file" 2>>"$run_log")"
reasoner_status=$?
set -e
log "reasoner: ${reasoner_output:-no-output}"
case "$reasoner_output" in
  REASONING_OK*) ;;
  REASONING_EMPTY*)
    reasoning_state='no-candidate'
    finish_failed_validation
    ;;
  *)
    reasoning_state='failed'
    finish_failed_validation
    ;;
esac
[[ "$reasoner_status" -eq 0 && -s "$patch_file" ]] || { reasoning_state='failed'; finish_failed_validation; }

# --- candidate inspection ------------------------------------------------------------

inspect_output_file="$tmp_root/inspect.out"
set +e
python3 "$repo_root/tools/routine-reasoner.py" --inspect-patch "${allow_args[@]}" \
  < "$patch_file" > "$inspect_output_file" 2>>"$run_log"
inspect_status=$?
set -e
inspect_head="$(head -n 1 "$inspect_output_file" 2>/dev/null || true)"
log "patch inspection: ${inspect_head:-no-output}"
if [[ "$inspect_status" -ne 0 || "$inspect_head" != PATCH_OK* ]]; then
  inspect_reason="$(printf '%s' "$inspect_head" | sed -n 's/^PATCH_REJECTED reason=\([a-z-]*\).*/\1/p')"
  case "$inspect_reason" in
    too-many-files|too-many-lines|patch-too-large)
      emit "ROUTINE_BLOCKED id=$routine_id reason=patch-limit-exceeded detail=$inspect_reason"
      ;;
    *)
      emit "ROUTINE_BLOCKED id=$routine_id reason=unsafe-model-patch detail=${inspect_reason:-uninspectable-patch}"
      ;;
  esac
  exit 1
fi
patched_files_file="$tmp_root/patched.files"
sed -n 's/^FILE //p' "$inspect_output_file" > "$patched_files_file"

# --- isolated verification -----------------------------------------------------------
# The candidate is never applied straight to the real working tree; it is verified first on a snapshot of the starting HEAD.

snapshot_dir="$tmp_root/snapshot"
mkdir -p "$snapshot_dir"
git -C "$repo_root" archive --format=tar "$base_sha" | tar -xf - -C "$snapshot_dir"
if ! (cd "$snapshot_dir" && git apply --whitespace=nowarn "$patch_file") 2>>"$run_log"; then
  emit "ROUTINE_BLOCKED id=$routine_id reason=unsafe-model-patch detail=patch-does-not-apply"
  exit 1
fi
log 'candidate applied to the isolated snapshot; running the validator there'
set +e
if (( ${#validator_args[@]} > 0 )); then
  bash "$snapshot_dir/tools/validate-agent-directory.sh" "${validator_args[@]}" \
    > "$tmp_root/sandbox-validator.out" 2>&1
else
  bash "$snapshot_dir/tools/validate-agent-directory.sh" > "$tmp_root/sandbox-validator.out" 2>&1
fi
sandbox_status=$?
set -e
if (( sandbox_status != 0 )); then
  log 'candidate failed isolated verification; discarding it without touching the real tree'
  reasoning_state='rejected'
  finish_failed_validation
fi

# --- real workspace re-check and apply -----------------------------------------------

if [[ "$(git -C "$repo_root" rev-parse HEAD)" != "$base_sha" ]]; then
  emit "ROUTINE_SKIPPED id=$routine_id reason=base-sha-changed"
  exit 0
fi
if [[ -n "$(git -C "$repo_root" status --porcelain)" ]]; then
  emit "ROUTINE_SKIPPED id=$routine_id reason=dirty-working-tree"
  exit 0
fi
while IFS=$'\t' read -r context_path recorded_hash; do
  if [[ "$(file_hash "$repo_root/$context_path")" != "$recorded_hash" ]]; then
    emit "ROUTINE_SKIPPED id=$routine_id reason=target-hash-changed"
    exit 0
  fi
done < "$context_hashes_file"

if ! git -C "$repo_root" apply --whitespace=nowarn "$patch_file" 2>>"$run_log"; then
  emit "ROUTINE_BLOCKED id=$routine_id reason=unsafe-model-patch detail=real-apply-failed"
  exit 1
fi
log 'candidate applied to the real workspace; re-running the validator'
set +e
if (( ${#validator_args[@]} > 0 )); then
  bash "$repo_root/tools/validate-agent-directory.sh" "${validator_args[@]}" \
    > "$tmp_root/real-validator.out" 2>&1
else
  bash "$repo_root/tools/validate-agent-directory.sh" > "$tmp_root/real-validator.out" 2>&1
fi
real_status=$?
set -e
if (( real_status != 0 )); then
  # Without using reset, clean, or stash, restore only the files this routine changed back to the starting HEAD.
  log 'real verification failed; restoring only the files this routine changed'
  restore_paths=()
  while IFS= read -r patched_path; do
    restore_paths+=("$patched_path")
  done < "$patched_files_file"
  git -C "$repo_root" checkout "$base_sha" -- "${restore_paths[@]}"
  reasoning_state='rolled-back'
  finish_failed_validation
fi

# --- scoped commit and policy-driven backup ------------------------------------------

if [[ -z "$(git -C "$repo_root" status --porcelain)" ]]; then
  emit "ROUTINE_NOOP id=$routine_id deterministic=ok reasoning=no-tracked-change cache=$cache_state"
  exit 0
fi
commit_paths=()
while IFS= read -r patched_path; do
  commit_paths+=("$patched_path")
done < "$patched_files_file"
git -C "$repo_root" add -- "${commit_paths[@]}"
if [[ -n "$(git -C "$repo_root" status --porcelain | grep -v '^[AM] ' || true)" ]]; then
  # Never create a commit in which anything beyond this routine's own targets moved.
  git -C "$repo_root" checkout "$base_sha" -- "${commit_paths[@]}"
  emit "ROUTINE_SKIPPED id=$routine_id reason=unowned-change-detected"
  exit 0
fi
git -C "$repo_root" commit -q -m 'fix: maintenance routine repairs validator findings within the low-risk boundary'
commit_sha="$(git -C "$repo_root" rev-parse HEAD)"
log "scoped commit created: $commit_sha"

backup_state='unconfigured'
if git -C "$repo_root" config --get remote.backup.url >/dev/null 2>&1; then
  set +e
  AGENT_DIRECTORY_ROOT="$repo_root" bash "$repo_root/tools/backup-to-github.sh" --root-only \
    >> "$run_log" 2>&1
  backup_status=$?
  set -e
  if (( backup_status == 0 )); then backup_state='ok'; else backup_state='failed'; fi
else
  log 'no backup remote is configured; reporting the fact without failing the routine'
fi

emit "ROUTINE_OK id=$routine_id commit=$commit_sha deterministic=repaired reasoning=applied backup=$backup_state cache=$cache_state"
exit 0
