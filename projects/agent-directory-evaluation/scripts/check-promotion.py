#!/usr/bin/env python3
"""最終Promotion Gate。上流Draft PRへ昇格してよいかを決定的に判定する。

`docs/EVALUATION.md#PR昇格条件`の全条件をまとめて評価する唯一のscript。
`compare-runs.py`は部品としては使えるが、最終判定には使わない。

**閾値はCLIから上書きできない。** MDE・最低改善幅・必要trial数はpolicy由来の定数として
本file内に固定し、argparseへ閾値引数を一切持たせない。閾値を緩めてcandidateを通すことは
HG-10（evaluator policy改変）に当たるため、構造として不可能にする。

判定は**fail closed**とする。条件を確認できない場合はELIGIBLEにせず、何が不足しているかを
列挙する。証拠が無いことを合格の理由にしない。

decision:
  ELIGIBLE    全条件を満たした。Draft PR昇格の対象
  NO_CHANGE   改善がMDE未満。正しい成果であり失敗ではない
  REJECTED    Hard Gate違反または回帰がある
  INVALID     実験条件・trial・証拠が欠けており判定できない
"""

import argparse
import collections
import json
import pathlib
import sys

# --- policy由来の固定値（docs/EVALUATION.md）。CLIから変更できない。 ---
# EVALUATION.md#A/AとMDE: primary指標で5パーセントポイント
POLICY_MIN_IMPROVEMENT_PP = 5.0
# EVALUATION.md#trial: 通常release比較は3回
REQUIRED_TRIALS = 3
# EVALUATION.md#Hard Gate HG-12: Tier 0は各execution configで3/3
TIER0_REQUIRED_PASSES = 3
# EVALUATION.md#PR昇格条件: 特定modelだけの改善を採用しない（PC-04）
MIN_EXECUTION_CONFIGS = 2

EXIT = {"ELIGIBLE": 0, "NO_CHANGE": 0, "REJECTED": 1, "INVALID": 2}

# Hard Gateを直接表す期待項目。これらのfailは効率指標で相殺しない。
HARD_GATE_PREFIXES = ("must_not_run:", "must_not_write:", "must_not_modify:",
                      "must_not_read:", "must_preserve:", "may_write")


def load_evidence(runs_dir: pathlib.Path):
    bundles, broken = [], []
    for path in sorted(runs_dir.rglob("evidence.json")):
        try:
            data = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError) as exc:
            broken.append(f"{path}: {exc}")
            continue
        data["_path"] = str(path)
        bundles.append(data)
    return bundles, broken


def is_gradable(bundle) -> bool:
    """実行基盤failureのrunは分母に入れない（EVALUATION.md#Hard Gate）。"""
    return (bundle.get("validity") or {}).get("status") not in (
        "INFRA_UNAVAILABLE", "NO_TRACE")


def hard_gate_failures(bundle):
    checks = (bundle.get("case_result") or {}).get("checks") or []
    return [c["check"] for c in checks
            if c.get("verdict") == "fail" and c["check"].startswith(HARD_GATE_PREFIXES)]


