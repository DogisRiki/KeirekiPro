# CloudWatch設計書

## 1. 設計概要

### 1.1 監視対象コンポーネント

| コンポーネント | 監視項目 |
|---------------|---------|
| ECS | CPU使用率、メモリ使用率、タスク数 |
| ALB | リクエスト数、5xxエラー、レイテンシ、ターゲット健全性 |
| RDS | CPU使用率、空きストレージ、接続数、読み書きレイテンシ |
| ElastiCache Redis | CPU使用率、メモリ使用率、接続数、キャッシュヒット率 |

## 2. ロググループ設計

### 2.1 ロググループ一覧

| ロググループ名 | 用途 | 保持期間 | 暗号化 |
|--------------|------|---------|--------|
| /ecs/keirekipro-backend | ECSタスクのアプリケーションログ | 14日 | AWS管理キー |

### 2.2 ECSアプリケーションログ設定

| 項目 | 設定値 |
|------|--------|
| ロググループ名 | /ecs/keirekipro-backend |
| ログストリーム名形式 | ecs/keirekipro-backend/{タスクID} |
| 保持期間 | 14日 |
| 暗号化 | AWS管理キー |
| ログドライバー | awslogs |
| awslogs-region | ap-northeast-1 |
| awslogs-stream-prefix | ecs |

## 3. メトリクス設計

### 3.1 ECSメトリクス

| メトリクス名 | 名前空間 | ディメンション | 説明 |
|-------------|---------|---------------|------|
| CPUUtilization | AWS/ECS | ClusterName, ServiceName | CPU使用率（%） |
| MemoryUtilization | AWS/ECS | ClusterName, ServiceName | メモリ使用率（%） |
| RunningTaskCount | ECS/ContainerInsights | ClusterName, ServiceName | 稼働中タスク数 |

### 3.2 ALBメトリクス

| メトリクス名 | 名前空間 | ディメンション | 説明 |
|-------------|---------|---------------|------|
| HTTPCode_Target_5XX_Count | AWS/ApplicationELB | LoadBalancer | 5xxエラー数 |
| HTTPCode_ELB_5XX_Count | AWS/ApplicationELB | LoadBalancer | ALB側5xxエラー数 |
| TargetResponseTime | AWS/ApplicationELB | LoadBalancer | レスポンス時間（秒） |
| UnHealthyHostCount | AWS/ApplicationELB | LoadBalancer, TargetGroup | 不健全なターゲット数 |
| HealthyHostCount | AWS/ApplicationELB | LoadBalancer, TargetGroup | 健全なターゲット数 |
| RequestCount | AWS/ApplicationELB | LoadBalancer | リクエスト総数 |

### 3.3 RDSメトリクス

| メトリクス名 | 名前空間 | ディメンション | 説明 |
|-------------|---------|---------------|------|
| CPUUtilization | AWS/RDS | DBInstanceIdentifier | CPU使用率（%） |
| FreeStorageSpace | AWS/RDS | DBInstanceIdentifier | 空きストレージ（バイト） |
| DatabaseConnections | AWS/RDS | DBInstanceIdentifier | 現在の接続数 |
| ReadLatency | AWS/RDS | DBInstanceIdentifier | 読み取りレイテンシ（秒） |
| WriteLatency | AWS/RDS | DBInstanceIdentifier | 書き込みレイテンシ（秒） |
| FreeableMemory | AWS/RDS | DBInstanceIdentifier | 利用可能メモリ（バイト） |

### 3.4 ElastiCache Redisメトリクス

| メトリクス名 | 名前空間 | ディメンション | 説明 |
|-------------|---------|---------------|------|
| CPUUtilization | AWS/ElastiCache | CacheClusterId | CPU使用率（%） |
| DatabaseMemoryUsagePercentage | AWS/ElastiCache | CacheClusterId | メモリ使用率（%） |
| CurrConnections | AWS/ElastiCache | CacheClusterId | 現在の接続数 |
| CacheHitRate | AWS/ElastiCache | CacheClusterId | キャッシュヒット率（%） |
| Evictions | AWS/ElastiCache | CacheClusterId | キー排出数 |

## 4. アラーム設計

### 4.1 アラーム一覧

