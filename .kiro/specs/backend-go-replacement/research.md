# 調べたことの記録

## 段階1 試作の記録

この節は、要件2のとおり、設計を書く前に Claude が試しに作って確かめた結果を残す。設計の段階でこの節を書き換えない。設計の段階で調べたことは、この節のあとに別の節として書く。

### 確かめた環境

- Java 版: main の 492ae6ae の backend を、開発環境の PostgreSQL、Redis、LocalStack につないで動かした。データベースは試作のためだけに作った `keireki_proto` を使い、Redis は DB 5 を使った
- Go: go1.27.3(イメージ golang:1.27-bookworm)
- PDF の試作: 上のイメージに Chromium 156.0.8078.79 と、今の backend が使う Noto の4つのフォント(NotoSansJP と NotoSerifJP の Regular と Bold)を入れたイメージ
- Go の部品: chromedp v0.23.0、golang.org/x/text、golang.org/x/net、golang-jwt、golang.org/x/crypto/bcrypt
- 試作のコードは作業用のフォルダに置き、リポジトリに入れていない(要件2の受入基準3)

### 洗い出した動きと結果の一覧

結果の欄の意味は次のとおりである。

- 同じ: 試作で、Java 版と同じ結果になることを確かめた
- 違う: 試作で、そのまま作ると違う結果になることを確かめた。同じにする方法と、同じにできない部分を下の節に書く
- 試作せず: Go の標準のライブラリか広く使われる部品で同じ結果を作れ、作れない危険が低いと判断した。細かい応答は、Java 版から作る API の仕様書と、Java 版と Go 版を比べる検査(要件4)で確かめる

| 記号 | 動き | 結果 |
|---|---|---|
| C1 | 保存されたパスワードでのログイン(BCrypt) | 同じ |
| C2 | ログインの状態のトークン | 同じ |
| C3 | メールアドレスの確認のトークン | 同じ |
| C4 | Cookie の書き方 | 同じ |
| C5 | 偽の送信を防ぐトークン(CSRF) | 同じ |
| C6 | ログインを続けるためのトークンとログアウト | 同じ |
| C7 | 2段階の認証 | 同じ |
| C8 | 外部のサービスでのログイン(OIDC)の URL | 試作せず |
| C9 | パスワードの再設定、メールアドレスの確認、送る回数の制限 | 試作せず |
| C10 | 乱数で作る文字列の形 | 試作せず |
| D1 | Redis に書く値の形 | 同じ(C6 と C7 で確かめた) |
| D2 | 本番の Redis(ElastiCache Serverless Valkey のクラスタの形) | 試作せず |
| E1 | データベースの変更の履歴の表 | 試作せず |
| E2 | 日時を日本の時刻で保存すること | 試作せず |
| E3 | 文字列の配列の列 | 試作せず |
| E4 | 複数の SQL の文を1回で送る箇所 | 試作せず |
| E5 | 日本語の名前の並び順 | 違う |
| E5 | 同じ名前のときの並び順(UUID の比べ方) | 試作せず |
| F1 | 前後の空白の取り除き方と、文字数の数え方 | 試作せず |
| F2 | メールアドレスの形の検査 | 同じ |
| F3 | UUID の読み方 | 試作せず |
| F4 | PDF の設定の値の直し方 | 試作せず |
| G1 | プロフィール画像の検査 | 違う |
| G2 | S3 に置くファイルの名前 | 試作せず |
| H1 | PDF の見た目 | 違う |
| H2 | PDF の本文の HTML の逃がし方 | 試作せず |
| H3 | Markdown の本文 | 試作せず(Java 版の動きを確かめた) |
| H4 | ダウンロードのファイル名(Content-Disposition) | 試作せず(Java 版の動きを確かめた) |
| I1 | Java 版のバックアップを Go で読み、Go で書いたバックアップを Java 版が戻すこと | 同じ |
| I2 | バックアップの版の照合 | 試作せず |
| J1 | SES でのメールの送り方 | 試作せず |
| J2 | メールの本文の5種類 | 試作せず |
| K1 | ログの形 | 試作せず |
| B1 | JSON の文字の書き方 | 違う(意味は同じ) |
| B2 | JSON の項目の順と、空の項目の扱い | 試作せず |
| B3 | 日時の書き方 | 試作せず(Java 版の動きを確かめた) |
| A1〜A9 | HTTP の細かい動き(エラーの応答、406、末尾の `/`、自動で付くヘッダ、CORS、ファイルの上限) | 試作せず |
| L1〜L4 | 起動と運用(秘密の値の読み込み、生きているかの確認、止め方、API の説明画面) | 試作せず |

### 認証(C1〜C7)

Claude は、Go の試作と Java 版を同じデータベースと Redis につなぎ、どの動きも両方の向きで確かめた。

