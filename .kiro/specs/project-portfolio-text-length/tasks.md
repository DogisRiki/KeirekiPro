# タスク

- [x] 1. 3つの列の型を変えるマイグレーションを足す

  Claude は、先にテスト `ProjectPortfolioTextColumnMigrationTest` を書いて失敗することを確かめ、そのあとでマイグレーション V6 を足す。V6 は、プロジェクトの「概要」「役割」とポートフォリオの「概要」の3つの列の型を `TEXT` に変える。テストは、V5 まで進めた保存先に255文字の文章を入れ、V6 まで進めたあとで同じ文章が読み出せることと、3つの列の型が `text` になったことを確かめる。
  - 完了の確かめ方: `ProjectPortfolioTextColumnMigrationTest` が通る。V6 の SQL から1つの列(たとえば `portfolios.overview`)の変更を一時的に外すと、3つの列が `text` であることの検査が失敗し、戻すと通る
  - 受入基準とテストの対応: 要件3の受入基準1(すでに保存してある文章を変えない)は、`ProjectPortfolioTextColumnMigrationTest` の「V5 の時点で入れた文章が V6 のあとも変わらず、3つの列が text になる」のテストで確かめる
  - _要件: 3.1_

- [ ] 2. 1000文字の文章が保存先と読み出しの経路を通ることを確かめ、設計図を揃える
- [ ] 2.1 1000文字の文章を保存して読み出すテストを足す (並行可)

  Claude は、`ResumeMapperTest` の `spring.flyway.target` を5から6に上げ、3つの欄に1000文字の多バイトの文章を入れて読み出すテストを2つ足す。Claude は、既存のテストを、target を上げる以外に変えない。
  - 完了の確かめ方: `ResumeMapperTest` の既存のテストと足したテストがすべて通る。target を5に戻すと、足した2つのテストが失敗する
  - 受入基準とテストの対応: 要件1の受入基準1・2(プロジェクトの「概要」「役割」に1000文字を保存できる)は、`ResumeMapperTest` の「insertProject で overview と role に1000文字を入れると selectProjectsByResumeId で同じ文章が返る」のテストで確かめる。要件1の受入基準3(ポートフォリオの「概要」に1000文字を保存できる)は、「insertPortfolio で overview に1000文字を入れると selectPortfoliosByResumeId で同じ文章が返る」のテストで確かめる。要件1の受入基準4(5つの保存のしかたのどれでも保存できる)は、5つの保存のしかたがどれも `insertProject` と `insertPortfolio` で書き込むので、この2つのテストで確かめる
  - _要件: 1.1, 1.2, 1.3, 1.4_
  - _対象の部品: ResumeMapperTest_
  - _依存: 1_

- [ ] 2.2 バックアップの JSON に1000文字の文章が入るテストを足す (並行可)

  Claude は、`ResumeQueryMapperTest` の `spring.flyway.target` を1から6に上げ、3つの欄に1000文字の多バイトの文章を入れた職務経歴書について、`selectResumeForBackup` の JSON の `projects[0].overview` `projects[0].role` `portfolios[0].overview` が同じ文章になるテストを足す。Claude は、既存のテストと既存のデータを入れる関数(`insertProject` と `insertPortfolio`)を、target を上げる以外に変えない。Claude は、1000文字の文章を入れるために、文章を引数で受け取るデータを入れる関数を新しく足す。既存のテストが target を上げて失敗したときは、Claude はアサーションを直さず、原因を所有者に報告する。
  - 完了の確かめ方: `ResumeQueryMapperTest` の既存のテストと足したテストがすべて通る。target を1に戻すと、足したテストが失敗する
  - 受入基準とテストの対応: 要件1の受入基準5のうちバックアップ(バックアップに保存した文章を欠かさずに載せる)は、`ResumeQueryMapperTest` の「selectResumeForBackup で3つの欄に1000文字の文章があるとき、JSON に同じ文章が入る」のテストで確かめる
  - _要件: 1.5_
  - _対象の部品: ResumeQueryMapperTest_
  - _依存: 1_

