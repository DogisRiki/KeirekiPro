# 調べた結果と設計の判断

## まとめ

- 機能: `claude-memory-weekly-inspection`
- 調べ方: 新しい機能として、外部の仕様を全部調べた。既存の仕組みは、集計の仕組み(`.claude/scripts/usage/`)と、`.claude/settings.json` のフックの登録のしかたを読んだ
- 設計を決めた3つの事実:
  - Claude Code の auto memory は、git のリポジトリごとに1つの場所(`~/.claude/projects/<作業フォルダの場所を符号にした名前>/memory/`)にあり、worktree のどれからも同じ場所を使う。会話の記録は、worktree ごとに別の場所にある
  - 週に1回動かす仕組みのうち、開発者の PC のファイルを読めて、Windows・macOS・Linux のどれでも使えるのは、OS の予定の仕組み(Windows のタスク スケジューラ、macOS の launchd、Linux の cron)だけである。macOS の launchd は、スリープの間に逃した回を起きたときに1回動かすので、点検の側で時刻を確かめて飛ばす
  - `claude -p` は、使う道具を引数で限れる(`--allowedTools`、`--disallowedTools`、`--permission-mode dontAsk`)。結果を JSON Schema に合う形で返させられる(`--json-schema`)。auto memory を切れる(`CLAUDE_CODE_DISABLE_AUTO_MEMORY=1`)。会話の記録を残さないようにできる(`--no-session-persistence`)

## 調べたこと

### auto memory の場所と読み込みの上限

- 調べたきっかけ: 点検のスクリプトが、どのメモリを読むかを決めるため
- 調べた先: https://code.claude.com/docs/en/memory 、https://code.claude.com/docs/en/sessions#where-transcripts-are-stored 、https://code.claude.com/docs/en/errors
- 分かったこと:
  - メモリは `~/.claude/projects/<project>/memory/` にあり、`MEMORY.md` と、メモリファイルから成る。`<project>` は git のリポジトリから決まり、worktree と下のフォルダのどれからも同じ場所を使う
  - 場所の名前は、作業フォルダの場所の英数字でない文字を `-` に替えたものである。200文字を超える名前は切り詰められ、ハッシュが付く
  - この PC では、worktree の会話のメモリは、本体の作業フォルダの名前の `C--Users-dogis-Desktop-DockerWorkSpace-develop-KeirekiPro/memory` にあった。会話の記録は、worktree ごとの名前(`…KeirekiPro--claude-worktrees-issue-522-a1eaad`)の下にあった
  - 会話の始めには、`MEMORY.md` の先頭の200行か25KBのうち少ないほうまでが読み込まれる。frontmatter と HTML の注記は数えない(2.1.211 から)
  - 設定 `autoMemoryDirectory` で場所を替えられる。設定 `autoMemoryEnabled: false` か環境変数 `CLAUDE_CODE_DISABLE_AUTO_MEMORY=1` で切れる。`CLAUDE_CONFIG_DIR` で `~/.claude` の場所が替わる
  - 公式の文書は、Claude がメモリを書くときに Write と Edit の道具を使うとは書いていない
- 設計への影響: スクリプトは、本体の作業フォルダ(git の共通ディレクトリの親)の場所からメモリの場所を求める。目次の行と大きさは、frontmatter と HTML の注記を除いて数える。Write と Edit の道具の呼び出しから会話の中の書き換えを見分けるやり方は、公式の文書に無いので、見分けられなかったときに害の無い向き(点検する側)に倒す

### `claude -p` で道具を限って動かす

