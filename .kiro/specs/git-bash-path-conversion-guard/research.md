# 調査と設計の判断の記録

## 要約

- 機能: `git-bash-path-conversion-guard`
- 調査の広さ: 既存の仕組みへの追加(Claude Code の設定と、既存のテストの直し)
- 分かったこと:
  - Git Bash の引数の書き換えは、MSYS のプログラム(bash など)が MSYS でないプログラム(`git` `gh` `docker` `curl` `cmd`)を起動するときにだけ起きる。`perl` `sed` `grep` は MSYS のプログラムなので、書き換わった文字列を受け取らない
  - 引数の書き換えだけを止める変数 `MSYS2_ARG_CONV_EXCL` と、引数と一般の環境変数の両方の書き換えを止める変数 `MSYS_NO_PATHCONV` がある。Claude Code は、どちらも自分では設定しない
  - Claude Code の設定 `settings.json` の `env` は、Claude Code が起こすサブプロセス(Bash ツールのコマンド、フックのコマンドなど)のすべてに届く。ファイルを保存すると、動いているセッションにも反映される
  - 書き換えを止めると、`mktemp` が返す `/tmp/…` の形のパスを `git` に渡しているテスト `test-protect-main.sh` が2件失敗し、`C:\tmp` の下にリポジトリを作ってしまう

## 調べたこと

### Git Bash が引数を書き換える条件

- きっかけ: 要件1の1が「Git Bash がどの形の引数を書き換えるかに依らず」と決めたため、書き換えの条件と、止める手段を確かめた
- 見たもの:
  - git-for-windows/msys2-runtime の生ファイル(コミット 81d9bd3): `winsup/cygwin/spawn.cc`(394〜404行、289〜299行)、`winsup/cygwin/msys2_path_conv.cc`(347行、353〜398行)、`winsup/cygwin/environ.cc`(322〜332行、1224行、1354行)
  - https://www.msys2.org/docs/filesystem-paths/
  - https://github.com/git-for-windows/build-extra/blob/main/ReleaseNotes.md の Known issues
  - 手元の実測(Git for Windows 2.39.1、Claude Code の Bash ツール)
- 分かったこと:
  - `spawn.cc` は、起動するプログラムが MSYS のプログラムでないときにだけ、引数の1つずつに推測の書き換えを当てる
  - 何もしないとき、`/kiro-x` は `C:/Program Files/Git/kiro-x` に、`--title=/kiro-y` は `--title=C:/Program Files/Git/kiro-y` に書き換わる(実測。`git rev-parse --sq-quote` で、`git` が受け取った引数を表示した)
  - `MSYS2_ARG_CONV_EXCL` は引数だけを対象にする。値 `*` で、すべての引数を書き換えの対象から外す(`spawn.cc` 289〜299行)。実測で、`MSYS2_ARG_CONV_EXCL='*'` のとき `/kiro-x` `--title=/kiro-y` `/a:/b` `/foo:/bar` は書いたとおりに届いた
  - `MSYS_NO_PATHCONV` は Git for Windows だけの変数で、変数があるかどうかだけを見る(値が空でも `0` でも書き換えが止まる)。引数と、一般の環境変数(`NAME=/foo`)の両方の書き換えを止める
  - `PATH` `HOME` `TMP` `TEMP` `TMPDIR` などの8つの環境変数は、どちらの変数を設定しても別の経路で書き換わる
- 設計への影響: この spec の要件は引数だけを対象にするので、引数だけを止める `MSYS2_ARG_CONV_EXCL` を使う

### Claude Code の `settings.json` の `env`

- きっかけ: 作業PCごとの設定なしで、Claude が実行するすべてのコマンドに効く置き場所を探した
- 見たもの:
  - https://code.claude.com/docs/en/settings-reference.md の `### env` と「When Claude Code applies env values」「Variables Claude Code ignores in env」
  - https://code.claude.com/docs/en/env-vars.md の「In settings files」と `CLAUDECODE` の行
  - https://code.claude.com/docs/en/setup.md の「Set up on Windows」
  - https://code.claude.com/docs/en/hooks.md
  - https://github.com/anthropics/claude-code/issues/91771 、#96632 、#74033
