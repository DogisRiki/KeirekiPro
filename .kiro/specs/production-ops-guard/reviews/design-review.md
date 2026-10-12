## サイクル1 往復1(2026-10-12)

承認済みの requirements.md(サイクル3)の要件1〜7の受入基準と design.md の「対応する要件」を突き合わせ、すべての受入基準がいずれかの部品(readonly-guard、keirekipro-ops、ops-shell.ps1、refresh-token.sh、フック、CLAUDE.md の決まり、所有者の PAT、手順書と PR の本文)で裏付けられていることを確かめた。Issue #489 の「やりたいこと」(インフラの変更と削除、本番デプロイのワークフローの起動を、コマンドの書き方によらず起動できないようにする)は、AWS 側(readonly-guard と keirekipro-ops)と GitHub 側(GitHub App と所有者の PAT)で対応しており、取りこぼしは無い。所有者が会話で決めたこと(Windows の別ユーザー・本番専用アカウント・CloudShell を採らない、GitHub App と fine-grained PAT、変更用の権限から IAM を外す)は設計に反映されている。

設計の前提をリポジトリの実ファイルで確かめた。(1) 本番を変えるワークフロー `release.yaml` `frontend-rollback.yaml` `terraform-apply.yaml` の入口は `workflow_dispatch` だけで、`backend-deploy.yaml` `frontend-deploy.yaml` は `workflow_call` だけである(設計の「入口を workflow_dispatch 以外に変えるとき」の前提と合う)。(2) `BOT_GITHUB_TOKEN` を使うワークフローは `auto-merge.yaml` `canary.yaml` `dependabot-auto-merge.yaml` `update-pr-branches.yaml` の4本で、設計の「作らないもの」の一覧と一致する。(3) 今のボットの鍵は classic PAT(scope `repo` `read:org` `workflow`、`doc/開発フロー/基盤構築手順.md` 1)、Claude の gh は `.claude/settings.local.json` の `GH_CONFIG_DIR`(`C:\Users\<user>\.gh-bot`)、git は `credential.https://github.com.helper` を空にしてから `!gh auth git-credential` を足す形(`doc/開発フロー/参加者セットアップ手順.md` 2-2・2-3)で、設計の「使う既存の仕組み」と合う。(4) `aws login` に `SignInLocalDevelopmentAccess` が要ること(`doc/インフラ設計/手順書/手動作業手順.md` 1.2)、ルールセットの Bypass list が空であること(基盤構築手順 2)を確かめた。(5) 既存のワークフローのうち PR の作成者を見るものは `dependabot[bot]` の除外だけで(`auto-merge.yaml` 92行目、`codex-review.yml` 44行目、`reserve-auto-merge.sh`)、PR の作成者が App のボットに変わっても `DogisRiki-bot` を名指しで判定している箇所は無い(要件6.4 は崩れない)。`.claude/settings.json` の7項目の記載と「ファイルの構成」の矛盾は無い(品質チェックの設定に `.claude/settings.json` と `.claude/hooks/` を足すことを書いている)。

### 申告

**1. 仕組みのワークフロー4本は、作り直したボットの classic PAT(`BOT_GITHUB_TOKEN`)をそのまま使う** — design.md 作らないもの、移行

- Issue の記載: なし。Issue は Claude の操作の止め方だけを求めている
- 決めたこと: `auto-merge.yaml` `canary.yaml` `dependabot-auto-merge.yaml` `update-pr-branches.yaml` は変えず、起動・再実行・取り消しの権限を持つ classic PAT をリポジトリの secrets に残す。Claude が前に読めた値を使えないよう、所有者が PAT を作り直す
- 他にありえた選択肢: この4本も GitHub App のインストールトークン(`actions/create-github-app-token` で、起動・承認の権限の無い App から発行)に替え、起動の権限を持つ鍵をリポジトリから無くす
- 外れていた場合: 指摘 D1-1-1 のとおり、Claude が同じリポジトリの PR のワークフローから secrets を読み出せるため、作り直した PAT も Claude の手に入り、移行の節の「作り直せば使えない」が成り立たない

**2. 変更用ロールの最大のセッションの長さを3600秒(既定)にした** — design.md keirekipro-ops「権限」

- Issue の記載: なし
- 決めたこと: CLI の切り替えは900秒だが、ロールの上限はマネジメントコンソールのスイッチロールのために3600秒のままにする
- 他にありえた選択肢: 上限を900秒に揃える(コンソールのスイッチロールも15分で切れる)
- 外れていた場合: `aws login` 直後の60秒のすき(要件1の7)で Claude の切り替えが通ったとき、Claude は `--duration-seconds 3600` を指定でき、最大1時間 AWS を変えられる。安全の節は「権限そのものは広がらない」とだけ書いており、所有者が受け入れたすきの大きさ(時間)はここで決まる

**3. 変更用ロールの権限を `PowerUserAccess` と `sts:AssumeRole` の Deny にし、`iam:PassRole` を与えない** — design.md keirekipro-ops「役割」

- Issue の記載: なし。要件3の6は「IAM の利用者・ロール・ポリシーを作る・変える・消す操作」を拒むと書く
- 決めたこと: `PowerUserAccess` は `iam:*` を含まないので、`iam:PassRole` も持たない。障害の対応で新しいタスク定義が要るときは terraform apply のワークフローで行う
- 他にありえた選択肢: 既にあるロール(ECS のタスクロールと実行ロール)に限って `iam:PassRole` を許す
- 外れていた場合: 障害のときに所有者が `ops-shell` から ECS のタスク定義を登録してタスクを動かす操作(`ecs register-task-definition` にロールを含めるもの)は `AccessDenied` になり、terraform apply のワークフロー(起動と承認で数分)に回る。要件3の前置きの「すばやく AWS を変える」のうち ECS に関わるものが CLI では通らない

