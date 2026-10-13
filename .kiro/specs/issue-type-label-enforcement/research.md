# 調査と設計の判断の記録

## まとめ

- spec: `issue-type-label-enforcement`
- 調査の種類: 既存の仕組みへの追加(Claude の起票の手順、Claude のフック、GitHub Actions のワークフロー)
- 主な結論:
  - GitHub のラベルの作成・名前の変更・削除の API は、ワークフローの `github.token` に `issues: write` を与えれば呼べる。シークレットは要らない
  - `gh issue create` は、`--label` を何度でも書け、1つの `--label` にカンマ区切りで複数のラベルを書ける。起票を止めるフックは、この2つの書き方を両方読む必要がある
  - ラベルの一覧のファイルは、フック(perl の JSON::PP で読む)とワークフローのスクリプトの両方が読むので、JSON で書く。既製のアクションは YAML のファイルを前提にするため使わない

## 調べたこと

### GitHub のラベルの API と権限

- きっかけ: ワークフローが GitHub のラベルを作り、直し、消すための権限とトークンを決めるため
- 調べたもの:
  - https://docs.github.com/en/rest/issues/labels
  - https://docs.github.com/en/rest/authentication/permissions-required-for-fine-grained-personal-access-tokens
  - https://docs.github.com/en/issues/using-labels-and-milestones-to-track-work/managing-labels
- 分かったこと:
  - `POST /repos/{owner}/{repo}/labels`(作成)、`PATCH /repos/{owner}/{repo}/labels/{name}`(説明・色・名前の変更)、`DELETE /repos/{owner}/{repo}/labels/{name}`(削除)は、権限「Issues」の write で呼べる(「Pull requests」の write でも呼べる)
  - `PATCH` の引数は `new_name`・`color`・`description`。`color` は先頭の `#` を付けない6桁の16進数。`description` は100文字まで
  - 公式の説明書に「Deleting a label will remove the label from issues and pull requests.」とある。消したラベルは、付いていた Issue と PR から外れる
  - 名前を変えたときに Issue と PR からラベルが外れないことは、公式の説明書に明記が無い。`PATCH` は同じラベルの名前を書き換える操作であり、ラベルを消して作り直す操作ではない
  - 名前に `/` や空白を含むラベルは、経路の中で `%2F` や `%20` に符号化すれば読める。`gh api "repos/kubernetes/kubernetes/labels/kind%2Fbug"` と `gh api "repos/DogisRiki/KeirekiPro/labels/good%20first%20issue"` が、それぞれのラベルを返すことを 2026-10-13 に確かめた
- 設計への影響: ワークフローの権限は `contents: read` と `issues: write` に限り、`github.token` で動かす。スクリプトは、ラベルの名前を経路に入れるときに必ず符号化する

### `gh issue create` のラベルの受け取り方

- きっかけ: 起票を止めるフックが、コマンドのどこからラベルを読むかを決めるため
- 調べたもの: `cli/cli` の `pkg/cmd/issue/create/create.go`(2026-10-13 に GitHub の API で読んだ。手元の gh は 2.102.0)
- 分かったこと:
  - ラベルは `cmd.Flags().StringSliceVarP(&opts.Labels, "label", "l", nil, ...)` で受け取る。使い方の例に `gh issue create --label "bug,help wanted"` と `gh issue create --label bug --label "help wanted"` がある。`-l` と `--label` を何度でも書け、1つの値にカンマ区切りで複数を書ける
  - `--template` はテンプレートの本文を使う。`--recover` は失敗した起票の入力を読み直す。`--web` はブラウザで起票する。`--editor` はエディタを開く。どれも、コマンドに書かれていないラベルが付くか、Claude が対話できない形である
  - `-R` / `--repo` で、起票する先のリポジトリを変えられる
