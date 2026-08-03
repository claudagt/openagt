# tools/ — 構造保守と限定取得

`tools/`は利用者の成果を作るSkillではなく、このディレクトリ自体を保守するmeta層である。
固定Toolは依存関係を増やさず、入出力、fallback、検証方法を明記する。

## 正本と派生物

Markdown、原資料、Project入出力、eval、Toolコードが正本である。`.agent-cache/`はGit管理外の派生物で、
削除して正本から再生成できる。cacheだけに情報を保存せず、正本や成果物からcacheを恒久参照しない。

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
raw/researchはmanifestへ登録するが、通常の意味検索catalogへ直接入れない。
`--check-routing`はraw/researchを走査せずrouteable正本だけでcatalogの鮮度を確認し、検索ごとの全正本走査を避ける。

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
- cacheが欠損・staleなら一度再生成する。
- metadataで見つからない場合は`rg`、なければ`grep`でrouteable正本の本文を検索する。
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
  `.DS_Store`が未追跡、submodule・Git LFSなし、100MiB以上のobjectなし、remoteがdivergeしていない。
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

## validate-agent-directory.sh

```bash
bash tools/validate-agent-directory.sh
bash tools/validate-agent-directory.sh --strict --full
bash tools/validate-agent-directory.sh --full --base main
```

- 通常: 必須構造、metadata、Project契約、STATE、サイズ、index/log、eval schema、cache再生成を検査
- `--strict`: 導入後に残してはいけない自己定義・Skillプレースホルダーも失敗にする
- `--full`: 全参照、全Knowledge/Skill/Project、context Tool fixtureを検査
- `--base <ref>`: Git差分からraw/research、閉鎖済みlog、Project物理移動の禁止を検査

終了コード0と`PASS: agent-directory structure is valid`が合格条件である。

既定でも`--full`でも、実GitHub接続、`gh` CLI、GitHub API、認証情報、Private可視性照会を必要としない。
backup Toolの検査は、静的な禁止操作検査と、一時ディレクトリのローカルbare remoteを使う隔離fixtureだけで行う。
Private可視性はセットアップ契約であり、利用者が確認する。

## サイズ予算

モデル非依存で安定するUTF-8 byteをhard limitに使う。行数と見出し数は可読性警告だけに使う。

| 対象 | hard limit |
|---|---:|
| `AGENTS.md` | 12KiB |
| `knowledge/KNOWLEDGE.md` | 20KiB |
| `skills/README.md` | 12KiB |
| `projects/README.md` | 20KiB |
| `STATE.md` | 8KiB |
| `PROJECT.md` / `SKILL.md` | 20KiB |
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
