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
- **Single Writer** — エージェント1体につき、書込可能な稼働マシンは常に1台だけ。他マシンのcloneは
  復旧または移行が完了するまで書込禁止とする。
- **Hub** — agent-directory本体。Embedded Projectの履歴と、Satellite Projectの契約・採用revisionを持つ。
- **Embedded Project** — `repository_mode: embedded`の通常Project。正本と履歴はHubのルートGitが持つ。
- **Satellite Repository** — `repository_mode: satellite`で宣言された独立リポジトリ。Hub backupの対象外で、
  コード、tests、Workflow、release、`ARCHITECTURE.md`、`docs/`、Git履歴はSatellite側が持つ。
  昇格条件と宣言形式は`projects/PROJECTS.md#repository-mode`が所有する。
- **Workspace Recovery Tuple** — HubのRecovery Pointと、各SatelliteのURL・branch・採用commit SHAの組。
  `BACKUP_OK`はHub backupの成功だけを表し、Satellite本体のバックアップ成功を表さない。

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
- Satellite本体。作業cloneはagent-directoryの外へ置き、バックアップはSatellite側が持つ。
  Hubは`PROJECT.md`のremote宣言と`STATE.md`の採用commit SHAだけを保全する。

永続正本を`.gitignore`へ追加してバックアップ対象外にすることは禁止する。対象外にしたい情報は、
そもそも正本として置かない。

宣言の有無やignore状態にかかわらず、ネストGitリポジトリは`nested-git-repository`、submoduleは
`unsupported-submodule`でToolが停止する。
エージェントは追加、削除、ignore、submodule化のいずれでも回避せず、外部リポジトリとして宣言するか
どうかを利用者へ確認する。

## リポジトリ構成

- エージェント1体につきGitHub Privateリポジトリを1つ用意する。共用しない。
- 公開スケルトンへ実運用データをpushしない。スケルトンの`origin`は`template`へ改名するか削除する。
- remote名の既定値は`backup`、branchは`main`とする。
- GitHub Web UI、Codespaces、別マシンからremoteを直接編集しない。remoteは常にpush先であり編集先ではない。
- Private可視性はセットアップ契約であり、利用者が作成時に確認する。Toolは可視性を照会・変更しない。

## backup Tool

```bash
bash tools/backup-to-github.sh
bash tools/backup-to-github.sh --remote backup --branch main
bash tools/backup-to-github.sh --remote backup --branch main --dry-run
```

前提条件は次である。ひとつでも満たさない場合、Toolは何も変更せず停止する。

1. `AGENTS.md`と`tools/validate-agent-directory.sh`を持つGitリポジトリrootで実行している。
2. detached HEADでない。
3. 現在branchが指定branchである。
4. 指定remoteが設定済みである。
5. index、tracked working tree、未追跡の非ignoreファイルがすべて空である。
6. `git stash`が空である。
7. 指定branchから到達できないローカルbranch commitがない。
8. `.tmp/`、`.agent-cache/`、`.env`実値、`.DS_Store`がGit追跡されていない。
9. submoduleとGit LFSを検出しない。
10. 100MiB以上の到達可能blobがない。
11. Satelliteの宣言とRepository Stateが整合し、Hub側に重複sourceがない。
12. 各Satelliteの採用commit SHAを宣言remoteから隔離一時repoへ取得できる。
13. Hubのremote branchが未作成であるか、remote SHAがローカルHEADのancestorである。

出力はstdoutの1行が機械可読な結果、stderrの`DETAIL:`が人間向け補足である。

| 結果 | 出力 | 終了コード |
|---|---|---:|
| 成功 | `BACKUP_OK remote=backup branch=main sha=<40文字SHA>` | 0 |
| dry-run成功 | `BACKUP_READY remote=backup branch=main sha=<40文字SHA>` | 0 |
| 停止 | `BACKUP_BLOCKED reason=<reason>`（stderr） | 非0 |

主なreason: `not-agent-directory-root`、`detached-head`、`branch-mismatch`、`missing-remote`、
`staged-changes`、`dirty-working-tree`、`untracked-files`、`stash-present`、`unreachable-local-branch`、
`forbidden-tracked-file`、`nested-git-repository`、`unsupported-submodule`、`unsupported-git-lfs`、
`oversized-git-object`、`invalid-project-repository-mode`、`invalid-satellite-declaration`、
`invalid-satellite-state`、`satellite-hub-contents`、`satellite-revision-unavailable`、
`remote-unreachable`、`remote-diverged`、`push-failed`、`remote-verification-mismatch`。

