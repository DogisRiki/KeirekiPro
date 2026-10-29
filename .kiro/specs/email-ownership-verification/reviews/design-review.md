# design のレビュー

## サイクル1 往復1(2026-10-20)

### 審査の範囲

範囲: 全体

### 申告

**1. 確認前の登録を users の表に入れず、Redis に有効期限付きで置く** — 概要、部品「PendingRegistrationStore と RedisPendingRegistrationStore」、データの形「Redis のキー」

- Issue の記載: あり。「利用者がメールの中の確認の操作を済ませてから、そのメールアドレスをアカウントのメールアドレスとして扱う」。置き場所は書かれていない
- 決めたこと: 確認前の登録(メールアドレス、パスワードのハッシュ、ユーザー名)を `pending-registration:{id}` に JSON で24時間置き、確認を済ませたときに同じ ID でアカウントを作る。確認前の登録を消す定期実行は作らない
- 他にありえた選択肢: users の表に状態の列を持たせて確認前の行として入れる。確認前の登録の専用の表を PostgreSQL に作る
- 外れていた場合: Redis を作り直したときや障害のときに確認前の登録が消え、利用者は登録し直すことになる。パスワードのハッシュが Redis にも置かれる。確認前の登録を DB に移すなら、登録とログインと確認のユースケースと Redis の実装を作り直す

**2. users の表に NULL を許す列 `email_verified_at` と `pending_email` を V7 で足し、データは書き換えない** — プロジェクトの決まりを守っているか「データベースの表の形」、データの形「users の表」、移行

- Issue の記載: あり。「すでにあるアカウントのメールアドレスも、利用者が確認の操作を済ませるまでは、同じように扱われる」
- 決めたこと: 列を2つ足すだけの expand のマイグレーションにし、今ある行は `email_verified_at` が NULL のままにする。`pending_email` に一意の制約と索引を付けない。このマイグレーションを含む PR は所有者の承認が要る
- 他にありえた選択肢: 確認の状態を別の表(たとえば `email_verifications`)に持つ。`email_verified` を boolean にする。管理者の行だけを確認済みに書き換える
- 外れていた場合: 列の意味や形を変えるときに contract の段階が要り、マイグレーションを2回出すことになる。管理者も本番投入の直後にログインできず、確認のメールで確認を済ませてからログインする

**3. 確認のリンクのトークンを、`exp` を付けない署名付きの JWT(`lexp` claim、鍵は `jwt.secret` から用途ごとに導く)にし、URL の `#` のあとに置く** — 部品「EmailVerificationTokenCodec と JwtEmailVerificationTokenCodec」「EmailVerificationMailer」、安全

- Issue の記載: なし
- 決めたこと: トークンに `aud` `jti` `sub` `purpose` `email` `lexp` を入れて HMAC-SHA256 で署名し、期限の判断は `lexp` と Redis の最新の `jti` で行う。リンクは `/email/verify#token` で、画面が `location.hash` から読む
- 他にありえた選択肢: 今のパスワードの再設定と同じく、乱数のトークンを Redis に置き、トークンの中身を持たせない。トークンを経路のパラメータ(`/email/verify/:token`)に置く
- 外れていた場合: `jwt.secret` を替えると送ったリンクがすべて使えなくなる。署名が正しいトークンは期限が切れても読めるので、使われなかった古いリンクは送り直しの入口として残り続ける(1分の制限はかかる)。乱数のトークンに替えるなら、トークンを作る部品と読む部品と Redis のキーの形と確認の画面を作り直す

**4. 確認がまだのログインを 409 `{message, errors, kind}` で断る** — 部品「EmailNotVerifiedUseCaseException と AppExceptionHandler」、データの形「API」、失敗したときの扱い

- Issue の記載: あり。「確認の操作を済ませていないメールアドレスは、どの機能でも、アカウントのメールアドレスとして扱われない」。応答の形は書かれていない
- 決めたこと: `UseCaseException` を継いだ例外を 409 のハンドラで受け、`ErrorResponse` に `kind` を足した形で返す。frontend は 409 を共通の受け口で扱わず、`LoginContainer` が `kind` で出し分ける
- 他にありえた選択肢: 今と同じ 400 の `ErrorResponse` の `errors` にキーを足す。200 で状態を返す
- 外れていた場合: 共通の axios の受け口が 409 を素通しにしていることが前提なので、受け口の扱いを変えるときにログインの画面も変わる。応答の形を変えるなら backend のハンドラと frontend の出し分けの両方を直す

**5. パスワードの再設定に続く確認のあとの再設定のトークンの期限を、リンクの残り時間(`lexp` − 今)にする** — 部品「VerifyEmailUseCase」の `PASSWORD_RESET` の書き込み

- Issue の記載: なし(requirements の R2-1-2 で design に送られた)
- 決めたこと: 確認を済ませた時点で `PasswordResetTokenStore.store(token, sub, lexp - 今)` で置き、同じ画面の `ResetPasswordForm` で使う
- 他にありえた選択肢: 確認を済ませた時点から固定の10分にする
- 外れていた場合: リンクの期限の直前に押した利用者は、数秒で再設定の画面を終えないと再設定できず、もう一度パスワードの再設定を求め直すことになる

**6. メールの送信に失敗したときは、登録では確認前の登録を消して 500、メールアドレスの設定ではトランザクションを取り消して 500、登録完了のお知らせの失敗では確認そのものを取り消す** — 部品「EmailVerificationMailer」「UserRegistrationUseCase」「EmailVerificationCompletion」「SetEmailAndPasswordUseCase」の失敗したとき

- Issue の記載: なし
- 決めたこと: 送信を同期で行い、失敗したら利用者の操作ごとやり直させる。送信の再試行と非同期の送信はしない
- 他にありえた選択肢: 確認を済ませることは成功とし、登録完了のお知らせだけを落とす。送信を非同期にして再試行する
- 外れていた場合: SES の障害のあいだは、登録、メールアドレスの設定、確認の完了がどれも 500 になる。確認を取り消す形を変えるなら `EmailVerificationCompletion` と `VerifyEmailUseCase` の失敗の扱いを直す

**7. 同じメールアドレスへの確認のメールを `SET NX EX 60` で1分に1回に抑え、送り元(IP やアカウント)単位の制限は作らない** — 部品「EmailVerificationSendLimiter と RedisEmailVerificationSendLimiter」、安全

- Issue の記載: なし(requirements の要件2.6 で所有者が1分と決めた)
- 決めたこと: 宛先のメールアドレスだけをキーにする。確認のメールのほかのメールには使わない
- 他にありえた選択肢: 送り元の IP も合わせたキーにする。WAF のレートの制限に任せる
- 外れていた場合: 多数の異なる宛先に送らせる使い方は抑えられない。制限の単位を変えるなら、この部品とキーの形と呼ぶ側の引数を直す

**8. `GithubOidcProvider` は、`GET /user` の `email` を使わず、いつも `GET /user/emails` の `primary` と `verified` がどちらも true の要素だけを使う** — 部品「GithubOidcProvider」

- Issue の記載: なし(requirements の要件7.4 で、持ち主を確かめたと返さなかったメールアドレスは受け取らないと決めた)
- 決めたこと: `GET /user/emails` は今の実装がすでに `user:email` の scope で呼んでいる経路を使い、scope は変えない。当てはまる要素が無いときと呼び出しに失敗したときは `email` を null にする
- 他にありえた選択肢: `GET /user` の `email` を先に使い、無いときだけ `GET /user/emails` を呼ぶ(今の形)
- 外れていた場合: GitHub の primary のメールアドレスを確かめていない利用者は、メールアドレスの無いアカウントになり、ユーザー設定の画面から設定して確認を済ませることになる

### 指摘

