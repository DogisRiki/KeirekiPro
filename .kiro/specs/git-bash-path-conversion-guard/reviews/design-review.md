# design のレビュー記録

## サイクル1 往復1(2026-10-06)

審査の材料: Issue #480 本文(コメントは読んでいない)、`design.md`、`requirements.md`(承認済み)、`research.md`、`spec.json`(`additional_issues` 無し)、`reviews/requirements-review.md`、`reviews/requirements-response.md`、`reviews/design-style.md`、雛形 `.kiro/settings/templates/specs/design.md`、steering 3本。設計の前提を確かめるために読んだ実ファイル: `.claude/settings.json`(`env` の欄は無い。`deny` に `.claude/settings.json` と `.claude/hooks/**` の Edit/Write がある。`.claude/scripts/` は `deny` に無い)、`.github/CODEOWNERS`(`/.claude/` 全体が所有者の承認の対象)、`.claude/hooks/protect-main.sh`(51〜62行目。`git -C <path>` の path と入力の `cwd` を `git` に渡す)、`.claude/hooks/check-verify-before-stop.sh`(45〜59行目)、`.claude/hooks/session-registry.sh`(51行目)、`.claude/hooks/tests/test-protect-main.sh`(13〜17行目。`mktemp -d` の結果をそのまま `git init` と `git -C` に渡す。`expect` は52件)、`.claude/hooks/tests/test-check-verify-before-stop.sh` と `test-session-registry.sh`(16〜19行目。`TMP_ROOT` と `pwd -W` の書き方)、`.claude/hooks/tests/test-spec-review-scan.sh`(`git` を呼ばない)、`.claude/scripts/parallel/lib.sh`(21行目 `export MSYS_NO_PATHCONV=1`)、`.claude/scripts/parallel/tests/test-lib.sh`(270〜275行目)、`.claude/scripts/parallel/tests/` の4本(すべて `pwd -W` で直している)、`start-dev.sh`(9行目)、`.claude/skills/ship/SKILL.md`、`.claude/skills/file-issue/SKILL.md`(本文は `--body-file <ファイル>` で渡す)。

要件との突き合わせ: 要件1の1〜4、2の3、3の1〜2は部品「settings.json の env」、要件1の6は部品「CLAUDE.md の Git規約の項目」、要件2の2は部品「test-protect-main.sh の直し」とテストの方針、要件4の1〜2は部品「test-path-conversion.sh」が裏付けている。要件1の5(止められたときの案内)は、止める手段を作らないと「作らないもの」で決めているので、使われない要件として扱いが決まっている。要件2の1は部品ではなくテストの方針(結合テスト)で裏付けている。要件に対応する要素が無いものは見つからなかった。

「プロジェクトの決まりを守っているか」の節: 7項目がすべて、中身のある項目(2つ)か「関係のない項目」の行(5つ)に出ている。「品質チェックの設定」は `.claude/` の下を変えると書き、「ファイルの構成」と一致している。新しいライブラリは出てこない。7項目目は指摘 D1-1-1 を参照。

境界: 「作らないもの」に挙げた、止めるフック・`lib.sh` の取り外し・自動で流す仕組み・メモリの直しを、本文は扱っていない。Issue 本文との突き合わせは requirements の往復と変わらず、取りこぼしも勝手な追加も無い。

### 申告

**1. 書き換えを止める変数を、ゲート設定ファイル `.claude/settings.json` の `env` に置く** — 概要、全体の構成、部品「settings.json の env」

- Issue の記載: あり。「メモリに頼らず仕組みで防ぐ(AIの提案を了承)」。置き場所は書かれていない
- 決めたこと: `.claude/settings.json` の最上位に `"env": { "MSYS2_ARG_CONV_EXCL": "*" }` を足す。Claude は書けないので所有者が置き、PR は CODEOWNERS の承認を待つ
- 他にありえた選択肢: 実行の前のフックでコマンドを止める(案C)、フックでコマンドの頭に変数を足す(案D)、起票と PR の作成のあとに題名を読み直す手順(案E)。いずれも research.md で比べている
- 外れていた場合: `env` の値が Windows の Bash ツールに届かなければ、同じ置き場所を使う案Bも成り立たず、作り方の比較からやり直しになる(指摘 D1-1-1 を参照)。届くなら、所有者の手置きが要るのは最初の1回だけである

