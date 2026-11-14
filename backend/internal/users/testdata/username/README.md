# 名前の変更の、Java 版の答え

`cases.json` は、Claude が 2026-11-13 に Java 版へ要求を送って控えた答えである。Java 版の動かし方は、`../../../httpapi/testdata/multipart/README.md` に書いた。

Claude は、27通りの名前を、`PUT /api/users/me` の `username` の部分で順に送った。同じ利用者に送ったので、断られた要求のあとも、利用者の名前は前の要求で保存した名前のままである。

- `input`: 送った名前。`inputHex` は、送ったバイト列を16進で書いたもの。`inputUtf16Len` は、送った名前を UTF-16 で数えた長さ
- `answer`: Java 版が答えた状態の番号と本文
- `storedUsername`: 答えの本文の `username`。Java 版が保存した名前である。答えが 200 でないときは `null` である
- `storedCodePoints`: 保存した名前の字を、1字ずつ `U+XXXX` の形で書いたもの
