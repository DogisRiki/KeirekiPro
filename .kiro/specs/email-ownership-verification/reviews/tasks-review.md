# tasks のレビュー

## サイクル1 往復1(2026-10-20)

### 審査の範囲

範囲: 全体

### 申告

申告に当たる決めごとは無い。tasks.md は、タスクから外した作業も、`- [ ]*` の印のテストも持たない。タスク 7.1 と 8.3 に `_要件:_` の行を書かないことは、本文に理由が書いてあり、外れても手戻りは無い。画面の実物の確認(`/verify-ui`)をどのタスクにも入れていないことは、本文で決めたことではないので、指摘 T1-1-4 で扱う。

### 指摘

| ID | レベル | 該当箇所 | 内容 | 直し方の案 |
|---|---|---|---|---|
| T1-1-1 | 中 | tasks.md タスク 8.2 の「完了の確かめ方」、完了条件4 | 「足した Playwright のテストが通る」を、作業の手元で確かめる手段が無い。`/verify-frontend` の手順(format・lint・typecheck・test・coverage)は Playwright を動かさない。`run-check.sh` が使う frontend のコンテナ(`docker/frontend/Dockerfile` の `node:24.22.0-bookworm-slim`)には Playwright のブラウザが入っておらず、コンテナは1回ごとに捨てられる(`docker compose run --rm`)。Playwright を動かすのは CI の `e2e-smoke`(`ci.yaml` の `pnpm exec playwright install --with-deps chromium` → `pnpm run build` → `pnpm exec playwright test`)だけである。そのため、`/kiro-impl` の確認役はこのタスクの完了を確かめられず、完了条件4(コードを一時的に壊してテストが失敗することを確かめる)も手元では行えない。実装の途中で止まり、tasks に戻って確かめ方を決め直すことになる | タスク 8.2 の「完了の確かめ方」を、CI の `e2e-smoke` で足したテストが通ることに置き換え、手元では `pnpm run typecheck` と `pnpm run lint`(`eslint-plugin-playwright`)で書き方だけを確かめると書く。完了条件4は、手元でブラウザを動かせないことを理由に、CI で一度だけ壊した版を流して失敗を確かめるか、確かめないかを決めて理由を添える。手元で動かす方法を足すなら、その手順(ブラウザの入れ方を含む)を書く |
| T1-1-2 | 低 | tasks.md タスク 1.2、3.1、3.3、4.1 の「受入基準とテストの対応」 | 完了条件1は、タスクの `_要件:_` に挙げた受入基準ごとに、確かめるテストを「受入基準とテストの対応」の行に書くと決めている。次の受入基準は `_要件:_` にあるが、対応の行に書かれていない。タスク 1.2 の要件7の受入基準3(`createWithVerifiedEmail`)、タスク 3.1 の要件2の受入基準2・3(「jti が最新でないリンクは EXPIRED」は受入基準4として書かれている)、タスク 3.3 の要件2の受入基準5・要件3の受入基準4・要件4の受入基準2、タスク 4.1 の要件1の受入基準6。どれも別のタスクのテストで確かめられているので、受入基準がテストの無いまま残ることは無い | 各タスクの対応の行に該当するテストの名前を足すか、そのタスクで確かめない受入基準を `_要件:_` から外す |
| T1-1-3 | 低 | tasks.md タスク 6.1・6.2 の「完了の確かめ方」 | 「ログインしていない要求で、3つの API が 401 にならない」「ログインしていない要求に 401 を返す」を確かめるテストが決まっていない。今の controller のテストは `@WebMvcTest` と `@AutoConfigureMockMvc(addFilters = false)` で Spring Security のフィルタを外し、`CurrentUserFacade` をモックにしている(例 `UserRegistrationControllerTest`、`GetUserInfoControllerTest`)。この形では、`SecurityConfig` の `/api/auth/**` の `permitAll` と `anyRequest().authenticated()` を通らないので、401 かどうかを確かめられない。リポジトリには、フィルタを通して 401 を確かめるテストが無い | 401 の確かめを、全体を組み上げるテスト(タスク 8.1 の結合テストに `@AutoConfigureMockMvc` を付けて、ログインせずに4つの API を呼ぶ)で行うと書くか、`SecurityConfig` を変えないことを理由にこの確かめを外す |
| T1-1-4 | 低 | tasks.md タスク 7.2、7.3、7.5、7.6、7.7 | `frontend/CLAUDE.md` は「UI変更時は `/verify-ui` で実画面のスクリーンショット確認まで行う」と決めているが、画面を変えるどのタスクにも `/verify-ui` が無い。`/kiro-impl` は `/verify-ui` を自分では動かさない。確認のリンクの画面、ログインの画面の案内、ユーザー設定の画面の確認待ちの表示は、Vitest と、API の応答を作った Playwright のテストでしか確かめられない | 画面を変えるタスクの「完了の確かめ方」に `/verify-ui` での確認を足すか、足さない理由を書く。V7 のあとは今あるアカウントがすべて確認前になるので、ログインの画面の 409 の案内とユーザー設定の画面の確認待ちの表示は、開発環境のアカウントで見られる |
| T1-1-5 | 低 | tasks.md タスク 4.1、4.7、7.4、7.5、7.6 と「実装のメモ」の2つ目 | 新しい動きに合わせて、既存のテストのアサーションを変えるか消すことが避けられないタスクがあるが、どのテストを変えるかが書かれていない。たとえば、`UserRegistrationControllerTest` は今 `status().isCreated()` を確かめ、`useUserRegister.test.ts` は今の完了の文を確かめている。タスク 4.7 で `User.setEmail` を消すと、`UserTest` の `setEmail` のテストも消える。タスク 7.5 は `userSettingRules` の引数を変える。「実装のメモ」は「アサーションを消さず、変えない」と書いており、適用の範囲は確認前のアカウントを断る条件で失敗するときに限られるが、確認役がこれらの変更を見かけの合格と読み違えるおそれがある。また、escape-hatch の検査は、アサーションの変更に PR 本文の `Test-Change-Justification:` を求める | 各タスクに、動きが変わるために変える既存のテストの名前を書き、`/ship` で PR 本文に `Test-Change-Justification:` を書くための理由として使えるようにする |
| T1-1-6 | 低 | tasks.md タスク 6.2 の `_対象の部品:_` | `_対象の部品:_` が、タスク 4.5 で作るユースケースの部品 `SendAccountEmailVerificationUseCase` を指している。このタスクで作るのは `SendAccountEmailVerificationController` で、確認役は変えたファイルを `_対象の部品:_` と突き合わせる | `_対象の部品:_` を、このタスクで作る controller が分かる書き方にするか、範囲が明らかなので行を外す |

