# backend ガイド(Spring Boot / オニオン+DDD+CQRS)

backend配下を変更するとき常に適用する。アーキテクチャ境界の多くはArchUnit
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

例外が1つある。`ext['junit-jupiter.version']` は依存宣言ではなく Spring Boot の
管理バージョンを上書きするプロパティで、`build.gradle` に残している。catalogへ移しても
Dependabotの更新対象にならないため。この行はSpring Bootを上げたときに不要になる想定で、
解除手順は当該行のコメントに書いてある。

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
- 新規テストは対象コードを一時的に壊して赤くなることを確認してから戻す(assertの実効性確認)
- `@Disabled`・アサーション削除で「見かけの合格」を作らない(escape-hatchチェックが検知)
- Spring Bootのバージョンを上げるときは、`build.gradle` の `ext['junit-jupiter.version']` が
  まだ必要かを確認する(判定方法はその行のコメントに記載)

## 完了前コマンド(この順で直列実行)

```
docker compose exec -w /home/spring/app backend ./gradlew spotlessApply
docker compose exec -w /home/spring/app backend ./gradlew check
```

`check` = spotlessCheck + test + jacocoTestReport + **jacocoTestCoverageVerification(カバレッジ閾値)** + spotbugsMain/Test。
閾値定義は `gradle/quality.gradle`(CODEOWNERS保護・編集禁止)。
