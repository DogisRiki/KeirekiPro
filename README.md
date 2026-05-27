# KeirekiPro

エンジニア向け職務経歴書作成Webアプリケーション

## 概要

エンジニアが職務経歴書を効率的に作成・管理するためのWebアプリケーションです。
プロジェクトごとの技術スタックや実績を詳細に記録し、職務経歴書のプレビュー確認、PDF／Markdown形式での出力、バックアップ／リストアができます。

**URL**: https://app.keirekipro.click

## アーキテクチャ

### 本番環境構成

![Architecture](doc/インフラ設計/構成図/本番環境構成/本番環境構成図.drawio.svg)

| レイヤー | サービス | 用途 |
|---------|---------|------|
| CDN/WAF | CloudFront, WAF | コンテンツ配信、DDoS対策、SQLインジェクション対策 |
| フロントエンド | S3 | React SPAホスティング |
| ロードバランサー | ALB | HTTPS終端、リクエスト振り分け |
| コンピューティング | ECS Fargate | バックエンドAPIコンテナ実行 |
| データベース | RDS PostgreSQL | データ永続化 |
| キャッシュ | ElastiCache for Valkey | 2FAコード・パスワードリセットトークン・OIDCセッション等の一時保存 |
| ストレージ | S3 | プロフィール画像等の保存 |
| メール | SES | メール認証、パスワードリセット、各種通知 |
| DNS/証明書 | Route 53, ACM | ドメイン管理、SSL/TLS証明書 |
| シークレット管理 | Secrets Manager | 認証情報の安全な管理 |
| 監視 | CloudWatch | ログ収集、メトリクス監視 |

### 開発環境構成

Docker Composeで7コンテナを起動し、DevContainerで開発を行います。

![Development Environment](doc/インフラ設計/構成図/開発環境構成/開発環境構成図.drawio.svg)

| コンテナ | 用途 |
|---------|------|
| backend (Spring Boot) | バックエンドAPI開発 |
| frontend (React) | フロントエンド開発 |
| terraform | IaC開発 |
| db (PostgreSQL) | データベース |
| redis | キャッシュ |
| localstack | AWS サービスエミュレーション（S3, Secrets Manager, SES） |
| dind | Testcontainers用Docker-in-Docker |

### CI/CDパイプライン

![Workflow](doc/インフラ設計/構成図/CICDワークフロー/CICDワークフロー図.drawio.svg)

GitHub ActionsとAWS OIDCを組み合わせた、セキュアで効率的なCI/CDパイプラインを構築しています。

