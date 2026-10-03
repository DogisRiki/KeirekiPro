# design レビューの記録

## サイクル1 往復1(2026-10-02)

審査の材料: `design.md`(全文)、`requirements.md`(全文。所有者が承認済み)、`research.md`(全文)、`spec.json`(issue 477、`spec_format` 2、`additional_issues` 無し)、`reviews/requirements-review.md`・`requirements-response.md`・`design-style.md`、Issue #477 本文(`gh issue view 477`。コメントは読んでいない)、`.kiro/settings/templates/specs/design.md`(審査の基準の雛形)と `tasks.md`・`init.json`、`.kiro/settings/rules/spec-writing.md`(全文)、`.claude/hooks/spec-review-scan.sh`(全文。L157〜165)と `tests/test-spec-review-scan.sh`(全文)、`.github/scripts/check-spec-backing.sh`(全文。L14、L74〜79)と `tests/test-check-spec-backing.sh`(全文)、`.claude/skills/kiro-impl/SKILL.md`(全文)と `templates/implementer-prompt.md`、`.claude/skills/kiro-spec-init/SKILL.md`(全文。L69)、`.claude/skills/spec-review/SKILL.md`(全文)、`.claude/agents/spec-style-checker.md`・`spec-reviewer.md`(`model: claude-fable-5-1`)、`.claude/settings.json`(deny の一覧)、`.github/CODEOWNERS`、`.github/workflows/guardrails.yaml` L130〜179、`.kiro/specs/*/spec.json`(11件)、`.kiro/specs/spec-readable-writing/design.md` L189 と同 spec の「プロジェクトの決まりを守っているか」の節、`spec_format` を持つファイルの一覧(`.kiro/specs` を除いて27ファイル)と古い名前を持つファイルの一覧(24ファイル)、`.kiro/settings/templates/specs-v1/`(4ファイル)、`ears-format.md`、`tasks-generation.md` L42・L181、`design-discovery-full.md` L10、`gap-analysis.md` L25、README・`doc/`・steering 3文書(`spec_format`・EARS・`specs-v1` への言及は無い)。

確かめた結果、design.md の「ファイルの構成」に挙げたファイルは、`spec_format` を読む27ファイルと古い名前を持つ24ファイルのすべてを覆っている。design.md が名指しした行番号(`spec-review-scan.sh` L157〜165、`check-spec-backing.sh` L14・L74〜79、`kiro-spec-init` L69、`tasks-generation.md` L42・L181、spec-readable-writing の design.md L189)は実ファイルと一致する。古い書き方の spec は9件で名前も一致し、9件とも3段階が `DogisRiki` の承認済みである。`{{英大文字}}` の形を本文に持つ spec は、spec-readable-writing の design.md L189 と、本 spec の requirements.md の Issue 引用(L16・L22)だけである。

### 申告

**1. 確かめ役を、定義ファイルを持たない汎用のサブエージェントとして `model: "fable"` で起動する** — 「書き換えの確かめ役」の節、research.md の比べた案

- Issue の記載: あり(「Fable 5.1 のサブエージェントが…確かめる」)。ただし起動のしかたは書かれていない
- 決めたこと: `.claude/agents/` に定義を足さず、Agent ツールに `subagent_type: "general-purpose"` と `model: "fable"` を渡して起動し、指示は design.md の文面を毎回渡す
- 他にありえた選択肢: spec-reviewer と同じく `.claude/agents/` に定義ファイルを置き、`model: claude-fable-5-1` で固定する。または Agent ツールの `model` に、定義ファイルと同じ値 `claude-fable-5-1` を渡す
- 外れていた場合: `"fable"` が受け付けられなければ確かめ役を起動できない。受け付けられずに既定のモデルで動いた場合は、確かめ役がこのセッションと同じモデルになり、Issue の「決めた方式」(別のモデルが確かめる)が満たされないまま承認が記録される(指摘 D1-1-2)

**2. `ready_for_implementation` を検査が読まないようにし、欄を雛形とすべての spec.json から消す** — 「check-spec-backing.sh」「spec.json の欄の削除」の節、research.md の比べた案

