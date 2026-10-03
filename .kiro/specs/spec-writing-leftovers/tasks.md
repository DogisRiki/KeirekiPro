# タスク

- [ ] 1. 古い書き方の spec を新しい書き方に書き換える

  Claude は、spec ごとに1つのタスクで、design.md の「書き換えの実装役」「書き換えの確かめ役」「書き換えの進め役」の節のとおりに書き換えと確かめと特例の承認の記録を進める。Claude は、タスクを1つずつ進め、spec ごとにコミットする。どのタスクでも、Claude は次の5つを守る。
  - 確かめ役への指示: Claude は、design.md の指示文に、記録 `rewrite-check.md` の書式(design.md の「状態の持ち方」の欄)と、食い違いが無いときは表を書かないことを足し、ファイルを作業場所の絶対パスで渡す
  - 確かめの回数: Claude は、1つの spec で確かめ役を起動した回数を数え、審査役の差し戻しのあとの確かめも数に入れる
  - モデルの確かめ: 確かめ役の応答の `MODEL:` が Fable 5.1(`claude-fable-5-1`)でなければ、Claude は結果を使わずに止める
  - 承認の記録: 審査役が承認し、最後の確かめが今の本文について `same` のときだけ、Claude はコミットの前に spec.json の承認を design.md の進め役の節のとおりに書き換える
  - 元の要望の節: requirements.md に `## Project Description (Input)` の節が無い spec(container-image-vulnerability-scanning、machine-gated-dependency-updates、merge-queue-migration、spec-review)では、実装役は `## 元の要望` の節を作らない

  書き換えのタスクの完了の確かめ方で使う「古い見出しと目印の点検」は、次の箇条書きのすべての grep の出力が、`## 元の要望` の節の中の行、既存の文書から引用した行、コードブロックの中の行だけであることを指す。
  - 古い名前の見出し: `grep -nE '^#{1,4} .*(Requirements Document|Requirement [0-9N]|Acceptance Criteria|Introduction|Project Description|Boundary Context|Design Document|Overview|Goals|This Spec Owns|Out of Boundary|Allowed Dependencies|Revalidation Triggers|Boundary Commitments|KeirekiPro|Architecture|Technology Stack|File Structure Plan|System Flows|Traceability|Components and Interfaces|Data Models|Error Handling|Testing Strategy|Unit Tests|Integration|Workflow|Config|Liveness|Supporting References|Implementation Plan|Implementation Notes)' <3つのファイル>` と、`grep -nE '^#{1,4} (Requirements|Tasks|Security Considerations|Performance & Scalability|Migration Strategy)$' <3つのファイル>`
  - 日本語の無い見出し: `LC_ALL=C.UTF-8 grep -nE '^#{1,4} ' <3つのファイル> | LC_ALL=C.UTF-8 grep -vP '[\p{Han}\p{Hiragana}\p{Katakana}]'`(上の一覧に無い英語の見出しも、ここに出る)
  - 利用者の立場を名乗る行: `grep -n '\*\*Objective:\*\*' <requirements.md>`
  - 英語の語を含む見出しの読み合わせ: Claude は、`grep -nE '^#{1,4} .*[A-Za-z]{3,}' <3つのファイル>` の出力を読み、ファイル名・コマンド・設定やイベントの名前・部品の名前でない英語の語が見出しに残っていないことを確かめる。この点検は、上の一覧に無い古い見出しの語を拾うためのものである。そのような英語の語が見出しに残っていたら、Claude は実装役にその見出しを直させる
  - 目印の行: `grep -nE '^\s*- _(Requirements|Boundary|Depends|Blocked):' <tasks.md>`
  - 並行の印: `grep -nE '^- \[.\] [0-9.]+ .*\(P\)' <tasks.md>`

