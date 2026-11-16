# タスク

- [ ] 1. マスタと経歴書の処理の土台を作る
- [x] 1.1 Java 版の答えを正解のファイルに控え、UTF-8 として誤ったバイトを含む本文の扱いを確かめる

  Claude は、research.md の「確かめた環境」と同じ設定で、開発環境の `spring` のコンテナの中に Java 版をもう1つ動かす。Claude は、所有者の開発のデータベース `keireki_pro` と Redis の DB 0 に触れない。試作の入力はリポジトリに無いので、Claude は、research.md の、リンクの P4、年月と日付の P5、項目の並びの P8、ID の P9、要求の本文の型の違う値の P10〜P12 の節に書いた書き方と値の種類をすべて含む入力を作り直す。件数は、試作の件数と同じでなくてよい。Claude は、その Java 版に入力を送り、次の5つの答えを、`backend/internal/resume/testdata/` に正解のファイルとして置く。

  1. 年月と日付の書き方ごとの、Java 版が読んだ値か、読めなかったこと
  2. ID の書き方ごとの、Java 版が経路の値として読んだ ID と、経歴書の作成の `resumeId` として読んだ ID か、読めなかったこと
  3. リンクごとの、Java 版の判定
  4. 型の違う値を入れた本文ごとの、Java 版の状態の番号と本文と、Java 版がデータベースに書いた値
  5. 期間か取得の年月か名前が同じ項目を持つ経歴書の、Java 版が返した6つの欄の項目の並び。項目の ID には、`0` から `7` で始まる UUID と `8` から `f` で始まる UUID の両方を使う

  Claude は、最初の値のあとに余りのある本文、空の本文、並びと `null` と文字列の本文を Java 版の経歴書の作成と職歴の追加に送り、Java 版の状態の番号と本文を、`backend/internal/httpapi/testdata/resumebody/` に正解のファイルとして置く。この正解のファイルは、小タスク5.2 の `TestResumeRoutes_WholeBody` が使う。

  Claude は、UTF-8 として誤ったバイトを含む本文を、文字列の欄と技術スタックの並びの欄に入れて Java 版に送り、Java 版の状態の番号と本文と、Java 版がデータベースに書いた値を、6つ目の正解のファイルとして `backend/internal/resume/testdata/` に置く。Claude は、同じ答えを、research.md の「危うい点と備え」に書き足す。Claude は、この答えと Go 版の答えの違いを、本文の読み手を作る小タスク2.4 のテストで確かめる。Claude は、控え終えたら、別に動かした Java 版を止め、データベース `keireki_proto` を消し、Redis の DB 7 を空にする。
  - 完了の確かめ方: `backend/internal/resume/testdata/` に6つの正解のファイルがあり、research.md の、リンクの P4、年月と日付の P5、項目の並びの P8、ID の P9、要求の本文の型の違う値の P10〜P12 の節に書いた書き方と値の種類が、それぞれの正解のファイルにすべて入っている。`backend/internal/httpapi/testdata/resumebody/` に、本文の全体の扱いへの Java 版の答えがある。research.md の「危うい点と備え」に、誤ったバイトを含む本文への Java 版の答えが書かれている。別に動かした Java 版が止まり、データベース `keireki_proto` が無い
  - 受入基準とテストの対応: Claude は、この小タスクで確認に使う道具を作り、この小タスクでは受入基準を直接は確かめない。正解のファイルは、本文と入力と経歴書の決まりを扱う部品を作る2つ目の大きなまとまりの単体テストと、経歴書の受け口を経路と起動につなぐ小タスク5.2 のテストが使う。要件6の受入基準1と2(設計の前に試しに作り、同じにできない動きが見つかれば止まる)は、research.md の試作の記録と、この小タスクの書き足しで確かめる
  - _要件: 6.1, 6.2_

- [x] 1.2 仕様書の要求の本文と項目の ID の型を書き換え、経路の値の誤りを扱う関数に名前を付ける

  Claude は、仕様書の変更の節のとおりに、`backend/api/openapi.yaml` の要求の本文の8つの型と、項目の ID の6つの経路の値に `x-go-type` を足し、6つの経路の値の説明を書き直す。Claude は、`make generate` で生成したコードを作り直す。Claude は、httpapi.New と paramErrorHandler の節のとおりに、`server.go` の `ErrorHandlerFunc` の無名の関数を `paramErrorHandler` に出し、`server_test.go` の2つの副テストを消し、`server_internal_test.go` で同じことを確かめる。Go 版は、このタスクのあとも、マスタと経歴書の操作の要求に未実装の答えを返す。
  - 完了の確かめ方: `make generate-check` が通る。`go test ./internal/httpapi/` が通る。`server_internal_test.go` の `TestParamErrorHandler` が、`/api/auth/` の下の問い合わせの誤りを 400 にし、ほかの経路の値の誤りを 500 にし、ログに誤りの型だけを書くことを確かめる
  - 受入基準とテストの対応: Claude は、この小タスクで土台を作り、この小タスクでは受入基準を直接は確かめない。要件1の受入基準1(本文を Java 版と同じに読んで答える)と要件4の受入基準4(項目の ID が読めない要求に無い項目と同じ答えを返す)は、小タスク5.1 と5.2 の `resumes_test.go` と、6つ目の大きなまとまりの筋書きで確かめる
  - _要件: 1.1, 4.4_

- [x] 1.3 マスタと経歴書の SQL の問い合わせを書いて生成する

  Claude は、読み書きの節とマスタの読み出しの節のとおりの問い合わせを、`backend/db/queries/resumes.sql` と `backend/db/queries/masters.sql` に書き、sqlc でコードを生成する。Claude は、Java 版の `ResumeMapper.xml` と、3つのマスタの `*QueryMapper.xml` を開き、列の名前と並べ方を確かめてから、問い合わせを書く。
  - 完了の確かめ方: `make generate` が、`sqlcgen` に `resumes.sql.go` と `masters.sql.go` を生成し、`make generate-check` が通る
  - 受入基準とテストの対応: Claude は、この小タスクで土台を作り、この小タスクでは受入基準を直接は確かめない。要件5の受入基準1と2(もう一方の版が保存した経歴書を読み書きし、日本の時刻で保存する)は、小タスク3.1 の `store_integration_test.go` と、小タスク6.7 の `cross-resume.yaml` で確かめる
  - _要件: 5.1, 5.2_

- [x] 1.4 マスタと経歴書の処理の入口と型と文言を作る

  Claude は、`internal/resume` の `service.go` に、Service の部品の節のとおりの入口の型 `Service` と、部品の束 `Deps` と、組み立ての関数 `New` を作る。Claude は、`service_test.go` に、`internal/users` の `service_test.go` と同じ形で、`New` が `Now` の無い `Deps` に今の時刻を返す関数を入れることを確かめる `TestNew_DefaultsNowToTimeNow` と、渡した部品をそのまま持つことを確かめる `TestNew_KeepsGivenDeps` を作る。Claude は、`model.go` に経歴書と6つの欄の項目と技術スタックのマスタの型を置き、`errors.go` にマスタと経歴書の操作の文言と誤りを作る関数を置く。Claude は、文言を、Java 版の経歴書のユースケースと `domain/model/resume/` と `ResumeLimitChecker` と要求の型の注釈を開いて写す。Claude は、結合テストの入口 `main_integration_test.go` を、`internal/users` の結合テストの入口と同じ形で作る。この入口は、testcontainers-go で動かす PostgreSQL に Java 版のマイグレーションを当てる。
  - 完了の確かめ方: `go test ./internal/resume/ -run 'TestNew|TestErrors' -v` が通り、`TestNew_DefaultsNowToTimeNow` と `TestNew_KeepsGivenDeps` と `TestErrors_MessagesMatchJava` が出力に出る。`make lint` が、`internal/resume` が `internal/auth` と `internal/platform` を読む状態で通る。1つ目の大きなまとまりの最後のタスクなので、完了条件の2つ目のとおり `/verify-backend` も通る
  - 受入基準とテストの対応: 要件2の受入基準1のうち、答えに入れるエラーの文言は、`errors_test.go` の `TestErrors_MessagesMatchJava` で確かめる。このテストは、文言の定数が Java 版のソースの文字列と同じかを確かめる
  - _要件: 2.1_

