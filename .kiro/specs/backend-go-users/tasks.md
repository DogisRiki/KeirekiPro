# タスク

- [x] 1. 利用者の処理の土台を作る
- [x] 1.1 認証の処理を利用者の処理から呼べる形で公開する

  Claude は、`internal/auth` の利用者の行の型 `storedUser` を、外から使える型 `StoredUser` に改め、欄の名前を `Row` `Providers` `Roles` にする。Claude は、`storedUser` と `loadStoredUser` と `loadStoredUserOr` を使う `emailverification.go` と `oidccallback.go` と `passwordreset.go` を、新しい名前に合わせて直す。`internal/auth` の今あるテストのファイルは `storedUser` を使わないので、Claude は今あるテストのファイルを変えない。そのため、名前を改める前に通っていたテストが、名前を改めたあとも同じ中身で通るかを確かめられる。Claude は、`exported.go` に、公開した認証の処理の節の表の関数と型のうち、`SendUserDeletedMail` のほかのすべてを置く。Claude は、`exported.go` の関数を、今ある関数を呼ぶだけの関数にする。`SendUserDeletedMail` は、小タスク1.3 の、退会の完了のメールを足すタスクで足す。
  - 完了の確かめ方: `go test ./internal/auth/` が通り、名前を改める前に通っていたテストがすべて通る。`go test ./internal/auth/ -run TestExported` が、`exported_integration_test.go` の、公開した関数ごとに元の関数と同じ結果を返す場合で通る
  - 受入基準とテストの対応: この小タスクは土台であり、受入基準を直接は確かめない。要件3の受入基準1から3(今のパスワードの照合、ログインの状態を使えなくすること、確認のメールの間隔とリンク)は、小タスク3.5 の確認のメールを送る処理、3.8 の退会の処理、3.9 のパスワードの処理の結合テストと、小タスク6.4 のパスワードとメールアドレスと確認のメールの筋書きで確かめる。要件4の受入基準2(もう一方の版でメールアドレスを確認しログインできる)は、小タスク6.6 の `cross-email-password.yaml` で確かめる
  - _要件: 3.1, 3.2, 3.3, 4.2_

- [x] 1.2 Java 版の答えを正解のファイルに控える

  Claude は、開発環境の `spring` のコンテナの中で、research.md の試作の記録の「確かめた環境」と同じ設定で、Java 版をもう1つ動かす。Claude は、所有者の開発のデータベース `keireki_pro` と Redis の DB 0 に触れない。Claude は、その Java 版に要求を送り、次の5つの答えを正解のファイルに置く。

  1. 試作の12通りのファイルの名前ごとの、答えと置いた画像の名前。置き場所は `internal/httpapi/testdata/multipart/` とする
  2. 試作の27通りの名前ごとの、保存した名前か答えの文言。置き場所は `internal/users/testdata/username/` とする
  3. UTF-8 として誤ったバイトを含む名前の、保存した名前。Claude は、試作の例の `61 E3 81 62` と `61 F4 90 80 80 62` と、2バイト、3バイト、4バイトの字の境目の例を送る。置き場所は `internal/httpapi/testdata/jdkutf8/` とする
  4. 本文を読む中間処理と multipart の読み方の節で、実装のときに Java 版の答えで確かめると決めた3つの要求の答え。置き場所は `internal/httpapi/testdata/multipart/java-checks/` とする
  5. 確認の済んだメールアドレスと名前を持つ利用者を退会させたときに、LocalStack の SES が受けた退会の完了のメールの件名と本文と、Java 版が差し込んだ名前とサイトの名前とサイトの URL。置き場所は `internal/auth/testdata/mail/` とし、件名と本文は `user-deleted.txt` に置く

  Claude は、試作の12通りと27通りの入力が research.md に一覧で残っていないので、research.md の試作の記録に書かれた例を含めて入力を作り直し、作り直した入力を正解のファイルに一緒に置く。Claude は、確かめたあとで、別に動かした Java 版を止め、使ったデータベースを消し、使った Redis の DB を空にし、置いた画像を消す。
  - 完了の確かめ方: 5つの置き場所に、入力と Java 版の答えの組が置かれている。12通りのファイルの名前には `x.GİF` と `a.png/` と RFC 2047 の書き方と `C:\dir\a.JPG` が、27通りの名前には NUL を含む名前と空の名前と50文字と51文字の名前と、前後に空白のある名前が含まれる
  - 受入基準とテストの対応: この小タスクは確認に使う正解のファイルを作り、受入基準を直接は確かめない。正解のファイルは、小タスク1.3 の退会の完了のメール、2.1 から2.4 の要求の本文の読み方、3.7 の名前と画像と2段階認証の設定の変更の単体テストで使う
  - _要件: 1.1, 1.3, 1.4_

- [x] 1.3 退会の完了のメールを足す

  Claude は、`mail.go` に、Mail の部品の節のとおりの退会の完了のメールを足し、`exported.go` に `SendUserDeletedMail` を足す。
  - 完了の確かめ方: `go test ./internal/auth/ -run 'TestMail_UserDeleted'` が通る。`TestMail_UserDeletedMatchesJava` は、小タスク1.2 で控えた値を渡して作った件名と本文の全体を、`user-deleted.txt` と比べる
  - 受入基準とテストの対応: 要件1の受入基準4(退会の完了のメールの宛先と件名と本文)は、`mail_test.go` の `TestMail_UserDeletedMatchesJava` と、名前が無いときに誤りを返す `TestMail_UserDeletedNoUsername` で確かめる。Java 版との突き合わせは、小タスク6.3 の `delete-user.yaml` で確かめる
  - _要件: 1.4_
  - _対象の部品: Mail_
  - _依存: 1.2_

- [x] 1.4 退会で消す表の SQL の問い合わせを書いて生成する

  Claude は、Delete の部品の節の11の表から利用者の行を消す問い合わせを `backend/db/queries/users.sql` に書き、sqlc でコードを生成する。Claude は、消す表の順を、Java 版の `UserMapper.xml` の削除の問い合わせを開いて確かめてから書く。
  - 完了の確かめ方: `make generate` が `sqlcgen` に退会の問い合わせのコードを生成し、`make generate-check` が通る
  - 受入基準とテストの対応: この小タスクは土台であり、受入基準を直接は確かめない。要件1の受入基準5(退会で消すもの)は、小タスク3.8 の `delete_integration_test.go` と、小タスク6.3 の `delete-user.yaml` で確かめる
  - _要件: 1.5_

- [x] 1.5 利用者の処理の入口と文言を作り、depguard の規則を変える

  Claude は、`internal/users` に、Service の部品の節のとおりの入口の型 `Service` と、部品の束 `Deps` と、組み立ての関数 `New` を作る。Claude は、`errors.go` に、Java 版の利用者の操作の文言の定数を置く。Claude は、文言の定数を、Java 版の利用者の操作のユースケースと `User` と要求の型の注釈を開いて写す。Claude は、品質チェックの設定の変更の提案の節のとおりに、`backend/.golangci.yml` の depguard の機能のパッケージの規則の許す一覧に `internal/auth` を1行足す。depguard は、golangci-lint の中で、パッケージが読んでよいほかのパッケージを規則で決め、規則に無いパッケージを読むコードを止める機能である。この変更は所有者の承認が要るので、Claude は、PR の本文に、承認が要る理由と、変える中身と、main に入れたときに本番で起きることを書く。
  - 完了の確かめ方: `go test ./internal/users/ -run 'TestNew|TestErrors'` が通る。`make lint` が、`internal/users` が `internal/auth` を読んだ状態で通る
  - 受入基準とテストの対応: 要件1の受入基準3(画面に出るエラーの文言)は、`errors_test.go` の `TestErrors_MessagesMatchJava` で確かめる。このテストは、文言の定数が Java 版のソースの文字列と同じかを確かめる
  - _要件: 1.1, 1.3_
  - _対象の部品: Service_

- [x] 1.6 偽の AWS が `//` を含む URL のパスを読めるようにする

  Claude は、Java 版と Go 版を比べる検査の広げ方の節の「偽の AWS が URL のパスを読む方法」のとおりに、偽の AWS の S3 の受け口を、`http.ServeMux` の前で要求の URL のパスをそのまま読み、置き場所の名前と画像の名前を取り出す形に変える。この変更を先に置くのは、小タスク1.7 の結合テストの土台のテストと、小タスク3.2 の画像の置き場所の処理の結合テストが、名前が `/` で始まる画像を偽の AWS に置いて読むためである。
  - 完了の確かめ方: `go test -tags compat ./compat/fakeaws/...` が通る。`s3_test.go` の `TestS3_DoubleSlashKey` は、名前が `/profile/image/` で始まる画像を置き、同じ名前で読み、同じ名前で消せることと、移るように答えないことを確かめる
  - 受入基準とテストの対応: 要件2の受入基準1から3(どちらの版でも同じ画像が表示される)を支える偽の AWS の読み方は、`s3_test.go` の `TestS3_DoubleSlashKey` で確かめる。今までの名前の画像を読めることは、今ある `fakeaws_test.go` のテストで確かめる
  - _要件: 2.1, 2.2, 2.3_

