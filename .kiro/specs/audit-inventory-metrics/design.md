# 設計

## 概要

この設計は、監査手順の定期作業のうち、人間の判断を含まない「調べて書き写す」部分を機械に移す。この設計は、ツールとランタイムの版・サポート期限(棚卸し)と、mutation スコア・カバレッジ(メトリクス)を月1回集め、判定をせずに台帳のIssueのコメントで所有者に届ける。

この設計の利用者は、リポジトリ所有者である。所有者は、コードを読まず、届いた表を読んで版の更新やテストの追加を Claude Code に指示する。

この設計により、所有者が配布元のサイトや台帳を開いて比べる作業が無くなる。定期の確認は残り、判断は人間が行う。あわせて、tflint と checkov の版の更新が Dependabot のPRで届くようになる。

## 作るものと作らないもの

### 作るもの

この設計は、次のことを目指す。

- 棚卸しの表が毎月1回、所有者に通知される形で届く
- mutation スコアの全件の回どうしの差と、カバレッジの実測・基準値が、月1回、通知される形で届く
- tflint と checkov の新しい版が Dependabot のPRとして届く。tflint の更新PRは、GitHub のリリースの公開から72時間経つまで自動マージを予約しない
- 棚卸しが止まったら週次監査の逸脱として届き、外部の不調は既存の監査に波及しない

この spec は、次のものを持つ。

- 棚卸しのワークフロー(`audit-inventory.yaml`)、収集のスクリプト、対象の設定ファイル、棚卸しの台帳のIssue(タイトル `棚卸し台帳: 版とサポート期限`)
- 台帳のIssueを探す・作る・コメントする・担当者に割り当てる共通の関数(`lib-ledger-issue.sh`)
- mutation の台帳への測定方式の記録、全件の回どうしの差の計算、月1回のコメント
- カバレッジの値と基準値の読み取り(`collect-coverage.sh`)と、CI の成果物の保持期間(main への push のときだけ90日)
- 週次監査の鮮度確認への棚卸しの追加と、鮮度確認のスクリプトの表示名の引数
- tflint と checkov の Dependabot への移管(Dockerfile・requirements.txt・dependabot.yml)
- tflint の更新PRの自動マージの予約を、公開から72時間経つまで保留する判定(`check-release-age.sh`)と、その判定を PR のイベントと1日1回の見直しで呼ぶこと(`dependabot-auto-merge.yaml`)
- 監査手順書の定期作業の表・版の確認先、README のワークフロー一覧と図、ワークフロー設計の自動チェック一覧と残余リスク、audit-automation / audit-notification の要件への注記

### 作らないもの

この設計は、次のことを目指さない。

- 版やスコアの良し悪しの判定、しきい値との比較、それに基づく逸脱の報告
- 版の更新やテストの追加そのもの
- Trivy の版の更新の自動化。Dependabot は `env:` を扱えない。2本の一致は、週次監査が既に確かめている
- 週次監査・カナリア照合の判定基準と問い合わせ先の変更

この spec は、次のものを持たない。

- 週次監査の判定項目(滞留・スキップ・期待一覧・Trivy の版の一致)の中身と、`audit-issue.sh` の通知の仕組み
- mutation testing の測定そのもの(Stryker・PIT の実行、全件にするかの条件)
- CI のテスト・カバレッジの判定(基準値の値、基準値を満たさないときに赤にする動き)
- Dependabot の docker レーンのほかの設定(メジャー更新の除外、他のイメージ)
- tflint 以外の Dependabot のPRの自動マージの扱い。tflint 以外のPRは、今までどおり、開いたときに予約される
- Dependabot 側のクールダウンの実装。ghcr.io で公開日時を取れないこと自体は、この spec では変えられない
- Trivy の版の宣言の場所と、その一致の確認
- 表を読んだ後の版の更新・テストの追加

## 使う既存の仕組み

- GitHub REST API(`gh api`。Issue・ラベル・担当者・Actions の実行と成果物・リリース)
- endoflife.date API v1(`https://endoflife.date/api/v1`)、PyPI JSON API(`https://pypi.org/pypi`)、Docker Hub の tags API(`https://hub.docker.com/v2`)。この設計は、これらへの問い合わせを、認証情報を送らない読み取りに限る(要件6-1)
- ランナーに入っている `bash` `jq` `curl` `gh`。この設計は、新しいライブラリやアクションを足さない
- 既存の `check-audit-scan-freshness.sh` と週次監査の `run_check`

## 設計を見直すきっかけ

- 台帳のIssueのタイトルや表の列を変えるとき。所有者が読む形と、比較で前の行を探す処理が変わる
- `mutation-report.yaml` の全件の条件を変えるとき。測定方式の出力と比較の対象が変わる
- `ci.yaml` の成果物の名前・中身のパスを変えるとき。カバレッジが読めなくなる
- `vite.config.ts` の `thresholds` や `quality.gradle` の `violationRules` の書き方を変えるとき。基準値が読めなくなる
- `check-audit-scan-freshness.sh` の引数を変えるとき。週次監査の2つの呼び出しが影響を受ける
- 外部の取得元の API の版が変わるとき
- tflint の置き場や入れ方を変えるとき。公開日時の取り方と、Dependabot の待ちが効くかが変わる

## プロジェクトの決まりを守っているか

- 新しいライブラリの追加: この設計は、アプリの依存を足さない。この設計は、開発環境の `docker/terraform/requirements.txt` に checkov を移すが、版(3.2.497)と入れ方(pip)は今と同じである
- 品質チェックの設定: **この設計は、品質チェックの設定の変更を含む。** `.github/`(ワークフロー・スクリプト・dependabot.yml・audit の設定)の変更には、所有者の承認が要る。この設計は、`vite.config.ts` と `quality.gradle` を読むだけで変えない。Claude は、この設計の変更を、承認つきのPRとして出す
- 使う外部の機能がこのリポジトリで使えるか: リポジトリは PUBLIC である(`gh repo view`)。成果物の保持の上限は90日である(公式ドキュメント)。Dependabot の pip と docker(ghcr を含む)は、公開リポジトリで使える。endoflife.date・PyPI・Docker Hub は、認証なしで読める(2026-09-29 実測)
- 関係のない項目: backend のコードを置く層(backend のコードを変えない)、frontend の機能ごとの境界(frontend のコードを変えない)、frontend の状態の持ち方、データベースの表の形(マイグレーションを含まない)

## 全体の構成

```mermaid
flowchart LR
    subgraph Monthly[月1回]
        INV[audit-inventory.yaml]
        MR[mutation-report.yaml 月初の全件の回]
    end
    subgraph Sources[公開情報]
        EOL[endoflife.date]
        GHR[GitHub Releases]
        PYPI[PyPI]
        DH[Docker Hub]
    end
    CI[ci.yaml main への push] -->|成果物 90日| ART[(frontend-test-results / backend-check-results)]
    INV --> EOL
    INV --> GHR
    INV --> PYPI
    INV --> DH
    INV -->|コメント+メンション| L1[棚卸し台帳のIssue]
    MR -->|読む| ART
    MR -->|行の追記+コメント| L2[メトリクス台帳: mutationスコア]
    AW[audit-weekly.yaml] -->|最終成功日を見る| INV
    AW -->|逸脱| AI[週次監査: 逸脱あり]
    L1 --> OWNER((所有者))
    L2 --> OWNER
    AI --> OWNER
```

