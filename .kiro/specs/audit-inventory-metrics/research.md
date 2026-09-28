# Research & Design Decisions

## Summary
- **Feature**: `audit-inventory-metrics`
- **Discovery Scope**: Extension(既存の監査の仕組み・mutation の台帳・Dependabot の設定の拡張。外部の公開APIを新たに使う)
- **Key Findings**:
  - Dependabot は Dockerfile の `FROM` 行だけを読み、`AS <name>` 付きも検出する。tflint は `FROM ghcr.io/terraform-linters/tflint:vX AS tflint` のステージにすれば追える。ただし **ghcr.io のイメージには Dependabot の既定のクールダウン(3日)が効かない**
  - サポート期限は endoflife.date v1 の `/products/{slug}/releases/{cycle}` と `/releases/latest` で機械的に取れる。LocalStack は扱われておらず、GitHub のリリース(v4.14.0)も Docker のタグ(2026.8.4)と一致しないため、Docker Hub のタグ一覧から取る
  - 既存の鮮度確認(`check-audit-scan-freshness.sh`)は、対象のワークフローが未登録なら判定不能、成功0件なら逸脱ありにする。導入直後はマージ後の手動実行が要る

## Research Log

### 既存の監査の仕組みとの接点
- **Context**: 棚卸しは週次監査と別に動かし、止まったことだけを週次監査で見る(要件5)
- **Sources Consulted**: `.github/workflows/audit-weekly.yaml`、`.github/scripts/check-audit-scan-freshness.sh`、`.github/scripts/audit-issue.sh`
- **Findings**:
  - 週次監査の `run_check <name> <title> <script> [args...]`(audit-weekly.yaml:157-197)は終了コード 0/1/2 を集約する。1本でも 2 なら全体が判定不能になる(174-195)
  - `check-audit-scan-freshness.sh <workflow_file> <threshold_days>` は `runs?status=success&per_page=1` を引く(105-106)。event とブランチで絞らないため、手動実行の成功も数える。成功0件は exit 1(118-129)、未登録(404)は exit 2(105-108)
  - 報告の見出しが「定期スキャン」で固定されている(85, 120, 144)。棚卸しに使うと文面が合わない
  - audit-weekly.yaml のヘッダは「GitHub以外の外部サービスへの問い合わせなし」(36)。棚卸しを同居させない根拠になる
  - `audit-issue.sh` の担当者の割り当ては `gh api -X POST repos/${REPO}/issues/${number}/assignees -f "assignees[]=${OWNER}"` で行い、失敗は警告で続行する(256-278)。メンションは本文の先頭行の `@OWNER`(144)
- **Implications**: 鮮度確認のスクリプトに表示名の引数を足し、既存の呼び出しは変えない。担当者の割り当てとメンションは同じ方式を使う

### mutation の台帳の現状
- **Sources Consulted**: `.github/workflows/mutation-report.yaml`、`.github/scripts/record-mutation-metrics.sh`
- **Findings**:
  - 全件か差分かの判定は「Download previous Stryker report」ステップ(54-77)の中だけにあり、`id` もステップの出力も無い。record 側はどちらの回かを知らない
  - 全件になる条件は3つある。月初の定期実行(`schedule` かつ UTC の日が7以下)、手動実行で `full` を選んだとき、前回の成果物が無い・取得できないとき(68-70, 75-76)
  - backend(PIT)は毎回全件を測る。差分があるのは frontend(Stryker)だけ
  - 台帳は本文の表への追記(`gh issue edit`、134行)で、通知が出ない。担当者の割り当てもメンションも無い
  - 表の列は `| 実行日(UTC) | backend(PIT) | frontend(Stryker) | 実行 |`(117)
- **Implications**: 判定ステップに出力を付け、job の outputs で record に渡す。表に列を足すと既存の行と列数が合わないため、新しい表を本文の末尾に始める

