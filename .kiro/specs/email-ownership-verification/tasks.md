# タスク

- [x] 1. 確認の状態を保存する列とドメインのモデルを作る
- [x] 1.1 users の表に2つの列を足すマイグレーションを作る

  Claude は、先にテスト `EmailVerificationColumnsMigrationTest` を書いて失敗することを確かめ、そのあとでマイグレーション `V7__add_email_verification_columns.sql` を足す。V7 は、users の表に `email_verified_at`(`TIMESTAMP NULL`)と `pending_email`(`VARCHAR(255) NULL`)を足すだけで、既存の列とデータを変えない。テストは、V6 まで進めたデータベースにアカウントの行と職務経歴書の行を入れ、V7 まで進めたあとで、その行が残り、`email_verified_at` と `pending_email` が NULL であることを確かめる。
  - 完了の確かめ方: `EmailVerificationColumnsMigrationTest` が通る。V7 の SQL から `email_verified_at` の列の追加を一時的に外すとテストが失敗し、戻すと通る
  - 受入基準とテストの対応: 要件5の受入基準1(前からあるアカウントのメールアドレスを確認前として扱う)は、`EmailVerificationColumnsMigrationTest` の「V6 の時点で入れたアカウントの email_verified_at が V7 のあとに NULL になる」で確かめる。要件5の受入基準2(アカウントと職務経歴書を消さない)は、同じテストの「V6 の時点で入れたアカウントと職務経歴書の行が V7 のあとも残る」で確かめる
  - _要件: 5.1, 5.2_

- [x] 1.2 ドメインのモデル User に確認の状態を持たせる

  Claude は、「User」の節のとおりに、ドメインのモデル `User` に欄 `emailVerifiedAt` と `pendingEmail` を足し、`isEmailVerified`、`createWithVerifiedEmail`、`verifyEmail`、`setPendingEmail`、`promotePendingEmail` を足す。Claude は、`changeTwoFactorAuthEnabled` の有効にする条件、`removeAuthProvider` の解除を断る条件、`delete` が `UserDeletedEvent` を積む条件を、「User」の節のとおりに変える。Claude は、`reconstruct` の検査を強めない。

  Claude は、`setEmail` を、呼ぶ側を直すタスク 4.7 で消す。

  Claude は、`reconstruct` を呼ぶ既存のコードを、足した2つの欄を渡す形に直す。`MyBatisUserRepository` は、このタスクでは2つの欄に null を渡し、ユーザーの保存で2つの列を読み書きするタスク 1.3 で、データベースから読んだ値を渡す。Claude は、テストの中で `reconstruct` を呼ぶ箇所では、確認済みのアカウントとして `emailVerifiedAt` に日時を渡す。
  - 完了の確かめ方: `UserTest` の足したテストと、backend の既存のテストがすべて通る。既存のテストには、2段階認証の有効化、外部連携の解除、退会を使うユースケースのテストも含む。確認前のアカウントに `UserDeletedEvent` を積むように一時的に戻すと、足したテストが失敗する
  - 受入基準とテストの対応: 次のテストで確かめる。
    - 要件4の受入基準1・2・3(設定待ちにする、確認で移す、置き換える)は、`UserTest` の「setPendingEmail は email の無いアカウントの pendingEmail を置き換える」「promotePendingEmail は pendingEmail を email に移し emailVerifiedAt を入れる」で確かめる
    - 要件3の受入基準4と要件7の受入基準2(確認前のメールアドレスを確認済みにする)は、「verifyEmail は emailVerifiedAt が null のときだけ日時を入れる」で確かめる
    - 要件10の受入基準1(退会のお知らせを送らない)は、「確認前のアカウントの delete は UserDeletedEvent を積まない」で確かめる
    - 要件10の受入基準2(2段階認証を有効にできるかを判断するときに、確認前と設定待ちのメールアドレスを無いものとして扱う)は、「確認前のアカウントの2段階認証の有効化を断る」で確かめる
    - 要件10の受入基準3(外部連携を解除できるかを判断するときに、確認前と設定待ちのメールアドレスを無いものとして扱う)は、「確認前のアカウントで外部連携が1つのときに解除を断る」で確かめる
  - _要件: 3.4, 4.1, 4.2, 4.3, 7.2, 7.3, 10.1, 10.2, 10.3_

- [x] 1.3 ユーザーの保存で2つの列を読み書きする

  Claude は、「MyBatisUserRepository と UserMapper」の節のとおりに、`UserDto`、`UserMapper`、`UserMapper.xml`、`MyBatisUserRepository` で、`email_verified_at` と `pending_email` を読み書きする。
  - 完了の確かめ方: `MyBatisUserRepositoryTest` で、`emailVerifiedAt` と `pendingEmail` を持つアカウントを保存して読み直すと、同じ値が返る。`UserMapper.xml` の `upsertUser` から `pending_email` を一時的に外すと、テストが失敗する。`upsertUser` は、users の表に行が無ければ行を足し、行があれば行を書き換える SQL の文である
  - 受入基準とテストの対応: 要件4の受入基準1・2(設定待ちのメールアドレスを保存し、確認で移す)と要件5の受入基準1(確認前のメールアドレスを確認前として読む)は、`MyBatisUserRepositoryTest` の「emailVerifiedAt と pendingEmail を保存して読み直すと同じ値が返る」「email_verified_at が NULL の行は確認前のアカウントとして読まれる」で確かめる
  - _要件: 4.1, 4.2, 5.1_

- [x] 2. 確認のリンクの部品と一時データの置き場所を作る
- [x] 2.1 確認のリンクのトークンを作り、読む部品を作る (並行可)

  Claude は、「EmailVerificationTokenCodec と JwtEmailVerificationTokenCodec」の節と「EmailVerificationPurpose」の節のとおりに、トークンの種類の列挙型、トークンの中身の record、トークンを作る部品と読む部品のインタフェースと、java-jwt の実装を作る。
  - 完了の確かめ方: `JwtEmailVerificationTokenCodecTest` が通る。`read` が、トークンをどの用途に使うかを示す値 `aud` を確かめないように一時的に変えると、テストが失敗する
  - 受入基準とテストの対応: 要件2の受入基準1(24時間と10分)は、`EmailVerificationPurposeTest` の「PASSWORD_RESET の期限は10分で、ほかの3つは24時間である」で確かめる。要件2の受入基準4・5(期限切れのリンクを見分ける)の前提は、`JwtEmailVerificationTokenCodecTest` の「lexp を過ぎたトークンも署名が正しければ中身を返す」で確かめる。`lexp` は、トークンに入れたリンクの期限である。トークンの偽造を受け付けないことは、「署名を変えたトークン、aud の違うトークン、アクセストークンの鍵で署名したトークンは空を返す」で確かめる
  - _要件: 2.1, 2.4, 2.5_
  - _対象の部品: EmailVerificationTokenCodec と JwtEmailVerificationTokenCodec, EmailVerificationPurpose_

