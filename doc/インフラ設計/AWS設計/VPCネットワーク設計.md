# VPCネットワーク設計書

## 1. VPC設計

| 項目 | 設定値 |
|------|--------|
| VPC名 | keirekipro-vpc |
| CIDR | 10.0.0.0/16 |
| DNS解決 | 有効 |
| DNSホスト名 | 有効 |

## 2. サブネット設計

| サブネット名 | CIDR | AZ | 種別 | 用途 |
|-------------|------|-----|------|------|
| keirekipro-public-1a | 10.0.1.0/24 | ap-northeast-1a | パブリック | NAT Gateway |
| keirekipro-public-1c | 10.0.2.0/24 | ap-northeast-1c | パブリック | - |
| keirekipro-private-1a | 10.0.11.0/24 | ap-northeast-1a | プライベート | ALB、ECS、RDS、ElastiCache Serverless |
| keirekipro-private-1c | 10.0.12.0/24 | ap-northeast-1c | プライベート | ALB、ElastiCache Serverless |

※ ALB は internal で、プライベートの2つのサブネットに置く。CloudFront からは VPC オリジンでつなぐ
※ ElastiCache Serverless には、プライベートの2つのサブネットを指定する
※ RDSのサブネットグループには両AZのサブネットを登録するが、Single-AZ構成のため、実際のインスタンスはprivate-1aにのみ配置される

## 3. インターネットゲートウェイ設計

| 項目 | 設定値 |
|------|--------|
| 名前 | keirekipro-igw |
| アタッチ先 | keirekipro-vpc |

## 4. NAT Gateway設計

| 項目 | 設定値 |
|------|--------|
| 名前 | keirekipro-nat |
| 配置サブネット | keirekipro-public-1a |
| Elastic IP | 新規割り当て |

## 5. ルートテーブル設計

### 5.1 パブリックルートテーブル

| 名前 | keirekipro-public-rt |
|------|----------------------|

| 送信先 | ターゲット |
|--------|-----------|
| 10.0.0.0/16 | local |
| 0.0.0.0/0 | keirekipro-igw |

関連付けサブネット: keirekipro-public-1a, keirekipro-public-1c

### 5.2 プライベートルートテーブル

| 名前 | keirekipro-private-rt |
|------|-----------------------|

| 送信先 | ターゲット |
|--------|-----------|
| 10.0.0.0/16 | local |
| 0.0.0.0/0 | keirekipro-nat |

関連付けサブネット: keirekipro-private-1a, keirekipro-private-1c

## 6. セキュリティグループ設計

### 6.1 ALB用セキュリティグループ

| 名前 | keirekipro-alb-sg |
|------|-------------------|

インバウンドルール:

| プロトコル | ポート | ソース | 説明 |
|-----------|--------|--------|------|
| HTTPS | 443 | CloudFrontのオリジン向けのマネージドプレフィックスリスト(com.amazonaws.global.cloudfront.origin-facing) | CloudFrontからのアクセス |

アウトバウンドルール:

| プロトコル | ポート | 送信先 | 説明 |
|-----------|--------|--------|------|
| TCP | 8080 | keirekipro-ecs-sg | ECSへのヘルスチェック・リクエスト転送 |

### 6.2 ECS用セキュリティグループ

| 名前 | keirekipro-ecs-sg |
|------|-------------------|

インバウンドルール:

| プロトコル | ポート | ソース | 説明 |
|-----------|--------|--------|------|
| TCP | 8080 | keirekipro-alb-sg | ALBからのリクエスト受信 |

アウトバウンドルール:

| プロトコル | ポート | 送信先 | 説明 |
|-----------|--------|--------|------|
| TCP | 5432 | keirekipro-rds-sg | RDSへの接続 |
| TCP | 6379-6380 | keirekipro-redis-sg | ElastiCache Serverlessへの接続 |
| TCP | 443 | 0.0.0.0/0 | AWS API、外部サービス接続 |

### 6.3 RDS用セキュリティグループ

| 名前 | keirekipro-rds-sg |
|------|-------------------|

インバウンドルール:

| プロトコル | ポート | ソース | 説明 |
|-----------|--------|--------|------|
| TCP | 5432 | keirekipro-ecs-sg | ECSからの接続 |

アウトバウンドルール:

| プロトコル | ポート | 送信先 | 説明 |
|-----------|--------|--------|------|
| なし | - | - | 不要 |

### 6.4 Redis用セキュリティグループ

| 名前 | keirekipro-redis-sg |
|------|---------------------|

インバウンドルール:

| プロトコル | ポート | ソース | 説明 |
|-----------|--------|--------|------|
| TCP | 6379-6380 | keirekipro-ecs-sg | ECSからの接続 |

※ ElastiCache Serverless は、読み書きに 6379、読み取り専用に 6380 を使う。

アウトバウンドルール:

| プロトコル | ポート | 送信先 | 説明 |
|-----------|--------|--------|------|
| なし | - | - | 不要 |

## 7. VPCエンドポイント設計

### 7.1 Gatewayエンドポイント

| サービス | 名前 | 関連付けルートテーブル |
|----------|------|----------------------|
| S3 | keirekipro-s3-endpoint | keirekipro-private-rt |

### 7.2 Interfaceエンドポイント

| サービス | 名前 | 配置サブネット | セキュリティグループ |
|----------|------|---------------|-------------------|
| ECR API | keirekipro-ecr-api-endpoint | keirekipro-private-1a, 1c | keirekipro-vpce-sg |
| ECR Docker | keirekipro-ecr-dkr-endpoint | keirekipro-private-1a, 1c | keirekipro-vpce-sg |
| CloudWatch Logs | keirekipro-logs-endpoint | keirekipro-private-1a, 1c | keirekipro-vpce-sg |
| Secrets Manager | keirekipro-secretsmanager-endpoint | keirekipro-private-1a, 1c | keirekipro-vpce-sg |

### 7.3 VPCエンドポイント用セキュリティグループ

| 名前 | keirekipro-vpce-sg |
|------|-------------------|

インバウンドルール:

| プロトコル | ポート | ソース | 説明 |
|-----------|--------|--------|------|
| TCP | 443 | keirekipro-ecs-sg | ECSからのHTTPS接続 |
