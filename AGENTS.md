## プロジェクト概要

KeirekiPro は、エンジニア向けの職務経歴書を作成、管理するフルスタック Web アプリケーションです。

このアプリケーションは、案件経歴、スキル、PDF/Markdown エクスポート、プロフィール画像、認証、バックアップ/リストア、AWS 上のインフラ管理を扱います。

## リポジトリ構成

- `backend` - Spring Boot バックエンド API
- `frontend` - React/Vite フロントエンド SPA
- `terraform` - AWS インフラ IaC
- `docker` と `compose.yaml` - Docker / devcontainer 設定
- `.github/workflows` - GitHub Actions CI/CD workflow
- `doc` - アーキテクチャおよびプロジェクト資料

全体の文脈把握のためにリポジトリ全体を確認してよいです。

ただし、変更は依頼された作業範囲に限定してください。

## 基本ルール

- 依頼範囲外のファイルを変更しないでください。
- 明示的に求められていない既存コメントを削除しないでください。
- スタイル調整だけを目的にファイル全体を書き換えないでください。
- 明示的に求められていない新しいライブラリ、フレームワーク、ツール、ランタイム依存を追加しないでください。
- コード実装、コード修正、設計、リファクタリング、テスト追加、エラー調査、セットアップ、設定変更では、Context7 を使用して関連する外部技術の現在の公式ドキュメントを確認してください。
- 明示的に求められていない public behavior、API contract、DB schema、インフラ設定、CI/CD 挙動、デプロイ挙動を変更しないでください。
- 明示的に求められていない commit、push、merge、deploy、破壊的コマンドを実行しないでください。
- 完了報告前に、必ず最終 diff を確認してください。
- ユーザーへの確認、承認要求、完了報告は日本語で行ってください。
- ソースコード、コメント、テスト名、ドキュメント、完了報告で文字化けした日本語を出力しないでください。
- 文字化けを検知した場合は、そのまま保存せず、正しい日本語に直してから変更してください。
- リポジトリ内のテキストファイルは UTF-8 として読み書きしてください。
- 文字化けした内容を根拠に作業しないでください。UTF-8として読み直しても判読できない場合は、推測せず対象ファイル名を報告して停止してください。

## Git

Git 操作は、ホスト OS のリポジトリルートで実行してください。

作業開始前に、必ず作業内容に対応するブランチを作成してから変更してください。

ブランチ名は、ルートにある `.branch_name_template` に従って作成してください。

```bash
git switch -c docs/update-agent-guidelines
```

```bash
git status --short
git diff --stat
git diff
```

完了報告前に、意図したファイルだけが変更されていることを確認してください。

Git status を確認できない場合は、完了報告をしないでください。

## Docker Compose 経由のコマンド実行

Codex はホスト OS のリポジトリルートで動かし、言語・ツール固有のコマンドは Docker Compose サービス内で実行してください。

backend コマンドは `backend` サービスの `/home/spring/app` で実行します。

frontend コマンドは `frontend` サービスの `/home/node/app` で、原則 `node` ユーザーとして実行します。

terraform コマンドは `terraform` サービスの `/workspace` で実行します。

品質ゲート command は並列実行しないでください。
format、lint、test、coverage、typecheck、backend check、terraform validate などは順番に実行してください。

## Backend

バックエンドは Java 21、Spring Boot、Gradle、MyBatis、Flyway、Spring Security、JWT、JUnit 5、Mockito、AssertJ、Testcontainers、Spotless、Checkstyle、JaCoCo、SpotBugs を使用します。

バックエンド変更後は、完了前に次を実行してください。

```bash
docker compose exec -w /home/spring/app backend ./gradlew spotlessApply
docker compose exec -w /home/spring/app backend ./gradlew check
```

障害調査中のみ、必要に応じて狭い範囲のコマンドを使用してください。

```bash
docker compose exec -w /home/spring/app backend ./gradlew test
docker compose exec -w /home/spring/app backend ./gradlew spotlessCheck
docker compose exec -w /home/spring/app backend ./gradlew checkstyleMain checkstyleTest
docker compose exec -w /home/spring/app backend ./gradlew spotbugsMain spotbugsTest
docker compose exec -w /home/spring/app backend ./gradlew jacocoTestReport
```

### Backend 設計ルール

- バックエンドは Onion Architecture、DDD、CQRS に従います。
- ドメインロジックは `domain` に配置してください。
- ユースケースの orchestration は `usecase` に配置してください。
- Query interface は `usecase/query` に配置してください。
- Query implementation は `infrastructure/query` に配置してください。
- フレームワーク、DB、storage、外部サービスに関する処理は `presentation` または `infrastructure` に配置してください。
- Controller の public method は、原則として各 class に `handle()` 1 つだけにしてください。
- UseCase の public method は、原則として各 class に `execute()` 1 つだけにしてください。
- Domain model の method が更新後 instance を返す場合、その戻り値を無視しないでください。
- SpotBugs warning は、実際の正しさや設計上の問題を示している場合はコードで修正してください。
- SpotBugs exclusion は、ツールまたは framework 由来の誤検知と確認できた場合だけ使用してください。

