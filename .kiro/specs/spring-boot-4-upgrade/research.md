# 調べた結果と設計の判断

## Summary

- **Feature**: `spring-boot-4-upgrade`
- **Discovery Scope**: Complex Integration(既存の backend の土台の部品を、系統ごと入れ替える)
- **Key Findings**:
  - Spring Boot 4.1.2 の BOM は、Jackson を 3 系(`tools.jackson`)に替え、JUnit を 6 系に替え、Testcontainers を 2 系にする。今の `ext` による版の上書き(netty、tomcat、jackson-bom、junit-jupiter)は、残すと系統を下げるか組み立てを壊すので、すべて外す。
  - Spring Boot 4 は、何も設定しないと、本番で見える動きを4つ変える。JSON の書き方(項目の並び順など)、本番の動いているかの確認の応答(probes が既定で有効になる)、AWS ECS の上での前置きのヘッダの扱い(Cookie に Secure が付き、HSTS が付く)、追跡の記録の送り出しの設定の名前である。設計は、4つとも設定で上げる前の動きに戻す。
  - 品質チェックの道具の新しい版(checkstyle 14.3.0 など)と、`google_checks.xml` の置き換えは、ゲートのファイル(`backend/gradle/quality.gradle` `backend/config/`)の変更である。Claude はゲートのファイルを変えないので、所有者が置く完成品を Claude が作業用のフォルダで作って確かめる。

## Research Log

### 版を決めた日と、公開から72時間の線

- **Context**: 要件1の2は、版を決める時点で公開から72時間を過ぎた正式版のうち最も新しい版を使うと決めている。
- **Sources Consulted**: Maven Central の各部品の公開日時、Gradle の配布元、各部品のリリースノート(References を参照)
- **Findings**:
  - 版を決めた日は 2026-10-29 である。線は 2026-10-26 04:00(UTC)とした。これより前に公開された版を「72時間を過ぎた版」とした。
  - jacoco 0.8.16 は 2026-10-26 10:37(UTC)の公開で、線より後である。そのため jacoco は 0.8.15(2026-06-04)とする。
  - springdoc-openapi 3.2.0(2026-10-24 14:13 UTC)と Spring Boot 4.1.2(2026-10-22)は線より前である。
  - spring-cloud-aws 4.2.1 は線より後である。そのため 4.2.0(2026-09-29)とする。
- **Implications**: design.md の版の表は、この線で固める。実装の途中で新しい版が出ても上げ直さない。

### Spring Boot 4.1.2 の BOM が決める版

- **Context**: 要件1の4は、Spring Boot が版を決める部品を Spring Boot の版に合わせると決めている。
- **Sources Consulted**: Spring Boot 4.1.2 の `spring-boot-dependencies` の pom、Spring Boot 4.1 のリリースノート、OSV
- **Findings**:
  - Spring Boot 4.2 は M1、M2、RC1 だけで、正式版が無い。4.1 系の最新の正式版は 4.1.2 である。Java 17〜27 と Gradle 8.14 以上か 9.x に対応する。
  - BOM が決める主な版: Spring Framework 7.0.10、Spring Security 7.1.2、Spring Data 2026.0.2(spring-data-redis 4.1.2)、Jackson 3 は `tools.jackson` 3.1.7(性質の名前 `jackson-bom.version`)、Jackson 2 は 2.21.7(新しい性質の名前 `jackson-2-bom.version`)、Flyway 12.4.0、Tomcat 11.0.27、Netty 4.2.19.Final、PostgreSQL JDBC 42.7.14、Lettuce 7.5.2、Micrometer 1.17.2、Micrometer Tracing 1.7.2、OpenTelemetry 1.62.0、Log4j2 2.25.5、commons-lang3 3.20.0、httpclient5 5.6.5、httpcore5 5.4.4、Thymeleaf 3.1.5、FreeMarker 2.3.35、Lombok 1.18.48、Hibernate Validator 9.1.5、JUnit Jupiter 6.0.3、Mockito 5.23.0、Testcontainers 2.0.5(BOM が testcontainers-bom を取り込む)
  - BOM は pdfbox と commons-compress を決めない。
  - OSV で、上の版に既知の脆弱性は見つからなかった(2026-10-29 時点)。
