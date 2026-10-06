## サイクル1 往復1(2026-10-06)

審査の材料: Issue #499 の本文、`requirements.md`、`design.md`、`tasks.md`、`research.md`、`spec.json`、`reviews/requirements-review.md` `requirements-response.md` `design-review.md` `design-response.md` `tasks-style.md`、steering 3本、雛形 `.kiro/settings/templates/specs/tasks.md`、`.kiro/settings/rules/spec-writing.md`、`.claude/skills/kiro-spec-tasks/rules/tasks-generation.md`、`.claude/skills/kiro-impl/SKILL.md`、`.claude/skills/verify-ui/SKILL.md`、`.claude/scripts/parallel/ui.sh`(L192〜L209: `kp_<鍵>` の作成と `spring.datasource.url` の上書き、backend のポートをホストに公開)、`.mcp.json`(Playwright MCP は `docker run -i --rm` で動き、ホストのフォルダを共有していない)、`V5__allow_nullable_portfolio_tech_stack.sql`、`application.yaml`(L17〜L20)、`application-test.yaml`、`PostgresTestContainerConfig.java`、`ResumeMapperTest.java`(`spring.flyway.target=5`、`insertProject` `insertPortfolio` のテスト)、`UserMapperTest.java` ほか(`spring.flyway.target=1`)、`ProjectTest.java` L257〜L279(`test14`)、`PortfolioTest.java` L125〜L139(`test9`)、`doc/DB設計/ER図.pu` L73・L75・L139、`frontend/src/features/resume/hooks/useExportResume.ts` `useBackupResume.ts`(`saveAs` でブラウザに保存)、`ResumePdfPreviewModal.tsx`(iframe で表示)、`protectedApiClient.ts`(`withCredentials: true`)、PDF と Markdown のテンプレート、既存の spec の tasks.md(小タスクを持たない大タスクの前例)。

要件カバレッジ: 要件1の受入基準1〜4はタスク2.1、受入基準5はタスク3、要件2の受入基準1はタスク3、要件3の受入基準1はタスク1の `_要件:_` に現れている。requirements.md に無い番号を指すタスクは無い。

design カバレッジ: V6 と `ProjectPortfolioTextColumnMigrationTest` はタスク1、`ResumeMapperTest` はタスク2.1、ER図はタスク2.2、変えない部品(入力の検査と読み出しの経路)はタスク3で扱っている。`_対象の部品:_` はどれも design の `## ファイルの構成` の範囲に収まっている。移行の節の「確かめる点」は所有者がマージの前に行う作業なので、タスクに無くてよい。

スコープ膨張: requirements の「決めないこと」と design の「作らないもの」に当たる作業はタスクに無い。

完了条件の4項目: 雛形どおり4項目とも書かれている。置き換えは無い。

並列と依存: 2.1(`ResumeMapperTest`)と 2.2(`ER図.pu`)は触るファイルが別で、同時に進めても衝突しない。2.1 の `_依存: 1_` は、V6 が無いと target を6にできないので正しい。小タスクを持たない大タスク(1と3)は雛形が認める形で、既存の spec(`git-bash-path-conversion-guard`)で実装まで進んだ前例がある。

テストの実現性: `PostgresTestContainerConfig` のコンテナは Spring の文脈ごとに作られ、`ResumeMapperTest` の文脈は `spring.flyway.target` の値で区別されるので、タスク2.1の「target を5に戻すと足した2つのテストが失敗する」は成り立つ。タスク1の「V6 の SQL から1つの列の変更を外すと検査が失敗する」も成り立つ。

### 申告

**1. バックアップ・PDF・Markdown の出力に1000文字の文章が入ることを、自動テストを足さずに `/verify-ui` の操作だけで確かめる** — tasks.md タスク3

- Issue の記載: なし(保存できることだけが書かれている)
- 決めたこと: 要件1の受入基準5(開き直した画面・バックアップ・PDF・Markdown に欠けずに出る)を、タスク3の画面操作で1回だけ確かめる。design の「テストの方針」の「読み出しの経路の自動テストは足さない」をそのまま受けている
- 他にありえた選択肢: 既存の `ThymeleafResumePdfExporterTest` `ThymeleafResumeMarkdownExporterTest` に、1000文字の「概要」「役割」を持つ職務経歴書で出力に文章が欠けないことを確かめるテストを足す
- 外れていた場合: 受入基準5は実装のときに1回だけ手で確かめた記録しか残らず、CI では確かめられない。テンプレートは文章を切り詰めずに載せる(`simple.html` L365・L377・L436、`default.md` L30・L38・L203)ので、今の動きが変わるおそれは小さい

