## サイクル1 往復1(2026-10-12)

承認済みの requirements.md(要件1〜7)の受入基準と design.md(サイクル4で承認)を tasks.md と突き合わせた。要件カバレッジは、要件1の1〜7、要件2の1・2、要件3の1〜6、要件4の1〜9、要件5の1・2、要件6の1〜4、要件7の1〜3のすべてが、少なくとも1つのタスクの `_要件:_` に現れる。requirements に無い番号を参照しているタスクは無い。design の8つの部品(keirekipro-readonly-guard、keirekipro-ops、ops-shell.ps1、refresh-token.sh、refresh-github-app-token.sh、CLAUDE.md の決まり、所有者の GitHub の鍵、手順書と PR の本文)は、それぞれタスク1.1、1.2、2、3.1、3.2、4、5.2、5.1〜5.4・6で扱われている。design の「ファイルの構成」に載る14のファイルは、すべてどれかのタスクの範囲に入り、タスクが載っていないファイルを変える指示は無い(`.claude/scripts/parallel/run-check.sh`、`compose.yaml`、`docker/` を変えないことをタスク6が確かめる)。design の単体テスト(`test-refresh-token.sh` の5つの場合)はタスク3.1の「受入基準とテストの対応」にそのまま現れ、フックのテスト(D4-1-2)はタスク3.2に起こされている。結合テストは、タスク6が design の項目をすべて含めたうえで A〜G の見出しに分け、D4-1-1(変更用ロールの権限の確かめは普段の鍵から `--policy-source-arn` で行う)、D2-1-2(起動の確かめは `auto-merge.yaml`)、D3-1-2(所有者の PAT の承認が拒まれる)、D2-1-4(`BOT_GITHUB_TOKEN` は GitHub の画面で置き換える)の低の指摘の扱いは、タスク5.2とタスク6に反映されている。

スコープを確かめた。requirements の「この spec で決めないこと」と design の「作らないもの」(本番を変えるワークフローの中身、`BOT_GITHUB_TOKEN` のワークフロー4本、OIDC のロール、`.claude/settings.json` の禁止の一覧、Windows の別ユーザーなど)に当たる作業をするタスクは無い。タスク3.2は `settings.json` にフックの登録を足すだけで、禁止の一覧には触れない。Issue #489 の「やりたいこと」に対する取りこぼしと、Issue に無い勝手な追加は無い。

完了条件の4項目は雛形(`.kiro/settings/templates/specs/tasks.md`)のとおりに書かれている。この spec が変えるファイルに frontend・backend・terraform は無いので、項目2(verify のスキル)は変えた領域が無いことで満たされ、置き換えは無い。`.claude/hooks/check-verify-before-stop.sh` は frontend・backend・terraform の下の変更だけを見るので、実装の停止を止めることも無い。並行と依存を確かめた。`(並行可)` のタスクは互いに別のファイルを対象にしており、5.1(`参加者セットアップ手順.md`)、5.2(`基盤構築手順.md`)、5.4(`障害時の本番操作手順.md`)は衝突しない。5.1 の `_依存: 2, 3.1_`、5.3 の `_依存: 1.1, 1.2_`、5.4 の `_依存: 2_` は、それぞれ参照するファイル名と手順の中身が先に決まる必要と合う。`kiro-impl` は `(並行可)` でも番号の順に1つずつ進める(`.claude/skills/kiro-impl/SKILL.md` 159行目)ので、5.3 が 5.1・5.2 の節を指すことも順序の問題にならない。

設計の前提をリポジトリの実ファイルで確かめた。(1) `.claude/settings.json` の deny は `.claude/hooks/**` と `.claude/settings.json` と `.github/**` の Edit と Write を止めており、タスク3.2が scratchpad に用意して所有者が置く形と、「実装のメモ」の1つ目は、この deny と合う。(2) `guardrails.yaml` 52〜53行目の shellcheck は `git ls-files -z '*.sh'` をまとめて渡す形で、タスク3.1・3.2の「追跡しているすべての `*.sh` をまとめて渡す」と同じ形である。(3) `参加者セットアップ手順.md` の 2-2(67〜177行目)は、`gh auth login` でボットの classic PAT を `.gh-bot` に入れる本文(69〜107行目)と、確かめ1〜4(132〜170行目)から成る。`基盤構築手順.md` の 1(8〜10行目、26〜27行目)と 3-1(71行目)は、ボットの PAT を参加者セットアップで使うことと、Claude の gh の鍵が `BOT_GITHUB_TOKEN` と同じ PAT であることを書いている。(4) `手動作業手順.md` 1.2(46〜65行目)は、`SignInLocalDevelopmentAccess` が「`AdministratorAccess` を持つなら不要」と書いており、design の「1.2 の節に普段のログインは読み取り専用であることを書き足す」の対象である。(5) `IAMロール・ポリシー設計.md` には IAM ユーザーと運用者のロールの章が無く、タスク5.3が足す形と合う。