### 前の段階への指摘

| ID | 対象 | 該当箇所 | 内容 |
|---|---|---|---|
| T1-1-7 | design(低) | 「確認のリンクの結果の決め方」の図の下の2つ目の箇条 | 「同じリンクが同時に2回押されたときは、あとの要求が2回目の判定で `ALREADY_VERIFIED` になる」は、先の要求のトランザクションが確定したあとにしか成り立たない。先の要求が最新の `jti` を消し、まだ保存を確定していない間にあとの要求が判定をやり直すと、`jti` は最新でなく、`REGISTRATION` では確認前の登録が残っているので `EXPIRED` になる(`ACCOUNT_EMAIL` でもアカウントの `email` がトークンの `email` と同じなので `EXPIRED`)。あとの画面には、確認が済んだのに送り直すボタンが出る。動きの誤りは小さいが、design の記述が実際の動きと違う。戻る先は design |
| T1-1-8 | design(低) | 「EmailVerificationStatus、userSettingRules、userSettingMessages、SettingUserContainer、ChangePasswordContainer」の節 | `isTwoFactorDisabled` が true のとき、`SettingUserForm` は2段階認証のスイッチを無効にする(`disabled={twoFactorDisabled}`)。前からあるアカウントで2段階認証が有効なまま確認前になった利用者は、Google か GitHub でログインしても、画面から2段階認証を無効にできない。backend の `changeTwoFactorAuthEnabled` は無効にする条件を変えないので、「画面の判断と backend の判断は食い違わない」という記述は、無効にする操作では成り立たない。要件10の受入基準2は有効にできるかの判断だけを決めているので、要件には反しない。戻る先は design |

- 往復: 1回目 / 高0 中1 低7

## サイクル1 往復2(2026-10-20)

### 審査の範囲

範囲: 差分

