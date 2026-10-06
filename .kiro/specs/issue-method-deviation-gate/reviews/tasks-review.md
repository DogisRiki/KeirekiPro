# tasks のレビュー記録

## サイクル1 往復1(2026-10-06)

読んだもの: Issue #473 の本文(コメントは読んでいない)、tasks.md、design.md(承認済み)、requirements.md(承認済み)、research.md、spec.json、reviews/requirements-review.md、reviews/design-review.md、reviews/design-response.md、reviews/tasks-style.md、steering 3本、雛形 `.kiro/settings/templates/specs/tasks.md`、`.kiro/settings/rules/spec-writing.md`、`.claude/skills/kiro-spec-tasks/rules/tasks-generation.md`(Task Plan Review Gate)、`.github/workflows/codex-review.yml`、`.github/workflows/guardrails.yaml`(actionlint・shellcheck・スクリプトのテストの手順)、`.github/scripts/tests/test-check-spec-backing.sh`(テストの先例)、`.claude/settings.json`(`.github/**` への Edit/Write の拒否)、`README.md`(表の105行目と図の66〜67行目)、`doc/インフラ設計/Github Actions設計/ワークフロー設計.md`(185行目)、先例の spec の tasks.md(`spec-need-triage` `issue-close-and-auto-merge-guarantee` `audit-notification` の完了条件と実装のメモ)。

前提の確かめ:

- 要件カバレッジ: 要件1の項目1〜7と要件2の項目1〜3は、すべて少なくとも1つのタスクの `_要件:_` に現れる(1.1 はタスク 1.1・1.2・2.1、1.2〜1.7 はタスク 2.2、2.1 はタスク 1.1・1.2・2.1・2.2、2.2 はタスク 2.2、2.3 はタスク 2.1)。requirements に無い番号を参照しているタスクは無い
- design カバレッジ: 部品 `extract-decided-method.sh`(タスク 1.2)、`test-extract-decided-method.sh`(タスク 1.1。「テストの方針」の単体テストの8つの場合をすべて書くと明記)、`codex-review.yml` の手順1・2(タスク 2.1)、手順3・4(タスク 2.2)、`README.md と ワークフロー設計.md`(タスク 3)に、それぞれタスクがある。「テストの方針」の静的検証(タスク 4.1。design に無い shellcheck も足している)、プロンプトの組み立ての確かめ(タスク 2.2)、実物での確かめ(実装のメモ: PR本文に手順を書く)も扱われている。「失敗したときの扱い」のIssue本文の取得の失敗は、タスク 2.1 のエラーの文面で扱われている。タスク 3 の `_対象の部品:_` は design の部品名と一致し、`## ファイルの構成` の範囲に収まる
- スコープ膨張: requirements の「決めないこと」と design の「作らないもの」(自動レビューの再開、spec のPRの判定、往復の上限、起票の決まり、`/review-loop` と `/start`、必須チェックの追加)を、どのタスクもやっていない。実装のメモは `/review-loop` を変えないと明記している
- 完了条件: 雛形の4項目が、文言そのままで書かれている。タスク 2.1・2.2・3 の「受入基準とテストの対応」は、テストのファイルを持てない理由(ワークフローの手順、Codex の判定、説明の変更)を添えて置き換えており、理由の無い欠落ではない
- 並列と依存: `(並行可)` はタスク 3 だけで、触るのは `README.md` と `ワークフロー設計.md`。ほかのタスクは scratchpad の `impl/.github/` のファイルだけを作るので、並行に動かしても衝突しない。1.1→1.2→2.1→2.2 の順は、テストを先に書き、スクリプト、ワークフローの順に組み立てる流れで、`_依存:_` を書かなくても読み取れる
- 実ファイルとの照合: `codex-review.yml` の `PROMPT_EOF`(179〜237行目)のあとに実パスの一覧(239〜249行目)があり、タスク 2.2 が足す位置は実在する。Evaluate verdict の表(295〜302行目)に行を足す位置も実在する。`settings.json` は `Edit(.github/**)` `Write(.github/**)` を拒否しており(61〜62行目)、実装のメモの「設定で止められる」は正しい。`guardrails.yaml` の actionlint は `rhysd/actionlint:1.7.12`(43行目)、shellcheck は `koalaman/shellcheck:v0.11.0`(53行目)で、タスク 4.1 の版と一致する。README は CRLF、`ワークフロー設計.md` は LF でコミットされており、タスク 3 の改行の確かめは意味がある
- design の審査の低の指摘4件(D1-1-1〜D1-1-4)は、response で「tasks で扱う」とされた。tasks は、D1-1-1 をエラーの文面に委ね、D1-1-2 と D1-1-4 は足さないと決め(実装のメモ)、D1-1-3 はタスク 2.1 の説明で3つの分岐のふるまいを書いた
- 要望の取りこぼしと勝手な追加は無い。意味の変わる誤記は無い

### 申告

**1. 抜き出しのテストを `guardrails.yaml` では流さず、`codex-review.yml` の中だけで流す** — `## 実装のメモ` の2つ目

