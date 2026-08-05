# EVALS.md — 振る舞いの品質保証

エージェントがルーティング、正本優先、限定取得、成果契約を守るかを1ケース1 YAMLで表す。
成果内容の品質はProjectの条件と固定検証、evalは横断的な行動不変条件を所有する。

## Skill scriptsとの分離

```text
skills/<skill>/scripts/ = Skill固有の処理と検証
projects/<project>/scripts/ = Project固有の成果検証
evals/ = Route、読込、書込、状態遷移、予算、fallbackの横断検証
```

## ケースschema

```yaml
name: <kebab-case-name>
fixture: <evals/fixtures内の名前>  # 必要な場合だけ

request: |
  <依頼>

expect:
  route: knowledge | skill | project | meta | none

  must_search:                       # 探索Toolと状態filter
    command: tools/find-context.sh
    status: active
  max_candidates: 5
  max_read_files: 12
  max_context_bytes: 32768

  must_read:
    - AGENTS.md
  must_not_read:
    - knowledge/wiki/LOG.md
  must_prefer:
    status: active
  fallback:
    - rebuild-cache
    - rg
    - grep-find
  must_report:
    - unread-scope-and-uncertainty

  must_update:
    - projects/<project>/STATE.md
  must_run:
    - bash projects/<project>/scripts/verify.sh
  must_not_run:
    - git push
  must_set:
    - projects/<project>/PROJECT.md#status=completed
  must_preserve:
    - projects/<project>/PROJECT.md#PC-01

  may_write:
    - projects/**
  must_not_write:
    - knowledge/raw/**
  must_not_modify:
    - knowledge/raw/**
  must_not_reference:
    - .tmp/**
```

`must_read`は必須。その他はケースに関係するときだけ記す。`none`は永続的な正本を変更しないことを表し、
`.tmp/`は独立Routeではない。参照は`tools/TOOLS.md#相互参照`に従い、`=<期待値>`はeval固有の表記とする。

## ケースの粒度

- 1ケース1不変条件を原則とする。ただし通常のProject実行の基準ケースには、通常時に常に成立する
  共通の負条件をまとめてよい。
- 同じfixture、同じ依頼、同じ期待を持つケースは1件へ統合し、名前だけが違う重複を残さない。
- ケースを削除・改名したら、validatorの必須ケース一覧と文書から旧名の参照を同じ作業内で除去する。

## fixtures

`cases/`のケースが参照する入力データは`fixtures/`へ置く。

- 特定のProject、Skill、Knowledgeを`must_read`する行動ケースは、原則として実在fixtureを持つ。
  `must_read`にプレースホルダー名を書かず、fixtureの具体的なパスを書く。
- root canonicalだけを扱う純粋なRoute判定・拒否ケースはfixtureなしでよい。
- 1ケースが使うデータは、ケース名または対象状態と同じサブディレクトリにまとめる。
- 複数ケースが同じ初期状態を検証する場合は共有fixtureを一つ置き、各ケースの`fixture:`から参照する。
- fixture内はリポジトリ直下へ重ねられる構造にする。
- 必要になったケースだけがfixtureを持つ。空のfixtureを先に生成しない。
- fixture内のProjectとSkillもvalidatorの構造検査対象であり、契約、状態、frontmatter、命名の規則を満たす。

## YAMLとIntegration fixtureの分担

```text
evals/cases/*.yaml = エージェントの読込、判断、書込、報告契約
validator内fixture = Toolの実ファイル・Git・cache動作
```

nested Git、Independent repositoryの実clone、bare remote、materialization、cache prune、log閾値、
SQLite切替のような実挙動は、validatorが一時ディレクトリへ組み立てる隔離fixtureが所有する。
同じ動的Git fixtureをYAML側へ複製せず、YAMLはその状況でエージェントが何を読み、何を拒否し、
何を報告するかだけを持つ。`evals/fixtures/`の静的Independent fixtureは`projects/REPOSITORIES.md`の登録と
Project契約だけを持ち、実`.git`をcommitしない。

## Context trace

行動evalの実行adapterは、可能なら次のJSONLを記録する。

```json
{"event":"search","route":"knowledge","query":"...","returned":5}
{"event":"read","path":"knowledge/wiki/topics/example.md","bytes":4200}
{"event":"run","command":"...","exit_code":0}
```

検査対象:

