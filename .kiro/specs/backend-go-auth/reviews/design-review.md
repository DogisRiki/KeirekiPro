# design の審査の記録

## サイクル1 往復1(2026-11-10)

### 審査の範囲

範囲: 全体

### 申告

**1. Google と GitHub とのやり取りを、置き換えの spec が挙げた x/oauth2 と go-oidc を使わず、標準の `net/http` と `encoding/json` で書く** — 「プロジェクトの決まりを守っているか」の「新しいライブラリの追加」、「全体の構成」の「使う技術」

- Issue の記載: なし。置き換えの spec の design の「使う技術」は、認証の部品に golang-jwt、x/crypto、x/oauth2 v0.37.0、go-oidc v3.21.0 を挙げている
- 決めたこと: x/oauth2 と go-oidc を足さず、コードの交換と利用者の情報の読み出しを自分で書く。理由と比べた結果は research.md に書いた
- 他にありえた選択肢: 置き換えの spec のとおり x/oauth2 と go-oidc を使う
- 外れていた場合: ID トークンの検証や PKCE の細かい扱いを自分で書くので、Java 版との違い(URL の項目の順、エスケープの規則、`code_verifier` の形)を比べる検査で1つずつ見つけて直すことになる。承認済みの置き換えの spec の「使う技術」と食い違ったままになる

**2. ログインの状態の検査を、偽の送信の検査の前の「値を読む段」と、あとの「ログインを求める段」の2つに分け、中間処理の順を変える** — 「Middleware」「httpapi.New の変更」

- Issue の記載: なし
- 決めたこと: `Identify` を CORS と偽の送信の検査の間に、`RequireLogin` を偽の送信の検査と経路の登録の間に置く。どちらも仕様書に無い経路への要求にも動く
- 他にありえた選択肢: 1つの中間処理で読んで求める。経路の登録のあと(操作ごと)に検査する
- 外れていた場合: ほかのまとまりの操作の 401 と 403 と、Cookie を消す `Set-Cookie` の付き方が Java 版と変わる。設計の「見直すきっかけ」にも書いたとおり、ほかのまとまりの spec がこの順を前提にするので、あとで直すと全まとまりに及ぶ

**3. `/api/admin/` の下で役割 `ADMIN` を求める検査を、API の仕様書に無い経路のために作る** — 「Middleware」の `RequireLogin`

- Issue の記載: なし。Java 版の `SecurityConfig` が `/api/admin/**` に `hasRole("ADMIN")` を付けている
- 決めたこと: Java 版と同じく、経路が `/api/admin/` の下で役割に `ADMIN` が無ければ 403 と `{"message":"アクセス権限がありません。"}` を返す
- 他にありえた選択肢: 仕様書に無い経路なので作らない(Go 版は仕様書に無い経路を 404 にする。CB-009)
- 外れていた場合: 作っても画面からは見えない。作らないと、Java 版が 403 を返す要求に Go 版が 404 を返し、比べる検査で差が出る

**4. ログインした利用者の受け渡し(`authctx`)を `internal/platform` に置く** — 「authctx」

- Issue の記載: なし
- 決めたこと: `internal/platform/authctx` に `With` `UserID` `Roles` を置き、ほかのまとまりはこれを読む
- 他にありえた選択肢: `internal/auth` に置き、`.golangci.yml` の depguard の許可にほかのまとまりから `internal/auth` を読む規則を足す(ゲート設定の変更で所有者の承認が要る)
- 外れていた場合: 関数の形を変えると、すべてのまとまりの受け口を直すことになる。「見直すきっかけ」に書いてある

**5. Java 版のメールのひな形(`src/main/resources/mail/*.ftl`)を、動かさずに `backend/mailtemplates.go` の `go:embed` で Go 版に埋め込む** — 「ファイルの構成」「Mail」

- Issue の記載: なし
- 決めたこと: ひな形のファイルは Java 版の場所に置いたまま埋め込み、`${名前}` を `{{.名前}}` に置き換えて `text/template` で差し込む。移すのは置き換えの spec の段階6
- 他にありえた選択肢: Go 版の置き場所に写しを置く。ひな形を Go の文字列として持つ
- 外れていた場合: 同じ内容のファイルが2つになると、Java 版だけを直したときに Go 版のメールが変わらない。埋め込む方式なら、Java 版の `.ftl` に `${名前}` のほかの書き方が足されたときに Go 版の読み込みが止まる

**6. 偽のログインのサービスを `api.github.com` の別名でポート 443 の TLS でも受け、Java 版には `JAVA_TOOL_OPTIONS` の trustStore、Go 版には `SSL_CERT_FILE` で自己署名の認証局を渡す** — 「偽のログインのサービスの広げ方」

- Issue の記載: なし。Java 版の `GithubOidcProvider` が `https://api.github.com/user/emails` を固定で呼ぶ
- 決めたこと: 比べる検査の中だけで証明書を作り、両方の版に信頼させる
- 他にありえた選択肢: GitHub のメールアドレスの URL を設定で差し替えられるように Java 版を直す(Java 版のコードの変更は「作らないもの」)
- 外れていた場合: Java 版のイメージが `JAVA_TOOL_OPTIONS` を受け付けないか、`keytool` を持たないと、GitHub のログインを比べる検査が作れず、要件5の受入基準3の GitHub の4場面を比べられない

**7. 設定 `App.ApplicationName`(値 `keirekipro`)を足す** — 「ファイルの構成」の `config.go`、「Mail」

- Issue の記載: なし。Java 版の `spring.application.name` は `keirekipro`
- 決めたこと: メールアドレスの確認とパスワードの再設定のメールの `siteName` と件名の【】の中に使う
- 他にありえた選択肢: `App.SiteName` を使う。定数で持つ
- 外れていた場合: Java 版が `spring.application.name` を使うメールと `app.site-name` を使うメールを分けているので、どちらかに寄せると件名が Java 版と違い、比べる検査のメールの比べで止まる

### 指摘

| ID | レベル | 該当箇所 | 内容 | 直し方の案 |
|---|---|---|---|---|
| D1-1-1 | 中 | design.md「認証の受け口」の `startOidcAuthorization` で `provider` が無いときの文、「ファイルの構成」の変えるファイル `server.go`、「変えた動きの一覧の項目」 | 「生成したコードの問い合わせの誤りの受け口で 400 にする」とあるが、その受け口は `server.go` の `gen.StdHTTPServerOptions.ErrorHandlerFunc` で、全操作に共通し、今は「4xx に変えるかはまとまりの spec が決める」として 500 を返している(`backend/internal/httpapi/server.go` 62〜69行目)。変えるファイル `server.go` の説明には `Options` と中間処理の順と型の束ねしか無く、`ErrorHandlerFunc` を変えることが書かれていない。また、全操作に共通の受け口を 400 に変えると、ほかのまとまりの操作の経路・問い合わせ・Cookie・ヘッダの誤りも Java 版の 500 と違う 400 になる。要件5の受入基準5は「認証の操作」に限って 400 を許し、変えた動きの一覧の項目も認証の操作しか載せないので、ほかのまとまりの変更は spec の範囲の外になる | 変えるファイル `server.go` に `ErrorHandlerFunc` の扱いを書き、どの範囲を 400 にするかを決める。たとえば、経路が `/api/auth` の下のときだけ 400 とし、ほかは今までどおり 500 にする。または、`startOidcAuthorization` の受け口で `provider` を `required: false` のように自分で読んで 400 にする方法に替え、どちらにするかを本文に書く |
| D1-1-2 | 中 | design.md「Error(操作の誤りの型)」の4つの本文の形、「PasswordReset」、「認証の操作の筋書き」の `password-reset.yaml` | Java 版の `ResetPasswordUseCase`(47行目)は、再設定の値が有効でも利用者が居ないときに `AuthenticationCredentialsNotFoundException("不正なアクセスです。")` を投げ、`AppExceptionHandler`(47〜55行目)がこれを 401 と `{"message":"不正なアクセスです。","errors":{}}` にし、`accessToken` と `refreshToken` を消す `Set-Cookie` を2つ付ける。API の仕様書 `resetPassword` もこの 401 を書いている。設計の `Error` は 401 を「認証に失敗しました。」(`JWTVerificationException` の受け口)の1つしか持たず、Cookie を消す性質も無い。`PasswordReset` の節にもこの場面が無く、`password-reset.yaml` の中身にも無いので、受け口が 400 か 500 で答えても、比べる検査で見つからない。この 401 の形は、利用者のまとまりの操作(`GetUserInfoUseCase` ほか7つ)でも同じ例外で使われるので、`Error` が持たないとほかのまとまりも困る | `Error` の本文の形に「`AuthenticationCredentialsNotFoundException` の受け口: 401 と `{"message": 文言, "errors": {}}` と、`accessToken` と `refreshToken` を消す Cookie」を足し、`PasswordReset` に「値は有効だが利用者が居ないときは、この形で断る」と書く。筋書きの `password-reset.yaml` にこの場面を足すか、作れない理由を書く |
| D1-1-3 | 中 | design.md「認証の受け口」の応答の表の `startOidcAuthorization`(`Content-Type: text/plain;charset=UTF-8` に固定) | API の仕様書(`backend/api/openapi.yaml` 385〜386行目)は、この操作の `Content-Type` は Accept で変わり、Accept に `application/json` が先に来ると `application/json` のまま引用符なしの本文になると書いている。画面は axios の `publicApiClient.get` で呼び(`frontend/src/features/auth/api/authorizeOidc.ts`)、axios の既定の Accept は `application/json, text/plain, */*` なので、画面からの要求に Java 版は `application/json` を返す。設計は「仕様書を変えない」としながら `text/plain` に固定しているので、筋書きが画面と同じ Accept を送ると、比べる検査が比べるヘッダ(`Content-Type`)で差が出る | 応答の表の `Content-Type` を「Java 版と同じく、Accept の先頭が `application/json` なら `application/json`、そのほかは `text/plain;charset=UTF-8`」のように Accept で決める形に直すか、固定にするなら変えた動きの一覧に載せる項目として書き、筋書きが送る Accept を本文に書く |
| D1-1-4 | 低 | design.md「Middleware」の「失敗したとき」と `RequireLogin` の 403 の本文 | `internal/auth/middleware.go` は、500 の「決まった本文」と 403 の `{"message":"アクセス権限がありません。"}` を書くが、depguard の規則(`backend/.golangci.yml` の feature)で `internal/auth` は `internal/httpapi/middleware` の `WriteError` `MessageForbidden` `MessageUnexpected` を読めない。文言と書き方を `internal/auth` に重ねて持つことになるが、本文にその断りが無い | 「Middleware」に、500 と 403 の本文の文言を `internal/auth` の定数で持ち、`internal/httpapi/middleware` の文言と同じにすることと、同じであることを単体テストで確かめることを書く。または、本文を書く関数を `internal/platform` に移すことを決める |

