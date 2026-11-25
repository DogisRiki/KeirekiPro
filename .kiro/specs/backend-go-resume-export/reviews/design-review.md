## サイクル1 往復1(2026-11-23)

### 審査の範囲

範囲: 全体

### 実ファイルで確かめた文

- 概要 10行「`usecase/resume/export/` の `ExportResumeUseCase` と `ResumePdfExportSettings`」: backend/src/main/java/com/example/keirekipro/usecase/resume/ExportResumeUseCase.java(`usecase/resume/` の直下)と usecase/resume/export/ResumePdfExportSettings.java / 食い違っていた(D1-1-1)
- 概要 9行と 11行と 12行「受け口の2つのコントローラ、`ResumeExportRuleCheckService`、`infrastructure/export/resume/` の `ResumeExportModelBuilder`」: presentation/resume/controller/ExportResumeController.java と ExportResumeWithSettingsController.java、domain/service/resume/ResumeExportRuleCheckService.java、infrastructure/export/resume/ResumeExportModelBuilder.java / 合っていた
- 使う既存の仕組み 49行「`Engine.Render(ctx, html)`、同時に作る数は2、打ち切りは30秒、A4」: backend/internal/platform/pdf/pdf.go(DefaultTimeout、DefaultMaxConcurrent、160行の Render) / 合っていた
- 使う既存の仕組み 52-55行「`findResume` と `order.go`、`parseID`、`errResumeNotFound`(404)と `errUnreadableInput`、`checkDiffTableInChangedBehaviors`」: backend/internal/resume/service.go、ids.go、errors.go、difftable_test.go 17行 / 合っていた
- 使う既存の仕組み 57行と 受け口の節 339行「`authRequestMiddleware` は Google と GitHub のログインの開始と戻り先の操作のときだけ Accept の行を context に入れる。`parseAccept` がある」: backend/internal/httpapi/auth.go 296-304行 / 合っていた
- 使う既存の仕組み 60行と 初期のデータの節 503行「fixtures の users/basic.sql、resumes/ の empty.sql many-pages.sql long-text.sql fonts.sql と4つの要求の本文の json」: backend/compat/fixtures/users/basic.sql(user1 と user2)、fixtures/resumes/ / 合っていた
- 使う既存の仕組み 61行と 筋書きの節 478行「resume-ops.sql の退会用の利用者と経歴書 350」: backend/compat/fixtures/resumes/resume-ops.sql 6-26行 / 合っていた
- 使う既存の仕組み 63行と 作らないもの 41行「poppler-utils の5つのコマンドが開発環境のイメージと CI の backend-compat のジョブに入っている」: docker/backend-go/Dockerfile 15-20行、.github/workflows/ci.yaml 481行と 505-509行 / 合っていた
- 使う既存の仕組み 64行と 使う技術 110行「x/text v0.43.0 が直接の依存、pgx v5.11.0、uuid v1.6.0、testcontainers v0.45.0、oapi-codegen v2.8.2、sqlc v1.31.1、Go 1.27.0」: backend/go.mod / 合っていた
- プロジェクトの決まり 79行「`internal/resume` が読む `internal/auth` と `internal/platform` と `golang.org/x/text` は今の depguard の規則で読める」: backend/.golangci.yml の depguard / 合っていた
- ファイルの構成 147行と 150行「resumeresponses.go と server.go に26の操作と書いたコメント、`resumeOperations`」: backend/internal/httpapi/resumeresponses.go 12行、resumes.go 55行、server.go 49行と 93行と 95行 / 合っていた
- ファイルの構成 151行「応答の型の数を確かめるテスト(803-836行)の期待が26」: backend/internal/httpapi/resumes_test.go 803-842行(836行に `len(visits) != 26`) / 合っていた
- ファイルの構成 148行「`authResponse` に Content-Disposition の欄が無い」: backend/internal/httpapi/authresponses.go / 合っていた
- 受け口の節 349行「multipart の Content-Disposition を読む `contentdisposition.go` がすでにある」: backend/internal/httpapi/contentdisposition.go / 合っていた
- 仕様書の節 355行「本文の8つの型に `x-go-type: json.RawMessage` があり `x-go-type-import` は無い。`ExportResumeRequest` には無い」: backend/api/openapi.yaml 1819-1905行と 2036行 / 合っていた
- 仕様書の節 355行「`unimplemented.go` が2つの出力の操作の未実装の答えを返す」: backend/internal/httpapi/unimplemented.go 152-158行 / 合っていた
- 本文の読み手の節 115行「生成した型で読むと読めない本文は生成したコードの誤りの経路に行く」: backend/internal/httpapi/gen/api.gen.go(runtime.BindJSONBody と RequestErrorHandlerFunc)、server.go / 合っていた
- main.go の節 361行「今は `resume.New` を PDF の部品を作る前に呼ぶ」: backend/cmd/keirekipro/main.go 173行と 175行 / 合っていた
- main.go の節 363行「手本の `TestRun_PassesResumeHandlers`」: backend/cmd/keirekipro/main_test.go 942行 / 合っていた
- 受け口の節 335行「Java 版は Accept の行の字の並びに `application/pdf` か `text/markdown` が含まれるかで選び、無ければ 406『対応していない形式が指定されました。』」: ExportResumeController.java と AppExceptionHandler.java 100-104行 / 合っていた
- 処理の流れ 221行と Service の節 252行「確かめる順、前提を満たさないときの始まりの文、設定を直せないときに業務の誤りにする」: ExportResumeUseCase.java、ExportResumeCommand.java(isPreview は INLINE) / 合っていた
- 本文の読み手の節 269行「errors の鍵の道筋 `pdfSettings.tableHeaderColor.rgb.red` と `specifiedOnce`」: presentation/resume/dto/ExportResumeRequest.java / 合っていた
- PDF の設定の節 281-284行「既定の値と、丸めと、6〜72 の範囲」: ResumePdfExportSettings.java / 合っていた
- 出力の前提の節 292行「確かめる順と8つの文言」: ResumeExportRuleCheckService.java / 合っていた
- ファイル名の節 325行「`FileUtil.sanitizeFileName` の決まり」: shared の FileUtil.java 81-90行 / 合っていた
- pdfcmp の節と ファイルの構成 155-156行「`Describe` と `Compare`、`normalizeText`、許す幅のコメント(30行)、今のテストが6つ、`pdf_helper_test.go`」: backend/compat/pdfcmp/pdfcmp.go(30行)、pdfcmp_test.go、pdf_helper_test.go / 合っていた
- harness の節 447行「期待の `content_type` は今は絶対の URL の段にだけ書け、`validateVersionBody` が断る。`checkStepExpect` で確かめる」: backend/compat/harness/scenario.go 383行、steps.go 135行 / 合っていた
- 筋書きの節 487行「`CrossRoute` は、筋書きの最後の段を、その前の版に送る段と違う版に送る。手本は `TestCrossRoute_ResumeSteps`」: backend/compat/harness/cross.go 36-83行、cross_test.go 263行 / 合っていた
- 筋書きの節 480行と 489行「`measure_memory` は perf の筋書きに書ける。`perfmeasure_test.go` に `TestLoadScenarios_*` がある」: backend/compat/harness/scenario.go 50行と 512行、perfmeasure_test.go 388行と 451行 / 合っていた
- 変えた動きの節 540行と ファイルの構成 164行「`match_test.go` の項目の数の期待(328行)」: backend/compat/harness/match_test.go 328行(55)、changed-behaviors.yaml の最後が CB-055 / 合っていた
- 変えた動きの節 527行「『所有者が YYYY-MM-DD に受け入れた』の形」: backend/compat/harness の TestChangedBehaviors_OwnerDecidedItems、changed-behaviors.yaml 10行 / 合っていた
- 進み具合の節 554-556行「出力の行は未着手。『作り終えた』にすると `TestCoverage_Operations` が group 4 の操作を求め始める」: .kiro/specs/backend-go-replacement/progress.md 41行、backend/compat/compat_test.go 64行、harness/coverage.go 17行 / 合っていた
- 初期のデータの節 495行「`many-pages.sql` を `compat_test.go` と `cross_test.go` の筋書きが使う」: backend/compat/compat_test.go 96行 / 合っていた
- API の説明画面の節 546行「compose の `api-docs` はポート 8082」「開発環境のイメージは Java 版の4つのフォントのファイルを置かない」: compose.yaml 75-82行、docker/backend-go/Dockerfile 15-20行(fonts-noto-cjk だけ) / 合っていた
- 試作の記録の節と 本文の読み手の節 260行「research.md の『本文の数の欄と型の読み方』」: .kiro/specs/backend-go-resume-export/research.md 240行 / 合っていた
- Makefile「`make compat` `make compat-cross` `make compat-perf`」: backend/Makefile / 合っていた
- データベース「resumes.date は NOT NULL、last_name と first_name は NULL を許す」(model の前提): Java 版の V1 マイグレーション / 合っていた

