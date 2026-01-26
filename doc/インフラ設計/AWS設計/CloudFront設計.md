# CloudFront設計書

## 1. ディストリビューション設計

### 1.1 基本設定

| 項目 | 設定値 |
|------|--------|
| ディストリビューションID | 自動生成 |
| 説明 | KeirekiPro CDN Distribution |
| 価格クラス | PriceClass_200（北米、欧州、アジア） |
| 状態 | 有効 |
| IPv6 | 有効 |
| HTTP/2 | 有効 |
| HTTP/3 | 有効 |
| ルートオブジェクト | index.html |

### 1.2 代替ドメイン名（CNAME）

| 項目 | 設定値 |
|------|--------|
| 代替ドメイン名 | app.keirekipro.click |
| SSL証明書 | ACM証明書（us-east-1） |
| 最小SSLプロトコルバージョン | TLSv1.2_2021 |
| サポートされているHTTPバージョン | HTTP/2, HTTP/3 |
| セキュリティポリシー | TLSv1.2_2021 |

### 1.3 ログ設定

| 項目 | 設定値 |
|------|--------|
| 標準ログ | 無効 |
| リアルタイムログ | 無効 |

## 2. オリジン設計

### 2.1 オリジン一覧

| オリジンID | オリジンタイプ | オリジンドメイン | 用途 |
|-----------|---------------|-----------------|------|
| S3-frontend | S3 | keirekipro-frontend.s3.ap-northeast-1.amazonaws.com | 静的ファイル配信 |
| ALB-api | ALB | api.keirekipro.click | APIリクエスト転送 |
| S3-storage | S3 | keirekipro-storage.s3.ap-northeast-1.amazonaws.com | 画像配信 |

### 2.2 S3-frontend オリジン設定

| 項目 | 設定値 |
|------|--------|
| オリジンID | S3-frontend |
| オリジンドメイン | keirekipro-frontend.s3.ap-northeast-1.amazonaws.com |
| オリジンパス | （空） |
| オリジンアクセス | Origin Access Control（OAC） |
| OAC名 | keirekipro-frontend-oac |
| 署名動作 | 常に署名する |
| 署名プロトコル | SigV4 |
| オリジンシールド | 無効 |
| 接続タイムアウト | 10秒 |
| 接続試行回数 | 3回 |

### 2.3 ALB-api オリジン設定

| 項目 | 設定値 |
|------|--------|
| オリジンID | ALB-api |
| オリジンドメイン | api.keirekipro.click |
| オリジンパス | （空） |
| オリジンプロトコルポリシー | HTTPS only |
| HTTPSポート | 443 |
| 最小オリジンSSLプロトコル | TLSv1.2 |
| オリジンシールド | 無効 |
| 接続タイムアウト | 10秒 |
| 接続試行回数 | 3回 |
| レスポンスタイムアウト | 30秒 |
| キープアライブタイムアウト | 5秒 |

### 2.4 S3-storage オリジン設定

| 項目 | 設定値 |
|------|--------|
| オリジンID | S3-storage |
| オリジンドメイン | keirekipro-storage.s3.ap-northeast-1.amazonaws.com |
| オリジンパス | （空） |
| オリジンアクセス | Origin Access Control（OAC） |
| OAC名 | keirekipro-storage-oac |
| 署名動作 | 常に署名する |
| 署名プロトコル | SigV4 |
| オリジンシールド | 無効 |
| 接続タイムアウト | 10秒 |
| 接続試行回数 | 3回 |

## 3. カスタムヘッダー設計

### 3.1 ALB-api オリジンへのカスタムヘッダー

| ヘッダー名 | 値 | 用途 |
|-----------|-----|------|
| X-Origin-Verify | {Secrets Managerから取得した値} | ALB直接アクセス防止 |

## 4. ビヘイビア設計

### 4.1 ビヘイビア一覧