| ID | レベル | 該当箇所 | 内容 | 直し方の案 |
|---|---|---|---|---|
| D1-1-1 | 中 | design.md「テストの方針」の「画面を通しで操作するテスト(Playwright)」の4項目 | 4項目(登録して確認のリンクの画面を開きログインできる、確認前の登録でログインすると文とボタンが出る、期限切れのリンクで送り直すボタンが出る、ユーザー設定の画面で確認待ちの表示が出る)は、backend が動き、確認のメールのリンクを取り出せることを前提にしている。このリポジトリの Playwright は、`frontend/playwright.config.ts` と `.kiro/steering/tech.md`(「ビルド成果物を `vite preview` で配信。バックエンド無しで検証できる範囲に限定」)と `frontend/CLAUDE.md` のとおり、`vite preview` だけを起こし backend を起こさない。CI の `e2e-smoke` も同じである。この4項目を書いたとおりに作るには、CI のワークフロー(`.github/`)に backend と Redis と メールの取り出しを足すことになり、「プロジェクトの決まりを守っているか」の「品質チェックの設定ファイルは変えない」と食い違う。tasks か実装の段階で必ず発覚し、テストの方針を書き直すことになる | 4項目を、今の決まりの範囲に収める形に書き直す。たとえば、Playwright のテストは `page.route` で API の応答(`POST /api/auth/login` の 409 と `kind`、`POST /api/auth/email-verification/verify` の `result`、`GET /api/users/me` の `emailVerified` と `pendingEmail`)を作って画面の表示だけを確かめると書く。登録から確認、アカウントの作成、ログインまでを通す確かめは、結合テストの項目に寄せる |
| D1-1-2 | 低 | design.md「処理の流れ」の「確認のリンクの結果の決め方」の下の2つ目の箇条 | 「同じリンクが同時に2回押されたときは、あとの要求が2回目の判定で `ALREADY_VERIFIED` になる」は保証されない。先の要求が `consume` に成功してから `EmailVerificationCompletion` のトランザクションを commit するまでの間に、あとの要求が2回目の判定に入ると、「sub のアカウントが email を確認済みで持つか」は いいえ、最新の `jti` は消えているので「lexp 前で、jti が current と同じか」も いいえ となり、`REGISTRATION` なら確認前の登録が残っているので `EXPIRED`、ほかの `purpose` なら対象のメールアドレスが同じなので `EXPIRED` になる。また「2回目も消せなかったときは `INVALID` を返す」は、2回目の判定で `consume` に進むには `jti` が current と同じであることが要るため、1回目で消した `jti` では到達しない。動きとしては利用者が送り直すボタンを押しても `ALREADY_VERIFIED` で断られるだけなので実装には影響しないが、文のとおりに単体テストや結合テストを書くと不安定になる | 箇条を「あとの要求は、2回目の判定で `ALREADY_VERIFIED` か `EXPIRED` のどちらかになる」と書き直し、「2回目も消せなかったときは `INVALID`」は消すか「2回目の判定は `consume` に進まない」と書く |
| D1-1-3 | 低 | design.md「部品」の「VerifyEmail ページと EmailVerificationContainer」 | 画面は `history.replaceState` で URL から `#` 以降を消し、`useVerifyEmail` の結果は memory の cache にだけ残る。そのため、利用者が画面を再読み込みするとトークンも結果も失われるが、`location.hash` にトークンが無いときに画面が何を出すかが書かれていない。また、`POST /api/auth/email-verification/verify` が 500 を返したとき(「処理の流れ」の3つ目の箇条の、`EmailVerificationCompletion` がトランザクションを取り消した場合も含む)に画面が何を出すかも書かれていない。3つ目の箇条の「利用者は、そのリンクの画面で `EXPIRED` を見て」は、メールのリンクをもう一度押したときの話であり、500 を受けた画面の話ではない | トークンが無いときの表示(たとえば `INVALID` と同じ文)と、`useVerifyEmail` が失敗したときの表示(たとえば、リンクをもう一度押すよう案内する文)を「`result` ごとの表示」の下に足す。3つ目の箇条を「利用者がメールのリンクをもう一度押すと、`EXPIRED` の画面から送り直せる」に直す |

### 前の段階への指摘

| ID | 対象 | 該当箇所 | 内容 |
|---|---|---|---|
| D1-1-4 | requirements | 要件7の2 | 要件7の2は、結び付いた Google か GitHub が返した持ち主を確かめたメールアドレスが、アカウントの「確認前のメールアドレス」と同じときだけを決めている。「設定待ちのメールアドレス」と同じときは決めていないため、design は、アカウントを変えない(設定待ちのまま)としている(部品「OidcLoginUseCase、HandleOidcCallbackUseCase、OidcCallbackController」の1つ目の箇条)。Google か GitHub だけでログインしている利用者が、その Google か GitHub と同じメールアドレスを設定した場合、Google か GitHub が持ち主を確かめていても、利用者は確認のメールのリンクを押すまで設定待ちのままになる。利用者はメールのリンクで確認を済ませられるので動きは成り立つが、要件7の2を設定待ちのメールアドレスにも広げるかは所有者の判断になる |

- 往復: 1回目 / 高0 中1 低2

## サイクル2 往復1(2026-10-20)

### 審査の範囲

範囲: 全体

### 申告

**1. 確認前の登録を users の表に入れず、Redis に有効期限付きで置く** — 概要、部品「PendingRegistrationStore と RedisPendingRegistrationStore」、データの形「Redis のキー」

- Issue の記載: あり。「利用者がメールの中の確認の操作を済ませてから、そのメールアドレスをアカウントのメールアドレスとして扱う」。置き場所は書かれていない
- 決めたこと: 確認前の登録(メールアドレス、パスワードのハッシュ、ユーザー名、作った日時)を `pending-registration:{id}` に24時間置き、確認を済ませたときに同じ ID でアカウントを作る。確認前の登録を消す定期実行は作らない
- 他にありえた選択肢: users の表に状態の列を持たせて確認前の行として入れる。確認前の登録の専用の表を PostgreSQL に作る
- 外れていた場合: 本番の ElastiCache は `maxmemory-policy volatile-lru` で `snapshot_retention_limit = 0`(`terraform/modules/elasticache/main.tf`)なので、メモリが足りなくなったときや作り直したときに確認前の登録が消え、利用者は登録し直すことになる。パスワードのハッシュが Redis にも置かれる。DB に移すなら、登録とログインと確認のユースケースと Redis の実装を作り直す

**2. users の表に NULL を許す列 `email_verified_at` と `pending_email` を V7 で足し、データは書き換えない** — プロジェクトの決まりを守っているか「データベースの表の形」、データの形「users の表」、移行

- Issue の記載: あり。「すでにあるアカウントのメールアドレスも、利用者が確認の操作を済ませるまでは、同じように扱われる」
- 決めたこと: 列を2つ足すだけの expand のマイグレーションにし、今ある行はすべて確認前になる。管理者の行も書き換えない。`pending_email` に一意の制約と索引を付けない。このマイグレーションを含む PR は所有者の承認が要る
- 他にありえた選択肢: 確認の状態を別の表に持つ。`email_verified` を boolean にする。管理者の行だけを確認済みに書き換える
- 外れていた場合: 管理者も本番投入の直後はメールアドレスとパスワードでログインできず、確認のメールで確認を済ませてからログインする。列の意味や形を変えるときに contract の段階が要り、マイグレーションを2回出すことになる

**3. ログインと、ログインの画面からの送り直しで照らし合わせる確認前の登録を、同じメールアドレスの新しい順に5件までにする** — 部品「LoginUseCase」「ResendEmailVerificationForLoginUseCase」、性能

