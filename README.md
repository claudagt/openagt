# agent-directory

長期稼働するAIエージェント1体ごとに持つ、ローカルファーストのAgent Workspaceテンプレート。
Knowledge、Skill、Projectを正本として育てながら、1タスクの読込量は総量から切り離す。

これは複数の外部リポジトリを束ねるHubではなく、一体のAgent Workspaceである。独立したremote identityが
必要なProjectも、cloneはこのツリー内の固定pathへ置く。

`AGENTS.md`は百科事典ではなく、ブートローダー兼ルーター兼目次である。Routeを一つ決めたら、その領域を
所有する正本へ引き継ぐ。詳細契約は各正本が持ち、READMEはそこへの入口だけを持つ。

## English overview

A local-first Agent Workspace template for one long-running AI agent. Canonical Markdown and source files may
grow, while deterministic, status-aware retrieval keeps each task's working context bounded. It is a single
workspace, not a hub of external repositories: a Project that needs its own remote identity is cloned to the
fixed in-tree path `projects/<name>/repository/`.

`AGENTS.md` is a bootloader and router, not an encyclopedia. It resolves one Route, then hands off to the
canonical file that owns that domain's rules. The repository is model- and client-agnostic: Codex, Claude Code,
CLIs, and IDE integrations use the same canonical files and the same `tools/find-context.sh` output.
Product-side memory and search databases are caches, never the source of truth.

## 利用開始

1. このリポジトリをエージェント1体につき1つコピーまたはクローンする。
2. [AGENTS.md](AGENTS.md)の`<agent-name>`、役割、使命、ビジョンを置換する。
3. `skills/_template/`または`projects/_template/`を、明示された必要に応じてコピーする。
4. `bash tools/validate-agent-directory.sh --strict --full`を実行する。
5. `tools/find-context.sh --route <route> --limit 5 -- "検索語"`で対象候補を絞って運用する。

テンプレートのままではプレースホルダーが残るため、通常の検証は合格し、`--strict`は導入完了まで失敗する。

## 設計方針

- リポジトリ内の正本を会話記憶、製品側AIメモリ、検索結果より優先する。
- `raw/internal/`と`raw/external/`の既存原資料は同じ強さで保護し、変更・削除しない。
- 完了・停止・廃止を物理archiveで表さず、frontmatterの状態で検索から除外する。
- 全件台帳をLLMへ渡さず、状態付きの決定的検索で候補を絞る。
- 派生catalogと自動生成DBは削除・再生成可能とし、恒久参照先にしない。
- ベクトルDB、常駐サービス、CI、外部課金は既定で導入しない。

## Route

| Route | 対象 | 着手後に読む正本 |
|---|---|---|
| `knowledge` | 取り込み、記憶、照会、統合 | [knowledge/KNOWLEDGE.md](knowledge/KNOWLEDGE.md) |
| `skill` | 分析・判定手順、再利用可能な研究方法 | [skills/SKILLS.md](skills/SKILLS.md)と対象`SKILL.md` |
| `project` | 固有の仕事・成果物、具体的な研究活動 | [projects/AGENTS.md](projects/AGENTS.md)、対象`PROJECT.md`、`STATE.md` |
| `meta` | 規約、テンプレート、eval、tool | 対象領域の大文字正本と変更対象 |
| `none` | 永続変更のない回答・一時作業 | 必要最小限。中間物は`.tmp/` |

## 構造

固定ファイルは大文字名、利用者が作るKnowledgeページとProjectの詳細文書は小文字ケバブケースとする。