**2. 引数だけを止める `MSYS2_ARG_CONV_EXCL` を選び、リポジトリの既存の `MSYS_NO_PATHCONV` と別の変数にした** — 全体の構成、作らないもの

- Issue の記載: あり。困っていることは引数の書き換えだけを指している
- 決めたこと: 引数だけを止める `MSYS2_ARG_CONV_EXCL=*` を使う。`lib.sh`(21行目)と `start-dev.sh`(9行目)が自分で設定している `MSYS_NO_PATHCONV=1` はそのまま残す
- 他にありえた選択肢: `lib.sh` と同じ `MSYS_NO_PATHCONV=1` に揃える(引数と、`NAME=/foo` の形の環境変数の両方を止める)
- 外れていた場合: リポジトリの中に、書き換えを止める変数が2種類並ぶ。Claude が `NAME=/foo cmd` の形で Windows 向けのプログラムに環境変数を渡したとき、その値は今までどおり書き換わる。この spec の要件は引数だけなので要件には反しないが、所有者が「書き換えは止めてある」と読むと食い違う場面が残る

**3. 止める手段を作らず、パスのつもりで書いた `/c/…` `/tmp/…` は Windows 向けのプログラムの失敗を Claude が見てから書き直すことにした** — 作らないもの、部品「CLAUDE.md の Git規約の項目」

- Issue の記載: なし
- 決めたこと: 実行の前に止めるフックを作らないので、要件1の5は使われない。CLAUDE.md の Git規約に、Windows 向けのプログラムにはドライブ文字の形か相対の形でパスを渡すという1項目を足す。この項目は書き直す回数を減らすためで、防ぐことはこの項目に頼らない
- 他にありえた選択肢: 止める手段を併用して、`/c/…` や `/tmp/…` を Windows 向けのプログラムに渡すコマンドだけ実行の前に止めて書き方を案内する(案C の縮小)
- 外れていた場合: Claude が Git Bash の形のパスを `gh` や `docker` に渡すたびに、そのコマンドが1回失敗してから書き直しになる。記録(題名・本文・コミットメッセージ)は壊れない。CLAUDE.md の項目は Claude が読み落とすと効かないが、防ぐことには関わらない

**4. 確かめるテストを `.claude/hooks/tests/` に置き、自動で流す仕組みは足さない** — 作らないもの、部品「test-path-conversion.sh」、テストの方針

- Issue の記載: なし
- 決めたこと: テストはホストの Git Bash で手で流す。`/verify-all` にも CI にも足さない。置き場所は `.claude/hooks/tests/` で、所有者が置く
- 他にありえた選択肢: `.claude/scripts/` の下に置く(Claude が書ける)。`/verify-all` の手順に `.claude/` のテストを足す。CI に Windows のジョブを足す
- 外れていた場合: `settings.json` から変数が外れても、誰かがテストを流すまで気づかない。気づく手段は、`.claude/settings.json` の変更が CODEOWNERS の承認を通ることだけになる(research.md の「危険と手当て」が同じことを書いている)

### 指摘