- [x] 1.7 利用者の処理の結合テストの土台を作る

  Claude は、`internal/users` の結合テストのための `TestMain` を作る。`TestMain` は、testcontainers-go で、Postgres と Valkey と偽の AWS のコンテナを起動し、`backend.Migrations()` を `migrate.Run` の `Apply` で流して表を作る。偽の AWS のコンテナは、`backend/compat/fakeaws/Dockerfile` から組み立てる。Claude は、結合テストのファイルを `_integration_test.go` で終わる名前にし、ビルドタグを付けない。
  - 完了の確かめ方: `go test ./internal/users/ -run TestIntegrationSetup` が、3つのコンテナを起動して通る。`TestIntegrationSetup` は、表があることと、Valkey に書けることと、偽の AWS の置き場所に、名前が `/` で始まる画像を置いて読めることを確かめる。1つ目の大きなまとまりの最後のタスクなので、完了条件の2つ目のとおり `/verify-backend` も通る
  - 受入基準とテストの対応: この小タスクは土台であり、受入基準を直接は確かめない。土台を使う結合テストは、小タスク3.2 の画像の置き場所の処理と、3.4 から3.9 の利用者の操作の処理のタスクで書く
  - _要件: 1.5, 2.1_
  - _依存: 1.6_

- [x] 2. 名前と画像と2段階認証の設定の変更の要求の本文を読む部品を作る
- [x] 2.1 JDK の UTF-8 の読み方を写す

  Claude は、本文を読む中間処理と multipart の読み方の節のとおりに、JDK の UTF-8 の読み方を写した、バイトの並びを文字列にする処理を `jdkutf8.go` に作る。
  - 完了の確かめ方: `go test ./internal/httpapi/ -run TestJDKUTF8` が通る
  - 受入基準とテストの対応: 要件1の受入基準1(Java 版と同じ本文)のうち誤ったバイトを含む名前の読み方は、`jdkutf8_test.go` の `TestJDKUTF8_MatchesJava` で確かめる。このテストは、小タスク1.2 の `testdata/jdkutf8/` の正解と、試作の2つの例の U+FFFD の数を比べる
  - _要件: 1.1_
  - _依存: 1.2_

- [x] 2.2 部分の名前とファイルの名前の読み方を写す

  Claude は、本文を読む中間処理と multipart の読み方の節のとおりに、Spring 7.0.10 の `ContentDisposition.parse` を写した読み方を `contentdisposition.go` に作る。Claude は、写す元の Spring のソースを、Java 版の依存の jar から開いて確かめる。
  - 完了の確かめ方: `go test ./internal/httpapi/ -run TestContentDisposition` が通る
  - 受入基準とテストの対応: 要件1の受入基準3(入力の誤りとして断る条件)のうちファイルの名前の読み方は、`contentdisposition_test.go` の `TestContentDisposition_MatchesJava` で確かめる。このテストは、小タスク1.2 の12通りのファイルの名前の正解と比べる
  - _要件: 1.3_
  - _依存: 1.2_

- [x] 2.3 multipart の本文を部分に分ける

  Claude は、`multipart.go` に、`Content-Type` の `boundary` で本文を部分に分け、部分ごとにヘッダと中身を取り出す処理を作る。multipart は、1つの要求の本文を、区切りの文字列 `boundary` で複数の部分に分けて、名前や画像のファイルを部分ごとに入れて送る形である。この処理は、部分のヘッダに制御文字があっても読む。
  - 完了の確かめ方: `go test ./internal/httpapi/ -run TestMultipart` が通る
  - 受入基準とテストの対応: 要件1の受入基準1(Java 版と同じ答え)のうち部分の分け方は、`multipart_test.go` の `TestMultipart_ControlCharInHeader` と `TestMultipart_Malformed` で確かめる
  - _要件: 1.1_

- [x] 2.4 名前と画像と2段階認証の設定の変更の要求の本文を読む中間処理を作る

  Claude は、`users.go` に、本文を読む中間処理と multipart の読み方の節の5つの手順のとおりの、生成したコードの中間処理を作る。この中間処理は、操作の名前が `UpdateUserInfo` のときだけ動き、読んだ項目を `context` に入れる。Claude は、小タスク1.2 で控えた3つの要求の Java 版の答えと、節の決まりが食い違えば、Java 版に合わせ、合わせた中身を research.md に書き足す。
  - 完了の確かめ方: `go test ./internal/httpapi/ -run TestUpdateUserInfoBody` が通る。テストは、テストの方針の `multipart.go` と本文を読む中間処理の行の場合を含む。2つ目の大きなまとまりの最後のタスクなので、完了条件の2つ目のとおり `/verify-backend` も通る
  - 受入基準とテストの対応: 要件1の受入基準1と3(Java 版と同じ答えと入力の誤りの条件)は、`users_test.go` の `TestUpdateUserInfoBody_SizeBoundary` と `TestUpdateUserInfoBody_UsernameJoin` と `TestUpdateUserInfoBody_TwoFactorValues` で確かめる。`TestUpdateUserInfoBody_SizeBoundary` は、2097152 バイトと 2097153 バイトの本文を確かめる。要件5の受入基準4(Java 版の 500 を Go 版の 400 にする要求)のうち、2MB を超える本文と、真偽として読めない `twoFactorAuthEnabled` と、ファイルとして送った `username` の3つの場合は、`TestUpdateUserInfoBody_JavaFiveHundredAs400` で確かめる。multipart でない本文の場合は、生成したコードが中間処理より前に断る。そのため、この場合は、小タスク4.2 の、受け口と中間処理を組み立てる関数と起動につなぐタスクで確かめる
  - _要件: 1.1, 1.3, 5.4_
  - _対象の部品: 本文を読む中間処理と multipart の読み方_
  - _依存: 1.2_

- [x] 3. 利用者の操作の処理を作る
- [x] 3.1 画像を検査する (並行可)

  Claude は、ImageCheck の部品の節の6つの検査の順のとおりに、画像を検査する `checkImage` と、拡張子の取り出しを `image.go` に作る。
  - 完了の確かめ方: `go test ./internal/users/ -run TestCheckImage` が通る
  - 受入基準とテストの対応: 要件1の受入基準3(画像の大きさと縦と横の長さの上限と文言)は、`image_test.go` の `TestCheckImage_Boundaries` と `TestCheckImage_ErrorOrder` と `TestCheckImage_NonASCIIExtension` で確かめる。`TestCheckImage_Boundaries` は、1048576 バイトと 1048577 バイトの画像と、4096 画素と 4097 画素の画像を確かめる。`TestCheckImage_ErrorOrder` は、誤りが重なったときの文言の並びを確かめる
  - _要件: 1.3_
  - _対象の部品: ImageCheck_

- [x] 3.2 画像の置き場所への書き込みと削除と署名付きの URL を作る (並行可)

  Claude は、ObjectStore の部品の節のとおりに、`objectstore.go` に、画像を置く処理と消す処理と署名付きの URL を作る処理を作る。Claude は、`objectstore.go` を書く前に、テストの方針の節の `objectstore.go` の項目のとおりに、署名付きの URL の正解を次の順に作る。

  1. Claude は、Java 版が使う AWS SDK for Java の版を、`spring` と同じイメージの1回きりのコンテナで `./gradlew dependencies --configuration runtimeClasspath` の出力から確かめる
  2. Claude は、Java 版の `S3ObjectStore` と同じ `S3Presigner` で URL を署名する小さな Java のプログラムを、`internal/users/testdata/presign/` に置く。このプログラムは、Java 版の `application-dev.yaml` と同じ接続先 `http://localstack:4566`、地域 `ap-northeast-1`、資格情報 `dummy`、パスの形の設定で、置き場所 `keirekipro-storage` の `/profile/image/` で始まる画像の名前に、600秒の URL を署名する。Claude は、プログラムの使い方を、ファイルの先頭の注釈に書く
  3. Claude は、このプログラムを、`spring` と同じイメージの1回きりのコンテナで、Gradle が取ってきた AWS SDK for Java の jar を `--class-path` に並べた `java` の1つのソースのファイルの起動で動かす。Claude は、出た URL を、同じフォルダに正解のファイルとして置く。正解の URL のホストは、`localhost` に置き換える前の `localstack:4566` のままにする

  Claude は、AWS SDK for Java の版を確かめる手順1のコマンドと、署名のプログラムを動かす手順3のコマンドを、`bash .claude/scripts/parallel/run-check.sh backend <コマンド>` の形で流す。このスクリプトは、`spring` と同じイメージの1回きりのコンテナに、この会話の作業フォルダの `backend/` を読み込ませる。そのため、作業フォルダに置いたプログラムがコンテナから見え、出た URL の正解のファイルも作業フォルダに書かれる。開発環境の `spring` のコンテナは、compose を起動したフォルダの `backend/` を読むので、作業フォルダのプログラムが見えないことがある。`run-check.sh` はコマンドをシェルを通さずに動かすので、Claude は、版を確かめる手順1のコマンドと、署名のプログラムを動かす手順3のコマンドを、`sh -c '…'` の1回のコマンドにまとめる。こうすると、jar を探して `--class-path` に並べる部分は、コンテナの中のシェルで展開される。`./gradlew dependencies` は依存の一覧を作るだけで、jar を取ってこない。そのため、Claude は、同じ `sh -c '…'` の中で、AWS SDK for Java の版を確かめる手順1のあと、署名のプログラムを動かす手順3の前に、`./gradlew bootJar` を流す。`bootJar` は Java 版の実行に要る jar をすべて Gradle の置き場に取ってくるので、署名のプログラムを動かす手順3の `java` の起動は、その jar を同じ置き場から読める。

  Claude は、`build.gradle` を変えない。そのため、この作業は、所有者の承認が要る backend のビルドスクリプトの変更にあたらない。
  - 完了の確かめ方: `internal/users/testdata/presign/` に、Java のプログラムと、その使い方の注釈と、出た URL の正解のファイルが置かれている。`go test ./internal/users/ -run 'TestPresign|TestObjectStore'` が通る。`TestPresign_MatchesJava` は、正解のファイルの URL の `X-Amz-Date` の時刻を署名の時刻として使い、正解と同じ資格情報で作った URL が、正解のファイルの URL と1文字も違わないことを確かめる。`TestObjectStore_PutDelete` は、小タスク1.7 の偽の AWS に、名前が `/` で始まる画像を置き、`Content-Type` とメタデータが部分の `Content-Type` になっていることと、消したあとに無いことを確かめる
  - 受入基準とテストの対応: 要件3の受入基準6(URL を使える時間)と要件2の受入基準1と2(どちらの版でも同じ画像が表示される)のうち URL の形は、`objectstore_test.go` の `TestPresign_MatchesJava` と `TestPresign_SecurityTokenBeforeSignature` と `TestPresign_LocalhostOnlyInDev` で確かめる。`TestPresign_MatchesJava` は、Java のプログラムで作った正解と1文字も違わないことを確かめる。要件1の受入基準5(退会で画像を消す)を支える削除は、`objectstore_integration_test.go` の `TestObjectStore_PutDelete` と `TestObjectStore_DeleteMissingKey` で確かめる
  - _要件: 1.5, 2.1, 2.2, 2.3, 3.6_
  - _対象の部品: ObjectStore_
  - _依存: 1.6, 1.7_

