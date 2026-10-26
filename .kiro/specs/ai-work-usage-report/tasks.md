# タスク

- [ ] 1. 集計の決まりのデータと、テストに使う偽の gh を用意し、設計の前提を確かめる
- [x] 1.1 データのファイルを作る (並行可)

  Claude は、部品「usage-config.json」を、`.claude/scripts/usage/usage-config.json` に、design の「データの形」の節の欄のとおりに作る。Claude は、`prices` の値を、Anthropic の公式の価格のページを実装のときに読んで書き、読んだページの URL を `prices.source` に、読んだ日を `prices.checked_on` に書く。公式の価格のページに載っていないモデルと条件の価格を、Claude は推して書かない。Claude は、`wait_categories` `stage_marks` `roles` `ci_exclude_checks` を、design の「データの形」の節の値のとおりに書く。
  - 完了の確かめ方: `perl -MJSON::PP -e` でファイルを JSON として読め、`prices` `wait_categories` `stage_marks` `roles` `ci_exclude_checks` の5つの欄がある。`prices.models` の各モデルの価格が、`prices.source` のページの値と一致する。`stage_marks` が、design の「データの形」の節の7つの段階の対応と、`request` の印を、そのとおりに持つ
  - 受入基準とテストの対応: 要件3の受入基準4(待ちの分類)は、このファイルを読むタスク2.3のテストで確かめる。要件4の受入基準2(条件ごとに換算する)・受入基準3(価格の出どころと確かめた日を書く)・受入基準4(価格が分からないモデル)と、要件5の受入基準3(段階の名前)・受入基準5(モデルと役割の組ごと)は、このファイルを読むタスク4.4とタスク4.8のテストで確かめる
  - _要件: 3.4, 4.2, 4.3, 4.4, 5.3, 5.5_
  - _対象の部品: usage-config.json_

- [x] 1.2 テストに使う偽の gh を作る (並行可)

  Claude は、偽の gh の本体を、`.claude/scripts/usage/tests/fixtures/fake-gh.sh` に作る。テストは、テストごとの一時フォルダに `gh` の名前で `fake-gh.sh` を写し、その一時フォルダを PATH の先頭に置く。本体の名前を `.sh` にするのは、`.gitattributes` の LF の決まりと、shellcheck の対象の選び方(実装のメモ)に入れるためである。偽の gh は、テストごとの一時フォルダに置いた JSON のファイルを GitHub の代わりにし、design の部品が呼ぶ gh の呼び出しに答える。答える呼び出しは、`gh pr list`、PR のコミットの一覧を含む `gh pr view`、`gh issue view`、`gh issue list`、`gh issue comment --body-file`、`gh issue edit --body-file`、`gh issue create`、`gh issue close`、`gh issue lock`、Issue とコメントの一覧とコメントの作成と編集の `gh api`、`repos/{owner}/{repo}` の `permissions.push` の `gh api`、`commits/<sha>/check-runs` の `gh api` である。偽の gh は、呼ばれた引数を1行ずつ記録し、テストが指定した呼び出しを失敗させる。Claude は、偽の gh を、bash と perl(JSON::PP)だけで動くように書く。
  - 完了の確かめ方: 3つの環境(実装のメモ)のそれぞれで、`gh` の名前で写した偽の gh で Issue を作り、コメントを書き、読み直すと書いた中身が返る。テストが失敗を指定した呼び出しが、0 でない終了コードで終わる。`fake-gh.sh` に対する shellcheck(`koalaman/shellcheck:v0.11.0`)の指摘が0件である
  - 受入基準とテストの対応: このタスクは受入基準を直接は満たさない。GitHub に書く部品 github.pl のテスト(タスク3)、集計を作る部品 report.pl のテスト(タスク4)、集計の入口のコマンド usage.sh のテスト(タスク5)が、この偽の gh で受入基準を確かめる
  - _対象の部品: テストの fixtures_

- [x] 1.3 ターミナルの会話の記録で、権限の確認と補助役の記録の形を確かめる

  親の会話の Claude は、design の「テストの方針」の2つ目の「手で確認すること」のうち、会話の記録の欄を確かめる部分を行う。Claude は、所有者に、この作業フォルダでターミナルの Claude Code を起動し、権限の確認が出る道具の呼び出しを1つ承認し、補助役を1つ起動する会話を動かすよう、手順を示して頼む。会話が終わったら、Claude は、その会話の記録で、`permissionDecision.source` が `user_` で始まることと、補助役の記録の形(`agent-<id>.jsonl` と `agent-<id>.meta.json`)がデスクトップアプリの会話と同じことを確かめる。値が design の前提と違ったときは、Claude は実装を始めず、違った値と、design のどこに戻るかを所有者に示す。
  - 完了の確かめ方: Claude が、確かめた会話のセッションの ID と、`permissionDecision.source` の値と、補助役の記録のファイルの名前を、所有者に示している
  - 受入基準とテストの対応: 要件1の受入基準8(ターミナルの会話からも集計を作る)と要件3の受入基準2(所有者の返事の待ちを除く)の前提を、この確認で確かめる。抜き出した行の確認は、タスク8.2で行う
  - _要件: 1.8, 3.2_

- [ ] 2. 会話の記録から数と名前だけを抜き出す部品を作る
- [x] 2.1 全部の会話の記録を読む呼び出しの骨組みを作る (並行可)

  Claude は、部品「extract.pl」のうち、`--state <記録の置き場所> --all --skip-locked|--wait --repo <本体の作業フォルダ>` の呼び出しの骨組みを、`.claude/scripts/usage/extract.pl` に作る。骨組みは、design の「extract.pl」の節のとおりに、OS ごとの会話の記録の置き場所の候補、このリポジトリの会話の見分け方、記録の鍵ごとの `.pos`、ファイルが小さくなったときの読み直し、壊れた行を飛ばすこと、終了コードを持つ。骨組みは、このリポジトリの会話を、`cwd` の欄を持つ最初の行と `git worktree list` で見分け、見分けるときに、Windows の区切りと大文字と小文字を design のとおりに扱う。本体の作業フォルダの下の `.claude/worktrees/` にあった、消した worktree の会話も、`cwd` が本体の作業フォルダの下にあるので、骨組みはこの決まりで読む。骨組みは、`.pos` に、読んだバイト数、ファイルの大きさ、飛ばした行の数、抜き出した extract.pl の版の番号(`offset` `size` `skipped` `version`)を書く。extract.pl は、版の番号をスクリプトの中の定数で持つ。`.pos` の版の番号が今の版の番号と違う記録の鍵では、骨組みは、その記録の鍵の抜き出した記録を消して最初から読み直し、`.pos` に今の版の番号を書く。会話の記録のファイルが無い記録の鍵では、骨組みは、版の番号が違っても、抜き出した記録と `.pos` を残す。骨組みは、このタスクでは `meta` の行だけを抜き出し、錠は取らない。錠はタスク2.6で足す。あわせて、Claude は、テスト `.claude/scripts/usage/tests/test-extract.sh` を作る。テストは、HOME を一時フォルダに替えて、作り物の会話の記録を置く。
  - 完了の確かめ方: 3つの環境(実装のメモ)の `bash .claude/scripts/usage/tests/test-extract.sh` が、どれも失敗0件で終わる。`perl -c .claude/scripts/usage/extract.pl` が通る。shellcheck の指摘が0件である
  - 受入基準とテストの対応: 次の3つである
    - 要件1の受入基準8(ターミナルの会話からも集計を作る)と要件2の受入基準1(別に起こしたセッションの会話を入れる)は、テストの「最初の数行に cwd が無い記録でも cwd を持つ最初の行で見分け、Windows の \ で区切った cwd と git worktree list の / で区切った場所を同じ作業フォルダとして見分ける」で確かめる
    - 要件10の受入基準2(さかのぼりの集計の対象)は、テストの「git worktree list に無い、本体の作業フォルダの下の .claude/worktrees/<名前> を cwd に持つ記録も、このリポジトリの会話として抜き出される」で確かめる
    - 要件2の受入基準7(会話を漏らさずに記録に残す)は、テストの「2回続けて呼んでも行が重ならず、ファイルが短くなったら最初から読み直す」と「壊れた行を飛ばし、飛ばした数を .pos に残して 0 で終わる」と「.pos の版の番号が今の版と違う記録の鍵では、抜き出した記録を消して最初から読み直し、.pos の版の番号を書き直す。会話の記録のファイルが無い記録の鍵では、抜き出した記録と .pos が残る」で確かめる
  - _要件: 1.8, 2.1, 2.7, 10.2_
  - _対象の部品: extract.pl_

- [x] 2.2 応答の行と、上限と再試行の行を抜き出す

  Claude は、extract.pl に、`msg` `limit` `retry` `branch` `pr` の行を抜き出す部分を、design の「extract.pl」の節と「データの形」の節のとおりに足す。足す部分は、同じ `message.id` の扱い、`<synthetic>` の行の扱い、キャッシュの書き込みの5分と1時間の分け方、`fast` `us` `end` への置き換え、`api_error` の `retryInMs`、`gitBranch` と `prNumber` である。Claude は、テスト `test-extract.sh` に、このタスクの場合を足す。
  - 完了の確かめ方: 3つの環境(実装のメモ)の `test-extract.sh` が、どれも失敗0件で終わる。shellcheck の指摘が0件である
  - 受入基準とテストの対応: 次の5つである
    - 要件4の受入基準1(4種類に分ける)・受入基準2(条件ごとに換算する)は、テストの「同じ message.id の2行と synthetic の行から、トークン数が1回だけ抜き出され、書き込みが5分と1時間に分かれる」と「speed と inference_geo が fast と us になる」で確かめる
    - 要件3の受入基準2(所有者の返事の待ちを除く)は、テストの「end_turn が msg.end になる」で確かめる
    - 要件3の受入基準3(上限)・受入基準4(API の再試行の待ち)は、テストの「上限の印と API の再試行の時間が抜き出される」で確かめる
    - 要件1の受入基準8(ターミナルの会話からも集計を作る)は、テストの「entrypoint が cli の記録と claude-desktop の記録から、同じ形の行が抜き出される」で確かめる
    - 要件9の受入基準2(会話の文とファイルの中身を書かない)は、テストの「抜き出した記録に、会話の文、コマンドの文字列、ファイルの中身が入らない」で確かめる
  - _要件: 1.8, 3.2, 3.3, 3.4, 4.1, 4.2, 9.2_
  - _対象の部品: extract.pl_

- [x] 2.3 会話の相手と道具の行を抜き出す

  Claude は、extract.pl に、`turn` `tool` `result` の行を抜き出す部分を、design の「extract.pl」の節と「データの形」の節のとおりに足す。足す部分は、`turnOrigin` の置き換え(一覧に無い値の `unknown` と `raw`)、resume-after-usage-limit.sh の知らせの印 `[resume-after-usage-limit]` を含む `task_notification` の行の `limit` への置き換え、道具の種類、`perm`、`wait_categories` による待ちの分類、裏で動かした仕事の識別子である。extract.pl は、データのファイルを、自分と同じディレクトリの `usage-config.json` から読む。design の「ファイルの構成」が、2つのファイルを同じ `.claude/scripts/usage/` に置くためである。Claude は、テスト `test-extract.sh` に、このタスクの場合を足す。
  - 完了の確かめ方: 3つの環境(実装のメモ)の `test-extract.sh` が、どれも失敗0件で終わる。shellcheck の指摘が0件である
  - 受入基準とテストの対応: 次の5つである
    - 要件3の受入基準2(所有者の返事の待ちを除く)は、テストの「turnOrigin の3つの値が owner・peer・notice になり、一覧に無い値が unknown と raw になり、41文字以上と記号を含む値の raw が空になる」と「permissionDecision.source が user_ で始まる道具の perm が user になる」で確かめる
    - 要件3の受入基準3(上限)は、テストの「turnOrigin が task_notification で文が [resume-after-usage-limit] を含む行が、turn.from が limit の行になり、文が手元の記録に残らない」で確かめる
    - 要件3の受入基準4(待ち時間に入る時間)は、テストの「品質チェックのコマンドの道具が、その分類の名前で抜き出され、コマンドの文字列が残らない」で確かめる
    - 要件3の受入基準5(補助役の待ち)は、テストの「道具の名前が tool.kind になり、知らない名前が other になり、裏で動かした仕事の識別子が抜き出される」で確かめる
    - 要件9の受入基準2(会話の文とファイルの中身を書かない)は、テストの「抜き出した行に、元の欄の名前が残らない」で確かめる
  - _要件: 3.2, 3.3, 3.4, 3.5, 9.2_
  - _対象の部品: extract.pl_
  - _依存: 1.1_

