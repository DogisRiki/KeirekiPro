# tasks のレビュー記録(backend-go-resume-export)

## サイクル1 往復1(2026-11-23)

### 審査の範囲

範囲: 全体

### 実ファイルで確かめた文

- 小タスク1.2「Java 版を `docker/backend/Dockerfile.prod` のイメージで組み立てる」: `backend/compat/harness/images.go` 44行目 / 合っていた
- 小タスク1.2「`versions.go` が Java 版に渡す環境変数と同じ名前の環境変数で起動する。この Java 版は、データベース `keireki_proto` と Redis の DB 7 を使う」: `backend/compat/harness/versions.go` 70〜95行目(`JavaEnv` はデータベースと Redis を環境変数で選ばず、fakeaws の秘密の値から読ませる)、`backend/src/main/resources/application-dev.yaml` 3行目と5行目と9〜12行目、`docker/localstack/init-localstack.sh` 18〜28行目(`keirekipro/rds` の `database` は `keireki_pro`、`keirekipro/redis` に DB の番号の欄は無い) / 食い違っていた(T1-1-3)
- 小タスク1.2「ログインと CSRF の値の付け方を `capture.go` の手順に合わせる」: `backend/compat/harness/capture.go` / 合っていた
- 小タスク1.1「`users/basic.sql` と `resumes/many-pages.sql` のあとに入れる」「経歴書 201」: `backend/compat/fixtures/users/basic.sql`、`backend/compat/fixtures/resumes/many-pages.sql` / 合っていた
- 小タスク1.1・6.1・6.2「`backend/compat/fixtures/export/` にファイルを置く」(置いたあとも今のテストが通ること): `backend/compat/harness/fixtures_test.go` 298〜334行目(`TestFixtures_AllLoadable` は、`users` `resumes` `backups` `images` のほかのフォルダのファイルを「知らない種類のファイルです」で失敗にする)、`backend/compat/harness/fixtures.go` 16〜24行目 / 食い違っていた(T1-1-4)
- 小タスク1.3「`make generate-check`」: `backend/Makefile` 48行目 / 合っていた
- 小タスク1.4「`TestLoadChangedBehaviors_CB005HasNoMatch` の期待する数 55」: `backend/compat/harness/match_test.go` 314行目と328行目 / 合っていた
- 小タスク1.4「CB-004 の文に書き足す」: `backend/compat/harness/match_test.go` 548行目の `TestChangedBehaviors_OwnerDecidedItems`(CB-004 に「配置」を含めてはならない) / 合っていた(書き足す文に「配置」を使わないことは T1-1-6 に書いた)
- 小タスク2.1「`validateVersionBody` の断る条件から外し、`checkStepExpect` で確かめる」: `backend/compat/harness/scenario.go` 369〜387行目(383〜385行目が版に送る段の `content_type` を断る)、`backend/compat/harness/steps.go` 135行目と142行目 / 合っていた。ただし、今の断る条件を確かめる `scenario_test.go` 544行目のテストの場合が残る(T1-1-2)
- 小タスク2.2・2.3「今の6つのテストも通る」: `backend/compat/pdfcmp/pdfcmp_test.go` 36〜149行目の6つのテスト。92行目は `firstDifferentLine` が作る「[ページの文字] ページ 1: 行 1: …」の説明を、112行目は頁ごとの `KindText` の違いを、65行目と75行目は `KindWordPos` を期待する。`pdfcmp.go` 40〜49行目の違いの種類と、design.md の PDF を比べる部品の節の表(414〜419行目)の新しい違いの種類 / 食い違っていた(T1-1-1)
- 小タスク2.2「`readTexts` と `firstDifferentLine` と `normalizeText`」、小タスク2.3「`compareWords`」「30行目のコメント」: `backend/compat/pdfcmp/pdfcmp.go` 30行目、247行目、268行目、428行目、447行目 / 合っていた
- 小タスク4.3「`service.go` の `Deps`」: `backend/internal/resume/service.go` 20行目 / 合っていた
- 小タスク3.5「`checkDiffTableInChangedBehaviors`」: `backend/internal/resume/difftable_test.go` 17行目 / 合っていた
- 小タスク5.1「`authResponse` と `write`」「`resumeresponses.go` の26の操作のコメント」「`TestAuthOIDCHandlers_MiddlewareOnlyOIDC`」「`TestResumeResponses_AllOperationsWrite` の期待26」: `backend/internal/httpapi/authresponses.go`、`resumeresponses.go` 12行目、`auth_test.go` 919行目、`resumes_test.go` 805〜836行目 / 合っていた
- 小タスク5.2「`server.go` の `ResumeHandlers` のコメントと `resumeOperations` の26の操作」「`TestResumeRoutes_Wired`」「`TestResumeRoutes_Unimplemented`」: `backend/internal/httpapi/server.go` 49行目と93行目、`resumes_test.go` 940〜970行目 / 合っていた。`resumes_test.go` 585行目の `TestResumeHandlers_SuccessResponses` の操作の数26は、タスクに書かれていない(T1-1-6)
- 小タスク5.3「`resume.New` を `d.newPDF` のあとに移す」「手本は `TestRun_PassesResumeHandlers`」: `backend/cmd/keirekipro/main.go` 71行目、173行目、175行目、`main_test.go` 307行目と942行目 / 合っていた
- 小タスク6.3「`scenarios/resumes/deleted-user.yaml`」「`TestCoverage_Operations`」「`progress.md` のまとまりの表」: `backend/compat/scenarios/resumes/deleted-user.yaml`、`backend/compat/compat_test.go` 64行目、`.kiro/specs/backend-go-replacement/progress.md` / 合っていた
- 小タスク6.4「手本は `TestCrossRoute_ResumeSteps`」「`make compat-cross`」、小タスク6.5「`make compat-perf`」、6.3「`make compat`」: `backend/compat/harness/cross_test.go` 263行目、`backend/Makefile` 127〜136行目 / 合っていた
- 小タスク7.1「compose の `api-docs`(ポート 8082)」「`backend-go`」: `compose.yaml` 40行目と76行目 / 合っていた
- 実装のメモ「`make check` は compat のテストを流さない」に当たる前提(`backend/compat/` のテストはビルドタグ `compat` を持つ): `backend/Makefile` 85〜101行目(`check` は compat を組み立てるだけで、テストは `make compat` が流す) / 合っていた

