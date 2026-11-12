# 調べたことの記録

## 試作の記録

この節は、要件7の受入基準1のとおり、設計を書く前に Claude が試しに作って確かめた方法と結果を残す。設計の段階でこの節を書き換えない。設計の段階で調べたことは、この節のあとの「設計の段階の記録」に書く。

### 確かめた環境

- Java 版: 作業のブランチ `feat/go-auth-operations`(main の 2b4e530d)の backend を、開発環境の PostgreSQL、Redis、LocalStack につないで動かした。データベースは試作のためだけに作った `keireki_proto` を使い、Redis は DB 5 を使った。所有者の開発のデータ(データベース `keireki_pro` と Redis の DB 0)には触れていない
- Go: go1.27.3(イメージ golang:1.27-bookworm)
- Go の部品: pgx v5.11.0、go-redis v9.23.0、AWS SDK for Go v2(SES と Secrets Manager)、golang.org/x/crypto v0.58.0(bcrypt)、google/uuid v1.6.0。Google と GitHub とのやり取りは、標準のライブラリの `net/http` だけで書いた
- Google と GitHub の代わり: 置き換えの spec で作った偽のログインのサービス(fakeoidc)を、同じ Docker のネットワークで動かした
- 試作のコードは作業用のフォルダに置き、リポジトリに入れていない

### 試作のやり方

Claude は、Go の試作の1つのプログラムに、確かめる動きごとの入口(URL の組み立て、戻ったあとの処理、再設定の申し込み、再設定、確認のメールの送り出し)を作った。Claude は、Java 版と Go の試作を同じデータベースと Redis と LocalStack につなぎ、動きごとに次の3つを確かめた。

1. 同じ入力で、Java 版と Go の試作が返す値(URL、移る先、メールの件名と本文)を、文字の単位で比べる
2. 一方の版が始めた手順を、もう一方の版で終える(Java 版で始めて Go で終える向きと、Go で始めて Java 版で終える向き)
3. 終えたあとのデータベースと Redis の中身を、Java 版だけで終えたときと比べる

送ったメールは、LocalStack の SES の送ったメールの一覧(`/_aws/ses`)から、送り主、宛先、件名、本文の順に書き出して、ファイルの単位で比べた。

### 確かめた動きと結果の一覧

| 記号 | 動き | 結果 |
|---|---|---|
| P1 | Google のログインの開始の URL(Java 版が返す本文) | 同じ |
| P2 | Google のログインの、初めての利用者と、登録済みの利用者 | 同じ(両方の向き) |
| P3 | ログインが断られたときと、記録が無いときの移る先 | 同じ |
| P4 | 確認の済んでいないメールアドレスのアカウントでのログイン | 同じ |
| P5 | Google が確認済みとしたメールアドレスでの、登録済みのアカウントへのつなぎ | 同じ |
| P6 | GitHub のログイン(確認済みのメールアドレスがある場合と無い場合) | 同じ |
| P7 | パスワードの再設定の申し込みと再設定 | 同じ(両方の向き) |
| P8 | 確認のメールを送り直せる間隔の制限 | 同じ(版をまたいで効く) |
| P9 | 4種類のメールの件名と本文 | 同じ(文字の単位で一致) |

### Google と GitHub のアカウントでのログイン(P1〜P6)

