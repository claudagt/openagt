---
updated_at: 2026-08-06
---

# Current State

## 現在の到達点

- `docs/EVALUATION.md`（policy v1.0.1）と最小harnessを整備し、`verify.sh`の24検査が合格。
- 2026-08-06の人間レビューで初期構築は合格。実運用開始はP0/P1解消まで保留。
- 第2段階でadapter（`codex-adapter.sh`）、run分類（`classify-run.py`）、case grader
  （`grade-case.py`）、trace写像（`map-trace.py`）、外側runner（`run-case.sh`）を追加。
- 実clientでのbaseline runは未実施。実モデル評価は未検証である。

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
- 結果: 合格（`VERIFY_OK`）。manifest決定性、known-good/known-bad grading、A/A NO_CHANGE、
  sandbox隔離、secret scanに合格。実client runは未実施のためPC-01の実運用充足は未検証。

- 対象: `PROJECT.md#PC-05`
- 確認日: 2026-08-06 / 方法: verify.sh内のsecret scan
- 結果: 合格。検出ゼロ。

- 対象: `PROJECT.md#PC-02`
- 確認日: 2026-08-06（subject実行隔離。HG-02のOS強制）
- 方法: `bash scripts/codex-adapter.sh --selftest`（`codex sandbox`。実モデル呼出なし）
- 結果: 合格（`SELFTEST_PASS`）。workspace内write=許可、workspace外write=拒否、
  `$HOME`へのwrite=拒否、network egress=拒否をOSレベル（macOS Seatbelt）で確認。
  read制限は未確認（sandboxはread側を制限しない）。

## 未完了・ブロッカー

- **ブロッカー（外部）**: codexのusage limit到達により実モデルsmokeが未完了
  （reset: 2026-08-08 14:17）。plumbing（auth解決、JSONL trace取得、exit code伝播）は
  観測できたが、モデルturnは`turn.failed`。実モデル呼出回数: 1（成功0、quota失敗1）。
  この失敗は`classify-run.py`が`INFRA_UNAVAILABLE`/`usage_limit`として分類済みで、
  candidate失敗としては数えない。
- P0（部分解消）: write root制限、HOME/CODEX_HOME分離、network遮断、利用者設定/rules非読込は
  adapterでOS強制・実測済み。**未解消**: sandboxはread側を制限せず、subjectから
  evaluator repositoryや`$HOME`配下を読める。現状はpath秘匿と配置のみで担保。
- adapterのexecution configは`system_instruction_hash`、`tool_schema_hash`、sampling、
  reasoning、各種上限が`unknown`（実値化はsmoke完了後）。
- P0（解消）: case grader `grade-case.py`と外側runner `run-case.sh`を実装。write系は
  clientの自己申告ではなくsubject sandboxのGitから観測する（偽申告・無申告のいずれでも
  write gateを通過できないことをverify.shで固定）。
- **未解消（実client接続）**: codexのitem系event（command_execution、file_change等）の
  field名が未確認のため、`map-trace.py`はread/runを写像できずunmappedとして数える。
  結果、実codex traceではread/run系の期待項目がUNVERIFIEDになる。実trace取得後に写像規則を
  追加する（推測で固定しない）。writeはclient非依存のため現時点でも有効。
- P1: `grade-run.py`の強度不足（HG-06未実装、path正規化なし、秘密検査がevents限定、
  Tier 0がmetrics自己申告、unknown hashのVALID扱い）。
- P1: `compare-runs.py`は1対1比較のみ。3 trial集約・複数config・最終Promotion Gateが
  未実装で、MDE・noise幅がCLIから上書き可能。
- `runs/`は実runが発生していないため未作成（先回り生成しない方針）。

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
- adapter第1号はcodex（`codex exec`）とする（2026-08-06実測）。根拠: 3client中唯一、
  documented CLI flagでOS強制sandbox（`-s workspace-write`）を選べ、`--json`でrunner側
  JSONL traceを取得でき、`--ignore-user-config`/`--ignore-rules`/`--ephemeral`で
  execution configをhermeticにできる。claude 2.1.220はOS強制sandbox flagを持たず、
  gemini 0.46.0の`-s`はcontainer runtime前提のため見送り。
- 実測: codexの組込permission profileは`:workspace`と`:read-only`のみ（colon接頭辞）。
  `sandbox_workspace_write.exclude_*`の上書きは`-P`profile経路では効果がない。

## 失敗・却下済み

- gemini 0.46.0の`-s/--sandbox`: container runtime導入が必要なため第1号adapterから除外。
- codexの`-P`profile経路での`sandbox_workspace_write.exclude_*`上書き: 実測で無効。

新しい根拠または利用者の明示指示がない限り、ここにある方法を繰り返さない。

## 次の一手

1. 5-5 3 trial集約と最終Promotion Gate（`check-promotion`。閾値をCLIから上書きできない構造）。
   併せてP1（grade-run.pyの強度: HG-06、path正規化、秘密検査の範囲、Tier 0導出、
   unknown hash）を独立commitで補強する。
2. quota回復後: smokeを完了し、codexのitem系eventの実形式を確認して`map-trace.py`へ
   read/runの写像規則を追加する。併せてresolved model ID・sampling・上限を実値化する。
3. 5-6 最初の実baseline取得（run開始時点の最新`agent-directory/main`を再取得・固定）。

本文は現在有効な状態と直近の検証だけに保ち、詳細履歴は`runs/`へ移す。8KiBを超えない。
