#!/usr/bin/env bash
# codex client adapter: subjectをOS強制の隔離下で非対話実行し、runner側traceを残す。
# - cwd/write rootをsubjectへ限定し、networkを遮断する（macOS Seatbelt）
# - CODEX_HOMEとHOMEを一時領域へ分離し、利用者設定・rules・session永続化を読ませない
# - evaluator rootのpathを引数・環境変数として渡さない
# - 観測はclientの--json（JSONL）で行い、subjectの自己申告を使わない
# 境界とexecution configの意味定義はdocs/EVALUATION.mdが所有する。
#
# 実測済みの制約（2026-08-06、codex-cli 0.146.0 / darwin arm64）:
# - workspace-write sandboxはcwd外への書込を拒否するが、/tmpと$TMPDIRは常に書込可能。
#   subjectを/tmp配下へ置くとHG-02（scope外write）がOSレベルで強制されない。
#   本adapterはsubjectを非tmp rootへ置くことを要求し、tmp配下を拒否する。
# - sandboxはread側を制限しない。「subjectからevaluatorを読ませない」はpath秘匿と
#   sandbox配置で担保し、OS強制ではない（execution configへ実値を記録する）。
# - provider keyをenv_keyで渡すと、shell_environment_policyでinherit="none"や
#   exclude=["*KEY*"]を指定してもsubjectのshellから当該変数が見えた。秘密をsubjectへ
#   渡さないため、providerのauth commandで供給する（実測で不可視化を確認済み）。
set -euo pipefail

usage() {
  printf 'Usage: %s --subject <dir> --prompt-file <file> --out-dir <dir> [--provider deepseek] [--model <id>] [--timeout <sec>]\n' "${0##*/}" >&2
  printf '       %s --selftest --out-dir <dir>\n' "${0##*/}" >&2
  exit 3
}

subject='' prompt_file='' out_dir='' model='' timeout_sec='900' selftest='no'
# provider未指定はcodex組込（ChatGPT auth）。deepseekはResponses APIで直結する。
provider=''
while (( $# > 0 )); do
  case "$1" in
    --subject) subject="${2:-}"; shift 2 ;;
    --prompt-file) prompt_file="${2:-}"; shift 2 ;;
    --out-dir) out_dir="${2:-}"; shift 2 ;;
    --model) model="${2:-}"; shift 2 ;;
    --provider) provider="${2:-}"; shift 2 ;;
    --timeout) timeout_sec="${2:-}"; shift 2 ;;
    --selftest) selftest='yes'; shift ;;
    *) usage ;;
  esac
done
[[ -n "$out_dir" ]] || usage

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
evaluator_root="$(cd "$script_dir/../../.." && pwd -P)"

command -v codex >/dev/null 2>&1 || { echo 'ERROR: codex client not found' >&2; exit 4; }
client_version="$(codex --version 2>/dev/null | tr -d '\n' || echo unknown)"

mkdir -p "$out_dir"
out_dir="$(cd "$out_dir" && pwd -P)"

# adapter自身のhash（execution configの一部）
adapter_hash="sha256:$(shasum -a 256 "${BASH_SOURCE[0]}" | cut -d' ' -f1)"

