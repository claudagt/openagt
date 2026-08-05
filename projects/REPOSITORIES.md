# REPOSITORIES — Independent Project Registry

Independent Projectのattachmentと復旧情報だけを持つ。
Projectの目的、成果契約、status、mode、現在状態は各Project自身の
`PROJECT.md`と`STATE.md`が所有する。

Project rootはEmbeddedもIndependentも`projects/<name>/`であり、pathはnameから自明なので保持しない。
`projects/.gitignore`のmanaged blockはこの登録集合から導出する派生projectionであり、正本ではない。
昇格条件、session境界、remote操作、移行手順は[projects/PROJECTS.md](PROJECTS.md)が所有する。

### entry形式

```markdown
## `data-pipeline`

- repository_url: `git@github.com:owner/data-pipeline.git`
- repository_reason: `automation`
- revision: `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa`
```

- 見出しは``## `<name>` ``だけとし、`<name>`は`projects/<name>/`のディレクトリ名と一致させる。
- entryはname昇順。名前を重複させない。
- fieldは`repository_url`、`repository_reason`、`revision`の3つを各1回。過不足も追加も許さない。
- `repository_url`は認証情報、query、fragment、`file://`、絶対・相対のローカルpathを含まない。
  `git@host:owner/repository.git`、`ssh://git@host/owner/repository.git`、
  `https://host/owner/repository.git`の形だけを使う。
- `revision`はremoteへpush済みの40文字lowercase commit SHA。Independent sessionのhandoff後に
  root sessionだけが更新する。
- `repository_default_branch`とpathは持たない。description、status、mode、現在目標を複製しない。
- entryが0件でもこのファイルは存在してよい。

### 派生projection

`projects/.gitignore`のmanaged blockは、この登録集合からnameを`/<name>/`の形で昇順に写したものである。
registryを変更した同じroot commitで更新し、集合が完全一致しない状態を残さない。

```gitignore
# Derived from projects/REPOSITORIES.md.
# BEGIN INDEPENDENT PROJECTS
/data-pipeline/
# END INDEPENDENT PROJECTS
```

### repository_reason

独立repoが必要になる境界だけを理由にする。

- `automation` — Actions、Pages、Packages、Dependabot、Webhook、外部デプロイ
- `distribution` — OSS公開、tag、Release、packageやbinaryの配布
- `collaboration` — 外部共同編集、Pull Request、Issue運用
- `access` — 異なるvisibility、権限、Secrets、branch protection
- `identity` — 外部サービスや利用者が固定repo URLを参照
- `upstream` — fork、upstream追従、他システムからの依存
- `retention` — rootと異なる履歴保持・export・削除・監査方針、または実測されたGit履歴上の復旧問題

### 登録

現在、Independent Projectは登録されていない。
