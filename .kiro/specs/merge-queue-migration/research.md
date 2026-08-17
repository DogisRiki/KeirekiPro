# Research Log — merge-queue-migration

調査日: 2026-08-17

## 調査の範囲

merge queue の仕様と、このリポジトリが使う3つのGitHub Actionの `merge_group` 対応。
いずれも公式ドキュメントとピン止めSHAの実装ソースで確認した。推測は含めない。

## 1. merge_group イベントのペイロード

アクティビティタイプは `checks_requested` のみ。`merge_group` オブジェクトのフィールドは
5つで全部(スキーマが `additionalProperties: false`)。

| フィールド | 意味 |
|---|---|
| `head_sha` | マージ列のSHA |
| `head_ref` | マージ列の完全なref(`gh-readonly-queue/{base}` プレフィックス) |
| `base_ref` | マージ先ブランチの完全なref |
| `base_sha` | マージ列の親コミットのSHA |
| `head_commit` | `head_sha` の展開(id / tree_id / message / timestamp / author / committer) |

`github.sha` はマージ列のコミット、`github.ref` はマージ列のref を指す。

**`github.event.pull_request` は存在しない。** また **元のプルリクエストを特定する
フィールドも無い。** PR番号もPRの一覧もペイロードのどこにも定義されていない。

`head_commit.message` からPR番号を推測する方法は公式ドキュメントに記載が無く、
慣行にすぎない。

- https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows#merge_group
- https://github.com/octokit/webhooks/blob/main/payload-schemas/api.github.com/merge_group/checks_requested.schema.json

### 設計への含意

R3 の「プルリクエスト段階で確定した結果を引き継ぐ」は、**マージ列から元のPRを引いて
結果を読み取る形では実装できない。** マージ列では同名のチェックを無条件に成功として
報告する形になる。この事実を残余リスクとして明記する必要がある(R3.4)。

## 2. 必須ステータスチェックの評価

**PR側とマージ列側の両方で評価される。** キュー投入の条件としてPR側の必須チェック通過が
必要で、さらにマージ列でも再評価される。

ワークフローは `merge_group` イベントで発火させ**なければならない**。報告されない
チェックは、設定したタイムアウトの経過後に失敗とみなされる。

> Maximum time for a required status check to report a conclusion. After this much
> time has elapsed, checks that have not reported a conclusion will be assumed to
> have failed

スキップの扱いは pull_request と同じ。

| スキップの種類 | 扱い |
|---|---|
| ジョブレベルの `if:` | **Success として報告される** |
| ワークフローのpathフィルタ等 | **Pending のまま残りマージをブロックする** |

成功扱いになるのは `success` / `skipped` / `neutral`。この挙動が merge_group で
異なるという記載は無い。

**チェック名の一致は明文化されていない**が、必須チェックは名前で判定され、
同名がマージ列で報告されないとマージが失敗する構造のため、実質的に同名が必要。

- https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/configuring-pull-request-merges/managing-a-merge-queue
- https://docs.github.com/en/pull-requests/how-tos/merge-and-close-pull-requests/troubleshooting-required-status-checks

### 設計への含意

**pathフィルタをワークフローレベルに付けてはいけない。** これは既存の
`dependency-review.yaml` の冒頭コメントが既に述べている方針と一致する。

## 3. キューの設定項目

| UI設定 | REST パラメータ | 範囲 |
|---|---|---|
| Merge method | `merge_method` | MERGE / SQUASH / REBASE |
| Build concurrency | `max_entries_to_build` | 0〜100 |
| Only merge non-failing pull requests | `grouping_strategy` | ALLGREEN / HEADGREEN |
| Status check timeout | `check_response_timeout_minutes` | 1〜360 |
| Merge limits | `min_entries_to_merge` / `max_entries_to_merge` | 0〜100 |
| 最小数を待つ時間 | `min_entries_to_merge_wait_minutes` | 0〜360 |

**各設定の既定値は公式ドキュメントにもOpenAPIにも記載が無い。** RESTでは全パラメータが
required 扱いで default 定義が無い。

ワイルドカードを含むブランチ保護ルールでは merge queue を有効化できない。

`Require branches to be up to date` との併存可否は明文が無い。公式は
「merge queue が同等の保証を提供するので up-to-date 要求は不要になる」という
位置づけのみ述べている。

- https://docs.github.com/en/rest/repos/rules?apiVersion=2022-11-28

### 設計への含意

