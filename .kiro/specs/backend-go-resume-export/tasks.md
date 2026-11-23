# タスク

- [x] 1. 出力の操作の土台を作る
- [x] 1.1 出力の経歴書の初期のデータを書く

  Claude は、初期のデータと要求の本文の節のとおりに、`backend/compat/fixtures/export/export.sql` に、経歴書 601 と 701 と、経歴書 201 に自己PR を1件足す行を書く。Claude は、ポートフォリオと SNS と自己PR の項目の名前を、`fonts.sql` と同じく、名前の頭の英大文字(`A ` と `B `)で順が決まる名前にする。

  `backend/compat/harness/fixtures_test.go` の `TestFixtures_AllLoadable` は、`fixtures/` の4つのフォルダのほかにあるファイルを「知らない種類のファイルです」で失敗にする。そのため、Claude は、このテストに `export` のフォルダの場合を足す。足した場合では、このテストは、`export/*.sql` を `users` と `resumes` の SQL のあとにデータベースに読み込み、`users` と `resumes` の SQL と同じ決まりで確かめ、`export/*.json` を JSON として読めることを確かめる。このテストは、小タスク6.1 と6.2 がこのフォルダに置く要求の本文も、この場合で確かめる。Claude は、`backend/compat/harness/fixtures.go` の `FixturesDir` のコメントの「中のフォルダは次の4つ」を5つにし、`export/` の中身を書き足す。
  - 完了の確かめ方: `backend/compat/fixtures/export/export.sql` があり、`users/basic.sql` と `resumes/many-pages.sql` のあとに入れると、データベースに誤り無く入る。経歴書 601 と 701 が出力の前提を満たす。`go test -tags compat -count=1 -run TestFixtures_AllLoadable ./compat/harness/` が通る
  - 受入基準とテストの対応: Claude は、この小タスクで確認に使う道具を作り、この小タスクでは受入基準を直接は確かめない。初期のデータは、小タスク1.2 の答えの控えと、4つ目の大きなまとまりの結合テストと、6つ目の大きなまとまりの筋書きが使う
  - _要件: 5.1_

- [x] 1.2 Java 版の答えを正解のファイルに控える

  Claude は、Java 版の答えの正解のファイルの節のとおりに、main の Java 版を試作用のコンテナで動かす。Claude は、Java 版を、Java 版と Go 版を比べる検査と同じ `docker/backend/Dockerfile.prod` のイメージで組み立て、`backend/compat/harness/versions.go` の `JavaEnv` が Java 版に渡す環境変数と同じ名前の環境変数で起動する。dev のプロファイルの Java 版は、データベースと Redis のつなぎ先を、開発環境の localstack の秘密の値 `keirekipro/rds` と `keirekipro/redis` から読む。この2つの秘密の値は、データベース `keireki_pro` と Redis の DB 0 を指す。そのため、Claude は、Spring の設定を上書きする2つの環境変数を足して、Java 版に渡す。Claude は、環境変数 `SPRING_DATASOURCE_URL` に `keireki_proto` を指す URL を入れ、環境変数 `SPRING_DATA_REDIS_DATABASE` に 7 を入れる。Spring Boot は、同じ設定が環境変数と取り込んだ秘密の値の両方にあるときは、環境変数の値を使う。そのため、Java 版は、この2つの環境変数の値でデータベースと Redis につなぐ。Spring Boot のこの順は、公式の文書 https://docs.spring.io/spring-boot/reference/features/external-config.html に書かれている。Claude は、localstack の秘密の値 `keirekipro/rds` と `keirekipro/redis` を書き換えない。Claude は、起動したあと、要求を送る前に、Java 版の `/actuator/env` で `spring.datasource.url` が `keireki_proto` を指し、`spring.data.redis.database` が 7 であることを確かめる。こうして、Claude は、所有者の開発のデータベース `keireki_pro` と Redis の DB 0 に触れない。Claude は、`keireki_proto` を作ってマイグレーションを流し、`users/basic.sql` と、`resumes/` の `many-pages.sql` `long-text.sql` `fonts.sql` `empty.sql` と、小タスク1.1 の `export/export.sql` を入れる。Claude は、ログインと CSRF の値の付け方を、Java 版と Go 版を比べる検査の `backend/compat/harness/capture.go` の手順に合わせる。

  試作の入力はリポジトリに無いので、Claude は、research.md の「本文の数の欄と型の読み方」の表のすべての書き方と値の種類を含む入力を作り直す。Claude は、その Java 版に要求を送り、正解のファイルの節の表の4つの正解のファイルを置く。4つの正解のファイルは、`backend/internal/resume/testdata/export/` の `markdown/*.md` と `body.json` と `filenames.json` と、`backend/internal/httpapi/testdata/exportdisposition.json` である。Claude は、`body.json` に、数の欄に真偽を入れた本文と、文字列の欄に指数の付いた数を入れた本文への Java 版の答えも入れる。`exportdisposition.json` には、経歴書の名前と出し方とヘッダに加えて、Java 版がヘッダに入れた拡張子付きのファイル名を入れる。経歴書の名前に経歴書の決まりで使えない字を入れるときは、Claude は、経歴書の行を `keireki_proto` に SQL で入れてから要求を送る。

  Claude は、控え終えたら、試作用のコンテナを止め、データベース `keireki_proto` を消し、Redis の DB 7 を空にする。
  - 完了の確かめ方: 要求を送る前に、Java 版の `/actuator/env` で、データベースの URL が `keireki_proto` を指し、Redis の DB の番号が 7 だった。正解のファイルの節の表の4つの正解のファイルがあり、正解のファイルの節の「正解のファイルに含めるもの」の箇条の書き方と名前と経歴書が、それぞれの正解のファイルにすべて入っている。試作用のコンテナが止まり、データベース `keireki_proto` が無い
  - 受入基準とテストの対応: Claude は、この小タスクで確認に使う道具を作り、この小タスクでは受入基準を直接は確かめない。正解のファイルは、本文と設定と出力の前提とファイル名を扱う部品を作る3つ目の大きなまとまりと、出力のモデルとひな形と Service の出力を作る4つ目の大きなまとまりの、単体テストと結合テストが使う
  - _要件: 5.1_

- [x] 1.3 仕様書の設定を付けた出力の本文の型を書き換え、生成したコードを作り直す

  Claude は、仕様書の変更の節のとおりに、`backend/api/openapi.yaml` の `ExportResumeRequest` に `x-go-type: json.RawMessage` を足し、`make generate` で生成したコードを作り直す。Claude は、`x-go-type-import` を足さない。Go 版は、このタスクのあとも、出力の操作の要求に未実装の答えを返す。
  - 完了の確かめ方: `make generate-check` が通る。`go test ./internal/httpapi/` が通る。生成したコードの設定を付けた出力の要求の型が、本文を `json.RawMessage` で持つ
  - 受入基準とテストの対応: Claude は、この小タスクで土台を作り、この小タスクでは受入基準を直接は確かめない。要件1の受入基準1のうち、設定を付けた出力の本文を Java 版と同じに読むことは、小タスク3.5 の `exportbody_test.go` と、小タスク5.2 の `resumes_test.go` で確かめる
  - _要件: 1.1_

