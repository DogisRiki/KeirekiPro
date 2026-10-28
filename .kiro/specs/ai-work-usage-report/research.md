# 調べた結果と設計の判断

## Summary
- **Feature**: `ai-work-usage-report`
- **Discovery Scope**: New Feature(開発の仕組みに、新しい記録と集計の仕組みを足す。既存のフック・スキル・並行作業のスクリプトとつなぐ)
- **Key Findings**:
  - Claude Code の会話の記録(JSONL)には、応答ごとのトークン数(キャッシュの書き込みは5分と1時間に分かれる)、モデル、時刻、ターンを始めた者、上限で止まった印、API の再試行、道具の呼び出しと結果、コマンドの名前と引数、ブランチの名前が残る。集計に要る数は、ほぼすべて会話の記録から取れる。ただし、Claude Code は既定で30日たった記録を消すので、数を手元に抜き出して残す仕組みが要る
  - 機械で読める公式の価格表は無い。価格は、公式の価格のページから、確かめた日を添えてリポジトリのデータのファイルに写す
  - GitHub Projects v2 は、トークンに `project` の権限を足すために、PC ごとに開発者がコマンドを打つ必要がある。要件1の7(コマンドを頼まない)に反するので、蓄積の一覧は、決まった題名の Issue に置く。台帳の Issue には、`lib-ledger-issue.sh` の前例がある
  - #659 の更新(題名の列を足す)は、既存の github.pl への拡張なので、Extension の調べ方(light)で調べた。GitHub は、一覧の Issue の列のリンクに、その Issue のカードを付けるので、題名の全文は一覧に書かなくても出る。表の中の題名は、コードの形にし、「\」と「|」を替えれば、どんな文字でも列がずれず、通知もつながりも作らない。一覧に今ある行への題名の書き足しは、所有者が仕組みに入れないと決めたので、設計に手順を置かない(#659)

## Research Log

### 会話の記録の形式(2026-10-24 に、この PC の記録で確かめた)
- **Context**: 作業時間とトークン数と回数を、何から数えられるかを確かめる
- **Sources Consulted**: `~/.claude/projects/` の下の JSONL(1,454個、1.18GB、最も古い記録は 2026-08-10)。公式のフックの文書(下の References)
- **Findings**:
  - 置き場所は `~/.claude/projects/<作業フォルダの場所を符号にした名前>/<sessionId>.jsonl`。補助役は `<sessionId>/subagents/agent-<id>.jsonl` と、`agentType` と `model` を持つ `agent-<id>.meta.json`
  - `assistant` の行の `message.usage` は、`input_tokens` `cache_creation_input_tokens` `cache_read_input_tokens` `output_tokens` を持ち、`cache_creation` の中で `ephemeral_5m_input_tokens` と `ephemeral_1h_input_tokens` に分かれる。`server_tool_use.web_search_requests` `speed`(この PC では `standard` だけを見た)`inference_geo`(`global` と `not_available` を見た)も持つ
  - 同じ応答が、1つの `message.id` で2行以上に書かれる。重なりはファイルをまたいでも起きるので、重なりは全体の `message.id` で除く。モデルが `<synthetic>` の行は、Claude Code が自分で作った行なので除く
  - 上限で止まった印は、`<synthetic>` の行の `error` が `rate_limit` で、`quotaLimits.resetsAt` を持つ。API の混雑は、`system` の行の `subtype` が `api_error` で、`retryInMs` を持つ
  - `user` の行の `turnOrigin` が、ターンを始めた者を表す(`human` `task_notification` `peer` `sdk` `scheduled`)。応答の終わりは `stop_reason` の `end_turn`
  - 道具の呼び出しの行に `permissionDecision` が付く。`source` が `user_` で始まるとき(`user_temporary` など)は、所有者が権限の確認に答えた呼び出しである。所有者が答えた時刻は記録に無い
  - 所有者が打ったコマンドは、`user` の行の `<command-name>` と `<command-args>` に残る。Claude がスキルを起動したときは、`Skill` の道具の呼び出しの `skill` と `args` に残る。どの行も `gitBranch` の欄を持つ。PR を作った行には `prNumber` が残る
- **Implications**: 数の抜き出しは、会話の文を残さず、数と名前だけを残す形にできる。応答の重なりを全体で除くので、抜き出した記録は応答の `message.id` を持つ

### フックの入力(2026-10-24 に公式の文書で確かめた)
- **Context**: 記録を付けるフックを、どの出来事に付けるかを決める
- **Sources Consulted**: https://code.claude.com/docs/en/hooks
- **Findings**:
  - どの出来事にも `session_id` `transcript_path` `cwd` `hook_event_name` が付く
  - `PostToolUse` には `tool_use_id` と `duration_ms` が付く。`duration_ms` は道具の実行時間で、権限の確認と PreToolUse のフックの時間を含まない
  - `PermissionRequest` には `tool_use_id` が付かない
  - `SubagentStop` には `agent_id` `agent_type` `agent_transcript_path` `last_assistant_message` が付く
  - コマンドのフックは `"async": true` で、Claude を待たせずに裏で動かせる。裏で動くフックの出力は、Claude への文脈にならない
  - `SessionStart` のフックは、`hookSpecificOutput.additionalContext`(10,000文字まで)で、会話の始めに Claude へ文脈を渡せる
