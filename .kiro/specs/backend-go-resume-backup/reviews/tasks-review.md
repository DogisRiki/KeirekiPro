## サイクル1 往復1(2026-11-24)

### 審査の範囲

範囲: 全体

### 実ファイルで確かめた文

- 小タスク1.1「`TestFixtures_AllLoadable` は、`fixtures/` の今あるフォルダのほかにあるファイルを、知らない種類のファイルとして失敗にする」: backend/compat/harness/fixtures_test.go 304行から(今あるフォルダは users、resumes、export、backups、images) / 合っていた
- 小タスク1.1「`backup/*.sql` を `users` と `resumes` の SQL と同じ決まりで確かめる」: backend/compat/harness/fixtures_test.go 440-490行(職歴の期間の重なり、始めの月の重なり、案件の会社が職歴にあること、長さ、https のリンク、名前の頭の英大文字) / 合っていた
- 小タスク1.1「ポートフォリオと SNS と自己PR の項目の名前を、`fonts.sql` と同じく `A ` と `B ` で順が決まる名前にする」: backend/compat/fixtures/resumes/fonts.sql(経歴書 401「フォントを比べる経歴書」と、`A ` `B ` で始まる項目の名前) / 合っていた
- 小タスク1.2「今の `fixtures/backups/` の4つのファイル」と「`checkBackup` に名前の頭ごとの確かめ方を足す」: backend/compat/fixtures/backups/(basic、broken、no-resume、wrong-version の4つ)、backend/compat/harness/fixtures_test.go 204行の `checkBackup`(知らない名前のファイルを default で失敗にする) / 合っていた
- 小タスク1.2「`resume-limits.sql` の利用者 500」: backend/compat/fixtures/resumes/resume-limits.sql / 合っていた
- 小タスク1.3「`docker/backend/Dockerfile.prod`、ネットワーク、`postgresql` のコンテナ、localstack、`SPRING_PROFILES_ACTIVE` を `dev`、`/actuator/env`」: docker/backend/Dockerfile.prod、compose.yaml(サービス db の container_name が postgresql、ネットワーク my-network)、backend/src/main/resources/application-dev.yaml(actuator の include が `*`、show-values が always) / 合っていた
- 小タスク1.3「ログインと CSRF の値の付け方を、`backend/compat/harness/capture.go` の手順に合わせる」: backend/compat/harness/capture.go(`CompatHost` の定数と、取り出しの元 `cookie:` の読み方だけを持ち、Cookie の束と CSRF のヘッダを付ける処理は無い)、backend/compat/harness/send.go 22-25行(`XSRF-TOKEN` と `X-XSRF-TOKEN`)、151-174行(`prepareVersionRequest` が Host、Cookie、`X-XSRF-TOKEN` を付ける) / 食い違っていた(T1-1-3)
- 小タスク1.3「`RestoreResumeUseCase.java` の文字列」と小タスク4.3「`RestoreResumeUseCase` の 97-138行」: backend/src/main/java/com/example/keirekipro/usecase/resume/RestoreResumeUseCase.java 59行、97-138行、137行 / 合っていた
- 小タスク1.4、1.5、実装のメモの5つ目「`make generate` と `make generate-check`、生成したコードの置き場」: backend/Makefile(generate、generate-check、test、check、compat、compat-cross、compat-perf)、backend/internal/platform/database/sqlcgen / 合っていた
- 小タスク1.5「`store_integration_test.go` に足す」: backend/internal/resume/store_integration_test.go(今あるテストの名前は `TestStore_*`。足すテストの名前 `TestStoreIntegration_UserExists` は新しい名前で、`-run` の名前と合う) / 合っていた
- 小タスク1.6「`TestLoadChangedBehaviors_CB005HasNoMatch` の期待する数を5つ増やす」: backend/compat/harness/match_test.go 314-330行(328-329行で項目の数を61と確かめる) / 合っていた
- 小タスク1.6「CB-062 から CB-066 を `TestLoadChangedBehaviors_CB005HasNoMatch` と `TestLoadChangedBehaviors_RequiredFields` で確かめる」: backend/compat/harness/match_test.go 248-312行(`RequiredFields` は `writeBehaviors` で作った仮のファイルだけを読み、`changed-behaviors.yaml` を読まない)、314-345行(`CB005HasNoMatch` は本物のファイルを読むが、数と、名前を挙げた項目の match だけを確かめ、CB-062 から CB-066 の match を確かめない) / 食い違っていた(T1-1-2)
- 小タスク2.1「`scenario.go` の `validateKind` `validateVersionBody` `validateJSONFile`、`capture.go` の `requestBody`」: backend/compat/harness/scenario.go、backend/compat/harness/capture.go 250行から(`requestBody`) / 合っていた
- 小タスク4.1「`service.go` の28の操作と書いたコメント」: backend/internal/resume/service.go 1行、31行 / 合っていた
- 小タスク4.2、4.4「結合テストは `users/basic.sql` などをデータベースに入れて動く」: backend/internal/resume/main_integration_test.go(`TestMain` がパッケージで1つの Postgres を作り、`testPool` をすべてのテストで使う)、backend/internal/resume/export_integration_test.go 18-74行(`exportFixtures` が `users/basic.sql` と `resumes/fonts.sql` を含み、`sync.Once` で1度だけ入れる。52行のコメント「初期のデータの ID は決まった値なので、2度入れると重なって失敗する」)、backend/compat/fixtures/users/basic.sql(`ON CONFLICT` の無い INSERT) / 食い違っていた(T1-1-1)
- 小タスク4.3「`errors_test.go` に足す」: backend/internal/resume/errors_test.go / 合っていた
- 小タスク5.1「`resumes_test.go` の28の操作を期待するテスト、`TestResumeRoutes_Unimplemented`、`TestResumeRoutes_Wired`、`TestResumeResponses_AllOperationsWrite`」: backend/internal/httpapi/resumes_test.go 846行、1000行、1030行 / 合っていた
- 小タスク5.1「`compat_test.go` と `cross_test.go` と `perf_test.go` の段 `restore-with-token` の期待、`TestSelf_OneCharFakeFails`、`TestSelf_MatchedDiffPasses`」: backend/compat/compat_test.go 94-108行、149行、173行、backend/compat/cross_test.go 189-205行、backend/compat/perf_test.go 15-30行 / 合っていた
- 小タスク5.2「`checkWholeBodyDiffTable` と同じ形」「`checkDiffTableInChangedBehaviors` は `resume` のパッケージのテストの中でしか呼べない」: backend/internal/httpapi/resumes_test.go 1102行、backend/internal/resume/difftable_test.go 17行 / 合っていた
- 小タスク6.3「手本の `scenarios/export/deleted-user.yaml` と `scenarios/users/require-login.yaml`」「`progress.md` のバックアップの行」: backend/compat/scenarios/export/deleted-user.yaml、backend/compat/scenarios/users/require-login.yaml、.kiro/specs/backend-go-replacement/progress.md 41-42行(出力が「比べる検査に通った」、バックアップが未定 / 未着手) / 合っていた
- 小タスク6.5「手本の `scenarios/auth/two-factor-perf.yaml`」「応答の時間を比べた結果の表の、出力の行」: backend/compat/scenarios/auth/two-factor-perf.yaml、.kiro/specs/backend-go-replacement/progress.md 67-68行 / 合っていた
- 実装のメモの1つ目「`run-check.sh --wait` と領域 `backend-go`」: .claude/scripts/parallel/run-check.sh / 合っていた
- 実装のメモの2つ目「`backend/compat/` の下のファイルは、すべて `//go:build compat` を持つ」: backend/compat の下の65の .go ファイル / 合っていた
- 実装のメモの3つ目「`TestCompare_Scenarios` は段の `expect` を確かめない。確かめるのは版をまたぐ検査と時間を測る検査だけ」: backend/compat/harness/steps.go 136行の `checkStepExpect` を呼ぶのは cross.go 184行と perf.go 161行、212行だけ / 合っていた

