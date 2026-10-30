# タスク

- [x] 1. 上げる前の backend で、見本と比べる手順を用意する
- [x] 1.1 上げる前の JSON と Redis の値の見本を作る

  Claude は、main の写しを `git worktree` で作る。Claude は、大タスク4で変異テストの報告を上げる前と比べるときにも、この写しを使う。Claude は、main のコードと Jackson 2 で、単体テストが比べる見本を作業用のフォルダに作る。見本は、Spring Boot が作る JSON の変換器が書いた JSON の文字列、`RedisTemplate` が書いた値のバイト、2つの Redis の store が書いた値の3種類である。Claude は、見本を書く使い捨てのテストを main の写しで動かし、使い捨てのテストをコミットしない。JSON の入力には、宣言の順と名前の順が違う項目、null の項目、空の配列、`LocalDate` と `LocalDateTime`、列挙、絵文字を含める。
  - 完了の確かめ方: 作業用のフォルダに、入力ごとの見本のファイルと、その見本を書いた main のコミットの番号がある
  - 受入基準とテストの対応: この小タスクは見本を作るだけである。見本を使う受入基準は、大タスク3の単体テストで確かめる
  - _要件: 2.1, 2.3, 5.3_

- [x] 1.2 比べる手順の台本とデータを作る

  Claude は、上げる前と比べる手順を、リポジトリの外の作業用のフォルダ `compare/` に作る。Claude は、main の bootJar を組み立て、シナリオの台本、比べる職務経歴書の2つのデータ、OIDC の偽物の応答、データベースを保存した状態に戻す手順を `compare/` に置く。bootJar とは、backend を1つのファイルで起動できるようにまとめた jar のファイルである。台本のシナリオは、設計の部品の節「上げる前と比べる手順」の呼び出し方の項目をすべて持つ。Claude は、`prod` の設定で起動するための上書きも `compare/` に置く。この上書きは、秘密の値を LocalStack の Secrets Manager から読ませ、Redis に SSL を使わずにつながせる。
  - 完了の確かめ方: 上げる前の backend を、開発用のコンテナのネットワークの上で `dev` の設定と `prod` の設定の両方で起動でき、台本のシナリオが最後まで流れる
  - 受入基準とテストの対応: この小タスクは比べる手順を用意するだけである。比べる手順で確かめる受入基準は、大タスク5で確かめる
  - _要件: 9.2_
  - _対象の部品: 上げる前と比べる手順_

- [x] 1.3 上げる前の backend で台本を2回流し、比べない値を決める

  Claude は、上げる前の backend で、保存した状態から台本を2回流す。この2回を、シナリオ A1 とシナリオ A2 と呼ぶ。Claude は、A1 と A2 で違った値を、値そのものを比べない値として一覧にする。
  - 完了の確かめ方: `compare/` に A1 と A2 の結果と比べない値の一覧があり、一覧に載せた値のほかに A1 と A2 の差が無い
  - 受入基準とテストの対応: 要件2の受入基準2(上げる前どうしでも変わる値を比べる対象から外す)は、この一覧と、大タスク5の API の比べる手順で確かめる
  - _要件: 2.2_
  - _対象の部品: 上げる前と比べる手順_

- [x] 2. 部品と Gradle の版を上げ、本番のコードとテストを新しい版で組み立てる

  Claude は、部品の版を上げ、本番のコードとテストを新しい版の書き方に合わせる。小タスク2.1で Gradle を 9.8.2 にした時点では、Spring Boot 3.5.16 と spotless 7.2.1 と Flyway のプラグイン 10.22.0 が Gradle 9.8.2 で動くかを確かめていない。小タスク2.2で版を上げてから小タスク2.9を終えるまで、本番のコードとテストはコンパイルできない。そのため、Claude は、小タスク2.1から2.8では、完了条件の2つ目にある、タスクで変えたファイルを使うテストがすべて成功していることを、タスクを完了とする条件にしない。Claude は、テストの成功を、小タスク2.9のコンパイルと小タスク2.10のテストでまとめて確かめる。

- [x] 2.1 Gradle の wrapper を 9.8.2 に作り直す

  Claude は、Gradle の wrapper を、設計に書いた版と配布元のチェックサムで作り直す。
  - 完了の確かめ方: `./gradlew --version` が Gradle 9.8.2 を示し、作り直した wrapper の jar の SHA-256 が、配布元が公表した値と同じである
  - 受入基準とテストの対応: 要件1の受入基準5(Gradle を最も新しい正式版に上げる)は、`./gradlew --version` の出力で確かめる
  - _要件: 1.5, 1.11_
  - _対象の部品: Gradle wrapper_

