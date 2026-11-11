# タスク

- [x] 1. 認証の処理の土台を作る
- [x] 1.1 依存と設定とメールのひな形の埋め込みを足す

  Claude は、golang-jwt v5.3.1 を Go 版の依存に足し、google/uuid を直接の依存に変える。Claude は、設定に `App.ApplicationName`(値 `keirekipro`)を足し、Java 版のメールのひな形4つを Go 版に埋め込む `mailtemplates.go` と、埋め込んだひな形から4つのファイル名が読めることを確かめる `mailtemplates_test.go` を作る。Claude は、`docker/backend-go/Dockerfile.prod` の組み立ての段に、`mailtemplates.go` と `src/main/resources/mail` をコピーする手順を、`migrations.go` とマイグレーションのファイルをコピーする手順の隣に足す。この変更は、イメージに入れるファイルを足すだけで、本番の設定の変更ではない。
  - 完了の確かめ方: `go test ./internal/platform/config/ .` が通り、埋め込んだひな形から4つのファイル名が読める。作業フォルダの最上位で、`docker build -f docker/backend-go/Dockerfile.prod backend` が通る
  - 受入基準とテストの対応: この小タスクは土台であり、受入基準を直接は確かめない。要件1の受入基準5(メールの件名と本文)は、小タスク3.2 の `mail_test.go` の `TestMail_FourKindsMatchJava` と、小タスク6.2 で書く `register.yaml` と `email-verification.yaml` の筋書きで確かめる
  - _要件: 1.5_

- [x] 1.2 ログインした利用者の受け渡しを作る

  Claude は、ログインした利用者の ID と役割を `context` に入れて取り出す `authctx` を作る。ほかのまとまりのパッケージは、`authctx` を呼び出して利用者の ID を得る。
  - 完了の確かめ方: `authctx_test.go` の、入れた ID と役割を取り出せる場合と、入れていない `context` で `UserID` が `false` を返す場合が通る
  - 受入基準とテストの対応: 要件2の受入基準4(ほかのまとまりは検査を作り直さず使う)は、`authctx_test.go` の `TestWithAndUserID` と、2.3 の `middleware_test.go` の `TestRequireLogin_PassesAuthctxUser` で確かめる
  - _要件: 2.4_

- [x] 1.3 認証の操作の SQL の問い合わせを書いて生成する

  Claude は、認証の操作が `users` `roles` `user_roles` `user_auth_providers` `user_token_versions` を読み書きする問い合わせを `auth.sql` に書き、sqlc でコードを生成する。Claude は、確認の済んでいるかの列と、V7 のマイグレーションで足した列の書き方を、Java 版の MyBatis の問い合わせと `EmailVerificationCompletion` の問い合わせで確かめてから書く。
  - 完了の確かめ方: `make generate` が `sqlcgen` に認証の問い合わせのコードを生成し、`make generate-check` が通る
  - 受入基準とテストの対応: この小タスクは土台であり、受入基準を直接は確かめない。要件4の受入基準1と2(版の間で記録を互いに読める)は、6.6 の版をまたいで確かめる検査で確かめる
  - _要件: 4.1, 4.2_

- [x] 1.4 認証の処理の入口と誤りの型と乱数を作る

  Claude は、`internal/auth` に、次の3つを作る。1つ目は、認証の処理の入口 `Service` と、部品の束 `Deps` と、組み立ての関数 `New` である。2つ目は、操作の誤りの型 `Error` と、Java 版の文言の定数である。3つ目は、32バイトの乱数の base64url の値と6桁の確認のコードを作る関数である。Claude は、`Error` の部品の節の5つの答えの形を `Error` の項目で表せるようにする。
  - 完了の確かめ方: `go test ./internal/auth/ -run 'TestError|TestRandom'` が通る
  - 受入基準とテストの対応: 要件3の受入基準6(アカウントが無いのかパスワードが違うのかを見分けられない)は、`errors_test.go` の `TestError_LoginFailureMessageIsSingle` と、3.7 の `login_integration_test.go` の `TestLogin_NoAccountAndWrongPasswordSameError` で確かめる。要件1の受入基準4(エラーの文言)は、`errors_test.go` の `TestError_MessagesMatchJava` で確かめる。500 と 403 の文言が、置き換えの spec の土台の文言と重ならないかも、このテストで確かめる
  - _要件: 1.4, 3.6_

- [x] 1.5 Redis の JSON の読み書きと結合テストの土台を作る

  Claude は、Java 版の `RedisConfig` と同じ JSON の形で Redis に書いて読む `redisjson.go` を作る。Claude は、`internal/auth` の結合テストのための `TestMain` を作る。`TestMain` は、testcontainers-go で Postgres と Valkey を起動し、`backend.Migrations()` を `migrate.Run` の `Apply` で流して表を作る。Claude は、結合テストのファイルを `_integration_test.go` で終わる名前にし、そのファイルにビルドタグを付けない。
  - 完了の確かめ方: `go test ./internal/auth/ -run TestRedisJSON` が、Postgres と Valkey のコンテナを起動して通る
  - 受入基準とテストの対応: 要件4の受入基準1と2(版の間で記録を互いに読める)のうち値の形は、`redisjson_integration_test.go` の `TestRedisJSON_MatchesJackson`(`<` `>` `&` を置き換えない場合を含む)で確かめる
  - _要件: 4.1, 4.2_

- [x] 1.6 Cookie の書き方を作る

  Claude は、Java 版の `CookieUtil` と同じ文字列で `Set-Cookie` の値を作る4つの関数を作る。Claude は、属性の順と `Secure` を置く位置を、Java 版の応答の文字列で確かめる。
  - 完了の確かめ方: `go test ./internal/auth/ -run Cookie` が、4つの関数の `Secure` の有無ごとの場合で通る。1つ目の大きなまとまりの最後のタスクなので、完了条件の2つ目のとおり `/verify-backend` も通る
  - 受入基準とテストの対応: 要件1の受入基準1(同じ Cookie の名前と性質)は、`cookies_test.go` の `TestSessionCookie` `TestChallengeCookie` `TestDeleteCookie` `TestExpiredAccessTokenCookie` で確かめる
  - _要件: 1.1, 2.2_

- [x] 2. ログインの状態を確かめる仕組みを作る
- [x] 2.1 安全のヘッダの中間処理を作る (並行可)

  Claude は、Spring Security と同じ6つのヘッダを、次の処理に渡す前に応答に置く中間処理を作る。
  - 完了の確かめ方: `go test ./internal/httpapi/middleware/ -run TestSecurityHeaders` が通る
  - 受入基準とテストの対応: 要件1の受入基準1(Java 版と同じ答え)のうちヘッダは、`securityheaders_test.go` の `TestSecurityHeaders_OnAllStatuses`(200、404、403、500)と `TestSecurityHeaders_HandlerOverrideKept` で確かめる。ほかの中間処理が返す応答にもヘッダが付くことは、4.4 の `TestNew_SecurityHeadersOnAllResponses` で確かめる
  - _要件: 1.1_
  - _対象の部品: SecurityHeaders_

- [x] 2.2 ログインの状態の値を作る

  Claude は、Java 版の `JwtProvider` と `UserTokenVersionStore` を写し、ログインの状態の JWT の発行と検証と、ログインの状態の世代の番号の読み書きを作る。データベースを読むテストは `accesstoken_integration_test.go` に、データベースを読まないテストは `accesstoken_test.go` に置く。
  - 完了の確かめ方: `go test ./internal/auth/ -run TestAccessToken` が通る
  - 受入基準とテストの対応: 要件3の受入基準1(有効な時間)は `accesstoken_integration_test.go` の `TestAccessToken_ExpiresIn10Minutes` で確かめる。要件2の受入基準2(期限切れ、書き換え、使えなくなった値を断る)は、`accesstoken_test.go` の `TestAccessToken_RejectsExpired` `TestAccessToken_RejectsBadSignature` `TestAccessToken_RejectsAlgNone` `TestAccessToken_RejectsNonUUIDSub` と、`accesstoken_integration_test.go` の `TestAccessToken_RejectsOldVersion` で確かめる。要件4の受入基準1(版をまたいでログインし続けられる)のうち値の形は、`accesstoken_integration_test.go` の `TestAccessToken_HeaderAndClaims` で確かめる
  - _要件: 2.2, 3.1, 4.1_

- [x] 2.3 値を読む段とログインを求める段を作る

  Claude は、Java 版の `JwtAuthenticationFilter` にあたる `Identify` と、Java 版の `authorizeHttpRequests` にあたる `RequireLogin` の2つの中間処理を作る。`RequireLogin` は、`/api/admin/` の下の 403 の応答の `Content-Type` を、Java 版の `accessDeniedHandler` と同じ `application/json;charset=UTF-8` にする。`Identify` は、データベースが読めないときに、要求を次の処理に渡さず、状態の番号 500 で答える。Claude は、データベースを読むテストを `middleware_integration_test.go` に、データベースを読まないテストを `middleware_test.go` に置く。
  - 完了の確かめ方: `go test ./internal/auth/ -run 'TestIdentify|TestRequireLogin'` が通る。2つ目の大きなまとまりの最後のタスクなので、完了条件の2つ目のとおり `/verify-backend` も通る
  - 受入基準とテストの対応: 要件2の受入基準1(ログインの状態の無い要求を断る、`OPTIONS` と生きているかの確認は通す)は、`middleware_test.go` の `TestRequireLogin_PublicPathBoundaries`(`/api/auth`、`/api/authx`、`/actuator`、`/healthz`、`OPTIONS`)と `TestRequireLogin_NoUser401` で確かめる。`/api/admin/` の 403 と `Content-Type` は `middleware_test.go` の `TestRequireLogin_AdminForbidden` で確かめる。要件2の受入基準2(無効な値を断り Cookie を消す)は `middleware_integration_test.go` の `TestIdentify_InvalidTokenClearsCookie` で、要件2の受入基準3(利用者が居るかを確かめない)は `TestIdentify_DoesNotCheckUserExists` で確かめる。データベースが読めないときの 500 は `TestIdentify_DBError500` で確かめる。要件6の受入基準2(ログインした要求を処理に渡す)は、`middleware_test.go` の `TestRequireLogin_PassesAuthctxUser` と、Java 版の `JwtProvider` と同じ項目と鍵で作った JWT を Cookie `accessToken` に持つ要求が次の処理に届く、`middleware_integration_test.go` の `TestIdentify_AcceptsJavaIssuedToken` で確かめる
  - _要件: 2.1, 2.2, 2.3, 6.2_

- [x] 3. 認証の操作ごとの処理を作る
- [x] 3.1 要求の入力の検査を作る (並行可)

  Claude は、Java 版の要求の型の注釈を、13の操作ごとの検査の関数に写す。Claude は、`@PasswordMatches` の項目の名前を `PasswordMatchesValidator` で確かめる。
  - 完了の確かめ方: `go test ./internal/auth/ -run TestValidate` が通る
  - 受入基準とテストの対応: 要件1の受入基準4(入力の誤りの条件と文言)は、`validate_test.go` の `TestValidate_Boundaries`(空白だけ、50文字と51文字、UTF-8 の72バイトと73バイト、全角の文字、改行を含むパスワード)と `TestValidate_EmailLikeHibernate` で確かめる。要件5の受入基準5(形の誤った要求)は、小タスク6.5 で書く `validation.yaml` の「形の誤った要求」と、変えた動きの一覧の項目で確かめる
  - _要件: 1.4_
  - _対象の部品: Validate_