**4. Claude の gh のトークンの入れ替えを Claude Code のフック(SessionStart、UserPromptSubmit、PreToolUse の Bash)で行う** — design.md refresh-github-app-token.sh

- Issue の記載: なし
- 決めたこと: 3つのフックで `refresh-token.sh` を呼び、期限まで600秒を切ったら発行する。フックは Claude の操作を止めない
- 他にありえた選択肢: Windows のタスクスケジューラで定期に入れ替える。または、`gh` の資格情報ヘルパーの形(呼ばれたときに発行する)にする
- 外れていた場合: フックが動かない経路(Bash 以外のツールで長く作業したあと、または Claude Code の外から `.gh-bot` を使う場面)でトークンが切れ、gh と push が 401 で止まる。また、`.claude/settings.json` と `.claude/hooks/` の変更は CODEOWNERS の承認を待つため、この PR は自動マージされない

**5. 普段のログインの鍵の Deny を、`kms:Decrypt`(すべて)、Secrets Manager の値の読み取り(すべて)、state バケットのオブジェクトに置き、ほかの S3 のオブジェクトは読めるままにした** — design.md keirekipro-readonly-guard「役割」

- Issue の記載: なし(サイクル1の R1-1-4 で、読める範囲の言い切りは設計に任せた)
- 決めたこと: 利用者のデータが入る S3 のオブジェクト、RDS のスナップショットなどは `ReadOnlyAccess` のまま読める。`kms:Decrypt` は対象を絞らず拒む
- 他にありえた選択肢: 利用者のデータのバケットも Deny に入れる。`kms:Decrypt` は秘密に使う鍵だけに絞る
- 外れていた場合: KMS で暗号化したものを読む操作(SSM の SecureString、SSE-KMS の S3 のオブジェクト、KMS 付きのログ)が普段のログインでは読めなくなり、障害の調査で `ops-shell` を開くことになる。逆に、利用者のデータは Claude も読める状態が残る

### 指摘

