# タスク

この spec のタスクは、design.md の「移行」の節の「段階ごとの PR」に合わせて、大タスク1つを PR 1つに当てる。大タスク1は PR 2-1、大タスク2は PR 2-2、大タスク3は PR 2-3、大タスク4は PR 2-4、大タスク5は PR 2-5、大タスク6は PR 4-1、大タスク7は PR 4-2、大タスク8は PR 4-3 である。大タスク9は段階5の確認と記録、大タスク10から14は段階6の PR 6-1 から 6-5 である。段階3の機能のまとまりの Go 版は、まとまりの spec で作るので、この tasks.md には無い。この spec の進め方は、末尾の「実装のメモ」に書いてある。

- [x] 1. ゲート設定を Go 版に対応させる(PR 2-1)
- [x] 1.1 run-check.sh に領域 backend-go を足す

  Claude は、`.claude/scripts/parallel/run-check.sh` に領域 `backend-go` を足す。この領域は、compose のサービス `backend-go` で1回きりのコンテナを作り、dind を起こし、リポジトリの最上位を読み取り専用で `/repo` に差し込み、環境変数 `KEIREKIPRO_REPO_ROOT=/repo` を渡す。この領域の最後の検査は `make check` である。`run-check.sh` は、`make check` が通ったときだけ、Go 版の品質チェックを動かした記録を書く。
  - 完了の確かめ方: `bash .claude/scripts/parallel/tests/test-run-check.sh` が、足した場合を含めて成功する
  - 受入基準とテストの対応: 要件3の受入基準2(どの OS でも1つのコマンドで Go 版の品質チェックを動かせる)は、`test-run-check.sh` の「backend-go の領域を受け付ける」「backend-go の make check が通ったときだけ記録を書く」「backend-go で dind を起こす」「backend-go に /repo を読み取り専用で差し込む」の場合で確かめる
  - _要件: 3.2_

- [x] 1.2 作業を終えるときの確認のフックで、Java 版と Go 版の記録を分ける

  Claude は、`.claude/hooks/check-verify-before-stop.sh` とそのテストの完成版を、置き場(実装のメモの「置き場」)に作る。このフックは、変わったファイルを、design.md の「CI の仕事」の見分け `backend_java` と `backend_go` と同じ形で分け、Java 版のファイルが変わったときは Java 版の記録を、Go 版のファイルが変わったときは Go 版の記録を求める。マイグレーションのファイルが変わったときは、両方の記録を求める。
  - 完了の確かめ方: 検査用の写しで、`.claude/hooks/tests/test-check-verify-before-stop.sh` が成功する
  - 受入基準とテストの対応: 要件3の受入基準2(Go 版の品質チェックの記録)は、`test-check-verify-before-stop.sh` の「Go 版のファイルだけが変わったときは Go 版の記録で止めない」「Java 版のファイルだけが変わったときは Java 版の記録を求める」「マイグレーションのファイルが変わったときは両方の記録を求める」の場合で確かめる
  - _要件: 3.2_
  - _依存: 1.1_

- [x] 1.3 verify のスキルに Go 版の手順を足す

  Claude は、`.claude/skills/verify-backend/SKILL.md` と `verify-all` のスキルに、Go 版のファイルが変わったときに `bash .claude/scripts/parallel/run-check.sh backend-go make check` を動かす手順を足す。Java 版の手順は変えない。
  - 完了の確かめ方: 2つのスキルの本文に、Go 版のファイルの見分け方と、領域 `backend-go` で `make check` を動かす手順がある
  - 受入基準とテストの対応: 要件3の受入基準2(決まった1つのコマンド)は、スキルの本文を読み、領域 `backend-go` のコマンドが1つだけ書かれていることで確かめる。スキルは文書なので、テストは無い
  - _要件: 3.2_
  - _依存: 1.1_

- [x] 1.4 backend-test の判定のスクリプトを作る (並行可)

  Claude は、`.github/scripts/backend-test-verdict.sh` とそのテスト `.github/scripts/tests/test-backend-test-verdict.sh` を、置き場に作る。このスクリプトは、3つの見分け(`backend_java` `backend_go` `backend_compat`)と3つの仕事の結果を受け取り、見分けが当たった仕事の結果が `success` でないとき、または見分けが当たったのに飛ばされた仕事があるときに失敗する。テストは、環境変数 `KP_TEST_CASE` に場合の名前を入れれば、その場合だけを流せる。
  - 完了の確かめ方: 検査用の写しで、`test-backend-test-verdict.sh` が成功する
  - 受入基準とテストの対応: 要件3の受入基準4(飛ばされたままマージされない)は「見分けが当たった仕事が skipped なら失敗する」の場合で、要件4の受入基準7と要件13の受入基準6(比べる検査が通らない PR は main に入らない)は「backend-compat が failure なら失敗する」の場合で、要件3の受入基準5(Go のファイルが無い間は Java 版の結果だけで決まる)は「backend_go と backend_compat が当たらず backend-java が success なら成功する」の場合で確かめる
  - _要件: 3.4, 3.5, 4.7, 13.6_
  - _対象の部品: CI の仕事_

- [x] 1.5 ci.yaml の backend の仕事を3つに分け、まとめの仕事で判定する

  Claude は、`.github/workflows/ci.yaml` の完成版を置き場に作る。完成版で変えるものは、次の4つである。

    - 見分け: `detect-changes` は見分け `backend_java` `backend_go` `backend_compat` を出す。`backend_java` と `backend_go` に当たるファイルの形は、design.md の「CI の仕事」の一覧のとおりにし、`backend_go` には `backend/assets/**` を含める。`backend_go` は、検査するコミットに `backend/go.mod` があるときだけ当たる。マイグレーションのファイルの変更は、3つの見分けのすべてに当たる。`backend_compat` は、検査するコミットに `backend/compat/` のフォルダがあり、変わったファイルが `backend_java` か `backend_go` か `backend/compat/**` に当たるときに当たる。
    - 4つの仕事の中身: 仕事は、`backend-java` と `backend-go` と `backend-compat` と `backend-test` の4つにする。`backend-java` は、今の `backend-test` の手順を動かす。`backend-go` は、`actions/setup-go` と版を固定した golangci-lint で `make check` を動かす。`backend-go` は、PR では、リポジトリの履歴のすべてを `fetch-depth: 0` で取得してから、`make mutation-diff BASE=origin/${{ github.base_ref }}` も動かす。`backend-compat` は、poppler-utils を入れて `make compat` と `make compat-cross` を動かし、違いの報告を成果物に残す。`backend-test` は、`if: always()` を付けて、タスク1.4の `backend-test-verdict.sh` を呼ぶ。
    - 権限と動く時: 4つの仕事に与える権限は、`contents: read` に限る。4つの仕事は、`pull_request` と、main への `push` で動く。
    - `docker-smoke`: `docker-smoke` には、`docker/backend-go/Dockerfile.prod` を組み立ての文脈 `./backend` で組み立てる分岐を足す。
  - 完了の確かめ方: 検査用の写しで、`docker run --rm -v "<写し>:/repo" -w /repo rhysd/actionlint:1.7.12 -color` と `bash .github/scripts/check-action-pinning.sh` が成功する
  - 受入基準とテストの対応: 要件3の受入基準2(CI で Go 版の品質チェックが必ず動く)と要件4の受入基準7(main への push でも比べる検査が動く)は、actionlint が通る ci.yaml を読み、見分けと仕事の条件と `on:` の組を確かめる。判定の中身は、1.4 の `test-backend-test-verdict.sh` で確かめる
  - _要件: 3.1, 3.2, 3.4, 4.7, 13.6_
  - _依存: 1.4_

- [x] 1.6 CodeQL の Go の組み立て方を決める (並行可)

  Claude は、`.github/codeql/languages.tsv` の Go の行を、組み立て方 `manual`、組み立てのコマンド `cd backend && go build ./...` にした完成版を、置き場に作る。
  - 完了の確かめ方: 検査用の写しで、`.github/scripts/tests/test-detect-codeql-languages.sh` が成功する
  - 受入基準とテストの対応: 要件3の受入基準1(ソースコードの脆弱性の診断)は、`test-detect-codeql-languages.sh` に足す「Go のファイルを含む変更で go の行を manual で選ぶ」の場合で確かめる
  - _要件: 3.1_
  - _対象の部品: CodeQL とイメージの検査と組み立てて動かす検査_

- [x] 1.7 index.golang.org から gomod の部品の公開の時刻を読む部品を作り、公開の時刻の検査につなぐ

  Claude は、`.github/scripts/lib-gomod-index.sh` とそのテストを置き場に作る。この部品は、index.golang.org の索引を、検査の時刻の73時間前から `since` で順に1度だけ読み、モジュールと版の組ごとに初めて取り込まれた時刻を返す。proxy.golang.org の `.info` の時刻は使わない。Claude は、`check-dependency-cooldown.sh` と、そこから呼ぶ `cooldown-check-*.sh` と `cooldown-match-alerts.sh` を、gomod の部品に対応させる。
  - 完了の確かめ方: 検査用の写しで、`test-lib-gomod-index.sh`、`test-check-dependency-cooldown.sh`、`test-cooldown-match-alerts.sh` が成功する
  - 受入基準とテストの対応: 要件3の受入基準1(公開から72時間たっていない部品を止める)は、`test-lib-gomod-index.sh` の「72時間より新しい組を新しいと返す」「72時間より古い組を古いと返す」「索引を1度だけ読む」の場合と、`test-check-dependency-cooldown.sh` に足す「gomod の部品が新しければ止める」の場合で確かめる
  - _要件: 3.1_

- [x] 1.8 Dependabot の PR の公開の時刻の検査を gomod に対応させる

  Claude は、`.github/scripts/check-release-age.sh` を、タスク1.7で作る `lib-gomod-index.sh` で gomod の部品の公開の時刻を調べる形にした完成版を、置き場に作る。
  - 完了の確かめ方: 検査用の写しで、`test-check-release-age.sh` が成功する
  - 受入基準とテストの対応: 要件3の受入基準1(公開から72時間たっていない部品を止める)は、`test-check-release-age.sh` に足す「gomod の版が72時間より新しければ止める」「gomod の版が古ければ通す」の場合で確かめる
  - _要件: 3.1_

- [x] 1.9 承認の対象と守る対象と escape-hatch の検知を Go に対応させる (並行可)

  Claude は、`.github/scripts/check-dependency-additions.sh` の承認の対象に `backend/Makefile` `backend/.golangci.yml` `backend/.testcoverage.yml` `backend/.gremlins.yaml` `backend/api/oapi-codegen.yaml` `backend/sqlc.yaml` を足す。Claude は、`.github/CODEOWNERS` に同じ6つのファイルを足す。Claude は、`.github/scripts/check-escape-hatches.sh` に、Go のテストの飛ばし(`t.Skip` `t.SkipNow` `t.Skipf`)と `//nolint` の追加を見つける形を足し、同じ6つのファイルを、所有者の承認があれば通るゲート隣接ファイルの一覧に足す。`check-escape-hatches.sh` は、`.testcoverage.yml` に除外を足す変更を、ゲート隣接ファイルの扱いで、所有者の承認が無ければ止める。Claude は、`check-dependency-additions.sh` と `CODEOWNERS` と `check-escape-hatches.sh` の完成版と、2つのスクリプトのテストを、置き場に作る。
  - 完了の確かめ方: 検査用の写しで、`test-check-dependency-additions.sh` と `test-check-escape-hatches.sh` が成功する
  - 受入基準とテストの対応: 要件3の受入基準3(Go 版の合格の基準を緩くしない)は、`test-check-dependency-additions.sh` に足す「.testcoverage.yml の変更を承認の対象にする」の場合と、`test-check-escape-hatches.sh` に足す「t.Skip の追加を見つける」「nolint の追加を見つける」「.testcoverage.yml の変更は所有者の承認が無ければ失敗する」「.testcoverage.yml を新しく作る変更は所有者の承認があれば通る」の場合で確かめる
  - _要件: 3.3_
  - _対象の部品: Makefile、.golangci.yml と .testcoverage.yml と .gremlins.yaml_