- **Implications**: 今の `ext` の上書き(netty、postgresql、tomcat、jackson-bom、opentelemetry、log4j2、commons-lang3、httpclient5、httpcore5、junit-jupiter)は、すべて BOM の版と同じか BOM の版より古い。上書きをすべて外し、`libs.versions.toml` の対応する版の行も消す。

### Spring Boot が版を決めない部品

- **Context**: 要件1の5と6
- **Sources Consulted**: 各部品の Maven Central、互換の表(springdoc、spring-cloud-aws、mybatis-spring-boot)
- **Findings**:
  - mybatis-spring-boot-starter 4.1.0(2026-07-16)は Spring Boot 4.1 系向けで、MyBatis 3.5.19 を引き込む。
  - springdoc-openapi 3.2.0 は、互換の表で Spring Boot 4.1 に 3.1.x〜3.2.x が対応する。swagger-core が Jackson 2 を使うので、Jackson 2 と Jackson 3 の両方がクラスパスに載る。
  - spring-cloud-aws 4.2.0 の互換の表は Spring Boot 4.0.x までしか書いていない。4.1 との組み合わせは表では確かめられない。spring-cloud-commons に依存しないので、Spring Cloud の互換の検査で起動が止まることはない。
  - Testcontainers 2 は、成果物の名前を `testcontainers-junit-jupiter` `testcontainers-postgresql` `testcontainers-localstack` に改めた。PostgreSQL のコンテナのクラスは `org.testcontainers.postgresql.PostgreSQLContainer` が新しい置き場所で、古いクラスも 2.0.5 には残っている。
  - archunit 1.5.1 は JUnit 6 用の `archunit-junit6` を出している。JUnit Platform 6.1.3 に対してコンパイルされている。
  - java-jwt 4.6.2、commons-validator 1.11.0、mybatis-postgresql-typehandlers 1.0.2、io.spring.dependency-management 1.1.7 は、すでに最新である。
  - openhtmltopdf 1.0.10 は最後の版で、pdfbox 2.0.24 を引き込む。pdfbox 2.0.24 に既知の脆弱性は見つからなかった。
  - Flyway の Gradle プラグインの最新は 13.11.1(2026-10-21)である。13.11.0 は Gradle Plugin Portal に無い。プラグインと、buildscript の `flyway-database-postgresql` は同じ版にそろえる必要がある。プラグインは開発者が手で打つ `./gradlew flywayInfo` にだけ使い、アプリの起動時のマイグレーションは BOM の Flyway 12.4.0 が行う。
- **Implications**: Spring Boot が版を決めない部品は、上の最新の版にする。spring-cloud-aws 4.2.0 と Spring Boot 4.1.2 の組み合わせ、archunit-junit6 と JUnit 6.0.3 の組み合わせ、Flyway のプラグイン 13 と BOM の Flyway 12 の組み合わせは、実装で動かして確かめる。動かないときは要件1の10に従って止める。

### Gradle 9.8.2

- **Context**: 要件1の5
- **Sources Consulted**: Gradle 9.8.2 のリリースノート、Gradle 9 への移行の手引き、`https://services.gradle.org/distributions/gradle-9.8.2-bin.zip.sha256`
- **Findings**:
  - Gradle 9.8.2(2026-10-19)が最新の正式版である。配布物 `gradle-9.8.2-bin.zip` の SHA-256 は `21bd5da2de49b642904077f38c0efdc7778e92b3ed0889392dca61b97e389607`、wrapper の jar の SHA-256 は `3b8a25775a69158b5ad2b1d17a80a88dc7b40a352a73eb27d06c612a7ce68e98` である。
  - `build.gradle` と `quality.gradle` は、Gradle 9 で消えた API を使っていない。Gradle 9 は Groovy 4 を使い、テストが1つも見つからないときにテストのタスクを失敗にする(`failOnNoDiscoveredTests`)。
  - spotless 8.10.4、spotbugs のプラグイン 6.5.13、pitest のプラグイン 1.19.0 は Gradle 9 に対応する。