- [x] 1.4 変えた動きの一覧に、設計で決まった出力の違いを足す

  Claude は、変えた動きの一覧に載せる違いの節のとおりに、CB-056 から CB-061 の6つの違いを、`backend/compat/changed-behaviors.yaml` の末尾に `group: 4` で足す。Claude は、どの違いの「画面に影響が無い理由」にも「所有者が 2026-11-23 に受け入れた(requirements の承認)」と書く。Claude は、CB-056 から CB-061 のどれにも match を書かない。CB-056 から CB-058 の違いは、PDF を比べる部品が許す幅の中で扱うためである。CB-059 から CB-061 の要求と本文は、Java 版と Go 版を比べる検査が送らないので、match が照らす答えが無いためである。Claude は、CB-004 の文に、PDF の文字の位置と「〜」のほかの Go 版の PDF の違いを CB-056 から CB-058 に載せたことを書き足す。Claude は、`backend/compat/harness/match_test.go` の `TestLoadChangedBehaviors_CB005HasNoMatch` の期待する数を、55 から 61 に替える。CB-062 は、Go 版の本文の読み手の答えが決まる小タスク3.5 で、違いがあるときだけ足す。
  - 完了の確かめ方: `go test -tags compat ./compat/harness/ -run 'TestLoadChangedBehaviors|TestChangedBehaviors'` が通る。1つ目の大きなまとまりの最後のタスクなので、大きなまとまりの最後のタスクで verify のスキルを流すと決めた完了条件の2つ目のとおり、`/verify-backend` も通る
  - 受入基準とテストの対応: 要件1の受入基準2のうち、Java 版と答えが変わる要求を変えた動きの一覧に載せることと、要件2の受入基準4のうち、PDF の3つの違いを変えた動きの一覧に載せることは、`changed-behaviors.yaml` の CB-056 から CB-061 の文と、`match_test.go` の `TestLoadChangedBehaviors_CB005HasNoMatch` と `TestLoadChangedBehaviors_RequiredFields` で確かめる。Go 版の答えが一覧のとおりであることは、一覧の項目ごとに設計が決めたテストで確かめる。CB-056 から CB-058 は小タスク2.2 と2.3 の `pdfcmp_test.go`、CB-059 と CB-060 は小タスク5.2 の `resumes_test.go`、CB-061 は小タスク3.5 の `exportbody_test.go` である
  - _要件: 1.2, 2.4_

- [ ] 2. 確認に使う道具を広げる
- [ ] 2.1 筋書きの要求と期待の欄を足す (並行可)

  Claude は、Java 版と Go 版を比べる検査の広げ方の節のとおりに、`backend/compat/harness` の筋書きの形を広げる。Claude は、要求の `json_file` を `scenario.go` と `capture.go` に、期待の `body_contains` を `scenario.go` と `steps.go` に足す。Claude は、期待の `content_type` を、版に送る段でも書けるように、`validateVersionBody` の断る条件から外し、`checkStepExpect` で確かめる。`scenario_test.go` の `TestScenarioValidate_UserFields` の場合「版に送る段の expect の content_type」は、今の断る条件で筋書きが断られることを期待するので、この変更のあとに失敗する。そのため、Claude は、この場合を `TestScenarioValidate_UserFields` から外し、版に送る段の `content_type` を書いた筋書きが断られずに読めることを確かめる場合として、`TestExpectContentType_VersionStep` に移す。Claude は、移した場合のアサーションを消さず、期待だけを替える。
  - 完了の確かめ方: `go test -tags compat ./compat/harness/ -run 'TestLoadScenarios|TestCapture|TestExpect|TestScenarioValidate'` が通る
  - 受入基準とテストの対応: 要件5の受入基準2のうち、Java 版と Go 版を比べる検査が Content-Type と答えの本文を確かめることと、要件6の受入基準2のうち、版をまたいで確かめる検査が Markdown の本文に保存した版の値が出ていることを確かめることは、次のテストで確かめる。
    - `scenario_test.go` の `TestLoadScenarios_JSONFileExclusive` は、`json_file` を `json` と `multipart` と `body_file` のどれかと同時に書いた筋書きと、無いファイルと JSON として読めないファイルを書いた筋書きを、筋書きを読む時点で断ることを確かめる
    - `capture_test.go` の `TestCapture_JSONFileSentAsIs` は、`json_file` のファイルのバイトをそのまま本文にし、Content-Type を `application/json` にして送ることを確かめる
    - `steps_test.go` の `TestExpectContentType_VersionStep` と `TestExpectBodyContains` は、版に送る段の `content_type` と `body_contains` を確かめ、合わないときに、段の名前と見つからない字の並びを報告に書くことを確かめる。`TestExpectBodyContains` は、`{名前}` を差し込んだ値も確かめる
  - _要件: 5.2, 6.2_
  - _対象の部品: Java 版と Go 版を比べる検査の広げ方_

- [ ] 2.2 PDF を比べる部品の、頁の大きさとフォントと字の比べ方を決め直す (並行可)

  Claude は、PDF を比べる部品の節のとおりに、`backend/compat/pdfcmp/pdfcmp.go` の比べ方のうち、頁の大きさ、フォント、文書の全体の字の並び、フォントと色ごとの字の数の4つを決め直す。Claude は、今の字の直し方の関数 `normalizeText` を、設計の字の直し方に置き換え、Java 版の行の左の端で列をまとめる処理を作る。Claude は、文書の全体の字の並びを `pdftotext -bbox-layout` の行から、フォントと色ごとの字の数を `pdftohtml -xml -fontfullname` から取る。Claude は、今の `pdftotext -layout` で頁ごとの字を読む `readTexts` と、頁ごとの字を比べる `firstDifferentLine` を、文書の全体の字の並びの比べ方に置き換えて消す。Claude は、`Describe` と `Compare` の形と、Java 版と Go 版を比べる検査への違いの渡し方を変えない。Claude は、このタスクで作る違いの種類に、PDF を比べる部品の節の表の名前を使う。

  `pdfcmp_test.go` の今の6つのテストのうち、`TestCompare_RejectsOneCharDiff` の1つ目の場合は、このタスクで消す `firstDifferentLine` が作る説明「[ページの文字] ページ 1: 行 1: …」を期待する。そのため、Claude は、この場合の期待を、`Describe` の2つの説明が違いの種類「文書の字の並び」を書き、Java 版の説明に「Hello World」の行の字を、Go 版の説明に「Hello Worle」の行の字を含む形に替える。`TestCompare_RejectsPageBreakDiff` の1つ目の場合は、頁ごとの字の違いを期待する。しかし、文書の全体の字の並びで比べると、この場合の2つの PDF の字は同じになる。この場合の頁の違いは、小タスク2.3 の行の組の比べ方で初めて見つかる。そのため、Claude は、この場合の期待を小タスク2.3 で替え、このタスクの完了を確かめるときには `TestCompare_RejectsPageBreakDiff` を流さない。Claude は、どのテストのアサーションも消さず、期待だけを替える。
  - 完了の確かめ方: `go test -tags compat ./compat/pdfcmp/ -run 'TestCompare_Allows2ptShift|TestCompare_Rejects2_5ptShift|TestCompare_RejectsOneCharDiff|TestCompare_FontSubsetPrefixIgnored|TestCompare_TableColorTolerance|TestCompare_PageSizeTolerance|TestNormalizeText|TestCompare_RejectsMissingChar|TestCompare_RejectsFontColorCount|TestCompare_TwoColumnOrder'` が通る。`TestCompare_RejectsPageBreakDiff` は、小タスク2.3 の完了を確かめるときに流す
  - 受入基準とテストの対応: 要件5の受入基準5の1つ目と2つ目の箇条のうち、頁の大きさと、PDF から写した字と、語と行の区切りの違いを違いとせず、フォントと頁ごとの字の違いを違いとすることと、要件2の受入基準4の頁の大きさと PDF から写した字は、`pdfcmp_test.go` の次のテストで確かめる。Claude は、テストの PDF を、`pdf_helper_test.go` の作り方で、テストの中で作る。
    - `TestCompare_PageSizeTolerance` は、頁の大きさの違いを 0.3pt なら許し、0.6pt なら違いとすることを確かめる
    - `TestNormalizeText` は、互換漢字と U+2011 と U+FF5E を直し、空白を除くことを確かめる。CJK の字は Type1 の標準フォントで作れないので、このテストは PDF を作らずに `normalizeText` を直接呼ぶ
    - `TestCompare_RejectsMissingChar` は、字が1字抜けた PDF を違いとすることを確かめる
    - `TestCompare_RejectsFontColorCount` は、フォントと色ごとの字の数が違う PDF を違いとすることを確かめる
    - `TestCompare_TwoColumnOrder` は、2列の行を、列、頁、上からの位置の順につないで比べることを確かめる
  - _要件: 2.4, 5.5_
  - _対象の部品: PDF を比べる部品_