- [x] 2.2 部品の版の一覧と組み立ての設定を書き換える

  Claude は、部品の版の一覧 `libs.versions.toml` の版と部品の名前を、設計の表のとおりに書き換える。Claude は、`build.gradle` の制約が使う版の行を、この小タスクでは消さない。制約とは、Gradle が部品を引き込むときに使う版を、`build.gradle` で指定する設定である。その行は、`jackson-bom`、`commons-lang3`、`httpclient5`、`httpcore5`、`commons-compress`、`plexus-utils` の6つである。Claude は、この6つの行を消すか残すかを、小タスク2.3で決める。Claude は、組み立ての設定 `build.gradle` で、起動の部品を Spring Boot 4 の名前に替え、Spring Boot 4 が分けた部品とテスト用の部品を足す。Claude は、`build.gradle` から、`ext` の上書きの行と `commons-logging` の除外を消す。
  - 完了の確かめ方: `./gradlew dependencies --configuration runtimeClasspath` が解決に失敗せず、Spring Boot 4.1.2、Jackson 3.1.7、JUnit 6.0.3 を示す
  - 受入基準とテストの対応: 要件1の受入基準1(Spring Boot を 4.1 系の最も新しい正式版に上げる)・3(宣言した部品が引き込む部品の版を、引き込む側の部品が決めた版に従わせる)・4(Spring Boot が版を決める部品は、Spring Boot が決めた版を使う)・5(Spring Boot が版を決めていない部品と Gradle を、最も新しい正式版に上げる)・6(別の作り手が引き継いだ部品に移らず、名前を改めた部品に移る)・10(最も新しい版では動かない部品を、動く版のうち最も新しい版に止める)は、`dependencies` と `dependencyInsight` の出力を設計の版の表と照らして確かめる。受入基準11(Java の版と、frontend と terraform の部品の版を変えない)は、`git diff --stat` に Java の版を書いたファイルと frontend と terraform のファイルが載らないことで確かめる
  - _要件: 1.1, 1.3, 1.4, 1.5, 1.6, 1.10, 1.11, 3.3, 4.3_
  - _対象の部品: libs.versions.toml, build.gradle_

- [x] 2.3 消す制約と上書きごとに、引き込まれる版に既知の脆弱性が無いことを確かめる

  Claude は、buildscript の5つの制約と、`commons-compress` と `plexus-utils` の制約を1つずつ外し、外したときに引き込まれる版に既知の脆弱性が無いかを確かめる。buildscript の制約とは、Gradle のプラグインが引き込む部品の版を決める制約である。Claude は、外したときに引き込まれる版を、`buildEnvironment`、`dependencyInsight`、`dependencies --configuration checkstyle` で読む。Claude は、既知の脆弱性がある版を引き込む制約だけを、直した版を指すように残す。Claude は、小タスク2.2が残した6つの版の行のうち、その行を使う制約を全部消した行だけを消す。Claude は、`jackson-bom` の行を残すときは、名前を `jackson2` に改める。

  Claude は、小タスク2.2で Claude が消した `ext` の上書きの9行についても、上書きした部品ごとに、消したあとに引き込まれる版を `dependencyInsight` で読む。読む範囲は、`runtimeClasspath`、`testRuntimeClasspath`、`checkstyle`、`pmd`、`spotbugs` の5つの configuration である。configuration とは、Gradle が部品を引き込む範囲ごとの名前である。Claude は、既知の脆弱性がある版が引き込まれる部品だけ、版の行と上書きを直した版で戻し、注記に脆弱性の番号と外す条件を書く。
  - 完了の確かめ方: 残した制約と戻した上書きごとに、脆弱性の番号と外す条件の注記が付いている。消した制約と消した上書きごとに、引き込まれる版と、その版に既知の脆弱性が無いことが作業用のフォルダの記録にある
  - 受入基準とテストの対応: 要件1の受入基準2と4のうち、脆弱性のある版を直した版に上げる決まりは、作業用のフォルダの記録で確かめる
  - _要件: 1.2, 1.4_
  - _対象の部品: libs.versions.toml, build.gradle_

- [x] 2.4 版の名前を書いた文書を書き換える (並行可)

  Claude は、`README.md` と `.kiro/steering/tech.md` の技術の表の、Spring Boot と JUnit の版の名前を書き換える。
  - 完了の確かめ方: 2つの文書の技術の表に、Spring Boot 4.1 と JUnit 6 と書いてあり、Spring Boot 3 と JUnit 5 の記載が残っていない
  - 受入基準とテストの対応: 要件1の受入基準1(Spring Boot を 4.1 系に上げる)は、2つの文書の記載でも確かめる
  - _要件: 1.1_
  - _対象の部品: 版の名前を書いた文書_

- [x] 2.5 JSON を読み書きする infrastructure のクラスを Jackson 3 に書き換える (並行可)

  Claude は、秘密の値の読み取り、OIDC の呼び出し、職務経歴書のバックアップの読み取り、2つの Redis の store を、Spring Boot が作る Jackson 3 の `JsonMapper` を受け取る形に書き換える。Claude は、Jackson 2 の検査例外を受け止めていた箇所を、Jackson 3 の非検査例外を受け止める形に替える。検査例外とは、受け止めるか、呼び出し元に投げると宣言しないとコンパイルが通らない例外であり、非検査例外とは、その宣言が要らない例外である。受け止めたあとの扱いは変えない。
  - 完了の確かめ方: 設計の部品の節「JSON を読み書きする infrastructure のクラス」に挙げた8つのクラスが、`com.fasterxml.jackson.databind` を import していない
  - 受入基準とテストの対応: 要件2の受入基準1(同じ要求に、上げる前と同じ状態コードと同じ中身の応答を返す)と6(ログインとログアウトの流れが上げる前と同じである)と、要件5の受入基準3(一時的な保存先の値を、上げる前と上げたあとの backend が互いに読める)と4(ログインし直さずに使い続けられる)は、小タスク2.10の今あるテストの全部と、大タスク3の store のテストで確かめる
  - _要件: 2.1, 2.6, 5.3, 5.4_
  - _対象の部品: JSON を読み書きする infrastructure のクラス_