- Issue の記載: なし(要件1.4 で、同じメールアドレスの確認前の登録を何件でも受け付けると決めている)
- 決めたこと: BCrypt の照らし合わせの回数を抑えるため、5件より古い登録はパスワードと照らし合わせない。登録の受け付けそのものには数の制限を付けない
- 他にありえた選択肢: 件数の上限を設けず全部照らす。同じメールアドレスの確認前の登録の数に上限を付け、超えたら古いものを消す。登録の受け付けを IP などで制限する
- 外れていた場合: 他人が同じメールアドレスで確認前の登録を5件以上作ると、本当の持ち主の登録が6件目以降に押し出される。持ち主は、ログインの画面で「確認がまだ」の文と送り直すボタンを見られず(要件3.1)、ログインの画面から確認のメールも受け取れない。持ち主が受け取った確認のメールのリンクは使えるが、登録したときに1分の制限で送られなかった人(要件2.7)は、他人が止めるまで確認を済ませる手段が無い

**4. 外部連携のログインで設定待ちのメールアドレスを確認済みに移すとき、確かめたあとにほかのアカウントが同じメールアドレスを確認済みにした重なりでは、ログインを1回失敗させる** — 部品「OidcLoginUseCase、HandleOidcCallbackUseCase、OidcCallbackController」の失敗したとき

- Issue の記載: なし(requirements の要件7.2 で、付けずに設定待ちのまま残したときもログインさせると決めた)
- 決めたこと: `findByEmail` で確かめてから `promotePendingEmail` を保存する。その間の重なりで一意の制約に当たったら、トランザクションごと取り消して `LOGIN_FAILED` にする。ログインのトランザクションを分ける仕組みは作らない
- 他にありえた選択肢: 一意の制約に当たったら、設定待ちのまま残す形でトランザクションをやり直してログインさせる
- 外れていた場合: まれな重なりのときに、要件7.2 の「設定待ちのまま残したときもログインさせる」が1回だけ守られない。直すなら、`OidcLoginUseCase` の保存とトランザクションの分け方を作り直す

**5. 確認のリンクのトークンを、`exp` を付けない署名付きの JWT(`lexp` claim、鍵は `jwt.secret` から導く)にし、URL の `#` のあとに置く** — 部品「EmailVerificationTokenCodec と JwtEmailVerificationTokenCodec」「EmailVerificationMailer」

- Issue の記載: なし
- 決めたこと: トークンに `aud` `jti` `sub` `purpose` `email` `lexp` を入れて HMAC-SHA256 で署名し、期限は `lexp` と Redis の最新の `jti` で判断する。リンクは `/email/verify#token`
- 他にありえた選択肢: 今のパスワードの再設定と同じく、乱数のトークンを Redis に置く。トークンを経路のパラメータに置く
- 外れていた場合: `jwt.secret` を替えると送ったリンクがすべて使えなくなる。期限の切れたリンクも送り直しの入口として残り続ける(1分の制限はかかる)。乱数のトークンに替えるなら、トークンの部品と Redis のキーの形と確認の画面を作り直す

**6. 確認がまだのログインを 409 `{message, errors, kind}` で断る** — 部品「EmailNotVerifiedUseCaseException と AppExceptionHandler」、データの形「API」

- Issue の記載: なし(応答の形は書かれていない)
- 決めたこと: `UseCaseException` を継いだ例外を 409 のハンドラで受け、`kind` で `LoginContainer` が出し分ける。共通の axios の受け口が 409 を素通しにすること(`frontend/src/lib/axiosInterceptors.ts` で確かめた)を前提にする
- 他にありえた選択肢: 400 の `errors` にキーを足す。200 で状態を返す
- 外れていた場合: 共通の受け口の扱いを変えるときにログインの画面も変わる。応答の形を変えるなら backend のハンドラと frontend の出し分けの両方を直す

**7. メールの送信を同期で行い、失敗したら利用者の操作ごとやり直させる** — 部品「EmailVerificationMailer」「UserRegistrationUseCase」「EmailVerificationCompletion」「SetEmailAndPasswordUseCase」の失敗したとき

- Issue の記載: なし
- 決めたこと: 登録では確認前の登録を消して 500、メールアドレスの設定ではトランザクションの中で送って失敗したら取り消して 500、登録完了のお知らせの失敗では確認そのものを取り消す(最新の `jti` は戻さない)。送信の再試行と非同期の送信はしない
- 他にありえた選択肢: 確認を済ませることは成功とし、登録完了のお知らせだけを落とす。送信を非同期にして再試行する
- 外れていた場合: SES の障害のあいだは、登録、メールアドレスの設定、確認の完了がどれも 500 になる。形を変えるなら `EmailVerificationCompletion` と `VerifyEmailUseCase` の失敗の扱いを直す

**8. 同じメールアドレスへの確認のメールを `SET NX EX 60` で1分に1回に抑え、送り元単位の制限は作らない** — 部品「EmailVerificationSendLimiter と RedisEmailVerificationSendLimiter」

- Issue の記載: なし(要件2.6 で所有者が1分と決めた)
- 決めたこと: 宛先のメールアドレスだけをキーにする
- 他にありえた選択肢: 送り元の IP も合わせたキーにする。WAF のレートの制限に任せる
- 外れていた場合: 多数の異なる宛先に送らせる使い方は抑えられない。制限の単位を変えるなら、この部品とキーの形と呼ぶ側の引数を直す

**9. パスワードの再設定に続く確認のあとの再設定のトークンの期限を、リンクの残り時間(`lexp` − 今)にする** — 部品「VerifyEmailUseCase」の `PASSWORD_RESET`

- Issue の記載: なし(requirements の R2-1-2 で design に送られた)
- 決めたこと: 確認を済ませた時点で `PasswordResetTokenStore.store(token, sub, lexp - 今)` で置く
- 他にありえた選択肢: 確認を済ませた時点から固定の10分にする
- 外れていた場合: リンクの期限の直前に押した利用者は、短い時間で再設定を終えないと、パスワードの再設定を求め直すことになる

**10. `GithubOidcProvider` は、いつも `GET /user/emails` の `primary` と `verified` がどちらも true の要素だけを使う** — 部品「GithubOidcProvider」

- Issue の記載: なし(要件7.4 で、持ち主を確かめたと返さなかったメールアドレスは受け取らないと決めた)
- 決めたこと: 今の scope(`user:email`)のまま、`GET /user` の `email` を使わない
- 他にありえた選択肢: `GET /user` の `email` を先に使い、無いときだけ `GET /user/emails` を呼ぶ(今の形)
- 外れていた場合: GitHub の primary のメールアドレスを確かめていない利用者は、メールアドレスの無いアカウントになる

### 指摘