- [ ] 2.3 PDF を比べる部品の、行の組と折り返しのまとまりと色の比べ方を決め直す

  Claude は、PDF を比べる部品の節のとおりに、`pdfcmp.go` の行の位置と高さの比べ方を、行の組と折り返しのまとまりで比べる形に決め直す。Claude は、今の語を出てくる順で組にして比べる `compareWords` を、行の組の比べ方に置き換えて消す。Claude は、色の集まりの取り方を、白でなく字の箱の外にある9画素以上の色の集まりにし、折り返しのまとまりが無ければ頁ごとに、あれば文書の全体で比べる。Claude は、`pdfcmp.go` の30行目にある許す幅のコメントが指す先を、この spec の design.md の PDF を比べる部品の節に直す。

  `pdfcmp_test.go` の今の6つのテストのうち、次の2つは、このタスクで消す語の位置の比べ方と頁ごとの字の比べ方の違いの種類を期待する。そのため、Claude は、2つのテストの期待を、行の組の比べ方の違いの種類に替える。Claude は、どのテストのアサーションも消さず、期待だけを替える。
    - `TestCompare_Rejects2_5ptShift` の上下左右に 2.5pt ずれた場合は、違いの種類「語の位置」を期待する。Claude は、この期待を、1頁目の「行の位置」の違いに替える。Claude は、語の箱の高さが違う場合の期待を、「文字の大きさ」の違いだけがあり、「行の位置」の違いが無いことを期待する形に替える
    - `TestCompare_RejectsPageBreakDiff` の1つ目の場合は、1頁目と2頁目の「ページの文字」の違いを期待する。Claude は、この期待を、`TestCompare_RejectsPageBreakDiffWithoutWrap` と同じく、折り返しのまとまりが無いのに組になった行の頁が違うことを違いとする形に替える
  - 完了の確かめ方: `go test -tags compat ./compat/pdfcmp/` が通る。期待を替えた今の6つのテストと、小タスク2.2 で足した頁の大きさとフォントと字の比べ方のテストも通る。2つ目の大きなまとまりの最後のタスクなので、大きなまとまりの最後のタスクで verify のスキルを流すと決めた完了条件の2つ目のとおり、`/verify-backend` も通る
  - 受入基準とテストの対応: 要件5の受入基準5の2つ目と3つ目の箇条(直した部品が、決めた点の違いを違いと判定し、長い文の折り返しから起きた違いを違いと判定しないこと)と、要件2の受入基準4の長い文の折り返しは、`pdfcmp_test.go` の次のテストで確かめる。
    - `TestCompare_AllowsFewerWrappedLines` は、同じ字の段落を Go 版で1行少なく折り返した PDF を許すことを確かめる
    - `TestCompare_RejectsMoreWrappedLines` は、Go 版の行の数が Java 版より多い折り返しを違いとすることを確かめる
    - `TestCompare_RejectsOverShiftAfterWrap` は、折り返しのあとの行が、減った行の高さより大きく上がった PDF を違いとすることを確かめる
    - `TestCompare_RejectsPageBreakDiffWithoutWrap` は、折り返しのまとまりが無いのに改頁の位置が違う PDF を違いとすることを確かめる
    - `TestCompare_RejectsColorSetDiff` は、色の集まりが違う PDF を違いとすることを確かめる
  - _要件: 2.4, 5.5_
  - _依存: 2.2_

- [ ] 3. 本文と設定と出力の前提とファイル名を扱う部品を作る
- [ ] 3.1 PDF の設定の既定の値と直し方を作る (並行可)

  Claude は、PDF の設定の値の節のとおりに、`backend/internal/resume/exportsettings.go` に、`defaultPDFSettings` と `normalizePDFSettings` と、直す前の設定の値の型 `exportPDFSettingsInput` と、直したあとの型 `pdfSettings` を作る。写す元は、Java 版の `ResumePdfExportSettings` である。
  - 完了の確かめ方: `go test ./internal/resume/ -run TestExportSettings` が通る
  - 受入基準とテストの対応: 要件2の受入基準1のうち、設定を付けない出力の既定の設定は、`exportsettings_test.go` の `TestExportSettings_Defaults` で確かめる。要件1の受入基準1のうち、画面が送らない値も Java 版と同じに直すことは、`TestExportSettings_RoundSizes` と `TestExportSettings_NormalizeColor` で確かめる。`TestExportSettings_RoundSizes` は、丸めの境界の x.2 と x.3、x.7 と x.8 と、6 と 72 が直せる値になることと、その外の値が誤りになることを確かめる。`TestExportSettings_NormalizeColor` は、大文字の16進数と赤と緑と青の値が小文字の `#rrggbb` になることを確かめる
  - _要件: 1.1, 2.1_
  - _対象の部品: PDF の設定の値_