- 分かったこと:
  - `env` の値は、Claude Code が起こすサブプロセスのすべてに届く。サブプロセスには、Bash ツールのコマンドとフックのコマンドが含まれる
  - ファイルを保存すると、動いているセッションの環境にも反映される。ただし、ファイルから消した変数は、動いているセッションでは消えない
  - プロジェクトの設定は、所有者が作業フォルダを信頼したあとに当てられる
  - Claude Desktop アプリが起動したセッションでは、アプリが作る起動の環境がすでに設定している変数について、`env` の値は無視される。このセッションでは `MSYS2_ARG_CONV_EXCL` も `MSYS_NO_PATHCONV` も設定されていない(実測)
  - Claude Code は、Bash ツールの環境に MSYS の変数を設定しない(実測と #91771)
- 設計への影響: `.claude/settings.json` の `env` に変数を置けば、リポジトリの内容だけで、Bash ツールとフックの両方に届く。サブエージェントの Bash ツールに届くことは文書に明記が無いので、実装のときに実測で確かめる

### 書き換えに頼っている既存のコマンド

- きっかけ: 要件2(今の作業を壊さない)のために、書き換えを止めたときに壊れるものを探した
- 見たもの: `.claude/skills/` `.claude/scripts/` `.claude/hooks/` `CLAUDE.md` `start-dev.sh` `doc/` の、`/` で始まる引数と `mktemp` の使い方
- 分かったこと:
  - `.claude/scripts/parallel/lib.sh`(21行目)と `start-dev.sh`(9行目)は、自分で `MSYS_NO_PATHCONV=1` を設定している。これらは、もとから書き換えを止めた状態で動いている
  - `.claude/scripts/parallel/tests/` のテストと、`.claude/hooks/tests/` の `test-check-verify-before-stop.sh` `test-session-registry.sh` は、`mktemp -d` の結果を `pwd -W` でドライブ文字の形に直してから使っている
  - `.claude/hooks/tests/test-protect-main.sh` は、`mktemp -d` が返す `/tmp/…` の形のパスを、そのまま `git init` と `git -C` に渡している。書き換えを止めて流すと、`git` がそのパスを `C:\tmp\…` と読み、2件が失敗した(実測。成功50件、失敗2件)
  - `.claude/hooks/tests/test-spec-review-scan.sh` は、書き換えを止めても9件すべて通った(実測)
  - `/ship` と `file-issue` は、コミットメッセージと Issue の本文を scratchpad のファイルに書いて渡す。scratchpad のパスはドライブ文字の形なので、書き換えに頼っていない
  - `doc/開発フロー/基盤構築手順.md` と `.claude/settings.json` の許可にある `docker compose exec -w /home/spring/app …` は、今は書き換えのせいで失敗する形であり、書き換えを止めると通るようになる
- 設計への影響: `test-protect-main.sh` を、ほかのテストと同じく `pwd -W` で直す

## 比べた作り方

| 案 | 中身 | よい点 | 弱い点 |
|---|---|---|---|
| A. `settings.json` の `env` に `MSYS2_ARG_CONV_EXCL=*` を置く | Claude Code が起こすすべてのサブプロセスで、引数の書き換えを止める | リポジトリの内容だけで効く。コマンドの文字を読まないので、書き方による漏れが無い。引数だけを止める | パスのつもりで `/c/…` や `/tmp/…` を Windows 向けのプログラムに渡すと、そのプログラムが失敗する |
| B. `settings.json` の `env` に `MSYS_NO_PATHCONV=1` を置く | Aと同じ置き場所で、引数と一般の環境変数の両方の書き換えを止める | リポジトリの `lib.sh` と同じ変数で揃う | 要件より広く、環境変数の書き換えまで止める。値を見ないので、`0` を書いても止まる |
| C. 実行の前のフックで、書き換わる形の引数を含むコマンドを止める | `protect-main.sh` と同じく、コマンドの文字を読んで止める | 止めた理由と書き直し方を Claude に返せる | 引用符、ヒアドキュメント、`$(...)`、変数の展開を正しく読めず、すり抜けと誤った停止が残る。Claude の作業が止まる回数が増える |
| D. 実行の前のフックで、コマンドの頭に変数を足して書き換える | フックが Claude のコマンドの文字を書き換えてから実行させる | Claude の書き方を問わない | 書き換えたコマンドが許可の一覧と `protect-main.sh` の形の判定に当たらなくなるおそれがある。Aと同じ結果を、より壊れやすい形で作る |
| E. 起票とPRの作成のあとに、題名を読み直して確かめる | `/ship` と `file-issue` の手順に確かめを足す | 作るものが少ない | 手順を読むかどうかに頼るので、メモリに頼る今の状態と変わらない。コミットメッセージなど、ほかのコマンドを覆えない |

## 設計の判断

### 判断: `settings.json` の `env` で引数の書き換えを止める

- きっかけ: 要件1、要件3
- 比べた案: 上の表のAからE
- 選んだ作り方: A。`.claude/settings.json` に `"env": { "MSYS2_ARG_CONV_EXCL": "*" }` を置く
- 理由: Claude Code が起こすサブプロセスのすべてに、作業PCごとの設定なしで効く。コマンドの文字を読まないので、書き方による漏れが無い。引数だけを止めるので、要件の範囲と合う
- 引き換えにするもの: Claude がパスのつもりで `/` で始まる形を Windows 向けのプログラムに渡すと、そのプログラムが失敗する。要件1の6は、この失敗を受け入れ、Claude が書き直すと決めている
- 実装のときに確かめること: サブエージェントの Bash ツールに変数が届くこと。所有者が `settings.json` を置いたあとに、セッションの Bash ツールで変数が見えること

### 判断: 止める手段(案C)を作らない

- きっかけ: 要件1の5
- 選んだ作り方: Claude のコマンドを止める手段を作らない。要件1の5は、止める手段があるときだけの決まりなので、この設計では使われない
- 理由: 案Aでは書き換えが起きないので、止める理由が無い

### 判断: Windows 向けのプログラムに渡すパスの書き方を CLAUDE.md に書く

- きっかけ: 要件1の6
- 選んだ作り方: CLAUDE.md の Git規約に、書き換えを止めてあることと、Windows 向けのプログラムにはドライブ文字の形か相対の形でパスを渡すことを、1つの項目で書く
- 理由: Claude は、失敗を見てから書き直せる。ただし、CLAUDE.md は毎回読み込まれるので、書き直す回数を減らせる。書き換えを防ぐこと自体は案Aが受け持ち、この項目には頼らない

## 危険と手当て

- Claude Desktop アプリの起動の環境が、あとで `MSYS2_ARG_CONV_EXCL` を設定するようになると、`settings.json` の値が無視される。手当て: テスト `test-path-conversion.sh` が、Claude Code の中で流したときに、Bash ツールの環境の値を確かめる
- `settings.json` から変数を消しても、動いているセッションでは変数が残り、消したことに気づかない。手当て: テストが `settings.json` の中身を確かめるので、消すと失敗する
- `.claude/hooks/tests/` のテストを自動で流す仕組みは無い(`/verify-all` は `.claude/` の変更でテストを流さず、CI にもジョブが無い)。手当て: この spec では足さない。`settings.json` の変更は CODEOWNERS の承認を通るので、所有者がその変更を見る
- この調査の実測は Git for Windows 2.39.1 で行った。ソースは main で読み、実測と一致した

## 参考

- https://github.com/git-for-windows/msys2-runtime/blob/81d9bd3d1c3680aa611ff2e5d1950787ffc95c6a/winsup/cygwin/msys2_path_conv.cc — 書き換えの推測と `MSYS_NO_PATHCONV` の判定
- https://raw.githubusercontent.com/git-for-windows/msys2-runtime/main/winsup/cygwin/spawn.cc — 引数の書き換えと `MSYS2_ARG_CONV_EXCL`
- https://www.msys2.org/docs/filesystem-paths/ — `MSYS2_ARG_CONV_EXCL` と `MSYS2_ENV_CONV_EXCL` の説明
- https://code.claude.com/docs/en/settings-reference.md — `env` の意味と、当てられる時期
- https://code.claude.com/docs/en/env-vars.md — `env` が届くサブプロセス
- https://github.com/anthropics/claude-code/issues/91771 — Bash ツールに MSYS の変数が設定されていないことの報告
