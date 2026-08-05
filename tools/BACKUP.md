# BACKUP.md — 遠隔バックアップと復旧

バックアップ、復旧、マシン移行、バックアップ監査を利用者が明示した場合だけ、meta Routeとして読む。
通常のKnowledge、Skill、Project作業では読まない。

## 目的と非ゴール

目的は、ローカルの稼働正本が失われたときに、最後に確定したGitコミットからリポジトリを再構築できる
遠隔コピーを1つ持つことである。

非ゴールは次である。これらは実装しない。

- GitHubを正本、実行キュー、タスク管理、デプロイ経路、クラウド同期基盤にすること
- 複数マシンの双方向同期と自動競合解決
- GitHub Actions、CI、cron、launchd、Git hook、常駐daemonによる自動バックアップ
- バックアップ履歴の正本、`BACKUP_STATUS.md`、remote SHAを保存する追跡ファイル
- 秘密情報、`.tmp/`、`.agent-cache/`、製品側AIメモリの遠隔保存

## 用語

- **Active Local Copy** — 現在稼働中のローカルリポジトリ。唯一の書込可能な正本。通常作業はここだけで完結する。
- **Remote Backup** — エージェント1体ごとに用意する別のGitHub Privateリポジトリ。最後に正常pushされた
  `main`コミットの受動的な復旧コピー。直接編集しない。
- **Recovery Point** — backup Toolがpush後に確認した、ローカルHEADとremote `main`が一致するコミットSHA。
  リポジトリ内に動的な最終バックアップSHAファイルを作らない。結果はToolの標準出力と
  `git ls-remote`のremote refから再確認する。
- **Agent Workspace** — agent-directoryのツリー全体。root repositoryと、固定pathへmaterializeされた
  全Independent repositoryを含む。
- **root repository** — Agent Workspace rootのGit。Embedded Projectの履歴と、Independent Projectの
  契約・採用revisionを持つ。
- **Embedded Project** — `repository_mode: embedded`の通常Project。正本と履歴はroot Gitが持つ。
- **Independent Repository** — `repository_mode: independent`で宣言され、`projects/<name>/repository/`へ
  通常cloneされた独立リポジトリ。コード、tests、release設定、`ARCHITECTURE.md`、`docs/`、Git履歴を持つ。
  昇格条件と宣言形式は`projects/PROJECTS.md#repository-mode`が所有する。
- **Materialization** — 宣言と採用revisionから固定pathのcloneを再現すること。
  `bash tools/materialize-project-repositories.sh --all`が行う。
- **Partial Materialization** — 一部のIndependent repositoryだけが存在する状態。復旧途中のdegraded state
  としてだけ許し、workspace全体のbackup成功として扱わない。
- **Single Writer** — Gitリポジトリ単位の制約。同じrepositoryへ同時に書き込むWriterを持たない。

## バックアップ対象

`main`のコミットから到達可能なGit管理ファイルと履歴を対象とする。存在するなら次はGit追跡されていること。

- `AGENTS.md`、`README.md`、各領域の規約
- `knowledge/`の正本、`skills/`の正本
- `projects/`の契約、状態、`ARCHITECTURE.md`、`docs/`、入力、成果物、`runs/`、`scripts/`
- `evals/`、`tools/`
- その他、リポジトリ内で永続正本または永続成果物として分類されたファイル

対象外は次である。復旧は別経路で行う。

- `.env`、`.env.local`などの秘密情報、SSH鍵、Git認証情報、ローカルGit設定
- `.tmp/`、`.agent-cache/`、`.DS_Store`、製品側AIメモリ
- 未コミット変更、未追跡ファイル、`git stash`
- `main`から到達できないローカルbranch、reflogだけに存在するコミット
- Independent repository本体。cloneは`projects/*/repository/`でignoreされ、履歴の保全は
  そのrepositoryのremoteが持つ。rootは`PROJECT.md`のremote宣言と`STATE.md`の採用commit SHAだけを保全する。
  ただし既定scopeでは、root pushの前に各Independent repositoryが実際にremoteから復旧可能かを監査する。

永続正本を`.gitignore`へ追加してバックアップ対象外にすることは禁止する。対象外にしたい情報は、
そもそも正本として置かない。

許可されるnested Gitは、宣言済みIndependent Projectの`projects/<name>/repository/.git/`だけである。
それ以外のネストGitリポジトリはignore状態にかかわらず`nested-git-repository`、submoduleは
`unsupported-submodule`でToolが停止する。
エージェントは追加、削除、ignore、submodule化のいずれでも回避せず、Independent Projectとして宣言するか
どうかを利用者へ確認する。

## リポジトリ構成

