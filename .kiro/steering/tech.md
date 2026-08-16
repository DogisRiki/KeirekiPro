# 技術スタック

## アーキテクチャ

- **backend**: Spring Boot / Java 21。オニオンアーキテクチャ + DDD + CQRS。
  層はパッケージ(`domain` / `usecase` / `infrastructure` / `presentation` / `shared`)で表現し、
  依存方向はArchUnitテストで機械強制される
- **frontend**: React SPA(TypeScript / Vite)。bulletproof-react型のfeature-first構成。
  境界(feature間参照の禁止等)はESLintで機械強制される
- **インフラ**: AWS。Terraformで管理(`terraform/modules/` + `terraform/environments/prod/`)。
  `terraform apply` は人間がGitHub Actions経由でのみ実行する

## コア技術

| 領域 | 技術 |
|---|---|
| backend | Java 21 / Spring Boot 3.5系 / Gradle(wrapper) |
| frontend | React 19 / TypeScript 5.9系 / Vite / Node 24 / pnpm(corepack固定) |
| DB | PostgreSQL 17系 + Flyway(マイグレーション) |
| キャッシュ | Redis(トークン失効管理等) |
| オブジェクトストレージ | S3(開発環境はLocalStackでS3/SES/Secrets Managerをエミュレート。MinIOではない) |

正確なバージョンは `backend/gradle/libs.versions.toml` と `frontend/package.json` が正。
steeringには転記しない(更新のたびに乖離するため)。

## パターンを規定する主要ライブラリ

### backend

- **MyBatis**(JPAではない): コマンド側リポジトリ実装とクエリ側の両方。XMLマッパーは
  Javaインターフェースと同じパッケージに置ける(`sourceSets` でjavaディレクトリをリソースに含めている)
- **Spring Security + OAuth2 Client**: 認証はステートレスJWT(セッションではない)。
  アクセストークン10分・リフレッシュトークン7日。CSRFはCookieベースで併用
- **Thymeleaf + OpenHTMLtoPDF**: PDF出力(Noto Sans JP / Noto Serif JP埋め込み)。
  メールテンプレートはFreeMarker
- **Spring Cloud AWS**: S3 / SES / Secrets Manager
- **Lombok / springdoc-openapi**(Swagger UI)

### frontend

- **MUI + Emotion**: UIキット
- **TanStack Query**(サーバー状態)と **Zustand**(クライアント状態)の分離が規約。
  サーバー状態をストアに写さない。フォーム状態はコンポーネントローカル
  (zod・フォームライブラリは不使用)
- **axios + axios-auth-refresh**: HTTPクライアントとトークンリフレッシュ
- **dnd-kit**(並べ替え)、**dayjs**、**Hygen**(`pnpm run new` でfeatureの雛形生成)

## テスト

| 対象 | ツール | 方針 |
|---|---|---|
| backend単体 | JUnit 5 + Mockito + AssertJ | domain/usecaseは純粋な単体テスト |
| backend結合 | Testcontainers(postgres / localstack)+ dind | infrastructureは実物のPostgres/Redisで検証 |
| backendアーキテクチャ | ArchUnit | 層依存・命名・配置ルールを `check` で強制 |
| frontend単体 | Vitest + Testing Library + happy-dom | `__tests__/` にコロケーション |
| E2E | Playwright | ビルド成果物を `vite preview` で配信。バックエンド無しで検証できる範囲に限定 |
| ミューテーション | PIT(backend)/ Stryker(frontend) | 週次レポートのみ。ゲートには入れない |

テストの完全性: 新規テストは対象コードを一時的に壊して赤くなることを確認してから戻す。
`@Disabled` / `.skip` / `.only` / `@ts-ignore` / インラインlint無効化は禁止(escape-hatchチェックが検知)。

## 品質基準

- カバレッジ閾値は「一度上げたら下げない」ラチェット運用。現在値は
  `backend/gradle/quality.gradle`(JaCoCo)と `frontend/vite.config.ts`(v8)が正
- backend: Spotless(フォーマット)・Checkstyle・SpotBugs・PMDを `check` で一括実行
- frontend: ESLint(flat config)+ Prettier。アサーションの無いテストはlintで拒否される
- これらのゲート設定ファイルはCODEOWNERS保護されており、エージェントは変更しない

## 開発環境

すべてDocker Compose(`compose.yaml`)のコンテナ内で実行する。
サービス: `backend` / `frontend` / `terraform` / `db`(PostgreSQL)/ `redis` /
`localstack` / `dind`(Testcontainers用のDockerデーモン)。起動は `./start-dev.sh`。

品質ゲートのコマンドはルートCLAUDE.mdの `/verify-frontend` `/verify-backend`
`/verify-terraform` が正(直列実行・並列禁止)。

## 主要な技術的意思決定

1. **認証はステートレスJWT**: セッションを持たず、失効管理はRedisで行う
2. **CQRSはイベントソーシング無し**: 書き込みはドメイン集約経由、読み取りはMyBatisマッパーで
   DTOを直接返しドメイン再構築を省く
3. **PDFはサーバーサイド生成**: クライアント生成にせず、テンプレートで出力品質を管理する
4. **バージョンカタログを承認境界にする**: backendの依存バージョンは
   `libs.versions.toml` に集約し `build.gradle` に直書きしない。TOMLは純粋な宣言なので
   機械検査(脆弱性・クールダウン)で代替でき、`*.gradle` の変更だけを人間承認に残せる
5. **DBマイグレーションはexpand-contract**: 後方互換を保つ2段階変更。expandとcontractを
   同一PRに入れない。マイグレーションPRは人間承認ゲートを通る
6. **チェックツールのバージョン固定**: checkov等は無断更新で新ルールが有効になり
   全PRが赤くなるため、Dockerfileで固定し人間が明示的に上げる
