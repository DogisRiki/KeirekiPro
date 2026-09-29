# design レビュー記録: audit-inventory-metrics

## サイクル1 往復1(2026-09-29)

design.md を requirements.md(承認済み)・Issue #415・research.md・実ファイル(`ci.yaml` `mutation-report.yaml` `audit-weekly.yaml` `terraform-plan.yaml` `dependabot.yml` `dependabot-auto-merge.yaml` `dependency-review.yaml` `CODEOWNERS` `required-checks.json` `record-mutation-metrics.sh` `check-audit-scan-freshness.sh` `audit-issue.sh` `check-dependency-additions.sh` `docker/*/Dockerfile` `terraform/.tflint.hcl` `terraform/modules/{rds,elasticache}/main.tf` `backend/build.gradle` `backend/gradle/quality.gradle` `frontend/vite.config.ts` `compose.yaml` `README.md` `監査手順.md` `ワークフロー設計.md`)に照らして審査した。

前提が実ファイルで成り立つことを確かめた点。

- 要件1〜7の全項目が Requirements Traceability と Components に現れ、実現する要素(ワークフロー・スクリプト・設定・文書)が対応している。ID だけで中身の無い項目は無い
- 対象の一覧(13行)の宣言の場所は 2026-09-29 の実物と一致する。Node.js の `node-version` は `ci.yaml`(160・222)・`mutation-report.yaml`(43)・`codex-review.yml`(99)・`guardrails.yaml`(238)、`TF_VERSION` は `terraform-plan.yaml`(14)・`terraform-apply.yaml`(21)、`TRIVY_VERSION` は `container-scan.yaml`(45)・`container-scan-scheduled.yaml`(65)、AWS ルールセットは `.tflint.hcl`(12)、RDS は `engine_version = "17.4"`、ElastiCache は `valkey` / `8.0`、dind は `docker:27-dind`、LocalStack は `2026.8.4`。系列の取り出し(`17.4` → `17`、`7.4.11` → `7.4`)は research の実測(amazon-rds-postgresql は `17.4` が404)と整合する
- cron `17 0 2 * *` は、カナリア生成(毎月1日 00:00 UTC)・カナリア照合(毎月4日 00:17 UTC)・週次監査(月曜 00:17 UTC)・mutation(土曜 00:00 UTC)のいずれとも重ならない
- `check-audit-scan-freshness.sh` は `runs?status=success&per_page=1` で引き、実行の種類で絞らない(105〜106行)ため、マージ後の手動実行の成功が数えられる。未登録は exit 2、成功0件は exit 1(105〜130行)。設計の「マージ後、最初の月曜より前に手動で1回実行する」は成り立つ
- `audit-weekly.yaml` の `run_check` は追加の引数をそのままスクリプトに渡す(157〜164行)ため、`run_check inventory-freshness ... audit-inventory.yaml 35 棚卸し` の形で3つ目の引数を渡せる。ヘッダの「4項目」(4行)と README(114行)の「4項目」は設計が直す対象に入っている
- `terraform-plan.yaml` の paths-filter は `docker/terraform/**` を含み(41行)、`terraform-static` は `docker/terraform/Dockerfile` をビルドして tflint と checkov を実行する(59〜84行)。要件4-4 はワークフローを変えずに成り立ち、残余リスクの記述「tflint は PR の terraform の静的検査の中で動く」も事実と合う。`terraform-plan` ジョブは必須チェックではない(`required-checks.json` には `terraform-static` と `detect-terraform-changes` だけ)ため、Dependabot の PR で AWS 認証が絡んでも止まらない
- Dependabot の pip レーンが作る PR は、`check-dependency-additions.sh` の対象(`frontend/` の取得元設定と `backend/` の `*.gradle`)に当たらず、`dependency-cooldown` は Dependabot の PR を対象外にし(`dependency-review.yaml` 153〜158行)、`docker/terraform/` は CODEOWNERS の対象外。`dependabot-auto-merge.yaml` は全レーンに予約する。要件4の PR は人手なしでマージされる(requirements の申告1のとおり)
- `audit-issue.sh` は `labels=audit&state=open` で一覧を取ったあと、タイトルの完全一致(`週次監査: 逸脱あり` / `判定不能`)だけを操作する(210〜222行)。棚卸しの台帳に `audit` ラベルを付けても、週次監査の解消処理で閉じられることはない。`audit` ラベルは `audit-issue.sh` が既に作っている(206行)
- `ci.yaml` は `push` を `branches: [main]` に限っている(7〜9行)ため、`retention-days: ${{ github.event_name == 'push' && 90 || 7 }}` は main への push だけを90日にする。frontend の成果物は `frontend/test-results/**` と `frontend/coverage/**` の2パス(197〜199行)で、`test-results/junit.xml` は vitest の reporter が出す(`vite.config.ts` 77行)ため両方が揃い、成果物の根は `frontend/`、中のパスは `coverage/coverage-summary.json` になる。設計の frontend のパスは正しい
- `record-metrics` は既に `issues: write` と `concurrency` を持ち(142〜148行)、`GITHUB_REPOSITORY_OWNER` はランナーの既定の環境変数のため、設計の「必須になる」は追加の設定なしに満たせる
- KeirekiPro Compliance Check は7項目に記載がある。「ゲート設定」だけがチェック無しで「変更を含む」と明記されており、本文(File Structure Plan の `.github/` 配下の一覧)と矛盾しない。「前提機能の利用可否」は日付(2026-09-29)と確かめ方(`gh repo view`、公式ドキュメント、各 API の実測)が書かれ、research.md に個々の応答の記録がある

