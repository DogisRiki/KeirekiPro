# 調べた記録

## 試作の記録

この節は、要件7の受入基準1のとおり、設計を書く前に Claude が試しに作って確かめた方法と結果を残す。設計の段階でこの節を書き換えない。設計の段階で調べたことは、この節のあとの「設計の段階の記録」に書く。

試した結果、Java 版と同じにできない動きは見つからなかった。そのため、Claude は、要件7の受入基準2のとおりに止まらず、設計を書いた。

### 確かめた環境

- Java 版: 作業のブランチ `feat/go-user-operations`(main の 9f3c420f)の backend を、開発環境の `spring` のコンテナの中で、所有者が動かしている Java 版と同じ起動の設定で、別にもう1つ動かした。足した設定は、ポート 8090、データベース `keireki_proto`、Redis の DB 5 の3つである。Java 21.0.11、Spring Framework 7.0.10、Tomcat 11.0.27 で、JVM の言語の設定は `en_US` である。所有者の開発のデータ(データベース `keireki_pro` と Redis の DB 0)には触れていない
- 画像の置き場所: 開発環境の LocalStack の S3 の `keirekipro-storage` を使った。この置き場所は所有者の開発環境と同じものだが、試作の前は空だった。試作で置いた画像は、試作のあとですべて消し、空に戻した
- Go: go1.27.3(イメージ golang:1.27-bookworm)
- Go の部品: AWS SDK for Go v2(aws-sdk-go-v2 v1.47.7、service/s3 v1.114.8、service/ses v1.42.8、config v1.33.15、credentials v1.20.15)、golang.org/x/crypto v0.58.0(試作の利用者のパスワードのハッシュを作るためだけに使った)
- 試作のコードは作業用のフォルダに置き、リポジトリに入れていない。試作のあとで、別に動かした Java 版を止め、データベース `keireki_proto` を消し、Redis の DB 5 を空にした

### 試作のやり方

Claude は、データベース `keireki_proto` に試作の利用者を4人入れた。4人とも、パスワードと確認の済んだメールアドレスを持つ。そのうち1人は、ユーザー名を持たない。Claude は、Java 版にログインし、利用者の操作の要求を `curl` で送った。

Go の試作は1つのプログラムで、確かめる動きごとの入口を持つ。入口は、名前の前後の空白の取り除きと文字数の判定、multipart の本文の読み方、画像を置くこと、画像を消すこと、画像を見せるための署名付きの URL を作ること、退会の完了のメールを送ることである。Claude は、Java 版と Go の試作に同じ入力を与え、結果を文字かバイトの単位で比べた。画像は LocalStack の S3 から、メールは LocalStack の SES の送ったメールの一覧(`/_aws/ses`)から読んで比べた。

### 確かめた動きと結果の一覧

| 記号 | 動き | 結果 |
|---|---|---|
| P1 | 画像を置き場所に置くときの名前と、置くときに付ける値 | 同じ |
| P2 | 画像を見せるための署名付きの URL | 同じにできる(AWS SDK の署名付きの URL の部品のままでは違う) |
| P3 | 一方の版で置いた画像を、もう一方の版の URL で見せること | 同じ(両方の向き) |
| P4 | アップロードしたファイルの名前の読み方と、拡張子の判定 | 同じにできる(Go の標準の部品のままでは違う) |
| P5 | 名前の誤りで断る要求で、画像を置くかどうか | 同じにできる(Java 版は名前を確かめる前に画像を置く) |
| P6 | 名前の前後の空白の取り除き方 | 同じ(すべての字で一致) |
| P7 | 名前の文字数の数え方 | 同じ(UTF-16 の単位で数える) |
| P8 | UTF-8 として誤ったバイトを含む名前の読み方 | 同じにできる(Go の標準の置き換えのままでは違う) |
| P9 | 退会の完了のメールの件名と本文 | 同じ(文字の単位で一致) |
| P10 | ユーザー名を持たない利用者の退会 | 同じにできる(Java 版は 500 で答え、一部だけを消す) |

### 画像の名前と URL(P1〜P3)

- P1: Java 版は、画像を `/profile/image/<利用者の ID>.<拡張子>` の名前で置く。名前は `/` で始まる。拡張子が無いときは `.` も付けない。置くときに、Java 版は、`Content-Type` と、利用者の付けた値(メタデータ)の `Content-Type` の両方に、要求の部分の `Content-Type` をそのまま入れる。Go の試作が同じ名前と同じ2つの値で置くと、LocalStack が答える画像の中身、`Content-Type`、メタデータが、Java 版が置いた画像と同じになった
- P2: Java 版の URL は、`http://localhost:4566/keirekipro-storage//profile/image/<利用者の ID>.png?X-Amz-Algorithm=…&X-Amz-Date=…&X-Amz-SignedHeaders=host&X-Amz-Credential=…&X-Amz-Expires=600&X-Amz-Signature=…` の形である。置き場所の名前のあとの `/` は2つ続く。画像の名前が `/` で始まるためである。問い合わせの項目は、この順に並ぶ。開発環境では、Java 版は、LocalStack の名前 `localstack` を `localhost` に置き換える
  - AWS SDK for Go v2 の署名付きの URL の部品(`s3.PresignClient`)は、問い合わせに `X-Amz-Checksum-Mode=ENABLED` と `x-id=GetObject` を足し、項目を名前の順に並べる。`x-id=GetObject` は署名する値に含まれるので、署名のあとで取り除けない
  - Claude は、2つの作り方を試した。1つ目は、AWS SDK の署名の部品(`aws/signer/v4` の `Signer`。道の `/` を逃がさない設定 `DisableURIPathEscaping` を付ける)で GET の要求に署名し、問い合わせの項目を Java 版の順に並べ直す作り方である。2つ目は、署名の手順(SigV4)を手で書く作り方である。どちらも、同じ時刻で署名すると、Java 版の URL と1文字も違わなかった
  - S3 は、署名を確かめるときに問い合わせの項目を名前の順に並べ直すので、並べる順は URL を使えるかどうかに関わらない。並べる順を Java 版にそろえるのは、要件5の受入基準3のとおり、比べる検査で URL の形を比べるためである
