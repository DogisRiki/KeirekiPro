# design 対応記録: spec-need-triage

## サイクル1 往復1 への対応(2026-10-02)

| ID | 処置 | 内容 |
|---|---|---|
| D1-1-1 | 修正 | `start` 手順2の表から `ready_for_implementation` を外し、`approvals.tasks.approved` と tasks.md の `- [ ]` / `- [x]` で判定する3行(tasks 未承認、tasks 承認済みで未完了あり、すべて完了)に分けた |
| D1-1-2 | 修正 | kiro-spec-requirements に、`additional_issues` があるときは既存の要件と受入基準を番号ごと残し、新しい要件を末尾の番号で足し、CLAUDE.md の印の決まりに従う、という2行を足すことを Modified Files に書いた。Out of Boundary の生成手順の項に、この2行と冒頭の1行を例外として明記した。「Issueの印」に、既存の番号を変えず新しい要件は最後の番号の次から足す決まりを加えた。Traceability の 5.8 に kiro-spec-requirements を加えた |
| D1-1-3 | 記録のみ | ゲート設定の項は、変更が要ることを理由とともに書いており、未チェックはその表示である |
| D1-1-4 | 記録のみ | 実測の日時は research.md の調査日(2026-10-02)で、tasks の検証で `gh issue create --parent` を改めて確かめる |
| D1-1-5 | 記録のみ | 200行の検査で止まったときにPRを閉じて部分ごとに新しいブランチを作る扱いと、実装の途中で分けるときの扱いの違いは、tasks で SKILL.md の文面を書くときに揃える |
| D1-1-6 | 記録のみ | タスクの行での `(#N)` と `(P)` の並びと、`_Requirements:_` の行に付けないことは、CLAUDE.md の印の決まりを書くタスクで定める |
| D1-1-7 | 記録のみ | PRのマージ以外で閉じたサブIssueは、所有者もAIもIssueを手で閉じない決まりのため起きない想定とし、Out of Boundary のとおり扱わない |
| D1-1-8 | 記録のみ | `spec-review/SKILL.md` Step 6 の「後続の段階を作り直し」を、所有者にコマンドを依頼する文面に直すことは、Step 6 に `approval_history` の手順を足すタスクで合わせて行う |

## サイクル1 往復2 への対応(2026-10-02)

| ID | 処置 | 内容 |
|---|---|---|
| D1-2-1 | 修正 | 直し方の案(a)を採った。kiro-spec-init の更新の形の手順3から `ready_for_implementation` を false に戻す記述を外し、このキーに触れないこととその理由(true に戻す手順が無く、false だと再承認の後も check-spec-backing.sh で止まる。実装の可否は3段階の承認で判定される)を書いた |
| D1-2-2 | 記録のみ | 「承認済みで次の段階が未生成」の行は、tasks で `start` の SKILL.md の表を書くときに足す |
| D1-2-3 | 記録のみ | kiro-spec-init の引数の読み分け(1つ目が `#N`、2つ目が既存の feature 名)と、Directory Conflict の扱いを更新の形では使わないことは、tasks で kiro-spec-init の文面を書くときに定める |
| D1-2-4 | 記録のみ | kiro-spec-requirements の2行と `start` 手順2の表の確認は、tasks の確認の項目に入れる |
| D1-2-5 | 記録のみ | 手順2の最後の行(すべて完了)だけは終えずに出荷の状況を確かめる、という書き分けは、tasks で SKILL.md の文面を書くときに揃える |

## サイクル1 往復3 への対応(2026-10-02)

新しい指摘なし。収束(高0 中0)。未解決: 0件
