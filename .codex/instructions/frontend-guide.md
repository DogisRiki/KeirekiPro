## この guide の扱い

- この guide は、ESLint / Prettier で表現しづらい frontend の設計判断とテスト方針を書くものです。
- `eslint.config.js` で担保済みの import 制約、type import、unused vars、formatting は再掲しません。
- 迷った場合は、既存実装と `eslint.config.js` を正としてください。

## 設計判断

- feature 内では、API 呼び出しは `api`、TanStack Query などの取得・更新 hook は `hooks`、UI は `components` に置いてください。
- 画面全体の流れを持つ component と、入力 field / 表示部品の component を分け、既存 feature の粒度に合わせてください。
- feature 固有の型は `types`、純粋な変換・判定は `utils`、固定値は `constants` に置いてください。
- feature 固有 state は feature 内の `stores` を優先し、全体共有が必要なものだけ `src/stores` に置いてください。
- shared component / hook / util に昇格するのは、複数 feature から自然に使われ、feature 固有語彙を含まない場合だけにしてください。

## 状態管理

- API から取得する server state は TanStack Query の query / mutation として扱い、Zustand に複製しないでください。
- 入力途中、開閉、選択中 item など画面内で閉じる state は component local state を優先してください。
- 通知、認証ユーザー、テーマ、横断的なエラー表示など複数画面で共有する client state だけ Zustand store に置いてください。
- store を追加・拡張する前に、既存 store / hook / query cache で表現できないか確認してください。

## UI 実装

- 既存の MUI component と `src/components/ui` の wrapper を優先してください。
- 新しい UI 部品を作る前に、既存の shared UI と feature 内 component を確認してください。
- 画面文言、validation 表示、loading、error、disabled 状態は既存画面の表現に合わせてください。

## テスト

- 既存の `frontend/src/test/testUtils.tsx` を優先して使い、Provider や store reset を各テストで重複実装しないでください。
- component / container のテストは `renderWithProviders` と Testing Library を使い、ユーザー操作は原則 `userEvent` で表現してください。
- DOM 検証は role、label、text などユーザーから見える手掛かりを優先してください。
- API client、router、共通 hook など外部境界は `vi.mock` で置き換え、呼び出し payload と画面/状態変化を検証してください。
- hook の mutation / query は `createQueryWrapper`、`mutateHook`、`waitFor` など既存 helper に合わせてください。
- TanStack Query のテストでは retry を無効化した QueryClient を使い、非同期状態は `waitFor` / `findBy...` で待ってください。
- Zustand store は `resetStoresAndMocks` または既存 reset 手順で各テスト前に初期化してください。
- store test は action 実行後の state を直接検証し、前の更新が保持される/消える境界も見てください。
- utils test は純粋関数として、正常系、空値、境界値、入力を破壊しないことを必要に応じて検証してください。
- mock 検証で曖昧な `expect.anything()` や広すぎる matcher に逃げず、重要な payload、遷移先、通知、store state を具体値で確認してください。

## 完了前の確認

frontend を変更した場合は順番に実行してください。

```bash
docker compose exec -u node -w /home/node/app frontend pnpm run format
docker compose exec -u node -w /home/node/app frontend pnpm run lint
docker compose exec -u node -w /home/node/app frontend pnpm test
docker compose exec -u node -w /home/node/app frontend pnpm run coverage
```

`pnpm run coverage` は frontend 品質ゲートとして必須です。`pnpm run build` で代替しないでください。

ビルド出力、routing、環境変数、デプロイ挙動に影響する変更の場合のみ、production build を実行してください。

```bash
docker compose exec -u node -w /home/node/app frontend pnpm run build
```
