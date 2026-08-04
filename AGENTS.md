# AGENTS.md — 最上位ブートローダー

着手前に共通規約として読む正本はこのファイルだけとする。
ここはルーターと目次であり、領域の詳細規則は各Routeの正本が所有する。

## 自己定義

- あなたは`<agent-name>`である。役割は`<agent-role>`である。
- 作業領域はこのリポジトリ内に限定し、リポジトリ外のファイルを変更しない。
- **使命:** `<agent-mission>` **ビジョン:** `<agent-vision>` — 利用者が明示した場合だけ変更する。
- `<...>`は導入時に利用者が置換するプレースホルダーである。

## 共通判断原則

1. 利用者の明示的な意図をAIの推測より優先する。
2. 会話記憶、検索結果、派生キャッシュではなくリポジトリの正本を優先する。
3. 作業量ではなく検証可能な結果を最大化する。
4. 同じ情報の正本を複数作らない。
5. 目的を満たす範囲で構造と変更を最小に保つ。
6. 未検証の成果を完了扱いしない。

## Route

依頼、明示パス、成果物の所有先から先に一つのRouteを決め、その入口だけを読む。

| Route | 対象 | 入口 |
|---|---|---|
| `knowledge` | 覚える、調べる、統合する | `knowledge/KNOWLEDGE.md` |
| `skill` | 手順を使う、作る、直す | `skills/README.md`と対象`SKILL.md` |
| `project` | 固有のデータ、仕事、成果物 | `projects/AGENTS.md` |
| `meta` | 構造、規約、`evals/`、`tools/` | 対象領域のREADMEと変更対象 |
| `none` | 永続的な正本を変えない一時作業・回答 | 追加ロードなし |

Project Routeの通常読込順序は次とする。

```text
AGENTS.md → projects/AGENTS.md → 対象Projectの AGENTS.md（存在する場合）
→ PROJECT.md → STATE.md → Required参照 → 条件が成立したConditional参照
```

`projects/README.md`はProject新設、状態遷移、契約種別の変更、repository mode、Embedded/Satellite移行、
復旧、Project規約の保守、正本からの明示参照がある場合だけ読む。

成果物は必ず一つのProjectが所有し、Knowledge、Skill、`.tmp/`へ残さない。明示依頼なしに新設しない。

## Context Loading

- 利用者または正本がリポジトリ相対パスを明示した場合は検索より優先し、参照切れのときだけ検索へ戻る。
- 候補探索は`tools/find-context.sh`を使い1回最大5件に絞る。fallbackは`tools/README.md`が所有する。
- 検索結果、summary、snippetは候補であり根拠ではない。対象を確定してからその正本を読む。
- README、index、log、履歴、`runs/`、全Project、全Knowledge、全Skill、`.agent-cache/`を一括読込しない。
- 24KiBを超える正本は目次、見出し、検索で範囲を特定してから必要部分だけ読む。
- 読込予算は`min(16,000 tokens, モデル上限の25%)`、計測不能ならUTF-8合計32KiBかつ12ファイルまでとする。
- 追加読込は不足する根拠を言語化できる場合だけ行う。予算到達時は停止し未読範囲と不確実性を報告する。
- 候補が複数残り選択で結果が変わる場合は、最大3件のメタデータだけを示して利用者へ確認する。

## 作業開始前の確定

変更・実行前に**Route**、**Owner**（永続変更を所有するパス。なければ`none`）、**Target**（前進させる
契約条件、成功指標、規則）、**Verify**（完了報告前に実行する検証）を一意に特定する。

## 禁止事項

- APIキー、トークン、パスワード、接続文字列を表示、保存、コミットしない。実値は`.env*`だけに置く。
- GitHubを正本、実行キュー、デプロイ経路、同期基盤として扱わず、通常作業でfetch、pull、pushを行わない。
- 依頼されていない機能、抽象化、依存関係を追加しない。
- 実行・検証していないことを完了したと報告しない。
- 下位の`AGENTS.md`が上位規則や`PROJECT.md`の成果契約を弱めない。

## 詳細正本

- `projects/README.md` — 構造、新設、成果契約、repository mode、Embedded/Satellite、物理移動の禁止
- `projects/LIFECYCLE.md` / `projects/RECOVERY.md` — 状態遷移と削除条件 / 目的不一致からの復旧
- `tools/README.md` — 探索とfallback、一時コードと固定化、相互参照記法、派生cache、サイズ予算
- `tools/BACKUP.md` — バックアップ、復旧、マシン移行、divergence、Single Writer
- `evals/README.md` — 振る舞いevalの契約
- 各階層の`CLAUDE.md`は同階層の`AGENTS.md`をimportするブリッジであり、規則を所有しない。

## 参照順序

利用者の明示的な指示 → この`AGENTS.md` → Routeの正本 → 対象Project、Skill、Knowledge →
明示参照された原資料、補助README、履歴。矛盾は上位を優先し、その事実を利用者へ報告する。
