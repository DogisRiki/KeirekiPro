---
name: spec-review
description: spec文書(requirements/design/tasks)を別モデルのサブエージェントにレビューさせ、指摘への対応を往復して記録に残す。各段階の生成直後に実行する。
allowed-tools: Read, Write, Edit, Bash, Glob, Grep, Agent
argument-hint: <feature-name> <requirements|design|tasks>
---

# spec-review Skill

spec 文書を `spec-reviewer`(Fable 5.1)にレビューさせ、指摘に対応して記録を残す。spec.json の `spec_format` が2の spec では、審査の前に毎往復、`spec-style-checker` に本文の書き方を点検させる。**各段階の生成直後に実行する。** 所有者が承認するときに、本文と記録の両方が手元にある状態を作るのが目的。

## 役割の分担

| 誰が | 何をするか | 書くファイル |
|---|---|---|
| spec-style-checker(サブエージェント) | 本文の書き方を点検し、外れと直し方の案を返す(`spec_format` が2の spec だけ) | なし |
| spec-reviewer(サブエージェント) | 審査して指摘を書く | `reviews/{段階}-review.md` だけ |
| このスキル(メインセッション) | 点検の案と指摘に対応して本文を直す | spec 本文、`reviews/{段階}-style.md`、`reviews/{段階}-response.md` |

**`{段階}-review.md` に書かない。** レビュー役だけが書くファイルである。

## 手順

### Step 1: 準備

1. 引数から `FEATURE` と `STAGE` を取る。`STAGE` は `requirements` / `design` / `tasks` のいずれか
2. `.kiro/specs/{FEATURE}/reviews/` が無ければ作る
3. `CYCLE` を決める: `reviews/{STAGE}-review.md` にある最大のサイクル番号 + 1。ファイルが無ければ 1
4. `ROUND` を 1 にする
5. `.kiro/specs/{FEATURE}/spec.json` の `spec_format` を読む。値が `2` なら、各往復で Step 2 の前に Step 1.5 を行う。`spec_format` の欄が無い spec(値が2でない spec)では Step 1.5 を飛ばし、今までどおり Step 2 へ進む

### Step 1.5: 書き方の点検(`spec_format` が2の spec だけ)

審査役を起動する前に、本文の書き方を点検し、中身の変わらない直しを本文に入れる。この工程は審査役の起動の前にだけ行い、最終往復の審査役の後には行わない。

1. Agent ツールで `spec-style-checker` を起動する。**モデルを指定しない**(起動したセッションと同じモデルを使わせるため)。渡すもの:
   - spec の名前(`FEATURE`)
   - 段階(`STAGE`)
   - 本文のパス(`.kiro/specs/{FEATURE}/{STAGE}.md`)
2. 点検役の最終応答を読む。応答は「外れは無い」の1行か、`## 文の書き方の外れ` `## 組み立て・design.md の書き方・繰り返しの外れ` `## まとめ` の3つの見出しを持つ形のどちらかである。どちらの形でもないときは、点検役を1回だけ起動し直す
3. 「中身が変わるか: 変わらない」の外れについて、案のとおりに本文を直す
   - 文の書き方の外れ: 原文の文を、書き直しの案の文に置き換える
   - 組み立て・design.md の書き方・繰り返しの外れ: 直し方の案のとおりに、節を足す、消す、まとめる
4. 「中身が変わるか: 変わる(…)」の外れでは、本文を直さない。該当する文や節と、括弧の中の理由を控えておく(記録と Step 7 の報告に使う)
5. **本文を直し終えてから**、`reviews/{STAGE}-style.md` の末尾に節を1つ足す。ファイルが無ければ作る。前に書いた節は書き換えない。外れが無かったときも、0件の節を足す
   - 判定のスクリプト `spec-review-scan.sh` は、点検の記録の変更日時が本文より新しいことを確かめる。そのため、本文を直す前に記録を書かない

点検の記録の書式(日時は UTC の ISO 8601):

```markdown
## 点検 2026-10-02T07:10:00Z

- 直した文: 3
- 直した節: 1
- 直さなかった外れ: 1
  - 42行目「…」: 書き直すと、承認を取り消す段階が変わるため
```

- `直した文` は文の書き方の外れで直した件数、`直した節` は組み立て・design.md の書き方・繰り返しの外れで直した件数である
- 直さなかった外れは1件ごとに1行書く。文の外れは `<行番号>行目「<原文>」: <理由>`、節の外れは `節「<見出し>」: <理由>` の形にする

所有者が承認の前に本文を直したら、`/spec-review` を流し直す。そのとき点検役は、所有者が直した文を含めて本文の全体を点検し、このスキルは所有者が書いた文も、直しても中身が変わらない範囲で直す。本文には所有者が書いた文を区別する手段が無く、直しても決めごとの中身は変わらないからである。

### Step 2: レビュー役を起動する

Agent ツールで `spec-reviewer` を起動する。**モデルを指定しない**(定義ファイルの `claude-fable-5-1` を使わせるため。起動時の指定は定義より優先される)。

渡すもの:

- `FEATURE` / `STAGE` / `CYCLE` / `ROUND` / `REVIEW_FILE`(`.kiro/specs/{FEATURE}/reviews/{STAGE}-review.md`)
- **直前1往復分**の review と response の該当部分(`ROUND` が 2 以上のとき)
- **却下された指摘の一覧**(そのサイクルの全往復分。ID とレベルと1行の要約だけ)

材料は読ませない。レビュー役が自分で読む。

### Step 3: 応答から構造化ブロックを読む

