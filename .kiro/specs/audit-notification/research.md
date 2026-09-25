# Research & Design Decisions

## Summary
- **Feature**: `audit-notification`
- **Discovery Scope**: Extension(既存の監査ワークフロー群への通知経路の追加と判定契約の変更)
- **Key Findings**:
  - 定期実行の失敗通知は、cronを最後に書き換えた利用者にしか届かない。audit-weekly.yaml・canary-verify.yaml の書き手と実行者はbot(`DogisRiki-bot`)のため、所有者には一度も届いていない
  - 既存の判定スクリプト4本は、逸脱と判定不能をどちらも exit 1 で返しており、終了コードで区別できない(Job Summary の見出しでのみ区別)
  - 定期コンテナスキャンの `container-scan-issue.sh` が、ラベルとタイトルでIssueを探して起票・追記・クローズする型と、PATHシムで `gh` を差し替えるテストの型を既に持つ

## Research Log

### 定期実行の失敗通知の宛先
- **Context**: 週次監査が 2026-09-14・09-21 に失敗したが、約2週間誰も気づかなかった
- **Sources Consulted**: [Events that trigger workflows / schedule](https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows)、`git log -- .github/workflows/audit-weekly.yaml`、`gh api .../audit-weekly.yaml/runs` の `actor` / `triggering_actor`
- **Findings**:
  - 公式: 「Notifications for scheduled workflows are sent to the user who last modified the cron syntax in the workflow file」
  - audit-weekly.yaml の最終コミッタは `DogisRiki-bot`。全実行の actor / triggering_actor も `DogisRiki-bot`(2026-09-24 実測)
  - 公式: 公開リポジトリでは60日間活動が無いと定期実行が自動で無効になる
- **Implications**: audit-automation spec の「通知はGitHub既定の失敗通知に乗る」という前提は成り立たない。通知経路を別に持つ必要がある

