---
name: start
description: "Issueへの着手の入口。所有者が `/start` にIssue番号を付けて打ったときも、「#N をやって」のように言葉で着手を頼んだときも、Issueへの着手を頼まれたら必ず使う。AIがIssueの本文とその時点のコードを調べて、spec が要るかどうかと進め方を決める。"
argument-hint: "<#Issue番号>"
---

# start

Issueに着手するときの手順。**所有者がすることは、spec が要るかどうかに依らず `/start #<Issue番号>` の1つだけにする。** spec が要るかどうかは所有者には判断できないため、AIがIssueの本文とその時点のコードを調べて決める。

- 進め方を決めるのはこのスキルだけである。ほかのスキル(file-issue、ship など)は、このスキルが決めた進め方に従って呼ばれる
- AIは spec の各段階のコマンド(`/kiro-spec-init`、`/kiro-spec-requirements`、`/kiro-spec-design`、`/kiro-spec-tasks`、`/kiro-impl`)を自分で起動しない。これらは `disable-model-invocation` により、AIからは起動できない。必要なときは、所有者に打つよう依頼する
- AIは状態を自分で覚えておかない。進み具合は、GitHub のIssue(親子と開閉)と spec.json から毎回読み直す

## 手順

### 着手するIssueの番号を確かめる

引数が無いとき、または引数からIssueの番号が読めないときは、AIは所有者に番号を尋ね、答えを待つ。

### Step 1: Issueを読む

AIは次のコマンドでIssueを読む。

```bash
gh issue view <N> --json number,title,body,state,url,parent,subIssues,subIssuesSummary
```

- `comments` は取得しない。`--comments` も付けない。コメントは進め方を決めるときの要望として扱わず、本文だけを基準にする
- 返る欄の形(2026-10-02 に #472、#466 で確かめた):
  - `state`: Issueは `OPEN` か `CLOSED`。gh issue view はPRの番号も失敗せずに読めてしまい、開いているPRは `OPEN` を返す。そのため `state` だけではIssueかPRかを見分けられない
  - `url`: Issueは `https://github.com/<owner>/<repo>/issues/<N>`、PRは `.../pull/<N>` になる。IssueかPRかはこの欄で見分ける
  - `parent`: 親が無ければ `null`
  - `subIssues`: `nodes`(分けた部分のIssueの一覧)と `totalCount`
  - `subIssuesSummary`: `total`(分けた部分の数)、`completed`(閉じた数)、`percentCompleted`
- 番号のIssueが無いとき(gh が「Could not resolve to an issue or pull request」と返す)は、AIは着手せず、そのIssueが無いことを所有者に伝えて終える
- `url` に `/pull/` を含むときは、その番号はPRの番号で、その番号のIssueは無い。AIは着手せず、#<N> はIssueではなくPRの番号であることを所有者に伝えて終える
- `state` が `OPEN` でないとき(閉じたIssue)は、AIは着手せず、そのIssueが閉じていることを所有者に伝えて終える
- それ以外の理由で gh の問い合わせに失敗したとき(認証やネットワークの失敗など)は、AIは進め方を判断せず、問い合わせに失敗したことと gh のエラーの文面を所有者に伝えて終える。推測で進めない

### Step 2: 対応する spec を探す

AIは `.kiro/specs/*/spec.json` のうち、`issue` が N のもの、または `additional_issues` に N を含むものを探す。

見つからなければ Step 3 へ進む。見つかったときは、進め方を決め直さない。AIはその spec の進み具合と、所有者が次に打つコマンドを示して終える。次のコマンドは、spec.json の `approvals` と tasks.md を見て、次の表の上から順に最初に当てはまる行で決める。

| spec の状態 | AIが示すこと |
|---|---|
| `phase` が `initialized`(要件がまだ作られていない) | `/kiro-spec-requirements <feature>` を打ってください |
| requirements が生成済みで未承認 | 要件の本文と審査の記録(`reviews/`)を読み、承認するなら `/kiro-spec-design <feature>` を打ってください |
| requirements が承認済みで、design が未生成 | `/kiro-spec-design <feature>` を打ってください |
| design が生成済みで未承認 | 設計の本文と審査の記録を読み、承認するなら `/kiro-spec-tasks <feature>` を打ってください |
| design が承認済みで、tasks が未生成 | `/kiro-spec-tasks <feature>` を打ってください |
| tasks が生成済みで未承認(`approvals.tasks.approved` が false) | タスクの本文と審査の記録を読み、承認するなら `/kiro-impl <feature>` を打ってください |
| tasks が承認済みで、tasks.md に未完了のタスク(`- [ ]`)がある | `/kiro-impl <feature>` を打ってください |
| tasks が承認済みで、tasks.md のタスクがすべて完了(`- [x]`) | 出荷の状況を確かめる(下記) |

- 進み具合は、どの段階まで生成・承認されたかと、tasks.md の完了の数(例: 12件中7件完了)で示す
- 最後の行だけは、示して終えるのではなく、AIが出荷の状況を確かめて進める。開いているPRのうち、本文に `Spec: .kiro/specs/<feature>` を含むものを探し、あればその番号を示して、`/ship` の CI を見届ける手順から続ける。無ければ、AIが `/ship` で出荷する

### Step 3: 分けてあるかを見る

`subIssuesSummary.total` が1以上なら、このIssueはすでに分けて進められている。AIは分け方を決め直さない。

AIは `subIssues.nodes` から、分けた部分のIssueの番号・題名・開いているか閉じているかを一覧で示して終える。あわせて、所有者に、部分ごとに `/start #<分けた部分のIssueの番号>` を打つよう案内する。

```markdown
## してほしいこと
まだ開いている部分に着手するときは、部分ごとに `/start #<番号>` を打ってください。

## 分けた部分のIssue(全<total>件、閉じたもの<completed>件)
| 番号 | 題名 | 状態 |
|---|---|---|
| #<番号> | <題名> | 開いている / 閉じている |
```

### Step 4: コードを調べる

AIは、Issueの本文に関わるコード・文書・ワークフローを読み、その時点で何があり、何を変えることになるかを確かめる。広く探す必要があるときは、Explore のサブエージェントに任せてよい。調べた結果は、次の判断の根拠(ファイルと行)に使う。
