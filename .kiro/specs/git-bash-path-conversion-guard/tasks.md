# タスク

- [ ] 1. 所有者が最初に置く2つのファイルを用意し、置く前の状態を記録する

  Claude は、部品「settings.json の env」と部品「test-protect-main.sh の直し」の変更を、scratchpad の `place-1/` に、リポジトリと同じ並び(`place-1/.claude/settings.json`、`place-1/.claude/hooks/protect-main.sh` の写し、`place-1/.claude/hooks/tests/test-protect-main.sh`)で用意する。`settings.json` は、いまのファイルの写しの最上位に `env` を足しただけのものにし、`permissions` と `hooks` は1文字も変えない。`test-protect-main.sh` は、13行目と14行目だけを、`mktemp -d` の結果を `TMP_ROOT` に置き、`pwd -W` でドライブ文字の形に直したパスを `WORK` にする書き方に直す。Claude は、直す前の `test-protect-main.sh` を、`MSYS2_ARG_CONV_EXCL` か `MSYS_NO_PATHCONV` のある環境で流さない。流すと `C:\tmp` の下にリポジトリが残るからである。あわせて、/kiro-impl を動かしているセッション(以下、親のセッション)は、自分の Bash ツールと、起動したサブエージェントの Bash ツールの両方で、置く前の状態として `printenv MSYS2_ARG_CONV_EXCL` と `git rev-parse --sq-quote /kiro-spec-quick` の出力を、scratchpad のファイル `place-1/before.txt` に記録する。
  - 完了の確かめ方: scratchpad の `place-1/` の中で、直した `test-protect-main.sh` が、`MSYS2_ARG_CONV_EXCL='*'` を付けて流したときも付けずに流したときも「成功 52 件 / 失敗 0 件」で終わり、流す前と流したあとで `C:\tmp` の下の項目の一覧が変わらない。`git diff --no-index` で本来の `settings.json` と `place-1/.claude/settings.json` を比べたとき、違いが `env` の4行だけである。親のセッションの記録では、置く前の2か所とも `printenv` が何も出さず、`git` が `C:/Program Files/Git/kiro-spec-quick` の形を返している
  - 受入基準とテストの対応: 要件2の受入基準2(フックの判定が変わらない)のうち `protect-main.sh` の判定は、`test-protect-main.sh` の52件が変数のある環境で通ることで確かめる。要件2の受入基準3(macOS と Linux で動きが変わらない)は、テストでは確かめない。手元に macOS と Linux の作業PCが無いためである。代わりに、`settings.json` に足すのが MSYS の実行環境だけが読む変数1つであることを、この差分の確かめで確かめる
  - _要件: 2.2, 2.3_
  - _対象の部品: settings.json の env, test-protect-main.sh の直し_

- [ ] 2. 所有者に2つのファイルを置いてもらい、変数が届くことを実測する

  親のセッションは、1で用意した `settings.json` と `test-protect-main.sh` を本来の場所に写すコマンドを、所有者に示して置くよう頼む。依頼には、Claude がこの2つを書けないこと(`settings.json` の `deny`)と、置くと動いているセッションにも変数が当たることを添える。所有者が置いたら、親のセッションは、自分の Bash ツールで `printenv MSYS2_ARG_CONV_EXCL` と `git rev-parse --sq-quote /kiro-spec-quick --title=/kiro-spec-quick` を打つ。続けて親のセッションは、サブエージェントを1つ起動し、同じ2つのコマンドをサブエージェントの Bash ツールで打たせ、出力をそのまま返させる。どちらかで値が `*` でないか、`git` が書き換わった文字列を返したら、親のセッションはこのあとのタスクに進まずに止まり、届かなかったことと出力を所有者に伝える。
  - 完了の確かめ方: 親のセッションの Bash ツールとサブエージェントの Bash ツールの両方で、`printenv MSYS2_ARG_CONV_EXCL` が `*` を出し、`git rev-parse --sq-quote` が ` '/kiro-spec-quick' '--title=/kiro-spec-quick'` を出す。1で記録した置く前の状態と比べて、変数が置いたあとに現れている
  - 受入基準とテストの対応: 要件1の受入基準1・2・4(Claude が書いた引数が書いたとおりの文字で届く、その決まりが Issue やPRを扱うコマンドに限らずすべてのコマンドに当てはまる、その決まりがメモリの記述を読んだかどうかに依らずに成り立つ)と要件3の受入基準1(作業PCごとに設定を足さずに、書き換えられずに届く)は、親のセッションの Bash ツールでの実測と、1で記録した置く前の状態との比べで確かめる。要件1の受入基準3(サブエージェントが実行するコマンドにも当てはまる)は、サブエージェントの Bash ツールでの実測で確かめる。要件3の受入基準2(新しく worktree を選んで開いたセッションでも届く)は、新しいセッションでは実測しない。このセッションが worktree で開いたセッションであり、プロジェクトの設定(SessionStart のフック)が当たっていることと、design が確かめた文書(`settings.json` の `env` は、プロジェクトの設定としてセッションの始めに当たる)を根拠にする
  - _要件: 1.1, 1.2, 1.3, 1.4, 3.1, 3.2_

