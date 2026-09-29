# tasks レビュー記録: audit-inventory-metrics

## サイクル1 往復1(2026-09-29)

tasks.md を requirements.md(承認済み)・design.md(承認済み)・Issue #415・research.md・requirements / design の記録と response・`.kiro/settings/templates/specs/tasks.md`・実ファイル(`dependabot-auto-merge.yaml` `mutation-report.yaml` `audit-weekly.yaml` `ci.yaml` `guardrails.yaml` `terraform-plan.yaml` `dependabot.yml` `docker/terraform/Dockerfile` `compose.yaml` `record-mutation-metrics.sh` `check-audit-scan-freshness.sh` `check-audit-dependabot-stuck.sh` `check-spec-backing.sh` `tests/test-check-audit-scan-freshness.sh` `tests/test-record-mutation-metrics.sh` `監査手順.md` `ワークフロー設計.md` `README.md` `steering/tech.md` `.claude/skills/kiro-impl/SKILL.md` `.claude/skills/ship/SKILL.md`)に照らして審査した。

確かめた点。

- 要件カバレッジ: requirements の受入基準 1.1〜7.3(全46項目)が、いずれも1つ以上のタスクの `_Requirements:` に現れる。requirements に無い番号を参照するタスクは無い
- design カバレッジ: File Structure Plan の新規ファイル(設定1・スクリプト4・テスト4・ワークフロー1・`requirements.txt`)と Modified Files の各項目が、1.1〜6.2 のいずれかで扱われている。Security Considerations の「表に入れる前に `|` と改行を取り除く」(2.1)、design の記録で tasks に委ねられた点(D1-1-3 のラベルの作成を台帳の作成に付随する操作とする、D1-1-4 のページ送り、D1-2-1 の成果物にファイルが無いときの文言、D2-1-2 の読み取れない差分、D2-1-3 の列挙の上限、D2-1-4 の manifest list の digest、D2-1-6 の exit 2 のときに残りのPRを続けること)、requirements の記録で委ねられた点(R1-1-6 の steering と `dependabot.yml` のコメント、R2-1-2 のマージ後の手動実行、R2-1-3 の `retention-days` の確認、R3-1-3 のコメントの重複防止と手順書の対処)が本文に落ちている。research.md の `tag_pattern`(D2-1-5)は既に design と同じ値になっている
- `_Boundary:` はいずれも File Structure Plan の範囲に収まる。`(P)` の5件(1.2・1.3・3.1・3.4・6.2)は、同じ群の他のタスクと触るファイルが重ならない。`_Depends:` の6件は参照先が実際に前提になる(2.1 は 1.3 が作る `requirements.txt` と `FROM` 行を読む。3.2 は 1.1 の関数に置き換える。3.3 は 3.1・3.2 の成果を組み込む。5 は 1.2 の引数と 2.4 のワークフロー名を使う)
- 完了条件の4項目: 冒頭に4項目が書かれ、verify の置き換え(既存の verify Skill の対象外)に理由がある。置き換え先(alpine コンテナでの同梱テスト、shellcheck v0.11.0、actionlint 1.7.12)は `guardrails.yaml` 43・53行と同じ版で、1.3 は `/verify-terraform` を残している
- スコープ: requirements の Out of scope(良し悪しの判定、Trivy の自動化、週次監査の判定基準の変更、`/usage`)と design の Non-Goals に当たる作業はタスクに無い。Task 5 が週次監査に加えるのは要件5-4 が定めた鮮度確認だけで、判定基準を変えない
- 実ファイルとの整合: `run_check` は追加の引数をそのまま渡す(`audit-weekly.yaml` 164行)ため Task 5 の3つ目の引数は通る。`check-audit-scan-freshness.sh` の既存テストは第3引数を渡していない(75行)ため、1.2 の「省略したときは今の文面のまま」で既存の検査が壊れない。`docker compose build terraform`(1.3)の service 名は `compose.yaml` 63行と一致する。`check-spec-backing.sh` はタスクのチェック状態を見ない(承認フラグと必須ファイルとプレースホルダだけ)ため、7.2 が未完のままでも実装のPRの size-check は通る。`dependabot-auto-merge.yaml` の既存 job の `if` は `github.event.pull_request` を見る(37〜39行)ため、4.2 の「起動のイベントの種類で job を分ける」は必要で正しい。`record-metrics` は既に checkout と `issues: write` を持ち(`mutation-report.yaml` 142〜151行)、3.3 で足すのは `actions: read` と mode の受け渡しだけになる

