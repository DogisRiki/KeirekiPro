# Review instructions

`/code-review`(ローカル一次レビュー)のカスタマイズ。日本語で報告すること。

## Important(重大)と判定するもの

- ロジックバグ・データ破壊・リグレッション
- セキュリティ問題(認証・認可の欠落、シークレット露出、インジェクション)
- アーキテクチャ境界違反(オニオン層の逆流依存、feature間import。ArchUnit/ESLintで検出できない設計逸脱を含む)
- DBスキーマの後方非互換変更(expand-contract規約違反。`backend/CLAUDE.md` 参照)
- ゴールハックの兆候(テストskip・アサーション削除・カバレッジ/lint除外の追加・閾値緩和)
- spec(`.kiro/specs/`)や参照Issueとの明確な不一致

## Nit(軽微)の扱い

- スタイル・命名・コメントの改善提案はNitとし、1レビューあたり最大5件まで
- Prettier/Spotless/Checkstyleが強制済みの整形観点は報告しない

## レビュー対象外

- 生成物: `frontend/dist/` `frontend/coverage/` `frontend/playwright-report/` `backend/build/`
- 自動生成されたロックファイル: `frontend/pnpm-lock.yaml`
- ドキュメントのみの変更におけるコード観点の指摘