- [ ] 2. 本文と入力と経歴書の決まりを扱う部品を作る
- [x] 2.1 年月と日付を Go の普通の読み方で読み、Java 版との違いを変えた動きの一覧に載せる

  Claude は、本文の読み手の節の年月と日付の欄のとおりに、`dates.go` に年月の型と日付の型を作る。2つの型は `json.Unmarshaler` を持ち、年月を `time.Parse` の書式 `2006-01` で、日付を書式 `2006-01-02` で読む。Claude は、前の design で作った `jackdate.go` と `jackdate_test.go` を消し、年月と日付の正解のファイル `testdata/jackdate.json` の名前を `testdata/dates.json` に替え、ID の正解のファイル `testdata/javauuid.json` の名前を `testdata/ids.json` に替える。年月と日付の正解のファイルには、小タスク1.1 のコミットのあとに、日付の `0000-01-15` への Java 版の答えと、年月の `Invalid Date` への Java 版の答えの2つを足してある。Claude は、この2つの答えを、名前を替えるのと同じコミットに入れる。Claude は、正解のファイルの中身を、この2つの答えのほかは替えない。

  Claude は、変えた動きの一覧に載せる違いの節のとおりに、画面が送らない書き方の値の読み方についての5つの違い CB-051 から CB-055 を、`backend/compat/changed-behaviors.yaml` の末尾に `group: 3` で足す。5つの違いには match を書かず、「画面に影響が無い理由」に「所有者が 2026-11-15 に決めた(requirements の承認)」と書く。Claude は、一覧の項目の数を確かめる `backend/compat/harness/match_test.go` の `TestLoadChangedBehaviors_CB005HasNoMatch` の期待する数を、46 から 51 に替える。

  Claude は、Go 版の部品の答えが Java 版と違う書き方を照らすテストの中の表のために、`internal/resume` のテストの共通の関数を `difftable_test.go` に作る。この関数は、表の番号が `backend/compat/changed-behaviors.yaml` にあることを確かめる。この関数は、`go.mod` が直接読み込む `go.yaml.in/yaml/v3` で一覧を読むので、`go.mod` は変わらない。
  - 完了の確かめ方: `go test ./internal/resume/ -run TestDates` が通る。`go test -tags compat ./compat/harness/ -run TestLoadChangedBehaviors` が通る。`internal/resume` に `jackdate.go` と `jackdate_test.go` が無く、`testdata/` に `jackdate.json` と `javauuid.json` が無い。`testdata/dates.json` に、日付の `0000-01-15` への Java 版の答えと、年月の `Invalid Date` への Java 版の答えがある
  - 受入基準とテストの対応: 要件1の受入基準1と要件2の受入基準1のうち、年月と日付の読み方は、`dates_test.go` の `TestDates_MatchesJava` で確かめる。このテストは、`testdata/dates.json` のすべての書き方で、次の3つを確かめる。
    1. 年月の型と日付の型が、画面が送る書き方の値から、Java 版と同じ年月と日付を読むか、Java 版と同じく値が無いとすること。画面が送る書き方とは、`2024-01` と `2024-01-15` の形と、空の文字列と `null` である。ただし、年が `0000` の年月は、この確認から除く
    2. 年月の型が、画面が年月の入力欄から送る `Invalid Date` を、Java 版と同じく読めないこと
    3. 画面が送らない書き方と年が `0000` の年月は、Java 版と違う答えになる書き方が、テストの中の表(CB-053)と合うこと。Java 版と違うのに表に無い書き方と、表にあるのに Java 版と同じ書き方があれば、テストは失敗する

    要件1の受入基準1の例外のうち、画面が送らない書き方の違いを変えた動きの一覧に載せることは、`dates_test.go` の `TestDates_DiffTableInChangedBehaviors` で確かめる。このテストは、表の番号が `backend/compat/changed-behaviors.yaml` にあることを確かめる
  - _要件: 1.1, 2.1_
  - _依存: 1.1_

- [x] 2.2 ID を Go の普通の読み方で読み、Java 版と同じ順に比べる

  Claude は、本文の読み手の節のとおりに、`ids.go` に、`uuid.Parse` で読む `parseID` と、`java.util.UUID.compareTo` を写した `compareJavaUUID` を作る。

  Claude は、ID の正解のファイル `testdata/ids.json` の経路の値の書き方 `paths` に、前後に1つずつ半角の空白を付けた ID への Java 版の答えを足す。この書き方は、変えた動きの一覧の CB-051 に載せた違いである。Claude がこの答えを足すのは、`ids_test.go` がこの書き方をテストの中の表と照らすのに、正解のファイルに Java 版の答えが要るためである。Claude は、Java 版の答えを正解のファイルに控えた小タスク1.1 と同じ設定で、開発環境の `spring` のコンテナの中に Java 版をもう1つ動かし、答えを控える。Claude は、所有者の開発のデータベース `keireki_pro` と Redis の DB 0 に触れない。Claude は、控え終えたら、別に動かした Java 版を止め、データベース `keireki_proto` を消し、Redis の DB 7 を空にする。
  - 完了の確かめ方: `go test ./internal/resume/ -run 'TestParseID|TestCompareJavaUUID'` が通る。`testdata/ids.json` の `paths` に、前後に1つずつ半角の空白を付けた ID がある。別に動かした Java 版が止まり、データベース `keireki_proto` が無い
  - 受入基準とテストの対応: 要件1の受入基準1と要件3の受入基準1と2のうち、経路の経歴書の ID と項目の ID の読み方は、`ids_test.go` の `TestParseID_MatchesJava` で確かめる。このテストは、`testdata/ids.json` の `paths` のすべての書き方で、Java 版が答えに返した小文字の形の ID を Java 版と同じく読むことと、Java 版と違う答えになる書き方がテストの中の表(CB-051)と合うことを確かめる。表の番号が `backend/compat/changed-behaviors.yaml` にあることは、`TestParseID_DiffTableInChangedBehaviors` で確かめる。6つの欄の項目の並びに使う比べ方は、`TestCompareJavaUUID_SignedOrder` で、`8` から `f` で始まる UUID を `0` から `7` で始まる UUID より前に並べることで確かめる
  - _要件: 1.1, 3.1, 3.2_
  - _依存: 1.1, 2.1_

- [x] 2.3 リンクが https の形かを Hibernate Validator と同じ規則で判定する (並行可)

  Claude は、入力の検査の節のとおりに、`link.go` に `isHibernateHTTPSURL` を作る。
  - 完了の確かめ方: `go test ./internal/resume/ -run TestLink` が通る。`TestLink_MatchesJava` は、小タスク1.1 で控えたすべてのリンクで、Java 版と同じ判定をすることを確かめる
  - 受入基準とテストの対応: 要件2の受入基準1のうち、リンクが https で始まる形かの判定は、`link_test.go` の `TestLink_MatchesJava` で確かめる
  - _要件: 2.1_
  - _対象の部品: 入力の検査_
  - _依存: 1.1_

- [x] 2.4 要求の本文を Go の標準のライブラリ encoding/json で読む

  Claude は、本文の読み手の節のとおりに、`body.go` に `decodeBody` と、8つの要求の型と、誤り `errUnreadableBody` を作る。`decodeBody` は、本文を `json.Unmarshal` で読む。8つの要求の型は、年月と日付の欄を小タスク2.1 の年月の型と日付の型で読む。`decodeBody` は、経歴書の作成の `resumeId` を `*string` で読み、空の文字列と `null` と鍵が無いことのほかの値を、小タスク2.2 の `parseID` で読む。`decodeBody` は、UTF-8 として誤ったバイトと、対になっていないサロゲートの `\uXXXX` の書き方を、`encoding/json` のとおり U+FFFD に置き換えて読む。サロゲートとは、UTF-16 で1つの文字を2つの単位に分けて書くときの片方の単位であり、対になっていないサロゲートは、もう片方の単位が続かないものを指す。U+FFFD は、読めない文字の代わりに置く文字である。
  - 完了の確かめ方: `go test ./internal/resume/ -run TestDecodeBody` が通る
  - 受入基準とテストの対応: 要件1の受入基準1のうち、本文の読み方は、次の4つのテストで確かめる。テストは、どれも `body_test.go` に置く。
    - `TestDecodeBody_MatchesJava` は、`testdata/body.json` のすべての本文で、画面が送る書き方の本文から Java 版と同じ値を読むことと、Java 版と違う答えになる本文がテストの中の表(CB-052 と CB-054)と合うことを確かめる。本文は、鍵の大文字、知らない鍵、同じ鍵の2つ目、文字列の欄の数と真偽、真偽の欄の文字列と整数と小数、技術スタックの並びの要素を含む
    - `TestDecodeBody_ResumeID` は、`testdata/ids.json` の経歴書の作成の `resumeId` の書き方 `resumeIds` のすべてで、Java 版と違う答えになる書き方がテストの中の表(CB-052)と合うことを確かめる
    - `TestDecodeBody_InvalidUTF8` は、`testdata/utf8.json` のすべての本文で、Go 版が U+FFFD に置き換えた値を読むことと、Java 版と違う答えになる本文がテストの中の表(CB-055)と合うことを確かめる
    - `TestDecodeBody_DiffTableInChangedBehaviors` は、3つの表の番号が `backend/compat/changed-behaviors.yaml` にあることを確かめる
  - _要件: 1.1_
  - _依存: 1.1, 2.1, 2.2_

