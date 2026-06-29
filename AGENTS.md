## 基本ルール
 
- 依頼された作業に必要な箇所のみ変更し、許可なくリファクタリング・改善・整形・コメントの追加や削除はしない。
- 依頼範囲外の挙動・API・DB スキーマを変えない。
- 監査ゲート（`mvn test`、app5 は checkstyle / spotbugs も）の結果を作業前と同一に保つ。新しい警告・エラーを出さない。
- 全テストを PASS させる必要はない。環境に用意されていない前提条件（特定のデータ・ファイル・外部依存など）に依存して落ちるテストがあるため。作業前から失敗しているテストはそのままでよい。守るべきは、今回の作業で失敗するテストを新たに増やさないこと。
- 既存の警告は消さない。checkstyle / spotbugs の設定は変えない。
- 判断に迷う変更は実施せず、内容を報告する。
- ユーザーへの確認・完了報告は日本語で行う。
## コマンド（Docker 経由・コンテナ名 = アプリ名）
 
- テスト: `docker compose exec -w /workspace/apps/<app> <app> mvn test`
- ビルド: `docker compose exec -w /workspace/apps/<app> <app> mvn clean package -DskipTests`
- 起動: `docker compose exec -w /workspace/apps/<app> <app> mvn spring-boot:run`
- common-app1 取込: `docker compose exec -w /workspace/apps/common-app1 common-app1 mvn clean install -DskipTests`
## Git
 
- Git 操作は、ホスト OS のリポジトリルートで実行してください。
- 完了報告前に、意図したファイルだけが変更されていることを確認してください。
- 完了報告前に、ホスト OS のリポジトリルートで `git status --short` と `git --no-pager diff` を確認してください。
- `git status --short` を確認できない場合は、完了報告をしないでください。
## 完了報告
 
完了報告は次の形式で行ってください。
 
```text
対象:
- <作業した対象（アプリ / 範囲）>
 
実施内容:
- <何を・なぜ行ったか>
 
監査ゲート結果（対象アプリの全ゲートを記載）:
- <ゲート>: <テスト系は 成功/失敗 件数。警告系（checkstyle / spotbugs 等）は 警告数 作業前 → 作業後>
  - <失敗・警告の項目名>（原因: ...）
- 今回の作業で新たに発生した失敗・警告: なし（あれば項目名と原因）
 
依頼範囲外への影響:
- なし（変更があれば内容と理由）
 
Notes:
- <ブロッカー、判断を要する点、申し送り 等>
```
