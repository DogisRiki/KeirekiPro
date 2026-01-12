# WAF設計書

## 1. Web ACL設計

### 1.1 基本設定

| 項目 | 設定値 |
|------|--------|
| Web ACL名 | keirekipro-waf-acl |
| スコープ | CloudFront（グローバル） |
| リソースタイプ | CloudFrontディストリビューション |
| デフォルトアクション | Allow |
| CloudWatch メトリクス | 有効 |
| サンプルリクエスト | 有効 |

### 1.2 関連付けリソース

| リソースタイプ | リソース名 |
|--------------|-----------|
| CloudFrontディストリビューション | keirekipro-distribution |

## 2. ルール設計

### 2.1 ルール一覧（優先順位順）

| 優先度 | ルール名 | ルールタイプ | アクション | 説明 |
|--------|---------|-------------|-----------|------|
| 0 | GeoBlockNonJP | カスタム（GeoMatch） | Block | 日本以外からのアクセスをブロック |
| 1 | RateLimitAuth | カスタム（Rate-based） | Block | 認証系エンドポイントへのレート制限 |
| 2 | RateLimitAPI | カスタム（Rate-based） | Block | API全体へのレート制限 |
| 3 | AWS-AWSManagedRulesCommonRuleSet | AWS Managed Rules | Block | 一般的な脆弱性からの保護 |
| 4 | AWS-AWSManagedRulesKnownBadInputsRuleSet | AWS Managed Rules | Block | 既知の悪意あるパターンをブロック |
| 5 | AWS-AWSManagedRulesSQLiRuleSet | AWS Managed Rules | Block | SQLインジェクション攻撃からの保護 |

## 3. ルール詳細設計

### 3.1 GeoBlockNonJP（優先度: 0）

地理的制限ルール。日本国外からのアクセスを全てブロックする。

| 項目 | 設定値 |
|------|--------|
| ルール名 | GeoBlockNonJP |
| ルールタイプ | 通常ルール |
| ステートメントタイプ | Geo match |
| 一致条件 | NOT（否定） |
| 対象国 | JP（日本） |
| アクション | Block |
| CloudWatch メトリクス名 | GeoBlockNonJP |

ルール条件ロジック:
```
NOT (originates from country: JP)
→ Block
```

### 3.2 RateLimitAuth（優先度: 1）

認証系エンドポイントへの集中的なリクエストを制限する。

| 項目 | 設定値 |
|------|--------|
| ルール名 | RateLimitAuth |
| ルールタイプ | Rate-based rule |
| レート制限 | 100リクエスト / 5分 / IP |
| 評価ウィンドウ | 5分（300秒） |
| 集約キー | IP address |
| スコープダウンステートメント | あり |
| アクション | Block |
| CloudWatch メトリクス名 | RateLimitAuth |

スコープダウンステートメント:
```
URI path starts with: /api/auth/
```

### 3.3 RateLimitAPI（優先度: 2）

API全体への過剰なリクエストを制限する。

| 項目 | 設定値 |
|------|--------|
| ルール名 | RateLimitAPI |
| ルールタイプ | Rate-based rule |
| レート制限 | 600リクエスト / 5分 / IP |
| 評価ウィンドウ | 5分（300秒） |
| 集約キー | IP address |
| スコープダウンステートメント | あり |
| アクション | Block |
| CloudWatch メトリクス名 | RateLimitAPI |

スコープダウンステートメント:
```
URI path starts with: /api/
```

### 3.4 AWS-AWSManagedRulesCommonRuleSet（優先度: 3）

AWSが提供するマネージドルールセット。一般的なWeb攻撃パターンから保護する。

| 項目 | 設定値 |
|------|--------|
| ルール名 | AWS-AWSManagedRulesCommonRuleSet |
| ルールタイプ | AWS Managed Rules |
| ベンダー | AWS |
| ルールグループ名 | AWSManagedRulesCommonRuleSet |
| バージョン | デフォルト（最新） |
| アクション | ルールグループのデフォルトアクションを使用 |
| CloudWatch メトリクス名 | AWS-AWSManagedRulesCommonRuleSet |

除外ルール設定:

| 除外ルール名 | 除外理由 |
|-------------|---------|
| SizeRestrictions_BODY | 大きなファイルアップロードを許可するため |
| CrossSiteScripting_BODY | リッチテキスト入力を許可するため（必要に応じて） |

### 3.5 AWS-AWSManagedRulesKnownBadInputsRuleSet（優先度: 4）

既知の悪意あるリクエストパターンをブロックする。