- [x] 1.10 所有者に置いてもらい、ゲート設定のテストをすべて流して PR を出す

  Claude は、実装のメモの「所有者に置いてもらう」のとおりに、置き場のファイルを所有者に本来の場所へ置いてもらったあと、`.github/scripts/tests/` と `.claude/scripts/parallel/tests/` と `.claude/hooks/tests/` のテストを Linux のコンテナで流し、shellcheck v0.11.0 をすべての `.sh` に流す。この PR には、この spec の文書(spec.json、requirements.md、design.md、research.md、tasks.md、reviews/)を入れる。Claude は、作業フォルダの `backend/api/openapi.yaml` を `.kiro/specs/backend-go-replacement/openapi.yaml` に移し、この PR に入れる。Claude は、仕様書を `backend/api/` に置く変更を、仕様書からコードを生成する設定を作るタスク2.2と同じ PR に入れる。仕様書と、仕様書から生成したコードが、別々の PR に分かれて食い違わないようにするためである。Claude は、PR 2-2 を、main から作る新しいブランチで進める。そのため、git で管理していない仕様書は、今の作業フォルダが片付けられると失われる。
  - 完了の確かめ方: すべてのテストと shellcheck と actionlint が成功し、PR の本文に `Spec: .kiro/specs/backend-go-replacement` と `Refs: #445` と、「承認が要る理由」と「main に入れたときに本番で起きること」の2つの欄がある
  - 受入基準とテストの対応: 要件1の受入基準2(PR の本文の2つの行)と要件7の受入基準3(承認が要る理由と本番で起きること)は、テストでなく、`gh pr view` で読んだ PR の本文で確かめる。要件3の受入基準5(Go 版のコードは、Go 版の土台を入れる PR 2-2 から main に入る)は、`git diff --name-only origin/main` に `.go` のファイルが無いことで確かめる
  - _要件: 1.2, 3.5, 7.2, 7.3_

- [ ] 2. Go 版の土台と品質チェックの設定と開発環境を入れる(PR 2-2)
- [x] 2.1 Go のモジュールと開発環境のイメージと compose のサービスを作る

  Claude は、`backend/go.mod` と `backend/go.sum` を作り、`toolchain go1.27.3` と、`tool` の指定で oapi-codegen と sqlc と go-test-coverage と gremlins と govulncheck の版を書く。Claude は、`docker/backend-go/Dockerfile` を作る。このイメージは、`golang:1.27.3-trixie` に、タスク1.5で `ci.yaml` に固定したのと同じ版の golangci-lint と、poppler-utils と、Docker の CLI と、Debian の `chromium` と、`fonts-noto-cjk` を入れる。Claude は、`compose.yaml` にサービス `backend-go` とボリューム `backend-go-cache` を足す。サービス `backend-go` は、ホストの 8081 をコンテナの 8080 につなぐ。
  - 完了の確かめ方: `docker compose build backend-go` が成功し、`bash .claude/scripts/parallel/run-check.sh backend-go go version` が `go1.27.3` を返す
  - 受入基準とテストの対応: 要件3の受入基準2(どの OS でも1つのコマンド)は、`run-check.sh backend-go` がこのイメージで動くことで確かめる。テストのコードは無い
  - _要件: 3.2_

- [x] 2.2 API の仕様書を入れ、HTTP の受け口のコードを生成する

  Claude は、タスク1.10で入れた `.kiro/specs/backend-go-replacement/openapi.yaml` を `git mv` で `backend/api/openapi.yaml` に移し、`backend/api/oapi-codegen.yaml`(`std-http-server` と `strict-server` と `models`)と `backend/sqlc.yaml`(マイグレーションのファイルを V1 から順に1つずつ並べる)を作る。Claude は、`backend/Makefile` に `generate` と `generate-check` を作る。`generate-check` は、一時のフォルダに生成し、リポジトリのファイルと `diff -r` で比べる。
  - 完了の確かめ方: `run-check.sh backend-go make generate` で `backend/internal/httpapi/gen/api.gen.go` ができ、`run-check.sh backend-go make generate-check` が成功し、生成したファイルを1行変えると `generate-check` が失敗する
  - 受入基準とテストの対応: 要件4の受入基準3(すべての API を仕様書に書く)は、`internal/httpapi/gen_test.go` の `TestGeneratedOperationsCount`(生成した `StrictServerInterface` が50の操作を持つ)で、要件14の受入基準2(仕様書と受け口の食い違いを品質チェックが止める)は、`make generate-check` が生成したコードの書き換えで失敗することで確かめる
  - _要件: 4.3, 14.2_

- [ ] 2.3 静的な検査とカバレッジと変異テストの設定と、品質チェックの入口を作る

  Claude は、`backend/.golangci.yml` と `backend/.testcoverage.yml` と `backend/.gremlins.yaml` を作る。`.golangci.yml` には、`version: "2"` と、gofumpt と goimports と、標準の組と depguard と errcheck と gosec と bodyclose と sqlclosecheck と、`run.build-tags: [compat]` を書く。`.testcoverage.yml` には、`./internal/...` の文の割合の下限 93% を書き、数えないフォルダを `internal/httpapi/gen/` と sqlc の出力のフォルダだけにする。Claude は、`backend/Makefile` に `fmt` `fmt-check` `lint` `test` `coverage` `build` `check` `mutation-diff` `mutation-full` `vuln` `compat` `compat-cross` `compat-perf` を足す。`build` は `go build ./...` を動かし、`backend/compat/` があるときだけ `go build -tags compat ./compat/...` も動かす。depguard の規則は、`internal/platform/**` が `internal/httpapi` と機能のパッケージを読むことと、機能のパッケージが `internal/httpapi` と `cmd` を読むことを断る。
  - 完了の確かめ方: `run-check.sh backend-go make lint` が成功し、`internal/platform` の下に `internal/httpapi` を読む仮のファイルを置くと `make lint` が depguard で失敗する
  - 受入基準とテストの対応: 要件3の受入基準1(書式、静的な検査、依存の向き、カバレッジ、変異テスト、脆弱性)は、Makefile のタスクの一覧と、depguard の違反を置いたときの `make lint` の失敗で、要件3の受入基準3(下限 93% と分岐の割合の代わり)は、`.testcoverage.yml` の `threshold` と `make mutation-diff` の `--threshold-efficacy 80 --threshold-mcover 93` で確かめる。`.golangci.yml` に `run.build-tags: [compat]` を書くのは、design の審査の D3-1-6(比べる検査のコードを `make lint` が読むか)への答えである
  - _要件: 3.1, 3.2, 3.3_

- [ ] 2.4 表の形の履歴の部品を作る

  Claude は、`backend/migrations.go`(`//go:embed src/main/resources/db/migration/*.sql`)と `backend/internal/platform/migrate/` を作る。この部品は、design.md の「migrate」のとおり、検査の値を計算し、`ValidateOnly` と `Apply` の2つの動かし方を持ち、`pg_advisory_lock` で1つずつ動く。`description` には、ファイル名から `V<版>__` と `.sql` を除き、`_` を空白にしたものを書く。この書き方は、design の審査で D3-3-2 として残った、`description` をどう書くかへの答えである。
  - 完了の確かめ方: `run-check.sh backend-go go test ./internal/platform/migrate/...` が成功する
  - 受入基準とテストの対応: 要件12の受入基準4(表の形の履歴を引き継ぐ)は、`migrate_test.go` の `TestChecksum_V1toV7`(research.md の7つの値と一致)、`TestRun_ValidateOnly_ChecksumMismatch`、`TestRun_ValidateOnly_FailedRow`、`TestRun_ValidateOnly_UnknownVersion`、`TestRun_ValidateOnly_WritesNothing`、`TestDescription_FromFileName` と、結合テスト `migrate_integration_test.go` の `TestValidateOnly_FlywayWrittenHistory`(testcontainers-go の Postgres に Flyway の形の表を作って通る)で、要件1の受入基準5(表の形を変えない)は、`TestRun_ValidateOnly_WritesNothing` で確かめる
  - _要件: 1.5, 12.4_

- [ ] 2.5 データベースと Redis と AWS につなぐ部品を作る (並行可)

  Claude は、`backend/internal/platform/database/` と `redisstore/` と `awsclient/` を作る。database は、接続ごとに `TimeZone` を `Asia/Tokyo` にし、接続の最大を10にする。redisstore は、本番ではクラスタの形と TLS と利用者の名前でつなぎ、`dev` と `test` では1台の形でつなぎ、Java 版と同じ Lua のスクリプトの文字列を持つ。awsclient は、S3 と SES v1 と Secrets Manager につなぎ、`dev` と `test` では `KEIREKIPRO_AWS_ENDPOINT` とパスの形を使う。3つの部品は、つなぎ先の値を引数で受け取り、設定の部品を読まない。
  - 完了の確かめ方: `run-check.sh backend-go go test ./internal/platform/database/... ./internal/platform/redisstore/... ./internal/platform/awsclient/...` が成功する
  - 受入基準とテストの対応: 要件12の受入基準1(データベースをそのまま読み書き)は `database_integration_test.go` の `TestPool_TimeZoneTokyo` で、要件13の受入基準5(形を変えてもログアウトされない取り決め)の土台の Redis の形は `redisstore_integration_test.go` の `TestScripts_SameResultAsJava`(Java 版と同じ Lua のスクリプトが同じ結果を返す)で、要件12の受入基準3(画像が同じに表示される)の土台の S3 のつなぎ方は `awsclient_test.go` の `TestNew_DevUsesPathStyleEndpoint` で確かめる
  - _要件: 12.1, 12.3, 13.5_
  - _対象の部品: database と redisstore と awsclient_

- [ ] 2.6 設定と秘密の値の読み込みを作る

  Claude は、`backend/internal/platform/config/` を作る。この部品は、`KEIREKIPRO_ENV` の値 `prod` `dev` `test` で環境を決める。`KEIREKIPRO_ENV` が無ければ、この部品は環境を `dev` にする。この部品は、Java 版の `application*.yaml` と同じ既定の値を持つ。`prod` では、タスク2.5の awsclient の Secrets Manager で design.md の表の5つの秘密の値を読み、`dev` と `test` では Java 版と同じ名前の環境変数と `KEIREKIPRO_OIDC_*` を読む。
  - 完了の確かめ方: `run-check.sh backend-go go test ./internal/platform/config/...` が成功する
  - 受入基準とテストの対応: 要件5の受入基準1(本番の設定を Java 版のままでも動く形で先に入れる)と要件12の受入基準2(同じアカウントでログインできる設定を読む)は、`config_test.go` の `TestLoad_ProdReadsSecretKeys`、`TestLoad_MissingKeyErrorHasNoValue`、`TestLoad_DevReadsJavaEnvNames`、`TestLoad_DefaultEnvIsDev`、`TestLoad_OIDCEndpointOverride` で確かめる
  - _要件: 5.1, 12.2_

- [ ] 2.7 ログの形を作る (並行可)

  Claude は、`backend/internal/platform/logging/` を作る。この部品は、`slog` の JSON の書き手を標準出力に置き、項目の名前を、design.md の「logging」に書いた Elastic Common Schema の10の名前に合わせる。Elastic Common Schema は、ログの項目の名前の決まりである。要求ごとのログに、Cookie と Authorization と要求の本文を書かない。
  - 完了の確かめ方: `run-check.sh backend-go go test ./internal/platform/logging/...` が成功する
  - 受入基準とテストの対応: 要件5の受入基準8(Java 版と同じ場所と形のログ)は、`logging_test.go` の `TestHandler_ECSFieldNames` と `TestHandler_ErrorFields` で確かめる
  - _要件: 5.8_
  - _対象の部品: logging_

- [ ] 2.8 HTTP の受け口の共通部分を作る

  Claude は、`backend/internal/httpapi/server.go`、`middleware/`、`health.go` を作る。Claude は、中間処理を、パニックの受け止め、要求のログ、偽の送信の検査、ログインの状態の検査の差し込み口の順に並べる。パニックとは、Go のプログラムが、処理を続けられない誤りに当たって、その処理を途中で打ち切ることである。HTTP の受け口の共通部分は、まだ作っていない操作への要求に、501 と `{"message":"未実装です。"}` を返す。HTTP の受け口の共通部分は、仕様書に無い経路への要求に 404 を返す。HTTP の受け口の共通部分は、`/actuator/health` と `/healthz` への要求を受けると、データベースに `SELECT 1` を送り、200 と `{"status":"UP"}` か、503 と `{"status":"DOWN"}` を返す。HTTP の受け口の共通部分は、形の誤った要求に、Java 版と同じ `{message, errors}` の形の本文で 400 を返す。
  - 完了の確かめ方: `run-check.sh backend-go go test ./internal/httpapi/...` が成功する
  - 受入基準とテストの対応: 要件9の受入基準4(偽の要求を断る)は `csrf_test.go` の `TestCSRF_MismatchReturns403WithNewCookie`、`TestCSRF_GetPasses`、`TestCSRF_RunsBeforeAuth` で、要件9の受入基準1と2(同じ URL とエラーの形)は `server_test.go` の `TestUnimplementedReturns501`、`TestBadJSONReturns400MessageErrors` で、要件9の受入基準5(Go の標準の形への変更を許す)の土台は `TestPanicReturns500JavaBody` で、要件14の受入基準3(本番で説明画面を開けない)は `TestUnknownRouteReturns404`(`/swagger-ui/index.html` と `/v3/api-docs` に 404)で、生きているかの確認は `health_test.go` の `TestHealth_UpAndDown` で確かめる
  - _要件: 9.1, 9.2, 9.4, 9.5, 14.2, 14.3_