### 指摘

| ID | レベル | 該当箇所 | 内容 | 直し方の案 |
|---|---|---|---|---|
| T1-1-1 | 中 | tasks.md タスク3(「その職務経歴書のバックアップ、PDF の出力、Markdown の出力に3つの欄の文章が欠けずに入っていることを確かめる」と完了の確かめ方) | 3つの出力の中身を Claude がどうやって読むかが書かれていない。画面のバックアップ・PDF・Markdown は `saveAs`(`useBackupResume.ts` `useExportResume.ts`)でブラウザに保存される。`/verify-ui` の Playwright のブラウザは `.mcp.json` のとおり `docker run -i --rm` の別のコンテナで動き、ホストのフォルダを共有していないので、保存されたファイルは Claude の手元に届かない。PDF のプレビュー(`ResumePdfPreviewModal.tsx`)も blob の URL を iframe で表示する形で、スクリーンショットから1000文字が欠けていないかは読み取れない。このままだと、実装のときに Claude が確かめる手段を自分で決めるか、確かめられないまま「確かめた」と記録するかのどちらかになり、受入基準5の確認が形だけになる | タスク3に、3つの出力の中身を読む手段を書く。たとえば、バックアップと Markdown は、ログイン済みの画面から Playwright の `browser_evaluate` で `GET /api/resumes/{id}/backup` と `GET /api/resumes/{id}/export`(`Accept: text/markdown`)を `credentials: "include"` で呼び、返った文字列に入れた1000文字の文章が含まれることを確かめる。PDF は、文字を取り出す手段が Playwright MCP に無いので、`ui.sh` がホストに公開する backend のポート(`localhost:<18080+枠>`)から取ったファイルを文字に直す手段を書くか、それが無ければ既存の `ThymeleafResumePdfExporterTest` に1000文字の「概要」「役割」「ポートフォリオの概要」を持つ職務経歴書で出力に文章が欠けないことを確かめるテストを足すタスクにする(後者は design の「テストの方針」の「読み出しの経路の自動テストは足さない」の見直しになるので、下の「前の段階への指摘」にも書く) |
| T1-1-2 | 低 | tasks.md タスク3(「`flyway_schema_history` に V6 が `success` として記録されたことを確かめてから」) | `kp_<鍵>` の鍵の求め方と、データベースを読むコマンドが書かれていない。鍵は `.claude/scripts/parallel` のスクリプトが作業フォルダから求めるもので、読むには `docker compose -p keirekipro exec -T db psql -U postgres -d kp_<鍵>` の形が要る。実装のときに Claude がスクリプトを読めば分かるので、実装には影響しない | 「鍵は `ui.sh` と同じ求め方で得て、`docker compose -p keirekipro exec -T db psql -U postgres -d kp_<鍵> -c "SELECT version, success FROM flyway_schema_history"` で読む」のように手段を書き添える |

### 前の段階への指摘

| ID | 対象 | 該当箇所 | 内容 |
|---|---|---|---|
| T1-1-3 | design | design.md テストの方針(「画面を通しで操作するテスト: `/verify-ui` で…バックアップ、PDF の出力、Markdown の出力に、3つの欄の文章が欠けずに入っていることを確かめる」「読み出しの経路の自動テストは足さない」) | T1-1-1 のとおり、`/verify-ui` の Playwright のブラウザは別のコンテナで動き、保存されたファイルは Claude の手元に届かない。バックアップと Markdown は画面から API を呼んで文字列を読めるが、PDF は Playwright MCP に文字を取り出す手段が無い。PDF の確認を手で行う前提が成り立たないときは、「読み出しの経路の自動テストは足さない」を見直し、`ThymeleafResumePdfExporterTest` に1000文字の文章を持つ職務経歴書のテストを足す形に変えることになる。戻る先は design |

- 往復: 1回目 / 高0 中1 低1

## サイクル2 往復1(2026-10-06)