### ワークフロー実行一覧APIの status 指定
- **Sources Consulted**: [List workflow runs for a workflow](https://docs.github.com/en/rest/actions/workflow-runs#list-workflow-runs-for-a-workflow)
- **Findings**: `status` に `completed` を指定できる(他に `success` / `failure` / `cancelled` など)。`completed` は結論を問わず完了した実行を返す
- **Implications**: 死活確認はクエリの `status=success` を `status=completed` に替えるだけで「実行されたか」の判定になる

### Issueの担当者割り当て
- **Sources Consulted**: [Add assignees to an issue](https://docs.github.com/en/rest/issues/assignees#add-assignees-to-an-issue)
- **Findings**: 公式: 「Only users with push access can add assignees to an issue. Assignees are silently ignored otherwise.」。GITHUB_TOKEN(`issues: write` のみ)での割り当てが受け付けられるかは公式に明記が無い(**未確認**)
- **Implications**: 割り当てはエラーにならず黙って無視されうる。作成後に担当者を読み戻して確かめ、本文に所有者へのメンションも入れて二重の経路にする。導入時の手動実行で実際に確認する(要件5.3)

### 既存の判定スクリプトとIssue操作の型
- **Sources Consulted**: `.github/scripts/check-audit-*.sh`、`check-canary-results.sh`、`container-scan-issue.sh` と各テスト、`container-scan-scheduled.yaml`
- **Findings**:
  - 4本とも `report_undecidable` で判定不能を exit 1 にしている(scan-freshness 44-60行、dependabot-stuck 62-77行、skipped-required 69-85行、canary 80-94行)。報告は `GITHUB_STEP_SUMMARY` に書く
  - テストの判定不能ケースは `check 1` で検証している(scan-freshness 4件、dependabot-stuck 11件、skipped-required 15件、canary 11件、計41件)
  - `container-scan-issue.sh` は `gh api repos/.../issues?labels=...&state=open --paginate --slurp` で探し、`pull_request` を持つ項目を除外し、規約外タイトルには触らない。ラベルは `gh label create ... || true` で冪等に作る。担当者は付けない
  - `check-container-scan.sh` の判定は 0 / 1 / 2 の3値契約で、ワークフロー側は 2 と契約外の値を失敗にしている
  - skipped-required の対象期間の下限は「前回の週次監査の実行(結論を問わない)」で決まる(170-198行)
- **Implications**: 3値の終了コード契約は既存の型に揃う。Issue操作は container-scan-issue.sh の探し方・除外・冪等なラベル作成・テストの型を踏襲する。逸脱ありの実行が成功で終わっても、skipped-required の対象期間の窓は変わらない

### リポジトリの属性
- **Findings**: `owner.type=User`、`visibility=public`、`has_issues=true`(`gh api repos/DogisRiki/KeirekiPro`、2026-09-24)。既存ラベルに `audit` は無い
- **Implications**: 所有者のログイン名は `GITHUB_REPOSITORY_OWNER` で得られる。Issue機能は使える

## Architecture Pattern Evaluation

| Option | Description | Strengths | Risks / Limitations | Notes |
|--------|-------------|-----------|---------------------|-------|
| 死活判定の変更のみ | `status=completed` にする | 最小の変更 | 通知ゼロのまま、唯一の信号(PRの赤)も消える | 不採用 |
| 失敗時にIssueを1件 | 赤になったらIssue | 小さい | 逸脱と故障が同じIssueに混ざり、急ぎ方と対処が見分けにくい | 不採用 |
| 3値化+2種類のIssue | 逸脱と故障を別のIssueで通知し、実行の赤は故障だけ | container-scan の型と一貫。行き詰まりが構造的に消える | 変更量が増える | 採用 |
| 外部の通知サービス | Slack等 | 確実に届く | リポジトリ外部へのデータ送信(人間承認)・secrets追加 | 不採用 |

## Design Decisions

### Decision: 判定スクリプトの終了コードを 0 / 1 / 2 の3値にする
- **Context**: 要件1.1〜1.3。現在は逸脱と判定不能がともに exit 1
- **Alternatives Considered**:
  1. Job Summary の見出しの文字列で区別する
  2. 終了コードで区別する
- **Selected Approach**: 2。`report_undecidable` を exit 2 にする
- **Rationale**: 文字列照合は文言の変更で壊れる。`check-container-scan.sh` と同じ契約になる
- **Trade-offs**: 既存テストの判定不能ケース41件の期待値が 1 から 2 に変わる(PR本文に `Test-Change-Justification` が要る)
- **Follow-up**: 契約外の終了コード(3以上や126・127)は判定不能として扱う

### Decision: Issue操作を1本のスクリプトにまとめ、監査の種類を引数で受ける
- **Context**: 要件2・3が週次監査とカナリア照合の両方に同じ振る舞いを求める
- **Selected Approach**: `audit-issue.sh <kind> <result> <report>`。kind が `weekly` / `canary`、result が `none` / `deviation` / `undecidable`
- **Rationale**: 一般化の観点。2種類の監査×2種類のIssueの状態遷移は同じ表で書ける。container-scan-issue.sh とは入力の形(脆弱性の配列 vs 結果の3値)が違うため、共通化はせず型だけ踏襲する
- **Trade-offs**: container-scan-issue.sh と似たIssue検索のコードが2か所になる。既存スクリプトを改修して共通化すると、稼働中の脆弱性通知に回帰の危険が及ぶため避ける

### Decision: 判定の集約と通知をステップに分け、通知は常に実行する
- **Context**: 要件1.2(自己テストの失敗も判定不能)、要件3(故障の通知)
- **Selected Approach**: 「判定」ステップは結果をステップ出力に書くだけで失敗しない。「通知」ステップは `if: always()` で動き、結果が無ければ判定不能として扱う。最後の「結論」ステップが判定不能のときだけ失敗する
- **Rationale**: 判定ステップが想定外に落ちても、故障のIssueが作られる
- **Trade-offs**: 通知スクリプト自身のテストが落ちた場合は通知できない(赤のみ)。要件のOut of scope(Issue操作そのものの失敗)に含まれる

### Decision: 担当者の割り当てとメンションを併用する
- **Context**: 要件2.1・3.1。割り当ては黙って無視されうる(公式)
- **Selected Approach**: 起票時に所有者を担当者にし、読み戻して確かめる。割り当てられていなければ警告を出して続行する。本文の冒頭に所有者へのメンションを入れる
- **Rationale**: 割り当てが無視されてもメンションで通知が届く。割り当ての失敗でワークフローを赤にしても、その赤は人間に届かない
- **Follow-up**: 導入時の手動実行で、通知が届くことと担当者が付くことを人間が確認する

## Risks & Mitigations
- 通知スクリプトのテスト失敗・Issue操作の失敗で通知が出ない — 受け入れる(見張りを見張る入れ子を作らない)。ワークフローは赤になり、手動で実行履歴を見たときに分かる
- GITHUB_TOKEN での担当者割り当てが黙って無視される — メンションとの併用。導入時に実地確認する
- 判定不能が一時的なAPI障害で起きるたびにIssueが開く — 固定タイトルで1件だけ持ち、次回の正常な実行で自動で閉じる。件数は増えない
- 逸脱ありで実行が緑になることで、実行一覧の赤だけを見て異常を探す運用が成り立たなくなる — 監査手順書で「Issueが来たときに対処する」と明記する

## References
- [Events that trigger workflows](https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows) — 定期実行の通知の宛先と、60日で無効になる条件
- [List workflow runs for a workflow](https://docs.github.com/en/rest/actions/workflow-runs#list-workflow-runs-for-a-workflow) — `status=completed`
- [Add assignees to an issue](https://docs.github.com/en/rest/issues/assignees#add-assignees-to-an-issue) — 割り当てが黙って無視される条件

## 設計レビュー(2026-09-25、独立レビュー)
- **反映(重大)**: 判定スクリプト4本は `${n:?}` と `set -e` により、配線ミスや想定外の失敗でも終了コード1を返しうる。1を「逸脱あり=成功」とする新契約ではこれが見かけの合格になるため、明示の検査と `trap 'exit 2' ERR` で2に倒す設計に改めた。`check-container-scan.sh` 56-61行が同じ理由で同じ対処をしている(実物で確認)
- **反映**: 通知スクリプトのテストを判定の後ろへ移し、テストが落ちても判定結果が Job Summary に残るようにした
- **反映**: 残余リスク3点(窓の穴、死活は完了のみを見る、通知の第3経路はWatch)を設計と手順書に明記する
- **反映**: 監査手順書の訂正対象に218・219行を追加。audit-automation spec の要件4・6-4・6-5 に置き換えの注記を加える
- **不採用**: 監査手順書41行の訂正の指摘。41行は codex-review の打ち切りの節で、監査の通知とは関係しない
