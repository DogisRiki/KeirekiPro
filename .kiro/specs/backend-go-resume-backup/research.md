# 調べたこと

## 今あるものについて確かめた文

- requirements.md はじめに「今の Go 版は、この2つの操作の要求に、未実装であることを示す答えを返す」: backend/internal/httpapi/unimplemented.go 97-98行、112-113行
- requirements.md はじめに「Java 版は、利用者の1つの経歴書の中身を JSON のファイルにして、ファイルを保存させる答えを返す」: backend/src/main/java/com/example/keirekipro/presentation/resume/controller/BackupResumeController.java 44行、55-60行。backend/src/main/java/com/example/keirekipro/usecase/resume/BackupResumeUseCase.java 53-55行
- requirements.md はじめに「画面は、答えの Content-Disposition のヘッダからファイルの名前を取り、利用者のパソコンにファイルを保存する」: frontend/src/features/resume/api/backupResume.ts 12行。frontend/src/features/resume/hooks/useBackupResume.ts 22行、27-31行
- requirements.md はじめに「Java 版は、要求の本文のバックアップから、要求を送った利用者の新しい経歴書を作り、状態の番号 201 と、作った経歴書の情報で答える」: backend/src/main/java/com/example/keirekipro/presentation/resume/controller/RestoreResumeController.java 43-44行
- requirements.md はじめに「画面は、利用者がバックアップの画面で拡張子 `.json` のファイルを選んで戻すときに、この操作を使う。画面は、選んだファイルの中身を JSON として読み、読んだ値をそのまま要求の本文にして送る」: frontend/src/features/resume/components/backup/RestoreSection.tsx 38-39行。frontend/src/features/resume/api/restoreResume.ts 11-14行
- requirements.md はじめに「戻しが成功すると、画面は、作った経歴書の編集の画面に移る」: frontend/src/features/resume/hooks/useRestoreResume.ts 26-28行
- requirements.md 範囲「API の仕様書には、2つの操作も書かれている」: backend/api/openapi.yaml 665-671行、757-764行
- requirements.md 範囲「マスタと経歴書のまとまりの Go 版は、経歴書と6つの欄の項目を読み書きし、経歴書を作るときに、作れる経歴書の数の上限と、経歴書の名前の重なりを確かめる」: backend/internal/resume/service.go 103行。backend/internal/resume/errors.go 32行、41行
- requirements.md 範囲「Claude は、Java 版が書き出したバックアップのファイルを Go で読んで書き直し、書き直したファイルを Java 版が状態の番号 201 で戻せることを確かめた。Claude は、そのとき、Go 版がバックアップのファイルを戻す処理と、バックアップのファイルの版を照らす処理を、Go で試しに作らなかった」: .kiro/specs/backend-go-replacement/research.md 53-54行、151行
- requirements.md 範囲「Java 版が書き出すバックアップのファイルと、Go の標準の書き方で書いたファイルでは、`<` `>` `&` と、行や段落の区切りを表す一部の文字の書き方が違う」: .kiro/specs/backend-go-replacement/research.md 58行、155-160行
- requirements.md 範囲「Java 版のバックアップの書き出しは、データベースから読んだ項目を、並べる順を指定せずに読んで、そのまま書く」と「画面と PDF は、経歴書を読み出すときに項目を決まった順に並べ替える」: 書き出しの問い合わせ backend/src/main/java/com/example/keirekipro/infrastructure/query/resume/ResumeQueryMapper.xml 35-174行(json_agg に ORDER BY が無い)。読み出すときの並べ替えは backend/src/main/java/com/example/keirekipro/domain/model/resume/Resume.java 88-110行(ResumeEntryOrderPolicy)と backend/internal/resume/order.go 17-30行(sortEntries)。並びがデータベースの行の置かれ方で変わることは、この research.md の「Java 版の書き出しの項目の並び」の節の試作の結果
- requirements.md 範囲「変えた動きの一覧には、経歴書の中の項目を名前で並べる順の違いが、所有者が受け入れた違いとして載っている」: backend/compat/changed-behaviors.yaml 15-44行
- requirements.md 要件1「状態の番号が 400 か 404 のときは、画面は、答えの本文のエラーの文言を見せる。状態の番号が 500 のときは、画面は、答えの本文を使わず、決まったサーバの誤りの知らせを見せる」: frontend/src/lib/axiosInterceptors.ts 35行、56行、67-68行
- requirements.md 要件1「置き換えの spec の設計は、Java 版が 500 で答える要求のうち、画面が送る要求には、Go 版が Java 版と同じ答えを返すと決めた」: .kiro/specs/backend-go-replacement/design.md 924-934行
- requirements.md 要件1の受入基準1「Java 版がこの要求にサーバの誤りとして状態の番号 500 で答えるとき」(経歴書の中身が無いファイルの戻しが 500 になる): backend/src/main/java/com/example/keirekipro/presentation/resume/dto/RestoreResumeRequest.java 50行。backend/src/main/java/com/example/keirekipro/usecase/resume/RestoreResumeUseCase.java 65-69行。backend/src/main/java/com/example/keirekipro/presentation/shared/AppExceptionHandler.java 173-182行
- requirements.md 要件1の受入基準2「書き出しで経歴書の ID の場所に ID の形でない文字を入れた要求」(Java 版は 404 で答える): backend/src/main/java/com/example/keirekipro/usecase/resume/ResumeIdResolver.java 12行、26-27行
- requirements.md 要件1の受入基準3「Java 版と同じ名前のファイルとして保存すること」と要件3の受入基準4「Java 版と同じ規則で、経歴書の名前から作る」: BackupResumeUseCase.java 30行、47行。backend/src/main/java/com/example/keirekipro/shared/utils/FileUtil.java 81-89行。BackupResumeController.java 55-60行
- requirements.md 要件2の受入基準2「6つの欄のどれかが無いファイルでは、その欄を項目の無い欄として戻す。プロジェクトの工程が無いファイルでは、すべての工程を選んでいないものとして戻す。プロジェクトの技術が無いファイルでは、技術を選んでいないものとして戻す。姓と名の両方が無いか空のファイルでは、氏名の無い経歴書として戻す」: RestoreResumeUseCase.java 147-151行、164行、180行、188行、217行、291行、307行、325行、341行
- requirements.md 要件3の受入基準1「Java 版が書かない欄は、たとえば、入っていない姓と名、終わりの年月の無い職歴とプロジェクト、項目の無い欄である。Go 版は、ファイルの版を `1.0` と書き、書き出した日時を世界標準時で書く」: backend/src/main/java/com/example/keirekipro/presentation/resume/dto/BackupResumeResponse.java 182行、185行、188-204行、217行、233行、282-408行。backend/src/main/java/com/example/keirekipro/usecase/resume/policy/ResumeBackupVersion.java 15行。BackupResumeUseCase.java 53-55行。.kiro/specs/backend-go-replacement/research.md 168行
- requirements.md 要件4の受入基準1「Java 版と同じく、次の順で戻しの要求を確かめる」: 値を読めない要求は本文を読む段で断る(AppExceptionHandler.java 89-92行)。そのあとの順は RestoreResumeUseCase.java 58-59行、63行、72行、75行
- requirements.md 要件4の受入基準1の5番目と受入基準5「Java 版が戻しで確かめる値の決まり(経歴書と項目を作るときに確かめる決まり)」と、例の「50文字を超える経歴書の名前」「始まりの年月より前の終わりの年月」「https の形でないリンク」: RestoreResumeUseCase.java 97-138行。Resume.java 187-197行。backend/src/main/java/com/example/keirekipro/domain/model/resume/ResumeName.java 48-49行。Period.java 66-68行。Link.java 36-44行、55行
- requirements.md 要件4の受入基準5「Java 版の戻しは確かめない」決まり(年月の範囲、職歴の期間の重なり、リンクの長さ、姓と名の両方が無いときの姓と名、工程): 画面の保存の決まりは backend/src/main/java/com/example/keirekipro/presentation/shared/validator/YearMonthRange.java 39-44行、presentation/resume/dto/CreatePortfolioRequest.java 37行、CreateSnsPlatformRequest.java 30行、UpdateResumeBasicRequest.java 36-42行、CreateProjectRequest.java 66-85行。期間の重なりは職歴を足すときだけ確かめる: Resume.java 284行、343-397行。姓と名の片方だけを入れたファイルは断る: RestoreResumeUseCase.java 146-151行(両方が無いか空のときだけ氏名を作らない)。backend/src/main/java/com/example/keirekipro/domain/model/resume/FullName.java 48-69行
- requirements.md 要件4の受入基準2「ファイルの版が `1.0` でないか、版が書かれていない要求には(中略)「サポートされていないバックアップバージョンです。」の文言で答える」: RestoreResumeUseCase.java 58-59行。ResumeBackupVersion.java 15行
- requirements.md 要件4の受入基準3「今の数と上限の数を入れた、上限に達したことを示す文言」: backend/src/main/java/com/example/keirekipro/usecase/resume/policy/ResumeLimitChecker.java 26-30行
- requirements.md 要件4の受入基準4「「この職務経歴書名は既に登録されています。」の文言で答える」: backend/src/main/java/com/example/keirekipro/domain/service/resume/ResumeNameDuplicationCheckService.java 38行
- requirements.md 要件4の受入基準5「「バックアップファイルが不正なためリストアできません。」の文と「別のバックアップファイルでお試しください。」の文を改行でつないだ文言で答える」: RestoreResumeUseCase.java 135-137行
- requirements.md 要件4の受入基準5「Go 版は、Java 版と同じく、戻しでは欄ごとの項目の数を確かめない」: RestoreResumeUseCase.java 63行(戻しは経歴書の数の上限だけを確かめる)。ResumeLimitChecker.java 44-99行(欄ごとの項目の数の上限は、項目を足す操作で確かめる)
- requirements.md 要件4の受入基準6「状態の番号 400 と「入力エラーがあります。」の文言で答える」: AppExceptionHandler.java 89-92行
- requirements.md 要件5の受入基準1「状態の番号 404 と「対象の職務経歴書データが存在しません。」の文言で答える」: BackupResumeUseCase.java 43-44行
- requirements.md 要件5の受入基準2「ほかの利用者の経歴書の書き出しの要求」(Java 版は、無い経歴書と同じ答えを返す): backend/src/main/java/com/example/keirekipro/infrastructure/query/resume/ResumeQueryMapper.xml 35行、173行。BackupResumeUseCase.java 43-44行
- requirements.md 要件5の受入基準3「認証のまとまりの spec が、すでに居ない利用者の要求はログインの状態の検査を通るとし、その要求への答えを、操作を作るまとまりの spec で Java 版と同じにすると決めた」: .kiro/specs/backend-go-auth/requirements.md 113行
- requirements.md 要件6の受入基準1「置き換えの spec の設計が、まとまりごとに足すと決めた、ログインが切れたあとの要求と、偽の送信の検査に通らない要求」: .kiro/specs/backend-go-replacement/design.md 1003-1005行
- requirements.md 要件6の受入基準2「Java 版と Go 版を比べる検査は、状態の番号と、Content-Type と Content-Disposition のヘッダと、答えの本文を比べる。また(中略)データベースに残ったデータも比べる」と「JSON として読んだ値で比べる」: .kiro/specs/backend-go-replacement/design.md 588-590行
- requirements.md 要件7「版をまたいで確かめる検査」(置き換えの spec の設計は、バックアップを一方の版で書き出してもう一方の版で戻すことを、版をまたいで確かめる操作に含めた): .kiro/specs/backend-go-replacement/design.md 640-641行
- requirements.md 要件6の受入基準4「置き換えの spec の設計は、バックアップの書き出しと戻しを、測る操作に含めた」: .kiro/specs/backend-go-replacement/design.md 649行
- requirements.md 要件8の受入基準3「置き換えの spec の進み具合の表の、バックアップのまとまりの行」: .kiro/specs/backend-go-replacement/progress.md 42行
- design.md 使う既存の仕組み「未実装の答えを返す `RestoreResume` と `BackupResume`」: backend/internal/httpapi/unimplemented.go 97-98行、112-113行
- design.md 仕様書の変更「戻しの要求の本文は `ResumeBackup` を指す。書き出しの 200 の答えも `ResumeBackup` を指す。戻しの 201 の答えは `ResumeInfoCreated` である」: backend/api/openapi.yaml 665行、682行、684-685行、757行、774行、1536行、2408行
- design.md 仕様書の変更「`CreateResumeRequest` に `x-go-type: json.RawMessage` が付いている」: backend/api/openapi.yaml 1817-1819行
- design.md 戻しと書き出しの受け口「`ResumeService` のインタフェースと、出力の答えを作る `exported`」: backend/internal/httpapi/resumes.go 17行、27行、383-393行
- design.md 戻しと書き出しの受け口「経歴書の操作の答えの型を `authResponse` にする並びと `Visit` の関数」: backend/internal/httpapi/resumeresponses.go 40-42行、324-333行
- design.md ファイルの構成「28の操作と書いたコメントとテストの期待」: backend/internal/httpapi/resumes.go 57行、resumeresponses.go 12行、server.go 49行、93行、resumes_test.go 469行、618行、626-627行、844行、879-880行、933行、946行、998行、1006-1007行、1028行、backend/internal/resume/service.go 1行、31行
- design.md Service の戻し「`CreateResume` が、トランザクションの中で、経歴書の数の上限と名前の重なりを確かめてから経歴書を入れる」: backend/internal/resume/service.go 103-162行。`isUserMissing` は 186行
- design.md Service の戻し「`inTx`、`findResume`、`countResumes`、`resumeNameExists`、`insertResume`、日本の時刻の `japanZone`」: backend/internal/resume/store.go 19行、33行、55行、82行、91行、100行
- design.md Service の戻し「経歴書の問い合わせ」: backend/db/queries/resumes.sql 29行(GetResume)、63行(CountResumesByUserID)、72行(ExistsResumeName)、84行(InsertResume)
- design.md 戻しの値の決まり「今ある決まりの関数」: backend/internal/resume/rules.go 55行(checkResumeName)、85行(isPersonName)、114行(checkPeriod)。link.go 53行(equalsIgnoreCaseASCII)、269行(parseJavaURI)。exportmodel.go 187行(javaTrim)。exportbody.go 85行(maxNumberLength)、215行(numbersWithinLimit)。order.go 17行(sortEntries)。filename.go 17行(sanitizeFileName)
- design.md 失敗したとき「今ある誤り」: backend/internal/resume/errors.go 138行(errResumeNotFound)、144行(errUnreadableInput)、154行(errResumeNameDuplicated)
- design.md 失敗したとき「256文字以上のリンクはデータベースの列の長さを超える」: backend/src/main/resources/db/migration/V1__create_tables.sql 264行、280行(`link VARCHAR(255)`)
- design.md harness の広げ方「要求の `json_file` の欄と、その検査」: backend/compat/harness/scenario.go 171-173行、341-343行、383-384行、397-416行、475行。capture.go 254-257行
- design.md harness の広げ方「答えの本文をそのまま取り出す `text`」: backend/compat/harness/capture.go 31行、60-61行、148行
- design.md バックアップの操作の筋書き「`CrossRoute` の向き」: backend/compat/harness/cross.go 40行
- design.md バックアップの操作の筋書き「バックアップのまとまりは group 5」: backend/compat/harness/operations.go 22行、31行、124行
- design.md バックアップの操作の筋書き「手本の筋書き」: backend/compat/scenarios/export/deleted-user.yaml、backend/compat/scenarios/users/require-login.yaml、backend/compat/scenarios/auth/two-factor-perf.yaml 7行(prepare_each)
- design.md 初期のデータ「退会用の利用者 340 と経歴書 350」: backend/compat/fixtures/resumes/resume-ops.sql 6-7行、11行
- design.md 初期のデータ「経歴書の数が上限の利用者 500」: backend/compat/fixtures/resumes/resume-limits.sql 10行
- design.md 初期のデータ「user1 の経歴書 401」: backend/compat/fixtures/resumes/fonts.sql 6行
- design.md 初期のデータ「今の `fixtures/backups/` の4つのファイルと、その説明」: backend/compat/fixtures/backups/、backend/compat/harness/fixtures.go 16-27行(23行)
- design.md 初期のデータ「`checkBackup` が知らない名前のファイルを誤りにする」: backend/compat/harness/fixtures_test.go 194-195行、204-207行、258行、304行、327行
- design.md 変えた動きの一覧「CB-001 がバックアップの3つの欄の順だけの違いを許す。最後の番号は CB-061」: backend/compat/changed-behaviors.yaml 14-30行、775行
- design.md 変えた動きの一覧「項目の数の期待は61」: backend/compat/harness/match_test.go 328-329行
- design.md 比べる検査そのもののテスト「戻しの要求に 501 を期待する」: backend/compat/compat_test.go 92-93行、105-107行、161-165行、178行。backend/compat/cross_test.go 189-190行、202-205行。backend/compat/perf_test.go 15行、28-30行
- design.md 進み具合の表「出力の2つの操作の時間の行」: .kiro/specs/backend-go-replacement/progress.md 67-68行
- design.md 進み具合の表「状態が「作り終えた」のまとまりの操作を筋書きに求める」: backend/compat/harness/coverage.go 17行、113行
- design.md テストの方針「手本のテスト」: backend/compat/harness/cross_test.go 325行(TestCrossRoute_ExportSteps)、perfmeasure_test.go 536行(TestLoadScenarios_ExportPerf)
- design.md 戻しと書き出しの受け口「生成したコードが本文を JSON として読めなければ、400 と「入力エラーがあります。」で答える」: backend/internal/httpapi/server.go 216-219行、backend/internal/httpapi/middleware/errors.go 13行、backend/internal/httpapi/gen の RestoreResume の strictHandler(BindJSONBody の失敗で RequestErrorHandlerFunc を呼ぶ)
- design.md 戻しと書き出しの受け口「経歴書を作る受け口 `CreateResume` は `withResume` と `rawBody` で本文を渡し、答えの本文を `newResumeBody` で作る」: backend/internal/httpapi/resumes.go 160-166行、resumeresponses.go 179行
- design.md 文言の定数「`MessageResumeNotFound` と `MessageResumeNameDuplicated`」: backend/internal/resume/errors.go 20行、40行
- design.md バックアップの操作の筋書き「期待の `values` で、答えの本文の値を JSON の道筋ごとに確かめる。版をまたぐ筋書きの手本」: backend/compat/harness/scenario.go 199行、backend/compat/scenarios/export/cross-export.yaml 1-11行
- design.md 変えた動きの一覧「CB-001 は backupResume の `$.resume.portfolios[*]` `$.resume.snsPlatforms[*]` `$.resume.selfPromotions[*]` の順だけの違いを許す」: backend/compat/changed-behaviors.yaml 34-44行
- design.md 仕様書の変更「`CreateResumeRequest` は `x-go-type: json.RawMessage` を持ち、`x-go-type-import` を持たない」: backend/api/openapi.yaml 1817-1820行
- design.md 使う既存の仕組み「`checkDiffTableInChangedBehaviors`」: backend/internal/resume/difftable_test.go 17行
- design.md 使う既存の仕組み「`formatContentDisposition`」: backend/internal/httpapi/exportdisposition.go 22行
- design.md 使う既存の仕組み「経歴書の数の上限を確かめる `resumeLimit`」: backend/internal/resume/rules.go 17行、backend/internal/resume/service.go 119行
- design.md 進み具合の表「`TestCoverage_Operations`」: backend/compat/compat_test.go 64行
- design.md API の説明画面での確認「compose の `api-docs` はポート 8082」: compose.yaml 76-82行
- design.md 比べる検査そのもののテスト「違いを許す設定の状態の番号は `http.StatusNotImplemented`」: backend/compat/compat_test.go 178行
- design.md Service の書き出し「`Deps` の `Now` の時刻」: backend/internal/resume/service.go 23-25行、39-40行
- design.md Java 版の答えの正解のファイル「Java 版のイメージは `docker/backend/Dockerfile.prod` で作る」: docker/backend/Dockerfile.prod 4行、28行。試作の Java 版のイメージ `keirekipro-proto-java:local` の `docker history` の層(`rm -f /usr/bin/pebble`、`COPY /app/build/libs/*.jar app.jar`)と同じ
- design.md Java 版の答えの正解のファイル「compose のネットワーク `my-network`」: compose.yaml 36行と末尾の `networks:` の節
- design.md Java 版の答えの正解のファイル「compose が付ける名前は `keirekipro_my-network`」「`SPRING_PROFILES_ACTIVE` を `dev`」: 試作で Java 版を起動したコマンド(`docker run -d --name kp-backup-proto-java --network keirekipro_my-network -e SPRING_PROFILES_ACTIVE=dev ...`)。比べる検査も dev で動かす: backend/compat/harness/versions.go 76行
- design.md Java 版の答えの正解のファイル「dev のプロファイルは localstack の秘密の値から読む」: backend/src/main/resources/application-dev.yaml 3行、15行
- design.md Service の戻し「Java 版の名前の値の決まりは対になっていないサロゲートを断らない」: backend/src/main/java/com/example/keirekipro/domain/model/resume/ResumeName.java 18行、43-67行(正規表現の `.` はサロゲートにも当たる)
- design.md Java 版の答えの正解のファイル「`SPRING_DATASOURCE_URL` を `jdbc:postgresql://postgresql:5432/kp_backup_proto`、`SPRING_DATA_REDIS_DATABASE` を `7`」: 試作の Java 版のコンテナ `kp-backup-proto-java` の環境変数を、片付ける前に `docker inspect` で読んだ(2026-11-24)
- design.md ファイルの構成「sqlc の生成したコードは `backend/internal/platform/database/sqlcgen/`」: backend/internal/resume/store.go 15行
- design.md Java 版の答えの正解のファイル「`fonts.sql` と `backup.sql` の経歴書が user1 のもの」「経歴書を持たない user2」: backend/compat/fixtures/users/basic.sql 4-7行(user1 と user2)、backend/compat/fixtures/resumes/fonts.sql に user2 の行は無い。利用者の役の行は Flyway が入れる: backend/src/main/resources/db/migration/V2__insert_mst_data.sql 4行
- design.md Java 版の答えの正解のファイル「経歴書を消す要求 `DELETE /api/resumes/{resumeId}`」: backend/src/main/java/com/example/keirekipro/presentation/resume/controller/DeleteResumeController.java 25行、36行

