## サイクル1 往復1(2026-11-13)

### 審査の範囲

範囲: 全体

### 実ファイルで確かめた文

- タスク1.1「`storedUser` と `loadStoredUser` と `loadStoredUserOr` を使うのは `emailverification.go` と `oidccallback.go` と `passwordreset.go`」: backend/internal/auth/emailverification.go 385、410、430、460、468、473、524行、oidccallback.go 538〜703行、passwordreset.go 112、122行(`loadStoredUserOr` と `saveUser`) / 合っていた。テストのファイルには `storedUser` も `loadStoredUser` も無い(design と research.md の文は食い違う。T1-1-4)
- タスク1.1「欄の名前を `Row` `Providers` `Roles` にする」: backend/internal/auth/emailverification.go 460〜465行(`row` `providers` `roles`)、passwordreset.go 120行(`u.row.Password`) / 合っていた
- タスク1.1 と design 公開した認証の処理の表「今ある関数」: backend/internal/auth/emailverification.go 180行(`clearCurrentEmailVerification`)、199行(`sendEmailVerification`)、548行(`inTransaction`)、accesstoken.go 102行(`BumpTokenVersion` は公開済み)、refreshtoken.go 127行(`removeAllRefreshTokens`)、login.go 222行(`findAccountByEmail`)、300行(`passwordMatches`)、errors.go 128行(`errCredentialsNotFound`)、commonsemail.go 62行(`emailCreateErrors`)、validate.go 133、145、158、172、211行(`notBlank` `isJavaWhitespace` `utf16Len` `passwordPatternOK` `isEmailLikeHibernate`)、cookies.go 68行(`DeleteCookie`) / 合っていた
- タスク1.2「開発環境の `spring` のコンテナ」「所有者の開発のデータベース `keireki_pro` と Redis の DB 0」「LocalStack の SES」: compose.yaml 15行(spring)、145行(keireki_pro)、176行(4566) / 合っていた
- タスク1.2「正解のファイルの置き場所 `internal/auth/testdata/mail/`」: backend/internal/auth/mail_test.go 19〜22、42行(`testdata/mail` の `<種類>.json` `<種類>.values.json` `app.json` を `fs.ReadFile(os.DirFS(...))` で読む) / 合っていた(今の正解は `.json`。`user-deleted.txt` は新しい形だが、設計の決めなので指摘しない)
- タスク1.4「`make generate` と `make generate-check`」: backend/Makefile 38〜137行(generate、generate-check、lint、test、coverage、build、compat、compat-cross、compat-perf の標的がある) / 合っていた
- タスク1.5「`backend/.golangci.yml` の depguard の機能のパッケージの規則の許す一覧」「所有者の承認が要る」: backend/.golangci.yml 20〜56行(feature の規則、allow は internal/platform だけ)、.github/CODEOWNERS 34行、.github/scripts/check-escape-hatches.sh 217行(`backend/.golangci.yml` をゲート設定として所有者の承認を求める) / 合っていた
- タスク1.6「偽の AWS の S3 の受け口は `http.ServeMux` で振り分け、`r.PathValue` で名前を読む」: backend/compat/fakeaws/fakeaws.go 69〜99行、s3.go 43〜93行 / 合っていた
- タスク1.6 と実装のメモ「`go test -tags compat ./compat/fakeaws/...`」「今ある `fakeaws_test.go`」「`backend/compat/` の下のファイルはすべて `//go:build compat`」: backend/compat/fakeaws/fakeaws_test.go があり、compat 配下の 61 ファイルすべてに `//go:build compat` がある / 合っていた
- タスク1.7「`backend.Migrations()` を `migrate.Run` の `Apply` で流す」「testcontainers-go で Postgres と Valkey」「`backend/compat/fakeaws/Dockerfile`」: backend/migrations.go 18行、backend/internal/auth/main_integration_test.go、backend/compat/fakeaws/Dockerfile / 合っていた
- タスク2.4 と design「生成したコードは中間処理の前に `r.MultipartReader()` を呼ぶ」: backend/internal/httpapi/gen/api.gen.go 9552〜9582行(research.md 179行の記録のとおり) / 合っていた
- タスク4.2「`server.go` の `Options` と `routes`、`NewStrictHandlerWithOptions` の中間処理の並び」「`main.go` と `main_test.go`」: backend/internal/httpapi/server.go 29〜111行、backend/cmd/keirekipro/main.go、main_test.go / 合っていた
- タスク5.1〜5.7「`scenario.go` `send.go` `steps.go` `normalize.go` `compare.go` `compareenv.go` `cross.go` `crossenv.go` `perfenv.go` と、`modes_test.go` の `TestCompareEnv_NewSteps`」: backend/compat/harness/ に全ファイルがあり、modes_test.go 385行に `TestCompareEnv_NewSteps` がある。`harness/multipart.go` `steps_test.go` は無い(新しく作る) / 合っていた
- タスク5.3 と design「比べる検査の AWS の接続先は偽の AWS のポート 4566」「絶対の URL の段は `fakeoidc` だけを書き換える」: backend/compat/harness/steps.go 16〜54行(`fakeoidcHost` の置き換えだけ) / 合っていた
- タスク5.6「今の画像の置き場所の比べ方は名前とバイトの並び」: backend/compat/harness/compare.go 514〜551行 / 合っていた
- タスク5.7「`make compat` と `make compat-cross` が CI で動く」: .github/workflows/ci.yaml 506、509行 / 合っていた。`make compat-perf` は Makefile 134行のとおり PR の検査では動かさない
- タスク5.8「CB-028 とする」「CB-020 は match を書かない」: backend/compat/changed-behaviors.yaml 235〜241行(CB-020)、301〜307行(CB-027 が最後) / 合っていた
- タスク5.8 と6.5「`TestLoadChangedBehaviors` と `match_test.go`」: backend/compat/harness/match_test.go がある / 合っていた
- タスク6.6「`backend/compat/harness/cross_test.go`」「CI で動く `make compat-cross` の `TestCross_` の検査」: backend/compat/harness/cross_test.go 56〜60行(`TestCrossRoute_AuthProcedureSteps` が同じ形の先例)、backend/compat/cross_test.go 112〜264行(`TestCross_` の4つ)、Makefile 131〜132行 / 合っていた
- タスク6.7「`make compat-perf` と `progress.md` の決まり」: Makefile 135〜136行、.kiro/specs/backend-go-replacement/progress.md 46〜60行 / 合っていた
- タスク7.1「compose の `api-docs`(ポート 8082)」「`backend-go`」: compose.yaml 40〜95行 / 合っていた
- タスク7.2「状態の列を「作り終えた」にすると、検査が利用者の7つの操作を筋書きに求め始める」「`TestCoverage_Operations`」: backend/compat/compat_test.go 28〜89行(`requireAllOperations = false`、`LoadCompletedGroups`)、backend/compat/harness/coverage.go 17行(`completedStates` は「作り終えた」「比べる検査に通った」「本番で動いている」)、23〜91行 / 合っていた
- タスク7.2「利用者の行は spec の列に `.kiro/specs/backend-go-users`、状態は「spec の作成中」」: .kiro/specs/backend-go-replacement/progress.md 36〜37行 / 合っていた。認証の行(36行)は PR のマージ後も「作り終えた」のまま(T1-1-1 の根拠)
- 実装のメモ「`run-check.sh backend-go` と `--wait`、順番待ちの表示」: .claude/scripts/parallel/run-check.sh 5、89〜99、138〜146行 / 合っていた
- 実装のメモ「この PC の `keirekipro.parallelSlots` は1」: 設定は書かれておらず、CLAUDE.md の初期値1が使われる / 合っていた
- 実装のメモ「`.golangci.yml` は `nosec: true`」「gosec の G101 と G124」: backend/.golangci.yml 20〜26行、.kiro/specs/backend-go-auth/tasks.md 367〜368行 / 合っていた
- 実装のメモ「`curl localhost:4566/_aws/ses`」「`XSRF-TOKEN`」「逆斜線と u の並びは perl で `\x5c`」: .kiro/specs/backend-go-auth/tasks.md 365、375行 / 合っていた
- 実装のメモ「`ResetPassword` はトランザクションの中で `BumpTokenVersion` にトランザクションの問い合わせを渡し、続けて `removeAllRefreshTokens` を呼ぶ」: backend/internal/auth/passwordreset.go 111〜132行 / 合っていた
- 完了条件の4項目「壊した写しの作り方は `.kiro/steering/tech.md` の「テストの完全性」」: .kiro/steering/tech.md 59〜72行、.kiro/settings/templates/specs/tasks.md 31〜38行(雛形と同じ文) / 合っていた

