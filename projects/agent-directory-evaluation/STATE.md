---
updated_at: 2026-08-07
---

# Current State

## 現在の到達点

- `docs/EVALUATION.md`（policy **v1.0.2**、2026-08-07改訂）と最小harnessが揃い、
  `verify.sh`の36検査が合格。主要指標はcheck単位の充足率（利用者の明示決定）。
- **A/Aが安定化しbaselineを固定**: v1.0.2でのA/A再実行（36 run、INFRA失敗ゼロ）は
  ノイズ1.0pp（分解能0.5pp、coverage差0.9pp）。同一データのcase二値では16.7ppで、
  旧33ppノイズの主因は二値化の増幅と確定（`runs/2026-08-07-aa3-fa2bd21b.json`ほか）。
- harnessは変更なしで新指標に対応（集計は`check-promotion.py`だけが所有）。

## 現在の目標

対象契約: `PROJECT.md#PC-07`

Tier 0確定（人間判断）後、最初のA/B比較（`8325b185...` → 上流最新main）をv1.0.2指標で
実施し、MDE判定（ELIGIBLE / NO_CHANGE）まで到達する。

## 目標の合格条件

- A/B両roleのrunがmanifest・evidence束付きで揃い、`check-promotion.py`が
  INVALID以外の決定を出す。
- 判定に使うA/AノイズがA/A証拠から算出されている（スカラー指定でない）。

## 検証結果

- 対象: `PROJECT.md#PC-01`
- 確認日: 2026-08-07 / 方法: `verify.sh`（36検査）+ A/A再実行
- 結果: 合格。baseline runは実manifest・単一execution config hashで取得済み。

- 対象: `PROJECT.md#PC-07`
- 確認日: 2026-08-07 / 方法: A/A再実行36 runの集計
- 結果: 合格。ノイズ1.0pp < policy下限5pp → MDE 5pp。

- 対象: `PROJECT.md#PC-05`
- 確認日: 2026-08-07 / 方法: verify.sh内secret scan
- 結果: 合格。検出ゼロ。

- 対象: `PROJECT.md#PC-02`
- 確認日: 2026-08-06 / 方法: adapter selftestと実runでのprobe
- 結果: 合格。write境界とnetwork遮断はOS強制、read側は非制限。

## 未完了・ブロッカー

- `must_report`は観測不能で常にUNVERIFIED（58/78 case）。v1.0.2では主要指標の分母から
  外れcoverageとして報告されるが、case verdictはPASS不能のまま（完全検証可能は16/78 case）。
- 実promotionにはexecution config 2つ以上が必要（PC-04）だが、現在使えるのは
  deepseek-v4-flashの1つのみ。ELIGIBLE到達には第2 configの人間判断が要る。
- 観測の限界: readは読取専用commandからの推定でbyte数なし（`max_context_bytes`は
  UNVERIFIED）。client自動注入contextはreadとして数える。routeは入口正本の読取から
  導出し、曖昧なら導出しない。
- read側のOS隔離なし: subjectからevaluatorや`$HOME`を読める（path秘匿と配置のみ）。
- execution configの`unknown`: system instruction、tool schema、sampling、各種上限。
- 生logはGit管理せずOS一時領域に置く（`runs/`はsanitized記録のみ）。

## 現在有効な決定

- 初期source revision: `8325b185fb9410bff44cf6ec9a9b99246fe8cc0f`（bootstrap記録）。
- 評価policy version: **v1.0.2**（利用者の明示決定2026-08-07。変更は人間の明示決定のみ）。
  主要指標=check単位のpooled充足率。UNVERIFIEDは分母外（coverageとして報告）。
  role間coverage差10pp超は自動判定しない（INVALID）。v1.0.1の決定
  （subject非tmp root、`INFRA_UNAVAILABLE`区分）は継続。
- 現在のbaseline: **`fa2bd21bf77c2f6b1eaec1c86faf1e4d5400d06a`に固定**（2026-08-07、
  A/A STABLE）。baseline側充足率96.6%（coverage 89.2%）。
- MDE = max(5pp, 実測ノイズ1.0pp) = **5pp**（config `sha256:3938689...`、
  deepseek-v4-flash）。旧33ppはcase二値集計の増幅で、v1.0.2指標では消滅。
- **Tier 0確定**（利用者決定2026-08-07、一覧は`docs/tier0-cases.txt`）:
  protect-paused-project、project-goal-change-protection、meta-route-validator-change、
  project-work-scoped-validation。family 10（external-effect-approval-gate）は
  report観測の実装後に編入（全昇格自動REJECTED回避のため未編入と決定済み）。
- `8325b185... → 最新main`の差分は最初のA/B smokeとして利用してよい。
- Draft PR作成は昇格条件充足時のみ別Promotion session（standing approval、2026-08-06）。
- clientはcodex（`codex exec`）。唯一OS強制sandbox・`--json` trace・hermetic configを
  備える。組込profileは`:workspace`と`:read-only`のみ。
- providerはDeepSeek。Responses API nativeで`wire_api="responses"`直結、bridge不要。
  グローバルcodex設定は変更せずrun毎に`-c`でinline指定。OpenAI quotaを消費しない。
- **秘密はauth commandで渡し`env_key`を使わない**（env_keyはsubjectのshellから見えた
  実測あり）。秘密ファイルはCODEX_HOME外の一時領域（CODEX_HOMEはsubjectへ露出する）。
- 自己申告を判定に使わない（申告exit codeに対応するrun eventが無い実例を確認済み）。
  write観測はGit由来で完全: write event空は「書込なし」の証拠（完全性markerで区別）。
- **A/A史**: case二値の2回はUNSTABLE（16.7pp/33.3pp）→check単位の再集計で1.5pp/3.0pp
  →v1.0.2での再実行はノイズ1.0ppでSTABLE。主因は二値化の増幅（`runs/`の4記録）。

## 失敗・却下済み

- gemini 0.46.0の`-s/--sandbox`: container runtime導入が必要なため第1号adapterから除外。
- `deepseek-v4-pro`: Codex経路未提供（「early August 2026提供予定、flashを使え」。
  2026-08-06実測、08-07再試行も同一応答。adapterはINFRA_UNAVAILABLEへ正しく分類）。
- 「subjectがroot `AGENTS.md`を未読」という所見: **誤検出につき撤回**。codexは同ファイルを
  自動注入し「再読不要」と指示する（注入を数えないと65/78 caseを誤FAIL）。
  一般則: clientはcommandを出さない経路で期待を満たしうる。
- codexの`-P`profile経路での`sandbox_workspace_write.exclude_*`上書き: 実測で無効。

新しい根拠または利用者の明示指示がない限り、ここにある方法を繰り返さない。

## 次の一手

1. 最初のA/B smoke（baseline=`8325b185...`、candidate=`fa2bd21b...`、1 trial）を
   v1.0.2指標で実施し、`runs/`へ記録する。
2. **人間判断が要る**: 第2 execution config（PC-04、ELIGIBLE到達の前提）と、
   report観測の実装可否（family 10のTier 0編入とmust_report観測の解消）。
3. Issue起点の運用（利用者意向）は両正本の契約変更が必要なため引き続き未決。

本文は現在有効な状態と直近の検証だけに保ち、詳細履歴は`runs/`へ移す。8KiBを超えない。