| ID | レベル | 該当箇所 | 内容 | 直し方の案 |
|---|---|---|---|---|
| D2-1-1 | 中 | design.md「部品」の「useUserRegister、useSetEmailAndPassword、useUserState、SetEmailAndPasswordContainer」と「EmailVerificationStatus と userSettingRules」、「ファイルの構成」の「Claude が変えるファイル」 | design は、設定待ちのメールアドレスとパスワードを設定したあとの状態を `PASSWORD_WITH_PROVIDER` として足し、利用者は設定待ちのメールアドレスを、メールアドレスとパスワードの設定の画面で入れ直して置き換えるとしている(要件4.3)。しかし、ユーザー設定の画面からその画面へ移る道が決まっていない。今の `createUserSettingMessages`(`frontend/src/features/user/utils/userSettingMessages.ts`)は、知らない状態に対して空のラベルと `paths.user` へのリンクを返すので、`PASSWORD_WITH_PROVIDER` の利用者には設定の画面へのリンクが出ない。design は `userSettingMessages` について連携の解除の文しか決めていない。また、`isTwoFactorDisabled` と `isProviderRemovable` は、今は `UserState` を受け取る関数で、design は判断を `emailVerified && hasPassword` に変えるので、呼んでいる `frontend/src/features/user/components/SettingUserContainer.tsx` の変更が要るが、「Claude が変えるファイル」に入っていない。`ChangePasswordContainer` も、`EMAIL_PASSWORD` と `EMAIL_PASSWORD_WITH_PROVIDER` のほかはログインの画面へ移すので、`PASSWORD_WITH_PROVIDER` の利用者は設定したパスワードを変えられない。tasks のファイルの範囲は「ファイルの構成」から決まるので、実装で型の誤りとして必ず発覚し、design に戻ることになる。要件4.3 の、設定し直す道が画面から無いまま終わるおそれもある | 「EmailVerificationStatus と userSettingRules」の節に、`PASSWORD_WITH_PROVIDER` のときの `createUserSettingMessages` のラベルと文とリンク先(`paths.emailPassword.set`)を書く。`isTwoFactorDisabled` と `isProviderRemovable` の新しい引数を書き、`SettingUserContainer.tsx` を「Claude が変えるファイル」に足す。`ChangePasswordContainer` で `PASSWORD_WITH_PROVIDER` を通すかどうかを決めて書く |
| D2-1-2 | 中 | design.md「部品」の「ResendEmailVerificationUseCase」と「ResendEmailVerificationForLoginUseCase」の手順 | 2つのユースケースは、`PendingRegistrationStore.extend(id, 24時間)` を呼んでから `EmailVerificationMailer.send` を呼ぶ。`send` が `RATE_LIMITED` を返したときと例外を投げたときも、確認前の登録の有効期限は今から24時間に延びたままになる。このとき新しいリンクは送られていないので、確認前の登録は、最後に送ったリンクの期限が切れたあとも最大24時間残る。要件1.6 は、確認前の登録を「最後に送った確認のリンクの期限が切れたときに消す」と決めており、design のとおりに作るとこれに反する。テストの方針にもこの場合が無いので、気づかれないまま実装が終わる | `send` が `SENT` を返したときだけ `extend` を呼ぶ順に直す。あわせて、確認前の登録の有効期限を、`send` が作ったリンクの期限(`linkExpiresAt`)にそろえると書くと、登録を受け付けたときに登録がリンクより数ミリ秒早く消える重なり(「確認のリンクの結果の決め方」の図で、リンクが使える側の枝に進んだのに `findById(sub)` が空になる場合)も無くせる |
| D2-1-3 | 低 | design.md「部品」の「VerifyEmail ページと EmailVerificationContainer」の `VERIFIED` の表示 | 要件1.2 は、確認前の登録の確認を済ませたときに「登録が済んだこと」を画面に出すと決めている。design の `VERIFIED` は、登録、前からあるアカウント、設定待ちのメールアドレスで共通で、表示は「確認が済んだことと、ログインの画面へ進むボタン」である。応答の `result` から登録だったかどうかが分からないので、画面は登録のときだけ「登録が済んだ」と出し分けられない | `REGISTRATION` のときに別の `result`(たとえば `REGISTERED`)を返すか、応答に `purpose` を足し、登録のときは登録が済んだことを出すと書く |
| D2-1-4 | 低 | design.md「プロジェクトの決まりを守っているか」の「関係のない項目」 | 「使う外部の機能がこのリポジトリで使えるか」を関係のない項目にしているが、design は、GitHub の `GET /user/emails` の `verified`、ElastiCache(Valkey 8.0)の Lua スクリプト(`consume`)と `SET NX EX` に頼っている。いずれもこのリポジトリの条件で使える(GitHub は今の実装がすでに `user:email` の scope で呼んでいる。ElastiCache はノード型の Valkey 8.0 で、`terraform/modules/elasticache/main.tf` にスクリプトを止める設定は無い)ので、動きには影響しない | 関係のある項目に移し、頼る機能と、使えることをどう確かめたかを1行で書く |
| D2-1-5 | 低 | design.md「処理の流れ」の「確認のリンクの結果の決め方」の下の2つ目と3つ目の箇条、「VerifyEmail ページと EmailVerificationContainer」 | サイクル1の D1-1-2 と D1-1-3 と同じ内容が、作り直した design にも残っている。同じリンクを同時に2回押したとき、あとの要求は2回目の判定で `EXPIRED` にもなりうる(先の要求の commit の前に判定すると、最新の `jti` は消えていて確認もまだ済んでいない)。「2回目も消せなかったときは `INVALID`」には到達しない。`location.hash` にトークンが無いとき(再読み込みしたとき)と、verify が 500 を返したときの画面の表示が書かれていない | D1-1-2 と D1-1-3 の直し方の案のとおり |
| D2-1-6 | 低 | design.md「失敗したときの扱い」の「Redis の失敗(500)」 | 「DB の users は変わらない」は、どの場合にも当てはまるわけではない。`VerifyEmailUseCase` は、`completeRegistration` の commit のあとに Redis の確認前の登録を消し、`PASSWORD_RESET` では `verifyAccountEmail` の commit のあとに Redis に再設定のトークンを置く。このあとの Redis の失敗では、users は変わったまま 500 になる。利用者がリンクをもう一度押すと `ALREADY_VERIFIED` になるので、動きは成り立つ | 「確認の書き込みを commit したあとの Redis の失敗では、users は確認済みのまま 500 になる。利用者がリンクをもう一度押すと `ALREADY_VERIFIED` を見る。パスワードの再設定では、利用者はパスワードの再設定を求め直す」と書く |

- 往復: 1回目 / 高0 中2 低4

## サイクル2 往復2(2026-10-20)

### 審査の範囲

範囲: 差分

- design.md「ファイルの構成」の「Claude が変えるファイル」、「EmailVerificationStatus、userSettingRules、userSettingMessages、SettingUserContainer、ChangePasswordContainer」の節、「テストの方針」の frontend の4項目: 差分で書き換えた箇所。`PASSWORD_WITH_PROVIDER` `SettingUserContainer` `ChangePasswordContainer` `createUserSettingMessages` で design を検索し、同じ状態を使う「useUserRegister、useSetEmailAndPassword、useUserState、SetEmailAndPasswordContainer」の節と「SetEmailAndPasswordUseCase」の節を読み、requirements の要件4.3、10.2、10.3 と照らした。実ファイル `frontend/src/features/user/utils/userSettingRules.ts` `userSettingMessages.ts` `components/SettingUserContainer.tsx` `ChangePasswordContainer.tsx` `SetEmailAndPasswordContainer.tsx` `PasswordStatusBox.tsx` `hooks/useUserState.ts` と `frontend/src/components/ui/UserMenu.tsx` で、関数の引数と画面の行き先を確かめた
- design.md「ResendEmailVerificationUseCase」と「ResendEmailVerificationForLoginUseCase」の手順、「テストの方針」の2つのユースケースの項目: 差分で順を変えた箇所。`extend` と「延ば」「置き直」で検索し、「PendingRegistrationStore と RedisPendingRegistrationStore」の「状態の持ち方」、「Redis のキー」の表、「EmailVerificationMailer」の「失敗したとき」を読み、requirements の要件1.6 と照らした
- design.md「作るものと作らないもの」: `ChangePasswordContainer`(パスワードの変更の画面)を変える部品に足したので、境界の記載と食い違わないかを見るために読んだ
- design.md「EmailVerificationTokenCodec と JwtEmailVerificationTokenCodec」の claim の文、「MyBatisUserRepository と UserMapper」の役割、「テストの方針」の `OidcLoginUseCase` の項目: 書き方の点検で文を分けただけで、中身は変わっていない。`OidcLoginUseCase` の項目が挙げる節の見出しが本文にあることだけを確かめた

### 申告

差分の中に、新しく申告に当たる決定は無い。`send` が `SENT` を返したときだけ `extend` を呼ぶ順と、`PASSWORD_WITH_PROVIDER` でもパスワードの変更の画面を出すことは、D2-1-2 と D2-1-1 を直したもので、外れていたときの手戻りは小さい。サイクル2 往復1 の申告1〜10 は、この差分で変わらない。

### 指摘

D2-1-1 と D2-1-2 は直っていることを確かめた。`PASSWORD_WITH_PROVIDER` の利用者は、ユーザー設定の画面の案内のリンクからメールアドレスとパスワードの設定の画面へ移れ、`UserMenu.tsx` が `hasPassword` の利用者を `paths.password.change` へ送るので、パスワードの変更の画面にも移れる。2つの送り直しのユースケースは、`SENT` のときだけ確認前の登録の有効期限を延ばすので、要件1.6 に合う。