### 確かめの道具を作るタスク

| 道具 | 作るタスク | 確かめる成果物を作るタスク | 並び |
|---|---|---|---|
| `exported_integration_test.go` の `TestExported`(公開した関数が元の関数と同じ結果) | 1.1 | 1.1 | 同じタスク |
| 正解のファイル(`testdata/multipart/` `testdata/username/` `testdata/jdkutf8/` `testdata/multipart/java-checks/` `testdata/mail/user-deleted.txt`) | 1.2 | 1.3、2.1、2.2、2.4、3.7 | 前 |
| `TestMail_UserDeletedMatchesJava` `TestMail_UserDeletedNoUsername` | 1.3 | 1.3 | 同じタスク |
| `make generate-check`(既存) | 無い(置き換えの spec で作ってある) | 1.4 | 前 |
| `make lint`(既存の depguard) | 無い(置き換えの spec で作ってある。規則は 1.5 で変える) | 1.5 | 前 |
| `s3_test.go` の `TestS3_DoubleSlashKey`、既存の `fakeaws_test.go` | 1.6 | 1.6、1.7、3.2、5.7 | 前 |
| 結合テストの土台 `TestMain`(Postgres、Valkey、偽の AWS)と `TestIntegrationSetup` | 1.7 | 3.2、3.4、3.5、3.6、3.7、3.8、3.9 | 前 |
| `TestJDKUTF8_MatchesJava` `TestContentDisposition_MatchesJava` `TestMultipart_*` `TestUpdateUserInfoBody_*` | 2.1、2.2、2.3、2.4 | 同じ番号のタスク | 同じタスク |
| `TestCheckImage_*` `TestPresign_*` `TestObjectStore_*` `TestValidate_*` `TestRemoveAuthProvider_*` `TestSendAccountEmailVerification_*` `TestGetUserInfo_*` `TestUpdateUserInfo_*` `TestDeleteUser_*` `TestChangePassword_*` `TestSetEmailAndPassword_*` | 3.1〜3.9 の同じタスク | 同じ番号のタスク | 同じタスク |
| 署名付きの URL の正解を作る Java のプログラム(`internal/users/testdata/presign/`) | 3.2 | 3.2 | 同じタスク(先に作る) |
| `TestUserHandlers_*` `TestUserResponses*` | 4.1 | 4.1 | 同じタスク |
| `TestNew_UserOperationsNotUnimplemented` `TestNew_UpdateUserInfoNonMultipart400`、`main_test.go` の場合 | 4.2 | 4.2 | 同じタスク |
| `/verify-backend`(`make check`。既存) | 無い(スキルとして既にある) | 3.9、4.2、5.8、6.7、7.2 | 前 |
| 筋書きの5つの欄と読み込みの確かめ(`TestScenarioValidate_UserFields`) | 5.1 | 6.1〜6.7 の筋書き | 前 |
| multipart の本文の組み立てと `body_file` の送り(`TestMultipartBody_*` `TestSend_BodyFile`) | 5.2 | 6.1〜6.7 の筋書き | 前 |
| `localhost:4566` の書き換えと `Host`(`TestAbsoluteURL_FakeAWSRewrite`) | 5.3 | 6.1、6.2、6.3、6.6 の絶対の URL の段 | 前 |
| `expect.values` `expect.body_file` `expect.content_type` の確かめ(`TestExpect*`) | 5.4 | 6.1、6.2、6.6 | 前 |
| 署名の値の正規化(`TestNormalize_PresignedURL`) | 5.5 | 6.1、6.2、6.4(`$.profileImage` の比べ) | 前 |
| 画像の置き場所の `Content-Type` とメタデータの比べ(`TestCompareObjects_ContentTypeAndMetadata`) | 5.6 | 6.2、6.3 | 前 |
| 3つの動かし方への接続(`TestCompareEnv_UserFields` `TestCrossEnv_UserFields` `TestPerfEnv_UserFields`)と、認証の筋書きでの `make compat` `make compat-cross` | 5.7 | 6.1〜6.7 | 前 |
| 並びの順の CB 項目(CB-028 ほか)と `TestChangedBehaviors_UserItems`、既存の `TestLoadChangedBehaviors` | 5.8 | 6.1〜6.5 の筋書き | 前 |
| 初期のデータ `users-ops.sql`、`wide.png`、`not-image.png` | 6.1 | 6.1〜6.7 | 前(6.1 は同じタスクの中で先に作る) |
| `make compat`(既存の `TestCompare_Scenarios`) | 無い(置き換えの spec で作ってある) | 6.1〜6.5 | 前 |
| `TestCrossRoute_UserSteps`(`harness/cross_test.go`) | 6.6 | 6.6 の3つの cross の筋書き | 同じタスク(先に作ると書いてある) |
| `make compat-cross`(既存の `TestCross_`) | 無い(置き換えの spec で作ってある) | 6.6 | 前 |
| `make compat-perf`(既存の `TestPerf_`)と `progress.md` の表 | 無い(置き換えの spec で作ってある) | 6.7 | 前 |
| Playwright と compose の `api-docs`(既存) | 無い(開発環境に既にある) | 7.1 | 前 |
| `TestCoverage_Operations`(既存)と `completedStates` | 無い(置き換えの spec で作ってある) | 7.2、6.1〜6.5 | 前 |

### 申告

**1. 進み具合の表を「比べる検査に通った」にする作業を、この spec のタスクの外に出した** — タスク7.2

- Issue の記載: なし。要件7の受入基準3は、比べる検査に通ったら「比べる検査に通った」にすると決めている
- 決めたこと: 7.2 は「作り終えた」までを扱い、「比べる検査に通った」は、この PR のマージ後の別の PR で書き換える。別の PR を出す時期と受け持ちはタスクに無く、PR の本文に残ると書くだけ
- 他にありえた選択肢: この spec のタスクに、マージ後に Claude が同じセッションで書き換えの PR を出す小タスクを足す。または、`/ship` のあとの手順として実装のメモに書く
- 外れていた場合: 認証の行と同じく、利用者の行が「作り終えた」のまま残り、要件7の受入基準3を満たさない(T1-1-1)

