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
成果物は必ず一つのProjectが所有し、Knowledge、Skill、`.tmp/`へ残さない。
再利用可能な知見だけを`knowledge/`へ同期する。

### 作らない重複

同じ情報のactive正本を二つ持たない。次はこの文書全体へ適用する。

- `docs/**`の一括読込と、Domain Canon全件の無条件読込。
- `AGENTS.md`へのDomain Canon、`PROJECT.md`、`STATE.md`本文の複製。
- `PROJECT.md`や`STATE.md`へのDomain文書本文の複製。
- Independent Projectのroot側envelopeへの個別`AGENTS.md`、`ARCHITECTURE.md`、`docs/`、コード、設計文書の複製。
- `PROJECT.md`と`PRODUCT_SENSE.md`、`PROJECT.md`と`DESIGN.md`、`STATE.md`と`PLANS.md`、
  `ARCHITECTURE.md`と詳細設計文書、Project ResearchとRoot Knowledge。

## 対象の選択

1. 依頼または正本が相対パスを明示していれば、そのProjectを選ぶ。
2. 未指定なら`tools/find-context.sh --route project --limit 5 -- <query>`で候補を得る。
   Project選択の単位は`PROJECT.md`であり、`docs/`配下は通常の検索候補へ展開しない。
3. 通常候補は`status: active`だけとする。`paused`、`completed`、`retired`は、明示参照、再開、監査、保守時だけ選ぶ。
4. 候補メタデータだけで一意に選べず、選択で成果や安全性が変わる場合は利用者へ確認する。
5. Projectを1件に確定してから次の順序で読む。この`PROJECTS.md`は`projects/AGENTS.md`が列挙する条件に
   該当する場合だけ読む。

```text
AGENTS.md → projects/AGENTS.md → 対象Project AGENTS.md（存在する場合）
→ PROJECT.md → STATE.md → 条件に一致したDomain Canon
→ Required Knowledge / Skill → 必要な詳細文書とConditional参照
```

## 基本構造

必要になったProjectだけが該当部分を作る。このツリー全体を生成しない。

