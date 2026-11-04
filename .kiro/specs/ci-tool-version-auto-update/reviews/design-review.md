## サイクル1 往復1(2026-11-03)

### 審査の範囲

範囲: 全体

### 申告

**1. 開発環境のイメージの公開日時を、Docker Hub の `tag_last_pushed` で、`FROM` の digest がタグの今の digest と同じときだけ数える** — design.md「lib-ci-tool-releases.sh」の `ci_tool_age_check`、「失敗したときの扱い」の「配布元がタグを公開し直したとき」

- Issue の記載: なし(「Node.js と Terraform は、開発環境と CI の版が揃って上がる」「72時間経ったあとに届く」だけ)
- 決めたこと: タグの公開し直しで digest が変わると、開いている更新の PR の公開からの時間の検査は失敗し、公開し直したタグが72時間経つ週まで、週1回の実行はその PR を書き換えない。書き換えるたびに `dismiss_stale_reviews_on_push` で所有者の承認が外れる
- 他にありえた選択肢: digest が違っても、そのタグが初めて見えた日時(過去の実行の記録)で数える。開発環境の版の検査では版の公開日時だけを数え、イメージは digest の照合だけにする。Node.js のイメージを公開し直しの少ない形(digest を固定しない、など)にする
- 外れていた場合: Node.js の公式イメージは同じ版のタグが公開し直される(research.md では公開の7日後)。main が動くたびに `update-pr-branches.yaml` がブランチを更新して検査が流れ直すので、承認待ちの Node.js の更新の PR が、1〜2週のあいだ赤のまま残り、承認をやり直すことが繰り返し起きうる

**2. 新しい検査を、既存の必須の検査 `dependency-cooldown` と `escape-hatch` のステップにする** — design.md「全体の構成」の図のあとの段落

- Issue の記載: なし
- 決めたこと: 公開からの時間の検査と、PR で変わった CI の版の署名の確認を `dependency-cooldown` に、版の書き場所の検査を `escape-hatch` に足す。必須の検査の一覧と ruleset は変えない
- 他にありえた選択肢: 新しいワークフローの新しい必須の検査にする(一覧と ruleset の変更を所有者に提案する)
- 外れていた場合: `dependency-cooldown` は、ジョブの条件で fork からの PR では動かず、スキップは成功として報告される。そのため、fork からの PR が4つの道具の版を変えても、公開からの時間の検査と署名の確認は動かない(所有者の承認だけが残る)。設計の本文はこのことを書いていない。要件5の1は、どの PR でも72時間経っていない版を止めると書いている

**3. 開いている更新の PR を、`origin/main` から作り直して force-push で書き換える** — design.md「ci-tool-version-update.sh」の呼び出し方

- Issue の記載: なし
- 決めたこと: 書き換えのたびにブランチを作り直し、`--force-with-lease` で push し、`gh pr edit` で題名と本文を書き換える
- 他にありえた選択肢: 開いている PR は閉じて新しい PR を作る。ブランチにコミットを積む
- 外れていた場合: 書き換えのたびに所有者の承認が外れる。所有者が承認したあと、マージの前に月曜日の実行が来ると、承認をやり直すことになる

**4. 版の書き場所を `.github/ci-tool-versions.json` にまとめ、`trusted-signers.json` の `locations` を消して、ci-tool-fast-update のスキルの読む先を替える** — design.md「ci-tool-fast-update のスキルと trusted-signers.json」

- Issue の記載: なし
- 決めたこと: 書き場所の一覧を1つのファイルにし、spec `security-fix-cooldown-exception` で作ったスキルの手順(Step 4)を書き換える
- 他にありえた選択肢: `locations` を残し、新しいファイルと `locations` の食い違いを版の書き場所の検査で止める
- 外れていた場合: 既存のスキルの手順が変わる。新しいファイルの形を変えるときに、スキルも同時に直す必要が残る

**5. 版を上げる道具に Renovate を使わず、このリポジトリのスクリプトで作る** — design.md「プロジェクトの決まりを守っているか」の新しいライブラリの追加、research.md「構成の案の比べ」

- Issue の記載: なし
- 決めたこと: 版の一覧の取得、版の選び、書き換え、PR の作成と書き換えを、bash のスクリプトとして作り、保守する
- 他にありえた選択肢: Renovate を自分のワークフローで動かし、72時間の待ちと開発環境のそろえは別の検査で補う
- 外れていた場合: 配布元の API の変更(design.md「設計を見直すきっかけ」)に、このリポジトリが自分で追従し続けることになる

