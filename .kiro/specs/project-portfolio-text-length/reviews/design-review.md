## サイクル1 往復1(2026-10-06)

審査の材料: Issue #499 の本文、`requirements.md`、`design.md`、`research.md`、`spec.json`、`reviews/requirements-review.md` と `requirements-response.md`、steering 3本、雛形 `.kiro/settings/templates/specs/design.md`、`backend/CLAUDE.md`、`V1__create_tables.sql`(L117・L119・L262 が `VARCHAR(255)`、`achievement` と `tech_stack` は `TEXT`)、`V5__allow_nullable_portfolio_tech_stack.sql`(1行コメントの形)、`doc/DB設計/ER図.pu`(L73・L75・L139)、`application.yaml`(`flyway.enabled` `baseline-on-migrate` `baseline-version` のみ)、`application-test.yaml`、`build.gradle`(`flyway-core` `flyway-database-postgresql` は `implementation`、`org.testcontainers:postgresql` `junit-jupiter` は `testImplementation`)、`ResumeMapperTest.java`(`@MybatisTest` + `spring.flyway.target=5`)、`PostgresTestContainerConfig.java`(`postgres:17.7-alpine`)、`Project.java` `Portfolio.java`(1000文字の検査)、`ProjectTest.java` L266・L268、`PortfolioTest.java` L130、`BackendArchitectureTest.java`(`DoNotIncludeTests`)、`ResumeMapper.java`(`insertProject` `selectProjectsByResumeId` `insertPortfolio` `selectPortfoliosByResumeId`)、`CreateProjectRequest.java` ほかの `@Size(max = 1000)`、`.github/workflows/guardrails.yaml`(`migration-label`)。

要件カバレッジ: 要件1の受入基準1〜4は V6 と `ResumeMapperTest` に足す2つのテスト、受入基準5は既存の読み出しの経路と `/verify-ui` の確認、要件2の受入基準1は変えない入力の検査と既存の `ProjectTest` `PortfolioTest`、要件3の受入基準1は `ProjectPortfolioTextColumnMigrationTest` に対応している。ID だけで実現する要素が無い要件は無い。

決まりの節: 雛形の7項目はすべて「関係のある項目」か「関係のない項目」のどちらかに出ている。`## ファイルの構成` に `.github/` や `*.gradle` のファイルは無く、新しいライブラリも出てこないので、節の記載と本文に矛盾は無い。外部サービスの機能は使わないので7項目目は関係のない項目でよい。

実現できるか: `flyway-core` は `implementation` なのでテストのクラスパスにあり、`Flyway.configure()...target("5").load().migrate()` は Flyway 10 の API で書ける。`VARCHAR` から `TEXT` への変更が表を書き直さないこと、Flyway が既定で `future` を無視すること(`ignoreMigrationPatterns` の既定 `*:future`)、PostgreSQL が DDL をトランザクションで取り消せることは、research.md の参考と一致している。ER図の行番号も実ファイルと一致している。

### 申告

**1. 3つの列を `TEXT` にした(`VARCHAR(1000)` にしなかった)** — design.md 概要、部品 V6、設計を見直すきっかけ

- Issue の記載: なし(「1000文字まで保存できる」とだけある。列の型は書かれていない)
- 決めたこと: `projects.overview` `projects.role` `portfolios.overview` を `TEXT` に変え、上限の文字数は入力の検査だけが持つ
- 他にありえた選択肢: `VARCHAR(1000)` にし、保存先の側にも長さの歯止めを残す
- 外れていた場合: `TEXT` にしたあとで保存先に歯止めを戻すには、もう1つマイグレーションが要る。入力の検査を通らずに書き込む経路は今は無い(research.md)ので、今の動きには影響しない

**2. 戻すマイグレーションを作らず、不具合のときはアプリだけを前の版に戻す** — design.md 作らないもの、移行の「元に戻す条件」

- Issue の記載: なし
- 決めたこと: V6 を1段で終え、保存先の型は戻さない。不具合のときは所有者がアプリだけを前の版に戻し、Flyway が V6 を `future` として無視することで前の版を起動させる
- 他にありえた選択肢: `VARCHAR(255)` に戻すマイグレーションを用意する(256文字以上の行があると失敗するので、戻せる条件が限られる)
- 外れていた場合: 本番で V6 を適用したあとに保存先を元の形に戻したくなったときに、256文字以上の行を手で短くしてからでないと戻せない。アプリだけを戻す運用で足りる限り、影響は無い

### 指摘

