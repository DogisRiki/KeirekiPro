# design レビュー記録: spec-need-triage

## サイクル1 往復1(2026-10-02)

審査の材料: `design.md`(全文)、`requirements.md`(全文。承認済み)、`research.md`、`spec.json`(issue 472、design 未承認)、Issue #472 本文(`gh issue view 472`、コメントは読んでいない)、`gh issue view 472 --json number,title,state,parent,subIssues,subIssuesSummary`(設計が前提にする JSON の欄が返ることを確認。`parent: null`、`subIssuesSummary.total: 0`)、steering 3文書、`CLAUDE.md`、`README.md`(L100〜111、L300〜406)、`doc/開発フロー/監査手順.md`(L95〜114)、`.kiro/settings/templates/specs/design.md` `tasks.md` `init.json`、`.claude/skills/kiro-spec-init|-requirements|-design|-tasks/SKILL.md`、`.claude/skills/kiro-impl/SKILL.md`(承認の確認と `[x]` の扱い)、`.claude/skills/file-issue/SKILL.md`、`.claude/skills/ship/SKILL.md`、`.claude/skills/spec-review/SKILL.md`、`.claude/agents/spec-reviewer.md`、`.claude/hooks/spec-review-scan.sh`、`.github/scripts/close-linked-issues.sh`、`.github/scripts/tests/test-close-linked-issues.sh`(L1〜913)、`.github/scripts/lib-notice-comment.sh`(`notice_post` の引数)、`.github/scripts/check-spec-backing.sh`、`.github/workflows/close-linked-issues.yaml`、`.github/workflows/guardrails.yaml`(L124〜190)、`.github/workflows/codex-review.yml`(L158〜168)、全スキルのフロントマター(`disable-model-invocation` の有無)、requirements の review と response(全サイクル)。`brief.md` は無い。

要件カバレッジ: 要件1〜10 のすべての受入基準が Requirements Traceability に現れ、`start` の手順・kiro-spec-init の更新の形・file-issue / ship / spec-review の変更・ParentCloser・文書の変更のいずれかに裏付けがある。ID だけで実現する要素が無いものは見つからなかった。requirements のサイクルで「design で決める」と申し送られた7件(R1-1-5、R1-1-6、R1-2-4、R1-2-5、R1-3-1〜R1-3-3、R2-1-1〜R2-1-3)は、いずれも本文で決められている(PRを閉じてブランチを残す、観点の定義、close-linked-issues.sh が親を閉じる、同じ会話で部分を進める、取り消しは所有者のコマンドの中、サブIssueの親子、PR本文で範囲を説明、「マージを取り消しても」の語、観点1の中間の扱い)。

境界: `This Spec Owns` と `Out of Boundary` に設計本文が反していないことを確かめた。Non-Goals の `codex-review.yml` と size-check は本文のどこでも変えていない。Compliance Check の「ゲート設定」は、本文の File Structure Plan(`.claude/` 14件、`.github/scripts/` 2件)と矛盾しない形で「変更を必要とする」と書かれている(チェックの付け方は D1-1-3)。

実現できない設計: GitHub のサブIssueがこのリポジトリ(個人所有・公開)で使えることは `gh issue view` の JSON で確かめた。`gh issue create --parent` は、審査役に許された `gh issue view` では確かめられないため、設計の実測の記述(gh 2.97.0)に依る。`disable-model-invocation` と `$ARGUMENTS` は、このリポジトリの既存スキル(`kiro-impl`、`request`、`retrospective`、`kiro-discovery`)がすでに使っている。ParentCloser が使う `issues: write` は既存のワークフローの権限のままで足りる。

### 申告

**1. 親のIssueを閉じる処理を、CI の `close-linked-issues.sh`(`.github/scripts/`、CODEOWNERS の対象)に足す** — ParentCloser、File Structure Plan

- Issue の記載: なし(「1つの spec に収まらないとAIが判断したら、分け方を理由付きで所有者に示す」までで、分けたあとの元のIssueの扱いは requirements で決めた)
- 決めたこと: 部分のPRのマージで動く close-linked-issues.sh の最後に、親の子がすべて閉じていれば親を閉じる処理を足す。親の親まで最大8段を繰り返す。失敗は親へのメンション付きのコメントで知らせる
- 他にありえた選択肢: 最後の部分のPRの本文に親の `Closes` も書く(research.md で退けた。どれが最後か分からない)。`issues: closed` を起点にする新しいワークフロー(`github.token` で閉じた子では起動しない)。AI側(`/start` か `/ship`)が親を閉じる。親は閉じずに、子がすべて閉じたことを知らせるだけにする
- 外れていた場合: `.github/scripts/` の変更は CODEOWNERS により所有者の承認が要り、テスト(`test-close-linked-issues.sh`)の偽の `gh` の応答にも手が入る。PRのマージ以外で閉じた子からは親が閉じず、知らせも出ない(設計はこれを Out of Boundary に置いた。D1-1-7)。親を閉じる判定を誤ると、残りの作業があるIssueが閉じる

**2. 既存の spec の更新は、3段階すべての承認を取り消して要件から作り直す** — kiro-spec-init の更新の形(手順2・3)、`start` 手順7

- Issue の記載: あり(「その spec を更新する」。「AIの提案を了承」の印)。更新のしかたは書かれていない
- 決めたこと: 所有者が `/kiro-spec-init #N <feature>` を打った時点で、承認済みの段階を `approval_history` に写し、要件・設計・タスクを `generated: false` `approved: false` に戻し、`phase` を `initialized` にする。新しいIssueの本文を requirements.md の要望の欄に足し、`/kiro-spec-requirements` から進める
- 他にありえた選択肢: 影響のある段階だけ取り消す(要件が変わらない変更なら design から)。既存の spec には触れず、差分を新しい spec にする(`start` の「新しい spec」に寄せ、「更新」を使わない)。承認は取り消さず、印付きの追記だけにする
- 外れていた場合: 更新のたびに3回の承認と3回の審査が要り、小さい追加でも所有者の負担が spec 1本分になる。手戻りは生じないが、所有者が「更新」より「新しい spec」を選ぶ運用になり、既存の spec と新しい spec に同じ範囲が二重に書かれる

**3. spec.json に `additional_issues` と `approval_history` を足し、`issue` は番号1つのまま変えない** — Data Models、Revalidation Triggers

- Issue の記載: なし
- 決めたこと: `issue` は元のIssueのまま。追加のIssueは `additional_issues`(整数の配列)、取り消した承認は `approval_history`(追記だけの配列。`stage` `approved_by` `approved_at` `issues` `revoked_at` `revoked_for`)に入れる。読み手は spec-reviewer、kiro-spec-init、`/start`
- 他にありえた選択肢: `issue` を配列にする(既存の全 spec と `check-spec-backing.sh` 以外の読み手に影響しないが、テンプレート `init.json` と kiro-spec-init の置き換えが変わる)。承認の履歴を spec.json ではなく `reviews/` の記録か別ファイル(`approvals.log` など)に残す
- 外れていた場合: 3つの読み手が同じ形に依存するため、あとで形を変えると既存の spec.json を一括で直すことになる(設計自身が Revalidation Triggers に挙げている)。履歴を spec.json に入れたことで、`spec-review-scan.sh` の perl の読み取りや `check-spec-backing.sh` の jq は影響を受けない(どちらもキーを個別に読むことを確かめた)

**4. `start` スキルは `disable-model-invocation` を付けず、AIが自分から起動できる形にする** — `start` の Responsibilities & Constraints、research.md の Decision

