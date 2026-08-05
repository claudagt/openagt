# projects/AGENTS.md — Project作業の入口

Project Routeの入口。最小手順だけを持ち、詳細は`projects/PROJECTS.md`が所有する。

## 着手

1. 対象を一つに確定する。明示パスがなければ`tools/find-context.sh --route project --limit 5`で
   `active`候補を得る。明示依頼なく新設しない。
2. `projects/<name>/`を作業cwdにする。所有Gitによらずこれが唯一のProject rootである。
3. `git -C projects/<name> rev-parse --show-toplevel`でGit所有境界を判定する。
4. 対象`AGENTS.md`（あれば）、`PROJECT.md`全文、`STATE.md`の順に読む。
5. 対象契約（`PROJECT.md#PC-xx`か`#status`）と合格条件を特定する。
6. Docs Routeの条件に一致した`ARCHITECTURE.md`と`docs/<DOMAIN>.md`、Required参照だけを読む。

## Git所有境界

- toplevelがAgent Workspace root: Embedded。commit先はroot Git。
- toplevelが`projects/<name>/`自身: Independent。commit先はProject固有Git。
- 解決できない場合だけ`projects/REPOSITORIES.md`を読み、materializeへ進む。
- 書込対象はどちらも`projects/<name>/**`。一sessionで二つのGit rootへcommitしない。
- 本体sessionはregistryを書かず、root sessionは本体を書かない。handoff後に
  root sessionが`projects/REPOSITORIES.md`の`revision`だけを更新する。

## 実行と完了

- 成果契約の範囲で最小かつ完全な変更を行う。目的、ゴール、完了条件、成功指標、固定制約は
  利用者の明示時だけ変更する。
- `PROJECT.md`の検証方法と合格条件を実行し、未実行の検証を合格扱いしない。
- 状態が変わった同じ作業内で`STATE.md`を更新し、結果、証拠、未完了を区別して報告する。

## projects/PROJECTS.mdを読む条件

Project新設、状態遷移、契約種別の変更、Independent昇格・移行、remote操作、docs構造、
個別`AGENTS.md`の設置、構造保守、復旧、規約変更、明示参照。