- [x] 2.5 経歴書の作成と基本の情報の更新と職歴と資格の入力欄を検査する

  Claude は、入力の検査の節のとおりに、`validate.go` に、経歴書の作成、基本の情報の更新、職歴の項目、資格の項目の4つの要求の型の検査を作る。写す元は、`CreateResumeRequest`、`UpdateResumeBasicRequest`、`CreateCareerRequest`、`UpdateCareerRequest`、`CreateCertificationRequest`、`UpdateCertificationRequest` の注釈である。
  - 完了の確かめ方: `go test ./internal/resume/ -run 'TestValidate_(Resume|Basic|Career|Certification)'` が通る
  - 受入基準とテストの対応: 要件2の受入基準1のうち、4つの要求の型の入力欄ごとの、入力が要るかどうかと長さの上限と値の形は、`validate_test.go` の `TestValidate_Resume`、`TestValidate_Basic`、`TestValidate_Career`、`TestValidate_Certification` で確かめる。どのテストも、空白だけの値、全角の空白だけの値、長さの上限とその1つ上の値、1899年と1900年と2100年と2101年の値を含む。長さの上限とその1つ上の値は、絵文字を含む値で、UTF-16 の単位の境界を含む。UTF-16 の単位とは、文字を UTF-16 で書いたときの16ビットずつの区切りであり、絵文字の多くは2つの単位で書く
  - _要件: 2.1_

- [x] 2.6 プロジェクトとポートフォリオと SNS と自己PR の入力欄を検査する

  Claude は、入力の検査の節のとおりに、`validate.go` に、プロジェクトの項目、ポートフォリオの項目、SNS の項目、自己PR の項目の4つの要求の型の検査を作る。写す元は、`CreateProjectRequest`、`UpdateProjectRequest`、`CreatePortfolioRequest`、`UpdatePortfolioRequest`、`CreateSnsPlatformRequest`、`UpdateSnsPlatformRequest`、`CreateSelfPromotionRequest`、`UpdateSelfPromotionRequest` の注釈である。`validate.go` の検査は、リンクを小タスク2.3 の `isHibernateHTTPSURL` で判定する。
  - 完了の確かめ方: `go test ./internal/resume/ -run 'TestValidate_(Project|Portfolio|SnsPlatform|SelfPromotion)'` が通る
  - 受入基準とテストの対応: 要件2の受入基準1のうち、4つの要求の型の入力欄ごとの、入力が要るかどうかと長さの上限と値の形は、`validate_test.go` の `TestValidate_Project`、`TestValidate_Portfolio`、`TestValidate_SnsPlatform`、`TestValidate_SelfPromotion` で確かめる。作業の工程の真偽の欄が無いときの文言「null は許可されていません」は、`TestValidate_Project` で確かめる
  - _要件: 2.1_

- [x] 2.7 経歴書と項目の数の上限と、名前と期間の決まりを作る (並行可)

  Claude は、経歴書の決まりの節のとおりに、`rules.go` に、経歴書と6つの欄の項目の数の上限と、経歴書の名前の重なりと、経歴書の名前に使えない文字と、姓と名に使える文字と、期間の決まりと、職歴どうしの期間の重なりを確かめる処理を作る。
  - 完了の確かめ方: `go test ./internal/resume/ -run TestRules` が通る
  - 受入基準とテストの対応: 要件2の受入基準1のうち、経歴書の数の上限と欄ごとの項目の数の上限は `rules_test.go` の `TestRules_Limits` で、経歴書の名前に使えない文字と姓と名に使える文字は `TestRules_Names` で、期間の決まりと職歴どうしの期間の重なりは `TestRules_Period` で確かめる。`TestRules_Limits` は、6つの欄と経歴書の上限とその1つ下を含む。`TestRules_Period` は、期間の4つの決まりと、終了の月と開始の月が同じ職歴の組を含む
  - _要件: 2.1_
  - _対象の部品: 経歴書の決まり_

- [x] 2.8 6つの欄の項目を Java 版と同じ順に並べる

  Claude は、項目の並びの節のとおりに、`order.go` に6つの欄の項目の並べ方を作る。ID の比べ方には、小タスク2.2 の `compareJavaUUID` を使う。日本語の並べ方に `golang.org/x/text` を初めて読み込むので、Claude は、`go mod tidy` で、`go.mod` の `golang.org/x/text` の `// indirect` の印を外す。`go.mod` を変える小タスクは、2つ目の大きなまとまりではこの小タスクだけである。
  - 完了の確かめ方: `go test ./internal/resume/ -run TestOrder` が通る。`TestOrder_MatchesJava` は、小タスク1.1 で控えた経歴書の6つの欄で、Java 版と同じ並びになることを確かめる。ポートフォリオと SNS と自己PR の、名前か題が違う項目どうしの並びについては、Claude は、変えた動きの一覧の CB-001 のとおり、Go の日本語の並べ方で並ぶことを確かめる。`go.mod` の `golang.org/x/text` に `// indirect` が無い。2つ目の大きなまとまりの最後のタスクなので、完了条件の2つ目のとおり `/verify-backend` も通る
  - 受入基準とテストの対応: 要件1の受入基準1のうち、6つの欄の項目の並び順は、`order_test.go` の `TestOrder_MatchesJava` で確かめる
  - _要件: 1.1_
  - Claude は、この小タスクで、2つ目の大きなまとまりの最後に `/verify-backend` を流し、`go.mod` も変えるので、この小タスクをほかの小タスクと並行に進めない
  - _依存: 1.1, 2.2_

- [ ] 3. マスタと経歴書の操作の処理を作る
- [x] 3.1 経歴書と6つの欄の項目を読み書きする

  Claude は、読み書きの節のとおりに、`store.go` に、経歴書と6つの欄の項目を、小タスク1.3 で生成した問い合わせで読み書きする処理を作る。
  - 完了の確かめ方: `go test ./internal/resume/ -run TestStore` が通る
  - 受入基準とテストの対応: 要件5の受入基準1のうち、Java 版と同じ表と値の形で読み書きすることは、`store_integration_test.go` の `TestStore_RoundTrip` で確かめる。このテストは、経歴書と6つの欄の項目を書いて読み直し、同じ値になることと、技術スタックの列に `NULL` の要素と特殊文字を含む値を書いて読み直しても同じ値になることを確かめる。要件5の受入基準2のうち、日時をマイクロ秒に丸めて書くことは、`TestStore_RoundsToMicrosecond` で、`.1234565` が `.123457` になることで確かめる。プロジェクトの技術スタックの書き込みが失敗したときにプロジェクトの行も残らないことは、`TestStore_ProjectRollback` で確かめる
  - _要件: 5.1, 5.2_
  - _依存: 1.3, 1.4_

- [x] 3.2 3つのマスタを読む

  Claude は、マスタの読み出しの節のとおりに、`masters.go` に処理を作る。この処理は、3つのマスタを小タスク1.3 で生成した問い合わせで読み、資格と SNS の名前の一覧と、技術スタックの名前の振り分けを作る。Claude は、`service.go` に、`masters.go` の処理を呼ぶ `Service` の3つのメソッドを作る。
  - 完了の確かめ方: `go test ./internal/resume/ -run TestService_Masters` が通る
  - 受入基準とテストの対応: 要件1の受入基準2のうち、入力の候補を返すことは、`service_integration_test.go` の `TestService_MastersListNames` と `TestService_MastersTechStacks` で確かめる。`TestService_MastersTechStacks` は、技術スタックの小分類が答えの鍵の名前に振り分けられることと、対応の無い小分類の行を捨てることを確かめる。資格と SNS の名前の並びが Java 版と同じことは、小タスク6.1 の `masters.yaml` で確かめる
  - _要件: 1.1, 1.2_
  - _依存: 1.3, 1.4_