- [x] 2.6 Redis の値の書き方の設定を Jackson 3 に書き換える (並行可)

  Claude は、`RedisConfig` の値とハッシュの値の書き方を、`JacksonJsonRedisSerializer<Object>` に Spring Boot の `JsonMapper` を渡す形に替える。Claude は、自前の `ObjectMapper` と `JavaTimeModule` の登録をやめる。キーとハッシュのキーの書き方は変えない。
  - 完了の確かめ方: `RedisConfig` が、Jackson 2 の型と `Jackson2JsonRedisSerializer` を使っていない
  - 受入基準とテストの対応: 要件5の受入基準3(一時的な保存先の値を、上げる前と上げたあとの backend が互いに読める)と4(ログインし直さずに使い続けられる)は、大タスク3の `RedisConfigTest` で確かめる
  - _要件: 5.3, 5.4_
  - _対象の部品: RedisConfig_

- [x] 2.7 OIDC の呼び出しに使う RestClient に JSON の変換器を渡す (並行可)

  Claude は、`RestClientConfig` が作る `RestClient` に、Spring Boot の `JsonMapper` を使う `JacksonJsonHttpMessageConverter` を明示して渡す。Claude は、Spring Framework 7.0.10 で非推奨でない `RestClient.Builder` のメソッドを使う。今の状態コードの扱いと、10秒の接続と読み取りの打ち切りと、フォームの送信に使う変換器は変えない。
  - 完了の確かめ方: `RestClientConfig` の `restClient` の Bean が `JsonMapper` を受け取り、その `JsonMapper` を使う変換器を `RestClient` に渡している
  - 受入基準とテストの対応: 要件2の受入基準6(ログインとログアウトの流れが上げる前と同じである)は、大タスク3の `OidcClientTest` で確かめる
  - _要件: 2.6_
  - _対象の部品: RestClientConfig_

- [x] 2.8 テストのコードを Jackson 3 に書き換える

  Claude は、Jackson 2 の `ObjectMapper` を使うテストを、`JsonMapper` を使う形に書き換える。テストが確かめる内容とアサーションとテストの数は変えない。
  - 完了の確かめ方: テストのコードのどのファイルも `com.fasterxml.jackson.databind` を import しておらず、`@Test` と `@ParameterizedTest` の数が書き換える前と同じである
  - 受入基準とテストの対応: 要件7の受入基準3(テストを消さず、確かめる内容を減らさない)は、`@Test` と `@ParameterizedTest` の数と、`git diff` でアサーションの行が消えていないことで確かめる
  - _要件: 7.3_
  - _対象の部品: テストの書き換え_

- [x] 2.9 テストの注釈の置き場所と Testcontainers 2 と ArchUnit の部品を書き換える

  Claude は、`@WebMvcTest`、`@AutoConfigureMockMvc`、`@DataRedisTest`、`RedisProperties` の import を、Spring Boot 4.1.2 の置き場所に替える。Claude は、`org.springframework.boot.test.autoconfigure` の下から import しているほかの注釈も、`@AutoConfigureTestDatabase` を含めて、すべて Spring Boot 4.1.2 の置き場所に替える。MyBatis のテスト用の部品 4.1.0 は、`@AutoConfigureTestDatabase` が入る部品 `spring-boot-jdbc-test` を引き込む。そのため、Claude は `spring-boot-jdbc-test` を足さない。新しい置き場所の注釈が、設計に挙げていない部品を足さないと使えないと分かったときは、Claude は、その部品を足さずに所有者に示す。Claude は、Testcontainers のクラスの import を、コンパイルで置き場所を確かめて Testcontainers 2 の置き場所に替える。Claude は、ArchUnit のテストのファイルを変えない。
  - 完了の確かめ方: `./gradlew compileJava compileTestJava` が通り、`@Test` と `@ParameterizedTest` の数が書き換える前と同じである
  - 受入基準とテストの対応: 要件7の受入基準3(テストを消さず、テストが確かめる内容を減らさない)は、小タスク2.8と同じく、`@Test` と `@ParameterizedTest` の数を書き換える前と比べて確かめる
  - _要件: 6.2, 7.3_
  - _対象の部品: テストの書き換え_

- [x] 2.10 Spring Boot 4 の既定の動きを、アプリの設定のファイルで上げる前に戻す

  Claude は、`application.yaml` に、Jackson 2 の既定に合わせるプロパティと、名前を改めた追跡のプロパティと、環境変数 `OTEL_*` を読まないプロパティを書く。Claude は、`application-prod.yaml` に、probes を増やさないプロパティと、`X-Forwarded-*` のヘッダを読まないプロパティを書く。probes とは、backend が動いているかを確かめるための `/actuator/health/liveness` と `/actuator/health/readiness` の URL である。Gradle 9 がテストを1つも見つけずに失敗したときは、Claude は、テストの部品が JUnit 6 の engine を見つけるように直す。Claude は、`/verify-backend` を動かし、spotless 8.10.4 の既定の Eclipse JDT 4.41 が整形を変えたファイルを、そのまま変更に入れる。この時点の品質チェックの道具は、上げる前の版のままである。
  - 完了の確かめ方: `./gradlew test` で、今あるテストと ArchUnit のテストがすべて通り、`/verify-backend` が成功する
  - 受入基準とテストの対応: 要件7の受入基準3(今あるテストがすべて通り、テストを消さず、確かめる内容を減らさない)は、`./gradlew test` の全部のテストで確かめる。要件2の受入基準4(エラーの文言)は、今の `@WebMvcTest` のテストのエラーの文言のアサーションで確かめる。要件5の受入基準1(データベースの表の形を変えない)と2(データベースの変更の履歴の表を、上げる前の backend が読める形のまま使う)は、Testcontainers のテストで Flyway が空のデータベースに今のマイグレーションを当てられることで確かめる。要件2の受入基準1(同じ要求に同じ応答を返す)・3(受け付けていた要求と断っていた要求を同じように扱う)・5(応答する URL と HTTP メソッドの組が同じである)と、要件4の受入基準1から5(ログ、動いているかの確認、追跡の記録、本番の設定での起動、止まり方)は、大タスク5の比べる手順で確かめる
  - _要件: 2.1, 2.3, 2.4, 2.5, 4.1, 4.2, 4.3, 4.4, 4.5, 5.1, 5.2, 7.3_
  - _対象の部品: アプリの設定_

