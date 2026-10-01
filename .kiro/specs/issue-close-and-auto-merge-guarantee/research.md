# Research & Design Decisions

## Summary
- **Feature**: `issue-close-and-auto-merge-guarantee`
- **Discovery Scope**: Extension(既存の `rearm-auto-merge.yaml` と通知の作法を広げる。権限を扱うため、外部仕様は一次資料と実測で確かめた)
- **Key Findings**:
  - 予約が外れたイベント(`auto_merge_disabled`)は、GitHub の内部処理で外れた場合も人が外した場合もワークフローを起動する。#441 で未確認だった点は、実行履歴で確認できた
  - Issue の「マージの後に閉じられたか」は、Issue のタイムラインの ClosedEvent の日時と PR の `mergedAt` の比較で判定できる(実APIで確認)
  - `github.token` で付けたコメントのメンションは所有者に届く(監査の台帳で運用済み)。知らせを PAT に依らせない構成にできる

## Research Log

### 予約が外れたイベントでワークフローが起動するか
- **Context**: #441 の時点では、GitHub の内部処理による `auto_merge_disabled` で起動するかを公式文書から断定できなかった。起動しないなら、付け直しは定期の見直しに頼るしかない
- **Sources Consulted**: `gh run list --workflow rearm-auto-merge.yaml`、各実行のログ(2026-10-01 実測)
- **Findings**:
  - 実行 36812062119(2026-10-01、PR #458): `state=OPEN draft=false armed=false reason=repository_rule_violation count=1` のあと「auto-merge を予約し直しました」。内部処理で外れた場合に起動し、付け直せている
  - 実行 36694835305(2026-09-30): `reason=manually_disabled`。人が外した場合にも起動している
- **Implications**: 付け直しはイベントを主経路にできる。定期の見直しは取りこぼしの保険として置く(要件4-2)

### Issue がマージの後に閉じられたかの判定
- **Context**: 要件2-4・2-6。所有者が開き直した Issue を閉じ直さないために、「マージの後に一度でも閉じられたか」を知る必要がある
- **Sources Consulted**: GraphQL `issue.timelineItems(itemTypes:[CLOSED_EVENT])` を Issue #448 と PR #450 で実行(2026-10-01 実測)
- **Findings**: `ClosedEvent.createdAt`(2026-09-30T09:13:56Z)と `pullRequest.mergedAt`(2026-09-30T08:33:59Z)が取れ、比較できる。マージ済み PR の一覧は `gh pr list --state merged --base main --search "merged:>=<日付>"` で取れる
- **Implications**: 状態を別に保存しなくても、GitHub の記録だけで判定できる

### リポジトリの属性と機能の利用可否
- **Context**: テンプレートの「前提機能の利用可否」の確認
- **Sources Consulted**: `gh api repos/:owner/:repo`(2026-10-01 実測)
- **Findings**: `owner.type=User`、`visibility=public`、`allow_auto_merge=true`、`allow_squash_merge=true`、`squash_merge_commit_message=COMMIT_MESSAGES`
- **Implications**: 自動マージの予約と squash は使える。定期実行は公開リポジトリのため無料で動くが、60日間リポジトリに活動が無いと自動で止まる(https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows#schedule)

### どのトークンで何をするか
- **Context**: 要件6-3(マージ後の後続の処理が動くこと)と、仕組みが止まったときに知らせも出ない問題(requirements レビューの申告3)
- **Sources Consulted**: `rearm-auto-merge.yaml`・`update-pr-branches.yaml` の冒頭の説明(#326 の経緯)、`lib-ledger-issue.sh`・`audit-weekly.yaml`(`github.token` でのメンションつきコメント)、https://docs.github.com/en/actions/how-tos/write-workflows/choose-what-workflows-do/trigger-a-workflow#triggering-a-workflow-from-a-workflow
- **Findings**:
  - `GITHUB_TOKEN` で予約した自動マージのマージ push は後続のワークフローを起動しない。予約は PAT(`BOT_GITHUB_TOKEN`)で行う必要がある
  - 監査の台帳は `github.token` でコメントし、メンションで所有者に届いている
- **Implications**: 予約だけを PAT で行い、照会・知らせ・Issue のクローズは `github.token` で行う。PAT の期限が切れても、予約の失敗の知らせと Issue のクローズは動き続ける

### カナリアPRの見分け方
- **Context**: requirements レビュー R1-1-8。カナリアPRに誤って予約すると、検査が壊れている月にマージされる
- **Sources Consulted**: `.github/scripts/create-canary-prs.sh`
- **Findings**: 生成側はブランチ名 `canary/<名前>-<日付>` とラベル `canary` を付ける。ラベルは `gh pr create --label` で付くが、作成のイベントの時点で付いている保証は無い。ブランチ名は作成の時点で確定している
- **Implications**: ブランチ名が `canary/` で始まるか、ラベル `canary` が付いていれば対象外とする(どちらか一方で足りる)

### スクリプトのテストを PR で走らせる場所
- **Context**: 要件6-6。既存の判定スクリプトのテストは、使うワークフローの中の自己テストと、`guardrails.yaml` の `escape-hatch` ジョブの2か所で走っている
- **Sources Consulted**: `.github/workflows/guardrails.yaml`、`.github/audit/required-checks.json`
- **Findings**: `escape-hatch` は常に走る必須チェックで、`test-check-action-pinning.sh` などをステップとして持つ
- **Implications**: 新しいテストは `escape-hatch` のステップに足す。必須チェックを新しく足さないため、`required-checks.json` の変更は要らない

## Architecture Pattern Evaluation

| Option | Description | Strengths | Risks / Limitations | Notes |
|--------|-------------|-----------|---------------------|-------|
| イベント+定期の見直し | PR のイベントで即時に動き、定期実行で取りこぼしを拾う | 即時性と取りこぼしへの強さを両立。`dependabot-auto-merge.yaml` と同じ形 | 定期実行の回数が増える | 採用 |
| イベントのみ | 現行の `rearm-auto-merge.yaml` の形 | 単純 | イベントの取りこぼしと、導入時に開いている PR を拾えない。要件2-4・4-2 を満たせない | 不採用 |
| 定期の見直しのみ | 定期実行だけで全 PR を見る | 単純 | 予約が付くまで最長で1周期待つ | 不採用 |
| `pull_request_target` で起動 | ワークフローの定義を常に main から取る | PR がワークフローを書き換えても影響しない | `auto_merge_disabled` で起動するかが未実測。既存のワークフローはすべて `pull_request` | 不採用(下の Decision を参照) |

## Design Decisions

### Decision: 予約の仕組みは `rearm-auto-merge.yaml` を置き換える
- **Context**: 付け直し(要件4)は現行の `rearm-auto-merge.yaml` の一般化で、新規の予約(要件3)と判定の大半が重なる
- **Alternatives Considered**:
  1. `rearm-auto-merge.yaml` を残し、新規の予約のワークフローを足す
  2. 1つのワークフローと1つの判定スクリプトにまとめ、`rearm-auto-merge.yaml` を削除する
- **Selected Approach**: 2。「対象の PR に予約が無ければ付ける」という1つの判定を、作成・下書き解除・開き直し・コミット・予約外れ・定期の見直しのすべてから呼ぶ
- **Rationale**: 予約の有無はその時点の PR の状態から決まり、起点のイベントに依らない。判定を1か所に置けば、同じ PR に2つのワークフローが別々の判断で予約することが無い
- **Trade-offs**: ワークフローの削除を伴うため README の表と図の更新が要る
- **Follow-up**: 削除と追加を同じ PR で行う

### Decision: ワークフロー内の判定をスクリプトに出す
- **Context**: 現行の `rearm-auto-merge.yaml` は判定をワークフローの中に直接書いており、自動テストが無い。要件6-6 は判定を自動テストで検証できる形で持つことを求める
- **Selected Approach**: 判定と操作を `.github/scripts/` のスクリプトに置き、`gh` を偽物に置き換えるテストを `.github/scripts/tests/` に置く(`check-release-age.sh` と同じ作法)
- **Rationale**: 既存の判定スクリプトとテストの形に揃う
- **Trade-offs**: なし

### Decision: 起動のイベントは `pull_request` を使う
- **Context**: 要件6-2(PR が書き換えた内容を、書き込みの権限を持たせて実行しない)
- **Alternatives Considered**:
  1. `pull_request`(現行と同じ)+ スクリプトは base のコミットから取得
  2. `pull_request_target`
- **Selected Approach**: 1
- **Rationale**: `pull_request` の `auto_merge_disabled` が起動することは実測済み。fork の PR にはシークレットが渡らず、ジョブの条件でも除く。スクリプトは base のコミットから取るため、PR が書き換えたスクリプトは実行されない
- **Trade-offs**: 同一リポジトリの PR がワークフローの定義そのものを書き換えた場合、その定義が PAT つきで動く。ブランチに push できるのは所有者と bot だけで、既存のすべてのワークフローと同じ条件である。`.github/` の変更は CODEOWNERS により所有者の承認までマージされない
- **Follow-up**: design レビューで問題になれば 2 に切り替える。その場合は `auto_merge_disabled` の起動を導入後に実測する

### Decision: 知らせは PR・Issue へのメンションつきコメントで行う
- **Context**: 要件2-1・2-2・4-3・5-1。知らせる対象は個々の PR・Issue に紐づく
- **Alternatives Considered**:
  1. 対象の PR・Issue に、所有者へのメンションつきでコメントする
  2. 監査と同じく、固定タイトルの通知 Issue を1件持つ
- **Selected Approach**: 1。同じ知らせを繰り返さないために、コメントに目印(HTML コメント)を入れ、同じ目印のコメントがあれば付けない
- **Rationale**: 所有者が知らせを開いた場所が、そのまま対処する場所になる。`check-release-age.sh` が同じ方法で運用されている。要件5-4 の「知らせを出した場所で分かる」も同じ PR へのコメントで満たせる
- **Trade-offs**: 知らせが PR・Issue ごとに分かれる。一覧で見る場所は無い

### Decision: マージ直後は60秒待ってから Issue を確かめる
- **Context**: GitHub 自身のクローズより先に仕組みが閉じると、ほとんどの Issue に仕組みの記録が付く(requirements レビューの申告7)
- **Selected Approach**: マージのイベントで起動したときは、60秒待ってから Issue の状態を確かめる
- **Rationale**: GitHub が閉じた Issue には何も書き込まない(要件1-4)という動きを、通常の場合に保つ
- **Trade-offs**: GitHub のクローズが60秒より遅れた場合は、仕組みが先に閉じて記録が付く。害は無い
- **Follow-up**: 導入後、仕組みの記録が付いた Issue の割合を見る

### Decision: 見直しの間隔
- **Context**: 要件2-4・2-5・4-2 の「1時間」
- **Selected Approach**: 予約の見直しは30分ごと、Issue の見直しは1時間ごとに定期実行する
- **Rationale**: GitHub の定期実行は混雑時に遅れる。予約は30分ごとにして、1時間の内に少なくとも1回は見直しが走る余裕を持たせる。Issue の見直しは「マージから1時間が経っても」が条件のため、1時間ごとで足りる
- **Trade-offs**: 定期実行の遅れが30分を超えると、予約の付け直しが1時間を超えることがある。GitHub 側の事象で、仕組みの側では防げない

## Synthesis Outcomes
- **Generalization**: 新規の予約と付け直しは「対象の PR に予約が無ければ付ける」という同じ判定にまとめた。予約の失敗・付け直しの停止・Issue の知らせは「目印つきのコメントを1回だけ付ける」という同じ操作にまとめ、共通の関数に置く
- **Build vs. Adopt**: GitHub 自身の Issue の自動クローズと自動マージをそのまま使い、仕組みはその取りこぼしを補うだけにした。外部のアクションやサービスは足さない
- **Simplification**: 状態の保存場所を持たない。判定はすべて、その時点の PR・Issue の状態とタイムライン、目印つきのコメントから行う。通知 Issue と、付け直しを止めるための専用ラベルは作らない

## Risks & Mitigations
- 定期実行が止まる(60日間の無活動、ワークフローの故障) — イベントの経路は動き続ける。見直しの停止に気づく仕組みは持たない(残余リスクとして運用文書に書く)
- `github.token` のコメントのメンションが所有者に届かない — 監査の台帳で届いている実績がある。導入後の確認手順(要件7-5)で確かめる
- `/ship` が PR を作ってから `pre-merge-check` ラベルを付けるまでの間に予約が付く — 予約が付いても、必須チェックが揃うまで数分かかるためマージされない。`/ship` の手順を、PR の作成と同時にラベルを付ける形に直す
- 導入時に開いている PR に一斉に予約が付く — 導入の前に、予約の無い開いている PR の一覧を所有者に示し、マージしたくないものを下書きにしてもらう

## References
- [Events that trigger workflows](https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows) — `pull_request` の種類、定期実行の遅れと自動停止
- [Triggering a workflow from a workflow](https://docs.github.com/en/actions/how-tos/write-workflows/choose-what-workflows-do/trigger-a-workflow#triggering-a-workflow-from-a-workflow) — `GITHUB_TOKEN` による操作は後続のワークフローを起動しない
- [gh pr merge](https://cli.github.com/manual/gh_pr_merge) — `--auto` `--match-head-commit`
- `.github/workflows/rearm-auto-merge.yaml` `.github/workflows/dependabot-auto-merge.yaml` `.github/scripts/check-release-age.sh` `.github/scripts/lib-ledger-issue.sh` — 既存の作法