| ID | レベル | 該当箇所 | 内容 | 直し方の案 |
|---|---|---|---|---|
| D1-1-1 | 低 | design.md 概要(「上限の文字数(1000文字)は、今までどおりドメイン層の入力の検査(…`validate`)だけが決める」) | 1000文字の上限は、ドメイン層のほかに presentation 層の `CreateProjectRequest` `UpdateProjectRequest` `CreatePortfolioRequest` `UpdatePortfolioRequest` の `@Size(max = 1000)` にもある。「ドメイン層…だけ」は事実と少し違う。「設計を見直すきっかけ」の「入力の検査だけを直せばよい」は両方を含むと読めるので矛盾ではないが、上限を変えるときに presentation 層を見落とす手がかりになりうる。この spec では上限を変えないので実装には影響しない | 「ドメイン層の入力の検査」を「入力の検査(presentation 層の `@Size` とドメイン層の `validate`)」のように書き、上限が2か所にあることを示す |
| D1-1-2 | 低 | design.md ファイルの構成(`unit/infrastructure/migration/ProjectPortfolioTextColumnMigrationTest.java`) | `backend/CLAUDE.md` のテスト方針は「mainと同じ集約構造」で置くとしているが、main に `infrastructure/migration` のパッケージは無い。ArchUnit は `DoNotIncludeTests` でテストを外しているので機械的には止まらず、実装にも影響しない | 置き場所をそのままにするなら、設計に「main に対応するパッケージは無いが、マイグレーションのテストの置き場所として新しく作る」と一言添える。または `unit/infrastructure/repository/resume/` に置く |

### 前の段階への指摘

なし。

- 往復: 1回目 / 高0 中0 低2
- 往復: 1回で収束 / 未解決: 0件

## サイクル2 往復1(2026-10-06)

審査の材料: Issue #499 の本文(`additional_issues` は無し)、`requirements.md`(承認済み)、`design.md`(差し戻し後の本文)、`tasks.md`、`research.md`、`spec.json`(`approval_history` に T1-1-3 による取り消しの記録)、`reviews/design-review.md` `design-response.md` `tasks-review.md` `tasks-response.md` `design-style.md`、steering 3本、雛形 `.kiro/settings/templates/specs/design.md`、`backend/CLAUDE.md`、`ResumeQueryMapperTest.java`(`@MybatisTest` + `spring.flyway.target=1`、test15 が `selectResumeForBackup` の JSON から `projects[0].overview` `role` `portfolios[0].overview` を読む)、`ResumeQueryMapper.xml`(L62・L64・L140 で3つの列をそのまま JSON に入れる)、`ResumeExportModelBuilderTest.java`(Mockito のモックで `Resume` を組み立てて `build` を呼ぶ形。`overview` `role` の検証が L175・L177・L231 にある)、`ResumeExportModelBuilder.java`(L56・L58・L98 で値をそのまま入れる)、`simple.html`(L365・L377・L436 の `th:text`)、`default.md`(L30・L38・L203 の `[[...]]`。切り詰める式は無い)、`PostgresTestContainerConfig.java`(文脈ごとの Bean)、`ResumeMapperTest.java`(注釈の組み合わせが `ResumeQueryMapperTest` と同じ)、`UserMapperTest.java` ほか(target=1)、V2〜V5 のマイグレーション(マスタの追加と変更・`user_token_versions`・`tech_stack` の NOT NULL 解除)、`doc/DB設計/ER図.pu` L73・L75・L139。

差し戻しの対応: T1-1-3 のとおり、読み出しの経路の確認が `ResumeQueryMapperTest`(バックアップの JSON)と `ResumeExportModelBuilderTest`(出力の元になるデータ)に移り、画面の操作は開き直した画面の表示と1001文字のエラーだけになった。「作るもの」「ファイルの構成」「部品」「テストの方針」の4か所が同じ内容を指しており、食い違いは無い。「作らないもの」の「読み出しの経路のコードの変更」は、テストを足すだけで main のコードを変えないので破っていない。

要件カバレッジ: 要件1の受入基準1〜4は V6 と `ResumeMapperTest`、受入基準5は画面の表示が `/verify-ui`、バックアップが `ResumeQueryMapperTest`、PDF と Markdown が `ResumeExportModelBuilderTest`、要件2の受入基準1は変えない入力の検査と既存の `ProjectTest` `PortfolioTest` と `/verify-ui`、要件3の受入基準1は `ProjectPortfolioTextColumnMigrationTest` に対応している。

決まりの節: 雛形の7項目はすべてどちらかに出ている。足すのはテストだけで `src/main/java` のクラスは変えず、`.github/` `*.gradle` のファイルも新しいライブラリも出てこない。節の記載と本文に矛盾は無い。