```text
projects/<project-name>/
├── PROJECT.md
├── STATE.md
├── AGENTS.md         # 任意。Project固有の作業差分がある場合だけ
├── CLAUDE.md         # 上記AGENTS.mdがある場合のブリッジ。内容は @AGENTS.md
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
すべてのプレースホルダーを書き換える。`_template/`は`PROJECT.md`と`STATE.md`だけを持ち、
`docs/`、`ARCHITECTURE.md`、Domain Canon、`references/`、`generated/`、個別`AGENTS.md`を常設しない。

## Project文書の三層

```text
Scope Canon      = AGENTS.md / PROJECT.md / STATE.md / ARCHITECTURE.md
Domain Canon     = docs/<DOMAIN>.md、docs/<DOMAIN>_SENSE.md
Detail Documents = docs/<小文字ケバブケース>/配下の詳細設計、仕様、研究、計画、証拠
```

### Domain Canon

`docs/`直下に置く、意味を持つ大文字のMarkdownである。必須一覧はなく、実際に存在する分野だけを作る。

```text
docs/DESIGN.md   docs/FRONTEND.md  docs/SECURITY.md       docs/RELIABILITY.md
docs/PLANS.md    docs/RESEARCH.md  docs/PRODUCT_SENSE.md  docs/QUALITY_SCORE.md
```

- 命名は原則として`^[A-Z][A-Z0-9]*(?:_[A-Z0-9]+)*\.md$`を満たす。
- 内容を持つ`docs/`は最低1件のDomain Canonを直下に持つ。詳細文書だけを置いて入口を欠かない。
- `docs/README.md`、`docs/NOTES.md`、`docs/MISC.md`のような汎用的・無責任な正本を作らない。
- 単なるリンク一覧にしない。通常作業に必要な現在有効な原則、境界、決定を短く保持し、必要な詳細文書へ
  案内する正本兼入口とする。
- 1ファイル24KiBを超えない。超える詳細はDetail Documentsへ委譲する。見出し構成は分野ごとに決めてよい。

### Detail Documents

詳細フォルダと詳細文書はProjectごとに設計してよく、agent-directory全体で名前を固定しない。

```text
docs/design-docs/core-beliefs.md        docs/product-specs/new-user-onboarding.md
docs/research/model-selection-study.md  docs/plans/database-migration.md
```

- フォルダと詳細文書は原則として小文字ケバブケースとする。
- `misc/`、`other/`、`notes/`のような総受けフォルダを作らない。
- `docs/`直下の各フォルダは、少なくとも一つのDomain Canonから参照する。`references/`と`generated/`も
  同じ規則に従い、どのDomain Canonが管理するかを明示する。
- 下位コレクションの局所地図として`index.md`を使ってよい。下位`README.md`を正本や入口として多用しない。
- 空フォルダをテンプレート生成しない。
- `docs/references/`と`docs/generated/`は予約された任意の慣例であり、必要な場合だけ作る。
  `references/`はProject固有で繰り返し参照する資料に限定し、Root Knowledgeと二重正本にしない。
  `generated/`は生成元、生成コマンド、鮮度確認方法が存在する場合だけ使い、生成物を手編集しない。

## ARCHITECTURE.md

Project implementation rootに置く任意の全体地図である。Embedded Projectは`projects/<name>/ARCHITECTURE.md`、
Independent Projectは`projects/<name>/repository/ARCHITECTURE.md`が所有する。

| 所有する | 所有しない |
|---|---|
| Projectが解く問題の俯瞰、主要コンポーネント | 現在目標、TODO、進捗 |
| コード、パッケージ、データの配置 | 詳細な試行履歴 |
| 依存方向、システム境界 | 頻繁に変わる実装詳細 |
| アーキテクチャ不変条件、横断的関心事 | `PROJECT.md`と`STATE.md`の再掲 |

短く安定した地図として扱い、詳細設計は`docs/`配下の詳細文書が持つ。

## `<DOMAIN>_SENSE.md`

分野固有の定性的な品質判断を所有する任意パターンである。裸の`SENSE.md`を使わず、必ず対象Domainを
名前に含める。例: `PRODUCT_SENSE.md`、`DESIGN_SENSE.md`、`EDITORIAL_SENSE.md`、`MUSIC_SENSE.md`、
`CONTENT_SENSE.md`、`RESEARCH_SENSE.md`。

- 所有する: What good looks like、Core beliefs、定性的な判断ヒューリスティクス、トレードオフ、
  Anti-patterns、良い例と悪い例、レビュー時の問い、見直し条件。
- 所有しない: 必須仕様、数値合格条件、コマンド、現在状態、単なる好み、根拠のない抽象語。

```text
<DOMAIN>.md                          = 現在有効な分野の原則・構造・決定
<DOMAIN>_SENSE.md                    = 定性的な品質判断
QUALITY_SCORE.md / <DOMAIN>_SCORE.md = 測定可能な評価軸
```

空のテンプレートファイルを先に置かず、必要になったProjectだけがこの構造で新規作成する。

## 個別ProjectのAGENTS.md

Project固有の作業差分だけを持つ差分ファイルである。差分があるときだけ置き、全Projectへ一律生成しない。
ただしEmbedded Projectに`ARCHITECTURE.md`または`docs/`が存在する場合は、同Projectの`AGENTS.md`と
`CLAUDE.md`を必須とし、段階的開示の入口にする。

置いてよい内容:

- 条件付きのProject Docs Route（本文を複製せず、条件と読む正本だけを列挙する）
- Project固有のbuild、test、lintコマンドと検証順序
- 特定パスの編集禁止、既存成果物の上書き禁止、使用するランタイム
- 本番送信、公開、課金、権限変更の承認ゲート、Project固有の生成物配置

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
| 定性的な製品判断を行う | `docs/PRODUCT_SENSE.md` |
```

見出しは`## Project Docs Route`と正確に一致させ、存在する`ARCHITECTURE.md`と`docs/`直下の各Domain Canonを
この節の条件付き項目として列挙する。項目は「条件」と「読む正本」を持つ表の行、または`条件:`と`参照:`の対と
する。本文中の言及、単なるファイル一覧、禁止文への登場は条件付き参照として数えない。
2,048 bytes以内とし、`PROJECT.md`と`STATE.md`を正本として参照する。同階層に`@AGENTS.md`だけを持つ`CLAUDE.md`を必ず置き、
`CLAUDE.md`だけを単独で置かない。Embedded Projectだけに置ける。Independent Projectの
`AGENTS.md`は`projects/<name>/repository/`が所有し、所有関係は`projects/PROJECTS.md#repository-mode`が持つ。
サイズ制約を拡大せず、短いRoute表として収まる設計を優先する。

## 研究文書とKnowledge昇格

具体的な研究活動はProjectが所有し、再利用可能な研究方法はSkillが所有する。研究中の仮説、調査、実験は
規模に応じて`docs/RESEARCH.md`または`docs/research/<study-name>.md`へ置き、成果物は`outputs/`へ置く。
研究文書の推奨要素は次とする。

```text
問い / 目的 / 仮説 / 方法 / 使用した証拠 / 観測・結果 /
反対証拠・限界 / 現在の結論 / Knowledgeへの昇格先
```