- [x] 3.3 経歴書の一覧と1件の取得と削除を作る

  Claude は、Service の部品の節のとおりに、`service.go` に、`ListResumes`、`GetResume`、`DeleteResume` を作る。`GetResume` と `DeleteResume` は、経路の経歴書の ID を小タスク2.2 の `parseID` で読み、読めなければ無い経歴書と同じ誤りを返す。`GetResume` は、経歴書1件の6つの欄の項目を、小タスク2.8 の並べ方で並べる。
  - 完了の確かめ方: `go test ./internal/resume/ -run 'TestService_(ListResumes|GetResume|DeleteResume)'` が通る
  - 受入基準とテストの対応: 要件3の受入基準1のうち、ほかの利用者の経歴書を返さず消さないことは、`service_integration_test.go` の `TestService_GetResumeOtherUser` と `TestService_DeleteResumeOtherUser` で確かめる。どちらのテストも、無い経歴書と同じ誤りを返すことと、経歴書の行が残ることを確かめる。要件3の受入基準4のうち、退会してすでに居ない利用者の一覧が空の並びになることは、`TestService_ListResumesDeletedUser` で確かめる
  - _要件: 3.1, 3.4_
  - _依存: 1.4, 2.2, 2.8_

- [x] 3.4 経歴書の作成とコピーした作成と基本の情報の更新を作る

  Claude は、Service の部品の節と、経歴書をコピーして作る処理の流れのとおりに、`service.go` に `CreateResume` と `UpdateResumeBasic` を作る。上限と名前の重なりと名前と姓と名の決まりは、小タスク2.7 の部品で確かめる。`CreateResume` は、Java 版と同じく、作成の答えの作成と更新の日時に、データベースに書いた丸めた値ではなく、`Now` から得た丸める前の値を返す。`UpdateResumeBasic` は、基本の情報の更新の答えの更新の日時に丸める前の値を返し、作成の日時にデータベースから読んだ値を返す。
  - 完了の確かめ方: `go test ./internal/resume/ -run 'TestService_(CreateResume|UpdateResumeBasic)'` が通る
  - 受入基準とテストの対応: 次の7つのテストで確かめる。テストは、どれも `service_integration_test.go` に置く。
    - 要件2の受入基準1のうち、経歴書の数の上限と名前の重なりを確かめる順は、`TestService_CreateResumeLimitBeforeDuplicate` で確かめる
    - 要件3の受入基準1のうち、ほかの利用者の経歴書をコピーできないことは、`TestService_CreateResumeCopyOtherUser` で確かめる
    - 要件3の受入基準4のうち、退会してすでに居ない利用者のコピーしない作成が無い経歴書と同じ誤りを返し、行を残さないことは、`TestService_CreateResumeDeletedUser` で確かめる
    - 要件5の受入基準2のうち、日本の時間帯でない時刻を返す `Now` を渡しても、作成と更新の日時を日本の時刻で書き、経歴書の日付を日本の日付で書くことは、`TestService_CreateResumeJapanTime` で確かめる
    - コピーした項目に新しい ID を付け、日付と姓と名をコピー元の値にすることは、`TestService_CreateResumeCopy` で確かめる
    - 要件1の受入基準1のうち、作成の答えの日時を Java 版と同じく丸める前の値にすることは、`TestService_CreateResumeReturnsUnroundedTime` で確かめる。このテストは、`Now` に `.1234565` 秒の時刻を返させ、答えの作成と更新の日時が `.1234565` のままで、データベースの値が `.123457` になることを確かめる
    - 要件1の受入基準1のうち、基本の情報の更新の答えの日時を Java 版と同じにすることは、`TestService_UpdateResumeBasicReturnsUnroundedUpdatedAt` で確かめる。このテストは、`Now` に `.1234565` 秒の時刻を返させ、答えの更新の日時が `.1234565` のままで、作成の日時がデータベースの値と同じことを確かめる
  - _要件: 1.1, 2.1, 3.1, 3.4, 5.2_
  - _依存: 1.4_

- [x] 3.5 項目の変更の共通の流れと、職歴とプロジェクトの項目の変更を作る

  Claude は、Service の部品の節のとおりに、`service.go` に、6つの欄の項目の変更をまとめる `editResume` と、職歴とプロジェクトの項目の追加と更新と削除の6つのメソッドを作る。`editResume` は、経歴書の行を `FOR UPDATE` で読んで固定する。項目の ID は、`editResume` が経歴書の行を読んで固定したあとに、小タスク2.2 の `parseID` で読む。`editResume` は、変更の答えの更新の日時に `Now` から得た丸める前の値を返し、作成の日時にデータベースから読んだ値を返す。
  - 完了の確かめ方: `go test ./internal/resume/ -run 'TestService_(EditResume|Career|Project)'` が通る
  - 受入基準とテストの対応: 要件3の受入基準1から3と要件4の受入基準4のうち、職歴とプロジェクトの2つの欄について、次の4つは、`service_integration_test.go` の `TestService_<欄>OtherUser`、`TestService_<欄>OfOtherResume`、`TestService_<欄>CreateOtherUserAtLimit`、`TestService_<欄>UnreadableItemID` で確かめる。`<欄>` は `Career` と `Project` である。

    1. ほかの利用者の経歴書の項目を変えないこと(要件3の受入基準1)
    2. 別の経歴書の項目を変えないこと(要件3の受入基準2)
    3. ほかの利用者の上限に達した経歴書への項目の追加に、無い経歴書と同じ誤りを返すこと(要件3の受入基準3)
    4. 項目の ID が読めない要求に、無い項目と同じ誤りを返すこと(要件4の受入基準4)

    ほかに、次の4つのテストで確かめる。テストは、どれも `service_integration_test.go` に置く。
    - 要件2の受入基準1のうち、職歴どうしの期間の重なりを断ることは、`TestService_CareerOverlap` で確かめる
    - 要件2の受入基準1のうち、項目の数の上限は、`TestService_EditResumeConcurrentLimit` で確かめる。このテストは、上限の1つ下の経歴書に2つの追加を同時に送っても、上限を超えないことを確かめる
    - プロジェクトの項目と技術スタックを1つのトランザクションで書くことは、`TestService_ProjectWithTechStack` で確かめる
    - 要件1の受入基準1のうち、変更の答えの日時を Java 版と同じにすることは、`TestService_EditResumeReturnsUnroundedUpdatedAt` で確かめる。このテストは、`Now` に `.1234565` 秒の時刻を返させ、答えの更新の日時が `.1234565` のままで、作成の日時がデータベースの値と同じことを確かめる
  - _要件: 1.1, 2.1, 3.1, 3.2, 3.3, 4.4_
  - _依存: 1.4, 2.2_

- [x] 3.6 資格とポートフォリオと SNS と自己PR の項目の変更を作る

  Claude は、Service の部品の節のとおりに、`service.go` に、資格、ポートフォリオ、SNS、自己PR の項目の追加と更新と削除の12のメソッドを、小タスク3.5 の `editResume` で作る。
  - 完了の確かめ方: `go test ./internal/resume/ -run 'TestService_(Certification|Portfolio|SnsPlatform|SelfPromotion)'` が通る。3つ目の大きなまとまりの最後のタスクなので、完了条件の2つ目のとおり `/verify-backend` も通る
  - 受入基準とテストの対応: 要件3の受入基準1から3のうち、4つの欄について、ほかの利用者の経歴書の項目と別の経歴書の項目を変えないことと、ほかの利用者の上限に達した経歴書への項目の追加に無い経歴書と同じ誤りを返すことは、`service_integration_test.go` の `TestService_<欄>OtherUser`、`TestService_<欄>OfOtherResume`、`TestService_<欄>CreateOtherUserAtLimit` で確かめる。`<欄>` は `Certification`、`Portfolio`、`SnsPlatform`、`SelfPromotion` である。要件4の受入基準4のうち、項目の ID が読めない要求に無い項目と同じ誤りを返すことは、`TestService_<欄>UnreadableItemID` で確かめる
  - _要件: 3.1, 3.2, 3.3, 4.4_
  - _依存: 1.4_

- [ ] 4. Java 版と Go 版を比べる検査を広げる
- [x] 4.1 経歴書の作成と更新の日時を、受けた時刻からの秒の差で置き換えて比べる

  Claude は、Java 版と Go 版を比べる検査の広げ方の節のとおりに、`normalize.go` に、経歴書の答えと一覧の答えの `createdAt` と `updatedAt` と、`resumes` の表の `created_at` と `updated_at` を `<wallclock:形:+秒>` に置き換える処理を足す。Claude は、`compare.go` の JSON の比べ方とデータベースの比べ方に、`<wallclock:形:+秒>` どうしを秒の差が5秒以内なら同じとする比べ方を足す。`compare.go` は、データベースを比べるときに、データベースの行を、秒を除いた文字で並べて組にし、組にしたあとで秒の差を比べる。
  - 完了の確かめ方: `go test -tags compat ./compat/harness/ -run 'TestNormalizeWallclock|TestCompareJSON_Wallclock|TestCompareDB_Wallclock'` が通る。テストは、秒の差が5秒と6秒の値、9時間ずれた値、秒を除いた文字が違う値、2つの版で同じ固定の日時を、受けた時刻を2秒ずらして置き換えた値を含む
  - 受入基準とテストの対応: 要件4の受入基準3のうち、日時を、形と、2つの版が保存した日時の差で比べることは、`normalize_test.go` の `TestNormalizeWallclock_SecondsFromReceived` と、`compare_test.go` の `TestCompareJSON_WallclockTolerance` と `TestCompareDB_WallclockTolerance` で確かめる。要件5の受入基準2のうち、日本の時間帯でない時刻を書くと Java 版と Go 版を比べる検査が止まることは、9時間ずれた値の場合で確かめる
  - _要件: 4.3, 5.2_