### 確かめの道具を作るタスク

| 道具 | 作るタスク | 確かめる成果物を作るタスク | 並び |
|---|---|---|---|
| `backup/backup.sql`(経歴書 801 から 805) | 1.1 | 4.2、4.4、4.5、6.1 から 6.3 | 前 |
| `TestFixtures_AllLoadable` の `backup` の場合と `checkBackup` の名前の頭ごとの確かめ方 | 1.1、1.2 | 1.1、1.2、1.3(置くファイル) | 前 |
| `reject-` `lax-` `malformed-` の22のファイル | 1.2 | 6.2 | 前 |
| `java-*.json`、`restore.json`、`backup-unsent.json` | 1.3 | 4.2、4.5、5.2、6.1 | 前 |
| `TestStoreIntegration_UserExists` | 1.5 | 1.5 | 前 |
| CB-062 から CB-066 と `TestLoadChangedBehaviors_CB005HasNoMatch` の数 | 1.6 | 4.2、4.5、6.1 | 前 |
| `json_capture` の欄と `TestLoadScenarios_JSONCaptureExclusive`、`TestCapture_JSONCapture*` | 2.1 | 6.4 | 前 |
| `TestJavaJSON_*`、`TestParseJTree_*`、`TestWTF8_*`、`TestReadRestoreFile_*` | 3.1 から 3.4 | 3.1 から 3.4 | 前 |
| `TestBackup_*`、`TestBuildRestored_*`、`TestErrors_BackupMessages` | 4.1、4.3 | 4.1、4.3 | 前 |
| `TestBackupIntegration_*` | 4.2 | 4.1 | 前 |
| `TestRestoreIntegration_Order`、`_Owner`、`_NoLeftover` | 4.4 | 4.4 | 前 |
| `TestRestoreIntegration_MatchesJava`、`_SurrogateName`、`_DeletedUser` | 4.5 | 4.4 | 前 |
| `TestBackupHandlers_*`、`TestResumeRoutes_*`、`TestResumeResponses_AllOperationsWrite` | 5.1、5.2 | 5.1 | 前 |
| compat の自分のテスト(`TestSelf_` `TestCross_SelfPairPasses` `TestCross_ThreeDirectionsRun` `TestPerf_SelfPairRuns`)の 400 の期待 | 5.1 | 5.1(戻しの受け口) | 前 |
| `TestBackupHandlers_UnsentRequests` | 5.2 | 5.1 | 前 |
| `TestCompare_Scenarios` の6つの筋書きと `make compat` | 6.1 から 6.3 | 4.1、4.4、5.1 | 前 |
| `TestCoverage_Operations`(今ある) | 今ある | 6.3 の進み具合の表 | 前 |
| `TestCrossRoute_BackupSteps` | 6.4(筋書きより先に作る) | 6.4 の `cross-backup.yaml` | 前 |
| `TestLoadScenarios_BackupPerf` | 6.5(筋書きより先に作る) | 6.5 の2つの筋書き | 前 |
| `make compat-cross`、`make compat-perf`(今ある) | 今ある | 6.4、6.5 | 前 |
| API の説明画面の「Try it out」(Playwright) | 今ある | 5.1 | 前 |