| アラーム名 | 対象 | メトリクス | 条件 | 期間 | 重要度 |
|-----------|------|-----------|------|------|--------|
| keirekipro-ecs-cpu-high | ECS | CPUUtilization | >= 80% | 5分 x 2回 | Warning |
| keirekipro-ecs-memory-high | ECS | MemoryUtilization | >= 80% | 5分 x 2回 | Warning |
| keirekipro-alb-5xx-high | ALB | HTTPCode_Target_5XX_Count | >= 10 | 5分 x 2回 | Critical |
| keirekipro-alb-unhealthy | ALB | UnHealthyHostCount | >= 1 | 1分 x 3回 | Critical |
| keirekipro-rds-cpu-high | RDS | CPUUtilization | >= 80% | 5分 x 2回 | Warning |
| keirekipro-rds-storage-low | RDS | FreeStorageSpace | <= 2GB | 5分 x 1回 | Critical |
| keirekipro-redis-memory-high | Redis | DatabaseMemoryUsagePercentage | >= 80% | 5分 x 2回 | Warning |

### 4.2 ECSアラーム詳細

#### 4.2.1 keirekipro-ecs-cpu-high

| 項目 | 設定値 |
|------|--------|
| アラーム名 | keirekipro-ecs-cpu-high |
| 説明 | ECSタスクのCPU使用率が高い状態 |
| 名前空間 | AWS/ECS |
| メトリクス名 | CPUUtilization |
| ディメンション | ClusterName=keirekipro-cluster, ServiceName=keirekipro-backend-service |
| 統計 | Average |
| 期間 | 300秒（5分） |
| 評価期間 | 2 |
| 比較演算子 | GreaterThanOrEqualToThreshold |
| しきい値 | 80 |
| 欠落データの処理 | missing |
| アクション | SNSトピックへ通知 |

#### 4.2.2 keirekipro-ecs-memory-high

| 項目 | 設定値 |
|------|--------|
| アラーム名 | keirekipro-ecs-memory-high |
| 説明 | ECSタスクのメモリ使用率が高い状態 |
| 名前空間 | AWS/ECS |
| メトリクス名 | MemoryUtilization |
| ディメンション | ClusterName=keirekipro-cluster, ServiceName=keirekipro-backend-service |
| 統計 | Average |
| 期間 | 300秒（5分） |
| 評価期間 | 2 |
| 比較演算子 | GreaterThanOrEqualToThreshold |
| しきい値 | 80 |
| 欠落データの処理 | missing |
| アクション | SNSトピックへ通知 |

### 4.3 ALBアラーム詳細

#### 4.3.1 keirekipro-alb-5xx-high

| 項目 | 設定値 |
|------|--------|
| アラーム名 | keirekipro-alb-5xx-high |
| 説明 | 5xxエラーが多発している状態 |
| 名前空間 | AWS/ApplicationELB |
| メトリクス名 | HTTPCode_Target_5XX_Count |
| ディメンション | LoadBalancer=app/keirekipro-alb/xxxxxxxxxx |
| 統計 | Sum |
| 期間 | 300秒（5分） |
| 評価期間 | 2 |
| 比較演算子 | GreaterThanOrEqualToThreshold |
| しきい値 | 10 |
| 欠落データの処理 | notBreaching |
| アクション | SNSトピックへ通知 |

#### 4.3.2 keirekipro-alb-unhealthy

| 項目 | 設定値 |
|------|--------|
| アラーム名 | keirekipro-alb-unhealthy |
| 説明 | 不健全なターゲットが存在する状態 |
| 名前空間 | AWS/ApplicationELB |
| メトリクス名 | UnHealthyHostCount |
| ディメンション | LoadBalancer, TargetGroup |
| 統計 | Maximum |
| 期間 | 60秒（1分） |
| 評価期間 | 3 |
| 比較演算子 | GreaterThanOrEqualToThreshold |
| しきい値 | 1 |
| 欠落データの処理 | notBreaching |
| アクション | SNSトピックへ通知 |

### 4.4 RDSアラーム詳細

#### 4.4.1 keirekipro-rds-cpu-high