### 申告

**1. tflint の更新PRを、クールダウン無し・digest 固定無しのまま自動マージに乗せる** — design.md「Config(変更)」「Security Considerations」

- Issue の記載: あり。「tflint: `FROM` で指す書き方に直す。赤くなったときにほかのイメージの更新を巻き込まないよう、まとめPR(group)から外す」。マージの扱いとクールダウンの記載は無い
- 決めたこと: `FROM ghcr.io/terraform-linters/tflint:vX.Y.Z AS tflint` のステージにし、docker のまとめPRから外す。ghcr.io には Dependabot の既定のクールダウン(3日)が効かないことを「受容した残余リスク」に記録する。`docker/terraform/` は CODEOWNERS の対象外で、`dependabot-auto-merge.yaml` が予約するため、terraform-static が緑なら人が見ずに main に入る
- 他にありえた選択肢: tflint の PR だけ所有者の承認を要る形にする(CODEOWNERS に `docker/terraform/` を足す。ゲート設定の変更)。tflint の行を digest 付きにする(Dependabot が digest ごと更新するため、タグの差し替えも PR として現れる)。tflint を Dependabot に任せず棚卸しの表だけで追う
- 外れていた場合: 公開直後の版(取り下げられる版や、配布元の侵害を含む)が、公開から1日以内に開発環境と CI の静的検査のイメージに入る。実行されるのは PR の静的検査の中に限られ、本番のイメージには入らない。所有者は research.md の決定(2026-09-28)でこれを受け入れている

**2. 棚卸しが赤で終わっても、その時点では所有者に届かない** — design.md「System Flows 棚卸し」「Error Handling」

- Issue の記載: あり。「棚卸しが止まったことは、週次監査の既存の確認で見つける。見張りの仕組みを新しく増やさない」。赤になった回の通知の扱いは無い
- 決めたこと: 自己テストの失敗・設定ファイルの形式違反・台帳に書けない失敗は実行を赤にするだけで、Issue への書き込みは行わない。所有者が知るのは、直近の成功から35日たった月曜の週次監査(逸脱あり)で、その報告は「止まっている」という事実だけで原因を含まない
- 他にありえた選択肢: 台帳に書けた範囲で失敗をコメントする(自己テストの失敗のときは台帳の操作ができるため、「今月は集められなかった」を届けられる)。35日を短くする(月次の周期のため下限は31日+実行の遅れ)
- 外れていた場合: 2日に失敗すると、所有者が知るまで最長で5週間かかり、その間の表は届かない。届いた逸脱の Issue から実行ログを開いて原因を見る必要がある。作り直しにはならない(スクリプトに1手順を足すだけ)

**3. mutation の台帳は新しい表を末尾に始め、既存の行を比較に使わない** — design.md「Data Models」「record-mutation-metrics.sh(変更)」

- Issue の記載: あり。「今の台帳は、全件を測り直した回と前回の結果を使った回の区別が記録されず、前月と正しく比べられない」
- 決めたこと: `## 記録(測定方式つき)` の5列の表を末尾に足し、以後はそちらだけに追記する。差の計算は新しい表の全件の行だけを使う。導入後の最初の全件の回は「比較対象なし」
- 他にありえた選択肢: 既存の行の測定方式を実行日から推定して埋める(`mutation-report.yaml` の全件の条件は「schedule かつ UTC の日が7以下」または手動 full で、前者は日付から決まる。手動の回と前回の結果が無かった回は区別できない)。既存の表に列を足して行を書き換える
- 外れていた場合: 最初の比較が1か月遅れるだけで、集め直しにはならない。既存の4列の表は残るため、過去の値は読める

**4. LocalStack の最新版を Docker Hub のタグ一覧から取る** — design.md「inventory-targets.json」「collect-inventory.sh」

