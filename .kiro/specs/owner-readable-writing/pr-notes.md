# 実装の記録

## タスク1.1 差し戻された文の集め方

### 読んだ会話の記録

- Claude は、`~/.claude/projects/` のうち、名前が `C--Users-dogis-Desktop-DockerWorkSpace-develop-KeirekiPro` で始まるフォルダを29開いた。29のうち、本体の作業フォルダのものが1つで、残りの28は worktree ごとのフォルダである。会話の記録のファイルが1つも無いフォルダが2つあった。
- Claude は、29のフォルダにある会話の記録のファイル129を読んだ。
- Claude は、所有者の発言のうち「わからない」「分からない」「意味」「わかりにくい」「とは?」「って?」「ですか?」を含む400字以下の発言を190件抜き出し、それぞれの直前に Claude が送った文を読んだ。190件のうち、所有者が文のわかりにくさを差し戻したものから、例の一覧の組を作った。
- Claude は、grep の言葉に当たらない所有者の発言のうち、タスク1.1 をチェックしたエージェントが見つけた2件(2026-08-25 の「理解不能」と、2026-10-13 の「確かめなんていう日本語は存在しません」)からも組を作った。組55と組62である。
- 190件のうち、組を作らなかったものの多くは、所有者が仕組みや言葉の中身を尋ねただけのものや、作業の進め方を差し戻したものである。
- 次の6件は、文の書き方を差し戻したと読める。4件からは組を作り、2件からは組を作らなかった。1件ずつ書く。
  - 2026-09-29T04:54: 所有者は、問われたことに答えずにほかの話をしたことと、説明の無い「記録」という言葉の2つを差し戻した。Claude は、04:54:18 の返事で、「記録」がわかりにくい言い方だったと認めている。「記録」の文から組69を作った。答えの中身の差し戻しからは、組を作っていない。
  - 2026-10-12T01:18: 直前の 00:51:03 の文は、テストの結果と「上の問いへの答えを待っています」だけの文である。所有者が差し戻したのは、その前の 00:44:15 に Claude が出した問いで、説明の無い「条件A」「session-overlap-guard」「Fable との壁打ち」を使っていた。この問いから組66を作った。
  - 2026-10-12T01:27: 直前の 01:23:58 の文は、2つの Issue の話を混ぜた説明で、788字の説明の全体が差し戻された。一部だけを切り出すと、何がわかりにくかったのかが伝わらないため、組にしなかった。
  - 2026-10-19T07:51: 直前の 07:51:32 の文は、組42の文を Claude が言い直した文で、所有者はこれも差し戻した。この文から組67を作った。
  - 2026-10-19T07:53: 所有者が差し戻したのは、わかりにくい報告が続いたことである。直前の文そのものを差し戻していない。
  - 2026-10-19T11:13:54 の「意味不明。しね。」: 直前の 11:13:28 の文は、組64の文から「文の読み直し」を言い換えた文で、所有者はこれも差し戻した。この文は、取り違えた中身を事実と違う「別のAIを一切使うな」と書き、2の後半の「チェックも全部自分でやる」が何のチェックかを書いていない。この文から組68を作った。
- メモリの no-unintelligible-reports.md に書いた「箱」の差し戻しは、会話の記録に元の文が見つからなかった。そのため、組65はメモリのファイルを出どころにした。メモリの writing-style-feedback.md に書いた「確かめ」の差し戻しは、会話の記録に元の文があったので、会話の日付を出どころにした(組62)。

### 壁打ちの各回と例の一覧の組

requirements.md の「壁打ちで決めた、わかりにくい文の種類」の各回について、その回の例から作った組の番号を次に書く。

| 回 | 組 |
|---|---|
| 1回目 | 1 |
| 2回目 | 2 |
| 3回目 | 3 |
| 4回目 | 3 |
| 5回目 | 4 |
| 6回目 | 5 |
| 7回目 | 6 |
| 8回目 | 7 |
| 9回目 | 8 |
| 10回目 | 9 |
| 11回目 | 10 |
| 12回目 | なし |
| 13回目 | 11 |
| 14回目 | 12 |
| 15回目 | 13 |
| 16回目 | 14 |
| 17回目 | なし |
| 18回目 | 15 |
| 19回目 | なし |
| 20回目 | 16 |

- 4回目は、硬い言い回しをわかりにくい文に入れないと決めた回である。4回目の例の「双方」「〜に限られる」「代替ではなく補完の関係にある」「失敗しうる」は、組3の差し戻された文に入っている。組3の書き直した文は、硬い言い回しを直したのではなく、3回目の専門用語の説明を足したものである。
- 12回目、17回目、19回目は、わかりにくい文に入れないと決めた回で、壁打ちでは例となる文を挙げていない。そのため、これらの回からは組を作っていない。

### 書かなかった文

Claude は、組ごとに、差し戻された文にまだ直していないセキュリティの穴の中身と秘密の値が無いことを読んで確かめた。該当する文は無かった。

## タスク1.3 メモリから移した書き方の決まり

### 移した決まりと、メモリのファイルの対応

