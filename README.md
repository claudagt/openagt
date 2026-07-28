# agent-directory

AIエージェントのディレクトリ構造テンプレート。

エージェントに知識を蓄積させ、固有のスキルを習得させることで、育てながらタスクを遂行していく。

## English Overview

A directory-structure template for AI agents — accumulate knowledge, acquire skills, and grow your agent while it works.

- `AGENTS.md` — top-level mission, vision, decision principles, and routing contract
- `CLAUDE.md` — Claude Code entry point; imports `AGENTS.md` (`@AGENTS.md`)
- `knowledge/` — immutable source records (`raw/`, `research/`) turned into reusable knowledge (`wiki/`)
- `skills/` — analysis procedures with entry points (`SKILL.md`), one directory per skill
- `projects/` — long-lived work and deliverables: `PROJECT.md` defines the outcome contract and `STATE.md` carries current state
- `evals/` — behavioral QA: cases that verify routing and contract compliance
- `tools/` — scripts that maintain this directory structure itself
- `.tmp/` — isolated temporary workspace, never referenced by durable code and cleaned up when work completes

Getting started:

1. Copy or clone this repository (one copy per agent).
2. Replace the `<agent-name>` / `<agent-mission>` / `<agent-vision>` / `<project-dir>` placeholders in [AGENTS.md](AGENTS.md).
3. Add your skills by copying `skills/_template/` and register them in [skills/README.md](skills/README.md).
4. Run `bash tools/validate-agent-directory.sh --strict` to verify the instantiated agent.
5. Operate the agent, accumulating knowledge under the rules in [knowledge/KNOWLEDGE.md](knowledge/KNOWLEDGE.md).

