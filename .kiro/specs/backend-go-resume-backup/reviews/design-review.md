## サイクル1 往復1(2026-11-24)

### 審査の範囲

範囲: 全体

### 実ファイルで確かめた文

- 使う既存の仕組み「`RequestErrorHandlerFunc` が読めない本文に 400 と『入力エラーがあります。』で答える」: backend/internal/httpapi/server.go / 合っていた
- 使う既存の仕組み「`GetResume` は `findResume` と `sortEntries` を使う」: backend/internal/resume/store.go 55行(findResume)、275行(loadEntries が sortEntries を呼ぶ)、order.go 17行 / 合っていた
- 使う既存の仕組み「`inTx` `countResumes` `resumeNameExists` `insertResume`」: backend/internal/resume/store.go 33行、82行、91行、100行 / 合っていた
- 使う既存の仕組み「`resumeLimit`」: backend/internal/resume/rules.go 17行(上限は 50) / 合っていた
- 使う既存の仕組み「`errResumeNotFound`(404)、`errUnreadableInput`(400)、`errResumeNameDuplicated`(400)」: backend/internal/resume/errors.go 138行、144行、154行 / 合っていた
- 使う既存の仕組み「`isPersonName` と `japanZone`」: backend/internal/resume/rules.go 85行、store.go 19行 / 合っていた
- 使う既存の仕組み「`Export` と `exported`」: backend/internal/resume/export.go 31-40行(Body、ContentType、FileName、Inline)、backend/internal/httpapi/resumes.go 385行 / 合っていた
- 使う既存の仕組み「`sanitizeFileName`」: backend/internal/resume/filename.go 17行 / 合っていた
- 使う既存の仕組み「`javaTrim` と `numbersWithinLimit`」: backend/internal/resume/exportmodel.go 187行、exportbody.go 215行 / 合っていた
- 使う既存の仕組み「`parseJavaURI` と `equalsIgnoreCaseASCII`」: backend/internal/resume/link.go 269行、53行 / 合っていた
- 使う既存の仕組み「`auth.ErrBusiness` と `NotBlank`」: backend/internal/auth/exported.go 101行、116行 / 合っていた
- 使う既存の仕組み「`fonts.sql` の経歴書 401、`resume-ops.sql` の利用者 340 と経歴書 350、`resume-limits.sql` の利用者 500、`fixtures/backups/` の4つのファイル」: backend/compat/fixtures/resumes/fonts.sql 6行、resume-ops.sql、resume-limits.sql、fixtures/backups/(basic.json、broken.json、no-resume.json、wrong-version.json) / 合っていた
- プロジェクトの決まり「`golang.org/x/text` と sqlc の生成したコードを今の depguard の規則で読める」: backend/.golangci.yml 27-57行(lax で、internal と cmd だけを禁じる) / 合っていた
- 全体の構成「使う技術の版は go.mod と Makefile にすでにある」: backend/go.mod(go 1.27.0、uuid v1.6.0、pgx v5.11.0、testcontainers v0.45.0、x/text v0.43.0)、Makefile(oapi-codegen v2.8.2、sqlc v1.31.1) / 合っていた
- 全体の構成「`encoding/json` は `<` `>` `&` と行や段落の区切りを番号で書き、今の `jacksonJSON` は使えない」: backend/internal/httpapi/authresponses.go 111行(SetEscapeHTML(false) で書くだけで、サロゲートと U+2028 を扱わない) / 合っていた
- ファイルの構成「`backend/internal/platform/db/sqlcgen/` の生成したコードを作り直す」: backend/Makefile 17行、backend/internal/resume/store.go 15行(実際の場所は `backend/internal/platform/database/sqlcgen/`) / 食い違っていた(D1-1-1)
- ファイルの構成「`ExistsUser` を足す」: backend/db/queries/(同じ名前の問い合わせはまだ無い) / 合っていた
- ファイルの構成「service.go の28の操作のコメント(1行と31行)」: backend/internal/resume/service.go 1行、31行 / 合っていた
- ファイルの構成「resumes.go の57行、resumeresponses.go の12行、server.go の49行と93行」: backend/internal/httpapi/resumes.go 57行、resumeresponses.go 12行、server.go 49行、93行 / 合っていた
- ファイルの構成「resumes_test.go の28を期待する箇所」: backend/internal/httpapi/resumes_test.go 469、618、626-627、844、879-880、933、946、998、1006-1007、1028行 / 合っていた
- ファイルの構成「scenario.go の `validateKind` の `hasRequest`、`validateVersionBody`、`validateJSONFile`、絶対の URL の段で json_file を断る」: backend/compat/harness/scenario.go 340-343行、375行、397行、475行 / 合っていた
- ファイルの構成「capture.go の `text` と `requestBody`」: backend/compat/harness/capture.go 31行、252-266行 / 合っていた
- ファイルの構成「`TestCrossRoute_ExportSteps` と `TestLoadScenarios_ExportPerf` が手本」: backend/compat/harness/cross_test.go 325行、perfmeasure_test.go 536行 / 合っていた
- ファイルの構成「fixtures.go の23行が backups/ の説明」: backend/compat/harness/fixtures.go 23行 / 合っていた
- ファイルの構成「`checkBackup` と `TestFixtures_AllLoadable` は知らない名前のファイルで失敗する」: backend/compat/harness/fixtures_test.go 204行(default で失敗)、304行、311行 / 合っていた
- ファイルの構成「compat_test.go、cross_test.go、perf_test.go が戻しの要求に 501 を期待する」: backend/compat/compat_test.go 92-93、105-107、161-165、178行、backend/compat/cross_test.go 189-190、202-205行、backend/compat/perf_test.go 15、28-30行 / 合っていた
- ファイルの構成「match_test.go の328-329行が項目の数を確かめる」: backend/compat/harness/match_test.go 328-329行(61を期待する) / 合っていた
- ファイルの構成「changed-behaviors.yaml に CB-062 から足す」: backend/compat/changed-behaviors.yaml 775行(最後は CB-061) / 合っていた
- 処理の流れ「`CreateResume` と同じく、上限、名前の重なり、入れる、を1つのトランザクションで行う」: backend/internal/resume/service.go 103-162行 / 合っていた
- 処理の流れ「Java 版は、値の無い要素で 500、版、上限、名前、名前の重なり、値の決まりの順に確かめる」: Java の RestoreResumeController(usecase の前に toCommand)、RestoreResumeRequest 189-190行(要素が null で NPE)、RestoreResumeUseCase 58行、63行、69行、72行、75行 / 合っていた
- Service の戻し「名前の重なりは、`toDBText` で直した名前を `resumeNameExists` に渡す。データベースに入る名前と同じ字で比べるため」: Java の ResumeNameDuplicationCheckService(ファイルの名前を Java の文字列のまま、DB から読んだ名前と equals で比べる)、ResumeName(INVALID_PATTERN に `?` を含むが、対になっていないサロゲートは断らない) / 食い違っていた(D1-1-3)
- Service の戻し「`buildRestored` は最後に `sortEntries` で項目を並べる。Java 版も戻すときに並べる」: Java の Resume.java 120-122行 / 合っていた
- Service の書き出し「ID の形でない値と、無い経歴書と、ほかの利用者の経歴書は 404」: Java の ResumeIdResolver / 合っていた
- 戻しと書き出しの受け口「`rawBody` と `authResponse` と `authErrorResponse` と `newResumeBody`」: backend/internal/httpapi/resumes.go 77行、86行、authresponses.go 15-26行、87行、resumeresponses.go 179行 / 合っていた
- 仕様書の変更「`CreateResumeRequest` と同じ書き方。戻しの本文は `ResumeBackup` を指す」: backend/api/openapi.yaml 665-693行(682行)、757-780行(774行)、1817-1819行 / 合っていた
- 仕様書の変更「`unimplemented.go` を残す」: backend/internal/httpapi/unimplemented.go 98行、113行 / 合っていた
- WTF-8 の扱い「PostgreSQL の UTF-8 の列は対になっていないサロゲートを入れられない」と JSON の書き手「Jackson はサロゲートを番号で書く」: Java のマイグレーション(resumes の名前に UNIQUE 制約は無い)、Jackson の UTF8JsonGenerator / 合っていた
- 正解のファイル「試作と同じ設定で、データベース `kp_backup_proto` と Redis の DB 7 を使う」と「`keireki_proto` に入れて書き出す」: research.md 87行(kp_backup_proto だけで、Redis の DB 7 とつなぎ先の選び方は書かれていない)、design.md 386行と396行 / 食い違っていた(D1-1-2)
- 筋書き「`CrossRoute` は最後の段を、その前の段と違う版に送る」: backend/compat/harness/cross.go 40行 / 合っていた
- 変えた動きの一覧「CB-001 が backupResume のポートフォリオ、SNS、自己PR の order_only を受け持つ」: backend/compat/changed-behaviors.yaml 14-45行 / 合っていた
- 進み具合の表「バックアップの行は未着手。応答の時間の表に出力の行がある」: .kiro/specs/backend-go-replacement/progress.md 42行、67-68行、backend/compat/harness/coverage.go(GroupNames に「バックアップ」) / 合っていた
- API の説明画面での確認「api-docs はポート 8082、backend-go のコンテナ」: compose.yaml 40行、76-86行 / 合っていた