却下された指摘は無い。

### 申告

**1. ポリシーの JSON と `ops-shell.ps1` には、動かして確かめるテストを作らない** — tasks.md 1.1・1.2・2 の完了の確かめ方

- Issue の記載: なし
- 決めたこと: 3つの JSON は `perl -MJSON::PP` で読めることと、Deny と Allow の中身を目で見ることで確かめる。`ops-shell.ps1` は構文の解析、ASCII、ファイルへの書き出しが無いこと、12桁の数字が無いことで確かめる。動かした結果は、マージのあとに所有者が PR の本文の確かめ方(A〜C)で1回だけ見る
- 他にありえた選択肢: JSON は、所有者が `aws login` しているあいだに、普段の鍵の `iam:SimulateCustomPolicy`(`ReadOnlyAccess` に含まれる)で、`aws iam simulate-custom-policy --policy-input-list file://<JSON>` を打ち、拒む操作と許す操作の判定をマージの前に確かめる。`ops-shell.ps1` は、6桁を受ける手前までを動かす試験用の入口(環境変数の消し方と PATH と設定ファイルの向け先だけを表示して終える)を持たせ、`powershell.exe -NoProfile` で流す
- 外れていた場合: JSON の誤り(操作名の綴り、対象の ARN の形)は、所有者が `AdministratorAccess` を外したあとに分かり、ルートユーザーで直すことになる。`ops-shell.ps1` の誤りは、所有者が障害のときに初めて気づくおそれがある。マージの前に Claude が確かめる手段があるのに使わない選択なので、所有者が判断する材料として挙げる

**2. 準備の全体の順番を `手動作業手順.md` に書く** — tasks.md 5.3

- Issue の記載: なし
- 決めたこと: AWS の権限を作る、ops-shell を置く、切り替えを確かめる、`AdministratorAccess` を外す、GitHub の準備、の順を `手動作業手順.md` に書き、`参加者セットアップ手順.md` と `基盤構築手順.md` の節を指す
- 他にありえた選択肢: リポジトリに1回だけ行う作業の手順書である `基盤構築手順.md`(「所有者が上から順に実施する」)に全体の順番を書き、AWS の手順を `手動作業手順.md` から指す
- 外れていた場合: 所有者が、GitHub の準備から始めて AWS の準備を飛ばしても、どの手順書も止めない。3つの手順書のつながりが切れていると、要件7の1の「迷わずに準備を終える」が崩れる。順番の置き場は所有者が開く順に合わせるのがよいので、挙げておく

### 指摘

