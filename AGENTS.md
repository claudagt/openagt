# AGENTS.md — 最上位規約

このリポジトリで作業するエージェントは、依頼に着手する前にこのファイルに従うこと。
ここは詳細な知識や手順を持つ場所ではない。依頼を正しい場所へ振り分けるルーターである。

## 自己定義

- あなたは `<agent-name>` である。役割は `<agent-role>`（例: 投資分析を支援するエージェント）。
- 作業領域はこのリポジトリ内に限定する。リポジトリ外のファイルを変更しない。
- 判断の正本はこのリポジトリのファイルである。記憶や推測より、ここに書かれた規約とデータを優先する。

`<agent-name>` などの `<...>` はプレースホルダーである。利用者は導入時に自分の名称・役割・プロジェクト名へ書き換えること。

## 依頼の振り分け

依頼を受けたら、まず次の4種類に分類し、指定の手順で作業する。

1. **知識を覚える・調べる依頼** → `knowledge/` で作業する。
   着手前に [knowledge/KNOWLEDGE.md](knowledge/KNOWLEDGE.md) を最後まで読み、その規約に従う。
2. **特定のスキルを使う依頼** → [skills/README.md](skills/README.md) で該当スキルを特定し、
   対象の `SKILL.md` を読んでから実行する。`SKILL.md` を読まずにスキルを実行しない。
3. **一時的な作業** → 中間ファイルはすべて `.tmp/` に置く。
   `.tmp/` が存在しない場合は、作業開始時に作成する。
   完了時に、残す価値のあるものは正式な保存先へ移し、それ以外は削除する。
4. **データや成果物** → 各固有プロジェクト `<project-dir>`（例: `projects/my-project/`）に置く。
   着手前に [projects/README.md](projects/README.md) を読み、その規約に従う。
   Knowledge・Skill・`.tmp/` に成果物を残さない。

分類に迷う場合は作業を始めず、利用者に確認する。

## AIメモリの並列記録

上記4分類とは別の、各作業に付随する副作用の規約。第5の分類ではない。

- 実行AIが、このリポジトリでの作業内容を自身の製品側永続メモリへ新規保存または更新した場合、
  同じ作業の中で同じ内容を `knowledge/memory/<memory-owner>.md` にも追記する。
- 記録するかどうかは実行AI自身のメモリ判断に従う。リポジトリ側で保存価値を再判定しない。
  自身のメモリへ保存しない内容を、この規約だけを理由に `knowledge/memory/` へ追加しない。
- 保存先はモデル名ではなくメモリ機構の所有者で決め、製品・実行環境名は記録内の `Source` に書く。
  OpenAI系（Codex、ChatGPTデスクトップのCodex）→ `knowledge/memory/openai.md`
  Anthropic系（Claude Code、Claude DesktopのCodeタブ）→ `knowledge/memory/anthropic.md`
- この並列記録では、通常のKnowledge取り込み（`raw/`・`research/`・`wiki/` への分類・知識化）を行わず、
  `wiki/index.md`・`wiki/log.md` も更新しない。完全に同一の内容がすでにある場合だけ追記を省略できる。
- 秘密情報は製品側メモリにもリポジトリ側メモリにも保存しない。

詳細は [knowledge/KNOWLEDGE.md](knowledge/KNOWLEDGE.md) の `memory/` 節に従う。

## 禁止事項

- 秘密情報（APIキー、トークン、パスワード、接続文字列）を表示・保存・コミットしない。
  実際の値は `.env` にのみ置き、`.env.example` にはプレースホルダーだけを書く。
- `knowledge/raw/` と `knowledge/research/` の既存ファイルを編集・上書き・削除しない。
- 依頼されていない機能・抽象化・依存関係を追加しない。
- 実行・検証していないことを、完了したと報告しない。

## 参照順序

1. 利用者の明示的な指示
2. この `AGENTS.md`
3. 各正本（`knowledge/KNOWLEDGE.md`、`skills/README.md`、`projects/README.md`、各 `SKILL.md`）
4. 各ディレクトリ内の `README.md`

矛盾がある場合は上位を優先し、矛盾があった事実を利用者に報告する。
