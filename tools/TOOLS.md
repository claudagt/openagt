# TOOLS.md — 構造保守と限定取得

`tools/`は利用者の成果を作るSkillではなく、このAgent Workspace自体を保守するmeta層である。
固定Toolは6つあり、依存関係を増やさず、入出力、fallback、検証方法を明記する。
macOS標準のbash 3.2で動くことを最低条件とする。`set -u`下では空配列の展開が失敗するため、
配列は件数で守ってから展開する。GNU専用option、associative array、`mapfile`、`readarray`を使わず、
BSD `find`と`sed`で動かす。変更時は`/bin/bash tools/*.sh`でも検証する。

```text
build-context-cache.sh   find-context.sh   append-knowledge-log.sh
backup-to-github.sh      validate-agent-directory.sh
materialize-project-repositories.sh
```

責務は次で固定する。Toolへ判断を持たせず、Agentへ決定的操作を再実装させない。

```text
Tool  = 決定的な操作を安全に実行する
Agent = いつ実行するかを規約に従って判断し、検証と記録まで完結する
Human = 例外と方針変更を決定する
```

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

## 自律実行の標準完了

検証合格後のscoped commitを通常の完了処理とし、可否を利用者へ質問しない。次をすべて満たすとき自動commitする。

- 依頼範囲内の変更であり、変更対象のOwnerが明確である。
- 必須検証が合格している。未検証または不合格の状態を完了commitとして扱わない。
- 秘密情報を含まず、unrelated changeを混ぜていない。
- 一つのsessionが一つのGit rootだけへ書き、作業ツリーから自分の変更を安全に分離できる。
- commitが意味的に一つの作業単位になっている。

commit messageは変更内容と理由が分かる一文を先頭に置く。長い作業を中断するときは、未完了であることと
残件をmessageへ明記したcheckpoint commitを作ってよい。checkpointは完了報告にせず、成果契約の達成としても
扱わない。commit後は`tools/BACKUP.md`のtriggerとpolicyが許す場合だけbackupまたは通常pushへ進む。

次のいずれかでは自動commitせず停止し、`AGENTS.md#人間へ上げる例外`として報告する。

- 秘密情報を含む、または所有者不明の変更と安全に分離できない。
- 同じ行や成果物で別sessionと競合している。
- 不可逆操作を前提とする、または成果契約の変更を含む。
- 何を正本とするか決定できない。

## 自己修復と停止

安全で可逆な内部エラーは、最初の失敗で利用者へ判断を返さず、原因を調査して自律修正し再検証する。対象は
サイズ超過、参照切れ、lintとformatの失敗、stale cache、validatorが示した構造違反、生成物の再生成漏れ、
Toolへの決定的な入力不備、自分の変更が壊したtestである。

同じ原因への修正再試行は3回までとし、到達したら停止する。同じ修正の反復と無限ループを行わない。
次のいずれかは試行回数によらず停止する。

- 修正方法が成果契約、目的、優先順位を変える。
- 解決策が複数あり、選択で成果や安全性が変わる。
- 不可逆操作または外部状態の変更が必要である。
- 所有者不明の変更へ触れる必要がある。
- 二つの正本が矛盾し、どちらを正本とするか一意に決まらない。

正本同士が矛盾した場合は片方を推測で書き換えない。両方のpath、矛盾する記述、`AGENTS.md#参照順序`上の
上位、影響範囲を示し、推奨する一つの解決を添えて停止する。

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

Embedded Projectはfilesystem全件findではなくroot indexの`projects/*/PROJECT.md`から決める。
Independent Projectは`projects/REPOSITORIES.md`のentryから列挙し、working treeの未commit内容ではなく
`git -C projects/<name> show <revision>:PROJECT.md`で採用revisionのfrontmatterを読み、
name、description、status、mode、pathだけをcatalogへ登録する。content_hashへ採用revisionを混ぜる。

登録済みの`projects/<name>/`はdirectory全体をpruneする。Independent Project本体をmanifest、
fingerprint、SQLite bodyのいずれからも除外し、root側の`projects/REPOSITORIES.md`と`projects/.gitignore`は
manifestへ入れる。root fingerprintは採用revisionが変わったときだけ変わる。`find-context.sh`はcatalogと
routeable正本だけを検索し、fallbackでもIndependent Project配下をrecursive grepしない。

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

- 入力: `--type`、`--target`、`--summary`、任意の`--date YYYY-MM-DD`。`AGENT_DIRECTORY_ROOT`で対象rootを差し替える。
- 出力: `APPENDED: <date> <target>`、ローテーション時は`ROTATED: <path> (<記録数>, <byte数>)`を追加で出す。
- 追記先は`knowledge/wiki/LOG.md`だけとし、1,000記録または128KiBで`logs/YYYY-QN[-NN].md`へ閉じ、
  現在のLOGをヘッダーだけへ戻す。閉鎖済みlogは以後変更しない。
