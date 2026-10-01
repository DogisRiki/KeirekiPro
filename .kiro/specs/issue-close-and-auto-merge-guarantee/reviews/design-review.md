# design レビュー記録: issue-close-and-auto-merge-guarantee

## サイクル1 往復1(2026-10-01)

確認した材料: `design.md`、`requirements.md`、`research.md`、`spec.json`、`reviews/requirements-review.md`、`reviews/requirements-response.md`、Issue #455 本文、`.kiro/settings/templates/specs/design.md`、`.github/workflows/rearm-auto-merge.yaml`、`dependabot-auto-merge.yaml`、`guardrails.yaml`、`pre-merge-check.yaml`、`update-pr-branches.yaml`、`canary.yaml`、`audit-weekly.yaml`(冒頭と権限)、`.github/scripts/lib-ledger-issue.sh`、`check-release-age.sh`(目印の箇所)、`create-canary-prs.sh`、`.claude/skills/ship/SKILL.md`、`README.md` のワークフロー一覧と図、`doc/開発フロー/基盤構築手順.md`(140〜274行目)、`doc/開発フロー/監査手順.md`(該当箇所)。

要件1〜7 の受入基準は、すべて Requirements Traceability に現れ、対応するコンポーネントがある。requirements レビューで design に送られた低の指摘(R1-1-5 対象のPRの定義、R1-1-7 Issue の知らせの解消、R1-1-8 カナリアPRの見分け方、R1-2-2 付け直しを止めたPRと見直し、R1-2-3 「マージの後に」が指すPR)は、どれも本文で決まっている。

設計の前提のうち、このレビューで確かめたこと。