- **Implications**: 権限の確認で所有者を待った時間は、`PermissionRequest` では呼び出しと結び付けられない。そこで、道具の呼び出しから結果までの時間から `PostToolUse` の `duration_ms` を引いた残りを、権限の確認の待ちとする。記録を付けるフックは裏で動かし、会話を待たせない

### 価格(2026-10-24 に確かめた)
- **Context**: 要件4の換算に使う価格を決める
- **Sources Consulted**: https://platform.claude.com/docs/en/about-claude/pricing
- **Findings**(米ドル/100万トークン。入力、5分の書き込み、1時間の書き込み、読み込み、出力の順):
  - Fable 5.1: 10 / 12.50 / 20 / 0.25 / 50
  - Fable 5: 10 / 12.50 / 20 / 1 / 50
  - Opus 5.5: 4 / 5 / 8 / 0.20 / 20
  - Opus 5、4.8、4.5〜4.7: 5 / 6.25 / 10 / 0.50 / 25
  - Opus 4、4.1: 15 / 18.75 / 30 / 1.50 / 75
  - Sonnet 5.5: 2 / 2.50 / 4 / 0.10 / 10
  - Sonnet 5: 2 / 2.50 / 4 / 0.20 / 10
  - Sonnet 4、4.5、4.6: 3 / 3.75 / 6 / 0.30 / 15
  - Haiku 5.5(入力が10万トークン以下): 0.10 / 0.125 / 0.20 / 0.01 / 0.50
  - Haiku 5.5(入力が10万トークンを超える): 0.50 / 0.625 / 1 / 0.05 / 2.50
  - Haiku 4.5: 1 / 1.25 / 2 / 0.10 / 5
  - `inference_geo` が `us` のときは1.1倍。fast mode は、Opus 5.5 が入力 8 / 出力 40、Opus 5 と 4.8 が 10 / 50。Web 検索は1,000回で10ドル。batch と Priority Tier は Claude Code で使わないので扱わない
  - 機械で読める公式の価格表は無い
- **Implications**: 価格はデータのファイルに写し、出どころの URL と確かめた日を同じファイルに持たせる。価格が変わったときは、データのファイルだけを直す

### 既存の記録の欠け
- **Context**: Issue と会話の結び付けに、並行作業の記録(`.git/keirekipro-parallel/`)を使えるかを確かめる
- **Sources Consulted**: `.claude/scripts/parallel/session.sh`、`.claude/hooks/session-registry.sh`
- **Findings**: `issues/<N>.json` は上書きの記録で、いつ受け持ったかの履歴が残らない。`sessions/<sid>.json` は、会話が終わると消える
- **Implications**: 並行作業の記録は集計に使わない。受け持ちの出来事は、会話の記録の中のコマンド(`/start #N`、`session.sh check-start|claim|takeover <N>`)から抜き出す。会話の記録から抜き出せば、仕組みが入る前の会話にも同じ見分け方が効くので、さかのぼりの集計(要件9)にも使える

### 往復と手戻りを数える材料
- **Context**: 往復と手戻りの表の行ごとに、数える材料があるかを確かめる
- **Sources Consulted**: `.claude/skills/spec-review/SKILL.md`、`.claude/skills/kiro-impl/templates/reviewer-prompt.md`、`.claude/skills/start/SKILL.md`、`.claude/skills/ship/SKILL.md`、`.github/workflows/codex-review.yml`、spec.json の `approval_history`
- **Findings**:
  - spec の審査役は、依頼文に `STAGE` `CYCLE` `ROUND` の欄を持つ。補助役の会話の記録から、段階と往復の組を数えられる
  - タスクごとの確認役は、最後の報告に `- VERDICT: APPROVED` か `- VERDICT: REJECTED` の行を必ず書く(reviewer-prompt.md の決まり)。補助役の会話の記録の最後の応答から、差し戻しを数えられる
  - 前の段階に戻ったことは、spec.json の `approval_history`(`stage` `revoked_at` `revoked_for`)に残る。`revoked_for` が「Issue #N のための更新」の要素は、新しい Issue のための更新で、手戻りではない
  - Codex の往復は、PR のコメントの見出し「## Codex Review(自動クロスレビュー)」で数えられる。決めた方式から外れたことは、同じコメントの表の「沿っていない」で分かる
  - 200行の検査と CI の失敗は、PR のコミットごとの検査の結果(check run)で分かる。数えるときは、`rerun-approval-gated-checks` `update-pr-branches`、取り消された検査、承認を待つ検査を外す
  - 記録が無く、新しく残す必要があるもの: 承認の前に所有者が spec の直しを求めたこと、同じ失敗を3回続けて止まったこと、spec 無しから spec に切り替えたこと
- **Implications**: 記録が無い3つだけを、スキルが印を残すコマンドで記録する。ほかは、会話の記録・spec.json・GitHub から数える

### 別に起こしたセッション
- **Context**: 本体の会話が別に起こしたセッション(デスクトップアプリの機能)を、Issue に結び付ける方法を確かめる
- **Sources Consulted**: この PC の会話の記録と、デスクトップアプリの手元の記録
- **Findings**: 子の会話の記録には、親を指す欄が無い。デスクトップアプリの手元の記録(Windows では `AppData/Local/Claude-Data/` の下の `local_<uuid>.json`)は `cliSessionId` と `spawnedFrom` を持つが、公式の文書が無い
- **Implications**: 別のセッションは、まずブランチで結び付ける(同じブランチで動くか、`Refs`/`Closes` で Issue を指す PR のブランチで動く)。ブランチで結び付かないときだけ、デスクトップアプリの手元の記録を補助に使う。どちらでも結び付かないときは、要件2の8の注記で扱う

