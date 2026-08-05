# PROJECTS.md — 成果契約と現在状態の正本

固有のデータ、仕事、成果物を1 Project 1ディレクトリで保存する。

## 正本と責務

Projectの正本は次の責務で分ける。

```text
AGENTS.md              = 読込Route、固有コマンド、禁止事項、承認ゲート
PROJECT.md             = なぜ行い、何を実現するか。種別、成果契約、判断原則、固定制約
STATE.md               = 今どこにいるか。現在目標、合格条件、検証結果、有効な決定、次の一手
ARCHITECTURE.md        = Project全体の構造地図、境界、不変条件
docs/<DOMAIN>.md       = 分野ごとの現在有効な正本兼入口
docs/<DOMAIN>_SENSE.md = 分野固有の定性的判断
下位文書               = 詳細設計、仕様、研究、計画、証拠
Root Knowledge         = Projectを越えて再利用する確定知識
```

別の`GOAL.md`、`STATUS.md`、`TODO.md`を作らない。詳細履歴は`runs/`またはGit履歴へ置く。
成果物はKnowledge、Skill、`.tmp/`へ残さず必ず一つのProjectが所有し、再利用可能な知見だけを
`knowledge/`へ同期する。

### 作らない重複

同じ情報のactive正本を二つ持たない。次は文書全体へ適用する。

- `docs/**`の一括読込とDomain Canon全件の無条件読込。
- `AGENTS.md`へのDomain Canon、`PROJECT.md`、`STATE.md`本文の複製。
- `PROJECT.md`や`STATE.md`へのDomain文書本文の複製。
- `PROJECT.md`とDomain Canon、`STATE.md`と`PLANS.md`、`ARCHITECTURE.md`と詳細設計文書、
  Project ResearchとRoot Knowledge。

## 対象の選択

1. 依頼か正本の明示相対パスを最優先し、未指定なら
   `tools/find-context.sh --route project --limit 5 -- <query>`で候補を得る。Project選択の単位は
   `PROJECT.md`であり、`docs/`配下を通常候補へ展開しない。
2. 通常候補は`status: active`だけ。`paused`、`completed`、`retired`は明示参照、再開、監査、保守時だけ選ぶ。
3. 候補メタデータだけで一意に選べず、選択で成果や安全性が変わる場合は利用者へ確認する。

読込順序は`projects/AGENTS.md#着手`が所有。

## 基本構造

必要になった部分だけを作り、ツリー全体を生成しない。

```text
projects/<project-name>/
├── PROJECT.md
├── STATE.md
├── AGENTS.md         # 任意。作業差分がある場合だけ
├── CLAUDE.md         # AGENTS.mdがあるときのブリッジ（@AGENTS.md）
├── ARCHITECTURE.md   # 任意。Project全体の構造地図
├── docs/             # 任意。分野ごとのDomain Canonと詳細文書
│   ├── <DOMAIN>.md
│   ├── <DOMAIN>_SENSE.md
│   ├── references/
│   ├── generated/
│   └── <project-defined>/
├── inputs/           # Project固有の入力
├── outputs/          # 完成成果物
├── runs/             # 保存価値のある詳細履歴。既定では読まない
├── candidates/       # Project固有の再利用候補
└── scripts/          # Project固有の固定コード
```

全Projectに`PROJECT.md`と`STATE.md`を必須とする。新規作成は利用者の明示依頼後に`_template/`をコピーし、
すべてのプレースホルダーを書き換える。`_template/`は`PROJECT.md`と`STATE.md`だけを持ち、他を常設しない。

## Project文書の三層

```text
Scope Canon      = AGENTS.md / PROJECT.md / STATE.md / ARCHITECTURE.md
Domain Canon     = docs/<DOMAIN>.md、docs/<DOMAIN>_SENSE.md
Detail Documents = docs/<小文字ケバブケース>/配下の詳細設計、仕様、研究、計画、証拠
```

### Domain Canon

`docs/`直下に置く、意味を持つ大文字のMarkdownである。必須一覧はなく、実際に存在する分野だけを作る。

```text
docs/DESIGN.md  docs/PLANS.md  docs/RESEARCH.md  docs/PRODUCT_SENSE.md  docs/QUALITY_SCORE.md
```