- [ ] 3.2 出力の前提の確認と8つの文言を作る (並行可)

  Claude は、出力の前提の確認の節のとおりに、`backend/internal/resume/exportrule.go` に、出力の前提の確認と、足りないものごとの8つの文言と、2つの始まりの文を作る。写す元は、Java 版の `ResumeExportRuleCheckService` である。Claude は、文言を `ResumeExportRuleCheckService.java` の文字列からそのまま写す。
  - 完了の確かめ方: `go test ./internal/resume/ -run TestExportRule` が通る
  - 受入基準とテストの対応: 要件3の受入基準2(出力の前提を満たさない経歴書に、Java 版と同じ文言で答える)は、`exportrule_test.go` の次の2つのテストで確かめる。`TestExportRule_EachMissing` は、8つの足りないもののそれぞれと、すべてが足りないときに、文言が Java 版の順に並ぶことを確かめる。`TestExportRule_LeadingSentence` は、inline と attachment と設定を付けない出力のそれぞれで、始まりの文が出し方ごとの文になることを確かめる
  - _要件: 3.2_
  - _対象の部品: 出力の前提の確認_

- [ ] 3.3 経歴書の名前からファイル名を作る (並行可)

  Claude は、ファイル名の節のとおりに、`backend/internal/resume/filename.go` に `sanitizeFileName` を作る。写す元は、Java 版の `FileUtil.sanitizeFileName` である。
  - 完了の確かめ方: `go test ./internal/resume/ -run TestSanitizeFileName` が通る
  - 受入基準とテストの対応: 要件2の受入基準3のうち、ファイル名を Java 版と同じ規則で経歴書の名前から作ることは、`filename_test.go` の `TestSanitizeFileName_MatchesJava` で確かめる。このテストは、小タスク1.2 で控えた `filenames.json` のすべての名前で、Java 版と同じファイル名になることを確かめる
  - _要件: 2.3_
  - _対象の部品: ファイル名_
  - _依存: 1.2_

- [ ] 3.4 Content-Disposition のヘッダを Spring と同じ規則で作る (並行可)

  Claude は、出力の受け口の節のとおりに、`backend/internal/httpapi/exportdisposition.go` に `formatContentDisposition` を作る。Claude は、ASCII への写し方の字の表を、Spring 7.0.10 の `ContentDisposition` のソースを開いて写す。
  - 完了の確かめ方: `go test ./internal/httpapi/ -run TestFormatContentDisposition` が通る
  - 受入基準とテストの対応: 要件2の受入基準3のうち、日本語の名前でもヘッダの字が Java 版と同じになることは、`exportdisposition_test.go` の `TestFormatContentDisposition_MatchesJava` で確かめる。このテストは、小タスク1.2 で控えた `exportdisposition.json` のすべての項目で、項目のファイル名と出し方から、Java 版と同じヘッダを作ることを確かめる。`sanitizeFileName` が `"` と `\` を `_` に替えるので、正解のファイルのファイル名には `"` と `\` が入らない。そのため、Claude は、ファイル名の `"` と `\` を書き換える処理を、`TestFormatContentDisposition_EscapesQuoteAndBackslash` で、テストの中の表で確かめる
  - _要件: 2.3_
  - _対象の部品: 出力の受け口_
  - _依存: 1.2_

- [ ] 3.5 設定を付けた出力の本文を読み、断る条件で確かめる

  Claude は、出力の本文の読み手の節のとおりに、`backend/internal/resume/exportbody.go` に、設定を付けた出力の本文の読み手と、断る条件の確認を作る。本文の読み手は、PDF の設定を小タスク3.1 の `exportPDFSettingsInput` に読む。Claude は、断る条件と文言を `ExportResumeRequest.java` の注釈から写す。

  Claude は、`body.json` の本文のうち画面が送らない書き方で、Go 版の答えが Java 版と違う書き方があれば、CB-062 を `changed-behaviors.yaml` に `group: 4` で足し、`match_test.go` の `TestLoadChangedBehaviors_CB005HasNoMatch` の期待する数を1つ増やす。違う書き方が無ければ、Claude は CB-062 を足さない。
  - 完了の確かめ方: `go test ./internal/resume/ -run TestExportBody` が通る。CB-062 を足したときは、`go test -tags compat ./compat/harness/ -run TestLoadChangedBehaviors` も通る。3つ目の大きなまとまりの最後のタスクなので、大きなまとまりの最後のタスクで verify のスキルを流すと決めた完了条件の2つ目のとおり、`/verify-backend` も通る
  - 受入基準とテストの対応: 要件1の受入基準1と2のうち、本文の読み方は、`exportbody_test.go` の `TestExportBody_MatchesJava` で確かめる。このテストは、`body.json` のすべての本文で、画面が送る書き方の本文に Java 版と同じ状態の番号と答えを返すことと、Java 版と違う答えになる本文がテストの中の表(CB-061 と CB-062)と合うことを確かめる。表の番号が `changed-behaviors.yaml` にあることは、`TestExportBody_DiffTableInChangedBehaviors` で `checkDiffTableInChangedBehaviors` を使って確かめる。要件3の受入基準1のうち、5種類の断る条件と、`errors` の鍵が Java 版の道筋になることは、`TestExportBody_RejectRules` で確かめる
  - _要件: 1.1, 1.2, 3.1_
  - _依存: 1.2, 1.4, 3.1_

- [ ] 4. 出力のモデルとひな形と Service の出力を作る
- [ ] 4.1 出力のモデルと Markdown のひな形を作る

  Claude は、出力のモデルとひな形の節のとおりに、`backend/internal/resume/exportmodel.go` に出力のモデルを作り、`templates/resume.md.tmpl` に Markdown のひな形を写し、`exporttemplate.go` に `renderMarkdown` を作る。写す元は、Java 版の `ResumeExportModelBuilder` と `templates/resume/markdown/default.md` である。`exporttemplate.go` は、ひな形を `embed` で読み込み、起動のときに `template.Must` で1度だけ読み込む。
  - 完了の確かめ方: `go test ./internal/resume/ -run 'TestExportModel|TestRenderMarkdown'` が通る
  - 受入基準とテストの対応: 要件2の受入基準2のうち、利用者が書いた `<` `>` `&` `"` `'` を Java 版と同じ形に書き換えることは、`exporttemplate_test.go` の `TestRenderMarkdown_Escapes` で確かめる。出力のモデルの日付と期間の書き方と、作業の工程の並びと、技術スタックの並びと、値の無い欄の扱いは、`exportmodel_test.go` の `TestExportModel_Formats` で確かめる。Markdown の全体が Java 版と1バイトも違わないことは、小タスク4.4 の結合テストで確かめる
  - _要件: 2.2_

- [ ] 4.2 PDF の HTML のひな形を作る

  Claude は、出力のモデルとひな形の節のとおりに、`backend/internal/resume/templates/resume.html.tmpl` に PDF の HTML のひな形を写し、試作で決めた CSS を足す。Claude は、`exporttemplate.go` に `renderPDFHTML` を作る。写す元は、Java 版の `templates/resume/pdf/simple.html` である。
  - 完了の確かめ方: `go test ./internal/resume/ -run TestRenderPDFHTML` が通る
  - 受入基準とテストの対応: 要件2の受入基準1のうち、利用者が選んだフォントと4つの文字の大きさと表の見出しの色が PDF に出ることと、要件2の受入基準4の違いに抑えるための CSS は、`exporttemplate_test.go` の `TestRenderPDFHTML_SettingsAndCSS` で確かめる。このテストは、HTML に、設定の値と、出力のモデルとひな形の節の6つの CSS が入ることを確かめる。利用者が書いた字を HTML として読まれない形で書き、改行を残すことは、`TestRenderPDFHTML_EscapesUserText` で確かめる。PDF の見た目が Java 版と同じことは、小タスク6.1 と6.2 の筋書きで確かめる
  - _要件: 2.1, 2.4_