**2. Java 版の正解を、開発環境でもう1つ動かした Java 版から取り直す** — タスク1.2

- Issue の記載: なし
- 決めたこと: 試作の12通りと27通りの入力が research.md に一覧で残っていないので、1.2 で Java 版をもう1つ動かし、入力を作り直して正解のファイルを作る
- 他にありえた選択肢: research.md に残る例だけを正解にする。比べる検査の筋書き(6.2)だけで確かめ、単体テストの正解を持たない
- 外れていた場合: 作り直した入力が試作の入力と違えば、試作で「同じ」と判定した根拠と単体テストの正解がずれる。1.2 の文は research.md の例を含めると決めているので、ずれは広がらない

**3. 署名付きの URL の正解を、小さな Java のプログラムで作る** — タスク3.2

- Issue の記載: なし。design のテストの方針は「試作で Java 版と1文字も違わなかった URL」と比べると書く
- 決めたこと: research.md に試作の URL の実値が残っていないので、AWS SDK for Java の署名の部品を決まった時刻と資格情報で動かす Java のプログラムを `internal/users/testdata/presign/` に置き、spring のコンテナで動かして正解を作る
- 他にありえた選択肢: 開発環境の Java 版の `GET /api/users/me` の答えから URL を控え、時刻と署名を取り除いた形だけを比べる
- 外れていた場合: Java のプログラムの依存の版や設定が Java 版の `S3ObjectStore` と違えば、Java 版が返さない URL を正解にしてしまう。比べる検査(6.1)の `$.profileImage` の形の比べが最後の網になる

**4. 変えた動きの項目の受け入れを、実装の途中で所有者に求める** — タスク5.8、6.5

- Issue の記載: なし。置き換えの spec は、変えた動きの一覧に載せると決めている
- 決めたこと: 6.5 で、5.8 と 6.5 で足したすべての項目の一覧と理由を所有者に示し、受け入れた日を項目に書く。受け入れまで実装が止まる
- 他にありえた選択肢: design の段階で承認を受けた項目(design の節「変えた動きの一覧の項目」の4種類)は design の承認日を書き、実装で見つかった項目だけを所有者に示す
- 外れていた場合: 所有者の返事を待つ時間が実装の途中に入る。項目の中身は design で承認済みなので、作り直しにはならない

- `- [ ]*` の省略可の印は無い

### 指摘

| ID | レベル | 該当箇所 | 内容 | 直し方の案 |
|---|---|---|---|---|
| T1-1-1 | 中 | tasks.md タスク7.2 | 要件7の受入基準3「比べる検査に通ったら「比べる検査に通った」にする」を、7.2 は「別の PR で書き換える」と書いて扱わず、別の PR を誰がいつ出すかを決めていない。PR の本文に残すだけでは実行されない。progress.md 36行の認証の行は、認証の spec の PR のマージ後も「作り終えた」のままで、同じ先送りが実際には起きなかったことを示す。この受入基準を確かめるタスクが無いまま承認すると、利用者の行も「作り終えた」のまま残る | 7.2 の次に小タスク7.3 を足し、「この PR のマージを確かめたあと、同じセッションで Claude が、利用者の行を「比べる検査に通った」にする PR を出す。認証の行も同じ PR で「比べる検査に通った」にするかを所有者に尋ねる」のように、受け持ちと時期を書く。または実装のメモに、`/ship` のあとの手順として同じ内容を書く。design の進み具合の表の節は「比べる検査が CI で通った PR で」と書くだけで、別の PR とは決めていないので、design を直さずに足せる |
| T1-1-2 | 低 | tasks.md タスク3.7 | `TestUpdateUserInfo_UsernameMatchesJava` を単体テスト `update_test.go` に置き、1.2 の27通りの正解と比べると書く。27通りには NUL を含む名前が入る(1.2 の完了の確かめ方)が、research.md 71行のとおり、その場合の Java 版の答えは PostgreSQL の誤りによる 500 で、データベースを使わない単体テストでは再現できない | 3.7 に、NUL を含む名前の場合は `update_integration_test.go` で確かめるか、単体テストでは比べる対象から外すと書く |
| T1-1-3 | 低 | tasks.md タスク1.7、2.4 | 大きなまとまり1と2の最後のタスクなのに、3.9、4.2、5.8、6.7、7.2 のように「完了条件の2つ目のとおり `/verify-backend` も通る」と書いていない。完了条件は全タスク共通なので実装に影響しないが、書き方が揃っていない | 1.7 と 2.4 の完了の確かめ方に同じ文を足す |

### 前の段階への指摘

| ID | 対象 | 該当箇所 | 内容 |
|---|---|---|---|
| T1-1-4 | design | design.md `## ファイルの構成` の「Claude が変えるファイル」の1つ目「`storedUser` を使うテストのファイル」と、research.md 195行「accesstoken_integration_test.go、emailverification_integration_test.go、login_integration_test.go、middleware_integration_test.go、middleware_test.go」 | `backend/internal/auth/` のテストのファイルに、型 `storedUser` と `loadStoredUser` `loadStoredUserOr` `saveUser` を使う箇所は無い(`*_test.go` を Grep して0件)。テストにあるのは別の名前の補助の関数 `insertStoredUser`(emailverification_integration_test.go 326行、oidc_integration_test.go 661行ほか)で、型の名前を改めても変える必要が無い。research.md が挙げた5つのファイルのうち、`insertStoredUser` を使うのは emailverification_integration_test.go だけである。tasks 1.1 は3つの実装のファイルだけを挙げており、tasks 側は正しい。design と research.md の文を「テストのファイルは変えない」に直すのが望ましい |
| T1-1-5 | design | design.md `## テストの方針` の「`objectstore.go`: …試作で Java 版と1文字も違わなかった URL と同じになること」 | research.md の試作の記録(P2)は、URL の実値を残していない。そのため、tasks 3.2 は正解を Java のプログラムで作り直すことにした(申告3)。design の文の「試作で…URL」は、正解のもとが無い。design を直すなら「Java 版と同じ署名の部品を決まった時刻と資格情報で動かして作った URL」にする |

- 往復: 1回目 / 高0 中1 低2

## サイクル2 往復1(2026-11-13)

### 審査の範囲

範囲: 全体

### 実ファイルで確かめた文

