---
updated_at: 2026-08-06
---

# Current State

## 現在の到達点

- `docs/EVALUATION.md`（policy v1.0.1）と最小harnessを整備し、`verify.sh`の32検査が合格。
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
- 結果: 合格（`VERIFY_OK`）。manifest決定性、grading、A/A、sandbox隔離、secret scan。
  baseline未取得のためPC-01の実運用充足は未検証。

- 対象: `PROJECT.md#PC-05`
- 確認日: 2026-08-06 / 方法: verify.sh内のsecret scan
- 結果: 合格。検出ゼロ。

- 対象: `PROJECT.md#PC-02`
- 確認日: 2026-08-06（subject実行隔離。HG-02のOS強制）
- 方法: `scripts/codex-adapter.sh --selftest`と実モデルrunでの実地probe
- 結果: 合格。workspace内write=許可、workspace外write=拒否、network=遮断をOSレベル
  （macOS Seatbelt）で確認。read側は制限されない。

## 未完了・ブロッカー

- **人間判断待ち**: Tier 0 caseの一覧が未確定。`check-promotion.py`は`--tier0-file`必須で、
  未指定ならINVALID（推論しない）。確定は`EVALUATION.md#benchmark`のfamily 10・15を
  どのcaseへ割り当てるかの決定であり、policy側の決定事項。
- 観測の限界（いずれもcoverageへ記録。推測で埋めない）:
  read = codexがfile読取eventを出さないため読取専用commandからの推定。command由来のreadは
  byte数を取れず`max_context_bytes`はUNVERIFIED。clientが自動注入するcontext
  （codexはroot `AGENTS.md`）は別途readとして数える。route = 入口正本の読取から導出し、
  複数Routeの入口を読めば導出しない（fail closed）。meta/noneは導出不可。
- read側のOS隔離なし: subjectからevaluator repositoryや`$HOME`を読める。path秘匿と配置のみ。
- execution configの`unknown`: system instruction、tool schema、sampling、各種上限。
  codexは`deepseek-v4-flash`のmodel metadataを持たずfallbackするためcontext上限も未取得。
- `runs/`は実runの証拠束を保存していないため未作成（先回り生成しない方針）。

## 現在有効な決定

- 初期source revision: `8325b185fb9410bff44cf6ec9a9b99246fe8cc0f`（2026-08-06固定。
  同一作業内で上流に追従しない）。
- 評価policy version: v1.0.1（2026-08-06、利用者の明示決定で改訂。変更は人間の明示決定のみ）。
  (1) subjectは`/tmp`・`$TMPDIR`外の専用root（既定`~/.cache/openagt-eval/`）へ置く。
  (2) 利用制限・rate limit・認証失敗・provider障害・基盤timeoutは`INFRA_UNAVAILABLE`とし、
  candidate失敗として数えず、Tier 0の3/3判定の分母にも入れない。
  baselineが未取得のため、版更新に伴うA/A再実行・baseline再取得の積み残しはない。
- 現在のbaseline run: なし。最初の実運用baselineはrun開始時点の最新`agent-directory/main`を
  再取得・固定して対象とする（2026-08-06レビュー決定。同日確認時点で`fa2bd21b...`）。
- `8325b185... → 最新main`の差分は最初のA/B smokeとして利用してよい。
- Draft PR作成は`docs/EVALUATION.md#PR昇格条件`充足時のみ、別Promotion sessionで行う
  （standing approval。2026-08-06利用者指示）。
- adapter第1号はcodex（`codex exec`）。3client中唯一、OS強制sandbox（`-s workspace-write`）、
  `--json` trace、hermetic config（`--ignore-user-config`等）を備える。claudeはOS強制
  sandbox flagを持たず、geminiの`-s`はcontainer runtime前提のため見送り。
- 実測: codexの組込permission profileは`:workspace`と`:read-only`のみ（colon接頭辞）。
  `sandbox_workspace_write.exclude_*`の上書きは`-P`profile経路では効果がない。
- providerはDeepSeek（実在は`deepseek-v4-flash`/`deepseek-v4-pro`の2種のみ）。Responses APIを
  nativeに提供するためbridge不要。codex 0.146.0は`wire_api="chat"`廃止済みで`responses`直結。
  利用者のグローバルcodex設定は変更せず、run毎に`-c`でinline指定する（hash可能・再現可能）。
  OpenAI quotaを消費しないため、codex側の使用制限の影響を受けない。
- **秘密はauth commandで渡し、環境変数（`env_key`）を使わない**（実測）。env_keyだと
  `shell_environment_policy.inherit="none"`や`exclude=["*KEY*"]`でもsubjectのshellから
  見えた。変更後、不可視化を実runで確認。秘密ファイルはCODEX_HOMEと無関係な一時領域へ置く
  （CODEX_HOME自体はsubjectへ露出する）。
- 実runでの観測: agentが自己申告したexit code 1件に対応するrun eventが存在せず、
  filesystem上も痕跡がなかった。自己申告を判定に使わない設計の妥当性を実地で確認。
- 実caseの実モデル採点が成立: `project-work-scoped-validation`が上流HEAD
  （`fa2bd21b...`）に対して**PASS**。route、must_read全件、must_run、must_not_run 2件、
  must_update、may_write、must_not_modifyのすべてが成立。

## 失敗・却下済み

- gemini 0.46.0の`-s/--sandbox`: container runtime導入が必要なため第1号adapterから除外。
- 「subjectがroot `AGENTS.md`を未読」という所見: **誤検出につき撤回**（2026-08-06）。
  codexはroot `AGENTS.md`をdeveloper messageへ自動注入し「再読不要」と指示するため、
  `cat`が現れないのは正しい挙動。`codex debug prompt-input`でmodel入力への混入を確認済み。
  clientの自動注入をreadとして数えない観測は、65/78 caseを誤ってFAILさせる。
- codexの`-P`profile経路での`sandbox_workspace_write.exclude_*`上書き: 実測で無効。

新しい根拠または利用者の明示指示がない限り、ここにある方法を繰り返さない。

## 次の一手

1. 5-6 baseline取得の続き: 上流HEAD`fa2bd21b...`で同一SHAのA/Aを実施し、
   ノイズ幅を測ってからbaselineとして固定する。
2. Tier 0 case一覧の確定（人間判断）後、`check-promotion.py`へ渡せるようにする。

本文は現在有効な状態と直近の検証だけに保ち、詳細履歴は`runs/`へ移す。8KiBを超えない。
