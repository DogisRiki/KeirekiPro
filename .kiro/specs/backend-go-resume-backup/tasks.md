# タスク

- [ ] 1. バックアップの操作の土台を作る
- [x] 1.1 バックアップの経歴書の初期のデータを書く

  Claude は、初期のデータとバックアップのファイルの節のとおりに、`backend/compat/fixtures/backup/backup.sql` に、user1 の経歴書 801 から 805 を書く。Claude は、経歴書 801 から 804 の各欄の項目を1件以下にし、ポートフォリオと SNS と自己PR の項目の名前を、`fonts.sql` と同じく、名前の頭の英大文字(`A ` と `B `)で順が決まる名前にする。Claude は、経歴書 805 の6つの欄に3件ずつの項目を、経歴書を読み出すときの順と違う順に入れる。

  `backend/compat/harness/fixtures_test.go` の `TestFixtures_AllLoadable` は、`fixtures/` の今あるフォルダのほかにあるファイルを、知らない種類のファイルとして失敗にする。そのため、Claude は、このテストに `backup` のフォルダの場合を足す。足した場合では、このテストは、`backup/*.sql` を `users` と `resumes` の SQL のあとにデータベースに読み込み、`users` と `resumes` の SQL と同じ決まりで確かめる。Claude は、`backend/compat/harness/fixtures.go` の `FixturesDir` のコメントに、`backup/` のフォルダの中身を書き足す。
  - 完了の確かめ方: `backend/compat/fixtures/backup/backup.sql` があり、`users/basic.sql` と `resumes/fonts.sql` のあとに入れると、データベースに誤り無く入る。`go test -tags compat -count=1 -run TestFixtures_AllLoadable ./compat/harness/` が通る
  - 受入基準とテストの対応: Claude は、この小タスクで確認に使う道具を作り、この小タスクでは受入基準を直接は確かめない。初期のデータは、小タスク1.3 の答えの控えと、4つ目の大きなまとまりの結合テストと、6つ目の大きなまとまりの筋書きが使う
  - _要件: 6.1_

- [ ] 1.2 戻しの要求の本文のファイルを置き、ファイルの名前の頭ごとの確かめ方を足す

  Claude は、初期のデータとバックアップのファイルの節の表のとおりに、`reject-` と `lax-` と `malformed-` で始まる22のファイルを `backend/compat/fixtures/backups/` に置く。Claude は、`reject-limit-duplicate.json` の経歴書の名前を `resume-limits.sql` の利用者 500 の経歴書の1つと同じにし、`reject-duplicate-invalid.json` の経歴書の名前を経歴書 401 と同じ「フォントを比べる経歴書」にする。Claude は、今の `fixtures/backups/` の4つのファイルを変えない。

  Claude は、`fixtures_test.go` の `checkBackup` に、ファイルの名前の頭ごとの確かめ方を足す。`checkBackup` は、`java-` で始まるファイルでは、今の `basic.json` と同じく、版が `1.0` で経歴書の中身を持つことを確かめる。`checkBackup` は、`reject-` と `lax-` と `malformed-` で始まるファイルでは、JSON として読めることだけを確かめる。Claude は、`fixtures.go` の `FixturesDir` のコメントの `backups/` の説明に、足すファイルの名前の頭ごとの中身を書く。Claude は、`java-` で始まるファイルを、Java 版の答えを正解のファイルに控える小タスク1.3 で置く。
  - 完了の確かめ方: 表の `reject-` と `lax-` と `malformed-` で始まる22のファイルが `fixtures/backups/` にある。`go test -tags compat -count=1 -run TestFixtures_AllLoadable ./compat/harness/` が通る
  - 受入基準とテストの対応: Claude は、この小タスクで確認に使う道具を作り、この小タスクでは受入基準を直接は確かめない。本文のファイルは、小タスク1.3 の答えの控えと、6つ目の大きなまとまりの筋書きが使う
  - _要件: 6.1_

- [ ] 1.3 Java 版の答えを正解のファイルに控える

  Claude は、Java 版の答えの正解のファイルの節のとおりに、main の Java 版を試作用のコンテナで動かす。Claude は、Java 版のイメージを `docker/backend/Dockerfile.prod` で作り、コンテナを compose のネットワーク `keirekipro_my-network` につなぐ。Claude は、開発環境の localstack が動いていることを確かめ、`postgresql` のコンテナにデータベース `kp_backup_proto` を作ってから、`SPRING_PROFILES_ACTIVE` を `dev` に、`SPRING_DATASOURCE_URL` を `jdbc:postgresql://postgresql:5432/kp_backup_proto` に、`SPRING_DATA_REDIS_DATABASE` を `7` にして Java 版を起動する。Claude は、要求を送る前に、Java 版の `/actuator/env` で、`spring.datasource.url` が `kp_backup_proto` を指し、`spring.data.redis.database` が 7 であることを確かめる。こうして、Claude は、所有者の開発のデータベース `keireki_pro` と Redis の DB 0 に触れない。Claude は、ログインと、偽の送信の検査に使う CSRF の値の付け方を、Java 版と Go 版を比べる検査の `backend/compat/harness/send.go` の `prepareVersionRequest` に合わせる。`prepareVersionRequest` は、要求の Host を `compat.test` にし、ログインで受け取った Cookie を付け、Cookie の `XSRF-TOKEN` の値を `X-XSRF-TOKEN` のヘッダに写す。

  Claude は、`users/basic.sql`、`resumes/fonts.sql`、小タスク1.1 の `backup/backup.sql` の順に `kp_backup_proto` に入れ、正解のファイルの節の「正解のファイルに含めるもの」の箇条のとおりに、次の3種類の正解のファイルを置く。

  1. `backend/compat/fixtures/backups/java-*.json`: 初期のデータとバックアップのファイルの節の表の `java-` で始まる8つのファイル。`java-created.json` と `java-added.json` と `java-edited.json` は、Claude が、経歴書を作る要求と、項目を足す要求と、値を変える要求を Java 版に送ってから書き出す。小タスク6.1 で `export.yaml` と `export-added.yaml` に同じ要求を書けるように、Claude は、送った要求の操作と本文と順を、research.md の試作の記録に書き足す。Claude は、この要求を筋書きのフォルダに置かない。Claude が Go 版に2つの操作を作り終える前にこの要求が筋書きのフォルダにあると、Java 版と Go 版を比べる検査が失敗するためである
  2. `backend/internal/resume/testdata/backup/restore.json`: 試作の記録の、形の誤ったファイルと断る条件に当たるファイルの書き方のすべてと、戻しの本文の読み手の節のすべての読み方の本文を、user2 が戻したときの答え。Claude は、答えが 201 のときは、次の本文を送る前に、作られた経歴書を user2 で消す。Claude は、名前に対になっていないサロゲートを含むファイルの答えを、ほかの本文の答えを控え終えてから、user2 で2回続けて戻した2回目の答えとして控える。サロゲートとは、UTF-16 で絵文字のような字を2つの単位の組で表すときの、それぞれの単位を指す。対になっていないサロゲートとは、組の片方だけが書かれたものを指す
  3. `backend/internal/httpapi/testdata/backup-unsent.json`: 書き出しで Accept に `application/json` の無い要求、戻しで本文が JSON として読めない要求、戻しで Content-Type のヘッダが JSON でない要求への答え。Claude は、書き出しの要求を user1 で経歴書 401 に送り、戻しの要求を user2 で送る

  Claude は、控え終えたら、試作用のコンテナを止め、データベース `kp_backup_proto` を消し、Redis の DB 7 を空にする。控えた Java 版の答えが research.md の試作の記録と違うときは、Claude は、Java 版と同じにできない動きが見つかったときの決まりである要件8の受入基準2のとおりに止まり、所有者に報告する。
  - 完了の確かめ方: 要求を送る前に、Java 版の `/actuator/env` で、データベースの URL が `kp_backup_proto` を指し、Redis の DB の番号が 7 だった。3種類の正解のファイルがあり、「正解のファイルに含めるもの」の箇条の本文と要求がすべて入っている。research.md に、`java-created.json` と `java-added.json` と `java-edited.json` を作るために送った要求の操作と本文と順が書かれている。`go test -tags compat -count=1 -run TestFixtures_AllLoadable ./compat/harness/` が、`java-` で始まる8つのファイルを含めて通る。試作用のコンテナが止まり、データベース `kp_backup_proto` が無い
  - 受入基準とテストの対応: Claude は、この小タスクで確認に使う道具を作り、この小タスクでは受入基準を直接は確かめない。要件8の受入基準2(Java 版と同じにできない動きが見つかったら止まる)は、控えた答えと research.md の試作の記録を突き合わせて確かめる。これを確かめるテストは無い。正解のファイルは、4つ目の大きなまとまりの結合テストと、5つ目の大きなまとまりの受け口のテストと、6つ目の大きなまとまりの筋書きが使う
  - _要件: 6.1, 8.2_