- [x] 3.2 メールの送り出しを作る (並行可)

  Claude は、埋め込んだひな形の `${名前}` を差し込み、SES で送る `mail.go` を作る。Claude は、4種類のメールの件名と差し込む値を、Mail の部品の節の表のとおりにする。research.md には、試作で Java 版と一致したことだけが書かれ、比べる正解の文字列は無い。そのため Claude は、開発環境の Java 版に4種類のメールを送らせ、LocalStack の SES が受けたメールの件名と本文を、`internal/auth/testdata/mail/` に正解のファイルとして置く。Claude は、正解のファイルと一緒に、Java 版がそのメールに差し込んだ値を `testdata/mail/` に置く。`TestMail_FourKindsMatchJava` は、同じ値を `mail.go` に渡し、件名と本文の全体を正解のファイルと比べる。確認のリンクと確認のコードと利用者の名前は、送るたびに違うためである。Claude は、2段階認証の確認のコードのメールを、開発環境で2段階認証を有効にした利用者でログインして送らせる。Claude は、登録の完了のメールを、開発環境で登録を最後まで済ませて送らせる。
  - 完了の確かめ方: `go test ./internal/auth/ -run TestMail` が通る
  - 受入基準とテストの対応: 要件1の受入基準5(メールの件名と本文)は、`mail_test.go` の `TestMail_FourKindsMatchJava`(`testdata/mail/` の正解のファイルと比べる)と `TestMail_RejectsOtherTemplateSyntax` で確かめる
  - _要件: 1.5_
  - _対象の部品: Mail_

- [x] 3.3 問い合わせのエスケープを作る (並行可)

  Claude は、URL の問い合わせの部分を Spring の `UriComponentsBuilder.encode()` と同じ規則でエスケープする `spring_query.go` を作る。
  - 完了の確かめ方: `go test ./internal/auth/ -run TestSpringQuery` が通る
  - 受入基準とテストの対応: 要件1の受入基準3(Google か GitHub のログインの開始の URL が Java 版と同じ)は、`spring_query_test.go` の `TestSpringQuery_MatchesSpring`(空白、`+`、`/`、`:`、`!$'()*+,;:@/?`、日本語)で確かめる
  - _要件: 1.3_
  - _対象の部品: OIDC_

- [x] 3.4 ログインを続けるための値を作る

  Claude は、Java 版の `RedisRefreshTokenStore` と `AuthSessionInvalidator` を写し、ログインを続けるための値の発行と読み出しと削除と、利用者のログインの状態をまとめて使えなくする処理を作る。
  - 完了の確かめ方: `go test ./internal/auth/ -run 'TestRefreshToken|TestInvalidateSessions'` が通る
  - 受入基準とテストの対応: 要件3の受入基準1(ログインし直さずに使い続けられる時間)は `refreshtoken_integration_test.go` の `TestRefreshToken_TTL7Days` で、要件3の受入基準5(ほかの端末のログインの状態も使えなくする)は `TestInvalidateSessions_RemovesAllTokens` で確かめる。要件4の受入基準1(版をまたいでログインし続けられる)のうち値の形は `TestRefreshToken_HashFieldsAsJSON` で確かめる
  - _要件: 3.1, 3.5, 4.1_

- [x] 3.5 2段階認証の確認のコードと途中の記録を作る

  Claude は、Java 版の `TwoFactorAuthIssueUseCase` と `TwoFactorAuthVerifyUseCase` の、確認のコードと途中の記録の発行と照合を作る。
  - 完了の確かめ方: `go test ./internal/auth/ -run TestTwoFactor` が通る
  - 受入基準とテストの対応: 要件3の受入基準2(コードの有効な時間と誤りの回数の上限)は、`twofactor_integration_test.go` の `TestTwoFactor_TTL10Minutes` `TestTwoFactor_FifthWrongCodeDeletes` と、誤ったコードで残りの有効な時間が保たれる `TestTwoFactor_WrongCodeKeepsTTL` で確かめる。要件4の受入基準2(途中の手順をまたぐ操作を、版をまたいでも終えられる)のうち途中の記録の形は `TestTwoFactor_ChallengeIsDoubleEncodedJSON` で確かめる
  - _要件: 3.2, 4.2_

- [x] 3.6 登録の途中の記録を作る

  Claude は、Java 版の `PendingRegistrationStore` の Redis の実装を写す。Claude は、`createdAt` の書き方と、集合の要素の形と、メールアドレスで最大5件を読む順を、Java 版が置いた値で確かめてから書く。
  - 完了の確かめ方: `go test ./internal/auth/ -run TestRegistration` が通る
  - 受入基準とテストの対応: 要件4の受入基準2(登録を版をまたいで終えられる)のうち記録の形は、`registration_integration_test.go` の `TestRegistration_RecordShape` と `TestRegistration_FindByEmailMax5` と `TestRegistration_Extend24h` で確かめる
  - _要件: 4.2_

- [x] 3.7 ログインと2段階認証の確認と作り直しとログアウトを作る

  Claude は、`Service` の `Login` `VerifyTwoFactor` `Refresh` `Logout` を、Java 版の `LoginUseCase` と `LogoutController` などが処理を進める順と同じ順で処理を進めるように作る。
  - 完了の確かめ方: `go test ./internal/auth/ -run 'TestLogin|TestVerifyTwoFactor|TestRefresh|TestLogout'` が通る
  - 受入基準とテストの対応: 要件1の受入基準2(ログイン、2段階認証、ログアウトを終えられる)は `login_integration_test.go` の `TestLogin_Success` `TestVerifyTwoFactor_Success` `TestLogout_Success` で確かめる。要件3の受入基準6(アカウントが無いのかパスワードが違うのかを見分けられない)は `TestLogin_NoAccountAndWrongPasswordSameError` で、要件3の受入基準5(ログアウトでほかの端末も使えなくする)は `TestLogout_InvalidatesAllSessions` で、要件3の受入基準1(作り直し)は `TestRefresh_RejectsOldVersion` で確かめる。登録の途中のアカウントの 409 は `TestLogin_PendingRegistration409` で確かめる
  - _要件: 1.2, 3.1, 3.2, 3.5, 3.6_

- [x] 3.8 メールアドレスの確認のリンクと送り直しの制限を作る

  Claude は、Java 版の `JwtEmailVerificationTokenCodec` と `EmailVerificationCurrentTokenStore` と `EmailVerificationMailer` を写し、確認のリンクの値の発行と読み出し、今のリンクの記録、送り直せる間隔の制限、確認のメールの送り出しを作る。
  - 完了の確かめ方: `go test ./internal/auth/ -run 'TestEmailVerificationToken|TestEmailVerificationRate'` が通る
  - 受入基準とテストの対応: 要件3の受入基準3(リンクの有効な時間、新しいリンクで前のリンクが使えない)は、`emailverification_integration_test.go` の `TestEmailVerificationToken_TTLByPurpose` と `TestEmailVerificationToken_NewLinkReplacesOld` で確かめる。要件3の受入基準4(送り直せる間隔)は `TestEmailVerificationRate_60Seconds` で確かめる
  - _要件: 3.3, 3.4_

- [x] 3.9 パスワードの再設定の値の置き場を作る

  Claude は、Java 版の `PasswordResetTokenStore` の Redis の実装を写し、`passwordreset.go` に、再設定の値を `password-reset:<値>` に10分置く処理と、読む処理と、消す処理を作る。3.11 の `VerifyEmail` と 3.12 の再設定の操作が、この置き場を使う。
  - 完了の確かめ方: `go test ./internal/auth/ -run TestPasswordResetToken` が通る
  - 受入基準とテストの対応: 要件3の受入基準3(再設定の値の有効な時間)は、`passwordreset_integration_test.go` の `TestPasswordResetToken_TTL10Minutes` で確かめる。要件4の受入基準2(途中の手順をまたぐ操作を、版をまたいでも終えられる)のうち値の形は、`TestPasswordResetToken_ValueIsUserIDJSON` で確かめる
  - _要件: 3.3, 4.2_

- [x] 3.10 確認のリンクの分類と確認の書き換えを作る

  Claude は、Java 版の `EmailVerificationLinkClassifier` と `EmailVerificationCompletion` を写し、リンクを結果の名前に分類する処理と、目的ごとの書き換えを1つのトランザクションで行う処理を作る。書き換えは、目的が `REGISTRATION` のときの登録の完了、`ACCOUNT_EMAIL` のときの確認済みにする書き換え(Java 版の `User.verifyEmail`)、`PENDING_EMAIL` のときのメールアドレスの付け替え(Java 版の `User.promotePendingEmail`)の3つである。Go 版にはメールアドレスの変更の操作がまだ無いので、`PENDING_EMAIL` の場面は Java 版と Go 版を比べる検査では作れない。Claude は、この場面を結合テストだけで確かめる。
  - 完了の確かめ方: `go test ./internal/auth/ -run TestEmailVerificationComplete` が通る
  - 受入基準とテストの対応: 要件3の受入基準3(1回しか使えない)は、`emailverification_integration_test.go` の `TestEmailVerificationComplete_SecondUseAlreadyVerified` で確かめる。要件4の受入基準2(どちらの版に届いた登録も残る)のうち行の形は、`TestEmailVerificationComplete_RowsInOneTransaction` と `TestEmailVerificationComplete_EmailTaken` で確かめる。目的が `ACCOUNT_EMAIL` の書き換えは `TestEmailVerificationComplete_AccountEmailVerified` で、目的が `PENDING_EMAIL` の付け替えは `TestEmailVerificationComplete_PendingEmailPromoted` と、付け替え先のメールアドレスがほかの利用者に使われているときの `TestEmailVerificationComplete_PendingEmailTaken`(結果 `EMAIL_TAKEN`)で確かめる
  - _要件: 3.3, 4.2_

- [x] 3.11 新規の登録とメールアドレスの確認と送り直しを作る

  Claude は、`Service` の `Register` `VerifyEmail` `ResendEmailVerification` `ResendEmailVerificationForLogin` を、Java 版のユースケースが処理を進める順と同じ順で処理を進めるように作る。`Register` は、メールの送り出しに失敗したら、置いた登録の途中の記録を消してから誤りを返す。`VerifyEmail` は、Java 版の `VerifyEmailUseCase` と同じく、目的が `PASSWORD_RESET` のリンクでは、3.9 の置き場に再設定の値を置き、結果 `PASSWORD_RESET_READY` と再設定の値を返す。
  - 完了の確かめ方: `go test ./internal/auth/ -run 'TestRegister|TestVerifyEmail|TestResend'` が通る
  - 受入基準とテストの対応: 要件1の受入基準2(新規の登録とメールアドレスの確認を終えられる)は、`register_integration_test.go` の `TestRegister_ThenVerifyEmail` で確かめる。要件3の受入基準4(送り直せる間隔)は `TestResend_RateLimited` で、要件3の受入基準3(送り直すと前のリンクが使えない)は `TestResend_OldLinkInvalid` で確かめる。メールの失敗で記録を消すことは `TestRegister_MailFailureRemovesPending` で、目的が `PASSWORD_RESET` のリンクの結果は `TestVerifyEmail_PasswordResetReady` で確かめる
  - _要件: 1.2, 3.3, 3.4_

- [x] 3.12 パスワードの再設定を作る

  Claude は、Java 版の `RequestPasswordResetUseCase` `VerifyPasswordResetTokenUseCase` `ResetPasswordUseCase` を写し、`Service` の `RequestPasswordReset` `VerifyPasswordResetToken` `ResetPassword` を、3.9 の置き場を使って作る。
  - 完了の確かめ方: `go test ./internal/auth/ -run TestPasswordReset` が通る
  - 受入基準とテストの対応: 要件1の受入基準2(再設定のメールを受け取り新しいパスワードでログインできる)は、`passwordreset_integration_test.go` の `TestPasswordReset_ThenLogin` で確かめる。要件3の受入基準3(再設定の値を1回だけ使える)は `TestPasswordReset_TokenSingleUse` で、要件3の受入基準5(ほかの端末のログインの状態を使えなくする)は `TestPasswordReset_InvalidatesAllSessions` で、要件3の受入基準6(アカウントの有無を見分けられない)は `TestPasswordReset_RequestSame204` で確かめる。利用者が居ないときの 401 は `TestPasswordReset_UserGoneClearSession` で確かめる
  - _要件: 1.2, 3.3, 3.5, 3.6_

