#!/usr/bin/env bash
set -euo pipefail

# Scheduler管理Tool。契約は routines/ROUTINES.md が所有する。
# OS scheduleの変更は利用者の明示操作（--install / --remove）だけで行い、
# 通常のRoutine実行やclone直後に自動installしない。root権限を要求しない。
# 扱うのはuser crontabとuser LaunchAgentだけで、無関係なentryへ触れない。

tool_root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
repo_root="${AGENT_DIRECTORY_ROOT:-$(cd "$tool_root/.." && pwd -P)}"
cache_dir="${AGENT_CACHE_DIR:-$repo_root/.agent-cache}"
logs_dir="$cache_dir/routines/logs"

routine_id=''
scheduler='auto'
at_time='03:00'
action=''

usage() {
  printf 'Usage: %s --routine maintenance --scheduler auto|cron|launchd [--at HH:MM] (--print|--dry-run|--install|--status|--remove)\n' \
    "${0##*/}" >&2
}

blocked() {
  printf 'SCHEDULE_BLOCKED reason=%s\n' "$1" >&2
  exit 1
}

while (( $# > 0 )); do
  case "$1" in
    --routine) [[ $# -ge 2 ]] || { usage; exit 2; }; routine_id="$2"; shift 2 ;;
    --scheduler) [[ $# -ge 2 ]] || { usage; exit 2; }; scheduler="$2"; shift 2 ;;
    --at) [[ $# -ge 2 ]] || { usage; exit 2; }; at_time="$2"; shift 2 ;;
    --print|--dry-run) action='print'; shift ;;
    --install) action='install'; shift ;;
    --status) action='status'; shift ;;
    --remove) action='remove'; shift ;;
    *) usage; exit 2 ;;
  esac
done

[[ -n "$routine_id" && -n "$action" ]] || { usage; exit 2; }
case "$routine_id" in
  maintenance) ;;
  *) blocked 'unknown-routine' ;;
esac
[[ "$at_time" =~ ^([01][0-9]|2[0-3]):[0-5][0-9]$ ]] || blocked 'invalid-time'
[[ -f "$repo_root/tools/run-routine.sh" ]] || blocked 'not-an-agent-directory'

# auto: macOS（Darwin）はlaunchd、その他の一般的なUnix環境はcronを標準とする。
# AGENT_ROUTINE_SCHEDULER_OSは隔離fixture専用のOS上書きで、通常運用では設定しない。
os_name="${AGENT_ROUTINE_SCHEDULER_OS:-$(uname -s)}"
case "$scheduler" in
  auto)
    if [[ "$os_name" == 'Darwin' ]]; then scheduler='launchd'; else scheduler='cron'; fi
    ;;
  cron|launchd) ;;
  *) blocked 'unsupported-scheduler' ;;
esac

