# HARNESS.md — 実行harnessの正本

評価scriptの構成、subject sandboxの配置、traceと公開証拠の形式を所有する
（policy v1.1.0で`EVALUATION.md`から責務移管、利用者決定2026-08-07）。
判定の意味定義（Hard Gate、指標、MDE、段階評価、PR昇格条件）は引き続き
`EVALUATION.md`だけが所有し、本書はその実行手段を記す。

## subject sandboxの配置

subjectはOpenAGT rootの外、かつ**`/tmp`と`$TMPDIR`の外**の専用root配下へ置く
（既定: `~/.cache/openagt-eval/`）。runごとにclean cloneを作り、run後に破棄する。

理由（2026-08-06実測、codex-cli 0.146.0 / macOS Seatbelt）: clientのsandboxは`/tmp`と
`$TMPDIR`を常に書込可能として扱うため、OS一時領域内のsubjectはHG-02（scope外write）を
OSレベルで強制できない。非tmp rootに置いてはじめてwrite root制限が効く。「作って捨てる」
性質はrun手順が担保する。生log・debug dumpの置き場は本節の対象外。

## 最小harness

新しい巨大frameworkを作らない。Python標準ライブラリとbashだけで、`scripts/`直下にflatに置く。

| script | 役割 |
|---|---|
| `scripts/verify.sh` | evaluator自身の決定的検証（構文、manifest決定性、fixture grading、隔離、secret scan） |
| `scripts/make-manifest.py` | run manifest生成（source SHA、policy/suite/grader/config hash） |
| `scripts/make-sandbox.sh` | 明示SHAからのsubject clean clone生成とremote除去・隔離検査（専用非tmp root） |
| `scripts/codex-adapter.sh` | codex clientの非対話実行、OS強制隔離、JSONL trace取得、隔離selftest |
| `scripts/responses-bridge.py` | provider未対応model向けのResponses→chat completions翻訳（localhost。bridge hashをexecution configへ記録し、秘密は転送のみで保持しない） |
| `scripts/classify-run.py` | client非依存のrun分類（OK / INFRA_UNAVAILABLE / NO_TRACE / RUN_FAILED） |
| `scripts/grade-case.py` | `evals/cases/*.yaml`の期待値と観測traceの照合（PASS / FAIL / UNVERIFIED） |
| `scripts/map-trace.py` | client固有traceの正準語彙への写像。writeはGitから観測しcoverageを記録 |
| `scripts/run-case.sh` | 1 case・1 trialの実行と証拠束生成（sandbox、overlay、trace、採点） |
| `scripts/run-eval.sh` | 段階評価driver（gate/smoke/A/B、逐次trial・早期終了・baseline cache・並列）。バッチ実行の唯一の入口 |
| `scripts/grade-run.py` | observable eventの決定的grading（PASS / FAIL / INVALID） |
| `scripts/compare-runs.py` | baseline/candidate比較とA/Aの部品。**最終判定には使わない** |
| `scripts/check-promotion.py` | 最終Promotion Gate。閾値はpolicy固定でCLIから上書きできない |

`scripts/adapters/`、`scripts/graders/`、`scripts/lib/`、`dashboard/`、`database/`、
`services/`、`packages/`は、必要性が実測されるまで作らない。

### adapter

Codex、Claude等のclient interfaceは変化しうるため、思い込みでcommandや出力形式を固定しない。
作業環境に存在するclientの実際のhelp、version、出力機能を確認してからexecution configを固定する。
利用できないclientを利用できたことにせず、取得できない値は`unknown`とする。
実client未構成でも、次はmock（synthetic fixture）で検証する。

- known-good runがPASS
- scope外writeがHard GateでFAIL
- 未検証完了がHard GateでFAIL
- policy hash差がINVALID
- 同一SHAのA/AがNO_CHANGE
- subjectからevaluator filesを読めない

実client未構成を理由に、偽のmodel結果を作らない。

## traceと公開証拠

自己申告ではなく、harnessまたはclientが観測した事実を使う。最低eventは次とする。

```text
phase / search / read / tool / write / external_effect /
question / escalation / validation / summary
```

最低限記録するもの: evaluator SHA、source baseline SHA、source candidate SHA、policy hash、
suite hash、grader hash、execution config hash、trial番号、read pathとbyte、Tool commandと
exit code、write path、Git diff、final state、validation結果、questionとescalation、wall time、
client提供のusage、validity、final decision。

- 全runの巨大な生logをGit管理しない。`runs/`へ保存するのは採否判断・回帰・再現に必要な
  sanitized証拠だけとする。
- 一時log、完全なprovider response、debug dumpは`.agent-cache/`またはOS一時領域が所有する。

## 観測の限界

harnessが構造上「観測できない」ことを固定して記録する。ここに挙げた項目は都度の所見では
なく、判定を`unverified`側へ倒す根拠である（`docs/EVALUATION.md`のUNVERIFIED規則）。

- **read**: commandからの推定で、byte数を持たない。clientが自動注入したcontextはreadとして
  数える（注入を数えないと大量の誤FAILになる）。read側のOS隔離は無い。
- **route**: 入口正本の読取から導出する。複数Routeの入口を読んで一意に決まらない場合は
  導出しない（誤ったrouteを埋めない）。
- **execution configのmodel**: 観測できない。codexの`--json`にproviderのmodelエコーが無く、
  記録は`declared`にとどまる。実在と応答modelの一致はprovider APIへの直接照会で確認する。
  execution configの他の項目も一部は`unknown`のまま残る。
- **must_report**: `report_match`パターンを持つcaseだけが採点可能で、パターンの無いslugは
  UNVERIFIEDのまま残る（`evals/EVALS.md#報告の観測`）。曖昧なキーワード照合で埋めない。
- **生log**: Git管理せずOS一時領域が持つ。`runs/`はsanitized記録だけを持つ。