- [x] 2.11 `backend/CLAUDE.md` から、消した `ext` の行を説明する文を消す (並行可)

  Claude は、`backend/CLAUDE.md` の「依存とプラグインのバージョン」の節から、`ext['junit-jupiter.version']` を `build.gradle` に残す例外を説明する段落を消す。Claude は、「テスト方針」の節から、Spring Boot を上げるときにこの行がまだ要るかを確かめる箇条を消す。Claude は、`backend/CLAUDE.md` のほかの文を変えない。
  - 完了の確かめ方: `backend/CLAUDE.md` に `junit-jupiter.version` の文字列が無く、`git diff backend/CLAUDE.md` に消した2か所のほかの変更が無い
  - 受入基準とテストの対応: 要件1の受入基準4(Spring Boot が版を決める部品は、Spring Boot が決めた版を使う)は、小タスク2.2で、`dependencies` と `dependencyInsight` の出力を設計の版の表と照らして確かめる。この小タスクでは、Claude は、受入基準4に従って小タスク2.2で `build.gradle` から消した行の説明を、`backend/CLAUDE.md` から消す
  - _要件: 1.4_
  - _対象の部品: backend/CLAUDE.md_

- [x] 3. 上げる前と同じ形で書き、上げる前の値を読めることを単体テストで確かめる

  Claude は、小タスク1.1で作った見本を、その見本を使う小タスクの中で、テストのコードの文字列か `src/test/resources` のファイルとしてテストに入れる。CI のテストは、作業用のフォルダを読めないためである。

- [x] 3.1 JSON の書き出しを上げる前に合わせる設定のクラスを作る (並行可)

  Claude は、`JsonMapperConfig` を作り、サロゲートの対を結合して書く機能を無効にする。サロゲートの対とは、絵文字のような一部の文字を表す2つの符号の組である。Claude は、最初に、`JsonMapperBuilderCustomizer` の置き場所をコンパイルで確かめる。Claude は、`JsonMapperConfigTest` で、Spring Boot が作る `JsonMapper` の書き出しと読み取りを、小タスク1.1で作った JSON の見本と比べる。
  - 完了の確かめ方: `JsonMapperConfigTest` が通り、書き出しの結果が見本と1文字も違わない
  - 受入基準とテストの対応: 要件2の受入基準1(項目の名前と並び順と値の書き方と空の項目)は、`JsonMapperConfigTest` の書き出しのテストで確かめる。要件2の受入基準3(JSON のあとの余分な文字と基本型への null の扱い)は、`JsonMapperConfigTest` の読み取りのテストで確かめる
  - _要件: 2.1, 2.3_
  - _対象の部品: JsonMapperConfig_

- [x] 3.2 OIDC の応答に知らない項目があっても読めることを確かめる (並行可)

  Claude は、`OidcClientTest` に、`RestClientConfig` が作る `RestClient` で、知らない項目を含むトークンの応答と利用者の情報の応答を読む場合を足す。Claude は、応答を偽物のサーバから返し、`RestClient` を偽物に差し替えない。
  - 完了の確かめ方: 足した場合が通り、読み取った値が応答の値と同じである
  - 受入基準とテストの対応: 要件2の受入基準6(ログインの流れ)のうち、外部のサービスの応答の読み取りは、`OidcClientTest` の知らない項目を含む応答を読む場合で確かめる
  - _要件: 2.6_
  - _対象の部品: RestClientConfig_

- [x] 3.3 2つの Redis の store が上げる前の値を読めることを確かめる

  Claude は、`RedisPendingRegistrationStoreTest` と `RedisTwoFactorAuthChallengeStoreTest` に、小タスク1.1で作った store の値の見本を Redis に置いて読む場合を足す。見本を読めないときは、Claude は、`use-jackson2-defaults` の設定では上げる前に戻らない差を探し、その差を上げる前に戻す処理を `JsonMapperConfig` に足すか、その差を所有者に示す。
  - 完了の確かめ方: 足した場合が通り、読み取った値が見本を書いたときの値と同じである
  - 受入基準とテストの対応: 要件5の受入基準3(上げる前の backend が書いた値を読める)は、2つの store のテストの見本を読む場合で確かめる
  - _要件: 5.3_
  - _依存: 3.1_

- [x] 3.4 Redis の値の書き方が上げる前と同じことを確かめる

  Claude は、`RedisConfigTest` を作り、`RedisTemplate` で JSON の文字列と絵文字を含む文字列を書いたバイトを、小タスク1.1で作った Redis の値の見本と比べる。見本と違うバイトを書いたときは、Claude は、違いの原因を `JsonMapperConfig` で直す。
  - 完了の確かめ方: `RedisConfigTest` が通り、書いたバイトが見本と同じで、見本のバイトを読むと元の文字列に戻る
  - 受入基準とテストの対応: 要件5の受入基準3(上げる前の backend も上げた backend が書いた値を読める)は、`RedisConfigTest` の書いたバイトを見本と比べるテストで確かめる
  - _要件: 5.3, 5.4_
  - _依存: 3.1_