- タスク1.1「`storedUser` と `loadStoredUser` と `loadStoredUserOr` を使うのは `emailverification.go` と `oidccallback.go` と `passwordreset.go` で、`internal/auth` のテストのファイルは `storedUser` を使わない」: backend/internal/auth/ を Grep し、該当は emailverification.go 15件、oidccallback.go 24件、passwordreset.go 1件だけで、`*_test.go` には無い / 合っていた
- タスク1.1「欄の名前を `Row` `Providers` `Roles` にする」(今は `row` `providers` `roles`): backend/internal/auth/emailverification.go 460〜464行 / 合っていた
- タスク1.1「`exported.go` の関数を、今ある関数を呼ぶだけの関数にする」: emailverification.go 180、199、468、473、524、548行、accesstoken.go 102行、refreshtoken.go 118行(`invalidateSessions` は世代の番号を上げてから値を消す)、127行、login.go 222、300行、errors.go 80、99、116、128行、validate.go 45、133、145、158、172、211行、commonsemail.go 62行 / 合っていた。`HashPassword` にあたる関数は無く、register.go 61行と passwordreset.go 116行が `bcrypt.GenerateFromPassword` を直に呼ぶ(実装に影響しないので指摘しない)
- タスク1.1「`exported_integration_test.go` の `TestExported`」が使う結合テストの土台: backend/internal/auth/main_integration_test.go 24〜85行 / 合っていた
- タスク1.2「research.md の試作の記録の「確かめた環境」」「`keireki_pro` と Redis の DB 0 に触れない」「試作の12通りと27通りの入力が一覧で残っていない」「`61 E3 81 62` と `61 F4 90 80 80 62`」: .kiro/specs/backend-go-users/research.md 9〜15、53、68〜71行 / 合っていた
- タスク1.2「`internal/auth/testdata/mail/`」: backend/internal/auth/testdata/mail/ に今は `.json` の正解と `app.json` がある / 合っていた
- タスク1.4「Java 版の `UserMapper.xml` の削除の問い合わせ」と design の11の表: backend/src/main/java/com/example/keirekipro/infrastructure/repository/user/UserMapper.xml 153〜281行 / 合っていた(順も design の表と同じ)
- タスク1.4「`make generate` と `make generate-check`」: backend/Makefile 38、48行 / 合っていた
- タスク1.5「depguard の機能のパッケージの規則の許す一覧」: backend/.golangci.yml 43〜56行(feature の allow は internal/platform だけ) / 合っていた
- タスク1.5「この変更は所有者の承認が要る」: .github/CODEOWNERS 34行 / 合っていた
- タスク1.6「偽の AWS の S3 の受け口は `http.ServeMux` で振り分け、名前を `r.PathValue` で読む」: backend/compat/fakeaws/fakeaws.go 80〜92行、s3.go 43〜44、59、93行 / 合っていた。`s3_test.go` は今は無い(新しく作る)
- タスク1.6「今ある `fakeaws_test.go`」: backend/compat/fakeaws/fakeaws_test.go / 合っていた
- タスク1.7「`backend.Migrations()` を `migrate.Run` の `Apply` で流す」: backend/migrations.go 18行、backend/internal/platform/migrate/migrate.go 29、119行、backend/internal/auth/main_integration_test.go 66〜71行 / 合っていた
- タスク1.7「偽の AWS のコンテナは `backend/compat/fakeaws/Dockerfile` から組み立てる」: backend/compat/fakeaws/Dockerfile 1〜24行(文脈は ./backend) / 合っていた。名前の無いホストの要求は共有の版の記録に入る(fakeaws.go 103〜113行)ので、結合テストから直に使える
- タスク2.2「Spring 7.0.10 の `ContentDisposition.parse`」: research.md 11、59行 / 合っていた
- タスク2.4 と4.2「生成したコードは中間処理より前に multipart でない本文を断る」「400 と `{"message": "入力エラーがあります。", "errors": {}}`」: backend/internal/httpapi/gen/api.gen.go 9552〜9569行、server.go 84〜86行、middleware/errors.go 13、27〜30行 / 合っていた
- タスク3.2「`application-dev.yaml` と同じ接続先 `http://localstack:4566`、地域 `ap-northeast-1`、資格情報 `dummy`、パスの形の設定、置き場所 `keirekipro-storage`」: backend/src/main/resources/application-dev.yaml 15〜22行、application.yaml 65行 / 合っていた
- タスク3.2「`run-check.sh backend` は `spring` と同じイメージの1回きりのコンテナで、作業フォルダの `backend/` を読み込む」「コマンドをシェルを通さずに動かす」: .claude/scripts/parallel/run-check.sh 145、221〜238行(`sh -c 'exec "$@"'`)、compose.yaml 14〜26行(backend のサービスは container_name spring、`./backend:/home/spring/app`) / 合っていた
- タスク3.2「手順1で Gradle が取ってきた jar を、手順3が同じ置き場から読める」: run-check.sh 222行(Gradle の置き場は枠ごとのボリューム `kp-gradle-home-<枠>` の /root/.gradle)、docker/backend/Dockerfile 1〜4行 / 置き場は同じだが、`dependencies` の出力を作るだけでは jar が取ってこられない見込みがある(T2-1-3)
- タスク3.2「`build.gradle` を変えない」「Java のプログラムを `internal/users/testdata/presign/` に置いても Java の書式の検査に入らない」: backend/gradle/quality.gradle 26〜28行(spotless の対象は `src/**/*.java`) / 合っていた
- design の ObjectStore と タスク5.3「Java 版は URL の中の AWS の接続先のホストを `localhost` に置き換えるので、比べる検査では `localhost:4566` になる」: backend/src/main/java/com/example/keirekipro/infrastructure/shared/aws/s3/LocalstackPresignedUrlTransformer.java 19〜31行、backend/compat/harness/versions.go 46〜47行、stack.go 229行 / 合っていた
- タスク3.4〜3.9 と要件1の受入基準6「利用者が居なければ 401 と「不正なアクセスです。」」: backend/src/main/java/com/example/keirekipro/usecase/user/ の7つのユースケース(GetUserInfoUseCase.java 39行、UpdateUserInfoUseCase.java 74行、DeleteUserUseCase.java 43行、SendAccountEmailVerificationUseCase.java 41行、SetEmailAndPasswordUseCase.java 53行、ChangePasswordUseCase.java 40行、RemoveAuthProviderUseCase.java 35行) / 合っていた。7つすべてが同じ例外を投げる(T2-1-2 の根拠)
- タスク4.2「`Options` に `UserHandlers` を足し、`routes` に深さ1で埋め込む」「中間処理の並び」: backend/internal/httpapi/server.go 29〜58、74〜82行 / 合っていた
- タスク4.2「`main_test.go`」: backend/cmd/keirekipro/main_test.go / 合っていた
- タスク5.1〜5.7「`scenario.go` `send.go` `steps.go` `normalize.go` `compare.go` `compareenv.go` `cross.go` `crossenv.go` `perfenv.go`」と今あるテストのファイル: backend/compat/harness/ にすべてあり、scenario_test.go、send_test.go、normalize_test.go、compare_test.go、modes_test.go、cross_test.go、match_test.go がある。`steps_test.go` と `harness/multipart.go` は無い(新しく作る) / 合っていた
- タスク5.1「筋書きの今の欄」と design の筋書きの場面(`oidc_users` `email_verified`、Redis を書き換える段、期限切れにする段、`cookie` の取り出し): backend/compat/harness/scenario.go 43〜171行 / 合っていた
- タスク5.3「今の絶対の URL の段は `fakeoidc` だけを書き換える」: backend/compat/harness/steps.go 16〜37行 / 合っていた
- タスク5.7「今ある `TestCompareEnv_NewSteps` と同じ `modes_test.go`」: backend/compat/harness/modes_test.go 385行 / 合っていた
- タスク5.8「CB-028 とする」: backend/compat/changed-behaviors.yaml 301行(CB-027 が最後) / 合っていた
- タスク5.8と6.5「`TestLoadChangedBehaviors`」: backend/compat/harness/match_test.go 247、313行(`TestLoadChangedBehaviors_RequiredFields` と `_CB005HasNoMatch`。`-run` の正規表現で両方に当たる) / 合っていた。match.go 100〜124行の読み込みの確かめは受け入れた日を求めないので、5.8 で日の無い項目を足しても通る
- タスク5.8「`/verify-backend` は `-tags compat` のテストを流さない」: backend/Makefile 85〜86、101〜104、127〜128行、.claude/skills/verify-backend/SKILL.md 45〜48行 / 合っていた
- タスク6.6「`TestCrossRoute_UserSteps` を `backend/compat/harness/cross_test.go` に作る」「CI で動く `make compat-cross` の `TestCross_`」: backend/compat/harness/cross_test.go 60行(`TestCrossRoute_AuthProcedureSteps` が先例)、backend/compat/cross_test.go 112〜264行、.github/workflows/ci.yaml 506、509行 / 合っていた
- タスク7.1「compose の `api-docs`(ポート 8082)」「`backend-go`」: compose.yaml 40〜82行 / 合っていた
- タスク7.2「状態の列を「作り終えた」にすると、筋書きに出てくる操作が足りているかの検査が利用者の7つの操作を求め始める」「`TestCoverage_Operations`」: backend/compat/compat_test.go 28〜89行、backend/compat/harness/operations.go 26〜31行(利用者のまとまりは GroupUsers) / 合っていた
- タスク7.2「利用者の行は今「spec の作成中」、認証の行は「作り終えた」」: .kiro/specs/backend-go-replacement/progress.md 36〜37、43行 / 合っていた
- タスク7.2「この PR は、必須のチェックが通るとすぐに自動でマージされる」: .github/CODEOWNERS 34行(`/backend/.golangci.yml` は所有者の承認が要る)、.claude/skills/ship/SKILL.md 146〜157行(CODEOWNERS の承認待ちでは `reviewDecision` が `REVIEW_REQUIRED` になり、承認を待つ) / 食い違っていた(T2-1-1)
- タスク7.3「`/ship` で、この spec の PR がマージされたことを確かめる」: .claude/skills/ship/SKILL.md 109〜172行(マージまで見届け、承認待ちのあいだは承認を待つコマンドを裏で動かす) / 合っていた
- 実装のメモ「`run-check.sh backend-go <コマンド>`」「`--wait`」「2つ目以降は順番待ちの表示だけを出して終わる」: .claude/scripts/parallel/run-check.sh 5〜7、138〜194、224〜228行 / 合っていた
- 実装のメモ「`.golangci.yml` は `nosec: true`」: backend/.golangci.yml 20〜26行 / 合っていた
- 実装のメモ「`ResetPassword` はトランザクションの中で `BumpTokenVersion` にトランザクションの問い合わせを渡し、続けて `removeAllRefreshTokens` を呼ぶ」: backend/internal/auth/passwordreset.go 111〜132行 / 合っていた
- 実装のメモ「この PC の `keirekipro.parallelSlots` は1」: 審査役が使える Bash は `gh issue view` だけなので、`git config` を読めず、確かめられなかった(サイクル1の記録では、設定が無く初期値1が使われる)
- 完了条件の4項目: .kiro/settings/templates/specs/tasks.md 31〜38行と同じ文 / 合っていた

