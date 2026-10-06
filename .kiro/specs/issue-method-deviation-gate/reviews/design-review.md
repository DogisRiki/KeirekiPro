# design のレビュー記録

## サイクル1 往復1(2026-10-06)

読んだもの: Issue #473 の本文(コメントは読んでいない)、design.md、requirements.md(承認済み)、research.md、spec.json、reviews/requirements-review.md、reviews/requirements-response.md、reviews/design-style.md、steering 3本、雛形 `.kiro/settings/templates/specs/design.md`、`.github/workflows/codex-review.yml`、`.github/workflows/guardrails.yaml`(スクリプトのテストと shellcheck の手順)、`.github/CODEOWNERS`、`.github/audit/required-checks.json`、`.github/scripts/check-spec-backing.sh` と `tests/test-check-spec-backing.sh`(スクリプトとテストの先例)、`.claude/skills/file-issue/SKILL.md`、`.claude/skills/review-loop/SKILL.md`、`README.md`(ワークフローの表と Mermaid の図)、`doc/インフラ設計/Github Actions設計/ワークフロー設計.md`。

前提の確かめ:

- `codex-review.yml` の Prepare review context は、`Spec:` のパスが実在しないときに `Refs: #N` のIssue本文を `spec.md` に書き出し(168〜173行目)、失敗したら `|| true` でPR本文に落としている。Write review prompt は `PROMPT_EOF` のヒアドキュメントのあとに `{ … } >> prompt.md` で実パスの一覧を足している(239〜249行目)。設計が足す場所(ヒアドキュメントのあと、実パスの一覧の前)は実在する。打ち消す2つの規則の文面(221〜222行目、235〜236行目)は設計の引用と一致する
- 手順に `shell:` の指定が無いので既定の `bash -e` で動く。設計の「コマンドが0以外で終われば手順が止まる」は成り立つ
- 権限は `contents: read` `pull-requests: write` `issues: read`(16〜19行目)。足す処理に追加の権限は要らない
- `codex-review` は `required-checks.json` に `paused` で登録済み。必須チェックの追加は不要という記述は正しい
- CODEOWNERS は `/.github/` 全体を所有者の承認対象にしている。新しいスクリプトとテストも対象になる
- スクリプトをワークフローの中で使う直前にテストする形は、`dependency-gate.yaml`(38行目)や `guardrails.yaml`(101行目)の先例と合う
- README の表の codex-review の行(105行目)と図の「系統4: AIレビュー」の箱(66〜67行目)、`ワークフロー設計.md` の「別AIによるレビュー」の行(185行目)は実在する
- 起票の決まりは見出しを `## 決めた方式` に固定し、中身の無い見出しを省く。スクリプトの見出しの判定と「中身が空なら『なし』」の扱いは、この決まりと合う
- 要件カバレッジ: 要件1の項目1〜7と要件2の項目1〜3は、どれも部品の節(スクリプト、ワークフローの手順2〜4、観点の節の文面)で裏付けられている。requirements のレビューで低として残した R1-1-3(抜けのときは作っていないものの名前)と R1-2-1(作り方を書いた項目を作っていない抜けは「沿っていない」)は、観点の節の文面に取り込まれている
- 「プロジェクトの決まりを守っているか」の7項目はすべて出ている。「品質チェックの設定を変える」の記載と `## ファイルの構成` の `.github/` のファイルは矛盾していない。新しいライブラリは出てこない(bash と awk はランナーにある)
- 「作らないもの」(自動レビューの再開、spec のPRの判定、往復の上限、起票の決まり、review-loop と start、必須チェックの追加)を、設計本文は扱っていない
- 要望の取りこぼしと勝手な追加は無い。意味の変わる誤記は無い

### 申告

**1. `Refs: #N` のIssue本文を取れなかったとき、PR本文に落として続けるのをやめ、手順を失敗にする** — 部品 codex-review.yml の手順2、`## 失敗したときの扱い`

- Issue の記載: なし(「違う作りなら…直るまでマージされない」とだけ書いている)
- 決めたこと: Issue本文の取得に失敗したら `::error::` を出して手順を失敗にし、ジョブを赤にする。「決めた方式」の見出しが無いIssueのPRにも当たる
- 他にありえた選択肢: 今のまま(取得に失敗したらPR本文を判定の基準にして続ける)。または、取得に失敗したときだけ再試行してから失敗にする
- 外れていた場合: 所有者が「見出しの無いIssueのPRは今と同じ動きのまま」と考えていたなら、一時的な取得の失敗で止まるPRが増える。逆に今のままにすると、取得に失敗した回は「決めた方式」があっても観点が足されず、外れたPRが通る。どちらを選び直しても、変わるのはワークフローの数行で、作り直しにはならない

**2. 「決めた方式」の節の抜き出しをスクリプト(`.github/scripts/extract-decided-method.sh`)で行い、Codex に見出しを探させない** — `## 概要`、`## 全体の構成`