- C1: Go が作ったパスワードのハッシュで、Java 版にログインできた。Java 版が作ったハッシュ(`$2a$10$` で始まる)を、Go が照合できた。73バイトのパスワードは、両方が断った
- C2: Go が作ったトークンを Java 版が受け入れ、Java 版が作ったトークンを Go が受け入れた。期限の切れたトークンは、両方が断った。Java 版はトークンを断ったときに、Cookie の accessToken を消す `Set-Cookie` を返す。Go 版も同じ文字列を返す
- C3: Java 版が作ったトークンを Go が読め、Go が作ったトークンを Java 版が受け入れた。Go の golang-jwt は宛先(aud)を配列で書き、Java の java-jwt は文字列で書くが、どちらの形も両方が受け入れた
- C4: accessToken、refreshToken、twoFactorChallenge の `Set-Cookie` の文字列が、Java 版と同じになった
- C5: Go が作った Cookie の XSRF-TOKEN とヘッダの X-XSRF-TOKEN の組を、Java 版が受け入れた。組が無いと、Java 版は 403 と `{"message":"アクセス権限がありません。"}` と新しい XSRF-TOKEN を返す
- C6: Go が書いたトークンで Java 版がアクセストークンを出し、Java 版が書いたトークンを Go が読めた。Java 版でログアウトすると、Go が書いたトークンも消え、Go は古いアクセストークンを断った
- C7: Go が書き直した2段階の認証の途中の記録で、Java 版が認証を終えた

### 日本語の名前の並び順(E5)

Java 版は、ポートフォリオ、SNS、自己PR などの名前を、Java の日本語の並べ替えの規則(Collator)で並べる。並び順は、画面と PDF に出る。

Claude は、61語を、Java 版と Go の golang.org/x/text/collate(日本語)で並べて比べた。

- 同じ位置になった語は、61語のうち1語だけだった
- 漢字どうしの順は同じだった
- Java は、全角の英数字、半角のカナ、絵文字を最後に置く。golang.org/x/text/collate は、そう並べない
- 小さい仮名、長音、濁点の順も違った。例として、Java は「つつ」を「っつ」より前に置き、golang.org/x/text/collate は「っつ」「ッツ」「つつ」の順に置く

同じにする方法は、Java の並べ替えの規則を Go に写すことだけである。ただし、その規則は OpenJDK のコードの一部で、写すと Go 版のコードが OpenJDK の許諾(GPLv2 と Classpath Exception)の条件を受けるおそれがある。そのため、Claude はこの動きを同じにできない動きとして所有者に報告する。

### メールアドレスの形の検査(F2)

Claude は、Java 版が使う commons-validator 1.11.0 の規則と、最上位のドメインの一覧(1437件)を Go に写した。commons-validator の許諾は Apache 2.0 なので、写しても問題は無い。48件のメールアドレスで、すべて Java 版と同じ結果になった。

写すときに Java 版と同じにする点は次のとおりである。

- 最後の `@` で、利用者の部分とドメインに分ける
- 利用者の部分の長さは、UTF-16 で数えて64以下にする
- 末尾が `.` のアドレスは断る
- `[IPv6:...]` の形のときだけ IPv6 を受け、それ以外の角括弧は IPv4 だけを受ける
- 日本語のドメインは、IDNA2003 の変換で ASCII に直す。Go の golang.org/x/net/idna は IDNA2008 なので、変換の形を Transitional にし、Unicode 3.2 に無い文字(BMP の外の文字)を断ることで近づけた。この近づけ方で違いが出ないかは、比べる検査で確かめる

### プロフィール画像の検査(G1)

Java 版は、送られた画像を Java の ImageIO で読めるかで確かめる。Claude は、11個のファイルを、Java 版の確かめ方と、Go の標準のライブラリ(PNG、JPEG、GIF)で比べた。

| ファイル | Java 版 | Go の標準のライブラリ |
|---|---|---|
| PNG、JPEG、GIF | 受け入れる | 受け入れる |
| BMP、WBMP | 受け入れる | 断る |
| TIFF、WebP | 断る | 断る |
| 途中で切れた JPEG | 受け入れる | 断る |
| 途中で切れた PNG と GIF | 断る | 断る |

Java 版は、ファイルの名前が `.png` で種類の欄が `image/png` なら、中身が BMP か WBMP でも受け入れ、そのまま保存する。Go 版で同じにするには、BMP は golang.org/x/image/bmp を足せば読め、WBMP は小さな読み手を自分で書けば読める。途中で切れた JPEG は、Go の JPEG の読み手が途中までの画像を返さないので、同じにできない。

### PDF の見た目(H1)

Claude は、Java 版のテンプレートに同じデータを入れた HTML を、Chromium で PDF にした。Java 版の PDF と比べた結果は次のとおりである。

- ページ数、フォント(NotoSansJP と NotoSerifJP の Regular と Bold)、用紙の大きさ(A4)は同じだった
- 1ページを作るのに約340ミリ秒かかった
- Chromium は、テンプレートの `word-break: break-all` のとおりに、英単語の途中で行を折り返した(例: 「AW」と「S」)。Java 版の openhtmltopdf は、英単語の切れ目で折り返す。Go 版のテンプレートの指定を `word-break: normal; line-break: strict; overflow-wrap: anywhere;` に変えると、行の折り返しが同じになった
- 職歴の表の期間の列の幅が違った。Chromium は幅 185px に内側の余白を含め、openhtmltopdf は含めない。Go 版のテンプレートで幅を 193px にすると、そろった
- この2つを直したあとも、文字の位置が1〜2pt ずれた。各ページの最後の文は同じになり、改頁の位置は同じだった。画素で比べると、1ページあたり約7〜15%の画素が違った。ずれが小さくても、ずれた文字の画素はすべて違うと数えるため、割合は大きく出る
- Java 版の PDF から文字を写すと、「〜」(U+301C)が「～」(U+FF5E)になる。Chromium の PDF では「〜」のまま写る