「全部」は、ファイルに書かれていることがすべて書き方の決まりで、すべてを移したファイルである。「一部」は、ファイルに書き方の決まりのほかのことも書かれていて、書き方の決まりだけを移したファイルである。

| `owner-writing.md` の見出し | メモリのファイル | 全部か一部か |
|---|---|---|
| 造語を使わない | writing-style-feedback.md | 一部 |
| 括弧に補足を詰め込まない | writing-style-feedback.md | 一部 |
| 矢印でつながない | writing-style-feedback.md | 一部 |
| 見出しに、かぎ括弧の標語を付けない | writing-style-feedback.md | 一部 |
| 結論と所有者にしてほしいことを、返事の最初に書く | plain-language-for-decisions.md | 全部 |
| 文ごとに主語と目的語を書く | plain-language-for-decisions.md | 全部 |
| 実際に動く人や物を主語にする | plain-language-for-decisions.md | 全部 |
| 作業の中だけで使う呼び名を使わない | plain-language-for-decisions.md | 全部 |
| 造語を使わない | plain-language-for-decisions.md | 全部 |
| 何が起きればよいのかを具体的に書く | plain-language-for-decisions.md | 全部 |
| 依頼は1回の返事に1つだけ書く | plain-language-for-decisions.md | 全部 |
| 報告に仕組みの中の言葉を出さず、どれの話かを指す番号と名前は残す | plain-language-for-decisions.md | 全部 |
| 選択肢の名前は、選んだときに何が起きるかで書く | plain-language-for-decisions.md | 全部 |
| 選択肢を減らすときは、減らした理由を1つずつ書く | plain-language-for-decisions.md | 全部 |
| 返事の形は、場面ごとに決める | plain-language-for-decisions.md | 全部 |
| 問われたことには、まず短く結論だけを答える | answer-short-first.md | 全部 |
| 依頼は1回の返事に1つだけ書く | one-ask-at-a-time.md | 全部 |
| 依頼には、何のために要るのかと、Claude が自分でできない理由を書く | ask-with-reason.md | 全部 |
| 所有者が自分で決めた前提を説明しない | ask-with-reason.md | 全部 |
| 実際に動く人や物を主語にする | owner-manual-step-wording.md | 全部 |
| 所有者が自分で決めた前提を説明しない | owner-manual-step-wording.md | 全部 |
| 所有者に頼む手順には、押す場所、打つコマンド、うまくいったかの見分け方を書く | owner-steps-concrete-clicks.md | 全部 |
| 場面は、所有者がしたことと起きた出来事で書く | scenario-in-owner-actions.md | 全部 |
| 問いには、誰の、何についての問いかを書き、似たものを1つの問いに混ぜない | question-needs-explicit-subject.md | 全部 |
| 決まりと普通の判断で答えが決まることを、所有者に尋ねない | no-obvious-questions.md | 一部 |
| 考えを求められたら、結論と推奨を本文に書く | think-first-then-recommend.md | 全部 |
| 調べた結果は、すぐする対処と、長く続ける対処と、採らなかった案を一度に書く | relay-full-conclusion-no-flip.md | 全部 |
| 問われたことには、まず短く結論だけを答える | close-the-asked-question-first.md | 一部 |
| 考えを求められたら、結論と推奨を本文に書く | close-the-asked-question-first.md | 一部 |
| 確かめていないことを、確かめたように書かない | no-unverified-claims-in-reports.md | 一部 |
| 確かめていないことを、確かめたように書かない | explain-safety-blocks-plainly.md | 一部 |
| 割り込みの質問には、その質問にだけ答える | dont-press-pending-ask.md | 一部 |
| 読んで決めてもらう中身は、ボタン付きの質問ではなく、返事の本文に全部書く | askuserquestion-hides-content.md | 全部 |
| Issue に、所有者の話し言葉をそのまま引かない | issue-quote-casual-words.md | 全部 |
| 文の書き方を示すときは、原文のまとまりと書き直しを並べる | examples-must-be-full-passages.md | 全部 |
| 形が答えになることは、たたき台の全体を見せる | request-show-draft-not-chained-choices.md | 全部 |
| 文ごとに主語と目的語を書く | request-show-draft-not-chained-choices.md | 全部 |
| 「〜せず」「〜ずに」を重ねない | request-show-draft-not-chained-choices.md | 全部 |
| 出荷の報告に、アプリの機能の案内を書かない | no-auto-fix-offer.md | 全部 |
| spec に、手元にしかない情報と、この spec 自身の作り方を書かない | spec-no-local-or-self-references.md | 全部 |
| 自分の誤りの原因を、出どころを挙げて言い訳せずに書く | own-past-work-no-blame.md | 全部 |
| 作業の終わりに、自分が作った物の穴を並べて所有者に投げない | no-deferring-loose-ends.md | 一部 |
| 公開される文に、まだ直していないセキュリティの穴を書かない | no-public-vulnerability-issues.md | 一部 |
| 作業の中だけで使う呼び名を使わない | no-unintelligible-reports.md | 全部 |
| 造語を使わない | no-unintelligible-reports.md | 全部 |
| 種類の違うものを1つの言葉でまとめない | no-unintelligible-reports.md | 全部 |
| 文ごとに主語と目的語を書く | no-unintelligible-reports.md | 全部 |
| 所有者が知っている正式な名前を使う | no-unintelligible-reports.md | 全部 |
| 自分の文がおかしくて書き直したときは、「書き直した」と書く | no-unintelligible-reports.md | 全部 |
| 返事の形は、場面ごとに決める | reply-shape-by-situation.md | 全部 |
| 返事の形は、場面ごとに決める | request-grilling-style.md | 一部 |
| 選択肢を減らすときは、減らした理由を1つずつ書く | request-honor-owner-constraints.md | 一部 |
| 所有者に頼む手順には、押す場所、打つコマンド、うまくいったかの見分け方を書く | user-runs-github-write-commands.md | 一部 |