### 申告

**1. 要件8の受入基準1、2と、要件8の受入基準3の「比べる検査に通った」を、テストでなく記録の文で確かめる** — 小タスク1.3、7.2、7.3

- Issue の記載: あり。Java 版と同じにできない動きが見つかったら止まることと、進み具合の表を直すこと
- 決めたこと: 控えた答えと research.md の試作の記録の突き合わせ、PR の本文、main の `progress.md` の文で確かめ、テストを書かない
- 他にありえた選択肢: 試作の記録と正解のファイルの食い違いを機械で調べるテストを置く
- 外れていた場合: 突き合わせを Claude が見落とすと、Java 版と同じにできない動きを所有者に報告せずに進む

**2. 筋書きの段ごとの `expect` の正しさを、完了の確かめ方でなく実装のメモの手順(作業フォルダの外の写しで `modes` を `[cross]` に替えて流す)で確かめる** — 実装のメモの3つ目

- Issue の記載: なし
- 決めたこと: `TestCompare_Scenarios` が `expect` を確かめないことを補う手順を、小タスクの完了の確かめ方に入れず、メモに置いた
- 他にありえた選択肢: 6.1 から 6.3 の完了の確かめ方に、この手順を入れる
- 外れていた場合: 誤った `expect` が筋書きに残っても、Java 版と Go 版を比べる検査は通るので、誤りが残ったまま出荷される。比べる検査の合否には影響しない

**3. 画面が送らない要求で Java 版が 500 で答える要求の扱いを、見つけた小タスクの中で決める** — 実装のメモの4つ目、小タスク6.3

- Issue の記載: なし(要件6の受入基準3で決めた)
- 決めたこと: 見つけたときに Go 版の答えを 404 か 400 から選び、変えた動きの一覧と結合テストを足し、筋書きから段を外す。要件6の受入基準1で含めると決めた要求なら止まる
- 他にありえた選択肢: 小タスク1.3 で Java 版の答えを控えるときに 500 の要求を洗い出し、タスクを分ける
- 外れていた場合: 6つ目の大きなまとまりの途中で、変えた動きの一覧と結合テストを足すことになり、5つ目のまとまりの verify をやり直す

### 指摘