| ID | レベル | 該当箇所 | 内容 | 直し方の案 |
|---|---|---|---|---|
| D1-1-1 | 高 | design.md 全体の構成(「Claude が手にできる鍵は3つ」「本番を変える道は2つだけ残る」)、安全(想定する脅威、残るすき)、移行(「Claude が前に読めた値を使えないよう、所有者は PAT を作り直す」)、作らないもの(`BOT_GITHUB_TOKEN` のワークフロー4本) | Claude が GitHub Actions を通して本番のワークフローを起動する道が、設計のどこにも扱われていない。Claude は同じリポジトリにブランチを push し、ワークフローのファイルを変えた PR を作れる(要件6の1・2。App に Contents と Workflows の write を与える)。同じリポジトリのブランチからの `pull_request` の実行は PR 側のワークフローのファイルで動き、リポジトリの secrets を受け取る(`auto-merge.yaml` 84行目のコメント「fork のPRではシークレットを使えないため同一リポジトリのPRに限る」が、同一リポジトリの PR には渡ることを示している。`auto-merge.yaml` は base を checkout して自分の中身を守っているが、Claude が新しいワークフローのファイルを PR に足せばそのファイルがそのまま動く)。また、GITHUB_TOKEN の権限はワークフローの `permissions:` で `actions: write` に上げられ(リポジトリの設定は既定値を決めるだけで、書き込みができる人はワークフローのファイルで上げられる。GitHub の文書「Automatic token authentication」)、GITHUB_TOKEN が起こすイベントのうち `workflow_dispatch` と `repository_dispatch` は新しい実行を作る(GitHub の文書「Triggering a workflow」)。したがって、Claude が `permissions: actions: write` と `gh workflow run release.yaml --ref main` を書いたワークフローを PR に足せば、手元の鍵の権限によらず `release.yaml` の実行が作られ、所有者に承認の依頼が届く(要件4の1に反する。`release.yaml` の「Reject dispatch from non-main ref」は `--ref main` では止まらない)。同じ方法で `${{ secrets.BOT_GITHUB_TOKEN }}` を出力に書き出せば、scope `repo` `workflow` の classic PAT が Claude の手に入り、Claude の PC から起動・再実行・取り消しができる。移行の節の「作り直せば使えない」は成り立たず、安全の節が「想定する脅威」に挙げた「別のプログラム・手元の別の鍵」のうち、この道だけが塞がれていない。結合テストは手元の鍵でしか試さないので、承認後に誰も気づかないまま実装が終わる。範囲の「決めないこと」が除いているのは OIDC のロールの権限だけで、この道は除かれていない | 2つに分ける。(1) secrets の側は設計で塞げる: 4本のワークフローの `BOT_GITHUB_TOKEN` を GitHub App のインストールトークン(`actions/create-github-app-token` で、起動・承認の権限の無い App から発行。Dependabot の実行には Dependabot secrets に同じ秘密鍵を置く)に替え、起動の権限を持つ classic PAT をリポジトリの secrets から無くす。ワークフローの変更は `.github/` なので所有者が置き、「作らないもの」からこの4本を外す。(2) GITHUB_TOKEN による起動は、Claude が同じリポジトリでワークフローを動かせる限り設計では塞げない。安全の節の「残るすき」に「Claude が PR のワークフローから GITHUB_TOKEN で本番のワークフローの実行を作れる。production の環境の承認が止めるので本番は変わらないが、実行は作られ、承認の依頼が届く」と書き、全体の構成の「本番を変える道は2つだけ残る」を直す。所有者の判断は前の段階への指摘 D1-1-6 に書いた |
| D1-1-2 | 中 | design.md 所有者の GitHub の鍵(「資格情報マネージャーにある github.com の git の資格情報…を消す」)、要件4の7・4の8 | `doc/開発フロー/参加者セットアップ手順.md` 2-3 は、グローバルの資格情報ヘルパー(Git Credential Manager)をこのリポジトリの設定だけで打ち消している。Git Credential Manager は github.com 単位で OAuth の鍵(scope `repo` `gist` `workflow`。`repo` はワークフローの起動と再実行を含む)を資格情報マネージャーに保存するので、所有者がこのPCのほかの GitHub のリポジトリで一度 push してブラウザでサインインすれば、設計で消した資格情報が同じ権限で作り直される。Claude は同じ Windows のユーザーなので、その鍵を読んで `release.yaml` を起動できる(要件4の7の「git が覚えている鍵」)。設計は一度消す手順だけで、作り直されないようにする手順が無い。所有者の毎日の操作に関わるので、要件4の8の「増える手順」として所有者に示す必要がある | 手順書に、所有者がこのPCで github.com に対して使う git の鍵をすべて起動・承認の権限の無い鍵にする手順を足す。例: Git Credential Manager のサインインの方法を PAT に限る(`git config --global credential.gitHubAuthModes pat`)か、Git Credential Manager を外して `gh auth setup-git` でグローバルのヘルパーを gh にする(この場合、所有者はほかのリポジトリの push にも fine-grained PAT の対象を広げる必要がある)。結合テストに「`git credential fill` で github.com の資格情報を引いたとき、返るのが fine-grained PAT だけである」を足す。増える手順を設計に書き、所有者が承認のときに決める |
| D1-1-3 | 中 | design.md 所有者の GitHub の鍵(権限の一覧)、要件4の8 | fine-grained PAT で `.github/workflows/` の下のファイルを含むコミットを push するには Workflows の権限が要る(GitHub の文書「Permissions required for fine-grained personal access tokens」の Workflows)。設計の所有者の PAT の一覧(Contents、Pull requests、Issues の write と Actions、Metadata の read)に Workflows が無いので、所有者はターミナルからワークフローを変えた push ができなくなる(`参加者セットアップ手順` 2-3 の確認2は所有者がターミナルから push する運用を前提にしている)。Workflows の権限は起動・再実行・取り消し・承認のどれも含まないので、付けても要件4は崩れない。設計は「所有者は、同じPCで、自分の名義の gh と git を使い続けられる」と書くだけで、この制約を要件4の8のとおり所有者に示していない。承認後は、所有者がワークフローを push したときに初めて分かり、PAT の作り直しになる | 一覧に Workflows: Read and write を足す。付けないと決めるなら、所有者がワークフローを変えた push をできなくなることを設計に書き、所有者が承認のときに決める |
| D1-1-4 | 低 | design.md 所有者の GitHub の鍵(「この PAT の期限が切れたら、所有者は作り直す」)、失敗したときの扱い、要件7の1 | 要件7の1は「所有者は、この準備のあと、毎回の手作業を増やさない」とし、例外を障害のときの手順とブラウザの許可の2つに限っている。設計は所有者の fine-grained PAT の定期の作り直しを足しているが、期限の長さ(fine-grained PAT で選べる最長)と、作り直しの手順の置き場を書いていない。ボットの classic PAT の1年ごとの再発行(`基盤構築手順` 3-1「カレンダーに登録する」)は今もある手作業だが、所有者の PAT の分が増える | 設計に、所有者の PAT の期限の長さと、作り直しの手順を書く手順書(`基盤構築手順` の「復旧」の節など)を書き、要件7の1の例外として所有者に示す。GitHub が期限なしを選べるなら、それを選ぶ |
| D1-1-5 | 低 | design.md ファイルの構成(Claude が変えるファイルの `参加者セットアップ手順.md` と `基盤構築手順.md`) | `参加者セットアップ手順` 2-2 の確認1・4(`gh api user --jq .login` が `DogisRiki-bot` を返す)と確認2(`hosts.yml` に `oauth_token` が無いこと。「平文のまま先へ進まない」)は、インストールトークンでは成り立たない(インストールトークンは `/user` を呼べない。設計は `hosts.yml` に `oauth_token` を平文で書く)。`基盤構築手順` の「botのPATが期限切れになったときの復旧」も、Claude の gh がボットの PAT を使う前提で書かれている。設計はこれらの手順書に「足す」とだけ書き、置き換える既存の節を挙げていないので、tasks で直す範囲が決まらない | 変えるファイルの説明に、2-2・2-3 の確認と「復旧」の節を App の形に書き直すことを足す。確認の例: `gh api /installation/repositories --jq '.repositories[].full_name'` が `DogisRiki/KeirekiPro` を返す。平文の確認は、1時間で切れる鍵であることを書いて外す |

### 前の段階への指摘

| ID | 対象 | 該当箇所 | 内容 |
|---|---|---|---|
| D1-1-6 | requirements | 要件4の1・4の2、要件6の1・6の2、範囲(決めないこと) | 要件4の1「実行は作られない。所有者に承認の依頼も届かない」と4の2「別のプログラムからの呼び出し」によらず拒むことは、要件6の1・6の2(Claude が同じリポジトリにブランチを push し、ワークフローのファイルを変えた PR を作れる)と、GitHub の今の作り(同じリポジトリの PR のワークフローは GITHUB_TOKEN を `actions: write` に上げられ、`workflow_dispatch` の実行を作れる。指摘 D1-1-1)のもとでは、同時に満たせない。範囲の「決めないこと」が除いているのは OIDC のロールの権限だけで、この道は除かれていない。所有者の判断が要る。選べる形は、(a) このすきを受け入れ、要件4の1を「Claude の手元の鍵では実行を作れない。PR のワークフローから GITHUB_TOKEN で作った実行は production の環境の承認で止まる」に直し、範囲の「決めないこと」にこの道を書く。(b) 本番を変えるワークフロー3本(と呼ばれる2本)を、Claude が書き込めない別のリポジトリに移す(OIDC の信頼ポリシーと環境の設定も移る。所有者の起動の手順が変わる)。(c) `.github/workflows/` の変更を所有者だけに限るルール(push ルールの file path の制限)を置く。この形は要件6の2(Claude がワークフローのファイルを変えた PR を作れる)と両立しないので、6の2を変えることになる。どれも所有者から見える結果が変わるので、design では決められない |