### 受入基準ごとの確かめ方

| 受入基準 | 確かめる道具 | 動かす場所 | 動かすのに要るもの | design の箇所 |
|---|---|---|---|---|
| 1.1 | `formats.yaml`(compare)と `resumes_test.go` の答えの書き方のテスト | CI の backend-compat(`make compat`)と backend-go のコンテナの `make check` | user1、経歴書 601 201 301 701 401、`inline-default.json` と `resumes/fonts-NotoSansJP.json`、Accept の行 | 筋書きの節 472行、テストの方針 604-610行と 632行 |
| 1.2 | `resumes_test.go`(CB-059 と CB-060 の表)、`prerequisite.yaml`、`not-found.yaml` | backend-go のコンテナの `make check` と CI の backend-compat | Java 版と違う読み方になる Accept の行の表、Accept に `application/json` の無い断る本文 | 変えた動きの節 532-533行、テストの方針 605行と 607行 |
| 1.3 | API の説明画面での Playwright の確認と `formats.yaml` | 開発環境の `api-docs`(8082)と `backend-go` のコンテナ | ログインした利用者、Cookie の `XSRF-TOKEN`、出力の前提を満たす経歴書 | API の説明画面の節 546-548行 |
| 2.1 | 決め直した pdfcmp で比べる `formats.yaml` と `settings.yaml`、`exportsettings_test.go`、`exporttemplate_test.go` | CI の backend-compat、backend-go のコンテナ | 本番のイメージの4つのフォント、2つのフォントと文字の大きさと色の本文の json | pdfcmp の節、筋書きの節 473行、テストの方針 598行と 600行 |
| 2.2 | `export_integration_test.go`(正解の Markdown と比べる)と `formats.yaml` | backend-go のコンテナ(testcontainers)と CI の backend-compat | 正解のファイル `testdata/export/markdown/*.md`、経歴書 701 の記号の字。名前で並べる順が2つの版で同じになる経歴書の名前 | テストの方針 626行、正解のファイルの節 388行。並べる順は 無い(D1-1-2) |
| 2.3 | `filename_test.go`、`exportdisposition_test.go`、`formats.yaml` | backend-go のコンテナ、CI の backend-compat | 正解のファイル `filenames.json` と `exportdisposition.json`、日本語の名前の経歴書 401 | ファイル名の節、受け口の節 343-347行、正解のファイルの節 390-391行 |
| 2.4 | `pdfcmp_test.go`(足す10の場合)と変えた動きの一覧の CB-056〜CB-058 | backend-go のコンテナ(`go test -tags compat`)と CI の backend-compat | `pdf_helper_test.go` でテストの中で作る PDF、`normalizeText` の直接の呼び出し | pdfcmp の節、テストの方針 612-622行、変えた動きの節 529-531行 |
| 3.1 | `rejects.yaml`、`exportbody_test.go`(正解のファイル `body.json`) | CI の backend-compat、backend-go のコンテナ | 5種類の断る本文の json、Accept に `application/json` | 本文の読み手の節、初期のデータの節 515-519行、テストの方針 597行 |
| 3.2 | `prerequisite.yaml`、`exportrule_test.go` | CI の backend-compat、backend-go のコンテナ | 経歴書 101(empty.sql) | 出力の前提の節、テストの方針 599行 |
| 3.3 | `not-found.yaml` | CI の backend-compat | 無い経歴書の ID と ID の形でない値 | 筋書きの節 476行 |
| 3.4 | `rejects.yaml`(無い経歴書に送る本文)と `export_test.go` | CI の backend-compat、backend-go のコンテナ | 形式の条件に当たる本文と無い経歴書 | 処理の流れの節 221行、テストの方針 603行 |
| 4.1 | `other-user.yaml`、`export_integration_test.go` | CI の backend-compat、backend-go のコンテナ | user2、user1 の経歴書 401 と 101 | 筋書きの節 477行、テストの方針 627行 |
| 4.2 | `deleted-user.yaml`、`export_integration_test.go` | CI の backend-compat、backend-go のコンテナ | resume-ops.sql の退会用の利用者と経歴書 350、退会の操作 | 筋書きの節 478行、テストの方針 628行 |
| 5.1 | 10本の筋書き | CI の backend-compat | export.sql の 601 と 701 と 201 の自己PR、11個の要求の本文 | 筋書きの節、初期のデータの節 |
| 5.2 | harness の比べ方と、足す `json_file` `body_contains` `content_type` の単体テスト | CI の backend-compat、backend-go のコンテナ | 決め直した pdfcmp、出力のあとのデータベースの比べ方 | harness の節、筋書きの節 483行、テストの方針 623行 |
| 5.3 | 変えた動きの一覧の項目と、その項目のテスト | CI の backend-compat | Java 版が 500 で答える要求(実装で見つかったとき) | Service の節 250行、変えた動きの節 536行 |
| 5.4 | `perf-export-pdf.yaml` と `perf-export-markdown.yaml`、`TestLoadScenarios_ExportPerf` | 開発環境の `make compat-perf`(手で動かす)、backend-go のコンテナ | 6つの欄のすべてに項目を持ち2頁になる経歴書 401、`measure_memory: true` | 筋書きの節 480-489行、進み具合の節 558行、性能の節 |
| 5.5 | `pdfcmp_test.go` | backend-go のコンテナ(`go test -tags compat`) | テストの中で作る PDF | pdfcmp の節、テストの方針 612-622行 |
| 6.1 | `cross-export.yaml`、`export_integration_test.go`(出力のあとに経歴書が変わらない) | CI の backend-compat(`make compat-cross`)、backend-go のコンテナ | 最初の版で作って足した項目の値、`body_contains` の差し込み | 筋書きの節 479行、テストの方針 629行と 637行 |
| 6.2 | `cross-export.yaml` と `TestCrossRoute_ExportSteps` | CI の backend-compat(`make compat-cross`) | 2つの向きの `CrossRoute` | 筋書きの節 479行と 487行 |
| 7.1 | research.md の「試作の記録」 | 設計の前の試作(済み) | 試作用の Java 版のコンテナ | 試作の記録の節 369行 |
| 7.2 | research.md と所有者への報告 | 設計の前(済み) | 所有者の受け入れ(2026-11-23) | 試作の記録の節 369行 |
| 7.3 | progress.md の出力の行と `TestCoverage_Operations` | backend-go のコンテナと CI の backend-compat | 筋書きを書き終えたあとの書き換えと、マージのあとの別の PR | 進み具合の節 554-560行 |