### 受入基準ごとの確かめ方

| 受入基準 | 確かめる道具 | 動かす場所 | 動かすのに要るもの | design の箇所 |
|---|---|---|---|---|
| 1.1 | `make compat` の scenarios/backup の筋書き一式、`restore_integration_test.go` と `restore.json` | CI の compat の検査、backend のコンテナ(testcontainers) | user1、user2、利用者 340、利用者 500、csrf、group 5、Java 版で控えた `restore.json` | バックアップの操作の筋書き、テストの方針の結合テスト |
| 1.2 | `resumes_test.go` と `backup-unsent.json`、CB-067 からの一覧 | backend のコンテナ | 控えるときに動かす Java 版のコンテナとそのつなぎ先(D1-1-2) | 戻しと書き出しの受け口、Java 版の答えの正解のファイル |
| 1.3 | `export.yaml` と `restore.yaml`、Playwright での API の説明画面の確認 | CI の compat の検査、開発環境の api-docs(8082)と backend-go | 作業フォルダのコードを動かす backend-go、Cookie の XSRF-TOKEN | API の説明画面での確認 |
| 2.1 | `restore.yaml`、`restore_integration_test.go` | CI の compat の検査、backend のコンテナ | `java-*.json`、user2、データベースの比べ方 | バックアップの操作の筋書き、テストの方針 |
| 2.2 | `lax.yaml`、`malformed.yaml`、`restore_integration_test.go`、`buildRestored` の単体テスト | CI の compat の検査、backend のコンテナ | `lax-no-process.json`、`lax-no-names.json`、`malformed-no-careers.json` | Service の戻し、テストの方針 |
| 2.3 | `restore_integration_test.go`、compat のデータベースの比べ方 | backend のコンテナ、CI の compat の検査 | user2 | テストの方針の結合テスト |
| 3.1 | `backup_integration_test.go`(801〜804 と `java-*.json` をバイトで比べる)、`export.yaml` | backend のコンテナ、CI の compat の検査 | `backup.sql`、Java 版で控えた `java-*.json` | テストの方針の結合テスト |
| 3.2 | `backup_integration_test.go` の経歴書 805、CB-062 | backend のコンテナ | 経歴書 805 | 初期のデータとバックアップのファイル、変えた動きの一覧に載せる違い |
| 3.3 | `backup_integration_test.go` のバイトの比べ、`javajson.go` の単体テスト | backend のコンテナ | 経歴書 804、`java-804.json` | JSON の書き手、テストの方針 |
| 3.4 | `backup_integration_test.go`、`export.yaml` | backend のコンテナ、CI の compat の検査 | 経歴書 803 | Service の書き出し、テストの方針 |
| 4.1 | `rejects.yaml` の確かめる順の組、`restore_integration_test.go` | CI の compat の検査、backend のコンテナ | 利用者 500、user1、`reject-bad-date-wrong-version.json` など | バックアップの操作の筋書き |
| 4.2 | `rejects.yaml`、`restore_integration_test.go` | 同上 | `wrong-version.json`、`reject-no-version.json` | 同上 |
| 4.3 | `rejects.yaml`、`restore_integration_test.go` | 同上 | 利用者 500 | 同上 |
| 4.4 | `rejects.yaml`、`restore_integration_test.go` | 同上 | user1 と `java-401.json`。対になっていないサロゲートを含む名前は確かめない(D1-1-3) | 同上 |
| 4.5 | `rejects.yaml`、`lax.yaml`、`buildRestored` の単体テスト | 同上 | `reject-*.json`、`lax-*.json` | Service の戻し、テストの方針 |
| 4.6 | `rejects.yaml`、`malformed.yaml`、`restoreread.go` の単体テスト、`restore.json` | 同上 | `reject-bad-date.json`、`malformed-types.json` | 戻しの本文の読み手 |
| 5.1 | `not-found-other-user.yaml`、`backup_integration_test.go` | CI の compat の検査、backend のコンテナ | user1 | バックアップの操作の筋書き |
| 5.2 | `not-found-other-user.yaml`、`backup_integration_test.go` | 同上 | user2 と経歴書 401 | 同上 |
| 5.3 | `deleted-user.yaml`、`restore_integration_test.go`(CB-063〜066) | 同上 | 利用者 340 と経歴書 350、`accessToken` の値 | Service の戻し、変えた動きの一覧に載せる違い |
| 6.1 | 筋書き一式 | CI の compat の検査 | 筋書きの表のファイル | バックアップの操作の筋書き |
| 6.2 | 筋書き一式のデータベースの比べ、`backup_integration_test.go` のバイトの比べ | CI の compat の検査、backend のコンテナ | CB-001 と CB-062 の order_only | バックアップの操作の筋書き、テストの方針 |
| 6.3 | `resumes_test.go` と `backup-unsent.json`、CB-067 から | backend のコンテナ | 控えた Java 版の答え | 変えた動きの一覧に載せる違い |
| 6.4 | `perf-backup.yaml` と `perf-restore.yaml`(prepare_each)、`make compat-perf`、`TestLoadScenarios_BackupPerf` | compat-perf の検査、backend のコンテナ | user1、経歴書 401、`java-401.json` | バックアップの操作の筋書き、進み具合の表 |
| 7.1 | `cross-backup.yaml`、`make compat-cross` | CI の compat-cross の検査 | user1、経歴書 401、`json_capture` | Java 版と Go 版を比べる検査の広げ方、バックアップの操作の筋書き |
| 7.2 | `cross-backup.yaml`、`TestCrossRoute_BackupSteps` | CI の compat-cross の検査、backend のコンテナ | 2つの向き | 同上 |
| 8.1 | research.md の試作の記録 | 設計の段階で済んでいる | 無し | 試作の記録 |
| 8.2 | research.md の試作の記録、控えた答えとの照らし合わせ | 実装のはじめ | Java 版のコンテナ | 試作の記録、Java 版の答えの正解のファイル |
| 8.3 | `progress.md` の書き換え、`TestCoverage_Operations` | backend のコンテナ | 無し | 進み具合の表 |