- [ ] 1.4 仕様書の戻しの本文の型を書き換え、生成したコードを作り直す (並行可)

  Claude は、仕様書の変更の節のとおりに、`backend/api/openapi.yaml` の components に `RestoreResumeRequest`(`x-go-type: json.RawMessage`)を足し、戻しの操作の要求の本文をこの型に向け直す。Claude は、`x-go-type-import` を足さず、書き出しの 200 の答えの `ResumeBackup` を変えない。Claude は、`make generate` で生成したコードを作り直す。Go 版は、このタスクのあとも、2つの操作の要求に未実装の答えを返す。
  - 完了の確かめ方: `make generate-check` が通る。`go test ./internal/httpapi/` が通る。生成したコードの戻しの要求の型が、本文を `json.RawMessage` で持つ
  - 受入基準とテストの対応: Claude は、この小タスクで土台を作り、この小タスクでは受入基準を直接は確かめない。要件1の受入基準1のうち、戻しの本文を Java 版と同じに読むことは、小タスク3.4 の `restoreread_test.go` と、小タスク4.5 の `restore_integration_test.go` で確かめる
  - _要件: 1.1_
  - _対象の部品: 仕様書の変更_

- [ ] 1.5 利用者が居るかを調べる問い合わせを足す (並行可)

  Claude は、利用者が居るかの問い合わせの節のとおりに、`backend/db/queries/resumes.sql` に問い合わせ `ExistsUser` を足し、`make generate` で sqlc の生成したコードを作り直す。Claude は、`backend/internal/resume/store.go` に `userExists` を足す。
  - 完了の確かめ方: `make generate-check` が通る。`go test ./internal/resume/ -run TestStoreIntegration_UserExists` が通る
  - 受入基準とテストの対応: 要件5の受入基準3のうち、退会してすでに居ない利用者かどうかを調べることは、`store_integration_test.go` に足す `TestStoreIntegration_UserExists` で確かめる。このテストは、居る利用者に真を、退会した利用者と無い ID に偽を返すことを確かめる。退会してすでに居ない利用者の戻しに 404 で答えることは、戻しの答えを Java 版の正解と比べる結合テストを書く小タスク4.5 で確かめる
  - _要件: 5.3_
  - _対象の部品: 利用者が居るかの問い合わせ_

- [ ] 1.6 変えた動きの一覧に、設計で決まったバックアップの違いを足す

  Claude は、変えた動きの一覧に載せる違いの節のとおりに、CB-062 から CB-066 の5つの違いを、`backend/compat/changed-behaviors.yaml` の末尾に `group: 5` で足す。Claude は、CB-062 の「画面に影響が無い理由」に、バックアップのファイルの中の6つの欄の項目の並びが変わることと、「所有者が 2026-11-24 に受け入れた(requirements の承認)」と書き、match を `backupResume` の `$.resume.careers[*]` と `$.resume.projects[*]` と `$.resume.certifications[*]` の `order_only` にする。Claude は、CB-063 から CB-066 に match を書かず、「画面に影響が無い理由」に、退会してすでに居ない利用者はどちらの答えでも戻しを終えられないことを書き、コメントに、Java 版と Go 版を比べる検査はこの要求を送らないことと、Go 版の答えは `restore_integration_test.go` が確かめることを書く。Claude は、`backend/compat/harness/match_test.go` の `TestLoadChangedBehaviors_CB005HasNoMatch` の期待する数を、5つ増やす。画面が送らない要求の違い(CB-067 から)は、Go 版の受け口の答えが決まる小タスク5.2 で足す。
  - 完了の確かめ方: `go test -tags compat ./compat/harness/ -run 'TestLoadChangedBehaviors|TestChangedBehaviors|TestMatch'` が通る。1つ目の大きなまとまりの最後のタスクなので、大きなまとまりの最後のタスクで verify のスキルを流すと決めた完了条件の2つ目のとおり、`/verify-backend` も通る
  - 受入基準とテストの対応: 要件3の受入基準2のうち、項目の並びの違いを変えた動きの一覧に載せることと、要件5の受入基準3のうち、答えを変えた要求を変えた動きの一覧に1つずつ載せることは、`changed-behaviors.yaml` の CB-062 から CB-066 の文と、`match_test.go` に足す `TestChangedBehaviors_BackupItems` で確かめる。このテストの手本は、`TestChangedBehaviors_UserItems` と `TestChangedBehaviors_OwnerDecidedItems` である。このテストは、`changed-behaviors.yaml` を読み、CB-062 の match が `backupResume` の `$.resume.careers[*]` と `$.resume.projects[*]` と `$.resume.certifications[*]` の `order_only` であることと、CB-062 の「画面に影響が無い理由」が所有者の受け入れを書いていることと、CB-063 から CB-066 が `group: 5` で match を持たないことを確かめる。変えた動きの一覧の項目の数は、`TestLoadChangedBehaviors_CB005HasNoMatch` で確かめる。Go 版の答えが一覧のとおりであることは、CB-062 は小タスク4.2 の `backup_integration_test.go`、CB-063 から CB-066 は小タスク4.5 の `restore_integration_test.go` で確かめる
  - _要件: 3.2, 5.3, 6.3_

