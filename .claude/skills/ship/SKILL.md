---
description: verify-all→ブランチ確認→規約準拠commit→push→PR作成→auto-mergeの予約の確認→CI監視まで、実装完了からCIの見届けまでを一気通貫で行う。auto-mergeは仕組みが予約する。
---

# ship

## Job

実装完了後の出荷手順。verify → commit → push → PR作成 → auto-mergeの予約の確認 → CI監視。
auto-mergeは、PRが作られると仕組み(ワークフロー)が予約する。AIは予約の操作をせず、予約されたことを確かめる。
人間はマージに関与しない(ゲート全通過で自動マージされる)。

## Steps

1. **verify**: `/verify-all` の手順を実行し、全PASSを確認する。FAILがあれば出荷しない。

2. **ブランチ確認**: `git branch --show-current` で現在のブランチを確認する。
   - mainにいる場合: `.branch_name_template` に従い `git switch -c <type>/<short-description>` で作成
   - featureブランチにいる場合: 作業内容と合っているか確認

3. **commit**: `.commit_template` の形式に従う(prefix / subject / Changes / Reason / BREAKING CHANGE / Refs)。
   次の3つを、それぞれ単独のコマンドとして順に実行する。
   1. コミットメッセージを scratchpad のファイルに Write で書く
   2. `git add <ファイル1> <ファイル2> ...`(変更したファイルを個別に指定する。`-A` で無関係なファイルを巻き込まない)
   3. `git commit -F <メッセージのファイル>`
   - `Refs: #<Issue番号>` を必ず入れる

4. **push**: `git push -u origin <ブランチ名>` を単独のコマンドとして実行する。

   commit と push は、上の形から変えない。`-q` などのオプションを足さない、`cd` や `git log` や
   `| tail` を `&&` `;` `|` でつながない、`-m` やヒアドキュメントでメッセージを渡さない。
   この形は `.claude/settings.json` の許可ルールにそのまま当たり、auto mode の判定に回らない。
   形がずれると判定に回り、ゲート設定(`.github/` `.claude/`)を含む変更は止められることがある。
   形は `.claude/hooks/protect-main.sh` が実行前に確かめ、外れていれば止めて正しい形を案内する
   (mainへのcommit/pushと強制pushも止める)。結果を確かめたいときは、`git log --oneline -1` を
   別のコマンドとして実行する。リモートのブランチの削除(`git push origin --delete`)も止まるので、
   削除が要るときは人間に依頼する。

5. **PR作成**: `gh pr create` で作成する。PR本文に必ず含めるもの:
   - `Refs: #<Issue番号>`
   - `Closes #<Issue番号>`(例外なく必須。マージ時にGitHubがIssueを自動で閉じる。GitHubが閉じなかったときは仕組みが閉じる)
   - Lane A(spec駆動)の場合: `Spec: .kiro/specs/<feature>`(size-checkがこの行で判定する)
   - テストのアサーションを意図的に変更した場合: `Test-Change-Justification: <理由>`
   - 変更概要・検証結果(verifyのReport)

   分けた部分のIssue(サブIssue)のPRでは、`Refs:` と `Closes` にサブIssueの番号を書き、元のIssue(親)の番号は書かない。
   codex-review はサブIssueの本文を判定の基準にし、close-linked-issues は元のIssueに「`Refs:` だけ」の知らせを出さない。
   元のIssueは、サブIssueがすべて閉じたときに仕組みが閉じる。

   更新した spec(spec.json に `additional_issues` がある)のPRでは、本文に
   「このPRが実装するのは `(#N)` の印の付いた項目です。印の無い項目は以前のPRで実装済みです」と書き、
   `Refs:` と `Closes` には追加のIssueの番号を書く。

   対応するIssue(Refs: #<Issue番号>)に `pre-merge-check` ラベルが付いているかを、PRを作る前に確かめる。
   付いている場合は、`gh pr create` に `--label pre-merge-check` を付け、PRの作成と同時に同じラベルを付ける
   (リポジトリにラベルが無ければ、先に
   `gh label create pre-merge-check --description "マージ前に人間がローカルで確認するPR" --color 1D76DB` で作成)。
   PRを作った後からラベルを付ける形にしない。仕組みがPRの作成の直後にauto-mergeを予約するため、
   後から付けると、付くまでの間は保留が効かない。
   このラベルのPRは、所有者がローカル確認してApproveするまで pre-merge-check チェックが赤のままになる。

6. **auto-mergeの予約の確認**: auto-mergeは仕組みが予約する。AIは `gh pr merge` で予約の操作をしない。
   予約されたことを次のコマンドで確かめる(`true` なら予約済み)。
   `gh pr view <PR番号> --json autoMergeRequest --jq '.autoMergeRequest != null'`
   - PRの作成の直後はまだ付いていないことがある(ワークフローが動くまで1分ほど)。`false` のときは少し待って確かめ直す
   - 数分たっても付かないとき、またはPRに予約の失敗を知らせるコメントが付いたときは、
     自分で予約の操作をせず、その旨を報告する(手順7のCI監視は続ける)

7. **CI監視**: `gh pr checks <PR番号> --watch` で必須チェックの結果を見届ける。
   - 赤になったら修正してpushする(以降のレビュー対応は `/review-loop` に従う)
   - ただし、spec 無しのPRが `size-check` で赤になったときは、修正してpushしない。
     `/start` の「途中で見立てが外れたとき」に従い、spec に切り替えるか小さく分けるかを決めて理由を示す
   - `dependency-gate` / `pre-merge-check` / CODEOWNERS起因の待ちは人間の承認待ちなので、その旨を報告して終了する
   - チェックは緑なのにブランチが out of date でマージが進まない場合は、
     `git fetch origin && git merge origin/main` してpushする(または `gh pr update-branch <PR番号>`)。
     コンフリクトが出たら解消し、verifyを再実行してから、`git add <解消したファイル>` と
     `git commit -F .git/MERGE_MSG` でマージを完了し、手順4の形でpushする

## Rules

- verify全PASSまでpushしない
- 1つのPRに複数の関心事を混ぜない(200行のsize-checkは分割のシグナル)
- マイグレーション・依存追加・ゲート設定変更を含む場合は、PR本文冒頭に「人間承認が必要な変更」として明記する
- `Refs: #<Issue番号>` は `Closes` と併記しても消さない。codex-reviewがこの行からIssue本文を
  取得してspec適合の判定基準にしている

## Report

```
ship:
- verify-all -> PASS
- branch     -> <ブランチ名>
- commit     -> <コミットハッシュ> <サブジェクト>
- PR         -> <PR URL>
- auto-merge -> 仕組みによる予約を確認済み / 未予約(確かめた結果と、失敗の知らせの有無)
- checks     -> 監視結果 / 人間承認待ちの有無
- issue      -> Closes #<Issue番号> 記載済み(マージ時に自動クローズ。GitHubが閉じなかったときは仕組みが閉じる)
```
