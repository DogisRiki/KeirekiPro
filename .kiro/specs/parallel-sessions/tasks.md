# タスク

- [ ] 1. 土台を作る
- [x] 1.1 記録の場所と枠の数え方をまとめた関数群を作る

  Claude は、部品「lib.sh」の関数群と、そのテスト `test-lib.sh` を作る。関数群は、記録の置き場所、作業フォルダと鍵(`core.ignorecase` が `true` のときだけ小文字にする)、本体フォルダ、設定の数(無ければ1)、セッションのID、枠を取る・返す・取り戻す・取り直す、枠の持ち主の一覧、JSON の読み書きを受け持つ。`lib.sh` は、読み込まれたときに自分で `MSYS_NO_PATHCONV=1` を設定する。Claude は、使う git のコマンドの最も新しい版(`git rev-parse --path-format=absolute` の 2.31)を、`lib.sh` の冒頭の注記に書く。テストは、偽物の `docker`(呼ばれた引数をファイルに書くだけのもの)を `PATH` の先に置き、一時的な git のリポジトリと worktree で動かす。
  - 完了の確かめ方: `bash .claude/scripts/parallel/tests/test-lib.sh` の場合がすべて通る
  - 受入基準とテストの対応: 要件3の受入基準1(設定で数を変えられ、初期値は1)は、テストの「設定が無いときに1を返す」「3 を設定すると3を返す」「0 や abc では終了コード69になる」「worktree と本体フォルダのどちらから呼んでも、記録の置き場所と設定が同じになる」で確かめる。要件3の受入基準2(設定の数に達していれば待つ)は、テストの「設定の数の枠が埋まっていれば取れない」「2つのプロセスが同時に取っても同じ枠を取らない」で確かめる。要件3の受入基準4(同時に走っても失敗や合格が出ない)の土台は、テストの「動いているコンテナの無い古い check の枠を取り戻す」で確かめる。要件1の受入基準5(ほかのセッションの開発サーバを止めない)は、テストの「持ち主のセッションの記録が残っている ui の枠は取り戻さず docker rm -f を呼ばない」「持ち主の記録が無い ui の枠は docker rm -f を呼んでから取り戻す」で確かめる。要件3の受入基準2の、同じセッションが画面確認を打ち直したときに自分の枠を待たないことは、テストの「いまの作業フォルダが持つ ui の枠は同じ番号で取り直せる」で確かめる
  - _要件: 1.5, 3.1, 3.2, 3.4_
  - _対象の部品: lib.sh_

- [x] 1.2 worktree でも compose の読み込みが通るようにする

  Claude は、部品「worktree に写すファイルと compose の読み込み」のとおり、`compose.yaml` の localstack の `env_file` を `required: false` の長い書き方にし、`.worktreeinclude` に `.claude/settings.local.json` と `docker/localstack/.env.local` を書き、`.gitignore` に `.claude/worktrees/` を足す。
  - 完了の確かめ方: `.env.local` の無い一時的な worktree の最上位で `docker compose -p keirekipro -f compose.yaml config -q` が終了コード0で終わる。本体フォルダで `git check-ignore -v .claude/worktrees/x` を打つと、無視の出どころとして `.gitignore` の行が出る(`.git/info/exclude` ではない)
  - 受入基準とテストの対応: 要件1の受入基準3(worktree でも `/ship` まで同じように終える)の土台と、要件6の受入基準1(セッションごとに所有者がファイルを写さない)は、この完了の確かめ方の `docker compose config -q` で確かめる
  - _要件: 1.3, 6.1_
  - _対象の部品: worktree に写すファイルと compose の読み込み_