Chromium で作るときに本番で必要になることは次のとおりである。

- コンテナのイメージが Chromium の分だけ大きくなる
- Chromium に、JavaScript を動かさせず、外へ通信させない
- フォントを fontconfig でイメージに入れる

### Markdown の本文(H3)

Java 版は、Thymeleaf の TEXT の形のテンプレートで Markdown を作る。このテンプレートの `[[...]]` は、`<` `>` `&` `"` `'` を `&lt;` `&gt;` `&amp;` `&quot;` `&#39;` に書き換える。そのため、利用者が「`<script>&amp;`」と書いた内容は、Markdown のファイルに「`&lt;script&gt;&amp;amp;`」と出る。Go の html.EscapeString は `"` を `&#34;` と書くので、Go 版は同じ5文字を同じ形に書き換える関数を自分で書く。

入力の足りない経歴書を書き出そうとすると、Java 版は 400 と、足りない項目を並べた JSON を返す。これは、frontend と同じ `Accept: text/markdown, application/json` を付けたときの動きである。

### ダウンロードのファイル名(H4)

Java 版は、Spring の ContentDisposition で、次の形のヘッダを返す。

```
attachment; filename="______backup.json"; filename*=UTF-8''%E5%85%83%E3%81%AE%E7%B5%8C%E6%AD%B4%E6%9B%B8_backup.json
```