- [x] 4.2 Java 版を日本の時間帯で動かす

  Claude は、Java 版と Go 版を比べる検査の広げ方の節のとおりに、`versions.go` の `JavaEnv` に `"TZ": "Asia/Tokyo"` を足し、`versions_test.go` の `TestJavaEnv_DevProfileAndOIDCEndpoints` の期待する環境の値に `TZ=Asia/Tokyo` を足す。
  - 完了の確かめ方: `go test -tags compat ./compat/harness/ -run TestJavaEnv` が通る
  - 受入基準とテストの対応: 要件4の受入基準3のうち、Java 版を本番と同じく日本の時間帯で動かすことは、`versions_test.go` の `TestJavaEnv_DevProfileAndOIDCEndpoints` で確かめる
  - _要件: 4.3_

- [x] 4.3 未実装の答えを確かめる検査の経路を、未実装のまま残る操作に移す

  Claude は、`compat_test.go`、`cross_test.go`、`perf_test.go` が未実装の答えを確かめるために使う経歴書の削除の要求を、経歴書の復元の要求 `POST /api/resumes/restore` に替える。経歴書の復元は、この spec のあとも未実装のまま残り、偽の送信の検査が働く書き込みの操作である。偽の送信の検査とは、利用者が開いたほかのサイトが利用者のブラウザから勝手に送らせた書き込みの要求を断る、CSRF の検査である。Go 版の生成したコードは、本文を読んでから受け口を呼ぶので、Claude は、要求に読める JSON の本文 `{}` と `csrf: true` を付け、答えの期待を 501 のまま残す。Claude は、3つのファイルの段の名前 `delete-with-token` を `restore-with-token` に替える。Claude は、`compat_test.go` の、Java 版と Go 版を比べる検査が報告した違いを確かめる箇所で、段の名前を `restore-with-token` に替え、操作の名前を経歴書の復元の操作の名前 `restoreResume` に替える。Claude は、`compat_test.go` で、テストが違いを許す範囲として書いた match の操作の名前も、`restoreResume` に替える。Claude は、3つのファイルの「経歴書の操作はまだ 501 を返す」という注釈を、経歴書の復元が未実装であることに書き直す。経歴書の受け口を経路につなぐ小タスク5.2 より前に替えないと、経歴書の削除が Go 版で動き始めた時点で、3つのファイルのテストが失敗する。
  - 完了の確かめ方: 3つのファイルに、経歴書の削除の経路 `/api/resumes/00000000-0000-4000-8000-000000000201` と、段の名前 `delete-with-token` と、操作の名前 `deleteResume` が残っていない。替えた要求を使う3つのファイルのテストを、テストの名前で選んで `go test -tags compat -count=1 -run '<テストの名前>' ./compat/` で流し、どれも通る。`make compat` が、認証と利用者の筋書きで通る。これは、経歴書の日時を受けた時刻からの秒の差で置き換えて比べる小タスク4.1 の変更と、Java 版を日本の時間帯で動かす小タスク4.2 の変更が、今ある筋書きを壊していないことを確かめるためである。4つ目の大きなまとまりの最後のタスクなので、完了条件の2つ目のとおり `/verify-backend` も通る
  - 受入基準とテストの対応: Claude は、この小タスクで確認に使う道具を直し、この小タスクでは受入基準を直接は確かめない。経歴書の削除が Go 版で動くようになったあとも、Java 版と Go 版を比べる検査そのもののテストが未実装の答えを確かめ続けられるようにする
  - _要件: 4.2_

- [ ] 5. 経歴書の受け口をつなぐ
- [x] 5.1 26の操作の受け口と答えの形を作る

  Claude は、経歴書の受け口の節のとおりに、`internal/httpapi/resumes.go` に `ResumeService` のインタフェースと `resumeHandlers` を作り、`resumeresponses.go` に経歴書の答えとマスタの答えの JSON の型と、答えを作る関数を作る。Claude は、`var _ ResumeService = (*resume.Service)(nil)` を置く。
  - 完了の確かめ方: `go test ./internal/httpapi/ -run TestResumeHandlers` が通る
  - 受入基準とテストの対応: 次の5つのテストで確かめる。テストは、どれも `resumes_test.go` に置く。
    - 要件1の受入基準1のうち、答えの状態の番号と本文の形は、`TestResumeHandlers_SuccessResponses` で確かめる。このテストは、26の操作の成功の答えの状態の番号と本文の形が、受け口の節の表のとおりになることを確かめる
    - 要件1の受入基準1のうち、値の無い鍵を書かないことは、`TestResumeHandlers_OmitEmpty` で確かめる
    - 要件1の受入基準1のうち、`systemTest` と `maintenance` の値を入れ替えて答えることは、`TestResumeHandlers_ProcessSwap` で確かめる
    - 要件1の受入基準1のうち、日時を作成と変更の答えではナノ秒まで、読み直しの答えではマイクロ秒まで書き、末尾の 0 を落とすことは、`TestResumeHandlers_DateTimeFormat` で確かめる。このテストは、経歴書の作成の答えと職歴の更新の答えと経歴書1件の取得の答えを含む
    - 要件4の受入基準4のうち、項目の ID が読めない要求に無い項目と同じ 404 と文言で答えることは、`TestResumeHandlers_UnreadableItemID` で確かめる
  - _要件: 1.1, 4.4_

- [x] 5.2 経歴書の受け口を経路と起動につなぐ

  Claude は、httpapi.New と paramErrorHandler の節のとおりに、`server.go` の `Options` に `ResumeHandlers` を足し、`routes` で経歴書の受け口を組み込む。Claude は、main.go の節のとおりに、`main.go` で `resume.New` で `Service` を作り、`httpapi.Options` に渡し、`main_test.go` に `TestRun_PassesResumeHandlers` を足す。手本は、同じファイルの `TestRun_PassesUserHandlers` である。
  - 完了の確かめ方: `go test ./internal/httpapi/ -run 'TestResumeRoutes|TestNew'` が通る。`go test ./cmd/keirekipro/ -run TestRun_PassesResumeHandlers` が通る。このテストは、入口を起動し、ログインした利用者の経歴書の一覧の要求が、未実装の答えでなく、200 と空の並びで答えられることを確かめる。`TestResumeRoutes_Unimplemented` は、`ResumeHandlers` が無いときに、Go 版が、マスタと経歴書の操作の要求に今と同じ未実装の答えを返すことを確かめる。5つ目の大きなまとまりの最後のタスクなので、完了条件の2つ目のとおり `/verify-backend` も通る
  - 受入基準とテストの対応: 要件1の受入基準1のうち、本文の全体の扱いは、`resumes_test.go` の `TestResumeRoutes_WholeBody` で確かめる。このテストは、`httpapi.New` で作った経路に、最初の値のあとに余りのある本文、空の本文、並びと `null` と文字列の本文を送る。このテストは、`internal/httpapi/testdata/resumebody/` の正解のファイルの Java 版と違う答えになる本文がテストの中の表(CB-054)と合うことと、それ以外の本文に、小タスク1.1 で控えた Java 版の答えと同じ状態の番号と本文で答えることを確かめる。表の番号が `backend/compat/changed-behaviors.yaml` にあることも、同じテストで確かめる。要件1の受入基準2のうち、`httpapi.New` に `ResumeHandlers` を渡すと26の操作の要求が受け口に届くことは、`TestResumeRoutes_Wired` で確かめる。Go 版を起動する入口が経歴書の処理を受け口に渡すことは、`main_test.go` の `TestRun_PassesResumeHandlers` で確かめる
  - _要件: 1.1, 1.2_
  - _依存: 1.1, 2.1, 4.3_