### ターミナルとデスクトップアプリの違い(2026-10-25 に確かめた)
- **Context**: Claude Code をターミナルで動かす PC と、デスクトップアプリを入れていない PC でも、この設計が動くかを確かめる
- **Sources Consulted**: 公式の設定の文書、公式のデスクトップアプリの文書、公式の `.claude` ディレクトリの文書(下の References)。この PC で、ターミナルの Claude Code 2.1.302 を `claude --setting-sources user "Reply with the single word OK. Do not use any tools."` で1回動かして残った会話の記録と、デスクトップアプリの会話の記録
- **Findings**:
  - 公式の設定の文書は、ターミナル、VS Code、JetBrains、デスクトップアプリが同じ設定のファイルを読むと書いている。`.claude/settings.json` のフックは、どれで動かしても動く
  - 公式の `.claude` ディレクトリの文書は、会話の記録を `~/.claude/projects/<project>/<session>.jsonl` に残すと書いている。Windows では `~/.claude` は `%USERPROFILE%\.claude` である
  - ターミナルで動かした会話の記録は、デスクトップアプリの会話と同じ `~/.claude/projects/` の下の、同じ作業フォルダのディレクトリに残った。行の `entrypoint` は、ターミナルでは `cli`、デスクトップアプリでは `claude-desktop` だった
  - ターミナルで動かした会話の記録にも、`turnOrigin` の `human`、`gitBranch`、`message.usage` の4種類のトークン数、`cache_creation` の `ephemeral_5m_input_tokens` と `ephemeral_1h_input_tokens`、`stop_reason` の `end_turn`、`speed`、`inference_geo` があった
  - ターミナルで動かした会話は、セッションを別に起こす道具(`mcp__ccd_session__start_session`)を持たなかった。公式のデスクトップアプリの文書も、セッションを別に起こすことをデスクトップアプリの機能として書いている
  - ターミナルでもデスクトップアプリでも、会話の記録の最初の数行(`mode` `permission-mode` `bridge-session` `queue-operation` などの行)は `cwd` の欄を持たなかった。デスクトップアプリの会話の記録の `cwd` は、Windows では `\` で区切られていた
  - ターミナルで確かめた会話は、道具を使わない会話1つだけである。ターミナルの会話の、道具の呼び出しの行に付く `permissionDecision`、補助役の記録、`task_notification` の `turnOrigin` は、まだ確かめていない。この PC の `-p` で動かした会話(`entrypoint` が `sdk-cli`)の記録にも `permissionDecision`(`source` が `config` のもの)があったので、この欄はデスクトップアプリではなく Claude Code の本体が書いていると見られる。ただし、ターミナルで所有者が権限の確認に答えたときの `source` の値は、確かめていない
  - この PC の `-p` で動かした会話(`entrypoint` が `sdk-cli`)では、書き込みの `turnOrigin` は `sdk` だった。この PC の `-p` の会話は、どれも一時のフォルダ(`AppData/Local/Temp/claude/` の下)で動いた試しの会話で、このリポジトリの作業フォルダの会話ではなかった
- **Implications**: この設計が使うもののうち、デスクトップアプリの手元の記録だけが、デスクトップアプリを入れた PC にしか無い。デスクトップアプリの手元の記録が無いときは、extract.pl はそれを読まずに続ける。このリポジトリの会話を見分けるときは、`cwd` の欄を持つ最初の行を使い、Windows では区切りをそろえて比べる。`-p` の会話は、この PC ではこのリポジトリの作業フォルダの外で動いているので、このリポジトリの会話の見分け方で集計から外れる

### GitHub の置き場(2026-10-24 に確かめた)
- **Context**: 集計と蓄積の一覧の置き場を決める
- **Sources Consulted**: `gh repo view`、`gh auth status`、`.github/scripts/lib-ledger-issue.sh`、GitHub の Issue の本文の上限
- **Findings**:
  - リポジトリは公開で、Discussions と Wiki は無効。owner は個人のアカウント
  - gh のトークンの権限は `read:org` `repo` `workflow` で、`project` が無い
  - Issue の本文の上限は65,536文字。Issue を閉じた PR は 2026-08〜10 の3か月で122件あり、年に600〜700件のペースである
  - 台帳の Issue には、決まった題名の完全一致で探し、閉じていても使い続け、同じ題名が2つ以上あれば最小の番号を使う前例がある(`lib-ledger-issue.sh`)
- **Implications**: 一覧を1つの本文だけに置くと、1年ほどで上限を超える。一覧は、本文と、区切りごとのコメントに分けて置く

### 共同作業者から外したアカウントの関係の欄(2026-10-25 に確かめた)
- **Context**: github.pl は、コメントと一覧の Issue を、リポジトリとの関係の欄(`author_association`)が `OWNER` か `COLLABORATOR` のものに限って読む。Claude の gh がログインするアカウントを替えたあと、前のアカウントを共同作業者から外すと、前のアカウントが書いたコメントと Issue の関係の欄が変わるかを確かめる
- **Sources Consulted**: GitHub の REST API の文書(Issues、Issue comments)、GraphQL の `CommentAuthorAssociation` の説明、GitHub の公式ブログ、利用者の報告、このリポジトリの Issue とコメントの関係の欄
- **Findings**:
  - GitHub は、関係の欄を、書いたときの値で残さず、読むたびにその時点の関係で返す。根拠は次の3つである
    - このリポジトリの PR #133 は、dependabot が 2026-08-13 05:42 に作り、マージされずに閉じた。dependabot の PR が初めてマージされたのは、それより4時間あとの #137 である。それでも、今 #133 を読むと、関係の欄は `CONTRIBUTOR` を返す。#133 のブランチには、作る1秒前の dependabot のコミットがあり、GitHub がマージされていないブランチのコミットも数えているなら、この例だけでは決め手にならない
    - GitHub の公式ブログは、PR がマージされるとその人のコメントに contributor の印が付き、この情報が API の `authorAssociation` と同じであると書いている。前に書いたコメントの値が、あとの出来事で変わることになる
    - 利用者の報告(huggingface/relore #74)は、組織を離れたメンテナが2023年に書いたコメントが、今は `CONTRIBUTOR` を返すと報告している
  - GitHub の API の文書は、関係の欄を読むたびに計算するとも、書いたときの値を残すとも書いていない
  - このリポジトリでは、今の共同作業者の DogisRiki-bot が書いた Issue とコメント(463件)は、どれも `COLLABORATOR` を返す。共同作業者でなく、マージ済みのコミットを持つ dependabot は `CONTRIBUTOR`、共同作業者でなく、コミットを持たない github-actions は `NONE` を返す
- **Implications**: 前のアカウントを共同作業者から外すと、前のアカウントは DogisRiki-bot と同じくマージ済みのコミットを持つので、関係の欄は `CONTRIBUTOR` を返し、github.pl は前のアカウントが書いたコメントと一覧の Issue を読まなくなる。前のアカウントを共同作業者のまま残せば、関係の欄は、読むたびに計算するときも、書いたときの値を残すときも、`COLLABORATOR` を返す。そのため、所有者が前のアカウントを外さない決まりにすれば、設計は、API の文書に書かれていない点に頼らない

### 上限が戻ったあとの再開の知らせ(2026-10-25 に確かめた)
- **Context**: このリポジトリには、使う量の上限で止まった会話を、上限が戻ったあとに再開させるフック `.claude/hooks/resume-after-usage-limit.sh` がある。補助役か別に起こしたセッションが上限に当たったときは、本体の会話の記録に `<synthetic>` の上限の行が残らないので、上限が戻るのを待っていた時間を、上限の印だけでは見分けられない
- **Sources Consulted**: `.claude/hooks/resume-after-usage-limit.sh`、`.claude/settings.json` のフックの登録、この PC の会話の記録(`review-opus-support-628fae` の作業フォルダの会話 `a7a76ff5-76ea-4100-81e6-67d6358d15ed`)
- **Findings**:
  - `.claude/settings.json` は、このフックを `Stop` と `StopFailure` に `asyncRewake` で登録している。フックは、上限が戻る時刻まで待ってから、終了コード2で、印 `[resume-after-usage-limit]` で始まる文を標準エラーに出し、会話を再開させる
  - 会話 `a7a76ff5-…` では、`stop_reason` が `end_turn` の応答(2026-10-19T05:46:02Z)のあとに、`turnOrigin` が `task_notification` の `user` の行(2026-10-19T05:50:16Z)が残っている。この行の文は、`Stop hook blocking error from command "Stop": [resume-after-usage-limit] 使う量の上限が戻る時刻を過ぎました。` を含む。この間に `<synthetic>` の上限の行は無い
- **Implications**: extract.pl は、`turnOrigin` が `task_notification` の行の文が印 `[resume-after-usage-limit]` を含むかで、上限が戻ったあとの再開を見分ける。report.pl は、その行の直前の時点からその行までを、上限で止まった時間に入れる

### 表の中の題名の出方(2026-10-28 に確かめた)(#659)
- **Context**: 要件11の6のとおり、Issue の題名にどんな文字が入っても、一覧の表の列がずれず、通知とほかの Issue へのつながりを作らない書き方を決める
- **Sources Consulted**: GitHub の Markdown を HTML にする API(`gh api -X POST markdown` の gfm の形、`context` にこのリポジトリ)、GitHub Flavored Markdown の仕様の表とコードの形の節
- **Findings**:
  - 表の中のコードの形の中の「@octocat」「#12」「:smile:」「<!--」は、HTML で `<code>` の中にそのままの文字で出る。アカウントへのつながり(`user-mention`)も Issue へのつながりも作らない。コードの形の外の「@octocat」は `user-mention` のつながりになる
  - 表の中では、GitHub は、コードの形を読む前に「\|」を「|」に戻すので、コードの形の中の「\|」は「|」で出て、列を区切らない。「\」も「\」で出る
  - 2026-10-28 に確かめ直した入力と出力は、次のとおりである。表の中のコードの形の「a\\b」は「a\\b」で出る。「a\b」は「a\b」で、「\\\|」は「\\|」で、「x\|y」は「x|y」で、「a\\」は「a\\」で出る。GitHub は、表の中で「\\」を「\」に戻さないほかの「\」で始まる組み合わせ(「\*」など)は、コードの形の中ではそのまま出る
  - 題名の中に「`」があっても、囲む「`」を題名の中の最も長い続きより多くすれば、コードの形は途中で終わらない。囲む「`」と題名の間に空白を1つずつ置くと、GitHub はその空白を除いて出す
  - リンクの題名(`[#526](URL "題名")`)は、HTML の `title` 属性になり、その中の「<!--」と「"」は文字として出る