**6. 週1回の実行の失敗を、`audit-issue.sh` の新しい種類 `ci-tool-update` の「判定不能」の Issue で知らせ、成功した実行でその Issue を閉じる。スクリプトのテストの失敗も失敗として知らせる** — design.md「ci-tool-version-update.yaml」「audit-issue.sh の種類 ci-tool-update」

- Issue の記載: なし(要件8で「ほかの監査の知らせと同じ形」)
- 決めたこと: 失敗の知らせを監査の Issue の仕組みに載せ、次に成功した実行で自動で閉じる
- 他にありえた選択肢: 失敗ごとに新しい Issue を作る。成功しても自動では閉じない
- 外れていた場合: 失敗が一時的なものなら、所有者が読む前に Issue が閉じることがある

### 指摘

| ID | レベル | 該当箇所 | 内容 | 直し方の案 |
|---|---|---|---|---|
| D1-1-1 | 中 | design.md「処理の流れ」の図の `A` と図のあとの1つ目と2つ目の箇条、「lib-ci-tool-releases.sh」の `ci_tool_age_check` | 週1回の実行は、「72時間経っていない」ことと「配布元から日時や digest を取れなかった」ことを分けていない。`ci_tool_age_check` は、どちらでも `ng` を出して 1 で終わり、図では `A` が「いいえ」なら `E`(PR を作らない)に進む。図のあとの箇条も、V を選ぶときのイメージのタグの確認で「条件を満たさない版は飛ばし」、T のタグの確認で「経っていなければ、その週は PR を作らない」とだけ書き、Docker Hub の問い合わせの失敗やタグが無いとき(404)の扱いを書いていない。このままだと、問い合わせが失敗した週や、配布元が `-bookworm-slim` のタグを出さなくなったときに、更新の PR も知らせも出ないまま止まる。要件8の1の「ある道具の新しい版を調べられなかったこと」の知らせが出ない。「失敗したときの扱い」の節は「`lib-ci-tool-releases.sh` が1になり…その道具だけを失敗にして」と書くが、`ctr_age_ok` も 1 で終わるので、どちらの 1 かを週1回の実行が分けられない | V を選ぶとき、T を確かめるとき、`A` の判定のそれぞれで、取れなかったとき(`ci_tool_age_check` の公開日時の欄が `-` の行、`ctr_image` と `ctr_published` の失敗、タグが無いこと)は、その道具を「新しい版を調べられなかった」の失敗にすると書く。終了コードか出力の欄で、まだ72時間経っていないことと取れなかったことを分ける形を `ci_tool_age_check` の呼び出し方に足す。結合テストに、イメージのタグの問い合わせが失敗した場合と、`A` の問い合わせが失敗した場合を足す |
| D1-1-2 | 中 | design.md「check-ci-tool-release-age.sh」の使う部品と呼び出し方 | このスクリプトは、`github.event.pull_request.base.sha`(イベントの時点の main の先頭)と head を直接比べる。main が進んだあとに古い main から作ったブランチで PR を出すと、main だけで変わった版(たとえば、マージ済みの更新の PR が上げた Node.js の版)が、「head で古い版に変わった」ように見える。CI の版は古い版なので通るが、開発環境の版は、head の `FROM` の古い digest がタグの今の digest と違えば `ng` になり、版を変えていない PR の `dependency-cooldown` が赤になる。要件5の5(4つの道具の版を変えない PR は止まらない)に反する。既存の `check-dependency-additions.sh` は `git merge-base` で PR 自身の変更だけを見ている。また、設計の取り方(`git fetch --depth=1 origin <base>` と深さ1の head の checkout)では merge-base を求められない | 比べる相手を、base と head の merge-base にすると書く。merge-base の求め方(`fetch-depth: 0` で checkout するか、`gh api repos/<リポジトリ>/compare/<base>...<head>` の `merge_base_commit.sha` を使う)を書く。単体テストに、main だけで版が変わった場合に止まらないことを足す |
| D1-1-3 | 中 | design.md「lib-ci-tool-versions.sh」の `civ_scan` の3種類の行 | 要件6の1は、ワークフローとアクションに直接書いた道具の版を「すべて」調べ、「道具を入れるコマンドに書いた版」も道具の版に当たるとする。`civ_scan` が見つけるのは、名前に `version` を含む行、`docker` の行のイメージのタグ、パッケージの管理の道具の `@版` と `==版` だけである。`curl` `wget` `gh release download` で配布元の URL の版(`.../releases/download/v1.2.3/...`)から入れる行、`apt-get install <名前>=<版>` の行、`tag:` や `release:` のような名前でアクションに渡す版は見つからない。今後こうした書き方で道具を足すと、版の書き場所の検査は通り、Issue の「自動で上がる対象に入っていないとき、そのことに気づける」が満たされない。設計は、見つけない書き方を「作らないもの」にも書いていないので、所有者は範囲が狭まったことを読み取れない。あわせて、`docker run -p 8080:80` の `8080:80` は「`<イメージ>:<タグ>` でタグが数字で始まる語」に当たり、誤って版の行と読まれる | 見つける行に、配布物を取るコマンド(`curl` `wget` `gh release download` など)の行の URL に含まれる版と、`apt-get install` などの `<名前>=<版>` を足す。どうしても見つけられない書き方が残るなら、その書き方と理由を「作らないもの」に書き、所有者が範囲を判断できるようにする。`docker` の行の語は、`-p` `-v` などの引数を除き、イメージの位置の語だけを読むと書く |
| D1-1-4 | 中 | design.md「移行」の Terraform の箇条(「`terraform-plan.yaml` がすでに 1.17.1 で plan を流していることを確かめる」)、research.md「今の版の書き場所」の Terraform | `terraform-plan.yaml` は plan を流していない。このワークフローのジョブ `terraform-static` は、開発環境のイメージで `fmt -check`、`validate`(`init -backend=false`)、tflint、checkov を流すだけで、本番の状態を読まない(`terraform-plan.yaml` 37〜39行目と `terraform-apply.yaml` 5〜6行目のコメント)。本番の状態との差分を新しい版で初めて出すのは `terraform-apply.yaml` で、同じジョブの中で plan のすぐあとに `apply -auto-approve` が動く。設計は、本番に適用する版を 1.9.0 から一度に8つのマイナー版上げる最初の PR について、所有者が承認の前に確かめる材料として、存在しない plan を挙げている。所有者は、新しい版で本番の状態を確かめ済みと誤って受け取り、元に戻しにくい変更を承認することになる | 「移行」の文を事実に合わせる。`terraform-plan.yaml` が 1.17.1 で確かめているのは書式・構文・静的な検査だけで、本番の状態に対する plan は、マージのあとに `terraform-apply.yaml` を動かしたときに初めて流れ、そのまま適用まで進むことを書く。そのうえで、所有者が承認の前と適用の前に確かめること(変更点の文書と上げ方の文書を読むことなど)を書き直す |
| D1-1-5 | 低 | design.md「移行」の「最初の実行では、次の2つの更新の PR が届く見込みである」 | Codex CLI の CI の版は 0.147.0 で、research.md によれば最新は 0.166 系である。最初の実行では Codex CLI の更新の PR も届く(Trivy も、新しい版があれば届く)。所有者が最初の週に届く PR の数を読み違える | Codex CLI(と、調べたうえで Trivy)の見込みも書く |
| D1-1-6 | 低 | design.md「ci-tool-version-update.sh」の本文の6(`## 承認`) | 本文は、どの PR にも「この PR は `.github/` を変えるので、所有者の承認が済むまでマージされない」と書く。開発環境の版だけをそろえる PR は `.github/` を変えず、承認を求めるのは `dependency-gate` の新しい検知である。本文の理由が事実と違う | 開発環境の版だけをそろえる PR では、承認を求めるのが `dependency-gate` であると書き分ける |
| D1-1-7 | 低 | design.md「使う既存の仕組み」の最後の段落、「設計を見直すきっかけ」の1つ目 | 依存の向きを「2つのライブラリがデータのファイルを読む一方向に限る」と書くが、図では `check-dependency-additions.sh` もデータのファイルを直接読み(`DG --> DATA`)、版の書き場所の検査は `inventory-targets.json` も読む。見直しのきっかけは、同じ形を読む場所を「4か所」とし、`check-dependency-additions.sh` を数えていない。形を変えたときに承認の検知だけが古い形のまま残るおそれがある | 依存の向きの文に、`check-dependency-additions.sh` がデータのファイルの `dev` を読むことを足し、見直しのきっかけの数え上げにも入れる |
| D1-1-8 | 低 | design.md「check-ci-tool-release-age.sh」の使う部品 | `lib-ci-tool-versions.sh` の関数は `<根のフォルダ>` を受け取るが、このスクリプトは base のファイルを `git show <base>:<ファイル>` で読むと書く。base の版を、どの形でライブラリに渡すのか(一時のフォルダに写すのか)が書かれていない。head のデータのファイルにあって base に無いファイルの扱いも書かれていない | base のファイルを一時の根のフォルダに写してから関数に渡すこと、base に無いファイルは版の変更として扱うことを書く |
| D1-1-9 | 低 | design.md「lib-ci-tool-releases.sh」の Trivy の取り先 | `repos/aquasecurity/trivy/releases` は既定で30件しか返さないが、ページをたどるかどうかが書かれていない。今の版から30件より多く離れたときに、要件2の3のあいだの版の変更点の文書のリンクが欠ける | `--paginate` でたどるか、今の版より古い版に届いたら止めることを書く |
| D1-1-10 | 低 | design.md「ファイルの構成」の `dependency-review.yaml` と `guardrails.yaml`、「テストの方針」の前置き | `cooldown` に足す「2本のテスト」と `escape-hatch` に足す「3本のテスト」がどのファイルかが書かれていない。また、手元のテストは alpine のコンテナで流すと書くが、結合テストと公開からの時間の検査のテストは `git` を使うので、`.github/CLAUDE.md` の形(`apk add bash jq`)のままでは流れない | どのジョブでどのテストを流すかを名指しする。手元のテストのコンテナに `git` を足すことを書く |
| D1-1-11 | 低 | design.md「プロジェクトの決まりを守っているか」の「使う外部の機能がこのリポジトリで使えるか」 | 「bot の PAT での push と PR の作成は、今の `frontend-vuln-fix.yaml` が同じ条件で動かしている」とあるが、`frontend-vuln-fix.yaml` はワークフローのファイルを変えるコミットを push しない。ワークフローのファイルを変える push に要る `workflow` の scope は、research.md では `doc/開発フロー/基盤構築手順.md` の記載から読んだもので、実際に push して確かめたものではない | 根拠を「基盤構築手順.md の記載で、実際の push では確かめていない」と正しく書くか、確かめた日と方法を書く |