Toolはfast-forward pushだけを`HEAD:refs/heads/<branch>`の明示refspecで行い、push後に`git ls-remote`で
remote SHAを再取得してローカルHEADとの完全一致を確認する。`--dry-run`はremoteへ一切書き込まない。

ToolはHub remoteを確認・pushする前に、各Satelliteの宣言、STATEの復旧tuple、Hub側の二重正本不在、
採用SHAのremote取得可能性を検証する。成功時とdry-run時は各`URL@SHA`と件数を`DETAIL:`へ列挙する。
`remote_verified_at`は採用時の証拠日であり、Toolは保存値だけを信用せず毎回remoteを再確認する。
`BACKUP_OK`/`BACKUP_READY`の1行フォーマットはHubの結果として変更しない。

`AGENT_BACKUP_MAX_BLOB_BYTES`は隔離fixture検証だけで使う閾値上書きであり、通常運用では設定しない。

## Toolが行わないこと

`git add`、`git commit`、`git stash push`、`git pull`、`git merge`、`git rebase`、`git reset`、
`git clean`、作業ツリーを変更する`git checkout`、force push、force-with-lease、mirror push、prune、
remote branch削除、tagや全branchの一括push、remote側の競合自動解決、秘密情報の保存、
GitHubリポジトリの作成・可視性変更、GitHub Actionsの実行、Satellite remoteへの書込。

Toolはコミットを作らない。バックアップ対象を確定するのは利用者のコミットであり、Toolではない。

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

1. 旧マシンで作業を確定し、`bash tools/backup-to-github.sh`が`BACKUP_OK`を出すまで実行する。
2. 旧マシンでの書込を停止する。以後、旧マシンは読み取り専用として扱う。
3. 新マシンでPrivate backupから新しいディレクトリへcloneする。
4. `git remote rename origin backup`で新マシンでもremote名を`backup`にする。
5. `git rev-parse HEAD`と`git ls-remote --heads backup main`が一致することを確認する。
6. `bash tools/validate-agent-directory.sh`を実行する。
7. `bash tools/build-context-cache.sh`で`.agent-cache/`を正本から再生成する。
8. `.env`などの秘密情報をパスワードマネージャー等の別経路から復旧する。
9. 新マシンを唯一の書込者へ昇格し、旧マシンのcloneを破棄するか読み取り専用のまま残す。

Satelliteがある場合は、新マシンで各`PROJECT.md`のURLからagent-directory外へ別々にcloneし、
`STATE.md`の採用SHAをcheckoutできることを確認する。Hub sessionとSatellite sessionは作業rootを共有しない。

昇格が完了するまで新旧両方から書き込まない。並行編集はdivergenceを作り、自動解決しない。

## 障害復旧

ローカルが失われた場合も手順は移行と同じである。相違点は次だけである。

- 旧マシンからの`BACKUP_OK`が取れないため、復旧点は最後に成功したバックアップコミットとなる。
- 最後のバックアップ以降の未コミット変更、未追跡ファイル、stashは復旧できない。失われた範囲を
  利用者へ明示する。
- 秘密情報はリポジトリに存在しないため、必ず別経路から再設定する。
- 復旧直後は`.agent-cache/`が存在しない。正本から再生成し、cacheを正本として扱わない。
- Satelliteは`STATE.md`のURL・branch・採用SHAから復旧する。branchの現在tipではなく、まず採用SHAを
  再現し、その後の更新採否は別のProject作業として扱う。

復旧後、最初の書込前に`bash tools/validate-agent-directory.sh`で構造の健全性を確認する。

## 大容量ファイル

Git LFSは既定構成へ導入しない。

- 通常のバックアップ対象はテキスト、コード、設定、文書、軽量成果物とする。
- 100MiB以上のGit objectはbackup Toolが`oversized-git-object`で停止する。
- 大量の動画、音声、モデル、データセット、生成物は通常Gitへ入れない。
- 大容量成果物が必要になった場合は、そのProjectに外部artifact保管先とchecksumを定義する。
  外部artifact保管の実装は本規約の範囲外とする。
- submoduleまたはGit LFSを検出した場合、完全バックアップを保証できないため自動処理せず、
  未対応として停止・報告する。