## 試作の記録(要件8の受入基準1)

### 試した方法

- Claude は、Java 版と、試しに作った Go 版を、開発環境のデータベースのサーバに作った試作専用のデータベース `kp_backup_proto` に向けて、並べて動かした。Java 版は今の main のコードを、Go 版は今の main のコードに2つの操作を足した試作のコードを動かした。試作のコードと、送った要求のファイルは、リポジトリに入れていない
- Claude は、同じ要求を、1件ずつ Java 版と Go 版に送った。1件ごとに、答えの状態の番号と Content-Type と本文を控え、データベースに残った行を、行が置かれた順に書き出して控え、試作専用のデータベースを要求の前の状態に戻した
- 比べ方は次の2つである。戻しの答えは、経歴書と項目の ID と作った日時と直した日時を除いて、JSON として読んだ値で比べた。書き出しの答えは、書き出した日時の値を除いて、本文のバイトの並びと、Content-Disposition のヘッダの字で比べた

### 結果

| 試した動き | 要求の数 | 結果 |
|---|---|---|
| Java 版が書き出したファイルを Go 版で戻す | 88件 | 88件とも、答えとデータベースに残った行が同じ |
| 形の誤ったファイルと、断る条件に当たるファイルの戻し | 312件 | 312件とも、答えとデータベースに残った行が同じ |
| 退会してすでに居ない利用者の戻しと書き出し | 9件 | 5件が同じ。Java 版が 500 で答えた4件に、Go 版は 404 で答えた |
| 256文字以上のリンクを持つファイルの戻し | 3件 | 3件とも、Java 版も Go 版も 500 で答えた |
| 書き出しの本文の文字の並び | 90件 | 項目の並び方を決める方式によって変わる。次の節に書く |
| 書き出しの Content-Disposition のヘッダ | 90件 | 90件とも同じ |
| 書き出しのファイルの中の項目の並び | 3通りの手順 | Java 版の並びが、データベースの行の置かれ方で変わる。次の節に書く |

