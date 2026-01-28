# ECS・ECR設計書

## 1. ECRリポジトリ設計

### 1.1 リポジトリ基本設定

| 項目 | 設定値 |
|------|--------|
| リポジトリ名 | keirekipro-backend |
| イメージタグのミュータビリティ | IMMUTABLE |
| 暗号化 | AES-256（AWS管理キー） |
| スキャン設定 | プッシュ時スキャン有効 |

### 1.2 ライフサイクルポリシー

```json
{
  "rules": [
    {
      "rulePriority": 1,
      "description": "最新5世代のイメージを保持",
      "selection": {
        "tagStatus": "any",
        "countType": "imageCountMoreThan",
        "countNumber": 5
      },
      "action": {
        "type": "expire"
      }
    }
  ]
}
```

## 2. ECSクラスター設計

### 2.1 クラスター基本設定

| 項目 | 設定値 |
|------|--------|
| クラスター名 | keirekipro-cluster |
| キャパシティプロバイダー | FARGATE, FARGATE_SPOT |
| デフォルトキャパシティプロバイダー戦略 | FARGATE: weight=1 |
| Container Insights | 無効 |

## 3. タスク定義設計

### 3.1 タスク定義基本設定

| 項目 | 設定値 |
|------|--------|
| タスク定義ファミリー名 | keirekipro-backend-task |
| 起動タイプ互換性 | FARGATE |
| ネットワークモード | awsvpc |
| CPU | 256（0.25 vCPU） |
| メモリ | 2048 MiB（2 GiB） |
| タスク実行ロール | keirekipro-ecs-task-execution-role |
| タスクロール | keirekipro-ecs-task-role |
| オペレーティングシステムファミリー | LINUX |
| CPUアーキテクチャ | ARM64 |

### 3.2 コンテナ定義

| 項目 | 設定値 |
|------|--------|
| コンテナ名 | keirekipro-backend |
| イメージ | {AWS_ACCOUNT_ID}.dkr.ecr.ap-northeast-1.amazonaws.com/keirekipro-backend:latest |
| 必須コンテナ | はい |
| ポートマッピング | 8080/tcp |

### 3.3 リソース制限

| 項目 | 設定値 |
|------|--------|
| CPU（ハード制限） | 256 |
| メモリ（ハード制限） | 2048 MiB |
| メモリ（ソフト制限） | 1792 MiB |

### 3.4 環境変数

| 変数名 | 値 | 説明 |
|--------|-----|------|
| SPRING_PROFILES_ACTIVE | prod | Spring Bootプロファイル |
| TZ | Asia/Tokyo | タイムゾーン |
| JAVA_TOOL_OPTIONS | -XX:+UseContainerSupport -XX:MaxRAMPercentage=75.0 | JVMオプション |

### 3.5 シークレット参照

| 変数名 | 参照先（Secrets Manager ARN） |
|--------|-------------------------------|
| ※spring.config.importで自動取得 | keirekipro/rds |
| ※spring.config.importで自動取得 | keirekipro/redis |
| ※spring.config.importで自動取得 | keirekipro/jwt |

### 3.6 ログ設定

| 項目 | 設定値 |
|------|--------|
| ログドライバー | awslogs |
| awslogs-group | /ecs/keirekipro-backend |
| awslogs-region | ap-northeast-1 |
| awslogs-stream-prefix | ecs |

### 3.7 ヘルスチェック

| 項目 | 設定値 |
|------|--------|
| コマンド | CMD-SHELL, curl -f http://localhost:8080/actuator/health \|\| exit 1 |
| 間隔 | 30秒 |
| タイムアウト | 5秒 |
| 開始期間 | 60秒 |
| リトライ回数 | 3回 |

## 4. サービス設計

### 4.1 サービス基本設定

| 項目 | 設定値 |
|------|--------|
| サービス名 | keirekipro-backend-service |
| クラスター | keirekipro-cluster |
| 起動タイプ | FARGATE |
| プラットフォームバージョン | LATEST |
| 希望タスク数 | 0 |
| 最小ヘルス率 | 100% |
| 最大率 | 200% |

### 4.2 ネットワーク設定

| 項目 | 設定値 |
|------|--------|
| VPC | keirekipro-vpc |
| サブネット | keirekipro-private-1a, keirekipro-private-1c |
| セキュリティグループ | keirekipro-ecs-sg |
| パブリックIPの自動割り当て | 無効 |

### 4.3 ロードバランサー設定

| 項目 | 設定値 |
|------|--------|
| ロードバランサータイプ | Application Load Balancer |
| ターゲットグループ | keirekipro-backend-tg |
| コンテナ名 | keirekipro-backend |
| コンテナポート | 8080 |
| ヘルスチェック猶予期間 | 180秒 |

### 4.4 デプロイ設定

| 項目 | 設定値 |
|------|--------|
| デプロイメントタイプ | ローリングアップデート |
| デプロイメント回路ブレーカー | 有効 |
| ロールバック | 有効 |
| 最小ヘルス率 | 100% |
| 最大率 | 200% |

### 4.5 オートスケーリング設定

| 項目 | 設定値 |
|------|--------|
| 最小タスク数 | 1 |
| 最大タスク数 | 2 |
| スケーリングポリシータイプ | ターゲット追跡 |

#### スケールアウトポリシー

| 項目 | 設定値 |
|------|--------|
| メトリクス | ECSServiceAverageCPUUtilization |
| ターゲット値 | 60% |
| スケールアウトクールダウン | 300秒 |
| スケールインクールダウン | 300秒 |

## 5. Dockerfile設計

### 5.1 マルチステージビルド構成

```dockerfile
# ビルドステージ
FROM eclipse-temurin:21-jdk AS builder
WORKDIR /app
COPY gradlew .
COPY gradle gradle
COPY build.gradle settings.gradle ./
COPY src src
RUN chmod +x ./gradlew && ./gradlew bootJar --no-daemon

# 実行ステージ
FROM eclipse-temurin:21-jre
WORKDIR /app
RUN apt-get update && apt-get install -y --no-install-recommends curl && rm -rf /var/lib/apt/lists/*
RUN groupadd -r spring && useradd -r -g spring spring
COPY --from=builder /app/build/libs/*.jar app.jar
RUN chown -R spring:spring /app
USER spring
EXPOSE 8080
ENTRYPOINT ["java", "-jar", "app.jar"]
```

### 5.2 ビルド設定

| 項目 | 設定値 |
|------|--------|
| ベースイメージ（ビルド） | eclipse-temurin:21-jdk |
| ベースイメージ（実行） | eclipse-temurin:21-jre |
| 実行ユーザー | spring（非root） |
| 公開ポート | 8080 |

## 6. CloudWatch Logs設計

### 6.1 ロググループ設計

| 項目 | 設定値 |
|------|--------|
| ロググループ名 | /ecs/keirekipro-backend |
| 保持期間 | 14日 |
| 暗号化 | AWS管理キー |
