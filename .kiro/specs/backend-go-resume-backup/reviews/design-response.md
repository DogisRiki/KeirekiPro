## サイクル1 往復1 への対応(2026-11-24)

- レビュー役のモデル: Opus 5.5(所有者が選んだ)
- レビュー役が使った量: 94551 トークン
- 審査の範囲: 全体

| ID | 処置 | 内容 |
|---|---|---|
| D1-1-1 | 修正 | design.md ファイルの構成の sqlc の生成したコードの置き場を `backend/internal/platform/database/sqlcgen/` に直した(backend/internal/resume/store.go 15行で確かめた)。research.md の「今あるものについて確かめた文」に1行足した |
| D1-1-2 | 修正 | design.md Java 版の答えの正解のファイルの節で、データベースの名前を `kp_backup_proto` にそろえた。あわせて、Java 版のイメージを `docker/backend/Dockerfile.prod` で作ること、compose のネットワーク `my-network` につなぐこと、`SPRING_DATASOURCE_URL` と `SPRING_DATA_REDIS_DATABASE` の値でつなぎ先を選ぶことを書いた。research.md の「今あるものについて確かめた文」に3行足した |
| D1-1-3 | 修正 | design.md Service の戻しの「名前の重なり」の箇条を直した。名前が無いときと、名前に対になっていないサロゲートを含むときは重なりを確かめず、それ以外の名前はそのまま `resumeNameExists` に渡す。指摘の筋書き(Java 版が重なりの誤りで答える)は、対になっていないサロゲートを含む名前を Java 版が値の決まりで 400 にするので起きないが、名前の `?` 版の経歴書を持つ利用者に Go 版が名前の重なりの誤りを返し、Java 版と見える答えが食い違う穴はあった。restore.json の答えと restore_integration_test にこの場合を足した |
| D1-1-4 | 記録のみ | 低の指摘。仕様書の restore の答えに 404 を足すかは、実装に影響しない |
| D1-1-5 | 記録のみ | 低の指摘。書き方の指摘で、実装に影響しない |

## サイクル1 往復2 への対応(2026-11-24)

- レビュー役のモデル: Opus 5.5(所有者が選んだ)
- レビュー役が使った量: 140768 トークン
- 審査の範囲: 前回からの差分

| ID | 処置 | 内容 |
|---|---|---|
| D1-2-1 | 修正 | design.md Service の戻しの「名前の重なり」の最後の文を、Java 版の名前の値の決まり(`ResumeName`)が対になっていないサロゲートを断らないので Go 版も断らない、に直した(ResumeName.java 18行、43-67行で確かめた)。restore_integration_test の場合の期待を、`restore.json` に控えた Java 版の答えと同じ答えになること、に直した。research.md の試作の記録に、400 になったのは書き出したファイルの名前の `?` のためであることと、対になっていないサロゲートを含む名前の戻しは試作で確かめていないことを書き足した。D1-1-3 の対応で挙げた根拠は読み違いだった |
| D1-2-2 | 修正 | design.md Java 版の答えの正解のファイルの節に、`SPRING_PROFILES_ACTIVE` を `dev` にして動かすこと、localstack が動いていることを確かめてから起動すること、起動の前に `kp_backup_proto` を作ること、compose が付けるネットワークの名前 `keirekipro_my-network` を書き足した。試作で Java 版を起動したコマンドと versions.go 76行と application-dev.yaml 3行、15行で確かめ、research.md に控えた |

## サイクル1 往復3 への対応(2026-11-24)

- レビュー役のモデル: Opus 5.5(所有者が選んだ)
- レビュー役が使った量: 118413 トークン
- 審査の範囲: 前回からの差分

| ID | 処置 | 内容 |
|---|---|---|
| D1-3-1 | 未解決 | 最終往復のため本文を直していない。Java 版の答えを控える手順に、`users/basic.sql` を `backup.sql` と `fonts.sql` より先に `kp_backup_proto` に入れることと、`restore.json` と `backup-unsent.json` を控えるときに要求を送る利用者(経歴書を持たない利用者と、名前のサロゲートを `?` にした経歴書を持つ利用者)とその経歴書の作り方が書かれていない |

## サイクル2 往復1 への対応(2026-11-24)

- レビュー役のモデル: Opus 5.5(所有者が選んだ)
- レビュー役が使った量: 97826 トークン
- 審査の範囲: 前回からの差分

この往復の指摘は無い。サイクル1 往復3 で未解決とした D1-3-1 は、この回の前に本文を直し、この往復の審査で直しが確かめられた。

| ID | 処置 | 内容 |
|---|---|---|
| D1-3-1 | 修正 | design.md Java 版の答えの正解のファイルの節で、`users/basic.sql`、`resumes/fonts.sql`、`backup/backup.sql` の順に `kp_backup_proto` に入れることを書いた。`restore.json` を控える利用者を経歴書を持たない user2 にし、201 のときは経歴書を消して戻すこと、名前の重なりの場合は同じファイルを user2 で2回戻して2回目の答えを控えることを書いた。`backup-unsent.json` の書き出しを user1 で経歴書 401 に、戻しを user2 で送ることを書いた。basic.sql 4-7行、V2__insert_mst_data.sql 4行、DeleteResumeController.java 25行、36行で確かめ、research.md に控えた |