既定値が不明なため、**マージ方式とタイムアウトは明示的に指定する。**
指定しないと squash 規約が崩れる可能性があり、タイムアウトが
`docker-smoke` の45分を下回る可能性もある。

## 4. auto-merge との関係(最重要)

キュー必須ブランチではPRのUIが「Merge when ready」になり、押すとキューに入る。

gh CLI の挙動(cli/cli `pkg/cmd/pr/merge/merge.go`):

- 必須チェックが通っていればキューに投入、通っていなければ auto-merge を有効化する
- **`--squash` 等の指定はエラーにならず警告のみ。** マージ方式はキュー側の設定で決まる
  (`The merge strategy for %s is set by the merge queue`)
- キュー必須時は `payload.auto = true` に強制される
- **`-d` / `--delete-branch` はキュー有効時にエラーになる**
- すでにキューにあるPRには `ErrAlreadyInMergeQueue`

### Dependabot の制約

> If the target branch uses a merge queue, the built-in `GITHUB_TOKEN` cannot add
> pull requests to the queue. In this case, you must authenticate the workflow with
> a personal access token or a GitHub App token that has permission to merge, and
> use it in place of `GITHUB_TOKEN` for the `gh pr merge` step

- https://docs.github.com/en/code-security/tutorials/secure-your-dependencies/automate-dependabot-with-actions

### 設計への含意(判断が要る)

現在の `dependabot-auto-merge.yaml` は `github.token` を使っている。
**merge queue 導入後、このままではDependabotのPRがキューに入らない。**

