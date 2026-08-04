# projects/AGENTS.md — Project作業の入口

Project Routeを確定したら読む。共通の最小手順だけを持ち、詳細は`projects/PROJECTS.md`が所有する。

## 着手

1. 対象Projectを一つに確定する。明示パスがなければ`tools/find-context.sh --route project --limit 5`で
   `active`候補を得る。明示依頼なしに新設しない。
2. 対象ディレクトリに`AGENTS.md`があれば`PROJECT.md`より先に読む。作業差分と条件付きDocs Routeだけを
   持つ差分ファイルであり、契約と状態を複製しない。
3. `PROJECT.md`、次に`STATE.md`を読み、対象契約（`PROJECT.md#PC-xx`または`#status`）と合格条件を特定する。
4. Docs Routeの条件に一致した`ARCHITECTURE.md`と`docs/<DOMAIN>.md`だけを読む。
   `docs/**`の一括読込とDomain Canon全件読込をしない。
5. Required参照だけを着手時に読み、Conditionalは記載条件が成立した場合だけ読む。

## 実行と完了

- 成果契約の範囲で最小かつ完全な変更を行い、品質基準を弱めない。
- `PROJECT.md`の検証方法と現在目標の合格条件を実行する。未実行の検証を合格と推測しない。
- 目的、ゴール、使命、完了条件、成功指標、固定制約は利用者の明示時だけ変更する。
- 状態が変わった場合は同じ作業内で`STATE.md`を更新する。
- 達成結果、検証証拠、未完了・ブロッカーを区別して報告する。

## projects/PROJECTS.mdを読む条件

Project新設、状態遷移、finite/continuous契約の変更、repository mode、Embedded/Satellite移行、
Project docs構造の設計、個別`AGENTS.md`の設置条件、構造保守、復旧、Project規約の変更、正本からの明示参照。