- Issue の記載: あり(「`ready_for_implementation` を true にするスキルが無い。一方で検査は true を求める」)。どちらを直すかは書かれていない
- 決めたこと: 検査は3段階の `approved` だけを見る。欄は `init.json` と11件の spec.json から消す。`.github/scripts/` の変更になるので、所有者が写し、CODEOWNERS の承認を経る
- 他にありえた選択肢: `/kiro-spec-tasks` の承認のときに true を書き、取り消しのときに false にする(検査は変えない)。または欄を消さずに残す
- 外れていた場合: 検査が「3段階の承認」だけで通る形になるので、承認の記録の意味が3段階に一本化される。欄を残す案を所有者が望んでいた場合、11件の spec.json から欄を消した変更を戻すことになる

**3. 特例の承認を `approved_by: "DogisRiki"`・`approved_at: 記録した時点` で書き、特例であることは `approval_basis` の欄で示す。書き換える前の承認は、取り消しの形(`revoked_at` `revoked_for`)のまま `approval_history` に残す** — 「書き換えの進め役」の節

- Issue の記載: あり(「承認済みとして記録してよい。所有者は承認し直さない」)。記録の形は書かれていない
- 決めたこと: 判定のスクリプトが ':' を含む `approved_by` を人の承認と見ないので、`approved_by` は所有者の名前にし、`approval_basis` で区別する。履歴の要素は CLAUDE.md の取り消しの形をそのまま使い、`revoked_for` に特例の理由を書く
- 他にありえた選択肢: `approved_at` を書き換え前の日時のまま残す。履歴の要素に `revoked_*` を使わず、別の名前(`replaced_at` など)の形を足して CLAUDE.md を直す
- 外れていた場合: `approved_at` が所有者の操作の無い日時になり、`approval_basis` を読まない人が、所有者がその日時に承認したと読む。履歴の要素は、取り消していない承認が「取り消し」として残る

**4. 3回目の確かめも食い違ったら、その時点で `/kiro-impl` の実行を止め、残りの spec の書き換えにも進まない** — 「処理の流れ」「書き換えの進め役」「失敗したときの扱い」の節

- Issue の記載: なし
- 決めたこと: 止めた spec の本文を戻し、`_保留:_` を付け、実装を止めて所有者に知らせる。それまでに済んだ spec の書き換えと特例の承認はブランチに残す
- 他にありえた選択肢: 止めた spec を保留にしたまま、残りの spec の書き換えを続け、道具の直しの前で止める(所有者が一度にすべての食い違いを見られる)
- 外れていた場合: 所有者が止めた spec の進め方を決めて再開しても、残りの spec でまた止まり、所有者の判断が spec の件数ぶん繰り返される

**5. 書き換えを先に、道具の直しをあとに、spec.json の欄の削除を最後に置く** — 「全体の構成」の節

- Issue の記載: なし
- 決めたこと: 書き換えのあいだは今の道具と対応表をそのまま使い、道具の直しは書き換えがすべて確かめられてから行う
- 他にありえた選択肢: 道具の直しを先に行い、書き換えのあいだは古い spec を新しい道具で読まない
- 外れていた場合: `/kiro-impl` 自身を含む道具を実装の途中で書き換えるので、道具の直しのタスクの後に残る書き換えのタスクが無いことが前提になる。順番が崩れると、直した道具が書き換え前の spec を新しい書き方として読み違える

### 指摘