- エージェント1体につきGitHub Privateリポジトリを1つ用意する。共用しない。
- 公開スケルトンへ実運用データをpushしない。スケルトンの`origin`は`template`へ改名するか削除する。
- remote名の既定値は`backup`、branchは`main`とする。
- GitHub Web UI、Codespaces、別マシンからremoteを直接編集しない。remoteは常にpush先であり編集先ではない。
- Private可視性はセットアップ契約であり、利用者が作成時に確認する。Toolは可視性を照会・変更しない。

## backup Tool

Toolは1つだけであり、scopeをoptionで選ぶ。別のbackup Toolを追加しない。

### 既定scope — workspace

```bash
bash tools/backup-to-github.sh
bash tools/backup-to-github.sh --dry-run
```

root repositoryをpushする前に、全Independent repositoryを監査する。Independent repository自体はpushしない。
全repositoryがremoteから復旧可能な場合だけ成功とする。partial materializationでは停止する。

| 結果 | 出力 | 終了コード |
|---|---|---:|
| 成功 | `WORKSPACE_BACKUP_OK remote=backup branch=main sha=<sha> independent=<count>` | 0 |
| dry-run成功 | `WORKSPACE_BACKUP_READY remote=backup branch=main sha=<sha> independent=<count>` | 0 |

### root-only scope

```bash
bash tools/backup-to-github.sh --root-only
bash tools/backup-to-github.sh --root-only --dry-run
```

root repositoryだけを検査・pushする。Independent repositoryのnetwork、dirty、unpushは検査しない。
静的metadataとroot ownership違反は検査する。これは明示的な部分結果であり、workspace全体の
バックアップ成功として報告しない。

| 結果 | 出力 | 終了コード |
|---|---|---:|
| 成功 | `ROOT_BACKUP_OK remote=backup branch=main sha=<sha> scope=root-only` | 0 |
| dry-run成功 | `ROOT_BACKUP_READY remote=backup branch=main sha=<sha> scope=root-only` | 0 |

### 共通

停止は両scopeとも`BACKUP_BLOCKED reason=<reason>`をstderrへ出し、終了コードを非0にする。
stdoutの1行が機械可読な結果、stderrの`DETAIL:`が人間向け補足である。

root前提条件は次である。ひとつでも満たさない場合、Toolは何も変更せず停止する。

1. `AGENTS.md`と`tools/validate-agent-directory.sh`を持つGitリポジトリrootで実行している。
2. detached HEADでない。
3. 現在branchが指定branchである。
4. 指定remoteが設定済みである。
5. index、tracked working tree、未追跡の非ignoreファイルがすべて空である。
6. `git stash`が空である。
7. 指定branchから到達できないローカルbranch commitがない。
8. `.tmp/`、`.agent-cache/`、`.env`実値、`.DS_Store`がGit追跡されていない。
9. 宣言済みIndependent以外のnested Git、submodule、Git LFSを検出しない。
10. 100MiB以上の到達可能blobがない。
11. Independentの宣言とRepository Stateが整合し、root側envelopeが余分なファイルを持たない。
12. root indexが`repository/`配下のpathもmode 160000のgitlinkも持たず、固定ignoreがある。
13. rootのremote branchが未作成であるか、remote SHAがローカルHEADのancestorである。

workspace scopeでは、さらに各Independent repositoryを次の順で監査する。子cloneをfetch、checkout、
reset等で変形しない。remote refsとlocal refsの到達性は一時bare repositoryで検査する。

1. 固定pathに存在する。
2. target、parent、`.git`がsymlinkでない。
3. `.git`が実directoryである（`.git` fileは非対応）。
4. toplevelが固定pathと完全一致する。
5. `remote.origin.url`が`PROJECT.md`の`repository_url`と完全一致する。
6. submodule、追加のnested Git、Git LFSがない。
7. staged changesがない。
8. tracked working treeがdirtyでない。
9. 非ignoreのuntracked fileがない。
10. stashがない。
11. remoteへ到達できる。
12. 採用revisionをremoteからfetchできる。
13. HEADが`STATE.md`の採用revisionと一致する。
14. HEADと全local branch tipがremote headまたはtagから到達できる。
15. local-onlyなtagがない。

構造的に非対応な状態（6）はcleanliness（7〜10）より先に判定する。未追跡ファイルとして
報告してしまうと原因が隠れるためである。

主なroot reason: `not-agent-directory-root`、`detached-head`、`branch-mismatch`、`missing-remote`、
`staged-changes`、`dirty-working-tree`、`untracked-files`、`stash-present`、`unreachable-local-branch`、
`forbidden-tracked-file`、`nested-git-repository`、`unsupported-submodule`、`unsupported-git-lfs`、
`oversized-git-object`、`invalid-project-repository-mode`、`remote-unreachable`、`remote-diverged`、
`push-failed`、`remote-verification-mismatch`。

