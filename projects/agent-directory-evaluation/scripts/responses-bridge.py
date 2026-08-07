#!/usr/bin/env python3
"""local Responses→chat completions bridge。

codex 0.146.0はResponses API（`/responses`）しか話せないが、DeepSeekは
`deepseek-v4-pro`のResponses対応を未提供（公式docs: early August 2026予定、
2026-08-07時点で未開通）。本bridgeはlocalhostで`/responses`を受け、
providerの`/chat/completions`へ翻訳して中継する。providerがproのResponses
対応を開始したら本bridgeは不要になる（直結へ戻す）。

設計制約:
- Python標準ライブラリのみ。状態を持たない（codexはstore:falseで全履歴を毎回送る）。
- 秘密を保持しない: 受信したAuthorization headerをそのまま転送するだけ。logへ出さない。
- 翻訳で落とすもの（実測したcodex requestに基づく）:
  * type=function以外のtool（namespace、web_search）→ chat APIが受けないため除去
  * reasoning項目・reasoning_content delta → codexの判定に不要のため非転送
- 起動時にport 0でbindし、実portを標準出力へ1行出す（adapterが読む）。

観測への影響: 本bridgeはexecution configの一部であり、adapterがbridge hashを
execution-config.jsonへ記録する（bridgeの有無はconfig hashを変える）。
"""

import argparse
import json
import socket
import sys
import threading
import urllib.error
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


def text_of(content) -> str:
    """message contentのtext部分を連結する。文字列/parts配列の両形を受ける。"""
    if isinstance(content, str):
        return content
    parts = []
    for part in content or []:
        if isinstance(part, dict) and part.get("type") in (
                "input_text", "output_text", "text", "summary_text"):
            parts.append(part.get("text", ""))
    return "".join(parts)


def to_chat_request(req: dict) -> dict:
    """Responses request → chat completions request。

    reasoningの往復（実測 2026-08-07）: proのthinking modeは、tool会話の続きで
    `reasoning_content`をassistant messageへ返送しないとinvalid_requestを返す。
    本bridgeはreasoningを`encrypted_content`としてcodexへ返しており（codexは
    store:falseのため次requestの履歴に含めて送り返す）、ここで直後のassistant/
    tool呼出messageの`reasoning_content`へ復元する。
    """
    messages = []
    instructions = req.get("instructions")
    if instructions:
        messages.append({"role": "system", "content": instructions})

    pending_reasoning = ""
    for item in req.get("input") or []:
        kind = item.get("type", "message")
        if kind == "reasoning":
            pending_reasoning = item.get("encrypted_content") or "".join(
                part.get("text", "") for part in item.get("summary") or [])
            continue
        if kind == "message":
            role = item.get("role", "user")
            if role == "developer":
                role = "system"
            message = {"role": role, "content": text_of(item.get("content"))}
            if role == "assistant" and pending_reasoning:
                message["reasoning_content"] = pending_reasoning
                pending_reasoning = ""
            messages.append(message)
        elif kind == "function_call":
            message = {
                "role": "assistant",
                "content": "",
                "tool_calls": [{
                    "id": item.get("call_id") or item.get("id") or "call_0",
                    "type": "function",
                    "function": {"name": item.get("name", ""),
                                 "arguments": item.get("arguments") or "{}"},
                }],
            }
            if pending_reasoning:
                message["reasoning_content"] = pending_reasoning
                pending_reasoning = ""
            messages.append(message)
        elif kind == "function_call_output":
            output = item.get("output")
            messages.append({
                "role": "tool",
                "tool_call_id": item.get("call_id") or "call_0",
                "content": output if isinstance(output, str) else text_of(output),
            })
        # その他のitem種別は判定へ寄与しないため転送しない

    tools = []
    for tool in req.get("tools") or []:
        if tool.get("type") == "function":
            tools.append({"type": "function", "function": {
                "name": tool.get("name", ""),
                "description": tool.get("description", ""),
                "parameters": tool.get("parameters") or {"type": "object", "properties": {}},
            }})

    chat = {
        "model": req.get("model"),
        "messages": messages,
        "stream": True,
        "stream_options": {"include_usage": True},
    }
    if tools:
        chat["tools"] = tools
        chat["tool_choice"] = req.get("tool_choice", "auto")
    return chat


