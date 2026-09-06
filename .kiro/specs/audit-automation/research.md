# Research & Design Decisions

## Summary
- **Feature**: `audit-automation`
- **Discovery Scope**: Extension(既存の `.github/` ワークフロー群への追加。light discovery)
- **Key Findings**:
  - 判定材料はすべてGitHub APIの読み取りだけで揃う(2026-09-03〜06の障害対応・カナリア検証で全エンドポイントを実測済み)
  - 「承認待ちによる赤」(dependency-gate / escape-hatch / pre-merge-check)は必須チェックの失敗として現れるため、滞留検知はこれを異常から除外する分類が必要
  - スキップの正当性はAPIからは判別できないため、必須チェックごとに「常時実行/条件付き実行」の区分をリポジトリ内の期待一覧に持たせる必要がある

## Research Log

### 定期スキャンの実行情報の取得(要件1)
- **Context**: 「前回成功から8日」の判定材料
- **Sources Consulted**: `.github/workflows/container-scan-scheduled.yaml`(name: Scheduled Container Image Vulnerability Scan、cron `17 3 * * 3` = 毎週水曜)、GitHub Actions API(`/actions/workflows/{file}/runs`)
- **Findings**: ワークフローファイル名指定で `status=success&per_page=1` の1リクエストで直近成功が取れる。週1実行に対し8日しきい値は1回の欠落で赤になる正しい間隔
- **Implications**: 判定はAPI 1リクエスト+日時比較のみ。外部依存なし