### 申告

**1. 正解のファイルを、実装のはじめに試作用の Java 版のコンテナから控え直す** — Java 版の答えの正解のファイル(testdata)の節 375-377行

- Issue の記載: なし(Issue は置き換えの spec の受入基準を満たすことだけを書く)
- 決めたこと: 試作の入力と答えはリポジトリに無いので、実装のはじめに、`keireki_proto` と Redis の DB 7 を使う Java 版を動かして控え直す
- 他にありえた選択肢: 試作の段階で控えたファイルを design と一緒にコミットしておく。Java 版と Go 版を比べる検査の compare の結果だけで確かめ、単体テストの正解のファイルを持たない
- 外れていた場合: 控え直した答えが試作のときと違えば、設計で決めた読み方(本文の数の欄と型の読み方)が実装のときに崩れ、CB-062 の中身と exportbody.go の作りを決め直すことになる

**2. PDF を比べる部品の許す幅と、折り返しのまとまりの受け入れ方** — PDF を比べる部品(pdfcmp)の節 403-435行

- Issue の記載: 置き換えの spec の要件10の受入基準1を満たす(Issue 本文の受入基準の番号の一覧)
- 決めたこと: 頁の大きさは 0.5pt、位置は 2pt、高さは 0.35pt、色は 2。折り返しのまとまりがあれば頁の数と行の頁の違いを許し、頁の違う組の縦の位置を比べない
- 他にありえた選択肢: 折り返しのまとまりがあっても、まとまりより前の頁の改頁の位置は比べる。高さの幅を文字の大きさの丸めの刻み(0.5)に合わせる
- 外れていた場合: 幅が広すぎれば、文字の大きさか改頁の違いを見逃す。狭すぎれば、Java 版と Go 版を比べる検査が通らず、実装のあとに比べ方を決め直すことになる。ほかのまとまり(バックアップ)の PDF の比べ方にも効く