- [ ] 2. 確認に使う道具を広げる
- [ ] 2.1 筋書きの要求に json_capture の欄を足す

  Claude は、Java 版と Go 版を比べる検査の広げ方の節のとおりに、`backend/compat/harness/scenario.go` の `Request` に `JSONCapture` の欄(`yaml:"json_capture"`)を足し、`validateKind` の `hasRequest` と `validateVersionBody` にこの欄を足す。Claude は、`validateJSONFile` を手本に `validateJSONCapture` を足し、`json` と `json_file` と `multipart` と `body_file` と同時に書かれていないことと、絶対の URL の段に書かれていないことを確かめる。Claude は、`capture.go` の `requestBody` に、取り出した値の字をそのまま本文にし、Content-Type を `application/json` にして送る場合を足す。送る時点で値の名前が取り出されていなければ、harness は、段の名前と値の名前を誤りに書いて、その段を失敗にする。
  - 完了の確かめ方: `go test -tags compat ./compat/harness/ -run 'TestLoadScenarios|TestCapture|TestScenarioValidate'` が通る。2つ目の大きなまとまりの最後のタスクなので、大きなまとまりの最後のタスクで verify のスキルを流すと決めた完了条件の2つ目のとおり、`/verify-backend` も通る
  - 受入基準とテストの対応: 要件7の受入基準2のうち、版をまたいで確かめる検査が、一方の版で書き出したファイルをもう一方の版に戻せることは、次のテストで確かめる。
    - `scenario_test.go` に足す `TestLoadScenarios_JSONCaptureExclusive` は、`json_capture` を同時に書けない欄と書いた筋書きと、絶対の URL の段の `json_capture` を、筋書きを読む時点で断ることを確かめる
    - `capture_test.go` に足す `TestCapture_JSONCaptureSentAsIs` は、取り出した値の字をそのまま本文にし、Content-Type を `application/json` にして送ることを確かめる
    - `capture_test.go` に足す `TestCapture_JSONCaptureMissing` は、値の名前が取り出されていない段を失敗にし、誤りに段の名前と値の名前を書くことを確かめる
  - _要件: 7.2_

- [ ] 3. JSON の読み書きと字の数え方の部品を作る
- [ ] 3.1 Java 版と同じ字の並びで JSON を書く書き手を作る (並行可)

  Claude は、JSON の書き手の節のとおりに、`backend/internal/resume/javajson.go` に `JavaJSON` を作る。`JavaJSON` は、構造体の欄を宣言の順に、`json` のタグの名前と `omitempty` に従って書き、`json.Marshaler` を持つ値はその書き方に従う。`JavaJSON` は、空白と改行を入れない。
  - 完了の確かめ方: `go test ./internal/resume/ -run TestJavaJSON` が通る
  - 受入基準とテストの対応: 要件3の受入基準3(Java 版がそのまま書く字をそのまま書き、番号で書く字を番号で書く)は、`javajson_test.go` の `TestJavaJSON_Escapes` で確かめる。このテストは、`"` `\`、0x20 より小さい字、BMP の外の字、対になっていないサロゲート、`<` `>` `&` `'` `/`、U+007F、U+2028、U+2029 の書き方を確かめる。BMP は、Unicode の U+0000 から U+FFFF までの字の範囲を指し、絵文字の多くはこの範囲の外にある。要件3の受入基準1のうち、Java 版が書かない欄を書かないことは、`TestJavaJSON_OmitEmptyAndMarshaler` で確かめる。このテストは、`omitempty` の欄と `json.Marshaler` を持つ値の書き方を確かめる
  - _要件: 3.1, 3.3_
  - _対象の部品: JSON の書き手_

- [ ] 3.2 対になっていないサロゲートを保って JSON を読む読み手を作る (並行可)

  Claude は、JSON の読み手の節のとおりに、`backend/internal/resume/jtree.go` に `parseJTree` を作る。`parseJTree` は、本文の最初の JSON の値を、オブジェクト、並び、文字列、数、真偽、`null` の6つの種類の値の木にし、数を JSON に書かれた字のまま持つ。
  - 完了の確かめ方: `go test ./internal/resume/ -run TestParseJTree` が通る
  - 受入基準とテストの対応: 要件2の受入基準1のうち、Java 版が戻す字を Go 版も同じに読むことは、`jtree_test.go` の `TestParseJTree_LoneSurrogate` で確かめる。このテストは、`\uD800` から `\uDFFF` の番号の対になっていないサロゲートが WTF-8 のバイトで残ることを確かめる。WTF-8 は、対になっていないサロゲートを UTF-8 と同じ規則でバイトにした書き方である。要件4の受入基準6のうち、Java 版と同じ本文を読めない本文とすることは、`TestParseJTree_Malformed` で確かめる。最初の値のあとの字を読まないことは `TestParseJTree_TrailingIgnored` で、同じ名前の欄があとの値になることは `TestParseJTree_DuplicateKey` で確かめる
  - _要件: 2.1, 4.6_
  - _対象の部品: JSON の読み手_

- [ ] 3.3 UTF-16 の単位で字を数え、データベースに入れる字に直す部品を作る (並行可)

  Claude は、WTF-8 の扱いの節のとおりに、`backend/internal/resume/wtf8.go` に、`wtf8Units` と `javaLen` と `toDBText` と `dbResume` を作る。`dbResume` は、経歴書と6つの欄の項目のすべての字の欄に `toDBText` を当てる。
  - 完了の確かめ方: `go test ./internal/resume/ -run TestWTF8` が通る
  - 受入基準とテストの対応: 要件4の受入基準5のうち、長さの上限を Java 版と同じ数え方で確かめることは、`wtf8_test.go` の `TestWTF8_JavaLen` で確かめる。このテストは、BMP の外の字を2、対になっていないサロゲートを1と数えることを確かめる。要件2の受入基準1のうち、対になっていないサロゲートを含む値を Java 版と同じ字でデータベースに入れることは、`TestWTF8_ToDBText` と `TestWTF8_DBResumeAllFields` で確かめる。`TestWTF8_DBResumeAllFields` は、経歴書と6つの欄の項目のすべての字の欄が直ることを確かめる
  - _要件: 2.1, 4.5_
  - _対象の部品: WTF-8 の扱い_

- [ ] 3.4 戻しの本文の読み手を作る

  Claude は、戻しの本文の読み手の節のとおりに、`backend/internal/resume/restoreread.go` に、`readRestoreFile` と、戻しの本文の型 `rsFile` と `rsResume` と6つの欄の項目の型を作る。`readRestoreFile` は、小タスク3.2 の `parseJTree` で本文を値の木にし、出力の spec の `numbersWithinLimit` で数の長さを確かめ、欄の種類ごとの読み方で戻しの本文の型にする。写す元は、Java 版の `RestoreResumeRequest` である。
  - 完了の確かめ方: `go test ./internal/resume/ -run TestReadRestoreFile` が通る。3つ目の大きなまとまりの最後のタスクなので、大きなまとまりの最後のタスクで verify のスキルを流すと決めた完了条件の2つ目のとおり、`/verify-backend` も通る
  - 受入基準とテストの対応: 要件4の受入基準6(Java 版が値を読めないとして断る本文を、Go 版も断る)と、要件1の受入基準1のうち、形の誤ったファイルを Java 版と同じに読むことは、`restoreread_test.go` の次のテストで確かめる。
    - `TestReadRestoreFile_FieldKinds` は、戻しの本文の読み手の節の欄の種類ごとに、読める書き方と読めない書き方を確かめる。欄の種類は、文字列、真偽、年月、日付、`exportedAt`、文字列の並び、オブジェクトの欄の7つである
    - `TestReadRestoreFile_Sections` は、無い欄と `null` の欄を値が無いとし、並びの中の `null` の要素で `nullElement` を真にし、オブジェクトでない要素を読めない値とすることを確かめる
    - `TestReadRestoreFile_Root` は、オブジェクトでない根と、数の長さが上限を超える本文を読めないことと、知らない名前の欄を読み飛ばすことを確かめる
    - 要件2の受入基準2のうち、ファイルの中に無い欄を値が無いとして読むことも、`TestReadRestoreFile_Sections` で確かめる
  - _要件: 1.1, 2.2, 4.6_
  - _依存: 3.2_

