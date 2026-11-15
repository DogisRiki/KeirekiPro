# tasks のレビューの記録

## サイクル1 往復1(2026-11-14)

### 審査の範囲

範囲: 全体

### 実ファイルで確かめた文

- 小タスク1.1「research.md の『確かめた環境』は、`spring` のコンテナの中の別の Java 版、データベース `keireki_proto`、Redis の DB 7 を使い、`keireki_pro` と DB 0 に触れない」: .kiro/specs/backend-go-master-resumes/research.md 9-13行 / 合っていた
- 小タスク1.1「試作の入力はリポジトリに無い」: research.md 13行(試作のコードはリポジトリに入れていない)、backend/internal の一覧に `resume/testdata` が無い / 合っていた
- 小タスク1.1「research.md に P4、P5、P8、P9、P10〜P12 の節がある」: research.md 37-85行 / 合っていた
- 小タスク1.2「`server.go` の `ErrorHandlerFunc` は無名の関数である」: backend/internal/httpapi/server.go 137-145行 / 合っていた
- 小タスク1.2「`server_test.go` に、項目の ID に `not-a-uuid` を入れた経路を使う副テストが2つある」: backend/internal/httpapi/server_test.go 135-139行、338-340行 / 合っていた
- 小タスク1.2と1.3「`make generate` と `make generate-check` がある。sqlc の出力は `sqlcgen`」: backend/Makefile 17行、38-70行 / 合っていた
- 小タスク1.3「Java 版に `ResumeMapper.xml` と3つのマスタの `*QueryMapper.xml` がある」: backend/src/main/java/com/example/keirekipro/infrastructure/repository/resume/ResumeMapper.xml、infrastructure/query/ の下の3つの `*QueryMapper.xml`(Glob で確かめた) / 合っていた
- 小タスク1.4「`internal/users` に結合テストの入口があり、testcontainers-go で PostgreSQL を動かす」: backend/internal/users/main_integration_test.go 16-18行 / 合っていた
- 小タスク1.4「`make lint` がある」: backend/Makefile 81-82行 / 合っていた
- 小タスク1.4「文言の定数を Java 版のソースの文字列と比べるテストの形」: backend/internal/users/errors_test.go 5-21行(同じ名前 `TestErrors_MessagesMatchJava`) / 合っていた
- 小タスク2.8「`go.mod` の `golang.org/x/text` に `// indirect` が付いている」: backend/go.mod 170行 / 合っていた
- 小タスク4.2「`versions.go` の `JavaEnv` に `TZ` が無く、`TestJavaEnv_DevProfileAndOIDCEndpoints` が環境の値の数も確かめる」: backend/compat/harness/versions.go 70-72行(`TZ` の語が無い)、backend/compat/harness/versions_test.go 48-71行 / 合っていた
- 小タスク4.3「3つのファイルが、未実装の答えを確かめるために経歴書の削除の経路 `/api/resumes/00000000-0000-4000-8000-000000000201` を使い、『経歴書の操作はまだ 501 を返す』という注釈を持つ」: backend/compat/compat_test.go 91-107行、backend/compat/cross_test.go 188-205行、backend/compat/perf_test.go 13-30行 / 合っていた
- 小タスク4.3「`POST /api/resumes/restore` は、偽の送信の検査が働く書き込みの操作で、JSON の本文を受ける」: backend/api/openapi.yaml 665-693行 / 合っていた
- 小タスク4.3「Go 版の生成したコードは、本文を読んでから受け口を呼ぶ」: backend/internal/httpapi/gen/api.gen.go 4939-4942行(`RestoreResumeRequestObject` の `Body`)、1266-1267行、backend/internal/httpapi/server.go 117-121行(本文を読めなければ 400) / 合っていた
- 小タスク4.3「筋書きの要求に `json` と `csrf: true` を書ける」: backend/compat/harness/scenario.go 161-164行 / 合っていた
- 小タスク4.3と6.6「`make compat` がある」: backend/Makefile 126-128行 / 合っていた
- 小タスク5.2「`ResumeHandlers` が無いときの未実装の答えを確かめるテストが `server_test.go` にある形」: backend/internal/httpapi/server_test.go 96行、604行 / 合っていた
- 小タスク6.1〜6.6「`TestCompare_Scenarios` が `./compat/` にあり、副テストの名前は筋書きの `name` である」: backend/compat/compat_test.go 35-60行 / 合っていた
- 小タスク6.7「`backend/compat/harness/cross_test.go` に、版をまたぐ筋書きの送り先を確かめるテストの形がある」: backend/compat/harness/cross_test.go 61行、180行 / 合っていた
- 小タスク6.7「`make compat-cross` が `TestCross_Scenarios` を動かす」: backend/Makefile 130-132行、backend/compat/cross_test.go 264行 / 合っていた
- 小タスク6.8「`fixtures/resumes/fonts.sql` の経歴書は、6つの欄のすべてに項目を持つ」: backend/compat/fixtures/resumes/fonts.sql 5-65行 / 合っていた
- 小タスク6.8「`make compat-perf` が `TestPerf_Scenarios` を動かし、`progress.md` に結果の表と決まりがある」: backend/Makefile 134-136行、backend/compat/perf_test.go 69行、.kiro/specs/backend-go-replacement/progress.md 46-63行 / 合っていた
- 小タスク7.1「開発環境の compose に `backend-go` と、ポート 8082 の `api-docs` がある」: compose.yaml 40行、75-82行 / 合っていた
- 小タスク7.2「`progress.md` のまとまりの表にマスタと経歴書の行があり、今は spec の列が『未定』、状態の列が『未着手』である」: .kiro/specs/backend-go-replacement/progress.md 34-40行 / 合っていた
- 小タスク7.2「状態の列を『作り終えた』にすると、`TestCoverage_Operations` が、マスタと経歴書の操作がすべて `group: 3` の筋書きに出てくることを求め始める」: backend/compat/compat_test.go 64-89行、backend/compat/harness/coverage.go 15-20行、110-140行、backend/compat/harness/operations.go 26-32行 / 合っていた
- 小タスク7.3「`/ship` は、PR がマージされたことを確かめるまで見届け、tasks.md に残りのタスクがあれば続きを案内する」: .claude/skills/ship/SKILL.md 109行、324行 / 合っていた
- 実装のメモ「`backend/compat/` の下のファイルは、すべて `//go:build compat` を持つ」: backend/compat の下の `*.go` 65個のすべてに `//go:build compat` がある(Glob と Grep の数で確かめた) / 合っていた
- 実装のメモ「選んで流しても、Java 版と Go 版のイメージは毎回組み立てられる」: backend/compat/compat_test.go 44行 / 合っていた
- 実装のメモ「`internal/resume` の結合テストは `make test` で毎回動く」: backend/Makefile 84-86行、backend/internal/users/main_integration_test.go(ビルドタグが無い) / 合っていた
- 完了条件「4項目は雛形と同じ」: .kiro/settings/templates/specs/tasks.md 31-38行 / 合っていた
- 完了条件「`.kiro/steering/tech.md` に『テストの完全性』がある」: .kiro/steering/tech.md 59-71行 / 合っていた