| ID | レベル | 該当箇所 | 内容 | 直し方の案 |
|---|---|---|---|---|
| D2-2-1 | 低 | design.md「部品」の「EmailVerificationStatus、userSettingRules、userSettingMessages、SettingUserContainer、ChangePasswordContainer」の `createUserSettingMessages` の段落、「テストの方針」の frontend の `userSettingMessages` の項目 | `createUserSettingMessages` は、メールアドレスの確認がまだのために外部連携を解除できないときに「メールアドレスの確認が済んでいないため、連携を解除できません。」を出すとしている。しかし、今の `createUserSettingMessages(state: UserState, providerCount: number)` は確認済みかどうかを受け取らない。`useUserState` は `email` があるかだけで状態を決めるので、確認前のメールアドレスとパスワードと外部連携1つを持つ利用者は `EMAIL_PASSWORD_WITH_PROVIDER` になり、今の文の決め方では `providerMessage` が null になる(解除のボタンは `isProviderRemovable(user)` で押せないのに、理由が出ない)。design は2つの判定の関数には `user` を渡すと書いたが、この関数に何を渡すかは書いていない。テストの方針も、この文を確かめる項目を持たない。実装する人が引数を足せば済むので、design に戻ることにはならない | `createUserSettingMessages` も `user`(か `emailVerified`)を受け取り、`SettingUserContainer` が渡すと書く。テストの方針の `userSettingMessages` の項目に、確認前のメールアドレスか設定待ちのメールアドレスを持ち外部連携が1つのときに、この文を返すことを足す |
| D2-2-2 | 低 | design.md「作るものと作らないもの」の「作るもの」の7つ目の箇条 | 変える画面として、確認のリンク、ログイン、登録、ユーザー設定、メールアドレスとパスワードの設定の各画面を挙げているが、この往復で足した `ChangePasswordContainer`(パスワードの変更の画面)が入っていない。本文の部品とファイルの構成には書かれているので、実装には影響しない | 「作るもの」の画面の並びに、パスワードの変更の画面を足す |

### 前の段階への指摘

なし

この往復の指摘の数: 高0 中0 低2

- 往復: 2回で収束 / 未解決: 0件

## サイクル3 往復1(2026-10-20)

### 審査の範囲

範囲: 差分

- design.md「部品」の「SetEmailAndPasswordUseCase」の「呼び出し方」と「失敗したとき」: 差分で `currentPassword` の照らし合わせを足した箇所。`SetEmailAndPassword` `currentPassword` `今のパスワード` `PASSWORD_WITH_PROVIDER` で design と requirements を検索し、requirements の要件3.5、4.1、4.3、6.2、9.3 と照らした。実ファイル `backend/.../usecase/user/SetEmailAndPasswordUseCase.java` `usecase/user/ChangePasswordUseCase.java` `usecase/user/command/SetEmailAndPasswordCommand.java` `presentation/user/dto/SetEmailAndPasswordRequest.java` `presentation/user/controller/SetEmailAndPasswordController.java` `usecase/shared/exception/UseCaseException.java` `domain/model/user/User.java`(`changePassword` と `resetPassword`)で、今のパスワードの照らし合わせ方と、パスワードを変えたあとの扱いを確かめた
- design.md「ファイルの構成」の「Claude が変えるファイル」の backend と frontend の行: 差分で足した行。`SetEmailAndPasswordRequest.java` `SetEmailAndPasswordCommand.java` `SetEmailAndPasswordForm.tsx` `setEmailAndPassword.ts` の今の欄を読み、`currentPassword` を通すのに要るファイルがそろっているかを確かめた
- design.md「部品」の「useUserRegister、useSetEmailAndPassword、useUserState、SetEmailAndPasswordContainer」: 差分で今のパスワードの入力欄の文を足した箇所。実ファイル `frontend/src/features/user/components/SetEmailAndPasswordContainer.tsx` と `SetEmailAndPasswordForm.tsx` を読んだ
- design.md「部品」の「EmailVerificationStatus、userSettingRules、userSettingMessages、SettingUserContainer、ChangePasswordContainer」の `createUserSettingMessages` の段落: 差分で1文を消した箇所。消した文と同じ中身が「useUserRegister、…」の節の最後の文に残っていて、リンク先 `paths.emailPassword.set` も残っていることを確かめた
- design.md「テストの方針」の `SetEmailAndPasswordUseCase` の項目: 差分で足した行。「SetEmailAndPasswordUseCase」の節の書き方と合っているかを見た
- design.md「失敗したときの扱い」と「安全」: `currentPassword` が合わないときの 400 と、利用者の操作を守る仕組みの書き方が、足した文と食い違わないかを見るために読んだ

### 申告

**1. パスワードを持つアカウントがメールアドレスとパスワードの設定の画面を使うときに、今のパスワードを求める** — 部品「SetEmailAndPasswordUseCase」「useUserRegister、useSetEmailAndPassword、useUserState、SetEmailAndPasswordContainer」

- Issue の記載: なし(requirements の要件4.1 と4.3 は、今のパスワードを求めるかどうかを書いていない)
- 決めたこと: アカウントがすでにパスワードを持つとき(状態 `PASSWORD_WITH_PROVIDER`)は、`currentPassword` が無いときと合わないときに `UseCaseException` で断り、何も保存しない。パスワードを持たないときは見ない
- 他にありえた選択肢: 今のパスワードを求めない(前の版の design)。パスワードを変えるときだけ今のパスワードを求め、設定待ちのメールアドレスの置き換えだけなら求めない
- 外れていた場合: パスワードを忘れた `PASSWORD_WITH_PROVIDER` の利用者は、設定待ちのメールアドレスを置き換えられない(下の D3-1-1)。逆に求めない形にすると、ログインの状態を奪った人が、パスワードを上書きし、自分のメールアドレスを設定待ちにして確認を済ませ、メールアドレスとパスワードでログインできるようになる

### 指摘

| ID | レベル | 該当箇所 | 内容 | 直し方の案 |
|---|---|---|---|---|
| D3-1-1 | 中 | design.md「部品」の「SetEmailAndPasswordUseCase」の「呼び出し方」の2つ目の箇条 | 今のパスワードを求めたことで、`PASSWORD_WITH_PROVIDER` の利用者がパスワードを忘れると、行き止まりになる。この利用者は、要件3.5 のとおり設定待ちのメールアドレスとパスワードではログインできないので、設定したパスワードを確認が済むまで一度も使わず、忘れやすい。忘れたあとは、(1) パスワードの変更の画面は今のパスワードを求める(`ChangePasswordUseCase` の `nowPassword`)、(2) パスワードの再設定は、要件9.3 のとおり設定待ちのメールアドレスにはメールを送らない、(3) メールアドレスとパスワードの設定の画面も、この差分で今のパスワードを求める。そのため、設定待ちのメールアドレスを打ち間違えていた利用者は、要件4.3 の「別のメールアドレスを設定し直す」ことができず、確認のメールも打ち間違えたメールアドレスにしか送れない(要件6.2)。確認済みのメールアドレスが無いままなので、2段階認証の有効化と外部連携の解除(要件10.2、10.3)もできない。要件4.3 は今のパスワードを条件にしていないので、design は要件4.3 を、パスワードを覚えている利用者だけに狭めている。design はこの場合を書いておらず、codex-review は design を基準にするので、このまま実装が終わる | どちらかに決めて書く。(a) 今のパスワードを求めたまま、パスワードを忘れた `PASSWORD_WITH_PROVIDER` の利用者が設定待ちのメールアドレスを置き換えられないことを「SetEmailAndPasswordUseCase」の節に書き、要件4.3 を狭めることを所有者に示す(前の段階への判断として)。(b) 設定待ちのメールアドレスを置き換える道を残す。たとえば、パスワードを忘れた利用者が設定待ちのメールアドレスとパスワードを外す(`PROVIDER_ONLY` に戻す)操作を、外部連携のログインの状態だけで許すなど、行き止まりにならない道を決めて書く |
| D3-1-2 | 低 | design.md「部品」の「SetEmailAndPasswordUseCase」の「呼び出し方」の2つ目と3つ目の箇条 | 今のパスワードを照らし合わせたうえでパスワードを上書きするので、この道は実質的にパスワードの変更になる。今のパスワードの変更(`ChangePasswordUseCase`)とパスワードの再設定(`ResetPasswordUseCase`)は、変えたあとに `authSessionInvalidator.invalidate(userId)` でほかのログインの状態を無効にするが、このユースケースは `resetPassword` を呼んで保存するだけで、無効にするかを書いていない。要件には書かれていないので実装は進むが、パスワードを変える道によって扱いが分かれる | `PASSWORD_WITH_PROVIDER` でパスワードを上書きしたときに、ほかのログインの状態を無効にするかどうかを書く。無効にするなら、テストの方針の `SetEmailAndPasswordUseCase` の項目にも足す |

