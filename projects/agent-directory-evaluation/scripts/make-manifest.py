#!/usr/bin/env python3
"""run manifest生成。source/policy/suite/grader/configのSHA・hashを固定する。

決定的出力: 同じ入力からは常に同じmanifestを生成する。実行時刻は--run-atで
明示された場合だけ記録する。取得できない値は"unknown"とし、0にしない。
policyの意味定義はdocs/EVALUATION.mdが所有する。
"""

import argparse
import hashlib
import json
import pathlib
import subprocess
import sys

SCRIPT_DIR = pathlib.Path(__file__).resolve().parent
PROJECT_DIR = SCRIPT_DIR.parent
REPO_ROOT = PROJECT_DIR.parent.parent
POLICY_PATH = PROJECT_DIR / "docs" / "EVALUATION.md"
GRADER_PATH = SCRIPT_DIR / "grade-run.py"
SUITE_DIR = REPO_ROOT / "evals" / "cases"


def sha256_file(path: pathlib.Path) -> str:
    return "sha256:" + hashlib.sha256(path.read_bytes()).hexdigest()


def suite_hash(suite_dir: pathlib.Path) -> str:
    """evals/cases/*.yamlのpath+内容を辞書順で連結したhash。"""
    if not suite_dir.is_dir():
        return "unknown"
    digest = hashlib.sha256()
    for case in sorted(suite_dir.glob("*.yaml")):
        digest.update(case.name.encode("utf-8"))
        digest.update(b"\0")
        digest.update(case.read_bytes())
        digest.update(b"\0")
    return "sha256:" + digest.hexdigest()


def evaluator_sha() -> str:
    try:
        out = subprocess.run(
            ["git", "-C", str(REPO_ROOT), "rev-parse", "HEAD"],
            capture_output=True, text=True, check=True,
        )
        return out.stdout.strip()
    except (OSError, subprocess.CalledProcessError):
        return "unknown"


def config_hash(config_path: str) -> str:
    if not config_path:
        return "unknown"
    path = pathlib.Path(config_path)
    data = json.loads(path.read_text(encoding="utf-8"))
    canonical = json.dumps(data, sort_keys=True, separators=(",", ":"))
    return "sha256:" + hashlib.sha256(canonical.encode("utf-8")).hexdigest()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-sha", required=True,
                        help="評価対象runのsubject SHA（40桁hex）")
    parser.add_argument("--role", choices=["baseline", "candidate"], required=True)
    parser.add_argument("--trial", type=int, required=True)
    parser.add_argument("--execution-config", default="",
                        help="execution config JSONのpath。未指定はunknown")
    parser.add_argument("--run-at", default="",
                        help="実行日時(ISO 8601)。明示時だけ記録する")
    parser.add_argument("--out", default="-", help="出力先。既定はstdout")
    args = parser.parse_args()

    if len(args.source_sha) != 40 or any(c not in "0123456789abcdef" for c in args.source_sha):
        print("ERROR: --source-sha must be a 40-hex commit SHA", file=sys.stderr)
        return 3

    manifest = {
        "schema": "openagt-run-manifest/v1",
        "role": args.role,
        "trial": args.trial,
        "evaluator_sha": evaluator_sha(),
        "source_sha": args.source_sha,
        "policy_hash": sha256_file(POLICY_PATH) if POLICY_PATH.is_file() else "unknown",
        "suite_hash": suite_hash(SUITE_DIR),
        "grader_hash": sha256_file(GRADER_PATH) if GRADER_PATH.is_file() else "unknown",
        "execution_config_hash": config_hash(args.execution_config),
        "allowed_write_roots": ["subject/"],
        "evaluator_paths": ["projects/agent-directory-evaluation/", "tools/", "evals/"],
    }
    if args.run_at:
        manifest["run_at"] = args.run_at

    rendered = json.dumps(manifest, sort_keys=True, indent=2, ensure_ascii=False) + "\n"
    if args.out == "-":
        sys.stdout.write(rendered)
    else:
        pathlib.Path(args.out).write_text(rendered, encoding="utf-8")
    return 0


if __name__ == "__main__":
    sys.exit(main())
