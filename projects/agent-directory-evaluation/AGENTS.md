# agent-directory-evaluation — 作業差分

契約は`PROJECT.md`、状態は`STATE.md`が所有する。

## Project Docs Route

条件に一致した正本だけを読む。

| 条件 | 読む正本 |
|---|---|
| 評価run・grading・比較・採否・PR昇格・policy参照 | `docs/EVALUATION.md` |
| harness保守・script構成・sandbox配置・trace形式 | `docs/HARNESS.md` |

## 実行

- 検証は`bash scripts/verify.sh`（repository root起点）で行う。
- 評価runの実行は`scripts/run-eval.sh`（段階評価driver、`docs/EVALUATION.md#段階評価`）
  だけを入口とし、対話sessionがバッチ実行へ張り付かない。
- 評価sessionのwrite先はOpenAGT root Gitのみ。subjectはOS一時領域のclean clone
  （明示SHA、`scripts/make-sandbox.sh`）とし、root継承ファイルを評価しない。
- subjectからOpenAGT repositoryを読ませず、grader・過去result・比較reportを渡さない。
  benchmark中のnetworkは原則無効（必要taskはallowlist）。
- public境界: commit・`runs/`・PR本文へはsanitized済み素材のみ。privateデータ・秘密情報
  （実値は`.env*`のみ）を持ち込まない。

## 外部操作（upstream PR）

- Draft PR作成は昇格条件充足時のみ、別のPromotion session（fresh agent-directory clone
  だけへwrite）で行う。1 sessionで両Git rootへwriteしない。
- merge・approve・自動close・上流default branchへの直接変更・force pushを行わない。
- policy・Hard Gate・MDE変更は人間の明示決定のみ（`docs/EVALUATION.md#評価policy変更`）。