- **Implications**: wrapper は `./gradlew wrapper --gradle-version 9.8.2 --gradle-distribution-sha256-sum 21bd5da2de49b642904077f38c0efdc7778e92b3ed0889392dca61b97e389607` で作り直す。設定のキャッシュ(configuration cache)は有効にしない。

### 品質チェックの道具

- **Context**: 要件1の7〜9と要件7
- **Sources Consulted**: checkstyle、spotbugs、pmd、jacoco、pitest-junit5-plugin、gradle-pitest-plugin、spotless のリリースノートと issue
- **Findings**:
  - checkstyle 14.3.0(2026-09-27)。13.0 から JDK 21 が要る。
  - spotbugs 4.10.5(2026-10-12)。新しい検出器(AT_*、HSM_HIDING_METHOD、CWO、NCR、USO/USBC、IAOM)が新しい指摘を出すおそれがある。
  - pmd 7.28.0(2026-09-25)。規則 `UnitTestShouldIncludeAssert` と性質 `extraAssertMethodNames` は残っている。
  - jacoco 0.8.15(上の72時間の線による)。
  - pitest-junit5-plugin 1.2.3(2025-05-20)。JUnit 6 への対応は、配布元の issue #113 で議論中で、確かめられていない。
  - gradle-pitest-plugin 1.19.0 には、JUnit 6 で launcher の版が食い違い `NoSuchMethodError` で落ちる既知の不具合がある。回避は `pitest { addJUnitPlatformLauncher = false }` と、`testRuntimeOnly 'org.junit.platform:junit-platform-launcher'` を明示することである(直す PR #404 はマージ済みで未公開)。
  - spotless 8.10.4(2026-10-08)は、既定の Eclipse JDT の版を 4.35 から 4.41 に上げる。整形の結果が変わるおそれがある。
  - spotbugs のプラグインがクラスを名前で読み込む `com.github.spotbugs.snom.Effort` `Confidence` `SpotBugsTask` は 6.5.13 でも同じ名前である。
- **Implications**: 道具の版の変更は `quality.gradle` の変更なので、所有者が置く。pitest の回避の設定は、落ちたときだけ足す。spotless は Eclipse の版を固定せず、`spotlessApply` で整え直す。

### checkstyle の google_checks.xml

- **Context**: 要件1の8と要件7の1
- **Sources Consulted**: checkstyle 10.26.1 と 14.3.0 の `src/main/resources/google_checks.xml`
- **Findings**:
  - このリポジトリが写したあとに加えた変更: LineLength を 120 にした。Indentation の basicOffset・braceAdjustment・caseIndent を 4、arrayInitIndent を 8 にし、入れ子の SLIST のための SuppressionXpathSingleFilter を足した。RightCurlySame の抑制を外し、RightCurlyAlone から LITERAL_CATCH を外した。抑制の XPath を古い書き方にした。CustomImportOrder を注釈にして止めた。SummaryJavadoc と JavadocParagraph を注釈にして止めた。MethodName の型を、漢字・ひらがな・カタカナと大文字の書き出しを許す `^[\p{IsHan}\p{IsHiragana}\p{IsKatakana}a-zA-Z][\p{IsHan}\p{IsHiragana}\p{IsKatakana}a-zA-Z0-9]*$` にした。
  - 10.26.1 から 14.3.0 で配布元が外した規則: module-info の BeforeExecutionExclusionFileFilter、RightCurly(GoogleRightCurly に置き換え)、空のブロックを見る RegexpSinglelineJava(WhitespaceBeforeEmptyBody に置き換え)、MemberName(GoogleNonConstantFieldName に置き換え)、MethodName(GoogleMethodName に置き換え)、CustomImportOrder の tokens の性質
  - GoogleMethodName は日本語の名前を許さず、このリポジトリの MethodName の緩めと食い違う。
  - 配布元は多くの規則を足し、いくつかの値を厳しくし、いくつかの値を緩めた。
- **Implications**: 置き換えたファイルは、14.3.0 の配布元のファイルを土台にし、外された規則を残し、緩められた値は厳しいほうを残し、このリポジトリの変更を入れ直す。外された規則が 14.3.0 に無いクラスなら、同じ検査をする規則に置き換える。置き換えられないときは、その理由を PR の本文に書く。

### Spring Boot 4 で変わる既定の動き

- **Context**: 要件2、要件4、要件5
- **Sources Consulted**: Spring Boot 4.0 の移行の手引き、Spring Boot 4.1 のリリースノート、Jackson 3 の移行の手引き、jackson-databind issue #5318、Spring Framework 7 と Spring Security 7 の移行の手引き
- **Findings**:
  - Jackson 3 の既定は、項目を名前の順に並べる、JSON のあとの余分な文字を誤りにする、基本型への null を誤りにする、列挙を toString で書く、コンストラクタの見つけ方を変える(#5318)。`spring.jackson.use-jackson2-defaults: true` で Jackson 2 の既定に戻る。
  - 戻らない差が2つ残るおそれがある。1つは、引数の名前からコンストラクタを見つける機能(`DETECT_PARAMETER_NAMES`)である。もう1つは、UTF-8 で書くときに絵文字のようなサロゲートの対をそのまま書く機能(`COMBINE_UNICODE_SURROGATES_IN_UTF8`)で、Jackson 3 では既定で有効、Jackson 2 では無効(`😀` の形で書く)である。
  - Jackson 3 の注釈は `com.fasterxml.jackson.annotation` のままである。例外の `JacksonException` は非検査例外になった。`JsonNode.asText()` は `asString()` に改められた。
  - Spring Boot 4 は Jackson 2 の `ObjectMapper` の Bean を作らない(Jackson 2 の代わりの部品は非推奨)。
  - 起動の部品の名前: `spring-boot-starter-aop` は `spring-boot-starter-aspectj` に改められた(旧名は無い)。起動時のマイグレーションには `spring-boot-starter-flyway` が要る。`spring-boot-starter-web` は `-webmvc` に、`-oauth2-client` は `-security-oauth2-client` に改められた(旧名は非推奨で残る)。テスト用は技術ごとに `spring-boot-starter-webmvc-test` `-data-redis-test` `-security-test` に分かれた。FreeMarker の自動設定は `spring-boot-freemarker` に分かれ、`spring-boot-starter-freemarker` が引き込む。
  - テストの注釈の置き場所: `org.springframework.boot.webmvc.test.autoconfigure.WebMvcTest` と `AutoConfigureMockMvc`、`org.springframework.boot.data.redis.test.autoconfigure.DataRedisTest`。`RedisProperties` も置き場所が変わる。
  - 追跡: actuator は追跡の自動設定を含まなくなった。`org.springframework.boot:spring-boot-micrometer-tracing-opentelemetry` が要る。`spring-boot-starter-opentelemetry` は OTLP で数値の記録も送るので使わない。性質 `management.otlp.tracing.export.enabled` は `management.tracing.export.otlp.enabled` に改められた。送り出しの Bean は `management.opentelemetry.tracing.export.otlp.endpoint` を設定したときだけ作られる。4.1 から `management.opentelemetry.map-environment-variables` が `OTEL_*` の環境変数を読む。MDC の名前は `traceId` と `spanId` のままである。ECS の構造化ログの形は変わらない。
  - 動いているかの確認: probes が既定で有効になり、本番の応答が `{"groups":["liveness","readiness"],"status":"UP"}` に変わり、`/actuator/health/liveness` と `/actuator/health/readiness` が増える。`management.endpoint.health.probes.enabled: false` で戻る。
  - 前置きのヘッダ: 環境変数 `AWS_EXECUTION_ENV` が `AWS_ECS` で始まると、Spring Boot 4 は動く場所を AWS ECS と判定し、前置きのヘッダを読む `RemoteIpValve` を有効にする。ALB が `X-Forwarded-Proto: https` を付けるので、XSRF-TOKEN の Cookie に Secure が付き、HSTS のヘッダが付き、要求元の住所が変わる。`server.forward-headers-strategy: none` で戻る。
  - Spring Security 7: AntPath と MvcRequestMatcher が消え、文字列の型は PathPattern で解釈する。PathPattern は型の途中の `**` を許さない。このリポジトリの型は、すべて末尾の `/**` か完全一致である。
  - Spring Framework 7: `HttpHeaders` は `MultiValueMap` を実装しなくなった。`HttpHeaders.addAll(HttpHeaders)` は残る。`org.springframework.lang.NonNull` は非推奨になった(コンパイルの警告だけで、組み立ては止まらない)。
  - `RestClient.builder()` の既定の変換器は Jackson 3 を先に選び、Spring Boot の設定を使わない。Spring Framework 6 では `Jackson2ObjectMapperBuilder` の既定(知らない項目を無視する)を使っていた。
  - Redis: `Jackson2JsonRedisSerializer` は非推奨だが動く。後継は `JacksonJsonRedisSerializer` である。保存する値は、あらかじめ文字列にした JSON を JSON の文字列として書いたもので、Jackson 2 と Jackson 3 のどちらで書いても同じ形になる。
  - Spring Framework 7 は spring-jcl を外し、spring-core が commons-logging 1.3.5 に依存する。今の `build.gradle` の `exclude group: 'commons-logging'` を残すと、起動時に `LogFactory` が見つからず落ちる。
- **Implications**: design.md の「アプリの設定」と「JSON の読み書きの設定」の部品で、4つの既定の変化をすべて上げる前の動きに戻す。`DETECT_PARAMETER_NAMES` は、比べた結果に差が出たときだけ設定する。

## Architecture Pattern Evaluation

| Option | Description | Strengths | Risks / Limitations | Notes |
|--------|-------------|-----------|---------------------|-------|
| 1つの PR でまとめて上げる | Spring Boot、ほかの部品、Gradle、品質チェックの道具を1つの PR で上げる | Issue の決めた方式どおり。脆弱性の抑制を同じ PR で消せる | PR が大きい | 選んだ |
| 段階に分けて上げる | Gradle だけ、品質チェックの道具だけ、と PR を分ける | 1つずつの差が小さい | 所有者の承認が PR の数だけ要る。Spring Boot 3.5 は Gradle 9 と JUnit 6 の組み合わせで動かないものがあり、途中の段階が成り立たない | 採らない |
| Jackson 2 の代わりの部品を使う | Spring Boot 4 の Jackson 2 の代わりの部品で、今の ObjectMapper の Bean を残す | コードの書き換えが少ない | 非推奨で、次の版で消える | 採らない |
| Jackson 3 に移り、Jackson 2 の既定に戻す | `tools.jackson` に書き換え、`spring.jackson.use-jackson2-defaults: true` と書き出しの機能の設定で上げる前の形に戻す | 非推奨の部品を使わない | 書き換えるファイルが多い | 選んだ |

## Design Decisions

### Decision: 上げる前の動きを、設定で戻す

- **Context**: 要件2、要件4、要件5は、上げる前と同じ動きを求める。Spring Boot 4 は既定の動きを変える。
- **Alternatives Considered**:
  1. 新しい既定のまま、frontend と運用を新しい動きに合わせる
  2. 設定で上げる前の動きに戻す
- **Selected Approach**: 2。Jackson は `spring.jackson.use-jackson2-defaults: true` と書き出しの機能の設定、本番は probes の無効化と前置きのヘッダの無視、追跡は性質の名前の置き換えで戻す。
- **Rationale**: frontend と terraform を変えないことが範囲の決めごとである。
- **Trade-offs**: Spring Boot の新しい既定(probes)を使わない。将来 probes を使うときは別の変更で有効にする。
- **Follow-up**: 上げる前と上げたあとの backend を並べて動かして比べ、残る差を見つける。

### Decision: 上げる前と比べる手順は、使い捨てにする

- **Context**: 要件9は、上げる前と同じであることの根拠を PR の本文に書くことを求める。
- **Alternatives Considered**:
  1. 比べる手順をリポジトリに入れて、CI で毎回動かす
  2. 比べる手順をリポジトリの外の作業用のフォルダに置き、この変更の確かめにだけ使う
- **Selected Approach**: 2
- **Rationale**: 比べる相手(上げる前の backend)は、この変更のあとには無くなる。毎回動かす意味が無い。所有者は、1回だけの作業を仕組みに入れないと決めている。
- **Trade-offs**: 比べた手順は残らない。結果と方法は PR の本文に残る。
- **Follow-up**: 無し

### Decision: ゲートのファイルの変更は、所有者が置く完成品にする

- **Context**: `quality.gradle`、`backend/config/`、`.github/container-scan-suppressions.json` は、Claude が変えないファイルである。
- **Alternatives Considered**:
  1. Claude が直接変える
  2. Claude が作業用のフォルダで完成品を作って確かめ、所有者が置く
- **Selected Approach**: 2。Claude は、完成品を作業用のフォルダに置き、その完成品で品質チェックが通ることを確かめる。Claude は、所有者に、作業フォルダへ移るコマンドと `cp` のコマンドを示す。所有者が置いたあと、Claude は `cmp` で中身が同じことを確かめ、品質チェックを動かし直す。
- **Rationale**: CLAUDE.md の自律動作の境界
- **Trade-offs**: 所有者の手が1回要る。
- **Follow-up**: 無し

### 総合の観点の結果(一般化・作るか採るか・簡素化)

- 一般化: 上げる前と同じ形を保つための設定は、Jackson、probes、前置きのヘッダ、追跡の4つとも「Spring Boot 4 の既定を上げる前の値に戻す性質」である。設定のファイルにまとめて書き、コードで個別に戻すのは、性質で戻せない書き出しの機能だけにした。
- 作るか採るか: JSON の差は Spring Boot の `use-jackson2-defaults` を採り、自前で Jackson 2 の既定を並べない。Redis の値の書き方は spring-data-redis の `JacksonJsonRedisSerializer` を採る。比べる手順は、`diff`、`pdftoppm`、ImageMagick の `compare` を採り、比べる道具を自前で書かない。
- 簡素化: Spring の `NonNull` の非推奨は、警告だけで組み立てを止めないので書き換えない。PIT 本体の版はプラグインの既定に従わせ、`pitestVersion` を書かない。pitest の回避の設定は、落ちたときだけ足す。Spring Boot が名前を改めたが旧名が残る起動の部品(`-web`、`-oauth2-client`)も、要件1の6に従って新しい名前に移る。

## Risks & Mitigations

- spring-cloud-aws 4.2.0 が Spring Boot 4.1.2 で動かない — 起動と S3・SES・Secrets Manager の結合テストで確かめる。動かないときは、要件1の10に従い、動く組み合わせの最も新しい版に止め、理由を PR の本文に書く。
- archunit-junit6 1.5.1 が JUnit 6.0.3 で動かない — ArchUnit のテストを動かして確かめる。動かないときは、Spring Boot の BOM の JUnit の版を archunit-junit6 が求める 6.1.3 に上げることはしない(要件1の4)。ArchUnit を動く版に止める。
- pitest-junit5-plugin 1.2.3 が JUnit 6 で動かない — `./gradlew pitest` を動かし、週次の変異テストの対象のクラスについて結果が出るかを確かめる。出ないときは、`addJUnitPlatformLauncher = false` を足し、それでも出ないときは、所有者に示す。
- Flyway のプラグイン 13.11.1 が開発用のデータベースで `flywayInfo` を出せない — 出せないときは、プラグインと buildscript の `flyway-database-postgresql` を 12.4.0 に止める。
- 新しい版の checkstyle と spotbugs が多くの指摘を出す — 動きを変えずに書き方を直す。直すほうが動きを変えるおそれがあるときは、所有者に示す。
- Jackson 3 の書き方の差が比べる手順で見つからない — 比べる職務経歴書と API の要求に、絵文字、空の配列、null の項目、日付を含める。
- 上げたあとのイメージで、2件のほかの脆弱性が見つかる — 要件8の3に従う。版を決めた日のあとに部品の脆弱性が見つかったときは、要件1の2の後段に従う。依存の検査(dependency-review)が、イメージの外の部品の脆弱性で落ちたときも、同じく報告する。

## References

- [Spring Boot 4.0 Migration Guide](https://github.com/spring-projects/spring-boot/wiki/Spring-Boot-4.0-Migration-Guide) — 起動の部品の名前、テストの注釈、Jackson 3、追跡、probes
- [Spring Boot 4.1 Release Notes](https://github.com/spring-projects/spring-boot/wiki/Spring-Boot-4.1-Release-Notes) — 4.1 の性質の名前と `OTEL_*` の読み込み
- [Spring Boot 4.1 Dependency Versions](https://docs.spring.io/spring-boot/4.1/appendix/dependency-versions/coordinates.html) — BOM の版
- [Migrating to Jackson 3](https://github.com/FasterXML/jackson/blob/main/jackson3/MIGRATING_TO_JACKSON_3.md) — 既定の変化と名前の変化
- [jackson-databind #5318](https://github.com/FasterXML/jackson-databind/issues/5318) — コンストラクタの見つけ方
- [Upgrading to Spring Framework 7.x](https://github.com/spring-projects/spring-framework/wiki/Upgrading-to-Spring-Framework-7.x) — HttpHeaders、JSpecify、commons-logging
- [Spring Security 7 Migration](https://docs.spring.io/spring-security/reference/7.0/migration/index.html) — PathPattern への移行
- [Gradle 9 upgrading guide](https://docs.gradle.org/current/userguide/upgrading_major_version_9.html) — Gradle 9 の変化
- [Gradle 9.8.2 checksum](https://services.gradle.org/distributions/gradle-9.8.2-bin.zip.sha256) — 配布物の SHA-256
- [springdoc compatibility matrix](https://springdoc.org/#what-is-the-compatibility-matrix-of-springdoc-openapi-with-spring-boot) — springdoc と Spring Boot の対応
- [Spring Cloud AWS compatibility](https://github.com/awspring/spring-cloud-aws#compatibility-with-spring-project-versions) — Spring Cloud AWS と Spring Boot の対応
- [Testcontainers 2.0.0 release](https://github.com/testcontainers/testcontainers-java/releases/tag/2.0.0) — 成果物の名前の変化
- [pitest-junit5-plugin #113](https://github.com/pitest/pitest-junit5-plugin/issues/113) — JUnit 6 への対応
- [gradle-pitest-plugin](https://github.com/szpak/gradle-pitest-plugin) — launcher の食い違いと PR #404
- [Checkstyle release notes](https://checkstyle.org/releasenotes.html) — 規則の追加と削除
- [SpotBugs changelog](https://github.com/spotbugs/spotbugs/blob/master/CHANGELOG.md) — 新しい検出器
- [PMD release notes](https://pmd.github.io/latest/pmd_release_notes.html) — 7.28.0
- [JaCoCo change history](https://www.jacoco.org/jacoco/trunk/doc/changes.html) — 0.8.15 と 0.8.16
- [Spotless Gradle changes](https://github.com/diffplug/spotless/blob/main/plugin-gradle/CHANGES.md) — 既定の Eclipse JDT の版
- [CVE-2026-47884](https://spring.io/security/cve-2026-47884) と [CVE-2026-47890](https://spring.io/security/cve-2026-47890) — 消す抑制の2件