- 形の誤ったファイルには、経歴書の中身が無いファイル、6つの欄のどれかが無いファイル、項目の中に値の無い要素を持つファイル、値の型の違うファイル、知らない名前の欄を持つファイル、中身が JSON のオブジェクトでなく配列や数のファイルを含めた。画面は、選んだファイルの中身を JSON として読んだ値をそのまま送るので、中身が配列や数のファイルからは、その配列や数を本文にした要求が送られる
- 退会してすでに居ない利用者の要求で、Java 版が 500 で答えたのは、版の正しいファイル、項目の中に値の無い要素を持つファイル、経歴書の中身が無いファイル、256文字以上のリンクを持つファイルの戻しである。版の誤ったファイルと、値を読めないファイルと、値の決まりを満たさないファイルの戻しには、Java 版は、利用者が居るときと同じ 400 で答えた。書き出しには、Java 版は 404 で答えた
- Java 版は、名前に対になっていないサロゲートを含む経歴書を書き出せるが、書き出したファイルを戻すと、値の決まりを満たさないとして 400 で断る。Go 版も同じに答えた。書き出したファイルの名前は、データベースから読んだ、サロゲートを `?` にした名前であり、400 になったのは、Java 版の名前の値の決まり(ResumeName.java 18行)が `?` を使えない字とするためである。Java 版の名前の値の決まりは、対になっていないサロゲートを断らない(ResumeName.java 43-67行)。そのため、名前に対になっていないサロゲートを含むファイルを戻したときの Java 版の答えは、この試作では確かめていない
- 文字の書き方は、`<` `>` `&` `'` `/`、改行、行や段落の区切りの文字、絵文字、対になっていないサロゲートを含む経歴書で比べた。項目の並びが同じ90件では、本文のバイトの並びが同じだった
- 対になっていないサロゲートを項目に含むファイル(試作の `chars-lone`)の戻しは、Java 版も Go 版も 201 で答え、戻したあとのデータベースの字が同じだった

