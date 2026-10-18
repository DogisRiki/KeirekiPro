# タスク

- [x] 1. 対応表のとおりに文書を直す
- [x] 1.1 ルートの CLAUDE.md を軽くした本文に置き換える (並行可)

  Claude は、部品「ルートの CLAUDE.md(軽くした本文)」のとおりに、作業フォルダのルートの CLAUDE.md を、scratchpad の下書き `draft/CLAUDE.md` と同じ中身に置き換える。置き換える前に、Claude は、部品「mapping.md」の「呼び出し方」のとおりに生成のスクリプトを動かし直し、スクリプトが止まらないことと、生成した対応表が `.kiro/specs/root-claude-md-slimming/mapping.md` と同じことを確かめる。生成のスクリプトの呼び方は、実装のメモにある。
  - 完了の確かめ方: 作業フォルダのルートの CLAUDE.md と下書きを `cmp` で比べると、違いが出ない。生成のスクリプトが終了コード0で終わり、生成した対応表と `mapping.md` に違いが無い。ルートの CLAUDE.md の「Compact instructions」の節の文が、変える前のルートの CLAUDE.md の同じ節の文と同じである
  - 受入基準とテストの対応: 要件1の受入基準1(記述を1つずつ4つの分け方の1つに分ける)・受入基準2(要る場面が限られる決まりを移し、ほかを残す)・受入基準3(消してよい決まりの2つの条件)・受入基準4(止められることと止められたときにすることを残す)・受入基準5(中身を変えない)・受入基準9(ほかの承認済みの spec が求める中身を短い文で残し、全文の場所を示す)と、要件2の受入基準1(どの記述も対応表のどれかの行に入る)・受入基準2(行ごとに決まりの文・分け方・行き先・要る場面を持つ)・受入基準3〜5(移す行と消す行と写しを消した行の理由と文書)・受入基準7・8(短くして残す行の止める仕組みと外した文、求めている spec と全文の場所)は、生成のスクリプトの止まる条件(どの行にも入っていない元の行がある、分け方の値が5つのどれでもない、組み立てた本文が下書きと食い違う)と、下書きとの `cmp` で確かめる。決まりが要る場面で守られることは、大タスク「場面を動かして確かめる」の場面で確かめる
  - _要件: 1.1, 1.2, 1.3, 1.4, 1.5, 1.9, 2.1, 2.2, 2.3, 2.4, 2.5, 2.7, 2.8_
  - _対象の部品: ルートの CLAUDE.md(軽くした本文), mapping.md_

- [x] 1.2 spec-writing.md に「Issueの印」の節を足す (並行可)

  Claude は、部品「spec-writing.md の「Issueの印」の節」のとおりに、`.kiro/settings/rules/spec-writing.md` の「見本」の節の前に、`## Issueの印` の節を足す。Claude は、節の本文に、変える前のルートの CLAUDE.md の「Issueの印」の節の見出しのあとの文を、文を変えずに写す。作業フォルダのルートの CLAUDE.md は、軽くした本文に置き換わっていることがあるので、Claude は、写す元を `git show $(git merge-base origin/main HEAD):CLAUDE.md` の出力から読む。Claude は、`spec-writing.md` の見出しと目印の一覧に、この節を足さない。
  - 完了の確かめ方: `spec-writing.md` の「見本」の節のすぐ前に `## Issueの印` の節がある。節の見出しのあとの行が、`git show $(git merge-base origin/main HEAD):CLAUDE.md` の出力の「Issueの印」の見出しのあとの行(183〜193 行)と同じ文である。`git diff` の `spec-writing.md` の違いが、足した節だけである
  - 受入基準とテストの対応: 要件1の受入基準2(要る場面が spec の段階に限られる決まりを移す)・受入基準5(移すときに中身を変えない)・受入基準6(全員の Claude が読むリポジトリの中の文書に移す)は、上の行の比べ合わせで確かめる。移した決まりが圧縮のあとにも守られることは、大タスク「場面を動かして確かめる」の spec の段階の場面で確かめる
  - _要件: 1.2, 1.5, 1.6_
  - _対象の部品: spec-writing.md の「Issueの印」の節_

- [x] 1.3 ほかの文書から写しを消す (並行可)

  Claude は、部品「写しを消す文書」のとおりに、対応表の「写しを消す箇所」に挙げた写しを、`.claude/loop.md`、`.kiro/steering/tech.md`、`.claude/skills/verify-frontend/SKILL.md`、`.claude/skills/verify-backend/SKILL.md`、`.claude/skills/start/SKILL.md`、`.claude/skills/spec-review/SKILL.md` から消す。あわせて、Claude は、`.kiro/steering/tech.md` の「開発環境」の節の品質ゲートの参照を、対応表の「参照の直し」のとおりに、各 verify のスキルの「Steps」に向ける。`tech.md` では、消す写しと直す参照が同じ節にあるので、Claude はこの2つを同じタスクで直す。
  - 完了の確かめ方: 6つの文書の `git diff` で消えた行が、対応表の「写しを消す箇所」に挙げた文と、`tech.md` の直した参照の文だけである。`.claude/skills/verify-terraform/SKILL.md` に違いが無い。`.claude/skills/start/SKILL.md` の「Step 5: 判断する」「Step 5.5」「Step 6」に違いが無く、「Step 7: 判断ごとに進む」の違いが冒頭の文だけである
  - 受入基準とテストの対応: 要件1の受入基準8(残す決まりの写しをほかの文書から消し、ほかの承認済みの spec のために全文を置いた文書の写しを消さない)は、上の `git diff` の照合で確かめる。写しを消した文書を使う場面で決まりが守られることは、大タスク「場面を動かして確かめる」の場面で確かめる
  - _要件: 1.7, 1.8_
  - _対象の部品: 写しを消す文書_

