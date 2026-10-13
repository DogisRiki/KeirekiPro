# タスク

- [x] 1. 名前を変えたラベルが Issue に付いたまま残ることを確かめる

  /kiro-impl を動かしているセッション(以下、親のセッション)は、所有者の了承を得てから、使い捨ての非公開のリポジトリを1つ作り、ラベル `bug` を付けた Issue を1つ作る。親のセッションは、`gh api -X PATCH "repos/<owner>/<repo>/labels/bug" -f new_name=kind/bug` でラベルの名前を変え、`gh issue view <番号> --json labels` でその Issue のラベルを読む。続けて、`gh api "repos/<owner>/<repo>/labels/kind%2Fbug"` が名前を変えたラベルを返すことと、`DELETE` で `good%20first%20issue` の形の符号化した名前のラベルを消せることも確かめる。確かめたあと、親のセッションは、所有者に使い捨てのリポジトリを消すよう頼む。
  - 完了の確かめ方: 名前を変えたあとの `gh issue view` の `labels` に `kind/bug` があり、`bug` が無い。結果を「実装のメモ」に記録してある。`kind/bug` が Issue から外れていたら、親のセッションはこのあとのタスクに進まずに止まり、design の「名前の変更の確かめ」のとおり、所有者に設計の見直しを伝える
  - 受入基準とテストの対応: 要件2の受入基準3のうち、名前を変えたラベルが付いていた Issue に付いたまま残ることは、この確かめで確かめる。GitHub の動きなので、スクリプトのテストでは確かめられない
  - _要件: 2.3_

- [x] 2. ラベルの一覧のファイルを作る

  Claude は、部品「labels.json」を、scratchpad の `place-1/.github/labels.json` に作る。中身は design の labels.json の節と「データの形」の節のとおりにする。そのほかのラベルの説明と色は、作るときに `gh label list --limit 100 --json name,description,color` で読んだ今の GitHub の値を写す。種類のラベルと場所のラベルの説明・場所のラベルが要るかどうか・選ぶときの決まりは、requirements の要件1(ラベルの一覧を1つのファイルに書く)の表の文と値を文字を変えずに写す。
  - 完了の確かめ方: `perl -MJSON::PP` で読める。`kind` の組が7つ、`area` の組が3つ、`other` の組が13個で、名前が design の labels.json の節と一致する。`duplicate` など6つの名前が、名前の欄にも `previous_names` にも無い。`kind/bug`・`kind/enhancement`・`kind/documentation` の `previous_names` が、それぞれ `bug`・`enhancement`・`documentation` である。Claude は、requirements の要件1の種類のラベルの表と場所のラベルの表から、ラベルごとの意味の文・場所のラベルが要るかどうか・選ぶときの決まりを取り出し、ファイルの `description`・`area_required`・`selection_rule` と1字ずつ比べる小さな perl の照合を scratchpad で流し、食い違いが0件である。そのほかのラベルの `description` と `color` は、`gh label list` の値と比べて食い違いが0件である
  - 受入基準とテストの対応: 要件1の受入基準1から6(ラベルをすべて1つのファイルに名前・説明・色・組とともに書くこと、最初に書く種類のラベル7つ・場所のラベル3つ・そのほかのラベル13個、`bug`・`enhancement`・`documentation` の名前を変えること、`duplicate` など6つを書かないこと)は、タスク3.1で作るテストの「リポジトリの labels.json が検証に通る」と、上の完了の確かめ方の照合で確かめる
  - _要件: 1.1, 1.2, 1.3, 1.4, 1.5, 1.6_
  - _対象の部品: labels.json_

