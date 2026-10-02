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