### Dependabot PRの滞留状態の分類(要件2)
- **Context**: 「失敗で止まっている」と「承認待ちで止まっている」の区別
- **Sources Consulted**: 2026-09-03の実測(PR #323/#324は escape-hatch が承認待ちで failure 表示、#314は dependency-review が障害で failure)、`doc/開発フロー/監査手順.md` 週次6
- **Findings**: 承認待ちは dependency-gate / escape-hatch / pre-merge-check の failure として現れ、チェック結論だけでは「本物の失敗」と区別できない。ただしこの3つは承認によって緑になる設計のチェックであり、コンテキスト名で静的に分類できる
- **Implications**: 期待一覧に `approval_gated` 属性を持たせ、これらの failure は「承認待ち」として異常から除外・報告のみとする

### スキップ検知の判定基準(要件3)
- **Context**: 「実行されるべきだったのに skipped」の機械判定
- **Sources Consulted**: 2026-09-03の実測(codex-review が有効化フラグ未設定で全PR skipped、必須チェックのスキップは成功扱い)、ci.yaml の paths-filter 構成、ruleset API(`/repos/{o}/{r}/rules/branches/main`。botトークンで動作確認済み。公開リポジトリのため読み取りに管理者権限は不要)
- **Findings**: GitHubはスキップの理由(paths-filter起因か、if条件起因か)をAPIで公開しない。よって「このチェックは変更内容によらず常に実行されるべき」(例: gitleaks, size-check, escape-hatch, codex-review)か「変更検知により条件付きで実行される」(例: backend-test, frontend-test)かを、期待一覧の `mode: always|conditional` として宣言的に持つしかない
- **Implications**: 検知対象は `mode: always` かつ `state: active` のチェックの skipped に限定。conditional のスキップ正当性は既存のカナリア(backend-failure等)が実行系を検証する
- **併せて**: 必須チェック一覧のリポジトリ内ファイル化により、Issue #310の「一覧がruleset側にしか無い」問題も解消(集合の一致を毎週照合)

### カナリアPRの特定と期待値(要件5)
- **Context**: 月次1の照合の機械化
- **Sources Consulted**: `.github/scripts/create-canary-prs.sh`(ブランチ命名 `canary/<type>-<YYYYMM>`、6種)、canary.yaml(cron `0 0 1 * *`)、監査手順 月次1の期待表、2026-09-01生成分の実測
- **Findings**: 種別→期待チェックの対応は known-bug→codex-review / assertless-test→frontend-test / skipped-test→escape-hatch / backend-failure→backend-test / vulnerable-dep→dependency-review / container-vuln→container-scan。ブランチ名から当月分を決定的に特定できる。照合は head ブランチのPR検索+チェック結論の取得で完結
- **Implications**: 発火は毎月4日(生成の3日後)。種別→期待チェックの対応表は照合スクリプト内の定数とし、停止状態のみ期待一覧を参照する

### 死活ステップの置き場所(要件4)
- **Context**: 「1日200回走るci.yamlに1ステップ寄生」の具体位置
- **Sources Consulted**: `.github/workflows/ci.yaml`(detect-changes ジョブが全PRで最初に実行され軽量)
- **Findings**: detect-changes は必須チェックであり全PRで必ず走る。ここに1ステップ足せば追加ジョブなし・追加ランナー起動なしで済む
- **Implications**: `actions: read` 権限の追加が必要(現在 `contents: read` のみ)。判定はAPI 1リクエスト

## Architecture Pattern Evaluation

| Option | Description | Strengths | Risks / Limitations | Notes |
|--------|-------------|-----------|---------------------|-------|
| 検査スクリプト+同梱テスト(既存パターン) | bash + gh api + jq、ワークフロー内で自テスト実行後に本判定 | リポジトリの実績パターン(check-dependency-cooldown等9本)。レビュー・監査の一貫性 | bashの複雑化に上限がある | 採用 |
| 判定ロジックをワークフローYAMLに直書き | スクリプト分離なし | ファイル数が減る | テスト不能。escape-hatch的にも検証しづらい | 不採用 |
| 外部監視サービス | Datadog等 | 実装量最小 | 外部送信=承認対象、費用、Issue #310で明示的に不採用 | 不採用 |

## Design Decisions

### Decision: 期待一覧(required-checks manifest)のスキーマ
- **Context**: 要件3-1〜3-4。スキップ判定・承認待ち分類・停止記録の3つの情報が必要
- **Alternatives Considered**:
  1. チェック名の配列のみ — スキップの正当性判定ができない
  2. 名前+mode+state+approval_gated の構造化JSON — 3情報を1ファイルで宣言
- **Selected Approach**: `.github/audit/required-checks.json` に `{context, mode: always|conditional, state: active|paused, approval_gated: bool, reason?, issue?}` の配列を置く
- **Rationale**: `.github/` 配下のためCODEOWNERSにより変更が所有者承認必須になり、要件3-3(停止記録の承認)が機械強制される
- **Trade-offs**: rulesetと二重管理になるが、毎週の集合照合(要件3-4)がずれを検知する
- **Follow-up**: 初期値はrulesetの現行19コンテキスト。codex-review は `paused`(参照 #166)

### Decision: 停止記録に期限を設けない(要件レビューからの持ち越し論点)
- **Context**: container-scan-suppressions.json は期限必須だが、期待一覧の `paused` はどうするか
- **Alternatives Considered**:
  1. 期限必須 — 期限切れで週次が赤になる
  2. 期限なし+参照Issue必須 — 追跡はIssueのopen状態に委ねる
- **Selected Approach**: 期限なし。ただし参照Issueを必須フィールドとし、週次の報告に停止中一覧を毎回明示する
- **Rationale**: 脆弱性抑制と違い、停止の妥当性は日付では失効しない(#166の再開判断はIssue側の進捗に依存する)。期限切れの機械赤はアラーム疲れを生み、今回の障害対応で確認した「赤の常態化がパイプラインを止める」リスクの方が大きい
- **Trade-offs**: 無期限停止が放置されうる。緩和として、対応Issueがcloseされたのに `paused` が残っている状態を週次照合の異常(要件3-4の不一致に準ずる)として扱うかは実装時のオプションとし、初版では報告明示のみとする

### Decision: 週次の対象期間は「前回実行」基準+初回7日
- **Context**: 要件3-5
- **Selected Approach**: 自ワークフローの直近実行(成功に限らない)の作成日時を下限とし、無ければ7日前
- **Rationale**: 「前回成功」基準だとマージ済みPRのスキップ検知が恒久的に赤になる(取り消せない過去を毎週再検知する)。前回実行基準なら、検知→人間対応→翌週から正常、で収束する

## Risks & Mitigations
- GitHub APIの一時的失敗で誤赤 — 判定不能は「判定不能」と明示して失敗させる(cooldownの既存パターン)。再実行で解消
- ruleset読み取りがGITHUB_TOKENで不可の環境変化 — 週次の集合照合が「取得失敗」として赤になり気づける(黙って素通りしない)
- 週次と死活の連鎖誤爆(要件レビューmust 1) — 期待一覧の `paused` で遮断済み。導入時に codex-review を paused で登録することが前提条件
- カナリア生成の仕様変更(命名・件数) — 照合スクリプトの定数と生成スクリプトが乖離しうる。生成側ファイルの変更をレビューで拾う運用とし、6件未満は常に赤で気づける

## References
- [Issue #310](https://github.com/DogisRiki/KeirekiPro/issues/310) — 判定表・採らないと決めたこと・進め方
- [GitHub REST: Workflow runs](https://docs.github.com/en/rest/actions/workflow-runs) — 直近成功の取得
- [GitHub REST: Rules for a branch](https://docs.github.com/en/rest/repos/rules) — 必須チェック集合の取得(2026-09-03に実測)
- 監査手順.md 週次6・週次8・月次1 — 置き換え対象の現行判定
