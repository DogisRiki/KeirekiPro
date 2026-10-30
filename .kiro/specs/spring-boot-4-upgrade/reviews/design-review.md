## サイクル1 往復1(2026-10-29)

### 審査の範囲

範囲: 全体

### 申告

**1. Jackson 2 の互換の部品を使わず、Jackson 3 に移ってから、設定で上げる前の書き方に戻す** — design.md「全体の構成」、「JSON を読み書きする infrastructure のクラス」、research.md の Architecture Pattern Evaluation

- Issue の記載: なし(「アプリの動きは、上げる前と一切変わらない」「API は同じ応答を返す」だけ)
- 決めたこと: `com.fasterxml.jackson` のコードを `tools.jackson` に書き換える。`spring.jackson.use-jackson2-defaults: true` と `JsonMapperConfig` で、上げる前の JSON の書き方に戻す
- 他にありえた選択肢: Spring Boot 4 の Jackson 2 の互換の部品を使い、今の `ObjectMapper` の Bean とコードを残す(書き換えるファイルが少ない。非推奨で、いずれ消える)
- 外れていた場合: `use-jackson2-defaults` でも戻らない差(項目の順、日付、null、絵文字の書き方)が残ると、API の応答と Redis の値が上げる前と変わる。比べる手順と見本のテストで見つけられなければ、frontend と、上げる前の版に戻したときの Redis の読み取りが壊れる

**2. API、Redis、OIDC の JSON を、Spring Boot が作る1つの `JsonMapper` の Bean で読み書きする** — design.md「全体の構成」3つ目の箇条、「RedisConfig」、「RestClientConfig」

- Issue の記載: なし
- 決めたこと: `RedisConfig` の自前の `new ObjectMapper()` をやめ、Redis の値の書き方にも、OIDC の `RestClient` の変換器にも、Spring Boot の `JsonMapper` の Bean を渡す
- 他にありえた選択肢: Redis と OIDC には、今と同じく、Spring Boot の設定から切り離した自前の `JsonMapper` を作る。OIDC は Spring Boot が作る `RestClient.Builder` を受け取る
- 外れていた場合: あとで `spring.jackson.*` のプロパティを API のために変えると、Redis に書く値と OIDC の応答の読み取りも一緒に変わる。Redis の値は、上げる前の版と上げたあとの版が互いに読む前提(要件5の3)なので、読めなくなる変更が気づかれずに入りうる

**3. Spring Cloud AWS 4.2.0 を、互換の表が Spring Boot 4.0.x までしか書いていないまま Spring Boot 4.1.2 と組み合わせる** — design.md「libs.versions.toml」の失敗したとき、research.md「Spring Boot が版を決めない部品」

- Issue の記載: あり。「backend のほかの部品も、上げられるものはすべて最新の版に上げる」
- 決めたこと: 4.2.0 を使い、組み合わせて動くかは、組み立てとテストと比べる手順で確かめる
- 他にありえた選択肢: 互換の表に載っている組み合わせだけを使う
- 外れていた場合: S3、SES、Secrets Manager の動きが本番でだけ違うと、本番の起動(秘密の値の読み込み)かメールの送信が止まる。比べる手順は LocalStack に向けるので、本物の AWS とだけ起きる差は見つからない

**4. spotless の Eclipse の整形の版を固定せず、spotless 8.10.4 の既定(Eclipse JDT 4.41)で全ファイルを整形し直す** — design.md「品質チェックの設定の完成品」

- Issue の記載: あり。「品質チェックの道具…の版と、その設定も最新に上げる」
- 決めたこと: `eclipse()` に版を書かず、整形が変わったファイルをそのまま PR に入れる
- 他にありえた選択肢: `eclipse('4.35')` のように今の整形の版を固定し、整形の差を出さない
- 外れていた場合: 整形だけが変わったファイルが多数 PR に入り、動きを変える差分が埋もれる。人間がコードを読まないので実害は小さいが、あとで原因を調べるときに履歴を追いにくくなる

**5. 環境変数 `OTEL_*` を読まない設定(`management.opentelemetry.map-environment-variables: false`)を足す** — design.md「アプリの設定」