### Java 版の書き出しの項目の並び

- Java 版の書き出しの問い合わせ(ResumeQueryMapper.xml の selectResumeForBackup)は、6つの欄の項目を json_agg で並べ、並べる順を指定しない。プロジェクトは、技術の表 project_tech_stacks と結合して読む
- PostgreSQL は、並べる順を指定しない問い合わせの行を、表の中に行が置かれている順か、結合のやり方で決まる順で返す。試作専用のデータベースでは、プロジェクトの結合は、技術の表を置かれた順に読んで、プロジェクトを探す形になった。そのため、Java 版の書き出しのプロジェクトの並びは、技術の表の行の置かれ方で決まった
- PostgreSQL は、消した行の場所に、あとから入れた行を置くことがある。Java 版は、経歴書を保存するたびに項目の行を消して入れ直すので、入れ直した行は、入れた順に置かれるとは限らない
- 次の3つを確かめた
  - Java 版で同じファイルを2回戻し、それぞれを Java 版で書き出した。1回目のファイルのプロジェクトは、経歴書を読み出すときと違う順に並び、2回目のファイルのプロジェクトは、経歴書を読み出すときと同じ順に並んだ。2回の違いは、その前にデータベースで消した行の数だけである
  - 開発環境の見本の経歴書2件を Java 版で書き出すと、2件以上の項目を持つ職歴、プロジェクト、資格は、経歴書を読み出すときの逆の順に並んだ。見本のデータは、古い項目から順に入れてあるためである
  - Java 版の API で、戻した経歴書に職歴と資格を足し、職歴を1件直した。Java 版の書き出しの並びは、経歴書を読み出すときと同じ順だった。同じ手順を Go 版の API で行い、Java 版で書き出すと、職歴と資格の並びは、経歴書を読み出すときと違う順になった。Go 版は、項目を足すときと直すときに、ほかの項目の行を入れ直さないためである
