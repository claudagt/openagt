#!/usr/bin/env python3
"""run結果の分類。subjectの振る舞いに起因しない実行基盤failureを切り分ける。

docs/EVALUATION.md#Hard Gate の「実行基盤failureの区別」が意味を所有する。
利用制限・rate limit・認証失敗・provider障害・基盤timeoutは、Hard Gate違反でも
candidate失敗でもなく INFRA_UNAVAILABLE（INVALID扱い）とする。利用制限はどの
providerでも起こりうるため、恒久的な前提として扱う。

client非依存。JSONL traceのerror系eventだけを見るため、client固有のexit code規約に
依存しない。取得できない値は捏造せずnullとする。

exit code:
  0  OK                  正常終了
  75 INFRA_UNAVAILABLE   実行基盤failure（EX_TEMPFAIL。失敗trialとして数えない）
  76 NO_TRACE            traceが無くvalidityを判定できない
  1  RUN_FAILED          上記以外の失敗（candidate失敗の候補）
"""

import argparse
import json
import pathlib
import re
import sys

# 先に一致した分類を採用する。順序に意味がある（quotaは429を伴うことがある）。
PATTERNS = [
    ("usage_limit", r"usage limit|quota|credit|billing|insufficient_quota|purchase more"),
    ("rate_limit", r"\b429\b|rate.?limit|too many requests|backoff"),
    ("auth", r"\b401\b|\b403\b|unauthor|forbidden|not logged in|token .*expired|invalid.*api.?key"),
    ("provider_error",
     r"\b5\d{2}\b|internal server error|service unavailable|"
     r"connection (reset|refused|closed)|model .*(unavailable|not found)"),
    ("timeout", r"\btimed? ?out\b|deadline exceeded"),
]

EXIT_CODES = {"OK": 0, "RUN_FAILED": 1, "INFRA_UNAVAILABLE": 75, "NO_TRACE": 76}


def read_events(path: pathlib.Path):
    """error系eventのmessageと、turn失敗の有無を返す。"""
    messages, turn_failed, saw_event = [], False, False
    if not path.is_file():
        return messages, turn_failed, saw_event
    for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            event = json.loads(line)
        except json.JSONDecodeError:
            continue
        if not isinstance(event, dict):
            continue
        saw_event = True
        event_type = event.get("type", "")
        if event_type == "turn.failed":
            turn_failed = True
        if event_type in ("error", "turn.failed"):
            error = event.get("error")
            message = event.get("message")
            if not message and isinstance(error, dict):
                message = error.get("message")
            if message:
                messages.append(message)
    return messages, turn_failed, saw_event


def classify(messages, turn_failed, saw_event, client_exit_code):
    blob = "\n".join(messages)
    for kind, pattern in PATTERNS:
        if re.search(pattern, blob, re.IGNORECASE):
            return "INFRA_UNAVAILABLE", kind
    if not saw_event:
        return "NO_TRACE", None
    if turn_failed or client_exit_code not in (0, None):
        return "RUN_FAILED", None
    return "OK", None


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--events", required=True, help="client traceのJSONL path")
    parser.add_argument("--client", default="unknown")
    parser.add_argument("--client-exit-code", type=int, default=None)
    parser.add_argument("--out", default="-")
    args = parser.parse_args()

    events_path = pathlib.Path(args.events)
    messages, turn_failed, saw_event = read_events(events_path)
    status, kind = classify(messages, turn_failed, saw_event, args.client_exit_code)

    result = {
        "schema": "openagt-adapter-result/v1",
        "client": args.client,
        "status": status,
        "infra_failure": kind or "none",
        "client_exit_code": args.client_exit_code,
        "events": str(events_path),
        "error_messages": messages or None,
    }
    rendered = json.dumps(result, indent=2, sort_keys=True, ensure_ascii=False) + "\n"
    if args.out == "-":
        sys.stdout.write(rendered)
    else:
        pathlib.Path(args.out).write_text(rendered, encoding="utf-8")
    print(f"ADAPTER_{status} infra={kind or 'none'} client_rc={args.client_exit_code}",
          file=sys.stderr)
    return EXIT_CODES[status]


if __name__ == "__main__":
    sys.exit(main())
