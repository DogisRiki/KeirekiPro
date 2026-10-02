# tasks レビューの記録(spec-readable-writing)

## サイクル1 往復1(2026-10-02)

tasks.md を、requirements.md(承認済み)、design.md(サイクル3で収束)、Issue #474 の本文、steering、リポジトリの実ファイルと突き合わせて審査した。実ファイルは作業ツリー(`feat/spec-need-triage` ブランチ)の版で確かめた。

この往復で確かめた事実: `/kiro-impl` の自律モードは、タスクごとに implementer サブエージェントを Agent ツールで起動し、implementer は `templates/implementer-prompt.md` のとおり `READY_FOR_REVIEW | BLOCKED | NEEDS_CONTEXT` を返すだけで、所有者に尋ねる手段を持たない。手動モード(タスク番号を渡す)はメインの会話で実行する。サブエージェントには Agent ツールが無い(この審査役のサブエージェントにも無い)。`/kiro-impl` の Step 2 は `_Depends:_` `_Blocked:_` `_Boundary:_` を名前で読み、Step 4 で `/kiro-validate-impl` を走らせる。`/kiro-validate-impl` は design.md の `Boundary Commitments` `Out of Boundary` `Allowed Dependencies` `Revalidation Triggers`、File Structure Plan、tasks.md の `## Implementation Notes` を名前で読む。`check-verify-before-stop.sh` は frontend・backend・terraform の変更だけを見るので、この spec の変更で verify の未実行を止めることは無い。`.github/scripts/check-spec-backing.sh` は jq が無いと失敗する(fail closed)。`.github/scripts/tests/test-check-spec-backing.sh` は `mktemp -d` の中で動き、リポジトリに書き込まない。`.claude/hooks/tests/test-protect-main.sh` は `$(dirname "$0")/..` でフックを探し、ホストで走らせる前提で書かれている。`spec-review-scan.sh` は `phase` が `initialized` の spec を飛ばし、生成済みで人の承認が無い段階だけを判定する。`/kiro-spec-tasks` の Step 4 は、生成の直後に「Approve and proceed to implementation?」と尋ね、承認されたら `approvals.tasks` に `approved_by: "DogisRiki"` を書く。`/kiro-spec-init` の `## Project Description (Input)` を目印にする更新の形、CLAUDE.md の「Issueの印」の節、`/spec-review` の Step 6 の `approval_history` は、いずれも spec-need-triage(spec.json の `phase` が `implemented`、タスク2.2・2.3・5.1)が足したもので、作業ツリーの `feat/spec-need-triage` ブランチにある。この spec のディレクトリ `.kiro/specs/spec-readable-writing/` は、同じ作業ツリーに未追跡(`??`)で置かれている。origin/main にこれらがあるかは、git を実行できないため確かめていない。

要件カバレッジ: 要件1〜7の受入基準(1.1〜1.2、2.1〜2.8、3.1〜3.3、4.1〜4.3、5.1〜5.3、6.1〜6.6、7.1〜7.3)は、すべて少なくとも1つのタスクの `_要件:_` に現れる。requirements.md に無い番号を参照するタスクは無い。

design カバレッジ: design の8つの部品(`spec-writing.md`、新しい雛形と古い雛形、spec を書くスキル、`spec-style-checker`、`/spec-review`、`spec-review-scan.sh`、spec を読むスキル、CLAUDE.md)はそれぞれタスクに現れ、`_対象の部品:_` はすべて design の部品の名前である。テストの方針の5項目(scan のテスト、`test-check-spec-backing.sh`、grep、点検役の確かめ、通しの確かめ)は 4.3・6.2・1.2・4.1・6.2 で扱う。移行の1(写してから置き換える)は 1.1 → 2.x の依存で守られ、移行の2(所有者が写してから出荷)は 6.3 にある。読み替えの指示の一覧(`requirements-review-gate.md` の境界の用語を含む)、research.md の雛形を `specs/` から読むこと、`design-review-gate.md` の「省いてよい」、観点3の読み替え、CLAUDE.md の4項目は、それぞれ 3.2・3.3・5.3・6.1 にある。

スコープ: 「作らないもの」(research.md などの書き方、今の spec の書き直し、quick/batch、`/kiro-validate-design` の案内)をやるタスクは無い。

完了条件: 4項目はすべてある。verify の実行は「frontend・backend・terraform のどれも変えない」という理由を添えて各タスクの「完了の確かめ方」に置き換えており、正当である。

