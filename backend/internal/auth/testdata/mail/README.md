# メールの正解のファイル

このフォルダの `email-verification` `password-reset` `two-factor-auth` `user-registered` のファイルの作り方は、`../../mail_test.go` の先頭の説明に書いた。
この README は、退会の完了のメールの `user-deleted` のファイルだけを説明する。

## 退会の完了のメール

Claude は、2026-11-13 に、確認の済んだメールアドレス `cap-mail@example.com` と名前 `退会太郎` を持つ利用者を、Java 版の `DELETE /api/users/me` で退会させた。
Java 版の動かし方は、`../../../httpapi/testdata/multipart/README.md` に書いた。

- `user-deleted.json`: 退会の要求の答えと、開発環境の LocalStack の SES が受けたメールの記録(`/_aws/ses` の答えのうち、宛先がこの利用者のもの)
- `user-deleted.txt`: そのメールの件名と本文。1行目が件名で、空の行を1つはさんで、3行目から最後までが本文である。本文の最後の改行も本文に含まれる
- `user-deleted.values.json`: Java 版がそのメールに差し込んだ、宛先と名前。ほかの4種類のメールの `<種類>.values.json` と同じ形である

Java 版が本文に差し込んだサイトの名前は `KeirekiPro`、サイトの URL は `https://app.keirekipro.click` で、`app.json` の値である。
