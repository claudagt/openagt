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
5. Projectを1件に確定してから、このREADME、`PROJECT.md`、`STATE.md`の順に読む。

## 基本構造

```text
project-name/
├── PROJECT.md
├── STATE.md
├── inputs/       # Project固有の入力。必要時のみ
├── outputs/      # 完成成果物。必要時のみ
├── runs/         # 保存価値のある詳細履歴。既定では読まない
├── candidates/   # Project固有の再利用候補
└── scripts/      # Project固有の固定コード
```

全Projectに`PROJECT.md`と`STATE.md`を必須とする。新規作成は利用者の明示依頼後に
`_template/`をコピーし、すべてのプレースホルダーを書き換える。

## 外部リポジトリを持つProject

既定では、Projectの正本と成果物はすべてこのリポジトリ内にあり、遠隔バックアップへ自動的に含まれる。
成果物を別リポジトリへ分割しないことを既定とする。リポジトリを増やすことはバックアップの検証点を
増やし、復旧の信頼性を下げるためである。

分割してよいのは、利用者の確認を得たうえで、次のいずれかを満たす場合だけとする。

- agent-directory外の他者がそのリポジトリを共同編集する。
- そのリポジトリ自体から公開、デプロイ、配布が行われる。
- agent-directoryと異なるアクセス権限が必要である。

サイズ、ファイル種類、整理上の都合、既に別のGitリポジトリで管理されているという事実は、
分割の理由にしない。既存の分割が上の条件を満たさない場合は統合を既定とし、統合するかどうかを
利用者へ確認する。エージェントは独断で統合、ignore、submodule化、削除を行わない。

分割を認めたProjectは次を守る。

- `PROJECT.md`の`## 制約・固定決定`へ一度だけ次の書式で宣言する。

  ```markdown
  - 外部リポジトリ: `<git-url>`（作業clone: `<agent-directory外のパス>`。バックアップはこのリポジトリ側が持つ）
  ```

- 作業cloneはこのリポジトリの外へ置く。内部にネストさせない。ネストrepoとsubmoduleは
  backup Toolが停止する。
- このリポジトリ側の`projects/<name>/`には`PROJECT.md`、`STATE.md`、参照だけを置く。これらは
  遠隔バックアップに含まれ、外部リポジトリへの入口として機能する。
- 宣言のないネストリポジトリやsubmoduleを検出した場合は、追加、削除、ignore、submodule化の
  いずれも行わず、宣言するかどうかを利用者へ確認する。

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
