# agent-directory

長期稼働するAIエージェント1体ごとに持つ、ローカルファーストのディレクトリ構造テンプレート。
Knowledge、Skill、Projectを正本として育てながら、1タスクの読込量は総量から切り離す。

## English overview

A local-first repository template for one long-running AI agent. Canonical Markdown and source files may grow,
while deterministic, status-aware retrieval keeps each task's working context bounded.

`AGENTS.md` is a bootloader and router, not an encyclopedia. It resolves one Route, then hands off to the
canonical file that owns that domain's rules. Instructions live in three layers: the root router, the shared
`projects/AGENTS.md` entry, and an optional per-Project `AGENTS.md` that carries only local work differences.

- `AGENTS.md` — self definition, mission, routing table, minimal context loading, prohibitions, index
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

テンプレートのままではプレースホルダーが残るため、通常の検証は合格し、`--strict`は導入完了まで失敗する。

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
| `project` | 固有の仕事・成果物 | `projects/AGENTS.md`、対象`PROJECT.md`、`STATE.md` |
| `meta` | 規約、テンプレート、eval、tool | 対象領域のREADMEと変更対象 |
| `none` | 永続変更のない回答・一時作業 | 必要最小限。中間物は`.tmp/` |

## AGENTS.mdの三層

`AGENTS.md`は百科事典ではなく、ブートローダー兼ルーター兼目次である。詳細規則は各Routeの正本が所有し、
ルートには発動条件と参照先だけを残す。`CLAUDE.md`は同階層の`AGENTS.md`をimportするブリッジであり、
規則を所有しない。

| 層 | ファイル | 所有する内容 |
|---|---|---|
| ルート | `AGENTS.md` | 自己定義、使命、共通判断原則、Route判定、最小Context Loading、禁止事項、目次 |
| Project共通 | `projects/AGENTS.md` | 全Project共通の着手・実行・完了手順だけ |
| Project個別 | `projects/<name>/AGENTS.md` | 任意。そのProject固有の作業差分だけ |

通常のProjectタスクの読込順序は次とする。

```text
AGENTS.md → projects/AGENTS.md → 対象Projectの AGENTS.md（存在する場合）
→ PROJECT.md → STATE.md → Required参照 → 条件が成立したConditional参照
```

`projects/README.md`は毎回読む必須正本ではない。Project新設、状態遷移、finite/continuous契約の変更、
repository mode、Embedded/Satellite移行、構造の保守、復旧、Project規約の変更、正本からの明示参照が
ある場合だけ読む。

個別Projectの`AGENTS.md`は任意の差分ファイルであり、全Projectへ一律生成しない。`_template/`にも置かず、
新規Projectへ自動複製しない。責務は次のとおり分ける。

```text
<name>/AGENTS.md = そのProjectだけの作業差分（コマンド、編集禁止、承認ゲート、検証順序）
PROJECT.md       = 目的、成果契約、固定判断、品質、検証方法
STATE.md         = 現在目標、現在状態、検証証拠、ブロッカー、次の一手
```

個別`AGENTS.md`を置く場合は同階層に`CLAUDE.md`を必ず置き、`CLAUDE.md`だけを単独で置かない。
`CLAUDE.md`の中身は`@AGENTS.md`の一行だけとし、validatorはファイル全体の完全一致で検査する。Embedded Projectだけに置け、Satellite Hub側は従来どおり`PROJECT.md`と`STATE.md`以外を
持たない。Satellite固有の`AGENTS.md`はSatelliteリポジトリ本体のルートが所有する。

サイズ予算はルート`AGENTS.md`が8KiB（4KiB超はwarning）、`projects/AGENTS.md`と個別`AGENTS.md`が
各2KiBである。validatorはこの3層の存在、サイズ、`CLAUDE.md`の完全一致、Route表と入口ファイルの実在、
個別`AGENTS.md`が契約・状態見出しを持たないこと、Satellite Hubの制限を検査する。

## 構造