Recommended environments: the template itself is model- and client-agnostic. The primary recommended setups are desktop local sessions — OpenAI Codex (inside the ChatGPT desktop app) and Anthropic Claude Code (Claude Desktop's Code tab) — opened on a local copy of this repository. The intended deployment is a dedicated machine per agent (e.g., a Mac mini) separate from your main computer, operated via each product's remote-connection feature from the desktop app on your main machine. Other environments (CLI, IDE extensions, cloud) also work as long as they can read the contracts.

Full documentation is in Japanese. The structure itself (directory names, file layout) is language-neutral, and the rule files are written for LLM agents, which read Japanese natively.

## 利用開始

1. このリポジトリをコピーまたはクローンする。
2. [AGENTS.md](AGENTS.md) の `<agent-name>` などのプレースホルダーを、
   自分のエージェント名・役割・使命・ビジョン・固有プロジェクトに書き換える。
3. `skills/_template/` をコピーして必要なSkillを追加し、[skills/README.md](skills/README.md) の一覧へ登録する。
4. `bash tools/validate-agent-directory.sh --strict` を実行し、初期設定と構造が合格することを確認する。
5. [knowledge/KNOWLEDGE.md](knowledge/KNOWLEDGE.md) の規約に沿ってKnowledgeを蓄積しながら運用する。

## アーキテクチャと利用例

構成は2層。操作卓となるメインマシン1台と、エージェントを動かすサブマシン群。
エージェント1体につきこの構造を1つ持たせ、サブマシンを増やせば水平に拡張できる。

```text
メインマシン（操作卓）
├── Codex Desktop ──┐
└── Claude Desktop ─┴─ 各製品のリモート接続機能でサブマシンへ

サブマシン1
├── Agent-1/agent-directory/   # エージェントごとに独立した知識・スキル・プロジェクト
├── Agent-2/agent-directory/
└── Agent-3/agent-directory/
サブマシン2
├── Agent-4/agent-directory/
└── ...
```

推論は各デスクトップ製品側で実行され、サブマシンはエージェントの作業領域
（ファイル・シェル・この構造）を担う。役割の分離が本質であり、機種やOSには依存しない。
実行環境はローカルマシンを想定する（クラウド対応は今後の視野）。
作者の想定環境はメインマシンが MacBook Pro、サブマシンが Mac mini。

## 構成

```text
agent-directory/
├── AGENTS.md               # 最上位規約 — 使命・ビジョン・共通原則・振り分け・禁止事項
├── CLAUDE.md               # Claude Code用の入口 — @AGENTS.md をインポート
├── README.md               # このファイル
├── LICENSE                 # MIT License
├── .env.example            # 環境変数のプレースホルダー
├── .tmp/                   # 一時作業領域 — Git管理外
├── knowledge/
│   ├── KNOWLEDGE.md        # Knowledge運用の正本
│   ├── raw/                # 内部で生まれた原記録 — 編集・削除しない
│   ├── research/           # 外部から取得した原資料 — 内容を変えない
│   └── wiki/               # 原資料を再利用可能な知識へ変換
│       ├── index.md        # 全体の入口
│       ├── guide.md        # 構造と使い方の案内
│       ├── log.md          # 時系列履歴
│       ├── sources/        # 資料別ノート — 1資料1ページ
│       └── topics/         # 統合知識 — 1トピック1ページ
├── skills/
│   ├── README.md           # スキル分類の正本
│   └── _template/          # 新規スキルの雛形 — コピーして使う
│       ├── SKILL.md        # 入口 — 発動条件・手順・出力契約
│       ├── agents/         # 表示情報
│       ├── references/     # 詳細な分析方法
│       ├── assets/         # テンプレート類
│       └── scripts/        # 固定化した検証・実行処理
├── projects/
│   ├── README.md           # プロジェクト運用の正本
│   └── _template/          # 新規プロジェクトの雛形
│       ├── PROJECT.md      # 成果契約 — 種別・目的・ゴールまたは使命・判断原則・検証
│       └── STATE.md        # 現在状態 — 現在の目標・合格条件・決定・次の一手・検証
├── evals/
│   ├── README.md           # 検証方法の正本
│   ├── cases/              # 検証ケース — 1ケース1ファイル
│   └── fixtures/           # ケース用の入力データ
└── tools/
    ├── README.md           # 構造保守Toolの規約
    └── validate-agent-directory.sh  # Project契約・STATE・Evals・秘密ファイル追跡の点検
```

## 役割

| 領域 | 役割 |
|------|------|
| `AGENTS.md` | 司令塔 — 依頼を正しい場所へ振り分ける |
| `knowledge/` | 記憶 — 原資料の蓄積と知識化 |
| `skills/` | 能力 — 分析方法と判定 |
| `projects/` | 仕事 — 固有プロジェクトの入力・成果物・実行記録 |
| `evals/` | 品質 — ルーティングと規約遵守の検証 |
| `tools/` | 保守 — この構造自体の点検・自動化 |
| `.tmp/` | 作業机 — 中間ファイル置き場 |

## 流れ

```text
知識を覚える依頼
  AGENTS.md → KNOWLEDGE.md → raw / research → sources → topics

分析の依頼
  AGENTS.md → skills/README.md → SKILL.md →(必要なら Wiki・原資料へ遡る)

データ・成果物の依頼
  AGENTS.md → projects/README.md → PROJECT.mdの成果契約 → STATE.mdの現在目標
  → 実行・検証 → STATE.md更新 → finiteなら完了判定、continuousなら次目標

すべての作業に付随する一時ファイル
  .tmp/ に隔離する → 正式コードから参照しない → 正式保存後または完了時に片付ける

コードのライフサイクル
  .tmp/ の一時コード → 2回目の利用で所有先の candidates/ → 3回目の利用前に固定化審査

製品側AIメモリ（各作業に付随する規約 — 独立した分類ではない）
  永続化すべき内容 → 先に上記の正本へ保存 → 必要なら製品側メモリへ写す
  （製品側メモリは正本から派生する任意のキャッシュ。矛盾したらリポジトリを優先する）
```

## Projectの成果契約

```text
使命・ビジョン = エージェント全体の長期的な方向
PROJECT.md       = Projectの目的、成果契約、固定された判断基準
STATE.md         = 現在地、現在の目標、検証結果、次の一手
```

`mode: finite` は検証可能な終了状態を達成したら `completed` にする。
`mode: continuous` は現在の目標を更新しながら継続し、Project自体を完了扱いにしない。
エージェントは両方を作業前に読み、完了条件または成功指標を前進させる作業だけを行う。
完了報告前にProject固有の検証を実行し、状態が変わった同じ作業内で `STATE.md` を更新する。
詳細は [projects/README.md](projects/README.md) を参照する。

## 推奨実行環境

このテンプレート自体は、特定のモデルやクライアントに依存しない。

主な推奨環境は、ローカルのリポジトリフォルダを開いて利用する次の2つのデスクトップ環境。

- **OpenAI Codex** — ChatGPTデスクトップアプリ内のCodex（旧Codexアプリの利用者も同様）
- **Anthropic Claude Code** — Claude DesktopのCodeタブ（Claude Code Desktop）

想定する配置は、メインの作業マシンとは別の専用マシン（Mac miniなど）で
エージェントを動かす構成（「アーキテクチャと利用例」参照）。操作は、メインマシンの各デスクトップアプリから
それぞれの製品のリモート接続機能で専用マシンへ接続し、遠隔で行う。同一マシンでの利用も可能。

推奨運用はデスクトップのローカルセッションだが、CLI・IDE拡張・クラウド環境でも、
この規約を読める場合は利用できる。特定のモデルバージョンを前提としない。
各製品側のメモリ機能は、このリポジトリが自動で有効化するものではなく、各製品側の設定に従う。

## License

[MIT](LICENSE)