- tasks.md タスク 8.2 の「完了の確かめ方」と、足した「新しく書いたテストが、テストの対象を一時的に壊すと失敗することの確かめ方」の行: T1-1-1 への直しで中身が変わった。直しが `/kiro-impl` → `/kiro-validate-impl` → `/ship` の順で実際に行えるかを見るため、`.claude/skills/kiro-impl/SKILL.md`(タスクに `[x]` を付ける時点と Step 4)、`.claude/skills/kiro-validate-impl/SKILL.md`(Success Criteria)、`.claude/skills/ship/SKILL.md`(手順1と「verify全PASSまでpushしない」)、`.claude/skills/verify-frontend/SKILL.md`、`frontend/package.json` の `lint` と `typecheck`、`frontend/tsconfig*.json` の `include`、`frontend/eslint.config.js`、`frontend/playwright.config.ts`、`frontend/e2e/smoke.spec.ts`、`.github/workflows/ci.yaml` の `e2e-smoke`、`.github/audit/required-checks.json` を読んだ
- tasks.md 「完了条件(全タスク共通)」の2と4: タスク 8.2 の直しが、この2つを置き換えているため
- tasks.md タスク 7.2、7.3、7.7 の Vitest のテスト: タスク 8.2 で一時的に変える「テストが確かめる文」は、これらのタスクの Vitest のテストも確かめる画面の文であるため
- design.md の「テストの方針」の Playwright の箇条(681行目): タスク 8.2 の範囲の元であるため。直しと食い違いは無い
- tasks.md タスク 1.2、1.3、3.3、8.1 の文の直し: 言い換えが design の「User」「MyBatisUserRepository と UserMapper」「VerifyEmailUseCase」の節と、`UserMapper.xml` の `upsertUser` の実在と合うかを見た。食い違いは無い
- tasks.md タスク 2.6、3.4、4.1、4.3、4.4、4.7、5.2、7.2、7.3、7.5、8.1 の「受入基準とテストの対応」の箇条への分け直し: 分けたあとも、受入基準とテストの組が分ける前と同じかを見た。タスク 3.4 だけが崩れている(T1-2-2)

### 申告

申告に当たる決めごとは無い。タスク 8.2 で完了条件4の確かめを CI に移したことは、T1-1-1 への直しであり、行えるかどうかは指摘 T1-2-1 で扱う。

### 指摘

| ID | レベル | 該当箇所 | 内容 | 直し方の案 |
|---|---|---|---|---|
| T1-2-1 | 中 | tasks.md タスク 8.2 の「完了の確かめ方」と「新しく書いたテストが、テストの対象を一時的に壊すと失敗することの確かめ方」 | T1-1-1 への直しは、次の3つの点で、決めた手順のとおりに行えない。(1) このタスクは「`/ship` で PR を作ったあと」「`e2e-smoke` が通ったときに完了とする」と書いたが、`/kiro-impl` は、確認役の合格と `kiro-verify-completion` のあとにタスクへ `[x]` を付け、Step 4 で「After all tasks complete」に `/kiro-validate-impl` を動かす。`/kiro-validate-impl` は Success Criteria に「All tasks marked `[x]` in tasks.md」を置く。`/ship` はそのあとに動く。そのため、このタスクは `/kiro-impl` の中で完了にできず、完了の前に `[x]` を付けるか、`/kiro-validate-impl` に進めないかのどちらかになる。(2) 手元の確かめにした「`/verify-frontend` の型の検査と lint」は、足すテストを検査しない。`lint` は `eslint ./src`、`typecheck` は `tsc -b` で、`tsconfig.app.json` の `include` は `src` と `vitest-setup.ts`、`tsconfig.node.json` は `vite.config.ts` だけである。足すテストの置き場の `frontend/e2e/` は、どちらにも入らない。(3) 「テストが確かめる文の1つを一時的に変えた」コミットは、その文を `src` の画面の文で変えると、タスク 7.2、7.3、7.7 の Vitest のテストも同じ文を確かめているので `pnpm test` が失敗する。`/ship` は手順1で `/verify-all` の全 PASS を求め、「verify全PASSまでpushしない」と決めているので、そのコミットを push できない。`e2e/` の側の期待する文を変えると、テストの対象のコードではなくテストを壊すことになり、完了条件4の確かめにならない。実装のときに、どれかで必ず止まり、tasks に戻ることになる。なお、`e2e-smoke` は必須のチェックで、この PR はマイグレーションを含み承認まで自動マージされないので、壊したコミットがマージされるおそれは無い | (1) は、タスク 8.2 を `/kiro-impl` の中で完了にできる条件(テストを書き、確認役が中身を読んだこと)に戻し、`e2e-smoke` で通ることと壊した版が失敗することの確かめは、タスクの完了ではなく出荷のときの確かめとして、いつ誰が行い、どこに結果を書くか(PR 本文など)を書く。(2) は、手元の確かめを、`e2e/` を対象にする形(例 `bash .claude/scripts/parallel/run-check.sh frontend npx eslint e2e`。型の検査は、`e2e/` を含む tsconfig が無いので行えないと書く)にするか、手元では検査できないと書く。(3) は、壊し方を、`/verify-all` を通る形(例 `e2e/` の中の `page.route` が返す API の応答の `result` を一時的に別の値にし、画面に出る文が変わってテストが失敗することを見る)に決めるか、壊して失敗を確かめることを、手元でも CI でも行えないことを理由に外す |
| T1-2-2 | 低 | tasks.md タスク 3.4 の「受入基準とテストの対応」の1つ目と2つ目の箇条 | 箇条に分けたときに、要件2の受入基準4の括弧の中の文(「同じ確認のための新しいメールを送る。パスワードの再設定のリンクは10分」)の句点で切れている。1つ目の箇条は「要件2の受入基準4(同じ確認のための新しいメールを送る」で終わってテストの名前が無く、2つ目の箇条は「パスワードの再設定のリンクは10分)は、」で始まる。読めば組は分かるので、実装には影響しない | 2つの箇条を1つに戻し、括弧の中を「同じ確認のための新しいメールを送り、パスワードの再設定のリンクは10分」のように句点の無い形にする |

