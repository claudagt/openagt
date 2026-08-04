# skills/ — 分析・判定手順の正本

Skill Routeを確定した後に読む。Knowledgeは「何が分かっているか」、Skillは「どう処理するか」、
Projectは「何を作り残すか」を所有する。

## 対象の選択

1. 利用者がSkill名または`SKILL.md`のパスを明示したらそれを優先する。
2. 未指定なら`tools/find-context.sh --route skill --limit 5 -- <query>`で候補を得る。
3. 通常候補は`status: active`だけとし、`_template/`を候補にしない。
4. 実行するSkillを1件に確定してから、その`SKILL.md`を最後まで読む。
5. catalog、検索snippet、descriptionだけでSkillを実行しない。

手動の全Skill一覧は持たない。各`SKILL.md`のfrontmatterが正本で、全件catalogはそこから再生成する。

## frontmatterと状態

```yaml
---
name: skill-name
description: 発動条件が分かる200文字以内の一行説明
status: active
aliases: [別名]
---
```

- `name`はSkillディレクトリ名と一致させる。
- `status`は`active | deprecated | retired`だけを使う。
- deprecatedはactiveな後継`SKILL.md`への`replaced_by`を持たせる。
- retiredは実行しない。deprecatedは明示的な互換性確認以外では後継を使う。
- 状態変更のために物理移動せず、パスを維持する。

## Knowledge参照

`SKILL.md`の「使用するKnowledge」を次に分ける。

- **Required** — 実行時に必ず読む。最大3件。リポジトリ相対パスで指定する。
- **Conditional** — `条件:`と`参照:`を組にし、条件成立時だけ読む。

通常判断ではactive Knowledgeだけを使う。原資料へ遡る条件は`knowledge/KNOWLEDGE.md#原資料へ遡る条件`、
総読込予算は`AGENTS.md#Context Loading`が所有する。

## 新規作成・更新

- `_template/`をコピーし、frontmatter、発動条件、手順、出力契約、Knowledge参照を置換する。
- `_template/`自体はSkillではない。
- 利用者向け能力のコードはSkillの`candidates/`または`scripts/`が所有する。
  一時コードから固定コードへの段階は`tools/README.md#一時作業と固定化`に従う。
- 詳細方法は`references/`、再利用テンプレートは`assets/`へ委譲し、`SKILL.md`を入口として短く保つ。
- `SKILL.md`は20KiBを超えない。超える詳細は明示参照された補助ファイルへ分ける。

## 基本構造

```text
skill-name/
├── SKILL.md
├── agents/       # 表示情報
├── references/   # 必要時だけ読む詳細方法
├── assets/       # 再利用テンプレート
├── candidates/   # 未安定な再利用候補
└── scripts/      # 固定した実行・検証処理
```