- [x] 3.3 パスワードの要求の入力を検査する (並行可)

  Claude は、Validate の部品の節のとおりに、パスワードの変更と、メールアドレスとパスワードの設定の要求を検査する2つの関数を `validate.go` に作る。Claude は、検査の部品に、`exported.go` で公開した部品を使う。
  - 完了の確かめ方: `go test ./internal/users/ -run TestValidate` が通る
  - 受入基準とテストの対応: 要件1の受入基準3(パスワードの長さと使う文字の決まりと文言)は、`validate_test.go` の `TestValidate_ChangePasswordBoundaries` と `TestValidate_SetEmailAndPasswordBoundaries`(空白だけ、7文字と8文字、UTF-8 の72バイトと73バイト、`null` のメールアドレス、255文字と256文字のメールアドレス)で確かめる。要件5の受入基準4(変えた動きの一覧に載せる要求)のうち本文の項目が無い要求は、`TestValidate_MissingFields` で確かめる。このテストは、`nowPassword` `newPassword` `password` を省いた要求が空の文字列と同じ文言を返すことと、`confirmPassword` を省いた要求が一致の文言を足さないことを確かめる
  - _要件: 1.3, 5.4_
  - _対象の部品: Validate_
  - _依存: 1.1_

- [x] 3.4 連携を解除する (並行可)

  Claude は、Provider の部品の節のとおりに、Google か GitHub のアカウントとの連携を解除する `RemoveAuthProvider` を `provider.go` に作る。
  - 完了の確かめ方: `go test ./internal/users/ -run TestRemoveAuthProvider` が通る
  - 受入基準とテストの対応: 要件3の受入基準5(連携を解除できる条件)は、`provider_integration_test.go` の `TestRemoveAuthProvider_LastProviderWithoutPassword` と `TestRemoveAuthProvider_NotLinked` と `TestRemoveAuthProvider_UpperCaseName` と `TestRemoveAuthProvider_Success` で確かめる。要件1の受入基準6(すでに居ない利用者)は `TestRemoveAuthProvider_UserGone` で確かめる
  - _要件: 1.2, 1.6, 3.5, 4.1_
  - _対象の部品: Provider_
  - _依存: 1.7_

- [x] 3.5 確認のメールを送る (並行可)

  Claude は、EmailVerification の部品の節のとおりに、確認のメールを送る `SendAccountEmailVerification` を `emailverification.go` に作る。
  - 完了の確かめ方: `go test ./internal/users/ -run TestSendAccountEmailVerification` が通る
  - 受入基準とテストの対応: 要件3の受入基準3(送り直せる間隔と、新しいリンクで前のリンクが使えなくなること)は、`emailverification_integration_test.go` の `TestSendAccountEmailVerification_RateLimited` と `TestSendAccountEmailVerification_ReplacesPreviousLink` で確かめる。要件1の受入基準4(確認のメールの宛先)は、`TestSendAccountEmailVerification_PendingEmailFirst` と `TestSendAccountEmailVerification_AccountEmail` で、確認の要るメールアドレスが無い利用者の 400 は `TestSendAccountEmailVerification_NothingToVerify` で確かめる。要件1の受入基準6(すでに居ない利用者)は `TestSendAccountEmailVerification_UserGone` で確かめる
  - _要件: 1.2, 1.4, 1.6, 3.3_
  - _対象の部品: EmailVerification_
  - _依存: 1.1, 1.7_

- [x] 3.6 利用者の情報を読む

  Claude は、UserInfo の部品の節のとおりに、利用者の情報の10の項目を返す `GetUserInfo` を `userinfo.go` に作る。
  - 完了の確かめ方: `go test ./internal/users/ -run TestGetUserInfo` が通る
  - 受入基準とテストの対応: 要件1の受入基準1(Java 版と同じ本文)のうち項目と値は、`userinfo_integration_test.go` の `TestGetUserInfo_Fields` と `TestGetUserInfo_NoImageIsNull` と `TestGetUserInfo_SortedProvidersAndRoles` で確かめる。要件3の受入基準6(URL を使える時間)は `TestGetUserInfo_PresignExpires600` で、要件1の受入基準6(すでに居ない利用者)は `TestGetUserInfo_UserGone` で確かめる
  - _要件: 1.1, 1.6, 2.1, 2.2, 3.6, 4.1_
  - _対象の部品: UserInfo_
  - _依存: 3.2_

- [x] 3.7 名前と画像と2段階認証の設定を変える

  Claude は、Update の部品の節の7つの手順のとおりに、`UpdateUserInfo` を `update.go` に作る。
  - 完了の確かめ方: `go test ./internal/users/ -run TestUpdateUserInfo` が通る
  - 受入基準とテストの対応: 要件1の受入基準3(名前の長さの上限と文言)は、`update_test.go` の `TestUpdateUserInfo_UsernameMatchesJava` で確かめる。このテストは、小タスク1.2 の27通りの名前の正解と比べる。このテストは、前後の空白の判定を、research.md の試作の記録の P6 に書いた、名前の前後から取り除く字と取り除かない字の一覧で確かめる。要件3の受入基準4(2段階認証の設定を変えられる条件)は、`update_integration_test.go` の `TestUpdateUserInfo_AdminCannotDisable2FA` と `TestUpdateUserInfo_Enable2FARequiresEmailAndPassword` で確かめる。要件2の受入基準3(替えたあとの画像)と、名前の誤りで断っても画像が残ることは、`TestUpdateUserInfo_ReplaceImage` と `TestUpdateUserInfo_ImageKeptOnUsernameError` で確かめる。要件1の受入基準6(すでに居ない利用者)は `TestUpdateUserInfo_UserGone` で確かめる
  - _要件: 1.2, 1.3, 1.6, 2.2, 2.3, 3.4, 4.1_
  - _対象の部品: Update_
  - _依存: 1.2, 3.1, 3.2_

- [x] 3.8 退会する

  Claude は、Delete の部品の節と処理の流れの節の「退会」の順のとおりに、1つのトランザクションの中で処理する `DeleteUser` を `delete.go` に作る。
  - 完了の確かめ方: `go test ./internal/users/ -run TestDeleteUser` が通る
  - 受入基準とテストの対応: 要件1の受入基準5(退会で消すもの)は、`delete_integration_test.go` の `TestDeleteUser_RemovesRowsImagesAndTokens` と `TestDeleteUser_NoDuplicateKeyDelete` で確かめる。`TestDeleteUser_RemovesRowsImagesAndTokens` は、11の表の行と、5つの画像の名前と、ログインを続けるための値が消えることを確かめる。要件3の受入基準2(退会ですべての端末のログインの状態を使えなくする)は `TestDeleteUser_InvalidatesSessions` と、トランザクションの中の世代の番号の問い合わせが待たずに終わる `TestDeleteUser_BumpInTransactionDoesNotBlock` で確かめる。要件1の受入基準4(退会の完了のメール)は `TestDeleteUser_MailOnlyWhenVerified` で、メールを送れないときに行が戻ることは `TestDeleteUser_MailFailureRollsBack` で確かめる。要件1の受入基準6(すでに居ない利用者)は `TestDeleteUser_UserGone` で確かめる
  - _要件: 1.4, 1.5, 1.6, 3.2, 4.3_
  - _対象の部品: Delete_
  - _依存: 1.3, 1.4, 3.2_

- [x] 3.9 パスワードを変え、メールアドレスとパスワードを設定する

  Claude は、Password の部品の節のとおりに、`ChangePassword` と `SetEmailAndPassword` を `password.go` に作る。
  - 完了の確かめ方: `go test ./internal/users/ -run 'TestChangePassword|TestSetEmailAndPassword'` が通る。3つ目の大きなまとまりの最後のタスクなので、完了条件の2つ目のとおり `/verify-backend` も通る
  - 受入基準とテストの対応: 要件3の受入基準1(今のパスワードが合わなければ変えない)は、`password_integration_test.go` の `TestChangePassword_WrongNowPassword` と `TestSetEmailAndPassword_WrongNowPassword` で確かめる。要件3の受入基準2(パスワードの変更ですべての端末のログインの状態を使えなくする)は `TestChangePassword_InvalidatesSessions` で確かめる。要件1の受入基準3(入力の誤りの条件と文言)は、メールアドレスの空と形の誤りの文言が、すでにメールアドレスを持つ誤りの文言と一緒に返る `TestSetEmailAndPassword_CollectsEmailErrors` と、`TestSetEmailAndPassword_EmailInUse` で確かめる。要件1の受入基準4(確認のメール)は `TestSetEmailAndPassword_SendsPendingEmailVerification` で、確認のメールを送れないときに行が戻ることは `TestSetEmailAndPassword_MailFailureRollsBack` で確かめる。要件1の受入基準6(すでに居ない利用者)は `TestChangePassword_UserGone` と `TestSetEmailAndPassword_UserGone` で確かめる
  - _要件: 1.2, 1.3, 1.4, 1.6, 3.1, 3.2, 3.3, 4.2, 4.3_
  - _対象の部品: Password_
  - _依存: 3.3_

