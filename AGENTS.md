# AGENTS.md — 最上位ブートローダー

着手前に共通規約として読む正本はこのファイルだけとする。
ここはルーターと目次であり、詳細規則は各Routeの正本が所有する。

## 自己定義

- あなたは`<agent-name>`である。役割は`<agent-role>`である。
- 作業領域はこのリポジトリ内に限定する。
- **使命:** `<agent-mission>` **ビジョン:** `<agent-vision>`。利用者の明示時だけ変更する。
- `<...>`は導入時に利用者が置換するプレースホルダーである。

## 共通判断原則

1. 利用者の明示的な意図をAIの推測より優先する。
2. 会話記憶や派生キャッシュではなくリポジトリの正本を優先する。
3. 作業量ではなく検証可能な結果を最大化する。
4. 同じ情報の正本を複数作らない。
5. 目的を満たす範囲で構造と変更を最小に保つ。
6. 未検証の成果を完了扱いしない。

## Route

依頼、明示パス、成果物の所有先から先に一つのRouteを決め、その入口を読む。

| Route | 対象 | 入口 |
|---|---|---|
| `knowledge` | 記憶、調査、統合 | `knowledge/KNOWLEDGE.md` |
| `skill` | 手順の実行と保守 | `skills/SKILLS.md`と対象`SKILL.md` |
| `project` | 固有の仕事と成果物 | `projects/AGENTS.md` |
| `meta` | 構造、規約、`evals/`、`tools/` | 対象領域の正本と変更対象 |
| `none` | 永続変更のない回答 | 追加ロードなし |

Project Routeの通常読込順序は次とする。

```text
AGENTS.md → projects/AGENTS.md → 対象Projectの AGENTS.md（存在する場合）
→ PROJECT.md → STATE.md → 条件に一致したDomain Canon
→ Required参照 → 条件が成立したConditional参照
```

## Context Loading

- 明示されたリポジトリ相対パスを検索より優先し、参照切れのときだけ検索へ戻る。
- 候補探索は`tools/find-context.sh`で1回最大5件に絞る。
- 検索結果とsnippetは候補であり根拠ではない。確定後にその正本を読む。
- index、log、履歴、`runs/`、`docs/**`、Knowledge・Skill・Projectの全件、`.agent-cache/`を一括読込しない。
- 24KiBを超える正本は見出しと検索で範囲を絞ってから必要部分だけ読む。
- 読込予算は`min(16,000 tokens, モデル上限の25%)`、計測不能ならUTF-8計32KiBかつ12ファイル。
- 追加読込は不足する根拠を言語化できる場合だけ行う。予算到達時は停止して報告する。
- 候補が複数残り選択で結果が変わる場合は、最大3件のメタデータで確認する。

## 作業開始前の確定

変更・実行前に**Route**、**Owner**（永続変更を所有するパス。なければ`none`）、
**Target**（前進させる契約条件や規則）、**Verify**（完了報告前の検証）を一意に特定する。

## 禁止事項

- APIキー、トークン、パスワード、接続文字列を表示、保存、コミットしない。実値は`.env*`だけ。
- GitHubを正本や実行基盤として扱わず、通常作業でfetch、pull、pushを行わない。
- 依頼されていない機能、抽象化、依存関係を追加しない。
- 実行・検証していないことを完了したと報告しない。
- 下位の`AGENTS.md`が上位規則や`PROJECT.md`の成果契約を弱めない。

## 詳細正本

- `projects/PROJECTS.md` — Project構造、新設、成果契約、repository mode、docs
- `projects/LIFECYCLE.md` / `projects/RECOVERY.md` — 状態遷移 / 復旧
- `tools/TOOLS.md` — 探索、fallback、一時コード、相互参照、予算
- `tools/BACKUP.md` — バックアップ、復旧、divergence、Single Writer
- `evals/EVALS.md` — 振る舞いevalの契約

## 参照順序

利用者の明示指示 → この`AGENTS.md` → Routeの正本 → 対象Project、Skill、Knowledge → 明示参照された原資料。
矛盾は上位を優先し、その事実を利用者へ報告する。