- [ ] 2. スクリプトとフックを作る
- [x] 2.1 品質チェックのコマンドを1回きりのコンテナで動かすスクリプトを作る (並行可)

  Claude は、部品「run-check.sh」のスクリプトと、そのテスト `test-run-check.sh` を作る。Claude は、スクリプトを、「コマンドの前にすること」が空の領域でも `sh -c` の区切りが壊れない形にする。Claude は、`run-check.sh` が枠を取った直後に `chown` を動かす別の1回きりのコンテナにも、同じ枠のラベル(`--label keirekipro.slot=<k>`)を付ける。Claude は、frontend の準備(pnpm のストアのボリュームの持ち主を変えることと、node_modules の確かめ)を、2.2 の `ui.sh` からも使えるように、`run-check.sh` の中で1つの関数にまとめ、読み込んで呼べる形にする。`run-check.sh` は、`BASH_SOURCE` と `$0` を比べ、読み込まれただけのときは本体の処理を動かさないようにする。Claude は、テストが待ちの上限を環境変数で短くできるようにする。
  - 完了の確かめ方: `bash .claude/scripts/parallel/tests/test-run-check.sh` の場合がすべて通る
  - 受入基準とテストの対応: 要件2の受入基準1(そのセッションの作業フォルダを検査する)は、テストの「worktree で呼ぶとその最上位で -p keirekipro run --rm --no-deps と枠のラベルが渡る」で確かめる。要件2の受入基準4(検査できないときは合格にしない)は、テストの「compose の読み込みに失敗すると終了コード69で記録を書かない」で確かめる。要件2の受入基準5(そのセッションの品質チェックだけを数える)は、テストの「coverage が0で終わったときだけ worktree の gate-run-frontend.txt を書き、本体フォルダには書かない」で確かめる。要件2の受入基準6(結果を上書きしない)は、テストの「作業フォルダごとの node_modules のボリューム名が鍵で分かれる」で確かめる。要件3の受入基準2と3(待つ、待ちを示す)は、テストの「枠が埋まっていて --wait が無ければ終了コード10と持ち主の一覧を出し、docker を呼ばない」「--wait では空いたあとに動く」で確かめる。要件3の受入基準4(同時に走っても失敗しない)は、テストの「VITEST_MAX_WORKERS が 8 ÷ 設定の数になる」「Gradle のユーザーのキャッシュのボリュームが枠ごとに分かれる」で確かめる。要件3の受入基準5(待ちの上限で合格にしない)は、テストの「待ちの上限で終了コード75になり記録を書かない」で確かめる
  - _要件: 2.1, 2.4, 2.5, 2.6, 3.2, 3.3, 3.4, 3.5_
  - _対象の部品: run-check.sh_

- [x] 2.2 画面確認の開発サーバを1回きりのコンテナで動かすスクリプトを作る

  Claude は、部品「ui.sh」のスクリプトと、そのテスト `test-ui.sh` を作る。`ui.sh` は、frontend の準備に、2.1 で `run-check.sh` にまとめた関数を読み込んで使う。`ui.sh` は、frontend が起動したか(TCP でつながるか)を、`perl` の `IO::Socket::INET` で確かめる。
  - 完了の確かめ方: `bash .claude/scripts/parallel/tests/test-ui.sh` の場合がすべて通る
  - 受入基準とテストの対応: 要件2の受入基準2(画面にそのセッションの変更が出る)は、テストの「start で、枠 k のポートと鍵の DB と host.docker.internal の VITE_API_URL と SPRING_APPLICATION_JSON が docker に渡る」で確かめる。要件1の受入基準5(ほかのセッションの開発サーバを止めない)は、テストの「stop は、いまの作業フォルダのラベルの ui コンテナだけを消す」で確かめる。要件2の受入基準4(検査できないときは合格にしない)は、テストの「健康の確かめが上限に達すると終了コード69で自分のコンテナを消し枠を返す」で確かめる。要件3の受入基準2(設定の数に達していれば待つ)、3(待っていることを示す)、5(待ちの上限で合格にしない)は、テストの「枠が埋まっていると終了コード10」「待ちの上限で終了コード75」で確かめる
  - _要件: 1.5, 2.2, 2.4, 3.2, 3.3, 3.5_
  - _対象の部品: ui.sh_
  - _依存: 2.1_

