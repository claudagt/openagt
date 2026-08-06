#!/usr/bin/env python3
"""client固有のtraceを、grade-case.pyが読む正準trace語彙へ写像する。

正準語彙は`evals/EVALS.md#Context trace`が所有する:
  phase / search / cache / read / run / write / summary

設計の要点（docs/EVALUATION.md#traceと公開証拠）:

- **write系はclient eventに依存しない。** runnerがsubject sandboxのGit状態から観測する。
  HG-02・must_not_write・may_writeはHard Gateの中核であり、clientがeventを出さない、
  または形式を変えただけで違反が見逃されてはならない。
- read / run はGitから観測できないためclient eventに依存する。**写像できなかったeventを
  黙って捨てない。** 捨てるとmust_not_run違反がPASSへ化ける。未知のeventはunmappedとして
  数え、coverageへ記録する。write以外の観測が不完全なcaseはgrade-case.py側で
  UNVERIFIEDになる（証拠が無いものを合格にしない）。
- 各clientのevent schemaは実測でのみ確定する。未確認の写像規則をverified扱いしない。

client写像規則の状態:
  codex: thread.started / turn.started / error / turn.failed は実runで確認済み。
         item系（command_execution、file_change等）のfield名は未確認のため、
         推測でmapせずunmappedとして数える。実traceが得られた時点で追加する。
"""

import argparse
import json
import pathlib
import subprocess
import sys

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


def map_codex_events(raw_events):
    """codexのJSONL eventを正準語彙へ写像する。未知のeventはunmappedへ回す。"""
    mapped, unmapped = [], []
    for event in raw_events:
        kind = event.get("type") or event.get("event") or ""
        if kind in CODEX_CONTROL_EVENTS:
            continue
        # 実測で確認済みの写像規則がまだ無いため、他はすべてunmappedとする。
        # 推測でreadやrunへ写像すると、誤った合格を生む。
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

    writes, git_error = git_writes(pathlib.Path(args.subject))
    if writes is not None:
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
        "read_run_observation": "client-events" if any(
            k in observed_kinds for k in ("read", "run")) else "unavailable",
        "complete": not unmapped and writes is not None,
    }
    pathlib.Path(args.meta_out).write_text(
        json.dumps(meta, indent=2, sort_keys=True, ensure_ascii=False) + "\n", encoding="utf-8")

    print(f"TRACE_MAPPED mapped={len(mapped)} unmapped={len(unmapped)} "
          f"writes={'git' if writes is not None else 'unavailable'}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
