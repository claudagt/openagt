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
`.tmp/`は独立Routeではない。参照は`tools/TOOLS.md#相互参照`に従い、`=<期待値>`はeval固有の表記とする。

## fixtures

`cases/`のケースが参照する入力データは`fixtures/`へ置く。

- 1ケースが使うデータは、ケース名または対象状態と同じサブディレクトリにまとめる。
- 複数ケースが同じ初期状態を検証する場合は共有fixtureを一つ置き、各ケースの`fixture:`から参照する。
- fixture内はリポジトリ直下へ重ねられる構造にする。
- 必要になったケースだけがfixtureを持つ。空のfixtureを先に生成しない。
- fixture内のProjectもvalidatorの構造検査対象であり、契約、状態、docs命名の規則を満たす。

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
  repository mode、移行、復旧、規約保守、docs構造の設計、明示参照のいずれかがある場合だけ読む。
- 個別Projectの`AGENTS.md`へ成果契約、現在状態、Domain Canonの本文を書かず、`PROJECT.md`、`STATE.md`、
  `docs/<DOMAIN>.md`へ書く。
- 現在目標と検証結果が`PROJECT.md#PC-xx`または`PROJECT.md#status`を参照する。
- Requiredだけを読み、条件未成立のConditionalを読まない。
- 個別タスクで成果契約を変更しない。状態変化は同じ作業内で`STATE.md`へ反映する。
- 完了報告前に指定検証を実行する。
- finiteは全条件の検証後だけcompleted、continuousは現在目標達成だけでcompletedにしない。
- paused/completed/retiredは明示参照、再開、監査、保守以外で候補にしない。

## Project docsケースの最低条件

- `ARCHITECTURE.md`または`docs/`があるEmbedded Projectでは、個別`AGENTS.md`が条件付きDocs Routeを持ち、
  そこを経由して正本へ進む。
- 条件に一致したDomain Canonだけを初期入口として読む。Design作業では`docs/DESIGN.md`だけを読み、
  `docs/**`を一括読込せずDomain Canonを全件読まない。
- モジュール、依存、データフロー、境界の変更では`ARCHITECTURE.md`を読む。
- `<DOMAIN>_SENSE.md`は定性的判断の正本であり、必須仕様、数値合格条件、コマンド、現在状態の保存先に
  しない。ハード仕様は`PROJECT.md`または`docs/<DOMAIN>.md`が所有する。
- `docs/README.md`、`docs/NOTES.md`、`docs/MISC.md`のような汎用正本を作らない。
- Satellite Hub側へ`docs/`、`ARCHITECTURE.md`、個別`AGENTS.md`を複製しない。

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