- 往復: 1回目 / 高1 中2 低2

## サイクル2 往復1(2026-10-12)

サイクル1の往復1の指摘が、作り直した design.md にどう反映されたかを確かめた。D1-1-1 は、所有者が「Claude が足したワークフローに本番のワークフローを起動させる道と、ワークフローの中で秘密と本番の権限に触れる道は #557 で扱う」と決め(requirements 要件4の9、サイクル4で承認)、design は「作らないもの」の3つ目にその道を書き、全体の構成の末尾(「#557 で扱う道は残る」)でも触れている。#557 の本文(「Claude が PR やブランチで変えたコードとワークフローが、GitHub のワークフローの中で、本番の秘密の値と本番の AWS の権限に触れられないようにする」「Claude が足したか変えたワークフローに、本番のワークフローを起動させられないようにする」)は、design が #557 に回した2つの道と一致する。D1-1-2 は、所有者が資格情報マネージャーの github.com の資格情報を消し、git の全体の設定で github.com の資格情報ヘルパーを gh だけにする手順が「所有者の GitHub の鍵」に入り、Git Credential Manager が github.com で呼ばれなくなる形で解決している。D1-1-3 は、所有者の PAT の一覧に Workflows: Read and write が入り、理由(ワークフローを変えたコミットの push)も書かれている。D1-1-4 は、期限を最も長い期間にすること、GitHub のメールで知らせが来ること、作り直しが要件7の1の例外になることが書かれている。D1-1-5 は、`参加者セットアップ手順` 2-2 の確認の置き換えと、`基盤構築手順` の「復旧」の節の直しが「手順書と PR の本文」に書かれている。

要件1〜7の受入基準と「対応する要件」を突き合わせ、すべての受入基準がいずれかの部品で裏付けられていることを確かめた(要件4の9は例外の項目なので、裏付ける部品は要らない)。Issue #489 の「やりたいこと」の取りこぼしと、Issue に無い勝手な追加は無い(所有者の判断で #557 に回した道は、要件4の9として requirements に書かれている)。「プロジェクトの決まりを守っているか」の7項目は、関係のある3項目(品質チェックの設定、使う外部の機能、新しいライブラリ)と関係のない4項目に分かれて全部出ており、「ファイルの構成」と矛盾しない(`.claude/settings.json` と `.claude/hooks/` を所有者が置くことを両方に書いている)。「作らないもの」の `.claude/settings.json` の禁止の一覧は、「ファイルの構成」が変えるのがフックの登録だけなので矛盾しない。steering(`tech.md` 11行目「`terraform apply` は人間がGitHub Actions経由でのみ実行する」)と矛盾する前提は無い。

設計の前提をリポジトリの実ファイルで確かめた。(1) 本番を変えるワークフロー3本の入口は `workflow_dispatch` だけで、`.github/workflows/` に `repository_dispatch` を入口にするワークフローは無い。App と所有者の PAT に与える Contents の write は `repository_dispatch` のイベントを作れるが、それで動くワークフローが無いので、要件4の1・4の2は崩れない。(2) ECS のタスク定義(`terraform/modules/ecs/main.tf` 56〜69行目)の `environment` は `SPRING_PROFILES_ACTIVE` `TZ` `JAVA_TOOL_OPTIONS` だけで、秘密の値を持たないので、`ReadOnlyAccess` の `ecs:DescribeTaskDefinition` で秘密が読めることは無く、要件1の4は readonly-guard の3つの Deny で足りる。(3) terraform に KMS の鍵は無く、S3 は3バケットとも `AES256`(SSE-S3)なので、`kms:Decrypt` の Deny で読めなくなる調査の情報は無い(要件2の2と食い違わない)。(4) CODEOWNERS は `/.claude/` 全体を所有者の承認の対象にしているので、`.claude/scripts/github-app/` を足すこの PR は、設計の「PR は CODEOWNERS の承認を待つ」のとおり自動マージされない。(5) `pre-merge-check.yaml` は所有者の承認を `github.repository_owner`(41・59行目)で判定し、`auto-merge.yaml` の作成者の判定は `dependabot[bot]` の除外だけ(92行目)なので、PR の作成者が App のボットに変わっても今の仕組みは動く。(6) `.claude/skills/` の中に `gh api user` や `gh auth` でログイン名を確かめる手順は無いので、インストールトークン(`/user` を呼べない)でも Claude の手順は止まらない。(7) `ci.yaml` の入口は `push` と `pull_request` だけで `workflow_dispatch` が無い(D2-1-2)。(8) `基盤構築手順` 3-2 と「復旧」4 は `gh secret set BOT_GITHUB_TOKEN --app dependabot` を使う(D2-1-4)。

却下された指摘は無い。サイクル1の低の指摘(D1-1-4、D1-1-5)は作り直しで解決しているので、もう一度は出さない。

### 申告

サイクル1の申告2〜5(変更用ロールの上限3600秒、`PowerUserAccess` と `iam:PassRole` なし、3つのフックでの入れ替え、Deny の範囲)の決めごとは変わっていないので、ここでは繰り返さない。申告1(`BOT_GITHUB_TOKEN` の4本を classic PAT のまま残す)は、所有者が #557 に回すと決めたので、Claude の解釈ではなくなった。作り直した design で新しく決めたのは次の3つである。

