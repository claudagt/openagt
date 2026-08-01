# Project lifecycle

Projectの状態遷移、完了、停止、廃止、削除を扱うときだけ読む。通常のactive Project作業では読まない。

## 状態

- `active` — 進行中。通常検索の対象。
- `paused` — 停止中。明示的な再開・監査以外では変更しない。
- `completed` — finiteの全完了条件を検証済み。追加作業を行わない。
- `retired` — 利用者が廃止を決定済み。通常検索から除外する。

continuousに`completed`は使わない。completed Projectの拡張は、新しいProjectまたは利用者が明示した次フェーズとして扱い、
AIが自動でactiveへ戻さない。

## 状態遷移

- finiteをcompletedにする前に、すべての`PROJECT.md#PC-xx`の検証証拠を確認する。
- completed時は`STATE.md`の現在目標と次の一手を「なし（Project完了）」にし、検証結果を現在の完了証拠へ更新する。
- continuousの現在目標は、合格条件が検証済みで、次目標が正本から一意に決まる場合だけAIが更新できる。
- 次目標に新しい戦略、優先順位、予算、品質上のトレードオフが必要なら利用者へ確認する。
- paused、retiredへの変更と再開は利用者の明示指示を必要とする。

## 物理位置

検索除外のためにProjectを`_archive/`へ移動しない。completed、paused、retiredも元のパスに残し、状態で絞る。
別パスへの移行が必要な場合は、すべての参照先、移行表、復旧方法を用意し、利用者の承認後に行う。

## 削除

Project削除は次をすべて満たす場合だけ行う。

1. `status: retired`である。
2. 利用者が削除を明示承認した後、`PROJECT.md`へ`deletion_approved: true`を記録して一度コミットしている。
3. リポジトリ内からの参照がゼロである。
4. 保持すべき成果物と監査証拠の保存先を`artifacts_retained_at: <repository-relative-path>`として記録している。
   保持対象がなく、`outputs/`にも追跡ファイルがない場合だけ`artifacts_retained_at: none`を使う。
5. 削除対象をread-only検査で確定し、Gitで復元可能である。

削除は、上記metadataを持つretired状態をbase commitに残した次の変更で行う。validatorは`--base`で
base側の状態、承認、成果物保持先、現在の参照ゼロ、ディレクトリ全削除を検査する。

pausedやcompletedを「古い」「動きがない」という理由だけで削除しない。
