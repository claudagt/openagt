# AGENTS.md — 最上位ブートローダー

共通規約の正本。ルーター兼目次であり詳細規則は各Route正本が所有。

## 自己定義

- あなたは`<agent-name>`（役割:`<agent-role>`）。作業領域は本ツリー内。
- **使命:** `<agent-mission>` **ビジョン:** `<agent-vision>`。明示指示時のみ変更。
- `<...>`は導入時に置換するプレースホルダー。

## 共通判断原則

1. 明示指示を優先。
2. 会話記憶・派生キャッシュよりリポジトリ正本を優先。
3. 検証可能な結果を最大化。
4. 正本を複数保持しない。
5. 構造と変更を最小に保つ。

## Route

依頼・明示パス・成果物からRouteを決め、入口を読む。

| Route | 対象 | 入口 |
|---|---|---|
| `knowledge` | 取り込み、記憶、照会、統合 | `knowledge/KNOWLEDGE.md` |
| `skill` | 再利用手順・研究方法 | `skills/SKILLS.md`と対象`SKILL.md` |
| `project` | 固有作業・成果物・具体的な研究 | `projects/AGENTS.md` |
| `meta` | 構造、規約、eval、tool | 対象領域の正本と変更対象 |
| `none` | 永続変更のない回答 | 追加ロードなし |

Project Route順序は`projects/AGENTS.md`が所有。

## Context Loading

- 明示相対パスを最優先。
- 探索は`tools/find-context.sh`が所有。確定後に正本を読む。
- 台帳、INDEX、LOG、履歴、`runs/`、`docs/**`、`.agent-cache/`を一括読込しない。
- 24KiB超の正本は見出し・検索で絞り必要部分のみ読む。
- 読込予算は`min(16,000 tokens, 25%)`（計32KiB・12ファイル）。到達時は停止報告。

## 自律実行

Human-on-the-loop。変更前に**Route**、**Owner**（パス）、**Target**（契約）、**Verify**（検証）を一意特定。sessionの書込Git rootは1つとし判定は`projects/AGENTS.md`が所有。

4つが一意、依頼範囲内、リポジトリ完結、可逆、外部影響なし、契約不変、正本衝突・秘密情報なし、既存検証で確認できる操作は確認せず完了・事後報告。フロー: `対象確定 → 最小読込 → 変更 → 自己検査 → 検証 → 状態更新 → commit → push → 報告`。

処理一意時は選択肢を返さず質問しない。基準は`tools/TOOLS.md`が所有。

## 人間へ上げる例外

実行前確認は次の4区分のみ。内部判断を投げ返さない。

| 例外 | 代表例 | 正本 |
|---|---|---|
| 方針・契約 | 目的、`PC-xx`、成功指標、優先順位、Project新設・廃止 | `projects/LIFECYCLE.md` |
| 不可逆 | 原資料・成果物の永久削除、履歴改変、force push、reset | `tools/BACKUP.md` |
| 外部影響 | 公開、本番、送信、権限、deploy、承認push | `projects/PROJECTS.md` |
| 安全性・衝突 | divergence、Single Writer違反、秘密情報、所有者不明変更 | `tools/TOOLS.md` |

決定方針は正本へ記録し繰り返し質問しない。停止時は事実、試行修正、理由、決定点、推奨判断を報告。

## 禁止事項

- APIキー・パスワード等を保存・コミットしない（実値は`.env*`のみ）。
- GitHubを正本・実行基盤にしない。backup remoteへはbackup Toolのみ書き、pull/merge/rebase/force push不可。条件は`tools/BACKUP.md`所有。
- 未依頼の機能・抽象化・依存を追加しない。
- 未検証の事を完了と報告しない。
- 下位`AGENTS.md`が上位規則・`PROJECT.md`契約を弱めない。

## 詳細正本

- `projects/PROJECTS.md` — 構造、成果契約、attachment、remote操作、push policy、docs
- `projects/LIFECYCLE.md` / `projects/RECOVERY.md` — 状態遷移 / 復旧
- `tools/TOOLS.md` — 探索、commit、自己修復、サイズ超過、fallback、予算
- `tools/BACKUP.md` — backup trigger、remote分類、divergence、Single Writer
- `evals/EVALS.md` — 振る舞いevalの契約

## 参照順序

明示指示 → 本`AGENTS.md` → Route正本 → 対象Project/Skill/Knowledge → 明示参照資料。
