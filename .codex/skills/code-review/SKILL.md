---
name: code-review
description: 現在の Git 差分を対象に、修正担当の AI エージェント向けレビューを行う。テストやビルドは実行せず、staged / unstaged / 必要な untracked テキストファイルを読み、重大度順の Findings を出す。
---

# Code Review

## Job

現在の Git 差分をレビューし、修正担当の AI エージェントがそのまま直せる粒度で指摘してください。

## Scope

- デフォルトでは現在のローカル差分を対象にしてください。
- ユーザーが PR 番号、commit、ファイル、範囲を指定した場合は、その指定を優先してください。
- staged、unstaged、必要な untracked テキストファイルを見落とさないでください。
- 生成物、依存ディレクトリ、coverage、build output は対象外にしてください。

## Rules

- この Skill はレビュー専用です。ファイル編集、format、fix、commit、push は行わないでください。
- テスト、ビルド、lint、coverage、format、terraform validate は実行しないでください。
- 指摘は重大度順に並べ、要約や変更説明より先に Findings を出してください。
- 指摘は修正担当 AI エージェントが実装できる粒度で書いてください。
- 修正方針は既存設計に合わせてください。新しい依存や大きな設計変更を前提にしないでください。
- 推測で断定しないでください。根拠が弱いものは Open questions に送ってください。

## Steps

1. `git status --short` で staged / unstaged / untracked を確認する。
2. `git diff --stat` と `git diff` で unstaged diff を読む。
3. `git diff --cached --stat` と `git diff --cached` で staged diff を読む。
4. `??` の untracked から、生成物・依存ディレクトリを除いたテキストファイルを読む。
5. 差分だけで判断できない場合は、関連する既存実装・テスト・設定を読む。
6. Findings を重大度順に出す。
7. 指摘がなければ「重大な指摘なし」と明記し、残るリスクや未確認事項だけを書く。

## Review Focus

- バグ、仕様逸脱、データ破壊、認証認可、セキュリティ。
- 既存アーキテクチャ・責務境界からの逸脱。
- API contract、DB schema、CI/CD、deploy 影響の見落とし。
- テスト不足または検証不足。
- 過剰設計、重複、保守性低下。
- 命名、コメント、ドキュメントの不整合。

## Severity

- `Blocker`: データ破壊、認証認可破壊、重大な security、CI 不能、deploy 危険、仕様の根本破綻。
- `High`: 主要機能バグ、API contract 破壊、DB/schema/infra 影響の見落とし、重要テスト欠落。
- `Medium`: 境界条件バグ、既存 architecture 逸脱、保守性低下、将来バグになりやすい実装。
- `Low`: 命名、コメント、局所的な読みやすさ、軽微なテスト観点。

## Output

```text
Findings:
- [Severity] path/to/file:line
  問題:
  影響:
  修正方針:
  修正時の注意:

Open questions:
- ...

Notes:
- ...
```

- 各 Finding には、必ず `問題`、`影響`、`修正方針`、`修正時の注意` を含めてください。
- 各 Finding には、可能な限り `path:line` を付けてください。
- 指摘がない場合は Findings に「重大な指摘なし」と書いてください。