- [ ] 4. Service の書き出しと戻しを作る
- [ ] 4.1 Service の書き出しのメソッドを作る

  Claude は、Service の書き出しの節のとおりに、`backend/internal/resume/backup.go` に、`BackupResume` と、バックアップのファイルの型 `bkFile` と `bkResume` と6つの欄の項目の型と、日時と日付の書き方を作る。写す元は、Java 版の `BackupResumeUseCase` と `BackupResumeResponse` である。`BackupResume` は、経歴書を `GetResume` で読み、小タスク3.1 の `JavaJSON` で書き、出力の spec の `Export` と `sanitizeFileName` で結果を返す。Claude は、`service.go` の28の操作と書いたコメントを30にする。
  - 完了の確かめ方: `go test ./internal/resume/ -run TestBackup` が通る
  - 受入基準とテストの対応: 要件3の受入基準1のうち、書かない欄の決まりと、版を `1.0` と書くことと、書き出した日時を世界標準時で書くことは、`backup_test.go` の `TestBackup_OmittedFields` と `TestBackup_ExportedAtFraction` で確かめる。`TestBackup_ExportedAtFraction` は、秒の小数を 0、3、6、9 桁で書き分けることを確かめる。年が 1 から 9999 の外の日付が `errBackupDate` になることは、`TestBackup_DateOutOfRange` で確かめる。要件3の受入基準4のうち、ファイル名を経歴書の名前から作ることは、`TestBackup_FileName` で確かめる
  - _要件: 3.1, 3.4_
  - _依存: 3.1_

- [ ] 4.2 書き出しのメソッドの結合テストを書く

  Claude は、テストの方針の節の結合テストのとおりに、`backend/internal/resume/backup_integration_test.go` を書く。`internal/resume` の結合テストは、パッケージで1つの Postgres を使い、出力の結合テストの `loadExportFixtures` が、`users/basic.sql` と `resumes/fonts.sql` を含む初期のデータを1度だけ入れる。初期のデータの ID は決まった値なので、同じファイルを2度入れると重なって失敗する。そのため、Claude は、`backup_integration_test.go` に、先に `loadExportFixtures` を呼んでから、`backend/compat/fixtures` の `backup/backup.sql` と `resumes/resume-limits.sql` を `sync.Once` で1度だけ入れる関数 `loadBackupFixtures` を作る。書き出しと戻しの結合テストは、どれも `loadBackupFixtures` を呼んでから動く。
  - 完了の確かめ方: `go test ./internal/resume/ -run TestBackupIntegration` が通る
  - 受入基準とテストの対応: 次の受入基準を、`backup_integration_test.go` の次のテストで確かめる。
    - 要件3の受入基準1と3と4(欄と値と字の並びとファイル名を Java 版と同じにする)と、要件6の受入基準2のうち、文字の並びを機械で確かめることは、`TestBackupIntegration_MatchesJavaBytes` で確かめる。このテストは、経歴書 801 から 804 の書き出しの本文が、`exportedAt` の値を除いて、小タスク1.3 で控えた `java-801.json` から `java-804.json` と1バイトも違わないことと、結果の Content-Type が `application/json` で、ファイル名が `sanitizeFileName` で直した経歴書の名前に `_backup.json` を付けた名前であることを確かめる。答えのヘッダの Content-Type と Content-Disposition が Java 版と同じことは、小タスク6.1 の `export.yaml` の Java 版と Go 版を比べる検査が確かめる
    - 要件3の受入基準2(ファイルの中の項目を、経歴書を読み出すときと同じ順に並べる)と、要件6の受入基準2のうち、項目の順を Go 版のテストで確かめることは、`TestBackupIntegration_EntryOrder` で確かめる。このテストは、経歴書 805 の書き出しの項目が、6つの欄のそれぞれで `GetResume` が返す順に並ぶことを確かめる
    - 要件5の受入基準1と2(無い経歴書とほかの利用者の経歴書に、同じ 404 で答える)は、`TestBackupIntegration_OtherUserIsNotFound` で確かめる。このテストは、無い経歴書と、ID の形でない値と、ほかの利用者の経歴書の書き出しが、どれも `errResumeNotFound` になることを確かめる
  - _要件: 3.1, 3.2, 3.3, 3.4, 5.1, 5.2, 6.2_
  - _依存: 1.1, 1.3_

- [ ] 4.3 戻しの値の決まりで経歴書を作る部品と、2つの文言を作る

  Claude は、Service の戻しの節のとおりに、`backend/internal/resume/restore.go` に `buildRestored` を作る。写す元は、Java 版の `RestoreResumeUseCase` の 97-138行と、`ResumeName` `FullName` `Period` `Link` などの経歴書と項目のクラスである。`buildRestored` は、長さを小タスク3.3 の `javaLen` で数え、最後に `sortEntries` で項目を並べる。Claude は、文言の定数の節のとおりに、`errors.go` に `MessageUnsupportedBackupVersion` と `MessageInvalidBackupFile` を足す。
  - 完了の確かめ方: `go test ./internal/resume/ -run 'TestBuildRestored|TestErrors'` が通る
  - 受入基準とテストの対応: 次の受入基準を、`restore_test.go` と `errors_test.go` の次のテストで確かめる。
    - 要件4の受入基準5(Java 版が戻しで確かめる値の決まりを満たさない中身を断る)は、`TestBuildRestored_Rules` で確かめる。このテストは、Service の戻しの節の値の決まりごとに、満たす値と満たさない値を分けることを確かめる。Claude は、このテストの満たさない値に、名前の無い経歴書、50文字を超える名前、姓だけの経歴書、始まりの年月より前の終わりの年月、https でないリンクを含める
    - 要件4の受入基準5のうち、Java 版の戻しが確かめない6つの決まりに当たる値を断らないことは、`TestBuildRestored_LaxRules` で確かめる
    - 要件2の受入基準2(ファイルの中に無い欄と値を Java 版と同じに補う)は、`TestBuildRestored_Defaults` で確かめる。このテストは、無い欄を項目の無い欄にし、工程が無ければすべての工程を選んでいないものにし、技術が無ければ選んでいないものにし、姓と名の両方が無いか空白だけなら氏名の無い経歴書にすることを確かめる
    - 要件2の受入基準1のうち、Java 版と同じ順で項目を入れることは、`TestBuildRestored_SortsEntries` で確かめる
    - 要件4の受入基準2と5の文言は、`errors_test.go` に足す `TestErrors_BackupMessages` で確かめる。このテストは、2つの定数の字が Java 版の `RestoreResumeUseCase.java` の文字列と同じことを確かめる
  - _要件: 2.1, 2.2, 4.2, 4.5_
  - _依存: 3.3_