### カバレッジの値の取り方
- **Sources Consulted**: `.github/workflows/ci.yaml`、`frontend/vite.config.ts`、`backend/gradle/quality.gradle`、GitHub Docs
- **Findings**:
  - frontend: `vite.config.ts:92` の `json-summary` で `frontend/coverage/coverage-summary.json` が出る。基準値は 93-98行(statements 79 / branches 59 / functions 80 / lines 80)
  - backend: `quality.gradle:73-78` で `backend/build/reports/jacoco/test/jacocoTestReport.xml` が出る。基準値は 86-112行の `counter` と `minimum`(LINE 0.93 / BRANCH 0.73 / INSTRUCTION 0.93)。JaCoCo の XML は、レポート全体の counter を末尾に置く
  - 成果物: `frontend-test-results`(ci.yaml:192-200)と `backend-check-results`(279-287)。どちらも `if: always()`、保持7日、PR と main への push の両方で上がる。ただし job は変更検知に従い、変更の無い run では作られない
  - 保持期間の上限は公開リポジトリで90日(https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/enabling-features-for-your-repository/managing-github-actions-settings-for-a-repository)。`retention-days` はリポジトリの設定を超えられない(https://docs.github.com/en/actions/tutorials/store-and-share-data)。リポジトリは PUBLIC(`gh repo view` で確認)
  - main の成果物を artifacts API で拾う前例がある(mutation-report.yaml:64-66。`workflow_run.head_branch == "main"` で絞る)
- **Implications**: 保持期間は main への push の実行だけ90日にし、PR は7日のままにする。基準値はゲート設定のファイルから読む(値を二重に持たない)

### Dependabot の対応範囲
- **Sources Consulted**:
  - https://raw.githubusercontent.com/dependabot/dependabot-core/main/docker/lib/dependabot/docker/file_parser.rb (L19-21, L41-50)
  - https://raw.githubusercontent.com/dependabot/dependabot-core/main/docker/lib/dependabot/shared/shared_file_parser.rb (L21-30)
  - https://raw.githubusercontent.com/dependabot/dependabot-core/main/docker/lib/dependabot/docker/update_checker.rb (L442-460, L489-497, L869-915)
  - https://raw.githubusercontent.com/dependabot/dependabot-core/main/docker/lib/dependabot/docker/tag.rb (L14-17)
  - https://raw.githubusercontent.com/dependabot/dependabot-core/main/common/lib/dependabot/dependency_group.rb (L65-121)
  - https://docs.github.com/en/code-security/reference/supply-chain-security/dependabot-options-reference
  - https://docs.github.com/en/code-security/reference/supply-chain-security/supported-ecosystems-and-repositories
  - https://raw.githubusercontent.com/dependabot/dependabot-core/main/github_actions/lib/dependabot/github_actions/file_parser.rb (L55-80)
- **Findings**:
  - `FROM_LINE` は `AS <name>` を任意の要素として受け付ける。`COPY --from=<image>` は読まない
  - ghcr.io の公開イメージは認証なしで扱える。依存名はレジストリを含まず `terraform-linters/tflint` になる
  - `v0.60.0` のような `v` 付きのタグも比較できる。0.x の更新は minor 扱いで、1.0 への更新は major 扱い(今の ignore で止まる)
  - **Docker Hub 以外のレジストリでは公開日時を取れず、クールダウンの判定を飛ばす**(update_checker.rb L442-460)。ghcr の tflint には既定の3日が効かない
  - `groups.<name>.exclude-patterns` は依存名にワイルドカードで照合し、除外が優先される
  - pip は任意の `.txt` の requirements を扱い、既定のクールダウン3日がかかる
  - ワークフローの `env:` に書いた版(`TRIVY_VERSION`)は扱わない。github-actions のエコシステムは `uses:` だけを読む
- **Implications**: tflint は `FROM ... AS tflint` にして、docker のまとめPRから外す。ghcr のクールダウンが効かない点は残余リスクとして記録する。Trivy は対象外のまま

### 外部の公開情報の取得元
- **Sources Consulted**: https://endoflife.date/docs/api/v1/openapi.yml (L13-70, L203-262, L871-875)、各製品の実測(2026-09-28〜29)、https://docs.pypi.org/api/json/ 、Docker Hub の tags API の実測
- **Findings**:
  - endoflife.date v1: 系列ごとに `isEol` `eolFrom` `isMaintained` `isLts` `latest.name` を返す。`releases` の並び順は保証されていないため、最新の系列は `/releases/latest` で取る。存在しない系列は404(本文はHTML)。数値のレート制限の記載は無く、429 と `Retry-After` がありうる。後方互換の方針が明記されている(/api/v1 を使い続ける、新しいフィールドを許容する)。Beta の表記は無い
  - 系列名の形式は製品ごとに違う: eclipse-temurin `21`、nodejs `24`、postgresql `17`、amazon-rds-postgresql `17`(`17.4` は404)、redis `7.4`、valkey `8.0`、terraform `1.16`、docker-engine `27`
  - 最新の系列は LTS とは限らない(nodejs 26、eclipse-temurin 26 は LTS ではない)。`isLts` を併記する必要がある
  - terraform は `eolFrom` が null(期限が未定)
  - docker-engine 27 は `isEol: true`、`eolFrom: 2025-05-03`
  - GitHub `releases/latest`: trivy v0.74.0、tflint v0.64.0、tflint-ruleset-aws v0.49.0(2026-09-29)
  - LocalStack: GitHub のリリースは v4.14.0 で止まっていて、Docker のタグ(年.月.連番)と対応しない。Docker Hub の `https://hub.docker.com/v2/namespaces/localstack/repositories/localstack/tags?page_size=100&ordering=last_updated` から、`^[0-9]{4}\.[1-9][0-9]?\.[0-9]+$`(月の先頭の0を許さず、別名の 2026.08.4 を除く) に一致するタグを版として比べる
  - PyPI: `https://pypi.org/pypi/checkov/json` の `info.version` が最新(3.3.20)
- **Implications**: 取得元は4種類(endoflife.date、GitHub のリリース、PyPI、Docker Hub)。どれも公開情報の読み取りで、送るのは製品名だけ

### 版の宣言の場所
- **Findings**(2026-09-29 時点):
  - Node.js: `docker/frontend/Dockerfile:1` は 24.21.0、ワークフローの `node-version` は 24.16.0(ci.yaml:160, 222 ほか)で食い違っている
  - Terraform: `docker/terraform/Dockerfile:1` は 1.16.4、`terraform-plan.yaml:14` と `terraform-apply.yaml:21` の `TF_VERSION` は 1.9.0 で食い違っている
  - Java: Dockerfile 2本(`21-jdk` / `21-jre`)と `backend/build.gradle:112` の toolchain(21)
- **Implications**: 同じ対象の宣言が複数あるときは、全ての場所と値を表に載せる。食い違いは表から読める(判定はしない)

## Architecture Pattern Evaluation

| Option | Description | Strengths | Risks / Limitations | Notes |
|---|---|---|---|---|
| 週次監査に同居 | audit-weekly に判定項目として足す | 仕組みが1つ | 外部の失敗が週次監査全体を判定不能にし、逸脱の通知を止める。ヘッダの方針にも反する | 不採用 |
| 別ワークフロー+台帳Issue | 月1回の別ワークフローが表をコメントで届ける。死活は週次監査の鮮度確認に加える | 外部の失敗が既存の判定に及ばない。見張りの仕組みが増えない | ワークフローが1本増える(README の表と図の更新) | 採用 |
| 対象ごとの専用スクリプト | 対象ごとに取得の処理を書く | 個別の事情に強い | 対象の追加のたびにコードが増える | 不採用。対象は設定ファイルに書く |

## Design Decisions

### Decision: 対象を設定ファイルに書き、収集のスクリプトは汎用にする
- **Context**: 対象は12あり、取得元は4種類に収まる
- **Alternatives Considered**:
  1. スクリプトに対象ごとの処理を書く
  2. 対象の一覧(宣言の場所の正規表現・取得元の種類・系列の取り出し方)を JSON に書き、スクリプトは取得元の種類ごとの処理だけを持つ
- **Selected Approach**: 2。`.github/audit/inventory-targets.json` に置く(期待一覧 `.github/audit/required-checks.json` と同じ場所)
- **Rationale**: 対象の追加・宣言の場所の変更が、コードではなく設定の変更で済む
- **Trade-offs**: 正規表現を JSON に書くため、書き誤りは実行時に「読み取れず」として現れる。テストで全対象の宣言が今のリポジトリで読めることを確かめる
- **Follow-up**: 宣言が1件も読めない対象があれば、テストが落ちる

### Decision: 台帳Issueの操作を共通の関数にまとめる
- **Context**: 棚卸しとメトリクスの両方が「決まったタイトルのIssueを探し、無ければ作り、コメントで所有者にメンションし、担当者に割り当てる」
- **Selected Approach**: `.github/scripts/lib-ledger-issue.sh` を作り、両方のスクリプトから読み込む。既存の `record-mutation-metrics.sh` の探し方(`state=all`、タイトル完全一致、最小の番号)をそのまま移す
- **Rationale**: 同じ処理が2か所に分かれると、片方だけ直す事故が起きる

### Decision: mutation の台帳は新しい表を本文の末尾に始める
- **Context**: 測定方式の列を足すと、既存の行と列数が合わない
- **Alternatives Considered**:
  1. 既存の行を書き換えて列を足す(過去の行の測定方式は分からない)
  2. 新しい見出しの表を本文の末尾に足し、以後はそちらに追記する
- **Selected Approach**: 2。比較は新しい表の行だけを使う。導入直後は「比較対象なし」になる
- **Trade-offs**: 導入後の最初の全件の回は比較できない

### Decision: カバレッジは main の CI の成果物から読み、保持期間を main への push のときだけ90日にする
- **Context**: 要件3-4・3-9。所有者は測り直しを退けた
- **Selected Approach**: `ci.yaml` の2つの成果物の `retention-days` を `${{ github.event_name == 'push' && 90 || 7 }}` にする。全件の回に、artifacts API で main の直近の成果物を探して読む
- **Trade-offs**: 90日以上 frontend(または backend)に変更が無いと「取得できず」になる(要件3-6 で許容)

### Decision: tflint の更新PRは、GitHub のリリースの公開から72時間経つまで自動マージを予約しない
- **Context**: 要件4-6〜4-9。ghcr.io には Dependabot の既定のクールダウンが効かない(`docker/README.md` の Cooldown publication dates、`update_checker.rb` の `registry_tag_release_date`・`using_dockerhub?` を 2026-09-29 に一次資料で確認)
- **Alternatives Considered**:
  1. 残余リスクとして受け入れる(当初の設計)
  2. tflint の更新PRだけ所有者の承認を必須にする
  3. 別の配布経路から入れる(公式の Docker Hub のイメージは無い。`terraform-linters/tflint` は Docker Hub で404)
  4. 必須チェックとして赤で待たせる(ruleset の変更と、赤のまま止まったPRの再実行の仕掛けが要る)
  5. 自動マージの予約を、公開から72時間経つまで保留する
- **Selected Approach**: 5。所有者の判断(2026-09-29)。公開日時は GitHub のリリースの `published_at` を使い、イメージの中の作成日時は使わない(公開した側が自由に付けられるため。Dependabot も同じ理由で採用していない)
- **Rationale**: 公開から72時間待つ決まりは frontend(pnpm)と backend(dependency-cooldown)で既に採っており、tflint だけ例外にする理由が無い。人の作業が増えず、必須チェックと ruleset を触らない
- **Trade-offs**: 1日1回の見直しが止まると、保留したPRが開いたまま残る(残余リスクとして記録)

## Risks & Mitigations
- 外部の取得元の形式が変わる — 欄が「取得できず」になり、理由を表の下に書く。実行自体は成功する
- endoflife.date の系列名の付け方が製品ごとに違う — 系列の取り出し方を対象ごとに設定ファイルに書き、テストで実物の宣言から系列を作れることを確かめる
- ghcr の tflint に既定のクールダウンが効かない — 自動マージの予約を公開から72時間保留する。見直しが止まったときの残りは「受容した残余リスク」に足す
- 棚卸しの導入直後は成功0件で週次監査が逸脱を出す — マージ後に手動で1回実行する(tasks の最後の確認)

## References
- https://endoflife.date/docs/api/v1/openapi.yml — API の形と互換性の方針
- https://docs.github.com/en/code-security/reference/supply-chain-security/dependabot-options-reference — groups の exclude-patterns、既定のクールダウン
- https://docs.github.com/en/actions/tutorials/store-and-share-data — 成果物の保持期間
- https://docs.pypi.org/api/json/ — PyPI の JSON API