- [ ] 3. ラベルを合わせるスクリプトを作る
- [x] 3.1 ファイルの検証を作る

  Claude は、部品「sync-labels.sh」のうち、引数の読み取りと `--check` の検証を、scratchpad の `place-1/.github/scripts/sync-labels.sh` に作る。あわせて、テスト `place-1/.github/scripts/tests/test-sync-labels.sh` に、design の「検証の決まり」の場合ごとのテストと、タスク2のファイルを検証に通すテストを作る。テストは gh を偽物に置き換え、偽物が呼ばれた回数を記録する。
  - 完了の確かめ方: alpine のコンテナに `place-1/.github` を写し(ホストに jq が無いため)、`chmod -R a-x` したうえで `bash .github/scripts/tests/test-sync-labels.sh` が失敗0件で終わる。`bash .github/scripts/sync-labels.sh --check` が、タスク2のファイルで終了コード0を返す
  - 受入基準とテストの対応: 要件2の受入基準5(ファイルを読めないときやラベルが無いときは何も変えずに失敗する)は、テストの「ファイルが無い」「JSON でない」「labels が空」「kind が無い」「area_required が true の種類があるのに area が無い」「色に # が付いている」「説明が101文字」「名前と前の名前が重なる」「種類のラベルに area_required が無い」「種類でないラベルに area_required がある」「selection_rule が空」の各場合で、終了コード2で終わり、偽物の gh が1回も呼ばれないことで確かめる。要件1の受入基準1(ラベルをすべて1つのファイルに、名前・説明・色・組とともに書く)は、テストの「リポジトリの labels.json が検証に通る」で確かめる
  - _要件: 1.1, 2.5_
  - _対象の部品: sync-labels.sh_

- [x] 3.2 GitHub のラベルの合わせ込みを作る

  Claude は、部品「sync-labels.sh」の合わせ込みの決まり(名前の変更、前の名前と新しい名前の食い違い、作成と直し、削除)と、失敗したときの扱いを作り、テストに場合を足す。偽物の gh は、`GET` に決めたラベルの一覧を返し、`POST`・`PATCH`・`DELETE` の呼び出しを経路と引数ごとに記録する。
  - 完了の確かめ方: alpine のコンテナに `place-1/.github` を写し、`chmod -R a-x` したうえで `bash .github/scripts/tests/test-sync-labels.sh` が失敗0件で終わる。shellcheck を、CI と同じく `git ls-files -z '*.sh'` の全ファイルに、scratchpad の `sync-labels.sh` とテストを `-v` で本来のパスに重ね、その2つのパスも引数に足して渡し、指摘が0件である(まだリポジトリに無いファイルは `git ls-files` に出ないため)
  - 受入基準とテストの対応: 要件2の受入基準1(ファイルにあって GitHub に無いラベルを作り、説明か色が違うラベルを直す)は、テストの「GitHub に無いラベルを作る」「説明か色が違うラベルを直す」で確かめる。受入基準2(所有者が GitHub の画面で手で足したラベルも、ファイルに無ければ消す)は「ファイルに無いラベルを消す」で確かめる。受入基準3(古い名前と新しい名前を書いたラベルは、消して作り直さずに名前だけを変える)は「前の名前のラベルだけがあるときは名前を変えて消さない」「両方あるときは変えず消さず1で終わる」「名前の変更が失敗しても同じ実行で新しい名前のラベルを作らない」「2回目の実行は何も書き込まない」で確かめる。受入基準4(消したラベルは、付いていた Issue と PR から外れる)は「ファイルに無いラベルに DELETE を呼ぶ」で確かめる(外れることは GitHub の動きで、公式の説明書にある)。受入基準6(ワークフローが失敗として終わったら、所有者が Actions の画面で失敗を見られる)は「書き込みの1件が失敗しても残りを続けて1で終わる」「ラベルを読めないときは書き込まずに1で終わる」で確かめる。あわせて、「経路の名前を符号化する(`kind%2Fbug`、`good%20first%20issue`)」「送る欄が name・description・color だけである」のテストを作る
  - _要件: 2.1, 2.2, 2.3, 2.4, 2.6_
  - _対象の部品: sync-labels.sh_