- そのため、Java 版が同じ経歴書を書き出したときの並びは、1つに決まらない。Go 版の並べ方を次の2通りで試した
  - Java 版と同じ問い合わせで読む方式: 同じデータベースを読めば、Java 版と同じ並びになった(90件とも本文のバイトが同じ)。一方で、Go 版の API で項目を足したり直したりした経歴書では、項目は、Java 版で同じ手順を行ったときと違う並びになった
  - 経歴書を読み出すときと同じ順に並べる方式: 90件のうち83件で、本文のバイトが Java 版と同じだった。違った7件は、上の1つ目と2つ目に当たる経歴書で、項目の並びのほかは同じだった。Go 版の API で項目を足したり直したりした経歴書では、Java 版で同じ手順を行ったときと同じ並びになった
- どちらの方式でも、戻した経歴書と、画面と PDF に出る項目の並びは変わらない。Java 版と Go 版は、戻すときに項目を経歴書を読み出すときと同じ順に並べ替えて入れ、画面と PDF は経歴書を読み出すときの順に並べるためである。並びの違いが出るのは、利用者がバックアップのファイルをテキストエディタで開いたときだけである

## 設計の段階で調べたこと

- 機能の種類: 今の Go 版の `internal/resume` と `internal/httpapi` と、比べる検査の harness に足す拡張である。Claude は、軽い調べ方(design-discovery-light)で、足す先の作りと、手本にする今のコードを調べた。新しい外部のライブラリと外部の API は使わないので、外部の資料は調べていない
- 手本にした今の作り: 経歴書を作る `CreateResume` の確かめる順とトランザクション、出力の spec の受け口 `exported`、出力の spec の本文の読み手の数の長さの上限、出力の spec の筋書きと初期のデータの置き方、マスタと経歴書の spec の退会した利用者の筋書き
- 試作のコードは scratchpad にあり、リポジトリに入れていない。Claude は、設計の部品の分け方を、試作のファイルの分け方(書き出し、本文の読み手、値の決まり、JSON の書き手、WTF-8 の扱い、JSON の読み手)に合わせた

