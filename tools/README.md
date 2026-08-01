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

token数はモデル差があるためvalidatorのhard failには使わない。実行時の読込予算は`AGENTS.md`が所有する。

## 中規模以降

routeable Knowledge 1,000件またはcatalog 5,000行へ達すると、`build-context-cache.sh`が
`search.sqlite`を自動生成する。SQLite FTS5 trigramが利用可能なら`find-context.sh`が本文検索へ使い、
利用不能なら警告して`rg`/`grep`へfallbackする。閾値はfixture検証時だけ
`AGENT_SQLITE_KNOWLEDGE_THRESHOLD`と`AGENT_SQLITE_CATALOG_THRESHOLD`で差し替えられる。

生成DBはGit管理外で、毎回正本から作る。外部content table、DBだけへの保存、ベクトルDBの既定導入は行わない。