**1. 所有者の gh の鍵を、所有者のすべてのリポジトリを対象にした fine-grained PAT にし、git の全体の設定で github.com の資格情報ヘルパーを gh だけにし、資格情報マネージャーの github.com の鍵を消す** — design.md 所有者の GitHub の鍵

- Issue の記載: なし。Issue は Claude の操作の止め方だけを求めている
- 決めたこと: 所有者がこのPCで github.com に対して使う git の鍵を、1つの fine-grained PAT(Contents、Pull requests、Issues、Workflows の write と Actions、Metadata の read。対象はすべてのリポジトリ)に寄せ、Git Credential Manager が github.com で呼ばれないようにする
- 他にありえた選択肢: 対象を KeirekiPro だけにし、ほかのリポジトリは Git Credential Manager のサインインを PAT に限る設定(`credential.gitHubAuthModes pat`)で守る。または、Pull requests を Read-only にする(D2-1-1)
- 外れていた場合: 所有者がこのPCから、自分の持ち物でないリポジトリ(ほかの人や Organization のもの)に push するとき、この PAT では通らず、所有者はそのリポジトリごとに別の手段を用意することになる。Pull requests の write を残すことの影響は D2-1-1 に書いた

**2. Claude の gh のトークンを、鍵の保管庫(Windows の資格情報マネージャー)ではなく `hosts.yml` に平文で書く** — design.md refresh-token.sh「呼び出し方」

- Issue の記載: なし
- 決めたこと: 1時間で切れるインストールトークンを `$GH_CONFIG_DIR/hosts.yml` の `oauth_token` に書く。`参加者セットアップ手順` 2-2 の確認2(「平文のまま先へ進まない」)は、設計が置き換える
- 他にありえた選択肢: 発行のたびに `gh auth login --with-token` で保管庫に入れる
- 外れていた場合: 平文の鍵は同じ Windows のユーザーなら誰でも読めるが、App の秘密鍵(`PRIVATE_KEY_FILE`)も同じ場所に平文で置くので、守りの強さは変わらない。所有者が「鍵を平文で置かない」という今の決まりを続けたいなら、保管庫に入れる形に直すことになり、`refresh-token.sh` の書き方とテストが変わる

**3. 変更用ロールへの切り替えの元の鍵に、所有者の普段の `aws login` の鍵(`%USERPROFILE%\.aws\login\cache`)を使う** — design.md ops-shell.ps1「役割」

- Issue の記載: なし
- 決めたこと: `ops-shell` は自分ではサインインせず、普段のターミナルの `aws login` で得た鍵を元にして、6桁付きで AssumeRole する。普段の鍵が切れていたら、所有者は普段のターミナルで `aws login` してから `ops-renew` を打つ
- 他にありえた選択肢: `ops-shell` の中で `aws login` を打ち、サインインの鍵を管理者だけが読める場所に置く
- 外れていた場合: 障害のときに普段の鍵が切れていると、所有者の手順が「普段のターミナルで `aws login` してから、管理者のターミナルで6桁を入れる」の2段になる。元の鍵は Claude が読み書きできる場所にあるが、6桁なしでは切り替えられないので、Claude の力は増えない(設計がそう書いており、研究の記録の試験と合う)

### 指摘