### 危うい点

- Java 版の答えの正解のファイルは、実装のはじめに Java 版から控える。控えたときに、試作の記録と違う答えが見つかったら、Claude は、要件8の受入基準2のとおり止まって所有者に報告する
- 画面が送らない要求(JSON として読めない本文、Content-Type が JSON でない本文、Accept が JSON でない書き出し、ID の形でない書き出し)への Java 版の答えは、試作では一部しか控えていない。違う答えは、正解のファイルを控えたときに変えた動きの一覧に足す
- Java 版の書き出しの項目の並びは、データベースの行の置かれ方で変わる。比べる検査は書き出しの答えの項目の順を比べないので、検査は、この並びのゆれで止まらない

## 設計の決めごと

### 一般化

- 筋書きの要求に、前の段で取り出した値をそのまま JSON の本文にして送る欄 `json_capture` を足す。版をまたぐ筋書きは、一方の版が書き出したバックアップのファイルを、書き写さずにもう一方の版に送れる。ほかのまとまりの筋書きも、前の段の答えの本文を次の段に送るときに使える
- Java 版の答えの書き方で JSON を書く書き手 `JavaJSON` を、バックアップのファイルと戻しの 201 の答えの両方に使う。2つの答えは、同じ経歴書の値を Java 版の Jackson の書き方で書くためである

