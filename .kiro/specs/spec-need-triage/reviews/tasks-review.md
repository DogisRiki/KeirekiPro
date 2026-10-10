# tasks レビュー記録: spec-need-triage

## サイクル1 往復1(2026-10-02)

審査の材料: `tasks.md`(全文)、`design.md`(全文。承認済み)、`requirements.md`(全文。承認済み)、`research.md`、`spec.json`(issue 472、tasks 未承認)、Issue #472 本文(`gh issue view 472`。コメントは読んでいない)、design の review と response(全往復)、`.kiro/settings/templates/specs/tasks.md`、`.claude/skills/kiro-spec-tasks/rules/tasks-generation.md`、steering 3文書、`CLAUDE.md`、`README.md`(L95〜114、L296〜407)、`doc/開発フロー/監査手順.md`(L90〜129)、`.github/scripts/close-linked-issues.sh`(全文)、`.github/scripts/tests/test-close-linked-issues.sh`(全文)、`.github/scripts/lib-notice-comment.sh`(`_notice_author_comments`・`notice_post` の入口)、`.github/workflows/guardrails.yaml`(L1〜200)、`.github/workflows/close-linked-issues.yaml`(`result=` と親子の語を grep。無し)、`.claude/skills/kiro-spec-init|-requirements|-design|-tasks|kiro-impl|file-issue|ship|spec-review/SKILL.md`、`.claude/skills/spec-review/rules/requirements.md`、`.claude/agents/spec-reviewer.md`、`.claude/hooks/spec-review-scan.sh`(全文)、`.claude/` 配下で kiro-spec の各段階を参照する箇所の grep、全スキルのフロントマター。`brief.md` は無い。

要件カバレッジ: 要件1〜10 の受入基準 51件すべてが、少なくとも1つのタスクの `_Requirements:_` に現れる(1.1〜1.7 → 3.1・4.1、2.1〜2.4・3.1〜3.3 → 4.2、4.1・4.2 → 4.3・6.2、5.1〜5.9 → 2.1・2.2・2.3・4.2・4.3・5.1、6.1〜6.4 → 4.2・4.3、7.1〜7.7 → 3.1・3.2・4.4、8.1・8.2 → 5.1・4.4、9.1〜9.6 → 1.1〜1.3・3.1・3.2・4.3・5.3、10.1〜10.7 → 2.3・3.1・5.1・5.2)。requirements に無い番号を参照するタスクは無い。

design カバレッジ: design のコンポーネント7つ(start、kiro-spec-init の更新の形、file-issue の変更、ship の変更、spec の審査の変更、ParentCloser、文書の変更)と、Modified Files の14件・新規1件が、いずれかのタスクで扱われている。Testing Strategy の単体テスト8項目は 1.1(親の無いIssue)・1.2(6項目)・1.3(失敗)に、スキルと文書の確認4項目と design の審査で tasks に申し送られた D1-1-5・D1-1-6・D1-1-8・D1-2-2〜D1-2-5 は 2.2・2.3・4.1・4.4・5.1・6.1 に入っている。design の Error Handling の4項目(gh の失敗、サブIssueの起票の途中の失敗、spec.json を先に書く、ParentCloser の失敗)も 4.1・4.3・2.2・1.3 にある。`(P)` のタスクの `_Boundary:_` は、2.1(kiro-spec-requirements / -design / -tasks)・2.2(kiro-spec-init)・2.3(spec-reviewer、spec-review)・3.1(file-issue)・3.2(ship)・5.1〜5.3(CLAUDE.md、README、監査手順)で互いに重ならず、File Structure Plan の範囲に収まる。

スコープ: requirements の Out of scope(200行の検査、3段階の承認、`/request` の中身)と design の Non-Goals・Out of Boundary(codex-review.yml、auto-merge.yaml、kiro-spec-quick / -batch、PRのマージ以外で閉じた子からの親のクローズ)にあたる作業は、どのタスクにも入っていない。2.1 は Out of Boundary の例外(冒頭の1行と、kiro-spec-requirements への2行)の範囲に収まり、「4つのスキル」の読み方(init・requirements・design・tasks。kiro-impl は付いているので変えない)を本文に明記している。これは research.md の Decision と Modified Files に一致する。

完了条件の4項目: 受入基準とテストの対応付け・verify・ゴールハック禁止・新規テストの赤の確認の4項目があり、verify の置き換え(変更領域が3つの verify Skill の対象外のため、guardrails と同じ同梱テストと shellcheck を手元で流す)に理由が書かれている。

