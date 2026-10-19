# design のレビュー記録

## サイクル1 往復1(2026-10-19)

### 審査の範囲

範囲: 全体

Issue #590 の本文には「きっかけ」と「困っていること」しか無い。requirements のサイクル1 往復1と同じく、「元の要望」の節を所有者の決めたことの記録として扱い、design が requirements.md の要件と Issue の「困っていること」に沿っているかを見た。設計の前提は、`.claude/settings.json`(permissions の deny と hooks の登録)、`.claude/hooks/notify-spec-review.sh`、`.claude/hooks/protect-main.sh`、`.claude/agents/spec-style-checker.md`、`.github/CODEOWNERS`、`.claude/skills/start/SKILL.md` の Step 6、`.claude/skills/spec-review/SKILL.md` の Step 1.5 と Step 7、`.claude/skills/ship/SKILL.md`、`.branch_name_template`、`.kiro/settings/rules/spec-writing.md`、research.md と、過去の spec(`claude-usage-reduction` `spec-writing-leftovers` `issue-type-label-enforcement` の design.md)で確かめた。

### 申告

**1. 所有者が入力するたびに、フックが決まりの要点(約3千字)を会話に差し込む** — 「全体の構成」、`inject-writing-rules.sh` の節

- Issue の記載: なし(「やりたいこと」は、決まりをリポジトリに置くことと、送る前に自分で読み直すことだけを決めている)
- 決めたこと: `UserPromptSubmit` のフックが、所有者の入力のたびに、決まりの名前と1文の決まりを標準出力に書き、Claude の文脈に足す。9千字を超える分は切り捨て、ファイルを開くよう促す1行を書く
- 他にありえた選択肢: CLAUDE.md の1行だけにする。会話の始まり(`SessionStart`)と要約のあと(`restore-after-compact.sh`)にだけ渡す。入力の中身で渡すかどうかを決める(design は「入力の中身を読まない」と決めている)
- 外れていた場合: 入力のたびに約3千字が会話に積み上がるので、会話が要約に達するのが早くなり、使う量も増える。決まりが増えて9千字を超えると、超えた分の決まりは会話に一度も現れず、Claude はファイルを開かない限りその決まりを知らない

**2. 決まりと例を足す PR は、`/ship` を通さず、Issue を起票せずに出す** — `owner-writing.md` の節の「決まりと例を足す手順」

- Issue の記載: 「やりたいこと」の6つ目に「例として決まりに足す変更を作り、PRで出す」とだけある
- 決めたこと: Claude は、scratchpad に別の作業フォルダとブランチ(`docs/<短い説明>`)を作り、`git` でコミットと push をし、`gh pr create` で PR を作る。verify、`Refs: #<Issue番号>`、auto-merge の予約の確かめは手順に無い
- 他にありえた選択肢: `/ship` の手順(verify → commit → push → PR → 予約の確かめ)に乗せる。Issue を1つ起票して `Refs:` を書く
- 外れていた場合: CLAUDE.md は出荷を `/ship` に従わせているので、`/ship` を通らない PR の作り方が1つ増える。codex-review は `Spec:` も `Refs:` も無い PR を PR の本文だけで判定するので、PR の本文が薄いと止まる。予約が付かなかったときに気づく手順が無い

**3. `spec-writing.md` を名指しで読むほかのファイルを直さず、`spec-writing.md` の冒頭の1文で `owner-writing.md` へ導く** — 「作らないもの」の3つ目、research.md の「spec-writing.md を読むスキルを書き換えない」

- Issue の記載: なし
- 決めたこと: 7つの決まりを `spec-writing.md` から消し、`spec-writing.md` の冒頭に `owner-writing.md` を先に読むことを書く。`spec-writing.md` を読む 22 のファイルのうち、`spec-style-checker` の定義のほかは直さない
- 他にありえた選択肢: 22 のファイルの参照を `owner-writing.md` にも向ける。7つの決まりを `spec-writing.md` にも短く残す
- 外れていた場合: spec を書くスキルが `spec-writing.md` の冒頭を読み飛ばすと、移した7つの決まり(主語と目的語、専門用語など)で spec を書かなくなる。点検役は両方で点検するので外れは返るが、往復が増える