- [x] 3.13 Google と GitHub のログインの開始を作る

  Claude は、`Service` の `StartOIDC` を作る。`StartOIDC` は、`state` と `code_verifier` を Redis に10分置いて、ログインの開始の URL を作る。Claude は、対象の外の `provider` を受けた Java 版の状態の番号と Redis に残るものを確かめる。Claude は、確かめた結果が要件5の受入基準5の形の誤った要求に当たるときは、`StartOIDC` が Redis に記録を残さずに誤りを返すように作る。
  - 完了の確かめ方: `go test ./internal/auth/ -run TestStartOIDC` が通る
  - 受入基準とテストの対応: 要件1の受入基準3(Java 版と同じ画面に移る)のうち URL の形は、`oidc_integration_test.go` の `TestStartOIDC_URLParamsOrder` で確かめる。要件3の受入基準7(同じブラウザが始めたログインと組になっていることを確かめる)のうち記録の形は `TestStartOIDC_StoresStateFor10Minutes` で確かめる。要件5の受入基準5(対象の外の `provider` を 400 にする)は、400 で答え、Redis に `oidc:` のキーが残らないことを確かめる `TestStartOIDC_UnknownProvider400` で確かめる
  - _要件: 1.3, 3.7, 4.2, 5.5_

- [x] 3.14 Google と GitHub から戻ったあとの処理を作る

  Claude は、`Service` の `HandleOIDCCallback` を作り、コードの交換、利用者の情報の読み出し、GitHub のメールアドレスの一覧の読み出し、アカウントの決め方、失敗したときの文言とエスケープを、OIDC の部品の節のとおりに作る。
  - 完了の確かめ方: `go test ./internal/auth/ -run TestHandleOIDCCallback` が、Google と GitHub の代わりの `httptest` のサーバを相手に通る。3つ目の大きなまとまりの最後のタスクなので、完了条件の2つ目のとおり `/verify-backend` も通る
  - 受入基準とテストの対応: 要件1の受入基準3(ログインが終わったときと失敗したときの移る先と文言)は、`oidc_integration_test.go` の `TestHandleOIDCCallback_NewUser` `TestHandleOIDCCallback_LinkExisting` `TestHandleOIDCCallback_UnverifiedEmail` `TestHandleOIDCCallback_Denied` `TestHandleOIDCCallback_ErrorMessageURLEncoderEscape` で確かめる。要件3の受入基準7(確認済みのメールアドレスだけを使い、`state` の記録が無ければ断る)は `TestHandleOIDCCallback_GitHubPrimaryVerifiedOnly` と `TestHandleOIDCCallback_MissingState` で確かめる
  - _要件: 1.3, 3.7, 4.2_

- [x] 4. 認証の受け口をつなぐ
- [x] 4.1 認証の操作の応答の型と誤りの本文を作る

  Claude は、認証の操作の応答を、Cookie を2つ以上書ける自分で書いた型で返す `authresponses.go` を作る。Claude は、`*auth.Error` を、Error の部品の節の5つの形の本文と状態の番号と Cookie に変える処理を作る。
  - 完了の確かめ方: `go test ./internal/httpapi/ -run TestAuthResponses` が通る
  - 受入基準とテストの対応: 要件1の受入基準1(同じ状態の番号、本文、Cookie)は、`auth_test.go` の `TestAuthResponses_StatusBodyCookies` で確かめる。要件1の受入基準4(エラーの文言)のうち本文の形は、`TestAuthResponses_ErrorBodies`(400、409 の `kind`、401 の Cookie の削除)で確かめる
  - _要件: 1.1, 1.4_

- [x] 4.2 ログインと登録と再設定の11の操作の受け口を作る

  Claude は、`auth.go` に、`login` から `resetPassword` までの、Google と GitHub のほかの11の操作の受け口を作る。受け口は、生成した要求の型から値を取り、`Validate` で検査し、`Service` を呼び、4.1 の応答の型で返す。
  - 完了の確かめ方: `go test ./internal/httpapi/ -run TestAuthHandlers` が通る
  - 受入基準とテストの対応: 要件1の受入基準1と2(画面の操作に Java 版と同じ答え)は、`auth_test.go` の `TestAuthHandlers_LoginNoBody` `TestAuthHandlers_VerifyTwoFactorCookieOrder` `TestAuthHandlers_VerifyTwoFactorNoChallenge400` `TestAuthHandlers_VerifyEmailNullToken` で確かめる。Java 版との突き合わせは、小タスク6.1 から 6.3 で書く `login.yaml` `two-factor.yaml` `refresh-logout.yaml` `register.yaml` `email-verification.yaml` `password-reset.yaml` の筋書きで確かめる
  - _要件: 1.1, 1.2_

- [x] 4.3 Google と GitHub の2つの操作の受け口を作る

  Claude は、`startOidcAuthorization` と `handleOidcCallback` の受け口と、要求の `Host` と `Accept` を `context` に入れる生成したコードの中間処理を作る。Claude は、`Content-Type` を Accept で決める規則と、戻り先の URL の作り方を、認証の受け口の節と処理の流れの節のとおりにする。Claude は、Accept が無い要求、`*/*`、axios の既定、`text/plain`、`application/json`、`*/*, application/json` の6つで、Java 版の `Content-Type` の文字列を確かめ、規則と食い違えば Java 版に合わせる。
  - 完了の確かめ方: `go test ./internal/httpapi/ -run TestAuthOIDCHandlers` が通る
  - 受入基準とテストの対応: 要件1の受入基準3(Java 版と同じ画面に移る)は、`auth_test.go` の `TestAuthOIDCHandlers_ContentTypeByAccept` `TestAuthOIDCHandlers_RedirectURIPort80` `TestAuthOIDCHandlers_CallbackFailure302NoBody` で確かめる
  - _要件: 1.3_

- [x] 4.4 中間処理の順と処理の束ねを変えて起動につなぐ

  Claude は、`httpapi.New` の `Options` に `Identify` と `AuthHandlers` を足し、中間処理の順、受け口の埋め込みの深さ、経路が `/api/auth/` の下の問い合わせの誤りの 400 を、「httpapi.New の変更」の節のとおりにする。Claude は、`main.go` で `Service` を組み立てて渡す。Claude は、Cookie の値の形の誤りが `ErrorHandlerFunc` に届く場面があるかを確かめ、届くなら Java 版の答えとの違いを 6.5 の変えた動きの一覧の候補に控える。
  - 完了の確かめ方: `go test ./internal/httpapi/ ./cmd/...` が通り、`go build ./cmd/keirekipro` が通る。4つ目の大きなまとまりの最後のタスクなので、完了条件の2つ目のとおり `/verify-backend` も通り、カバレッジが下限の 93% に届く
  - 受入基準とテストの対応: 要件2の受入基準1(ログインの要る操作の 401)は、`server_test.go` の `TestNew_RequireLoginBeforeUnimplemented` で確かめる。要件2の受入基準2(偽の送信の検査で断られた要求でも Cookie を消す)は `TestNew_IdentifyBeforeCSRF` で確かめる。要件6の受入基準1(説明画面からログインできる)のうち経路は `TestNew_AuthHandlersShadowUnimplemented` で確かめる。`/api/auth/` の下の問い合わせの誤りの 400 は `TestNew_AuthQueryError400` で確かめる。要件1の受入基準1(Java 版と同じ答え)のうち、偽の送信の検査が返す 403、パニックの受け止めが返す 500、`/healthz` の応答にも安全のヘッダが付くことは、`TestNew_SecurityHeadersOnAllResponses` で確かめる
  - _要件: 2.1, 2.2, 2.4, 6.1_
  - _依存: 2.1, 2.3_

- [ ] 5. Java 版と Go 版を比べる検査を広げる
- [x] 5.1 偽のログインのサービスに断る動きと TLS の受け口と初めに戻す口を足す (並行可)

  Claude は、偽のログインのサービスに、提供元ごとの断る残りの回数を持たせ、`PUT /_compat/deny/{provider}` を受けるたびに1増やし、残りの回数が1以上のときに次のログインの開始を `error=access_denied&state=<state>` で戻して1減らす動きを足す。Claude は、ネットワークの別名 `api.github.com` のポート 443 で TLS を受けて `/user/emails` だけに答える働きを足す。偽のログインのサービスは、起動のときに証明書と鍵のファイルの場所を渡されたときだけ、この働きを始める。証明書と鍵を検査の起動から渡すのは小タスク5.9 である。偽のログインのサービスが、証明書と鍵のファイルの場所を渡されたときだけこの働きを始めるのは、小タスク5.9 より前に偽のログインのサービスを起動する harness のテストも動くようにするためである。Claude は、提供元ごとの利用者の設定と断る残りの回数を初めの状態に戻す口を足す。今の偽のログインのサービスには利用者の設定を消す口が無く、空の値を送ると中身の空の利用者が登録されるためである。
  - 完了の確かめ方: `go test -tags compat ./compat/fakeoidc/...` が通る
  - 受入基準とテストの対応: 要件5の受入基準3(Google か GitHub がログインを断ったとき)を支える動きは、`fakeoidc_test.go` の `TestDeny_CountsDown` で確かめる。`TestDeny_CountsDown` は、偽のログインのサービスが `PUT /_compat/deny/{provider}` を2回受けると、次のログインの開始を2回断り、3回目は通すことを確かめる。GitHub のメールアドレスの読み出しを支える受け口は `TestTLS_UserEmailsOnly` で、証明書と鍵のファイルが渡されないときに TLS を受けずに起動することは `TestTLS_DisabledWithoutCertFiles` で、初めの状態に戻す口は `TestReset_ClearsUsersAndDenyCount` で確かめる
  - _要件: 5.3_
  - _対象の部品: fakeoidc_

- [x] 5.2 段の4つの種類と、段ごとの欄を確認する処理を足す (並行可)

  Claude は、筋書きの段を、版に送る段、絶対の URL の段、Redis を書き換える段、値を期限切れにする段の4種類にする。harness は、筋書きを読むときに、段ごとに種類に要る欄があるかと、ほかの種類の欄が無いかを確かめ、外れた段の名前を誤りとして返す。Claude は、筋書きに `oidc_users` と `prepare_each` の欄を足す。harness は、`prepare_each` が真の筋書きに `measure_memory` があれば、その筋書きを読み込みで断る。Claude は、版をまたいで確かめる検査の筋書きの検査(`validateCross`)を、`to` と `expect.status` を版に送る段にだけ求め、最後の段が版に送る段であることを求める形に変える。
  - 完了の確かめ方: `go test -tags compat ./compat/harness/ -run 'TestScenarioValidate_StepKinds|TestScenario_PrepareEachRejectsMeasureMemory|TestValidateCross_OnlyVersionSteps'` が通る
  - 受入基準とテストの対応: 要件5の受入基準1(リンクや確認のコードを使う要求を筋書きに含める)を支える段の形は、`scenario_test.go` の `TestScenarioValidate_StepKinds` で確かめる。`TestScenarioValidate_StepKinds` は、harness が、4種類の段のそれぞれで、要る欄が無い段と、ほかの種類の欄を持つ段を断ることを確かめる。要件5の受入基準6(主な操作の応答の時間を測る)を支える `prepare_each` の欄の制限は `TestScenario_PrepareEachRejectsMeasureMemory` で、要件4の受入基準3(版をまたいで確かめる検査に筋書きを足し、CI で動かす)を支える版をまたぐ筋書きの形は `TestValidateCross_OnlyVersionSteps` で確かめる
  - _要件: 4.3, 5.1, 5.6_
  - _対象の部品: harness_

