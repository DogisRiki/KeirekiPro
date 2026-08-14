# KeirekiPro

エンジニア向け職務経歴書の作成・管理を行うフルスタックWebアプリケーション。
開発は、人間がコードをレビューしないことを前提とした自律パイプラインで行う。
実装からマージまでを自律的に進め、品質は自動チェック(テスト・静的解析・カバレッジ閾値・
Codexによるクロスレビュー)で担保する。人間が関与するのは、Issue起票・specの承認・
影響の大きい変更の承認・デプロイ前確認・デプロイ実行のみ。

## リポジトリ構成

| パス | 内容 | スコープ別ガイド |
|---|---|---|
| `backend/` | Spring Boot API(Java 21 / オニオン+DDD+CQRS) | `backend/CLAUDE.md` |
| `frontend/` | React SPA(TS / Vite / bulletproof-react型) | `frontend/CLAUDE.md` |
| `terraform/` | AWS IaC | `terraform/CLAUDE.md` |
| `docker/` + `compose.yaml` | 開発環境(全コマンドはコンテナ内実行) | - |
| `.github/` | CI/CD・ガードレール(CODEOWNERS保護) | - |
| `.kiro/specs/` | spec(仕様書。監査証跡としてコミット) | - |
| `.kiro/steering/` | steering(プロジェクト知識) | - |
| `doc/` | 設計図(クラス図・ER図・インフラ設計等)と人間向けの運用文書 | - |

## 品質ゲート(すべて Docker Compose 経由・この順で直列実行。並列実行禁止)

frontend(`/verify-frontend`):

```
docker compose exec -u node -w /home/node/app frontend pnpm run format
docker compose exec -u node -w /home/node/app frontend pnpm run lint
docker compose exec -u node -w /home/node/app frontend pnpm test
docker compose exec -u node -w /home/node/app frontend pnpm run coverage
```

backend(`/verify-backend`):

```
docker compose exec -w /home/spring/app backend ./gradlew spotlessApply
docker compose exec -w /home/spring/app backend ./gradlew check
```

terraform(`/verify-terraform`):

```
docker compose exec -w /workspace terraform terraform fmt -check -recursive
docker compose exec -w /workspace terraform terraform validate
docker compose exec -w /workspace terraform tflint --recursive
docker compose exec -w /workspace terraform checkov -d .
```

CI環境(GitHub Actions = Docker Compose無し)では `docker compose exec ...` を外し、
`frontend/` `backend/` 各ディレクトリでネイティブにコマンドを実行する。

## 自律動作の境界

- 作業は必ずfeatureブランチで行う。mainブランチではcommit/pushしない(hookでもブロックされる)
- ゲート設定ファイル(`.github/` `.claude/` `eslint.config.js` `vite.config.ts` `backend/gradle/quality.gradle` `backend/config/` ArchUnitテスト `CODEOWNERS`)は変更しない。変更が必要なときは理由を添えて人間に提案する
- 人間の承認が必要な変更: 依存パッケージの追加・backendのビルド定義(`*.gradle` `*.gradle.kts` `*.versions.toml` `gradle-wrapper.properties`)の変更・DBスキーマ変更(マイグレーション)・ゲート設定の変更・リポジトリ外部へのデータ送信。これらを含むPRは承認まで自動マージされない(dependency-gate / CODEOWNERSが機械強制)
- テストのskip化・アサーション削除・カバレッジ/lint除外の追加で「見かけの合格」を作らない(escape-hatchチェックが機械検知)
- 200行(コード差分)を超える変更はspec駆動(Lane A)で行い、PR本文に `Spec: .kiro/specs/<feature>` を記載する
- 本番デプロイ(release.yaml)・`terraform apply` は起動しない(人間の専権)
- 同一の失敗が3回続いたら停止して人間に報告する(修正の無限ループを作らない)
- 依頼範囲外の問題を見つけたら報告のみ行う(勝手に直さない)
- `/loop` などの定期実行ループの中からはcommit/pushしない(出荷は明示的な `/ship` でのみ行う)

## Git規約