- [ ] 3. 書き換えを止める変数が働いているかを確かめるテストを作る

  Claude は、部品「test-path-conversion.sh」のテストを、scratchpad の `place-2/.claude/hooks/tests/test-path-conversion.sh` に作る。`place-2/.claude/settings.json` には、所有者が2で置いた `settings.json` の写しを置く。Claude は、テストの場合2が `git rev-parse --sq-quote` の出力を、`git` が付ける単一引用符と先頭の空白を含めた文字列(` '/kiro-spec-quick' '--title=/kiro-spec-quick' '/a:/b' '/foo:/bar'`)と比べるように作る。テストができたら、親のセッションは、所有者に、`place-2/` のテストを本来の場所に写すコマンドを示して置くよう頼む。
  - 完了の確かめ方: scratchpad の `place-2/` の中で `bash .claude/hooks/tests/test-path-conversion.sh` が4つの場合をすべて通し、終了コード0で終わる。`place-2/.claude/settings.json` から `MSYS2_ARG_CONV_EXCL` の行を消すと場合1が失敗し、終了コード1で終わる。場合2の比べる文字列を書き換わった形(` 'C:/Program Files/Git/kiro-spec-quick'`)に変えて流すと場合2が失敗する。確かめたあと、Claude は消した行と変えた文字列を元に戻す。所有者が置いたあと、本来の場所で同じテストが終了コード0で終わる
  - 受入基準とテストの対応: 要件4の受入基準1(働いているかを確かめる自動のテストがある)は、`test-path-conversion.sh` の場合1から場合4で確かめる。要件4の受入基準2(外すか壊すとテストが失敗する)は、`settings.json` の行を消すと場合1が失敗することで確かめる。要件1の受入基準1(書いたとおりの文字で届く)は、場合2と場合3で確かめる
  - _要件: 4.1, 4.2, 1.1_
  - _対象の部品: test-path-conversion.sh_

- [ ] 4. CLAUDE.md の Git規約に、Windows 向けのプログラムに渡すパスの書き方を足す

  Claude は、部品「CLAUDE.md の Git規約の項目」のとおり、CLAUDE.md の「Git規約」の節の、Git操作をホストOSで行う項目のあとに1項目を足す。Claude は、項目に、対象は Windows 向けのプログラムに渡す引数だけで、`>/dev/null` のようなリダイレクトは今までどおり書くことを添える。
  - 完了の確かめ方: CLAUDE.md の「Git規約」の節に項目が1つ増え、`git diff CLAUDE.md` の変更がその項目の追加の行だけである
  - 受入基準とテストの対応: 要件1の受入基準6(パスのつもりの `/` で始まる形も書き換えずに届き、Windows 向けのプログラムが失敗したら Claude が書き直す)の前半は、`test-path-conversion.sh` の場合2で確かめる。場合2は、値が `*` のときに `/` で始まる引数が一律に書き換わらないことを確かめるもので、パスのつもりの形(`/c/…` `/tmp/…`)を引数に含めていない。Git Bash はパスのつもりの形とそうでない形を見分けないので、場合2で足りる。後半は Claude の振る舞いなので、テストでは確かめない
  - _要件: 1.6_
  - _対象の部品: CLAUDE.md の Git規約の項目_