### 前の段階への指摘

なし

- 往復: 1回目 / 高0 中3 低1

## サイクル1 往復2(2026-11-10)

### 審査の範囲

範囲: 差分

- design.md「httpapi.New の変更」の `ErrorHandlerFunc` の段と「認証の受け口」の4つの箇条の4つ目、「変えた動きの一覧の項目」の `provider` が無い要求の項目: D1-1-1 の直しの行。`backend/internal/httpapi/server.go`(`ErrorHandlerFunc` は `r` を受けるので経路で分けられること)と、生成したコード `api.gen.go` で `ErrorHandlerFunc` に届く誤りの種類を確かめた。「`startOidcAuthorization` だけである」の断りを、`openapi.yaml` の `/api/auth/` の下の13の操作の項目(問い合わせ・Cookie)で確かめた
- design.md「Error(操作の誤りの型)」の `ClearSession` の箇条、「PasswordReset」の「失敗したとき」、「harness」の Redis を書き換える段、「認証の操作の筋書き」の `password-reset.yaml`: D1-1-2 の直しの行。Java 版の `AppExceptionHandler`(47〜55行目)と `CookieUtil.deleteCookie`(80〜89行目。`Path=/`)、`ResetPasswordUseCase`(42〜47行目)で状態の番号・文言・Cookie の順とパスを確かめた。harness の `compareenv.go`(79〜80行目)で、compare が版ごとに Store(Redis)を持つことを確かめた
- design.md「認証の受け口」の `startOidcAuthorization` の `Content-Type` の段と応答の表、「ファイルの構成」の `auth.go`、「httpapi.New の変更」の `NewStrictHandlerWithOptions` の中間処理、「認証の操作の筋書き」の `oidc-google.yaml`: D1-1-3 の直しの行。Java 版の `OidcAuthorizationController`(40〜43行目。`produces` 無しで `String` を返す)で Accept に依ることを確かめ、`gen.StrictMiddlewareFunc`(`api.gen.go` 8161行目)が `r` を受けることを確かめた
- design.md「作るものと作らないもの」の `### 作らないもの`: 箇条を2つ消した行。requirements.md の「範囲」の「この spec で決めないこと」と、雛形 `.kiro/settings/templates/specs/design.md` の `### 作らないもの` の注釈と照らした
- design.md「テスト」の `make compat` `make compat-cross` `make compat-perf` の箇条: 要件の番号を文で言い換えた行。requirements.md の要件4の受入基準3と要件5の受入基準1〜6と照らした(言い換えは合っている)
- design.md「使う既存の仕組み」の「6つのパッケージ」、「Cookies」の表と表の下、「redisjson」と「TwoFactor」の TTL の文、「筋書き」の表と表の下の箇条、「設計を見直すきっかけ」の理由の追記: 書き方の直しの行。中身が変わっていないことを前後と照らした(指摘なし)
- 「ログインの状態の版」を「世代の番号」に言い換えた行(`accesstoken.go`、`RefreshToken`、`EmailVerification`、`PasswordReset`、「テスト」、「性能」): design.md を「版」で検索し、言い換え漏れが無いことと、JWT の項目の名前 `tokenVersion` は変えていないことを確かめた(指摘なし)

### 申告

**1. 生成したコードの誤りの受け口 `ErrorHandlerFunc` を、経路が `/api/auth/` の下のときだけ 400 にし、ほかの経路は 500 のままにする** — 「httpapi.New の変更」、「認証の受け口」の4つ目の箇条、「変えた動きの一覧の項目」

- Issue の記載: なし。要件5の受入基準5は、認証の操作に限って、Java 版が 500 で答える形の誤った要求に 400 を返すと決めている
- 決めたこと: 全操作に共通の受け口の中で、経路の頭で 400 と 500 を分ける。ほかのまとまりの spec で 400 にする操作は、その経路をこの条件に足す
- 他にありえた選択肢: `startOidcAuthorization` の受け口で `provider` を自分で読み、操作の中で 400 にする(受け口は 500 のままにする)。または、受け口の条件を操作の名前で持つ
- 外れていた場合: 経路の頭で分けるので、`/api/auth/` の下に生成したコードの誤りを持つ操作が増えると、ほかのまとまりの spec が気づかないまま 400 になる(変えた動きの一覧の項目に、この点の断りがある)。操作の中で読む形にしていれば、`server.go` は置き換えの spec のままで済んだ

### 指摘

