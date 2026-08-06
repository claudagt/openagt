---
updated_at: 2026-08-06
---

# Current State

## 現在の到達点

- `docs/EVALUATION.md`（policy v1.0.1）と最小harnessを整備し、`verify.sh`の32検査が合格。A/Aは実施済みだが不安定。
- 2026-08-06の人間レビューで初期構築は合格。実運用開始はP0/P1解消まで保留。
- 第2段階でadapter（`codex-adapter.sh`）、run分類（`classify-run.py`）、case grader
  （`grade-case.py`）、trace写像（`map-trace.py`）、外側runner（`run-case.sh`）、
  最終Gate（`check-promotion.py`）を追加。
- 実モデルrunに成功（DeepSeek経由）。baseline runは未取得。

## 現在の目標

対象契約: `PROJECT.md#PC-01`

実client（利用可能なもの1つ）のexecution configを固定し、pinned source revisionに対する
最初のbaseline runを再現可能なmanifest付きで取得する。

## 目標の合格条件

- baseline runのmanifestにsource SHA、policy hash、suite hash、grader hash、
  execution config hashがすべて実値（`unknown`可、0埋め不可）で記録されている。
- 同じmanifestから第三者がsandbox生成とgradingを再実行できる。

## 検証結果

- 対象: `PROJECT.md#PC-01`
- 確認日: 2026-08-06 / 方法: `scripts/verify.sh`
- 結果: 合格（`VERIFY_OK`）。baseline未取得のためPC-01の実運用充足は未検証。

- 対象: `PROJECT.md#PC-05`
- 確認日: 2026-08-06 / 方法: verify.sh内のsecret scan
- 結果: 合格。検出ゼロ。

- 対象: `PROJECT.md#PC-02`
- 確認日: 2026-08-06（subject実行隔離）
- 方法: `codex-adapter.sh --selftest`と実モデルrunでの実地probe
- 結果: 合格。workspace内write=許可、外=拒否、network=遮断をOSレベルで確認。read側は非制限。

## 未完了・ブロッカー

- **人間判断待ち**: Tier 0 case一覧が未確定。`check-promotion.py`は`--tier0-file`必須で
  未指定ならINVALID（推論しない）。policy側の決定事項。
- `must_report`は構造化レポートを観測できず常にUNVERIFIED（suiteの58/78 caseが該当）。
  これらのcaseは現状PASSに到達できない。
- 観測の限界（coverageへ記録。推測で埋めない）: readは読取専用commandからの推定で
  byte数を取れず`max_context_bytes`はUNVERIFIED。clientの自動注入context（codexはroot
  `AGENTS.md`）は別途readとして数える。routeは入口正本の読取から導出し、曖昧なら導出しない。
- read側のOS隔離なし: subjectからevaluator repositoryや`$HOME`を読める。path秘匿と配置のみ。
- execution configの`unknown`: system instruction、tool schema、sampling、各種上限。
- `runs/`にA/A記録を作成済み。生logはGit管理せずOS一時領域に置く。

## 現在有効な決定

- 初期source revision: `8325b185fb9410bff44cf6ec9a9b99246fe8cc0f`（bootstrap記録）。
- 評価policy version: v1.0.1（利用者の明示決定で改訂。変更は人間の明示決定のみ）。
  (1) subjectは`/tmp`・`$TMPDIR`外の専用root（既定`~/.cache/openagt-eval/`）。
  (2) 利用制限・rate limit・認証失敗・provider障害・基盤timeoutは`INFRA_UNAVAILABLE`とし、
  candidate失敗として数えず、Tier 0の3/3の分母にも入れない。
- 現在のbaseline run: **未確定**。上流HEAD`fa2bd21bf77c2f6b1eaec1c86faf1e4d5400d06a`で
  A/Aを実施したが不安定のため、baselineとして固定しない。ノイズ低減が先。