- [x] 2.3 着手のときの調べと記録のスクリプトを作る (並行可)

  Claude は、部品「session.sh」のうち、`check-start`、`claim`、`end`、`spec-names` のサブコマンドと、そのテスト `test-session.sh` を作る。Claude は、`check-start` が最初に呼ぶ `prune` を、この小タスクでは何もしない形にしておき、2.4 で `prune` の中身を作る。
  - 完了の確かめ方: `bash .claude/scripts/parallel/tests/test-session.sh` の check-start・claim・end・spec-names の場合がすべて通る
  - 受入基準とテストの対応: 要件5の受入基準1(同じ作業フォルダの別のセッションで止まる)は、テストの「同じ作業フォルダに別の作業中のセッションの記録があると folder_conflict に出る」「同じ作業フォルダの、Issueの記録の無いセッション(着手していない記録)は folder_conflict に出ない」で確かめる。要件5の受入基準2(やめたと答えたら続ける)は、テストの「end のあとの check-start では folder_conflict が空になる」で確かめる。要件4の受入基準1と2(どの作業フォルダの作りかけでも、セッションの開閉を問わず止まる)は、テストの「別の worktree のコミットしていない spec が leftovers に出て、セッションの記録の有無が active_session に出る」「いまの作業フォルダの作りかけは is_self が真で出る」「spec の無いIssueもIssueの記録のブランチで見つかる」で確かめる。要件3の受入基準6(埋まっていることを報告する)は、テストの「capacity に自分以外の作業中のセッションが出る」で確かめる。要件1の受入基準1の spec の名前の重なりは、テストの「spec-names がほかの worktree の spec の名前も出す」で確かめる
  - _要件: 1.1, 3.6, 4.1, 4.2, 5.1, 5.2_
  - _対象の部品: session.sh_

- [x] 2.4 記録と残ったものの片付けを作る

  Claude は、部品「session.sh」の `prune` のサブコマンドと、そのテストを `test-session.sh` に足す。`prune` は、最初に `git worktree prune` を打ってディレクトリが消えた worktree を git の記録から外し、作業フォルダが無くなった記録とボリュームと DB を片付け、ブランチが残っているIssueの記録は `folder` を空にして残し、取り戻せる枠を取り戻す。この小タスクで Claude が変えるファイルは 2.3 と同じなので、Claude は、この小タスクを 2.3 のあとに行う。
  - 完了の確かめ方: `bash .claude/scripts/parallel/tests/test-session.sh` の prune の場合がすべて通る
  - 受入基準とテストの対応: 要件4の受入基準5(ブランチだけでも止まる)は、テストの「worktree を git worktree remove で消したあとも、ブランチが残っていれば issues の記録が folder を空にして残り、check-start の branch_only に出る」「ブランチも消したあとは記録が消える」で確かめる。ディレクトリだけが消えた worktree のブランチに切り替えられることは、テストの「ディレクトリだけを消した worktree は git worktree prune で外れ、そのブランチに git switch できる」で確かめる
  - _要件: 4.5_
  - _対象の部品: session.sh_
  - _依存: 2.3_

- [ ] 2.5 作りかけの引き継ぎを作る

  Claude は、部品「session.sh」の `takeover` のサブコマンドと、そのテストを `test-session.sh` に足す。Issueの記録が無いときの `--from`(移行の前からある作りかけ)と、`--branch` のときのいまの作業フォルダのきれいさの確かめとリモートの取得も扱う。前の HEAD がいまの HEAD の先祖でないときは、Claude は、`takeover` が出す文に「いまの作業フォルダのブランチに前の作業フォルダの HEAD(前の土台)を取り込んでから、もう一度 `/start` を打つ」という次の手を含める。前の HEAD がいまの HEAD の先祖でない食い違いは、前の土台を含んでいない、いまの作業フォルダの側でしか直せないからである。この小タスクで Claude が変えるファイルは 2.4 と同じなので、Claude は、この小タスクを 2.4 のあとに行う。
  - 完了の確かめ方: `bash .claude/scripts/parallel/tests/test-session.sh` の takeover の場合がすべて通る
  - 受入基準とテストの対応: 要件4の受入基準6と要件1の受入基準1(前の作業フォルダの作りかけを失わずに引き継ぐ)は、テストの「別の worktree のコミットしていない spec とブランチが写り、前の worktree の中身は消えない」「古い main にいた前の作業フォルダからの引き継ぎで、新しい main のコミットが取り消されない」「前の HEAD がいまの HEAD の先祖でなければ、何も写さずに終了コード1で止まり、次の手を出す」で確かめる。要件4の受入基準3と4(やめた・続きから進めるの答えで引き継ぐ)は、テストの「--from がいまの作業フォルダのとき、作りかけが残ったまま記録の session_id だけが書き換わる」で確かめる。要件4の受入基準5(ブランチだけが残っていても止まり、続きから進められる)は、テストの「--branch でリモートにだけあるブランチを取得して切り替える」で確かめる。要件4の受入基準6の後半(引き継いだあとは前の作業フォルダを数えない)は、テストの「引き継いだあとの check-start は前の worktree も自分の作りかけも出さない」で確かめる。要件1の受入基準2(ほかのセッションのブランチにコミットしない)は、テストの「前の worktree はブランチを手放して detached になる」で確かめる
  - _要件: 1.1, 1.2, 4.3, 4.4, 4.5, 4.6_
  - _対象の部品: session.sh_
  - _依存: 2.4_