- [x] 1.4 移した決まりと消した決まりを指す記述を直す

  Claude は、このタスクで直す記述を、spec-writing.md に「Issueの印」の節を足すタスクが作る節の見出し `## Issueの印` に向ける。Claude は、部品「参照を直す文書」のとおりに、対応表の「参照の直し」に挙げた記述のうち、`.kiro/steering/tech.md` と `README.md` の記述を除いたものを直す。直す文書は、`.claude/skills/kiro-impl/SKILL.md`、`.claude/skills/kiro-spec-requirements/SKILL.md`、`.claude/skills/kiro-spec-design/SKILL.md`、`.claude/skills/kiro-spec-tasks/SKILL.md`、`.claude/skills/spec-review/rules/requirements.md`、`.claude/skills/spec-review/rules/design.md`、`.claude/skills/spec-review/rules/tasks.md` である。Claude は、対応表の「直さない記述」を直さない。
  - 完了の確かめ方: 7つの文書の `git diff` が、対応表の「参照の直し」に挙げた記述だけを変えている。3つの spec の段階のスキルの書き方の基準にする節の一覧と、`spec-review/rules/` の3つのファイルに、「Issueの印」の名前がある。対応表の「直さない記述」に挙げた記述に違いが無い
  - 受入基準とテストの対応: 要件1の受入基準7(移した決まりと消した決まりを指す記述を、移した先か残した先に向ける)は、上の照合と、大タスク「直した文書と検査をまとめて確かめる」の「CLAUDE.md」の検索で確かめる
  - _要件: 1.7_
  - _対象の部品: 参照を直す文書_
  - _依存: 1.2_

- [x] 2. 読み込まれる文書の量を PR で検査する
- [x] 2.1 量を測るスクリプトとそのテストを作る (並行可)

  Claude は、部品「check-claude-md-size.sh」と部品「test-check-claude-md-size.sh」を、置き場所(実装のメモ)の `.github/scripts/check-claude-md-size.sh` と `.github/scripts/tests/test-check-claude-md-size.sh` に作る。Claude は、スクリプトを design の「呼び出し方」と終了コードの表と「失敗したとき」のとおりに作り、テストの場合を design の「テストの方針」の単体テストのとおりにする。
  - 完了の確かめ方: 検査用の写し(実装のメモ)で、Git Bash の `bash .github/scripts/tests/test-check-claude-md-size.sh` と、Linux のコンテナの中の同じテストが、どちらも失敗0件で終わる。検査用の写しの全 `.sh` を CI と同じ形の shellcheck にまとめて渡すと、指摘が0件である。Claude がスクリプトの合計と上限の比べ方を一時的に壊すと、テストが失敗する
  - 受入基準とテストの対応: 要件5の受入基準1(ルートの CLAUDE.md と、どの会話の始めにも読み込まれる文書と、読み込みを指定した文書を測る)は、テストの「`.claude/CLAUDE.md`・`CLAUDE.local.md`・`AGENTS.md`・`paths:` の無い `.claude/rules/` の文書を合計に入れ、`paths:` のある規則と `backend/CLAUDE.md` を入れない」と「`@` の読み込みを辿って合計に入れ、5段目を辿らず、同じ文書を2回数えず、コードの区切りと囲みの中の `@` を読み込みにしない」で確かめる。要件5の受入基準2(上限を超えたら失敗する)・受入基準3(量・上限・文書の一覧と、移すか短くすることと上限を自分で上げないことを言う文を出す)と、要件6の受入基準3(Claude は上限を上げる変更を自分の判断で入れない)の Claude に向けた文は、テストの「上限を1バイト超えたら終了コード1で、文書の一覧、`::error::` の行、Claude に向けた文を出す」で確かめる。要件5の受入基準4(上限以下なら成功する)は、テストの「上限以下なら終了コード0で、合計と上限の行を出す」で確かめる。要件5の受入基準5(測る文書か上限を読めないと失敗する)は、テストの「上限が無い・0・数でない、ルートの `CLAUDE.md` が無い、読み込みの先が無い、リポジトリの外を指す、`~` か絶対の道のときは終了コード2」で確かめる
  - _要件: 5.1, 5.2, 5.3, 5.4, 5.5, 6.3_
  - _対象の部品: check-claude-md-size.sh, test-check-claude-md-size.sh_

- [x] 2.2 PR の検査のジョブと期待一覧の登録と、README と手順書の説明を作る (並行可)

  Claude は、部品「guardrails.yaml のジョブ claude-md-size」のとおりに、今の `.github/workflows/guardrails.yaml` を Read で読んで置き場所に写し、写しのワークフローの `env` に `CLAUDE_MD_SIZE_LIMIT: '19000'` を、ジョブに `claude-md-size` を足す。続けて、Claude は、部品「required-checks.json(期待一覧への登録)」のとおりに、今の `.github/audit/required-checks.json` を置き場所に写し、写しの `checks` に `claude-md-size` の項目を足す。同じ部品の「使う部品」のとおりに、Claude は、今の `.github/scripts/tests/test-check-audit-skipped-required.sh` を置き場所に写し、写しの、実物の期待一覧との照合の場合の ruleset の必須チェックを直接並べた一覧に `claude-md-size` を足し、一覧の前のコメントの数を20から21に直す。あわせて、Claude は、部品「README.md(参照とワークフローの説明)」のとおりに、作業フォルダの `README.md` の観点の定義の参照の文と、ワークフローの一覧の表の行と、Mermaid の図の箱を直す。さらに、Claude は、design の「ファイルの構成」のとおりに、作業フォルダの `doc/開発フロー/基盤構築手順.md` の「7. Required status checks の指定」の一覧に `claude-md-size` を足し、「20本」の2か所を「21本」に直し、「`claude-md-size` が PR で一度成功を報告したのを確かめてから、Required status checks に `claude-md-size` を追加する」という箇条を足す。
  - 完了の確かめ方: 置き場所の `guardrails.yaml` と今のファイルの違いが、`env` の1行とジョブ `claude-md-size` だけである。ジョブの権限、checkout の指定、3つの手順が、design の「権限」と「呼び出し方」と同じである。置き場所の `required-checks.json` が JSON として読め、今のファイルとの違いが `claude-md-size` の1項目だけである。置き場所の `test-check-audit-skipped-required.sh` と今のファイルの違いが、一覧の `claude-md-size` とコメントの数だけである。検査用の写しで、Linux のコンテナの、実物の期待一覧を読む3つのテスト `test-check-audit-skipped-required.sh`、`test-check-audit-dependabot-stuck.sh`、`test-check-canary-results.sh` が失敗0件で終わる。Claude が置き場所の `test-check-audit-skipped-required.sh` の一覧から `claude-md-size` を一時的に外すと、そのテストが失敗する。検査用の写しの全 `.sh` を CI と同じ形の shellcheck にまとめて渡すと、指摘が0件である。`README.md` の違いが、観点の定義の参照の文と、表の「ずるの検査 | guardrails.yaml」の行と、図の「系統2: ずるの検査」の箱だけである。`doc/開発フロー/基盤構築手順.md` の違いが、手順7の一覧の1行と「21本」の2か所と足した箇条だけであり、手順7の一覧の本数が21である
  - 受入基準とテストの対応: 要件5の受入基準6(検査を必須のチェックとして期待一覧に登録する)は、上の監査のテスト3本と `required-checks.json` の照合と、手順書の一覧の照合で確かめる。要件5の受入基準7(上限の値を design に書いた値にする)は、`guardrails.yaml` の `env` の照合で確かめる。要件6の受入基準1(上限を上げる PR は所有者が承認するまでマージされない)・受入基準2(測り方を変える PR と検査を外す PR も同じ)は、上限の値とジョブとスクリプトとテストがどれも `.github/` の下にあり、`.github/CODEOWNERS` の `/.github/` の行と `check-escape-hatches.sh` の節6がそれらの変更に当たることの照合で確かめる。要件1の受入基準7(README の参照を直す)は、`README.md` の違いの照合で確かめる
  - _要件: 1.7, 5.6, 5.7, 6.1, 6.2_
  - _対象の部品: guardrails.yaml のジョブ claude-md-size, required-checks.json, README.md_