### 申告

**1. 退会してすでに居ない利用者の 500 を、トランザクションのあとに利用者が居るかを調べて 404 にする** — Service の戻し、利用者が居るかの問い合わせ

- Issue の記載: なし(置き換えの spec の受入基準を指すだけ。requirements の要件5の受入基準3が、400 か 404 かを設計で決めるとした)
- 決めたこと: 新しい sqlc の問い合わせ `ExistsUser` を足し、誤りが `*auth.Error` でないときだけ、トランザクションのあとに利用者が居るかを調べ、居なければ 404 にする
- 他にありえた選択肢: 今の `isUserMissing`(外部キーの違反 23503)で見分ける。400 で答える。トランザクションの初めに利用者が居るかを調べる
- 外れていた場合: `isUserMissing` だけでは、入れる前に起きる 500(要素が null、経歴書の中身が無い)を拾えず、CB-064 と CB-065 の場面で Go 版が 500 を返す。初めに調べる形にすると、利用者が居ないときの確かめる順が Java 版の 400 の場面と変わる

**2. 書き出しの項目の並びを、経歴書を読み出すときの `sortEntries` の順にする** — Service の書き出し、変えた動きの一覧の CB-062

- Issue の記載: なし(requirements の要件3の受入基準2で所有者が受け入れた)
- 決めたこと: `GetResume` の並びをそのまま使い、職歴、プロジェクト、資格の並びの違いを CB-062 の order_only で比べない
- 他にありえた選択肢: Java 版と同じく、データベースから読んだ順のまま書く
- 外れていた場合: データベースの順のまま書くと、Go 版のテストで項目の順を確かめられず、requirements の要件6の受入基準2を満たせない

**3. JSON の書き手 `JavaJSON` と読み手 `jtree` を、ライブラリを足さずに新しく作る** — 全体の構成、JSON の読み手、JSON の書き手

- Issue の記載: なし
- 決めたこと: 今の `jacksonJSON` を使わず、サロゲートと U+2028 などの書き方を Jackson に合わせた書き手と、対になっていないサロゲートを保つ読み手を作る
- 他にありえた選択肢: `jacksonJSON` を広げる。外部の JSON のライブラリを足す
- 外れていた場合: 書き手が Jackson と1字でも違うと、`backup_integration_test.go` のバイトの比べで見つかり、書き手を直すことになる。読み手が Jackson より厳しいか緩いと、`restore.json` との比べで見つかる

**4. 仕様書の戻しの本文の型を `json.RawMessage` にする** — 仕様書の変更

- Issue の記載: なし
- 決めたこと: 新しい型 `RestoreResumeRequest` に `x-go-type: json.RawMessage` を付け、生成したコードに本文を読ませない
- 他にありえた選択肢: 今の `ResumeBackup` の生成した型で読む
- 外れていた場合: 生成した型で読むと、対になっていないサロゲートが U+FFFD に置き換わり、型の違う値の本文が読めない本文として断られ、Java 版と答えが分かれる