### 前の段階への指摘

なし(D3-1-1 の直し方の案(a)を選ぶときは、要件4.3 を狭めることを所有者が判断する)

この往復の指摘の数: 高0 中1 低1

- 往復: 1回目 / 高0 中1 低1

## サイクル3 往復2(2026-10-20)

### 審査の範囲

範囲: 差分

- design.md「部品」の「SetEmailAndPasswordUseCase」の「呼び出し方」の3つ目の箇条(D3-1-1 を直すために足した行): `今のパスワード` `PASSWORD_WITH_PROVIDER` `currentPassword` `4.3` で design と requirements を検索し、同じ節の2つ目の箇条、「useUserRegister、useSetEmailAndPassword、useUserState、SetEmailAndPasswordContainer」の節(589行目の、設定待ちのメールアドレスを入れ直して置き換える文)、「User」の節の `removeAuthProvider` の条件、requirements の要件4.3 と要件9.3 を読み、足した文が本文のほかの箇所と食い違わないか、利用者が外部連携でログインし続けられるという前提が成り立つか(`PASSWORD_WITH_PROVIDER` は外部連携を持つ状態で、確認前は外部連携を解除できない)を確かめた
- design.md「設計を見直すきっかけ」の409 の `kind` と、users の2つの列の箇条(理由を書き足した行): `LoginContainer` `isEmailVerified` `退会` `emailVerified` で design を検索し、「概要」の2つ目の段落、「作るもの」の6つ目の箇条、「User」の節(`changeTwoFactorAuthEnabled` `removeAuthProvider` `delete()`)、「ファイルの構成」の `GetUserInfoUseCase` と frontend の `User` の型の行と照らした(指摘 D3-2-1)
- design.md「プロジェクトの決まりを守っているか」の「データベースの表の形」と「移行」の V7 の箇条: 消した文(NULL を許す列2つだけ、既存の列は変えず、データも書き換えない)が「移行」の箇条に移り、中身が残っていることを確かめた
- design.md「使う技術」の Redis の行: 消した説明と同じ中身が「使う既存の仕組み」の `RedisTemplate<String, Object>` の箇条に残っていることを確かめた
- design.md「EmailVerificationTokenCodec と JwtEmailVerificationTokenCodec」の claim の文、「GithubOidcProvider」の役割、「User」の `setPendingEmail`、「users の表」の索引の文: 書き方の点検で主語を補っただけで、中身は変わっていない。`GoogleOidcProvider` を変えないとした文について、「ファイルの構成」に `GoogleOidcProvider` が無いことだけを確かめた

### 申告

**1. パスワードを持つアカウントがメールアドレスとパスワードの設定の画面を使うときに今のパスワードを求め、今のパスワードを忘れた利用者には設定待ちのメールアドレスを置き換える道を作らない** — 部品「SetEmailAndPasswordUseCase」の「呼び出し方」の2つ目と3つ目の箇条

- Issue の記載: あり。「利用者があとからアカウントにメールアドレスを設定するときも、アプリは同じ確認を行う」。今のパスワードを求めるかどうかは書かれていない。requirements の要件4.3 は、確認を済ませる前に別のメールアドレスを設定し直せると決めており、今のパスワードを条件にしていない
- 決めたこと: 状態 `PASSWORD_WITH_PROVIDER` の利用者は、今のパスワードを入れたときだけ設定待ちのメールアドレスを置き換えられる。今のパスワードを忘れた利用者は、Google か GitHub でログインし、確認がまだのアカウントとして使い続ける。その利用者は、設定待ちのメールアドレスを打ち間違えていたときは、確認を済ませる手段が無く、2段階認証の有効化と外部連携の解除もできない
- 他にありえた選択肢: 今のパスワードを求めない。設定待ちのメールアドレスの置き換えだけなら今のパスワードを求めない。外部連携のログインの状態だけで、設定待ちのメールアドレスとパスワードを外す(`PROVIDER_ONLY` に戻す)操作を許す
- 外れていた場合: 所有者が要件4.3 をすべての利用者に守るべきと判断したら、置き換える道か外す道を足すために、`SetEmailAndPasswordUseCase` とメールアドレスとパスワードの設定の画面(か新しい API と画面)を作り直す。今のパスワードを求めない形に戻すと、ログインの状態を奪った人が、自分のメールアドレスを設定待ちにして確認を済ませ、そのアカウントにメールアドレスとパスワードでログインできるようになる

サイクル2 往復1 の申告1〜10 は、この差分で変わらない。

### 指摘

D3-1-1 は、直し方の案(a)のとおり直っていることを確かめた。足した箇条は、今のパスワードを忘れた利用者が設定待ちのメールアドレスを置き換えられないことと、その利用者が外部連携でログインし続けることを書いている。`PASSWORD_WITH_PROVIDER` は外部連携を持つ状態で、「User」の `removeAuthProvider` は確認前に最後の外部連携の解除を断るので、外部連携でログインし続けられるという前提は成り立つ。要件4.3 を狭めることは、下の「前の段階への指摘」に挙げた。

| ID | レベル | 該当箇所 | 内容 | 直し方の案 |
|---|---|---|---|---|
| D3-2-1 | 低 | design.md「設計を見直すきっかけ」の5つ目の箇条 | 足した理由は、`email_verified_at` と `pending_email` を見て動きを分けるのを、ログイン、パスワードの再設定の要求、外部連携のログイン、メールアドレスとパスワードの設定の4つのユースケースだけとしている。しかし、「User」の節の `changeTwoFactorAuthEnabled` `removeAuthProvider` `delete()` も `isEmailVerified()`(`emailVerifiedAt` を見る)で動きを分け、`VerifyEmailUseCase` と `EmailVerificationCompletion`、`GetUserInfoUseCase` が返す `emailVerified` と `pendingEmail`、それを使う frontend の `userSettingRules` と `EmailVerificationStatus` も2つの列に頼る。「作るもの」の6つ目の箇条は、退会、2段階認証の切り替え、外部連携の解除も挙げている。列の意味を変える人が、この箇条を見て4つのユースケースだけを直すおそれがあるが、きっかけの一覧なので実装には影響しない | 理由を「この2つの列を見て動きを分けている部品(ログイン、パスワードの再設定の要求、外部連携のログイン、メールアドレスとパスワードの設定、確認、`User` の2段階認証の切り替えと外部連携の解除と退会、ユーザー設定の画面)」のように、本文で列に頼る部品をすべて挙げる形にする |

### 前の段階への指摘