- [ ] 2.9 PDF を作る部品を作る (並行可)

  Claude は、`backend/internal/platform/pdf/` を作る。この部品は、Chromium を1つ起動したまま持ち、PDF ごとにタブを開いて閉じ、JavaScript を止め、`data:` のほかの通信を断り、`preferCSSPageSize: true` と `printBackground: true` で印刷する。この部品は、同時に作る PDF の数を2までにし、1つの PDF を作る処理を30秒で打ち切り、Chromium が異常で終わったら、次の要求の前に Chromium を起動し直す。この部品は、chromedp の既定の探し方で、本番のイメージの headless-shell と、開発環境のイメージの `chromium` と、CI の機械の Google Chrome のどれでも、ブラウザの実行ファイルとして見つける。見つからなければ、起動の失敗として誤りを返す。
  - 完了の確かめ方: `run-check.sh backend-go go test ./internal/platform/pdf/...` が成功する
  - 受入基準とテストの対応: 要件10の受入基準1(同じ見た目の PDF)の土台と要件13の受入基準1(PDF の出力がエラーにならない)は、`pdf_test.go` の `TestRender_A4`、`TestRender_ThirdWaitsForFirst`、`TestRender_TimeoutReturnsError`、`TestRender_RestartsAfterCrash`、`TestRender_BlocksNetwork`、`TestNew_NoBrowserReturnsError` で確かめる。CI の機械の Google Chrome で動くことは、タスク2.13の PR の CI の `backend-go` で確かめる。見た目が Java 版と同じことは、Claude が、出力のまとまりの spec で作る比べる検査で確かめる
  - _要件: 10.1, 13.1_
  - _対象の部品: pdf_

- [ ] 2.10 起動の入口を作る

  Claude は、`backend/cmd/keirekipro/main.go` を作る。入口は、設定を読み、`ValidateOnly` で表の形の履歴を確かめ、データベースと Redis と AWS と PDF の部品をつなぎ、8080 を開く。入口は、`SIGTERM` を受けたら、最大90秒待ってから、8080 で開いた受け口を閉じる。最初の接続のどれかが失敗したら、理由をログに書き、終了コード1で終わる。
  - 完了の確かめ方: `run-check.sh backend-go go test ./cmd/keirekipro/...` が成功する
  - 受入基準とテストの対応: 要件5の受入基準7(出荷が途中で失敗したら Java 版のまま)の土台は `main_test.go` の `TestRun_ExitsWithCode1OnMigrateError`、`TestRun_ExitsWithCode1OnDBUnreachable` で、要件5の受入基準6(戻してもログアウトされない)の土台の止め方は `TestRun_GracefulShutdownWaits` で、要件5の受入基準8(ログ)は `TestRun_LogsStartupFailureReason` で、要件9の受入基準4(偽の要求を断る中間処理がつながる)は `TestRun_MiddlewareOrder` で確かめる
  - _要件: 5.6, 5.7, 5.8, 9.4_

- [ ] 2.11 Go 版の本番のイメージを作る

  Claude は、`docker/backend-go/Dockerfile.prod` と `backend/assets/fonts.conf` を作る。1つ目の工程は `golang:1.27.3-trixie` で `CGO_ENABLED=0 GOOS=linux GOARCH=$TARGETARCH go build -trimpath` を動かす。2つ目の工程は、digest で固定した `chromedp/headless-shell` に、`backend/src/main/resources/fonts/` の Noto の4つのフォントを `/usr/share/fonts/keirekipro/` に置き、`fonts.conf` と `curl` を入れ、プログラムを動かす利用者を uid 10001 にし、`ENTRYPOINT` を `["/app/keirekipro"]` にする。
  - 完了の確かめ方: `docker build -f docker/backend-go/Dockerfile.prod backend` が成功し、できたイメージを接続先なしで起動すると終了コード1で終わり、`docker run --entrypoint fc-list` で4つのフォントが出る
  - 受入基準とテストの対応: 要件3の受入基準1(本番と同じ形のイメージを組み立てて動かす検査)と要件5の受入基準2(1回の出荷で切り替えられるイメージ)と要件10の受入基準1(同じフォント)は、`docker build` の成功と `fc-list` の出力で確かめる
  - _要件: 3.1, 5.2, 10.1_

- [ ] 2.12 開発の手順と進み具合の表を書き、機能のまとまりの子の Issue を起票する

  Claude は、`start-dev.sh` に `backend-go` を足す。Claude は、`backend/CLAUDE.md` に、Go 版の作り方として、パッケージの分け方と依存の向きと、品質チェックのコマンドと、Redis と S3 の形を変えるときの2回の出荷の決まりを足す。Claude は、`.kiro/specs/backend-go-replacement/progress.md` を作り、次の5つを書く。

    - 段階の表。段階1の行は research.md の「段階1 試作の記録」を指す
    - まとまりの表。5つのまとまりと、それぞれの子の Issue と spec と状態を書く
    - 所有者がする6つの操作
    - PR の本文の決まり
    - 会話が途切れたときの読み直し方

  Claude は、`file-issue` のスキルの決まりで、5つのまとまりの子の Issue を起票し、`gh api` の sub-issues で Issue #445 につなぐ。
  - 完了の確かめ方: `gh api repos/{owner}/{repo}/issues/445/sub_issues` が5つの Issue を返し、progress.md のまとまりの表に5つの Issue の番号がある
  - 受入基準とテストの対応: この小タスクの受入基準は、Claude の進め方の決まりと文書であり、テストのコードは無い。要件1の受入基準1と2と6(6つの段階、PR の本文の2つの行、一方を直すときはもう一方も直す)、要件2の受入基準1から5(設計の前に試しに作って確かめる)、要件4の受入基準1と2(まとまりごとの子の Issue と spec、要件を書き写さない)、要件7の受入基準1と3から5(所有者がする6つの操作、承認が要る理由と本番で起きること、進み具合を1か所で見られる、会話が途切れても続ける)、要件8の受入基準1から3(決めた方式のとおりに作れないときなどに止まって報告する)は progress.md の本文で、要件4の受入基準1(子の Issue)は `gh api` の sub-issues の結果で、要件6の受入基準4(Go 版の説明を足す)と要件13の受入基準5(2回の出荷の決まり)は `backend/CLAUDE.md` の本文で確かめる
  - _要件: 1.1, 1.2, 1.6, 2.1, 2.2, 2.3, 2.4, 2.5, 4.1, 4.2, 6.4, 7.1, 7.3, 7.4, 7.5, 8.1, 8.2, 8.3, 13.5_

- [ ] 2.13 Go 版の品質チェックを通し、PR を出す

  Claude は、`/verify-backend` を動かし、`bash .claude/scripts/parallel/run-check.sh backend-go make check` と `run-check.sh backend-go make vuln` を通す。Claude は、`docker build -f docker/backend-go/Dockerfile.prod backend` も通す。Claude は、PR の本文の「承認が要る理由」の欄に、Makefile などの品質チェックの設定が承認の対象であることを書き、「main に入れたときに本番で起きること」の欄に、本番で起きることは無いと書く。
  - 完了の確かめ方: `make check` が成功し、Go 版の品質チェックの記録が書かれ、PR の CI の `backend-go` と `backend-test` が成功する
  - 受入基準とテストの対応: 要件3の受入基準1から3(9種類の品質チェックをそろえる、1つのコマンドで動かせる、合格の基準を緩くしない)は、`make check` と、CI の `backend-go` の仕事の `make mutation-diff` の結果で確かめる。要件7の受入基準3(承認が要る理由と、main に入れたときに本番で起きることを示す)は、`gh pr view` で読んだ PR の本文で確かめる
  - _要件: 3.1, 3.2, 3.3, 7.3_

- [ ] 3. Java 版と Go 版を比べる検査を入れる(PR 2-3)
- [ ] 3.1 比べる検査の土台を作る

  Claude は、`backend/compat/harness/`(ビルドタグ `compat`)に、`KEIREKIPRO_REPO_ROOT` から design.md の6つのイメージを testcontainers-go の Dockerfile からの組み立てで作る処理と、検査ごとに Docker のネットワークを1つ作り `java` `go` `fakeaws` `fakeoidc` などの名前でコンテナを入れる処理と、筋書きのファイルを読む処理を作る。harness は、コンテナの起動を5分で、1つの要求を60秒で打ち切り、失敗したら両方の版のコンテナのログを残す。harness は、検査の始めに、各データベースに migrate の `Apply` で V1〜V7 を適用する。harness は、Go 版のコンテナを起動するときに、起動から `/healthz` が 200 を返すまでの時間を測り、10秒を超えたら検査を失敗にする。
  - 完了の確かめ方: `run-check.sh backend-go go test -tags compat ./compat/harness/...` が成功する
  - 受入基準とテストの対応: 要件4の受入基準5(同じ要求を送って比べる検査を作る)の土台は、`harness_test.go` の `TestLoadScenario_ParsesSteps`、`TestLoadScenario_RejectsUnknownMode`、`TestNetwork_ContainersResolveByName` で、Go 版の本番のイメージの起動の時間は `TestStartup_Over10sFails` と `TestStartup_Within10sPasses` で確かめる
  - _要件: 4.5_
  - _保留: PR 2-2 が main に入ったあと、所有者が `/kiro-impl backend-go-replacement` を打った会話で、Claude が大タスク3を行う_

- [ ] 3.2 AWS の代わりを作る (並行可)

  Claude は、`backend/compat/fakeaws/`(ビルドタグ `compat`)と、その `Dockerfile`(`golang:1.27.3-trixie` で組み立て、digest で固定した `gcr.io/distroless/static-debian13:nonroot` に置く)を作る。fakeaws は、S3 のパスの形の `PutObject` `GetObject` `DeleteObject` と署名付きの URL の `GetObject`、SES v1 の `SendEmail`、Secrets Manager の `GetSecretValue` を受け、受けたものを版ごとに覚えて返す。
  - 完了の確かめ方: `run-check.sh backend-go go test -tags compat ./compat/fakeaws/...` が成功する
  - 受入基準とテストの対応: 要件9の受入基準3(メールの件名と本文を比べられる)は `fakeaws_test.go` の `TestSendEmail_RecordsPerVersion` で、要件12の受入基準3(画像を比べられる)は `TestS3_PutGetDelete` と `TestS3_PresignedGet` で、Java 版の起動に要る秘密の値は `TestSecretsManager_GetSecretValue` で確かめる
  - _要件: 9.3, 12.3_
  - _対象の部品: fakeaws と fakeoidc_
  - _保留: 3.1 と同じ_

- [ ] 3.3 外部のログインの代わりを作る (並行可)

  Claude は、`backend/compat/fakeoidc/`(ビルドタグ `compat`)とその `Dockerfile` を作る。fakeoidc は、Google の認可と token と userinfo と、GitHub の認可と `access_token` と `/user` と `/user/emails` に、筋書きが決めた利用者の値で応答を返す。
  - 完了の確かめ方: `run-check.sh backend-go go test -tags compat ./compat/fakeoidc/...` が成功する
  - 受入基準とテストの対応: 要件12の受入基準2(Google と GitHub のアカウントでログインできることを比べられる)は、`fakeoidc_test.go` の `TestGoogleFlow_ReturnsScenarioUser` と `TestGitHubFlow_ReturnsScenarioUserAndEmails` で確かめる
  - _要件: 12.2_
  - _対象の部品: fakeaws と fakeoidc_
  - _保留: 3.1 と同じ_

- [ ] 3.4 正規化と比べる処理と報告を作る

  Claude は、`backend/compat/harness/` に、design.md の「比べ方」の表の9つのものの正規化と比べ方と、違いの報告を作る。違いの報告には、筋書きの名前、段、比べたもの、Java 版の値、Go 版の値を書き、違いの見つかった最初の段を先頭に置く。比べる検査は、Java 版を `SPRING_PROFILES_ACTIVE=dev` と fakeaws に登録した秘密の値で、Go 版を `KEIREKIPRO_ENV=dev` で動かす。
  - 完了の確かめ方: `run-check.sh backend-go go test -tags compat ./compat/harness/...` が成功する
  - 受入基準とテストの対応: 要件4の受入基準4と5(実際の応答と保存したデータを正解にして比べる)と要件4の受入基準6(違いがあれば止める)は、`compare_test.go` の `TestCompareJSON_UUIDNumbering`、`TestCompareJSON_TokenClaims`、`TestCompareHeaders_OnlySelected`、`TestCompareDB_SortsAfterNormalize`、`TestCompareRedis_TTLTolerance5s`、`TestCompareMail_TokenInURL` と、`report_test.go` の `TestReport_FirstDiffStepFirst` で、要件9の受入基準1から3(画面が使う URL とデータの形、エラーの文言と条件、メールの件名と本文を同じにする)、要件10の受入基準2(Markdown が1文字も違わない)、要件11の受入基準1から3(バックアップを同じに戻し、同じ形で書き出し、誤ったものを同じに拒む)、要件12の受入基準1(データベースをそのまま読み書きする)は、同じテストの「ヘッダ」「本文」「Markdown は1文字も違わない」「S3」「メール」「データベース」の場合で確かめる
  - _要件: 4.4, 4.5, 4.6, 9.1, 9.2, 9.3, 10.2, 11.1, 11.2, 11.3, 12.1_
  - _保留: 3.1 と同じ_