- [x] 4. 利用者の受け口をつなぐ
- [x] 4.1 利用者の7つの操作の受け口と応答の型を作る

  Claude は、`users.go` に、利用者の受け口の節のとおりの型 `userHandlers` と7つの操作のメソッドを作り、`userresponses.go` に7つの操作の `Visit<操作の名前>Response` を作る。受け口は、利用者の処理をインタフェースで受ける。テストで処理の代わりを使うためである。`updateUserInfo` の受け口は、小タスク2.4 の中間処理が `context` に入れた項目を読む。
  - 完了の確かめ方: `go test ./internal/httpapi/ -run 'TestUserHandlers|TestUserResponses'` が通る
  - 受入基準とテストの対応: 要件1の受入基準1と2(Java 版と同じ状態の番号と本文と Cookie)は、`users_test.go` の `TestUserHandlers_SuccessResponses` と `TestUserHandlers_DeleteUserClearsCookies` で確かめる。`TestUserHandlers_SuccessResponses` は、利用者の受け口の節の表の7つの操作を確かめる。要件1の受入基準6(すでに居ない利用者の要求を断り Cookie を消す)は、`TestUserHandlers_UserGoneClearsCookies` で確かめる
  - _要件: 1.1, 1.2, 1.6_
  - _対象の部品: 利用者の受け口_
  - _依存: 2.4, 3.3, 3.4, 3.5, 3.6, 3.7, 3.8, 3.9_

- [x] 4.2 受け口と中間処理を組み立てる関数と起動につなぐ

  Claude は、httpapi.New の変更の節のとおりに、`server.go` の `Options` に `UserHandlers` を足し、`routes` に利用者の受け口を深さ1で埋め込み、生成したコードの中間処理の並びに本文を読む中間処理を足す。Claude は、`main.go` で、`users.New` で `Service` を作り、`httpapi.Options` に渡す。
  - 完了の確かめ方: `go test ./internal/httpapi/ ./cmd/keirekipro/` が通る。`server_test.go` の `TestNew_UserOperationsNotUnimplemented` は、7つの操作が未実装の答えでなく利用者の受け口に届くことと、ほかのまとまりの操作が未実装の答えのままであることを確かめる。4つ目の大きなまとまりの最後のタスクなので、完了条件の2つ目のとおり `/verify-backend` も通る
  - 受入基準とテストの対応: 要件1の受入基準1(利用者の操作の要求に Go 版が答える)は、`server_test.go` の `TestNew_UserOperationsNotUnimplemented` と、`main_test.go` の、組み立てた `Service` が `Options` に渡ることを確かめる場合で確かめる。要件5の受入基準4(Java 版の 500 を Go 版の 400 にする要求)のうち multipart でない本文の場合は、`server_test.go` の `TestNew_UpdateUserInfoNonMultipart400` で確かめる。このテストは、`New` が組み立てた受け口に multipart でない本文を送り、400 と `{"message": "入力エラーがあります。", "errors": {}}` が返ることを確かめる。要件6の受入基準1(ログインした開発者の情報を返す)は、小タスク7.1 の API の説明画面での確認で確かめる
  - _要件: 1.1, 5.4, 6.1_
  - _対象の部品: httpapi.New の変更_

- [ ] 5. Java 版と Go 版を比べる検査を広げる
- [x] 5.1 筋書きの形に5つの欄を足し、読むときに確かめる

  Claude は、`scenario.go` に、Java 版と Go 版を比べる検査の広げ方の節の `request.multipart` `request.body_file` `expect.values` `expect.body_file` `expect.content_type` の5つの欄を足す。harness は、筋書きを読むときに、`request.multipart` の `file` が `fixtures/images` に無いときと、`request.body_file` と `expect.body_file` と `expect.content_type` が絶対の URL の段に無いときを、段の名前を付けた誤りとして返す。
  - 完了の確かめ方: `go test -tags compat ./compat/harness/ -run 'TestScenarioValidate_UserFields'` が通る
  - 受入基準とテストの対応: 要件5の受入基準1(画像の大きさ、縦と横の長さ、ファイルの形式の誤りを含む要求を筋書きに書ける)は、`scenario_test.go` の `TestScenarioValidate_UserFields` で確かめる
  - _要件: 5.1_

- [x] 5.2 multipart の本文を組み立てて送る

  Claude は、`harness/multipart.go` に、筋書きの `request.multipart` から、決まった `boundary` で本文を組み立てる処理を作る。この処理は、`pad_to` を書いた `file` の部分の後ろに0のバイトを足して、ファイルを `pad_to` の大きさにする。Claude は、`send.go` に、`request.multipart` の本文と、絶対の URL の段の `request.body_file` の本文を送る処理を足す。
  - 完了の確かめ方: `go test -tags compat ./compat/harness/ -run 'TestMultipartBody|TestSend_BodyFile'` が通る
  - 受入基準とテストの対応: 要件5の受入基準1(1MB を超える画像を含む要求)は、`multipart_test.go` の `TestMultipartBody_PadTo` と `TestMultipartBody_FixedBoundary` で確かめる。`TestMultipartBody_PadTo` は、1048577 バイトにした PNG を `image.DecodeConfig` で読めることを確かめる。要件2の受入基準1(Java 版で置いた画像を Go 版で見せる)を支える画像の置き方は、`send_test.go` の `TestSend_BodyFile` で確かめる
  - _要件: 2.1, 5.1_

- [ ] 5.3 絶対の URL の段の宛先と Host を書き換える

  Claude は、Java 版と Go 版を比べる検査の広げ方の節の「絶対の URL の書き換え」のとおりに、絶対の URL の段の宛先と `Host` を書き換える処理を作る。この処理は、絶対の URL の段の URL のホストが `localhost:4566` のときに、宛先を偽の AWS のアドレスにし、要求の `Host` を、その版の設定の AWS の接続先のホストとポートにする。
  - 完了の確かめ方: `go test -tags compat ./compat/harness/ -run TestAbsoluteURL_FakeAWSRewrite` が通る
  - 受入基準とテストの対応: 要件2の受入基準1から3(どちらの版でも同じ画像が表示される)を支える画像の読み方は、`steps_test.go` の `TestAbsoluteURL_FakeAWSRewrite` で確かめる。このテストは、`localhost:4566` のほかのホストの URL を書き換えないことも確かめる
  - _要件: 2.1, 2.2, 2.3_

- [ ] 5.4 応答の値と画像のバイトと `Content-Type` を確かめる

  Claude は、`steps.go` に、`expect.values` と `expect.body_file` と `expect.content_type` で応答を確かめる処理を足す。外れたときは、harness は、段の名前と、期待した値と、受けた値を報告に書く。画像の中身は報告に書かず、大きさと SHA-256 だけを書く。
  - 完了の確かめ方: `go test -tags compat ./compat/harness/ -run 'TestExpectValues|TestExpectBodyFile|TestExpectContentType'` が通る
  - 受入基準とテストの対応: 要件4の受入基準1(一方の版で変えたものが、もう一方の版でも見える)を確かめる道具は、`steps_test.go` の `TestExpectValues_WithCapturedNames` で確かめる。要件2の受入基準1から3(同じ画像が表示される)を確かめる道具は、`TestExpectBodyFile_SizeAndSHA256Only` と `TestExpectContentType` で確かめる
  - _要件: 2.1, 2.2, 2.3, 4.1_

- [ ] 5.5 署名付きの URL の値を正規化する

  Claude は、`normalize.go` に、文字と JSON の本文の中の、問い合わせに `X-Amz-Signature` を持つ URL の、`X-Amz-Date` の値と `X-Amz-Credential` の中の日付と `X-Amz-Signature` の値を決まった文字列に置き換える処理を足す。
  - 完了の確かめ方: `go test -tags compat ./compat/harness/ -run TestNormalize_PresignedURL` が通る
  - 受入基準とテストの対応: 要件5の受入基準3(要求のたびに違う値の比べ方)は、`normalize_test.go` の `TestNormalize_PresignedURL` で確かめる。このテストは、`X-Amz-Expires` の値と項目の並ぶ順と URL のパスを置き換えないことと、項目の順が違う URL が違いとして残ることを確かめる
  - _要件: 5.3_

- [ ] 5.6 画像の置き場所の比べ方に `Content-Type` とメタデータを足す

  Claude は、Java 版と Go 版を比べる検査が画像の置き場所を比べるときに、今の置き場所の名前とバイトの並びに加えて、`Content-Type` と、利用者の付けた値(メタデータ)を比べるようにする。
  - 完了の確かめ方: `go test -tags compat ./compat/harness/ -run TestCompareObjects_ContentTypeAndMetadata` が通る
  - 受入基準とテストの対応: 要件5の受入基準2(アップロードした画像の置き場所に残ったものを比べる)は、`compare_test.go` の `TestCompareObjects_ContentTypeAndMetadata` で確かめる
  - _要件: 5.2_