- [x] 1.1 audit-automation を書き換える

  書き換えの実装役は、`.kiro/specs/audit-automation/` の requirements.md・design.md・tasks.md を新しい書き方に書き換える。
  - 完了の確かめ方: `reviews/rewrite-check.md` の最後の節の結果が「同じ」で、spec.json の `approval_history` に3つの段階の要素が1つずつある。古い見出しと目印の点検に、引用でない行が出ない
  - 受入基準とテストの対応: 要件1の受入基準1・3・6(新しい書き方への書き換え、番号と印、「なし」の節の中身)は、古い見出しと目印の点検で確かめる。要件1の受入基準2・4(中身と引用を変えない)と要件2の受入基準1〜4(中身が同じかを確かめ役が確かめる)は、記録 `rewrite-check.md` の最後の節で確かめる。要件2の受入基準5(3回で止めて戻す)は、止めたときに本文が `git diff` で変わっていないことで確かめる。要件2の受入基準6(結果を記録に残す)は、`rewrite-check.md` があることで確かめる。要件3の受入基準1・2・4(承認を取り消さず、確かめたあとに履歴と承認を記録し、特例と分かるようにする)は、spec.json の `approval_history` の要素の `revoked_for` と、承認の欄の `approved_at` がその要素の `revoked_at` と同じであることで確かめる
  - _要件: 1.1, 1.2, 1.3, 1.4, 1.6, 2.1, 2.2, 2.3, 2.4, 2.5, 2.6, 3.1, 3.2, 3.4_

- [x] 1.2 audit-inventory-metrics を書き換える

  書き換えの実装役は、`.kiro/specs/audit-inventory-metrics/` の requirements.md・design.md・tasks.md を新しい書き方に書き換える。
  - 完了の確かめ方: タスク1.1と同じ
  - 受入基準とテストの対応: タスク1.1と同じ
  - _要件: 1.1, 1.2, 1.3, 1.4, 1.6, 2.1, 2.2, 2.3, 2.4, 2.5, 2.6, 3.1, 3.2, 3.4_

- [x] 1.3 audit-notification を書き換える

  書き換えの実装役は、`.kiro/specs/audit-notification/` の requirements.md・design.md・tasks.md を新しい書き方に書き換える。
  - 完了の確かめ方: タスク1.1と同じ
  - 受入基準とテストの対応: タスク1.1と同じ
  - _要件: 1.1, 1.2, 1.3, 1.4, 1.6, 2.1, 2.2, 2.3, 2.4, 2.5, 2.6, 3.1, 3.2, 3.4_

- [x] 1.4 container-image-vulnerability-scanning を書き換える

  書き換えの実装役は、`.kiro/specs/container-image-vulnerability-scanning/` の requirements.md・design.md・tasks.md を新しい書き方に書き換える。この spec は最も大きく(design.md 826行、tasks.md 385行)、spec.json に `amendments` を持つ。Claude は `amendments` の欄を書き換えない。
  - 完了の確かめ方: タスク1.1と同じ。加えて、spec.json の `amendments` が書き換えの前と同じである
  - 受入基準とテストの対応: タスク1.1と同じ
  - _要件: 1.1, 1.2, 1.3, 1.4, 1.6, 2.1, 2.2, 2.3, 2.4, 2.5, 2.6, 3.1, 3.2, 3.4_

- [x] 1.5 issue-close-and-auto-merge-guarantee を書き換える

  書き換えの実装役は、`.kiro/specs/issue-close-and-auto-merge-guarantee/` の requirements.md・design.md・tasks.md を新しい書き方に書き換える。実装役は、同じディレクトリの `pr-body.md` を書き換えない。
  - 完了の確かめ方: タスク1.1と同じ
  - 受入基準とテストの対応: タスク1.1と同じ
  - _要件: 1.1, 1.2, 1.3, 1.4, 1.6, 2.1, 2.2, 2.3, 2.4, 2.5, 2.6, 3.1, 3.2, 3.4_

- [x] 1.6 machine-gated-dependency-updates を書き換える

  書き換えの実装役は、`.kiro/specs/machine-gated-dependency-updates/` の requirements.md・design.md・tasks.md を新しい書き方に書き換える。
  - 完了の確かめ方: タスク1.1と同じ
  - 受入基準とテストの対応: タスク1.1と同じ
  - _要件: 1.1, 1.2, 1.3, 1.4, 1.6, 2.1, 2.2, 2.3, 2.4, 2.5, 2.6, 3.1, 3.2, 3.4_

- [ ] 1.7 merge-queue-migration を書き換える

  書き換えの実装役は、`.kiro/specs/merge-queue-migration/` の requirements.md・design.md・tasks.md を新しい書き方に書き換える。
  - 完了の確かめ方: タスク1.1と同じ
  - 受入基準とテストの対応: タスク1.1と同じ
  - _要件: 1.1, 1.2, 1.3, 1.4, 1.6, 2.1, 2.2, 2.3, 2.4, 2.5, 2.6, 3.1, 3.2, 3.4_

