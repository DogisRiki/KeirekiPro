# tasks の審査の記録

## サイクル1 往復1(2026-10-11)

requirements.md の受入基準(1.1〜1.6、2.1〜2.7、3.1)と design.md の部品・テストの方針・ファイルの構成を tasks.md と突き合わせ、`session.sh` `lib.sh` `test-session.sh`、`/start` と `/kiro-spec-init` と `/ship` のスキル、README のコマンドの一覧、`guardrails.yaml` の shellcheck の手順、`check-escape-hatches.sh` を読んで確かめた。

要件のカバレッジ: すべての受入基準が、少なくとも1つのタスクの `_要件:_` に現れる(1.1〜1.6 は 1.2・1.3・3.1、2.1〜2.7 は 2.1〜2.3・3.2・3.3、3.1 は 1.1・1.2・2.1・3.1・3.2)。存在しない番号を引くタスクは無い。design のカバレッジ: 7つの部品(`check-start` の変更、`claim` と `takeover` の変更、`check-spec`、`prune` の変更、start スキル、kiro-spec-init スキル、README)は、それぞれ 1.1〜1.2、1.3、2.1〜2.2、2.3、3.1、3.2、3.3 が扱う。テストの方針の場合は、`check-start` の予約が 1.1〜1.3、同時の `check-start` が 1.2、`claim` が 1.3、`check-spec` が 2.1・2.2、`prune` が 2.3 に割り当てられている。`_対象の部品:_` の3つは、design の `## ファイルの構成` の範囲に収まる。スコープ: design の `### 作らないもの`(spec `parallel-sessions` の本文、`/start` の判断の段階の調べ、spec の各段階のコマンドへの調べ、新しい spec を作る形、フックと settings.json、GitHub Actions)に当たるタスクは無い。完了条件の4項目は雛形のとおりに書かれ、verify のスキルが無いことと、スキルの変更に自動のテストが無いことは、実装のメモに理由つきで書かれている。並列: `(並行可)` は 3.1〜3.3 だけで、互いに別のファイルを変え、`_依存:_`(3.1 は 1.3、3.2 は 2.2)は部品の境界をまたぐ依存を正しく示している。1.x と 2.x はどれも `session.sh` と `test-session.sh` を変えるので、順に進める指定で合っている。

design の審査で記録のみとした D1-1-2(69で終わる前に錠を返す)は 1.1 の「錠のディレクトリを消してから `_kp_die69` を呼ぶ形にそろえる」で、D1-1-3(「食い違う spec:」の行をPR本文に書く)は実装のメモの3つ目で、D1-2-2(手順2の2つの意味)は 3.2 の 2a〜2d の番号で扱われている。

### 申告

**1. スキルの変更(3.1・3.2)の Claude の動きは、マージのあとに所有者が行う実地の確かめだけで確かめる** — tasks.md 3.1・3.2 の「受入基準とテストの対応」、実装のメモの2つ目と3つ目

- Issue の記載: あり。「確かめ方」の2つ(同じIssueに数秒差で `/start` を打つ、同じ spec を直す別々のIssueで両方のセッションで spec を直すコマンドを打つ)
- 決めたこと: 3.1 と 3.2 の完了の確かめ方は SKILL.md に決めた文があるかどうかにし、要件1の受入基準2・4・5・6、要件2の受入基準2・3・4・7、要件3の受入基準1の Claude の動きは、PR本文に書いた実地の確かめ(マージのあと)に回す
- 他にありえた選択肢: マージの前に、所有者が2つの worktree でセッションを開いてIssueの「確かめ方」を行い、その結果を見てからPRを承認する。または、SKILL.md の決めた文の有無を `test-session.sh` のような機械の検査にする
- 外れていた場合: SKILL.md の手順の書き方の誤り(たとえば、2c で「やめた」のあとに 2b をやり直すと書き忘れる)は、マージのあとに所有者が実地で確かめて初めて分かり、直しは別のPRになる。スクリプトの側(1.1〜2.3)はテストで確かめてあるので、誤りが残るのはスキルの手順の文だけである

**2. 失敗の経路のうち、テストを置かないもの** — tasks.md 2.1・1.3 の「受入基準とテストの対応」