### 前の段階への指摘

なし

- 往復: 1回目 / 高0 中4 低7

## サイクル1 往復2(2026-11-03)

### 審査の範囲

範囲: 差分

- design.md「処理の流れ」の図と図のあとの箇条(D1-1-1 の修正): 「取れなかった」の分かれ道を足したので、同じ判定を書く `lib-ci-tool-releases.sh` の `ci_tool_age_check` と「失敗したとき」、`ci-tool-version-update.sh` の「失敗したとき」、「失敗したときの扱い」の1つ目、「テストの方針」の単体テストと結合テスト、requirements.md の要件8の1を読み、食い違いが無いかを確かめた
- design.md「lib-ci-tool-versions.sh」の `civ_scan`(D1-1-3 の修正): 見つける行を広げたので、見つけた行を書き換える `civ_rewrite_ci`、見つけた行を照らす `check-ci-tool-placement.sh`、「データの形」の `excluded` と `keys` とその下の説明、「作らないもの」の新しい箇条、requirements.md の要件6の1と6の6を読んだ。あわせて、今の `.github/workflows/` と `.github/actions/` を、広げた名前の条件と、`curl` `wget` `gh release download` `apt-get install` `docker run` の語で検索し、新しく当たる行が無いことと、`terraform-plan.yaml` と `guardrails.yaml` の `docker run` の行がイメージの位置の語の決まりで正しく読めることを確かめた
- design.md「check-ci-tool-release-age.sh」の役割と使う部品と呼び出し方(D1-1-2 と D1-1-8 の修正): 比べる相手を分かれ目のコミットに変え、一時の根のフォルダに写すことと分かれ目に無いファイルの扱いを足したので、`lib-ci-tool-versions.sh` の「失敗したとき」(データのファイルが無いときの終了コード)、このスクリプトの終了コードと「外部に問い合わせずに 0 で終わる」の箇条、「性能」の2つ目、「テストの方針」の単体テスト、`dependency-review.yaml` のジョブ `cooldown` の checkout と権限、`check-dependency-additions.sh` の merge-base の求め方、requirements.md の要件5の5を読んだ
- design.md「移行」の Terraform の箇条(D1-1-4 の修正): `terraform-plan.yaml` と `terraform-apply.yaml` を読み、書いた事実(静的な検査だけであること、`workflow_dispatch` と production environment の承認のあとに plan と `apply -auto-approve` が同じジョブで動くこと)が合っているかを確かめた
- design.md「全体の構成」の図のあとの段落: ジョブ `cooldown` が検査の一覧に `dependency-cooldown` の名前で出るという文を足したので、`dependency-review.yaml` の `name:` を確かめた
- 「作らないもの」「使う既存の仕組み」「プロジェクトの決まりを守っているか」「PR で変わった CI の版の署名の確認」「ci-tool-fast-update のスキル」「データの形」の前置き「失敗したときの扱い」の2つ目と3つ目「テストの方針」の前置き「安全」「性能」の1つ目の書き換え: 書き方の点検で文を分けたり主語を足したりした箇所で、直す前の文と読み比べ、意味が変わっていないことを確かめた。ほかの節に影響は無い

