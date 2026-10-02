# 調査と設計判断の記録

## 概要

- 対象: spec-readable-writing(Issue #474)
- 調査の範囲: 既存の仕組みの拡張。spec を書くスキルと雛形、spec を読むスキル、審査のフックを調べた
- 調べた版: origin/main の fd8d0eb(#475 のマージ後)。作業ツリーは別の会話が別のブランチで使っていたため、`git show origin/main:` と `git archive` で読んだ

## 調べたこと

### spec の見出しを機械で読み取っている箇所

- スクリプトが spec を読むときに見ているのは、ファイル名、spec.json のキー、`{{...}}` のプレースホルダの3つだけである。見出しや欄を解析しているスクリプトは無い
  - `.github/scripts/check-spec-backing.sh` 66行目は、4つのファイルに `\{\{[A-Z0-9_]+\}\}` が残っていないかを調べる。プレースホルダの名前を英大文字のまま残せば、この検査は今までどおり働く
  - `.github/workflows/codex-review.yml` 162行目は、spec のディレクトリの直下の .md をすべて連結して読む。見出しは解析しない
  - `.claude/hooks/spec-review-scan.sh` は、本文のファイル名と変更日時、reviews/ の記録の書式だけを見る
- 見出しや欄の名前は、AI への指示の中で名前を挙げて参照されている。名前を変えると、指示と spec の中身が合わなくなる
  - `/kiro-impl`(SKILL.md 62〜176行目、templates/ の3つ)は、タスク番号、`_Depends:_` `_Boundary:_` `_Blocked:_`、`(P)`、`## Implementation Notes` を読む
  - `/kiro-validate-impl` `/kiro-review` `/kiro-spec-status` `/kiro-debug` `/start`(92行目の「This Spec Owns」)と、`/spec-review` の rules/design.md・rules/tasks.md も名前で参照する
  - `/kiro-spec-init` の43行目と68行目は、`## Project Description (Input)` と完全に一致する行を目印にして、既存の spec に追加の要望を足す

### spec を書く側の指示

- `.claude/skills/kiro-spec-requirements/rules/ears-format.md` 8行目は、英語の定型句を残して可変部分だけを日本語にするよう指示している。新しい書き方と真っ向から食い違う
- 雛形 `.kiro/settings/templates/specs/` の requirements.md・design.md・tasks.md は、見出しと欄の大半が英語である。design.md の雛形は、Goals と This Spec Owns、Non-Goals と Out of Boundary、要件の対応の表と部品の Requirements 行のように、同じことを書く節が重なっている
- `/kiro-spec-tasks` の SKILL.md 129〜138行目は、生成の直後に承認を尋ねる。CLAUDE.md は、審査が終わってから承認を求めると定めている
- spec を書くスキルのどれも、生成の後に `/spec-review` を呼ぶ指示を持たない。指示は CLAUDE.md にだけある

### 審査のフック

- `spec-review-scan.sh` は、spec.json の `phase` が `initialized` の spec と、人が承認した段階を対象から外す。段階ごとに、記録の有無、未処置の指摘、証跡、本文と記録の変更日時を比べて理由を出す
- `check-spec-review-before-stop.sh`(Stop)と `notify-spec-review.sh`(UserPromptSubmit など)は、どちらも scan の出力を使う。scan に判定を足せば、止める側と知らせる側の両方に効く
- `.claude/hooks/**` と `.claude/settings.json` は、`settings.json` の permissions.deny で Claude が書き込めない。`.claude/skills/**` と `.claude/agents/**` は書き込めるが、CODEOWNERS と escape-hatch により所有者の承認が要る
- spec-review のフックにはテストが無い。`.claude/hooks/tests/` には test-protect-main.sh だけがある

## 判断

### 新旧の spec の見分け方

- 背景: 要件1は、変更が main に入る前に作られた spec を今の書き方のまま進めると決めた。スキルとフックは、spec ごとにどちらの書き方かを知る必要がある
- 考えた案:
  1. spec.json に書き方の版を表す欄を足す
  2. spec.json の `created_at` と、変更が main に入った日時を比べる
  3. requirements.md の見出し(`# 要件` か `# Requirements Document` か)で見分ける
- 選んだ案: 1。雛形の init.json に `"spec_format": 2` を足し、欄が無い spec を今の書き方として扱う
- 理由: 2は、main に入った日時をどこかに持たせる必要がある。3は、見出しを読むと要件1の境目(作られた時点)と食い違う場合がある。1は、作られた時点で決まり、あとから変わらない

### 古い雛形の扱い

- 背景: 途中の spec は、このあと書く design と tasks も今の書き方で書く。古い雛形と古いルールが要る
- 選んだ案: 今の雛形を `.kiro/settings/templates/specs-v1/` に移し、`.kiro/settings/templates/specs/` を新しい雛形に置き換える。古い書き方の spec が無くなったら、`specs-v1/` と `ears-format.md` を消す(この spec の範囲外)
- 理由: 新しい spec が正しい場所を使う形にしておくと、古い方を消すときに参照を直す箇所が少ない

### 書き方の決まりの置き場所

- 選んだ案: `.kiro/settings/rules/spec-writing.md` を新しく作り、書き方の決まり、見本、新旧の目印の対応表をまとめる。書くスキル、点検役、読むスキルは、このファイルを参照する
- 理由: 決まりを各スキルに書き写すと、同じ決まりが何か所にも書かれ、直すときに食い違う

### 点検を置く場所

- 考えた案:
  1. 各生成スキルの「書く前の自己点検」に足す
  2. `/spec-review` の中で、審査役を起動する前に毎回点検する
  3. `/spec-review` が収束した後、承認を求める前に点検する
- 選んだ案: 2
- 理由: 1は、審査の指摘で直した後の本文を見ない(要件6の2を満たさない)。3は、点検で本文を直すと、既存のフックが「本文がレビューより新しい」と判定し、審査をもう1サイクル回すことになる。2なら、本文、点検の記録、審査の記録の順に新しくなり、既存の判定とも新しい判定とも両立する

### 点検をする役

- 選んだ案: 点検は新しいサブエージェント(spec-style-checker)が行い、外れた文と書き直しの案を返す。本文を直すのは、今までどおり `/spec-review` のメインセッションだけにする
- 理由: 書いた本人のセッションは、自分の文の抜けに気づきにくい。この spec の requirements でも、決まりを書いた本人の文に主語の抜けがあり、審査で見つかった(R1-2-4)

### 読む側の目印

- 考えた案:
  1. tasks.md の目印(`_Depends:_` など)を英語のまま残し、読む側を変えない
  2. 目印も日本語にし、読む側のスキルに新旧の対応表を読ませる
- 選んだ案: 2
- 理由: 要件2の5は欄の名前を日本語で書くと決めている。読む側は AI への指示であり、対応表を1か所に置けば、指示の変更は「spec_format が 2 なら対応表の名前で読む」という1文で済む