- [ ] 4.4 Service の戻しのメソッドを作る

  Claude は、Service の戻しの節と処理の流れの節の戻しの図のとおりに、`restore.go` に `RestoreResume` を作る。`RestoreResume` は、小タスク3.4 の `readRestoreFile` で本文を読み、`CreateResume` と同じく1つのトランザクションで、値の無い要素を持つ欄、ファイルの版、経歴書の数、経歴書の中身、名前の重なり、値の決まりの順に確かめてから、`insertResume(dbResume(r))` で経歴書と項目を入れる。トランザクションのあとに誤りが `*auth.Error` でなければ、`RestoreResume` は、小タスク1.5 の `userExists` で利用者が居るかを調べ、居なければ `errResumeNotFound` を返す。写す元は、Java 版の `RestoreResumeUseCase` である。
  - 完了の確かめ方: `go test ./internal/resume/ -run 'TestRestoreIntegration_(Order|Owner|NoLeftover)'` が通る
  - 受入基準とテストの対応: 次の受入基準を、`restore_integration_test.go` の次のテストで確かめる。このテストは、小タスク4.2 の `loadBackupFixtures` を呼んでから動く。
    - 要件4の受入基準1と3と4(確かめる順と、経歴書の数の上限と、名前の重なり)は、`TestRestoreIntegration_Order` で確かめる。このテストは、2つ以上の条件に当たる要求が、順の早い条件の誤りになることを確かめる
    - 要件2の受入基準3(作った経歴書は、要求を送った利用者の経歴書になる)は、`TestRestoreIntegration_Owner` で確かめる
    - 要件4の受入基準1のうち、断った要求のあとに経歴書が残らないことは、`TestRestoreIntegration_NoLeftover` で確かめる。このテストは、値の決まりを満たさない要求と、データベースの列の長さを超える値の要求のあとに、経歴書と項目の数が変わらないことを確かめる
  - _要件: 1.1, 2.3, 4.1, 4.3, 4.4_
  - _依存: 1.5, 3.4, 4.3_

- [ ] 4.5 戻しの答えを Java 版の正解と比べる結合テストを書く

  Claude は、テストの方針の節の結合テストのとおりに、`restore_integration_test.go` に、小タスク1.3 で控えた `restore.json` と Go 版の答えを比べるテストと、退会してすでに居ない利用者のテストを足す。
  - 完了の確かめ方: `go test ./internal/resume/ -run TestRestoreIntegration` が通る。4つ目の大きなまとまりの最後のタスクなので、大きなまとまりの最後のタスクで verify のスキルを流すと決めた完了条件の2つ目のとおり、`/verify-backend` も通る
  - 受入基準とテストの対応: 次の受入基準を、`restore_integration_test.go` の次のテストで確かめる。
    - 要件2の受入基準1と2と、要件4の受入基準2と5と6と、要件1の受入基準1のうち形の誤ったファイルへの答えは、`TestRestoreIntegration_MatchesJava` で確かめる。このテストは、`restore.json` の本文ごとに、Go 版の答えの状態の番号と文言が Java 版と同じことを確かめる。201 の答えは、経歴書と項目の ID と作った日時と直した日時を除いて、JSON として読んだ値で比べる。このテストは、小タスク1.3 の控え方と同じく、本文を user2 で順に戻し、答えが 201 のときは、次の本文を戻す前に、作られた経歴書を消す。消さないと、同じ名前の本文が名前の重なりの誤りになり、Java 版の答えと食い違うためである
    - 要件1の受入基準1と要件4の受入基準4のうち、名前に対になっていないサロゲートを含むファイルの答えは、`TestRestoreIntegration_SurrogateName` で確かめる。このテストは、そのサロゲートを `?` にした名前の経歴書を持つ利用者が戻すと、名前の重なりの誤りでなく、`restore.json` に控えた Java 版の答えと同じ答えになることを確かめる。このテストは、小タスク1.3 の控え方と同じく、このファイルを user2 で2回続けて戻し、2回目の答えを比べる
    - 要件5の受入基準3(退会してすでに居ない利用者の要求への答え)は、`TestRestoreIntegration_DeletedUser` で確かめる。このテストは、CB-063 から CB-066 の4つの戻しが 404 と「対象の職務経歴書データが存在しません。」になり、版の誤りと読めない本文と値の決まりを満たさない本文が 400 になることを確かめる
  - _要件: 1.1, 2.1, 2.2, 4.2, 4.4, 4.5, 4.6, 5.3_
  - _依存: 1.3, 1.6_

- [ ] 5. 書き出しと戻しの受け口をつなぐ
- [ ] 5.1 2つの受け口を作り、経路につなぐ

  Claude は、戻しと書き出しの受け口の節のとおりに、`backend/internal/httpapi/resumes.go` の `ResumeService` に2つのメソッドを足し、`BackupResume` と `RestoreResume` の受け口を作る。Claude は、`resumeresponses.go` に `_ gen.BackupResumeResponseObject = authResponse{}` と `_ gen.RestoreResumeResponseObject = authResponse{}` と2つの `Visit` の関数を足す。Claude は、`server.go` の `Options` の `ResumeHandlers` のコメントと `resumeOperations` と、`resumes.go` と `resumeresponses.go` の28の操作と書いたコメントを、30の操作にする。Claude は、`resumes_test.go` の、28の操作を期待するテストの期待とコメントを30にする。

  Claude が Go 版の戻しの操作を作ると、Go 版は、空のオブジェクト `{}` の本文の戻しに、501 でなく 400 と「サポートされていないバックアップバージョンです。」で答えるようになる。そのため、Claude は、Java 版と Go 版を比べる検査そのもののテストの節のとおりに、`backend/compat/compat_test.go` と `cross_test.go` と `perf_test.go` の段 `restore-with-token` の期待を 400 にし、501 と書いたコメントを、ファイルの版の無い本文に 400 で答えることで確かめると書き直す。Claude は、`compat_test.go` の `TestSelf_OneCharFakeFails` が期待する字を「サポートされていないバックアップバージョンです。」と「サポートされていないバックアップバージョンです！」にし、`TestSelf_MatchedDiffPasses` の違いを許す設定の状態の番号を `http.StatusBadRequest` にする。Claude は、どのテストのアサーションも消さず、期待だけを替える。
  - 完了の確かめ方: `go test ./internal/httpapi/ -run 'TestResumeHandlers|TestResumeResponses|TestResumeRoutes|TestBackupHandlers'` が通る。`go test -tags compat -count=1 -run 'TestSelf_|TestCross_SelfPairPasses|TestCross_ThreeDirectionsRun|TestPerf_SelfPairRuns' ./compat/` が通る
  - 受入基準とテストの対応: 次の受入基準を、`resumes_test.go` の次のテストで確かめる。
    - 要件1の受入基準1のうち、書き出しが 200 と `application/json` と attachment の Content-Disposition と本文を書くことと、要件3の受入基準4のうち Content-Disposition のファイル名は、`TestBackupHandlers_BackupResponse` で確かめる
    - 要件1の受入基準1のうち、戻しが 201 と `application/json` と `JavaJSON` で書いた本文を書くことは、`TestBackupHandlers_RestoreResponse` で確かめる。このテストは、対になっていないサロゲートを含む経歴書の本文が番号で書かれることも確かめる
    - `ResumeHandlers` が無いときに2つの操作の要求に今と同じ未実装の答えを返すことは、`TestResumeRoutes_Unimplemented` で確かめる。`httpapi.New` に `ResumeHandlers` を渡すと30の操作の要求が受け口に届くことは、`TestResumeRoutes_Wired` で確かめ、答えの型の数は `TestResumeResponses_AllOperationsWrite` の期待を30にして確かめる
  - _要件: 1.1, 3.4_
  - _依存: 1.4, 4.1, 4.4_