- Issue の記載: あり。「最新版とサポート期限は、GitHub のリリース情報、endoflife.date、PyPI から取る」。Docker Hub は無い
- 決めたこと: 4つ目の取得元として Docker Hub の tags API(`hub.docker.com/v2`)を足し、`^[0-9]{4}\.[0-9]{1,2}\.[0-9]+$` に一致するタグの最大を最新とする。research.md によれば GitHub のリリースは v4.14.0 で止まり、Docker のタグ(年.月.連番)と対応しない
- 他にありえた選択肢: GitHub のリリースをそのまま使う(実態と合わない値になる)。LocalStack は最新版を「取得できず」とし、サポート期限と同じく「公表なし」にする
- 外れていた場合: Docker Hub の API やタグの付け方が変わると LocalStack の行だけが「取得できず」になる。他の行には及ばない

**5. 全件を測り直した回は、月初の定期実行以外(手動・前回の結果なし)でもコメントで届ける** — design.md「System Flows メトリクス」「record-mutation-metrics.sh(変更)」

- Issue の記載: あり。「mutation スコアとカバレッジを、月1回、比べられる形で届ける」
- 決めたこと: `full-scheduled` / `full-manual` / `full-no-previous` の3値をどれもコメントの対象にし、理由をコメントに書く。frontend の job が途中で失敗して mode が無いときも `full-no-previous` として扱う(backend は毎回全件のため)
- 他にありえた選択肢: `full-scheduled` だけをコメントの対象にする。手動 full の回はコメントするが、前回の結果が無かった回(成果物の期限切れ)はしない
- 外れていた場合: 月に2回以上コメントが届く月ができる。所有者が「月1回」と思って読むと、直前の全件の行との差が短い期間の差になる(コメントに前回の日付が書かれるため読めば分かる)

**6. 棚卸しの台帳に、週次監査の通知と同じ `audit` ラベルを付ける** — design.md「lib-ledger-issue.sh」「Data Models」

- Issue の記載: なし
- 決めたこと: ラベル `audit`(`audit-issue.sh` が「監査の通知」として作ったもの)を付ける。mutation の台帳は既存のとおりラベル無し
- 他にありえた選択肢: 台帳用のラベル(例 `ledger`)を新しく作る。ラベルを付けない(mutation の台帳と揃える)
- 外れていた場合: `audit` ラベルで通知の Issue を絞ると台帳が混ざる。`audit-issue.sh` はタイトルの完全一致で操作するため誤操作は起きない。付け替えは手作業で済み、作り直しにはならない

### 指摘

