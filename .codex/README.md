# Codex Setup

このドキュメントでは、Codex IDE で使用する MCP と Skills の設定を管理します。

---

# MCP Setup

このプロジェクトでは、Codex IDE から以下の MCP を使用します。

- GitHub MCP
- Context7 MCP
- Playwright MCP

## 前提

| ツール | 用途 |
|---|---|
| Docker Desktop | GitHub MCP / Playwright MCP の起動 |
| Codex IDE | MCP の利用 |

GitHub MCP と Playwright MCP は、Codex が `docker run` を実行して MCP server を起動します。

ローカルに Node.js / npm / npx をインストールする必要はありません。

## 必要な環境変数

MCP 用の secret はリポジトリ配下に配置せず、各開発者の OS ユーザー環境変数として管理します。

| 環境変数 | 用途 |
|---|---|
| `GITHUB_PERSONAL_ACCESS_TOKEN` | GitHub MCP 用 Fine-grained PAT |
| `CONTEXT7_API_KEY` | Context7 MCP 用 API key |

## 環境変数の設定

### Windows Git Bash の場合

```bash
setx GITHUB_PERSONAL_ACCESS_TOKEN "github_pat_xxxxxxxxxxxxxxxxx"
setx CONTEXT7_API_KEY "ctx7_xxxxxxxxxxxxxxxxx"
```

### Windows PowerShell の場合

```powershell
[Environment]::SetEnvironmentVariable("GITHUB_PERSONAL_ACCESS_TOKEN", "github_pat_xxxxxxxxxxxxxxxxx", "User")
[Environment]::SetEnvironmentVariable("CONTEXT7_API_KEY", "ctx7_xxxxxxxxxxxxxxxxx", "User")
```

### macOS の場合

```bash
launchctl setenv GITHUB_PERSONAL_ACCESS_TOKEN "github_pat_xxxxxxxxxxxxxxxxx"
launchctl setenv CONTEXT7_API_KEY "ctx7_xxxxxxxxxxxxxxxxx"
```

設定後、Codex IDE を完全終了してから再起動します。

## GitHub PAT 権限

GitHub MCP 用の Fine-grained Personal Access Token は、対象リポジトリをこのプロジェクトに限定し、以下の権限にします。

| Permission | Access |
|---|---|
| Contents | Read-only |
| Issues | Read and write |
| Pull requests | Read-only |
| Actions | Read-only |
| Metadata | Read-only |

## MCP 設定ファイル

MCP server の実体設定は、各開発者のユーザー設定ファイルに配置します。

### Windows

```text
%USERPROFILE%\.codex\config.toml
```

例:

```text
C:\Users\<ユーザー名>\.codex\config.toml
```

### macOS

```text
~/.codex/config.toml
```

## 注意: project-scoped config について

Codex 公式仕様上は、trusted project であればリポジトリ配下の `.codex/config.toml` も設定対象です。

ただし、Windows 版 VS Code Codex IDE では、project-scoped `.codex/config.toml` の MCP 設定が runtime に反映されない事象があります。

そのため、現時点では MCP server の実体設定はリポジトリ配下ではなく、各開発者のユーザー設定ファイルに配置します。

リポジトリ配下の `.codex/config.toml` は、プロジェクト固有の Codex 設定や参考用テンプレートとして扱います。

## config.toml 追記内容

各開発者の `~/.codex/config.toml` または `%USERPROFILE%\.codex\config.toml` に、以下を追記します。

