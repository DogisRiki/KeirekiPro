---
description: verify-all→ブランチ確認→規約準拠commit→push→PR作成→auto-mergeの予約の確認→CI監視まで、実装完了からCIの見届けまでを一気通貫で行う。auto-mergeは仕組みが予約する。
---

# ship

## Job

実装完了後の出荷手順。verify → commit → push → PR作成 → auto-mergeの予約の確認 → CI監視。
auto-mergeは、PRが作られると仕組み(ワークフロー)が予約する。AIは予約の操作をせず、予約されたことを確かめる。
人間はマージに関与しない(ゲート全通過で自動マージされる)。

## Steps

1. **verify**: `/verify-all` の手順を実行し、全PASSを確認する。FAILがあれば出荷しない。

2. **ブランチ確認**: `git branch --show-current` で現在のブランチを確認する。
   - mainにいる場合: `.branch_name_template` に従い `git switch -c <type>/<short-description>` で作成
   - featureブランチにいる場合: 作業内容と合っているか確認

3. **commit**: `.commit_template` の形式に従う(prefix / subject / Changes / Reason / BREAKING CHANGE / Refs)。
   次の3つを、それぞれ単独のコマンドとして順に実行する。
   1. コミットメッセージを scratchpad のファイルに Write で書く
   2. `git add <ファイル1> <ファイル2> ...`(変更したファイルを個別に指定する。`-A` で無関係なファイルを巻き込まない)
   3. `git commit -F <メッセージのファイル>`
   - `Refs: #<Issue番号>` を必ず入れる

4. **push**: `git push -u origin <ブランチ名>` を単独のコマンドとして実行する。

   commit と push は、上の形から変えない。`-q` などのオプションを足さない、`cd` や `git log` や
   `| tail` を `&&` `;` `|` でつながない、`-m` やヒアドキュメントでメッセージを渡さない。
   この形は `.claude/settings.json` の許可ルールにそのまま当たり、auto mode の判定に回らない。
   形がずれると判定に回り、ゲート設定(`.github/` `.claude/`)を含む変更は止められることがある。
   形は `.claude/hooks/protect-main.sh` が実行前に確かめ、外れていれば止めて正しい形を案内する
   (mainへのcommit/pushと強制pushも止める)。結果を確かめたいときは、`git log --oneline -1` を
   別のコマンドとして実行する。リモートのブランチの削除(`git push origin --delete`)も止まるので、
   削除が要るときは人間に依頼する。