- [ ] 4.3 Service の出力の2つのメソッドを作る

  Claude は、Service の出力の節のとおりに、`backend/internal/resume/export.go` に、`ExportResume` と `ExportResumeWithSettings` と、出力の結果の型 `Export` と、形式の型 `ExportFormat` を作る。Claude は、`service.go` の `Deps` に `PDF PDFRenderer` を足す。写す元は、Java 版の `ExportResumeUseCase` である。2つのメソッドは、処理の流れの節の確かめる順で、小タスク3.5 の本文の読み手と、マスタと経歴書のまとまりの経歴書の読み取りと、小タスク3.2 の出力の前提の確認と、小タスク3.1 の設定の値の直し方と、小タスク4.1 と4.2 のひな形と、小タスク3.3 のファイル名を呼ぶ。
  - 完了の確かめ方: `go test ./internal/resume/ -run TestExport_` が通る
  - 受入基準とテストの対応: 要件3の受入基準4(本文を断る条件で先に確かめ、断る本文には経歴書によらず本文の誤りで答える)は、`export_test.go` の `TestExport_RejectBodyFirst` で確かめる。このテストは、断る本文の要求に、経歴書の ID が読めないときも、本文の誤りで答え、足りない項目の一覧を入れないことを確かめる。Claude は、無い経歴書と、ほかの利用者の経歴書と、出力の前提を満たさない経歴書で同じことを、小タスク4.4 の結合テストで確かめる。要件1の受入基準1のうち、`Export` が PDF と Markdown の Content-Type とファイル名と出し方を持つことは、`TestExport_ResultFields` で確かめる。`PDF` が nil のときに PDF を求めると誤りになることは、`TestExport_NilPDFRenderer` で確かめる。Claude は、`PDFRenderer` の偽の部品を `export_test.go` に1つだけ作る。小タスク4.4 の結合テストも、この偽の部品を使う。2つのテストのファイルは同じパッケージなので、2つ作ると組み立てられないためである
  - _要件: 1.1, 3.4_

- [ ] 4.4 出力の2つのメソッドの結合テストを書く

  Claude は、テストの方針の節の結合テストのとおりに、`backend/internal/resume/export_integration_test.go` を書く。このテストは、`backend/compat/fixtures` の `users/basic.sql` と、経歴書のファイルと、`export/export.sql` をデータベースに入れ、`Deps` の `PDF` に小タスク4.3 の偽の部品を渡して動く。
  - 完了の確かめ方: `go test ./internal/resume/ -run TestExportIntegration` が通る。4つ目の大きなまとまりの最後のタスクなので、大きなまとまりの最後のタスクで verify のスキルを流すと決めた完了条件の2つ目のとおり、`/verify-backend` も通る
  - 受入基準とテストの対応: 次の受入基準を、`export_integration_test.go` の次のテストで確かめる。
    - 要件2の受入基準2(Markdown を Java 版と1文字も違わないものにする)は、`TestExportIntegration_MarkdownMatchesJava` で確かめる。このテストは、経歴書 601、201、301、401、701 の Markdown が、小タスク1.2 で控えた Java 版の Markdown と1バイトも違わないことを確かめる
    - 要件3の受入基準3(無い経歴書に 404 と Java 版の文言で答える)と要件4の受入基準1(ほかの利用者の経歴書に、無い経歴書と同じ答えを返す)は、`TestExportIntegration_OtherUserIsNotFound` で確かめる。このテストは、無い経歴書が 404 と「対象の職務経歴書データが存在しません。」になることと、ほかの利用者の経歴書が、出力の前提を満たすときも満たさないときも、無い経歴書と同じ誤りになることを確かめる
    - 要件3の受入基準4のうち、無い経歴書と、ほかの利用者の経歴書と、出力の前提を満たさない経歴書でも断る本文が本文の誤りになることは、`TestExportIntegration_RejectBodyFirst` で確かめる
    - 要件4の受入基準2(退会してすでに居ない利用者の要求に、Java 版と同じ答えを返す)は、`TestExportIntegration_DeletedUser` で確かめる。このテストは、退会してすでに居ない利用者の要求に 404 で答えることを確かめる
    - 要件6の受入基準1のうち、出力のあとも保存が残ることは、`TestExportIntegration_NoWrite` で確かめる。このテストは、出力のあとに、経歴書の行と6つの欄の項目が変わっていないことを確かめる
    - 要件2の受入基準1のうち、PDF を設定の値で作ることは、`TestExportIntegration_PDFReceivesHTML` で確かめる。このテストは、偽の部品に、設定の値を入れた HTML が渡ることを確かめる
  - _要件: 2.1, 2.2, 3.3, 3.4, 4.1, 4.2, 6.1_
  - _依存: 1.1, 1.2_

- [ ] 5. 出力の受け口をつなぐ
- [ ] 5.1 答えの型に Content-Disposition を足し、設定を付けない出力に Accept の行を渡す

  Claude は、出力の受け口の節のとおりに、`backend/internal/httpapi/authresponses.go` の `authResponse` に `contentDisposition` の欄を足し、`write` で書く。Claude は、`resumeresponses.go` に、`_ gen.ExportResumeResponseObject = authResponse{}` と `_ gen.ExportResumeWithSettingsResponseObject = authResponse{}` と、2つの `Visit` の関数を足し、26の操作と書いたコメントを28にする。Claude は、`auth.go` の `authRequestMiddleware` が Accept の行を context に入れる操作に、`ExportResume` を足す。
  - 完了の確かめ方: `go test ./internal/httpapi/ -run 'TestResumeResponses|TestAuthRequestMiddleware|TestAuthResponses'` が通る
  - 受入基準とテストの対応: 要件1の受入基準1のうち、答えに Content-Disposition のヘッダを書くことは、`auth_test.go` の `TestAuthResponses_ContentDisposition` で確かめる。応答の型の数は、`resumes_test.go` の `TestResumeResponses_AllOperationsWrite` の期待を26から28にして確かめる。設定を付けない出力が Accept の行を受け口で読めることは、`auth_test.go` の今の `TestAuthOIDCHandlers_MiddlewareOnlyOIDC` を `TestAuthRequestMiddleware_Operations` に名前を替えて広げて確かめる。Claude は、このテストの表に `ExportResume` と `ExportResumeWithSettings` を足す。このテストは、`authRequestMiddleware` が、`ExportResume` のときだけ Accept の行を context に入れ、`ExportResumeWithSettings` では入れないことを確かめる。Claude は、テストのコメントを、値を入れる3つの操作の説明に直す。同じことを確かめるテストを2つにしないためである
  - _要件: 1.1_