- [x] 2.4 出来事と補助役の情報を抜き出す

  Claude は、extract.pl に、`stage` `recv` `merge` `spawn` `verdict` の行と、補助役の `meta` の行を抜き出す部分を足す。Claude は、`--all` の呼び出しが、補助役の記録も読むようにする。補助役の記録は、本体の会話の記録 `<sessionId>.jsonl` と同じフォルダの、`<sessionId>/subagents/` の下の `agent-<id>.jsonl` と `agent-<id>.meta.json` である(research.md)。テストの作り物の補助役の記録も、この場所に置く。Claude は、design の「extract.pl」の節のとおりに、extract.pl に次の3つの部分を作る。1つ目の部分は、段階の印を `stage_marks` に載った名前だけにする。2つ目の部分は、受け持ちとまとめの出来事を、結果が失敗でないときだけ残す。3つ目の部分は、補助役の報告を、最後の `assistant` の行の文と `SubagentHandback` の `input.message` のうち後にあるほうから読む。Claude は、テスト `test-extract.sh` に、このタスクの場合を足す。
  - 完了の確かめ方: 3つの環境(実装のメモ)の `test-extract.sh` が、どれも失敗0件で終わる。shellcheck の指摘が0件である
  - 受入基準とテストの対応: 次の5つである
    - 要件2の受入基準4(受け持ちの決まり)は、テストの「`session.sh claim 42 --branch feat/x` と `/start #42` と `gh issue close 7 --reason "not planned" --comment "#9 に統合した。"` から、受け持ちとまとめの出来事が抜き出される」と「失敗した結果の呼び出しからは出来事が抜き出されない」で確かめる
    - 要件6の受入基準3(数えるための記録を作業の途中で残す)は、テストの「確認役の `- VERDICT: REJECTED` と `NEXT_ACTION:` の行と、審査役の `STAGE: design` `CYCLE: 1` `ROUND: 2` が、最後の assistant の行の文で返した記録と SubagentHandback で返した記録の両方から抜き出される」で確かめる
    - 要件5の受入基準3(段階の名前)は、テストの「stage_marks に載ったスキルの名前だけが段階の印になる」で確かめる
    - 要件5の受入基準5(役割の名前)は、テストの「補助役の meta の行に agentType とモデルが入る」で確かめる
    - 要件2の受入基準1(別に起こしたセッションの会話を入れる)は、テストの「start_session の結果から local_<uuid> が抜き出される」で確かめる
  - _要件: 2.1, 2.4, 5.3, 5.5, 6.3_
  - _対象の部品: extract.pl_

- [x] 2.5 デスクトップアプリの手元の記録を読む

  Claude は、extract.pl の `--all` の呼び出しに、デスクトップアプリの手元の記録を読み、`extract/desktop.jsonl` に `local_<uuid>` と会話のセッションの対応を書く部分を、design の「呼び出し方」の欄のとおりに足す。手元の記録の置き場所の候補が1つも無いときは、extract.pl は `desktop.jsonl` を作らずに 0 で終わる。Claude は、テスト `test-extract.sh` に、このタスクの場合を足す。
  - 完了の確かめ方: 3つの環境(実装のメモ)の `test-extract.sh` が、どれも失敗0件で終わる。shellcheck の指摘が0件である
  - 受入基準とテストの対応: 要件2の受入基準1(別に起こしたセッションの会話を入れる)は、テストの「デスクトップアプリの記録の cliSessionId から desktop.jsonl に local と session の対応が書かれる」で確かめる。要件1の受入基準8(デスクトップアプリを入れていない PC でも集計を作る)は、テストの「デスクトップアプリの手元の記録の置き場所が無い PC で、desktop.jsonl を作らずに 0 で終わる」で確かめる
  - _要件: 1.8, 2.1_
  - _対象の部品: extract.pl_

- [x] 2.6 錠と、知らない値の行の書き直しを作る

  Claude は、extract.pl に、記録の鍵ごとの錠と、`--skip-locked` と `--wait` の扱いと、錠の中での `unknown` の行の書き直しを、design の「状態の持ち方」の欄のとおりに足す。extract.pl は、錠を `locks/extract-<記録の鍵>` の mkdir で取り、錠の時刻を10秒ごとに直し、60秒より古い錠を取り直す。`--wait` は、1つの記録の鍵につき600秒まで待つ。Claude は、テストのための上書き(実装のメモ)を足す。Claude は、テスト `test-extract.sh` に、このタスクの場合を足す。
  - 完了の確かめ方: 3つの環境(実装のメモ)の `test-extract.sh` が、どれも失敗0件で終わる。テストのための上書きが無いときの待つ時間と上限が、design の値と同じである。shellcheck の指摘が0件である
  - 受入基準とテストの対応: 要件1の受入基準5(集計は1回だけ)と要件2の受入基準7(会話を漏らさずに記録に残す)は、テストの「錠を持つ呼び出しがあるとき、--skip-locked はその記録の鍵を飛ばし、--wait は錠が外れてから最後まで読む」「--wait は上限を超えると 1 で終わる」「読んでいる間に錠の時刻が直り、古いとみなす時間を過ぎてもほかの呼び出しが錠を取り直さない」で確かめる。要件3の受入基準2(所有者の返事の待ちを除く)は、テストの「手元の記録に手で書いた unknown の行のうち、raw の値が extract.pl の値の一覧にある行が、--all で呼ぶと書き直され、その行の元の会話の記録のファイルが無くても書き直される」で確かめる。Claude は、このテストで、値の一覧を書き換えずに、古い extract.pl が書いた行を手で作って確かめる
  - _要件: 1.5, 2.7, 3.2_
  - _対象の部品: extract.pl_

- [x] 2.7 フックから呼ばれたときの動きを作る

  Claude は、extract.pl に、`perl extract.pl hook` の形の呼び出しを、design の「フックから呼ばれたとき」の表と箇条のとおりに足す。`PostToolUse` で呼ばれたときは、extract.pl は、入力を JSON として解かずに、3つの欄を `durations/<session_id>.tsv` に追記する。`Stop` `SessionEnd` `SubagentStop` で呼ばれたときは、extract.pl は、入力の会話の記録の続きを読む。`SessionStart` で呼ばれたときは、extract.pl は、裏で `--all --skip-locked` の呼び出しを起動する。extract.pl は、その呼び出しの `--state` に、入力の `cwd` から決めた記録の置き場所を渡し、`--repo` に、実装のメモの「本体の作業フォルダの求め方」の箇条で求めたフォルダを渡す。extract.pl は、`usage.sh session-context` を呼び、その出力をフックの出力の形に入れる。フックから呼ばれた extract.pl は、知らない `hook_event_name` で呼ばれたときは何もしない。フックから呼ばれた extract.pl は、失敗しても 0 で終わり、失敗の理由を `extract/errors.log` に残す。Claude は、テスト `test-extract.sh` に、このタスクの場合を足す。テストは、`SessionStart` の場合では、extract.pl と `usage-config.json` を一時フォルダに写し、隣に決まった行を出す作り物の `usage.sh` を置いて確かめる。
  - 完了の確かめ方: 3つの環境(実装のメモ)の `test-extract.sh` が、どれも失敗0件で終わる。`SessionStart` の場合で、テストがフックの終わりを裏の起動の終わりより先に見る。shellcheck の指摘が0件である
  - 受入基準とテストの対応: 要件2の受入基準7(会話を漏らさずに記録に残す)と要件3の受入基準2(権限の確認の待ちを除くための実行時間)は、テストの「PostToolUse で durations に1行足し、欄が足りない入力では何も書かずに 0 で終わる」「Stop と SessionEnd と SubagentStop で、その会話の記録の鍵だけを読み、錠を持つ呼び出しがあれば飛ばす」「知らない hook_event_name では何もせずに 0 で終わる」で確かめる。要件1の受入基準3(次の会話で出す)・受入基準6(出せなかったら次の会話で出し直す)は、テストの「SessionStart で session-context の行が additionalContext に入った1つの JSON として出る」「行が無いときは何も出さない」「10,000文字を超えると超える行が省かれ、省いたことを知らせる1行が最後に付く」で確かめる
  - _要件: 1.3, 1.6, 2.7, 3.2_
  - _対象の部品: extract.pl_

- [ ] 3. GitHub に集計と一覧と案の索引を書く部品を作る
- [ ] 3.1 書き手の確認と、出し済みかの確認を作る (並行可)

  Claude は、部品「github.pl」のうち、コメントと Issue の書き手の確認と、`reported <N>` を、`.claude/scripts/usage/github.pl` に、design の「github.pl」の節のとおりに作る。書き手の確認では、github.pl は、印で見つけるコメントと、題名で見つける一覧の Issue に限って、`author_association` が `OWNER` か `COLLABORATOR` かを確かめ、ほかの書き手のものを読み飛ばす。github.pl は、集計する Issue を起票した人を確かめない。`reported` は、Issue N のコメントのうち、書き手の確認を通り、集計のコメントの印 `keirekipro-usage-report:v1` を持つコメントがあるかを出す。Claude は、テスト `.claude/scripts/usage/tests/test-github.sh` を作る。テストは、偽の gh で、コメントと書き手の関係を返す。
  - 完了の確かめ方: 3つの環境(実装のメモ)の `bash .claude/scripts/usage/tests/test-github.sh` が、どれも失敗0件で終わる。`perl -c .claude/scripts/usage/github.pl` が通る。shellcheck の指摘が0件である
  - 受入基準とテストの対応: 要件9の受入基準4(ほかの人のコメントと Issue を使わない)と要件1の受入基準5(集計は1回だけ)と、要件7の受入基準1(出すたびに1行)のうち出したかの判断は、テストの「reported が、関係の欄の違う集計のコメントを出し済みとしない」と「reported が、関係の欄が COLLABORATOR の集計のコメントを出し済みとする」で確かめる
  - _要件: 1.5, 7.1, 9.4_
  - _対象の部品: github.pl_
  - _依存: 1.2_

- [ ] 3.2 一覧の Issue を見つけ、作り、ロックする部分を作る

  Claude は、github.pl に、書き込む前の `permissions.push` の確認と、一覧の Issue を見つける・作る・閉じる・ロックする・使い直す部分を、design の「github.pl」の節のとおりに足す。一覧の Issue を探すときは、github.pl は、タスク3.1の書き手の確認と、`locked` と、`state.json` の `list_issue` を確かめる。一覧の Issue を作る・閉じる・ロックするのは、書き込む呼び出しだけである。読むだけの呼び出し(`reported` `list-read` `proposals-open`)は、一覧の Issue を作らない。閉じることも、ロックすることもしない。`list-read` と `proposals-open` は、ロックしてある一覧の Issue が無ければ、一覧の行も案も無いものとして出す。github.pl は、`state.json` に書くときに、ファイルを読み直して `list_issue` の欄だけを替え、一時ファイルに書いてから名前を替えて置き換える。github.pl と `usage.sh owner` が `state.json` に同時に書いて片方の欄が消えても、集計は正しく出る。`list_issue` が消えたときは、github.pl が次の呼び出しで一覧の Issue を探し直す。`owner` が消えたときは、Claude が次の会話で、会話の相手が所有者かをまた尋ねる。Claude は、テスト `test-github.sh` に、このタスクの場合を足す。テストは、偽の gh で、Issue の書き手の関係とロックを返す。
  - 完了の確かめ方: 3つの環境(実装のメモ)の `test-github.sh` が、どれも失敗0件で終わる。shellcheck の指摘が0件である
  - 受入基準とテストの対応: 要件7の受入基準6(一覧は1つだけ)・受入基準7(ほかの人は一覧に書き込めない)と要件9の受入基準4(ほかの人のコメントと Issue を使わない)は、テストの「関係の欄が OWNER でも COLLABORATOR でもない、一覧の題名の Issue を読まず、編集しない」「関係の欄が OWNER のアカウントで作った一覧の Issue に COLLABORATOR のアカウントが行を足し、一覧の Issue が1つのまま」「関係の欄の違う一覧の Issue しか無いときは、一覧の Issue を作り、閉じ、ロックする」「ロックしていない一覧の Issue しか無いときは、ロックしてから使い、新しい Issue を作らない」「ロックに失敗したときは list_pending が残る」「permissions.push が偽のときは、書かずに 1 で終わり、一覧の Issue を作らない」「一覧の Issue が無いとき、reported と list-read と proposals-open が、偽の gh に Issue の作成とクローズとロックを頼まない」「state.json に owner があるときに list_issue を書くと、list_issue が書かれ、owner が残る」で確かめる
  - _要件: 7.6, 7.7, 9.4_
  - _対象の部品: github.pl_

- [ ] 3.3 一覧の行とページを書き、読み直して確かめる

  Claude は、github.pl に、一覧の行の作り方、書いたあとの読み直しと3回の書き直しと `list_pending`、`list-read`、`list-add <file>`、`list-ensure <N>` を、design の「github.pl」の節と「一覧の Issue」の見本のとおりに足す。github.pl は、一覧の行を終了日と番号の順に並べ、300行ごとにページを分け、1ページ目を本文に、2ページ目からを印の付いたコメントに書く。github.pl は、印の付いたページのコメントのうち、関係の欄が `OWNER` でも `COLLABORATOR` でもないコメントを読まず、編集しない。`list-read` は、一覧の行ごとに、Issue の番号、集計のコメントの URL、spec の有無、終了日、作業時間の秒、トークン数、使用料、実装中に spec へ戻った回数を、数の書き方の文字から数に戻して JSON で出す。実装中に spec へ戻った回数が「数えられない」の行では、`list-read` は、その回数を null で出す。タスク4.9の report.pl は、この形を `--list` で受ける。Claude は、テストのための上書き(実装のメモ)を足す。Claude は、テスト `test-github.sh` に、このタスクの場合を足す。
  - 完了の確かめ方: 3つの環境(実装のメモ)の `test-github.sh` が、どれも失敗0件で終わる。テストのための上書きが無いときの待つ時間が、design の値と同じである。shellcheck の指摘が0件である
  - 受入基準とテストの対応: 次の4つである
    - 要件7の受入基準4(終了日の古い順)は、テストの「一覧が301行になると2ページ目のコメントができ、終了日が古い行を足すと、ページの境目の行がずれて並ぶ」と「300行の一覧の本文が65,536文字に届かない」で確かめる
    - 要件7の受入基準5(同時に足しても消えず重ならない)は、テストの「書いたあとの読み直しで足した行が無いとき行を足し直し、3回やっても無ければ list_pending を書く」で確かめる
    - 要件7の受入基準2(列)・受入基準3(各行から集計を開ける)は、テストの「一覧の本文と続きのコメントが、一覧の Issue の見本の形で書かれ、各行が集計のコメントへのリンクを持つ」「list-ensure が、手で書いた集計のコメントの最後の数字の行の JSON から、一覧の Issue の見本の形の行を作る」「list-read が、見本の行から、数に戻した値と、数えられない行の null を出す」で確かめる
    - 要件7の受入基準7(ほかの人は一覧に書き込めない)と要件9の受入基準4(ほかの人のコメントと Issue を使わない)は、テストの「関係の欄が OWNER でも COLLABORATOR でもない keirekipro-usage-list:v1 page=2 のコメントの行を、list-read が出さず、list-add が並べ直しに入れない」で確かめる
  - _要件: 7.2, 7.3, 7.4, 7.5, 7.7, 9.4_
  - _対象の部品: github.pl_

