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

### テストを書くときの落とし穴(実測で確かめたもの)

- `@/features/resume` の中の部品が使うフックを差し替えるときは、index をまるごと `vi.mock` しない。
  index の中で部品が index を読み込み直すため、部品は元のフックを使い続ける。フックのファイル(`@/features/resume/hooks/useXxx`)を個別に `vi.mock` する
- react-dropzone のドロップは、`fireEvent.drop` に `files` だけでなく `items`(`{ kind: "file", type, getAsFile }`)も渡す。
  happy-dom には本物の DataTransfer があり、`items` が空だとファイルが読まれない
- MUI X の年月ピッカーの月のボタンは、`radio` の名前が英語の正式名("April")になる。年を選んだあとに月を選ぶときは `fireEvent.click` を使う
- MUI Accordion は、見出しに `id` を渡さないと、開いた中身の region に名前が付かない。閉じた中身は隠れるので、開いたものだけが role のクエリで取れる
- RTL の `rerender` は `renderWithProviders` の包みを外して描き直すので、部品が作り直される。状態が持ち越されるかを確かめるときは、状態を持つ親の部品をテストの中に作る
- Lint が拒むもの: `container.querySelector` などで要素をたどること(`testing-library/no-node-access`)、
  `typeof import(...)` の型(`import type * as X` を使う)、`render` の戻り値を `view` と `utils` 以外の名前にすること、`toHaveProperty("checked")`(`toBeChecked` を使う)。
  hidden の file input は `getByDisplayValue("")` で取れる
- 手元の vitest が時間切れや `Worker exited unexpectedly` で落ちたら、まずメモリ不足を疑う(`compose.yaml` の `VITEST_MAX_WORKERS` で並列の数を抑えている)
- frontend のコンテナには `ps` と `kill` のコマンドが無い。プロセスを止めるときは `sh -c 'kill <pid>'` でシェルの組み込みを使う
- 手元の frontend のコンテナで `pnpm exec stryker run` を動かすと、`ps` が無いため `spawn ps ENOENT` で落ち、`frontend/.stryker-tmp/` が残る(Git の無視の対象に入っていない)。
  変異テストで効果を測るときは、ブランチで「Mutation Report」のワークフローを手動で実行する。新しいテストが効くかは、対象のコードを1か所ずつ壊して vitest を回し、`git checkout -- <file>` で戻して確かめる。
  Git Bash の perl で壊すときは、改行を `\x5cn` で置き換える(`s/\\n/\n/` は効かなかった)

## 完了前コマンド(この順で直列実行。coverageは必須でbuildで代替不可)

```
bash .claude/scripts/parallel/run-check.sh frontend pnpm run format
bash .claude/scripts/parallel/run-check.sh frontend pnpm run lint
bash .claude/scripts/parallel/run-check.sh frontend pnpm run typecheck
bash .claude/scripts/parallel/run-check.sh frontend pnpm test
bash .claude/scripts/parallel/run-check.sh frontend pnpm run coverage
```

カバレッジ閾値は `vite.config.ts`(CODEOWNERS保護・編集禁止)に定義。
UI変更時は `/verify-ui` で実画面のスクリーンショット確認まで行う。
E2Eスモーク(`e2e/smoke.spec.ts`)はCIで実行される。