# ---------------------------------------------------------------------------
# tmp配下判定: codexのworkspace-write sandboxは/tmpと$TMPDIRを常に書込可能にする。
# subjectがtmp配下だとwrite root強制が無効化されるため拒否する。
# ---------------------------------------------------------------------------
is_under_tmp() {
  local p="$1" t
  for t in /tmp /private/tmp "${TMPDIR:-}"; do
    [[ -n "$t" ]] || continue
    t="$(cd "$t" 2>/dev/null && pwd -P)" || continue
    case "$p/" in "$t"/*) return 0 ;; esac
  done
  return 1
}

# ---------------------------------------------------------------------------
# selftest: 実モデル呼出なしでOS隔離の実効性を検査する（codex sandboxを使用）
# ---------------------------------------------------------------------------
if [[ "$selftest" == 'yes' ]]; then
  probe_root="$(mktemp -d "${HOME}/.cache/openagt-selftest.XXXXXX")"
  trap 'rm -rf "$probe_root"' EXIT
  work="$probe_root/work"; mkdir -p "$work"
  results="$out_dir/isolation-selftest.json"
  status='PASS'

  probe() { # name expect command
    local name="$1" expect="$2" cmd="$3" got
    if codex sandbox -P ':workspace' -C "$work" -- /bin/sh -c "$cmd" >/dev/null 2>&1; then
      got='allowed'
    else
      got='denied'
    fi
    [[ "$got" == "$expect" ]] || status='FAIL'
    printf '  {"probe":"%s","expect":"%s","observed":"%s"}' "$name" "$expect" "$got"
  }

  {
    printf '{\n "schema": "openagt-isolation-selftest/v1",\n'
    printf ' "client": "codex", "client_version": "%s",\n' "$client_version"
    printf ' "probes": [\n'
    probe 'write_inside_workspace'  'allowed' 'echo x > inside.probe'; printf ',\n'
    probe 'write_outside_workspace' 'denied'  "echo x > $probe_root/outside.probe"; printf ',\n'
    probe 'write_home'              'denied'  "echo x > $HOME/openagt-escape.probe"; printf ',\n'
    probe 'network_egress'          'denied'  'curl -sS -m 5 -o /dev/null https://example.com'; printf '\n'
    printf ' ],\n "status": "%s"\n}\n' "$status"
  } > "$results"

  # statusはprobe実行後に確定するため書き直す
  python3 - "$results" "$status" <<'PY'
import json, sys
p, _ = sys.argv[1], sys.argv[2]
d = json.load(open(p, encoding='utf-8'))
d["status"] = "PASS" if all(x["expect"] == x["observed"] for x in d["probes"]) else "FAIL"
json.dump(d, open(p, "w", encoding="utf-8"), indent=2, sort_keys=True)
open(p, "a", encoding="utf-8").write("\n")
print(f"SELFTEST_{d['status']} {p}")
sys.exit(0 if d["status"] == "PASS" else 1)
PY
  exit $?
fi

# ---------------------------------------------------------------------------
# 通常run
# ---------------------------------------------------------------------------
[[ -n "$subject" && -n "$prompt_file" ]] || usage
[[ -d "$subject" ]] || { echo "ERROR: subject not a directory: $subject" >&2; exit 3; }
[[ -f "$prompt_file" ]] || { echo "ERROR: prompt file not found: $prompt_file" >&2; exit 3; }
subject="$(cd "$subject" && pwd -P)"

case "$subject/" in
  "$evaluator_root"/*)
    echo "ERROR: subject must be outside the evaluator repository: $subject" >&2
    exit 1 ;;
esac
if is_under_tmp "$subject"; then
  echo "ERROR: subject must NOT live under /tmp or \$TMPDIR (write-root enforcement is void there): $subject" >&2
  exit 1
fi

# 隔離HOME / CODEX_HOME。auth材のみ複製し、run後に破棄する。
iso_root="$(mktemp -d "${HOME}/.cache/openagt-iso.XXXXXX")"
secret_root=''
trap 'rm -rf "$iso_root" "$secret_root"' EXIT
iso_home="$iso_root/home"; iso_codex="$iso_root/codex"
mkdir -p "$iso_home" "$iso_codex"; chmod 700 "$iso_root" "$iso_home" "$iso_codex"

# provider別のauth。秘密の実値はここでも記録しない（変数名だけを残す）。
provider_key_var=''
case "$provider" in
  '')
    if [[ -f "$HOME/.codex/auth.json" ]]; then
      install -m 600 "$HOME/.codex/auth.json" "$iso_codex/auth.json"
      auth_source='copied-auth-json'
    else
      auth_source='none'
    fi
    ;;
  deepseek)
    if [[ -z "${DEEPSEEK_API_KEY:-}" ]]; then
      echo 'ERROR: DEEPSEEK_API_KEY is not set in the environment' >&2
      exit 4
    fi
    # 実測（2026-08-06）: env_keyで渡すと、shell_environment_policyでinherit="none"や
    # exclude=["*KEY*"]を指定してもsubjectのshellからその変数が見えた（codexが
    # policy適用後に注入していると見られる）。秘密をsubjectへ渡さないため、
    # 環境変数を経由しないauth commandへ切り替える。
    # 秘密はCODEX_HOMEと無関係な一時領域へ置く（CODEX_HOME自体はsubjectへ露出する）。
    secret_root="$(mktemp -d "${HOME}/.cache/openagt-key.XXXXXX")"
    chmod 700 "$secret_root"
    trap 'rm -rf "$iso_root" "$secret_root"' EXIT
    umask 077
    printf '%s' "$DEEPSEEK_API_KEY" > "$secret_root/token"
    chmod 600 "$secret_root/token"
    printf '#!/bin/sh\ncat %s\n' "$secret_root/token" > "$secret_root/auth.sh"
    chmod 700 "$secret_root/auth.sh"
    auth_source='auth-command (no environment variable)'
    ;;
  *)
    echo "ERROR: unsupported provider: $provider" >&2
    exit 3
    ;;
esac

events="$out_dir/events.raw.jsonl"
last_msg="$out_dir/last-message.txt"

cfg=(
  -c 'sandbox_workspace_write.network_access=false'
  -c 'sandbox_workspace_write.exclude_slash_tmp=true'
  -c 'sandbox_workspace_write.exclude_tmpdir_env_var=true'
  -c 'sandbox_workspace_write.writable_roots=[]'
  # subjectのshellへevaluator側の環境変数を継承させない。
  # provider APIキーはcodexプロセスには必要だが、subjectが`env`で読めてはならない（HG-03）。
  -c 'shell_environment_policy.inherit="none"'
  -c 'shell_environment_policy.exclude=["*KEY*","*TOKEN*","*SECRET*","*PASSWORD*"]'
)
[[ -n "$model" ]] && cfg+=(-m "$model")
if [[ "$provider" == 'deepseek' ]]; then
  # 実測（2026-08-06）: DeepSeekはResponses APIをnativeに提供する（/responses が200を返す）。
  # codex 0.146.0は`wire_api="chat"`を廃止済みのため、responsesで直結する。
  # ローカルResponses bridgeは不要（旧構成の名残であり、依存させない）。
  cfg+=(
    -c 'model_provider="deepseek"'
    -c 'model_providers.deepseek.name="DeepSeek"'
    -c "model_providers.deepseek.base_url=\"${DEEPSEEK_BASE_URL:-https://api.deepseek.com}\""
    -c 'model_providers.deepseek.wire_api="responses"'
    -c "model_providers.deepseek.auth.command=\"$secret_root/auth.sh\""
    -c 'model_providers.deepseek.auth.timeout_ms=5000'
  )
fi

# execution config（決定的。実行時刻・run固有pathを含めない）
cat > "$out_dir/execution-config.json" <<EOF
{
  "schema": "openagt-execution-config/v1",
  "provider": "${provider:-openai}",
  "model": "${model:-unknown}",
  "client": "codex",
  "client_version": "$client_version",
  "adapter_hash": "$adapter_hash",
  "invocation": "codex exec --json --ignore-user-config --ignore-rules --ephemeral --skip-git-repo-check -s workspace-write -C <subject>",
  "system_instruction_hash": "unknown",
  "tool_schema_hash": "unknown",
  "filesystem_permission": "workspace-write; write root = subject only; tmp roots excluded; reads NOT restricted by OS",
  "network_permission": "denied",
  "sampling": "unknown",
  "reasoning": "unknown",
  "context_limit": "unknown",
  "output_limit": "unknown",
  "step_limit": "unknown",
  "timeout_sec": $timeout_sec,
  "retry_policy": "none",
  "os": "$(uname -s) $(uname -m)",
  "runtime": "$client_version",
  "user_config_loaded": false,
  "rules_loaded": false,
  "session_persisted": false,
  "auth_source": "$auth_source"
}
EOF

env_args=(
  PATH="/usr/bin:/bin:/usr/sbin:/sbin:$(dirname "$(command -v codex)")"
  HOME="$iso_home"
  CODEX_HOME="$iso_codex"
  TERM=dumb LANG=C
)
# 秘密は環境変数として渡さない（auth commandがcodexへ直接供給する）。
set +e
env -i "${env_args[@]}" \
  codex exec \
    --json \
    --ignore-user-config \
    --ignore-rules \
    --ephemeral \
    --skip-git-repo-check \
    --color never \
    -s workspace-write \
    -C "$subject" \
    -o "$last_msg" \
    "${cfg[@]}" \
    - < "$prompt_file" > "$events" 2>"$out_dir/client.stderr"
rc=$?
set -e

# ---------------------------------------------------------------------------
# 実行基盤failureの分類。subjectの振る舞いに起因しない失敗はcandidate失敗と区別する
# （docs/EVALUATION.md#Hard Gate の「実行基盤failureの区別」）。
# 利用制限はどのproviderでも起こりうるため、恒久的な前提として扱う。
# exit 75 (EX_TEMPFAIL) = INFRA_UNAVAILABLE。runnerはこれをINVALIDとして扱い、
# 失敗trialとして数えない。
# ---------------------------------------------------------------------------
python3 "$script_dir/classify-run.py" \
  --events "$events" \
  --client codex \
  --client-exit-code "$rc" \
  --out "$out_dir/adapter-result.json"
exit $?