- 命名は原則として`^[A-Z][A-Z0-9]*(?:_[A-Z0-9]+)*\.md$`を満たす。
- 内容を持つ`docs/`は最低1件のDomain Canonを直下に持つ。詳細文書だけを置いて入口を欠かない。
- `docs/README.md`、`docs/NOTES.md`、`docs/MISC.md`のような汎用的・無責任な正本を作らない。
- 単なるリンク一覧にしない。現在有効な原則、境界、決定を短く保持し、詳細文書へ案内する正本兼入口とする。
- 24KiBを超えない。超える詳細はDetail Documentsへ委譲する。見出し構成は分野ごとに決めてよい。

### Detail Documents

詳細フォルダと詳細文書はProjectごとに設計してよく、agent-directory全体で名前を固定しない。

```text
docs/design-docs/core-beliefs.md  docs/research/model-selection-study.md
```

- フォルダと詳細文書は原則として小文字ケバブケースとする。
- `misc/`、`other/`、`notes/`のような総受けフォルダを作らない。
- `docs/`直下の各フォルダは少なくとも一つのDomain Canonから参照し、`references/`と`generated/`も
  どのDomain Canonが管理するかを明示する。
- 下位コレクションの局所地図として`index.md`を使ってよい。下位`README.md`を正本や入口として多用しない。
- 空フォルダをテンプレート生成しない。
- `docs/references/`は繰り返し参照するProject固有資料に限定し、Root Knowledgeと二重正本にしない。
  `docs/generated/`は生成元、生成コマンド、鮮度確認方法がある場合だけ使い、生成物を手編集しない。

## ARCHITECTURE.md

Project rootに置く任意の全体地図である。

| 所有する | 所有しない |
|---|---|
| Projectが解く問題の俯瞰、主要コンポーネント | 現在目標、TODO、進捗 |
| コード、パッケージ、データの配置 | 詳細な試行履歴 |
| 依存方向、システム境界 | 頻繁に変わる実装詳細 |
| アーキテクチャ不変条件、横断的関心事 | `PROJECT.md`と`STATE.md`の再掲 |

短く安定した地図とし、詳細設計は詳細文書が持つ。

## `<DOMAIN>_SENSE.md`

分野固有の定性的な品質判断を所有する任意パターンである。裸の`SENSE.md`を使わず、必ず対象Domainを
名前に含める。例: `PRODUCT_SENSE.md`、`DESIGN_SENSE.md`。

- 所有する: What good looks like、Core beliefs、判断ヒューリスティクス、トレードオフ、
  Anti-patterns、良い例と悪い例、レビュー時の問い、見直し条件。
- 所有しない: 必須仕様、数値合格条件、コマンド、現在状態、単なる好み、根拠のない抽象語。

```text
<DOMAIN>.md                          = 現在有効な分野の原則・構造・決定
<DOMAIN>_SENSE.md                    = 定性的な品質判断
QUALITY_SCORE.md / <DOMAIN>_SCORE.md = 測定可能な評価軸
```

## 個別ProjectのAGENTS.md

Project固有の作業差分だけを持つ差分ファイルである。差分があるときだけ置き、全Projectへ一律生成しない。
ただし`ARCHITECTURE.md`または`docs/`が存在する場合は、同Projectの`AGENTS.md`と`CLAUDE.md`を必須とし、
段階的開示の入口にする。

置いてよい内容:

- 条件付きのProject Docs Route（本文を複製せず、条件と読む正本だけを列挙する）
- Project固有のbuild、test、lintコマンドと検証順序
- 特定パスの編集禁止、既存成果物の上書き禁止、使用するランタイム
- 本番送信、公開、課金、権限変更の承認ゲート、`## Push Policy`、Project固有の生成物配置

置いてはいけない内容:

- 目的、最終ゴール、継続的使命、完了条件、成功指標、Project Criterion
- 現在目標、現在状態、検証結果、現在有効な決定
- KnowledgeとSkillの参照一覧
- `projects/PROJECTS.md#作らない重複`が禁じる本文の複製と一括読込指示

```markdown
## Project Docs Route

| 条件 | 読む正本 |
|---|---|
| モジュール、依存、データフローを変更する | `ARCHITECTURE.md` |
| UIや体験を変更する | `docs/DESIGN.md` |
```