- P3: 次の4つの手順のどれでも、URL から読んだ画像のバイト列と `Content-Type` は、置いた画像と同じだった
  - Java 版で置いた画像を、Go の試作の URL で読む
  - Go の試作で置いた画像を、Java 版が返す利用者の情報の URL で読む
  - 同じ拡張子の別の画像に替えたあとで、もう一方の版の URL で読む
  - 違う拡張子の画像に替えたあとで、もう一方の版の URL で読む。このとき、前の拡張子の画像は置き場所に残る。Java 版も同じに残す

### ファイルの名前と拡張子(P4、P5)

- Java 版は、multipart の部分の名前を、Spring の `ContentDisposition.parse` で読む。拡張子は、ファイルの名前の最後の `.` のあとの文字列を `toLowerCase()` で小文字にしたものである。Claude は、名前の違う12通りの要求を Java 版に送り、答えと置いた画像の名前を記録した
- Go の標準の部品(`mime/multipart` の `Part.FileName()` と `mime.ParseMediaType`)で読むと、12通りのうち次の3通りで Java 版と違う結果になった
  - `x.GİF`: Java 版は `İ` を2文字(`i` と結合の点)に小文字にするので、拡張子を許可しない。Go の `strings.ToLower` は `İ` を `i` にするので、`gif` として許可する
  - `a.png/`: Java 版は拡張子を `png/` と読んで許可しない。Go の `Part.FileName()` は最後の `/` のあとだけを名前にするので、`a.png` と読んで許可する
  - `=?UTF-8?B?55S75YOPLnBuZw==?=`: Java 版は RFC 2047 の書き方を解いて `画像.png` と読み、許可する。Go の標準の部品は解かないので、拡張子が無いと読む
- Go の標準の部品は、部分の見出しに制御文字(たとえば BEL)があると、本文の全体を読めない誤りにする。Java 版(Tomcat)は、制御文字があっても読む
- Claude は、Spring 7.0.10 の `ContentDisposition.parse` のソースを写した読み方と、部分の見出しを制御文字があっても読む読み方を Go の試作で書いた。拡張子は、ASCII の字だけを小文字にし、ASCII でない字を含む拡張子を許可しない。Java で、ASCII でない字のうち `toLowerCase` で ASCII の字だけになるものを数えると、ケルビンの記号(U+212A、`k` になる)の1字だけだった。許可する拡張子 `jpg` `jpeg` `png` `gif` には `k` が無いので、この判定は Java 版と同じになる。この読み方で、12通りのすべてが Java 版と同じ結果になった
- `C:\dir\a.JPG` は、Java 版でも Go の標準の部品でも `.jpg` になった。ただし、理由は違う。Java 版は `\` のあとが `"` か `\` のときだけ `\` を取り除く。Go の標準の部品は、`\` のあとの字の種類によらず `\` を取り除く
- 小タスク2.2 の実装(2026-11-13): Claude は、Spring 7.0.10 の `ContentDisposition.parse` を写した `contentdisposition.go` と、Java 版の依存の jar の本物の `ContentDisposition.parse` に、乱数で作った見出しを30万通りずつ2回渡して、種類と部分の名前とファイルの名前と誤りになるかを比べた。食い違いは、次の1つだけだった
  - RFC 2047 の書き方(`=?文字コード?B?…?=` と `=?文字コード?Q?…?=`)の文字コードが、UTF-8 と ISO-8859-1 と US-ASCII(と JDK が認める別名)のどれでもないとき。Java 版は、JDK が読める文字コード(`Shift_JIS` など)なら解いてファイルの名前にする。Go 版は、誤りにする。JDK が読める文字コードは百を超え、文字コードごとの誤ったバイトの扱いまで JDK と同じにするのは難しいためである。ブラウザは、multipart のファイルの名前を RFC 2047 の書き方で送らない。この違いを変えた動きの一覧に載せるかは、変えた動きの一覧に項目を足す小タスクで所有者に示して決める
  - `filename*` の書き方の文字コードは、Spring が UTF-8 と ISO-8859-1 に限るので、Java 版と Go 版で違いが無い
- 小タスク2.3 の実装(2026-11-13): Claude は、Tomcat 11.0.27 の fileupload を写した `multipart.go` と、本物の `tomcat-embed-core` 11.0.27 の `FileUpload`(Spring Boot と同じ上限を付けたもの)に、乱数で作った multipart の本文を合わせて50万通りと、決めた本文68通りを渡して、部分の名前とファイルの名前と見出しと中身と、誤りになるかを比べた。Java 側は、本文を毎回ちがう長さに区切って読ませた。食い違いは、次の1つの種類だけだった
  - Tomcat は、部分の見出しの項目の値(`name` `filename` と、入れ子の `multipart/mixed` の `boundary`)も RFC 2047 と RFC 2231 の書き方で解く。文字コードが UTF-8 と ISO-8859-1 と US-ASCII のどれでもないとき、Java 版は、JDK が読める文字コード(`Shift_JIS` `EUC-KR` など)なら解く。名前の形は正しいが JDK が知らない文字コードなら、解かずにそのままの値を使う。Go 版は、どちらも誤りにする。小タスク2.2 の違いと同じ理由である。文字コードの名前は、Java の `toLowerCase(Locale.ROOT)` で小文字にしてから別名の表を引くので、ケルビンの記号(U+212A)を含む `euc-` と `r` のあいだにケルビンの記号を挟んだ名前も `EUC-KR` として解かれることを確かめた