| ID | レベル | 該当箇所 | 内容 | 直し方の案 |
|---|---|---|---|---|
| D1-1-1 | 中 | design.md 処理の流れ(Record → Review → Commit)、書き換えの進め役の節 | 特例の承認を記録したあとに `/kiro-impl` の審査役が動く。審査役が REJECTED を返すと、`kiro-impl/SKILL.md` の手順(d)(「REJECTED (round 1-2) → re-dispatch implementer」、debug の `RETRY_TASK` も同じ)により実装役が本文をもう一度書き換える。design はこの経路を扱っておらず、確かめ役が「同じ」と確かめた本文と、コミットされる本文が違いうる。`approval_basis` は「Fable 5.1 が確かめた」と書くので、確かめていない本文に特例の承認が付く。Issue の「決めた方式」(確かめた結果に問題が無ければ承認済みとして記録してよい)の前提が崩れる | 承認の記録を、審査役が APPROVED を返したあと、コミットの前に行う。または、確かめ役が「同じ」を返したあとに実装役が本文を変えたら(審査役の差し戻し、debug の再実装のどちらでも)、確かめ役をもう一度起動し、「同じ」が最後の変更より後にあるときだけ承認を記録すると書く。回数の数え方(3回の上限に含めるか)も決める |
| D1-1-2 | 中 | design.md 使う既存の仕組み、書き換えの確かめ役の節の「呼び出し方」 | `model: "fable"` が Agent ツールで受け付けられる値であることの根拠が無い。リポジトリに Fable 5.1 を使う前例は `.claude/agents/spec-reviewer.md` の `model: claude-fable-5-1`(定義ファイルの中の完全なID)だけで、`"fable"` の形で起動した例は無い。`/spec-review` は「起動時の指定は定義より優先される」とし、起動時の指定に頼らず定義ファイルで固定している。受け付けられなければ確かめ役を起動できない。受け付けられずに既定のモデルで動けば、確かめ役がこのセッションと同じモデルになり、Issue が求めた「別のモデルが確かめる」が満たされないまま承認が記録され、誰も気づかない | `model` に、前例のある完全なID `claude-fable-5-1` を渡す(または定義ファイルを置く案に変える)。あわせて、確かめ役の記録の節に「確かめ役のモデル: <自分のモデルID>」の行を書かせ、進め役は、その行が `claude-fable-5-1` でないときは承認を記録せず止まる、と書く。これで実装のときに実測の証跡が残る |
| D1-1-3 | 中 | design.md 書き方を読み分けないスキルと点検役の節(「`approval_basis` があれば、それも同じ名前で写す」)、spec-writing.md と雛形と CLAUDE.md の節 | 特例の承認を後で取り消すときの `approval_basis` の扱いが、履歴に写すことしか書かれていない。`/kiro-spec-init` の更新の形(SKILL.md L67)と `/spec-review` の Step 6(L137)は、取り消しで `approved_by` と `approved_at` を消すが、`approval_basis` は消す対象に無い。書き換えた spec を新しいIssueのために開き直すと、`approval_basis` が段階に残ったまま `approved: false` になり、所有者が本文を読んで承認し直したあとも、その段階に「所有者は本文を読んで承認し直していない」と書いた欄が残る。要件3の項目4(特例かどうかが記録から分かる)と項目6(特例は今回だけ)に反する記録になる | 取り消しのときに、`approval_basis` を履歴に写したあと、その段階から `approved_by`・`approved_at` と同じく `approval_basis` も消す、と `/kiro-spec-init` の更新の形と `/spec-review` の Step 6 の両方に書く。CLAUDE.md の取り消しの決まり(「`approved_by` / `approved_at` を削除」)にも `approval_basis` を足す |
| D1-1-4 | 低 | design.md 書き換えの実装役の節(「この spec の本文に空欄の目印の形をそのまま書くと、この spec も200行を超えるPRの検査で赤になるので」) | 理由が事実と合わない。本 spec の requirements.md は Issue の引用として `{{NUMBER}}` `{{TITLE}}` を L16・L22 に持ち、検査は requirements.md も対象にする(`check-spec-backing.sh` L66〜68)ので、design.md で目印の形を避けても、この spec は検査に掛かれば赤になる。実際に赤にならないのは、この spec のPRが200行に届かないから(research.md「200行の検査で数える行」。`guardrails.yaml` L139〜148 で `*.md` と `.kiro/**` は数えない)である | 記録のみ。理由を「この spec のPRは200行に届かないので検査に掛からないが、design.md にまで目印の形を増やさない」のように、事実に合う形に直してもよい |
| D1-1-5 | 低 | design.md 書き換えの確かめ役の節の「呼び出し方」の指示文(「決められた書式で書き足す」)と「状態の持ち方」 | 確かめ役に渡す指示の文面には記録の書式が含まれておらず、「決められた書式」が何かを確かめ役は知る手段が無い(design.md を読めとも書いていない)。書式は「状態の持ち方」の欄に別に書かれている。また、サブエージェントは作業ディレクトリが起動のたびに戻るので、「作業場所の .kiro/specs/<feature>/<ファイル>」は絶対パスで渡す必要がある。点検役も 165行目として挙げ、直すと指示の中身が変わるとして残した箇所 | 記録のみ。「呼び出し方」に、指示の文面といっしょに「状態の持ち方」の書式のブロックも渡す、と1文足す。パスは絶対パスで渡すと書く |
| D1-1-6 | 低 | design.md spec-writing.md と雛形と CLAUDE.md の節、テストの方針(`grep -rn "spec_format" .claude .kiro/settings CLAUDE.md`)、作らないもの | `spec-writing.md` の tasks.md の見本(L242「この scan は、`spec_format` が2の spec で、…」)が `spec_format` を含む。この見本は Issue #474 からの引用ではなく、作らないものの「見本1・見本2の本文」には当たらないが、design は spec-writing.md の直しとして「冒頭の段落」「印と ears-format.md と specs-v1/ の記述」「対応表」しか挙げていない。残すと、テストの方針の grep の出力が「作らないものに挙げたファイルだけ」にならない | 記録のみ。tasks.md の見本の文も新しい書き方だけの文(例: 「この scan は、点検の記録が無いときと、本文が点検の記録より新しいときに、理由を出す。」)に直すと書くか、見本を直さない理由を作らないものに足す |
| D1-1-7 | 低 | design.md プロジェクトの決まりを守っているか(「品質チェックの設定」の行) | ゲート設定として `.claude/hooks/spec-review-scan.sh` と `.github/scripts/check-spec-backing.sh` だけを挙げるが、CODEOWNERS は `/.claude/` 全体(skills・agents を含む)を所有者の承認の対象にしている(`.github/CODEOWNERS` L16)。spec-readable-writing の design はこの点を同じ節に書いている(「`.claude/skills/` と `.claude/agents/` の変更も、CODEOWNERS により所有者の承認を経てマージされる」)。実装に影響は無い | 記録のみ。`.claude/skills/` と `.claude/agents/` の変更も CODEOWNERS の承認を経ることを同じ行に足してもよい |