- [ ] 4. ワークフローと PR の検査にスクリプトをつなぐ
- [x] 4.1 ラベルを合わせるワークフローを作る

  Claude は、部品「sync-labels.yaml」を、scratchpad の `place-1/.github/workflows/sync-labels.yaml` に、design の節のとおりの起動するイベント・動かす条件・権限・同時実行・時間の上限・手順で作る。`actions/checkout` は、`guardrails.yaml` と同じコミットの SHA で固定する。
  - 完了の確かめ方: actionlint(`rhysd/actionlint:1.7.12`)を、scratchpad の `place-1/.github/workflows/` を重ねたリポジトリに対して流し、指摘が0件である。`sync-labels.yaml` の `uses:` の行が、`guardrails.yaml` の `actions/checkout` の行と同じ文字列(`@` のあとの40桁のコミットの SHA と、そのあとの `# <版>` のコメント)であることを、`grep -nE 'uses:'` の出力を2つのファイルで比べて確かめる(`check-action-pinning.sh` は `git ls-files` で対象を集めるので、まだリポジトリに無いファイルを見ない)。`permissions` が `contents: read` と `issues: write` の2つだけである
  - 受入基準とテストの対応: 要件2の受入基準1(main に入ったら合わせる)と受入基準7(手で動かせる)は、ワークフローを自動のテストで確かめられないので、actionlint と、マージのあとの初めての実行(「実装のメモ」の、マージのあとの確かめ)で確かめる。受入基準6(ワークフローが失敗として終わったら、所有者が Actions の画面で失敗を見られる)は、ワークフローの手順が `|| true` などでスクリプトの終了コードを握りつぶしておらず、スクリプトが0以外で終わったときにジョブが失敗することを、Claude が読んで確かめる
  - _要件: 2.1, 2.6, 2.7_
  - _対象の部品: sync-labels.yaml_

- [x] 4.2 PR の検査にファイルの検証を足す

  Claude は、部品「guardrails.yaml の手順」を、scratchpad の `place-1/.github/workflows/guardrails.yaml`(今のファイルの写し)に作る。ジョブ `escape-hatch` の `Test close linked issues` のあと、`Check owner approval` の前に、`test-sync-labels.sh` を流す手順と `sync-labels.sh --check` を流す手順の2つを足す。
  - 完了の確かめ方: `git diff --no-index` で今の `guardrails.yaml` と写しを比べたとき、違いが足した2つの手順だけである。actionlint の指摘が0件である
  - 受入基準とテストの対応: 要件2の受入基準5のうち、誤ったファイルを main に入れないことは、この手順が流す `sync-labels.sh --check` のテスト(タスク3.1)で確かめる
  - _要件: 2.5_
  - _対象の部品: guardrails.yaml の手順_

- [ ] 5. ラベルが足りない起票を止める
- [x] 5.1 起票を止めるフックを作る (並行可)

  Claude は、部品「check-issue-labels.sh」を、scratchpad の `place-2/.claude/hooks/check-issue-labels.sh` に、design の「コマンドの読み方」「止める決まり」「ラベルの一覧のファイルを読む場所」「止めたときに出す文」のとおりに作る。あわせて、テスト `place-2/.claude/hooks/tests/test-check-issue-labels.sh` を作る。テストは、一時フォルダに git のリポジトリを作って `origin` を設定し、`.github/labels.json` を置き、フックの入力の `cwd` にそのフォルダを渡す。
  - 完了の確かめ方: Git Bash で `bash <place-2>/.claude/hooks/tests/test-check-issue-labels.sh` が失敗0件で終わる。テストの後片付けで一時フォルダが消えている。shellcheck を、3.2 と同じく全 `.sh` に、scratchpad のフックとテストを `-v` で本来のパスに重ね、その2つのパスも引数に足して渡し、指摘が0件である
  - 受入基準とテストの対応: 要件4の受入基準1(種類のラベルを付けない起票は止まり、理由と種類のラベルの一覧が示される)は「ラベル無しを止める」「gh issue new のラベル無しを止める」「url=$(gh issue create ...) のラベル無しを止める」「sh -c の中のラベル無しを止める」で確かめる。受入基準2(種類のラベルを2つ以上付けた起票は止まる)は「種類のラベルのカンマ区切りの2つを止める」「--label の重ね書きの2つを止める」で確かめる。受入基準3(場所のラベルが要る種類のラベルを付けて場所のラベルを付けない起票は止まり、要らない種類のラベルなら止まらない)は「area_required が true の種類で場所のラベル無しを止める」「area_required が false の種類だけの起票を通す」で確かめる。受入基準4(起票を止める判定は、そのときのラベルの一覧のファイルのとおりに変わる)は「kind/test を足したファイルで kind/test の起票を通す」「kind/bug の area_required を false に変えたファイルで場所のラベル無しの起票を通す」で確かめる。受入基準5(ラベルの一覧のファイルを読めなければ起票は止まる)は「ファイルが無いときに止める」「ファイルが壊れているときに止める」で確かめる。受入基準6(定期実行のワークフローが作る Issue、所有者が作る Issue、PR は止めない)は「-R でほかのリポジトリへの起票を通す」で確かめる(定期実行と所有者の端末の起票は、Claude の Bash のフックを通らないのでテストを持たない)。受入基準7(すでにある Issue のラベルの付け替えは止めない)は「gh issue edit --add-label を通す」で確かめる。あわせて、「種類のラベル1つと場所のラベル1つを付けた起票を通す」「場所のラベル2つを付けた起票を通す」「ラベルの大文字と小文字の違いを通す」「--label=kind/bug の形を通す」「url=$(gh issue create ... --label kind/bug --label area/app) を通す」「gh issue list を通す」「gh api で Issue を作るコマンドを止める」「gh api の -X GET の読み取りを通す」「--web と --template を止める」「止めたときの文に種類のラベルの一覧と場所のラベルの一覧が出る」「入力が JSON でないときに通す」のテストを作る
  - _要件: 4.1, 4.2, 4.3, 4.4, 4.5, 4.6, 4.7_
  - _対象の部品: check-issue-labels.sh_
  - _依存: 2_

