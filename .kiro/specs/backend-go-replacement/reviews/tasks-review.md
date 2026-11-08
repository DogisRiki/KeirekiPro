# tasks のレビューの記録

## サイクル1 往復1(2026-11-08)

### 審査の範囲

範囲: 全体

### 申告

**1. API の仕様書 `backend/api/openapi.yaml` を PR 2-1 に入れず、作業フォルダの未追跡のファイルのまま PR 2-2 まで持ち越す** — tasks.md タスク1.10、タスク2.2

- Issue の記載: あり。「API の仕様書(OpenAPI)を先に書き」「API の仕様書は、設計を書く前に今の Java 版から作る」。どの PR で main に入れるかは書いていない
- 決めたこと: PR 2-1 には spec の文書だけを入れ、`backend/api/openapi.yaml` は入れない。PR 2-2 で「作業フォルダにある」ファイルを入れる
- 他にありえた選択肢: 2-1 で `backend/api/**` を `backend_go` の見分けから外して仕様書を 2-1 に入れる。仕様書を退避用のブランチに push しておく。`.kiro/specs/` の下に写しを置く
- 外れていた場合: PR 2-1 のマージ後に新しいブランチ(会話も新しい)で大タスク2を始めるので、作業フォルダや worktree が片付けられると、設計の前に作った50の操作の仕様書が失われ、Java 版から作り直すことになる(指摘 T1-1-2)

**2. `.testcoverage.yml` の除外の追加を、書き方の検知ではなく「所有者の承認があれば通るゲート隣接ファイル」の扱いで止める** — tasks.md タスク1.9

- Issue の記載: あり。「今と同じ種類の自動品質チェックを、Go側にそろえてから切り替える」
- 決めたこと: `check-escape-hatches.sh` に `t.Skip` 系と `//nolint` の追加の検知を足し、`.testcoverage.yml` は除外の行の形を見ずに、ファイルの変更そのものを所有者の承認が無ければ止める
- 他にありえた選択肢: `.testcoverage.yml` の `exclude` の追加の行を検知して、承認の有無によらず赤にする(Java 版の jacoco の除外の扱いと同じ形)
- 外れていた場合: 所有者が PR を承認するときに `.testcoverage.yml` の差分を読み落とすと、除外が増えても止まらない。直すときは `check-escape-hatches.sh` を直す PR(所有者の承認が要る)がもう1つ要る

**3. 比べる検査のコードを `make lint` の対象に入れる(`run.build-tags: [compat]`)** — tasks.md タスク2.3

- Issue の記載: なし
- 決めたこと: `.golangci.yml` の `run.build-tags` に `compat` を書き、`backend/compat/` の下のコードも静的な検査と書式の検査の対象にする。`make build` も `backend/compat/` があるときに `-tags compat` で組み立てる
- 他にありえた選択肢: 比べる検査のコードは `make check` の対象から外し、`make compat` を動かすときだけ組み立てる
- 外れていた場合: 外れても手戻りは小さい。`.golangci.yml` の1行を消すだけで戻せる。入れないと、比べる検査のコードの書式と静的な検査が通らないまま main に入りうる

**4. テストを省略可能な印(`- [ ]*`)にしたタスク**: 無い

### 指摘

