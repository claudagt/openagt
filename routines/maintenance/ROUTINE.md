# ROUTINE.md — Maintenance Routine

- id: `maintenance`
- Route: `meta`
- Owner: このAgent Workspaceのroot repository（構造、cache、validator、Routine派生状態）
- Target: 正本構造の健全性維持と、決定的に証明できる低リスク修復
- Verify: `tools/validate-agent-directory.sh`と`tools/run-routine.sh`の隔離fixture

共通規則（lock、予算、送信境界、commit/backup条件、結果語彙）は`routines/ROUTINES.md`が
所有する。本書はMaintenance固有の契約だけを持つ。

## 実行コマンド

```bash
bash tools/run-routine.sh maintenance            # 日次の標準実行
bash tools/run-routine.sh maintenance --dry-run  # 検査のみ。tracked変更・commit・backup・外部送信なし
bash tools/run-routine.sh maintenance --full     # 広域検証を強制
```

## 日次の決定的Maintenance

1. 実行rootを確定し、instance lockを取得する。
2. working tree、index、untracked、branch、HEADを確認し、base SHAを記録する。
   cleanでなければ`SKIPPED`する。
3. `tools/build-context-cache.sh --check-routing`でcache鮮度を確認し、欠損・staleの
   場合だけ`tools/build-context-cache.sh`で1回再生成して再確認する。
4. 標準validator `tools/validate-agent-directory.sh`を実行する。
5. 自分が所有する`.agent-cache/routines/**`のrun logとstale lockだけを限定的に保守する。
6. machine-readableな結果を出力する。

Knowledge LOGへは追記しない。LOGのローテーションは`tools/append-knowledge-log.sh`の
契約が所有し、変更のない日次実行で発火させない。`STATE.md`もNOOPでは更新しない。

## 広域検証の周期

毎日のSchedulerを1つ登録するだけで運用できるよう、full検証はExecutorが自律判定する。

- `.agent-cache/routines/state/`の最終成功時刻から7日以上経過、記録なし、または`--full`
  指定で、`--full` validatorを実行する。
- 導入済みAgentでプレースホルダー（`<agent-name>`等）が解消済みの場合は`--strict`も
  併用する。公開スケルトンの意図されたプレースホルダーをstrict通過のために書き換えない。

## NOOP

決定的検査が合格し、actionable findingもtracked変更もない場合は`ROUTINE_NOOP`で終了し、
Provider呼び出し、tracked log作成、`STATE.md`更新、空commit、backup、pushを行わない。

## optional reasoningと修復境界

推論はvalidatorの具体的なFAILがある場合だけ、`routines/ROUTINES.md`の条件下で1回起動する。
自動修復してよいのは、診断contextへ明示的に含めた、root Gitが所有する既存tracked
UTF-8テキストへの次の低リスク修復だけである。

- validatorが特定したMarkdown schema違反・frontmatter不備
- validatorが特定した壊れた相対参照
- 決定的に証明できる重複参照
- 既存正本の内容を変えないformat修正

新規作成、削除、改名、binary、実行属性、shell script、validator、eval、`AGENTS.md`、
`PROJECT.md`、`STATE.md`、ガバナンス正本、`.env*`、`knowledge/raw/**`、
`knowledge/wiki/logs/**`、Project outputs、Independent repositoryへの変更候補は
自動適用せず`BLOCKED`とする。適用前に隔離snapshotでvalidatorを実行し、realへの適用後も
再検証する。real検証に失敗したら、自分が変更したファイルだけを開始時HEADから復元する。

## commitとbackup

修復がrealで検証合格した場合だけ、そのファイルだけのscoped commitを1つ作る。
commit後のbackupは`tools/BACKUP.md`の既存trigger（通常は`--root-only`）に従う。
remote未設定ならbackupを実行せず、その事実だけを報告する。
