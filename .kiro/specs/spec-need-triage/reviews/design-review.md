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