### 前の段階への指摘

なし

- 往復: 2回目 / 高0 中1 低1

## サイクル1 往復3(2026-10-20)

### 審査の範囲

範囲: 差分

- tasks.md タスク 8.2 の「完了の確かめ方」「出荷のときの確かめ方」「テストの対象を一時的に壊して失敗を確かめる完了条件の扱い」: T1-2-1 への直しで中身が変わった。(1) `/kiro-impl` の中で完了にできるかを見るため、`.claude/skills/kiro-impl/SKILL.md`(確認役の合格のあとに `kiro-verify-completion` を通して `[x]` を付ける手順)と `.claude/skills/kiro-verify-completion/SKILL.md`(TASK の主張に求める証拠と、checklist による確かめ)を読んだ。確認役がテストのファイルを読んで確かめる形は、タスクの範囲に合った証拠になり、`/ship` を待たずに完了にできる。(2) 「lint と型の検査は `frontend/e2e/` を対象にしない」は、往復2で読んだ `frontend/package.json` と `tsconfig*.json` の事実と合う。(3) 出荷のときの確かめ方は、`.claude/skills/ship/SKILL.md` の手順7(CI 監視で必須の検査の赤を直して push し直す)と合う。完了条件4は、手元でブラウザを動かせないことを理由に置き換えており、理由がある置き換えに当たる
- tasks.md タスク 7.2、7.3、7.7: タスク 8.2 が、3つの画面の文とボタンをこれらのタスクの Vitest のテストが確かめていると書いたため。7.2 の `EmailVerificationContainer.test.tsx`、7.3 の `LoginContainer.test.tsx`、7.7 の `userParts.test.tsx` が、それぞれ確認のリンクの画面、ログインの画面、ユーザー設定の画面の文とボタンを確かめており、完了条件4がこれらのテストにも及ぶので、書いたことと合う
- tasks.md の「受入基準とテストの対応」で括弧の中身を足した箇所(タスク 1.2、2.6、3.1、3.3、3.4、4.1、4.3、4.4、4.5、4.6、4.7、5.1、5.2、5.3、6.1、6.2、7.2、7.3、7.4、7.5、7.6、7.7、8.1、8.2): 足した中身を、requirements.md の該当する受入基準の本文と1つずつ照らした。食い違いは無い。タスク 7.2 の要件1の受入基準5の括弧は「使えないことを出す」で、requirements.md の「このメールアドレスでは登録できないことを画面に出す」と言い方が違うが、承認済みの design の `EMAIL_TAKEN` の文(「このメールアドレスは使えないこと」)に合わせた要約で、意味は変わらないと判断した
- tasks.md タスク 3.4 の箇条: T1-2-2 の切れ目が、1つの箇条にまとめて直されていることを確かめた
- tasks.md タスク 2.1、2.3、3.1 に足した `aud` `lexp` `jti` `sub` の意味: design.md の「EmailVerificationTokenCodec と JwtEmailVerificationTokenCodec」の節(298行目)と「EmailVerificationCurrentTokenStore と RedisEmailVerificationCurrentTokenStore」の節(339行目)の定義と合う。タスク 2.3 の `consume` の言い換えも、design の「置いてある値が `jti` と同じときだけ消す」と、完了の確かめ方の「値を比べずに消すように一時的に変えると失敗する」とで、同じ動きを指す
- tasks.md タスク 1.2、4.1、4.3、4.6、5.2、7.2 の主語を足した文: 言い換えで、何をするか、何を変えないかが変わっていないことを見た。食い違いは無い

### 申告

申告に当たる決めごとは無い。タスク 8.2 で、テストの対象を一時的に壊して失敗を確かめることを行わないと決めたことは、T1-2-1 への直しとして理由を添えて本文に書かれており、同じ画面の文とボタンはタスク 7.2、7.3、7.7 の Vitest のテストで壊して失敗を確かめるので、外れても手戻りは小さい。

### 指摘

なし

### 前の段階への指摘

なし

- 往復: 3回で収束 / 未解決: 0件