## Frontend

フロントエンドは TypeScript、React 18、Vite、React Router v7、MUI、Zustand、TanStack Query、ESLint、Prettier、Vitest、Testing Library を使用します。

フロントエンド変更後は、完了前に次を実行してください。

```bash
docker compose exec -u node -w /home/node/app frontend npm run format
docker compose exec -u node -w /home/node/app frontend npm run lint
docker compose exec -u node -w /home/node/app frontend npm test
docker compose exec -u node -w /home/node/app frontend npm run coverage
```

`npm run coverage` はフロントエンド品質ゲートとして必須です。

`npm run build` で代替しないでください。

ビルド出力、routing、環境変数、デプロイ挙動に影響する変更の場合のみ、production build を実行してください。

```bash
docker compose exec -u node -w /home/node/app frontend npm run build
```

フロントエンドコマンドは、`dist/` や `test-results/` などの ignored artifact を生成する場合があります。

フロントエンドコマンド実行後は、必ずホスト OS のリポジトリルートで最終 diff を確認してください。

```bash
git status --short
git diff --stat
```

### Frontend 設計ルール

- フロントエンドは Bulletproof React を参考にした feature-based structure に従います。
- Feature code は `src/features/{feature-name}` に配置してください。
- Shared UI は `src/components` に配置してください。
- Shared hook は `src/hooks` に配置してください。
- Global state は `src/stores` に配置してください。
- API access と query logic は、既存 feature の規約に合わせてください。
- formatting は Prettier で確認されます。
- linting は ESLint で確認されます。
- test と coverage は Vitest で確認されます。

## Terraform

Terraform 変更後は、完了前に関連する検証を実行してください。

```bash
docker compose exec -w /workspace terraform terraform fmt -check -recursive
docker compose exec -w /workspace terraform terraform validate
docker compose exec -w /workspace terraform tflint --recursive
docker compose exec -w /workspace terraform checkov -d .
```

### Terraform ルール

- 明示的に求められていない production-impacting なインフラ変更をしないでください。
- 明示的に求められていない resource name、state-sensitive identifier、backend setting、provider setting を変更しないでください。
- secret、credential、secret を含む `.tfvars`、state file、生成された plan file を commit しないでください。
- resource replacement のリスクがある場合は報告してください。

## Docker と devcontainer

Docker と devcontainer 関連ファイルは次にあります。

```text
docker
compose.yaml
```

### Docker / devcontainer ルール

- backend、frontend、terraform container は、リポジトリルートを確認できる状態を維持してください。
- 各 container の primary working directory は、それぞれの作業領域に合わせて維持してください。
- 明示的に求められていない container user、working directory、mount path、service name、installed package の変更をしないでください。
- Codex の主 workspace を devcontainer の component-level workspace にしないでください。
- Codex の主 workspace は、ホスト OS のリポジトリルートにしてください。

## CI/CD

GitHub Actions workflow は次にあります。

```text
.github/workflows
```

### CI/CD の事実

- Pull request では check のみ実行します。
- Deploy workflow は、`main` への push 後に該当 CI job が成功した場合、または明示的な manual dispatch の場合に実行します。
- Backend CI は `./gradlew check` を実行します。
- Frontend CI は format、lint、test、coverage を実行します。
- Backend deploy は Docker image を ECR に push し、ECS Fargate に deploy します。
- Frontend deploy は SPA を build し、S3 に sync し、CloudFront cache を invalidate します。

### CI/CD ルール

- 明示的に求められていない AWS role、region、service name、S3 bucket、CloudFront distribution、ECR repository、ECS service、deployment trigger を変更しないでください。
- CI 成功を bypass する形で、deploy workflow を `push` から直接・独立して実行するように変更しないでください。

## Documentation

Documentation は次にあります。

```text
doc
```

### Documentation ルール

- 依頼された変更が、文書化済みの挙動、setup、architecture、command、operation に影響する場合のみ documentation を更新してください。
- 広範囲に documentation を書き換えないでください。
- 必要な箇所だけを対象にしてください。
- コード断片を複製するより、authoritative file への参照を優先してください。

## 完了報告

完了報告は次の形式で行ってください。

```text
Changed files:
- ...

Commands:
- ... -> PASS
- ... -> FAIL

Notes:
- ...
```

変更領域に必要な品質ゲート command は、すべて command result に含めてください。

command が失敗し、その失敗が作業範囲内であれば修正してください。

command が失敗し、その失敗が作業範囲外であれば、実行した command と関連 output を報告してください。

完了報告には、ルートにある `.commit_template` を参照して作成したコミットメッセージも含めてください。

完了報告前に、必ずホスト OS のリポジトリルートで次を確認してください。

```bash
git status --short
git diff --stat
```

最終 diff の確認ができていない場合は、完了報告をしないでください。