- Issue の記載: なし。要件3の受入基準1が「調べを終えられなければ進まない」と定めている
- 決めたこと: 要件3の受入基準1のテストは、錠を取れないとき(1.1)、予約を書けないとき(1.2)、`origin/main` が無いときと名前の誤り(2.1)に限る。design の「失敗したとき」にある、`check-spec` の手順4で git のコマンドが失敗したときの終了コード69と一時的な索引の削除、`claim` と `takeover` が錠を取れないときの69には、テストを置かない(design の「テストの方針」にも無く、tasks はそれに従っている)
- 他にありえた選択肢: `test-session.sh` にある、決まったサブコマンドだけが失敗する git の差し替え(`t_prune_skips_without_worktree_list` L724-741、`t_takeover_apply_failure_reopens_branch` L1111-1131)と同じ作りで、`read-tree` か `write-tree` が失敗する場合を足し、終了コード69と、W の git のディレクトリに一時的な索引が残らないことを確かめる
- 外れていた場合: `check-spec` が git の失敗を69にせず、空の `conflicts` で0を返す作りになっても誰も気づかず、ほかのセッションが同じ spec を直していても `/kiro-spec-init` が進む(要件3の受入基準1の取りこぼし)。一時的な索引のファイルがほかの作業フォルダの `.git` に残り続ける

### 指摘

| ID | レベル | 該当箇所 | 内容 | 直し方の案 |
|---|---|---|---|---|
| T1-1-1 | 中 | tasks.md 1.2 と 1.3 の「完了の確かめ方」(1.3 の「既存の `claim` と `takeover` の場合を含む」)、`## 実装のメモ` の3つ目 | 既存のテストのうち2つの場合は、design の新しい動きと逆のことを確かめているので、そのままでは通らない。(1) `t_claim`(`test-session.sh` L488-506)の2回目の `claim`(L497-502)は、ほかの作業フォルダ WT2 とほかのセッション s-old の記録を、MAIN のセッション s-new の `claim` が書き直して成功することを確かめる。design の「session.sh claim と takeover の変更」では、`folder` が違う記録は断って終了コード1なので、この場合は必ず赤になる。run_test の名前(L1190「claim がIssueの記録を書き、すでにあれば書き直す」)も新しい動きと合わない。(2) `t_prune_branch_gone`(L583-594)は、ブランチを消したあとの `check-start` で `issues/42.json` が無いこと(L593)を確かめるが、1.2 のあとの `check-start` は、`prune` が記録を消したあと何も見つけずに予約を書くので、ファイルは必ずできる。1.3 は既存の場合が変わらず通ると書き、1.2 は既存の場合に触れていない。どちらも実装で必ず赤になり、Claude がテストの期待を書き換えることになるが、どう書き換えるかを tasks が決めていない。シェルのテストの書き換えは escape-hatch の機械検知の外(`check-escape-hatches.sh` L183-186 は frontend と backend のテストだけを見る)なので、CLAUDE.md と `/ship`(SKILL.md L43)が求めるPR本文の `Test-Change-Justification:` は Claude が自分で書くしかないが、実装のメモの「PRの本文に書くもの」に入っていない | 1.2 に、`t_prune_branch_gone` の `check-start` のあとの記録の確かめを「予約(`folder` がいまの作業フォルダ、`branch` が空、`session_id` がこのセッション)がある」に直すことを書く。1.3 に、`t_claim` の2回目の `claim` を「ほかの作業フォルダの記録なら終了コード1で断り、記録を書き換えない」に直し、run_test の名前も直すことを書く。実装のメモの3つ目に、PR本文に `Test-Change-Justification:` と、design の `claim` の断りと `check-start` の予約に合わせて既存の2つの場合の期待を変えた理由を書くことを足す |
| T1-1-2 | 低 | tasks.md 1.2 と 1.3 の説明の文(`test-session.sh` に足す場合) | 1.2 は「design.md の「テストの方針」の `check-start` の予約の場合」をすべて足すと書き、1.3 は「`end` のあとの `check-start` の場合」を足すと書く。design の「テストの方針」では、`end` のあとの `check-start` の場合は `check-start` の予約の群(5つ目)に入っているので、同じ場合が 1.2 と 1.3 の両方に割り当てられている。1.2 の `_要件:_` に 1.4 が無いことから、1.3 に置く意図と読めるが、1.2 の文からは除かれていない。実装では、1.2 で足したあと 1.3 で足すものが無いだけなので、影響しない | 1.2 の説明の文に「`end` のあとの `check-start` の場合を除く」と書くか、1.3 から `end` の場合を外して 1.2 に 1.4 を足す |
| T1-1-3 | 低 | tasks.md 3.2 の説明の文(「`git merge origin/main` を打ったあとは手順2からやり直し、2a から 2d ももう一度通る」) | design の審査への対応の記録(design-response.md の D1-2-1)は、「手順2をやり直したあとに足した手順を繰り返さない(取り込み済みなので4は飛ぶ)形に書きそろえる」と処置を書いた。tasks は逆に、2a〜2d をもう一度通る(2d は何もしない)と書いている。design.md の図(`Merge` → `Read` → `Fetch`)とは合っているので、要件2の受入基準7の動きは変わらず、実装にも影響しない。ただ、対応の記録と tasks が食い違ったまま残る | tasks の 3.2 を対応の記録の処置に合わせる(手順2のやり直しのあとは 2a〜2d を飛ばして手順3か手順4へ進む)か、対応の記録の D1-2-1 の処置を tasks の形に合わせて書き直す。どちらかにそろえる |

