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
| backend | Java 21 / Spring Boot 4.1系 / Gradle(wrapper) |
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
- **dnd-kit**(並べ替え)、**dayjs**

## テスト

| 対象 | ツール | 方針 |
|---|---|---|
| backend単体 | JUnit 6 + Mockito + AssertJ | domain/usecaseは純粋な単体テスト |
| backend結合 | Testcontainers(postgres / localstack)+ dind | infrastructureは実物のPostgres/Redisで検証 |
| backendアーキテクチャ | ArchUnit | 層依存・命名・配置ルールを `check` で強制 |
| frontend単体 | Vitest + Testing Library + happy-dom | `__tests__/` にコロケーション |
| E2E | Playwright | ビルド成果物を `vite preview` で配信。バックエンド無しで検証できる範囲に限定 |
| ミューテーション | PIT(backend)/ Stryker(frontend) | 週次レポートのみ。ゲートには入れない |

テストの完全性: 新規テストは対象コードを一時的に壊して赤くなることを確認してから戻す。
Claude は、壊して確かめるときに、次のとおりにする。

- Claude は、新しいテスト1件につき、テストの対象のコードを1か所だけ壊す。Claude は、tasks.md や Issue が求めていないテストを足して、壊す箇所を増やさない
- Claude は、壊すたびに、そのテストだけを名前で選んで流す。テストのファイルの全部の場合は流さない
- テストのファイルが場合を名前で選んで流せないときは、Claude は、壊して確かめる前に、場合の名前で選んで流せる仕組みをそのファイルに足す(書き方は `.kiro/settings/rules/spec-writing.md` の「シェルのテストは場合の名前で選んで流せる形にする」)。選べないまま流すと、Claude は1件を確かめるたびに全部の場合を流すことになる。Issue #465 では、147件で1回に約5分半かかる全部の場合を、足したテストの確かめのたびに流した
- Claude は、壊したコードを、壊し方ごとに作業フォルダの外の別の写しに作り、作業フォルダの実装のファイルを書き換えない。止めたつもりの実行が裏で残ると、作業フォルダの実装を書き換え続けるためである(Issue #465 で起きた)
  - シェルのスクリプト: Claude は、スクリプトとそのテストのフォルダを scratchpad に写し、写しを壊して、写しのテストを `perl .claude/scripts/parallel/run-copies.pl` で流す。このスクリプトは、写しごとに時間の上限(既定300秒)を付け、標準入力を空にし、上限に達した写しを子と孫のプロセスまで止める。Issue #465 では、標準入力を待つコマンドを足した写しが止まり、Claude は約2時間待ち続けた。使い方はスクリプトの先頭に書いてある
  - コンテナで流すテスト(backend と frontend): `run-check.sh` は git の作業フォルダの最上位を読み込むので、Claude は scratchpad に `git worktree add --detach <写し> HEAD` で写しを作り、まだコミットしていない変更を写しに写してから壊し、写しの最上位で `run-check.sh` を呼ぶ。終わったら `git worktree remove --force <写し>` で消す
- Claude は、写しごとの実行を同時に流す。同時に流す数は10までにする。31本を同時に流したときは PC が重くなり、時間切れを確かめる別のテストまで落ちた。コンテナで流すテストは、`run-check.sh` が同時に動かす数を `keirekipro.parallelSlots` までに抑える
- Claude は、`run-copies.pl` を前面の Bash で、Bash の `timeout` を 600000 にして流す。写しは全部が同時に流れるので、`run-copies.pl` は写しごとの上限と止めるまでの数秒で必ず終わり、Claude は結果を受け取るまで止まらずに済む
- Claude は、そのほかの2分を超えそうな実行を Bash の `run_in_background` で流す。前面の Bash は10分で打ち切られ、それまでの時間が無駄になるためである。前面で流すテストには、Bash の `timeout` を付ける
- Claude は、裏の実行の終わりを、期限の無いループ(`until ...; do sleep ...; done`)で待たない。裏の実行は終わったときにしか Claude を起こさないので、止まった実行を期限の無いループで待つと、Claude は所有者が声をかけるまで待ち続ける。待つときは、`timeout <秒>` か Monitor の `timeout_ms` で期限を付け、期限に達したら止まったものとして調べる
- Claude は、裏の実行の進み具合を、終わった数ではなく、まだ動いているプロセスがいつ始まったか(`ps` の開始の時刻)で見る。Issue #465 では、終わった数だけを見て、2時間前から止まっている写しに気づかなかった
- Claude は、流す前に作業フォルダの実装のファイルの中身を控え、流したあとに控えと同じかを比べる。裏で流した実行を止めたときは、本当に止まったことを `ps` で確かめてから進む。Windows では、止めたつもりの実行の子のプロセスが残ることがあるためである

`@Disabled` / `.skip` / `.only` / `@ts-ignore` / インラインlint無効化は禁止(escape-hatchチェックが検知)。

## 品質基準

- カバレッジ閾値は「一度上げたら下げない」ラチェット運用。現在値は
  `backend/gradle/quality.gradle`(JaCoCo)と `frontend/vite.config.ts`(v8)が正
- backend: Spotless(フォーマット)・Checkstyle・SpotBugs・PMDを `check` で一括実行
- frontend: ESLint(flat config)+ Prettier。アサーションの無いテストはlintで拒否される

## 開発環境

すべてDocker Compose(`compose.yaml`)のコンテナ内で実行する。
サービス: `backend` / `frontend` / `terraform` / `db`(PostgreSQL)/ `redis` /
`localstack` / `dind`(Testcontainers用のDockerデーモン)。起動は `./start-dev.sh`。

品質ゲートのコマンドは `/verify-frontend` `/verify-backend` `/verify-terraform` の
各スキルの「Steps」が正。

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
   全PRが赤くなるため、明示的な版で固定する(tflint は digest も)。更新は Dependabot の
   PRで届き(checkov は `docker/terraform/requirements.txt` の pip レーン、tflint は docker
   レーンのまとめPRから外した個別のPR)、増えた指摘はそのPRの terraform-static が赤で示す。
   tflint は ghcr.io にあり Dependabot の既定の待ち期間(公開から3日)が効かないため、
   GitHub のリリースの公開から72時間経つまで自動マージを予約しない(`dependabot-auto-merge.yaml`)