- [ ] 5.2 画面が送らない要求への答えを Java 版の正解と照らし、違いを一覧に足す

  Claude は、`resumes_test.go` に、小タスク1.3 で控えた `backup-unsent.json` の要求ごとに Go 版の受け口の答えを Java 版の答えと比べるテストを足す。Claude は、Java 版と答えが違う要求ごとに、変えた動きの一覧に載せる違いの節のとおりに、CB-067 から番号を振った違いを `changed-behaviors.yaml` に `group: 5` で足し、テストの中の表に、その要求と番号を書く。Claude は、足した違いに match を書かず、コメントに、Java 版と Go 版を比べる検査はこの要求を送らないことと、Go 版の答えは `resumes_test.go` が確かめることを書く。Claude は、`match_test.go` の `TestLoadChangedBehaviors_CB005HasNoMatch` の期待する数を、足した違いの数だけ増やす。違う要求が無ければ、Claude は違いを足さず、そのことを小タスク7.2 で PR の本文に書く。
  - 完了の確かめ方: `go test ./internal/httpapi/ -run TestBackupHandlers_UnsentRequests` が通る。`go test -tags compat ./compat/harness/ -run 'TestLoadChangedBehaviors|TestChangedBehaviors'` が通る。5つ目の大きなまとまりの最後のタスクなので、大きなまとまりの最後のタスクで verify のスキルを流すと決めた完了条件の2つ目のとおり、`/verify-backend` も通る
  - 受入基準とテストの対応: 要件1の受入基準2の1つ目の箇条(画面が送らない要求には Java 版と違う答えを返してよく、違う要求を変えた動きの一覧に載せる)は、`TestBackupHandlers_UnsentRequests` で確かめる。このテストは、`resumes_test.go` の `checkWholeBodyDiffTable` と同じ形で `changed-behaviors.yaml` を読み、テストの中の表の番号が変えた動きの一覧にあることを確かめる。`internal/resume` の `checkDiffTableInChangedBehaviors` は、`resume` のパッケージのテストの中でしか呼べない。そのため、このテストは `checkDiffTableInChangedBehaviors` を使わない。Java 版と違うのに表に無い要求と、表にあるのに Java 版と同じ要求があれば、このテストは失敗する
  - _要件: 1.2, 6.3_
  - _依存: 1.3, 5.1_

- [ ] 6. バックアップの操作の筋書きで Java 版と Go 版を比べる
- [ ] 6.1 書き出しと、Java 版が書き出したファイルの戻しの筋書きを書く

  Claude は、バックアップの操作の筋書きの節のとおりに、`backend/compat/scenarios/backup/` に `export.yaml` と `export-added.yaml` と `restore.yaml` を `group: 5` で書く。Claude は、`export.yaml` と `export-added.yaml` の、経歴書を作る段と項目を足す段と値を変える段に、小タスク1.3 で research.md に書き足した要求と同じ操作と本文を同じ順に書く。Claude は、書き出しの段の Accept を `application/json` にし、戻しの段に `csrf: true` を付け、戻しの本文を `json_file` で `fixtures/backups/` のファイルから送る。
  - 完了の確かめ方: `go test -tags compat -count=1 -run 'TestCompare_Scenarios/(<3つの筋書きの名前を | でつないだもの>)' ./compat/` が通る。`export.yaml` と `export-added.yaml` の、経歴書を作る段と項目を足す段と値を変える段の操作と本文と順が、小タスク1.3 で research.md に書き足した要求と同じである
  - 受入基準とテストの対応: 要件1の受入基準1と3のうち、画面が送る書き出しと戻しの要求に Java 版と同じ答えを返し、今の画面と同じ要求で2つの操作を終えられることと、要件3の受入基準1と4(欄と値とファイル名)と、要件6の受入基準1のうち書き出しの7つの経歴書と Java 版が書き出したファイルの戻しは、3つの筋書きの Java 版と Go 版を比べる検査で確かめる。要件2の受入基準1から3(Java 版で戻した経歴書と同じ経歴書を、要求を送った利用者に作る)と、要件6の受入基準2のうち要求のあとのデータベースを比べることは、`restore.yaml` の Java 版と Go 版を比べる検査で確かめる。Java 版と Go 版を比べる検査は、CB-001 と CB-062 の `order_only` に従い、書き出しの本文の6つの欄の項目の順を比べない
  - _要件: 1.1, 1.3, 2.1, 2.2, 2.3, 3.1, 3.4, 6.1, 6.2_
  - _依存: 1.3, 1.6, 5.1_

- [ ] 6.2 断る条件と、確かめない決まりと、形の誤ったファイルの筋書きを書く

  Claude は、バックアップの操作の筋書きの節のとおりに、`rejects.yaml` と `lax.yaml` と `malformed.yaml` を書く。3つの筋書きは、小タスク1.2 で置いた `reject-` と `lax-` と `malformed-` で始まるファイルと、今の `wrong-version.json` と `no-resume.json` と `basic.json` を `json_file` で送る。
  - 完了の確かめ方: `go test -tags compat -count=1 -run 'TestCompare_Scenarios/(<3つの筋書きの名前を | でつないだもの>)' ./compat/` が通る
  - 受入基準とテストの対応: 要件4の受入基準1から6(断る条件と、確かめる順と、文言)と、要件6の受入基準1のうち断る条件ごとの要求と2つ以上の条件に当たる要求は、`rejects.yaml` で確かめる。要件4の受入基準5のうち Java 版の戻しが確かめない決まりに当たるファイルを戻すことと、要件6の受入基準1のうちその要求は、`lax.yaml` で確かめる。要件1の受入基準1のうち形の誤ったファイルから作った要求に、Java 版が 500 で答えるときも同じ 500 で答えることと、要件6の受入基準1のうちその要求は、`malformed.yaml` で確かめる。要件6の受入基準2のうち、断った要求のあとに経歴書が作られていないことは、3つの筋書きのデータベースの比べ方で確かめる
  - _要件: 1.1, 4.1, 4.2, 4.3, 4.4, 4.5, 4.6, 6.1, 6.2_
  - _依存: 1.2_