- Tomcat は multipart の本文を読めないとき例外を投げ、Spring はそれを `MultipartException` にするので、Java 版は 500 で答えるはずである(状態の番号は小タスク2.4 で確かめる)
- 小タスク2.4 の実装(2026-11-13): Claude は、本文を読む中間処理の規則を、本物の Java 版と比べて、次のとおり確かめた
  - Claude は、Java 版の依存の jar の本物の Spring 7.0.10 の変換の部品(`WebDataBinder` と `DefaultFormattingConversionService`)に、`twoFactorAuthEnabled` の値を渡して、真偽の読み方を比べた。渡した値は、8つの語(`true` `on` `yes` `1` `false` `off` `no` `0`)の1字を置き換えた値と、語の前か後ろに1字を足した値と、1字だけの値と、決めた値23通りである。字は、サロゲートの範囲を除く U+0000 から U+FFFF のすべてである。Spring が受け付けた702通りの値と、それ以外の値のすべてで、Go 版は Spring と同じ答えになった
  - Claude は、design.md の「本文を読む中間処理と multipart の読み方」の節の手順4と違う、次の3つの点を、Java 版に合わせた
    - `username` の値が URL の問い合わせと本文の両方にあるとき、Go 版は、本文の値を先に、問い合わせの値を後に並べる。小タスク1.2 で控えた Java 版の答えのとおりである
    - `twoFactorAuthEnabled` の値が1つのとき、Spring は、変換の部品が例外を投げたあと、`CustomBooleanEditor` で読み直す。`CustomBooleanEditor` は語を Java の `equalsIgnoreCase` で比べるので、長い s(U+017F)を使った `yeſ` を真に、`falſe` を偽にする。Go 版も同じにした。前後の U+0020 以下の字は、制御文字も含めて除く。前後の NBSP と全角の空白は除かず、400 で断る
    - `twoFactorAuthEnabled` の値が2つ以上あるとき、Spring は、最初の値だけを読み、あとの値を見ない。最初の値は、`equalsIgnoreCase` でなく、小文字にして語と比べる。そのため、`true` と `maybe` の2つの値は真になり、`maybe` と `true` の2つの値と、`yeſ` と `true` の2つの値は 400 になる。Go 版も同じにした
  - Claude は、開発環境の `spring` のコンテナで、所有者の Java 版とは別に、ポート 8090 と別のデータベースと Redis の DB 6 で Java 版を動かし、次の要求を送った。どの要求にも、Java 版は 500 と「予期せぬエラーが発生しました。」で答えた。Go 版は、どの要求にも 400 と「入力エラーがあります。」で答える。design.md が名指しした4つの要求のほかに見つけた要求なので、変えた動きの一覧に項目を足す小タスクで、要求ごとに1つの項目を足す
    - 閉じの区切りが無く、部分に分けられない本文
    - Tomcat は読めるが、Spring の `ContentDisposition.parse` が読めない `Content-Disposition` の部分がある本文(例: `filename*=US-ASCII''a`)
    - `Content-Type` が `multipart/mixed` の要求。Go 版では、生成したコードが中間処理の前に 400 で断る
    - `twoFactorAuthEnabled` をファイルとして送った要求
    - Tomcat が読めない URL の問い合わせを持つ要求。名前の無い項目(`=foo`)と、`%` のあとに16進の2桁が無い項目(`%ZZ` `%2`)と、UTF-8 として誤ったバイト(`%FF`)を確かめた
    - URL の問い合わせの項目の数が、1000 から部分の数を引いた数を超える要求。部分が2つのとき、問い合わせが998項目なら Java 版は 200 で答え、999項目なら 500 で答えた
  - 同じ送り方で、design.md が名指しした要求のうち、真偽として読めない `twoFactorAuthEnabled` と、ファイルとして送った `username` にも、Java 版が 500 で答えることを確かめた。値の無い問い合わせの項目(`a&&b`)を Tomcat が読み飛ばすか空の値にすることと、`twoFactorAuthEnabled` の2つの値の最初だけを読むことも、Java 版の 200 の答えで確かめた
  - Tomcat は、ファイルの名前の無い部分の名前と中身のバイト数に2を足して合計し、2097152 を超えると例外を投げる。部分の名前を RFC 2047 の ISO-8859-1 の書き方で送ると、解いた名前が本文の中の名前より長くなるので、本文が 2097152 バイト以下でも、この合計は上限を超えうる。Go 版は、この検査を写し、400 で答える。Claude は、この要求を Java 版に送っていない。Tomcat 11.0.27 の `Request.parseParts` を読んで写した。変えた動きの一覧に足す項目には、この要求も含める
