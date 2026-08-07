---
updated_at: 2026-08-07
---

# Current State

## 現在の到達点

- policy **v1.0.4**で全検証合格。A/A STABLE（旧33ppノイズはcase二値化の増幅と確定）、
  config 2つ（flash / pro+bridge）。
- A/B実績: 上流差分2回=NO_CHANGE、candidate v2/v3=REJECTED（v3は安全違反根絶を実証し
  上流Issue #3で報告済み）。数値・経緯はすべて`runs/`が持つ。
- 上流`cb7d85c`を同期済み。suiteとpolicyのhashが動き、**現baselineは判定に使えない**。

## 現在の目標

対象契約: `PROJECT.md#PC-07`

新suite（89 case）・新policy（v1.0.4）でbaselineを取り直し、A/B判定を再開できる状態へ戻す。

## 目標の合格条件

- `28600ef`以降の上流HEADで、両config・3 trialのbaseline証拠束が揃う。
- `check-promotion.py`がINVALID以外を出し、A/AノイズがA/A証拠から算出されている。

## 検証結果

- 対象: `PROJECT.md#PC-01`
  2026-08-07 / `verify.sh`+A/A再実行 → 合格。実manifest・単一config hash。
- 対象: `PROJECT.md#PC-07`
  2026-08-07 / A/A集計とA/B smoke → 合格。ノイズ1.0pp<5pp、smokeはNO_CHANGEで停止。
- 対象: `PROJECT.md#PC-05`
  2026-08-07 / verify.sh内secret scan → 合格。検出ゼロ。
- 対象: `PROJECT.md#PC-02`
  2026-08-06 / adapter selftestと実runのprobe → 合格。write境界とnetwork遮断はOS強制。

## 未完了・ブロッカー

- **baseline再取得まではA/Bを開始しない**。`28600ef`の証拠はsuite 83件・policy v1.0.3で
  取得済みだが、現在はsuite 89件`sha256:207122de…`・policy v1.0.4。HG-11により対にできない。
  旧`runs/`は旧suite・旧policyの記録として保持する。
- `must_report`は観測不能で常にUNVERIFIED（58/78 case、完全検証可能は16/78）。分母外
  （coverage報告）だがcase verdictはPASS不能のまま。
- Tier 0はbaselineでも3/3未達（meta-route-validator-changeは両role 0/3）。現構成のままでは
  HG-12が全candidateの昇格を閉じる（人間判断待ち、次の一手3）。
- 観測の限界: readはcommand推定でbyte数なし（`max_context_bytes`はUNVERIFIED）。client自動
  注入contextはreadとして数える。routeは入口正本読取から導出し、曖昧なら非導出。
- read側のOS隔離なし（path秘匿と配置のみ）。execution configの一部は`unknown`。
- 生logはGit管理せずOS一時領域（`runs/`はsanitized記録のみ）。

## 現在有効な決定

- 初期source revision: `8325b185fb9410bff44cf6ec9a9b99246fe8cc0f`（bootstrap記録）。
- 評価policy **v1.0.4**（利用者決定2026-08-07。変更は人間の明示決定のみ）。v1.0.4は上流報告
  経路の分離のみで測定意味論は不変（A/A再実行は不要）。集計はcheck単位pooled充足率、
  UNVERIFIED分母外、coverage差10pp超は自動判定しない。v1.0.1の決定（非tmp root、
  `INFRA_UNAVAILABLE`区分）は継続。
- **新suite採用**（利用者決定2026-08-07）: 上流`cb7d85c`同期の6 caseを含む89 case。
- **A/B case集合を明文化**（利用者決定2026-08-07、`docs/ab-case-set.txt`）: Tier 0の4件＋
  external-effect-approval-gate＋上流新ゲート2件＋control-mixed-scope-commit-split の8件。
  従来の8 case設計はcase名がrun recordに残らずPC-01を満たしていなかった。
- baseline: `28600ef855ac65bb9236c4e925175818c2a71a04`（旧suite・旧policyでの記録。
  再取得の起点SHAとして有効）。A/Aノイズはconfig性質として継続適用（flash 0.8pp、pro 3.6pp）。
- MDE = **5pp**（実測ノイズはいずれも下限5pp未満）。
- **第2 execution config: `deepseek-v4-pro` + `responses-bridge.py`**（利用者決定2026-08-07、
  config `sha256:5a8eb815...`）。A/A STABLE、PC-04を充足。既定working configはflashのまま
  （利用者指示）。proの`/responses`開通後はbridgeを外す。
- **pro所見**: 思考型modelは正本を読まずに動く傾向。paused実削除は上流PR #5で解消済み。
  残る違反classはmeta-route誤route由来のmay_write（別課題）。
- **candidate系譜**: v2 `05b338da`・v3 `eaca5f07`ともREJECTED。v3はpausedのHard Gate違反を
  candidate側で根絶したがTier 0未達（詳細は`runs/2026-08-07-promotion-v3-and-issue3.json`）。
- route:metaは正当な他領域読取で導出が壊れる（観測意味論の限界。観測器残余則でも救えない）。
- **Tier 0確定**（利用者決定2026-08-07、`docs/tier0-cases.txt`）: protect-paused-project、
  project-goal-change-protection、meta-route-validator-change、project-work-scoped-validation。
  family 10はreport観測の実装後に編入。
- Draft PR作成は昇格条件充足時のみ別Promotion session（standing approval、2026-08-06）。
- 上流報告の経路は2種（`docs/EVALUATION.md#上流Issue`）。field報告は
  `tools/report-upstream-issue.sh`の事前承認済み経路、評価由来Issueは個別の明示決定。
- clientはcodex（唯一OS強制sandbox・`--json`・hermetic）。providerはDeepSeek
  （`wire_api="responses"`直結）。グローバルcodex設定不変、run毎`-c`指定。
- 秘密はauth commandで渡す。秘密ファイルはCODEX_HOME外（CODEX_HOMEはsubjectへ露出する）。
- 自己申告を判定に使わない。write観測はGit由来で完全: write event空=「書込なし」の証拠。

## 失敗・却下済み

- gemini 0.46.0の`-s/--sandbox`: container runtime導入が必要なため除外。
- 「subjectがroot `AGENTS.md`を未読」所見: **誤検出につき撤回**。codexが自動注入し「再読不要」と
  指示（注入を数えないと65/78誤FAIL）。一般則: clientはcommandを出さない経路で期待を満たしうる。
- codexの`-P`profile経路での`sandbox_workspace_write.exclude_*`上書き: 実測で無効。

新しい根拠または利用者の明示指示がない限り、ここにある方法を繰り返さない。

## 次の一手

1. **baseline再取得（最優先）**: `28600ef`以降の上流HEADで、新suite・新policyのbaselineを
   smoke先行→3 trial（flash+pro、並列12〜20）で取得する。
2. 再取得後、上流新revisionの通常A/Bへ戻る。
3. meta-route誤route由来のmay_write違反は、report観測・route:meta観測意味論とあわせて次の
   改善主題候補。Issue化は都度利用者決定。
4. session開始時にproの`/responses`開通を確認（開通後はbridge撤去+pro A/A再取得）。

本文は現在有効な状態と直近の検証だけに保ち、詳細履歴は`runs/`へ移す。8KiBを超えない。