- 前提: ホストOSに **Git for Windows(Git Bash同梱)が必須**(`.claude/hooks/` のフックはGit Bashで実行される。シェルスクリプトは `.gitattributes` でLF強制)
- Git操作はホストOSのリポジトリルートで実行する(devcontainer内Gitは無効)
- ブランチ名は `.branch_name_template`、コミットメッセージは `.commit_template` に従う
- PR本文には必ず `Refs: #<Issue番号>` を含める。テストのアサーションを意図的に変更した場合は
  `Test-Change-Justification: <理由>` を記載する
- PR本文には `Closes #<Issue番号>` も併記し、マージ時にIssueが自動で閉じるようにする。
  ただしIssueの完了条件にマージ後の人間の作業(設定ファイルの差し替え・リポジトリ設定の変更・
  本番環境での実行・ローカルでの画面確認など)が含まれる場合は書かない。その場合は、
  作業の完了を確認した時点でエージェントが `gh issue close` する。人間はIssueを閉じない
- `Refs: #<Issue番号>` は `Closes` と併記しても消さない。codex-reviewがこの行からIssue本文を
  取得してspec適合の判定基準にしている
- push先はfeatureブランチのみ。マージはauto-merge(ゲート全通過で自動)に任せ、`gh pr merge --auto --squash` を予約する
- 出荷手順(verify→commit→push→PR→auto-merge予約)は `/ship` に従う

## 作業規約

- 依頼範囲外のファイルを変更しない。スタイル調整目的の全面書き換えをしない
- `.github/workflows/` のワークフローを追加・変更・削除したPRでは、READMEのワークフロー一覧表とMermaid図も更新する
- 外部技術の仕様は Context7 MCP または公式ドキュメントで現行版を確認してから使う
- 外部ツールの仕様やエラーは、記憶で判断せず公式ドキュメントとissueを調査してから実装・提案する(根拠URLを添える)
- ユーザーへの報告・PR本文・コミットメッセージは日本語(コミットprefix等の規約語は除く)
- テキストファイルはUTF-8。文字化けを検知したら保存せず停止して報告する(hookでもブロックされる)
- Think in English, generate responses in Japanese. `.kiro/` 配下に生成するMarkdown(requirements.md,
  design.md, tasks.md, research.md 等)は spec.json.language の設定言語(日本語)で書く

## spec駆動開発(cc-sdd / Kiro-style)

新機能・複数層にまたがる変更(Lane A)はspec駆動で行う。小修正(Lane B)にspecは不要。

### パスと役割分担

- Steering: `.kiro/steering/`(プロジェクト全体の知識。`product.md` `tech.md` `structure.md`。
  作業規約はこのCLAUDE.mdとスコープ別CLAUDE.mdに書き、steeringと二重記述しない)
- Specs: `.kiro/specs/`(機能単位の要件・設計・タスク。進捗は `/kiro-spec-status {feature}`)

### ワークフロー

- Discovery: `/kiro-discovery "アイデア"` — 1spec/複数spec/spec不要を判定し brief.md を作成
- Phase 1(仕様化):
  - `/kiro-spec-init "説明"` → `/kiro-spec-requirements {feature}` → `/kiro-spec-design {feature}` → `/kiro-spec-tasks {feature}`
  - 既存コードとの整合確認: `/kiro-validate-gap {feature}`(任意)、設計レビュー: `/kiro-validate-design {feature}`(任意)
- Phase 2(実装): `/kiro-impl {feature}`(タスクごとにsubagent実装+独立レビュー+最終検証)
  - 再検証のみ: `/kiro-validate-impl {feature}`
- 実装完了後の出荷は `/ship`(PR本文に `Spec: .kiro/specs/{feature}` と `Refs: #<Issue番号>` を記載)

### ルール

- 3段階承認: Requirements → Design → Tasks の各段階で人間の承認を得る(`-y` は意図的なfast-trackのみ)
- 各タスクの完了条件に該当verify Skillの実行を含める(タスクテンプレートに定義済み)
- Skills は `.claude/skills/kiro-*/SKILL.md`。適用可能性が1%でもあればスキルを起動する
- steeringは常に最新に保つ(`/kiro-steering` で更新)
