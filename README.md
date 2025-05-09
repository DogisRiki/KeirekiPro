# OIDCログイン設定手順（Google / GitHub）

本アプリケーションでは、Google および GitHub を使ったOIDCログイン機能が存在します。
利用には、各プロバイダーで発行したクライアントID・クライアントシークレットが必要です。

---

## 1. クライアントID / クライアントシークレットの取得

Google および GitHub で OAuth アプリケーションを登録し、それぞれの `client_id` と `client_secret` を取得してください。

- リダイレクトURIの設定には以下を使用してください：
  - 開発用: `http://localhost:8080/api/auth/oidc/callback`

---

## 2. `.env.local` ファイルの作成

docker/localstack/内に `.env.local` ファイルを作成し、以下のように記述してください。

```dotenv
GOOGLE_CLIENT_ID=your-google-client-id
GOOGLE_CLIENT_SECRET=your-google-client-secret
GITHUB_CLIENT_ID=your-github-client-id
GITHUB_CLIENT_SECRET=your-github-client-secret
```

---

## 3. Secrets Managerの操作方法

- シークレットの確認

```bash
awslocal --region ap-northeast-1 secretsmanager list-secrets
```

- シークレットの個別確認
```bash
awslocal --region ap-northeast-1 secretsmanager get-secret-value --secret-id keirekipro/oidc/google
```
```bash
awslocal --region ap-northeast-1 secretsmanager get-secret-value --secret-id keirekipro/oidc/github
```

---

## 4. S3の操作方法

- バケット一覧を確認
```bash
awslocal --region ap-northeast-1 s3 ls
```

- オブジェクトの一覧の確認（例: my-bucket配下）
```bash
awslocal --region ap-northeast-1 s3 ls s3://my-bucket/
```

- ファイルをアップロード
```bash
awslocal --region ap-northeast-1 s3 cp ./example.txt s3://my-bucket/
```

---

## 5. SESの操作方法

- 送信元メールアドレスの確認
```bash
awslocal --region ap-northeast-1 ses list-identities
```

- テストメールの送信
```bash
awslocal --region ap-northeast-1 ses send-email \
  --from no-reply@keirekipro.click \
  --destination "ToAddresses=no-reply@keirekipro.click" \
  --message "Subject={Data=Test Email},Body={Text={Data=This is a test email.}}"
```

- メール内容の確認
    1. 最新の送信メールファイル名を確認する
        ```bash
        ls -lt /tmp/localstack/state/ses/
        ```

    2. ファイルの中身を確認する（ファイル名は例）
        ```bash
        cat /tmp/localstack/state/ses/v123abc456.json
        ```