並列と依存: `(P)` の指定は、同じグループの中でファイルが重ならないものだけに付いている。4.1〜4.4 は同じ `start` の SKILL.md を順に書くので `(P)` が無い。`_Depends:_`(4.1 → 2.2、4.3 → 3.1、5.3 → 1.3)は順序からも成り立つ依存で、矛盾は無い。3.2 が `/start` の「途中で見立てが外れたとき」(4.4 で書く)を、2.3 が 2.1 の決定を参照するが、どちらも文書の相互参照で、6.1 が見出しの実在を確かめる。

実現できない前提: 同梱テストが要るコマンド(bash・jq・coreutils の `timeout -k`・grep・sed)は、完了条件2の alpine コンテナの構成で揃う。`disable-model-invocation: true` を kiro-spec-requirements / -design / -tasks に足しても、所有者の入力で動く `notify-spec-review.sh`(UserPromptExpansion)と `spec-review-scan.sh`(`generated` と `approved` だけを読む)には影響しない。更新の形が3段階を `generated: false` に戻すため、design.md と tasks.md が残っていても再生成までは scan の対象にならないことを確かめた。

### 申告

**1. スキルと文書の受入基準に自動テストを作らず、タスク6.1 の手作業の突き合わせと 6.2 の出荷後の確認で代える** — 完了条件1、6.1、6.2

- Issue の記載: なし
- 決めたこと: 自動テストを持つのは close-linked-issues.sh の部分(9.5、9.6)だけにする。`/start`・kiro-spec-init・file-issue・ship・spec の審査・CLAUDE.md・README の受入基準は、6.1 で受入基準ごとに本文の該当箇所を突き合わせ、6.2 でPR本文に出荷後の確認の手順を書く
- 他にありえた選択肢: 機械で確かめられる項目(4つのスキルの冒頭の `disable-model-invocation: true`、CLAUDE.md・README・file-issue に「200行を超える見込み」が残っていないこと、4つの観点の表が3か所で同じこと、参照する見出しの実在)を `.github/scripts/tests/` のシェルテストにして、guardrails の escape-hatch で毎回流す
- 外れていた場合: 出荷の時点では 6.1 で確かめるので差は出ない。出荷後に SKILL.md や CLAUDE.md が直されて3か所がずれたとき、止める仕組みが無い。`/start` の判断の基準がずれても、PR の段階の検査(codex-review・size-check)はそれを見ない

**2. `gh issue create --parent` と、親子を持つIssueの GraphQL の応答の形を、実物を作らずに確かめる** — 1.1、3.1、6.2

- Issue の記載: なし
- 決めたこと: 3.1 は `gh issue create --help` に `--parent` があることだけを確かめる。1.1 は #472(親も子も無い)で `parent` と `subIssuesSummary` を引く。親が付いたときの `parent { number }` の形と、`--parent` で作ったIssueが `subIssuesSummary` に数えられることは、6.2 の出荷後の確認で初めて実物を見る
- 他にありえた選択肢: 使い捨てのサブIssueを1件作って(すぐ閉じる)、両方の形を実測してから偽の gh の応答を決める
- 外れていた場合: 偽の gh の応答の形が実物と違えば、テストは通るのに本番の close-linked-issues.sh が「応答の形が想定と違う」で止まり、親が閉じない。発覚は最初の分割の出荷後で、直すのは `.github/scripts/` なので所有者の承認がもう一度要る

**3. verify の置き換え先を、alpine コンテナでの同梱テストと shellcheck v0.11.0 にする** — 完了条件2

- Issue の記載: なし
- 決めたこと: 同梱テストは `bash jq coreutils grep git` を入れた alpine コンテナで、shellcheck は guardrails と同じ `koalaman/shellcheck:v0.11.0` で流す
- 他にありえた選択肢: guardrails と同じ ubuntu のイメージで流す。手元では流さず、PR の guardrails だけに任せる
- 外れていた場合: alpine(sed は busybox のまま)と ubuntu の差でテストの結果が変わることがありうるが、CI の guardrails が同じテストを流すので、PR の時点で分かる。手戻りは小さい

### 指摘