### 指摘

| ID | レベル | 該当箇所 | 内容 | 直し方の案 |
|---|---|---|---|---|
| D1-1-1 | 中 | design.md 「プロジェクトの決まりを守っているか」の「品質チェックの設定」、「ファイルの構成」、`inject-writing-rules.sh` の節 | design は、Claude が `.claude/hooks/inject-writing-rules.sh` と `.claude/hooks/tests/test-inject-writing-rules.sh` を新しく作り、`.claude/settings.json` を変えると書いている。しかし `.claude/settings.json` の permissions の deny に `Edit(.claude/hooks/**)` `Write(.claude/hooks/**)` `Edit(.claude/settings.json)` `Write(.claude/settings.json)` があり、Claude はこの3つのファイルを書けない。過去の spec(`claude-usage-reduction` の design.md の「権限」の欄、`spec-writing-leftovers` の「所有者による写し」)は、Claude が scratchpad に作り、所有者が写すコマンドを打つ形を設計に書いている。この design にはその置き方が無いので、tasks でフックを作るタスクの完了の確かめ方が決まらず、実装で止まる。あわせて、「品質チェックの設定」の行は「Claude は、品質チェックの設定ファイルを変えない」と書きながら、同じ行で `.claude/settings.json` にフックを足すと書いている。CLAUDE.md の「自律動作の境界」はゲート設定ファイルに `.claude/` を含めているので、この行は自分と食い違う | `inject-writing-rules.sh` の節に「権限」の欄を足し、「Claude は permissions の deny でこのファイルと `.claude/settings.json` を書けない。Claude は変更後の全文を scratchpad に作り、所有者に写すコマンドを示す。所有者が写したあとで Claude がコミットする」のように書く。「ファイルの構成」の3つのファイルにも、所有者が写すことを添える。「品質チェックの設定」の行を「この spec は `.claude/settings.json` と `.claude/hooks/` を変える。これは所有者への提案であり、PR は CODEOWNERS により所有者が承認するまでマージされない。品質チェックの中身(検査の対象、しきい値、除外)は変えない」のように、雛形の「所有者への提案として分けて書く」に合わせる |
| D1-1-2 | 中 | design.md 「CLAUDE.md の作業規約の1行」の節、`owner-writing.md` の節の「冒頭の節」 | 要件2の1は、Claude が送る前に自分で読み直す対象を、チャットの報告と問い、Issue の本文、PR の本文の3つに限り、「送る前」を6つの時(チャットは所有者に見せる前、Issue は案を見せる前と起票する前と書き足す前、PR は作る前と書き換える前)で定めている。spec の本文は、要件2の5のとおり点検役が点検し、Claude の読み直しの対象ではない(requirements のサイクル3 往復1の申告1で所有者が承認した決めごと)。design の CLAUDE.md の1行は「所有者に送る4つの文を書く前に `owner-writing.md` を読み、送る前にその決まりと照らして自分で読み直す」と、spec の本文も読み直しの対象にしている。また、6つの時をどのファイル(CLAUDE.md の1行か、`owner-writing.md` の冒頭の節か)に書くかが design に無い。この spec の requirements.md は実装のあとに Claude が読むファイルではないので、どこにも書かれなければ、「Issue の本文に書き足す前」「PR の本文を書き換える前」の読み直しは決まりとして残らない | CLAUDE.md の1行を「4つの文を書く前に読む」(要件1の1)と「3つの文を送る前に読み直す」(要件2の1)に分け、読み直しの対象を3つにする。`owner-writing.md` の冒頭の節に書くことに、要件2の1の6つの時を足し、spec の本文は点検役 `spec-style-checker` が点検するので Claude の読み直しの対象にしないことも書く |
| D1-1-3 | 中 | design.md 「メモリの移し替え」の節の「消すとき」 | 消す作業は「この spec の PR がマージされたあと」に行うとしているが、Claude がマージを知る手段と、作業を始める引き金が無い。この spec の PR は `.claude/` を直すので所有者の承認を待ち、`/ship` の見届けは承認待ちの時点で終わる(`/ship` の手順7の4の5)。そのため、マージの時点で Claude は PR を見ていない。tasks は、この作業を `/kiro-impl` で完了できるタスクとして書けず、完了の確かめ方も決まらない | 「消すとき」に引き金を書く。たとえば「所有者が、PR がマージされたことを Claude に伝えたら、Claude は `gh pr view <PR番号> --json state` でマージ済みを確かめてから消す」のように、所有者の操作から始まる形にする。tasks では、このタスクを `_保留:_` の目印で PR のあとに回すことを「実装のメモ」に書くよう、design に1行添える |
| D1-1-4 | 低 | design.md 「spec-style-checker.md の直し」の節 | `.claude/agents/spec-style-checker.md` の「当てはめる決まり」の節は、`spec-writing.md` の見出しの名前で、「文の書き方」の節の例外(「ラベル: 内容」の箇条書き)と、「繰り返しの扱い」の節の「1つの文書で同じ決めごとを繰り返さない」を名指ししている。design はこの2つを `owner-writing.md` に移すので、点検役の定義に、無くなった見出しへの参照が残る。design の直しは「足す」ことだけを書いていて、残る参照を直すことと、`owner-writing.md` の冒頭の例外(画面の名前、ファイル名、引用、「ラベル: 内容」)を外れとして挙げないことを書いていない。実装で点検役の定義を直すときに目に入るので、実装は止まらない | 「spec-style-checker.md の直し」に、「当てはめる決まり」の節で移した見出しを名指ししている行を `owner-writing.md` の見出しに書き換えることと、`owner-writing.md` の冒頭の例外を外れとして挙げないことを足す |
| D1-1-5 | 低 | design.md `inject-writing-rules.sh` の節、「テストの方針」 | `owner-writing.md` には `## 決まり` のほかに `## 決まりに入れない書き方` と `## 決まりと例を足すとき` の見出しがあり、どちらも `## 決まり` で始まる。フックが見出しの行を前方一致で探すと、3つの節を1つに読み、「決まりに入れない書き方」の節に `### ` の見出しがあればそれも決まりとして渡す。design は「`## 決まり` の節から」としか書いておらず、テストの決まりのファイルにほかの2つの節があるかも書いていない | フックが `## 決まり` と行全体が一致する見出しから次の `## ` の見出しの前までを読むことを書く。テストの決まりのファイルに `## 決まりに入れない書き方` と `## 決まりと例を足すとき` の節を置き、その節の中身が出力に入らないことを確かめることを「テストの方針」に足す |
| D1-1-6 | 低 | design.md 「報告の書式の直し」の節の最後の段落、「ファイルの構成」 | 「実装のときに、ほかのスキルの手順の報告の書式も照らし、外れる書式を見つけたら同じ PR で直す」と書いているが、「ファイルの構成」が Claude の変えるファイルとして挙げているのは `start/SKILL.md` と `spec-review/SKILL.md` の2つだけで、research.md も外れる書式はこの2つだけと結論している。直す範囲が実装のときに広がりうる形で、tasks は扱うファイルを決められない。所有者が承認する PR なので、広がっても所有者の目は通る | research.md の調べた結果どおり、直すのは2つの書式に限ると書く。ほかのスキルの書式に外れを見つけたときは、同じ PR で直さず、`owner-writing.md` の「決まりと例を足すとき」と同じく別の PR にするか、報告だけにするかを決めて書く |
| D1-1-7 | 低 | design.md `owner-writing.md` の節の「決まりと例を足す手順」の2と5 | `protect-main.sh` は、`git commit` と `git push` を `git commit -F <ファイル>` と `git push -u origin <ブランチ>` の単独のコマンドだけ通し、`git -C <フォルダ> push` と `cd <フォルダ> && git push` を止める。手順2で作る作業フォルダは scratchpad の中なので、Claude がその作業フォルダで push するには、`cd` を単独のコマンドで打ってから push する必要がある。手順はその形を書いていない。また、この PR には Issue が無いので、`.commit_template` の `Refs:` は `N/A` になる。手順を読む Claude が実装のときに形を決められるので、設計のやり直しにはならない | 手順5に「Claude は、`cd <作業フォルダ>` を単独のコマンドで実行してから、`git add` `git commit -F` `git push -u origin docs/<短い説明>` `gh pr create` をそれぞれ単独のコマンドで実行し、終わったら元の作業フォルダに戻る」と書く。コミットメッセージと PR の本文の `Refs:` は `N/A` にすることも書く |