| ID | レベル | 該当箇所 | 内容 | 直し方の案 |
|---|---|---|---|---|
| D2-1-1 | 低 | design.md 所有者の GitHub の鍵(「Claude はこの PAT を読めるが、Claude の App も Workflows の write を持つので、この PAT で Claude にできることは増えない」) | この文は事実と合わない。所有者の PAT は所有者(DogisRiki)の名義で動くので、Pull requests の write があれば、Claude はこの PAT で PR に所有者としての Approve のレビューを付けられる(GitHub の REST「Create a review for a pull request」は Pull requests の write で呼べる)。所有者は CODEOWNERS(`/.github/` `/.claude/` `quality.gradle` など)の承認者であり、`pre-merge-check.yaml` と dependency-gate は `github.repository_owner` の Approve で通る(`pre-merge-check.yaml` 41・59行目)。Claude の App はこの承認を付けられないので、この PAT で Claude にできることは App より増える。また、対象がすべてのリポジトリなので、Claude はこの PAT で所有者のほかのリポジトリにも push できる(App は KeirekiPro にだけ入れる)。今の所有者の OAuth の鍵(scope `repo`)でも同じことができるので、この spec で悪くなるわけではなく、本番を変える操作そのもの(起動と承認)はこの PAT でも拒まれる。ただし、所有者が要件4の8の判断をするときに読む文なので、事実のとおりに書く必要がある | 文を「この PAT の権限では、本番のワークフローの起動と承認はできない。ただし、Claude はこの PAT で、所有者の名義の PR の Approve(CODEOWNERS と pre-merge-check と dependency-gate の承認)と、所有者のほかのリポジトリへの push ができる。今の所有者の鍵でもできることで、この spec で広がるものではない」のように直す。所有者がターミナルから PR を作ったりレビューしたりしないなら、Pull requests を Read-only にして、この道を同時に閉じることを所有者に示す |
| D2-1-2 | 低 | design.md テストの方針(結合テストの GitHub の1つ目: `ci.yaml` の dispatch が 403 になり、新しい実行が無い) | `ci.yaml` の入口は `push` と `pull_request` だけで、`workflow_dispatch` が無い(`.github/workflows/ci.yaml` 7〜11行目)。誰の鍵でも `ci.yaml` は起動できないので、「`gh run list --workflow ci.yaml` に新しい実行が無い」は権限によらず成り立ち、権限が絞れたことの確かめにならない。「403 になる」のほうは、GitHub が権限の判定を入口の判定より先に行うなら権限の確かめになるが、審査役はその順序を確かめていない。起動の権限を持つ鍵で試したときに 422(入口が無い)と 403 を見分けられる形にしておかないと、確かめが通っても何を確かめたか分からない | 起動の確かめには、`workflow_dispatch` を入口に持ち、本番を変えないワークフローを使う(例: `auto-merge.yaml` の71行目の `workflow_dispatch`。手動の見直しで、予約の無い PR を見直すだけ)。`ci.yaml` は `gh run rerun` の確かめにだけ使う |
| D2-1-3 | 低 | design.md refresh-token.sh「呼び出し方」(`hosts.yml` の `user: <App の名前>[bot]`) | `gh auth git-credential` は、`hosts.yml` の `user` を git のユーザー名として返す。GitHub の文書(インストールトークンの説明)は、git の HTTPS でインストールトークンを使うときのユーザー名を `x-access-token` と示している。ほかのユーザー名でも通るかを審査役は確かめていない。通らないと、Claude の push が結合テストの最後の項目(「Claude がブランチを push し」)で初めて失敗し、`hosts.yml` の形を直すことになる | `user` を `x-access-token` にする(文書どおりの形になり、ほかの表示には使わない)。または、`参加者セットアップ手順` に置く確かめ(`refresh-token.sh --force` のあと)に `git push --dry-run` を足し、準備の最初の段階で確かめる |
| D2-1-4 | 低 | design.md 手順書と PR の本文(`基盤構築手順` の「ボットの classic PAT を作り直して `BOT_GITHUB_TOKEN` を置き換える手順」と「復旧」の節)、所有者の GitHub の鍵、要件4の8 | `基盤構築手順` 3-2 と「復旧」4 は、Dependabot の secrets の登録と確認に `gh secret set BOT_GITHUB_TOKEN --app dependabot` と `gh secret list --app dependabot` を使う。所有者の fine-grained PAT には Secrets の権限が無いので、所有者の gh ではこれらが拒まれる。設計はこの節を直すと書いているが、Dependabot の secrets を GitHub の画面(Settings → Secrets and variables → Dependabot)で登録することを書いていないので、tasks がこのコマンドを残したまま手順を直すおそれがある。所有者の手順が gh から画面に変わるので、要件4の8の「増える手順」にも当たる | 「手順書と PR の本文」に、`BOT_GITHUB_TOKEN` の登録(Actions と Dependabot の両方)は GitHub の画面で行い、gh の `secret` のコマンドは手順書から外すと書く。所有者の PAT に Secrets の権限は付けない(付けると、Claude がこの PAT で secrets を書き換えられる) |

### 前の段階への指摘

この往復では無い。

- 往復: 1回目 / 高0 中0 低4
- 往復: 1回で収束 / 未解決: 0件

## サイクル3 往復1(2026-10-12)

サイクル2で収束したあと、所有者の判断で直した1か所(「所有者の GitHub の鍵(fine-grained PAT)」の役割の欄。所有者の PAT の Pull requests を Read-only にし、所有者は PR の承認を GitHub の画面で行う)と、書き方の点検で直した文を、design.md 全体を読み直して審査した。直した欄は、D2-1-1 が示した「この PAT で Claude が所有者の名義の PR の承認を出せる」道を、所有者が PAT の権限の選び方で一緒に塞ぐと決めたことと、この道が要件の範囲の外であることを本文に書いている。要件4の8(所有者の手順が増える場合は設計で示す)に対して、「今まで端末の `gh pr review --approve` で承認していたときは、この手順が画面の操作に変わる」と増える手順を示しているので、要件4の8は満たされている。

この変更が所有者と Claude の今の手順を壊さないかを、リポジトリの実ファイルで確かめた。(1) 所有者向けの手順書(`doc/開発フロー/監査手順.md`、`基盤構築手順.md`、`参加者セットアップ手順.md`、README の「人間の役割」)に、所有者が `gh pr review` `gh pr create` `gh pr merge` `gh pr close` を打つ手順は無い。README 365行目と `監査手順.md` 184〜188行目は「承認ボタンを押す」と書いており、所有者の承認はもともと画面の操作である。`監査手順.md` 142・148行目の `@dependabot recreate` は PR へのコメントで、コメントの作成は Issues の write でも呼べるので、所有者の PAT(Issues: Read and write)で gh から打っても拒まれない。(2) Claude の側の `gh pr create`(`.claude/skills/ship/SKILL.md` 39行目)、`gh pr edit --add-label`(`review-loop/SKILL.md` 32行目)、`gh pr close`(`start/SKILL.md` 461行目)は Claude の gh(App のトークン。Pull requests: Read and write)で動くので、所有者の PAT の権限を絞っても変わらない。(3) 所有者の名義の Approve を人間の承認として扱うワークフローは、設計が挙げた `pre-merge-check.yaml`(41・59行目)、`guardrails.yaml`(83〜95行目)、`dependency-gate.yaml`(46〜58行目)のほかに、承認を受けて失敗した判定を再実行する `rerun-approval-gated-checks.yaml`(28〜29行目)がある。これは承認の結果を伝える側なので、設計の一覧に無くても設計は変わらない。(4) 「全体の構成」の図の `OwnerPat[所有者の gh の鍵 起動と承認なし]`、「失敗したときの扱い」の「同じ権限で PAT を作り直す」、「手順書と PR の本文」の `基盤構築手順` の項目(所有者の gh の鍵を fine-grained PAT に作り直す手順)は、直した欄と矛盾しない。