- [x] 5.2 フックを Claude の設定に登録する

  Claude は、`.claude/settings.json` の写しを scratchpad の `place-2/.claude/settings.json` に作り、`PreToolUse` の `matcher: "Bash"` のフックの一覧の最後に、`check-issue-labels.sh` を時間の上限15秒で足す。
  - 完了の確かめ方: `git diff --no-index` で今の `settings.json` と写しを比べたとき、違いがフックの1件の追加だけである。写しが `perl -MJSON::PP` で読める
  - 受入基準とテストの対応: 要件4の受入基準1から3(種類のラベルが無いか2つ以上ある起票と、場所のラベルが要るのに無い起票が止まる)が、Claude のセッションで実際に働くことは、「実装のメモ」の、マージのあとのフックの確かめで確かめる。フックの判定そのものは、タスク5.1のテストで確かめる
  - _要件: 4.1_

- [ ] 6. 起票の手順にラベルの選び方を入れる
- [x] 6.1 起票の決まりにラベルの選び方を入れる (並行可)

  Claude は、部品「file-issue の直し」のとおり、`.claude/skills/file-issue/SKILL.md` に「## ラベルの選び方」の節を足し、Step 3・Step 4・Step 5、「分けた部分のIssue」のコマンド、「実装の途中で小さく分けるとき」の箇条を直す。
  - 完了の確かめ方: 「## ラベルの選び方」の節が、ファイルを起票のたびに読むこと、`description` と `selection_rule` で種類を1つ選ぶこと、迷ったときの手がかりの順(「どうなれば解決か」「やりたいこと」「困っていること」)、`area_required` で場所のラベルを選ぶかを決めること、所有者がラベルを直すよう言ったら Claude がラベルを直すことを含む。`gh issue create` のコマンドの例のすべてに `--label` がある。`grep -nE 'kind/|area/|retrospective'` の当たりが、もとからある「監査の通知と振り返りのIssueは対象外」の行だけである
  - 受入基準とテストの対応: 要件3の受入基準1から7(Claude が起票する Issue に、ラベルの一覧のファイルから選んだ種類のラベルを1つと、要るときは場所のラベルを付け、付けるラベルを所有者に見せる)は、手順の文書なので自動のテストを持たない。上の完了の確かめ方の照合と grep で確かめる
  - _要件: 3.1, 3.2, 3.3, 3.4, 3.5, 3.6, 3.7_
  - _対象の部品: file-issue の直し_

- [ ] 6.2 着手の手順の分け方の案にラベルを入れる (並行可)

  Claude は、部品「start の直し」のとおり、`.claude/skills/start/SKILL.md` の「分けた部分のIssueの案」の書式に、部分ごとの「ラベル: <種類のラベル>、<場所のラベル>」の行を足し、ラベルを起票の決まりの選び方の節に従って選ぶこと、了承された案のラベルのとおりに起票することを書く。
  - 完了の確かめ方: 書式の欄に「ラベル:」の行がある。`grep -nE 'kind/|area/|retrospective'` の当たりが、今の start の手順にもとからある行のほかに増えていない
  - 受入基準とテストの対応: 要件3の受入基準5の分けた部分の起票と、受入基準6(案にラベルを見せる)は、手順の文書なので自動のテストを持たない。上の照合で確かめる
  - _要件: 3.5, 3.6_
  - _対象の部品: start の直し_