- Issue の記載: なし
- 決めたこと: Spring Boot 4.1 の、`OTEL_*` を設定として読む機能を止める
- 他にありえた選択肢: 何も足さない(今の本番の環境には `OTEL_*` が無い)
- 外れていた場合: 将来、所有者が環境変数だけで追跡の送り出しを始めようとしても、黙って無視される

### 指摘

| ID | レベル | 該当箇所 | 内容 | 直し方の案 |
|---|---|---|---|---|
| D1-1-1 | 中 | design.md「品質チェックの設定の完成品」の `google_checks.xml` の置き換え(入れ直す変更の4つ目と5つ目、「配布元が 14.3.0 で外した規則のうち…」の箇条) | 要件1の8は「上げる前のファイルにあった規則を、上げた版の配布元が外していたときは、その規則を替えたあとのファイルに残す」と決めている。設計は、外された RightCurly・空のブロックの RegexpSinglelineJava・MemberName を置き換え先の規則(GoogleRightCurly ほか)に替え、元の規則は「置き換え先が緩いときで、しかもクラスが 14.3.0 にあれば」だけ残すとしており、要件と食い違う。さらに、同じ節で「RightCurlySame の抑制の削除」「RightCurlyAlone の LITERAL_CATCH の削除」を入れ直すと書いているが、この2つは今のファイルの `RightCurly` のモジュール(id が RightCurlySame と RightCurlyAlone。google_checks.xml の103〜122行)の手直しである。RightCurly を GoogleRightCurly に替えると、入れ直す先が無くなる。どちらを採るかが実装者の判断に任され、検査の範囲が気づかれずに変わるおそれがある(要件7の1) | 外された3つの規則は、上げる前の設定(RightCurlySame と RightCurlyAlone の手直しを含む)のまま残し、配布元が足した置き換え先の規則は新しく足した規則として加える、と書き直す。両方を置くと検査が重なるだけで緩くはならない。置き換え先だけにしたいなら、要件1の8の例外として所有者の了承が要るので、前の段階への指摘に回す |
| D1-1-2 | 中 | design.md「上げる前と比べる手順」の呼び出し方の「起動」と「ログ」の箇条 | 比べる手順は2つの backend を `dev` で起動すると決めているが、`application-dev.yaml` は `logging.structured.format.console:` を空にして構造化ログを止めている(42〜44行)。ログの箇条はどの設定で比べるかを書いていないので、`dev` のまま比べると、上げる前も上げたあとも ECS の JSON が出ず、`trace.id` と `span.id` が「両方とも無い」ので同じ、と判定されうる。要件4の1(本番のログの項目名と形式)を確かめないまま合格になり、Spring Boot 4 で ECS の形が変わっていても見つからない | ログの比べ方を、`prod` の設定(か、`logging.structured.format.console: ecs` を当てた設定)で起動したときのログで行う、と書く。比べるのは、項目の名前だけでなく、入れ子を含む項目の道筋(たとえば `log.level` が平らな名前か入れ子か)と、`trace.id` `span.id` が値を持って出ることにする |
| D1-1-3 | 中 | design.md「build.gradle」の消すものの2つ目、「libs.versions.toml」の `[versions]` から消す行 | buildscript の `constraints` のうち `jackson-databind` だけを、「Spring Boot と Flyway のプラグインは Jackson 2 を引き込まなくなった」という前提で無条件に消している。この前提は research.md に出典が無く、`buildEnvironment` で確かめる手順も無い(ほかの4つは確かめてから消すと書いている)。前提が外れると、組み立ての環境に脆弱な Jackson 2 が入っても、本番のイメージの外なので container-scan は見ない。また、`[versions]` から `commons-lang3` `httpclient5` `httpcore5` `jackson-bom` を無条件に消す一方で、buildscript の制約は条件付きで残しうるとしており、残したときに制約が参照する版の行が無くなって組み立てが壊れる | `jackson-databind` の制約も、ほかの4つと同じく `./gradlew -q buildEnvironment` で、外したあとに引き込む版に既知の脆弱性が無いときだけ消す、と書く。制約を残すときは、参照する版の行(Jackson 2 の版は名前を `jackson2` などに改める)も `[versions]` に残す、と「libs.versions.toml」の節に書く |
| D1-1-4 | 低 | design.md「アプリの設定」の `application-prod.yaml` に足すプロパティ | probes を止める `management.endpoint.health.probes.enabled: false` を `application-prod.yaml` にだけ足すので、`dev` では `/actuator/health/liveness` と `/actuator/health/readiness` が新しく応答し、`/actuator/health` の応答に `groups` が増える。要件2の5(新しい URL に応答し始めない)は本番に限っていない。`/actuator/mappings` は `/actuator/health/**` の型が上げる前からあるので、この差を見つけない | probes の設定を `application.yaml` に置き、すべての設定で止める |
| D1-1-5 | 低 | design.md「Gradle wrapper」の呼び出し方 | `./gradlew wrapper --gradle-version 9.8.2 …` を今の Gradle 8.14.6 で1回動かすと、`gradle-wrapper.properties` は 9.8.2 になるが、`gradle-wrapper.jar` と `gradlew` は 8.14.6 の wrapper のまま作られる。Gradle の手引きは、jar とスクリプトまで新しくするにはもう1回 wrapper のタスクを動かすよう求めている。このままだと、設計が書く jar の SHA-256 の照合が外れる | 同じコマンドを、9.8.2 になった wrapper でもう1回動かしてから jar の SHA-256 を照らす、と書く |
| D1-1-6 | 低 | design.md「安全」の1つ目の箇条 | 「本番の XSRF-TOKEN の Cookie …の Secure は、今と同じく設定 `cookie.secure` で決め」とあるが、今の `SecurityConfig.csrfTokenRepository()` は `CookieCsrfTokenRepository` に Cookie の手直しを渡しておらず、XSRF-TOKEN の Secure は要求が https かどうか(`request.isSecure()`)で決まっている。`cookie.secure` で決まるのはログインの Cookie だけである。この文を読んだ実装者が、XSRF-TOKEN に `cookie.secure` を当てる手直しを足すと、本番で Secure が付き始め、要件2の6に反する | 「XSRF-TOKEN の Secure は、今と同じく要求が https かどうかで決まり、`server.forward-headers-strategy: none` によって上げる前と同じく付かない。ログインの Cookie の Secure は `cookie.secure` で決まる」と事実どおりに書く |
| D1-1-7 | 低 | design.md「版の名前を書いた文書」、「ファイルの構成」 | `ext['junit-jupiter.version']` を消すが、`backend/CLAUDE.md` は「例外が1つある。`ext['junit-jupiter.version']` は…`build.gradle` に残している」と「Spring Bootのバージョンを上げるときは、`ext['junit-jupiter.version']` がまだ必要かを確認する」を書いており、消したあとは無い行を指す。`build.gradle` の冒頭の注記の「Flyway Gradleプラグイン(10系)」も 13 系に合わなくなる | 書き換える文書に `backend/CLAUDE.md` の該当の2か所と、`build.gradle` と `libs.versions.toml` の注記を足す |
| D1-1-8 | 低 | design.md「libs.versions.toml」の `[versions]` の表(spotbugs 6.5.13 → 6.5.13) | 要件1の5は Spring Boot が版を決めない部品を最も新しい正式版に上げると決めている。spotbugs の Gradle プラグイン 6.5.13 を据え置く理由が design にも research.md にも無い(research.md は java-jwt などは「すでに最新」と書くが、このプラグインには触れていない) | 6.5.13 が線の日時より前の最新であることを research.md に書くか、新しい版に上げる |
| D1-1-9 | 低 | design.md「プロジェクトの決まりを守っているか」の backend のコードを置く層 | 「presentation は Spring Boot が作る JSON の変換器を通してだけ Jackson を使う」とあるが、presentation の DTO と `AppExceptionHandler` は `com.fasterxml.jackson.annotation` を直接 import している。注釈は Jackson 3 でも同じ置き場所なので実装は変わらないが、記載が事実と違う | 「presentation は Jackson の注釈(`com.fasterxml.jackson.annotation`)だけを使い、注釈は Jackson 3 でも置き場所が変わらない」と書く |