- [ ] 3.5 変えた動きの一覧と違いを許す範囲を作る

  Claude は、`backend/compat/changed-behaviors.yaml` に、design.md の変えた動きの一覧の CB-001 から CB-005 の5つの項目を書き、比べる検査が違いを一覧の `match` と照らす処理を作る。Claude は、CB-005 の、JSON で文字を `\uXXXX` の形で書くかどうかの項目を、`match` を持たない記録だけの項目にする。
  - 完了の確かめ方: `run-check.sh backend-go go test -tags compat ./compat/harness/...` が成功する
  - 受入基準とテストの対応: 要件4の受入基準6(一覧に載せた違いでは止めない)と要件9の受入基準5と6(変えた動きの一覧)は、`match_test.go` の `TestMatch_OrderOnlyAllowsReorder`、`TestMatch_OtherOperationNotAllowed`、`TestLoadChangedBehaviors_RequiredFields`、`TestLoadChangedBehaviors_CB005HasNoMatch` で確かめる
  - _要件: 4.6, 9.5, 9.6_
  - _保留: 3.1 と同じ_

- [ ] 3.6 PDF の比べ方を作る (並行可)

  Claude は、`backend/compat/pdfcmp/`(ビルドタグ `compat`)を作る。pdfcmp は、design.md の「pdfcmp」の表の6つを poppler-utils で読んで比べ、語の位置は 2pt、文字の大きさは 0.5pt、表の色は RGB のそれぞれ 2 まで許す。フォントの名前は先頭の6文字の付け足しを除き、ページの文字は「～」(U+FF5E)を「〜」(U+301C)に直してから比べる。
  - 完了の確かめ方: `run-check.sh backend-go go test -tags compat ./compat/pdfcmp/...` が成功する
  - 受入基準とテストの対応: 要件10の受入基準1と4(配置、フォント、文字の大きさ、表の色、改頁の位置を比べる方法と許す違い)は、`pdfcmp_test.go` の `TestCompare_Allows2ptShift`、`TestCompare_Rejects2_5ptShift`、`TestCompare_RejectsOneCharDiff`、`TestCompare_RejectsPageBreakDiff`、`TestCompare_FontSubsetPrefixIgnored`、`TestCompare_TableColorTolerance` で確かめる
  - _要件: 10.1, 10.3, 10.4_
  - _対象の部品: pdfcmp_
  - _保留: 3.1 と同じ_

- [ ] 3.7 比べる経歴書とバックアップと画像の初めのデータを置く

  Claude は、`backend/compat/fixtures/` に、利用者の初めのデータと、`resumes/` の4種類の経歴書(項目が空、職歴と案件が多く3ページ以上、長い文と改行、2つのフォントのそれぞれ)と、バックアップと画像のファイルを置く。どのデータを使うかは、Claude が、まとまりの spec で作る筋書きに書く。
  - 完了の確かめ方: `run-check.sh backend-go go test -tags compat ./compat/harness/...` の `TestFixtures_AllLoadable` が成功する
  - 受入基準とテストの対応: 要件10の受入基準3(いろいろな経歴書のデータで比べる)は、`fixtures_test.go` の `TestFixtures_AllLoadable` と `TestFixtures_ResumeKindsPresent` で確かめる
  - _要件: 10.3_
  - _保留: 3.1 と同じ_

- [ ] 3.8 版をまたぐ確認を作る

  Claude は、`backend/compat/cross_test.go` と harness の版をまたぐ動かし方を作る。この動かし方は、Java 版と Go 版を1つの Postgres と1つの Redis と1つの fakeaws につなぎ、筋書きごとに、Java 版から Go 版へ、Go 版から Java 版へ、2つの版へ交互に、の3つの送り先の組を試し、最後の段でもう一方の版から保存した内容を読む。
  - 完了の確かめ方: `run-check.sh backend-go go test -tags compat -run Cross ./compat/...` が成功する
  - 受入基準とテストの対応: 要件13の受入基準1から4と6(切り替えの間と後に、操作が失敗せず、保存が消えず、ログアウトされず、途中の手順をまたぐ操作を終えられることを、切り替えの前に版をまたいで確かめる)と要件5の受入基準6(戻してもログアウトされず保存が残る)の土台は、`cross_test.go` の `TestCross_SelfPairPasses`(同じイメージを両方の位置に置いた筋書きが通る)、`TestCross_WrongStatusFailsWithStepAndDirection`、`TestCross_ThreeDirectionsRun` で確かめる。10の操作の筋書きは、Claude が、まとまりの spec で足す
  - _要件: 5.6, 13.1, 13.2, 13.3, 13.4, 13.6_
  - _保留: 3.1 と同じ_

- [ ] 3.9 応答の時間の比べ方を作る

  Claude は、`backend/compat/perf_test.go` と harness の時間の動かし方を作る。この動かし方は、20回の測らない要求のあと200回ずつ順に送り、操作ごとに95パーセンタイルを「Go 版 ≤ Java 版 × 1.2 + 20ミリ秒」で比べ、PDF の出力では同時2件のときのメモリの最大が 1792MB 以内かを確かめる。
  - 完了の確かめ方: `run-check.sh backend-go go test -tags compat ./compat/harness/...` の `TestPerfJudge_*` が成功する
  - 受入基準とテストの対応: 要件9の受入基準7(決めた幅で比べる)は、`perf_judge_test.go` の `TestPerfJudge_WithinTolerance`、`TestPerfJudge_ExceedsTolerance`、`TestPerfJudge_MemoryOver1792MBFails` で確かめる
  - _要件: 9.7_
  - _保留: 3.1 と同じ_

- [ ] 3.10 比べる検査の入口と自分を確かめる筋書きを作り、PR を出す

  Claude は、`backend/compat/compat_test.go` に、筋書きを読んで比べる入口と、筋書きに出てくる操作の確認 `TestCoverage_Operations` を作る。この確認は、定数 `requireAllOperations` が `false` の間は、`progress.md` で完了と記した操作がそのまとまりの筋書きに1回以上出てくることを確かめ、`true` のときは、仕様書の50の操作のすべてが筋書きに出てくることを確かめる。この確認は、どちらの値でも必ず動く。Claude は、比べる検査そのものが正しく動くかを確かめる3つの筋書きを作る。1つ目は、同じイメージを両方の位置に置き、違いが0件になる筋書きである。2つ目は、1文字変える偽物を置き、検査が失敗する筋書きである。3つ目は、`match` に当たる違いだけがあり、検査が通る筋書きである。Claude は、`Apply` で作った表を Java 版の Flyway の `validate` が通すことの確認も作る。最後に、Claude は `/verify-backend` と `run-check.sh backend-go make check` と `run-check.sh backend-go make compat` と `make compat-cross` を通して PR を出す。
  - 完了の確かめ方: `make check` と `make compat` と `make compat-cross` が成功し、PR の CI の `backend-compat` と `backend-test` が成功する
  - 受入基準とテストの対応: 要件4の受入基準5から7(比べる検査を作り、違いがあれば止め、一覧に載せた違いでは止めない)は `compat_test.go` の `TestSelf_SameImageNoDiff`、`TestSelf_OneCharFakeFails`、`TestSelf_MatchedDiffPasses` で、要件4の受入基準7(CI で動き続ける)は PR と main の CI の `backend-compat` の結果で、要件12の受入基準4(履歴の続きとして変える)は `TestApply_JavaFlywayValidatePasses` で、要件9の受入基準1(すべての操作を比べる)の土台は `TestCoverage_Operations` と、その判定の関数の単体テスト `TestCoverageJudge_CompletedOnly` と `TestCoverageJudge_All50` で確かめる
  - _要件: 4.5, 4.6, 4.7, 9.1, 12.4_
  - _保留: 3.1 と同じ_

- [ ] 4. API の説明画面と開発の手順の文書を入れる(PR 2-4)
- [ ] 4.1 開発環境の API の説明画面を作る

  Claude は、digest で固定した `swaggerapi/swagger-ui` をもとにする `docker/api-docs/Dockerfile` を作る。Claude は、`compose.yaml` にサービス `api-docs` を作り、このサービスをホストの 8082 につなぎ、`backend/api/openapi.yaml` を読み取りだけで差し込み、`SWAGGER_JSON=/spec/openapi.yaml` を渡す。Claude は、`start-dev.sh` に `api-docs` を足す。仕様書の `servers` は `http://localhost:8081` にする。
  - 完了の確かめ方: `docker compose up -d api-docs` のあと、`curl -s http://localhost:8082/` が Swagger UI の HTML を返し、`curl -s http://localhost:8082/openapi.yaml` が仕様書を返す
  - 受入基準とテストの対応: 要件14の受入基準1(開発環境で開ける)は、`curl` の2つの応答で確かめる。要件14の受入基準3(本番で開けない)は、2.8 の `TestUnknownRouteReturns404` で確かめてある
  - _要件: 14.1, 14.3_
  - _保留: PR 2-3 が main に入ったあと、所有者が `/kiro-impl backend-go-replacement` を打った会話で、Claude が大タスク4を行う_

- [ ] 4.2 開発の手順の文書に URL を書き、PR を出す

  Claude は、`doc/開発フロー/参加者セットアップ手順.md` に、API の説明画面の URL `http://localhost:8082` と、Go 版の開発サーバの URL `http://localhost:8081` を書く。最後に、Claude は、`start-dev.sh` で開発環境を起動し、`backend-go` の `/healthz` と `api-docs` が応答することを確かめて PR を出す。
  - 完了の確かめ方: 文書に2つの URL があり、`start-dev.sh` で起動した開発環境で `curl -s http://localhost:8081/healthz` が `{"status":"UP"}` を返す
  - 受入基準とテストの対応: 要件14の受入基準4(URL を文書に書く)は、テストでなく、文書の本文で確かめる
  - _要件: 14.4_
  - _保留: 4.1 と同じ_

- [ ] 5. Go のファイルがあることを前提にするゲート設定を Go 版に対応させる(PR 2-5)
- [ ] 5.1 Dependabot に gomod と比べる検査の Dockerfile を足す

  Claude は、`.github/dependabot.yml` に gomod の項目(`/backend`)を足し、docker の項目の `directories` に `/backend/compat/fakeaws` と `/backend/compat/fakeoidc` を足した完成版を、置き場に作る。`docker/backend-go/` と `docker/api-docs/` は、今の `/docker/*` に当たるので足さない。Claude は、docker の項目の `open-pull-requests-limit` 10 で足りるかを、Dependabot の公式の文書で上限の意味を読んで決め、決めた結果と根拠の URL を PR の本文に書く。これは、design の審査で D3-2-2 として残った問いへの答えである。
  - 完了の確かめ方: 検査用の写しで、置き場の `dependabot.yml` を、版を固定した `mikefarah/yq` のイメージで読み、gomod の項目と docker の項目の `directories` の2つのフォルダが出る
  - 受入基準とテストの対応: 要件3の受入基準6(Go 版の部品の版を上げる PR を作る)と要件1の受入基準7(Java 版の項目を今のとおり続ける)は、テストでなく、置いたあとの `dependabot.yml` の項目と、Dependabot の画面で gomod の更新の確認が動いたことで確かめる
  - _要件: 1.7, 3.6_
  - _保留: PR 2-4 が main に入ったあと、所有者が `/kiro-impl backend-go-replacement` を打った会話で、Claude が大タスク5を行う_

- [ ] 5.2 イメージの検査に Go 版の本番のイメージを足す (並行可)

  Claude は、`.github/workflows/container-scan.yaml` と `container-scan-scheduled.yaml` に、`docker/backend-go/Dockerfile.prod` から組み立てたイメージを Trivy で調べる仕事を足した完成版を、置き場に作る。
  - 完了の確かめ方: 検査用の写しで、actionlint と `check-action-pinning.sh` と `test-check-container-scan.sh` が成功する
  - 受入基準とテストの対応: 要件3の受入基準1(本番のイメージの脆弱性の検査)は、`test-check-container-scan.sh` に足す「backend-go のイメージの結果を読む」の場合で確かめる
  - _要件: 3.1_
  - _対象の部品: CodeQL とイメージの検査と組み立てて動かす検査_
  - _保留: 5.1 と同じ_