### 確かめの道具を作るタスク

| 道具 | 作るタスク | 確かめる成果物を作るタスク | 並び |
|---|---|---|---|
| `backend/compat/fixtures/export/export.sql`(経歴書 601、701、201 の自己PR) | 1.1 | 1.2、4.4、6.1、6.2、6.3 | 前 |
| 正解のファイル(`testdata/export/markdown/*.md` `body.json` `filenames.json`、`httpapi/testdata/exportdisposition.json`) | 1.2 | 3.3、3.4、3.5、4.4 | 前 |
| `go test -tags compat ./compat/harness/ -run 'TestLoadChangedBehaviors\|TestChangedBehaviors'` | 今ある | 1.4、3.5、6.3 | 前 |
| `make generate-check`、`go test ./internal/httpapi/` | 今ある | 1.3 | 前 |
| 筋書きの `json_file` `body_contains` 版に送る段の `content_type` と、`TestLoadScenarios_JSONFileExclusive` `TestCapture_JSONFileSentAsIs` `TestExpectContentType_VersionStep` `TestExpectBodyContains` | 2.1 | 2.1(テスト)、6.1、6.2、6.4(筋書き) | 前 |
| PDF を比べる部品の決め直した比べ方と、`pdfcmp_test.go` の足すテスト | 2.2、2.3 | 2.2、2.3(テスト)、6.1、6.2(筋書き) | 前 |
| `exportsettings_test.go` `exportrule_test.go` `filename_test.go` `exportdisposition_test.go` `exportbody_test.go` | 3.1〜3.5(それぞれのタスク) | 同じタスク | 前 |
| `exportmodel_test.go` `exporttemplate_test.go` | 4.1、4.2 | 同じタスク | 前 |
| `PDFRenderer` の偽の部品と `export_test.go` | 4.3 | 4.3、4.4 | 前 |
| `export_integration_test.go` | 4.4(6.3 で足す) | 4.3 の Service、6.3 の 500 の要求 | 前 |
| `auth_test.go` `TestAuthResponses_ContentDisposition` `TestAuthRequestMiddleware_Operations`、`resumes_test.go` `TestResumeResponses_AllOperationsWrite` | 5.1 | 5.1 | 前 |
| `resumes_test.go` `TestExportHandlers_*` `TestResumeRoutes_*` | 5.2 | 5.2 | 前 |
| `main_test.go` `TestRun_PassesPDFEngineToResume` | 5.3 | 5.3 | 前 |
| `TestCompare_Scenarios`(`make compat`)と `TestCoverage_Operations` | 今ある | 6.1、6.2、6.3 | 前 |
| `fixtures_test.go` `TestFixtures_AllLoadable`(`make compat` で動く) | 今ある(新しいフォルダ `export/` を受けるよう直すタスクが無い) | 1.1、6.1、6.2 | 後ろ(T1-1-4) |
| `TestCrossRoute_ExportSteps` と `make compat-cross` | 6.4(筋書きより前に作る) | 6.4 | 前 |
| `TestLoadScenarios_ExportPerf` と `make compat-perf` | 6.5(筋書きより前に作る) | 6.5 | 前 |
| `/verify-backend` | 今ある | 1.4、2.3、3.5、4.4、5.3、6.5、7.2 | 前 |
| API の説明画面の「Try it out」 | 今ある(compose の `api-docs`) | 7.1 | 前 |

