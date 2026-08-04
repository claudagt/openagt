# TOOLS.md — 構造保守と限定取得

`tools/`は利用者の成果を作るSkillではなく、このディレクトリ自体を保守するmeta層である。
固定Toolは依存関係を増やさず、入出力、fallback、検証方法を明記する。

## 正本と派生物

Markdown、原資料、Project入出力、eval、Toolコードが正本である。`.agent-cache/`はGit管理外の派生物で、
削除して正本から再生成できる。cacheだけに情報を保存せず、正本や成果物からcacheを恒久参照せず、
Git追跡対象にもしない。

## 相互参照

恒久参照は`<repository-relative-path>#<target>`を使う。

- 見出し: `projects/AGENTS.md#着手`
- Project条件: `projects/example/PROJECT.md#PC-01`
- frontmatter: `projects/example/PROJECT.md#status`

追加でずれる行番号は恒久参照に使わない。同じProject内でも対象ファイル名を省略しない。

## 一時作業と固定化

- 一時コードと中間ファイルは`.tmp/`に置き、正式処理から参照せず、完了時に削除する。
- 同じ目的で2回目に使う不安定なコードは所有先の`candidates/`、3回目に使う前に固定化を判断する。
- 固定コードはProjectまたはSkillの`scripts/`、構造保守はこの`tools/`が所有し、実行方法と検証方法を持つ。
- 外部共有、本番、金銭、権限、機密へ影響する処理は初回から固定コード相当の品質を要求する。
- 全件監査でも全件を同時に入力しない。バッチで検査し、`.tmp/`の集約結果と必要な正本だけを次段階へ渡す。

## build-context-cache.sh

```bash
bash tools/build-context-cache.sh
bash tools/build-context-cache.sh --check
bash tools/build-context-cache.sh --check-routing
```

生成物:

- `catalog.tsv` — routeableなKnowledge、Skill、Project、meta規約の最小metadata
- `manifest.tsv` — 全正本ファイルのpath、種別、byte、content hash、routeable、不変属性
- `cache.meta` — schema、generator hash、正本fingerprint、件数、検索backend
- `search.sqlite` — 規模閾値到達後だけ自動生成するFTS5 trigram派生索引

catalogはpath順で決定的に生成し、name、aliases、description、status、pathなど候補選択に必要な項目だけを持つ。
`--check-routing`は不変原資料を走査せずrouteable正本だけでcatalogの鮮度を確認し、検索ごとの全正本走査を避ける。

manifestは少なくとも次を区別する。

| path | kind | immutable |
|---|---|---|
| `knowledge/raw/internal/**` | `internal-record` | true |
| `knowledge/raw/external/**` | `external-source` | true |
| `knowledge/wiki/logs/**` | `closed-log` | true |
| `knowledge/wiki/sources/**`、`knowledge/wiki/topics/**` | `knowledge` | false |
| `projects/*/ARCHITECTURE.md` | `project-architecture` | false |
| `projects/*/docs/**` | `project-doc` | false |

Project選択の単位は`PROJECT.md`である。`ARCHITECTURE.md`とProject docsはmanifestでは分類するが、
routeable catalogへ入れず、通常検索結果へ全件投入しない。対象Projectを確定した後、個別`AGENTS.md`の
Docs RouteからDomain Canonへ進む。`knowledge/raw/`配下もmanifestへ登録するが意味検索catalogへ入れない。

環境変数`AGENT_DIRECTORY_ROOT`で検査対象root、`AGENT_CACHE_DIR`で出力先を差し替えられる。
fixtureや隔離検証以外では既定値を使う。

## find-context.sh

```bash
tools/find-context.sh --route knowledge --limit 5 -- "検索語"
tools/find-context.sh --route project --include-inactive -- "監査対象"
```