**3. 設定を付けた出力の本文を、生成した型を使わずに Jackson に合わせて読む** — 出力の本文の読み手(exportbody.go)の節 260-267行

- Issue の記載: なし
- 決めたこと: `encoding/json` の生成した型で読まず、`json.RawMessage` と `math/big` で鍵の大文字と小文字の区別と、数を文字列で送ったときの読み方を Java 版に合わせる
- 他にありえた選択肢: 生成した型で読み、画面が送らない書き方の違いを変えた動きの一覧にまとめて載せる
- 外れていた場合: 読み手の作りが大きく、画面が送らない書き方で Java 版と違う答えが残れば、CB-062 の表が膨らむ

**4. 設定を付けない出力の Accept の行を、字の並びでなく型として読む(CB-059)** — 出力の受け口の節 335行

- Issue の記載: なし(要件1の受入基準2が、画面が送らない要求で違ってよいとする)
- 決めたこと: `parseAccept` で型として読み、`application/pdf` があれば PDF、無くて `text/markdown` があれば Markdown、どちらも無ければ 406
- 他にありえた選択肢: Java 版と同じく、Accept の行の字の並びの contains で選ぶ
- 外れていた場合: `application/pdf;q=0` のような、画面が送らない Accept の行で答えが Java 版と違う。画面からは見えない