```text
agent-directory/
├── AGENTS.md                     # ブートローダー兼ルーター兼目次
├── CLAUDE.md                     # @AGENTS.md
├── .agent-cache/                 # Git管理外の派生物
├── knowledge/
│   ├── KNOWLEDGE.md
│   ├── raw/{internal,external}/  # 不変の原記録と原資料
│   └── wiki/
│       ├── INDEX.md              # 小型ルートマップ
│       ├── LOG.md                # 現在の変更履歴。既定では読まない
│       ├── logs/                 # 閉鎖済みの不変ログ
│       ├── _template/            # SOURCE.md / TOPIC.md
│       ├── sources/              # 一つの原資料を解釈したKnowledge
│       └── topics/               # 複数の根拠や判断を統合したKnowledge
├── skills/
│   ├── SKILLS.md
│   └── _template/                # SKILL.mdとagents/だけ
├── projects/
│   ├── AGENTS.md                 # Project作業共通の薄い入口
│   ├── CLAUDE.md                 # @AGENTS.md
│   ├── PROJECTS.md               # Projectシステムの詳細正本。条件付きで読む
│   ├── LIFECYCLE.md              # 状態遷移時だけ読む
│   ├── RECOVERY.md               # 目的不一致の復旧時だけ読む
│   ├── _template/                # PROJECT.mdとSTATE.mdだけ
│   └── <project-name>/           # PROJECT.md、STATE.md、任意のAGENTS.md・docs/・inputs/・outputs/
├── evals/                        # EVALS.md、cases/、fixtures/
└── tools/                        # TOOLS.md、BACKUP.md、6つのTool
```

## Repository境界

すべてのProjectは`repository_mode: embedded`で開始し、独立したremote identityが必要になった場合だけ
`independent`へ昇格する。Independentの通常cloneは必ず次の固定pathへ置く。普通の`git clone`であり、
`repository/.git`は実directoryとする。worktree、submodule、symlink、`.git` fileは使わない。

```text
projects/<embedded-project>/      # root Gitが全体を追跡する
├── PROJECT.md
├── STATE.md
├── ARCHITECTURE.md               # 任意
├── docs/                         # 任意
└── outputs/

projects/<independent-project>/   # root Gitが追跡するのは2ファイルだけ
├── PROJECT.md                    # remote URL、reason、default branch
├── STATE.md                      # ## Repository State に採用revisionだけ
└── repository/                   # 普通のclone。root Gitはignore、Independent Gitのroot
    ├── .git/                     # 実directory
    ├── AGENTS.md / ARCHITECTURE.md / docs/
    └── src/ tests/ …
```

| 所有 | 対象 |
|---|---|
| root Gitが追跡 | 全Embedded Project、Independentの`PROJECT.md`と`STATE.md` |
| Independent Gitが追跡 | コード、tests、Project固有`AGENTS.md`、`ARCHITECTURE.md`、`docs/`、実行・release設定、Git履歴 |
| root Gitがignore | `projects/*/repository/`。gitlinkもmanifest登録も検索候補も持たない |

statusにかかわらず全Independent repositoryが固定pathへmaterialize済みであることを健全な状態とする。

```bash
bash tools/materialize-project-repositories.sh --all --check
bash tools/materialize-project-repositories.sh --all
bash tools/materialize-project-repositories.sh --project <name>
```

昇格条件、`repository_reason`、session rootとSHA handoffは[projects/PROJECTS.md](projects/PROJECTS.md)が
所有する。agent-directory外へcloneを置く旧Satellite方式は現役modeとして許可せず、移行対象としてだけ
[tools/BACKUP.md](tools/BACKUP.md)が扱う。

## コンテキスト探索

```bash
# active Knowledgeを最大5件
tools/find-context.sh --route knowledge --limit 5 -- "資本配分"

# 明示的な監査時だけ非activeも含める
tools/find-context.sh --route project --include-inactive -- "site migration"
```

明示パスと正本の明示参照を最優先とし、検索結果は候補として扱う。選択後に正本を読む。
`.agent-cache/`のcatalogとmanifestは正本から再生成され、欠損・stale時はToolが一度作り直す。
探索順位、fallback、読込予算の詳細は[tools/TOOLS.md](tools/TOOLS.md)と[AGENTS.md](AGENTS.md)が所有する。

## 検証

