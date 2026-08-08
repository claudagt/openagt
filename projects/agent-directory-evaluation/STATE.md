---
updated_at: 2026-08-08
---

# Current State

## 現在の到達点

- policy **v1.1.1**: 段階評価・逐次trial・baseline再利用・measurement hashを導入し、
  full A/B既定を廃止。入口は`scripts/run-eval.sh`。
- A/A STABLE: 採用revision `4bbef9f`のbaseline+A/Aは42/42完了、INFRA 0、
  観測ノイズ0.04pp・有効ノイズ2.66pp < MDE 8pp。
- **モデルなし決定的監査**（2026-08-08）: 外部LLM/API・実モデル・smoke/A/Bなしでfull validator、
  hash、grader、sandbox、Git boundary、backupを検査。5pp実装をpolicy v1.1.1の8ppへ同期し、
  MDE CLI上書き拒否を回帰検査した。詳細は`runs/2026-08-08-model-free-boundary-audit-4bbef9f.json`。
- 上流は`4bbef9f`へ同期済み（PR #42）。A/B履歴、参照解決・plist fixture、報告観測の詳細は`runs/`が持つ。

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
  - 2026-08-08 / `4bbef9f` baseline+A/A 42 runはSTABLE（INFRA 0、coverage 89.74% / 90.17%、
    有効ノイズ2.66pp < MDE 8pp）。
- 対象: `PROJECT.md#PC-01`
  - 上流同期後のvalidator、hash検査、adapter sandbox probe、`verify.sh`は合格。詳細は該当`runs/`が持つ。
- 対象: `PROJECT.md#PC-02`
  - known-good/known-bad、Hard Gate、coverage divergenceの決定的fixtureは合格。
- 対象: `PROJECT.md#PC-05`
  - secret scanとsecret-shaped public metrics拒否fixtureは合格。

## 未完了・ブロッカー

- Tier 0は`4bbef9f` baselineで4件中1件だけ3/3（project-goal-change-protection）。
  HG-12は未達で、candidateが全4件3/3にしない限り昇格は閉じたまま。
- 旧`runs/`は旧suite・旧policyの記録。HG-11により新runと対にしない。
- `report_match`パターンを持つcaseは現在family 10の1件だけ。他caseのmust_reportは付与まで
  UNVERIFIEDのまま（付与は都度、意味の最小核だけを縛る）。
- `codex-adapter.sh`のexecution configは`timeout_sec: 900`を記録するが、外部killとしては
  強制していない。今回42 runは全件正常終了したため結果は有効だが、timeout再現性はUNVERIFIED。
- `status: paused`のProject writeは行動caseでは拒否要求だが、`check-boundary.sh`はstatusを見ず
  UNENFORCED。外部effect、validator省略、非0無視、arbitrary secret本文もtrace/scan検出だけである。
- `verify.sh`は2026-08-08に`VERIFY_OK`。smoke 1回・A/B 3回は全てstub adapterで、
  外部Provider・実モデル呼出しは0回（`runs/2026-08-08-verify-integration-4bbef9f.json`）。
- manifestの宣言済み`grader_hash`は`grade-run.py`単体で、`grade-case.py`、
  `map-trace.py`、`compare-runs.py`、`check-promotion.py`を含む範囲の採否は未決定である。
- 構造上の観測の限界（read推定・route導出・model非観測・生log）は
  `projects/agent-directory-evaluation/docs/HARNESS.md#観測の限界`が所有する。

## 現在有効な決定

- 初期sourceは`8325b185…`、採用revisionは`git config agent-directory.upstream-revision`が所有する。
- policy **v1.1.1**（人間決定、MDE 8pp、HG-11等）は`docs/EVALUATION.md`だけが所有する。
- 現行suiteは89 case、Tier 0は4件（`docs/tier0-cases.txt`）。直近flash baselineは`4bbef9f`、
  proは旧条件で比較不能。詳細hashと数値はbaseline evidenceが持つ。
- Draft PRと上流Issueは`EVALUATION.md`の条件を満たす別sessionだけで扱う。write観測はGit由来である。

## 失敗・却下済み

- gemini sandboxはcontainer runtime要で除外。root AGENTS未読所見とprofile経由のtmp除外上書きは撤回済み。
- must_reportの即席keyword照合は採用せず、`report_match`/`final_response`（Issue #18採用済み）を使う。

新しい根拠または利用者の明示指示がない限り、ここにある方法を繰り返さない。

## 次の一手

1. 次の上流revisionは`run-eval.sh --stage gate`から入り、EVAL_REQUIRED時だけ`4bbef9f`の
   hash一致baselineを比較へ使う。条件hashが動いた場合は再取得する。
2. **手順省略問題は仮説2/3消費で一時停止**。最後の枠のmust_run観測意味論は人間決定が先。
3. execution configのmodel観測欠落を潰す（現在declared）。
4. manifestの`grader_hash`へ含めるsemantic grader群の範囲を人間が決定する。決定までは
   audit用の複合hashを証拠へ記録するだけで、既存baselineを新しい意味論の比較へ流用しない。

本文は現在有効な状態と直近の検証だけに保ち、詳細履歴は`runs/`へ移す。