- [ ] 5.2 出力の2つの受け口を作り、経路につなぐ

  Claude は、出力の受け口の節のとおりに、`backend/internal/httpapi/resumes.go` の `ResumeService` に出力の2つのメソッドを足し、`ExportResume` と `ExportResumeWithSettings` の受け口を作る。2つの受け口は、小タスク3.4 の `formatContentDisposition` でヘッダを作る。Claude は、`server.go` の `Options` の `ResumeHandlers` のコメントと `resumeOperations` を、26の操作から28の操作にする。
  - 完了の確かめ方: `go test ./internal/httpapi/ -run 'TestResumeHandlers|TestResumeRoutes|TestExportHandlers'` が通る
  - 受入基準とテストの対応: 次の受入基準を、`resumes_test.go` の次のテストで確かめる。
    - 要件1の受入基準1のうち、設定を付けない出力が Accept の行で形式を選ぶことと、要件1の受入基準2のうち、Java 版と違う読み方になる Accept の行がテストの中の表(CB-059)と合うことは、`TestExportHandlers_AcceptSelectsFormat` で確かめる。どの形式も選べない Accept の行に 406 で答えることも、このテストで確かめる
    - 要件1の受入基準1のうち、出力の2つの操作が状態の番号 200 と、Content-Type と Content-Disposition と本文を書くことは、`TestExportHandlers_SuccessHeaders` で確かめる
    - 要件1の受入基準2のうち、Accept の行に `application/json` の無い断る本文の要求に 400 と JSON の本文で答えること(CB-060)は、`TestExportHandlers_RejectWithoutJSONAccept` で確かめる
    - `ResumeHandlers` が無いときに出力の操作の要求に今と同じ未実装の答えを返すことは、`TestResumeRoutes_Unimplemented` で確かめる。`httpapi.New` に `ResumeHandlers` を渡すと28の操作の要求が受け口に届くことは、`TestResumeRoutes_Wired` で確かめる
  - _要件: 1.1, 1.2_
  - _依存: 1.4, 3.4, 4.3_

- [ ] 5.3 Go 版を起動する入口で、PDF の部品を経歴書の処理に渡す

  Claude は、main.go の節のとおりに、`backend/cmd/keirekipro/main.go` の `resume.New` を `d.newPDF` のあとに移し、`resume.Deps` に PDF の部品を渡す。Claude は、`main_test.go` に `TestRun_PassesPDFEngineToResume` を足す。手本は、同じファイルの `TestRun_PassesResumeHandlers` である。
  - 完了の確かめ方: `go test ./cmd/keirekipro/ -run 'TestRun_PassesPDFEngineToResume|TestRun_PassesResumeHandlers'` が通る。5つ目の大きなまとまりの最後のタスクなので、大きなまとまりの最後のタスクで verify のスキルを流すと決めた完了条件の2つ目のとおり、`/verify-backend` も通る
  - 受入基準とテストの対応: 要件1の受入基準3のうち、Go 版を相手に PDF を作れることは、`main_test.go` の `TestRun_PassesPDFEngineToResume` で確かめる。このテストは、入口を起動し、出力の前提を満たす経歴書をデータベースに入れ、ログインした利用者として設定を付けた出力で PDF を求め、200 と `application/pdf` と `%PDF-` で始まる本文で答えることを確かめる
  - _要件: 1.1, 1.3_

- [ ] 6. 出力の操作の筋書きで Java 版と Go 版を比べる
- [ ] 6.1 画面が送る4種類の要求の筋書きを書く

  Claude は、出力の操作の筋書きの節のとおりに、`backend/compat/scenarios/export/formats.yaml` を `group: 4` で書き、要求の本文 `backend/compat/fixtures/export/inline-default.json` を置く。Claude は、設定を付けた出力の段に `csrf: true` を付け、Accept の行を `headers` の欄に書く。
  - 完了の確かめ方: `go test -tags compat -count=1 -run 'TestCompare_Scenarios/<formats.yaml の筋書きの名前>' ./compat/` が通る
  - 受入基準とテストの対応: 要件1の受入基準1(4種類の要求に、Java 版と同じ状態の番号とヘッダで答える)と、要件2の受入基準1から3(PDF の見た目と、Markdown の字と、ファイル名を Java 版と同じにする)と、要件5の受入基準1のうち4種類の要求を5つの経歴書に送ることは、`formats.yaml` の Java 版と Go 版を比べる検査で確かめる。Java 版と Go 版を比べる検査は、状態の番号と、Content-Type と Content-Disposition のヘッダを比べ、PDF を小タスク2.2 と2.3 で決め直した比べ方で比べ、Markdown を字で比べる。要件5の受入基準2のうち、出力のあとのデータベースを比べることも、この検査で確かめる。要件1の受入基準3のうち、画面と同じ要求で3つの操作を終えられることも、この筋書きで確かめる
  - _要件: 1.1, 1.3, 2.1, 2.2, 2.3, 5.1, 5.2_
  - _依存: 2.1, 2.3, 5.3_

- [ ] 6.2 PDF の設定の値と断る条件の筋書きを書く

  Claude は、出力の操作の筋書きの節のとおりに、`settings.yaml` と `rejects.yaml` を書き、初期のデータと要求の本文の節の表の、`half-step-sizes.json` から `reject-color.json` までの10の要求の本文を `backend/compat/fixtures/export/` に置く。`settings.yaml` は、置き換えの spec が置いた4つの要求の本文を `json_file` で送る。Claude は、`bool-number.json` と `exp-string.json` のうち、Go 版の答えが Java 版と違うと小タスク3.5 の `exportbody_test.go` で分かった本文を、`settings.yaml` から外す。断る条件と誤りの答えを確かめる要求の Accept には、Claude は `application/json` を含める。
  - 完了の確かめ方: `go test -tags compat -count=1 -run 'TestCompare_Scenarios/(<settings.yaml と rejects.yaml の筋書きの名前を | でつないだもの>)' ./compat/` が通る
  - 受入基準とテストの対応: 要件1の受入基準1のうち、画面が送らない設定の値も Java 版と同じに直すことと、要件2の受入基準1のうち、選んだフォントと4つの文字の大きさと表の見出しの色が PDF に出ることと、要件5の受入基準1のうち設定を付けた出力の要求は、`settings.yaml` の Java 版と Go 版を比べる検査で確かめる。要件3の受入基準1(設定を付けた出力の本文を、Java 版と同じ断る条件と文言で断る)と、要件3の受入基準4のうち無い経歴書に断る本文を送ったときの答えと、要件5の受入基準1のうち断る条件の要求は、`rejects.yaml` の Java 版と Go 版を比べる検査で確かめる
  - _要件: 1.1, 2.1, 3.1, 3.4, 5.1_
  - _依存: 3.5_