### 確かめの道具を作るタスク

| 道具 | 作るタスク | 確かめる成果物を作るタスク | 並び |
|---|---|---|---|
| `internal/resume/testdata/` の5つの正解のファイル | 1.1 | 2.1、2.2、2.3、2.4、2.8 | 前 |
| `internal/httpapi/testdata/resumebody/` の正解のファイル | 1.1 | 5.2 | 前 |
| UTF-8 として誤ったバイトを含む本文への Java 版の答え | 1.1(research.md に書くだけ。正解のファイルは無い) | 2.4 | 前。ただし使うテストが無い(T1-1-1) |
| `make generate` `make generate-check` | 今ある | 1.2、1.3 | 前 |
| `TestParamErrorHandler`(`server_internal_test.go`) | 1.2 | 1.2 | 同じタスク |
| 結合テストの入口 `main_integration_test.go` | 1.4 | 3.1〜3.6 | 前 |
| `TestErrors_MessagesMatchJava` | 1.4 | 1.4 | 同じタスク |
| `TestJackDate_MatchesJava` `TestJavaUUID_MatchesJava` `TestCompareJavaUUID_SignedOrder` `TestLink_MatchesJava` `TestDecodeBody_MatchesJava` `TestValidate_*` `TestRules_*` `TestOrder_MatchesJava` | 2.1〜2.8(それぞれ同じタスク) | 2.1〜2.8 | 同じタスク |
| `/verify-backend`(2つ目の大きなまとまりの最後) | 今ある | 2.1〜2.8 | 2.8 が `(並行可)` なので、2.3 と 2.7 より先に流れうる(T1-1-2) |
| `TestStore_*` `TestService_*` | 3.1〜3.6(それぞれ同じタスク) | 3.1〜3.6 | 同じタスク |
| `<wallclock:形:+秒>` の置き換えと比べ方、そのテスト | 4.1 | 6.1〜6.7 | 前 |
| Java 版の `TZ=Asia/Tokyo` と `TestJavaEnv_DevProfileAndOIDCEndpoints` | 4.2 | 6.1〜6.7 | 前 |
| 未実装の答えを確かめる3つのファイルのテスト(経歴書の復元に替えたもの) | 4.3 | 5.2 | 前 |
| `TestResumeHandlers_*` | 5.1 | 5.1 | 同じタスク |
| `TestResumeRoutes_*` | 5.2 | 5.2 | 同じタスク |
| 初期のデータ `resume-ops.sql` | 6.1 | 6.2〜6.6 | 前 |
| 初期のデータ `resume-limits.sql` | 6.1 | 6.5 | 前 |
| `TestCompare_Scenarios/<name>` | 今ある | 6.1〜6.6 | 前 |
| 変えた動きの一覧の CB-050(文言の並びの match) | 6.2 | 6.2、6.3、6.4 | 前 |
| `TestCoverage_Operations` がマスタと経歴書の26の操作を求める状態(`progress.md` の「作り終えた」) | 7.2 | 6.1〜6.6 | 後ろ(T1-1-3) |
| `TestCrossRoute_ResumeSteps` | 6.7(筋書きより先に作る) | 6.7 | 同じタスク |
| `make compat-cross` の `TestCross_Scenarios` | 今ある | 6.7 | 前 |
| `make compat-perf` の `TestPerf_Scenarios` | 今ある | 6.8 | 前 |
| API の説明画面(`api-docs`)と Playwright | 今ある | 7.1 | 前 |

### 申告

**1. 正解のファイルの入力を作り直し、件数を試作と同じにしない** — 小タスク1.1

- Issue の記載: なし
- 決めたこと: 試作の入力がリポジトリに無いので、research.md の P4、P5、P8、P9、P10〜P12 の書き方と値の種類をすべて含む入力を作り直す。件数は試作と同じでなくてよい
- 他にありえた選択肢: design のテストの方針の件数(年月と日付 103件、ID 36件、リンク 57件)と同じ件数になるまで入力を足す
- 外れていた場合: 試作で Java 版と比べた書き方のうち、research.md の文に種類として書かれていないものが正解のファイルから落ち、その書き方で Go 版が Java 版と違っても単体テストで見つからない