- [ ] 5.7 新しい欄を3つの動かし方につなぐ

  Claude は、`compareenv.go` `compare.go` `crossenv.go` `cross.go` `perfenv.go` を、小タスク5.1 から5.6 の欄と処理を使う形に変える。比べる動かし方では、harness は、絶対の URL の段を版ごとに1回ずつ送り、版ごとの AWS の接続先で `Host` を決める。版をまたぐ動かし方では、harness は、`expect.values` と `expect.body_file` を、送り先の版の応答で確かめる。Claude は、広げたあとに、認証の操作の筋書きを動かし直し、結果が変わらないことを確かめる。
  - 完了の確かめ方: `go test -tags compat ./compat/harness/ -run 'TestCompareEnv_UserFields|TestCrossEnv_UserFields|TestPerfEnv_UserFields'` が通る。Claude は、3つのテストを、今ある `TestCompareEnv_NewSteps` と同じ `modes_test.go` に置く。`make compat` と `make compat-cross` が、認証の操作の筋書きで通る
  - 受入基準とテストの対応: 要件4の受入基準4(版をまたいで確かめる検査に筋書きを足す)と要件5の受入基準1から3(Java 版と Go 版を比べる検査の筋書きと比べるもの)を3つの動かし方で使えることは、`modes_test.go` の3つの `UserFields` のテストで確かめる。広げたあとも認証の操作の答えが変わらないことは、`make compat` と `make compat-cross` の認証の筋書きで確かめる
  - _要件: 4.4, 5.1, 5.2, 5.3_
  - _依存: 1.6_

- [ ] 5.8 並びの順だけの違いを許す、変えた動きの項目を足す

  Claude は、変えた動きの一覧の項目の節のうち、match を書く2つの項目を、`changed-behaviors.yaml` に `group: 2` で足す。1つは、`getUserInfo` `updateUserInfo` `setEmailAndPassword` の答えの `$.roles[*]` と `$.authProviders[*]` の並びの順の項目で、CB-028 とする。もう1つは、`changePassword` と `setEmailAndPassword` の入力の誤りの文言の並びの項目である。この2つを筋書きより前に足すのは、Java 版の並びの順が決まっていないためである。項目が無いと、小タスク6.1 から6.4 で書く利用者の操作の筋書きで、Java 版と Go 版の答えの比較が、並びの順の違いだけで外れる。Claude は、`match_test.go` に、本物の `changed-behaviors.yaml` を読み、利用者の操作の項目の番号と、項目ごとの match の有無と中身を確かめる `TestChangedBehaviors_UserItems` を作る。
  - 完了の確かめ方: `go test -tags compat ./compat/harness/ -run 'TestChangedBehaviors_UserItems|TestLoadChangedBehaviors'` が通る。5つ目の大きなまとまりの最後のタスクなので、完了条件の2つ目のとおり `/verify-backend` も通る。`/verify-backend` は `-tags compat` のテストを流さないので、加えて `go test -tags compat ./compat/harness/ ./compat/fakeaws/...` も通る
  - 受入基準とテストの対応: 要件5の受入基準3(要求のたびに違う値の比べ方)のうち並びの順は、`match_test.go` の `TestChangedBehaviors_UserItems` で確かめる。このテストは、2つの項目が `order_only: true` の match を持つことを確かめる
  - _要件: 5.3, 5.4_

- [ ] 6. 利用者の操作の筋書きで Java 版と Go 版を比べる
- [ ] 6.1 初期のデータと画像のファイルと、利用者の情報を見る筋書きを書く

  Claude は、利用者の操作の筋書きの節の表の5人の利用者を置く `fixtures/users/users-ops.sql` と、`fixtures/images/wide.png` と `fixtures/images/not-image.png` を作る。Claude は、同じ節のとおりに、`get-user-info.yaml` を `group: 2` と `modes: [compare]` で書く。Claude は、利用者の操作の筋書きの `fixtures` に、`users/basic.sql` と `users/auth-users.sql` と `users/users-ops.sql` を書く。
  - 完了の確かめ方: `make compat` が `get-user-info.yaml` で通り、答え、Cookie、データベース、Redis、画像の置き場所に違いが出ない
  - 受入基準とテストの対応: 要件1の受入基準1と2(利用者の情報を見る操作で Java 版と同じ答え)は、`get-user-info.yaml` の、画像の無い利用者、パスワードの無い利用者、管理者、設定待ちのメールアドレスを持つ利用者の場面で確かめる。要件2の受入基準2(Go 版で置いた画像を表示する)と要件3の受入基準6(URL を使える時間)は、画像のある利用者の場面の `$.profileImage` の URL の形と、`expect.body_file` の画像で確かめる
  - _要件: 1.1, 1.2, 2.2, 3.6, 5.1, 5.2, 5.3_
  - _依存: 4.2, 5.7, 5.8_

- [ ] 6.2 名前と画像と2段階認証の設定の変更の筋書きを書く

  Claude は、利用者の操作の筋書きの節のとおりに、`update-user-info.yaml` と `update-validation.yaml` を書く。
  - 完了の確かめ方: `make compat` が2つの筋書きで通る
  - 受入基準とテストの対応: 要件1の受入基準3(入力の誤りの条件と文言)は、`update-validation.yaml` の、名前の空と空白だけと51文字、画像の `Content-Type` と拡張子の誤り、1048577 バイトの画像、`wide.png`、`not-image.png` の場面で確かめる。要件3の受入基準4(2段階認証の設定を変えられる条件)は、管理者が使わない設定にする場面と、パスワードの無い利用者が使う設定にする場面で確かめる。要件2の受入基準3(替えたあとの画像)は、`update-user-info.yaml` の拡張子の違う画像への替えの場面で確かめる。名前の誤りで断っても画像が残ることは、同じ筋書きで画像の置き場所を比べて確かめる
  - _要件: 1.1, 1.2, 1.3, 2.3, 3.4, 5.1, 5.2_

- [ ] 6.3 退会と連携の解除の筋書きを書く

  Claude は、利用者の操作の筋書きの節のとおりに、`delete-user.yaml` と `remove-auth-provider.yaml` を書く。`delete-user.yaml` の、2つの連携を持つ利用者の画像は、harness が、筋書きの始めの絶対の URL の段で、`request.body_file` で偽の AWS に置く。
  - 完了の確かめ方: `make compat` が2つの筋書きで通る
  - 受入基準とテストの対応: 要件1の受入基準5(退会で消すもの)は、`delete-user.yaml` で、画像のある利用者と2つの連携を持つ利用者が退会したあとのデータベースと画像の置き場所を比べて確かめる。要件1の受入基準4(退会の完了のメール)は、両方の版が送ったメールを比べて確かめる。要件1の受入基準6と要件5の受入基準1(退会した利用者の要求の2つの場合)は、パスワードを変えずに退会した場合の 401 と2つの Cookie の削除と、パスワードを変えてから退会した場合の断られ方で確かめる。要件3の受入基準5(連携を解除できる条件)は、`remove-auth-provider.yaml` の最後の連携の解除の場面で確かめる
  - _要件: 1.4, 1.5, 1.6, 3.2, 3.5, 5.1, 5.2_

- [ ] 6.4 パスワードとメールアドレスと確認のメールの筋書きを書く

  Claude は、利用者の操作の筋書きの節のとおりに、`email-password.yaml` と `change-password.yaml` と `email-verification.yaml` を書く。
  - 完了の確かめ方: `make compat` が3つの筋書きで通る
  - 受入基準とテストの対応: 要件1の受入基準2(メールアドレスとパスワードを設定し、届いたリンクで確認する)は、`email-password.yaml` の、設定のあとに届いたリンクを `verifyEmail` に送る場面で確かめる。要件3の受入基準1(今のパスワードの照合)は、`email-password.yaml` と `change-password.yaml` の今のパスワードが合わない場面で、要件3の受入基準2(パスワードの変更で前のログインの状態を使えなくする)は、`change-password.yaml` の変更の前のログインの状態での要求の場面で確かめる。要件3の受入基準3(送り直せる間隔と前のリンク)は、`email-verification.yaml` の間隔の中の送り直しと前のリンクの場面で確かめる。要件1の受入基準4(確認のメールの宛先と件名と本文)は、3つの筋書きで両方の版が送ったメールを比べて確かめる
  - _要件: 1.2, 1.3, 1.4, 3.1, 3.2, 3.3, 5.1, 5.2, 5.3_

- [ ] 6.5 ログインの状態と偽の送信の筋書きと、残りの変えた動きの項目を書く

  Claude は、利用者の操作の筋書きの節のとおりに、`require-login.yaml` を書く。Claude は、変えた動きの一覧の項目の節のうち、match を書かない項目を、`changed-behaviors.yaml` に `group: 2` で足す。足すのは、本文の項目が無い要求の項目と、Java 版の 500 を Go 版の 400 にする4つの要求の項目である。実装の中で Java 版が 500 で答えるほかの形の誤った要求が見つかっていれば、Claude は、要求ごとに1つの項目を足す。Claude は、`TestChangedBehaviors_UserItems` が確かめる項目に、足した項目を加える。Claude は、並びの順だけの違いを許す項目を足す小タスク5.8 とこの小タスクで足したすべての項目の一覧と、項目ごとに画面に影響が無い理由を所有者に示し、所有者が受け入れた日を、項目の「画面に影響が無い理由」に書く。
  - 完了の確かめ方: `make compat` が、`require-login.yaml` と、小タスク6.1 から6.4 で書いた利用者の操作の筋書きのすべてで通る。`go test -tags compat ./compat/harness/ -run 'TestChangedBehaviors_UserItems|TestLoadChangedBehaviors'` が通る
  - 受入基準とテストの対応: 要件5の受入基準1(ログインの状態を持たない要求、切れた要求、偽の要求を見分けるヘッダを付けない要求)は、`require-login.yaml` の7つの操作の場面で確かめる。要件5の受入基準4(答えを変えた要求を変えた動きの一覧に載せる)は、`match_test.go` の `TestChangedBehaviors_UserItems` で確かめる。このテストは、match を書かない項目が match を持たないことを確かめる
  - _要件: 5.1, 5.4_