- Issue の記載: なし
- 決めたこと: design の審査の D1-1-4(自動レビューが止まっている間は CI でテストが1度も流れない)に対し、`guardrails.yaml` には足さず、このPRでは手元のコンテナで流した結果をPR本文に書く
- 他にありえた選択肢: `guardrails.yaml` の「Test reserve auto merge」などと同じく、PRの時点で流す手順を足す(design の `## ファイルの構成` に `guardrails.yaml` を足すことになる)
- 外れていた場合: 所有者が自動レビューを再開するまで、あとのPRがスクリプトやテストを壊しても CI は気づかない(shellcheck は通る)。再開したあとの最初の実行で、テストの手順が赤になって初めて分かる。`guardrails.yaml` に手順を1つ足せば済み、作り直しにはならない

**2. 観点の節に「この High は spec適合の軸に数える」の1文を足さず、design の文面のままにする** — `## 実装のメモ` の3つ目、タスク 2.2

- Issue の記載: なし
- 決めたこと: design の審査の D1-1-2(Codex が High をコード品質の軸に数えるおそれ)に対し、文面を足さない。どちらの軸が `CHANGES_REQUESTED` でもジョブは赤になるので、マージが止まることは変わらないとした
- 他にありえた選択肢: design の観点の節の文面に、High を spec適合の軸の指摘として数え `VERDICT_SPEC_COMPLIANCE` を `CHANGES_REQUESTED` にする旨の1文を足す(design の手順3の文面の変更になる)
- 外れていた場合: Codex が High をコード品質の軸に数えると、PRは止まるが、要件1の項目2の「spec適合の判定を『直す必要あり』にする」の形にはならず、実行の要約の spec適合の行は `LGTM` のまま出る。実装のメモの4つ目に書いた実物での確かめ(spec適合が `CHANGES_REQUESTED` になることを見る)が、この理由で合格にならないことがありうる。直すのはプロンプトの1文で、作り直しにはならない

**3. Issue本文の取得に失敗して赤になったPRの扱いを `/review-loop` に足さず、エラーの文面の案内に任せる** — `## 実装のメモ` の4つ目、タスク 2.1

- Issue の記載: なし
- 決めたこと: design の審査の D1-1-1(`/review-loop` に再実行の手順が無い)に対し、`/review-loop` は変えず、`::error::` の文面に「`Refs:` の番号を確かめてジョブを再実行すればよい」と書く
- 他にありえた選択肢: `/review-loop` に、Codex が動く前に手順が失敗したときの扱い(同じコミットで再実行する、Issue番号の誤りなら所有者に報告する)を足す
- 外れていた場合: Claude が `/review-loop` の手順どおりに Codex のコメントを探して見つからず止まる。ジョブのログのエラーを読めば進めるので、影響は往復1回分の遅れにとどまる

### 指摘

| ID | レベル | 該当箇所 | 内容 | 直し方の案 |
|---|---|---|---|---|
| T1-1-1 | 低 | `## 完了条件(全タスク共通)` の2つ目 | この spec が変えるのは `.github/`・`README.md`・`doc/` だけで、`/verify-frontend` `/verify-backend` `/verify-terraform` のどれも対象にならない。雛形の文のままだと、何も流さずに満たしたことになる。先例の spec(`spec-need-triage` `issue-close-and-auto-merge-guarantee` `audit-notification`)は、この項目に「既存の verify Skill の対象外である。代わりに guardrails.yaml と同じ検査を手元で通す」と書き足している。タスク 4.1 が実質の代わりになっているので、実装への影響は無い | 2つ目の項目に「この spec は frontend・backend・terraform を変えないので、verify のスキルは対象外である。Claude は、代わりに、タスク 4.1 の静的検証とテストを通す」の2文を足す |
| T1-1-2 | 低 | タスク 2.1 の説明の文 | 「Issue本文を `spec.md` に書き出す分岐の中で抜き出しを呼び、`DECIDED_METHOD` を `$GITHUB_ENV` に書く処理を足す」と「`Spec:` のパスが実在する分岐と `Refs:` が無い分岐では…`DECIDED_METHOD=なし` を書く」が並び、`なし` をどこに書くか(3つの分岐のそれぞれか、分岐の前に初期値を置いて分岐のあとで1回書くか)が決まっていない。design の審査の D1-1-3 を tasks で扱うとしたが、同じ曖昧さが残っている。どちらで作っても動き、完了の確かめ方の5つの入力で確かめられるので、実装への影響は無い | 説明の文を「`decided=なし` を分岐の前に置き、Issueの分岐の中で `decided-method.md` に中身があるときだけ `あり` に変え、分岐のあとで `DECIDED_METHOD=$decided` を `$GITHUB_ENV` に1回書く」のように、足す場所を1つに決めて書く |
| T1-1-3 | 低 | タスク 2.2 の「受入基準とテストの対応」 | 要件2の受入基準2(「決めた方式」に書かれていない作り方は理由があれば適合)を、`なし` の `prompt.md` が変更前と同じであることだけで確かめている。この受入基準は `DECIDED_METHOD=あり` のときにも当てはまり(「決めた方式」に無い作り方は今のまま緩い)、design の観点の節は打ち消しを「決めた方式の項目には当てはめない」と限っている。`あり` の側の確かめが書かれていないが、文面は design で固定されているので、実装への影響は無い | 対応の行に「要件2の受入基準2は、加えて、`あり` の `prompt.md` の観点の節で、2つの規則の打ち消しが『決めた方式の項目』に限られていることを読んで確かめる」の1文を足す |

### 前の段階への指摘

なし。

- 往復: 1回目 / 高0 中0 低3
- 往復: 1回で収束 / 未解決: 0件