| ID | レベル | 該当箇所 | 内容 | 直し方の案 |
|---|---|---|---|---|
| T1-1-1 | 低 | 1.3 の知らせの文面、5.3 | 1.3 は「親の問い合わせ、または親を閉じる操作に失敗したら」同じ文面「この Issue から分けた Issue はすべて閉じましたが、この Issue を自動で閉じられませんでした。」を出す。問い合わせに失敗したときは、子がすべて閉じているかをスクリプトは知らない(子の数は親の応答から読む)ので、文面が事実と違うことがある。design の Failure の文面をそのまま写したもので、5.3 の対処が「子がすべて閉じていることを確かめて手で閉じる」なので実害は小さい | 問い合わせの失敗のときだけ「分けた Issue がすべて閉じたかを確かめられず、この Issue を自動で閉じられませんでした」のような文に分けるか、design のとおり1つの文面で通すなら 5.3 の対処に「知らせが出た時点で子が残っていることもある」と添える |
| T1-1-2 | 低 | 5.1 の印の決まり | 「タスクの行では `(P)` の後に `(#N)` を置き」とあるが、`(P)` の位置は、テンプレート(`.kiro/settings/templates/specs/tasks.md` L8)では題名の後ろ、生成の規則(`kiro-spec-tasks/rules/tasks-generation.md` L175-176)と本 tasks.md では番号の直後で、2通りある。番号の直後の `(P)` の後に置くと `- [ ] 2.1 (P) (#N) 題名` になり、design の「タスクの末尾に `(#N)`」と食い違う | 「タスクの行では行末に `(#N)` を置く(`(P)` が行末にあればその後ろ)」のように、`(P)` の位置に依らない書き方にする |
| T1-1-3 | 低 | 1.2、1.3 | test-close-linked-issues.sh の最後の確認(L1116)は、標準出力の行を `result=(untouched\|closed\|close-failed\|refs-only-noticed\|not-an-issue)` に限っている。`parent-closed`・`parent-close-failed` を出すと、この確認と、スクリプト冒頭の「出力:」の一覧(L81-83)を直す必要がある。1.2・1.3 は「判定表」と「知らせの説明」だけを挙げている。テストが赤になるので実装中に気づくが、冒頭の「出力:」の一覧は忘れやすい | 1.2 の detail に「冒頭の『出力:』の一覧と、テストの標準出力の形の確認(最後の節)に2つの result を足す」を1行足す |
| T1-1-4 | 低 | 2.2 | 「引数の1つ目が `#<番号>`、2つ目が既存の feature 名で…feature が無ければ誤りとして伝えて何も書かない」とある。今の kiro-spec-init は Step 0 で `$ARGUMENTS` が Issue 番号を「含む」ときも受け付けるため、`/kiro-spec-init #480 ログインの改善` のように説明を添えた打ち方が、この決まりでは「feature が無い」の誤りになる。design の審査 D1-2-3 が挙げ、tasks で定めるとされていた点である。何も書かずに止まるので手戻りは無いが、所有者が打ち直すことになる | 「2つ目の語が `.kiro/specs/` にある feature 名のときだけ更新の形。それ以外の語は従来どおり説明文として扱う」とするか、`#N` の後ろに説明を付ける打ち方を受け付けないと決めて、誤りの文面にそう書く |

### 前の段階への指摘

なし。タスクに落とす過程で、requirements と design の不足・矛盾は見つからなかった(T1-1-1 の文面は design の Failure に由来するが、5.3 の対処で補えるため、design への差し戻しにはしない)。

- 往復: 1回目 / 高0 中0 低4
- 往復: 1回で収束 / 未解決: 0件

## サイクル2 往復1(2026-10-10)