- [ ] 1.8 spec-need-triage を書き換える

  書き換えの実装役は、`.kiro/specs/spec-need-triage/` の requirements.md・design.md・tasks.md を新しい書き方に書き換える。
  - 完了の確かめ方: タスク1.1と同じ
  - 受入基準とテストの対応: タスク1.1と同じ
  - _要件: 1.1, 1.2, 1.3, 1.4, 1.6, 2.1, 2.2, 2.3, 2.4, 2.5, 2.6, 3.1, 3.2, 3.4_

- [ ] 1.9 spec-review を書き換える

  書き換えの実装役は、`.kiro/specs/spec-review/` の requirements.md・design.md・tasks.md を新しい書き方に書き換える。
  - 完了の確かめ方: タスク1.1と同じ
  - 受入基準とテストの対応: タスク1.1と同じ
  - _要件: 1.1, 1.2, 1.3, 1.4, 1.6, 2.1, 2.2, 2.3, 2.4, 2.5, 2.6, 3.1, 3.2, 3.4_

- [ ] 1.10 spec-readable-writing の design.md の空欄の目印を書き換える

  書き換えの実装役は、`.kiro/specs/spec-readable-writing/design.md` の189行目にある空欄の目印2つ(NUMBER と TITLE を二重の波括弧で囲んだもの)を、この spec の design.md の「書き換えの実装役」の節のとおりに書き換える。実装役は、ほかの行とほかのファイルを書き換えない。
  - 完了の確かめ方: `grep -nE '\{\{[A-Z0-9_]+\}\}'` を spec-readable-writing の spec.json・requirements.md・design.md・tasks.md に流して出力が無い。`reviews/rewrite-check.md` の最後の節の結果が「同じ」で、spec.json の `approval_history` に design の段階の要素が1つだけあり、requirements と tasks の承認の欄が書き換えの前と同じである
  - 受入基準とテストの対応: 要件1の受入基準5(雛形の説明の文字を、残った空欄と取り違えられない書き方にする)は、上の grep で確かめる。要件3の受入基準3(書き換えなかった段階の承認を変えない)は、spec.json の requirements と tasks の承認の欄で確かめる
  - _要件: 1.5, 2.1, 2.2, 2.3, 2.4, 2.5, 2.6, 3.1, 3.2, 3.3, 3.4_

- [ ] 2. 道具から書き方の読み分けを消す

  Claude は、タスク1のすべてが完了してから、このタスクに進む。タスク1のどれかに `_保留:_` が付いたら、Claude はこのタスクにもタスク3にも進まず、所有者の判断を待つ。

  タスク2の小タスクの完了の確かめ方で使う「道具の点検」は、design.md のテストの方針の2つの grep に、`grep -rn "新旧の見出しと目印の対応表\|対応表の新しい名前"` を加えた3つを、その小タスクで直したファイルに流し、出力が無いことを指す。

- [ ] 2.1 書き方の決まりと雛形を新しい書き方だけにする

  Claude は、design.md の「spec-writing.md と雛形と CLAUDE.md」の節のうち spec-writing.md と雛形の部分のとおりに、spec-writing.md と雛形を変える。Claude は、spec-writing.md の冒頭の段落と対応表を直し、tasks.md の見本の説明の文(「`spec_format` が2の spec で、…」)も印に触れない文にする。Claude は、`init.json` から `spec_format` と `ready_for_implementation` の欄を消し、`.kiro/settings/templates/specs-v1/` の4つのファイルを消す。
  - 完了の確かめ方: 始める前に、tasks.md のタスク1.1〜1.10がすべて `[x]` で `_保留:_` が無いことを確かめてある。`grep -rn "spec_format\|specs-v1\|今の名前" .kiro/settings` の出力が無く、spec-writing.md に「見出しと目印の一覧」の表がある。spec-writing.md の見本1・見本2の本文は変わっていない
  - 受入基準とテストの対応: 要件4の受入基準3(古い書き方のための雛形を消す)と受入基準4(spec-writing.md から古い書き方と印の記述を消す)は、上の grep で確かめる。要件4の受入基準5(書き換えを止めたら仕組みを消さない)は、始める前の確かめで確かめる
  - _要件: 4.1, 4.3, 4.4, 4.5_
  - _依存: 1.1, 1.2, 1.3, 1.4, 1.5, 1.6, 1.7, 1.8, 1.9, 1.10_