- [x] 2.2 確認前の登録の置き場所を作る (並行可)

  Claude は、「PendingRegistrationStore と RedisPendingRegistrationStore」の節のとおりに、確認前の登録の record、置き場所のインタフェース、Redis の実装を作る。Redis のキーと有効期限は、「データの形」の「Redis のキー」の表のとおりにする。
  - 完了の確かめ方: `RedisPendingRegistrationStoreTest`(Testcontainers の Redis)が通る。`findByEmail` が新しい順に並べないように一時的に変えると、テストが失敗する
  - 受入基準とテストの対応: 要件1の受入基準4(同じメールアドレスの登録を2つ以上受け付ける)は、`RedisPendingRegistrationStoreTest` の「同じメールアドレスの登録を2つ置くと findByEmail が新しい順に2つ返す」で確かめる。要件1の受入基準6(24時間で消え、送り直すと延びる)は、「save の有効期限が24時間になる」「extend で有効期限を置き直す」「消えた登録の ID を findByEmail が集合から取り除く」で確かめる
  - _要件: 1.4, 1.6_
  - _対象の部品: PendingRegistrationStore と RedisPendingRegistrationStore_

- [x] 2.3 最新のリンクの ID の置き場所を作る (並行可)

  Claude は、「EmailVerificationCurrentTokenStore と RedisEmailVerificationCurrentTokenStore」の節のとおりに、インタフェースと Redis の実装を作る。`consume` は、置いてある最新の `jti` と渡された `jti` を比べることと、置いてある `jti` を消すことを、Lua スクリプト1つで行う。`jti` は、リンクごとに作る ID である。
  - 完了の確かめ方: `RedisEmailVerificationCurrentTokenStoreTest`(Testcontainers の Redis)が通る。`consume` が値を比べずに消すように一時的に変えると、テストが失敗する
  - 受入基準とテストの対応: 要件2の受入基準2(1回だけ使える)は、`RedisEmailVerificationCurrentTokenStoreTest` の「同じ jti の consume は1回目だけ true を返す」で確かめる。要件2の受入基準3(新しいメールで前のリンクが使えなくなる)は、「put で置き換えたあとは前の jti の consume が false を返す」で確かめる
  - _要件: 2.2, 2.3_
  - _対象の部品: EmailVerificationCurrentTokenStore と RedisEmailVerificationCurrentTokenStore_

- [x] 2.4 同じメールアドレスへの送信を1分に1回に抑える部品を作る (並行可)

  Claude は、「EmailVerificationSendLimiter と RedisEmailVerificationSendLimiter」の節のとおりに、インタフェースと Redis の実装を作る。
  - 完了の確かめ方: `RedisEmailVerificationSendLimiterTest`(Testcontainers の Redis)が通る。`tryAcquire` を `SET NX` を使わない形に一時的に変えると、テストが失敗する
  - 受入基準とテストの対応: 要件2の受入基準6(1分に1回まで)は、`RedisEmailVerificationSendLimiterTest` の「同じメールアドレスの2回目の tryAcquire は60秒の間 false を返す」「release のあとは tryAcquire が true を返す」で確かめる
  - _要件: 2.6_
  - _対象の部品: EmailVerificationSendLimiter と RedisEmailVerificationSendLimiter_

- [x] 2.5 確認のメールの通知と文面を作る (並行可)

  Claude は、「EmailVerificationNotification と email-verification.ftl」の節のとおりに、通知の record と文面のテンプレートを作り、`SesFreeMarkerNotificationDispatcher` に確認のメールの分岐を足す。
  - 完了の確かめ方: `SesFreeMarkerNotificationDispatcherTest` で、確認のメールの件名が「【{siteName}】メールアドレスの確認」になり、本文に確認のリンクとリンクの期限が入る
  - 受入基準とテストの対応: 要件1の受入基準1・要件4の受入基準1・要件9の受入基準1(確認のメールを送る)は、`SesFreeMarkerNotificationDispatcherTest` の「EmailVerificationNotification を渡すと確認のメールの件名と本文で送る」で確かめる
  - _要件: 1.1, 4.1, 9.1_
  - _対象の部品: EmailVerificationNotification と email-verification.ftl_

- [x] 2.6 確認のメールを送る部品を作る

  Claude は、「EmailVerificationMailer」の節のとおりに、1分の制限を確かめ、トークンを作り、最新の `jti` を置き、確認のメールを送る部品を作る。リンクは、トークンを URL の `#` のあとに置いた形にする。
  - 完了の確かめ方: `EmailVerificationMailerTest` が通る。送信に失敗したときに `release` を呼ばないように一時的に変えると、テストが失敗する
  - 受入基準とテストの対応: 次のテストで確かめる。
    - 要件2の受入基準3(新しいメールで前のリンクが使えなくなる)は、`EmailVerificationMailerTest` の「送るたびに最新の jti を置き換える」で確かめる
    - 要件2の受入基準6(同じメールアドレスへの確認のメールは1分に1回まで送る)は、「tryAcquire が false なら、トークンも通知も作らずに RATE_LIMITED を返す」で確かめる
    - 送信に失敗したときにやり直せることは、「送信に失敗したら release と clear を呼んで例外を返す」で確かめる
    - リンクの期限は、「PASSWORD_RESET のリンクの lexp は10分後になる」で確かめる
  - _要件: 2.1, 2.3, 2.6_
  - _依存: 2.1, 2.3, 2.4, 2.5_

- [x] 3. 確認のリンクを受け付ける流れを作る
- [x] 3.1 リンクの状態を決める部品を作る

  Claude は、「EmailVerificationLinkClassifier」の節と「確認のリンクの結果の決め方」の図のとおりに、読んだトークンの中身から `USABLE`、`ALREADY_VERIFIED`、`EXPIRED`、`REGISTRATION_GONE`、`INVALID` を決める部品を作る。
  - 完了の確かめ方: `EmailVerificationLinkClassifierTest` で、図の分岐ごとのテストが通る。`PENDING_EMAIL` で対象のメールアドレスを `email` と比べるように一時的に変えると、テストが失敗する
  - 受入基準とテストの対応: 要件2の受入基準4(期限切れか、新しいメールで使えなくなったリンク)は、`EmailVerificationLinkClassifierTest` の「lexp を過ぎたリンクは EXPIRED」「jti が最新でないリンクは EXPIRED」で確かめる。要件2の受入基準4のうち登録が消えたときは、「確認前の登録が無い REGISTRATION のリンクは REGISTRATION_GONE」で確かめる。要件2の受入基準5(確認を済ませたあとのリンクを押すと、確認がすでに済んでいることを出す)は、「sub のアカウントが email を確認済みで持てば ALREADY_VERIFIED」で確かめる。`sub` は、トークンに入れた、確認前の登録かアカウントの ID である
  - _要件: 2.2, 2.3, 2.4, 2.5_