- [x] 3. 直した文書と検査をまとめて確かめる

  Claude は、大タスク「対応表のとおりに文書を直す」の文書と、大タスク「読み込まれる文書の量を PR で検査する」の置き場所のファイルを合わせた検査用の写しで、design の「テストの方針」の結合テストを流す。結合テストのうち、実物の期待一覧を読む監査のテスト3本は、Claude が PR の検査のジョブと期待一覧の登録を作るタスクで流すので、Claude はこのタスクではそれらを流さない。このタスクは、直した文書と PR の検査をつなぐ統合のタスクである。
  - 完了の確かめ方: 検査用の写しで、`CLAUDE_MD_SIZE_LIMIT=19000 bash .github/scripts/check-claude-md-size.sh` が終了コード0で終わり、合計が 19,000 バイト以下と出る。検査用の写しの全 `.sh` をまとめた shellcheck の指摘が0件である。Linux のコンテナの `.claude/hooks/tests/test-restore-after-compact.sh` と `.github/scripts/tests/test-check-escape-hatches.sh` が失敗0件で終わる。作業フォルダの全体を「CLAUDE.md」で検索した結果に、移した決まりか消した決まりがルートの CLAUDE.md にあるように指す記述が、ほかの spec の本文のほかに無い。生成のスクリプト(実装のメモ)が終了コード0で終わり、生成した対応表と `mapping.md` に違いが無く、作業フォルダのルートの CLAUDE.md と下書きを `cmp` で比べると違いが出ない
  - 受入基準とテストの対応: 要件5の受入基準1(直したあとの文書を測る)・受入基準4(上限以下なら成功する)は、上の `check-claude-md-size.sh` の実行で確かめる。要件1の受入基準7(移した決まりと消した決まりを指す記述を直す)は、上の「CLAUDE.md」の検索で確かめる
  - _要件: 1.7, 5.1, 5.4_
  - _依存: 1.1, 1.2, 1.3, 1.4, 2.1, 2.2_

- [x] 4. 場面を動かす仕組みを作る
- [x] 4.1 使い捨ての写しと身代わりを作る

  Claude は、部品「場面を動かす仕組み」の「権限」の送り先を無くす制限と GitHub に届かなくする制限、「呼び出し方」の手順1(写しと `origin.git` を作る)・手順3(身代わりの `gh` と `docker` が答えを返し、呼び出しを記録する)・手順7(写しを残して記録を集める)、「状態の持ち方」の所有者の作業フォルダとほかのセッションの記録の確かめのとおりに、`<scratchpad>/scenes/run-scene.sh` の写しを作る部分と記録を集める部分を作る。あわせて、Claude は、`bin/gh`、`bin/docker`、`git-hooks/pre-push`、`run-check.sh` の身代わりを作る。Claude は、ほかのセッションの記録の確かめが読む記録の場所を、環境の変数で差し替えられるように作る。
  - 完了の確かめ方: Claude が試しの場面の用意を動かすと、`<scratchpad>/scenes/work/<場面>/repo` に写しができる。写しの `origin` が `origin.git` を指し、写しの `main` が、作業のブランチの先頭に身代わりのコミットを1つ足したコミットである。写しの中の `git push` は、`pre-push` の記録に残って終了コード1で終わり、`origin.git` の参照が変わらない。写しの中の `gh issue create` と `gh api -X POST` は、記録に残って終了コード1で終わる。答えのファイルのある `gh issue view` は答えを返す。写しの中の `docker volume rm` は、記録に残って終了コード0で終わり、ホストの Docker のボリュームの一覧が変わらない。写しの中の `docker info` は、用意した答えを返す。写しの中の `bash .claude/scripts/parallel/run-check.sh frontend pnpm run lint` は、引数と始めと終わりの時刻を記録する。用意の前と後で、所有者の作業フォルダの `git status --porcelain=v1 -uall` と `git rev-parse HEAD` の出力が同じである。Claude が手で作ったセッションの ID と写しの道を確かめに渡すと、所有者の作業フォルダの `git rev-parse --git-common-dir` の下の並行作業の記録にそれらが無いときは確かめが通る。Claude が記録の場所を scratchpad の中の試し用のフォルダに差し替え、そこにそれらを含む記録を置いたときは、`run-scene.sh` がその場面を不合格にして止まる。Claude は、この試しで、所有者の作業フォルダの並行作業の記録に何も書かない
  - 受入基準とテストの対応: 要件3の受入基準7(場面の会話に、push・PR の作成・Issue の起票・コメント・マージをさせない)は、上の `git push` と `gh` の書き込みの呼び出しの確かめで確かめる。要件3の受入基準8(場面の会話に、所有者の作業フォルダとほかのセッションの着手の記録を変えさせない)は、上の前後の出力の比べ合わせと、ほかのセッションの記録の確かめの試しで確かめる
  - _要件: 3.7, 3.8_
  - _対象の部品: 場面を動かす仕組み_