### 前の段階への指摘

なし。タスクに落として初めて分かった requirements と design の穴は見つからなかった。

- 往復: 1回目 / 高0 中1 低2

## サイクル1 往復2(2026-10-11)

往復1の T1-1-1 への修正(tasks.md 1.2 の `t_prune_branch_gone` の書き換え方、1.3 の `t_claim` の書き換え方と完了の確かめ方、実装のメモの4つ目の `Test-Change-Justification:`)を、design.md の部品「session.sh check-start の変更」の `started` の判定と予約の書き込み、部品「session.sh claim と takeover の変更」、`test-session.sh` の全体(check-start を呼ぶ場合31か所、claim を呼ぶ場合7か所)と突き合わせて確かめた。

1.2 の書き換え方は design と合う。ブランチを消したあとに `prune` を打てば記録は消え(`session.sh` の冒頭の注記 L45-46)、そのあとの `check-start` は、`folder_conflict` `leftovers` `branch_only` がすべて空なので、`branch` が空の予約(`folder` がいまの作業フォルダ、`session_id` が `--session` の s-me)を作る。1.3 の書き換え方も design と合う。`folder` と `session_id` が空の記録は「`prune` が残した記録」として書き直せ、WT2 と s-old の記録は「ほかのセッションの記録」の2つの条件(`folder` が違う、`session_id` が違う)の両方に当たるので終了コード1で断る。実装のメモの4つ目は、`/ship` が求める `Test-Change-Justification:` の行と、2つの場合を変えた理由を書くことを決めている。

ただし、`check-start` が予約を書くことと、ほかのセッションの記録に `started` を付けることで赤になる既存の場合を、`test-session.sh` の check-start を呼ぶ31か所すべてについて、design の `started` の4つの条件と予約の3つの場合に当てて確かめたところ、往復1で挙げた2つのほかにもう1つ、必ず赤になる場合が残っていた(下の T1-2-1)。ほかの28か所は、予約が書かれても出力の確かめに影響しないか(`t_end_clears_conflict` `t_folder_conflict_idle_ignored` `t_capacity` `t_prune_quiet_in_check_start` など)、同じセッションの記録なので `updated_at` だけが変わるか(`t_leftover_own_claim_excluded` の1回目、`t_takeover_from_self` L1023、`t_takeover_then_check_start` L1070)、`started` が付いても `kinds` を確かめていない(`t_takeover_then_check_start` L1074-1076、`t_takeover_back_unhides_receiver` L1087-1088)ので、変わらず通る。`t_leftover_branch_without_spec`(L376-392)は、s-wt のセッションの記録が無いので `started` の条件3に当たらず、`kinds` は `branch` と `changes,branch` のまま通る。

往復1の低の指摘2件(T1-1-2、T1-1-3)は記録のみの処置で、どちらも実装に影響しないので、出し直さない。

### 申告

往復1の2件に加えるものは無い。往復1の修正で足した既存のテストの書き換え方は、design の動きから一つに決まるものなので、申告の対象ではない。

### 指摘