| ID | レベル | 該当箇所 | 内容 | 直し方の案 |
|---|---|---|---|---|
| T1-1-1 | 中 | tasks.md タスク6.1「完了の確かめ方」「受入基準とテストの対応」、タスク11.1「完了の確かめ方」「受入基準とテストの対応」 | 2つのタスクは、要件5.1 と要件6.2 を「PR の CI の terraform-plan の差分」で確かめると書く。しかし、PR で動く `.github/workflows/terraform-plan.yaml` は `terraform fmt -check`、`terraform init -backend=false` と `validate`、tflint、checkov の静的な検査だけで、`terraform plan` を動かさない。`terraform/CLAUDE.md` も「PRで動くワークフローはAWSに接続しない。本番の状態との差分(plan)は、承認が通ったあとに `terraform-apply.yaml` が適用の直前に出す」と決めている。そのため、ここに書いた確かめ方は実装のときに実行できず、要件5.1(Java 版が読む値を変えない)と要件6.2 の確かめが無いままタスクが完了になる | 確かめ方を、(1) `git diff origin/main -- terraform/` の差分が、design.md の「本番の設定の値の変わり方」の表のその段階の列の値だけであること(6.1 は環境変数 `KEIREKIPRO_ENV` の追加と `redis-username` のキーの追加だけ、11.1 は表の段階6の列だけ)、(2) 所有者が `terraform-apply.yaml` を動かしたときに適用の直前に出る plan の差分が同じ資源と値だけであることを、所有者が apply の前に確かめ、runbook.md(7.3)か PR の本文に、期待する plan の差分(変わる資源の名前と属性)を書いておく、の2つに替える。「受入基準とテストの対応」の行も同じ形に直す |
| T1-1-2 | 中 | tasks.md タスク1.10(「`backend/api/openapi.yaml` は入れない」)、タスク2.2(「作業フォルダにある `backend/api/openapi.yaml` をこの PR に入れ」)、実装のメモ「PR の分け方と進め方」 | `backend/api/openapi.yaml` は、今の作業フォルダに git の管理外(未追跡)のファイルとしてだけある。1.10 は PR 2-1 に入れないと決め、2.2 は PR 2-2 で「作業フォルダにある」ファイルを入れると書く。しかし、実装のメモのとおり大タスク2は、PR 2-1 が main に入ったあと、所有者が `/kiro-impl` を打った別の会話で、main から作る新しいブランチで進める。その間に worktree が片付けられるか、別の作業フォルダで始めると、仕様書の唯一の写しが失われる。失われると、2.2 で気づき、Java 版の Controller と型から50の操作の仕様書を作り直すことになる(research.md 「Java 版から作った API の仕様書」の作業のやり直し)。2-1 に入れられないのは、1.5 の新しい見分け `backend_go` が `backend/api/**` に当たり、`go.mod` の無いまま `backend-go` の仕事が動いて失敗するためで、入れない判断自体は正しい | 1.10 に、仕様書を失わないための置き方を1つ決めて書く。たとえば、(a) PR 2-1 を出すときに `backend/api/openapi.yaml` だけを別のブランチ(例: `spec/backend-go-replacement-openapi`)にコミットして `origin` に push し(PR は作らない)、2.2 で `git show <ブランチ>:backend/api/openapi.yaml` から取り出す、(b) 2-1 の PR に `.kiro/specs/backend-go-replacement/openapi.yaml` として写しを入れ、2.2 で `backend/api/` に移す(`.kiro/specs/` は `backend_go` の見分けに当たらない)、のどちらか。2.2 の「作業フォルダにある」を、決めた置き場から取り出す書き方に直す |
| T1-1-3 | 低 | tasks.md タスク1.9 `_対象の部品: Makefile、.golangci.yml と .testcoverage.yml と .gremlins.yaml_` | 1.9 が直すのは `check-dependency-additions.sh`、`CODEOWNERS`、`check-escape-hatches.sh` であり、design.md ではこれらは「所有者に提案するゲート設定の変更」の表にあって、部品「Makefile」「.golangci.yml と .testcoverage.yml と .gremlins.yaml」の中身を作るのは 2.3 である。並行の衝突は無い(1.4、1.6 と触るファイルが別)が、部品の名前が実際に触るファイルと合わない | `_対象の部品:_` を「所有者に提案するゲート設定の変更(`check-dependency-additions.sh`、`CODEOWNERS`、`check-escape-hatches.sh`)」のように、触るファイルが分かる書き方にする |
| T1-1-4 | 低 | tasks.md タスク7.2「そのあとの4つのステップは変えない」 | 今の `backend-deploy.yaml` は、イメージの組み立てと送信のあとに、タスク定義の取得、イメージの差し替え、登録、desired count の調整、サービスの更新、安定の待ち、確認の7つのステップがある。design.md の「4つのステップ」は、送信・登録・更新・待ちのまとめ方であり、ワークフローのステップの数ではない。実装のときに「4つ」を数えようとすると迷う | 「イメージの組み立てと送信のステップより後のステップは変えない」のように、数でなく範囲で書く |
| T1-1-5 | 低 | tasks.md タスク3.10 `TestCoverage_Operations`、タスク2.12 progress.md の「まとまりの表」 | 3.10 の確認は「`progress.md` で完了と記した操作」を数えるが、2.12 が作る progress.md のまとまりの表は、まとまりごとの子の Issue と spec と状態の列だけで、操作の一覧の列が無い。まとまりから操作への対応(design.md の「まとまりの分け方と順番」の表の「認証 13」などの数)を、検査がどこから読むかが決まっていない | 3.10 に、対応の読み方を1つ書く。たとえば、`openapi.yaml` の各操作の `tags` にまとまりの名前を書いて検査が読む、または progress.md のまとまりの表に操作の一覧の列を足す |
| T1-1-6 | 低 | tasks.md タスク1.2 | 今の `check-verify-before-stop.sh` は `backend/` の下のどのファイルが変わっても backend の記録を求める。1.2 の分け方では、`backend_java` にも `backend_go` にも当たらない `backend/` の下のファイル(`backend/compat/scenarios/*.yaml`、`backend/compat/fixtures/**`、`backend/assets/**`、`backend/CLAUDE.md`)が変わっても、どの記録も求めなくなる。design.md の「CI の仕事」の見分けと同じ形なので design どおりだが、筋書きと初めのデータだけを変えた会話で、作業を終えるときの確認が効かなくなる | 1.2 に、どちらにも当たらない `backend/` の下の変更の扱いを1行で決める(たとえば「どちらにも当たらない `backend/` の下の変更は Go 版の記録を求める」) |
| T1-1-7 | 低 | tasks.md タスク13.4、タスク14.4 | 13.4(PR 6-4)と 14.4(PR 6-5)は所有者の承認が要る PR だが、ほかの承認が要る PR のタスク(1.10、2.13、5.6、7.4、10.9)と違い、「完了の確かめ方」に「承認が要る理由」と「main に入れたときに本番で起きること」の2つの欄があることを書いていない。実装のメモの「PR の本文」に共通の決まりがあるので、欄が抜けることはないが、タスクごとの確かめ方がそろっていない | 13.4 と 14.4 の「完了の確かめ方」にも2つの欄があることを足す |

