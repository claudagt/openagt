#!/usr/bin/env python3
"""client固有のtraceを、grade-case.pyが読む正準trace語彙へ写像する。

正準語彙は`evals/EVALS.md#Context trace`が所有する:
  phase / search / cache / read / run / write / summary

設計の要点（docs/HARNESS.md#traceと公開証拠）:

- **write系はclient eventに依存しない。** runnerがsubject sandboxのGit状態から観測する。
  HG-02・must_not_write・may_writeはHard Gateの中核であり、clientがeventを出さない、
  または形式を変えただけで違反が見逃されてはならない。
- read / run はGitから観測できないためclient eventに依存する。**写像できなかったeventを
  黙って捨てない。** 捨てるとmust_not_run違反がPASSへ化ける。未知のeventはunmappedとして
  数え、coverageへ記録する。write以外の観測が不完全なcaseはgrade-case.py側で
  UNVERIFIEDになる（証拠が無いものを合格にしない）。
- 各clientのevent schemaは実測でのみ確定する。未確認の写像規則をverified扱いしない。

client写像規則の状態（2026-08-06、codex-cli 0.146.0の実runで確認）:
  codex: thread.started / turn.started / turn.completed / turn.failed / error（制御）、
         item.started / item.updated / item.completed（item.type = command_execution / file_change /
         agent_message / reasoning / error）。command_executionのみを正準語彙へ写像する。
         file_changeは出るがwriteの正本はGit観測とし、client申告に依存させない。
         **codexはfile読取専用のeventを出さない。** readは読取専用commandからの推定に留まり、
         byte数は取得できない（max_context_bytesは常にUNVERIFIED）。
"""

import argparse
import importlib.util
import json
import pathlib
import subprocess
import sys

# command正規化規則はgrade-case.pyが単一の正本。ここで別実装を持たない（HG-06）。
_spec = importlib.util.spec_from_file_location(
    "openagt_grade_case", pathlib.Path(__file__).resolve().parent / "grade-case.py")
_grade_case = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_grade_case)
unwrap_shell = _grade_case.unwrap_shell
SHELL_SEPARATORS = _grade_case.SHELL_SEPARATORS

# 実測で確認済みのevent type。写像しても正準traceへは出さない（制御event）。
CODEX_CONTROL_EVENTS = {"thread.started", "turn.started", "turn.completed",
                        "turn.failed", "error"}

# git status --porcelain のcodeから書込modeへの写像
GIT_STATUS_MODES = {
    "M": "update", "A": "create", "D": "delete",
    "R": "rename", "C": "create", "?": "create", "U": "update",
}


def git_writes(subject: pathlib.Path):
    """subject sandboxのGit状態から書込eventを観測する（client非依存）。"""
    try:
        out = subprocess.run(
            ["git", "-C", str(subject), "status", "--porcelain=v1", "-z", "--untracked-files=all"],
            capture_output=True, text=True, check=True,
        ).stdout
    except (OSError, subprocess.CalledProcessError) as exc:
        return None, f"git status failed: {exc}"

    events, fields = [], [f for f in out.split("\0") if f]
    i = 0
    while i < len(fields):
        entry = fields[i]
        if len(entry) < 4:
            i += 1
            continue
        code, path = entry[:2], entry[3:]
        mode = GIT_STATUS_MODES.get(code[0].strip() or code[1].strip() or "?", "update")
        if code[0] == "R":
            # rename は "R  new\0old" の順で並ぶ。両方を記録する。
            i += 1
            if i < len(fields):
                events.append({"event": "write", "path": fields[i], "mode": "delete"})
        events.append({"event": "write", "path": path, "mode": mode})
        i += 1
    return events, None


# 読取専用のfile accessと見なせるcommand。read eventの推定に使う。
# 書換えうるcommandは含めない（推定を広げると誤った合格を生む）。
READ_COMMANDS = ("cat", "head", "tail", "less", "more", "bat", "wc", "nl", "od")


def infer_read_paths(command: str):
    """command文字列から読まれたpathを推定する。

    codexはfile読取専用のeventを出さず、shell commandとして実行する。read eventが
    まったく得られないと`must_read`が常にUNVERIFIEDになり、どのcaseも判定できない。
    ここではcommand実行という**観測事実**から、読取専用commandの引数だけを拾う。
    自己申告ではないが推定ではあるため、coverageへinferredと明記する。

    実測（2026-08-06）: agentは`cat A && echo '---' && cat B`のような複合commandを
    使う。全体を空白分割すると`echo`や区切り文字列までpathとして拾ってしまい、
    must_not_readの誤検出につながる。segmentへ分解し、各segmentの先頭が読取専用
    commandのときだけ、その引数からpathらしいtokenを取る。
    """
    paths = []
    for segment in SHELL_SEPARATORS.split(unwrap_shell(command)):
        tokens = segment.strip().split()
        if not tokens:
            continue
        head = tokens[0].rsplit("/", 1)[-1]
        if head not in READ_COMMANDS:
            continue
        for token in tokens[1:]:
            token = token.strip("'\"")
            if not token or token.startswith("-"):
                continue
            if any(c in token for c in "<>|&$`*?="):
                continue
            # pathらしさ: separatorを含むか、既知の拡張子を持つもののみ採る。
            if "/" not in token and "." not in token:
                continue
            paths.append(token)
    return paths