| ID | レベル | 該当箇所 | 内容 | 直し方の案 |
|---|---|---|---|---|
| T1-2-1 | 中 | tasks.md 1.2 の説明の文と「完了の確かめ方」、`## 実装のメモ` の4つ目 | T1-1-1 の修正は `t_claim` と `t_prune_branch_gone` の2つを直したが、1.2 の `started` の判定で必ず赤になる既存の場合がもう1つある。`t_leftover_own_claim_excluded`(`test-session.sh` L360-373)は、MAIN でセッション s-me が Issue 42 を `claim` したあと(L363-364 でセッションの記録と `claim`)、同じ MAIN から別のセッション s-other で `check-start` を呼び(L369)、MAIN の作りかけの `kinds` が `spec,changes,branch` であることを確かめる(L372)。design の「`started` の判定」の4つの条件に当てると、記録の `session_id`(s-me)は空でなく、s-other と違い、`sessions/s-me.json` があって MAIN は無くなっておらず、MAIN は bare でない worktree で `handed_over_from` に入っていないので、すべてに当たる。design は `kinds` の並びを `started` `spec` `changes` `branch` の順と決めているので、1.2 のあとの `kinds` は `started,spec,changes,branch` になり、L372 は必ず赤になる。tasks の 1.2 はこの場合に触れておらず、実装のメモの4つ目も書き換える既存のテストを `t_claim` と `t_prune_branch_gone` の2つに限っているので、Claude がこの場合をどう書き換えるか(`started` を期待に足すのか、`started` を外して確かめるのか、`kinds` の確かめを消すのか)を決める材料が無い。`kinds` の確かめを消す書き換えをしても、シェルのテストは escape-hatch の機械検知の外なので止まらない | 1.2 の説明の文に、`t_leftover_own_claim_excluded` の L372 の期待を `started,spec,changes,branch` に直すことを書く(ほかの種類と一緒のときの `started` の位置を確かめる場合にもなる)。実装のメモの4つ目の、書き換える既存のテストに `t_leftover_own_claim_excluded` を足し、理由(ほかのセッションの記録に `started` が付くようになったこと)を書く |
| T1-2-2 | 低 | tasks.md 1.3 の説明の文(`t_claim` の書き換え方) | T1-1-1 の直し方の案にあった run_test の名前(`test-session.sh` L1190「claim がIssueの記録を書き、すでにあれば書き直す」)の直しが、1.3 に入っていない。場合の中身を「ほかのセッションの記録では断る」形に書き換えると、この名前は新しい動きと逆のままになる。名前は `ok:` の行に出るだけなので、テストの合否には影響しない | 1.3 の説明の文に、run_test の名前を「claim は、記録が無いか空の記録なら書き、ほかのセッションの記録なら終了コード1で断る」のように直すことを足す |

### 前の段階への指摘

なし。

- 往復: 2回目 / 高0 中1 低1

## サイクル1 往復3(2026-10-11)

往復2の T1-2-1 への修正(tasks.md 1.2 の `t_leftover_own_claim_excluded` の書き換え方、実装のメモの4つ目の対象と理由)を、design.md の部品「session.sh check-start の変更」の `started` の判定と `kinds` の並び、`test-session.sh` L360-373 と突き合わせて確かめた。

1.2 の書き換え方は design と合う。L364 の `claim` のあとの記録は `folder` が MAIN、`session_id` が s-me、`branch` が main で、L369 の s-other の `check-start` から見ると、`started` の4つの条件にすべて当たる。design が決めた並び(`started` `spec` `changes` `branch`)のとおり、L372 の期待は `started,spec,changes,branch` になる。1.2 の文は、この場合が4つの条件にすべて当たることを理由として書き、書き換えのあとの期待を一つに決めている。L366 の s-me の1回目の `check-start` は、`folder_conflict` `leftovers` `branch_only` がすべて空で、記録が同じセッションのものなので、予約の書き込みは `updated_at` だけを書き直し(design の予約の2つ目の場合)、`branch` の main は残る。L367 と L370 の確かめは変わらず通る。実装のメモの4つ目は、書き換える既存のテストを `t_claim` `t_prune_branch_gone` `t_leftover_own_claim_excluded` の3つにし、理由に「ほかのセッションの記録を `started` として返すようになったこと」を足している。`/ship` の SKILL.md L43 が求める `Test-Change-Justification:` の行の形と合う。

往復2のあとに main に入った #541 の変更(`t_capacity_only_responding` L449-464、`t_conflict_and_leftover_ignore_responding` L467-482)も当てて確かめた。前者は Issue 42 の記録が無く `leftovers` `folder_conflict` `branch_only` がすべて空なので予約が書かれるが、確かめているのは `capacity.active` だけで、予約の `session_id` は s-me 自身なので `active` から除かれ、変わらず通る。後者は `folder_conflict` が空でないので予約を書かず、Issue 42 の記録が無いので `started` も付かない。往復2で確かめた既存の場合に、この往復で新たに赤になるものは無い。

往復1・2の低の指摘3件(T1-1-2、T1-1-3、T1-2-2)は記録のみの処置で、どれも実装に影響しないので、出し直さない。T1-2-2 については、対応の記録が「1.3 で `t_claim` を書き換えるときに合わせて直す」と決めており、合否に影響しないことは往復2の指摘のとおりである。

### 申告

往復1の2件に加えるものは無い。

### 指摘

なし。

### 前の段階への指摘

なし。

- 往復: 3回で収束 / 未解決: 0件