- **Implications**: github.pl は、題名の欄を、制御文字を空白に替え、20字に縮め、「|」を「\|」に替えてから、コードの形にする。「\」は替えない。実装のときに、同じ API で、特別な字を含む題名の行を確かめ直す

### Issue のカード(2026-10-28 に確かめた)(#659)
- **Context**: 要件11の3のとおり、所有者が一覧の Issue の列の番号にマウスを置いたときに、題名の全文が出る仕組みを決める
- **Sources Consulted**: 上の API の出力、内蔵のブラウザで開いた一覧の Issue(#654)
- **Findings**:
  - GitHub は、Issue の URL で始まるリンク(集計のコメントの `#issuecomment-` の付いた URL を含む)に、`data-hovercard-type="issue"` と `data-hovercard-url` を付ける
  - 内蔵のブラウザで #654 の Issue の列の番号にマウスを置くと、その Issue の題名の全文を持つカードが出た。カードは、GitHub にログインしている人に出る
- **Implications**: 一覧には、題名の全文を書かない。Issue の列の今のリンクのままで、要件11の3を満たす。カードはその時点の題名を出すので、一覧の題名の欄(足したときの題名)と食い違うことがある。要件11の4はそれを認めている

### 変更の前の github.pl が一覧を書き直したとき(2026-10-28 に確かめた)(#659)
- **Context**: 題名の列を足す変更を取り込んでいない会話が一覧に行を足したときの動きを調べる
- **Sources Consulted**: `.claude/scripts/usage/github.pl`(`parse_row` `read_list` `write_list`)
- **Findings**:
  - 今の `parse_row` は、7つの欄の行だけを正規表現で読み、ほかの形の行を読まない。`write_list` は、読めた行と足す行だけで、本文とページのコメントを書き直す。そのため、変更の前の github.pl は、8つの欄の行を一覧から消す
  - 今のページのコメントの印の正規表現は `keirekipro-usage-list:v1 page=` で、案の索引の印は `keirekipro-usage-proposals:v1` である。どちらも `keirekipro-usage-list-index:v1` に当たらないので、変更の前の github.pl は、新しい番号の索引のコメントを読まず、書き直さない
- **Implications**: 変更の前の github.pl は、8つの欄の行を一覧から消す。所有者は、2026-10-28 に、Issue #659 の作業を、一覧に題名の列を足すことと、今ある行に題名を一度だけ書き足すことに絞った。そのため、この設計は、消えた行を戻す仕組みを作らない(「Decision: 今ある行への題名の書き足し」)

## Architecture Pattern Evaluation

| Option | Description | Strengths | Risks / Limitations | Notes |
|--------|-------------|-----------|---------------------|-------|
| 抜き出しと集計を分ける | フックが会話の記録から数だけを手元に抜き出し、マージのあとに集計の部品が抜き出した数を読む | 古い記録が消えても数が残る。会話を待たせない。さかのぼりも同じ部品で読める | 抜き出した記録の形を、Claude Code の記録の形の変化に合わせ続ける必要がある。合わせる先は抜き出しの部品の1つに限る(Decision「Claude Code の形を知る部品を1つにする」) | 採る |
| マージのときに会話の記録を直接読む | 抜き出しをせず、集計のときに会話の記録を全部読む | 部品が1つで済む | 30日で消えた会話を数えられない(要件2の7に反する) | 採らない |
| 記録の形を Claude Code の OpenTelemetry で取る | Claude Code の計測の出力を受ける仕組みを立てる | 公式の出力の形 | 受け取る仕組みを PC ごとに立てる必要があり、開発者の作業が増える | 採らない |

## Design Decisions

### Decision: 蓄積の一覧の置き場
- **Context**: 要件7の一覧を、GitHub 上の1か所に置き、行を終了日の順に並べ、同時に足しても消えないようにする
- **Alternatives Considered**:
  1. GitHub Projects v2 — 並べ替えと絞り込みの画面がある
  2. 決まった題名の Issue の本文と、区切りごとのコメント
  3. 専用のブランチの Markdown のファイル — push の拒否で同時の書き込みを見分けられる
  4. Discussions、Wiki — 無効
- **Selected Approach**: 2。題名「AIの作業の集計の一覧」の Issue を、閉じたまま置く
- **Rationale**: 1は、`project` の権限を足すために PC ごとに `gh auth refresh -s project` を打つ必要があり、要件1の7に反する。並べ方の設定も画面で手で行う。3は、CLAUDE.md の「push 先は feature ブランチのみ」から外れ、push のたびにワークフローが動くおそれがある。4は使えない
- **Trade-offs**: Issue の本文の書き換えには、同時に書いたときに後から書いたほうが勝つ。書いたあとに読み直して自分の行を確かめ、無ければ足し直す。足し直しの漏れは、次の会話の始めに確かめ直す
- **Follow-up**: 区切りの行数(300行)で、本文とコメントが上限に届かないことをテストで確かめる。#659 からは、ページの全文の UTF-8 のバイトの数でも区切る(「Decision: ページをバイトの数でも分ける」)(#659 で変更)

### Decision: 受け持ちの見分け方
- **Context**: 要件2の3と4で、会話がどの Issue をいつ受け持ったかを決める
- **Alternatives Considered**:
  1. `session.sh` に、受け持ちを追記する記録を足す
  2. 会話の記録の中のコマンドから抜き出す
- **Selected Approach**: 2。`/start #N`(所有者が打ったコマンドか、Claude が起動した `start` のスキル)と、Bash で呼んだ `session.sh check-start|claim|takeover <N>` と、まとめて閉じる `gh issue close <M> --reason "not planned" --comment "#<K> に統合した。"` を、抜き出しの部品が見分ける
- **Rationale**: 仕組みが入る前の会話にも同じ見分け方が効き、さかのぼりの集計(要件9)に使える。`session.sh` を変えずに済む
- **Trade-offs**: コマンドの文字列の形に頼る。形が変わったときは、抜き出しの部品の見分けの決まりも直す(設計を見直すきっかけに書く)
- **Follow-up**: 抜き出しのテストに、3つの形のコマンドを入れる

### Decision: 往復と手戻りのうち、記録が無いものの残し方
- **Context**: 要件6の3で、仕組みが入ったあとはすべての行を数える
- **Alternatives Considered**:
  1. 会話の文から推して数える
  2. スキルが、決まった時点で印を残すコマンドを呼ぶ
- **Selected Approach**: 2。`usage.sh mark <種類>` が、手元の記録に1行を追記する。種類は `spec-fix`(changed 付きの審査)、`same-failure`(同じ失敗3回で止まった)、`switch-to-spec`(spec に切り替えた)の3つ
- **Rationale**: 会話の文は数えるための形をしていない。会話の文を読む数え方は、要件10の「会話の文を書かない」と同じ理由で避ける
- **Trade-offs**: Claude がスキルの手順どおりにコマンドを呼ばないと、数が漏れる

### Decision: 所見の書き方
- **Context**: 要件8の所見は、数だけでは作れない判断を含む
- **Alternatives Considered**:
  1. スクリプトが決まった文の型で所見を作る
  2. スクリプトが集計と過去との比べを作り、Claude が所見を書き、スクリプトが出す
- **Selected Approach**: 2。`usage.sh draft` → Claude が所見のファイルを書く → `usage.sh publish`
- **Rationale**: 直す案は Claude の判断である。出す前に、スクリプトが所見の文に PC の中の場所とユーザー名が無いかを機械で確かめる

### Decision: 会話の相手が所有者かどうかの見分け方
- **Context**: 要件8の3と4
- **Alternatives Considered**:
  1. PC ごとの git の設定 `keirekipro.owner`
  2. データのファイルに、所有者の GitHub のアカウント名を書き、`gh api user` のアカウント名と比べる
  3. Claude が、まだ答えていない案があり、その PC で所有者かどうかが決まっていないときに、会話の相手に所有者かを1回だけ尋ね、答えを手元の記録の `state.json` の `owner` に書く
- **Selected Approach**: 3
- **Rationale**: 2は成り立たない。`doc/開発フロー/参加者セットアップ手順.md` の2-2のとおり、参加者全員の Claude の gh は、同じ bot のアカウント `DogisRiki-bot` でログインするので、`gh api user` は、所有者の会話でもほかの開発者の会話でも `DogisRiki-bot` を返す(設計の審査の D1-1-1)。1は、所有者か開発者が `git config` を打つ必要があり、要件1の7(コマンドを打つよう頼まない)に反する。3は、会話の相手が答えるだけで決まり、答えは clone ごとに残るので、同じ PC で尋ね直さない
- **Trade-offs**: 所有者が新しい PC か新しい clone で会話を始めると、もう一度尋ねる。会話の相手の答えをそのまま信じるので、所有者でない人が「所有者だ」と答えると、その人に案を尋ねる

### Decision: Claude Code の形を知る部品を1つにする
- **Context**: 所有者が、Claude Code の会話の記録の形が変わったとき、直すのが1ファイルで済むことを求めた(2026-10-24 の会話。設計の審査のサイクル1のあと)。サイクル1の設計では、集計の部品が `stop_reason` `turnOrigin` 道具の名前などの生の値を読み、フックのスクリプト3つがフックの入力の欄を読んでいたので、形が変わると3〜5ファイルを直す必要があった
- **Alternatives Considered**:
  1. 生の値を抜き出したまま残し、集計の部品とデータのファイルで値を見分ける
  2. 抜き出しの部品が、Claude Code の値をこの仕組みの中の値(`msg.end` `turn.from` `tool.kind` `perm` など)に置き換えてから書き、フックのスクリプトは入力をそのまま抜き出しの部品に渡す
- **Selected Approach**: 2。フックのスクリプトは `usage-hook.sh` の1つにし、5つの時点に登録する。抜き出しの部品が `hook_event_name` で時点ごとのすることを分け、`SessionStart` の出力の形も書く
- **Rationale**: 1では、値の名前と意味が集計の部品・データのファイル・フックのスクリプトに散る。とくにフックのスクリプトは `.claude/hooks/` の下にあり、直すたびに所有者の承認が要る。2では、欄の名前・置き場所・値が変わったときに直すのは抜き出しの部品とそのテストの作り物の記録だけで済む
- **Trade-offs**: `PostToolUse` で道具を使うたびに perl が起きる。抜き出しの部品は、この時点では入力を JSON として解かず、正規表現で3つの欄だけを取り出して1行足す。フックは async で動くので、会話は待たない。数の材料そのもの(例 `duration_ms`)が無くなったときは、抜き出しの部品の直しでは足りず、数え方を見直す
- **Follow-up**: 集計の部品・GitHub の部品・入口・データのファイル・フックのスクリプトに、Claude Code の欄の名前と値が現れないことを、文字列の検索のテストで確かめる

### Decision: 言語
- **Selected Approach**: 抜き出しと集計は perl(JSON::PP)、フックと入口は bash
- **Rationale**: ホストの前提は bash と perl(JSON::PP)で、jq に依存しない(CLAUDE.md の Git規約)。1GB を超える記録を読むので、bash だけでは遅い

### Decision: さかのぼりの集計で出せなかった集計を、仕組みで出し直さない
- **Context**: 所有者は、さかのぼりの集計を、毎回動く仕組みに入れない一度だけの作業と決めた(要件10の7)。前の設計は、さかのぼりの集計の Issue に `backfill: true` の印を書き、`pending` がその Issue を分けて出し、会話の始めのフックが出し直しを知らせていた
- **Selected Approach**: `backfill` の印を無くす。`draft <N> --backfill` は、`draft <N>` と同じ集計しない印(`before-system` か `system-pr`)を書いてから集計を続ける。`pending` は、閉じた時刻の絞り込みと集計しない印の決まりを、まだ出していない Issue にも、一覧か案の索引への書き込みが残った Issue にも当てる。そのため、さかのぼりの集計の Issue は、会話の始めのフックに知らされない
- **Rationale**: 仕組みにある印と絞り込みだけで、さかのぼりの集計の Issue を仕組みから外せる。さかのぼりの集計のための状態を、手元の記録に足さずに済む
- **Ordering**: `backfill-list` は、対象の Issue を、終了日(所有者の PC の時間帯の日付)の古い順に、終了日が同じなら番号の小さい順に並べる。一覧の行の並べ方と `past_rows` の数え方に合わせるためである
- **Note**: PR #651 で、`draft <N> --backfill` を無くし、`draft` は Issue の番号のほかの引数を受けなくなった。PR #652 で、`backfill-list` を無くした。さかのぼりの集計は、所有者に頼まれたときに、Claude が会話の中で一度だけ行い、仕組みは手順を持たない(PR #651 で変更済み)(PR #652 で変更済み)

### Decision: 題名の全文の出し方(#659)
- **Context**: 要件11の3
- **Alternatives Considered**:
  1. Issue の列のリンクに、GitHub が付けるカードを使う
  2. Issue の列のリンクに、リンクの題名(`title` 属性)として題名の全文を書く
  3. 題名の欄に全文を書き、表示だけを縮める
- **Selected Approach**: 1
- **Rationale**: 1は、今のリンクのままで、GitHub がカードに題名の全文を出す。2は、行に最大256文字の題名を持たせ、1行が長くなり、「"」の替え方の決まりが増える。3は、GitHub の Markdown に、表の欄の表示だけを縮める書き方が無い
- **Trade-offs**: カードは GitHub にログインしている人にだけ出る。所有者は一覧をログインして見るので、要件11の3を満たす

### Decision: 題名の欄の書き方(#659)
- **Context**: 要件11の2と11の6
- **Alternatives Considered**:
  1. コードの形にし、「\」と「|」だけを替える
  2. 題名の特別な字を、1字ずつ HTML の文字の参照(`&#64;` など)に替える
  3. 題名の特別な字を、1字ずつ「\」で替える
- **Selected Approach**: 1
- **Rationale**: 2と3は、GitHub が特別に扱う字(「@」「#」「<」「:」「*」「_」「~」「[」など)をすべて挙げる必要があり、挙げ漏れが通知やつながりを作る。1は、コードの形の中では GitHub がどの字も特別に扱わないことに頼るので、挙げる字が「\」と「|」と「`」だけで済む。読むときも、コードの形の終わりを囲む「`」の数で見分けられる
- **Trade-offs**: 題名が等幅の字で、背景の色付きで出る。数え方は、拡張書記素クラスタ(perl の `\X`)で、要件11の2の「全角の文字も半角の文字も、1字を1文字と数える」に合う

### Decision: 今ある行への題名の書き足し(#659)
- **Context**: 要件11の5。題名の列を足す変更が main に入ったときに一覧にある行には、題名が無い
- **Alternatives Considered**:
  1. github.pl が、行を足すたびに、題名の無い行の題名を読んで書き足す
  2. Claude が、変更が main に入ったあとに、会話の中で一度だけ書き足す
- **Selected Approach**: 2
- **Rationale**: 所有者が、2026-10-28 に、今ある行への書き足しを毎回動く仕組みに入れないと決めた(Issue #659 の本文の「決めた方式」)。書き足しは一度だけ行えば済む。1は、一度だけの作業のために、github.pl に毎回動く手順を足すことになる
- **Trade-offs**: 変更が main に入ってから Claude が書き足すまでのあいだ、今ある行の題名の欄は空である。変更を取り込んでいない会話が一覧に行を足すと、題名の列のある行が一覧から消える。所有者が作業を絞ったので、この設計は消えた行を戻す仕組みを作らない

### Decision: ページをバイトの数でも分ける(#659)
- **Context**: 要件7の4。題名の欄で1行の長さが大きく変わる
- **Selected Approach**: 1ページを300行までとし、ページの全文が UTF-8 で60,000バイトを超えるときは、超える行の前で分ける
- **Rationale**: 拡張書記素クラスタの20字は、結合文字で、題名の256文字のすべてを持てる。300行の上限だけでは、本文が65,536文字を超えることがある。GitHub が文字をどの単位で数えても、文字の数は UTF-8 のバイトの数を超えないので、バイトで分ければ数え方に頼らない

### 設計を固める前の3つの見方の結果
- 一般化: 本体・補助役・別のセッションの会話を、どれも「会話」として同じ形で抜き出し、役割だけを欄で分ける。段階の印も、コマンドとスキルを同じ表で段階に対応させる
- 既にあるものを使う: 記録の置き場は `kp_state_dir` と同じ git の共通ディレクトリ、錠は `_kp_lock` と同じ作り(mkdir)、台帳の Issue は `lib-ledger-issue.sh` の探し方の決まり、確認役の判定は既存の `VERDICT` の行、審査の往復は依頼文の既存の欄
- 減らす: `PermissionRequest` のフックは足さない(`PostToolUse` の `duration_ms` で足りる)。`session.sh` は変えない。kiro-impl は変えない

### #659 の設計を固める前の3つの見方の結果(#659)
- 一般化: 題名の欄の読み書きは、今の一覧の行の読み書き(`parse_row` と `write_list`)に欄を1つ足すだけで、新しい置き場を作らない
- 既にあるものを使う: 題名の全文は、GitHub の Issue のカードを使い、一覧に書かない。題名は、`gh api repos/{owner}/{repo}/issues/<N>` で読み、テストの偽の gh が既に返す `title` を使う
- 減らす: 題名が変わったときの書き直しをしない(要件11の4)。今ある行への題名の書き足しと、消えた行を戻すことを、仕組みに入れない(要件11の5)。変わるのは github.pl と、test-github.sh と test-usage.sh だけである

## Risks & Mitigations
- Claude Code の会話の記録の形が変わる — 抜き出しの部品は、知らない形の行を飛ばし、飛ばした数を記録する。集計は、読めない会話があれば注記する(要件2の8)。直すのは抜き出しの部品とそのテストだけで済む
- 一覧の Issue の本文を2つの会話がほぼ同時に書き換え、片方の行が消える — 書いたあと10秒待って読み直し、無ければ足し直す。漏れは次の会話の始めに確かめ直す
- 価格が変わる — データのファイルに確かめた日を持たせ、集計に価格の出どころと確かめた日を書く。価格の変わり目は所有者がデータのファイルを直す
- `PostToolUse` のフックが道具を使うたびに動く — 裏で(async で)動かす。抜き出しの部品は、この時点では入力を JSON として解かず、正規表現で3つの欄を取り出して1行を追記するだけにする。perl が道具ごとに1回起きるのは、Claude Code の形を知る部品を1つにするための代償として受け入れる
- 抜き出しの手元の記録が消える(作業フォルダの本体を消したとき) — 手元の記録は git の共通ディレクトリにあり、worktree を消しても残る。本体を消したときは、残った会話の記録だけで集計し、注記する
- 題名の列を足す変更を取り込んでいない会話が一覧に行を足し、題名の列のある行が一覧から消える(#659) — 所有者が 2026-10-28 に Issue #659 の作業を絞ったので、この設計は戻す仕組みを作らない。消えた行の集計は、Issue の集計のコメントに残る
- GitHub が Issue のカードを出さなくなる、または表の中のコードの形の扱いを変える(#659) — 設計を見直すきっかけに書く。実装のときに、Markdown を HTML にする API で確かめ直す

## References
- [Claude Code のフック](https://code.claude.com/docs/en/hooks) — フックの入力の欄、`async`、`additionalContext`
- [Claude Code の設定](https://code.claude.com/docs/en/settings) — ターミナル、IDE、デスクトップアプリが同じ設定のファイルを読むこと
- [Claude Code のデスクトップアプリ](https://code.claude.com/docs/en/desktop) — セッションを別に起こす機能がデスクトップアプリのものであること
- [.claude ディレクトリ](https://code.claude.com/docs/en/claude-directory) — 会話の記録の置き場所と、Windows の `~/.claude` の場所
- [Claude の価格](https://platform.claude.com/docs/en/about-claude/pricing) — モデルごとの価格と条件
- `.github/scripts/lib-ledger-issue.sh` — 台帳の Issue の探し方の前例
- [Making it easier to grow communities on GitHub](https://github.blog/news-insights/the-library/making-it-easier-to-grow-communities-on-github/) — マージのあとにコメントの contributor の印が付くことと、`authorAssociation` が同じ情報であること
- [huggingface/relore #74](https://github.com/huggingface/relore/issues/74) — 組織を離れたメンテナの前のコメントが、今は `CONTRIBUTOR` を返すという報告
- `.claude/scripts/parallel/lib.sh` — 記録の置き場所と錠の前例
