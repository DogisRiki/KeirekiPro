## サイクル1 往復1(2026-10-13)

### 審査の範囲

範囲: 全体

### 申告

**1. フックは、起票するセッションの作業フォルダにある `.github/labels.json` で判定する** — design.md 部品「check-issue-labels.sh」の「ラベルの一覧のファイルを読む場所」

- Issue の記載: なし。requirements 要件4の受入基準4は「そのときのラベルの一覧のファイル」とだけ書き、どこのファイルかは design に任せた(requirements の往復1の R1-1-4)
- 決めたこと: フックは、入力の `cwd` のリポジトリの最上位の `.github/labels.json` を読む。main のファイルや GitHub のラベルは見ない
- 他にありえた選択肢: `origin/main` のファイル(`git show origin/main:.github/labels.json`)で判定する。GitHub のラベルの一覧を API で読んで判定する
- 外れていた場合: このPRのマージより前に作ったブランチや worktree で作業しているセッションは、ファイルが無いので起票がすべて止まる(要件4の受入基準5のとおりの動きだが、所有者には理由が分かりにくい)。ラベルを書き換える途中のブランチでは、GitHub にまだ無いラベルをフックが通し、gh の起票が失敗する

**2. 「このPRのマージ前に、使い捨てのリポジトリで、名前を変えたラベルが Issue から外れないことを確かめる」** — design.md テストの方針「名前の変更の確かめ(マージの前)」

- Issue の記載: なし
- 決めたこと: Claude が、所有者の了承を得て使い捨てのリポジトリを作り、ラベルを付けた Issue を作って `PATCH` で名前を変え、ラベルが付いたままかを確かめる。外れたらマージせずに設計を見直す
- 他にありえた選択肢: このリポジトリで一時的なラベルを作って確かめる。GitHub の画面での名前の変更と同じ操作であることを根拠に、確かめを省く
- 外れていた場合: リポジトリの作成は、CLAUDE.md の「リポジトリ外部へのデータ送信」として所有者の承認が要る作業で、tasks に所有者の手作業が1つ増える。所有者が了承しなければ、マージ前の確かめができず進め方が止まる

**3. `gh api` で Issue を作るコマンドは、ラベルと宛先に関係なくすべて止め、`gh issue create -R <ほかのリポジトリ>` は調べずに通す** — design.md 部品「check-issue-labels.sh」の「止める決まり」1・2

- Issue の記載: なし。requirements 要件4はほかのリポジトリへの起票を挙げていない(requirements の往復1の R1-1-5)
- 決めたこと: `gh api` での起票は、`--label` に当たる引数があっても、宛先がほかのリポジトリでも止める。`gh issue create` に `-R` / `--repo` でこのリポジトリ以外を指定したときは止めない
- 他にありえた選択肢: `gh api` の起票も `labels[]` の引数を読んで判定する。ほかのリポジトリへの起票も止める
- 外れていた場合: ほかのリポジトリへの起票の扱いが所有者の考えと違う。影響は、ほかのリポジトリに起票する場面に限られる

**4. フックのテストは CI に足さず、手で流す** — design.md テストの方針の末尾

- Issue の記載: なし
- 決めたこと: `test-check-issue-labels.sh` は、ほかのフックのテストと同じく、コンテナの中か Git Bash で手で流す。`test-sync-labels.sh` は `guardrails.yaml` の `escape-hatch` で流す
- 他にありえた選択肢: `test-check-issue-labels.sh` も `escape-hatch` の手順に足す
- 外れていた場合: 要件4の「Claude の判断によらず止まる」を担うフックが、あとの変更で壊れても、PR の検査では見つからない

**5. GitHub に前の名前と新しい名前のラベルが両方あるときは、何も変えずに終了コード1で終え、付け替えは所有者が画面で行う** — design.md 部品「sync-labels.sh」の合わせ込みの決まり2

- Issue の記載: なし。requirements では扱いを決めず design に任せた(requirements の往復2の R1-2-1)
- 決めたこと: スクリプトは前の名前のラベルを変えず消さず、所有者に、Issue と PR を新しい名前に付け替えてから前の名前のラベルを画面で消すよう文で示し、失敗として終わる
- 他にありえた選択肢: スクリプトが、前の名前のラベルが付いた Issue と PR に新しい名前のラベルを付けてから、前の名前のラベルを消す
- 外れていた場合: この状態になるたびに、所有者が手で付け替える作業が生じ、それまでワークフローは失敗し続ける