| ID | レベル | 該当箇所 | 内容 | 直し方の案 |
|---|---|---|---|---|
| T1-1-1 | 中 | tasks.md 2 完了の確かめ方 | `ops-shell.ps1` の完了の確かめ方は、構文、ASCII、ファイルへの書き出しが無いこと、12桁の数字が無いことだけで、design の「ops-shell.ps1」の節の手順1〜9のうち、要件3の3(Claude は鍵を読めない。Claude が書ける設定を読まずに動く)を成り立たせる手順の中身(管理者でなければ終える、`AWS_` と `PYTHON` で始まる環境変数とプロキシの変数を消す、`PATH` を4つにする、`AWS_CONFIG_FILE` と `AWS_SHARED_CREDENTIALS_FILE` を `C:\Program Files\KeirekiPro\` に向ける、`aws.exe` を絶対のパスで呼ぶ、`Read-Host -AsSecureString`、`--duration-seconds 900`、`--serial-number`、`ops-renew`)が、1つも確かめの対象になっていない。`aws-config` の中身(`login_session` と `region`)も確かめていない。タスク1.1・1.2が Deny と Allow の中身を1つずつ確かめるのに対して、タスク2だけが中身を見ない。PR の本文の確かめ方「B. 切り替え」は切り替えが通ることしか見ないので、たとえば環境変数を消す手順が抜けても、マージの前にもあとにも機械では見つからない。design が手順を具体に書いているので実装役とレビュー役が気づく見込みはあるが、タスクの確かめ方として穴がある | 完了の確かめ方に、スクリプトが次の文字列を含むことを足す: `AWS_CONFIG_FILE`、`AWS_SHARED_CREDENTIALS_FILE`、`C:\Program Files\KeirekiPro`、`C:\Program Files\Amazon\AWSCLIV2\aws.exe`、`Read-Host -AsSecureString`、`--duration-seconds 900`、`--serial-number`、`ops-renew`、管理者の判定(`WindowsBuiltInRole` の `Administrator`)。`aws-config` が `login_session = arn:aws:iam::<ACCOUNT_ID>:user/keirekipro` と `region = ap-northeast-1` を持つことを足す。環境変数を消す手順と `PATH` を4つにする手順は、design の手順2・3の名前の一覧がスクリプトに揃っていることを目で見ると書く |
| T1-1-2 | 中 | tasks.md 5.3 説明と完了の確かめ方 | タスク5.3は「変更用ロールと制限のポリシーを作り、切り替えを確かめてから `AdministratorAccess` を外す手順」と書き、中身は design の「手順書と PR の本文」の節を指す。しかしその節は「手順を足す」としか書いておらず、所有者が付ける権限の中身は部品の節にある(「keirekipro-readonly-guard」: `keirekipro` の権限を `ReadOnlyAccess`・`SignInLocalDevelopmentAccess`・このポリシーの3つだけにする。「keirekipro-ops」: ロールの権限を `PowerUserAccess` と `keirekipro-ops-guard` の2つにし、最大のセッションの長さを3600秒にし、`iam:PassRole` を与えない)。完了の確かめ方は `<ACCOUNT_ID>` の置き換え、順序、節のつながり、章の書き足し、設計書の項目しか見ないので、手順書が `ReadOnlyAccess` と `SignInLocalDevelopmentAccess` を付ける手順を落としても通る。落とすと、所有者が `AdministratorAccess` を外した時点で普段の鍵は何も読めず `aws login` もできなくなり(要件2の1)、ルートユーザーで戻すことになる。「移行」の節の「切り替えを確かめてから外す」は切り替えしか確かめないので、この落ちは防げない。あわせて、design が 1.2 の節に書き足すとした「普段のログインは読み取り専用である」ことも、5.3 の確かめの対象に無い | 完了の確かめ方に次を足す: 手順が、`keirekipro` に `ReadOnlyAccess`・`SignInLocalDevelopmentAccess`・`keirekipro-readonly-guard` の3つを付けたうえで `AdministratorAccess` を外す形であること。変更用ロールに `PowerUserAccess` と `keirekipro-ops-guard` の2つを付け、最大のセッションの長さを3600秒にし、`iam:PassRole` を付けないこと。「1.2 AWS CLIの認証設定」の節に、普段のログインは読み取り専用であることと、`SignInLocalDevelopmentAccess` が要ること(「`AdministratorAccess` を持つなら不要」の文を直す)が書かれていること。説明の文に「中身は design.md の「keirekipro-readonly-guard」と「keirekipro-ops」の節の権限のとおり」と足す |
| T1-1-3 | 中 | tasks.md 5.1 説明(「2-2 の節の確かめ方を置き換える」)、5.2 説明 | 直す範囲が確かめ方に限られていて、Claude の gh がボットの classic PAT でログインする本文が残る。`参加者セットアップ手順.md` 2-2 の 69〜107行目は、`.gh-bot` に `gh auth login` でボットの PAT を入れる手順と「PATはOSの資格情報ストアに入り、設定ファイルには残らない」の文であり、`基盤構築手順.md` の 8〜10行目と26〜27行目は「手順1で発行するbotのPATを参加者セットアップで使う」、71行目は「bot専用のgh設定ディレクトリのトークンも同じPATのため、エージェントのgh操作が全て止まる」と書く。design の移行の節は、ボットの classic PAT を Claude の手元から消すことを前提にしている(「Claude の手元から消したあとも…`BOT_GITHUB_TOKEN` に残る」)。タスク5.1が確かめ方だけを置き換えると、所有者が手順書のとおりに準備したときに、作り直したボットの PAT(scope `workflow`。起動・再実行・取り消しができる)を `.gh-bot` に入れたうえで `refresh-token.sh` も動かす形になり、要件4の1・4の4が手元の鍵で崩れる。PR の本文の確かめ方「D」は gh が使う鍵がどちらかによって通ったり通らなかったりするので、落ちを必ず見つけるとは言えない。完了の確かめ方も、2-2 に `gh auth login` の手順が残っていないことを見ていない | タスク5.1の説明を「2-2 の節を、ボットの PAT でログインする手順ごと、`github-app.env` と秘密鍵を置く手順と確かめ方に置き換える」とし、完了の確かめ方に「`参加者セットアップ手順.md` に、Claude の gh(`.gh-bot`)へ `gh auth login` でボットの PAT を入れる手順が残っていないこと」を足す。タスク5.2に、`基盤構築手順.md` の 1 と 3-1 の、ボットの PAT を参加者セットアップと Claude の gh で使う記述を、`BOT_GITHUB_TOKEN` にだけ使う記述に直すことを足す |
| T1-1-4 | 低 | tasks.md 3.2 完了の確かめ方(「`github-app.env` が無いときに3つのイベントのどれでも終了コード0で何も書き換えないこと」)、受入基準とテストの対応(「設定が無ければ何もしない」) | この場合は `refresh-token.sh` の振る舞い(design「呼び出し方」: `github-app.env` が無ければ何もせず0で終える)であり、タスク3.2のテストは `refresh-token.sh` を偽物に置き換えて流すので、偽物がこの判定を持たない限り確かめにならない。フックの確かめとしては、D4-1-2 が示したとおり「偽物が0で終われば、フックは0で終わり何も出さない」が対応する場合である。実装役が偽物に `github-app.env` の判定を書き足せば通るが、フックの何を確かめたのか読み手に伝わらない | 1つ目の場合を「偽の `refresh-token.sh` が0で終われば、3つのイベントのどれでも、フックは終了コード0で終わり、標準出力に何も出さない」に直し、テスト名を「入れ替えに成功したら何も出さない」のように直す。`github-app.env` が無い場合は、タスク3.1のテストがすでに持っている |
| T1-1-5 | 低 | tasks.md 3.1 説明と完了の確かめ方 | 2点。(1) design-response の D2-1-3 は「`hosts.yml` の `user` の値は、tasks の実装で公式文書を確かめて決める」としたが、タスク3.1は design の呼び出し方(`user: <App の名前>[bot]`)のとおりに書くとだけ書き、確かめることを引き継いでいない。インストールトークンを git の HTTPS で使うときの GitHub の文書のユーザー名は `x-access-token` で、ほかの名前で push が通るかは確かめられていない。通らないと、所有者の準備のあとの「D」で Claude の push が初めて失敗する。(2) 「追跡しているすべての `*.sh`」は `git ls-files` の結果なので、新しく作った `refresh-token.sh` と `test-refresh-token.sh` を `git add` する前に流すと、新しいファイルが検査に入らずに0件になる | (1) 説明に「`hosts.yml` の `user` は、GitHub の文書(インストールトークンを git で使うときのユーザー名)を確かめて決め、確かめた文書を PR の本文に書く」と足す。または design の値を `x-access-token` にすることを所有者に示す。(2) 完了の確かめ方に「新しいファイルを `git add` したうえで」と足す |
| T1-1-6 | 低 | tasks.md 6(下書きの見出し「F. ワークフローのファイルを変えた PR」。design の結合テストの項目「Claude が、ワークフローのファイルのコメントだけを変えたブランチを push して PR を作れる」) | `.claude/settings.json` の deny は `.github/**` の Edit と Write を止めており、所有者は Claude が別の経路(Bash の `sed` など)で `.github/` に書くことも認めていない。今、Claude がワークフローを変えた PR を作るときは、Claude が scratchpad に用意し、所有者がコマンドで置き、Claude がコミットして push する形である。「F」の項目を design の文のまま下書きに写すと、確かめのときに Claude が `.github/` を自分で書くか、所有者が置くのかが決まっておらず、所有者が置く手順(scratchpad のファイルの `cp`)が確かめ方に無い。要件6の2の「今と同じく」は、所有者が置いて Claude が push する今の形を指す | タスク6の「追加の項目」に、F は「Claude が scratchpad にコメントだけを変えたワークフローのファイルを用意し、所有者が置き、Claude がコミットして push し PR を作る。確かめたあと、Claude は PR を閉じてブランチを消す」の形で書くことを足す |

### 前の段階への指摘

この往復では無い。

- 往復: 1回目 / 高0 中3 低3

## サイクル1 往復2(2026-10-12)

往復1の修正3件を tasks.md の本文で確かめた。T1-1-1: タスク2の完了の確かめ方に、design の「ops-shell.ps1」の節の9つの手順(管理者の判定、環境変数の消去、`PATH` を4つにする、`AWS_CONFIG_FILE` と `AWS_SHARED_CREDENTIALS_FILE` の向け先、作業の場所、`Read-Host -AsSecureString`、`aws.exe` の絶対のパスと `--duration-seconds 900`、鍵を環境変数に置く、`ops-renew`)をすべて持つことと、`aws-config` の `source` が `login_session` と `region = ap-northeast-1` だけを持つことが足されており、design の手順1〜9と1つずつ対応する。T1-1-2: タスク5.3の完了の確かめ方に、`keirekipro` に `ReadOnlyAccess`・`SignInLocalDevelopmentAccess`・`keirekipro-readonly-guard` を付けてから `AdministratorAccess` を外す順、`keirekipro-ops` に `PowerUserAccess` と `keirekipro-ops-guard` を付けて最大のセッションの長さを3600秒にすること、「1.2 AWS CLIの認証設定」の節への書き足しが入った。`iam:PassRole` を与えないことは確かめの文に無いが、ロールの権限を `PowerUserAccess` と `keirekipro-ops-guard` の2つだけにすれば `iam:PassRole` は入らない(`PowerUserAccess` は `iam:*` を `NotAction` で除いており、`iam:PassRole` を含まない)ので、別に確かめる必要は無い。T1-1-3: タスク5.1の説明が「2-2. PR作成名義の固定(bot専用のgh設定ディレクトリ)」の節の本文ごと置き換える形になり、完了の確かめ方に `.gh-bot` へボットの classic PAT を入れる手順が残っていないことが入った。タスク5.2の説明に「1」と「3-1」の記述の直しと、完了の確かめ方に `基盤構築手順.md` にボットの PAT を Claude の手元に入れる記述が残っていないことが入った。あわせて直した T1-1-4(偽物の `refresh-token.sh` が成功したときに終了コード0で終える)と T1-1-5(`git add` のあとに shellcheck、`hosts.yml` の `user` を公式文書で確かめて根拠の URL をテストの注記に書く)も本文に反映されている。

タスクが指す手順書の節の名前を実ファイルで確かめた。`参加者セットアップ手順.md` の「2-2. PR作成名義の固定(bot専用のgh設定ディレクトリ)」(67行目)、`基盤構築手順.md` の「1. botアカウントの作成とPATの発行」(12行目)、「3-1. Actions secrets」(64行目)、「botのPATが期限切れになったときの復旧」(296行目)、`手動作業手順.md` の「1.2 AWS CLIの認証設定」(46行目)、「3. Terraformバックエンド用リソース作成」(198行目)、「4. GitHub Actions用OIDC設定」(288行目)は、すべて今の本文にある。Claude の gh の身元が `DogisRiki-bot` から GitHub App の `<App の名前>[bot]` に替わることについて、`.github/` のワークフローとスクリプトが PR の作成者の名前を `DogisRiki-bot` と照合している箇所が無いか調べた。作成者の照合は `dependabot[bot]`(`auto-merge.yaml` 92行目、`codex-review.yml` 44行目、`dependabot-auto-merge.yaml` 65行目、`dependency-review.yaml` 156行目、`reserve-auto-merge.sh` 320行目)と、承認者が所有者であること(`pre-merge-check.yaml` 59行目、`guardrails.yaml` 90行目、`dependency-gate.yaml` 53行目、`rerun-approval-gated-checks.yaml` 29行目)だけで、`DogisRiki-bot` を名指しするのはテストの固定の値(`test-reserve-auto-merge.sh`)だけである。身元の替わりで仕組みのワークフローが止まる箇所は無く、要件6の4の前提は成り立つ。別の Issue に回す道の受け先 #557 は開いている。

要件カバレッジ、design カバレッジ、スコープ、完了条件の4項目、並行と依存は往復1から変わっておらず、往復1の確かめの結果のままである。往復1の申告1・2は、タスクの内容が変わっていないのでそのまま残る。新しい申告は無い。

却下された指摘は無い。

### 申告

往復1の申告1・2のまま。新しく申告するものは無い。

### 指摘

| ID | レベル | 該当箇所 | 内容 | 直し方の案 |
|---|---|---|---|---|
| T1-2-1 | 低 | tasks.md 5.1 完了の確かめ方、5.3 完了の確かめ方 | 置き換えの対象の外に、ボットの PAT と `AdministratorAccess` を前提にした説明の文が残る。`参加者セットアップ手順.md` の 2-3(179〜209行目)の確かめ1「Claude Codeのセッションでpushし、成功すること(botのPATが使われる)」(200行目)と、195〜196行目の「グローバル設定のヘルパー(Git Credential Manager等)を打ち消すためのもの」は、Claude の push が App のトークンになり、所有者の全体の資格情報ヘルパーが `gh auth git-credential` になったあとは、理由の説明が今の作りと合わなくなる。`手動作業手順.md` 1.2 の64行目「`SignInLocalDevelopmentAccess` ポリシーが必要(`AdministratorAccess` を持つなら不要)」は、5.3 で `keirekipro` から `AdministratorAccess` を外すので、括弧の中が所有者に当てはまらなくなる。タスク5.1の確かめは「PAT を入れる手順が残っていないこと」、5.3 の確かめは「読み取り専用であることが書き足されていること」なので、どちらも説明の文の残りは見ない。手順そのものは正しく動くので、実装には影響しない | タスク5.1の説明に「2-3 の確かめ1の括弧を App のトークンに直す」を、タスク5.3の完了の確かめ方に「1.2 の『`AdministratorAccess` を持つなら不要』の括弧を消すか、`keirekipro` には要ると書き直す」を足す |
| T1-2-2 | 低 | tasks.md 3.2 完了の確かめ方(「登録を足した `settings.json` の下書きが `perl -MJSON::PP` で読み込めること」) | design の「refresh-github-app-token.sh」の節は「打ち切りの時間は30秒にする」と決めているが、タスク3.2の確かめは下書きが JSON として読めることだけで、3つのイベントの登録に `timeout` が30で付いていることと、PreToolUse の matcher が `Bash` であることを見ない。抜けても Claude Code の既定の打ち切りで動くので、実装には影響しないが、所有者が置く下書きの確かめとしては design の決めを1つ落としている | 完了の確かめ方に「下書きの3つの登録が、`refresh-github-app-token.sh` を指し、`timeout` が30であり、PreToolUse の matcher が `Bash` であること」を足す |
| T1-2-3 | 低 | tasks.md 5.4 説明と完了の確かめ方 | design の「失敗したときの扱い」の4つ目(`ops-shell` で切り替えたあとに `AccessDenied` になったら、その操作は `PowerUserAccess` に無い操作なので、terraform apply のワークフローかルートユーザーで行う)と、要件3の6の後半(所有者が IAM を変えるときは terraform apply のワークフローかルートユーザーで行う)は、所有者が障害のときに読む文であるが、design の「手順書と PR の本文」の節は `障害時の本番操作手順.md` の中身を「`ops-shell` で変える手順、スイッチロールの手順、切り替えられないときの手順」の3つとしか書いておらず、タスク5.4もこの3つと `ops-renew` の4つの見出しだけを確かめる。所有者が障害のときに IAM の変更で `AccessDenied` を受けたとき、開いている手順書に次の手が無い。手順書の文の抜けであり、実装には影響しない | タスク5.4の説明に「変更用ロールで `AccessDenied` になる操作(IAM の変更など)は terraform apply のワークフローかルートユーザーで行うことを書く」を足し、完了の確かめ方の見出しの確かめに加える |

### 前の段階への指摘

この往復では無い。

- 往復: 2回で収束 / 未解決: 0件