- [x] 4. 品質チェックの道具を上げる
- [x] 4.1 品質チェックの設定と脆弱性の抑制のファイルの完成品を作る

  Claude は、作業用のフォルダに、`quality.gradle`、`google_checks.xml`、`container-scan-suppressions.json` の完成品を作る。`quality.gradle` の完成品では、Claude は、5つの道具の版だけを設計の表のとおりに替える。`google_checks.xml` の完成品では、Claude は、checkstyle 14.3.0 の配布元のファイルを土台にし、設計に挙げた7つの変更を入れ直し、配布元が外した3つの規則を残す。脆弱性の抑制のファイルの完成品では、Claude は2件の抑制を消す。Claude は、作業フォルダの中のゲートのファイルを変えない。
  - 完了の確かめ方: 3つの完成品と、規則ごとに上げる前の値と配布元の値と選んだ値を並べた表が、作業用のフォルダにある。`git status` にゲートのファイルの変更が無い
  - 受入基準とテストの対応: 要件1の受入基準7(品質チェックの道具を最も新しい正式版に上げる)・8(`google_checks.xml` を上げた版の配布元のファイルに替え、加えた変更と外された規則を残す)・9(自分で書いた設定のファイルは、書き方が変わったときだけ書き直す)は、完成品と規則の表で確かめる。要件7の受入基準1(品質チェックの基準を上げる前より緩めない)は、`quality.gradle` の完成品と上げる前の差が版の行だけであることと、規則の表で選んだ値が上げる前より緩くないことで確かめる。要件8の受入基準1(2件を見逃す設定を同じ PR の中で消す)は、抑制のファイルの完成品に2件が無いことで確かめる
  - _要件: 1.7, 1.8, 1.9, 7.1, 8.1_
  - _対象の部品: 品質チェックの設定の完成品, 脆弱性の抑制のファイル_

- [x] 4.2 新しい版の道具が出した指摘を、動きを変えずに直す

  Claude は、作業のブランチの今の中身を、`.commit_template` に従うコミットにする。Claude は、このコミットを `/ship` の前には push しない。Claude は、そのコミットから、ブランチを持たない作業のブランチの写しを `git worktree add --detach` で作る。作業のブランチは作業フォルダが使っているので、写しは同じブランチを使えないためである。Claude は、写しに完成品を置き、`spotlessApply` と `check` を動かす。Claude は、新しい版の checkstyle、spotbugs、pmd が出した指摘を、作業フォルダのコードの書き方を直して無くす。Claude は、作業フォルダでコードを直すたびに、直したコードをコミットし、写しで `git checkout --detach` でそのコミットに移ってから、`check` を動かし直す。写しに置いた完成品は、コミットに含まれないので、移ったあとも写しに残る。

  - 書き方を直すと動きが変わるおそれがある指摘は、Claude は直さずに所有者に示して止まる
  - 上げる前の規則と新しく足した規則が、同じ箇所に逆の書き方を求め、どちらにも合う書き方が無いときは、Claude は、どちらの規則も外さずに止まる。Claude は、食い違う箇所と2つの規則を所有者に示す
  - pmd 7.28.0 で ruleset の書き方が変わったときは、Claude は、小タスク4.1の完成品に `ruleset.xml` を足す
  - 完了の確かめ方: 完成品を置いた写しで `./gradlew check` が通り、作業フォルダの変更に、検査から外す設定が無い
  - 受入基準とテストの対応: 要件7の受入基準2(新しい指摘を、検査から外さずに、動きを変えない書き方の直しで無くす)は、写しでの `check` の成功と、検査から外す設定が増えていないことで確かめる。要件7の受入基準3(今あるテストがすべて通り、テストを消さず、確かめる内容を減らさない)は、`check` が動かすテストの全部で確かめる
  - _要件: 1.9, 6.2, 7.2, 7.3_

- [x] 4.3 変異テストが上げる前と同じ対象で結果を出すことを確かめる

  Claude は、完成品を置いた写しで `./gradlew pitest` を動かす。Claude は、小タスク1.1で作った main の写しでも `./gradlew pitest` を動かし、2つの報告の対象のクラスの一覧を比べる。完成品を置いた写しの `./gradlew pitest` が、JUnit Platform の launcher の版の食い違いで失敗したときだけ、Claude は、`quality.gradle` の完成品に `addJUnitPlatformLauncher = false` を足す。
  - 完了の確かめ方: 写しの `./gradlew pitest` が成功し、報告の対象のクラスの一覧が、main の写しの報告と同じである
  - 受入基準とテストの対応: 要件6の受入基準5(週に1回の変異テストが同じ対象のクラスについて結果を出す)は、2つの報告の対象のクラスの一覧を比べて確かめる
  - _要件: 6.5_

- [x] 4.4 所有者に完成品を置いてもらい、作業フォルダで品質チェックを通す

  Claude は、所有者に、作業フォルダの最上位へ移る `cd` と、完成品を置く `cp` を1つの手順にまとめて示し、置き終えたという返事を待つ。所有者が返事をしたら、Claude は、置かれたファイルが完成品と同じ中身かを `cmp` で確かめ、`/verify-backend` を動かす。
  - 完了の確かめ方: `cmp` が差を示さず、`/verify-backend` が成功する
  - 受入基準とテストの対応: 要件6の受入基準2(品質チェックのコマンドが同じコマンドで動き、同じか多い種類の検査を行う)は、`/verify-backend` の成功と、`check` が動かす検査のタスクの一覧を上げる前と比べて確かめる。要件8の受入基準1(2件を見逃す設定を同じ PR の中で消す)は、作業フォルダの抑制のファイルに2件が無いことで確かめる
  - _要件: 6.2, 8.1_