### 確かめの道具を作るタスク

| 道具 | 作るタスク | 確かめる成果物を作るタスク | 並び |
|---|---|---|---|
| `exported_integration_test.go` の `TestExported` と、今ある `internal/auth` のテスト | 1.1(今あるテストは認証の spec で作ってある) | 1.1 | 同じタスク |
| 正解のファイル(`testdata/multipart/` `testdata/username/` `testdata/jdkutf8/` `testdata/multipart/java-checks/` `testdata/mail/user-deleted.txt`) | 1.2 | 1.3、2.1、2.2、2.4、3.7 | 前 |
| `TestMail_UserDeletedMatchesJava` `TestMail_UserDeletedNoUsername` | 1.3 | 1.3 | 同じタスク |
| `make generate` `make generate-check`(既存) | 無い(置き換えの spec で作ってある) | 1.4 | 前 |
| `TestNew` `TestErrors_MessagesMatchJava` と `make lint`(depguard は既存) | 1.5 | 1.5 | 同じタスク |
| `s3_test.go` の `TestS3_DoubleSlashKey`、既存の `fakeaws_test.go` | 1.6 | 1.6 | 同じタスク |
| 結合テストの土台 `TestMain`(Postgres、Valkey、偽の AWS)と `TestIntegrationSetup` | 1.7 | 3.2、3.4、3.5、3.6、3.7、3.8、3.9 | 前(3.9 の `_依存:_` からは 1.7 にたどれない。T2-1-4) |
| `TestJDKUTF8_MatchesJava` | 2.1 | 2.1 | 同じタスク |
| `TestContentDisposition_MatchesJava` | 2.2 | 2.2 | 同じタスク |
| `TestMultipart_ControlCharInHeader` `TestMultipart_Malformed` | 2.3 | 2.3 | 同じタスク |
| `TestUpdateUserInfoBody_*` | 2.4 | 2.4 | 同じタスク |
| `TestCheckImage_*` | 3.1 | 3.1 | 同じタスク |
| 署名付きの URL の正解を作る Java のプログラムと正解のファイル(`internal/users/testdata/presign/`) | 3.2 | 3.2 | 同じタスク(先に作る) |
| `TestPresign_*` `TestObjectStore_*` | 3.2 | 3.2 | 同じタスク |
| `TestValidate_*` | 3.3 | 3.3 | 同じタスク |
| `TestRemoveAuthProvider_*` | 3.4 | 3.4 | 同じタスク |
| `TestSendAccountEmailVerification_*` | 3.5 | 3.5 | 同じタスク |
| `TestGetUserInfo_*` | 3.6 | 3.6 | 同じタスク |
| `TestUpdateUserInfo_*` | 3.7 | 3.7 | 同じタスク |
| `TestDeleteUser_*` | 3.8 | 3.8 | 同じタスク |
| `TestChangePassword_*` `TestSetEmailAndPassword_*` | 3.9 | 3.9 | 同じタスク |
| `TestUserHandlers_*` `TestUserResponses*` | 4.1 | 4.1 | 同じタスク |
| `TestNew_UserOperationsNotUnimplemented` `TestNew_UpdateUserInfoNonMultipart400`、`main_test.go` の場合 | 4.2 | 4.2 | 同じタスク |
| `/verify-backend`(`make check`。既存) | 無い(スキルとして既にある) | 1.7、2.4、3.9、4.2、5.8、6.7、7.2 | 前 |
| 筋書きの5つの欄と読み込みの確かめ(`TestScenarioValidate_UserFields`) | 5.1 | 5.1、6.1〜6.7 の筋書き | 前 |
| multipart の本文の組み立てと `body_file` の送り(`TestMultipartBody_*` `TestSend_BodyFile`) | 5.2 | 5.2、6.1〜6.7 の筋書き | 前 |
| `localhost:4566` の書き換えと `Host`(`TestAbsoluteURL_FakeAWSRewrite`) | 5.3 | 5.3、6.1、6.2、6.3、6.6 の絶対の URL の段 | 前 |
| `expect.values` `expect.body_file` `expect.content_type` の確かめ(`TestExpectValues_WithCapturedNames` `TestExpectBodyFile_SizeAndSHA256Only` `TestExpectContentType`) | 5.4 | 5.4、6.1、6.2、6.6 | 前 |
| 署名の値の正規化(`TestNormalize_PresignedURL`) | 5.5 | 5.5、6.1、6.2、6.4 | 前 |
| 画像の置き場所の `Content-Type` とメタデータの比べ(`TestCompareObjects_ContentTypeAndMetadata`) | 5.6 | 5.6、6.2、6.3 | 前 |
| 3つの動かし方への接続(`TestCompareEnv_UserFields` `TestCrossEnv_UserFields` `TestPerfEnv_UserFields`)と、認証の筋書きでの `make compat` `make compat-cross` | 5.7 | 5.7、6.1〜6.7 | 前 |
| 並びの順の CB 項目(CB-028 ほか)と `TestChangedBehaviors_UserItems`、既存の `TestLoadChangedBehaviors_*` | 5.8 | 5.8、6.1〜6.5 の筋書き | 前 |
| 初期のデータ `users-ops.sql`、`wide.png`、`not-image.png` | 6.1 | 6.1〜6.7 | 前(6.1 は同じタスクの中で先に作る。6.2〜6.7 の `_依存:_` には無い。T2-1-4) |
| `make compat`(既存の `TestCompare_Scenarios` と `TestCoverage_Operations`) | 無い(置き換えの spec で作ってある) | 5.7、6.1〜6.5 | 前 |
| `TestCrossRoute_UserSteps`(`harness/cross_test.go`) | 6.6 | 6.6 の3つの cross の筋書き | 同じタスク(先に作ると書いてある) |
| `make compat-cross`(既存の `TestCross_`) | 無い(置き換えの spec で作ってある) | 5.7、6.6 | 前 |
| `make compat-perf`(既存の `TestPerf_`)と `progress.md` の表 | 無い(置き換えの spec で作ってある) | 6.7 | 前 |
| Playwright と compose の `api-docs`、開発環境の LocalStack の SES(既存) | 無い(開発環境に既にある) | 7.1 | 前 |
| `TestCoverage_Operations`(既存) | 無い(置き換えの spec で作ってある) | 7.2 | 前 |
| main の `progress.md` の文 | 無い | 7.3 | 前 |

