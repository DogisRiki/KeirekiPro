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

## サイクル3 往復1(2026-10-11)

審査の材料: `design.md`(全文。Issue #531 のための更新後)、`requirements.md`(全文。サイクル6で収束し、2026-10-11 に所有者が承認)、`research.md`(#531 の節 L98〜120、L205〜225)、`spec.json`(issue 472、additional_issues [524, 531]、design 生成済み・未承認、approval_history 9件)、Issue #472・#524・#531 の本文(`gh issue view 472` / `524` / `531`。いずれもコメントは読んでいない)、steering 3文書、`CLAUDE.md`(ワークフローの「着手」の箇条、「Issueの印」)、`.claude/skills/start/SKILL.md`(全文。Step 1.5 の表 L77〜97、Step 5 L123〜168、Step 6 L170〜215、Step 7 L217〜257)、`.claude/skills/file-issue/SKILL.md`(全文。Step 2 L73〜75、本文の書式 L43〜63、書き足しの節 L139〜187、制約 L189〜192)、`.claude/skills/ship/SKILL.md`(L26、L40〜52)、`.claude/scripts/parallel/session.sh`(全文。使い方の注記 L1〜119、`_KP_SS_PL_ACTIVE` L178〜250、`check-start` の leftovers の spec の探し方 L694〜714、`check-spec` L1365〜1507、振り分け L1521〜1534)、`.claude/scripts/parallel/lib.sh`(`kp_state_dir` L32〜37、`kp_live_folders` L92〜106、`kp_folder_gone` L121〜135、`kp_session_id` L196〜208、`_kp_lock` L323〜335)、`.claude/scripts/parallel/tests/test-session.sh`(冒頭の注記 L1〜19)、`.claude/hooks/tests/test-session-registry.sh`(SessionEnd で記録が消えること L196〜200)、`.github/scripts/audit-issue.sh`(L46)、`.github/scripts/container-scan-issue.sh`(L47)、`.github/scripts/lib-ledger-issue.sh`(存在の確認)、`.github/workflows/guardrails.yaml`(L157〜170。`.claude/scripts/parallel/tests/**` は行数の計上から外すだけで、CI はこのテストを流さない)、requirements の review と response(サイクル4〜6)、design の review と response(サイクル1・2)、`reviews/design-style.md`(2026-10-11T12:13:05Z の点検)。`brief.md` は無い。

この往復は、design.md のうち `(#531)` と `(#531 で変更)` の印の付いた節と項目を、Issue #531 と requirements の #531 の項目(2.8、3.3、10.11、10.12、要件11)を基準に審査した。印の無い部分と `(#524)` の部分は承認・実装済みであり、サイクル1・2の結論から変えない。印の付いた部分と、それがほかの節と食い違わないかを見た。

- 印の付け方: 概要の段落、作るもの2項目と持つもの4項目、作らないもの4項目と持たないもの1項目、使う既存の仕組み2項目、見直すきっかけ3項目、決まりの節の1項目、ファイルの構成の #531 の一覧、処理の流れの新しい図、部品の表の2行と start・file-issue・文書の変更の各節の対応する要件の行(`#531 で変更`)、start の Step 5.5・報告の書式・答えを受けたときの3つの小節、当てはめ方の3の (b) の箇条、file-issue のまとめるときの節、session.sh active-issues の節、データの形の2つの小節、失敗したときの扱いの3項目、テストの方針の2つの小節、出荷後の確認の1項目、要件との対応の8行に、印が付いている。印の番号はすべて `additional_issues` にある
- 要件カバレッジ(#531 の分): 2.8 は「観点2と観点3の当てはめ方」の3の (b) の箇条に、3.3 は「まとめる提案があるときの報告の書式」に、10.11 は file-issue の「まとめるときに本文を書き換えるとき」と例外の参照に、10.12 は文書の変更の「Issue #531 の分」に、11.1〜11.17 は Step 5.5・報告の書式・答えを受けたとき・file-issue・`active-issues`・失敗したときの扱いに裏付けがある。11.12 の後半(まとめたあとのPRの `Closes` に閉じたIssueを書かない)だけは、どの部品にも当たる文が無い(D3-1-6)。11.4 の「spec があるIssue」の実現のしかたに穴がある(D3-1-1)
- 実測の確認: `session-registry.sh` は SessionEnd でそのセッションの記録 `sessions/<ID>.json` を消す(`test-session-registry.sh` L196〜200 がそれを確かめている)。`is_active` は `sessions/` の記録を起点に `issues/` の記録と突き合わせる(session.sh L231〜236)ので、記録が消えたセッションは作業中に数えられない。`kp_state_dir` は `git rev-parse` を、`kp_live_folders` は `git worktree list` を呼ぶ(lib.sh L34、L95)。`check-start` は、すべての作業フォルダの `.kiro/specs/*/spec.json` を読んで `issue` と `additional_issues` を突き合わせている(session.sh L701〜711)。ラベル `audit` `container-vuln` を付けるスクリプトは設計の記述のとおりで、`blocked` は research.md L118 のとおり 2026-10-11 時点で2件に付いている。`gh issue close --reason "not planned" --comment` の実績は research.md L103 に日付と版がある
- 境界: 作らないもの(#531 の4項目と持たないものの1項目)を本文が破っていないことを確かめた。file-issue の Step 2 は変えていない。まとめないという答えはどこにも残さない(Step 7 の2)。相手探しは「新しい spec」「spec を直す」のときだけである(Step 5.5 の1)。「どの spec を直すか」の決め方は Step 5 のままである。`session.sh` の変更は `active-issues` の追加と振り分け・注記・誤りの文だけで、ほかのサブコマンドと記録の形は変えていない
- 決まりの節: #531 の行(`.claude/` と CLAUDE.md だけ、`.github/` を変えない)は、ファイルの構成の #531 の一覧と一致する。7項目目に #531 の分が無い(D3-1-8)
- 設計内の矛盾: `active-issues` の「git のコマンドを呼ばない」と、同じ節の「作業フォルダが無くなったセッションの記録を数えない」(`git worktree list` が要る)が合わない(D3-1-4)。Step 5.5 の3の「いまの作業フォルダは、Step 1.5 の直後に `origin/main` から作ったものか、main と同じ中身」は、ブランチを作る時点(Step 6 の前か、まとめる提案では答えのあと)より前の記述であり、成り立たない(D3-1-1 に含める)

### 申告

**1. 条件B(同じ spec を直すことになる)は、候補の本文が spec の「作るもの」にある名前に触れるものにだけ当てる** — Step 5.5 の4、research.md「開いているIssueの数と、まとめる相手の探し方の費用」

- Issue の記載: なし(Issue #531 は「どんなIssueを「1つにまとめたほうがよい」とするかの定義は、要件を作るときに決める」とし、requirements 11.2 は条件Bを「相手のIssueにも着手のときと同じ判断を当てると、直す spec が同じになる」と定めた。候補を先に絞ることは requirements に無い)
- 決めたこと: 候補の本文が spec `<feature>` の design.md の「作るもの」にある動き(スキル・スクリプト・画面・手順の名前)に触れるかで先に絞り、触れる候補にだけ Step 4 と Step 5 と同じ判断を行う
- 他にありえた選択肢: 外す条件を通ったすべての候補に、着手のときと同じ判断を行う(費用はかかるが、requirements の定義そのまま)。名前でなく、候補の本文が触れるファイルや領域で絞る
- 外れていた場合: 本文に名前を書いていないが、調べれば同じ spec を直すことになるIssue(例: 「着手のときの報告が読みにくい」のように、`/start` の名前を出さずに書かれたIssue)が提案から漏れる。所有者は、その組み合わせを別々に承認することになり、#531 の「承認のやり直し」の困りごとが一部残る。提案が出ないだけなので手戻りは無い

**2. まとめる提案への返事が相手ごとにどちらとも読めないときは、その相手を「まとめない」として扱い、そのまま先へ進む** — 「まとめる提案の答えを受けたとき」の1

- Issue の記載: なし(requirements 11.10〜11.16 は「まとめる」と「まとめない」の答えを扱い、どちらとも読めない返事の扱いは design が決めた)
- 決めたこと: どちらとも読めない返事の相手はまとめないものとして扱い、そのことを報告に書く。すべての相手がまとめないになれば、ブランチを作って記録し、コマンドを依頼する報告を出す
- 他にありえた選択肢: 問いの返事と同じく「答えで決まらない」として、聞き直すか、答えが来るまで待つ(#524 の問いでは、答えていない返事は「答えで決まらない問い」として spec に改める扱いにした)。推奨のとおりに扱う
- 外れていた場合: 所有者が提案に対して確認の質問を返しただけで、Claude がまとめずにブランチを作り、コマンドの依頼まで出す。所有者がそのあとでまとめたいと言うと、作ったブランチと記録を残したまま、Claude が本文の書き換えからやり直すことになる。#524 の問いの扱い(聞き直さず、決まらないものとして spec に改める)とは向きが逆で、所有者から見ると返事の読まれ方が場面で変わる

**3. 相手を探すための gh の問い合わせと `session.sh active-issues` が失敗したときは、止まらずに、まとめる提案の無い報告として進める** — 「失敗したときの扱い」の最後の項目

- Issue の記載: なし
- 決めたこと: 失敗したことと内容を報告に1行で書き、相手が無いときと同じく、ブランチを作ってコマンドを依頼する。`/start` の方針(gh の問い合わせに失敗したときは判断せずに止まる)の例外になる
- 他にありえた選択肢: ほかの gh の失敗と同じく、失敗を伝えて止まる(所有者が打ち直す)。相手探しだけをもう一度試す
- 外れていた場合: まとめる相手がいる場面で、相手探しが失敗した回だけ提案が出ず、所有者は1行の知らせを見落とすと、同じ spec を別々に直して承認をやり直すことになる。止まる形にしても、所有者が `/start` を打ち直すだけなので、どちらでも手戻りは小さい

**4. まとめる提案を出すときだけ、ブランチと `session.sh claim` を所有者の答えのあとにずらし、#N の着手の予約は答えのあとも消さない** — 「まとめる相手を探して提案する流れ」の箇条、「まとめる提案の答えを受けたとき」の6、research.md の Decision

- Issue の記載: なし(requirements 11.9 は「答えるまで spec を始めるコマンドを依頼しない」まで)
- 決めたこと: 提案のある報告ではブランチを作らず、答えで残すIssueが決まってから、残すIssueでブランチを作って記録する。残すIssueが #N でないとき、`check-start` が書いた #N の予約はこのセッションの記録として残す
- 他にありえた選択肢: 今の Step 6 のとおり先に #N のブランチを作り、残すIssueが変わったらブランチ名を付け直す。予約を消すサブコマンドを `session.sh` に足す(research.md L111 は、予約を消す手段が無いことを事実として挙げている)
- 外れていた場合: 所有者が答えずに会話が途切れると、#N の予約だけが残り、次の `/start #N` の Step 1.5 が、ほかのセッションからは `started` の作りかけとして見える(予約の仕組みそのものの動きで、この設計が新しく持ち込むものではない)。残すIssueが #M のとき、#N の予約は #N が閉じているので着手を止めないが、記録の置き場所に閉じたIssueの予約が、`prune` が片付けるまで残る

**5. Step 1.5 の `takeover` が終了コード0で終わったときは、所有者の答えが「進める」でも「やめた」でも、まとめる相手を探さない** — Step 5.5 の1

- Issue の記載: なし(requirements 11.17 は「所有者が続きから進めると答えて Claude がその作りかけを引き継いだとき」と書く)
- 決めたこと: `takeover` の終了コードで判定する。Step 1.5 の表では、ほかのセッションの作りかけに「やめた」と答えたときも `takeover` を呼ぶので、その場合も探さない
- 他にありえた選択肢: 「続きから進める」と答えたときだけ探さず、「やめた」で引き継いだときは探す
- 外れていた場合: 「やめた」で引き継いだ作りかけが小さいとき(ブランチだけなど)に、まとめる提案が出ないままコマンドを依頼する。引き継いだ変更をやり直さないという 11.17 の理由には沿っているので、手戻りは無い

### 指摘

| ID | レベル | 該当箇所 | 内容 | 直し方の案 |
|---|---|---|---|---|
| D3-1-1 | 中 | Step 5.5 の3の「spec があるIssue」と「ほかのセッションが作業中のIssue」の箇条、requirements 11.4 | 設計は「spec があるIssue」を、いまの作業フォルダの `.kiro/specs/*/spec.json` だけで見分け、「main に無く、ほかの作業フォルダで作っている spec のIssueは、そのIssueで作業中のほかのセッションが記録を持つので、次の箇条(`active-issues`)で外れる」とする。この前提は、そのセッションが開いている間しか成り立たない。`session-registry.sh` は SessionEnd で `sessions/<ID>.json` を消し(`test-session-registry.sh` L196〜200)、`is_active` は `sessions/` の記録を起点に判定する(session.sh L231〜236)ので、所有者が Claude のセッションを閉じると、その作業フォルダに spec の作りかけが残っていても、`active-issues` はそのIssueを返さない。これは parallel-sessions の `leftovers` が扱う、ごく普通の場面である(例: この spec の #531 の更新を進めている作業フォルダ `issue-520-f3c5b9` のセッションを閉じたあと、別のセッションで `/start` の判断に関わるIssueに着手すると、#531 が条件Bの相手として提案される)。所有者がまとめると答えると、#531 は閉じられ、作業フォルダに残った spec の更新は、spec.json の `additional_issues` が閉じたIssueを指すまま誰にも引き継がれない。requirements 11.4 は「spec があるIssue」を場所によらず外すと定めている。あわせて、同じ箇条の「いまの作業フォルダは、Step 1.5 の直後に `origin/main` から作ったものか、main と同じ中身なので」も成り立たない。ブランチを `origin/main` から作るのは Step 6 の直前(まとめる提案では答えのあと)で、Step 5.5 の時点の作業フォルダは、前の作業のブランチのままでありうる。この箇条は SKILL.md にそのまま写され、文書なので自動テストも無く、「スキルと文書の確認(#531 の分)」の1つ目は「外す条件の動きが書かれていること」までしか見ない | spec の有無を、すべての作業フォルダで見る。`check-start` が leftovers のために行っているのと同じく(session.sh L694〜714)、`git worktree list --porcelain` で得た作業フォルダごとに `<作業フォルダ>/.kiro/specs/*/spec.json` を読み、`issue` か `additional_issues` に候補の番号を持つものがあれば外す、と書く。Claude に作業フォルダの一覧を読ませたくなければ、`active-issues` の出力に、すべての作業フォルダの spec.json が指すIssueの番号を別の欄(例: `spec_issues`)で足し、その欄のIssueも外すと書く(記録の形は変わらず、`check-start` の同じ perl の処理を使える)。どちらにしても、「main と同じ中身なので」の理由の文は消す。テストの方針の「スキルと文書の確認(#531 の分)」の1つ目に、「spec があるIssue」の見分けがいまの作業フォルダに限られていないことの確認を足す |
| D3-1-2 | 中 | 「観点2と観点3の当てはめ方」の3の (b) の箇条(2.8。「どの spec の「作るもの」にも無い動きを変える部分は、範囲の中で作れない部分として扱う」) | この1文は、承認済みの spec が2本以上に関わる変更のうち、どの spec も持っていない動き(承認済みの spec の無い領域のコード・文書)を変える部分を「範囲の中で作れない」とし、(b) に当たると判定させる。一方、同じ3の (b) は「Issueに関わる承認済みの spec が無いときは、Claude は (b) を当てはめない」とし、spec の無い領域だけを変える変更には (b) を当てない。したがって、spec A の領域と spec の無い領域を変える変更は (b) の判定が本文で決まらず、spec A と spec B と spec の無い領域を変える変更は必ず (b) に当たる。このリポジトリは spec 駆動より前のコードと文書が多く(backend、frontend、`.github/` の多く)、2本の spec にまたがる直しがそれらにも触れることは普通にある。その直しがすべて spec が要ると判定されるのは、Issue #531 の「どうなれば解決か」(spec が要ると判断しすぎない)に反する。この箇条は SKILL.md にそのまま写され、自動テストは無い | 「どの spec の「作るもの」にも無い動き」を2つに分ける。(1) ある spec の design.md の「ファイルの構成」か「作るもの」が持つ部品・ファイルの動きを、その spec の「作るもの」に無い形に変える部分は、その spec の範囲の中で作れない部分(範囲を広げる直し)。(2) どの承認済みの spec も持たない部品・ファイルの動きを変える部分は、関わる spec が無い部分として、(b) の判定の対象にしない(spec が無いときに (b) を当てはめないのと同じ扱い)。この分け方を (b) の箇条に書き、「スキルと文書の確認(#531 の分)」の4つ目に、(2) の部分が (b) に当たらない扱いで書かれていることの確認を足す。requirements 2.8 は「関わる spec ごとの部分」しか扱わないので、(2) の扱いは design で決めてよい |
| D3-1-3 | 中 | Step 5.5 の2(`gh issue list --state open --limit 200 --json number,title,body,labels`)と3の最後の箇条(`gh pr list --state open --json number,body`) | どちらも、本文を含む JSON を Claude が読んで候補を絞る形である。Claude Code の Bash の結果は一定の長さで切り詰められるので、本文の合計がその長さを超えると、後ろのIssueやPRが見えなくなる(D2-1-4 で中とし、同じ設計が `--jq` でコマンドの中で絞り込む形に直した問題と同じ)。開いているIssueは 2026-10-11 時点で20件(research.md L118)で、このリポジトリのIssue本文は1件で1〜2KBあり、件数は増えていく。開いているPRは、Dependabot のPRの本文が更新内容の説明を含んで長く、数件で数十KBになる。PRの一覧で後ろのPRが切れると、そのPRの `Closes` `Refs:` のIssueが「開いているPRがあるIssue」として外れず、まとめる相手として提案される。所有者がまとめると答えると、開いているPRの対象のIssueが `not planned` で閉じられ、そのPRの作業がやり直しになる(requirements 11.4 がこの条件を置いた理由そのもの)。切り詰めは出力の末尾の注記だけで、Claude は拾い漏れに気づけない | 本文を一括で読まない形にする。Issueは、`gh issue list --state open --limit 200 --json number,title,labels` で番号・題名・ラベルだけを取って3の外す条件を当て、残った候補の本文を `gh issue view <番号> --json body --jq .body` で1件ずつ読む(4で本文を読むのは残った候補だけなので、読む量は変わらない)。PRは、`--jq` で番号だけを出す。例: `gh pr list --state open --limit 200 --json body --jq '[.[] | (.body // "") | scan("(?:Closes|Refs:) #([0-9]+)") | .[0] | tonumber] | unique'`。どちらも、返った件数が `--limit` に達したときは、それより古いものを見ていないことを報告の1行に書く。見直すきっかけの「`Closes` と `Refs:` を書く形を変えたとき」の項目に、この `--jq` の式が行の形に依ることを添える |
| D3-1-4 | 低 | 「session.sh active-issues」の「権限と副作用」(「docker と git のコマンドを呼ばない」)と「数えるIssue」(「作業フォルダが無くなったセッションの記録を数えない」) | `session.sh` のどのサブコマンドも、記録の置き場所を求める `kp_state_dir` で `git rev-parse` を呼ぶ(lib.sh L34)。作業フォルダが無くなったセッションの記録を数えないためには、`check-start` と `check-spec` が使う `_kp_ss_gone_sessions` と同じく `kp_live_folders`(`git worktree list`。lib.sh L95)を呼ぶ必要がある。したがって「git のコマンドを呼ばない」は、同じ節の決めごとと両立しない。実装者はすぐ気づくので実装には影響しないが、テストの方針の「記録を書かない」の確認と取り違えると、git を呼ばないテストを書こうとして迷う | 「git の状態を変えるコマンド(`switch` `fetch` `worktree add` など)と docker を呼ばない。読むだけの git のコマンド(`rev-parse`、`worktree list`)は `check-start` と同じく呼ぶ」のように直す |
| D3-1-5 | 低 | 「session.sh active-issues」の「数えるIssue」(「記録の `session_id` か `folder` が、作業中のセッションのもの」) | `folder` でも突き合わせると、同じ作業フォルダで2つのセッションが開かれたあと(Step 1.5 の `folder_conflict`)、片方が `end` で記録を消しても、その片方が着手していたIssueの記録は、もう片方の作業中のセッションと `folder` が一致するので、作業中として数えられる。`check-start` の `started`(ほかのセッションの着手の記録)は `session_id` だけで突き合わせ、`sessions/<session_id>.json` の有無で判定している(session.sh L682〜692)。この違いは、同じ作業フォルダでセッションを開き直した場面でだけ、まとめる相手が1つ余計に外れる形で現れる。設計のテストの「セッションの記録が無い(セッションを終えた)記録: 番号が出ない」は、`folder` が一致する作業中のセッションが無い場合しか通らない | 数え方を `check-start` の `started` に合わせ、「記録の `session_id` が空でなく、`sessions/<session_id>.json` があり、その作業フォルダが無くなっていない記録」とする。`folder` で引くのは、`session_id` が空の記録に限る(その記録は `prune` が残したもので、設計のとおり数えない)。テストの「セッションを終えた記録」の場合に、同じ作業フォルダにほかの作業中のセッションがあっても番号が出ないことを添える |
| D3-1-6 | 低 | requirements 11.12 の後半(「まとめたあとの作業のPRの本文の `Closes` の行に、閉じたほうのIssueの番号を書かない」)、ship の変更の節、要件との対応の表の 11.10–11.13 の行 | ship の変更の節に #531 の分が無く、要件との対応の表は 11.10〜11.13 を start と file-issue に対応づけているが、start の「まとめる提案の答えを受けたとき」にも file-issue にも、PR本文の `Closes` に触れる文は無い。今の出荷手順(`ship/SKILL.md` L40〜41)は `Closes` に対象のIssue(残すIssue)の番号を書かせ、閉じたIssueを書く理由は無いので、動きとしては満たされる。ただし、受入基準の文がどの部品にも現れないため、tasks の段階でこの受入基準に当たるタスクが作られず、審査でも対応づけられない | ship の変更の節に「まとめたあとのPRでは、`Refs:` と `Closes` に残したIssueの番号を書き、統合して閉じたIssueの番号を書かない(11.12)」の1行を足し、部品の表の ship の行と要件との対応の表に 11.12 を加える。または、start の「まとめる提案の答えを受けたとき」の4に同じ1行を置き、ship は今の決まり(`Closes` は対象のIssue)で足りることを添える |
| D3-1-7 | 低 | file-issue の変更の「まとめるときに本文を書き換えるとき」(「残すIssueに同じ見出しの節が無ければ…「本文の書式」の見出しの順のとおりの位置に節を作る」)と「着手のときの答えを本文に書き足すとき」(「節が無ければ、Claude は本文の末尾に `## 決めた方式` の見出しを作って」) | 同じ file-issue の中で、無い節を作る位置が、#524 の書き足しでは本文の末尾、#531 のまとめでは書式の順と、2つの決まりになる。閉じるIssueに「決めた方式」があり残すIssueに無いとき、まとめでは「やらないこと」の前に節ができ、そのあと着手の問いの答えを書き足すときは同じ節に足すので、結果は変わらない。自動レビューの抜き出しは見出しの形だけを見るため、どちらでも動く。実装には影響しないが、file-issue に写すときに2つの決まりが並ぶ | どちらかに揃える(書式の順に揃えるなら、#524 の節の「本文の末尾」を「書式の順の位置」に直し、サイクル2 往復1 の申告3の記録に沿って理由を1文添える)。揃えないなら、#531 の節に「書き足しのときと違い、書式の順に置く」と理由を1文書く |
| D3-1-8 | 低 | 「プロジェクトの決まりを守っているか」の「使う外部の機能がこのリポジトリで使えるか」 | この項目は #472 のサブIssueの分だけで、#531 の分(`gh issue list --json labels` でラベルが取れること、`gh pr list --state open --json body`、`gh issue close --reason "not planned" --comment`)が無い。「使う既存の仕組み」には `gh issue close` の実績(2026-10-09 の #530、2026-10-11 の #538)があり、research.md L103 には版(gh 2.102.0)もあるが、7項目目は「いつ何をどう確かめたか」を書く欄である(D2-1-6 と同じ) | 項目に #531 の分を1行足す。例: 「(#531)`gh issue close --reason "not planned" --comment` は、2026-10-11 に gh 2.102.0 で #538 を閉じて確かめた。`gh issue list --json labels` と `gh pr list --state open --json body` は同じ版で使える」 |

### 前の段階への指摘

なし。D3-1-1〜D3-1-3 は、いずれも requirements 11.4・2.8 の定めを design がどう実現するかの問題で、requirements に戻る必要は無い。D3-1-2 の (2) の扱い(関わる spec の無い部分)は requirements 2.8 が触れていないが、design で決めれば足りる。

- 往復: 1回目 / 高0 中3 低5

## サイクル3 往復2(2026-10-11)

審査の材料: `design.md`(全文。往復1の対応と、書き方の点検(2026-10-11T12:29:45Z)の直しのあと)、`requirements.md`(全文。承認済み)、`research.md`(L114 の `busy-issues` の決定)、`spec.json`(issue 472、additional_issues [524, 531]、design 生成済み・未承認)、Issue #472・#524・#531 の本文(`gh issue view 472` / `524` / `531`。いずれもコメントは読んでいない)、`gh issue view 531 --json number,labels,parent,subIssuesSummary`(設計が頼る欄が返ることの確認。`labels[].name` が `enhancement`、`parent: null`)、往復1の review と response、`reviews/design-style.md`(4回目と5回目の点検)、`.claude/scripts/parallel/session.sh`(使い方の注記 L1〜119、`_KP_SS_PL_ACTIVE` の `load_dir` `load_sessions` `active_index` L178〜250、`_kp_ss_worktree_paths` L253〜263、`check-start` の `started` の条件 L678〜699、`spec-names` L1509〜1519、振り分け L1521〜1534)、`.claude/scripts/parallel/lib.sh`(`kp_state_dir` L32〜37、`kp_live_folders` L92〜115、`kp_folder_gone` L121〜135)、`.claude/skills/start/SKILL.md`(Step 5 L123〜168)、`.claude/skills/ship/SKILL.md`(手順5 L39〜56)、`.kiro/settings/rules/spec-writing.md`(見出しの一覧 L267〜276)、承認済みの全 spec の design.md(`## ファイルの構成` の見出しがあることの grep。16本すべてにある)、`.kiro/specs/parallel-sessions/design.md`(L122。`CLAUDE.md` を「ファイルの構成」に挙げている)、`.kiro/specs/session-overlap-guard/design.md`(L89〜97。`session.sh` `start/SKILL.md` `kiro-spec-init/SKILL.md` `README.md` を挙げている)。`brief.md` は無い。

往復1の修正の確認:

- D3-1-1: サブコマンドは `busy-issues` になり、`{"active":[...],"spec":[...]}` を返す。`spec` は、すべての作業フォルダの中身(`spec-names` と同じ一覧。`_kp_ss_worktree_paths` L253〜263 が実在する)、`refs/remotes/origin/main` の木、`issues/` の記録の `branch` のブランチの木(`refs/heads/<branch>`、無ければ `refs/remotes/origin/<branch>`)の3か所の spec.json から読む。閉じたセッションが作業フォルダに残した spec は1つ目で、作業フォルダが消えて記録だけが残った spec(`prune` は `branch` が残っていれば記録を `folder` と `session_id` を空にして残す。session.sh L94〜95)は3つ目で拾える。Step 5.5 の3の「spec があるIssue」の箇条は `busy-issues` の `spec` と `active` で外す形になり、「main と同じ中身なので」の文は消えた。`active` の条件は `check-start` の `started` の4つの条件(session.sh L682〜699)と同じ文面で、`folder` だけが一致する記録を数えないと書かれ、往復1の D3-1-5 も同時に直っている。「権限と副作用」は読むだけの git のコマンドに限る形になり、D3-1-4 も直っている。テストの方針(L829〜843)は3か所の spec.json と、ブランチが無いとき、壊れた spec.json、記録を書かないこと、錠を取れないときを含む。概要(L13)、作るもの(L46)、使う既存の仕組み(L87)、見直すきっかけ(L97)、部品の表(L312)、失敗したときの扱い(L787)、要件との対応(L922)、research.md L114 が同じ名前と形を指している。修正は足りている
- D3-1-2: (b) の箇条(L374)は、部分が関わる spec を「その部分が変えるファイルを、design.md の「ファイルの構成」の節に挙げている承認済みの spec」で決め、「どの承認済みの spec の「ファイルの構成」にも無いファイルだけを変える部分は、関わる spec が無い部分であり、(b) を当てない」とした。往復1で指摘した「spec の無い領域だけを変える部分が必ず (b) に当たる」問題は無くなった。`## ファイルの構成` の見出しは、承認済みの16本の design.md すべてにあることを grep で確かめた(spec-writing.md L276 の一覧の名前)。ただし、関わる spec をファイルの名前だけで決めることで、別の形の判断しすぎが入った。D3-2-1 に挙げる
- D3-1-3: Step 5.5 の2は `gh issue list --state open --limit 200 --json number,labels --jq '[...]'` で番号だけを出し、ラベルの外しもコマンドの中で行う形になった。jq の式(`[.labels[].name] | any(. == ... ) | not`)は jq の文法として成り立ち、ラベルが無いIssueは `[]` に `any` を当てて false になるので候補に残る。`labels[].name` が返ることは `gh issue view 531 --json labels` で確かめた。3の最後の箇条は `gh pr list --state open --limit 200 --json body --jq '[.[].body | scan("(?m)^(?:Closes|Refs:) #([0-9]+)") | .[0] | tonumber] | unique'` で番号だけを出す形になった(`(?m)` は gh の jq(Oniguruma の Perl の文法)で `^` を行の頭に当てる印)。審査役は `gh pr list` を実行できないため、動くことは response の記録(手元で確かめた)に依る。本文は外したあとの候補ごとに `gh issue view` で読む。修正は足りている。「返った件数が `--limit` に達したときの1行」は入っていないが、低として D3-2-2 に書く
- D3-1-4〜D3-1-8: 低のまま「記録のみ」。D3-1-4 と D3-1-5 は D3-1-1 の書き直しで直っている。再び出さない

要件カバレッジ・境界・決まりの節・実現できない設計: 往復1の修正で変わった箇所(概要、作るもの、使う既存の仕組み、見直すきっかけ、ファイルの構成、Step 5.5 の2と3、(b) の箇条、`busy-issues` の節、データの形、失敗したときの扱い、テストの方針、要件との対応)が、ほかの節と食い違いを起こしていないことを確かめた。`session.sh` の変更は `busy-issues` の追加と振り分け・注記・誤りの文だけで、記録の形を変えないこと(持たないものの最後の項目)と一致する。作らないもの(#531 の4項目)を本文が破っていないことも変わらない。往復1の確認の結果から、下の2件のほかに変わった点は無い。

### 申告

**1. `busy-issues` の `spec` は、すべての作業フォルダの中身・`origin/main` の木・記録の `branch` のブランチの木の3か所の spec.json から読む** — 「session.sh busy-issues」の「`spec` に入れるIssue」、research.md L114

- Issue の記載: なし(requirements 11.4 は「spec があるIssue」を外すとだけ定め、どこにある spec を見るかは design が決めた)
- 決めたこと: 3か所の spec.json の `issue` と `additional_issues` を集める。`origin/main` が無ければその場所を飛ばし、ブランチがローカルにもリモートにも無ければそのブランチを飛ばす
- 他にありえた選択肢: 作業フォルダの中身だけを見る(往復1の直し方の案の前半。セッションを閉じたあとに作業フォルダを消した spec は拾えない)。`issues/` の記録に、`claim` のときに spec の有無を書き足す(記録の形を変えるので、持たないものに反する)。候補ごとに Claude が `check-start` の leftovers を読む(予約を書くので採れない)
- 外れていた場合: 記録が無いブランチ(`claim` を通らずに作ったブランチ)にだけある spec のIssueは `spec` に入らず、まとめる相手として提案される。所有者がまとめると答えると、そのブランチの spec の作りかけは、閉じたIssueを指したまま残る。parallel-sessions のあとは `/start` が `claim` で記録を書くので、この場面は起きにくい。`refs/remotes/origin/<branch>` は手元に取得した時点の木なので、取得していないリモートのブランチの spec も入らない

### 指摘

| ID | レベル | 該当箇所 | 内容 | 直し方の案 |
|---|---|---|---|---|
| D3-2-1 | 中 | 「観点2と観点3の当てはめ方」の3の (b) の箇条(L374。「ある部分がどの spec に関わるかは、その部分が変えるファイルを、design.md の「ファイルの構成」の節に挙げている承認済みの spec で決める。関わる spec があり、その部分が変える動きがその spec の「作るもの」に無いときは、Claude は、その部分を範囲の中で作れない部分として扱う」)、requirements 2.8 | 往復1の修正で、部分が関わる spec を、その部分が変える**ファイル**を「ファイルの構成」に挙げている spec で決めるようにした。このリポジトリでは、1つのファイルを複数の spec が「ファイルの構成」に挙げている。`CLAUDE.md` は parallel-sessions(design.md L122)と本 spec が、`README.md` と `.claude/skills/start/SKILL.md` は session-overlap-guard(L95、L97)と本 spec が、`session.sh` は parallel-sessions・session-overlap-guard・本 spec が挙げている。そのため、この決め方では次の2つが起きる。(1) どの spec も持たない動きを変える部分が、ファイルの名前だけで spec に関わる部分になり、「その spec の「作るもの」に無い」ので範囲の中で作れない部分になる。例: CLAUDE.md の「同一の失敗が3回続いたら停止して人間に報告する」の決まりを直す部分は、CLAUDE.md を挙げる parallel-sessions と本 spec に関わる部分になり、どちらの「作るもの」にも無いので (b) に当たる。往復1で直す前の文(#524 で承認した「Issueに関わる承認済みの spec が無いときは (b) を当てはめない」)なら、この部分に関わる spec は無く、(b) は当たらなかった。ファイル単位の決め方が、#531 の「どうなれば解決か」(spec が要ると判断しすぎない)と逆の向きに働く。(2) 1つの部分に関わる spec が2本以上あるとき、「その spec の「作るもの」に無いとき」の「その spec」がどれを指すかが決まらない。例: `start/SKILL.md` の観点の表を直す部分は、本 spec(「作るもの」に「4つの観点の定義」がある)と session-overlap-guard(無い)の両方に関わる。本 spec の「作るもの」にあるので範囲の中で作れると読むか、session-overlap-guard の「作るもの」に無いので作れないと読むかで、(b) の結果が変わる。(1) も (2) も、この箇条が SKILL.md にそのまま写されて初めて現れ、文書なので自動テストも無く、「スキルと文書の確認(#531 の分)」の4つ目は「当てはめ方が書かれていること」までしか見ない | 関わる spec の決め方を、ファイルの名前でなく、「ファイルの構成」の行が書いている中身で決める。「ファイルの構成」の各行は、そのファイルのどの部分をその spec が作った・変えたかを書いている(例: 本 spec の `CLAUDE.md` の行は「着手の入口、4つの観点、200行の検査の位置づけ、…を書く」)。(1) の直し: 「ある部分がどの spec に関わるかは、その部分が変える箇所を、その spec の design.md の「ファイルの構成」の行が、その spec が作った・変えた中身として書いているかで決める。ファイルの名前だけが同じで、行の中身に当たらない箇所を変える部分は、その spec に関わらない。どの承認済みの spec にも関わらない部分は、関わる spec が無い部分であり、(b) を当てない」とする。(2) の直し: 「1つの部分に関わる spec が2本以上あるときは、そのうち1本でも「作るもの」の範囲の中で作れれば、その部分は範囲の中で作れる部分とする。どの spec の「作るもの」にも無いときだけ、範囲の中で作れない部分とする」と書く。あわせて、「承認済みの spec 2本以上にまたがるとき」の「またがる」も同じ決め方で判定することを1文添える。「スキルと文書の確認(#531 の分)」の4つ目に、関わる spec をファイルの名前だけで決めていないことと、2本以上に関わる部分の扱いが書かれていることの確認を足す。「過去の統合の当てはめ」と同じく、#537(#524 の出荷。`start/SKILL.md` と CLAUDE.md と README を直した)に当てはめて、(b) に当たらず「spec-need-triage を直す」になることを確かめる項目を1つ足すと、文面の検算になる |
| D3-2-2 | 低 | Step 5.5 の2(`gh issue list --limit 200`)と3の最後の箇条(`gh pr list --limit 200`) | 往復1の D3-1-3 の直し方の案に含めた「返った件数が `--limit` に達したときは、それより古いものを見ていないことを報告の1行に書く」が入っていない。番号だけを出す形にしたので、件数は出力の配列の長さで分かる。開いているIssueは 2026-10-11 時点で20件、開いているPRは数件で、200件に届くのは当面先であり、届いても古いIssueやPRが候補から漏れるだけで、着手の判断そのものは変わらない(「失敗したときの扱い」の最後の項目と同じ扱いでよい) | 2と3の最後の箇条に「出力の配列の長さが 200 のときは、Claude は、それより古いIssue(PR)を見ていないことを Step 6 の報告に1行で書く」を添える。tasks で SKILL.md の文面を書くときに足しても足りる |

### 前の段階への指摘

なし。D3-2-1 は requirements 2.8 の「関わる spec ごとの部分」をどう決めるかの問題で、design で決めれば足りる。

- 往復: 2回目 / 高0 中1 低1

## サイクル3 往復3(2026-10-11)

審査の材料: `design.md`(全文。往復2の対応と、書き方の点検(2026-10-11T12:41:25Z)の直しのあと)、`requirements.md`(全文。承認済み)、`spec.json`(issue 472、additional_issues [524, 531]、design 生成済み・未承認)、Issue #472・#524・#531 の本文(`gh issue view 472` / `524` / `531`。いずれもコメントは読んでいない)、往復1・2の review と response、`reviews/design-style.md`(6回目と7回目の点検)、`.claude/skills/start/SKILL.md`(Step 5 の「既存の spec の範囲か」L134、観点の表 L143、当てはめ方 L156〜166)、`.kiro/specs/parallel-sessions/design.md`(「ファイルの構成」L97〜122)、`.kiro/specs/session-overlap-guard/design.md`(「ファイルの構成」L89〜97)、承認済みの全 spec の design.md(`## ファイルの構成` の見出しと、その直後の行の書き方の grep。16本すべてにある)、`.kiro/specs/spec-readable-writing/design.md`(L148。`This Spec Owns` を `作るもの` に書き換えた対応表)。`brief.md` は無い。

往復2の修正の確認:

- D3-2-1: (b) の箇条(L374)は、部分が関わる spec を「ファイルの名前ではなく、design.md の「ファイルの構成」の節の行の中身(その spec がそのファイルの中で作った箇所か変えた箇所)で決める」とし、「同じファイルを挙げていても、行の中身がその箇所を挙げていない spec は関わらない」「関わる spec が2本以上あるときは、そのうち1本でも「作るもの」の範囲の中で作れれば、その部分を範囲の中で作れる部分とする」「どの承認済みの spec の「ファイルの構成」の行の中身にも挙がっていない箇所だけを変える部分(例: CLAUDE.md の、どの spec も作っていない決まりの文)は、関わる spec が無い部分であり、(b) を当てない」の3つを持つ形になった。往復2の (1)(2) の直し方の案と一致する。往復2で挙げた2つの例を、実ファイルの「ファイルの構成」で当て直した。(1) CLAUDE.md の「同一の失敗が3回続いたら停止」の決まりを直す部分: parallel-sessions の `CLAUDE.md` の行(L122)は「部品「文書」」で、その部品は品質チェックと並行作業の記述を書くもの、本 spec の `CLAUDE.md` の行(L166)は着手の入口・4つの観点・200行の検査などを書くもので、どちらもこの決まりを挙げていないため、関わる spec が無い部分になり、(b) は当たらない。(2) `start/SKILL.md` の観点の表を直す部分: 本 spec の `start/SKILL.md` の行(L150)が「4つの観点の定義」を挙げ、session-overlap-guard の行(L95)は「部品「start スキルの変更」」(Step 1.5)で観点の表を挙げていないため、関わる spec は本 spec だけになり、「作るもの」の「4つの観点の定義」の範囲の中で作れる。関わる spec が2本になる場合も、1本でも範囲の中なら範囲の中とする文で結果が1つに決まる。往復2の直し方の案の末尾の検算(#537 を当てはめる)も手で行った。#537 が直した `start/SKILL.md` の観点の表・CLAUDE.md の観点の表・README の `/start` の行は、いずれも本 spec の「ファイルの構成」の行の中身に当たり、本 spec の「作るもの」の範囲の中で作れるので、(b) に当たらず、Step 5 の決め方で「spec-need-triage を直す」になる。修正は足りている。直し方の案のうち、「またがる」の判定の1文と、「スキルと文書の確認(#531 の分)」の4つ目への追加と、#537 の検算の項目は反映されていないが、いずれも本文の決めごとを変えるものではないため、低として D3-3-3 に書く
- D3-2-2: 低のまま「記録のみ」。再び出さない
- 書き方の点検(2026-10-11T12:41:25Z)で直った1文は、同じ箇条の最後の文に主語「Claude は」を補ったもので、意味は変わっていない

要件カバレッジ・境界・決まりの節・設計内の矛盾・実現できない設計: 往復2からの本文の変更は L374 の1か所だけであり、その変更が requirements 2.8(関わる spec ごとの部分に分け、どの部分も範囲の中で作れれば当たらない、作れない部分が1つでもあれば当たる)、観点の表の観点2(L362)、当てはめ方の1と6、Step 5 の「既存の spec の範囲か」(L346)、作らないものの最後の項目(どの spec を直すかの決め方は変えない)、「スキルと文書の確認(#531 の分)」(L851)と食い違いを起こしていないことを確かめた。関わる spec が無い部分に (b) を当てない扱いは、#524 で承認した「承認済みの spec が無いときは (b) を当てはめない」(L373)と同じ向きで、本文もそう書いている。往復1・2の確認の結果から、下の低3件のほかに変わった点は無い。

### 申告

**1. 1つの部分に関わる承認済みの spec が2本以上あるときは、そのうち1本でも「作るもの」の範囲の中で作れれば、その部分を範囲の中で作れる部分とする** — 「観点2と観点3の当てはめ方」の3の (b) の箇条(L374)

- Issue の記載: なし(Issue #531 の「どうなれば解決か」は「spec の範囲の中で作れるかを判定でき、spec が要ると判断しすぎない」まで。requirements 2.8 は「その部分に関わる spec の設計の「作るもの」の節に書かれた範囲の中で作れるか」と書き、関わる spec が2本以上のときの扱いは design が決めた)
- 決めたこと: 関わる spec が2本以上の部分は、どれか1本の「作るもの」の範囲の中で作れれば範囲の中とし、どの spec の「作るもの」にもその部分が変える動きが無いときだけ範囲の中で作れない部分とする
- 他にありえた選択肢: 関わるすべての spec の「作るもの」の範囲の中で作れるときだけ範囲の中とする(安全側。#531 の「判断しすぎない」とは逆の向き)。その部分が変える箇所を「ファイルの構成」の行に挙げた spec が2本以上あるときは、行の中身がより狭く当たる1本だけを関わる spec とする
- 外れていた場合: spec A の「作るもの」にある動きを、spec B が作った箇所の中で変える部分が (b) に当たらず、ほかの観点にも当たらなければ spec 無しで進む。そのとき spec B の本文はその動きを持たないままになるが、#524 で決めたPR本文の「食い違う spec:」の行と、次の更新のときの反映で拾われる。200行の検査と自動レビューも網になるので、手戻りは小さい

### 指摘

| ID | レベル | 該当箇所 | 内容 | 直し方の案 |
|---|---|---|---|---|
| D3-3-1 | 低 | 「観点2と観点3の当てはめ方」の3の (b) の箇条(L374。「design.md の「ファイルの構成」の節の行の中身(その spec がそのファイルの中で作った箇所か変えた箇所)で決める」) | 承認済みの spec の「ファイルの構成」の行には、箇所を直接書かずに「部品「文書」」「部品「start スキルの変更」」のように部品の名前だけを書くものがある(parallel-sessions L116・L122、session-overlap-guard L95〜96)。本文の「行の中身が挙げていれば」を文字どおりに読むと、これらの行はどの箇所も挙げていないことになり、その spec が実際に変えた箇所(例: parallel-sessions が CLAUDE.md に書いた品質チェックの説明)を変える部分が、関わる spec の無い部分になる。括弧の中の「その spec がそのファイルの中で作った箇所か変えた箇所」で、部品の節まで辿る読み方はできるので、実装者が迷うだけで、判定の向きは「spec が要ると判断しすぎない」側に倒れる | 箇条に「行が部品の名前だけを書いているときは、その部品の節が書いた箇所で決める」の1文を添える。tasks で SKILL.md の文面を書くときに足しても足りる |
| D3-3-2 | 低 | Step 5 の「既存の spec の範囲か」(L346。「既存の spec の design.md の「This Spec Owns」に書かれた範囲」) | `This Spec Owns` は、spec-readable-writing(design.md L148)で `### 作るもの` に書き換えられた古い見出しの名前で、今の承認済みの design.md のどれにも無い。同じ節の観点の表(L362)と当てはめ方の1・3(L371、L373〜374)は「作るもの」と書いており、本文の中で2つの名前が並ぶ。実装済みの `start/SKILL.md` L134 はすでに `### 作るもの` で書かれているため、動きには影響しない。#472 のときからある文で、書き方の点検の記録も「直さなかった外れ」として毎回挙げている | 「This Spec Owns」を「作るもの」に直す。(b) の箇条が「Step 5 の「既存の spec の範囲か」の決め方では「新しい spec」になる」と参照しているので、同じ名前で読めるようにする |
| D3-3-3 | 低 | 「スキルと文書の確認(#531 の分)」の4つ目(L851)、(b) の箇条の冒頭(「承認済みの spec 2本以上にまたがるとき」) | 往復2の直し方の案のうち、確認の項目への追加(関わる spec をファイルの名前だけで決めていないこと、2本以上に関わる部分の扱いが書かれていること、#537 を当てはめて「spec-need-triage を直す」になること)と、「またがる」を同じ決め方で判定する1文は反映されていない。L851 は「当てはめ方が書かれていること」までしか見ないため、SKILL.md に写すときに今回足した3つの決めごとのどれかが落ちても、この確認では拾えない。「またがる」は、箇条の2文目以降の「関わる spec」の決め方から読み取れる(部分の関わる spec が合わせて2本以上あれば、またがる)。tasks の段階で完了条件に入れれば足りる | L851 を「…当てはめ方が書かれていること。関わる spec を「ファイルの構成」の行の中身で決めること、関わる spec が2本以上の部分は1本でも範囲の中なら範囲の中とすること、関わる spec が無い部分に (b) を当てないことが書かれていること(2.8)」に広げ、「過去の統合の当てはめ」の下に「#537 の変更に当てはめ、(b) に当たらず「spec-need-triage を直す」になること」を1項目足す。箇条の冒頭に「変更の部分が関わる spec が、合わせて2本以上あるとき」と添える |

### 前の段階への指摘

なし。D3-3-1〜D3-3-3 は、いずれも design の文面の問題で、requirements に戻る必要は無い。

- 往復: 3回で収束 / 未解決: 0件
