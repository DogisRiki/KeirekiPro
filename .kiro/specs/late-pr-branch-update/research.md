# 調査と設計の判断

## まとめ

- 機能: `late-pr-branch-update`
- 調査の種類: 既存の仕組みの拡張(Extension)
- 主な発見:
  - ruleset `main` の必須ステータスチェックは `strict_required_status_checks_policy: true` で、PRのブランチが main の最新を含んでいないとマージできない(2026-10-06 に `gh api repos/DogisRiki/KeirekiPro/rulesets/2986186` で確かめた)。merge queue は有効になっていない
  - `update-pr-branches.yaml` は `push`(main)だけで起動する。#508 が main に入ったのは 2026-10-06T01:38:57Z、PR #509 が作られたのは 01:44:56Z で、#509 は起動の時点で存在しなかった。01:53:37Z に bot のアカウントが main を取り込み(コミット f9f51be3)、01:57:14Z にマージされた
  - `/ship` の手順7は、`gh pr checks --watch` が終わったあとにPRがマージされたかを確かめていない。チェックが緑のまま out-of-date で止まったPRを Claude が見落とす

## 調べたこと

### Dependabot が起こしたイベントで使えるシークレット

- きっかけ: 要件1の3で、PRを出したときに合わせる対象に Dependabot のPRが入る(今の `update-pr-branches.yaml` は Dependabot を除いていない)
- 出どころ: https://docs.github.com/en/code-security/dependabot/troubleshooting-dependabot/troubleshooting-dependabot-on-github-actions
- 分かったこと:
  - Dependabot が起こしたイベントで動くワークフローには、Actions のシークレットは渡らず、Dependabot のシークレットだけが渡る
  - `GITHUB_TOKEN` は読み取りだけになる
  - このリポジトリでは、`BOT_GITHUB_TOKEN` が Dependabot のシークレットにも登録されている(`gh api repos/DogisRiki/KeirekiPro/dependabot/secrets` で確かめた)
- 設計への影響: `pull_request` のイベントで起動するジョブでも、Dependabot のPRに対して `secrets.BOT_GITHUB_TOKEN` を使える。`GITHUB_TOKEN` は使わない

### ブランチを合わせる API

- 出どころ: https://docs.github.com/en/rest/pulls/pulls#update-a-pull-request-branch
- 分かったこと:
  - `PUT /repos/{owner}/{repo}/pulls/{pull_number}/update-branch` は、受け付けると 202 を返す。`expected_head_sha` を渡し、PRの先頭のコミットと違えば 422 を返す
  - ブランチがすでに最新のときの応答は、公式の文書に書かれていない。今のワークフローの `*"not behind"* | *"up to date"* | *up-to-date*` の判定は、直近30回の実行のログに一度も現れていない(main への push のたびに対象のPRが古くなっているため)
- 設計への影響: PRを出したときの起動では、PRを出した直後のブランチが最新であることが多い。最新かどうかを、update-branch の応答の文面ではなく、比較の API(`GET /repos/{owner}/{repo}/compare/{base}...{head}` の `behind_by`)で先に確かめる

### 同時実行の組

- 出どころ: https://docs.github.com/en/actions/how-tos/write-workflows/choose-when-workflows-run/control-workflow-concurrency
- 分かったこと: 同じ concurrency の組では、動いている実行のほかに待てる実行は1つだけで、新しい実行が待ちに入ると、それまで待っていた実行は取り消される
- 設計への影響: PRを出したときの実行を、main への push の実行と同じ組に入れると、待っていた push の実行が取り消され、ほかのPRが合わせられないまま残る。PRを出したときの実行は、PRごとの別の組にする

## 比べた案