- [ ] 2.2 tasks.md の雛形の完了条件の節を書き直す

  Claude は、`.kiro/settings/templates/specs/tasks.md` の完了条件の節の本文を、design.md の「tasks.md の雛形の完了条件の節」の節の文に置き換える。
  - 完了の確かめ方: 雛形の完了条件の節に「上記フォーマット」「detail item」「受け入れ基準」「ゴールハック」が無く、テストの無い受入基準を残さないこと・verify のスキルを通すこと・見かけの合格の禁止・テストが失敗することの確かめの4つの決めごとが残っている
  - 受入基準とテストの対応: 要件5の受入基準1〜4(完了条件の節の文が指す先の分からない言葉を使わず、欄を欄の名前で指し、「受入基準」の表記をそろえ、節が決める中身を変えない)は、上の4つの言い回しが無いことを確かめる grep と、4つの決めごとの読み合わせで確かめる
  - _要件: 5.1, 5.2, 5.3, 5.4_

- [ ] 2.3 spec を作るスキルと要件を書くスキルから読み分けを消す

  Claude は、`/kiro-spec-init` と `/kiro-spec-requirements` の SKILL.md と、`kiro-spec-requirements/rules/requirements-review-gate.md` から、design.md の「書き方を読み分けないスキルと点検役」の節のとおりに読み分けと古い名前を消す。Claude は、`rules/ears-format.md` を消し、`kiro-spec-init` の `ready_for_implementation` に触れないよう指示する文と、新しい spec に `spec_format` を書く指示を消す。Claude は、対応表を指していた文を、spec-writing.md の「見出しと目印の一覧」を指す文にする。
  - 完了の確かめ方: 道具の点検を2つのスキルのディレクトリに流して出力が無い
  - 受入基準とテストの対応: 要件4の受入基準1(新しい spec を作るときに印を書かない)と受入基準2(道具が書き方を見分けない)は、上の点検で確かめる
  - _要件: 4.1, 4.2, 4.3_
  - _依存: 2.1_

- [ ] 2.4 設計とタスクを書くスキルから読み分けを消す

  Claude は、`/kiro-spec-design` と `/kiro-spec-tasks` の SKILL.md と、それぞれの `rules/` のファイル(`design-principles.md`、`design-review-gate.md`、`design-discovery-full.md`、`tasks-generation.md`、`tasks-parallel-analysis.md`)から、読み分けと古い名前を消す。Claude は、`tasks-generation.md` の42行目と181行目が指す見出しを新しい design.md の雛形の見出しにし、`design-discovery-full.md` の EARS の文言を design.md のファイルの構成の節のとおりに直す。Claude は、対応表を指していた文を、「見出しと目印の一覧」を指す文にする。
  - 完了の確かめ方: 道具の点検を2つのスキルのディレクトリに流して出力が無く、`tasks-generation.md` に「Architecture Pattern & Boundary Map」が無い
  - 受入基準とテストの対応: 要件4の受入基準2(道具が書き方を見分けない)と要件6の受入基準1(タスクを作る決まりが設計の雛形にある見出しを指す)は、上の点検と grep で確かめる
  - _要件: 4.2, 6.1_
  - _依存: 2.1_

- [ ] 2.5 spec を読むスキルから読み分けを消す

  Claude は、`/kiro-impl`(雛形2つを含む)・`/kiro-validate-impl`・`/kiro-review`・`/kiro-debug`・`/kiro-spec-status`・`/start`・`/kiro-spec-batch`・`/kiro-spec-quick` の SKILL.md と、`kiro-validate-gap/rules/gap-analysis.md` から、読み分けと古い名前を消す。Claude は、対応表を指していた文を、「見出しと目印の一覧」を指す文にする。
  - 完了の確かめ方: 道具の点検をこれらのファイルに流して出力が無い
  - 受入基準とテストの対応: 要件4の受入基準2(道具が書き方を見分けない)は、上の点検で確かめる
  - _要件: 4.2_
  - _依存: 2.1_