- [ ] 2.6 セッションの記録を付けるフックを作る (並行可)

  Claude は、部品「session-registry.sh」のフックと、そのテスト `test-session-registry.sh` を作る。Claude は scratchpad に、リポジトリと同じ並び(`.claude/hooks/session-registry.sh`、`.claude/hooks/tests/test-session-registry.sh`、`.claude/scripts/parallel/lib.sh` の写し)を作り、その中でテストを流す。フックが `lib.sh` を `$(dirname "$0")/../scripts/parallel/lib.sh` で読み込み、テストがフックを `$(dirname "$0")/..` で探すためである。Claude は、scratchpad に作ったファイルを本来の場所に置く作業を、3.5 で所有者に頼む。
  - 完了の確かめ方: scratchpad のリポジトリと同じ並びの中で、`bash .claude/hooks/tests/test-session-registry.sh` の場合がすべて通る
  - 受入基準とテストの対応: 要件5の受入基準1と要件4の受入基準3(作業中のセッションを見分ける)は、テストの「SessionStart で記録ができ additionalContext にIDが出る」「SessionEnd で記録が消える」「cwd が worktree なら記録の folder が worktree になる」で確かめる。要件3の受入基準6(セッションが埋まっていることを報告する)は、テストの「UserPromptSubmit で記録が無ければ作る」で確かめる
  - _要件: 3.6, 4.3, 5.1_
  - _対象の部品: session-registry.sh_

- [ ] 2.7 作業の終わりのフックがそのセッションの作業フォルダを見るようにする (並行可)

  Claude は、部品「check-verify-before-stop.sh の変更」のとおりに直したフックと、そのテスト `test-check-verify-before-stop.sh` を、2.6 と同じく scratchpad のリポジトリと同じ並びの中に作り、その中でテストを流す。`record-gate-run.sh` を消すことも、3.5 で所有者に頼む。
  - 完了の確かめ方: scratchpad のリポジトリと同じ並びの中で、`bash .claude/hooks/tests/test-check-verify-before-stop.sh` の場合がすべて通る
  - 受入基準とテストの対応: 要件2の受入基準5(そのセッションの品質チェックだけを数える)は、テストの「cwd が worktree のとき worktree の変更と記録を見る」「本体フォルダの記録が新しくても worktree の変更が新しければ止める」で確かめる
  - _要件: 2.5_
  - _対象の部品: check-verify-before-stop.sh の変更_

- [ ] 3. スキルと設定をつなぐ
- [ ] 3.1 品質チェックのスキルを新しいスクリプトにつなぐ

  Claude は、部品「品質チェックと画面確認のスキルの変更」のとおり、`/verify-frontend` `/verify-backend` `/verify-terraform` と `.claude/commands/goal-fix-tests.md` の品質チェックと自動の直しのコマンドを `run-check.sh` 経由に変え、`/verify-all` の説明を合わせる。単発のテストや検査(`npx vitest run` や `./gradlew test` など)も `run-check.sh` で打つと書く。`--wait` を `run_in_background` で呼ぶときは、Bash の時間の上限を、待ちの上限(1800秒)とそのコマンドの実行時間の和より長くすると書く。Bash の時間の上限を長くするのは、`--wait` が、待ったあとに同じ呼び出しの中でコマンドを動かすためである(backend の `./gradlew check` では最悪で約40分になり、`run_in_background` の既定の30分では足りない)。
  - 完了の確かめ方: 3つのスキルと goal-fix-tests に、常駐コンテナへの `docker compose exec` が残っていない(`grep` で0件)。本体フォルダで `/verify-terraform` の手順を `run-check.sh` 経由で流すと、4つのコマンドがすべて合格する
  - 受入基準とテストの対応: 要件2の受入基準1(品質チェックはそのセッションの作業フォルダを検査する)、4(検査できないときは合格にしない)と、要件3の受入基準3(待っていることを示す)、5(待ちの上限で合格にしない)のスキルの側の扱いは、この完了の確かめ方と、5.1 の結合テストで確かめる
  - _要件: 2.1, 2.4, 3.3, 3.5_
  - _対象の部品: 品質チェックと画面確認のスキルの変更_
  - _依存: 2.1_