- [ ] 2.3 出力の元になるデータに1000文字の文章が入るテストを足す (並行可)

  Claude は、`ResumeExportModelBuilderTest` に、3つの欄に1000文字の多バイトの文章を持つ `Resume` を `ResumeExportModelBuilder.build` に渡すと、返るデータのプロジェクトの `overview` `role` とポートフォリオの `overview` が渡した文章と1文字も違わないことを確かめるテストを足す。Claude は、足すテストを、既存のテストの作り方(モックの形)に合わせる。
  - 完了の確かめ方: `ResumeExportModelBuilderTest` の既存のテストと足したテストがすべて通る。`ResumeExportModelBuilder` で、プロジェクトの `overview`、プロジェクトの `role`、ポートフォリオの `overview` を1つずつ一時的に先頭の255文字に切ると、そのたびに足したテストが失敗し、戻すと通る
  - 受入基準とテストの対応: 要件1の受入基準5のうち PDF と Markdown(出力に保存した文章を欠かさずに載せる)は、`ResumeExportModelBuilderTest` の「3つの欄に1000文字の文章を持つ職務経歴書から、出力の元になるデータに同じ文章が入る」のテストで確かめる
  - _要件: 1.5_
  - _対象の部品: ResumeExportModelBuilderTest_

- [ ] 2.4 ER図の3つの列の型を書き直す (並行可)

  Claude は、`doc/DB設計/ER図.pu` のプロジェクトの表の `overview` と `role` と、ポートフォリオの表の `overview` の型を、`VARCHAR(255)` から `TEXT` に書き直す。Claude は、ほかの列と書式(色の指定、`[NOT NULL]` の印、コメント)を変えない。
  - 完了の確かめ方: ER図の3つの列が `TEXT` と書かれ、プロジェクトの表の `achievement` と、ポートフォリオの表の `tech_stack` の書き方と揃っている。`git diff` で、ER図の変更が3行だけである
  - 受入基準とテストの対応: このタスクは設計図を保存先に揃える作業で、受入基準を満たさない。そのため、`_要件:_` の行を書かない
  - _対象の部品: doc/DB設計/ER図.pu_

- [ ] 3. 画面を通して保存と表示とエラーを確かめる

  Claude は、backend の品質チェックを通したあと、`/verify-ui` で画面確認の開発サーバを起動する。起動に使うスクリプト `ui.sh start` は、作業フォルダのコードで backend を起動し、作業フォルダごとのデータベース `kp_<鍵>` につなぐ。Claude は、鍵を、`ui.sh` と同じく `.claude/scripts/parallel/lib.sh` の `kp_folder_key` で求める。Claude は、`docker compose -p keirekipro exec -T db psql -U postgres -d kp_<鍵> -c "SELECT version, success FROM flyway_schema_history"` で、そのデータベースに V6 が `success` として記録されたことを確かめてから、画面を操作する。Claude は、3つの欄に1000文字の文章を入れて保存し、画面を開き直して同じ文章が出ることを確かめる。続けて、Claude は、3つの欄のどれかに1001文字の文章を入れて保存し、今と同じエラーの文が出て保存されないことを確かめる。
  - 完了の確かめ方: `/verify-backend` が成功する。画面確認の backend がつなぐ作業フォルダごとのデータベース `kp_<鍵>` の `flyway_schema_history` に、V6 が `success` として記録されている。`/verify-ui` の結果に、1000文字の文章が保存されて開き直した画面に出たことと、1001文字でエラーの文が出たことが、スクリーンショットとともに残る
  - 受入基準とテストの対応: 要件1の受入基準5のうち画面の表示(開き直した画面に保存した文章をそのまま表示する)は、`/verify-ui` の操作で確かめる。要件2の受入基準1(1000文字を超えると今と同じエラーの文を出して保存しない)は、既存の `ProjectTest` の `test14`(「各項目が最大文字数を超える場合、エラーが収集される」)と `PortfolioTest` の `test9`(同じ名前のテスト)が `/verify-backend` で通ることと、`/verify-ui` の操作で確かめる
  - _要件: 1.5, 2.1_

## 完了条件(全タスク共通)

Claude は、どのタスクでも、タスクの箇条書きの欄を書いたうえで、次の4つを満たしたときにタスクを完了とする。

1. Claude は、タスクが満たす requirements.md の受入基準(要件の番号付きの項目)ごとに、それを確かめるテストのファイル名とテスト名を「受入基準とテストの対応」の行に書く。Claude は、確かめるテストの無い受入基準を残さない。
2. タスクで変えた領域の verify のスキル(`/verify-frontend` `/verify-backend` `/verify-terraform`)が、すべて成功している。
3. Claude は、テストを飛ばす設定、アサーションの削除、カバレッジや lint の対象からの除外を足して、完了条件を満たしたように見せない。CI の escape-hatch の検査が、これらの追加を機械で見つける。
4. Claude は、新しく書いたテストについて、テストの対象のコードを一時的に壊してテストが失敗することを確かめてから、コードを元に戻す。