- [ ] 6. マスタと経歴書の操作の筋書きで Java 版と Go 版を比べる
- [x] 6.1 初期のデータと、マスタの筋書きを書く

  Claude は、初期のデータの節のとおりに、`backend/compat/fixtures/resumes/resume-ops.sql` と `resume-limits.sql` を書く。Claude は、マスタと経歴書の操作の筋書きの節のとおりに、`backend/compat/scenarios/resumes/masters.yaml` を `group: 3` と `modes: [compare]` で書く。
  - 完了の確かめ方: `go test -tags compat -count=1 -run 'TestCompare_Scenarios/<masters.yaml の筋書きの名前>' ./compat/` が通る。`resume-ops.sql` と `resume-limits.sql` は、この筋書きの `fixtures` に書いてデータベースに入り、入れるときに誤りが出ない
  - 受入基準とテストの対応: 要件1の受入基準1のうち、3つのマスタの答えが Java 版と同じことは、`masters.yaml` で確かめる。資格と SNS の名前の並びも、この筋書きで確かめる
  - _要件: 1.1, 1.2, 4.1_
  - _依存: 4.1, 4.2_

- [ ] 6.2 経歴書の作成と取得と更新と削除の筋書きと、入力の誤りの筋書きを書く

  Claude は、マスタと経歴書の操作の筋書きの節のとおりに、`resume-crud.yaml` と `resume-validation.yaml` を書く。Claude は、Java 版の要求の型の注釈を開き、1つの入力欄に2つ以上の文言が付きうる入力欄を確かめ、変えた動きの一覧の節の、入力の誤りの文言の並びの違い CB-050 を、`changed-behaviors.yaml` の CB-051 の前に足す。Claude は、`match_test.go` の `TestLoadChangedBehaviors_CB005HasNoMatch` の期待する数を、51 から 52 に替える。Claude は、`resume-validation.yaml` に、鍵を大文字で書いた要求と、画面が送らない書き方の ID と年月と日付を入れた要求を書かない。2つの版の答えが違い、変えた動きの一覧の CB-051 から CB-054 に match を書かないためである。
  - 完了の確かめ方: `go test -tags compat -count=1 -run 'TestCompare_Scenarios/(<resume-crud.yaml の筋書きの名前>|<resume-validation.yaml の筋書きの名前>)' ./compat/` が通る
  - 受入基準とテストの対応: 要件1の受入基準1と要件4の受入基準1から3のうち、経歴書の一覧、作成、コピーした作成、1件の取得、基本の情報の更新、削除の答えとデータベースと日時と ID は、`resume-crud.yaml` で確かめる。要件2の受入基準1のうち、経歴書の作成と基本の情報の更新の入力の誤りと、名前の重なりと、名前と姓と名の文字は、`resume-validation.yaml` で確かめる
  - _要件: 1.1, 2.1, 4.1, 4.2, 4.3_
  - _依存: 6.1_

- [ ] 6.3 職歴とプロジェクトの項目の筋書きを書く

  Claude は、マスタと経歴書の操作の筋書きの節のとおりに、`career.yaml` と `project.yaml` を書く。Claude は、`project.yaml` に、技術スタックの4つの大分類のすべての並びに値を入れた本文を送る段と、`null` と `[]` の並びを含む本文を送る段を書く。Claude は、`career.yaml` の年月の値の形の誤りに、画面の年月の入力欄で Home を押したときに画面が送る `Invalid Date` を入れた段を書く。2つの版は、この段に、400 と空の `errors` で答える。Claude は、2つの筋書きに、鍵を大文字で書いた要求と、画面が送らない書き方の ID と年月と日付を入れた要求を書かない。
  - 完了の確かめ方: `go test -tags compat -count=1 -run 'TestCompare_Scenarios/(<career.yaml の筋書きの名前>|<project.yaml の筋書きの名前>)' ./compat/` が通る
  - 受入基準とテストの対応: 要件1の受入基準1と要件4の受入基準1から3のうち、職歴とプロジェクトの項目の追加と更新と削除の答えとデータベースは、`career.yaml` と `project.yaml` で確かめる。要件2の受入基準1のうち、2つの欄の入力の誤りと、期間の決まりと、職歴どうしの期間の重なりと、本文が読めない3つの要求は、同じ2つの筋書きで確かめる。本文が読めない3つの要求は、文字列の欄に並びを入れた要求、真偽の欄に読めない文字列を入れた要求、本文の全体が並びか文字列の要求である。要件4の受入基準1のうち、年月の値の形の誤りに `Invalid Date` を含めることは、`career.yaml` の `Invalid Date` の段で確かめる
  - _要件: 1.1, 2.1, 4.1, 4.2, 4.3_
  - _依存: 6.1_

- [ ] 6.4 資格とポートフォリオと SNS と自己PR の項目の筋書きを書く

  Claude は、マスタと経歴書の操作の筋書きの節のとおりに、`certification.yaml`、`portfolio.yaml`、`sns-platform.yaml`、`self-promotion.yaml` を書く。
  - 完了の確かめ方: `go test -tags compat -count=1 -run 'TestCompare_Scenarios/(<4つの筋書きの名前を | でつないだもの>)' ./compat/` が通る
  - 受入基準とテストの対応: 要件1の受入基準1と要件4の受入基準1から3のうち、4つの欄の項目の追加と更新と削除の答えとデータベースは、4つの筋書きで確かめる。Java 版と Go 版を比べる検査は、ポートフォリオと SNS と自己PR の並び順の違いを、変えた動きの一覧の CB-001 の match で許す。要件2の受入基準1のうち、4つの欄の入力の誤りは、同じ4つの筋書きで確かめる
  - _要件: 1.1, 2.1, 4.1, 4.2, 4.3_
  - _依存: 6.1_

- [ ] 6.5 上限と無い経歴書と、ほかの利用者の経歴書の筋書きを書く

  Claude は、マスタと経歴書の操作の筋書きの節のとおりに、`limits.yaml`、`not-found.yaml`、`other-user.yaml` を書く。
  - 完了の確かめ方: `go test -tags compat -count=1 -run 'TestCompare_Scenarios/(<3つの筋書きの名前を | でつないだもの>)' ./compat/` が通る
  - 受入基準とテストの対応: 要件2の受入基準1と要件4の受入基準1のうち、経歴書の数の上限と欄ごとの項目の数の上限は、`limits.yaml` で確かめる。要件3の受入基準2(別の経歴書の項目を変えない)と、要件4の受入基準1のうち無い経歴書と無い項目の要求は、`not-found.yaml` で確かめる。要件3の受入基準1(ほかの利用者の経歴書を返さず変えない)は、`other-user.yaml` で確かめる
  - _要件: 2.1, 3.1, 3.2, 4.1_
  - _依存: 6.1_

- [ ] 6.6 退会してすでに居ない利用者の筋書きと、残りの変えた動きを書く

  Claude は、この小タスクで次の4つをする。

  1. Claude は、マスタと経歴書の操作の筋書きの節のとおりに、`deleted-user.yaml` を書く。
  2. Claude は、`progress.md` のまとまりの表のマスタと経歴書の行の spec の列に `.kiro/specs/backend-go-master-resumes` を書き、状態の列を「作り終えた」にする。この spec の PR は、マスタと経歴書のまとまりの最初の PR であり、26の操作を作り終えた PR でもある。状態の列を「作り終えた」にすると、筋書きに出てくる操作が足りているかを確かめる `TestCoverage_Operations` が、マスタと経歴書の26の操作がすべて `group: 3` の筋書きに出てくることを求め始める。Claude は、筋書きから漏れた操作を6つ目の大きなまとまりの中で見つけるために、この書き換えを筋書きを書き終えるこの小タスクで行う。
  3. Claude は、変えた動きの一覧の節のとおりに、ほかの利用者の経歴書の上限に達した欄に項目を足す要求の違い CB-047、項目の ID が読めない項目の更新と削除の要求の違い CB-048、退会してすでに居ない利用者のコピーしない経歴書の作成の違い CB-049 を、`changed-behaviors.yaml` の CB-050 の前に足す。Claude は、`match_test.go` の `TestLoadChangedBehaviors_CB005HasNoMatch` の期待する数を、52 から 55 に替える。
  4. Claude は、6つ目の大きなまとまりの筋書きを書く途中で、Java 版が 500 で答えるほかの要求を見つけていたら、要求ごとに1つの違いを `changed-behaviors.yaml` に足す。
  - 完了の確かめ方: `go test -tags compat -count=1 -run 'TestCompare_Scenarios/<deleted-user.yaml の筋書きの名前>' ./compat/` が通る。`make compat` が、マスタと経歴書の操作のすべての筋書きで通る。`progress.md` のマスタと経歴書の行が、spec の列に `.kiro/specs/backend-go-master-resumes`、状態の列に「作り終えた」を持ち、`go test -tags compat -run TestCoverage_Operations ./compat/` が通る
  - 受入基準とテストの対応: 要件3の受入基準4(退会してすでに居ない利用者の要求に Java 版と同じ答えを返す)は、`deleted-user.yaml` で確かめる。要件6の受入基準3のうち、進み具合の表にこの spec の場所と「作り終えた」を書くことは、`progress.md` の文で確かめる。要件3の受入基準3と要件4の受入基準4のうち、答えを変えた要求を変えた動きの一覧に載せることは、`changed-behaviors.yaml` の CB-047 から CB-049 の文で確かめる。この3つの要求への Go 版の答えは、小タスク3.4、3.5、3.6 の `service_integration_test.go` と、小タスク5.1 の `resumes_test.go` で確かめる
  - _要件: 3.3, 3.4, 4.1, 4.4, 6.3_
  - _依存: 6.1_