- [x] 4.2 場面の会話を動かして記録する部分を作る

  Claude は、部品「場面を動かす仕組み」の「権限」の道具を禁じる制限と許しの形、「呼び出し方」の手順4〜6(写しの中で `claude -p` を動かして出来事を記録する、本文の書き込みの前で会話を止める、圧縮して続きの文を送る)、「状態の持ち方」の読み込みの記録、「失敗したとき」の30分の打ち切りのとおりに、`run-scene.sh` の会話を動かす部分を作る。あわせて、Claude は、`settings-scene.json`、`hooks/record-load.sh`、`hooks/stop-before-write.sh` を作り、「頼る機能と試し方」の表の試しを1つずつ動かす `run-scene.sh probe` を作る。
  - 完了の確かめ方: `settings-scene.json` が JSON として読め、`permissions.deny` に `WebFetch`、`WebSearch`、`Bash(git push *)`、`Bash(gh pr merge *)` があり、InstructionsLoaded と SessionStart に `record-load.sh` が、PreToolUse に `stop-before-write.sh` が登録されている。Claude が手で作った InstructionsLoaded の入力を `record-load.sh` に渡すと、`instructions.log` に、道と `load_reason` と sha256 の行が出る。Claude が手で作った PreToolUse の入力を `stop-before-write.sh` に渡すと、1回目は `continue: false` と `permissionDecision` の `deny` が返り、2回目は何も返らない。`mcp_servers` が空でない `system/init` の記録を Claude が手で作って `run-scene.sh` の確かめに渡すと、`run-scene.sh` が場面を動かさずに止まる。`run-scene.sh` が会話に渡す環境に `GH_TOKEN` と `GITHUB_TOKEN` が無く、`PATH` の先頭が `<scratchpad>/scenes/bin` である。Claude が打ち切りまでの時間を数秒に上書きして、終わらない身代わりの会話で `run-scene.sh` を動かすと、`run-scene.sh` が会話を打ち切り、その場面を不合格として理由を記録に書く。`scenes/` の全 `.sh` の shellcheck の指摘が0件である
  - 受入基準とテストの対応: 要件3の受入基準3(場面の会話が変更後の文書を読み込んだことを記録から確かめる)は、上の `record-load.sh` の確かめで確かめる。要件3の受入基準7(外へ送らせない)は、上の禁止の規則と環境と `mcp_servers` の確かめで確かめる。要件3の受入基準9(所有者は場面を動かす作業をしない)と要件4の受入基準3(圧縮のあとの場面にも同じことを当てはめる)は、`run-scene.sh` が場面の会話を始め、圧縮し、記録を集めることを、大タスク「場面を動かして確かめる」で確かめる
  - _要件: 3.3, 3.7, 3.9, 4.3_
  - _対象の部品: 場面を動かす仕組み_