- MDE = max(5pp, A/A実測ノイズ) → **33pp**。`deepseek-v4-flash`はこのbenchmarkに対して
  非決定性が大きすぎ、33pp未満の改善を検出できない。sampling固定は不可（codexに
  temperature等のconfigが無い・実測）。run数増でも縮まらないことを実測済み。
  残る手は、より決定的なmodel（`deepseek-v4-pro`）か、caseごとの合否ではなく
  check単位の集計へ指標を変えるか（後者はpolicy変更を要する）。
- `8325b185... → 最新main`の差分は最初のA/B smokeとして利用してよい。
- Draft PR作成は`docs/EVALUATION.md#PR昇格条件`充足時のみ、別Promotion sessionで行う
  （standing approval。2026-08-06利用者指示）。
- clientはcodex（`codex exec`）。3client中唯一、OS強制sandbox・`--json` trace・hermetic
  configを備える。組込permission profileは`:workspace`と`:read-only`のみ。
- providerはDeepSeek（実在は`deepseek-v4-flash`/`deepseek-v4-pro`のみ）。Responses API
  nativeでbridge不要、`wire_api="responses"`。利用者のグローバルcodex設定は変更せず
  run毎に`-c`でinline指定する。OpenAI quotaを消費しない。
- **秘密はauth commandで渡し`env_key`を使わない**（実測）。env_keyだと
  `shell_environment_policy`で遮断してもsubjectのshellから見えた。変更後、不可視化を実runで
  確認。秘密ファイルはCODEX_HOMEと無関係な一時領域へ置く（CODEX_HOMEはsubjectへ露出する）。
- 実runでの観測: agentの自己申告exit code 1件に対応するrun eventが無く、filesystemにも
  痕跡がなかった。自己申告を判定に使わない設計を実地で確認。
- write観測はGit由来で完全。write eventが空であること自体が「書込なし」の証拠であり、
  UNVERIFIEDにしない（traceの完全性markerで区別する）。
- 実caseの実モデル採点が成立: `project-work-scoped-validation`が上流HEAD
  （`fa2bd21b...`）に対してPASS（3/3 baseline）。
- **A/A 2回実施・いずれも不安定**: 12 run（role当たり6、分解能16.7pp）→ノイズ16.7pp、
  36 run（role当たり18、分解能5.6pp）→ノイズ33.3pp。**分解能を3分の1にしてもノイズは
  縮まらず**、量子化ではなくmodelの実変動と確定。証拠は`runs/2026-08-06-aa-fa2bd21b.json`と
  `runs/2026-08-06-aa2-fa2bd21b.json`。

## 失敗・却下済み

- gemini 0.46.0の`-s/--sandbox`: container runtime導入が必要なため第1号adapterから除外。
- `deepseek-v4-pro`: provider側がCodex経路を未提供（「early August 2026に提供予定、
  flashを使え」と応答。2026-08-06実測）。ノイズ低減のmodel変更手段は現状ない。
- 「subjectがroot `AGENTS.md`を未読」という所見: **誤検出につき撤回**。codexは同ファイルを
  developer messageへ自動注入し「再読不要」と指示するため、`cat`が現れないのは正しい挙動
  （`codex debug prompt-input`で確認）。自動注入を数えない観測は65/78 caseを誤ってFAILさせる。
  一般則: clientはcommandを出さない経路で期待を満たしうる。
- codexの`-P`profile経路での`sandbox_workspace_write.exclude_*`上書き: 実測で無効。

新しい根拠または利用者の明示指示がない限り、ここにある方法を繰り返さない。

## 次の一手

1. **人間判断が要る**: ノイズ低減の手段が尽きた。指標定義の変更（case合否の二値→check単位の
   集計）はpolicy変更のため実施できない。あるいは別clientをsubjectにする（claude CLIは
   OS強制sandboxを持たないため、write違反は検出できるが防止はできない）。
2. Tier 0 case一覧の確定（人間判断）後、`check-promotion.py`へ渡せるようにする。

本文は現在有効な状態と直近の検証だけに保ち、詳細履歴は`runs/`へ移す。8KiBを超えない。