Independentとworkspaceのreason:
`invalid-independent-declaration`、`invalid-independent-state`、`missing-independent-repository`、
`repository-path-symlink`、`repository-gitfile-unsupported`、`repository-origin-mismatch`、
`repository-toplevel-mismatch`、`root-tracks-independent-repository`、`unsupported-root-gitlink`、
`independent-nested-repository`、`independent-submodule-unsupported`、`independent-git-lfs-unsupported`、
`independent-staged-changes`、`independent-dirty-working-tree`、`independent-untracked-files`、
`independent-stash-present`、`independent-head-not-adopted`、`independent-revision-unavailable`、
`independent-unpushed-commit`、`independent-unreachable-local-branch`、`independent-unpushed-tag`、
`independent-remote-unreachable`、`workspace-partially-materialized`、`deprecated-satellite-mode`。

Toolはfast-forward pushだけを`HEAD:refs/heads/<branch>`の明示refspecで行い、push後に`git ls-remote`で
remote SHAを再取得してローカルHEADとの完全一致を確認する。`--dry-run`はremoteへ一切書き込まない。
成功時とdry-run時は各`URL@SHA`と件数を`DETAIL:`へ列挙する。Toolは保存値だけを信用せず毎回remoteを
再確認する。

`AGENT_BACKUP_MAX_BLOB_BYTES`は隔離fixture検証だけで使う閾値上書きであり、通常運用では設定しない。

## Toolが行わないこと

`git add`、`git commit`、`git stash push`、`git pull`、`git merge`、`git rebase`、`git reset`、
`git clean`、作業ツリーを変更する`git checkout`、force push、force-with-lease、mirror push、prune、
remote branch削除、tagや全branchの一括push、remote側の競合自動解決、秘密情報の保存、
GitHubリポジトリの作成・可視性変更、GitHub Actionsの実行、Independent remoteへの書込、
子cloneのfetch・checkout・reset・merge・rebase・stashによる変形。

Toolはコミットを作らない。バックアップ対象を確定するのは利用者のコミットであり、Toolではない。

## Single Writer

Single WriterはAgent単位ではなくGitリポジトリ単位の制約である。

- 同じrepositoryへ同時に書き込むWriterを持たない。
- 異なるIndependent repositoryは並行して進めてよい。
- root `STATE.md`の採用revisionは、child sessionのSHA handoffが完了した後にroot sessionが更新する。
- materializationまたはmigrationの実行中は、対象repositoryのWriterを停止する。

## root での `git clean`

Independent cloneはroot Gitからignoreされている。次はrootで実行しない。

- `git clean -x`
- `git clean -X`
- `git clean`への二つ以上の`-f`（`-ff`、`-ffd`、`-ffdx`など）

これらは未pushのIndependent commit、stash、未追跡の作業を不可逆に削除しうる。掃除が必要な場合は
対象pathを明示した最小のコマンドを利用者へ提示し、削除対象と失われる範囲を先に報告する。
危険性の検証は破棄前提の一時fixtureだけで行い、実作業rootで実行しない。

## バックアップ実行条件

次を利用者が明示した場合だけ実行する。

- バックアップを依頼された
- マシン移行を依頼された
- 破壊的変更前の復旧点作成を指示された
- チェックポイント保存を指示された

通常タスク終了後の自動pushは行わない。バックアップは通常ワークフローの完了条件ではない。
remoteの障害、未設定、到達不能はローカルタスクの検証結果と無関係であり、ローカル作業を停止させない。
バックアップ失敗をタスクの失敗として報告しない。逆に、バックアップ成功をタスクの検証成功として報告しない。

フルvalidatorの合否はバックアップの必須条件ではない。壊れた状態の保全にもバックアップを使う。
ただし秘密情報、未コミット状態、remote divergence、対象漏れ、GitHubのhard limitは停止条件とする。

## divergenceの停止

remote SHAがローカルHEADのancestorでない場合、Toolは何も変更せず`remote-diverged`で停止し、
remote SHAとlocal SHAを報告する。

このときエージェントは、pull、merge、rebase、reset、force pushのいずれも行わない。分岐は、
別マシンからの書込、GitHub上での直接編集、Single Writer違反のいずれかを意味する。原因の特定と
どちらを採用するかの決定は利用者が行う。エージェントは事実だけを報告して停止する。

## マシン移行