### 前の段階への指摘

なし。

- 往復: 1回目 / 高0 中3 低4

## サイクル1 往復2(2026-10-02)

審査の材料: `design.md`(往復1の対応後の全文)、`requirements.md`(全文)、`research.md`(全文)、`spec.json`、`reviews/design-review.md`(往復1)・`design-response.md`・`design-style.md`(点検2回分)、Issue #477 本文(`gh issue view 477`。コメントは読んでいない)、`.claude/skills/kiro-impl/SKILL.md`(全文。手順(d)の差し戻しと debug の `RETRY_TASK` の経路)と `templates/implementer-prompt.md`、`.claude/hooks/spec-review-scan.sh`(全文。L74 の人の承認の判定、L157〜165)と `tests/test-spec-review-scan.sh`(全文。場合1〜5b)、`.github/scripts/check-spec-backing.sh`(全文。L14、L74〜79)と `tests/test-check-spec-backing.sh`(全文。`write_spec_json` の4つ目の引数、`m_not_ready`、`m_no_approvals_key`)、`.claude/skills/kiro-spec-init/SKILL.md` L55〜79(更新の形の取り消しの手順。L67 で `approved_by` と `approved_at` だけを消す)、`.claude/skills/spec-review/SKILL.md` L123〜137(Step 6 の取り消し)、`.kiro/settings/templates/specs/tasks.md`(全文。完了条件の節 L31〜42 と欄の名前 L18〜19)、`.kiro/settings/rules/spec-writing.md` の「受入基準とテストの対応」の箇所(L185・L188・L243〜244・L250)、`.kiro/specs/spec-readable-writing/spec.json`(3段階が `DogisRiki` の承認済み)、`.claude/hooks/` の一覧(spec の本文の書き込みを止めるフックは無い)。

往復1の修正の確かめ:

- D1-1-1: 処理の流れの図が Check(同じ)→ Review → Record → Commit の順になり、Review の差し戻しが Redo → Check に戻る。書き換えの進め役の節は、審査役の差し戻し後の確かめを3回の数に入れ、「審査役が承認し、最後の確かめが今の本文について `RESULT: same` なら」コミットの前に記録すると書く。`kiro-impl/SKILL.md` の手順(d)(APPROVED → verify → `[x]` → commit)の間に記録を挟む形で、矛盾は無い。直っている
- D1-1-2: 確かめ役の応答に `MODEL:` の行を足し、進め役がそれを `claude-fable-5-1` と照らし、違えば結果を使わず止める。design の本文に「Agent ツールの `model` の引数は `sonnet` `opus` `haiku` `fable` の4つの値だけを受け付け、完全なIDは受け付けない」と書かれた。この値の一覧はレビュー役からは確かめられない(response に「このセッションの Agent ツールの定義による」とある)が、`MODEL:` の行の照合で、`fable` が別のモデルに向いたときは実装のときに止まる。承認が誰にも気づかれず記録される経路は塞がれている。直っている(残る点は D1-2-1)
- D1-1-3: 「書き方を読み分けないスキルと点検役」の節に、`/kiro-spec-init` と `/spec-review` が承認を取り消すときに `approval_basis` を履歴に写したあと段階から消すこと、CLAUDE.md の取り消しの決まりに `approval_basis` を足すことが書かれた。直っている

