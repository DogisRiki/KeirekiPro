# 調べたことと設計の判断

## まとめ

- 機能: `spec-writing-leftovers`
- 調べた範囲: 既存の仕組みの手直し(spec のスキル、点検役、判定のスクリプト、PRの検査、雛形、既存の spec)
- 分かったこと:
  - 古い書き方の spec は9件あり、9件とも3段階が所有者の承認済みで、tasks.md に未完了のタスクは無い(`grep '^- \[ \]' .kiro/specs/*/tasks.md` が0件)
  - 書き方の印 `spec_format` を読むファイルは、スキルと点検役と判定のスクリプトとその試験を合わせて27ある。古い名前(`_Boundary:_` など)を本文に持つファイルも、ほぼ同じ顔ぶれである
  - 200行の検査で数えられるのは、この変更ではシェルスクリプト(`spec-review-scan.sh`、その試験、`check-spec-backing.sh`)だけで、200行に届かない

## 調べたこと

### 古い書き方の spec の数と状態

- きっかけ: 要件1は、古い書き方の spec をすべて書き換える
- 調べたもの: `.kiro/specs/*/spec.json`、各 spec の tasks.md、`wc -l`
- 分かったこと:
  - 印を持つ spec は spec-readable-writing とこの spec の2件だけで、ほかの9件(audit-automation、audit-inventory-metrics、audit-notification、container-image-vulnerability-scanning、issue-close-and-auto-merge-guarantee、machine-gated-dependency-updates、merge-queue-migration、spec-need-triage、spec-review)が古い書き方である
  - 9件の requirements.md・design.md・tasks.md は、合わせて約7,400行ある。最も大きいのは container-image-vulnerability-scanning(design.md 826行、tasks.md 385行)である
  - 9件とも `ready_for_implementation` は true で、`approval_history` を持たない。container-image-vulnerability-scanning は、design の追加の承認を `amendments` に3件持つ
  - 古い design.md のうち7件が `### Existing Architecture Analysis`、4件が `## Supporting References` を持つ(requirements の審査 R1-1-1 で確かめた)
- 設計への影響: 書き換えは spec ごとに1つのタスクにし、確かめ役の比べる単位も spec ごとにする

### `spec_format` と古い名前を読むファイル

- きっかけ: 要件4は、どの道具も書き方を見分けないようにする
- 調べたもの: `grep -rc spec_format`、古い見出しと目印の名前の `grep -rcE`
- 分かったこと:
  - `spec_format` を読むのは、`.claude/skills/` の kiro-spec-init・kiro-spec-requirements(決まり1つを含む)・kiro-spec-design(決まり2つを含む)・kiro-spec-tasks(決まり2つを含む)・kiro-impl(雛形2つを含む)・kiro-validate-impl・kiro-review・kiro-debug・kiro-spec-status・spec-review(決まり3つを含む)・start、`.claude/agents/spec-style-checker.md`、`.claude/hooks/spec-review-scan.sh` とその試験、`.kiro/settings/rules/spec-writing.md`、`.kiro/settings/templates/specs/init.json`、`CLAUDE.md` である
  - 古い名前だけを持ち `spec_format` を読まないのは、kiro-spec-batch(3か所)、kiro-spec-quick(1か所)、kiro-discovery(1か所)、kiro-steering-custom(1か所)である。kiro-steering-custom の `Testing Strategy` は steering の文書の見出しで、spec の名前ではない
  - EARS を名指すのは、ears-format.md のほかに、kiro-spec-design の `design-discovery-full.md` L10 と kiro-validate-gap の `gap-analysis.md` L25 である
  - `.github/` の中で古い名前を使うファイルは無い
- 設計への影響: kiro-discovery は CLAUDE.md が使わないと決めているので、手を入れない。kiro-steering-custom は spec を扱わないので、手を入れない

### `ready_for_implementation`

- 調べたもの: `grep -rn ready_for_implementation`
- 分かったこと: 値を読むのは `check-spec-backing.sh` L77 だけである。値を書くのは雛形 `init.json` の false だけで、true にする道具は無い。`kiro-spec-init` L69 は、この値に触れないよう指示している
- 設計への影響: 検査が値を読まないようにすれば、承認の3つの段階だけで判定がそろう。値を読む道具が無くなるので、雛形と既存の spec.json から欄を消す

