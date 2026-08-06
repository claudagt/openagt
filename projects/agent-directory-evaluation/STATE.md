---
updated_at: 2026-08-06
---

# Current State

## 現在の到達点

- OpenAGT初期構築の一部として本Projectを新設し、`docs/EVALUATION.md`（policy v1.0.0）と
  最小harness（manifest生成、sandbox生成、grading、比較、verify.sh）を整備した。
- harness自己検証（known-good PASS、known-bad FAIL、hash欠落INVALID、A/A NO_CHANGE、
  sandbox隔離、secret scan）が合格している。
- 2026-08-06の人間レビューで初期構築は合格判定。指摘のP2（root `AGENTS.md`の4KiB超過）を
  修正済み（validator warningゼロ）。実運用開始はP0/P1解消まで保留。
- 実clientでのbaseline runは未実施。実モデル評価は未構成・未検証である。

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
- 確認日: 2026-08-06
- 方法: `bash projects/agent-directory-evaluation/scripts/verify.sh`
- 結果: 合格（`VERIFY_OK`）。manifest決定性、known-good/known-bad grading、A/A NO_CHANGE、
  sandbox隔離、secret scanのsynthetic fixture検査に合格。実client runは未実施のため
  PC-01の実運用充足は未検証。

- 対象: `PROJECT.md#PC-05`
- 確認日: 2026-08-06
- 方法: verify.sh内のsecret scan（tracked公開成果物への秘密情報パターン検査）
- 結果: 合格。検出ゼロ。

## 未完了・ブロッカー

- 実client adapter（Codex、Claude等）のexecution configが未構成。実モデルによる
  baseline runとTier 0 trialは未実施・未検証。
- P0: 現在のsandboxはclone分離のみで、OSレベルの実行隔離（write root制限、HOME分離、
  network遮断、clientのworkspace permission制限）はadapter未実装のため強制されていない。
- P0: 実モデルrunner・case grader（`evals/cases/*.yaml`の期待値照合、fixture overlay、
  外側からのtrace/diff/metrics生成）が未実装。
- P1: `grade-run.py`の強度不足（HG-06未実装、path正規化なし、秘密検査がevents限定、
  Tier 0がmetrics自己申告、unknown hashのVALID扱い）。
- P1: `compare-runs.py`は1対1比較のみ。3 trial集約・複数config・最終Promotion Gateが
  未実装で、MDE・noise幅がCLIから上書き可能。
- `runs/`は実runが発生していないため未作成（先回り生成しない方針）。

## 現在有効な決定

- 初期source revision（評価対象baseline）: `8325b185fb9410bff44cf6ec9a9b99246fe8cc0f`
  （agent-directory/main、2026-08-06固定。作業途中で上流が進んでも同一作業内では追従しない）。
- 評価policy version: v1.0.0（`docs/EVALUATION.md`。変更は人間の明示決定のみ）。
- 現在のbaseline run: なし（未取得）。最初の実運用baselineは、初期source revisionではなく
  run開始時点の最新`agent-directory/main`を再取得・固定して対象とする（2026-08-06レビュー決定。
  レビュー時点は`059a089e...`、同日確認時点では`fa2bd21bf77c2f6b1eaec1c86faf1e4d5400d06a`まで前進）。
- `8325b185... → 最新main`の差分は最初のA/B smokeとして利用してよい（2026-08-06レビュー）。
- Draft PR作成は`docs/EVALUATION.md#PR昇格条件`充足時のみ、別Promotion sessionで行う
  （standing approval。2026-08-06利用者指示）。
- 現在判断ではactiveなKnowledgeとSkillを優先し、非activeな参照は履歴確認時だけ使う。

## 失敗・却下済み

- なし（初期構築時点で却下済みの方法はない）

新しい根拠または利用者の明示指示がない限り、ここにある方法を繰り返さない。

## 次の一手

1. 実client adapterを1つだけ作る（2026-08-06レビューの順序: adapter → subjectの
   workspace/network制限強制 → YAML case grader → 外側runner → 3 trial集約と
   Promotion Gate → 最初の実baseline取得）。着手時に利用可能clientのhelp・version・
   trace出力を実測してexecution configを固定する。

本文は現在有効な状態と直近の検証だけに保ち、詳細履歴は`runs/`へ移す。8KiBを超えない。
