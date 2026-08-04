# projects/ — 成果契約と現在状態の正本

固有のデータ、仕事、成果物を1 Project 1ディレクトリで保存する。

## 二つの正本

```text
PROJECT.md = なぜ行い、何を実現するか。種別、成果契約、判断原則、固定制約
STATE.md   = 今どこにいるか。現在目標、合格条件、検証結果、有効な決定、次の一手
```

別の`GOAL.md`、`STATUS.md`、`TODO.md`を作らない。詳細履歴は`runs/`またはGit履歴へ置く。
成果物はProjectが所有し、再利用可能な知見だけを`knowledge/`へ同期する。

## 対象の選択

1. 依頼または正本が相対パスを明示していれば、そのProjectを選ぶ。
2. 未指定なら`tools/find-context.sh --route project --limit 5 -- <query>`で候補を得る。
3. 通常候補は`status: active`だけとする。`paused`、`completed`、`retired`は、明示参照、再開、監査、保守時だけ選ぶ。
4. 候補メタデータだけで一意に選べず、選択で成果や安全性が変わる場合は利用者へ確認する。
5. Projectを1件に確定してから、`projects/AGENTS.md`、対象Projectの`AGENTS.md`（存在する場合）、
   `PROJECT.md`、`STATE.md`の順に読む。このREADMEは`projects/AGENTS.md`が列挙する条件に
   該当する場合だけ読む。

## 基本構造

```text
project-name/
├── PROJECT.md
├── STATE.md
├── AGENTS.md     # 任意。Project固有の作業差分がある場合だけ
├── CLAUDE.md     # 上記AGENTS.mdがある場合のブリッジ。内容は @AGENTS.md
├── inputs/       # Project固有の入力。必要時のみ
├── outputs/      # 完成成果物。必要時のみ
├── runs/         # 保存価値のある詳細履歴。既定では読まない
├── candidates/   # Project固有の再利用候補
└── scripts/      # Project固有の固定コード
```

全Projectに`PROJECT.md`と`STATE.md`を必須とする。新規作成は利用者の明示依頼後に
`_template/`をコピーし、すべてのプレースホルダーを書き換える。`_template/`は`AGENTS.md`を持たず、
新規Projectへ自動複製しない。

## 個別ProjectのAGENTS.md

任意の差分ファイルである。実際にProject固有の作業差分があるときだけ置き、全Projectへ一律生成しない。

置いてよい内容:

- Project固有のbuild、test、lintコマンドと検証順序
- 特定パスの編集禁止、既存成果物の上書き禁止
- 使用するランタイムやパッケージマネージャー
- 本番送信、公開、課金、権限変更の承認ゲート
- Project固有の生成物配置

置いてはいけない内容:

- 目的、最終ゴール、継続的使命、完了条件、成功指標、Project Criterion
- 現在目標、現在状態、検証結果、現在有効な決定
- KnowledgeとSkillの参照一覧、`PROJECT.md`や`STATE.md`の再掲

2,048 bytes以内とし、`PROJECT.md`と`STATE.md`を正本として参照する。同階層に`@AGENTS.md`だけを持つ
`CLAUDE.md`を必ず置き、`CLAUDE.md`だけを単独で置かない。Embedded Projectだけに置ける。
Satellite Hub側は従来どおり`PROJECT.md`と`STATE.md`以外を持たず、Satellite固有の`AGENTS.md`は
Satelliteリポジトリ本体のルートが所有する。

## Repository mode

Projectは成果、目的、状態の境界であり、Gitリポジトリは変更権限、自動化、配布、外部接続の境界である。
両者を1対1にしない。すべてのProjectは`embedded`で開始し、外部の人またはシステムがProjectを独立した
Gitリポジトリとして識別・操作する必要が生じた場合だけ`satellite`へ昇格する。

### Embedded Project

`repository_mode: embedded`では、Projectの正本、コード、軽量成果物を`projects/<name>/`に置く。
ルートGitがProject単位の履歴、差分、復元を持ち、Private backupへまとめて保全する。Project内の`.git`、
submodule、固有remote、GitHub Actionsは禁止する。Project単位の履歴は次のようにパスで取得できる。