- 小タスク3.1 の実装(2026-11-13): Claude は、design.md の「ImageCheck」の節のとおり、Go 版の画像の検査を `image.DecodeConfig` と `image.Decode` で書いた。そのうえで、Java 版の `UpdateUserInfoUseCase` と同じ `ImageIO` の呼び方をする1つのファイルの Java のプログラムと、Go 版の `checkImageContent` に、同じ画像を渡して比べた
  - 次の画像では、Java 版と Go 版の答えが同じだった: PNG のあとに 0 を足して 1048577 バイトにした画像、画素の塊の途中で切れた PNG、半分で切れた JPEG、最後の5バイトを消した GIF、`BM` で始まる 66 バイト、画像でない文字列、横 4097 画素の PNG、横 4096 画素の PNG、`ImageIO` が書いた JPEG と GIF、4色の JPEG に Adobe の印を付けて色の変換の種類を 0(CMYK)と 2(YCCK)にした画像
  - 次の4つの画像では、Java 版と Go 版の答えが違った。どれも、利用者が画面で普通に選ぶ画像ではなく、手で組み立てた画像である
    - GIF の外枠の大きさが 4096 画素を超え、1枚目の絵が 4096 画素以内の画像(外枠が横 5000 画素で絵が1画素のもの、外枠が横 4097 画素で絵が1画素のもの)。Java 版は1枚目の絵の大きさを見るので受け付ける。Go 版は外枠の大きさを見るので、「プロフィール画像の幅と高さは4096ピクセル以下である必要があります。」で断る
    - GIF の外枠が 4096 画素以内で、1枚目の絵が 4096 画素を超える画像(外枠が 10 画素四方で絵が横 5000 画素のもの)。Java 版は「プロフィール画像の幅と高さは4096ピクセル以下である必要があります。」で断る。Go 版は、外枠の大きさの検査を通したあと、絵が外枠からはみ出すので読めず、「有効な画像ファイルではありません。」で断る。どちらの版も断るが、文言が違う
    - Adobe の印の無い4色の JPEG。Java 版は受け付ける。Go 版は読めず、「有効な画像ファイルではありません。」で断る
    - 4色の JPEG に Adobe の印を付け、色の変換の種類を 1(YCbCr)にした画像。Java 版は読めず(`Unsupported Image Type`)、「有効な画像ファイルではありません。」で断る。Go 版は受け付ける
  - この4つの違いは、要件1の受入基準3(断る条件を Java 版と同じにする)に届かない。Java 版と同じにするには、GIF の1枚目の絵の大きさを自分で読む処理と、Go の標準の部品が読めない JPEG を読む部品が要り、design.md が決めた `image.DecodeConfig` と `image.Decode` から外れる。Claude は、変えた動きの一覧に項目を足す小タスクで所有者に項目の一覧を示すときに、この4つも示し、項目を足すか、Java 版に合わせる直しをするかを所有者に決めてもらう。PR の本文にも書く
- P5: 名前が51文字で、画像が正しい要求に、Java 版は名前の誤りで 400 を返し、利用者の行を変えなかった。それでも、置き場所には画像を置いた。Java 版は、画像を確かめたあと、名前を確かめる前に画像を置くためである。Go 版も、この順を守れば同じになる

### 名前の空白と文字数(P6〜P8)

- P6: Java 版は、名前の前後の空白を `String.strip()` で取り除く。Claude は、すべての字について Java の `Character.isWhitespace` を Java で書き出し、Go の試作の判定と比べた。両方とも、取り除く字は U+0009〜U+000D、U+001C〜U+0020、U+1680、U+2000〜U+2006、U+2008〜U+200A、U+2028、U+2029、U+205F、U+3000 で、一致した。U+00A0、U+2007、U+202F、U+0085、U+200B は取り除かない
- P7: Java 版は、名前の文字数を `String.length()` で数える。これは UTF-16 の単位の数なので、絵文字1字は2と数える。Go の試作は UTF-16 の単位で数え、50を上限にした
- P8: multipart の部分の本文に UTF-8 として誤ったバイトがあると、Java 版は JDK の UTF-8 の読み方で U+FFFD に置き換える。Go の標準の置き換えは、2通りのどちらも Java 版と違う
  - `[]rune` への変換は、誤ったバイトを1バイトずつ置き換える。`61 E3 81 62` を、Java 版は U+FFFD 1つにし、Go は2つにする
  - `strings.ToValidUTF8` は、続いた誤ったバイトをまとめて1つに置き換える。`61 F4 90 80 80 62` を、Java 版は U+FFFD 4つにし、Go は1つにする
  - Claude は、JDK の `String.decodeUTF8_UTF16` の読み方を Go の試作で写した。ランダムなバイト列30万通りで Java と比べ、すべて一致した
- 名前の要求27通りを Java 版に送った。Go の試作の判定は、26通りで、Java 版と同じ名前を保存するか同じ誤りで断った。残りの1通りは、名前に NUL(0x00)を含む要求である。Java 版は、PostgreSQL が NUL を受け付けないので、500 と「予期せぬエラーが発生しました。」で答えた。Go 版も、同じ名前を保存しようとすれば、同じデータベースの誤りになる
- ほかに、Java 版の次の動きを確かめた
  - `username` の部分が2つある要求では、Java 版は2つの値を `,` でつないだ名前を保存した
  - `username` の部分をファイルとして送る要求には、Java 版は 500 で答えた
  - 空の名前には、「ユーザー名は必ず指定してください。」で答えた

### 退会の完了のメール(P9、P10)