- [x] 3.2 確認を済ませたときの書き込みを作る

  Claude は、「EmailVerificationCompletion」の節のとおりに、`completeRegistration`、`verifyAccountEmail`、`promotePendingEmail` を、それぞれ1つのトランザクションで行う部品を作る。
  - 完了の確かめ方: `EmailVerificationCompletionTest` が通る。`completeRegistration` で `register()` を呼ばないように一時的に変えると、テストが失敗する
  - 受入基準とテストの対応: 要件1の受入基準2(登録と同じ内容でアカウントを作る)と受入基準3(登録完了のお知らせ)は、`EmailVerificationCompletionTest` の「completeRegistration は登録と同じ ID とメールアドレスとパスワードとユーザー名で確認済みのアカウントを保存し、UserRegisteredEvent を発行する」で確かめる。要件3の受入基準4と要件9の受入基準2の確認は、「verifyAccountEmail はトークンの email と同じアカウントの email を確認済みにする」で確かめる。要件4の受入基準2は、「promotePendingEmail は pending_email がトークンの email と同じときだけ移す」で確かめる
  - _要件: 1.2, 1.3, 3.4, 4.2, 9.2_

- [x] 3.3 確認のリンクを受け付けるユースケースを作る

  Claude は、「VerifyEmailUseCase」の節のとおりに、トークンを読み、リンクの状態を決め、最新の `jti` を消せたときに確認を済ませたときの書き込みを `EmailVerificationCompletion` に任せるユースケースと、結果の列挙型と DTO を作る。`PASSWORD_RESET` のリンクでは、このユースケースは、パスワードの再設定のトークンを、リンクの期限までの残りの時間を有効期限にして置く。
  - 完了の確かめ方: `VerifyEmailUseCaseTest` が通る。一意の制約で失敗したときにアカウントを読み直さないように一時的に変えると、テストが失敗する
  - 受入基準とテストの対応: 次のテストで確かめる。
    - 要件1の受入基準2(確認を済ませたら、登録のメールアドレスとパスワードとユーザー名でアカウントを作る)は、`VerifyEmailUseCaseTest` の「REGISTRATION のリンクで登録を完了し、登録と ID の集合の中の ID を消して VERIFIED を返す」で確かめる
    - 要件1の受入基準5(確認のリンクを押したときに、登録のメールアドレスをすでにアカウントが持っていれば、アカウントを作らない)と要件4の受入基準5(確認のリンクを押したときに、そのメールアドレスをすでにほかのアカウントが持っていれば、アカウントに付けない)は、「一意の制約で失敗し、sub のアカウントが email を持たなければ EMAIL_TAKEN を返す」で確かめる
    - 要件2の受入基準2(確認のリンクは1回だけ使える)は、「最新の jti を消せなければ1回だけやり直し、2回目は ALREADY_VERIFIED か INVALID を返す」で確かめる
    - 要件9の受入基準2(パスワードの再設定を求めたときの確認のリンクを受け付けたら、続けてパスワードの再設定の画面を出す)は、「PASSWORD_RESET のリンクで確認を済ませ、PASSWORD_RESET_READY と再設定のトークンを返す」「再設定のトークンの有効期限は lexp までの残りである」で確かめる
  - _要件: 1.2, 1.5, 2.2, 2.5, 3.4, 4.2, 4.5, 9.2_

- [x] 3.4 使えなくなったリンクから送り直すユースケースを作る

  Claude は、「ResendEmailVerificationUseCase」の節のとおりに、リンクの状態が `EXPIRED` のときだけ、同じ宛先、同じ対象、同じ種類で確認のメールを送り直すユースケースを作る。
  - 完了の確かめ方: `ResendEmailVerificationUseCaseTest` が通る。`RATE_LIMITED` のときにも登録の有効期限を延ばすように一時的に変えると、テストが失敗する
  - 受入基準とテストの対応: 次のテストで確かめる。
    - 要件2の受入基準4(使えなくなったリンクから同じ確認のための新しい確認のメールを送り、パスワードの再設定のリンクなら送り直したリンクも10分だけ使える)は、`ResendEmailVerificationUseCaseTest` の「EXPIRED のリンクから同じ purpose で send を呼ぶ」「EXPIRED でないリンクでは UseCaseException を投げる」で確かめる
    - 要件1の受入基準6(確認前の登録は、最後に送った確認のリンクの期限が切れたときに消す)は、「SENT のときだけ REGISTRATION の登録の有効期限を延ばす」で確かめる
    - 要件2の受入基準6(同じメールアドレスへの確認のメールは1分に1回まで送る)は、「RATE_LIMITED なら1分の文の UseCaseException を投げる」で確かめる
  - _要件: 1.6, 2.4, 2.6_

- [x] 4. 確認前の登録と確認前のメールアドレスを扱う既存のユースケースを変える
- [x] 4.1 登録を受け付けるユースケースを変える

  Claude は、「UserRegistrationUseCase」の節のとおりに、登録を受け付けて確認前の登録を置き、確認のメールを送るように、`UserRegistrationUseCase` を変える。Claude は、`UserRegistrationController` の応答を本体なしの 202 にする。
  - 完了の確かめ方: `UserRegistrationUseCaseTest` と `UserRegistrationControllerTest` が通る。`UserRegistrationUseCase` は、登録を受け付けたときに、アカウントを users の表に保存しない
  - 受入基準とテストの対応: 次のテストで確かめる。
    - 要件1の受入基準1(登録したら確認のメールを送り、この時点ではアカウントを作らない)は、`UserRegistrationUseCaseTest` の「登録を受け付けると確認前の登録を24時間で置き、REGISTRATION の確認のメールを送り、アカウントを保存しない」で確かめる
    - 要件1の受入基準4(同じメールアドレスの確認前の登録があっても、別の登録を受け付ける)は、「同じメールアドレスの確認前の登録があっても受け付ける」で確かめる
    - 要件1の受入基準7(すでにアカウントが持つメールアドレスでは、今と同じく登録を断る)は、「users にあるメールアドレスでは今と同じ DomainException を投げる」で確かめる
    - 要件2の受入基準7(前の確認のメールから1分たっていなくても、登録を受け付け、登録したときにいつも出す文を出す)は、「RATE_LIMITED でも例外を投げない」と、`UserRegistrationControllerTest` の「登録すると 202 を返す」で確かめる
    - 送信の失敗は、「send が例外を投げたら置いた登録を消す」で確かめる
  - _要件: 1.1, 1.4, 1.6, 1.7, 2.7_

- [x] 4.2 確認がまだのときの 409 の応答を作る

  Claude は、「EmailNotVerifiedUseCaseException と AppExceptionHandler」の節のとおりに、`kind` を持つ例外と、`AppExceptionHandler` の 409 のハンドラと、`EmailNotVerifiedErrorResponse` を作る。
  - 完了の確かめ方: `AppExceptionHandlerTest` で、`EmailNotVerifiedUseCaseException` が 409 と `{message, errors, kind}` になり、ほかの `UseCaseException` が今と同じ 400 になる
  - 受入基準とテストの対応: 要件3の受入基準1・2(確認がまだであることを画面に出す材料)は、`AppExceptionHandlerTest` の「EmailNotVerifiedUseCaseException は 409 と kind を返す」で確かめる
  - _要件: 3.1, 3.2_