あわせて確かめたこと: 試験の変更の記述(場合1〜5bの名前と中身、`write_spec_json` の4つ目の引数、`m_no_approvals_key` が `{ "ready_for_implementation": true }` であること)は実ファイルと一致する。tasks.md の雛形の完了条件の節の書き直し(要件5)は、欄の名前「受入基準とテストの対応」を雛形 L19・見本 L244 と同じ表記で指し、決めごと4つを今の節 L35〜42 のとおりに残している。「書き換えの実装役は spec.json と `reviews/` に書き込まない」は、`implementer-prompt.md` の「Do NOT update `tasks.md`」「Do NOT create commits」と矛盾しない。design.md の中で節どうしの食い違いは見つからなかった。

### 申告

往復1の申告1〜5に変わりは無い。申告1は、往復1の対応で「`fable` が Fable 5.1 を指す」ことを `MODEL:` の行で実装のときに確かめる形になった。

### 指摘

| ID | レベル | 該当箇所 | 内容 | 直し方の案 |
|---|---|---|---|---|
| D1-2-1 | 低 | design.md 書き換えの確かめ役の節(「Agent ツールの `model` の引数は、`sonnet` `opus` `haiku` `fable` の4つの値だけを受け付け…」)、プロジェクトの決まりを守っているかの「関係のない項目」 | 受け付ける値の一覧を事実として書いているが、いつ何で確かめたかが本文に無い(design-response.md には「このセッションの Agent ツールの定義による」とある)。審査の基準は、前提にした機能が使えるという主張に、確かめ方を添えることを求める。実装への影響は無い。`fable` が受け付けられなければ Agent ツールの起動が失敗し、別のモデルに向けば `MODEL:` の行の照合で止まるので、承認が誤って記録される経路は無い | 記録のみ。この文に「(2026-10-02、メインセッションの Agent ツールの引数の定義で確かめた)」のように確かめ方を添えるか、「使う外部の機能がこのリポジトリで使えるか」の項目に同じ内容を書いて、関係のない項目の行から外す |
| D1-2-2 | 低 | design.md 書き換えの進め役の節の「呼び出し方」(「3回目も `different` なら…戻す」「審査役が差し戻したら…この確かめも3回の数に入れる」) | 3回の上限は `different` が3回目に出たときの文でしか書かれていない。確かめが `same` のまま審査役の差し戻しが重なり(`kiro-impl/SKILL.md` は差し戻しを2回まで実装役に戻し、3回目は debug の `RETRY_TASK` で新しい実装役に直させる)、4回目の確かめが要る場合と、前の確かめが `same` で3回目以降に初めて `different` が出た場合の扱いが、文のとおりには決まらない。「最後の確かめが今の本文について `same`」の条件があるので、確かめていない本文に承認が記録されることは無い。進め役がその場で判断する余地が残るだけで、実装には影響しない | 記録のみ。「確かめの回数が3回に達したあとで本文が変わったら、`different` の有無にかかわらず本文を戻して止める」のように、上限を回数だけで決める1文にしてもよい。tasks でこの流れを書くときに合わせる |

### 前の段階への指摘

なし。

- 往復: 2回で収束 / 未解決: 0件

## サイクル2 往復1(2026-10-02)

審査の材料: `design.md`(`approval_basis` を取り除いたあとの全文)、`requirements.md`(全文。所有者が承認済み)、`research.md`(全文。「承認の判定と特例の承認の記録」の節が新しい形に合わせて直されている)、`spec.json`(issue 477、`additional_issues` 無し、design は未承認)、`reviews/design-review.md`(サイクル1)・`design-response.md`・`design-style.md`(点検3回分)、Issue #477 本文(`gh issue view 477`。コメントは読んでいない)、`.claude/hooks/spec-review-scan.sh`(L74 の人の承認の判定、L157〜165 の点検の判定)と `tests/test-spec-review-scan.sh`(全文。場合1〜5b)、`.claude/skills/kiro-spec-init/SKILL.md` L50〜88(更新の形。L54〜67 の `approval_history` の要素の形と取り消しで消す欄、L69・L71)、`.claude/skills/spec-review/SKILL.md` L115〜147(Step 6 の `approval_history` の要素の形と取り消しで消す欄、Step 7)、`CLAUDE.md` L150〜159(承認と取り消しの決まり。`approval_history` の要素が持つ6つの欄)、`.kiro/specs/*/spec.json`(11件。`additional_issues` と `approval_history` を持つ spec は無く、`amendments` は container-image-vulnerability-scanning だけ)、`approval_basis` の文字列の全文検索(残っているのは `reviews/` の過去の記録だけ)。