```bash
git log -- projects/<name>
git diff <old-sha>..<new-sha> -- projects/<name>
git restore --source=<sha> -- projects/<name>
```

無関係な複数Projectを同じcommitへ混ぜず、`project(<name>): ...`のように変更単位を分ける。
コード量、ファイル数、言語、重要度、期間、整理上の都合、個別履歴の希望、既存ローカルrepoという事実は
Satellite化の理由にしない。大容量artifactはrepo分割ではなく、Projectが外部保管先とchecksumを定義する。

### Satellite Repository

利用者の承認を得たうえで、次のいずれかを満たす場合だけ`repository_mode: satellite`へ昇格する。

| `repository_reason` | 独立repoが必要になる境界 |
|---|---|
| `automation` | Actions、Pages、Packages、Dependabot、Webhook、外部デプロイ |
| `distribution` | OSS公開、tag、Release、packageやbinaryの配布 |
| `collaboration` | 外部共同編集、Pull Request、Issue運用 |
| `access` | 異なるvisibility、権限、Secrets、branch protection |
| `identity` | 外部サービスや利用者が固定repo URLを参照 |
| `upstream` | fork、upstream追従、他システムからの依存 |

Satelliteの`PROJECT.md`は次をfrontmatterへ各1回だけ宣言する。マシン固有のclone pathや認証情報を含むURLは
正本へ保存しない。

```yaml
repository_mode: satellite
repository_url: git@github.com:<owner>/<repository>.git
repository_reason: automation
repository_default_branch: main
```

Hub側の`projects/<name>/`は`PROJECT.md`と`STATE.md`だけを持つ。目的、成果契約、固定判断は
`PROJECT.md`、現在目標、採用revision、検証結果は`STATE.md`が所有する。コード、tests、Workflow、release、
deploy設定、Git履歴はSatelliteだけが所有し、同じsourceをHubへ複製しない。

Satelliteの`STATE.md`は次の復旧tupleを持つ。`revision`はremoteへpush済みの完全な40文字commit SHAとし、
`repository`と`branch`は`PROJECT.md`の宣言に一致させる。

```markdown
## Repository State

- repository: `git@github.com:<owner>/<repository>.git`
- revision: `<40-character-commit-sha>`
- branch: `main`
- remote_verified_at: `YYYY-MM-DD`
```

agent-directoryをrootにしたHub sessionはこの2ファイルだけを変更し、Satellite本体を変更しない。
Satelliteの作業は、そのcloneを唯一のrootとする別sessionで行う。Satellite sessionはcommit SHA、検証結果、
未完了事項を返し、Hub sessionが採用するSHAと状態を`STATE.md`へ反映する。cloneの配置は環境側で決め、
agent-directory内へネストしない。

### 昇格と統合

EmbeddedからSatelliteへの昇格は、次の順序で行う。

1. 利用者がSatellite化を承認する。
2. ルートGitで移行前checkpointを確定する。
3. Satellite repoを作成し、コード、tests、実行設定を移す。
4. Satellite側で検証、commit、remote pushを完了する。
5. Hubの`PROJECT.md`をSatellite宣言へ変更し、`STATE.md`へ初回SHAを記録する。
6. Hubから重複sourceを除き、validatorで二重正本がないことを確認する。
7. 利用者が明示した場合だけHubをバックアップする。

履歴維持に実益がある場合だけ対象pathの履歴を抽出する。履歴抽出のために平常時からrepoを分けない。
宣言のないnested repoまたはsubmoduleは追加、削除、ignore、submodule化せず、停止して利用者へ確認する。

SatelliteからEmbeddedへの統合は自動既定にしない。外部共同編集、automation、release、Webhook、固定URL参照、
配布、異なる権限、upstream関係がすべて存在しないことを監査し、利用者が明示的に廃止・統合を承認した場合だけ
実行する。過去に外部identityを持ったrepoは、現在停止中という理由だけで統合しない。

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
- `repository_mode`は`embedded`または`satellite`だけを使う。Satellite追加項目は
  `projects/README.md#repository-mode`に従う。
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
2. Required参照と、成立したConditional参照だけを読む。
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