- [ ] 3.4 集計のコメントと案の索引を書く

  Claude は、github.pl に、`publish <N> --draft --findings` と、書く前に本文が「データの形」の節の形だけからなることを確かめる部分と、案の索引のコメントと、`proposals-ensure`、`proposals-open`、`proposal-remove` を、design の「github.pl」の節と「集計のコメント」の見本のとおりに足す。`publish` は、`proposals_pending` を先に書き、そのあと集計のコメント、案の索引、一覧の順に書く。github.pl は、案の索引のコメントを1,000件ごとに分け、書いたあとに読み直し、空になったページを `[]` で残す。Claude は、テスト `test-github.sh` に、このタスクの場合を足す。テストは、手で書いた `report.json` と `report.md` と所見のファイルを使う。
  - 完了の確かめ方: 3つの環境(実装のメモ)の `test-github.sh` が、どれも失敗0件で終わる。shellcheck の指摘が0件である
  - 受入基準とテストの対応: 次の4つである
    - 要件7の受入基準2(列)・受入基準3(各行から集計を開ける)と要件8の受入基準2(案を所見に書く)と要件5の受入基準6(最後に所見)は、テストの「集計のコメントが、1行目の印、report.md、### 所見 と所見のファイル、最後の数字の行の順に組み立てられる」「案の索引のコメントが、一覧の Issue の見本の形で書かれる」「list-ensure が、publish の書いた集計のコメントの最後の数字の行の JSON から作った行が、publish が一覧に足した行と同じになる」で確かめる
    - 要件9の受入基準1(置く中身を限る)は、テストの「データの形の節の形に無い値を含む本文を、github.pl が書かずに 1 で終わる」で確かめる
    - 要件8の受入基準4(相手が所有者でないときは次の会話で尋ねる)・受入基準5(起票しないと答えた案は尋ねない)は、テストの「案の索引が一覧の本文に入らず、1,000件ごとに索引のコメントが分かれ、1,000件の索引のコメントが65,536文字に届かない」「proposal-remove で外した案が索引から外れ、proposals-ensure で戻らない」で確かめる
    - 要件8の受入基準4(相手が所有者でないときは次の会話で尋ねる)と要件9の受入基準4(ほかの人のコメントと Issue を使わない)は、テストの「関係の欄の違う案の索引のコメントの案を proposals-open が出さない」で確かめる
  - _要件: 5.6, 7.2, 7.3, 8.2, 8.4, 8.5, 9.1, 9.4_
  - _対象の部品: github.pl_

- [ ] 4. Issue ごとの集計を作る部品を作る
- [ ] 4.1 呼び出し方と、PR と、spec の有無と、仕組みが入った時刻を決める (並行可)

  Claude は、部品「report.pl」の呼び出し方(`--state --config --issue --out --list --backfill`、終了コード 0・2・1)と、手順「Issue の PR を集める」「Issue のブランチを集める」と、手順「開始日と終了日」のうち終了日の決め方を、`.claude/scripts/usage/report.pl` に、design の「report.pl」の節のとおりに作る。あわせて、Claude は、spec 無しの Issue の決め方(終了の時刻の main の spec.json と `switch-to-spec` の印)と、仕組みが main に入った時刻の決め方(design の「移行」の節の `git log` のコマンド)を、report.pl に作る。report.pl は、この時点で `report.json` に、Issue の番号、PR、終了日、spec の有無を書く。`--backfill` を受けたときの出力は、タスク4.8で足す。Claude は、テスト `.claude/scripts/usage/tests/test-report.sh` と、その作り物の手元の記録(extract.pl が書く形の行)を作る。テストは、一時フォルダに git のリポジトリを作り、`origin/main` に spec.json とデータのファイルを足したコミットを置き、偽の gh で PR と Issue の親子を返す。
  - 完了の確かめ方: 3つの環境(実装のメモ)の `bash .claude/scripts/usage/tests/test-report.sh` が、どれも失敗0件で終わる。`perl -c .claude/scripts/usage/report.pl` が通る。shellcheck の指摘が0件である
  - 受入基準とテストの対応: 次の3つである
    - 要件1の受入基準1(PR が2つ以上でも1つの集計)は、テストの「PR が2つの Issue で、終了日が Closes の PR のマージの日になる」と「マージせずに閉じた PR は終了日を決めない」で確かめる
    - 要件6の受入基準1(spec 無しの Issue の行)は、テストの「終了の時刻の main に Issue の番号を持つ spec.json が無い Issue を spec 無しとし、switch-to-spec の印がある Issue を spec ありとする」で確かめる
    - 要件6の受入基準4(「数えられない」と書くとき)は、テストの「仕組みが main に入った時刻が、データのファイルを足したコミットの時刻になる」で確かめる
  - _要件: 1.1, 6.1, 6.4_
  - _対象の部品: report.pl_
  - _依存: 1.2_

- [ ] 4.2 受け持ちの区切りから、Issue に入れる行を決める

  Claude は、report.pl の手順「受け持ちの区切りを作る」「1行ごとに Issue を決める」と、手順「開始日と終了日」のうち開始日と開始の時刻の決め方と、手順「記録が無い Issue」(Issue に決めた行が1つも無いときに 2 で終わる部分)を、design の「report.pl」の節のとおりに足す。Claude は、テスト `test-report.sh` に、このタスクの場合を足す。
  - 完了の確かめ方: 3つの環境(実装のメモ)の `test-report.sh` が、どれも失敗0件で終わる。shellcheck の指摘が0件である
  - 受入基準とテストの対応: 次の6つである
    - 要件2の受入基準1(本体と補助役と別に起こしたセッション)は、テストの「補助役の行と、desktop.jsonl で結び付いた別に起こしたセッションの行が、本体の Issue に入る」と「PR が2つの Issue で、2つのブランチの作業が1つの集計に入る」で確かめる
    - 要件2の受入基準2(/request を入れない)は、テストの「/request の印のあとの行が、どの Issue にも入らない」で確かめる
    - 要件2の受入基準3(1つの会話を Issue ごとに分ける)は、テストの「1つの会話が2つの Issue を続けて受け持つと、受け持ちの区切りで2つに分かれ、同じ行が2つの集計に重ならない」で確かめる
    - 要件2の受入基準4(受け持ちの決まり)は、テストの「分けた Issue で、親の区切りが最初に受け持った子に入る」と「まとめた Issue で、M の区切りが K に入る」で確かめる
    - 要件2の受入基準5(開始日)は、テストの「開始日が、初めて受け持った日になる」で確かめる
    - 要件1の受入基準4(記録の無い PC では集計しない)は、テストの「手元の記録に、その Issue に決まる行が1つも無いと 2 で終わる」で確かめる
  - _要件: 1.4, 2.1, 2.2, 2.3, 2.4, 2.5_
  - _対象の部品: report.pl_

- [ ] 4.3 作業時間を分けて数える

  Claude は、report.pl の手順「作業時間を数える」を、design の「report.pl」の節のその手順と、「処理の流れ」の図と9つの決まりのとおりに足す。report.pl は、作業時間から、所有者の返事の待ち、所有者に尋ねる道具、同期の補助役を待つ本体の時間、権限の確認の分、上限で止まった時間を除く。report.pl は、上限で止まった区間を、会話ごとに「処理の流れ」の3つの決まりで作り、その Issue のすべての会話の区間を重ねて、重なる区間と接する区間を1つにまとめる。上限で止まった時間は、まとめた区間の長さの合計で、上限で止まった回数は、まとめた区間の数である。report.pl は、待ちの分類と、補助役でない知らせと、API の再試行を、待ち時間にする。report.pl は、会話ごとの時間を合わせて、作業時間、待ち時間、同時に動いた時間、上限の回数と時間を `report.json` の `totals` に書く。report.pl は、`turn.from` が `unknown` の行の回数を `report.json` の `unknown_turns` に書く。Claude は、テスト `test-report.sh` に、このタスクの場合を足す。
  - 完了の確かめ方: 3つの環境(実装のメモ)の `test-report.sh` が、どれも失敗0件で終わる。shellcheck の指摘が0件である
  - 受入基準とテストの対応: 次の5つである
    - 要件3の受入基準1(同時の時間を1回だけ数える)は、テストの「2つの会話が重なった時間が作業時間に1回だけ入り、同時に動いた時間に入る」で確かめる
    - 要件3の受入基準2(所有者の返事の待ちを除く)は、テストの「応答の終わりのあと owner の行までの時間と、ask の道具の時間と、perm が user の道具の確認の時間(実行時間を引いた残り)が作業時間に入らない」と「turn.from が unknown の行までの時間が待ち時間に入り、unknown_turns に回数が出る」で確かめる
    - 要件3の受入基準3(上限)は、テストの「上限の印のあとの時間が作業時間に入らず、上限で止まった回数と時間が全体の合計に別に出る」と「msg.end が真の応答のあとに turn.from が limit の行が来た記録で、その間の時間が作業時間と待ち時間に入らず、上限で止まった回数と時間に入る」と、次の4つの記録で上限で止まった回数が1回になるテストで確かめる
      - 1つ目は、上限の印のすぐあとに turn.from が limit の行が来た記録である
      - 2つ目は、補助役の会話が上限の印で終わり、本体の会話に msg.end が真の応答と turn.from が limit の行がある記録である
      - 3つ目は、1つの会話に、msg.end が真の応答、turn.from が limit の行、上限の印、turn.from が limit の行の順に並ぶ記録である
      - 4つ目は、本体の会話と別に起こしたセッションの会話が、同じ時間に上限で止まった記録で、上限で止まった時間は、重なった時間を1回だけ数えた長さになる
    - 要件3の受入基準4(待ち時間に入る時間)は、テストの「品質チェックの分類に当たる道具の時間と、裏で動かした Bash の知らせを待った時間と、API の再試行の時間が待ち時間に入る」で確かめる
    - 要件3の受入基準5(補助役の待ち)・受入基準6(同時に動いた時間を作業時間に足さない)は、テストの「同期の補助役を待つ本体の時間が、本体にも同時に動いた時間にも入らず、補助役の側に入る。補助役が品質チェックを待った時間は待ち時間に入る」で確かめる
  - _要件: 3.1, 3.2, 3.3, 3.4, 3.5, 3.6_
  - _対象の部品: report.pl_

- [ ] 4.4 段階とモデルと役割ごとにトークン数と使用料を数える

  Claude は、report.pl の手順「段階を決める」「トークン数と使用料を数える」「役割を決める」を、design の「report.pl」の節のとおりに足す。report.pl は、`stage_marks` で段階を決め、印の無い時間を「その他」にし、`message.id` で重ならないようにトークン数を数え、`usage-config.json` の価格で使用料を換算し、価格が分からないモデルを使用料から除き、`report.json` の `stages` `models` `totals` に書く。Claude は、テスト `test-report.sh` に、このタスクの場合を足す。
  - 完了の確かめ方: 3つの環境(実装のメモ)の `test-report.sh` が、どれも失敗0件で終わる。shellcheck の指摘が0件である
  - 受入基準とテストの対応: 次の4つである
    - 要件5の受入基準4(合計の行が全体の合計と一致する)は、テストの「段階ごとの表の合計が全体の合計と一致し、印の無い時間が その他 に入る」で確かめる
    - 要件4の受入基準1(4種類に分ける)・受入基準2(条件ごとに換算する)・受入基準4(価格が分からないモデル)は、テストの「価格がデータのファイルに無いモデルの使用料が 価格が分からない になり、Haiku 5.5 の10万トークンを超える応答と fast と us の価格が当たる」と「2つの会話に同じ message.id があっても1回だけ数える」で確かめる
    - 要件5の受入基準3(段階の名前)は、テストの「spec-review の引数と、審査役と点検役の STAGE と、kiro-impl のあとの spec の直しが、それぞれの段階に入り、spec 無しの Issue では claim のあとが 実装 に入る」で確かめる
    - 要件5の受入基準5(モデルと役割の組ごと)は、テストの「本体の会話と、agent_type と verdict から決めた役割と、別に起こしたセッションが、モデルと役割の組ごとに分かれる」で確かめる
  - _要件: 4.1, 4.2, 4.4, 5.3, 5.4, 5.5_
  - _対象の部品: report.pl_
  - _依存: 1.1_

- [ ] 4.5 印と spec の記録と補助役の報告から、往復と手戻りを数える

  Claude は、report.pl の手順「往復と手戻りを数える」のうち、審査の STAGE と CYCLE と ROUND、`spec-fix` `same-failure` `switch-to-spec` の印、main の spec.json の `approval_history`、確認役の VERDICT、Issue の分割から数える行と、spec 無しの Issue の5つの行の扱いを、design の「report.pl」の節のとおりに足す。report.pl は、結果を `report.json` の `rework` に書く。Claude は、テスト `test-report.sh` に、このタスクの場合を足す。
  - 完了の確かめ方: 3つの環境(実装のメモ)の `test-report.sh` が、どれも失敗0件で終わる。shellcheck の指摘が0件である
  - 受入基準とテストの対応: 要件6の受入基準1(往復と手戻りの行)は、テストの「approval_history の、Issue #N のための更新でない要素から、前の段階に戻った回数と実装中に戻った回数が分かれて数えられる」「spec 無しの Issue で、spec に関わる行が無い」「分けた Issue で、分けた行が 有 になる」で確かめる。要件6の受入基準3(数えるための記録を作業の途中で残す)は、テストの「spec-fix と same-failure と switch-to-spec の印が、それぞれの行に数えられ、承認を取り消された段階の spec-fix の印は数えない」で確かめる
  - _要件: 6.1, 6.3_
  - _対象の部品: report.pl_