- [ ] 6.6 版をまたいで確かめる筋書きを書いて通す

  Claude は、まず、版をまたいで確かめる筋書きの送り先を確かめるテスト `TestCrossRoute_UserSteps` を `backend/compat/harness/cross_test.go` に作る。このテストは、`scenarios/users/` の、`modes` に `cross` を書いた筋書きを読み、Java 版から Go 版の向きと Go 版から Java 版の向きのそれぞれで、`expect.values` か `expect.body_file` を持つ段と前のログインの状態を送る段が、その前の変える段と違う版に送られることを確かめる。このテストは、`cross-update.yaml` と `cross-email-password.yaml` と `cross-invalidate.yaml` のどれかが無ければ失敗する。Claude は、そのあとで、利用者の操作の筋書きの節のとおりに、`cross-update.yaml` と `cross-email-password.yaml` と `cross-invalidate.yaml` を書く。
  - 完了の確かめ方: `go test -tags compat -run TestCrossRoute_UserSteps ./compat/harness/` が通る。`make compat-cross` が、Java 版から Go 版、Go 版から Java 版、交互の3つの向きで通る
  - 受入基準とテストの対応: 要件4の受入基準1(変えたものがもう一方の版で見える)と要件2の受入基準1と2(一方の版で置いた画像をもう一方の版で表示する)は、`cross-update.yaml` の `expect.values` と `expect.body_file` で確かめる。要件4の受入基準2(もう一方の版で確認しログインする)は `cross-email-password.yaml` で、要件4の受入基準3(前のログインの状態がもう一方の版で使えない)は `cross-invalidate.yaml` で確かめる。要件4の受入基準4(両方の向きの筋書きを CI で動かす)は、`TestCrossRoute_UserSteps` と、CI で動く `make compat-cross` の `TestCross_` の検査で確かめる
  - _要件: 2.1, 2.2, 4.1, 4.2, 4.3, 4.4_

- [ ] 6.7 主な操作の応答の時間を測る

  Claude は、利用者の操作の筋書きの節のとおりに、`get-user-info-perf.yaml` と `update-username-perf.yaml` を `modes: [perf]` で書く。Claude は、置き換えの spec の測り方で2つの操作の応答の時間を測り、結果を `progress.md` の決まりのとおりに書く。
  - 完了の確かめ方: `make compat-perf` が2つの操作を測り、`progress.md` に結果が書かれる。6つ目の大きなまとまりの最後のタスクなので、完了条件の2つ目のとおり `/verify-backend` も通る
  - 受入基準とテストの対応: 要件5の受入基準5(利用者の情報を見ることと、名前を変えることの応答の時間を測る)は、`make compat-perf` の `TestPerf_` の検査の結果で確かめる
  - _要件: 5.5_

- [ ] 7. API の説明画面で確かめて進み具合を書く
- [ ] 7.1 API の説明画面で利用者の情報を確かめる

  Claude は、この作業フォルダの最上位から compose の `backend-go` を作り直して起動し、この作業フォルダのコードを動かす。Claude は、Go 版の `registerUser` と `verifyEmail` の操作で利用者を作る。確認のリンクの値は、開発環境の LocalStack の SES が受けたメールから読む。Claude は、API の説明画面での確認の節のとおりに、開発環境の compose の `api-docs`(ポート 8082)を Playwright で開いて確かめ、結果を PR の本文に書く準備をする。
  - 完了の確かめ方: 作った利用者での `POST /api/auth/login` の「Try it out」が 200 を返し、そのあとの `GET /api/users/me` の「Try it out」が、200 と、作った利用者の ID とメールアドレスと名前を持つ利用者の情報を返す
  - 受入基準とテストの対応: 要件6の受入基準1(ログインした開発者の情報を返す)は、`GET /api/users/me` の「Try it out」の 200 と本文で確かめる
  - _要件: 6.1_

- [ ] 7.2 進み具合の表と試作の記録を書き足す

  Claude は、このタスクで、次の4つをする。

  1. `progress.md` のまとまりの表の利用者の行の状態の列を「作り終えた」にする。状態の列を「作り終えた」にすると、筋書きに出てくる操作が足りているかを確かめる検査が、利用者の7つの操作がすべて `group: 2` の筋書きに出てくることを求め始める
  2. 表の下の、API の説明画面での確認の決まりを、進み具合の表の節のとおりに書き直す
  3. 実装で確かめた Java 版の動きを、research.md に書き足す
  4. 状態の列を「比べる検査に通った」にする作業が残ることを、PR の本文に書く

  Claude は、状態の列を「比べる検査に通った」にすることを、このタスクで扱わない。Claude は、この spec の PR の CI で Java 版と Go 版を比べる検査が通り、この spec の PR がマージされたあとに、小タスク7.3 の別の PR で状態の列を書き換える。この spec の PR は、小タスク1.5 の `backend/.golangci.yml` の変更を所有者が承認し、必須のチェックがすべて通ると、自動でマージされる。所有者が承認する時と CI が終わる時の、どちらが先かは決まっていない。所有者が先に承認していれば、この spec の PR は CI が通るとすぐにマージされるので、Claude には、CI が通ったあとにこの spec の PR の中で状態の列を書き換える機会が無い。
  - 完了の確かめ方: `progress.md` の利用者の行が、spec の列に `.kiro/specs/backend-go-users`、状態の列に「作り終えた」を持ち、表の下の決まりと research.md の書き足しが、この小タスクの文のとおりになっている。`go test -tags compat -run TestCoverage_Operations ./compat/` が通る。この spec の PR に入れる最後のタスクなので、完了条件の2つ目のとおり `/verify-backend` も通る
  - 受入基準とテストの対応: 要件7の受入基準3(進み具合の表に、この spec の場所とまとまりの状態を書く)は、`progress.md` の文で確かめる。要件7の受入基準1と2(設計の前に試しに作り、同じにできない動きが見つかれば止まる)は、research.md の試作の記録と書き足しで確かめる。この3つの受入基準を確かめるテストは無い。利用者の7つの操作が Java 版と Go 版を比べる検査の筋書きに出てくることは、`compat_test.go` の `TestCoverage_Operations` で確かめる
  - _要件: 7.1, 7.2, 7.3_

- [ ] 7.3 この spec の PR のマージのあとに、進み具合の表を「比べる検査に通った」にする PR を出す

  Claude は、`/ship` で、この spec の PR がマージされたことを確かめる。この spec の PR は、Java 版と Go 版を比べる検査を含む必須のチェックがすべて通ったときにだけマージされる。Claude は、マージを確かめたあと、同じ会話で、main から新しい featureブランチを作り、`progress.md` のまとまりの表の利用者の行の状態の列を「比べる検査に通った」にして、`/ship` で PR を出す。
  Claude は、その PR を出す前に、認証の行の状態の列も同じ PR で「比べる検査に通った」にするかを、所有者に尋ねる。認証の行は、認証の spec の PR がマージされたあとも「作り終えた」のまま残っているためである。
  - 完了の確かめ方: 出した PR がマージされ、main の `progress.md` の利用者の行の状態の列が「比べる検査に通った」になっている
  - 受入基準とテストの対応: 要件7の受入基準3のうち、Java 版と Go 版を比べる検査に通ったら状態を「比べる検査に通った」にすることは、main の `progress.md` の文で確かめる。これを確かめるテストは無い
  - _要件: 7.3_
  - _依存: 7.2_

## 実装のメモ