- GitHub 自身が Issue を閉じた日時は、PR のマージ日時の1秒後だった(`gh issue view` で3組を確認。PR #451 と Issue #446: 01:49:58 と 01:49:59、PR #449 と Issue #447: 01:45:56 と 01:45:57、PR #458 と Issue #457: 03:47:06 と 03:47:07)。「`mergedAt` 以降の `ClosedEvent`」という判定と、60秒の待ち時間は、この3組では成り立つ
- Dependabot の PR 本文(PR #357)では、取り込んだ変更履歴の中の番号は `<a href=...>#1961</a>` の形に置き換わっており、設計の読み取り規則(`closes` のあと空白を挟んで `#<番号>`)には当たらない。Dependabot の PR のマージで、このリポジトリの Issue が誤って閉じられる経路は見つからなかった
- 監査の台帳は `github.token` でコメントしている(`audit-weekly.yaml` `audit-inventory.yaml` `mutation-report.yaml`)。設計の「通知の作法」の記述は実ファイルと合っている
- 実行 36812062119 と 36694835305 の中身(予約が外れたイベントでの起動)は、このレビューでは確かめられなかった(使えるコマンドが `gh issue view` に限られるため)。research.md の記載をそのまま前提にしている

### 申告

**1. bot のトークンを使うワークフローを、PR のイベント(`pull_request`)と定期実行で動かす。ゲート設定の変更を伴う** — design.md KeirekiPro Compliance Check 6項目め、auto-merge.yaml の Event Contract、Security Considerations、research.md「起動のイベントは `pull_request` を使う」

- Issue の記載: なし(「仕組みが必ず付ける」とだけある)
- 決めたこと: `rearm-auto-merge.yaml` を削除し、`auto-merge.yaml` と `close-linked-issues.yaml` を足す。`guardrails.yaml` の `escape-hatch` にテスト3本を足し、`.claude/skills/ship/SKILL.md` を変える。予約は `secrets.BOT_GITHUB_TOKEN` で行い、起動は `pull_request`(作成・開き直し・下書き解除・コミット・予約外れ)と30分ごとの定期実行。同じリポジトリの PR がワークフローの定義そのものを書き換えた場合、その定義が bot のトークンつきで動く(現行の `rearm-auto-merge.yaml` と同じ条件だが、起動するイベントの種類は増える)。Compliance Check の6項目めはチェックを入れず、「変更を必要とする。機能がゲート設定の領域にあるため分離できない」と書いている
- 他にありえた選択肢: `pull_request_target` で起動し、ワークフローの定義を常に main から取る。または定期実行だけにして、PR のイベントでは bot のトークンを使わない
- 外れていた場合: ブランチに push できる者(所有者と bot)が書き換えたワークフローが、bot のトークンで動く。後から `pull_request_target` に替える場合は、予約が外れたイベントで起動するかを測り直すことになる

**2. 仕組みそのものが動かないときは、赤で終わるだけで所有者に届かない** — design.md Error Handling、Monitoring、Non-Goals

- Issue の記載: あり。「Issue が閉じなかったときは、所有者に知らせが届く」「予約に失敗したときは、所有者に知らせが届く」
- 決めたこと: 知らせのコメントを付けられない、自己テストが失敗する、照会できない、定期実行が止まる(60日間活動が無いと自動で止まる)のどれも、実行が赤になるだけで知らせは出ない。残余リスクとして運用文書に書く。bot のトークンの期限切れは、予約の失敗として `github.token` のコメントで届く
- 他にありえた選択肢: 週次監査に「開いている対象のPRに予約が無い」「マージ済みPRの `Closes` の Issue が開いたまま」の確認を足す。`ci.yaml` の死活確認(`audit-liveness`)と同じ形で定期実行の停止を見る
- 外れていた場合: スクリプトの不具合などで両方のワークフローが赤になり続けると、#448 と同じく、誰も気づかないまま Issue が開いて残り、PR が止まる

**3. 知らせは、対象の PR・Issue へのコメントと所有者へのメンションで出す。作成者は `github-actions[bot]`** — design.md 各スクリプトの「知らせ」、lib-notice-comment.sh、research.md「知らせは PR・Issue へのメンションつきコメントで行う」

- Issue の記載: あり。「所有者に知らせが届く」。届け方には触れていない
- 決めたこと: PR・Issue ごとにコメントし、先頭行で所有者にメンションする。担当者の割り当てはしない(監査の台帳はメンションに加えて担当者にも割り当てている)。知らせを一覧で見る場所は無い。届くことは、導入後の確認の5番で確かめる
- 他にありえた選択肢: 監査と同じ、決まったタイトルの通知 Issue を1件持つ。メンションに加えて担当者に割り当てる
- 外れていた場合: メンションが届かなければ、知らせは PR・Issue を開くまで見えない。導入後の確認で分かるが、届け方を替えると知らせの重複を防ぐ仕組み(目印)も作り直しになる

**4. 導入した時点で、開いている PR すべてと、過去7日にマージされた PR にさかのぼって働く** — design.md Migration Strategy

- Issue の記載: なし
- 決めたこと: 導入後に両方の見直しを手動で1回ずつ動かす。開いていて下書きでない PR(Dependabot とカナリアを除く)には予約が付く。過去7日のマージ済み PR について、`Closes` の Issue が開いていれば閉じ、`Refs:` だけの開いた Issue には知らせを付ける。導入の前に、予約の無い開いている PR の一覧を所有者に示す
- 他にありえた選択肢: 導入後に作成・マージされた PR だけを対象にする
- 外れていた場合: 所有者がマージするつもりの無い開いた PR が、チェックが緑になった時点でマージされる。過去7日に `Refs:` だけを書いた PR があれば、その Issue に一斉に知らせが付く

**5. 知らせは、同じ PR の同じコミットにつき1回だけ。その後に同じことが起きても出ない** — design.md reserve-auto-merge.sh の「知らせ」、lib-notice-comment.sh

- Issue の記載: なし
- 決めたこと: `failed` と `stopped` の知らせは、head のコミットごとに1回。予約が付いたら `resolved` を1回付ける。同じコミットでもう一度失敗しても、もう一度止まっても、新しい知らせは出ない(目印が既にあるため)。Issue 側の知らせには「解消」のコメントを付けない
- 他にありえた選択肢: `resolved` のあとに起きた失敗は、新しい知らせとして出す
- 外れていた場合: 所有者が知らせを見て手で予約し、その予約がまた外れた場合、PR は予約の無いまま止まり、2度目の知らせは出ない(新しいコミットが積まれるまで)

**6. 定期実行の間隔と待ち時間** — design.md auto-merge.yaml・close-linked-issues.yaml の Batch / Job Contract、System Flows

- Issue の記載: なし
- 決めたこと: 予約の見直しは30分ごと、Issue の見直しは1時間ごと。マージの直後は60秒待ってから Issue を確かめる。Issue の見直しは、マージから5分たてば対象にする(要件2-4 の「1時間」より早く閉じる)
- 他にありえた選択肢: 見直しを1日1回にする。マージの直後は待たずに閉じる
- 外れていた場合: 影響は小さい。定期実行の回数が1日あたり72回増える

**7. PR 本文のどこに書いてあっても、`closes` と `refs` のあとの番号を拾う** — design.md close-linked-issues.sh「本文の読み取り規則」

- Issue の記載: なし
- 決めたこと: 大文字小文字を区別せず、`closes`(または `refs`)、任意の `:`、空白、`#<番号>` の並びを本文全体から拾う。行頭に限らない。`Fixes` `Resolves` と `owner/repo#<番号>` は扱わない。1つの `closes` のあとに番号を並べた場合(`Closes #1, #2`)は最初の1つだけ
- 他にありえた選択肢: 行頭にある場合だけ拾う。コードの引用の中は除く
- 外れていた場合: PR 本文の説明文の中に「…は Closes #12 で…」のような記述があると、その Issue が閉じられる。`Refs` も同じで、説明文の中の記述から知らせが付く

### 指摘

| ID | レベル | 該当箇所 | 内容 | 直し方の案 |
|---|---|---|---|---|
| D1-1-1 | 中 | design.md System Flows「Issue のクローズ」、close-linked-issues.sh の Postconditions と Invariants | マージより前に閉じられ、そのまま閉じている Issue の扱いが決まっていない。フロー図は「マージの後に一度でも閉じられたか」だけで分岐し、いいえなら「閉じて記録する」へ進む。Postconditions の `untouched` も「`mergedAt` 以降に一度でも閉じられている」場合だけを挙げている。このとおりに作ると、マージの前から閉じている Issue(所有者が先に手で閉じた場合や、同じ Issue を `Closes` に書いた2本目の PR がマージされた場合)に、閉じる操作と「PR #<番号> のマージにより閉じました」の記録が行われ、要件1-4(すでに閉じているときは何も書き込まない)に反する。Testing Strategy には「閉じている Issue には書き込みの呼び出しが無い(1.4)」とあるが、テストの Issue を「マージの後に閉じた」状態で用意すると通ってしまい、この場合は確かめられない。外部依存に `issue.state` を挙げているのに、フローと Postconditions のどこにも状態の判定が無い | フローの最初に「いま閉じているなら何もしない」の分岐を置き、`untouched` の定義に「いま閉じている」を足す。テストの項目を「`mergedAt` より前の `ClosedEvent` しか無く、いま閉じている Issue には書き込みの呼び出しが無い」と具体的に書く |
| D1-1-2 | 中 | design.md close-linked-issues.yaml と auto-merge.yaml の Batch / Job Contract、Testing Strategy「ワークフローの検査」と「導入後の人間による確認」 | 見直しの対象を選ぶ判定(マージが7日前から5分前まで、最大200件、開いている main 向けの PR)がワークフローの中にあり、確かめる手段が無い。Testing Strategy は「2.7 の7日、4.2 の30分ごと」などを「実装のレビューと導入後の確認で確かめる」としているが、導入後の確認の6項目に見直しを通る項目は無く(どれもイベントの経路)、このパイプラインに人間による実装のレビューは無い。要件2-4・2-5・2-7・4-2 は、自動テストでも人間の確認でも確かめられないまま残る。「ワークフローは判定を持たない」(auto-merge.yaml の Responsibilities)とも、要件6-6(判定の部分を自動テストで検証できる形で持つ)とも合わない。tasks は受入基準ごとにテストの対応付けを求めるため、その段階で design に戻ることになる | 対象を選ぶ部分をスクリプトに移す(例: `close-linked-issues.sh` に見直しの入口を足し、現在時刻を引数か環境変数で渡して、7日と5分の境界を `gh` の偽物でテストする)。少なくとも、導入後の確認に「見直しだけで閉じる・知らせる・予約する」ことを確かめる項目を足す(例: イベントの経路を通らなかった PR を手動の見直しで拾えること) |
| D1-1-3 | 中 | design.md lib-notice-comment.sh の Responsibilities と Service Interface、reserve-auto-merge.sh「未解消の知らせがある」 | 知らせの作成者を見分ける値(`NOTICE_AUTHOR` の既定 `github-actions[bot]`)を、どの API のどの項目と比べるかが書かれていない。REST のコメント一覧(`repos/<repo>/issues/<番号>/comments` の `.user.login`)では `github-actions[bot]` だが、`gh pr view --json comments` や GraphQL の `author.login` では `github-actions` になる。後者で作ると既にある知らせが一致せず、見直しのたびに(PR は30分ごと、Issue は1時間ごとに7日間)メンションつきの同じ知らせが増え続け、要件2-8 と 5-3 に反する。`resolved` の判定も働かない。テストは `gh` を偽物に置き換えるため、偽物が返す名前の形しだいで通ってしまい、出荷後に最初の知らせが出るまで分からない。既存の `check-release-age.sh` は `gh api user` で自分の名前を取っているが、`github.token` ではこの方法を使えないため、既存の作法をそのまま写すこともできない | コメントの一覧を読む API(REST の `issues/<番号>/comments`)と比べる項目(`.user.login`)を Service Interface に書く。テストの偽物が返す応答の形もそれに合わせると書く。導入後の確認に「知らせが付いたあと、見直しをもう一度動かしても知らせが増えない」を足す |
| D1-1-4 | 低 | design.md Migration Strategy | 導入の PR 自身では、予約が外れても付け直す仕組みが働かない。PR のイベントで動くワークフローは PR 側の定義を使うため、削除した `rearm-auto-merge.yaml` は動かず、新しい `auto-merge.yaml` は base のコミットを checkout するのでスクリプトがまだ無く、自己テストで赤になる。この PR は所有者の承認が要り、承認後に予約が外れる事象(#440)が起きやすい条件に当たる。同じ理由で、導入の時点で開いている PR も、ブランチが最新化されるまではイベントの経路が赤になる(30分ごとの見直しが拾う) | Migration Strategy に「導入の PR で承認後に予約が外れたら、手で予約し直す」と「導入の PR では `auto-merge.yaml` の実行が赤になるが、必須チェックではない」を書く |
| D1-1-5 | 低 | design.md Modified Files | AI に予約の操作を求める、または予約を `/ship` の作業として説明する記述が、挙げられた箇所のほかにも残る。`.claude/skills/ship/SKILL.md` の冒頭の説明(2行目)・Job(9行目)・Report(75行目)、`CLAUDE.md` 83行目(「verify→commit→push→PR→auto-merge予約」)、`README.md` 401行目(`/ship` の説明「マージ予約までの一連の出荷作業」)、`.github/scripts/create-canary-prs.sh` 37行目のコメント(「カナリアPRには auto-merge を設定しない」。導入後は仕組みが除外する)。要件7-1 の趣旨(古い手順どおりに AI が予約し続けない)から、手順6だけを直すと記述が食い違う | Modified Files の各行に、直す箇所として上の行を足す |
| D1-1-6 | 低 | design.md close-linked-issues.yaml の Batch / Job Contract、close-linked-issues.sh の Postconditions `closed` | マージのイベントのジョブと見直しのジョブは別の concurrency で、同じ PR を同時に扱わない保証は「直近5分を除く」だけである。イベントのジョブの開始が5分を超えて遅れると、両方が同じ Issue を閉じ、記録のコメントが2つ付くことがある(記録のコメントには目印による重複の防止が無い)。また、閉じる操作が成功して記録のコメントだけ失敗した場合、次の見直しでは「マージの後に閉じられた」に当たるため、記録は付かないまま残る(要件1-3)。どちらもまれで、害は小さい | 記録のコメントにも目印を付けて `notice_post` で1回だけ付ける。または、起こりうることとして Implementation Notes に書く |

### 前の段階への指摘

なし。

- 往復: 1回目 / 高0 中3 低3

## サイクル1 往復2(2026-10-01)

確認した材料: 修正後の `design.md`、`requirements.md`、`research.md`、`spec.json`、`reviews/design-response.md`、Issue #455 本文、`.kiro/settings/templates/specs/design.md`、`.github/workflows/rearm-auto-merge.yaml`、`dependabot-auto-merge.yaml`、`guardrails.yaml`(ステップの並び)、`.github/scripts/lib-ledger-issue.sh`、`create-canary-prs.sh`(カナリアの印)、リポジトリ内で `rearm-auto-merge` と自動マージの予約に触れている箇所の検索結果。

往復1の中の指摘3件が直っていることを、本文で確かめた。

- D1-1-1: フロー図の最初に「いま閉じているか」の分岐があり、閉じていれば次の Issue へ進む。`untouched` の定義と Invariants に「いま閉じている(閉じた時期を問わない)」が入った。テストは、`ClosedEvent` が `mergedAt` より後のものと、より前のものしか無いものの両方を確かめると書かれている。要件1-4 と合う
- D1-1-2: 見直しの対象を選ぶ判定が `reserve-auto-merge.sh --sweep` と `close-linked-issues.sh --sweep` に移り、ワークフローは `--sweep` を1回呼ぶだけになった。7日と5分の境界は `NOW_EPOCH` を固定してテストすると書かれている。対応表の 2.4・2.5・2.7・4.2 はスクリプトを指している。要件6-6 と合う
- D1-1-3: コメントの一覧は REST の `issues/<番号>/comments` で読み、`.user.login` を `NOTICE_AUTHOR` と比べると書かれている。テストの偽物も同じ応答の形を返すと書かれている。既存の `dependabot-auto-merge.yaml` の見直しも同じ API と項目(`.user.login`)で目印の作成者を見分けており、作法が揃っている

修正で新しく入った記述(`--sweep` の契約、テスト、導入後の確認 7・8)と、ほかの節との食い違いを確かめた。高と中に当たるものは見つからなかった。`rearm-auto-merge.yaml` を参照しているのは README の一覧表の1行だけで、削除によって壊れる参照はほかに無い。

### 申告

往復1の申告7件から変わっていない。修正で新しく決まったことは、見直しの対象の選び方をスクリプトに置いたことだけで、申告6(間隔と待ち時間)の範囲に収まる。

### 指摘

| ID | レベル | 該当箇所 | 内容 | 直し方の案 |
|---|---|---|---|---|
| D1-2-1 | 低 | design.md Components and Interfaces の一覧表と、`reserve-auto-merge.sh`・`close-linked-issues.sh` の詳細の Requirements の行 | 一覧表は `reserve-auto-merge.sh` に 4.1–4.5、`close-linked-issues.sh` に 2.1–2.7 を挙げているが、詳細の Requirements の行には 4.2 と 2.4・2.5・2.7 が無い(`--sweep` を足す前のまま)。Intent も「PR 1件について」のままで、一覧表の「見直しの対象の一覧」と合わない。対応表と Service Interface は正しいため、実装は変わらない | 詳細の Requirements の行に 4.2 と 2.4・2.5・2.7 を足し、Intent に見直しの入口を足す |
| D1-2-2 | 低 | design.md auto-merge.yaml の Batch / Job Contract「PR ごとの呼び出しに `timeout 120` を付ける」 | ワークフローは `--sweep` を1回呼ぶだけになったため、PR ごとの時間の上限を付ける場所がワークフローに無い。上限を付けるのがスクリプトの中なのかが書かれていない。`close-linked-issues.sh --sweep` には同じ記述が無い。1件が止まるとジョブの上限(30分)まで残りの PR が見直されないが、次の定期実行が拾う | 上限はスクリプトの `--sweep` が1件ごとに付けると書き、Issue の見直しにも同じ扱いを書く |
| D1-2-3 | 低 | design.md Testing Strategy「導入後の人間による確認」7 と 8 | 確認 7 は、マージから5分たつ前に見直しを動かすと、その PR が対象から外れるため、知らせが増えないことを確かめたことにならない。確認 8 の例(確認 2 で予約を外した直後)は、予約が外れたイベントですぐ付け直されるため、予約の無い PR を見直しに渡せない。見直しだけで予約が付くことは、Migration Strategy の 3(導入の時点で開いている PR に予約が付く)で確かめられる。判定そのものは自動テストで確かめるため、実装への影響は無い | 確認 7 に「マージから5分以上たってから」を足す。確認 8 は、導入の直後に見直しを動かしたとき、開いていた対象の PR に予約が付いたことを見る形にする |

### 前の段階への指摘

なし。

- 往復: 2回目 / 高0 中0 低3
- 往復: 2回で収束 / 未解決: 0件

## サイクル2 往復1(2026-10-01)

サイクル2 は、承認後の修正(要件7-5 の置き場所を「導入の PR の本文」に変更、要件7-6 の追加)に合わせて design を直したことによる再レビューである。

確認した材料: 修正後の `design.md` 全文、修正後の `requirements.md`、`research.md`、`spec.json`(3段階とも承認が取り消されている)、`reviews/design-response.md`(「承認後の修正」の節)、`reviews/requirements-review.md`、`reviews/requirements-response.md`、`tasks.md`(design の記述だけで後の工程が迷わないかを見るため)、Issue #455 本文、`.kiro/settings/templates/specs/design.md`、`.github/workflows/rearm-auto-merge.yaml`、`guardrails.yaml`(`escape-hatch` のステップ)、`dependency-graph.yaml`・`update-pr-branches.yaml`・`dependabot-auto-merge.yaml` の起動条件、`.claude/skills/ship/SKILL.md`、`README.md` の該当行、`doc/開発フロー/基盤構築手順.md`(135〜234行目)、`doc/開発フロー/監査手順.md`(見出しと予約に触れている行)。

修正箇所を requirements と突き合わせた結果。

- 要件7-5: 対応表の 7.5 は「導入の PR の本文」を指し、Testing Strategy の「導入後の人間による確認」は置き場所を導入の PR の本文と明記している。要件7-5 が挙げる4つ(所有者の PR に予約が付く、知らせが届く、マージ後の後続の処理が動く、`pre-merge-check` ラベルの PR が承認までマージされない)は、確認の 1・5・3・4 に対応する。確認 3 が名指しする `dependency-graph.yaml` と `update-pr-branches.yaml` は、どちらも main への push で起動する実ファイルである
- 要件7-6: 対応表に 7.6 の行があり、Modified Files の監査手順.md の行は「1回だけ行う確認の手順は書かない(導入の PR の本文に書く)」としている。監査手順.md に足すと書かれているもの(知らせの対処、付け直されること、保留はラベル、残余リスク)は、どれも繰り返し参照する内容で、要件7-6 に反しない。Error Handling と Monitoring の「運用文書に残余リスクとして書く」も同じく反しない
- 基盤構築手順.md の変更(152・205・215行目付近の検証用 PR の記述)は、既にある記述を仕組みに合わせて直すもので、本specの導入のための作業を足すものではない。設計は要件7-6 の「導入」を本specの仕組みの導入と読んでおり、この読み方で本文に矛盾は無い
- Migration Strategy の 4 は「手順は導入の PR の本文にある」となっており、Testing Strategy と合っている。Boundary Commitments と Non-Goals に、今回の修正と食い違う記述は無い
- KeirekiPro Compliance Check の7項目は、サイクル1 から変わっていない。6項目め(ゲート設定)はチェックを入れずに変更が要ることを明記しており、File Structure Plan と合っている。7項目めは、いつ何をどう確かめたかが書かれている

サイクル1 で確かめた設計の前提(実ファイルとの整合)は、今回読み直した範囲で変わっていない。Issue 本文もサイクル1 のときと同じである。

対応記録についての注記(design 本文への指摘ではない)。`design-response.md` の D1-2-3 の処置は「tasks の運用文書の変更に含める」と書かれたままで、要件7-6 の追加後は事実と合わない(同じ内容は、いまは導入の PR の本文に書く扱いになっている)。同じファイルの「承認後の修正」の節が後から書かれているため実害は無いが、所有者が承認のときに両方を読むと食い違って見える。

### 申告

サイクル1 の申告7件は、修正後の本文でもそのまま当てはまる。今回の修正で新しく AI が決めたことは無い(導入後の確認手順の置き場所は、所有者の指示と要件7-5・7-6 で決まっており、他の選択肢が無い)。

### 指摘

| ID | レベル | 該当箇所 | 内容 | 直し方の案 |
|---|---|---|---|---|
| D2-1-1 | 低 | design.md Modified Files の監査手順.md の行、Migration Strategy の 1 と 3 | 要件7-6 は「1回だけ行う**作業**の手順」を運用文書に書かないとしているが、design は「1回だけ行う**確認**の手順は書かない」と、範囲を確認に狭めて書いている。Migration Strategy の 1(導入の前に、予約の無い開いている PR の一覧を所有者に示す)と 3(マージ後に両方の見直しを手動で1回ずつ動かす)、およびサイクル1 の D1-1-4(導入の PR で承認後に予約が外れたら手で予約し直す)は、確認ではない1回きりの作業だが、誰が行い、手順をどこに書くかが design に無い(置き場所が書かれているのは 4 だけ)。文面だけを読むと、3 の手順を監査手順.md に書いても design には反しないように読める。tasks.md は 6.2 でこれらを導入の PR の本文に入れており、要件7-6 も tasks と実装の判定の基準になるため、実装への影響は無い | Modified Files の記述を要件7-6 と同じ「1回だけ行う作業の手順は書かない」に揃える。Migration Strategy の 1 と 3 に、手順の置き場所(導入の PR の本文)と行う者を書く |

### 前の段階への指摘

なし。

- 往復: 1回目 / 高0 中0 低1
- 往復: 1回で収束 / 未解決: 0件