def to_responses_usage(usage: dict) -> dict:
    return {
        "input_tokens": usage.get("prompt_tokens", 0),
        "output_tokens": usage.get("completion_tokens", 0),
        "total_tokens": usage.get("total_tokens", 0),
        "input_tokens_details": {
            "cached_tokens": (usage.get("prompt_tokens_details") or {}).get("cached_tokens", 0)},
        "output_tokens_details": {
            "reasoning_tokens": (usage.get("completion_tokens_details") or {})
            .get("reasoning_tokens", 0)},
    }


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    upstream = "https://api.deepseek.com"

    def log_message(self, *args):  # 既定のaccess logを出さない（秘密混入防止の一環）
        pass

    def _sse(self, event_type: str, payload: dict) -> None:
        payload = dict(payload)
        payload["type"] = event_type
        data = json.dumps(payload, ensure_ascii=False)
        self.wfile.write(f"event: {event_type}\ndata: {data}\n\n".encode("utf-8"))
        self.wfile.flush()

    def do_POST(self):
        if self.path.rstrip("/") != "/responses":
            self.send_error(404)
            return
        length = int(self.headers.get("Content-Length", 0))
        try:
            req = json.loads(self.rfile.read(length))
            chat_req = to_chat_request(req)
        except (ValueError, TypeError) as exc:
            body = json.dumps({"error": {"message": f"bridge: bad request: {exc}",
                                         "type": "invalid_request_error"}}).encode()
            self.send_response(400)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            return

        upstream_req = urllib.request.Request(
            self.upstream + "/chat/completions",
            data=json.dumps(chat_req).encode("utf-8"),
            headers={
                "Content-Type": "application/json",
                "Accept": "text/event-stream",
                # 秘密は転送するだけで保持・記録しない
                "Authorization": self.headers.get("Authorization", ""),
            }, method="POST")
        try:
            stream = urllib.request.urlopen(upstream_req, timeout=600)
        except urllib.error.HTTPError as exc:
            body = exc.read()
            self.send_response(exc.code)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            return
        except OSError as exc:
            body = json.dumps({"error": {"message": f"bridge: upstream unreachable: {exc}",
                                         "type": "server_error"}}).encode()
            self.send_response(502)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            return

        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.send_header("Cache-Control", "no-cache")
        self.send_header("Connection", "close")
        self.end_headers()

        response_id = "resp_bridge"
        self._sse("response.created",
                  {"response": {"id": response_id, "status": "in_progress", "output": []}})

        output = []            # 確定済みoutput items
        text_buf = []          # 進行中message text
        text_open = False
        tool_calls = {}        # index -> {id, name, arguments}
        reasoning_buf = []     # 進行中reasoning（encrypted_contentとしてcodexへ返す）
        usage = {}

        def flush_reasoning():
            """reasoningをitem化してcodexへ返す。次requestで履歴として戻ってくる。"""
            if not reasoning_buf:
                return
            item = {"type": "reasoning", "id": f"rs_{len(output)}",
                    "summary": [],
                    "encrypted_content": "".join(reasoning_buf)}
            output.append(item)
            self._sse("response.output_item.done",
                      {"output_index": len(output) - 1, "item": item})
            reasoning_buf.clear()

        def close_message():
            nonlocal text_open
            if not text_open:
                return
            item = {"type": "message", "id": f"msg_{len(output)}", "role": "assistant",
                    "status": "completed",
                    "content": [{"type": "output_text", "text": "".join(text_buf),
                                 "annotations": []}]}
            output.append(item)
            self._sse("response.output_item.done",
                      {"output_index": len(output) - 1, "item": item})
            text_open = False
            text_buf.clear()

        def close_tool_calls():
            for index in sorted(tool_calls):
                call = tool_calls[index]
                item = {"type": "function_call", "id": f"fc_{len(output)}",
                        "status": "completed", "call_id": call["id"],
                        "name": call["name"], "arguments": call["arguments"]}
                output.append(item)
                self._sse("response.output_item.done",
                          {"output_index": len(output) - 1, "item": item})
            tool_calls.clear()

        for raw in stream:
            line = raw.decode("utf-8", errors="replace").strip()
            if not line.startswith("data:"):
                continue
            data = line[5:].strip()
            if data == "[DONE]":
                break
            try:
                chunk = json.loads(data)
            except ValueError:
                continue
            if chunk.get("usage"):
                usage = chunk["usage"]
            for choice in chunk.get("choices") or []:
                delta = choice.get("delta") or {}
                reasoning = delta.get("reasoning_content")
                if reasoning:
                    reasoning_buf.append(reasoning)
                content = delta.get("content")
                if content:
                    if not text_open:
                        flush_reasoning()
                        text_open = True
                        self._sse("response.output_item.added",
                                  {"output_index": len(output),
                                   "item": {"type": "message", "id": f"msg_{len(output)}",
                                            "role": "assistant", "status": "in_progress",
                                            "content": []}})
                    text_buf.append(content)
                    self._sse("response.output_text.delta",
                              {"item_id": f"msg_{len(output)}",
                               "output_index": len(output), "content_index": 0,
                               "delta": content})
                for tc in delta.get("tool_calls") or []:
                    flush_reasoning()
                    index = tc.get("index", 0)
                    slot = tool_calls.setdefault(
                        index, {"id": f"call_{index}", "name": "", "arguments": ""})
                    if tc.get("id"):
                        slot["id"] = tc["id"]
                    fn = tc.get("function") or {}
                    if fn.get("name"):
                        slot["name"] = fn["name"]
                    slot["arguments"] += fn.get("arguments") or ""
                # reasoning_contentは転送しない

        flush_reasoning()
        close_message()
        close_tool_calls()
        completed = {"id": response_id, "status": "completed", "output": output,
                     "usage": to_responses_usage(usage)}
        self._sse("response.completed", {"response": completed})
        try:
            stream.close()
        except OSError:
            pass


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--upstream", default="https://api.deepseek.com")
    parser.add_argument("--port", type=int, default=0,
                        help="0なら空きportへbindし、実portを標準出力へ出す")
    args = parser.parse_args()

    Handler.upstream = args.upstream.rstrip("/")
    server = ThreadingHTTPServer(("127.0.0.1", args.port), Handler)
    print(server.server_address[1], flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    return 0


if __name__ == "__main__":
    sys.exit(main())
