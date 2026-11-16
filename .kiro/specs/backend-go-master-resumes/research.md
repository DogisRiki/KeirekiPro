# 調べたことの記録

## 試作の記録

この節は、要件6の受入基準1のとおり、設計を書く前に Claude が試しに作って確かめた方法と結果を残す。実装の小タスクで確かめた Java 版の動きは、この節の最後の「実装で確かめた Java 版の動き」に書く。設計の段階で調べたことは、この節のあとの「設計の段階の記録」に書く。

試した結果、Java 版と同じにできない動きは見つからなかった。そのため、Claude は、要件6の受入基準2のとおりに止まらず、設計を書いた。

### 確かめた環境

- Java 版: 作業のブランチ `feat/go-master-resume-operations`(95aca2b2)の backend を、開発環境の `spring` のコンテナの中で、所有者が動かしている Java 版と同じ起動の設定で、別にもう1つ動かした。足した設定は、ポート 8090、データベース `keireki_proto`、Redis の DB 7、時間帯 `TZ=Asia/Tokyo` の4つである。時間帯は、本番の ECS のタスクの設定に合わせた。所有者の開発のデータ(データベース `keireki_pro` と Redis の DB 0)には触れていない
- Go: go1.27.3(イメージ `golang:1.27-bookworm`)。部品は pgx v5.11.0 と google/uuid v1.6.0 である。Go の試作は、開発環境のネットワーク `keirekipro_my-network` の中のコンテナで動かした
- 試作のコードは作業用のフォルダに置き、リポジトリに入れていない。試作のあとで、別に動かした Java 版を止め、データベース `keireki_proto` を消し、Redis の DB 7 を空にした

### 試作のやり方

Claude は、データベース `keireki_proto` に、Java 版のマイグレーションの V1 から V7 までと、開発環境と同じマスタのデータを入れた。Claude は、試作の利用者で Java 版にログインし、マスタと経歴書の操作の要求を、Go の試作のプログラムから送った。Claude は、Java 版の答えと、Java 版がデータベースに書いた行を読み、Go の試作が同じ入力から作る値と、文字の単位で比べた。

Go の試作は1つのプログラムで、確かめる動きごとの入口(P1 から P13)を持つ。年月と日付の読み方は Jackson の読み方を、リンクの判定は Hibernate Validator 9.1.5 の `URLValidator` と `java.net.URI` の読み方を、ID の読み方は `java.util.UUID.fromString` と Spring の経路の値の読み方と Jackson の UUID の読み方を、Go で写して比べた。

所有者は、2026-11-15 に、画面が送らない書き方の値を Java 版に合わせないと決めた(requirements の要件1の受入基準1)。そのため、設計は、年月と日付と ID と本文を Go の普通の読み方(`encoding/json`、`time.Parse`、`uuid.Parse`)で読み、この試作の写した読み方を使わない。リンクの判定は、利用者が入力欄に打ち込める値なので、試作のとおり Java 版と同じ判定を写す。試作の答えの控えは、Go 版と Java 版の答えの違いを確かめるために使う(design.md の「Java 版の答えの正解のファイル(testdata)」)。

### 確かめた動きと結果の一覧

| 記号 | 動き | 結果 |
|---|---|---|
| P1 | 資格と SNS のマスタの名前の並び | 同じ(並べ方を指定せずに読めば同じ) |
| P2 | 経歴書の作成と更新の日時の保存と読み方 | 同じにできる(書く前にマイクロ秒に丸める) |
| P3 | 入力の前後の空白と、長さの数え方 | 同じ(19件) |
| P4 | リンクが https の形かの判定 | 同じにできる(57件。Hibernate Validator の読み方を写す) |
| P5 | 年月と日付の書き方の読み方 | 同じにできる(103件。Jackson の読み方を写す) |
| P6 | 技術スタックの文字列の並びの列の読み書き | 同じ(6件) |
| P7 | プロジェクトの項目と技術スタックの保存 | 同じ(1つのトランザクションで書ける) |
| P8 | 期間か取得の年月か名前が同じ項目どうしの並び | 同じにできる(UUID を符号付きの整数で比べる) |
| P9 | 経歴書と項目の ID の読み方 | 同じにできる(36件。Java の読み方を写す) |
| P10〜P12 | 要求の本文の型の違う値の読み方 | 同じにできる(Jackson の読み方を写す) |
| P13 | 退会してすでに居ない利用者の要求 | 同じにできる(写さない作成だけ Java 版は 500) |

### マスタと並び(P1、P8)

- P1: Java 版は、資格と SNS のマスタを、`ORDER BY` の無い SQL で読む。PostgreSQL は、この問い合わせの行を、表の行の置き場所の順(`ctid` の順)で返す。資格の160件と SNS の27件を `ORDER BY id` で読むと、資格の13番目と SNS の19番目で Java 版の答えと食い違った。Go の試作が Java 版と同じ `ORDER BY` の無い SQL で読むと、すべて同じ並びになった。技術スタックのマスタは、Java 版が `ORDER BY main_category, sub_category, m.id` を付けて読むので、同じ SQL で同じ並びになる
- P8: Java 版は、6つの欄のどれでも、期間か取得の年月か名前が同じ項目どうしを、`java.util.UUID.compareTo` で並べる。`compareTo` は、UUID の上位の64ビットと下位の64ビットを、それぞれ符号付きの整数として比べる。そのため、`8` から `f` で始まる UUID は、`0` から `7` で始まる UUID より前に並ぶ。文字列の順とは違う。Go の試作が同じ比べ方で並べると、6つの欄のどれでも Java 版と同じ並びになった

### 日時(P2)

- Java 版は、経歴書の作成と、経歴書と項目の変更のたびに、`LocalDateTime.now()` の値を作成と更新の日時にする。作成と変更の操作の答えは、この値をナノ秒まで出し、末尾の 0 を落とす(例 `2026-11-14T10:23:45.34123748`)
- pgjdbc は、この値をマイクロ秒に四捨五入してデータベースに書く(`.291894609` は `.291895` になる)。読み直す操作の答えは、データベースの値を出し、末尾の 0 を落とす。9件で一致した
- pgx は、マイクロ秒より細かい値を切り捨てて書く(`.1234565` は `.123456` になる)。そのため、Go 版は、書く前に `time.Round(time.Microsecond)` で丸める。pgx は、`time.Time` を、壁時計の見た目のまま `TIMESTAMP` の列に書く。Go 版は、日本の時間帯の時刻を作ってから書く
- 日付の列(`resumes.date`)は、日本の日付で書く