**2. UTF-8 として誤ったバイトを含む本文で Java 版と同じにできないときは、止まって所有者に報告する** — 小タスク1.1、2.4

- Issue の記載: なし
- 決めたこと: Java 版の扱いが Go の `encoding/json` と違えば小タスク2.4 で Java 版と同じ答えにし、同じにできなければ要件6の受入基準2のとおりに止まる
- 他にありえた選択肢: research.md の「危うい点と備え」に書いてある、変えた動きの一覧に足して所有者に報告する進め方
- 外れていた場合: 実装の途中で止まり、所有者の判断を待つ時間が増える。動きが変わることは無い

**3. 「比べる検査に通った」を、この spec の PR のマージのあとの別の PR で書く** — 小タスク7.3

- Issue の記載: なし
- 決めたこと: この spec の PR では状態を「作り終えた」にし、マージを確かめたあとに、main から新しいブランチを作って「比べる検査に通った」にする PR を出す
- 他にありえた選択肢: この spec の PR の中で、CI の Java 版と Go 版を比べる検査が通ったあとに書く。または、認証と利用者のまとまりと同じく「作り終えた」のままにする(progress.md 36-37行)
- 外れていた場合: PR が1つ増える。マージのあとに会話が途切れると、小タスク7.3 が `- [ ]` のまま残る

**4. 未実装の答えを確かめる検査の経路を、経歴書の復元に移す** — 小タスク4.3

- Issue の記載: なし
- 決めたこと: `POST /api/resumes/restore` に本文 `{}` と `csrf: true` を付けて送り、501 を期待する
- 他にありえた選択肢: 出力のまとまりの `POST /api/resumes/{resumeId}/export`。または、未実装の操作に頼らない確かめ方に書き直す
- 外れていた場合: バックアップのまとまりの spec で経歴書の復元を作るときに、同じ3つのファイルをもう一度書き直す

**5. 進み具合の表で「spec の作成中」を書かずに「作り終えた」にする** — 小タスク7.2

- Issue の記載: なし
- 決めたこと: この spec の PR は最初の PR であり、26の操作を作り終えた PR でもあるので、状態を「未着手」から「作り終えた」にする
- 他にありえた選択肢: design の「進み具合の表」の節のとおり、最初の PR で「spec の作成中」にする PR を分ける
- 外れていた場合: 実装の間、main の進み具合の表のマスタと経歴書の行が「未着手」のままに見える

### 指摘

| ID | レベル | 該当箇所 | 内容 | 直し方の案 |
|---|---|---|---|---|
| T1-1-1 | 中 | tasks.md 小タスク1.1、2.4 | UTF-8 として誤ったバイトを含む本文への答えを確かめるテストが、どのタスクの「完了の確かめ方」にも「受入基準とテストの対応」にも無い。小タスク1.1 は Java 版の答えを research.md に書くだけで、正解のファイルに置かない。小タスク2.4 は「違うときは Java 版と同じ答えにする」と書くが、完了の確かめ方は `TestDecodeBody_MatchesJava`(型の違う値を入れた本文)だけである。筋書きの `json` の欄は YAML の値なので、誤ったバイトを筋書きで送ることもできない(backend/compat/harness/scenario.go 164行)。そのため、Go 版が Java 版と違う答えを返しても、どの検査でも見つからない(要件1の受入基準1) | 小タスク1.1 で、誤ったバイトを含む本文への Java 版の状態の番号と本文とデータベースの値を、正解のファイルに置く。小タスク2.4 か5.2 の「完了の確かめ方」と「受入基準とテストの対応」に、その正解のファイルと比べるテストの名前を足す。Java 版と Go 版の読み方が同じだった場合も、同じであることをこのテストで確かめる |
| T1-1-2 | 中 | tasks.md 小タスク2.8 | 小タスク2.8 は `(並行可)` で、依存は小タスク2.2 だけである。一方で、完了の確かめ方は「2つ目の大きなまとまりの最後のタスクなので `/verify-backend` も通る」と書く。小タスク2.8 が、同じ `(並行可)` の小タスク2.3 と2.7 と並行に進むと、`/verify-backend` が、2.3 か 2.7 の書きかけのファイルを含めて流れるか、2.3 と 2.7 の成果物を含まずに流れる。完了条件の2つ目の、まとまりの最後の確認が、まとまりの全部のタスクを見ないことになる。小タスク2.8 は `go.mod` も変えるので、並行に流れているほかのタスクのテストの組み立てにも当たる | 小タスク2.8 の題名から `(並行可)` を外す。または、`_依存:_` に 2.3、2.6、2.7 を足す |
| T1-1-3 | 中 | tasks.md 小タスク7.2、6.1〜6.6 | マスタと経歴書の26の操作がすべて `group: 3` の筋書きに出てくるかを機械で確かめる `TestCoverage_Operations` は、`progress.md` の状態が「作り終えた」になるまで、このまとまりの操作を求めない(backend/compat/harness/coverage.go 17行、135行)。状態を「作り終えた」にするのは小タスク7.2 で、筋書きを書く小タスク6.1〜6.6 より後ろである。小タスク6.6 の `make compat` は、操作が筋書きから漏れていても通る。漏れは小タスク7.2 で初めて見つかり、6つ目の大きなまとまりに戻ることになる。`.kiro/settings/rules/spec-writing.md` の「確かめの道具を作るタスクを、使うタスクより前に置く」から外れている | `progress.md` の spec の列と状態の列を書く作業(小タスク7.2 の1つ目)を、比べる動かし方の筋書きを書き終える小タスク6.6 に移し、小タスク6.6 の完了の確かめ方に `go test -tags compat -run TestCoverage_Operations ./compat/` を足す。小タスク7.2 には、research.md の書き足しと PR の本文の作業を残す |
| T1-1-4 | 低 | tasks.md 小タスク1.1 の完了の確かめ方 | 説明の文は、項目の並びの P8 の書き方と値の種類も入力に含めると書くが、完了の確かめ方が挙げる節は P4、P5、P9、P10〜P12 で、P8 が無い | 完了の確かめ方に P8 を足す |
| T1-1-5 | 低 | tasks.md 小タスク2.4、2.8 の `_依存:_` | 小タスク2.1、2.2、2.3 は、小タスク1.1 の正解のファイルを使うので `_依存: 1.1_` を持つ。同じく正解のファイルを使う小タスク2.4 には `_依存:_` が無く、小タスク2.8 の `_依存:_` には 1.1 が無い。小タスク1.1 は前の大きなまとまりにあるので、実装の順は変わらない | 小タスク2.4 に `_依存: 1.1, 2.1, 2.2_` を、小タスク2.8 の `_依存:_` に 1.1 を足す |