1. 旧マシンで作業を確定し、`bash tools/backup-to-github.sh`が`WORKSPACE_BACKUP_OK`を出すまで実行する。
2. 旧マシンでの書込を停止する。以後、旧マシンは読み取り専用として扱う。
3. 新マシンでPrivate backupから新しいディレクトリへcloneする。
4. `git remote rename origin backup`で新マシンでもremote名を`backup`にする。
5. `git rev-parse HEAD`と`git ls-remote --heads backup main`が一致することを確認する。
6. `bash tools/materialize-project-repositories.sh --all`で全Independent repositoryを固定pathへ揃える。
7. `bash tools/validate-agent-directory.sh`を実行する。
8. `bash tools/build-context-cache.sh`で`.agent-cache/`を正本から再生成する。
9. `.env`などの秘密情報をパスワードマネージャー等の別経路から復旧する。
10. 新マシンを唯一の書込者へ昇格し、旧マシンのcloneを破棄するか読み取り専用のまま残す。

Independent repositoryは`projects/<name>/repository/`の固定pathへ通常cloneし、agent-directoryの外へ
置かない。root sessionとIndependent sessionは作業rootを共有しない。全件が揃うまではpartial
materializationであり、workspace backupの成功として扱わない。

昇格が完了するまで新旧両方から書き込まない。並行編集はdivergenceを作り、自動解決しない。

## 障害復旧

ローカルが失われた場合も手順は移行と同じである。相違点は次だけである。

- 旧マシンからの`WORKSPACE_BACKUP_OK`が取れないため、復旧点は最後に成功したバックアップコミットとなる。
- 最後のバックアップ以降の未コミット変更、未追跡ファイル、stashは復旧できない。失われた範囲を
  利用者へ明示する。
- 秘密情報はリポジトリに存在しないため、必ず別経路から再設定する。
- 復旧直後は`.agent-cache/`が存在しない。正本から再生成し、cacheを正本として扱わない。
- 復旧直後は`projects/*/repository/`も存在しない。`PROJECT.md`の`repository_url`と`STATE.md`の採用SHAから
  materializerで再現する。branchの現在tipではなく、まず採用SHAを再現し、その後の更新採否は別の
  Project作業として扱う。

復旧後、最初の書込前に`bash tools/validate-agent-directory.sh`で構造の健全性を確認する。

## 旧Satellite cloneの移行

agent-directoryの外へcloneを置く旧Satellite方式は最終標準として残さない。二方式の併存も認めない。
検出時は`deprecated-satellite-mode`として扱い、次の順序で固定pathへ移行する。

1. 対象repositoryの全Writerを停止する。
2. rootでcheckpointコミットを確定する。
3. source cloneの`origin`、HEAD、`git status`、stash、全branch、未pushのcommitとtagを監査する。
4. ignore、cache prune、validatorの新ルールを先に導入する。
5. 固定target`projects/<name>/repository/`が存在しないことを確認する。
6. dirty、staged、untracked、stash、未pushがあるsourceはclone仕直しをせず、directory全体を固定pathへ移す。
7. cleanで全refがremote-backedなsourceだけ、固定pathへのfresh cloneで置き換えてよい。
8. `PROJECT.md`のmetadataを`repository_mode: independent`へ変更する。
9. `STATE.md`の`## Repository State`を採用`revision`だけへ変更する。
10. validator、cache、`bash tools/backup-to-github.sh --dry-run`を実行する。
11. rootでcommitする。
12. `bash tools/backup-to-github.sh`が`WORKSPACE_BACKUP_OK`を出すことを確認する。
13. 利用者の明示承認を得た後だけ旧cloneを削除する。

旧cloneを削除してよいのは、次をすべて満たす場合だけである。

- 固定pathのcloneが存在し、`.git`が実directoryで、`origin`が宣言と完全一致する。
- 旧cloneのHEAD、全local branch tip、全tagが、固定path側またはremoteから到達できる。
- 旧cloneにdirty、staged、untracked、stashが残っていない。
- 利用者が削除を明示承認している。

マシン固有のsource pathはCLI入力と移行手順の中だけで使い、`PROJECT.md`、`STATE.md`、その他の正本へ
保存しない。

## 大容量ファイル

Git LFSは既定構成へ導入しない。

- 通常のバックアップ対象はテキスト、コード、設定、文書、軽量成果物とする。
- 100MiB以上のGit objectはbackup Toolが`oversized-git-object`で停止する。
- 大量の動画、音声、モデル、データセット、生成物は通常Gitへ入れない。
- 大容量成果物が必要になった場合は、そのProjectに外部artifact保管先とchecksumを定義する。
  外部artifact保管の実装は本規約の範囲外とする。
- submoduleまたはGit LFSを検出した場合、完全バックアップを保証できないため自動処理せず、
  未対応として停止・報告する。