- [ ] 5. 変数が届いた環境で、今の作業が壊れていないことを確かめる

  親のセッションは、変数が届いた自分の Bash ツールで、`.claude/hooks/tests/` のテスト5本(今ある4本と、3で足した `test-path-conversion.sh`)と、`.claude/scripts/parallel/tests/` のテスト4本をすべて流す。続けて親のセッションは、サブエージェントを1つ起動し、`bash .claude/hooks/tests/test-path-conversion.sh` を流させて結果を返させる。
  - 完了の確かめ方: 9本のテストがすべて失敗0件で終わる。流す前と流したあとで `C:\tmp` の下の項目の一覧が変わらない。サブエージェントが流した `test-path-conversion.sh` が場合4まで通る
  - 受入基準とテストの対応: 要件2の受入基準1(リポジトリに書かれたコマンドが同じ結果で終わる)のうちスクリプトの部分は、`.claude/scripts/parallel/tests/` の4本で確かめる。要件2の受入基準2(フックの判定が変わらない)は、`.claude/hooks/tests/` の今ある4本で確かめる。要件1の受入基準3(サブエージェントにも当てはまる)は、サブエージェントが流した `test-path-conversion.sh` の場合4で確かめる
  - _要件: 2.1, 2.2, 1.3_

## 実装のメモ

- `.claude/settings.json` と `.claude/hooks/` は Claude が書けない(`settings.json` の `deny`)。所有者が置くまで、Claude はそれらを本来の場所に書こうとしない
- 所有者への依頼、親のセッションの Bash ツールでの実測、サブエージェントの起動は、/kiro-impl を動かしている親のセッションが行う。実装役のサブエージェントは、所有者に依頼する手前で止まり、用意したもの(scratchpad の `place-1/` `place-2/` のパス)を親のセッションに返す。1と3の成果は scratchpad にあり、リポジトリには所有者が置いたあとに入る。そのため、確認役は、1と3の成果を scratchpad のパスで確かめる
- 所有者が `settings.json` を置くと、動いているセッションにも変数が当たる。そのあと、Claude は `/tmp/…` や `/c/…` の形のパスを Windows 向けのプログラム(`git` `gh` `docker`)に渡さない
- design は、変数が届くことを実測するまでほかの部品を作らないと決めている。1で `test-protect-main.sh` の直しだけを先に作るのは、この直しが変数があってもなくても通るものであり、直す前のテストを変数のある環境で流させないために `settings.json` と同時に置く必要があるからである。`test-path-conversion.sh` と CLAUDE.md の項目は、2の実測のあとに作る。そのため、所有者への依頼は2と3の2回になる
- 要件1の受入基準5(実行の前に止められたら理由と書き方が伝わる)は、design が止める手段を作らないと決めたので、この spec のタスクでは扱わない
- 要件2の受入基準1(リポジトリに書かれたコマンドが変更の前と同じ結果で終わる)のうち `/start` と `/ship` の手順のコマンドは、タスクでは確かめない。全タスクが終わったあと、Claude がこの spec を `/ship` で出荷するときに、`git commit -F`、`git push -u origin`、`gh pr create` が変数のある環境で通り、`gh pr view --json title,body` でPRの題名と本文に `C:/Program Files/Git` が含まれないことを確かめる
- 共通の完了条件の1(確かめるテストの無い受入基準を残さない)の例外は、要件1の受入基準6の後半(Windows 向けのプログラムがエラーで終わったら、Claude がパスを書き直して実行する)、要件2の受入基準3(macOS と Linux の作業PCでは動きが変わらない)、要件3の受入基準2(新しく worktree を選んで開いたセッションでも届く)の3つである。理由は、それぞれのタスクの「受入基準とテストの対応」に書いた

## 完了条件(全タスク共通)

Claude は、どのタスクでも、タスクの箇条書きの欄を書いたうえで、次の4つを満たしたときにタスクを完了とする。

1. Claude は、タスクが満たす requirements.md の受入基準(要件の番号付きの項目)ごとに、それを確かめるテストのファイル名とテスト名を「受入基準とテストの対応」の行に書く。Claude は、確かめるテストの無い受入基準を残さない。
2. タスクで変えた領域の verify のスキル(`/verify-frontend` `/verify-backend` `/verify-terraform`)が、すべて成功している。
3. Claude は、テストを飛ばす設定、アサーションの削除、カバレッジや lint の対象からの除外を足して、完了条件を満たしたように見せない。CI の escape-hatch の検査が、これらの追加を機械で見つける。
4. Claude は、新しく書いたテストについて、テストの対象のコードを一時的に壊してテストが失敗することを確かめてから、コードを元に戻す。
