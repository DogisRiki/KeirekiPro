## サイクル1 往復1 への対応(2026-11-24)

- レビュー役のモデル: Opus 5.5(所有者が選んだ)
- レビュー役が使った量: 94724 トークン
- 審査の範囲: 全体

| ID | 処置 | 内容 |
|---|---|---|
| T1-1-1 | 修正 | export_integration_test.go 18-74行の `loadExportFixtures` が `users/basic.sql` と `resumes/fonts.sql` を `sync.Once` で1度だけ入れることを実ファイルで確かめた。小タスク4.2 に、先に `loadExportFixtures` を呼んでから `backup/backup.sql` と `resumes/resume-limits.sql` を `sync.Once` で1度だけ入れる `loadBackupFixtures` を作ると書き、小タスク4.4 はそれを呼ぶと書き直した。小タスク4.5 の `TestRestoreIntegration_MatchesJava` に、201 のたびに経歴書を消してから次の本文を戻すことを、`TestRestoreIntegration_SurrogateName` に、user2 で2回続けて戻して2回目の答えを比べることを書き足した |
| T1-1-2 | 修正 | match_test.go の `TestLoadChangedBehaviors_RequiredFields` が仮のファイルだけを読むことを実ファイルで確かめた。小タスク1.6 の受入基準とテストの対応を、`match_test.go` に足す `TestChangedBehaviors_BackupItems` で CB-062 の match と理由の文、CB-063 から CB-066 が match を持たないことを確かめる、と書き直した |
| T1-1-3 | 修正 | CSRF のヘッダを付ける処理が send.go 151-174行の `prepareVersionRequest` にあることを実ファイルで確かめた。小タスク1.3 の文を `send.go` の `prepareVersionRequest` に合わせると書き直し、Host と Cookie と `X-XSRF-TOKEN` のヘッダの付け方を書き足した |
| T1-1-4 | 記録のみ | 前の段階(design)への、作るものが変わらない低の穴。小タスク1.1 の完了の確かめ方の `TestFixtures_AllLoadable` が職歴の重なりを見つけるので、実装に影響しない |

## サイクル1 往復2 への対応(2026-11-24)

- レビュー役のモデル: Opus 5.5(所有者が選んだ)
- レビュー役が使った量: 110365 トークン
- 審査の範囲: 差分

| ID | 処置 | 内容 |
|---|---|---|
| T1-2-1 | 記録のみ | 低の指摘。小タスク4.4 と 4.5 は `(並行可)` でなく、番号の順に 4.2 のあとに進むので、実装に影響しない |