### 申告

**1. 配布元のイメージのタグが無いことを、その道具の「新しい版を調べられなかった」の失敗にする** — design.md「処理の流れ」の図のあとの4つ目の箇条

- Issue の記載: なし(要件4の2は、イメージも公開から72時間経っていることを条件にするだけで、タグが無いときの扱いを決めていない)
- 決めたこと: 版の公開から72時間経った版のタグを問い合わせて 404 なら、その版を飛ばさずに道具ごと失敗にし、知らせの Issue を作る
- 他にありえた選択肢: タグが無い版は、タグが72時間経っていない版と同じく飛ばし、1つ前の版を確かめる。タグが無い状態が何週か続いたときだけ失敗にする
- 外れていた場合: Docker の公式イメージは、配布元が短い間隔で2つの版を出すと、あいだの版のイメージを作らないことがある。そのときは、あいだの版のタグが無いまま、その週の週1回の実行が失敗し、知らせの Issue が作られる。新しいほうの版が72時間経つ週の実行が成功すれば Issue は閉じるが、所有者は、直す必要の無い知らせを読むことになる

### 指摘

| ID | レベル | 該当箇所 | 内容 | 直し方の案 |
|---|---|---|---|---|
| D1-2-1 | 中 | design.md「check-ci-tool-release-age.sh」の使う部品の2つ目の段落(「データのファイルと、データのファイルの `ci` と `dev` のファイルを…一時の根のフォルダに写して」「分かれ目に無いファイルは、空のファイルとして扱う」) | このスクリプトは、分かれ目のデータのファイル `ci-tool-versions.json` も一時の根のフォルダに写し、分かれ目に無いファイルは空のファイルとして扱う。一方で、`lib-ci-tool-versions.sh` の「失敗したとき」は、データのファイルが無いか JSON として読めないときに、どの関数も 2 で終わると書き、このスクリプトの終了コードも、データのファイルを読めないときは 2 とする。この spec の PR では、分かれ目(今の main)にデータのファイルがまだ無いので、新しく足すステップが 2 で終わり、この spec の PR の `dependency-cooldown` が赤になる。spec のマージの前に main から分けて、マージのあとも main に合わせられていない PR(ぶつかって `update-pr-branches.yaml` が更新できない PR など)も、版を変えていないのに同じく赤になり、要件5の5に反する。「テストの方針」の単体テストにも、分かれ目にデータのファイルが無い場合が無い | 分かれ目にデータのファイルが無いときの扱いを決めて書く。たとえば、分かれ目にデータのファイルが無いときは、head のデータのファイルを分かれ目の根のフォルダにも写し、同じ書き場所の一覧で分かれ目の版を読む。単体テストに、分かれ目にデータのファイルが無く、4つの道具の版を変えない PR が通る場合を足す。`check-dependency-additions.sh` の検知の追加も、base と head の `ci-tool-versions.json` の `dev` を読むので、この spec の PR で同じことが起きないかをあわせて確かめる |
| D1-2-2 | 中 | design.md「lib-ci-tool-versions.sh」の `civ_scan` の2つ目の種類(`docker` の行のイメージの位置の語) | D1-1-3 の修正で、`docker` の行は、`-` で始まる引数と、名指しした14の引数の次の語を飛ばし、残った最初の語だけをイメージの位置の語として読むようにした。名指しした引数のほかにも、次の語を値に取る引数は多い。たとえば `--platform`(`.github/CLAUDE.md` の手順も使う)、`--env-file`、`-l` と `--label`、`-m` と `--memory`、`--cpus`、`-h` と `--hostname`、`--add-host`、`--cap-add`、`--pull`、`--ulimit`、`--tmpfs`、`--device` である。`docker run --platform linux/amd64 node:24.22.1 ...` では、残った最初の語は `linux/amd64` になり、イメージのタグの版が見つからない。直す前は行の中の `<イメージ>:<タグ>` の形の語をすべて見つけていたので、この書き方は、修正で新しく見落とすようになった。見落としは検査が通るだけで表に出ないので、要件6の1の「すべて調べる」と、Issue の「自動で上がる対象に入っていないとき、そのことに気づける」が、こうした書き方では満たされない | 見落としを作らない向きの決まりにする。たとえば、行の中の `<イメージ>:<タグ>` の形の語をすべて見つけ、そのうち、値に `:` を含む引数(`-p` `--publish` `-v` `--volume` `--mount` `--add-host` `-e` `--env` `--device` `--tmpfs` `--expose` `--link` `--security-opt` など)の値だけを除く。読み違えたときは版の書き場所の検査が赤になって表に出るので、見落とすより安全である。単体テストに、`--platform` を付けた `docker run` のイメージのタグを見つける場合を足す |
| D1-2-3 | 低 | design.md「lib-ci-tool-versions.sh」の `civ_rewrite_ci` | `civ_scan` が見つける行に、`apt-get install <パッケージ>=<版>` と、`curl` `wget` `gh release download` の URL の版を足した。版の書き場所の検査は、4つの道具の `keys` に当たる名前の行を `ci` に足すよう求めるので、こうした行が `ci` に入ることがある。`civ_rewrite_ci` は「値を囲む引用符は残す」としか書いておらず、URL の区切りの先頭の `v` を残すことと、URL のファイル名の中の同じ版(`trivy_0.74.0_Linux-64bit.tar.gz` など)も書き換えるかが書かれていない。区切りの版だけを書き換えると、取る配布物の URL が壊れる。今のワークフローにこうした行は無いので、今の実装には影響しない | `civ_rewrite_ci` が、`civ_scan` の種類ごとに、どの文字を書き換え、何を残すかを書く。URL の版は書き換えの対象にしない(`excluded` に入れるよう案内する)と決めるのでもよい |
| D1-2-4 | 低 | design.md「check-ci-tool-release-age.sh」の呼び出し方の最後の箇条、「性能」の2つ目、「テストの方針」の `test-check-ci-tool-release-age.sh` の1つ目 | D1-1-2 の修正で、このスクリプトは、どの PR でも、`gh api repos/<リポジトリ>/compare/...` と `git fetch` で分かれ目のコミットを取ってから版を比べる。それでも、「4つの道具の版が1つも変わらない PR では、このスクリプトは外部に問い合わせずに 0 で終わる」の文と、同じ趣旨のテストの文が残っている。ここでの外部が配布元の API を指すことが読み取れず、テストの偽の `gh` が compare の応答を返す必要があることも書かれていない。また、compare の問い合わせが失敗したときの終了コードが書かれていない | 「外部」を「配布元」と書き直す。compare の問い合わせが失敗したときは、版の変更を判定できないので止める(終了コード)ことを書く |
| D1-2-5 | 低 | design.md「check-ci-tool-release-age.sh」の呼び出し方の「変わった版の見つけ方」 | 「分かれ目の版と head の版が違う行を、CI の版の変更とする」と書くが、分かれ目と head とで行をどう対応させるか(行番号か、ファイルと名前の組か)が書かれていない。行番号で対応させると、版の行より上に行を足しただけの PR で、変わっていない版を変更と読み、配布元への問い合わせと署名の確認が動く | ファイルと名前の組ごとに、分かれ目の版の集まりと head の版の集まりを比べる、と書く |

