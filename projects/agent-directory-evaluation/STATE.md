---
updated_at: 2026-08-06
---

# Current State

## 現在の到達点

- OpenAGT初期構築の一部として本Projectを新設し、`docs/EVALUATION.md`（policy v1.0.0）と
  最小harness（manifest生成、sandbox生成、grading、比較、verify.sh）を整備した。
- harness自己検証（known-good PASS、known-bad FAIL、hash欠落INVALID、A/A NO_CHANGE、
  sandbox隔離、secret scan）が合格している。
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
- `runs/`は実runが発生していないため未作成（先回り生成しない方針）。

## 現在有効な決定

- 初期source revision（評価対象baseline）: `8325b185fb9410bff44cf6ec9a9b99246fe8cc0f`
  （agent-directory/main、2026-08-06固定。作業途中で上流が進んでも同一作業内では追従しない）。
- 評価policy version: v1.0.0（`docs/EVALUATION.md`。変更は人間の明示決定のみ）。
- 現在のbaseline run: なし（未取得）。
- Draft PR作成は`docs/EVALUATION.md#PR昇格条件`充足時のみ、別Promotion sessionで行う
  （standing approval。2026-08-06利用者指示）。
- 現在判断ではactiveなKnowledgeとSkillを優先し、非activeな参照は履歴確認時だけ使う。

## 失敗・却下済み

- なし（初期構築時点で却下済みの方法はない）

新しい根拠または利用者の明示指示がない限り、ここにある方法を繰り返さない。

## 次の一手

1. 作業環境で実際に利用可能なclient（help・version・trace出力）を確認し、最初の
   execution configを1つ固定してbaseline runを取得する。

本文は現在有効な状態と直近の検証だけに保ち、詳細履歴は`runs/`へ移す。8KiBを超えない。