- [ ] 5.3 脆弱性を直す仕組みに Go の仕事を足す (並行可)

  Claude は、`.github/workflows/backend-vuln-fix.yaml` と `.github/scripts/backend-vuln-fix.sh` に、毎日 `make vuln` を動かし、呼ばれる箇所のある脆弱性を直す PR を作る Go の仕事を足した完成版を、置き場に作る。Go の仕事は、部品の脆弱性を、`go get <モジュール>@<直した版>` と `go mod tidy` で直す。Go の仕事は、標準ライブラリの脆弱性を、`go.mod` の `toolchain` と、`docker/backend-go/` と `backend/compat/fakeaws/` と `backend/compat/fakeoidc/` の `golang` のイメージの版を1つの PR で上げて直す。上げる Dockerfile は、`docker/backend-go/` の `Dockerfile` と `Dockerfile.prod` と、fakeaws と fakeoidc の `Dockerfile` の4つである。
  - 完了の確かめ方: 検査用の写しで、`test-backend-vuln-fix.sh` と actionlint が成功する
  - 受入基準とテストの対応: 要件3の受入基準6(Go 版の部品の脆弱性を直す PR を作る)は、`test-backend-vuln-fix.sh` に足す「Go の部品の脆弱性で go get の PR を作る」「標準ライブラリの脆弱性で toolchain と4つの Dockerfile を上げる」「呼ばれる箇所の無い脆弱性では PR を作らない」の場合で確かめる
  - _要件: 3.6_
  - _対象の部品: Dependabot と公開の時刻の検査と脆弱性の直し_
  - _保留: 5.1 と同じ_

- [ ] 5.4 週次の変異テストの報告に Go 版を足す (並行可)

  Claude は、`.github/workflows/mutation-report.yaml` と `.github/scripts/record-mutation-metrics.sh` に、`make mutation-full` の JSON の報告を週次で集める処理を足した完成版を、置き場に作る。
  - 完了の確かめ方: 検査用の写しで、`test-record-mutation-metrics.sh` と actionlint が成功する
  - 受入基準とテストの対応: 要件3の受入基準1(変異テスト)は、`test-record-mutation-metrics.sh` に足す「gremlins の報告から割合を読む」の場合で確かめる
  - _要件: 3.1_
  - _保留: 5.1 と同じ_

- [ ] 5.5 週次のカバレッジの集計に Go 版を足す (並行可)

  Claude は、`.github/scripts/collect-coverage.sh` に、Go 版の `coverage.out` から文の割合を集める処理を足した完成版を、置き場に作る。
  - 完了の確かめ方: 検査用の写しで、`test-collect-coverage.sh` が成功する
  - 受入基準とテストの対応: 要件3の受入基準1(カバレッジ)は、`test-collect-coverage.sh` に足す「Go の coverage.out から文の割合を出す」の場合で確かめる
  - _要件: 3.1_
  - _保留: 5.1 と同じ_

- [ ] 5.6 所有者に置いてもらい、ゲート設定のテストをすべて流して PR を出す

  Claude は、実装のメモの「所有者に置いてもらう」のとおりに、置き場のファイルを所有者に本来の場所へ置いてもらったあと、`.github/scripts/tests/` のテストを Linux のコンテナで流し、shellcheck v0.11.0 と actionlint を流す。
  - 完了の確かめ方: すべてのテストと shellcheck と actionlint が成功し、PR の本文に「承認が要る理由」と「main に入れたときに本番で起きること」の欄がある
  - 受入基準とテストの対応: 要件7の受入基準3(承認が要る理由と、main に入れたときに本番で起きることを示す)は、`gh pr view` で読んだ PR の本文で確かめる
  - _要件: 7.3_
  - _保留: 5.1 と同じ_

- [ ] 6. 切り替えの出荷より前に入れる本番の設定の変更を入れる(PR 4-1)
- [ ] 6.1 タスク定義と Redis の秘密の値に Go 版が読む値を足し、PR を出す

  Claude は、`terraform/modules/ecs/main.tf` のタスク定義に環境変数 `KEIREKIPRO_ENV=prod` を足し、`terraform/main.tf` の `keirekipro/redis` の秘密の値にキー `redis-username` を足す。Java 版が読む値は変えない。Claude は `/verify-terraform` を通して PR を出す。PR 4-1 は terraform のファイルだけを変えるので、所有者の承認を待たずに、品質チェックに通ると main に入る。本番の設定は、main に入っただけでは変わらない。

  PR の CI は `terraform plan` を動かさないので、Claude は、PR の本文と所有者への返事に、次の3つを書く。

    - 1つ目は、PR が main に入ったあと、所有者が `terraform-apply.yaml` を `plan_only` にチェックを付けて動かすことと、うまくいったときに実行の概要に「本番には適用していません」が出ることである
    - 2つ目は、その実行の plan の差分で変わるはずのリソースと値である。変わるはずのものは、タスク定義の環境変数 `KEIREKIPRO_ENV` の追加と、`keirekipro/redis` のキー `redis-username` の追加の2つである
    - 3つ目は、Claude がその実行の記録を確かめたあとに、所有者が `plan_only` を付けずに `terraform-apply.yaml` を動かすことと、反映されたかの見分け方(`keirekipro/redis` に `redis-username` がある)である

  所有者が `plan_only` で動かしたあと、Claude は、`gh run view --log` でその実行の「Terraform Plan (差分の事前表示)」の記録を読み、plan の差分が PR の本文に書いたリソースと値だけであることを所有者に示す。
  - 完了の確かめ方: `/verify-terraform` が成功し、`git diff origin/main -- terraform/` の差分が、環境変数1つと秘密の値のキー1つの追加だけで、PR の本文に plan で変わるはずのリソースと値がある
  - 受入基準とテストの対応: 要件5の受入基準1(Java 版のままでも動く形で先に入れる)は、`git diff origin/main -- terraform/` の差分と、`plan_only` で動かした `terraform-apply.yaml` の plan の差分に、Java 版が読む値の変更と削除が無いことで確かめる
  - _要件: 5.1_
  - _保留: 5つのまとまりの spec の PR がすべて main に入り、progress.md の5つのまとまりの状態が「比べる検査に通った」になったあと、所有者が `/kiro-impl backend-go-replacement` を打った会話で、Claude が大タスク6を行う_

- [ ] 7. 出荷の版の選び方と切り替えの手順書を入れる(PR 4-2)
- [ ] 7.1 出荷する版を決めるスクリプトを作る

  Claude は、`.github/scripts/backend-deploy-impl.sh` とそのテストを、置き場に作る。このスクリプトは、入力 `current` `java` `go` と、今のタスク定義のイメージのタグを受け取り、版と、Dockerfile と、組み立ての文脈 `./backend` と、イメージのタグを返す。返すイメージのタグは、Java 版ではコミットの SHA、Go 版では `go-<SHA>` である。`current` では、タグが `go-` で始まれば Go 版、そうでなければ Java 版にする。
  - 完了の確かめ方: 検査用の写しで、`test-backend-deploy-impl.sh` が成功する
  - 受入基準とテストの対応: 要件5の受入基準2(1回の出荷で切り替えと戻し)は、`test-backend-deploy-impl.sh` の「go を選ぶと Go 版の Dockerfile と go- のタグ」「java を選ぶと Java 版の Dockerfile と SHA のタグ」の場合で、要件1の受入基準3と4(切り替えるまでは Java 版のまま出荷が成功する)と要件5の受入基準7(失敗したら Java 版のまま)は「current で今のタグが SHA なら Java 版」「current で今のタグが go- なら Go 版」の場合で確かめる
  - _要件: 1.3, 1.4, 5.2, 5.7_
  - _保留: Claude は、大タスク7を、所有者が PR 4-1 を本番に反映したあとに、所有者が `/kiro-impl backend-go-replacement` を打った会話で行う。PR 4-1 の反映では、Claude が `plan_only` の実行の差分を照らした結果を所有者に示し、そのあと所有者が `plan_only` のチェックを外して `terraform-apply.yaml` を動かす_

- [ ] 7.2 出荷のワークフローに入力 backend_impl を足す

  Claude は、`.github/workflows/release.yaml` と `backend-deploy.yaml` の完成版を、置き場に作る。`release.yaml` は、入力 `backend_impl` を受け取り、`backend-deploy.yaml` に渡す。`backend_impl` の既定の値は `current` である。`backend-deploy.yaml` は、最初のステップで `aws ecs describe-task-definition` を動かして今のタスク定義を読み、タスク7.1の `backend-deploy-impl.sh` で版を決め、決めた版をワークフローの要約に書く。そのあとの4つのステップは変えない。
  - 完了の確かめ方: 検査用の写しで、actionlint と `check-action-pinning.sh` と `node .github/scripts/tests/test-release-gate.mjs` が成功する
  - 受入基準とテストの対応: 要件5の受入基準2(1回の出荷で切り替えと戻しができる)と要件1の受入基準4(どの PR のあとでも出荷が成功する)は、actionlint が通る2つのワークフローで入力が渡ることと、タスク7.1の `test-backend-deploy-impl.sh` で確かめる
  - _要件: 1.3, 1.4, 5.2_
  - _保留: 7.1 と同じ_

- [ ] 7.3 切り替えの手順書を書く (並行可)

  Claude は、`.kiro/specs/backend-go-replacement/runbook.md` に、切り替え、Java 版に戻す、もう一度切り替える、の3つの場面ごとに、design.md の「runbook.md」の5つの操作を、押す場所か打つコマンドと、うまくいったかの見分け方と一緒に書く。Claude は、要件5の受入基準3で決めた出荷の時間帯と、出荷を 20:00 の30分前までに終えることも、runbook.md に書く。Claude は、操作1(段階4の本番の設定の変更の反映)を、design.md の「段階ごとの PR」に書いた `terraform-apply.yaml` の2回の起動の手順のとおりに、`plan_only` にチェックを付けた1回目と、チェックを外した2回目に分けて書く。
  - 完了の確かめ方: runbook.md に3つの場面と5つの操作があり、操作ごとに見分け方があり、操作1に1回目と2回目の起動がある
  - 受入基準とテストの対応: 要件5の受入基準3と4(切り替えの手順書を作り、出荷の時刻を所有者が選ぶ)と要件7の受入基準1(所有者がする6つの操作)は、テストでなく、runbook.md の本文で確かめる。手順書は文書なので、テストは無い
  - _要件: 5.3, 5.4, 7.1_
  - _対象の部品: runbook.md_
  - _保留: 7.1 と同じ_

- [ ] 7.4 所有者に置いてもらい、テストを流して PR を出す

  Claude は、実装のメモの「所有者に置いてもらう」のとおりに、置き場のファイルを所有者に本来の場所へ置いてもらったあと、`.github/scripts/tests/` のテストを Linux のコンテナで流し、shellcheck と actionlint を流して PR を出す。
  - 完了の確かめ方: すべてのテストと shellcheck と actionlint が成功し、PR の本文に「承認が要る理由」と「main に入れたときに本番で起きること」(入力の既定が `current` なので、出荷しても今の版のまま)の欄がある
  - 受入基準とテストの対応: 要件7の受入基準3(承認が要る理由と、main に入れたときに本番で起きることを示す)は、`gh pr view` で読んだ PR の本文で確かめる
  - _要件: 7.3_
  - _保留: 7.1 と同じ_

- [ ] 8. 50の操作の確認を必須にし、応答の時間を測る(PR 4-3)
- [ ] 8.1 50の操作がすべて筋書きに出てくることを必須にする

  Claude は、タスク3.10で作った定数 `requireAllOperations` を `true` にする。Claude は、`TestCoverage_Operations` に、design.md の「cross」の10の操作がそれぞれ `modes` に `cross` を持つ筋書きに出てくることと、design.md の「perf」の11の操作がそれぞれ `modes` に `perf` を持つ筋書きに出てくることの確認を足す。足りない筋書きがあれば、Claude は、その筋書きを足す。
  - 完了の確かめ方: `run-check.sh backend-go go test -tags compat -run TestCoverage ./compat/...` が成功する
  - 受入基準とテストの対応: 要件9の受入基準1(画面が使うすべての操作を同じにする)は `TestCoverage_Operations` で、要件13の受入基準6(切り替えの前に版をまたぐ確認がある)と要件9の受入基準7(決めた操作の時間を比べる)の筋書きがそろっていることは、判定の関数の単体テストに足す `TestCoverageJudge_CrossOperationsMissing` と `TestCoverageJudge_PerfOperationsMissing` で確かめる
  - _要件: 9.1, 9.7, 13.6_
  - _保留: PR 4-2 が main に入ったあと、所有者が `/kiro-impl backend-go-replacement` を打った会話で、Claude が大タスク8を行う_

- [ ] 8.2 応答の時間を測り、幅を超えた操作を直す

  Claude は、`run-check.sh backend-go make compat-perf` を動かし、11の操作の95パーセンタイルと、PDF の同時2件のメモリの最大と、起動の時間を `progress.md` に書く。幅を超えた操作があれば、Claude は、要件9の受入基準7のとおりに Go 版を直して測り直し、直せなければ操作と測った値を所有者に報告する。メモリが 1792MB を超えたら、PDF の同時の数を1に下げて測り直し、それでも超えたら所有者に報告する。
  - 完了の確かめ方: `make compat-perf` が成功し、progress.md に測った値の表がある
  - 受入基準とテストの対応: 要件9の受入基準7(主な操作の応答の時間を Java 版と比べ、決めた幅に収める)は、`perf_test.go` の `TestPerf_AllOperationsWithinTolerance`、`TestPerf_PDFMemoryWithin1792MB` で確かめる
  - _要件: 9.7_
  - _保留: 8.1 と同じ_

