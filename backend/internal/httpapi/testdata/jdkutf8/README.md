# UTF-8 として誤ったバイトを含む名前の、Java 版の答え

`cases.json` は、Claude が 2026-11-13 に Java 版へ要求を送って控えた答えである。Java 版の動かし方は、`../multipart/README.md` に書いた。

Claude は、`PUT /api/users/me` の `username` の部分の中身に、`inputHex` のバイト列をそのまま入れて送った。
バイト列は、`a`(0x61)と `b`(0x62)の間に、UTF-8 として誤ったバイトか、2バイト、3バイト、4バイトの字の境目の字を置いた形である。

- `answer`: Java 版が答えた状態の番号と本文
- `storedUsername`: 答えの本文の `username`。Java 版が保存した名前である。U+FFFD は、JSON の `\ufffd` の書き方で書いた
- `storedHex`: 保存した名前を UTF-8 にしたバイト列を16進で書いたもの
- `storedCodePoints`: 保存した名前の字を、1字ずつ `U+XXXX` の形で書いたもの