### 前の段階への指摘

| ID | 対象 | 該当箇所 | 内容 |
|---|---|---|---|
| T1-1-6 | design | design.md `## ファイルの構成` | tasks.md が作るか変えるファイルのうち、次の3つが design のファイルの構成に無い。(1) 小タスク1.1 と5.2 の `backend/internal/httpapi/testdata/resumebody/`。(2) 小タスク6.7 が `TestCrossRoute_ResumeSteps` を足す `backend/compat/harness/cross_test.go`。design の「変えるファイル」にあるのは `backend/compat/cross_test.go` だけで、このテストは design のテストの方針にも無い。(3) `backend/internal/resume/testdata/` の中身。design は「年月と日付、ID、リンク、本文の読み方」の4つと書き、tasks.md は項目の並びを足した5つと書く。design に戻る指摘である |
| T1-1-7 | design | design.md `## テストの方針` の単体テスト | design は、`jackdate.go` を「試作の P5 の103件」、`javauuid.go` を「試作の P9 の36件」、`link.go` を「試作の P4 の57件」で確かめると書く。試作の入力はリポジトリに無く(research.md 13行)、tasks.md の小タスク1.1 は入力を作り直し、件数は同じでなくてよいとした。design の件数のとおりには確かめられない。design に戻る指摘である(申告の1つ目) |

- 往復: 1回目 / 高0 中3 低2

## サイクル2 往復1(2026-11-15)

### 審査の範囲

範囲: 全体

### 実ファイルで確かめた文