見出しは`## Project Docs Route`と正確に一致させ、存在する`ARCHITECTURE.md`と`docs/`直下の各Domain Canonを
この節の条件付き項目として列挙する。項目は「条件」と「読む正本」を持つ表の行、または`条件:`と`参照:`の対と
する。本文中の言及、単なるファイル一覧、禁止文への登場は条件付き参照として数えない。
2,048 bytes以内とし、`PROJECT.md`と`STATE.md`を正本として参照する。同階層に`@AGENTS.md`だけを持つ
`CLAUDE.md`を必ず置き、`CLAUDE.md`だけを単独で置かない。サイズ制約を拡大せず、短いRoute表として
収まる設計を優先する。

## 研究文書とKnowledge昇格

具体的な研究活動はProjectが所有し、再利用可能な研究方法はSkillが所有する。仮説、調査、実験は規模に応じて
`docs/RESEARCH.md`か`docs/research/<study-name>.md`へ、成果物は`outputs/`へ置く。推奨要素は次とする。

```text
問い / 目的 / 仮説 / 方法 / 使用した証拠 / 観測・結果 /
反対証拠・限界 / 現在の結論 / Knowledgeへの昇格先
```

Root Knowledgeへ昇格するのは次をすべて満たす場合だけとする。

1. Project外でも再利用できる。
2. 根拠へ遡れる。
3. 適用範囲と不確実性が明記されている。
4. 一時的な作業メモではない。

昇格時はProject Researchを研究履歴として残し、Knowledge側と元研究・原資料を双方向にリンクする。
現在有効な再利用可能結論の正本はKnowledge側とし、同じ結論を二つのactive正本として保守しない。
Project固有の結論を無理に昇格させない。

## Attachment

Projectは成果、目的、状態の境界であり、Gitリポジトリは変更権限、自動化、配布、外部接続の境界である。
両者を1対1にしない。agent-directoryは外部repoの集約点ではなく、一体のAgent Workspaceである。

Project root、実装root、通常の作業cwdは、attachmentによらず`projects/<name>/`へ統一する。
違いはpathではなく所有Gitだけである。

- **Embedded** — Git top-levelはAgent Workspace root。`projects/<name>/**`をroot Gitが所有する。
- **Independent** — Git top-levelは`projects/<name>/`自身。直下に実`.git/`を持つ通常cloneである。

worktree、submodule、symlink、`.git` file、外部配置、`repository/`のような下位repo階層を使わない。
すべてのProjectはEmbeddedで開始し、独立したremote identityが必要な場合だけIndependentへ昇格する。

`PROJECT.md`はattachmentを宣言しない。`repository_mode`、`repository_url`、`repository_reason`、
`repository_default_branch`、`STATE.md`の`## Repository State`は廃止済みで現役schemaへ残さない。
判定は`projects/REPOSITORIES.md`の登録、`git -C projects/<name> rev-parse --show-toplevel`の結果、
root Gitがそのpath配下を追跡しているかの三つで行う。

### Canonical Ownership

Independentでは`projects/<name>/**`のすべて（契約、状態、個別`AGENTS.md`と`CLAUDE.md`、docs、入出力、
コード、Git履歴）をProject固有Gitが所有し、root Gitは内部ファイルを一つも追跡しない。root側へ
`PROJECT.md`や`STATE.md`のコピーを残さず、同じ契約と状態を二つのGitへ複製しない。Project内部の
相対pathは両attachmentで同じであり、mode別の読み替えを持たない。

### Registryとignore projection

root Gitが持つのはProject本文ではなく、[projects/REPOSITORIES.md](REPOSITORIES.md)の最小な
attachment／recovery registryと、その派生projectionである`projects/.gitignore`だけである。registryは
目的、成果契約、status、mode、現在状態を複製せず、entry形式、field規則、`repository_reason`の値と意味、
managed blockの形式と更新規則はregistry自身が所有する。registryが正本であり、ignoreは派生である。

Embedded Project、`_template/`、registry自身をignoreせず、`projects/*/`のような広いpatternを追加しない。

コード量、ファイル数、言語、整理都合、重要度、期間、既存repoだった事実だけではIndependent化しない。
大容量binaryも理由にせず、外部artifact保管先とchecksumはProject側が定義する。remote名は`origin`固定と
し、remoteから復旧できることを必須とする。

### Session rootとSHA handoff

一つのAI sessionは二つのGit rootへ書き込まない。Single Writer定義は`tools/BACKUP.md`が所有する。