- 追記(2026-10-13): `create.go` の `Aliases: []string{"new"}` で、`gh issue new` が `gh issue create` の別名であることを確かめた
- 設計への影響: フックは、`-l` / `--label` の値をカンマで分けて数える。フックは `gh issue new` も起票として扱う。`--template` `--recover` `--web` `--editor` を含む起票は、ラベルを確かめられない形として止める

### Claude Code のフック

- きっかけ: 起票の前に止める仕組みの置き場所を決めるため
- 調べたもの: 既存のフック `.claude/hooks/block-full-test-in-implementer.sh`(#556)と `.claude/hooks/protect-main.sh`、`.claude/settings.json` の `PreToolUse` の登録。フックの入力の欄は https://code.claude.com/docs/en/hooks の「Common input fields」
- 分かったこと:
  - `PreToolUse` の `Bash` のフックは、メインのセッションとサブエージェントのどちらの Bash のコマンドでも、実行の前に呼ばれる。終了コード2で終わると実行が止まり、標準エラーの文が Claude に渡る
  - フックの入力には、セッションの作業フォルダ(`cwd`)が入る。`protect-main.sh` は、この `cwd` でリポジトリを見分けている
  - `block-full-test-in-implementer.sh` は、perl の `Text::ParseWords` でコマンドを `&&` `||` `;` `|` 改行で区切り、`sh -c '...'` の中も読む。同じ作りで、`gh issue create` を見つけられる
  - Claude Desktop で worktree のセッションを開くと、本体の作業フォルダのフックが使われることがある(anthropics/claude-code#99145)。フックがファイルを、フック自身の置き場所からたどって読むと、本体の作業フォルダの古いファイルを読むおそれがある
- 設計への影響: 起票を止めるフックは、新しい `PreToolUse` の `Bash` のフックとして足す。ラベルの一覧のファイルは、フックの置き場所ではなく、入力の `cwd` のリポジトリの最上位から読む

### ラベルを合わせる既製のアクション

- きっかけ: ファイルのとおりに GitHub のラベルを合わせる部分を、自分で作るか既製のものを使うかを決めるため
- 調べたもの: `crazy-max/ghaction-github-labeler` の README(2026-10-13 に GitHub の API で読んだ)
- 分かったこと: ラベルを YAML のファイル(既定は `.github/labels.yml`)に書き、`from_name` で名前を変え、`skip-delete` で削除を止め、`dry-run` で変更を試せる
- 設計への影響: 下の「既製のアクションを使わず、スクリプトを自分で作る」の判断を参照

### 世の中のラベルの付け方

- きっかけ: 所有者が、ラベルの名前を英語にそろえる前に、ほかのリポジトリの付け方を知りたいと言ったため
- 調べたもの: `gh label list` で、kubernetes/kubernetes、rust-lang/rust、facebook/react、microsoft/vscode、golang/go、vercel/next.js のラベルを読んだ(2026-10-13)。GitHub の「Issue の種類」の機能は https://docs.github.com/en/issues/tracking-your-work-with-issues/configuring-issues/managing-issue-types-in-an-organization
- 分かったこと:
  - Kubernetes は、種類を `kind/bug` `kind/feature` `kind/cleanup` `kind/documentation` `kind/dependency` など、場所を `area/...` で表す。rust-lang/rust は `C-`(種類)と `A-`(場所)、facebook/react は `Type: ...` を使う。どれも英語だけで名前を付けている
  - GitHub の「Issue の種類」の機能の説明書には、組織での設定方法だけが書かれている。このリポジトリの持ち主は個人である(`gh api repos/DogisRiki/KeirekiPro --jq .owner.type` が `User` を返す)
- 設計への影響: 所有者は、Kubernetes の付け方(`kind/` と `area/`)を選んだ(requirements の「元の要望」の「決めた方式」)。Issue の種類の機能は使わず、ラベルで表す

### 今のラベルと、ラベルを作る既存の仕組み

- きっかけ: ファイルに書くラベルの初めの値と、ファイルとずれるおそれのある仕組みを確かめるため
- 調べたもの: `gh label list`、`.github/scripts/audit-issue.sh`、`.github/scripts/container-scan-issue.sh`、`.github/workflows/guardrails.yaml`、`.claude/skills/review-loop/SKILL.md`、`.claude/skills/retrospective/SKILL.md`、`.github/scripts/collect-inventory.sh`
- 分かったこと:
  - 監査の通知(`audit`)、脆弱性の通知(`container-vuln`)、データベースの形を変えるPR(`migration`)、Codex の指摘を退けたPR(`codex-overruled`)、振り返り(`retrospective`)のラベルは、それぞれのスクリプトと手順が、ラベルが無いときだけ `gh label create` で作る
  - `retrospective` のラベルは、今の GitHub に無い(`gh api repos/DogisRiki/KeirekiPro/labels/retrospective` が 404 を返す)。振り返りの手順で起票したことが無いためである
  - Dependabot が付ける `dependencies` `java` `javascript` `python` `docker` `github_actions` を読む仕組みは、このリポジトリに無い
- 設計への影響: これらのラベルは、今の説明と色のままファイルに書く。ラベルが無いときだけ作る既存の仕組みは、ファイルと同じ名前のラベルがあれば何もしないので、ファイルとずれない。振り返りの手順だけは、この spec で起票の手順を直すので、ラベルを作る手順を外す

## 比べた案

| 案 | 中身 | よい点 | 難点 |
|---|---|---|---|
| A. 自分で作るスクリプト | JSON のファイルを読み、gh の API でラベルを合わせるスクリプトを `.github/scripts/` に置く | フックと同じファイルを読める。既存のスクリプトと同じく、gh を偽物に置き換えたテストを書ける。外部のアクションを足さない | 名前の変更や削除の処理を自分で書いて試す必要がある |
| B. `crazy-max/ghaction-github-labeler` | YAML のファイルを読んでラベルを合わせるアクションを使う | 名前の変更・削除・試しの実行が初めからある | フックは perl の標準の部品で動かす決まりで、YAML を読めない。ファイルが2つになる。外部のアクションを足すと、SHA の固定と公開からの待ち時間の検査の対象が増える |
| C. フックは使わず、スキルの文だけで守らせる | 起票の手順にラベルを付けるよう書くだけにする | 作るものが少ない | Claude が手順を読み飛ばすと止まらない。要件の「Claude の判断によらず止まる」を満たさない |

## 設計の判断

### 判断: 既製のアクションを使わず、スクリプトを自分で作る

- きっかけ: ラベルの一覧のファイルを、ワークフローと起票を止めるフックの両方が読む必要がある
- 比べた案: 上の表の A と B
- 選んだ案: A。`.github/scripts/sync-labels.sh` が JSON のファイルを読み、gh の API でラベルを合わせる
- 理由: ファイルを1つにできる。既存のスクリプト(`close-linked-issues.sh` など)と同じ作りとテストのしかたで作れる。外部のアクションを増やさない
- 引き換えにするもの: 名前の変更と削除の処理を自分で書く。誤って全部を消さないための検証もスクリプトに持たせる
- あとで確かめること: 名前を変えたラベルが、付いていた Issue から外れないこと(公式の説明書に明記が無い)

### 判断: ラベルの一覧のファイルを `.github/labels.json` に置く

- きっかけ: ファイルを書き換えると、GitHub のラベルが消えることがあり、消したラベルは戻らない。また、起票を止めるフックはこのファイルで判定する
- 比べた案: 1. `.github/` の下に置く 2. リポジトリの最上位や `doc/` の下に置く
- 選んだ案: 1
- 理由: `.github/` の下は CODEOWNERS で守られ、所有者が承認するまでマージされない。ラベルを消す変更を、所有者が見ないまま自動でマージさせない。また、Claude が自分の作業のブランチでファイルを書き換えて、起票を止める判定を緩めることを防ぐ
- 引き換えにするもの: Claude は `.github/` の下に書き込めない設定なので、ファイルの変更は、Claude が作った内容を所有者が写す手間がかかる

### 判断: ファイルの各ラベルに組(`group`)を書き、フックは名前の頭ではなく組で判定する

- きっかけ: 所有者は、ラベルの決め方がこれからも変わると考えている
- 選んだ案: 各ラベルに `group`(`kind` / `area` / `other`)を書く。フックは `group` が `kind` のラベルを種類のラベル、`area` のラベルを場所のラベルとして扱う
- 理由: 名前の頭(`kind/` `area/`)で判定すると、名前の付け方を変えたときにフックも直す必要がある。組で判定すれば、ファイルを書き換えるだけで済む

### 判断: 種類のラベルごとに、場所のラベルが要るかどうかと選ぶときの決まりをファイルに書く

- きっかけ: 所有者は、振り返りの Issue のように、種類と場所の2つを付けない Issue がこれからも増えると考えている。また、ラベルの名前や意味を、スクリプトや手順に直接書かない形を求めた(requirements の要件3の受入基準3、要件4の受入基準4)
- 比べた案: 1. 場所のラベルを要らない種類の名前を、フックと手順に書く 2. ファイルの種類のラベルごとに `area_required`(真偽値)と `selection_rule`(文)を書く
- 選んだ案: 2
- 理由: 場所のラベルを要らない種類を足すときも、選ぶときの決まりを変えるときも、ファイルを書き換えるだけで、フックと手順を直さずに済む。フックはラベルの名前を持たず、`group` と `area_required` だけで判定する
- 引き換えにするもの: 選ぶときの決まりは、GitHub の画面の説明(100文字まで)とは別の欄になる。GitHub の画面では、選ぶときの決まりは見えない

### 判断: 名前を変える前の名前を、ファイルの各ラベルに残す

- きっかけ: 要件で、名前を変えたラベルを、どの実行でも消さずに名前だけを変えることを求めている
- 選んだ案: 各ラベルに `previous_names`(前の名前の配列)を書く。スクリプトは、新しい名前のラベルが GitHub に無く、前の名前のラベルがあれば、そのラベルの名前を変える。前の名前は、ファイルに無いラベルとして消さない
- 理由: どの実行でも、ファイルだけを見て名前の変更と見分けられる。前の実行が途中で失敗していても、次の実行が同じ結果にたどり着く

## 残るおそれと手当て

- 名前を変えたラベルが Issue から外れるおそれ: 公式の説明書に明記が無い。手当て: 実装のときに、所有者の了承を得た使い捨てのリポジトリで、名前を変えたあともラベルが Issue に付いていることを確かめる
- ファイルの誤りで多くのラベルが消えるおそれ: 手当て: スクリプトは、ファイルを検証してから API を呼ぶ。検証は PR の時点(guardrails)でも流し、誤りのあるファイルを main に入れない
- フックの読み取りをすり抜けて起票されるおそれ(コマンドの書き方の工夫や、gh 以外の手段): 手当て: フックは、`gh api` で Issue を作るコマンドも止める。`curl` などで GitHub の API を直接呼ぶ起票は、フックでは止めない。Claude の起票の手順はどれも `gh issue create` を使うので、手順のとおりに動く限りフックを通る
- 本体の作業フォルダの古いファイルを読むおそれ: 手当て: フックは入力の `cwd` のリポジトリからファイルを読む

## 参考

- https://docs.github.com/en/rest/issues/labels — ラベルの API の引数
- https://docs.github.com/en/rest/authentication/permissions-required-for-fine-grained-personal-access-tokens — ラベルの API に要る権限
- https://docs.github.com/en/issues/using-labels-and-milestones-to-track-work/managing-labels — ラベルを消したときに Issue と PR から外れること
- https://code.claude.com/docs/en/hooks — フックの入力の欄と終了コード
- https://github.com/cli/cli/blob/trunk/pkg/cmd/issue/create/create.go — `gh issue create` のラベルの受け取り方
- https://github.com/crazy-max/ghaction-github-labeler — 比べた既製のアクション