| ID | レベル | 該当箇所 | 内容 | 直し方の案 |
|---|---|---|---|---|
| D1-1-1 | 高 | design.md「collect-coverage.sh」backend の成果物の中のパス | `backend-check-results` の中のパスを `jacoco/test/jacocoTestReport.xml` としているが、実物と合わない。`ci.yaml` はこの成果物を `backend/build/reports/**` と `backend/build/test-results/**` の2パスで上げており(284〜286行)、upload-artifact は複数パスのとき「全パスの最も近い共通の親」を成果物の根にする(frontend を `coverage/coverage-summary.json` と書いたのと同じ規則)。backend の根は `backend/build/` になり、中のパスは `reports/jacoco/test/jacocoTestReport.xml` になる。設計のパスで実装すると、backend のカバレッジは毎回「取得できず」になる。テストは設計の形に合わせた偽の成果物で書かれるため、実装中のテストでは見つからず、「取得できず」は設計上の正常な値のためマージ後の確認でも見分けにくい。人はコードを読まないため、実装が終わったあと気づかれずに残る | パスを `reports/jacoco/test/jacocoTestReport.xml` に直す(または成果物の中を `find -name jacocoTestReport.xml` で探す形にする)。`test-collect-coverage.sh` の偽の成果物は `ci.yaml` の2パスと同じ配置(backend は `reports/` と `test-results/`、frontend は `coverage/` と `test-results/`)にし、「今の `ci.yaml` の path の形に合わせる」と Testing Strategy に書く。あわせて「成果物はあるが中にファイルが無い」(main で `./gradlew check` が失敗して report が欠けた等)ときの理由の文言を決める |
| D1-1-2 | 低 | design.md「Testing Strategy」Docker Hub のタグの項 | 「`2026.08.4` … が除かれること」と書いているが、同じ設計の `tag_pattern` の例 `^[0-9]{4}\.[0-9]{1,2}\.[0-9]+$` は月が2桁でも一致するため、`2026.08.4` は除かれない。テストと設定のどちらかが誤っている | 除く例を `-arm64` 付きや `latest` のような形だけにするか、月を1桁に限るなら `tag_pattern` を `[0-9]{1,2}` から `[1-9]|1[0-2]` の形に直す |
| D1-1-3 | 低 | design.md「lib-ledger-issue.sh」Invariants と要件6-3 | 「ラベルが無ければ `gh label create ... || true` で作る」は、要件6-3 の書き込みの範囲(台帳の作成・コメント・担当者の割り当て)に無い書き込み(R1-2-4 で design に委ねられた点)。実際には `audit` ラベルを `audit-issue.sh` が既に作っている(206行)ため作成は起きないが、設計に「既存のラベルを使う」か「6-3 の範囲外だがラベルの作成を含める」かが書かれていない | 「`audit` ラベルは `audit-issue.sh` が作る既存のものを使う。無いときの作成は `audit-issue.sh` と同じ扱い」と Invariants に書く。または要件6-3 の解釈として記録する |
| D1-1-4 | 低 | design.md「collect-coverage.sh」成果物の探し方 | `actions/artifacts?name={name}&per_page=100` の1ページから main の最新を選ぶ。`mutation-report.yaml` の `stryker-report` は週1回しか作られないため1ページで足りるが、`frontend-test-results` / `backend-check-results` は PR の実行のたびに作られる(`if: always()`)。直近100件が PR の成果物で埋まると、main の成果物が期限内に存在しても「取得できず」になる | `gh api --paginate` にするか、`repos/{repo}/actions/workflows/ci.yaml/runs?branch=main&event=push&status=success` から run を先に選び、その run の成果物を取る形にする |
| D1-1-5 | 低 | design.md「mutation-report.yaml」全件のときの `collect-coverage.sh` の起動 | `collect-coverage.sh` が exit 2(出力ファイルに書けない・引数不足)で終わったとき、そのステップが失敗すると後続の記録のステップが動かず、台帳に行が残らない。既存のワークフローは、レポートの取得のステップに `continue-on-error: true` を付けて記録を必ず行う方針(153〜167行)を取っている | `collect-coverage.sh` のステップにも `continue-on-error: true` を付け(または `|| true`)、失敗したら `COVERAGE_FILE` を渡さず「取得できず」で記録を続けると書く |
| D1-1-6 | 低 | design.md「Config(変更)」Dockerfile の例 | `FROM ghcr.io/terraform-linters/tflint:v0.60.0 AS tflint` に digest が無い。今の `COPY --from=` の行も digest 無しのため現状維持だが、`dependabot.yml` の docker レーンは「ベースイメージは digest 固定してあり」(76行)を前提にコメントを書いており、この行だけが例外になる。digest を付ければ Dependabot が digest ごと更新するため、クールダウンが効かない(申告1)ことへの補いにもなる | digest を付けるか、付けない理由(tflint は実行環境の道具でありベースイメージではない等)を Security Considerations に書く |

### 前の段階への指摘

新たな指摘は無い。requirements で「design で決める」とされた点(R1-1-5・R1-1-7・R1-1-8・R1-2-2・R1-2-3・R1-2-4・R1-2-5・R2-1-1・R2-1-3)は、いずれも本文で決められている(宣言の場所の列挙、台帳を分けること、全件の理由の記載、担当者の割り当て、公表なしの3列、ラベル、振り返りの件数の状態、カバレッジの種別、PR の成果物は7日のまま)。

- 往復: 1回目 / 高1 中0 低5

## サイクル1 往復2(2026-09-29)

往復1の処置(D1-1-1 の修正、D1-1-2〜D1-1-6 は記録のみ)を受けた design.md を、実ファイル(`ci.yaml` `backend/gradle/quality.gradle` `frontend/vite.config.ts` `mutation-report.yaml` `terraform-plan.yaml` `compose.yaml` `docker/terraform/Dockerfile` `dependabot.yml`)と research.md に照らして審査した。

D1-1-1 の修正が実物で成り立つことを確かめた点。

- design.md「collect-coverage.sh」の backend の中のパスは `reports/jacoco/test/jacocoTestReport.xml` に直り、根が `backend/build/` になる理由(`backend/build/reports/**` と `backend/build/test-results/**` の共通の親)が併記された。`ci.yaml` 284〜286行の2パスと一致する
- `quality.gradle` 73〜80行で `jacocoTestReport` の XML 出力が有効(`xml.required = true`)で、121〜124行で `check` が `jacocoTestReport` に依存する。既定の出力先は `build/reports/jacoco/test/jacocoTestReport.xml` のため、main で `./gradlew check` が通った run の成果物にはこのファイルが入る
- 基準値の読み取り元も実物と合う。`quality.gradle` 89〜111行は `counter = 'LINE'|'BRANCH'|'INSTRUCTION'` の直後(1行おいて)に `minimum = 0.93|0.73|0.93`、`vite.config.ts` 93〜97行は `thresholds` の中に `statements` `branches` `functions` `lines` の4種。設計の「frontend 4種、backend 3種」と一致する
- 修正は1か所の置き換えで、Requirements Traceability・Error Handling・Testing Strategy の他の記述と食い違いを生んでいない

