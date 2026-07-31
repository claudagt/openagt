# evals/ — 振る舞いの品質保証

エージェントが `AGENTS.md` の規約どおりに振る舞うかを検証するケースを置く。

## Skillのscriptsとの分離

```text
skills/<skill>/scripts/ = そのSkill固有の実行・検証   → スキル単位
evals/                  = ルーティングと規約遵守の検証 → エージェント全体
```

## ケースの書き方

`cases/` に1ケース1ファイルで置く。文章の完全一致ではなく、構造上の不変条件を検証する。
判定をパス、分類、必須検証コマンド、必要な状態遷移に限定することで、
モデルや文章表現が変わってもテストが壊れにくくする。

```yaml
name: <case-name>

fixture: <fixtures内のディレクトリ名>  # 必要な場合のみ。リポジトリ直下へ重ねて使う

request: |
  <エージェントへの依頼文>

expect:
  route: knowledge | skill | project | none   # 残す正本の3分類。永続物がなければnone
  must_read:        # 着手前に読むべきファイル
    - AGENTS.md
  must_update:      # 状態変化を反映するため更新が必須の既存ファイル
    - projects/<project>/STATE.md
  must_run:         # 完了報告前に実行が必須の検証コマンド
    - bash projects/<project>/scripts/verify.sh
  must_set:         # 検証後に必要な状態遷移
    - projects/<project>/PROJECT.md#status=completed
  must_preserve:    # 状態遷移時にも変更してはならない契約の節
    - projects/<project>/PROJECT.md#PC-01
  may_write:        # 書き込みが許される場所
    - projects/**
  must_not_write:   # 書き込んではならない場所
    - knowledge/raw/**
  must_not_modify:  # 既存ファイルの編集・上書き・削除の禁止 — 必要な場合のみ
    - knowledge/raw/**
  must_not_reference: # 正式コードから参照してはならない領域 — 必要な場合のみ
    - .tmp/**
```

`.tmp/` は独立したrouteではなく、すべてのrouteで利用できる横断的な一時作業領域として判定する。
`none` は独立した分類ではなく、永続的な正本を新設・変更しないことを表す。
`must_update`、`must_run`、`must_set`、`must_preserve` はProjectの状態遷移を検証する項目であり、
該当する変化がないケースでは省略できる。
参照部分は `AGENTS.md#相互参照` の `<repository-relative-path>#<target>` に従う。
`must_set` の `=<期待値>` は参照先に期待する状態を表すEval固有の表記であり、参照先自体には含めない。

## Projectケースの最低条件

既存Projectを扱うケースは、原則として次を検証する。

- `AGENTS.md`、`projects/README.md`、対象の `PROJECT.md`、`STATE.md` を着手前に読む。
- 現在の目標と検証結果が、対象の `PROJECT.md#PC-xx`（停止・完了状態の確認では `PROJECT.md#status`）を参照する。
- 個別タスクだけを理由に `PROJECT.md` を変更しない。
- 成果・決定・失敗・ブロッカーが変わった場合は `STATE.md` を更新する。
- 完了報告前に `PROJECT.md` が指定する検証を実行する。
- 失敗・却下済みの方法を新しい根拠なしに繰り返さない。
- `finite` の全完了条件を検証した場合だけ `status: completed` にする。
- `continuous` の現在目標を検証し、次目標が事前定義済みなら `STATE.md` を自動更新する。
- 状態を更新しても、目的、成果契約、判断原則を勝手に変更しない。

Evalsは経路、読み書き、コマンド実行という行動の不変条件を検証する。
成果物の内容品質は、各Projectの完了条件または成功指標、品質基準、検証方法、
固定検証スクリプトで担保する。

## 実行

ケースの `request` をエージェントに与え、実際に読み書きしたパスが `expect` を満たすか確認する。
ケースが参照する入力データは `fixtures/` に置く。`fixture:` がある場合は、そのディレクトリの内容を
リポジトリ直下へ重ねた隔離コピーでケースを実行し、元の作業ツリーを変更しない。

このリポジトリに含まれる `tools/validate-agent-directory.sh` は、必須ファイル、テンプレート見出し、
Project fixture、必須ケースの存在を静的に点検する。モデルに依頼を実行させる行動Evals自体とは別物である。