- Issue の記載: なし
- 決めたこと: `.github/scripts/` にスクリプトとテストの2ファイルを新しく置き、ワークフローはそれを呼ぶだけにする
- 他にありえた選択肢: プロンプトだけを直して Codex に `spec.md` から見出しを探させる(research.md の案A)。codex-review とは別のジョブで判定する(案C)
- 外れていた場合: 所有者が「ワークフローの1ファイルだけ変える」ことを望んでいたなら、スクリプトとテストを取りやめてプロンプトに書き直すことになる。案Cを望んでいたなら、必須チェックの追加を含めて設計からやり直しになる

**3. 外れの判定を新しい判定の行にせず、spec適合の軸の High の指摘で `CHANGES_REQUESTED` にする** — `## 全体の構成`、部品 codex-review.yml の手順3

- Issue の記載: なし
- 決めたこと: `VERDICT_*` の行は2本のまま。Codex が「沿っていない」項目に High を付けることで、今の規則(High が1件以上なら `CHANGES_REQUESTED`)に乗せる。ワークフローは項目ごとの表の有無を検査しない
- 他にありえた選択肢: `VERDICT_DECIDED_METHOD: LGTM|CHANGES_REQUESTED` のような3本目の行を Codex に出させ、Evaluate verdict が「決めた方式」があるときはその行も見る
- 外れていた場合: Codex が観点の節を読み落として High を付けなかったとき、ワークフローには気づく手段が無く、外れたPRが通る。3本目の行にしていれば、行が無い(未出力)ときに fail-closed で止められた。判定の行を足し直す変更は Evaluate verdict と観点の節の数行で済み、作り直しにはならない

### 指摘

| ID | レベル | 該当箇所 | 内容 | 直し方の案 |
|---|---|---|---|---|
| D1-1-1 | 低 | `## 失敗したときの扱い` の「Issue本文を取れなかったとき」、部品 codex-review.yml の「失敗したとき」 | 「Claude は `/review-loop` の手順で原因を確かめ、再実行する」と書いているが、`review-loop/SKILL.md` の手順は Codex のコメントの指摘を分類して直す流れだけで、Codex が動く前に手順が失敗したときの扱いも、同じコミットで再実行する手順も無い。「作らないもの」で review-loop の変更を外しているので、委ねる先に手順が無いまま残る | この節に、再実行のしかたを直接書く(例: 原因が一時的な取得の失敗なら `gh run rerun <run-id>` で同じコミットを再実行する。Issue番号の誤りならPR本文を直さず、`/review-loop` の Rules に従って止まり所有者に報告する) |
| D1-1-2 | 低 | 部品 codex-review.yml の手順3(観点の節の文面) | 「沿っていない」項目ごとに High の指摘を書かせているが、その指摘がどちらの軸(コード品質か spec適合か)に数えるものかを文面で示していない。今のプロンプトも指摘を軸で分けていないので、Codex が High をコード品質の軸に数えると `VERDICT_CODE_QUALITY` が `CHANGES_REQUESTED` になる。PRは止まるので要件1の項目2の効き目は変わらないが、要約の表と「実物での確かめ」の見るべき行が食い違う | 観点の節に「この High は spec適合の軸の指摘として数え、`VERDICT_SPEC_COMPLIANCE` を `CHANGES_REQUESTED` にする」の1文を足す |
| D1-1-3 | 低 | `## 使う既存の仕組み` の1つ目と、部品 codex-review.yml の手順2の3つ目 | 前者は「Issueの分岐の中にだけ処理を足す」と書き、後者は `Spec:` の分岐と `Refs:` が無い分岐でも `DECIDED_METHOD=なし` を書くとしている。足す場所の説明が食い違う | 「分岐の前に `decided=なし` を初期値にし、Issueの分岐の中でだけ `あり` に変え、分岐のあとで1回 `$GITHUB_ENV` に書く」のように、足す場所を1つに揃えて書く |
| D1-1-4 | 低 | 部品 test-extract-decided-method.sh の「いつ動くか」、`## テストの方針` | テストを流す場所が、止まっている `codex-review.yml` の中だけなので、所有者が自動レビューを再開するまで CI ではテストが1度も動かない。`guardrails.yaml`(63〜75行目)は、使う側のワークフローの中で自己テストするスクリプトでも、PRの時点で確かめるために同じテストを流している | `guardrails.yaml` にもテストの手順を足すか、足さない理由(この spec の変更を codex-review.yml に閉じるため、など)を「いつ動くか」に書く。足す場合は `## ファイルの構成` の変えるファイルにも `guardrails.yaml` を足す |

### 前の段階への指摘

なし。

- 往復: 1回目 / 高0 中0 低4
- 往復: 1回で収束 / 未解決: 0件