- [ ] 5. 上げる前と上げたあとの backend を比べる

  Claude は、大タスク5の比べる手順で差を見つけて設定かコードを直したときは、それまでに終えた大タスク5の比べる手順をすべて流し直す。1か所の直しが、ほかの比べた結果を変えることがあるためである。

- [ ] 5.1 API の応答とログインの流れを比べる

  Claude は、比べる手順の間だけ、`spring-boot-properties-migrator` を `runtimeOnly` で足した作業のブランチの bootJar を組み立てる。Claude は、この bootJar を `dev` の設定で起動し、名前が変わったプロパティの警告が出ないことを確かめる。Claude は、この部品を変更に入れない。Claude は、保存した状態から台本の API、URL の一覧、他のサイトからの呼び出し、ログインの流れのシナリオを流す。この回をシナリオ B と呼ぶ。Claude は、小タスク1.3で決めた比べない値を外して、A1 と B を比べる。差が見つかったときは、Claude は差の原因を直してからもう一度比べる。
  - 完了の確かめ方: `dev` の設定での起動で、名前が変わったプロパティの警告が出ない。`compare/` の比べた結果で、状態コード、応答のヘッダ、本文、URL と HTTP メソッドの組、CORS のヘッダ、Cookie の名前と属性に差が無い
  - 受入基準とテストの対応: 要件2の受入基準1(同じ要求に同じ状態コードと同じ中身の応答を返す)と2(上げる前どうしでも変わる値を比べる対象から外す)は API のシナリオで、受入基準3(受け付けていた要求と断っていた要求を同じように扱う)と4(エラーの文言が同じである)は断られる要求のシナリオで、受入基準5(応答する URL と HTTP メソッドの組が同じである)は URL の一覧のシナリオで、受入基準6(ログインとログアウトの流れと Cookie の名前と属性が同じである)はログインの流れのシナリオで、受入基準7(ほかのサイトの画面からの呼び出しを許す範囲が同じである)は他のサイトからの呼び出しのシナリオで確かめる
  - _要件: 2.1, 2.2, 2.3, 2.4, 2.5, 2.6, 2.7_
  - _対象の部品: 上げる前と比べる手順_

- [ ] 5.2 PDF と Markdown とメールを比べる

  Claude は、比べる職務経歴書の2つのデータを、2つの書体と、既定と違う文字の大きさと見出しの色で、上げる前と上げたあとの backend から出力する。Claude は、PDF をページごとの画像にして比べ、Markdown をバイトで比べる。Claude は、LocalStack の SES に届いたメールの差出人と件名と本文を比べる。
  - 完了の確かめ方: PDF のページの数が同じで、ページごとの画像の差が0画素である。Markdown のバイトと、メールの差出人と件名と本文に差が無い
  - 受入基準とテストの対応: 要件3の受入基準1(PDF が上げる前と同じ見た目になる)は PDF のシナリオで、受入基準2(Markdown が上げる前と1文字も違わない)は Markdown のシナリオで、受入基準3(メールの差出人と件名と本文が同じになる)はメールのシナリオで確かめる。要件9の受入基準2(2つの職務経歴書を両方の版で出力して比べ、結果を PR の本文に書く)は、2つのデータを両方の backend で出力して比べた結果で確かめる
  - _要件: 3.1, 3.2, 3.3, 9.2_
  - _対象の部品: 上げる前と比べる手順_

- [ ] 5.3 本番の設定での起動とログと止まり方を比べる

  Claude は、2つの bootJar を、`prod` の設定に、小タスク1.2で作った上書きを足して起動する。Claude は、`prod` の設定での起動でも、名前が変わったプロパティの警告が出ないことを確かめる。Claude は、ログの項目の道筋、動いているかの確認の応答、OTLP のポートへの通信を比べる。項目の道筋とは、`log.level` のような、入れ子をたどった項目の名前である。OTLP とは、処理の追跡の記録を外部に送るときの通信の決まりである。Claude は、環境変数 `AWS_EXECUTION_ENV=AWS_ECS_FARGATE` を付けて起動した backend に、ヘッダ `X-Forwarded-Proto: https` を付けた要求を送り、Cookie の属性と HSTS のヘッダを比べる。Claude は、時間のかかる要求の途中で `SIGTERM` を送り、止まり方を比べる。
  - 完了の確かめ方: `prod` の設定での起動で、名前が変わったプロパティの警告が出ない。ログの項目の道筋の集まりが同じで、`trace.id` と `span.id` が値を持って出る。`/actuator/health` が `{"status":"UP"}` だけを返し、`/actuator/health/liveness` が 404 を返す。4317 番と 4318 番のポートへの通信が無い。Cookie の属性と HSTS のヘッダが同じである。処理中の要求が終わってから backend が止まる
  - 受入基準とテストの対応: 要件4の受入基準1(ログの項目名と形式と、`trace.id` と `span.id` が同じである)はログのシナリオで、受入基準2(動いているかの確認の URL が、動いているかだけを返す)は動いているかの確認のシナリオで、受入基準3(処理の追跡の記録を外部に送らない)は追跡のシナリオで、受入基準4(上げる前と同じ本番の設定のまま起動する)は本番の設定のシナリオで、受入基準5(処理中の要求を終えてから止まる)は止まり方のシナリオで確かめる
  - _要件: 4.1, 4.2, 4.3, 4.4, 4.5_
  - _対象の部品: 上げる前と比べる手順_