### 前の段階への指摘

なし

- 往復: 1回目 / 高0 中3 低4

## サイクル1 往復2(2026-10-19)

### 審査の範囲

範囲: 差分

- design.md 「作るものと作らないもの」の「作るもの」のフックの行と CLAUDE.md の行: 「概要」とファイルの構成の直しで、フックを誰が作るかが変わり、CLAUDE.md の1行の中身が3つに分かれたので、「作るもの」の書き方と食い違わないかを見た。食い違いは無かった
- design.md 「全体の構成」の、CLAUDE.md の1行とフックの2つの経路を説明する段落: 「CLAUDE.md の作業規約の1行」の節が直されたので、同じ1行を説明するこの段落と食い違わないかを見た。食い違いは無かった
- design.md 「ファイルの構成」の `.claude/agents/spec-style-checker.md` `.claude/skills/start/SKILL.md` `.claude/skills/spec-review/SKILL.md` の行: 「権限」の欄が deny の対象を挙げたので、この3つに「所有者が写す」が無いことが正しいかを `.claude/settings.json` の deny で見た。deny は `.claude/hooks/**` と `.claude/settings.json` だけで、`.claude/agents/` と `.claude/skills/` は Claude が書けるので正しい
- design.md `owner-writing.md` の節の「決まりと例を足す手順」の最後の段落(`.claude/` と `.github/` を直さないので承認を待たない): 「品質チェックの設定」の行が CODEOWNERS の範囲を挙げたので、両者が同じ範囲を指しているかを `.github/CODEOWNERS` で見た。どちらも `/.claude/` と `/.github/` で一致する
- design.md 「メモリの移し替え」の「権限」の欄(所有者の PC の Claude だけが行う): 「消すとき」が所有者の伝えから始まる形になったので、両者が合うかを見た。合っている
- requirements.md 要件1の1、要件2の1・3・4・5、要件4の1: `owner-writing.md` の冒頭の節と CLAUDE.md の1行の直しが、読む時、読み直す3つの文と6つの時、別のエージェントを使わないこと、報告しないこと、点検役の役割、指摘されたときの手順と一致するかを見た。すべて一致する
- requirements.md 要件5の2・3と「範囲」の前提の3つ目(この spec の PR は所有者が承認してからマージされる): 「消すとき」の直しが、マージのあとに消すことと、承認待ちの前提に合うかを見た。合っているが、所有者に伝えてほしいと頼む手順が無い(D1-2-1)
- 実ファイル: `.claude/settings.json` の deny、`.github/CODEOWNERS`、`.claude/skills/ship/SKILL.md` の手順7の4の5(承認待ちで見届けを終える)、`.claude/skills/kiro-impl/SKILL.md` と `.claude/skills/kiro-validate-impl/SKILL.md` の `_保留:_` の扱い、`.kiro/specs/claude-usage-reduction/design.md` の「権限」の欄と「頼み」の欄、同じ spec の tasks.md のタスク4.2・4.3と実装のメモ(置き場所、マージのあとのタスクの進め方)で、差分の前提が成り立つかを確かめた

