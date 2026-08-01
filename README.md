# agent-directory

長期稼働するAIエージェント1体ごとに持つ、ローカルファーストのディレクトリ構造テンプレート。
Knowledge、Skill、Projectを正本として育てながら、1タスクの読込量は総量から切り離す。

## English overview

A local-first repository template for one long-running AI agent. Canonical Markdown and source files may grow,
while deterministic, status-aware retrieval keeps each task's working context bounded.

- `AGENTS.md` — mission, routing, common policy, and the Context Loading Contract
- `knowledge/` — immutable records and reusable source/topic knowledge
- `skills/` — reusable procedures and output contracts
- `projects/` — outcome contracts, current state, inputs, outputs, and run evidence
- `evals/` — behavioral contracts for routing and bounded retrieval
- `tools/` — dependency-free structure validation and context discovery
- `.agent-cache/` — ignored, disposable catalog regenerated from canonical files

The repository is model- and client-agnostic. Codex, Claude Code, CLIs, and IDE integrations can use the same
canonical files and the same `tools/find-context.sh` output. Product-side memory and search databases are caches,
never the source of truth.

## 利用開始

1. このリポジトリをエージェント1体につき1つコピーまたはクローンする。
2. [AGENTS.md](AGENTS.md)の`<agent-name>`、役割、使命、ビジョンを置換する。
3. `skills/_template/`または`projects/_template/`を、明示された必要に応じてコピーする。
4. `bash tools/validate-agent-directory.sh --strict --full`を実行する。
5. `tools/find-context.sh --route <route> --limit 5 -- "検索語"`で対象候補を絞って運用する。

テンプレートのままではプレースホルダーがあるため、通常validationは合格し、`--strict`は導入完了まで失敗する。

## 基本原則

- リポジトリ内の正本を会話記憶、製品側AIメモリ、検索結果より優先する。
- `raw/`と`research/`の既存原資料は変更・削除しない。
- `sources/`と`topics/`も、人間・AIの判断を含むKnowledge正本として扱う。
- `PROJECT.md`は低頻度の成果契約、`STATE.md`は短い現在状態とする。
- 完了・停止・廃止を物理archiveで表さず、frontmatterの状態で検索から除外する。
- 全件台帳をLLMへ渡さず、状態付きの決定的検索で最大5候補に絞る。
- 派生catalogや規模閾値で自動生成するSQLiteは削除・再生成可能とし、恒久参照先にしない。
- ベクトルDB、常駐サービス、外部課金は既定で導入しない。

## Route

| Route | 対象 | 着手後に読む正本 |
|---|---|---|
| `knowledge` | 記憶、調査、統合 | `knowledge/KNOWLEDGE.md`と選択したKnowledge |
| `skill` | 分析・判定手順 | `skills/README.md`と対象`SKILL.md` |
| `project` | 固有の仕事・成果物 | `projects/README.md`、対象`PROJECT.md`、`STATE.md` |
| `meta` | 規約、テンプレート、eval、tool | 対象領域のREADMEと変更対象 |
| `none` | 永続変更のない回答・一時作業 | 必要最小限。中間物は`.tmp/` |

## 構造

```text
agent-directory/
├── AGENTS.md
├── CLAUDE.md
├── README.md
├── .agent-cache/                 # Git管理外の派生物
├── knowledge/
│   ├── KNOWLEDGE.md
│   ├── raw/                      # 不変の内部原記録
│   ├── research/                 # 不変の外部原資料
│   └── wiki/
│       ├── index.md              # 小型ルートマップ
│       ├── log.md                # 現在の変更履歴。既定では読まない
│       ├── logs/                 # 閉鎖済みの不変ログ
│       ├── _template/            # source/topic雛形
│       ├── sources/              # 資料別Knowledge正本
│       └── topics/               # 統合Knowledge正本
├── skills/
│   ├── README.md
│   └── _template/
├── projects/
│   ├── README.md
│   ├── LIFECYCLE.md              # 状態遷移時だけ読む
│   ├── RECOVERY.md               # 目的不一致の復旧時だけ読む
│   └── _template/
├── evals/
│   ├── README.md
│   ├── cases/
│   └── fixtures/
└── tools/
    ├── README.md
    ├── build-context-cache.sh
    ├── find-context.sh
    ├── append-knowledge-log.sh
    └── validate-agent-directory.sh
```

## コンテキスト探索

```bash
# active Knowledgeを最大5件
tools/find-context.sh --route knowledge --limit 5 -- "資本配分"

# 明示的な監査時だけ非activeも含める
tools/find-context.sh --route project --include-inactive -- "site migration"
```

検索順位は、明示パス・正本の明示参照を最優先とし、Tool内ではname完全一致、alias完全一致、
name/alias/description/path一致、本文一致の順に決定する。検索結果は候補であり、選択後に正本を読む。

`.agent-cache/catalog.tsv`と`manifest.tsv`はfrontmatterと実ファイルから生成される。
欠損・stale時はToolが一度再生成する。生成不能時の正本検索fallbackも`AGENTS.md`で規定する。

## Context Loading Contractの既定値

- 候補: 1検索最大5件
- Knowledge: 初回3ページ、追加後最大6ページ
- Project Required参照: KnowledgeとSkillの合計6件
- Skill Required Knowledge: 3件
- 正本の合計: 32KiB・12ファイル、または16,000 token・モデル上限25%の小さい方
- 24KiB超のファイル: 見出し・検索で範囲を絞って部分読込
- log、closed logs、runs、Git履歴: 通常0件

## 検証

```bash
bash tools/validate-agent-directory.sh
bash tools/validate-agent-directory.sh --strict --full
bash tools/validate-agent-directory.sh --full --base main
```

validatorは構造、frontmatter、Project契約、状態、参照上限、サイズ、index、log、eval schema、
派生cacheの決定的再生成、禁止されたGit追跡を検査する。`--base`は不変原資料や閉鎖済みlogの変更も検査する。

## 規模拡大

通常はfrontmatter、TSV、`rg`/`grep`を使う。routeable Knowledgeが1,000件またはcatalogが5,000行へ
達すると、cache生成ToolがSQLite FTS5 trigramを自動生成し、検索Toolが本文検索へ自動利用する。
SQLite/FTS5を利用できない環境でも正本を失わず、警告して`rg`/`grep`へfallbackする。
利用者が移行やDB管理を行う必要はない。生成DBは常にGit管理外で、正本から再生成できる。

ベクトル検索は自動導入しない。決定的検索で品質不足が実測されない限り、依存関係を増やさない。

## ライセンス

[MIT License](LICENSE)