往復1で確かめていなかった前提を追加で確かめた点。

- Dockerfile の例にある `COPY docker/terraform/requirements.txt /tmp/requirements.txt` は、ビルドコンテキストがリポジトリのルートであることを前提にしている。`compose.yaml`(66〜67行 `context: .`)と `terraform-plan.yaml`(60行 `docker build -f docker/terraform/Dockerfile ... .`)の両方でルートがコンテキストになっており、今の Dockerfile も同じ前提で `COPY terraform/.tflint.hcl` を書いている(16行)。成り立つ
- `dependabot.yml` の docker レーンには group `docker-base-images` がある(100行)。`exclude-patterns` を足す先は実在する
- `mutation-report.yaml` の `record-metrics` は `actions/checkout` を行う(150〜151行)ため、`collect-coverage.sh` が `vite.config.ts` と `quality.gradle` を読める

### 申告

往復1の申告1〜6から変わらない。往復1の修正で新しく決めたことは無い。

### 指摘

| ID | レベル | 該当箇所 | 内容 | 直し方の案 |
|---|---|---|---|---|
| D1-2-1 | 低 | design.md「collect-coverage.sh」成果物の探し方と「Error Handling」の表 | 「取得できず」になる場合として書かれているのは「成果物が見つからない(90日以内に main で該当の job が動いていない)」だけで、成果物はあるが中に対象のファイルが無い場合が決まっていない。この場合は起きうる。`ci.yaml` の両成果物は `if: always()` で上がるため、main でテストが失敗した run(`jacocoTestReport` は `dependsOn test` のため走らず、XML が出ない)の成果物が「最新の main の成果物」として選ばれる。往復1の D1-1-1 の直し方の案に含めた点だが、response では取り上げられていない。要件3-6 の「取得できなかった場合」に当たるため実装は「取得できず」に寄ると見込め、実装の方向を変えない | 「成果物の中にファイルが無いときも『取得できず』とし、理由を『最新の main の成果物(run へのリンク)にカバレッジのファイルが無い』とする」と書き、Error Handling の表に1行足す。あわせて `test-collect-coverage.sh` の偽の成果物を `ci.yaml` の2パスと同じ配置(backend は `reports/` と `test-results/`、frontend は `coverage/` と `test-results/`)にすることを Testing Strategy に書く。tasks で決めてもよい |

### 前の段階への指摘

新たな指摘は無い。

- 往復: 2回で収束 / 未解決: 0件

## サイクル2 往復1(2026-09-29)

requirements の要件4の改訂(4-5 の追記、4-6〜4-9 の追加。サイクル3で収束し承認済み)に合わせて再生成された design.md を、requirements.md・Issue #415・research.md・requirements のサイクル3の記録と response・design-response の「要件の改訂に合わせた再生成」の節・実ファイル(`dependabot-auto-merge.yaml` `dependabot.yml` `update-pr-branches.yaml` `docker/terraform/Dockerfile` `check-audit-dependabot-stuck.sh` `required-checks.json` `pre-merge-check.yaml` `README.md` `監査手順.md` `基盤構築手順.md` `steering/tech.md`)に照らして審査した。サイクル1で確かめた点は再確認の対象にせず、変わった部分(tflint の自動マージの保留、digest 固定、サイクル1の低の指摘の本文への反映)を中心に見た。

前提が実ファイルで成り立つことを確かめた点。

