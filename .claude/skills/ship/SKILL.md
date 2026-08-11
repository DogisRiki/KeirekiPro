---
description: verify-all→ブランチ確認→規約準拠commit→push→PR作成→auto-merge予約→CI監視まで、実装完了からマージ予約までを一気通貫で行う。
---

# ship

## Job

実装完了後の出荷手順。verify → commit → push → PR作成 → auto-merge予約 → CI監視。
人間はマージに関与しない(ゲート全通過で自動マージされる)。

## Steps

1. **verify**: `/verify-all` の手順を実行し、全PASSを確認する。FAILがあれば出荷しない。

2. **ブランチ確認**: `git branch --show-current` で現在のブランチを確認する。
   - mainにいる場合: `.branch_name_template` に従い `git switch -c <type>/<short-description>` で作成
   - featureブランチにいる場合: 作業内容と合っているか確認

3. **commit**: `.commit_template` の形式に従う(prefix / subject / Changes / Reason / BREAKING CHANGE / Refs)。
   - `git add` は変更したファイルを個別に指定する(`-A` で無関係なファイルを巻き込まない)
   - `Refs: #<Issue番号>` を必ず入れる

4. **push**: `git push -u origin <ブランチ名>`(mainへのpushはhookでブロックされる)

5. **PR作成**: `gh pr create` で作成する。PR本文に必ず含めるもの:
   - `Refs: #<Issue番号>`
   - Lane A(spec駆動)の場合: `Spec: .kiro/specs/<feature>`(size-checkがこの行で判定する)
   - テストのアサーションを意図的に変更した場合: `Test-Change-Justification: <理由>`
   - 変更概要・検証結果(verifyのReport)

   対応するIssue(Refs: #<Issue番号>)に `pre-merge-check` ラベルが付いている場合は、
   PRにも同じラベルを付与する(ラベルが無ければ
   `gh label create pre-merge-check --description "マージ前に人間がローカルで確認するPR" --color 1D76DB` で作成)。
   このラベルのPRは、所有者がローカル確認してApproveするまで pre-merge-check チェックが赤のままになる。

6. **auto-merge予約**: `gh pr merge --auto --squash <PR番号>`

7. **CI監視**: `gh pr checks <PR番号> --watch` で必須チェックの結果を見届ける。
   - 赤になったら修正してpushする(以降のレビュー対応は `/review-loop` に従う)
   - `dependency-gate` / `pre-merge-check` / CODEOWNERS起因の待ちは人間の承認待ちなので、その旨を報告して終了する
   - チェックは緑なのにブランチが out of date でマージが進まない場合は、
     `git fetch origin && git merge origin/main` してpushする(または `gh pr update-branch <PR番号>`)。
     コンフリクトが出たら解消し、verifyを再実行してからpushする

## Rules

- verify全PASSまでpushしない
- 1つのPRに複数の関心事を混ぜない(200行のsize-checkは分割のシグナル)
- マイグレーション・依存追加・ゲート設定変更を含む場合は、PR本文冒頭に「人間承認が必要な変更」として明記する

## Report

```
ship:
- verify-all -> PASS
- branch     -> <ブランチ名>
- commit     -> <コミットハッシュ> <サブジェクト>
- PR         -> <PR URL>(auto-merge予約済み)
- checks     -> 監視結果 / 人間承認待ちの有無
```