### 前の段階への指摘

| ID | 対象 | 該当箇所 | 内容 |
|---|---|---|---|
| T1-1-8 | design | 「移行」の節の「段階ごとの PR」の表の 4-1 と、「段階6の削除と書き換え」の表の 6-2(所有者の承認「要る」「PR の承認と terraform apply」) | 4-1 と 6-2 は terraform だけを変える PR だが、`.github/CODEOWNERS` の守る対象は `terraform/.checkov.baseline` だけで、`terraform/main.tf` と `terraform/modules/` は含まれない。そのため、この2つの PR は所有者の承認なしに自動マージされる。本番は所有者の `terraform apply` まで変わらないので利用者への影響は無いが、表の「要る」はこの仕組みでは機械で強制されない。tasks の 6.1 と 11.1 は「所有者に `terraform apply` を頼む」と書いており、承認を待つ手順は無いので、tasks は仕組みに合っている。design の表の書き方を所有者に確かめてもらうのがよい |

- 往復: 1回目 / 高0 中2 低5

## サイクル2 往復1(2026-11-08)

### 審査の範囲

範囲: 差分

- tasks.md タスク6.1、11.1、7.3、7.1 の `_保留:_`、12.1 の `_保留:_`、実装のメモ「`terraform-apply.yaml` の実行の確かめ方」、`.github/workflows/terraform-apply.yaml`: T1-1-1 と T1-1-8 の直しで、`terraform plan` を PR で動かさない前提と、`plan_only` での2回の起動に替わった。`terraform-apply.yaml` を読み、入力 `plan_only`(boolean)、ステップ名「Terraform Plan (差分の事前表示)」「Terraform Apply」(`if: ${{ !inputs.plan_only }}`)、実行の概要の文「本番には適用していません。」がそのとおりにあることを確かめた。design.md 「段階ごとの PR」の 4-1 と 6-2 の箇条(2回の起動)、「runbook.md」の操作1、「段階6の削除と書き換え」の表の 6-2(「`terraform-apply.yaml` の2回の起動」)とも合っている
- tasks.md タスク6.1 の「変わるはずのリソースと値」、`terraform/modules/ecs/main.tf`、`terraform/main.tf`、`.github/workflows/backend-deploy.yaml`: `aws_ecs_service` が `ignore_changes = [task_definition]` を持ち、`backend-deploy.yaml` が family の名前で最新のタスク定義を読むので、design.md 「段階4の本番の設定の変更」の「そのあとの最初の出荷で新しいタスク定義を元にする」が成り立つことを確かめた。6.1 の2つの値(`KEIREKIPRO_ENV` の追加、`redis-username` の追加)は「本番の設定の値の変わり方」の表の段階4の列と合う
- tasks.md タスク1.10、2.2、4.1、13.4、design.md 「ファイルの構成」の `backend/api/openapi.yaml`、`.github/scripts/check-spec-backing.sh`、`.claude/hooks/restore-after-compact.sh`: T1-1-2 の直し(b)で、仕様書を PR 2-1 では `.kiro/specs/backend-go-replacement/openapi.yaml` に置き、2.2 で `git mv` する形になった。`.kiro/specs/` は design の見分け `backend_go` のどの形にも当たらず、spec のフォルダを読む CI のスクリプトとフックは spec.json と reviews/ だけを見るので、余分な yaml があっても壊れない。4.1 が差し込む `backend/api/openapi.yaml` は 2-2 のあとにあるので合う。design.md は一時の置き場を書いていないが、ファイルの構成は最終の形を書く節であり、食い違いではない
- tasks.md タスク1.5(見分け)、1.2、1.4、10.5、design.md 「CI の仕事」453〜461行目と「段階6の削除と書き換え」758〜765行目: design に足された `backend/assets/**` と `backend/go.mod` があることの条件とマイグレーションのファイルの形が、1.5 の本文と、10.5 の「`backend/db/migrations/**` に替える」「`backend/go.mod` の条件を消す」に反映されている。1.4 の判定のスクリプトは見分けの値を受け取るだけなので影響なし。1.2 は見分けを「同じ形」で使うが、`backend/go.mod` の条件を含むかが読めない(指摘 T2-1-1)。10.5 が消す `go.mod` の条件は design の 6-1 の一覧に無い(前の段階への指摘 T2-1-2)
- tasks.md タスク8.1、8.2、3.9、design.md 「cross」593〜604行目、「perf」612行目、「テストの方針」927行目: 「12の操作」を「11の操作」に直した。design の perf の操作を数えると、ログイン、トークンの更新、利用者の情報の取得、経歴書の一覧・取得・基本情報の保存・職歴の追加、PDF の出力、Markdown の出力、バックアップの書き出し・戻しの11で合う。cross の10も design の箇条と合う
- tasks.md タスク5.3、10.7、2.1、2.11、3.2、3.3、design.md 「Dependabot と公開の時刻の検査と脆弱性の直し」499〜501行目: 5.3 の「4つの Dockerfile」(`docker/backend-go/` の `Dockerfile` と `Dockerfile.prod`、fakeaws と fakeoidc の `Dockerfile`)は、2.1 と 2.11 と 3.2 と 3.3 が作る `golang` のイメージを使う Dockerfile と合う。10.7 の「`docker/backend/` の2つの Dockerfile」は 6-1 の名前の戻しのあとの形で合う
- tasks.md 実装のメモ「design の審査で残った記録」の D5-1-1、タスク10.7、design-review.md サイクル5 往復1の D5-1-1、design-response.md: D5-1-1 は低・記録のみで、design の本文は `backend-vuln-fix.yaml` の Java 版の仕事を 6-1 と 6-4 のどちらで消すかを名指ししていない。10.7 は 6-1 で消すと決めており、D5-1-1 の直し方の案と同じ向きで、design の本文と食い違わない
- tasks.md タスク14.3、14.4、`.github/CODEOWNERS`、リポジトリ全体の `kiro-discovery|kiro-validate-design|kiro-spec-batch` の検索: 14.3 に足した `kiro-spec-design` と `kiro-spec-init` の `SKILL.md` は、`.kiro/specs/` と消す3つのスキル自身を除いて、この3つを名指す残りのファイル(ルートの `CLAUDE.md` と合わせて3つ)と一致する。14.4 の「スキルを消すゲート設定の変更を含む」は、CODEOWNERS が `/.claude/` を守ることと合う
- tasks.md タスク7.3、10.1、requirements.md 要件5の受入基準3、要件6の受入基準1: 「要件5の受入基準3で決めた出荷の時間帯」(平日 08:00〜20:00)と「要件6の受入基準1で決めた尋ね方」(たった日数と不具合を示す)が、受入基準の文に実際にあることを確かめた
- tasks.md タスク6.1 の `_要件:_`(7.3 を外した)と要件7の受入基準3: 7.3 は「所有者の承認が要る PR を作ったとき」の決まりで、PR 4-1 は承認が要らない PR になったので外して正しい。7.3 は 1.10、2.12、2.13、5.6、7.4、10.9、13.4、14.4 の `_要件:_` に残る
- tasks.md タスク2.4、2.6、2.8、2.12、3.1、3.4、3.5、3.10、7.1、7.2、10、10.3、実装のメモの箇条の分け方: 書き方の点検で主語と語の説明を足し、長い文を分けた差分。前後の文と design.md の同じ部品(「migrate」「config」「httpapi」「compat harness」「changed-behaviors.yaml」「backend-deploy.yaml と release.yaml」)を読み、中身が変わっていないことを確かめた。影響なし