**5. progress.md の状態を「比べる検査に通った」にする PR を、マージのあとに別に出す** — 進み具合の節 560行

- Issue の記載: なし(要件7の受入基準3)
- 決めたこと: この spec の PR では「作り終えた」にし、マージを確かめたあとに main から別の PR で「比べる検査に通った」にする
- 他にありえた選択肢: 同じ PR で「比べる検査に通った」まで書く(比べる検査が必須のチェックなので、マージできれば通っている)
- 外れていた場合: PR が1つ増えるだけで、作るものは変わらない

### 指摘

| ID | レベル | 該当箇所 | 内容 | 直し方の案 |
|---|---|---|---|---|
| D1-1-1 | 中 | design.md 概要 10行「`usecase/resume/export/` の `ExportResumeUseCase` と `ResumePdfExportSettings`」 | 事実の誤り。`ExportResumeUseCase` は `backend/src/main/java/com/example/keirekipro/usecase/resume/ExportResumeUseCase.java` にあり、`usecase/resume/export/` の下には無い。`export/` の下にあるのは `ResumePdfExportSettings.java` だけである。写す元の場所が違うと、実装のときに Claude が写す元を探し直すことになる | 「`usecase/resume/` の `ExportResumeUseCase` と、`usecase/resume/export/` の `ResumePdfExportSettings`」に直す |
| D1-1-2 | 中 | design.md PDF を比べる部品(pdfcmp)の節 415行と 420行と 424行、初期のデータと要求の本文の節 497-503行 | requirements の記録 R3-2-2 で「design で書く: 全体の字の並びを比べる前に、要件2の受入基準4の写した字の違いと『～』と、名前で並べる順の違いをそろえる方法を決める」とされた。design は、写した字(NFC と U+2011)と「～」(U+FF5E)のそろえ方を 420行に書いたが、名前で並べる順の違い(CB-001。ポートフォリオ、SNS、自己PR を Java の Collator と x/text の collate で並べる違い)のそろえ方を書いていない。比べ方は順の違いを許す書き方になっておらず(全体の字の並びと行の組は字の順で比べ、Markdown は字で比べる。CB-001 の match は JSON の並びの順だけ)、`export.sql` の経歴書 601 と 701 の項目の名前を、2つの版で順が同じになるように選ぶとも書いていない。とくに 701 は名前に日本語を入れる経歴書なので、項目の名前の選び方によっては、Markdown の1字も違わない比べ方と PDF の全体の字の並びの比べ方で止まる | 初期のデータの節に、筋書きの経歴書(601、701、201 に足す自己PR)の、名前で並べる欄の項目の名前を、2つの版で同じ順に並ぶ名前にする(今の fixtures のように、名前の頭の英大文字で順を決める)と書く。あわせて、PDF を比べる部品と Markdown の比べ方は順の違いを許さず、順の違いは筋書きのデータで避けると、pdfcmp の節の字の直し方の段落に書く |
| D1-1-3 | 低 | design.md プロジェクトの決まりを守っているか 84-85行 | 雛形 `.kiro/settings/templates/specs/design.md` 42行と 55行は、関係のない項目を「関係のない項目:」の1行に名前だけ並べると決めている。design は「frontend の機能ごとの境界」と「frontend の状態の持ち方」を別の行に、理由を付けて書いた。7つの項目はすべて出ている | 2行を「- 関係のない項目: frontend の機能ごとの境界、frontend の状態の持ち方」の1行にする |