- [ ] 8.3 品質チェックと比べる検査を通し、変えた動きの一覧と手順書を所有者に示して PR を出す

  Claude は、`/verify-backend` と `run-check.sh backend-go make check` と `make compat` と `make compat-cross` を通して PR を出す。Claude は、PR を出したときの返事で、`changed-behaviors.yaml` の全体と runbook.md を所有者に示す。
  - 完了の確かめ方: `make check` と `make compat` と `make compat-cross` が成功し、PR の CI の `backend-test` が成功する
  - 受入基準とテストの対応: 要件9の受入基準6(切り替えの前に一覧を見られる)は、テストでなく、所有者への返事に一覧の全体を載せたことで確かめる
  - _要件: 9.6_
  - _保留: 8.1 と同じ_

- [ ] 9. 本番の切り替えを確かめて記録する(段階5)
- [ ] 9.1 切り替えの出荷の結果を確かめて所有者に報告する

  Claude は、所有者が会話で「切り替えた」と書いたら、`gh run view` で出荷の結果を読み、`aws ecs describe-services` と `describe-task-definition` で動いているタスクのイメージのタグが `go-` で始まることを確かめ、CloudWatch Logs の `/ecs/keirekipro-backend` で出荷のあとの Go 版のログに 5xx の行が無いかを読む。Claude は、確かめた結果と、所有者が画面で確かめる操作(runbook.md の操作4)を、1つの返事で示す。AWS を読む権限が無いときは、所有者に打つコマンドを1つずつ示す。
  - 完了の確かめ方: 所有者への返事に、出荷の結果、タスクのイメージのタグ、5xx の行の有無、画面で確かめる操作がある
  - 受入基準とテストの対応: 要件5の受入基準5(切り替えの出荷の結果を確かめて所有者に報告する)は、テストでなく、所有者への返事で確かめる
  - _要件: 5.5_
  - _保留: 所有者が runbook.md のとおりに切り替えの出荷をして、会話で「切り替えた」と書いたあと、Claude が大タスク9を行う_

- [ ] 9.2 進み具合の表を「本番で動いている」にして PR を出す

  Claude は、所有者が画面での確認を終えたと書いたら、`progress.md` の5つのまとまりの状態を「本番で動いている」にし、段階5の終えた日を書いて PR を出す。
  - 完了の確かめ方: progress.md の5つのまとまりが「本番で動いている」で、PR が main に入る
  - 受入基準とテストの対応: 要件7の受入基準4(まとまりごとの進み具合を1か所で見られる)は、テストでなく、progress.md の本文で確かめる
  - _要件: 7.4_
  - _保留: 9.1 と同じ_

- [ ] 10. Java 版のコードと、Java 版と Go 版を比べる検査を消し、開発環境の名前を戻す(PR 6-1)
- [ ] 10.1 Java 版を消してよいかを所有者に尋ねる

  Claude は、切り替えの出荷から7日以上たったら、要件6の受入基準1で決めた尋ね方のとおりに、Java 版を消してよいかを所有者に尋ね、Go 版で見つかった不具合を Issue の一覧で示す。所有者が「まだ」と答えたら、Claude は大タスク10を進めない。
  - 完了の確かめ方: 所有者が会話で「Java 版を消してよい」と答えている
  - 受入基準とテストの対応: 要件6の受入基準1(所有者が消してよいと答えるまで Java 版を消さない)は、テストでなく、所有者への問いと答えで確かめる
  - _要件: 6.1_
  - _保留: 大タスク9の PR が main に入り、切り替えの出荷から7日以上たったあと、所有者が `/kiro-impl backend-go-replacement` を打った会話で、Claude が大タスク10を行う_

- [ ] 10.2 マイグレーションとフォントを新しい場所に写し、Go 版の起動を Apply にする

  Claude は、マイグレーションのファイルを `backend/db/migrations/` に、フォントを `backend/assets/fonts/` に写し、`migrations.go` と `sqlc.yaml` と `docker/backend-go/Dockerfile.prod` が読む場所を直し、Go 版の起動を `Apply` にする。写す元の `backend/src/main/resources/` のファイルは、タスク10.3で Java 版のコードと一緒に消す。
  - 完了の確かめ方: `run-check.sh backend-go go test ./internal/platform/migrate/... ./cmd/keirekipro/...` と `docker build -f docker/backend-go/Dockerfile.prod backend` が成功する
  - 受入基準とテストの対応: 要件12の受入基準4(履歴の続きとして表の形を変える)は、`migrate_integration_test.go` に足す `TestApply_EmptyDBThenValidate` と、`main_test.go` の `TestRun_UsesApplyMode` で確かめる
  - _要件: 12.4_
  - _保留: 10.1 と同じ_

- [ ] 10.3 Java 版のコードと、Java 版と Go 版を比べる検査を消す

  Claude は、Java 版のコード、Gradle の設定と wrapper、`docker/backend/`、ArchUnit のテスト、`backend/compat/` を消す。Claude は、消す前に、`backend/compat/changed-behaviors.yaml` を `.kiro/specs/backend-go-replacement/changed-behaviors.yaml` に移す。design.md の「消す一覧」の冒頭に書いた、Java 版と一緒に消えるもの(`backend/.vscode/`、`backend/.gitignore` の Spring Initializr の行、Gradle の Flyway のプラグイン、PMD と OpenTelemetry の設定)も消す。作業を終えるときの確認のフックが Java 版の品質チェックの記録を求めたら、Claude は、Java 版のコードを消したので Java 版の品質チェックを動かせないことを、報告に書く。
  - 完了の確かめ方: `git ls-files backend | grep -E '\.java$|gradle|compat/'` が何も返さず、changed-behaviors.yaml が spec のフォルダにあり、`run-check.sh backend-go make check` が成功する
  - 受入基準とテストの対応: 要件6の受入基準2(Java 版のコードを消す)は、`git ls-files` の結果で確かめる。ArchUnit のテストと Gradle の設定を消すのは所有者の承認が要る変更なので、Claude は、タスク10.9で、PR の本文の「承認が要る理由」にこのことを書く
  - _要件: 6.2_
  - _保留: 10.1 と同じ_

- [ ] 10.4 開発環境の名前と確認の経路を戻し、verify のスキルを Go 版だけにする

  Claude は、`docker/backend-go/` を `docker/backend/` に、compose の `backend-go` を `backend` に、`run-check.sh` の `backend-go` を `backend` に戻し、`run-check.sh` の `/repo` の差し込みを消す。Claude は、`start-dev.sh`、`.claude/scripts/parallel/ui.sh`、`tests/test-ui.sh`、`verify-ui` のスキルの確認の経路を `/healthz` に替える。Claude は、`verify-backend` と `verify-all` のスキルの backend の手順を、`bash .claude/scripts/parallel/run-check.sh backend make check` の1つだけにする。スキルを言語に依存しない書き方にするのは、大タスク13で行う。
  - 完了の確かめ方: `bash .claude/scripts/parallel/tests/test-run-check.sh` と `bash .claude/scripts/parallel/tests/test-ui.sh` と `run-check.sh backend make check` が成功し、2つのスキルの本文に Gradle のコマンドが無い
  - 受入基準とテストの対応: 要件6の受入基準3(Go 版だけで今のとおりに動く)は、`test-run-check.sh` の「backend の領域で make check を動かす」と `test-ui.sh` の「/healthz で起動を確かめる」の場合で確かめる
  - _要件: 6.3_
  - _保留: 10.1 と同じ_

- [ ] 10.5 CI の仕事と作業を終えるときの確認のフックを Go 版だけにする

  Claude は、次の完成版を置き場に作る。Claude は、`ci.yaml` から、見分け `backend_java` と `backend_compat` と、仕事 `backend-java` と `backend-compat` を消し、`backend-test` が見る仕事を `backend-go` だけにし、`docker-smoke` の分岐の Dockerfile と、見分け `backend_go` の `docker/backend-go/**` を、`docker/backend/` の下に替える。Claude は、見分け `backend_go` のマイグレーションのファイルの形を、タスク10.2で移した `backend/db/migrations/**` に替える。Claude は、見分け `backend_go` から、`backend/go.mod` があることの条件を消す。`backend-test-verdict.sh` とそのテストは、`backend-go` の結果だけで判定する形にする。`check-verify-before-stop.sh` とそのテストは、`backend/` の下の変更に Go 版の記録だけを求める形に戻す。
  - 完了の確かめ方: 検査用の写しで、actionlint と `check-action-pinning.sh` と `test-backend-test-verdict.sh` と `test-check-verify-before-stop.sh` が成功し、`ci.yaml` の見分け `backend_go` に `backend/db/migrations/**` と `docker/backend/**` と `backend/assets/**` がある
  - 受入基準とテストの対応: 要件6の受入基準2と3(Java 版だけが使っていた品質チェックと CI の設定を消し、Go 版だけで今のとおりに動く)は、`test-backend-test-verdict.sh` の「backend-go だけを見る」の場合と、`test-check-verify-before-stop.sh` の「backend の変更に Go 版の記録を求める」の場合で確かめる
  - _要件: 6.2, 6.3_
  - _保留: 10.1 と同じ_

- [ ] 10.6 依存のグラフと必須の検査を Go 版に替える

  Claude は、次の完成版を置き場に作る。`dependency-review.yaml` の仕事 `dependency-graph-generate` と `dependency-graph-submit` と、`dependency-graph.yaml` の main への push の送信を、次のように替える。`dependency-graph-generate` は `go mod verify` に、`dependency-graph-submit` と main への push の送信は `actions/go-dependency-submission` v2.0.3(`go-mod-path: backend/go.mod`、`go-build-target: backend/cmd/keirekipro/main.go`)に替える。`guardrails.yaml` から `gradle-wrapper` の仕事を消し、`check-gradle-wrapper.sh` とそのテストを消す。`.github/audit/required-checks.json` から `gradle-wrapper` の行を消す。
  - 完了の確かめ方: 検査用の写しで、actionlint と `check-action-pinning.sh` と `test-check-audit-skipped-required.sh` が成功し、`guardrails.yaml` に `gradle-wrapper` の仕事が無く、`required-checks.json` に `gradle-wrapper` の行が無く、`check-gradle-wrapper.sh` とそのテストが無い
  - 受入基準とテストの対応: 要件6の受入基準2(Java 版だけの品質チェックを消す)は、完了の確かめ方に書いた `guardrails.yaml` と `required-checks.json` と `check-gradle-wrapper.sh` の3つの確かめの結果と、`test-check-audit-skipped-required.sh` が今の期待一覧で成功することで確かめる
  - _要件: 6.2_
  - _保留: 10.1 と同じ_

- [ ] 10.7 Dependabot と脆弱性の直しとイメージの検査と週次の報告から Java 版の分を消す

  Claude は、次の完成版を置き場に作る。`dependabot.yml` から、`gradle` の項目と、docker の項目の `backend/compat/` の2つのフォルダを消す。`backend-vuln-fix.yaml` と `backend-vuln-fix.sh` から Java 版の仕事を消し、Go の仕事が `golang` のイメージの版を上げる場所を `docker/backend/` の2つの Dockerfile だけにする。これは、design の審査で D3-3-1 として残った、`backend-vuln-fix` が版を上げる場所の一覧への答えである。`container-scan` の2つのワークフローと `mutation-report.yaml` と `record-mutation-metrics.sh` と `collect-coverage.sh` から、Java 版の分を消す。`container-scan` の2つのワークフローの Go 版の仕事が読む Dockerfile は、変更の見分けと組み立ての指定の両方で `docker/backend/Dockerfile.prod` に替える。
  - 完了の確かめ方: 検査用の写しで、actionlint と、`test-backend-vuln-fix.sh` と `test-check-container-scan.sh` と `test-record-mutation-metrics.sh` と `test-collect-coverage.sh` が成功し、`git grep -n compat/fake -- .github` が何も返さず、`dependabot.yml` に `gradle` の項目が無い
  - 受入基準とテストの対応: 要件6の受入基準2(Java 版だけが使っていた品質チェックと CI の設定を消す)は、`test-backend-vuln-fix.sh` の「標準ライブラリの脆弱性で docker/backend の2つの Dockerfile を上げる」の場合と、`git grep` の結果で確かめる
  - _要件: 6.2_
  - _保留: 10.1 と同じ_

- [ ] 10.8 出荷のワークフローから版の選び方を消す

  Claude は、`release.yaml` と `backend-deploy.yaml` から入力 `backend_impl` と版の見分けを消し、組み立てる Dockerfile を `docker/backend/Dockerfile.prod` にした完成版を、置き場に作る。Claude は、`backend-deploy-impl.sh` とそのテストを消す。
  - 完了の確かめ方: 検査用の写しで、actionlint と `check-action-pinning.sh` と `node .github/scripts/tests/test-release-gate.mjs` が成功し、`git grep -n backend_impl -- ':!.kiro/specs/'` が何も返さない
  - 受入基準とテストの対応: 要件6の受入基準2(出荷の設定から Java 版の分を消す)は、`git grep` の結果と actionlint で確かめる
  - _要件: 6.2_
  - _保留: 10.1 と同じ_

