# tasks の指摘への対応(backend-go-resume-export)

## サイクル1 往復1 への対応(2026-11-23)

- レビュー役のモデル: Opus 5.5(所有者が選んだ)
- レビュー役が使った量: 104636 トークン
- 審査の範囲: 全体

| ID | 処置 | 内容 |
|---|---|---|
| T1-1-1 | 修正 | 小タスク2.2 に、`TestCompare_RejectsOneCharDiff` の1つ目の場合の期待を「文書の字の並び」の説明に替えることと、`TestCompare_RejectsPageBreakDiff` を2.2 の完了の確かめで流さず2.3 で期待を替えることを書き、完了の確かめ方の `-run` を2.2 の時点で通るテストに絞った。小タスク2.3 に、`TestCompare_Rejects2_5ptShift` と `TestCompare_RejectsPageBreakDiff` の1つ目の場合の期待を行の組の比べ方の違いの種類に替えることを書いた。どちらもアサーションを消さないと書いた |
| T1-1-2 | 修正 | 小タスク2.1 に、`TestScenarioValidate_UserFields` の場合「版に送る段の expect の content_type」を、断られずに読める場合として `TestExpectContentType_VersionStep` に移すことを書き、完了の確かめ方の `-run` に `TestScenarioValidate` を足した |
| T1-1-3 | 修正 | 事実の誤り。`versions.go` の `JavaEnv` と `application-dev.yaml` と `init-localstack.sh` を読んで確かめた。小タスク1.2 に、`SPRING_DATASOURCE_URL` と `SPRING_DATA_REDIS_DATABASE` を足して `keireki_proto` と Redis の DB 7 を選ばせること(Spring Boot は環境変数を取り込んだ設定より先に読む。https://docs.spring.io/spring-boot/reference/features/external-config.html)、localstack の秘密の値を書き換えないこと、要求を送る前に `/actuator/env` でつなぎ先を確かめることを書き、完了の確かめ方にも足した |
| T1-1-4 | 修正 | 小タスク1.1 に、`TestFixtures_AllLoadable` に `export` のフォルダの場合を足すこと(`export/*.sql` は `users` と `resumes` の SQL のあとに読み込んで同じ決まりで確かめ、`export/*.json` は JSON として読めることを確かめる)と、`fixtures.go` の `FixturesDir` のコメントを5つのフォルダにすることを書き、完了の確かめ方に `TestFixtures_AllLoadable` を足した |
| T1-1-5 | 記録のみ | 低。タスクは番号の順に進むので、実装に影響しない |
| T1-1-6 | 記録のみ | 低。どちらも5.2 と1.4 の完了の確かめ方のテストで見つかる |
| T1-1-7 | 修正 | design.md のテストの方針の `pdfcmp.go` の文を、design の承認を残して直した(kept-approval-fixes.md の 1) |

## サイクル1 往復2 への対応(2026-11-23)

- レビュー役のモデル: Opus 5.5(所有者が選んだ)
- レビュー役が使った量: 127399 トークン
- 審査の範囲: 前回からの差分

| ID | 処置 | 内容 |
|---|---|---|
| T1-2-1 | 記録のみ | 低。前の段階の design への作るものが変わらない穴で、低の穴は直さない。tasks の小タスク1.1 の本文に、`fixtures_test.go` と `fixtures.go` で変える中身が書いてあるので、実装には影響しない |