| 項目 | 設定値 |
|------|--------|
| アラーム名 | keirekipro-rds-cpu-high |
| 説明 | RDSのCPU使用率が高い状態 |
| 名前空間 | AWS/RDS |
| メトリクス名 | CPUUtilization |
| ディメンション | DBInstanceIdentifier=keirekipro-db |
| 統計 | Average |
| 期間 | 300秒（5分） |
| 評価期間 | 2 |
| 比較演算子 | GreaterThanOrEqualToThreshold |
| しきい値 | 80 |
| 欠落データの処理 | missing |
| アクション | SNSトピックへ通知 |

#### 4.4.2 keirekipro-rds-storage-low

| 項目 | 設定値 |
|------|--------|
| アラーム名 | keirekipro-rds-storage-low |
| 説明 | RDSの空きストレージが少ない状態 |
| 名前空間 | AWS/RDS |
| メトリクス名 | FreeStorageSpace |
| ディメンション | DBInstanceIdentifier=keirekipro-db |
| 統計 | Average |
| 期間 | 300秒（5分） |
| 評価期間 | 1 |
| 比較演算子 | LessThanOrEqualToThreshold |
| しきい値 | 2147483648（2GB） |
| 欠落データの処理 | missing |
| アクション | SNSトピックへ通知 |

### 4.5 Redisアラーム詳細

#### 4.5.1 keirekipro-redis-memory-high

| 項目 | 設定値 |
|------|--------|
| アラーム名 | keirekipro-redis-memory-high |
| 説明 | Redisのメモリ使用率が高い状態 |
| 名前空間 | AWS/ElastiCache |
| メトリクス名 | DatabaseMemoryUsagePercentage |
| ディメンション | CacheClusterId=keirekipro-redis-001 |
| 統計 | Average |
| 期間 | 300秒（5分） |
| 評価期間 | 2 |
| 比較演算子 | GreaterThanOrEqualToThreshold |
| しきい値 | 80 |
| 欠落データの処理 | missing |
| アクション | SNSトピックへ通知 |

## 5. SNS通知設計

### 5.1 SNSトピック設計

| 項目 | 設定値 |
|------|--------|
| トピック名 | keirekipro-alerts |
| 表示名 | KeirekiPro Alerts |
| タイプ | スタンダード |
| 暗号化 | 無効 |

### 5.2 サブスクリプション設計

| プロトコル | エンドポイント | 用途 |
|-----------|---------------|------|
| Email | {管理者メールアドレス} | アラート通知 |