| ID | 対象 | 該当箇所 | 内容 |
|---|---|---|---|
| D3-2-2 | requirements | 要件4の3 | 要件4.3 は、確認を済ませる前に利用者が別のメールアドレスを設定し直せると決め、条件を付けていない。design は、ログインの状態を奪った人がパスワードを上書きできないように、パスワードを持つアカウント(状態 `PASSWORD_WITH_PROVIDER`)では今のパスワードを求める形にし、今のパスワードを忘れた利用者は設定待ちのメールアドレスを置き換えられないと書いた(部品「SetEmailAndPasswordUseCase」の「呼び出し方」の2つ目と3つ目の箇条)。この利用者は、要件3.5 のとおり設定待ちのメールアドレスとパスワードではログインできず、要件9.3 のとおりパスワードの再設定のメールも届かないので、パスワードを取り戻す手段も無い。設定待ちのメールアドレスを打ち間違えていた利用者は、確認を済ませる手段が無いまま、2段階認証の有効化と外部連携の解除(要件10.2、10.3)もできない。要件4.3 を、今のパスワードを入れられる利用者に限るか(requirements に条件を足すか、design のこの形を了承する)、すべての利用者に守るか(design に、置き換える道か外す道を足す)は、所有者の判断になる |

この往復の指摘の数: 高0 中0 低1

- 往復: 2回で収束 / 未解決: 0件

## サイクル4 往復1(2026-10-20)

### 審査の範囲

範囲: 全体

### 申告

**1. 確認前の登録を users の表に入れず、Redis に有効期限付きで置く** — 概要、部品「PendingRegistrationStore と RedisPendingRegistrationStore」、データの形「Redis のキー」

- Issue の記載: あり。「利用者がメールの中の確認の操作を済ませてから、そのメールアドレスをアカウントのメールアドレスとして扱う」。置き場所は書かれていない
- 決めたこと: 確認前の登録(メールアドレス、パスワードのハッシュ、ユーザー名、作った日時)を `pending-registration:{id}` に24時間置き、確認を済ませたときに同じ ID でアカウントを作る。確認前の登録を消す定期実行は作らない
- 他にありえた選択肢: users の表に状態の列を持たせて確認前の行として入れる。確認前の登録の専用の表を PostgreSQL に作る
- 外れていた場合: 本番の ElastiCache は `maxmemory-policy volatile-lru` でスナップショットを残さないので、メモリが足りなくなったときや作り直したときに確認前の登録が消え、利用者は登録し直すことになる。パスワードのハッシュが Redis にも置かれる。DB に移すなら、登録とログインと確認のユースケースと Redis の実装を作り直す

**2. users の表に NULL を許す列 `email_verified_at` と `pending_email` を V7 で足し、データは書き換えない** — プロジェクトの決まりを守っているか「データベースの表の形」、データの形「users の表」、移行

- Issue の記載: あり。「すでにあるアカウントのメールアドレスも、利用者が確認の操作を済ませるまでは、同じように扱われる」
- 決めたこと: 列を2つ足すだけの expand のマイグレーションにし、今ある行はすべて確認前になる。管理者の行も書き換えない。`pending_email` に一意の制約と索引を付けない。このマイグレーションを含む PR は所有者の承認が要る
- 他にありえた選択肢: 確認の状態を別の表に持つ。`email_verified` を boolean にする。管理者の行だけを確認済みに書き換える
- 外れていた場合: 管理者も本番投入の直後はメールアドレスとパスワードでログインできず、確認のメールで確認を済ませてからログインする。列の意味や形を変えるときに contract の段階が要り、マイグレーションを2回出すことになる

**3. ログインと、ログインの画面からの送り直しで照らし合わせる確認前の登録を、同じメールアドレスの新しい順に5件までにする** — 部品「LoginUseCase」「ResendEmailVerificationForLoginUseCase」、性能

- Issue の記載: なし(要件1.4 で、同じメールアドレスの確認前の登録を何件でも受け付けると決めている)
- 決めたこと: BCrypt の照らし合わせの回数を抑えるため、5件より古い登録はパスワードと照らし合わせない。登録の受け付けそのものには数の制限を付けない
- 他にありえた選択肢: 件数の上限を設けず全部照らす。同じメールアドレスの確認前の登録の数に上限を付け、超えたら古いものを消す。登録の受け付けを IP などで制限する
- 外れていた場合: 他人が同じメールアドレスで確認前の登録を5件以上作ると、本当の持ち主の登録が6件目以降に押し出され、持ち主はログインの画面で「確認がまだ」の文と送り直すボタンを見られない(要件3.1)。登録したときに1分の制限で確認のメールが送られなかった持ち主(要件2.7)は、他人が止めるまで確認を済ませる手段が無い

**4. 外部連携のログインで設定待ちのメールアドレスを確認済みに移すとき、確かめたあとにほかのアカウントが同じメールアドレスを確認済みにした重なりでは、ログインを1回失敗させる** — 部品「OidcLoginUseCase、HandleOidcCallbackUseCase、OidcCallbackController」の失敗したとき

- Issue の記載: なし(要件7.2 で、付けずに設定待ちのまま残したときもログインさせると決めた)
- 決めたこと: `findByEmail` で確かめてから `promotePendingEmail` を保存する。その間の重なりで一意の制約に当たったら、トランザクションごと取り消して `LOGIN_FAILED` にする
- 他にありえた選択肢: 一意の制約に当たったら、設定待ちのまま残す形でトランザクションをやり直してログインさせる
- 外れていた場合: まれな重なりのときに、要件7.2 の「設定待ちのまま残したときもログインさせる」が1回だけ守られない。直すなら、`OidcLoginUseCase` の保存とトランザクションの分け方を作り直す

**5. 確認のリンクのトークンを、`exp` を付けない署名付きの JWT(`lexp` claim、鍵は `jwt.secret` から導く)にし、URL の `#` のあとに置く** — 部品「EmailVerificationTokenCodec と JwtEmailVerificationTokenCodec」「EmailVerificationMailer」

- Issue の記載: なし
- 決めたこと: トークンに `aud` `jti` `sub` `purpose` `email` `lexp` を入れて HMAC-SHA256 で署名し、期限は `lexp` と Redis の最新の `jti` で判断する。リンクは `/email/verify#token`
- 他にありえた選択肢: 今のパスワードの再設定と同じく、乱数のトークンを Redis に置く。トークンを経路のパラメータに置く
- 外れていた場合: `jwt.secret` を替えると送ったリンクがすべて使えなくなる。期限の切れたリンクも送り直しの入口として残り続ける(1分の制限はかかる)。乱数のトークンに替えるなら、トークンの部品と Redis のキーの形と確認の画面を作り直す

**6. 確認がまだのログインを 409 `{message, errors, kind}` で断る** — 部品「EmailNotVerifiedUseCaseException と AppExceptionHandler」、データの形「API」

- Issue の記載: なし(応答の形は書かれていない)
- 決めたこと: `UseCaseException` を継いだ例外を 409 のハンドラで受け、`kind` で `LoginContainer` が出し分ける。共通の axios の受け口が 409 を素通しにすること(`frontend/src/lib/axiosInterceptors.ts` で確かめた)を前提にする
- 他にありえた選択肢: 400 の `errors` にキーを足す。200 で状態を返す
- 外れていた場合: 共通の受け口の扱いを変えるときにログインの画面も変わる。応答の形を変えるなら backend のハンドラと frontend の出し分けの両方を直す

**7. メールの送信を同期で行い、失敗したら利用者の操作ごとやり直させる** — 部品「EmailVerificationMailer」「UserRegistrationUseCase」「EmailVerificationCompletion」「SetEmailAndPasswordUseCase」の失敗したとき

- Issue の記載: なし
- 決めたこと: 登録では確認前の登録を消して 500、メールアドレスの設定ではトランザクションの中で送って失敗したら取り消して 500、登録完了のお知らせの失敗では確認そのものを取り消す(最新の `jti` は戻さない)。送信の再試行と非同期の送信はしない
- 他にありえた選択肢: 確認を済ませることは成功とし、登録完了のお知らせだけを落とす。送信を非同期にして再試行する
- 外れていた場合: SES の障害のあいだは、登録、メールアドレスの設定、確認の完了がどれも 500 になる。形を変えるなら `EmailVerificationCompletion` と `VerifyEmailUseCase` の失敗の扱いを直す