### 前の段階への指摘

無い

- 往復: 1回目 / 高0 中2 低1

## サイクル1 往復2(2026-11-23)

### 審査の範囲

範囲: 差分

- design.md 概要 7行と 10行: D1-1-1 の直しと書き方の直しの行。写す元の Java のクラスの場所を、実ファイルでもう一度確かめた
- design.md 作らないもの 35行と 37行、使う既存の仕組み 56-66行と 73行: 書き方の直しの行。`internal/auth` と `internal/httpapi` の部品の数と名前が、前と同じかを照らした。`golang.org/x/text` は、pdfcmp(`backend/compat`)からも使うので、同じモジュールかを確かめた
- design.md PDF を比べる部品(pdfcmp)の節 429行と、初期のデータと要求の本文の節 512-514行: D1-1-2 の直し。CB-001 の語で changed-behaviors.yaml と、筋書きが使う経歴書のファイル(fonts.sql、long-text.sql、many-pages.sql、empty.sql、resume-ops.sql)を検索し、名前で並べる3つの欄の項目の名前が、2つの版で同じ順に並ぶかを見た。requirements の記録 R3-2-2(design で書くと記録された食い違い)が、この直しで書かれたかを見た
- design.md テストの方針 625行と 636-641行: 字の直し方のテストと、正解の Markdown と比べる結合テスト(要件2の受入基準2)が、直した初期のデータの節と食い違わないかを見た
- design.md 筋書きの節 464行と 488-490行と 496-498行: 書き方の直しの行。`headers` の欄と、`make compat-perf` が最後の段を繰り返して測ることを実ファイルで確かめた
- design.md 設計を見直すきっかけ 82行、プロジェクトの決まり 88行、ひな形の節 325行: 書き方の直しの行。82行の `ascent-override` と `descent-override` が、ひな形の節 326行の CSS と合うかを照らした
- design.md ファイル名の節 334行、仕様書の節 364行、試作の記録の節 378行、変えた動きの節 547行、テストの方針 609行、安全の節 654行: 書き方の直しの行。547行は Service の節 259行と、609行は PDF の設定の節 292行と、654行は処理の流れの節 230行と Service の節 259行と照らした
- そのほかの節(本文の読み手、受け口、harness、API の説明画面、進み具合など): 差分の語が出てこず、直しで中身が変わらないので、読み直していない

### 実ファイルで確かめた文