### 前の段階への指摘

なし

- 往復: 2回目 / 高0 中2 低3

## サイクル1 往復3(2026-11-03)

### 審査の範囲

範囲: 差分

- design.md「check-ci-tool-release-age.sh」の使う部品の2つ目と3つ目の段落と「変わった版の見つけ方」(D1-2-1 の修正): 分かれ目の版を head のデータのファイルの書き場所で読むようにしたので、`lib-ci-tool-versions.sh` の `civ_tool_versions` と `civ_dev_from` と「失敗したとき」(一時の根のフォルダに写した head のデータのファイルで関数が動くか)、このスクリプトの終了コードの箇条、「テストの方針」の `test-check-ci-tool-release-age.sh`、「安全」の最後の箇条(head のデータのファイルを読むことですり抜けが増えないか)、版の書き場所の検査の `keys` の決まり、`dependency-review.yaml` のジョブ `cooldown` の checkout(PR の head を取る)、`update-pr-branches.yaml` の冒頭の説明(ブランチを main に合わせる仕組み)を読んだ
- design.md「check-dependency-additions.sh の検知の追加」の役割(D1-2-1 の修正): head のデータのファイルの `dev` だけを読むようにしたので、`dependency-gate.yaml` の checkout(PR の head、`fetch-depth: 0`)と、今の `check-dependency-additions.sh` の merge-base の求め方、「テストの方針」の既存のテストに足す場合を読んだ
- design.md「lib-ci-tool-versions.sh」の `civ_scan` の2つ目の種類(D1-2-2 の修正): 行の中の `<イメージ>:<タグ>` の語をすべて読む決まりに替えたので、「データの形」の `excluded` とその下の説明(この spec が main に入った時点で見つける行が8つであること)と、「テストの方針」の `test-lib-ci-tool-versions.sh` を読んだ。あわせて、今の `.github/workflows/` と `.github/actions/` の `docker run` の行と `image:` `container:` の行を検索し、新しい決まりで `guardrails.yaml` の2つのイメージのタグだけが見つかり、`-v "$PWD:/repo"` などの値が除かれることを確かめた
- design.md「dependabot.yml の除外」の段落の書き換え: `.github/dependabot.yml` の docker の `"*"` の `semver-major` の除外を読み、書いた事実が合っていることを確かめた
- 「概要」「作らないもの」の digest の説明、`ci_tool_age_check` の最後の文の削除、`ci-tool-version-update.sh` の呼び出し方と本文の4、「棚卸しの対象と取り方 npm の追加」、「性能」、「移行」の Terraform の箇条の書き換え: 書き方の点検で主語を足したり文をまとめたりした箇所で、直す前の文と読み比べた。`ci_tool_age_check` から消した「週1回の実行は、結果の欄を読んで分ける」の文は、「処理の流れ」の図のあとの最後の箇条に同じ中身があるので、意味は失われていない。「性能」から消した版の書き場所の検査の文は、`check-ci-tool-placement.sh` の役割に同じ中身がある。ほかの節に影響は無い