| 案 | 中身 | 良い点 | 悪い点 |
|---|---|---|---|
| A. `update-pr-branches.yaml` に `pull_request` の起点を足す | PRを出したときに、そのPRだけを合わせる | PRを出した直後に合わせられる。対象の判定を push の起動と1か所で持てる | ワークフローの変更のため所有者の承認が要る |
| B. `auto-merge.yaml` の30分ごとの見直しで合わせる | 定期実行で古いPRを拾う | 合わせ損ねたPRも拾える | PRが最長30分止まる。予約のワークフローに別の責任が混ざる |
| C. `/ship` だけで直す | Claude がPRを出す前に main を取り込み、マージまで見届ける | ワークフローを変えない | Dependabot と所有者のPRは救えない。要件1に合わない |
| D. merge queue へ切り替える | キューが最新の main に重ねて検証する | out-of-date そのものが無くなる | 必須チェック18本の対応が要り、別の要望(#203)の範囲。要件の範囲で決めないことにした |

A を選び、要件2のために `/ship` の見届けも直す(C の一部)。

## 設計の判断

### 判断: 対象の判定を1つの jq の式にまとめる

- きっかけ: 要件1の3は、PRを出したときの対象を、main に push されたときの対象と同じにすると決めている
- 比べた案:
  1. push の起動と同じ式を、PRの起動用にもう1つ書く
  2. 式を1つの変数に置き、両方の起動で使う
- 選んだ案: 2。ステップの先頭で対象の判定の式を変数に置き、push の起動では一覧の各PRに、PRの起動ではそのPR1件に当てる
- 理由: 式を2つ持つと、片方だけを直したときに対象が食い違う

### 判断: スクリプトに切り出さない

- きっかけ: `reserve-auto-merge.sh` のように、判定をスクリプトに切り出してテストを付ける形もある
- 選んだ案: ワークフローの中の `run` に書いたままにする
- 理由: 今のワークフローは checkout せず、PRのコードを一切実行しない。スクリプトに切り出すと、base の checkout を足す必要があり、この性質が変わる。足す分岐は、起点のイベントで一覧の取り方を変えることと、最新かどうかの事前の確かめだけである。actionlint が `run` の中に shellcheck をかける
- 引き換え: 判定の式のテストは書けない。導入のあとに実地で確かめる

## 危険と手当て

- PRを出したときの実行と main への push の実行が、同じPRを同時に合わせる。update-branch はサーバー側でマージするので、片方が先に合わせれば、もう片方は比較で最新と判定して何もしない。比較と update-branch の間に先を越されたときは、update-branch がすでに最新の応答を返すか、余分なマージのコミットを1つ作るだけで、壊れはしない
- Claude が `/ship` の見届けで main を取り込む push と、ワークフローの update-branch が重なる。Claude は必須の検査の結果がすべて出るまで push しないので、PRを出した直後のワークフローの実行とは重ならない

## 要件に戻ったあとの追加の調査(2026-10-06)

### 衝突しているPRでのワークフローの起動

- きっかけ: design のレビューの指摘 D1-1-1 と、前の段階への指摘 D1-1-8
- 出どころ: https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows#pull_request
- 分かったこと: 「Workflows will not run on `pull_request` activity if the pull request has a merge conflict.」。このリポジトリの必須の検査は、どれも `pull_request` で動く
- 設計への影響: 衝突しているPRでは、PRの起点の `update-pr-branches.yaml` も必須の検査も始まらない。Claude は、見届けの最初に `mergeStateStatus` を読み、`DIRTY` なら検査を待たずに取り込む。要件2の3はこのために足した

### ブランチが古いかどうかの読み方

- きっかけ: design のレビューの指摘 D1-1-4
- 分かったこと: `mergeStateStatus` は値を1つしか返さず、承認待ちなどほかの理由があると `BLOCKED` になって、ブランチが古いことが読めない
- 設計への影響: Claude は、ブランチが古いかどうかをワークフローと同じ compare の API の `behind_by` で読み、`mergeStateStatus` は衝突(`DIRTY`)の判定に使う

### 承認待ちと取り込みの順

- きっかけ: requirements のレビューの指摘 R2-1-3
- 分かったこと: ruleset `main` の `pull_request` の規則は `dismiss_stale_reviews_on_push: true` である。承認のあとに取り込むと承認が外れる
- 設計への影響: Claude は、承認待ちで見届けを終える前に、古いブランチを取り込む