- routeは`knowledge | skill | project | meta`。
- limitは1〜5。通常はactiveだけを返す。
- name完全一致、alias完全一致、metadata部分一致、本文一致の順に候補を決め、pathで同順位を固定する。
- cacheが欠損・stale・破損なら一度だけ再生成する。規模閾値ではSQLite索引も自動生成する。
- metadataで見つからない場合は`rg`、なければ`grep`/`find`でrouteable正本の本文を直接検索し、
  いずれのfallbackでも候補を最大5件に保つ。
- 出力は最大5件のmetadataだけで、catalog全文や本文を出力しない。
- 結果は候補であり、判断前にpathの正本を読む。

## append-knowledge-log.sh

```bash
tools/append-knowledge-log.sh --type ingest --target knowledge/wiki/topics/example.md --summary "変更内容"
```

Knowledge変更履歴はこのToolだけで追記する。追記後に1,000記録または128KiBへ達すると、
`logs/YYYY-QN[-NN].md`へ自動ローテーションし、現在の`log.md`をヘッダーだけに戻す。
閉鎖済みlogは以後変更しない。`AGENT_DIRECTORY_ROOT`を使った隔離fixtureでも同じ挙動を検証できる。

## backup-to-github.sh

```bash
bash tools/backup-to-github.sh
bash tools/backup-to-github.sh --remote backup --branch main
bash tools/backup-to-github.sh --remote backup --branch main --dry-run
```

meta層のToolであり、通常のKnowledge、Skill、Project作業から自動実行しない。利用者がバックアップ、
マシン移行、破壊的変更前の復旧点作成、チェックポイント保存を明示した場合だけ実行する。
規約と手順は[BACKUP.md](BACKUP.md)が所有し、バックアップ・復旧・移行時だけ読む。

- 入力: `--remote`（既定`backup`）、`--branch`（既定`main`）、`--dry-run`。
  `AGENT_DIRECTORY_ROOT`で対象root、`AGENT_BACKUP_MAX_BLOB_BYTES`でblob上限を差し替えられる。
  上限の差し替えは隔離fixture検証だけで使う。
- 前提条件: リポジトリroot、非detached HEAD、branch一致、remote設定済み、index・作業ツリー・
  未追跡ファイルが空、stashなし、branch外のローカルcommitなし、`.tmp`/`.agent-cache`/`.env`実値/
  `.DS_Store`が未追跡、ignore済みを含むnested `.git`なし、submodule・Git LFSなし、100MiB以上のobjectなし、
  Satelliteの宣言・Hub内容・採用SHAが検証済み、Hub remoteがdivergeしていない。
- 出力: 成功`BACKUP_OK remote=<name> branch=<name> sha=<40文字SHA>`、
  dry-run成功`BACKUP_READY ...`をstdoutへ1行。停止時は`BACKUP_BLOCKED reason=<reason>`をstderrへ出し、
  終了コードを非0にする。補足はstderrの`DETAIL:`行に出す。
- 失敗条件のreasonは`BACKUP.md#backup Tool`に一覧を持つ。
- remoteへpushする唯一の標準経路であり、pushは`HEAD:refs/heads/<branch>`の明示refspecによる
  通常のfast-forward pushだけとする。push後に`git ls-remote`で一致を再確認する。
- コミットを作らない。`git add`、`git commit`、`git stash push`を行わない。
- remote divergenceを修正しない。検出時は何も変更せず停止し、remote SHAとlocal SHAを報告する。
- force push、force-with-lease、mirror push、prune、remote branch削除、一括pushを行わない。
- `--dry-run`はremoteへ一切書き込まない。
- Satelliteのremoteはread-onlyで検証し、`STATE.md`の採用SHAを隔離一時repoへ取得できない場合は停止する。
  `BACKUP_OK`はHubの成功だけを表す。

## validate-agent-directory.sh

```bash
bash tools/validate-agent-directory.sh
bash tools/validate-agent-directory.sh --strict --full
bash tools/validate-agent-directory.sh --full --base main
```

- 通常: 必須構造、`AGENTS.md`/`CLAUDE.md`の階層、metadata、Project契約、STATE、Project docs境界、
  サイズ、index/log、eval schema、cache再生成を検査
