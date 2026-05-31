## プロジェクト概要

KeirekiPro は、エンジニア向け職務経歴書を作成・管理するフルスタック Web アプリケーションです。

## リポジトリ構成

- `backend`: Spring Boot API
- `frontend`: React/Vite SPA
- `terraform`: AWS IaC
- `docker`, `compose.yaml`: Docker Compose 設定
- `.github/workflows`: CI/CD workflow
- `doc`: 設計・運用資料

## 作業前に読むファイル

変更対象に応じて、作業前に次の guide を読んでください。

| 対象 | 読むファイル |
|---|---|
| backend | `.codex/instructions/backend-guide.md` |
| frontend | `.codex/instructions/frontend-guide.md` |
| terraform / CI/CD | `.codex/instructions/infrastructure-guide.md` |
| backend と frontend を同時に変更 | backend-guide と frontend-guide の両方 |
| 影響範囲が曖昧 | 関連しそうな guide をすべて |

## 基本ルール

- 依頼範囲外のファイルを変更しないでください。
- 明示的に求められていない既存コメントを削除しないでください。
- スタイル調整だけを目的にファイル全体を書き換えないでください。
- 明示されていない新しいライブラリ、フレームワーク、ツール、ランタイム依存を追加しないでください。
- コード実装、修正、設計、リファクタリング、テスト追加、エラー調査、セットアップ、設定変更では、Context7 で関連外部技術の現在の公式ドキュメントを確認してください。
- 明示されていない public behavior、API contract、DB schema、インフラ設定、CI/CD、デプロイ挙動を変更しないでください。
- 明示的に求められていない commit、push、merge、deploy、破壊的コマンドを実行しないでください。
- 言語・領域別コマンドは、該当 guide に記載された Docker Compose コマンドで実行してください。
- 品質ゲート command は並列実行しないでください。format、lint、test、coverage、backend check、terraform validate などは順番に実行してください。
- ユーザーへの確認、承認要求、完了報告は日本語で行ってください。

## 文字コード

- リポジトリ内のテキストファイルは UTF-8 として読み書きしてください。
- ソースコード、コメント、テスト名、ドキュメント、完了報告で文字化けした日本語を出力しないでください。
- 文字化けを検知した場合は、そのまま保存せず、正しい日本語に直してから変更してください。
- 文字化けした内容を根拠に作業しないでください。UTF-8 として読み直しても判読できない場合は、推測せず対象ファイル名を報告して停止してください。

## Git

- Git 操作は、ホスト OS のリポジトリルートで実行してください。
- 作業開始前に現在のブランチを確認してください。
- `main` ブランチにいる場合だけ、`.branch_name_template` を読み、作業内容に対応するブランチを作成してください。
- すでに `main` 以外のブランチにいる場合は、新しいブランチを作成せず、そのブランチが作業内容に合っているか確認してください。
- 現在のブランチが作業内容と明らかに合わない場合は、勝手に切り替えずユーザーに確認してください。
- 完了報告前に、意図したファイルだけが変更されていることを確認してください。
- 完了報告前に、ホスト OS のリポジトリルートで `git status --short`、`git diff --stat`、`git diff` を確認してください。
- `git status --short` を確認できない場合は、完了報告をしないでください。

## Documentation

- 文書化済みの挙動、setup、architecture、command、operation に影響する場合だけ `doc` を更新してください。
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

Commit message:
...
```

- 変更領域に必要な品質ゲート command は、すべて command result に含めてください。
- command が失敗し、その失敗が作業範囲内であれば修正してください。
- command が失敗し、その失敗が作業範囲外であれば、実行した command と関連 output を報告してください。
- 完了報告には、ルートにある `.commit_template` を参照して作成したコミットメッセージ案を含めてください。
