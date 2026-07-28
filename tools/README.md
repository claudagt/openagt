# tools/ — 構造保守の道具

このディレクトリ構造そのものを点検・保守するスクリプトを置く。

## Skillとの分離

```text
skills/ = 利用者の依頼を処理する能力
tools/  = このディレクトリ自体を保守する道具
```

分離の軸は「道具か能力か」ではなく「誰に仕えるか」。利用者に仕えるスクリプトは各スキルの `scripts/` に従属させ、構造それ自体に仕えるスクリプトだけをここに置く。依頼のルーティング対象にならない点で、`tools/` は `evals/` と同じメタ層に属する。

コードの段階と片付けは `AGENTS.md` に従う。構造保守の再利用候補だけを
`tools/candidates/`、固定Toolだけを `tools/` 直下に置く。

## 対象となる処理

- `knowledge/wiki/index.md` と実ファイルの不一致検出
- ウィキリンク切れの検出
- `raw/`・`research/` への不適切な混入チェック
- 新しいSkill・プロジェクトの雛形生成

スクリプトは最初の自動化が必要になった時点で追加する。先回りして作らない。

## 構造検証

`validate-agent-directory.sh` は依存関係なしで、Projectの `finite` / `continuous` 契約、
`STATE.md` の構造、Evals、秘密を含み得る環境ファイルのGit追跡を点検する。

```bash
bash tools/validate-agent-directory.sh
```

終了コード0と `PASS: agent-directory structure is valid` が合格条件。
Project内の未置換プレースホルダーは常に検査する。このテンプレートを実エージェント用にコピーした後は
`--strict` を付け、`AGENTS.md` の自己定義も置換済みか確認する。
Gitリポジトリのルートでない場合、Git追跡の点検だけは `SKIP` と明示される。