### 承認の判定と特例の承認の記録

- 調べたもの: `spec-review-scan.sh` L12〜16・L74、`check-spec-backing.sh` L74〜79
- 分かったこと: 判定のスクリプトは、`approved` が true で `approved_by` が空でなく ':' を含まない段階を、人の承認として判定の対象から外す。PRの検査は `approved` だけを見る
- 設計への影響: 特例の承認は `approved_by` を `DogisRiki` にし、特例であることは `approval_history` の要素の `revoked_for` に書く。新しい欄は足さない(所有者の指示。欄を足すと、承認を写す道具にも手当てが要り、今回だけの特例のための仕組みが残る)。`approved_by` に ':' を含む値を使うと、判定のスクリプトが書き換えた spec の段階を審査の対象にしてしまう

### 200行の検査で数える行

- 調べたもの: `.github/workflows/guardrails.yaml` L139〜166
- 分かったこと: `*.md` と `.kiro/**` は数えない。試験として数えないのは `.github/scripts/tests/**` などで、`.claude/hooks/tests/**` は数える
- 設計への影響: この変更で数えられるのは `spec-review-scan.sh`、`test-spec-review-scan.sh`、`check-spec-backing.sh` の差分だけで、合わせて100行に届かない見込みである。そのため、この spec の requirements.md の Issue の引用に残る `{{NUMBER}}` `{{TITLE}}` は、この変更のPRで検査に掛からない

## 比べた案

| 案 | 中身 | 良い点 | 弱い点 |
|---|---|---|---|
| A. 確かめ役の定義ファイルを `.claude/agents/` に足す | 書き換えの確かめ役を、モデルを固定した定義で作る | モデルの指定が定義に残る | 今回だけの特例のための定義が、使われないまま残る |
| B. Agent ツールの `model: "fable"` で汎用のサブエージェントを起動する(採る) | 確かめの指示を design.md に置き、起動のたびに渡す | 定義が後に残らない | 指示を毎回渡す必要がある |

| 案 | 中身 | 良い点 | 弱い点 |
|---|---|---|---|
| A. `/kiro-spec-tasks` の承認で `ready_for_implementation` を true にする | 欄を残し、承認と取り消しのたびに値を書く | PRの検査を変えない | 承認の3つの段階と同じことを2か所に持ち、取り消しのたびに値をそろえる手間が残る |
| B. PRの検査が欄を読まない(採る) | 検査は3つの段階の承認だけを見る | 値をそろえる手間が無くなり、書き換えた spec も特例の承認だけで検査を通る | `.github/` の変更になり、所有者の承認が要る |

## 設計の判断

### 書き換え前の本文の取り出し方

- 背景: 確かめ役は、書き換え前と書き換え後を比べる
- 選んだ方法: 書き換えはタスクのコミットの前に行うので、書き換え前の本文は `git show HEAD:<パス>` で取り出せる。確かめ役は、これと作業場所のファイルを比べる
- 理由: 書き換え前の本文の写しを別に作らずに済み、写し間違いが起きない

### 書き換えをやめたときの戻し方

- 選んだ方法: その spec の3つのファイルだけを `git restore --source=HEAD -- <3つのファイル>` で戻す
- 理由: ほかの spec の書き換えとほかのタスクの変更に触れずに戻せる

## 危ないことと対策

- 書き換えで中身が落ちる: 確かめ役が書き換え前を正として比べ、spec ごとに記録を残す。比べる中身は requirements.md の要件2で決めたとおりにし、書き方の違いでは止まらないようにする
- `.claude/hooks/` と `.github/` は Claude が書き込めない: Claude が scratchpad に用意し、所有者が作業場所に写す。写したあと、Claude が写した版と用意した版が同じことと、試験が通ることを確かめる
- 実装中に、実装を進めるスキル自身(kiro-impl など)を書き換える: 道具を直すタスクを spec の書き換えのあとに置き、spec.json から印を消すタスクを最後にする。spec の書き換えのあいだは、新旧の対応表と今の道具がそのまま使える