### 申告

**1. 進み具合の表を「比べる検査に通った」にする作業を、この spec の PR のマージのあとの別の PR にした** — タスク7.2、7.3

- Issue の記載: なし。要件7の受入基準3は、比べる検査に通ったら「比べる検査に通った」にすると決めている。design の進み具合の表の節は「比べる検査が CI で通った PR で」と書く
- 決めたこと: 7.2 は「作り終えた」までを扱う。7.3 で、この spec の PR のマージを `/ship` で見届けたあと、同じ会話で別の PR を出して「比べる検査に通った」にする。その PR を出す前に、認証の行も同じ PR で直すかを所有者に尋ねる
- 他にありえた選択肢: この spec の PR は `.golangci.yml` の変更のために所有者の承認を待つので、CI の比べる検査が通ったあと、承認の前に、同じ PR に状態の列を書き換えるコミットを足す。認証の行には触れない
- 外れていた場合: マージのあとに所有者の承認がもう1回要る PR が1つ増える。認証の行を直すかの問いは、この spec の範囲(利用者のまとまり)の外のことを所有者に尋ねることになる

**2. Java 版の正解を、開発環境でもう1つ動かした Java 版から取り直す** — タスク1.2

- Issue の記載: なし
- 決めたこと: 試作の12通りと27通りの入力が research.md に一覧で残っていないので、1.2 で Java 版をもう1つ動かし、入力を作り直して正解のファイルを作る
- 他にありえた選択肢: research.md に残る例だけを正解にする。比べる検査の筋書き(6.2)だけで確かめ、単体テストの正解を持たない
- 外れていた場合: 作り直した入力が試作の入力と違えば、試作で「同じ」と判定した根拠と単体テストの正解がずれる。1.2 の文は research.md の例を含めると決めているので、ずれは広がらない

**3. 変えた動きの項目の受け入れを、実装の途中で所有者に求める** — タスク5.8、6.5

- Issue の記載: なし。置き換えの spec は、変えた動きの一覧に載せると決めている
- 決めたこと: 5.8 で match を書く2つの項目を、受け入れた日を書かずに先に足す。6.5 で、5.8 と 6.5 で足したすべての項目の一覧と理由を所有者に示し、受け入れた日を項目に書く。受け入れまで 6.5 が終わらない
- 他にありえた選択肢: design の段階で承認を受けた項目(design の節「変えた動きの一覧の項目」の4種類)は design の承認日を書き、実装で見つかった項目だけを所有者に示す
- 外れていた場合: 所有者の返事を待つ時間が実装の途中に入る。項目の中身は design で承認済みなので、作り直しにはならない

**4. Java 版が 500 で答える4つの要求と、本文の項目が無い要求を、比べる検査に送らず単体テストだけで確かめる** — タスク2.4、3.3、4.2、6.5

- Issue の記載: なし。design の「変えた動きの一覧の項目」の節が、筋書きで送らないと決めている
- 決めたこと: 4つの要求は `users_test.go` と `server_test.go` で、項目の無い要求は `validate_test.go` で、Go 版の答えだけを確かめる
- 他にありえた選択肢: 状態の番号だけを違いとして許す match を harness に足し、比べる検査でも送る
- 外れていた場合: Java 版がほかの形の誤った要求に 500 で答えることを、比べる検査で見つけられない。6.5 の「見つかっていれば項目を足す」は、実装の中で Claude が気づいたときだけに当たる

- `- [ ]*` の省略可の印は無い

### 指摘