### 前の段階への指摘

なし

- 往復: 1回目 / 高0 中3 低6

## サイクル1 往復2(2026-10-29)

### 審査の範囲

範囲: 差分

- design.md「品質チェックの設定の完成品」の `google_checks.xml` の置き換えの全箇条(入れ直す7つ、GoogleMethodName、値を緩めた規則と新しく足した規則の扱い)と、requirements.md 要件1の8・1の9・7の1、research.md の81〜82行: D1-1-1 の直しで、外された規則の残し方と、置き換え先の規則の扱いが変わったため。入れ直す変更の4つ目と5つ目(RightCurlySame・RightCurlyAlone の手直し)の入れ直し先と、GoogleMethodName を使わない例外と、「新しく足した規則はそのまま使う」の箇条が、直した箇条と食い違わないかを見た
- design.md「上げる前と比べる手順」の「起動」「本番の設定」「ログ」の箇条と、requirements.md 要件4の1、`backend/src/main/resources/application.yaml` `application-dev.yaml` `application-prod.yaml` のログの設定: D1-1-2 の直しで、ログを `prod` で比べることにしたため。`prod` で起動するときの上書きの書き方と、`prod` で構造化ログが出ること(`application-prod.yaml` が `logging.structured` を上書きしないこと)を確かめた
- design.md「build.gradle」の消すものと、「libs.versions.toml」の `[versions]` から消す行と失敗したとき、`backend/build.gradle` の buildscript の制約、`backend/gradle/libs.versions.toml` の上書きの行: D1-1-3 の直しで、制約を消す条件と `[versions]` の行を消す条件が変わったため。制約がどの `[versions]` の行をどの名前で参照しているかを実ファイルで確かめた
- design.md「全体の構成」「処理の流れ」「JSON を読み書きする infrastructure のクラス」「build.gradle」の消すもの: 書き方の点検で、`ext` の上書きを外す理由、自前の `ObjectMapper` を作らない理由、Java 21 のコンテナとネットワークの文が別の節に移ったか消されたため。移った先に同じ中身があるかを見た
- design.md「libs.versions.toml」の箇条と requirements.md 要件1の6: openhtmltopdf を引き継いだ部品に移らないと書いた箇条が消されたため
- design.md の「要件7の2」「要件8の3」「要件9の3」「要件1の10」を言い換えた箇所(品質チェックの設定の完成品、JsonMapperConfig、脆弱性の抑制のファイル、比べる手順、PR の本文の失敗したとき)と requirements.md の該当の受入基準: 要件の番号だけの参照を中身の言い換えに替えたため。言い換えが受入基準と同じ中身かを照らした
- design.md「安全」「移行」「プロジェクトの決まりを守っているか」の言い換え: 中身が変わっていないかを見た。「安全」の1つ目の箇条は D1-1-6(記録のみ)と同じ中身のままで、出し直さない