- [x] 4.3 ログインのユースケースを変える

  Claude は、「LoginUseCase」の節のとおりに、確認がまだのアカウントと確認前の登録で、パスワードが合ったときに `EmailNotVerifiedUseCaseException` を投げるように、`LoginUseCase` を変える。Claude は、既存のテストのアカウントを確認済みのメールアドレスで作るように直し、既存のテストのアサーションを変えない。
  - 完了の確かめ方: `LoginUseCaseTest` の足したテストと既存のテストがすべて通る。照らし合わせる確認前の登録の数を6件にすると、テストが失敗する
  - 受入基準とテストの対応: 次のテストで確かめる。
    - 要件3の受入基準1(確認前の登録のメールアドレスとパスワードが合っても、ログインさせず、確認がまだであることを出す)は、`LoginUseCaseTest` の「アカウントが無く、確認前の登録のパスワードが合えば kind が PENDING_REGISTRATION の例外を投げる」で確かめる
    - 要件3の受入基準2(確認前のメールアドレスとパスワードが合っても、ログインさせず、確認がまだであることを出す)は、「確認前のアカウントのパスワードが合えば kind が UNVERIFIED_ACCOUNT_EMAIL の例外を投げ、2段階認証に進まない」で確かめる
    - 要件3の受入基準3(パスワードが違えば、確認前でも今と同じ文を出す)は、「確認前でもパスワードが違えば今と同じ UseCaseException を投げる」で確かめる
    - 要件3の受入基準5(設定待ちのメールアドレスでは、今と同じ文を出し、ログインさせない)は、「設定待ちのメールアドレスでは今と同じ UseCaseException を投げる」で確かめる
    - 要件3の受入基準4(確認を済ませたアカウントのログインは、今と同じに動く)は、「確認済みのアカウントは今と同じくログインする」で確かめる
  - _要件: 3.1, 3.2, 3.3, 3.4, 3.5_

- [x] 4.4 ログインの画面から確認のメールを送るユースケースを作る (並行可)

  Claude は、「ResendEmailVerificationForLoginUseCase」の節のとおりに、入力されたメールアドレスとパスワードを照らし合わせ、合えば確認のメールを送るユースケースと、その入力の command を作る。
  - 完了の確かめ方: `ResendEmailVerificationForLoginUseCaseTest` が通る。パスワードを照らし合わせずに送るように一時的に変えると、テストが失敗する
  - 受入基準とテストの対応: 次のテストで確かめる。
    - 要件3の受入基準1(確認前の登録のメールアドレスとパスワードが合えば、確認のメールを送り直すボタンを出す)は、`ResendEmailVerificationForLoginUseCaseTest` の「確認前の登録のパスワードが合えば REGISTRATION の確認のメールを送り、SENT のときだけ有効期限を延ばす」で確かめる
    - 要件3の受入基準2(確認前のメールアドレスとパスワードが合えば、ボタンを押すと確認のメールを送る)は、「確認前のアカウントのパスワードが合えば ACCOUNT_EMAIL の確認のメールを送る」で確かめる
    - 要件3の受入基準3(パスワードが違えば、確認前でも今と同じ文を出す)は、「パスワードが違えばログインと同じ UseCaseException を投げる」で確かめる
    - 要件2の受入基準6(同じメールアドレスへの確認のメールは1分に1回まで送る)は、「RATE_LIMITED なら1分の文の UseCaseException を投げる」で確かめる
  - _要件: 1.6, 2.6, 3.1, 3.2, 3.3_
  - _対象の部品: ResendEmailVerificationForLoginUseCase_
  - _依存: 2.2, 2.6_

- [x] 4.5 ユーザー設定の画面から確認のメールを送るユースケースを作る (並行可)

  Claude は、「SendAccountEmailVerificationUseCase」の節のとおりに、ログインしている利用者の設定待ちのメールアドレスか確認前のメールアドレスに確認のメールを送るユースケースを作る。
  - 完了の確かめ方: `SendAccountEmailVerificationUseCaseTest` が通る。`pending_email` より `email` を先に見るように一時的に変えると、テストが失敗する
  - 受入基準とテストの対応: 要件6の受入基準2(ユーザー設定の画面のボタンで、確認前のメールアドレスか設定待ちのメールアドレスに確認のメールを送る)は、`SendAccountEmailVerificationUseCaseTest` の「pending_email があれば PENDING_EMAIL で送る」「pending_email が無く email が確認前なら ACCOUNT_EMAIL で送る」「確認が必要なメールアドレスが無ければ UseCaseException を投げる」で確かめる。要件2の受入基準6(同じメールアドレスへの確認のメールは1分に1回まで送る)は、「RATE_LIMITED なら1分の文の UseCaseException を投げる」で確かめる
  - _要件: 2.6, 6.2_
  - _対象の部品: SendAccountEmailVerificationUseCase_
  - _依存: 2.6_

- [x] 4.6 パスワードの再設定を求めるユースケースを変える (並行可)

  Claude は、「RequestPasswordResetUseCase」の節のとおりに、確認前のアカウントには `PASSWORD_RESET` の確認のメールを送るように、`RequestPasswordResetUseCase` を変える。Claude は、既存のテストのアカウントを確認済みのメールアドレスで作るように直し、既存のテストのアサーションを変えない。
  - 完了の確かめ方: `RequestPasswordResetUseCaseTest` の足したテストと既存のテストがすべて通る。確認前のアカウントにパスワードの再設定のメールを送るように一時的に戻すと、テストが失敗する
  - 受入基準とテストの対応: 要件9の受入基準1(確認前のメールアドレスでパスワードの再設定を求めると、再設定のメールの代わりに確認のメールを送る)は、`RequestPasswordResetUseCaseTest` の「確認前のアカウントには PASSWORD_RESET の確認のメールを送り、再設定のメールを送らない」で確かめる。要件9の受入基準3(確認前の登録のメールアドレスと設定待ちのメールアドレスではメールを送らない)は、「確認前の登録のメールアドレスと設定待ちのメールアドレスでは何も送らない」で確かめる。要件9の受入基準4・5(どの場合も、前の確認のメールから1分たっていないときも、画面に同じ文を出す)は、「確認済み、確認前、RATE_LIMITED、アカウントが無いのどの場合も例外を投げない」で確かめる
  - _要件: 9.1, 9.3, 9.4, 9.5_
  - _対象の部品: RequestPasswordResetUseCase_
  - _依存: 2.6_

