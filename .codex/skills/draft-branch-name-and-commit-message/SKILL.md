---
name: draft-branch-name-and-commit-message
description: staged / unstaged / untracked の現在差分を確認し、.branch_name_template に従ったブランチ名と .commit_template に従ったコミットメッセージ案を作成する。Git操作やファイル変更は行わない。
---

# Draft Branch And Commit

## Job

現在の Git 変更内容から、ブランチ名とコミットメッセージ案を作成する。

対象は以下すべて。

- staged changes
- unstaged changes
- untracked files

## Inputs

- `git status --short`
- `git diff --cached`
- `git diff`
- untracked files
- `.branch_name_template`
- `.commit_template`

## Outputs

- `.branch_name_template` に従った推奨ブランチ名
- `.commit_template` に従ったコミットメッセージ案
- 変更概要
- staged / unstaged / untracked の状態
- 注意事項

## Rules

- ファイルを変更しない。
- branch 作成、commit、push はしない。
- staged だけ、または unstaged だけで判断しない。
- untracked files も確認対象に含める。
- 現在差分だけを根拠にする。
- ブランチ名は `.branch_name_template` に従う。
- コミットメッセージは `.commit_template` に従う。
- unrelated な変更が混在する場合は、コミット分割が必要な旨を Notes に書く。

## Steps

1. 現在差分を確認する。

```bash
git status --short
git diff --cached
git diff
```

2. untracked files があれば、ファイル名と必要最小限の内容を確認する。

3. `.branch_name_template` を確認する。

4. `.commit_template` を確認する。

5. 変更内容を分類する。

分類例:

- docs
- test
- refactor
- fix
- feat
- chore
- build
- ci
- style
- perf
- security

6. `.branch_name_template` に従ってブランチ名を1つ提案する。

7. `.commit_template` に従ってコミットメッセージ案を作成する。

## Report

```text
Recommended branch:
- ...

Commit message:
...

Changed files summary:
- ...

State:
- staged: ...
- unstaged: ...
- untracked: ...

Notes:
- ...
```