サイクル2で確かめた要件カバレッジ、「プロジェクトの決まりを守っているか」の7項目、作るものと作らないものの境界、Issue #489 との突き合わせは、この変更で崩れていない。書き方の点検の直しは文の主語と条件の書き方の直しで、設計の中身は変わっていない。却下された指摘は無い。D2-1-2〜D2-1-4 は「記録のみ」で本文は変わっていないが、低の指摘で tasks での扱いが response に書かれているので、もう一度は出さない。

### 申告

Pull requests を Read-only にし、所有者が PR の承認を GitHub の画面で行う形は、所有者が決めたことで、Claude の解釈ではない。サイクル2の申告1〜3の決めごとは変わっていない。この往復で新しく申告するものは無い。

### 指摘

| ID | レベル | 該当箇所 | 内容 | 直し方の案 |
|---|---|---|---|---|
| D3-1-1 | 低 | design.md 所有者の GitHub の鍵(「Claude はこの PAT を読めるが、Claude の App も Contents と Workflows の write を持つので、push について Claude にできることは増えない」) | D2-1-1 の残りの部分。この PAT の対象は所有者のすべてのリポジトリで、App は KeirekiPro にだけ入れるので、Claude はこの PAT で、所有者のほかのリポジトリに所有者の名義で push できる。KeirekiPro に限れば「push について増えない」は正しいが、文はリポジトリを限っていない。今の所有者の OAuth の鍵でもできることなので、この spec で広がるものではなく、本番を変える操作には届かない。所有者が要件4の8の判断をするときに読む文なので、事実のとおりに書いておくほうがよい | 「KeirekiPro への push について Claude にできることは増えない。所有者のほかのリポジトリへは、この PAT で Claude も push できるが、今の所有者の鍵でもできることで、この spec で広がるものではない」のように、リポジトリの範囲を書く |
| D3-1-2 | 低 | design.md テストの方針(結合テストの GitHub の項目) | 所有者の PAT の Pull requests を Read-only にして、Claude が所有者の名義で PR の承認を出す道を塞ぐと決めたが、結合テストにその確かめが無い。所有者の PAT の確かめは `env -u GH_CONFIG_DIR gh workflow run ci.yaml` の403だけである。権限の選び方を所有者が画面で行うので、確かめが無いと、Pull requests に write を付けたまま準備を終えても気づかない。本番を変える操作ではないので、要件7の3が求める確かめの対象ではない | 結合テストに「`env -u GH_CONFIG_DIR gh pr review --approve <開いている PR>` が 403 になる(所有者の PAT)」を足す。ついでに D2-1-2 のとおり、起動の確かめに使うワークフローを `workflow_dispatch` を持つものに替える |

### 前の段階への指摘

この往復では無い。

- 往復: 1回目 / 高0 中0 低2
- 往復: 1回で収束 / 未解決: 0件

## サイクル4 往復1(2026-10-12)

サイクル3で収束したあと、tasks の組み立ての点検が design に戻した5か所(起動の確かめを `auto-merge.yaml` に替えた、承認と取り消しと要件6の2の確かめを足した、`keirekipro-ops-guard` で `iam:CreateServiceLinkedRole` と `iam:DeleteServiceLinkedRole` も Deny する、シェルのテストはホストの Git Bash で流す、フックのテストをファイルの構成に足した)と、書き方の点検の直しを、design.md 全体を読み直して審査した。

直した箇所の前提をリポジトリの実ファイルで確かめた。(1) `auto-merge.yaml` は `workflow_dispatch` を入口に持ち(71行目)、入力を取らないので、`gh workflow run auto-merge.yaml` は入力の不足(422)ではなく権限で判定される。手動の実行は見直し(sweep)だけで、本番を変えない。(2) `terraform-apply.yaml` はジョブが1つで `environment: production` を指定している(38行目)ので、承認を待つあいだはジョブが始まらず、AWS の鍵も発行されない。「承認を待つあいだはジョブが始まらないので、本番は変わらない」は成り立つ。(3) `ci.yaml` の入口は `push` と `pull_request` だけで、`gh run rerun` と取り消しの確かめにだけ使うのは D2-1-2 の直し方と合う。(4) `.claude/scripts/parallel/tests/test-lib.sh` の見出しは「ホストの Git Bash から流す。前提: bash・perl(JSON::PP)・git」で、`.claude/hooks/tests/` にも同じ形のテストが6本ある。design の「使う既存の仕組み」の流し方の記載と合う。(5) `.claude/settings.json` の deny は `.claude/hooks/**` と `.claude/settings.json` の Edit と Write を止めており、`.claude/scripts/` は止めていない。「ファイルの構成」の「所有者が置く」の印がフックとフックのテストと `settings.json` にだけ付いていることと合う。(6) `PowerUserAccess` が `iam:*` を除いたうえで `iam:CreateServiceLinkedRole` と `iam:DeleteServiceLinkedRole` を許すことは、research.md の29行目(「サービスにひもづくロールの作成など一部を除く」)と合い、この2つを Deny しないと要件3の6(IAM のロールを作る・消す操作を拒む)が成り立たない。直しは要件に合う。

サイクル2・3で確かめた要件カバレッジ、「プロジェクトの決まりを守っているか」の7項目、作るものと作らないものの境界、Issue #489 との突き合わせは、この直しで崩れていない。却下された指摘は無い。

### 申告

サイクル2・3の申告の決めごとは変わっていない。この往復で新しく決めたのは次の2つである。

**1. 変更用ロールで `iam:CreateServiceLinkedRole` と `iam:DeleteServiceLinkedRole` を Deny する** — design.md keirekipro-ops「役割」