- [x] 5.3 値の取り出しと差し込みと Host を広げる

  Claude は、`capture.go` に、本文の全体 `text`、ヘッダ `header:<名前>`、ヘッダの URL の問い合わせの項目 `header:<名前>?<項目>`、応答の `Set-Cookie` の値 `cookie:<名前>`、その段のあとに届いた最後のメールの本文 `mail:<正規表現>` の5つの取り出しの元を作る。Claude は、harness が、`{名前}` の差し込みを、経路に加えて、JSON の本文の文字列の値と、`Cookie` ヘッダを含むヘッダの値にも行うようにする。Claude は、harness が、版に送るすべての要求の `Host` の項目に `compat.test` を入れ、送る先のアドレスを版のポートのままにするようにする。
  - 完了の確かめ方: `go test -tags compat ./compat/harness/ -run 'TestCapture|TestSubstitute|TestSend_HostIsCompatTest'` が通る
  - 受入基準とテストの対応: 要件5の受入基準1(リンクや確認のコードを使う要求を筋書きに含める)を支える取り出しは、`capture_test.go` の `TestCapture_Sources`(5つの元)と、値が無いときと正規表現が当たらないときに段と取り出しの名前で失敗する `TestCapture_MissingFailsWithNames` で確かめる。差し込みは `TestSubstitute_BodyHeaderAndCookie` で確かめる。要件5の受入基準3(Google と GitHub のログインの戻り先を版の間で同じにする)を支える `Host` は、`send_test.go` の `TestSend_HostIsCompatTest` で確かめる
  - _要件: 5.1, 5.3_

- [x] 5.4 絶対の URL の段と Redis を書き換える段を足す

  Claude は、絶対の URL の段を、`request.url` のホストが `fakeoidc` のときにテストの処理から届くアドレスに書き換えて送り、リダイレクトを追わず、`expect.status` があれば状態の番号だけを確かめ、応答を比べない形で作る。Claude は、Redis を書き換える段を、`redis.del` と `redis.set` を、その版の筋書きの値を差し込んだキーと値で、その版の Redis に書く形で作る。Claude は、`stack.go` の偽のサービスの部品に、偽のログインのサービスを初めの状態に戻す処理と、`oidc_users` の利用者を設定する処理を足す。Claude は、3つの動かし方からこの2つの処理を呼ぶようにする変更を、新しい段と取り出しを3つの動かし方につなぐ小タスク5.8 で行う。Claude は、偽のログインのサービスに登録する戻り先を、版ごとの URL から `http://compat.test/api/auth/oidc/callback` に変える。
  - 完了の確かめ方: `go test -tags compat ./compat/harness/ -run 'TestAbsoluteURL|TestRedisStep|TestOIDCUsers|TestStack_RedirectURIIsCompatTest'` が通る
  - 受入基準とテストの対応: 要件5の受入基準1(期限の切れたリンクの要求)を作る段は、`scenario_test.go` の `TestRedisStep_DelAndSetWithVersionValues`(版ごとの値で差し込んだキーを消して置く)で確かめる。要件5の受入基準3(偽のログインのサービスで比べる)を支える段は、`send_test.go` の `TestAbsoluteURL_RewritesHostNoFollow` と、`harness_test.go` の `TestOIDCUsers_ResetAndSet` と `TestStack_RedirectURIIsCompatTest` で確かめる
  - _要件: 5.1, 5.3_
  - _依存: 5.1_

- [x] 5.5 値を期限切れにする段を足す

  Claude は、`expire.go` に、筋書きの中の JWT の値を期限の過ぎた値に書き換えて署名し直す処理を作る。`expire.cookie` を持つ段では、`expire.go` の処理は、Cookie の束のうち `expire.cookie` に書いた名前の Cookie を書き換える。`expire.var` を持つ段では、`expire.go` の処理は、`expire.var` に書いた名前の取り出した値を書き換える。`expire.go` の処理は、2つの JWT を、JWT の項目に `aud` があるかで見分ける。どちらも `alg` は `HS256` なので、`alg` では見分けられない。`expire.go` の処理は、ログインの状態の値では、`iat` を今の11分前に、`exp` を今の1分前にして、`JWT.Secret` の値で署名する。`expire.go` の処理は、メールアドレスの確認のリンクの値では、`lexp` を今の1分前にして、HMAC-SHA256(`JWT.Secret` の値, `keirekipro-email-verification-v1`)で署名する。書き換える値が無いときは、その段の誤りとして筋書きを失敗にする。
  - 完了の確かめ方: `go test -tags compat ./compat/harness/ -run TestExpire` が通る
  - 受入基準とテストの対応: 要件5の受入基準1(期限の切れたリンクの要求を筋書きに含める)を支える段は、`expire_test.go` の `TestExpire_AccessTokenKeepsClaims`、`TestExpire_EmailVerificationLexp`、`TestExpire_MissingValueFails` で確かめる。`TestExpire_AccessTokenKeepsClaims` は、書き換えたログインの状態の値で、`sub` と世代の番号と `jti` が残り、`exp` だけが過去になることを確かめる
  - _要件: 5.1_

- [x] 5.6 確認のコードとリンクの値と文字の本文の正規化を足す

  Claude は、harness の正規化の処理が、2段階認証の確認のコードを、件名が「2段階認証コードのお知らせ」のメールの本文の1行目と、Redis のキー `2fa:<UUID>` の値でだけ `<code:N>` に置き換えるようにする。Claude は、文字の本文を比べる処理に、`Location` と同じ URL の置き換えを通す。Claude は、URL を置き換える処理が、`#` のあとで `=` を持たない部分も JWT と UUID と乱数の値の置き換えに渡す形に変える。Claude は、harness の正規化の処理が、メールアドレスの確認のリンクの JWT の `aud` `sub` `purpose` `email` を比べ、`lexp` を、harness がメールを送らせた段の応答を受けた時刻との差として比べ、Redis の残りの有効な時間と同じく5秒のずれを許すようにする。偽の AWS の記録には時刻が無いので、harness が自分で持つ時刻を基準にする。確認のリンクの値には `iat` も `exp` も無く、今の正規化の `exp - iat` の差では比べられないためである。
  - 完了の確かめ方: `go test -tags compat ./compat/harness/ -run 'TestNormalizeTwoFactorCode|TestNormalizeEmailVerificationJWT|TestNormalizeTextBodyURL|TestNormalizeURLFragment'` が通る
  - 受入基準とテストの対応: 要件5の受入基準4(要求のたびに違う値は形を比べる)は、`normalize_test.go` の `TestNormalizeTwoFactorCode_OnlyTargetPlaces`、`TestNormalizeEmailVerificationJWT_LexpAsDelta`、`TestNormalizeTextBodyURL_StateAndChallenge`、`TestNormalizeURLFragment_JWTWithoutEquals` で確かめる。`TestNormalizeEmailVerificationJWT_LexpAsDelta` は、`lexp` の4秒のずれを許し、6秒のずれを差にすることを確かめる。要件5の受入基準2(メールと Redis を比べる)のうち正規化の範囲も、同じテストで確かめる
  - _要件: 5.2, 5.4_

- [x] 5.7 回ごとに準備の段を送り直す測り方を足す

  Claude は、`perf.go` の `MeasureLatency` と `perfenv.go` の `measure` を、`prepare_each` が真の筋書きでは、慣らしの回と測る回のそれぞれの前に最後の段より前の段を送り直し、最後の段の時間だけを測る形に変える。慣らしの回数と測る回数は変えない。
  - 完了の確かめ方: `go test -tags compat ./compat/harness/ -run TestMeasureLatency_PrepareEach` が通る
  - 受入基準とテストの対応: 要件5の受入基準6(主な操作の応答の時間を測る)のうち、2段階認証の確認を測れることは、`perfmeasure_test.go` の `TestMeasureLatency_PrepareEach` で確かめる。`TestMeasureLatency_PrepareEach` は、準備の段が回ごとに送られ、最後の段の時間だけが返ることを確かめる
  - _要件: 5.6_

- [x] 5.8 新しい段と取り出しを3つの動かし方につなぐ

  Claude は、筋書きの1回の実行に、メールを読む部品と Redis を書き換える部品を渡す。比べる動かし方(`compareenv.go` `compare.go`)は、Cookie の束と取り出した値を版ごとに持ち、絶対の URL の段を版ごとに1回ずつ送り、Redis を書き換える段と値を期限切れにする段を版ごとの値で行い、メールを版ごとの偽の AWS の記録から読む。比べる動かし方は、段ごとに応答を受けた時刻を持ち、確認のリンクの `lexp` を比べる正規化の処理に渡す。版をまたぐ動かし方(`crossenv.go` `cross.go`)は、送り先の版を版に送る段だけに割り当て、ほかの3種類の段を数えず、Redis を1回だけ書き換え、メールを1つの偽の AWS の記録から読む。Claude は、3つの動かし方が、筋書きの始めに偽のログインのサービスを初めの状態に戻してから `oidc_users` の利用者を設定し、筋書きの終わりに、筋書きが失敗したときも、初めの状態に戻すようにする。版をまたぐ動かし方の `CrossEnv.Run` は、1つの筋書きを3つの向きで続けて動かし、向きごとに `Reset` と初期のデータの読み込みをやり直す。そのため Claude は、版をまたぐ動かし方では、向きごとに、`Reset` と同じところで、偽のログインのサービスを初めの状態に戻してから `oidc_users` の利用者を設定し直すようにする。設定し直さないと、2つ目と3つ目の向きが、前の向きの途中で替えた利用者のまま始まり、筋書きの場面と違う利用者でログインしたことに検査が気づかない。応答の時間を測る動かし方(`perfenv.go` `perf.go`)は、メールを、その段を送った版の環境の偽の AWS の記録から読む。`perfenv.go` の `StartPerfEnv` が版ごとに環境を作り、偽の AWS は環境ごとに1つずつあるためである。
  - 完了の確かめ方: `go test -tags compat ./compat/harness/ -run 'TestCompareEnv_NewSteps|TestCrossRoute_OnlyVersionSteps|TestCrossEnv_NewSteps|TestPerfEnv_NewSteps'` が通る。3つの動かし方のテストは、`oidc_users` の欄と、`mail:` の取り出しと、Redis を書き換える段と、値を期限切れにする段を含む筋書きを動かす。`TestCompareEnv_NewSteps` は、確認のリンクの `lexp` を、メールを送らせた段の応答を受けた時刻との差として比べる場合を含む。`TestCrossEnv_NewSteps` は、途中で `oidc_users` の利用者を替える筋書きを3つの向きで動かし、どの向きの始めにも `oidc_users` の利用者が設定し直されていることを確かめる場合を含む
  - 受入基準とテストの対応: 要件5の受入基準1(リンクや確認のコードを使う要求を筋書きに含める)を3つの動かし方で使えることは、上の3つの `NewSteps` のテストで確かめる。要件4の受入基準3(版をまたいで確かめる検査に筋書きを足し、CI で動かす)を支える送り先の決め方は、`TestCrossRoute_OnlyVersionSteps` で確かめる。`TestCrossRoute_OnlyVersionSteps` は、交互の向きで、ほかの3種類の段をはさんでも、版に送る段の数で版が替わることを確かめる
  - _要件: 4.3, 5.1, 5.6_
  - _依存: 5.2, 5.3, 5.4, 5.5, 5.6, 5.7_