# clientがcontextへ自動注入するファイル。commandとして現れないため、
# 注入を数えないとmust_readが誤ってFAILになる。
#
# 実測（2026-08-06、codex-cli 0.146.0）: codexのbase instructionsは
# 「repo rootおよびCWDからrootまでのAGENTS.mdの内容はdeveloper messageに含まれるので
# 再読不要」と明言しており、`codex debug prompt-input`でsubjectのAGENTS.md本文が
# model入力に含まれることを確認した。したがってagentが`cat AGENTS.md`しないのは
# 正しい挙動であり、未読ではない。
CLIENT_INJECTED_CONTEXT = {
    # subject rootからの相対path
    "codex": ("AGENTS.md",),
    "canonical": (),
}


def injected_reads(client: str, subject: pathlib.Path):
    """clientがcontextへ自動注入したファイルをread eventとして返す。"""
    events = []
    for relative in CLIENT_INJECTED_CONTEXT.get(client, ()):
        target = subject / relative
        if target.is_file():
            events.append({"event": "read", "path": relative,
                           "bytes": target.stat().st_size,
                           "source": "client-injected-context"})
    return events


# Route → 入口正本。subjectの`AGENTS.md#Route`表が定義する対応をそのまま使う。
# 独自の判定基準を作らない（判定はどの入口を実際に読んだかという観測に基づく）。
ROUTE_ENTRY_CANON = {
    "knowledge/KNOWLEDGE.md": "knowledge",
    "skills/SKILLS.md": "skill",
    "projects/AGENTS.md": "project",
}

# metaは固有のbootstrap入口を持たず、入口は対象領域の正本そのもの（subjectの
# AGENTS.md#Route表）。主要3Routeの入口をひとつも読まずに領域正本を読んだ場合だけ
# metaを導出する（残余則）。主要入口を読んだ作業はそのRouteが支配するため、
# 領域正本の併読ではmetaへ倒さない。2026-08-07人間決定（これが無いとroute: metaは
# 観測上導出不能で、meta系caseが構造的にPASS不能だった）。
META_AREA_CANON = ("tools/TOOLS.md", "tools/BACKUP.md", "tools/CONTROL.md",
                   "evals/EVALS.md")


def infer_route(read_events):
    """読まれた入口正本からRouteを導出する。

    codexはroute/search eventを出さないため、これが無いと全caseで`route`が
    UNVERIFIEDになり、どのcaseもPASSに到達できない。入口正本の読取という観測事実から
    導出し、複数Routeの入口を読んでいて一意に決まらない場合は導出しない（fail closed）。
    metaは残余則: 主要入口の読取がゼロで、meta領域正本の読取があるときだけ導出する。
    """
    routes = set()
    meta_seen = False
    for event in read_events:
        path = (event.get("path") or "").lstrip("./")
        for entry, route in ROUTE_ENTRY_CANON.items():
            if path == entry or path.endswith("/" + entry):
                routes.add(route)
        for entry in META_AREA_CANON:
            if path == entry or path.endswith("/" + entry):
                meta_seen = True
    if len(routes) == 1:
        return routes.pop()
    if not routes and meta_seen:
        return "meta"
    return None


def map_codex_events(raw_events):
    """codexのJSONL eventを正準語彙へ写像する。未知のeventはunmappedへ回す。

    実測schema（codex-cli 0.146.0、2026-08-06の実runで確認）:
      {"type":"item.completed","item":{"type":"command_execution",
       "command":"/bin/zsh -lc '...'","exit_code":0,"status":"completed"}}
    item.startedはitem.completedと重複するため採らない。
    """
    mapped, unmapped = [], []
    for event in raw_events:
        kind = event.get("type") or event.get("event") or ""
        if kind in CODEX_CONTROL_EVENTS:
            continue
        if kind in ("item.started", "item.updated"):
            # 最終状態はitem.completedが持つ。ここで拾うと二重計上になる。
            # item.updatedはplan（todo_list）の途中更新でも出る。
            continue
        if kind == "item.completed":
            item = event.get("item") or {}
            item_type = item.get("item_type") or item.get("type") or ""
            if item_type == "command_execution":
                command = str(item.get("command", ""))
                mapped.append({"event": "run", "command": command,
                               "exit_code": item.get("exit_code")})
                for path in infer_read_paths(command):
                    mapped.append({"event": "read", "path": path, "bytes": None,
                                   "inferred": True})
                continue
            if item_type == "file_change":
                # codexはfile_changeも出すが、writeの正本はGit観測とする。
                # clientの申告に依存させないため、ここでは採用しない（unmappedでもない）。
                continue
            if item_type in ("agent_message", "reasoning", "error", "todo_list",
                             "web_search", "mcp_tool_call"):
                continue  # 判定に使う正準語彙を持たない
            unmapped.append(f"item.completed/{item_type or '<none>'}")
            continue
        unmapped.append(kind or "<no-type>")
    return mapped, unmapped