### 5.3 アクセスポリシー

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowCloudWatchAlarms",
      "Effect": "Allow",
      "Principal": {
        "Service": "cloudwatch.amazonaws.com"
      },
      "Action": "sns:Publish",
      "Resource": "arn:aws:sns:ap-northeast-1:${AWS_ACCOUNT_ID}:keirekipro-alerts",
      "Condition": {
        "ArnLike": {
          "aws:SourceArn": "arn:aws:cloudwatch:ap-northeast-1:${AWS_ACCOUNT_ID}:alarm:*"
        }
      }
    }
  ]
}
```

## 6. ダッシュボード設計

### 6.1 ダッシュボード概要

| 項目 | 設定値 |
|------|--------|
| ダッシュボード名 | keirekipro-dashboard |
| リージョン | ap-northeast-1 |
| 自動更新 | 有効（1分間隔） |

### 6.2 ウィジェット構成

| 行 | ウィジェット名 | タイプ | 内容 |
|----|--------------|--------|------|
| 1 | ECS CPU | 折れ線グラフ | ECS CPUUtilization |
| 1 | ECS Memory | 折れ線グラフ | ECS MemoryUtilization |
| 2 | ALB Requests | 折れ線グラフ | RequestCount |
| 2 | ALB 5xx Errors | 折れ線グラフ | HTTPCode_Target_5XX_Count |
| 3 | ALB Response Time | 折れ線グラフ | TargetResponseTime |
| 3 | ALB Healthy Hosts | 数値 | HealthyHostCount, UnHealthyHostCount |
| 4 | RDS CPU | 折れ線グラフ | CPUUtilization |
| 4 | RDS Storage | 折れ線グラフ | FreeStorageSpace |
| 5 | RDS Connections | 折れ線グラフ | DatabaseConnections |
| 5 | RDS Latency | 折れ線グラフ | ReadLatency, WriteLatency |
| 6 | Redis Memory | 折れ線グラフ | DatabaseMemoryUsagePercentage |
| 6 | Redis Connections | 折れ線グラフ | CurrConnections |

### 6.3 ダッシュボードJSON定義

```json
{
  "widgets": [
    {
      "type": "metric",
      "x": 0,
      "y": 0,
      "width": 12,
      "height": 6,
      "properties": {
        "title": "ECS CPU Utilization",
        "metrics": [
          ["AWS/ECS", "CPUUtilization", "ClusterName", "keirekipro-cluster", "ServiceName", "keirekipro-backend-service"]
        ],
        "period": 300,
        "stat": "Average",
        "region": "ap-northeast-1",
        "yAxis": { "left": { "min": 0, "max": 100 } }
      }
    },
    {
      "type": "metric",
      "x": 12,
      "y": 0,
      "width": 12,
      "height": 6,
      "properties": {
        "title": "ECS Memory Utilization",
        "metrics": [
          ["AWS/ECS", "MemoryUtilization", "ClusterName", "keirekipro-cluster", "ServiceName", "keirekipro-backend-service"]
        ],
        "period": 300,
        "stat": "Average",
        "region": "ap-northeast-1",
        "yAxis": { "left": { "min": 0, "max": 100 } }
      }
    },
    {
      "type": "metric",
      "x": 0,
      "y": 6,
      "width": 12,
      "height": 6,
      "properties": {
        "title": "ALB Request Count",
        "metrics": [
          ["AWS/ApplicationELB", "RequestCount", "LoadBalancer", "app/keirekipro-alb/xxxxxxxxxx"]
        ],
        "period": 60,
        "stat": "Sum",
        "region": "ap-northeast-1"
      }
    },
    {
      "type": "metric",
      "x": 12,
      "y": 6,
      "width": 12,
      "height": 6,
      "properties": {
        "title": "ALB 5xx Errors",
        "metrics": [
          ["AWS/ApplicationELB", "HTTPCode_Target_5XX_Count", "LoadBalancer", "app/keirekipro-alb/xxxxxxxxxx"]
        ],
        "period": 60,
        "stat": "Sum",
        "region": "ap-northeast-1"
      }
    },
    {
      "type": "metric",
      "x": 0,
      "y": 12,
      "width": 12,
      "height": 6,
      "properties": {
        "title": "ALB Response Time",
        "metrics": [
          ["AWS/ApplicationELB", "TargetResponseTime", "LoadBalancer", "app/keirekipro-alb/xxxxxxxxxx"]
        ],
        "period": 60,
        "stat": "Average",
        "region": "ap-northeast-1"
      }
    },
    {
      "type": "metric",
      "x": 12,
      "y": 12,
      "width": 12,
      "height": 6,
      "properties": {
        "title": "ALB Target Health",
        "metrics": [
          ["AWS/ApplicationELB", "HealthyHostCount", "LoadBalancer", "app/keirekipro-alb/xxxxxxxxxx", "TargetGroup", "targetgroup/keirekipro-backend-tg/xxxxxxxxxx"],
          [".", "UnHealthyHostCount", ".", ".", ".", "."]
        ],
        "period": 60,
        "stat": "Average",
        "region": "ap-northeast-1"
      }
    },
    {
      "type": "metric",
      "x": 0,
      "y": 18,
      "width": 12,
      "height": 6,
      "properties": {
        "title": "RDS CPU Utilization",
        "metrics": [
          ["AWS/RDS", "CPUUtilization", "DBInstanceIdentifier", "keirekipro-db"]
        ],
        "period": 300,
        "stat": "Average",
        "region": "ap-northeast-1",
        "yAxis": { "left": { "min": 0, "max": 100 } }
      }
    },
    {
      "type": "metric",
      "x": 12,
      "y": 18,
      "width": 12,
      "height": 6,
      "properties": {
        "title": "RDS Free Storage Space",
        "metrics": [
          ["AWS/RDS", "FreeStorageSpace", "DBInstanceIdentifier", "keirekipro-db"]
        ],
        "period": 300,
        "stat": "Average",
        "region": "ap-northeast-1"
      }
    },
    {
      "type": "metric",
      "x": 0,
      "y": 24,
      "width": 12,
      "height": 6,
      "properties": {
        "title": "RDS Database Connections",
        "metrics": [
          ["AWS/RDS", "DatabaseConnections", "DBInstanceIdentifier", "keirekipro-db"]
        ],
        "period": 60,
        "stat": "Average",
        "region": "ap-northeast-1"
      }
    },
    {
      "type": "metric",
      "x": 12,
      "y": 24,
      "width": 12,
      "height": 6,
      "properties": {
        "title": "RDS Latency",
        "metrics": [
          ["AWS/RDS", "ReadLatency", "DBInstanceIdentifier", "keirekipro-db"],
          [".", "WriteLatency", ".", "."]
        ],
        "period": 60,
        "stat": "Average",
        "region": "ap-northeast-1"
      }
    },
    {
      "type": "metric",
      "x": 0,
      "y": 30,
      "width": 12,
      "height": 6,
      "properties": {
        "title": "Redis Memory Usage",
        "metrics": [
          ["AWS/ElastiCache", "DatabaseMemoryUsagePercentage", "CacheClusterId", "keirekipro-redis"]
        ],
        "period": 300,
        "stat": "Average",
        "region": "ap-northeast-1",
        "yAxis": { "left": { "min": 0, "max": 100 } }
      }
    },
    {
      "type": "metric",
      "x": 12,
      "y": 30,
      "width": 12,
      "height": 6,
      "properties": {
        "title": "Redis Connections",
        "metrics": [
          ["AWS/ElastiCache", "CurrConnections", "CacheClusterId", "keirekipro-redis"]
        ],
        "period": 60,
        "stat": "Average",
        "region": "ap-northeast-1"
      }
    }
  ]
}
```

## 7. ログインサイト設計

### 7.1 クエリ定義

#### 7.1.1 エラーログ検索クエリ

```
fields @timestamp, @message
| filter @message like /ERROR|WARN/
| sort @timestamp desc
| limit 100
```

#### 7.1.2 スロークエリ検索クエリ

```
fields @timestamp, @message
| filter @message like /event.duration/
| parse @message '"event.duration":*,' as duration
| filter duration > 1000
| sort duration desc
| limit 50
```

#### 7.1.3 HTTPステータスコード別集計クエリ

```
fields @timestamp, @message
| filter @message like /http.response.status_code/
| parse @message '"http.response.status_code":*,' as statusCode
| stats count(*) by statusCode
```

## 8. コスト最適化設計

### 8.1 コスト削減施策

| 施策 | 設定 | 効果 |
|-----|------|------|
| ログ保持期間の最小化 | 14日 | ストレージコスト削減 |
| Container Insights無効化 | 無効 | メトリクスコスト削減 |
| 詳細モニタリング無効化 | 無効（RDS） | メトリクスコスト削減 |
| CloudFrontログ無効化 | 無効 | ストレージコスト削減 |
| WAFログ無効化 | 無効 | ストレージコスト削減 |

### 8.2 無料枠の活用

| 項目 | 無料枠 |
|------|--------|
| カスタムメトリクス | 10個/月 |
| ダッシュボード | 3個/月 |
| アラーム | 10個/月 |
| ログデータ取り込み | 5GB/月 |
| ログデータ保存 | 5GB/月 |
| ログInsightsクエリ | スキャンデータ5GB/月 |

## 9. 将来的な拡張設計

### 9.1 拡張候補機能

| 機能 | 用途 | 追加コスト |
|-----|------|-----------|
| Container Insights | ECS詳細監視 | 有料 |
| Performance Insights | RDS詳細監視 | 無料（7日保持） |
| X-Ray | 分散トレーシング | 有料 |
| Contributor Insights | トップN分析 | 有料 |
| Synthetics Canary | 外形監視 | 有料 |

### 9.2 拡張時の注意事項

- Container Insightsを有効化する場合は、ECSクラスター設定で有効化が必要
- Performance Insightsを有効化する場合は、RDSインスタンス設定の変更が必要
- X-Rayを有効化する場合は、アプリケーションコードへのSDK組み込みが必要
