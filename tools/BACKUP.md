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
  リポジトリ内に動的な最終バックアップSHAファイルを作らず、Tool出力と`git ls-remote`から再確認する。
- **Agent Workspace** — agent-directoryのツリー全体。root repositoryと、materializeされた
  全Independent repositoryを含む。
- **root repository** — Agent Workspace rootのGit。Embedded Projectの履歴とattachment registryを持つ。
- **Embedded Project** — `projects/<name>/**`をroot Gitが所有する通常Project。
- **Independent Repository** — `projects/REPOSITORIES.md`へ登録され、`projects/<name>/`自体を
  top-levelとして通常cloneされた独立リポジトリ。契約、状態、docs、コード、Git履歴をすべて持つ。
  昇格条件と登録形式は`projects/PROJECTS.md#Attachment`が所有する。
- **Materialization** — 登録と採用revisionから`projects/<name>/`のcloneを再現すること。
- **Partial Materialization** — 一部だけが存在する状態。復旧途中のdegraded stateとしてだけ許し、
  workspace全体のbackup成功として扱わない。
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
- Independent repository本体。cloneは`projects/.gitignore`のmanaged blockでignoreされ、履歴の保全は
  そのrepositoryのremoteが持つ。rootは`projects/REPOSITORIES.md`のentryだけを保全する。
  ただし既定scopeでは、root pushの前に各Independent repositoryが実際にremoteから復旧可能かを監査する。

永続正本を`.gitignore`へ追加してバックアップ対象外にすることは禁止する。対象外にしたい情報は、
そもそも正本として置かない。

許可されるnested Gitは、登録済みIndependent Projectの`projects/<name>/.git/`だけである。
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

1. `AGENTS.md`と`tools/validate-agent-directory.sh`を持つGitリポジトリrootで実行し、detached HEADでなく、
   現在branchが指定branchで、指定remoteが設定済みである。
2. index、tracked working tree、未追跡の非ignoreファイル、`git stash`がすべて空である。
3. 指定branchから到達できないローカルbranch commitがない。
4. `.tmp/`、`.agent-cache/`、`.env`実値、`.DS_Store`がGit追跡されていない。
5. 登録済みIndependent以外のnested Git、submodule、Git LFSがなく、100MiB以上の到達可能blobもない。
6. `projects/REPOSITORIES.md`の構造と、`projects/.gitignore`のmanaged blockが登録集合と一致する。
7. root indexが登録済み`projects/<name>/`配下のpathもmode 160000のgitlinkも持たない。
8. 旧`projects/<name>/repository/`、旧repository frontmatter、旧`## Repository State`が残っていない。
9. rootのremote branchが未作成であるか、remote SHAがローカルHEADのancestorである。

`--root-only`でも6〜8の静的境界は検査する。workspace scopeでは、さらに各Independent repositoryを
次の順で監査する。子cloneをfetch、checkout、reset等で変形しない。remote refsとlocal refsの到達性は
一時bare repositoryで検査する。

1. **attachment** — `projects/<name>/`に存在し、targetと`.git`がsymlinkでなく、`.git`が実directoryで
   （`.git` fileは非対応）、toplevelと`remote.origin.url`が登録と完全一致する。
2. **構造** — submodule、追加のnested Git、Git LFSがなく、HEADに`PROJECT.md`と`STATE.md`が存在する。
3. **cleanliness** — staged、tracked dirty、非ignoreのuntracked、stashがない。
4. **到達性** — remoteへ到達でき採用revisionをfetchでき、HEADが採用revisionと一致し、HEADと全local
   branch tipがremote headまたはtagから到達でき、local-onlyなtagがない。

構造的に非対応な状態（2）はcleanliness（3）より先に判定する。未追跡ファイルとして報告してしまうと
原因が隠れるためである。

主なroot reason: `not-agent-directory-root`、`detached-head`、`branch-mismatch`、`missing-remote`、
`staged-changes`、`dirty-working-tree`、`untracked-files`、`stash-present`、`unreachable-local-branch`、
`forbidden-tracked-file`、`nested-git-repository`、`unsupported-submodule`、`unsupported-git-lfs`、
`oversized-git-object`、`invalid-registry`、`invalid-ignore-projection`、
`deprecated-repository-layout`、`remote-unreachable`、`remote-diverged`、`push-failed`、
`remote-verification-mismatch`。

Independent関連のreason: `missing-independent-repository`、`repository-path-symlink`、
`repository-gitfile-unsupported`、`repository-origin-mismatch`、`repository-toplevel-mismatch`、
`root-tracks-independent-repository`、`unsupported-root-gitlink`、`workspace-partially-materialized`、
`independent-nested-repository`、`independent-submodule-unsupported`、`independent-git-lfs-unsupported`、
`independent-contract-missing`、`independent-staged-changes`、`independent-dirty-working-tree`、
`independent-untracked-files`、`independent-stash-present`、`independent-head-not-adopted`、
`independent-revision-unavailable`、`independent-unpushed-commit`、
`independent-unreachable-local-branch`、`independent-unpushed-tag`、`independent-remote-unreachable`。

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

## remote操作の分担

`AGENTS.md#禁止事項`のfetch、pull、push禁止はroot repositoryを対象とする。root remoteへのpushは
このToolだけが行い、Independent repositoryへは決してpushしない。Independent側のfetchと通常pushは
`projects/<name>/`をrootとするIndependent sessionが行い、条件は
`projects/PROJECTS.md#Remote操作の境界`が所有する。

