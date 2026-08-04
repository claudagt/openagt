# projects/AGENTS.md — Project作業の入口

Project Routeを確定したら読む。共通の最小手順だけを持ち、詳細は`projects/README.md`、
各Projectの契約と状態は`PROJECT.md`と`STATE.md`が所有する。

## 着手

1. 対象Projectを一つに確定する。明示パスがなければ`tools/find-context.sh --route project --limit 5`で
   `active`候補を得る。
2. 対象ディレクトリに`AGENTS.md`があれば先に読む。
3. `PROJECT.md`、次に`STATE.md`を読む。
4. 現在の対象契約（`PROJECT.md#PC-xx`または`PROJECT.md#status`）と合格条件を特定する。
5. Required参照だけを着手時に読み、Conditionalは記載条件が成立した場合だけ読む。

## 実行と完了

- 成果契約の範囲で最小かつ完全な変更を行い、品質基準を弱めない。
- `PROJECT.md`の検証方法と現在目標の合格条件を実行する。未実行の検証を合格と推測しない。
- 状態が変わった場合は同じ作業内で`STATE.md`を更新する。
- 目的、ゴール、継続的使命、完了条件、成功指標、判断原則、非ゴール、固定決定は、利用者が変更を
  明示した場合だけ変更する。
- 達成結果、検証証拠、未完了・ブロッカーを区別して報告する。

## 個別ProjectのAGENTS.md

任意であり、Project固有の作業差分だけを持つ。契約と状態は`PROJECT.md`と`STATE.md`が所有し、
目的、ゴール、使命、完了条件、成功指標、現在目標、現在状態、検証結果、参照一覧を書かない。
2,048 bytes以内とし、同階層に`@AGENTS.md`だけの`CLAUDE.md`を置く。Embedded限定。
下位の`AGENTS.md`は上位規則と`PROJECT.md`の成果契約を弱めない。

## projects/README.mdを読む条件

Project新設、状態遷移、finite/continuous契約の変更、repository mode、Embedded/Satellite移行、
構造の保守、復旧、Project規約の変更、正本からの明示参照。
