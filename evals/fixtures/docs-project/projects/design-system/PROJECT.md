---
name: design-system
description: 社内プロダクトの共通デザインシステムを、実装済みコンポーネントと判断基準まで含めて確立する。
status: active
mode: finite
repository_mode: embedded
---

# `design-system`

## 目的

各プロダクトで重複している画面部品と判断基準を一本化し、実装と意思決定の往復を減らす。

## 最終ゴール

> 3プロダクトが同一のコンポーネント定義と品質判断基準を使い、検証済みで参照できる状態にする。

## 完了条件

- **PC-01** コンポーネント定義が`outputs/component-catalog.md`に存在し、3プロダクトが参照している。
- **PC-02** 定性的な品質判断が`docs/PRODUCT_SENSE.md`に、構造決定が`docs/DESIGN.md`に分離されている。
- **PC-03** `scripts/verify-catalog.sh`が合格する。

## 判断原則

- 見た目の統一より、判断が再現できることを優先する。
- 例外を増やす前に、既存の原則が実態と合っているかを先に見直す。

## 非ゴール

- 個別プロダクトの機能開発は行わない。
- ブランド刷新は扱わない。

## 制約・固定決定

- 構造地図は`ARCHITECTURE.md`、分野の現在有効な原則は`docs/`直下のDomain Canonが所有する。
- 詳細な調査記録は`docs/research/`へ置き、確定していない結論をRoot Knowledgeへ昇格させない。

## 品質基準

- 原則には必ず適用範囲と反例を添える。
- 未検証のコンポーネントを完成扱いにしない。

## 入力

- `inputs/current-components.csv`

## 使用するKnowledge

### Required

- なし

### Conditional

- なし

## 使用するSkill

### Required

- なし

### Conditional

- なし

## 成果物

- `outputs/component-catalog.md`

## 検証方法

- 実行手順: `bash scripts/verify-catalog.sh`
- 合格条件: カタログに必須見出しが存在し、終了コードが0になる。
- 不合格時の扱い: 完了扱いにせず、理由と次の一手を`STATE.md`に残す。
- 必要な環境変数: なし
- 使用した入力: `inputs/current-components.csv`