- 記録の種別と意味的な運用規則は`knowledge/KNOWLEDGE.md#LOG`が所有する。
- 検証: `AGENT_DIRECTORY_ROOT`を使った隔離fixtureで閾値挙動を再現できる。

## backup-to-github.sh

```bash
bash tools/backup-to-github.sh
bash tools/backup-to-github.sh --dry-run
bash tools/backup-to-github.sh --root-only
bash tools/backup-to-github.sh --remote backup --branch main --dry-run
```

meta層のToolであり、いつ実行するかはAgentが規約に従って判断する。有効なPrivate backup remoteと自動backup
方針が設定済みなら、検証済みcommitの後のようなタスク境界で確認を求めず実行する。trigger、未設定・失敗時の
扱い、remote分類は`tools/BACKUP.md`が所有する。ファイル1件ごとにpushする設計にはしない。

- 入力: `--remote`（既定`backup`）、`--branch`（既定`main`）、`--dry-run`、`--root-only`。
  `AGENT_DIRECTORY_ROOT`で対象root、`AGENT_BACKUP_MAX_BLOB_BYTES`でblob上限を差し替えられる。
  上限の差し替えは隔離fixture検証だけで使う。
- 出力: 成功とdry-runは1行の機械可読な結果をstdoutへ、停止は`BACKUP_BLOCKED reason=<reason>`をstderrへ
  出して終了コードを非0にする。scope、結果文字列、前提条件、停止reasonの一覧、divergence時の禁止操作、
  Independent監査項目、Single Writer、root `git clean`の禁止、復旧・移行手順は`tools/BACKUP.md`が所有し、
  扱うときだけ読む。
- root backup remoteへpushする唯一の標準経路であり、pushは`HEAD:refs/heads/<branch>`の明示refspecによる
  通常のfast-forward pushだけとする。Independent remoteへは決してpushしない。コミットを作らず、
  `--dry-run`はremoteへ一切書き込まない。
- 検証: 一時ディレクトリのローカルbare remoteを使う隔離fixtureで、実GitHub接続なしに再現できる。

## materialize-project-repositories.sh

```bash
bash tools/materialize-project-repositories.sh --all
bash tools/materialize-project-repositories.sh --project <name>
bash tools/materialize-project-repositories.sh --all --check
```

`projects/REPOSITORIES.md`の登録と採用revisionから、Project root`projects/<name>/`へ通常cloneを再現する。
復旧、マシン移行、partial materializationの解消で使う。

- 入力: `--all`または`--project <name>`のいずれか一つ、任意の`--check`。`AGENT_DIRECTORY_ROOT`で
  隔離fixture rootへ差し替えられる。Independent Projectの列挙は`projects/REPOSITORIES.md`だけを
  正本とし、`PROJECT.md`のfrontmatterを走査しない。
  `AGENT_ALLOW_LOCAL_REPOSITORY_URL=true`はローカルbare remoteを許す隔離fixture専用の上書きであり、
  通常運用では設定しない。
- 出力: 成功`MATERIALIZATION_OK total=<n> cloned=<n> verified=<n>`をstdoutへ1行。
  停止時は`MATERIALIZATION_BLOCKED reason=<reason> project=<name>`をstderrへ出し、終了コードを非0にする。
- 動作: registryとignore projectionの整合を先に検査し、targetが無いときだけ`--no-checkout`でcloneして
  採用revisionをdetached checkoutする。branch tipへ勝手に進めない。cloneの直後にtoplevel、`origin`、
  HEAD、採用commitの`PROJECT.md`と`STATE.md`を検査する。`--check`はcloneせず整合だけを検査する。
- 既存targetをreset、clean、stash、merge、rebaseしない。dirtyなら停止する。non-emptyな非repoを上書きせず、
  target・parent・`.git`のsymlinkと`.git` fileを拒否する。認証情報を保存せず、絶対pathを正本へ書かない。
- 主な停止reason: `not-agent-directory-root`、`invalid-project`、`invalid-registry`、
  `invalid-ignore-projection`、`target-path-symlink`、`target-not-empty`、
  `repository-gitfile-unsupported`、`repository-toplevel-mismatch`、`repository-origin-mismatch`、
  `repository-dirty`、`repository-staged`、`repository-untracked`、`repository-stash-present`、
  `repository-head-not-adopted`、`repository-contract-missing`、`revision-unavailable`、
  `authentication-required`、`remote-unreachable`。`--check`で未materializeを検出した場合は
  `missing-independent-repository`とし、backup Toolと語彙を揃える。
- 既存cloneでは採用revisionの存在だけでなく、HEADが採用SHAと一致することまで検査する。
  branch上で作業してそのtipを採用する運用も許すため、detached HEADは要求しない。
- 検証: 一時ディレクトリのローカルbare remoteを使う隔離fixtureで、fresh clone、採用SHAのdetached checkout、
  `--check`の冪等性、dirty targetの停止を実GitHub接続なしに再現できる。

## validate-agent-directory.sh

```bash
bash tools/validate-agent-directory.sh
bash tools/validate-agent-directory.sh --strict --full
bash tools/validate-agent-directory.sh --full --base main
```

