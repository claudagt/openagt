---
updated_at: 2026-08-08
---

# Current State

## 現在の到達点

- policy **v1.1.0**で全検証合格（verify.sh）。段階評価・逐次trial・baseline再利用・
  measurement hashを導入し、full A/B既定を廃止。入口は`scripts/run-eval.sh`。
- A/A STABLE（旧33ppノイズはcase二値化の増幅）、config 2つ（flash / pro+bridge）。
- A/B実績: 上流差分2回=NO_CHANGE、v2/v3=REJECTED（v3は安全違反根絶→Issue #3→上流PR #5
  でmerge）、v4/v5=REJECTED_EARLY（must_run省略が残存）。数値・SHA・経緯は`runs/`が持つ。
- report観測を実装しTier 0を4件へ編入。baselineは新suiteで`cb7d85c`にて再取得済み
  （`runs/2026-08-08-aa5-baseline-newsuite-cb7d85c.json`、A/A込み42 run、INFRA 0）。
- **上流を`cb7d85c`→`4a188ca`へ同期済み**（2026-08-08）。Issue #18は上流採用され、
  報告観測は`report_match` + trace event `final_response`として`evals/EVALS.md#報告の観測`が
  正本になった。**この同期でbaselineは無効**（下記ブロッカー）。

## 現在の目標

対象契約: `PROJECT.md#PC-07`

`4a188ca`でbaselineを再取得し、段階評価（Stage 0-2）の実運用へ戻す。

## 目標の合格条件

- 上流更新時の既定フローがStage 0（gate）で始まり、NO_EVAL時に評価runゼロで終わる。
- `4a188ca`のbaselineとA/Aが同一実行条件で揃い、A/Aノイズ < MDE 8ppである。
- `check-promotion.py`がINVALID以外を出し、A/AノイズがA/A証拠から算出されている。

## 検証結果

- 対象: `PROJECT.md#PC-07`
  2026-08-07 / A/A集計とA/B smoke → 合格。ノイズ1.0pp<MDE、NO_CHANGE停止。
- 対象: `PROJECT.md#PC-05`
  2026-08-07 / verify.sh内secret scan → 合格。検出ゼロ。
- 対象: `PROJECT.md#PC-02`
  2026-08-06 / adapter selftestと実runのprobe → 合格。write境界・network遮断はOS強制。
- 対象: `PROJECT.md#PC-01`
  2026-08-08 / 上流`4a188ca`同期後のverify.sh＋validator --strict --full → 合格。

## 未完了・ブロッカー

- **`4a188ca`同期でbaselineは無効。次のA/Bの前に再取得が要る**（HG-11は実行条件の一致を
  要求する。再測定は費用を伴うため着手は利用者決定）。独立に動いたhashは3つ: suite
  （report_matchの上流版化と、must_readの`tools/TOOLS.md`→`tools/REFERENCE.md`移動）、
  grader（trace event `report`→`final_response`）、source SHA（`cb7d85c`→`4a188ca`）。
- Tier 0は`cb7d85c`のbaselineで3件とも3/3未達（flash 0/3、pro 0/3）。candidateが3/3に
  しない限り昇格は閉じたまま。`4a188ca`での再測定値は未取得。
- 旧`runs/`は旧suite・旧policyの記録。HG-11により新runと対にしない。
- `report_match`パターンを持つcaseは現在family 10の1件だけ。他caseのmust_reportは付与まで
  UNVERIFIEDのまま（付与は都度、意味の最小核だけを縛る）。
- 構造上の観測の限界（read推定・route導出・model非観測・生log）は
  `projects/agent-directory-evaluation/docs/HARNESS.md#観測の限界`が所有する。

## 現在有効な決定

- 初期source revision: `8325b185fb9410bff44cf6ec9a9b99246fe8cc0f`（bootstrap記録）。
  採用済みupstream revisionは`git config agent-directory.upstream-revision`が持つ。
- 評価policy **v1.1.0**（利用者決定2026-08-07。変更は人間の明示決定のみ）。段階評価、
  MDE 8pp、HG-11、driver入口`run-eval.sh`等の正本は`docs/EVALUATION.md`であり複製しない。
- **新suite採用**（利用者決定2026-08-07）: 上流`cb7d85c`同期の6 caseを含む89 case。
- 直近baseline: `cb7d85ceff8882606d54299922611332810e9d94`（flash 89.5% pooled充足率、
  coverage 89.7%、A/Aノイズ2.35pp / SE 2.84pp）。proは旧suiteの77.6%のまま
  （Stage 3で使う時に再取得）。`4a188ca`では未取得。
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

1. **`4a188ca`でのbaseline再取得**（A/A込み、`--no-early-stop`）。suite・grader・
   source SHAが同時に動いたため、これを済ませるまで新しいA/B判定は出せない。
   実行はAPI費用を伴うので利用者の着手決定を待つ。
2. **手順省略問題は仮説2/3消費で一時停止**（`runs/2026-08-08-ab9-10-v4-v5-screening.json`）。
   最後の枠は「finalizeを`tools/finalize-task.sh`実行として固定」だが、wrapper経由の検証を
   must_run充足と数えるかの**観測意味論の人間決定が先**。または上流報告（利用者決定）。
3. 上流新revisionは`run-eval.sh --stage gate`から入る（full A/Bを既定にしない）。
4. execution configのmodel観測欠落を潰す（現在declared）。

本文は現在有効な状態と直近の検証だけに保ち、詳細履歴は`runs/`へ移す。