- 調べた先: https://code.claude.com/docs/en/cli-reference 、https://code.claude.com/docs/en/headless 、https://code.claude.com/docs/en/permissions#what-runs-before-you-trust-a-folder 、https://code.claude.com/docs/en/agent-sdk/typescript 、手元の `claude --help`(2.1.302)
- 分かったこと:
  - `--permission-mode dontAsk` は、許していない道具の呼び出しを尋ねずに断る。`--permission-prompts none`(2.1.259 から)も、尋ねるはずの呼び出しを断る
  - `--disallowedTools` に道具の名前だけを書くと、その道具が無くなる。断る決まりは許す決まりより強い
  - 信頼していないフォルダの `-p` では、プロジェクトの `permissions.allow` は使われないが、プロジェクトのフックは動く。`--settings '{"disableAllHooks": true}'` で、その1回のフックを止められる。`--setting-sources user` で、プロジェクトの設定を読まない
  - `--bare` は、フックと auto memory と CLAUDE.md を読まないが、ログインの資格情報を読まず `ANTHROPIC_API_KEY` を要る。開発者の多くは契約のログインで使うので、`--bare` は使えない
  - `--max-turns` は、上限に達するとエラーで終わる。`--json-schema` は、結果を JSON Schema に合う形で返させる
  - `--output-format json` の結果は、`subtype`(`success`、`error_max_turns`、`error_during_execution`、`error_max_structured_output_retries` など)、`is_error`、`terminal_reason`、`api_error_status` の欄を持つ。使う量の上限やネットワークの失敗に決まった終了コードは無い
  - `--no-session-persistence` は、会話の記録を残さない
- 設計への影響: 点検の中の Claude には道具を1つも渡さない。事実の調べとメモリの書き換えは、点検の中の Claude ではなくスクリプトが行う。理由は、設計の判断の節の「メモリを書き換えるのはスクリプトで、点検の中の Claude には道具を渡さない」に書く。失敗の理由は、終了コードではなく結果の欄で見分ける

### 週に1回動かす仕組み

- 調べた先: https://learn.microsoft.com/en-us/windows/win32/taskschd/tasksettings-startwhenavailable 、https://learn.microsoft.com/en-us/windows/win32/taskschd/tasksettings-disallowstartifonbatteries 、https://learn.microsoft.com/en-us/powershell/module/scheduledtasks/new-scheduledtasksettingsset 、https://learn.microsoft.com/en-us/windows-server/administration/windows-commands/schtasks-create 、https://learn.microsoft.com/en-us/windows/win32/taskschd/principal-logontype 、https://keith.github.io/xcode-man-pages/launchd.plist.5.html 、https://developer.apple.com/library/archive/documentation/MacOSX/Conceptual/BPSystemStartup/Chapters/ScheduledJobs.html 、https://keith.github.io/xcode-man-pages/launchctl.1.html 、https://man7.org/linux/man-pages/man8/cron.8.html 、https://www.freedesktop.org/software/systemd/man/latest/systemd.timer.html 、https://code.claude.com/docs/en/desktop-scheduled-tasks 、https://code.claude.com/docs/en/routines 、https://code.claude.com/docs/en/scheduled-tasks
- 分かったこと:
  - Windows のタスク スケジューラ: `StartWhenAvailable` の初期値は偽で、逃した回を遅れて動かさない。`DisallowStartIfOnBatteries` の初期値は真で、電池で動くノート PC では動かない。`schtasks` には電池の設定の引数が無く、PowerShell の `New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries` で設定する。ログオフ中に動かすにはパスワードを保存する必要があり、S4U はネットワークに出られない
  - macOS の launchd: `StartCalendarInterval` の回をスリープの間に逃すと、起きたときに1回だけ動かす。電源が切れていた回は動かさない。読み込みは `launchctl bootstrap gui/<uid>`、外すのは `launchctl bootout`
  - Linux の cron: PC が止まっていた回を動かさない。systemd のタイマーの `Persistent=` の初期値は偽で、こちらも動かさないが、ログオフ中に動かすには `loginctl enable-linger` が要る
  - Claude Desktop の予定のタスク: アプリを開いていて PC が起きている間だけ動き、起きたときに、7日以内に逃した直近の回を1回動かす。Linux で使えるかは確かめられなかった
  - クラウドで動かす予定: 新しく取ったリポジトリの写しで動き、手元の `~/.claude` を読めない
  - `/loop` と CronCreate: 会話が開いている間だけ動き、7日で切れる
- 設計への影響: OS の予定の仕組みを使う。Windows は PowerShell の `Register-ScheduledTask` で、電池でも動く設定にし、`StartWhenAvailable` を付けない。macOS の起きたときの1回を飛ばすため、点検のスクリプトは、決まった時刻から60分を過ぎていたら何もせずに終わる

### 会話の記録の形

