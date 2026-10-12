# 調査の記録

## まとめ
- 機能: `production-ops-guard`
- 調査の範囲: 既存の仕組みへの追加(AWS の IAM、GitHub の認証、所有者のPCの設定、Claude Code のフック)
- 設計を決めた発見:
  - Claude は所有者と同じ Windows のユーザーで動く。Claude Code の sandbox は Windows ネイティブでは動かず、UAC は Microsoft がセキュリティの境界と扱っていない。そのため、所有者のPCの中で Claude から鍵を隠しきることはできない。止める場所は、AWS の IAM と GitHub の権限に置く
  - `aws login` で得た鍵は、多要素認証を済ませたものとして扱われる。ロールの信頼ポリシーの条件を `aws:MultiFactorAuthAge` が60秒未満にすると、6桁のコードを入れたときだけ切り替えが通る(2026-10-12 に実機で確かめた)
  - classic PAT は、ワークフローの起動と承認の権限を、push や PR の権限から切り離せない。ボットは所有者の個人リポジトリに fine-grained PAT を使えない。起動と承認の権限を外せるのは GitHub App だけである

## 調べたこと

### AWS の多要素認証の条件と `aws login`
- きっかけ: 要件3で、所有者だけが6桁のコードで変更用の権限に切り替えられる形を決めた
- 見た資料: IAM の条件キー、MFA で API を守る方法、`aws login` の説明、AssumeRole の API の説明
- 分かったこと:
  - 公式文書は、`aws login` の鍵に MFA の条件キーが付くかを書いていない
  - 実機の試験: 権限の無い試験用のロール `keirekipro-mfa-probe` を所有者が作った。信頼ポリシーの条件を `aws:MultiFactorAuthPresent` が true にすると、`aws login` の鍵で6桁なしの切り替えが通った。条件を `aws:MultiFactorAuthAge` が60未満にすると、6桁なしは AccessDenied になり、所有者が `--serial-number` と `--token-code` を付けた切り替えは通った。試験のあと、所有者がロールを削除した
  - AssumeRole の `--duration-seconds` の最小は900秒である。ロールを引き受けたあとは、MFA を確かめ直さない
  - パスキーとセキュリティキーは STS の API に渡せない。6桁を入れて切り替える形は、仮想 MFA(認証アプリ)でだけ成り立つ。所有者の MFA は仮想 MFA である
- 設計への影響: 変更用ロールの信頼ポリシーに `aws:MultiFactorAuthAge` が60未満の条件を置く。`aws login` で新しくサインインした直後の60秒は、Claude の手元の鍵も条件を満たす(要件1の7で所有者が受け入れた)

### 読み取り専用の権限で読めるもの
- 見た資料: AWS 管理ポリシー `ReadOnlyAccess`、`PowerUserAccess` の参照ページ、`terraform/backend.tf`、`terraform/main.tf`
- 分かったこと:
  - `ReadOnlyAccess` は `secretsmanager:GetSecretValue` と `kms:Decrypt` を含まないが、`s3:Get*` を含む
  - terraform の state は S3 の `keirekipro-terraform-state` にあり、SSE-S3 で暗号化されている。state には、terraform が作った秘密の値が入る
  - `ReadOnlyAccess` は `sts:AssumeRole` を含まない
  - `PowerUserAccess` は、`iam:*`、`organizations:*`、`account:*` を除くすべてを許す(サービスにひもづくロールの作成など一部を除く)
- 設計への影響: 普段のログインに、state バケットのオブジェクトの読み取り、`secretsmanager:GetSecretValue`、`kms:Decrypt` の明示の Deny を足す。変更用ロールの権限は `PowerUserAccess` にする。`AdministratorAccess` は checkov の検査にも当たるので使わない

### 同じ Windows ユーザーでの管理者ターミナル
- 見た資料: UAC の仕組み、Microsoft のセキュリティのサービス基準、整合性レベルの説明、Claude Code の sandbox の説明
- 分かったこと:
  - 管理者として開いたターミナルも、同じユーザーの HKCU の環境変数、PowerShell のプロファイル、`~/.aws` の設定、Windows Terminal の設定を読む。Claude はこれらを書ける
  - Microsoft は UAC を境界と扱わず、すり抜けを直す対象にしていない。境界として守るのはユーザーの境界である
  - 整合性レベルの既定の方針は、下から上への書き込みを禁じるが、ファイルとレジストリの読み取りは禁じない。Medium のプロセスは High のプロセスのメモリを読めない
  - Windows 11 Home は Windows Sandbox を使えない。同じ Windows ユーザーからは、WSL のどのディストリでも root になれる
- 設計への影響: 管理者ターミナルのスクリプトは、Claude が書ける設定を読まない作りにする。それでも Claude が意図して Windows の設定に細工した場合は防げないので、要件3の3の例外として書いた。Windows の別のユーザーに分ける案は、管理するものが増えるので所有者が採らなかった

### GitHub の権限
- 見た資料: fine-grained PAT と GitHub App の権限の表、インストールトークンの説明、ワークフローの起動と承認の API、ルールセットと environment の説明
- 分かったこと:
  - ワークフローの起動、再実行、取り消しには Actions の write が要る。承認には Deployments の write が要り、さらに required reviewer 本人でなければならない
  - classic PAT の `repo` は、これらをまとめて含む
  - fine-grained PAT は、トークンの持ち主か組織が持つリポジトリにしか使えない
  - GitHub App のインストールトークンは、App に与えた権限を超えられない。App の権限を変える REST API は無く、変えるには所有者が Web で App の設定を変える
  - インストールトークンは1時間で切れる。App のトークンの push は、`on: push` と `pull_request` のワークフローを起こす
  - ワークフローの起動を、人で制限する GitHub の機能(ルールセットなど)は無い。environment の保護はジョブを止めるが、実行の作成は止めない
