# プロジェクト構造ガイド

このプロジェクトはオニオンアーキテクチャ + DDD + CQRSをベースにした構成。

## ディレクトリ構造

### アプリケーションのベース構造 (`src/main/java/.../keirekipro/`)
```
keirekipro
|
+-- domain           # ドメイン層：ビジネスロジックの中核
|   +-- model        #   エンティティ、値オブジェクト、集約
|   +-- repository   #   リポジトリインターフェース
|   +-- service      #   ドメインサービス
|   +-- policy       #   ドメインポリシー
|   +-- event        #   ドメインイベント
|   +-- shared       #   基底クラス、共通例外
|
+-- usecase          # ユースケース層：アプリケーションのビジネスロジック
|   +-- auth         #   認証関連ユースケース
|   +-- resume       #   職務経歴書関連ユースケース
|   +-- user         #   ユーザー関連ユースケース
|   +-- query        #   参照系クエリ（CQRS）
|   +-- shared       #   共通インターフェース（通知、ストア等）
|
+-- infrastructure   # インフラ層：外部システムとの連携
|   +-- repository   #   リポジトリ実装（MyBatis）
|   +-- query        #   クエリ実装（CQRS）
|   +-- auth         #   OIDC連携
|   +-- event        #   ドメインイベントリスナー
|   +-- export       #   PDF/Markdown出力
|   +-- logging      #   ユースケースロギング
|   +-- store        #   Redisストア実装
|   +-- shared       #   AWS連携、Redis設定、通知
|
+-- presentation     # プレゼンテーション層：HTTPリクエスト/レスポンス処理
|   +-- */controller #   RESTコントローラー
|   +-- */dto        #   リクエスト/レスポンスDTO
|   +-- security     #   認証フィルター、JWT
|   +-- shared       #   例外ハンドラー、バリデーター
|
+-- shared           # アプリケーション共通
    +-- config       #   設定クラス
    +-- exception    #   基底例外
    +-- utils        #   ユーティリティ
```

### リソース構造 (`src/main/resources/`)
```
resources
|
+-- application.yaml      # 共通設定
+-- application-dev.yaml  # 開発環境設定
+-- application-prod.yaml # 本番環境設定
|
+-- db/migration          # Flywayマイグレーション
|
+-- fonts                 # PDF出力用フォント
|
+-- mail                  # メールテンプレート（FreeMarker）
|
+-- mybatis               # MyBatis設定
|
+-- templates/resume      # 職務経歴書テンプレート（Thymeleaf）
    +-- pdf               #   PDF用HTMLテンプレート
    +-- markdown          #   Markdown用テンプレート
```

## アプリケーションの起動方法

### デバッグモードでの起動

1. VSCodeで`F5`キーを押下
   - Spring Bootアプリケーションが起動する
   - プロファイル `dev` で起動
   - ブレークポイントを設定してデバッグ可能

2. 起動後、以下のURLでAPIにアクセス可能：
   - API: `http://localhost:8080/api/`
   - Swagger UI: `http://localhost:8080/swagger-ui.html`

### テストの実行

VSCodeのサイドバーからフラスコアイコン（Testing）をクリックし、実行したいテストを選択して実行する。

## 設計原則

### レイヤー間の依存関係
```
presentation → usecase → domain
                 ↑          ↑
             infrastructure

shared（すべての層から参照可能）
```

- 内側のレイヤーは外側のレイヤーを知らない
- 依存性逆転の原則により、infrastructureはdomain/usecaseのインターフェースを実装
- presentationはusecaseのみを参照し、infrastructureを直接参照しない
- sharedはすべての層から参照可能な共通モジュール

### コントローラーの設計

- 1クラス1パブリックメソッドの原則
- メソッド名は `handle()`
- 例: `CreateResumeController`, `UpdateResumeBasicController`, `DeleteResumeController`

### ユースケースの設計

- 1クラス1パブリックメソッドの原則
- メソッド名は `execute()`
- 例: `CreateResumeUseCase`, `UpdateResumeBasicUseCase`, `DeleteResumeUseCase`

### CQRS

- 更新系: `usecase/{feature}/`配下のUseCaseクラス → Repository
- 参照系: `usecase/query/`配下のQueryインターフェース → `infrastructure/query/`で実装
