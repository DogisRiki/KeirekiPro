# backend ガイド(Spring Boot / オニオン+DDD+CQRS と、置き換え中の Go 版)

backend配下を変更するとき常に適用する。backend には、今の本番で動く Java 版と、Issue #445 で置き換える Go 版がある。
Java 版の決まりはこの節から「完了前コマンド」までに、Go 版の決まりは末尾の「Go 版」の節に書く。
Java 版のアーキテクチャ境界の多くはArchUnit
(`src/test/java/.../unit/architecture/BackendArchitectureTest.java`)が機械強制する。
ここには機械で表現できない配置判断だけを書く。

## 層の責務と配置判断

| 層 | パッケージ | 置くもの / 置かないもの |
|---|---|---|
| domain | `domain.<集約>` | エンティティ・値オブジェクト・ドメインサービス・リポジトリIF。フレームワーク依存を持ち込まない |
| usecase | `usecase.<集約>` | ユースケース1クラス1公開メソッド。DTOはここに置く。書き込み系はdomain経由、参照系(Query)はMyBatis Mapper直読みでよい(CQRS) |
| infrastructure | `infrastructure` | リポジトリ実装・MyBatis Mapper・外部サービス(S3/SES/Redis/SecretsManager)クライアント |
| presentation | `presentation.<集約>` | Controller・リクエスト/レスポンス型。ビジネスロジックを書かない |
| shared | `shared` | 横断関心(例外・ユーティリティ・共通設定)。他層への依存を持たない |

- 迷ったら: ビジネスルールはdomain、手順の編成はusecase、技術詳細はinfrastructure
- 例外は `shared` の共通例外体系を使う。HTTPステータスへの変換はpresentationの責務

## 依存とプラグインのバージョン

バージョンは `gradle/libs.versions.toml`(version catalog)の `[versions]` に集約する。
**`build.gradle` に version を直書きしない。**

- 依存を追加するとき: `[versions]` と `[libraries]` にエントリを足し、`build.gradle` からは
  `libs.<alias>` で参照する
- プラグインを追加するとき: `[versions]` と `[plugins]` に足し、`alias(libs.plugins.<alias>)` で参照する
- `buildscript` ブロックから参照できるのは `[versions]` だけ(`libs.versions.x.get()`)。
  `[libraries]` と `[bundles]` は参照できない
- flyway は `buildscript` の classpath と `plugins` の両方が同じ版を要求するため、
  `[versions] flyway` の1箇所を両方から参照している。片方だけ書き換えない