- 選んだ型: この設計は、月1回の別ワークフローと台帳のIssueを使う。この設計は、外部の取得元と既存の週次監査のあいだに、実行の成否だけの接点を置く
- 守る既存の作り: 測った側が台帳に書く(#334)。台帳の探し方(`state=all`・タイトル完全一致・最小の番号)。担当者の割り当てとメンションの方式(`audit-issue.sh`)。スクリプトは `bash` で起動し、テストは `gh` と `curl` を PATH の先頭に置いた偽物で置き換える
- 新しい部品が要る理由: 棚卸しの収集(新しい取得元)と、カバレッジの読み取り(新しい入力)は、既存のどのスクリプトの責務にも入らない。そのため、この設計はこの2つを新設する。台帳の操作は2か所で使うため、この設計は台帳の操作を共通の関数にする

**使う技術**:
- 実行環境: GitHub Actions `ubuntu-latest`(既存と同じ)。月1回の実行を受け持つ。この設計は、新しいアクションを足さない。`actions/checkout` は、既存の SHA 固定の参照を使う
- スクリプト: bash + jq + curl + gh。収集・整形・Issue 操作を受け持つ。既存のスクリプトと同じ構成である
- 設定: JSON(`.github/audit/inventory-targets.json`)。対象の一覧を持つ。置き場所は `required-checks.json` と同じ場所である
- 外部: endoflife.date API v1 / PyPI JSON / Docker Hub v2 tags。最新版とサポート期限を返す。認証なしの読み取りである
- 依存の更新: Dependabot docker(ghcr)/ pip。tflint と checkov の更新PRを作る。更新PRは、既存の auto-merge の流れに乗る。tflint の更新PRだけ、公開から72時間の判定を挟む

## ファイルの構成

Claude が新しく作るファイル:

```
.github/
├── audit/
│   └── inventory-targets.json        # 棚卸しの対象の一覧(宣言の場所・取得元・系列の取り出し方)
├── scripts/
│   ├── collect-inventory.sh          # 棚卸し: 宣言を読み、外部から最新版と期限を集め、表を台帳にコメントする
│   ├── collect-coverage.sh           # main の直近の CI 成果物からカバレッジを、ゲート設定から基準値を読み、Markdown を出す
│   ├── lib-ledger-issue.sh           # 台帳のIssueを探す・作る・コメントする・担当者に割り当てる共通の関数(source して使う)
│   ├── check-release-age.sh          # Dependabot のPRの差分から tflint の更新を見分け、自動マージを予約してよいかを判定する
│   └── tests/
│       ├── test-collect-inventory.sh
│       ├── test-collect-coverage.sh
│       ├── test-lib-ledger-issue.sh
│       └── test-check-release-age.sh
└── workflows/
    └── audit-inventory.yaml          # 月1回(毎月2日)の棚卸し
docker/terraform/
└── requirements.txt                  # checkov の版の宣言(Dependabot の pip が読む)
```

Claude が変えるファイル:

- `.github/scripts/record-mutation-metrics.sh`: 測定方式の列を持つ新しい表への追記、全件の回どうしの差の計算、全件の回のコメント(カバレッジの Markdown を含む)を足す。台帳の操作を `lib-ledger-issue.sh` に置き換える
- `.github/scripts/tests/test-record-mutation-metrics.sh`: 上の変更に合わせたテストにする
- `.github/workflows/mutation-report.yaml`: 全件か差分かのステップに `id` と出力を付け、job の outputs で record に渡す。record job に `actions: read` を足し、全件の回だけ `collect-coverage.sh` を動かす。record の前に新しいテストを流す
- `.github/workflows/ci.yaml`: `frontend-test-results` と `backend-check-results` の `retention-days` を `${{ github.event_name == 'push' && 90 || 7 }}` にする
- `.github/scripts/check-audit-scan-freshness.sh`: 3つ目の引数(表示名。省略時は今の「定期スキャン」)を足す
- `.github/scripts/tests/test-check-audit-scan-freshness.sh`: 表示名の引数のテストを足す
- `.github/workflows/audit-weekly.yaml`: `run_check inventory-freshness "棚卸しの稼働確認" ... audit-inventory.yaml 35 棚卸し` を足す。ヘッダの「4項目」を直す
- `.github/dependabot.yml`: pip のレーン(`/docker/terraform`)を足す。docker レーンの group に `exclude-patterns: ["terraform-linters/tflint"]` を足す。コメントを直す
- `docker/terraform/Dockerfile`: 先頭に `FROM ghcr.io/terraform-linters/tflint:v0.60.0@sha256:<digest> AS tflint` のステージを置き(digest は実装時に ghcr.io から取る)、`COPY --from=tflint` にする。checkov は、`requirements.txt` を COPY して `pip3 install -r` で入れる
- `.github/workflows/dependabot-auto-merge.yaml`: 予約の前に `check-release-age.sh` を呼ぶ。1日1回の `schedule` と `workflow_dispatch` で、予約を保留した tflint の更新PRを見直す job を足す
- `doc/開発フロー/監査手順.md`: 定期作業の表の月次・半期の行と版の確認先を、届いたコメントを読む形にする。PRが止まったときの節に、tflint の更新PRに「自動マージを予約していない」のコメントが付いたときの対処を足す
- `doc/インフラ設計/Github Actions設計/ワークフロー設計.md`: 2.1 の一覧に棚卸しと tflint の公開から72時間の判定を足し、2.2 に「1日1回の見直しが止まると、保留した tflint の更新PRが開いたまま残る」残余リスクを足す
- `README.md`: ワークフロー一覧の表と Mermaid の図に `audit-inventory.yaml` を足し、週次監査の項目数と `dependabot-auto-merge.yaml` の起動条件(1日1回の見直し)を直す
- `.kiro/specs/audit-automation/requirements.md`、`.kiro/specs/audit-notification/requirements.md`: 外部問い合わせの要件に、この spec で棚卸しに限って改めた旨の注記を足す
- `.kiro/steering/tech.md`: 「checkov 等は Dockerfile で固定し人間が明示的に上げる」を、Dependabot のPRで上げる形に直す(`/kiro-steering` で行う)

## 処理の流れ

### 棚卸し(毎月2日)

```mermaid
sequenceDiagram
    participant WF as audit-inventory.yaml
    participant S as collect-inventory.sh
    participant R as リポジトリのファイル
    participant X as 外部の取得元
    participant I as 棚卸し台帳のIssue
    WF->>WF: 自己テスト(失敗なら赤で終了)
    WF->>S: 実行
    S->>R: 対象ごとに宣言を読む
    loop 対象ごと
        S->>X: 最新版・使っている系列・最新の系列
        X-->>S: 値 または 失敗(欄を「取得できず」に)
    end
    S->>S: 表と振り返りのIssueの件数を組み立てる
    S->>I: 探す(無ければ作る)・コメント(@所有者)・担当者の割り当て
    alt 書けた
        S-->>WF: 0(成功)
    else 書けなかった
        S-->>WF: 2(赤)
    end
```

- 欄が「取得できず」でも、スクリプトは実行を成功で終える(要件2-8)。実行が赤になるのは、自己テストの失敗と、台帳に書けなかったときだけである
- 実行が赤で終わっても、所有者には通知されない(定期実行の失敗通知は bot に届く)。35日以内に成功が無ければ、週次監査が逸脱として届ける(要件5-1)

### メトリクス(毎週土曜。コメントは全件の回だけ)

```mermaid
flowchart TD
    A[frontend-mutation: 全件か差分かを決める] -->|outputs.mode| C[record-metrics]
    B[backend-mutation] --> C
    C --> D{mode は全件か}
    D -->|差分| E[新しい表に1行追記。コメントしない]
    D -->|全件| F[collect-coverage.sh で main の直近の成果物と基準値を読む]
    F --> G[新しい表に1行追記]
    G --> H[直前の全件の行と差を計算]
    H --> I[コメント: 今回・前回・差・カバレッジ + @所有者 + 担当者]
```

- `mode` は、`full-scheduled`(月初の定期)、`full-manual`(手動で full)、`full-no-previous`(前回の結果が無い)、`incremental` の4値である。全件の3値はどれもコメントの対象であり、record-mutation-metrics.sh は全件になった理由をコメントに書く

### tflint の更新PRの自動マージ(PR のイベントと1日1回の見直し)

```mermaid
flowchart TD
    A[Dependabot のPR: opened / reopened / synchronize] --> J[check-release-age.sh]
    S[1日1回: 予約されていない Dependabot のPRを列挙] --> J
    J --> K{判定}
    K -->|reserve: tflint の更新ではない、または公開から72時間経った| R[gh pr merge --auto --squash]
    K -->|wait: 公開から72時間経っていない| W[何もしない。翌日の見直しを待つ]
    K -->|notify: 公開日時を取れない、または中身だけの更新| N[理由をPRにコメントし @所有者。同じ理由のコメントは1回だけ]
    N -->|公開日時を取れない場合だけ| W
```

- 1日1回の見直しは、中身(digest)だけの更新を、以後の見直しの対象から外す(要件4-7 の除外)。公開日時を一時的に取れなかった場合は、見直しは翌日もそのPRを見直す(R3-3-1)

## 部品

この設計の部品は、次の表のとおりである。

| 部品 | 種類 | 役割 | 対応する要件 | 主に使う部品 | 呼び出し方の種類 |
|---|---|---|---|---|---|
| audit-inventory.yaml | ワークフロー | 月1回の棚卸しの起動 | 1.1, 2.7, 5.2, 6.3 | collect-inventory.sh (P0) | 一括処理 |
| inventory-targets.json | 設定 | 対象の一覧 | 1.1, 1.2, 1.5 | - | 状態 |
| collect-inventory.sh | スクリプト | 集めて表にし、台帳にコメント | 1.x, 2.x, 5.3, 6.1 | lib-ledger-issue.sh (P0), 外部の取得元 (P1) | 一括処理 |
| lib-ledger-issue.sh | スクリプトの関数群 | 台帳のIssueの操作 | 2.2-2.4, 3.3, 6.4 | GitHub API (P0) | サービス |
| collect-coverage.sh | スクリプト | カバレッジと基準値の Markdown | 3.4, 3.6, 3.8 | GitHub artifacts API (P0) | 一括処理 |
| record-mutation-metrics.sh | スクリプト | 測定方式の記録・差・コメント | 3.1-3.3, 3.5-3.8 | lib-ledger-issue.sh (P0) | 一括処理 |
| mutation-report.yaml | ワークフロー | mode の受け渡し・カバレッジの読み取りの起動 | 3.1, 3.4, 3.7 | record-mutation-metrics.sh (P0) | 一括処理 |
| ci.yaml | ワークフロー | 成果物の保持 | 3.9 | - | - |
| check-audit-scan-freshness.sh / audit-weekly.yaml | スクリプト / ワークフロー | 棚卸しの鮮度確認 | 5.1, 5.4 | - | 一括処理 |
| Dockerfile / requirements.txt / dependabot.yml | 設定 | Dependabot への移管 | 4.1-4.5 | Dependabot (P0) | - |
| check-release-age.sh / dependabot-auto-merge.yaml | スクリプト / ワークフロー | tflint の更新PRの予約を公開から72時間保留する | 4.6-4.9 | GitHub API (P0) | 一括処理 |
| 文書類 | 文書 | 手順書・一覧・注記 | 6.6, 7.x | - | - |

### audit-inventory.yaml(毎月2日に棚卸しを1回実行するワークフロー)

対応する要件: 1.1, 2.7, 5.2, 6.3

**役割**: このワークフローは、毎月2日に棚卸しを1回実行する。このワークフローは、AIのアクションを使わない(要件6-2)。

**権限**: このワークフローの権限は `permissions: contents: read, issues: write` である。このワークフローには、それ以外の権限を付けない(要件6-3)。

**いつ動くか**:
- 起動: `on: schedule: cron '17 0 2 * *'`(毎月2日 09:17 JST。1日のカナリア生成と4日のカナリア照合を避ける)と `workflow_dispatch`。毎月2日の cron、または手動で動く
- 同時実行と時間の上限: `concurrency: group: audit-inventory, cancel-in-progress: false`、`timeout-minutes: 15`

**呼び出し方(一括処理)**:
- 手順: このワークフローは、checkout(既存と同じ SHA 固定の参照)のあと、自己テスト(`test-lib-ledger-issue.sh` と `test-collect-inventory.sh`)を流す。自己テストが失敗したら、このワークフローは赤で終了する。自己テストが通ったら、このワークフローは `bash .github/scripts/collect-inventory.sh .github/audit/inventory-targets.json`(`GH_TOKEN: ${{ github.token }}`)を実行する
- 出力: 棚卸し台帳のIssueへのコメント1件
- 何度実行しても同じか: 同じ月に再実行すると、コメントがもう1件増える。この設計は、増えたコメントを新しい事実として扱い、重複の除去はしない

### inventory-targets.json(棚卸しの対象の一覧を持つ設定ファイル)

対応する要件: 1.1, 1.2, 1.5

**役割**: この設定ファイルは、対象・宣言の場所・取得元・系列の取り出し方を1か所に書く。

**状態の持ち方**: この設定ファイルの形は、次のとおりである。

```typescript
type InventoryTargets = {
  targets: Target[];
};
type Target = {
  name: string;                       // 表の「対象」列。例 "Node.js"
  declarations: Declaration[];        // 1件以上
  latest: LatestSource;               // 最新のリリースの取得元
  support: SupportSource | null;      // null はサポート期限の公表が無い(要件1-5)
};
type Declaration = {
  files: string[];                    // リポジトリのルートからのパス。1件以上
  pattern: string;                    // jq(Oniguruma)の正規表現。名前付きグループ version を1つ持つ
};
type LatestSource =
  | { type: "github-release"; repo: string }                       // 例 "terraform-linters/tflint"
  | { type: "pypi"; package: string }                              // 例 "checkov"
  | { type: "dockerhub-tags"; repository: string; tag_pattern: string } // 例 "localstack/localstack", "^[0-9]{4}\\.[1-9][0-9]?\\.[0-9]+$"(月の先頭の0を許さず、別名の 2026.08.4 を除く)
  | { type: "endoflife"; product: string };                        // 最新の系列の latest.name を最新のリリースとする
type SupportSource = {
  type: "endoflife";
  product: string;                    // 例 "nodejs"
  cycle_pattern: string;              // version から系列を取り出す正規表現。名前付きグループ cycle を1つ持つ
};
```

**対象の一覧**(宣言の場所は 2026-09-29 の実物に合わせる)

| name | declarations(files) | latest | support.product / 系列の例 |
|---|---|---|---|
| tflint | `docker/terraform/Dockerfile`(`FROM ghcr.io/terraform-linters/tflint:v…`) | github-release `terraform-linters/tflint` | null |
| tflint の AWS 用ルールセット | `terraform/.tflint.hcl`(`plugin "aws"` の `version`) | github-release `terraform-linters/tflint-ruleset-aws` | null |
| checkov | `docker/terraform/requirements.txt` | pypi `checkov` | null |
| Trivy | `.github/workflows/container-scan.yaml`、`container-scan-scheduled.yaml` の `TRIVY_VERSION` | github-release `aquasecurity/trivy` | null |
| Java | `docker/backend/Dockerfile`、`Dockerfile.prod` の `eclipse-temurin:`、`backend/build.gradle` の `JavaLanguageVersion.of(` | endoflife `eclipse-temurin` | eclipse-temurin / `21` |
| Node.js | `docker/frontend/Dockerfile` の `node:`、ワークフローの `node-version:` | endoflife `nodejs` | nodejs / `24` |
| PostgreSQL(開発) | `docker/db/Dockerfile` の `postgres:` | endoflife `postgresql` | postgresql / `17` |
| PostgreSQL(本番) | `terraform/modules/rds/main.tf` の `engine_version` | endoflife `amazon-rds-postgresql` | amazon-rds-postgresql / `17` |
| Redis(開発) | `docker/redis/Dockerfile` の `redis:` | endoflife `redis` | redis / `7.4` |
| Valkey(本番) | `terraform/modules/elasticache/main.tf` の `engine_version` | endoflife `valkey` | valkey / `8.0` |
| Terraform | `docker/terraform/Dockerfile` の `hashicorp/terraform:`、ワークフローの `TF_VERSION` | endoflife `terraform` | terraform / `1.16` |
| Docker(dind) | `docker/dind/Dockerfile` の `docker:` | endoflife `docker-engine` | docker-engine / `27` |
| LocalStack | `docker/localstack/Dockerfile` の `localstack/localstack:` | dockerhub-tags `localstack/localstack` | null |

- ワークフローの `node-version` は `ci.yaml`・`mutation-report.yaml`・`codex-review.yml`・`guardrails.yaml` に、`TF_VERSION` は `terraform-plan.yaml`・`terraform-apply.yaml` にある。宣言が複数あるときは、この設定ファイルは全部を載せる(research.md「版の宣言の場所」)

### collect-inventory.sh(宣言を読み、外部から最新版と期限を集め、表を台帳にコメントするスクリプト)

対応する要件: 1.1-1.7, 2.1-2.8, 5.3, 6.1

**役割**: このスクリプトは、宣言を読み、外部から最新版と期限を集め、表を台帳にコメントする。このスクリプトは、値の良し悪しを判定しない。このスクリプトは、版の食い違い・期限切れを強調する記号も付けず、事実の列として出す。

**使う部品**:
- lib-ledger-issue.sh: このスクリプトは、台帳の操作にこの関数群を使う(P0)
- endoflife.date / PyPI / Docker Hub / GitHub Releases: このスクリプトは、最新版と期限をこれらから取る(P1。失敗は欄に閉じる)

**呼び出し方(一括処理)**:
- 使い方: `collect-inventory.sh <targets.json>`。環境変数 `GH_TOKEN` `GITHUB_REPOSITORY` `GITHUB_REPOSITORY_OWNER` `GITHUB_SERVER_URL` `GITHUB_RUN_ID`(必須)、`ENDOFLIFE_BASE` `PYPI_BASE` `DOCKERHUB_BASE`(任意。テスト用の差し替え。既定は公開のURL)
- 起動: audit-inventory.yaml がこのスクリプトを実行する
- 入力の検証: `targets` が配列で、各要素が `name` `declarations` `latest` `support` を持つこと。違反は exit 2
- 出力先: 棚卸し台帳のIssue へのコメント1件
- 終了コード: **0 = 台帳にコメントを書けた / 2 = 書けなかった(引数・環境変数の不足、設定ファイルの形式違反、Issue の操作の失敗)**。このスクリプトは、1 を使わない(判定をしないため。要件1-7)
- 宣言の読み取り: このスクリプトは、各 `files` を読み、`pattern` の `version` を全て取り出す。ファイルが無い・一致が0件なら、このスクリプトはその場所を「読み取れず」とする(要件2-6)
- 外部への問い合わせ: このスクリプトは、`curl -sS --max-time 20` で問い合わせ、認証ヘッダを付けない(要件6-1)。GitHub のリリースだけは、このスクリプトは `gh api repos/{repo}/releases/latest` を使う。応答が200以外・JSON として読めない・期待のキーが無いときは、このスクリプトはその欄を「取得できず」とし、理由(HTTP の状態コードや「形式が想定と違う」)を表の下に書く(要件2-5)
- endoflife.date: このスクリプトは、使っている系列を `GET {ENDOFLIFE_BASE}/products/{product}/releases/{cycle}` で、最新の系列を `GET {ENDOFLIFE_BASE}/products/{product}/releases/latest` で取る。このスクリプトは、宣言の版から `cycle_pattern` で系列を作る。版が複数あり系列が複数できたときは、このスクリプトは系列ごとに問い合わせる
- Docker Hub: このスクリプトは、`GET {DOCKERHUB_BASE}/namespaces/{ns}/repositories/{repo}/tags?page_size=100&ordering=last_updated` の `results[].name` から `tag_pattern` に一致するものを取り、版として最大のものを最新とする(`sort -V`)
- 振り返りのIssue: `gh api repos/{repo}/labels/retrospective` が404なら、このスクリプトはラベルなし・0件とする。ラベルがあれば、このスクリプトは `gh api --paginate "repos/{repo}/issues?labels=retrospective&state=all&per_page=100"` から PR を除いて、全件と未完了の件数を数える
- 何度実行しても同じか: このスクリプトの問い合わせは読み取りだけであり、再実行してよい

**表の形**(要件2-1)

```
| 対象 | 使っている版(書いてある場所) | 最新のリリース | 使っている系列のサポート期限 | 期限切れ | 最新の系列 |
|---|---|---|---|---|---|
| Node.js | 24.21.0(docker/frontend/Dockerfile:1)<br>24.16.0(.github/workflows/ci.yaml:160 ほか3か所) | 26.x.y | 24: 2028-04-30 | 24: いいえ | 26(LTS ではない) |
| Terraform | 1.16.4(docker/terraform/Dockerfile:1)<br>1.9.0(.github/workflows/terraform-plan.yaml:14 ほか1か所) | 1.16.4 | 1.16: 未定<br>1.9: … | … | 1.16 |
| tflint | v0.60.0(docker/terraform/Dockerfile:1) | v0.64.0 | 公表なし | 公表なし | 公表なし |
```

- `support: null` の対象では、このスクリプトは、期限・期限切れ・最新の系列の3列を「公表なし」とする(R1-2-3)
- endoflife.date の `eolFrom` が null のときは、このスクリプトは「未定」と書く。このスクリプトは、`isEol` の真偽を「はい」「いいえ」で書く。`isLts` が false の最新の系列には、このスクリプトは「(LTS ではない)」を添える
- 表の下: 取得できなかった欄の理由の一覧、`振り返りのIssue: 全N件(未完了M件)`、ラベルが無ければ `振り返りのIssue: 0件(retrospective ラベルが存在しない)`、実行へのリンク

### lib-ledger-issue.sh(台帳のIssueを探す・作る・コメントする・担当者に割り当てる共通の関数群)

対応する要件: 2.2, 2.3, 2.4, 3.3, 6.4

**役割**: この関数群は、台帳のIssueを探し、作り、コメントし、担当者に所有者を割り当てる。

**呼び出し方(サービス)**: 関数の形は、次のとおりである。

```bash
# source .github/scripts/lib-ledger-issue.sh
# 必須の環境変数: GH_TOKEN GITHUB_REPOSITORY GITHUB_REPOSITORY_OWNER

# タイトルが完全一致する台帳のIssue(PRを除く、state=all、最小の番号)を探し、番号を標準出力に出す。
# 無ければ本文ファイルとラベル(空なら付けない)で作成する。失敗は戻り値 1。
ledger_find_or_create <title> <initial_body_file> <label>

# 本文の先頭行に "@<owner> " を付けてコメントし、担当者に所有者を割り当てる。
# コメントの失敗は戻り値 1。担当者の割り当ての失敗は ::warning:: を出して戻り値 0(audit-issue.sh と同じ扱い)。
ledger_comment <issue_number> <body_file>

# 本文の末尾にテキストを追記する(通知は出ない)。失敗は戻り値 1。
ledger_append_body <issue_number> <text_file>
```

- 呼ぶ前に成り立つ条件: `gh` が使え、`issues: write` があること
- 常に成り立たせる条件: この関数群は、決まったタイトルと完全一致するIssueだけを操作する(要件6-4)。ラベルを付けるときは、この関数群は、ラベルが無ければ `gh label create ... || true` で作る
- 台帳のタイトルとラベル: 棚卸しの台帳は、タイトル `棚卸し台帳: 版とサポート期限`、ラベル `audit` である。mutation の台帳は、既存のタイトル `メトリクス台帳: mutationスコア` のままにし、ラベルを付けない(既存の台帳を変えない)

### collect-coverage.sh(カバレッジと基準値を読み、Markdown を出すスクリプト)

対応する要件: 3.4, 3.6, 3.8

**役割**: このスクリプトは、main で最後にテストを実行した CI の成果物からカバレッジを、ゲート設定から基準値を読み、Markdown を出す。

**呼び出し方(一括処理)**:
- 使い方: `collect-coverage.sh <出力ファイル>`。環境変数 `GH_TOKEN` `GITHUB_REPOSITORY`(必須)
- 成果物の探し方: このスクリプトは、`gh api --paginate "repos/{repo}/actions/artifacts?name={name}&per_page=100"` から、期限切れでなく `workflow_run.head_branch == "main"` のものを `created_at` の新しい順に取り、先頭を使う(mutation-report.yaml:64-66 と同じ方法)。このスクリプトは、`gh run download <run_id> -n <name>` で成果物を取得する
- frontend: このスクリプトは、`frontend-test-results` の `coverage/coverage-summary.json` の `total.{lines,statements,functions,branches}.pct` を読む
- backend: このスクリプトは、`backend-check-results` の `reports/jacoco/test/jacocoTestReport.xml`(成果物の根は2つのパス `backend/build/reports/**` と `backend/build/test-results/**` の共通の親 `backend/build/` になるため)の末尾にある `<counter type="LINE|BRANCH|INSTRUCTION" missed=".." covered=".."/>`(レポート全体の値)を読む。このスクリプトは、covered / (missed + covered) を小数第1位で出す
- 基準値: このスクリプトは、`frontend/vite.config.ts` の `thresholds` の中の `statements` `branches` `functions` `lines` と、`backend/gradle/quality.gradle` の `counter = '…'` と直後の `minimum = …` を読む。読めなければ、このスクリプトは「読み取れず」とする
- 並べる種別: このスクリプトは、並べる種別を、基準値を定めている種別に揃える(frontend 4種、backend 3種)(R2-1-1)
- 成果物が見つからないとき: 90日以内に main で該当の job が動いていないときは、このスクリプトは「取得できず(90日以内に main でテストを実行したCIが無い)」とする(要件3-6)
- 成果物の中にカバレッジのファイルが無いとき: 成果物はあるが中にカバレッジのファイルが無い(main でテストが途中で失敗した実行)ときは、このスクリプトは「取得できず(成果物にカバレッジのファイルが無い)」とし、それより古い成果物を探さない(D1-2-1)
- 添える情報: このスクリプトは、各値に、その成果物を作った実行の日付(`created_at`)、コミット(`workflow_run.head_sha` の先頭7文字)、実行へのリンクを添える
- 終了コード: 0 = Markdown を書けた(欄が取得できずでも 0) / 2 = 出力ファイルに書けなかった・引数不足。このスクリプトは、判定をしない(要件3-8)

### record-mutation-metrics.sh(測定方式を記録し、全件の回どうしの差とカバレッジをコメントで届けるスクリプト。既存のスクリプトを変える)

対応する要件: 3.1, 3.2, 3.3, 3.5, 3.6, 3.7, 3.8

**役割**: このスクリプトは、測定方式を記録し、全件の回どうしの差とカバレッジをコメントで届ける。

**呼び出し方(一括処理)**:
- 新しい環境変数: `MUTATION_MODE`(`full-scheduled` / `full-manual` / `full-no-previous` / `incremental`。必須。それ以外は exit 2)、`COVERAGE_FILE`(任意。全件の回に collect-coverage.sh の出力を渡す)、`GITHUB_REPOSITORY_OWNER`(必須になる)
- 台帳の新しい表: 見出し `## 記録(測定方式つき)` の下に `| 実行日(UTC) | 測定方式 | backend(PIT) | frontend(Stryker) | 実行 |` を置く。本文にこの見出しが無ければ、このスクリプトは見出しと表の頭を末尾に足してから行を足す。このスクリプトは、既存の表を変えない
- 測定方式の列の値: `全件(月初の定期)` `全件(手動)` `全件(前回の結果なし)` `差分`
- 全件の回: このスクリプトは、新しい表の中で、今回より前の最後の全件の行を探し、backend と frontend のそれぞれで差(ポイント、小数第1位、符号つき)を出す。前の行が無い・その欄が「取得できず」なら、このスクリプトは「比較対象なし」とする(要件3-5)
- 全件の回のコメント: このスクリプトは、`今回 / 前回の全件(日付) / 差` の表、全件になった理由、`COVERAGE_FILE` の中身(無ければ「取得できず」)、実行へのリンクを、`ledger_comment` で送る
- 差分の回: このスクリプトは、行の追記だけを行い、コメントしない(要件3-7)
- 終了コード: 0 / 2 は今と同じである。このスクリプトは、コメントの失敗も 2 にする

### mutation-report.yaml(測定方式を受け渡し、カバレッジの読み取りを起動するワークフロー。既存のワークフローを変える)

対応する要件: 3.1, 3.4, 3.7

**役割**: このワークフローは、全件か差分かの測定方式を記録の job に渡し、全件の回だけカバレッジの読み取りを起動する。

**変える点**:
- 「Download previous Stryker report」: この設計は、このステップに `id: mode` を付け、`mode=full-scheduled|full-manual|full-no-previous|incremental` を `$GITHUB_OUTPUT` に書かせる。`full-no-previous` は、前回の run が見つからない・取得に失敗した分岐である
- frontend-mutation: この設計は、`outputs: mode: ${{ steps.mode.outputs.mode }}` を足す
- record-metrics: この設計は、`permissions` に `actions: read` を足す。この設計は、`env: MUTATION_MODE: ${{ needs.frontend-mutation.outputs.mode || 'full-no-previous' }}` を置く(frontend の job が途中で失敗し出力が無いときも全件として扱う。backend は毎回全件のため)
- record の前: このワークフローは、`test-lib-ledger-issue.sh` と `test-collect-coverage.sh` を流す。`MUTATION_MODE` が全件のときだけ、このワークフローは `collect-coverage.sh "${RUNNER_TEMP}/coverage.md"` を動かし、`COVERAGE_FILE` で渡す。collect-coverage.sh が失敗しても、このワークフローは記録とコメントを止めず、コメントのカバレッジの欄を「取得できず」にする(D1-1-5)

### check-release-age.sh と dependabot-auto-merge.yaml(tflint の更新PRの自動マージの予約を保留するスクリプトとワークフロー)

対応する要件: 4.6, 4.7, 4.8, 4.9

**役割**: このスクリプトとワークフローは、tflint の更新PRの自動マージの予約を、GitHub のリリースの公開から72時間経つまで保留する。

**権限**: `recheck` job の `permissions` は、既存と同じ(`contents: write`, `pull-requests: write`)である。トークンは、既存と同じ `BOT_GITHUB_TOKEN` を使う。

**いつ動くか**:
- 既存の `auto-merge` job: PR の opened / reopened / synchronize
- 新しい `recheck` job: `on: schedule: cron '37 1 * * *'`(毎日 10:37 JST)と `workflow_dispatch`

**check-release-age.sh の呼び出し方**:
- 使い方: `check-release-age.sh <PR番号>`。環境変数 `GH_TOKEN` `GITHUB_REPOSITORY` `GITHUB_REPOSITORY_OWNER`(必須)、`NOW_EPOCH`(任意。テスト用の時刻固定)
- 判定の結果: このスクリプトは、判定の結果を、標準出力の1行 `decision=reserve|wait|notify` と `reason=<理由>` で返す。終了コードは、0 = 判定できた / 2 = PR の差分を取れない等で判定できなかった、である
- 対象の表(スクリプトの定数): イメージ `ghcr.io/terraform-linters/tflint` ⇔ GitHub のリポジトリ `terraform-linters/tflint`。Docker Hub 以外の置き場から入れるイメージが増えたら、この表に足す
- 差分の読み取り: このスクリプトは、PR の差分(`gh api repos/{repo}/pulls/{n}/files` の `patch`)から、対象のイメージの `FROM` 行の削除と追加を探し、前後のタグと digest を取り出す
  - 対象のイメージの行が差分に無い: `reserve`(tflint の更新ではない。今までどおり予約する)
  - タグが変わった: このスクリプトは、`gh api repos/terraform-linters/tflint/releases/tags/{新しいタグ}` の `published_at` を読む。今の時刻との差が72時間以上なら `reserve`、未満なら `wait`。取得できない(404・500・形式違反)なら `notify`(理由「公開日時を取れない」)
  - タグが同じで digest だけが変わった: `notify`(理由「中身だけの更新」)
- 公開日時: このスクリプトは、公開日時に GitHub のリリースの `published_at` だけを使う。このスクリプトは、イメージの中の作成日時(image config の `created`)や置き場の更新日時を読まない(要件4-9)
- `notify` のとき: このスクリプトが PR にコメントする。このスクリプトは、コメントの先頭行に `@<owner>`、本文に理由と次の対処、末尾に `<!-- release-age: <reason> -->` の目印を付ける。同じ目印のコメントが既にあれば、このスクリプトはコメントを重ねない(R3-1-3)

**dependabot-auto-merge.yaml の変える点**:
- 既存の `auto-merge` job: この job は、checkout してから `check-release-age.sh` を呼び、`reserve` のときだけ今までどおり `gh pr merge --auto --squash` を実行する。`wait` と `notify` のときは、この job は予約せずに成功で終える。スクリプトが exit 2 のときは、この job は予約せずに失敗で終える(安全側)
- 新しい `recheck` job: この job は、Dependabot が作った open のPRのうち、自動マージが予約されていないもの(`gh pr list --author app/dependabot --json number,autoMergeRequest`)ごとに `check-release-age.sh` を呼び、`reserve` なら予約する。理由が「中身だけの更新」のPRは、目印のコメントがあれば、この job はスクリプトを呼ばずに飛ばす(要件4-7 の除外)。理由が「公開日時を取れない」のPRは、この job は翌日も見直す(R3-3-1)
- checkout: PR のコードを実行しないよう、このワークフローは base(main)のスクリプトを使う(`pull_request` のイベントでも `ref: ${{ github.event.pull_request.base.sha }}` を明示する)

**呼び出し方(一括処理)**:
- 起動: Dependabot のPRのイベント、毎日1回、手動
- 出力: 自動マージの予約、または PR へのコメント
- 何度実行しても同じか: 予約は冪等である。冪等とは、同じPRに何度予約しても結果が変わらないことを指す。コメントは、目印で重複を防ぐ

### ci.yaml(CI の成果物の保存期間を変えるワークフロー。既存のワークフローを変える)

対応する要件: 3.9

**変える点**: この設計は、`frontend-test-results` と `backend-check-results` の `retention-days: 7` を `retention-days: ${{ github.event_name == 'push' && 90 || 7 }}` にする。PR の成果物は7日のままである(要件3-9)。

### check-audit-scan-freshness.sh と audit-weekly.yaml(棚卸しの鮮度を確かめるスクリプトとワークフロー。既存のものを変える)

対応する要件: 5.1, 5.4

**変える点**:
- check-audit-scan-freshness.sh: この設計は、このスクリプトの使い方を `check-audit-scan-freshness.sh <workflow_file> <threshold_days> [表示名]` にする。表示名を省略すると、このスクリプトは今の「定期スキャン」を使う。このスクリプトは、報告の見出しと本文の「定期スキャン」を表示名に置き換える。この設計は、既存の呼び出し(`container-scan-scheduled.yaml 8`)を変えない
- audit-weekly.yaml: この設計は、Judge に次を足す。
  ```
  run_check inventory-freshness "棚卸しの稼働確認" \
    .github/scripts/check-audit-scan-freshness.sh audit-inventory.yaml 35 棚卸し
  ```
- 35日は、「月1回の実行が1回欠けた」を意味する(週1回の定期スキャンの8日と同じ考え方)
- 既存の鮮度確認は、成功0件を逸脱にし、未登録を判定不能にする。そのため、この設計は、**マージ後、最初の月曜より前に `audit-inventory.yaml` を手動で1回実行する**ことを、tasks の最後の確認に置く。手順書には書かない

### docker/terraform/Dockerfile・requirements.txt・dependabot.yml(tflint と checkov を Dependabot に移す設定)

対応する要件: 4.1, 4.2, 4.3, 4.4, 4.5

**変える点**:

```dockerfile
FROM ghcr.io/terraform-linters/tflint:v0.60.0@sha256:<digest> AS tflint

FROM hashicorp/terraform:1.16.4@sha256:985c...

COPY --from=tflint /usr/local/bin/tflint /usr/local/bin/tflint
COPY docker/terraform/requirements.txt /tmp/requirements.txt
RUN apk add --no-cache python3 py3-pip git \
    && pip3 install --no-cache-dir --break-system-packages -r /tmp/requirements.txt
```

- `docker/terraform/requirements.txt` は、`checkov==3.2.497` の1行である(今の版のまま。上げるのは #408)
- この設計は、版の固定の理由のコメント(新しいルールで全PRが赤になる)を残し、そのコメントを「更新は Dependabot のPRで届き、terraform-static が新しい指摘を赤で示す」に直す
- dependabot.yml:
  - pip のレーン: `package-ecosystem: "pip"`、`directory: "/docker/terraform"`、毎週月曜 09:00 JST、`commit-message.prefix: "chore"`、メジャー更新の除外(他のレーンと同じ)
  - docker レーンの group `docker-base-images`: `exclude-patterns: ["terraform-linters/tflint"]` を足す
  - コメント: この設計は、コメント「除外した分は監査手順の…で棚卸しする」を「棚卸し(audit-inventory.yaml)が月1回届ける」に直す
- `terraform-plan.yaml` の paths-filter が `docker/terraform/**` を含む(41行)ため、更新PRで terraform の静的検査が走る(要件4-4。変更なし)

## データの形

### 棚卸し台帳のIssue
- タイトル `棚卸し台帳: 版とサポート期限`、ラベル `audit`
- 本文: 作成時に説明を1回だけ書く(「月1回、audit-inventory.yaml がコメントで表を届ける。人が編集しない」)
- コメント: 月1回。先頭行 `@<owner>`、表、表の下の注記

### mutation の台帳のIssue(既存)
- タイトル `メトリクス台帳: mutationスコア`(変えない)
- 本文: 既存の表(4列)はそのまま残す。末尾に `## 記録(測定方式つき)` と5列の表を足し、以後はこちらに追記する
- コメント: 全件の回だけ

## 失敗したときの扱い

### 方針
- 外部の取得元の失敗は、スクリプトが欄に閉じ込める(「取得できず」+理由)。スクリプトは、実行を成功で終える
- スクリプトは、台帳に書けない失敗だけを実行の失敗にする。所有者への通知は、週次監査の鮮度確認(35日)が受け持つ
- 設定ファイルの形式違反と自己テストの失敗も、実行の失敗になる(同じく鮮度確認で届く)

### 失敗の種類と扱い

| 事象 | 扱い | 所有者に見えるもの |
|---|---|---|
| 外部の取得元が200以外・タイムアウト・429 | 欄を「取得できず」、理由を表の下に | その月のコメント |
| 外部の応答の形が想定と違う | 同上(理由「形式が想定と違う」) | その月のコメント |
| 宣言のファイルが無い・正規表現に一致しない | 欄を「読み取れず」、場所を併記 | その月のコメント |
| 台帳のIssueに書けない | exit 2、実行は赤 | 35日後に週次監査の逸脱 |
| 自己テストの失敗 | 実行は赤 | 同上 |
| カバレッジの成果物が90日以内に無い | 欄を「取得できず」+理由 | 全件の回のコメント |
| 担当者の割り当ての失敗 | 警告のみ(メンションで届く) | コメントのメンション |

### 死活の見張り
- 棚卸しの死活: 週次監査の `inventory-freshness`(成功から35日)
- mutation の記録の死活: 既存のとおり、台帳に行が増えないことで見える(この spec では変えない)

## テストの方針

### 単体テスト(`.github/scripts/tests/`、gh と curl を PATH の先頭の偽物で置き換える)
- `test-collect-inventory.sh`
  - 今のリポジトリの `inventory-targets.json` で、全ての対象の宣言から版が1件以上読めること(設定の書き誤りの検出)
  - Node.js と Terraform のように宣言が複数あるとき、全ての場所と値が1行にまとまること
  - endoflife.date の応答で、`eolFrom: null` が「未定」、`isEol: true` が「はい」、`isLts: false` の最新の系列に「(LTS ではない)」が付くこと
  - 外部が 500・404(HTML の本文)・429・不正な JSON を返したとき、その欄だけが「取得できず」になり、他の対象が続き、終了コードが 0 であること
  - `support: null` の対象の3列が「公表なし」になること
  - 宣言のファイルが無いとき「読み取れず」と場所が出ること
  - Docker Hub のタグから `tag_pattern` に一致する最大の版が選ばれ、`2026.08.4` や `-arm64` 付きが除かれること
  - 振り返りのラベルが無いとき「0件(retrospective ラベルが存在しない)」になること
  - コメントの失敗で終了コードが 2 になること。curl の呼び出しに認証ヘッダが無いこと
- `test-lib-ledger-issue.sh`
  - タイトルの完全一致・最小の番号の選択、無いときの作成、ラベルの作成、コメントの先頭行の `@owner`、担当者の割り当ての失敗が警告で済むこと
- `test-collect-coverage.sh`
  - main 以外の成果物・期限切れの成果物を無視し、最新の main の成果物を選ぶこと
  - `coverage-summary.json` と JaCoCo の XML から値を計算すること(レポート全体の counter を使うこと)
  - `vite.config.ts` と `quality.gradle` の今の書き方から基準値を読めること(今の実ファイルで確かめる)
  - 成果物が無いとき「取得できず」と理由が出ること
- `test-record-mutation-metrics.sh`(変更)
  - 新しい見出しが無い本文に見出しと表の頭が足されること。既存の表が変わらないこと
  - 全件の回で直前の全件の行との差が出ること。差分の行は比較に使わないこと
  - 前の全件の行が無いとき「比較対象なし」、差分の回はコメントしないこと
  - `MUTATION_MODE` の不正値で終了コード 2
- `test-check-release-age.sh`
  - tflint 以外の差分(docker の他のイメージ、npm、gradle)は `reserve` になること
  - 版が変わり、リリースの `published_at` が72時間前より新しいと `wait`、72時間ちょうど以上前なら `reserve` になること(境界は時刻を固定して確かめる)
  - 版が同じで digest だけが変わると `notify`(理由: 中身だけの更新)になること
  - リリースの取得が404・500・不正な JSON だと `notify`(理由: 公開日時を取れない)になること
  - 同じ理由のコメントが既にあると、コメントを重ねないこと。コメントの先頭に `@所有者` が付くこと
  - イメージの中の作成日時(image config の `created`)を読まないこと(GitHub のリリース以外に問い合わせない)
- `test-check-audit-scan-freshness.sh`(変更)
  - 表示名を渡すと見出しと本文に使われ、省略すると今の文面のままであること

### 結合テスト(マージ後の確認。tasks の最後に置く)
- `audit-inventory.yaml` を手動で実行し、棚卸し台帳のIssueにコメントが付き、所有者に通知が届くこと
- 次の月曜の週次監査で、棚卸しの稼働確認が逸脱なしになること
- `mutation-report.yaml` を手動で `full` 実行し、新しい表に `全件(手動)` の行が入り、カバレッジを含むコメントが付くこと
- Dependabot の次の実行で、tflint が docker のまとめPRとは別のPRになること(新しい版が出ていれば)。そのPRが公開から72時間経つまで予約されず、経った後の見直しで予約されること。`dependabot-auto-merge.yaml` を手動で実行し、見直しの job がエラー無く終わること。pip のレーンが設定のエラー無く動くこと(Insights の Dependabot のログ)

## 安全

- 外部への問い合わせは GET のみであり、スクリプトが送るのは URL に含まれる製品名・パッケージ名・リポジトリ名だけである。`GH_TOKEN` は `gh` だけが使い、スクリプトは curl には `GH_TOKEN` を渡さない(要件6-1)
- スクリプトは、外部の応答を表の文字列にするだけで、実行しない。スクリプトは、表に入れる前に `|` と改行を取り除く(表の崩れと、コメントへの任意の Markdown の差し込みを防ぐ)
- **tflint の更新には Dependabot の既定のクールダウンが効かない**(ghcr.io は公開日時を取れず、Dependabot が判定を飛ばす。dependabot-core の `docker/README.md` と `update_checker.rb` の `registry_tag_release_date`・`using_dockerhub?` で確認)。代わりに、`check-release-age.sh` が GitHub のリリースの `published_at`(GitHub が付け、公開した側が後から書き換えられない値)で72時間を判定し、自動マージの予約を保留する。イメージの中の作成日時は公開した側が自由に付けられるため、`check-release-age.sh` はその日時を使わない
- 1日1回の見直しが止まると、保留した tflint の更新PRが開いたまま残る。PR のチェックは緑のため、そのPRは週次監査の滞留検知には掛からない。この設計は、見張りを増やさず、このことを残余リスクとして記録する(次の Dependabot の更新でPRが更新されると再び判定される)
- この設計は、開発環境の terraform コンテナに AWS の認証情報を渡さない(#416)。tflint が悪意のある版だった場合も、tflint は CI と開発環境の両方で秘密情報に触れない
- この設計は、ワークフローの `permissions` を最小にする(棚卸し: `contents: read, issues: write`。record-metrics: 既存に `actions: read` を足すだけ)

## 既存の構成

- 週次監査(`audit-weekly.yaml`)は、判定スクリプトを `run_check` で束ね、結果を `audit-issue.sh` で Issue に届ける。週次監査は、外部への問い合わせをしない方針をヘッダに書いている
- mutation の測定(`mutation-report.yaml`)では、測った側が台帳のIssueの本文に1行追記する(#334 の決定。監査の側は状態を持たない)
- CI は変更検知で job を飛ばすため、main の直近の成果物が数日〜数週間前のものになることがある

## 要件との対応

| 要件 | 要約 | 部品 | 呼び出し方 | 処理の流れ |
|---|---|---|---|---|
| 1.1 | 12の対象を月1回集める | audit-inventory.yaml, inventory-targets.json, collect-inventory.sh | cron `17 0 2 * *` | 棚卸し |
| 1.2 | 使っている版をファイルから読む | collect-inventory.sh, inventory-targets.json | `declarations[]` | 棚卸し |
| 1.3 | 最新のリリース(系列を問わない) | collect-inventory.sh | `latest` の取得元 | 棚卸し |
| 1.4 | 使っている系列の期限・期限切れ・最新の系列 | collect-inventory.sh | `support`(endoflife.date) | 棚卸し |
| 1.5 | 期限の公表が無ければ「公表なし」 | collect-inventory.sh | `support: null` | 棚卸し |
| 1.6 | 振り返りのIssueの件数 | collect-inventory.sh | GitHub の labels / issues API | 棚卸し |
| 1.7 | 判定しない | collect-inventory.sh | 終了コードの契約 | 棚卸し |
| 2.1 | 表と振り返りの件数 | collect-inventory.sh | 表の列の定義 | 棚卸し |
| 2.2 | 台帳にコメント | lib-ledger-issue.sh | `ledger_comment` | 棚卸し |
| 2.3 | メンションと担当者 | lib-ledger-issue.sh | `ledger_comment`, `ledger_assign_owner` | 棚卸し |
| 2.4 | 台帳が無ければ作る | lib-ledger-issue.sh | `ledger_find_or_create` | 棚卸し |
| 2.5 | 取得できなければ「取得できず」+理由 | collect-inventory.sh | 取得元ごとの失敗の扱い | 棚卸し |
| 2.6 | 宣言が読めなければ「読み取れず」+場所 | collect-inventory.sh | `declarations[]` | 棚卸し |
| 2.7 | 書けなければ失敗 | collect-inventory.sh, audit-inventory.yaml | 終了コード 2 | 棚卸し |
| 2.8 | 書ければ成功 | collect-inventory.sh | 終了コード 0 | 棚卸し |
| 3.1 | 測定方式を行ごとに記録 | mutation-report.yaml, record-mutation-metrics.sh | `MUTATION_MODE` | メトリクス |
| 3.2 | 直前の全件の回との差 | record-mutation-metrics.sh | 新しい表の解析 | メトリクス |
| 3.3 | 全件の回にコメントとメンション | record-mutation-metrics.sh, lib-ledger-issue.sh | `ledger_comment` | メトリクス |
| 3.4 | カバレッジの値・日付・コミット・基準値 | collect-coverage.sh | 出力の Markdown | メトリクス |
| 3.5 | 比較対象なし | record-mutation-metrics.sh | 新しい表の解析 | メトリクス |
| 3.6 | 取得できず(保存期間内に CI が無い場合を含む) | collect-coverage.sh, record-mutation-metrics.sh | 欄の値 | メトリクス |
| 3.7 | 差分の回はコメントしない | record-mutation-metrics.sh | `MUTATION_MODE` | メトリクス |
| 3.8 | 判定しない | record-mutation-metrics.sh, collect-coverage.sh | 終了コードの契約 | メトリクス |
| 3.9 | main の成果物を90日保存 | ci.yaml | `retention-days` の式 | - |
| 4.1 | tflint の更新PR | docker/terraform/Dockerfile | `FROM ... AS tflint` | - |
| 4.2 | tflint をまとめPRに入れない | dependabot.yml | `exclude-patterns` | - |
| 4.3 | checkov の更新PR | docker/terraform/requirements.txt, dependabot.yml | pip レーン | - |
| 4.4 | 更新PRで terraform の静的検査 | terraform-plan.yaml(変更なし) | paths-filter `docker/terraform/**` | - |
| 4.5 | 明示的な版と digest で固定 | docker/terraform/Dockerfile, requirements.txt | `vX.Y.Z@sha256:…` / `==X.Y.Z` | - |
| 4.6 | 公開から72時間経っていなければ予約しない | check-release-age.sh, dependabot-auto-merge.yaml | 判定 `wait` | tflint の自動マージ |
| 4.7 | 1日1回見直して予約する | dependabot-auto-merge.yaml | `recheck` job | tflint の自動マージ |
| 4.8 | 公開日時が取れない・中身だけの更新は予約せず知らせる | check-release-age.sh, dependabot-auto-merge.yaml | 判定 `notify` | tflint の自動マージ |
| 4.9 | 書き換えられない公開日時だけを使う | check-release-age.sh | GitHub のリリースの `published_at` | tflint の自動マージ |
| 5.1 | 35日で逸脱 | audit-weekly.yaml, check-audit-scan-freshness.sh | `run_check inventory-freshness` | - |
| 5.2 | 別に実行し、失敗を週次監査が判定不能にしない | audit-inventory.yaml | 実行の成否だけが接点 | 棚卸し |
| 5.3 | 外部の失敗を週次監査の判定不能にしない | collect-inventory.sh | 欄の「取得できず」 | 棚卸し |
| 5.4 | 見張りを新設しない | audit-weekly.yaml | 既存の鮮度確認 | - |
| 6.1 | 外部には製品名だけを送る読み取り | collect-inventory.sh | curl の呼び出し | 棚卸し |
| 6.2 | AIを呼ばない | 全体 | - | - |
| 6.3 | 書き込みは台帳のIssueに限る | audit-inventory.yaml, lib-ledger-issue.sh | `permissions` | 棚卸し |
| 6.4 | 台帳をタイトルで区別する | lib-ledger-issue.sh | `ledger_find_or_create` | 両方 |
| 6.5 | 自動テスト | tests/*.sh | - | - |
| 6.6 | 既存の spec への注記 | audit-automation / audit-notification の requirements.md | - | - |
| 7.1 | 手順書の定期作業の表 | 監査手順.md | - | - |
| 7.2 | 判断は人間、しきい値なし | 監査手順.md | - | - |
| 7.3 | 止まったら週次監査の逸脱で届く | 監査手順.md | - | - |

## 参考にした資料

- 詳しい調査の記録と、却下した案は `research.md` にある
