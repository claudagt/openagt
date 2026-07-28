---
name: site-migration
status: active
mode: finite
---

# `site-migration`

## 目的

旧ルートから新ルートへの移行結果を、運用担当者が検証できる状態にする。

## 最終ゴール

> 指定された全ルートの移行結果と検証証拠が、一つの移行サマリーとして引き渡せる状態になる。

## 完了条件

- [ ] `outputs/migration-summary.md` が存在する。
- [ ] サマリーに移行対象、検証結果、残課題が含まれる。
- [ ] `scripts/verify-migration.sh` が合格する。

## 判断原則

- 移行件数より、各ルートの検証可能性を優先する。
- 未確認のルートを移行済みと扱わない。

## 非ゴール

- 新しいルートや機能を追加しない。

## 制約・固定決定

- `inputs/routes.txt` にないルートを対象へ加えない。

## 品質基準

- 検証証拠のない完了宣言を禁止する。

## 入力

- `inputs/routes.txt`

## 使用するKnowledge

- なし

## 使用するSkill

- なし

## 成果物

- `outputs/migration-summary.md`

## 検証方法

- 実行手順: `bash scripts/verify-migration.sh`
- 合格条件: 必須見出しと全入力ルートを含み、終了コードが0になる。
- 不合格時の扱い: `status: active` のまま、理由と次の一手を `STATE.md` に残す。
- 必要な環境変数: なし
- 使用した入力: `inputs/routes.txt`