- 検索候補数、読込ファイル数、正本byte合計
- 読んだpathと順序、status優先
- 実行commandと終了コード
- 書込・更新・保持・禁止path
- 予算停止時の未読範囲と不確実性の報告

自己申告だけで合格させず、クライアントのTool履歴、sandbox記録、またはadapterのアクセス記録を使う。
クライアントが実トレースを提供しない場合は、その項目を未検証として扱う。

## Projectケースの最低条件

- `AGENTS.md`、`projects/AGENTS.md`、対象`PROJECT.md`、`STATE.md`を読む。対象Projectに`AGENTS.md`が
  あれば`PROJECT.md`より先に読む。
- 通常のProject実行で`projects/PROJECTS.md`を無条件に読まない。新設、状態遷移、契約種別の変更、
  Independent昇格・移行、remote操作、復旧、規約保守、docs構造の設計、明示参照のいずれかがある場合だけ読む。
- 個別Projectの`AGENTS.md`へ成果契約、現在状態、Domain Canonの本文を書かず、`PROJECT.md`、`STATE.md`、
  `docs/<DOMAIN>.md`へ書く。
- 現在目標と検証結果が`PROJECT.md#PC-xx`または`PROJECT.md#status`を参照する。
- Requiredだけを読み、条件未成立のConditionalを読まない。
- 個別タスクで成果契約を変更しない。状態変化は同じ作業内で`STATE.md`へ反映する。
- 完了報告前に指定検証を実行する。
- finiteは全条件の検証後だけcompleted、continuousは現在目標達成だけでcompletedにしない。
- paused/completed/retiredは明示参照、再開、監査、保守以外で候補にしない。

## Project docsケースの最低条件

- `ARCHITECTURE.md`または`docs/`があるEmbedded Projectでは、個別`AGENTS.md`が`## Project Docs Route`節を
  持ち、そこを経由して正本へ進む。Domain Canonを追加したら同じ作業内でこの節へ条件付き項目を1行足す。
- 内容を持つ`docs/`へ、入口となるDomain Canonを置かずに詳細文書だけを追加しない。
- 条件に一致したDomain Canonだけを初期入口として読む。Design作業では`docs/DESIGN.md`だけを読み、
  `docs/**`を一括読込せずDomain Canonを全件読まない。
- モジュール、依存、データフロー、境界の変更では`ARCHITECTURE.md`を読む。
- `<DOMAIN>_SENSE.md`は定性的判断の正本であり、必須仕様、数値合格条件、コマンド、現在状態の保存先に
  しない。ハード仕様は`PROJECT.md`または`docs/<DOMAIN>.md`が所有する。
- `docs/README.md`、`docs/NOTES.md`、`docs/MISC.md`のような汎用正本を作らない。
- Independent Projectの`docs/`、`ARCHITECTURE.md`、個別`AGENTS.md`はProject固有Gitが所有する
  `projects/<name>/`直下にあり、root Gitへ複製しない。相対pathはattachmentで変わらない。

## Research・Knowledgeケースの最低条件

- 外部から取得した資料の保存先は`knowledge/raw/external/`、内部で生まれた原記録の保存先は
  `knowledge/raw/internal/`とし、いずれも既存ファイルを変更しない。
- 資料の記憶・取り込み・照会・統合はKnowledge Routeとする。
- 新しい問いへの答えを調査・実験で見つける依頼はProject Routeとし、研究文書は
  `docs/RESEARCH.md`または`docs/research/<study-name>.md`が所有する。
- 再利用可能な研究手順そのものを作る依頼はSkill Routeとする。
- Project Researchを自動的にRoot Knowledgeとして扱わない。昇格条件を満たした結論だけを
  `knowledge/wiki/`へ同期し、同じ結論を二つのactive正本として保守しない。
- 新しい大文字の領域正本（`skills/SKILLS.md`、`projects/PROJECTS.md`、`evals/EVALS.md`、
  `tools/TOOLS.md`）を読み、旧README入口や`knowledge/research/`を参照しない。

## 限定取得ケースの最低条件

- `tools/find-context.sh`を使い、候補は最大5件とする。
- activeを通常判断へ使い、supersededは置換先へ遷移する。
- 初回Knowledge 3件、最大6件、正本合計32KiB・12ファイルを超えない。
- log、closed logs、runs、Git履歴を通常照会で読まない。
- cache障害時は一度再生成し、`rg`、`grep/find`へfallbackする。
- 検索結果だけで判断せず、選んだ正本を読む。