審査の材料: Issue #499 の本文(`additional_issues` は無し)、`requirements.md`(承認済み)、`design.md`(サイクル2で再承認済み)、作り直した `tasks.md`、`spec.json`(`approval_history` に T1-1-3 による取り消しの記録)、`reviews/tasks-review.md` `tasks-response.md` `design-review.md` `design-response.md` `tasks-style.md`、steering 3本、`backend/CLAUDE.md` `frontend/CLAUDE.md`、雛形 `.kiro/settings/templates/specs/tasks.md`、`.kiro/settings/rules/spec-writing.md`(tasks.md の見本と、見出しと目印の一覧)、`.claude/skills/kiro-impl/SKILL.md`(`_依存:_` `_対象の部品:_` `(並行可)` の読み方)、`.claude/skills/verify-ui/SKILL.md`(`ui.sh start` の呼び方と報告の形にスクリーンショットの添付があること)、`.claude/scripts/parallel/ui.sh` L132〜L209(`kp_folder_key` で鍵を求め、`docker compose -p keirekipro exec -T db psql -U postgres` で `kp_<鍵>` を作り、`spring.datasource.url` を上書きして作業フォルダの backend を起動する)、`.claude/scripts/parallel/lib.sh` L40〜L69(`kp_folder` は `git rev-parse --show-toplevel`、`kp_folder_key` はそのパスの `git hash-object` の先頭12文字)、`compose.yaml`(サービス名 `db`、`POSTGRES_USER: postgres`)、`ResumeMapperTest.java`(`spring.flyway.target=5`、`insertProject` `selectProjectsByResumeId` `insertPortfolio` `selectPortfoliosByResumeId` のテスト)、`ResumeQueryMapperTest.java`(`spring.flyway.target=1`、test15 が `selectResumeForBackup` の JSON を読む。L481 `insertProject(UUID, UUID)` と L536 `insertPortfolio(UUID, UUID, String)` は文章を固定で入れる)、`ResumeExportModelBuilderTest.java`(`MockitoExtension` と `mock()` で `Resume` を組み立てて `build` を呼ぶ形)、`ProjectTest.java` L257(`test14`「各項目が最大文字数を超える場合、エラーが収集される」)、`PortfolioTest.java` L125(`test9`、同じ名前)、`Project.java` L288・L300、`Portfolio.java` L148(エラーの文)、`ProjectSection.tsx` L223〜L260(`TextField` に `maxLength` は無く、エラーは `helperText` で出る)、`doc/DB設計/ER図.pu` L73・L75・L139(`VARCHAR(255)`)と L76・L140(`TEXT` の書き方)、`backend/src/main/resources/db/migration/`(V1〜V5 があり V6 は無い)。

前回の指摘への対応: T1-1-1(バックアップ・PDF・Markdown の中身を `/verify-ui` で確かめられない)は、作り直した tasks.md で、バックアップがタスク2.2(`ResumeQueryMapperTest`)、PDF と Markdown がタスク2.3(`ResumeExportModelBuilderTest`)の自動テストに移り、タスク3の画面の操作は「開き直した画面の表示」と「1001文字のエラー」だけになった。タスク3の本文と完了の確かめ方から、バックアップ・PDF・Markdown の記述は消えている。T1-1-2(`kp_<鍵>` の求め方)は、タスク3に「`ui.sh` と同じく `lib.sh` の `kp_folder_key` で求める」と `psql` のコマンドが書かれた。コマンドの形(`-p keirekipro` `exec -T db` `-U postgres` `-d kp_<鍵>`)は `ui.sh` L194・L198 と一致し、`kp_folder_key` は作業フォルダの中で `git rev-parse` から求まるので、Claude が作業フォルダで呼べば得られる。どちらも対応されている。

要件カバレッジ: 要件1の受入基準1〜4はタスク2.1、受入基準5はタスク2.2(バックアップ)・2.3(PDF と Markdown)・3(画面の表示)、要件2の受入基準1はタスク3、要件3の受入基準1はタスク1の `_要件:_` に現れている。requirements.md に無い番号を指すタスクは無い。タスク2.4は受入基準を満たさない作業で、`_要件:_` を書かない理由が本文にある。

design カバレッジ: V6 と `ProjectPortfolioTextColumnMigrationTest` はタスク1、`ResumeMapperTest` は2.1、`ResumeQueryMapperTest` は2.2、`ResumeExportModelBuilderTest` は2.3、ER図は2.4、変えない部品(入力の検査と読み出しの経路)はタスク3で扱っている。design の「作るもの」5項目と「ファイルの構成」の新しく作る2ファイル・変える4ファイルは、すべていずれかのタスクに出ている。`_対象の部品:_` はどれも「ファイルの構成」の範囲に収まっている。移行の節の「確かめる点」は所有者がマージの前に行う作業なので、タスクに無くてよい。