- 設計への影響: Claude の手元の gh を GitHub App のインストールトークンに替える。所有者の gh は fine-grained PAT に替え、Actions と Deployments の write を付けない

### ブラウザ
- 見た資料: Claude in Chrome の権限の説明、Claude Desktop の内蔵ブラウザの説明
- 分かったこと:
  - Claude in Chrome の許可は「この操作だけ許可」と「このサイトでは常に許可」である。個人のプランでは、サイトの拒否リストを作れない
  - 内蔵ブラウザの Cookie は Code のセッションではアプリを閉じると消える
- 設計への影響: 「常に許可」を出さないことは所有者の前提に置き、Claude の振る舞いの決まりを CLAUDE.md に書く

## 比べた案

| 案 | 中身 | 良い点 | 弱い点 | 結果 |
|---|---|---|---|---|
| 同じユーザーの管理者ターミナル(強化) | Claude が書ける設定を読まないスクリプトで、6桁を入れて切り替える | 所有者の手順が短い。PCの CLI を使える | Claude が意図して Windows の設定に細工すると防げない | 採る(例外を要件に書いた) |
| CloudShell | マネジメントコンソールで切り替えて CloudShell を使う | 鍵がPCに来ない | 所有者の求める速さに合わない | 採らない |
| Windows の別のユーザー | 変更の作業を別の管理者アカウントで行う | ユーザーの境界で守れる | アカウントが増え、所有者の管理が増える | 採らない(所有者の判断) |
| 本番専用の GitHub アカウント | 本番の起動と承認を別のアカウントに寄せる | ブラウザの道も仕組みで止まる | アカウントが増える | 採らない(所有者の判断) |
| ワークフローの冒頭で起動者を確かめる | ボットが起動したら失敗させる | 変更が小さい | 実行は作られる | 採らない |

## 決めたこと

### 止める場所を AWS と GitHub の側に置く
- 背景: Issue は書き方によらず止めることを求める。Claude Code の禁止の一覧とフックは文字の並びしか見ない
- 選んだ形: Claude の手が届く鍵(所有者の普段の `aws login` の鍵、Claude の GitHub の鍵、所有者の GitHub の鍵)から、本番を変える権限そのものを外す
- 理由: 権限の判定は AWS と GitHub が行うので、Claude がどんなプログラムからどう呼んでも結果が同じになる
- 引き換え: 鍵の作り直しが、所有者の最初の1回の作業になる

### IAM の運用者の権限は手作業で作る
- 背景: IAM ユーザー `keirekipro` と GitHub Actions のロールは、手作業で作られており、terraform の管理の外にある
- 選んだ形: 変更用ロールとポリシーの JSON をリポジトリに置き、所有者が最初の1回にコマンドで作る
- 理由: 所有者自身の権限を、GitHub Actions のロールに変えさせない。既存の運用者の権限の作り方と揃える

## 残る危険と手当て
- Claude が所有者のPCの Windows の設定に意図して細工すると、管理者ターミナルの鍵を奪える: 要件3の例外として受け入れた。スクリプトは Claude が書ける設定を読まない作りにし、事故で起きる道は塞ぐ
- `aws login` で新しくサインインした直後の60秒: 要件1の7で受け入れた。変更用ロールの権限から IAM の変更を外し、渡っても権限を広げられないようにする
- 所有者が Claude in Chrome に「常に許可」を出すと、ブラウザの道が開く: 所有者の前提として手順書に書く
- GitHub のワークフローが本番の AWS に入るときの権限: この spec の範囲の外で、#557 で扱う

## 参考
- [IAM の条件キー](https://docs.aws.amazon.com/IAM/latest/UserGuide/reference_policies_condition-keys.html)
- [MFA で API を守る](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_credentials_mfa_configure-api-require.html)
- [aws login](https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-sign-in.html)
- [AssumeRole](https://docs.aws.amazon.com/STS/latest/APIReference/API_AssumeRole.html)
- [ReadOnlyAccess](https://docs.aws.amazon.com/aws-managed-policy/latest/reference/ReadOnlyAccess.html)
- [PowerUserAccess](https://docs.aws.amazon.com/aws-managed-policy/latest/reference/PowerUserAccess.html)
- [UAC の仕組み](https://learn.microsoft.com/en-us/windows/security/application-security/application-control/user-account-control/how-it-works)
- [Windows のセキュリティのサービス基準](https://www.microsoft.com/en-us/msrc/windows-security-servicing-criteria)
- [整合性レベル](https://learn.microsoft.com/en-us/windows/win32/secauthz/mandatory-integrity-control)
- [Claude Code の sandbox](https://code.claude.com/docs/en/sandboxing)
- [個人アクセストークン](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/managing-your-personal-access-tokens)
- [GitHub App に要る権限](https://docs.github.com/en/rest/authentication/permissions-required-for-github-apps)
- [インストールトークン](https://docs.github.com/en/apps/creating-github-apps/authenticating-with-a-github-app/generating-an-installation-access-token-for-a-github-app)
- [ワークフローの実行の API](https://docs.github.com/en/rest/actions/workflow-runs)
- [ワークフローを起こすイベント](https://docs.github.com/en/actions/writing-workflows/choosing-when-your-workflow-runs/triggering-a-workflow)
- [Claude in Chrome の権限](https://support.claude.com/en/articles/12902446-claude-in-chrome-permissions-guide)
- [Claude Desktop のブラウザ](https://claude.com/docs/third-party/claude-desktop/browser)