- [ ] 6.3 無い経歴書とほかの利用者と退会した利用者とログインの筋書きを書き、進み具合の表を「作り終えた」にする

  Claude は、この小タスクで次の2つをする。

  1. Claude は、バックアップの操作の筋書きの節のとおりに、`not-found-other-user.yaml` と `deleted-user.yaml` と `require-login.yaml` を書く。`deleted-user.yaml` の手本は `scenarios/export/deleted-user.yaml`、`require-login.yaml` の手本は `scenarios/users/require-login.yaml` である。`deleted-user.yaml` は、CB-063 から CB-066 の4つの戻しを送らない。
  2. Claude は、進み具合の表の節のとおりに、`.kiro/specs/backend-go-replacement/progress.md` のまとまりの表のバックアップの行の spec の列に `.kiro/specs/backend-go-resume-backup` を書き、状態の列を「作り終えた」にする。状態の列を「作り終えた」にすると、`TestCoverage_Operations` が、2つの操作が `group: 5` の筋書きに1回以上出てくることを求め始める。
  - 完了の確かめ方: `go test -tags compat -count=1 -run 'TestCompare_Scenarios/(<3つの筋書きの名前を | でつないだもの>)' ./compat/` が通る。`make compat` が、バックアップの操作のすべての筋書きで通る。`progress.md` のバックアップの行が、spec の列に `.kiro/specs/backend-go-resume-backup`、状態の列に「作り終えた」を持ち、`go test -tags compat -run TestCoverage_Operations ./compat/` が通る
  - 受入基準とテストの対応: 要件5の受入基準1と2(無い経歴書とほかの利用者の経歴書に同じ 404 で答える)と、要件6の受入基準1のうちその要求は、`not-found-other-user.yaml` で確かめる。要件5の受入基準3のうち Java 版と同じ答えを返す退会してすでに居ない利用者の要求と、要件6の受入基準1のうちその要求は、`deleted-user.yaml` で確かめる。要件6の受入基準1のうち、ログインが切れたあとの要求と偽の送信の検査に通らない要求は、`require-login.yaml` で確かめる。要件6の受入基準3のうち答えを変えた要求を変えた動きの一覧に載せることは、`changed-behaviors.yaml` に足した違いの文で確かめ、その要求への Go 版の答えは、実装のメモの、Java 版が 500 で答える要求の扱いのとおりに結合テストに足すテストで確かめる。Java 版が 500 で答える要求が見つからなかったときは、Claude は、そのことを小タスク7.2 で PR の本文に書く。要件8の受入基準3のうち「作り終えた」を書くことは、`progress.md` の文と `TestCoverage_Operations` で確かめる
  - _要件: 5.1, 5.2, 5.3, 6.1, 6.3, 8.3_
  - _依存: 6.1_

- [ ] 6.4 版をまたいで確かめる筋書きを書いて通す

  Claude は、まず、版をまたいで確かめる筋書きの送り先を確かめるテスト `TestCrossRoute_BackupSteps` を `backend/compat/harness/cross_test.go` に作る。手本は `TestCrossRoute_ExportSteps` である。このテストは、`cross-backup.yaml` が無ければ失敗する。Claude は、次に、バックアップの操作の筋書きの節のとおりに、`cross-backup.yaml` を5つの段で書く。
  - 完了の確かめ方: `go test -tags compat -run TestCrossRoute_BackupSteps ./compat/harness/` が通る。`make compat-cross` が、Java 版から Go 版の向きと Go 版から Java 版の向きで通る
  - 受入基準とテストの対応: 要件7の受入基準1(一方の版で書き出したファイルを、もう一方の版で戻せ、戻した経歴書を最初の版で読める)は、`cross-backup.yaml` の戻しの段の期待の 201 と、最後の読む段の期待の `values` で確かめる。要件7の受入基準2(版をまたいで確かめる検査に筋書きを足し、2つの向きで動かす)は、`make compat-cross` の `TestCross_Scenarios` と、`TestCrossRoute_BackupSteps` で確かめる。`TestCrossRoute_BackupSteps` は、2つの向きのそれぞれで、戻しの段の送り先が書き出しの段の送り先と違い、最後の読む段の送り先が書き出しの段の送り先と同じことを確かめる
  - _要件: 7.1, 7.2_
  - _依存: 2.1, 6.1_

- [ ] 6.5 書き出しと戻しの応答の時間を測る

  Claude は、まず、時間を測る筋書きを読むテスト `TestLoadScenarios_BackupPerf` を `backend/compat/harness/perfmeasure_test.go` に作る。手本は `TestLoadScenarios_ExportPerf` である。このテストは、2つの筋書きが無ければ失敗する。Claude は、次に、バックアップの操作の筋書きの節のとおりに、`perf-backup.yaml` と `perf-restore.yaml` を書く。Claude は、`make compat-perf` で2つの操作を測り、進み具合の表の節のとおりに、結果を `progress.md` の応答の時間を比べた結果の表の、出力の行のあとに足す。
  - 完了の確かめ方: `go test -tags compat -run TestLoadScenarios_BackupPerf ./compat/harness/` が通る。`make compat-perf` が2つの操作を測り、`progress.md` に結果が書かれる。6つ目の大きなまとまりの最後のタスクなので、大きなまとまりの最後のタスクで verify のスキルを流すと決めた完了条件の2つ目のとおり、`/verify-backend` も通る
  - 受入基準とテストの対応: 要件6の受入基準4(6つの欄に項目を入れた経歴書で、書き出しと戻しの時間を測る)は、`make compat-perf` の `TestPerf_Scenarios` の結果と、`TestLoadScenarios_BackupPerf` で確かめる。`TestLoadScenarios_BackupPerf` は、2つの筋書きが group 5 で、段の数と最後の段の操作が筋書きの節のとおりで、戻しの筋書きだけが `prepare_each` を持つことを確かめる
  - _要件: 6.4_
  - _依存: 1.3_

- [ ] 7. API の説明画面で確かめて、記録を書く
- [ ] 7.1 API の説明画面で書き出しと戻しを確かめる

  Claude は、この作業フォルダの最上位から compose の `backend-go` を作り直して起動し、この作業フォルダのコードを動かす。Claude は、API の説明画面での確認の節のとおりに、開発環境の compose の `api-docs`(ポート 8082)を Playwright で開き、2つの操作の答えを確かめる。Claude は、確かめた結果を、`/ship` で作るこの spec の PR の本文に書く。
  - 完了の確かめ方: 書き出しの「Try it out」が、200 と `application/json` と attachment の Content-Disposition で答える。経歴書を消してから、書き出した本文を戻しの本文に入れた戻しの「Try it out」が、201 で答える
  - 受入基準とテストの対応: 要件1の受入基準3のうち、Go 版を相手に書き出しと戻しを終えられることは、2つの「Try it out」の答えで確かめる
  - _要件: 1.3_