- [ ] 5.4 保存されたデータを互いに読めることを確かめる

  Claude は、上げたあとの backend が起動したあとに、`flyway_schema_history` の中身を上げる前と比べる。Claude は、上げる前、上げたあと、上げる前の順に backend を入れ替え、同じ Cookie でログインのまま使えるか、片方が送った2段階の認証の番号をもう片方が受け付けるか、Redis の値を互いに読めるかを確かめる。
  - 完了の確かめ方: `flyway_schema_history` の中身が同じで、入れ替えのどの回でも、ログインのまま使え、2段階の認証の番号が受け付けられ、Redis の値を読める
  - 受入基準とテストの対応: 要件5の受入基準1(データベースの表の形を変えない)と2(データベースの変更の履歴の表を、上げる前の backend が読める形のまま使う)は `flyway_schema_history` の比べた結果で、受入基準3(一時的な保存先の値を、上げる前と上げたあとの backend が互いに読める)は Redis の値を互いに読むシナリオと2段階の認証の番号のシナリオで、受入基準4(ログインし直さずに使い続けられる)は同じ Cookie で使い続けるシナリオで確かめる
  - _要件: 5.1, 5.2, 5.3, 5.4_
  - _対象の部品: 上げる前と比べる手順_

- [ ] 5.5 開発用のコンテナでの起動と、本番のイメージの組み立てを確かめる

  Claude は、開発用のコンテナの中で、上げる前と同じ起動のコマンドで backend を起動する。Claude は、本番のイメージを今の `docker/backend/Dockerfile.prod` で組み立て、組み立てたイメージで backend を起動する。比べる手順で差を直すためにコードを変えたときは、Claude は `/verify-backend` を動かし直す。
  - 完了の確かめ方: 起動のコマンドが backend を起動する。組み立てたイメージのコンテナが Java 21 で backend を起動し、`/actuator/health` が `{"status":"UP"}` を返す
  - 受入基準とテストの対応: 要件6の受入基準1(開発用のコンテナで backend を起動するコマンドが、上げる前と同じコマンドのまま動く)は開発用のコンテナでの起動で、受入基準4(本番のコンテナイメージを同じ手順で組み立てられ、そのイメージが Java 21 で backend を起動する)は組み立てたイメージでの起動で確かめる
  - _要件: 6.1, 6.4_

- [ ] 6. 確かめた結果を PR の本文に載せ、CI の結果を確かめる
- [ ] 6.1 PR の本文を書く

  Claude は、`/ship` が PR を作るときに渡す本文を、作業用のフォルダに書く。Claude は、設計の部品の節「PR の本文」に挙げた項目をすべて書き、確かめた方法と結果には、大タスク5の比べた結果の要約を書く。確かめた結果が要件に届かないときは、Claude は、要件に届かない結果の扱いを決めた要件9の受入基準3のとおりに本文と所有者への報告を書き、所有者が合否を決めるまで `/ship` を動かさない。
  - 完了の確かめ方: 本文に設計の節の項目がすべてあり、版の表の版が `dependencies` と `buildEnvironment` の出力と同じである。要件に届かない結果があるときは、所有者が合否を決めた返事がある
  - 受入基準とテストの対応: 要件1の受入基準2(版を決めた日を PR の本文に書く)・10(止めた部品の版と止めた理由を PR の本文に書く)・12(版を変えた部品ごとに、上げる前と上げたあとの版を PR の本文に書く)は、本文の版を決めた日と版の表と止めた部品の欄で確かめる。要件9の受入基準1(確かめた方法と結果を PR の本文に書く)と3(要件に届かない結果の扱い)は、本文の確かめた方法と結果の欄で確かめる。要件8の受入基準3(2件のほかの脆弱性の扱い)は、2件のほかの脆弱性があったときの本文の欄で確かめる
  - _要件: 1.2, 1.10, 1.12, 8.3, 9.1, 9.3_
  - _対象の部品: PR の本文_

- [ ] 6.2 PR の CI と container-scan の結果を確かめる

  Claude は、`/ship` が PR を作ったあと、CI の backend に関わるジョブと `container-scan` の結果を読む。Claude は、`container-scan` の実行をキャンセルしない。`container-scan` が2件のほかの脆弱性を見つけたときは、Claude は、部品の版を上げて直せるかを確かめる。

  - 版を上げて直したときは、Claude は、`/verify-backend` と、大タスク5の比べる手順のうち上げた部品が関わるものを動かし直す。そのあと、Claude は `/ship` をもう一度動かし、直した変更を PR に足す
  - 版を上げても直せないときは、Claude は、直せない脆弱性の扱いを決めた要件8の受入基準3のとおりに、その脆弱性を所有者に示す
  - 完了の確かめ方: 所有者の承認を待つ検査を除いて、CI の backend に関わるジョブが成功する。`container-scan` が、2件を抑制しない設定で、2件を検出しない
  - 受入基準とテストの対応: 要件6の受入基準3(CI の backend に関わるジョブがすべて成功する)は CI のジョブの結果で、要件8の受入基準2(2件を見逃す設定を消した状態で、2件を検出しない)は `container-scan` の結果で、要件8の受入基準3(2件のほかの脆弱性の扱い)は2件のほかの脆弱性を見つけたときの扱いで確かめる
  - _要件: 6.3, 8.2, 8.3_

## 完了条件(全タスク共通)

Claude は、どのタスクでも、タスクの箇条書きの欄を書いたうえで、次の4つを満たしたときにタスクを完了とする。