- [x] 4.7 メールアドレスとパスワードを設定するユースケースを変える

  Claude は、「SetEmailAndPasswordUseCase」の節のとおりに、入力されたメールアドレスを設定待ちにし、確認のメールを送るように、`SetEmailAndPasswordUseCase` を変える。パスワードを持つアカウントでは、`SetEmailAndPasswordUseCase` は、入力の `currentPassword` を今のパスワードと照らし合わせる。Claude は、`SetEmailAndPasswordRequest` と `SetEmailAndPasswordCommand` に欄 `currentPassword` を足し、使わなくなった `User.setEmail` を消す。
  - 完了の確かめ方: `SetEmailAndPasswordUseCaseTest` が通る。`currentPassword` を照らし合わせないように一時的に変えると、テストが失敗する
  - 受入基準とテストの対応: 次のテストで確かめる。
    - 要件4の受入基準1(設定したメールアドレスを設定待ちにして確認のメールを送り、パスワードはその時点で設定する)は、`SetEmailAndPasswordUseCaseTest` の「メールアドレスを設定待ちにし、パスワードを設定し、PENDING_EMAIL の確認のメールを送り、email を変えない」で確かめる
    - 要件4の受入基準3(確認を済ませる前に設定し直すと、設定待ちのメールアドレスを置き換え、パスワードを持つアカウントでは今のパスワードが合うときだけ受け付ける)は、「パスワードを持つアカウントで currentPassword が合えば設定待ちのメールアドレスを置き換え、前のリンクを使えなくする」「currentPassword が無いときと合わないときは UseCaseException を投げ、何も保存しない」で確かめる
    - 要件4の受入基準4(すでにアカウントが持つメールアドレスでは設定を断る)は、「users にあるメールアドレスでは DomainException を投げる」で確かめる
    - 要件4の受入基準6(前の確認のメールから1分たっていなくても、設定待ちのメールアドレスにし、いつもと同じ文を出す)は、「RATE_LIMITED でも例外を投げない」で確かめる
  - _要件: 4.1, 4.3, 4.4, 4.6_

- [x] 4.8 ユーザーの情報に確認の状態を載せる (並行可)

  Claude は、「GetUserInfoUseCase と UserInfoResponse」の節のとおりに、`UserInfoUseCaseDto` と `UserInfoResponse` に `emailVerified` と `pendingEmail` を足し、`GetUserInfoUseCase` で値を入れる。
  - 完了の確かめ方: `GetUserInfoUseCaseTest` と `GetUserInfoControllerTest` で、`GET /api/users/me` の応答に `emailVerified` と `pendingEmail` が入る
  - 受入基準とテストの対応: 要件6の受入基準1(確認待ちとして見せる材料)は、`GetUserInfoUseCaseTest` の「確認前のアカウントは emailVerified が false で email を返す」「設定待ちのメールアドレスを pendingEmail で返す」で確かめる
  - _要件: 6.1_
  - _対象の部品: GetUserInfoUseCase と UserInfoResponse_
  - _依存: 1.2_

- [x] 5. 外部連携のログインで確認の状態を扱う
- [x] 5.1 GitHub が確かめたメールアドレスだけを受け取る (並行可)

  Claude は、「GithubOidcProvider」の節のとおりに、`GithubOidcProvider` が、いつも `GET /user/emails` の `primary` と `verified` がどちらも true の要素だけを使うように変える。
  - 完了の確かめ方: `GithubOidcProviderTest` が通る。`verified` を見ないように一時的に変えると、テストが失敗する
  - 受入基準とテストの対応: 要件7の受入基準4(Google か GitHub が持ち主を確かめたと返さなかったメールアドレスを受け取らない)は、`GithubOidcProviderTest` の「verified が false の primary は email を null にする」「GET /user の email を使わない」「GET /user/emails の呼び出しに失敗したら email を null にする」で確かめる。要件7の受入基準3(新しいアカウントに、持ち主を確かめたメールアドレスを確認済みとして付ける)の前提は、「primary と verified が true の要素の email を返す」で確かめる
  - _要件: 7.3, 7.4_
  - _対象の部品: GithubOidcProvider_

- [x] 5.2 外部連携のログインのユースケースを変える

  Claude は、「OidcLoginUseCase、HandleOidcCallbackUseCase、OidcCallbackController」の節のとおりに、`OidcLoginUseCase` の分岐を変え、確認がまだのアカウントへ結び付けないときの例外 `UnverifiedEmailAccountUseCaseException` を作る。Claude は、既存のテストのアカウントを確認済みのメールアドレスで作るように直し、既存のテストのアサーションを変えない。
  - 完了の確かめ方: `OidcLoginUseCaseTest` の足したテストと既存のテストがすべて通る。確認前のアカウントにも結び付けるように一時的に戻すと、テストが失敗する
  - 受入基準とテストの対応: 次のテストで確かめる。
    - 要件7の受入基準1(Google か GitHub が結び付いたアカウントには、今と同じくログインさせ、返したメールアドレスを付けない)は、`OidcLoginUseCaseTest` の「結び付いたアカウントにログインさせ、返したメールアドレスを付けない」で確かめる
    - 要件7の受入基準2(返したメールアドレスがアカウントの確認前か設定待ちのメールアドレスと同じなら、確認済みのメールアドレスにする)は、「email が同じ確認前のアカウントを確認済みにする」「pendingEmail が同じでほかのアカウントが持たなければ移す」「ほかのアカウントが持っていれば設定待ちのまま残してログインさせる」で確かめる
    - 要件7の受入基準3(新しいアカウントに、持ち主を確かめたメールアドレスを確認済みとして付ける)は、「新しいアカウントを確認済みのメールアドレスで作る」で確かめる
    - 要件7の受入基準4(持ち主を確かめたと返さなかったメールアドレスを受け取らず、メールアドレスを持たないアカウントを作る)は、「email が null ならメールアドレスの無いアカウントを作る」で確かめる
    - 要件7の受入基準5(同じメールアドレスの確認前の登録があっても、Google か GitHub でログインした利用者のアカウントを作る)は、「同じメールアドレスの確認前の登録があってもアカウントを作る」で確かめる
    - 要件8の受入基準1(確認前のメールアドレスのアカウントには Google か GitHub を結び付けず、ログインさせない)は、「確認前のアカウントと同じメールアドレスでは UnverifiedEmailAccountUseCaseException を投げて結び付けない」で確かめる
    - 要件8の受入基準3(メールアドレスが確認済みになったあとは、今と同じく結び付ける)は、「確認済みのアカウントには今と同じく結び付ける」で確かめる
  - _要件: 7.1, 7.2, 7.3, 7.4, 7.5, 8.1, 8.3_

- [x] 5.3 結び付けを断ったときの戻り先を作る

  Claude は、`OidcCallbackError` に `UNVERIFIED_ACCOUNT_EMAIL` を足し、`HandleOidcCallbackUseCase` が `UnverifiedEmailAccountUseCaseException` を今の `catch (Exception e)` より先に受けるようにする。Claude は、`OidcCallbackController` が、その失敗のときだけ `/login?error=unverified_email` へ送るようにする。
  - 完了の確かめ方: `HandleOidcCallbackUseCaseTest` と `OidcCallbackControllerTest` が通る。ほかの失敗の送り先は今のままである
  - 受入基準とテストの対応: 要件8の受入基準1・2(確認前のメールアドレスのアカウントに結び付けずにログインさせず、先に確認を済ませるよう案内する文を出す)は、`HandleOidcCallbackUseCaseTest` の「UnverifiedEmailAccountUseCaseException なら UNVERIFIED_ACCOUNT_EMAIL の失敗を返す」と、`OidcCallbackControllerTest` の「UNVERIFIED_ACCOUNT_EMAIL なら /login?error=unverified_email へ送る」で確かめる
  - _要件: 8.1, 8.2_

