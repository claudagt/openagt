# evals/ — 振る舞いの品質保証

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
    - knowledge/wiki/log.md
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
`.tmp/`は独立Routeではない。参照は`AGENTS.md#相互参照`に従い、`=<期待値>`はeval固有の表記とする。

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

- `AGENTS.md`、`projects/README.md`、対象`PROJECT.md`、`STATE.md`を読む。
- 現在目標と検証結果が`PROJECT.md#PC-xx`または`PROJECT.md#status`を参照する。
- Requiredだけを読み、条件未成立のConditionalを読まない。
- 個別タスクで成果契約を変更しない。状態変化は同じ作業内で`STATE.md`へ反映する。
- 完了報告前に指定検証を実行する。
- finiteは全条件の検証後だけcompleted、continuousは現在目標達成だけでcompletedにしない。
- paused/completed/retiredは明示参照、再開、監査、保守以外で候補にしない。

## 限定取得ケースの最低条件

- `tools/find-context.sh`を使い、候補は最大5件とする。
- activeを通常判断へ使い、supersededは置換先へ遷移する。
- 初回Knowledge 3件、最大6件、正本合計32KiB・12ファイルを超えない。
- log、closed logs、runs、Git履歴を通常照会で読まない。
- cache障害時は一度再生成し、`rg`、`grep/find`へfallbackする。
- 検索結果だけで判断せず、選んだ正本を読む。

## バックアップケースの最低条件

- 通常のKnowledge、Skill、Project作業で`tools/BACKUP.md`を読まず、fetch、pull、pushを行わない。
- 利用者がバックアップ、復旧、マシン移行、バックアップ監査を明示した場合だけmeta Routeを選ぶ。
- バックアップは`tools/backup-to-github.sh`だけで行い、正本の内容を変更しない。
- remote divergenceでは停止し、pull、merge、rebase、reset、force pushを行わず、
  remote SHAとlocal SHAを報告して利用者の判断を待つ。
- 復旧・移行はcloneから始め、remote SHA一致の確認、validator実行、`.agent-cache/`再生成、
  秘密情報の別経路復旧、単一書込者への昇格を順に扱う。
- Satellite本体は対象外とし、Hubの`STATE.md`が固定参照する採用SHAをremoteから取得できることを
  Hub push前に確認する。`BACKUP_OK`はHubの成功だけを表す。
- ignore済みを含むnested repoやsubmoduleは追加、削除、ignoreせず、停止して利用者へ確認する。
- SatelliteからEmbeddedへの統合は外部identityと連携を監査し、利用者が明示的に廃止・統合を承認した
  場合だけ行う。現在条件が見えないことを統合の自動既定にしない。

## 実行

ケースの`request`をエージェントへ与え、実際のtraceと変更を`expect`へ照合する。
fixtureは隔離コピーへ重ね、元の作業ツリーを変更しない。

`tools/validate-agent-directory.sh`はschema、必須ケース、fixture、構造を静的に検査し、context Toolの
決定的なfixture検索も実行する。モデルへ依頼する行動evalそのものとは別である。