- 調べた先: https://code.claude.com/docs/en/sessions 、https://code.claude.com/docs/en/claude-directory 、https://code.claude.com/docs/en/settings-reference 、手元の会話の記録
- 分かったこと:
  - 会話の記録は `~/.claude/projects/<project>/<会話の ID>.jsonl` にあり、補助役の記録は `<会話の ID>/subagents/` にある。初期値では30日で消える(`cleanupPeriodDays`)
  - 公式の文書は、記録の形を Claude Code の中のものとし、版ごとに変わると書いている
  - 手元の記録では、道具の結果は `type` が `user` で中身が `tool_result` の行であり、開発者が打った文は `type` が `user` で中身が文字の列の行である。`isMeta` の行もある
  - この PC のメモリファイルの frontmatter には、Claude Code が付けた `originSessionId`(そのメモリを書いた会話の ID)がある
- 設計への影響: 外から混入した指示の出どころは、メモリファイルの `originSessionId` の会話の記録から、開発者が打った文だけを抜き出して確かめる。記録が無いか読めないときは、確かめられなかったとする

### 会話の始めに文を差し込む

- 調べた先: https://code.claude.com/docs/en/hooks
- 分かったこと: SessionStart のフックが 0 で終わったときの標準出力は、Claude の文脈に入る。上限は10,000文字である。matcher は `startup` `resume` `clear` `compact` `fork` である
- 設計への影響: 会話の始めのフックは、報告の中身ではなく、まだ示していない報告の番号だけを出す。報告の中身は、Claude が会話の中でコマンドで読む

## 構成の比べ方

| 案 | 中身 | 良いところ | 困るところ |
|---|---|---|---|
| OS の予定と `claude -p` | OS の予定がスクリプトを動かし、スクリプトが `claude -p` を呼ぶ | 3つの OS で動く。アプリを開いていなくても動く | OS ごとに登録のしかたが違う |
| Claude Desktop の予定のタスク | Desktop が決まった時刻に会話を動かす | 登録が簡単 | 起きたときに逃した回を動かす。アプリを開いていないと動かない。ターミナルだけの開発者は使えない |
| クラウドの予定 | Anthropic のクラウドで動かす | PC が止まっていても動く | 手元のメモリを読めない |
| 会話の始めに点検を動かす | 会話を始めたときに、前の点検から7日を過ぎていたら動かす | 予定の登録が要らない | 「所有者が何も打たなくても週に1回」にならない。決まった曜日と時刻にならない |

OS の予定と `claude -p` を選んだ。

## 設計の判断

### メモリを書き換えるのはスクリプトで、点検の中の Claude には道具を渡さない

- 背景: 点検の中の Claude が、メモリに混入した指示に従って、ほかのファイルを書き換えたり GitHub に書き込んだりするおそれがある。報告に載る直す前の文と直したあとの文が、実際の書き換えと食い違うおそれもある
- 分かった事実: このリポジトリの `.claude/settings.json` の `permissions.allow` には、`git commit *` `git push origin *` `gh issue create *` `gh pr create *` `gh issue comment *` の許可がある。プロジェクトの設定を読む `claude -p` では、これらの許可が点検の中の Claude にも効く。開発者の利用者の設定に何が許されているかは、開発者ごとに違い、スクリプトからは分からない
- 比べた案:
  1. 点検の中の Claude に Edit の道具を渡し、メモリを直接直させる
  2. 点検の中の Claude に、読む道具と、読むだけの `git` と `gh` のコマンドの許可を渡す。直し方を JSON で返させ、スクリプトが確かめてから書き換える
  3. 点検の中の Claude に道具を1つも渡さない。点検の中の Claude は、確かめたい事実を「調べてほしいこと」として JSON で返し、スクリプトが決まった読むだけのコマンドで調べて、次の呼び出しで結果を渡す。直し方も JSON で返させ、スクリプトが確かめてから書き換える