| ID | レベル | 該当箇所 | 内容 | 直し方の案 |
|---|---|---|---|---|
| T2-1-1 | 中 | tasks.md タスク7.2 の最後の段落 | 「この PR は、必須のチェックが通るとすぐに自動でマージされる。そのため、Claude には、この PR の CI が通ったあとに、この PR の中で状態の列を書き換える機会が無い」は、実ファイルと食い違う。この PR は小タスク1.5 で `backend/.golangci.yml` を変える。.github/CODEOWNERS 34行のとおり、このファイルの変更は所有者の承認が要り、.claude/skills/ship/SKILL.md 146〜157行のとおり、`/ship` は CODEOWNERS の承認待ち(`REVIEW_REQUIRED`)の間はマージを待つ。小タスク1.5 自身も「この変更は所有者の承認が要る」と書いており、tasks の中でも食い違う。7.3 を別の PR にした理由が誤ったまま承認されると、実装のときに Claude がこの文を前提に動き、承認待ちの間に同じ PR で書き換えられることに気づいても、7.3 の手順との食い違いで止まることになる | 7.2 の理由の文を、実際の流れに合わせて書き直す。案1: 「この PR は、`.golangci.yml` の変更を所有者が承認し、必須のチェックがすべて通るとマージされる。Claude は、承認のあとにコミットを足すと承認が外れるので、状態の列は小タスク7.3 の別の PR で書き換える」のように、別の PR にする理由を事実に合う形にする。案2: 承認待ちの間に CI の比べる検査が通ったことを確かめ、承認の前に同じ PR で状態の列を書き換えると決め、7.3 を取りやめる |
| T2-1-2 | 中 | tasks.md タスク3.5、3.7、3.8、3.9 | 要件1の受入基準6(すでに居ない利用者の要求を Java 版と同じ答えで断り、Cookie を消す)は、利用者の7つの操作すべてに当たる。Java 版の7つのユースケースは、すべて利用者が居なければ `AuthenticationCredentialsNotFoundException("不正なアクセスです。")` を投げる(usecase/user/ の7つのファイル。実ファイルで確かめた文の節)。ところが、受入基準6を確かめるテストは、処理の側では 3.4 の `TestRemoveAuthProvider_UserGone` と 3.6 の `TestGetUserInfo_UserGone` の2つだけである。4.1 の `TestUserHandlers_UserGoneClearsCookies` は処理の代わりを使う受け口のテストで、処理が正しい誤りを返すかは確かめない。6.3 の筋書きも `GET /api/users/me` だけを送る。今の `loadStoredUser` は、居ない利用者に確認のリンクが無効な 400 を返す(emailverification.go 466〜468行)ので、`UpdateUserInfo` `DeleteUser` `SendAccountEmailVerification` `SetEmailAndPassword` `ChangePassword` のどれかで渡す誤りを取り違えると、401 と Cookie の削除の代わりに 400 か 500 が返り、どのテストも落ちないまま実装が終わる。3.5、3.7、3.8、3.9 の `_要件:_` にも 1.6 が無く、完了条件の1つ目(受入基準ごとにテストを書く)がこの4つのタスクで働かない | 3.5、3.7、3.8、3.9 の `_要件:_` に 1.6 を足し、それぞれの「受入基準とテストの対応」に、`TestSendAccountEmailVerification_UserGone`、`TestUpdateUserInfo_UserGone`、`TestDeleteUser_UserGone`、`TestChangePassword_UserGone` と `TestSetEmailAndPassword_UserGone` を足す。テストは、401 と「不正なアクセスです。」と、Cookie を消す印を持つ誤りが返ることを確かめる |
| T2-1-3 | 低 | tasks.md タスク3.2 の4段落目 | 「手順3は、手順1で Gradle が取ってきた jar を、同じ置き場から読める」とあるが、`./gradlew dependencies` は依存の一覧を作るために依存の情報(pom など)を取ってくるだけで、jar は取ってこない見込みがある。jar が置き場にあるのは、同じ枠のボリューム `kp-gradle-home-<枠>`(run-check.sh 222行)で、前に Java 版のビルドかテストが流れていたときに限られる。置き場に jar が無ければ、手順3の `--class-path` が空になり、プログラムが動かない。気づくのは 3.2 の中で、直すのも 3.2 の中で済む | 手順1の `sh -c '…'` に、jar を取ってくる Gradle のタスク(例 `./gradlew compileJava` か、`runtimeClasspath` を解決するタスク)を足すか、「jar が見つからなければ止まって、取ってくるコマンドを足す」と書く |
| T2-1-4 | 低 | tasks.md タスク3.9、5.7、6.2〜6.7 | spec-writing.md の「確かめの道具を作るタスクを、使うタスクより前に置く」は、道具を使うタスクの `_依存:_` に道具を作るタスクの番号を書くと決めている。3.9 は 1.7 の結合テストの土台を使うが、`_依存: 3.3_` から 1.7 にたどれない。5.7 は 5.1〜5.6 の欄と処理を使うが `_依存: 1.6_` だけである。6.2〜6.7 は 6.1 の初期のデータと画像のファイルを使うが `_依存:_` が無い。どれも番号の順で前にあり、kiro-impl はタスクを番号の順に1つずつ進める(.claude/skills/kiro-impl/SKILL.md 164行)ので、実装には影響しない | 3.9 に 1.7、5.7 に 5.1〜5.6、6.2〜6.7 に 6.1 を `_依存:_` で足す |

### 前の段階への指摘

| ID | 対象 | 該当箇所 | 内容 |
|---|---|---|---|

- 往復: 1回目 / 高0 中2 低2

## サイクル2 往復2(2026-11-13)

### 審査の範囲

範囲: 差分

- tasks.md タスク3.2 の4段落目(`./gradlew dependencies` は jar を取ってこない、`./gradlew bootJar` を手順1と手順3の間に流す): T2-1-3 の直しで足した文。今あるもの(Gradle のタスクと、`run-check.sh backend` の置き場)について書いているので、実ファイルで確かめた
- tasks.md タスク3.2 の5段落目「`build.gradle` を変えない」: `bootJar` を流す決めが、`build.gradle` を変えずに成り立つかを見た(`bootJar` は Spring Boot のプラグインが持つタスクで、足す設定は要らない)
- tasks.md タスク3.5、3.7、3.8、3.9 の「受入基準とテストの対応」と `_要件:_`(1.6 と `_UserGone` のテストを足した): T2-1-2 の直し。requirements.md 要件1の受入基準6(106行)と、design.md の Service の節(269行「どのメソッドも、利用者の行を読み、利用者が居なければ 401 と…」)と、公開した認証の処理の節(312行「`LoadUser` は、利用者が居なければ、渡された誤りを返す」)を読み、足したテストが design の決めと同じ向きかを見た
- tasks.md タスク3.4、3.6、4.1、6.3(1.6 を扱うほかのタスク): 要件1.6 で tasks.md を検索し、7つの操作がすべて 1.6 を持つようになったかを見た(3.4、3.5、3.6、3.7、3.8、3.9 の `_要件:_` に 1.6 があり、4.1 と 6.3 は受け口と筋書きで確かめる。7つの操作が揃った)
- tasks.md タスク7.2 の最後の段落(T2-1-1 の直し。承認と CI の終わりの順、マージの条件): 今あるもの(CODEOWNERS、`/ship` の見届け、必須のチェック)について書いているので、実ファイルで確かめた。7.3 の「比べる検査を含む必須のチェックがすべて通ったときにだけマージされる」と食い違わないかを見た
- tasks.md タスク2.3、5.3、5.7、6.3、6.5 と実装のメモ(書き方の点検で直した文): 文の順の入れ替えと主語の補いで、決めごとは変わっていない。5.7 と 6.3 の「harness は/が」の主語が、5.2(`send.go` に `request.body_file` の本文を送る処理を足す)と 5.3(絶対の URL の段の書き換え)の決めと合うことを見た。実装のメモの「5つ目の大きなまとまり」「6つ目の大きなまとまり」の呼び名は、タスク5と6の見出しと同じである
- 影響を受けない箇所(タスク1、2.1、2.2、2.4、3.1、3.3、4.2、5.1、5.2、5.4〜5.6、5.8、6.1、6.2、6.4、6.6、6.7、7.1、7.3、完了条件): 差分の語(bootJar、1.6、`_UserGone`、承認、必須のチェック)で検索しても当たらないか、当たっても文が変わっていないので、読み直していない

### 実ファイルで確かめた文