| フェーズ | ワークフロー | トリガー | 処理内容 |
|---------|-------------|---------|---------|
| CI | ci.yaml | push / PR | paths-filterでfrontend/backendの変更検知、Frontend: Format → Lint → Test → Coverage → Production Build、Backend: Gradle check |
| Infrastructure | terraform-plan.yaml | PR (terraform/**) | Terraform Plan実行、PRにplan結果をコメント |
| Infrastructure | terraform-apply.yaml | push to main (terraform/**) | Terraform Apply実行（アプリケーションデプロイとは独立） |
| Backend CD | ci.yaml → backend-deploy.yaml | push to main (backend/**) | 変更対象のCI通過後、Docker Build → ECR Push → ECS Deploy → Wait Stable |
| Frontend CD | ci.yaml → frontend-deploy.yaml | push to main (frontend/**) | CIで生成した`frontend-dist`をS3へ配布 → CloudFront Cache Invalidate |
| Frontend Rollback | frontend-rollback.yaml | manual | 成功済みmain CI runの`frontend-dist`を検証して再配布 |

frontend/backendの両方に変更がある場合は、両方のCIが成功してからbackend、frontendの順にデプロイします。backendのデプロイに失敗した場合はfrontendを公開せず、frontendの公開失敗時は成功済みartifactを再配布して復旧します。

| 特徴 | 説明 |
|------|------|
| OIDC認証 | GitHub ActionsからAWSへのアクセスキーレス認証 |
| 変更検知 | paths-filterによる変更ファイルに応じた条件付き実行 |
| デプロイゲート | 変更対象のCIがすべて成功するまで本番デプロイを開始しない |
| Build once / Deploy same artifact | Frontendのproduction buildをCIで行い、検証済みartifactを配布・rollbackに再利用 |
| ローリングアップデート | ECSサービスの無停止デプロイと回路ブレーカーによるbackend自動rollback |
| キャッシュ無効化 | フロントエンド配布・rollback時のCloudFrontキャッシュ自動無効化 |
| State管理 | Terraform StateのS3保存とDynamoDBによるロック制御 |

### セキュリティ対策

- CloudFront → ALB間のオリジン検証（カスタムヘッダー）
- WAFによるAWSマネージドルール適用（SQLi、XSS、悪意あるBot対策）
- プライベートサブネットへのバックエンド配置
- Secrets Managerによる認証情報の一元管理
- HTTPS強制、HttpOnly/Secure Cookie設定
- CSRF対策（トークンベース）
- 認証トークンのサーバー側失効制御

## 技術スタック

### フロントエンド

| カテゴリ | 技術 |
|---------|------|
| 言語 | TypeScript |
| フレームワーク | React 18 |
| ビルドツール | Vite |
| 状態管理 | Zustand, TanStack Query |
| UIライブラリ | MUI (Material-UI) |
| ルーティング | React Router v7 |
| テスト | Vitest, Testing Library |
| カバレッジ | Vitest Coverage V8 |
| リンター | ESLint |
| フォーマッター | Prettier, prettier-plugin-organize-imports |
| コード生成 | Hygen |
| アナリティクス | Google Analytics 4 |

### バックエンド

| カテゴリ | 技術 |
|---------|------|
| 言語 | Java 21 |
| フレームワーク | Spring Boot 3.4 |
| データアクセス | MyBatis |
| マイグレーション | Flyway |
| 認証 | Spring Security, JWT (java-jwt) |
| PDF生成 | OpenHTMLtoPDF |
| テンプレートエンジン | Thymeleaf, FreeMarker |
| AWS連携 | Spring Cloud AWS (S3, SES, Secrets Manager) |
| API仕様 | Springdoc OpenAPI (Swagger UI) |
| 監視/トレーシング | Spring Boot Actuator, Micrometer, OpenTelemetry |
| テスト | JUnit 5, Mockito, AssertJ, Testcontainers |
| カバレッジ | JaCoCo |
| ビルドツール | Gradle |
| 静的解析 | Checkstyle, SpotBugs |
| フォーマッター | Spotless, Eclipse Formatter |

### インフラ/DevOps

| カテゴリ | 技術 |
|---------|------|
| クラウド | AWS |
| IaC | Terraform |
| CI/CD | GitHub Actions |
| コンテナ | Docker, ECR, ECS Fargate |
| 監視 | CloudWatch Logs |
| 静的解析 | tflint, Checkov |

## 設計

### バックエンド: オニオンアーキテクチャ + DDD + CQRS

ドメイン駆動設計に基づき、関心の分離を徹底した多層構造を採用しています。

```
backend/src/main/java/com/example/keirekipro/
├── domain/           # ドメイン層
│   ├── model/        #   エンティティ、値オブジェクト、集約
│   ├── repository/   #   リポジトリインターフェース
│   ├── service/      #   ドメインサービス
│   ├── policy/       #   ドメインポリシー
│   ├── event/        #   ドメインイベント
│   └── shared/       #   基底クラス、共通例外
├── usecase/          # ユースケース層
│   ├── auth/         #   認証関連ユースケース
│   ├── resume/       #   職務経歴書関連ユースケース
│   ├── user/         #   ユーザー関連ユースケース
│   ├── query/        #   参照系クエリ（CQRS）
│   └── shared/       #   共通インターフェース
├── infrastructure/   # インフラ層
│   ├── repository/   #   リポジトリ実装（MyBatis）
│   ├── query/        #   クエリ実装（CQRS）
│   ├── auth/         #   OIDC連携
│   ├── event/        #   ドメインイベントリスナー
│   ├── export/       #   PDF/Markdown出力
│   ├── logging/      #   ユースケースロギング
│   ├── store/        #   Redisストア実装
│   └── shared/       #   AWS連携、Redis設定、通知
├── presentation/     # プレゼンテーション層
│   ├── */controller/ #   RESTコントローラー
│   ├── */dto/        #   リクエスト/レスポンスDTO
│   ├── security/     #   認証フィルター、JWT
│   └── shared/       #   例外ハンドラー、バリデーター
└── shared/           # アプリケーション共通
    ├── config/       #   設定クラス
    ├── exception/    #   基底例外
    └── utils/        #   ユーティリティ
```

### フロントエンド: Bulletproof React

機能ベースのモジュール設計を採用し、関心の分離とスケーラビリティを確保しています。

```
frontend/src/
├── features/              # 機能モジュール
│   ├── auth/              #   認証
│   ├── resume/            #   職務経歴書
│   ├── user/              #   ユーザー設定
│   └── contact/           #   お問い合わせ
│       （各featureは以下のサブディレクトリを持つ）
│         ├── api/         #     API通信
│         ├── components/  #     コンポーネント
│         ├── hooks/       #     カスタムフック
│         ├── stores/      #     状態管理
│         ├── types/       #     型定義
│         └── utils/       #     ユーティリティ
├── components/            # 共通コンポーネント
│   ├── ui/                #   ボタン、テキストフィールド等
│   ├── dnd/               #   ドラッグ&ドロップ
│   ├── layouts/           #   レイアウト
│   └── errors/            #   エラー表示
├── config/                # 設定（環境変数、テーマ、パス定義）
├── hooks/                 # 共通フック
├── stores/                # グローバルストア
├── lib/                   # クライアント設定
├── pages/                 # ページコンポーネント
├── routes/                # ルーティング定義
├── providers/             # プロバイダー
├── types/                 # 共通型定義
└── utils/                 # ユーティリティ
```

## 規模

| 項目 | 数量 |
|------|------|
| APIエンドポイント | 48 |
| データベーステーブル | 17 |

## ディレクトリ構成

```
keirekipro/
├── frontend/                 # フロントエンド (React/TypeScript)
├── backend/                  # バックエンド (Spring Boot/Java)
├── terraform/                # インフラ定義
│   ├── modules/              # Terraformモジュール
│   ├── main.tf
│   └── variables.tf
├── .github/workflows/        # CI/CD定義
│   ├── ci.yaml
│   ├── frontend-deploy.yaml
│   ├── frontend-rollback.yaml
│   ├── backend-deploy.yaml
│   ├── terraform-plan.yaml
│   └── terraform-apply.yaml
├── docker/                   # Docker設定
├── docs/                     # 設計ドキュメント
└── compose.yaml
```

## AI駆動開発

本プロジェクトでは、Codex IDE と MCP（Model Context Protocol）を利用し、Issue 起点の計画作成・レビュー・実装支援を行います。

AI エージェントには、リポジトリ全体を無制限に操作させず、GitHub MCP の利用範囲を Issue / Pull Request / GitHub Actions の読み取りと、承認済み Plan の Issue コメント投稿に限定しています。

| MCP | 用途 |
|-----|------|
| GitHub MCP | Issue / PR / Actions の参照、Approved Plan の Issue コメント投稿 |
| Context7 MCP | ライブラリ・フレームワーク公式ドキュメントの参照 |
| Playwright MCP | ブラウザ操作を伴う動作確認・E2E観点の検証 |

### AI駆動開発フロー

| ステップ | 担当 | 内容 |
|---------|------|------|
| 1 | 開発者 | Issue を作成する |
| 2 | Codex IDE | GitHub MCP で Issue を読む |
| 3 | Codex IDE | 実装 Plan を作成する |
| 4 | 開発者 | Plan を確認する |
| 5 | Claude / ChatGPT | Plan をレビューする |
| 6 | Codex IDE | 指摘があれば Plan を修正する |
| 7 | 開発者 | Plan を承認する |
| 8 | Codex IDE | Approved Plan を Issue コメントに投稿する |
| 9 | 開発者 | 実装開始を承認する |
| 10 | Codex IDE | ローカル作業ツリーで実装する |

### GitHub MCPの権限制御

GitHub MCP には Fine-grained Personal Access Token を使用し、以下の権限に限定します。

| Permission | Access |
|-----------|--------|
| Contents | Read-only |
| Issues | Read and write |
| Pull requests | Read-only |
| Actions | Read-only |
| Metadata | Read-only |

Codex IDE に許可する操作は以下です。

- Issue を読む
- Issue コメントを読む
- Issue に Approved Plan をコメント投稿する
- PR を読む
- PR の diff / files / comments / reviews / check runs を読む
- GitHub Actions の workflow / run / job / logs を読む
- GitHub 上のファイル内容を読む

Codex IDE に許可しない操作は以下です。

- GitHub 上でコードを直接変更する
- branch を作成する
- commit を作成する
- push する
- PR を作成する
- PR を更新する
- PR review を投稿する
- merge する
- workflow を手動実行する
- deploy する

## Codex Skills

本プロジェクトでは、Codex Skills を利用し、繰り返し発生する作業を定型化しています。

現在、本プロジェクトでは以下のスキルを使用します。

| Skill | 用途 |
|------|------|
| `diff-backend-class-diagram-sync` | Git差分に含まれるバックエンドソースの変更を、クラス図へ同期する |
| `full-backend-class-diagram-sync` | バックエンドソース全体を正として、クラス図全体を同期する |
| `diff-db-er-diagram-sync` | Git差分に含まれる DB マイグレーションファイル の変更を、ER図へ同期する |
| `full-db-er-diagram-sync` | DB マイグレーションファイル 全体を正として、ER図全体を同期する |
| `draft-branch-name-and-commit-message` | 現在の Git 差分から、ブランチ名とコミットメッセージ案を作成する |
| `draft-issue-plan` | GitHub Issue の本文とコメントを読み、実装 Plan を作成する |
| `post-issue-plan-comment` | 作成済みの Plan を指定した GitHub Issue にコメント投稿する |
