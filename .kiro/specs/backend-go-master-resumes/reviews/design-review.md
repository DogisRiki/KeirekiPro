# design のレビュー記録(backend-go-master-resumes)

## サイクル1 往復1(2026-11-14)

### 審査の範囲

範囲: 全体

### 実ファイルで確かめた文

- design.md 概要・プロジェクトの決まり「depguard の規則は、機能のパッケージが `internal/auth` と `internal/platform` を読むことを許してある」: backend/.golangci.yml 43-57行(list-mode は lax で、外部のライブラリは禁じていない) / 合っていた
- design.md 使う既存の仕組み「`internal/auth` の公開した部品(`FieldErrors` `ErrBusiness` `ErrInvalidInput` `NotBlank` `UTF16Len` `IsJavaWhitespace`)」: backend/internal/auth/exported.go 27行、101行、106行、116行、121行、126行、backend/internal/auth/errors.go 80-91行 / 合っていた
- design.md 使う既存の仕組み「`authresponses.go` の `authResponse` `authJSON` `authErrorResponse` `jacksonJSON`」: backend/internal/httpapi/authresponses.go 15行、48行、85行、109行 / 合っていた
- design.md 使う既存の仕組み「`database` は日本の時間帯の接続の設定を持つ」: backend/internal/platform/database/database.go 18-19行、47行 / 合っていた
- design.md 使う既存の仕組み・プロジェクトの決まり「`golang.org/x/text` は `go.mod` に間接の依存として v0.43.0 が入っている」「使う技術の版」: backend/go.mod 170行ほか / 合っていた
- design.md 使う既存の仕組み「初期のデータ `fixtures/users/basic.sql` と `fixtures/resumes/fonts.sql`」、筋書きの節「`fonts.sql` の、6つの欄のすべてに項目を持つ経歴書」: backend/compat/fixtures/users/basic.sql 16-18行、backend/compat/fixtures/resumes/fonts.sql 5-67行(持ち主は user1、6つの欄と `project_tech_stacks` に行がある) / 合っていた
- design.md ファイルの構成「sqlc の問い合わせは `db/queries`、出力は `internal/platform/database/sqlcgen`。`backend/sqlc.yaml` は変えない」: backend/sqlc.yaml 17-21行、backend/db/queries の一覧(auth.sql、users.sql) / 合っていた
- design.md 受け口の節「手本は利用者の受け口 `userHandlers`」「`var _ ... = (*....Service)(nil)` で型を確かめる」「利用者の ID は `authctx.UserID` で得る」: backend/internal/httpapi/users.go 386行、396行、399行、436行 / 合っていた
- design.md httpapi.New の節「`Options` に認証と利用者の受け口があり、`routes` が深さ1に埋め込む」「`ErrorHandlerFunc` の無名の関数は `/api/auth/` の下の問い合わせの誤りだけを 400 にする」: backend/internal/httpapi/server.go 27行、45行、48行、60-64行、119-121行、137-145行 / 合っていた
- design.md httpapi.New の節「`server_test.go` の2つの副テスト(`TestBadJSONReturns400MessageErrors` と `TestNew_AuthQueryError400` の中)が `/careers/not-a-uuid` を使う」: backend/internal/httpapi/server_test.go 123行、135-139行、324行、338-340行 / 合っていた
- design.md 仕様書の節「項目の ID の6つの経路の値の説明に『Java 版は UUID として受け取り、UUID として読めない値には 500 を返す。』がある」「経歴書の ID は文字列」: backend/api/openapi.yaml 1441-1497行 / 合っていた
- design.md 仕様書の節「要求の本文の8つの型」: backend/api/openapi.yaml 1811-1899行。8つの型は、要求の本文(651行、743行、891行ほか14か所)からだけ参照され、ほかの型からは参照されていない / 合っていた
- design.md 概要・仕様書の節「生成したコードが本文を読む(`runtime.BindJSONBody`)。読めなければ 400 と決まった本文」: backend/internal/httpapi/gen/api.gen.go 8818-8823行、backend/internal/httpapi/server.go 119-121行 / 合っていた(`runtime.BindJSONBody` の中身は、リポジトリにソースが無く開けなかった。D1-1-5)
- design.md main.go の節「`main.go` は `users.New` で処理を作り `httpapi.Options` に渡す」: backend/cmd/keirekipro/main.go 162行、184-191行 / 合っていた
- design.md 作らないもの・受け口の節「Java 版の答えで `systemTest` と `maintenance` の値が入れ替わる」「`lastName` `firstName` は null なら書かない。6つの欄は空なら書かない」: backend/src/main/java/com/example/keirekipro/presentation/resume/dto/ResumeInfoResponse.java 30-56行、100-107行、217-225行 / 合っていた
- design.md データの形「`techStack` の中の鍵は、`frontend` の8つ、`backend` の10、`infrastructure` の9つ、`tools` の7つ」: ResumeInfoResponse.java 244-304行、backend/api/openapi.yaml 2326-2344行、MyBatisTechStackListQuery.java 122-129行。`tools` の鍵は8つである / 食い違っていた(D1-1-1)
- design.md rules.go の節・初期のデータの節「上限は、経歴書50、職歴30、プロジェクト100、資格50、SNS 10、ポートフォリオ50、自己PR 5」: backend/src/main/java/com/example/keirekipro/usecase/resume/policy/ResumeLimits.java 15-45行 / 合っていた
- design.md 処理の流れ「Java 版は、上限を、経歴書が利用者のものかより先に確かめる」: backend/src/main/java/com/example/keirekipro/usecase/resume/CreateCareerUseCase.java 44-52行 / 合っていた
- design.md 処理の流れ「コピーの順は、上限、名前の重なり、コピー元の読み出し、利用者のものかの確認。日付と姓と名はコピー元の値」「コピーしない作成の日付は今日、姓と名は null」: CopyCreateResumeUseCase.java 50-66行、126-137行、CreateResumeUseCase.java 44-65行 / 合っていた
- design.md order.go の節「6つの欄の並べ方」: backend/src/main/java/com/example/keirekipro/domain/policy/resume/ResumeEntryOrderPolicy.java 50-168行、189-218行 / 合っていた
- design.md masters.go の節「技術スタックは分類と ID の順に読み、小分類 `framework` は鍵 `frameworks` になる。対応の無い小分類は捨てる」「資格と SNS は並べ方を指定しない」: MyBatisTechStackListQuery.java 74-136行、TechStackQueryMapper.xml 8-19行、CertificationQueryMapper.xml 8行、SnsPlatformQueryMapper.xml 8行(ORDER BY が無い) / 合っていた
- design.md 読み書きの節「Java 版の `selectAllByUserId` と同じ並べ方」: backend/src/main/java/com/example/keirekipro/infrastructure/repository/resume/ResumeMapper.xml 73-87行 / 合っていた
- design.md データの形「`resumes.created_at` と `updated_at` は `TIMESTAMP(6)`」「`resumes.user_id` は `users` を参照し `ON DELETE CASCADE` を持たない」「`project_tech_stacks` は `project_id` を主キーにする」: backend/src/main/resources/db/migration/V1__create_tables.sql 69-77行、151-152行 / 合っていた
- design.md harness の節「`JavaEnv` に TZ が無い」「比べる検査と版をまたいで確かめる検査の Java 版は、どちらも `JavaEnv` で動く」: backend/compat/harness/versions.go 72-92行、backend/compat/harness/stack.go 52行 / 合っていた
- design.md harness の節「本番の ECS のタスクと同じ設定(TZ=Asia/Tokyo)」: terraform/modules/ecs/main.tf 62-63行 / 合っていた
- design.md harness の節「`Normalizer` の `received`」「`<datetime:形>`」「`RedisTTLTolerance` は5秒」「段ごとに Java 版、Go 版の順に送る」: backend/compat/harness/normalize.go 58-60行、backend/compat/harness/compare.go 39行、106行、backend/compat/harness/compareenv.go 168行 / 合っていた
- design.md harness の節「初期のデータの固定の日時は、2つの版で同じ値なので、秒の差も同じになる」: backend/compat/harness/compare.go 106行(受けた時刻は版ごとに違う)、backend/compat/harness/compareenv.go 168行 / 食い違っていた(D1-1-3)
- design.md harness の節「`compat_test.go` `cross_test.go` `perf_test.go` は、未実装の答えを確かめるために経歴書の削除の経路を使う」: backend/compat/compat_test.go 106-107行、backend/compat/cross_test.go 204-205行、backend/compat/perf_test.go 29-30行 / 合っていた
- design.md ファイルの構成「harness のテストで変えるのは `normalize_test.go` と `compare_test.go`」: backend/compat/harness/versions_test.go 48-58行、60-72行(`JavaEnv` の値の数と中身を確かめるテストがある) / 食い違っていた(D1-1-4)
- design.md 筋書きの節「退会のあとも、取り出した値がログインの状態の検査を通る」「退会の答えは `accessToken` と `refreshToken` だけを消す」: backend/internal/users/delete.go 37-64行、backend/internal/auth/accesstoken.go 113-123行、backend/src/main/java/com/example/keirekipro/presentation/user/controller/DeleteUserController.java 48-49行、backend/compat/scenarios/users/delete-user.yaml、backend/compat/harness/send.go 150-173行、backend/compat/harness/capture.go / 合っていた
- design.md 変えた動きの一覧の節「今の最後の項目は CB-046」「CB-011 は `order_only` の match を持つ」「match の無い項目は記録だけの項目」: backend/compat/changed-behaviors.yaml 118-162行、501-502行、backend/compat/harness/match.go 21-31行、42-45行 / 合っていた
- design.md 進み具合の表の節「状態の名前」「`作り終えた` にすると、group 3 の26の操作を筋書きに求める」: .kiro/specs/backend-go-replacement/progress.md 30行、38行、backend/compat/harness/coverage.go 17-19行、133-137行、backend/compat/harness/operations.go 115-128行、backend/api/openapi.yaml の operationId(50個のうち、認証13、利用者7、出力2、バックアップ2を除く26個) / 合っていた
- design.md テストの方針「`make compat` `make compat-cross` `make compat-perf` `make generate`」: backend/Makefile 38-42行、127-135行 / 合っていた
- design.md API の説明画面の節「compose の `api-docs`(ポート 8082)」「`backend-go` のコンテナは作業フォルダのコードを動かす」: compose.yaml 40-51行、76-86行 / 合っていた
- design.md 安全「Go 版は、要求の本文を、今の土台が決めた大きさの上限のまま読む」: backend/internal/httpapi/users.go 24-25行、110-114行(上限があるのは名前と画像の変更の本文だけ)、backend/cmd/keirekipro/main.go 195行(`ReadHeaderTimeout` だけ)。backend/internal と backend/cmd に、JSON の本文の大きさを限る処理(`MaxBytesReader` など)は無い / 食い違っていた(D1-1-2)

### 受入基準ごとの確かめ方

| 受入基準 | 確かめる道具 | 動かす場所 | 動かすのに要るもの | design の箇所 |
|---|---|---|---|---|
| 1.1 | `make compat` の `scenarios/resumes/` の compare の筋書き、`resumes_test.go`、`body_test.go` ほかの単体テスト | 開発環境の `backend-go` の領域の検査と CI の比べる検査 | user1 と user2(`basic.sql`)、`resume-ops.sql`、マイグレーション V2 と V4 が入れるマスタの行、`<wallclock:形:+秒>` の比べ方。本文の全体の読み方(余り、空、並び、`null`)を、生成したコードを通して確かめる道具 | 「マスタと経歴書の操作の筋書き」「テストの方針」。生成したコードを通す道具は無い(D1-1-5) |
| 1.2 | 画面と同じ本文の compare の筋書きと、Playwright での `api-docs` の確認 | 開発環境の compose(`api-docs` 8082、`backend-go` 8081) | 利用者(利用者の spec の手順で作る)、書き込みの操作に付ける `X-XSRF-TOKEN` の値 | 「API の説明画面での確認」。`X-XSRF-TOKEN` の値の入れ方は無い(D1-1-6) |
| 2.1 | `resume-validation.yaml` と欄ごとの筋書きと `limits.yaml`、`validate_test.go` `rules_test.go` `link_test.go` `jackdate_test.go` | 同上(1.1) | `resume-limits.sql`(50件の経歴書と、上限に達した6つの欄)、絵文字を含む境界の値、`testdata/` の正解の値 | 「マスタと経歴書の操作の筋書き」「初期のデータ」「テストの方針」 |
| 3.1 | `other-user.yaml` と `service_integration_test.go` | 比べる検査と、testcontainers-go の結合テスト | user1 の経歴書と項目(`resume-ops.sql`)、user2 のログイン | 「マスタと経歴書の操作の筋書き」「テストの方針」 |
| 3.2 | `not-found.yaml`(別の経歴書の項目の ID を組にした要求)と `service_integration_test.go` | 同上 | 2つの経歴書とその項目 | 「マスタと経歴書の操作の筋書き」「テストの方針」 |
| 3.3 | `service_integration_test.go`(比べる検査では送らない)と、変えた動きの一覧の CB-047 | 結合テスト | ほかの利用者の、上限に達した経歴書 | 「変えた動きの一覧の項目」「テストの方針」 |
| 3.4 | `deleted-user.yaml` と、コピーしない作成の `service_integration_test.go`、CB-049 | 比べる検査と結合テスト | 退会用の利用者(世代の番号 0)、`cookie:accessToken` の取り出し、退会のあとも残る `XSRF-TOKEN` | 「マスタと経歴書の操作の筋書き」の退会の箇条、「初期のデータ」 |
| 4.1 | `scenarios/resumes/` の表の筋書きと、`progress.md` の状態で働く操作の網羅の検査 | CI の比べる検査 | `progress.md` の状態が `作り終えた` 以上であること | 「マスタと経歴書の操作の筋書き」「進み具合の表」 |
| 4.2 | compare の段ごとのデータベースの比べ方(`CompareDB`) | 比べる検査 | `resumes` の日時の列の `<wallclock>` の置き換え | 「Java 版と Go 版を比べる検査の広げ方」「マスタと経歴書の操作の筋書き」 |
| 4.3 | `<wallclock:形:+秒>` の5秒の幅、UUID の置き換え、`JavaEnv` の `TZ`、harness の単体テスト | 比べる検査と、harness の単体テスト | 版ごとの受けた時刻、`TZ=Asia/Tokyo`、`versions_test.go` の書き換え | 「Java 版と Go 版を比べる検査の広げ方」。`versions_test.go` はファイルの構成に無い(D1-1-4)。固定の日時の扱いの文が仕組みと合わない(D1-1-3) |
| 4.4 | CB-047〜050 と、`resumes_test.go` `service_integration_test.go` | 単体テストと結合テスト | 読めない項目の ID、退会した利用者 | 「Service」の「失敗したとき」「変えた動きの一覧の項目」 |
| 4.5 | `perf-*.yaml` の5つと `make compat-perf` | 開発環境の `backend-go` の領域 | `fonts.sql` の経歴書(6つの欄に項目がある)、user1 のログイン | 「マスタと経歴書の操作の筋書き」の末尾、「テストの方針」 |
| 5.1 | `cross-resume.yaml` と `make compat-cross` | CI の版をまたいで確かめる検査 | 同じデータベースにつなぐ2つの版、`capture` と `expect.values` | 「マスタと経歴書の操作の筋書き」の `cross-resume.yaml` |
| 5.2 | `cross-resume.yaml` の日時の比べ、`store_integration_test.go` の日時の丸め、比べる検査の `<wallclock>` | 同上と結合テスト | `TZ=Asia/Tokyo` の Java 版、`Deps.Now` | 「読み書き」の日時の箇条、「Java 版と Go 版を比べる検査の広げ方」 |
| 5.3 | `cross-resume.yaml` の5つの段 | CI の版をまたいで確かめる検査 | 保存した版の `GET` の答えから取り出した ID と日時 | 「マスタと経歴書の操作の筋書き」の `cross-resume.yaml` |
| 6.1 | research.md の「試作の記録」(P1〜P13) | 設計の前に済んでいる | 無い | 「試作の記録(research.md)」 |
| 6.2 | research.md の「同じにできない動き」(無い) | 設計の前に済んでいる | 無い | 「試作の記録(research.md)」 |
| 6.3 | `progress.md` のマスタと経歴書の行 | PR の差分 | 無い | 「進み具合の表」 |

### 申告

**1. 比べる検査の Java 版の時間帯を変え、経歴書の日時を時刻の差で比べる** — design.md「Java 版と Go 版を比べる検査の広げ方(harness)」