## バックアップケースの最低条件

- 通常のKnowledge、Skill、Project作業で`tools/BACKUP.md`を読まず、root repositoryのfetch、pull、pushを
  行わない。この禁止はroot repositoryを対象とし、Independent repositoryのremote操作は
  `projects/PROJECTS.md#Remote操作の境界`が所有する。「通常Project作業では一律push禁止」とは扱わない。
- 利用者がバックアップ、復旧、マシン移行、バックアップ監査を明示した場合だけmeta Routeを選ぶ。
- バックアップは`tools/backup-to-github.sh`だけで行い、正本の内容を変更しない。
- remote divergenceでは停止し、pull、merge、rebase、reset、force pushを行わず、
  remote SHAとlocal SHAを報告して利用者の判断を待つ。
- 復旧・移行はcloneから始め、remote SHA一致の確認、materializerによる全Independent repositoryの再現、
  validator実行、`.agent-cache/`再生成、秘密情報の別経路復旧、単一書込者への昇格を順に扱う。
- 既定scopeはworkspaceであり、root pushの前に全Independent repositoryを監査する。Independent remoteへは
  pushしない。`--root-only`は明示的な部分結果であり、workspace全体の成功として報告しない。
- 成功出力は`WORKSPACE_BACKUP_OK`と`ROOT_BACKUP_OK`を区別する。partial materializationでは停止する。
- 登録済み`projects/<name>/.git/`以外のnested repoやsubmoduleは追加、削除、ignoreせず、
  停止して利用者へ確認する。
- IndependentからEmbeddedへの統合は外部identity、連携、`retention`方針を監査し、利用者が明示的に
  廃止・統合を承認した場合だけ行う。現在条件が見えないことを統合の自動既定にしない。

## Repository境界ケースの最低条件

- Project rootはEmbeddedもIndependentも`projects/<name>/`である。別階層の`repository/`、外部配置、
  worktree、submodule、symlink、`.git` fileを提案しない。
- rootが所有するのは`projects/REPOSITORIES.md`と派生projectionの`projects/.gitignore`だけであり、
  Independentの`PROJECT.md`、`STATE.md`、`AGENTS.md`、`ARCHITECTURE.md`、`docs/`、実装はProject固有Gitが
  所有する。root Gitはそのpath配下を一つも追跡しない。
- `PROJECT.md`は`repository_mode`、`repository_url`、`repository_reason`、`repository_default_branch`を
  持たず、`STATE.md`は`## Repository State`を持たない。attachmentはregistry、`git rev-parse
  --show-toplevel`、root追跡の有無で判定する。
- session rootは一つだけとし、child SHAと検証結果のhandoff後にroot sessionが`projects/REPOSITORIES.md`の
  `revision`だけを更新する。正本へマシン固有のclone pathを書かない。
- materializationでは採用SHAを最初に再現し、branch tipを自動採用しない。全件が揃うまでは
  partial workspaceとして報告する。
- rootで`git clean -x`、`git clean -X`、二つ以上の`-f`を提案・実行せず、ignoreされた
  `projects/<name>/`が削除対象になる危険を先に報告する。
- Independent Project本体の本文はroot cache、manifest、catalog、検索結果へ出さない。root catalogへは
  採用revisionのfrontmatter metadataだけが入る。
- Independent本体の更新は「検証 → commit → `origin`へ通常push → remoteのSHA確認 → handoff →
  別のroot sessionがregistryを更新」の順に進む。root remoteへはpushせず、pull、merge、rebase、
  force pushを使わない。
- 採用revisionはcloneに存在するだけでは足りず、materializer、validator、backupの三つすべてで
  HEADが採用SHAと一致していることまで確認する。
- registryの`repository_url`に認証情報、query、fragment、ローカルpathを書かない。

## 実行

ケースの`request`をエージェントへ与え、実際のtraceと変更を`expect`へ照合する。
fixtureは隔離コピーへ重ね、元の作業ツリーを変更しない。

`tools/validate-agent-directory.sh`はschema、必須ケース、fixture、構造を静的に検査し、context Toolの
決定的なfixture検索も実行する。モデルへ依頼する行動evalそのものとは別である。