| ID | レベル | 該当箇所 | 内容 | 直し方の案 |
|---|---|---|---|---|
| D1-1-1 | 中 | design.md「プロジェクトの決まりを守っているか」の「使う外部の機能がこのリポジトリで使えるか」、部品「settings.json の env」 | この設計の中心の前提は「`.claude/settings.json` の `env` の値が、Windows で Claude Code が起こす Git Bash(Bash ツール、サブエージェントの Bash ツール、フック)の環境に届くこと」である。節の記載は「どのプランでも使える」と「SessionStart のフックが worktree でも動いた」の2つで、前者は文書の記載、後者はフックの設定が当たっていることの確認であり、`env` の値が Bash ツールの環境に届いたことの実測ではない。research.md 自身が「サブエージェントの Bash ツールに届くことは文書に明記が無い」「所有者が `settings.json` を置いたあとに Bash ツールで変数が見えることは実装のときに確かめる」と書いており、前提が未確認であることを design.md は書いていない。届かなかったときは、同じ置き場所の案Bも成り立たず、案C・Dとの比較からやり直しになる。rules の観点3は、この項目に「いつ何をどう確かめたか」を求めている | 節の7項目目に、(a) 文書で確かめたこと(URL と節の名前)、(b) 実測していないことと、Claude が `.claude/settings.json` を書けないため実測できなかったこと、(c) 実装の最初の手順として、所有者が `env` の1行を置いたあと、Claude が Bash ツール・サブエージェント・フック(たとえば `protect-main.sh` が読む環境を一時的に出す)の3か所で `MSYS2_ARG_CONV_EXCL` を実測し、届かなければ他の部品を作らずに所有者へ戻ること、を書く。tasks.md はこの実測を最初のタスクにする。所有者の手を借りずに先に実測するなら、`claude -p` に `--settings <scratchpad の JSON>` を渡して子の Claude Code の Bash ツールで `printenv MSYS2_ARG_CONV_EXCL` を実行する方法があるが、その可否もこの spec の文書で確かめてから書く |
| D1-1-2 | 低 | design.md 部品「settings.json の env」の「いつ動くか」、部品「test-protect-main.sh の直し」、テストの方針 | 所有者が `settings.json` を置くと、動いているセッションにも値が当たる(本文の記載)。その状態で直す前の `test-protect-main.sh` を流すと、本文が書くとおり `C:\tmp` の下にリポジトリが残る。所有者が置く2つのファイル(`settings.json` と `test-protect-main.sh` の直し)の順番を本文は決めておらず、tasks が「settings.json を置く → テストをすべて流す」の順に並べると、流した時点で残骸ができる。実装の途中で気づくので実装には影響しないが、片付けの手間が所有者に出る | 部品「test-protect-main.sh の直し」か「いつ動くか」に、所有者は `test-protect-main.sh` の直しを `settings.json` より先に(または同時に)置き、Claude は直す前の `test-protect-main.sh` を変数のある環境で流さない、と書く |
| D1-1-3 | 低 | design.md 部品「test-path-conversion.sh」の場合2 | `git rev-parse --sq-quote` は受け取った引数を単一引用符で囲み、先頭に空白を付けて出す(`/kiro-spec-quick` を渡すと ` '/kiro-spec-quick'` が返る)。「`git` が返した文字列が、渡した4つと同じ文字であることを確かめる」を字句どおりに作ると、変数があっても一致せず失敗する。実装のときに最初の実行で分かる | 「`git` が返した文字列から単一引用符を外したものが、渡した4つと同じ文字であること」か、「返す文字列が ` '/kiro-spec-quick' '--title=/kiro-spec-quick' '/a:/b' '/foo:/bar'` であること」のどちらかに書き換える |
| D1-1-4 | 低 | design.md「ファイルの構成」、部品「test-path-conversion.sh」 | 新しいテストは、どのフックも対象にしないのに `.claude/hooks/tests/` に置く。`.claude/hooks/**` は `settings.json` の `deny` で Claude が書けないので、所有者が手で置くファイルが3つ(`settings.json`、`test-protect-main.sh`、新しいテスト)になる。`.claude/scripts/` は `deny` に無く(CODEOWNERS の承認は同じく要る)、`.claude/scripts/parallel/tests/` には同じ書き方のテストが4本ある。置き場所を変えれば所有者の手置きは2つに減る。どちらでも設計は成り立つので、所有者が決めればよい | 置き場所を `.claude/scripts/` の下(たとえば `.claude/scripts/tests/test-path-conversion.sh`)にするか、`.claude/hooks/tests/` に置く理由(フックのテストと一緒に流すためなど)を本文に書く |
| D1-1-5 | 低 | design.md 部品「CLAUDE.md の Git規約の項目」 | 足す項目は「`/c/…` や `/tmp/…` の形は渡さない」と書くが、Claude Code の Bash ツールの案内は Claude に `/dev/null` を使わせる(`NUL` でなく `/dev/null`)。`>/dev/null` のリダイレクトは bash が処理するので書き換えに関わらないが、`--body-file /dev/null` のように Windows 向けのプログラムの引数に書くと、変更のあとは届かない形になる。項目を読んだ Claude が、リダイレクトまで避けて書き直すか、逆に引数の `/dev/null` を見落とすおそれがある | 項目に「対象は Windows 向けのプログラムに渡す引数だけで、`>/dev/null` のようなリダイレクトは今までどおり書く」の1文を足す |