- [ ] 5.9 `api.github.com` の証明書と信頼の束を検査の起動につなぐ

  Claude は、`tlsalias.go` で、自己署名の認証局と `api.github.com` の証明書を検査のたびに作る。Claude は、`stack.go` の検査の起動を変え、Java 版に `keytool` で作った PKCS12 の信頼の束を `JAVA_TOOL_OPTIONS` で渡し、Go 版に認証局の証明書を `SSL_CERT_FILE` で渡し、偽のログインのサービスに証明書と鍵とネットワークの別名 `api.github.com` を渡すようにする。信頼の束とは、Java 版が信頼する認証局の証明書をまとめたファイルで、Java ではトラストストアと呼ぶ。今の harness には、コンテナにファイルを写す手段が無い。そのため Claude は、`env.go` の `ContainerSpec` に、testcontainers の `Files` でファイルを写す欄を足す。Claude は、`versions.go` の `Backing` と `JavaEnv` と `GoEnv` に、信頼の束と認証局の証明書の置き場を渡す値を足す。Claude は、PKCS12 の信頼の束を、Java 版のイメージで `keytool` を1回だけ動かすコンテナで作る。
  - 完了の確かめ方: `go test -tags compat ./compat/harness/ -run 'TestTLSAlias|TestVersionsEnv_TLS'` が通る。5つ目の大きなまとまりの最後のタスクなので、完了条件の2つ目のとおり `/verify-backend` も通る。`/verify-backend` は `-tags compat` のテストを流さないので、加えて `go test -tags compat ./compat/harness/ ./compat/fakeoidc/...` も通る
  - 受入基準とテストの対応: 要件5の受入基準3(GitHub の比べ方)を支える証明書は、`tlsalias_test.go` の `TestTLSAlias_CertValidForAPIGitHub` と `TestTLSAlias_FilesStayInWorkDir` で確かめる。版に渡す環境変数は、`versions_test.go` の `TestVersionsEnv_TLS`(Java 版の `JAVA_TOOL_OPTIONS` と Go 版の `SSL_CERT_FILE`)で確かめる。Java 版と Go 版が TLS でつながることは、6.4 の `oidc-github.yaml` で確かめる
  - _要件: 5.3_
  - _依存: 5.1_

- [ ] 6. 認証の操作の筋書きで Java 版と Go 版を比べる
- [ ] 6.1 初期のデータとログインと2段階認証と作り直しとログアウトの筋書きを書く

  Claude は、認証の操作の筋書きのために、次の7つを書く。

  1. 確認の済んでいない利用者と、2段階認証を有効にした利用者の2人を置く `fixtures/users/auth-users.sql`。2人は、`basic.sql` の利用者と同じパスワードと、違うメールアドレスを持つ
  2. design の「認証の操作の筋書き」の筋書きごとの場面のとおりの `login.yaml` `two-factor.yaml` `refresh-logout.yaml`。Claude は、3つの筋書きの `fixtures` に `users/basic.sql` と `users/auth-users.sql` を書く
  3. 筋書きの動かし方の表のとおりの `modes: [compare, cross]` と、版に送る段ごとの `expect.status`。Claude は、この2つを、この小タスクの3つの筋書きと、小タスク6.2 から 6.4 で書く `register.yaml` `email-verification.yaml` `password-reset.yaml` `oidc-google.yaml` `oidc-github.yaml` に書く。版をまたいで確かめる検査が、版に送る段に `expect.status` を求めるためである
  4. `login.yaml` の、管理者の経路 `GET /api/admin/users` への段。Claude は、この段を正しいログインの段のすぐあとに置き、`to: other` を付ける
  5. `refresh-logout.yaml` の、ログアウトのあとの管理者の経路への段。Claude は、この段をログアウトの段のすぐあとに置き、`to: other` を付ける。Claude が管理者の経路への2つの段をすぐあとに置くと、版をまたいで確かめる検査の交互の向きでも、その2つの段は、ログインした版と違う版に送られる
  6. 2つの値の期限切れ。Claude は、ログインの状態の値の期限切れを `expire.cookie: accessToken` で作り、ログインを続けるための値の期限切れを、Redis を書き換える段で `refresh-token:{取り出した値}` を消して作る
  7. 途中の手順をまたぐ5つの操作と、作り直しとログアウトの段の `to: other`。Claude は、この小タスクの3つの筋書きと、小タスク6.2 から 6.4 で書く5つの筋書きで、手順の2つ目からの要求を送る段に `to: other` を付ける。その段は、2段階認証の確認の段、作り直しの段、ログアウトの段、確認のリンクでの確認の段、送り直したリンクでの確認の段、再設定の確認の段と再設定の段、`handleOidcCallback` の段である。版をまたいで確かめる検査の送り先を決める `CrossRoute` は、Java 版から Go 版の向きと Go 版から Java 版の向きでは、`to: other` を付けた段と最後の段でだけ版を替える。そのため、Claude が `to: other` を付けないと、手順の1つ目と2つ目の要求が同じ版に送られ、版をまたいで確かめる検査は、1つ目の要求と2つ目からの要求が別々の版に届く場面(要件4の受入基準2)を確かめられない

  - 完了の確かめ方: `make compat` の全体が通り、3つの筋書きの答え、Cookie、ヘッダ、データベース、Redis、メールに違いが出ない。`make compat` の全体には、5つ目の大きなまとまりで harness を変えたあとも、置き換えの spec の段階2の検査(版を自分と比べる検査と、操作の数の検査)が通ることが含まれる
  - 受入基準とテストの対応: 要件1の受入基準1(Java 版と同じ状態の番号、本文、Cookie)と受入基準2(今の画面で登録、ログイン、2段階認証、ログアウト、再設定を終えられる)は、`login.yaml` の「正しいログイン」と `two-factor.yaml` の「2段階認証のログインと確認」で確かめる。要件3の受入基準1(ログインの状態の有効な時間と、ログインし直さずに使い続けられる時間)は、`refresh-logout.yaml` の「作り直し」と「ログインの状態の値の期限が切れたあとの作り直し」と「ログインを続けるための値の期限が切れたあとの作り直し」で確かめる。要件3の受入基準2(確認のコードの有効な時間と、誤りの回数の上限)は、`two-factor.yaml` の「誤ったコード」と「5回目で上限」で確かめる。要件3の受入基準5(ログアウトでほかの端末のログインの状態も使えなくする)は、`refresh-logout.yaml` の「ログアウトのあとの作り直しとログインの要る操作」で確かめる。要件3の受入基準6(アカウントが無いのかパスワードが違うのかを見分けられない)は、`login.yaml` の「パスワードの誤り」と「アカウントが無い」で確かめる。要件2の受入基準1(ログインの状態を持たない要求を断る)と受入基準2(期限切れ、書き換え、使えなくなったログインの状態の要求を断る)のうち管理者の経路の答えは、`login.yaml` と `refresh-logout.yaml` の管理者の経路への場面で確かめる。Java 版と Go 版は、管理者の経路への要求に、ログインの状態の値を受け入れれば 403 で答え、受け入れなければ 401 で答える。要件5の受入基準1(誤りのある要求も含めた筋書きを書く)と受入基準2(データベースとログインの状態の保存先とメールを比べる)と受入基準4(要求のたびに違う値は形を比べる)は、この3つの筋書きの比べた結果で確かめる
  - _要件: 1.1, 1.2, 2.1, 2.2, 3.1, 3.2, 3.5, 3.6, 5.1, 5.2, 5.4_
  - _依存: 4.4, 5.9_

- [ ] 6.2 新規の登録と確認のメールの送り直しの筋書きを書く

  Claude は、`register.yaml` と `email-verification.yaml` を、筋書きごとの場面のとおりに書く。確認のリンクの値は `mail:` で取り出す。期限の切れたリンクは、取り出したリンクの値を `expire.var` で書き換えて作る。Claude は、ログインの画面からの送り直しの場面と「前のリンクが使えないこと」の場面では、Redis を書き換える段で `email-verification:rate:<メールアドレス>` を消してから、送り直しの要求を送る段を置く。
  - 完了の確かめ方: `make compat` で、2つの筋書きの答えと残したものとメールに違いが出ない
  - 受入基準とテストの対応: 要件1の受入基準2(新規の登録とメールアドレスの確認を終えられる)は、`register.yaml` の「確認のリンクでの登録の完了」で確かめる。要件1の受入基準5(メールの件名と本文)は、`register.yaml` の「登録の完了のメール」と `email-verification.yaml` の確認のメールで確かめる。要件3の受入基準3(リンクの有効な時間と、1回しか使えないことと、新しいリンクで前のリンクが使えなくなること)は、`register.yaml` の「使い終わったリンク」と `email-verification.yaml` の「期限の切れたリンクでの送り直し」と「前のリンクが使えないこと」で確かめる。要件3の受入基準4(送り直せる間隔の制限)は、`email-verification.yaml` の「送り直せる間隔の制限」で確かめる
  - _要件: 1.2, 1.5, 3.3, 3.4, 5.1, 5.2_

- [ ] 6.3 パスワードの再設定の筋書きを書く

  Claude は、`password-reset.yaml` を、筋書きごとの場面のとおりに書く。再設定の値は `mail:` で取り出す。期限の切れた値は Redis を書き換える段で `password-reset:{取り出した値}` を消して作り、値は有効だが利用者が居ない場面は、Redis を書き換える段で、筋書きに書いた値のキーに居ない利用者の ID を置いて作る。ほかの端末のログインの状態は、再設定の前のログインで `cookie:accessToken` で取り出した値を、再設定のあとに `Cookie` ヘッダに差し込んで送る。
  - 完了の確かめ方: `make compat` で、`password-reset.yaml` の答えと残したものとメールに違いが出ない
  - 受入基準とテストの対応: 要件1の受入基準2(再設定のメールを受け取り、新しいパスワードでログインできる)は、`password-reset.yaml` の「再設定」で確かめる。要件3の受入基準3(再設定のリンクの有効な時間と、1回しか使えないこと)は、`password-reset.yaml` の「期限の切れた値」と「使い終わった値」で確かめる。要件3の受入基準5(再設定でほかの端末のログインの状態も使えなくする)は、`password-reset.yaml` の「再設定のあとのほかの端末のログインの状態」で確かめる。要件3の受入基準6(アカウントがあるかを答えから見分けられない)は、`password-reset.yaml` の「アカウントが無いメールアドレス」で確かめる
  - _要件: 1.2, 3.3, 3.5, 3.6, 5.1_

- [ ] 6.4 Google と GitHub のアカウントでのログインの筋書きを書く

  Claude は、`oidc-google.yaml` と `oidc-github.yaml` を、筋書きごとの場面のとおりに書く。開始の要求は、Accept が無いものと、axios の既定の Accept を付けたものの2つを送る。どの場面も、開始の応答から `text` でログインの開始の URL を取り出し、絶対の URL の段で偽のログインのサービスに送り、`header:Location?code` と `header:Location?state` で取り出した値を差し込んで、`handleOidcCallback` を `request.path` の形の版に送る段で送る。`path` の形で送るのは、操作の数の検査(`TestCoverage_Operations`)が、`path` の形の段だけを操作として数えるためである。Claude は、「断られたとき」の場面の筋書きを、絶対の URL の段で `PUT /_compat/deny/<提供元>` を送ってから、ログインの開始の要求を送る形で書く。Claude は、途中で利用者を替える場面の筋書きでは、利用者を替えるところに、絶対の URL の段で `PUT /_compat/users/<提供元>` を送る段を置く。
  - 完了の確かめ方: `make compat` で、2つの筋書きの答え、`Location`、Cookie、データベース、Redis に違いが出ない
  - 受入基準とテストの対応: 要件5の受入基準3(Google か GitHub のアカウントでのログインを、偽のログインのサービスを使って比べる)の4つの場面は、2つの筋書きの「初めての利用者」「登録済みのアカウントへのつなぎ」「確認の済んでいないアカウント」「断られたとき」で確かめる。要件1の受入基準3(Google か GitHub でログインでき、Java 版と同じ画面に移り、同じ文言を見せる)は、同じ場面の `Location` と開始の応答の比べた結果で確かめる。要件3の受入基準7(確認済みのメールアドレスだけを使い、同じブラウザが始めたログインと組になっていることを確かめる)は、`oidc-github.yaml` の「確認済みのメールアドレスが無い利用者」と、両方の「`state` の記録が無いとき」で確かめる
  - _要件: 1.3, 3.7, 5.3_