- タスク3.2「`./gradlew dependencies` は依存の一覧を作るだけで、jar を取ってこない」: backend/build.gradle 69、117行(`./gradlew dependencies` を、版を読む「解除の判定」の道具としてだけ使っている)。Gradle の `dependencies` の報告は依存の図(graph)を解決して版を出すもので、jar の実体は解決しない / 合っていた(T2-1-3 の直し)
- タスク3.2「`./gradlew bootJar` は Java 版の実行に要る jar をすべて Gradle の置き場に取ってくる」「`build.gradle` を変えない」: backend/build.gradle 26〜37行(`alias(libs.plugins.spring.boot)` で Spring Boot のプラグインを使う)、backend/gradle/libs.versions.toml 29、82行(`org.springframework.boot` 4.1.2)。`bootJar` は Spring Boot のプラグインが足すタスクで、`runtimeClasspath` の jar を実行可能な jar に詰めるために解決して取ってくる。`build.gradle` と quality.gradle(121〜127行の `check` の依存)に、`bootJar` や `compileJava` に書式や静的解析の検査をつなぐ設定は無いので、`bootJar` はコンパイルと jar の作成だけで終わる / 合っていた
- タスク3.2「AWS SDK for Java の jar」が `runtimeClasspath` に入る: backend/build.gradle 130〜133行(`spring-cloud-aws-starter-s3` などを `implementation` で入れる) / 合っていた
- タスク3.2「手順3の `java` の起動は、その jar を同じ置き場から読める」: .claude/scripts/parallel/run-check.sh 222行(`kp-gradle-home-<枠>` を `/root/.gradle` に差し込む。`bootJar` も手順3も同じ1回のコンテナの中で動くので、置き場は同じ)、235〜238行(`sh -c 'exec "$@"'` に `sh -c '…'` を渡せる) / 合っていた
- タスク3.2「署名のプログラムを `internal/users/testdata/presign/` に置く」が `bootJar` のコンパイルに入らない: backend/build.gradle 177〜183行(main の sourceSets は `src/main/resources` と `src/main/java`) / 合っていた
- タスク3.5、3.7、3.8、3.9「要件1の受入基準6(すでに居ない利用者)」の Java 版の動き: サイクル2 往復1で7つのユースケースを開いて確かめてある(usecase/user/ の7ファイル。すべて `AuthenticationCredentialsNotFoundException`)。この往復では design.md 269、312、328行で Go 版の決めが同じ向きであることを読んだ / 合っていた
- タスク7.2「この spec の PR は、小タスク1.5 の `backend/.golangci.yml` の変更を所有者が承認し、必須のチェックがすべて通ると、自動でマージされる」: .github/CODEOWNERS 34行(`/backend/.golangci.yml` は所有者の承認が要る)、.claude/skills/ship/SKILL.md 146〜157行(承認待ちは `REVIEW_REQUIRED`。承認を待つコマンドを裏で動かす)、170〜172行(予約があり必須の検査がすべて通ればマージの途中) / 合っていた(T2-1-1 の直し)
- タスク7.2「所有者が承認する時と CI が終わる時の、どちらが先かは決まっていない」「所有者が先に承認していれば、CI が通るとすぐにマージされる」: .claude/skills/ship/SKILL.md 139〜172行(承認待ちと検査の結果待ちは別の判定で、順は決めていない。承認済みで必須の検査がすべて通り予約があれば、マージを待つだけ) / 合っていた
- タスク7.2 と7.3「この spec の PR の CI で Java 版と Go 版を比べる検査が通り」「比べる検査を含む必須のチェック」: .github/audit/required-checks.json 4行(`backend-test` が必須)、.github/workflows/ci.yaml 474〜476行(`backend-compat` は見分け `backend_compat` で動く)、520〜543行(必須の `backend-test` は `backend-compat` の結果を `backend-test-verdict.sh` で判定する)、.github/scripts/backend-test-verdict.sh 75行(`backend-compat` が success でなければ失敗) / 合っていた。`backend-compat` 自体は必須の検査の名前に無いが、必須の `backend-test` が `backend-compat` の結果で決まるので、比べる検査が通らない PR はマージされない

### 確かめの道具を作るタスク

| 道具 | 作るタスク | 確かめる成果物を作るタスク | 並び |
|---|---|---|---|
| `TestMultipart_ControlCharInHeader` `TestMultipart_Malformed` | 2.3 | 2.3 | 同じタスク |
| `./gradlew bootJar` で取ってきた jar と、署名付きの URL の正解を作る Java のプログラムと正解のファイル(`internal/users/testdata/presign/`) | 3.2(`bootJar` は Spring Boot のプラグインが持つ既存のタスク) | 3.2 | 同じタスク(先に作る) |
| `TestPresign_*` `TestObjectStore_*` | 3.2 | 3.2 | 同じタスク |
| `TestSendAccountEmailVerification_UserGone` と結合テストの土台 | 3.5(土台は 1.7) | 3.5 | 同じタスク(土台は前。`_依存: 1.1, 1.7_`) |
| `TestUpdateUserInfo_UserGone` と結合テストの土台 | 3.7(土台は 1.7) | 3.7 | 同じタスク(土台は前。`_依存: 3.2_` から 1.7 にたどれる) |
| `TestDeleteUser_UserGone` と結合テストの土台 | 3.8(土台は 1.7) | 3.8 | 同じタスク(土台は前。`_依存: 3.2_` から 1.7 にたどれる) |
| `TestChangePassword_UserGone` `TestSetEmailAndPassword_UserGone` と結合テストの土台 | 3.9(土台は 1.7) | 3.9 | 同じタスク(土台は前。`_依存: 3.3_` から 1.7 にたどれないのは T2-1-4 で記録済み) |
| `TestAbsoluteURL_FakeAWSRewrite` | 5.3 | 5.3、6.1、6.2、6.3、6.6 | 前 |
| `TestCompareEnv_UserFields` `TestCrossEnv_UserFields` `TestPerfEnv_UserFields`、認証の筋書きでの `make compat` `make compat-cross` | 5.7 | 5.7、6.1〜6.7 | 前 |
| `make compat`(既存) | 無い(置き換えの spec で作ってある) | 6.3、6.5 | 前 |
| `TestChangedBehaviors_UserItems`、既存の `TestLoadChangedBehaviors_*` | 5.8 | 6.5 | 前 |
| `TestCoverage_Operations`(既存)と `/verify-backend`(既存) | 無い(置き換えの spec とスキルで作ってある) | 7.2 | 前 |

### 申告

サイクル2 往復1の申告1〜4から変わっていない。往復1への対応で足した決めは、T2-1-3 の直しの `./gradlew bootJar` を流すこと(3.2)だけで、これは `build.gradle` を変えずに jar を取ってくる手段の選びであり、外れていても 3.2 の中で別の Gradle のタスクに替えれば済むので、申告の対象にしない。

- `- [ ]*` の省略可の印は無い

### 指摘

| ID | レベル | 該当箇所 | 内容 | 直し方の案 |
|---|---|---|---|---|

この往復の指摘は無い。T2-1-1 の直し(7.2)は CODEOWNERS と `/ship` の見届けの手順と合い、7.3 とも食い違わない。T2-1-2 の直し(3.5、3.7、3.8、3.9)で、要件1の受入基準6が利用者の7つの操作すべてで処理の側のテストを持つようになった。T2-1-3 の直し(3.2)の `./gradlew bootJar` は、`build.gradle` を変えずに `runtimeClasspath` の jar を取ってくる既存のタスクで、文は実ファイルと合う。T2-1-4 は記録のみで、却下の理由(番号の順で前にあり、kiro-impl は番号の順に進める)は往復1で確かめたとおりである。

### 前の段階への指摘

| ID | 対象 | 該当箇所 | 内容 |
|---|---|---|---|

- 往復: 2回で収束 / 未解決: 0件