```text
agent-directory/
├── AGENTS.md                     # ブートローダー兼ルーター兼目次
├── CLAUDE.md                     # @AGENTS.md
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
│   ├── AGENTS.md                 # Project作業共通の薄い入口
│   ├── CLAUDE.md                 # @AGENTS.md
│   ├── README.md                 # Projectシステムの詳細正本。条件付きで読む
│   ├── LIFECYCLE.md              # 状態遷移時だけ読む
│   ├── RECOVERY.md               # 目的不一致の復旧時だけ読む
│   ├── _template/                # PROJECT.mdとSTATE.mdだけ。AGENTS.mdは持たない
│   └── <project-name>/
│       ├── AGENTS.md             # 任意。Project固有の作業差分がある場合だけ
│       ├── CLAUDE.md             # 上記がある場合の @AGENTS.md ブリッジ
│       ├── PROJECT.md
│       └── STATE.md
├── evals/
│   ├── README.md
│   ├── cases/
│   └── fixtures/
└── tools/
    ├── README.md
    ├── BACKUP.md                  # バックアップ・復旧・移行時だけ読む
    ├── build-context-cache.sh
    ├── find-context.sh
    ├── append-knowledge-log.sh
    ├── backup-to-github.sh
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
欠損・stale時はToolが一度再生成する。生成不能時の正本検索fallbackは[tools/README.md](tools/README.md)が所有する。

## Context Loadingの既定値

ルート`AGENTS.md`は予算と共通規則だけを持ち、領域別の上限は各Routeの正本が所有する。

- 候補: 1検索最大5件（`AGENTS.md`）
- 正本の合計: 32KiB・12ファイル、または16,000 token・モデル上限25%の小さい方（`AGENTS.md`）
- 24KiB超のファイル: 見出し・検索で範囲を絞って部分読込（`AGENTS.md`）
- Knowledge: 初回3ページ、追加後最大6ページ（`knowledge/KNOWLEDGE.md`）
- Skill Required Knowledge: 3件（`skills/README.md`）
- Project Required参照: KnowledgeとSkillの合計6件（`projects/README.md`）
- log、closed logs、runs、Git履歴: 通常0件

## 検証

```bash
bash tools/validate-agent-directory.sh
bash tools/validate-agent-directory.sh --strict --full
bash tools/validate-agent-directory.sh --full --base main
```

validatorは構造、`AGENTS.md`と`CLAUDE.md`の三層、frontmatter、Project契約、状態、参照上限、サイズ、
index、log、eval schema、派生cacheの決定的再生成、禁止されたGit追跡を検査する。
`--base`は不変原資料や閉鎖済みlogの変更も検査する。

## ローカル正本とGitHubバックアップ

ローカルの作業コピーが唯一の書込可能な稼働正本であり、GitHubは最後に確定したコミットの受動的な
遠隔復旧コピーである。GitHubは必須の実行基盤ではなく、通常タスクはネットワークなしで完結する。
GitHub Actions、CI、定期同期、自動commit、自動pushは使用しない。

- エージェント1体につきGitHub Privateリポジトリを1つ用意し、共用しない。
- 公開スケルトンと実運用データを分離する。スケルトンへ実運用データをpushしない。
- remote名は`backup`、branchは`main`を既定とする。
- GitHub上で直接編集しない。remoteは常にpush先であり編集先ではない。
- 書込可能な稼働マシンは常に1台だけとする（Single Writer）。
- Projectは`repository_mode: embedded`で開始し、ルートGitとPrivate backupへ含める。外部の人または
  システムが独立repo identityを必要とする場合だけ、[projects/README.md](projects/README.md)の
  「Repository mode」に従って`satellite`へ昇格する。
- Satellite本体はHub backupの対象外だが、Hubの`STATE.md`が採用commit SHAを固定参照する。
  backup ToolはそのSHAをSatellite remoteから取得できることを確認してからHubをpushする。

### セットアップ

GitHubで空のPrivateリポジトリを作成してから、次を実行する。`<owner>`と
`<private-agent-repository>`は利用者が置換する。

```bash
git remote rename origin template
git remote add backup git@github.com:<owner>/<private-agent-repository>.git
git config remote.pushDefault backup
bash tools/backup-to-github.sh --remote backup --branch main
```

スケルトンの更新を追う必要がなければ`git remote remove template`で`template` remoteを削除してよい。
実在するPrivate URLや認証情報はこのリポジトリへ保存しない。

### バックアップ

```bash
bash tools/backup-to-github.sh --dry-run
bash tools/backup-to-github.sh
```

利用者がバックアップ、マシン移行、破壊的変更前の復旧点作成、チェックポイント保存を明示した場合だけ
実行する。通常タスクの完了条件ではない。成功時は`BACKUP_OK ... sha=<40文字SHA>`を出力し、
未コミット変更、秘密情報の追跡、remoteの分岐、100MiB以上のobjectがあれば何も変更せず停止する。
ignore済みを含むnested `.git`、不完全なSatellite宣言、remoteから取得できない採用SHAでも停止する。

### 復旧・移行

```bash
git clone git@github.com:<owner>/<private-agent-repository>.git <new-directory>
git -C <new-directory> remote rename origin backup
git -C <new-directory> rev-parse HEAD
git -C <new-directory> ls-remote --heads backup main
bash <new-directory>/tools/validate-agent-directory.sh
bash <new-directory>/tools/build-context-cache.sh
```

remote SHAとローカルHEADの一致を確認し、validatorを実行し、`.agent-cache/`を正本から再生成する。
`.env`などの秘密情報はバックアップ対象外なので、パスワードマネージャー等の別経路から復旧する。
新マシンを唯一の書込者へ昇格するまで、旧マシンから書き込まない。

条件、対象範囲、divergence時の停止、禁止コマンドの詳細は[tools/BACKUP.md](tools/BACKUP.md)が所有する。
バックアップ・復旧・移行を扱うときだけ読む。

## 規模拡大

通常はfrontmatter、TSV、`rg`/`grep`を使う。routeable Knowledgeが1,000件またはcatalogが5,000行へ
達すると、cache生成ToolがSQLite FTS5 trigramを自動生成し、検索Toolが本文検索へ自動利用する。
SQLite/FTS5を利用できない環境でも正本を失わず、警告して`rg`/`grep`へfallbackする。
利用者が移行やDB管理を行う必要はない。生成DBは常にGit管理外で、正本から再生成できる。

ベクトル検索は自動導入しない。決定的検索で品質不足が実測されない限り、依存関係を増やさない。

## ライセンス

[MIT License](LICENSE)