**5. 対になっていないサロゲートを、`toDBText` で `?` にしてデータベースに入れる** — WTF-8 の扱い

- Issue の記載: なし
- 決めたこと: 経歴書と項目のすべての字の欄で、対になっていないサロゲートを `?` にして入れる
- 他にありえた選択肢: U+FFFD にする。読めない本文として断る
- 外れていた場合: 試作の記録のとおり Java 版のデータベースの字と同じになるので、外れは小さい。ただし名前の重なりの確かめに同じ直しを当てたことは、指摘 D1-1-3 のとおり Java 版と食い違う

**6. 比べる検査の戻しの本文を `json_file` の `fixtures/backups/` のファイルで送り、`json_capture` は版をまたぐ検査だけに使う** — Java 版と Go 版を比べる検査の広げ方

- Issue の記載: なし
- 決めたこと: Java 版が書き出したファイルを実装のはじめに控え、`json_file` で両方の版に同じ本文を送る
- 他にありえた選択肢: 比べる検査でも、書き出しの答えから取り出した値を送る
- 外れていた場合: 版ごとに取り出した値が分かれ、両方の版に同じ本文を送れないので、比べる検査が成り立たない

### 指摘

| ID | レベル | 該当箇所 | 内容 | 直し方の案 |
|---|---|---|---|---|
| D1-1-1 | 中 | design.md 149行(ファイルの構成の「Claude が変えるファイル」) | 事実の誤り。sqlc の生成したコードの場所を `backend/internal/platform/db/sqlcgen/` と書いているが、実際の場所は `backend/internal/platform/database/sqlcgen/` である(backend/Makefile 17行、backend/internal/resume/store.go 15行の import)。tasks でこのパスを写すと、無いフォルダを指すタスクになる | `backend/internal/platform/database/sqlcgen/` に直す |
| D1-1-2 | 中 | design.md 386行と396行(Java 版の答えの正解のファイル) | 386行は Java 版のデータベースを `kp_backup_proto` と書き、396行は `backup.sql` と `fonts.sql` を `keireki_proto` に入れると書いていて、同じ節の中でデータベースの名前が食い違う(`keireki_proto` は出力の spec の試作の名前である)。また、「試作と同じ設定」の中身(Java 版のつなぎ先を `kp_backup_proto` と Redis の DB 7 に向ける環境変数)が research.md(87行は `kp_backup_proto` だけを書く)にも design にも無く、実装のはじめに正解のファイルを控える手順を再現できない。つなぎ先を誤ると、所有者の開発のデータベース `keireki_pro` に初期のデータを入れることになる | データベースの名前を1つにそろえ、Java 版のつなぎ先を選ぶ環境変数(出力の spec が tasks の T1-1-3 で書いた `SPRING_DATASOURCE_URL` と `SPRING_DATA_REDIS_DATABASE` のような形)を書く |
| D1-1-3 | 高 | design.md 259行(Service の戻しの「名前の重なり」) | 名前の重なりを `toDBText` で直した名前で確かめ、その理由を「データベースに入る名前と同じ字で比べるため」と書いている。Java 版の `ResumeNameDuplicationCheckService` は、ファイルの名前を Java の文字列のまま(対になっていないサロゲートを含めて)、データベースから読んだ名前と equals で比べる。`ResumeName` は対になっていないサロゲートを断らない(`INVALID_PATTERN` の `?` には当たらない)。そのため、名前に対になっていないサロゲートを含むファイル(たとえば名前が `"X\uD800"`)を同じ利用者が2回戻すと、Java 版は2回とも 201 で答え(データベースには `X?` が2件入る)、Go 版は2回目を名前の重なりの 400 で答える。これは画面が送る要求なので、要件1の受入基準1と要件4の受入基準4に反する。`restore.json` は経歴書を持たない利用者で控え、筋書きにもこの場面が無いので、どの検査もこの違いを見つけない | 名前に対になっていないサロゲートを含むときは、名前の重なりを確かめない(データベースの名前にサロゲートは入らないので、Java 版でも重ならない)。生の WTF-8 を SQL に渡さない(PostgreSQL が断るため)。理由の文を Java 版の比べ方に合わせて直し、`restore_integration_test.go` で、同じファイルを2回戻す場面を確かめる |
| D1-1-4 | 低 | design.md 346-350行(仕様書の変更) | Go 版は、退会してすでに居ない利用者の戻しに 404 で答える(CB-063〜066)が、仕様書の restore の答え(openapi.yaml 665-693行)は 201、400、401、403、500 だけで、404 が無い。仕様書の変更の節は 404 を足すかどうかを書いていない | 404 の答えを足すか、足さない理由を書く |
| D1-1-5 | 低 | design.md 85-86行(プロジェクトの決まりを守っているか) | frontend の機能ごとの境界と状態の持ち方の2つの項目を、雛形の「関係のない項目:」の1行にまとめず、別の行に書いている | 「関係のない項目: frontend の機能ごとの境界、frontend の状態の持ち方(画面を変えないため)」の1行にまとめる |

### 前の段階への指摘

無い

- 往復: 1回目 / 高1 中2 低2

## サイクル1 往復2(2026-11-24)

### 審査の範囲

範囲: 差分

- design.md「Service の戻し(restore.go)」の「名前の重なり」の箇条と「失敗したとき」: D1-1-3 の直しの本文で、名前の重なりの確かめ方と、そのあとの値の決まりでの扱いを書き換えたため。Java の `ResumeNameDuplicationCheckService` `ResumeName` `RestoreResumeUseCase` と照らした
- design.md「Service の戻し」の `buildRestored` の経歴書の名前の箇条と、「WTF-8 の扱い(wtf8.go)」: 対になっていないサロゲートを含む名前が値の決まりで断られるかは、この2つの箇所の書き方で決まるため
- design.md「Java 版の答えの正解のファイル」の節(試作のコンテナの設定、`restore.json` に足した場合)と、research.md の試作の記録 87-111行と「今あるものについて確かめた文」82-85行: D1-1-2 と D1-1-3 の直しの本文と、直しの根拠に挙げられた記録のため
- design.md「テストの方針」の `restore_integration_test.go` の5つの場合: D1-1-3 の直しで3つ目の場合を足したため。requirements.md の要件1の受入基準1と要件4の受入基準4(114行、118行)を見た
- design.md「ファイルの構成」の sqlc の生成したコードの場所: D1-1-1 の直しのため
- 書き方の点検の直し(「ファイルの版」の呼び名、主語、全体の構成の部品の箇条を部品の節に任せたこと、WTF-8 の意味の文を移したこと、`GetResume` の箇条、CB-067 の文、`numbersWithinLimit` の文): 意味が変わっていないか、部品の数が部品の節と合うか(6つの部品の節があること)を見た。ほかの節は、この差分で影響を受けないので読み直していない