| ID | レベル | 該当箇所 | 内容 | 直し方の案 |
|---|---|---|---|---|
| T1-1-1 | 中 | tasks.md 小タスク4.2、4.4、4.5 | `internal/resume` の結合テストは、`main_integration_test.go` の `TestMain` が作る1つの Postgres(`testPool`)をパッケージのすべてのテストで使う。今の `export_integration_test.go` 18-74行の `loadExportFixtures` は、`users/basic.sql` と `resumes/fonts.sql` を含む `exportFixtures` を `sync.Once` で1度だけ入れ、52行のコメントに「2度入れると重なって失敗する」とある。`users/basic.sql` は `ON CONFLICT` の無い INSERT である。小タスク4.2 は「`users/basic.sql` と `resumes/fonts.sql` と `backup/backup.sql` をデータベースに入れて動く」、4.4 は加えて `resume-limits.sql` を入れると書くが、出力の結合テストと同じデータベースに同じファイルを入れる方法を書いていない。書いたとおりにそれぞれのテストで入れると、`go test ./internal/resume/` を流したときに、あとから入れた側が重なりで失敗する。また、4.5 の `TestRestoreIntegration_MatchesJava` は `restore.json` の本文を user2 で順に戻すが、小タスク1.3 の控えは 201 のたびに経歴書を消してから次の本文を送っている。Go 版のテストで消さないと、同じ名前の本文が名前の重なりの誤りになり、Java 版の答えと食い違う | 4.2 と 4.4 に、`backup/backup.sql` と `resumes/resume-limits.sql` を、`exportFixtures` と重ならないように、パッケージで1度だけ入れると書く(たとえば、`exportFixtures` と同じ `sync.Once` の読み込みに足すか、`users/basic.sql` と `resumes/fonts.sql` を除いた2つのファイルを別の `sync.Once` で入れ、先に `loadExportFixtures` を呼ぶ)。4.5 に、`TestRestoreIntegration_MatchesJava` は 201 の答えのたびに作られた経歴書を消してから次の本文を送ると書く。名前に対になっていないサロゲートを含むファイルを2回続けて戻すことも、小タスク1.3 の控え方と同じにすると書く |
| T1-1-2 | 中 | tasks.md 小タスク1.6 の受入基準とテストの対応 | 「CB-062 から CB-066 の文と、`TestLoadChangedBehaviors_CB005HasNoMatch` と `TestLoadChangedBehaviors_RequiredFields` で確かめる」とあるが、`match_test.go` 248-312行の `RequiredFields` は `writeBehaviors` で作った仮のファイルだけを読み、`changed-behaviors.yaml` を読まない。314-345行の `CB005HasNoMatch` は本物のファイルを読むが、項目の数と、名前を挙げた項目(CB-001、CB-005 から CB-027 の一部、CB-006)の match だけを確かめる。CB-062 の match(`backupResume` の3つの欄の `order_only`)と、CB-063 から CB-066 が match を持たないことと、CB-062 の理由の文を確かめるテストは無い。完了条件の1つ目の「確かめるテストの名前を書く」が、確かめていないテストを挙げている(事実の誤り) | 1.6 に、`match_test.go` に CB-062 から CB-066 を確かめるテスト(手本は `TestChangedBehaviors_UserItems` 384行と `TestChangedBehaviors_OwnerDecidedItems` 548行)を足すと書く。そのテストが、CB-062 の match が `backupResume` の `$.resume.careers[*]` `$.resume.projects[*]` `$.resume.certifications[*]` の `order_only` であることと理由の文、CB-063 から CB-066 が `group: 5` で match を持たないことを確かめると書き、受入基準とテストの対応の `RequiredFields` をそのテストの名前に替える。完了の確かめ方の `-run` の式は今のままで、足したテストを含む |
| T1-1-3 | 中 | tasks.md 小タスク1.3 1段落目の最後の文 | 「ログインと CSRF の値の付け方を、`backend/compat/harness/capture.go` の手順に合わせる」とあるが、`capture.go` にあるのは Host の定数 `CompatHost` と、取り出しの元 `cookie:` の読み方だけである。Cookie の束を要求に付け、`XSRF-TOKEN` の Cookie の値を `X-XSRF-TOKEN` のヘッダに写す手順は、`send.go` 22-25行と 151-174行の `prepareVersionRequest` にある。Claude が `capture.go` だけを読むと、CSRF のヘッダの名前と付け方が分からず、Java 版に送る要求が偽の送信の検査で 403 になる(事実の誤り) | 文を「ログインと CSRF の値の付け方を、`backend/compat/harness/send.go` の `prepareVersionRequest`(Host を `compat.test` にし、Cookie の束の Cookie を付け、`XSRF-TOKEN` の Cookie の値を `X-XSRF-TOKEN` のヘッダに写す)に合わせる」に直す |