### 前の段階への指摘

なし。設計に落とす過程で、requirements の不足・曖昧さ・矛盾は見つからなかった。要件1の5が使われない要件になることは、requirements の往復1(R1-1-2)で止める方式を採らない可能性として確かめてある。

- 往復: 1回目 / 高0 中1 低4

## サイクル1 往復2(2026-10-06)

審査の材料: 往復1と同じ(Issue #480 本文、`design.md` の直したあとの本文、`requirements.md`、`research.md`、`spec.json`、雛形、steering 3本)に加えて、`reviews/design-response.md` の「サイクル1 往復1 への対応」と `reviews/design-style.md` の2回目の点検。実ファイルは `.claude/settings.json`(`deny` の 60〜65行目に `.claude/settings.json` と `.claude/hooks/**` の Edit/Write がある。`env` の欄は無い)と `.claude/hooks/tests/test-protect-main.sh`(13〜17行目)を読み直し、往復1の前提が変わっていないことを確かめた。

D1-1-1 の確認: 「使う外部の機能がこのリポジトリで使えるか」の項目に、(a) 文書で確かめたこと(2つの URL と節の名前)、(b) Bash ツールとサブエージェントの Bash ツールに届くことをまだ実測していないことと、`settings.json` の `deny` のため所有者が置く前には実測できないこと、(c) 実装の最初の手順として、所有者が `env` を置いたあとに Claude が2か所で `MSYS2_ARG_CONV_EXCL` の値と `git rev-parse --sq-quote /kiro-spec-quick` の結果を実測し、届かなければほかの部品を作らずに止まって所有者に戻し、作り方の比較(案CとD)からやり直すこと、が書かれている。直し方の案で挙げた3か所目(フック)は実測しないと決め、理由(フックは `/` で始まる引数を Windows 向けのプログラムに渡さない。フックのテストを変数のある環境で流して判定が変わらないことを確かめる)を書いている。往復1で読んだ `protect-main.sh` `check-verify-before-stop.sh` `session-registry.sh` は、`git -C <path>` の path と `cwd` にドライブ文字の形か Claude Code が渡す形しか使わず、`/` で始まる固定の引数を `git` に渡していないので、この理由は実ファイルと合っている。研究の記録(research.md「判断」の「実装のときに確かめること」)とも一致した。rules の観点3が求める「いつ何をどう確かめたか」が書かれたので、D1-1-1 は解消した。

D1-1-2〜D1-1-5(低、記録のみ): 処置に異存は無い。D1-1-2 の順番(`test-protect-main.sh` の直しを `settings.json` より先か同時に置く)は tasks で並べると response に書かれているので、tasks の審査で確かめる。

要件との突き合わせ、「プロジェクトの決まりを守っているか」の節と本文の矛盾、境界、設計内の矛盾: 直した箇所は7項目目の1項目だけで、「ファイルの構成」「部品」「テストの方針」は変わっていない。往復1の確認の結果はそのまま成り立つ。直した文に、本文のほかの節と食い違うことは無い。

### 申告

往復1の4件から変わらない。直した箇所で新しく決めたこと(フックの環境は実測せず、フックのテストで代える)は、外れていてもフックの判定が変わらない(`/` で始まる固定の引数を Windows 向けのプログラムに渡すフックが無い)ので、手戻りが大きいものに当たらず、申告しない。

### 指摘

| ID | レベル | 該当箇所 | 内容 | 直し方の案 |
|---|---|---|---|---|
| D1-2-1 | 低 | design.md「プロジェクトの決まりを守っているか」の「使う外部の機能がこのリポジトリで使えるか」、部品「test-protect-main.sh の直し」 | 直した文は「実装の最初の手順として、所有者が `settings.json` の `env` を置いたあと」に実測すると書き、D1-1-2 への処置は「`test-protect-main.sh` の直しを `settings.json` より先か同時に置く」と書いている。両方を満たすには、所有者が最初に置くファイルが `settings.json` だけでなく `test-protect-main.sh` の直しも含むことになる。本文は「ほかの部品を作らずに止まり」と書くので、tasks が「実測が通るまで `test-protect-main.sh` に手を付けない」と読むと D1-1-2 の順番と食い違い、直す前の `test-protect-main.sh` を変数のある環境で流す余地が残る。実装には影響しないが、tasks の並べ方で片付けの手間が出るかどうかが決まる | 7項目目の文に「所有者は、`settings.json` の `env` と `test-protect-main.sh` の直しを同時に置く」と1文を足すか、tasks で「最初のタスクで所有者が置くのは `settings.json` と `test-protect-main.sh` の2つ」と明記する |

### 前の段階への指摘

なし。

- 往復: 2回で収束 / 未解決: 0件

## サイクル2 往復1(2026-10-06)

このサイクルは、実装の途中の実測による差し戻し(spec.json の `approval_history`。`settings.json` の `env` が、Claude Desktop アプリで動いているセッションには当たらず、新しく始めたセッションから当たる)で始まった。直したのは、design.md の部品「settings.json の env」の「いつ動くか」と、research.md の「要約」と「Claude Code の `settings.json` の `env`」の分かったことの2か所、および書き方の点検(`reviews/design-style.md` の 02:30 の節)による中身の変わらない直しである。

審査の材料: Issue #480 本文(コメントは読んでいない)、`design.md` の直したあとの本文、`requirements.md`(承認済み)、`research.md` の直したあとの本文、`tasks.md`(1〜5 が `[x]`。「実装のメモ」の「2 の途中の記録」「2 の完了の記録」「5 の完了の記録」「設計への書き足し」)、`spec.json`(`additional_issues` 無し。`approval_history` に design と tasks の取り消しが1件ずつ)、`reviews/design-response.md`、`reviews/design-style.md`、雛形 `.kiro/settings/templates/specs/design.md`、steering 3本。設計の前提を確かめるために読んだ実ファイル(すべて実装後の状態): `.claude/settings.json`(2〜4行目に `"env": { "MSYS2_ARG_CONV_EXCL": "*" }` が最上位の先頭にあり、`permissions` と `hooks` は往復1のときと同じ)、`.claude/hooks/tests/test-path-conversion.sh`(場合1〜4が design の部品のとおり。場合2は ` '/kiro-spec-quick' '--title=/kiro-spec-quick' '/a:/b' '/foo:/bar'` と比べ、`env -u MSYS_NO_PATHCONV` で `git` を起動する。場合4は `CLAUDECODE` があるときだけいまのシェルの値を見る)、`.claude/hooks/tests/test-protect-main.sh`(13〜15行目が `TMP_ROOT` と `pwd -W` の書き方に直されている)、`CLAUDE.md`(85行目に Git規約の項目があり、D1-1-5 の1文も足されている)。

直した箇所の確認: 「いつ動くか」の新しい記載(保存しても Desktop アプリで動いているセッションには当たらず、新しく始めたセッションから当たる。所有者が置いたあと Claude は新しいセッションで作業を続ける)は、tasks.md「2 の途中の記録」の実測(置く前から動いていたセッションでは `printenv` が空で `git` が書き換わった文字列を受け取り、所有者が worktree のフォルダを選んで新しく始めたセッションでは `*` と `'/kiro-spec-quick'` が返った)と一致し、research.md の2か所とも一致する。この記載で、要件3の2(新しく worktree を選んで開いたセッションでも届く)の裏付けは、文書だけでなく実測(新しいセッションは worktree のフォルダで開いた)にもなった。「失敗したとき」「test-path-conversion.sh」「test-protect-main.sh の直し」「CLAUDE.md の Git規約の項目」「テストの方針」は変わっておらず、実ファイルの中身とも食い違っていない。

要件との突き合わせ、「プロジェクトの決まりを守っているか」の節の7項目の出方、境界、Issue 本文との突き合わせ: 往復1・2の結果がそのまま成り立つ。取りこぼしも勝手な追加も無い。直した文に、設計を実現できなくする前提の変化は無い(置き場所・変数・テスト・CLAUDE.md の項目はどれも実装され、tasks.md「5 の完了の記録」で9本のテストが失敗0件で通っている)。

設計内の矛盾として見つかったのは、下の D2-1-1 の1件である。直したのが「いつ動くか」だけで、同じ手順を書いている7項目目が直っていないために生じた。残りの工程(tasks の再審査、`/ship`)で作り直しや戻りを起こすものではないので低にした。

### 申告

往復1の4件から変わらない。このサイクルで新しく本文に入った「所有者が置いたあと、Claude は新しく始めたセッションで作業を続ける」は、Claude が選んだ作り方ではなく実測で分かった動き方であり、他にありえた選択肢(動いているセッションに当たるのを待つ)は実測で成り立たないと分かっているので、申告にしない。

### 指摘

| ID | レベル | 該当箇所 | 内容 | 直し方の案 |
|---|---|---|---|---|
| D2-1-1 | 低 | design.md「プロジェクトの決まりを守っているか」の「使う外部の機能がこのリポジトリで使えるか」 | 7項目目は、サイクル1のまま「`env` の値が Windows の Bash ツールとサブエージェントの Bash ツールの環境に実際に届くことを、まだ実測していない」「実装の最初の手順として、所有者が `settings.json` の `env` を置いたあと、Claude は…2か所で…実測する。どちらかで届かなければ、Claude はほかの部品を作らずに止まり、所有者に戻して、作り方の比較(research.md の案CとD)からやり直す」と書いている。同じ本文の「いつ動くか」は「2026-10-06 に実測」と書き、tasks.md「2 の完了の記録」は2か所とも届いたことを記録しているので、「まだ実測していない」は今は成り立たない。また、この手順には「新しく始めたセッションで実測する」が無く、置く前から動いているセッションで実測すると「届かなかった」と読めて案CとDに戻ることになる。これは、このサイクルの差し戻しの原因そのものであり、「いつ動くか」には直しが入ったが、同じ手順を書く7項目目には入っていない。rules の観点3が7項目目に求める「いつ何をどう確かめたか」も、「いつ動くか」の「(2026-10-06 に実測)」には日付しか無く、何をどう確かめたかは tasks.md にしか無い。tasks 1〜5 は完了しているので、この食い違いが実装の戻りを起こすことは無い | 7項目目の「ただし」以降を、実測の記録に書き換える。たとえば「2026-10-06 に、所有者が `settings.json` の `env` を置いたあとに新しく始めたセッションで、Claude は、自分の Bash ツールとサブエージェントの Bash ツールの2か所で、`printenv MSYS2_ARG_CONV_EXCL` が `*` を出し、`git rev-parse --sq-quote /kiro-spec-quick --title=/kiro-spec-quick` が書いたとおりの文字を返すことを確かめた。置く前から動いていたセッションでは値が届かなかったので、実測は新しく始めたセッションで行う」のように、いつ・どこで・何を・どう確かめたかと、新しいセッションで確かめる条件を書く。「届かなければ止まる」の文を残すなら、「新しく始めたセッションでも届かなければ」に直す |
| D2-1-2 | 低 | design.md 部品「settings.json の env」の「失敗したとき」 | 「失敗したとき」は、場合4が失敗する原因を「Claude Desktop アプリの起動の環境がすでに `MSYS2_ARG_CONV_EXCL` を設定している」の1つだけ書いている。このサイクルで分かったとおり、`settings.json` を置く(またはこのPRを取り込む)前から動いているセッションでも、場合4は同じく失敗する(`test-path-conversion.sh` 105行目は「いまのシェルの値: <設定なし>」と出すだけで、2つの原因を見分けない)。原因を1つだけ書いたままだと、場合4が失敗したときに、Claude が新しいセッションで流し直す前に Desktop アプリの環境のせいと判断するおそれがある。実装には影響しない | 「失敗したとき」に「置く前から動いているセッションでも場合4は失敗する。場合4が失敗したら、Claude はまず新しく始めたセッションで流し直し、それでも失敗するときに Desktop アプリの起動の環境を疑う」の趣旨を1文足す |

### 前の段階への指摘

なし。requirements の要件3の1・2は「使うだけで届く」「新しく worktree を選んでセッションを開いたときも届く」と書いており、セッションの始めに当たるという今回の実測と矛盾しない。

- 往復: 1回で収束 / 未解決: 0件