- P9: Java 版で試作の利用者を退会させたあと、Go の試作で、同じ宛先と名前で、退会の完了のメールを送った。Go の試作は、Java 版のひな形 `backend/src/main/resources/mail/user-deleted.ftl` をそのまま読み、`${名前}` を Go の `text/template` の差し込みに置き換えた。送り主 `no-reply@keirekipro.click`、宛先、件名「【KeirekiPro】退会手続き完了のお知らせ」、本文(テキストだけで、HTML は無い)が、文字の単位で一致した。`siteName` は `KeirekiPro`、`siteUrl` は `https://app.keirekipro.click` である
- P10: ユーザー名を持たない利用者が退会すると、Java 版は、メールのひな形の `${username}` が無いので本文を作れず、500 と「予期せぬエラーが発生しました。」で答えた。データベースの行は元に戻り、利用者は残った。一方で、その利用者のログインを続けるための値は Redis から消えていた。メールは送られなかった。Java 版は、利用者の行を消し、画像を消し、ログインの状態を使えなくしてから、同じトランザクションの中でメールを作るためである。Go 版も、同じ順に処理し、メールを作れなければトランザクションを戻して 500 で答えれば、同じになる

### 同じにできない動き

無い。P2、P4、P5、P8、P10 は、Go の標準の部品か素直な順では Java 版と違うが、Java 版と同じ読み方と順で書けば同じになると、試作で確かめた。

本番の画像の URL は、開発環境で確かめられなかった。本番では、置き場所の名前を URL のどこに書くか(道か、ホストの名前か)と、ECS のタスクの権限で署名したときの `X-Amz-Security-Token` の位置が、開発環境と違うおそれがある。並べる順は URL を使えるかどうかに関わらないので、本番で違っても画像は表示される。

## 設計の段階の記録

- 調べ方: 既存の仕組みを広げる設計なので、つなぐところに絞って調べた(light、Extension)。新しい外部のサービスとライブラリは使わない
- 調べたこと: Java 版の利用者の7つの操作の受け口、ユースケース、`User` の変更の決まり、退会の削除の問い合わせ、画像の置き場所の部品、要求の型の注釈と、Go 版の `internal/auth` と `internal/httpapi` の土台と、Java 版と Go 版を比べる検査の harness と偽の AWS である
- 分かったこと:
  - 認証の spec の `invalidateSessions` は、トランザクションの外の接続で世代の番号を上げる。退会は利用者の行を消すトランザクションの中で世代の番号を上げるので、外の接続で上げると、消した行の鍵を待ち続ける。そのため、退会は、トランザクションの問い合わせを渡せる `BumpTokenVersion` を使う
  - 筋書きの `expect` は状態の番号と項目の有無しか確かめられない。版をまたいで、変えた値がもう一方の版で見えることを確かめるには、値を確かめる欄が要る
  - 比べる検査の環境は2つの版を開発環境の設定で動かすので、版が返す署名付きの URL のホストは `localhost:4566` になる。画像を読む段は、宛先と `Host` を書き換えないと偽の AWS に届かない
  - 偽の AWS は `http.ServeMux` で要求を振り分けるので、画像の名前が `/` で始まる URL(道に `//` を含む)を、別の道に移すように答える

## 設計で比べた案

- 利用者の処理から認証の処理を使う方法:
  - 選んだ案: `internal/auth` の処理を `exported.go` で公開し、`internal/users` から呼ぶ。depguard の規則に許可を1つ足す。所有者の承認が要る
  - 選ばなかった案1: 利用者の処理を `internal/auth` の中に置く。depguard の規則を変えずに済むが、認証のパッケージが利用者のまとまりの受け持ちまで持ち、ファイルの数と責任が大きくなる。経歴書のまとまりも同じ形で足すと、`internal/auth` が全部の機能を持つことになる
  - 選ばなかった案2: 利用者の行の読み書きと確認のメールの処理を `internal/users` に写す。依存は増えないが、同じ処理の写しが2つでき、一方だけを直す誤りが起きる。Java 版と同じ動きを守る置き換えでは、この誤りが比べる検査の外で起きうる
- multipart の本文の読み方: 標準の `mime/multipart` は、試作の記録の P4 と P8 のとおり Java 版と違う結果になるので、Spring と Tomcat と JDK の読み方を写した部品を自分で書く
- 署名付きの URL の作り方: 試作の記録の P2 の2つの作り方のうち、AWS SDK の署名の部品を使う作り方を選んだ。署名の手順を手で書く作り方より、書くコードが少なく、署名の誤りが起きにくい

## 設計で決めたこと

- 退会は、Java 版と同じく、1つのトランザクションの中で、行を消し、画像を消し、世代の番号を上げ、ログインを続けるための値を消し、メールを送る。メールを作れないか送れないときは、トランザクションを戻す
- 名前と画像の変更の本文を読む処理は、生成したコードの中間処理として `internal/httpapi` に置く。`internal/users` は HTTP の要求の形を知らない
- Java 版が 500 で答え、Go 版が 400 で答える4つの要求は、変えた動きの一覧に match を書かずに載せ、Go 版の答えを単体テストで確かめる
- 筋書きの形に `request.multipart` `request.body_file` `expect.values` `expect.body_file` `expect.content_type` を足す。1MB を超える画像は `pad_to` で作り、大きなファイルをリポジトリに置かない

## 危うい点と備え

- 本番の署名付きの URL の形: 開発環境では確かめられない。本番の切り替えのときに、Java 版と Go 版が同じ利用者に返す URL を比べ、置き場所の名前の位置と `X-Amz-Security-Token` の位置を確かめる。並べる順が違っても、画像は表示される
- depguard の規則の変更で、ほかの機能のパッケージも `internal/auth` を読めるようになる。まとまりごとの spec の設計で、`internal/auth` を読むかを決める
- 退会の完了のメールを作れない利用者(名前の無い利用者)の退会は、Java 版と同じく 500 で答え、ログインを続けるための値と画像だけが消える。Java 版の誤りを直すかは、置き換えの spec の決まりのとおり所有者に報告する