### 実ファイルで確かめた文

- ファイルの構成「sqlc の生成したコードは `backend/internal/platform/database/sqlcgen/`」: backend/internal/platform/database/sqlcgen/(db.go、resumes.sql.go など6つのファイル) / 合っていた
- 使う既存の仕組み「`GetResume` は、中で `findResume` と `sortEntries` を使う」: backend/internal/resume/service.go 67行、72行、store.go 55行、275行 / 合っていた
- Service の戻し「名前があれば `resumeNameExists` に渡す」: backend/internal/resume/store.go 91行 / 合っていた
- Service の戻し「データベースの経歴書の名前は対になっていないサロゲートを含まないので、Java 版でも、このような名前は重ならない」: backend/src/main/java/com/example/keirekipro/domain/service/resume/ResumeNameDuplicationCheckService.java 37-46行(データベースから読んだ名前と `equals` で比べる)、research.md 111行(データベースの字は `?` になる) / 合っていた
- Service の戻し「対になっていないサロゲートを含む名前は、そのあとの値の決まりで断られる」と、テストの方針の `restore_integration_test.go` の3つ目の場合「Java 版と同じ値の決まりの誤りになる」: backend/src/main/java/com/example/keirekipro/domain/model/resume/ResumeName.java 18行、43-67行、backend/src/main/java/com/example/keirekipro/usecase/resume/RestoreResumeUseCase.java 69-75行、research.md 109行 / 食い違っていた(D1-2-1)
- Java 版の答えの正解のファイル「Java 版のイメージを `docker/backend/Dockerfile.prod` で作る」: docker/backend/Dockerfile.prod 4行、28行、48行、60行 / 合っていた
- Java 版の答えの正解のファイル「compose のネットワーク `my-network`」と「`jdbc:postgresql://postgresql:5432/...`」と「所有者の開発のデータベース `keireki_pro`」: compose.yaml 134-156行(container_name は postgresql、POSTGRES_DB は keireki_pro、ポート 5432)、213-215行 / 合っていた
- Java 版の答えの正解のファイル「試作と同じ設定で動かす。設定は `SPRING_DATASOURCE_URL` と `SPRING_DATA_REDIS_DATABASE` で選ぶ」: backend/src/main/resources/application.yaml 11-15行(既定の Redis のホストは localhost で、`frontend-base-url` が無い)、application-dev.yaml 1-27行、backend/src/main/java/com/example/keirekipro/presentation/auth/controller/OidcCallbackController.java 44行(`@Value("${frontend-base-url}")` に既定の値が無い)、backend/compat/harness/versions.go 74-79行(比べる検査は Java 版を `SPRING_PROFILES_ACTIVE=dev` で動かす) / 食い違っていた(D1-2-2)
- 戻しの本文の読み手「`numbersWithinLimit` は本文の中の数の長さが上限を超えないことを確かめる」: backend/internal/resume/exportbody.go 214-215行 / 合っていた

### 受入基準ごとの確かめ方

| 受入基準 | 確かめる道具 | 動かす場所 | 動かすのに要るもの | design の箇所 |
|---|---|---|---|---|
| 1.1 | `restore_integration_test.go` の3つ目の場合と `restore.json` | backend のコンテナ(testcontainers) | 名前に対になっていないサロゲートを含むファイル、その名前のサロゲートを `?` にした経歴書を持つ利用者、控えた Java 版の答え。期待する答えの書き方が Java 版の動きと食い違う(D1-2-1) | Java 版の答えの正解のファイル、テストの方針の結合テスト |
| 4.4 | `rejects.yaml` の名前の重なりの組、`restore_integration_test.go` の2つ目と3つ目の場合 | CI の compat の検査、backend のコンテナ | user1 と `java-401.json`、上の利用者とファイル | Service の戻しの「名前の重なり」、テストの方針 |
| 1.2、6.3 | `resumes_test.go` と `backup-unsent.json` | backend のコンテナ | 控えるときに動かす Java 版のコンテナと、その起動の設定(D1-2-2) | Java 版の答えの正解のファイル |
| 2.1、3.3、4.6、6.2 | `java-*.json` と `restore.json` を使う結合テストと筋書き | backend のコンテナ、CI の compat の検査 | 控えるときに動かす Java 版のコンテナと、その起動の設定、データベース `kp_backup_proto`(D1-2-2) | Java 版の答えの正解のファイル |
| 8.2 | 控えた答えと research.md の試作の記録の照らし合わせ | 実装のはじめ | Java 版のコンテナと、その起動の設定(D1-2-2) | Java 版の答えの正解のファイル |

### 申告

この往復の差分に、新しく申告する決定は無い。名前に対になっていないサロゲートを含むときに名前の重なりを確かめないことは、Java 版の比べ方と同じ答えになる写し方で、ほかの選択肢で答えが変わらない。

### 指摘

