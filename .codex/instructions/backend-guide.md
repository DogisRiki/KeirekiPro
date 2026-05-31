## この guide の扱い

- この guide は、ArchUnit で表現しづらい backend の設計判断とテスト方針を書くものです。
- `BackendArchitectureTest` で担保済みの package 依存、配置、命名、公開メソッド数などは再掲しません。
- 迷った場合は、既存実装と `BackendArchitectureTest` を正としてください。

## 責務判断

- domain には、業務ルール、不変条件、状態遷移、値の妥当性を置いてください。
- usecase には、入力 command や認証済み userId を受け取り、domain と port/query を組み合わせてユースケースを完了させる処理を置いてください。
- presentation には、HTTP、認証コンテキスト、request/response 変換、cookie/header/status など入出力境界を置いてください。
- infrastructure には、永続化、外部サービス、PDF/Markdown 生成、通知、storage、secret、query 実装など技術詳細を置いてください。
- shared には、本当に複数領域にまたがる小さな共通部品だけを置いてください。機能固有判断を入れないでください。
- ドメインモデルの操作が更新後インスタンスを返す場合、戻り値を必ず次の処理、永続化、返却に使ってください。

## 例外設計

- アプリケーション例外は、その例外を定義している層の失敗を表す場合だけ送出してください。
- 同じ層で共通処理したい失敗は、その層の基底アプリケーション例外を継承した専用例外として表現してください。
- 専用例外は、HTTP status、エラーレスポンス、ログ、メトリクスなどで共通処理を分けたい場合に作ってください。
- 呼び出し元や横断処理が失敗の種類を型で判別する必要がある場合に作ってください。
- メッセージを分けたいだけなら、既存の層基底例外を使い、例外クラスを増やさないでください。
- 横断処理で失敗の種類を判定する場合は、例外型や明示的な属性で判定し、メッセージ文字列に依存しないでください。
- 横断的な処理には、特定機能・特定リソースに依存した判定や文言を入れないでください。

## SpotBugs

- SpotBugs warning が実際の正しさや設計上の問題を示している場合は、コードで修正してください。
- SpotBugs exclusion は、ツールまたは framework 由来の誤検知と確認できた場合だけ使用してください。

## テスト

- backend test は `backend/src/test/java/com/example/keirekipro/unit/...` 配下で、対象層に合わせた package に置いてください。
- テストの仕様は `@DisplayName` に日本語で書き、既存テストと同じ粒度のシナリオ名にしてください。
- 既存の test helper がある場合は再利用し、巨大な fixture を無目的に複製しないでください。
- mock 検証で `any()` だけに逃げず、意味のある引数は `eq(...)`、`ArgumentCaptor`、具体値、または状態検証で確認してください。
- `any()` は、対象テストの主眼ではない依存や、値の詳細が別 assertion で検証済みの場合に限って使ってください。
- 不正 request や途中失敗の検証では、`never()` を使って後続処理が呼ばれないことを確認してください。

### domain test

- 値オブジェクトは、有効値、必須、桁数、形式、境界値、複数エラー収集を検証してください。
- `ErrorCollector` を使う domain では、生成結果だけでなく、追加される field/message と不要な error が追加されないことを検証してください。
- Entity / aggregate は、生成、再構築、追加、更新、削除、境界条件、`DomainException` を検証してください。
- 更新メソッドが更新後 instance を返す場合は、返却 instance の状態を検証してください。
- collection の更新は、件数、対象 ID、含まれる/含まれない要素を検証し、不要に順序へ依存しないでください。

### usecase test

- UseCase test は原則 `MockitoExtension` で repository/query/store/gateway/policy など外部境界を mock してください。
- 正常系では、依存先呼び出し、保存対象、返却 DTO が保存後 state と一致することを検証してください。
- 保存や外部境界への入力は `ArgumentCaptor` で取り、domain state / DTO field を確認してください。
- リソース未存在、所有者不一致、上限、認証失敗などの主要な失敗分岐を検証してください。
- 途中で失敗する場合は、後続の repository/save/external call が実行されないことを検証してください。
- 認可上「存在しない」と扱うケースは、実装と同じ例外・メッセージで検証してください。

### presentation test

- Controller test は原則 `@WebMvcTest` と `MockMvc` で HTTP 境界を検証してください。
- 正常系では status、主要 response JSON、認証ユーザー取得、UseCase へ渡す command を検証してください。
- request validation は field ごとの message を検証し、不正 request では UseCase が呼ばれないことを検証してください。
- 例外ハンドラは HTTP status、response body、field errors、ログ、secret masking など横断仕様を検証してください。

### infrastructure test

- mapper/repository/query/store/exporter/外部 adapter は、外部技術そのものではなく境界変換と副作用を検証してください。
- MyBatis mapper は `@MybatisTest` と Testcontainers 設定を使い、SQL の抽出結果、並び順、主要 field mapping を検証してください。
- repository/query 実装は、mapper 呼び出し、DTO/domain 変換、親子要素、null 許容値、境界値を検証してください。
- Redis store など状態を持つ adapter は、発行、検索、削除、存在しない値、他ユーザー/他キーへの影響を検証してください。
- AWS/S3 など外部 SDK adapter は SDK client を mock し、request の bucket/key/contentType/TTL などを検証してください。

## 完了前の確認

backend を変更した場合は順番に実行してください。

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