- 概要 10行「`usecase/resume/` の `ExportResumeUseCase` と、`usecase/resume/export/` の `ResumePdfExportSettings`」: 往復1で開いた backend/src/main/java/com/example/keirekipro/usecase/resume/ExportResumeUseCase.java と usecase/resume/export/ResumePdfExportSettings.java の場所 / 合っていた
- 使う既存の仕組み 73行「`golang.org/x/text` は `go.mod` に直接の依存として v0.43.0 が入っている」: backend/go.mod 15-37行の直接の require の 36行。backend の go.mod はこの1つだけで、`backend/compat` も同じモジュールなので pdfcmp からも使える / 合っていた
- 初期のデータの節 512行「`fonts.sql` は、ポートフォリオと SNS と自己PR の項目の名前を、頭の英大文字(`A ` と `B `)で順が決まる名前にしている」: backend/compat/fixtures/resumes/fonts.sql 56-67行(ポートフォリオと自己PR は `A ` と `B `、SNS は GitHub・Qiita・Zenn で、頭の英大文字で順が決まる) / 合っていた
- 初期のデータの節 512行「この3つの欄の項目は、Java 版と Go 版で並べ替えの規則が違い、日本語で始まる名前では順が違うことがある(CB-001)」: backend/compat/changed-behaviors.yaml 14-39行 / 合っていた
- 初期のデータの節 514行「筋書きが使うほかの経歴書のファイル」の名前で並べる欄: fixtures/resumes/long-text.sql 36-51行(`A ` で始まる)、many-pages.sql(3つの欄の項目が無い)、resume-ops.sql 110-126行(経歴書 350 は各欄1件) / 合っていた(既存の経歴書では順の違いは起きない)
- 筋書きの節 464行「Accept の行を `headers` の欄に書く」: backend/compat/harness/scenario.go 160行 / 合っていた
- 筋書きの節 489-490行「`make compat-perf` は、最後の段を繰り返して測る」: backend/Makefile 134-136行、backend/compat/harness/perf.go 136-143行と 167-190行 / 合っていた

### 受入基準ごとの確かめ方

| 受入基準 | 確かめる道具 | 動かす場所 | 動かすのに要るもの | design の箇所 |
|---|---|---|---|---|
| 2.2 | `export_integration_test.go`(正解の Markdown と比べる)と `formats.yaml` | backend-go のコンテナ(testcontainers)と CI の backend-compat | 正解のファイル `testdata/export/markdown/*.md`、経歴書 701 の記号の字、名前で並べる順が2つの版で同じになる項目の名前 | テストの方針 637行、正解のファイルの節 390行と 397行、初期のデータの節 512行 |
| 2.4 | `pdfcmp_test.go`(`normalizeText` を直接呼ぶ場合を含む10の場合) | backend-go のコンテナ(`go test -tags compat`)と CI の backend-compat | `pdf_helper_test.go` で作る PDF、互換漢字と U+2011 と U+FF5E の字 | pdfcmp の節 429行、テストの方針 623-633行 |
| 4.1 | `other-user.yaml`、`export_integration_test.go` | CI の backend-compat、backend-go のコンテナ | user2、user1 の経歴書 401 と 101 | 処理の流れ 230行、Service の節 259行、筋書きの節 486行、テストの方針 638行、安全の節 654行 |
| 5.1 | 10本の筋書き | CI の backend-compat | export.sql の 601 と 701 と 201 の自己PR(名前の頭の英大文字で順が決まる項目の名前)、11個の要求の本文 | 筋書きの節、初期のデータの節 506-514行 |
| 5.4 | `perf-export-pdf.yaml` と `perf-export-markdown.yaml`、`TestLoadScenarios_ExportPerf` | 開発環境の `make compat-perf`、backend-go のコンテナ | 経歴書 401、`measure_memory: true`、最後の段を繰り返す perf の測り方 | 筋書きの節 489-490行と 498行 |
| 6.1 | `cross-export.yaml`、`export_integration_test.go` | CI の backend-compat(`make compat-cross`)、backend-go のコンテナ | 最初の版で作って足した項目の値、`body_contains` | 筋書きの節 488行、テストの方針 640行と 648行 |
| 6.2 | `cross-export.yaml` と `TestCrossRoute_ExportSteps` | CI の backend-compat(`make compat-cross`) | 2つの向きの `CrossRoute` | 筋書きの節 488行と 496行 |

### 申告

差分で新しく決めたことのうち、申告に当たるものは無い。名前の頭の英大文字で順を決めるのは、既存の fixtures の書き方に合わせたもので、ほかの選択肢(比べる部品に順の違いを許させる)を選ぶと比べる部品の比べ方が広がるが、design は比べ方を広げないと書いており、外れても作り直しにはならない。

### 指摘

無い

D1-1-1 と D1-1-2 は、差分の直しで埋まった。requirements の記録 R3-2-2 の「名前で並べる順の違いをそろえる方法」は、429行と 512行に書かれた。D1-1-3(低、記録のみ)は、もう一度出さない。

### 前の段階への指摘

無い

- 往復: 2回で収束 / 未解決: 0件