| 優先度 | パスパターン | オリジン | 用途 |
|--------|-------------|---------|------|
| 0 | /api/* | ALB-api | APIリクエスト |
| 1 | /media/* | S3-storage | 画像配信 |
| 2 | デフォルト (*) | S3-frontend | 静的ファイル配信 |

### 4.2 /api/* ビヘイビア設定

| 項目 | 設定値 |
|------|--------|
| パスパターン | /api/* |
| オリジン | ALB-api |
| ビューワープロトコルポリシー | HTTPS only |
| 許可されたHTTPメソッド | GET, HEAD, OPTIONS, PUT, POST, PATCH, DELETE |
| キャッシュポリシー | CachingDisabled |
| オリジンリクエストポリシー | AllViewerExceptHostHeader |
| レスポンスヘッダーポリシー | なし |
| 圧縮 | 無効 |
| フィールドレベル暗号化 | なし |
| リアルタイムログ | なし |

### 4.3 /media/* ビヘイビア設定

| 項目 | 設定値 |
|------|--------|
| パスパターン | /media/* |
| オリジン | S3-storage |
| ビューワープロトコルポリシー | HTTPS only |
| 許可されたHTTPメソッド | GET, HEAD |
| キャッシュポリシー | CachingOptimized |
| オリジンリクエストポリシー | なし |
| レスポンスヘッダーポリシー | なし |
| 圧縮 | 有効 |
| フィールドレベル暗号化 | なし |
| リアルタイムログ | なし |

### 4.4 デフォルト (*) ビヘイビア設定

| 項目 | 設定値 |
|------|--------|
| パスパターン | * |
| オリジン | S3-frontend |
| ビューワープロトコルポリシー | Redirect HTTP to HTTPS |
| 許可されたHTTPメソッド | GET, HEAD |
| キャッシュポリシー | CachingOptimized |
| オリジンリクエストポリシー | なし |
| レスポンスヘッダーポリシー | SecurityHeadersPolicy |
| 圧縮 | 有効 |
| フィールドレベル暗号化 | なし |
| リアルタイムログ | なし |

## 5. キャッシュポリシー設計

### 5.1 使用するキャッシュポリシー

| ビヘイビア | キャッシュポリシー | ポリシーID |
|-----------|-------------------|-----------|
| /api/* | CachingDisabled | 4135ea2d-6df8-44a3-9df3-4b5a84be39ad |
| /media/* | CachingOptimized | 658327ea-f89d-4fab-a63d-7e88639e58f6 |
| デフォルト | CachingOptimized | 658327ea-f89d-4fab-a63d-7e88639e58f6 |

### 5.2 CachingDisabled（API用）

| 項目 | 設定値 |
|------|--------|
| ポリシー名 | CachingDisabled |
| 説明 | キャッシュ無効（APIリクエスト用） |
| デフォルトTTL | 0秒 |
| 最小TTL | 0秒 |
| 最大TTL | 0秒 |

### 5.3 CachingOptimized（静的ファイル・画像用）

| 項目 | 設定値 |
|------|--------|
| ポリシー名 | CachingOptimized |
| 説明 | 静的コンテンツ用最適化キャッシュ |
| デフォルトTTL | 86400秒（24時間） |
| 最小TTL | 1秒 |
| 最大TTL | 31536000秒（1年） |
| キャッシュキーに含める | なし（シンプルなキャッシュキー） |

## 6. オリジンリクエストポリシー設計

### 6.1 使用するオリジンリクエストポリシー

| ビヘイビア | オリジンリクエストポリシー | ポリシーID |
|-----------|-------------------------|-----------|
| /api/* | AllViewerExceptHostHeader | b689b0a8-53d0-40ab-baf2-68738e2966ac |
| /media/* | なし | - |
| デフォルト | なし | - |

### 6.2 AllViewerExceptHostHeader（API用）

| 項目 | 設定値 |
|------|--------|
| ポリシー名 | AllViewerExceptHostHeader |
| 説明 | Hostヘッダーを除くすべてのビューワーヘッダーを転送 |
| ヘッダー | All viewer headers except Host |
| Cookie | All |
| クエリ文字列 | All |

## 7. レスポンスヘッダーポリシー設計

### 7.1 使用するレスポンスヘッダーポリシー

| ビヘイビア | レスポンスヘッダーポリシー |
|-----------|-------------------------|
| デフォルト | SecurityHeadersPolicy |
| /api/* | なし |
| /media/* | なし |

### 7.2 SecurityHeadersPolicy

| 項目 | 設定値 |
|------|--------|
| ポリシー名 | SecurityHeadersPolicy |
| Strict-Transport-Security | max-age=31536000; includeSubDomains |
| X-Content-Type-Options | nosniff |
| X-Frame-Options | DENY |
| X-XSS-Protection | 1; mode=block |
| Referrer-Policy | strict-origin-when-cross-origin |

## 8. Origin Access Control（OAC）設計

### 8.1 keirekipro-frontend-oac

| 項目 | 設定値 |
|------|--------|
| OAC名 | keirekipro-frontend-oac |
| 説明 | OAC for frontend S3 bucket |
| 署名動作 | 常に署名する |
| オリジンタイプ | S3 |

### 8.2 keirekipro-storage-oac

| 項目 | 設定値 |
|------|--------|
| OAC名 | keirekipro-storage-oac |
| 説明 | OAC for storage S3 bucket |
| 署名動作 | 常に署名する |
| オリジンタイプ | S3 |

## 9. エラーページ設計

### 9.1 カスタムエラーレスポンス

| HTTPエラーコード | レスポンスページパス | レスポンスコード | キャッシュTTL |
|-----------------|-------------------|-----------------|-------------|
| 403 | /index.html | 200 | 10秒 |
| 404 | /index.html | 200 | 10秒 |

## 10. 地理的制限設計

| 項目 | 設定値 |
|------|--------|
| 制限タイプ | WAFで制御（CloudFront側では設定しない） |

## 11. WAF連携設計

| 項目 | 設定値 |
|------|--------|
| Web ACL | keirekipro-waf-acl |
| WAFリージョン | グローバル（CloudFront用） |

## 12. ACM証明書設計（CloudFront用）

### 12.1 証明書設定

| 項目 | 設定値 |
|------|--------|
| ドメイン名 | app.keirekipro.click |
| 追加の名前 | なし |
| 検証方法 | DNS検証 |
| リージョン | us-east-1（CloudFront用は必須） |
| キーアルゴリズム | RSA 2048 |

### 12.2 DNS検証レコード

| レコードタイプ | 名前 | 値 |
|--------------|------|-----|
| CNAME | _xxxxxxxx.app.keirekipro.click | _yyyyyyyy.acm-validations.aws |

## 13. Route 53連携設計

### 13.1 Aレコード（エイリアス）

| 項目 | 設定値 |
|------|--------|
| レコード名 | app.keirekipro.click |
| レコードタイプ | A |
| エイリアス | はい |
| ルーティングターゲット | CloudFrontディストリビューション |
| ルーティングポリシー | シンプル |

### 13.2 AAAAレコード（エイリアス）

| 項目 | 設定値 |
|------|--------|
| レコード名 | app.keirekipro.click |
| レコードタイプ | AAAA |
| エイリアス | はい |
| ルーティングターゲット | CloudFrontディストリビューション |
| ルーティングポリシー | シンプル |

## 14. キャッシュ無効化（Invalidation）設計

### 14.1 CI/CDでの無効化パス

| 用途 | 無効化パス |
|------|-----------|
| フロントエンドデプロイ時 | /* |

### 14.2 無効化の実行方法

GitHub Actionsワークフローでフロントエンドデプロイ後に実行する。

```bash
aws cloudfront create-invalidation \
  --distribution-id ${DISTRIBUTION_ID} \
  --paths "/*"
```
