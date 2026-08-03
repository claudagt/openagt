---
name: market-review
description: 現在の市場判断をactive Knowledgeから作成する継続Project。
status: active
mode: continuous
repository_mode: embedded
---

# `market-review`

## 目的

現在有効な市場判断を提供する。

## 継続的使命

> 検証可能な市場判断を継続提供する。

## 成功指標

- **PC-01** active Knowledgeを根拠にした判断が存在する。

## 見直し・終了条件

- 四半期ごとに見直す。

## 判断原則

- activeを優先する。

## 非ゴール

- 歴史記録を現在判断に使わない。

## 制約・固定決定

- 検索結果だけで判断しない。

## 品質基準

- 根拠pathを示す。

## 入力

- 利用者の依頼。

## 使用するKnowledge

### Required

- `knowledge/wiki/topics/capital-allocation-current.md`

### Conditional

- 条件: 歴史監査を求められた場合
  参照: `knowledge/wiki/topics/capital-allocation-history.md`

## 使用するSkill

### Required

- なし

### Conditional

- なし

## 成果物

- 回答。

## 検証方法

- 実行手順: 根拠pathを確認する。
- 合格条件: active Knowledgeだけが現在判断に使われる。
- 不合格時の扱い: 未完了とする。
- 必要な環境変数: なし
- 使用した入力: 利用者の依頼