- [x] 6. 確認の API を作る
- [x] 6.1 確認と送り直しの API を作る

  Claude は、`VerifyEmailController`、`ResendEmailVerificationController`、`ResendEmailVerificationForLoginController` と、その要求と応答の DTO を作る。Claude は、`EmailVerificationTokenRequest` の `token` に、`@NotBlank` と、長さを2048文字までに限る検査を付ける。`VerifyEmailController` は、どの結果でも 200 を返す。
  - 完了の確かめ方: 3つの controller のテストが通る。ログインしていない要求で、3つの API が 401 にならない
  - 受入基準とテストの対応: 要件2の受入基準4・5(使えなくなったリンクと確認を済ませたあとのリンクを押したときの表示と送り直し)と要件9の受入基準2(確認のリンクを受け付けたら、続けてパスワードの再設定の画面を出す)は、`VerifyEmailControllerTest` の「結果と再設定のトークンを 200 で返す」と、`ResendEmailVerificationControllerTest` の「送り直すと 204 を返す」で確かめる。要件3の受入基準1・2(確認がまだの利用者に、ログインの画面から確認のメールを送れるようにする)は、`ResendEmailVerificationForLoginControllerTest` の「メールアドレスとパスワードで送ると 204 を返す」で確かめる。トークンの長さの検査は、「2049文字のトークンは 400 を返す」で確かめる
  - _要件: 2.4, 2.5, 3.1, 3.2, 9.2_
  - _依存: 3.3, 3.4, 4.4_

- [x] 6.2 ユーザー設定の画面から送る API を作る (並行可)

  Claude は、`SendAccountEmailVerificationController`(`POST /api/users/me/email-verification`)を作る。
  - 完了の確かめ方: `SendAccountEmailVerificationControllerTest` で、ログインした利用者の要求に 204 を返し、ログインしていない要求に 401 を返す
  - 受入基準とテストの対応: 要件6の受入基準2(ユーザー設定の画面のボタンで確認のメールを送る)は、`SendAccountEmailVerificationControllerTest` の「ログインした利用者のアカウントに確認のメールを送り 204 を返す」で確かめる
  - _要件: 6.2_
  - _対象の部品: SendAccountEmailVerificationUseCase_
  - _依存: 4.5_

- [x] 7. 画面を作る
- [x] 7.1 frontend の利用者の型に確認の状態を足す

  Claude は、frontend の `User` の型に、欄 `emailVerified` と `pendingEmail` を足す。Claude は、テストの中で利用者のデータを作る既存の箇所に、確認済みのアカウントとして `emailVerified: true` と `pendingEmail: null` を足す。
  - 完了の確かめ方: frontend の型の検査と既存のテストがすべて通る
  - 受入基準とテストの対応: このタスクは型を揃える作業で、受入基準を満たさない。そのため、`_要件:_` の行を書かない

- [x] 7.2 確認のリンクの画面を作る

  Claude は、「VerifyEmail ページと EmailVerificationContainer」の節のとおりに、確認と送り直しの API を呼ぶ関数とフックと、`EmailVerificationContainer` と、ページ `VerifyEmail` を作る。Claude は、経路 `paths.email.verify` と、`AppRouter` のどのレイアウトにも属さない経路を足し、ページを `pages/index` から公開する。画面は、`location.hash` からトークンを取り、URL から `#` 以降を消し、`result` ごとに文とボタンを出す。
  - 完了の確かめ方: `EmailVerificationContainer.test.tsx` と `useVerifyEmail.test.ts` と `AppRouter.test.tsx` が通る。確認のリンクの画面は、出し直しても、確認の API を2回呼ばない
  - 受入基準とテストの対応: 次のテストで確かめる。
    - 要件1の受入基準2(確認前の登録の確認を済ませると、アカウントを作り、ログインの画面へ進めるようにする)・要件3の受入基準4(前からあるアカウントの確認を済ませると、ログインの画面へ進めるようにする)・要件4の受入基準2(設定待ちのメールアドレスの確認を済ませると、アカウントのメールアドレスにする)は、`EmailVerificationContainer.test.tsx` の「VERIFIED では確認が済んだこととログインの画面へ進むボタンを出す」で確かめる
    - 要件9の受入基準2(確認のリンクを受け付けたら、続けてパスワードの再設定の画面を出す)は、「PASSWORD_RESET_READY ではパスワードの再設定の入力欄を出し、再設定のトークンで送る」で確かめる
    - 要件2の受入基準4(使えなくなったリンクでは送り直すボタンを出し、確認前の登録が消えていればもう一度登録するよう案内する)は、「EXPIRED では送り直すボタンを出し、押すとトークンで送り直す」「REGISTRATION_GONE では登録し直す案内と登録の画面へのリンクを出す」で確かめる
    - 要件2の受入基準5(確認を済ませたあとのリンクを押すと、確認がすでに済んでいることを出す)は、「ALREADY_VERIFIED では確認がすでに済んだことを出す」で確かめる
    - 要件1の受入基準5・要件4の受入基準5(確認のリンクを押したときに、そのメールアドレスをすでにアカウントが持っていれば、使えないことを出す)は、「EMAIL_TAKEN ではこのメールアドレスは使えないことを出す」で確かめる
    - ログインしていない利用者が確認のリンクを開けることは、`AppRouter.test.tsx` の「/email/verify はログインしていなくても確認のリンクの画面を出す」で確かめる
  - _要件: 1.2, 1.5, 2.4, 2.5, 3.4, 4.2, 4.5, 9.2_
  - _依存: 7.1_

- [x] 7.3 ログインの画面に確認がまだであることを出す

  Claude は、「LoginContainer と EmailVerificationNotice」の節のとおりに、ログインの画面から確認のメールを送る関数とフックと、`EmailVerificationNotice` を作り、`LoginContainer` が 409 の `kind` と、クエリ `error=unverified_email` を受けて、ログインの画面に出す案内を出し分けるようにする。
  - 完了の確かめ方: `LoginContainer.test.tsx` と `useResendEmailVerificationForLogin.test.ts` が通る。クエリ `error` にほかの値を入れても、画面にその文字列が出ない
  - 受入基準とテストの対応: 次のテストで確かめる。
    - 要件3の受入基準1(確認前の登録では、確認がまだであることと送り直すボタンを出す)は、`LoginContainer.test.tsx` の「409 の PENDING_REGISTRATION では確認がまだであることと送り直すボタンを出す」で確かめる
    - 要件3の受入基準2(確認前のメールアドレスでは、確認がまだであることと確認のメールを送るボタンを出す)は、「409 の UNVERIFIED_ACCOUNT_EMAIL では確認のメールを送るボタンを出し、押すと入力欄のメールアドレスとパスワードで送る」で確かめる
    - 要件3の受入基準3(パスワードが違えば、今と同じ文を出し、確認がまだであることを出さない)は、「400 では今と同じ文を出し、確認がまだであることを出さない」で確かめる
    - 要件8の受入基準2(そのメールアドレスのアカウントがあることと、先に確認を済ませるよう案内する文を出す)は、「error=unverified_email のときだけ決まった案内の文を出す」で確かめる
    - 要件2の受入基準6(前の確認のメールから1分たつ前に送り直しを求めると、少し待ってから求め直すよう案内する文を出す)は、「1分たつ前に送ったときの 400 の文を ErrorBanner が出す」で確かめる
  - _要件: 2.6, 3.1, 3.2, 3.3, 8.2_