5. **PR作成**: `gh pr create` で作成する。PR本文に必ず含めるもの:
   - `Refs: #<Issue番号>`
   - `Closes #<Issue番号>`(例外なく必須。マージ時にGitHubがIssueを自動で閉じる。GitHubが閉じなかったときは仕組みが閉じる)
   - Lane A(spec駆動)の場合: `Spec: .kiro/specs/<feature>`(size-checkがこの行で判定する)
   - テストのアサーションを意図的に変更した場合: `Test-Change-Justification: <理由>`
   - 変更概要・検証結果(verifyのReport)

   分けた部分のIssue(サブIssue)のPRでは、`Refs:` と `Closes` にサブIssueの番号を書き、元のIssue(親)の番号は書かない。
   codex-review はサブIssueの本文を判定の基準にし、close-linked-issues は元のIssueに「`Refs:` だけ」の知らせを出さない。
   元のIssueは、サブIssueがすべて閉じたときに仕組みが閉じる。

   更新した spec(spec.json に `additional_issues` がある)のPRでは、本文に
   「このPRが実装するのは `(#N)` の印の付いた項目です。印の無い項目は以前のPRで実装済みです」と書き、
   `Refs:` と `Closes` には追加のIssueの番号を書く。

   対応するIssue(Refs: #<Issue番号>)に `pre-merge-check` ラベルが付いているかを、PRを作る前に確かめる。
   付いている場合は、`gh pr create` に `--label pre-merge-check` を付け、PRの作成と同時に同じラベルを付ける
   (リポジトリにラベルが無ければ、先に
   `gh label create pre-merge-check --description "マージ前に人間がローカルで確認するPR" --color 1D76DB` で作成)。
   PRを作った後からラベルを付ける形にしない。仕組みがPRの作成の直後にauto-mergeを予約するため、
   後から付けると、付くまでの間は保留が効かない。
   このラベルのPRは、所有者がローカル確認してApproveするまで pre-merge-check チェックが赤のままになる。

   PRを作ったら、`gh pr view --json number -q .number` を単独のコマンドとして実行し、いまのブランチのPRの番号を得る。
   以降の手順の `<PR番号>` には、この番号を使う。ほかのPRの番号を使わない(並行して動くほかのセッションのPRを扱わないため)。

6. **auto-mergeの予約の確認**: auto-mergeは仕組みが予約する。AIは `gh pr merge` で予約の操作をしない。
   はじめに、`gh pr view <PR番号> --json mergeStateStatus --jq .mergeStateStatus` を単独のコマンドとして実行する。
   `DIRTY`(PRが main と衝突している)なら、予約の確認を飛ばして手順7の1に進む。
   衝突しているPRでは仕組みのワークフローが起動しないので、予約が付かないためである。
   予約は、手順7の手元での取り込みのあとの push で、仕組みが付ける。
   `DIRTY` でなければ、予約されたことを次のコマンドで確かめる(`true` なら予約済み)。
   `gh pr view <PR番号> --json autoMergeRequest --jq '.autoMergeRequest != null'`
   - PRの作成の直後はまだ付いていないことがある(ワークフローが動くまで1分ほど)。`false` のときは少し待って確かめ直す
   - 数分たっても付かないとき、またはPRに予約の失敗を知らせるコメントが付いたときは、
     自分で予約の操作をせず、その旨を報告する(手順7のCI監視は続ける)

7. **CI監視**: PRがマージされたことを確かめるまで見届ける。見届けの途中で、PRのブランチが main と衝突しているか、
   main の最新を含んでいなければ、main を取り込む。下の1から順に進め、コマンドはどれも単独のコマンドとして実行する。
   状態は覚えておかず、3のたびに読み直す。ただし、60秒待って読み直した回数だけは数える。

   60秒待つときは、Claude Code の待ちの道具(Monitor など)で待つ。Bash の前で動かす `sleep` は止められるので使わない。

   1. **衝突の確かめ**: `gh pr view <PR番号> --json mergeStateStatus --jq .mergeStateStatus` を実行する。
      - `DIRTY`(main と衝突している)なら、検査の結果を待たずに、5の「手元での取り込み」に進む。
        衝突しているPRでは GitHub が必須の検査を起動しないので、検査の結果が出る時点が来ないためである
      - `UNKNOWN`(GitHub がまだ計算していない)なら、60秒待って読み直す
      - それ以外なら2に進む
   2. **検査の見届け**: `gh pr checks <PR番号> --watch --required` で、必須の検査の結果がすべて出るのを待つ。
      この間は、ブランチを合わせる操作をしない。赤の検査があって終了コードが0でないときも、3に進む。
      push の直後などで検査がまだ1つも報告されておらず、待たずに終わったときは、60秒待って1に戻る
      (push の直後に衝突して GitHub が検査を起動しないときに、1の `DIRTY` の判定で拾うため)
   3. **状態の読み取り**: 次の4つを、それぞれ単独のコマンドとして順に実行する。
      1. `gh pr view <PR番号> --json state,mergeStateStatus,reviewDecision,autoMergeRequest,headRefName`
      2. `gh pr checks <PR番号> --required --json name,bucket`(`bucket` が `pass` `skipping` なら通った、
         `fail` `cancel` なら赤、`pending` なら結果が出ていない)
      3. `git fetch origin`
      4. `git log --oneline origin/<headRefName>..origin/main`(1行でも出れば、PRのブランチは main の最新を含んでいない)

      ブランチが古いかどうかを `mergeStateStatus` で読まないのは、承認待ちなどほかの理由があると `BLOCKED` になり、
      古いことが読めないためである。
   4. **判定**: 3で読んだ状態を次の順に当て、最初に当たったものに従う。判定には必須の検査だけを使う。
      1. `state` が `MERGED`: 見届けを終える
      2. `mergeStateStatus` が `DIRTY`: 5の「手元での取り込み」に進む
      3. `git log` が1行以上を出した: 5の「サーバーでの取り込み」に進む。
         承認待ちや赤の検査より先に取り込むのは、承認のあとに取り込むと承認が外れ、所有者が承認し直すことになるためである
      4. 必須の検査に結果が出ていないもの(`bucket` が `pending`)がある: 2に戻る。
         読み直しの間に main が進み、仕組みがブランチを合わせて検査がやり直されたときに当たる
      5. 所有者の承認を待っている: `reviewDecision` が `REVIEW_REQUIRED` のとき(CODEOWNERS の承認待ちを含む)、
         または承認待ちのゲートの検査が赤のとき。承認待ちのゲートの検査は、`.github/audit/required-checks.json` で
         `approval_gated: true` の検査(今は `escape-hatch` `dependency-gate` `pre-merge-check`)である。
         この項に当たるのは、承認待ちのゲートのほかに必須の検査の赤が無いときに限る。
         ほかに赤があれば、この項を飛ばして6に進む。当たったら、状態を報告して見届けを終える。
         この項を6より先に置くのは、承認待ちのゲートの赤を `/review-loop` で直そうとしないためである
      6. 必須の検査に赤がある: 修正して手順4の形でpushし、1に戻る(以降のレビュー対応は `/review-loop` に従う)。
         ただし、spec 無しのPRが `size-check` で赤になったときは、修正してpushしない。
         `/start` の「途中で見立てが外れたとき」に従い、spec に切り替えるか小さく分けるかを決めて理由を示し、7に進む
      7. 所有者に提案して答えを待っている(`size-check` で止まったとき、ゲートの設定の変更、コンテナの脆弱性の抑制の追加など):
         状態を報告して見届けを終える
      8. 必須の検査がすべて通り、`autoMergeRequest` が `null`: 自動マージの予約が付いていない。
         自分で予約を付けず、状態を報告して見届けを終える
      9. それ以外(予約があり、必須の検査がすべて通り、ブランチが最新): マージの途中なので、60秒待って3に戻る
   5. **取り込み**:
      - **サーバーでの取り込み**(衝突していないとき): 次の3つを、それぞれ単独のコマンドとして順に実行する。
        1. `gh pr view <PR番号> --json headRefOid --jq .headRefOid` で、取り込みの前の head を読む
        2. `gh pr update-branch <PR番号>`
        3. `gh pr view <PR番号> --json headRefOid --jq .headRefOid` で、取り込みのあとの head を読む

        GitHub がサーバーで main を取り込み、PRの検査がやり直される。手元で push しないので、手元の `/verify-all` は通さない。
        衝突していないPRを手元で取り込まない。
        - head が進んだら、2に戻る
        - head が進んでいなければ、60秒待って head を読み直す
        - `gh pr update-branch` が衝突で失敗したら、下の「手元での取り込み」に進む
        - `gh pr update-branch` が衝突のほかの理由で失敗したら、60秒待ってやり直す
      - **手元での取り込み**(衝突しているとき): `git fetch origin` と `git merge origin/main` を、それぞれ単独のコマンドとして順に実行する。
        衝突が出たら解消し、`/verify-all` を通してから、次の3つを、それぞれ単独のコマンドとして順に実行してマージを完了する。
        1. `git rev-parse --git-path MERGE_MSG` でマージのメッセージのファイルのパスを得る
           (worktree の作業フォルダと本体フォルダとでパスが違うため、パスを決め打ちしない)
        2. `git add <解消したファイル>`
        3. `git commit -F <手順1で得たパス>`(手順3と同じく、コマンドの置き換え `$(...)` でパスを渡さない)

        衝突が出ずにマージが完了したときも、`/verify-all` を通す。`/verify-all` が通らなければ push しない。
        最後に、手順4の形で push し、1に戻る
   6. **見届けを終えるとき**: 報告に、終えた理由と、3で読んだ `mergeStateStatus` と、
      ブランチが main の最新を含んでいるかどうかを添える

   **手元での push が拒まれたとき**: 手元で push する場面(5の手元での取り込みで衝突を直したとき、4の6で赤を直したとき)で、
   サーバーでの取り込みやワークフローによってリモートのブランチが進んでいて push が拒まれたら、
   `git fetch origin` と `git merge origin/<ブランチ名>` を、それぞれ単独のコマンドとして順に実行してリモートのPRブランチを取り込む。
   `git merge origin/<ブランチ名>` は `.claude/settings.json` の許可の規則に無いので、実行のときに確認が出ることがある。
   衝突が出たら、5の「手元での取り込み」と同じく解消し、`git rev-parse --git-path MERGE_MSG` でパスを得て、
   `git add <解消したファイル>` と `git commit -F <得たパス>` を、それぞれ単独のコマンドとして順に実行してマージを完了する。
   衝突が出たときも出なかったときも、`/verify-all` を通してから手順4の形で push し直す。`/verify-all` が通らなければ push しない。

   **同じ失敗が3回続いたとき**: 次のどれかが3回続いたら、CLAUDE.md の「同一の失敗が3回続いたら停止」に当たるとして、
   PRの状態を報告して見届けを終える。
   - 1の `UNKNOWN` と、4の9(それ以外)で、60秒待って読み直しても状態が変わらない。
     予約があり検査がすべて通っていれば、GitHub は通常1分ほどでマージするので、3分たってもマージされないのは何かが止まっているときである
   - 2で、60秒待って1に戻っても、検査がまだ1つも報告されていない
   - 5のサーバーでの取り込みで、取り込みのあとに読み直しても head が進んでいない
   - 5のサーバーでの取り込みで、`gh pr update-branch` が衝突のほかの理由で失敗する
   - 5の手元での取り込みで、衝突を直したあとの `/verify-all` が同じ理由で通らない
   - 手元での push が拒まれる

## Rules

- verify全PASSまでpushしない。手順7でPRが main と衝突していないときは、`gh pr update-branch` でサーバーで main を取り込み、手元で push しない
- 1つのPRに複数の関心事を混ぜない(200行のsize-checkは分割のシグナル)
- マイグレーション・依存追加・ゲート設定変更を含む場合は、PR本文冒頭に「人間承認が必要な変更」として明記する
- `Refs: #<Issue番号>` は `Closes` と併記しても消さない。codex-reviewがこの行からIssue本文を
  取得してspec適合の判定基準にしている

## Report

```
ship:
- verify-all -> PASS
- branch     -> <ブランチ名>
- commit     -> <コミットハッシュ> <サブジェクト>
- PR         -> <PR URL>
- auto-merge -> 仕組みによる予約を確認済み / 未予約(確かめた結果と、失敗の知らせの有無)
- checks     -> 監視結果 / 人間承認待ちの有無
- merge      -> マージ済み / 見届けを終えた理由(承認待ち・提案の答え待ち・予約なし・3回失敗)と mergeStateStatus・ブランチが最新か
- issue      -> Closes #<Issue番号> 記載済み(マージ時に自動クローズ。GitHubが閉じなかったときは仕組みが閉じる)
```