レビュー役の最終応答から `- FEATURE:` から `- STATUS:` までのブロックを読む。`- STATUS:` 行だけを厳密に見る。

ブロックが無い、または形式が違う場合は、**ブロックだけを出力させる再起動を1回行う**。このとき `REVIEW_FILE` に追記させない(同じ往復が二重に残るため)。

### Step 4: 指摘に対応する

`reviews/{STAGE}-review.md` の今回の往復を読み、`reviews/{STAGE}-response.md` に追記する。

| 指摘 | すること | 処置 |
|---|---|---|
| 高・中 | 本文を直す | 修正 |
| 高・中で誤検知と判断した | 直さない。根拠を具体的に書く | 却下 |
| 低 | 直さない | 記録のみ |
| 前の段階への指摘 | 直さない。Step 6 へ | 所有者判断待ち |

**`review.md` の全指摘に処置を書く。** 書き漏らすと Stop フックが止める。

response の書式:

```markdown
## サイクル<N> 往復<M> への対応(<日付>)

| ID | 処置 | 内容 |
|---|---|---|
| R1-1-1 | 修正 | requirements.md 要件3の受入基準に観測点を追記した |
| R1-1-2 | 却下 | 要件2.3 に既定があり、指摘は事実誤認。該当行を引用: ... |
| R1-1-4 | 記録のみ | 表現の指摘。実装に影響しない |
```

### Step 5: 往復の判定

- `STATUS` が `converged`(高と中が0件)なら終了。Step 7 へ
- `unresolved` で `ROUND` が 3 未満なら、`ROUND` を 1 増やして Step 1.5 へ(`spec_format` が2でない spec は Step 2 へ)。Step 4 で直した本文を、審査役の前にもう一度点検するためである
- `unresolved` で `ROUND` が 3 なら、**本文を直さずに**終了する。残った高と中を「未解決」として response に書き、Step 7 へ

**最終往復の後に本文を直さない。** 直すと、直した内容を誰もレビューしないまま承認に上がる。Step 1.5 の点検も、終了した後には行わない。

### Step 6: 前の段階への指摘があった場合

1. 往復を止める
2. 所有者に報告する。報告には次を含める
   - 指摘の内容と、どの段階に戻るのか
   - **その spec で何回目の差し戻しか**(review ファイルの再レビューの節を数える)
   - **2回目以降は、直す以外の選択肢も並べる**: spec を分割する / requirements から作り直す
3. 所有者が直すと判断した場合
   - **取り消す前に、承認を `approval_history` に写す。** 戻る段階とその後続の段階のうち、`approved` が `true` の段階ごとに、spec.json の `approval_history` に次の要素を1つ追記する(配列が無ければ作る)。書式は kiro-spec-init の更新の形と同じ
     ```json
     {
       "stage": "requirements",
       "approved_by": "<approvals.requirements.approved_by>",
       "approved_at": "<approvals.requirements.approved_at>",
       "issues": [<issue>, <additional_issues の各番号>],
       "revoked_at": "<現在の ISO 8601 の日時>",
       "revoked_for": "<差し戻しの理由。指摘のIDと1行の要約>"
     }
     ```
     - `issues` には、その承認のときに spec が対象にしていたIssue(`issue` と、いまの `additional_issues`)を入れる
     - `revoked_for` の例: `"D1-1-3 による requirements への差し戻し: 要件4の受入基準が design の前提と食い違う"`
     - `approval_history` は追記だけにし、書いてある要素を書き換えたり消したりしない
   - 戻る段階とその後続の段階について、spec.json の `approved` を `false` にし、`approved_by` と `approved_at` を削除する
   - 本文を直す
   - その段階について、`CYCLE` を 1 増やして Step 1.5 からやり直す(`spec_format` が2でない spec は Step 2 から。往復は新たに最大3回)
   - 後続の段階は自分で作り直さない。所有者に、後続の段階のコマンドを順に打つよう依頼する(requirements に戻るときは `/kiro-spec-design <feature>` と `/kiro-spec-tasks <feature>`、design に戻るときは `/kiro-spec-tasks <feature>`)。各段階のコマンドには `disable-model-invocation` が付いており、AIからは起動できない。所有者が打って生成された段階は、それぞれこのスキルでレビューする

### Step 7: 所有者への報告

チャットには件数と場所だけ出す。`spec_format` が2の spec では、次の2つを足す。

- 書き方の点検で直した文と節の数。この回の `/spec-review` の全往復の合計を出す
- 直さなかった外れのすべて。1件ごとに、該当する文や節と、直さなかった理由を示す

```
requirements のレビューが終わりました(サイクル1、往復2で収束)。
高 0件 / 中 0件 / 低 2件 / 未解決 0件
申告 3件
書き方の点検: 直した文 5件 / 直した節 1件 / 直さなかった外れ 1件
  - requirements.md 42行目「…」: 書き直すと、承認を取り消す段階が変わるため

.kiro/specs/{feature}/requirements.md
.kiro/specs/{feature}/reviews/requirements-review.md
.kiro/specs/{feature}/reviews/requirements-response.md
.kiro/specs/{feature}/reviews/requirements-style.md
```

`spec_format` の欄が無い spec では、「書き方の点検」の行と `-style.md` の行を出さない。

## 制約

- **spec 本文を直すのはこのスキルだけ。** レビュー役には直させない
- 往復は最大3回。`kiro-impl` と同じく上限で打ち切る
- 低の指摘は直さない。記録に残す
- 同じ指摘で3往復を使い切った場合は、所有者に判断を仰ぐ
