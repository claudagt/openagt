#!/usr/bin/env python3
"""baseline runとcandidate runを決定的に比較する（A/Aを含む）。

Hard Gate・validityの判定はgrade-run.pyへ委譲し、判定器を二重化しない。
閾値の意味定義（MDE = max(policy固定幅, A/Aノイズ幅)）はdocs/EVALUATION.mdが所有する。

decision:
  INVALID     -- どちらかのrunがINVALID、または実行条件hashが一致しない（HG-11）
  REJECTED    -- candidateのHard Gate違反、またはMDE超の主要指標regression
  AA_UNSTABLE -- 同一SHA比較で差がノイズ許容を超えた（runner/grader/環境を先に修正）
  NO_CHANGE   -- 差がMDE未満。正しい成果として扱う
  ELIGIBLE    -- MDE超の改善。PR昇格条件の他項目の検査へ進める

exit code: 0 = NO_CHANGE/ELIGIBLE, 1 = REJECTED/AA_UNSTABLE, 2 = INVALID, 3 = usage error
"""

import argparse
import json
import pathlib
import subprocess
import sys

SCRIPT_DIR = pathlib.Path(__file__).resolve().parent
GRADER = SCRIPT_DIR / "grade-run.py"
CONDITION_KEYS = ("suite_hash", "grader_hash", "execution_config_hash")
# EVALUATION.md#A/AとMDEが所有する固定下限。CLIから緩和させない。
POLICY_MIN_IMPROVEMENT_PP = 8.0


def policy_conditions_differ(base: dict, cand: dict) -> bool:
    """HG-11のpolicy側判定（v1.1.0）。

    測定意味論hash（measurement hash）が両manifestにあればそれで比較する。統治規定のみの
    policy改訂でrunが比較不能にならないようにするため。片方でも持たない旧記録は、従来
    どおりpolicy hash全体で比較する（fail closed）。
    """
    if "measurement_hash" in base and "measurement_hash" in cand:
        return base["measurement_hash"] != cand["measurement_hash"]
    return base.get("policy_hash") != cand.get("policy_hash")


def grade(run_dir: pathlib.Path) -> dict:
    result = subprocess.run(
        [sys.executable, str(GRADER), str(run_dir)],
        capture_output=True, text=True,
    )
    if result.returncode == 3 or not result.stdout.strip():
        raise RuntimeError(f"grader failed on {run_dir}: {result.stderr.strip()}")
    return json.loads(result.stdout)


def load_manifest(run_dir: pathlib.Path) -> dict:
    path = run_dir / "manifest.json"
    if not path.is_file():
        return {}
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except ValueError:
        return {}


def decide(args) -> dict:
    baseline_dir = pathlib.Path(args.baseline)
    candidate_dir = pathlib.Path(args.candidate)
    base_verdict = grade(baseline_dir)
    cand_verdict = grade(candidate_dir)
    base_manifest = load_manifest(baseline_dir)
    cand_manifest = load_manifest(candidate_dir)

    report = {
        "baseline": {"dir": str(baseline_dir), "verdict": base_verdict},
        "candidate": {"dir": str(candidate_dir), "verdict": cand_verdict},
        "metric": args.metric,
    }

    if base_verdict["validity"] != "VALID" or cand_verdict["validity"] != "VALID":
        report.update(decision="INVALID",
                      reason="one or both runs are INVALID (missing conditions/trace)")
        return report

    mismatched = [k for k in CONDITION_KEYS
                  if base_manifest.get(k) != cand_manifest.get(k)]
    if policy_conditions_differ(base_manifest, cand_manifest):
        mismatched.insert(0, "measurement/policy_hash")
    if mismatched:
        report.update(decision="INVALID",
                      reason=f"execution conditions differ (HG-11): {', '.join(mismatched)}")
        return report

    if cand_verdict["gate"] != "PASS":
        report.update(decision="REJECTED",
                      reason="candidate violates Hard Gate",
                      violations=cand_verdict["violations"])
        return report

    try:
        base_value = float(base_verdict["metrics"][args.metric])
        cand_value = float(cand_verdict["metrics"][args.metric])
    except (KeyError, TypeError, ValueError):
        report.update(decision="INVALID",
                      reason=f"primary metric missing or non-numeric: {args.metric}")
        return report

    delta_pp = (cand_value - base_value) * 100.0
    effective_mde_pp = max(POLICY_MIN_IMPROVEMENT_PP, args.aa_noise_pp)
    report.update(baseline_value=base_value, candidate_value=cand_value,
                  delta_pp=round(delta_pp, 6), effective_mde_pp=effective_mde_pp)

    same_sha = (base_manifest.get("source_sha") == cand_manifest.get("source_sha"))
    if same_sha:
        if abs(delta_pp) > args.aa_noise_pp:
            report.update(decision="AA_UNSTABLE",
                          reason="same-SHA comparison exceeds noise tolerance; "
                                 "fix runner/grader/adapter/environment first")
        else:
            report.update(decision="NO_CHANGE", reason="A/A within noise tolerance")
        return report

    if delta_pp >= effective_mde_pp:
        report.update(decision="ELIGIBLE",
                      reason="primary metric improves beyond MDE; "
                             "remaining PR promotion conditions still apply")
    elif delta_pp <= -effective_mde_pp:
        report.update(decision="REJECTED",
                      reason="primary metric regresses beyond MDE")
    else:
        report.update(decision="NO_CHANGE", reason="delta below MDE")
    return report


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--baseline", required=True)
    parser.add_argument("--candidate", required=True)
    parser.add_argument("--metric", default="requirement_pass_rate")
    parser.add_argument("--aa-noise-pp", type=float, default=2.0,
                        help="A/Aで観測したノイズ幅（パーセントポイント）")
    args = parser.parse_args()

    try:
        report = decide(args)
    except (RuntimeError, ValueError) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 3

    print(json.dumps(report, sort_keys=True, indent=2, ensure_ascii=False))
    decision = report["decision"]
    if decision == "INVALID":
        return 2
    if decision in ("REJECTED", "AA_UNSTABLE"):
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