Root Knowledgeへ昇格するのは次をすべて満たす場合だけとする。

1. Project外でも再利用できる。
2. 根拠へ遡れる。
3. 適用範囲と不確実性が明記されている。
4. 一時的な作業メモではない。

昇格時はProject Researchを研究履歴として残し、Knowledge側から元研究と原資料へ、Project側から昇格先
Knowledgeへリンクする。現在有効な再利用可能結論の正本はKnowledge側とし、同じ結論を二つのactive正本として
保守しない。Project固有の結論は、研究が完了していても無理に昇格させない。

## Repository mode

agent-directoryは複数の外部repoを束ねるHubではなく、一体のAgent Workspaceである。Projectは成果、目的、
状態の境界であり、Gitリポジトリは変更権限、自動化、配布、外部接続の境界である。両者を1対1にしない。
すべてのProjectは`embedded`で開始し、独立したremote identityが必要になった場合だけ`independent`へ昇格する。

### Embedded Project

`repository_mode: embedded`では、Projectの正本、コード、軽量成果物を`projects/<name>/`に置く。
root GitがProject単位の履歴、差分、復元を持ち、Private backupへまとめて保全する。Project内の`.git`、
submodule、固有remote、GitHub Actionsは禁止する。Project単位の履歴は次のようにパスで取得できる。

```bash
git log -- projects/<name>
git diff <old-sha>..<new-sha> -- projects/<name>
git restore --source=<sha> -- projects/<name>
```

無関係な複数Projectを同じcommitへ混ぜず、`project(<name>): ...`のように変更単位を分ける。

### Independent Project Repository

利用者の承認を得たうえで、次のいずれかを満たす場合だけ`repository_mode: independent`へ昇格する。

| `repository_reason` | 独立repoが必要になる境界 |
|---|---|
| `automation` | Actions、Pages、Packages、Dependabot、Webhook、外部デプロイ |
| `distribution` | OSS公開、tag、Release、packageやbinaryの配布 |
| `collaboration` | 外部共同編集、Pull Request、Issue運用 |
| `access` | 異なるvisibility、権限、Secrets、branch protection |
| `identity` | 外部サービスや利用者が固定repo URLを参照 |
| `upstream` | fork、upstream追従、他システムからの依存 |
| `retention` | rootと異なる履歴保持・export・削除方針、または実測されたGit履歴上の復旧問題 |

コード量、ファイル数、言語、整理上の都合、重要度、期間、個別履歴の希望、既存の別repoという事実だけでは
Independent化しない。大容量binaryやartifactもrepo分割の理由にせず、Project側が外部artifact保管先と
checksumを定義する。Independent repositoryはremoteから復旧できることを必須とし、remote名は`origin`を
固定既定とする。

Independentの`PROJECT.md`は次をfrontmatterへ各1回だけ宣言する。マシン固有のclone pathや認証情報を含むURLは
正本へ保存しない。`remote.origin.url`は`repository_url`と完全一致させる。

```yaml
repository_mode: independent
repository_url: git@github.com:<owner>/<repository>.git
repository_reason: automation
repository_default_branch: main
```

`STATE.md`の`## Repository State`は採用revisionだけを持つ。remoteへpush済みの完全な40文字commit SHAとする。

```markdown
## Repository State

- revision: `<40-character-commit-sha>`
```

### 固定pathとCanonical Ownership

Independentの通常cloneは必ず次の固定pathへ置く。普通の`git clone`であり、`repository/.git`は実directoryとする。
worktree、submodule、symlink、`.git` file、Projectディレクトリ自体の別repo化は禁止する。

```text
projects/<name>/
├── PROJECT.md      # root Gitが追跡。目的、成果契約、remote宣言
├── STATE.md        # root Gitが追跡。現在目標、採用revision、検証結果
└── repository/     # root Gitではignored、cacheではpruned、Independent Gitではroot
```

root側のIndependent Project directoryに置いてよいものはこの3つだけである。root Gitは`repository/`本体を
追跡せず、gitlinkも持たない。コード、tests、Project固有`AGENTS.md`、`ARCHITECTURE.md`、`docs/`、実行設定、
release設定、Git履歴はIndependent repositoryが所有する。root cache、manifest、fingerprint、検索は
`repository/`本体を完全にpruneする。

Project内部のpathはProject implementation rootからの相対とする。embeddedは`projects/<name>/`、
independentは`projects/<name>/repository/`である。

### Session rootとSHA handoff

一つのAI sessionが二つのGit rootへ書き込んではならない。Single Writerはagent単位ではなく
Gitリポジトリ単位であり、同じrepositoryへの同時Writerを禁止する一方、異なるIndependent repositoryは
並行して進めてよい。