並列と依存: `(並行可)` の付いたタスク(2.1〜2.3、3.1〜3.4、5.1〜5.3)は互いに別のファイルを変える。実装のメモが「番号の順に1つずつ進める」と定めているので、並列に動かして衝突することは無い。

### 申告

**1. 実装を、メインの作業ツリーではなく origin/main から作った git worktree で行う** — 完了条件(全タスク共通)の5

- Issue の記載: なし
- 決めたこと: origin/main から別の作業場所を作り、そこで実装する。メインの作業ツリーは別の会話が別のブランチで使っているため
- 他にありえた選択肢: spec-need-triage の PR がマージされるのを待ってから、メインの作業ツリーで行う。`feat/spec-need-triage` から枝を切る
- 外れていた場合: この spec が参照する実ファイル(`追加の要望` の目印、「Issueの印」の節、Step 6 の `approval_history`)が作業場所に無く、タスク3.1・6.1・4.2 を書かれたとおりに行えない(T1-1-1)

**2. scan のテストをホストの Git Bash で走らせ、`test-check-spec-backing.sh` はリポジトリを読み取り専用で mount した `docker run` で走らせる** — タスク4.3、6.2

- Issue の記載: なし
- 決めたこと: design のテストの方針は「コンテナの中で」と書くが、tasks は scan のテストをホストで走らせる(フックが動く環境と同じ)。`check-spec-backing.sh` は jq を要するので、こちらはコンテナで走らせる
- 他にありえた選択肢: 両方をコンテナで走らせる。両方をホストで走らせる(jq が無いので `check-spec-backing.sh` の方は失敗する)
- 外れていた場合: 走らせる場所を変えるだけで、実装は変わらない

**3. テストを省略可能な印(`- [ ]*`)にしたタスクは無い** — タスクの一覧

- Issue の記載: なし
- 決めたこと: すべてのタスクに完了の確かめ方を付け、省略可能にしていない
- 他にありえた選択肢: 点検役の確かめ(4.1)と通しの確かめ(6.2)を省略可能にする
- 外れていた場合: なし

### 指摘