registryの`repository_url`には認証情報、query、fragment、`file://`、ローカルpathを書かない。Toolはこれらと
`-`で始まるURLを`invalid-registry`で拒否し、報告経路でもuserinfoのpasswordを伏せる。
`AGENT_ALLOW_LOCAL_REPOSITORY_URL=true`はローカルbare remoteを使う隔離fixture専用の上書きである。

## Single Writer

Single WriterはAgent単位ではなくGitリポジトリ単位の制約である。

- 同じrepositoryへ同時に書き込むWriterを持たない。
- 異なるIndependent repositoryは並行して進めてよい。
- `projects/REPOSITORIES.md`の採用revisionは、child sessionのSHA handoffが完了した後にroot sessionが
  更新する。
- materializationまたはmigrationの実行中は、対象repositoryのWriterを停止する。

## root での `git clean`

登録済みIndependent Projectの`projects/<name>/`はroot Gitからignoreされている。次はrootで実行しない。

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
6. `bash tools/materialize-project-repositories.sh --all`で全Independent repositoryを揃える。
7. `bash tools/validate-agent-directory.sh`を実行する。
8. `bash tools/build-context-cache.sh`で`.agent-cache/`を正本から再生成する。
9. `.env`などの秘密情報をパスワードマネージャー等の別経路から復旧する。
10. 新マシンを唯一の書込者へ昇格し、旧マシンのcloneを破棄するか読み取り専用のまま残す。

Independent repositoryは`projects/<name>/`自体へ通常cloneし、agent-directoryの外や下位階層へ置かない。
root sessionとIndependent sessionは同じGit rootへ書き込まない。全件が揃うまではpartial materializationである。

昇格が完了するまで新旧両方から書き込まない。並行編集はdivergenceを作り、自動解決しない。

## 障害復旧

ローカルが失われた場合も手順は移行と同じである。相違点は次だけである。

- 旧マシンからの`WORKSPACE_BACKUP_OK`が取れないため、復旧点は最後に成功したバックアップコミットとなる。
- 最後のバックアップ以降の未コミット変更、未追跡ファイル、stashは復旧できない。失われた範囲を
  利用者へ明示する。
- 秘密情報はリポジトリに存在しないため、必ず別経路から再設定する。
- 復旧直後は`.agent-cache/`が存在しない。正本から再生成し、cacheを正本として扱わない。
- 復旧直後は登録済みの`projects/<name>/`も存在しない。`projects/REPOSITORIES.md`の`repository_url`と
  採用SHAからmaterializerで再現する。branchの現在tipではなく、まず採用SHAを再現し、その後の更新採否は
  別のProject作業として扱う。

復旧後、最初の書込前に`bash tools/validate-agent-directory.sh`で構造の健全性を確認する。

## 旧構造からの移行

Project rootは`projects/<name>/`だけである。次の二つの旧方式は残さず併存も認めず、検出時は
`deprecated-repository-layout`として扱う。

### A. `projects/<name>/repository/`方式

root Gitが`PROJECT.md`と`STATE.md`を持ち、child Gitが`repository/`にある構造からの移行。

1. rootとchildの全Writerを停止し、rootでcheckpointコミットを確定する。
2. child repositoryのdirty、staged、untracked、stash、全branch、全tag、未pushを監査する。
3. root側`PROJECT.md`と`STATE.md`から旧repository fieldと`## Repository State`を除いた内容をchild repoへ移す。
4. child repoで両ファイルを含めて検証、commit、`origin`へ通常pushし、commit SHAを取得する。
5. rootへregistry entryと`projects/.gitignore`のmanaged entryを追加する。
6. root indexから旧`PROJECT.md`と`STATE.md`を削除し、root commitを作成する。
7. child cloneを一時安全pathへ退避する。
8. `projects/<name>/`を消失させない形で、child clone全体を一段上へ移動する。
9. `.git`が`projects/<name>/.git/`にあること、`PROJECT.md`、`STATE.md`、`origin`、HEAD、全refを再確認する。
10. validator、cache、`bash tools/backup-to-github.sh --dry-run`を実行する。
11. `bash tools/backup-to-github.sh`が`WORKSPACE_BACKUP_OK`を出すことを確認する。
12. 利用者の明示承認を得た後だけ旧一時copyを削除する。

### B. agent-directory外の旧clone

外部cloneも最終的にclone全体を`projects/<name>/`へ移す。手順はAの2〜12と同じで、差分は移動元が
ツリー外である点だけである。cleanで全refがremote-backedなsourceに限り、fresh cloneで置き換えてよい。

どちらでも、dirty、staged、untracked、stash、未pushが残るcloneをfresh cloneで置換せず、reset、clean、
stash作成、force pushで移行しない。旧copyの削除は、新cloneが実`.git`と一致する`origin`を持ち、旧copyの
全refがそこかremoteから到達でき、旧copyがcleanで、利用者が明示承認した場合だけ行う。マシン固有の
source pathはCLI入力と移行手順の中だけで使い、正本へ保存しない。

## 大容量ファイル

Git LFSは既定構成へ導入しない。

- 通常のバックアップ対象はテキスト、コード、設定、文書、軽量成果物とする。
- 100MiB以上のGit objectはbackup Toolが`oversized-git-object`で停止する。
- 大量の動画、音声、モデル、データセット、生成物は通常Gitへ入れない。
- 大容量成果物が必要になった場合は、そのProjectに外部artifact保管先とchecksumを定義する。
  外部artifact保管の実装は本規約の範囲外とする。
- submoduleまたはGit LFSを検出した場合、完全バックアップを保証できないため自動処理せず、
  未対応として停止・報告する。