| session | root | 書いてよい |
|---|---|---|
| Embedded作業 | Agent Workspace root | `projects/<name>/`配下 |
| Independent本体作業 | `projects/<name>/repository/` | Independent repositoryの中身だけ |
| Independent metadata更新 | Agent Workspace root | `PROJECT.md`と`STATE.md`だけ |

Independent sessionはcommit SHA、検証結果、未完了事項を返し、root sessionだけがそのSHAを`STATE.md`へ
採用する。Independent sessionはroot metadataを書かず、root sessionはIndependent本体を書かない。

### Materializationとbackup境界

健全なAgent Workspaceでは、statusにかかわらず全Independent repositoryが固定pathへmaterialize済みである。
`bash tools/materialize-project-repositories.sh --all`が宣言と採用revisionからcloneを再現する。
partial materializationは復旧途中のdegraded stateとしてだけ許し、workspace全体のbackup成功として扱わない。

backupの既定scopeはworkspaceであり、root repositoryをpushする前に全Independent repositoryを監査する。
Independent repository自体はpushしない。`--root-only`はrootだけを扱う部分結果である。
scope、停止reason、監査項目は`tools/BACKUP.md`が所有する。

rootで`git clean -x`、`git clean -X`、`git clean`への二つ以上の`-f`を実行しない。`repository/`はignored
であり、これらは未pushのIndependent commitを不可逆に削除しうる。

### 昇格、移行、統合

EmbeddedからIndependentへの昇格は、次の順序で行う。

1. 利用者がIndependent化と`repository_reason`を承認する。
2. root Gitで移行前checkpointを確定する。
3. remote repoを作成し、コード、tests、実行設定、`ARCHITECTURE.md`、`docs/`を移す。
4. `projects/<name>/repository/`で検証、commit、`origin`へのpushを完了する。
5. rootの`PROJECT.md`をIndependent宣言へ変更し、`STATE.md`へ初回SHAを記録する。
6. rootから重複sourceを除き、validatorで二重正本と`repository/`の追跡がないことを確認する。
7. 利用者が明示した場合だけworkspaceをバックアップする。

履歴維持に実益がある場合だけ対象pathの履歴を抽出する。履歴抽出のために平常時からrepoを分けない。
宣言のないnested repoまたはsubmoduleは追加、削除、ignore、submodule化せず、停止して利用者へ確認する。

agent-directory外へcloneを置く旧Satellite方式は最終標準として残さない。検出時は`deprecated-satellite-mode`
として扱い、移行対象としてだけ文書化する。移行手順と旧clone削除条件は`tools/BACKUP.md`が所有する。

IndependentからEmbeddedへの統合は自動既定にしない。外部共同編集、automation、release、Webhook、固定URL参照、
配布、異なる権限、upstream関係、`retention`上の保持・削除方針がすべて存在しないことを監査し、利用者が
明示的に廃止・統合を承認した場合だけ実行する。過去に外部identityを持ったrepoは、現在停止中という理由だけで
統合しない。

## PROJECT.md

frontmatterは次を必須とする。

```yaml
---
name: project-name
description: 候補選択に使う一行説明
status: active
mode: finite
repository_mode: embedded
---
```

- `name`はディレクトリ名と一致させる。
- `description`は200文字以内の一行とし、タブを含めない。
- `mode`は`finite`または`continuous`だけを使う。
- `repository_mode`は`embedded`または`independent`だけを使う。Independent追加項目は
  `projects/PROJECTS.md#repository-mode`に従う。
- `status`は`active | paused | completed | retired`だけを使う。
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
- 上限を超える場合は条件付き化、hub化、またはProject分割を行い、無制限読込で解決しない。

## 着手から終了まで

1. `PROJECT.md`と`STATE.md`を最後まで読み、現在目標、合格条件、それが前進させる`PROJECT.md#PC-xx`を特定する。
2. Required参照と、成立したConditional参照およびDomain Canonだけを読む。
3. 成果契約の範囲で最小かつ完全な変更を行う。契約や品質基準を弱めない。
4. `PROJECT.md`の検証方法と現在目標の合格条件を実行する。未実行の検証を合格と推測しない。
5. 状態が変わった同じ作業内で`STATE.md`を現在有効な状態へ更新する。
6. 達成結果、検証証拠、未完了・ブロッカーを区別して報告する。

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
- 固定コードは`scripts/`、一時コードは`.tmp/`、2回目の不安定な再利用候補は`candidates/`が所有する。
- 外部公開、送信、課金、権限変更は、必要な利用者承認がない限り完了条件を満たしたとしない。
