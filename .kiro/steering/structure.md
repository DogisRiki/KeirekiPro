# プロジェクト構成

## 構成の考え方

- **backend**: オニオンアーキテクチャの層をトップレベルパッケージにし、各層の内部を
  集約(`resume` / `user` / `auth` 等)で分ける。ビジネスルールはdomain、
  オーケストレーションはusecase、技術詳細はinfrastructure、HTTP変換はpresentation
- **frontend**: feature-first。featureが縦に完結し、2つ以上のfeatureで必要になったものだけ
  共有層へ昇格させる。featureをまたぐ直接参照はしない
- ルールは文書ではなくテスト・lintで強制する(backend: ArchUnit、frontend: ESLint)。
  新しいコードが既存パターンに従う限り、この文書の更新は不要

## ディレクトリパターン(代表例)

### backend(`backend/src/main/java/com/example/keirekipro/`)

| 場所 | 役割 | 例 |
|---|---|---|
| `domain/model/{集約}/` | 集約ルート・エンティティ・値オブジェクト | `domain/model/resume/Resume.java`, `Period.java` |
| `domain/repository/{集約}/` | リポジトリのインターフェースのみ | `ResumeRepository.java` |
| `domain/service/` `domain/policy/` | ドメインサービス・ポリシー | `ResumeNameDuplicationCheckService.java` |
| `usecase/{集約}/` | 書き込み系ユースケース(1クラス1公開メソッド `execute`) | `CreateResumeUseCase.java` |
| `usecase/{集約}/command/` | ユースケースの入力 | `CreateResumeCommand.java` |
| `usecase/query/{対象}/` | CQRS読み取り系(ドメインを経由しない) | `infrastructure/query/` と対で置く |
| `infrastructure/repository/{集約}/` | MyBatis実装 + 永続化DTO + マッパー | `MyBatisResumeRepository.java`, `ResumeMapper.xml` |
| `infrastructure/shared/` | AWS・Redis・PDF等の技術アダプタ | `aws/s3/`, `pdf/` |
| `presentation/{集約}/controller/` | 1エンドポイント1コントローラ(公開メソッドは `handle` のみ) | `CreateResumeController.java` |
| `presentation/{集約}/dto/` | `…Request` / `…Response` | `CreateCareerRequest.java` |
| `src/main/resources/db/migration/` | Flyway(expand-contract) | `V1__create_tables.sql` |

### frontend(`frontend/src/`)

| 場所 | 役割 | 例 |
|---|---|---|
| `features/{feature}/` | 機能単位の縦割り(`api/ components/ hooks/ stores/ types/ utils/ constants/`) | `features/resume/` |
| `features/{feature}/index.ts` | featureの唯一の公開面(バレル) | 外部はここからのみimportできる |
| `components/{ui,layouts,errors,dnd}/` | feature非依存の共有UI | `ui/Button.tsx` |
| `pages/` | 薄いルーティングページ(featureのContainerを組むだけ) | `ResumeList.tsx` |
| `routes/` `providers/` | ルーター定義とプロバイダ合成 | `AppRouter.tsx`, `AppProvider.tsx` |
| `stores/` | アプリ全域のZustandストア | `userAuthStore.ts` |
| `lib/` | 外部ライブラリの設定 | `protectedApiClient.ts`, `queryConfig.ts` |
| `config/` | パス・環境変数・テーマ・メッセージ | `paths.ts` |
| `test/` | 共有テストユーティリティ | `testUtils.tsx` |
| `_templates/` | Hygenの雛形(`pnpm run new`) | `_templates/feature/new/` |

## 命名規約

### backend

- クラスは役割サフィックス: `〜UseCase`(公開メソッドは `execute` のみ)・
  `〜Controller`(1エンドポイント1クラス、公開メソッドは `handle` のみ)・
  `〜Command`・`〜UseCaseDto`・`〜Request` / `〜Response`
- リポジトリはインターフェース `〜Repository`、実装は技術名を前置(`MyBatis〜Repository`)。
  マッパーは `〜Mapper` + 同名XML。読み取りは `MyBatis〜Query`
- 例外は `BaseException` を頂点に `DomainException` / `UseCaseException`
- テストクラスは `{対象}Test`。**テストメソッドは `test1()` `test2()` … の連番で、
  仕様は日本語の `@DisplayName` に書く**
- マイグレーションは `V{n}__snake_case_description.sql`

### frontend

- コンポーネントはPascalCase `.tsx`。Container/Presentationalを
  サフィックスで分ける(`LoginContainer.tsx` + `LoginForm.tsx`)
- フックは `use〜` camelCase。API関数は動詞始まりcamelCaseで関数名 = ファイル名
  (`createCareer.ts`)。ストアは `〜Store.ts`、ユーティリティは `〜Utils.ts`
- コンポーネントのサブフォルダはkebab-case可(`components/resume-list/`)
- テストは `{対象}.test.ts(x)`。複数ユニットにまたがるものは `{トピック}.integration.test.tsx`
- 共有フォルダとfeatureは必ず `index.ts` のバレルを持つ

## import・依存ルール

### frontend(ESLintで機械強制)

- パスエイリアス `@/` → `src/`(tsconfigで定義、バレル内部でも使う)
- **feature → 他のfeature: 禁止**(エイリアス・相対パスの両方をESLintが遮断)
- **featureへのdeep import: 禁止**。`@/features/{feature}` (index.ts経由)のみ許可
- **共有層(`components/` `config/` `hooks/` `lib/` `providers/` `types/` `utils/`)から
  featureへの参照: 禁止**

### backend(ArchUnitで機械強制)

- domainは外側(usecase / infrastructure / presentation)に依存しない。
  usecaseはpresentation / infrastructureに依存しない。トップレベルパッケージ間の循環禁止
- Redis / AWS SDKへの参照はinfrastructureのみ。本番コードからテストライブラリへの依存禁止
- `System.exit` / `Thread.sleep` / `printStackTrace` は全域で禁止
- ArchUnitテスト自体はゲート設定であり変更しない

## テストの配置

| 領域 | 場所 | 対応関係 |
|---|---|---|
| backend | `src/test/java/.../unit/{層}/...` | `unit/` 配下でmainのパッケージ木を1:1ミラー |
| backendテスト基盤 | `src/test/java/.../config/` `helper/` | Testcontainers設定・テストデータビルダー |
| frontend | 対象の隣の `__tests__/` | コロケーション。サブ構造もミラーする |
| E2E | `frontend/e2e/` | Playwrightスモーク |

テスト戦略の対応: domain/usecase = Mockito単体、infrastructure = Testcontainers結合、
presentation = MockMvc契約テスト。frontendの描画テストは `src/test/` の
`renderWithProviders` を使い、`resetStoresAndMocks` で後始末する。