- [ ] 6.5 ログインの状態の検査と入力の誤りの筋書きと変えた動きの一覧を書く

  Claude は、`require-login.yaml` と `validation.yaml` を、design の「認証の操作の筋書き」の筋書きごとの場面のとおりに、筋書きの動かし方の表のとおり `modes: [compare]` で書き、`changed-behaviors.yaml` に CB-011 からの項目を、変えた動きの一覧の項目の節のとおりに足す。期限を切らした値は `expire.cookie: accessToken` で作り、書き換えた値は筋書きに書いた署名の合わない JWT を `Cookie` ヘッダで送り、ログアウトで使えなくなった値は取り出した値を `Cookie` ヘッダに差し込んで送る。Claude は、小タスク4.4 で控えた、Cookie の値の形の誤りが `ErrorHandlerFunc` に届く場面の Java 版との違いと、筋書きで見つかった、Java 版が 500 で答える要求を、要求ごとに1つの項目にする。
  - 完了の確かめ方: `make compat` で、2つの筋書きに、変えた動きの一覧に載せた違いのほかの違いが出ない
  - 受入基準とテストの対応: 要件2の受入基準1(ログインの状態を持たない要求を断り、`OPTIONS` と生きているかの確認は通す)と受入基準2(期限切れ、書き換え、使えなくなったログインの状態の要求を断る)は `require-login.yaml` の「Cookie の無い要求」「期限を切らした値」「書き換えた値」「ログアウトで使えなくなった値」「無効な値での書き込みの要求」「`OPTIONS` と `/actuator/health`」で確かめる。要件2の受入基準3(利用者が居るかを確かめない)は、2.3 の `TestIdentify_DoesNotCheckUserExists` で確かめる。要件1の受入基準4(入力の誤りの条件とエラーの文言)は `validation.yaml` の13の操作の入力の誤りで、要件5の受入基準1のうち偽の要求を見分けるヘッダを付けない要求は `validation.yaml` の「偽の送信の検査のヘッダを付けない要求」で、要件5の受入基準5(形の誤った要求に 400 で答え、変えた動きの一覧に載せる)は `validation.yaml` の「形の誤った要求」と変えた動きの一覧の項目で確かめる
  - _要件: 1.4, 2.1, 2.2, 2.3, 5.1, 5.5_

- [ ] 6.6 版をまたいで確かめる検査を通す

  Claude は、6.1 から 6.4 で `modes` に `cross` を書いた筋書きを、Java 版から Go 版、Go 版から Java 版、交互の3つの向きで動かし、違いが出た筋書きを直す。この検査は、途中の手順をまたぐ5つの操作と、ログインした版と違う版への管理者の経路への要求を含む。
  - 完了の確かめ方: `make compat-cross` が通る。`go test -tags compat -run TestCrossRoute_AuthProcedureSteps ./compat/harness/` が通る。このテストは、認証の筋書きを読み、Java 版から Go 版の向きと Go 版から Java 版の向きのそれぞれの `CrossRoute` の結果で、管理者の経路への段と、小タスク6.1 で `to: other` を付けた、途中の手順の2つ目からの要求を送る段と作り直しの段とログアウトの段が、その前の版に送る段と違う版に送られることを確かめる。Claude は、このテストを、`backend/compat/harness/cross.go` のテストのファイルとして `backend/compat/harness/cross_test.go` を作って置く
  - 受入基準とテストの対応: 要件4の受入基準1(一方の版でログインした利用者が、もう一方の版でもログインし直さずに使い続けられる)は、ログインした版と違う版への管理者の経路への要求と、作り直しとログアウトの3つの向きで確かめる。要件4の受入基準2(途中の手順をまたぐ5つの操作を、版をまたいでも終えられる)は5つの操作の3つの向きで、要件4の受入基準3(版をまたいで確かめる検査に筋書きを足し、CI で動かす)は `make compat-cross` が CI で動く `TestCross_` の検査で確かめる
  - _要件: 4.1, 4.2, 4.3_

- [ ] 6.7 主な操作の応答の時間を測る

  Claude は、`login-perf.yaml` `two-factor-perf.yaml` `refresh-perf.yaml` `register-perf.yaml` を、筋書きの動かし方の表のとおりに、`modes` を `perf` にして書く。`two-factor-perf.yaml` は、`prepare_each` を真にし、`measure_memory` を付けず、`auth-users.sql` の2段階認証を有効にした利用者を使い、ログインの段のあとに届いたメールから確認のコードを `mail:` で取り出す。Claude は、置き換えの spec の測り方で4つの操作の応答の時間を測り、結果を `progress.md` の決まりのとおりに書く。
  - 完了の確かめ方: `make compat-perf` が4つの操作を測り、`progress.md` に結果が書かれる。6つ目の大きなまとまりの最後のタスクなので、完了条件の2つ目のとおり `/verify-backend` も通る
  - 受入基準とテストの対応: 要件5の受入基準6(主な操作の応答の時間を測る)は、`make compat-perf` の `TestPerf_` の検査の結果で確かめる
  - _要件: 5.6_

- [ ] 7. API の説明画面で確かめて進み具合を書く
- [ ] 7.1 API の説明画面でログインを確かめる

  Claude は、この作業フォルダの最上位から compose の `backend-go` を作り直して起動し、この作業フォルダのコードを動かす。Claude は、Go 版の `registerUser` と `verifyEmail` の操作で、ログインに使う利用者を作る。確認のリンクの値は、開発環境の LocalStack の SES が受けたメールから読む。Claude は、開発環境の compose の `api-docs`(ポート 8082)を Playwright で開き、API の説明画面での確認の節の3つを確かめ、結果を PR の本文に書く準備をする。
  - 完了の確かめ方: ログインする前の `GET /api/users/me` が 401 を、作った利用者での `POST /api/auth/login` が 200 を、ログインしたあとの `GET /api/users/me` が 501 と「未実装です。」を返す
  - 受入基準とテストの対応: 要件6の受入基準1(説明画面の「Try it out」でログインできる)は `POST /api/auth/login` の「Try it out」の 200 で、要件6の受入基準2(ログインした開発者の要求を操作の処理に渡す)はログインの前後の `GET /api/users/me` の 401 と 501 で確かめる
  - _要件: 6.1, 6.2_

- [ ] 7.2 進み具合の表と試作の記録を書き足す

  Claude は、このタスクで、次の4つをする。

  1. `progress.md` のまとまりの表の認証の行の spec の列に `.kiro/specs/backend-go-auth` を書き、状態の列を「作り終えた」にする。状態の列を「作り終えた」にすると、操作の数の検査(`TestCoverage_Operations`)が、認証の13の操作がすべて比べる筋書きに出てくることを求め始める
  2. 表の下の、API の説明画面での確認の決まりを、API の説明画面での確認の節のとおりに書き直す
  3. 実装で確かめた Java 版の値の形を、research.md に書き足す
  4. 状態の列を「比べる検査に通った」にする作業が残ることを、PR の本文に書く

  Claude は、このタスクで、次の2つを扱わない。

  1. 状態の列の「spec の作成中」。これは spec を出す PR で書く
  2. 状態の列を「比べる検査に通った」にすること。Claude は、状態の列を「比べる検査に通った」にすることを、置き換えの spec の段階2の終わりを書いたときと同じく、別の PR で行う。Claude がその PR を作るのは、この PR の CI で Java 版と Go 版を比べる検査が通り、この PR がマージされたあとである。この PR は必須のチェックが通るとすぐに自動でマージされるので、この PR の中で CI が通ったあとに書く機会が無いためである

  このタスクの完了は、状態の列を「作り終えた」にしたところまでとする。
  - 完了の確かめ方: `progress.md` の認証の行が、spec の列に `.kiro/specs/backend-go-auth`、状態の列に「作り終えた」を持ち、表の下の決まりと research.md の書き足しが、この小タスクの文のとおりになっている。`go test -tags compat -run TestCoverage_Operations ./compat/` が通る。7つ目の大きなまとまりの最後のタスクなので、完了条件の2つ目のとおり `/verify-backend` も通る
  - 受入基準とテストの対応: 要件6の受入基準3(進み具合の表の下の決まりを書き直す)と要件7の受入基準3(進み具合の表に、この spec の場所とまとまりの状態を書く)は、`progress.md` の文で確かめる。要件7の受入基準1(設計の前に試しに作り、方法と結果を research.md に書く)と受入基準2(同じにできない動きが見つかれば止まって所有者に報告する)は、research.md の試作の記録と書き足しで確かめる。この4つの受入基準を確かめるテストは無い。認証の13の操作が比べる筋書きに出てくることは、`compat_test.go` の `TestCoverage_Operations` で確かめる
  - _要件: 6.3, 7.1, 7.2, 7.3_

## 実装のメモ