- Issue の記載: なし(Issue #772 は、置き換えの spec の要件 4.5 を満たすことだけを求めている)
- 決めたこと: `JavaEnv` に `TZ=Asia/Tokyo` を足す。`resumes` の表の日時の列と、JSON の鍵 `createdAt` `updatedAt` を `<wallclock:形:+秒>` に置き換え、5秒の幅で比べる
- 他にありえた選択肢: 幅を別の値にする。経歴書のまとまりの筋書きだけを対象にする。Go 版の時刻を検査の側から決める
- 外れていた場合: この変更は、認証と利用者のまとまりの筋書きと、あとで作る出力とバックアップのまとまりの筋書きにも効く。幅が狭ければ CI が時々止まり、対象が広すぎれば、ほかのまとまりの検査の結果が変わる

**2. 要求の本文を生成したコードで読まず、`internal/resume` が Jackson の規則を写して読む** — design.md「本文の読み手」「仕様書の変更」

- Issue の記載: なし
- 決めたこと: API の仕様書の8つの要求の型に `x-go-type: json.RawMessage` を足し、本文の読み手を自分で書く
- 他にありえた選択肢: 生成した構造体で読み、Jackson との違いを変えた動きの一覧に載せる
- 外れていた場合: 写した規則が Jackson と違う箇所は、筋書きと単体テストに入れた書き方でしか見つからない。入れていない書き方では、Go 版が Java 版と違う値を保存する

**3. Java 版と違い、変わる行だけを書き、経歴書の行を `FOR UPDATE` で固定する** — design.md「Service」「読み書き」

- Issue の記載: なし
- 決めたこと: 項目の変更では、その項目の行と `resumes` の `updated_at` だけを書く。Java 版は6つの欄の行をすべて消して書き直す
- 他にありえた選択肢: Java 版と同じく、すべての行を書き直す
- 外れていた場合: 切り替えの途中で、同じ経歴書への要求が2つの版に同時に届くと、Java 版の書き直しと Go 版の1行の書き込みが重なり、一方の変更が消えることがある。比べる検査も版をまたいで確かめる検査も、同時の要求は送らない

**4. 項目の ID が読めない要求と、退会した利用者のコピーしない作成に、404 で答える** — design.md「Service」の「失敗したとき」、「変えた動きの一覧の項目」

- Issue の記載: なし(requirements の要件4の受入基準4が、要求の誤りか対象が無いことのどちらで答えるかを設計で決めるとしている)
- 決めたこと: どちらも、無い項目か無い経歴書と同じ 404 にする
- 他にありえた選択肢: 項目の ID が読めない要求を 400(要求の誤り)にする
- 外れていた場合: 答えの状態の番号を変える直しと、変えた動きの一覧と API の仕様書の説明の書き直しになる

**5. 作業の工程の `systemTest` と `maintenance` の入れ替わりを、Go 版でも同じにする** — design.md「作らないもの」「経歴書の受け口」

- Issue の記載: なし
- 決めたこと: Go 版の答えで2つの値を入れ替え、Java 版の誤りは所有者に報告する
- 他にありえた選択肢: Go 版は正しい値を返し、違いを変えた動きの一覧に載せる。Java 版と Go 版を同じ PR で直す
- 外れていた場合: 画面が今、入れ替わった値を前提に動いているかは、この設計は確かめていない。所有者があとで直すと決めたときは、2つの版と画面を合わせて直すことになる

**6. マスタの3つの操作を `internal/resume` に置き、`internal/resume` に `internal/auth` を読ませる** — design.md「設計を見直すきっかけ」、research.md「設計で決めたこと」

- Issue の記載: なし
- 決めたこと: マスタと経歴書を1つのパッケージにし、誤りの型と入力の検査の部品を `internal/auth` の `exported.go` から読む
- 他にありえた選択肢: 共通の部品を `internal/platform` に移す。マスタを別のパッケージにする
- 外れていた場合: 認証の spec の設計(ほかのまとまりは `internal/auth` を読まない)との食い違いが広がり、あとで部品を移すときに、3つのまとまりを同時に直すことになる

### 指摘

| ID | レベル | 該当箇所 | 内容 | 直し方の案 |
|---|---|---|---|---|
| D1-1-1 | 中 | design.md「データの形」の「経歴書の答え」の箇条(525行) | 「`tools` の7つ」は実ファイルと食い違う。`tools` の鍵は8つである(`sourceControls` `projectManagements` `communicationTools` `documentationTools` `apiDevelopmentTools` `designTools` `editors` `developmentEnvironments`)。ResumeInfoResponse.java 295-304行、backend/api/openapi.yaml 2326-2344行、MyBatisTechStackListQuery.java 122-129行。この数のまま答えの型と筋書きを作ると、鍵が1つ欠ける | 「`tools` の8つ」に直す |
| D1-1-2 | 中 | design.md「安全」の3つ目の箇条(567行) | 「今の土台が決めた大きさの上限のまま読む」は実ファイルと食い違う。Go 版の土台に、JSON の本文の大きさの上限は無い。上限があるのは名前と画像の変更の本文だけである(backend/internal/httpapi/users.go 24-25行、110-114行)。backend/cmd/keirekipro/main.go 195行は `ReadHeaderTimeout` だけを決め、backend/internal と backend/cmd に本文を限る処理は無い。生成したコードは `runtime.BindJSONBody` に本文をそのまま渡す(api.gen.go 8819行) | 上限が無いことを書いたうえで、経歴書の操作でも上限を置かない(認証の JSON の操作と同じ)か、この設計で上限を置くかを決めて書く。置くなら、値と、超えたときの答えと、Java 版との違いの扱いを書く |
| D1-1-3 | 中 | design.md「Java 版と Go 版を比べる検査の広げ方(harness)」の最後の2つの箇条(406-407行) | 「初期のデータの固定の日時は、2つの版で同じ値なので、秒の差も同じになる」は、同じ節の置き換え方(404行: 値から、その版の応答を受けた時刻を引く)と合わない。受けた時刻は版ごとに違う(compare.go 106行。compareenv.go 168行のとおり Java 版、Go 版の順に送る)ので、固定の日時の秒は、Go 版の段にかかった時間だけ必ずずれる。406行の「2つの版の日時の差は、Go 版の応答の時間ほどになる」も、引いたあとの秒の差の説明になっていない。対象は `resumes` の表の全部の行なので、`fonts.sql`(7行)や `many-pages.sql` の固定の日時を持つ、ほかのまとまりの筋書き(出力など)でも、Go 版の段が5秒を超えると、変わっていない行が違いとして報告される | 固定の日時でも秒は「Go 版の段にかかった時間」だけずれ、幅の内側で同じとみなすことを書く。または、2つの版の元の値が同じ文字なら秒を比べずに同じとする、と決めて書く。harness の単体テストの場面(560行)にも、固定の日時の場面を足す |
| D1-1-4 | 中 | design.md「ファイルの構成」の「Claude が変えるファイル」(143行)、「テストの方針」(560行) | `JavaEnv` に `TZ` を足すと、backend/compat/harness/versions_test.go の `TestJavaEnv_DevProfileAndOIDCEndpoints`(60-72行)が落ちる。`assertEnv`(48-58行)が環境の値の数を確かめているためである。テストの方針は「Java 版の環境の値に `TZ` が入ることも確かめる」と書くが、ファイルの構成には `normalize_test.go` と `compare_test.go` しか無い | 「Claude が変えるファイル」に `backend/compat/harness/versions_test.go` を足す |
| D1-1-5 | 中 | design.md「本文の読み手」の「本文の全体」の箇条(271行)、「仕様書の変更」の3つ目の箇条(372行)、「テストの方針」の `body.go` の箇条(541行) | 本文の型を `json.RawMessage` にすると、本文の全体の扱い(最初の値のあとの余り、空の本文、JSON として誤った本文)は、`decodeBody` より前に、生成したコードの `runtime.BindJSONBody`(api.gen.go 8819行)が決める。design は、この扱いを `decodeBody` の規則として書き、`body.go` の単体テストだけで確かめる。筋書きの「本文が読めない要求」(435行)にも、余りと空と並びと `null` の本文は入っていない。`BindJSONBody` が余りのある本文を断るなら、Go 版は Java 版(余りを読まずに受ける)と違う答えを返し、どの検査も見つけない。審査役は `BindJSONBody` のソースをリポジトリの中で開けず、どちらになるかを確かめられなかった | 余りのある本文、空の本文、並びと `null` と文字列の本文を、経路を通した要求で確かめる場面を足す(`resumes_test.go` で `httpapi.New` の経路に送るか、`resume-validation.yaml` に足す)。`BindJSONBody` が `json.RawMessage` にどこまでを渡すかを、確かめた行を添えて design に書く |
| D1-1-6 | 中 | design.md「API の説明画面での確認」(481行) | 経歴書の作成と職歴の追加は書き込みの操作で、Go 版は `X-XSRF-TOKEN` のヘッダが Cookie の値と合わないと 403 で答える(backend/api/openapi.yaml 47-54行、1400-1415行)。利用者の spec の手順は、ログイン(検査の対象の外)と `GET /api/users/me` だけなので、ヘッダの値の入れ方を含まない(.kiro/specs/backend-go-users/design.md 668-670行)。design は「利用者の spec と同じ手順」とだけ書き、ヘッダの値をどこから得て「Try it out」のどの欄に入れるかを決めていない。仕組みは今の環境にある(Cookie `XSRF-TOKEN` は HttpOnly でなく、仕様書にヘッダの欄がある。compose.yaml 85-86行) | 「Claude は、Cookie `XSRF-TOKEN` の値を読み、『Try it out』の `X-XSRF-TOKEN` の欄に入れる」の形の1文を足す。作った経歴書の ID を次の操作の `resumeId` の欄に入れることも書く |
| D1-1-7 | 低 | design.md「プロジェクトの決まりを守っているか」(69-70行) | 雛形は、関係のない項目を「関係のない項目:」の1行に名前だけで並べる形である。design は、frontend の2つの項目を別々の行に「この spec は画面を変えない」と書いている。7つの項目はすべて出ており、本文との矛盾は無い | 2行を「関係のない項目: frontend の機能ごとの境界、frontend の状態の持ち方」の1行にする |
| D1-1-8 | 低 | design.md「マスタと経歴書の操作の筋書き」の `cross-resume.yaml`(446行)、「テストの方針」(558行) | 版をまたいで確かめる検査は、2つの向きに加えて、段ごとに版を入れ替える組(alternate)でも筋書きを動かす(backend/compat/harness/cross.go の `CrossDirections`)。design は2つの向きだけを書く。5つの段は「最初の版」と「もう一方の版」で書かれており、alternate の組でどの版に届くかは書かれていない | alternate の組でも動くことと、その組で5つの段が成り立つこと(`to: other` の段の届き先)を1文で足す |
| D1-1-9 | 低 | design.md「変えた動きの一覧の項目」の CB-048(472行) | 要件4の受入基準4は「答えを変えた要求を、変えた動きの一覧に1つずつ載せる」と書く。CB-048 は、6つの欄の更新と削除(12の操作)を1つの項目にまとめている。同じ節の最後の箇条は「要求ごとに1つの項目を足す」と書いており、まとめ方が節の中でそろっていない | CB-048 を1つにまとめる理由(同じ原因で同じ答えになる)を書くか、欄ごとに分ける |

### 前の段階への指摘

無い。

- 往復: 1回目 / 高0 中6 低3

## サイクル1 往復2(2026-11-14)

### 審査の範囲

範囲: 差分

- design.md「本文の読み手」の「本文の全体」の箇条(270行)、「仕様書の変更」の3つ目の箇条(371行)、「テストの方針」の `body.go` と `resumes.go` の箇条(542行、549行)、「マスタと経歴書の操作の筋書き」の入力の誤りの箇条(436行): 差分が `BindJSONBody` の読み方と、経路を通した確かめを足した。同じ本文の全体の扱いを書くほかの箇条と、要件1の受入基準1と、research.md の P10〜P12(82行)と食い違わないかを見た
- design.md「Java 版と Go 版を比べる検査の広げ方(harness)」の全体(399-412行)と「テストの方針」の harness の箇条(561行)、「ファイルの構成」の harness のファイル(140-144行): 差分が秒の差の説明と、単体テストの場面と、`versions_test.go` を足した。同じ節の置き換え方と比べ方、要件4の受入基準2と3、要件5の受入基準2に効く
- design.md「API の説明画面での確認」(482行): 差分が `X-XSRF-TOKEN` と `resumeId` の入れ方を足した。要件1の受入基準2に効く
- design.md「安全」の3つ目の箇条(568行): 差分が本文の大きさの上限の文を書き直した
- design.md「データの形」の `tools` の鍵の数(526行): 差分が数を直した。往復1で openapi.yaml 2326-2344行と合わせて確かめた数(8つ)と同じである
- design.md 概要、「設計を見直すきっかけ」の depguard の文(55行)、「プロジェクトの決まりを守っているか」(64行): 差分が depguard の説明を概要から55行に移した。depguard の規則についての文が64行に残っていることを見た
- design.md「処理の流れ」の項目の追加の図のあとの文(消した行)、「経歴書の決まり」の最後の箇条(309行)、「変えた動きの一覧に載せる違い」の CB-047 と CB-049(472行、474行)、「マスタと経歴書の操作の筋書き」の箇条(441行、442行): 差分が、上限と持ち主の確認の順の文と、「比べる検査はこの要求を送らない」を消した。消した中身が309行と441行と442行に残っていることを見た。要件3の受入基準3と要件4の受入基準4の確かめ方は変わらない
- そのほかの差分(「項目」を「違い」「入力欄」に言い換えた行、トランザクションと外部キーと Bean Validation の説明を足した行、見出しを書き換えた2つの節、`Deps.Now` と `ResumeService` と `validate.go` の文の主語を足した行): 中身を変えていない書き方の直しである。言い換えた語(「変えた動きの一覧に載せる違い」「httpapi.New と paramErrorHandler」)で design.md を検索し、古い見出しの名前を指す箇所が残っていないことを見た。ほかの節には影響しない

### 実ファイルで確かめた文

- design.md ファイルの構成「`versions_test.go` の `TestJavaEnv_DevProfileAndOIDCEndpoints` は、`assertEnv` が環境の値の数も確かめるので、`TZ` を足さないと落ちる」: backend/compat/harness/versions_test.go 48-58行、60-71行。`JavaEnv` を呼ぶほかのテスト(208行、227行)は、数を確かめない / 合っていた
- design.md 本文の読み手「生成したコードが `runtime.BindJSONBody` を呼び、誤りのときは 400 と `errors` が空の答えにする」: backend/internal/httpapi/gen/api.gen.go 8818-8822行、backend/internal/httpapi/server.go 119-121行 / 合っていた
- design.md 本文の読み手「Go 版には要求を仕様書で検査する中間処理が無い」: backend/internal/httpapi/server.go 116行(strict の中間処理は `authRequestMiddleware` と `updateUserInfoMiddleware` だけ)、153-159行(外側の中間処理の並び)、backend/go.mod 82行(kin-openapi は間接の依存) / 合っていた
- design.md 本文の読み手「`BindJSONBody`(oapi-codegen/runtime v1.8.0 の `bindjson.go` 36-45行)は、`json.NewDecoder(r.Body).Decode` で最初の値だけを読む。余りは読まない。空の本文は誤りを返す」: 版は backend/go.mod 30行で合っていた。`bindjson.go` はリポジトリに無く(`*.go` を検索して該当なし)、ホストの Go のモジュールの置き場所にも無かったので、審査役は開けなかった。合っていたとも食い違っていたとも判定していない。食い違っていたときは、design が足した `resumes_test.go` の経路を通した場面(549行)が実装のときに見つける
- design.md テストの方針「本文の全体の扱いは、試作の P10 で Java 版が返したのと同じ答え」: .kiro/specs/backend-go-master-resumes/research.md 82行(余りは読まない。並び、`null`、空、文字列は 400 で `errors` は空) / 合っていた
- design.md 筋書き「本文の全体が並びか文字列の要求も送る」: backend/compat/harness/scenario.go 163-164行(`json` の欄は `any` で、並びと文字列を書ける。`null` は書けないが、design は並びと文字列だけを挙げている) / 合っていた
- design.md harness の節「段ごとに Java 版、Go 版の順に要求を送る(`compareenv.go` の段の繰り返し)。Go 版の応答を受けた時刻は、Java 版より、Go 版の段にかかった時間だけ遅い」: backend/compat/harness/compareenv.go 166-174行、180-183行、backend/compat/harness/compare.go 106行(版ごとの受けた時刻を `received` に写す)、backend/compat/harness/normalize.go 58-60行 / 合っていた
- design.md harness の節「初期のデータの固定の日時は、2つの版で同じ値」: backend/compat/harness/compareenv.go 144-148行(同じ初期のデータを、版ごとのデータベースに読み込む) / 合っていた
- design.md harness の節「前の段で保存した日時は、2つの版で同じ値」: backend/compat/harness/compareenv.go 144-148行、197-200行(データベースは版ごとに別で、前の段の日時は、版ごとにその版が書いた値である)。同じ値にはならない。実装する比べ方と幅には影響しない(D1-2-1)
- design.md API の説明画面「書き込みの操作は、`X-XSRF-TOKEN` が Cookie `XSRF-TOKEN` と合わないと 403。ブラウザの Cookie から値を読める。『Try it out』に `X-XSRF-TOKEN` の欄がある」: backend/internal/httpapi/middleware/csrf.go 19-21行、35-42行(ログインの要求は検査の対象の外で、Cookie が無ければそのときに発行する)、52-54行(HttpOnly を付けない)、backend/api/openapi.yaml 637-645行、880-885行、1399-1408行 / 合っていた
- design.md API の説明画面「compose の `api-docs`(ポート 8082)」「利用者の spec と同じ手順で利用者を作ってログインする」: compose.yaml 75-84行、.kiro/specs/backend-go-users/design.md 668-670行 / 合っていた
- design.md 安全「Go 版の土台は、JSON の要求の本文の大きさに上限を置いていない。上限があるのは `internal/httpapi/users.go` の `updateUserInfoMaxBody` だけ」: backend/internal/httpapi/users.go 24-25行、110-114行。backend の `*.go` を `MaxBytesReader` `LimitReader` で検索し、`internal` の下で要求の本文を限るのはこの1か所だけである / 合っていた
- design.md 安全「Java 版も、JSON の本文の大きさの上限を設定していない。`application.yaml` の `spring.servlet.multipart` の上限(2MB)は multipart の要求にだけかかる」: backend/src/main/resources/application.yaml 26-29行。backend/src/main の下に、本文の大きさを限るほかの設定(`maxPostSize` `max-http` など)は無い / 合っていた
- design.md 設計を見直すきっかけ・プロジェクトの決まり「depguard の規則は、機能のパッケージに `internal/auth` を読むことを許している」: 往復1で backend/.golangci.yml 43-57行を開いて確かめた文で、差分は文の場所を移しただけである / 合っていた

### 受入基準ごとの確かめ方

| 受入基準 | 確かめる道具 | 動かす場所 | 動かすのに要るもの | design の箇所 |
|---|---|---|---|---|
| 1.1 | `make compat` の `scenarios/resumes/` の compare の筋書き、`body_test.go` ほかの単体テスト、`resumes_test.go` の `httpapi.New` の経路を通した場面 | 開発環境の `backend-go` の領域の検査と CI の比べる検査 | user1 と user2(`basic.sql`)、`resume-ops.sql`、マスタの行。本文の全体の扱いは、経路に、余りのある本文、空の本文、並びと `null` と文字列の本文を送って確かめる。正解は research.md の P10 の Java 版の答えである | 「本文の読み手」の「本文の全体」、「マスタと経歴書の操作の筋書き」の入力の誤りの箇条、「テストの方針」の `resumes.go` の箇条 |
| 1.2 | 画面と同じ本文の compare の筋書きと、Playwright での `api-docs` の確認 | 開発環境の compose(`api-docs` 8082、`backend-go` 8081) | 利用者(利用者の spec の手順で作る)、ブラウザの Cookie `XSRF-TOKEN` から読む `X-XSRF-TOKEN` の値、経歴書の作成の答えの `id`(`resumeId` の欄に入れる) | 「API の説明画面での確認」 |
| 3.3 | `service_integration_test.go`(比べる検査では送らない)と、変えた動きの一覧の CB-047 | 結合テスト | ほかの利用者の、上限に達した経歴書 | 「経歴書の決まり」の最後の箇条、「マスタと経歴書の操作の筋書き」のほかの利用者の箇条、「変えた動きの一覧に載せる違い」 |
| 4.2 | compare の段ごとのデータベースの比べ方(`CompareDB`) | 比べる検査 | `resumes` の日時の列の `<wallclock>` の置き換え。固定の日時の行も5秒の幅で比べる | 「Java 版と Go 版を比べる検査の広げ方」 |
| 4.3 | `<wallclock:形:+秒>` の5秒の幅、`JavaEnv` の `TZ`、harness の単体テスト(5秒と6秒、9時間、形の違い、受けた時刻を2秒ずらした固定の日時) | 比べる検査と、harness の単体テスト | 版ごとの受けた時刻、`TZ=Asia/Tokyo`、`versions_test.go` の期待する値の書き換え | 「Java 版と Go 版を比べる検査の広げ方」、「ファイルの構成」の `versions_test.go`、「テストの方針」の harness の箇条 |
| 4.4 | CB-047〜050 と、`resumes_test.go` `service_integration_test.go` | 単体テストと結合テスト | 読めない項目の ID、退会した利用者 | 「Service」の「失敗したとき」、「変えた動きの一覧に載せる違い」 |
| 5.2 | `cross-resume.yaml` の日時の比べ、`store_integration_test.go` の日時の丸め、比べる検査の `<wallclock>` | CI の版をまたいで確かめる検査と結合テスト | `TZ=Asia/Tokyo` の Java 版(`JavaEnv`)、`Deps.Now` | 「読み書き」の日時の箇条、「Java 版と Go 版を比べる検査の広げ方」 |

### 申告

**1. 経歴書の操作の JSON の本文に、大きさの上限を置かない** — design.md「安全」の3つ目の箇条

- Issue の記載: なし
- 決めたこと: Go 版は、経歴書の操作の本文を、大きさを限らずに読む。Java 版も JSON の本文に上限を持たないので、同じ答えにするためである
- 他にありえた選択肢: Go 版に上限(たとえば名前と画像の変更と同じ 2MB)を置き、Java 版との違いを変えた動きの一覧に載せる
- 外れていた場合: ログインした利用者が大きな本文を送ると、Go 版はその全体をメモリに読む。あとで上限を置くときは、超えたときの答えを決め、変えた動きの一覧に足すことになる

### 指摘

| ID | レベル | 該当箇所 | 内容 | 直し方の案 |
|---|---|---|---|---|
| D1-2-1 | 低 | design.md「Java 版と Go 版を比べる検査の広げ方(harness)」の秒の差の2つ目の箇条(407行) | 「前の段で保存した日時」を、固定の日時と一緒に「2つの版で同じ値」と書いている。比べる検査は版ごとに別のデータベースを使い(compareenv.go 144-148行、197-200行)、前の段の日時は版ごとにその版が書いた値なので、同じ値ではない。1つ上の箇条(406行)の「どちらの版も、応答を受ける少し前の時刻を書く」とも合わない。この値の秒の差は、前の段と今の段で Go 版の段にかかった時間の違いほどになり、固定の日時の差より小さい。比べ方と5秒の幅と単体テストの場面は変わらないので、実装には影響しない | 407行から「前の段で保存した日時」を外し、「前の段で保存した日時: 版ごとに別の値で、秒の差は、前の段と今の段で Go 版の段にかかった時間の違いほどになる」の箇条を足す |

### 前の段階への指摘

無い。

- 往復: 2回で収束 / 未解決: 0件

## サイクル1 往復3(2026-11-14)

### 審査の範囲

範囲: 差分

- design.md「Java 版と Go 版を比べる検査の広げ方(harness)」の秒の差の3つの箇条(406-408行): 差分が、前の段で保存した日時を、その段で保存した日時の箇条に移し、固定の日時の箇条の理由を書き直し、5秒の幅の文を9時間の箇条にまとめた。同じ節の置き換え方(403行)と比べ方(404行)と段の順の文(405行)、「テストの方針」の harness の箇条(561行)、要件4の受入基準2と3、要件5の受入基準2と食い違わないかを見た。消した「5秒の幅の内側なら同じとみなす」の中身は、404行の比べ方に残っている
- design.md「Service」の `FOR UPDATE` の説明(242行): 差分が SQL の指定の説明を足した。同じ段落の「行の固定」の文と、「テストの方針」の同時の追加の場面(553行)と合っている。ほかの節には影響しない
- design.md「設計を見直すきっかけ」の depguard の箇条(55行): 差分が、利用者の spec が何を確かめると決めたかを書き足した。利用者の spec と認証の spec の設計の文と合うかを見た
- design.md「初期のデータ」の `resume-limits.sql` の箇条(464行): 差分が上限の数を消し、「経歴書の決まり(rules.go)」の節を指す形にした。その節の数の上限の箇条(304行)に7つの数が残っていることを見た。要件2の受入基準1の確かめ方は変わらない
- design.md「マスタと経歴書の操作の筋書き」の入力の誤りの箇条(436行): 差分が、本文が読めない要求を4つと数えて並べ直した。並べた要求は、直す前の括弧の中の4つと同じである
- design.md「テストの方針」の結合テストの箇条(551-552行): 差分が、括弧の中の説明を文にした。今ある結合テストの名前と動かし方と合うかを見た
- そのほかの差分(概要の4段落目、「処理の流れ」のコピーの順の文、「本文の読み手」のオブジェクトでない値の文、「経歴書の受け口」の `authErrorResponse` と `authJSON` の文、`resume-ops.sql` のパスワードの文): 文を分けたか、主語を足しただけで、中身は変わっていない。ほかの節には影響しない

### 実ファイルで確かめた文

- design.md harness の節「Java 版と Go 版を比べる検査は、版ごとに別のデータベースを使う(`compareenv.go` の `Stores`)」: backend/compat/harness/compareenv.go 26-27行、79-85行(版ごとに `startStore` を呼ぶ)、197-200行、backend/compat/harness/stack.go 77-78行(版の名前を付けた別のホストの Postgres) / 合っていた
- design.md harness の節「どちらの版も、自分のデータベースに、応答を受ける少し前の自分の時刻を書く」「秒は、その版の応答を受けた時刻を引いた秒数」: backend/compat/harness/send.go 133行(応答を読み終えた時刻を `Received` に入れる)、backend/compat/harness/compare.go 72-74行、106行(版ごとの `Received` を版ごとの `received` に写す) / 合っていた
- design.md harness の節「Java 版と Go 版を比べる検査は、2つの版のデータベースに同じ初期のデータを入れる。秒の差は、Java 版の応答を受けてから Go 版の応答を受けるまでの時間になる」: backend/compat/harness/compareenv.go 144-148行(同じ `s.Fixtures` を版ごとのデータベースに読み込む)、166-174行(段ごとに Java 版、Go 版の順に送る)、backend/compat/harness/fixtures.go 47-59行 / 合っていた
- design.md 設計を見直すきっかけ「認証の spec の設計は、ほかのまとまりのパッケージが `internal/auth` を読まず、`internal/platform/authctx` だけを読むと決めている」: .kiro/specs/backend-go-auth/design.md 47行 / 合っていた
- design.md 設計を見直すきっかけ「利用者の spec は、depguard の規則で機能のパッケージに `internal/auth` を読むことを許し、認証の spec の設計のこの決まりを守るかどうかを、まとまりごとの spec の設計で確かめると決めた」: .kiro/specs/backend-go-users/design.md 56行、559行 / 合っていた
- design.md テストの方針「結合テストは、名前が `_integration_test.go` で終わるファイルに書き、testcontainers-go で動かす PostgreSQL に Java 版のマイグレーションを当ててから動く」: backend/internal/users/main_integration_test.go 16-18行、63-68行、85-93行(`backend.Migrations()` を `migrate.Run` で流す)、backend/internal/auth と backend/internal/users の `*_integration_test.go` の一覧 / 合っていた
- design.md 処理の流れ「経歴書をコピーして作るときの順は、`CopyCreateResumeUseCase` のとおり、上限、名前の重なり、コピー元の読み出し、利用者のものかの確認」: 往復1で CopyCreateResumeUseCase.java 50-66行を開いて確かめた文で、差分は主語を足しただけである / 合っていた
- design.md 本文の読み手「`BindJSONBody` が渡した最初の値がオブジェクトでなければ、読めない」: 往復2で確かめた文で、差分は括弧の中を別の文に出しただけである。`bindjson.go` を審査役が開けなかったことは、往復2の記録のとおりで変わらない

### 受入基準ごとの確かめ方

| 受入基準 | 確かめる道具 | 動かす場所 | 動かすのに要るもの | design の箇所 |
|---|---|---|---|---|
| 4.2 | compare の段ごとのデータベースの比べ方(`CompareDB`) | 比べる検査 | 版ごとのデータベース(`Stores`)、`resumes` の日時の列の `<wallclock>` の置き換え。その段と前の段で保存した行も、固定の日時の行も、5秒の幅で比べる | 「Java 版と Go 版を比べる検査の広げ方」の比べ方と秒の差の箇条 |
| 4.3 | `<wallclock:形:+秒>` の5秒の幅、`JavaEnv` の `TZ`、harness の単体テスト(5秒と6秒、9時間、形の違い、受けた時刻を2秒ずらした固定の日時) | 比べる検査と、harness の単体テスト | 版ごとの受けた時刻、`TZ=Asia/Tokyo`、`versions_test.go` の期待する値の書き換え | 「Java 版と Go 版を比べる検査の広げ方」、「テストの方針」の harness の箇条 |
| 5.2 | `cross-resume.yaml` の日時の比べ、`store_integration_test.go` の日時の丸め(`.1234565` が `.123457`)、比べる検査の `<wallclock>` | CI の版をまたいで確かめる検査と結合テスト | `TZ=Asia/Tokyo` の Java 版(`JavaEnv`)、`Deps.Now`、Java 版のマイグレーションを当てた testcontainers-go の PostgreSQL | 「読み書き」の日時の箇条、「Java 版と Go 版を比べる検査の広げ方」、「テストの方針」の結合テストの箇条 |
| 2.1 | `limits.yaml` と `rules_test.go` | 比べる検査と単体テスト | `resume-limits.sql`(上限の数は「経歴書の決まり」の節の7つの数) | 「初期のデータ」、「経歴書の決まり(rules.go)」の数の上限の箇条 |

### 申告

この往復の差分に、新しく決めたことは無い。

### 指摘

無い。

| ID | レベル | 該当箇所 | 内容 | 直し方の案 |
|---|---|---|---|---|

### 前の段階への指摘

無い。

- 往復: 3回で収束 / 未解決: 0件

## サイクル2 往復1(2026-11-14)

### 審査の範囲

範囲: 差分

- design.md「Java 版の答えの正解のファイル(testdata)」の節(新しい節、403-424行)と、「作るもの」(21行)、「ファイルの構成」の2つの `testdata/`(121-122行)、「テストの方針」の単体テストの箇条(581-590行、598行): 差分が、正解のファイルの中身と作り方を足し、試作の件数で確かめる文を、正解のファイルのすべての入力で確かめる文に替えた。research.md の「確かめた環境」(9-13行)と P4、P5、P8、P9、P10〜P12 の節(37-85行)と「危うい点と備え」(143行)、要件1の受入基準1、要件6の受入基準1と2と食い違わないかを見た
- design.md「Service」の「作成と変更の操作が返す経歴書の日時」(247-251行)と、「経歴書の受け口」の日時の箇条(369行)、「テストの方針」の `resumes.go` の日時の箇条(596行)と `service.go` の結合テストの9つ目(613行): 差分が、どの操作のどの日時が丸める前の値かを足した。「読み書き」の日時の箇条(342行)、「データの形」の経歴書の答えの例(548-549行)、research.md の P2(44-46行)、Java 版のコード、要件1の受入基準1と要件5の受入基準2と食い違わないかを見た
- design.md「Java 版と Go 版を比べる検査の広げ方(harness)」の移し替えの段落(441行)と `make compat` の段落(443行)、「ファイルの構成」の `backend/compat/` の3つのファイル(148行)、「テストの方針」の harness の箇条の最後の文(623行): 差分が、移す先を経歴書の復元に決めた。3つのファイルと、API の仕様書と、未実装の答えのコードを開いて確かめた
- design.md「マスタと経歴書の操作の筋書き」の `TestCrossRoute_ResumeSteps` の段落(488行)と、「ファイルの構成」の `backend/compat/harness/cross_test.go`(147行)、「テストの方針」の版をまたいで確かめる検査の箇条(621行): 差分がテストを足した。同じ節の `cross-resume.yaml` の5つの段(482-486行)と、要件5の受入基準1から3に効く
- design.md「進み具合の表」の節(523-527行): 差分が、状態の書き換えの順と、別の PR を足した。`progress.md` と `coverage.go` と CI のワークフローと、要件6の受入基準3と、同じ節の「マスタと経歴書の操作の筋書き」(要件4の受入基準1)に効く
- design.md「試作の記録」の節の最後の2文(401行): 差分が、UTF-8 として誤ったバイトを含む本文を確かめる時期と、同じにできないときに止まることを足した。要件6の受入基準2と research.md 143行に効く
- design.md「テストの方針」の `validate.go` `order.go` `errors.go` の箇条(588行、590行、591行)、`resumes.go` の8つの場合(593-600行)、`service.go` の結合テストの11の場合(605-615行)、「ファイルの構成」の `errors_test.go`(117行): 差分が、確かめる場合を足し、1つずつの箇条に分けた。足した場合ごとに、design のほかの節(「処理の流れ」「Service」「マスタの読み出し」「入力の検査」「httpapi.New」「変えた動きの一覧に載せる違い」)に同じ動きが書かれているかを見た
- design.md「プロジェクトの決まりを守っているか」の品質チェックの設定(68行)、「仕様書の変更」の消した箇条、「データベースの表」の消した文(533行): 差分が、ほかの節と重なる文を消した。消した中身が、「作らないもの」(34-35行)と「本文の読み手」の「本文の全体」(279行)と「プロジェクトの決まりを守っているか」(66行)に残っていることを見た。ほかの節には影響しない
- そのほかの差分(99行、216行、245行、266行、490行、508行): 主語を足したか、文を分けただけで、中身は変わっていない。ほかの節には影響しない

### 実ファイルで確かめた文

- design.md harness の節「`backend/compat/` の `compat_test.go`、`cross_test.go`、`perf_test.go` は、未実装の答えを確かめるために、経歴書の削除の要求(`DELETE /api/resumes/00000000-0000-4000-8000-000000000201` と `csrf: true`)を使う」: backend/compat/compat_test.go 105-107行、backend/compat/cross_test.go 202-205行、backend/compat/perf_test.go 28-30行。`backend/compat` の `*.go` で、この経路を使うのはこの3か所だけである / 合っていた
- design.md harness の節「経歴書の復元は、バックアップのまとまりの操作であり、この spec のあとも未実装のまま残る、偽の送信の検査が働く書き込みの操作である」: backend/compat/harness/operations.go 123-124行(`restoreResume` は `GroupBackup`)、backend/api/openapi.yaml 665-693行(`XsrfTokenHeader` と `XsrfTokenCookie` を持つ POST)、backend/internal/httpapi/unimplemented.go 97-100行(`ErrNotImplemented` を返す)。Issue #772 の26の操作に `restoreResume` は無い / 合っていた
- design.md harness の節「生成したコードは本文を読んでから受け口を呼ぶ」: backend/internal/httpapi/gen/api.gen.go 1266-1267行(本文の型は `ResumeBackup`)、4939-4942行(`RestoreResumeRequestObject` の `Body`)、backend/api/openapi.yaml 677-682行(`requestBody` は `required: true` の JSON) / 合っていた
- design.md 筋書きの節「手本は、同じファイルの `TestCrossRoute_UserSteps` である」「`modes` に `cross` を書いた筋書きを読み」: backend/compat/harness/cross_test.go 175-248行(`LoadScenarios(dir, ModeCross)` で読み、筋書きのファイルが無ければ失敗し、2つの向きで `CrossRoute` を確かめる)、backend/compat/harness/scenario.go 22-23行、46行、254行 / 合っていた
- design.md テストの方針「`TestCrossRoute_ResumeSteps` で確かめる」(CI で動くか): backend/Makefile 127-128行(`make compat` は `./compat/...` を `-skip '^Test(Cross|Perf)_'` で流す。`TestCrossRoute_` は `TestCross` のあとが `_` でないので、飛ばされずに `make compat` で動く)、.github/workflows/ci.yaml 505-506行 / 合っていた
- design.md 進み具合の表の節「状態の列を『未着手』から直接『作り終えた』にする」: .kiro/specs/backend-go-replacement/progress.md 30行(状態の名前)、38行(今は spec の列が「未定」、状態の列が「未着手」)、backend/compat/harness/coverage.go 17-19行(知っている状態に順の決まりは無い) / 合っていた
- design.md 進み具合の表の節「状態を『作り終えた』にすると、`TestCoverage_Operations` が、group 3 の26の操作がすべて筋書きに1回以上出てくることを求め始める」: backend/compat/compat_test.go 64-89行、backend/compat/harness/coverage.go 17行、113-140行 / 合っていた
- design.md 進み具合の表の節「Java 版と Go 版を比べる検査は、この spec の PR の必須のチェックであり、通らなければ PR はマージされない」: .github/workflows/ci.yaml 474-476行(`backend-compat`)、505-509行(`make compat` と `make compat-cross`)、520-543行(必須のチェック `backend-test` が `backend-compat` の結果を判定する)、.github/audit/required-checks.json 4行(`backend-test`) / 合っていた
- design.md Service の節「Java 版は、作成と変更の答えに、`LocalDateTime.now()` の丸める前の値を返す」「変更の答えの作成の日時は、データベースから読んだ値」: backend/src/main/java/com/example/keirekipro/domain/model/resume/Resume.java 139-140行(作成は `createdAt` と `updatedAt` の両方に `LocalDateTime.now()`)、226行ほか(変更は `this.createdAt` をそのまま持ち、`updatedAt` だけを `LocalDateTime.now()` にする)、backend/src/main/java/com/example/keirekipro/usecase/resume/UpdateCareerUseCase.java 42行、64-68行(データベースから読んだ経歴書を変え、保存に渡した値をそのまま答えにする)、CopyCreateResumeUseCase.java 126-141行、research.md 44-45行 / 合っていた
- design.md testdata の節「research.md の『確かめた環境』と同じ設定(`spring` のコンテナ、データベース `keireki_proto`、Redis の DB 7。`keireki_pro` と DB 0 に触れない)」「試作で Java 版に送った入力はリポジトリに入っていない」: .kiro/specs/backend-go-master-resumes/research.md 11-13行、compose.yaml 15行(`spring`)、145行(`keireki_pro`)、158-159行(`redis`) / 合っていた
- design.md testdata の節「research.md の P4、P5、P8、P9、P10〜P12 の節」: research.md 37-40行(P8)、54-62行(P4、P5)、69-75行(P9)、77-85行(P10〜P12) / 合っていた
- design.md テストの方針「作業の工程の真偽の欄が無いときの文言が『null は許可されていません』」: research.md 83行(Java 版の答えで確かめた文言) / 合っていた
- design.md テストの方針「`resumes.go` の単体テストが、Go 版の起動で26の操作が受け口につながることを確かめる」: backend/cmd/keirekipro/main.go 162行、184-191行、backend/cmd/keirekipro/main_test.go 855-858行。入口が処理を受け口に渡すことを確かめる今のテスト `TestRun_PassesUserHandlers` は `main_test.go` にあり、`internal/httpapi` のテストからは `main.go` を確かめられない。食い違いではなく、書き方があいまいである(D2-1-1)

### 受入基準ごとの確かめ方

| 受入基準 | 確かめる道具 | 動かす場所 | 動かすのに要るもの | design の箇所 |
|---|---|---|---|---|
| 1.1 | `jackdate_test.go` `javauuid_test.go` `link_test.go` `body_test.go` `order_test.go`(正解のファイルのすべての入力で比べる)、`resumes_test.go` の本文の全体の扱いと日時の書き方の場面、`service_integration_test.go` の日時の場面、`make compat` の筋書き | 開発環境の `backend-go` の領域の検査と CI の `backend-go` と `backend-compat` | `internal/resume/testdata/` の6つの正解のファイルと `internal/httpapi/testdata/resumebody/` の正解のファイル。作るのに要るものは、開発環境の `spring` のコンテナの中の別の Java 版、データベース `keireki_proto`、Redis の DB 7、research.md の節の書き方と値の種類である。日時は、`.1234565` 秒を返す `Now` | 「Java 版の答えの正解のファイル(testdata)」、「Service」の「作成と変更の操作が返す経歴書の日時」、「テストの方針」の単体テストと結合テストの箇条 |
| 4.1 | `scenarios/resumes/` の筋書きと `TestCoverage_Operations` | 開発環境と CI の `make compat` | `progress.md` の状態の列を、筋書きを書き終える時点で「作り終えた」にすること | 「進み具合の表」の2つ目の段落 |
| 4.3 | harness の単体テストと、今ある認証と利用者の筋書きでの `make compat`、経歴書の復元で 501 を確かめる3つのファイルのテスト | 開発環境と CI の `make compat` `make compat-cross`、開発環境の `make compat-perf` | 本文 `{}` と `csrf: true` を付けた `POST /api/resumes/restore`。経歴書の受け口を経路につなぐ前に替えること | 「Java 版と Go 版を比べる検査の広げ方」の移し替えの段落と `make compat` の段落、「テストの方針」の harness の箇条 |
| 5.1 | `cross-resume.yaml` と `make compat-cross`、`TestCrossRoute_ResumeSteps` | CI の `make compat-cross`。`TestCrossRoute_ResumeSteps` は `make compat` で動く | `scenarios/resumes/` の `modes` に `cross` を書いた筋書き。`expect.values` を持つ段と、その前の変える段 | 「マスタと経歴書の操作の筋書き」の `cross-resume.yaml` の5つの段と `TestCrossRoute_ResumeSteps` の段落 |
| 5.2 | `cross-resume.yaml` の日時の `expect.values`、`service_integration_test.go` の日本の時刻の場面と `.1234565` の場面、`store_integration_test.go` の丸めの場面 | CI の `make compat-cross` と結合テスト | 保存した版の `GET` の答えから取り出した日時(データベースから読んだマイクロ秒の値)、日本の時間帯でない時刻を返す `Now` | 「マスタと経歴書の操作の筋書き」の2つ目と3つ目の段、「Service」の日時の箇条、「テストの方針」の結合テストの箇条 |
| 5.3 | `cross-resume.yaml` の5つの段と `TestCrossRoute_ResumeSteps` | CI の `make compat-cross` と `make compat` | 2つの向きの送り先の組 | 「マスタと経歴書の操作の筋書き」、「テストの方針」の版をまたいで確かめる検査の箇条 |
| 6.1 | research.md の「試作の記録」と、実装のはじめの UTF-8 として誤ったバイトを含む本文の確かめの書き足し | 設計の前に済んでいる。書き足しは開発環境の別の Java 版 | 誤ったバイトを文字列の欄と技術スタックの並びの欄に入れた本文 | 「試作の記録(research.md)」、「Java 版の答えの正解のファイル(testdata)」の表の6つ目 |
| 6.2 | 所有者への報告(同じ答えにできないと分かったとき) | 実装のはじめ | 無い | 「試作の記録(research.md)」の最後の文 |
| 6.3 | `progress.md` のマスタと経歴書の行 | この spec の PR の差分と、マージのあとの別の PR の差分 | この spec の PR のマージを確かめること。main から作る新しい featureブランチ | 「進み具合の表」の1つ目と3つ目の段落 |

### 申告

**1. 正解のファイルの入力を作り直し、件数を試作と同じにしない** — design.md「Java 版の答えの正解のファイル(testdata)」

- Issue の記載: なし
- 決めたこと: 試作の入力がリポジトリに無いので、research.md の節に書いた書き方と値の種類をすべて含む入力を、実装のはじめに作り直し、Java 版をもう1つ動かして答えを控える。件数は試作(年月と日付 103件、ID 36件、リンク 57件)と同じでなくてよい
- 他にありえた選択肢: 試作と同じ件数になるまで入力を足す。または、設計の段階で入力を作り直して正解のファイルを先に控える
- 外れていた場合: 試作で Java 版と比べた書き方のうち、research.md の文に種類として書かれていないものが正解のファイルから落ちる。その書き方で Go 版が Java 版と違っても、単体テストでは見つからない

**2. UTF-8 として誤ったバイトを含む本文を、実装のはじめに確かめ、同じにできなければ止まる** — design.md「試作の記録(research.md)」

- Issue の記載: なし
- 決めたこと: 設計の前には確かめず、実装のはじめに Java 版の答えを控える。Java 版と同じ答えにできないと分かったら、要件6の受入基準2のとおりに止まって所有者に報告する
- 他にありえた選択肢: 設計の承認の前に確かめる。または、research.md の「危うい点と備え」のとおり、違いを変えた動きの一覧に足して報告する
- 外れていた場合: 実装の途中で止まり、所有者の判断を待つことになる。本文の読み手の設計(`encoding/json` の `Token` で読む)を直すことになれば、design の承認を取り消すことになる

**3. 「比べる検査に通った」を、この spec の PR のマージのあとの別の PR で書く** — design.md「進み具合の表」

- Issue の記載: なし
- 決めたこと: この spec の PR では状態を「未着手」から直接「作り終えた」にし、マージを確かめたあとに、main から新しい featureブランチを作って「比べる検査に通った」にする PR を出す
- 他にありえた選択肢: この spec の PR の中で、CI の比べる検査が通ったあとに書く。または、認証と利用者のまとまり(progress.md 36-37行)と同じく「作り終えた」のままにする
- 外れていた場合: PR が1つ増える。マージのあとに会話が途切れると、状態が「作り終えた」のまま残る。実装の間、main の表のマスタと経歴書の行は「未着手」のままに見える

**4. 未実装の答えを確かめる検査の要求を、経歴書の復元に移す** — design.md「Java 版と Go 版を比べる検査の広げ方(harness)」

- Issue の記載: なし
- 決めたこと: `POST /api/resumes/restore` に本文 `{}` と `csrf: true` を付けて送り、501 を期待する
- 他にありえた選択肢: 出力のまとまりの操作に移す。または、未実装の操作に頼らない確かめ方に書き直す
- 外れていた場合: バックアップのまとまりの spec で経歴書の復元を作るときに、同じ3つのファイルをもう一度書き直す

### 指摘

| ID | レベル | 該当箇所 | 内容 | 直し方の案 |
|---|---|---|---|---|
| D2-1-1 | 低 | design.md「テストの方針」の `resumes.go` の単体テストの8つ目(600行) | 「Go 版の起動で26の操作が受け口につながること」は、`resumes.go` の単体テスト(`internal/httpapi`)の場合として書かれている。`internal/httpapi` のテストが確かめられるのは、`httpapi.New` に `ResumeHandlers` を渡したときに26の操作が未実装の答えでなくなることまでで、入口 `main.go` が `ResumeHandlers` を渡すことは確かめられない。利用者のまとまりは、これを `backend/cmd/keirekipro/main_test.go` の `TestRun_PassesUserHandlers`(855-858行)で確かめており、`main_test.go` は design の「ファイルの構成」に無い。`main.go` が渡し忘れたときは、`make compat` の筋書きが Go 版の 501 として見つけるので、実装には影響しない | 「`httpapi.New` に `ResumeHandlers` を渡すと、26の操作が未実装の答えでなくなること」と書き直す。入口も単体テストで確かめるなら、「Claude が変えるファイル」に `backend/cmd/keirekipro/main_test.go` を足す |
| D2-1-2 | 低 | design.md「Java 版と Go 版を比べる検査の広げ方(harness)」の移し替えの段落(441行) | `backend/compat/compat_test.go` は、筋書きの要求のほかに、操作の名前 `deleteResume` と段の名前 `delete-with-token` を、`TestSelf_OneCharFakeFails`(161行、165行)と `TestSelf_MatchedDiffPasses`(178行)で確かめている。要求を経歴書の復元に替えると、操作の名前は `restoreResume` になる。design は要求の替え方だけを書き、この3か所に触れていない。同じファイルの中であり、直さなければそのテストが失敗して分かるので、実装には影響しない | 「同じファイルの、操作の名前 `deleteResume` を確かめる箇所も `restoreResume` に替える」の1文を足す |
| D2-1-3 | 低 | design.md「進み具合の表」の1つ目と3つ目の段落(523行、527行) | 1つ目の段落は「この spec の PR は1つであり」と書き、3つ目の段落は、状態を「比べる検査に通った」にする PR を別に出すと書く。PR は2つになる。読めば、1つ目の段落の PR が26の操作を作る PR を指すと分かるので、実装には影響しない | 1つ目の段落を「26の操作を作る PR は1つであり」の形にする |
| D2-1-4 | 低 | design.md「試作の記録(research.md)」の最後の文(401行)と research.md「危うい点と備え」の1つ目(143行) | design は、UTF-8 として誤ったバイトを含む本文で Java 版と同じ答えにできないときは止まって所有者に報告すると書く。research.md は「違えば、Java 版と同じ答えにするか、変えた動きの一覧に足して所有者に報告する」と書いたままである。design のほうが要件6の受入基準2に沿っており、実装は design に従うので、実装には影響しない | 実装のはじめに research.md に答えを書き足すときに、143行の進め方も design と同じに直す |

### 前の段階への指摘

無い。

- 往復: 1回で収束 / 未解決: 0件

## サイクル2 往復2(2026-11-14)

### 審査の範囲

範囲: 差分

- design.md「ファイルの構成」の `backend/cmd/keirekipro/main_test.go`(141行)、「main.go」の節の2つ目の段落(398行)、「テストの方針」の `resumes.go` の8つ目(603行)と `main.go` の行(605行): 差分が、入口のテスト `TestRun_PassesResumeHandlers` を足し、`internal/httpapi` のテストが確かめる範囲を書き直した。語 `main_test` `TestRun_Passes` `ResumeHandlers` で design.md を検索し、「httpapi.New と paramErrorHandler」の節(386行)、「経歴書の受け口」の表の経歴書の一覧の答え(359行)、「Service」の退会してすでに居ない利用者の箇条(259行)と食い違わないかを見た。要件1の受入基準2に効く
- design.md「Java 版と Go 版を比べる検査の広げ方(harness)」の移し替えの段落(444行): 差分が、段の名前と操作の名前の替え方を足した。語 `delete-with-token` `deleteResume` `restoreResume` で design.md と `backend/` を検索し、「ファイルの構成」の3つのファイルの行(149行)と食い違わないかを見た。要件4の受入基準3に効く
- design.md「マスタと経歴書の操作の筋書き」の `cross-resume.yaml` の3つ目の段(487行): 差分が主語を足しただけで、中身は変わっていない。ほかの節には影響しない
- research.md「危うい点と備え」の1つ目(143行): design.md の差分には出ないが、前の往復の D2-1-4 の直しなので、design.md「試作の記録(research.md)」の最後の文(404行)と要件6の受入基準2と合うかを見た
- 語 `main_test` `restore-with-token` で requirements.md を検索し、該当は無かった。前の段階の本文には影響しない

### 実ファイルで確かめた文

- design.md main.go の節「手本は、同じファイルの `TestRun_PassesUserHandlers` である」「入口を起動し、ログインした利用者の要求が、未実装の答えでなく答えられることを確かめる」: backend/cmd/keirekipro/main_test.go 855-937行(マイグレーションを当て、利用者の行を足し、`auth.New(...).IssueAccessToken` でログインの状態の値を作り、`newHarness` と `start` で入口を起動して、Cookie `accessToken` を付けた `GET /api/users/me` を送る)。同じ作り方で `GET /api/resumes` を送れる / 合っていた
- design.md main.go の節「`internal/httpapi` のテストは `httpapi.New` に自分で `ResumeHandlers` を渡すので、`main.go` が渡し忘れても通ってしまう」: backend/cmd/keirekipro/main.go 183-194行(`httpapi.Options` を組み立てるのは入口だけで、今は `ResumeHandlers` の欄が無い)、backend/internal/httpapi/server.go の `Options`(前の往復までに確かめた) / 合っていた
- design.md ファイルの構成「`main_test.go` にテストを足す」(今あるテストが、経歴書の受け口をつないだあとも通るか): backend/cmd/keirekipro/main_test.go 766-779行(ログインしていない `GET /api/resumes` に 401 を期待する)、782-808行(受け付けないログインの状態の値を付けた `POST /api/resumes` に 403 と 401 を期待する)。どちらも、ログインの検査と偽の送信の検査が受け口より前で答えるので、経歴書の受け口をつないでも答えは変わらない / 合っていた
- design.md harness の節「3つのファイルの段の名前 `delete-with-token`」: backend/compat/compat_test.go 105行、backend/compat/cross_test.go 202行、backend/compat/perf_test.go 28行。`backend/` の下で、この段の名前を持つのはこの3つのファイルだけである / 合っていた
- design.md harness の節「`compat_test.go` で、検査が報告した違いの段の名前と操作の名前 `deleteResume` を確かめる箇所と、テストが違いを許す範囲として書いた match の操作の名前」: backend/compat/compat_test.go 161-162行(`d.Step.Name` と `d.Step.Operation`)、165行(報告の文に `deleteResume` があること)、178行(`harness.Matches` の `Operation`)。`backend/compat` の `*.go` で `deleteResume` を使うのはこの4行だけで、`cross_test.go` と `perf_test.go` は操作の名前を確かめていない / 合っていた
- design.md harness の節「経歴書の復元の操作の名前 `restoreResume`」: backend/compat/harness/coverage_test.go 158行(`POST /api/resumes/restore` は `restoreResume` に当たる)、backend/compat/harness/operations.go 123行 / 合っていた
- research.md 143行「実装のはじめに確かめる。違えば、Java 版と同じ答えにする。同じ答えにできなければ、要件6の受入基準2のとおりに止まり、所有者に報告する」: design.md 404行と同じ進め方である。今あるものについての文(Go の `encoding/json` は誤ったバイトを U+FFFD に置き換える)は、前の往復から変わっていない / 合っていた

### 受入基準ごとの確かめ方

| 受入基準 | 確かめる道具 | 動かす場所 | 動かすのに要るもの | design の箇所 |
|---|---|---|---|---|
| 1.2 | `main_test.go` の `TestRun_PassesResumeHandlers`(入口が経歴書の処理を受け口に渡すこと)、`resumes_test.go` の「`httpapi.New` に `ResumeHandlers` を渡すと、26の操作の要求が受け口に届くこと」の場面、画面と同じ本文の compare の筋書き、Playwright での `api-docs` の確認 | 開発環境の `backend-go` の領域の検査(`make check`)と CI の `backend-go` | testcontainers-go の Postgres と Valkey(`main_test.go` の `TestMain` が今も動かしている)、Java 版のマイグレーション、利用者の行、`IssueAccessToken` で作るログインの状態の値。どれも手本の `TestRun_PassesUserHandlers` にある | 「main.go」の節の2つ目の段落、「ファイルの構成」の `main_test.go`、「テストの方針」の `resumes.go` の8つ目と `main.go` の行 |
| 4.3 | 経歴書の復元で 501 を確かめる3つのファイルのテスト(`TestSelf_SameImageNoDiff` `TestSelf_OneCharFakeFails` `TestSelf_MatchedDiffPasses` `TestCross_SelfPairPasses` `TestPerf_SelfPairRuns`) | 開発環境と CI の `make compat` `make compat-cross`、開発環境の `make compat-perf` | 段の名前 `restore-with-token`、操作の名前 `restoreResume`(`compat_test.go` の4行)、本文 `{}` と `csrf: true` を付けた `POST /api/resumes/restore` | 「Java 版と Go 版を比べる検査の広げ方」の移し替えの段落、「ファイルの構成」の3つのファイルの行 |
| 6.2 | 所有者への報告(同じ答えにできないと分かったとき) | 実装のはじめ | 無い | 「試作の記録(research.md)」の最後の文。research.md 143行も同じ進め方になった |

### 申告

この往復の差分に、新しく決めたことは無い。

### 指摘

| ID | レベル | 該当箇所 | 内容 | 直し方の案 |
|---|---|---|---|---|
| D2-2-1 | 低 | design.md「Java 版と Go 版を比べる検査の広げ方(harness)」の移し替えの段落(444行) | 3つのファイルの筋書きの前の説明の文(backend/compat/compat_test.go 92-93行、backend/compat/cross_test.go 189-190行、backend/compat/perf_test.go 15行)は、「Go 版の経歴書の操作はまだ 501 を返すので」と書いている。この spec のあとは、501 を返すのは経歴書の復元であり、経歴書の操作ではない。design は、段の名前と操作の名前の替え方までを書き、この説明の文に触れていない。テストの結果は変わらないので、実装には影響しない | 「3つのファイルの筋書きの前の説明の文も、経歴書の復元がまだ 501 を返すことに合わせて直す」の1文を足す |

### 前の段階への指摘

無い。

- 往復: 2回で収束 / 未解決: 0件

## サイクル3 往復1(2026-11-14)

### 審査の範囲

範囲: 差分

- 審査役: サイクル2 往復2 の審査役(Fable)が使用量の上限で止まったため、Opus の審査役として、同じ材料(起動の文の差分と、research.md 143行の直し)で審査し直した。サイクル2 往復2 の節は書き換えていない。その節の判定には頼らず、実ファイルを開き直して確かめた
- design.md「ファイルの構成」の `backend/cmd/keirekipro/main_test.go`(141行)、「main.go」の節の2つ目の段落(398行)、「テストの方針」の `resumes.go` の8つ目(603行)と `main.go` の行(605行): 差分が、入口のテスト `TestRun_PassesResumeHandlers` を足し、`internal/httpapi` のテストが確かめる範囲を書き直した(D2-1-1 の直し)。語 `ResumeHandlers` `main_test` で design.md を検索し、「httpapi.New と paramErrorHandler」の節(386行)、「経歴書の受け口」の表の経歴書の一覧の答え(359行)、「Service」の退会してすでに居ない利用者の箇条(259行)と食い違わないかを見た。要件1の受入基準2に効く
- design.md「Java 版と Go 版を比べる検査の広げ方(harness)」の移し替えの段落(444行): 差分が、段の名前と操作の名前の替え方を足した(D2-1-2 の直し)。語 `restore` `復元` `501` で design.md を検索し、「ファイルの構成」の3つのファイルの行(149行)と「テストの方針」の harness の箇条の最後の文(627行)と食い違わないかを見た。語 `delete-with-token` `deleteResume` で `backend/compat` を検索し、替える箇所の漏れが無いかを見た。要件4の受入基準3に効く
- design.md「マスタと経歴書の操作の筋書き」の `cross-resume.yaml` の3つ目の段(487行): 差分が主語を足しただけで、中身は変わっていない。ほかの節には影響しない
- research.md「危うい点と備え」の1つ目(143行): design.md の差分には出ないが、D2-1-4 の直しなので、design.md「試作の記録(research.md)」の最後の文(404行)と、要件6の受入基準2(requirements.md 173行)と合うかを見た
- 語 `main_test` `restore` `ResumeHandlers` `delete-with-token` で requirements.md を検索し、該当は無かった。前の段階の本文には影響しない

### 実ファイルで確かめた文

- design.md main.go の節「手本は、同じファイルの `TestRun_PassesUserHandlers` である」: backend/cmd/keirekipro/main_test.go 855-937行(新しいデータベースに `backend.Migrations()` を `migrate.Run` で当て、`sqlcgen.UpsertUser` で利用者の行を足し、`auth.New(...).IssueAccessToken` でログインの状態の値を作り、`newHarness` と `start` で入口を起動して、Cookie `accessToken` を付けた `GET /api/users/me` を送り、状態の番号と本文を確かめる)。同じ作り方で、経歴書を持たない利用者の `GET /api/resumes` を送れる。ファイルにビルドの条件(build タグ)は無く、`make check` のテストで動く(1行) / 合っていた
- design.md main.go の節「`internal/httpapi` のテストは `httpapi.New` に自分で `ResumeHandlers` を渡すので、`main.go` が渡し忘れても通ってしまう」: backend/cmd/keirekipro/main.go 184-194行(`httpapi.Options` を組み立てるのは入口で、今は `AuthHandlers` と `UserHandlers` までを渡す)、backend/internal/httpapi/server.go 96-112行(`Options` の受け口が無ければ、その操作は `Handlers` か未実装の答えになる) / 合っていた
- design.md main.go の節「200 と空の並び」: design.md 359行(経歴書の一覧の答えは `{"resumes":[...]}`)、259行(利用者の行と経歴書の行を利用者の ID で組にして読む)。経歴書を持たない利用者では `{"resumes":[]}` になる。今あるテストとの関係では、backend/cmd/keirekipro/main_test.go 766-808行のログインしていない `GET /api/resumes`(401)と受け付けない値の `POST /api/resumes`(403、401)は、server.go 153-159行の中間処理(ログインの状態を読む段、偽の送信の検査、ログインを求める段)が受け口より前で答えるので、経歴書の受け口をつないでも変わらない / 合っていた
- design.md harness の節「3つのファイルの段の名前 `delete-with-token`」: backend/compat/compat_test.go 105行、backend/compat/cross_test.go 202行、backend/compat/perf_test.go 28行。`backend/compat` の `*.go` で、この段の名前を持つのはこの3か所と、compat_test.go 161-162行の確かめだけである / 合っていた
- design.md harness の節「`compat_test.go` で、検査が報告した違いの段の名前と操作の名前 `deleteResume` を確かめる箇所と、match の操作の名前」: backend/compat/compat_test.go 161-162行(`d.Step.Name` と `d.Step.Operation`)、165行(報告の文に `deleteResume` があること)、178行(`harness.Matches` の `Operation`)。`cross_test.go` と `perf_test.go` は操作の名前を確かめていない(cross_test.go 211-240行、perf_test.go 33-65行) / 合っていた
- design.md harness の節「経歴書の復元の操作の名前 `restoreResume`」「この spec のあとも未実装のまま残る、偽の送信の検査が働く書き込みの操作」: backend/api/openapi.yaml 665-668行(`POST /api/resumes/restore` の operationId は `restoreResume`)、backend/compat/harness/operations.go 123行(バックアップのまとまり)、backend/compat/harness/coverage_test.go 158行。Issue #772 の26の操作に `restoreResume` は無い / 合っていた
- design.md harness の節「生成したコードは本文を読んでから受け口を呼ぶので、読める JSON の本文 `{}` を付ける」: backend/internal/httpapi/server.go 117-121行(本文を読めないときは、受け口より前に 400 で答える)。`{}` は JSON のオブジェクトとして読めるので、受け口の未実装の答え(server.go 123-125行の 501)に届く / 合っていた
- research.md 143行「実装のはじめに確かめる。違えば、Java 版と同じ答えにする。同じ答えにできなければ、要件6の受入基準2のとおりに止まり、所有者に報告する」: design.md 404行と同じ進め方である / 合っていた

### 受入基準ごとの確かめ方

| 受入基準 | 確かめる道具 | 動かす場所 | 動かすのに要るもの | design の箇所 |
|---|---|---|---|---|
| 1.2 | `main_test.go` の `TestRun_PassesResumeHandlers`(入口が経歴書の処理を受け口に渡すこと)、`resumes_test.go` の「`httpapi.New` に `ResumeHandlers` を渡すと、26の操作の要求が受け口に届くこと」の場面、画面と同じ本文の compare の筋書き、Playwright での `api-docs` の確認 | 開発環境の `backend-go` の領域の検査(`make check`)と CI の `backend-go` | testcontainers-go の Postgres と Redis(`main_test.go` の `TestMain` が今も動かしている)、Java 版のマイグレーション、経歴書を持たない利用者の行、`IssueAccessToken` で作るログインの状態の値。どれも手本の `TestRun_PassesUserHandlers` にある | 「main.go」の節の2つ目の段落、「ファイルの構成」の `main_test.go`、「テストの方針」の `resumes.go` の8つ目と `main.go` の行 |
| 4.3 | 経歴書の復元で 501 を確かめる3つのファイルのテスト(`TestSelf_SameImageNoDiff` `TestSelf_OneCharFakeFails` `TestSelf_MatchedDiffPasses` `TestCross_SelfPairPasses` `TestPerf_SelfPairRuns`) | 開発環境と CI の `make compat` `make compat-cross`、開発環境の `make compat-perf` | 段の名前 `restore-with-token`、操作の名前 `restoreResume`(`compat_test.go` の161-162行、165行、178行)、本文 `{}` と `csrf: true` を付けた `POST /api/resumes/restore`。経歴書の受け口を経路につなぐ前に替えること | 「Java 版と Go 版を比べる検査の広げ方」の移し替えの段落、「ファイルの構成」の3つのファイルの行、「テストの方針」の harness の箇条の最後の文 |
| 6.2 | 所有者への報告(同じ答えにできないと分かったとき) | 実装のはじめ | 無い | 「試作の記録(research.md)」の最後の文。research.md 143行も同じ進め方になった |

### 申告

この往復の差分に、新しく決めたことは無い。

### 指摘

| ID | レベル | 該当箇所 | 内容 | 直し方の案 |
|---|---|---|---|---|
| D3-1-1 | 低 | design.md「Java 版と Go 版を比べる検査の広げ方(harness)」の移し替えの段落(444行) | 3つのファイルの筋書きの前の説明の文(backend/compat/compat_test.go 92-93行、backend/compat/cross_test.go 189-190行、backend/compat/perf_test.go 15行)は、「Go 版の経歴書の操作はまだ 501 を返すので」と書いている。この spec のあとは、501 を返すのは経歴書の復元(バックアップのまとまりの操作)であり、経歴書の操作の多くは 501 を返さない。design は、要求と段の名前と操作の名前の替え方までを書き、この説明の文に触れていない。テストの結果は変わらないので、実装には影響しない(サイクル2 往復2 の D2-2-1 と同じ内容で、その往復の審査は止まって処置を受けていない) | 「Claude は、3つのファイルの筋書きの前の説明の文も、経歴書の復元がまだ 501 を返すことに合わせて直す」の1文を足す |

### 前の段階への指摘

無い。

- 往復: 1回で収束 / 未解決: 0件

## サイクル4 往復1(2026-11-15)

### 審査の範囲

範囲: 差分

- 記録の書き方: 審査役は、ファイルに書き足す道具を持たないので、このファイルの全体を書き直して、この節を末尾に足した。サイクル1からサイクル3の節は、読んだ文字のまま写した
- design.md 概要の4段落目と5段落目(11行、13行)、「作るもの」の2つ目(22行)、「ファイルの構成」の `body.go` `dates.go` `ids.go` とテストの一覧(109-111行、119行)、「処理の流れ」の2つの図(171行、173行、199行): 差分が、Jackson と Java の読み方を写す文を、Go の普通の読み方の文に替えた。要件1の受入基準1の1つ目の例外と、要件2の受入基準1の末尾の段落に効く
- design.md「本文の読み手(body.go、dates.go、ids.go)」の節の全体(272-298行): 差分が、読み方の規則を書き直した。語 `uuid.Parse` `time.Parse` `encoding/json` `parseID` `errUnreadableBody` で design.md を検索し、「Service」の「失敗したとき」(258-259行)、「入力の検査」の年月と日付の範囲の箇条(308行)、「失敗したときの扱い」の誤りを返す順(594行)と食い違わないかを見た。画面が送る値について書いた文は、正解のファイル `backend/internal/resume/testdata/` の Java 版の答えと1つずつ照らした
- design.md「試作の記録(research.md)」の最後の3文(408行): 差分が、UTF-8 として誤ったバイトの確かめを済んだことにし、止まる文を消した。research.md 147-156行と、要件6の受入基準1と2に効く
- design.md「Java 版の答えの正解のファイル(testdata)」の表と2つの比べ方(422-436行)、「テストの方針」の単体テストの箇条(599-606行、618行): 差分が、画面が送る値と送らない値で比べ方を分け、テストの中の表と変えた動きの一覧の番号を照らす仕組みを足した。要件1の受入基準1(「Java 版と答えが変わる書き方を、変えた動きの一覧に載せる」)に効く
- design.md「マスタと経歴書の操作の筋書き」の入力の誤りの箇条と、無い経歴書と無い項目の箇条(481行、485行): 差分が、鍵を大文字で書いた要求と前後に空白のある ID を送らないことにし、`Invalid Date` を足した。要件4の受入基準1の2つ目の箇条に効く。残した要求(文字列の欄の並び、真偽の欄の読めない文字列、本文の全体が並びか文字列、大文字の ID)が、新しい読み方でも Java 版と同じ答えになるかを、正解のファイルで見た
- design.md「変えた動きの一覧に載せる違い」の CB-051 から CB-055(517行、523-528行): 差分が5つの違いを足した。違いごとに、Java 版の側の文を正解のファイルと照らし、Go 版の側の文を「本文の読み手」の節と照らした
- design.md「経歴書の受け口」の利用者の ID の箇条(357行): 差分が主語を足しただけで、中身は変わっていない。ほかの節には影響しない
- 語 `jackdate` `javauuid` `jacksonUUID` `springPathUUID` `decodeBody(body []byte, fields` で design.md を検索し、古い部品の名前が残っていないことを見た。`jacksonJSON`(48行)は、認証の spec の今ある関数の名前で、差分の外である
- 影響を受けないと判断した箇所: harness の広げ方、初期のデータ、読み書き、項目の並び(`compareJavaUUID` は残る)、受け口、仕様書の変更、main.go、進み具合の表。差分はこれらの節の動きを変えていないので、読み直していない

### 実ファイルで確かめた文

- design.md 概要(13行)「生成したコードは、UUID として読めない経路の値を経路の値の誤りとして 500 で答える」「項目の ID の経路の値を、文字列のまま受け取る型にする」: backend/internal/httpapi/server.go 131-134行、150-165行(`paramErrorHandler`)、backend/api/openapi.yaml 1441-1503行(経歴書の ID は `type: string` だけ。項目の ID の6つは `format: uuid` と `x-go-type: string`) / 合っていた
- design.md 概要(13行)「`internal/resume` は生成した型を読まない決まり」: design.md 53行の依存の向きと同じ文である。今あるコードについての文ではない / 合っていた
- design.md 本文の読み手(284行)「生成したコードが `runtime.BindJSONBody` を呼び、誤りのときは 400 と `errors` が空の答えにする」: backend/internal/httpapi/gen/api.gen.go 8538-8548行、backend/internal/httpapi/server.go 118-121行、backend/go.mod 30行(oapi-codegen/runtime v1.8.0) / 合っていた(`bindjson.go` は、前のサイクルと同じく、リポジトリにもホストにも無く、開けなかった)
- design.md 本文の読み手(280行)「正解のファイルで、Java 版は、年月の `"2024-01"` と日付の `"2024-01-15"` をそのまま読み、空の文字列と `null` を入力が要る文言で断った」: backend/internal/resume/testdata/jackdate.json 4-8行、310-321行、342-353行、517-521行、763-774行、795-806行 / 合っていた
- design.md 本文の読み手(280行)「この書き方(年月は `2024-01` の形)の値は、下の読み方でも、Java 版と同じ値になる」: backend/internal/resume/testdata/jackdate.json 602-609行。Java 版は、年月の `"0000-01"` を読めず、400 と空の `errors` で答えた。Go の `time.Parse` の書式 `2006-01` は、年が 0000 の値を読む / 食い違っていた(D4-1-2)
- design.md 本文の読み手(288行)「画面が年月の入力欄から送る `Invalid Date` の文字列も、書式に合わないので読めない。Java 版がこの文字列にどう答えるかは、筋書きで確かめる」: backend/internal/resume/testdata/jackdate.json の全体と、.kiro/specs/backend-go-master-resumes/research.md を `Invalid Date` で検索し、どちらにも無かった。`backend/` の下にも無い。Java 版がこの文字列に返した答えの控えは、リポジトリに無い(D4-1-3)
- design.md 本文の読み手(295行)「`uuid.Parse` は、大文字の値と、`{` と `}` で囲んだ値と、`urn:uuid:` で始まる値と、区切りの `-` の無い32桁の値も読む。前後に空白のある値と、区切りの間の桁が足りない値は読めない」: 版は backend/go.mod 26行(github.com/google/uuid v1.6.0)で確かめた。`uuid.go` は、リポジトリにもホストの Go のモジュールの置き場所(`C:/Users/dogis/go` は無い)にも無く、審査役は開けなかった。合っていたとも食い違っていたとも判定していない。公開されている v1.6.0 の `Parse` は、長さが38の値の最初と最後の1字を、`{` と `}` かを調べずに捨てる、と審査役は覚えている。そのとおりなら、前に1つ、後ろに1つの空白を付けた値(長さ38)は読める(D4-1-1)
- design.md CB-051(524行)「区切りの間の桁が足りない値(`1-2-3-4-5`)と、全角の数字を含む値は、Java 版が経歴書の ID と項目の ID の両方で読み、前後に半角の空白のある値は、Java 版が項目の ID でだけ読む」「`{` `}` と `urn:uuid:` と32桁の値は、Java 版は読めない」: backend/internal/resume/testdata/javauuid.json 37-78行、96-106行、291-324行、446-473行 / 合っていた
- design.md CB-052(525行)「Java 版は、前後の空白を除いて読み、空白だけの値をコピーしない作成にし、16バイトを base64 で書いた値も読む」「`{` `}` と `urn:uuid:` と32桁の値は、Java 版は読めない」: backend/internal/resume/testdata/javauuid.json 536-563行、591-645行、686-695行 / 合っていた
- design.md CB-053(526行)「Java 版は、数の並び、日付の欄の日数の数、日付の欄の日時の文字列、前後に半角の空白のある値を読み、空白だけの値と空の並びを入力が要る文言で断り、`+12024-01` のような5桁の年の値を範囲の外の文言で断る」: backend/internal/resume/testdata/jackdate.json 9-18行、128-137行、322-333行、354-358行、395-406行、423-427行、570-581行、716-725行、807-811行、860-871行 / 合っていた
- design.md CB-054(527行)「Java 版は、鍵の大文字と小文字を区別し、文字列の欄の数や真偽の欄の文字列を型に合わせて読み、本文の全体が `null` の要求を断る」: backend/internal/resume/testdata/body.json 5-8行、1021-1047行、2764-2776行、backend/internal/httpapi/testdata/resumebody/cases.json 151-160行、430-439行 / 合っていた
- design.md CB-055(528行)と本文の読み手(291行)「Java 版は、誤ったバイトの一部を断り、一部を対になっていないサロゲートとして受けて、データベースに `?` で保存する」: .kiro/specs/backend-go-master-resumes/research.md 149-152行、backend/internal/resume/testdata/utf8.json 2行(控えの説明) / 合っていた
- design.md 試作の記録(408行)「UTF-8 として誤ったバイトを含む本文への Java 版の答えは、小タスク1.1 で確かめ、research.md の『危うい点と備え』に書き足した」: research.md 147-156行、backend/internal/resume/testdata/utf8.json / 合っていた
- design.md 正解のファイル(436行)「`resumebody/` には、余りのある本文、空の本文、並びと `null` と文字列の本文を、経歴書の作成と職歴の追加に送った答えを置く」: backend/internal/httpapi/testdata/resumebody/cases.json 4-489行 / 合っていた
- design.md 正解のファイル(434行)「表の番号が `backend/compat/changed-behaviors.yaml` に無いときも、テストは失敗する」(テストがこのファイルを読めるか): backend/compat/changed-behaviors.yaml 493-507行(今の最後は CB-046。違いは `- id: CB-0NN` の行で始まる)、backend/go.mod 34行(`go.yaml.in/yaml/v3` は直接の依存) / 合っていた
- design.md 筋書き(485行)「大文字の ID を送る」(新しい読み方でも Java 版と同じ答えか): backend/internal/resume/testdata/javauuid.json 15-36行(Java 版は、経歴書の ID でも項目の ID でも大文字の値を読む) / 合っていた

### 受入基準ごとの確かめ方

| 受入基準 | 確かめる道具 | 動かす場所 | 動かすのに要るもの | design の箇所 |
|---|---|---|---|---|
| 1.1(原則。画面が送る値) | `dates_test.go` `ids_test.go` `body_test.go` `link_test.go` `order_test.go` の「画面が送る値」の比べ方、`make compat` の筋書き | 開発環境の `backend-go` の領域の検査と CI の `backend-go` と `backend-compat` | `internal/resume/testdata/` の6つの正解のファイル(控えてある)。どの書き方を画面が送る値に数えるかの決まり | 「Java 版の答えの正解のファイル(testdata)」の1つ目の比べ方、「テストの方針」の `dates.go` の箇条。年が 0000 の年月は、画面が送る形に当たるのに Java 版と違う答えになる(D4-1-2) |
| 1.1(1つ目の例外。画面が送らない値) | 単体テストの中の違いの表と、表の番号が `changed-behaviors.yaml` にあることの確かめ、CB-051 から CB-055 | 同上 | 正解のファイルの Java 版の答え、Go 版の部品の答え、`backend/compat/changed-behaviors.yaml` | 「Java 版の答えの正解のファイル(testdata)」の2つ目の比べ方、「変えた動きの一覧に載せる違い」。前後に1つずつ空白を付けた ID の Go 版の答えが、design の文と合わないおそれがある(D4-1-1) |
| 2.1 | `validate_test.go` `rules_test.go` `link_test.go` と、入力の誤りの筋書き | 単体テストと比べる検査 | 読めた年月と日付の年の範囲(1900年から2100年)の境界の値 | 「入力の検査」、「マスタと経歴書の操作の筋書き」の入力の誤りの箇条 |
| 4.1(2つ目の箇条 `Invalid Date`) | 年月の値の形の誤りの筋書きの段 | 比べる検査 | 本文の年月の欄に入れる文字列 `Invalid Date` | 「マスタと経歴書の操作の筋書き」の入力の誤りの箇条 |
| 4.4 | CB-047 から CB-050 と、`resumes_test.go` `service_integration_test.go` | 単体テストと結合テスト | 読めない項目の ID | 「Service」の「失敗したとき」、概要の5段落目 |
| 6.1(5つ目。年月と日付の読み方) | research.md の P5 と、正解のファイル `jackdate.json` | 設計の前に済んでいる | 画面が送る `2024-01` `2024-01-15` と空の文字列と `null` と `Invalid Date` への Java 版の答え | 「試作の記録(research.md)」、「本文の読み手」の年月と日付の箇条。`Invalid Date` への Java 版の答えの控えは無い(D4-1-3) |
| 6.2 | research.md の「危うい点と備え」の UTF-8 の記録 | 済んでいる | 無い | 「試作の記録(research.md)」の最後の3文 |

### 申告

**1. Go の普通の読み方を、Go の部品の受ける値のままにし、Java 版が断る値も受ける** — design.md「本文の読み手」、CB-051、CB-052、CB-054

- Issue の記載: なし(Issue #772 の本文は、置き換えの spec の要件を満たすことだけを求めている。画面が送らない値を Go の普通の読み方で読むことは、requirements の要件1の受入基準1の例外にある)
- 決めたこと: 鍵の大文字と小文字を区別しない。本文の全体が `null` の要求を、すべての欄の値が無い要求として入力の検査に進める。`{` と `}` で囲んだ ID、`urn:uuid:` で始まる ID、区切りの無い32桁の ID を読む。Java 版はどれも断るか、別の答えを返す
- 他にありえた選択肢: Go の部品で読む前に、画面が送る形(小文字と大文字の36字の ID、要求の型のとおりの鍵)だけを通す。この選択肢でも Java の部品の読み方は写さない
- 外れていた場合: Go 版は、Java 版が 404 か 400 で断る要求に、経歴書を返すか、保存する。持ち主の確認は ID を読んだあとに働くので、ほかの利用者の経歴書は読めない。あとで狭めるときは、CB-051、CB-052、CB-054 と単体テストの表を書き直す

**2. 読めない年月と日付を、欄ごとの文言でなく、本文が読めない要求として 400 と空の `errors` で断る** — design.md「本文の読み手」の年月と日付の箇条、CB-053

- Issue の記載: なし
- 決めたこと: 書式に合わない年月と日付は、`decodeBody` が `errUnreadableBody` で断る。Java 版が読んで範囲の外の文言か入力が要る文言で断る書き方(空白だけ、空の並び、5桁の年)にも、Go 版は空の `errors` で答える
- 他にありえた選択肢: 読めない年月と日付を値が無いこととして入力の検査に進め、欄ごとの文言で断る
- 外れていた場合: 画面が `Invalid Date` を送ったときの答えが Java 版と違えば、画面に出る文言が変わる。`Invalid Date` への Java 版の答えは、まだ控えていない(D4-1-3)

**3. UTF-8 として誤ったバイトを U+FFFD に置き換えて保存する** — design.md「本文の読み手」の最後の箇条、CB-055

- Issue の記載: なし
- 決めたこと: Go 版は、誤ったバイトを含む本文を断らず、U+FFFD に置き換えた値を保存して答える。Java 版は、一部を 400 で断り、一部を `?` で保存する
- 他にありえた選択肢: 誤ったバイトを含む本文を、本文が読めない要求として 400 で断る
- 外れていた場合: データベースに U+FFFD を含む値が残る。画面は誤ったバイトを送らないので、手で作った要求でだけ起きる

**4. 違いを、単体テストの中の表と変えた動きの一覧の番号で照らし、5つの違いにまとめる** — design.md「Java 版の答えの正解のファイル(testdata)」、「変えた動きの一覧に載せる違い」

- Issue の記載: なし
- 決めたこと: 画面が送らない書き方ごとの違いをテストの中の表に書き、表の番号が `changed-behaviors.yaml` にあることをテストが確かめる。変えた動きの一覧には、書き方ごとでなく、ID、`resumeId`、年月と日付、鍵と型、UTF-8 の5つにまとめて載せる
- 他にありえた選択肢: 書き方ごとに1つの違いを載せる。または、違いの表を `changed-behaviors.yaml` の側に持つ
- 外れていた場合: 所有者が変えた動きの一覧で読めるのは5つのまとまりの説明までで、書き方ごとの答えは Go のテストのコードにだけある

### 指摘

| ID | レベル | 該当箇所 | 内容 | 直し方の案 |
|---|---|---|---|---|
| D4-1-1 | 中 | design.md「本文の読み手」の `parseID` の箇条(295行)とその下の段落(298行)、CB-051(524行)、CB-052(525行) | design は「`uuid.Parse` は、前後に空白のある値を読めない」と書き、CB-051 は前後に半角の空白のある経路の値を Go 版が 404 で断ると書き、CB-052 は `resumeId` の前後の空白を Java 版だけが除いて読むと書く。google/uuid v1.6.0(backend/go.mod 26行)の `Parse` は、長さが38の値を `{…}` の形として扱うときに、最初と最後の1字が `{` と `}` かを調べずに捨てる、と審査役は覚えている(調べるのは同じライブラリの `Validate` だけである)。そのとおりなら、前に1つ、後ろに1つの空白を付けた ID(` 1b4e28ba-…-0016d3cca427 `、長さ38)と、前後に好きな1字を付けた ID を、`parseID` は読む。正解のファイルには、この形の `resumeId` がある(backend/internal/resume/testdata/javauuid.json 536-542行。Java 版は読んで 201)。すると、Go 版は Java 版と同じ答えになり、CB-052 の表に載せた書き方が「表にあるのに Java 版と同じ」でテストが落ちる。経路の経歴書の ID では、Java 版が 404 で断る値(前後に1つずつの空白)に、Go 版が経歴書を返す。この書き方は正解のファイルの `paths` に無いので(37-78行は片側だけの空白)、単体テストは見つけない。審査役は `uuid.go` を開けなかったので、まず動かして確かめてほしい | `backend-go` の領域で `uuid.Parse(" 1b4e28ba-2fa1-11d2-883f-0016d3cca427 ")` を1回動かして結果を research.md に書く。読めるなら、(a) `parseID` が、長さ38の値は最初が `{` で最後が `}` のときだけ `uuid.Parse` に渡す、と design に書く。または (b) 読めることを 295行と CB-051 と CB-052 に書き、正解のファイルの `paths` に前後に1つずつ空白を付けた値を足す、のどちらかにする |
| D4-1-2 | 中 | design.md「本文の読み手」の画面が送る本文の段落(280行)、年月と日付の箇条(288行)、「テストの方針」の `dates.go` の箇条(604行)、CB-053(526行) | 280行は「この書き方(年月は `2024-01` の形、日付は `2024-01-15` の形)の値は、下の読み方でも、Java 版と同じ値になる」と書き、604行は、この形の値を Java 版と同じに読むことをテストで確かめると書く。正解のファイルでは、Java 版は年月の `"0000-01"` を読めず、400 と空の `errors` で答えた(backend/internal/resume/testdata/jackdate.json 602-609行)。Go の `time.Parse` の書式 `2006-01` は年が 0000 の値を読むので、Go 版は入力の検査に進み、範囲の外の文言「取得年月が不正です。」で答える(308行。1899年の値と同じ扱い。jackdate.json 682-693行)。状態の番号は同じ 400 だが、本文が違う。`"0000-01"` は書式に合うので、CB-053 の「書式に合わない値」にも当たらない。このまま作ると、`dates_test.go` が、画面が送る形の値で Java 版と違うとして落ちるか、表に載せる番号が無い違いとして落ち、design に戻る | 次のどちらかを design に書く。(a) `dates.go` の年月の型と日付の型は、`time.Parse` で読めても年が 0000 の値は読めないとする。(b) 年が 0000 の値を画面が送らない書き方に数え、CB-053 に「年が 0000 の値は、Java 版が読めず、Go 版は読んで範囲の外の文言で断る」を足す。あわせて、604行の「画面が送る書き方」の決まりを、形だけでなく年の範囲でも言い切る |
| D4-1-3 | 中 | design.md「本文の読み手」の年月と日付の箇条の最後の2文(288行)、「試作の記録(research.md)」(408行)、「テストの方針」の `dates.go` の箇条(604行) | 要件6の受入基準1の5つ目は、設計を書く前に試す年月と日付の読み方に、画面が送る `Invalid Date` を挙げている。`Invalid Date` は画面が送る値なので、Go 版は Java 版と同じ答えを返さなければならない(要件1の受入基準1の原則)。design は「Java 版がこの文字列にどう答えるかは、筋書きで確かめる」と書き、実装のあとの比べる検査に回している。Java 版の答えの控えは、research.md にも正解のファイル(backend/internal/resume/testdata/jackdate.json)にも無い。408行は「9つの動きを試しに作り、方法と結果を research.md に書いた」と書くが、この値は入っていない。Java 版の答えが 400 と空の `errors` でなければ、年月の読み手の作り(読めない値を `errUnreadableBody` にする)を直すことになり、承認のあとに design に戻る。正解のファイルを控えた環境(`spring` のコンテナの中のもう1つの Java 版)で、今すぐ確かめられる | 正解のファイルを控えたのと同じ環境で、資格の追加の `date` と、職歴の `startDate` に `"Invalid Date"` を入れて Java 版に送り、答えを年月と日付の正解のファイルと research.md の P5 に足す。design の288行に Java 版の答えを書き、604行の `dates_test.go` の場合を「`Invalid Date` で Java 版と同じ答えになること」に直す |
| D4-1-4 | 低 | design.md「変えた動きの一覧に載せる違い」の「対応する要件」(515行) | この節の「対応する要件」は 3.3 と 4.4 だけである。差分で足した CB-051 から CB-055 は、要件1の受入基準1の1つ目の例外(「Claude は、Java 版と答えが変わる書き方を、変えた動きの一覧に載せる」)を受け持つ。本文には「要件1の受入基準1の例外」と書いてある(11行)ので、実装には影響しない | 「対応する要件: 1.1, 3.3, 4.4」にする |
| D4-1-5 | 低 | design.md「ファイルの構成」の `dates.go` `ids.go` と `testdata/`(110-111行、119行、123行) | 作業のブランチには、前の design で作った `backend/internal/resume/jackdate.go` `jackdate_test.go` と、正解のファイル `testdata/jackdate.json` `testdata/javauuid.json` がある。design は、新しい名前のファイルを作るとだけ書き、今あるファイルを消すか名前を替えるか、正解のファイルの名前をどうするかを書いていない。main には無いファイルで、PR の差分には残らないので、実装には影響しない | tasks で、今ある `jackdate.go` と `jackdate_test.go` を消すことと、正解のファイルの名前を替えるか残すかを書く |

### 前の段階への指摘

無い。

- 往復: 1回目 / 高0 中3 低2

## サイクル4 往復2(2026-11-15)

### 審査の範囲

範囲: 差分

- 記録の書き方: 審査役は、ファイルに書き足す道具を持たないので、このファイルの全体を書き直して、この節を末尾に足した。サイクル1からサイクル4 往復1の節は、読んだ文字のまま写した
- design.md「本文の読み手」の画面が送る本文の段落(287行)、年月と日付の箇条(295行)、CB-053(533行)、「テストの方針」の `dates.go` の箇条(611行): 差分が、年が `0000` の値を Java 版と違う答えになる値として足し、`Invalid Date` への Java 版の答えを書いた(D4-1-2 と D4-1-3 の直し)。語 `0000` `Invalid Date` `time.Parse` で design.md と research.md を検索し、「入力の検査」の年月と日付の範囲の箇条、筋書きの入力の誤りの箇条(488行)、research.md の「年月と日付(P5)」(62-65行)と食い違わないかを見た。Java 版の側の文は、正解のファイル `backend/internal/resume/testdata/jackdate.json` と、Java 版の要求の型と照らした。要件1の受入基準1と要件6の受入基準1に効く
- design.md「本文の読み手」の `parseID` の箇条(302行)とその下の段落(305行)、CB-051(531行)、CB-052(532行): 差分が、`uuid.Parse` の長さごとの読み方と、前後に1つずつ空白のある値の扱いを書いた(D4-1-1 の直し)。語 `uuid.Parse` `空白` で design.md を検索し、筋書きの無い経歴書と無い項目の箇条(492行)、「テストの方針」の `ids.go` の箇条(612行)と食い違わないかを見た。Java 版の側の文は、正解のファイル `javauuid.json` と Java 版の `ResumeIdResolver` と照らした。要件1の受入基準1の1つ目の例外に効く
- design.md「試作の記録(research.md)」の最後の文(415行): 差分が、UTF-8 の文の後ろの「変えた動きの一覧に載せる」の文を消し、`Invalid Date` を確かめた文を足した。消した中身は、「本文の読み手」の最後の箇条(298行)と CB-055 に残っている。要件6の受入基準1に効く
- design.md「使う既存の仕組み」の `internal/auth` の公開した部品(47-54行): 差分が、1行の並びを7つの箇条に分けた。7つの名前が今のコードにあるかを見た
- そのほかの差分(`json` のタグの説明、「入力の検査」の文言の並びの文、「仕様書の変更」の2つの箇条、正解のファイルの節の主語、筋書きの節の主語、「テストの方針」の harness の箇条、「性能」の経歴書1件の取得の文): 主語を足したか、語の説明を足したか、文を分けただけで、中身は変わっていない。ほかの節には影響しない
- 影響を受けないと判断した箇所: harness の広げ方、初期のデータ、読み書き、項目の並び、受け口、main.go、進み具合の表。差分はこれらの節の動きを変えていないので、読み直していない
- 語 `0000` `Invalid Date` で requirements.md を検索する代わりに、前の往復で確かめた要件6の受入基準1の5つ目(`Invalid Date` を挙げる)と要件1の受入基準1を基準にした。差分は前の段階の本文を変えていない

### 実ファイルで確かめた文

- design.md 使う既存の仕組み(47-54行)「`internal/auth` の公開した部品のうち、`auth.Error` `FieldErrors` `ErrBusiness` `ErrInvalidInput` `NotBlank` `UTF16Len` `IsJavaWhitespace` の7つを使う」: backend/internal/auth/exported.go 27行、101行、106行、116行、121行、126行(`Error` の型は、サイクル1 往復1で backend/internal/auth/errors.go 80-91行を開いて確かめた) / 合っていた
- design.md 本文の読み手(295行)「Java 版も、`Invalid Date` を読めない値として、400 と空の `errors` で断る(年月と日付の正解のファイル)」: backend/internal/resume/testdata/jackdate.json 1008-1015行(`yearMonth` の末尾。400 と空の `errors`)、.kiro/specs/backend-go-master-resumes/research.md 65行 / 合っていた
- design.md 試作の記録(415行)「`Invalid Date` への Java 版の答えは、2026-11-15 に Java 版に送って確かめ、research.md の『年月と日付(P5)』に書き足した」: research.md 65行、backend/internal/resume/testdata/jackdate.json 2行(控えの説明)と 1008-1015行 / 合っていた
- design.md CB-053(533行)「Java 版は、年が `0000` の値(年月)を読めない値として 400 と空の `errors` で断る」: backend/internal/resume/testdata/jackdate.json 602-609行(年月の `"0000-01"`)、backend/src/main/java/com/example/keirekipro/presentation/resume/dto/UpdateCertificationRequest.java 31-33行(`@JsonFormat(pattern = "yyyy-MM")`) / 合っていた
- design.md 本文の読み手(287行)「年が `0000` の年月と日付を除き、Java 版と同じ答えになる」、CB-053(533行)「年月と日付の書き方。…年が `0000` の値を読めない値として 400 と空の `errors` で断る」、テストの方針(611行)「年が `0000` の値を除き」のうち、日付についての部分: 正解のファイルの `date` の一覧(backend/internal/resume/testdata/jackdate.json 3-515行)に、年が `0000` の日付は無い。Java 版の日付の欄は書式の指定の無い `LocalDate` である(backend/src/main/java/com/example/keirekipro/presentation/resume/dto/UpdateResumeBasicRequest.java 31-34行。年月の欄だけが `yyyy-MM` の書式を持つ)。Java 版は、日付の `"-2024-01-15"` を読んで範囲の外の文言「日付が不正です。」で断っている(jackdate.json 236-247行)。同じ正解のファイルに合わせて作った今のコードも、年月だけを年が1より小さいときに読めないとし(backend/internal/resume/jackdate.go 160-165行)、日付の年には下限を置いていない(230-231行、305-308行)。日付の年が `0000` の値を、Java 版は読んで範囲の外の文言で断ると読める。Go 版も `time.Parse` で読んで範囲の外の文言で断るので、違いにならない / 食い違っていた(D4-2-1)
- design.md 本文の読み手(302行)「`uuid.Parse` は、値の長さで読み方を決める。長さ36、長さ38(最初と最後の1字を除く。`{` と `}` でなくても除く)、長さ45(`urn:uuid:` の9字を除く)、長さ32。ほかの長さの値は読めない」: 版は backend/go.mod 26行(github.com/google/uuid v1.6.0)で確かめた。`uuid.go` は、前の往復と同じくリポジトリにもホストにも無く、審査役は開けなかった。実装セッションが Go のテストで、前後に1つずつ空白のある値と `x` と `y` で囲んだ値が読めることを確かめたと記録している(reviews/design-response.md 81行)。審査役が覚えている v1.6.0 の `Parse` の作りとも合う / 合っていた(審査役は自分では動かしていない)
- design.md CB-051(531行)「片側にだけ半角の空白のある値は、Java 版が項目の ID でだけ読む」: backend/internal/resume/testdata/javauuid.json 37-64行(経歴書の ID は 404、項目の ID は 200) / 合っていた
- design.md CB-051(531行)「前後に1つずつ空白のある経歴書の ID は、Go 版が読み、Java 版は 404 で答える」: backend/src/main/java/com/example/keirekipro/usecase/resume/ResumeIdResolver.java 23-28行(`trim` を呼ばずに `UUID.fromString` に渡し、読めなければ 404 の誤りにする)、research.md 79行、backend/internal/resume/testdata/javauuid.json 37-64行(片側の空白は 404)。前後に1つずつ空白を付けた経路の値そのものは、正解のファイルの `paths` に無い(D4-2-2) / 合っていた
- design.md CB-052(532行)「前後に1つずつ空白のある `resumeId` は、Java 版と Go 版のどちらも読む」: backend/internal/resume/testdata/javauuid.json 536-542行(Java 版は 201 で、写した元の ID を読んでいる) / 合っていた
- design.md 本文の読み手(305行)「区切りの間の桁が足りない経路の項目の ID(`1-2-3-4-5`)を、Java 版は読む」: backend/internal/resume/testdata/javauuid.json 96-106行(項目の ID で 200) / 合っていた

### 受入基準ごとの確かめ方

| 受入基準 | 確かめる道具 | 動かす場所 | 動かすのに要るもの | design の箇所 |
|---|---|---|---|---|
| 1.1(原則。画面が送る値) | `dates_test.go` の「画面が送る書き方」の比べ方(年が `0000` の値を除く)と `Invalid Date` の場合、`ids_test.go` の小文字の ID の場合、`make compat` の筋書き | 開発環境の `backend-go` の領域の検査と CI の `backend-go` と `backend-compat` | 正解のファイル `jackdate.json`(`Invalid Date` と年月の `0000-01` の答えがある。日付の年が `0000` の答えは無い)、`javauuid.json` | 「本文の読み手」の画面が送る本文の段落と年月と日付の箇条、「テストの方針」の `dates.go` の箇条。日付の年が `0000` の値を Java 版と違う答えに数える根拠が無い(D4-2-1) |
| 1.1(1つ目の例外。画面が送らない値) | `dates_test.go` `ids_test.go` `body_test.go` の中の違いの表(CB-051、CB-052、CB-053)と、表の番号が `changed-behaviors.yaml` にあることの確かめ | 同上 | 正解のファイルの Java 版の答え、Go 版の部品の答え、`backend/compat/changed-behaviors.yaml` | 「Java 版の答えの正解のファイル(testdata)」の2つ目の比べ方、CB-051 から CB-053。CB-051 に足した、前後に1つずつ空白のある経歴書の ID の違いは、正解のファイルの `paths` に値が無いので、表と照らす値が無い(D4-2-2) |
| 4.1(2つ目の箇条 `Invalid Date`) | 年月の値の形の誤りの筋書きの段 | 比べる検査 | 本文の年月の欄に入れる文字列 `Invalid Date`。2つの版の答えは、400 と空の `errors` で同じになる | 「マスタと経歴書の操作の筋書き」の入力の誤りの箇条、「本文の読み手」の年月と日付の箇条 |
| 6.1(5つ目。年月と日付の読み方) | research.md の P5 と、正解のファイル `jackdate.json` | 設計の前に済んでいる | 画面が送る `2024-01` `2024-01-15` と空の文字列と `null` と `Invalid Date` への Java 版の答え(どれも控えてある) | 「試作の記録(research.md)」の最後の文、「本文の読み手」の年月と日付の箇条 |

### 申告

**1. 年が `0000` の値を Go 版の読み方のままにし、違いを変えた動きの一覧に載せる** — design.md「本文の読み手」の画面が送る本文の段落、CB-053

- Issue の記載: なし
- 決めたこと: `2024-01` の形に合う、年が `0000` の年月を、Go 版は読んで範囲の外の文言で断る。Java 版は読めない値として空の `errors` で断る。状態の番号はどちらも 400 で、本文の `errors` が違う
- 他にありえた選択肢: `dates.go` が、年が `0000` の値を読めない値にして、Java 版と同じ答えにする(前の往復の D4-1-2 の直し方の案の (a))
- 外れていた場合: 利用者が年月の入力欄に年 `0000` を打ち込めるなら、画面に出る文言が Java 版と変わる(Java 版は欄ごとの文言を出さず、Go 版は「取得年月が不正です。」の形の文言を出す)。あとで合わせるときは、`dates.go` と CB-053 とテストの表を直す

**2. 長さ38の ID の最初と最後の1字を、`{` と `}` かを調べずに除く読み方を、そのまま使う** — design.md「本文の読み手」の `parseID` の箇条、CB-051

- Issue の記載: なし
- 決めたこと: `parseID` は `uuid.Parse` をそのまま呼ぶ。前後に好きな1字を付けた長さ38の値を、経歴書の ID と項目の ID と `resumeId` のどれでも読む
- 他にありえた選択肢: `parseID` が、長さ38の値は最初が `{` で最後が `}` のときだけ `uuid.Parse` に渡す(前の往復の D4-1-1 の直し方の案の (a))
- 外れていた場合: Java 版が 404 か 500 で答える経路の値に、Go 版が経歴書か項目を返す。持ち主の確認は ID を読んだあとに働くので、ほかの利用者の経歴書は読めない。あとで狭めるときは、`ids.go` と CB-051 を直す

### 指摘

| ID | レベル | 該当箇所 | 内容 | 直し方の案 |
|---|---|---|---|---|
| D4-2-1 | 中 | design.md「本文の読み手」の画面が送る本文の段落(287行)、CB-053(533行)、「テストの方針」の `dates.go` の箇条(611行) | 差分は、年が `0000` の値を「年月と日付」の両方で Java 版と違う答えになる値にした。287行は「年が `0000` の年月と日付を除き、…Java 版と同じ答えになる」と書き、CB-053 は、年月と日付の書き方の違いとして「Java 版は、年が `0000` の値を読めない値として 400 と空の `errors` で断る。Go 版は、年が `0000` の値を読み、範囲の外の文言で断る」と書く。Java 版の答えの控えがあるのは年月の `"0000-01"` だけである(backend/internal/resume/testdata/jackdate.json 602-609行)。日付の年が `0000` の値は、正解のファイルの `date` の一覧(3-515行)にも research.md にも無い。Java 版の日付の欄は、年月の欄と違い、書式 `yyyy-MM` の指定を持たない `LocalDate` である(UpdateResumeBasicRequest.java 31-34行、UpdateCertificationRequest.java 31-33行)。Java 版は日付の `"-2024-01-15"` を読んで「日付が不正です。」で断っており(jackdate.json 236-247行)、同じ正解のファイルに合わせて作った今のコードも、年が1より小さい値を読めないとするのは年月だけである(backend/internal/resume/jackdate.go 160-165行、230-231行、305-308行)。これらから、Java 版は日付の `"0000-01-15"` を読んで「日付が不正です。」で断ると読め、Go 版の答えと同じになる。このまま作ると、変えた動きの一覧の CB-053 に、日付について確かめていない(おそらく誤った)Java 版の動きが載る。あとで日付の年が `0000` の値を正解のファイルに足したときは、「表にあるのに Java 版と同じ書き方」として `dates_test.go` が落ちる | 次のどちらかにする。(a) 287行と CB-053 と 611行の、年が `0000` の値についての文を、年月だけに限る(「年が `0000` の年月」)。(b) 正解のファイルを控えたのと同じ環境で、基本の情報の更新の `date` に `"0000-01-15"` を入れて Java 版に送り、答えを `jackdate.json` の `date` と research.md の P5 に足し、その答えに合わせて3か所の文を直す |
| D4-2-2 | 低 | design.md CB-051(531行)、「テストの方針」の `ids.go` の箇条(612行)、「Java 版の答えの正解のファイル(testdata)」の2つ目の比べ方 | CB-051 に足した「前後に1つずつ空白のある経歴書の ID は、Go 版が読み、Java 版は 404 で答える」の違いは、正解のファイルの `paths` に、この形の値が無い(backend/internal/resume/testdata/javauuid.json 37-78行は片側だけの空白)。`ids_test.go` は正解のファイルの書き方ごとに表と照らすので、この違いはテストの表に載らず、テストでは確かめられない。Java 版の側の動きは、`ResumeIdResolver.java` 23-28行と片側の空白の答えから読めるので、文は誤りではない。また、302行のとおり、Go 版は空白でない1字で囲んだ長さ38の値も、経歴書の ID と項目の ID の両方で読むが、CB-051 は空白の場合だけを書いている。どちらも画面が送らない値で、作るものは変わらないので、実装には影響しない | tasks で、正解のファイルの `paths` に、前後に1つずつ空白を付けた値を足すことを書く(D4-2-1 の (b) で Java 版を動かすなら、同じときに控える)。CB-051 の文を「前後に1字ずつ付けた長さ38の値」の形に広げる |

### 前の段階への指摘

無い。

- 往復: 2回目 / 高0 中1 低1

## サイクル4 往復3(2026-11-15)

### 審査の範囲

範囲: 差分

- 記録の書き方: 審査役は、ファイルに書き足す道具を持たないので、このファイルの全体を書き直して、この節を末尾に足した。サイクル1からサイクル4 往復2の節は、読んだ文字のまま写した
- design.md「本文の読み手」の画面が送る本文の段落(287行)、CB-053(539行)、「テストの方針」の `dates.go` の箇条(617行): 差分が、年が `0000` の値についての文を年月だけに限り、年が `0000` の日付は Java 版と Go 版の答えが同じで違いに当たらないと書いた(D4-2-1 の直し)。語 `0000` で design.md と research.md と tasks.md を検索し、ほかに年が `0000` の値を書く箇所が research.md の「年月と日付(P5)」(66行)だけであることと、3か所の文が互いに食い違わないことを見た。Java 版の側の文は、足された正解のファイルの行と照らした。要件1の受入基準1と要件6の受入基準1に効く
- design.md「テストの方針」の単体テストの箇条から消えた行(「違いの表を持つテストは、表の番号が `backend/compat/changed-behaviors.yaml` にあることも確かめる」): 差分がこの行を消した。語 `表の番号` で design.md を検索し、同じ中身が「Java 版の答えの正解のファイル(testdata)」の2つ目の比べ方(442行。「表の番号が `backend/compat/changed-behaviors.yaml` に無いときも、テストは失敗する」)に残っていることを見た。確かめの仕組みは減っていない。要件1の受入基準1の1つ目の例外の確かめ方は変わらない
- design.md「Java 版と Go 版を比べる検査の広げ方(harness)」の移し替えの段落(461-466行): 差分が、1つの段落を、前置きの文と4つの箇条に分けた。語 `delete-with-token` `deleteResume` `restoreResume` で design.md と `backend/compat` を検索し、替える箇所が直す前と同じであることを見た。要件4の受入基準3の確かめ方は変わらない
- design.md「性能」の最後の箇条(670行): 差分が、Go 版が書く量が少ない理由を足した。語 `書く量` `消して` で design.md と research.md を検索し、「読み書き」の書き方の箇条(352行)と research.md 117行、132行と同じ中身であることを見た
- design.md「失敗したときの扱い」の誤りを返す順(610行): 差分が、括弧と読点の並びを文に分けた。順(本文が読めない、入力欄の検査、経歴書の ID と経歴書、上限と名前の重なり、項目、期間の決まり)は直す前と同じである
- そのほかの差分(「作るもの」の CB-047 の箇条(29行)、「Service」の退会した利用者の箇条(267行)、`BindJSONBody` の場所の文(291行)、「経歴書の受け口」のマスタの答えの表(369-370行)、CB-047 と CB-049 と CB-051 から CB-055 の「Claude は、…match を書かない」の文(532行、534行、536行)、CB-053 の Java 版の文の分け方): 主語を足したか、文と表の行を分けただけで、中身は変わっていない。ほかの節には影響しない
- 影響を受けないと判断した箇所: `parseID` と CB-051 と CB-052、入力の検査、読み書き、項目の並び、初期のデータ、筋書き、main.go、進み具合の表。差分はこれらの節の動きを変えていないので、読み直していない
- 語 `0000` で requirements.md を検索し、該当は無かった。差分は前の段階の本文を変えていない

### 実ファイルで確かめた文

- design.md 本文の読み手(287行)「年が `0000` の日付は、Java 版と Go 版のどちらも読み、範囲の外の文言で断る」: backend/internal/resume/testdata/jackdate.json 515-526行(`date` の末尾の `"0000-01-15"`。Java 版は 400 と `errors.date` の「日付が不正です。」で答えた。範囲の外の `"1899-12-31"` の答え(268-279行)と同じ本文である)、.kiro/specs/backend-go-master-resumes/research.md 66行 / 合っていた
- design.md 本文の読み手(287行)、CB-053(539行)「Java 版は、年が `0000` の年月を、読めない値として 400 と空の `errors` で断る」: backend/internal/resume/testdata/jackdate.json 614-621行(`yearMonth` の `"0000-01"`。400 と空の `errors`) / 合っていた
- design.md CB-053(539行)「Java 版は、数の並び(`[2024,1]`)と、日付の欄の日数の数(`19737`)と、日付の欄の日時の文字列と、前後に半角の空白のある値を読む」「空白だけの値と空の並びを、入力が要る文言で断る」「`+12024-01` のような5桁の年の値を、範囲の外の文言で断る」: backend/internal/resume/testdata/jackdate.json 819-823行、423-427行、128-132行、9-13行と728-732行、322-333行と787-798行、395-406行と872-883行、582-593行。差分は1つの文を4つに分けただけで、どの文も正解のファイルと合う / 合っていた
- design.md 本文の読み手(287行)「正解のファイルで、Java 版は、年月の `"2024-01"` と日付の `"2024-01-15"` をそのまま読み、空の文字列と `null` を入力が要る文言で断った」: backend/internal/resume/testdata/jackdate.json 4-8行、310-321行、342-353行、529-533行、775-786行、807-818行(正解のファイルに1件足されたので、`yearMonth` の行の番号は前の往復から12行ずれている) / 合っていた
- design.md harness の節(461-466行)「3つのファイルは、経歴書の削除の要求(`DELETE /api/resumes/00000000-0000-4000-8000-000000000201` と `csrf: true`)を使う」「3つのファイルの段の名前 `delete-with-token`」「`compat_test.go` で、違いの段の名前と操作の名前 `deleteResume` を確かめる箇所と、match の操作の名前」「経歴書の復元の操作の名前 `restoreResume`」: backend/compat/compat_test.go 105-106行、161-162行、165行、178行、backend/compat/cross_test.go 202-204行、backend/compat/perf_test.go 28-29行、backend/compat/harness/coverage_test.go 158行 / 合っていた
- design.md 性能(670行)「Java 版は経歴書の保存のたびに6つの欄の行をすべて消して書き直す」: backend/src/main/java/com/example/keirekipro/infrastructure/repository/resume/MyBatisResumeRepository.java 80-123行(`save` は、`resumes` を upsert したあと、6つの欄ごとに `delete…ByResumeId` を呼んでから、項目を1件ずつ `insert…` する) / 合っていた
- design.md 本文の読み手(291行)「`runtime.BindJSONBody` は、oapi-codegen/runtime v1.8.0 の `bindjson.go` の36-45行にある」: 版は backend/go.mod 30行で合っていた。`bindjson.go` は、前の往復までと同じく、リポジトリに無く(`backend/` の下を `func BindJSONBody` で検索して該当なし)、審査役は開けなかった。差分は括弧の中を別の文に出しただけで、中身は変わっていない。合っていたとも食い違っていたとも判定していない
- design.md 失敗したときの扱い(610行)「経歴書の作成では、Java 版の `CreateResumeUseCase` と `CopyCreateResumeUseCase` のとおり、上限、名前の重なり、コピー元の読み出しの順にする」: サイクル1 往復1で CopyCreateResumeUseCase.java 50-66行と CreateResumeUseCase.java 44-65行を開いて確かめた文で、差分はこの文を変えていない / 合っていた
- design.md Service(267行)「Java 版は、`resumes.user_id` の外部キーの違反で 500 と答える」: サイクル1 往復1で V1__create_tables.sql 69-77行を開いて確かめた文で、差分は最後の文の主語を足しただけである / 合っていた

### 受入基準ごとの確かめ方

| 受入基準 | 確かめる道具 | 動かす場所 | 動かすのに要るもの | design の箇所 |
|---|---|---|---|---|
| 1.1(原則。画面が送る値) | `dates_test.go` の「画面が送る書き方」の比べ方(年が `0000` の年月を除く。年が `0000` の日付は Java 版と同じ答えの側に入る)と `Invalid Date` の場合 | 開発環境の `backend-go` の領域の検査と CI の `backend-go` | 正解のファイル `jackdate.json`(年月の `"0000-01"` と日付の `"0000-01-15"` と `Invalid Date` の答えがどれも控えてある) | 「本文の読み手」の画面が送る本文の段落、「テストの方針」の `dates.go` の箇条 |
| 1.1(1つ目の例外。画面が送らない値) | `dates_test.go` `ids_test.go` `body_test.go` の中の違いの表(年が `0000` の年月は CB-053)と、表の番号が `changed-behaviors.yaml` にあることの確かめ | 同上 | 正解のファイルの Java 版の答え、Go 版の部品の答え、`backend/compat/changed-behaviors.yaml` | 「Java 版の答えの正解のファイル(testdata)」の2つ目の比べ方(表の番号の確かめはこの箇所に残っている)、CB-053、「テストの方針」の `dates.go` の箇条 |
| 4.3 | 経歴書の復元で 501 を確かめる3つのファイルのテスト | 開発環境と CI の `make compat` `make compat-cross`、開発環境の `make compat-perf` | 段の名前 `restore-with-token`、操作の名前 `restoreResume`、本文 `{}` と `csrf: true` を付けた `POST /api/resumes/restore`。経歴書の受け口を経路につなぐ前に替えること | 「Java 版と Go 版を比べる検査の広げ方」の移し替えの段落と4つの箇条 |
| 6.1(5つ目。年月と日付の読み方) | research.md の P5 と、正解のファイル `jackdate.json` | 設計の前に済んでいる | 年が `0000` の日付への Java 版の答え(research.md 66行と jackdate.json 515-526行に控えてある) | 「試作の記録(research.md)」、「本文の読み手」の画面が送る本文の段落 |

### 申告

この往復の差分に、新しく決めたことは無い。年が `0000` の年月を Go 版の読み方のままにすることは、前の往復の申告の1つ目に書いた。

### 指摘

無い。

| ID | レベル | 該当箇所 | 内容 | 直し方の案 |
|---|---|---|---|---|

### 前の段階への指摘

無い。

- 往復: 3回で収束 / 未解決: 0件

## サイクル5 往復1(2026-11-15)

### 審査の範囲

範囲: 差分

- 記録の書き方: 審査役は、ファイルに書き足す道具を持たないので、このファイルの全体を書き直して、この節を末尾に足した。サイクル1からサイクル4 往復3の節は、読んだ文字のまま写した
- design.md「仕様書の変更」の1つ目の箇条(393行): 差分が、`x-go-type-import` を足す文を、足さない文とその理由に替えた(T3-1-4 の直し)。語 `x-go-type` で design.md と requirements.md と tasks.md と research.md を検索し、「設計を見直すきっかけ」の箇条(69行)、「ファイルの構成」の `backend/api/openapi.yaml` の行(146行)、tasks.md の小タスク1.2(23行)と「実装のメモ」(335行)、research.md 124行と食い違わないかを見た。どれも `x-go-type` だけを書いており、`x-go-type-import` を足すと書く箇所は残っていない。requirements.md に該当は無い。要件1の受入基準1と要件4の受入基準4の確かめ方は変わらない
- design.md「ファイルの構成」の `backend/internal/resume/difftable_test.go`(127行)と、「Java 版の答えの正解のファイル(testdata)」の2つ目の比べ方の最後の2文(444行): 差分が、表の番号を一覧と照らす共通の関数の置き場所と、一覧の読み方を足した(T3-1-5 の直し)。語 `difftable` `表の番号` で design.md と tasks.md を検索し、同じ節の次の段落(446行。`resumes_test.go` も「画面が送らない値の比べ方」で比べる)、「テストの方針」の表と照らす箇条(616-620行、632行)、tasks.md の小タスク2.1(49行、56行)と小タスク5.2(228行)と食い違わないかを見た。要件1の受入基準1の1つ目の例外に効く
- design.md「ファイルの構成」の `backend/compat/harness/match_test.go`(161行): 差分が、項目の数を確かめるテストの期待する数を増やす行を足した(T3-1-5 の直し)。語 `match_test` `CB005HasNoMatch` で design.md と tasks.md と `backend/compat` を検索し、「変えた動きの一覧に載せる違い」の節(532-543行。CB-047 から CB-055 の9つ)、tasks.md の小タスク2.1(47行。46から51)、6.2(243行。51から52)、6.6(279行。52から55)、「実装のメモ」(337行)と数が合うかを見た。要件3の受入基準3と要件4の受入基準4と要件1の受入基準1の例外(変えた動きの一覧に載せること)に効く
- design.md「ファイルの構成」の全体(112-166行): 差分の目的が、tasks が作るか変えるファイルを載せることなので、tasks.md に出てくるファイルの名前をすべて検索し、ファイルの構成の行と照らした。載っていないのは、小タスク1.4 の `service_test.go`(D5-1-2)と、小タスク2.1 が消す `jackdate.go` `jackdate_test.go` と名前を替える正解のファイルである。後ろのものは、サイクル4 往復1 の D4-1-5(低。記録のみ)で扱ってあるので、もう一度は出さない
- 影響を受けないと判断した箇所: 本文の読み手、入力の検査、Service、読み書き、項目の並び、受け口、httpapi.New、main.go、harness の広げ方、筋書き、初期のデータ、進み具合の表、変えた動きの一覧に載せる違いの中身。差分はこれらの節の動きを変えていないので、読み直していない

### 実ファイルで確かめた文

- design.md 仕様書の変更(393行)「要求の本文の8つの型に `x-go-type: json.RawMessage` を足す。`x-go-type-import` を足さない」(済んだ実装と合うか): backend/api/openapi.yaml 1819行、1830行、1844行、1861行、1871行、1885行、1895行、1905行(8つの型に `x-go-type: json.RawMessage`)、1458-1503行(6つの経路の値に `x-go-type: string`)。ファイルを `x-go-type` で検索し、`x-go-type-import` は1つも無い / 合っていた
- design.md 仕様書の変更(393行)「oapi-codegen v2.8.2 が生成したコードは元から `encoding/json` を読み込む」「生成したコードは、本文を読まずに `json.RawMessage` として受け口に渡す」: backend/go.mod 118行(oapi-codegen/v2 v2.8.2)、backend/Makefile 40行(`go tool oapi-codegen`)、backend/internal/httpapi/gen/api.gen.go 8-11行(`import` の中の `"encoding/json"`)、246行、267行、286行、404行、429行、555行、578行、630行(8つの型は `= json.RawMessage` の別名) / 合っていた
- design.md 仕様書の変更(393行)「`x-go-type-import` を足すと同じ読み込みが2つになり、コンパイルできない」: 今あるファイルについての文ではなく、足したときにどうなるかの文である。審査役は `make generate` を動かせないので、自分では確かめていない。実装セッションが小タスク1.2 で確かめたと記録している(tasks.md 335行)。前提の「元から `encoding/json` を読み込む」は上の行で合っていた。足さない今の仕様書で生成したコードが8つの型を `json.RawMessage` にしていることも上の行で確かめたので、この文が外れていても作るものは変わらない。合っていたとも食い違っていたとも判定していない
- design.md ファイルの構成(161行)「`backend/compat/harness/match_test.go` の `TestLoadChangedBehaviors_CB005HasNoMatch` は、変えた動きの一覧の項目の数を確かめる。増やさないと、このテストが失敗する」: backend/compat/harness/match_test.go 313-314行(`filepath.Join("..", "changed-behaviors.yaml")` を読む)、327-329行(`len(got) != 46` なら失敗)、1行(`//go:build compat`。`make compat` で動く)。backend/compat/changed-behaviors.yaml の `- id: CB-` の行は今46である。同じテストの、match を持たない番号の一覧(331-335行)は、挙げた番号だけを調べるので、足した違いを一覧に足さなくても失敗しない。`backend/` の `*.go` で実際の一覧を読むテストは、このファイルの314行、384行、530行だけで、数を確かめるのは327行だけである / 合っていた
- design.md 正解のファイル(444行)「`go.mod` が直接読み込む `go.yaml.in/yaml/v3` で一覧を読む」: backend/go.mod 34行(`go.yaml.in/yaml/v3 v3.0.5`。`// indirect` の付かない側の `require`)、backend/compat/harness/match.go 18行(同じライブラリで同じ一覧を読んでいる) / 合っていた
- design.md ファイルの構成(127行)と正解のファイル(444行)「`internal/resume` の単体テストが `backend/compat/changed-behaviors.yaml` を読む」(今の決まりと環境で読めるか): backend/.golangci.yml 43-57行(機能のパッケージの depguard の規則は lax で、禁じるのは `backend/internal` と `backend/cmd` の読み込みだけである。外のライブラリ `go.yaml.in/yaml/v3` は禁じていない)。`backend/compat/go.mod` は無く、`backend/internal/resume` と `backend/compat` は同じモジュールの同じ作業フォルダにあるので、テストは `../../compat/changed-behaviors.yaml` を読める。`difftable_test.go` は、まだリポジトリに無い(backend/internal/resume/ の一覧。小タスク2.1 が作る) / 合っていた

### 受入基準ごとの確かめ方

| 受入基準 | 確かめる道具 | 動かす場所 | 動かすのに要るもの | design の箇所 |
|---|---|---|---|---|
| 1.1(1つ目の例外。画面が送らない値の違いを、変えた動きの一覧に載せること) | `dates_test.go` `ids_test.go` `body_test.go` の中の違いの表と、表の番号を一覧と照らす `difftable_test.go` の共通の関数 | 開発環境の `backend-go` の領域の検査(`make check` のテスト)と CI の `backend-go` | `backend/compat/changed-behaviors.yaml`(同じ作業フォルダにある)、`go.yaml.in/yaml/v3`(go.mod の直接の依存。depguard は禁じていない) | 「ファイルの構成」の `difftable_test.go`(127行)、「Java 版の答えの正解のファイル(testdata)」の2つ目の比べ方(444行) |
| 1.1(本文の全体の扱い。CB-054 の表) | `resumes_test.go` の中の違いの表と、表の番号が一覧にあることの確かめ | 同上 | `backend/compat/changed-behaviors.yaml`、`internal/httpapi` のテストの中で一覧を読む処理 | 「Java 版の答えの正解のファイル(testdata)」の最後の段落(446行)。`internal/httpapi` のテストが表の番号をどう照らすかは書かれていない(D5-1-1) |
| 1.1 と 4.4(仕様書の型) | `make generate` のあとの `make check`(生成したコードの食い違いの検査とビルド)、`resumes_test.go`、`server_internal_test.go` | 開発環境の `backend-go` の領域の検査と CI の `backend-go` | `x-go-type: json.RawMessage` と `x-go-type: string` だけを足した仕様書(済んでいる) | 「仕様書の変更」の2つの箇条(393-394行) |
| 3.3、4.4、1.1 の例外(変えた動きの一覧に載せること) | `changed-behaviors.yaml` の CB-047 から CB-055 と、`match_test.go` の `TestLoadChangedBehaviors_CB005HasNoMatch` | 開発環境と CI の `make compat`(`-tags compat`) | 期待する数を、足した違いの数だけ増やすこと(46 から、9つを足して 55) | 「ファイルの構成」の `match_test.go`(161行)、「変えた動きの一覧に載せる違い」(532-543行) |

### 申告

この往復の差分に、新しく決めたことは無い。`x-go-type-import` を足さないことは、済んだ実装(小タスク1.2)に本文を合わせた直しで、ほかの選択肢は無い。共通の関数の置き場所と一覧の読み方は、テストの中の作りで、外れていたときの手戻りは小さい。

### 指摘

| ID | レベル | 該当箇所 | 内容 | 直し方の案 |
|---|---|---|---|---|
| D5-1-1 | 低 | design.md「Java 版の答えの正解のファイル(testdata)」の2つ目の比べ方(444行)と最後の段落(446行) | 差分は、表の番号を一覧と照らす共通の関数を「`internal/resume` の単体テストの共通の関数」として `difftable_test.go` に置くと書いた。446行は、`internal/httpapi` の `resumes_test.go` も「画面が送らない値の比べ方」で比べると書き、tasks.md の小タスク5.2(228行)は、`TestResumeRoutes_WholeBody` が表の番号を一覧と照らすと書く。`_test.go` の関数はほかのパッケージから呼べないので、`resumes_test.go` は `difftable_test.go` の関数を使えない。`internal/httpapi` の側で一覧をどう読むかは、design に書かれていない。`go.yaml.in/yaml/v3` は `internal/httpapi` のテストからも読め(backend/.golangci.yml 43-48行。`internal/httpapi` は機能のパッケージの規則の外)、実装役が同じ読み方をもう1つ書けば済むので、実装には影響しない。tasks の T3-1-2(低。記録のみ)と同じ中身である | 446行に、「`resumes_test.go` は、同じ読み方で一覧を読み、表の番号を確かめる」の1文を足す |
| D5-1-2 | 低 | design.md「ファイルの構成」の単体テストの行(126行) | 126行の括弧の中の単体テストの名前(`body_test.go` から `errors_test.go` の8つ)に、tasks.md の小タスク1.4(37行)が作った `service_test.go` が無い(backend/internal/resume/service_test.go は、今リポジトリにある)。行の頭の `backend/internal/resume/*_test.go` と「上の各ファイルの単体テスト」の説明には当たる(`service.go` は114行にある)ので、載っていないファイルではなく、括弧の中の名前の並びが足りないだけである。実装には影響しない | 括弧の中に `service_test.go` を足す |

### 前の段階への指摘

無い。

- 往復: 1回で収束 / 未解決: 0件