- [ ] 4.6 PR と CI と Codex レビューから、往復と手戻りを数える

  Claude は、report.pl の手順「往復と手戻りを数える」のうち、Codex レビューのコメント、CI の検査の結果、200行の検査、Codex の表から数える行を、design の「report.pl」の節のとおりに足す。report.pl は、CI の検査の結果のうち、`ci_exclude_checks` に載った検査と、`size-check` と、`codex-review` と、取り消された検査を除く。report.pl は、PR のコミットの一覧を `gh pr view` で、検査の結果を `gh api` の `check-runs` で読む。Claude は、テスト `test-report.sh` に、このタスクの場合を足す。
  - 完了の確かめ方: 3つの環境(実装のメモ)の `test-report.sh` が、どれも失敗0件で終わる。shellcheck の指摘が0件である
  - 受入基準とテストの対応: 要件6の受入基準1(往復と手戻りの行)は、テストの「マージせずに閉じた PR の size-check の失敗が1と数えられ、閉じた PR の CI の失敗と Codex レビューも数えられる」と「ci_exclude_checks の検査と取り消された検査の失敗を数えない」で確かめる。要件2の受入基準6(Codex レビューは往復の回数だけ)は、テストの「Codex レビューのコメントが往復の回数にだけ入り、使用料に入らない」で確かめる
  - _要件: 2.6, 6.1_
  - _対象の部品: report.pl_
  - _依存: 1.1_

- [ ] 4.7 数えられない行と、読めなかった記録を決める

  Claude は、report.pl の手順「往復と手戻りを数える」のうち「数えられない」と書く2つのときと、印の残らない会話の行の扱いと、読めない会話から数える5行の扱いと、手順「読めない会話を見つける」の4つの条件を、design の「report.pl」の節のとおりに足す。report.pl は、結果を `report.json` の `uncountable` と `partial_records` に書く。Claude は、テスト `test-report.sh` に、このタスクの場合を足す。
  - 完了の確かめ方: 3つの環境(実装のメモ)の `test-report.sh` が、どれも失敗0件で終わる。shellcheck の指摘が0件である
  - 受入基準とテストの対応: 要件6の受入基準3(仕組みが入ったあとはすべて数える)と受入基準4(「数えられない」と書く2つのとき)は、テストの「仕組みが main に入る前に受け持った Issue で、数えられない行が 数えられない になる」と「道具を使ったのに durations に行が無い本体の会話があると、印から数える3行が 数えられない になり、すべての本体の会話に durations の行があり印が無いときは 0 になる」と「.pos の飛ばした行の数が1以上の会話があると、design が挙げる5行が null になり、uncountable に出る」と「補助役の起動があるのに補助役の記録が無い会話があると、design が挙げる5行が null になり、uncountable に出る」で確かめる。要件2の受入基準8(読めない会話を黙って落とさない)と要件1の受入基準8(ターミナルの会話からも集計を作る)は、テストの「durations にセッションの ID があり、extract にその記録が無いとき、読めなかったことが記録される」「補助役の起動があるのに補助役の記録が無いとき、読めなかったことが記録される」「ターミナルで動かした会話だけで desktop.jsonl が無くても、読めなかったことが記録されない」「別に起こしたセッションの出来事があり、desktop.jsonl が無く、ブランチでも結び付けられないとき、読めなかったことが記録される」で確かめる
  - _要件: 1.8, 2.8, 6.3, 6.4_
  - _対象の部品: report.pl_

- [ ] 4.8 集計のコメントの本文を書き出す

  Claude は、report.pl の出力のうち、`report.md` と、`report.json` の残りの欄(`v` `prices` `backfill`)と、下書きを作った時刻のファイル `created_at` を、design の「データの形」の節のとおりに足す。Claude は、`report.md` の見出しと表の列と行の並びを design の「集計のコメント」の見本に合わせ、数を「数の書き方」の形で書き、注記を注記の箇条の順に並べる。タスク5.4の `publish` は、`created_at` で下書きの新しさを確かめる。report.pl は、`--backfill` を付けて呼ばれたときだけ `backfill` を真にし、注記の最初に、さかのぼりの集計の注記を書く。Claude は、テスト `test-report.sh` に、このタスクの場合を足す。
  - 完了の確かめ方: 3つの環境(実装のメモ)の `test-report.sh` が、どれも失敗0件で終わる。shellcheck の指摘が0件である
  - 受入基準とテストの対応: 次の4つである
    - 要件5の受入基準1(最初に開始日と終了日と spec の有無と全体の合計)・受入基準2(段階ごとの表)・受入基準3(段階の名前)・受入基準5(モデルと役割の組ごと)と、要件6の受入基準1(往復と手戻りの行)・受入基準2(起きなかった項目は 0 か無し)・受入基準4(「数えられない」と書く2つのとき)と、要件4の受入基準3(価格の出どころと確かめた日を書く)・受入基準4(価格が分からないモデル)と、要件2の受入基準8(読めない会話を黙って落とさない)は、テストの「作り物の記録から作った report.md が、集計のコメントの見本と同じ見出しと表の列と行の並びを持ち、数が数の書き方の形で書かれる」「spec 無しの Issue では、段階ごとの表が5行、往復と手戻りの表が7行になる」「注記は、条件に当たるものだけが注記の箇条の順に出て、どれにも当たらないときは見出しも出ない」で確かめる
    - 要件9の受入基準1(置く中身を限る)は、テストの「report.md に、作業時間・トークン数・使用料・回数・日付・番号・段階とモデルと役割の名前のほかの値が入らない」で確かめる
    - 要件1の受入基準5(集計は1回だけ)のための下書きの新しさの確認は、テストの「report.pl が、下書きのディレクトリに、作った時刻の created_at を書く」で確かめる
    - 要件10の受入基準5(さかのぼりの集計であることを書く)は、テストの「--backfill を付けて作った report.json の backfill が真になり、注記の最初に、さかのぼりの集計の注記が出る。--backfill を付けないと、backfill が偽になり、その注記が出ない」で確かめる
  - _要件: 1.5, 2.8, 4.3, 4.4, 5.1, 5.2, 5.3, 5.5, 6.1, 6.2, 6.4, 9.1, 10.5_
  - _対象の部品: report.pl_

- [ ] 4.9 過去との比べと、見分けられなかった値の一覧を書き出す

  Claude は、report.pl の出力のうち、`--list` で受けた一覧の行から作る `compare.json` と、`unknown.json` を、design の「データの形」の節のとおりに足す。report.pl は、`--list` のファイルを、タスク3.3の `list-read` の出力の形で読む。report.pl は、一覧の行のうち、この Issue より前に終わった行だけを、過去の行として比べる。この Issue より前に終わった行とは、終了日がこの Issue の終了日より前の行と、終了日が同じで Issue の番号がこの Issue より小さい行である。Claude は、テスト `test-report.sh` に、このタスクの場合を足す。
  - 完了の確かめ方: 3つの環境(実装のメモ)の `test-report.sh` が、どれも失敗0件で終わる。shellcheck の指摘が0件である
  - 受入基準とテストの対応: 次の3つである
    - 要件8の受入基準1(過去の行と比べる)は、テストの「compare.json で、過去の行が無いと past_rows が 0 になり、中央値が 0 の値の ratio が null になり、数えられない過去の行が中央値から除かれる」で確かめる
    - 要件8の受入基準1と要件10の受入基準4(終了日の古い順に集計し、前に終わった Issue の行と比べる)は、テストの「一覧に、この Issue より終了日の新しい行と、終了日が同じで番号の大きい行があっても、その行は past_rows にも中央値にも入らない」で確かめる
    - 要件3の受入基準2(所有者の返事の待ちを除く)は、テストの「unknown.json に raw の値ごとの回数が出て、report.json と report.md には raw の値が出ず、注記に回数と作業時間が長く数えられたことがあることが出る」で確かめる
  - _要件: 3.2, 8.1, 10.4_
  - _対象の部品: report.pl_
  - _依存: 3.3_

- [ ] 5. 集計の入口のコマンドを作る
- [ ] 5.1 記録の置き場所と、印と、案と所有者のサブコマンドを作る

  Claude は、部品「usage.sh」のうち、記録の置き場所(`<git-common-dir>/keirekipro-usage/`)の決め方、`--session <ID>`、終了コード(0・2・1 と日本語の1文)、`mark <spec-fix|same-failure|switch-to-spec> [--stage] [--issue]`、`pending`、`proposals`、`proposal <ID> filed|declined`、`owner yes|no` を、`.claude/scripts/usage/usage.sh` に、design の「usage.sh」の節のとおりに作る。`owner` は、`state.json` を読み直して `owner` の欄だけを替え、一時ファイルに書いてから名前を替えて置き換える。usage.sh は、JSON を読み書きするときに、bash の中から `perl -MJSON::PP` を呼ぶ。

  `pending` は、次の7つの決まりで Issue を出す。
  1. `pending` は、仕組みが main に入った時刻を、design の「移行」の節の `git log origin/main --first-parent --diff-filter=A` のコマンドで求める
  2. 仕組みが main に入った時刻を取れないときは、`pending` は、gh を呼ばずに、番号を1つも持たない JSON の1行を出して 0 で終わる
  3. 時刻を取れたときは、`pending` は、`gh issue list` が返した Issue を、`closedAt` が仕組みが main に入った時刻と同じかそれより後のものに絞る
  4. `pending` は、絞った Issue のうち、手元の抜き出した記録に受け持ちの出来事がある Issue だけを出す
  5. `pending` は、`issues/<N>.json` の集計しない印の `closed_at` が、いまの `closedAt` と同じ Issue を出さない
  6. `pending` は、出し済みの Issue のうち、`issues/<N>.json` に `list_pending` か `proposals_pending` がある Issue も出す
  7. `pending` は、閉じた時刻の絞り込みと、集計しない印の決まりを、`list_pending` か `proposals_pending` がある Issue にも当てる。さかのぼりの集計で出した Issue と出せなかった Issue の番号を、`pending` が出さないようにするためである

  Claude は、テスト `.claude/scripts/usage/tests/test-usage.sh` を作る。テストは、一時フォルダに git のリポジトリを作り、`origin/main` にデータのファイルを足したコミットを置き、偽の gh で動かす。
  - 完了の確かめ方: 3つの環境(実装のメモ)の `bash .claude/scripts/usage/tests/test-usage.sh` が、どれも失敗0件で終わる。shellcheck の指摘が0件である
  - 受入基準とテストの対応: 次の7つである
    - 要件6の受入基準3(数えるための記録を作業の途中で残す)は、テストの「mark が marks.jsonl に、時刻と会話と種類と段階と Issue とブランチの1行を足し、ほかの種類を受けない」で確かめる
    - 要件1の受入基準3(次の会話で出す)は、テストの「pending が、仕組みが入ったあとに閉じた Issue のうち出していないものを出し、gh issue list を1回だけ呼ぶ」「データのファイルを足したコミットと同じ日の、そのコミットより前の時刻に閉じた Issue を、pending が出さない」「origin/main にデータのファイルを足したコミットが無いとき、pending が番号の無い JSON の1行を出して 0 で終わり、偽の gh を呼ばない」「集計しない印の closed_at がいまの closedAt と同じ Issue を pending が出さず、closedAt が変わるとまた出す」「出し済みで list_pending か proposals_pending がある Issue を pending が出す」で確かめる
    - 要件10の受入基準7(さかのぼりの集計で出せなかった集計を次の会話で出し直さない)は、テストの「データのファイルを足したコミットより前に閉じた Issue と、集計しない印の system-pr がある Issue に list_pending があっても、pending が出さない」で確かめる
    - 要件1の受入基準4(PR を出した PC で集計する)は、テストの「手で作った抜き出した記録に受け持ちの出来事が無い Issue を、pending が出さない」で確かめる
    - 要件8の受入基準4(相手が所有者でないときは次の会話で尋ねる)は、テストの「owner が無い PC で owner yes を呼んだあと、proposals が、まだ答えていない案の ID と Issue の番号と案の文を出す」で確かめる
    - 要件8の受入基準5(起票しないと答えた案は尋ねない)は、テストの「proposal <ID> declined で答えた案を proposals が出さない」で確かめる
    - 要件8の受入基準4は、テストの「state.json に list_issue があるときに owner yes を呼ぶと、owner が書かれ、list_issue が残る」でも確かめる
  - _要件: 1.3, 1.4, 6.3, 8.4, 8.5, 10.7_
  - _対象の部品: usage.sh_