- [ ] 3.2 画面確認のスキルを新しいスクリプトにつなぐ

  Claude は、`/verify-ui` の開発サーバの起動と停止を `ui.sh start --session <ID>` と `ui.sh stop` に変え、Playwright で開く URL を `ui.sh` の出力から取るようにする。`ui.sh` の終了コード10・69・75の扱いは、品質チェックのスキルと同じにする。「自分が起動したdevサーバのプロセスを放置してよい」の決まりを消す。
  - 完了の確かめ方: `/verify-ui` に常駐コンテナへの `docker compose exec` が残っていない。本体フォルダで `/verify-ui` の手順を流すと、出された URL の画面を Playwright で開け、`ui.sh stop` のあと `docker ps --filter label=keirekipro.kind=ui` が空になる
  - 受入基準とテストの対応: 要件2の受入基準2(画面確認の画面にそのセッションの変更が出る)と、要件3の受入基準3(待っていることを示す)、5(待ちの上限で合格にしない)のスキルの側の扱いは、この完了の確かめ方と、5.1 の結合テストで確かめる
  - _要件: 2.2, 2.4, 3.3, 3.5_
  - _対象の部品: 品質チェックと画面確認のスキルの変更_
  - _依存: 2.2_

- [ ] 3.3 着手のスキルに調べと記録をつなぐ

  Claude は、部品「start スキルの変更」のとおり、`/start` に Step 1.5(`check-start` を呼び、JSON の欄ごとの表で問いとサブコマンドを決める)を足す。spec で進めるIssueでも、`/kiro-spec-init` を依頼する前にブランチを作って `claim` を呼ぶようにする。引き継ぎのあとでいまのブランチがIssueの記録のブランチと同じなら、Step 7 の手順1(最新の main からブランチを作る)を丸ごと飛ばすと明示する。Step 7 の手順1の「別の会話が作りかけの spec のフォルダなど」の例を消す。
  - 完了の確かめ方: `/start` の Step 1.5 の表が、design.md の start スキルの変更の表と同じ6行を持つ。一時的な worktree を2つ作り、片方で spec の作りかけを残した状態でもう片方から `check-start` を呼ぶと、表のどの行に当たるかを JSON から決められる
  - 受入基準とテストの対応: 要件4の受入基準1(作りかけが残っていれば止まる)、3(作業中のセッションがあれば、やめたかを尋ねる)、4(作業中のセッションが無ければ、続きから進めるかを尋ねる)、5(ブランチだけが残っていても止まる)、6(作りかけを失わずに引き継ぐ)、要件5の受入基準1(同じ作業フォルダの別のセッションで止まる)、2(やめたと答えたら続ける)、要件3の受入基準6(セッションが埋まっていることを報告する)の問いと進み方は、`test-session.sh` の check-start・prune・takeover の場合(2.3〜2.5)の出力を表に当てはめて確かめる
  - _要件: 1.1, 1.2, 3.6, 4.1, 4.3, 4.4, 4.5, 4.6, 5.1, 5.2_
  - _対象の部品: start スキルの変更_
  - _依存: 2.3, 2.5_

- [ ] 3.4 出荷のスキルと spec を始めるスキルを作業フォルダに依らない形にする

  Claude は、部品「ship と review-loop の変更」のとおり、`/ship` と `/review-loop` を直す。マージのメッセージのファイルは、`git rev-parse --git-path MERGE_MSG` を別のコマンドとして先に打ってパスを得てから、そのパスを指定してコミットする形にする。design.md は、マージのメッセージのファイルの指定を、コマンドの置き換え(`$(...)`)を使う形で書いている。Claude がこの形を採らないのは、`/ship` の手順4のとおり、コミットのコマンドが `settings.json` の許可にそのまま当たる形でないと auto mode の判定に回るためである(design の審査の D1-1-10)。Claude は、`/ship` と `/review-loop` が扱うPRの番号を `gh pr view --json number -q .number` で取るようにする。あわせて、Claude は、`/kiro-spec-init` が spec の名前の重なりを確かめるときに `session.sh spec-names` の一覧を使うように直す。
  - 完了の確かめ方: `/ship` に `.git/MERGE_MSG` の固定のパスも `$(git rev-parse` も残っていない。一時的な worktree で `git rev-parse --git-path MERGE_MSG` が worktree 用のパス(`.git/worktrees/<名前>/MERGE_MSG`)を返す。`/kiro-spec-init` の名前の確かめが、ほかの worktree の spec の名前も見る
  - 受入基準とテストの対応: 要件1の受入基準3(worktree の作業フォルダでも本体フォルダでも `/ship` を同じように終える)と4(そのセッションで出したPRだけを扱う)は、この完了の確かめ方と、所有者と一緒に行う通しの確かめ(実装のメモ)で確かめる。要件1の受入基準1の spec の名前の重なりは、`test-session.sh` の「spec-names がほかの worktree の spec の名前も出す」で確かめる
  - _要件: 1.1, 1.3, 1.4_
  - _対象の部品: ship と review-loop の変更_
  - _依存: 2.3_