| ID | レベル | 該当箇所 | 内容 | 直し方の案 |
|---|---|---|---|---|
| D1-2-1 | 低 | design.md「認証の受け口」の4つ目の箇条「この受け口に届く誤りを持つのは、必須の問い合わせの項目を持つ `startOidcAuthorization` だけである」、「変えた動きの一覧の項目」の「`startOidcAuthorization` のほかに当たる操作は無い」 | `ErrorHandlerFunc` に届くのは必須の問い合わせの誤りだけではない。生成したコード `api.gen.go` は、Cookie の項目の値の読み取りの誤り(`InvalidParamFormatError`)も同じ受け口に渡す(`verifyTwoFactorAuth` の `twoFactorChallenge` は 1497〜1500行目、`logout` と `refreshToken` の `refreshToken` も同じ形)。oapi-codegen の runtime は Cookie の値をパーセントの書き方から戻すので、`%` のあとが16進でない Cookie の値は誤りになる。この要求に Java 版は Cookie の値をそのまま読んで答える(`logout` は仕様書のとおり 204)が、Go 版は 400 と「入力エラーがあります。」になる。画面はこの値を送らず、筋書きにも無いので、実装と検査には影響しない。ただし「だけである」「当たる操作は無い」の断りは事実と合わない | 2つの断りを「必須の問い合わせの項目を持つのは `startOidcAuthorization` だけである。Cookie の項目(`refreshToken` `twoFactorChallenge`)の値の形の誤りも同じ受け口に届く」の形に直し、Java 版と答えが変わる要求として、変えた動きの一覧の項目に添える。または、実装のときに runtime の Cookie の読み方を確かめ、誤りにならないなら今の文のままにする、と書く |
| D1-2-2 | 低 | design.md「認証の受け口」の `startOidcAuthorization` の `Content-Type` の段(「q の値が同じ型は、Accept に書かれた順に見る」「`text/plain` と `*/*` と `text/*` のどれよりも先に `application/json` に当たれば」)と、実装のときに確かめる5つの Accept | Spring は、Accept の型を書かれた順ではなく、具体的な型(`application/json` `text/plain`)を `text/*` より、`text/*` を `*/*` より先に並べてから選ぶ(`HeaderContentNegotiationStrategy` が `MimeTypeUtils.sortBySpecificity` で並べ替える)。そのため `Accept: */*, application/json` や `Accept: text/*, application/json` に Java 版は `application/json` を返すが、設計の規則では `*/*` か `text/*` に先に当たるので `text/plain;charset=UTF-8` になる。また、`Accept: text/html` のように `text/plain` でも `application/json` でもない具体的な型だけを送ると、Java 版は `StringHttpMessageConverter` が `*/*` を書けるので要求された型(`text/html;charset=UTF-8`)を返すが、設計の規則では `text/plain;charset=UTF-8` になる。実装のときに確かめる5つの Accept(無し、`*/*`、axios の既定、`text/plain`、`application/json`)はどれもこの違いを出さないので、「食い違えば Java 版に合わせる」の手順でも見つからない。画面は axios の既定だけを送り、筋書きの2つの要求もこの違いを出さないので、実装と検査には影響しない | 規則を「Accept の型を、具体的な型、`text/*` のような型の範囲、`*/*` の順に並べ、同じ段の中では q の大きい順、同じ q なら書かれた順に見る。最初に当たった型が `application/json` なら `application/json`、`text/plain` か `text/*` か `*/*` か Accept 無しなら `text/plain;charset=UTF-8`」の形に直す。ほかの具体的な型だけの Accept は、Java 版の答えを実装のときに確かめ、Go 版が `text/plain;charset=UTF-8` にするなら変えた動きの一覧に載せるか、仕様書の「Accept で変わる」の範囲として Java 版と同じにする、と書く。確かめる Accept に `*/*, application/json` を足す |
| D1-2-3 | 低 | design.md「作るものと作らないもの」の `### 作らないもの` | 往復1の本文にあった「認証の機能の追加と、認証の仕様の変更」と「本番の切り替え」の2つが消え、「本番の設定の変更」だけが残った。requirements.md の「範囲」の「この spec で決めないこと」は、この2つを決めないことに挙げている(「Issue #445 の『やらないこと』で、所有者が、置き換えでは機能を足さず、仕様も変えないと決めたため」「本番の切り替えは、置き換えの spec が受け持つ」)。雛形は `### 作らないもの` を「『ついでに』取り込んではいけない変更を書く」場所と定めているので、所有者が決めた「機能を足さず、仕様も変えない」をここから外すと、tasks と実装の確認役が、ついでの変更を止めるよりどころを失う。設計の本文はこの2つを扱っていないので、本文との矛盾ではない | `### 作らないもの` に「認証の機能の追加と、認証の仕様の変更。Issue #445 の『やらないこと』で所有者が決めた」と「本番の切り替え。置き換えの spec が受け持つ」を戻す |

### 前の段階への指摘

なし

- 往復: 2回で収束 / 未解決: 0件

## サイクル2 往復1(2026-11-10)

### 審査の範囲

範囲: 差分

- design.md「ファイルの構成」の `backend/internal/auth/*_test.go` の箇条と「テストの方針」の「結合テスト:」の行: ビルドタグを外し testcontainers-go に替えた直しの行。既存の `backend/internal/platform/redisstore/redisstore_integration_test.go`(ビルドタグ無し、`TestMain` で Valkey `valkey/valkey:8.0.12-alpine` を起動)と `database_integration_test.go`(ビルドタグ無し、`postgres:17.11-alpine` を起動)、`backend/Makefile` の `test`(`go test -race -coverprofile ... ./...`、タグ無し)、`.github/workflows/ci.yaml` の Go 版の検査(`make check`)で、「`make test` と CI で毎回動き、カバレッジに入る」が事実であることを確かめた。結合テストが読み書きする表(「データベースの表」の節の5つの表)を、起動したばかりの Postgres にどう作るかが本文に無いので、`backend/migrations.go`(`go:embed` で Flyway の SQL を埋め込む `Migrations()`)、`internal/platform/migrate` の `Run` の `Apply`、`migrate/main_test.go` の `migrationFS`、`.golangci.yml` の depguard(機能のパッケージから最上位の `backend` パッケージと `internal/platform` を読めること)で、実装のときに作れることを確かめた
- design.md「Middleware」の `RequireLogin` の5つの箇条、「認証の受け口」の箇条の前置き(3つと1つ)、「使う既存の仕組み」の6つの箇条: 数を書いた行。箇条の数と照らした(合っている)
- design.md「認証の受け口」の4つ目の箇条と「httpapi.New の変更」の `ErrorHandlerFunc` の段、「変えた動きの一覧の項目」の対象の外の `provider` の項目と「OIDC」の節の対象の外の `provider` の箇条(498行目): 参照先に書き換えた行。参照先の節の中身と、requirements.md の要件5の受入基準5と照らした
- design.md「Validate」の `@Pattern` の行: 見えない文字を ` ` ` ` の書き方に直した行。今の本文が ` ` ` ` の文字列で書かれていることを Grep で確かめた(指摘なし)
- 「httpapi.New の変更」の「経路の記録」を「経路の登録」に直した行: サイクル1の申告2と「Middleware」の「いつ動くか」の呼び方と照らした(合っている)
- そのほかの差分の行(主語を足した行、「(10分)」「(7日)」を文に直した行、`BaseException` ほかの「受け口にあたる」を言い換えた行、「関係のない項目」に理由を足した行、depguard の説明を足した行、「見直すきっかけ」の筋書きの形の行、harness の節の主語の行、「安全」の主語の行): 書き方の直しの行。前後と照らし、中身が変わっていないことを確かめた(指摘なし)

### 申告

なし(この往復の差分に、新しく決めた選択肢は無い。結合テストを testcontainers-go で動かすことは、既存の結合テストと `backend/CLAUDE.md` の「結合テストは testcontainers-go で Postgres と Redis を動かす」の決まりのとおりで、選ぶ余地が無い)

### 指摘

| ID | レベル | 該当箇所 | 内容 | 直し方の案 |
|---|---|---|---|---|
| D2-1-1 | 低 | design.md「ファイルの構成」の `backend/internal/auth/*_test.go` の箇条、「テストの方針」の「結合テスト:」 | 開発環境の Postgres を使う形から、テストの中で起動する Postgres を使う形に替えたので、起動したばかりの Postgres には `users` `user_token_versions` ほかの表が無い。パスワードの再設定の結合テスト(世代の番号の繰り上げ)は表が要るが、表をどう作るかが本文に無い。既存の `database_integration_test.go` は表を使わないので、「同じく」と書いただけでは手順が決まらない。ただし、`backend/migrations.go` の `Migrations()` と `internal/platform/migrate` の `Run(..., Apply)` で Java 版と同じ表を作れ(`migrate/main_test.go` の `migrationFS` が同じ形で読む)、depguard も機能のパッケージから両方を読むことを許すので、実装のときに作れる。実装と検査には影響しない | 箇条に「Postgres を使うテストは、`TestMain` で、`backend.Migrations()` を `migrate.Run` の `Apply` で流して、Java 版と同じ表を作る」と書く |
| D2-1-2 | 低 | design.md「OIDC」の対象の外の `provider` の箇条(498行目)と、「変えた動きの一覧の項目」の対象の外の `provider` の項目 | 一覧の項目は「Java 版が 500 で答えたときだけ足す」と書き、「OIDC」の節を参照する。参照先の「OIDC」の節は「Java 版が 500 で答え、Redis に記録を残すなら」と2つの条件で Go 版の答えを決めており、Java 版が 500 で答えて Redis に記録を残さないときの Go 版の答えを決めていない。requirements.md の要件5の受入基準5は、Java 版が 500 で答える形の誤った要求には記録の有無によらず 400 で答えると決めているので、実装は要件に従えば迷わない。実装と検査には影響しない | 「OIDC」の箇条を「Java 版が 500 で答えるなら、Go 版は 400 で答え、Redis に記録を残さない」の1つの条件に直す |

### 前の段階への指摘

なし

- 往復: 1回で収束 / 未解決: 0件

## サイクル3 往復1(2026-11-10)

### 審査の範囲

範囲: 差分

- design.md「Java 版と Go 版を比べる検査の広げ方(harness)」の「回ごとに準備の段を送り直す測り方」の箇条と、対応する要件に 5.6 を足した行: 直し(1)の行。`backend/compat/harness/perf.go`(`prepare` が準備の段を1回だけ送り、`MeasureLatency` が最後の段を慣らし20回と測る200回送る)、`perfenv.go`(`RunPerf` と `measure` が `MeasureLatency` を呼び、`PerfEnv` が `Stack` を持つ)、`scenario.go`(`Scenario` の欄、`LoadScenario` が1つのファイルから1つの筋書きだけを読むこと、`validatePerf`)、`compareenv.go`(fakeaws のメールの記録の読み方)で、書いたとおりに作れるかを確かめた。Java 版の `usecase/auth` を「rate|attempt|limit」で検索し、2段階認証のコードの発行に送る間隔の制限が無いこと(220回のログインが断られないこと)と、メールの送り出しが `@Async` でなく同期であること(ログインの応答のあとに読んだ最後のメールがその回のメールになること)を確かめた
- 「two-factor.yaml」で design.md を検索して見つけた「認証の操作の筋書き」の役割の段(「どの筋書きも `fixtures/users/basic.sql` を使う」)と表と場面の箇条: 直し(1)が `two-factor.yaml` の中の「測る筋書き」と、その筋書きのログインの段に2段階認証の確認のメールが届くことを前提にするため。`backend/compat/fixtures/users/basic.sql` の2人の利用者の `two_factor_auth_enabled` と、置き換えの spec の design.md の「筋書きのファイルの形」(1つのファイルが1つの筋書き)と照らした
- design.md「テストの方針」の `make compat-perf` の箇条: 直し(1)の行。requirements.md の要件5の受入基準6と照らした(4つの操作を測ることは変わっていない)
- design.md「ファイルの構成」の `docker/backend-go/Dockerfile.prod` の箇条: 直し(2)の行。`docker/backend-go/Dockerfile.prod`(組み立ての段が `migrations.go` `cmd` `internal` とマイグレーションのファイルだけをコピーしていること)、`backend/.dockerignore`(`src/main/resources/mail` と `.go` を除かないこと)、`backend/compat/harness/images.go`(比べる検査が `docker/backend-go/Dockerfile.prod` を文脈 `backend` で組み立てること)で確かめた。あわせて、本番に関わるファイルを変えるので、`### 作らないもの` の「本番の設定の変更」と照らした
- design.md「API の説明画面での確認」の節: 直し(3)の行。`compose.yaml` の `backend-go`(`./backend` を差し込んで `go run` で動かす)と `api-docs` と `localstack`、`docker/localstack/init-localstack.sh`(SES の送り元の確認済みの登録)、`backend/internal/platform/awsclient/awsclient.go`(Go 版は SES v1 を使う)、`docker/db/` と `backend/src/main` に利用者の初期のデータが無いことを確かめた。requirements.md の要件6の受入基準1〜3と照らした
- design.md「認証の受け口」の箇条の前置き(「守ることを3つと、確かめることを2つ」)と、`Content-Type` の段から確かめの箇条を移した行: 箇条の数を数え(守ること3つ、確かめること2つで合っている)、移した箇条の「下の規則」が次の段を指すことを確かめた
- 「失敗したときの扱い」から「安全」へ、ログに秘密を書かない文を移した行: 移した先の「安全」の箇条に、消した文の4つの値がそろっていることを確かめた(中身は変わっていない)
- そのほかの差分の行(概要の文の順の入れ替え、ArchUnit の文を2つに分けた行、`Error` の2つの箇条を分けた行、`Identify` と `RequireLogin` の「いつ動くか」を分けた行、`authctx` の呼び出し方を箇条にした行、`redisjson` のハッシュの説明を足した行、「httpapi.New の変更」の深さの文を分けた行と `ErrorHandlerFunc` の文を言い換えた行、「性能」の文を分けた行): 書き方の直しの行。前後と照らし、中身が変わっていないことを確かめた(指摘なし)

### 申告

**1. 2段階認証の確認の応答の時間を、回ごとにログインからやり直す筋書き(`prepare_each`)で測る** — 「Java 版と Go 版を比べる検査の広げ方(harness)」の「回ごとに準備の段を送り直す測り方」、「テストの方針」の `make compat-perf`

- Issue の記載: なし。Issue は置き換えの spec の要件 9.7(応答の時間を比べる)を満たすとだけ書き、requirements.md の要件5の受入基準6が、測る操作に2段階認証の確認のコードの入力を挙げている
- 決めたこと: 筋書きに真偽の欄 `prepare_each` を足し、慣らしの20回と測る200回のそれぞれの前にログインの段を送り直して、届いたメールから確認のコードを取り出す。同時に送ってメモリを測る欄は付けない
- 他にありえた選択肢: Redis を書き換える段で、測る回ごとに `2fa:<利用者の ID>` と `2fa:challenge:<値>` に決まった値を置き、Cookie `twoFactorChallenge` を筋書きから送る(bcrypt を含むログインを回ごとに送らずに済む)。2段階認証の確認だけ測る回数を減らす
- 外れていた場合: 筋書きの形に足した欄 `prepare_each` は、ほかのまとまりの筋書きも使える形として残る。回ごとに bcrypt のログインを送るので、`make compat-perf` の時間は、版ごとに220回のログインの分だけ延びる。測る値そのもの(最後の段の時間)は、どちらの方式でも変わらない

### 指摘

| ID | レベル | 該当箇所 | 内容 | 直し方の案 |
|---|---|---|---|---|
| D3-1-1 | 中 | design.md「Java 版と Go 版を比べる検査の広げ方(harness)」の「回ごとに準備の段を送り直す測り方」の「`two-factor.yaml` の測る筋書きは、`prepare_each` を真にし」、「認証の操作の筋書き」の表の `two-factor.yaml`(compare、cross、perf)と `refresh-logout.yaml`(作り直しだけ perf)と `register.yaml`(登録だけ perf) | `prepare_each` は筋書き(`Scenario`)の欄で、測るのは筋書きの最後の段である。2段階認証の確認を測るには、ログインと確認の2つの段だけを持ち、最後の段が成功する確認になる筋書きが要る。一方、`two-factor.yaml` には、誤ったコード、5回目で上限、Cookie の無い確認の場面も入るので、測る筋書きは、ほかの場面の筋書きと別の筋書きになる。今の harness の `LoadScenario`(`backend/compat/harness/scenario.go` 86〜101行目)は、1つのファイルから YAML の文書を1つだけ `Decode` し、2つ目からの文書は誤りにもせずに読み捨てる。置き換えの spec の「筋書きのファイルの形」も、1つのファイルを1つの筋書きとしている。設計は、1つのファイルに複数の筋書きを置く形も、測る筋書きを別のファイルに置く形も書いておらず、`scenario.go` の広げ方(「呼び出し方」の箇条)にも、複数の筋書きを読むことが無い。実装が `two-factor.yaml` に `---` で筋書きを並べると、2つ目からの筋書きが黙って読まれず、測る筋書きか、compare と cross の場面の一部が動かないまま検査が通る。ファイルを分けると、「ファイルの構成」の10のファイルと「テストの方針」の「10のファイル」と食い違う | 次のどちらかを本文に書く。(a) 測る筋書きを別のファイル(例: `two-factor-perf.yaml` `refresh-perf.yaml` `register-perf.yaml`)に置き、「ファイルの構成」の筋書きのファイルの並びと「テストの方針」のファイルの数を直す。(b) harness の広げ方に「1つのファイルに `---` で区切った複数の筋書きを置けるようにし、`LoadScenario` は文書をすべて読む。読めない文書があれば誤りにする」を足し、`two-factor.yaml` の測る筋書きがファイルの中のどれかを書く |
| D3-1-2 | 低 | design.md「認証の操作の筋書き」の役割の段「どの筋書きも、置き換えの spec の段階2の利用者の初期のデータ(`fixtures/users/basic.sql`)を使う」と、「回ごとに準備の段を送り直す測り方」の「回ごとにログインの段を送り、その段のあとに届いたメールから確認のコードを `mail:` で取り出す」 | `backend/compat/fixtures/users/basic.sql` の2人の利用者(user1 と user2)は、どちらも `two_factor_auth_enabled` が `FALSE` である。この初期のデータだけでは、ログインの段は 200 で答え、確認のコードのメールが届かないので、`mail:` の取り出しが失敗する。2段階認証を有効にする操作は利用者のまとまりの操作で、Go 版ではまだ「未実装です。」を返すので、筋書きの段でも有効にできない。2段階認証を有効にした利用者の初期のデータのファイルが要るが、「ファイルの構成」の作るファイルに無く、役割の段の「どの筋書きも basic.sql を使う」とも合わない。筋書きの欄 `fixtures` は複数のファイルを受けるので、実装のときに初期のデータのファイルを足せば作れる。実装と検査には影響しない | 役割の段を「どの筋書きも basic.sql を使う。2段階認証の筋書きは、加えて、2段階認証を有効にした利用者の初期のデータ(例: `fixtures/users/two-factor.sql`)を使う」の形に直し、作るファイルにそのファイルを足す |
| D3-1-3 | 低 | design.md「ファイルの構成」の変えるファイル `backend/compat/harness/scenario.go` `send.go` `normalize.go` `stack.go` `compare.go` `cross.go` `perf.go` の箇条と、「回ごとに準備の段を送り直す測り方」の「harness は、応答の時間を測るときにも、メールを読む部品を筋書きの実行に渡す」 | 応答の時間を測る処理を版の環境から呼ぶのは `backend/compat/harness/perfenv.go` の `measure`(`MeasureLatency(ctx, p.client, p.URL, s, ...)`)で、メールを読む部品(`Stack` の fakeaws の記録)を渡すには、このファイルも変える。`perfenv.go` は変えるファイルの並びに無い。同じく、Redis を書き換える段と `mail:` の取り出しを compare と cross で動かすには、版ごとの Redis と fakeaws を持つ `compareenv.go` と `crossenv.go` も変えることになるはずだが、並びに無い。実装は並びに無いファイルを変えれば済み、実装と検査には影響しない | 変えるファイルの並びに `perfenv.go`(と、変えるなら `compareenv.go` `crossenv.go`)を足す |
| D3-1-4 | 低 | design.md「作るものと作らないもの」の `### 作らないもの` の「本番の設定の変更」と、「ファイルの構成」の `docker/backend-go/Dockerfile.prod` の箇条(「このイメージは、Java 版と Go 版を比べる検査と本番の両方が使う」) | 本番の Go 版のイメージを組み立てる `Dockerfile.prod` を変える一方で、作らないものに「本番の設定の変更」がある。足すのはコードを組み立てるためのファイルのコピーで、本番の設定(環境変数・秘密の値・タスクの定義)ではないので、中身は矛盾しない。ただし本文にその断りが無いので、tasks と実装の確認役が「本番の設定の変更」にあたると読む余地がある | `Dockerfile.prod` の箇条に「この変更は、組み立てに要るファイルを足すだけで、本番の設定(環境変数、秘密の値、タスクの定義)は変えない」と足すか、作らないものの箇条を「本番の設定(環境変数、秘密の値、タスクの定義)の変更」と書く |

### 前の段階への指摘

なし

- 往復: 1回目 / 高0 中1 低3

## サイクル3 往復2(2026-11-10)

### 審査の範囲

範囲: 差分

- design.md「ファイルの構成」の `backend/compat/scenarios/auth/*.yaml` の箇条(測る筋書きを別のファイルに置く文と、その理由の文): D3-1-1 の直しの行。`backend/compat/harness/scenario.go` の `LoadScenario`(1つのファイルから1つの文書だけを `Decode` する)と `LoadScenarios`(フォルダの下の `.yaml` をすべて読み、`modes` に当たる筋書きだけを返す)、`validatePerf`(perf の筋書きは最後の段に `expect` の `status` が要る)、`perf.go` の `prepare` と `MeasureLatency`(測るのは最後の段だけ)で、理由の文が事実と合うことと、`modes: [perf]` だけのファイルを同じフォルダに置いても compare と cross に混ざらないことを確かめた
- design.md「認証の操作の筋書き」の表(perf を外した4行と、足した4つのファイルの行): D3-1-1 の直しの行。`backend/compat/compat_test.go` の `TestCompare_Scenarios` と `TestCoverage_Operations` が `LoadScenarios(..., ModeCompare)` で読むこと、`perf_test.go` の `TestPerf_Scenarios` が `ModePerf` で読むことで、perf だけのファイルが compare の数と操作の網羅の数え方に入らないことを確かめた。足した4つのファイルが、それぞれ測る操作を最後の段に持てるかを、Java 版の動き(`refreshToken` は `accessToken` だけを返し、ログインを続けるための値を作り直さないので最後の段を繰り返せること。`UserRegistrationUseCase` は同じメールアドレスの登録を繰り返しても、送る間隔の制限に当たったときも登録を受け付けること。`/api/auth` の下は偽の送信の検査を受けないので、ログインと2段階認証の確認の前にトークンを受け取る段が要らないこと)で確かめた
- design.md「Java 版と Go 版を比べる検査の広げ方(harness)」の「回ごとに準備の段を送り直す測り方」の箇条(`two-factor-perf.yaml` に直した文): D3-1-1 の直しの行。表の `two-factor-perf.yaml` の行(ログインと確認の2つの段だけ)と照らし、`prepare_each` で送り直すのがログインの段だけになることを確かめた
- 「two-factor」「perf」「10の」で design.md を検索して見つけた「テストの方針」の `make compat`(10のファイルを compare で動かす)と `make compat-perf`(4つの操作)の箇条、「筋書きごとの場面」の箇条: D3-1-1 の直しでファイルの数と測る筋書きの置き場所が変わったため。compare で動かすファイルが10のままであることと、場面の箇条の `two-factor.yaml` の中身(誤ったコード、5回目で上限、Cookie の無い確認)が測る筋書きと分かれたことを確かめた(指摘なし)
- design.md「Service」の「失敗したとき」の「包む」の説明の行、「Middleware」の「いつ動くか」の行、「認証の受け口」の「失敗したとき」の行、「EmailVerification」と「PasswordReset」の主語を足した行: 書き方の直しの行。「いつ動くか」は、消した「分ける」の文の中身が、参照先の「httpapi.New の変更」の節の並び(値を読む段、偽の送信の検査、ログインを求める段)にあることを確かめた。ほかの行は前後と照らし、中身が変わっていないことを確かめた(指摘なし)

### 申告

なし(この往復の差分に、新しく決めた選択肢は無い。測る筋書きを別のファイルに置くことは、往復1の指摘 D3-1-1 の直し方の案(a)のとおりで、今の harness の読み方に合わせたものである)

### 指摘

なし

### 前の段階への指摘

なし

- 往復: 2回で収束 / 未解決: 0件

## サイクル4 往復1(2026-11-11)

### 審査の範囲

範囲: 全体

- 範囲を「全体」にした理由: 審査の途中で会話が自動で要約され、起動の文の「前回からの差分」の差分の全文が会話に残っていなかったため。design.md と requirements.md と前回までの記録をファイルから読み直し、design の本文の全体を審査した
- とくに、今回直した harness の節(4種類の段、取り出しの元、差し込み、版に送る要求の Host、`prepare_each`、文字の本文と `#` のあとと確認のコードと JWT の正規化、cross の送り先)、fakeoidc の節(断る残りの回数、利用者の設定、`api.github.com`)、筋書きの節と「筋書きごとの場面」、「ファイルの構成」の `expire.go` `auth-users.sql` `compareenv.go` `crossenv.go` `perfenv.go`、「テストの方針」を、今の harness のコードと照らした。照らしたのは `backend/compat/harness/` の `scenario.go`(段の欄、`validate` と `validateCross` と `validatePerf`、`LoadScenario`)、`send.go`(`Session` の Cookie の束と取り出した値、`storeCookies`、`capture`、`expandPath`)、`stack.go`(`fakes` の `jwtSecret`、`registerRedirects`)、`compareenv.go`(版ごとの Store と fakeaws の別名、段ごとに Java 版と Go 版へ送る `Run`)、`crossenv.go` と `cross.go`(1つの Stack と1つの Session、`CrossRoute` が最後の段を前の段と違う版に送ること、どの向きも同じ `expect` で確かめること)、`perf.go` と `perfenv.go`(`StartPerfEnv` が版ごとに別の Stack を作ること)、`normalize.go`(`urls()` の `?` と `#` の区切り、`=` の無い部分を残すこと、`jwt()` の項目の除き方)、`compare.go`(比べるヘッダ、JSON として読めない本文を文字の本文として比べること、メールの本文に URL の置き換えだけを通すこと)、`versions.go`(Go 版に `APIBaseURL` を設定しないこと)と、`backend/compat/fakeoidc/`(`authorize` が `client_id` と `redirect_uri` を確かめ、利用者が無ければ 409 を返すこと、`token` が `redirect_uri` と PKCE を確かめること、利用者を消す口が無いこと)と、`backend/compat/fixtures/users/basic.sql`(2人とも2段階認証が無効で確認済み)である
- 筋書きの場面が作れるかは、Java 版の `DevBaseUrlResolver`(Tomcat の `getServerName` と `getServerPort` で戻り先を作り、http でポート80ならポートを書かないので、ポートの無い `Host: compat.test` で `http://compat.test/api/auth/oidc/callback` になること)、`JwtEmailVerificationTokenCodec`(`exp` を付けず `aud` と `lexp` を持つこと)、`JwtProvider`(HMAC256 で `tokenVersion` を確かめること)、`LogoutController`(ログアウトの利用者を、まず Cookie `refreshToken` から、無ければ `accessToken` から決めること)、`SecurityConfig`(`/api/admin/**` に `hasRole("ADMIN")`、ログインしていなければ本文の無い 401、役割が足りなければ 403 と `{"message":"アクセス権限がありません。"}`)で確かめた
- 「ログインしたまま」「ログインの要る操作」で requirements.md を検索し、要件4の受入基準1と3を、筋書きの節の最後の段落と「テストの方針」の `make compat-cross` の箇条と照らした

### 申告

**1. 版に送るすべての要求の `Host` を `compat.test` にし、偽のログインのサービスに `http://compat.test` を戻り先として1つだけ登録する** — 「Java 版と Go 版を比べる検査の広げ方(harness)」の「版に送る要求の Host」

- Issue の記載: なし
- 決めたこと: 版ごとにポートの違う戻り先の URL を、`Host` を同じにすることで両方の版でそろえる。送る先のアドレスは版のポートのまま変えない
- 他にありえた選択肢: 偽のログインのサービスに、版ごとの URL を両方とも戻り先として登録し、比べる処理で戻り先の URL のポートを正規化する。Go 版にだけ `APIBaseURL` を設定する
- 外れていた場合: 認証のほかのまとまりの筋書きも含めて、版に送るすべての要求の `Host` が変わる。Java 版か Go 版が `Host` を使う動き(戻り先のほかに URL を作る操作)があれば、その答えも `compat.test` を含む形に変わる。両方の版で同じに変わるので比べる検査では差にならないが、本番の `Host` での答えを確かめていないことになる

**2. ログインの状態の値と確認のリンクの値の期限切れを、harness が検査の鍵で JWT を署名し直して作る** — 「値を期限切れにする段」

- Issue の記載: なし
- 決めたこと: 筋書きに `expire` の段を足し、JWT の項目を写して期限の項目だけを過去にし、検査を始めるたびに作った鍵で署名し直す
- 他にありえた選択肢: 検査の間だけ、両方の版の値の有効な時間を短い設定にして、待って期限を切らす。期限切れの場面を単体のテストだけで確かめる
- 外れていた場合: harness が、両方の版の署名の作り方(ログインの状態の値は設定の秘密の値そのもの、確認のリンクの値は秘密の値から作った鍵)を写して持つ。版の鍵の作り方が変わると、筋書きが期限ではなく署名を理由に断られ、期限切れの場面を確かめないまま答えだけがそろう

**3. 確認の済んでいない利用者と2段階認証を有効にした利用者を、初期のデータ `fixtures/users/auth-users.sql` で置く** — 「認証の操作の筋書き」の役割の段

- Issue の記載: なし
- 決めたこと: この spec の範囲の Go 版は2段階認証を有効にする操作を未実装の答えで返すので、筋書きの段では作れない利用者を、SQL の初期のデータで置く
- 他にありえた選択肢: Redis を書き換える段と同じように、データベースを書き換える段を足す。2段階認証の場面を、利用者のまとまりの spec まで待つ
- 外れていた場合: 初期のデータの列の値(確認の済んでいるかの列、2段階認証の列)が、Java 版の登録と2段階認証を有効にする操作が書く値と違うと、筋書きの前提が実際の利用者と違う形になる。両方の版が同じ初期のデータを読むので、比べる検査では差にならない

### 指摘

| ID | レベル | 該当箇所 | 内容 | 直し方の案 |
|---|---|---|---|---|
| D4-1-1 | 中 | design.md「認証の操作の筋書き」の最後の段落(647行目「ログインした利用者がログインの要る操作を呼べる場面は、筋書きに入れない」)、「テストの方針」の `make compat-cross` の「ログインしたままの利用者の操作を含む」(731行目)、`middleware.go` の単体テスト(724行目) | 段落は、この場面を筋書きに入れない理由を「Go 版はログインの要る操作をすべて未実装の答えで返すので、Java 版の 200 と必ず違う」とする。しかし、`/api/admin/` の下の経路は、ログインした役割 `USER` の利用者に、両方の版が同じ答えを返す。Java 版は `SecurityConfig` の106行目で `/api/admin/**` に `hasRole("ADMIN")` を付け、ログインしていれば 403 と `{"message":"アクセス権限がありません。"}`(84〜88行目)を、ログインしていなければ本文の無い 401(82行目)を返す。Go 版の `RequireLogin` も、design 349行目のとおり同じ 403 と 401 を返し、仕様書に無い経路にも動く(351行目)ので、未実装の答えにはならない。そのため、`basic.sql` の利用者でログインしたあとの `GET /api/admin/<任意の経路>` は、受け取った版がログインの状態の値を受け入れれば 403、受け入れなければ 401 になり、どちらの版に届いても答えが同じである。cross は、どの向きでも1つの `expect` で確かめる(`cross.go` の `CrossRoute` と `RunCross`)ので、この段は3つの向きのすべてで通る。この場面が無いと、Go 版が作ったログインの状態の値を Java 版が受け入れることは、どの検査でも確かめられない。段落の単体テストは、Java 版と同じ項目と鍵で作った値を Go 版が受け入れる向きだけを確かめる。compare は Go 版が作った値を Go 版にだけ送る(`compareenv.go` の `Run`)。`refresh-logout.yaml` の作り直しは Cookie `refreshToken` だけで答え、Java 版のログアウトも利用者を先に `refreshToken` から決める(`LogoutController` 68〜82行目)ので、Java 版が Go 版の値を読まなくても cross は通る。Go 版が鍵の作り方を誤っても、compare と cross は通り、切り替えの途中で Go 版にログインした利用者は Java 版で 401 になる。要件4の受入基準1(一方の版でログインした利用者は、もう一方の版でも、ログインし直さずに使い続けられる)と受入基準3(ログインしたままの利用者の操作の両方の向きの筋書きを cross に足す)を、cross で確かめないことになり、731行目の「含む」とも合わない | `login.yaml` か `refresh-logout.yaml` に、ログインの段のあとに `to: other` で `GET /api/admin/<経路>` を送り、`expect.status` を 403 と `$.message` にする場面を足す。ログアウトのあとと、`expire.cookie: accessToken` のあとにも同じ経路を送り、401 にする場面を足すと、使えなくなった値を版をまたいで断ることも確かめられる。段落は「ログインした利用者が、200 を返すログインの要る操作を呼べる場面は入れない。ログインの状態の値を版をまたいで受け入れることは、`/api/admin/` の下の 403 で確かめる」の形に直す。この方式を採らないなら、Go 版が作った値を Java 版が受け入れることを確かめる別の検査を本文に書くか、要件4の受入基準3との食い違いとして requirements.md の側の扱いを所有者に諮る |
| D4-1-2 | 低 | design.md「harness」の取り出しの元の箇条(579行目「応答の時間を Java 版と Go 版で測って比べることでは、2つの版が1つの偽の AWS に送るので、harness は、その1つの記録からメールを読む」) | `perfenv.go` の `StartPerfEnv`(34〜37行目)は、版ごとに `startStack` を呼び、版ごとに別の Postgres と Redis と fakeaws と fakeoidc を作る(21〜22行目の説明のとおり)。応答の時間を測るときは、2つの版が1つの偽の AWS に送るのではなく、それぞれの版の環境の fakeaws に送る。それぞれの環境には fakeaws が1つだけなので、その環境の記録からメールを読めば済み、実装と検査には影響しない | 「応答の時間を測るときは、版ごとの環境に fakeaws が1つずつあるので、harness は、その版の環境の記録からメールを読む」の形に直す |
| D4-1-3 | 低 | design.md「harness」の JWT の正規化の箇条(589行目「`lexp` を時刻の差として比べる」)と、URL の `#` のあとの値の正規化の箇条(587行目) | 確認のリンクの値には `iat` も `exp` も無い(`JwtEmailVerificationTokenCodec` は `exp` を付けない)。今の `normalize.go` の `jwt()` は `exp - iat` だけを差として足し、ほかの時刻の項目はそのまま比べるので、`lexp` を何との差として比べるかが本文に無いと、実装は `lexp` を秒の値のまま比べる。Java 版と Go 版は同じ段を順に送るので、メールを出した秒がずれると `lexp` が1秒違い、比べる検査が差を出す。今回足した `#` のあとの正規化は、確認のリンクの値をこの決まりで比べるので、この決まりに頼るようになった。実装のときに差が出れば気づいて直せるので、検査が誤って通ることはない | 「`lexp` は、その版がメールを受けた時刻(fakeaws の記録の時刻)との差として比べ、Redis の残りの有効な時間と同じく5秒のずれを許す」のように、比べる基準と許すずれを書く |
| D4-1-4 | 低 | design.md「harness」の値を期限切れにする段の箇条(575行目「harness は、ヘッダの `alg` と JWT の項目の `aud` で、2つの値を見分ける」) | ログインの状態の値(`JwtProvider` の `Algorithm.HMAC256`)も確認のリンクの値も、ヘッダの `alg` は `HS256` で同じなので、`alg` では見分けられない。見分けに使えるのは `aud` の有無だけで、実装は `aud` で見分ければ迷わない | 「harness は、JWT の項目の `aud` があるかで2つの値を見分ける。どちらも `alg` は `HS256` である」の形に直す |
| D4-1-5 | 低 | design.md「fakeoidc」の利用者の設定の箇条(604行目「筋書きの終わりに、harness が利用者の設定を空に戻す」)と、ログインを断る動きの箇条(603行目) | `fakeoidc` には利用者の設定を消す口が無く、`PUT /_compat/users/google` に空の値を送ると、中身の空の利用者が登録される(`authorize` は利用者が登録されていれば 409 にしない)。また、断る残りの回数を筋書きごとに0に戻すことが書かれていないので、筋書きが `PUT /_compat/deny/{provider}` のあと、開始の要求を送る前に失敗すると、残った回数で次の筋書きのログインの開始が断られる。どちらも、失敗した筋書きのあとの筋書きにだけ出るので、すべての筋書きが通るときの検査の結果は変わらない | fakeoidc に、提供元ごとの利用者の設定と断る残りの回数を初めの状態に戻す口(例: `DELETE /_compat/state`)を足し、harness が筋書きの始めにこれを呼ぶ、と書く |

### 前の段階への指摘

なし

- 往復: 1回目 / 高0 中1 低4

## サイクル4 往復2(2026-11-11)

### 審査の範囲

範囲: 差分

- design.md「Middleware」の `RequireLogin` の段(349行目。主語を足し、403 の `Content-Type` を足した行): D4-1-1 の対応で足した行。Java 版の `SecurityConfig` の84〜87行目(`accessDeniedHandler` が `application/json;charset=UTF-8` を設定し、`{"message":"アクセス権限がありません。"}` を書くこと)と照らした。`backend/internal/httpapi/server.go` の75〜83行目(ログインを求める段の差し込み口 `Auth` が `mux` の全体を包むこと)で、仕様書に無い `/api/admin/users` への要求にもログインを求める段が動くことを確かめた
- design.md「認証の操作の筋書き」の `login.yaml` と `refresh-logout.yaml` の箇条と、最後の段落: D4-1-1 の直しの行。`backend/api/openapi.yaml` の73行目(`/api/admin/**` には受け付ける処理が無いこと)、Java 版の `SecurityConfig` の82行目と106行目、`JwtProvider` の120〜122行目(役割に `ROLE_` を付けて権限にするので、役割 `USER` の値でログインした利用者は `hasRole("ADMIN")` で 403 になること)、`backend/compat/fixtures/users/basic.sql` の10〜12行目(2人とも役割 `USER` だけを持つこと)で、`GET /api/admin/users` が、どちらの版でも、値を受け入れれば 403、受け入れなければ 401 になることを確かめた。「ログインした版と違う版に送る」が作れるかを、`backend/compat/harness/cross.go` の `CrossRoute`(36〜69行目)で確かめた(下の D4-2-1)
- 「admin」「403」「compat-cross」「middleware.go」で design.md を検索して見つけた「テストの方針」の `middleware.go` の項目(724行目)と `make compat-cross` の箇条(731行目): 最後の段落が単体のテストの中身をこの項目に任せるようになったため。また、731行目は直しの行。724行目に、Java 版の `JwtProvider` と同じ項目と鍵で作った JWT が、ログインを求める段を通って次の処理に届くことが書かれていることを確かめた(指摘なし)
- 「ログインし直さず」「ログインしたまま」で requirements.md を検索して見つけた要件4の受入基準1と3: 直しが確かめる受入基準のため。受入基準3の「両方の向き」は、`CrossRoute` の Java 版から Go 版への向きと、Go 版から Java 版への向きで確かめられることを確かめた(下の D4-2-1)
- design.md「安全のヘッダ」の節(541〜543行目): `RequireLogin` が返す 403 にも、Java 版と同じく安全のヘッダが付くかを確かめた。「httpapi.New の変更」の節の並び(安全のヘッダがログインを求める段より外にある)により付く(指摘なし)

### 申告

なし(この往復の差分に、新しく決めた選択肢は無い。管理者の経路への要求の答えで、ログインの状態の値を版が受け入れたかを確かめることは、往復1の指摘 D4-1-1 の直し方の案のとおりである)

### 指摘

| ID | レベル | 該当箇所 | 内容 | 直し方の案 |
|---|---|---|---|---|
| D4-2-1 | 低 | design.md「認証の操作の筋書き」の最後の段落(647行目「版をまたいで確かめる検査は、ログインした版と違う版にこの要求を送り、…3つの向きのすべてで確かめる」)と、`login.yaml` の箇条(636行目「正しいログインのあとに `GET /api/admin/users` を送り」)、`refresh-logout.yaml` の箇条(638行目) | `cross.go` の `CrossRoute`(36〜69行目)は、Java 版から Go 版と Go 版から Java 版の向きでは、`to: other` を付けた段と、筋書きの最後の段でだけ版を替える。交互の向きでは、`to` を見ずに、段の番号の偶奇で版を決める。`login.yaml` は1つの筋書きで、正しいログインのほかに、パスワードの誤りなどの場面の段も並ぶ。本文は、管理者の経路への段を筋書きのどこに置き、`to: other` を付けるかを書いていない。管理者の段を筋書きの途中に置いて `to: other` を付けないと、2つの向きでも、ログインした版と同じ版に送られ、Go 版が作った値を Java 版が受け入れることを確かめないまま検査が通る。箇条の並びのとおりに筋書きの最後に置くと、2つの向きでは版が替わるが、交互の向きでは、正しいログインの段と管理者の段の間の段の数によって、同じ版に送られ、「3つの向きのすべてで」が成り立たない。`refresh-logout.yaml` の、ログアウトのあとの管理者の経路への要求も、ログアウトを受けた版と違う版に送るかが書かれていない。ただし、段落は「ログインした版と違う版にこの要求を送り」と目的を書いており、要件4の受入基準3が求める2つの向きは、`to: other` を付ければ確かめられるので、実装は迷わない | 最後の段落か `login.yaml` の箇条に「管理者の経路への段は、正しいログインの段のすぐあとに置き、`to: other` を付ける。すぐあとに置くと、交互の向きでも、ログインした版と違う版に送られる」と書く。`refresh-logout.yaml` の、ログアウトのあとの段にも、ログアウトの段のすぐあとに置き、`to: other` を付けることを書く |

### 前の段階への指摘

なし

- 往復: 2回で収束 / 未解決: 0件

## サイクル5 往復1(2026-11-11)

### 審査の範囲

範囲: 差分

- design.md「ファイルの構成」の作るファイルの `tlsalias.go` の箇条と、足した `backend/mailtemplates_test.go` と `backend/internal/auth/testdata/mail/` の箇条、変えるファイルの `server.go` と `server_test.go` の箇条と、足した `env.go` と `versions.go` `versions_test.go` の箇条: T1-1-7 の直しの行。`backend/compat/harness/env.go`(`ContainerSpec` にファイルを写す欄が無く、`Start` が testcontainers-go の `ContainerCustomizer` の並びでコンテナを作ること。`backend/go.mod` の testcontainers-go は v0.45.0 で、ファイルを写す customizer を持つ)、`versions.go`(`Backing` に証明書の置き場が無く、`JavaEnv` と `GoEnv` が環境変数を返す関数であること)、`backend/internal/httpapi/server_test.go` と `harness/versions_test.go` が既にあること、`backend/src/main/resources/mail/` に5つのひな形があり、「Mail」の節の表が使う4つ(`email-verification.ftl` `password-reset.ftl` `two-factor-auth.ftl` `user-registered.ftl`)が含まれること、`application-dev.yaml` が Java 版の AWS の送り先を LocalStack にしていることと、research.md の P9 が LocalStack の SES の送ったメールの一覧(`/_aws/ses`)から件名と本文を読んで比べたことで、書いたとおりに作れることを確かめた。tasks-review.md の T1-1-7 が挙げた5つ(`env.go`、`versions.go` と `versions_test.go`、`testdata/mail/`、ひな形の埋め込みのテスト、`server_test.go`)がすべて足されたことを確かめた
- 「信頼の束」「SSL_CERT_FILE」「tlsalias」で design.md を検索して見つけた「偽のログインのサービスの広げ方」の「使う部品」(611行目)と「安全」(744行目): `tlsalias.go` の箇条を「Java 版に渡す信頼の束と、Go 版に渡す認証局の証明書」に書き分け、`env.go` と `versions.go` の箇条で渡し方を足したため。611行目の、Java 版には PKCS12 の信頼の束を `JAVA_TOOL_OPTIONS` で、Go 版には認証局の証明書を `SSL_CERT_FILE` で渡す書き方と合うことを確かめた。`docker/backend/Dockerfile.prod` が `JAVA_TOOL_OPTIONS` を設定していないので、`JavaEnv` で足しても上書きにならないことも確かめた(指摘なし)
- 「mail_test」「testdata」「4種類」で design.md を検索して見つけた「Mail」の節(528〜537行目)と「テストの方針」の `mail.go` の項目(727行目): `testdata/mail/` の箇条が `mail_test.go` の比べる相手を決めたため。727行目の「試作で Java 版と一致した文字列」と、`testdata/mail/` の「開発環境の Java 版が LocalStack の SES に送ったメールから作る」は、どちらも Java 版の出力で、research.md の P9 の試作の作り方とも合う(指摘なし)。「テストの方針」が `server_test.go` と `mailtemplates_test.go` を挙げていないことは下の D5-1-1
- design.md「Java 版と Go 版を比べる検査の広げ方(harness)」の取り出しの元の箇条(583行目)と、値を期限切れにする段の箇条(579行目): T1-1-8 の直しの行。`backend/compat/harness/perfenv.go` の `StartPerfEnv`(32〜35行目。版ごとに別の env を渡し、`startStack` で fakeaws を含む環境を作る)と、Java 版の `JwtProvider`(61行目。`Algorithm.HMAC256`、`aud` を付けない)と `JwtEmailVerificationTokenCodec`(53〜61行目。`Algorithm.HMAC256`、`withAudience`)で、2つの文が事実と合うことを確かめた。D4-1-2 と D4-1-4 の直し方の案のとおりである
- design.md「Middleware」の `Identify` と `RequireLogin` の「いつ動くか」(355行目): 理由の文を書き直した行。`backend/internal/httpapi/middleware/csrf.go` と `errors.go`(偽の送信の検査が断るときに `Content-Type` だけを設定して書き、前の段が置いた `Set-Cookie` を消さないこと)で、`Identify` が足した `Set-Cookie` が 403 の応答に残ることを確かめた(指摘なし)
- そのほかの差分の行(概要の `internal/httpapi` の行、`### 作らないもの` の CORS の説明、「設計を見直すきっかけ」の JWT の説明、「使う技術」の TLS の説明、`BumpTokenVersion` の文を分けた行、応答の表の `startOidcAuthorization` の行、`Content-Type` を確かめる箇条の charset の言い換え、「認証の受け口」の主語を足した2つの行、「httpapi.New の変更」の見出しの言い換え、`consumeJSONIfEqual` の消し込みの説明、「OIDC」の「権限」の主語を足した行、Redis を書き換える段の理由の言い換え、「テストの方針」の「確認」の言い換え): 書き方の直しの行。前後と照らし、中身が変わっていないことを確かめた。見出しの言い換えは、本文の参照が「httpapi.New の変更」の名前で節を指しており、今の見出しもこの名前で始まるので、参照は切れていない(指摘なし)
- `.kiro/specs/backend-go-auth/spec.json`: 審査の範囲によらず読むファイルとして読んだときに、`approval_history` の3つ目の要素の `revoked_for` の文字化けを見つけた(下の D5-1-2)

### 申告

なし(この往復の差分に、外れたときの手戻りの大きい新しい決定は無い。足したファイルは、tasks の審査の T1-1-7 のとおり、design の部品の節の中身を作るのに要るファイルであり、メールの正解のファイルの作り方は research.md の P9 の試作と同じ方法である)

### 指摘

| ID | レベル | 該当箇所 | 内容 | 直し方の案 |
|---|---|---|---|---|
| D5-1-1 | 低 | design.md「テストの方針」の「単体テスト:」(722〜729行目)と、「ファイルの構成」の `server.go` と `server_test.go` の箇条(170行目)、`backend/mailtemplates_test.go` の箇条(165行目) | 「ファイルの構成」は、`server_test.go` に「中間処理の順と安全のヘッダを確かめるテスト」を足し、`mailtemplates_test.go` で「埋め込んだひな形から4つのファイル名が読めること」を確かめると書くが、「テストの方針」の単体テストの並びは、どちらも挙げていない。並びにある `securityheaders.go` の項目は中間処理を1つだけで確かめるもので、中間処理の順(`Identify` が偽の送信の検査より前に動くので 403 にも Cookie を消す `Set-Cookie` が付くこと、6つのヘッダが CORS と偽の送信の検査の 403 にも付くこと)を確かめるのは `server_test.go` だけである。「ファイルの構成」の箇条に中身が書いてあり、tasks の 4.4 と 1.1 も作るので、実装と検査には影響しない | 「テストの方針」の単体テストに、`server.go`(`New` が並べた中間処理の順で、偽の送信の検査が断った 403 に、`Identify` が足した Cookie を消す `Set-Cookie` と6つのヘッダが付くこと)と、`mailtemplates.go`(`MailTemplates()` から4つのひな形のファイル名が読めること)の項目を足す |
| D5-1-2 | 低 | `.kiro/specs/backend-go-auth/spec.json` の `approval_history` の3つ目の要素(承認 2026-11-11T02:00:55Z、取り消し 2026-11-11T02:37:20Z)の `revoked_for` | 値が「T1-1-7 ã¨ T1-1-8 ã«ãã design ã¸ã®å·®ãæ»ã: …」のように文字化けしている。UTF-8 の日本語を、別の文字の符号として読んでもう一度 UTF-8 で書いた形である。ほかの2つの要素の `revoked_for` は正しい日本語である。design の本文ではなく、実装と検査には影響しないが、取り消しの理由を残す監査の記録が読めない。CLAUDE.md は、文字化けを見つけたら保存せずに止めて報告すると定め、`approval_history` は追記だけにし、書いてある要素を書き換えないと定めている。そのため、直すかどうかと直し方は所有者が決めることになる | メインセッションが所有者に報告する。所有者が直すと決めたときは、取り消しの理由(tasks の審査の T1-1-7 と T1-1-8 による design への差し戻し: ファイルの構成に tasks が変えるファイルが載っていない、応答の時間を測る環境の偽の AWS の数と JWT の見分け方の2つの文が事実と違う)を正しい日本語で書き直す。あわせて、spec.json を書いた手順のどこで文字化けが入ったかを調べる |

### 前の段階への指摘

なし

- 往復: 1回で収束 / 未解決: 0件