- `--strict`: 導入後に残してはいけない自己定義・Skillプレースホルダーも失敗にする
- `--full`: 全参照、全Knowledge/Skill/Project、context Tool fixtureを検査
- `--base <ref>`: Git差分から`knowledge/raw/`、閉鎖済みlog、Project物理移動の禁止を検査

構造境界として少なくとも次を機械検査する。

- `knowledge/research/`が存在せず、`knowledge/raw/internal/`と`knowledge/raw/external/`が存在し、
  どちらもimmutableとして扱われる。
- 領域正本が`skills/SKILLS.md`、`projects/PROJECTS.md`、`evals/EVALS.md`、`tools/TOOLS.md`であり、
  対応する旧`README.md`が存在しない。ルート`README.md`は外部向け入口として存在する。
- `docs/README.md`が存在しない。Embedded Projectの`docs/`直下Markdownが大文字Domain Canon形式である。
- `docs/`または`ARCHITECTURE.md`を持つEmbedded Projectが個別`AGENTS.md`と`CLAUDE.md`を持ち、
  `CLAUDE.md`が`@AGENTS.md`だけである。
- 個別`AGENTS.md`が`PROJECT.md`と`STATE.md`を正本として参照し、存在する`ARCHITECTURE.md`と
  各Domain Canonを参照し、`docs/**`の一括読込を命じない。
- Satellite Hubが`PROJECT.md`と`STATE.md`以外を持たない。
- `projects/_template/`が`docs/`、`ARCHITECTURE.md`、`AGENTS.md`を持たない。

`docs/`より下のフォルダ名と見出し構成はProjectが決める。validatorは境界とサイズだけを固定し、
下位構造を固定しない。終了コード0と`PASS: agent-directory structure is valid`が合格条件である。

既定でも`--full`でも、実GitHub接続、`gh` CLI、GitHub API、認証情報、Private可視性照会を必要としない。
backup Toolの検査は、静的な禁止操作検査と、一時ディレクトリのローカルbare remoteを使う隔離fixtureだけで行う。
Private可視性はセットアップ契約であり、利用者が確認する。

## サイズ予算

モデル非依存で安定するUTF-8 byteをhard limitに使う。行数と見出し数は可読性警告だけに使う。

| 対象 | hard limit |
|---|---:|
| `AGENTS.md`（ルート） | 8KiB。4KiB超はwarning |
| `projects/AGENTS.md` | 2KiB |
| `projects/<name>/AGENTS.md` | 2KiB |
| `knowledge/KNOWLEDGE.md` | 20KiB |
| `skills/SKILLS.md` | 12KiB |
| `projects/PROJECTS.md` | 24KiB |
| `evals/EVALS.md` | 24KiB |
| `tools/TOOLS.md` | 20KiB |
| `STATE.md` | 8KiB |
| `PROJECT.md` / `SKILL.md` | 20KiB |
| `projects/<name>/ARCHITECTURE.md` | 24KiB |
| `projects/<name>/docs/<DOMAIN>.md` | 24KiB |
| `knowledge/wiki/index.md` | 8KiB・50項目 |
| active Wiki | 64KiB。24KiB超はRetrieval Map必須 |
| `knowledge/wiki/log.md` | 128KiB・1,000記録 |
| `tools/BACKUP.md` | 20KiB |

token数はモデル差があるためvalidatorのhard failには使わない。実行時の読込予算は`AGENTS.md`が所有する。

## 中規模以降

routeable Knowledge 1,000件またはcatalog 5,000行へ達すると、`build-context-cache.sh`が
`search.sqlite`を自動生成する。SQLite FTS5 trigramが利用可能なら`find-context.sh`が本文検索へ使い、
利用不能なら警告して`rg`/`grep`へfallbackする。閾値はfixture検証時だけ
`AGENT_SQLITE_KNOWLEDGE_THRESHOLD`と`AGENT_SQLITE_CATALOG_THRESHOLD`で差し替えられる。

生成DBはGit管理外で、毎回正本から作る。外部content table、DBだけへの保存、ベクトルDBの既定導入は行わない。