- [ ] 6.7 版をまたいで確かめる筋書きを書いて通す

  Claude は、まず、版をまたいで確かめる筋書きの送り先を確かめるテスト `TestCrossRoute_ResumeSteps` を `backend/compat/harness/cross_test.go` に作る。このテストは、`scenarios/resumes/` の、`modes` に `cross` を書いた筋書きを読み、Java 版から Go 版の向きと Go 版から Java 版の向きのそれぞれで、`expect.values` を持つ段が、その前の変える段と違う版に送られることを確かめる。このテストは、`cross-resume.yaml` が無ければ失敗する。Claude は、次に、マスタと経歴書の操作の筋書きの節のとおりに、`cross-resume.yaml` を書く。
  - 完了の確かめ方: `go test -tags compat -run TestCrossRoute_ResumeSteps ./compat/harness/` が通る。`make compat-cross` が、Java 版から Go 版の向きと Go 版から Java 版の向きで通る
  - 受入基準とテストの対応: 要件5の受入基準1(一方の版で作った経歴書と足した項目を、もう一方の版で読み、直し、消せる)と要件5の受入基準2(もう一方の版が同じ時刻として返す)は、`cross-resume.yaml` の `expect.values` で確かめる。要件5の受入基準3(両方の向きの筋書きを CI で動かす)は、`make compat-cross` の `TestCross_Scenarios` と、`TestCrossRoute_ResumeSteps` で確かめる
  - _要件: 5.1, 5.2, 5.3_

- [ ] 6.8 主な操作の応答の時間を測る

  Claude は、マスタと経歴書の操作の筋書きの節のとおりに、5つの `perf-*.yaml` を `modes: [perf]` で書く。Claude は、5つの `perf-*.yaml` で測る経歴書に、`fixtures/resumes/fonts.sql` の、6つの欄のすべてに項目を持つ経歴書を使う。Claude は、置き換えの spec の測り方で5つの操作の応答の時間を測り、結果を、`progress.md` の決まりのとおりに `progress.md` に書く。
  - 完了の確かめ方: `make compat-perf` が5つの操作を測り、`progress.md` に結果が書かれる。6つ目の大きなまとまりの最後のタスクなので、完了条件の2つ目のとおり `/verify-backend` も通る
  - 受入基準とテストの対応: 要件4の受入基準5(5つの主な操作の応答の時間を、6つの欄に項目のある経歴書で測る)は、`make compat-perf` の `TestPerf_Scenarios` の結果で確かめる
  - _要件: 4.5_

- [ ] 7. API の説明画面で確かめて進み具合を書く
- [ ] 7.1 API の説明画面でマスタと経歴書の操作を確かめる

  Claude は、この作業フォルダの最上位から compose の `backend-go` を作り直して起動し、この作業フォルダのコードを動かす。Claude は、API の説明画面での確認の節のとおりに、開発環境の compose の `api-docs`(ポート 8082)を Playwright で開いて確かめる。Claude は、確かめた結果を、`/ship` で作るこの spec の PR の本文に書く。
  - 完了の確かめ方: 技術スタックのマスタの取得、経歴書の作成、職歴の追加、経歴書1件の取得の「Try it out」が、それぞれ 200、201、201、200 を返す。経歴書1件の取得の答えに、足した職歴が入っている
  - 受入基準とテストの対応: 要件1の受入基準2のうち、Go 版を相手に経歴書を作り、項目を足し、入力の候補を見られることは、4つの操作の「Try it out」の答えで確かめる
  - _要件: 1.2_

- [ ] 7.2 試作の記録を書き足す

  Claude は、実装で確かめた Java 版の動きを、research.md に書き足す。Claude は、`/ship` で作るこの spec の PR の本文に、次の3つを書く。

  1. 進み具合の表の状態の列を「比べる検査に通った」にする PR を、この PR のマージのあとに出すこと
  2. Java 版の答えで、作業の工程の `systemTest` と `maintenance` の値が入れ替わること
  3. 画面が送らない書き方の値に、Go 版が Java 版と違う答えを返すことと、その違いを載せた変えた動きの一覧の CB-051 から CB-055

  Claude は、状態の列を「比べる検査に通った」にすることを、このタスクで扱わず、小タスク7.3 で扱う。
  - 完了の確かめ方: research.md に、実装で確かめた Java 版の動きが書き足されている。この spec の PR に入れる最後のタスクなので、`/verify-backend` も通る
  - 受入基準とテストの対応: 要件6の受入基準1と2(設計の前に試しに作り、同じにできない動きが見つかれば止まる)は、research.md の試作の記録と書き足しで確かめる
  - _要件: 6.1, 6.2_

- [ ] 7.3 この spec の PR のマージのあとに、進み具合の表を「比べる検査に通った」にする PR を出す

  Claude は、`/ship` で、この spec の PR がマージされたことを確かめる。この spec の PR は、Java 版と Go 版を比べる検査を含む必須のチェックがすべて通ったときにだけマージされる。Claude は、マージを確かめたあと、同じ会話で、main から新しい featureブランチを作り、`progress.md` のまとまりの表のマスタと経歴書の行の状態の列を「比べる検査に通った」にして、`/ship` で PR を出す。
  - 完了の確かめ方: 出した PR がマージされ、main の `progress.md` のマスタと経歴書の行の状態の列が「比べる検査に通った」になっている
  - 受入基準とテストの対応: 要件6の受入基準3のうち、Java 版と Go 版を比べる検査に通ったら状態を「比べる検査に通った」にすることは、main の `progress.md` の文で確かめる。これを確かめるテストは無い
  - _要件: 6.3_
  - _依存: 7.2_

## 実装のメモ