| ID | レベル | 該当箇所 | 内容 | 直し方の案 |
|---|---|---|---|---|
| D1-2-1 | 中 | design.md 252行(Service の戻しの「名前の重なり」の最後の文)、390行(`restore.json` に足した場合)、606行(テストの方針の `restore_integration_test.go` の3つ目の場合) | 事実の誤り(置き換える前の版の動き)。design は、対になっていないサロゲートを含む名前は値の決まりで断られ、Java 版は値の決まりの誤りで答えると書いている。しかし、Java の `ResumeName`(ResumeName.java 18行、43-67行)は、空白だけ、50文字を超える、`\ / : * ? " < > |` を含む(正規表現の `.` は対になっていないサロゲートにも当たる)、`.` で始まるか終わる、の4つしか断らず、対になっていないサロゲートを断らない。`RestoreResumeUseCase`(69-75行)はこの `ResumeName` で確かめるので、名前 `"X\uD800"` のほかに誤りの無いファイルを戻すと、Java 版は 201 で答え、データベースには `X?` が入る(research.md 111行の項目の場合と同じ)。直しの根拠の research.md 109行は、Java 版が書き出したファイルの場合で、書き出したファイルの名前はデータベースから読んだ `X?` なので、400 になったのは使えない字 `?` のためであり、ファイルの名前に対になっていないサロゲートを書いた場合の記録ではない。名前の重なりを確かめない直しそのものは Java 版と同じ答えになる。ただし、Claude がこの文のとおりに3つ目の場合の期待を「値の決まりの誤り」にすると、Java 版から控えた `restore.json` の答え(201)と食い違ってテストが通らず、文に合わせて `buildRestored` に対になっていないサロゲートを断る決まりを足すと、Java 版と答えが分かれる。どちらも実装で見つかり、design に戻ることになる | 252行の最後の文を消すか、「対になっていないサロゲートを含む名前は、ほかの値の決まりを満たせば Java 版と同じく 201 で戻り、データベースには `toDBText` で `?` にした名前が入る」に直す。606行の3つ目の場合を「名前の重なりの誤りにならず、`restore.json` に控えた Java 版の答えと同じになること」にし、期待する答えを design で決め打ちしない。research.md 109行に、400 の理由が書き出したファイルの名前の `?` であることを書き足す |
| D1-2-2 | 中 | design.md 379行(Java 版の答えの正解のファイルの、試作のコンテナの設定) | 動かすのに要るものの抜けと事実の誤り。design は「試作と同じ設定で」動かすとし、設定として `SPRING_DATASOURCE_URL` と `SPRING_DATA_REDIS_DATABASE` の2つだけを書いている。しかし、`Dockerfile.prod` のイメージをプロファイル無しで動かすと、application.yaml には `frontend-base-url` が無く、OidcCallbackController.java 44行の `@Value("${frontend-base-url}")` に既定の値が無いので Java 版は起動しない。Redis のホストも既定の localhost(application.yaml 13行)になる。比べる検査は Java 版を `SPRING_PROFILES_ACTIVE=dev` で動かしている(backend/compat/harness/versions.go 76行)ので、試作も dev のプロファイル(localstack の秘密の値で Redis のホストなどを読む)で動かしたと考えられるが、research.md 84行の記録にも design にも無い。あわせて、データベース `kp_backup_proto` を消す手順はあるが、起動の前に作る手順が無い。D1-1-2 が求めた、実装のはじめに正解のファイルを控える手順を再現できる形になっていない | 起動の設定に `SPRING_PROFILES_ACTIVE=dev` を足し、dev のプロファイルが localstack(`http://localstack:4566`)から Redis のホストなどを読むので localstack が動いている必要があることを書く。Java 版を起動する前に、開発環境のデータベースのサーバに `kp_backup_proto` を作ることを書く。research.md の「今あるものについて確かめた文」の84行にも同じ設定を書き足す |

### 前の段階への指摘

無い

- 往復: 2回目 / 高0 中2 低0

## サイクル1 往復3(2026-11-24)

### 審査の範囲

範囲: 差分

- design.md「Service の戻し(restore.go)」の「名前の重なり」の箇条と、同じ節の `buildRestored` の経歴書の名前の箇条: D1-2-1 の直しで、名前の値の決まりが対になっていないサロゲートを断らないと書き換えたため。Java の `ResumeName` `ResumeNameDuplicationCheckService` と、Go の今の `checkResumeName` を照らした
- design.md「Java 版の答えの正解のファイル」の `restore.json` の箇条(390行)と、「テストの方針」の `restore_integration_test.go` の3つ目の場合(606行)と、research.md 112行: D1-2-1 の直しで期待を書き換え、根拠の記録を直したため。「断られ」「値の決まりの誤り」で design と research.md を検索し、古い書き方が残っていないかを見た
- design.md「Java 版の答えの正解のファイル」の試作のコンテナの段落(379行)と、同じ節の `java-*.json` の箇条(389行): D1-2-2 の直しで、データベース `kp_backup_proto` の作り方と表の作り方を書き足したため。`kp_backup_proto` で design を検索し、そのデータベースに初期のデータを入れる389行を見た
- design.md「バックアップの操作の筋書き」の `cross-backup.yaml` の4つ目の段: 書き方の点検で「201 で答えることを確かめ」と書き換えたため。cross の形の段が状態の番号を確かめられるかを harness で見た
- 書き方の点検の直し(概要の2文を消したこと、Jackson と WTF-8 の意味の文を移したこと、職歴の箇条、試作の記録の節の1文を消したこと): 消した中身が部品の節に残っているか(Jackson と同じ書き方と読み方、Java 版と同じ順、1つのトランザクション、書き出しの項目の並び)と、移した意味の文が言葉の初めて出る箇所の前にあるかを、「Jackson」「WTF-8」で検索して見た。ほかの節は、この差分で影響を受けないので読み直していない
- requirements-response.md の R1-3-1(design で書くと記録された、姓と名の空白だけの扱い): design.md 259行にそのとおり書かれている。この差分で変わっていない

### 実ファイルで確かめた文