1. Claude は、タスクが満たす requirements.md の受入基準(要件の番号付きの項目)ごとに、それを確かめるテストのファイル名とテスト名を「受入基準とテストの対応」の行に書く。Claude は、確かめるテストの無い受入基準を残さない。
2. タスクで変えたファイルを使うテストが、すべて成功している。`1.` や `2.` の見出しのタスクを大タスクと呼ぶ。大タスクの最後のタスクでは、加えて、その大タスクのタスクで変えた領域の verify のスキル(`/verify-frontend` `/verify-backend` `/verify-terraform`)が、すべて成功している。
3. Claude は、テストを飛ばす設定、アサーションの削除、カバレッジや lint の対象からの除外を足して、完了条件を満たしたように見せない。CI の escape-hatch の検査が、これらの追加を機械で見つける。
4. Claude は、新しく書いたテストについて、テストの対象のコードを一時的に壊してテストが失敗することを確かめてから、コードを元に戻す。

## 実装のメモ

- 1.2: compare/ の台本で、別のコンテナや背景の処理の出力を待つ箇所には、経過時間の上限(`deadline=$((SECONDS + N))`)と、相手が先に終わったかの確かめを必ず付ける。回数で数える上限は、1回の確かめにかかる時間が足されて延びる
- 1.2: bash の単一引用符の中に書く Python の文では、改行の文字に `"\n"` ではなく `chr(10)` を使う(編集の道具が本物の改行に変え、Python の文法の誤りで即座に落ちた)。`docker run --rm` は落ちたコンテナのログを残さないため、起動を確かめるときは `--rm` を外す
- 1.2: 上げる前の backend でも断られる要求(ログイン無しの参照の 401、JSON の書き出しの 406、prod の liveness と readiness の 404)は、台本の「成功するはずの一覧」に入れない
- 1.3: 比べない値の規則は、上げる前の2回で実際に値が違った場所(ファイルと、配列の番号を含む道筋)にだけ当てる。パターンに当たる場所すべてに当てると、2回で同じだった値まで上げたあとの比べで隠す。上げたあと(B)は `diff_runs.py A1 B excluded-values.json --at out/varying-A1-A2.json` で比べる
- 1.3: 値を形に置き換えるときは、要件2.1の書き方(日時の秒の小数と時差、HTTP の日付、UUID の大文字と小文字、記号の列の長さ、整数と小数)を残す。比べ方を作る前に、要件と設計が求める比べ方を全部書き出してから作る(指摘を1つずつ直して確認役と6往復した)
- 2.1: `./gradlew wrapper` は、動いている Gradle が jar を作る。版を上げるときは2回流す(1回目で設定のファイルだけが新しい版になり、2回目で新しい版の Gradle が jar と gradlew を作り直す)
- 2.2: archunit-junit6 1.5.1 は junit-platform-engine 6.1.3 を求め、junit-bom 6.1.3 を持ち込んで junit-platform-launcher だけを 6.1.3 に上げる。`build.gradle` で archunit-junit6 から junit-platform-engine を外し、JUnit の部品をすべて Spring Boot の 6.0.3 にそろえた(設計に無い変更。PR 本文に書く)。小タスク2.9・2.10で、ArchUnit のテストが JUnit 6.0.3 の上で見つかって実行されることを確かめる
- 2.2: 完了の確かめ方は「runtimeClasspath が JUnit 6.0.3 を示す」だが、JUnit はテストだけで使う部品で runtimeClasspath に入らない。JUnit 6.0.3 は testRuntimeClasspath で確かめた(食い違いとして PR 本文に書く)。小タスク2.3で constraints を決めるとき、`build.gradle` の constraints の注記に残る「testcontainers 1.21.4 経由」の古い説明も合わせて直すか消す
- 2.3: 部品の版は `./gradlew buildEnvironment dependencies` を1回流して全 configuration を読み、OSV(api.osv.dev の querybatch)に問い合わせる。台本は作業用のフォルダの `vuln-check/`(`parse_deps.py`、`osv_check.py`)にある。版を書かずに宣言した部品は `group:name -> 版` の形で出るので、名前から ` -> 版` を外して読む
- 2.3: 残したのは buildscript の commons-lang3 と checkstyle の plexus-utils の制約、戻したのは `ext['opentelemetry.version']`(1.67.0)。OpenTelemetry を上げると okhttp と okio の版も上がる(作業用のフォルダの記録にある。PR の本文の版の前後の表に書く)。大タスク4で checkstyle を上げたあと、同じ台本で checkstyle の configuration を調べ直す
- 2.6: `RedisConfig` の `redisTemplate` は Spring Boot の `JsonMapper` の Bean を受け取るようになった。`RedisClientTest` は `@DataRedisTest` で `RedisConfig` を `@Import` しており、Spring Boot 4 の `@DataRedisTest` が Jackson の自動設定を含まないと Bean が無くて組み立てに失敗する。2.9 と 2.10 でこの失敗が出たら、テストの側で Jackson の自動設定を足す
- 2.9: Spring Boot 4 の `@DataRedisTest` は Jackson の自動設定を含まない。`RedisConfig` を `@Import` するテストには `@ImportAutoConfiguration(JacksonAutoConfiguration.class)` を足す。ArchUnit のテストは JUnit 6.0.3 の上で18件見つかって実行された
- 3.4: SpotBugs は、テストのクラスでも、null しか代入しない項目を警告し(`spotbugsTest`)、`check` が落ちる。null の項目を書くテストでは、null をコンストラクタの引数で渡す
- 4.2: checkstyle 14.3.0 の TextBlockGoogleStyleFormatting は、spotless の Eclipse の整形が手で折り返した行をつなぎ直すため、どの書き方でも両立しない(`text_block_indentation` を替えても直らない)。所有者が 2026-10-30 に完成品の google_checks.xml からこの規則だけを外すと決めた。checkstyle の警告はビルドを落とさないので、上げる前の警告と比べて新しい指摘を見分ける