### 前の段階への指摘

| ID | 対象 | レベル | 作るもの | 該当箇所 | 内容 | 直し方の案 |
|---|---|---|---|---|---|---|
| T1-1-4 | design | 低 | 変わらない | design.md 初期のデータとバックアップのファイルの節 486行 | 「職歴の期間を、経歴書 805 のほかで重ならないようにする」は、経歴書 805 の職歴の期間は重なってよいと読める。だが、小タスク1.1 で `backup.sql` に当てる `TestFixtures_AllLoadable` の決まり(fixtures_test.go 441-455行。職歴の期間の重なり、職歴の始めの月の重なり、案件の期間の重なり、資格の日付の重なり)は、すべての経歴書に当たる。805 の職歴を重ねると、1.1 の完了の確かめ方で失敗する。1.1 の中で気づいて直せるので、実装に影響しない | 「職歴の期間を、経歴書 805 を含むどの経歴書でも重ならないようにし、805 の3件の職歴と案件と資格は、始めの月と日付を別々にする」に直す |

- 往復: 1回目 / 高0 中3 低1

## サイクル1 往復2(2026-11-24)

### 審査の範囲

範囲: 差分

- tasks.md 小タスク1.2、1.3、1.5、3.1、3.2、5.2: 差分は書き方の点検の直し(用語の意味の書き添え、番号だけの指し方の言い足し、文の分け方)と、1.3 の CSRF の手本の差し替え(T1-1-3)である。差分の行を読み、書き添えた用語の説明(サロゲート、BMP、WTF-8)と手本の関数の説明を実ファイルと照らした
- tasks.md 小タスク1.6: T1-1-2 の直しで `TestChangedBehaviors_BackupItems` を足すと書いた。完了の確かめ方の `-run` の式が足すテストを含むかと、手本のテストと `changed-behaviors.yaml` の最後の項目と書式を確かめた
- tasks.md 小タスク4.2、4.4、4.5: T1-1-1 の直しで `loadBackupFixtures` を 4.2 で作り、4.4 と 4.5 が使うと書いた。`loadBackupFixtures` と `loadExportFixtures` と `resume-limits.sql` の語で tasks.md と design.md を検索し、パッケージの共有のデータベースで重なりが起きないか、ほかの結合テストが全体の行の数に頼っていないか、design のテストの方針と `restore.json` の控え方(design.md 391行)と食い違わないか、4.4 と 4.5 の `_依存:_` が道具を作る 4.2 を挙げているかを確かめた
- 前の段階の記録: design-review.md と design-response.md を「tasks」で検索した。後ろの段階で書くと記録された食い違いは無かった(D1-1-1 と D1-1-2 は design の中で直す指摘である)

### 実ファイルで確かめた文

- 小タスク1.3「`prepareVersionRequest` は、要求の Host を `compat.test` にし、ログインで受け取った Cookie を付け、Cookie の `XSRF-TOKEN` の値を `X-XSRF-TOKEN` のヘッダに写す」: backend/compat/harness/send.go 22-26行(`csrfCookie` `csrfHeader`)、151-174行(`prepareVersionRequest`)、backend/compat/harness/capture.go 22行(`CompatHost = "compat.test"`) / 合っていた
- 小タスク1.6「手本は `TestChangedBehaviors_UserItems` と `TestChangedBehaviors_OwnerDecidedItems`」「項目の数は `TestLoadChangedBehaviors_CB005HasNoMatch` で確かめる」: backend/compat/harness/match_test.go 314行、384行、548行 / 合っていた
- 小タスク1.6「CB-062 から CB-066 を `changed-behaviors.yaml` の末尾に足す」「画面に影響が無い理由」: backend/compat/changed-behaviors.yaml 766-781行(最後の項目は CB-061 で、欄の名前は `画面に影響が無い理由`、match を書かない項目はコメントで理由を書く) / 合っていた
- 小タスク4.2「`loadExportFixtures` が `users/basic.sql` と `resumes/fonts.sql` を含む初期のデータを1度だけ入れる」「同じファイルを2度入れると重なって失敗する」: backend/internal/resume/export_integration_test.go 18-27行(`exportFixtures` に basic.sql と fonts.sql を含む6つのファイル)、46-74行(`sync.Once`、52行のコメント) / 合っていた
- 小タスク4.2「`resumes/resume-limits.sql` を `loadBackupFixtures` で1度だけ入れる」: backend/compat/fixtures/resumes/resume-limits.sql 1-20行(利用者 500 と経歴書 501 から 550 を自分で入れ、basic.sql と一緒に使う)。`internal/resume` の結合テストで `resume-limits.sql` を入れるほかの箇所は無い(Grep)。全体の行の数を数えるテストは main_integration_test.go 112-122行のマスタの表だけで、経歴書の行の数はどれも利用者か経歴書の ID で絞っている(service_integration_test.go 241-248行、431行、store_integration_test.go 451-457行) / 合っていた
- 小タスク4.5「user2 で戻す」: backend/internal/resume/export_integration_test.go 29-33行(初期のデータの経歴書はすべて user1 のもの)。user2 の経歴書を作るほかの結合テストは無い(Grep) / 合っていた
- 小タスク5.2「`checkDiffTableInChangedBehaviors` は `resume` のパッケージのテストの中でしか呼べない」: 往復1で確かめた backend/internal/resume/difftable_test.go 17行(`_test.go` の中の関数)から文の分け方だけが変わった / 合っていた

