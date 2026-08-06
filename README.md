# OpenAGT

`cloudagts/agent-directory`を継続的かつ公開・再現可能な方法で評価し、根拠のある改善だけを
上流へDraft PRとして提出する、評価専用のAIエージェント（Agent Workspace）である。

本リポジトリは[agent-directory](https://github.com/cloudagts/agent-directory)テンプレートから
instantiateされたAgent Workspaceであり、同時にそのテンプレート自体の公開評価器として運用する。
評価policy、benchmark、実行条件、比較結果、採否理由を原則公開し、単発の思いつきではなく
公開された証拠と再現可能な実験だけを上流改善の根拠とする。

## 上流との関係

```text
origin   = https://github.com/cloudagts/openagt          # OpenAGT本体（evaluator）
upstream = https://github.com/cloudagts/agent-directory  # 評価対象の取得・比較用read-only remote
```

- 初期source revision: `8325b185fb9410bff44cf6ec9a9b99246fe8cc0f`（`agent-directory/main`、2026-08-06取得）
- OpenAGTの`main`はこのrevisionをGit祖先として持つ（履歴を引き継いだのは取込時点の`main`だけで、全branch・tagのmirrorではない）
- `upstream`へはpushしない。upstream/mainの自動merge・自動rebase・force push・mirror pushを行わない
- **OpenAGTは上流のmerge権限を持たない。** Draft PRの採否は常に人間がレビューして決める

## 評価対象とevaluatorの分離

OpenAGTのroot treeは評価器（evaluator）の実行環境であり、評価対象そのものではない。
rootに継承済みのファイルを「上流の現在状態」として評価してはならない。

```text
OpenAGT repository            = evaluator、policy、runner、evidence
OS一時領域のclean clone       = subject（baseline / candidate）。明示SHAから毎回生成
```

subject sandboxはOpenAGT repositoryを読めず、grader・過去result・比較reportを受け取らない。
1つのsessionが書き込むGit rootは常に1つである（評価sessionはOpenAGTのみ、PR作成の
Promotion sessionはfresh agent-directory cloneのみ）。

## 通常運転の閉ループ

```text
上流の特定SHAを取得
→ 固定された評価policyとbenchmarkで実行
→ trace、diff、検証結果を観測
→ 失敗を再現
→ 原因所有者を判定
→ 改善仮説を作る
→ baselineとcandidateを同条件で比較
→ Hard Gateと停止条件で判定
→ 証拠をOpenAGTへ保存
→ 条件を満たした場合だけ別writer sessionでDraft PRを作成
→ 人間がレビュー
→ 人間がmergeまたは却下
```

評価policy、Hard Gate、改善指標、trial規則、A/AとMDE、停止条件、PR昇格条件の唯一の正本は
[projects/agent-directory-evaluation/docs/EVALUATION.md](projects/agent-directory-evaluation/docs/EVALUATION.md)である。
評価Projectの契約は[projects/agent-directory-evaluation/PROJECT.md](projects/agent-directory-evaluation/PROJECT.md)、
現在状態は同Projectの`STATE.md`が持つ。

主要な固定判断:

- **単一総合点を使わない。** 指標はexecution configごとに個別に読む
- **Hard Gate違反を効率指標で相殺しない。** 1件でも違反したcandidateはREJECTED
- **`NO_CHANGE`は正しい成果である。** MDE未満の差で上流変更を提案しない
- 単発失敗だけで上流変更を提案しない。特定モデルだけの改善を汎用上流変更として採用しない
- 評価Agent自身がcandidateを合格させる目的でpolicy・benchmark・grader・MDEを変更しない

## public運用の範囲

評価素材は、publicな上流ソース、synthetic fixture、または公開可能な形に完全にsanitizedした
事例だけを使う。次は**絶対に取り込まない**。

- privateな個別AIエージェントのリポジトリ、private Projectの成果物、private trace
- 利用者の非公開データ、個人情報を含む実運用記録
- API key、token、password、cookie、Authorization header（実値は`.env*`のみ、Git管理外）
- private repositoryのURLやclone情報、秘密を含むpromptまたはresponse

## 実行基盤

ローカル実行を前提とする。GitHub Actions、CI、常駐daemon、外部サービスを評価の実行基盤に
しない。GitHubの役割はOpenAGT本体の保管・公開と、上流へのDraft PR提出だけである。

## 主要な検証コマンド

```bash
# Workspace全体の構造・契約検証（instantiate済みのため--strictで合格する）
bash tools/validate-agent-directory.sh --strict --full

# 通常workの限定検証
bash tools/validate-agent-directory.sh --changed

# 評価Project固有の検証（evaluator自己検証。harnessのmock fixture検査を含む）
bash projects/agent-directory-evaluation/scripts/verify.sh
```

## Workspaceとしての構造とRoute

Workspace共通規約は[AGENTS.md](AGENTS.md)がブートローダーとして所有する。Route判定、
Context Loading、自律実行と例外、禁止事項はそちらを読む。

| Route | 対象 | 着手後に読む正本 |
|---|---|---|
| `knowledge` | 取り込み、記憶、照会、統合 | [knowledge/KNOWLEDGE.md](knowledge/KNOWLEDGE.md) |
| `skill` | 分析・判定手順、再利用可能な研究方法 | [skills/SKILLS.md](skills/SKILLS.md)と対象`SKILL.md` |
| `project` | 評価run、改善提案、成果物 | [projects/AGENTS.md](projects/AGENTS.md)、対象`PROJECT.md`、`STATE.md` |
| `meta` | 規約、テンプレート、eval、tool | 対象領域の大文字正本と変更対象 |
| `none` | 永続変更のない回答・一時作業 | 必要最小限。中間物は`.tmp/` |

継承したテンプレート構造（`knowledge/`、`skills/`、`projects/`、`routines/`、`evals/`、`tools/`）は
そのまま維持する。Attachment境界、Independent Projectの扱い、`projects/REPOSITORIES.md`の
registryは[projects/PROJECTS.md](projects/PROJECTS.md)が所有し、必要になった場合は
`bash tools/materialize-project-repositories.sh --all --check`で再現状態を検査する。

> [!WARNING]
> **Git Cleanの注意:** 登録済みIndependent Projectはroot Gitからignoreされる。rootでの
> `git clean -x`や`git clean -ffdx`はignoreされた作業を不可逆に削除しうるため原則行わない。

## コンテキスト探索

```bash
tools/find-context.sh --route project --limit 5 -- "評価"
tools/prepare-context.sh --route project --target projects/agent-directory-evaluation --class work
```

明示パスと正本の明示参照を最優先とし、検索結果は候補として扱う。詳細は
[tools/TOOLS.md](tools/TOOLS.md)と[AGENTS.md](AGENTS.md)が所有する。

## Routine（自律定期保守）

`routines/`はSchedulerがAgentを起動するTrigger層である。RoutineはRouteではなくTriggerであり、
詳細契約は[routines/ROUTINES.md](routines/ROUTINES.md)と
[routines/maintenance/ROUTINE.md](routines/maintenance/ROUTINE.md)が所有する。
推論ProviderやAPIキーなしでも決定的Maintenanceは完全に実行できる。

```bash
bash tools/run-routine.sh maintenance            # 日次: cache鮮度 + 標準validator
bash tools/run-routine.sh maintenance --dry-run  # 検査のみ。変更・commit・backup・外部送信なし
bash tools/run-routine.sh maintenance --full     # 広域検証を強制

# Scheduler登録は明示操作（macOSはlaunchd、その他はcron）
bash tools/manage-routine-schedule.sh --routine maintenance --scheduler auto --at 03:00 --print
bash tools/manage-routine-schedule.sh --routine maintenance --scheduler auto --at 03:00 --install
```

optional reasoning（`.env.example`参照）は、validatorの具体的なFAILがあるときだけ限定的な
推論支援を有効にする。設定不足でも決定的Maintenanceは失敗しない。

## ローカル正本とGitHubバックアップ

ローカルの作業コピーが唯一の書込可能な稼働正本であり、backupはタスク境界で起きる
event-drivenな操作である。backup remoteへの書込は`tools/backup-to-github.sh`だけが行い、
pull・merge・rebase・force pushを行わない。停止条件、divergence時の扱い、Single Writer、
復旧手順は[tools/BACKUP.md](tools/BACKUP.md)が所有する。

```bash
bash tools/backup-to-github.sh --dry-run
bash tools/backup-to-github.sh
```

backupの失敗は検証済みローカルcommitの成功を取り消さず、`local task` / `local commit` /
`backup` / `recoverability`を区別して報告する。

## 正本

| 正本 | 所有する内容 |
|---|---|
| [AGENTS.md](AGENTS.md) | 自己定義、共通判断原則、Route判定、Context Loading、自律実行と例外、禁止事項、目次 |
| [projects/agent-directory-evaluation/docs/EVALUATION.md](projects/agent-directory-evaluation/docs/EVALUATION.md) | 評価policy、Hard Gate、指標、trial、A/A・MDE、停止条件、PR昇格条件 |
| [knowledge/KNOWLEDGE.md](knowledge/KNOWLEDGE.md) | 四層構造、保存先、不変規則、命名、限定取得、INDEX、LOG |
| [skills/SKILLS.md](skills/SKILLS.md) | Skillの選択、frontmatter、Knowledge参照、構造 |
| [projects/AGENTS.md](projects/AGENTS.md) | Project作業共通の着手・実行・完了手順 |
| [projects/PROJECTS.md](projects/PROJECTS.md) | 成果契約、Project docs、Domain Canon、Research昇格、attachment、push policy |
| [projects/LIFECYCLE.md](projects/LIFECYCLE.md) / [projects/RECOVERY.md](projects/RECOVERY.md) | 状態遷移と削除条件 / 目的不一致からの復旧 |
| [routines/ROUTINES.md](routines/ROUTINES.md) | Routine Trigger層、Scheduler分離、送信境界、commit/backup条件 |
| [evals/EVALS.md](evals/EVALS.md) | 振る舞いevalの契約、ケースschema、fixture、最低条件 |
| [tools/TOOLS.md](tools/TOOLS.md) | Toolの入出力、自律commit、自己修復、サイズ超過、fallback、予算 |
| [tools/BACKUP.md](tools/BACKUP.md) | backup trigger、remote分類、失敗と復旧、divergence、Single Writer |

## ライセンス

[MIT License](LICENSE)（上流`agent-directory`のライセンス条件を保持する）