### 申告

**1. 配布元が外した3つの規則と、その代わりに配布元が足した3つの規則の両方を置く** — design.md「品質チェックの設定の完成品」の `google_checks.xml` の置き換え

- Issue の記載: あり。「品質チェックの道具…の版と、その設定も最新に上げる」「新しい指摘を出したときは…書き方を直す」
- 決めたこと: RightCurly(RightCurlySame と RightCurlyAlone の手直しを含む)、空のブロックの RegexpSinglelineJava、MemberName を上げる前の設定のまま残し、GoogleRightCurly、WhitespaceBeforeEmptyBody、GoogleNonConstantFieldName も加える。2つの規則が同じ箇所に逆の書き方を求めるときは、どちらも外さずに止まって所有者に示す
- 他にありえた選択肢: 置き換え先の規則だけを置き、上げる前の規則を外す(要件1の8の例外として所有者の了承を得る)。または、上げる前の規則だけを残し、置き換え先の規則を加えない
- 外れていた場合: 2つの規則が重なって、今のコードに多くの新しい指摘が出ると、書き方の直しのファイルが増える。逆の書き方を求める組み合わせがあると、実装の途中で止まって所有者の判断を待つことになる

### 指摘

| ID | レベル | 該当箇所 | 内容 | 直し方の案 |
|---|---|---|---|---|
| D1-2-1 | 低 | design.md「libs.versions.toml」の `[versions]` から消す行の段落 | `jackson-bom` の行を残すときに名前を `jackson2` に改めると書いたが、`backend/build.gradle` の buildscript の制約は `libs.versions.jackson.bom.get()` でこの行を参照している(23行)。名前を改めるなら参照も `libs.versions.jackson2.get()` に替える必要があるが、design はそれを書いていない。また、`libs.versions.toml` のこの行の注記は「build.gradle の ext で参照」と書いており、制約だけが使う行として残すと注記が事実と違う。どちらも組み立てを動かせばすぐに分かり、実装には影響しない | 「名前を改めたときは、buildscript の制約の参照も新しい名前に替え、`libs.versions.toml` の注記を buildscript の制約が使う行だと書き直す」と1文足す |
| D1-2-2 | 低 | design.md「libs.versions.toml」(往復1で「openhtmltopdf は、別の作り手が引き継いだ部品に移らず、今の名前の最後の版 1.0.10 のままにする」とあった箇条が消された) | 要件1の6(別の作り手が引き継いだ部品に移らず、今の名前の最も新しい正式版にする)を design で明示していた箇条が、書き方の点検で消された。今は `[versions]` の表の openhtmltopdf 1.0.10 → 1.0.10 の行だけが要件1の6を裏付ける。表のとおりに作れば引き継いだ部品には移らないので実装は変わらないが、1.0.10 が今の名前の最後の版であり、据え置きが要件1の5(最も新しい正式版)にも合うことが design から読めなくなった | 消した箇条を戻すか、表の下に「openhtmltopdf は今の名前の最後の版 1.0.10 で、引き継いだ部品には移らない(要件1の6)」と1文足す |

