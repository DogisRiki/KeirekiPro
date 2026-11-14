# 名前と画像と2段階認証の設定の変更の要求の、Java 版の答え

このフォルダのファイルは、Claude が 2026-11-13 に Java 版へ要求を送って控えた答えである。
Java 版は、開発環境の `spring` のコンテナの中で、所有者の開発の Java 版と同じ起動の設定に、ポート 8090 と、別のデータベースと、Redis の DB 6 を足して動かした。
画像の置き場所は、開発環境の LocalStack の S3 の `keirekipro-storage` である。Claude は、要求ごとに、置かれた画像を読んで記録し、消した。

## filenames.json

部分の `Content-Disposition` の書き方を12通りに変えて、`PUT /api/users/me` に画像を送った答えである。
どの要求も、部分の `Content-Type` は `image/png` で、中身は `image.png` である。

- `contentDisposition`: 部分の `Content-Disposition` の見出しの値。`contentDispositionHex` は、同じ値のバイト列を16進で書いたものである。制御文字(BEL)を含む値があるので、バイト列も残す
- `answer`: Java 版が答えた状態の番号と本文
- `storedObjects`: Java 版が置いた画像の名前と、`Content-Type` と、利用者の付けた値(メタデータ)と、大きさ。画像を置かなかったときは空である

## java-checks/cases.json

design.md の「本文を読む中間処理と multipart の読み方」の節で、実装のときに Java 版の答えで確かめると決めた3つの要求の答えである。
Claude は、3つの要求を、この順に同じ利用者に送った。2つ目の要求は `username` の部分を送っていないので、2つ目の答えの名前は、1つ目の要求で保存した名前のままである。

- `query`: URL の問い合わせ
- `parts`: 送った部分の見出しと中身。`bodyFile` は、中身にしたファイルを、このファイルからの相対の道で指す
- `storedUsername`: 答えの本文の `username`。答えが 200 でないときは `null` である