cwdとcommit先の対応は`projects/AGENTS.md#Git所有境界`が所有する。registryを更新するsessionだけが
Agent Workspace rootをcwdとし、registryとignore projectionだけを書く。本体を変更するsessionは
root repositoryを変更しない。

### Remote操作の境界

root backup remoteへのpushは`tools/backup-to-github.sh`だけが行い、remote分類とtriggerは
`tools/BACKUP.md`が所有する。Independentの`origin`はCI、deploy、release、Webhook、外部共同編集、
公開のような外部影響を持ちうるため、backupと同じ扱いにしない。

#### push policy

Projectごとに一度決め、以後push可否を質問しない。値は`auto`と`gated`だけとし、判定は次の優先順で
一意に定める。

1. **宣言** — `projects/<name>/AGENTS.md`の`## Push Policy`が`auto`か`gated`を1語で持つ。
2. **観測** — repository内にCI、deploy、release、publish、Webhookを起動する設定がある場合は`gated`。
3. **既定** — `repository_reason`が`automation`、`distribution`、`access`なら`gated`、
   `collaboration`、`identity`、`upstream`、`retention`なら`auto`。

- `auto` — 検証済みcommitを`origin`へ通常pushし、remoteにSHAが存在することまでAIが自律確認する。
- `gated` — commitまでAIが行い、push前だけ利用者の承認を得る。承認待ちはpushだけを止め、検証済み
  ローカルcommitを取り消さない。

三段で一意にならない場合だけ一度確認し、決まった値を`## Push Policy`へ記録する。判定のための
新しいregistry fieldやfrontmatterを追加しない。

policyによらず、force push、force-with-lease、mirror push、pull・merge・rebaseによる自動統合、検証前の
push、root sessionからのIndependent remote操作、remote divergenceの自動解消を行わない。

通常のIndependent更新は次の順で進み、安全条件を満たす限り確認を挟まない。

1. `projects/<name>/`のsessionで`projects/AGENTS.md`の手順どおり読込、変更、検証、commitする。
2. policyが`auto`なら`origin`へ通常pushし、remoteにcommit SHAが存在することを確認する。
3. SHA、検証結果、未完了をhandoffする。
4. 別のroot sessionが`projects/REPOSITORIES.md`の`revision`だけを更新する。
5. root validatorとcacheを実行してroot Gitへcommitし、設定済みならworkspace backupを実行する。

### Materializationとbackup境界

健全なAgent Workspaceでは、statusにかかわらず全Independent repositoryがmaterialize済みである。
materializerはregistryからcloneを再現して採用revisionを最初にcheckoutし、branch tipを自動採用せず、
HEADが採用revisionと一致しない既存cloneを正常扱いしない。

backupの既定scopeはworkspaceであり、root pushの前に全Independent repositoryを監査し、Independent
repository自体はpushしない。`--root-only`は部分結果である。scope、停止reason、監査項目、移行手順、
rootでの`git clean`の禁止（ignoredな`projects/<name>/`を不可逆に消しうる）は`tools/BACKUP.md`が所有する。

### 昇格、移行、統合

EmbeddedからIndependentへの昇格は次の順で行う。

1. 利用者がIndependent化と`repository_reason`を承認し、root Gitで移行前checkpointを確定する。
2. remote repoを作成し、`projects/<name>/`をrootとするsessionで検証、commit、`origin`へ通常pushする。
3. root indexから`projects/<name>/`配下を削除し、registry entryとmanaged entryを同じroot commitで
   追加する。
4. validatorで二重正本とroot追跡の不在を確認する。
5. 設定済みならworkspaceをバックアップする。

履歴抽出は実益がある場合だけ行い、そのために平常時からrepoを分けない。
登録のないnested repoまたはsubmoduleは追加、削除、ignore、submodule化せず、停止して利用者へ確認する。

IndependentからEmbeddedへの統合は自動既定にしない。`repository_reason`のどの根拠も現在成立しないことを
監査し、利用者が明示承認した場合だけ実行する。過去に外部identityを持ったrepoを、停止中という理由だけで
統合しない。

### 旧構造からの移行

対象は旧`projects/<name>/repository/`方式とagent-directory外へcloneを置く旧方式で、最終標準として
残さず永久併存も認めない。どちらもclone全体を`projects/<name>/`へ移し、契約と状態はProject固有Gitが
持つ形へ揃える。順序、監査項目、置換・削除条件、machine-localなsource pathの扱いは
[tools/BACKUP.md](../tools/BACKUP.md)が所有する。

