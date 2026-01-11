# Secrets Manager 設計書

## 1. 管理対象シークレット

| シークレット名 | 用途 |
|---------------|------|
| `keirekipro/rds` | RDSデータベース接続情報 |
| `keirekipro/redis` | ElastiCache Redis接続情報 |
| `keirekipro/jwt` | JWTトークン署名鍵 |
| `keirekipro/oidc/google` | Google OAuth認証情報 |
| `keirekipro/oidc/github` | GitHub OAuth認証情報 |
| `keirekipro/alb-origin-verify` | ALB直接アクセス防止用ヘッダ値 |

## 2. 管理対象外

以下は秘匿性がないため、環境変数または設定ファイルで管理する。

- SES送信元アドレス
- S3バケット名
- サイト名・サイトURL
- フロントエンドURL
- CORS許可オリジン
- Cookie Secure設定

## 3. シークレット構造（JSONスキーマ）

### 3.1 keirekipro/rds
```json
{
  "host": "string",
  "port": "string",
  "database": "string",
  "username": "string",
  "password": "string"
}
```

### 3.2 keirekipro/redis
```json
{
  "redis-host": "string",
  "redis-port": "string",
  "redis-password": "string"
}
```

### 3.3 keirekipro/jwt
```json
{
  "jwt-secret": "string"
}
```

### 3.4 keirekipro/oidc/google
```json
{
  "client_id": "string",
  "client_secret": "string"
}
```

### 3.5 keirekipro/oidc/github
```json
{
  "client_id": "string",
  "client_secret": "string"
}
```

### 3.6 keirekipro/alb-origin-verify
```json
{
  "headerValue": "string"
}
```

## 4. 取得方式

シークレットをどのタイミングでどう取得するかの定義を示す。

| シークレット | 取得方式 | 取得タイミング |
|-------------|---------|---------------|
| keirekipro/rds | spring.config.importによる自動バインド | 起動時 |
| keirekipro/redis | spring.config.importによる自動バインド | 起動時 |
| keirekipro/jwt | spring.config.importによる自動バインド | 起動時 |
| keirekipro/oidc/google | アプリケーションから直接取得 | 認証フロー実行時 |
| keirekipro/oidc/github | アプリケーションから直接取得 | 認証フロー実行時 |
| keirekipro/alb-origin-verify | CloudFront/ALB設定で参照 | インフラ構築時 |

## 5. 環境別エンドポイント

Secrets ManagerのAPIの接続先を示す。

| 環境 | エンドポイント |
|-----|---------------|
| dev | LocalStack（http://localstack:4566） |
| prod | AWS標準エンドポイント（SDK自動解決） |

## 6. セキュリティ設定

### 6.1 暗号化

Secrets Managerに保存されるシークレットの暗号化方式を示す。

| 項目 | 設定値 |
|-----|-------|
| 暗号化キー | AWS管理キー（aws/secretsmanager） |
| カスタムKMSキー | 使用しない |

### 6.2 ローテーション

シークレットを定期的に自動で新しい値に更新する機能についての方式を示す。

| シークレット | ローテーション | 理由 |
|-------------|--------------|------|
| keirekipro/rds | 無効 | ポートフォリオ用途のため運用負荷を軽減 |
| keirekipro/redis | 無効 | 同上 |
| keirekipro/jwt | 無効 | 同上 |
| keirekipro/oidc/google | 無効 | 外部IdP管理のため自動ローテーション不可 |
| keirekipro/oidc/github | 無効 | 同上 |
| keirekipro/alb-origin-verify | 無効 | CloudFront/ALB設定との同期が必要なため手動管理 |

### 6.3 バージョニング

Secrets Managerはシークレットの変更履歴の定義を示す。

- ステージングラベル: `AWSCURRENT`のみ使用（デフォルト）
- 過去バージョンの保持: Secrets Managerのデフォルト動作に従う

### 6.4 削除保護

シークレットを誤って削除した場合の保護機能についての方式を示す。

| 項目 | 設定値 |
|-----|-------|
| リカバリウィンドウ | 7日間（デフォルト） |
| 即時削除 | 使用しない |

## 7. 監査・ログ

誰がいつシークレットにアクセスしたかの記録についての方式を示す。

| 項目 | 設定 |
|-----|------|
| CloudTrail | AWSアカウントのデフォルト設定に従う |
| 記録対象イベント | GetSecretValue, CreateSecret, UpdateSecret, DeleteSecret |

## 8. IAMポリシー（prod環境）

ECSタスク（アプリケーションが動くコンテナ）がSecrets Managerにアクセスするための権限設定について示す。

### 8.1 ECSタスクロール用
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "secretsmanager:GetSecretValue",
      "Resource": "arn:aws:secretsmanager:ap-northeast-1:*:secret:keirekipro/*"
    }
  ]
}
```

## 9. LocalStack初期化（dev環境）

dev環境では、コンテナ起動時に以下のシークレットをLocalStackに登録する。

| シークレット名 | 値の取得元 |
|---------------|-----------|
| keirekipro/rds | 固定値（ローカルDB接続情報） |
| keirekipro/redis | 固定値（ローカルRedis接続情報） |
| keirekipro/jwt | 固定値（開発用署名鍵） |
| keirekipro/oidc/google | 環境変数（.env.local） |
| keirekipro/oidc/github | 環境変数（.env.local） |