## 参考にしたもの

- 試作の記録(この文書の「試作の記録」)
- 認証の spec の設計 `.kiro/specs/backend-go-auth/design.md`
- 置き換えの spec の設計 `.kiro/specs/backend-go-replacement/design.md`

## 今あるものについて確かめた文

J は `backend/src/main/java/com/example/keirekipro/` を指す。

- requirements.md 範囲の節「Issue #445 の「やらないこと」で、置き換えでは機能を足さず、仕様も変えない」: Issue #445 の本文の「## やらないこと」の節(2026-11-13 に `gh issue view 445` で確かめた)
- requirements.md 範囲の節「認証の spec の Go 版は、main に入っている」: PR #799(feat(backend-go-auth))は 2026-11-12 にマージ済み、Issue #770 は閉じている(2026-11-13 に gh で確かめた)
- requirements.md 範囲の節「確認を受け付ける操作は、設定待ちのメールアドレスを確認する場合も受ける」: backend/internal/auth/emailverification.go 47行、270行
- requirements.md 範囲の節「偽のサービスは、画像を版ごとに覚え、署名付きの URL への要求に答える」: .kiro/specs/backend-go-replacement/design.md 608行、backend/compat/fakeaws/fakeaws_test.go 145-178行
- requirements.md 範囲の節「利用者の操作の API の仕様書は main に入っている」: backend/api/openapi.yaml 446-617行
- requirements.md 範囲の節「プロフィール画像の見分け方は同じにできず、所有者が 2026-11-07 に受け入れ、変えた動きの一覧に載っている」: .kiro/specs/backend-go-replacement/research.md 47行、101-113行、backend/compat/changed-behaviors.yaml 39-44行
- requirements.md 範囲の節「画像の名前、名前の空白と文字数、退会のメールは試しに作っていない」: .kiro/specs/backend-go-replacement/research.md 43行(F1)、48行(G2)、56行(J2)。認証の spec が試しに作ったメールは4種類で、退会の完了のメールを含まない: .kiro/specs/backend-go-auth/requirements.md 176行
- requirements.md 要件1「利用者の操作が送るメールは、確認のメールと退会の完了のメールの2種類」: J usecase/user/SendAccountEmailVerificationUseCase.java 44-47行、J usecase/user/SetEmailAndPasswordUseCase.java 80-84行、J infrastructure/event/user/UserDeletedEventListener.java 29-37行、backend/src/main/resources/mail/ の email-verification.ftl と user-deleted.ftl
- requirements.md 要件1「退会では、利用者の情報と経歴書と、アップロードしたプロフィール画像を消す」: J usecase/user/DeleteUserUseCase.java 44-66行、J infrastructure/repository/user/UserMapper.xml 153-281行
- requirements.md 要件1「すでに居ない利用者の要求は、断るときに Cookie を消す」: J usecase/user/ChangePasswordUseCase.java 39-40行(各ユースケースの findById)、J presentation/shared/AppExceptionHandler.java 47-55行
- requirements.md 要件1「断る条件に、名前の長さ、画像の大きさと縦と横、パスワードの長さと文字の決まりがある」: J usecase/user/UpdateUserInfoUseCase.java 40-53行、J domain/model/user/User.java 806-818行、J presentation/user/dto/ChangePasswordRequest.java 24-31行、J presentation/user/dto/SetEmailAndPasswordRequest.java 24-39行
- requirements.md 要件3「パスワードの変更と、パスワードを持つ利用者のメールアドレスとパスワードの設定で、今のパスワードを確かめる」: J usecase/user/ChangePasswordUseCase.java 44-46行、J usecase/user/SetEmailAndPasswordUseCase.java 63-67行
- requirements.md 要件3「パスワードの変更と退会で、すべての端末のログインの状態を使えなくする」: J usecase/user/ChangePasswordUseCase.java 57-59行、J usecase/user/DeleteUserUseCase.java 60-61行、J presentation/user/controller/DeleteUserController.java 46-49行
- requirements.md 要件3「確認のメールの間隔の制限と、確認のリンクの有効な時間」: J infrastructure/store/auth/RedisEmailVerificationSendLimiter.java 27行(60秒)、J usecase/auth/verification/EmailVerificationPurpose.java 19-24行(24時間)
- requirements.md 要件3「2段階認証の設定を変えられる条件」: J domain/model/user/User.java 703-717行
- requirements.md 要件3「つなぎを解除できる条件」: J domain/model/user/User.java 741-756行
- requirements.md 要件3「プロフィール画像を見せる URL を使える時間」: J usecase/user/GetUserInfoUseCase.java 40-45行(10分)
- requirements.md 要件5「2MB を超えるファイルを送る要求に、Java 版は 500 で答える」: backend/api/openapi.yaml 470-471行
- requirements.md 要件5「画面は 1MB を超える画像を送る前に断る」: frontend/src/features/user/components/SettingUserContainer.tsx 17-20行、58-67行
- requirements.md 要件6「認証の spec は、ログインした開発者への答えを利用者のまとまりの spec で確かめると決めた」: .kiro/specs/backend-go-auth/requirements.md 170行、.kiro/specs/backend-go-replacement/progress.md のまとまりの表の下の箇条
- requirements.md 要件7「状態は `spec の作成中` `作り終えた` `比べる検査に通った` を使う」: .kiro/specs/backend-go-replacement/progress.md のまとまりの表の上の文
- requirements.md 要件5「退会した利用者のログインの状態がログインの状態の検査を通るかは、退会の前にすべての端末のログインの状態を使えなくする操作をしたかで変わる」: J usecase/user/DeleteUserUseCase.java 49行(利用者の行を先に消す)と 61行(そのあとで版を上げる)、backend/src/main/resources/db/migration/V3__create_user_token_versions.sql 3行(ON DELETE CASCADE)、J infrastructure/store/auth/UserTokenVersionMapper.xml 29-35行(UPDATE だけで、行が無ければ何も変えない)、J infrastructure/store/auth/MyBatisUserTokenVersionStore.java 23行(行が無ければ版を 0 とみなす)
- design.md 処理の流れ「退会」「世代の番号を上げる問い合わせは、利用者の行を消したトランザクションの中で送り、何も変えない。Java 版も同じトランザクションの中で送る」: J usecase/user/DeleteUserUseCase.java 39行(@Transactional)、49行、61行、J usecase/auth/session/AuthSessionInvalidator.java 29-31行、backend/db/queries/auth.sql 144-148行、backend/internal/auth/accesstoken.go 100-112行
- design.md 処理の流れ「退会」「認証の spec の invalidateSessions はトランザクションの外の接続を使う」: backend/internal/auth/refreshtoken.go 118行
- design.md 処理の流れ「名前と画像と2段階認証の設定の変更」「画像を置いてから名前を確かめ、変更のあとで情報を読み直す」: J usecase/user/UpdateUserInfoUseCase.java 65-110行、J presentation/user/controller/UpdateUserInfoController.java 50-55行
- design.md 部品「Service」「利用者が居なければ 401 と不正なアクセスと2つの Cookie を消す」: J usecase/user/GetUserInfoUseCase.java 35-40行、J presentation/shared/AppExceptionHandler.java 47-55行、backend/internal/auth/errors.go 95-135行
- design.md 部品「公開した認証の処理」「BumpTokenVersion は Service のメソッドとして公開してある」: backend/internal/auth/accesstoken.go 100-102行
- design.md 部品「公開した認証の処理」「EmailInUse は users の email の列だけを見る」: J domain/service/user/UserEmailDuplicationCheckService.java 26-37行、J infrastructure/repository/user/UserMapper.xml 82行、backend/db/queries/auth.sql 31-53行、backend/internal/auth/login.go 222-228行
- design.md 部品「公開した認証の処理」「確認のメールの送り出し、今のリンクの記録を消す処理、利用者の行の型と読み書きとトランザクション」: backend/internal/auth/emailverification.go 180行、199行、460-473行、524行、548行
- design.md 部品「Error」「500 の文言」: J presentation/shared/AppExceptionHandler.java 174-182行
- design.md 部品「Validate」「@PasswordMatches は2つの値がどちらも null でなく違うときに、項目 confirmPassword に既定の文言を付ける」: J presentation/shared/validator/PasswordMatches.java 25-27行、J presentation/shared/validator/PasswordMatchesValidator.java 23-35行、J presentation/user/dto/SetEmailAndPasswordRequest.java 24行
- design.md 部品「Validate」「2つの要求の型の注釈と文言」: J presentation/user/dto/ChangePasswordRequest.java 20-42行、J presentation/user/dto/SetEmailAndPasswordRequest.java 20-42行
- design.md 部品「UserInfo」「10の項目の順と、URL を使える時間」: J presentation/user/dto/UserInfoResponse.java 20-42行、J usecase/user/GetUserInfoUseCase.java 40-45行
- design.md 部品「Update」「名前の決まり」: J domain/model/user/User.java 803-825行
- design.md 部品「Update」「2段階認証の2つの条件は同時に当たらない」: J domain/model/user/User.java 703-717行
- design.md 部品「本文を読む中間処理」「中身が0バイトの画像は、画像が無いものとして扱う」: J usecase/user/UpdateUserInfoUseCase.java 78行、121行
- design.md 部品「ImageCheck」「6つの検査の順と文言と上限」: J usecase/user/UpdateUserInfoUseCase.java 38-53行、115-160行
- design.md 部品「ObjectStore」「Content-Type とメタデータの Content-Type に部分の Content-Type を入れる」: J infrastructure/shared/aws/s3/S3ObjectStore.java 75-85行
- design.md 部品「ObjectStore」「署名付きの URL を作り、開発環境でホストを localhost にする」: J infrastructure/shared/aws/s3/S3ObjectStore.java 169-177行、J infrastructure/shared/aws/s3/LocalstackPresignedUrlTransformer.java 13-14行
- design.md 部品「ObjectStore」「開発環境は設定 Env が dev のとき」: backend/internal/platform/config/config.go 22-28行、74行
- design.md 部品「Delete」「11の表を UserMapper.xml と同じ順で消す」: J infrastructure/repository/user/UserMapper.xml 153-281行(156、172、186、200、214、228、242、256、263、270、277行)
- design.md 部品「Delete」「消す画像の名前は4つの拡張子の名前と今の画像の名前」: J usecase/user/DeleteUserUseCase.java 52-58行、J usecase/user/ProfileImageKeys.java 10-50行
- design.md 部品「Delete」「退会の完了のメールはメールアドレスの確認が済んだ利用者にだけ送る」: J domain/model/user/User.java 855-870行、J infrastructure/event/user/UserDeletedEventListener.java 25-40行
- design.md 部品「Mail」「件名とひな形」: J infrastructure/shared/notification/SesFreeMarkerNotificationDispatcher.java 75行、backend/src/main/resources/mail/user-deleted.ftl 1行
- design.md 部品「Password」「メールアドレスとパスワードの設定の順と、送れたかを見ないこと」: J usecase/user/SetEmailAndPasswordUseCase.java 31行、57-84行
- design.md 部品「Password」「パスワードの変更の順」: J usecase/user/ChangePasswordUseCase.java 36-60行
- design.md 部品「Provider」「連携の解除の条件と文言」: J usecase/user/RemoveAuthProviderUseCase.java 30-43行、J domain/model/user/User.java 738-760行
- design.md 部品「EmailVerification」「送る先の選び方と2つの文言」: J usecase/user/SendAccountEmailVerificationUseCase.java 25行、27行、38-55行
- design.md 部品「本文を読む中間処理」「本文の上限は 2MB」: backend/src/main/resources/application.yaml 28-29行
- design.md 部品「本文を読む中間処理」「生成したコードは中間処理の前に MultipartReader を呼ぶ」: backend/internal/httpapi/gen/api.gen.go 9552-9582行
- design.md 部品「利用者の受け口」「authResponse は Cookie を2つ以上書ける」: backend/internal/httpapi/authresponses.go 15-24行、43-46行
- design.md 部品「httpapi.New の変更」「受け口の深さと中間処理の並び」: backend/internal/httpapi/server.go 26-112行、backend/cmd/keirekipro/main.go 143-182行
- design.md 部品「品質チェックの設定の変更の提案」「feature の規則の許す一覧は internal/platform だけ」: backend/.golangci.yml 43-52行
- design.md 部品「Java 版と Go 版を比べる検査の広げ方」「比べる検査は開発環境の設定で動かし、接続先は偽の AWS のポート 4566」: backend/compat/harness/versions.go 46-47行、74-75行、98行、108行、backend/compat/harness/stack.go 229行、backend/compat/fakeaws/fakeaws.go 34行
- design.md 部品「Java 版と Go 版を比べる検査の広げ方」「偽の AWS は ServeMux で振り分ける」: backend/compat/fakeaws/fakeaws.go 80-92行
- design.md 部品「Java 版と Go 版を比べる検査の広げ方」「筋書きの欄は状態の番号と項目の有無だけ」: backend/compat/harness/scenario.go 154-172行
- design.md 部品「Java 版と Go 版を比べる検査の広げ方」「画像の置き場所の比べ方は名前とバイトの並び」: backend/compat/harness/compare.go 515行、539行
- design.md 部品「利用者の操作の筋書き」「oidc_users、Redis を書き換える段、期限を切らす段、cookie と mail の取り出し」: backend/compat/harness/scenario.go 55行、105-111行、131行、backend/compat/harness/capture.go 31-34行
- design.md 部品「利用者の操作の筋書き」「利用者のまとまりは group 2」: backend/compat/harness/operations.go 17-23行
- design.md 部品「変えた動きの一覧の項目」「CB-011 の形と、CB-027 が最後の項目」: backend/compat/changed-behaviors.yaml 118-134行、301行
- design.md データの形「Redis のキー」: backend/internal/auth/emailverification.go 33-34行
- design.md プロジェクトの決まり「カバレッジの下限は 93%」: backend/.testcoverage.yml 9行
- design.md 全体の構成「使う技術の版」: backend/go.mod
- design.md 部品「Password」「メールアドレスの空と形の誤りは集めるだけで、すでにメールアドレスを持つ誤りと一緒に返す」: J usecase/user/SetEmailAndPasswordUseCase.java 57-71行、J domain/model/user/Email.java 36-48行、J domain/model/user/User.java 587-596行、J domain/service/user/UserEmailDuplicationCheckService.java 26-37行
- design.md 部品「公開した認証の処理」「EmailCreateErrors は emailCreateErrors を呼ぶ」: backend/internal/auth/commonsemail.go 55-71行
- design.md ファイルの構成「storedUser を使うファイル」: backend/internal/auth/emailverification.go、oidccallback.go、passwordreset.go 112-122行。backend/internal/auth/ のテストのファイルには、storedUser と loadStoredUser と saveUser を使う箇所が無い(2026-11-13 に *_test.go を検索して0件)。テストのファイルにあるのは補助の関数 insertStoredUser で、emailverification_integration_test.go、oidc_integration_test.go、passwordreset_integration_test.go が使う
- design.md 部品「Java 版と Go 版を比べる検査の広げ方」「偽の AWS は署名を調べず、Host のホスト名で版を選ぶ」: backend/compat/fakeaws/fakeaws.go 5行、103-113行、backend/compat/fakeaws/s3.go 57-59行
- design.md ファイルの構成「s3.go は r.PathValue で名前を読む」: backend/compat/fakeaws/s3.go 43-44行、59行、93行
- design.md 部品「利用者の操作の筋書き」「確認の済んでいない利用者はパスワードでログインできない」: backend/internal/auth/login.go 77-79行
- design.md 部品「利用者の操作の筋書き」「連携で見つけた利用者は、Google が確認の済んだメールアドレスを返さなければ確認済みにならない」: backend/internal/auth/oidccallback.go 237-245行、538-561行、598-606行、backend/compat/harness/scenario.go 65-70行
- design.md 部品「Validate」「生成した要求の型の項目の型」: backend/internal/httpapi/gen/api.gen.go 297-300行、652-657行、J presentation/user/dto/ChangePasswordRequest.java 24-31行
- design.md 部品「変えた動きの一覧の項目」「CB-020 の形」: backend/compat/changed-behaviors.yaml 235-241行