- 要件4-6〜4-9 が Requirements Traceability・Components・System Flows・Testing Strategy に現れ、実現する要素(`check-release-age.sh` と `dependabot-auto-merge.yaml` の `auto-merge` job の変更・`recheck` job の追加)が対応している。Goals・Boundary Commitments(This Spec Owns / Out of Boundary / Revalidation Triggers)・File Structure Plan・Security Considerations も同じ仕組みを指しており、節どうしの食い違いは無い
- `dependabot-auto-merge.yaml` は `pull_request`(opened / reopened / synchronize)で起動し、`pull_request_target` を使わない(18〜26行)。Dependabot 発の `pull_request` では Actions secrets を参照できないが、`BOT_GITHUB_TOKEN` は Dependabot secret としても登録されている(`基盤構築手順.md` 87行 `gh secret set BOT_GITHUB_TOKEN --app dependabot`)ため、`auto-merge` job から `gh api`(PR の差分・tflint のリリース)と PR へのコメントが行える。`recheck` job は `schedule` で起動するため Actions secret 側を使うが、同じ名前が Actions secret にも登録されており(同 71行。`canary.yaml` 40行と `update-pr-branches.yaml` 38行が schedule / push で使っている)、設計の「トークンは既存と同じ `BOT_GITHUB_TOKEN`」は両方の job で成り立つ
- 設計の「checkout は PR のコードを実行しないよう base(main)のスクリプトを使う」は、`pull_request` のままで `ref: ${{ github.event.pull_request.base.sha }}` を明示する形で、既存ヘッダの方針(`pull_request_target` を使わない。25〜26行)と矛盾しない
- 予約を保留した tflint の PR が out-of-date のまま残ることは無い。`update-pr-branches.yaml` は自動マージの有無にかかわらず open の PR 全件を最新化し(46行)、bot の PAT による push は `synchronize` を起こすため、設計の「PR のイベントでも判定する」が main の更新のたびに再び走る。requirements サイクル3 往復3の確認(synchronize でも 4-6 の判定が走り、4-7 と同じ結果になる)と整合する
- 予約されずに開いている tflint の PR は、週次監査の滞留検知に掛からない。`check-audit-dependabot-stuck.sh` は `required-checks.json` に載る context の結論だけを見る(134〜137行・183〜190行)ため、`auto-merge` job が exit 2 で赤になっても(設計「安全側」)滞留とは数えられない。設計の「PR のチェックは緑のため週次監査の滞留検知には掛からない」は正しい
- 設計が「公開日時を一時的に取れなかった場合は、翌日も見直す(R3-3-1)」としている点は、requirements-response の R3-3-1 の処置「design で決める(確かめ直す想定)」と一致する。中身だけの更新を以後の見直しから外す点は要件4-7 の括弧書きのとおり
- 同じ理由のコメントを1回に限る(目印 `<!-- release-age: <reason> -->`)と、手順書に「予約していない」コメントが付いたときの対処を足す点は、requirements-response の R3-1-3 の処置(design と tasks で決める)に対応している
- `dependabot.yml` の docker レーンのコメント「ベースイメージは digest 固定してあり」(76行)と、tflint の `FROM` 行を digest でも固定する設計が揃う。`digest更新はgroupsに入らず、ディレクトリごとの個別PRになる`(85〜87行)ため、`exclude-patterns` で tflint を group から外す設計と、中身だけの更新が個別の PR として現れる前提(要件4-8)が成り立つ
- 監査手順.md 90行「マージを保留したいときは、auto-merge の解除ではなく `pre-merge-check` ラベルを付ける」は、所有者が予約を手で外す運用をしていないことを示す。`recheck` job が予約されていない Dependabot の PR を毎日予約し直しても、所有者の保留の手段(`pre-merge-check` ラベル。`required-checks.json` 18行で approval_gated)と衝突しない
- サイクル1の低の指摘の反映は本文で確認できた。D1-1-2(`tag_pattern` が `^[0-9]{4}\.[1-9][0-9]?\.[0-9]+$` になり、テストの「`2026.08.4` を除く」と揃った)、D1-1-4(`gh api --paginate`)、D1-1-5(collect-coverage.sh が失敗しても記録とコメントを止めない)、D1-2-1(成果物にファイルが無いときの文言と、古い成果物を探さないこと)、D1-1-6(digest 固定。要件4-5 で決まった)
- Compliance Check の7項目は変わらず、「ゲート設定」の未チェックと理由、「前提機能の利用可否」の日付と確かめ方が残っている。新しく使う GitHub の API(他リポジトリのリリースの `published_at`、PR の差分、`gh pr list` の `autoMergeRequest`)はどれも GitHub の REST / GraphQL の公開機能で、Allowed Dependencies の「GitHub REST API」の範囲にある。tflint のリリースが GitHub に存在することは research.md 72行(`releases/latest` の実測)で確かめられている
- `steering/tech.md` 意思決定6(90行「checkov等は無断更新で新ルールが有効になり…」)は、設計の Modified Files で `/kiro-steering` による更新の対象に入っている

### 申告

サイクル1の申告1(tflint をクールダウン無し・digest 固定無しで自動マージに乗せる)は、要件4-5〜4-9 の追加で前提が変わり、もう成り立たない。所有者の判断で「digest 固定+公開から72時間の保留」に置き換わった。申告2〜6はそのまま有効。再生成で新しく決めたことを下に挙げる。

**1. 1日1回の見直しを既存の `dependabot-auto-merge.yaml` の中の `recheck` job にし、対象を「予約されていない Dependabot の open な PR 全部」にする** — design.md「dependabot-auto-merge.yaml の変更」

