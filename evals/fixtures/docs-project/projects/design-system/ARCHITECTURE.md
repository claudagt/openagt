# ARCHITECTURE — design-system

このProjectが解く問題と、構成要素の配置・境界・依存方向を持つ短い地図である。
現在目標、進捗、TODOは`STATE.md`が持ち、ここには置かない。

## 解く問題

3プロダクトが同じ画面部品を別々に実装しており、変更コストと判断のばらつきが積み上がっている。

## 主要コンポーネント

- `tokens` — 色、間隔、タイポグラフィの原始値
- `primitives` — tokensだけに依存する最小部品
- `patterns` — primitivesを組み合わせた画面単位の構成
- `catalog` — 実装済み部品の一覧と使用条件

## 配置

- 定義とコードは`scripts/`と`outputs/`
- 分野ごとの現在有効な原則は`docs/`直下のDomain Canon
- 調査記録は`docs/research/`

## 依存方向

```text
patterns → primitives → tokens
catalog → patterns
```

逆方向の依存を作らない。`tokens`は他のどの層も参照しない。

## システム境界

- 個別プロダクトのビジネスロジックはこのProjectの外側にある。
- ブランド定義は外部が所有し、このProjectは参照するだけとする。

## アーキテクチャ不変条件

- 層をまたぐ循環依存を作らない。
- `tokens`の変更は`catalog`の再検証を伴う。

## 横断的関心事

- アクセシビリティのコントラスト比は全層で同じ判定を使う。