- [ ] 6.3 出力の前提と無い経歴書とほかの利用者と退会した利用者の筋書きを書き、進み具合の表を「作り終えた」にする

  Claude は、この小タスクで次の3つをする。

  1. Claude は、出力の操作の筋書きの節のとおりに、`prerequisite.yaml`、`not-found.yaml`、`other-user.yaml`、`deleted-user.yaml` を書く。`deleted-user.yaml` の手本は、`scenarios/resumes/deleted-user.yaml` である。
  2. Claude は、進み具合の表の節のとおりに、`.kiro/specs/backend-go-replacement/progress.md` のまとまりの表の出力の行の spec の列に `.kiro/specs/backend-go-resume-export` を書き、状態の列を「作り終えた」にする。状態の列を「作り終えた」にすると、`TestCoverage_Operations` が、出力の2つの操作が `group: 4` の筋書きに1回以上出てくることを求め始める。
  3. Claude は、小タスク6.1 から6.3 の筋書きを書く途中で、Java 版が 500 で答える出力の要求を見つけていたら、変えた動きの一覧に載せる違いの節のとおりに、要求ごとに1つの違いを `changed-behaviors.yaml` に `group: 4` で足し、`match_test.go` の `TestLoadChangedBehaviors_CB005HasNoMatch` の期待する数を足した数だけ増やす。Claude は、その要求に Go 版が 404 か 400 で答えることを確かめるテストを、`export_integration_test.go` に要求ごとに1つ足す。Claude は、退会してすでに居ない利用者の経歴書の作成の要求を載せた、変えた動きの一覧の CB-049 と同じく、その違いに match を書かず、その要求を送る段を、Java 版と Go 版を比べる検査の筋書きから外す。要件5の受入基準1は、Java 版と Go 版を比べる検査の筋書きに含める要求を決めている。外す要求がその要求に当たるときは、Claude は段を外さずに止まり、所有者に報告する。段を外すと、要件5の受入基準1が満たせなくなるためである。
  - 完了の確かめ方: `go test -tags compat -count=1 -run 'TestCompare_Scenarios/(<4つの筋書きの名前を | でつないだもの>)' ./compat/` が通る。`make compat` が、出力の操作のすべての筋書きで通る。`progress.md` の出力の行が、spec の列に `.kiro/specs/backend-go-resume-export`、状態の列に「作り終えた」を持ち、`go test -tags compat -run TestCoverage_Operations ./compat/` が通る
  - 受入基準とテストの対応: 要件3の受入基準2(出力の前提を満たさない経歴書に、Java 版と同じ文言で答える)と、要件5の受入基準1のうち出力の前提を満たさない経歴書の要求は、`prerequisite.yaml` で確かめる。要件3の受入基準3(無い経歴書に 404 と Java 版の文言で答える)と、要件5の受入基準1のうち無い経歴書の要求は、`not-found.yaml` で確かめる。要件4の受入基準1(ほかの利用者の経歴書に、無い経歴書と同じ答えを返す)と、要件5の受入基準1のうちほかの利用者の経歴書の要求は、`other-user.yaml` で確かめる。要件4の受入基準2(退会してすでに居ない利用者の要求に、Java 版と同じ答えを返す)と、要件5の受入基準1のうち退会してすでに居ない利用者の要求は、`deleted-user.yaml` で確かめる。要件1の受入基準2の3つ目の箇条と要件5の受入基準3のうち、答えを変えた要求を変えた動きの一覧に載せることは、`changed-behaviors.yaml` に足した違いの文で確かめる。この要求への Go 版の答えは、この小タスクで `export_integration_test.go` に足すテストで確かめる。500 で答える要求が見つからなかったときは、Claude は、そのことを小タスク7.2 で PR の本文に書く。要件7の受入基準3のうち「作り終えた」を書くことは、`progress.md` の文と `TestCoverage_Operations` で確かめる
  - _要件: 1.2, 3.2, 3.3, 4.1, 4.2, 5.1, 5.3, 7.3_
  - _依存: 6.1_

- [ ] 6.4 版をまたいで確かめる筋書きを書いて通す

  Claude は、まず、版をまたいで確かめる筋書きの送り先を確かめるテスト `TestCrossRoute_ExportSteps` を `backend/compat/harness/cross_test.go` に作る。手本は `TestCrossRoute_ResumeSteps` である。このテストは、`cross-export.yaml` が無ければ失敗する。Claude は、次に、出力の操作の筋書きの節のとおりに、`cross-export.yaml` を書く。
  - 完了の確かめ方: `go test -tags compat -run TestCrossRoute_ExportSteps ./compat/harness/` が通る。`make compat-cross` が、Java 版から Go 版の向きと Go 版から Java 版の向きで通る
  - 受入基準とテストの対応: 要件6の受入基準1(一方の版で保存した経歴書を、もう一方の版で PDF と Markdown で出力できる)は、`cross-export.yaml` の期待の `content_type` と `body_contains` と、最後の読み取りの段の期待で確かめる。要件6の受入基準2(版をまたいで確かめる検査に出力の筋書きを足し、2つの向きで動かす)は、`make compat-cross` の `TestCross_Scenarios` と、`TestCrossRoute_ExportSteps` で確かめる。`TestCrossRoute_ExportSteps` は、2つの向きのそれぞれで、出力の2つの段の送り先が、その前の、経歴書か項目を変える段の送り先と違うことを確かめる
  - _要件: 6.1, 6.2_
  - _依存: 2.1, 6.1_

- [ ] 6.5 出力の応答の時間とメモリの最大を測る

  Claude は、まず、時間を測る筋書きを読むテスト `TestLoadScenarios_ExportPerf` を `backend/compat/harness/perfmeasure_test.go` に作る。このテストは、2つの筋書きが無ければ失敗する。Claude は、次に、出力の操作の筋書きの節のとおりに、`perf-export-pdf.yaml` と `perf-export-markdown.yaml` を書く。Claude は、`make compat-perf` で2つの操作を測り、進み具合の表の節のとおりに、結果を `progress.md` の応答の時間を比べた結果の表に足し、PDF の出力のメモリの最大を表の下の箇条に書く。
  - 完了の確かめ方: `go test -tags compat -run TestLoadScenarios_ExportPerf ./compat/harness/` が通る。`make compat-perf` が2つの操作を測り、`progress.md` に結果が書かれる。6つ目の大きなまとまりの最後のタスクなので、大きなまとまりの最後のタスクで verify のスキルを流すと決めた完了条件の2つ目のとおり、`/verify-backend` も通る
  - 受入基準とテストの対応: 要件5の受入基準4(PDF と Markdown の出力の応答の時間と、PDF の出力のメモリの最大を測る)は、`make compat-perf` の `TestPerf_Scenarios` の結果と、`TestLoadScenarios_ExportPerf` で確かめる。`TestLoadScenarios_ExportPerf` は、2つの筋書きが group 4 で、段の数と最後の段の操作が筋書きの節の表のとおりで、PDF の筋書きだけが `measure_memory` を持つことを確かめる
  - _要件: 5.4_

- [ ] 7. API の説明画面で確かめて、記録を書く
- [ ] 7.1 API の説明画面で出力の2つの操作を確かめる

  Claude は、この作業フォルダの最上位から compose の `backend-go` を作り直して起動し、この作業フォルダのコードを動かす。Claude は、API の説明画面での確認の節のとおりに、開発環境の compose の `api-docs`(ポート 8082)を Playwright で開き、出力の2つの操作の答えを確かめる。Claude は、確かめた結果を、`/ship` で作るこの spec の PR の本文に書く。
  - 完了の確かめ方: 設定を付けた出力の inline と attachment の PDF の「Try it out」が、200 と `application/pdf` で答える。設定を付けない出力の Markdown の「Try it out」が、200 と `text/markdown;charset=utf-8` で答える
  - 受入基準とテストの対応: 要件1の受入基準3のうち、Go 版を相手に PDF のプレビューと PDF の保存と Markdown の保存の要求に答えられることは、3つの「Try it out」の答えで確かめる
  - _要件: 1.3_