スコープ膨張: requirements の「決めないこと」と design の「作らないもの」に当たる作業はタスクに無い。タスク2.2が足す「文章を引数で受け取るデータを入れる関数」はテストの中の関数で、「読み出しの経路のコードの変更」(main のコード)には当たらない。

完了条件の4項目: 雛形どおり4項目とも書かれている。置き換えは無い。タスク2.4は `doc/` だけを変え、該当する verify のスキルが無いが、項目2は「変えた領域の verify のスキル」なので置き換えではない。

並列と依存: 2.1(`ResumeMapperTest`)・2.2(`ResumeQueryMapperTest`)・2.3(`ResumeExportModelBuilderTest`)・2.4(`ER図.pu`)は触るファイルがすべて別で、同時に進めても衝突しない。2.1 と 2.2 の `_依存: 1_` は、V6 が無いと target を6にできないので正しい。2.3 はモックで `Resume` を組み立てる単体テストで、2.4 は設計図なので、V6 に依らず `_依存:_` が無いのは正しい。タスク3は並びの順で1と2のあとになり、`_依存:_` が無くてよい(tasks-style.md の判断と同じ)。

テストの実現性: タスク2.2の「target を1に戻すと足したテストが失敗する」は、V1 の `VARCHAR(255)` に1000文字の多バイトの文章を入れると挿入が失敗するので成り立つ。2.1 と 2.2 をどちらも target=6 にすると注釈の組み合わせが同じで1つの Spring の文脈を共有するが、`@MybatisTest` はテストごとにロールバックするので、互いのデータは残らない。タスク2.3の「`ResumeExportModelBuilder` で3つの値を1つずつ先頭の255文字に切るとそのたびに失敗する」は、`build` が値をそのまま入れている(L56・L58・L98)ので成り立つ。タスク3の「今と同じエラーの文」は、`ProjectSection.tsx` の `TextField` に `maxLength` が無く、backend の検査のエラーが `helperText` に出る形なので、1001文字を入れて保存すれば `Project.java` L288 の文が出る。タスク3の `ProjectTest` `test14` と `PortfolioTest` `test9` の名前は実ファイルと一致する。

### 申告

**1. PDF と Markdown の出力のファイルの中身は、タスクでは確かめない** — tasks.md タスク2.3、タスク3

- Issue の記載: なし(保存できることだけが書かれている)
- 決めたこと: 要件1の受入基準5のうち PDF と Markdown は、出力の元になるデータ(`ResumeExportModelBuilder.build` の戻り値)に同じ文章が入ることだけをタスク2.3で確かめ、出力のファイルを読むテストと画面からの出力の操作は行わない。design のサイクル2で所有者が了承した形(design-review の申告3)をそのまま受けている
- 他にありえた選択肢: `ThymeleafResumePdfExporterTest` `ThymeleafResumeMarkdownExporterTest` に1000文字の文章を持つ職務経歴書で出力のファイルに文章が欠けないことを確かめるテストを足すタスクを置く
- 外れていた場合: テンプレートや出力の部品が文章を切り詰めるように変わったとき、CI では気づけない。今のテンプレート(`simple.html` `default.md`)は値をそのまま書き出すので、この spec の範囲では影響しない

**2. 要件3の受入基準1の「利用者がその職務経歴書を開いたら今までと同じ文章を表示する」を、画面の操作ではなく、マイグレーションのテストの読み直しで確かめる** — tasks.md タスク1、タスク3

- Issue の記載: なし
- 決めたこと: V6 の前に保存した文章が変わらないことを `ProjectPortfolioTextColumnMigrationTest` の JDBC の読み直しで確かめ、画面の操作(タスク3)では V6 のあとに保存した1000文字の表示だけを確かめる。V6 の前からある職務経歴書を画面で開く操作はタスクに無い
- 他にありえた選択肢: タスク3で、V6 を適用する前の `kp_<鍵>` に短い文章の職務経歴書を作っておき、V6 のあとに開いて同じ文章が出ることも操作で確かめる
- 外れていた場合: 画面の表示の経路は変えず、design の移行の節の「確かめる点」で所有者がマージの前に既存の職務経歴書が開けることを確かめるので、見落としが本番に残るおそれは小さい

### 指摘

なし。

### 前の段階への指摘

なし。

- 往復: 1回目 / 高0 中0 低0
- 往復: 1回で収束 / 未解決: 0件