### 申告

なし(この往復の差分で、新しく申告に当たる決定は無い)

### 指摘

| ID | レベル | 該当箇所 | 内容 | 直し方の案 |
|---|---|---|---|---|
| D1-3-1 | 低 | design.md「check-ci-tool-release-age.sh」の使う部品の3つ目の段落(「この spec の PR と、この spec が main に入る前に main から分けたブランチの PR では、分かれ目にデータのファイルが無い」) | 理由の2つ目の場合は、この修正では救われない。main の ruleset はブランチが main に合っていることを求め、`update-pr-branches.yaml` は main が進むたびに開いている PR のブランチを main に合わせる。合わせたあとのブランチの分かれ目は、データのファイルを持つ main のコミットになる。合わせていないブランチでは、ジョブ `cooldown` が checkout する PR の head に、データのファイルもこのスクリプトも無いので、分かれ目のデータのファイルを読まなくても、このステップは失敗する(合わせれば直る)。修正で救われるのはこの spec の PR だけで、設計の決めたこと自体は正しい。実装には影響しない | 理由を、この spec の PR では分かれ目にデータのファイルが無いため、と書き直す。古い main から分けたブランチの PR は、`update-pr-branches.yaml` が main に合わせたあとに検査が流れ直して通る、と書き添えるのでもよい |

### 前の段階への指摘

なし

- 往復: 3回で収束 / 未解決: 0件