### 空白と長さ(P3)

- Java 版は、入力の前後の空白を取り除かずに保存する。全角の空白だけの値は、`@NotBlank` で空として断る
- Java 版は、長さを UTF-16 の単位で数える。絵文字の1文字は2と数える。認証の spec の `UTF16Len` と `IsJavaWhitespace` と同じ規則で、19件が一致した

### リンク(P4)

- Java 版は、リンクを、Hibernate Validator 9.1.5 の `@URL(protocol = "https")` で調べる。この検査は `new URI(値).toURL()` で読めるかと、プロトコルが `https` かを見る。Go の試作は、この2つの読み方を写し、57件で Java 版と同じ判定になった。Go の `net/url` の読み方とは、空白と、`%` のあとの文字と、ホストの無い値の扱いが違う

### 年月と日付(P5)

- Java 版は、年月を Jackson の `YearMonth` の読み方で、日付を `LocalDate` の読み方で読む。前後の空白を除いて読む。`[2024,1]` の並びの形を読む。日付は `T` の付いた日時と、1970年1月1日からの日数の整数も読む。`+09:00` の付いた値は 400 にする
- 読めた年月が1900年より前か2100年より後なら、Java 版は「取得年月が不正です。」か「日付が不正です。」のような文言で断る
- Go の試作は、Jackson の読み方を写した部品で、103件で Java 版と同じ答えになった
- 画面の年月の入力欄が送る `Invalid Date`: 2026-11-15 に、資格の追加の取得年月に入れて Java 版に送った。Java 版は、読めない値として 400 と `{"message":"入力エラーがあります。","errors":{}}` で答えた(正解のファイル `backend/internal/resume/testdata/jackdate.json`)。Go の `time.Parse` も書式 `2006-01` でこの文字列を読めないので、Go 版は同じ答えを返す
- 年が `0000` の日付: 2026-11-15 に、基本の情報の更新の日付に `"0000-01-15"` を入れて Java 版に送った。Java 版は、この値を読み、範囲の外の日付と同じく 400 と「日付が不正です。」で答えた(正解のファイル `backend/internal/resume/testdata/jackdate.json`)。年が `0000` の年月を読めない値として断るのは、年月の欄だけが書式 `yyyy-MM` を持つためである

### 技術スタックの列とプロジェクトの保存(P6、P7)