- Service の戻し「Java 版の名前の値の決まり(`ResumeName`)は対になっていないサロゲートを断らない」: backend/src/main/java/com/example/keirekipro/domain/model/resume/ResumeName.java 18行、43-67行(空白だけ、50文字を超える、使えない9つの字、`.` で始まるか終わる、の4つだけを断る) / 合っていた
- Service の戻し「データベースの経歴書の名前は対になっていないサロゲートを含まないので、Java 版でも、このような名前は重ならない」: backend/src/main/java/com/example/keirekipro/domain/service/resume/ResumeNameDuplicationCheckService.java 37-46行(データベースから読んだ名前と `equals` で比べる) / 合っていた
- Service の戻し「Go 版の値の決まりも断らない」に関わる今の Go の名前の決まり: backend/internal/resume/rules.go 45-66行(`strings.ContainsAny` で使えない字を探すので、WTF-8 のサロゲートのバイトは使えない字に当たらない。長さは design のとおり `javaLen` で数える) / 合っていた
- research.md 112行「400 になったのは書き出したファイルの名前の `?` のため」: ResumeName.java 18行 / 合っていた
- Java 版の答えの正解のファイル「compose が付ける名前は `keirekipro_my-network`」: compose.yaml 213-215行(ネットワークに name が無い)、.claude/scripts/parallel/run-check.sh 162行と session.sh 380行(開発環境を `-p keirekipro` で動かす) / 合っていた
- Java 版の答えの正解のファイル「dev のプロファイルは、データベースと Redis のつなぎ先と JWT の値を localstack の秘密の値から読む」: backend/src/main/resources/application-dev.yaml 3行、5-12行、15行、25行、docker/localstack/init-localstack.sh 19-35行 / 合っていた
- Java 版の答えの正解のファイル「比べる検査と同じく `SPRING_PROFILES_ACTIVE` を `dev` にして動かす」: backend/compat/harness/versions.go 74-79行 / 合っていた。比べる検査は `TZ` も `Asia/Tokyo` にするが、バックアップのファイルの日時は世界標準時の `exportedAt` だけで(BackupResumeResponse.java 31行)、`restore.json` の比べ方は作った日時と直した日時を除くので、控える答えは時間帯で変わらない
- Java 版の答えの正解のファイル「表は、Java 版が起動のときに Flyway で作る」: backend/src/main/resources/application.yaml 19-22行(`flyway.enabled: true`) / 合っていた
- Java 版の答えの正解のファイル「`backup.sql` と `fonts.sql` を `kp_backup_proto` に入れて Java 版で書き出す」: backend/compat/fixtures/resumes/fonts.sql 1行、5-7行(経歴書 401 は `users/basic.sql` の user1 のもの)、backend/src/main/resources/ の Flyway のマイグレーション(`users` に行を入れるものは無い) / 食い違っていた(D1-3-1)
- 筋書き「`cross-backup.yaml` の4つ目の段で 201 で答えることを確かめる」: backend/compat/harness/cross.go 163行、181-190行(版に送る段の expect の status を確かめる) / 合っていた

### 受入基準ごとの確かめ方

| 受入基準 | 確かめる道具 | 動かす場所 | 動かすのに要るもの | design の箇所 |
|---|---|---|---|---|
| 1.1、4.4 | `restore_integration_test.go` の3つ目の場合と `restore.json` | backend のコンテナ(testcontainers) | 名前に対になっていないサロゲートを含むファイル、そのサロゲートを `?` にした名前の経歴書を持つ利用者、控えた Java 版の答え。Java 版で控えるときの、その利用者と、経歴書を持たない利用者が決まっていない(D1-3-1) | Service の戻しの「名前の重なり」、Java 版の答えの正解のファイル、テストの方針の結合テスト |
| 2.1、3.3、4.6、6.2 | `java-*.json` と `restore.json` を使う結合テストと筋書き | backend のコンテナ、CI の compat の検査 | Java 版のコンテナ(dev のプロファイル、localstack、`kp_backup_proto`、Redis の DB 7)、`kp_backup_proto` に入れる初期のデータ。`users/basic.sql` が並んでいない(D1-3-1) | Java 版の答えの正解のファイル |
| 1.2、6.3 | `resumes_test.go` と `backup-unsent.json` | backend のコンテナ | Java 版のコンテナとその起動の設定、要求を送る利用者(D1-3-1) | Java 版の答えの正解のファイル |
| 8.2 | 控えた答えと research.md の試作の記録の照らし合わせ | 実装のはじめ | Java 版のコンテナとその起動の設定 | Java 版の答えの正解のファイル |
| 7.1、7.2 | `cross-backup.yaml` の4つ目の段(201 を確かめ、`$.id` を取り出す) | CI の compat-cross の検査 | user1、経歴書 401、`json_capture` | バックアップの操作の筋書き |

### 申告

この往復の差分に、新しく申告する決定は無い。

### 指摘

| ID | レベル | 該当箇所 | 内容 | 直し方の案 |
|---|---|---|---|---|
| D1-3-1 | 中 | design.md 389行(Java 版の答えの正解のファイルの `java-*.json` の箇条)、390-391行 | 動かすのに要るものの抜け。D1-2-2 の直しで、`kp_backup_proto` は起動の前に空で作り、表は Java 版の Flyway が作ると書いた。Flyway のマイグレーションは `users` に行を入れない。そのあとの389行は、`backup.sql` と `fonts.sql` だけを `kp_backup_proto` に入れると書くが、fonts.sql の経歴書 401 は `users/basic.sql` の user1 のもの(fonts.sql 1行、6行)で、`backup.sql` も user1 の経歴書を置く(design.md 477行)。書いたとおりに入れると外部キーの違反で入らず、API で経歴書を作るためのログインもできない。結合テスト(599行)と筋書き(453行)は `users/basic.sql` を先に入れているのに、Java 版の答えを控える手順だけに無い。あわせて、390-391行の `restore.json` と `backup-unsent.json` を控えるときに、どの利用者で送るか(経歴書を持たない利用者と、名前のサロゲートを `?` にした経歴書を持つ利用者を誰にし、その経歴書をどう作るか)が書かれていない。user1 は経歴書 401 と 801 からを持つので、経歴書を持たない利用者にできない。D1-1-2 と D1-2-2 が求めた、正解のファイルを控える手順を再現できる形になっていない | 389行に、`users/basic.sql` を `backup.sql` と `fonts.sql` より先に入れることを書く。390行に、経歴書を持たない利用者を user2 のように名で決め、名前のサロゲートを `?` にした経歴書を持つ利用者と、その経歴書の作り方(たとえば、ほかの答えを控え終えてから、その利用者が名前に対になっていないサロゲートを含む経歴書を API で作る)を書く。391行の要求を送る利用者も書く |

