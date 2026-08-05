# projects/AGENTS.md — Project作業の入口

Project Routeの入口。詳細は`projects/PROJECTS.md`が所有する。

## 着手

1. 対象を一つに確定する。明示パスがなければ`tools/find-context.sh --route project --limit 5`。
   明示依頼なく新設しない。
2. 作業cwdは`projects/<name>/`（所有Gitによらず唯一のProject root）。
3. `git -C projects/<name> rev-parse --show-toplevel`でGit所有境界を判定する。
4. `AGENTS.md`（あれば）→`PROJECT.md`全文→`STATE.md`の順に読む。
5. 対象契約（`PROJECT.md#PC-xx`か`#status`）と合格条件を特定する。
6. 成立したDocs Route条件の正本とRequired参照だけを読む。

## Git所有境界

- toplevel=Workspace root: Embedded。commit先はroot Git。
- toplevel=`projects/<name>/`自身: Independent。commit先はProject固有Git。
- 解決不能時だけ`projects/REPOSITORIES.md`を読みmaterializeへ進む。
- 書込対象は常に`projects/<name>/**`。
- 本体sessionはregistryを書かず、root sessionは本体を書かない。

## 実行と完了

- 成果契約の範囲で最小かつ完全な変更を行う。契約自体の変更は`projects/LIFECYCLE.md#人間が決める遷移`。
- `PROJECT.md`の検証を実行し、未実行の検証を合格扱いしない。
- 状態が変わった同じ作業内で`STATE.md`を更新。
- 検証合格後はscoped commitまで確認なしで完結し、結果、証拠、commit、未完了を区別して事後報告する。
  条件と停止は`tools/TOOLS.md#自律実行の標準完了`が所有。

## PROJECTS.mdを読む条件

Project新設、状態遷移、契約種別変更、Independent昇格・移行、remote操作、docs構造、
個別`AGENTS.md`設置、構造保守、復旧、規約変更、明示参照。