- Claude は、途中のタスクのテストを、`bash .claude/scripts/parallel/run-check.sh backend-go <コマンド>` の形で流す。タスクの「完了の確かめ方」の `go test` と `make` のコマンドは、この `<コマンド>` にあたる。Claude は、`go test` を、`backend/` を作業の場所として流す
- `backend/compat/` の下のファイルは、すべて `//go:build compat` を持つ。Claude は、5つ目の大きなまとまりで新しく作る `capture.go` `expire.go` `tlsalias.go` `deny.go` とそれぞれのテストにも、同じビルドタグを付ける。`backend/compat/` の下のファイルのテストは、`-tags compat` を付けないと組み立てに入らない。`/verify-backend`(`make check`)は、これらのテストを流さない
- Claude は、`make compat` `make compat-cross` `make compat-perf` を、筋書きを書く6つ目の大きなまとまりのタスクでだけ流す。どれも Java 版と Go 版のイメージを組み立てるので、1回に長い時間がかかる
- この PC の `keirekipro.parallelSlots` は1である。Claude は、壊して確かめる写しの `run-check.sh` を同時に流すと、2つ目以降が順番待ちの表示だけを出して終わり、テストが流れない。Claude は、写しを1つずつ、`run-check.sh --wait` で流す
- `internal/auth` は depguard の決まりで `internal/httpapi/middleware` を読めないので、`auth.MessageUnexpected` と `auth.MessageForbidden` は middleware と同じ文字列を別に持つ。Claude は、両方を読める `internal/httpapi` のテストで、2つの定数が middleware の定数と同じかを確かめる。`errInvalidInput` は渡した束をそのまま `Errors` に入れるので、Claude は nil を渡さない
- Java 版の Redis の値は、application.yaml の `use-jackson2-defaults` と `JsonMapperConfig` の設定を当てた Jackson で書かれる。そのため、絵文字などの U+10000 以上の文字は、大文字の16進の2つ組の逃がしになる。Claude は、期待する値を設定の無い JsonMapper で作らず、`backend/src/test/resources/baseline-samples/redis/` にある Java 版が置いた値の見本と比べる。`redisjson.go` の `toJacksonEscapes` が、Go の Encoder と Jackson の3つの違いを直す
- Claude のツールの引数は、逆斜線と u と4桁の16進の並びを、その並びが表す文字に変えてしまう。Claude は、この並びをファイルに書くときは、perl の置き換えで逆斜線を `\x5c` と書き、日本語を含む置き換えには perl を使わない
- Spring の `ResponseCookie` は、Max-Age が0以上のとき、必ず `Expires=` も書く。そのため、`auth.ChallengeCookie` は、design.md の表と違って `now time.Time` を3つ目の引数に取り、`Expires=` に now の600秒後を書く。`auth.DeleteCookie` と `auth.ExpiredAccessTokenCookie` も `Expires=Thu, 01 Jan 1970 00:00:00 GMT` を書く。Claude は、httpapi のタスクで、`ChallengeCookie` に要求を受けた時刻を渡し、Cookie の名前と Path は `auth.ChallengeCookieName` と `auth.ChallengeCookiePath` を使う
- golangci-lint の gosec は、名前に cred、pass、pwd、secret、token などを含む文字列の定数を、秘密の値として止める(G101)。また、変数のパスを `os.ReadFile` に渡すと止める(G304)。`.golangci.yml` は `nosec: true` なので、`#nosec` では黙らせられない。Claude は、文言の定数にそれらを含まない名前を付け、テストのファイルは `fs.ReadFile(os.DirFS(<置き場>), <名前>)` で読む
- gosec は、`Secure` `HttpOnly` `SameSite` を付けない `http.Cookie` の値を止める(G124)。テストの要求に Cookie を付けるときも当たるので、Claude は、テストでは `r.Header.Add("Cookie", "名前=値")` と書く
- `auth.Identify` は、データベースを読めないとき、包んだ誤りでパニックにする。`internal/auth` は depguard の決まりで `internal/httpapi/middleware` を読めず、ログを書く部品も持たないので、いちばん外側の `Recover` が、誤りをログに書き、決まった本文の 500 で答える。Claude は、`httpapi.New` に中間処理を並べるタスクで、`Recover` を `Identify` より外に置き、データベースを読めない `Identify` を含めてつないだ場合に、決まった本文の 500 が返ることもテストで確かめる
- `auth.RequireLogin` は、Spring の `/api/admin/**` に合わせ、`/api/admin` そのものにも役割 `ADMIN` を求める。`/api/adminx` には求めない
- `@Email` の判定は、Hibernate Validator が呼ぶ JDK の `java.net.IDN.toASCII` を写すため、`idna.go` に nameprep(Unicode 3.2)と Punycode を持つ。表の `nameprep_table.go` は `testdata/nameprep/Gen.java` が JDK から読み出して作り、テストの期待の `email_vectors.txt` と `idna_vectors.txt` は `testdata/nameprep/Vectors.java` が Java 版の判定を動かして作る。どちらも spring のコンテナの Java 21 で動かす(使い方は各ファイルの先頭の注釈)。Claude は、作るときに、基本多言語面のすべての文字を4つの位置に置いた25万件(`Vectors.java exhaustive`)で、Go 版と Java 版の判定の食い違いが0件であることも写しの中で確かめた。Go 版は、`golang.org/x/text` を直接の依存にしない(design.md は go.mod に足す依存を2つに限る)
- 生成した要求の型は項目を `string` で持つので、Go 版は、項目が無い要求を空の文字列の要求と同じに検査する。Java 版は、項目が無いと値が null になり、`@NotBlank` の文言だけを返す(`@Size` `@Pattern` `@MaxUtf8Bytes` は null を誤りにせず、`@PasswordMatches` は null どうしを一致とみなす)。そのため、`password` の項目が無い要求には「8文字以上」と「英小文字、英大文字、数字」の文言が、`confirmPassword` だけが無い要求には「一致していません」の文言が、Go 版で増える。Claude は、小タスク6.5 で、この違いを変えた動きの一覧に足し、所有者に報告する
- Claude の Edit の道具は、文字と結合する文字の並び(「ا」と U+0653 など)を、合成した1文字に変えることがある。Claude は、結合する文字をファイルに書くときは、Java では `(char) 0x0301` のように、Go のテストでは `ch(0x0301)` のように、文字の番号で書く
- 要求の JSON に対になっていないサロゲートの書き方(たとえば `"\ud800"`)があると、Go の `encoding/json` は U+FFFD(UTF-8 で3バイト)に置き換え、Java 版の `MaxUtf8BytesValidator` は `?`(1バイト)と数える。そのため、72バイトの境目の近くのパスワードで、2つの版の判定が変わることがある。画面からは送られない入力である。Claude は、小タスク6.5 で、この違いを、項目が無い要求の違いと並べて、変えた動きの一覧に載せるかを決め、所有者に報告する。
- LocalStack の SES が受けたメールは、`curl localhost:4566/_aws/ses` で JSON として読める。Java 版の FreeMarker は、拡張子が `.ftl` のひな形では HTML の特別な文字を逃がさず、利用者の名前の `<&>` や `${x}` もそのまま差し込む。Claude は、Java 版の CSRF の検査を通すため、先に GET の要求で `XSRF-TOKEN` の Cookie を受け取り、POST の要求の `X-XSRF-TOKEN` の見出しに同じ値を入れる
- `spring_query.go` の正解の `testdata/springquery/vectors.txt` は、`testdata/springquery/Gen.java` を spring のコンテナの Java 21 で、Java 版と同じ Spring 7.0.10 の jar(spring-core と spring-web と commons-logging と jspecify)を渡して動かして作る。`springQuery` は先頭の `?` を付けないので、Claude は、小タスク3.13 で、問い合わせの無い認可の URL のあとに `?` と `springQuery` の結果をつなぐ
- Java 版の Jackson が Redis の中の JSON を読む規則(前後の文字、数の小数と文字列、UUID の形、値が null や JSON でないとき)は、開発環境の Java 版の Redis に値を置いて API を呼べば調べられる。`twofactor.go` の `parseJacksonUUID` と `parseJacksonInt` はその結果を写したもので、表は `TestTwoFactor_ReadsChallengeLikeJackson` にある。Claude は、ほかの途中の記録を読むときも、この2つの関数を使う
- Redis の値の中に JSON を文字列として入れる記録(Java 版の `writeValueAsString` で作った文字列を、もう一度 JSON の文字列にして置く記録)では、中の JSON を `encodeJSONText` で作る。中の JSON は U+10000 以上の文字(絵文字など)をそのまま書き、外の JSON の文字列にするときだけ `encodeJSON` が2つ組の `\u` にする。日時の項目は、Jackson が数、秒の数の文字列、時差の付いた ISO 8601、空の文字列も読むので、`registration.go` の `parseJacksonInstant` を使う
- `login.go` の `passwordMatches` は、Spring の `BCryptPasswordEncoder.matches` を、開発環境の Java 版で確かめた規則で写す。ハッシュは `$2a$` `$2b$` `$2y$` の形だけを照らす(`$2$` は、Go の bcrypt が鍵の末尾に0のバイトを足して計算し、Java 版と結果が変わるので、照らさずに合わないとする)。強さが4から31の外のハッシュは、Java 版が 500 で答えるので誤りを返す。塩の22文字目に使われない下位の4ビットが立つハッシュは合わないとする。パスワードは先頭の72バイトだけを使う(Go の `bcrypt.CompareHashAndPassword` も先頭の72バイトだけを使うので切り詰めない。72バイトを超えると誤りにするのは `bcrypt.GenerateFromPassword` だけで、ハッシュを作る操作では先に切り詰める)。Claude は、パスワードを照らすほかの操作でも、この関数を使う
- `login.go` の `accountFromRows` は、役割を USER、ADMIN の順に並べる。Java 版は役割を順の決まらない集合で持つので、ログインの状態の値とログインを続けるための値の `roles` の順が、Java 版では JVM ごとに変わる。Claude は、小タスク6.5 で、この違いを変えた動きの一覧に載せるかを決め、所有者に報告する
- Java 版の `User.reconstruct` は、利用者を読むたびに、2段階認証が有効でメールアドレスかパスワードが無い利用者と、2段階認証が無効な管理者を、DomainException の 400 で断る。Go 版は、`login.go` の `accountFromRows` で同じ順に確かめる。Claude は、Java 版が `UserRepository` で利用者を読むほかの操作(パスワードの再設定、確認のメールの送り直し、メールアドレスの確認、Google と GitHub のログイン)でも、`findAccountByEmail` か `findAccountByID` を通して読み、この確かめを外さない
- `emailverification.go` の `issueEmailVerificationToken` は、golang-jwt の `SignedString` を使わずに、決まったヘッダと `encodeJSONText` で書いた本体に `jwt.SigningMethodHS256.Sign` で署名する。`SignedString` は本体を `json.Marshal` で書き、< > & を逃がして Java 版と違う値になるためである。値を読む `readEmailVerificationToken` は、開発環境の java-jwt 4.6.2 で確かめた動き(`testdata/emailverification/Probe.java`)に合わせ、署名の末尾の = を受け付け、exp と nbf と iat があれば確かめる。lexp が小数の値と、形の崩れた UUID の sub は、Java 版と読み方が違う可能性があり確かめていないが、サーバーの鍵でしか署名できないので外から見える違いは無い
- `sendEmailVerification` は、送り直せる間隔の中で送れないとき、偽と nil の誤りを返す。Claude は、小タスク3.10 と3.11 で、これを Java 版の RATE_LIMITED と同じ 400 の答え(MessageResendRateLimited)に写す。テストの `javaDevSigningKey` と `javaSample` で始まる定数は、開発環境の Java 版が実際に送った確認のリンクの値とその項目なので、後のタスクのテストでも使える
- `passwordreset.go` の `storePasswordResetToken` は、渡された有効な時間を付け、0以下なら記録を置かずに誤りを返す。Claude は、小タスク3.11 の `VerifyEmail` で、Java 版と同じく確認のリンクの残りの時間を渡す。残りが1ミリ秒より短いと、go-redis は1ミリ秒に切り上げて置き、Java 版は Redis に断られて 500 になりうるので、3.11 でこの境目の扱いを Java 版と比べる
- `emailverification.go` の `inTransaction` と `loadStoredUser` と `saveUser` は、Java 版の `@Transactional` と `UserRepository.findById` と `MyBatisUserRepository.save` を写した。小タスク3.12 と3.14 で利用者の行を書き換えるときは、これを使う。`isIntegrityViolation` は、Spring が `DataIntegrityViolationException` に訳す SQLSTATE(21000 と、分類 01 02 22 23 27 44)を見分ける。小タスク3.11 の `Register` は、Java 版の `UserRegistrationUseCase` が呼ぶ `Email.create`(Apache Commons の `EmailValidator`。Hibernate の確かめとは別)を写すか、変えた動きの一覧に書く。登録の完了(`completeRegistration`)は、登録の受け付けで確かめ済みのメールアドレスしか届かないので、この確かめを写していない。`loadStoredUser` は連携の行を行の ID でまとめ、Java 版の `toEntity` は小文字にした連携の名前でまとめるので、同じ名前の連携の行が2つあると保存の結果が違う。Java 版の保存ではこの行を作れないので写していないが、小タスク6.5 の変えた動きの一覧に書く
- `commonsemail.go` は、Java 版の `Email.create` が使う Apache Commons Validator 1.11.0 の `EmailValidator.getInstance(false, false)` を写した。トップレベルドメインの表(`commons_tld_table.go`)と期待(`testdata/commonsemail/vectors.txt`)は、`testdata/commonsemail/Gen.java` を Java 版の依存の版で動かして作り直す。ドメインに基本多言語面の外の文字があると変えずに返すので、呼ぶ側は入力の検査(`isEmailLikeHibernate`)を先に通す。`Register` は、Java 版がパスワードのハッシュを作ってから入力の誤りで断るのに対し、ハッシュを作らずに断る(答えは同じ)。`VerifyEmail` の目的 PASSWORD_RESET の再設定の値の有効な時間は、Java 版の `Duration.toMillis` と同じくミリ秒に切り捨て、1ミリ秒より短いと置かずに誤りを返す(Java 版は Redis に断られて 500 になる)。`errors.go` に `MessageEmailNotRegistrable` を足した
- `passwordreset.go` の `ResetPassword` は、`invalidateSessions` を呼ばずに、`inTransaction` の中で `BumpTokenVersion` にトランザクションの `q` を渡し、続けて `removeAllRefreshTokens` を呼ぶ。`invalidateSessions` はトランザクションの外で世代の番号を上げるので、Java 版の `@Transactional` と同じ取り消しにならないためである。利用者が居ないときの誤りを操作ごとに変えるときは、`emailverification.go` の `loadStoredUserOr` に誤りを渡す(`loadStoredUser` は確認のリンクが無効な 400 を渡す)
- 対象の外の `provider` を受けた Java 版は、`StartOidcAuthorizationUseCase` が Redis に `oidc:provider:` `oidc:state:` `oidc:code_verifier:` の3つの記録を置いたあとに、`OidcProviderFactory.getProvider` が RuntimeException を投げ、`AppExceptionHandler` の Exception の扱いで 500「予期せぬエラーが発生しました。」で答え、3つの記録を残す(コードを読んで確かめた)。`oidc.go` の `StartOIDC` は、記録を置く前に 400「入力エラーがあります。」と空の `errors` で断る。この違いは、design.md の変えた動きの一覧の節のとおり、タスク6.5で一覧に載せる。`provider` の大文字と小文字は Java 版と同じく区別せず、Redis には受けたままの `provider` を置く
- Google と GitHub から戻ったあとの処理は、`oidc.go` ではなく同じパッケージの `oidccallback.go` に置いた(約700行あり、開始の処理と分けたほうが読みやすいため)。`HandleOIDCCallback` は、移る先の URL の全体を `OIDCCallbackResult` の `Location` に入れて返し、成功のときだけ `Session` にログインの状態の値を入れる。受け口(タスク4.3)はこの値をそのまま使う。Java 版の RestClient はどの状態の番号の応答でも本文を読み(`RestClientConfig` の `defaultStatusHandler`)、Jackson は `spring.jackson.use-jackson2-defaults` で先頭の JSON の値のあとを読まないので、Go 版も Google と GitHub の応答を状態の番号によらず読み、先頭の値のあとを読まない。トークンの応答の `expires_in` は、Java 版の `Integer` の項目と同じく `parseJacksonInt` の規則で読めるかだけを確かめ、値は使わない。Google と GitHub の応答の本文は 1 MiB までしか読まない。GitHub の `id` が整数でない数か、オブジェクトか配列のときは、Java 版の `String.valueOf` と同じ文字列を作れないので、利用者の情報の失敗にする。この違いはタスク6.5で変えた動きの一覧に載せる
- 認証の13の操作は、生成した応答の型ではなく `httpapi` の `authresponses.go` の `authResponse` で答える。生成した応答の型は Set-Cookie を1つしか書けないためである。受け口(タスク4.2、4.3)は、`*auth.Error` を `authErrorResponse` で状態の番号と本文と Cookie に変え、偽が返ったときだけほかの誤りとして扱う。入力の誤りの `errors` の項目は名前の順に書く。Java 版は HashMap の順だが、Java 版との突き合わせの仕組みは JSON の項目を名前で比べるので、食い違いにならない
- 11の操作の受け口は、`auth.go` の型 `authHandlers` に置き、認証の処理をインタフェース `authService` で受ける(テストで処理の代わりを使うため)。4.3 で Google と GitHub の2つの操作を足すときは、`authService` に `StartOIDC` と `HandleOIDCCallback` を足す。無い Cookie と本文の任意の項目は空の値にして処理に渡す。Java 版は、空の値の Cookie `twoFactorChallenge` を、Cookie が無いときの例外を投げずに空の値のまま処理に渡すので、空の値の Cookie の答えが Go 版と同じかを、6.1〜6.3 の `two-factor.yaml` の筋書きで突き合わせる
- Google と GitHub の2つの操作の受け口は、`auth.go` に置いた。4.4 では、`NewStrictHandlerWithOptions` に中間処理 `authRequestMiddleware` を渡し(要求の Host と Accept を context に入れる)、`newAuthHandlers` に、ログの出力先、Cookie の Secure、設定の `App.APIBaseURL`(本番の戻り先の URL の基底)、`time.Now` を渡す。`startOidcAuthorization` の Content-Type は、設計の簡単な規則では `*/*, application/json` などで Java 版と食い違ったので、Spring と Tomcat の取り決めを写した。処理は、Java 版と同じく、Accept を調べる前に呼ぶ
- 6.5 の変えた動きの一覧に載せる、`startOidcAuthorization` の Accept と Host の違い(どれも手元の Java 版で答えを確かめた): (1) `image/*` `application/*+xml`、ASCII でない Accept、`Q=abc` や `Q=2` のような正しくない大文字の Q は、Java 版では誤りの画面の都合で 401、Go 版では 406。(2) 名前の形が正しいが Java が知らない charset は、Java 版では 406、Go 版では受け入れる。(3) 受けられる型の候補が50を超える Accept(`*/*` と `a/b1`〜`a/b49` の50個)は、Java 版では内部の誤りで 500、Go 版では 200。(4) Host の port が数字でない(`8o` `+80`)ときは、Java 版では Tomcat が 400、Go 版では Host をそのまま使うか port を落とす。(5) provider が正しくなく Accept も受けられないときは、Java 版では 500 か 401、Go 版では 400
- 4.4 で、`server.go` に、認証の受け口を深さ1に、ほかの操作の答えを深さ2に埋め込む型 `routes` を置いた。ほかのまとまりの spec は、自分の受け口を `routes` に深さ1で足し、問い合わせの誤りに 400 で答える経路を `queryErrorAs400Prefix` の条件に足す。認証の処理の型は、`Options.AuthHandlers` に渡すため、外から使える名前 `AuthService` にした
- Cookie の値の形の誤りは、生成したコードの `ErrorHandlerFunc` に届かない。生成したコードは Cookie の引数を string の別名で受け、値を変換せずに渡すためである。そのため、6.5 の候補には控えない
- 6.5 の変えた動きの一覧に載せる: Google と GitHub から戻ったときの問い合わせで `code` か `state` が2つある要求は、Java 版では誤りの画面への 302、Go 版では設計のとおり 400 と入力の誤りの本文(手元の Java 版で確かめた)
- 起動のテスト(`cmd/keirekipro/main_test.go`)のデータベースには、表が無い(マイグレーションの履歴を確かめるだけの作りのため)。起動のテストで認証の操作を確かめるときは、表を読む前に断られる要求(入力の検査で断られる要求、受け付けないログインの状態の値)を使う。表を読む答えは、6.x の Java 版と Go 版を比べる検査で確かめる
- 5.1 で、偽のログインのサービスの初めに戻す口を `POST /_compat/reset` にした。戻すのは両方の提供元の利用者の設定と断る残りの回数だけで、クライアントの値と発行済みのコードとアクセストークンは残す。断らせる口は `PUT /_compat/deny/{provider}`
- 5.9 で、偽のログインのサービスに証明書と鍵を渡すときは、環境変数の名前の定数 `fakeoidc.CertFileEnv` と `fakeoidc.KeyFileEnv` を使う。TLS の受け口のポートは `fakeoidc.TLSPort`(443)。イメージは distroless の nonroot 版で、root でない利用者が 443 を受けられるのは Docker の既定の設定(コンテナの `net.ipv4.ip_unprivileged_port_start=0`)に頼っているので、5.9 でコンテナの中で 443 を受けられることを確かめる
- 5.2 で、design.md に名前の無い段の欄を次の形にした。Redis の段は `redis: {del: [キー], set: [{key, value, ttl_seconds}]}`(ttl_seconds は1以上)、期限切れの段は `expire: {cookie: <名前>}` か `expire: {var: <名前>}`、絶対の URL の段は `request.url`。種類は `Step.Kind()` で引く。`oidc_users` の型は harness の `OIDCUsers` で、json の名前は fakeoidc の `GoogleUser` `GitHubUser` と同じ
- 5.8 で、版に送る段だけを数えて版に割り当てるように直すのは `cross.go` の段の割り当てだけでなく、`compareenv.go` と `coverage.go` の、どの段にも `Request.Method` と `Request.Path` で操作を引く箇所も含む
- 5.3 で、取り出しの元 `mail:` のメールは `Session.SetMailReader` で渡す部品から読む。5.8 で、compare と cross と perf の動かし方から、版ごとの偽の AWS のメール(compareenv の `records(ctx, version, "emails", ...)`)を読む部品を渡す。部品が無い Session は、`mail:` を持つ段を送らずに失敗する
- 5.4 で、絶対の URL の段の `request.url` への差し込みには、capture.go の `Session.expand` を使う(パスとヘッダと本文の差し込みと同じ誤りの文になる)
- 5.8 で、compare と cross と perf の動かし方は、筋書きごとに初めに stack.go の `resetOIDC` を呼び、筋書きの `oidc_users` を `setOIDCUsers` で登録する(5.4 で処理だけを足し、呼び出しはまだ無い)
- 5.8 で、段の種類で送り方を選ぶ。版の段は `Send`、絶対の URL の段は steps.go の `SendAbsolute` にテストの処理から届く fakeoidc のアドレス(`oidcURL`)を渡す、Redis の段は `ApplyRedis` にその版の Redis の部品を渡す。絶対の URL の段は版の Cookie を送らず、Set-Cookie も覚えず、応答を比べない
- 5.8 で、値を期限切れにする段は expire.go の `Session.Expire(step, jwtKey)` を呼ぶ。`jwtKey` には stack.go の `jwtSecret`(両方の版に渡した JWT.Secret)を渡し、比べる動かし方では版ごとの Session で1回ずつ呼ぶ。compare_test.go に関数 `jwt` があるので、harness のテストで golang-jwt を読むときは別名(expire_test.go では `gojwt`)を付ける
- 5.8 で、比べる動かし方は、段ごとに `CompareResponse` を `CompareMail` より先に呼ぶ。`CompareResponse` が `Response.Received`(`Send` が入れる応答の時刻)を正規化の基準の時刻に写し、メールの `lexp` はその時刻との差で比べるためである。`Response` を手で作るときは `Received` も入れる
- 5.8 で、測る動かし方にメールを読む部品を渡すときは、perf.go の `prepare` が作る Session に `SetMailReader` を呼ぶ。prepare_each が真の筋書きでは、`MeasureLatency` が回ごとに `prepare` で新しい Session を作るので、初めの Session だけに渡すと2回目から `mail:` の取り出しが誤りになる
- 5.8 で、段の種類による動かし方は steps.go の `stepTools.send` にまとめた。絶対の URL の段の expect の status は `SendAbsolute` が確かめて誤りを返すので、呼び出し元で `CheckExpect` を重ねない。版をまたぐ動かし方と測る動かし方は、最後の段が版に送る段でない筋書きを誤りにする
- 5.8 で、測る動かし方は fakeoidc を、測る処理全体の初めと終わりに1回ずつだけ初めの状態に戻す。prepare_each が真の筋書きで、準備の段が fakeoidc の利用者を替えると、2回目からの回は替えたあとの利用者で始まる

