# KNOWLEDGE.md — Knowledge運用の正本

Knowledge Routeを確定した後にこのファイルを最後まで読む。この規約は`knowledge/`全体へ適用する。

## 構造と正本性

```text
knowledge/
├── KNOWLEDGE.md
├── raw/                    # 内部で生まれた不変の原記録
├── research/               # 外部から取得した不変の原資料
└── wiki/
    ├── index.md            # 分野・主要hubへの小型ルートマップ
    ├── guide.md            # 人間向け案内
    ├── log.md              # 現在の変更履歴セグメント
    ├── logs/               # 閉鎖済みの不変ログ
    ├── _template/          # source/topicの雛形
    ├── sources/            # 資料別Knowledge。1資料1ページ
    └── topics/             # 複数資料・判断を統合したKnowledge
```

`raw/`、`research/`、`sources/`、`topics/`はいずれも正本である。sources/topicsには要約、判断、推論が含まれ、
原資料から同一内容を再生成できない。検索TSV、DB、snippet、製品側AIメモリだけが再生成可能な派生物である。

## 保存先

1. 利用者や運用内部で生まれた原文、判断、決定、仮説、観測は`raw/`へ新規保存する。
2. 論文、記事、契約、外部資料は取得元を記録し、内容を変えず`research/`へ新規保存する。
3. 1資料を読み解いたKnowledgeは`sources/`、複数資料・内部経験を統合したKnowledgeは`topics/`へ置く。

成果物はProject、手順はSkillが所有する。製品側の永続メモリは正本から派生する任意のキャッシュであり、
永続化する内容は先にこの判定でリポジトリへ保存する。両者が矛盾したらリポジトリを優先する。
秘密情報はどちらにも保存しない。

## 不変規則

- `raw/`と`research/`の既存ファイルを編集、上書き、削除、改名しない。訂正・追記は新規原資料とWiki側で行う。
- 外部資料へ要約、翻訳、推論を混ぜない。
- 秘密情報を保存しない。

## 候補探索と読込

- 照会・取り込み前に`tools/find-context.sh --route knowledge --limit 5 -- <query>`で候補を得る。
- 通常検索は`status: active`だけを対象にし、最初は上位3ページ、追加後も最大6ページまでとする。
  追加は不足する根拠を具体化できる場合だけ1件ずつ行う。
- 取り込みは既存候補を最大5件確認し、新規作成、既存更新、統合、supersedeのいずれかを選ぶ。
  重複確認のための全件読込をしない。
- `index.md`や派生catalogの全件読込を候補選択に使わない。
- `superseded`、`archived`、`retired`を通常判断に使わない。旧ページを明示された場合は
  `superseded_by`が示すactiveページを優先する。
- `log.md`、`logs/`、Git履歴は、監査、復旧、過去判断の確認、利用者の明示依頼を除き読まない。
- 検索結果だけで回答せず、採用したKnowledge正本を読む。24KiB超の部分読込と総読込予算は
  `AGENTS.md#Context Loading`に従う。

### 原資料へ遡る条件

`raw/`、`research/`へ遡るのは次のいずれかがある場合だけとする。

- 原資料そのものの確認
- 正確な引用、数値、契約、仕様の確認
- Knowledge間の衝突、またはKnowledgeの根拠不足
- ProjectまたはSkillからの明示参照

## Wiki frontmatter

sources/topicsの各ページは`_template/`を使い、少なくとも次を持つ。

```yaml
---
summary: 候補選択に使う一行説明
status: active
aliases: [別名, English alias]
---
```

- `summary`は200文字以内の一行とし、タブを含めない。
- `aliases`は一行の配列にし、タブ、改行、重複を含めない。
- statusは`active | superseded | archived | retired`だけを使う。
- `superseded`は存在するactiveページへの`superseded_by`を必須とする。
- `review_after`を使う場合は`YYYY-MM-DD`とする。日付到達は自動失効ではなく見直しの合図である。

## 情報の区別

Wikiでは次を混ぜずに書く。

- **原資料の内容** — ファイルパスとページ・見出し・行などの位置を示す。
- **利用者の見解** — 利用者の判断と明示する。
- **AIの推論** — 推論と明示し、前提と根拠へリンクする。
- **運用ルール** — 適用範囲を示し命令形で書く。

出典のない事実主張を書かない。不確実性、反対証拠、適用範囲、有効期間を失わない。

## 作成・更新・統合

- ファイル名は小文字ケバブケースとし、パスを恒久IDとして維持する。
- sourcesは書誌、原資料リンク、要約、重要主張と位置、数値、資料の限界を持つ。
- topicsは複数sourcesまたは内部原記録を統合し、判断・推論を根拠へ遡れるようにする。
- 同じ意味のactiveページを増やさず、既存更新、統合、supersedeを優先する。

統合時は次を行う。

1. 統合先activeページへ固有情報、根拠、反対証拠、判断、適用範囲を移す。
2. 旧ページは削除せず`status: superseded`と`superseded_by`を設定する。
3. 参照切れと置換先のactive状態を検証する。
4. 表現だけの旧版や重複引用はGit履歴へ委ねてよいが、現在も意味のある情報をGit履歴だけへ退避しない。

## index

`wiki/index.md`は全件台帳ではなく、主要分野、hub、重要なactiveページへの人間向け入口である。

- 1項目1行、最大50項目、8KiB以内とする。
- raw/researchや全Wikiを個別登録しない。全件一覧は`.agent-cache/catalog.tsv`へ再生成する。
- 項目追加・削除は入口としての価値が変わる場合だけ行う。

## log

- Knowledgeの永続変更だけを`tools/append-knowledge-log.sh`で記録する。`log.md`を直接追記しない。
- 実行例: `tools/append-knowledge-log.sh --type ingest --target knowledge/wiki/topics/example.md --summary "要約"`
- 種別は`ingest | lint | migration | supersede | archive | retire`とする。通常照会は記録しない。
- logと過去logは既定の読込対象にしない。
- Toolは追記後に128KiBまたは1,000記録へ達すると、自動で`logs/YYYY-QN.md`へ閉じて現在logを初期化する。
  同じ四半期の2本目以降は`YYYY-QN-02.md`のように採番する。利用者が手作業で分割しない。
- 閉鎖済みlogは編集、削除、改名しない。

## archive・retire・削除

- `archived`は歴史照会だけ、`retired`は判断利用禁止とする。状態変更のために物理移動しない。
- 非activeページの削除は、参照ゼロ、代替または保持先確認、利用者の明示承認が揃った場合だけ行う。
- raw/researchと閉鎖済みlogは削除しない。

## lint

`bash tools/validate-agent-directory.sh --full`でmetadata、状態、参照、サイズ、log、派生catalog再生成を検査する。
意味的な重複は自動削除せず、人間が統合を判断する候補に留める。