このサイクルの変更の確かめ:

- `approval_basis` の欄は design.md から無くなっている(作るものの「新しい欄は足さない」、書き換えの進め役の「承認の欄に新しい欄を足さない」、書き方を読み分けないスキルと点検役の「承認を `approval_history` に写して取り消す手順は変えない」、spec-writing.md と雛形と CLAUDE.md の節のどこにも残っていない)。サイクル1の D1-1-3 で指摘した「取り消しのときに欄が段階に残る」経路は、欄そのものが無くなったので消えている
- 特例の承認の示し方は、`approval_history` の要素の `revoked_for`(「Issue #477 の特例: …所有者は本文を読んで承認し直していない」)と、今の承認の `approved_at` がその要素の `revoked_at` と同じ値になることの2つで決まっている。要件3の項目2(書き換える前の承認と理由を履歴に追記する)と項目4(特例によるものだと記録から分かる)を満たす。要素の形(`stage` `approved_by` `approved_at` `issues` `revoked_at` `revoked_for`)は、CLAUDE.md L158、`kiro-spec-init` L55〜64、`spec-review` L124〜133 の形と同じで、取り消しの手順を変えずに済む
- `approved_by` を `DogisRiki` にする理由(判定のスクリプト L74 が ':' を含む `approved_by` を人の承認と見ない)は実ファイルと一致する。試験の場合6(`approved` が true、`approved_by` が `DogisRiki`、`approval_history` に特例の要素)は、L74 で判定の対象から外れるので、点検についての理由が出ないという期待で正しい。要件3の項目5を試験で確かめる形になっている
- 判定のスクリプトの変更(L157〜165 の `spec_format` の条件を外す)と試験の変更(場合1の期待を変え、場合2〜5bから `"spec_format":2` を消す)は、実ファイルの行と場合の名前に一致する
- 「設計を見直すきっかけ」が指す節の名前(「書き換えの進め役」)は本文の節と一致する。節どうしの食い違いは見つからなかった
- サイクル1で記録のみとした D1-1-4〜7・D1-2-1・D1-2-2 は、この往復では再び出さない

### 申告

サイクル1の申告1・2・4・5に変わりは無い。申告3は、`approval_basis` が無くなったので、次のとおり改める。

**3. 特例の承認を `approved_by: "DogisRiki"`・`approved_at: 記録した時点` で書き、特例であることは `approval_history` の要素の `revoked_for` と、`approved_at` が同じ要素の `revoked_at` と同じ値であることで示す。新しい欄は足さない** — 「書き換えの進め役」の節

- Issue の記載: あり(「承認済みとして記録してよい。所有者は承認し直さない」)。記録の形は書かれていない。欄を足さないことは所有者の指示(research.md「承認の判定と特例の承認の記録」)
- 決めたこと: 判定のスクリプトが ':' を含む `approved_by` を人の承認と見ないので、`approved_by` は所有者の名前にする。履歴の要素は CLAUDE.md の取り消しの形をそのまま使い、`revoked_for` に特例の理由を書く。段階の欄には今の6つの欄以外を足さない
- 他にありえた選択肢: `approved_at` を書き換え前の日時のまま残す(履歴の要素と段階の欄が同じ日時になるので、特例の有無を日時の一致で見分けられなくなる)。履歴の要素の `revoked_for` だけで示し、`approved_at` の一致を決めない
- 外れていた場合: 書き換えた spec を後で新しいIssueのために開き直すと、特例の承認は `revoked_for: "Issue #N のための更新"` の要素として履歴に移る。その要素が特例によるものだったことは、1つ前の要素の `revoked_for` の文と、`approved_at` と `revoked_at` の一致から読み取ることになり、欄で直接は示されない

### 指摘

なし。

### 前の段階への指摘

なし。

- 往復: 1回で収束 / 未解決: 0件