- [ ] 10.9 所有者に置いてもらい、品質チェックを通して PR を出す

  Claude は、実装のメモの「所有者に置いてもらう」のとおりに、置き場のファイルを所有者に本来の場所へ置いてもらったあと、`.github/scripts/tests/` と `.claude/` のテストを Linux のコンテナで流し、shellcheck と actionlint と `/verify-backend` と `run-check.sh backend make check` を通す。PR の本文の「承認が要る理由」に、GitHub の ruleset から `gradle-wrapper` を外す操作と、画面で押す場所と、外せたかの見分け方を書く。
  - 完了の確かめ方: すべてのテストと `make check` が成功し、`git grep -n docker/backend-go -- ':!.kiro/specs/'` が何も返さず、所有者が ruleset から `gradle-wrapper` を外したあと、PR の必須の検査がすべて成功する
  - 受入基準とテストの対応: 要件6の受入基準3(Java 版を消したあとも、Go 版だけで今のとおりに動く)は `make check` と PR の CI の結果で、要件7の受入基準2と3(所有者に頼む操作と理由)は `gh pr view` で読んだ PR の本文で確かめる
  - _要件: 6.3, 7.2, 7.3_
  - _保留: 10.1 と同じ_

- [ ] 11. 段階6の本番の設定の変更を入れる(PR 6-2)
- [ ] 11.1 タスク定義と ALB と Redis の秘密の値から Java 版の値を消し、PR を出す

  Claude は、`terraform/modules/ecs/main.tf` から `SPRING_PROFILES_ACTIVE` と `JAVA_TOOL_OPTIONS` を消し、コンテナのヘルスチェックのパスを `/healthz` にする。Claude は、`terraform/modules/alb/` のターゲットグループのヘルスチェックのパスを `/healthz` にし、`terraform/main.tf` の `keirekipro/redis` から `spring.data.redis.*` のキーを消す。Claude は `/verify-terraform` を通して PR を出す。反映されたかの見分け方は、`aws elbv2 describe-target-groups` で読んだターゲットグループのヘルスチェックのパスが `/healthz` であることである。PR 6-2 は、PR 4-1 と同じく terraform のファイルだけを変えるので、所有者の承認を待たずに、品質チェックに通ると main に入る。

  Claude は、PR の本文と所有者への返事に、タスク6.1と同じ形で、次の3つを書く。

    - 1つ目は、所有者が `terraform-apply.yaml` を `plan_only` で動かすことである
    - 2つ目は、plan で変わるはずのリソースと値であり、design.md の「本番の設定の値の変わり方」の表の段階6の列のとおりである
    - 3つ目は、Claude がその実行の記録を確かめたあとに、所有者が `plan_only` を付けずに `terraform-apply.yaml` を動かすことである

  所有者が `plan_only` で動かしたあと、Claude は、`gh run view --log` でその実行の plan の差分を読み、PR の本文に書いたリソースと値だけであることを所有者に示す。
  - 完了の確かめ方: `/verify-terraform` が成功し、`git diff origin/main -- terraform/` の差分が design.md の「本番の設定の値の変わり方」の表の段階6の列と一致し、PR の本文に plan で変わるはずのリソースと値がある
  - 受入基準とテストの対応: 要件6の受入基準2(本番の設定から Java 版の分を消し、所有者が反映する)は、`git diff origin/main -- terraform/` の差分と、`plan_only` で動かした `terraform-apply.yaml` の plan の差分で確かめる
  - _要件: 6.2_
  - _保留: PR 6-1 が main に入ったあと、所有者が `/kiro-impl backend-go-replacement` を打った会話で、Claude が大タスク11を行う_

- [ ] 12. Go 版の /actuator/health を消す(PR 6-3)
- [ ] 12.1 /actuator/health を呼ぶ設定が無いことを確かめてから消し、PR を出す

  Claude は、`git grep -n 'actuator/health' -- ':!.kiro/specs/'` を動かし、その経路を呼ぶ設定とスクリプトが残っていないことを確かめる。残ってよいのは、Java と Spring を前提にした記述を書き換える PR 6-4 で書き換える文書の行だけである。Claude は、`internal/httpapi/health.go` から `/actuator/health` を消し、`/healthz` だけにする。Claude は、`/verify-backend` と `run-check.sh backend make check` を通して PR を出す。
  - 完了の確かめ方: `git grep` の結果が文書の行だけで、`make check` が成功する
  - 受入基準とテストの対応: 要件6の受入基準3(Go 版だけで今のとおりに動く)は、`health_test.go` の `TestHealth_ActuatorPathRemoved`(`/actuator/health` に 404)と `TestHealth_UpAndDown` で確かめる
  - _要件: 6.3_
  - _保留: Claude は、大タスク12を、所有者が PR 6-2 を本番に反映したあとに、所有者が `/kiro-impl backend-go-replacement` を打った会話で行う。PR 6-2 の反映では、Claude が `plan_only` の実行の差分を照らした結果を所有者に示し、そのあと所有者が `plan_only` のチェックを外して `terraform-apply.yaml` を動かす_

- [ ] 13. Java と Spring を前提にした記述を書き換える(PR 6-4)
- [ ] 13.1 言語を書いてよい文書を Go 版に合わせて書き直す (並行可)

  Claude は、`README.md`、`backend/CLAUDE.md` と `backend/` の中のほかの説明、`.kiro/steering/tech.md`、`doc/` の設計図(`DB設計/` `インフラ設計/` `クラス図/` `シーケンス図/` `モデル図/` `ログ設計/`)を、Go 版の作りに合わせて書き直す。Java 版のクラス図は、Go 版のパッケージの図に替える。
  - 完了の確かめ方: 書き直した文書に Java 版の作りの記述が残っていない
  - 受入基準とテストの対応: 要件15の受入基準1と2(Java と Spring を前提にした記述を書き換え、言語を書いてよい文書を限る)は、テストでなく、タスク13.4の語の検査の結果と文書の本文で確かめる
  - _要件: 15.1, 15.2_
  - _対象の部品: 段階6の削除と書き換え_
  - _保留: PR 6-3 が main に入ったあと、所有者が `/kiro-impl backend-go-replacement` を打った会話で、Claude が大タスク13を行う_

- [ ] 13.2 言語に依存しない書き方にする文書を書き換える (並行可)

  Claude は、ルートの `CLAUDE.md` と `REVIEW.md`、スキル(`verify-backend` `verify-all` `verify-ui` `kiro-impl` `retrospective` `goal-fix-tests` `vuln-watch`)、`.kiro/settings/rules/spec-writing.md` と `owner-writing.md`、`.kiro/settings/templates/specs/design.md`、`.kiro/steering/structure.md` と `product.md`、`doc/開発フロー/` の4つの手順書から、言語と道具の名前を消し、「backend の品質チェック」「backend の変異テスト」のように書く。spec-writing.md の「`./gradlew check`」の例も、言語に依存しない例に替える。
  - 完了の確かめ方: 書き換えた文書に、語の一覧の語が残っていない
  - 受入基準とテストの対応: 要件15の受入基準3(ルートの CLAUDE.md、スキル、手順書を言語に依存しない書き方にする)は、テストでなく、タスク13.4の語の検査の結果で確かめる
  - _要件: 15.3_
  - _対象の部品: 段階6の削除と書き換え_
  - _保留: 13.1 と同じ_

- [ ] 13.3 設定とスクリプトを Go 版の道具に替える

  Claude は、`.claude/scripts/` の `session.sh` と vuln-watch のスクリプト、`docker/`、`compose.yaml`、`start-dev.sh`、`terraform/` の説明の行、`.gitignore` の Java 版の分を、Go 版の道具に替えるか消す。Claude は、`.claude/settings.json` と `.claude/hooks/check-encoding.sh`(`.go` を足し、`.java` を消す)と `.github/` のワークフローとスクリプトと設定の完成版を、置き場に作る。
  - 完了の確かめ方: 検査用の写しで、`.claude/` と `.github/scripts/tests/` のテストと actionlint が成功する
  - 受入基準とテストの対応: 要件15の受入基準1(設定の記述を書き換える)は、`check-encoding.sh` のテストに足す「.go を対象にする」の場合と、13.4 の語の検査の結果で確かめる
  - _要件: 15.1_
  - _依存: 13.1_
  - _保留: 13.1 と同じ_

- [ ] 13.4 Java 版だけの名前が残っていないことを確かめ、PR を出す

  Claude は、Java 版のコードを消す PR 6-1 で消す前の `backend/gradle/libs.versions.toml` と `backend/build.gradle` と `docker/backend/` の Dockerfile を `git show` で読み、Go 版が使わない部品と道具と土台のイメージの名前を、design.md の語の一覧に足す。Claude は、`git grep -n -i -o -E '(^|[^[:alnum:]])(<語の一覧>)[[:alnum:]_]*'` を、言語を書いてよいファイルと `.kiro/specs/` を除いて動かし、`javascript` で始まる語を除く。残った語の行は、残す理由を添えて PR の本文に並べる。Claude は、実装のメモの「所有者に置いてもらう」のとおりに、置き場のファイルを所有者に本来の場所へ置いてもらったあと、すべてのテストと shellcheck と actionlint と `/verify-all` を通して PR を出す。
  - 完了の確かめ方: 語の検査で残った行が、`flyway_schema_history` のように Java 版を消したあとも使う名前の行だけで、PR の本文にその行と理由がある
  - 受入基準とテストの対応: 要件15の受入基準4(Java 版だけが使う言語と道具の名前が残っていない)は、語の検査の結果で確かめる
  - _要件: 15.1, 15.4, 7.3_
  - _保留: 13.1 と同じ_

- [ ] 14. 使っていないものを消す(PR 6-5)
- [ ] 14.1 compose と .gitignore の使っていないものを消す (並行可)

  Claude は、`compose.yaml` のボリューム `vendor`(`named-vendor`)と frontend のポート `6006:6006` と、`.gitignore` の `output.sh` と `output_result.txt` を消す。
  - 完了の確かめ方: `docker compose config` が成功し、`start-dev.sh` で開発環境が起動する
  - 受入基準とテストの対応: 要件16の受入基準1と3(使っていないものを、所有者が消してよいとしたものに限って消す)は、`docker compose config` の成功と、消したものが所有者の消してよいとした一覧にあることで確かめる
  - _要件: 16.1, 16.3_
  - _保留: PR 6-4 が main に入ったあと、所有者が `/kiro-impl backend-go-replacement` を打った会話で、Claude が大タスク14を行う_

- [ ] 14.2 frontend の使っていない部品を消す (並行可)

  Claude は、frontend の `package.json` と `pnpm-lock.yaml` から `@react-router/node` と `@react-router/dev` を消す。
  - 完了の確かめ方: frontend のテストが成功する
  - 受入基準とテストの対応: 要件16の受入基準1と3(使っていないものを、所有者が消してよいとしたものに限って消す)は、部品を消したあとの frontend の型の検査とテストの成功で確かめる
  - _要件: 16.1, 16.3_
  - _保留: 14.1 と同じ_

- [ ] 14.3 ui.sh の dind と、使わない3つのスキルを消す (並行可)

  Claude は、`.claude/scripts/parallel/ui.sh` の `KP_UI_SERVICES` から `dind` を消し、`tests/test-ui.sh` を合わせる。Claude は、スキル `kiro-discovery` と `kiro-validate-design` と `kiro-spec-batch` を消し、ルートの `CLAUDE.md` と、スキル `kiro-spec-design` と `kiro-spec-init` の `SKILL.md` の、この3つを名指す行を、消したことに合わせて直す。
  - 完了の確かめ方: `bash .claude/scripts/parallel/tests/test-ui.sh` が成功し、`git grep -n -E 'kiro-discovery|kiro-validate-design|kiro-spec-batch' -- ':!.kiro/specs/'` が何も返さない
  - 受入基準とテストの対応: 要件16の受入基準1と3(使っていないものを、所有者が消してよいとしたものに限って消す)は、`test-ui.sh` の「起動するサービスに dind を含まない」の場合と、`git grep` の結果で確かめる
  - _要件: 16.1, 16.3_
  - _保留: 14.1 と同じ_