- [ ] 3.5 設定とフックの置き換えを所有者に頼む

  Claude は、`.claude/settings.json` の変更(`session-registry.sh` を SessionStart・UserPromptSubmit・SessionEnd に登録し、`record-gate-run.sh` の登録を外し、新しいスクリプトの許可を足し、常駐コンテナへの品質チェック・単発のテスト・開発サーバの `exec` の許可を外す)を scratchpad に用意する。続けて Claude は、2.6 と 2.7 で作ったフックとテストと、この `settings.json` を置くコマンドと、`record-gate-run.sh` を消すコマンドを、所有者にまとめて示す。所有者が置いたら、Claude は置かれたフックのテストを本来の場所で流し、品質チェックの記録が `run-check.sh` だけから書かれることを確かめる。
  - 完了の確かめ方: 所有者が置いたあと、`bash .claude/hooks/tests/test-session-registry.sh` と `bash .claude/hooks/tests/test-check-verify-before-stop.sh` が通り、`.claude/hooks/record-gate-run.sh` が無く、`settings.json` に `record-gate-run.sh` も常駐コンテナへの品質チェックの `exec` の許可も無い。本体フォルダで `run-check.sh terraform checkov -d .` が合格すると `.claude/.state/gate-run-terraform.txt` が書き直され、`PATH` の先に必ず失敗する偽物の `docker` を置いて同じコマンドが終了コード69で終わったときは書き直されない
  - 受入基準とテストの対応: 要件2の受入基準5(そのセッションの品質チェックだけを数える)、要件3の受入基準6(セッションが埋まっていることを報告する)、要件5の受入基準1(同じ作業フォルダの別のセッションで止まる)のフックの側は、この完了の確かめ方で流すフックのテストと、記録の書き直しの確かめで確かめる
  - _要件: 2.5, 3.6, 5.1_
  - _依存: 2.6, 2.7, 3.1, 3.2_

- [ ] 4. 文書を書き直す
- [ ] 4.1 CLAUDE.md と steering を並行して進める前提に書き直す

  Claude は、部品「文書」のとおり、`CLAUDE.md` の「品質ゲート」の節と Git規約、スコープ別の CLAUDE.md、`.kiro/steering/tech.md` の品質チェックのコマンドと「直列実行・並列禁止」と「リポジトリルート」の記述を書き直す。
  - 完了の確かめ方: 5つの文書に、常駐コンテナへの品質チェックの `docker compose exec`、「並列実行禁止」「直列実行・並列禁止」、「ホストOSのリポジトリルートで実行する」が残っていない(`grep` で0件)
  - 受入基準とテストの対応: 要件6の受入基準4(作業フォルダが1つでセッションも1つだけ動くことを前提にした記述を書き直す)は、この完了の確かめ方の `grep` で確かめる
  - _要件: 6.4_
  - _対象の部品: 文書_

- [ ] 4.2 並行作業の運用の文書を書く

  Claude は、`doc/開発フロー/並行作業の手順.md` を書く。文書には、worktree を選んでセッションを開くこと、`git config keirekipro.parallelSlots <数>` での数の変え方と目安、最初に一度だけ行う準備(本体フォルダで `docker compose up -d`)、残った枠やコンテナを片付ける `session.sh prune`、`ui.sh` が使う `curl` が Git for Windows に同梱されていることを書く。
  - 完了の確かめ方: 文書に、上の5つの項目がそれぞれ見出しか箇条書きとしてある。数の目安の式が design.md の「文書」の部品の式と同じである
  - 受入基準とテストの対応: 要件6の受入基準2(最初に一度だけ行う準備の手順を運用の文書に書く)と3(並行して進めるときの所有者の操作を運用の文書に書く)は、この完了の確かめ方で確かめる
  - _要件: 6.2, 6.3_
  - _対象の部品: 文書_