```bash
bash tools/validate-agent-directory.sh
bash tools/validate-agent-directory.sh --strict --full
bash tools/validate-agent-directory.sh --full --base main
```

validatorは構造、`AGENTS.md`と`CLAUDE.md`の三層、frontmatter、Project契約、状態、Project docsの境界と
命名、参照上限、サイズ、INDEX、LOG、eval schema、派生cacheの決定的再生成、禁止されたGit追跡を検査する。
`--base`は不変原資料や閉鎖済みlogの変更も検査する。依存関係、CI、GitHub接続を必要としない。

## ローカル正本とGitHubバックアップ

ローカルの作業コピーが唯一の書込可能な稼働正本であり、GitHubは最後に確定したコミットの受動的な
遠隔復旧コピーである。通常タスクはネットワークなしで完結し、GitHub Actions、CI、定期同期、自動commit、
自動pushは使用しない。エージェント1体につきPrivateリポジトリを1つ用意し、公開スケルトンへ実運用データを
pushしない。Single WriterはGitリポジトリ単位であり、同じrepositoryへ同時に書き込む稼働コピーを持たない。
異なるIndependent repositoryは並行して進めてよい。

```bash
# セットアップ（GitHubで空のPrivateリポジトリを作成してから実行する）
git remote rename origin template
git remote add backup git@github.com:<owner>/<private-agent-repository>.git
git config remote.pushDefault backup

# バックアップ（既定はworkspace scope）
bash tools/backup-to-github.sh --dry-run
bash tools/backup-to-github.sh

# root repositoryだけの部分結果
bash tools/backup-to-github.sh --root-only --dry-run
bash tools/backup-to-github.sh --root-only
```

利用者がバックアップ、マシン移行、復旧点作成、チェックポイント保存を明示した場合だけ実行する。通常タスクの
完了条件ではない。前提条件を満たさなければ何も変更せず停止する。

| scope | 検査範囲 | 成功出力 |
|---|---|---|
| 既定（workspace） | root push前に全Independent repositoryを監査。Independent remoteへはpushしない | `WORKSPACE_BACKUP_OK` |
| `--root-only` | root repositoryだけ。Independentのnetwork、dirty、unpushは検査しない部分結果 | `ROOT_BACKUP_OK` |

停止条件、divergence時の禁止操作、Single Writer、root `git clean`の禁止、復旧・移行手順、旧Satellite
cloneの移行は[tools/BACKUP.md](tools/BACKUP.md)が所有し、バックアップ・復旧・移行を扱うときだけ読む。

## 正本

| 正本 | 所有する内容 |
|---|---|
| [AGENTS.md](AGENTS.md) | 自己定義、共通判断原則、Route判定、Context Loading、禁止事項、目次 |
| [knowledge/KNOWLEDGE.md](knowledge/KNOWLEDGE.md) | 四層構造、保存先、不変規則、命名、限定取得、INDEX、LOG |
| [skills/SKILLS.md](skills/SKILLS.md) | Skillの選択、frontmatter、Knowledge参照、構造 |
| [projects/AGENTS.md](projects/AGENTS.md) | Project作業共通の着手・実行・完了手順 |
| [projects/PROJECTS.md](projects/PROJECTS.md) | 成果契約、Project docs、Domain Canon、Research昇格、repository mode |
| [projects/LIFECYCLE.md](projects/LIFECYCLE.md) / [projects/RECOVERY.md](projects/RECOVERY.md) | 状態遷移と削除条件 / 目的不一致からの復旧 |
| [evals/EVALS.md](evals/EVALS.md) | 振る舞いevalの契約、ケースschema、fixture、最低条件 |
| [tools/TOOLS.md](tools/TOOLS.md) | Toolの入出力、fallback、相互参照、サイズ予算、規模拡大 |
| [tools/BACKUP.md](tools/BACKUP.md) | バックアップ、復旧、divergence、Single Writer |

## ライセンス

[MIT License](LICENSE)