- 小タスク1.1「research.md の『確かめた環境』は、`spring` のコンテナの中の別の Java 版、データベース `keireki_proto`、Redis の DB 7 を使い、`keireki_pro` と DB 0 に触れない。試作の入力はリポジトリに無い」: .kiro/specs/backend-go-master-resumes/research.md 11-13行 / 合っていた
- 小タスク1.1「research.md に P4、P5、P8、P9、P10〜P12 の節と『危うい点と備え』がある」: research.md 37-85行、141-143行 / 合っていた
- 小タスク1.2「`server.go` の `ErrorHandlerFunc` は無名の関数で、`server_test.go` に `not-a-uuid` の経路を使う副テストが2つある」: backend/internal/httpapi/server.go 137行、backend/internal/httpapi/server_test.go 137行、340行(`TestBadJSONReturns400MessageErrors` 123行、`TestNew_AuthQueryError400` 324行の中) / 合っていた
- 小タスク1.2と1.3「`make generate` と `make generate-check` があり、sqlc の出力も比べる」: backend/Makefile 38-70行 / 合っていた
- 小タスク1.3「Java 版に `ResumeMapper.xml` と3つのマスタの `*QueryMapper.xml` がある」: backend/src/main/java/com/example/keirekipro/infrastructure/repository/resume/ResumeMapper.xml、infrastructure/query/ の certification、snsplatform、techstack の `*QueryMapper.xml`(Glob) / 合っていた
- 小タスク1.4「`internal/users` の `service_test.go` に `TestNew_DefaultsNowToTimeNow` と `TestNew_KeepsGivenDeps` がある」: backend/internal/users/service_test.go 11行、25行 / 合っていた
- 小タスク1.4「`internal/users` の結合テストの入口は、testcontainers-go の PostgreSQL に Java 版のマイグレーションを当てる」: backend/internal/users/main_integration_test.go 56-93行 / 合っていた
- 小タスク1.4「`TestErrors_MessagesMatchJava` の形がある。`make lint` がある」: backend/internal/users/errors_test.go 7行、backend/Makefile 81-82行 / 合っていた
- 小タスク1.4ほか「`/verify-backend` は Go 版で `make check` を流す。カバレッジの下限は生成したコードを数えない」: .claude/skills/verify-backend/SKILL.md 45-48行、backend/.testcoverage.yml 9-15行(小タスク1.3 の `sqlcgen` の出力はまとまりの最後の確認で下限を下げない) / 合っていた
- 小タスク2.8「`go.mod` の `golang.org/x/text` に `// indirect` が付いている」: backend/go.mod 170行 / 合っていた
- 小タスク4.1「今の日時の置き換えは、秒の小数の桁を形に入れない」: backend/compat/harness/normalize.go 19行、32行、203-223行 / 合っていた
- 小タスク4.2「`JavaEnv` に `TZ` が無く、`TestJavaEnv_DevProfileAndOIDCEndpoints` の `assertEnv` が環境の値の数も確かめる」: backend/compat/harness/versions.go 72-92行、backend/compat/harness/versions_test.go 48-71行 / 合っていた
- 小タスク4.3「3つのファイルが経歴書の削除の経路と段の名前 `delete-with-token` を使い、`compat_test.go` が段の名前と操作の名前 `deleteResume` を確かめ、match に `deleteResume` を書く」: backend/compat/compat_test.go 92-107行、161-165行、178行、backend/compat/cross_test.go 189-205行、backend/compat/perf_test.go 15-30行 / 合っていた
- 小タスク4.3「経歴書の復元 `POST /api/resumes/restore` の操作の名前は `restoreResume` で、偽の送信の検査のヘッダを持ち、JSON の本文を受け、バックアップのまとまりの操作である」: backend/api/openapi.yaml 665-693行、backend/compat/harness/operations.go 123行 / 合っていた
- 小タスク4.3と5.2「経歴書の受け口をつないだあとに、ログインした利用者の経歴書の操作に 501 を期待する箇所は、3つのファイルのほかに無い」: backend/compat/scenarios/auth/require-login.yaml 23-38行(401)、backend/compat/scenarios/auth/validation.yaml 137-142行(403)、backend/cmd/keirekipro/main_test.go 766-825行(401 と 403 とプリフライト) / 合っていた
- 小タスク5.2「`main_test.go` に手本の `TestRun_PassesUserHandlers` がある。`Options` に `UserHandlers` があり、無ければ未実装の答えのままにする」: backend/cmd/keirekipro/main_test.go 858行、backend/internal/httpapi/server.go 46-48行、104-105行、backend/internal/httpapi/server_test.go 604行 / 合っていた
- 小タスク6.1〜6.6「`TestCompare_Scenarios` の副テストの名前は筋書きの `name` で、選んで流してもイメージを組み立てる」: backend/compat/compat_test.go 35-60行 / 合っていた
- 小タスク6.6「`progress.md` のマスタと経歴書の行は今『未定』『未着手』で、状態を『作り終えた』にすると `TestCoverage_Operations` がまとまりの操作を比べる動かし方の筋書きに求める」: .kiro/specs/backend-go-replacement/progress.md 38行、backend/compat/harness/coverage.go 17行、110-139行、backend/compat/compat_test.go 64-89行 / 合っていた
- 小タスク6.6と4.3「`make compat` は `TestCross_` と `TestPerf_` のほかを流す」: backend/Makefile 127-128行 / 合っていた
- 小タスク6.7「`backend/compat/harness/cross_test.go` に手本の `TestCrossRoute_UserSteps` があり、筋書きのファイルが無ければ失敗する。`make compat-cross` が `TestCross_Scenarios` を動かす」: backend/compat/harness/cross_test.go 175-229行、backend/Makefile 131-132行、backend/compat/cross_test.go 264行 / 合っていた
- 小タスク6.8「`fonts.sql` の経歴書は user1 のもので、6つの欄のすべてに項目を持つ。`make compat-perf` が `TestPerf_Scenarios` を動かし、`progress.md` に結果の表がある」: backend/compat/fixtures/resumes/fonts.sql 1-67行、backend/Makefile 135-136行、backend/compat/perf_test.go 69行、progress.md 46-63行 / 合っていた
- 小タスク7.1「compose に `backend-go` と、ポート 8082 の `api-docs` がある」: compose.yaml 40-49行、76-82行 / 合っていた
- 実装のメモ「`run-check.sh` に領域 `backend-go` がある。`(並行可)` のタスクも1つずつ進む」: .claude/scripts/parallel/run-check.sh(`backend-go` が8か所)、.claude/skills/kiro-impl/SKILL.md 181行 / 合っていた
- 実装のメモ「`internal/resume` の結合テストは `make test` で毎回動く」: backend/Makefile 85-86行 / 合っていた
- 完了条件「4項目は雛形と同じ」: .kiro/settings/templates/specs/tasks.md 31-38行 / 合っていた

### 確かめの道具を作るタスク