### 申告

**1. Java 版が 500 で答える出力の要求を、変えた動きの一覧に載せて筋書きから外し、外すと要件5の受入基準1が満たせない要求なら止まる** — tasks.md 小タスク6.3 の3

- Issue の記載: なし(Issue #773 は、置き換えの spec の要件の番号を挙げるだけ)
- 決めたこと: 筋書きを書く途中で Java 版が 500 で答える要求を見つけたら、要求ごとに変えた動きの一覧に足し、match を書かずに段を筋書きから外し、Go 版の答えを結合テストで確かめる。外す要求が、要件5の受入基準1が含めると決めた要求に当たるときは、段を外さずに止まる
- 他にありえた選択肢: 見つけた時点で、どの要求でも止まって所有者に報告する
- 外れていた場合: 所有者が知らないまま、Java 版と比べない要求が増える。PR の本文(小タスク7.2 の3)で報告されるので、マージ前に所有者が読める

**2. CB-062 を、画面が送らない書き方で答えが違うときだけ足す** — tasks.md 小タスク1.4、3.5

- Issue の記載: なし
- 決めたこと: 本文の読み手を作り、`body.json` の正解のファイルと比べて違いがあったときだけ、CB-062 を足す
- 他にありえた選択肢: 違いを設計の段階で確定させ、tasks で番号を固定する
- 外れていた場合: 違いの中身が所有者の承認を経ずに一覧に載る。ただし requirements の要件1の受入基準2が、画面が送らない書き方での違いを受け入れている

**3. `bool-number.json` と `exp-string.json` のうち、Go 版の答えが Java 版と違う本文を `settings.yaml` から外す** — tasks.md 小タスク6.2

- Issue の記載: なし
- 決めたこと: 単体テストで違いが分かった本文を、Java 版と Go 版を比べる検査の筋書きから外す
- 他にありえた選択肢: 外さずに match を書いて比べる
- 外れていた場合: 外した本文は、比べる検査で見張られず、`exportbody_test.go` の表だけで確かめる

**4. 進み具合の表を「比べる検査に通った」にするのを、別の PR に分ける** — tasks.md 小タスク7.2、7.3

- Issue の記載: なし
- 決めたこと: この spec の PR のマージを確かめてから、同じ会話で別の PR を出す
- 他にありえた選択肢: この spec の PR の中で書く
- 外れていた場合: 2つ目の PR が出されないと、表の状態が「作り終えた」のまま残る

**5. API の説明画面での確認で、PDF の見た目を確かめない** — tasks.md 小タスク7.1、実装のメモ

- Issue の記載: なし
- 決めたこと: 開発環境のイメージに Java 版の4つのフォントが無いので、説明画面では状態の番号と Content-Type だけを確かめ、PDF の見た目は `make compat` で確かめる
- 他にありえた選択肢: 説明画面で出した PDF を開いて見る
- 外れていた場合: 開発環境で PDF の見た目が崩れても、この spec の確認では見つからない

### 指摘

| ID | レベル | 該当箇所 | 内容 | 直し方の案 |
|---|---|---|---|---|
| T1-1-1 | 中 | tasks.md 小タスク2.2 と2.3 の「完了の確かめ方」 | 「今の6つのテストも通る」は、この2つのタスクの変更のあとでは成り立たない。`pdfcmp_test.go` 92行目は、2.2 で消す `firstDifferentLine` が作る説明「[ページの文字] ページ 1: 行 1: Hello World」をそのまま期待する。112行目は、改頁の位置が違う PDF に頁ごとの `KindText` の違いを期待するが、2.2 の文書の全体の字の並びの比べ方では字の並びが同じになり、違いは行の頁の違い(design の「行の位置、文字の大きさ、折り返し、ページの数」)として出る。65行目と75行目の `KindWordPos`(語の位置)も、2.3 の行の組の比べ方では行の位置の違いになる。このまま進むと、Claude は、タスクの文に従えずに止まるか、テストの期待を書き換えるか消すかを自分で決めることになり、消せば完了条件の3(アサーションの削除)に触れる | 2.2 と2.3 に、今の6つのテストのうち期待を変えるテストと、変えたあとの期待(違いの種類と頁の番号と説明の形)を書く。例: `TestCompare_RejectsOneCharDiff` は「文書の字の並び」の違いを期待する形に、`TestCompare_RejectsPageBreakDiff` の1つ目の場合は、2.3 の `TestCompare_RejectsPageBreakDiffWithoutWrap` と同じ違いを期待する形に、`TestCompare_Rejects2_5ptShift` は行の位置の違いを期待する形に替える。どれも、アサーションを消さずに期待を替える、と書く。「完了の確かめ方」を「今の6つのテストを、決め直した違いの種類で期待する形に替えて通る」にする |
| T1-1-2 | 中 | tasks.md 小タスク2.1 | 2.1 は、版に送る段の `content_type` を `validateVersionBody` の断る条件から外す。`scenario_test.go` 544行目の `TestScenarioValidate_UserFields` の場合「版に送る段の expect の content_type」は、この筋書きが「expect の content_type は、絶対の URL の段にだけ」で断られることを期待するので、2.1 のあとに失敗する。2.1 はこの場合に触れず、「完了の確かめ方」の `-run 'TestLoadScenarios\|TestCapture\|TestExpect'` は `TestScenarioValidate_UserFields` を流さない。`make check` は compat のテストを流さないので、失敗は6.3 の `make compat` か CI で初めて見つかる | 2.1 に、`scenario_test.go` の今の場合「版に送る段の expect の content_type」を、断られない場合として確かめる形に替えるか、`TestExpectContentType_VersionStep` に移すことを書く(アサーションを消さない)。「完了の確かめ方」の `-run` に `TestScenarioValidate` を足す |
| T1-1-3 | 中 | tasks.md 小タスク1.2 | 「`versions.go` が Java 版に渡す環境変数と同じ名前の環境変数で起動する。この Java 版は、データベース `keireki_proto` と Redis の DB 7 を使う」は、実ファイルと合わない。`versions.go` 74〜95行目の `JavaEnv` は、`SPRING_PROFILES_ACTIVE=dev` と `SPRING_CLOUD_AWS_ENDPOINT` と `TZ` と `OIDC_PROVIDERS_*` だけを渡し、データベースと Redis は、dev のプロファイルの `application-dev.yaml` 3行目のとおり秘密の値 `keirekipro/rds` と `keirekipro/redis` から読ませる。開発環境の localstack の秘密の値は、`init-localstack.sh` 20行目で `"database":"keireki_pro"`、27行目で Redis の DB の番号の欄が無い(DB 0)。同じ名前の環境変数だけで起動すると、Java 版は所有者の開発のデータベース `keireki_pro` と Redis の DB 0 を使い、同じタスクの「触れない」に反する。`keireki_proto` と DB 7 を選ばせる方法(環境変数の名前、または秘密の値の置き場)がタスクにも design にも無い | 1.2 に、`keireki_proto` と Redis の DB 7 を選ばせる方法を書く。たとえば、`JavaEnv` の環境変数に加えて、Spring の設定を上書きする環境変数(データベースの URL を `keireki_proto` にするものと、Redis の database を 7 にするもの)を渡すこと、またはこのタスクのためだけの秘密の値の置き場を使うこと、と書く。開発環境の localstack の秘密の値 `keirekipro/rds` と `keirekipro/redis` を書き換えないことも書く。どの方法でも、起動したあとに Java 版がつないだデータベースの名前を確かめてから要求を送ることを「完了の確かめ方」に足す |
| T1-1-4 | 中 | tasks.md 小タスク1.1(と6.1、6.2) | 1.1 と6.1 と6.2 は、新しいフォルダ `backend/compat/fixtures/export/` に、`export.sql` と、`inline-default.json` と10の要求の本文を置く。`fixtures_test.go` 298〜334行目の `TestFixtures_AllLoadable` は、`fixtures/` のすべてのファイルを調べ、`users` `resumes` `backups` `images` のどれでもないフォルダのファイルを「知らない種類のファイルです」で失敗にする。どのタスクも `fixtures_test.go` を直すと書いていない。このテストは compat のビルドタグを持ち、`make check` では流れないので、6.3 の `make compat` か CI で初めて見つかる。`export.sql` を、ほかの SQL と同じ経歴書の決まりで確かめることも抜ける | 1.1 に、`fixtures_test.go` の `TestFixtures_AllLoadable` に `export` のフォルダの場合を足すことを書く。`export/*.sql` は `users` と `resumes` の SQL と同じく読み込んで決まりを確かめ、`export/*.json` は JSON として読めることを確かめる、と書く。`fixtures.go` 16〜24行目の `FixturesDir` のコメントの「中のフォルダは次の4つ」を5つにすることも書く。「完了の確かめ方」に `go test -tags compat -run TestFixtures_AllLoadable ./compat/harness/` を足す |
| T1-1-5 | 低 | tasks.md 小タスク1.2、4.4、6.1、6.2 の `_依存:_` | spec-writing.md の決まりでは、道具を使うタスクの `_依存:_` に、道具を作るタスクの番号を書く。1.2 は1.1 の `export.sql` を使うのに `_依存: 1.1_` が無い。4.4 は4.3 の偽の部品を使うのに `_依存:_` に4.3 が無い。6.1 は1.1 の `export.sql` を、6.2 は2.1 の `json_file` と2.3 の比べ方と5.3 の入口を使うのに、その番号が無い。タスクは番号の順に1つずつ進むので、実装には影響しない | それぞれの `_依存:_` に、使う道具を作るタスクの番号を足す |
| T1-1-6 | 低 | tasks.md 小タスク5.2、1.4 | 5.2 は、`resumes_test.go` 585行目の `TestResumeHandlers_SuccessResponses` の操作の数26に触れていない。`resumeOps()` に出力の2つの操作を足すと、このテストの期待も28にする必要がある(足さなければ触れなくてよい)。1.4 で CB-004 に書き足す文は、`match_test.go` 548行目の `TestChangedBehaviors_OwnerDecidedItems` が「配置」を含めないことを求めるので、この語を使えない。どちらも、5.2 と1.4 の「完了の確かめ方」のテストで見つかる | 5.2 に「`resumeOps()` に出力の操作を足すときは、`TestResumeHandlers_SuccessResponses` の期待を28にする」と書く。1.4 に「CB-004 に書き足す文に『配置』を使わない」と書く |

### 前の段階への指摘

| ID | 対象 | レベル | 作るもの | 該当箇所 | 内容 | 直し方の案 |
|---|---|---|---|---|---|---|
| T1-1-7 | design | 中 | 変わらない | design.md テストの方針の `pdfcmp.go`(623行目) | 「今の6つのテストを保ち」は、同じ design の PDF を比べる部品の節(410〜442行目)と合わない。この節は、頁ごとの字の比べ方と語の位置の比べ方を、文書の全体の字の並びと行の組の比べ方に替え、違いの種類を表の名前(「文書の字の並び」「行の位置」など)にする。今の `pdfcmp_test.go` の `TestCompare_RejectsOneCharDiff`(92行目)、`TestCompare_RejectsPageBreakDiff`(112行目)、`TestCompare_Rejects2_5ptShift`(65行目と75行目)は、今の違いの種類と説明を期待するので、そのままでは保てない。tasks の T1-1-1 の元になる文である | 623行目を「今の6つのテストは、確かめる場合を保ち、期待する違いの種類と説明を、この節の比べ方の違いの種類に替える。次の10の場合を足す」に直す |

- 往復: 1回目 / 高0 中5 低2

## サイクル1 往復2(2026-11-23)

### 審査の範囲

範囲: 差分

- tasks.md 小タスク1.1(`TestFixtures_AllLoadable` に `export` の場合を足す文と完了の確かめ方): T1-1-4 の直し。`fixtures_test.go` の `fixtureDB` と `TestFixtures_ResumeKindsPresent` が同じデータベースを使うこと、design.md のファイルの構成と「初期のデータと要求の本文」の節(504〜532行目)の要求の本文がすべて JSON として読める本文であることを合わせて見た
- tasks.md 小タスク1.2(Spring の設定を上書きする2つの環境変数と `/actuator/env` での確かめ): T1-1-3 の直し。`versions.go` の `JavaEnv`、`application-dev.yaml`、`init-localstack.sh`、`SecurityConfig.java` を開いた
- tasks.md 小タスク2.1(`TestScenarioValidate_UserFields` の場合を `TestExpectContentType_VersionStep` に移す文と `-run`): T1-1-2 の直し。`scenario_test.go` と `steps_test.go` のテストの名前を見た
- tasks.md 小タスク2.2 と2.3(今の6つのテストの期待を替える文と完了の確かめ方): T1-1-1 の直し。2.2 のあとも `compareWords` が残る間の各テストの結果と、2.3 のあとの各テストの結果を、`pdfcmp.go` の `compareDocs` と design.md の PDF を比べる部品の節(406〜446行目)に当てはめて確かめた
- design.md テストの方針の `pdfcmp.go`(623行目): 承認を残した直し(T1-1-7)。同じ design の PDF を比べる部品の節と、tasks 2.2 と2.3 の文が合うかを見た
- tasks.md 小タスク1.2 の受入基準とテストの対応、小タスク6.3 の3、実装のメモの3つの箇条: 書き方の点検の直し。意味が変わっていないかだけを見た。前後の文と食い違う箇所は無かった

### 実ファイルで確かめた文

- 小タスク1.1「`TestFixtures_AllLoadable` は、`fixtures/` の4つのフォルダのほかにあるファイルを『知らない種類のファイルです』で失敗にする」: `backend/compat/harness/fixtures_test.go` 298〜335行目 / 合っていた
- 小タスク1.1「`export/*.sql` を `users` と `resumes` の SQL のあとに読み込み、同じ決まりで確かめる」(今のテストが `users` と `resumes` の SQL を読み込んで決まりを確かめること): `fixtures_test.go` 43〜79行目(`fixtureDB`)、404〜489行目 / 合っていた
- 小タスク1.1「`fixtures.go` の `FixturesDir` のコメントの『中のフォルダは次の4つ』」: `backend/compat/harness/fixtures.go` 16〜24行目 / 合っていた
- 小タスク1.2「`JavaEnv` が Java 版に渡す環境変数」: `backend/compat/harness/versions.go` 74〜95行目 / 合っていた
- 小タスク1.2「dev のプロファイルの Java 版は、データベースと Redis のつなぎ先を localstack の秘密の値 `keirekipro/rds` と `keirekipro/redis` から読む」: `backend/src/main/resources/application-dev.yaml` 3〜12行目 / 合っていた
- 小タスク1.2「この2つの秘密の値は、データベース `keireki_pro` と Redis の DB 0 を指す」: `docker/localstack/init-localstack.sh` 20行目と27行目(Redis の秘密の値に DB の番号の欄が無い) / 合っていた
- 小タスク1.2「Java 版の `/actuator/env` で `spring.datasource.url` と `spring.data.redis.database` を確かめる」(dev のプロファイルで `/actuator/env` が開いていて値が読めること): `application-dev.yaml` 52〜61行目(`exposure.include: "*"`、`env.show-values: always`)、`backend/src/main/java/com/example/keirekipro/presentation/security/config/SecurityConfig.java` 67行目と97行目(`/actuator/**` は認証無しで通る) / 合っていた
- 小タスク2.1「`TestScenarioValidate_UserFields` の場合『版に送る段の expect の content_type』は、今の断る条件で筋書きが断られることを期待する」: `backend/compat/harness/scenario_test.go` 496行目と544行目 / 合っていた
- 小タスク2.2「`TestCompare_RejectsOneCharDiff` の1つ目の場合は、`firstDifferentLine` が作る説明『[ページの文字] ページ 1: 行 1: …』を期待する」: `backend/compat/pdfcmp/pdfcmp_test.go` 81〜95行目、`backend/compat/pdfcmp/pdfcmp.go` 96〜110行目と402〜404行目と428〜437行目 / 合っていた
- 小タスク2.2「`TestCompare_RejectsPageBreakDiff` の1つ目の場合は、頁ごとの字の違いを期待する。文書の全体の字の並びで比べると、この場合の2つの PDF の字は同じになる」: `pdfcmp_test.go` 106〜115行目(字は両方とも Alpha、Bravo、Charlie の順) / 合っていた
- 小タスク2.2 の完了の確かめ方で `TestCompare_Rejects2_5ptShift` を流すこと(2.2 のあとも `KindWordPos` を期待したまま通ること): `pdfcmp.go` 386〜425行目(`compareWords` は2.3 で消すまで残り、字が同じ頁で語の位置を比べる)、`pdfcmp_test.go` 55〜79行目 / 合っていた
- 小タスク2.3「`TestCompare_Rejects2_5ptShift` は違いの種類『語の位置』を期待する」「`TestCompare_RejectsPageBreakDiff` の1つ目の場合は1頁目と2頁目の『ページの文字』の違いを期待する」: `pdfcmp_test.go` 65行目、75行目、112行目、`pdfcmp.go` 45〜46行目 / 合っていた
- 小タスク2.3 で期待を替えないほかのテスト(`TestCompare_RejectsPageBreakDiff` の2つ目の場合の「ページの数」、`TestCompare_FontSubsetPrefixIgnored` の「フォント」、`TestCompare_TableColorTolerance` の「表の色」)が、design の表の違いの種類の名前のままで通ること: `pdfcmp_test.go` 116〜173行目、design.md 412〜419行目 / 合っていた

### 確かめの道具を作るタスク

| 道具 | 作るタスク | 確かめる成果物を作るタスク | 並び |
|---|---|---|---|
| `go test -tags compat -count=1 -run TestFixtures_AllLoadable ./compat/harness/`(`export` の場合を足したもの) | 1.1 | 1.1、6.1、6.2 | 前 |
| Java 版の `/actuator/env` | 今ある(`application-dev.yaml`) | 1.2 | 前 |
| `go test -tags compat ./compat/harness/ -run 'TestLoadScenarios\|TestCapture\|TestExpect\|TestScenarioValidate'`(移した場合を含む `TestExpectContentType_VersionStep`) | 2.1 | 2.1 | 前 |
| 2.2 の完了の確かめ方の `-run` の10のテスト(期待を替えた `TestCompare_RejectsOneCharDiff` を含む) | 今ある6つのうち5つと、2.2 で足す5つ | 2.2 | 前 |
| `go test -tags compat ./compat/pdfcmp/`(期待を替えた `TestCompare_Rejects2_5ptShift` と `TestCompare_RejectsPageBreakDiff` を含む) | 今ある6つと、2.2 と2.3 で足すテスト | 2.3 | 前 |

### 申告

差分の範囲に、新しく申告するものは無い。

### 指摘

いまの段階の指摘は無い。

### 前の段階への指摘

| ID | 対象 | レベル | 作るもの | 該当箇所 | 内容 | 直し方の案 |
|---|---|---|---|---|---|---|
| T1-2-1 | design | 低 | 変わらない | design.md ファイルの構成の「Claude が変えるファイル」(151〜174行目) | tasks の小タスク1.1 は、T1-1-4 の直しで `backend/compat/harness/fixtures_test.go`(`TestFixtures_AllLoadable` に `export` の場合を足す)と `backend/compat/harness/fixtures.go`(`FixturesDir` のコメント)を変える。design のファイルの構成の「Claude が変えるファイル」には、この2つのファイルが無い。tasks の本文に変える中身が書いてあるので、実装には影響しない | 「Claude が変えるファイル」に、`backend/compat/harness/fixtures_test.go`(`TestFixtures_AllLoadable` に `export` のフォルダの場合を足す)と `backend/compat/harness/fixtures.go`(`FixturesDir` のコメントに `export/` を足す)を足す |

### 承認を残して直した前の段階の審査

- 直しの番号 1: T1-1-7: 埋まった / 作るもの: 変わらない

- 往復: 2回で収束 / 未解決: 0件