- P6: 技術スタックの列は `TEXT[]` である。`{a,NULL}` と、`,` `"` `\` `{` と空白を含む名前の6例で、Java 版が書いた値と読んだ値が、Go の `[]*string` と同じになった
- P7: pgx のトランザクションの中で、`projects` と `project_tech_stacks` の行を続けて書けた。2つ目の書き込みを失敗させると、どちらの行も残らなかった。Java 版の答えでは、作業の工程の `systemTest` と `maintenance` の値が入れ替わる。データベースには正しく書かれる。この入れ替わりの扱いは、この文書の「危うい点と備え」に書く

### ID(P9)

- Java 版は、経歴書の ID を、経路の値の前後の空白を除いてから `UUID.fromString` で読む。`UUID.fromString` は、区切りの `-` の間の桁が足りない値と、大文字の値を読む。google/uuid の `uuid.Parse` とは、受ける値が違う
- 経歴書の ID が読めなければ、Java 版は 404 と「対象の職務経歴書データが存在しません。」で答える
- 項目の ID が読めなければ、Java 版は 500 で答える
- 経歴書をコピーして作る要求の本文の `resumeId` は、Jackson の UUID の読み方で読む。24文字の base64 の値も読める。空の文字列は、コピーしない作成として扱う
- Go の試作は、この3つの読み方を写し、36件で Java 版と同じ ID か同じ答えになった
- 1つ目の箇条の訂正(小タスク1.1 で 2026-11-15 に控え直して分かった。正解のファイルは `backend/internal/resume/testdata/javauuid.json`): Java 版は、経歴書の ID を、経路の値の前後の空白を除かずに `UUID.fromString` で読む(`ResumeIdResolver.resolve` は `trim` を呼ばない)。そのため、前か後ろに空白か tab の付いた経歴書の ID は 404 になる。項目の ID は、Spring の型の変換が、前後の U+0020 以下の字を除いてから読む。全角の空白(U+3000)は、どちらの ID でも除かない
- 経路の値の末尾に改行(`%0A`)を付けると、Java 版は、ID を読む前に Spring Security の firewall で 401 と空の本文で答える。この動きは経歴書の操作の外にあるので、正解のファイルから除いた

### 要求の本文の型の違う値(P10〜P12)

- 文字列の欄: 数と真偽の値は、送った書き方のまま文字列にする(`1.50` は `"1.50"`)。並びとオブジェクトは 400 にし、本文は `{"message":"入力エラーがあります。","errors":{}}` である。前後の空白は残す
- 真偽の欄: 文字列は、前後の空白を除いてから、`true` `True` `TRUE` `false` `False` `FALSE` を受ける。空、空白だけ、`"null"`、`" null "` は `null` として扱い、必須の文言で断る。`tRuE` `NULL` `yes` `1` `0` `t` と、全角の空白の付いた値は 400(`errors` は空)にする。整数は、0 と -0 を偽、ほかを真にする。小数の書き方の数と、並びと、オブジェクトは読めず 400 にする
- 鍵: 大文字と小文字を区別する。知らない鍵と、職歴の `active` の鍵は無視する。同じ鍵が2つあれば、あとの値を使う
- 本文の全体: 最初の値のあとの余りは読まない。本文が並び、`null`、空、文字列なら 400(`errors` は空)にする
- 作業の工程の真偽の欄が `null` か無いと、Java 版は、その欄の文言を `["null は許可されていません"]` にして断る
- 技術スタックの並びの要素: 数と真偽の値は文字列にし、`null` は `NULL` のまま書く。並びでない値は 400 にする。答えの `techStack` の中の並びは、`null` と `[]` を書いたまま返す
- 職歴とプロジェクトの期間: 「継続中の場合、終了年月を設定できません。」と「終了年月は入力必須です。」の2つの文言を、Java 版の答えで確かめた

### 退会してすでに居ない利用者(P13)

Claude は、世代の行を持たない利用者 `00000000-0000-4000-8000-0000000d0013` を SQL で作ってログインし、経歴書と、6つの欄の項目を作った。そのあと、Claude は、SQL で、経歴書の子の表、経歴書、利用者の ID を持つほかの表、利用者の順に行を消し、ログインの状態の Cookie を残したまま26の操作を送った。Java 版の答えは次のとおりである。

- 3つのマスタ: 200 と、ログインした利用者の答えと同じ本文
- 経歴書の一覧: 200 と `{"resumes":[]}`
- コピーしない経歴書の作成: 500 と `{"message":"予期せぬエラーが発生しました。","errors":{}}`。`resumes.user_id` の外部キーの違反である
- 消えた経歴書とほかの利用者の経歴書をコピーする作成: 404 と「対象の職務経歴書データが存在しません。」
- 経歴書の取得と削除と基本の情報の更新と、6つの欄の項目の作成と更新と削除: 404 と「対象の職務経歴書データが存在しません。」

ログインの状態の検査は、世代の行が無い利用者の世代を 0 として扱うので、この要求を通す。

### 同じにできない動き

無い。P2、P4、P5、P8、P9、P10〜P12 は、Go の標準の部品のままでは Java 版と違うが、Java 版と同じ読み方と並べ方で書けば同じになると、試作で確かめた。

### 実装で確かめた Java 版の動き

この節は、要件6の受入基準1のとおり、試作のあとの実装の小タスクで Claude が確かめた Java 版の動きを残す。試作の記録と同じく、Java 版と同じにできない動きは見つからなかった。画面が送らない書き方の値は、所有者が 2026-11-15 に決めたとおり Java 版に合わせず、違いを変えた動きの一覧(`backend/compat/changed-behaviors.yaml`)に載せた。パスの `J/` は `backend/src/main/java/com/example/keirekipro/` を指す。

- 項目の経路の ID: Java 版は、項目の ID の先頭にタブを付けた値も読む。経歴書の ID では読まない。Go 版は `uuid.Parse` で読み、読めない ID として 404 で答える。変えた動きの一覧の CB-051 の java の欄と go の欄に書いた(小タスク2.2 と6.2 で確かめた。表は `backend/internal/resume/ids_test.go`)
- 経路の ID の末尾の改行: 経路の ID の末尾に改行(`%0A`)を付けた要求に、Java 版は、Spring Security の firewall が ID を読む前に 401 で答える。この動きは経歴書の操作の処理に届く前に起きるので、ID の書き方ごとの答えの正解のファイル `backend/internal/resume/testdata/ids.json` から除いた(小タスク1.1 で確かめた)。Go 版の `internal/httpapi/middleware` には、この firewall にあたる処理が無い。firewall はすべての経路の要求を調べるので、この違いは経歴書の操作だけの違いではない。そのため、この spec では変えた動きの一覧に載せず、範囲の外の違いとして PR の本文に書く
- 経歴書の名前の使えない文字: Java 版の `J/domain/model/resume/ResumeName.java` の66行は、`value.matches(".*" + INVALID_PATTERN + ".*")` で調べる。Java の `.` は改行の文字に当たらないので、名前に5つの改行の文字(`\n` `\r` U+0085 U+2028 U+2029)のどれかがあると、使えない文字を断らない。Go 版の `rules.go` は、要件2のとおり Java 版と同じ条件で断る(小タスク2.7 で確かめた)
- 経歴書の名前の重なり: Java 版の `J/usecase/resume/UpdateResumeBasicUseCase.java` の57行は、名前が変わったときだけ名前の重なりを確かめる。Go 版も同じ順にした。応答の時間を測る筋書き `perf-update-basic.yaml` は、このことを使って、毎回、経歴書の今の名前を送る(小タスク6.8 で確かめた)
- 名前の並べ方: Java 版の `J/domain/policy/resume/ResumeEntryOrderPolicy.java` の36行は `Collator.getInstance(Locale.JAPANESE)` で並べ、半角のカタカナの「ｱｲｳ」を最後に並べる。Go 版の `golang.org/x/text/collate` は「ｱｲｳ」を「Zenn」と「あいう」のあいだに並べる。この違いは、所有者が受け入れた並び順の違い(CB-001)に含まれ、CB-001 の go の欄に書き足した(小タスク6.2 で確かめた。`backend/internal/resume/order_test.go` の `goNameOrder`)
- プロジェクトの技術スタックの行: Java 版の `J/infrastructure/repository/resume/MyBatisResumeRepository.java` の95〜98行は、経歴書の保存のたびにプロジェクトの行を消して書き直し、`J/infrastructure/repository/resume/ResumeMapper.xml` の `insertProject`(275行から)が、317行の INSERT で技術スタックの行も書く。そのため、技術スタックの行が無いプロジェクトを直すと、Java 版は技術スタックの行を作る。Go 版の `updateProject` は、技術スタックの行が無いと技術スタックの変更を捨てる。どちらの版もプロジェクトを作るときに技術スタックの行を書くので、行が無いことは手で直したデータでしか起きない(小タスク3.1 で確かめた)
- U+0000 を含む値: 本文の文字列の欄に `\u0000` を書いた要求に、Java 版は 500 で答える(この文書の「危うい点と備え」)。Go 版も、PostgreSQL が書き込みを断るので 500 で答える。同じ動きなので、変えた動きの一覧には載せない(小タスク3.1 の `store_integration_test.go` の `TestStore_NullCharacter`)
- overlong の `c0 80`: 文字列の欄に入れた本文に、Java 版は 500 と「予期せぬエラーが発生しました。」で答える。Go 版は `encoding/json` のとおり U+FFFD に置き換えて読む。変えた動きの一覧の CB-055 の java の欄に書き足した(小タスク2.4 と6.2 で確かめた。表は `backend/internal/resume/body_test.go`)
- 作業の工程の `systemTest` と `maintenance`: 版をまたぐ筋書き `cross-resume.yaml` で、Java 版で保存した値を Go 版で読んだときも、Go 版で保存した値を Java 版で読んだときも、答えでこの2つの値が入れ替わることを確かめた。データベースには送った値のとおりに書かれる(小タスク6.7 で確かめた)

## 設計の段階の記録

- 調べ方: 既存の Go 版の土台と認証と利用者のまとまりを広げる設計なので、つなぐところに絞って調べた(light、Extension)。新しい外部のサービスとライブラリは使わない
- 調べたこと: Java 版の経歴書の受け口、ユースケース、`Resume` の変更の決まり、`MyBatisResumeRepository` の保存の仕方と、Go 版の `internal/httpapi` の経路の組み立てと誤りの受け口、生成したコードの本文と経路の値の読み方、Java 版と Go 版を比べる検査の比べ方と筋書きの欄である
- 分かったこと:
  - 生成したコードは、本文を `runtime.BindJSONBody` で読む。この関数は、構造体への読み込みで鍵の大文字と小文字を区別しない。Java 版の Jackson は区別するので、本文の型を `json.RawMessage` にし、`internal/resume` で Jackson と同じ規則で読む
  - 生成したコードは、項目の ID を `uuid.UUID` で読み、読めない値を `*gen.InvalidParamFormatError` にして誤りの受け口に渡す。項目の ID の型を `string` にすると、この誤りは起きず、受け口が Java 版の読み方で読める
  - `server_test.go` の2つの副テストは、項目の ID に `not-a-uuid` を入れた経路で、誤りの受け口の動きを確かめている。項目の ID の型を `string` にすると、この経路は誤りの受け口に届かない。そのため、誤りの受け口を名前の付いた関数にし、`package httpapi` のテストで直接確かめる
  - Java 版は、経歴書の保存のたびに、`resumes` の行を `ON CONFLICT (id) DO UPDATE` で書き、6つの欄の行を経歴書ごとにすべて消してから書き直す
  - Java 版と Go 版を比べる検査は、日時を、秒の小数を除いた形(`<datetime:形>`)で比べる。経歴書の作成と更新の日時は、要件4の受入基準3のとおり、2つの版がそれぞれ保存した日時の差も確かめる必要があるので、比べ方を足す
  - 比べる検査の環境の Java 版は、時間帯を持たずに動く(`versions.go` の `JavaEnv`)

## 設計で比べた案

- 要求の本文の読み方:
  - 選んだ案: 仕様書の要求の本文の8つの型を `x-go-type: json.RawMessage` にし、`internal/resume` が `encoding/json` の `Decoder` の `Token` で鍵と値を1つずつ読む
  - 選ばなかった案1: 生成した構造体で読む。鍵の大文字と小文字を区別しないことと、数と真偽を文字列の欄に入れられないことが、試作の P10〜P12 の Java 版の答えと違う
  - 選ばなかった案2: `map[string]json.RawMessage` に読んでから欄ごとに読む。同じ鍵の2つ目で前の値が上書きされる点は Java 版と同じだが、鍵の大文字と小文字を区別したまま知らない鍵を無視する処理と、最初の値のあとの余りを読まない処理を別に書くことになり、`Token` で読む案より短くならない
- 項目の ID の読み方:
  - 選んだ案: 仕様書の6つの経路の値を `x-go-type: string` にし、受け口が Java 版の読み方で読む。読めなければ無い項目と同じ 404 にする
  - 選ばなかった案: 生成したコードの `uuid.UUID` のまま読み、誤りの受け口で 404 にする。誤りの受け口は、どの経路のどの値が誤りかを知らないので、経歴書の確かめより先に答えることになり、ほかの利用者の経歴書の項目の要求で、経歴書があるかを答えから見分けられる
- 経歴書の保存の仕方:
  - 選んだ案: 操作ごとに、変わる行だけを書く。たとえば、職歴の項目の更新では、`careers` の1行と、`resumes` の `updated_at` だけを書く
  - 選ばなかった案: Java 版と同じく、`resumes` を書いたあとに、6つの欄の行をすべて消して書き直す。データベースに残る行の中身は同じだが、1つの項目を直すたびに経歴書のすべての項目を書き直すので、書く量が項目の数に比例する。比べる検査は行の中身を比べ、行を書いた順と回数は比べないので、どちらの案でも比べる検査を通る
- 日時の比べ方:
  - 選んだ案: 経歴書の答えの `createdAt` `updatedAt` と、`resumes` の表の `created_at` `updated_at` を、`<wallclock:形:+秒>` に置き換え、秒の差を 5 秒の幅で比べる
  - 選ばなかった案: Go 版の時刻を比べる検査が決める。Go 版の作る値が Java 版の作る値と違う時刻になる誤りを、比べる検査で見つけられない

## 設計で決めたこと

- 一般化: 6つの欄の項目の作成と更新と削除は、どれも、経歴書を利用者の経歴書として読み、項目を足すか直すか消し、`resumes` の `updated_at` を新しくし、経歴書の全体を答える。Claude は、この流れを1つの関数 `editResume` にまとめ、欄ごとの違い(読む本文、検査、書く SQL)だけを欄ごとの関数に分ける
- 作るか採るか: JSON の読み方、年月と日付の読み方、リンクの判定、UUID の読み方は、Java 版の Jackson、Hibernate Validator、`java.util.UUID` と同じ答えを返すライブラリが Go に無いので、写した部品を自分で書く。所有者は、2026-11-15 に、画面が送らない書き方の値を Java 版に合わせないと決めた(requirements の要件1の受入基準1)。そのため、設計は、写すのはリンクの判定だけにした。日本語の名前の並べ方は、変えた動きの一覧の CB-001 のとおり、すでに `go.mod` にある `golang.org/x/text/collate` を使う
- 簡素化: マスタの3つの操作は、経歴書の処理と同じパッケージ `internal/resume` に置く。マスタの操作は1つの SQL を読んで並べるだけで、別のパッケージに分けると depguard の規則を足すことになるためである
- Java 版が 500 で答える要求のうち、項目の ID が読めない要求は、無い項目と同じ 404 にする。退会した利用者のコピーしない作成は、無い経歴書と同じ 404 にする
- ほかの利用者の経歴書に項目を足す要求では、Go 版は、上限の確かめより先に、経歴書が利用者のものかを確かめる
- 6つの欄の項目の作成と更新と削除のトランザクションでは、`resumes` の行を `FOR UPDATE` で読んで固定する。同じ経歴書への2つの要求が、上限と期間の重なりの確認を同時に通り、上限を超える項目か期間の重なる項目を残すことを防ぐためである
- 退会してすでに居ない利用者の筋書きは、世代の番号が 0 の利用者を `DELETE /api/users/me` で退会させ、退会の前に取り出したログインの状態の値を送って作る。比べる検査の筋書きに SQL を流す段が無いためである

## 危うい点と備え

- UTF-8 として誤ったバイトを含む本文: Go の `encoding/json` は、誤ったバイトを U+FFFD に置き換えて読む。Jackson の扱いは試作で確かめていない。Claude は、実装のはじめに、Java 版に誤ったバイトを含む本文を送って確かめる。違えば、Java 版と同じ答えにする。Java 版と同じ答えにできなければ、Claude は、要件6の受入基準2のとおりに止まり、所有者に報告する
  - 確かめた結果(小タスク1.1 で 2026-11-15 に確かめた。正解のファイルは `backend/internal/resume/testdata/utf8.json`): 誤ったバイトを、職歴の会社名の途中と末尾、プロジェクトの技術スタックの並びの要素に入れて送った。3つの欄で、答えは同じだった
  - Java 版は、本文を Jackson の UTF-8 の読み方で読み、誤ったバイトを U+FFFD に置き換えない。Go の `encoding/json` の読み方とは違う
  - 次のバイトは読めず、Java 版は 400 と `{"message":"入力エラーがあります。","errors":{}}` で答える: 字の始まりにならないバイト(`ff` `fe` と、`f8` で始まる5バイト)、続きのバイトだけ(`80` `a0 a1`)、続きのバイトが足りない字(`c3 28` `e2 28 a1` `e2 82 28` `f0 28 8c bc` と、本文の文字列の中で切れた `e3 81`)、サロゲートを3バイトで書いた字(`ed a0 80` `ed bf bf`)
  - 次のバイトは読める。Jackson は、始まりのバイトで字の長さを決め、範囲を調べずにビットをつなぐ: 2バイトと3バイトの冗長な書き方(`c0 af` と `e0 80 af` は `/`、`c1 bf` は U+007F)、4バイトの冗長な書き方(`f0 80 80 af`)、U+10FFFF より大きい値(`f4 90 80 80` から `f7 bf bf bf`)。4バイトの字は、つないだ値から 0x10000 を引いて2つの UTF-16 の字に分けるので、この2つの場合は対になっていないサロゲートを含む字になる(`f0 80 80 af` は U+FFC0 と U+DC2F、`f4 90 80 80` は U+DC00 と U+DC00、`f5 80 80 80` は U+DCC0 と U+DC00、`f7 bf bf bf` は U+DFBF と U+DFFF)
  - 対になっていないサロゲートを含む値を受けると、Java 版は 201 で答え、答えの JSON にはそのサロゲートを `\uXXXX` の書き方で書く。データベースには、そのサロゲートを `?` に置き換えて書く。そのため、作成の答えと、あとで経歴書を読んだ答えが違う。正解のファイルでは、Go の JSON の読み手が U+FFFD に変えないように、答えの中の対になっていないサロゲートを `<U+DC00>` の形の文字列に置き換えて書いた
  - `c0 80` は U+0000 になる。PostgreSQL が U+0000 を含む文字列の書き込みを断るので、Java 版は 500 と「予期せぬエラーが発生しました。」で答える
  - 比べるために送った正しい字(U+0800、U+FFFF、U+10FFFF、U+1F600)は、そのまま書いて答えた
  - Go 版で同じ答えにできるかの見込み: 同じにできる。Go の文字列は任意のバイトを持てるので、本文の読み手が Jackson の UTF-8 の読み方を写し、対になっていないサロゲートを持つ値を保てる。データベースに書く前に `?` に置き換え、答えを書くときに `\uXXXX` の書き方で書けばよい。Claude は、この読み方を、本文の読み手を作る小タスク2.4 で作る
  - 所有者は、2026-11-15 に、画面が送らない書き方の値を Java 版に合わせないと決めた(requirements の要件1の受入基準1)。そのため、設計は、この見込みを使わない。Go 版は、誤ったバイトを `encoding/json` のとおり U+FFFD に置き換えて読み、Java 版との違いを変えた動きの一覧の CB-055 に載せる
- 作業の工程の `systemTest` と `maintenance` の入れ替わり: Java 版の `ResumeInfoResponse.java` は、答えを作るときに、この2つの値を入れ替える。Go 版は、要件1の受入基準1のとおり、Java 版と同じ答えを返す。この入れ替わりは Java 版の誤りで、この spec の範囲の外である。Claude は、所有者に報告し、直すかを決めてもらう
- 比べる検査の日時の幅: 2つの版の日時の差を 5 秒の幅で比べる。比べる検査は、段ごとに Java 版、Go 版の順に送るので、差は Go 版の応答の時間ほどである。CI の機械が遅く、差が 5 秒を超えたときは、比べる検査が止まる。その場合、Claude は、幅を広げずに原因を調べる
- 比べる検査の Java 版の時間帯を `Asia/Tokyo` にすると、Java 版が書く利用者のまとまりの日時の見た目も9時間変わる。利用者のまとまりの筋書きは、日時を `<datetime:形>` で比べるので、比べる結果は変わらない

## 参考にしたもの

- 試作の記録(この文書の「試作の記録」)
- 認証の spec の設計 `.kiro/specs/backend-go-auth/design.md`
- 利用者の spec の設計 `.kiro/specs/backend-go-users/design.md`
- 置き換えの spec の設計 `.kiro/specs/backend-go-replacement/design.md`
- oapi-codegen runtime v1.8.0 の `bindjson.go` と `bindparam.go`(Go のモジュールの置き場所のソース)

## 今あるものについて確かめた文

この節は、Claude が requirements.md と design.md に書いた、今あるものについての文と、その文を書く前に開いたファイルと行を、1件1行で控える。パスの `J/` は `backend/src/main/java/com/example/keirekipro/` を指す。

- requirements.md はじめに「マスタと経歴書の操作の Go 版は、今は未実装の答えを返す」: backend/internal/httpapi/server.go 18-22行、backend/internal/httpapi/unimplemented.go 83-230行
- requirements.md 要件5「画面は、経歴書の一覧に、経歴書ごとの作成と更新の日時を見せる」: frontend/src/features/resume/components/resume-list/ResumeCard.tsx 50-57行
- requirements.md 範囲「API の仕様書に、マスタと経歴書の操作が書かれている」: backend/api/openapi.yaml 728行(基本の情報の更新)、1338行(資格のマスタ)、1372行(技術スタックのマスタ)
- requirements.md 範囲「認証のまとまりは作り終えた」: .kiro/specs/backend-go-replacement/progress.md 36行
- requirements.md 範囲「段階1で、日時を日本の時刻で保存することと、文字数の数え方などを試作しなかった」: .kiro/specs/backend-go-replacement/research.md 37-47行、174-182行
- requirements.md 範囲と要件1「ポートフォリオ、SNS、自己PR の並び順の違いを、所有者が受け入れた」: backend/compat/changed-behaviors.yaml 6-18行(CB-001)
- requirements.md 要件1「画面は、職歴の継続中を `isActive` の名前で送り、`active` の名前で受け取る」: J/presentation/resume/dto/CreateCareerRequest.java 41行、J/presentation/resume/dto/ResumeInfoResponse.java 189行
- requirements.md 要件2「1人の利用者が作れる経歴書は50件まで」: J/usecase/resume/policy/ResumeLimits.java 15行
- requirements.md 要件2「欄ごとの項目の数の上限がある」: J/usecase/resume/policy/ResumeLimits.java 20-45行
- requirements.md 要件2「経歴書の名前に使えない文字がある」: J/domain/model/resume/ResumeName.java 52行
- requirements.md 要件2「姓と名に使える文字が決まっている」: J/domain/model/resume/FullName.java 18行
- requirements.md 要件2「1人の利用者の中で経歴書の名前が重なると断る」: J/domain/service/resume/ResumeNameDuplicationCheckService.java 37-46行
- requirements.md 要件2「終了の年月が開始の年月より前の期間を断る。職歴どうしの期間の重なりを断る」: J/domain/model/resume/Period.java 60-72行、J/domain/model/resume/Resume.java 283行、339行
- requirements.md 要件2「リンクは https の形でなければならない」: J/presentation/resume/dto/CreatePortfolioRequest.java 36行
- requirements.md 要件3「Java 版は、ほかの利用者の経歴書の要求に、無い経歴書と同じ答えを返す」: J/usecase/resume/CreateCareerUseCase.java 47-52行(項目を足すほかの操作と、経歴書の取得・削除・更新の操作も同じ形)
- requirements.md 要件3「ほかの利用者の経歴書に項目を足す要求で、Java 版は、項目の数の上限を、経歴書が誰のものかより先に確かめる」: J/usecase/resume/CreateCareerUseCase.java 44-52行
- requirements.md 要件3「すでに居ない利用者の要求は、ログインの状態の検査を通る」: .kiro/specs/backend-go-auth/requirements.md 113行
- requirements.md 要件4「マスタと経歴書の操作は、メールを送らず、ログインの状態の保存先に書かない」: J/usecase/resume/ の下に Redis とメールを使う箇所が無いことを grep で確かめた
- requirements.md 要件4「Java 版は、項目の ID の形が誤った要求に 500 で答える」: J/presentation/resume/controller/UpdateCareerController.java 46行(ID を UUID の型で受ける)、J/presentation/shared/AppExceptionHandler.java 47-183行(型の食い違いを扱う箇所が無く、173-183行の 500 の答えになる)
- requirements.md 要件6「Java 版は、資格と SNS の名前の一覧を返すときに、並べ方を指定していない」: J/infrastructure/query/certification/CertificationQueryMapper.xml 8-14行、J/infrastructure/query/snsplatform/SnsPlatformQueryMapper.xml 8-14行
- requirements.md 要件6「Java 版は、経歴書の作成と更新の日時を、時差を持たない日時として作る」: J/domain/model/resume/Resume.java 4行、47-52行、139行
- requirements.md 範囲「段階1で、文字列の並びの列、1回の送信で複数の書き込みをする箇所、ID の順の並べ方、ID の読み方も試作しなかった」: .kiro/specs/backend-go-replacement/research.md 39-45行(E3、E4、E5 の2行目、F3)
- requirements.md 要件6「Java 版は、技術スタックの種類ごとに名前の並びを1つの列に入れる」: backend/src/main/resources/db/migration/V1__create_tables.sql 155-166行(TEXT[] の列)
- requirements.md 要件6「Java 版は、プロジェクトの項目と技術スタックを1回の送信で保存する」: J/infrastructure/repository/resume/ResumeMapper.xml 275-330行(insertProject の中の2つの INSERT の文)
- requirements.md 要件6「同じ期間か取得の年月か名前の項目どうしを ID の順に並べる」: J/domain/policy/resume/ResumeEntryOrderPolicy.java 45-56行、89-100行、111-122行
- requirements.md 要件5「版をまたいで確かめる検査は、前の段の答えから値を取り出し、あとの段の答えの値と比べられる」: backend/compat/harness/scenario.go 110行(capture)、190-195行(expect の values)、backend/compat/harness/steps.go 90-131行(CheckValues が期待する値の {名前} を取り出した値に置き換える)、135-137行、backend/compat/harness/cross.go 184行、backend/compat/scenarios/users/cross-update.yaml(使っている筋書き)
- requirements.md 要件5「版をまたいで確かめる検査は、筋書きを2つの向きで動かす」: backend/compat/harness/cross.go 16-26行
- requirements.md 要件5「Java 版は、本番では時間帯を日本に設定したコンテナで動く」: terraform/modules/ecs/main.tf 62-63行(TZ=Asia/Tokyo)
- requirements.md 要件4「今の比べる検査は、Java 版のコンテナに時間帯を渡していない」: backend/compat/harness/versions.go 72-92行(JavaEnv に TZ が無い)
- design.md 使う既存の仕組み「`internal/httpapi` は、`Options` に認証と利用者の受け口を持ち、`routes` で深さ1に埋め込む」: backend/internal/httpapi/server.go 30-48行(Options、AuthHandlers 45行、UserHandlers 48行)、60-110行(routes と New)
- design.md 部品「誤りの受け口は `/api/auth/` の下の問い合わせの誤りだけを 400 にし、ほかを 500 にして誤りの型をログに書く」: backend/internal/httpapi/server.go 24-27行(queryErrorAs400Prefix)、119-150行(RequestErrorHandlerFunc と ErrorHandlerFunc)
- design.md 部品「生成したコードは本文を `runtime.BindJSONBody` で読み、読めなければ 400 と決まった本文で答える」: oapi-codegen runtime v1.8.0 bindjson.go 36-45行、backend/internal/httpapi/server.go 119-121行、backend/internal/httpapi/middleware/errors.go 13-27行
- design.md 部品「生成したコードは経路の値を型が string なら誤りにしない」: oapi-codegen runtime v1.8.0 bindparam.go 95-140行、backend/internal/httpapi/gen の生成したコード 1956行
- design.md ファイルの構成「`server_test.go` の2つの副テストが、項目の ID に `not-a-uuid` を入れた経路を使う」: backend/internal/httpapi/server_test.go 29-30行、123-142行、324-342行
- design.md ファイルの構成「`server_test.go` の未実装の答えのテストは経歴書の受け口が無いときに通る」: backend/internal/httpapi/server_test.go 96行、298行
- design.md ファイルの構成「`internal/httpapi` に `package httpapi` のテストのファイルがある」: backend/internal/httpapi/ の `*_test.go` の一覧(users_test.go ほか)
- design.md 部品「仕様書の要求の本文の8つの型と、項目の ID の6つの経路の値」: backend/api/openapi.yaml 1441-1497行、1811-1890行
- design.md データの形「経歴書の答えの `createdAt` `updatedAt` は経歴書の答えと一覧の答えだけにある」: backend/api/openapi.yaml 2094-2136行
- design.md データの形「マスタの答えの形」: backend/api/openapi.yaml 2521-2549行
- design.md 部品「`main.go` は `users.New` で利用者の処理を作り、`httpapi.Options` に渡す」: backend/cmd/keirekipro/main.go 162行、184-191行
- design.md 部品「利用者の受け口の形(`UserService` のインタフェース、型の確かめ、組み立て、誤りの答え)」: backend/internal/httpapi/users.go 386行、396行、413行、418行
- design.md 部品「受け口の成功と失敗の答えは `authJSON` と `authErrorResponse` で作る」: backend/internal/httpapi/authresponses.go 48行、85-107行、109行
- design.md 部品「誤りの型 `auth.Error` の欄」: backend/internal/auth/errors.go 80-91行
- design.md 部品「`internal/auth` が公開する入力の検査の部品と誤りを作る関数」: backend/internal/auth/exported.go 27-146行(FieldErrors 27行、InTransaction 51行、ErrBusiness 101行、ErrInvalidInput 106行、ErrCredentialsNotFound 111行、NotBlank 116行、UTF16Len 121行、IsJavaWhitespace 126行)
- design.md 部品「ログインの状態の検査は世代の行が無い利用者を世代 0 として通す」: backend/internal/auth/accesstoken.go 113-123行
- design.md 部品「Go 版は Java 版の時刻を日本の時間帯で作る」: backend/internal/auth/accesstoken.go 21-23行、105行、backend/internal/users/provider.go 15行、backend/internal/platform/database/database.go 18-19行、47行
- design.md プロジェクトの決まり「depguard は機能のパッケージに `internal/platform` と `internal/auth` を許す」: backend/.golangci.yml 28-52行
- design.md ファイルの構成「sqlc の問い合わせは `db/queries` の下にある」: backend/db/queries の一覧(auth.sql、users.sql)
- design.md テストの方針「`make compat` `make compat-cross` `make compat-perf`」: backend/Makefile 127-135行
- design.md 部品「未実装の答えを前提にした比べる検査のテストが、経歴書の削除の経路を使う」: backend/compat/compat_test.go 106行、backend/compat/cross_test.go 204行、backend/compat/perf_test.go 29行
- design.md 部品「比べる検査の日時の比べ方と幅」: backend/compat/harness/compare.go 38-39行(RedisTTLTolerance)、95-106行(CompareResponse)、217-275行(compareJSON と diffJSON)、340-400行(CompareDB と rowTexts と sortedDifference)、596-620行(sameNormalized)
- design.md 部品「正規化の部品(受けた時刻、値の置き換え、日時の形)」: backend/compat/harness/normalize.go 19行、32行、43-44行、50-76行、155-161行、203-223行、253行、270-291行
- design.md 部品「比べる検査は段ごとに Java 版、Go 版の順に送り、データベースを `to_jsonb(t)::text` で読む」: backend/compat/harness/compareenv.go 160-222行、backend/compat/harness/snapshot.go 23-44行
- design.md 部品「筋書きの段の欄と、値の取り出し元」: backend/compat/harness/scenario.go 100-200行、backend/compat/harness/capture.go 20-92行
- design.md 部品「match の欄」: backend/compat/harness/match.go 30-52行
- design.md 部品「比べる検査の Java 版の環境の値」: backend/compat/harness/versions.go 66-100行
- design.md 部品「筋書きの書き方(版をまたぐ筋書きと、ログインの状態の値の取り出し)」: backend/compat/scenarios/users/cross-update.yaml 1-45行、backend/compat/scenarios/users/delete-user.yaml、backend/compat/scenarios/users/get-user-info-perf.yaml
- design.md 部品「初期のデータ」: backend/compat/fixtures/users/basic.sql、backend/compat/fixtures/resumes の一覧(empty.sql、many-pages.sql、fonts.sql、long-text.sql と2つの JSON)、backend/compat/fixtures/resumes/fonts.sql
- design.md 部品「変えた動きの一覧の最後は CB-046 で、項目の形は id、group、変えた動き、java、go、画面に影響が無い理由、match」: backend/compat/changed-behaviors.yaml 1-20行(CB-001)、118-140行(CB-011)、485-510行(CB-044〜046)
- design.md 部品「進み具合の表のマスタと経歴書の行」: .kiro/specs/backend-go-replacement/progress.md 34-40行
- design.md 部品「Java 版は経歴書を upsert し、6つの欄の行を消して書き直す」: J/infrastructure/repository/resume/MyBatisResumeRepository.java 80-130行、J/infrastructure/repository/resume/ResumeMapper.xml 107-140行
- design.md 部品「Java 版は経歴書の一覧を作成の日時の順に読む」: J/infrastructure/repository/resume/ResumeMapper.xml 73-89行、J/usecase/resume/GetResumeListUseCase.java 29行
- design.md 部品「Java 版は技術スタックのマスタを分類と ID の順に読み、小分類の名前で振り分ける」: J/infrastructure/query/techstack/TechStackQueryMapper.xml 8-23行、J/infrastructure/query/techstack/MyBatisTechStackListQuery.java 75-128行
- design.md 部品「Java 版は経歴書の作成と変更のたびに更新の日時を新しくする」: J/domain/model/resume/Resume.java 139-140行、187-660行
- design.md 部品「経歴書の答えの、姓と名を null なら書かず、空の欄を鍵ごと書かない形と、作業の工程の入れ替わり」: J/presentation/resume/dto/ResumeInfoResponse.java 30-56行、98-108行、184-236行
- design.md 部品「欄ごとの上限の値」: J/usecase/resume/policy/ResumeLimits.java 15-45行
- design.md 部品「Java 版の経歴書の受け口と処理と要求の型のクラス」: J/presentation/resume/controller と J/presentation/resume/dto と J/usecase/resume の一覧
- design.md 部品「項目が無いときの文言」: J/usecase/resume/ の Update と Delete のユースケース(7種の文言)
- design.md データの形「表の列」: backend/src/main/resources/db/migration/V1__create_tables.sql 69-341行(resumes 69行、careers 91行、projects 109行、project_tech_stacks 151行、certifications 244行、portfolios 258行、sns_platforms 276行、self_promotions 290行、4つのマスタ 304-341行)、migration の一覧(V1〜V7)
- design.md 使う既存の仕組み「depguard の機能のパッケージの規則は `internal/platform` と `internal/auth` を許し、ほかの `internal` と `cmd` を禁じる」: backend/.golangci.yml 27-56行
- design.md 設計を見直すきっかけ「認証の spec の設計は、ほかのまとまりが `internal/auth` を読まず `internal/platform/authctx` を読むと決めている」: .kiro/specs/backend-go-auth/design.md 47行
- design.md プロジェクトの決まり「`golang.org/x/text` は `go.mod` に間接の依存として v0.43.0 が入っている。使う技術の版」: backend/go.mod 3行、26行、27行、32行、170行
- design.md 処理の流れ「経歴書の作成は、上限、名前の重なり、コピー元の読み出し、コピー元が利用者のものかの確認の順で、コピーした項目に新しい ID を付ける」: J/usecase/resume/CreateResumeUseCase.java と J/usecase/resume/CopyCreateResumeUseCase.java の execute、J/presentation/resume/controller/CreateResumeController.java 50-52行
- design.md 部品「進み具合の表のまとまりの行が『作り終えた』になると、比べる検査がまとまりの操作のすべてを筋書きに求める」: backend/compat/compat_test.go 76-88行、backend/compat/harness/coverage.go 95-140行、backend/compat/harness/operations.go 18-29行、126行
- design.md 部品「`scenarios/<まとまり>/` に置いた筋書きは自動で読まれる」: backend/compat/harness/scenario.go 247-283行
- design.md ファイルの構成「sqlc の出力は `internal/platform/database/sqlcgen` で、問い合わせは `db/queries`」: backend/sqlc.yaml
- design.md 部品「本文は Jackson と同じく `<>&` を逃がさずに書き、U+2028 などの逃がし方の違いは CB-005 で受け入れてある」: backend/internal/httpapi/jdkutf8.go、backend/internal/httpapi/authresponses.go 80-135行、backend/compat/changed-behaviors.yaml 60-72行(CB-005)
- design.md 部品「成功の答えの状態の番号(作成は 201、取得と更新は 200、削除は 204)」: backend/api/openapi.yaml 615-1390行
- design.md 部品「利用者の受け口の組み立てと誤りの答え」: backend/internal/httpapi/users.go 405-440行、backend/internal/users/errors.go
- design.md 部品「`auth.Error` の欄と公開した部品」: backend/internal/auth/errors.go 78-112行、backend/internal/auth/exported.go 20-40行
- design.md 部品「退会の筋書きの形(ログインの状態の値の取り出しと、退会のあとの 401)」: backend/compat/scenarios/users/delete-user.yaml 1-120行
- design.md 部品「退会は、経歴書と6つの欄の項目と利用者の行を消し、世代の番号の行も利用者と一緒に消える。行が無ければ世代の番号を上げる問い合わせは何も変えない」: backend/internal/users/delete.go 20-70行、backend/internal/auth/accesstoken.go 100-123行
- design.md 部品「退会の答えは Cookie の accessToken と refreshToken だけを消す」: J/presentation/user/controller/DeleteUserController.java 48-49行
- design.md 部品「筋書きの要求は、書いた Cookie のヘッダと Cookie の束の Cookie をつなぎ、csrf の値を Cookie の束の XSRF-TOKEN から取る」: backend/compat/harness/send.go 150-173行
- design.md 部品「初期のデータの利用者は世代の番号の行を持つ」: backend/compat/fixtures/users/basic.sql 16行、backend/compat/fixtures/users/users-ops.sql 1-20行、43行
- design.md 部品「正規化の受けた時刻は、その版の応答を最後に受けた時刻」: backend/compat/harness/normalize.go 56-62行
- design.md 部品「Java 版の経歴書の一覧は、経歴書ごとに6つの欄の項目も読む」: J/infrastructure/repository/resume/MyBatisResumeRepository.java 37-49行
- design.md 部品「マスタの3つの受け口と問い合わせのクラス」: J/presentation/certification/controller/GetCertificationListController.java、J/presentation/snsplatform/controller/GetSnsPlatformListController.java、J/presentation/techstack/controller/GetTechStackListController.java、J/usecase/query/ の CertificationListQuery.java、SnsPlatformListQuery.java、TechStackListQuery.java
- design.md 部品「小分類の名前と答えの鍵の対応(例: framework は frameworks)」: J/infrastructure/query/techstack/MyBatisTechStackListQuery.java 75-92行
- design.md データの形「`techStack` の `tools` の鍵は8つ」: backend/api/openapi.yaml 2326-2344行
- design.md 安全「Go 版の土台は JSON の本文の大きさに上限を置いていない。上限は名前と画像の変更の本文だけ」: backend/internal/httpapi/users.go 21-25行、110-116行。backend/internal と backend/cmd に MaxBytesReader は無い
- design.md 安全「Java 版の本文の大きさの上限は multipart の要求だけ」: backend/src/main/resources/application.yaml 28-29行
- design.md 部品「生成したコードは runtime.BindJSONBody で本文を読み、要求を仕様書で検査する中間処理が無いときは json.NewDecoder の Decode で最初の値だけを読む」: backend/internal/httpapi/gen/api.gen.go 8818-8822行、oapi-codegen/runtime v1.8.0 の bindjson.go 36-45行(gh api で読んだ)、backend/go.mod 30行。backend/internal と backend/cmd に openapi3filter は無い
- design.md 部品「書き込みの操作は X-XSRF-TOKEN のヘッダを Cookie XSRF-TOKEN と合わせる。合わないと 403」: backend/api/openapi.yaml 47-54行、1400-1416行
- design.md ファイルの構成「versions_test.go の assertEnv が環境の値の数を確かめる」: backend/compat/harness/versions_test.go 48-72行
- design.md 部品「段ごとに Java 版、Go 版の順に送り、受けた時刻は版ごとに応答から取る」: backend/compat/harness/compareenv.go 165-172行、backend/compat/harness/compare.go 104-106行
- design.md 部品「比べる検査は版ごとに別のデータベースを使い、2つの版のデータベースに同じ初期のデータを入れる」: backend/compat/harness/compareenv.go 140-148行、196-200行