### 申告

**1. メモリを消す作業は、所有者が PR のマージを Claude に伝えたときに始める** — 「メモリの移し替え」の節の「消すとき」

- Issue の記載: なし(要件5の2は「この spec の PR がマージされたあとに」とだけ決めている)
- 決めたこと: 所有者が PR のマージを Claude に伝えたときに、Claude が `gh pr view <PR番号> --json state` でマージ済みを確かめてから、メモリの決まりを消す。tasks では、このタスクを PR を出したあとに回す
- 他にありえた選択肢: 所有者が次に `/start` を打ったときに、Claude が PR の状態を読んで始める。会話の始まりのフック(`SessionStart`)で PR の状態を読む。所有者が自分でメモリを消す
- 外れていた場合: 所有者が伝えるまで、書き方の決まりがメモリとリポジトリの両方に残り、要件5が避けたい食い違いが続く。所有者に伝えてほしいと頼む手順が無いと、いつまでも始まらない(D1-2-1)

### 指摘

| ID | レベル | 該当箇所 | 内容 | 直し方の案 |
|---|---|---|---|---|
| D1-2-1 | 中 | design.md 「メモリの移し替え」の節の「消すとき」 | 消す作業は「所有者が PR のマージを Claude に伝えたとき」に始まるが、所有者にそう伝えてほしいと頼む手順が design に無い。この spec の PR は所有者が承認してマージするので、所有者が何も言わなければ、メモリの決まりは消えず、要件5の2と3は満たされない。メモリは所有者の PC にだけあるので、消えていないことに所有者は気づかない。先例の `claude-usage-reduction` の design は、マージのあとに Claude が行う作業に「頼み」の欄を置き、出荷の報告と PR の本文に頼みの文を1回だけ書くことを決め、tasks のタスク4.2がそれを実装した。この design には頼みの欄が無いので、tasks は、頼みの文をどこに何回書くかと、`_保留:_` のタスクの引き金を所有者が知る手段を決められず、tasks の審査で design に戻ることになる | 「消すとき」に「頼み」を足す。たとえば「Claude は、この spec の PR を出荷したことの報告と PR の本文に、『PR をマージしたら、マージしたことを Claude に1回伝えてください』の頼みを1回だけ書く」のように、頼む場所と回数を書く。tasks でその文を書くタスクを置くことも添える |
| D1-2-2 | 低 | design.md `inject-writing-rules.sh` の節の「権限」 | Claude がフックとテストと `.claude/settings.json` の全文を作る場所を scratchpad としている。`claude-usage-reduction` の tasks.md の実装のメモは、scratchpad が会話ごとに別の場所になり、所有者の返事が新しい会話で来たときや、別の実装役が続きを作るときに見つからないため、作業フォルダの `.claude/.state/<feature>/` の下(git の管理外で、deny の対象外)に置いたと記録している。`/kiro-impl` では実装役の補助役が作り、親の会話が所有者に頼むので、この spec でも同じことが起きる。先例のメモに従って実装のときに置き場所を決められるので、設計のやり直しにはならない | 「権限」の置き場所を「作業フォルダの `.claude/.state/owner-readable-writing/` の下に、リポジトリと同じ並びで作る」のように、会話が変わっても見つかる場所に書き換える |