- Issue の記載: あり(「所有者が着手時にすることは…1つだけにする」「AIが…返事を待たずに実装を始める」。いずれも「AIの提案を了承」の印)。AIが自分から着手の手順に入ってよいかは書かれていない
- 決めたこと: 所有者が「#N をやって」と言葉で頼んだときも同じ手順に入れるよう、AIから起動できる形にする。説明文に「Issueへの着手を頼まれたら必ず使う」と書く
- 他にありえた選択肢: `request` `kiro-impl` と同じく `disable-model-invocation: true` を付け、所有者が `/start` と打ったときだけ動かす(言葉で頼まれたら `/start #N` を打つよう案内する)
- 外れていた場合: spec 不要と判断した場合は返事を待たずに実装から `/ship` まで進む手順なので、所有者が着手のつもりで無い発言(「#N はどう直す?」)や定期実行のループの中からAIが着手し、PRまで出る。止める決まりは CLAUDE.md の「`/loop` から commit/push しない」に頼る(research.md の Trade-offs)

**5. 4つの観点の線引きを design で決めた(観点1は「今ある動きを意図して変える変更」を当たらないとし、観点4に「本番の設定を変える」を足した)** — `start` の「観点の定義」

- Issue の記載: あり(「新しい機能か、設計上の選択があるか、依頼に抜けがあるか、取り消しにくい変更か」。「AIの提案を了承」の印)。線の引き方は requirements 2.1 が例で示し、中間(R2-1-2)は design に申し送られた
- 決めたこと: 観点1の「当たらない」に「今ある動きを意図して変えるだけの変更」を入れ、観点2と3で判断する。観点4の「当たる」に、requirements の例(データの形、外部への送信)に加えて「本番の設定を変える」を入れた
- 他にありえた選択肢: 意図した動きの変更を観点1の「当たる」に寄せる(R2-1-2 の直し方の案の前半)。観点4は requirements の例のままにする
- 外れていた場合: 観点1を狭くした分、動きを変える変更が観点2・3のどちらにも当たらなければ spec 無しで進む(例: 上限の値を変える、並び順の方針を変える)。200行に届かなければ、codex-review はIssue本文だけを基準に通す。観点4を広げた分は spec 側に倒れるだけで、手戻りは無い

### 指摘

| ID | レベル | 該当箇所 | 内容 | 直し方の案 |
|---|---|---|---|---|
| D1-1-1 | 中 | `start` 手順2 の表(spec.json の状態 → 示すこと) | 表の4行目は「tasks が生成済みで未承認、または `ready_for_implementation` が true で未完了のタスクがある」を `/kiro-impl` の条件にしている。しかし `ready_for_implementation` を true にする手順は `.claude/` のどのスキルにも無い(grep の結果、書いているのはテンプレート `init.json` の `false` だけで、読むのは `check-spec-backing.sh` だけ)。`kiro-spec-tasks/SKILL.md` Step 4 は `approvals.tasks.approved: true` を記録するだけで、`kiro-impl/SKILL.md` L45-46 も「tasks are approved in spec.json」しか確かめない。既存の spec(`issue-close-and-auto-merge-guarantee`)で true なのは、決まりではなく習慣で書かれたものである。このため「tasks が承認済み、`ready_for_implementation` が false のまま、未完了のタスクがある」という状態がどの行にも当たらず、`/start` を打った所有者に次のコマンドを示せない。表はそのまま SKILL.md に写されるため、実装の段階では気づかない | 4行目の条件を「tasks が生成済みで未承認」と「`approvals.tasks.approved` が true で、tasks.md に `[ ]` のタスクが残っている」の2行に分け、`ready_for_implementation` を判定に使わない。あわせて kiro-spec-init の更新の形(手順3)で `ready_for_implementation` を false にする記述は残してよい(`check-spec-backing.sh` が読むため)が、誰がいつ true に戻すかを本文に1行書く(例: 「tasks の承認を記録するときに true にする」) |
| D1-1-2 | 中 | kiro-spec-init の更新の形(手順3・5)、「Issueの印」、Out of Boundary の4つ目 | 更新の形は、既存の requirements.md を残したまま `generated: false` に戻し、要望の欄に新しいIssueを足して `/kiro-spec-requirements` を打たせる。印の決まり(「印の無い項目は元のIssueに対するもの」「既存の項目を直したら `(#N で変更)`」「取りやめても本文を消さない」)と、tasks.md の `[x]` の維持は、既存の要件が番号ごと残ることを前提にしている。ところが `kiro-spec-requirements/SKILL.md` には既存の本文を保つ手順が無い。Step 1(L27)は requirements.md を「for project description」として読み、Step 3(L51)は「Create initial requirements draft based on project description」、Step 5(L71)で書く。design(`kiro-spec-design/SKILL.md` L112「merge mode」)と tasks(`kiro-spec-tasks/SKILL.md` L65「If existing tasks.md found, merge with new content」)には merge の記述があるが、requirements だけ無い。設計は Out of Boundary で生成の手順の変更を「冒頭の1行と、CLAUDE.md の印の決まりに従うことを除く」として外しており、CLAUDE.md の印の決まりにも「既存の要件の番号と本文を保つ」は書かれていない。要件が作り直されて番号が変わると、`[x]` のタスクの `_Requirements:_` と design の traceability が別の要件を指し、印の無い項目が元のIssueに対するものとも言えなくなる。審査(5.7)は印を頼りに判定するため、ずれを検出できない | 次のどちらかにする。(a) `kiro-spec-requirements/SKILL.md` に「requirements.md に `### 追加の要望(Issue #N)` があるときは、既存の要件の番号と本文を保ち、追加・変更・取りやめを印の決まりで書く(merge mode)」の1〜2行を足すことを、Out of Boundary の例外として明記し、File Structure Plan に加える。(b) 生成の手順を変えないなら、kiro-spec-init の更新の形で requirements.md に書き足す見出しの直下に、生成側への指示文(既存の番号を変えない、追加は末尾に `(#N)`、変更は `(#N で変更)`)を本文として入れ、CLAUDE.md の印の決まりに「既存の要件・設計の節・タスクの番号は変えない」を加える。どちらの場合も、Testing Strategy の「スキルと文書の確認」に、更新の形を試したときに既存の要件の番号が変わらないことの確認を加える |
| D1-1-3 | 低 | KeirekiPro Compliance Check「ゲート設定」 | 7項目のうちこの1項目だけチェックが入っていない(`- [ ]`)。本文は「変更を必要とする。所有者への提案として扱う」と理由を書いており、File Structure Plan とも矛盾しないため内容の問題ではない。ただしテンプレートは「各項目にチェックを入れ、該当しない場合は N/A と理由を書く」であり、未チェックのままだと「確認していない」と読める | `- [x] **ゲート設定**: 変更を必要とする(所有者への提案として分離。…)` の形にして、確認済みであることと結論を分けて書く |
| D1-1-4 | 低 | KeirekiPro Compliance Check「前提機能の利用可否」、research.md「GitHub のサブIssue」 | 「実測した」の記述に、何を(`gh api repos/.../issues/472`、`gh --version`)どう確かめたかは書かれているが、いつ確かめたかが無い。審査役は `gh issue view --json parent,subIssues,subIssuesSummary` が返ることを 2026-10-02 に確かめたが、`gh issue create --parent` は確かめられない。日時が無いと、あとで gh の版が変わったときに実測の時点を追えない | 「2026-10-02 に gh 2.97.0 で…を実測した」のように日付を添える |
| D1-1-5 | 低 | 「途中で見立てが外れたとき」の4と5 | 4(小さく分ける)は「いまのブランチの変更は最初の部分に当たるものだけを残し、ほかの部分の変更は取り除く」とし、いまのブランチを最初の部分に使う。5(200行の検査で止まった)は「小さく分けるときは、PRを閉じ、4に進む(部分ごとに新しいブランチとPRを作る)」とし、最初の部分も新しいブランチにするように読める。どちらでも実装はできるが、SKILL.md に写すときにどちらかに決めることになる | 5の括弧書きを「最初の部分はいまのブランチを使い、2つ目以降は新しいブランチにする」か「すべて新しいブランチにする」のどちらかに揃える。ブランチ名は `.branch_name_template` に従い、サブIssueの番号を含める旨も添える |
| D1-1-6 | 低 | 「Issueの印」(タスクの末尾に `(#N)`) | tasks.md の書式(`.kiro/settings/templates/specs/tasks.md`)は、タスクの行末に ` (P)` の印を置き、`_Requirements:_` の行には「IDs only; do not add descriptions or parentheses」と定めている。`(#N)` をタストの行末に付けるとき、`(P)` との前後関係と、`_Requirements:_` の行には付けないことが本文に無い。`kiro-impl` は `[x]` と `_Depends:_` を読むため、置き場所が揃っていれば影響しないが、生成側が迷う | 「タスクの行では、`(#N)` は題名の直後、`(P)` の前に置く。`_Requirements:_` `_Boundary:_` `_Depends:_` の行には付けない」のように置き場所を1行で決める |
| D1-1-7 | 低 | Out of Boundary「PRのマージ以外で閉じたサブIssueからの、親のクローズ」、ParentCloser の Risks、要件9.6 | 要件9.6は「分けた部分のIssueがすべて閉じたとき、元のIssueは閉じる」と無条件に書かれているが、設計は親を閉じる契機をPRのマージ(と毎時の見直し)に限り、それ以外で閉じた子からは親が閉じないし知らせも出ない。このリポジトリでは所有者もAIもIssueを手で閉じない決まりのため実際には起きにくく、設計も Risks に書いている。ただし監査手順に足す行は「閉じられなかったとき」の知らせだけで、知らせも無く親が開いたまま残る形はどこにも書かれない | Non-Goals か Adjacent expectations にあたる節に「サブIssueがPRのマージ以外で閉じたときは、親は自動で閉じない(次にいずれかの部分のPRがマージされるか、所有者が手で閉じる)」と1行書く。監査手順の表に加える行の「すること」に、子がすべて閉じているのに親が開いたままのときの扱いも含める |
| D1-1-8 | 低 | spec の審査の変更(`spec-review/SKILL.md` Step 6)、Modified Files | 設計は kiro-spec-requirements / -design / -tasks に `disable-model-invocation: true` を付ける。`spec-review/SKILL.md` Step 6 の3は「後続の段階を作り直し、それぞれレビューする」とあり、AIが後続の段階を生成するように読める文で、この変更のあとは AI が実行できない(所有者がコマンドを打つ)。設計は同じ Step 6 に `approval_history` の手順を足すので、そのときに文を揃えないと、スキルの中で実行できない指示が残る | Step 6 を直すときに、3の「後続の段階を作り直し」を「所有者に、戻る段階のコマンドから順に打ってもらう」のように、所有者がコマンドを打つ形に合わせる |

### 前の段階への指摘

なし。設計に落とす過程で、requirements の不足・曖昧さ・矛盾は見つからなかった(D1-1-7 の要件9.6 の無条件の書き方は、設計側で境界を書けば足りるため、requirements への指摘にはしない)。

- 往復: 1回目 / 高0 中2 低6

## サイクル1 往復2(2026-10-02)

審査の材料: `design.md`(全文。往復1の対応後)、`requirements.md`(全文。承認済み)、`research.md`、`spec.json`、Issue #472 本文(`gh issue view 472`。コメントは読んでいない)、往復1の review と response、`.claude/skills/kiro-spec-init|-requirements|-design|-tasks|kiro-impl/SKILL.md`、`.claude/skills/spec-review/SKILL.md`、`.github/scripts/check-spec-backing.sh`(L13〜14、L74〜79)、`CLAUDE.md`(L63、L99、L115、L126、L131)、`README.md`(L107、L337、L370)、`.claude/` 配下で `ready_for_implementation` と `approvals.tasks.approved` を書く箇所の grep。

往復1の修正の確認:

- D1-1-1: `start` 手順2の表は `approvals.tasks.approved` と tasks.md の `- [ ]` / `- [x]` で3行に分かれ、`ready_for_implementation` を判定に使っていない。表の前半はそれで足りる。ただし、直し方の案の後半(更新の形で `ready_for_implementation` を false にするなら、誰がいつ true に戻すかを本文に書く)は反映されていない。この点は、D1-1-1 の残りとしてではなく、`check-spec-backing.sh` との関係で別の問題になるため、D1-2-1 として書く
- D1-1-2: Modified Files の kiro-spec-requirements の行、Out of Boundary の例外、「Issueの印」の最後の項、Traceability 5.8 の4か所が揃っている。`kiro-spec-design/SKILL.md` L112 と `kiro-spec-tasks/SKILL.md` L65 に merge の記述があることは実ファイルで確かめた。直し方の案の最後(Testing Strategy への追加)は反映されていない(D1-2-4)

要件カバレッジ・境界・設計内の矛盾・実現できない設計: 往復1の確認の結果から変わっていない。往復1で直した箇所が、ほかの節と食い違いを起こしていないことを確かめた(Out of Boundary の例外、Modified Files、Issueの印、Traceability は同じ内容を指している)。

### 申告

往復1の5件から追加は無い。往復1の修正で新しく決めたこと(表の判定に tasks.md のチェックボックスを使う、kiro-spec-requirements に2行足す)は、他にありえた選択肢が小さく、外れても手戻りが小さいため申告しない。

### 指摘

| ID | レベル | 該当箇所 | 内容 | 直し方の案 |
|---|---|---|---|---|
| D1-2-1 | 中 | kiro-spec-init の更新の形(手順3)、`.github/scripts/check-spec-backing.sh` L74〜79 | 更新の形は `ready_for_implementation` を false に戻す。一方、200行を超えるPRの size-check が呼ぶ `check-spec-backing.sh` は、`approvals.*.approved` の3つに加えて `ready_for_implementation == true` を要求し、欠ければ赤にする(L74〜78)。ところが、この値を true にする手順は設計本文にも `.claude/` のどのスキルにも無い(`kiro-spec-tasks/SKILL.md` Step 4 は `approvals.tasks.approved` だけを書く。grep で `ready_for_implementation` を書く箇所は `init.json` の `false` と本設計の手順3だけ)。新しい spec では、既存の spec が true になっているとおり、誰かが習慣で true にしている。更新の形では、設計が true を false に書き戻した上で、戻す手順を決めていないため、更新した spec の実装のPR(spec 駆動なので200行を超えるのが普通)が size-check で止まり、そのとき初めて手で true に直すことになる。D1-1-1 の直し方の案の後半(「誰がいつ true に戻すかを本文に1行書く」)に当たる | 次のどちらかにする。(a) 更新の形の手順3で `ready_for_implementation` に触れず、既存の値を残す(`check-spec-backing.sh` は `approvals.*.approved` も見るため、承認を取り消せば未承認の spec は止まる)。(b) false にするなら、CLAUDE.md のルールの節(本設計が直す「承認の取り消し」の行の近く)に「tasks の承認を spec.json に記録するとき(`approvals.tasks.approved` を true にするとき)に `ready_for_implementation` も true にする」と書き、`start` 手順2の表の「tasks が承認済み」の行の判定には影響しないことを添える。(a) の方が変更が小さい。どちらにしても、Testing Strategy の「スキルと文書の確認」に「更新の形を通した spec.json が、tasks の承認後に `check-spec-backing.sh` の条件(L74〜77)を満たすこと」を1項目足す |
| D1-2-2 | 低 | `start` 手順2 の表 | 表は「requirements が生成済みで未承認」「design が生成済みで未承認」の行を持つが、「requirements が承認済みで design が未生成」「design が承認済みで tasks が未生成」の状態に当たる行が無い。このリポジトリでは承認の記録は次の段階のコマンド(`kiro-spec-design` Step 6、`kiro-spec-tasks` Step 4)が書くため、この状態は普通は現れないが、CLAUDE.md L126 は「承認を記録するときは spec.json に承認者名と日時を残す」と承認時の記録も認めており、生成の途中で止まったときにも現れる。表のどの行にも当たらないと、`/start` を打った所有者に次のコマンドを示せない | 「requirements が承認済みで design が未生成」→ `/kiro-spec-design <feature>`、「design が承認済みで tasks が未生成」→ `/kiro-spec-tasks <feature>` の2行を足す。または表の条件を「次に生成されていない段階のコマンド。その前の段階が未承認なら、審査の記録を読んで承認するよう添える」の1文にまとめる |
| D1-2-3 | 低 | kiro-spec-init の更新の形(Responsibilities & Constraints)、`kiro-spec-init/SKILL.md` Step 0・Step 3・Safety & Fallback「Directory Conflict」 | 更新の形は「引数が `#<N> <feature>` で spec.json があるとき」に動くが、今の kiro-spec-init は `$ARGUMENTS` 全体を説明文として扱い(Step 0「is (or contains)」)、feature 名の衝突は「数字の接尾辞を付けて新しく作る」(Safety & Fallback)と定めている。設計は、この衝突時の扱いを更新の形に置き換えること、`#N` の後ろの語を feature 名とみなす条件(例: `.kiro/specs/<語>/spec.json` がある語だけ。無ければ従来どおり説明文の一部)を書いていない。SKILL.md に写すときに決めれば済むが、決めないと `#N` の後ろに説明を添えた既存の打ち方が「feature が無い」の誤りになる | Responsibilities に「`#N` の直後の1語が `.kiro/specs/` にある feature 名のときだけ更新の形。それ以外は従来どおり説明文として扱う」と書き、Modified Files の kiro-spec-init の行に「Directory Conflict の扱いを、更新の形に当たらないときだけに限る」を添える |
| D1-2-4 | 低 | Testing Strategy「スキルと文書の確認」 | 往復1で足した kiro-spec-requirements の2行(`additional_issues` があるときは既存の要件の番号を残す)と、`start` 手順2の表の判定の確認が、確認の項目に無い。4つ目の項目(grep で古い基準が残っていないこと)と同じ粒度で書ける | 「`kiro-spec-requirements/SKILL.md` に、`additional_issues` があるときの決まりの2行があること」と「`start` の SKILL.md の表が、spec.json の `approvals` と tasks.md のチェックボックスだけで判定していること」を足す |
| D1-2-5 | 低 | `start` 手順2(本文と表の最後の行) | 手順2の本文は「見つかったら、進み具合と次に所有者が打つコマンドを示して終える」とあるが、表の最後の行(tasks がすべて `- [x]`)は「AIが `/ship` で進める」とし、終えない。意味は読み取れるが、SKILL.md に写すときにどちらかに揃える | 本文を「示して終える(タスクがすべて完了しているときだけ、AIが `/ship` で出荷まで進める)」のように、例外を1つ添える |

### 前の段階への指摘

なし。

- 往復: 2回目 / 高0 中1 低4

## サイクル1 往復3(2026-10-02)

審査の材料: `design.md`(全文。往復2の対応後)、`requirements.md`(全文。承認済み)、`research.md`、`spec.json`(issue 472、design 未承認)、Issue #472 本文(`gh issue view 472`。コメントは読んでいない)、往復1・2の review と response、`.github/scripts/check-spec-backing.sh`(全文)、リポジトリ全体で `ready_for_implementation` を書く・読む箇所の grep、steering 3文書。

往復2の修正の確認:

- D1-2-1: kiro-spec-init の更新の形の手順3は「`ready_for_implementation` には触れない」に変わり、理由(true に戻す手順がどのスキルにも無い、false にすると再承認の後も `check-spec-backing.sh` L74-78 で止まる、実装の可否は3段階の承認で判定される)が添えられている。理由の3点を実ファイルで確かめた。(1) grep の結果、このキーを書くのはテンプレート `init.json`(`false`)と各 spec の spec.json だけで、`.claude/` 配下には書く箇所も読む箇所も無い。(2) `check-spec-backing.sh` L74-77 は `approvals.*.approved` の3つと `ready_for_implementation` を and で結んでいるため、更新の形が承認を false に戻せば、既存の値が true のままでも未承認の間は止まり、3段階の再承認が済めば通る。既存の値が false の spec(途中で止まっていた spec)では再承認の後も止まるが、これは新しい spec でも同じ(true にする手順が元から無い)であり、本設計が持ち込んだものではなく、Out of Boundary(200行の検査の判定)に当たる。(3) `start` 手順2の表は `approvals` と tasks.md のチェックボックスだけで判定しており(往復1の修正)、`kiro-impl` も `approvals.tasks.approved` だけを見るため、「実装の可否は3段階の承認で判定される」と食い違わない。直し方の案(a)の内容と一致し、修正は足りている。直し方の案の末尾(Testing Strategy への1項目)は反映されていないが、往復2で低(D1-2-4)として「tasks の確認の項目に入れる」と記録されており、同じ扱いでよい
- D1-2-2〜D1-2-5: 低のまま「記録のみ」。tasks で SKILL.md の文面と確認の項目を書くときに扱うとの記録があり、再び出さない

要件カバレッジ・境界・Compliance Check・設計内の矛盾・実現できない設計: 往復2から本文の変更は手順3の1か所だけであり、その変更がほかの節(`start` 手順2の表、Data Models、Error Handling の「spec.json を先に書く」、Testing Strategy)と食い違いを起こしていないことを確かめた。往復1・2の確認の結果から変わっていない。

### 申告

往復1の5件から追加は無い。往復2の修正(`ready_for_implementation` に触れない)は、他にありえた選択肢(false にして true に戻す決まりを足す)が往復2の記録に書かれており、外れても `check-spec-backing.sh` が止めるだけで手戻りは小さいため申告しない。

### 指摘

なし。

### 前の段階への指摘

なし。

- 往復: 3回で収束 / 未解決: 0件

## サイクル2 往復1(2026-10-10)

審査の材料: `design.md`(全文。Issue #524 のための更新後)、`requirements.md`(全文。サイクル3で収束し、2026-10-10 に所有者が承認)、`research.md`(#524 の節を含む全文)、`spec.json`(issue 472、additional_issues [524]、design 生成済み・未承認、approval_history 6件)、Issue #472 本文と Issue #524 本文(`gh issue view 472` / `gh issue view 524`。どちらもコメントは読んでいない)、steering 3文書、`.kiro/settings/templates/specs/design.md`、`CLAUDE.md`(L73、L112〜125 の観点の表、L141〜142 の着手の箇条)、`README.md`(L336〜386。L341・L374〜379・L384)、`.claude/skills/start/SKILL.md`(全文。Step 5〜7、観点の表 L136〜141、見直しの時点 L259〜266)、`.claude/skills/file-issue/SKILL.md`(全文。L28、L54〜63、L139〜142)、`.claude/skills/ship/SKILL.md`(全文。手順5)、`.claude/skills/kiro-spec-requirements/SKILL.md`(Step 3 L51〜60)、`.claude/skills/kiro-spec-design/SKILL.md`(Step 4 L106〜117)、`.claude/skills/kiro-spec-tasks/SKILL.md`(merge の記述 L28・L68)、`.claude/skills/spec-review/rules/requirements.md`(観点9 L57〜69)、`.github/workflows/codex-review.yml`(L161〜200 の判定の基準の決め方、L240〜247、L264〜293 の決めた方式の観点)、`.github/scripts/extract-decided-method.sh`(全文)、`.github/scripts/check-spec-backing.sh`(L44 の `Spec:` の抜き出し)、`.github/CODEOWNERS`(L16 `/.claude/`)、requirements の review と response(サイクル1〜3)、design の review と response(サイクル1)、`reviews/design-style.md`。`brief.md` は無い。

この往復は、design.md のうち `(#524)` と `(#524 で変更)` の印の付いた節と項目を Issue #524 と requirements の #524 の項目を基準に審査した。印の無い部分は #472 のときに承認・実装済みであり、サイクル1の結論から変えない。印の無い部分との食い違いだけを見た。

- 印の付け方: 概要の段落、作るもの3項目、作らないもの4項目、使う既存の仕組み2項目、見直すきっかけ2項目、決まりの節の1項目、全体の構成の2項目、ファイルの構成の #524 の一覧、処理の流れの新しい図と見直しの時点の箇条、部品の表の3行、start・file-issue・ship・文書の変更の各節の対応する要件の行、spec の生成のスキルの変更の節、データの形の2つの小節、失敗したときの扱いの2項目、テストの方針の #524 の小節、既存の構成の1項目、要件との対応の8行に、印が付いている。印の番号はすべて `additional_issues` にある
- 要件カバレッジ(#524 の分): 要件 2.1(変更)・2.5・2.6・2.7・3.3(変更)・3.4・4.1(変更)・4.3〜4.7・7.8・10.1(変更)・10.8〜10.10 のそれぞれが、`start` の「観点の定義」「観点2と観点3の当てはめ方」「問いがあるときの報告の書式」「問いの出し方と答えの書き足し」「見直しの時点」、file-issue の「着手のときの答えを本文に書き足すとき」、ship の「## AIが決めたこと」、spec の生成のスキルの変更、文書の変更のいずれかに裏付けがある。裏付けが一部足りないものを D2-1-1(2.1 観点2の2つ目の条件の後半)と D2-1-3(10.10 の README の分)に挙げる
- 実測の確認: `extract-decided-method.sh` が `##` と空白のあとに `決めた方式` だけが続く見出しを節の始まりとし、次の1段目か2段目の見出しの手前までを中身とすること(L49〜57、L100〜104)、codex-review が `Refs:` のIssue本文をPRの審査のたびに `gh issue view` で取り直すこと(L176〜185)、「決めた方式」の項目はPR本文に理由があっても High にすること(L282〜285)、所有者の操作のように確かめられない項目は判定しないこと(L276〜277、L286)を実ファイルで確かめた。設計の記述と一致する。PR本文の「- 食い違う spec: `.kiro/specs/...`」の行が `Spec:` の行と取り違えられないことも確かめた(`check-spec-backing.sh` L44 と `codex-review.yml` L168 はどちらも大文字始まりの `Spec:` に直接 `.kiro` が続く形だけを拾う。食い違いの行は小文字の `spec:` で、あとに `` ` `` が入る)
- 境界: 作らないものの4項目(再現テストの決まり、自動レビューに「AIが決めたこと」を確かめさせること、観点の数と観点4の定義、spec 無しのPRで承認済みの本文を直すこと)を、本文が破っていないことを確かめた。観点4の表の文面は今の `start/SKILL.md` L141 と同じである。`codex-review.yml` と `.github/` は #524 の分で変えていない(ファイルの構成の #524 の一覧と、決まりの節の記述が一致する)
- 設計内の矛盾: 観点の表(L303〜308)と当てはめ方の手順(L314〜321)の食い違いを D2-1-1 に、部品の表と部品の見出しと要件との対応の表の番号の食い違いを D2-1-8 に挙げる

### 申告

**1. spec 無しで変えた動きの記録を、マージ済みのPRの本文にだけ置き、次に spec を更新するときに `gh pr list` で探して反映する** — 「spec の生成のスキルの変更」、「データの形」の「PR本文の「## AIが決めたこと」の節の形」、見直すきっかけの最後の項目

- Issue の記載: なし(Issue #524 は spec の本文の扱いに触れていない。requirements 4.7 と範囲の前提が「PR本文に書く」「次に更新するときに直す」と決め、探す手順は design に申し送られた。R3-3-4)
- 決めたこと: 食い違いは `- 食い違う spec: ` で始まる決まった形の1行でPR本文に書く。kiro-spec-requirements と kiro-spec-design が、更新のとき(`additional_issues` があるとき)にマージ済みのPRを一覧し、その行を持つPRを探して本文に反映する
- 他にありえた選択肢: spec のディレクトリに食い違いの記録のファイル(例: `pending-changes.md`)を置き、spec 無しのPRで追記する(codex-review は `Spec:` のPRで spec のディレクトリの `*.md` をすべてつなげて判定の基準にするため、記録が基準に混ざる。#341 と同じ形)。spec.json に食い違いの配列を足す(spec 無しのPRが spec.json を変えることになる)。食い違いが出た時点で、その spec の更新のIssueを起票する
- 外れていた場合: 記録がGitHubのPR本文にしか無いため、PRの本文を書き換えると記録が消える。探す手順が機能しないとき(D2-1-4)は、食い違いが拾われず、承認済みの spec の本文がコードと食い違ったまま次の審査と自動レビューの基準になる。設計の「失敗したとき」は、探せなかったことを生成の報告に書くことで補う

**2. 問いに答えていない返事(別の話、どちらとも読める返事)は「答えで決まらない問い」として扱い、聞き直さずに判断を「spec が要る」に改める** — 「問いの出し方と答えの書き足し」の1と3

- Issue の記載: なし(requirements 4.4 は「答えを受けても…決められないものが残ったら」と書くが、答えていない返事の扱いは design が決めた)
- 決めたこと: 所有者の返事を問いごとに読み、答えになっていない問いは決まらなかったものとして、受けた答えを本文に書き足したうえで spec に改め、コマンドを依頼する
- 他にありえた選択肢: 答えていない問いだけを1回聞き直す(requirements 2.6 の「1回」を、同じ時点の問いの出し直しには数えない読み方)。所有者が「全部推奨で」のように答えなかったときは推奨で進む。所有者の返事が問いへの答えでないときは、答えが来るまで待つ
- 外れていた場合: 所有者が問いに対して確認の質問を返しただけで、Claude が spec に改めてコマンドを依頼する。所有者は spec 1本分の手間を負い、Issue #524 の「時間と費用」に響く。design で聞き直しの道を1つ足せば直るので、手戻りは小さいが、所有者の運用に直接見える

**3. 所有者の答えの書き足しは、Issueの本文を丸ごと取り出して書き足し、`gh issue edit --body-file` で本文全体を置き換える形にする。節が無ければ本文の末尾に `## 決めた方式` を作る。読み直して食い違えば、元に戻さずに止まる** — file-issue の変更の「着手のときの答えを本文に書き足すとき」、「失敗したときの扱い」の最後の2項目

- Issue の記載: なし(requirements 4.3 と 10.8 が「決めた方式」の節に書き足すことまで決めた)
- 決めたこと: 本文を scratchpad に書き出して直し、全文を置き換える。置き換えたあとに読み直し、足した箇条が無いか、ほかの行が変わっていれば、実装を始めず、違いを所有者に示して止まる。本文を元に戻す操作は Claude の判断でしない。節を新しく作るときは、起票の決まりの書式の順(「決めた方式」は「やらないこと」の前)ではなく本文の末尾に置く
- 他にありえた選択肢: 節の位置を起票の決まりの書式の順に合わせる。書き足しの直前に本文を読み直し、`/start` で読んだ本文と違っていれば書き足さない(所有者が同じ時間に本文を直していたときの上書きを防ぐ)。食い違いが出たときに、書き足す前の本文に戻す
- 外れていた場合: 所有者が `/start` のあとに本文を直していると、その直しが Claude の書き足しで消える。読み直しで気づけるのは、Claude が書き足す前に取った本文との違いだけである。節の位置は、自動レビューの抜き出しには影響しない(見出しの形だけを見る)

**4. 問いを出す前に、ブランチを作り `session.sh claim` で記録する** — `start` Step 7 の「spec 不要で、所有者に尋ねる問いがある」、処理の流れの図の B

- Issue の記載: なし
- 決めたこと: 答えを待つ前にブランチを作って記録する。答えで決まらず spec に改めるときは、作ったブランチをそのまま使い、作り直さない(今の `start/SKILL.md` が spec の判断でもコマンドの依頼の前にブランチを作って記録する作りに合わせた)
- 他にありえた選択肢: 答えを受けてから(実装を始める直前に)ブランチを作る
- 外れていた場合: 所有者が答えずに会話が途切れると、Issue #N に紐づいた空のブランチと記録が残り、次の `/start #N` の Step 1.5 が「続きから進めるか」を尋ねる。手戻りは無く、所有者に1つ問いが増えるだけである

### 指摘

| ID | レベル | 該当箇所 | 内容 | 直し方の案 |
|---|---|---|---|---|
| D2-1-1 | 中 | `start` の「観点2と観点3の当てはめ方」の1と3、観点の表の観点2(#524 で変更) | requirements 2.1 の観点2の2つ目の条件は、「「決めた方式」に沿ったまま作れる作り方が1つも無い変更」と「承認済みの spec が作ると決めた範囲の中で作れる作り方が1つも無い変更」の2つを別々に当たるとしている。観点の表(L306)もそのとおり「または」でつないでいる。ところが当てはめ方の手順は、1で「決めた方式」から外れる作り方だけを候補から外し、3で「候補が残らず、「決めた方式」に沿ったまま作れる作り方も、承認済みの spec の「作るもの」の範囲の中で作れる作り方も無いときは」当たるとしており、承認済みの spec の範囲の条件は、「決めた方式」に沿える候補が1つも残らなかったときにしか評価されない。「決めた方式」には沿えるが、沿える作り方がどれも承認済みの spec の「作るもの」の範囲の外に出る変更(spec が作ると決めた範囲を広げる直し)は、1で候補が残るので3に入らず、4・5で問いの候補が無ければ「当たらない」になり、spec 無しで進む。この手順は SKILL.md の Step 5 にそのまま写され、文書なので自動テストも無い。requirements 2.1 のこの条件は、承認済みの範囲を変える変更を要件5(更新か新しい spec か)に進めるために置かれたものである(R3-1-1、R3-2-2 の修正) | 手順を条件ごとに分ける。1で、「決めた方式」から外れる作り方を候補から外すのと同じ段で、Issueに関わる承認済みの spec があるときは、作り方ごとにその spec の design.md の `### 作るもの` の範囲の中で作れるかを書く。3を「(a) 「決めた方式」に沿ったまま作れる作り方が1つも無いとき、または (b) 承認済みの spec があり、その「作るもの」の範囲の中で作れる作り方が1つも無いときは、観点2の2つ目の条件に当たる。(a) と (b) は別々に見る」の形にする。6の根拠の欄に書く内容(沿えない項目か、外れる範囲の箇所)は条件 (a) (b) に対応させる。「スキルと文書の確認(#524 の分)」の2つ目の項目に、(a) と (b) が別々の判定として書かれていることの確認を加える |
| D2-1-2 | 中 | 「spec の生成のスキルの変更」の変える点(`(#N で変更)` を付ける。N は `additional_issues` の最後の番号)、`.claude/skills/spec-review/rules/requirements.md` 観点9(L57〜69)、ship の変更の「更新した spec のPR」の本文、kiro-spec-tasks の merge | 設計は、以前の spec 無しのPRで変わった動きを、次の更新のときに本文に反映し、直した項目に `(#N で変更)` を付ける。N は更新のきっかけの新しいIssueである。しかし、その動きを変えたのは別のIssue(食い違いを書いたPRの `Refs:` のIssue。以下 M)であり、Issue #N の本文には書かれていない。今の審査の決まり(`rules/requirements.md` L67、L69。本設計の #472 の部分が入れたもの)は、`(#N)` の印の項目を Issue #N の本文を基準に見て、本文に無ければ「勝手な追加」か「印の誤り(印の番号が、その要望の書かれたIssueと違う)」として指摘する。したがって、この反映を行うたびに、審査役が中の指摘を出し、メインセッションが却下で返す往復が必ず起きる。また、出荷の手順(`ship/SKILL.md` L50〜51)は更新した spec のPRの本文に「このPRが実装するのは `(#N)` の印の付いた項目です。印の無い項目は以前のPRで実装済みです」と書き、kiro-spec-tasks は印の付いた項目からタスクを作るため、すでに出荷済みの動きが Issue #N のタスクとして生成され、codex-review も `Spec:` の `*.md` を基準にその実装を探す。この印の使い方は、CLAUDE.md の印の決まり(「追加のIssue #N のために足した」「直した」)とも意味が合わない | 反映した項目には、追加のIssueの印と区別できる印を付ける。例: 項目の末尾に `(PR #<番号> で変更済み)` を付け、印の決まり(CLAUDE.md の「Issueの印」と kiro-spec-init の節の「Issueの印」)にこの印を1行足す(「spec 無しのPRで変わった動きを更新のときに反映した項目。実装は済んでいる」)。`.claude/skills/spec-review/rules/requirements.md` の観点9の表にこの印の行を足し、審査役はこの印の項目を「そのPRの本文の食い違いの行と一致するか」で見て、取りこぼしと勝手な追加の判定の対象にしないことを書く(審査役は `gh issue view` しか実行できないため、PRの本文は読めない。一致の確認は、項目の文がPR本文の行の `<このPRで変えた動き>` と合うかを、design.md か research.md に写した行で見る形にするか、確認の対象から外すかを決める)。ship の「更新した spec のPR」の本文の文を「このPRが実装するのは `(#N)` の印の付いた項目です。印の無い項目と `(PR #… で変更済み)` の項目は以前のPRで実装済みです」に直す。kiro-spec-tasks は merge の記述(L68)に従うため、この印の項目からタスクを作らないことを、kiro-spec-requirements と kiro-spec-design に足す1行と同じ場所(kiro-spec-tasks)にも1行足すか、設計の「作らないもの」の生成の手順の例外に kiro-spec-tasks の1行を加える。ファイルの構成の #524 の一覧に `.claude/skills/spec-review/rules/requirements.md` と(必要なら)`kiro-spec-tasks/SKILL.md` を加え、決まりの節の「`.claude/` と CLAUDE.md と README だけ」との整合を保つ |
| D2-1-3 | 中 | 文書の変更の「Issue #524 の分」の README の2項目(L557〜558)、要件 10.10 | requirements 10.10 は「CLAUDE.md と README に、…問いがあるときは、Claude が答えを待つことと、答えをIssueの本文の「決めた方式」の節に書き足すことを書く」と定める。設計の CLAUDE.md の分(L556)は両方を含むが、README の `/start` の行に足す文は「AIが決められないことがあれば、推奨を付けた問いを1回出し、答えを待ってから実装する」で、答えをIssueの本文に書き足すことが無い。「どの観点にも当たらない」の行も「同じ扱いを足す」としている。テストの方針の確認(L638)も「問いがあるときの扱いが添えてあること」までで、書き足しの記述は確かめない。tasks は設計の文面からタスクを作るため、README は 10.10 の後半を満たさないまま出荷される。所有者は README を読んで、Issueの本文が書き換わることを知らずに答える | README の2行に足す文を「AIが決められないことがあれば、推奨を付けた問いを1回出し、答えを待つ。答えはAIがIssueの本文の「決めた方式」に書き足し、そのあと実装する」のように、書き足しまで含む形にする。テストの方針の確認の項目に「README の2行に、答えをIssueの本文の「決めた方式」に書き足すことが書かれていること」を加える |
| D2-1-4 | 中 | 「spec の生成のスキルの変更」の変える点の1行(`gh pr list --state merged --limit 1000 --json number,title,body` を実行し、本文に…で始まる行を持つPRを選ぶ) | このコマンドは、マージ済みのPR(今の時点で300件以上)の本文をすべて1つの JSON で返す。このリポジトリのPR本文は検証の結果や変更の説明を含み1件で数KBあるため、出力は数百KB以上になる。Claude Code の Bash の結果は一定の長さで切り詰められるので、Claude が出力を読んで行を探す形では、切り詰められた範囲より前のPRしか見えず、古いPRの食い違いの行が拾われない。切り詰めは出力の末尾に注記が付くだけで、拾い漏れがあったことは生成の報告にも審査にも現れない(設計の「失敗したとき」はコマンドの失敗だけを扱う)。この1行は SKILL.md にそのまま写され、次に spec を更新するときに初めて動く | コマンドの中で絞り込み、該当するPRの番号と行だけを出す形にする。例: `gh pr list --state merged --limit 1000 --json number,body --jq '.[] | select(.body | contains("- 食い違う spec: \`.kiro/specs/<feature>/")) | {number, lines: [.body | split("\n")[] | select(startswith("- 食い違う spec: \`.kiro/specs/<feature>/"))]}'`(`--jq` は gh に組み込みで、ホストの jq に依らない)。`--limit` の上限に達した(返った件数が 1000 のとき)ら、それより古いPRを見ていないことを生成の報告に書くことも1行に含める。見直すきっかけの最後の項目に、この絞り込みが行の形に依ることを添える |
| D2-1-5 | 低 | `start` Step 5 の「既存の spec の範囲か」、観点の表の観点2(2つ目の条件の後半)、requirements 2.1 | requirements 2.1 は「承認済みの spec が作ると決めた範囲を変える変更では、Claude は、要件5の…決め方(その spec を更新するか、新しい spec を作るか)で進め方を決める」とする。設計の Step 5 の決め方は「変更する動きが既存の spec の design.md の「作るもの」に書かれた範囲に入るなら「更新」、入らなければ「新しい spec」」である。観点2の2つ目の条件の後半で spec が要ると判断した変更は、定義により「作るもの」の範囲の中で作れないので、この決め方では常に「新しい spec を作る」になり、「その spec を更新する」(範囲を広げる更新)に進む道が無い。#472 のときに承認された決め方であり、Claude はどちらかに必ず進めるので実装には影響しないが、requirements の「更新するか新しい spec を作るか」の文と、設計の決め方の結果が合わない | Step 5 の2つ目に「変更する動きが「作るもの」の範囲に入るか、範囲を広げるだけで既存の「作るもの」を変えないなら「更新」。既存の「作るもの」と別の機能なら「新しい spec」」のように、範囲を広げる変更の行き先を1つ決めて書く。requirements の文のままにするなら、D2-1-1 の直しの中で、(b) の判定の結果は Step 5 で「新しい spec」になることを明記し、所有者に見えるようにする |
| D2-1-6 | 低 | 「プロジェクトの決まりを守っているか」の「使う外部の機能がこのリポジトリで使えるか」 | この項目はサブIssue(#472 の分)だけを書いている。#524 の分で新しく頼る外部の機能は、ボットの資格(DogisRiki-bot)で所有者が起票したIssueの本文を `gh issue edit --body-file` で書き換えられることと、`gh pr list --state merged --json` でマージ済みのPRの本文を一覧できることである。research.md(「Issueの本文を書き足す手段」)には、2026-10-09 に #507 の本文を `gh issue edit` で書き換えた実績が書かれているが、design.md のこの項目には現れない。実装には影響しないが、7項目目は「いつ何をどう確かめたか」を書く欄である | 項目に #524 の分を1行足す。例: 「(#524)ボットの資格で所有者のIssueの本文を書き換えられることは、2026-10-09 に #507 の本文を `gh issue edit` で書き換えて確かめた。`gh pr list --state merged --json` は gh 2.97.0 で使える」 |
| D2-1-7 | 低 | 「spec の生成のスキルの変更」の「失敗したとき」 | 「`gh pr list` が失敗したら、Claude は生成を止めず、検索できなかったことを生成の報告に書く。spec の審査で、審査役が食い違いの拾い漏れを指摘できるようにするためである」とあるが、審査役(spec-reviewer)が実行できる Bash は `gh issue view` だけで、PRの本文を読めない。審査役は、生成の報告も読まない(読むのは spec の本文、Issue本文、前回の記録、リポジトリのファイル)。したがって、この理由のとおりには働かない。実装には影響しない | 理由を「所有者が、更新した spec を承認するときに、拾い漏れがありうることを知るためである」に直し、検索できなかったことを生成の報告だけでなく requirements.md の「追加の要望」の節の直下か design.md の既存の構成の節に1行残す形にする。審査役に読ませたいなら、research.md の #524 の節に書くことを決める |
| D2-1-8 | 低 | 部品の表の start の行、start の節の「対応する要件」の行、「要件との対応」の表の #524 の行 | 部品の表の start の行は「(#524 で 2.5–2.7, 3.4, 4.3–4.7, 7.8 を追加)」とし 4.5 と 4.7 を含むが、start の節の「対応する要件」は 4.5・4.7 を含まず(4.3、4.4、4.6 まで)、同じ表の ship の行が 4.5・4.7 を持つ。「要件との対応」の表は「3.3, 3.4(#524 で変更)」「4.1, 4.3, 4.4(#524 で変更)」とまとめているが、3.4・4.3・4.4 は #524 で足した項目(印は `(#524)`)で、変更ではない。意味は読み取れ、実装には影響しない | 部品の表の start の行を「4.3, 4.4, 4.6」に直す。「要件との対応」の表の2行を「3.3(#524 で変更), 3.4(#524)」「4.1(#524 で変更), 4.3, 4.4(#524)」のように、印を項目ごとに付ける |

### 前の段階への指摘

なし。D2-1-1〜D2-1-4 は、いずれも requirements の定めを design がどう実現するかの問題で、requirements に戻る必要は無い。D2-1-5 は requirements 2.1 の文と #472 のときに承認した設計の決め方の間の食い違いだが、設計側で行き先を1つ書けば足りる。

- 往復: 1回目 / 高0 中4 低4

## サイクル2 往復2(2026-10-10)

審査の材料: `design.md`(全文。往復1の対応後)、`requirements.md`(全文。承認済み)、`spec.json`(issue 472、additional_issues [524]、design 生成済み・未承認)、Issue #472 本文と Issue #524 本文(`gh issue view 472` / `gh issue view 524`。どちらもコメントは読んでいない)、往復1の review と response、`.claude/skills/spec-review/rules/requirements.md`(観点9 L55〜70)、`.claude/skills/kiro-spec-tasks/SKILL.md`(Step 2 の merge の記述 L68、Step 3 の coverage の確認 L75、Safety の「Incomplete Requirements Coverage」L191〜193)、`.claude/skills/ship/SKILL.md`(手順5 L39〜52)、`CLAUDE.md`(「Issueの印」L174〜184)、`README.md`(L341、L384)、`research.md`(食い違いの行の形 L177)。`brief.md` は無い。

往復1の修正の確認:

- D2-1-1: 「観点2と観点3の当てはめ方」の1は、承認済みの spec があるときに作り方ごとに「作るもの」の範囲の中で作れるかを書く形になり、3は (a)「決めた方式」と (b) 承認済みの spec の範囲に分かれ、「(a) に当たらなくても (b) を当てはめる」「承認済みの spec が無いときは (b) を当てはめない」と別々の判定であることが書かれている。6の根拠は (a)(b) ごとに対応し、テストの方針の確認(L639)にも (a) と (b) が別々の判定であることの確認が入った。観点の表(L306)との食い違いは無くなった。修正は足りている
- D2-1-2: 新しい印 `(PR #<番号> で変更済み)` が、「Issueの印」(L444)、spec の審査の変更の観点9(L491)、ship の更新した spec のPRの文(L477)、kiro-spec-tasks の1行(L502〜503)、生成のスキルの1行(L500)、CLAUDE.md の分(L560)、ファイルの構成の #524 の一覧(L157〜158)、作らないものの例外(L61)、テストの方針(L644)に同じ形で現れる。`rules/requirements.md` の観点9の今の表(L59〜64)に、この印の行を足せば判定から外す形になることと、kiro-spec-tasks の merge の記述(L68)が実在することを実ファイルで確かめた。`(PR #… で変更済み)` の項目からタスクを作らなくても、既存の受入基準に対する `[x]` のタスクが merge で残るため、kiro-spec-tasks の coverage の確認(L75)で未対応の要件にはならない。決まりの節の「`.claude/` と CLAUDE.md と README だけ」(L86)と、#524 の一覧(L151〜160)は一致している。修正は足りている
- D2-1-3: README の2行(L563〜564)に、答えをIssueの本文の「決めた方式」に書き足すことが入り、テストの方針の確認(L646)にも入った。README L341 と L384 の今の文は設計が引用するとおりである。修正は足りている
- D2-1-4: `--jq` でコマンドの中で絞り込む形(L500)になった。jq の式(`select(.body | contains(...))`、`split("\n")[]`、`{number, lines: [...]}`)は jq の文法として成り立ち、検索する文字列は「データの形」の食い違いの行の形(L592)と research.md L177 の行の先頭に一致する。GitHub の PR の `body` は空のとき空文字列で返るため、`contains` が null で失敗することは無い。絞り込みの形は足りている。ただし、この形にしたことで、同じ1行の中の「返ったPRの数が上限の1000に達したときは」の条件が観測できなくなった。これを D2-2-1 に挙げる
- D2-1-5〜D2-1-8: 低のまま「記録のみ」。再び出さない

要件カバレッジ・境界・決まりの節・実現できない設計: 往復1の修正で変わった箇所(当てはめ方の1・3・6、印の一覧、ship、spec の審査の変更、生成のスキルの変更、文書の変更の README の2行、ファイルの構成、部品の表、テストの方針)が、ほかの節と食い違いを起こしていないことを確かめた。作らないもの(L51〜54、L61)を本文が破っていないことも変わらない。往復1の確認の結果から、D2-2-1 と D2-2-2 のほかに変わった点は無い。

### 申告

**1. `(PR #… で変更済み)` の印の項目を、審査役の取りこぼしと勝手な追加の判定から外し、PRの動きと合っているかも判定しない** — 「spec の審査の変更」の観点9の項(L491)、「Issueの印」(L444)

- Issue の記載: なし(Issue #524 は spec の本文の扱いに触れていない。requirements 4.7 がPR本文に食い違いを書くことまで決め、更新のときの反映と審査は design が決めた)
- 決めたこと: 更新のときに生成のスキルがマージ済みのPRから反映した項目には `(PR #<番号> で変更済み)` を付け、審査役はこの印の項目をどのIssueの本文とも照らさず、PRの本文の行とも照らさない
- 他にありえた選択肢: 生成のスキルが、反映の根拠にしたPRの食い違いの行を research.md の #524 の節か requirements.md の「追加の要望」の節の直下に写し、審査役はその行と項目の文が合うかを見る(審査役は `gh issue view` しか実行できないため、リポジトリのファイルに写すしかない)。印に Issue の番号(`Refs:` のIssue M)も含め、審査役が `gh issue view M` で本文と照らす
- 外れていた場合: 生成のスキルが、どのIssueにも無い動きを `(PR #… で変更済み)` の印を付けて本文に入れても、審査役は指摘しない。所有者は、更新した spec を承認するときに、この印の項目をPRの本文と自分で照らすことになる。印の無い項目と `(#N)` の項目には審査の網があるので、網から外れるのはこの印の項目だけである

### 指摘

| ID | レベル | 該当箇所 | 内容 | 直し方の案 |
|---|---|---|---|---|
| D2-2-1 | 中 | 「spec の生成のスキルの変更」の変える点の1行(L500。`--jq` で絞り込むコマンドと、「返ったPRの数が上限の1000に達したときは、Claude は、それより古いPRを見ていないことを生成の報告に書く」) | 往復1の D2-1-4 の修正で、コマンドは `--jq` の `select` で食い違いの行を持つPRだけを出す形になった。この出力には、該当したPRの番号と行だけが含まれ、`gh pr list` が返したPRの総数は含まれない。したがって、同じ1行の「返ったPRの数が上限の1000に達したとき」を、Claude は出力から判定できない。この1行は SKILL.md にそのまま写され、文書なので自動テストも無く、テストの方針の確認(L645)は「エラーにならず、食い違いの行が無ければ何も出ないこと」までしか見ない。マージ済みのPRが1000件を超えたとき(今は300件台で、すぐには起きない)に、古いPRの食い違いが拾われず、拾われなかったことを生成の報告に書く道も働かない。D2-1-4 の修正自体は正しく、その修正で条件の観測の手段が無くなった | jq の出力に総数を含める。例: `--jq '{total: length, hits: [.[] | select(.body | contains("- 食い違う spec: \`.kiro/specs/<feature>/")) | {number, lines: [.body | split("\n")[] | select(startswith("- 食い違う spec: \`.kiro/specs/<feature>/"))]}]}'` とし、本文の条件を「出力の `total` が 1000 のときは」に直す。または、総数を得る別のコマンド(`gh pr list --state merged --limit 1000 --json number --jq length`)を1行に添える。テストの方針の確認(L645)に「出力に総数が含まれること」を加える |
| D2-2-2 | 低 | 「観点2と観点3の当てはめ方」の6(L320)、requirements 2.5 | requirements 2.5 は、観点2の2つ目の条件に当たると判断するときの根拠を「沿えない「決めた方式」の項目か、外れる承認済みの spec の範囲の箇所と、それに沿ったまま作れる作り方が無い理由」と定める。6は (a) で「沿えない「決めた方式」の項目」、(b) で「外れる spec の「作るもの」の箇所」を書くとし、「沿ったまま作れる作り方が無い理由」が無い(観点3には「その理由」がある)。1で作り方ごとに「作るもの」の範囲の中で作れるかを書くので、理由の材料はそろっており、SKILL.md に写すときに1語足せば済む | 6の (a)(b) に「と、それに沿ったまま作れる作り方が無い理由(1で挙げた作り方ごとの可否)」を添える |

### 前の段階への指摘

なし。

- 往復: 2回目 / 高0 中1 低1

## サイクル2 往復3(2026-10-10)

審査の材料: `design.md`(全文。往復2の対応と、書き方の点検の3回目の直しのあと)、`requirements.md`(全文。承認済み)、`spec.json`(issue 472、additional_issues [524]、design 生成済み・未承認)、Issue #472 本文と Issue #524 本文(`gh issue view 472` / `gh issue view 524`。どちらもコメントは読んでいない)、往復1・2の review と response、`reviews/design-style.md`(3回の点検の記録)、`research.md`(食い違いの行の形 L177)、`.claude/skills/file-issue/SKILL.md`(本文の書式 L50〜62)。`brief.md` は無い。

往復2の修正の確認:

- D2-2-1: 「spec の生成のスキルの変更」の1行(L500)の jq の式は `'{total: length, hits: [.[] | select(.body | contains(...)) | {number, lines: [...]}]}'` になった。`length` は `gh pr list --json` が返す配列の要素数を返すので、`total` は返ったPRの総数、`hits` は食い違いの行を持つPRの番号と行になり、jq の文法としても成り立つ。本文の条件は「`total` が上限の1000のときは、Claude は、それより古いPRを見ていないことを生成の報告に書く」に直り、出力から判定できる。「返ったPRの総数(`total`)と、食い違いの行を持つPRの番号とその行(`hits`)だけを得る」の説明も式と合う。テストの方針の確認(L645)は「`total` にマージ済みのPRの数が出て、食い違いの行が無ければ `hits` が空になること」になり、出力に総数が含まれることを確かめる形になった。審査役は `gh pr list` を実行できないため、実際の出力(`{"hits":[],"total":258}`)は response の記録(2026-10-10 に実行)に依る。修正は足りている
- D2-2-2: 低のまま「記録のみ」。再び出さない
- 書き方の点検で直った「3つの材料」の1つ目(L311): 「今の動きのまま変えないこと」になり、requirements 2.7 の1つ目(今の動きのまま変えないこと)、観点の表の観点2・3の「3つの材料」の参照、当てはめ方の4の「決めた材料(今の動き、…)」、「AIが決めたこと」の節の形(L591)の「今の動きのまま」と合う

要件カバレッジ・境界・決まりの節・設計内の矛盾・実現できない設計: 往復2からの本文の変更は、L500 の1行と L645 の確認の項目と、書き方の点検による文の直し(L311 を含む)である。これらが、見直すきっかけの最後の項目(L81。行の形で検索する)、「データの形」の食い違いの行の形(L592)、research.md L177、「失敗したとき」(L507)と食い違いを起こしていないことを確かめた。作らないもの(L51〜54、L61)を本文が破っていないことも変わらない。往復1・2の確認の結果から、下の低2件のほかに変わった点は無い。

### 申告

往復1の4件と往復2の1件から追加は無い。往復2の修正(jq の出力に `total` を含める)は、他にありえた選択肢(総数を得る別のコマンドを添える)が往復2の記録に書かれており、外れても生成の報告の1行が欠けるだけで手戻りは無いため申告しない。

### 指摘

| ID | レベル | 該当箇所 | 内容 | 直し方の案 |
|---|---|---|---|---|
| D2-3-1 | 低 | `start` の「観点の定義」の表の下の「3つの材料」(L311)、requirements 2.7 | requirements 2.7 の2つ目の材料は「Issueの本文の「どうなれば解決か」に書かれた目的」である。設計の L311 は「Issueの本文の「やりたいこと」と「どうなれば解決か」に書かれた目的」とし、「「どうなれば解決か」の節が無いIssueでも、Claude は「やりたいこと」の節から目的を読む」と広げている。起票の決まり(`file-issue/SKILL.md` L62)は「中身の無い見出しは省く。「困っていること」と「やりたいこと」の少なくとも一方は書く」としており、「どうなれば解決か」の無いIssueはありうるので、広げたこと自体は筋が通る。ただし、requirements の文より材料の出どころが1つ増えており、本文はそれを requirements との違いとして示していない(書き方の点検の記録も「細部が違う」と残している)。「やりたいこと」も所有者が決めた文なので、Claude がそこから決めた動きが所有者の意図と外れるおそれは小さく、実装には影響しない | L311 の2つ目に「requirements 2.7 は「どうなれば解決か」だけを挙げるが、この節の無いIssueがあるため、「やりたいこと」も目的の出どころに含める」のように、広げた理由を1文添える。または requirements 2.7 の文に合わせて「どうなれば解決か」だけにし、節が無いときの扱いを別の1文で決める |
| D2-3-2 | 低 | 「spec の生成のスキルの変更」の変える点の1行(L500) | コマンド全体を1組のバッククォートで囲んだ中に、jq の検索文字列のバッククォート(`` `.kiro/specs/<feature>/ ``)が2つ入っている。Markdown ではコード片は次のバッククォートで閉じるため、この行はコード片の範囲が崩れて表示される(research.md L177 は `\`` で逃がしている。往復1の直し方の案も同じ)。Claude は生の文を読むため、SKILL.md に写すときの文字列には影響しない | コマンド全体を二重のバッククォート(`` `` … `` ``)で囲むか、コマンドをコードブロックに移す |

### 前の段階への指摘

なし。

- 往復: 3回で収束 / 未解決: 0件