- Issue の記載: なし(要件4-7 は「予約しなかった tflint の更新PR」だけを対象にしている)
- 決めたこと: `gh pr list --author app/dependabot --json number,autoMergeRequest` で予約の無い PR を全部列挙し、それぞれに `check-release-age.sh` を掛ける。tflint 以外は `reserve` になるため、結果として tflint 以外の PR も毎日予約し直される。見直しは別のワークフローではなく同じファイルの job にする
- 他にありえた選択肢: 見直しの対象を tflint の更新PR(差分に `docker/terraform/Dockerfile` を含む Dependabot の PR)に限る。見直しを別のワークフロー(例 `dependabot-recheck.yaml`)にする
- 外れていた場合: tflint 以外の PR で、開いたときの予約が失敗したまま残っていたものが、翌日に予約される(今は synchronize が起きるまで残る)。所有者が手で予約を外して保留した PR があれば毎日予約し直されるが、手順書は保留に `pre-merge-check` ラベルを使うと定めているため、運用上の衝突は無い。作り直しにはならない

**2. `wait` のときは PR に何も書かず、ワークフローも成功で終える** — design.md「System Flows tflint の更新PRの自動マージ」「dependabot-auto-merge.yaml の変更」

- Issue の記載: なし
- 決めたこと: 公開から72時間経っていない tflint の更新PRには、予約をしないだけで、コメントも赤も残さない。`notify` のときだけコメントする
- 他にありえた選択肢: `wait` のときも「公開日時 X のため Y まで予約しない」を1回コメントする。`wait` を job の失敗(赤)にして PR の画面から分かるようにする(`check-audit-dependabot-stuck.sh` は期待一覧の context だけを見るため、赤にしても滞留にはならない)
- 外れていた場合: 所有者が PR を開いても、予約されていない理由が分からない(auto-merge のボタンが押されていないことしか見えない)。最長で3日+1日で自動的に予約されるため、所有者が手を出す必要は無い。手順書の「予約していないコメントが付いたとき」の節は `wait` の PR には当たらない

**3. 公開日時を取れなかった PR は翌日も見直し、中身だけの更新は目印のコメントで以後の見直しから外す** — design.md「System Flows」「dependabot-auto-merge.yaml の変更」

- Issue の記載: なし(R3-3-1 で design に委ねられた)
- 決めたこと: 「公開日時を取れない」は一時的な失敗として翌日も `check-release-age.sh` を呼ぶ。コメントは同じ目印があれば重ねない。「中身だけの更新」は PR の性質として、目印のコメントがあればスクリプトを呼ばずに飛ばす
- 他にありえた選択肢: どちらも以後の見直しから外し、所有者の手動の予約に任せる(要件4-7 の括弧書きの字面に近い)
- 外れていた場合: リリースの取得が恒久的に失敗する版(リリースを作らずタグだけ打たれた版など)では、毎日 `check-release-age.sh` が呼ばれ続けるが、コメントは1回で止まる。所有者に届く知らせは同じで、作り直しにはならない

**4. PR の差分に対象のイメージの `FROM` 行が無ければ `reserve`(予約する側)に倒す** — design.md「check-release-age.sh」

- Issue の記載: なし
- 決めたこと: 差分に `ghcr.io/terraform-linters/tflint` の行の削除と追加が見つからなければ「tflint の更新ではない」と判定し、今までどおり予約する。判定の対象は Dependabot の全 PR のため、この既定が「tflint 以外は今までどおり」を実現している
- 他にありえた選択肢: 差分に `docker/terraform/Dockerfile` が含まれるのに tflint の行を読み取れないときは `notify`(理由「差分を読み取れない」)にする。`pulls/{n}/files` に加えて PR のタイトル(Dependabot は `Bump terraform-linters/tflint from … to …` の形で書く)でも照合する
- 外れていた場合: 差分の読み取りに誤りがあると(Dependabot の書き方の変化、`patch` の欠落)、tflint の更新PRが「tflint ではない」として直ちに予約され、72時間の待ちが効かないまま気づかれない。単体テストの偽の差分が Dependabot の実際の形と同じである限り起きない

### 指摘