- [x] 7.4 登録の画面の文を変える (並行可)

  Claude は、`useUserRegister` が、成功したときに、確認のメールを送ったことと、メールの中のリンクを押すよう案内する文をトーストで出し、ログインの画面へ移るようにする。
  - 完了の確かめ方: `useUserRegister.test.ts` で、202 の応答のあとに決まった文のトーストが出て、ログインの画面へ移る
  - 受入基準とテストの対応: 要件1の受入基準1(登録したら、確認のメールを送ったことと、リンクを押すよう案内する文を出す)と要件2の受入基準7(前の確認のメールから1分たっていなくても、登録したときにいつも出す文を出す)は、`useUserRegister.test.ts` の「登録が 202 で終わると確認のメールを送ったことを伝える文を出す」で確かめる。1分の制限で送らなかったときも backend は同じ 202 を返すので、画面の文は同じになる
  - _要件: 1.1, 2.7_
  - _対象の部品: useUserRegister_

- [x] 7.5 ユーザー設定の判断を確認の状態で行う (並行可)

  Claude は、「EmailVerificationStatus、userSettingRules、userSettingMessages、SettingUserContainer、ChangePasswordContainer」の節と「useUserRegister、useSetEmailAndPassword、useUserState、SetEmailAndPasswordContainer」の節のとおりに、`useUserState` に状態 `PASSWORD_WITH_PROVIDER` を足し、`userSettingRules` の2つの関数を `user` で判断する形に変え、`userSettingMessages`、`SettingUserContainer`、`ChangePasswordContainer` を変える。
  - 完了の確かめ方: `useUserState.test.ts`、`userSettingRules.test.ts`、`userSettingMessages.test.ts`、`ChangePasswordContainer.test.tsx` が通る
  - 受入基準とテストの対応: 次のテストで確かめる。
    - 要件10の受入基準2(2段階認証を有効にできるかを判断するときに、確認前と設定待ちのメールアドレスを無いものとして扱う)は、`userSettingRules.test.ts` の「emailVerified が false なら isTwoFactorDisabled が true を返す」で確かめる
    - 要件10の受入基準3(外部連携を解除できるかを判断するときに、確認前と設定待ちのメールアドレスを無いものとして扱う)は、「emailVerified が false で外部連携が1つなら isProviderRemovable が false を返す」で確かめる
    - 要件4の受入基準3(設定待ちのメールアドレスを置き換える画面へ進む)は、`useUserState.test.ts` の「メールアドレスが無くパスワードと外部連携があれば PASSWORD_WITH_PROVIDER を返す」と、`userSettingMessages.test.ts` の「PASSWORD_WITH_PROVIDER ではメールアドレスとパスワードの設定の画面へのリンクを返す」で確かめる
    - 要件10の受入基準3(外部連携を解除できるかを判断するときに、確認前と設定待ちのメールアドレスを無いものとして扱う)の画面の文は、`userSettingMessages.test.ts` の「確認前のアカウントで外部連携が1つなら、メールアドレスの確認が済んでいないため連携を解除できないことを出す」で確かめる
    - パスワードの変更の画面は、`ChangePasswordContainer.test.tsx` の「PASSWORD_WITH_PROVIDER ではログインの画面へ移さない」で確かめる
  - _要件: 4.3, 10.2, 10.3_
  - _対象の部品: useUserState、userSettingRules、userSettingMessages、SettingUserContainer、ChangePasswordContainer_
  - _依存: 7.1_

- [x] 7.6 メールアドレスとパスワードの設定の画面を変える

  Claude は、`SetEmailAndPasswordContainer` が `PROVIDER_ONLY` と `PASSWORD_WITH_PROVIDER` のときにメールアドレスの入力欄を出し、`PASSWORD_WITH_PROVIDER` のときに今のパスワードの入力欄も出すようにする。Claude は、`SetEmailAndPasswordForm` と `setEmailAndPassword` に欄 `currentPassword` を足し、`useSetEmailAndPassword` の成功の文を、確認のメールを送ったことと設定待ちであることを伝える文に変える。
  - 完了の確かめ方: `useSetEmailAndPassword.test.ts` と `userForms.integration.test.tsx` が通る
  - 受入基準とテストの対応: 要件4の受入基準1・6(設定したメールアドレスを設定待ちにして確認のメールを送り、1分たっていなくてもいつもと同じ文を出す)は、`useSetEmailAndPassword.test.ts` の「成功すると確認のメールを送ったことと設定待ちであることを伝える文を出す」で確かめる。要件4の受入基準3(パスワードを持つアカウントでは、今のパスワードが合うときだけ設定し直しを受け付ける)は、`userForms.integration.test.tsx` の「PASSWORD_WITH_PROVIDER では今のパスワードの入力欄を出し、currentPassword を送る」で確かめる
  - _要件: 4.1, 4.3, 4.6_
  - _依存: 7.5_

- [x] 7.7 ユーザー設定の画面に確認待ちの表示と送るボタンを出す

  Claude は、ユーザー設定の画面から確認のメールを送る関数とフックと、`EmailVerificationStatus` を `features/user` に作り、`SettingUserForm` に出す。`features/user` は `features/auth` を import しない。
  - 完了の確かめ方: `userParts.test.tsx` と `useSendEmailVerification.test.ts` が通る。確認済みでメールアドレスの設定待ちが無いアカウントでは、確認待ちの表示が出ない
  - 受入基準とテストの対応: 要件6の受入基準1(ユーザー設定の画面で、確認前と設定待ちのメールアドレスを確認待ちとして見せる)は、`userParts.test.tsx` の「pendingEmail があれば設定待ちのメールアドレスを確認待ちとして出す」「emailVerified が false なら email を確認待ちとして出す」で確かめる。要件6の受入基準2(ユーザー設定の画面のボタンで確認のメールを送る)は、「送るボタンを押すと POST /api/users/me/email-verification を呼び、トーストを出す」で確かめる
  - _要件: 6.1, 6.2_
  - _依存: 7.5_