| 道具 | 作るタスク | 確かめる成果物を作るタスク | 並び |
|---|---|---|---|
| `internal/resume/testdata/` の6つの正解のファイル | 1.1 | 2.1、2.2、2.3、2.4、2.8 | 前 |
| `internal/httpapi/testdata/resumebody/` の正解のファイル | 1.1 | 5.2 | 前 |
| `make generate` `make generate-check` | 今ある | 1.2、1.3 | 前 |
| `TestParamErrorHandler` | 1.2 | 1.2 | 同じタスク |
| `TestNew_DefaultsNowToTimeNow` `TestNew_KeepsGivenDeps` `TestErrors_MessagesMatchJava` | 1.4 | 1.4 | 同じタスク |
| 結合テストの入口 `main_integration_test.go` | 1.4 | 3.1〜3.6 | 前 |
| `TestJackDate_MatchesJava` `TestJavaUUID_MatchesJava` `TestCompareJavaUUID_SignedOrder` `TestLink_MatchesJava` `TestDecodeBody_MatchesJava` `TestDecodeBody_InvalidUTF8MatchesJava` `TestValidate_*` `TestRules_*` `TestOrder_MatchesJava` | 2.1〜2.8(それぞれ同じタスク) | 2.1〜2.8 | 同じタスク |
| `TestStore_*` | 3.1 | 3.1 | 同じタスク |
| `TestService_Masters*` `TestService_GetResume*` `TestService_DeleteResume*` `TestService_ListResumes*` `TestService_CreateResume*` | 3.2〜3.4(それぞれ同じタスク) | 3.2〜3.4 | 同じタスク |
| `TestService_UpdateResumeBasic*` | 無い(小タスク3.4 の `-run` の式にだけあり、テストの名前がどこにも無い。T2-1-1) | 3.4 | 道具が無い(T2-1-1) |
| `TestService_Career*` `TestService_EditResume*` `TestService_ProjectWithTechStack` | 3.5 | 3.5 | 同じタスク |
| プロジェクトの欄の `OtherUser` `OfOtherResume` `CreateOtherUserAtLimit` `UnreadableItemID` のテスト | 無い(T2-1-2) | 3.5 | 道具が無い(T2-1-2) |
| `TestService_<欄>*`(資格、ポートフォリオ、SNS、自己PR) | 3.6 | 3.6 | 同じタスク |
| `<wallclock:形:+秒>` の置き換えと比べ方と、そのテスト | 4.1 | 6.1〜6.7 | 前 |
| Java 版の `TZ=Asia/Tokyo` と `TestJavaEnv_DevProfileAndOIDCEndpoints` | 4.2 | 6.1〜6.7 | 前 |
| 未実装の答えを確かめる3つのファイルのテスト(経歴書の復元に替えたもの) | 4.3 | 5.2 | 前 |
| `make compat`(今ある認証と利用者の筋書き) | 今ある | 4.1、4.2 | 前(4.3 で流す) |
| `TestResumeHandlers_*` | 5.1 | 5.1 | 同じタスク |
| `TestResumeRoutes_*` `TestRun_PassesResumeHandlers` | 5.2 | 5.2 | 同じタスク |
| 初期のデータ `resume-ops.sql` `resume-limits.sql` | 6.1 | 6.2〜6.6 | 前 |
| `TestCompare_Scenarios/<name>` | 今ある | 6.1〜6.6 | 前 |
| 変えた動きの一覧の CB-050 の match | 6.2 | 6.2、6.3、6.4 | 前 |
| `TestCoverage_Operations` がマスタと経歴書の26の操作を求める状態(`progress.md` の「作り終えた」) | 6.6 | 6.1〜6.6 | 同じまとまりの中(筋書きを書き終える小タスクで求め始める。サイクル1の T1-1-3 の直し方のとおり) |
| `TestCrossRoute_ResumeSteps` | 6.7(筋書きより先に作る) | 6.7 | 同じタスク |
| `make compat-cross` の `TestCross_Scenarios` | 今ある | 6.7 | 前 |
| `make compat-perf` の `TestPerf_Scenarios` と `fonts.sql` | 今ある | 6.8 | 前 |
| API の説明画面(`api-docs`)と Playwright | 今ある | 7.1 | 前 |

### 申告

**1. 答えを変えた3つの要求(CB-047、CB-048、CB-049)への Go 版の答えを、筋書きでなく結合テストと受け口のテストだけで確かめる** — 小タスク3.4、3.5、3.6、5.1、6.6

- Issue の記載: なし
- 決めたこと: Java 版と Go 版で答えが違う要求は筋書きで送らず、`service_integration_test.go` と `resumes_test.go` で Go 版の答えを確かめる
- 他にありえた選択肢: 変えた動きの一覧に match を書き、筋書きでも送って Go 版の答えの状態の番号を確かめる
- 外れていた場合: 結合テストに欄の抜けがあると、その欄の答えはどの検査でも確かめられない(指摘 T2-1-2 がこの例である)

**2. 「比べる検査に通った」を、この spec の PR のマージのあとの別の PR で書く** — 小タスク7.3

- Issue の記載: なし
- 決めたこと: この spec の PR では状態を「作り終えた」にし、マージを確かめたあとに、main から新しいブランチを作って「比べる検査に通った」にする PR を出す
- 他にありえた選択肢: 認証と利用者のまとまりと同じく「作り終えた」のままにする(progress.md 36-37行)
- 外れていた場合: PR が1つ増える。マージのあとに会話が途切れると、小タスク7.3 が `- [ ]` のまま main に残る

**3. 筋書きを書く途中で見つけた、Java 版が 500 で答えるほかの要求を、止まらずに変えた動きの一覧に足す** — 小タスク6.6

- Issue の記載: なし
- 決めたこと: 見つけた要求ごとに1つの違いを `changed-behaviors.yaml` に足して進める
- 他にありえた選択肢: 見つけるたびに止まり、Go 版の答えを所有者に確かめてから足す
- 外れていた場合: 所有者が見ていない答えの違いが変えた動きの一覧に入る。所有者がそれを知るのは PR の差分か報告だけになる

### 指摘