| ID | レベル | 該当箇所 | 内容 | 直し方の案 |
|---|---|---|---|---|
| D2-1-1 | 低 | design.md「Boundary Commitments」Out of Boundary と「dependabot-auto-merge.yaml の変更」 | Out of Boundary は「tflint 以外の Dependabot のPRの自動マージの扱い(今までどおり、開いたときに予約する)」を範囲外としているが、`recheck` job は予約されていない Dependabot の open な PR 全部を毎日列挙して `check-release-age.sh` を呼び、tflint 以外は `reserve` として予約する。tflint 以外の PR も「開いたとき」に加えて「毎日」予約されることになり、境界の記述と本文が合わない。動きとしては害が無い(申告1)が、実装と codex-review が境界の文を基準にすると、`recheck` の対象を tflint に絞るか全部にするかで判断が分かれる | Out of Boundary の文を「tflint 以外の Dependabot のPRの判定(`reserve` のまま。予約の契機に1日1回の見直しが加わる)」のように直すか、`recheck` の列挙を「差分に `docker/terraform/Dockerfile` を含む PR」に絞ると本文に書く |
| D2-1-2 | 低 | design.md「check-release-age.sh」差分の読み取り | 「対象のイメージの行が差分に無い: `reserve`」は、tflint の行が本当に無い場合と、行はあるがタグや digest を読み取れなかった場合(Dependabot の書き方の変化、`FROM` 行の別の書き方)を区別せず、どちらも予約する側に倒す。要件4-6 を守れないのは後者のときで、単体テストは設計と同じ形の偽の差分で書かれるため実装中には見つからず、マージ後の確認も新しい版が出ないと確かめられない。既存の監査のスクリプトは判定できないときに閉じる側(exit 2)に倒しており、設計も exit 2 は「予約せずに失敗」としているため、この1点だけが開ける側になっている | 「差分の変更行に `terraform-linters/tflint` を含む行があるのに、前後のタグと digest を取り出せないときは `notify`(理由「差分を読み取れない」)にする。`reserve` は変更行に対象のイメージが一切現れないときに限る」と書き、Testing Strategy に「対象のイメージを含む読み取れない差分で `notify` になること」を足す |
| D2-1-3 | 低 | design.md「dependabot-auto-merge.yaml の変更」`recheck` job の列挙 | `gh pr list` は件数の上限を省略すると30件で切れる。`dependabot.yml` の `open-pull-requests-limit` は 5+5+5+10 で、脆弱性対応の PR は上限に数えられない(1〜7行)ため、open の Dependabot の PR が30件を超えることがありうる。超えた分は見直しの対象から外れ、tflint の PR がその中にあれば予約されないまま残る | `--limit` を明示する(例 `--limit 100`)か、`gh api --paginate "repos/{repo}/pulls?state=open&per_page=100"` で `check-audit-dependabot-stuck.sh`(143行)と同じ取り方にすると書く |
| D2-1-4 | 低 | design.md「Config(変更)」Dockerfile の例「digest は実装時に ghcr.io から取る」 | どの digest を書くか(マルチアーキテクチャの manifest list の digest か、プラットフォーム別の manifest の digest か)が決まっていない。Dependabot が比較・更新するのは manifest list の digest(今の `hashicorp/terraform:1.16.4@sha256:985c…` と同じ種類)のため、プラットフォーム別の digest を書くと、移管後の最初の Dependabot の実行で「版が同じで digest だけが変わった」PR が作られ、`notify` 経路で所有者にメンションが届く。所有者は中身の差し替えと区別できない | 「digest は manifest list のもの(`docker buildx imagetools inspect ghcr.io/terraform-linters/tflint:v0.60.0` が先頭に出す digest、または `docker manifest inspect` の `Digest`)を書く」と本文に書き、tasks の完了条件に「`docker/terraform/Dockerfile` の digest が manifest list の digest であること」を入れる |
| D2-1-5 | 低 | research.md「外部の公開情報の取得元」LocalStack の `tag_pattern` と design.md「inventory-targets.json」 | research.md 73行は `^[0-9]{4}\.[0-9]{1,2}\.[0-9]+$` のままで、design.md(D1-1-2 の反映後)の `^[0-9]{4}\.[1-9][0-9]?\.[0-9]+$` と食い違う。research は spec 本文ではないが、design が「詳しい調査の記録」として参照している | research.md の正規表現を design と同じにし、月の先頭の0を許さない理由(別名 `2026.08.4` を除く)を添える |
| D2-1-6 | 低 | design.md「Testing Strategy」Integration の tflint の項 | 「そのPRが公開から72時間経つまで予約されず、経った後の見直しで予約されること」を確かめるとしているが、見直しの時点では必須チェックがすべて緑になっていることが多く、その状態で `gh pr merge --auto` を実行したときに「予約」として残るか直ちにマージされるかは gh の実装に依る(本審査では確かめていない)。どちらでも要件は満たすが、確認の文言が「予約されること」だけだと、直ちにマージされた場合に確認が失敗と読まれる | 確認の文言を「経った後の見直しで予約またはマージされること(実行ログに `reserve` の判定が出ること)」にする。あわせて、`recheck` job の1つの PR で `check-release-age.sh` が exit 2 になったときに他の PR の見直しを続けるかを本文か tasks で決める |

### 前の段階への指摘

新たな指摘は無い。requirements サイクル3で design に委ねられた点(R3-1-3 のコメントの繰り返しと手順書の対処、R3-3-1 の翌日の見直し)は、いずれも本文で決められている。

- 往復: 1回目 / 高0 中0 低6
- 往復: 1回で収束 / 未解決: 0件