- [x] 8. 全体の流れを確かめ、設計図を揃える
- [x] 8.1 登録から確認までの流れを結合テストで確かめる

  Claude は、Testcontainers の PostgreSQL と Redis を使う結合テスト `EmailVerificationFlowIntegrationTest` を作る。Claude は、メールの送信を、通知を受け取るテスト用の部品に置き換える。テストは、その部品が受け取った確認のメールのリンクから、トークンを読む。
  - 完了の確かめ方: `EmailVerificationFlowIntegrationTest` が通る
  - 受入基準とテストの対応: 次のテストで確かめる。
    - 要件1の受入基準1・2・3(登録したら確認のメールを送り、確認を済ませたらアカウントを作り、登録完了のお知らせのメールを送る)は、「登録、確認のリンク、アカウントの作成、登録完了のお知らせの順に通り、確認前の登録の段階では users に行が無い」で確かめる
    - 要件1の受入基準4・5(同じメールアドレスの確認前の登録は、先に確認を済ませたものだけからアカウントを作り、すでにアカウントが持つメールアドレスではアカウントを作らない)は、「同じメールアドレスの2つの確認前の登録を同時に確認すると、1つだけがアカウントになり、もう1つが EMAIL_TAKEN になる」で確かめる
    - 要件2の受入基準3・4(新しい確認のメールを送ると前のリンクが使えなくなり、使えなくなったリンクから同じ確認のための確認のメールを送り直せる)は、「新しい確認のメールを送ったあとに前のリンクが EXPIRED になり、送り直しで同じ purpose のリンクが届く」で確かめる
    - 要件9の受入基準1・2(確認前のメールアドレスでパスワードの再設定を求めると確認のメールを送り、リンクを受け付けたら続けてパスワードの再設定の画面を出す)と要件3の受入基準4(前からあるアカウントの確認を済ませると、そのあとのログインは今と同じに動く)は、「前からあるアカウントのパスワードの再設定の要求から、確認、パスワードの再設定、ログインまでが通り、再設定のトークンの有効期限がリンクの期限までの残りである」で確かめる
  - _要件: 1.1, 1.2, 1.3, 1.4, 1.5, 2.3, 2.4, 3.4, 9.1, 9.2_

- [x] 8.2 画面の表示を Playwright で確かめる

  Claude は、今の Playwright のテストと同じく backend を起動せず、`page.route` で API の応答を作り、確認のリンクの画面、ログインの画面、ユーザー設定の画面の表示を確かめるテストを `frontend/e2e/` に足す。
  - 完了の確かめ方: 作業の手元の frontend のコンテナにはブラウザが無く、`/verify-frontend` の lint と型の検査は `frontend/e2e/` を対象にしない。そのため、手元では足したテストを動かせない。`/kiro-impl` の確認役は、足したテストが3つの画面ごとに、`page.route` で返す応答と、画面に出る文とボタンの期待を持つことを、テストのファイルを読んで確かめる
  - 出荷のときの確かめ方: Claude は、`/ship` で PR を作ったあと、PR の CI の `e2e-smoke` で足したテストが通ることを確かめる。通らなければ、Claude はテストか画面を直して push し直し、直したことを PR 本文に書く
  - テストの対象を一時的に壊して失敗を確かめる完了条件の扱い: 手元でブラウザを動かせないので、Claude は、このタスクでは、テストの対象を一時的に壊してテストが失敗することを確かめない。3つの画面の文とボタンは、確認のリンクの画面を作るタスク 7.2、ログインの画面に確認がまだであることを出すタスク 7.3、ユーザー設定の画面に確認待ちの表示を出すタスク 7.7 の Vitest のテストが確かめている。Claude は、それらの Vitest のテストについて、テストの対象を一時的に壊してテストが失敗することを確かめている
  - 受入基準とテストの対応: 要件2の受入基準4・5(使えなくなったリンクと確認を済ませたあとのリンクを押したときに、画面に出す文とボタン)は、`email-verification.spec.ts` の「確認のリンクの画面が result ごとに決まった文とボタンを出す」で確かめる。要件3の受入基準1・2(確認がまだの利用者に、ログインの画面で確認がまだであることと確認のメールを送るボタンを出す)は、「ログインの画面が 409 の kind ごとに確認がまだである文とボタンを出す」で確かめる。要件6の受入基準1・2(ユーザー設定の画面で確認待ちのメールアドレスを見せ、確認のメールを送るボタンを出す)は、「ユーザー設定の画面が emailVerified と pendingEmail に応じて確認待ちの表示とボタンを出す」で確かめる
  - _要件: 2.4, 2.5, 3.1, 3.2, 6.1, 6.2_

- [x] 8.3 設計図を書き足す

  Claude は、`doc/DB設計/ER図.pu` に2つの列を、`doc/DB設計/Redis設計.md` に4つのキーを、`doc/クラス図/*.pu` に足した部品を、`doc/シーケンス図/ログインシーケンス.puml` に確認がまだのときの 409 を、`doc/画面設計/画面遷移図.drawio` に確認のリンクの画面を書き足す。Claude は、図のほかの部分と書式を変えない。
  - 完了の確かめ方: 5つの図に、この設計の変更が書き足されている。`git diff` で、図の変更が書き足した箇所だけである
  - 受入基準とテストの対応: このタスクは設計図をコードに揃える作業で、受入基準を満たさない。そのため、`_要件:_` の行を書かない

## 実装のメモ

- Claude は、frontend で新しく作る関数、フック、部品を、そのタスクの中で、それぞれの feature の `index.ts` から公開する
- 既存のテストが、確認前のアカウントを断る条件で失敗するときは、Claude は、テストのアカウントを確認済みのメールアドレスで作るように直す。Claude は、アサーションを消さず、変えない
- backend のテストで、`assertThatThrownBy` の中で戻り値のあるメソッドを呼ぶときは、Claude は、`User ignored = ...; assertThat(ignored).isNotNull();` のブロックの形で書く。戻り値を捨てる式の形で書くと、`./gradlew check` の spotbugsTest が失敗する
- 所有者が 2026-10-28 に決めたとおり、この spec では、確認役は、タスクごとには変えたファイルを使うテストだけを動かし、`./gradlew check` などの品質チェックの全体は、大きなまとまり(1. から 8. の見出しのタスク)の最後のタスクの確認で1回だけ動かす。Claude は、確認役に送る前に、変えたファイルを使うテストを `grep` で探して全部動かす
- `UserMapper` の SQL を変えるときは、`spring.flyway.target` で古い版の表を使うテストのうち、`UserMapper` を呼ぶもの(`UserMapperTest`、`ResumeMapperTest`)の版も上げる
- backend で、コンストラクタの中で例外を投げうる部品のクラスは、Claude は `final` にする。`final` でないと、`./gradlew check` の spotbugsMain が「作りかけの物が残る」という指摘で失敗する

## 完了条件(全タスク共通)

Claude は、どのタスクでも、タスクの箇条書きの欄を書いたうえで、次の4つを満たしたときにタスクを完了とする。

1. Claude は、タスクが満たす requirements.md の受入基準(要件の番号付きの項目)ごとに、それを確かめるテストのファイル名とテスト名を「受入基準とテストの対応」の行に書く。Claude は、確かめるテストの無い受入基準を残さない。
2. タスクで変えた領域の verify のスキル(`/verify-frontend` `/verify-backend` `/verify-terraform`)が、すべて成功している。
3. Claude は、テストを飛ばす設定、アサーションの削除、カバレッジや lint の対象からの除外を足して、完了条件を満たしたように見せない。CI の escape-hatch の検査が、これらの追加を機械で見つける。
4. Claude は、新しく書いたテストについて、テストの対象のコードを一時的に壊してテストが失敗することを確かめてから、コードを元に戻す。