**8. 同じメールアドレスへの確認のメールを `SET NX EX 60` で1分に1回に抑え、送り元単位の制限は作らない** — 部品「EmailVerificationSendLimiter と RedisEmailVerificationSendLimiter」

- Issue の記載: なし(要件2.6 で所有者が1分と決めた)
- 決めたこと: 宛先のメールアドレスだけをキーにする
- 他にありえた選択肢: 送り元の IP も合わせたキーにする。WAF のレートの制限に任せる
- 外れていた場合: 多数の異なる宛先に送らせる使い方は抑えられない。制限の単位を変えるなら、この部品とキーの形と呼ぶ側の引数を直す

**9. パスワードの再設定に続く確認のあとの再設定のトークンの期限を、リンクの残り時間(`lexp` − 今)にする** — 部品「VerifyEmailUseCase」の `PASSWORD_RESET`

- Issue の記載: なし
- 決めたこと: 確認を済ませた時点で `PasswordResetTokenStore.store(token, sub, lexp - 今)` で置く
- 他にありえた選択肢: 確認を済ませた時点から固定の10分にする
- 外れていた場合: リンクの期限の直前に押した利用者は、短い時間で再設定を終えないと、パスワードの再設定を求め直すことになる

**10. `GithubOidcProvider` は、いつも `GET /user/emails` の `primary` と `verified` がどちらも true の要素だけを使う** — 部品「GithubOidcProvider」

- Issue の記載: なし(要件7.4 で、持ち主を確かめたと返さなかったメールアドレスは受け取らないと決めた)
- 決めたこと: 今の scope(`read:user user:email`)のまま、`GET /user` の `email` を使わない
- 他にありえた選択肢: `GET /user` の `email` を先に使い、無いときだけ `GET /user/emails` を呼ぶ(今の形)
- 外れていた場合: GitHub の primary のメールアドレスを確かめていない利用者は、メールアドレスの無いアカウントになる

パスワードを持つアカウントがメールアドレスとパスワードの設定の画面を使うときに今のパスワードを求める形は、承認済みの requirements の要件4.3 が決めたので、申告に挙げない。

### 指摘

要件1〜10 の受入基準は、どれも部品に対応している。「プロジェクトの決まりを守っているか」の7項目はそろっており、本文と食い違わない(`UseCase` は `execute` だけ、controller は `handle` だけ、`*Command` は `usecase..command..`、Redis と java-jwt は infrastructure に置く形を、`BackendArchitectureTest` と照らして確かめた)。前提にした既存の仕組み(`AppExceptionHandler` が例外の型に近いハンドラを選ぶこと、`/api/auth/**` がログインを要らず CSRF の対象外であること、`UserRegisteredEventListener` が同期であること、users の `email` の一意の制約、`UseCaseLoggingAspect` が引数を記録しないこと、`JwtProvider` の `Algorithm.HMAC256(secret)`、`GithubOidcProvider` が `user:email` の scope で `GET /user/emails` を呼べること、設定の画面がユーザーの情報を取り直すこと、更新すると書いた doc のファイル)は、実ファイルで成り立つことを確かめた。

前のサイクルで記録のみとした低の指摘 D1-1-2、D1-1-3、D2-1-3、D2-1-4、D2-1-6、D2-2-1、D2-2-2、D3-1-2、D3-2-1 は、作り直した本文にも同じ形で残っている。処置は前のとおりとし、ここでは挙げ直さない。

| ID | レベル | 該当箇所 | 内容 | 直し方の案 |
|---|---|---|---|---|
| D4-1-1 | 低 | design.md「処理の流れ」の「確認のリンクの結果の決め方」の図の `Same` の分岐と、その下の1つ目の箇条 | 利用者が設定待ちのメールアドレスを A にし、確認の前に B に置き換えると(要件4.3)、A に送ったリンクは、要件2.3 のとおり「新しい確認のメールを送ったために使えなくなったリンク」になる。要件2.4 は、そのリンクを押したときに、使えないことと送り直すボタンを出すと決めている。design では、`pending_email` が B でトークンの `email` が A なので、図の「アカウントの対象のメールアドレスが email と同じか」が いいえ になり、`INVALID`(リンクが正しくないこと)を出し、送り直すボタンを出さない。A に送り直しても `promotePendingEmail` で確認を済ませられないので、design の形は理にかなっているが、要件2.4 をこの場合だけ狭めていることと、その理由が本文に書かれていない。実装はこの図のとおりに進むので、実装には影響しない | 図の下の箇条に、「`PENDING_EMAIL` のリンクのメールアドレスが、利用者が置き換えたために設定待ちのメールアドレスでなくなったときは、送り直しても確認を済ませられないので、送り直すボタンを出さず `INVALID` にする」と書く。`INVALID` の画面の文が、この場合にも合うかを見直す |
| D4-1-2 | 低 | design.md「部品」の「VerifyEmailUseCase」の `purpose` ごとの書き込みの `REGISTRATION` | `EmailVerificationLinkClassifier` は、`REGISTRATION` のリンクが期限内で最新の `jti` と同じなら、確認前の登録が残っているかを見ずに `USABLE` を返す。そのあと `consume` に成功してから `findById(sub)` が空になる場合(登録を受け付けたときに、登録のキーが最新の `jti` のキーより数ミリ秒早く消える重なりと、本番の ElastiCache の `volatile-lru` でメモリが足りずに登録のキーだけが消えた場合)に、このユースケースが何を返すかが書かれていない。D2-1-2 の対応で重なりそのものを残すと決めたことは了承しており、ここでは結果だけを問う。実装する人が決めれば済むので、実装には影響しない | `REGISTRATION` の箇条に、「`findById(sub)` が空なら `REGISTRATION_GONE` を返す」と書く |
| D4-1-3 | 低 | design.md「部品」の「SetEmailAndPasswordUseCase」の「呼び出し方」の3つ目と4つ目の箇条 | 今の `SetEmailAndPasswordRequest` は `email` を省いてよく、メールアドレスを持ち外部連携でログインしている利用者(状態 `EMAIL_WITH_PROVIDER`)は、パスワードだけを設定できる。3つ目と4つ目の箇条(`setPendingEmail`、`clear(userId)`、`send(email, userId, PENDING_EMAIL)`)は、1つ目の箇条と違い、メールアドレスが入力されたときに限ると書いていない。文のとおりに作ると、パスワードだけを設定する利用者で、`setPendingEmail` が「email があれば断る」に当たるか、`clear(userId)` が、その利用者の確認前のメールアドレスに送った `ACCOUNT_EMAIL` のリンクを使えなくする。今の実装がメールアドレスのあるときだけ設定しているので、実装する人はそれに合わせると考えられ、実装には影響しない | 3つ目と4つ目の箇条の頭に「メールアドレスが入力されたときは」を足し、パスワードだけが入力されたときは、設定待ちのメールアドレスと最新の `jti` に触れないと書く |
| D4-1-4 | 低 | design.md「ファイルの構成」の「Claude が新しく作るファイル」と「全体の構成」の図の最後の矢印 | `EmailVerificationLinkClassifier` が返す `LinkState` と、`EmailVerificationMailer` が返す `SendOutcome` を置くファイルが、ファイルの構成に無い(どちらかのクラスの中の型にするのかも書いていない)。図の `EmailVerificationCompletion --> MyBatisUserRepository` は、usecase の部品が infrastructure の実装に頼るように読めるが、本文の「VerifyEmailUseCase」は `UserRepository` を使うとしている。どちらも実装には影響しない | `LinkState` と `SendOutcome` を、それぞれの部品の中の列挙型にするか、別のファイルにするかを書く。図の矢印の先を、domain の `UserRepository` にする |

### 前の段階への指摘

なし

この往復の指摘の数: 高0 中0 低4

- 往復: 1回で収束 / 未解決: 0件