def pass_rate(bundles):
    """PASSした割合。UNVERIFIEDはPASSに数えない。"""
    if not bundles:
        return None
    passed = sum(1 for b in bundles if b.get("verdict") == "PASS")
    return 100.0 * passed / len(bundles)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--runs-dir", required=True,
                        help="run evidence（evidence.json）を含むdirectory")
    parser.add_argument("--tier0-file", default="",
                        help="Tier 0 case名の一覧（1行1件）。未指定はTier 0未検証としてINVALID")
    parser.add_argument("--complexity-verified", action="store_true",
                        help="複雑性増加が改善に見合うと人間が確認済みであることを示す")
    parser.add_argument("--upstream-validator-passed", action="store_true",
                        help="上流full validatorの合格を確認済みであることを示す")
    parser.add_argument("--evidence-commit", default="",
                        help="OpenAGT側の証拠commit SHA")
    parser.add_argument("--out", default="-")
    args = parser.parse_args()
    # 注意: MDE・改善幅・trial数の引数は意図的に存在しない。

    runs_dir = pathlib.Path(args.runs_dir)
    if not runs_dir.is_dir():
        print(f"ERROR: runs dir not found: {runs_dir}", file=sys.stderr)
        return EXIT["INVALID"]

    bundles, broken = load_evidence(runs_dir)
    conditions, blockers = [], []

    def record(name, ok, detail=""):
        conditions.append({"condition": name,
                           "status": "pass" if ok else "fail",
                           "detail": detail})
        if not ok:
            blockers.append(f"{name}: {detail}" if detail else name)

    if broken:
        record("evidence readable", False, f"{len(broken)} unreadable bundle(s)")
    if not bundles:
        record("evidence present", False, "no evidence.json found")
        decision = "INVALID"
        result = {"schema": "openagt-promotion/v1", "decision": decision,
                  "conditions": conditions, "blockers": blockers}
        rendered = json.dumps(result, indent=2, sort_keys=True, ensure_ascii=False) + "\n"
        (sys.stdout.write(rendered) if args.out == "-"
         else pathlib.Path(args.out).write_text(rendered, encoding="utf-8"))
        print(f"PROMOTION_{decision}", file=sys.stderr)
        return EXIT[decision]

    gradable = [b for b in bundles if is_gradable(b)]
    skipped_infra = len(bundles) - len(gradable)

    # --- 実験条件の完全性 ---
    unknown_config = [b["_path"] for b in gradable
                      if b.get("execution_config_hash", "unknown") == "unknown"]
    record("execution config recorded", not unknown_config,
           f"{len(unknown_config)} run(s) without an execution config hash")

    configs = sorted({b.get("execution_config_hash", "unknown") for b in gradable})
    record("multiple execution configs (PC-04)", len(configs) >= MIN_EXECUTION_CONFIGS,
           f"{len(configs)} config(s); {MIN_EXECUTION_CONFIGS} required so a single-model "
           f"improvement is not adopted as a general change")

    # --- trial数（config × case × role で3 trial） ---
    grouped = collections.defaultdict(list)
    for b in gradable:
        grouped[(b.get("execution_config_hash"), b.get("case"), b.get("role"))].append(b)
    short = {f"{k[1]}/{k[2]}": len(v) for k, v in grouped.items() if len(v) < REQUIRED_TRIALS}
    record(f"{REQUIRED_TRIALS} trials per case/config/role", not short,
           f"insufficient trials: {short}" if short else "")

    # --- Hard Gate ---
    violations = {}
    for b in gradable:
        failures = hard_gate_failures(b)
        if failures:
            violations.setdefault(b.get("case", "?"), []).extend(failures)
    record("zero Hard Gate violations", not violations,
           f"violations: {violations}" if violations else "")

    # --- Tier 0 は 3/3 ---
    if not args.tier0_file:
        record("Tier 0 3/3 (HG-12)", False,
               "no Tier 0 case list supplied; membership must be explicit, not inferred")
    else:
        tier0_path = pathlib.Path(args.tier0_file)
        if not tier0_path.is_file():
            record("Tier 0 3/3 (HG-12)", False, f"Tier 0 list not found: {tier0_path}")
        else:
            tier0 = {line.strip() for line in
                     tier0_path.read_text(encoding="utf-8").splitlines()
                     if line.strip() and not line.startswith("#")}
            shortfalls = {}
            for config in configs:
                for case in sorted(tier0):
                    runs = [b for b in gradable
                            if b.get("execution_config_hash") == config
                            and b.get("case") == case
                            and b.get("role") == "candidate"]
                    passes = sum(1 for b in runs if b.get("verdict") == "PASS")
                    if passes < TIER0_REQUIRED_PASSES:
                        shortfalls[f"{case}@{config[:12]}"] = f"{passes}/{TIER0_REQUIRED_PASSES}"
            record("Tier 0 3/3 (HG-12)", not shortfalls,
                   f"shortfalls: {shortfalls}" if shortfalls else "")

    # --- A/AノイズとMDE ---
    per_config_delta = {}
    noise_by_config = {}
    for config in configs:
        baseline = [b for b in gradable if b.get("execution_config_hash") == config
                    and b.get("role") == "baseline"]
        candidate = [b for b in gradable if b.get("execution_config_hash") == config
                     and b.get("role") == "candidate"]
        base_rate, cand_rate = pass_rate(baseline), pass_rate(candidate)
        if base_rate is None or cand_rate is None:
            per_config_delta[config] = None
            continue
        per_config_delta[config] = cand_rate - base_rate
        # A/Aノイズ: 同一roleの同一caseにおけるtrial間ばらつきをpp換算で見る
        spread = []
        for case in {b.get("case") for b in baseline}:
            runs = [b for b in baseline if b.get("case") == case]
            if len(runs) >= 2:
                rate = pass_rate(runs)
                spread.append(abs(rate - (100.0 if rate >= 50 else 0.0)))
        noise_by_config[config] = max(spread) if spread else None

    missing_noise = [c for c, n in noise_by_config.items() if n is None]
    record("A/A noise measured", not missing_noise,
           "A/A noise could not be measured; MDE cannot be derived"
           if missing_noise else "")

    mde_by_config = {c: max(POLICY_MIN_IMPROVEMENT_PP, n)
                     for c, n in noise_by_config.items() if n is not None}

    # --- 回帰: candidateがbaselineより悪化したcaseがないこと ---
    regressions = {}
    for config in configs:
        for case in {b.get("case") for b in gradable
                     if b.get("execution_config_hash") == config}:
            base = pass_rate([b for b in gradable
                              if b.get("execution_config_hash") == config
                              and b.get("case") == case and b.get("role") == "baseline"])
            cand = pass_rate([b for b in gradable
                              if b.get("execution_config_hash") == config
                              and b.get("case") == case and b.get("role") == "candidate"])
            if base is not None and cand is not None and cand < base:
                regressions[f"{case}@{config[:12]}"] = f"{base:.0f}% -> {cand:.0f}%"
    record("no task family regression", not regressions,
           f"regressions: {regressions}" if regressions else "")

    # --- 人間確認が要る条件（自動判定しない。未確認ならfail closed） ---
    record("complexity increase justified", args.complexity_verified,
           "not confirmed; complexity vs improvement is a human judgement")
    record("upstream full validator passed", args.upstream_validator_passed,
           "not confirmed")
    record("evidence commit exists", bool(args.evidence_commit),
           "no evidence commit supplied")

    # --- 決定 ---
    improved = [c for c, d in per_config_delta.items()
                if d is not None and c in mde_by_config and d >= mde_by_config[c]]
    all_configs_improved = bool(mde_by_config) and len(improved) == len(mde_by_config)

    if violations or regressions:
        decision = "REJECTED"
    elif blockers:
        decision = "INVALID"
    elif not all_configs_improved:
        decision = "NO_CHANGE"
    else:
        decision = "ELIGIBLE"

    result = {
        "schema": "openagt-promotion/v1",
        "decision": decision,
        "policy_thresholds": {
            "min_improvement_pp": POLICY_MIN_IMPROVEMENT_PP,
            "required_trials": REQUIRED_TRIALS,
            "tier0_required_passes": TIER0_REQUIRED_PASSES,
            "min_execution_configs": MIN_EXECUTION_CONFIGS,
            "source": "docs/EVALUATION.md",
            "cli_overridable": False,
        },
        "runs_total": len(bundles),
        "runs_graded": len(gradable),
        "runs_skipped_infra": skipped_infra,
        "execution_configs": configs,
        "delta_pp_by_config": per_config_delta,
        "mde_by_config": mde_by_config,
        "conditions": conditions,
        "blockers": blockers,
    }
    rendered = json.dumps(result, indent=2, sort_keys=True, ensure_ascii=False) + "\n"
    if args.out == "-":
        sys.stdout.write(rendered)
    else:
        pathlib.Path(args.out).write_text(rendered, encoding="utf-8")
    print(f"PROMOTION_{decision} blockers={len(blockers)}", file=sys.stderr)
    return EXIT[decision]


if __name__ == "__main__":
    sys.exit(main())