実現できるか: `ResumeQueryMapperTest` の target を6に上げても、V2〜V5 はこのテストが行を入れる表(users・resumes・careers・projects・project_tech_stacks・certifications・sns_platforms・portfolios・self_promotions)に触れない(V3 の `INSERT ... FROM users` はマイグレーション時に動き、そのとき users は空)。`ResumeMapperTest` と `ResumeQueryMapperTest` は注釈の組み合わせが同じなので、どちらも target=6 にすると1つの Spring の文脈(1つのコンテナ)を共有し、`check` で立つコンテナの数は今(target=1 と target=5)から増えない。`ResumeExportModelBuilderTest` は既存のテストと同じモックの形で書け、`MockitoExtension` の厳密な stub の検査にも、足した stub を検証で使う限り触れない。前回確かめた Flyway の API・`future` の扱い・PostgreSQL の型の変更の動きは変わっていない。

### 申告

**1. 3つの列を `TEXT` にした(`VARCHAR(1000)` にしなかった)** — design.md 概要、部品 V6、設計を見直すきっかけ

- Issue の記載: なし(「1000文字まで保存できる」とだけある。列の型は書かれていない)
- 決めたこと: `projects.overview` `projects.role` `portfolios.overview` を `TEXT` に変え、上限の文字数は入力の検査だけが持つ
- 他にありえた選択肢: `VARCHAR(1000)` にし、保存先の側にも長さの歯止めを残す
- 外れていた場合: `TEXT` にしたあとで保存先に歯止めを戻すには、もう1つマイグレーションが要る。入力の検査を通らずに書き込む経路は今は無いので、今の動きには影響しない

**2. 戻すマイグレーションを作らず、不具合のときはアプリだけを前の版に戻す** — design.md 作らないもの、移行の「元に戻す条件」

- Issue の記載: なし
- 決めたこと: V6 を1段で終え、保存先の型は戻さない。不具合のときは所有者がアプリだけを前の版に戻し、Flyway が V6 を `future` として無視することで前の版を起動させる
- 他にありえた選択肢: `VARCHAR(255)` に戻すマイグレーションを用意する(256文字以上の行があると失敗するので、戻せる条件が限られる)
- 外れていた場合: 本番で V6 を適用したあとに保存先を元の形に戻したくなったときに、256文字以上の行を手で短くしてからでないと戻せない。アプリだけを戻す運用で足りる限り、影響は無い

**3. PDF と Markdown は、出力のファイルの中身ではなく、出力の元になるデータ(`ResumeExportModelBuilder.build` の戻り値)で確かめる** — design.md 作るもの、部品 ResumeExportModelBuilderTest、テストの方針

- Issue の記載: なし(保存できることだけが書かれている)
- 決めたこと: 3つの欄に1000文字を持つ `Resume` から組み立てたデータに同じ文章が入ることを `ResumeExportModelBuilderTest` で確かめ、テンプレートが値をそのまま書き出すことを理由に、PDF と Markdown のファイルを読むテストは足さない。所有者はこの形を了承している(tasks-review の T1-1-3 への対応)
- 他にありえた選択肢: `ThymeleafResumePdfExporterTest` `ThymeleafResumeMarkdownExporterTest` に1000文字の文章を持つ職務経歴書で出力のファイルに文章が欠けないことを確かめるテストを足す
- 外れていた場合: テンプレートや出力の部品が文章を切り詰めるように変わったとき、CI では気づけない。今のテンプレート(`simple.html` L365・L377・L436、`default.md` L30・L38・L203)は切り詰めずに書き出すので、この spec の範囲では影響しない

### 指摘

| ID | レベル | 該当箇所 | 内容 | 直し方の案 |
|---|---|---|---|---|
| D2-1-1 | 低 | design.md テストの方針(1つ目の「単体テスト: 足さない。…」と5つ目の「単体テスト(出力の元になるデータ): `ResumeExportModelBuilderTest` にテストを足す」) | 同じ節の中で、単体テストを「足さない」と「足す」の両方を書いている。1つ目は入力の検査の単体テストの話で、5つ目は出力の元になるデータの単体テストの話なので、読めば区別できるが、1つ目の「足さない」が節全体の方針に読める。「作るもの」「ファイルの構成」「部品」は足すことで揃っており、実装には影響しない | 1つ目を「単体テスト(入力の検査): 足さない。…」のように対象を括弧で添える |

### 前の段階への指摘

なし。

- 往復: 1回目 / 高0 中0 低1
- 往復: 1回で収束 / 未解決: 0件