### 申告

**1. 自動マージのワークフローの両方の job で、判定の前に `test-check-release-age.sh` を流し、失敗したら予約せずに失敗で終える** — tasks.md 4.2

- Issue の記載: なし
- 決めたこと: design には無い自己テストのステップを、PR のイベントの job と1日1回の見直しの job の両方に置く。既存の監査のワークフローと同じ形
- 他にありえた選択肢: 自己テストは guardrails(PR のとき)に任せ、自動マージのワークフローでは判定だけを行う。見直しの job だけで流す
- 外れていた場合: テストが落ちる状態(ランナーの環境の変化、テストの書き誤り)になると、tflint 以外を含む Dependabot の全PRで予約が付かなくなる。この job は必須チェックではなく PR は緑のままのため、週次監査の滞留検知(`check-audit-dependabot-stuck.sh` は失敗の結論だけを数える)に掛からず、docker レーンの更新が止まったことに誰も気づかない。同じことは design が決めた「exit 2 で予約せずに失敗」でも起きるため、テストの追加で新しく増える経路は「テスト自体の失敗」の分に限られる。作り直しにはならない

**2. マージ後の確認を 7.2 として tasks に置き、7.1 の完了条件に PR の作成(所有者の承認待ち)を含める** — tasks.md 7.1・7.2

- Issue の記載: なし(requirements の Out of scope が「実装のタスクのマージ後の確認で扱う」と定め、R2-1-2 の response が「bot の側で行う確認として書く」とした)
- 決めたこと: 出荷(PR の作成)を 7.1 の完了条件に入れ、マージ後の4つの確認(棚卸しの手動実行、mutation の手動の全件、見直しの job の手動実行、次の月曜の週次監査と tflint のPR)を 7.2 にする。tflint の更新PRが届かなければ確認待ちとして #415 に記録する
- 他にありえた選択肢: 7.2 を tasks から外し、マージ後の手順を PR 本文か #415 のコメントに書いて所有者に依頼する。7.2 を所有者が行う作業として書く
- 外れていた場合: `/kiro-impl` の自律実行は 7.2 をマージ前に起動するため、実行できずにブロックされる(指摘 T1-1-1)。マージ後の手動実行が最初の月曜に間に合わないと、週次監査が「成功した実行が存在しません」の逸脱を1回出す(R1-3-1 で記録済み。監査手順の既存の対処で復旧できる)。作り直しにはならない

**3. 今のリポジトリの宣言が全て読めることの検査を、月1回の実行の自己テストから外し、環境変数で有効にしたときだけ動かす** — tasks.md 2.1・2.4・7.1

- Issue の記載: なし
- 決めたこと: design の Testing Strategy と Decision(「宣言が1件も読めない対象があれば、テストが落ちる」)は、この検査を自己テストの一部として月1回の実行でも流す形に読める。tasks は、出荷前(7.1)だけ有効にし、月1回の実行では無効にする。理由は、後で宣言の書き方が変わったときに、実行を赤にせず「読み取れず」の欄つきで表を届けるため(要件2-6)
- 他にありえた選択肢: design どおり月1回の実行でも流す(宣言の書き方が変わった月は実行が赤になり、35日後に週次監査の逸脱で届く。その月の表は届かない)
- 外れていた場合: 宣言の書き方が変わっても CI では検知されず(guardrails は同梱テストを個別に選んで流しており、このテストは含まれない)、翌月の表の「読み取れず」で所有者が知る。要件2-6 が定める動きのため、影響は小さい

**4. tflint の行が差分にあるのにタグや digest を読み取れないときは、PR にコメントせず、終了コード 2(予約せずに失敗)にする** — tasks.md 4.1・4.2

- Issue の記載: なし
- 決めたこと: D2-1-2 の response は「`notify`(理由「差分を読み取れない」)にする」と予定していたが、tasks は design の「判定できなかった = exit 2」に寄せた。所有者へのコメントは無く、PR のイベントの job と見直しの job が失敗で終わる(翌日も見直す)
- 他にありえた選択肢: response の予定どおり `notify` にして所有者にメンションする
- 外れていた場合: 該当する tflint の更新PRは、緑のまま予約されずに残り、失敗の通知は bot にしか届かない。所有者が知るのは、棚卸しの表で tflint の使っている版が最新から遅れ続けることから。Dependabot が `FROM` 行の書き方を変えない限り起きない。作り直しにはならない(条件分岐1つ)

### 指摘