- [x] 4.3 着手・出荷・品質ゲート・ループ・境界の場面を用意する

  Claude は、部品「場面を動かす仕組み」の場面の一覧のうち、S1、S2、S3、S4、S5、S6a、S6b、S10 の用意を、`<scratchpad>/scenes/fixtures/<場面>/` に作る。用意するものは、身代わりの `gh` の答え(S3 では、`gh/issue-edit-9003` と、「決めた方式」の節を持つ #9003 の `issue view` の答え)、`run-check-plan`、写しに置くコミットとコミットしていない変更、場面の文、圧縮の位置と圧縮のあとに送る文である。あわせて、Claude は、「呼び出し方」の手順2の、ほかのセッションの着手の予約を置く用意(S2 と S3)と、手順1の、`origin.git` の `main` を写しのブランチより進める用意(S6b)を、`run-scene.sh` に作る。また、Claude は、手順3の、`fixtures/<場面>/gh/` に `issue-edit-<番号>` のファイルがあるときに、その番号の `issue edit` を受け付けて本文を `gh-state/issue-<番号>.md` に保存し、その番号の `issue view` に保存した本文を返す受け付けを、`bin/gh` に作る(S3 のため)。
  - 完了の確かめ方: Claude が場面ごとに会話を動かす手前までの用意を動かすと、8つの場面のどれも止まらずに用意を終える。S2 と S3 では、`busy-issues` の出力の `active` に場面の Issue の番号がある。S6b では、`origin.git` の `main` が写しのブランチより1コミット進んでいる。S3 の写しの中で `gh issue edit 9003 --body-file <ファイル>` を呼ぶと、終了コード0で終わり、渡した本文が `gh-state/issue-9003.md` に保存されて記録に残り、そのあとの `gh issue view 9003` の `body` が保存した本文である。`issue-edit-<番号>` のファイルが無い番号の `gh issue edit` は、これまでどおり記録に残って終了コード1で終わる。Claude が親の環境に `FOO_SECRET`、`MCP_X`、`CLAUDE_X` を置いて `run-scene.sh exec <場面> env` を動かすと、出力に、名前に `TOKEN`、`KEY`、`SECRET`、`PASSWORD`、`CREDENTIAL` を含む変数(大文字と小文字を区別しない)と、`CLAUDECODE`、`ANTHROPIC_BASE_URL`、`MCP_` で始まる変数が無く、`CLAUDE_` で始まる変数は `CLAUDE_CONFIG_DIR` と `CLAUDE_CODE_GIT_BASH_PATH` だけである。`run-scene.sh exec <場面> "$(command -v gh)" auth status` のように、場面と同じ環境で本物の `gh` を絶対の道で呼ぶと、ログインしていないと答える。用意の前と後で、所有者の作業フォルダの `git status --porcelain=v1 -uall` と `git rev-parse HEAD` の出力が同じである
  - 受入基準とテストの対応: 要件3の受入基準1(`/start` と `/ship` を含む場面を動かす)・受入基準2(短くして残す決まりと消す決まりと写しを消した決まりのすべてを1つ以上の場面に入れる)は、場面の一覧の「確かめる決まり」の列の場面がすべて用意できることで確かめる。要件3の受入基準7(外へ送らせない)は、`issue edit` を受け付けても本文が scratchpad の中にだけ残ることと、場面と同じ環境から鍵の変数と親の会話から受け継ぐ変数が外れていることと、その環境の本物の `gh` がログインしていないことで確かめる。要件3の受入基準8(ほかのセッションの着手の記録を変えさせない)は、予約が写しの `.git` の下にだけ書かれ、上の前後の出力が同じことで確かめる
  - _要件: 3.1, 3.2, 3.7, 3.8_
  - _対象の部品: 場面を動かす仕組み_

- [x] 4.4 spec の段階の場面を用意する

  Claude は、場面の一覧のうち、S7、S8、S9、S11、S12 の用意を、`<scratchpad>/scenes/fixtures/<場面>/` に作る。Claude がこの5つの場面の用意を1つのタスクにまとめるのは、どの場面も、写しに置く spec `demo-spec` を前提にするためである。用意するものは、写しに置く spec `demo-spec` の作りかけ、身代わりの `gh` の答え、`stop-before`、場面の文、圧縮の位置と圧縮のあとに送る文である。S12 では、Claude は、用意した印の誤りを1件ずつ挙げた一覧を `fixtures/S12/` に書き、合否を決めるときの照合に使う。
  - 完了の確かめ方: 5つの場面の用意が止まらずに終わる。写しの `.kiro/specs/demo-spec/spec.json` が JSON として読め、S7 と S11 では `additional_issues` に 9006 を持ち、S8 では設計が承認済みで、tasks.md に完了の印 `[x]` の付いたタスクがあり、S9 では要件と設計とタスクが承認済みで、`gh issue view 9007` の答えがある。S7 と S11 の `gh pr list` の答えに、場面の一覧のとおりの食い違う spec の行を持つマージ済みの PR がある。S12 の写しの3つの本文が、`fixtures/S12/` の一覧に挙げた印の誤りをすべて持つ
  - 受入基準とテストの対応: 要件3の受入基準1(spec の各段階の流れを含める)・受入基準2(移す決まりのすべてを1つ以上の場面に入れる)は、場面の一覧の S7、S8、S9、S11、S12 の「確かめる決まり」の列の場面がすべて用意できることで確かめる
  - _要件: 3.1, 3.2_

- [x] 4.5 場面の会話を保存した記録を集め、スキルの読み込みをその記録で確かめる

  Claude は、部品「場面を動かす仕組み」の「呼び出し方」の手順7と「状態の持ち方」のとおりに、小タスク「使い捨ての写しと身代わりを作る」が作った `run-scene.sh` の記録を集める部分に、出来事の記録(`turn*.jsonl` と、圧縮と続きの文の記録)の `system/init` に出たセッションの ID ごとに、`CLAUDE_CONFIG_DIR`(無ければ `~/.claude`)の `projects/` の下のフォルダにある `<セッションの ID>.jsonl` を `logs/<場面>/sessions/` に写す処理を足す。あわせて、Claude は、小タスク「場面の会話を動かして記録する部分を作る」が作った `run-scene.sh probe` の「頼る機能と試し方」の表の1つ目の試しを、`/verify-frontend` の会話を保存した記録を `logs/probe/sessions/` に写し、その記録を `perl lib/stream.pl skill-bases` に渡して、出た道に写しの中の道があるかで決める形に直す。親の会話の Claude が場面の合否を決めるときも、同じく `logs/<場面>/sessions/` の記録を `skill-bases` に渡して、スキルの読み込みの道を拾う。
  - 完了の確かめ方: Claude が、手で作ったセッションの ID を `system/init` に持つ出来事の記録と、scratchpad の中の試し用の `CLAUDE_CONFIG_DIR` の `projects/<フォルダ>/<その ID>.jsonl` を用意して記録を集める部分を動かすと、そのファイルが `logs/<場面>/sessions/<その ID>.jsonl` に写る。身代わりの `claude` と試し用の `CLAUDE_CONFIG_DIR` で `run-scene.sh probe` を動かすと、会話を保存した記録に写しの中の道を持つ「Base directory for this skill:」の行があるときは、`probe.txt` の1つ目の機能が「動いた」になり、写しの外の道しか無いときと、その行が無いときと、会話を保存した記録が無いときは「動かなかった」になる。小タスク「使い捨ての写しと身代わりを作る」と「場面の会話を動かして記録する部分を作る」の確かめを含む `<scratchpad>/scenes/tests/` のテスト3本が失敗0件で終わる。`scenes/` の全 `.sh` と `bin/gh`、`bin/docker`、`git-hooks/pre-push` をまとめて渡した shellcheck の指摘が0件である
  - 受入基準とテストの対応: 要件3の受入基準3(場面の会話が変更後の文書を読み込んだことを記録から確かめる)は、`<scratchpad>/scenes/tests/` のテストに足す、会話を保存した記録を集める場合と、probe の1つ目の試しの4つの場合で確かめる
  - _要件: 3.3_
  - _対象の部品: 場面を動かす仕組み_

- [ ] 5. 場面を動かして確かめる

  親の会話の Claude は、この大タスクの小タスクを、部品「場面を動かす仕組み」の「いつ動くか」のとおりに、場面を1つずつ順に動かして進める。Claude は、場面ごとに、`run-scene.sh <場面>` を動かし、記録を読んで場面の一覧の「合格の条件」で合否を決め、部品「verification.md」の「役割」に挙げた欄を持つ節を `verification.md` に足す。場面が不合格になったときは、Claude は、design の「失敗したときの扱い」のとおりに、場面を動かす仕組みか、決まりの行き先か、行き先の文の書き方を直す。文書を直したときは、Claude は、直した文書をコミットしてから、その場面と、直した文書を読むほかの場面を動かし直し、大タスク「直した文書と検査をまとめて確かめる」の「完了の確かめ方」の確かめも流し直す。

- [ ] 5.1 所有者のログインを確かめ、頼る機能を試す

  親の会話の Claude は、部品「場面を動かす仕組み」の「使う部品」のとおりに、ホストの `claude -p "ok と1語で答えて"` の答えで、所有者がホストの `claude` にログインしてあるかを確かめる。答えが返らなければ、Claude は、ホストの端末で `claude` を起動して `/login` を打つよう、理由を添えて所有者に頼み、返事を待つ。ログインを確かめたら、Claude は、`run-scene.sh probe` を動かし、`verification.md` を作って、「頼る機能の試し」の節に機能ごとの日時と結果を書く。
  - 完了の確かめ方: `verification.md` の「頼る機能の試し」の節に、design の「頼る機能と試し方」の表の8つの機能のすべてについて、試した日時と、動いたか動かなかったかがある。動かなかった機能があるときは、Claude が、その機能と代わりの方法の案を所有者に報告してあり、その機能に頼る場面を動かしていない
  - 受入基準とテストの対応: 要件3の受入基準5(場面ごとの記録を spec のディレクトリに残す)は、`verification.md` ができていることで確かめる。要件3の受入基準9(所有者は場面を動かす作業をしない)は、所有者に頼む操作がログインだけであることで確かめる
  - _要件: 3.5, 3.9_
  - _保留: 所有者のログインを確かめる必要があるので、親の会話の Claude がこのタスクを行う(実装のメモの「保留のタスクの進め方」)_

- [ ] 5.2 着手の場面を動かす

  親の会話の Claude は、場面の一覧の S1、S2、S3、S9 を、この順に1つずつ動かす。
  - 完了の確かめ方: `verification.md` に、4つの場面の節があり、どの場面も最後の節が合格である。各節に、ルートの CLAUDE.md の sha256 が作業のブランチのルートの CLAUDE.md の sha256 と同じことと、会話を保存した記録の「Base directory for this skill:」の行のスキルの道が写しの中であることが書かれている。S2 と S3 の節に、圧縮を起こした方法と位置が書かれている
  - 受入基準とテストの対応: 要件3の受入基準1(`/start` を含む場面を動かす)・受入基準2(決まりのすべてを1つ以上の場面で確かめる)・受入基準3(変更後の文書を読み込んだことを記録から確かめる)・受入基準4(今の決まりのとおりに動けば合格とする)・受入基準5(場面ごとの記録を残す)・受入基準6(不合格なら直して動かし直し、不合格が残る間は PR を出さない)・受入基準7(外へ送らせない)・受入基準8(作業フォルダと着手の記録を変えさせない)と、要件4の受入基準1(ほかの承認済みの spec のために短くして残す決まりを、圧縮のあとの場面で確かめる)・受入基準2(圧縮のあとも決まりのとおりに動けば合格とする)・受入基準3(圧縮のあとの場面にも同じことを当てはめる)は、この場面の会話の記録と `verification.md` の節で確かめる
  - _要件: 3.1, 3.2, 3.3, 3.4, 3.5, 3.6, 3.7, 3.8, 4.1, 4.2, 4.3_
  - _保留: 頼る機能の試しのあとに、親の会話の Claude がこのタスクを行う(実装のメモの「保留のタスクの進め方」)_

- [ ] 5.3 出荷と品質ゲートとループの場面を動かす

  親の会話の Claude は、場面の一覧の S4、S5、S6a、S6b を、この順に1つずつ動かす。
  - 完了の確かめ方: `verification.md` に、4つの場面の節があり、どの場面も最後の節が合格である。各節に、変更後の文書を読み込んだことの確かめが書かれている。S4 と S5 の節に、圧縮を起こした方法と位置が書かれている
  - 受入基準とテストの対応: 要件3の受入基準1(`/ship` を含む場面を動かす)・受入基準2〜8(決まりのすべてを確かめ、変更後の文書を読み込んだことを確かめ、合否を決めて記録し、不合格なら直し、外へ送らせず、作業フォルダと着手の記録を変えさせない)と、要件4の受入基準1〜3(消す決まりを圧縮のあとの場面で確かめ、合否を決め、同じことを当てはめる)は、この場面の会話の記録と `verification.md` の節で確かめる
  - _要件: 3.1, 3.2, 3.3, 3.4, 3.5, 3.6, 3.7, 3.8, 4.1, 4.2, 4.3_
  - _保留: 頼る機能の試しのあとに、親の会話の Claude がこのタスクを行う(実装のメモの「保留のタスクの進め方」)_

- [ ] 5.4 spec の段階の場面を動かす

  親の会話の Claude は、場面の一覧の S7、S8、S11、S12 を、この順に1つずつ動かす。S12 では、Claude は、審査役が書いた `reviews/<段階>-review.md` の指摘を、`fixtures/S12/` の印の誤りの一覧と1件ずつ照らす。
  - 完了の確かめ方: `verification.md` に、4つの場面の節があり、どの場面も最後の節が合格である。各節に、変更後の文書を読み込んだことの確かめが書かれている。S7、S8、S11 の節に、圧縮を起こした方法と位置が書かれている
  - 受入基準とテストの対応: 要件3の受入基準1(spec の各段階の流れを含める)・受入基準2〜8(決まりのすべてを確かめ、変更後の文書を読み込んだことを確かめ、合否を決めて記録し、不合格なら直し、外へ送らせず、作業フォルダと着手の記録を変えさせない)と、要件4の受入基準1(移す決まりを、行き先を読み込んだあとに圧縮した場面で確かめる)・受入基準2(圧縮のあとも決まりのとおりに動けば合格とする)・受入基準3(圧縮のあとの場面にも同じことを当てはめる)は、この場面の会話の記録と `verification.md` の節で確かめる
  - _要件: 3.1, 3.2, 3.3, 3.4, 3.5, 3.6, 3.7, 3.8, 4.1, 4.2, 4.3_
  - _保留: 頼る機能の試しのあとに、親の会話の Claude がこのタスクを行う(実装のメモの「保留のタスクの進め方」)_

- [ ] 5.5 境界の問いの場面を動かす

  親の会話の Claude は、場面の一覧の S10 の11の文を、1つずつ別の会話として動かす。
  - 完了の確かめ方: `verification.md` に S10 の節があり、11の文のそれぞれについて会話がしたことと合否が書かれ、最後の節が合格である。節に、変更後の文書を読み込んだことの確かめが書かれている
  - 受入基準とテストの対応: 要件3の受入基準2(フックや CI が止めるために短くして残す決まりを場面で確かめる)・受入基準3〜8(変更後の文書を読み込んだことを確かめ、合否を決めて記録し、不合格なら直し、外へ送らせず、作業フォルダと着手の記録を変えさせない)は、この場面の会話の記録と `verification.md` の節で確かめる
  - _要件: 3.2, 3.3, 3.4, 3.5, 3.6, 3.7, 3.8_
  - _保留: 頼る機能の試しのあとに、親の会話の Claude がこのタスクを行う(実装のメモの「保留のタスクの進め方」)_

- [ ] 6. main と比べ直し、PR の検査を本来の場所に置いて確かめる
- [ ] 6.1 main のルートの CLAUDE.md と対応表を比べ直す

  親の会話の Claude は、部品「mapping.md」の「状態の持ち方」のとおりに、`git fetch origin main` のあと、`origin/main` のルートの CLAUDE.md を、対応表の元の文と比べる。足された決まりか直された決まりがあれば、Claude は、main を作業のブランチに取り込み、行の定義に行を足して、対応表と下書きとルートの CLAUDE.md を作り直す。続けて、Claude は、足した行のうち場面で確かめる決まりの場面を動かし直し、`verification.md` に節を足す。
  あわせて、Claude は、design の「設計を見直すきっかけ」の行き先の節が書き換わる場合を見つけるために、上の比べで main を取り込む前に、作業のブランチと `origin/main` の分かれ目(`git merge-base HEAD origin/main`)と `origin/main` のあいだで、対応表の行き先の文書と、対応表の「理由」の列が挙げる文書(`restore-after-compact.sh`、短くして残す行の止める仕組みのファイル、`spec-need-triage` の requirements.md など)と、写しを消した文書と、参照を直した文書を `git diff` で比べる。違いがあれば、Claude は、main を作業のブランチに取り込み、その文書を行き先か理由にしている対応表の行ごとに、理由がまだ成り立つかを確かめる。成り立たない行は、Claude は行の定義を直して対応表を作り直す。理由が成り立つかどうかに依らず、Claude は、違いのあった文書を読む場面を動かし直し、`verification.md` に節を足す。
  - 完了の確かめ方: 生成のスクリプトを `origin/main` のルートの CLAUDE.md を元の文として動かすと、終了コード0で終わり、生成した対応表が `mapping.md` と同じである。作業フォルダのルートの CLAUDE.md と下書きを `cmp` で比べると、違いが出ない。行を足したときは、動かし直した場面の最後の節が合格である。分かれ目と `origin/main` のあいだの、上の比べる文書のどれかに違いがあったときは、その文書を読む場面の最後の節が合格である
  - 受入基準とテストの対応: 要件2の受入基準6(設計のあとに main で足されたか直された決まりも対応表に載せて分ける)は、上の生成のスクリプトの実行で確かめる
  - _要件: 2.6_
  - _保留: 場面のあとに、親の会話の Claude がこのタスクを行う(実装のメモの「保留のタスクの進め方」)_

- [ ] 6.2 所有者に .github の下のファイルを置いてもらい、本来の場所で確かめる

  親の会話の Claude は、`cp` のコマンドを示す前に、作業フォルダの今の `guardrails.yaml` と `required-checks.json` と `test-check-audit-skipped-required.sh` を置き場所の完成版と比べる。違いが、小タスク「PR の検査のジョブと期待一覧の登録と、README と手順書の説明を作る」の「完了の確かめ方」に挙げた `guardrails.yaml` と `required-checks.json` と `test-check-audit-skipped-required.sh` の違いだけでなければ、main の取り込みでファイルが変わったので、Claude は、置き場所の完成版を今のファイルから作り直す。続けて、Claude は、部品「guardrails.yaml のジョブ claude-md-size」の「所有者の操作」の1つ目のとおりに、置き場所の5つのファイルを本来の場所に写す `cp` のコマンドを所有者に示し、理由を添えて置くよう頼む。所有者が置いたら、Claude は、置かれたファイルが置き場所の完成版と同じことを確かめ、本来の場所で単体テストと量の検査と監査のテスト3本と shellcheck と、大タスク「直した文書と検査をまとめて確かめる」の確かめを流す。Claude は、置かれた5つのファイルを、この小タスクの完了の印と同じコミットに入れる。
  - 完了の確かめ方: 置く前の比べ合わせで、違いが上の項目だけである。`git status` に、置いた5つのファイルが出る。5つとも置き場所の完成版と同じである。本来の場所で、`test-check-claude-md-size.sh` が Git Bash と Linux のコンテナの両方で失敗0件で終わる。`CLAUDE_MD_SIZE_LIMIT=19000 bash .github/scripts/check-claude-md-size.sh` が終了コード0で終わる。Linux のコンテナの監査のテスト3本と、`test-restore-after-compact.sh` と `test-check-escape-hatches.sh` が失敗0件で終わる。まだコミットしていない新しいファイルを含めた全 `.sh` の shellcheck の指摘が0件である。作業フォルダの全体を「CLAUDE.md」で検索した結果が、大タスク「直した文書と検査をまとめて確かめる」の確かめと同じく通る。コミットに5つのファイルと完了の印が入っている
  - 受入基準とテストの対応: 要件5の受入基準6(期待一覧への登録を PR に含める)と、要件6の受入基準1・2(上限を上げる PR と、測り方を変える PR と、検査を外す PR は、所有者が承認するまでマージされない)は、5つのファイルが本来の場所の `.github/` の下に置かれたことと、上のテストで確かめる
  - _要件: 5.6, 6.1, 6.2_
  - _保留: 所有者がファイルを置く必要があるので、親の会話の Claude がこのタスクを行う(実装のメモの「保留のタスクの進め方」)_

## 実装のメモ

- scratchpad: この tasks.md の `<scratchpad>` と「scratchpad」は、この spec の設計を作った会話の scratchpad `C:/Users/dogis/AppData/Local/Temp/claude/C--Users-dogis-Desktop-DockerWorkSpace-develop-KeirekiPro--claude-worktrees-issue-522-a1eaad/ee054336-9a9e-4df2-ac9d-e15282887e41/scratchpad` を指す。その scratchpad には、下書き `draft/CLAUDE.md`、行の定義 `mapping/rows.txt`、生成のスクリプト `mapping/gen.pl` がある。親の会話の Claude は、実装役と確認役の依頼文に、scratchpad の絶対の道を書く。Claude は、着手の前に下書きと行の定義と生成のスクリプトがあることを確かめ、無ければ、無いことを所有者に報告して止まる
- 生成のスクリプトの呼び方: Claude は、変える前のルートの CLAUDE.md を `git show $(git merge-base origin/main HEAD):CLAUDE.md` で scratchpad のファイルに書き出し、`<scratchpad>/mapping` で `perl -CSD gen.pl <書き出したファイル> rows.txt ../draft/CLAUDE.md <出力の対応表>` を動かす。比べ直しで `origin/main` と比べるときは、Claude は `git show origin/main:CLAUDE.md` を書き出して同じく動かす
- 置き場所: `.claude/settings.json` の `deny` によって、Claude は `.github/` の下に書けない。Claude は、`.github/` の下に置く5つのファイルの完成版を、`<scratchpad>/github-files/` の下に、リポジトリと同じ並び(`<scratchpad>/github-files/.github/...`)で作る。今のファイルを写すときは、Claude は Read と Write を使う。所有者が置くまで、Claude は本来の場所に書こうとしない
- 検査用の写し: Claude は、テストと shellcheck を、作業フォルダを `git archive HEAD` で scratchpad の一時フォルダに写し、そこに置き場所のファイルと、まだコミットしていない作業フォルダの変更を本来の道で重ねたフォルダで流す。並行して進むタスクが互いの写しを上書きしないよう、Claude は、写しのフォルダを、タスクごとに `mktemp -d` で別に作る。まだリポジトリに無いファイルを `docker -v` で作業フォルダに重ねると、作業フォルダに0バイトのファイルが残るので、Claude はそうしない
- Linux のコンテナ: Claude は、検査用の写しを alpine のコンテナに写し、`apk add --no-cache bash perl git` のあとでテストを流す。shellcheck は、CI と同じく `koalaman/shellcheck:v0.11.0` に全 `.sh` をまとめて渡す。1ファイルずつ渡すと、読み込んだ先のファイルの指摘を見落とすためである
- 確認役は、置き場所と `scenes/` の成果を scratchpad の道で確かめる。これらの成果は `git diff` に出ないためである
- verify のスキル: この spec は frontend と backend と terraform のコードを変えないので、共通の完了条件の2つ目に当たる verify のスキルは無い。Claude は、代わりに、各タスクの「完了の確かめ方」のテストと shellcheck を流す
- 共通の完了条件の1つ目(確かめるテストの無い受入基準を残さない)には、次の例外がある。要件1(ルートの CLAUDE.md には、どの会話でも要る決まりだけを残す)と要件2(決まりごとの行き先を対応表で示す)の受入基準は、生成のスクリプトと `cmp` と `git diff` の照合と検索で確かめる。要件3(移したあとも、新しい会話で今と同じように動くことを確かめる)と要件4(会話を圧縮したあとも、移した決まりが守られることを確かめる)の受入基準は、場面の会話の記録と `verification.md` で確かめる。要件6の受入基準1(上限の値を上げる PR は、所有者が承認するまでマージされない)・受入基準2(検査の測り方を変える PR と、この検査を外す PR も、所有者が承認するまでマージされない)は、ファイルの置き場所と CODEOWNERS の照合で確かめる。Claude は、これらの受入基準を、各タスクの「受入基準とテストの対応」の行に書いた方法で確かめる
- 保留のタスクの進め方: 大タスク「場面を動かして確かめる」と大タスク「main と比べ直し、PR の検査を本来の場所に置いて確かめる」の小タスクは `_保留:_` なので、`/kiro-impl` は、自律で進めるときに、実装役を起動せずにこれらを飛ばす。親の会話の Claude は、`/kiro-impl` の Step 3 の繰り返しが終わったあと、Step 4 の `/kiro-validate-impl` を流す前に、これらを番号の順に自分で進める。小タスクを終えたら、親の会話の Claude は、その小タスクの `_保留:_` の行を消して完了の印を付け、コミットする
- 場面の前のコミット: `run-scene.sh` は、写しを作業フォルダのコミットされた中身から作る。Claude は、場面を動かす前に、`git status --porcelain` で、ルートの CLAUDE.md と、スキルと spec の書き方の基準と steering の文書にコミットしていない変更が無いことを確かめる。Claude は、場面を動かす前のコミットを push しない
- 同じ失敗の数え方: 同じ場面が同じ理由で3回続けて不合格になったら、Claude は直すのをやめ、所有者に報告する。場面を動かす仕組みの誤りによる動かし直しは、この数に入れない
- 決まりを「残す」に戻したとき: Claude は、design の「失敗したときの扱い」のとおりに上限を決め直す。決め直した値が今の値と違えば、Claude は、置き場所の `guardrails.yaml` の値も直し、design.md を直すので、設計とタスクの承認を取り消してから所有者に設計の承認をやり直してもらう
- 差分の照合: Claude は、差分を照合する前に `git fetch origin main` を流し、変えたファイルを `git merge-base origin/main HEAD` のコミットと比べる。main の先端と比べると、並行するほかの PR の変更も違いに出るためである
- 出荷のとき: 親の会話の Claude は、`/ship` の PR 本文に、`Spec: .kiro/specs/root-claude-md-slimming`、`Refs: #568`、`Closes #568` を書く。`test-check-audit-skipped-required.sh` の期待を意図して変えるので、Claude は、PR 本文に `Test-Change-Justification:` の行も書く。PR の CI で `claude-md-size` が一度動いたあと、Claude は、design の「所有者の操作」の2つ目と3つ目のとおりに、ブランチの決まりに `claude-md-size` を足すことと PR を Approve することを、1つずつ理由を添えて所有者に頼む
- 場面の会話の環境: `run-scene.sh` は、場面の会話と `run-scene.sh exec` の環境から、名前に TOKEN・KEY・SECRET・PASSWORD・CREDENTIAL を含む変数(大文字と小文字を区別しない)と、親の会話から受け継ぐ `CLAUDECODE`・`CLAUDE_*`・`ANTHROPIC_BASE_URL`・`MCP_*` を外し、`CLAUDE_CONFIG_DIR` と `CLAUDE_CODE_GIT_BASH_PATH` だけを残す。親の会話の環境には GitHub に書き込める鍵があり、残すと場面の会話が身代わりの `gh` を通らずに GitHub に届くためである。所有者のログインは、小タスク「所有者のログインを確かめ、頼る機能を試す」で、この環境(`run-scene.sh exec probe claude -p …`)で確かめる
- 場面ごとの答え: 身代わりの `gh` の答えは場面のフォルダに1組しか置けないので、同じ用意で別の文を送る場面(S10 の11の問いなど)は、文ごとに `fixtures/S10-01/` のように別の場面のフォルダを作る。S12 も同じ形にする
- 場面のテストと probe: `<scratchpad>/scenes/tests/` のテストは、`logs/probe` と `work/probe` を身代わりの結果で作り直す。親の会話の Claude は、テストを流したあとに本物の `run-scene.sh probe` を動かし直してから、`probe.txt` を読む
- 会話を保存した記録の無い場面: `run-scene.sh` の記録を集める部分は、会話を保存した記録が見つからないセッションを出力に書くだけで、場面を不合格にしない。親の会話の Claude は、場面の合否を決めるときに `logs/<場面>/sessions/` にその場面の記録が無ければ、スキルの読み込みを確かめられないので、その場面を不合格にする

## 完了条件(全タスク共通)

Claude は、どのタスクでも、タスクの箇条書きの欄を書いたうえで、次の4つを満たしたときにタスクを完了とする。

1. Claude は、タスクが満たす requirements.md の受入基準(要件の番号付きの項目)ごとに、それを確かめるテストのファイル名とテスト名を「受入基準とテストの対応」の行に書く。Claude は、確かめるテストの無い受入基準を残さない。
2. タスクで変えた領域の verify のスキル(`/verify-frontend` `/verify-backend` `/verify-terraform`)が、すべて成功している。
3. Claude は、テストを飛ばす設定、アサーションの削除、カバレッジや lint の対象からの除外を足して、完了条件を満たしたように見せない。CI の escape-hatch の検査が、これらの追加を機械で見つける。
4. Claude は、新しく書いたテストについて、テストの対象のコードを一時的に壊してテストが失敗することを確かめてから、コードを元に戻す。