- Claude は、途中のタスクのテストを、`bash .claude/scripts/parallel/run-check.sh backend-go <コマンド>` の形で流す。タスクの「完了の確かめ方」の `go test` と `make` のコマンドは、この `<コマンド>` にあたる。Claude は、`go test` を、`backend/` を作業の場所として流す
- `backend/compat/` の下のファイルは、すべて `//go:build compat` を持つ。Claude は、Java 版と Go 版を比べる検査を広げる5つ目の大きなまとまりと、利用者の操作の筋書きで Java 版と Go 版を比べる6つ目の大きなまとまりで新しく作る `harness/multipart.go` とテストにも、同じビルドタグを付ける。`/verify-backend`(`make check`)は、これらのテストを流さない
- `internal/users` の結合テストは、ビルドタグを持たず、`make test` と CI の Go 版の検査で毎回動く。偽の AWS のパッケージは `//go:build compat` を持つので、`internal/users` の結合テストは、偽の AWS をパッケージとして読まず、`backend/compat/fakeaws/Dockerfile` から組み立てたコンテナとして起動する
- Claude は、`make compat` `make compat-cross` `make compat-perf` を、新しい欄を3つの動かし方につなぐ小タスク5.7 と、筋書きを書く6つ目の大きなまとまりのタスクでだけ流す。どれも Java 版と Go 版のイメージを組み立てるので、1回に長い時間がかかる
- この PC の `keirekipro.parallelSlots` は1である。Claude が、テストの対象のコードを壊して確かめるための写しで `run-check.sh` を同時に流すと、2つ目以降の `run-check.sh` は、順番待ちの表示だけを出して終わり、テストを流さない。Claude は、写しを1つずつ、`run-check.sh --wait` で流す
- golangci-lint の gosec は、名前に cred、pass、pwd、secret、token などを含む文字列の定数を、秘密の値として止める(G101)。`.golangci.yml` は `nosec: true` なので、gosec は、`#nosec` の注釈を書いた箇所も止める。Claude は、文言の定数にそれらを含まない名前を付け、テストのファイルは `fs.ReadFile(os.DirFS(<置き場>), <名前>)` で読む
- gosec は、`Secure` `HttpOnly` `SameSite` を付けない `http.Cookie` の値を止める(G124)。Claude は、テストの要求に Cookie を付けるときは `r.Header.Add("Cookie", "名前=値")` と書く
- Claude のツールの引数は、逆斜線と u と4桁の16進の並びを、その並びが表す文字に変えてしまう。Claude は、この並びをファイルに書くときは、perl の置き換えで逆斜線を `\x5c` と書き、日本語を含む置き換えには perl を使わない。結合する文字は、Go のテストでは文字の番号で書く
- LocalStack の SES が受けたメールは、`curl localhost:4566/_aws/ses` で JSON として読める。
- Java 版の CSRF の検査を通すため、Claude は、先に GET の要求で `XSRF-TOKEN` の Cookie を受け取り、書き込みの要求の `X-XSRF-TOKEN` のヘッダに同じ値を入れる。CSRF の検査は、ほかのサイトから送られた偽の要求を断る検査である
- 認証の spec の `passwordreset.go` の `ResetPassword` は、トランザクションの中で `BumpTokenVersion` にトランザクションの問い合わせを渡し、続けて `removeAllRefreshTokens` を呼ぶ。小タスク3.8 の退会も、同じ形で世代の番号を上げる
- 小タスク1.2 で、design.md の「本文を読む中間処理と multipart の読み方」の節で Java 版の答えで確かめると決めた3つの要求の答えが、`internal/httpapi/testdata/multipart/java-checks/cases.json` に入った。design.md は「食い違えば Java 版に合わせる」と決めているので、小タスク2.4 と3.7 は、次の Java 版の答えに合わせる
  - `username` が URL の問い合わせと本文の両方にあるとき、Java 版は、本文の値を先に、問い合わせの値を後に並べて `,` でつなぐ(問い合わせが `問い合わせ`、本文が `本文` のとき、保存した名前は `本文,問い合わせ`)。design.md の手順4の「問い合わせ、本文の順」とは逆である
  - `profileImage` をファイルの名前の無い文字の部分で送ると、Java 版は、画像が無い要求として 200 で答え、画像を置かない
  - `Content-Type` の無い画像の部分を送ると、Java 版は、500 と「予期せぬエラーが発生しました。」で答え、画像を置かない。この要求は、design.md が Java 版の答えで確かめると名指しした3つの1つなので、「変えた動きの一覧の項目」の節の最後の箇条(実装で見つけたほかの形の誤った要求に項目を足す決まり)にはあたらない。Go 版も、500 と「予期せぬエラーが発生しました。」で答え、画像を置かない。変えた動きの一覧には項目を足さない
- 小タスク1.2 の Java 版の答えでは、UTF-8 のサロゲートの範囲の3バイト(`ED A0 80` と `ED BF BF`)を、Java 版は U+FFFD の1つに置き換える。3バイトの冗長な形(`E0 80 80`)は3つに置き換える。小タスク2.1 は、`internal/httpapi/testdata/jdkutf8/cases.json` の28通りのすべてと同じ結果にする
- 小タスク1.5 の `internal/users/errors.go` は、Java 版のユースケースと `User` と要求の型の注釈の文言だけを持つ。メールアドレスとパスワードの設定で、ほかの利用者が使っているメールアドレスを断る文言「このメールアドレスは登録できません。」は、Java 版のドメインのサービス `UserEmailDuplicationCheckService` の文言である。Claude は、この文言に、認証の spec が公開した `auth.MessageEmailNotRegistrable` を使う
- 小タスク1.6 で、偽の AWS の `fakeaws.go` の `ServeHTTP` は、`ServeMux` に渡す前に、URL のパスから置き場所の名前と画像の名前を取り出し、`r.SetPathValue` で要求に入れる。`s3.go` の処理は、今までどおり `r.PathValue` で、その取り出した名前を読む。そのため、`s3.go` は変えていない
- 小タスク1.7 の `internal/users/main_integration_test.go` は、Postgres への接続の束 `testPool`、Valkey の「ホスト:ポート」`testRedisAddr`、偽の AWS の URL `testAWSEndpoint`、置き場所の名前 `testBucket` と、本番と同じ `awsclient.New` で S3 のクライアントを作る `newTestS3` を持つ。小タスク3.2 と3.4 から3.9 の結合テストは、これらを使う
- Java の動きを写した Go のコードは、本物の Java と突き合わせられる。Claude は、`backend/build/` の下(git が無視するフォルダ)に Java の1つのファイルのプログラムを置き、`bash .claude/scripts/parallel/run-check.sh --wait backend sh -c 'java build/<フォルダ>/<名前>.java'` で動かして答えをファイルに書かせ、Go の一時のテストで読んで比べる。比べ終えたら、一時のテストと `backend/build/` の下のファイルを消す。小タスク2.1 は、この形で30万通りのバイト列を比べ、すべて一致した
- Go の `strings.Builder.WriteRune` は、サロゲートの範囲の字を U+FFFD にして書く。そのため、`jdkutf8.go` は、3バイトの字がサロゲートの範囲かを自分で調べない
- Java 版の Spring は、`ContentDisposition.parse` の結果のうちファイルの名前だけを使う。部分の名前は、Tomcat の `Part.getName()` が Tomcat の読み方で読んだものである(`StandardMultipartHttpServletRequest.parseRequest`)。小タスク2.3 と2.4 は、部分の名前の端の場合(項目の名前の大文字と小文字、引用符の無い値の逆スラッシュ、`form-data` で始まらない見出し)を Java 版の答えで確かめ、食い違えば Java 版に合わせる。Spring は、すべての部分で `ContentDisposition.parse` を呼び、例外を `MultipartException` にする。そのため、どれか1つの部分で `parseContentDisposition` が誤りを返せば、要求の全体を誤りとして扱う。そのときの Java 版の状態の番号も、小タスク2.4 で Java 版の答えで確かめる
- 小タスク2.2 の `contentdisposition.go` は、RFC 2047 の書き方(`=?文字コード?B?…?=`)の文字コードを、UTF-8 と ISO-8859-1 と US-ASCII と、その JDK の別名に限り、ほかの文字コード(`Shift_JIS` など)を誤りにする。Java 版は、JDK が読める文字コードなら解いて受け付ける(research.md の P4 の節)。この違いは、Java 版が 200 で答え、Go 版が受け付けない違いなので、変えた動きの一覧に項目を足す小タスクの「Java 版の 500 を Go 版の 400 にする」決まりには当たらない。Claude は、変えた動きの一覧に項目を足す小タスクで所有者に項目の一覧を示すときに、この違いも示し、項目を足すかを所有者に決めてもらう。PR の本文にも書く
- 小タスク2.3 の `multipart.go` は、Java 版の Tomcat 11.0.27 の fileupload(`FileUploadBase` `MultipartStream` `ParameterParser` `MimeUtility` `RFC2231Utility`)を写した。Claude は、本物の `tomcat-embed-core` の `FileUpload` に、Spring Boot と同じ上限(部分の中身と本文の全体が 2097152 バイト、部分の見出しが 512 バイト、部分の数が 50)を付けて、乱数で作った本文を合わせて50万通りと、決めた本文68通りを渡し、答えを比べた。食い違いは、次の1つの種類だけだった
  - 部分の見出しの項目(`name` `filename` と、入れ子の `multipart/mixed` の `boundary`)の RFC 2047 と RFC 2231 の書き方の文字コード。Go 版は、小タスク2.2 と同じく、UTF-8 と ISO-8859-1 と US-ASCII のほかの文字コードを誤りにする。Java 版は、JDK が読める文字コード(`Shift_JIS` など)なら解いて受け付け、名前の形は正しいが JDK が知らない文字コードなら、解かずにそのままの値を使う。Go 版は、この2つ目の場合も誤りにする。Claude は、この違いを小タスク2.2 の違いと一緒に所有者に示す
  - Tomcat は、multipart の本文を読めないとき、どの誤りでも例外を投げ、Spring はそれを `MultipartException` にする。そのため、Java 版は 500 で答えるはずである。小タスク2.4 は、この状態の番号を Java 版の答えで確かめる
  - Tomcat の `Request.parseParts` は、部分の数の上限を、`maxParameterCount`(1000)から URL の問い合わせの項目の数を引いた数と、`maxPartCount`(50)の小さいほうにする。`parseMultipart` は 50 だけを見る。小タスク2.4 は、問い合わせの項目が 950 を超える要求を扱うかを決める
  - Tomcat の `Request.parseParts` は、ファイルの名前の無い部分ごとに、解いたあとの名前と中身のバイト数に2を足して合計し、`maxPostSize`(Spring Boot の `server.tomcat.max-http-form-post-size`、既定は 2MB)を超えると例外を投げる。部分の名前を RFC 2047 の書き方で送ると、解いたあとのバイト数が本文の中のバイト数より大きくなるので、2MB に近い本文では Java 版だけが誤りになりうる。小タスク2.4 は、部分の数の上限と一緒に、この検査を写すかを決める