審査の材料: `tasks.md`(全文。Issue #524 のための更新後。大タスク7と完了条件7が `(#524)` の印付き)、`design.md`(全文。2026-10-10 に所有者が承認)、`requirements.md`(全文。2026-10-10 に所有者が承認)、`research.md`(「過去の着手の判断(#524)」L64〜72 と #524 の Decision)、`spec.json`(issue 472、additional_issues [524]、tasks 生成済み・未承認、approval_history 6件)、Issue #472 本文と Issue #524 本文(`gh issue view 472` / `gh issue view 524`。どちらもコメントは読んでいない)、design の review と response(サイクル1・2の全往復)、`reviews/tasks-style.md`、`.kiro/settings/templates/specs/tasks.md`、`.kiro/settings/rules/spec-writing.md`、steering 3文書、`.claude/skills/start/SKILL.md`(全文。Step 5〜7、観点の表 L136〜141、見直しの時点 L259〜266、冒頭の箇条 L13)、`.claude/skills/file-issue/SKILL.md`(全文。L28、L105〜107、L139〜142)、`.claude/skills/ship/SKILL.md`(全文。手順5 L39〜52)、`.claude/skills/kiro-spec-requirements/SKILL.md`(L4、Step 3 L51〜60)、`.claude/skills/kiro-spec-design/SKILL.md`(L4、Step 4 L106〜114)、`.claude/skills/kiro-spec-tasks/SKILL.md`(L4、Step 2 L42〜68)、`.claude/skills/spec-review/rules/requirements.md`(観点9 L55〜70)、`CLAUDE.md`(L110〜125 の観点の表、L142 の着手の箇条、L174〜185 の「Issueの印」)、`README.md`(L341、L370〜386)。`brief.md` は無い。

この往復は、tasks.md のうち `(#524)` の印の付いたタスク7.1〜7.7 と完了条件7を、Issue #524・requirements の #524 の項目・design の #524 の項目を基準に審査した。大タスク1〜6 は #472 のときに承認・実装済み(`[x]`)であり、サイクル1の結論から変えない。書き方の点検で「## タスクの一覧」の見出しが消え、「完了条件(全タスク共通)」の節がタスクの並びのあとへ移ったが、見出しと目印の一覧(`spec-writing.md`)の `## 完了条件(全タスク共通)` `## 実装のメモ` `_要件:_` `_対象の部品:_` `_依存:_` `(並行可)` は残っており、読み手のスキルに影響しない。

- 要件カバレッジ(#524 の分): Issue #524 で足したか変えた受入基準17件(2.1、2.5、2.6、2.7、3.3、3.4、4.1、4.3、4.4、4.5、4.6、4.7、7.8、10.1、10.8、10.9、10.10)は、すべて 7.1〜7.6 のいずれかの `_要件:_` に現れ、7.7 の `_要件:_` にも揃っている(2.1・2.5〜2.7・4.6 → 7.1、3.3・3.4・4.1・4.3・4.4・7.8 → 7.2、4.3・10.8 → 7.3、4.5・4.7・10.9 → 7.4、4.7 → 7.5、4.7・10.1・10.10 → 7.6)。requirements に無い番号を参照するタスクは無い
- design カバレッジ(#524 の分): design の「ファイルの構成」の #524 の一覧8件(start、file-issue、ship、kiro-spec-requirements と -design、kiro-spec-tasks、`rules/requirements.md`、CLAUDE.md、README)は、7.1・7.2(start)、7.3(file-issue)、7.4(ship)、7.5(生成の3スキルと審査の規則)、7.6(CLAUDE.md、README)で扱われている。start の節の「観点2と観点3の当てはめ方」1〜7、「問いがあるときの報告の書式」、「問いの出し方と答えの書き足し」1〜5、「見直しの時点」、「状態の持ち方」は 7.1・7.2 に、file-issue の節の箇条と2つの例外は 7.3 に、ship の「## AIが決めたこと」の形と「無し」の扱いは 7.4 に、「失敗したときの扱い」の Issue 本文の書き足しの2項目は 7.3 に、「テストの方針」の「スキルと文書の確認(#524 の分)」10項目と「出荷後の確認」の #524 の2項目は 7.7 に入っている。入っていないものを T2-1-1 に挙げる。`(並行可)` のタスクの `_対象の部品:_`(7.3 file-issue の変更、7.4 ship の変更、7.5 spec の生成のスキルの変更・spec の審査の変更、7.6 文書の変更)は design の部品の名前と一致し、design の #524 の一覧の範囲に収まる
- 実ファイルとの照合: 7.1・7.2 が指す start の Step 5・6・7 と「見直しの時点」、7.3 が指す file-issue の「本文に載せるかどうか」の段落(L28)と制約の節(L142)、7.4 が指す ship の手順5と更新した spec のPRの文(L50〜52)、7.5 が指す kiro-spec-requirements の Step 3(L59 に `additional_issues` の2行がある)・kiro-spec-design の Step 4(L114 に merge の記述)・kiro-spec-tasks の Step 2(L68 に merge の記述)・`rules/requirements.md` の観点9の表(L59〜64)、7.6 が指す CLAUDE.md の観点の表(L120〜125)・着手の箇条(L142)・「Issueの印」(L174〜185)、README の2行(L341・L384)と観点の定義を CLAUDE.md に案内する文(L379)は、すべて実在し、タスクの記述どおりである。7.5 の完了の確かめ方が期待する出力の形 `{"hits":[],"total":<数>}` は、gh の `--jq` が gojq でキーを名前順に出すことと、design の対応記録(2026-10-10 に `{"hits":[],"total":258}` を実測)に合う
- スコープ: requirements の「決めないこと」の #524 の2項目(観点の数と観点4の定義、再現テストの決まり)と design の「作らないもの」の #524 の4項目(再現テストの決まり、自動レビューに「AIが決めたこと」を確かめさせること、観点の数と観点4の定義、spec 無しのPRで承認済みの本文を直すこと)にあたる作業は、7.1〜7.7 のどれにも無い。7.1 が差し替える観点の表の観点4の行は、今の start/SKILL.md L141 と同じ文面である。完了条件7の「変えるのは `.claude/`・CLAUDE.md・README だけ」は、design の決まりの節(L86)と一致し、7.1〜7.7 に `.github/` と `doc/` を変える作業は無い
- 完了条件: 4項目(受入基準とテストの対応、verify、見かけの合格の禁止、新しいテストの赤の確認)は残っており、#524 の分の verify の置き換え(変更領域が verify Skill の対象外のため、7.7 の突き合わせと 7.5 のコマンドの実行で代える)は完了条件7に理由付きで書かれている
- 並列と依存: 7.1 と 7.2 は同じ start/SKILL.md を書くので `(並行可)` が無く、番号の順に進む。7.3〜7.6 の `(並行可)` は互いにファイルが重ならない(file-issue / ship / 生成の3スキルと審査の規則 / CLAUDE.md と README)。7.4 と 7.6 の `_依存: 7.1_` は、ship が参照する節の名前と CLAUDE.md の表の文面が 7.1 で決まるためで、成り立つ。7.2 が参照する file-issue の節の名前と、7.3 が参照する start の参照は、design が名前を固定しているので、7.2 と 7.3 の並行に衝突は無く、7.7 が一致を確かめる

### 申告

**1. Issue #524 の受入基準に自動テストを作らず、タスク7.7 の手作業の突き合わせと、タスク7.5 のコマンドの実行で代える** — 完了条件7、7.5、7.7

- Issue の記載: なし
- 決めたこと: #524 で変える場所は `.claude/`・CLAUDE.md・README だけで、自動テストを持たない。観点の表が start と CLAUDE.md で同じ文面であること、`(PR #… で変更済み)` の印が同じ形であること、参照する節の名前が一致することは、7.7 で Claude が手で確かめる。過去の5件の判断への当てはめも手で行う
- 他にありえた選択肢: 観点の表の同一性と印の形の一致を `.github/scripts/tests/` のシェルテストにして、guardrails で毎回流す(サイクル1の申告1と同じ選択肢)。design の「使う既存の仕組み」のとおり `.github/` を変えない方針を採ったため、tasks では採っていない
- 外れていた場合: 出荷の時点では 7.7 で確かめるので差は出ない。出荷後に start か CLAUDE.md のどちらかの表だけが直されてずれたとき、止める仕組みが無い。design の「設計を見直すきっかけ」はこのずれを人が気づく前提に置いている

### 指摘

| ID | レベル | 該当箇所 | 内容 | 直し方の案 |
|---|---|---|---|---|
| T2-1-1 | 中 | 7.5、design の「spec の生成のスキルの変更」の「失敗したとき」(L507)、design の対応記録 D2-1-7 | design は、kiro-spec-requirements と kiro-spec-design に足す1行について、「`gh pr list` が失敗したら、Claude は生成を止めず、検索できなかったことを生成の報告に書く」と決めている。design の審査 D2-1-7(低)への対応記録は「tasks の段階で、検索できなかったことを所有者に見える場所に残す形を扱う」としている。7.5 は、探すコマンドの形と、`total` が1000のときの報告と、印の形だけを書いており、`gh pr list` が失敗したときの扱いを書いていない。7.7 の確かめる項目にも、design の「スキルと文書の確認(#524 の分)」にも、この扱いは無い。このため、SKILL.md に写した1行に失敗の扱いが入らなくても、どの工程でも気づかれない。次に spec を更新するときに `gh pr list` が失敗すると、Claude が生成を止めるか、何も書かずに進むかが決まらない | 7.5 の箇条に「Claude は、`gh pr list` が失敗したときは生成を止めず、検索できなかったことを生成の報告に書く、と1行に含める」を足す。D2-1-7 の対応記録のとおり所有者に見える場所に残すなら、残す先(例: requirements.md の「追加の要望」の節の直下、または design.md の「既存の構成」の節)をこの箇条で1つに決める。7.7 の確かめる項目に、2つの SKILL.md の1行に失敗のときの扱いがあることを足す |
| T2-1-2 | 低 | 7.7 の「過去の判断への当てはめ」 | 「食い違ったら、Claude は、食い違った件と理由を示して7.1 に戻る」とあるが、7.1 が書く観点の表は design の表と同じ文面(`diff` で確かめる)、当てはめ方も design の1〜7を写すものなので、SKILL.md が design と一致しているのに結果が食い違ったときは、7.1 で直せるものが無い。そのまま戻ると、当てはめ方の文面を design から離して結果を合わせることになる。CLAUDE.md の「同一の失敗が3回続いたら停止」で止まるので、手戻りは小さい | 「SKILL.md の文面が design と同じなのに食い違うときは、7.1 に戻らず、食い違った件と理由を所有者に示して止まる(design か requirements の判断が要る)」の1文を添える |
| T2-1-3 | 低 | 7.2 の4つ目の箇条(「状態の持ち方」に…書く) | 「状態の持ち方」は design の start の節の欄の名前で、start/SKILL.md にこの名前の節は無い。SKILL.md で同じ内容を書いているのは、冒頭の箇条(L13「AIは状態を自分で覚えておかない。進み具合は、GitHub のIssue(親子と開閉)と spec.json から毎回読み直す」)である。実装者が置き場所を探すだけで済む | 「SKILL.md の冒頭の箇条(進み具合を毎回読み直す、の行)に」のように、書き足す先を SKILL.md の実際の箇所で指す |
| T2-1-4 | 低 | 7.7 の確かめる項目(`(PR #… で変更済み)` の印が…4か所で同じ形)、design の「テストの方針」(L644) | design の「spec の生成のスキルの変更」の1行(L500)は、kiro-spec-requirements と kiro-spec-design にも「直した項目の末尾に `(PR #<そのPRの番号> で変更済み)` を付ける」と印の形を含めている。印の形が現れる場所は、CLAUDE.md・`rules/requirements.md`・ship・kiro-spec-tasks の4か所に、この2つを加えた6か所である。7.7 の確かめる項目は design の4か所をそのまま写しており、2つの生成のスキルの1行の印の形がずれても確かめられない。印の形がずれると、審査役が `rules/requirements.md` の表で見分けられない | 7.7 の確かめる項目を「CLAUDE.md、`rules/requirements.md`、ship、kiro-spec-tasks、kiro-spec-requirements、kiro-spec-design の6か所」にする |

### 前の段階への指摘

| ID | 対象 | 該当箇所 | 内容 |
|---|---|---|---|
| T2-1-5 | requirements | 要件2の受入基準7(3つの材料の2つ目) | requirements 2.7 は、2つ目の材料を「Issueの本文の「どうなれば解決か」に書かれた目的」とする。design(L311)と、それを写す 7.1 の3つ目の箇条は、「やりたいこと」も目的の出どころに含める。7.7 は「requirements の要件2の受入基準7より広いが、design の審査の記録 D2-3-1 のとおり design に合わせ、食い違いとして扱わない」と明記しており、tasks の時点で、実装が requirements 2.7 の文より広くなることが確定した。起票の決まり(file-issue L62)は「どうなれば解決か」の無いIssueを許すので、広げること自体は筋が通る。ただし requirements 2.7 の文は実装と合わないまま承認済みで残る。戻る先は requirements(2.7 に「やりたいこと」を加えるか、「どうなれば解決か」の節が無いときの扱いを1文足す)。実装に影響しないため、所有者が requirements を直すかどうかを決める |

- 往復: 1回目 / 高0 中1 低3

## サイクル2 往復2(2026-10-10)

審査の材料: `tasks.md`(全文。往復1への対応後)、`reviews/tasks-response.md`(サイクル2 往復1への対応と、T2-1-5 への所有者の判断)、`reviews/tasks-review.md`(サイクル2 往復1)、`reviews/tasks-style.md`(2回目の点検。7.1 と 7.2 に `_対象の部品: start_` を足し、文を3つ直した記録)、`design.md`(全文。「spec の生成のスキルの変更」の節 L493〜507、「テストの方針」L635〜656、「要件との対応」L673〜710)、`requirements.md`(全文)、`spec.json`、Issue #472 本文と Issue #524 本文(`gh issue view 472` / `gh issue view 524`。どちらもコメントは読んでいない)、design の response(サイクル2 全往復)、`.claude/skills/kiro-spec-requirements/SKILL.md`(Step 3 L51〜60)、`.claude/skills/kiro-spec-design/SKILL.md`(Step 4 L106〜117)、`.kiro/settings/rules/spec-writing.md`(「文書の組み立て」L75〜、「見出しと目印の一覧」L252〜)、`.claude/hooks/spec-review-scan.sh`(requirements.md / design.md の本文を読む箇所の grep。無し)、steering 3文書。`brief.md` は無い。

この往復は、往復1の指摘への対応が本文に入っているか、対応が新しい食い違いを生んでいないかを見た。往復1で確かめた要件カバレッジ・design カバレッジ・スコープ・並列と依存の結論は、対応で変わる箇所(7.5 の箇条、7.7 の確かめる項目、7.1 と 7.2 の `_対象の部品:_`)を見直したうえで、変えない。

- T2-1-1(中)の対応: 7.5 の3つ目の箇条に、`gh pr list` が失敗したときは生成を止めず、検索できなかったことを生成の報告に書き、生成する文書の末尾に「spec 無しのPRの検索に失敗したため、食い違いを拾えていない」の1行を残すこと、その理由(所有者が承認のときに拾い漏れがありうることを知るため)、出どころ(D2-1-7)が書かれている。7.7 の確かめる項目に「kiro-spec-requirements と kiro-spec-design の1行に、`gh pr list` が失敗したときの扱いがあること」が足されている。design の「失敗したとき」(L507。生成を止めず、生成の報告に書く)と矛盾せず、所有者に見える場所に残す形は D2-1-7 の対応記録の申し送りどおり tasks で決まった。直っている
- T2-1-2〜T2-1-4(低)は記録のみで、本文は変わっていない。往復1の判断のとおり実装に影響しない
- T2-1-5(前の段階への指摘)は、所有者が「要件は直さずに進める」と判断し、response に記録されている。この往復では出さない
- 書き方の点検で足された 7.1 と 7.2 の `_対象の部品: start_` は、design の部品の表の名前(start)と、design の「ファイルの構成」の #524 の一覧(`.claude/skills/start/SKILL.md`)に一致する。7.1〜7.7 の `_対象の部品:_` は、7.7(突き合わせだけで、ファイルを変えない)を除いてすべて揃った
- 7.5 の完了の確かめ方「4つのファイルに上の行があり」の4つは、箇条の冒頭の文(kiro-spec-requirements、kiro-spec-design、kiro-spec-tasks、spec-review の `rules/requirements.md`)から読め、design の「ファイルの構成」の #524 の一覧と一致する

### 申告

なし。この往復の対応で、往復1の申告1に新しく足す決定は無い。

### 指摘

| ID | レベル | 該当箇所 | 内容 | 直し方の案 |
|---|---|---|---|---|
| T2-2-1 | 低 | 7.5 の3つ目の箇条(「生成する文書の末尾に…の1行を残す」) | 残す先を「文書の末尾」と決めたが、requirements.md の末尾は `### 要件10` の番号付きの箇条の直後、design.md の末尾は `## 要件との対応` の表の直後である。design.md では、表のあとに空行を置かずに1行を書くと、Markdown はその行を表の続き(壊れた行)として表示する。requirements.md では、要件10の箇条の直後に置くと、審査役と所有者がそれを要件10の一部として読むおそれがある。どちらも、SKILL.md に写すときに「空行を1つ置いて書く」と添えれば済み、kiro-spec-requirements / kiro-spec-design を次に更新の形で動かすまで表に出ないため、実装に影響しない | 7.5 の箇条の「末尾に…の1行を残す」に「空行を1つ置いてから」を添える。または、残す先を見出しの下(requirements.md は `## 範囲` の「この spec が前提にしていること」の直下、design.md は `## 既存の構成` の直下)にして、要件の箇条と表から離す |

### 前の段階への指摘

なし。T2-1-5 は所有者が判断済み(要件は直さずに進める)で、繰り返さない。

- 往復: 2回目 / 高0 中0 低1
- 往復: 2回で収束 / 未解決: 0件