### 確かめの道具を作るタスク

| 道具 | 作るタスク | 確かめる成果物を作るタスク | 並び |
|---|---|---|---|
| `TestFixtures_AllLoadable` と `checkBackup` の名前の頭ごとの確かめ方 | 1.1、1.2 | 1.2、1.3(置くファイル) | 前 |
| `send.go` の `prepareVersionRequest`(今ある。控えの手順の手本) | 今ある | 1.3 | 前 |
| `TestStoreIntegration_UserExists` | 1.5 | 1.5 | 前 |
| `TestChangedBehaviors_BackupItems` と `TestLoadChangedBehaviors_CB005HasNoMatch` の数 | 1.6 | 1.6 | 前 |
| `TestJavaJSON_Escapes`、`TestParseJTree_LoneSurrogate` | 3.1、3.2 | 3.1、3.2 | 前 |
| `loadBackupFixtures`(`backup/backup.sql` と `resumes/resume-limits.sql`) | 4.2 | 4.1、4.4、4.5 | 前(4.4 と 4.5 の `_依存:_` に 4.2 が無い。T1-2-1) |
| `TestBackupIntegration_*` | 4.2 | 4.1 | 前 |
| `TestRestoreIntegration_Order`、`_Owner`、`_NoLeftover` | 4.4 | 4.4 | 前 |
| `TestRestoreIntegration_MatchesJava`、`_SurrogateName`、`_DeletedUser` と `restore.json` | 4.5、1.3 | 4.4 | 前 |
| `TestBackupHandlers_UnsentRequests` と `backup-unsent.json` | 5.2、1.3 | 5.1 | 前 |

### 申告

差分で、新しく申告するものは無い。往復1の申告1から3は、差分で変わっていない。

### 指摘

| ID | レベル | 該当箇所 | 内容 | 直し方の案 |
|---|---|---|---|---|
| T1-2-1 | 低 | tasks.md 小タスク4.4 と 4.5 の `_依存:_` | T1-1-1 の直しで、4.4 の `TestRestoreIntegration_*` と 4.5 のテストは、小タスク4.2 が `backup_integration_test.go` に作る `loadBackupFixtures` を呼んでから動くと書いた。`loadBackupFixtures` は確かめの道具で、`.kiro/settings/rules/spec-writing.md` 178行は「道具を使うタスクの `_依存:_` に、道具を作るタスクの番号を書く」と決めている。だが、4.4 の `_依存:_` は 1.5, 3.4, 4.3、4.5 は 1.3, 1.6 で、どちらも 4.2 を挙げない(`loadBackupFixtures` が入れる `backup.sql` を作る 1.1 も挙げない)。4.4 と 4.5 は `(並行可)` でなく、番号の順に 4.2 のあとに進むので、実装には影響しない。`/kiro-impl` で 4.4 だけを選んだときに、`_依存:_` の確かめ(kiro-impl の SKILL.md 71行)で 4.2 が先に要ることが分からない | 4.4 の `_依存:_` に 4.2 を足し、4.5 の `_依存:_` に 4.2 を足す(4.2 が 1.1 と 1.3 に依存するので、1.1 は 4.2 を通して満たされる) |

### 前の段階への指摘

差分の中に、前の段階の穴は無い。

- 往復: 2回で収束 / 未解決: 0件