## PROJECT.md

frontmatterは次を必須とする。

```yaml
---
name: project-name
description: 候補選択に使う一行説明
status: active
mode: finite
---
```

- `name`はディレクトリ名と一致させる。
- `description`は200文字以内の一行とし、タブを含めない。
- `mode`は`finite`または`continuous`だけを使う。
- `status`は`active | paused | completed | retired`だけを使う。
- attachmentはfrontmatterで宣言しない。判定は`#Attachment`が持つ。
- パスが恒久IDである。別のID体系や物理archiveを作らない。

### finite

一つの検証可能な終了状態を実現する。`最終ゴール`と固定ID付き`完了条件`を持ち、
全条件の検証後だけ`completed`にする。

### continuous

現在目標を更新しながら継続する。`継続的使命`、固定ID付き`成功指標`、`見直し・終了条件`を持つ。
現在目標の達成を理由に`completed`へ変更しない。

## 参照するKnowledgeとSkill

各参照欄を`### Required`と`### Conditional`に分ける。

- RequiredのKnowledgeとSkillは合計6件以内とし、着手時に読む。
- Conditionalは`条件:`と`参照:`を組にし、条件成立時だけ読む。
- 参照はリポジトリ相対パスを使う。ウィキリンクだけを実行時参照にしない。
- 非activeなKnowledge、deprecated/retired SkillをRequiredにしない。
- 上限を超える場合は条件付き化、参照入口の集約、またはProject分割を行い、無制限読込で解決しない。

## 着手から終了まで

1. `PROJECT.md`と`STATE.md`を最後まで読み、現在目標、合格条件、それが前進させる`PROJECT.md#PC-xx`と、
   Required参照および成立したConditional参照・Domain Canonだけを特定して読む。
2. 成果契約の範囲で最小かつ完全な変更を行う。契約や品質基準を弱めない。
3. `PROJECT.md`の検証方法と現在目標の合格条件を実行する。未実行の検証を合格と推測しない。
4. 状態が変わった同じ作業内で`STATE.md`を現在有効な状態へ更新する。
5. 検証合格後は同じ作業内でscoped commitまで完結し、可否を質問しない
   （`tools/TOOLS.md#自律実行の標準完了`）。
6. 達成結果、検証証拠、commit、push・backup結果、未完了・ブロッカーを区別して報告する。

`mode`、目的、ゴールまたは使命、完了条件または成功指標、判断原則、非ゴール、固定決定は、
利用者が変更を明示した場合だけ変更する。

## Project Criterion

finiteの完了条件とcontinuousの成功指標だけに`PC-01`から始まる固定IDを付ける。

```markdown
- **PC-01** <安定した合格条件>
```

IDは達成状態ではなく恒久的な住所である。並べ替えや達成で変更せず、削除後に番号を再利用しない。
達成状態と証拠は`STATE.md`だけが持つ。

## STATE.md

- 現在目標は一つの到達状態とし、`対象契約: PROJECT.md#PC-xx`を一つ示す。
- 合格条件は第三者が判定できる形にする。
- 検証結果は対象、確認日、方法、客観的結果を持ち、最新の有効な証拠だけを残す。
- 有効な決定、失敗・却下済み、ブロッカー、次の一手を現在形で短く保つ。
- 詳細な試行履歴は`runs/`またはGitへ移し、8KiBを超えない。
- 現在判断ではactiveなKnowledgeとSkillを優先する。

状態遷移と削除条件は必要な場合だけ[projects/LIFECYCLE.md](LIFECYCLE.md)を読む。
利用者から間違い、重複、目的不一致を指摘された場合だけ[projects/RECOVERY.md](RECOVERY.md)を読む。

## 検証

- Project固有の検証は`PROJECT.md`に実行方法、期待結果、入力、必要な環境変数名を記す。
- 固定コードは`scripts/`、一時コードは`.tmp/`、2回目の再利用候補は`candidates/`が所有する。
- 外部公開、本番反映、送信、課金、権限変更、`gated`なpushは実行前に承認を得る。承認がない限り
  完了条件を満たしたとしない。内部で完結する可逆な検証と修正は承認を待たずに行う。
