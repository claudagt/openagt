---
updated_at: 2026-08-08
---

# Current State

## 現在の到達点

- policy **v1.1.1**で全検証合格（verify.sh）。段階評価・逐次trial・baseline再利用・
  measurement hashを導入し、full A/B既定を廃止。入口は`scripts/run-eval.sh`。
- A/A STABLE。採用revision `4bbef9f`の既定flash configでbaseline+A/Aを再取得し、
  42/42 run完了、INFRA 0、観測ノイズ0.04pp・有効ノイズ2.66pp < MDE 8pp。
- A/B実績: 上流差分2回=NO_CHANGE、v2/v3=REJECTED（v3は安全違反根絶→Issue #3→上流PR #5
  でmerge）、v4/v5=REJECTED_EARLY（must_run省略が残存）。数値・SHA・経緯は`runs/`が持つ。
- **上流を`4a188ca`→`4bbef9f`へ同期済み**（2026-08-08、PR #42）。参照解決checker分離、
  docs-project兄弟参照fixture、Project所有plist fixtureを上流blobどおり採用した。Issue #18は上流採用済みで、
  報告観測は`report_match` + trace event `final_response`として`evals/EVALS.md#報告の観測`が
  正本のまま。新baseline証拠は`runs/2026-08-08-aa6-baseline-4bbef9f.json`が持つ。

## 現在の目標

対象契約: `PROJECT.md#PC-07`

`4bbef9f`の固定baselineを使い、次の上流更新を段階評価（Stage 0-2）から判定する。

## 目標の合格条件

- 採用revisionとbaseline source SHAが`4bbef9fefeae4247d5ea2bf5d24bf319ec875b15`で一致する。
- baselineとA/Aが同一execution config・suite・grader・measurement・policy・case集合hashで揃う。
- 7 case × 3 trial × 2 roleが完全で、INFRAを分離し、A/A有効ノイズ < MDE 8ppである。
- 次の上流更新はStage 0（gate）から始め、hash不一致の旧baselineを比較へ使わない。

## 検証結果

- 対象: `PROJECT.md#PC-07`
  2026-08-08 / `4bbef9f` baseline+A/A 42 run → 合格。INFRA 0、coverage 89.74% / 90.17%、
  観測ノイズ0.04pp、有効ノイズ2.66pp < MDE 8pp、STABLE。
- 対象: `PROJECT.md#PC-05`
  2026-08-08 / verify.sh内secret scan → 合格。検出ゼロ。
- 対象: `PROJECT.md#PC-02`
  2026-08-06 / adapter selftestと実runのprobe → 合格。write境界・network遮断はOS強制。
- 対象: `PROJECT.md#PC-01`
  2026-08-08 / 上流`4bbef9f`同期後のverify.sh＋validator --strict --full → 合格。
  42 runでsource・execution config hash一意、suite・grader・measurement・policy・case集合hashを記録。

## 未完了・ブロッカー

- Tier 0は`4bbef9f` baselineで4件中1件だけ3/3（project-goal-change-protection）。
  HG-12は未達で、candidateが全4件3/3にしない限り昇格は閉じたまま。
- 旧`runs/`は旧suite・旧policyの記録。HG-11により新runと対にしない。
- `report_match`パターンを持つcaseは現在family 10の1件だけ。他caseのmust_reportは付与まで
  UNVERIFIEDのまま（付与は都度、意味の最小核だけを縛る）。
- `codex-adapter.sh`のexecution configは`timeout_sec: 900`を記録するが、外部killとしては
  強制していない。今回42 runは全件正常終了したため結果は有効だが、timeout再現性はUNVERIFIED。
- 構造上の観測の限界（read推定・route導出・model非観測・生log）は
  `projects/agent-directory-evaluation/docs/HARNESS.md#観測の限界`が所有する。

## 現在有効な決定

- 初期source revision: `8325b185fb9410bff44cf6ec9a9b99246fe8cc0f`（bootstrap記録）。
  採用済みupstream revisionは`git config agent-directory.upstream-revision`が持つ。
- 評価policy **v1.1.1**（利用者決定2026-08-08。変更は人間の明示決定のみ）。段階評価、
  MDE 8pp、HG-11、driver入口`run-eval.sh`等の正本は`docs/EVALUATION.md`であり複製しない。
- **現行suite採用**（利用者決定2026-08-07）: 89 case。`4bbef9f`でのsuite hashは
  `runs/2026-08-08-aa6-baseline-4bbef9f.json`が持つ。
- 直近baseline: `4bbef9fefeae4247d5ea2bf5d24bf319ec875b15`（flash 91.90% pooled充足率、
  coverage 89.74%、A/A観測ノイズ0.04pp / SE 2.66pp / 有効ノイズ2.66pp）。proは旧条件のまま
  で比較不能（Stage 3で使う時に同一hashで再取得）。
- **Tier 0は4件**（利用者決定2026-08-07、`docs/tier0-cases.txt`）: 従来3件＋
  external-effect-approval-gate。meta-route-validator-changeは観測意味論の限界で除外のまま。
- Draft PR作成は昇格条件充足時のみ別Promotion session（standing approval、2026-08-06）。
- 上流報告の経路は2種（`docs/EVALUATION.md#上流Issue`）。評価由来Issueもv1.1.1で
  standing approval化（利用者決定2026-08-08。条件充足時は確認不要、義務ではない）。
- clientはcodex（唯一OS強制sandbox・`--json`・hermetic）、providerはDeepSeek
  （`wire_api="responses"`直結、proは`responses-bridge.py`経由）。グローバルcodex設定
  不変、run毎`-c`指定。秘密はauth commandで渡し、秘密ファイルはCODEX_HOME外。
- 自己申告を判定に使わない。write観測はGit由来で完全（write event空=「書込なし」の証拠）。

## 失敗・却下済み

- gemini 0.46.0の`-s/--sandbox`: container runtime要のため除外。
- 「subjectがroot `AGENTS.md`未読」所見: **誤検出につき撤回**（codexが自動注入し
  「再読不要」と指示。注入を数えないと65/78誤FAIL）。
- codexの`-P`profile経由の`sandbox_workspace_write.exclude_*`上書き: 実測で無効。
- must_reportのキーワード即席照合: 採用しない（ノイズをHard Gateへ持ち込まない）。
  schema拡張として上流提案し、Issue #18として**上流採用済み**（2026-08-08同期）。

新しい根拠または利用者の明示指示がない限り、ここにある方法を繰り返さない。

## 次の一手

1. 次の上流revisionは`run-eval.sh --stage gate`から入り、EVAL_REQUIRED時だけ`4bbef9f`の
   hash一致baselineを比較へ使う。条件hashが動いた場合は再取得する。
2. **手順省略問題は仮説2/3消費で一時停止**（`runs/2026-08-08-ab9-10-v4-v5-screening.json`）。
   最後の枠は「finalizeを`tools/finalize-task.sh`実行として固定」だが、wrapper経由の検証を
   must_run充足と数えるかの**観測意味論の人間決定が先**。または上流報告（利用者決定）。
3. execution configのmodel観測欠落を潰す（現在declared）。

本文は現在有効な状態と直近の検証だけに保ち、詳細履歴は`runs/`へ移す。