- Issue の記載: なし。要件3の6が「IAM の利用者・ロール・ポリシーを作る・変える・消す操作は、AWS が拒む」と書く
- 決めたこと: `PowerUserAccess` が許すサービスにひもづくロールの作成と削除も、`keirekipro-ops-guard` で Deny する
- 他にありえた選択肢: `PowerUserAccess` のまま許す(サービスにひもづくロールは AWS が定めた権限しか持てないので、権限を広げる道にはならない)
- 外れていた場合: 障害のときに、まだ一度も使っていない AWS のサービスを `ops-shell` から初めて使う操作(そのサービスにひもづくロールを AWS が自動で作る操作)が `AccessDenied` になり、terraform apply のワークフローかルートユーザーに回る。今使っているサービス(RDS、ECS など)のロールは既にあるので、止まったデータベースの起動などの今の障害の対応は変わらない

**2. 承認の確かめに、所有者が `terraform-apply.yaml` を本当に起動して承認待ちの実行を作り、確かめたあとに Reject する** — design.md テストの方針(結合テストの GitHub の項目)

- Issue の記載: なし。要件7の3は「Claude が試す操作は、拒まれなかったときにも本番を変えない操作にする」と書く
- 決めたこと: 承認待ちの実行は所有者が画面で作り、Claude の鍵と所有者の PAT で `pending_deployments` を打って 403 を見てから、所有者が Reject する
- 他にありえた選択肢: 承認の確かめを省き、App と PAT の権限の表(Deployments を付けていないこと)を画面で見るだけにする。または、本番を変えないワークフローに production の環境を付けた確かめ用のジョブを足す(ワークフローの変更になる)
- 外れていた場合: 確かめのあいだ、本番を変える実行が承認待ちで存在する。所有者が Reject でなく誤って承認すると `terraform apply` が動く(main に差分が無ければ変更は無いが、動くことに変わりはない)。Claude が試す操作そのものは要件7の3のとおり本番を変えない

### 指摘

| ID | レベル | 該当箇所 | 内容 | 直し方の案 |
|---|---|---|---|---|
| D4-1-1 | 低 | design.md テストの方針(結合テストの AWS の2つ目: 「所有者が `ops-shell` で6桁を入れると、`aws sts get-caller-identity` が `keirekipro-ops` を返す。`aws iam simulate-principal-policy` で、`keirekipro-ops` に … 拒まれることを見る」) | この項目は `ops-shell` の中で打つ流れで書かれているが、`aws iam simulate-principal-policy` には `iam:SimulatePrincipalPolicy` が要り、変更用ロールの `PowerUserAccess` は `iam:*` を除く(research.md 29行目。許す例外は `iam:CreateServiceLinkedRole`、`iam:DeleteServiceLinkedRole`、`iam:ListRoles` だけ)。そのため `ops-shell` の鍵でこのコマンドを打つと、確かめたい Deny ではなく、コマンド自体が `AccessDenied` になる。所有者はこの結果から、`keirekipro-ops-guard` が正しく付いているかを読み取れない。読み取り専用の `keirekipro` の鍵(`ReadOnlyAccess` は `iam:Get*`、`iam:List*`、`iam:Simulate*` を含む)なら、`--policy-source-arn` に変更用ロールの ARN を渡して、ロールの権限を確かめられる。PR の本文の確かめ方だけが変わり、ポリシーとスクリプトは変わらない | この項目を2つに分ける。`ops-shell` で打つのは `aws sts get-caller-identity` が `keirekipro-ops` を返すことと、15分後に `ExpiredToken` になることだけにする。`aws iam simulate-principal-policy --policy-source-arn arn:aws:iam::<ACCOUNT_ID>:role/keirekipro-ops --action-names rds:StartDBInstance iam:CreateUser iam:CreateRole iam:CreateServiceLinkedRole iam:DeleteServiceLinkedRole iam:PutRolePolicy` は、普段のターミナル(`keirekipro` の鍵)で打つと書く。1つ目の AWS の項目(`keirekipro` の `rds:StartDBInstance`)と同じ鍵で打つ形になる |
| D4-1-2 | 低 | design.md ファイルの構成(`.claude/hooks/tests/test-refresh-github-app-token.sh`)、テストの方針 | フックのテストをファイルの構成に足したが、テストの方針には `test-refresh-token.sh` の場合しか無く、フックのテストが何を確かめるかが書かれていない。フックの振る舞い(終了コードはいつも0、SessionStart と UserPromptSubmit で発行に失敗したら理由を標準出力に出す、`refresh-token.sh` を `--force` なしで呼ぶ)は「refresh-github-app-token.sh」の節にあるので、tasks はそこから場合を起こせるが、tasks の点検が「確かめが無い」と判定する材料になる。あわせて、PreToolUse の箇条書きの「`--force` を付けずに呼ぶ。長い作業の途中でトークンが切れないようにするためである」は、理由の文が「`--force` を付けない」理由ではなく「PreToolUse でも呼ぶ」理由を言っており、読み手が `--force` と理由を結びつけて誤読する | テストの方針に「単体テスト(`test-refresh-github-app-token.sh`。ホストの Git Bash で流す。`refresh-token.sh` を偽物に置き換える)」を足し、場合を書く: 偽物が0で終われば、フックは0で終わり何も出さない。偽物が1で終われば、SessionStart と UserPromptSubmit のときは0で終わり「GitHub App のトークンを入れ替えられなかった」と理由を標準出力に出す。PreToolUse のときも0で終わる。どの経路でも偽物に `--force` が渡らない。PreToolUse の箇条書きは「フックは、PreToolUse でも `refresh-token.sh` を呼ぶ。長い作業の途中でトークンが切れないようにするためである。`--force` は付けない」のように、理由と `--force` を分けて書く |

### 前の段階への指摘

この往復では無い。

- 往復: 1回目 / 高0 中0 低2
- 往復: 1回で収束 / 未解決: 0件