- [ ] 5. 結合して確かめる
- [ ] 5.1 実際の Docker で2つの作業フォルダを並べて確かめる

  Claude は、本体フォルダと、scratchpad に作った一時的な worktree の2つで、実際の Docker を使って結合テストを流し、結果を記録する。backend の `./gradlew check` を2回順に走らせる確かめは10分を超えるので、Claude は Bash を `run_in_background` で動かす。テストのために壊したコードと、作った worktree・ボリューム・DB は、終わったら元に戻して片付ける。
  - 完了の確かめ方: 次の4つがすべて期待どおりになり、その出力を記録に残す。設定を一時的に2にし、worktree でだけテストを壊して2つで同時に frontend の品質チェックを走らせると、2つは待たずに同時に走り、worktree の側だけが失敗する(frontend の品質チェックは2つ同時でもメモリに収まる。確かめのあと、設定を1に戻す)。設定1で2つ同時に品質チェックを呼ぶと片方が終了コード10を返し、`--wait` で前の片方のあとに始まる。worktree で `ui.sh start` を打つと worktree の画面の変更が出て、`ui.sh stop` のあとも本体フォルダの常駐コンテナの開発サーバが動いている。設定1で2つ同時に backend の `./gradlew check` を走らせると、重ならずに順に走ってどちらも合格する
  - 受入基準とテストの対応: 要件2の受入基準3(壊した側のセッションだけが失敗する)と、要件3の受入基準2のうち設定の数に達していなければ待たずに始まる側と、要件3の受入基準4(同時に走っても失敗や合格が出ない)の同時に走る側は、「設定2で worktree でだけテストを壊す」で確かめる。要件3の受入基準2のうち設定の数に達していれば待つ側は、「設定1で2つ同時に呼ぶ」で確かめる。要件2の受入基準2(画面確認の画面にそのセッションの変更が出る)と要件1の受入基準5(ほかのセッションの開発サーバを止めない)は、「worktree で ui.sh start を打つ」で確かめる。要件3の受入基準4(同時に走っても失敗や合格が出ない)は、「設定1で2つ同時に backend の check を走らせる」で確かめる。worktree から `-p keirekipro run` で本体のプロジェクトの `dind` につながることも、この結合テストで確かめる
  - _要件: 1.5, 2.1, 2.2, 2.3, 3.2, 3.4_
  - _依存: 3.5_

## 実装のメモ

- `.claude/hooks/` と `.claude/settings.json` は Claude が書けない(`settings.json` の `deny`)。所有者が置くまで、Claude はそれらを本来の場所に書こうとしない
- マージまでは、所有者も Claude も、複数のセッションで作業を並行して進めない(design.md の「移行」)
- 着手から出荷までの通しの確かめ(2つの worktree のセッションで別々のIssueを `/start` から `/ship` まで進める)は、新しいスキルが main に入ってからでないとできない。マージのあと、Claude は、所有者と一緒に、この通しの確かめを1回行う
- design.md の「設計を見直すきっかけ」には、`VITEST_MAX_WORKERS` の基準の8が `compose.yaml` の `frontend` の環境変数に由来することが書かれていない(design の審査の D2-1-4)。`compose.yaml` の値を変えるときは、`run-check.sh` の割り算の基準も合わせて変える
- 1.1 で作った `lib.sh` の使い方の決まり: 枠を取る関数は、セッションのIDを環境変数 `KP_SESSION_ID`(`--session` の値)から受け取る。`kp_slot_holders` は1行ずつタブ区切りで「枠の番号、作業フォルダ、Issueの番号、種類、始めた時刻」を出す。取り戻しを単独で呼べる `kp_slot_reclaim` がある(2.4 の `prune` で使う)。`kp_json_write` は `キー=値` で文字列を、`キー:=JSON` で数や配列を書き、ファイルが既にあれば中身を残して書き足す。終了コード69の関数は `exit` で終わるので、呼ぶ側を止めたくないときはサブシェルで呼ぶ
- 2.1 で作った `run-check.sh` の決まり: frontend の準備は `kp_frontend_prepare <k>` で、結果を `KP_FRONTEND_ARGS` `KP_FRONTEND_PRE` `KP_FRONTEND_ERROR` に返す。コンテナの中の準備(`pnpm install`、`terraform init`)の失敗は終了コード197で見分け、外で69に読み替える。Docker のデーモンにつながるかは、枠を取ったあとに `docker version` で確かめる
- design.md の lib.sh の節の `kp_main_folder` の書き方は、design のサイクル3で、誤り(「`kp_state_dir` の親」は `.git` になる)から「git の共通ディレクトリの親、つまり本体フォルダ」に直っている。Claude は、`kp_main_folder` の実装を 1.1 で作ったとおりのままにし、変えない
- 2.3 の確認役の申し送り: `check-start` は、セッションのIDが空のときは、Issueの記録の `session_id` との照合で自分の作りかけを除かない(空どうしを同じとみなすと、閉じた前のセッションの作りかけを見落とすため)。作業フォルダのディレクトリが消えた worktree(git では prunable)は作業フォルダとして数えず、そこで開かれていたブランチは `branch_only` に出るが、git はそのブランチを開いたままとみなすので `git switch` が「already checked out」で失敗する。この食い違いは 2.4 の `prune` が手当てし、2.5 の `takeover --branch` では手当てしない
- 2.2 の確認役の申し送り: `ui.sh` は `run-check.sh` の内部の関数(`_kp_rc_print_holders` `_kp_rc_seconds`)を使うので、名前を変えるときは両方を直す。frontend の TCP の確かめ(1秒ごとに60回)は、node_modules のボリュームが空で `pnpm install` が長いと足りないおそれがあり、db を起こした直後の `psql` の確かめも失敗しうる。この2つの確かめで足りるかどうかは、3.2 と 5.1 の本物の docker での確かめで見る。

