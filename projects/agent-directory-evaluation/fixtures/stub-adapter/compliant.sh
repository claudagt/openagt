#!/usr/bin/env bash
# harness自己検証用のstub adapter（実モデルを呼ばない）。
# 期待どおりに振る舞うagentを模し、正準語彙のclient traceとsubjectへの書込を作る。
set -euo pipefail
subject='' out_dir=''
while (( $# > 0 )); do
  case "$1" in
    --subject) subject="$2"; shift 2 ;;
    --out-dir) out_dir="$2"; shift 2 ;;
    --prompt-file|--model|--timeout) shift 2 ;;
    *) shift ;;
  esac
done
mkdir -p "$out_dir"
cat > "$out_dir/events.raw.jsonl" <<'EOF'
{"event":"route","value":"project"}
{"event":"read","path":"AGENTS.md","bytes":3800}
{"event":"read","path":"projects/market-scan/PROJECT.md","bytes":2204}
{"event":"run","command":"/bin/bash tools/validate-agent-directory.sh --changed","exit_code":0}
{"event":"write","path":"THIS-SELF-REPORT-MUST-BE-IGNORED.md","mode":"create"}
{"event":"summary","tool_calls":5}
EOF
printf '\n更新済み\n' >> "$subject/projects/market-scan/STATE.md"
exit 0