### 作るか使うか

- JSON の書き手と、対になっていないサロゲートを保つ JSON の読み手は、ライブラリを足さずに Go で作る。Go の `encoding/json` は `<` `>` `&` と行や段落の区切りを番号で書き、対になっていないサロゲートを U+FFFD に置き換えるので、Java 版と同じ字の並びを書けず、同じ値を読めない。試作で、作った書き手と読み手が Java 版と同じ字と値になることを確かめた
- 退会してすでに居ない利用者かどうかは、sqlc の問い合わせを1つ足して確かめる。今の `isUserMissing` は経歴書の行を入れたときの外部キーの誤りだけを見るので、行を入れる前に断る要求では、利用者が居ないことが分からない
- ファイル名は出力の spec の `sanitizeFileName` を、Content-Disposition は出力の spec の `exported` をそのまま使う
- 数の長さの上限は、出力の spec の `numbersWithinLimit` をそのまま使う

### 簡素化

- 書き出しの項目は、経歴書を読み出すときと同じ順(`sortEntries`)に並べる。Java 版と同じ問い合わせを作らずに、今の経歴書の読み取りをそのまま使える
- 比べる検査の戻しの要求には、実装のはじめに Java 版から控えたバックアップのファイルを `json_file` で送る。比べる検査では、版ごとに取り出した値が分かれるので、一方の版が書き出したファイルを両方の版に送れないためである
- 戻しの時間を測る筋書きは、段を測る前に毎回、利用者の経歴書を消す(`prepare_each`)。同じファイルを繰り返し戻すと、名前の重なりで断られるためである
- 退会してすでに居ない利用者の要求で Java 版が 500 で答えるものは、要求ごとに分けて調べず、トランザクションのあとに利用者が居るかを1回確かめて 404 にする
- 比べる検査そのもののテストは、戻しの要求の期待を 501 から 400 に変える。この spec で、すべての操作が作り終わり、未実装の答えを返す操作が無くなるためである