hour="${at_time%%:*}"
minute="${at_time##*:}"
hour_number=$((10#$hour))
minute_number=$((10#$minute))

# Workspaceごとに一意な識別子。複数Agentのlabelとcron entryが衝突しない。
root_hash="$(printf '%s' "$repo_root" | { shasum -a 256 2>/dev/null || cksum; } | \
  awk '{print $1}' | cut -c1-8)"
launchd_label="local.agent-directory.$root_hash.routine.$routine_id"
cron_marker="# agent-directory routine=$routine_id root=$repo_root"

# cronの限定PATHでも動くよう、絶対pathと明示PATHでコマンドを組む。
routine_command="cd $repo_root && PATH=/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin:/opt/homebrew/bin /bin/bash tools/run-routine.sh $routine_id >> $logs_dir/cron.log 2>&1"
cron_entry="$minute_number $hour_number * * * $routine_command $cron_marker"

render_plist() {
  cat <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Label</key>
	<string>$launchd_label</string>
	<key>ProgramArguments</key>
	<array>
		<string>/bin/bash</string>
		<string>$repo_root/tools/run-routine.sh</string>
		<string>$routine_id</string>
	</array>
	<key>WorkingDirectory</key>
	<string>$repo_root</string>
	<key>StartCalendarInterval</key>
	<dict>
		<key>Hour</key>
		<integer>$hour_number</integer>
		<key>Minute</key>
		<integer>$minute_number</integer>
	</dict>
	<key>StandardOutPath</key>
	<string>$logs_dir/launchd.out.log</string>
	<key>StandardErrorPath</key>
	<string>$logs_dir/launchd.err.log</string>
</dict>
</plist>
PLIST
}

plist_path="$HOME/Library/LaunchAgents/$launchd_label.plist"

current_crontab() {
  crontab -l 2>/dev/null || true
}

crontab_without_entry() {
  current_crontab | { grep -Fv -- "$cron_marker" || true; }
}

install_crontab() {
  # 無関係なentryを保持したまま、自分のmanaged entryだけを置換する。
  if [[ -n "$1" ]]; then
    printf '%s\n' "$1" | crontab -
  else
    printf '' | crontab -
  fi
}

case "$scheduler" in
  cron)
    command -v crontab >/dev/null 2>&1 || blocked 'crontab-unavailable'
    case "$action" in
      print)
        printf '%s\n' "$cron_entry"
        printf 'SCHEDULE_PRINTED routine=%s scheduler=cron at=%s\n' "$routine_id" "$at_time"
        ;;
      install)
        mkdir -p "$logs_dir"
        remaining="$(crontab_without_entry)"
        if [[ -n "$remaining" ]]; then
          install_crontab "$remaining"$'\n'"$cron_entry"
        else
          install_crontab "$cron_entry"
        fi
        printf 'SCHEDULE_INSTALLED routine=%s scheduler=cron at=%s\n' "$routine_id" "$at_time"
        ;;
      status)
        if current_crontab | grep -Fq -- "$cron_marker"; then
          current_crontab | grep -F -- "$cron_marker" >&2
          printf 'SCHEDULE_STATUS routine=%s scheduler=cron installed=true\n' "$routine_id"
        else
          printf 'SCHEDULE_STATUS routine=%s scheduler=cron installed=false\n' "$routine_id"
        fi
        ;;
      remove)
        if current_crontab | grep -Fq -- "$cron_marker"; then
          install_crontab "$(crontab_without_entry)"
          printf 'SCHEDULE_REMOVED routine=%s scheduler=cron removed=true\n' "$routine_id"
        else
          printf 'SCHEDULE_REMOVED routine=%s scheduler=cron removed=false\n' "$routine_id"
        fi
        ;;
    esac
    ;;
  launchd)
    case "$action" in
      print)
        render_plist
        printf 'SCHEDULE_PRINTED routine=%s scheduler=launchd at=%s label=%s\n' \
          "$routine_id" "$at_time" "$launchd_label"
        ;;
      install)
        command -v launchctl >/dev/null 2>&1 || blocked 'launchctl-unavailable'
        mkdir -p "$logs_dir" "$HOME/Library/LaunchAgents"
        render_plist > "$plist_path"
        # 再installを冪等にするため、既存の自分のjobだけをboot outしてから登録する。
        launchctl bootout "gui/$(id -u)/$launchd_label" >/dev/null 2>&1 || true
        launchctl bootstrap "gui/$(id -u)" "$plist_path" >/dev/null 2>&1 || \
          blocked 'launchd-bootstrap-failed'
        printf 'SCHEDULE_INSTALLED routine=%s scheduler=launchd at=%s label=%s\n' \
          "$routine_id" "$at_time" "$launchd_label"
        ;;
      status)
        if [[ -f "$plist_path" ]]; then
          printf 'SCHEDULE_STATUS routine=%s scheduler=launchd installed=true label=%s\n' \
            "$routine_id" "$launchd_label"
        else
          printf 'SCHEDULE_STATUS routine=%s scheduler=launchd installed=false label=%s\n' \
            "$routine_id" "$launchd_label"
        fi
        ;;
      remove)
        command -v launchctl >/dev/null 2>&1 || blocked 'launchctl-unavailable'
        if [[ -f "$plist_path" ]]; then
          launchctl bootout "gui/$(id -u)/$launchd_label" >/dev/null 2>&1 || true
          rm -f "$plist_path"
          printf 'SCHEDULE_REMOVED routine=%s scheduler=launchd removed=true\n' "$routine_id"
        else
          printf 'SCHEDULE_REMOVED routine=%s scheduler=launchd removed=false\n' "$routine_id"
        fi
        ;;
    esac
    ;;
esac