- [ ] 7.2 試作の記録を書き足す

  Claude は、実装で確かめた Java 版の動きを、research.md に書き足す。Claude は、`/ship` で作るこの spec の PR の本文に、次の3つを書く。

  1. 進み具合の表の状態の列を「比べる検査に通った」にする PR を、この PR のマージのあとに出すこと
  2. Go 版が Java 版と違う答えを返す要求と、その違いを載せた変えた動きの一覧の番号
  3. 画面が送る要求でないもので Java 版が 500 で答える要求が見つかったかどうか。見つかったときは、要求ごとの、Go 版の答えと変えた動きの一覧の番号

  - 完了の確かめ方: research.md に、実装で確かめた Java 版の動きが書き足されている。この spec の PR に入れる最後のタスクなので、`/verify-backend` も通る
  - 受入基準とテストの対応: 要件8の受入基準1と2(設計の前に試しに作り、同じにできない動きが見つかれば止まる)は、research.md の試作の記録と書き足しで確かめる。これを確かめるテストは無い
  - _要件: 8.1, 8.2_

- [ ] 7.3 この spec の PR のマージのあとに、進み具合の表を「比べる検査に通った」にする PR を出す

  Claude は、`/ship` で、この spec の PR がマージされたことを確かめる。この spec の PR は、Java 版と Go 版を比べる検査を含む必須のチェックがすべて通ったときにだけマージされる。Claude は、マージを確かめたあと、同じ会話で、main から新しい featureブランチを作り、`progress.md` のまとまりの表のバックアップの行の状態の列を「比べる検査に通った」にして、`/ship` で PR を出す。
  - 完了の確かめ方: 出した PR がマージされ、main の `progress.md` のバックアップの行の状態の列が「比べる検査に通った」になっている
  - 受入基準とテストの対応: 要件8の受入基準3のうち、Java 版と Go 版を比べる検査に通ったら状態を「比べる検査に通った」にすることは、main の `progress.md` の文で確かめる。これを確かめるテストは無い
  - _要件: 8.3_
  - _依存: 7.2_

## 実装のメモ

- Claude は、途中のタスクのテストを、`bash .claude/scripts/parallel/run-check.sh backend-go <コマンド>` の形で流す。タスクの「完了の確かめ方」の `go test` と `make` のコマンドは、この `<コマンド>` にあたる。Claude は、`go test` を、`backend/` を作業の場所として流す。台本の中や審査役に渡すコマンドでは、Claude は `run-check.sh --wait` を使う。`--wait` を付けないと、ほかの会話が同時に流せる数の枠をすべて使っているときに、`run-check.sh` は順番待ちの文だけを出して何も流さずに終わるためである
- `backend/compat/` の下のファイルは、すべて `//go:build compat` を持つ。Claude は、確認に使う道具を広げる2つ目の大きなまとまりと、バックアップの操作の筋書きで Java 版と Go 版を比べる6つ目の大きなまとまりで足すテストにも、同じビルドタグを付ける。`internal/resume` の結合テストは、ビルドタグを持たず、`make test` と CI の Go 版の検査で毎回動く
- Java 版と Go 版を比べる検査(`TestCompare_Scenarios`)は、Java 版と Go 版の答えとデータベースを比べるだけで、筋書きの段の `expect` を確かめない。`expect` を確かめるのは、版をまたいで確かめる検査と、応答の時間を測る検査だけである。Claude は、6つ目の大きなまとまりで、段ごとの期待が正しいことを、作業フォルダの外の写しで筋書きの `modes` を `[cross]` に替えて `TestCross_Scenarios/<name>` を流して確かめる
- Java 版が 500 で答える要求の扱い: Claude は、小タスク6.1 から6.3 のどれかで筋書きを書く途中で、Java 版が 500 で答える要求のうち、要件1の受入基準1の画面が送る要求でないものを見つけたら、見つけた小タスクの中で次のことをする。Claude は、要件6の受入基準3のとおり、Go 版が 404 か 400 のどちらで答えるかを決め、要求ごとに1つの違いを `changed-behaviors.yaml` に `group: 5` で足し、`match_test.go` の期待する数を足した数だけ増やす。Claude は、その要求に Go 版が決めた状態の番号で答えることを確かめるテストを、`restore_integration_test.go` か `backup_integration_test.go` に要求ごとに1つ足す。Claude は、その違いに match を書かず、その要求を送る段を、Java 版と Go 版を比べる検査の筋書きから外す。外す要求が要件6の受入基準1の筋書きに含める要求に当たるときは、Claude は段を外さずに止まり、所有者に報告する。段を外すと、Java 版と Go 版を比べる検査が、要件6の受入基準1で筋書きに含めると決めた要求を確かめられなくなるためである
- Claude は、変えた動きの一覧 `changed-behaviors.yaml` の項目を、番号の順に並べる。小タスク5.2 と、6.1 から6.3 で足す違いは、足した時点の最後の番号の次から番号を振る
- 小タスク1.4 と1.5 は、どちらも `make generate` で生成したコードを作り直す。2つの小タスクが作り直す対象は別々で、小タスク1.4 は仕様書から作る `internal/httpapi/gen` を、小タスク1.5 は sqlc の `internal/platform/database/sqlcgen` を対象にする。ただし、`make generate` は両方を作り直す。そのため、2つの小タスクを並行に進めるときは、Claude は、あとに終えた小タスクで `make generate-check` をもう一度流す
- Claude は、`backup/backup.sql` の経歴書 801 から 805 を、Java 版の戻しの値の決まりに通る値で書く。Java 版が書き出したファイルを戻す筋書きは、すべての要求に 201 を期待するためである。経歴書の名前に禁じた9字を入れるときは、名前に改行か U+2028 のような行の区切りの字を混ぜる。Java 版の禁じた字の検査は、行の区切りの字を含む名前を確かめないため、その名前は戻しで断られない。姓と名には、かな、漢字、英字だけを入れ、リンクには `<` `>` `"` を入れない

## 完了条件(全タスク共通)

Claude は、どのタスクでも、タスクの箇条書きの欄を書いたうえで、次の4つを満たしたときにタスクを完了とする。

1. Claude は、タスクが満たす requirements.md の受入基準(要件の番号付きの項目)ごとに、それを確かめるテストのファイル名とテスト名を「受入基準とテストの対応」の行に書く。Claude は、確かめるテストの無い受入基準を残さない。
2. タスクで変えたファイルを使うテストが、すべて成功している。`1.` や `2.` の見出しのタスクを大きなまとまりと呼ぶ。大きなまとまりの最後のタスクでは、加えて、そのまとまりのタスクで変えた領域の verify のスキル(`/verify-frontend` `/verify-backend` `/verify-terraform`)が、すべて成功している。
3. Claude は、テストを飛ばす設定、アサーションの削除、カバレッジや lint の対象からの除外を足して、完了条件を満たしたように見せない。CI の escape-hatch の検査が、これらの追加を機械で見つける。
4. Claude は、新しく書いたテストについて、テストの対象のコードを一時的に壊してテストが失敗することを確かめる。Claude は、新しいテスト1件につき1か所だけを、作業フォルダの外の写しで壊し、そのテストだけを流す。壊した写しの作り方と流し方は、`.kiro/steering/tech.md` の「テストの完全性」に従う。