```toml
[mcp_servers.github]
command = "docker"
args = [
  "run",
  "-i",
  "--rm",
  "-e",
  "GITHUB_PERSONAL_ACCESS_TOKEN",
  "-e",
  "GITHUB_TOOLS=issue_read,list_issues,search_issues,add_issue_comment,pull_request_read,list_pull_requests,search_pull_requests,actions_get,actions_list,get_job_logs,get_file_contents",
  "ghcr.io/github/github-mcp-server"
]
env_vars = [
  "GITHUB_PERSONAL_ACCESS_TOKEN"
]
enabled_tools = [
  "issue_read",
  "list_issues",
  "search_issues",
  "add_issue_comment",
  "pull_request_read",
  "list_pull_requests",
  "search_pull_requests",
  "actions_get",
  "actions_list",
  "get_job_logs",
  "get_file_contents"
]
startup_timeout_sec = 120
tool_timeout_sec = 120

[mcp_servers.context7]
url = "https://mcp.context7.com/mcp"
env_http_headers = { "CONTEXT7_API_KEY" = "CONTEXT7_API_KEY" }
startup_timeout_sec = 40
tool_timeout_sec = 120
enabled = true

[mcp_servers.playwright]
command = "docker"
args = [
  "run",
  "-i",
  "--rm",
  "--init",
  "--pull=always",
  "mcr.microsoft.com/playwright/mcp"
]
startup_timeout_sec = 120
tool_timeout_sec = 120
enabled = true
```

## 動作確認

Codex IDE を再起動後、`/mcp` で以下が有効になっていることを確認します。

```text
github
context7
playwright
```

### GitHub MCP

```text
GitHub MCPを使ってこのリポジトリのIssue一覧を取得してください。
```

### Context7 MCP

```text
Web検索は使わず、Context7 MCPだけを使ってください。
Context7 MCPの resolve-library-id で react-router を解決し、query-docs で React Router v7 の loader に関する公式ドキュメントを取得してください。
```

### Playwright MCP

```text
Web検索、GitHub MCP、Context7 MCPは使わないでください。
Playwright MCPだけを使ってください。
browser_navigate で https://demo.playwright.dev/todomvc を開き、browser_snapshot でページの heading と textbox を確認してください。
```

## Docker コンテナについて

GitHub MCP / Playwright MCP 実行時に Docker コンテナが起動します。これは正常です。Codex が MCP server と通信している間、コンテナは起動したままになります。

`--rm` を指定しているため、Codex 側の接続が閉じてコンテナが終了すれば削除されます。

不要な MCP コンテナが残っている場合は、以下で停止できます。

### Playwright MCP

```powershell
docker ps --filter "ancestor=mcr.microsoft.com/playwright/mcp" -q | % { docker stop $_ }
```

### GitHub MCP

```powershell
docker ps --filter "ancestor=ghcr.io/github/github-mcp-server" -q | % { docker stop $_ }
```

---

# Skills Setup

このプロジェクトでは、Codex Skills を使用します。

Codex Skills は、特定の作業手順を `.codex/skills/<skill-name>/SKILL.md` に定義し、Codex IDE から呼び出して使うための仕組みです。

## Skills の使い方

Codex IDE の入力欄で `$` を入力すると、利用可能な Skill の一覧が表示されます。

一覧から使用したい Skill を選択して実行します。

```text
$
```

## Skill の作り方

新しい Skill を追加する場合は、`.codex/skills/` 配下に Skill 名のディレクトリを作成し、その中に `SKILL.md` を配置します。

```text
.codex/skills/<skill-name>/SKILL.md
```

`SKILL.md` は既存 Skill のフォーマットに合わせて作成します。

基本フォーマットは以下です。

````md
---
name: skill-name
description: このSkillを使うべき作業内容を具体的に書く。
---

# Skill Title

## Job

この Skill が行う作業を記述する。

## Inputs

- 入力として見るファイル、ディレクトリ、差分などを記述する。

## Outputs

- 変更するファイル
- 報告する内容

## Rules

- 変更してよい対象を明記する。
- 変更してはいけない対象を明記する。
- 根拠のない変更を禁止する。
- 既存の未コミット変更を不用意に触らない。

## Steps

1. 実行手順を書く。
2. 確認手順を書く。
3. 変更手順を書く。
4. 最後に確認すべき内容を書く。

## Report

```text
Changed files:
- path/to/file
    - 変更内容: ...
    - 反映元: ...

Notes:
- ...
```
````

## Skill 作成時の基本ルール

- `name` は短く、用途が先頭から分かる名前にする。
- `description` には、いつ使う Skill なのかを明確に書く。
- 対象ファイル・対象ディレクトリを明記する。
- 変更してよいファイルと、変更してはいけないファイルを明記する。
- 既存ファイルの表記・粒度・フォーマットに合わせる。
- 根拠のない追加・削除・推測修正を禁止する。