### 前の段階への指摘

無い

- 往復: 3回 / 未解決: 1件

## サイクル2 往復1(2026-11-24)

### 審査の範囲

範囲: 差分

- design.md「Java 版の答えの正解のファイル」の `java-*.json` の箇条(389行): D1-3-1 の直しで、初期のデータを入れる順に `users/basic.sql` を足したため。`users/basic.sql` で design を検索し、筋書きの `fixtures`(454行、458行)と `backup_integration_test.go`(600行)の並びと食い違わないかを見た
- design.md「Java 版の答えの正解のファイル」の `restore.json` の2つの箇条(390-391行)と `backup-unsent.json` の箇条(392行): D1-3-1 の直しで、要求を送る利用者と、201 のあとに経歴書を消す手順と、名前の重なりの場合の作り方を書き足したため。「経歴書を持たない」「user2」で design を検索し、`restore.yaml` `lax.yaml` `malformed.yaml` の利用者(422-425行)と、テストの方針の `restore_integration_test.go` の5つの場合(604-609行)、特に3つ目の場合(607行)と照らした。research.md の試作の記録(105行、114行、116行)と「今あるものについて確かめた文」(89-90行)も見た
- design.md「使う既存の仕組み」の `internal/resume` の部品の箇条(50行): 書き方の点検で、`countResumes` `resumeNameExists` `insertResume` に役割を書き添えたため。書き添えた役割が今のコードと合うかを見た
- 書き方の点検のほかの直し(`backupVersion` と日付の書き方の主語、`\u00XX` の大文字の文、データの形の「空白と改行を入れない」を消したこと、「答えの型の数」、安全の節のほかの利用者の経歴書の文): 意味が変わっていないかを見た。消した「空白と改行を入れない」は、JSON の書き手の節(310行)に残っている。ほかの節は、この差分で影響を受けないので読み直していない
- requirements-response.md の R1-3-1(design で書くと記録された、姓と名の空白だけの扱い): design.md 259行にそのとおり書かれている。この差分で変わっていない

### 実ファイルで確かめた文

- 使う既存の仕組み「`countResumes` は利用者の経歴書の数を数え、`resumeNameExists` は名前が利用者のほかの経歴書と重なるかを調べ、`insertResume` は経歴書と項目をデータベースに入れる」: backend/internal/resume/store.go 81-88行、90-97行、99-127行 / 合っていた
- Java 版の答えの正解のファイル「`fonts.sql` と `backup.sql` の経歴書が user1 のもの」: backend/compat/fixtures/resumes/fonts.sql 1行、5-7行(経歴書 401 の user_id は user1)、backend/compat/fixtures/users/basic.sql 4-8行 / 合っていた
- Java 版の答えの正解のファイル「`users/basic.sql` を `kp_backup_proto` に入れる」(Flyway で作った表に入れられるか): backend/compat/fixtures/users/basic.sql 10-12行(`roles` の USER の行を読む)、backend/src/main/resources/db/migration/V2__insert_mst_data.sql 4-6行(Flyway が USER の役を入れる) / 合っていた
- Java 版の答えの正解のファイル「経歴書を持たない user2」: backend/compat/fixtures/users/basic.sql 7行(user2 が居る)、fonts.sql に user2 の経歴書は無い / 合っていた
- Java 版の答えの正解のファイル「作られた経歴書を `DELETE /api/resumes/{resumeId}` で消し、user2 が経歴書を持たない状態に戻す」: backend/src/main/java/com/example/keirekipro/presentation/resume/controller/DeleteResumeController.java 25行、36行、backend/src/main/java/com/example/keirekipro/usecase/resume/DeleteResumeUseCase.java 43行(`resumeRepository.delete`)、マイグレーションに `deleted_at` などの論理削除の列は無い(行が消えるので、名前の重なりと経歴書の数に残らない) / 合っていた
- Java 版の答えの正解のファイル「1回目の戻しで、データベースに名前のサロゲートを `?` にした経歴書ができる」と「2回目の答えを控える」: backend/src/main/java/com/example/keirekipro/usecase/resume/RestoreResumeUseCase.java 53-54行(`@Transactional`)、research.md 116行(項目の対になっていないサロゲートはデータベースで `?` になり 201)、ResumeNameDuplicationCheckService.java 37-46行(前の往復で確かめた、データベースの名前と `equals` で比べる) / 合っていた。201 以外で答える戻し(500 の戻しを含む)は、トランザクションで戻るので、user2 に経歴書は残らない

### 受入基準ごとの確かめ方

| 受入基準 | 確かめる道具 | 動かす場所 | 動かすのに要るもの | design の箇所 |
|---|---|---|---|---|
| 1.1、4.4 | `restore_integration_test.go` の3つ目の場合と `restore.json` の名前の重なりの場合 | backend のコンテナ(testcontainers)、控えるときは試作用の Java 版のコンテナ | user2、名前に対になっていないサロゲートを含むファイル、Java 版に2回戻した2回目の答え | Java 版の答えの正解のファイル(391行)、テストの方針の結合テスト(607行) |
| 2.1、3.3、4.6、6.2 | `java-*.json` と `restore.json` を使う結合テストと筋書き | backend のコンテナ、CI の compat の検査、控えるときは試作用の Java 版のコンテナ | Java 版のコンテナ(dev のプロファイル、localstack、`kp_backup_proto`、Redis の DB 7)、`users/basic.sql` `resumes/fonts.sql` `backup/backup.sql` を入れる順、経歴書を持たない user2 と 201 のあとの消す要求 | Java 版の答えの正解のファイル(379行、389-390行) |
| 1.2、6.3 | `resumes_test.go` と `backup-unsent.json` | backend のコンテナ、控えるときは試作用の Java 版のコンテナ | 書き出しは user1 と経歴書 401、戻しは user2 | Java 版の答えの正解のファイル(392行) |

### 申告

この往復の差分に、新しく申告する決定は無い。

### 指摘

無い

### 前の段階への指摘

無い

- 往復: 1回で収束 / 未解決: 0件