| ID | レベル | 該当箇所 | 内容 | 直し方の案 |
|---|---|---|---|---|
| T1-1-1 | 低 | tasks.md 7.2 | 7.2 はマージ後にしか実行できないが、`/kiro-impl` の自律実行は tasks.md の未完のサブタスクを順に起動する(`kiro-impl/SKILL.md` Step 2・3)。7.1 の直後に 7.2 の実装役が起動され、マージされていないため BLOCKED になり、デバッグ役を経て `_Blocked:` が付く。誰が(bot)いつ(マージ後、最初の月曜より前)どう起動するか(`/kiro-impl audit-inventory-metrics 7.2` の手動モード)が本文に無い。実装には影響しない | 7.2 の detail に「自律実行の対象外。マージ後に所有者の指示で手動モードで実行する」と書くか、あらかじめ `_Blocked: マージ後に実行_` を付けて自律実行に飛ばさせる。あわせて、7.2 の結果を tasks.md に `[x]` として残すには main への別PR(文書のみ)が要ることを添える |
| T1-1-2 | 低 | tasks.md 4.1 のテストの一覧 | `pulls/{n}/files` の応答は、差分の大きいファイルで `patch` を持たないことがある(本審査では外部を確かめられないため、実装時に公式ドキュメントで確認する)。npm レーンの PR は `pnpm-lock.yaml` の差分が大きい。実装が `patch` の無い要素を「差分を読み取れない」として exit 2 に倒すと、tflint 以外の PR の予約が止まる(申告1と同じく、緑のまま滞留検知に掛からない)。テストの一覧の「tflint 以外は reserve」は偽の差分が `patch` を持つ形で書かれると見込まれ、この形を検査しない | テストの一覧に「`patch` の無いファイルを含む差分でも、tflint の行が無ければ `reserve` になること(`patch` の有無は tflint の行を含むファイルだけで見る)」を足す |
| T1-1-3 | 低 | tasks.md 6.1 ワークフロー設計の残余リスク | 2.2 に足す残余リスクが「1日1回の見直しが止まったとき」だけになっている。design が決めた「exit 2 で予約せずに失敗」と 4.2 の自己テスト(申告1)により、判定の側が壊れたときは tflint 以外を含む Dependabot の全PRで予約が付かず、PR は緑のため滞留検知に掛からない。この経路が残余リスクに書かれない。実装には影響しない | 2.2 の記述を「判定(自己テストを含む)が失敗すると Dependabot の全PRの予約が止まり、緑のため滞留検知に掛からない。見直しの job の失敗の通知は bot にしか届かない」まで広げる |
| T1-1-4 | 低 | tasks.md 7.2 | design の Testing Strategy(Integration)にある「pip のレーンが設定のエラー無く動くこと(Insights の Dependabot のログ)」と「tflint が docker のまとめPRとは別のPRになること」が 7.2 に無い。pip のレーンの設定が誤っていると checkov の更新PRが一度も届かず、気づくのは棚卸しの表で checkov の版が遅れ続けることからになる | 7.2 に「マージ後の最初の月曜(Dependabot の実行)の後に、Insights の Dependabot のログで pip のレーンにエラーが無いことを確かめる」を足す。tflint の別PRの確認は「届いていなければ確認待ち」の項に含める |
| T1-1-5 | 低 | tasks.md 1.3 完了の観測条件 | 要件4-4(更新PRで terraform の静的検査が走る)は `terraform-plan.yaml` の paths-filter(41行)で変更なしに成り立つが、観測する場面がタスクに無い。実装のPR自体が `docker/terraform/**` を変えるため、そのPRで `terraform-static` が実行されることが観測になる | 1.3 か 7.1 の観測条件に「実装のPRで `terraform-static` が実行され、新しい Dockerfile で tflint と checkov が動くこと」を足す |
| T1-1-6 | 低 | tasks.md 6.1 README の項 | 「変えるワークフロー5本(audit-inventory・…)」のうち audit-inventory は新規で、「変える」に当たらない。意味は変わらない | 「新しい1本と変える4本」に直す |

### 前の段階への指摘

新たな指摘は無い。design で tasks に委ねられた点は、D2-1-1(Out of Boundary の文言と `recheck` の対象の食い違い)を除いて本文に落ちている。D2-1-1 は design 本文の文言の問題であり、tasks 4.2 は design の本文(予約されていない Dependabot の PR を全部列挙する)に従っている。

- 往復: 1回目 / 高0 中0 低6
- 往復: 1回で収束 / 未解決: 0件