| 項目 | 設定値 |
|------|--------|
| ルール名 | AWS-AWSManagedRulesKnownBadInputsRuleSet |
| ルールタイプ | AWS Managed Rules |
| ベンダー | AWS |
| ルールグループ名 | AWSManagedRulesKnownBadInputsRuleSet |
| バージョン | デフォルト（最新） |
| アクション | ルールグループのデフォルトアクションを使用 |
| CloudWatch メトリクス名 | AWS-AWSManagedRulesKnownBadInputsRuleSet |

除外ルール設定:

| 除外ルール名 | 除外理由 |
|-------------|---------|
| なし | すべてのルールを有効化 |

### 3.6 AWS-AWSManagedRulesSQLiRuleSet（優先度: 5）

SQLインジェクション攻撃からデータベースを保護する。

| 項目 | 設定値 |
|------|--------|
| ルール名 | AWS-AWSManagedRulesSQLiRuleSet |
| ルールタイプ | AWS Managed Rules |
| ベンダー | AWS |
| ルールグループ名 | AWSManagedRulesSQLiRuleSet |
| バージョン | デフォルト（最新） |
| アクション | ルールグループのデフォルトアクションを使用 |
| CloudWatch メトリクス名 | AWS-AWSManagedRulesSQLiRuleSet |

除外ルール設定:

| 除外ルール名 | 除外理由 |
|-------------|---------|
| なし | すべてのルールを有効化 |

## 4. カスタムレスポンス設計

### 4.1 ブロック時のカスタムレスポンス

| 項目 | 設定値 |
|------|--------|
| レスポンスコード | 403 |
| カスタムレスポンスボディ | なし（デフォルトレスポンス） |

## 5. ログ設定

### 5.1 ログ出力設定

| 項目 | 設定値 |
|------|--------|
| ログ出力 | 無効 |
| ログ出力先 | - |

### 5.2 ログ出力を有効化する場合の設定（将来的な拡張用）

| 項目 | 設定値 |
|------|--------|
| ログ出力先 | CloudWatch Logs |
| ロググループ名 | aws-waf-logs-keirekipro |
| 保持期間 | 14日 |
| フィルタリング | なし（全ログ出力） |

## 6. CloudWatchメトリクス設計

### 6.1 Web ACLメトリクス

| メトリクス名 | 説明 |
|-------------|------|
| AllowedRequests | 許可されたリクエスト数 |
| BlockedRequests | ブロックされたリクエスト数 |
| CountedRequests | カウントされたリクエスト数 |
| PassedRequests | 通過したリクエスト数 |

### 6.2 ルール別メトリクス

| ルール | メトリクス名 |
|--------|-------------|
| GeoBlockNonJP | GeoBlockNonJP |
| RateLimitAuth | RateLimitAuth |
| RateLimitAPI | RateLimitAPI |
| AWS Managed Rules（共通） | AWS-AWSManagedRulesCommonRuleSet |
| AWS Managed Rules（悪意入力） | AWS-AWSManagedRulesKnownBadInputsRuleSet |
| AWS Managed Rules（SQLi） | AWS-AWSManagedRulesSQLiRuleSet |

## 7. AWS Shield連携

### 7.1 Shield Standard

| 項目 | 設定値 |
|------|--------|
| Shield Standard | 自動有効（CloudFront標準機能） |
| 追加設定 | 不要 |
| 追加コスト | なし |

### 7.2 Shield Advanced

| 項目 | 設定値 |
|------|--------|
| Shield Advanced | 無効（ポートフォリオ用途のため） |

## 8. レート制限の計算根拠

### 8.1 認証系エンドポイント（RateLimitAuth: 100 req/5min/IP）

| 項目 | 計算 |
|------|------|
| 想定正常利用 | ログイン試行5回程度/セッション |
| 5分間の上限 | 100リクエスト |
| 1秒あたり換算 | 約0.33リクエスト/秒 |
| ブルートフォース対策 | 100回/5分 = 20回/分 で十分に抑制 |

### 8.2 API全体（RateLimitAPI: 600 req/5min/IP）

| 項目 | 計算 |
|------|------|
| 想定正常利用 | ページ遷移時に5-10リクエスト |
| 5分間の上限 | 600リクエスト |
| 1秒あたり換算 | 2リクエスト/秒 |
| 想定シナリオ | 通常の操作で十分な余裕あり |

## 9. WAFルール優先順位の設計根拠

| 優先度 | ルール | 配置理由 |
|--------|--------|---------|
| 0 | GeoBlockNonJP | 最初に地理的制限を適用し、対象外の国からのリクエストを早期に拒否 |
| 1 | RateLimitAuth | 認証エンドポイントは攻撃対象になりやすいため、厳しい制限を先に適用 |
| 2 | RateLimitAPI | 全体的なレート制限を認証ルールの後に適用 |
| 3-5 | AWS Managed Rules | 残ったリクエストに対して詳細な脆弱性チェックを実施 |