- P1: Java 版は、ログインの開始の URL の問い合わせの部分を、Spring の `UriComponentsBuilder` の `encode()` で書く。この書き方は、`scope` の空白を `%20` にし、`!$'()*+,;:@/?` を逃がさずに残す。Go の `url.Values.Encode()` は、空白を `+` にし、`/` と `:` を逃がすので、そのままでは同じ文字列にならない。Claude は、Spring と同じ文字を残す逃がし方を Go で書き、項目の順も Java 版と同じ順(`client_id` `response_type` `scope` `redirect_uri` `state` `code_challenge` `code_challenge_method`)に並べた。同じ `state` と `code_challenge` を使うと、Go の URL は Java 版の URL と1文字も違わなかった
- P2: Java 版が始めたログインを Go の試作の戻ったあとの処理で終える向きと、Go の試作が始めたログインを Java 版で終える向きの両方で、利用者の行、Google のアカウントのつなぎの行、役割の行、ログインの状態の版の行が、Java 版だけで終えたときと同じになった。2回目のログインでは、どちらの版も新しい行を足さなかった
- P3: Google が `error=access_denied` で戻したときと、Redis に `state` の記録が無いときに、どちらの版も、画面の `/login?error=` に「認証に失敗しました。しばらく時間を置いてから再度お試しください。」を付けた URL へ、302 で移した。Java 版の 302 の応答には本文と `Content-Type` が無い。Go の `http.Redirect` は HTML の本文と `Content-Type` を付けるので、Claude は `Location` だけを書いて 302 を返す形で同じにした
- P4: 確認の済んでいないメールアドレスを持つアカウントと同じメールアドレスで Google のログインをすると、どちらの版も `/login?error=unverified_email` へ移し、アカウントをつながなかった
- P5: Google が確認済みとしたメールアドレスと同じメールアドレスの、確認済みのアカウントがあると、どちらの版も、そのアカウントに Google のアカウントをつないだ。つないだときに、Java 版は利用者の行の `updated_at` を書き換える。Go の試作も同じに書き換えた
- P6: GitHub は、メールアドレスを `/user` ではなく `/user/emails` で返す。Java 版は `/user/emails` の URL を `https://api.github.com/user/emails` と書き込んでおり、設定で替えられない。Claude は、偽のログインのサービスの前に、名前 `api.github.com` で TLS を受けて偽のログインのサービスへ渡す試作の中継を置いた。中継の証明書は、試作の中で作った自己署名の証明書である。Java 版には、Java の実行環境の `keytool` で作った証明書の束を、環境変数 `JAVA_TOOL_OPTIONS` の `-Djavax.net.ssl.trustStore` で渡した。Go には、同じ証明書を環境変数 `SSL_CERT_FILE` で渡した。どちらの版も、主で確認済みのメールアドレスがあればそのメールアドレスでアカウントを作り、無ければメールアドレスの無いアカウントを作った。結果は両方の版で同じになった

### パスワードの再設定(P7)

- 申し込み: 確認済みの利用者には、どちらの版も、Redis の `password-reset:<トークン>` に利用者の ID を JSON の文字列として10分の期限で置き、再設定のメールを送った。確認の済んでいない利用者には、どちらの版も、再設定のメールの代わりに、目的が `PASSWORD_RESET` のメールアドレスの確認のメールを送った。アカウントの無いメールアドレスには、どちらの版もメールを送らなかった
- 再設定: Java 版が置いたトークンで Go の試作が再設定する向きと、その逆の向きの両方で、パスワードのハッシュの書き換え、トークンの削除、ログインの状態の版の1つの繰り上げ、その利用者のログインを続けるための値の全部の削除が、Java 版だけのときと同じになった。新しいパスワードで、もう一方の版にログインできた

### 確認のメールを送り直せる間隔の制限(P8)

- どちらの版も、Redis の `email-verification:rate:<メールアドレス>` に、値 `"1"`(JSON の文字列)を、60秒の期限で、無いときだけ置く(`SET NX`)。置けなかったときは、メールを送らない
- Java 版で送った直後に Go の試作で送ると、Go の試作は送らなかった。その逆の向きでも、Java 版は送らなかった。60秒がたったあとは、どちらの版も送った

### メールの件名と本文(P9)

- Claude は、Java 版のメールのひな形(`backend/src/main/resources/mail/*.ftl`)のファイルを Go の試作でそのまま読み、`${名前}` を Go の `text/template` の差し込みに置き換えて本文を作った。ひな形は `${名前}` のほかの FreeMarker の書き方を使っていない。`text/template` は HTML の逃がしをしないので、Java 版と同じ本文になる
- 比べたメール: メールアドレスの確認(有効な時間が24時間のものと10分のもの)、パスワードの再設定、2段階認証の確認のコード、新規の登録の完了。どれも、送り主、宛先、件名、本文が文字の単位で一致した。2段階認証の確認のコードは、同じコードを使って比べた
- 件名と、ひな形に渡す値は、メールによって違う。メールアドレスの確認とパスワードの再設定は、件名の【】の中と本文の `siteName` に Spring のアプリの名前 `keirekipro` を使い、`siteUrl` に画面の URL(開発環境では `http://localhost:5173`)を使う。2段階認証の確認のコードと新規の登録の完了は、件名の【】の中と本文の `siteName` に `KeirekiPro` を使い、`siteUrl` に `https://app.keirekipro.click` を使う
- 送り主は、開発環境では `no-reply@keirekipro.click` である。本文はテキストだけで、HTML の本文は無い