| ID | レベル | 該当箇所 | 内容 | 直し方の案 |
|---|---|---|---|---|
| T1-1-1 | 中 | tasks.md 完了条件の5、タスク3.1・4.2・6.1 | 完了条件の5は「origin/main から作った別の作業場所(git worktree)」で実装すると定めるが、2つのことが決まっていない。(1) この spec のディレクトリ `.kiro/specs/spec-readable-writing/` は、`feat/spec-need-triage` ブランチの作業ツリーに未追跡で置かれており、origin/main から作った worktree には無い。`/kiro-impl` は Step 1 で `.kiro/specs/{feature}/` の4ファイルを読み、Preflight で tasks の承認を確かめるので、spec を作業場所に持ち込まないと始められない。どのブランチにどう持ち込むかが tasks に無い。(2) タスク3.1 が直す「追加の要望を足すときの目印の行」、タスク6.1 が直す「Issueの印」の節と「`/kiro-spec-tasks` が生成直後に承認を尋ねる」の行、タスク4.2 が点検の工程に戻す Step 6 の差し戻しの手順は、spec-need-triage(タスク2.2・2.3・5.1)が足したもので、作業ツリーの `feat/spec-need-triage` ブランチで確かめた。origin/main にあるかは私は確かめていない(git を実行できない)。無ければ、タスク3.1・6.1 は書かれたとおりに行えず、implementer は BLOCKED を返すか、無い行を自分で足して spec-need-triage のマージ時に競合する。確かめ方: `git log origin/main -1 --oneline -- .claude/skills/kiro-spec-init/SKILL.md` と `git show origin/main:CLAUDE.md` に「Issueの印」があるか | 完了条件の5に、作業場所の基点を「spec-need-triage の PR が main に入ったあとの origin/main」(または `feat/spec-need-triage`)と書き、この spec のディレクトリを作業場所の feature ブランチにコミットして持ち込む手順を足す。origin/main に無いまま始める場合は、3.1・6.1 の該当する直しを spec-need-triage のマージ後に行うと書く |
| T1-1-2 | 中 | tasks.md タスク4.1 の完了の確かめ方、タスク6.2 | 4.1 の完了の確かめ方(短い本文を点検役に渡して返りを見る)と 6.2(直したあとの `/spec-review` を1往復流す。点検役が読み込まれていなければ所有者に会話の始め直しを頼む)は、Agent ツールで点検役と審査役を起動することと、所有者に頼むことを要する。`/kiro-impl` の自律モードは、タスクごとに implementer サブエージェントに任せ、implementer は `templates/implementer-prompt.md` のとおり `READY_FOR_REVIEW | BLOCKED | NEEDS_CONTEXT` を返すだけで、所有者に尋ねる手段も Agent ツールも持たない(サブエージェントはサブエージェントを起動できない。この審査役にも Agent ツールは無い)。したがって、4.1 の確かめと 6.2 は自律モードでは必ず BLOCKED か NEEDS_CONTEXT になり、そこで初めて手動モード(`/kiro-impl spec-readable-writing 4.1` のように番号を渡す。メインの会話で実行する)への切り替えを所有者に頼むことになる。tasks はどのタスクをメインの会話で行うかを書いておらず、実装のメモも `_依存:_` の読み方だけを扱っている。また、`.claude/agents/spec-style-checker.md` を作った会話でそれが読み込まれるかの扱いは 6.2 にだけあり、同じ確かめをする 4.1 には無い | 4.1 の確かめの部分を切り出して(たとえば 4.1 は定義ファイルを作るところまでにし、確かめを 6.2 に寄せる)、6.2 と 6.3 に「このタスクはメインの会話が手動モード(`/kiro-impl spec-readable-writing 6.2`)で行う。所有者に打ってもらう」と書く。実装のメモにも、自律モードで進めるタスクと手動モードで進めるタスクの分け方を足す |
| T1-1-3 | 低 | tasks.md タスク2.1 の `_依存:_` | 2.1 は「`spec-writing.md` の対応表の新しい名前に書き換える」と書くが、`_依存:_` は 1.1 だけで、対応表を書く 1.2 が無い。実装のメモが番号の順に進めると定めているので、実際には 1.2 のあとに動き、衝突しない | `_依存: 1.1, 1.2_` にする |
| T1-1-4 | 低 | tasks.md タスク6.2 | 一時的な spec で `/spec-review` を流す手順に、D1-2-4 の処置で「tasks で扱う」とした2点が無い。(1) 審査役は spec.json の `issue` で `gh issue view` を実行するので、一時的な spec.json に Issue の番号(#474 など)を書くこと。(2) 一時的な spec は Stop フックの走査の対象になるので、作ってから消すまでを1回の応答の中で終えること(「すぐに消す」とあるが、応答をまたぐと2回まで止められる)。あわせて、`docker run` の像(イメージ)に jq が要ること(`check-spec-backing.sh` は jq が無いと失敗する)が書かれていない。どれも実装のときに気づいて扱える | 6.2 に、一時的な spec.json に `issue` を書くこと、1回の応答の中で作ってから消すまでを終えること、jq のある像で `docker run` することを足す |
| T1-1-5 | 低 | tasks.md 実装のメモ | 実装のメモは、直す前の `/kiro-impl` が `_Depends:_` などの旧名を読むことだけを扱う。`/kiro-impl` の Step 4 は `/kiro-validate-impl` を走らせ、`/kiro-validate-impl` は design.md の `Boundary Commitments` `Out of Boundary` `Allowed Dependencies` `Revalidation Triggers` と File Structure Plan、tasks.md の `## Implementation Notes` を名前で読む(SKILL.md の行126・131・139)。この spec の design.md と tasks.md は新しい名前なので、最終検証が節を見つけられず NO-GO か MANUAL_VERIFY_REQUIRED を返しうる。タスク5.2 で直したあとの版がその会話で読み込まれるかにもよる。実装には影響しない | 実装のメモに、最終検証(`/kiro-validate-impl`)では design の対応表の新しい名前で読むことを渡す、または結果が MANUAL_VERIFY_REQUIRED のときは節の名前の違いによるものかを確かめる、と足す |
| T1-1-6 | 低 | tasks.md タスク4.3、design.md テストの方針の1項目目 | 4.3 は scan のテストをホストの Git Bash で走らせると理由付きで書くが、design のテストの方針は「コンテナの中で bash と perl を使って走らせ」のままである(D1-3-2 は記録のみで、tasks が決めるとした)。tasks の側に理由があるので実装は迷わない | design の1項目目を「ホストの Git Bash で」に直す。design を直さないなら、tasks の 4.3 に「design の『コンテナの中で』はこの手順に読み替える」と添える |

### 前の段階への指摘

なし。

- 往復: 1回目 / 高0 中2 低4

## サイクル1 往復2(2026-10-02)

往復1の処置(T1-1-1・T1-1-2 の修正)を、直したあとの tasks.md と、origin/main の実ファイルで確かめた。origin/main の中身は、メインセッションの指示により `git show origin/main:<path>`(読むだけ)で確かめた。

この往復で確かめた事実: origin/main の先頭は `fd8d0eb feat: 着手の入口を /start の1つにし、specの要否をAIが着手時に判断する (#475)` で、spec-need-triage はマージ済みである。origin/main の `.claude/skills/kiro-spec-init/SKILL.md` の45・46・68行目に `### 追加の要望(Issue #<N>)` と `## Project Description (Input)` を目印にする更新の手順があり、`CLAUDE.md` の149行目に「`/kiro-spec-tasks` が生成直後に承認を尋ねる」の行、161行目に「#### Issueの印」の節があり、`.claude/skills/spec-review/SKILL.md` の81行目に Step 6、89行目に `approval_history` がある。往復1の処置の記載はすべて事実と一致する。T1-1-1 で私が「確かめていない」と書いた部分は、origin/main にあることで解消した。`/kiro-impl` は、タスク番号を渡すとメインの会話で実行する手動モードを持つ(SKILL.md の Role と Step 2)ので、実装のメモの「メインの会話で行う」は実行できる。`protect-main.sh` は `git branch --show-current` が `main` のときだけ commit/push を止めるので、ブランチの無い worktree(detached HEAD)では止めない。フックは `CLAUDE_PROJECT_DIR` で作業場所を決めるので、worktree で始めた会話でも worktree の `.kiro/specs/` と `.claude/.state/` を見る。`.claude/.state/` は `.gitignore` に入っている。`/ship` の Step 2 は `git branch --show-current` でブランチを確かめ、main かfeatureブランチかの2通りしか扱っていない。

往復1で確かめた要件カバレッジ・design カバレッジ・スコープ・完了条件・並列と依存に変わりは無い(直したのは完了条件の5と実装のメモだけで、タスクの本文と目印は変わっていない)。

### 申告

**1. この spec のディレクトリを、コミットを経ずにメインの作業ツリーから作業場所に写す** — 完了条件(全タスク共通)の5

- Issue の記載: なし
- 決めたこと: 作業場所(worktree)を作ったらすぐに、未追跡のまま置かれている `.kiro/specs/spec-readable-writing/` をメインの作業ツリーからファイルとして写す
- 他にありえた選択肢: メインの作業ツリーの側で spec をブランチにコミットし、作業場所でそのブランチを基点にする
- 外れていた場合: 写したあとにメインの作業ツリーの側の spec(承認の記録など)が変わると、作業場所の spec と食い違う。写すのは1回なので、写す時点を承認のあとにすれば起きない

### 指摘

| ID | レベル | 該当箇所 | 内容 | 直し方の案 |
|---|---|---|---|---|
| T1-2-1 | 低 | tasks.md 完了条件の5 | 作業場所を「origin/main から作った git worktree」とだけ書き、そこで使うブランチに触れていない。`git worktree add <path> origin/main` の形で作ると detached HEAD になり、`protect-main.sh` は止めないので `/kiro-impl` のタスクごとのコミットはそのまま進むが、`/ship` の Step 2(ブランチ確認)は main とfeatureブランチしか扱わず、`git push -u origin <ブランチ名>` に渡すブランチが無い。CLAUDE.md の「作業は必ずfeatureブランチで行う」に従えば起きず、起きても `git switch -c` でコミットは保てるので、実装の作り直しにはならない | 完了条件の5に「`.branch_name_template` に従ったfeatureブランチを作って作業場所にする(`git worktree add -b <ブランチ名> <path> origin/main`)」と添える |
| T1-2-2 | 低 | tasks.md タスク4.1 の完了の確かめ方、実装のメモの2つ目 | 実装のメモで 4.1 の確かめをメインの会話で行うことになったが、`.claude/agents/spec-style-checker.md` を作った会話でその点検役が読み込まれていないときの扱い(6.2 には「所有者に会話の始め直しを頼む」がある)が 4.1 には無い。読み込まれていなければ起動できずその場で分かるので、実装には影響しない | 4.1 の完了の確かめ方に、6.2 と同じく「読み込まれていなければ所有者に会話の始め直しを頼む」を添える。または 4.1 の確かめを 6.2 にまとめる |

### 前の段階への指摘

なし。

- 往復: 2回で収束 / 未解決: 0件