- [ ] 6.3 振り返りの手順をファイルの決まりで選ぶ形にする (並行可)

  Claude は、部品「retrospective の直し」のとおり、`.claude/skills/retrospective/SKILL.md` から、ラベルを作る手順と `gh label create` のコマンドを外し、起票のコマンドを `--label <種類のラベル> [--label <場所のラベル>]` の形にする(場所のラベルは、選んだ種類のラベルの `area_required` が `true` のときだけ付ける)。種類のラベルは、起票の決まりのラベルの選び方の節に従って選び、選ぶときの決まりが振り返りの手順を名指ししているラベルがあればそれを選ぶ、と書く。Claude は、振り返りの手順に、Claude が起票したあとに Issue の番号と付けたラベルを所有者に示すことを書く。
  - 完了の確かめ方: `gh label create` が無い。`grep -n 'retrospective'` の当たりが、手順の名前を書いた見出しと説明の行だけで、ラベルの名前としての `retrospective` が無い
  - 受入基準とテストの対応: 要件3の受入基準5の振り返りの起票は、手順の文書なので自動のテストを持たない。上の照合と、タスク2のファイルの `retrospective` の `selection_rule` が振り返りの手順を名指ししていることで確かめる
  - _要件: 3.5_
  - _対象の部品: retrospective の直し_

- [ ] 7. ワークフローの一覧の文書に足す (並行可)

  Claude は、`README.md` のワークフローの一覧の表に `sync-labels.yaml` の行を足し、Mermaid の図に、ラベルの一覧が main に入ったら GitHub のラベルを合わせる流れを足す。`doc/インフラ設計/Github Actions設計/ワークフロー設計.md` の表にも、同じワークフローの行を足す。
  - 完了の確かめ方: 2つの文書の表に `sync-labels.yaml` の行があり、発火条件が push(main、ラベルの一覧のファイルの変更)と手動である。README の Mermaid の図の構文が、ノードの名前に括弧と引用符を含まない
  - 受入基準とテストの対応: この文書の直しが満たす受入基準は無い(CLAUDE.md の作業規約で、ワークフローを足した PR は README の表と図も直すと決まっている)
  - _要件: 2.1_
  - _依存: 4.1_

- [ ] 8. 所有者が置いたファイルで全体を確かめる
- [ ] 8.1 所有者にファイルを置いてもらい、置いた場所でテストを流す

  親のセッションは、scratchpad の `place-1/` と `place-2/` のファイルを本来の場所に写すコマンドを、所有者に示して置くよう頼む。依頼には、Claude が `.github/` と `.claude/settings.json` と `.claude/hooks/` に書き込めないこと(`settings.json` の `deny`)を添える。所有者が置いたら、親のセッションは、本来の場所で、コンテナの中の `test-sync-labels.sh`、Git Bash の `test-check-issue-labels.sh`、shellcheck(対象は `git ls-files -z --cached --others --exclude-standard '*.sh'` で、まだコミットしていない新しいファイルを含める)、actionlint、`sync-labels.sh --check` を流す。
  - 完了の確かめ方: `git status` に、置いた7つのファイル(`labels.json`、`sync-labels.sh`、`test-sync-labels.sh`、`sync-labels.yaml`、`guardrails.yaml`、`check-issue-labels.sh`、`test-check-issue-labels.sh`)と `settings.json` が出る。上のすべてが失敗0件か指摘0件で終わる
  - 受入基準とテストの対応: タスク3.1と3.2で作った `test-sync-labels.sh` のテストと、タスク5.1で作った `test-check-issue-labels.sh` のテストを、本来の場所で流し直して確かめる
  - _要件: 2.1, 2.5, 4.1_
  - _依存: 3.2, 4.2, 5.2_

## 実装のメモ