さらに、このワークフローはDependabotのPRを起点とするため **Actions secrets を
参照できない**(#127 の制約1)。使えるのは Dependabot secrets に登録した鍵だけ。

これは #127 が「鍵の管理点が2箇所に増える」として避けた費用そのものであり、
merge queue では回避できない。

`/ship` が使う `gh pr merge --auto --squash` は、警告は出るが動作する。
`--squash` が無視されるだけなので、コマンド自体の変更は必須ではない。

## 5. 権限

merge_group 固有の `GITHUB_TOKEN` 既定権限の記載は無い。一般則
(リポジトリ設定の既定)のみ。`pull-requests: write` が merge_group で意味を持つかも
記載が無い。

`pull_request_review` を起点にするワークフローが merge queue 導入後どう扱われるかも
記載が無い。

## 6. キューが詰まったときの挙動

タイムアウト時、チェックは失敗扱いとなりPRはキューから**自動で除外される**。
除外理由はPRのタイムラインに表示される。除外後、後続PRの一時ブランチは
除外PRを含まない形で再作成される。

公式が列挙する除外理由は4つ。CI失敗 / タイムアウト / APIまたはUIからの除外要求 /
自動解決できないブランチ保護の失敗。

**人間が取り出す方法**: PRページの「Remove from queue」ボタン、またはキュー画面。
**gh CLI では取り出せない。**

キュー全体が止まった場合の公式の復旧手順は記載が無い。管理者の直接マージ
(ブランチ保護のバイパス)のみが関連する記述。

## 7. 3つのアクションの merge_group 対応

| アクション | 対応 | 根拠 |
|---|---|---|
| `actions/dependency-review-action` v5.0.0 | **ネイティブ対応** | `src/git-refs.ts` に `merge_group` の分岐。`base_sha`/`head_sha` を自動採用 |
| `gradle/actions/dependency-submission` v6.3.0 | イベント分岐は無いが動作 | `getShaFromContext()` が PR系イベント以外では `context.sha` を返す。merge_group では `GITHUB_SHA`(マージ列のコミット)になる |
| `dorny/paths-filter` v4.0.3 | **ネイティブ対応**(v4.0.1で追加) | `src/main.ts` に `merge_group` の分岐。`base_sha`/`head_sha` を採用し `git diff` 経路で判定 |
| `gitleaks/gitleaks-action` v3.0.0 | **非対応** | `src/index.js` の `supportedEvents` は push / pull_request / workflow_dispatch / schedule の4つ。リスト外は `core.error("ERROR: The [${eventType}] event is not yet supported")` の後 `process.exit(1)`。ピン止めSHAは v3.0.0 タグと一致し、それが最新タグ。上流の対応要望 gitleaks-action#118 / #186 / #189 はいずれも open |

### 落ち方

- `dependency-review-action`: refs が決まらなければ throw して失敗する。静かに成功しない。
  ただし **head SHA のスナップショットが未送信だと「差分なし」で緑になる**(既知)
- `dependency-submission`: 生成・送信の失敗は既定でジョブ失敗
  (`dependency-graph-continue-on-failure` の既定が false)。
  空のスナップショットで exit 0 になる件は #204 で対処済み
- `paths-filter`: merge_group は対応済み。未知のイベントでは既定ブランチとの
  merge-base 比較にフォールバックする設計(そちらは wrong-but-green になりうる)

### gitleaks の扱い

`merge_group` で発火させると `exit 1` で失敗し、必須チェックが赤になってキューが詰まる。
現在のジョブは `if: github.event_name == 'pull_request'` を持つため、トリガを足しても
スキップ(成功扱い)になり、追加の変更は要らない。

再走査を諦める判断は次の理由による。マージ列のコミットは base と各PRのコミットを
GitHub が機械的に重ねたもので、新しい内容を生まない。main に入った内容はすべてPR段階で
走査済みであり、衝突するPRは同時にキューへ投入できない。

### 設計への含意(最重要の落とし穴)

`dependency-review.yaml` の submit ジョブは次の条件を持つ。

```yaml
if: github.event.pull_request.head.repo.full_name == github.repository
```

**merge_group では `github.event.pull_request` が存在しないため false になり、
submit がスキップされる。** その状態で review は動くが、スナップショットが送られて
いないため「差分なし」で緑を返す。

`merge_group:` トリガを足しただけだと、**依存の検査が静かに無効化される。**

## 8. 未確認のまま残る事項

| 事項 | 検証手順 |
|---|---|
| キュー解体後、到達不能SHAに紐づくスナップショットがどうなるか | merge_group の run 後に `gh api /repos/{owner}/{repo}/dependency-graph/compare/{base_sha}...{head_sha}` を、直後とキュー解体後の2時点で比較する |
| `GITHUB_SHA` と `merge_group.head_sha` の同一性 | merge_group の run で両方を出力して突き合わせる |
| 各キュー設定の既定値 | 有効化後に Rulesets API で実際の値を読む |
| merge_group での `GITHUB_TOKEN` 既定権限 | 有効化後に実測する |

## 9. リポジトリ側の棚卸し

### `pull_request` 文脈への依存

| ワークフロー | 参照数 | 参照しているもの |
|---|---|---|
| `ci.yaml` | 1 | `number`(concurrency のみ) |
| `guardrails.yaml` | 19 | `base.sha` `head.sha` `body` `number` |
| `dependency-review.yaml` | 7 | `base.sha` `head.sha` `head.repo.full_name` `number` `user.login` |
| `terraform-plan.yaml` | 0 | 無し(paths-filter が既定で解決) |
| `dependency-gate.yaml` | 6 | `base.sha` `head.sha` `number` |
| `pre-merge-check.yaml` | 3 | `head.sha` `number` |
| `codex-review.yml` | 11 | 上記に加えて `draft` `title` `head.ref` 等 |

### concurrency グループ

`github.event.pull_request.number` を参照している箇所は、merge_group で空文字になり
すべてのマージ列が同じグループ名になって互いをキャンセルする。

| ワークフロー | 現在の式 | 対応 |
|---|---|---|
| `ci.yaml` | `format('ci-pr-{0}', ...number \|\| github.run_id)` | フォールバック済み。変更不要 |
| `codex-review.yml` | `codex-review-${{ ...number }}` | 要修正 |
| `dependency-gate.yaml` | `dependency-gate-${{ ...number }}-${{ event_name }}` | 要修正 |
| `dependency-review.yaml` | `dependency-review-${{ ...number }}` | 要修正 |
| `guardrails.yaml` | `guardrails-${{ ...number }}-${{ event_name }}` | 要修正 |
| `pre-merge-check.yaml` | `pre-merge-check-${{ ...number }}-${{ event_name }}` | 要修正 |

### 既存の鍵

`BOT_GITHUB_TOKEN` が Actions secrets に登録済み(`canary.yaml` で使用)。
Dependabot secrets への登録状況は未確認。

## 10. 文書のずれ(切り替えとは別に解消が必要)

`doc/開発フロー/基盤構築手順.md` に2点のずれがある。

- 41行目: `Require branches to be up to date before merging | ✅` だが、実際は無効
- 124〜139行目: 必須チェックの一覧が15本。実際は18本で
  `docker-smoke` `detect-changes` `detect-terraform-changes` が未記載

いずれも PR #200 と #208 で生じたもの。R6.5 で解消する。