### 前の段階への指摘

なし

- 往復: 2回で収束 / 未解決: 0件

## サイクル2 往復1(2026-10-29)

### 審査の範囲

範囲: 差分

- design.md「作るものと作らないもの」の `### 作るもの` の足した箇条と、`### 作らないもの` の全箇条: 足した箇条が、作らないものに挙げたもの(ワークフロー、Dockerfile、マイグレーションなど)とぶつからないかを見た。ぶつからない
- design.md「ファイルの構成」の「Claude が変えるファイル」の足した行と、「所有者が置くファイル」の一覧、`.github/CODEOWNERS`、ルートの CLAUDE.md のゲート設定ファイルの一覧: `backend/CLAUDE.md` を Claude が変えてよいか(所有者が置くファイルに当たらないか)を確かめた。`backend/CLAUDE.md` は CODEOWNERS の保護にもゲート設定ファイルの一覧にも入っておらず、Claude が変えるファイルに置いてよい
- design.md「backend/CLAUDE.md」の新しい節と、`backend/CLAUDE.md` の20〜41行(「依存とプラグインのバージョン」)と53〜63行(「テスト方針」): 節が言う「2か所」の場所と中身が実ファイルと合うかを確かめた。38〜41行の段落と62〜63行の箇条の2か所で合う
- design.md「backend/CLAUDE.md」の「ほかの文を変えない」と、`backend/CLAUDE.md` の30〜31行(flyway の箇条)、`backend/build.gradle` の1〜43行、design.md「libs.versions.toml」の185行: 消さずに残す文が上げたあとも事実と合うかを見た。flyway の版を buildscript と plugins の両方が `[versions] flyway` から参照する形は design でも変わらないので、残す文は事実と合う
- design.md「build.gradle」の消すもの(208行)と「libs.versions.toml」の失敗したとき(187行): `backend/CLAUDE.md` の2か所を消す前提である「`ext['junit-jupiter.version']` を消す」が、design の中で条件付きになっていないかを見た。208行は無条件に消すと書き、187行の残す条件は既知の脆弱性を直す版の行に限るので、JUnit の行には当たらない。前提は design の中で一貫している
- リポジトリ全体の `junit-jupiter.version` の出現(spec のフォルダを除く): 消す行を説明する文が `backend/CLAUDE.md` のほかに無いかを確かめた。出現は `backend/CLAUDE.md` の2か所と `backend/build.gradle` の56行だけで、design が足した直しで漏れは無い
- design.md「backend/CLAUDE.md」の「対応する要件: 1.4」と requirements.md 要件1の4: この直しは、Spring Boot が決めた版を使うために上書きの行を消すこと(要件1の4)から生じるので、対応の付け方は妥当と判断した

### 申告

なし

### 指摘

なし

### 前の段階への指摘

なし

- 往復: 1回で収束 / 未解決: 0件