- `filename` は、ASCII でない文字を1文字ずつ `_` に置き換える
- `filename*` は、英数字と `!#$&+-.^_`|~` を残し、それ以外を `%XX` にする

Go の mime.FormatMediaType は形が違うので、Go 版はこの形を作る関数を自分で書く。

### バックアップ(I1)

Claude は、Java 版で自己PR を持つ経歴書のバックアップを書き出し、Go で読んだ。Go は、項目を名前の順に並べ替え、`<>&` と U+2028 を逃がす Go の書き方で書き直した。Java 版は、Go が書き直したバックアップを 201 で戻し、戻した自己PR の本文は元の本文と同じだった。Go が Java 版のバックアップを戻す処理は、まだ無い。Go が Java 版のバックアップを読めることは確かめたので、戻す処理は機能のまとまりの spec で作り、比べる検査で確かめる。

### JSON の書き方(B1、B3)

意味は同じだが、文字の書き方が違う。

- Java 版は、絵文字を `😀` と書き、U+2028 と U+2029 と U+007F をそのまま書き、`<>&` を逃がさない
- Go の encoding/json は、絵文字をそのまま書き、U+2028 と U+2029 をいつも逃がし、既定では `<>&` を `<` などに逃がす

frontend は JSON を解析してから使うので、利用者から見た違いは無い。Java 版と Go 版を比べる検査は、文字の並びでなく、解析した値で比べる。

日時の書き方は、次のとおりである。Go の time の書式で同じ形を作れる。

- 作った日時と直した日時は、日本の時刻で、時差を付けずに書く(例: `2026-11-07T22:55:54.072661`)。秒の下の桁は、値によって6桁か9桁になる
- 日付は `2026-11-07` の形で書く
- バックアップの書き出した日時は、世界標準時で `Z` を付けて書く

### 試作の途中で見つけた Java 版の不具合

`Accept: text/markdown` だけを付けて、入力の足りない経歴書を書き出すと、Java 版は 401 と空の本文を返した。Java 版が、エラーの JSON を Markdown の形で書けずに失敗し、エラーの画面の処理に回って 401 になったと考えられる。frontend は `Accept` に `application/json` も付けて送るので、利用者の操作ではこの不具合は起きない。

### 試作せずと判断した動きの理由

- C8〜C10: URL と乱数の文字列の形は、Go の標準のライブラリで同じ形に作れる。送る回数の制限は Redis の Lua の台本で数えており、Go からも同じ台本を送れる
- D2: Go の Redis の部品(go-redis)はクラスタの形に対応している。今のキーは `{}` で囲んだ部分で置き場所が決まる(ハッシュタグ)。同じキーの名前を使えば、置き場所も同じになる
- E1〜E4: Go のデータベースの部品(pgx)で同じ型を読み書きできる。複数の文を1回で送る箇所は、パラメータ付きの問い合わせでは pgx が受け付けないので、Go 版では文ごとに分けて同じトランザクションで送る。データベースの変更の履歴の表の扱いは、設計で決める
- F1、F3、F4: Java の空白の判定と UTF-16 の文字数の数え方、緩い UUID の読み方は、小さな関数で同じにできる
- G2、I2、J1、J2、K1: 文字列の形を同じにすれば済む。メールの本文は、Go のテンプレートで作り直し、比べる検査で本文を比べる
- A1〜A9、B2、L1〜L4: Go の net/http と、Java 版から作る API の仕様書で同じ応答を作れる。細かい応答は、比べる検査で確かめる

### 同じにできない動きの扱い

Claude は、同じにできない4つの動きを所有者に報告した。所有者は、2026-11-07 に、4つとも Claude の推奨のとおりに決めた。決めた扱いは、Issue #445 の本文の「決めた方式」に書いてある。

- 日本語の名前の並び順(E5): Go の標準の日本語の並び順に変え、変えた動きの一覧に載せる
- PDF の見た目(H1): 文字の位置の1〜2pt のずれと、写したときの「〜」の文字の違いを受け入れる
- プロフィール画像の検査(G1): 中身が PNG、JPEG、GIF のファイルだけを受け入れ、途中で切れた JPEG は断る。変えた動きの一覧に載せる
- 入力の足りない経歴書の書き出し: 要求の Accept の値によらず、400 と足りない項目の一覧を返す。変えた動きの一覧に載せる

## 設計の段階の記録

この節から下は、設計の段階で Claude が調べたことと、設計で選んだことの理由を残す。上の「段階1 試作の記録」の節は書き換えていない。

### まとめ

- 対象: backend-go-replacement(Issue #445)
- 調べ方: 全部を調べる形。新しい言語の導入と、本番の切り替えを含むためである
- 設計を決めた主な発見:
  - Flyway が表の形の履歴を記録する表(`flyway_schema_history`)の検査の値は、Go で同じ値を計算できる。今の7つのマイグレーションのすべてで、データベースに記録された値と一致した。Go 版は、表の形の履歴を、移し替えずにそのまま続けられる
  - CodeQL の言語の対応表(`.github/codeql/languages.tsv`)では、Go の行のビルドのしかたが空になっている。このままでは、Go のファイルを1つでも含む PR で、言語を見分ける仕事が失敗する。Go のコードを main に入れる最初の PR で、所有者の承認つきでこの行を埋める必要がある
  - 本番の ECS のタスク定義は、秘密の値をタスク定義で渡さず、アプリが Secrets Manager から自分で読む。Go 版も同じ読み方にすれば、Java 版と Go 版でタスク定義を共有でき、出荷するイメージを替えるだけで切り替えと戻しができる
  - 開発環境の LocalStack は、起動に認証トークンが要る。CI には認証トークンが無いので、比べる検査は LocalStack を使えない

### 今の CI と本番の作り

- 調べたきっかけ: 切り替えの仕組みと、Go 版の品質チェックを、今の CI と本番にどうつなぐかを決めるため
- 調べたもの: `.github/workflows/` のすべて、`.github/audit/required-checks.json`、`terraform/` のすべて、`compose.yaml`、`.claude/scripts/parallel/run-check.sh`、`backend/gradle/quality.gradle`
- 分かったこと:
  - CI の `backend-test` は、`backend/**` が変わったときに `./gradlew check` を流す。必須の検査の期待一覧に、`backend-test` は変わった領域で決まる必須の検査として載っている
  - 必須の検査の名前は、リポジトリのファイルでは管理されておらず、GitHub の ruleset の設定にある。新しい必須の検査を足すと、所有者が ruleset を変える操作が増える
  - 本番の出荷(`release.yaml` から呼ぶ `backend-deploy.yaml`)は、`./backend` を文脈にして `docker/backend/Dockerfile.prod` を arm64 で組み立て、ECR の `keirekipro-backend` にコミットの SHA を付けて送る。そのあと、今のタスク定義のイメージだけを替えて登録し、サービスを更新して安定するまで待つ
  - ECS のサービスは、最小 100%・最大 200% で入れ替え、デプロイのサーキットブレーカーで失敗したら前のタスク定義に戻す
  - タスク定義は、CPU 256、メモリ 2048、ARM64、ポート 8080 で、環境変数は `SPRING_PROFILES_ACTIVE=prod` `TZ=Asia/Tokyo` `JAVA_TOOL_OPTIONS` である。コンテナの生きているかの確認は `curl -f http://localhost:8080/actuator/health` で、ALB の確認の経路も `/actuator/health` である
  - ログは awslogs で `/ecs/keirekipro-backend` に書かれる
  - 秘密の値は `keirekipro/rds` `keirekipro/redis` `keirekipro/jwt` `keirekipro/oidc/google` `keirekipro/oidc/github` にある。`keirekipro/redis` には、Spring の設定の名前をそのまま使ったキー(`spring.data.redis.cluster.nodes` と `spring.data.redis.username`)がある
- 設計への影響:
  - 必須の検査の名前を増やさず、`backend-test` を、Java 版の検査と Go 版の検査と比べる検査の結果をまとめる仕事にする。所有者の ruleset の操作を増やさないためである
  - タスク定義を Java 版と Go 版で共有する。Go 版は、`/actuator/health` を切り替えの間も返し、イメージに curl を入れる
  - Go 版が要る値は、Java 版が読まない新しい環境変数と、秘密の新しいキーとして、段階4で先に足す

### Java と Spring を前提にした記述と、使っていないもの

- 調べたきっかけ: 要件15の書き換えの対象と、要件16の消す一覧を作るため
- 調べたもの: `git grep` で、Java、Spring、Gradle、JDK、JaCoCo、PIT などの名前を含むファイルをすべて挙げ、ファイルごとに言語を書いてよいかを分けた。compose のボリュームとポート、`.gitignore` の行、frontend の部品、スキルについて、参照する箇所があるかを調べた
- 分かったこと: 書き換える対象と消す候補は、design.md の「移行」の節と「消す一覧」の節に書いた。Claude は、compose のボリューム `vendor`、frontend のポート 6006、`.gitignore` の `output.sh` と `output_result.txt`、frontend の `@react-router/node` と `@react-router/dev` について、参照が無いことを自分で確かめた
- 設計への影響: 消す一覧に、消すものごとの理由を書き、調べて残すと決めたものも並べる

### 段階6の書き換えの検査の語と、生きているかの確かめの経路(2026-11-08 の作り直し)

- 調べたきっかけ: design の審査の指摘 D1-3-1 が、6-4 の検査の語の一覧に Java 版だけの道具の名前が足りないと指摘し、所有者が設計を作り直すコマンドを打った
- 調べたもの: `backend/gradle/libs.versions.toml` と `backend/build.gradle` の依存とプラグインの名前、`docker/backend/` の Dockerfile の土台のイメージを読んだ。足した語の一覧で `git grep` を `.kiro/specs/` と `backend/src/` を除いて動かし、拾う語を数えた。`actuator` を含む設定とスクリプトを `git grep` で挙げた
- 分かったこと: 足した語の一覧は、`.kiro/steering/structure.md` の `MyBatis〜Repository` `Mockito単体` `MockMvc契約テスト` の行と、`.claude/scripts/parallel/ui.sh` の `actuator/health` の行を拾う。`maven` は vuln-watch のスクリプトが部品の種類の名前として使っており、Go 版に替えるときに書き換える対象である。`/actuator/health` は、`start-dev.sh`、`ui.sh`、`test-ui.sh`、`verify-ui` のスキル、terraform の ALB とタスク定義が呼んでいる。terraform の分は 6-2 で替わるが、開発環境の分は 6-4 まで替わらず、6-3 で Go 版から経路を消すと、6-3 から 6-4 までの間、開発環境の起動の確かめが失敗する
- 設計への影響: 6-4 の検査の語の一覧を種類ごとの表にし、6-4 の PR を作るときに 6-1 で消す前の Java 版の部品の名前を `git show` で読んで足す文を書いた。開発環境の生きているかの確かめの経路を `/healthz` に替える作業を 6-1 に入れ、6-3 の PR の前に `actuator/health` を呼ぶ設定とスクリプトが残っていないことを確かめる文を書いた

### Go の部品と道具

- 調べたきっかけ: 決めた方式(Webフレームワークを使わない、仕様書からコードを生成する、Go にとって標準的な作り)に合う部品を選ぶため
- 調べたもの: 各部品の公式の文書と GitHub のリリース。2026-11-08 に確かめた
- 分かったこと:
  - Go は go1.27.3 が最新で、1.26 と 1.27 が保守の対象である。go.mod の `tool` の指定で、道具の版を固定できる
  - oapi-codegen v2.8.2 は OpenAPI 3.1 に対応し、`std-http-server` で標準の `http.ServeMux` に経路を登録するコードを作る。`strict-server` は、操作ごとに型の付いた要求と応答を作る。同じ応答に複数の `Set-Cookie` を付けるときは、応答の型に自分で書き込みの関数を持たせる
  - データベースは pgx v5.11.0 と sqlc v1.31.1 が広く使われる。sqlc は表の形をマイグレーションのファイルから読むが、ファイルを名前の順に読むので、`V10` が `V2` より前になる。ファイルを順に並べて渡す必要がある
  - goose、golang-migrate、tern は、Flyway の履歴の表を読めない。golang-migrate は `V1__` の形の名前を受け付けない。Atlas は Flyway の形のファイルを読むが、自分の表を使う
  - golangci-lint v2.15.0 は、設定を `version: "2"` で書き、書式の検査(gofumpt と goimports)も受け持つ。公式は、`go tool` での導入でなく、版を固定した実行ファイルの導入を勧める
  - 層の依存の向きは、golangci-lint の depguard で検査できる。`internal/` の下のパッケージは、外のモジュールからの import をコンパイラが止める
  - Go のカバレッジは文の割合だけで、分岐の割合を標準では測れない。go-test-coverage で、割合の下限を検査できる
  - 変異テストは gremlins v0.6.0 がある。`--diff` で、指定した git の参照から変えた箇所だけを書き換えて調べられる。`--threshold-efficacy` を下回ると終了コード10で止まる。既定で書き換えるのは、条件の反転、条件の境目、算術の演算子、増減、符号の反転の5種類である
  - 脆弱性は govulncheck v1.9.0 で、呼ばれる箇所まで調べられる。公式の action は最新版を入れるので、版を固定するには `go tool` で動かす
  - Dependabot は gomod に対応し、dependency-review も gomod を読める
  - Go のモジュールの公開の時刻は、proxy.golang.org の `.info` の `Time` がコミットの時刻で、後から古い時刻にできる。index.golang.org の `Timestamp` は proxy が初めて取り込んだ時刻で、後から変えられない。ただし、index にはモジュールごとの問い合わせが無く、`since` で順に読む。72時間の分は約190回の問い合わせになる
  - Redis は go-redis v9.23.0 がクラスタと TLS に対応する。ElastiCache Serverless はクラスタの形だけで、Lua の台本のキーは同じ場所に置く必要がある
  - AWS SDK for Go v2 は、クライアントごとに接続先(`BaseEndpoint`)とパスの形(`UsePathStyle`)を指定できる
  - 認証は golang-jwt v5.3.1、go-oidc v3.21.0、golang.org/x/oauth2 v0.37.0、golang.org/x/crypto v0.58.0 がある。GitHub のログインは OIDC ではなく OAuth2 で、`/user` と `/user/emails` を読む
  - PDF は chromedp が広く使われる。chromedp/headless-shell のイメージは Debian trixie-slim の上に作られ、約161MB である。日本語のフォントは入っておらず、既定では root で動く
  - chromedp/headless-shell の `latest` は、`linux/amd64` と `linux/arm64/v8` の両方のイメージを持つ。Claude は、2026-11-08 に `docker buildx imagetools inspect chromedp/headless-shell:latest` で確かめた。そのときの索引の digest は `sha256:830fa77e0602cb42e5cb2cbd9237ba27b649ad69d5fb82b54713aac8b7ab4f29` である。本番の ECS は ARM64 で動くので、同じ土台のイメージを本番と CI の両方で使える
  - API の説明画面には、Go の公式の標準は無い。Go で最も多く使われるのは Swagger UI で、Scalar と Redoc もある
  - テストは testcontainers-go が広く使われる
  - 本番のイメージは、CGO を使わずに組み立てた実行ファイル1つで動かせる
- 設計への影響: 部品の選び方は、下の「設計で決めたこと」と design.md の「使う技術」に書いた。2026-11-08 の時点で公開から72時間たっていない版(chromedp v0.23.0、testcontainers-go v0.45.0、2026-11-06 の aws-sdk-go-v2、go-test-coverage v2.23.0)は、実装のときに72時間たっていればその版を使い、たっていなければ1つ前の版を使う

### moto と LocalStack

- 調べたきっかけ: 比べる検査で、S3、SES、Secrets Manager の代わりを何で用意するかを決めるため
- 調べたもの: `docker/localstack/Dockerfile`、moto の公式の文書(server mode、SES、S3、Secrets Manager)、moto の `moto/ses/models.py`、PyPI
- 分かったこと:
  - 開発環境の LocalStack のイメージは、起動に認証トークン(`LOCALSTACK_AUTH_TOKEN`)が要る。CI のワークフローには LocalStack の認証トークンが無い
  - moto 5.2.5(Apache-2.0)は、Secrets Manager と S3 のパスの形に対応する。しかし、SES で送ったメールを読む HTTP の口は文書に無く、Python の同じプロセスの中からしか読めない。S3 の署名付きの URL の扱いも文書に無い
  - Java 版が使う AWS の操作は、S3 の PutObject、GetObject、DeleteObject、署名付きの GetObject の URL、SES v1 の SendEmail、Secrets Manager の GetSecretValue だけである
- 設計への影響: 比べる検査は、これらの操作だけを受ける小さな AWS の代わりを、Go で自分で作る

### Flyway の検査の値

- 調べたきっかけ: 要件12の4のとおり、Go 版が表の形の履歴を引き継げるかを確かめるため
- 確かめた方法: Claude は、作業用のフォルダで、Flyway の検査の値を計算する Go の小さなプログラムを書いた。計算は、UTF-8 の BOM を取り除き、行ごとに改行を除いた文字列を CRC32(IEEE)に順に入れ、結果を符号付きの32ビットの整数にする
- 結果: V1 から V7 のすべてで、開発環境のデータベースの `flyway_schema_history` の `checksum` と一致した。V1 は 307357257、V2 は -1507682078、V3 は 1416944501、V4 は 987836944、V5 は 1592927299、V6 は 2070947832、V7 は 1678842263 である
- 設計への影響: Go 版は、`flyway_schema_history` を読み書きする小さなマイグレーションの部品を持つ

### Java 版から作った API の仕様書

- 調べたきっかけ: 要件4の3のとおり、設計を書く前に、Java 版が受け付けるすべての API を仕様書に書くため
- 作り方: Claude は、Java 版の Controller と要求と応答の型と、例外の扱いと、セキュリティの設定を読み、`backend/api/openapi.yaml`(OpenAPI 3.1)を書いた。Java 版の springdoc が出した API の一覧と、操作の組(HTTP のメソッドと経路)が一致することを確かめた。OpenAPI 3.1 の公式の JSON Schema で検査し、誤りは0件だった
- 分かったこと:
  - 操作は50個ある。内訳は、認証が13、利用者が7、経歴書が27、マスタが3である
  - エラーの応答は `{message, errors}` の形が基本で、403 だけは `errors` を持たない。401 には、本文が空のものと JSON のものの2つの形がある。ログインの 409 は `kind` を持つ
  - Java 版は、例外の扱いの最後で、405、415、2MB を超えるファイル、必須の問い合わせの値が無いとき、UUID でない子の項目の ID などを、すべて 500 で返している。これらは、利用者が目にしない動きを Go の標準の形に直す候補である(要件9の5)
  - 偽の送信を防ぐ検査(CSRF)は、ログインの検査より先に動く。そのため、ログインしていない利用者がトークンを付けずに送ると、401 でなく 403 になる
  - 要求では `isActive`、応答とバックアップでは `active` の名前を使う
  - 確かめきれなかった細部(日時の秒の下の桁の数、XSRF-TOKEN の Cookie の `Secure` の付き方、ファイルの名前を返すヘッダの形など)は、比べる検査で確かめる

## 設計で比べた案

| 案 | 中身 | 良い点 | 危うい点 | 結論 |
|---|---|---|---|---|
| Go のコードを `backend/` に置く | Java 版と同じフォルダに go.mod を置く | 削除のあとにフォルダを移す作業が要らない。本番の組み立ての文脈も同じ | `backend/**` の変更で Java 版の検査も動く | 採る。CI は、変わったファイルの種類で動かす仕事を分ける |
| Go のコードを `backend-go/` に置く | 別のフォルダに置く | 検査の分け方が単純 | 削除のあとにフォルダを移し、手順書と CI を2回書き換える | 採らない |
| 品質チェックを Java 版と同じ開発用のサービスで動かす | JDK と Go の両方を入れたイメージ | 領域の名前が1つで済む | イメージが大きくなり、Go 版の検査が Java 版の検査の時間に巻き込まれる | 採らない |
| 開発環境に Go 版のサービスを足す | `backend-go` の領域とサービスを足す | Java 版の環境に触れない | 削除のときに名前を `backend` に戻す | 採る |
| PDF の Chromium を同じイメージに入れる | Go 版のイメージに Chromium を入れる | タスク定義を Java 版と共有でき、戻しが1回の出荷で済む | イメージが大きくなる | 採る |
| PDF の Chromium を別のコンテナにする | 同じタスクに headless-shell のコンテナを足す | イメージが分かれる | タスク定義が Java 版と Go 版で変わり、戻しにタスク定義の変更が要る | 採らない |

## 設計で決めたこと

### 決めたこと: 表の形の履歴は Go の小さな部品で続ける

- きっかけ: 要件12の4のとおり、Go 版は、表の形を変えてきた履歴を引き継ぎ、続きとして変える
- 比べた案:
  1. Flyway の公式のイメージを、別のコンテナとして動かす
  2. goose などの Go の道具に移し、初回に V1〜V7 を適用済みとして記録する
  3. `flyway_schema_history` を読み書きする部品を Go で作る
- 選んだ案: 3
- 理由: 履歴を `flyway_schema_history` に残し続けることは、切り替えの間だけでなく、削除のあとも続く条件である。案1は、Java の実行環境を含む約398MB のイメージと、それを動かす本番の仕組みを足す。案2は、Go の道具が自分の表を使うので、2つの表の食い違いを防ぐ部品を結局作ることになる。案3は、検査の値の計算を確かめ済みで、記録された値の確かめと、未適用のファイルの適用と記録だけの小さな部品で済む
- 引き換えにしたもの: Flyway の細かい機能(繰り返しのマイグレーション、元に戻すマイグレーション)は作らない。今のリポジトリはそれらを使っていない
- 実装で確かめること: Java 版の Flyway が記録した行を、Go 版の部品が検査で通すこと。Go 版の部品が記録した行を、Java 版の Flyway が検査で通すこと

### 決めたこと: 必須の検査の名前を増やさない

- きっかけ: 要件3の4と、要件4の6・7のとおり、Go 版の品質チェックと比べる検査が通らない PR を止める
- 比べた案:
  1. `backend-go-test` と `backend-compat` を新しい必須の検査にする
  2. 今の必須の検査 `backend-test` を、Java 版の検査と Go 版の検査と比べる検査の結果をまとめる仕事にする
- 選んだ案: 2
- 理由: 案1は、所有者が GitHub の ruleset を変える操作を増やす。案2は、期待一覧と ruleset を変えずに、3つの検査のどれかが失敗した PR を止められる。仕事の名前 `backend-test` は言語の名前を含まないので、Java 版を削除したあとも使える

### 決めたこと: 分岐の割合の代わりに、変えた箇所の変異テストで止める

- きっかけ: 要件3の3のとおり、Go で標準的に測れない分岐の割合の代わりの守りを決める
- 比べた案:
  1. gobco で条件の割合を測る
  2. 文の割合の下限を上げる
  3. PR で変えた箇所だけに変異テストを流し、条件の書き換えを見逃す割合が決めた値を超えたら止める
- 選んだ案: 3
- 理由: 分岐の割合が守るのは、条件が成り立つ側と成り立たない側の両方をテストが通ることである。条件を反転した変異をテストが見逃すのは、片方の側の結果をテストが確かめていないときである。案3はこれを直接調べる。案1の gobco は広く使われておらず、案2は条件の両側を通ることを保証しない
- 引き換えにしたもの: gremlins は 0.x の版で、版の間で指定の名前が変わることがある。版を固定し、Dependabot の版上げの PR で検査が動くことを確かめる

### 決めたこと: 比べる検査の AWS の代わりは自分で作る

- きっかけ: 要件4の5と要件9の3のとおり、比べる検査で、保存したファイルと送ったメールを比べる
- 選んだ案: S3 の4つの操作、SES の SendEmail、Secrets Manager の GetSecretValue だけを受ける小さな HTTP のサーバを、比べる検査の一部として Go で作る
- 理由: LocalStack は CI で認証トークンが無く動かない。moto は送ったメールを HTTP で読めない。使う操作は6つだけで、署名を確かめる必要も無い

### 決めたこと: 出荷の入力の既定を、今の版を引き継ぐ形にする

- きっかけ: 要件5の2と、要件1の3・4
- 選んだ案: 出荷のワークフローに、`current`、`java`、`go` から選ぶ入力を足し、既定を `current` にする。`current` は、今のタスク定義のイメージのタグから、今の版を読む。Go 版のイメージのタグは `go-<SHA>` にする
- 理由: 既定を `java` にすると、切り替えたあとに所有者がいつもどおり出荷したとき、本番が知らないうちに Java 版に戻る。既定を `current` にすれば、所有者が明示的に選んだときだけ版が替わる。今の版を覚えておく場所を、本番のタスク定義のほかに作らずに済む

### 共通化と簡素化で決めたこと

- 共通化: 比べる検査の手順の形を1つにし、Java 版と Go 版の同じ要求の比べ方(要件4)、版をまたぐ操作の確かめ(要件13)、応答の時間の比べ方(要件9の7)の3つを、同じ筋書きのファイルから動かす
- 作るか使うか: HTTP の受け口は標準のライブラリと oapi-codegen を使う。データベースは pgx と sqlc を使う。設定の読み込みは、読む値が少ないので標準のライブラリで書く。API の説明画面は Swagger UI の公式のイメージを使い、Go 版のコードに説明画面を入れない。表の形の履歴の部品と、比べる検査の AWS の代わりは、合う既存の道具が無いので作る
- 簡素化: PDF の部品は、別のコンテナに分けず、同じイメージの中の Chromium を1つ起動したまま使う。秘密の値は、ECS のタスク定義で渡す形に変えず、Java 版と同じく起動時にアプリが読む

## 危うい点と備え

- Chromium を含むイメージの大きさと、脆弱性の検査の指摘が増えること。備えとして、Chromium の土台のイメージを Dependabot の docker の対象に入れ、container-scan で毎回調べる
- Chromium のメモリ。タスクのメモリ 2048MB の中で、PDF を同時に作る数を2に絞る。段階4の応答の時間の比べで、メモリの使い方も測る
- index.golang.org を順に読む公開の時刻の検査が、問い合わせの数で遅くなること。備えとして、72時間の分の索引を1回の検査で1度だけ読み、PR のすべての部品をまとめて照らす
- Java 版の細かい動きの見落とし。備えとして、比べる検査は、仕様書のすべての操作が筋書きに1回以上出てくることを確かめ、出てこない操作があれば失敗する
- gremlins の版が 0.x であること。備えとして、版を固定し、版を上げる PR で変異テストの結果が変わらないことを確かめる

## 参考にしたもの

- [Go のリリースの履歴](https://go.dev/doc/devel/release) — 保守の対象の版
- [oapi-codegen](https://github.com/oapi-codegen/oapi-codegen) — `std-http-server` と `strict-server`
- [sqlc](https://docs.sqlc.dev/) — pgx v5 との組み合わせ
- [golangci-lint の設定](https://golangci-lint.run/docs/configuration/) — v2 の設定と formatters
- [go-test-coverage](https://github.com/vladopajic/go-test-coverage) — カバレッジの下限の検査
- [gremlins の unleash](https://gremlins.dev/latest/usage/commands/unleash/) — `--diff` と `--threshold-efficacy`
- [govulncheck](https://pkg.go.dev/golang.org/x/vuln/cmd/govulncheck) — 呼ばれる箇所までの脆弱性の調べ
- [index.golang.org](https://index.golang.org/) — モジュールを初めて取り込んだ時刻
- [chromedp](https://github.com/chromedp/chromedp) と [headless-shell](https://github.com/chromedp/docker-headless-shell) — PDF の作り方
- [moto の SES](https://docs.getmoto.org/en/latest/docs/services/ses.html) — 送ったメールの読み方が同じプロセスに限られること
- [CodeQL の対応する言語](https://codeql.github.com/docs/codeql-overview/supported-languages-and-frameworks/) — Go の対応