### 前の段階への指摘

なし

- 往復: 2回目 / 高0 中1 低1

## サイクル1 往復3(2026-10-19)

### 審査の範囲

範囲: 差分

- design.md 「メモリの移し替え」の「消すとき」(D1-2-1 の直し): 頼みを出荷の報告と PR の本文に1回ずつ書く形が、`/ship` の手順で書ける形かを見た。`/ship` の「PR作成」は PR の本文に必ず含める行を定めるだけで、節を足すことを止めていない。先例の `claude-usage-reduction` の tasks.md の実装のメモ「出荷のとき」も、PR の本文の節と出荷の報告に頼みの文を1回ずつ書いている。この design の形は先例と同じで、tasks で頼みの文を書くタスクを置ける
- design.md 「メモリの移し替え」の「示すとき」と「権限」、requirements.md 要件5の2・3: 「消すとき」の直しのあとも、マージのあとに消すこと、一覧を示すこと、所有者の PC の Claude だけが行うことと食い違わないかを見た。食い違いは無かった
- design.md 「全体の構成」の段落(決まりの本文を1か所にだけ書く): 「フック、CLAUDE.md、`spec-writing.md`、`spec-style-checker` の定義は…指すだけにする」の文が消え、「決まりの本文が1か所にしか無いので」に変わったので、消えた4つの名指しが部品の節に移っているかを見た。CLAUDE.md の1行、`spec-writing.md` の直し、`spec-style-checker.md` の直しの3つの節に「決まりの本文を写さず、`owner-writing.md` を指す文だけを書く」の文が足され、フックは `inject-writing-rules.sh` の節の「役割」の「フックは、決まりの本文と例を持たない」で元から決まっている。4つとも残っている
- design.md 「CLAUDE.md の作業規約の1行」「spec-writing.md の直し」「spec-style-checker.md の直し」に足した「写さず、指す文だけを書く」の文と、requirements.md 要件4の3(決まりと例をエージェントの定義とスキルの手順に写さない): 足した文が要件4の3と合うかを見た。合っている。`spec-writing.md` の直しでは、同じ節が「対応の行だけは要件の番号で書く」を `spec-writing.md` に残すと書いているが、これは移す決まりの本文ではなく spec の本文にだけある例外なので、足した文と食い違わない。`spec-style-checker.md` の「当てはめる決まり」に今ある例外の言い換え(「ラベル: 内容」など)は、往復1の D1-1-4(低・記録のみ)で挙げた残る参照の話で、足した文が新しく生む食い違いではない
- design.md `owner-writing.md` の節の「出どころが違っても同じことを決めている決まり」の段落と、requirements.md 「壁打ちで決めた、わかりにくい文の種類」の5回目、要件1の6: 「壁打ちの5回目で、spec の本文から所有者に送る4つの文すべてに広げると決めた4つの決まり」が requirements と合うかを見た。5回目は「spec の本文にだけある次の4つの決まりを、対象の4つの文すべてに広げる」と決め、挙げた4つ(番号だけで指さない、指す言葉で済ませない、まだ無い仕組みを主語にしない、英語と日本語を混ぜた決まり文句)はどれも要件1の6の7つに入っている。合っている
- design.md 「作るもの」のフックの行(「所有者が入力するたびに」を消した): フックがいつ動くかは `inject-writing-rules.sh` の節の「いつ動くか」と「全体の構成」の段落と「テストの方針」の1つ目で変わらず決まっている。「作るもの」はものの名前を並べる箇条なので、消しても決めごとは変わらない
- 実ファイル: `.claude/skills/ship/SKILL.md` の「PR作成」の手順と「Report」の節、`.kiro/specs/claude-usage-reduction/design.md` の「頼み」の欄と同じ spec の tasks.md のタスク4.2と実装のメモ「出荷のとき」「頼みの文」、`.claude/agents/spec-style-checker.md` の「当てはめる決まり」、`.kiro/settings/rules/spec-writing.md` の見出しの並びで、差分の前提が成り立つかを確かめた

### 申告

なし。「消すとき」に足した頼みの置き場所(出荷の報告と PR の本文に1回ずつ)は、往復2の申告1(所有者が伝えたときに始める)の決めごとの一部であり、先例の `claude-usage-reduction` と同じ形なので、新しく申告しない。

### 指摘

なし

### 前の段階への指摘

なし

- 往復: 3回で収束 / 未解決: 0件