### 申告

(今回の差分で新しく申告するものはない。サイクル1の申告1は、T1-1-2 の修正で「PR 2-1 に `.kiro/specs/backend-go-replacement/openapi.yaml` として入れ、2.2 で `backend/api/` に移す」形に変わり、外れた場合の影響(仕様書を失う)は無くなった)

### 指摘

| ID | レベル | 該当箇所 | 内容 | 直し方の案 |
|---|---|---|---|---|
| T2-1-1 | 低 | tasks.md タスク1.2(「design.md の「CI の仕事」の見分け `backend_java` と `backend_go` と同じ形で分け」「マイグレーションのファイルが変わったときは、両方の記録を求める」)と、その「受入基準とテストの対応」の3つの場合 | 1.5 の直しで、見分け `backend_go` には「検査するコミットに `backend/go.mod` があるときだけ当たる」条件が入った。1.2 のフックは見分けを「同じ形」で使うが、この条件も同じにするのかが読めず、テストの場合にも無い。条件を入れないと、PR 2-1 が main に入ってから PR 2-2 が入るまでのあいだに、作業フォルダでマイグレーションのファイルを変えた会話で、フックが Go 版の記録を求める。そのとき `backend/go.mod` も `Makefile` も compose のサービス `backend-go`(2.1 で足す)も無いので、`run-check.sh backend-go make check` は動かず、記録を書けない。この spec の PR 2-2 の会話では 2.1 が最初に `go.mod` と compose のサービスを作るので当たらず、当たるのはその間にマイグレーションを変える別の作業だけである | 1.2 に「`backend/go.mod` が作業フォルダに無いときは、見分け `backend_go` と同じく、Go 版の記録を求めない」の1文を足し、「受入基準とテストの対応」に「`backend/go.mod` が無いときはマイグレーションの変更に Java 版の記録だけを求める」の場合を足す |

### 前の段階への指摘

| ID | 対象 | 該当箇所 | 内容 |
|---|---|---|---|
| T2-1-2 | design | 「段階6の削除と書き換え」の 6-1 の「段階2で足した移行のための条件を、次の5つのとおりに消すか元の1つの形に戻す」の一覧(758〜765行目)、「CI の仕事」の `backend_go` の `backend/go.mod` の条件の段(459行目)と、`check-verify-before-stop.sh` の見分け方の箇条(96行目) | design に足した「検査するコミットに `backend/go.mod` があるときだけ当たる」条件は、段階2で足す移行のための条件だが、6-1 で消す5つの一覧に無く、`backend_compat` の見分けのように「6-1 で消す」とも書いていない。tasks の 10.5 は 6-1 でこの条件を消すと書いており、tasks のほうが design より先に決めている。食い違いではないが、design の一覧に6つ目として足せば、10.5 の根拠が design に揃う。また、96行目の「見分け方は …`backend_java` と `backend_go` と同じにする」が、この条件を含むかも design に書くと、tasks の 1.2(指摘 T2-1-1)の読み方が1つに決まる |

- 往復: 1回で収束 / 未解決: 0件