- 通常: 必須構造、`AGENTS.md`/`CLAUDE.md`の階層、metadata、Project契約、STATE、Project docs境界、
  Independentのattachmentとroot ownership、サイズ、INDEX/LOG、eval schema、cache再生成を検査
- `--strict`: 導入後に残してはいけない自己定義・Skillプレースホルダーも失敗にする
- `--full`: 全参照、全Knowledge/Skill/Project、context Tool fixtureを検査
- `--base <ref>`: Git差分から`knowledge/raw/`、閉鎖済みlog、Project物理移動の禁止を検査
- 終了コード0と`PASS: agent-directory structure is valid`が合格条件である。

機械検査する境界には少なくとも次が含まれる。

- `knowledge/research/`と旧領域`README.md`が存在せず、`knowledge/raw/`の二領域がimmutableである。
- `knowledge/KNOWLEDGE.md#命名規則`のとおり固定Wikiが大文字名、利用者ページが小文字ケバブケースであり、
  旧小文字パスがGit indexにも実ファイル名にも戻っていない。
- frontmatterを欠く正本があってもcache生成が停止せず、対象パスと欠落キーを警告して候補から外す。
- `PROJECT.md`に`repository_mode`、`repository_url`、`repository_reason`、`repository_default_branch`が
  残らず、`STATE.md`に`## Repository State`が残らない。
- `projects/REPOSITORIES.md`のheading、name、昇順、field数、reason enum、safe URL、40文字SHA、
  Project pathとの対応が成立し、`projects/.gitignore`のmanaged blockと登録集合が完全一致する。
- Independent Projectは`projects/<name>/`にsymlinkでない実cloneを持ち、`.git`が実directoryで、
  toplevelと`remote.origin.url`とHEADが登録と完全一致し、`PROJECT.md`と`STATE.md`を自ら持つ。
- root indexが登録済みProject root配下もmode 160000のgitlinkも持たず、Embedded Projectとregistry、
  ignore projection自身がignoreされていない。旧`projects/<name>/repository/`は追跡でも実体でも停止させる。
- 登録済みの`projects/<name>/.git/`以外のnested `.git`は、directoryでもfileでも停止させる。

AGENTS三層とProject docsの完全な構造規則は`projects/PROJECTS.md`が所有する。validatorはその境界と
サイズだけを固定し、`docs/`より下のフォルダ名と見出し構成はProjectが決める。

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
| `knowledge/wiki/INDEX.md` | 8KiB・50項目 |
| active Wiki | 64KiB。24KiB超はRetrieval Map必須 |
| `knowledge/wiki/LOG.md` | 128KiB・1,000記録 |
| `tools/BACKUP.md` | 20KiB |

token数はモデル差があるためvalidatorのhard failには使わない。実行時の読込予算は`AGENTS.md`が所有する。

### 超過時の標準処理

ルート`AGENTS.md`、Project個別`AGENTS.md`、Domain Canonのような短い入口が上限を超えたら、圧縮・分割・
上限拡大のどれを選ぶかを利用者へ質問せず、次の順で処理する。

1. 同じ意味の重複記述を除去する。
2. 詳細を既存の正しい所有先へ移す。
3. 条件付きロードへ変更する。
4. 残る詳細を責務単位で詳細文書へ分割する。
5. 元の正本には現在有効な原則、境界、Route、参照だけを残す。
6. 移動前後で意味、禁止事項、例外、参照が失われていないことを確認する。
7. 参照切れを検査し、validatorを実行し、commitして結果を報告する。

「圧縮」は曖昧な要約への置換ではなく、意味を保持した重複除去、責務移管、段階的開示である。既定では上限を
拡大しない。拡大を検討できるのは、既存の責務分離では収容できず、そのファイル自身が情報を所有すべき明確な
根拠があり、構造全体の変更として正当化できる場合だけであり、validatorを通すためだけの拡大は禁止する。
hard limit未満のwarningは委譲余地の確認を促す助言であり、閾値を動かして消さない。

原資料、Knowledge、研究証拠、Project成果物は、大きいことだけを理由に圧縮、要約置換、削除しない。入口
ファイルの肥大化と保存すべき情報量の増加は別問題として扱い、前者は責務移管、後者は限定取得で解く。
非破壊的な取り扱いは`knowledge/KNOWLEDGE.md`が所有する。

## 中規模以降

routeable Knowledge 1,000件またはcatalog 5,000行へ達すると、`build-context-cache.sh`が
`search.sqlite`を自動生成する。SQLite FTS5 trigramが利用可能なら`find-context.sh`が本文検索へ使い、
利用不能なら警告して`rg`/`grep`へfallbackする。閾値はfixture検証時だけ
`AGENT_SQLITE_KNOWLEDGE_THRESHOLD`と`AGENT_SQLITE_CATALOG_THRESHOLD`で差し替えられる。

生成DBはGit管理外で、毎回正本から作る。外部content table、DBだけへの保存、ベクトルDBの既定導入は行わない。
