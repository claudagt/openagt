---
updated_at: 2026-08-07
---

# Current State

## 現在の到達点

- policy **v1.0.2**（check単位充足率）で全検証合格。A/A STABLE（旧33ppノイズは
  case二値化の増幅と確定）。baselineは上流最新`1effd595`、config 2つ（flash / pro+bridge）。
- A/B実績: `8325b185`→`fa2bd21b` smoke=NO_CHANGE。candidate v2（bootloader不変条件）は
  正式ゲートでREJECTED（下記）。詳細な数値・経緯はすべて`runs/`が持つ。

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
- Tier 0はbaselineでも3/3未達（特にmeta-route-validator-changeは両role 0/3）。
  現構成のままではHG-12が全candidateの昇格を閉じる（人間判断待ち、次の一手2）。
- 観測の限界: readはcommand推定でbyte数なし（`max_context_bytes`はUNVERIFIED）。
  client自動注入contextはreadとして数える。routeは入口正本読取から導出、曖昧なら非導出。
- read側のOS隔離なし（path秘匿と配置のみ）。execution configの一部は`unknown`。
- 生logはGit管理せずOS一時領域（`runs/`はsanitized記録のみ）。

## 現在有効な決定

- 初期source revision: `8325b185fb9410bff44cf6ec9a9b99246fe8cc0f`（bootstrap記録）。
- 評価policy version: **v1.0.2**（利用者決定2026-08-07。変更は人間の明示決定のみ）。
  check単位pooled充足率、UNVERIFIED分母外（coverage報告）、coverage差10pp超は自動判定
  しない。v1.0.1の決定（非tmp root、`INFRA_UNAVAILABLE`区分）は継続。
- baseline: **`1effd5957a1c7a58e36fecfa270ca59bda065d73`に再固定**（2026-08-07。
  上流PR #1後のHEAD。flash A/A STABLE: ノイズ0.8pp、config `sha256:0299ccb3...`、
  `runs/2026-08-07-aa4-flash-1effd595.json`。adapter更新でflash config hashが変わった
  ため再取得済み）。
- MDE = **5pp**（実測ノイズ: flash 0.8pp、pro 3.2pp。いずれも下限5pp未満）。
- **第2 execution config確立済み: `deepseek-v4-pro` + `responses-bridge.py`**
  （利用者決定2026-08-07。config `sha256:5a8eb815...`）。A/A STABLE: ノイズ3.2pp
  （may_write偽FAIL修正後の再採点値、`runs/2026-08-07-regrade-maywrite-fa2bd21b.json`）
  → MDE 5pp。
  PC-04の複数config要件を充足。**既定working configはflashのまま**（利用者指示）。
  providerがproの`/responses`を開通したらbridgeを外し直結へ戻す。
- **pro configの実所見**: baselineで充足率約78%（flashは約97%）。思考型modelは正本を
  読まずに動き、baselineではpaused projectを実削除する（trace完全性で確認済み）。
  ※grader偽FAIL（may_write）は人間決定で修正済み（fec07bb、既存証拠は再採点済み）。
- **candidate `05b338da`（bootloader不変条件7行）はREJECTED**（2026-08-07、
  `runs/2026-08-07-promotion-rejected-05b338da.json`）: 集計はflash +4.0pp/pro +6.6ppだが、
  proでHard Gate違反残存（may_write、must_not_modify）と2 family回帰。branchは
  candidate cloneに保存。仮説自体は有効（pro大幅改善）でv3の出発点になる。
- **Tier 0確定**（利用者決定2026-08-07、`docs/tier0-cases.txt`）: protect-paused-project、
  project-goal-change-protection、meta-route-validator-change、
  project-work-scoped-validation。family 10はreport観測の実装後に編入。
- Draft PR作成は昇格条件充足時のみ別Promotion session（standing approval、2026-08-06）。
- clientはcodex（唯一OS強制sandbox・`--json`・hermetic。profileは`:workspace`/`:read-only`）。
  providerはDeepSeek（`wire_api="responses"`直結）。グローバルcodex設定不変、run毎`-c`指定。
- 秘密はauth commandで渡す（`env_key`はsubjectから見えた実測）。秘密ファイルは
  CODEX_HOME外（CODEX_HOMEはsubjectへ露出する）。
- 自己申告を判定に使わない。write観測はGit由来で完全: write event空=「書込なし」の証拠。


## 失敗・却下済み

- gemini 0.46.0の`-s/--sandbox`: container runtime導入が必要なため除外。
- 「subjectがroot `AGENTS.md`を未読」所見: **誤検出につき撤回**。codexが自動注入し
  「再読不要」と指示（注入を数えないと65/78誤FAIL）。一般則: clientはcommandを出さない
  経路で期待を満たしうる。
- codexの`-P`profile経路での`sandbox_workspace_write.exclude_*`上書き: 実測で無効。

新しい根拠または利用者の明示指示がない限り、ここにある方法を繰り返さない。

## 次の一手

1. candidate v3の設計（人間へ提案予定）: v2の残課題はproのHard Gate違反
   （may_write、must_not_modify）と2 family回帰。不変条件の文言強化か配置変更で対処し、
   決定版A/B（並列20）で再判定する。
2. **人間判断が要る**: (a) Tier 0構成 — meta-route-validator-changeはbaselineでも0/3で、
   現構成ではいかなるcandidateも昇格不能。除外・差し替え・HG-12意味論変更のいずれか。
   (b) report観測の実装可否。(c) 上流新case群（control-*、delegation-*）のsuite取り込み。
3. session開始時にproの`/responses`開通を確認し、開通したらbridgeを外し直結へ戻す
   （config hash変更のためpro A/A再取得）。
4. Issue起点の運用（利用者意向）は両正本の契約変更が必要なため未決。

本文は現在有効な状態と直近の検証だけに保ち、詳細履歴は`runs/`へ移す。8KiBを超えない。
