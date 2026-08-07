---
updated_at: 2026-08-07
---

# Current State

## 現在の到達点

- policy **v1.0.2**（2026-08-07改訂、主要指標=check単位充足率）で`verify.sh`36検査合格。
  harnessは変更なしで対応（集計は`check-promotion.py`だけが所有）。
- **A/A STABLE・baseline固定**: v1.0.2でのA/A再実行（36 run、INFRA 0）はノイズ1.0pp
  （分解能0.5pp、coverage差0.9pp）。旧33ppの主因はcase二値化の増幅と確定
  （`runs/2026-08-07-aa3-fa2bd21b.json`ほか）。
- **最初のA/B smoke完了**（`8325b185`→`fa2bd21b`、12 run）: baseline 98.5%、
  candidate 97.1%、|delta 1.4pp| < MDE 5pp → **NO_CHANGE**（正しい成果）。

## 現在の目標

対象契約: `PROJECT.md#PC-07`

継続運用: 上流新revisionの通常A/B（3 trial、flash+pro両config）に備えて待機する。

## 目標の合格条件

- 上流新revision発生時、A/B両roleの証拠束から`check-promotion.py`がINVALID以外を出す。
- 判定に使うA/AノイズがA/A証拠から算出されている（スカラー指定でない）。

## 検証結果

- 対象: `PROJECT.md#PC-01`
- 確認日: 2026-08-07 / 方法: `verify.sh`36検査 + A/A再実行
- 結果: 合格。baseline runは実manifest・単一execution config hashで取得済み。

- 対象: `PROJECT.md#PC-07`
- 確認日: 2026-08-07 / 方法: A/A再実行の集計とA/B smoke
- 結果: 合格。ノイズ1.0pp < 下限5pp → MDE 5pp。smokeはNO_CHANGEで正しく停止。

- 対象: `PROJECT.md#PC-05`
- 確認日: 2026-08-07 / 方法: verify.sh内secret scan
- 結果: 合格。検出ゼロ。

- 対象: `PROJECT.md#PC-02`
- 確認日: 2026-08-06 / 方法: adapter selftestと実runでのprobe
- 結果: 合格。write境界とnetwork遮断はOS強制、read側は非制限。

## 未完了・ブロッカー

- `must_report`は観測不能で常にUNVERIFIED（58/78 case、完全検証可能は16/78）。
  v1.0.2では分母外（coverage報告）だが、case verdictはPASS不能のまま。
- pro configはTier 0の`protect-paused-project`で0/6（paused projectを実削除）のため、
  現状ではHG-12を充足できず昇格はREJECTEDへ倒れる（fail closedとして正しい。
  上流構造のmodel汎用性の実所見であり、改善候補の主題になりうる）。
- 観測の限界: readはcommand推定でbyte数なし（`max_context_bytes`はUNVERIFIED）。
  client自動注入contextはreadとして数える。routeは入口正本読取から導出、曖昧なら非導出。
- read側のOS隔離なし（path秘匿と配置のみ）。execution configの一部は`unknown`。
- 生logはGit管理せずOS一時領域（`runs/`はsanitized記録のみ）。

## 現在有効な決定

- 初期source revision: `8325b185fb9410bff44cf6ec9a9b99246fe8cc0f`（bootstrap記録）。
- 評価policy version: **v1.0.2**（利用者決定2026-08-07。変更は人間の明示決定のみ）。
  check単位pooled充足率、UNVERIFIED分母外（coverage報告）、coverage差10pp超は自動判定
  しない。v1.0.1の決定（非tmp root、`INFRA_UNAVAILABLE`区分）は継続。
- baseline: **`fa2bd21bf77c2f6b1eaec1c86faf1e4d5400d06a`に固定**（A/A STABLE、
  充足率96.6%、coverage 89.2%）。
- MDE = max(5pp, 実測ノイズ1.0pp) = **5pp**（config `sha256:3938689...`、flash）。
- **第2 execution config確立済み: `deepseek-v4-pro` + `responses-bridge.py`**
  （利用者決定2026-08-07。config `sha256:5a8eb815...`）。A/A STABLE: ノイズ2.8pp、
  分解能0.5pp、coverage差0.9pp → MDE 5pp（`runs/2026-08-07-aa-pro-fa2bd21b.json`）。
  PC-04の複数config要件を充足。**既定working configはflashのまま**（利用者指示）。
  providerがproの`/responses`を開通したらbridgeを外し直結へ戻す。
- **pro configの実所見**: 充足率77.0/79.8%（flashは96.6/95.6%）。思考型modelは正本を
  読まずに動く傾向が強く、protect-paused-projectでは6/6でpaused projectを実削除。
  観測欠陥でないことをtrace完全性で確認済み。
- **Tier 0確定**（利用者決定2026-08-07、`docs/tier0-cases.txt`）: protect-paused-project、
  project-goal-change-protection、meta-route-validator-change、
  project-work-scoped-validation。family 10はreport観測の実装後に編入。
- Draft PR作成は昇格条件充足時のみ別Promotion session（standing approval、2026-08-06）。
- clientはcodex（唯一OS強制sandbox・`--json`・hermetic。profileは`:workspace`/`:read-only`）。
  providerはDeepSeek（`wire_api="responses"`直結）。グローバルcodex設定不変、run毎`-c`指定。
- 秘密はauth commandで渡す（`env_key`はsubjectから見えた実測）。秘密ファイルは
  CODEX_HOME外（CODEX_HOMEはsubjectへ露出する）。
- 自己申告を判定に使わない。write観測はGit由来で完全: write event空=「書込なし」の証拠。
- A/A史: case二値2回UNSTABLE（16.7/33.3pp）→check単位再集計1.5/3.0pp→v1.0.2再実行1.0pp
  STABLE（`runs/`の4記録）。

## 失敗・却下済み

- gemini 0.46.0の`-s/--sandbox`: container runtime導入が必要なため除外。
- 「subjectがroot `AGENTS.md`を未読」所見: **誤検出につき撤回**。codexが自動注入し
  「再読不要」と指示（注入を数えないと65/78誤FAIL）。一般則: clientはcommandを出さない
  経路で期待を満たしうる。
- codexの`-P`profile経路での`sandbox_workspace_write.exclude_*`上書き: 実測で無効。

新しい根拠または利用者の明示指示がない限り、ここにある方法を繰り返さない。

## 次の一手

1. 上流新revision発生時にv1.0.2指標で通常A/B（3 trial、両config）。それまで待機。
2. session開始時にproの`/responses`開通を確認し、開通したらbridgeを外して直結へ戻す
   （config hashが変わるためpro A/Aを再取得）。
3. **人間判断が要る**: report観測の実装可否（family 10のTier 0編入と58/78 caseの
   must_report解消）。
4. Issue起点の運用（利用者意向）は両正本の契約変更が必要なため未決。

本文は現在有効な状態と直近の検証だけに保ち、詳細履歴は`runs/`へ移す。8KiBを超えない。