- [ ] 5.2 下書きを作るサブコマンドの、集計の対象かを確かめる部分を作る

  Claude は、usage.sh に、`draft <N>` を、design の「usage.sh」の節のとおりに足す。このタスクでは、Claude は、`draft` の錠と、「集計の対象か」の3つの手順と、閉じる PR の無い Issue の扱いを作る。`draft` は、Issue の錠 `locks/issue-<N>` の中で、次の順に動く。
  1. `draft` は、「集計の対象か」の手順1で、仕組みが main に入ったコミットを取る。コミットが無ければ、`draft` は、gh を呼ばずに 2 で終わり、`issues/<N>.json` にも書かない。`git fetch` が失敗したら、`draft` は 1 で終わる
  2. `draft` は、「集計の対象か」の手順2で、`Closes` か `Refs:` の PR の `mergeCommit` が仕組みが main に入ったコミットと同じ Issue に `skip: "system-pr"` を書いて 2 で終わる
  3. 閉じているのに閉じる PR の無い Issue では、`draft` は `skip: "no-merged-pr"` を書いて 2 で終わる。開いていて閉じる PR の無い Issue では、`draft` は何も書かずに 2 で終わる
  4. `draft` は、「集計の対象か」の手順3で、閉じる PR が仕組みが main に入る前にマージされた Issue に `skip: "before-system"` を書いて 2 で終わる。`git merge-base --is-ancestor` が 0 と 1 のほかの値で終わったら、`draft` は 1 で終わる

  `draft` は、`system-pr` と `no-merged-pr` と `before-system` の印を書くかを確かめるときに使う PR を、report.pl の手順「Issue の PR を集める」と同じ gh のコマンドで取る。`draft` は、取った PR のうち、本文の行頭に `Closes #<N>` か `Refs: #<N>` があり、`state` が `MERGED` か `CLOSED` である PR を、report.pl と同じ選び方で、`perl -MJSON::PP` で選ぶ。Claude は、タスク5.3で、出し済みかの確認を、仕組みが main に入ったコミットを取る動きと、`system-pr` の印を書くかを確かめる動きの間に足す。Claude は、タスク5.3で、集計を作る動きを、`before-system` の印を書くかを確かめる動きのあとに足す。タスク5.3を終えるまでは、上の4つの動きを終えて先へ進んだ Issue で、`draft` は集計しない印を書かずに 0 で終わる。Claude は、テストのための上書き(実装のメモ)を足す。Claude は、テスト `test-usage.sh` に、このタスクの場合を足す。このテストは、本物の github.pl を、偽の gh で動かす。
  - 完了の確かめ方: 3つの環境(実装のメモ)の `test-usage.sh` が、どれも失敗0件で終わる。テストのための上書きが無いときの錠の古さの上限が、design の値と同じである。shellcheck の指摘が0件である
  - 受入基準とテストの対応: 要件8の受入基準6(作業の途中では集計しない)は、テストの「開いていてマージ済みの Closes の PR が無い Issue で、draft が何も書かずに 2 で終わる」で確かめる。要件1の受入基準3(次の会話で出す)は、次の7つのテストで確かめる。要件1の受入基準9(#501 をマージのたびの集計に入れない)は、下の3つ目の、draft が system-pr の印を書くテストと、4つ目の、draft が before-system の印を書くテストで確かめる
    1. 「まとめて閉じた Issue と分けた元の Issue で、draft が集計しない印を書いて 2 で終わり、開き直して閉じ直すとまた pending に出る」
    2. 「origin/main にデータのファイルを足したコミットが無いとき、draft が issues/<N>.json に書かず、偽の gh を呼ばずに 2 で終わる」
    3. 「Refs: の PR の mergeCommit がデータのファイルを足したコミットと同じ Issue に、draft が system-pr の印を書いて 2 で終わり、次の pending がその Issue を出さない」
    4. 「閉じる PR がデータのファイルを足したコミットより前にマージされた Issue に、draft が before-system の印を書いて 2 で終わる。閉じる PR がデータのファイルを足したコミットより後にマージされた Issue には、draft が集計しない印を書かない」
    5. 「Refs: の PR だけがあって閉じる PR の無い閉じた Issue で、draft が git merge-base を呼ばずに no-merged-pr の印を書く」
    6. 「閉じる PR の mergeCommit が手元に無く、git merge-base --is-ancestor が 0 と 1 のほかの値で終わると、draft が 1 で終わる」
    7. 「git fetch が失敗すると draft が 1 で終わる」
  - _要件: 1.3, 1.9, 8.6_
  - _対象の部品: usage.sh_

- [ ] 5.3 下書きを作るサブコマンドの、集計を作る部分を作る

  Claude は、タスク5.2の `draft` に、design の「usage.sh」の節の残りの2つの動きを足す。
  1. `draft` は、仕組みが main に入ったコミットを取る動きのあと、`system-pr` の印を書くかを確かめる動きの前に、`github.pl reported` で出し済みかを確かめる。出し済みなら、`draft` は、一覧の行と案の索引を足し直して 2 で終わる
  2. `draft` は、「集計の対象か」の3つの手順を通った Issue で、`--repo` に実装のメモの「本体の作業フォルダの求め方」の箇条で求めたフォルダを渡して `extract.pl --all --wait` を呼び、`github.pl list-read` の出力を `report.pl --list` に渡して集計を作り、下書きを `drafts/<N>/` に書く。`draft` は、`compare.json` の要約と、`unknown.json` の値と回数を標準出力に出す。`extract.pl` が 1 で終わったら、`draft` は、report.pl を呼ばないまま 1 で終わり、下書きは作られない。途中までしか抜き出していない記録で集計を作らないためである

  下書きのディレクトリは、Issue ごとに `drafts/<N>/` の1つだけである。`draft` を呼び直すと、report.pl が同じディレクトリのファイルを書き直す。Claude は、テスト `test-usage.sh` に、このタスクの場合を足す。このテストは、本物の extract.pl と report.pl と github.pl を、偽の gh で動かす。
  - 完了の確かめ方: 3つの環境(実装のメモ)の `test-usage.sh` が、どれも失敗0件で終わる。テストの「draft を2回呼ぶと、drafts/<N>/ の created_at が2回目の時刻になる」が通る。shellcheck の指摘が0件である
  - 受入基準とテストの対応: 次の5つである
    - 要件1の受入基準5(集計は1回だけ)と要件2の受入基準8(読めない会話を黙って落とさない)は、テストの「裏の extract.pl --all --skip-locked が記録を読んでいる間に draft を呼んでも、集計の数が、裏の読み込みが終わってから呼んだときと同じになる」で確かめる
    - 要件3の受入基準2(所有者の返事の待ちを除く)は、テストの「unknown.json があるとき、draft が値と回数を標準出力に出す」で確かめる
    - 要件7の受入基準1(出すたびに1行)は、テストの「集計のコメントがあって一覧に行が無い Issue で、draft が一覧に行を足して 2 で終わる」で確かめる
    - 要件8の受入基準1(過去の行と比べる)は、テストの「draft が、一覧の過去の行と比べた compare.json の要約を出す」で確かめる
    - 要件2の受入基準7(会話を漏らさずに記録に残す)・受入基準8(読めない会話を黙って落とさない)は、テストの「extract.pl が 1 で終わると、draft が report.pl を呼ばずに、下書きを作らずに 1 で終わる」で確かめる。このテストは、テストのための上書きで錠を待つ上限を短くし、記録の鍵の錠を持ったままにして確かめる
  - _要件: 1.5, 2.7, 2.8, 3.2, 7.1, 8.1_
  - _対象の部品: usage.sh_

- [ ] 5.4 集計を出すサブコマンドを作る

  Claude は、usage.sh に、`publish <N> --findings <ファイル>` を、design の「usage.sh」の節の `publish` の7つの箇条のとおりに足す。`publish` は、Issue の錠の中で、出し済みかと下書きの新しさを確かめ、所見のファイルを確かめ、`github.pl publish` で出す。`publish` は、`drafts/<N>/` の下書きを読む。タスク5.3で作る `draft` は、下書きのディレクトリを Issue ごとに1つだけにする。そのため、`publish` が読む下書きは、いつも同じ Issue の最新の下書きである。`publish` は、`drafts/<N>/created_at` の時刻から60分以内の下書きだけを出す。下書きが古ければ、`publish` は、`draft` からやり直すよう返す。所見のファイルに、手元の場所、PC のユーザー名、`git config user.email` の値のどれかがあれば、`publish` は GitHub に書かずに 1 で終わる。集計のコメントを書けたら、`publish` は、`issues/<N>.json` に `reported_at` と `report_url` を書いて出し済みにし、`reported_at` の7日後の時刻を `list_checked_until` に書く。集計のコメントのあとの書き込みが失敗しても、`publish` は 0 で終わり、案の ID と `owner` を出す。`publish` は、一覧か案の索引に書けなかったときは、書けなかった書き込み(`list` か `proposals`、または両方)を出し、両方に書けたときは、書けなかった書き込みを空にして出す。Claude は、テストのための上書き(実装のメモ)を足す。Claude は、テスト `test-usage.sh` に、このタスクの場合を足す。このテストは、本物の report.pl と github.pl を、偽の gh で動かす。
  - 完了の確かめ方: 3つの環境(実装のメモ)の `test-usage.sh` が、どれも失敗0件で終わる。テストの「下書きを作ってから上限の時間を過ぎると、publish が GitHub に書かずに、draft からやり直すよう返す」と「publish が、issues/<N>.json に reported_at と、その7日後の list_checked_until を書く」が通る。テストのための上書きが無いときの下書きの新しさの上限が、design の値と同じである。shellcheck の指摘が0件である
  - 受入基準とテストの対応: 次の7つである
    - 要件1の受入基準5(集計は1回だけ)は、テストの「draft と publish の組を2つ同時に動かしても、集計のコメントは1つだけ書かれる」で確かめる
    - 要件9の受入基準2(会話の文とファイルの中身を書かない)は、テストの「所見に C:/Users/ を含むと、publish が書かずに 1 で終わる」で確かめる
    - 要件7の受入基準1(出すたびに1行)・受入基準2(列)は、テストの「publish が一覧に1行を足し、その行の値が、同じ Issue の report.md の値と同じ形で書かれる」で確かめる
    - 要件8の受入基準3(所有者に起票するかを尋ねる)は、テストの「state.json に owner が無いと、publish が owner に unknown を出す」で確かめる
    - 要件1の受入基準6(出せなかったら次の会話で出し直す)は、テストの「集計のコメントの書き込みが失敗すると publish が 1 で終わり、pending がその Issue を出し続ける」と「コメントのあとに索引か一覧の書き込みが失敗しても publish が 0 で終わって案の ID と owner を出し、次の draft が案を索引に、行を一覧に足し、proposal で答えた案は戻らない」で確かめる
    - 要件9の受入基準5(起票した人に関わらず集計する)は、テストの「関係の欄が NONE のアカウントが起票した Issue で、draft と publish が集計のコメントを書き、一覧に行を足す」で確かめる
    - 要件10の受入基準7(出せなかったことを会話の相手に書く)のための出力は、テストの「一覧の書き込みが失敗すると publish が書けなかった書き込みに list を出し、案の索引の書き込みが失敗すると proposals を出し、両方に書けたときは空を出す」で確かめる
  - _要件: 1.5, 1.6, 7.1, 7.2, 8.3, 9.2, 9.5, 10.7_
  - _対象の部品: usage.sh_

- [ ] 5.5 会話の始めに知らせる文を作る

  Claude は、部品「usage.sh session-context」を、usage.sh に、design の「usage.sh session-context」の節のとおりに足す。出してから7日の間の Issue とは、タスク5.4の `publish` が書いた `issues/<N>.json` の `list_checked_until` が、いまより後の Issue である。`session-context` は、`pending` と同じ手順で知らせる Issue を取り、出してから7日の間の Issue の一覧の行を `github.pl list-read` で確かめ、`state.json` の `owner` で所有者の行と案を足す。`session-context` は、gh で GitHub を読むだけにする。gh が失敗するか10秒を超えたら、`session-context` は何も出さずに 0 で終わる。仕組みが main に入った時刻を取れないときは、`session-context` は、gh を呼ぶ前に、出力を空のまま 0 で終わる。Claude は、テスト `test-usage.sh` に、このタスクの場合を足す。
  - 完了の確かめ方: 3つの環境(実装のメモ)の `test-usage.sh` が、どれも失敗0件で終わる。shellcheck の指摘が0件である
  - 受入基準とテストの対応: 次の4つである
    - 要件1の受入基準3(次の会話で出す)・受入基準6(出せなかったら次の会話で出し直す)は、テストの「session-context が、閉じた Issue だけを知らせ、gh が失敗したら何も知らせずに 0 で終わる」と「origin/main にデータのファイルを足したコミットが無いとき、session-context が何も出さずに 0 で終わり、偽の gh を呼ばない」で確かめる
    - 要件7の受入基準5(同時に足しても消えず重ならない)は、テストの「出してから7日の間の Issue の行が一覧に無いと、list_pending を書き直してその Issue を知らせる」で確かめる
    - 要件8の受入基準3(所有者に起票するかを尋ねる)・受入基準4(相手が所有者でないときは次の会話で尋ねる)は、テストの「owner が無く案があると、所有者かどうかがまだ決まっていないと知らせ、owner が偽の PC では案を知らせない」と「関係の欄の違う案の索引のコメントの案を知らせない」で確かめる
    - 要件1の受入基準7(コマンドを打つよう頼まない)は、テストの「知らせる文が、usage-report のスキルの手順を指し、所有者に打たせるコマンドを含まない」で確かめる
  - _要件: 1.3, 1.6, 1.7, 7.5, 8.3, 8.4_
  - _対象の部品: usage.sh session-context_

- [ ] 5.6 さかのぼりの集計の対象を出すサブコマンドを作る

  Claude は、usage.sh に、`backfill-list` を、design の「usage.sh」の節の `backfill-list` の7つの手順のとおりに足す。`backfill-list` は、`draft` と同じく、仕組みが main に入ったコミットを取り、コミットが無ければ gh を呼ばずに 2 で終わる。`backfill-list` は、`--repo` に実装のメモの「本体の作業フォルダの求め方」の箇条で求めたフォルダを渡して `extract.pl --all --wait` を呼び、手元の記録の `recv` と `stage` の行の Issue の番号と、`branch` の行の `name` と同じ `headRefName` を持つ PR が本文の行頭に書いた Issue の番号を、候補にする。`backfill-list` は、PR を、report.pl の手順「Issue の PR を集める」と同じ gh の呼び出しを1回だけ呼んで読み、`mergeCommit` が仕組みが main に入ったコミットと同じ PR が本文の行頭に書いた Issue を、候補に足す。`backfill-list` は、候補のうち、Issue を閉じる PR があり、仕組みを main に入れた Issue か、Issue を閉じる PR のうち最も遅くマージされたものが仕組みが main に入る前にマージされた Issue だけを残す。仕組みを main に入れた Issue に Issue を閉じる PR がまだ無いときは、`backfill-list` は、その番号を `waiting` に入れる。`backfill-list` は、手元の `issues/<N>.json` が出し済みで、`list_pending` も `proposals_pending` も無い Issue を除く。`backfill-list` は、残った Issue を、終了日の古い順に、終了日が同じなら番号の小さい順に並べる。終了日は、report.pl の手順「開始日と終了日」と同じく、Issue を閉じる PR のうち最も遅くマージされたものの `mergedAt` を、所有者の PC の時間帯の日付にしたものである。`backfill-list` は、`{"issues":[<番号>, ...],"waiting":[<番号>, ...]}` の1行を出して 0 で終わる。`git fetch` か gh が失敗したときと、`git merge-base --is-ancestor` が 0 と 1 のほかの値で終わったときは、`backfill-list` は 1 で終わる。Claude は、テスト `test-usage.sh` に、このタスクの場合を足す。このテストは、本物の extract.pl を、偽の gh で動かす。
  - 完了の確かめ方: 3つの環境(実装のメモ)の `test-usage.sh` が、どれも失敗0件で終わる。shellcheck の指摘が0件である
  - 受入基準とテストの対応: 次の5つである
    - 要件10の受入基準2(さかのぼりの集計の対象)・受入基準4(終了日の古い順)・受入基準6(出し済みの Issue を出し直さない)は、テストの「backfill-list が、usage-config.json を足したコミットより前にマージされた PR が閉じた Issue のうち、手元の記録に受け持ちかブランチの行がある Issue と、そのコミットの PR が本文に書いた Issue を、終了日の古い順に、終了日が同じなら番号の小さい順に出す。同じ日に、番号の大きい Issue を閉じる PR が先にマージされても、番号の小さい Issue が先に出る。Issue を閉じる PR がそのコミットよりあとにマージされた Issue と、手元の記録の無い Issue と、Issue を閉じる PR が無い Issue と、出し済みの Issue は出さない」で確かめる
    - 要件10の受入基準1(仕組みが main に入ったあとに行う)は、テストの「origin/main にそのコミットが無いとき、backfill-list が偽の gh を呼ばずに 2 で終わる」で確かめる
    - 要件10の受入基準2は、テストの「そのコミットの PR が本文に Refs: だけを書き、その Issue を閉じる PR がまだ無いとき、backfill-list がその番号を issues に入れず、waiting に入れる」でも確かめる
    - 要件10の受入基準2は、テストの「worktree の作業フォルダから backfill-list を呼んでも、git worktree list に無い、本体の作業フォルダの下の .claude/worktrees/<名前> を cwd に持つ記録の Issue が候補に入る」でも確かめる
    - 失敗のときの扱いは、テストの「偽の gh が失敗すると、backfill-list が 1 で終わり、標準出力に何も出さない」で確かめる
  - _要件: 10.1, 10.2, 10.4, 10.6_
  - _対象の部品: usage.sh_

- [ ] 5.7 下書きを作るサブコマンドに、さかのぼりの集計の形を足す

  Claude は、usage.sh の `draft` に、`--backfill` を、design の「usage.sh」の節の `draft <N> --backfill` の2つの違いのとおりに足す。`draft <N> --backfill` は、仕組みを main に入れた Issue と、Issue を閉じる PR のうち最も遅くマージされたものが仕組みが main に入る前にマージされた Issue だけを集計する。`draft <N> --backfill` は、タスク5.2の `draft` の4つの動きを、次のとおりに替える。
  1. 1つ目の動き(仕組みが main に入ったコミットを取る)は、`draft <N>` と同じである
  2. 2つ目の動きでは、`draft <N> --backfill` は、`skip: "system-pr"` とそのときの `closedAt` を `issues/<N>.json` に書いたあと、2 で終わらずに先へ進む
  3. 3つ目の動き(閉じる PR の無い Issue の扱い)は、`draft <N>` と同じである。そのため、仕組みを main に入れた Issue に、Issue を閉じる PR がまだ無いときは、`draft <N> --backfill` は、2つ目の動きで印を書いたあと、2 で終わる
  4. 4つ目の動きでは、`draft <N> --backfill` は、`skip: "before-system"` とそのときの `closedAt` を `issues/<N>.json` に書いたあと、2 で終わらずに先へ進む
  5. `system-pr` の印も `before-system` の印も書かなかった Issue では、`draft <N> --backfill` は、`issues/<N>.json` に書かずに 2 で終わる。この Issue は、Issue を閉じる PR が仕組みが main に入ったあとにマージされた Issue である

  `draft <N> --backfill` は、印を書いて先へ進んだ Issue で集計を続け、report.pl に `--backfill` を渡す。`issues/<N>.json` に印がすでにあっても、`draft <N> --backfill` は集計する。出し済みの Issue では、`draft <N> --backfill` は、`draft <N>` と同じく、一覧の行と案の索引を足し直して 2 で終わる。Claude は、テスト `test-usage.sh` に、このタスクの場合を足す。このテストは、本物の extract.pl と report.pl と github.pl を、偽の gh で動かす。
  - 完了の確かめ方: 3つの環境(実装のメモ)の `test-usage.sh` が、どれも失敗0件で終わる。shellcheck の指摘が0件である
  - 受入基準とテストの対応: 次の3つである
    - 要件10の受入基準2(さかのぼりの集計の対象)・受入基準3(要件2から6と要件9のとおりに集計を作り、1回だけ出す)と要件1の受入基準9(#501 をさかのぼりの集計でだけ集計する)は、テストの「draft <N> --backfill が、skip の before-system の印がある Issue でも下書きを作る。印の無い、仕組みが入る前に閉じた Issue では、before-system の印を書いてから下書きを作る。そのコミットの PR が本文に書いた Issue では、system-pr の印を書いてから下書きを作る。Issue を閉じる PR がそのコミットよりあとにマージされた Issue では、issues/<N>.json に書かずに 2 で終わる。--backfill を付けない draft は、Issue を閉じる PR が仕組みの入る前にマージされた Issue で、before-system の印を書いて 2 で終わる」と「そのコミットの PR が本文に Refs: だけを書き、その Issue を閉じる PR がまだ無いとき、draft <N> --backfill が system-pr の印を書いて 2 で終わる」で確かめる
    - 要件10の受入基準5(さかのぼりの集計であることを書く)は、同じテストで、draft <N> --backfill の下書きの report.json の backfill が真であることを確かめる
    - 要件10の受入基準6(出し済みの Issue を出し直さない)・受入基準7(出せなかった集計を次の会話で出し直さない)は、テストの「draft <N> --backfill のあとに publish が失敗した Issue を、次の pending が出さず、session-context もその Issue の文を作らない。仕組みが入る前に閉じた Issue と、そのコミットの PR が本文に書いた Issue の両方で確かめる。集計のコメントを書いたあとに一覧の書き込みが失敗した Issue も、次の pending は出さない。このとき、publish は 0 で終わり、書けなかった書き込みに list を出す。そのあとの backfill-list はその Issue を出し、draft <N> --backfill は一覧にその行を足して 2 で終わる」で確かめる
  - _要件: 1.9, 10.2, 10.3, 10.5, 10.6, 10.7_
  - _対象の部品: usage.sh_

- [ ] 6. 集計を出す手順のスキルを書く
- [ ] 6.1 usage-report のスキルを書く (並行可)

  Claude は、部品「usage-report のスキル」を、`.claude/skills/usage-report/SKILL.md` に、design の「usage-report のスキル」の節のとおりに書く。スキルは、5つの時点(マージを見届けたとき、次の会話で出すとき、案を尋ねるとき、所有者かを尋ねるとき、さかのぼりの集計を頼まれたとき)と、design の「usage-report のスキル」の節の、集計を出す「手順」の全部と、「さかのぼりの集計を頼まれたとき」の手順の全部と、design の「データの形」の節の「所見」の決まりと見本を載せる。「さかのぼりの集計を頼まれたとき」の手順では、Claude が、`usage.sh backfill-list` を呼び、出力の番号の順に `usage.sh draft <N> --backfill` と `usage.sh publish` を呼ぶ。この手順では、`draft` か `publish` が 1 で終わったときと、`publish` の出力に書けなかった書き込みがあったときに、Claude が残りの Issue を集計せずに止まる。この手順は、`waiting` の番号を会話の相手に書くことと、案を Issue ごとでなくまとめて、最後の `publish` の出力の `owner` で扱うことを含む。Claude は、スキルの文を `.kiro/settings/rules/owner-writing.md` の決まりで書く。
  - 完了の確かめ方: SKILL.md に、5つの時点の見出しと、`usage.sh draft` `publish` `proposals` `proposal` `owner` `backfill-list` と `draft <N> --backfill` を呼ぶ手順と、所見の決まりと見本がある。frontmatter の `name` が `usage-report` で、`description` が5つの時点を挙げている。frontmatter は、SKILL.md の先頭の `---` で囲んだ、スキルの名前と説明を書く欄である
  - 受入基準とテストの対応: 要件1の受入基準2(マージを見届けた会話で出す)・受入基準3(次の会話で出す)・受入基準6(出せなかったら次の会話で出し直す)・受入基準7(コマンドを打つよう頼まない)と、要件8の受入基準1から6(所見と直す案の扱い)と、要件5の受入基準6(最後に所見)と、要件9の受入基準3(所見で会話の文を引かない)と、要件10の受入基準1・3・4・6・7(さかのぼりの集計の手順)は、タスク7.2で足すテストの「usage-report の SKILL.md に、5つの時点の見出しと、usage.sh の draft・publish・proposals・proposal・owner・backfill-list と draft --backfill を呼ぶ行と、所見の決まりの見出しがある」で、手順があることを確かめる。Claude がその手順のとおりに動くことは、タスク8.3の、マージのあとの最初の集計を確かめる確認で確かめる。さかのぼりの集計の手順のとおりに動くことは、実装のメモの「さかのぼりの集計」のとおりに扱う
  - _要件: 1.2, 1.3, 1.6, 1.7, 5.6, 8.1, 8.2, 8.3, 8.4, 8.5, 8.6, 9.3, 10.1, 10.3, 10.4, 10.6, 10.7_
  - _対象の部品: usage-report のスキル_

- [ ] 7. 既存の手順と設定に、集計を出す時点と印を残す時点をつなぐ
- [ ] 7.1 既存のスキルと CLAUDE.md と構築の手順書を直す (並行可)

  Claude は、部品「ship・spec-review・start の SKILL.md と CLAUDE.md」の4つの変更を、design のその節のとおりに入れる。あわせて、Claude は、`doc/開発フロー/基盤構築手順.md` の「1. botアカウントの作成とPATの発行」の節に、bot のアカウントを替えるときも前のアカウントを共同作業者から外さないことと、外すと集計の一覧と集計のコメントを読まなくなることを足す。Claude は、ほかの文を変えない。
  - 完了の確かめ方: `git diff $(git merge-base origin/main HEAD) -- .claude/skills/ship/SKILL.md .claude/skills/spec-review/SKILL.md .claude/skills/start/SKILL.md CLAUDE.md doc/開発フロー/基盤構築手順.md` の違いが、design の節に書いた変更と手順書の足した文だけである。`bash .github/scripts/check-claude-md-size.sh` が通る
  - 受入基準とテストの対応: 要件1の受入基準2(マージを見届けた会話で出す)と要件6の受入基準3(数えるための記録を作業の途中で残す)は、タスク7.2で足すテストの「ship の SKILL.md の MERGED の行が usage-report の手順を指し、同じ失敗の3回目の箇所が mark same-failure を呼ぶ」「spec-review の SKILL.md が changed のときに mark spec-fix を呼ぶ」「start の SKILL.md の spec に切り替えるときの箇所が mark switch-to-spec を呼ぶ」「CLAUDE.md に mark same-failure の行と usage-report の行がある」で確かめる
  - _要件: 1.2, 6.3_
  - _対象の部品: ship・spec-review・start の SKILL.md と CLAUDE.md、`doc/開発フロー/基盤構築手順.md`_

- [ ] 7.2 フックと設定の完成版を作り、部品をつなぐテストを足す

  Claude は、部品「usage-hook.sh」を置き場所の `.claude/.state/ai-work-usage-report/place-1/hooks/usage-hook.sh` に、部品「settings.json の変更」を置き場所の `place-1/settings.json` に作る(実装のメモ)。usage-hook.sh は、標準入力をそのまま `perl "${CLAUDE_PROJECT_DIR}/.claude/scripts/usage/extract.pl" hook` に渡す。Claude は、今の `.claude/settings.json` を Read で読んで写しを作り、design の「settings.json の変更」の4つの項目だけを足す。足すフックのコマンドは、どれも `bash "${CLAUDE_PROJECT_DIR}/.claude/hooks/usage-hook.sh"` である。このタスクは、フックと設定とスキルと部品をつなぐ統合のタスクである。Claude は、テスト `test-usage.sh` に、次の4つを確かめる場合を足す。
  1. usage-hook.sh が標準入力をそのまま `extract.pl hook` に渡して標準出力を返し、extract.pl が失敗しても 0 で終わること。作業フォルダの最上位でないディレクトリから、`CLAUDE_PROJECT_DIR` に作業フォルダの最上位を入れて動かしても、extract.pl が動くこと
  2. settings.json に、design の「settings.json の変更」の登録と許可があり、足したフックのコマンドがどれも `bash "${CLAUDE_PROJECT_DIR}/.claude/hooks/usage-hook.sh"` であること。今ある登録と許可が残っていることは、テストではなく、完了の確かめ方の HEAD との違いで確かめる。検査用の写しには HEAD の settings.json と比べる元が無く、テストに写しの元を固定すると、settings.json が変わるたびにテストが古くなるためである
  3. タスク6.1の SKILL.md とタスク7.1の4つの文書が、受入基準とテストの対応の欄に書いた行を持つこと
  4. Claude Code が決めている欄の名前と値が extract.pl のほかに現れないこと
  - 完了の確かめ方: `place-1/settings.json` が JSON として読め、今のファイルとの違いが design の4つの項目だけである。検査用の写し(実装のメモ)で、3つの環境(実装のメモ)の4つのテストが、どれも失敗0件で終わる。検査用の写しの全 `.sh` を shellcheck にまとめて渡し、指摘が0件である
  - 受入基準とテストの対応: 次の5つである
    - 要件1の受入基準7(コマンドを打つよう頼まない)と要件2の受入基準7(会話を漏らさずに記録に残す)は、テストの「settings.json に、Stop・SubagentStop・SessionEnd・PostToolUse(matcher *)の async の登録と、SessionStart の timeout 10 の登録と、Bash(bash .claude/scripts/usage/usage.sh *) の許可がある」と、完了の確かめ方の「今のファイルとの違いが design の4つの項目だけである」で確かめる
    - 要件2の受入基準7(会話を漏らさずに記録に残す)と要件3の受入基準2(所有者の返事の待ちを除く)と要件6の受入基準3(数えるための記録を作業の途中で残す)は、テストの「usage-hook.sh が入力をそのまま extract.pl hook に渡して出力を返し、extract.pl が失敗しても 0 で終わる」で確かめる
    - 要件2の受入基準7(会話を漏らさずに記録に残す)と要件3の受入基準2(所有者の返事の待ちを除く)は、テストの「settings.json の完成版の、足したフックのコマンドが、どれも bash "${CLAUDE_PROJECT_DIR}/.claude/hooks/usage-hook.sh" である」と「usage-hook.sh を作業フォルダの最上位でないディレクトリから、CLAUDE_PROJECT_DIR に最上位を入れて動かすと、extract.pl が動いて durations/ に行が足される」でも確かめる
    - 要件1の受入基準2(マージを見届けた会話で出す)と要件6の受入基準3(数えるための記録を作業の途中で残す)は、タスク6.1とタスク7.1の受入基準とテストの対応の欄に書いたテストの名前で確かめる
    - 要件9の受入基準2(会話の文とファイルの中身を書かない)を守るために、Claude Code が決めている欄の名前と値を扱う部品を extract.pl の1つだけにしていることは、テストの「report.pl、github.pl、usage.sh、usage-config.json、usage-hook.sh に、stop_reason・turnOrigin・hook_event_name・cliSessionId・AskUserQuestion などの欄の名前と値が文字列として現れない」で確かめる
  - _要件: 1.2, 1.7, 2.7, 3.2, 6.3, 9.2_
  - _対象の部品: usage-hook.sh、settings.json の変更_
  - _依存: 2.7, 5.7, 6.1, 7.1_

- [ ] 8. 本来の場所に置いて確かめ、出荷のあとに最初の集計を確かめる
- [ ] 8.1 所有者に置いてもらい、本来の場所でテストを流す

  親の会話の Claude は、置き場所の `place-1/` の2つのファイル(`hooks/usage-hook.sh` と `settings.json`)を、`.claude/hooks/usage-hook.sh` と `.claude/settings.json` に写すコマンドを所有者に示して、置くよう頼む。依頼には、Claude が `.claude/settings.json` と `.claude/hooks/` に書き込めないこと(`settings.json` の `deny`)を添える。依頼には、置いたときから PR がマージされるまで、この作業フォルダの会話でフックが動き、会話の記録を抜き出すことも添える。仕組みが main に入るまでは、`usage.sh session-context` の出力は空になり、`usage.sh draft` は gh を呼ぶ前に 2 で終わる(design の「移行」の節)。所有者が置いたら、親の会話の Claude は、置いたファイルが置き場所の完成版と一致することを確かめ(実装のメモ)、本来の場所で、3つの環境(実装のメモ)の4つのテストと、shellcheck を流す。
  - 完了の確かめ方: `git status` に、置いた2つのファイルが出る。2つとも置き場所の完成版と一致する。置いた `.claude/settings.json` と、HEAD の `.claude/settings.json` との違いが、design の「settings.json の変更」の4つの項目だけである。本来の場所の4つのテストが、3つの環境(実装のメモ)のどれでも失敗0件で、shellcheck の指摘が0件である
  - 受入基準とテストの対応: 要件1の受入基準7・8(コマンドを打たせず、どの PC でも動く)と要件2の受入基準7(会話を漏らさずに記録に残す)は、本来の場所で、3つの環境(実装のメモ)のどれでも流した `test-usage.sh` の settings.json と usage-hook.sh の場合で確かめる
  - _要件: 1.7, 1.8, 2.7_
  - _保留: 親の会話の Claude が、`/kiro-impl` の Step 3 でタスクを1つずつ実装する繰り返しが終わったあと、Step 4 の `/kiro-validate-impl` を流す前に、所有者に置いてもらって進める_

- [ ] 8.2 ターミナルの会話の記録から、権限の確認と補助役の行が抜き出されることを確かめる

  親の会話の Claude は、タスク1.3で所有者に動かしてもらった会話の記録で、`extract.pl --all --wait` を動かし、`tool.perm` が `user` の行と、補助役の `meta` の行が抜き出されることを確かめる。Claude は、`--state` に scratchpad の一時フォルダを渡す。Claude は、本物の記録の置き場所(`<git-common-dir>/keirekipro-usage/`)に書かない。
  - 完了の確かめ方: Claude が、確かめた会話のセッションの ID と、抜き出した `tool.perm` の行と補助役の `meta` の行を、所有者に示している
  - 受入基準とテストの対応: 要件1の受入基準8(ターミナルの会話からも集計を作る)と要件3の受入基準2(所有者の返事の待ちを除く)は、この確認で、実際のターミナルの会話の記録から抜き出せることを確かめる
  - _要件: 1.8, 3.2_
  - _保留: 親の会話の Claude が、タスク8.1のあとに進める_

- [ ] 8.3 マージのあとの最初の集計を確かめる

  親の会話の Claude は、design の「テストの方針」の1つ目の「手で確認すること」を行う。Claude が確かめる会話は、この spec の仕組みが main に入ったあと、所有者の PC で、仕組みを main に入れた Issue のほかの Issue を閉じる PR のマージを最初に見届けた会話である。仕組みを main に入れた Issue では、`draft` が集計しない印を書いて集計を作らないためである。Claude は、その会話で、集計のコメントがその Issue に1つ出たことと、一覧の Issue に行が1つ足されたことと、集計のコメントと一覧の行の値が `drafts/<N>/report.md` の値と同じことを確かめる。
  - 完了の確かめ方: Claude が、集計のコメントの URL と、一覧の Issue の URL と、足された行を、所有者に示している
  - 受入基準とテストの対応: 要件1の受入基準2(マージを見届けた会話で出す)・受入基準7(コマンドを打つよう頼まない)と、要件7の受入基準1(出すたびに1行)と、要件8の受入基準1(過去の行と比べる)・受入基準2(案を所見に書く)・受入基準3(所有者に起票するかを尋ねる)と、要件9の受入基準3(所見で会話の文を引かない)は、この確認で、実際の会話で Claude がスキルのとおりに集計と所見を出したことを確かめる
  - _要件: 1.2, 1.7, 7.1, 8.1, 8.2, 8.3, 9.3_
  - _保留: この spec の PR がマージされたあと、所有者の PC で、仕組みを main に入れた Issue のほかの Issue を閉じる PR のマージを最初に見届けた会話で、Claude がタスク8.3を行う_

## 実装のメモ

- `.claude/settings.json` と `.claude/hooks/` の下は、Claude が書けない(`settings.json` の `deny`)。所有者が置くまで、Claude はそれらを本来の場所に書こうとしない。`.claude/scripts/`、`.claude/skills/`、CLAUDE.md、`doc/` は書ける
- `.claude/` の下のファイルは、`cp` や `cmp` で読むときも `deny` に止められることがある。Claude は、写しを作るときは Read と Write を使い、一致を確かめるときは、止められたら Read で両方の中身を読んで比べる
- 置き場所: Claude は、`.claude/hooks/usage-hook.sh` と `.claude/settings.json` の完成版を、作業フォルダの中の `.claude/.state/ai-work-usage-report/place-1/` に作る。`.claude/.state/` は git の管理外で、`deny` の対象に当たらない
- 検査用の写し: タスク7.2で、Claude は、作業フォルダを `git archive HEAD` で scratchpad の一時フォルダに写し、まだコミットしていない `.claude/scripts/usage/` と `.claude/skills/usage-report/` のファイルと、`place-1/` の2つのファイルを本来のパスで重ね、そこでテストと shellcheck を流す。まだリポジトリに無いファイルを `docker -v` で作業フォルダに重ねると、作業フォルダに0バイトのファイルが残るので、Claude はそうしない
- 3つの環境: Claude は、bash のテストを次の3つの環境で流す。テストの対象のフォルダは、タスク2からタスク6では作業フォルダ、タスク7.2では検査用の写し、タスク8.1では本来の場所である
  1. Git Bash: この PC の Git Bash で、テストを流す
  2. Linux のコンテナ: Claude は、テストの対象のフォルダを、`docker run --rm -v "<フォルダ>:/src:ro" alpine` で読むだけの形で渡し、コンテナの中で `/src` を別のフォルダに写してから、`apk add --no-cache bash perl git` のあとで同じテストを流す
  3. bash 3.2 のコンテナ: Claude は、テストの対象のフォルダを、`docker run --rm -v "<フォルダ>:/src:ro" bash:3.2` で読むだけの形で渡し、コンテナの中で `/src` を別のフォルダに写してから、`apk add --no-cache perl git` のあとで同じテストを流す。Docker の公式のイメージ `bash:3.2` は、Alpine の上の GNU bash 3.2.57 で、macOS の `/bin/bash` と同じ版である
- macOS で動く書き方: usage.sh、usage-hook.sh、テストのスクリプト、`fake-gh.sh` は、bash 3.2 にある機能と、macOS にあるコマンドの形だけを使う。時間の上限は perl の `alarm` で作り、`timeout` を使わない。macOS に `timeout` が無いためである。Claude は、`stat -c`(macOS は `-f`)、`date -d`(macOS は `-j -f` と `-v`)、引数の無い `sed -i`(macOS は `sed -i ''`)を使わない。`bash:3.2` のイメージは busybox のコマンドを持ち、`timeout` も持つので、3つの環境のテストでは、これらのコマンドの形の違いを見つけられないためである
- extract.pl の版: タスク8.1で所有者が置いたあとに、extract.pl が抜き出す行か値を変えたら、Claude は、extract.pl の版の番号を上げる。上げないと、置いたあとに抜き出した記録が、古い形のまま残るためである
- shellcheck: Claude は、CI の `guardrails.yaml` と同じく、`koalaman/shellcheck:v0.11.0` に、対象の `.sh` をまとめて渡す。対象は、`git ls-files -z --cached --others --exclude-standard '*.sh'` で選び、まだコミットしていない新しいファイルを含める
- テストのための上書き: extract.pl と github.pl と usage.sh は、design が決めた待つ時間と上限(錠を待つ600秒、錠を古いとみなす60秒、錠の時刻を直す10秒、一覧を読み直す前に待つ10秒、下書きを出せる60分)を、テストだけが使う環境変数で短くできるようにする。環境変数が無いときは、design の値で動く。テストが design の値のまま待つと、1回のテストに10分を超えるためである
- 所有者に作業を頼むのは、親の会話の Claude である。実装役の補助役は、所有者に依頼する手前で止まり、用意したもの(置き場所のパス)を親の会話に返す。確認役は、置く前の成果を置き場所のパスで確かめる。タスク7.2の成果の一部は置き場所にあり、`git diff` に出ないためである
- `_保留:_` のタスク: `/kiro-impl` は、自律で進めるときに、実装役を起動せずにタスク1.3とタスク8.1から8.3を飛ばす。親の会話の Claude は、Step 3 でタスクを1つずつ実装する繰り返しを始める前にタスク1.3を進め、確認が通ったら `_保留:_` の行を消して完了の印を付ける。親の会話の Claude は、Step 3 でタスクを1つずつ実装する繰り返しが終わったあと、Step 4 の `/kiro-validate-impl` を流す前に、タスク8.1と8.2を進め、テストと確認が通ったら `_保留:_` の行を消して完了の印を付け、コミットする。タスク8.3は、この spec の PR がマージされたあとに行うので、この spec の PR では `_保留:_` のまま出す
- 共通の完了条件の2(verify のスキル): この spec が変えるのは `.claude/`、CLAUDE.md、`doc/` だけで、frontend・backend・terraform を変えないので、当たる verify のスキルは無い。Claude は、代わりに、各タスクの完了の確かめ方の bash のテストと shellcheck を流す
- 共通の完了条件の1(確かめるテストの無い受入基準を残さない)には、次の例外がある。要件9の受入基準3(所見で会話の文を引かない)と、要件8の受入基準1から5のうち Claude が所見を書き案を尋ねる動き、要件1の受入基準2・7のうち Claude がスキルのとおりに動くことは、Claude の書く文と動きなので、テストで確かめられない。Claude は、これらを、タスク7.2のテストで手順があることを確かめ、タスク8.3の、マージのあとの最初の集計を確かめる確認で、実際の動きを確かめる。要件10の受入基準1・3・4・6・7のうち Claude がスキルのとおりに動くことは、下の「さかのぼりの集計」のとおりに扱う。要件1の受入基準8のうち macOS で動くことは、この PC で macOS を動かせないので、3つの環境(Git Bash、Linux のコンテナ、bash 3.2 のコンテナ)のテストと、上の「macOS で動く書き方」と、research.md に書いた macOS の記録の置き場所で代える
- さかのぼりの集計: さかのぼりの集計(要件10)を実際に行うことは、この spec のタスクにしない。所有者が、仕組みを main に入れる PR と、#501 を閉じる PR がマージされたあとに、会話でさかのぼりの集計を頼む(design の「移行」の節)。要件10の受入基準1・3・4・6・7のうち、Claude がスキルのとおりに動くことは、テストで確かめられないので、タスク7.2のテストで手順があることを確かめる。実際の動きは、所有者がさかのぼりの集計を頼んだ会話で、所有者が見る
- CI でこれらのテストを流すことは、この spec では作らない(design の「作らないもの」)。Claude は、出荷の報告で、CI で流す案を所有者に1行で示す
- 本体の作業フォルダの求め方: extract.pl と usage.sh は、`--all` の呼び出しの `--repo` に渡す本体の作業フォルダを、`git rev-parse --path-format=absolute --git-common-dir` が返すフォルダの親のフォルダとする。worktree の中では、`git rev-parse --show-toplevel` がその worktree の場所を返すので、その値を `--repo` に渡すと、消した worktree の会話を extract.pl が読まないためである。2026-10-25 に、このリポジトリの worktree の中で、`--git-common-dir` が本体の作業フォルダの `.git` を返すことを確かめた
- design の審査で「低」として記録した4つの点(D12-1-2、D12-1-3、D12-1-6、D12-1-7)は、Claude が次のとおりに作る
  - usage.sh は、git を、作業フォルダの最上位で動かす(`git -C "$(git rev-parse --show-toplevel)" …`)。Claude が Bash で `cd` したまま会話が要約されても、`usage-config.json` を足したコミットを見つけられるようにするためである
  - `pending` は、`closed:>=` に、仕組みが main に入った時刻を協定世界時に直した日付の、前の日を渡す。GitHub の検索がどの時間帯で日付を読んでも、仕組みが入った時刻より後に閉じた Issue を検索から落とさないためである。余分に返った Issue は、`closedAt` の絞り込みが除く
  - report.pl の開始の時刻は、受け持ちの出来事のうち最も早い時刻とし、受け持ちの出来事が無ければ Issue のブランチで最初に動いた行の時刻とする。開始日は、開始の時刻の日付である
  - `draft` の動く順と、`git merge-base --is-ancestor` の終了コードの扱いは、タスク5.2の `draft` の4つの動きのとおりに作る
- タスク1.3の確認(2026-10-26): ターミナルの会話 `bdb245fe-1c0d-4d7c-b621-9c54e2c846fe` で、所有者が権限の確認に答えた道具の呼び出しの `permissionDecision.source` は `user_temporary` だった。ターミナルの会話 `2e8c319f-d634-4289-8d97-18ec4d64ec20` で、補助役の記録は `subagents/agent-a039b4650efc270fb.jsonl` と `agent-a039b4650efc270fb.meta.json` だった。どちらも design の前提と同じである。ターミナルの Claude Code が auto mode で動くと、道具の呼び出しの `source` は `config` になり、所有者の返事の待ちは生じない
- 検査の名前: GitHub の検査の結果の名前は、ワークフローのジョブの `name` である。`rerun-approval-gated-checks.yaml` のジョブの名前は `rerun` なので、`ci_exclude_checks` は、design の5つの名前に加えて `rerun` を持つ。2026-10-26 に PR #620 から #622 の最後のコミットの検査の名前を読み、`update-pr-branches` `escape-hatch` `dependency-gate` `pre-merge-check` の名前が検査の結果の名前と同じことを確かめた
- 価格の名前の照らし方: report.pl は、モデルの ID が `prices.models` の名前と同じときか、名前のあとに `-` と8桁の日付だけが続くとき(例 `claude-opus-4-20250514` は `claude-opus-4`)に、その名前の価格を使う。どれにも当たらない ID は「価格が分からない」にする。頭が当たる名前のうち最も長いものを使う決まりにすると、`claude-fable-5-2` のような、価格を確かめた日より後に出たモデルに `claude-fable-5` の価格が付き、要件4の受入基準4に反するためである。タスク4.4か4.8のテストは、`claude-fable-5-2` が「価格が分からない」になる場合と、`claude-opus-4-20250514` が `claude-opus-4` の価格になる場合を持つ
- `stage_marks` の読み方: `request` の値は `null` なので、extract.pl は、印を残すかを、値が真かでなく名前があるか(`exists`)で決める。`verify-*` と `goal-*` の `*` は、名前の頭が同じものに当てる
- 名前で起動するスクリプトの1行目: テストが PATH の先頭に置いて名前で起動する偽のコマンド(`fake-gh.sh` を写した `gh` など)は、1行目を `#!/usr/bin/env bash` にする。`bash:3.2` のイメージは bash を `/usr/local/bin/bash` に置き、`/bin/bash` を持たないので、`#!/bin/bash` では起動できないためである(2026-10-26 にタスク1.2で確かめた)。`bash <ファイル>` の形で流すテストのスクリプトは、この限りでない
- 偽の gh の答え方: 偽の gh は、`--json` で知らない欄を頼まれると null を返し、`issues/<番号>/comments` の経路では Issue だけを探す(PR の番号は 404 になる)。タスク3からタスク5の部品が、PR の会話のコメントを `gh api` で読むときや、本物の gh が持たない欄の名前を書き間違えたときに気づくには、そのタスクで偽の gh に答えを足す
- Mythos 5.1 と Mythos 5: 価格のページにも、モデルの一覧のページにも、API のモデルの ID が無いので、`prices.models` に入れない。使われたときは「価格が分からない」になる
- 差分の照合: Claude は、差分を照合する前に `git fetch origin main` を流し、変えたファイルを `git merge-base origin/main HEAD` のコミットと比べる
- Windows の場所の見分け方: extract.pl は、ドライブ文字か `\\` で始まる場所を Windows の場所とみなし、`\` を `/` にそろえ、大文字と小文字を区別せずに比べる。design の「Windows では」を、Linux のコンテナのテストでも確かめられるように、OS でなく場所の形で決めたためである(タスク2.1)
- タスク2.1の確認役の助言: タスク2.2で抜き出した行を書き足すときは、書き足したあと `.pos` を書く前に止まっても、次の呼び出しで行が重ならない作りにする。extract.pl は、`--repo` の値を utf8 として解いてから cwd と比べる。Git Bash のテストには、HOME と USERPROFILE を別のフォルダにする場合を足す
- verdict の行の取り決め: extract.pl は、補助役の記録を読むたびに、その時点の報告の判定を `ts` 付きの verdict の行として書き足し、前に書いた判定を打ち消すときは `value` を null にした行を書く。補助役が動いている間に読むと、途中の文を報告として読むためである。report.pl(タスク4.4・4.5)は、記録の鍵ごとに最後の verdict の行だけを使い、`value` が null の行を判定なしとして読む(タスク2.4)
- 補助役のモデル: 起動のときにモデルを指定しなかった補助役の `agent-<id>.meta.json` には `model` が無い。report.pl は、そのときは補助役の msg の行のモデルを使う(タスク2.4)
- 続きから動かした確認役: 確認役が判定を返したあと、同じ補助役を続きから動かして別の判定を返すと、後の判定だけが残り、先の判定は数えられない。タスク2.4の確認役が、本物の記録で1件見つけた。`/kiro-impl` は差し戻しのたびに新しい確認役を起こすので、ふだんは起きない
- 最初の読み取りの時間: 2026-10-26 に、タスク2.4の確認役が、この PC の約1.4GB の記録を Git Bash の perl で最初から読むと、約15分かかった。design の「性能」は「数分」と見込んでいるので、Claude は、タスク5.2・5.3で `draft` の最初の1回の時間を確かめる

## 完了条件(全タスク共通)

Claude は、どのタスクでも、タスクの箇条書きの欄を書いたうえで、次の4つを満たしたときにタスクを完了とする。

1. Claude は、タスクが満たす requirements.md の受入基準(要件の番号付きの項目)ごとに、それを確かめるテストのファイル名とテスト名を「受入基準とテストの対応」の行に書く。Claude は、確かめるテストの無い受入基準を残さない。
2. タスクで変えた領域の verify のスキル(`/verify-frontend` `/verify-backend` `/verify-terraform`)が、すべて成功している。
3. Claude は、テストを飛ばす設定、アサーションの削除、カバレッジや lint の対象からの除外を足して、完了条件を満たしたように見せない。CI の escape-hatch の検査が、これらの追加を機械で見つける。
4. Claude は、新しく書いたテストについて、テストの対象のコードを一時的に壊してテストが失敗することを確かめてから、コードを元に戻す。
- 続きを読むときの途中の停止: extract.pl は、続きを読む前に、抜き出した記録の改行の無い最後の行を切り捨て、すでに書いた行と同じ行を書かない。ブランチは会話の記録の読み始めの位置より前から求める。止まったあとに読み直しても、抜き出した記録は一度に読んだときと同じになる。あとのタスクで抜き出す行の種類を足すときも、Claude は、同じ入力から同じ文字の列の行ができるように書く(同じ行かどうかを文字の列で見分けるため)
- 道具の行と古い版の記録: Claude Code は、`permissionDecision` を道具の呼び出しの行ではなく結果の行(`tool_result` を持つ `user` の行)に書く(research.md の書き方と違う。2026-10-26 にこの PC の記録 570 ファイルで確かめた)。そのため extract.pl は、`tool` の行を結果の行を読んだときに書き、読み始めの位置より前の呼び出しは記録を後ろから読んで探す。`turnOrigin` を持たない `user` の行(v2.1.275 までの所有者の行、今の版にもある `task-notification` の行、補助役の記録の `coordinator` の行)は、同じ値を `origin.kind` に `-` でつないで書くので、extract.pl は `turnOrigin` が無いときに `origin.kind` を読む。`coordinator` は値の一覧に無いので `unknown` の行になる。report.pl を作るタスクは、補助役の記録のこの行で `unknown` の数が増えることに気を付ける。extract.pl は、データのファイル `usage-config.json` を読めないときは、抜き出した記録を作らずに 1 で終わる
- デスクトップアプリの手元の記録: 確かめた置き場所は Windows の `%LOCALAPPDATA%\Claude-Data\claude_<id>\claude-code-sessions\<uuid>\<uuid>\local_<uuid>.json` だけである(2026-10-26 にこの PC の 119 ファイルで確かめた。`waiting-input/` の下の2つは `cliSessionId` を持たない)。公式の文書は置き場所を書いていないので、extract.pl はほかの OS の候補を持たない。ほかの OS では desktop.jsonl ができず、report.pl は別に起こしたセッションを結び付けられないので、design の決まりどおり「会話の記録の一部を読めなかった」と書く。desktop.jsonl には、今回このリポジトリの会話と見分けた鍵と、`.pos` がある鍵の対応を書く(会話の記録のファイルが消えても対応を残すため)。Git Bash の perl の `$^O` は `cygwin` なので、Windows だけのテストは `msys` と `cygwin` の両方で動かす
- 錠と書き直し: 錠を待つ上限・古いとみなす時間・時刻を直す間隔(600秒・60秒・10秒)は、テストだけが環境変数 `KP_USAGE_TEST_LOCK_WAIT` `KP_USAGE_TEST_LOCK_STALE` `KP_USAGE_TEST_LOCK_TOUCH` で短くする。読むのに時間のかかる呼び出しは、テストで `CORE::GLOBAL::readline` を1行ごとに待つ関数に替えて作る。unknown の行の書き直しは、書き直した行と同じ行がファイルのどこかにあれば、書き直した行を残さない(確認役が合格のときに挙げた直しを、合格のあとに入れた)。本物の `turn` の行の `ts` は UNIX 秒の数なので、テストで手で作る行も数で書く。古い錠を2つの呼び出しが同時に取り直す競り合いは、lib.sh の錠と同じく残る
- フックの呼び出し: PostToolUse は、入力の上の層の欄が最後に来る並びを前提に、session_id は最初の一致、tool_use_id と duration_ms は最後の一致を使う(道具の入力と応答の中に同じ名前の欄があるため)。フックの extract.pl は、標準エラーを先に捨て先へ向け、記録の置き場所が決まってから `extract/errors.log` へ向け直す。`exec` のあとに文を置くと Perl の警告が標準エラーに出るので、`{ exec(...) };` の形で囲む。Git Bash の perl では PERL5LIB の区切りが `:` なので、テストは `C:/` の形ではなく `/tmp` の形のパスを渡す。テストは、`PERL5OPT=-M<遅く読む部品>` で裏の呼び出しを遅らせ、フックの終わりが先に来ることを確かめる。usage.sh ができるまでは、会話の始めのフックは何も出さず、失敗を errors.log に残す
