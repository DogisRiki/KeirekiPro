---
name: spec-review
description: spec文書(requirements/design/tasks)を別モデルのサブエージェントにレビューさせ、指摘への対応を往復して記録に残す。各段階の生成直後に実行する。
allowed-tools: Read, Write, Edit, Bash, Glob, Grep, Agent
argument-hint: <feature-name> <requirements|design|tasks>
---

# spec-review Skill

spec 文書を `spec-reviewer`(Fable 5.1)にレビューさせ、指摘に対応して記録を残す。**各段階の生成直後に実行する。** 所有者が承認するときに、本文と記録の両方が手元にある状態を作るのが目的。

## 役割の分担

| 誰が | 何をするか | 書くファイル |
|---|---|---|
| spec-reviewer(サブエージェント) | 審査して指摘を書く | `reviews/{段階}-review.md` だけ |
| このスキル(メインセッション) | 指摘に対応して本文を直す | spec 本文、`reviews/{段階}-response.md` |

**`{段階}-review.md` に書かない。** レビュー役だけが書くファイルである。

## 手順

### Step 1: 準備

1. 引数から `FEATURE` と `STAGE` を取る。`STAGE` は `requirements` / `design` / `tasks` のいずれか
2. `.kiro/specs/{FEATURE}/reviews/` が無ければ作る
3. `CYCLE` を決める: `reviews/{STAGE}-review.md` にある最大のサイクル番号 + 1。ファイルが無ければ 1
4. `ROUND` を 1 にする

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
- `unresolved` で `ROUND` が 3 未満なら、`ROUND` を 1 増やして Step 2 へ
- `unresolved` で `ROUND` が 3 なら、**本文を直さずに**終了する。残った高と中を「未解決」として response に書き、Step 7 へ

**最終往復の後に本文を直さない。** 直すと、直した内容を誰もレビューしないまま承認に上がる。

### Step 6: 前の段階への指摘があった場合

1. 往復を止める
2. 所有者に報告する。報告には次を含める
   - 指摘の内容と、どの段階に戻るのか
   - **その spec で何回目の差し戻しか**(review ファイルの再レビューの節を数える)
   - **2回目以降は、直す以外の選択肢も並べる**: spec を分割する / requirements から作り直す
3. 所有者が直すと判断した場合
   - 戻る段階とその後続の段階について、spec.json の `approved` を `false` にし、`approved_by` と `approved_at` を削除する
   - 本文を直す
   - その段階について、`CYCLE` を 1 増やして Step 2 からやり直す(往復は新たに最大3回)
   - 後続の段階を作り直し、それぞれレビューする

### Step 7: 所有者への報告

チャットには件数と場所だけ出す。

```
requirements のレビューが終わりました(サイクル1、往復2で収束)。
高 0件 / 中 0件 / 低 2件 / 未解決 0件
申告 3件

.kiro/specs/{feature}/requirements.md
.kiro/specs/{feature}/reviews/requirements-review.md
.kiro/specs/{feature}/reviews/requirements-response.md
```

## 制約

- **spec 本文を直すのはこのスキルだけ。** レビュー役には直させない
- 往復は最大3回。`kiro-impl` と同じく上限で打ち切る
- 低の指摘は直さない。記録に残す
- 同じ指摘で3往復を使い切った場合は、所有者に判断を仰ぐ