- [ ] 14.4 品質チェックを通し、Issue #445 を閉じる PR を出す

  Claude は、`/verify-frontend` と、`.claude/scripts/parallel/tests/` のテストを通し、PR の本文に `Closes #445` を書いて PR を出す。この PR はスキルを消すゲート設定の変更を含むので、Claude は、PR の本文に「承認が要る理由」と「main に入れたときに本番で起きること」の2つの欄を書く。
  - 完了の確かめ方: `/verify-frontend` とテストが成功し、PR の本文に `Closes #445` と、「承認が要る理由」と「main に入れたときに本番で起きること」の2つの欄がある
  - 受入基準とテストの対応: 要件1の受入基準8(すべてを終えた PR でだけ Issue #445 を閉じる)は、`gh pr view` で読んだ PR の本文と、大タスク10から13の PR が main に入っていることで確かめる。要件7の受入基準3(承認が要る理由と、main に入れたときに本番で起きることを示す)は、`gh pr view` で読んだ PR の本文で確かめる。要件16の受入基準2(消す一覧を設計に書く)は、design.md の「消す一覧」で満たしてある
  - _要件: 1.8, 7.3, 16.2_
  - _保留: 14.1 と同じ_

## 実装のメモ

- PR の分け方と進め方: 次の5つのとおりに進める。
  - 1回の起動で進める範囲: `/kiro-impl` は、1回の起動で、`_保留:_` の無い大タスクだけを進め、最後の `/kiro-validate-impl` と `/ship` で1つの PR を出す
  - 保留の条件の確かめ方: 所有者が次の PR のために `/kiro-impl backend-go-replacement` を打ったら、親の会話の Claude は、Step 3 でタスクを1つずつ実装する繰り返しを始める前に、`gh pr list` と `gh pr view` で、次の大タスクの `_保留:_` の条件が満たされたかを確かめる
  - 条件を満たしたときと満たしていないとき: 満たされていれば、親の会話の Claude は、main から新しいブランチを作り、次の大タスクの小タスクの `_保留:_` の行だけを消してコミットしてから進める。満たされていなければ、何が足りないかを所有者に示して止まる
  - `terraform-apply.yaml` の実行の確かめ方: `_保留:_` の条件が `terraform-apply.yaml` の実行のときは、親の会話の Claude は、`gh run list --workflow terraform-apply.yaml` と `gh run view --json jobs` で、PR が main に入った時刻より後の実行のうち、ステップ「Terraform Apply」が飛ばされずに成功した実行があることを確かめる
  - 大タスク1のブランチ: 大タスク1は、今のブランチ `refactor/replace-backend-with-go` で進める
- `/kiro-validate-impl` の範囲: `/kiro-validate-impl` は、その PR で進めた大タスクだけを判定する。`_保留:_` のまま残した大タスクは、未完了として扱わない
- 受入基準の確かめ方: 要件の受入基準のうち、Claude の進め方の決まり(要件1の受入基準1と2と6、要件2、要件7、要件8)と、文書と PR の本文と所有者への返事で満たすものは、テストのコードでなく、「受入基準とテストの対応」の行に書いた文書か記録を読んで確かめる。要件2の受入基準1から4(設計を書く前に、今と同じにできるかが分からない動きを洗い出し、試しに作って確かめる)の結果は、Claude が段階1の記録として research.md に書き終えてある
- 置き場: Claude は、`.github/` と `.claude/hooks/` と `.claude/settings.json` の下のファイルの完成版を、作業フォルダの中の `.claude/.state/backend-go-replacement/place-<大タスクの番号>/` に、本来のパスと同じフォルダの形で作る。`.claude/.state/` は git の管理外である。`.claude/scripts/` と `.claude/skills/` は Claude が直接書ける
- 所有者に置いてもらう: Claude は、所有者に、置き場から本来の場所への `cp -r <置き場>/. <本来の場所>/` を、絶対パスで書き、置き場ごとの `cp` を `&&` でつないだ1つのコマンドで示し、置く理由を添える(タスク1.10で、ファイルごとに `cp` を並べると打ち漏らすと所有者に指摘された)。所有者が置いたあと、Claude は `cmp` で置き場と本来の場所を比べる。`cmp` が止められたら、Read で両方を読んで比べる
- `.github/` の置き場(タスク1.4で分かったこと): 許可の設定の `Write(.github/**)` は、作業フォルダの中の置き場の下の `.github/` にも当たり、Claude は書けない。そのため、Claude は `.github/` の下のファイルの完成版を、`.github/CLAUDE.md` のとおり、会話の scratchpad の `place-<大タスクの番号>/` に、本来のパスと同じフォルダの形で作る。scratchpad は会話ごとのフォルダなので、Claude は、大タスクの最後の小タスクで所有者に置いてもらうまで、同じ会話で進める
- 検査用の写し: Claude は、作業フォルダを `git archive HEAD` で scratchpad の一時フォルダに写し、まだコミットしていないファイルと置き場のファイルを本来のパスで重ねた写しで、置き場のファイルのテストを流す。まだリポジトリに無いファイルを `docker -v` で作業フォルダに重ねると、作業フォルダに0バイトのファイルが残るので、Claude はそうしない
- テストを流す環境: 大きなまとまりの途中の小タスクでは、Claude は、そのタスクで変えたファイルのテストだけを、この PC の Git Bash で流す。大きなまとまりの最後の小タスクでは、Claude は、`docker run --rm -v "<フォルダ>:/src:ro" alpine:3` で写しを読むだけの形で渡し、コンテナの中で別のフォルダに写してから、`apk add --no-cache bash perl git curl jq` のあとですべてのテストを流す。shellcheck は、CI の `guardrails.yaml` と同じく `koalaman/shellcheck:v0.11.0` に対象の `.sh` をまとめて渡し、actionlint は `rhysd/actionlint:1.7.12` で流す
- CI で動くスクリプト: CI のワークフローが呼ぶスクリプトを作るか直すときは、`.github/CLAUDE.md` の「CI で動くスクリプトを手元で確かめる」に従い、ランナーの CPU とファイルの権限を確かめる
- Go の品質チェックの動かし方: PR 2-1 が main に入ったあと、Claude は、Go 版のコードのテストを `bash .claude/scripts/parallel/run-check.sh backend-go <コマンド>` で動かす。途中の小タスクでは、そのタスクのパッケージの `go test` だけを動かし、`make check` と `make compat` は大きなまとまりの最後の小タスクで動かす。`make mutation-diff` は git の履歴が要るので CI でだけ動く
- Go のテストの飛ばしと検査の外し: Claude は、Go のコードに `t.Skip` と `//nolint` を書かない。タスク1.9で、escape-hatch の検査がこの2つを機械で見つけて PR を止めるためである。Claude は、Docker が要る結合テストを、Docker が無ければ失敗するように書く。`run-check.sh backend-go` と CI の `backend-go` の仕事は、どちらも Docker を使える
- 部品と道具の版: Claude は、design.md の「使う技術」の版が公開から72時間たっていればその版を、たっていなければ1つ前の版を使う。版は `backend/go.mod` に書き、`tool` の指定で道具の版も `go.mod` に集める
- 必須の検査の期待一覧: Claude は、`.github/audit/required-checks.json` を、大タスク10(PR 6-1)まで変えない
- ワークフローを変える PR: ワークフローを追加・変更・削除した PR では、Claude は、README のワークフローの一覧の表と Mermaid の図も直す
- 比べる検査の報告の置き場(タスク1.5で決めたこと): `ci.yaml` の `backend-compat` は、`backend/compat/report/` の下のファイルを成果物 `backend-compat-report` に残す。Claude は、比べる検査を作るタスクで、違いの報告と、失敗したときの両方の版のコンテナのログを、このフォルダに書くように作り、このフォルダを `backend/.gitignore` に足す
- golangci-lint の版(タスク1.5で決めたこと): `ci.yaml` の `backend-go` は、golangci-lint の版を v2.15.0 に固定し、`.github/ci-tool-versions.json` の excluded に載せた。週1回の自動の更新はこの版を上げない。Claude は、`docker/backend-go/Dockerfile` に同じ版を書き、版を上げるときは2か所を同じ PR で上げる
- CodeQL の Go の解析(タスク1.6で分かったこと): `codeql.yaml` には `actions/setup-go` の手順が無く、Go の行の組み立ては、GitHub Actions の機械に入っている Go と、`go.mod` の `toolchain` の指定による Go の自動の入手に頼る。Claude は、`backend/go.mod` を足す PR 2-2 で、CodeQL の `go` の仕事が成功したことを `gh run view` で確かめ、失敗したときは `setup-go` の手順を足す提案を所有者に出す
- PR の本文: この spec の PR の本文には、`Spec: .kiro/specs/backend-go-replacement` と `Refs: #445` を書く。所有者の承認が要る PR では、「承認が要る理由」と「main に入れたときに本番で起きること」の2つの欄を書き、PR を作ったときの所有者への返事に、この2つの欄をそのまま写す
- 公開のリポジトリ: Claude は、まだ直していないセキュリティの穴を、Issue、PR、コミット、spec の本文に書かない
- 公開の時刻の検査のテストの環境(タスク1.7で分かったこと): `test-check-dependency-cooldown.sh` は openssl と gnupg を使う。Linux のコンテナで流すときは、`apk add` に `openssl gnupg` を足す
- Go のモジュールの索引の読み方(タスク1.8で分かったこと): index.golang.org は1回の問い合わせに約4秒かかり、73時間分を順に読むと約10分かかって、判定の手順の5分の上限に収まらない。そのため `lib-gomod-index.sh` は、73時間を4時間ずつの区間(`GOMOD_INDEX_SEGMENT_HOURS`)に分け、約19本を同時に読む。design.md の「索引を順に読む」の書き方とは違う。区間の中のページは、最後の行の時刻を秒に切り上げた値が区間の終わりと同じときも、次のページを読む(`-le`)。check-release-age.sh は、go.mod の go・toolchain・module・exclude・retract・tool・godebug・ignore の行を照らさない。Dependabot が toolchain の行を変えるかは確かめていない
- Go の検査の外しの検知(タスク1.9で決めたこと): `check-escape-hatches.sh` は、`backend/` の下のすべての `.go` で、足した `.Skip(` `.SkipNow(` `.Skipf(` と `//nolint` と `// coverage-ignore`(go-test-coverage がカバレッジから外すコメント)を見つける。受け手の名前は `t` に限らない。gosec の `// #nosec` は見つけない。そのため、Claude は、タスク2.3で `.golangci.yml` を作るとき、gosec が `#nosec` のコメントに従わない設定にする。Claude は、タスク2.3で `Makefile` から golangci-lint と gremlins を呼ぶとき、設定のファイルを名前で指定する。承認の対象の6つのファイルと別の名前の設定のファイルを、道具が読まないようにするためである
- design の審査で残った記録: 次の5つを、それぞれ次のタスクで扱う。
  - D3-3-1: 6-1 の `backend-vuln-fix` が版を上げる場所の一覧である。design.md の「Dependabot と公開の時刻の検査と脆弱性の直し」に書き足したとおりに、タスク10.7で扱う
  - D5-1-1: 6-1 での `backend-vuln-fix.yaml` の Java 版の仕事の扱いである。タスク10.7で扱う
  - D3-3-2: 表の形の履歴の `description` の書き方である。タスク2.4で扱う
  - D3-2-2: Dependabot の docker の項目の `open-pull-requests-limit` である。タスク5.1で扱う
  - D3-1-6: 比べる検査のコードを `make lint` が読むかである。タスク2.3で扱う
- コードの生成(タスク2.2で分かったこと): oapi-codegen は、設定のファイルに `output` があると `-o` を使わない。そのため `api/oapi-codegen.yaml` には `output` を書かず、Makefile が `-o` で出力の場所を渡す。sqlc は、問い合わせのファイルが1つも無いと失敗するので、Makefile は `db/queries/*.sql` があるときだけ sqlc を動かす。sqlc は設定のファイルのフォルダから相対のパスを読むので、`generate-check` は設定とマイグレーションと問い合わせを `cp --parents` で一時のフォルダに写して生成する。問い合わせを作るタスク(2.5 以降)で、Claude は `db/queries/` に SQL を置き、`make generate` で `internal/platform/database/sqlcgen/` を作る

## 完了条件(全タスク共通)

Claude は、どのタスクでも、タスクの箇条書きの欄を書いたうえで、次の4つを満たしたときにタスクを完了とする。

1. Claude は、タスクが満たす requirements.md の受入基準(要件の番号付きの項目)ごとに、それを確かめるテストのファイル名とテスト名を「受入基準とテストの対応」の行に書く。Claude は、確かめるテストの無い受入基準を残さない。
2. タスクで変えたファイルを使うテストが、すべて成功している。`1.` や `2.` の見出しのタスクを大きなまとまりと呼ぶ。大きなまとまりの最後のタスクでは、加えて、そのまとまりのタスクで変えた領域の verify のスキル(`/verify-frontend` `/verify-backend` `/verify-terraform`)が、すべて成功している。
3. Claude は、テストを飛ばす設定、アサーションの削除、カバレッジや lint の対象からの除外を足して、完了条件を満たしたように見せない。CI の escape-hatch の検査が、これらの追加を機械で見つける。
4. Claude は、新しく書いたテストについて、テストの対象のコードを一時的に壊してテストが失敗することを確かめる。Claude は、新しいテスト1件につき1か所だけを、作業フォルダの外の写しで壊し、そのテストだけを流す。壊した写しの作り方と流し方は、`.kiro/steering/tech.md` の「テストの完全性」に従う。