# 正準語彙をそのまま出すclient用。harness自己検証のstub adapterと、
# 将来的に正準語彙で出力するclientが使う。writeはこちらでも採用せず、Gitを優先する。
CANONICAL_EVENTS = {"phase", "search", "cache", "read", "run", "summary", "route", "report"}


def map_canonical_events(raw_events):
    mapped, unmapped = [], []
    for event in raw_events:
        kind = event.get("event") or event.get("type") or ""
        if kind in CANONICAL_EVENTS:
            mapped.append(event)
        elif kind == "write":
            continue  # writeはGit観測を正本とし、自己申告を採らない
        else:
            unmapped.append(kind or "<no-type>")
    return mapped, unmapped


MAPPERS = {"codex": map_codex_events, "canonical": map_canonical_events}


def load_jsonl(path: pathlib.Path):
    events = []
    if not path.is_file():
        return events
    for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            event = json.loads(line)
        except json.JSONDecodeError:
            continue
        if isinstance(event, dict):
            events.append(event)
    return events


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--client", required=True, choices=sorted(MAPPERS))
    parser.add_argument("--client-events", required=True, help="client固有traceのJSONL")
    parser.add_argument("--subject", required=True, help="subject sandbox root（Git観測用）")
    parser.add_argument("--out", required=True, help="正準trace JSONLの出力先")
    parser.add_argument("--meta-out", required=True, help="coverage情報の出力先JSON")
    args = parser.parse_args()

    raw = load_jsonl(pathlib.Path(args.client_events))
    mapped, unmapped = MAPPERS[args.client](raw)

    # clientが自動注入したcontextもreadとして数える（commandには現れない）
    subject_path = pathlib.Path(args.subject)
    injected = injected_reads(args.client, subject_path)
    mapped.extend(injected)

    # Routeは入口正本の読取から導出する（clientがroute eventを出さないため）。
    inferred_route = infer_route([e for e in mapped if e.get("event") == "read"])
    if inferred_route:
        mapped.append({"event": "route", "value": inferred_route, "inferred": True})

    writes, git_error = git_writes(subject_path)
    if writes is not None:
        # write観測はGit由来で**完全**である。空であることは「不明」ではなく
        # 「書き込んでいない」を意味する。grade-case.pyがこれを区別できるよう、
        # traceへ完全性マーカーを載せる（載せないと、正しく何も書かなかったsubjectが
        # must_not_writeを証明できずUNVERIFIEDになる）。
        mapped.append({"event": "coverage", "observation": "write",
                       "source": "git", "complete": True})
        mapped.extend(writes)

    out_path = pathlib.Path(args.out)
    out_path.write_text(
        "".join(json.dumps(e, sort_keys=True, ensure_ascii=False) + "\n" for e in mapped),
        encoding="utf-8")

    observed_kinds = {e["event"] for e in mapped}
    meta = {
        "schema": "openagt-trace-coverage/v1",
        "client": args.client,
        "raw_event_count": len(raw),
        "mapped_event_count": len(mapped),
        "unmapped_event_count": len(unmapped),
        "unmapped_event_types": sorted(set(unmapped)),
        # 観測できた語彙。ここに無い語彙の期待項目はUNVERIFIEDになる。
        "observed_vocabulary": sorted(observed_kinds),
        "write_observation": "git" if writes is not None else "unavailable",
        "write_observation_error": git_error,
        # readとrunはclient event由来。写像規則が未確立なら不完全と明示する。
        "run_observation": "client-events" if "run" in observed_kinds else "unavailable",
        # readはclientがeventを出さないため、読取専用commandからの推定。
        # 観測事実（command実行）に基づくが推定であることを明示する。
        "read_observation": ("inferred-from-commands" if "read" in observed_kinds
                             else "unavailable"),
        # Routeはclient eventでは得られず、入口正本の読取から導出する。
        # 複数Routeの入口を読んでいて一意に決まらない場合は導出しない。
        "route_observation": ("inferred-from-entry-canon" if inferred_route
                              else "unavailable"),
        "client_injected_reads": [e["path"] for e in injected],
        "complete": not unmapped and writes is not None,
    }
    pathlib.Path(args.meta_out).write_text(
        json.dumps(meta, indent=2, sort_keys=True, ensure_ascii=False) + "\n", encoding="utf-8")

    print(f"TRACE_MAPPED mapped={len(mapped)} unmapped={len(unmapped)} "
          f"writes={'git' if writes is not None else 'unavailable'}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