- 設計への書き足しの貯め方(所有者が 2026-10-05 に決めた): 実装で見つかった、design.md に書き足しが要る細部は、見つかるたびに design を直さず、この下の一覧に貯める。全タスクが終わったあと、出荷の前に、まとめて1回で design.md に書き足し、design と tasks の承認を1回でやり直す
- 設計への書き足しの一覧:
  - (2.3・2.4、tasks の審査の T3-1-2)Claude は、2.3 の確認役の申し送りに書いた、ディレクトリだけが消えた worktree の数え方と、2.4 の説明に書いた `prune` の最初の `git worktree prune` を、design の「作りかけの見つけ方」と、`prune` の箇条書きと「使う部品」に足す
  - (2.4 の確認役)`prune` が消すボリュームと DB の鍵は、記録(sessions の `folder_key`、issues の `folder`)からしか求めない。記録が先に消えた作業フォルダ(引き継いだ元、`/start` をしなかった worktree)の分は片付けから漏れる。Docker のボリュームの一覧から求めると、同じプロジェクト名の別の clone のボリュームを消すおそれがあるため、Claude は、記録から求める形を design に書き、漏れることを「失敗したときの扱い」か `prune` の節に書く
  - (2.3 の確認役)Claude は、2.3 の確認役の申し送りに書いた、セッションのIDが空のときの `check-start` の照合の扱いを、design の「作りかけの見つけ方」に書く
  - (tasks の審査の T1-1-8)Claude は、`ui.sh` が frontend の準備のために `run-check.sh` を読み込むことを、design の「使う既存の仕組み」の依存の向きに書く
  - (design の審査の D2-1-4)Claude は、実装のメモに書いた `VITEST_MAX_WORKERS` の基準の8の由来を、design の「設計を見直すきっかけ」に書く

## 完了条件(全タスク共通)

Claude は、どのタスクでも、タスクの箇条書きの欄を書いたうえで、次の4つを満たしたときにタスクを完了とする。

1. Claude は、タスクが満たす requirements.md の受入基準(要件の番号付きの項目)ごとに、それを確かめるテストのファイル名とテスト名を「受入基準とテストの対応」の行に書く。Claude は、確かめるテストの無い受入基準を残さない。
2. タスクで変えた領域の verify のスキル(`/verify-frontend` `/verify-backend` `/verify-terraform`)が、すべて成功している。
3. Claude は、テストを飛ばす設定、アサーションの削除、カバレッジや lint の対象からの除外を足して、完了条件を満たしたように見せない。CI の escape-hatch の検査が、これらの追加を機械で見つける。
4. Claude は、新しく書いたテストについて、テストの対象のコードを一時的に壊してテストが失敗することを確かめてから、コードを元に戻す。