no-unintelligible-reports.md の「送る前にすること」は、見出しではなく、`owner-writing.md` の冒頭の「送る前の読み直し」の節に当たる。writing-style-feedback.md の「図の中の矢印は使ってよい」は、見出しではなく、`owner-writing.md` の「決まりの例外」の節に当たる。

### 一部を移したファイルに残すこと

- writing-style-feedback.md: 次の4つの決まりを残す。README、doc/ の文書、CLAUDE.md や SKILL.md のような AI 向けのファイル、システムが送る通知文は、`owner-writing.md` が決まりの対象にする4つの種類の文に入らないためである
  - README には、アプリの紹介だけを書く
  - README と doc/ の文書を書いたら、造語、個数の括弧、矢印、見出しの標語がないかを読み直す
  - AI 向けのファイルでも、造語を使わない
  - システムが送る通知文は、通知文の定型で書く
- no-obvious-questions.md: 今の不具合を残す案を推奨にしないという、推奨の中身の決まりを残す
- close-the-asked-question-first.md: 別のAIとの話し合いの依頼を、所有者が挙げた論点に絞るという、作業の進め方を残す
- no-unverified-claims-in-reports.md: 確かめるときにコンテナの中で動かして確かめるという、確かめ方を残す
- explain-safety-blocks-plainly.md: 書き込みと push が止められる原因と、止められない push の書き方を残す
- dont-press-pending-ask.md: 所有者の手で進められない事情が見えたら止まって待つという、作業の進め方を残す
- no-deferring-loose-ends.md: 自分が作った物の穴を同じ PR の中で直すという、作業の進め方を残す
- no-public-vulnerability-issues.md: リポジトリに跡が残らない手作業を先に勧めるという、直し方の決まりを残す。コミットのメッセージと PR のコメントに、まだ直していないセキュリティの穴を書かないという決まりも残す。この2つは、`owner-writing.md` が決まりの対象にする4つの種類の文に入らない
- request-grilling-style.md: `/request` で何を問いにしてよいか、いつ終えるかという、壁打ちの進め方を残す
- request-honor-owner-constraints.md: 問いを出す前に、所有者が決めたことを打ち消していないかを読むという、作業の進め方を残す
- user-runs-github-write-commands.md: `.github/` への書き込みを scratchpad で作り、写すコマンドを所有者に渡し、写したあとに一致を確かめるという手順を残す

### 移さなかったメモリのファイル

MEMORY.md の行のうち、上の表に無いファイルは次のとおりである。どれも、所有者に送る文の書き方の決まりを書いていない。

- 作業の進め方を書いたファイル: kiro-commands-human-typed.md、claude-gh-is-bot-user-gh-is-human.md、research-before-offering-options.md、evaluate-pipeline-not-assume-it.md、process-instruction-not-design-requirement.md、auto-merge-and-issue-close-by-workflow.md、ship-is-run-by-claude.md、no-new-mechanism-for-one-off.md、sessions-continue-after-merge.md、no-recurring-manual-work.md、aws-cli-uses-aws-login.md、no-backup-when-fixing-memory.md、spec-assume-team-and-all-os.md、rules-as-data-not-hardcoded.md、no-subagents.md、verify-with-raw-source-and-live-probe.md
- `doc/` の文書の書き方を書いたファイル: procedure-doc-only-steps.md、no-one-time-work-in-ops-docs.md。`doc/` の文書は、`owner-writing.md` が決まりの対象にする4つの種類の文に入らない
- 道具や仕組みの知識を書いたファイル: windows-powershell-hooks-bom.md、gradle-apply-from-classloader.md、shell-tests-need-container.md、github-token-automerge-pitfall.md、audit-notification-via-issues.md、audit-expected-list-change-pitfalls.md、frontend-test-writing-pitfalls.md、frontend-local-check-gaps.md、git-bash-slash-arg-conversion.md、settings-env-needs-new-session.md、desktop-worktree-loads-main-checkout-config.md、shellcheck-run-like-ci.md、docker-overlay-creates-empty-files.md、desktop-appdata-virtualized.md
- プロジェクトや作業の記録を書いたファイル: autonomous-pipeline-overview.md、pending-human-setup-steps.md、audit-automation-shipped.md、parallel-sessions-field-test.md、test-suite-durations.md、issue-566-session-switch-idea.md