- [ ] 2.6 審査のスキルと点検役から読み分けを消す

  Claude は、`/spec-review` の SKILL.md と `rules/` の3つのファイル、`.claude/agents/spec-style-checker.md` から、読み分けと古い名前を消す。変更後の `/spec-review` は、すべての spec で点検の工程(Step 1.5)を行い、報告に「書き方の点検」の行を書く。Claude は、対応表を指していた文を、「見出しと目印の一覧」を指す文にする。
  - 完了の確かめ方: 道具の点検をこれらのファイルに流して出力が無く、`/spec-review` の SKILL.md に「`spec_format` が2の spec だけ」の文が無い
  - 受入基準とテストの対応: 要件4の受入基準2(道具が書き方を見分けない)は、上の点検で確かめる
  - _要件: 4.2_
  - _依存: 2.1_

- [ ] 2.7 CLAUDE.md から印と古い名前の記述を消す

  Claude は、CLAUDE.md の spec 駆動開発の節とIssueの印の節を、design.md の「spec-writing.md と雛形と CLAUDE.md」の節のとおりに直す。Claude は、対応表を指していた文を、「見出しと目印の一覧」を指す文にする。
  - 完了の確かめ方: 道具の点検と `grep -n "spec_format\|_Requirements:_\|(P)" CLAUDE.md` の出力が無い。CLAUDE.md の承認を取り消す決まりと `approval_history` の決まりは、`git diff` で見て変わっていない
  - 受入基準とテストの対応: 要件4の受入基準4(CLAUDE.md から古い書き方と印の記述を消す)は、上の grep で確かめる。要件3の受入基準6(特例を今回だけにし、これより後は今までどおり承認を取り消す)は、承認の決まりが変わっていないことで確かめる
  - _要件: 3.6, 4.4_
  - _依存: 2.1_

- [ ] 2.8 作業を止める判定のスクリプトと試験の変更を用意する (並行可)

  Claude は、変更後の `spec-review-scan.sh` と `test-spec-review-scan.sh` を、design.md の「spec-review-scan.sh」の節のとおりに scratchpad に用意する。
  - 完了の確かめ方: scratchpad の版をコンテナの中で流し、試験の場合がすべて通る。変更前の scan に対して、変えた場合1(印の無い spec でも、点検の記録が無ければ「書き方の点検の記録がない」を出す)が失敗する。足した場合6(特例で承認済みにした段階では、点検の記録が無くても点検についての理由を出さない)は、scan の人の承認を見分ける判定(74行目)を一時的に壊すと失敗し、元に戻すと通る
  - 受入基準とテストの対応: 要件3の受入基準5(特例で承認済みにした spec を承認済みとして扱う)は、テスト `test-spec-review-scan.sh` の場合6(特例で承認済みにした段階では、点検の記録が無くても点検についての理由を出さない)で確かめる。要件4の受入基準2(書き方を見分けない)は、同じテストの場合1(印の無い spec でも、点検の記録が無ければ「書き方の点検の記録がない」を出す)で確かめる
  - _要件: 3.5, 4.2_
  - _対象の部品: spec-review-scan.sh_

- [ ] 2.9 200行を超えるPRの検査と試験の変更を用意する (並行可)

  Claude は、変更後の `check-spec-backing.sh` と `test-check-spec-backing.sh` を、design.md の「check-spec-backing.sh」の節のとおりに scratchpad に用意する。Claude は、試験に、開き直しの形の場合(`approval_history` を持ち、`approved` が false で `approved_by` の無い段階がある spec。期待 1)も足す。
  - 完了の確かめ方: scratchpad の版をコンテナの中で流し、全ケースが成功する。変更前の検査に対しては、足した「ready_for_implementation が false でも3段階が承認済みなら通る」と「欄が無くても通る」の場合が失敗する
  - 受入基準とテストの対応: 要件7の受入基準1(3つの段階の承認がそろった spec を、承認がそろっていると判定する)は足した2つの場合、受入基準2(どれかの段階が承認されていない spec を、承認がそろっていないと判定する)は「tasks が未承認」「design が未承認」「requirements が未承認」の場合、受入基準3(開き直して承認が取り消された spec を、承認し直されるまで承認がそろっていないと判定する)は開き直しの形の場合で確かめる
  - _要件: 7.1, 7.2, 7.3, 3.5_
  - _対象の部品: check-spec-backing.sh_

