# projects/AGENTS.md — Project作業の入口

Project Routeの入口。最小手順だけを持ち、詳細は`projects/PROJECTS.md`が所有する。

## 着手

1. 対象を一つに確定する。明示パスがなければ`tools/find-context.sh --route project --limit 5`で
   `active`候補を得る。明示依頼なく新設しない。
2. `PROJECT.md`の`repository_mode`を読み、次節でsession rootを確定してから書込を始める。
3. 対象に`AGENTS.md`があれば`PROJECT.md`より先に読む。契約と状態を複製しない差分ファイル。
4. `PROJECT.md`、`STATE.md`の順に読み、対象契約（`PROJECT.md#PC-xx`か`#status`）と合格条件を特定する。
5. Docs Routeの条件に一致した`ARCHITECTURE.md`と`docs/<DOMAIN>.md`、Required参照だけを読む。
   Conditionalは条件成立時だけ読む。

## Session root

- `embedded`: Agent Workspace rootがsession root。
- `independent`: root sessionは`PROJECT.md`と`STATE.md`だけを読み、本体作業は
  `projects/<name>/repository/`を唯一のGit rootとする別sessionが行う。
- Independent sessionはroot metadataを書かず、root sessionはIndependent本体を書かない。
- child SHAと検証結果のhandoff後だけroot `STATE.md`の採用revisionを更新する。
- 一sessionで二つのGit rootへcommitしない。

## 実行と完了

- 成果契約の範囲で最小かつ完全な変更を行う。目的、ゴール、完了条件、成功指標、固定制約は
  利用者の明示時だけ変更する。
- `PROJECT.md`の検証方法と合格条件を実行し、未実行の検証を合格扱いしない。
- 状態が変わった同じ作業内で`STATE.md`を更新し、結果、証拠、未完了を区別して報告する。

## projects/PROJECTS.mdを読む条件

Project新設、状態遷移、契約種別の変更、repository mode、Independent昇格・移行、docs構造、
個別`AGENTS.md`の設置、構造保守、復旧、規約変更、明示参照。