- Claude は、途中のタスクのテストを、`bash .claude/scripts/parallel/run-check.sh backend-go <コマンド>` の形で流す。タスクの「完了の確かめ方」の `go test` と `make` のコマンドは、この `<コマンド>` にあたる。Claude は、`go test` を、`backend/` を作業の場所として流す
- `backend/compat/` の下のファイルは、すべて `//go:build compat` を持つ。Claude は、Java 版と Go 版を比べる検査を広げる4つ目の大きなまとまりと、筋書きで比べる6つ目の大きなまとまりで足すテストにも、同じビルドタグを付ける
- `internal/resume` の結合テストは、ビルドタグを持たず、`make test` と CI の Go 版の検査で毎回動く
- `TestCompare_Scenarios` の副テストの名前は、筋書きの `name` である。Claude は、筋書きを1つずつ確かめるときは、`-run 'TestCompare_Scenarios/<name>'` で選んで流す。選んで流しても、Java 版と Go 版のイメージは毎回組み立てられるので、1回に長い時間がかかる
- Claude は、仕様書の要求の型に `x-go-type: json.RawMessage` だけを足し、`x-go-type-import` は足さない。oapi-codegen v2.8.2 の生成したコードは、元から `encoding/json` を読み込む。そのため、`x-go-type-import` を足すと、生成したコードは `encoding/json` を2回読み込み、Go のコンパイラはそのコードをコンパイルできない。Claude は、このことを、仕様書の要求の本文と項目の ID の型を書き換える小タスク1.2 で確かめた。
- `db/queries/resumes.sql` の問い合わせは、技術スタックの列 `TEXT[]` を、JSON を通して読み書きする。読むときは `to_jsonb(pts)` で行を JSON にし、書くときは `jsonb_populate_record(NULL::project_tech_stacks, ...)` で JSON を行にする。JSON を通すのは、次の2つのためである。sqlc v1.31.1 は、`TEXT[]` を `[]string` にする。pgx v5 は、要素の NULL を `[]string` に読めない。Claude は、`sqlc.yaml` の型の上書きを使わない。型の上書きは、ゲート設定の変更になるためである。`store.go` は、この JSON を `[]*string` の欄を持つ Go の構造体と読み書きし、35の鍵を全部送る。JSON に無い鍵の列は NULL になるためである。Claude は、このことを、マスタと経歴書の SQL の問い合わせを書いて生成する小タスク1.3 で確かめた。
- 変えた動きの一覧 `changed-behaviors.yaml` に項目を足す小タスクは、一覧の項目の数を確かめる `match_test.go` の `TestLoadChangedBehaviors_CB005HasNoMatch` の期待する数も替える。替えないと、このテストが失敗する。Claude は、一覧の項目を、番号の順に並べる。
- 項目の経路の ID の先頭にタブを付けた値も、Java 版は読み、Go 版は読まない。`ids_test.go` の表は、この違いを CB-051 に当てている。一方、`changed-behaviors.yaml` の CB-051 の java の欄は「片側にだけ半角の空白」と書くだけで、タブに触れていない。Claude は、一覧の項目を足す小タスク6.2 で、CB-051 の java の欄と go の欄に、タブを付けた値の読み方を書き足す。Claude は、このことを小タスク2.2 の審査で知った。
- UTF-8 として誤ったバイトのうち、overlong の `c0 80` を文字列の欄に入れた本文に、Java 版は 500 で答え、Go 版は U+FFFD に置き換えて読む。`body_test.go` の表は、この3件を CB-055 に当てている。一方、`changed-behaviors.yaml` の CB-055 の java の欄は「一部を断り、一部を受けて ? で保存する」と書くだけで、500 で答えることに触れていない。Claude は、一覧の項目を足す小タスク6.2 で、CB-055 の java の欄に、500 で答える書き方を書き足す。Claude は、このことを小タスク2.4 の審査で知った。
- Go の `encoding/json` は、`\u0000` の書き方を U+0000 として読む。PostgreSQL の `TEXT` の列は U+0000 を含む値を断る。Claude は、経歴書と6つの欄の項目を読み書きする小タスク3.1 で、U+0000 を含む値を書いたときの Go 版の答えを確かめ、Java 版と違えば変えた動きの一覧に載せる。Claude は、このことを小タスク2.4 の審査で知った。
- 小タスク2.5 の受入基準は、どのテストも1899年と1900年と2100年と2101年の値を含むと書く。経歴書の作成の要求(`CreateResumeRequest`)には年月と日付の欄が無いので、`TestValidate_Resume` は年の値を含まない。年の範囲の検査は、ほかの3つのテストが確かめる。Claude は、PR の本文に、この食い違いと、要件2の受入基準1を満たすと考える理由を書く。Claude は、このことを小タスク2.5 の審査で知った。
- `rules.go` の経歴書の名前と姓と名の検査は、`validate.go` の要求の検査と同じく、入力が要ることと長さの上限の誤りも足す。Claude は、経歴書の操作の Service を作るまとまり3のタスクで、要求の検査に誤りがあればそこで 400 を返し、値の決まりの検査を呼ばない順にする。両方を呼ぶと、同じ文言が2つ並ぶためである。Claude は、このことを小タスク2.7 の審査で知った。
- Java 版の経歴書の名前の使えない文字の検査は、名前に5つの改行の文字(`\n` `\r` U+0085 U+2028 U+2029)のどれかがあると、使えない文字を断らない。画面の1行の入力欄は U+0085 と U+2028 と U+2029 を貼り付けで送れるので、`rules.go` は要件2のとおり Java 版と同じ条件で断る。Claude は、このことを小タスク2.7 の審査で知った。
- Go の `golang.org/x/text/collate` の日本語の並べ方は、半角のカタカナの「ｱｲｳ」を「Zenn」と「あいう」のあいだに並べる。Java 版の `java.text.Collator` は「ｱｲｳ」を最後に並べる。`order_test.go` の `goNameOrder` がこの順を確かめる。Claude は、小タスク6.2 で、変えた動きの一覧の CB-001 の Go 版の欄にこの違いが書かれているかを確かめ、書かれていなければ書き足す。
- 小タスク3.1 で、U+0000 を含む値の書き込みを PostgreSQL が断り、書き込みが失敗することを確かめた(`store_integration_test.go` の `TestStore_NullCharacter`)。research.md の155行のとおり Java 版も 500 で答え、design.md の607行のとおり Go 版もデータベースの誤りを 500 で答える。同じ動きなので、変えた動きの一覧には載せない。上の小タスク2.4 のメモへの答えである
- `db/queries/resumes.sql` の374行の注記「Java 版と同じく、技術スタックの行が無ければ何も書かない」は誤りである。Java 版の `MyBatisResumeRepository.save` はプロジェクトの行を消して書き直すので、技術スタックの行を作る。Go 版の `updateProject` は、技術スタックの行が無いと技術スタックの変更を捨てる。どちらの版もプロジェクトを作るときに技術スタックの行を書くので、行が無いことは手で直したデータでしか起きない。注記は小タスク1.3 の範囲なので直さず、PR 本文に書く。Claude は、このことを小タスク3.1 の審査で知った
- 経歴書の作成と基本の情報の更新は、名前の重なりを、`store.go` の `resumeNameExists`(データベースへの問い合わせ。名前が完全に一致する経歴書を探す)で確かめる。design.md の経歴書をコピーして作る処理の流れの図も、同じ名前の経歴書があるかをデータベースに尋ねると書く。そのため、`rules.go` の `checkResumeNameDuplicated` は本番のコードから呼ばれず、テストだけが使う。tasks.md の小タスク3.4 の本文は、名前の重なりを小タスク2.7 の部品で確かめると書くが、Go 版は2.7 の部品のうち誤りの値 `errResumeNameDuplicated` だけを使う。Claude は、このことを小タスク3.4 の審査で知った
- 項目の変更が経歴書の行を固定することは、別のトランザクションで経歴書の行に `FOR UPDATE` の鍵をかけ、`pg_stat_activity` で鍵を待つ接続が揃うのを待ってから鍵を外すと、確実に確かめられる(小タスク3.5 の `TestService_EditResumeConcurrentLimit`)。追加を同時に送るだけでは、追加が順に流れて、行を固定しない写しでもテストが通った。小タスク3.6 の4つの欄の追加も同じ `editResume` で行を固定するので、Claude は、行の固定をこのテストだけで確かめ、欄ごとの同時の追加のテストは足さなかった
- `run-check.sh` は、ほかの会話が同時に流せる数の枠をすべて使っているとき、`--wait` を付けないと順番待ちの文だけを出して何も流さずに終わる(終了コード10)。Claude は、台本の中や審査役に渡すコマンドでは `run-check.sh --wait` を使う
- 壊して確かめる台本で、置き換える文字の中の `\n` と `\t` を perl で改行とタブに直すときは、逆斜線を `\x5c` と書く。台本を書き写すときに逆斜線が1つ落ちると、置き換えが働かず、改行を含む壊し方は「見つからない」で終わるか、Go のコードの書き間違いでビルドが失敗する。ビルドの失敗はテストの失敗と見分けにくいので、Claude は、結果に「build failed」が出た壊し方を、ビルドが通る形に直して流し直す。Claude は、このことを小タスク4.1 の確かめで知った

## 完了条件(全タスク共通)

Claude は、どのタスクでも、タスクの箇条書きの欄を書いたうえで、次の4つを満たしたときにタスクを完了とする。

1. Claude は、タスクが満たす requirements.md の受入基準(要件の番号付きの項目)ごとに、それを確かめるテストのファイル名とテスト名を「受入基準とテストの対応」の行に書く。Claude は、確かめるテストの無い受入基準を残さない。
2. タスクで変えたファイルを使うテストが、すべて成功している。`1.` や `2.` の見出しのタスクを大きなまとまりと呼ぶ。大きなまとまりの最後のタスクでは、加えて、そのまとまりのタスクで変えた領域の verify のスキル(`/verify-frontend` `/verify-backend` `/verify-terraform`)が、すべて成功している。
3. Claude は、テストを飛ばす設定、アサーションの削除、カバレッジや lint の対象からの除外を足して、完了条件を満たしたように見せない。CI の escape-hatch の検査が、これらの追加を機械で見つける。
4. Claude は、新しく書いたテストについて、テストの対象のコードを一時的に壊してテストが失敗することを確かめる。Claude は、新しいテスト1件につき1か所だけを、作業フォルダの外の写しで壊し、そのテストだけを流す。壊した写しの作り方と流し方は、`.kiro/steering/tech.md` の「テストの完全性」に従う。