- [ ] 2.10 所有者が写したファイルを確かめる

  Claude は、タスク2.8と2.9で用意した4つのファイルを作業場所へ写すコマンドを、1つの依頼にまとめて所有者に示す。所有者が写したあと、Claude は、写したファイルと scratchpad の版を `diff` で比べ、写した場所で2つの試験をコンテナの中で流す。
  - 完了の確かめ方: 4つのファイルで `diff` の出力が無く、2つの試験がすべて成功する
  - 受入基準とテストの対応: タスク2.8と2.9と同じ
  - _要件: 3.5, 4.2, 7.1, 7.2, 7.3_
  - _依存: 2.8, 2.9_

- [ ] 3. spec.json から印と使われない欄を消し、全体を確かめる
- [ ] 3.1 すべての spec.json から `spec_format` と `ready_for_implementation` を消す

  Claude は、design.md の移行の節のとおりに、`.kiro/specs/*/spec.json` のすべてから2つの欄を消す。この spec 自身の spec.json も対象にする。
  - 完了の確かめ方: `grep -rn "spec_format\|ready_for_implementation" .kiro/specs/*/spec.json` の出力が無く、すべての spec.json が JSON として読める(`perl -MJSON::PP` で読み込める)
  - 受入基準とテストの対応: 要件4の受入基準1(すべての spec.json から印を消す)は、上の grep で確かめる
  - _要件: 4.1_
  - _依存: 2.3, 2.4, 2.5, 2.6, 2.7, 2.10_

- [ ] 3.2 全体を確かめる

  Claude は、design.md のテストの方針の項目と道具の点検を、`.claude` と `.kiro/settings` と `CLAUDE.md` の全体に流し、結果をこのタスクの完了の記録に残す。あわせて、Claude は、このブランチの変更のうち200行の検査で数えられる行数を、`guardrails.yaml` と同じ除外で数える。数えた行数が200行を超えていたら、Claude は出荷せずに止め、200行を超えたことを所有者に知らせる。この spec の requirements.md は、Issue の本文の引用に空欄の目印の形を含むので、200行を超えるとこの spec を `Spec:` に書くPRが検査で赤になる。
  - 完了の確かめ方: design.md のテストの方針の節の grep と道具の点検の出力が、design.md の「作らないもの」の節に挙げたファイルだけである。書き換えた10件の spec の spec.json・requirements.md・design.md・tasks.md にプレースホルダの形が無い。数えた行数が200行以下である
  - 受入基準とテストの対応: 要件1〜7の受入基準のうち grep で確かめるものを、ここでまとめて確かめ直す
  - _要件: 1.5, 4.1, 4.2, 5.1, 6.1_
  - _依存: 3.1_

## 完了条件(全タスク共通)

Claude は、どのタスクでも、タスクの箇条書きの欄を書いたうえで、次の4つを満たしたときにタスクを完了とする。

1. Claude は、タスクが満たす requirements.md の受入基準(要件の番号付きの項目)ごとに、それを確かめるテストのファイル名とテスト名を「受入基準とテストの対応」の行に書く。Claude は、確かめるテストの無い受入基準を残さない。
2. タスクで変えた領域の verify のスキル(`/verify-frontend` `/verify-backend` `/verify-terraform`)が、すべて成功している。この spec は frontend・backend・terraform を変えないので、verify のスキルは対象外である。
3. Claude は、テストを飛ばす設定、アサーションの削除、カバレッジや lint の対象からの除外を足して、完了条件を満たしたように見せない。CI の escape-hatch の検査が、これらの追加を機械で見つける。
4. Claude は、新しく書いたテストについて、テストの対象のコードを一時的に壊してテストが失敗することを確かめてから、コードを元に戻す。

## 実装のメモ

- 書き換えのタスク(1.1〜1.10)では、Claude は、`/kiro-impl` の手順に加えて、確かめ役を起動し、特例の承認を記録する(design.md の処理の流れの節)
- Claude がタスク2.8と2.9の試験をコンテナの中で流すのは、ローカルには jq が無く、実行の権限の扱いも違うからである。
- Claude は、PR本文の「人間承認が必要な変更」に、`.claude/hooks/` と `.github/scripts/` に加えて、`.claude/skills/` と `.claude/agents/` も CODEOWNERS の承認の対象として挙げる。試験の期待を変えたので、Claude は PR本文に `Test-Change-Justification:` も書く。