### 同じにできない動き

試作で、Java 版と同じにできない動きは見つからなかった。そのため、Claude は、要件7の受入基準2の報告をせずに、設計を書いた。

## 設計の段階の記録

この節から下は、設計の段階で Claude が調べたことと、設計で選んだことの理由を残す。上の「試作の記録」の節は書き換えていない。

### まとめ

- 対象: backend-go-auth(Issue #770)
- 調べ方: 既存の仕組みにつなぐ形。Go 版の土台、比べる検査、偽のログインのサービスは置き換えの spec の段階2で作ってあり、この spec はそこに機能を足す
- 設計を決めた主な発見:
  - Java 版は、Spring Security の働きで、すべての応答に `Cache-Control: no-cache, no-store, max-age=0, must-revalidate` などのヘッダを付ける。Go 版は今どの応答にも付けていない。比べる検査は `Cache-Control` を比べるので、Go 版がこのヘッダを付けないと、すべての操作の比べで違いが出る
  - 入力の誤りが1つの項目に2つ以上あると、Java 版は、その項目の文言の並びを、要求ごとに入れ替える。同じ要求を6回送ると、並びは2通りに分かれた。Go 版の並びを1つに決めても、Java 版の並びと合わない要求が出る
  - depguard は、機能のパッケージから、`internal/platform` のほかの `internal` の下のパッケージを読むことを禁じる。認証のコードを `internal/auth` の下の小さなパッケージに分けると、分けたパッケージどうしを読めなくなる。ほかのまとまりのパッケージも、`internal/auth` を読めない
  - oapi-codegen が生成する応答の型は、`Set-Cookie` を1つしか書けない。ログインの応答は Cookie を2つ付けるので、生成した型では Java 版と同じ応答を返せない

### Java 版の認証の作り

- 調べたきっかけ: Go 版を、Java 版の今の動きと同じにするため(要件1の受入基準1)
- 調べたもの: `backend/src/main/java/com/example/keirekipro/` の下の、認証の受け口(`presentation/auth/`)、認証の処理(`usecase/auth/`)、Redis とメールと外部のログインの部品(`infrastructure/auth/` `infrastructure/shared/`)、`presentation/security/`(`SecurityConfig` `JwtProvider` `JwtAuthenticationFilter`)、`AppExceptionHandler`、要求の入力の検査の注釈、`application.yaml` と `application-dev.yaml`
- 分かったこと:
  - ログインの状態の値は、HMAC-SHA256 で署名した JWT で、項目 `sub`(利用者の ID)、`roles`(役割の名前の並び)、`tokenVersion`(ログインの状態の版)、`iat`、`exp` を持つ。Java 版は、要求のたびに、データベースの `user_token_versions` の版と `tokenVersion` を比べ、違えば断る
  - Java 版のログインの状態の検査は、`OPTIONS` の要求と、経路が `/api/auth` で始まる要求を検査しない。値が無効な Cookie `accessToken` を持つ要求には、その Cookie を消す `Set-Cookie` を付け、ログインしていない要求として次に渡す
  - Java 版は、ログインの要る操作にログインしていない要求が届くと、本文の無い 401 を返す。経路が `/api/admin` の下の操作には、役割 `ADMIN` を求め、持たない要求には 403 と `{"message":"アクセス権限がありません。"}` を返す。今の API の仕様書には、`/api/admin` の下の操作が無い
  - Redis のキーの頭は、`email-verification:current:` `email-verification:rate:` `oidc:state:` `oidc:provider:` `oidc:code_verifier:` `password-reset:` `pending-registration:` `pending-registration:email:` `refresh-token:` `user-refresh-tokens:` `2fa:challenge:` `2fa:` である。値は、どれも Jackson で JSON の値として書かれる。文字列は `"..."` で囲まれ、登録の途中の記録は、JSON の文字列の中に JSON を入れた形である
  - 2段階認証の誤ったコードの上限は5回で、確認のコードと途中の記録の有効な時間は10分である。メールアドレスの確認の照合は、確認と消し込みを最大2回くり返す
- 設計への影響: Go 版の Redis の読み書きは、Java 版と同じキーと同じ JSON の値の形にする。Go の `encoding/json` は既定で `<` `>` `&` を `<` などに逃がすので、Go 版は HTML の逃がしを止めて書く

### Java 版の応答のヘッダ

- 調べたきっかけ: 比べる検査は `Content-Type` `Content-Disposition` `Cache-Control` `Location` を比べる。Go 版の今の応答にどれが足りないかを確かめるため
- 調べたもの: 開発環境で動いている Java 版(ポート 8080)と Go 版(ポート 8081)の応答のヘッダ
- 分かったこと:
  - Java 版は、ログインの要求の 400、ログインの要る操作の 401、ログインの開始の 200、プリフライトの応答、`/actuator/health` の応答のどれにも、`Cache-Control: no-cache, no-store, max-age=0, must-revalidate`、`Pragma: no-cache`、`Expires: 0`、`X-Content-Type-Options: nosniff`、`X-Frame-Options: DENY`、`X-XSS-Protection: 0` を付けた。Java 版のコードには、`Cache-Control` を自分で書く箇所が無い
  - Go 版は、これらのヘッダをどの応答にも付けていない
  - ログインの開始の応答の `Content-Type` は、Java 版では `text/plain;charset=UTF-8` である。oapi-codegen が生成する応答の型は `text/plain` と書く
- 設計への影響: Go 版の HTTP の受け口に、6つのヘッダをすべての応答に付ける中間処理を足す。ヘッダを付けないと、比べる検査がすべての操作で違いを出す。また、ブラウザが API の答えを手元に残さないようにする対策と、ブラウザが答えの種類を推測しないようにする対策と、ほかのサイトの枠の中に表示させない対策が、Go 版で弱まる(要件3)

### 入力の誤りの文言の並び

- 調べたきっかけ: 1つの項目に2つ以上の誤りがあるときに、Java 版がどの順に文言を並べるかを確かめるため
- 調べたもの: 開発環境の Java 版に、メールアドレスの形が誤り、ユーザー名が空、パスワードが1文字、確認のパスワードが違う、新規の登録の要求を6回送った
- 分かったこと: 項目 `password` の2つの文言(「パスワードは8文字以上で…」と「パスワードには英小文字…」)の並びが、6回のうち4回と2回で入れ替わった。Java 版の入力の検査(Hibernate Validator)は、誤りを順の決まらない集まりに入れるためである
- 設計への影響: Go 版は、文言を決まった順に並べる。比べる検査では、変えた動きの一覧の、並びの順だけの違いを許す項目(`order_only`)で、項目ごとの文言の並びの順だけを許す。順の違いは、画面の表示の順だけで、文言の中身は同じである

### Go 版の土台と比べる検査

- 調べたきっかけ: 認証の操作を、置き換えの spec の段階2で作った土台と比べる検査に、どうつなぐかを決めるため
- 調べたもの: `backend/internal/httpapi/server.go` `middleware/` `unimplemented.go`、`backend/internal/platform/` の下のすべて、`backend/cmd/keirekipro/main.go`、`backend/.golangci.yml`、`backend/sqlc.yaml`、`backend/compat/harness/` `fakeoidc/` `fixtures/` `changed-behaviors.yaml`
- 分かったこと:
  - `httpapi.Options` には、ログインの状態の検査を差し込む欄 `Auth` が用意されている。中間処理の順は、パニックの受け止め、要求のログ、CORS、偽の送信の検査、ログインの状態の検査、経路の記録である
  - 生成した `gen.StrictServerInterface` を満たす型は、まとまりの処理と、未実装の答えを返す型を埋め込んで作る。まとまりの処理のメソッドが、未実装の答えより優先される
  - 設定には、Spring のアプリの名前(`keirekipro`)にあたる値が無い。メールアドレスの確認とパスワードの再設定のメールが、この値を使う
  - 比べる検査の筋書きは、取り出しの値を JSON の本文からしか取れない。確認のコードとリンクの値はメールの本文に、ログインの開始の URL はテキストの本文に、移る先は `Location` のヘッダにある
  - 比べる検査の正規化は、UUID、日時、JWT、bcrypt のハッシュ、URL の中の43文字のトークンを置き換える。2段階認証の6桁の確認のコードは置き換えない
  - 偽のログインのサービスは、ログインを断る動き(`error=access_denied` で戻す動き)と、名前 `api.github.com` で TLS を受ける口を持たない
  - Docker 29.9.3 のコンテナでは、`ip_unprivileged_port_start` が 0 なので、権限の無い利用者(`nonroot`)のプログラムもポート 443 で待てる
  - depguard の規則では、機能のパッケージは `internal/platform` のほかの `internal` の下を読めない。生成した型 `internal/httpapi/gen` も読めない
  - 比べる検査は、Cookie を筋書きの Cookie の束で引き継ぎ、Cookie の名前と性質だけを比べる。Redis の残りの有効な時間は5秒のずれを許して比べる
- 設計への影響: 比べる検査の取り出しと正規化と偽のログインのサービスを、この spec で広げる。広げる中身は design.md の「比べる検査の広げ方」に書く。認証の操作の受け口と応答の型は、生成した型を読める `internal/httpapi` に置き、`internal/auth` は Go の普通の型で受けて返す

### Java 版のログインの状態の検査の位置

- 調べたきっかけ: Go 版のログインの状態の検査を、中間処理の並びのどこに置くかを決めるため
- 調べたもの: Java 版の `SecurityConfig` と `JwtAuthenticationFilter`、`AppExceptionHandler`、`MyBatisUserTokenVersionStore` と `UserTokenVersionMapper.xml`
- 分かったこと:
  - Java 版は、ログインの状態の値を読むフィルタを、偽の送信の検査のフィルタの前に置く(`addFilterBefore`)。ログインしていない要求を 401 で断る処理は、偽の送信の検査のあとにある
  - そのため、無効な Cookie `accessToken` を持つ書き込みの要求が偽の送信の検査で断られるときも、応答に Cookie を消す `Set-Cookie` が付く
  - 値を読むフィルタは `JWTVerificationException` だけを受け止める。データベースの誤りでは要求が止まる
  - ログインの状態の版の行が無いときの版は 0 である。版の繰り上げは `UPDATE` だけで、行が無ければ何もしない
  - 入力の誤りの文言は「入力エラーがあります。」、確認の済んでいないメールアドレスの文言は「メールアドレスの確認が済んでいません。」である
- 設計への影響: Go 版のログインの状態の検査を、偽の送信の検査の前で値を読む段と、偽の送信の検査のあとでログインを求める段の2つに分ける

## 設計で比べた案

| 案 | 中身 | 良い点 | 危うい点 | 結論 |
|---|---|---|---|---|
| 認証のコードを `internal/auth` の1つのパッケージにする | ログインの状態、メール、Google と GitHub、Redis の読み書きを1つのパッケージのファイルに分ける | depguard の規則を変えずに作れる | パッケージのファイルが多くなる | 採る |
| 認証のコードを `internal/auth` の下の小さなパッケージに分ける | `auth/token` `auth/oidc` などに分ける | パッケージの責任が小さくなる | 分けたパッケージどうしを読むために、ゲートの設定 `.golangci.yml` の変更が要る | 採らない |
| ログインした利用者の ID の受け渡しを `internal/platform` に置く | ほかのまとまりが `internal/auth` を読まずに利用者の ID を得る | depguard の規則を変えずに、ほかのまとまりが使える | なし | 採る |
| ログインした利用者の ID の受け渡しを `internal/auth` に置く | ほかのまとまりが `internal/auth` を読む | 認証のコードが1か所に集まる | まとまりごとに depguard の規則の変更が要る | 採らない |
| Google と GitHub とのやり取りを x/oauth2 と go-oidc で書く | 置き換えの spec が挙げた部品を使う | 部品の作法に沿う | ログインの開始の URL が Java 版と同じにならない。Java 版は ID トークンを確かめないので go-oidc の主な働きを使わない | 採らない |
| Google と GitHub とのやり取りを `net/http` で書く | 試作と同じ書き方 | 試作で Java 版と同じになることを確かめた。部品を増やさない | 自分で書く量が増える | 採る |

## 設計で決めたこと

### 決めたこと: 認証の操作の応答の型を、生成した型の代わりに自分で書く

- きっかけ: 要件1の受入基準1のとおり、Cookie の名前と性質と `Content-Type` を Java 版と同じにする
- 比べた案:
  1. 生成した応答の型を使い、足りないヘッダを中間処理で足す
  2. 生成した型の代わりに、`Visit<操作の名前>Response` のメソッドを持つ型を `internal/httpapi` で書く。depguard の規則で、`internal/auth` は生成した型を読めないためである
- 選んだ案: 2
- 理由: oapi-codegen の strict-server は、操作が返す値の `Visit<操作の名前>Response` を呼んで応答を書く。この形を満たす型なら、生成した型でなくても返せる。案2なら、ログインの応答に `Set-Cookie` を2つ書き、ログインの開始の応答に `text/plain;charset=UTF-8` を書ける。案1は、中間処理が操作ごとの応答の中身を知ることになる
- 引き換えにしたもの: 生成した型が仕様書から自動で変わる利点を、認証の操作の応答では使わない。比べる検査が、仕様書と Java 版の応答の食い違いを見つける
- 実装で確かめること: 自分で書いた型が、生成したインタフェースの応答の型を満たすことを、型の検査で確かめる

### 決めたこと: Google と GitHub とのやり取りに x/oauth2 と go-oidc を使わない

- きっかけ: 置き換えの spec は、認証の部品として x/oauth2 v0.37.0 と go-oidc v3.21.0 を挙げ、使う処理をこの spec で作ると決めた
- 比べた案:
  1. x/oauth2 でログインの開始の URL を作り、コードを交換する。go-oidc で ID トークンを確かめる
  2. 試作と同じく、標準のライブラリの `net/http` で書く
- 選んだ案: 2
- 理由: x/oauth2 は URL の問い合わせの部分を `url.Values.Encode()` で書くので、Java 版の URL と同じにならない(試作の P1)。Java 版は ID トークンを確かめず、アクセストークンで利用者の情報の口を読むので、go-oidc の主な働きを使わない。案2は、試作で Java 版と同じになることを確かめた書き方で、部品も増えない
- 引き換えにしたもの: Google と GitHub の口を呼ぶコードを自分で持つ。比べる検査が、偽のログインのサービスで Java 版と同じかを確かめる

### 決めたこと: メールの本文は Java 版のひな形のファイルをそのまま使う

- きっかけ: 要件1の受入基準5のとおり、メールの件名と本文を Java 版と同じにする
- 比べた案:
  1. 本文を Go のコードの中に書き写す
  2. Java 版のひな形のファイルを Go 版に埋め込み、`${名前}` を差し込む
- 選んだ案: 2
- 理由: 試作で、ひな形をそのまま読んで差し込むと、本文が文字の単位で一致した。1つのファイルを両方の版が読むので、片方だけを直す食い違いが起きない(置き換えの spec の要件1の受入基準6)
- 引き換えにしたもの: ひな形は Java 版のフォルダ `src/main/resources/mail/` にある。Java 版を削除する段階6で、ひな形のファイルを移し、埋め込みの指定も直す。マイグレーションのファイルと同じ扱いである
- 実装で確かめること: ひな形に `${名前}` のほかの FreeMarker の書き方が足されたら、Go 版の差し込みが失敗することを、Go 版の単体テストで確かめる

### 共通化と簡素化で決めたこと

- 共通化: 認証の操作の Redis の読み書きは、JSON の値として書いて読む1つの部品にまとめる。12のキーの頭のどれも、この部品を通す
- 作るか使うか: JWT は golang-jwt v5.3.1 を使う。bcrypt は golang.org/x/crypto を使う。Google と GitHub とのやり取りと、Spring と同じ URL の逃がし方は、合う部品が無いので書く。メールの差し込みは標準の `text/template` を使う
- 簡素化の見直し: はじめは、管理者の役割の検査(`/api/admin` の下の操作に `ADMIN` を求める検査)を作らないと決めた。今の API の仕様書に `/api/admin` の下の操作が無いためである。設計を書く中で、この決めを改め、検査を作ることにした。ログインを求める段は、仕様書に無い経路への要求にも Java 版と同じ答えを返すので、`/api/admin` の下への要求にも Java 版と同じく 403 を返すためである。検査は数行で、ログインを求める段の中に収まる

## 実装で確かめた Java 版の値の形

この節は、実装の中で Claude が開発環境の Java 版か Java 版のコードで確かめた、Java 版の値の形と読み方を残す。Go 版は、どれも同じ形で書き、同じ規則で読む。Java 版と違えた動きは、変えた動きの一覧(`backend/compat/changed-behaviors.yaml`)に載せた。

### Redis の値

- Java 版は、Redis の値を、application.yaml の `use-jackson2-defaults` と `JsonMapperConfig` の設定を当てた Jackson で書く。そのため、絵文字のような U+10000 以上の文字は、大文字の16進で書いた2つ組の逃がしになる。Go 版の `redisjson.go` は、Go の JSON の書き方と Jackson の3つの違いを直す
- Java 版が `writeValueAsString` で作った JSON を、もう一度 JSON の文字列にして置く記録がある。中の JSON は U+10000 以上の文字をそのまま書き、外の JSON の文字列にするときだけ2つ組の逃がしにする
- Java 版の Jackson は、日時の項目を、数、秒の数の文字列、時差の付いた ISO 8601、空の文字列のどれでも読む。UUID と数の項目の読み方も、開発環境の Java 版の Redis に値を置いて API を呼んで確かめた。Go 版の `parseJacksonInstant` `parseJacksonUUID` `parseJacksonInt` が、確かめた規則を写す

### Cookie

- Spring の `ResponseCookie` は、Max-Age が0以上のとき、必ず `Expires=` も書く。そのため、Go 版も、2段階認証の途中の Cookie に要求を受けた時刻の600秒後を書き、消す Cookie に `Expires=Thu, 01 Jan 1970 00:00:00 GMT` を書く

### 入力の検査

- Java 版の `@Email` は、JDK の `java.net.IDN.toASCII`(nameprep は Unicode 3.2)でドメインを変えてから判定する。Go 版の `idna.go` は、JDK から読み出した表で同じ変え方をする。基本多言語面のすべての文字を4つの位置に置いた25万件で、2つの版の判定の食い違いが0件であることを確かめた
- Java 版の `Email.create` は、Apache Commons Validator 1.11.0 の `EmailValidator.getInstance(false, false)` で判定する。Go 版の `commonsemail.go` は、Java 版の依存の版で作った表と期待で、同じ判定をする
- Java 版は、要求の JSON に項目が無いと値を null にし、`@NotBlank` の文言だけを返す。`@Size` `@Pattern` `@MaxUtf8Bytes` は null を誤りにせず、`@PasswordMatches` は null どうしを一致とみなす。Go 版は項目が無い要求を空の文字列の要求と同じに検査するので、文言が増える(CB-020)
- 要求の JSON に対になっていないサロゲートの書き方があると、Java 版の `MaxUtf8BytesValidator` はその文字を `?`(1バイト)と数える。Go 版の JSON の読み方は U+FFFD(3バイト)に置き換えるので、72バイトの境目の近くで判定が変わる(CB-021)

### メールとリンク

- Java 版の FreeMarker は、拡張子が `.ftl` のひな形では HTML の特別な文字を逃がさず、利用者の名前の `<&>` や `${x}` もそのまま差し込む
- Java 版は、Google と GitHub の認可の URL の問い合わせの部分を、Spring 7.0.10 の `UriComponentsBuilder` で逃がす。Go 版の `spring_query.go` の期待は、同じ版の Spring の jar を動かして作った
- Java 版のメールアドレスの確認の値は、java-jwt 4.6.2 で読む。java-jwt は、署名の末尾の `=` を受け付け、exp と nbf と iat があれば確かめる。Go 版は、値の本体を `<` `>` `&` を逃がさずに書き、同じ規則で読む
- Java 版のメールアドレスの確認の操作は、結果が VERIFIED、EXPIRED、ALREADY_VERIFIED のどれでも 200 を返す

### ログインと利用者

- Java 版の `BCryptPasswordEncoder.matches` は、`$2a$` `$2b$` `$2y$` の形のハッシュを照らし、強さが4から31の外のハッシュでは 500 で答える。パスワードは先頭の72バイトだけを使う。Go 版の `passwordMatches` は、開発環境の Java 版で確かめたこの規則を写し、塩の使われないビットが立つハッシュは、合わないとする
- Java 版の `BCryptPasswordEncoder.matches` は、`$2$` の形のハッシュも照らす。Go の bcrypt は、`$2$` の形でも鍵の末尾に0のバイトを足して計算し、Java 版と違う値になる。そのため、Go 版の `passwordMatches` は、`$2$` の形のハッシュを照らさずに合わないとする。Java 版は、パスワードのハッシュを `new BCryptPasswordEncoder()` の既定の `$2a$` の形で作るので、API の要求で `$2$` の形のハッシュを持つ利用者はできない(CB-027)
- Java 版は、利用者の役割を順の決まらない集合で持つので、`roles` の並びが JVM ごとに変わる。Go 版は USER、ADMIN の順に並べる(CB-022)
- Java 版の `User.reconstruct` は、利用者を読むたびに、2段階認証が有効でメールアドレスかパスワードが無い利用者と、2段階認証が無効な管理者を、400 で断る。Go 版も、利用者を読むすべての操作で同じ順に確かめる

### Google と GitHub

- Java 版の RestClient は、どの状態の番号の応答でも本文を読む。Java 版の Jackson は、先頭の JSON の値のあとを読まない。Go 版も同じに読む
- 対象の外の `provider` を受けた Java 版は、Redis に3つの記録を置いたあとに 500 で答え、記録を残す(コードを読んで確かめた)。Go 版は記録を置く前に 400 で断る
- Java 版は、`startOidcAuthorization` の要求の Accept と Host の一部の形で、Go 版と違う状態の番号を返す。手元の Java 版で答えを確かめ、変えた動きの一覧に載せた

### プリフライトでない OPTIONS の要求

- プリフライトでない OPTIONS の要求に、Java 版は、経路のある URL では 200、経路の無い URL では 500 で答える。Go 版は 405 と 404 で答える(CB-026)

## 危うい点と備え

- Java 版の細かい動きの見落とし。備えとして、認証の操作のすべてについて、筋書きに入力の誤りと期限切れと上限の要求を含め、データベースと Redis とメールも比べる(要件5の受入基準1と2)
- 入力の誤りの文言の並びが Java 版で決まらないこと。備えとして、変えた動きの一覧に、並びの順だけを許す項目を、項目の場所ごとに書く。文言の中身の違いは許さない
- 比べる検査で、名前 `api.github.com` の TLS の口を作ること。証明書は検査のたびに作り直し、検査の外には出さない。Java 版の証明書の束は Java 版のイメージの `keytool` で作るので、Java 版のイメージの土台を替えると作り方の見直しが要る
- 2段階認証の確認のコードは、要求のたびに違う6桁の数字である。正規化しないと、メールと Redis の比べで違いが出る。備えとして、メールの本文の決まった行と、Redis のキー `2fa:<利用者の ID>` の値だけを正規化し、ほかの場所の6桁の数字は置き換えない

## 参考にしたもの

- [oapi-codegen の strict-server](https://github.com/oapi-codegen/oapi-codegen#strict-server) — 応答の型の `Visit<操作の名前>Response` の形
- [golang-jwt v5](https://pkg.go.dev/github.com/golang-jwt/jwt/v5) — HMAC-SHA256 の署名と項目の読み方
- [Spring Security の既定のヘッダ](https://docs.spring.io/spring-security/reference/servlet/exploits/headers.html) — `Cache-Control` などの6つのヘッダ
- [Spring の UriComponentsBuilder](https://docs.spring.io/spring-framework/docs/current/javadoc-api/org/springframework/web/util/UriComponentsBuilder.html) — 問い合わせの部分の逃がし方
- [GitHub の REST API の利用者のメールアドレス](https://docs.github.com/en/rest/users/emails) — `/user/emails` の主で確認済みのメールアドレス
- [Go の crypto/x509 の SSL_CERT_FILE](https://pkg.go.dev/crypto/x509) — 信頼する証明書の束の替え方
- [Docker の ip_unprivileged_port_start の既定](https://docs.docker.com/engine/release-notes/20.10/) — コンテナの中で権限の無いプログラムが低いポートで待てること