| ID | レベル | 該当箇所 | 内容 | 直し方の案 |
|---|---|---|---|---|
| T2-1-1 | 中 | tasks.md 小タスク3.4 | 小タスク3.4 は `UpdateResumeBasic` を作り、説明の文で「更新の日時に丸める前の値を返し、作成の日時にデータベースから読んだ値を返す」と決めるが、「受入基準とテストの対応」に `UpdateResumeBasic` を確かめるテストの名前が1つも無い。完了の確かめ方の `-run 'TestService_(CreateResume|UpdateResumeBasic)'` は、`TestService_UpdateResumeBasic*` が1件も無くても通る。design のテストの方針は、`Now` が `.1234565` 秒を返すときの答えの日時を、Service の節の「作成と変更の操作が返す経歴書の日時」のとおり(基本の情報の更新を含む)確かめると決めている。`UpdateResumeBasic` は `editResume` を通らないので、小タスク3.5 の `TestService_EditResumeReturnsUnroundedUpdatedAt` では確かめられない。Java 版と Go 版を比べる検査は秒の小数の桁を比べない(backend/compat/harness/normalize.go 19行。`<wallclock:形:+秒>` の形も同じ)ので、基本の情報の更新の答えの日時が Java 版と違っても、どの検査でも見つからない(要件1の受入基準1) | 小タスク3.4 の「受入基準とテストの対応」に、`TestService_UpdateResumeBasicReturnsUnroundedUpdatedAt` のような名前のテストを足す。このテストは、`Now` に `.1234565` 秒を返させ、答えの更新の日時が `.1234565` のままで、作成の日時がデータベースの値と同じで、データベースの更新の日時が `.123457` になることを確かめる |
| T2-1-2 | 中 | tasks.md 小タスク3.5 | 小タスク3.5 は職歴とプロジェクトの2つの欄を作るが、ほかの利用者の経歴書(`OtherUser`)、別の経歴書の項目(`OfOtherResume`)、ほかの利用者の上限に達した経歴書への追加(`CreateOtherUserAtLimit`)、読めない項目の ID(`UnreadableItemID`)のテストは職歴にしか無い。プロジェクトのテストは `TestService_ProjectWithTechStack` だけである。小タスク3.6 は残りの4つの欄のすべてにこの4種のテストを置くので、6つの欄のうちプロジェクトだけが抜けている。上限の確かめと項目の ID の読み方は欄ごとの関数にあり(design の全体の構成「欄ごとに違うのは、本文の読み方と、検査と、書く SQL」)、職歴のテストではプロジェクトの関数を確かめられない。上限に達した経歴書への追加と読めない項目の ID は、筋書きで送らない(design の筋書きの節と CB-047、CB-048)ので、プロジェクトの欄の要件3の受入基準3と要件4の受入基準4は、どの検査でも確かめられない | 小タスク3.5 の「受入基準とテストの対応」と完了の確かめ方に、`TestService_ProjectOtherUser`、`TestService_ProjectOfOtherResume`、`TestService_ProjectCreateOtherUserAtLimit`、`TestService_ProjectUnreadableItemID` を足す。小タスク3.6 と同じく `TestService_<欄>…` の形で、`<欄>` を `Career` と `Project` にしてもよい |
| T2-1-3 | 低 | tasks.md 小タスク2.6 | 小タスク2.5 は、どのテストも、空白だけの値、全角の空白だけの値、長さの上限とその1つ上(絵文字を含む値)、1899年と1900年と2100年と2101年の値を含むと書く。小タスク2.6 には、この境界の値の文が無い。design のテストの方針は、8つの要求の型のすべてで境界の値を確かめると決めている。入力欄ごとの境界は小タスク6.3 と6.4 の筋書きでも送るので、抜けは後の検査で見つかる | 小タスク2.6 の「受入基準とテストの対応」に、小タスク2.5 と同じ境界の値の文を足す |
| T2-1-4 | 低 | tasks.md 小タスク2.6 の `_依存:_` | 小タスク2.6 は小タスク2.3 の `isHibernateHTTPSURL` を使うが、`_依存: 2.3_` が無い。小タスク2.3 は `(並行可)` である。`/kiro-impl` はタスクを番号の順に1つずつ進める(.claude/skills/kiro-impl/SKILL.md 181行)ので、実装の順は変わらない | 小タスク2.6 に `_依存: 2.3_` を足す |
| T2-1-5 | 低 | tasks.md 小タスク2.8、4.3 | 小タスク2.8 は、`_要件:_` と `_依存:_` の間に、目印でも欄でもない箇条「この小タスクは…並行に進めない」を持つ。見本の箇条書きの形(完了の確かめ方、受入基準とテストの対応、目印)から外れている。小タスク4.3 の `_要件: 4.2_` は、データベースを比べる受入基準を指すが、この小タスクは未実装の答えを確かめるテストの移し替えで、受入基準を直接は確かめない。どちらも実装には影響しない | 小タスク2.8 の箇条の文を説明の文に移す。小タスク4.3 の `_要件:_` は、そのままでもよい |

### 前の段階への指摘

無い。

- 往復: 1回目 / 高0 中2 低3

## サイクル2 往復2(2026-11-15)

### 審査の範囲

範囲: 差分

- tasks.md 小タスク3.4 の「受入基準とテストの対応」と説明の文: T2-1-1 の直しで `TestService_UpdateResumeBasicReturnsUnroundedUpdatedAt` が足され、1つの文が7つの箇条に分けられた。足したテストが design の決まりと合うかを見るために、design.md の Service の節の「作成と変更の操作が返す経歴書の日時」(248-251行)とテストの方針(617行)を読んだ
- tasks.md 小タスク3.5 の「受入基準とテストの対応」: T2-1-2 の直しで、4種のテストが `<欄>` を `Career` と `Project` にする形に書き直された。同じ形を使う小タスク3.6 と、完了の確かめ方の `-run` の式、`_要件:_` の番号(3.1、3.2、3.3、4.4)、requirements.md の要件3の受入基準1から3と要件4の受入基準4、design.md の `editResume` の節(99行、246行)と CB-047、CB-048(477行、510-511行)を、食い違いが無いかを見るために読んだ
- tasks.md 小タスク5.1 の「受入基準とテストの対応」: 1つの文が5つの箇条に分けられ、3つの箇条に「要件1の受入基準1のうち」が足された。`_要件: 1.1, 4.4_` と design.md の受け口の節の日時の書き方(370行)とテストの方針(599行)を読んだ
- tasks.md 小タスク1.1、1.3、2.4、2.6、2.8、3.2、4.3、6.8 の書き方の直し: 語と主語と文の区切りだけが変わった行である。直す前と意味が変わっていないかを、行ごとに比べた。意味の変わった行は無いので、ほかの箇所への影響は無いと判断した
- 小タスク6.6 の「この3つの要求への Go 版の答えは、小タスク3.4、3.5、3.6 の `service_integration_test.go` と、小タスク5.1 の `resumes_test.go` で確かめる」: 小タスク3.5 のテストの名前が増えたので読んだ。文はファイルの名前で指しており、直しの影響を受けない