- `.github/` の下と、`.claude/settings.json`、`.claude/hooks/` の下は、Claude が書けない(`settings.json` の `deny`)。Claude は、それらのファイルを scratchpad の `place-1/`(`.github` の分)と `place-2/`(`.claude` の分)に、リポジトリと同じ並びで作る。所有者が置くまで、Claude はそれらを本来の場所に書こうとしない
- `.claude/` の下のファイルは、`cp` で読むときも `deny` に止められる。Claude は、写しを作るときは Read と Write を使う。Bash の heredoc で書くときは、100行を超えるファイルを分けて `>>` で追記する
- Claude は、scratchpad の写しに書くときは、Write に scratchpad の絶対パスを渡す。拒否されたときは、Bash の heredoc か Python で書く
- Claude は、actionlint を、リポジトリの作業フォルダを読み取り専用で写したものに、scratchpad の `place-1/.github/workflows/` のファイルを重ねて流す。actionlint は `docker run --rm -v "$(pwd -W):/repo:ro" -v "<place-1 の絶対パス>/.github/workflows/sync-labels.yaml:/repo/.github/workflows/sync-labels.yaml:ro" -v "<place-1 の絶対パス>/.github/workflows/guardrails.yaml:/repo/.github/workflows/guardrails.yaml:ro" -w /repo rhysd/actionlint:1.7.12 -color` の形で流す
- 所有者への依頼と、使い捨てのリポジトリの作成は、親のセッションが行う。実装役のサブエージェントは、所有者に依頼する手前で止まり、用意したもの(scratchpad のパス)を親のセッションに返す。確認役は、置く前の成果を scratchpad のパスで確かめる
- 共通の完了条件の1(確かめるテストの無い受入基準を残さない)の例外は、要件2の受入基準3のうち Issue にラベルが残ること・受入基準4のうち Issue と PR から外れること(GitHub の動き。タスク1と公式の説明書で確かめる)、要件2の受入基準1と7(ワークフローの起動。マージのあとの初めての実行で確かめる)、要件3の受入基準1から7(Claude が起票する Issue に、ラベルの一覧のファイルから選んだ種類のラベルを1つと、要るときは場所のラベルを付け、付けるラベルを所有者に見せること。手順の文書なので、照合と grep で確かめる)、要件4の受入基準6のうち定期実行と所有者の端末の起票(Claude のフックを通らない)である
- マージのあとのフックの確かめ: Claude は、出荷の PR の本文に、この確かめの手順を書く。マージのあと、所有者がこの確かめを始める。Claude Desktop の worktree のセッションは、本体の作業フォルダの設定とフックを読む。そのため、マージの前にこの worktree で新しいセッションを開いても、登録したフックは働かない。マージのあと、所有者が本体の作業フォルダを最新の main にしてから新しいセッションを開き、Claude は `GH_TOKEN=invalid gh issue create --title t --body b` を打って、フックがその起票を止めること(要件4の受入基準1)を確かめる。`GH_TOKEN` を無効な値にするのは、フックが働かなかったときにも Issue が作られないようにするためである
- マージのあとの確かめ: 所有者は、初めての `sync-labels.yaml` の実行が成功していることと、`bug`・`enhancement`・`documentation` の名前が変わり、今それらが付いている Issue に新しい名前のラベルが付いていること、`duplicate` など6つが消えていることを、Actions の画面と Issue の一覧で確かめる。Claude は、出荷の PR の本文にこの確かめを書く
- 1 の完了の記録(2026-10-13): 所有者が自分のアカウントで非公開のリポジトリ `DogisRiki/label-rename-check` を作り、確かめた(bot のアカウントでの作成は、安全装置に止められるおそれがあるため、所有者が作った)。`bug` を付けた Issue を作り、`gh api -X PATCH repos/DogisRiki/label-rename-check/labels/bug -f new_name=kind/bug` で名前を変えたあと、`gh issue view 1 --json labels` は `kind/bug`(説明と色は `bug` のまま)だけを返した。`gh api "repos/DogisRiki/label-rename-check/labels/kind%2Fbug"` は `kind/bug` を返し、`gh api -X DELETE "repos/DogisRiki/label-rename-check/labels/good%20first%20issue"` で消せた。新しいリポジトリの初めのラベルには `accessibility` もあった(このリポジトリの今のラベルには無い)
- 2 の申し送り: 成果物は scratchpad の `place-1/.github/labels.json`(23個)。今の GitHub の色のうち7個(blocked・audit・container-vuln・canary・pre-merge-check・migration・codex-overruled)は大文字で、ファイルは小文字で書いた。タスク3.2のスクリプトは、色を大文字と小文字を区別せずに比べる(区別すると、初めての実行で色の変わらない直しを7個送り、2回目の実行が何も書き込まないことの確かめが GitHub の返す形に左右されるため)。requirements の表の文のバッククォートは、`description` と `selection_rule` にそのまま入れた。GitHub の画面の説明では、バッククォートが文字のまま出る
- 3.1 の申し送り: `--check` を付けずに呼ぶと、今は検証のあとに終了コード1で止まる(合わせ込みは3.2で作る)。3.2では、スクリプトの末尾のこの扱いと、先頭の説明の「guardrails から実行」と終了コード1の説明を、合わせ込みの説明に書き直す。`GITHUB_REPOSITORY` と `GH_TOKEN` の確かめも3.2で入れる。名前が空の文字列のラベルは、design の検証の決まりに無いので検証に通る(GitHub が受け付けないので、合わせ込みの書き込みが失敗して終了コード1で終わる)
- 3.2 の申し送り: `GITHUB_REPOSITORY` が無いか形が誤っているとき、`GH_TOKEN` が無いときは、gh を呼ばずに終了コード64で終わる。前の名前のラベルが GitHub に2つ以上あるときは、`previous_names` の先のものの名前を変え、残りを食い違いとして1で終わる。gh の呼び出しは `timeout -k 10 60` で打ち切る(alpine と ubuntu:24.04 の両方にある)。書き込みの失敗の文は、標準エラーに加えて実行の要約にも出す
- 3.2 で起きたこと: 実装役が、読み取り専用で写したリポジトリにファイルを重ねようとして、Docker が作業フォルダに0バイトの `.github/scripts/sync-labels.sh` と `.github/scripts/tests/test-sync-labels.sh` を作った。Claude は `.github/` の下を消せないので、タスク8.1で所有者が置くときに上書きされる。4.1 と 5.1 で shellcheck や actionlint を流すときは、作業フォルダに無いファイルを `-v` で重ねない。リポジトリを scratchpad の一時フォルダに写してそこで重ねるか、scratchpad のファイルを直接渡す
- 5.1 の申し送り: フックは、design の読み方に加えて、次の形も読む。`gh` と `issue` の間の `-R` / `--repo`。`env`・`command`・`exec`・`time`・`nohup`・`if` などの前置きの語。`"$(...)"` の中。`sh` か `bash` が受けるヒアドキュメントの本文(それ以外のヒアドキュメントの本文は読まない)。`--help` / `-h` の起票は通す。このリポジトリが分からないとき(origin が無いなど)は、`-R` をほかのリポジトリとみなさず、ラベルの判定を続ける。`GH_REPO` は見ない。止まりすぎの形として、`bash -c '...' <<EOF` と `bash script.sh <<EOF` の本文にラベル無しの `gh issue create` の行があると止まる。通り抜ける形として、`tee f <<EOF | bash`・`eval`・`timeout 30 gh ...`・`gh api` に URL を全部書く形・curl がある。どれも手順では使わない形なので、このままにする
- 6.1 で見つかったこと: 文書だけを変える Issue(`kind/documentation`)は `area_required` が `true` だが、3つの場所のラベルの説明はどれも文書そのものを指していない。文書が扱う対象(インフラの設計の文書なら `area/infra` など)で選べば1つに決まるが、spec はこの読み方を決めていない。所有者に伝える
- 共通の完了条件の2(verify のスキル)は、この spec が frontend・backend・terraform を変えないので、当てはまらない。代わりに、Claude は、各タスクの完了の確かめ方に書いたテスト・shellcheck・actionlint を流す

## 完了条件(全タスク共通)

Claude は、どのタスクでも、タスクの箇条書きの欄を書いたうえで、次の4つを満たしたときにタスクを完了とする。

1. Claude は、タスクが満たす requirements.md の受入基準(要件の番号付きの項目)ごとに、それを確かめるテストのファイル名とテスト名を「受入基準とテストの対応」の行に書く。Claude は、確かめるテストの無い受入基準を残さない。
2. タスクで変えた領域の verify のスキル(`/verify-frontend` `/verify-backend` `/verify-terraform`)が、すべて成功している。
3. Claude は、テストを飛ばす設定、アサーションの削除、カバレッジや lint の対象からの除外を足して、完了条件を満たしたように見せない。CI の escape-hatch の検査が、これらの追加を機械で見つける。
4. Claude は、新しく書いたテストについて、テストの対象のコードを一時的に壊してテストが失敗することを確かめてから、コードを元に戻す。
