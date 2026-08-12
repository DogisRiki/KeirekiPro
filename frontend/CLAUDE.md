# frontend ガイド(React / TypeScript / bulletproof-react型)

frontend配下を変更するとき常に適用する。ディレクトリ間の依存境界はESLint
(`eslint.config.js` の `no-restricted-imports` / `import/no-restricted-paths`)が機械強制する。
ここには機械で表現できない配置判断だけを書く。

## 配置判断

| パス | 置くもの |
|---|---|
| `src/features/<機能>/` | 機能固有の api / components / hooks / stores / types。**feature間の相互importは禁止**(ESLintが検知)。他featureから使いたくなったら共通層へ昇格する |
| `src/components/` | 機能に依存しない共通UI(layouts / ui / errors)。features/ を参照できない |
| `src/pages/` | ルーティング単位の薄いページ。featureのContainerを組み合わせるだけにする |
| `src/hooks/` `src/utils/` `src/lib/` | 機能非依存の共通ロジック。lib/ はaxiosクライアント等の外部ライブラリ設定 |
| `src/stores/` | アプリ全域のZustandストア(認証・テーマ等) |
| `src/config/` | パス定義(`paths.ts`)・環境設定 |

- featureの公開はそのfeatureの `index.ts` 経由のみ(深いimportはESLintが検知)
- 新しいfeature/構造のひな形はHygenで生成する: `pnpm run new`(feature)/ `pnpm run init`(構造)

## 状態管理

- **server state**(APIから取るもの)= TanStack Query。手動でstoreにコピーしない
- **client state**(UIの状態・認証フラグ等)= Zustand
- フォーム状態はコンポーネントローカルで持つ

## テスト方針

- コロケーション: 対象の隣の `__tests__/` または同階層に `*.test.ts(x)`(Vitest + Testing Library)
- レンダリングを伴うテストは `src/test/` の `renderWithProviders` / `createQueryWrapper` を使う
- モックとストアの後始末は `resetStoresAndMocks` を使う
- アサーション無しのテストはESLint(`sonarjs/assertions-in-tests`)が拒否する
- 新規テストは対象コードを一時的に壊して赤くなることを確認してから戻す
- `.skip`/`.only`/`@ts-ignore`/インライン`eslint-disable` の追加は禁止(escape-hatchチェックが検知)

## 完了前コマンド(この順で直列実行。coverageは必須でbuildで代替不可)

```
docker compose exec -u node -w /home/node/app frontend pnpm run format
docker compose exec -u node -w /home/node/app frontend pnpm run lint
docker compose exec -u node -w /home/node/app frontend pnpm test
docker compose exec -u node -w /home/node/app frontend pnpm run coverage
```

カバレッジ閾値は `vite.config.ts`(CODEOWNERS保護・編集禁止)に定義。
UI変更時は `/verify-ui` で実画面のスクリーンショット確認まで行う。
E2Eスモーク(`e2e/smoke.spec.ts`)はCIで実行される。