- [ ] 7.2 試作の記録を書き足す

  Claude は、実装で確かめた Java 版の動きを、research.md に書き足す。書き足す動きには、数の欄に真偽を入れた本文と、文字列の欄に指数の付いた数を入れた本文への Java 版の答えを含める。Claude は、`/ship` で作るこの spec の PR の本文に、次の3つを書く。

  1. 進み具合の表の状態の列を「比べる検査に通った」にする PR を、この PR のマージのあとに出すこと
  2. Go 版が Java 版と違う答えを返す要求と、その違いを載せた変えた動きの一覧の番号
  3. Java 版が 500 で答える出力の要求が見つかったかどうか。見つかったときは、要求ごとの、Go 版の答えと変えた動きの一覧の番号

  Claude は、状態の列を「比べる検査に通った」にすることを、このタスクで扱わず、この spec の PR のマージのあとに進み具合の表を書き換える PR を出す小タスク7.3 で扱う。
  - 完了の確かめ方: research.md に、実装で確かめた Java 版の動きが書き足されている。この spec の PR に入れる最後のタスクなので、`/verify-backend` も通る
  - 受入基準とテストの対応: 要件7の受入基準1と2(設計の前に試しに作り、同じにできない動きが見つかれば止まる)は、research.md の試作の記録と書き足しで確かめる。これを確かめるテストは無い
  - _要件: 7.1, 7.2_

- [ ] 7.3 この spec の PR のマージのあとに、進み具合の表を「比べる検査に通った」にする PR を出す

  Claude は、`/ship` で、この spec の PR がマージされたことを確かめる。この spec の PR は、Java 版と Go 版を比べる検査を含む必須のチェックがすべて通ったときにだけマージされる。Claude は、マージを確かめたあと、同じ会話で、main から新しい featureブランチを作り、`progress.md` のまとまりの表の出力の行の状態の列を「比べる検査に通った」にして、`/ship` で PR を出す。
  - 完了の確かめ方: 出した PR がマージされ、main の `progress.md` の出力の行の状態の列が「比べる検査に通った」になっている
  - 受入基準とテストの対応: 要件7の受入基準3のうち、Java 版と Go 版を比べる検査に通ったら状態を「比べる検査に通った」にすることは、main の `progress.md` の文で確かめる。これを確かめるテストは無い
  - _要件: 7.3_
  - _依存: 7.2_

## 実装のメモ

- Claude は、途中のタスクのテストを、`bash .claude/scripts/parallel/run-check.sh backend-go <コマンド>` の形で流す。タスクの「完了の確かめ方」の `go test` と `make` のコマンドは、この `<コマンド>` にあたる。Claude は、`go test` を、`backend/` を作業の場所として流す。台本の中や審査役に渡すコマンドでは、Claude は `run-check.sh --wait` を使う。`--wait` を付けないと、ほかの会話が同時に流せる数の枠をすべて使っているときに、`run-check.sh` は順番待ちの文だけを出して何も流さずに終わるためである
- `backend/compat/` の下のファイルは、すべて `//go:build compat` を持つ。Claude は、確認に使う道具を広げる2つ目の大きなまとまりと、出力の操作の筋書きで Java 版と Go 版を比べる6つ目の大きなまとまりで足すテストにも、同じビルドタグを付ける。`internal/resume` の結合テストは、ビルドタグを持たず、`make test` と CI の Go 版の検査で毎回動く
- Java 版と Go 版を比べる検査(`TestCompare_Scenarios`)は、Java 版と Go 版の答えとデータベースを比べるだけで、筋書きの段の `expect` を確かめない。`expect` を確かめるのは、版をまたいで確かめる検査と、応答の時間を測る検査だけである。Claude は、出力の操作の筋書きで Java 版と Go 版を比べる6つ目の大きなまとまりで、段ごとの期待が正しいことを、作業フォルダの外の写しで筋書きの `modes` を `[cross]` に替えて `TestCross_Scenarios/<name>` を流して確かめる。このことは、マスタと経歴書の spec の実装で分かった
- 開発環境のイメージは Java 版の4つのフォントのファイルを置かないので、Claude は、PDF の見た目を、本番のイメージで動かす Java 版と Go 版を比べる検査(`make compat`)で確かめる
- Java 版と Go 版を比べる検査は、小タスク6.1 と6.2 の筋書きで、Java 版の PDF と Go 版の PDF を比べる。2つの PDF の違いが PDF を比べる部品の許す幅を超えたら、Claude は、許す幅を広げずに止まり、所有者に報告する。置き換えの spec の要件8の受入基準2が、同じ動きにできない違いが見つかったら止まると決めたためである
- Claude は、変えた動きの一覧 `changed-behaviors.yaml` の項目を、番号の順に並べる
- 小タスク1.2 で控えた `filenames.json` の項目のうち、空白だけの名前と空の名前は、Java 版がファイル名を作る前に出力の前提の検査で断るので、`status` が 400 で、`fileName` の代わりに `response` を持つ。Claude は、`TestSanitizeFileName_MatchesJava` で、`status` が 200 の項目だけをファイル名で比べ、400 の項目は出力の前提の検査のテストで扱う
- `filenames.json` の、UTF-16 で255を超える名前のファイル名の末尾の `?` は、Java 版が UTF-16 の255で切って半分に割れた絵文字を、ヘッダを作るときに UTF-8 で `?` に替えたものである。`fileName` は、Content-Disposition の `filename*=` を読んだ値で、拡張子を含む

## 完了条件(全タスク共通)

Claude は、どのタスクでも、タスクの箇条書きの欄を書いたうえで、次の4つを満たしたときにタスクを完了とする。

1. Claude は、タスクが満たす requirements.md の受入基準(要件の番号付きの項目)ごとに、それを確かめるテストのファイル名とテスト名を「受入基準とテストの対応」の行に書く。Claude は、確かめるテストの無い受入基準を残さない。
2. タスクで変えたファイルを使うテストが、すべて成功している。`1.` や `2.` の見出しのタスクを大きなまとまりと呼ぶ。大きなまとまりの最後のタスクでは、加えて、そのまとまりのタスクで変えた領域の verify のスキル(`/verify-frontend` `/verify-backend` `/verify-terraform`)が、すべて成功している。
3. Claude は、テストを飛ばす設定、アサーションの削除、カバレッジや lint の対象からの除外を足して、完了条件を満たしたように見せない。CI の escape-hatch の検査が、これらの追加を機械で見つける。
4. Claude は、新しく書いたテストについて、テストの対象のコードを一時的に壊してテストが失敗することを確かめる。Claude は、新しいテスト1件につき1か所だけを、作業フォルダの外の写しで壊し、そのテストだけを流す。壊した写しの作り方と流し方は、`.kiro/steering/tech.md` の「テストの完全性」に従う。
