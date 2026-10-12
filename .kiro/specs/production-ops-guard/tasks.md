# タスク

- [ ] 1. AWS の運用者の権限を定める
- [x] 1.1 普段のログインの権限の制限のポリシーを書く (並行可)

  Claude は、IAM ユーザー `keirekipro` に付けるインラインポリシー `keirekipro-readonly-guard.json` を、design.md の「keirekipro-readonly-guard」の節のとおりに書く。Claude は、アカウントの番号を `<ACCOUNT_ID>` と書く。
  - 完了の確かめ方: `perl -MJSON::PP` で読み込めること。state バケットのオブジェクトの読み取り、`secretsmanager:GetSecretValue`、`secretsmanager:BatchGetSecretValue`、`kms:Decrypt` の Deny と、変更用ロールへの `sts:AssumeRole` と自分の `iam:ChangePassword` の Allow だけを持つこと。12桁の数字(アカウントの番号)を含まないこと
  - 受入基準とテストの対応: 要件1の受入基準1・2・3と要件3の受入基準4(普段の鍵では AWS を変えられない)、要件1の受入基準4と要件2の受入基準2(秘密の値と state を読めない)、要件2の受入基準1(状態は読める)は、PR の本文の確かめ方の「A. Claude の普段の鍵で読めるもの・拒まれるもの」で確かめる
  - _要件: 1.1, 1.2, 1.3, 1.4, 2.1, 2.2, 3.4_
  - _対象の部品: keirekipro-readonly-guard_

- [x] 1.2 変更用ロールの信頼ポリシーとインラインポリシーを書く (並行可)

  Claude は、変更用ロール `keirekipro-ops` の信頼ポリシー `keirekipro-ops-trust.json` とインラインポリシー `keirekipro-ops-guard.json` を、design.md の「keirekipro-ops」の節のとおりに書く。
  - 完了の確かめ方: 2つのファイルが `perl -MJSON::PP` で読み込めること。信頼ポリシーが、主体を `keirekipro` に限り、`aws:MultiFactorAuthPresent` と、`aws:MultiFactorAuthAge` が60未満であることの両方の条件を持つこと。インラインポリシーが、`sts:AssumeRole`、`iam:CreateServiceLinkedRole`、`iam:DeleteServiceLinkedRole` の Deny だけを持つこと。12桁の数字を含まないこと
  - 受入基準とテストの対応: 要件1の受入基準7(新しくサインインした直後の60秒は通る)は、この完了の確かめ方で信頼ポリシーの条件が60秒未満であることを見る。要件1の受入基準6(6桁なしの切り替えは拒まれる)と要件3の受入基準5(マネジメントコンソールのスイッチロール)は、PR の本文の確かめ方の「B. 切り替え」で確かめる。要件3の受入基準6(IAM のロールの作成などは拒まれる)は、「C. 変更用ロールで拒まれるもの」で確かめる
  - _要件: 1.6, 1.7, 3.5, 3.6_
  - _対象の部品: keirekipro-ops_