- 小タスク2.4 は、問い合わせの項目の数の上限と、Tomcat の合計の上限の検査を、どちらも写した。中間処理は `users.go` の `updateUserInfoMiddleware` で、受け口は `updateUserInfoFormFrom(ctx)` で読んだ項目を受け取る。小タスク4.2 は、`server.go` の中間処理の並びにこの中間処理を足す。`Content-Type` の無い画像では、中間処理は `errImageWithoutContentType` を返し、生成したコードの `ResponseErrorHandlerFunc` が 500 と「予期せぬエラーが発生しました。」で答える。空の `Content-Type` の画像は、空の文字列のまま受け口に渡すので、小タスク3.1 の画像の検査が断る
- 小タスク2.4 で、Java 版が 500 で答え、Go 版が 400 で答える要求が、design.md が名指しした4つのほかに7つ見つかった。要求の一覧は research.md の「小タスク2.4 の実装」の記録にある。変えた動きの一覧に項目を足す小タスクは、要求ごとに1つの項目を足す
- 小タスク3.1 の `ImageInput` は `image.go` にある。`internal/users` のテストのファイルは、`image/png` `image/jpeg` `image/gif` を読み込まない。読み込むと、テストの中でその形式が登録され、`image.go` が形式を読み込み忘れてもテストが通るためである。小タスク3.7 のテストも、PNG は `image_test.go` の `pngBytes` で組み立て、JPEG と GIF は `testdata/images` の見本のファイルを読む。`checkImage` のテストの端の場合(PNG のあとに 0 を足した 1048576 バイトの画像、途中で切れた PNG と JPEG と GIF、`BM` で始まる 66 バイト、ASCII でない字の拡張子)は、本物の Java の `ImageIO` と `toLowerCase` の答えと同じだった。手で組み立てた4つの画像(外枠と1枚目の絵の大きさが違う2つの GIF と、2つの4色の JPEG)では、答えが違った。違いの中身は research.md の「小タスク3.1 の実装」の記録にある。変えた動きの一覧に項目を足す小タスクは、所有者に項目の一覧を示すときに、この4つも示し、項目を足すか、Java 版に合わせる直しをするかを所有者に決めてもらう。PR の本文にも書く
- 小タスク3.2 の `objectstore.go` は、画像を置く処理 `put` と消す処理 `delete` と署名付きの URL を作る処理 `presign` を、`Service` のメソッドとして持つ。`presign` は、資格情報を取るために、名前と時間のほかに `context.Context` を受け取る。署名の時刻は `Deps.Now` である。`testdata/presign/PresignExpected.java` を動かすには、AWS SDK for Java の jar のほかに、`reactive-streams` と `slf4j-api` の jar を `--class-path` に並べる。動かし方は、ファイルの先頭の注釈にある
- 小タスク3.3 の `ValidateSetEmailAndPassword` は、項目 `password` を省いた本文を空の文字列の本文と同じに検査する。そのため、`password` を省き、空でない `confirmPassword` を送った要求には、Go 版だけが項目 `confirmPassword` に一致の文言を足す。Java 版の `@PasswordMatches` は、`password` が null のとき通すためである。Claude は、変えた動きの一覧に項目を省いた要求の違いを書くとき、この場合も名前を挙げて書く
- 小タスク3.4 の `provider.go` は、Java 版の `LocalDateTime.now()` と同じ見た目の今の時刻を返す `javaNow` と、東京の時間帯 `javaZone` を持つ。小タスク3.7 から3.9 で `updated_at` を書くときも、これを使う。経路の名前を小文字にする `asciiLower` は `image.go` にある。`provider_integration_test.go` は、利用者の行を作る `insertUser`、読む `loadUser`、時刻の見本 `oldStamp` と `testNow`、`testNow` を東京の時刻の見た目にする `javaWallClock`、`pgtype.Text` を作る `someText` を持つ。小タスク3.5 から3.9 の結合テストも、これらを使う
- 小タスク3.5 の `emailverification_integration_test.go` は、送ったメールを記録する偽の SES `recordingSES`、本物の認証の `Service` と Valkey をつないだ組 `newVerificationEnv`、リンクの JWT の中身を読んで目的と宛先と利用者を確かめる `wantLink`、400 の業務の誤りを確かめる `wantBusinessError` を持つ。小タスク3.8 と3.9 の結合テストも、これらを使う。`insertUser` は、メールアドレスには利用者の ID を前に付けるが、設定待ちのメールアドレスには付けないので、テストは設定待ちのメールアドレスを利用者ごとに変える。認証の `VerifyEmail` は、メールアドレスをすでに持つ利用者の設定待ちのメールアドレスを、「設定待ちのメールアドレスが無いため確認できません。」で断る。そのため、そういう利用者のリンクは、`VerifyEmail` を呼ばずに `wantLink` で確かめる
- 小タスク3.6 の `userinfo.go` の `UserInfo` は、JSON の名前を持たない Go の型である。小タスク4.1 は、受け口の応答の型にこの10の項目を同じ順で写す。nil のポインタは null に、空の並びは `[]` にする。値の有無で文字の列のポインタを作る `textPointer` も `userinfo.go` にある。`userinfo_integration_test.go` は、偽の AWS につなぐ `userInfoService` と、利用者の行を読んで変えて書き戻す `changeUser` を持つ。役割 ADMIN の利用者は2段階認証を使う設定でないと読めないので、テストは ADMIN を足す前に2段階認証を使う設定にする
- 小タスク3.7 の `update.go` は、名前の前後の空白を除いて長さを確かめる `normalizeUsername`、画像の名前を作る `profileImageKey`、役割 ADMIN を持つかを返す `isAdmin` を持つ。`update_integration_test.go` は、どの項目の 400 の入力の誤りも確かめる `wantInputErrors`、偽の AWS の置き場所から画像を読む `storedObject`、2段階認証を使う設定の管理者を作る `adminUser` を持つ。小タスク3.8 の退会で画像が消えたかを確かめるときも、`storedObject` を使う。4.1 の受け口は、Java 版の受け口と同じく、`UpdateUserInfo` のあとで `GetUserInfo` を呼んで答える
- 小タスク3.8 の `delete.go` の `DeleteUser` は、1つのトランザクションの中で、11の表の行を消し、画像を消し、世代の番号を上げ、ログインを続けるための値を消し、確認の済んだメールアドレスへメールを送る。`delete_integration_test.go` は、8つの表に履歴書の行を1行ずつ足す `insertAccountRows`、11の表の行の数を確かめる `wantAccountRows`、本物のログインで2つの値を作る `login`、Java 版の形で Redis のキーを組み立てる `sessionKeys`、世代の番号の行を足す `insertTokenVersion` を持つ。小タスク3.9 のパスワードの変更のテストは、これらを使える。4.x の退会の受け口は、204 と、Cookie を消す2つの `Set-Cookie` で答える
- 小タスク3.9 の `password.go` の `ChangePassword` は、Java 版と同じくトランザクションを使わず、`SetEmailAndPassword` は1つのトランザクションの中で動く。4.x の受け口は、パスワードの変更には 204 で、メールアドレスとパスワードの設定には `GetUserInfo` の結果の 200 で答える。`password_integration_test.go` は、パスワードが合うかを確かめる `wantPhrase`、居ない利用者の 401 を確かめる `wantUserGone`、パスワードと `updated_at` と設定待ちのメールアドレスだけが変わったことを確かめる `wantPhraseChanged`、パスワードだけを持つ利用者を作る `phraseOnlyUser`、Google の連携だけを持つ利用者を作る `googleOnlyUser`、利用者ごとに違うメールアドレスを作る `newAddress` を持つ
- テストの対象のコードを壊した写しで、変数を使う唯一の箇所を消すと、Go は使わない変数を誤りにしてビルドが通らない。Claude は、条件を `x || true` のように書き換えて壊す
- 小タスク4.1 の `users_test.go` は、利用者の処理の偽物 `fakeUsers`(呼ばれた操作と引数を記録し、操作の名前ごとに決めた誤りを返す)、ログインした context を作る `loggedIn`、本文を読んだ結果を入れる `withForm`、7つの操作を並べた `userOps`、消す Cookie の文字列 `deleteSessionCookies` を持つ。小タスク4.2 と5.x のテストは、これらを使える。
- 小タスク5.2 の `harness/multipart.go` は、筋書きの `file` の部分に `filename` が無ければファイルの名前を送り、`content_type` が無ければ部分の `Content-Type` を送らない。文字の部分の値の `{名前}` は置き換える。`request.body_file` の本文には `Content-Type` を付けないので、筋書きは `request.headers` に `Content-Type` を書く。テストの `multipart_test.go` は、受けた要求の本文の全体を記録するサーバ `bodyServer` と、画像のファイルを読む `imageFixture` を持つ

## 完了条件(全タスク共通)

Claude は、どのタスクでも、タスクの箇条書きの欄を書いたうえで、次の4つを満たしたときにタスクを完了とする。

1. Claude は、タスクが満たす requirements.md の受入基準(要件の番号付きの項目)ごとに、それを確かめるテストのファイル名とテスト名を「受入基準とテストの対応」の行に書く。Claude は、確かめるテストの無い受入基準を残さない。
2. タスクで変えたファイルを使うテストが、すべて成功している。`1.` や `2.` の見出しのタスクを大きなまとまりと呼ぶ。大きなまとまりの最後のタスクでは、加えて、そのまとまりのタスクで変えた領域の verify のスキル(`/verify-frontend` `/verify-backend` `/verify-terraform`)が、すべて成功している。
3. Claude は、テストを飛ばす設定、アサーションの削除、カバレッジや lint の対象からの除外を足して、完了条件を満たしたように見せない。CI の escape-hatch の検査が、これらの追加を機械で見つける。
4. Claude は、新しく書いたテストについて、テストの対象のコードを一時的に壊してテストが失敗することを確かめる。Claude は、新しいテスト1件につき1か所だけを、作業フォルダの外の写しで壊し、そのテストだけを流す。壊した写しの作り方と流し方は、`.kiro/steering/tech.md` の「テストの完全性」に従う。