分離の理由は、`build.gradle` がプログラムであり「バージョンだけの変更」と
「ビルドロジックの変更」を静的解析で区別できないため。TOMLは宣言なので区別でき、
バージョン更新を人間の承認なしに通せるようになる(#182 のやること6で実施)。
直書きすると承認が必要な側に戻る。

## DBスキーマ変更(expand-contract規約)

本番DBは1つだけでロールバックが困難なため、スキーマ変更は必ず後方互換を保つ2段階で行う:

1. **expand**: 追加のみのマイグレーション(列追加はNULL許可 or デフォルト付き)+新旧両対応のコード
2. **contract**: 旧コードの参照が消えた後のリリースで、削除・制約強化のマイグレーション

1つのPRでexpandとcontractを同時に行わない。マイグレーションを含むPRは人間承認ゲート
(CODEOWNERS)にかかり、承認前にローカルDBで適用・巻き戻しが確認される。

## テスト方針

- 配置: `src/test/java/.../unit/{architecture,domain,usecase,infrastructure,presentation,shared}/`(mainと同じ集約構造)
- domain/usecase: Mockitoでリポジトリをモックした純粋ユニットテスト
- infrastructure: Testcontainers(`config/PostgresTestContainerConfig` / `RedisTestContainerConfig`)で実DB/Redisに対して検証
- presentation: MockMvcでリクエスト/レスポンス契約を検証
- テストデータは `helper/`(例: `ResumeObjectBuilder`)を再利用する
- 新規テストは対象コードを一時的に壊して赤くなることを確認してから戻す(assertの実効性確認)。壊す箇所の数と、壊した写しの作り方と流し方は `.kiro/steering/tech.md` の「テストの完全性」に従う
- `@Disabled`・アサーション削除で「見かけの合格」を作らない(escape-hatchチェックが検知)

## 完了前コマンド(この順で直列実行)

```
bash .claude/scripts/parallel/run-check.sh backend ./gradlew spotlessApply
bash .claude/scripts/parallel/run-check.sh backend ./gradlew check
```

`check` = spotlessCheck + test + jacocoTestReport + **jacocoTestCoverageVerification(カバレッジ閾値)** + spotbugsMain/Test。
閾値定義は `gradle/quality.gradle`(CODEOWNERS保護・編集禁止)。

## Go 版

Go 版は、Java 版を置き換えるまで、Java 版と同じ `backend/` に並べて置く。進め方と進み具合は
`.kiro/specs/backend-go-replacement/progress.md` に書く。Java 版のオニオンの層の分け方は写さず、Go で標準的な、機能ごとのパッケージに分ける。

### パッケージの分け方と依存の向き

| パッケージ | 置くもの |
|---|---|
| `cmd/keirekipro` | 起動の入口。設定を読み、部品をつなぎ、HTTP の受け口を開く。業務の処理は書かない |
| `internal/httpapi` | 経路の登録、まとまりの処理の束ね、共通の受け口の処理(`middleware/`)、生きているかの確認 |
| `internal/httpapi/gen` | `api/openapi.yaml` から生成したコード。手で直さない(`make generate` で作り直す) |
| `internal/<機能>` | 機能のまとまりごとの処理(例: `internal/auth`)。まとまりの spec で足す |
| `internal/platform/<部品>` | 機能によらない部品(設定、データベース、表の形の履歴、Redis、AWS、ログ、PDF) |
| `internal/platform/database/sqlcgen` | `db/queries/*.sql` から sqlc で生成したコード。手で直さない |

- 依存の向きは、`cmd/keirekipro` → `internal/httpapi` → 機能のパッケージ → `internal/platform` の一方向とする。`.golangci.yml` の depguard が機械で止める
- 機能のパッケージどうしの依存は、まとまりの spec で depguard の許可に足したものだけを許す。`.golangci.yml` はゲート設定なので、足すときは理由を添えて所有者に提案する
- HTTP の受け口の型は、仕様書(`api/openapi.yaml`)から生成する。受け口を変えるときは、仕様書を直してから `make generate` を動かす
- 表の形は、Java 版を削除するまで Java 版の Flyway が変える。Go 版は、起動のときに履歴を確かめるだけにする

### 品質チェックのコマンド

すべて作業フォルダの最上位から、`run-check.sh` の領域 `backend-go` で動かす。

```
bash .claude/scripts/parallel/run-check.sh backend-go make fmt
bash .claude/scripts/parallel/run-check.sh backend-go make check
```

- `make check` は、書式の検査、生成したコードの食い違いの検査、静的な検査と依存の向きの検査、テスト(`-race`)、カバレッジの下限(`./internal/...` の文の93%)の検査、ビルドを順に動かす。Java 版の `./gradlew check` に当たる
- 作業の途中は、変えたパッケージのテストだけを流す(例: `bash .claude/scripts/parallel/run-check.sh backend-go go test -race -count=1 ./internal/platform/pdf/...`)
- `make vuln` は呼ばれる箇所のある脆弱性を調べる。`make mutation-diff BASE=<git の参照>` は変えた箇所の変異テストで、git の履歴が要るので CI で動く
- 本番のイメージは、`docker build -f docker/backend-go/Dockerfile.prod backend` で組み立てる
- 結合テストは testcontainers-go で Postgres と Redis を動かす。Docker は compose の `dind` を使う
- テストを足したら、Java 版と同じく、対象のコードを壊して赤くなることを確かめてから戻す(`.kiro/steering/tech.md` の「テストの完全性」)
- `t.Skip`・`//nolint`・検査の設定を緩める変更で、見かけの合格を作らない(escape-hatch の検査が見つける)

### Redis と S3 の形を変えるとき(2回の出荷)

Redis のキーの名前と値の形、S3 のオブジェクトのキーの形は、Java 版と Go 版の取り決めである。Go 版は Java 版と同じ形を使う。
Java 版を削除したあとに形を変えるときは、利用者がログアウトされず、途中の手順をまたぐ操作を最後まで終えられるように、変更を2回の出荷に分ける。

1. 1回目の出荷: Go 版は、古い形と新しい形の両方を読み、古い形で書く
2. 古い形で書いた値がすべて期限切れになるまで待つ。ログインを続けるためのトークンの有効な時間が7日なので、7日待つ
3. 2回目の出荷: Go 版は、新しい形で書く

1回の出荷で読み方と書き方を同時に変えない。ECS の入れ替えの途中では、古い版と新しい版の両方が同じ Redis と S3 を読み書きするためである。