- [x] 2. 所有者が管理者のターミナルで切り替えるスクリプトを作る (並行可)

  Claude は、`ops-shell.ps1` と `aws-config` を、design.md の「ops-shell.ps1」の節の手順のとおりに書く。Claude は、スクリプトを ASCII の文字だけで書く。スクリプトは、鍵をファイルに書かない。Claude は、アカウントの番号を `<ACCOUNT_ID>` と書く。
  - 完了の確かめ方: `powershell.exe -NoProfile -Command` から `[System.Management.Automation.Language.Parser]::ParseFile` でスクリプトを読み、構文の誤りが0件であること。`grep -P '[^\x00-\x7F]'` で ASCII 以外の文字が0件であること。スクリプトの中に、`Out-File`、`Set-Content`、`Add-Content`、`>` によるファイルへの書き出しが無いこと。12桁の数字を含まないこと。スクリプトが、design.md の「ops-shell.ps1」の節の9つの手順(管理者でなければ終える、`AWS_` などの環境変数を消す、`PATH` を4つにする、`AWS_CONFIG_FILE` と `AWS_SHARED_CREDENTIALS_FILE` を `C:\Program Files\KeirekiPro\` に向ける、作業の場所を変える、`Read-Host -AsSecureString` で受ける、`aws.exe` を絶対のパスで `--duration-seconds 900` を付けて呼ぶ、鍵を環境変数に置く、`ops-renew` を定める)をすべて持つことを、所有者が置く前に Claude が読んで見ること。`aws-config` が、`source` のプロファイルに `login_session` と `region = ap-northeast-1` だけを持つこと
  - 受入基準とテストの対応: 要件3の受入基準1・2・3(管理者のターミナルで6桁を入れると15分変えられる。Claude は鍵を読めない)は、PR の本文の確かめ方の「B. 切り替え」で確かめる
  - _要件: 3.1, 3.2, 3.3_
  - _対象の部品: ops-shell.ps1_

- [ ] 3. Claude の手元の gh を GitHub App のトークンで動かす
- [x] 3.1 トークンを入れ替えるスクリプトをテストから作る (並行可)

  Claude は、`refresh-token.sh` を、design.md の「refresh-token.sh」の節の呼び出し方のとおりに、テスト `test-refresh-token.sh` を先に書いてから作る。テストは、テストの中で作った鍵と偽の `curl` を使い、ネットワークにつながない。Claude は、ホストの Git Bash で `bash .claude/scripts/github-app/tests/test-refresh-token.sh` を打って、テストを流す。
  - 完了の確かめ方: `test-refresh-token.sh` の場合がすべて通ること。新しい `*.sh` を `git add` したあと、CI と同じ形で、追跡しているすべての `*.sh` をまとめて渡した shellcheck の指摘が0件であること。`hosts.yml` の `user` の値を GitHub の公式文書で確かめ、根拠の URL をテストの冒頭の注記に書くこと
  - 受入基準とテストの対応: 要件6の受入基準1・4(Claude の gh と git の push が今までどおり動き、仕組みのワークフローも動く)は、テストの「期限が近ければ、署名した JWT で発行したトークンを hosts.yml に書く」「github-app.env が無ければ何もしない」「curl が失敗したら hosts.yml を書き換えずに終了コード1で終える」「期限まで600秒以上あれば curl を呼ばない」「--force なら期限の前でも発行する」と、PR の本文の確かめ方の「D. GitHub の App の鍵」で確かめる
  - _要件: 6.1, 6.4_
  - _対象の部品: refresh-token.sh_

- [x] 3.2 トークンを入れ替えるフックとそのテストを用意する

  Claude は、フック `refresh-github-app-token.sh` と、そのテスト `test-refresh-github-app-token.sh` と、`.claude/settings.json` の SessionStart、UserPromptSubmit、PreToolUse(matcher は `Bash`)への登録を、design.md の「refresh-github-app-token.sh」の節のとおりに、このセッションの scratchpad の下の `production-ops-guard/` に用意する。テストは、scratchpad に置いたフックを、`refresh-token.sh` を偽物に置き換えたうえで、3つのイベントの入力で直接呼んで確かめる。
  - 完了の確かめ方: scratchpad のテストが通ること。テストは、偽物の `refresh-token.sh` が成功したときに3つのイベントのどれでも終了コード0で終えること、`refresh-token.sh` が失敗したときに SessionStart と UserPromptSubmit では理由を標準出力に出し、どのイベントでも終了コード0で終えること、フックが `refresh-token.sh` に `--force` を渡さないことを確かめる。scratchpad のフックとテストを、追跡しているすべての `*.sh` とまとめて shellcheck に渡し、指摘が0件であること。登録を足した `settings.json` の下書きが `perl -MJSON::PP` で読み込めること
  - 受入基準とテストの対応: 要件6の受入基準1・4(Claude の gh と git の push が今までどおり動き、仕組みのワークフローも動く)は、テスト `test-refresh-github-app-token.sh` の「入れ替えが成功すれば終了コード0で終える」「入れ替えに失敗しても Claude の操作を止めない」と、PR の本文の確かめ方の「D. GitHub の App の鍵」で確かめる
  - _要件: 6.1, 6.4_
  - _対象の部品: refresh-github-app-token.sh_

- [x] 4. Claude の振る舞いの決まりを CLAUDE.md に書く (並行可)

  Claude は、CLAUDE.md の「自律動作の境界」の節に、design.md の「CLAUDE.md の決まり」の節の4つの決まりを足す。
  - 完了の確かめ方: CLAUDE.md の「自律動作の境界」の節に、拒まれたときの振る舞い、AWS を変える操作とワークフローの手での起動を試さないこと、所有者の GitHub の鍵を使わないこと、ブラウザで github.com と AWS のコンソールを操作する前に伝えることの4つが書かれていること
  - 受入基準とテストの対応: 要件1の受入基準5と要件4の受入基準6(AWS や GitHub に操作を拒まれたら、Claude は別の書き方で試さず、何をしようとして拒まれたかを所有者に伝える)、要件5の受入基準1・2(Claude は、github.com と AWS のコンソールでどのページで何をするかを所有者に伝えてから、1回の操作ごとに所有者の許可を求める)は、PR の本文の確かめ方の「G. Claude の振る舞いの決まり」(4つの決まりが CLAUDE.md にあることを見る)で確かめる
  - _要件: 1.5, 4.6, 5.1, 5.2_
  - _対象の部品: CLAUDE.md の決まり_

- [ ] 5. 所有者の準備と障害のときの手順を書く
- [x] 5.1 Claude の手元の準備と ops-shell を置く手順を書く (並行可)

  Claude は、`参加者セットアップ手順.md` に、`github-app.env` と App の秘密鍵の置き場とその確かめ方を書き、「2-2. PR作成名義の固定(bot専用のgh設定ディレクトリ)」の節を、ボットの classic PAT で `gh auth login` する手順から、App のトークンを `refresh-token.sh` で入れる手順に置き換え、確かめ方も置き換える。あわせて、`ops-shell.ps1` と `aws-config` の `<ACCOUNT_ID>` をアカウントの番号に置き換えて `C:\Program Files\KeirekiPro\` に置き、空の `empty-credentials` を同じ場所に作り、全利用者のスタートメニューに「KeirekiPro ops」を作る手順を書く。
  - 完了の確かめ方: 手順が、`refresh-token.sh --force` のあとに `gh auth status` と `gh repo view DogisRiki/KeirekiPro` で確かめる形になっていること。`参加者セットアップ手順.md` に、ボットの classic PAT を Claude の手元(`.gh-bot`)に入れる手順が残っていないこと。`<ACCOUNT_ID>` を置き換えるコマンドと、`empty-credentials` を作るコマンドがあること。スタートメニューの項目の起動の内容が design.md の「ops-shell.ps1」の節と一致すること
  - 受入基準とテストの対応: 要件6の受入基準1(Claude は今と同じく、ブランチを push し、PR と Issue を作り、コメントを書き、ワークフローの実行の様子とログを読める)と要件7の受入基準1(所有者が最初に1回だけ行う準備の手順を、既存の環境構築の手順書に書く)は、所有者が手順のとおりに準備を終え、PR の本文の確かめ方の「B. 切り替え」と「D. GitHub の App の鍵」が通ることで確かめる
  - _要件: 6.1, 7.1_
  - _対象の部品: 参加者セットアップ手順.md_
  - _依存: 2, 3.1_

- [x] 5.2 GitHub の準備の手順を書く (並行可)

  Claude は、`基盤構築手順.md` に、GitHub App を作ってインストールする手順、ボットの classic PAT を作り直して `BOT_GITHUB_TOKEN` を GitHub の画面で Actions と Dependabot の両方の秘密に置き換える手順、所有者の gh の鍵を fine-grained PAT(Pull requests は Read-only)に作り直して `gh auth login --with-token` でログインし直し、前の OAuth の鍵を取り消す手順、資格情報マネージャーの github.com の資格情報を消して git の資格情報ヘルパーを設定する手順、ユーザーの環境変数の GitHub の鍵を消す手順、所有者の前提の3つ(「常に許可」を出さない、内蔵ブラウザでサインインしない、Claude Desktop を管理者として起動しない)を書く。あわせて、Claude がワークフローのファイルを足して本番のワークフローを起動させる道と、ワークフローの中でリポジトリの秘密に触れる道は、この準備では塞がず #557 で扱うことを書く。「botのPATが期限切れになったときの復旧」の節を直し、「App の秘密鍵を作り直すとき」の節を足す。「1」と「3-1」の、ボットの PAT を参加者セットアップで使うという記述を、ボットの PAT は `BOT_GITHUB_TOKEN` にだけ使う記述に直す。
  - 完了の確かめ方: App の権限の一覧と、所有者の PAT の権限の一覧が、design.md の「refresh-token.sh」と「所有者の GitHub の鍵(fine-grained PAT)」の節と一致すること。上に挙げた手順と、#557 で扱う道の記述がすべてあること。`基盤構築手順.md` に、ボットの PAT を Claude の手元に入れる記述が残っていないこと。所有者の前提の3つ(「常に許可」を出さない、内蔵ブラウザでサインインしない、Claude Desktop を管理者として起動しない)が書かれていること
  - 受入基準とテストの対応: 要件4の受入基準1・2・3・4(App の鍵では起動・再実行・取り消し・承認ができない)は、PR の本文の確かめ方の「D. GitHub の App の鍵」で確かめる。要件4の受入基準5・7・8(所有者は画面で起動・承認でき、所有者の鍵を Claude が使っても起動・承認できず、所有者は gh と git を使い続けられる)は、「E. 所有者の PAT」で確かめる。要件4の受入基準9(Claude が足したワークフローの道はこの spec では塞がない)は、この完了の確かめ方で、`基盤構築手順.md` に #557 で扱うことが書かれていることを見る。要件5の受入基準1(所有者が許可しない限り、Claude は Claude in Chrome で github.com と AWS のコンソールを操作できない)の前提は、手順書に所有者の前提が書かれていることを見る。要件7の受入基準1(所有者が最初に1回だけ行う準備の手順を、既存の環境構築の手順書に書く)は、所有者が手順のとおりに準備を終えることで確かめる
  - _要件: 4.1, 4.2, 4.3, 4.4, 4.5, 4.7, 4.8, 4.9, 5.1, 7.1_
  - _対象の部品: 基盤構築手順.md_

- [x] 5.3 AWS の準備の手順と、準備の全体の順番を書く

  Claude は、`手動作業手順.md` に、変更用ロールと制限のポリシーを作り、切り替えを確かめてから `AdministratorAccess` を外す手順を足し、既存の AWS を変える手順を design.md の「手順書と PR の本文」の節のとおりに直す。あわせて、`IAMロール・ポリシー設計.md` に、IAM ユーザー `keirekipro` と変更用ロール `keirekipro-ops` を足す。準備の全体の順番は、design.md の「移行」の順(AWS の権限を作る、ops-shell を置く、切り替えを確かめる、`AdministratorAccess` を外す、GitHub の準備)とし、ほかの手順書の該当する節へのつながりを書く。
  - 完了の確かめ方: 手順が、`<ACCOUNT_ID>` を置き換えるコマンドを含み、`AdministratorAccess` を外す前に切り替えを確かめる順になっていること。ops-shell を置く手順は `参加者セットアップ手順.md` の節を、GitHub の準備は `基盤構築手順.md` の節を指していること。「3. Terraformバックエンド用リソース作成」の章に `ops-shell` で行うことが、「4. GitHub Actions用OIDC設定」の章にルートユーザーで行うことが書かれていること。`IAMロール・ポリシー設計.md` に `keirekipro` と `keirekipro-ops` の項目があること。手順が、`keirekipro` に `ReadOnlyAccess` と `SignInLocalDevelopmentAccess` と `keirekipro-readonly-guard` を付けてから `AdministratorAccess` を外す順であること。手順が、`keirekipro-ops` に `PowerUserAccess` と `keirekipro-ops-guard` を付け、最大のセッションの長さを3600秒にすること。「1.2 AWS CLIの認証設定」の節に、普段のログインは読み取り専用であることが書き足されていること
  - 受入基準とテストの対応: 要件3の受入基準4・6(普段の鍵と変更用ロールで拒まれるもの)は、PR の本文の確かめ方の「A. Claude の普段の鍵で読めるもの・拒まれるもの」と「C. 変更用ロールで拒まれるもの」で確かめる。要件7の受入基準1(所有者が最初に1回だけ行う準備の手順を、既存の環境構築の手順書に書く)は、所有者が手順のとおりに準備を終え、PR の本文の確かめ方が通ることで確かめる
  - _要件: 3.4, 3.6, 7.1_
  - _依存: 1.1, 1.2_

- [x] 5.4 障害のときの手順書を書く (並行可)

  Claude は、`障害時の本番操作手順.md` を新しく書く。手順書は、`ops-shell` で AWS を変える手順、マネジメントコンソールにサインインし直して1分以内にスイッチロールする手順、15分を過ぎたときの `ops-renew`、切り替えられないときにルートユーザーで直す手順を持つ。
  - 完了の確かめ方: 所有者が障害のときにこの1つの文書を開けば、CLI とマネジメントコンソールの両方で AWS を変える手順が揃っていること
  - 受入基準とテストの対応: 要件3の受入基準1・2・5(ops-shell とマネジメントコンソールで変えられる)は、所有者がこの手順書のとおりに PR の本文の確かめ方の「B. 切り替え」を行うことで確かめる。要件7の受入基準2(障害のときに所有者が AWS を変える手順を、所有者が障害のときに開く手順書に書く)は、文書の見出しに4つの手順が揃っていることを見る
  - _要件: 3.1, 3.2, 3.5, 7.2_
  - _対象の部品: 障害時の本番操作手順.md_
  - _依存: 2_

- [x] 6. 準備のあとの確かめ方を PR の本文の下書きに用意する

  Claude は、design.md の「テストの方針」の結合テストの項目に、下の追加の項目を足して、所有者の準備のあとに一度だけ行う確かめ方を、このセッションの scratchpad の下の `production-ops-guard/pr-body-check.md` に書く。Claude は、`/ship` で PR を作るときに、この下書きを本文の節「マージのあとにすること」として載せる。変更用ロールの権限の確かめは、普段の `keirekipro` の鍵から、`aws iam simulate-principal-policy` の `--policy-source-arn` に変更用ロールの ARN を渡して行う。
  - 下書きの見出し: 「A. Claude の普段の鍵で読めるもの・拒まれるもの」「B. 切り替え」「C. 変更用ロールで拒まれるもの」「D. GitHub の App の鍵」「E. 所有者の PAT」「F. ワークフローのファイルを変えた PR」「G. Claude の振る舞いの決まり」
  - 追加の項目: A に、`aws rds describe-db-instances` と `aws logs describe-log-groups` が通ること。B に、`aws login` から2分以上たってから、6桁なしの切り替えが拒まれること。D に、Claude が Issue にコメントを書けることと、`gh run view --log` でワークフローのログを読めること。E に、所有者が普段のターミナルで `gh auth status` と `gh pr list` が通り、KeirekiPro とほかのリポジトリに git push できること、所有者が `terraform-apply.yaml` の承認待ちの画面を開いて Reject を操作できること
  - 完了の確かめ方: 下書きに、7つの見出しと、design.md の結合テストの項目と、上の追加の項目が揃っていること。`git diff --name-only origin/main` に、`.claude/scripts/parallel/run-check.sh`、`compose.yaml`、`docker/` の下のファイルが無いこと(品質チェックの設定と動かし方を変えていない)
  - 受入基準とテストの対応: 要件7の受入基準3(準備が済んだあとに一度だけ行う確かめ方を PR の本文に書き、Claude が試す操作は拒まれなかったときにも本番を変えない操作にする)は、この下書きがあることで確かめる。要件6の受入基準3(品質チェックは今と同じく動く)は、`git diff --name-only` の確かめで見る。要件6の受入基準2(ワークフローのファイルを変えた PR を作れる)は、下書きの「F. ワークフローのファイルを変えた PR」で確かめる
  - _要件: 6.2, 6.3, 7.3_

## 実装のメモ

- 所有者の指示(2026-10-12、タスク5.2の途中): 手順書(基盤構築手順・参加者セットアップ手順・手動作業手順)は「リポジトリを壊して1から作るときに見る手順」なので、今の環境の置き換え・取り消し・作り直し・外すといった切り替えの記述は書かない。切り替えは scratchpad の `production-ops-guard/pr-body-migration.md` にまとめ、PR の本文の「マージのあとにすること」に載せる。design.md の「手順書と PR の本文」の節と tasks.md の5.x の文面(作り直す・取り消す・外す手順を手順書に書く)より、この指示を優先する
- タスク4のレビューで、`.github/workflows/codex-review.yml` の誤りの文と、承認済みの spec `issue-method-deviation-gate` の design が、Claude に codex-review の再実行をさせていると分かった。App に替えたあとは Claude は再実行できないので、PR の本文の `Refs:` を直したときは、Claude がコミットを push して動き直させるか、所有者が再実行する。範囲の外なので所有者に報告する
- タスク3.2のレビューで、`.claude/settings.local.json` の `env` の `GH_CONFIG_DIR` がフックの処理に届くかを公式文書で確かめられなかった。そこでフックは、環境に `GH_CONFIG_DIR` が無ければ `settings.local.json` の `env.GH_CONFIG_DIR` を読んで渡す(テスト3件を足した)
- タスク3.1で、`hosts.yml` の `user` は `x-access-token` にした(design-response.md の D2-1-3 の対応のとおり、公式文書と gh の資格情報ヘルパーで確かめた)。design.md の「refresh-token.sh」の節の `<App の名前>[bot]` は古い記述で、手順書と PR の本文では `x-access-token` で書く
- タスク2のレビューで、ユーザーのモジュールの置き場(`DocumentsWindowsPowerShellModules`)に置いた偽の PSReadLine が、`-NoProfile -File` でもスクリプトより先に読み込まれると分かった。Claude が意図してファイルを置く道なので、要件3の3の例外に当たる。PR の本文の確かめ方と所有者への報告に、この道を例外に含むと明記する。`ops-renew` は aws.exe をその時点の作業の場所で起動するので、手順書に、`ops-renew` は `cd` で移らずに打つことを書く
- タスク1.1のレビューで、`ReadOnlyAccess` の `s3:Get*` は `s3:GetObjectTorrent` と `s3:GetObjectVersionTorrent` も許すと分かった。design の Deny の一覧には無い。PR の本文の確かめ方「A」で、`aws s3api get-object-torrent` で state の中身を取り出せないことも見る
- `.claude/hooks/` と `.claude/settings.json` は、Claude の Edit と Write が禁止されている。Claude はタスク3.2の成果物を scratchpad に用意し、`/ship` の前に、所有者が置くためのコマンドをまとめて示す。所有者が置いたあと、Claude は `/ship` のコミットの前に、置いた場所(`.claude/hooks/tests/`)でフックのテストを流し直し、通ることを確かめる
- `/kiro-impl` の実装役とレビュー役と `/ship` は、タスク3.2とタスク6の成果物を、それぞれのタスクに書いた scratchpad の置き場から読む。セッションが替わったときは、Claude はタスク3.2とタスク6の成果物を新しいセッションの scratchpad に作り直す
- このリポジトリは公開されているので、Claude は、ポリシーの JSON とスクリプトと手順書に、AWS のアカウントの番号を書かない
- 所有者の準備(AWS と GitHub の設定)は、この PR がマージされたあとに所有者が行う

## 完了条件(全タスク共通)

Claude は、どのタスクでも、タスクの箇条書きの欄を書いたうえで、次の4つを満たしたときにタスクを完了とする。

1. Claude は、タスクが満たす requirements.md の受入基準(要件の番号付きの項目)ごとに、それを確かめるテストのファイル名とテスト名を「受入基準とテストの対応」の行に書く。Claude は、確かめるテストの無い受入基準を残さない。
2. タスクで変えた領域の verify のスキル(`/verify-frontend` `/verify-backend` `/verify-terraform`)が、すべて成功している。
3. Claude は、テストを飛ばす設定、アサーションの削除、カバレッジや lint の対象からの除外を足して、完了条件を満たしたように見せない。CI の escape-hatch の検査が、これらの追加を機械で見つける。
4. Claude は、新しく書いたテストについて、テストの対象のコードを一時的に壊してテストが失敗することを確かめてから、コードを元に戻す。