### 指摘

| ID | レベル | 該当箇所 | 内容 | 直し方の案 |
|---|---|---|---|---|
| D1-1-1 | 中 | design.md 部品「sync-labels.sh」の合わせ込みの決まり1・3と「失敗したとき」、テストの方針の「名前の変更」 | 決まり3の「GitHub に無いものは `POST` で作る」が、最初に読んだ GitHub のラベルで判定するのか、名前の変更のあとの状態で判定するのかが書かれていない。「失敗したとき」は、書き込みが失敗しても残りの書き込みを続けると定めている。そのため、決まり1で `bug` から `kind/bug` への名前の変更(`PATCH`)が失敗すると、同じ実行の決まり3で `kind/bug` が「GitHub に無い」として新しく作られる。次の実行からは `bug` と `kind/bug` が両方あるので、決まり2のとおり名前を変えられず、今 `bug` が付いている Issue に `kind/bug` が付かないまま、所有者の手での付け替えが要る状態になる。これは、requirements 要件2の受入基準3(main に入ったときの実行が失敗しても、どの実行でも名前だけを変え、付いていた Issue と PR にラベルが残る)に反する。テストの方針にこの場合が無いので、実装とテストを終えても気づかれない | 決まり3に「その実行で名前の変更の対象にしたラベル(変更が失敗したものを含む)は作らない」と書き足す。テストの方針の「名前の変更」に、「`bug` の名前の変更が失敗したとき、`kind/bug` を作らず、終了コード1で終わり、次の実行で名前を変えること」を足す |
| D1-1-2 | 低 | design.md 部品「check-issue-labels.sh」の「コマンドの読み方」、テストの方針の「通す形」 | 語の頭の `$(` と `` ` `` は外すが、語の末尾の `)` と `` ` `` を外すことが書かれていない。`url=$(gh issue create --title x --body-file f --label kind/bug --label area/app)` では、最後の語が `area/app)` になり、場所のラベルが0と数えられて、ラベルのそろった起票が止まる。file-issue は「起票したIssueの番号は、gh issue create が出力するURLから取る」と書いており、この形は使われうる。また、`url=$(gh` の語は「先頭の `NAME=value` の形の語を飛ばす」に当たり、`gh` ごと飛ばされうる。テストの方針は、この形を「止める形」にだけ挙げている | 語の末尾の `)` と `` ` `` も外すこと、`NAME=$(` の形の語は `NAME=` と `$(` を外した残りを読むことを書く。「通す形」に、ラベルのそろった `url=$(gh issue create ... --label kind/bug --label area/app)` を足す |
| D1-1-3 | 低 | design.md 部品「check-issue-labels.sh」の「コマンドの読み方」 | `gh issue create` には別名 `gh issue new` がある(`cli/cli` の `pkg/cmd/issue/create/create.go` の `Aliases` で確かめられる)。フックは `issue` に続く語が `create` のときだけを起票とみなすので、`gh issue new` はラベル無しでも止まらない。起票の手順はどれも `gh issue create` を使うので、影響は手順を外れたときに限られる | `create.go` の `Aliases` を確かめ、別名があれば `create` と同じく起票とみなすと書き、テストの「止める形」に足す |
| D1-1-4 | 低 | design.md 部品「check-issue-labels.sh」の「コマンドの読み方」の `gh api` の箇条 | `-f` などのフィールドの引数があれば Issue を作るコマンドとみなすので、`gh api repos/o/r/issues -X GET -f state=open` のような一覧の読み取りも止まる。止めた理由は「Issue は `gh issue create` で `--label` を付けて起票する」となり、Claude が読み取りを止められた理由を取り違えうる | `-X` / `--method` に `POST` 以外が指定されているときは Issue を作るコマンドとみなさない、と書く |
| D1-1-5 | 低 | design.md 部品「guardrails.yaml の手順」 | 足す2つの手順を、ジョブ `escape-hatch` のどこに置くかが書かれていない。`guardrails.yaml` は、所有者の承認とは関係の無い検査を、承認待ちで失敗する手順(`Run escape hatch check`)より前に置くよう注記している。後ろに置くと、`.github/` を変える PR(このPRと、これからのラベルの変更の PR のすべて)では、承認までファイルの検証が一度も動かない | 2つの手順を `Check owner approval` より前(既存の `Test close linked issues` のあと)に置くと書く |

### 前の段階への指摘

| ID | 対象 | 該当箇所 | 内容 |
|---|---|---|---|
| D1-1-6 | requirements | 要件3の受入基準2 | 2つ以上の種類に当てはまりそうなときの選び方を、本文の「どうなれば解決か」に書かれた一番の目的で決めるとしている。振り返りの手順(`/retrospective`)の Issue の本文は「事象」「すり抜けたゲート」「強化案」の様式で、「どうなれば解決か」の節が無い。実装の途中で小さく分けた Issue の本文も、元の本文からの抜き出しなので、この節を含まないことがある。design は振り返りでも起票の決まりのラベルの選び方の節を使うとしているが、そのときに何を基準に選ぶかが決まっていない。ラベルはあとで付け替えられるので、影響は種類の選び方がぶれることに留まる |

- 往復: 1回目 / 高0 中1 低4

## サイクル2 往復1(2026-10-13)

### 審査の範囲

範囲: 差分

- design.md の差分の行すべて(概要、作るもの・作らないもの、設計を見直すきっかけ、部品「labels.json」「sync-labels.sh」「sync-labels.yaml」「guardrails.yaml の手順」「check-issue-labels.sh」「file-issue の直し」「start の直し」「retrospective の直し」、データの形、失敗したときの扱い、テストの方針、安全、移行): 差分そのものの審査のため
- requirements.md 要件1の受入基準1・2、要件3の受入基準2・3・5、要件4の受入基準3・4: 差分の語「area_required」「selection_rule」「retrospective」「困っていること」で検索した。足した欄と決まりが、承認済みの受入基準(種類のラベルごとの場所のラベルの要否、選ぶときの決まりをファイルから読むこと、振り返りの起票に `retrospective` を付けること)を満たすかを見た
- design.md 部品「sync-labels.sh」の合わせ込みの決まり1・2・4と「失敗したとき」、処理の流れの図: 差分で直した決まり3(名前を変える対象のラベルを作らない)が、ほかの決まりの判定(最初に読んだラベルでの判定、削除の対象)と食い違わないかを見た
- design.md 部品「check-issue-labels.sh」の「コマンドの読み方」の区切りの文と「失敗したとき」: 差分で直した語の読み方が、写し元の `.claude/hooks/block-full-test-in-implementer.sh` の区切りの作り(`parse_line` と `shellwords`)の上で成り立つかを、その実ファイルで確かめた
- `.github/workflows/guardrails.yaml` の `escape-hatch` の手順: 差分で書いた置き場所(`Test close linked issues` のあと、`Check owner approval` の前)と、承認待ちの手順 `Run escape hatch check` が実ファイルにあるかを確かめた
- `.claude/skills/file-issue/SKILL.md`、`.claude/skills/start/SKILL.md`、`.claude/skills/retrospective/SKILL.md`: 差分の「手順にラベルの名前を書かない」と grep の確かめが、design が残すと書いた行や、手順の今の本文と両立するかを、実ファイルで確かめた
- `.github/scripts/collect-inventory.sh` と `doc/開発フロー/監査手順.md`: 差分で足した「作らないもの」と「設計を見直すきっかけ」の `retrospective` の名前の扱いが、実ファイルの数え方と合うかを確かめた

### 申告

**1. 振り返りの手順はラベルの名前を書かず、ファイルの `selection_rule` を読んで `retrospective` を選ぶ** — design.md 部品「retrospective の直し」

- Issue の記載: あり。「決めた方式」に「振り返りの Issue に付ける `retrospective` は、種類のラベルの1つにする」「選ぶときの決まりを変えるときは、ファイルだけを書き換える」とある。振り返りの手順にラベルの名前を書くかどうかは書かれていない(requirements の R3-2-1)
- 決めたこと: 振り返りの手順の起票のコマンドを `gh issue create --label <種類のラベル> [--label <場所のラベル>] ...` にし、`retrospective` の名前を書かない。Claude は起票の決まりのラベルの選び方の節に従い、ファイルの `selection_rule` から `retrospective` を選ぶ
- 他にありえた選択肢: 振り返りの手順に `--label retrospective` を名指しで残す
- 外れていた場合: 振り返りの Issue に `retrospective` 以外の種類のラベルが付くと、月次の棚卸し(`collect-inventory.sh`)の振り返りの件数から漏れる。起票のあとに付けたラベルを所有者に示すので、所有者が気づける

**2. 月次の棚卸しのスクリプト `collect-inventory.sh` を変えず、`retrospective` の名前で数え続ける** — design.md「作らないもの」と「設計を見直すきっかけ」

- Issue の記載: なし
- 決めたこと: `collect-inventory.sh` は名前 `retrospective` で振り返りの Issue を数えたままにする。所有者がファイルでこの名前を変えるときを、設計を見直すきっかけに挙げる
- 他にありえた選択肢: 棚卸しのスクリプトが `.github/labels.json` を読んで振り返りのラベルを見つける形にする
- 外れていた場合: 所有者がファイルで `retrospective` の名前を変えると、ワークフローは名前を変えるが、棚卸しは「ラベルが存在しない」として0件と報告し続ける。`doc/開発フロー/監査手順.md` の半期の見直しの `gh issue list --label retrospective` も同じく空になる

### 指摘

| ID | レベル | 該当箇所 | 内容 | 直し方の案 |
|---|---|---|---|---|
| D2-1-1 | 低 | design.md 部品「retrospective の直し」、部品「file-issue の直し」のラベルの選び方の2つ目の箇条 | 「retrospective の直し」は、`retrospective` の `selection_rule` が振り返りの Issue を指すので Claude は `retrospective` を付ける、としている。しかし `selection_rule` の文は「振り返りの手順(/retrospective)で起票する Issue にだけ付ける」で、ほかの Issue に付けないことは言うが、振り返りの Issue に必ず付けることは言っていない。振り返りの Issue(ゲートを足す提案)が `kind/feature` や `kind/enhancement` にも当たりそうに見えたとき、ラベルの選び方の節の決め方は「どうなれば解決か」「やりたいこと」「困っていること」の一番の目的で選ぶとするが、振り返りの本文は「事象」「すり抜けたゲート」「強化案」の様式で、3つの節のどれも無い。そのため、requirements 要件3の受入基準5の3つ目の箇条(振り返りの起票では `retrospective` を付ける)が、Claude の読み方に頼っている。起票のあとに付けたラベルを所有者に示すので、外れても所有者が気づける | ラベルの選び方の節に、ラベルの名前によらない決まりとして「`selection_rule` が今の起票の手順を名指ししているラベルがあれば、そのラベルを選ぶ」(または「`selection_rule` に当たるラベルを、`selection_rule` の無いラベルより先に選ぶ」)を足す |
| D2-1-2 | 低 | design.md テストの方針「手順の確かめ」、部品「file-issue の直し」の最後の箇条、部品「retrospective の直し」 | 「手順の確かめ」は、起票の決まり・着手の手順・振り返りの手順の本文に `retrospective` が例のほかに書かれていないことを grep で確かめるとする。一方、「file-issue の直し」は、`.claude/skills/file-issue/SKILL.md` の18行目「監査の通知(定期実行が起票する `audit`)と振り返り(`retrospective`)のIssueは対象外」を残すとしている。また `.claude/skills/retrospective/SKILL.md` は見出しが `# retrospective`(手順の名前)である。どちらも grep に当たるので、確かめのとおりに作ると、残すと決めた行と手順の名前の見出しを書き換えることになり、design のほかの節と食い違う | 「手順の確かめ」の対象を、起票のコマンドの `--label` の値と、ラベルを選ぶ決まりの文に限ると書く。または、file-issue の18行目の `retrospective` と、手順の名前(見出しと `/retrospective`)を除くと書く |

### 前の段階への指摘

なし

- 往復: 1回で収束 / 未解決: 0件