## 完了条件(全タスク共通)

Claude は、どのタスクでも、タスクの箇条書きの欄を書いたうえで、次の4つを満たしたときにタスクを完了とする。

1. Claude は、タスクが満たす requirements.md の受入基準(要件の番号付きの項目)ごとに、それを確かめるテストのファイル名とテスト名を「受入基準とテストの対応」の行に書く。Claude は、確かめるテストの無い受入基準を残さない。
2. タスクで変えたファイルを使うテストが、すべて成功している。`1.` や `2.` の見出しのタスクを大きなまとまりと呼ぶ。大きなまとまりの最後のタスクでは、加えて、そのまとまりのタスクで変えた領域の verify のスキル(`/verify-frontend` `/verify-backend` `/verify-terraform`)が、すべて成功している。
3. Claude は、テストを飛ばす設定、アサーションの削除、カバレッジや lint の対象からの除外を足して、完了条件を満たしたように見せない。CI の escape-hatch の検査が、これらの追加を機械で見つける。
4. Claude は、新しく書いたテストについて、テストの対象のコードを一時的に壊してテストが失敗することを確かめる。Claude は、新しいテスト1件につき1か所だけを、作業フォルダの外の写しで壊し、そのテストだけを流す。壊した写しの作り方と流し方は、`.kiro/steering/tech.md` の「テストの完全性」に従う。