### 実ファイルで確かめた文

- 小タスク1.3「Java 版に `ResumeMapper.xml` と、3つのマスタの `*QueryMapper.xml` がある」: backend/src/main/java/com/example/keirekipro/infrastructure/repository/resume/ResumeMapper.xml、infrastructure/query/ の certification、snsplatform、techstack の `*QueryMapper.xml`(Glob) / 合っていた
- 小タスク2.8「`go.mod` の `golang.org/x/text` に `// indirect` が付いている」: backend/go.mod 170行 / 合っていた
- 小タスク3.4「Java 版は、作成の答えの作成と更新の日時に丸める前の値を返す」: design.md 248-251行と research.md の P2 を指す文で、サイクル2 往復1 から書き換えたのは主語だけである。リポジトリの実ファイルでは確かめていない(Java 版を動かした結果の記録である)
- 小タスク4.3「3つのファイルに、段の名前 `delete-with-token` と、操作の名前 `deleteResume` と、『経歴書の操作はまだ 501 を返す』という注釈がある」: backend/compat/compat_test.go 92行、105行、161-165行、178行、backend/compat/cross_test.go 189行、202行、backend/compat/perf_test.go 15行、28行 / 合っていた
- 小タスク6.8「`fonts.sql` の経歴書は、6つの欄のすべてに項目を持つ。`progress.md` に、応答の時間の結果の表と決まりがある」: backend/compat/fixtures/resumes/fonts.sql 5-65行(`resumes` と6つの欄の表と `project_tech_stacks` への INSERT)、.kiro/specs/backend-go-replacement/progress.md 46-63行 / 合っていた

### 確かめの道具を作るタスク

| 道具 | 作るタスク | 確かめる成果物を作るタスク | 並び |
|---|---|---|---|
| `TestService_UpdateResumeBasicReturnsUnroundedUpdatedAt` と、小タスク3.4 のほかの6つのテスト | 3.4 | 3.4 | 同じタスク |
| `TestService_<欄>OtherUser` `TestService_<欄>OfOtherResume` `TestService_<欄>CreateOtherUserAtLimit` `TestService_<欄>UnreadableItemID`(`<欄>` は `Career` と `Project`) | 3.5 | 3.5 | 同じタスク |
| `TestService_CareerOverlap` `TestService_EditResumeConcurrentLimit` `TestService_ProjectWithTechStack` `TestService_EditResumeReturnsUnroundedUpdatedAt` | 3.5 | 3.5 | 同じタスク |
| 結合テストの入口 `main_integration_test.go` | 1.4 | 3.4、3.5 | 前 |
| `TestResumeHandlers_SuccessResponses` `TestResumeHandlers_OmitEmpty` `TestResumeHandlers_ProcessSwap` `TestResumeHandlers_DateTimeFormat` `TestResumeHandlers_UnreadableItemID` | 5.1 | 5.1 | 同じタスク |
| `internal/resume/testdata/` の6つの正解のファイル | 1.1 | 2.4、2.8 | 前 |
| `make generate` `make generate-check` | 今ある | 1.3 | 前 |
| `TestService_Masters*` | 3.2 | 3.2 | 同じタスク |
| `TestValidate_(Project|Portfolio|SnsPlatform|SelfPromotion)` | 2.6 | 2.6 | 同じタスク |
| 未実装の答えを確かめる3つのファイルのテスト(経歴書の復元に替えたもの)と `make compat` | 4.3 と、今ある | 4.1、4.2、5.2 | 前 |
| `make compat-perf` の `TestPerf_Scenarios` と `fonts.sql` | 今ある | 6.8 | 前 |

### 申告

差分の中に、新しく申告するものは無い。サイクル2 往復1 の3件は変わっていない。

### 指摘

無い。

T2-1-1 と T2-1-2 の直しを確かめた結果は、次のとおりである。

- T2-1-1: 小タスク3.4 の「受入基準とテストの対応」に `TestService_UpdateResumeBasicReturnsUnroundedUpdatedAt` が入り、完了の確かめ方の `-run 'TestService_(CreateResume|UpdateResumeBasic)'` で選ばれる。テストが確かめる中身(更新の日時が `.1234565` のまま、作成の日時がデータベースの値と同じ)は、design.md 251行の決まりと合う。箇条の数は「次の7つのテスト」の文と合う
- T2-1-2: 小タスク3.5 の4種のテストが `Career` と `Project` の2つの欄に置かれ、完了の確かめ方の `-run 'TestService_(EditResume|Career|Project)'` で選ばれる。要件の番号と受入基準の中身は、requirements.md 126-128行、144行と合う。小タスク3.6 と合わせて、6つの欄のすべてに4種のテストがある。「ほかに、次の4つのテスト」の箇条の数も合う

### 前の段階への指摘

無い。

- 往復: 2回で収束 / 未解決: 0件
