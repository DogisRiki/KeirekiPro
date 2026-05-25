---
name: post-issue-plan-comment
description: Issue番号を受け取り、GitHub MCPで該当IssueにPlanをそのままコメント投稿する。Planの作成・修正・実装・ファイル変更は行わない。
---

# Post Issue Plan Comment

## Job

指定されたIssueに、作成済みのPlanをコメントとして投稿する。

## Rules

- Issue番号がない場合は停止する。
- 投稿するPlan本文がない場合は停止する。
- GitHub MCPで対象Issueを確認する。
- Plan本文は原則そのまま投稿する。
- Planの内容を勝手に要約・修正・追記しない。
- ファイル変更、実装、branch作成、commit、pushは行わない。

## Output

- 日本語で投稿結果を報告する。
- 投稿先Issue番号を明記する。
- ファイル変更・実装・branch作成・commit・pushを行っていないことを明記する。
