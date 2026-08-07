---
updated_at: 2026-08-07
---

# Current State

## 現在の到達点

- policy **v1.1.0**で全検証合格（verify.sh 39検査）。段階評価・逐次trial・baseline
  再利用・measurement hashを導入し、full A/B既定を廃止。入口は`scripts/run-eval.sh`。
- A/A STABLE（旧33ppノイズはcase二値化の増幅）、config 2つ（flash / pro+bridge）。
- A/B実績: 上流差分2回=NO_CHANGE、candidate v2/v3=REJECTED（v3は安全違反根絶を実証し
  上流Issue #3で報告→上流PR #5でmerge）。数値・経緯はすべて`runs/`が持つ。
- **report観測を実装**（report_match照合。family 10のmust_report 5checkが採点可能に
  なり、external-effect-approval-gateをTier 0へ編入。Tier 0は4件）。
- baselineは新suiteで**`cb7d85c`にて再取得済み**
  （`runs/2026-08-08-aa5-baseline-newsuite-cb7d85c.json`、A/A込み42 run、INFRA 0、
  A/A STABLE: ノイズ2.35pp・SE 2.84pp < MDE 8pp。baseline cacheへ蓄積済み）。

## 現在の目標

対象契約: `PROJECT.md#PC-07`

段階評価の実運用（run-eval.shによるStage 0-2）へ移行し、report観測の設計を
上流提案として固める（Tier 0再編入とmust_report UNVERIFIED解消の前提）。

## 目標の合格条件

- 上流更新時の既定フローがStage 0（gate）で始まり、NO_EVAL時に評価runゼロで終わる。
- report観測が実装され、must_reportのcheckがUNVERIFIED以外を返す。
- `check-promotion.py`がINVALID以外を出し、A/AノイズがA/A証拠から算出されている。

## 検証結果

- 対象: `PROJECT.md#PC-01`
  2026-08-07 / verify.sh+A/A再実行 → 合格。実manifest・単一config hash。
- 対象: `PROJECT.md#PC-07`
  2026-08-07 / A/A集計とA/B smoke → 合格。ノイズ1.0pp<MDE、NO_CHANGE停止。
- 対象: `PROJECT.md#PC-05`
  2026-08-07 / verify.sh内secret scan → 合格。検出ゼロ。
- 対象: `PROJECT.md#PC-02`
  2026-08-06 / adapter selftestと実runのprobe → 合格。write境界・network遮断はOS強制。

## 未完了・ブロッカー

- Tier 0は`cb7d85c`のbaselineで3件とも3/3未達（flash 0/3、pro 0/3）。candidate側が
  3/3にしない限り昇格は閉じたまま。
- **execution configのmodelは観測できない**（codex `--json`にproviderのmodelエコーが
  無くdeclaredのみ。provider APIへの直接照会で実在と応答model一致は確認済み）。
- 旧`runs/`は旧suite・旧policyの記録。HG-11により新runと対にしない。
- `must_report`は`report_match`パターンを持つcaseだけ採点可能（現在family 10の1 case）。
  他caseはパターン付与まで従来どおりUNVERIFIED（付与は都度、意味の最小核だけを縛る）。
- 観測の限界: readはcommand推定でbyte数なし、client自動注入contextはreadとして数える、
  routeは入口正本読取から導出（曖昧なら非導出）、read側のOS隔離なし、execution config
  の一部は`unknown`。生logはGit管理せずOS一時領域（`runs/`はsanitized記録のみ）。

## 現在有効な決定

- 初期source revision: `8325b185fb9410bff44cf6ec9a9b99246fe8cc0f`（bootstrap記録）。
- 評価policy **v1.1.0**（利用者決定2026-08-07。変更は人間の明示決定のみ）。段階評価、
  逐次trial・早期終了、baseline再利用、HG-11のmeasurement hash判定、MDE 8pp、
  A/B 7 case、pro=Stage 3のみ、driver入口`run-eval.sh`（並列既定20）——これらの正本は
  `docs/EVALUATION.md`であり、ここへ複製しない。
- **新suite採用**（利用者決定2026-08-07）: 上流`cb7d85c`同期の6 caseを含む89 case。
- baseline: **`cb7d85ceff8882606d54299922611332810e9d94`**（新suite・flash 89.5%
  pooled充足率、coverage 89.7%）。A/Aノイズ: flash 2.35pp（SE 2.84pp、有効2.84pp）。
  proは旧suiteの77.6%のまま（Stage 3で使う時に再取得）。
- **Tier 0は4件**（利用者決定2026-08-07、`docs/tier0-cases.txt`）: 従来3件＋
  external-effect-approval-gate（report観測実装により編入）。
  meta-route-validator-changeは観測意味論の限界で除外のまま。
- Draft PR作成は昇格条件充足時のみ別Promotion session（standing approval、2026-08-06）。
- 上流報告の経路は2種（`docs/EVALUATION.md#上流Issue`）。
- clientはcodex（唯一OS強制sandbox・`--json`・hermetic）、providerはDeepSeek
  （`wire_api="responses"`直結、proは`responses-bridge.py`経由）。グローバルcodex設定
  不変、run毎`-c`指定。秘密はauth commandで渡し、秘密ファイルはCODEX_HOME外。
- 自己申告を判定に使わない。write観測はGit由来で完全（write event空=「書込なし」の証拠）。

## 失敗・却下済み

- gemini 0.46.0の`-s/--sandbox`: container runtime要のため除外。
- 「subjectがroot `AGENTS.md`未読」所見: **誤検出につき撤回**（codexが自動注入し
  「再読不要」と指示。注入を数えないと65/78誤FAIL）。
- codexの`-P`profile経由の`sandbox_workspace_write.exclude_*`上書き: 実測で無効。
- must_reportのキーワード即席照合: 採用しない（ノイズをHard Gateへ持ち込まない。
  case側`report_match`のschema拡張として上流提案する）。

新しい根拠または利用者の明示指示がない限り、ここにある方法を繰り返さない。

## 次の一手

1. **candidate v4のA/B**（`aad16241`、完了の定義のbootloader昇格。根拠:
   144 tier0-runの実測で支配的失敗は手順の省略——入口正本未読66%・検証未実行53%・
   STATE未記録58%——であり安全実体の違反ではない）。smoke→効けばフルA/B
   （baseline cache再利用で candidate側21 runのみ）。
2. 上流新revisionは`run-eval.sh --stage gate`から入る（full A/Bを既定にしない）。
3. `report_match`のschema拡張とfamily 10計装を上流へ提案（評価由来の変更だが
   suite正本は上流所有。Issue/PR化は利用者決定）。
4. execution configのmodel観測欠落を潰す（現在declared）。

本文は現在有効な状態と直近の検証だけに保ち、詳細履歴は`runs/`へ移す。8KiBを超えない。
