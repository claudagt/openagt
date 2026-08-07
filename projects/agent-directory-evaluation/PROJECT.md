---
name: agent-directory-evaluation
description: agent-directoryを固定policy・公開証拠・再現可能な比較で継続評価し、条件を満たした改善だけを上流Draft PRへ昇格する評価専用Project
status: active
mode: continuous
---

# `agent-directory-evaluation`

## 目的

上流`claudagt/agent-directory`（汎用AIエージェント構造テンプレート）を、固定された評価基準と
公開可能な証拠で継続評価し、思いつきではなく再現可能な実験に基づく改善だけを上流へ提案する。
利用者と上流コミュニティに、検証済みで独立再現可能な改善根拠を提供する。

## 継続的使命

> 固定された評価policy、観測、同条件比較、停止条件に基づき、agent-directoryを
> 必要な場合だけ改善し、`NO_CHANGE`を正しい成果として扱い続ける。

この使命は、利用者が変更を明示した場合だけ変更する。個別タスクや実装都合から変更しない。

## 成功指標

- **PC-01** 全runが、source SHA、candidate SHA、policy hash、suite hash、grader hash、execution config hashの組から第三者が再現できる
- **PC-02** Hard Gate違反を主要指標・効率指標で相殺せず、違反candidateを常にREJECTEDとする
- **PC-03** 単発の失敗観測だけを根拠とした上流変更提案がゼロである
- **PC-04** 特定モデル（単一execution config）だけの改善を汎用上流変更として採用しない
- **PC-05** privateデータ・秘密情報のpublic成果物（commit、runs/、PR本文）への混入がゼロである
- **PC-06** 改善量より複雑性増加が大きい変更を採用しない
- **PC-07** 明確な停止条件を持ち、MDE未満・停止条件充足時に`NO_CHANGE`/`STABLE`で正しく停止する
- **PC-08** `docs/EVALUATION.md`のPR昇格条件をすべて満たした提案だけがDraft PRへ昇格する
- **PC-09** OpenAGT自身による上流のmerge・approve・default branch直接変更がゼロである

## 見直し・終了条件

- 上流`agent-directory`がarchive・廃止された場合、利用者へ報告しpaused遷移を提案する。
- 評価policyの版更新（人間の明示決定）ごとに、A/A再実行とbaseline再取得で本Projectの
  前提を見直す。
- 2回連続のfull cycleでELIGIBLE変更がなく、Hard GateとTier 0が安定していれば`STABLE`とし、
  常時の問題探索を停止する（再開は新しい実運用失敗または人間の指示）。

## 判断原則

- 自己申告よりharness・clientが観測した事実を優先する。取得できない値は`unknown`とし0にしない。
- candidate合格よりevaluatorの健全性（A/A安定、条件・hash・traceの完全性）を優先する。
- 実験条件が欠けたrunはcandidate失敗ではなくINVALIDとして扱う。
- 迷った場合は変更しない側（`NO_CHANGE`）へ倒す。

## 非ゴール

- 上流リポジトリの直接変更、非Draft PRの作成、merge、リリース判断。
- 評価由来Issueの自動作成（利用者の明示決定と再現済み証拠を伴うものだけ、
  `docs/EVALUATION.md#上流Issue`の条件下で作成できる。2026-08-07利用者決定）。
  Workspace運用で観測したfield報告は`tools/UPSTREAM.md#事前承認済み送信`の
  事前承認済み経路で送る（2026-08-07利用者決定、policy v1.0.4）。
- モデル間の絶対性能比較・leaderboard・単一総合スコアの作成。
- 全eval caseの実モデル網羅実行、大量の新case量産、prompt自動最適化。
- 常駐daemon、dashboard、DB、vector DB、message queue、GitHub Actionsでの評価実行。
- privateな個別Agent運用データの取り込み・評価素材化。

## 制約・固定決定

- 初期source revision: `8325b185fb9410bff44cf6ec9a9b99246fe8cc0f`（作業開始時のagent-directory/main。
  runごとの評価対象SHAはrun manifestが記録し、現在のbaselineは`STATE.md`が持つ）。
- 評価対象は常にOS一時領域のclean clone（明示SHA）。OpenAGT rootの継承ファイルを評価しない。
- 評価sessionのwrite先はOpenAGT root Gitのみ。Promotion sessionのwrite先はfresh
  agent-directory cloneのみ。1 sessionで両Git rootへwriteしない。
- 評価policy・Hard Gate・MDE・benchmarkの変更は人間の明示決定のみ。candidate評価と
  policy変更を同じcommit・同じrunで行わない。
- 上流へのpush・merge・force push・mirror push、upstream/mainの自動merge・自動rebaseを行わない。
- 素材はpublic上流ソース、synthetic fixture、完全sanitized事例のみ。秘密情報の実値は
  `.env*`（Git管理外）のみ。
- Draft PR作成は条件充足時のstanding approvalの範囲で行い、それ以外の外部影響は事前確認する。

## 品質基準

- 全runにmanifest（hash一式）と観測traceが揃っている。欠落runを判定へ使わない。
- 未実行の検証を合格として報告しない。実client未構成の項目は「未構成・未検証」と明記する。
- `runs/`へはsanitized済み証拠だけを置く。生log・完全なprovider response・debug dumpは
  `.agent-cache/`またはOS一時領域が持つ。
- 検証はscripts/の決定的検査で行い、目視・自己申告で代替しない。

## 入力

- 上流`agent-directory`の明示SHA（`upstream` remote経由で取得）。
- 継承済みbenchmark素材: `evals/EVALS.md`、`evals/cases/`、`evals/fixtures/`
  （参照時はsource revision、case path、content hashを記録する）。
- `fixtures/`のsynthetic run record（harness自己検証用）。

## 使用するKnowledge

### Required

- なし

### Conditional

- なし（評価で得た一般知見の昇格が必要になった場合に追加する）

## 使用するSkill

### Required

- なし

### Conditional

- なし

## 成果物

- `docs/EVALUATION.md` — 評価policyの唯一の正本
- `scripts/` — evaluator自己検証と最小harness（manifest、sandbox、grading、比較）
- `runs/` — 採否判断・回帰・再現に必要なsanitized証拠（実runが発生した場合だけ作成）
- 条件を満たした場合のみ: 上流へのDraft PR（Promotion session経由、run ID・evidence commit・結果表を記載）

## 検証方法

- 実行手順: `bash projects/agent-directory-evaluation/scripts/verify.sh`（repository rootから実行）
- 合格条件: shell/Python構文検査、manifest決定性、known-good runのPASS、known-bad run
  （scope外write・未検証完了）のHard Gate FAIL、hash欠落のINVALID、同一SHA A/AのNO_CHANGE、
  subject sandbox隔離検査、secret scanのすべてが合格し`VERIFY_OK`を出力する
- 不合格時の扱い: 失敗した検査名と証拠をSTATE.mdの未完了・ブロッカーへ記録し、合格扱いしない
- 必要な環境変数: なし
- 使用した入力: `fixtures/`のsynthetic run record
