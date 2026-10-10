# Research & Design Decisions

## Summary
- **Feature**: `spec-need-triage`
- **Discovery Scope**: Extension(既存の開発手順・スキル・ワークフローの拡張)
- **Key Findings**:
  - spec の要否を振り分ける役は、本家 cc-sdd では `/kiro-discovery` が持つが、このリポジトリは使っていない(CLAUDE.md L113)。今は起票直後の案内(`file-issue/SKILL.md` L104-107)だけが振り分けにあたり、着手時には誰も判断しない
  - GitHub のサブIssueは、このリポジトリ(個人所有・公開)で使える。gh 2.97.0 は `gh issue create --parent` を持つ。ただし、サブIssueがすべて閉じても親は自動では閉じない
  - spec.json に新しいキーを足しても壊れる読み手は無い。`issue` を読むのは spec-reviewer と kiro-spec-init だけで、どちらも番号が1つだけと想定している

## Research Log

### 着手の入口にできる既存の仕組み
- **Context**: 要件1(入口を1つにする)を、新しく作るか既存のスキルを使うか
- **Sources Consulted**: `.claude/skills/kiro-discovery/SKILL.md`(L3-4, L34-57, L121-250)、本家 cc-sdd の kiro-discovery(壁打ちの調査結果。gotalab/cc-sdd main e2a0c67)、`CLAUDE.md` L113、Claude Code の公式ドキュメント https://code.claude.com/docs/en/skills.md 、https://code.claude.com/docs/en/commands.md
- **Findings**:
  - kiro-discovery は5つの経路(既存specの更新・spec不要・spec 1本・複数spec・混在)に振り分けるが、spec 不要の経路でも「次の手を勧めて止まる」作りで、要件4.1(返事を待たずに実装を始める)と合わない
  - kiro-discovery は `brief.md` と `roadmap.md` を spec のディレクトリに書く。codex-review は `Spec:` のディレクトリの `*.md` をすべてつなげて判定の基準にする(`codex-review.yml` L162)ため、これらが判定の基準に混ざる(#341 で既知)
  - kiro-discovery には、Issueを分けたときのサブIssueの起票も、途中で見立てが外れたときの扱いも無い
  - 組み込みのコマンドに `/start` は無い。スキルの引数は `$ARGUMENTS` で受け取れる
  - `disable-model-invocation: true` を付けたスキルは、AIが自分から起動できず、AIの手元の一覧にも説明が出ない。人間が `/<名前>` と打てば動く
- **Implications**: kiro-discovery を直して使うより、新しいスキル `start` を作る方が小さい。kiro-discovery は使わない決まりのまま残す

### GitHub のサブIssue
- **Context**: 要件9(分けた部分ごとのIssue、親子の関係、親を閉じる)
- **Sources Consulted**: https://docs.github.com/en/issues/tracking-your-work-with-issues/using-issues/adding-sub-issues 、https://docs.github.com/en/rest/issues/sub-issues 、https://github.blog/changelog/2025-04-09-evolving-github-issues-and-projects/ 、https://github.com/github/gh-aw/blob/main/.github/workflows/sub-issue-closer.md 、実測(`gh api repos/DogisRiki/KeirekiPro` → owner.type User・public、`gh --version` → 2.97.0、`gh api repos/DogisRiki/KeirekiPro/issues/472 --jq '{sub_issues_summary,parent}'`、`gh issue view 472 --json parent,subIssues,subIssuesSummary`)
- **Findings**:
  - 2025-04-09 に一般提供。個人所有の無料プランでも使え、有効にする設定は無い。親1件につき100件、入れ子は8段まで
  - `gh issue create --parent <番号>` で、作ると同時に親に紐づけられる。`gh issue view` は `parent` `subIssues` `subIssuesSummary` を返す
  - GraphQL の Issue には `parent` と `subIssuesSummary { total completed }` がある(gh の JSON は GraphQL から取っている)
  - 子がすべて閉じても親は自動で閉じない。GitHub 自身が親を閉じるための定期実行のワークフローを別に持っている(gh-aw の sub-issue-closer)
  - 親が無いときの REST の `GET .../parent` は 404 を返す
- **Implications**: 親子の関係は GitHub のサブIssueで表す(要件9.3。どちらのIssueの画面からも相手が見える)。親を閉じる処理は自分で作る

### マージ後にIssueを閉じる既存の仕組み
- **Context**: 要件9.5、9.6 の閉じる役をどこに置くか(requirements の指摘 R1-2-4)
- **Sources Consulted**: `.github/workflows/close-linked-issues.yaml`(L40-41, L54-70, L73-181)、`.github/scripts/close-linked-issues.sh`(L18-34, L52-53, L118-199, L202-218, L346-466)、`.github/scripts/tests/test-close-linked-issues.sh`(L55, L100, L237-241)、`.github/scripts/lib-notice-comment.sh`
- **Findings**:
  - マージ時と毎時の見直し(マージから7日以内のPR)で、PR本文の `Closes` のIssueを閉じる。権限は `issues: write`、`github.token` だけを使う
  - `github.token` で閉じたIssueは、ほかのワークフローを起動しない(L40-41)。`issues: closed` を起点にする新しいワークフローは、このスクリプトが閉じたサブIssueでは動かない
  - スクリプトは「すべて問い合わせてから書く」作り(L52-53)。所有者への知らせは `notice_post`(メンション付きのコメント、同じ目印があれば出さない)
  - テストは偽の `gh` で、GraphQL のクエリを文字列で振り分ける。`issue(number:` を含む新しいクエリは既存の振り分けに吸われる
- **Implications**: 親を閉じる処理は close-linked-issues.sh の最後に足す。Issueの問い合わせ(ISSUE_QUERY)に `parent` と `subIssuesSummary` を足し、親の問い合わせにも同じクエリを使う。毎時の見直しがそのまま閉じ漏れを拾う

### spec.json の読み手と承認の取り消し
- **Context**: 要件5.7〜5.9(既存の spec の更新)
- **Sources Consulted**: `.claude/agents/spec-reviewer.md`(L20, L27, L30)、`.claude/hooks/spec-review-scan.sh`(L22-34, L64-74)、`.github/scripts/check-spec-backing.sh`(L45-77)、`.claude/skills/spec-review/SKILL.md`(L81-92)、`CLAUDE.md` L131-132、`.kiro/specs/container-image-vulnerability-scanning/spec.json`(L29-41)
- **Findings**:
  - どの読み手もキーの一覧で検査していない。`amendments` という独自のキーを足した前例がある
  - spec-reviewer は `issue` の番号1つで `gh issue view` する
  - 承認の取り消しは `approved_by` と `approved_at` を消す手順で、履歴は残らない
  - spec-review-scan は `phase: initialized` の spec を対象外にする。人の承認は `approved_by` に `:` を含まないことで見分ける
- **Implications**: spec.json に `additional_issues`(追加のIssue番号の並び)と `approval_history`(取り消した承認の履歴)を足す。`issue` は元のIssueのまま変えない

### codex-review の判定の基準
- **Context**: 分けた部分のPRと、更新した spec のPRが何と突き合わされるか
- **Sources Consulted**: `.github/workflows/codex-review.yml` L156-174, L209-236、過去のPR #211 #212 #223 #305 の本文
- **Findings**:
  - `Spec:` があれば spec のディレクトリの `*.md`、無ければ `Refs:` のIssue本文を判定の基準にする。PR本文は常に入力に入る
  - spec を基準にしたときは、範囲が一部であることを認める決まりが無い。過去に1つの spec を複数のPRで実装したときは、PR本文の文章で範囲を説明して通っている
  - codex-review は差分だけでなく、PRの先頭のコミットを取り出したリポジトリ全体を読める
- **Implications**: 分けた部分のPRは `Refs:` がその部分のIssueを指すため、部分の本文と突き合わされる。更新した spec のPRは、本文に「印の付いた要件だけを実装する。印の無い要件は実装済み」と書く。codex-review.yml は変えない

### 過去の着手の判断(#524)
- **Context**: Issue #524 の「直す変更まで spec が要ると判断しすぎる」の原因を確かめる
- **Sources Consulted**: このリポジトリの過去の会話の記録(`~/.claude/projects/` の下の会話ファイル)のうち、`/start` が出した「## 判断:」の報告6件(#480、#481 の2件、#499、#511、#473 の続き、#507、#520、#522)
- **Findings**:
  - 直すIssue(#499、#507、#511、#520、#522)は、どれも観点1に「当たらない」と判断されていた
  - そのうえで、どれも観点2に「当たる」と判断されていた。理由は「作り方が2つ以上ある」で、作り方ごとに所有者から見える結果が違うかは書かれていなかった(#507 は止まる時点、#511 は待ち時間、#520 は記録のしかた)
  - #499 を除くどれも観点3に「当たる」と判断されていた。理由は、Esc で止めたとき・衝突したとき・提案の中身が本文に無い、のように、Issueの目的や今の動きから決められる場合分けだった
  - #499 は観点4(DBのマイグレーション)にも当たっており、定義を直しても spec が要る
- **Implications**: 観点2と観点3の「当たる」の側が、AIが場合を1つ思い浮かべるだけで満たされる。定義を「所有者や利用者から見える結果」で書き直し、当たると書くときに根拠を義務にする

### 自動レビューが「決めた方式」をどう読むか(#524)
- **Context**: 所有者の答えをIssueの本文のどの節に書き足せば、自動レビューが答えのとおりに作られているかを確かめるか(requirements の指摘 R3-1-4)
- **Sources Consulted**: `.github/workflows/codex-review.yml` L163-200(判定の基準の決め方)、L240-247(spec 適合の観点)、L264-292(決めた方式の観点)、`.github/scripts/extract-decided-method.sh` L1-30
- **Findings**:
  - `Spec:` の無いPRでは、自動レビューは `Refs:` のIssueの本文を、PRの審査のたびに `gh issue view` で取り直す。着手のあとに書き足した節も、審査の時点の本文として読まれる
  - Issueの本文を基準にするとき、自動レビューは本文を「問題提起であって受け入れ基準の網羅的な列挙ではない」と読み、PR本文に理由があれば記述と違う作りも通す(L245-247)
  - 「## 決めた方式」の節の項目だけは、PR本文に理由があっても「沿っていない」を High にして止める(L279-285)。PRの変更から確かめられない項目は判定しない(L286)
  - 節の抜き出しは、`##` と空白のあとに `決めた方式` だけが続く行から、次の `#` か `##` の見出しの手前までである。`###` 以下は中身に含む
- **Implications**: 所有者の答えは「## 決めた方式」の節に書き足す。節が無ければ本文の末尾に作る

### Issueの本文を書き足す手段(#524)
- **Context**: 所有者の答えを Claude がIssueの本文に書き足す方法
- **Sources Consulted**: `gh issue edit --help`(gh 2.97.0。`-F, --body-file`)、`.claude/skills/file-issue/SKILL.md` L28(本文に載せるかどうか)・L141-142(制約)、2026-10-09 の会話で Claude が #507 の本文を `gh issue edit` で書き換えた実績
- **Findings**:
  - `gh issue edit <N> --body-file <ファイル>` で本文を置き換えられる。Claude の gh はボットの資格で動き、所有者が起票したIssueの本文も書き換えられる(#507 で実績あり)
  - 起票の決まりは、「起票したIssueの本文を、所有者に断らずに書き換えない」と「AIの提案を所有者が了承しただけの方式は本文に載せない」の2つを定めている。所有者の答えの書き足しは、どちらにも触れる
- **Implications**: 起票の決まりに、着手のときの答えの書き足しを2つの決まりの例外として書く。書き足しは、本文を取り出して scratchpad のファイルで直し、置き換える形にする

### 別のモデルとの壁打ち(#524)
- **Context**: 所有者が、観点の定義の直し方を Fable 5.1 と壁打ちして最適案を持ってくるよう頼んだ(2026-10-10)
- **Findings**(採ったもの): 問いの数の上限ではなく問いの形(1回・互いに独立・推奨付き・コードを読まずに答えられる)で線を引く。かかる時間の違いを見える結果に数えない。決まっていない動きを決める材料(今の動き・Issueの目的・既存の文書)を置く。当たると書くときに根拠を義務にする。観点1に「中の仕組みを足しても当たらない」を足す。PR本文に「AIが決めたこと」の節を置く
- **Findings**(採らなかったもの): 直すPRに再現テストを必ず入れる決まり、自動レビューに「AIが決めたこと」の確かめを足すこと。どちらも Issue #524 の本文に無いため(所有者に了承済み)
- **Implications**: requirements の要件2・4・7・10 の #524 の項目は、この壁打ちの結論をもとにしている

## Architecture Pattern Evaluation

| Option | Description | Strengths | Risks / Limitations | Notes |
|--------|-------------|-----------|---------------------|-------|
| 新しいスキル `start` | 着手の手順を1つのスキルにまとめる | 要件4.1 の「待たずに実装」、途中の扱い、サブIssueまで1か所で定められる | 文書の量が増える | 採用 |
| kiro-discovery を直して使う | 本家の振り分けを流用する | 振り分けの型がすでにある | brief.md が判定の基準に混ざる、spec 不要でも止まる作り、本家の更新と衝突する | 不採用 |
| CLAUDE.md に手順を書くだけ | スキルを作らず、決まりだけを書く | 変更が小さい | 所有者が打つ操作が決まらず、要件1.1 を満たせない | 不採用 |

## Design Decisions

### Decision: 入口は `/start #<Issue番号>` にする
- **Context**: 要件1.1
- **Alternatives Considered**:
  1. `/kiro-spec-init` に判断を兼ねさせる — spec を作るコマンドに「spec を作らない」判断が入り、名前と動きが食い違う。spec を始める同意(要件5の Objective)とも混ざる
  2. 新しいスキル `start` — 採用
- **Selected Approach**: `.claude/skills/start/SKILL.md` を作る。AIが自分から起動できる形にする(所有者が「#N をやって」と言葉で頼んだときも同じ手順に入るため)
- **Rationale**: spec の要否に依らず、所有者が打つものが1つになる
- **Trade-offs**: AIが自分から起動できるため、ループの中で勝手に着手しないよう、CLAUDE.md の「`/loop` から commit/push しない」の決まりに頼る
- **Follow-up**: 出荷後に、実際のIssueで `/start` を試す手順をPR本文に書く

### Decision: spec を始めるコマンドを、AIが起動できないようにする
- **Context**: 要件5.3
- **Alternatives Considered**:
  1. 決まりとして書くだけ
  2. kiro-spec-init / -requirements / -design / -tasks に `disable-model-invocation: true` を付ける — 採用
- **Selected Approach**: 4つのスキルの冒頭に1行足す。kiro-impl にはすでに付いている
- **Rationale**: 決まりだけでなく、Claude Code の仕組みで止まる
- **Trade-offs**: kiro-spec-quick が内部で requirements・design・tasks を呼べなくなる。kiro-spec-quick は CLAUDE.md が禁じる自動承認を使うスキルで、所有者が名指ししたときだけ動く例外であり、使われていない

### Decision: 既存の spec の更新は `/kiro-spec-init #<新Issue> <feature>` で始める
- **Context**: 要件5.4〜5.9、requirements の指摘 R1-3-1(承認を取り消す時点)
- **Alternatives Considered**:
  1. `/start` の中でAIが承認を取り消す — 所有者が同意する前に承認が消える
  2. kiro-spec-init に更新の形を足し、所有者がコマンドを打った時点で取り消す — 採用
- **Selected Approach**: kiro-spec-init は、2つ目の引数に既存の feature 名があれば更新の形で動く。取り消す前の承認を `approval_history` に写し、新しいIssueを `additional_issues` に足し、要望の欄に新しいIssueの本文を足す
- **Rationale**: 所有者がコマンドを打つことが同意になる、という今の決まりのまま進められる
- **Trade-offs**: 更新では、要件・設計・タスクの3段階すべての承認を取り消す(新しいIssueの要望は必ず要件から入るため)

### Decision: 親のIssueは close-linked-issues.sh が閉じる
- **Context**: 要件9.5、9.6、指摘 R1-2-4
- **Alternatives Considered**:
  1. 最後の部分のPRに親の `Closes` も書く — 部分のPRが同時に進むと、どれが最後か分からない
  2. `issues: closed` を起点にする新しいワークフロー — `github.token` で閉じたサブIssueでは起動しない
  3. close-linked-issues.sh の最後に、親を閉じる処理を足す — 採用
- **Selected Approach**: 閉じた(または閉じていた)`Closes` のIssueに親があれば、親の子がすべて閉じているかを確かめて閉じる。親にさらに親があれば、同じことを上へ繰り返す
- **Rationale**: マージ時と毎時の見直しの両方で動く。既存の知らせの仕組みを使える
- **Trade-offs**: PRのマージ以外で閉じたサブIssueは拾わない(所有者はIssueを閉じない決まりのため、起きない想定)

### Decision: 途中で spec に切り替えるとき、それまでの実装はローカルのブランチに残す
- **Context**: 要件7.3、7.7、指摘 R1-1-5
- **Selected Approach**: 実装の途中で止めたときは、それまでの変更をいまのブランチにコミットし、push しない。200行の検査で止まったPRは閉じる。spec の実装でその変更を使うかは tasks で決める
- **Rationale**: 未コミットの変更を残すと停止時の検査(check-verify-before-stop.sh)に止められる。捨てると、使える変更を失う

### Decision: 観点2と観点3を、所有者や利用者から見える結果で定義し直す(#524)
- **Context**: Issue #524、requirements の要件2
- **Alternatives Considered**:
  1. 今ある動きを直す変更は、観点4に当たらない限りすべて spec 無しにする — 直しの形をした仕様の変更(数え方を変える等)が、所有者の決定なしに通る
  2. 行数以外の大きさの目安(変えるファイルや領域の数)を足す — 大きさは、所有者が決めることが残っているかと関係が無い。要件2.4 の「行数を使わない」とも趣旨が合わない
  3. 見える結果が決まっているかで線を引き、決まらないものは1回尋ねるか spec にする — 採用
- **Selected Approach**: `/start` の観点の表と判断の手順を、要件2の定義と根拠の義務のとおりに書き直す
- **Rationale**: spec の役目のうち、所有者が何を作るかを決めることだけが、直す変更で spec を要る理由になる。設計の審査は自動レビューが、大きな変更の分割は200行の検査が受けている
- **Trade-offs**: AIが「今の動きのまま」で決める範囲が広がる。所有者は、PR本文の「AIが決めたこと」を読んで確かめる

### Decision: 所有者の答えは、Issueの本文の「## 決めた方式」の節に書き足す(#524)
- **Context**: 要件4.3、requirements の指摘 R3-1-4
- **Alternatives Considered**:
  1. 「どうなれば解決か」に書き足す — 自動レビューは、PR本文に理由があれば違う作りも通す
  2. PR本文の「AIが決めたこと」にだけ残す — 自動レビューは答えを守らせない
  3. 「決めた方式」に書き足す — 採用
- **Selected Approach**: 起票の決まりに例外を書き、`/start` が答えを「## 決めた方式」の節に書き足す
- **Rationale**: 自動レビューが、PR本文の理由に依らず答えから外れた作りを止める。`.github/` を変えずに済む
- **Trade-offs**: 「決めた方式」に、作り方だけでなく見える動きも入る。PRの変更から確かめられない答え(所有者の操作など)は、自動レビューが判定しない

### Decision: spec 無しで変えた動きは、spec を更新するときに拾う(#524)
- **Context**: 要件4.7、範囲の節の前提、requirements の指摘 R3-2-2・R3-3-4
- **Alternatives Considered**:
  1. spec 無しのPRで spec の本文も直す — 承認済みの本文を、承認を経ずに書き換えることになる
  2. 食い違いを捨て置く — 次の更新の審査の基準が古いまま残る
  3. PR本文に決まった形の1行で食い違いを残し、spec を更新するときに検索して直す — 採用
- **Selected Approach**: PR本文の「AIが決めたこと」に `- 食い違う spec: \`.kiro/specs/<feature>/<文書>\` <箇所>` の行を書く。kiro-spec-requirements と kiro-spec-design は、更新のときに、マージ済みのPRからこの行を探して本文に反映する
- **Rationale**: 承認の手順を経て spec の本文を直せる。行の形を決めておけば検索で拾える
- **Trade-offs**: 次の更新が来るまで、spec の本文はコードと食い違ったままになる

## Risks & Mitigations
- (#524) AIが「今の動きのまま」を広く使い、所有者が決めるべき動きを問わずに決める — PR本文の「AIが決めたこと」に材料ごとに残す。所有者が読んで違えば、新しいIssueで直す
- (#524) 所有者の答えが問いに答えていない — `/start` は、答えで決まらない動きが残ったら spec に改める(要件4.4)
- AIが4つの観点を甘く判断し、spec の要る変更を spec 無しで進める — 判断の根拠を所有者に示す(要件3)。途中で気づいたら止まる(要件7)。200行の検査が最後に止める
- 更新した spec のPRが、実装済みの要件まで未実装と判定される — PR本文で範囲を説明する。誤った判定は review-loop の誤検知の扱いで処理する
- `.claude/` と `.github/` の変更が書き込みの禁止に止まる — 既存のやり方(scratchpad で作り、所有者がコピーのコマンドを打つ)で反映する。.github/ の変更を含むPRは CODEOWNERS により所有者の承認までマージされない

## References
- [Claude Code Skills](https://code.claude.com/docs/en/skills.md) — `disable-model-invocation` と引数
- [Claude Code Commands](https://code.claude.com/docs/en/commands.md) — 組み込みのコマンドの一覧
- [Adding sub-issues](https://docs.github.com/en/issues/tracking-your-work-with-issues/using-issues/adding-sub-issues) — 上限
- [REST API: Sub-issues](https://docs.github.com/en/rest/issues/sub-issues) — 親子の取得と追加
- [gh-aw sub-issue-closer](https://github.com/github/gh-aw/blob/main/.github/workflows/sub-issue-closer.md) — 親が自動で閉じないことの傍証