- 選んだ案: 3
- 理由: 案2では、許可の設定が点検の中の Claude に効くので、`git push` や `gh issue create` を止めきれない。`git log` の `--output` や `git grep` の `--open-files-in-pager` のように、読むだけに見えるコマンドにもファイルを書き出す引数やプログラムを動かす引数がある。案3では、点検の中の Claude が道具を持たないので、どの許可の設定も効かない。スクリプトは、引数を配列で渡し、決まった引数だけでコマンドを動かす。直す前の文と直したあとの文は、スクリプトが実際に書き換えた文なので、報告と食い違わない。1つのファイルの全体の書き換え、確かめられなかった汚染の直し、戻した直しのやり直しも、スクリプトが機械で断れる
- 引き換え: `claude -p` の呼び出しが、調べてほしいことの往復の分だけ増える。呼び出しは3回までに限る。直し方は、1つの文の置き換え、目次の末尾への1行の追加、1つのファイルの削除の3つに限られ、新しいメモリファイルは作れない。要件の直し方は、この3つで足りる
- 実装で確かめること: `--tools ""` で道具を1つも持たない `claude -p` になるか。`--json-schema` の結果を受ける欄の名前

### 前の点検の時点のメモリの中身を残さずに、書き換えと見落としを見つける

- 背景: 会話を通らない書き換えを見つけるには、前の点検の時点と比べる元が要る。前の点検のときからあった汚染かどうかを決めるにも、比べる元が要る。ただし、直す前のメモリの控えを作ってはいけない
- 選んだ案: スクリプトは、点検の終わりに、メモリファイルごとのハッシュと、空でない行ごとのハッシュだけを残す。ハッシュからはメモリの文を戻せないので、控えに当たらない
- 書き換えの見分け方: ハッシュが変わったメモリファイルについて、前の点検のあとの会話の記録に、そのファイルを指す Write か Edit の道具の呼び出しがあれば、会話の中の書き換えとする。無ければ、会話を通らない書き換えの疑いとする。疑いのファイルは点検するだけで、消しも戻しもしないので、見分けを誤っても、余分に点検するだけで害は無い

### 繰り返しの数え方と案の出し方

- 背景: 決まりの見直しの案は、Claude が汚染を見つけたあとでないと、出すかどうかが決まらない
- 選んだ案: スクリプトは、点検の前に、前の3回の記録から、種類ごとに「今回1つでも新しく見つかれば2回以上になる種類」と「すでに2回以上の種類」を求め、点検の中の Claude に渡す。Claude は、その種類の案を書く。スクリプトは、点検のあとに、今回の結果を足して数え直し、当たらない種類の案を報告から外す
- 新しく見つかった汚染: 種類とメモリファイルの名前と記述の文のハッシュが、前のどの記録にも無い汚染である

### 移す先の文書にまとめたあと、メモリの側を消す時点

- 背景: 置き場所の誤りの記述は、PR がマージされたあとにメモリから消す。マージを見届ける会話と、案を了承した会話は、別の会話になることがある
- 選んだ案: 新しい印を足さない。PR がマージされたあとの点検で、同じ記述がリポジトリの文書にもあるので、点検は、その記述を重複と二重記述の汚染として消す
- 理由: マージと結び付ける記録を足すと、記録の形と読み分けが増える(steering の `pipeline-design.md` の「一度きりの事情のために仕組みを足さない」)

## おそれと手当て

- Windows で、タスク スケジューラが `bash.exe` を動かすと、点検の間、黒い窓が出るおそれがある。窓を閉じると点検が途中で終わる。手当て: 予定の動かし方を `powershell.exe -NoProfile -WindowStyle Hidden` からにする。Windows Terminal が既定の端末のときにも窓が隠れるかは、実装のときに手で確かめる
- 会話の記録の形が Claude Code の版で変わると、書き換えの見分けと、開発者の発言の抜き出しが働かなくなる。手当て: 読めないときは、書き換えの疑いとして点検し、外から混入した指示は確かめられなかったとする。どちらも、消す向きに倒さない
- 点検に使うモデルは、開発者の既定のモデルになる。手当て: 引数でモデルを決めない。モデルの選びは開発者の設定に任せる
- 会話の記録は初期値で30日で消える。点検は週に1回なので、前の点検のあとの記録は残っている

## 参考

- https://code.claude.com/docs/en/memory — auto memory の場所、上限、切り方
- https://code.claude.com/docs/en/headless — `claude -p` の動き
- https://code.claude.com/docs/en/cli-reference — 引数の一覧
- https://code.claude.com/docs/en/hooks — SessionStart のフック
- https://learn.microsoft.com/en-us/powershell/module/scheduledtasks/new-scheduledtasksettingsset — Windows の予定の設定
- https://keith.github.io/xcode-man-pages/launchd.plist.5.html — launchd の予定
