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

## サイクル3 往復1(2026-11-09)

### 審査の範囲

範囲: 差分

- tasks.md タスク3.5(227〜229行目。CB-001 から CB-009 の9つ、記録だけの項目、`match` の照らし方、足したテスト)、design.md 「変えた動きの一覧の形」の `match` の説明(842行目)と表(846〜856行目)と CB-005〜CB-009 の箇条(862〜866行目)、「compat harness」の比べるヘッダの箇条(563行目)、「テストの方針」の比べる検査の土台(944行目)、「安全」の1つ目の箇条(959行目): 3.5 の項目の数、記録だけにする4つの項目、`operation: "*"` と `status` と `target: header` の `path` の読み方が design と合うかを照らした。合っている。記録だけの項目の確かめと書き方は指摘 T3-1-1
- tasks.md タスク3.4(`TestCompareHeaders_OnlySelected`)、タスク8.3、13.x の `changed-behaviors.yaml` を名指す行: 3.5 の項目の数が変わったことで、ヘッダの比べ方と一覧を示す・移す手順が変わるかを確かめた。どれも項目の数を書いていないので、影響なし
- tasks.md 大タスク1と2の箱の [x] と、2.1〜2.13 の `_保留:_` の削除: 実装を進めた印の差分で、タスクの本文と確かめ方は変わっていない。影響なし
- tasks.md 実装のメモ「所有者に置いてもらう」「`.github/` の置き場」、`.claude/settings.json` の `Write(.github/**)`、`.github/CLAUDE.md` の scratchpad の決まり、requirements.md 要件7の受入基準5: `.github/` の下の完成版を会話ごとの scratchpad に作る決まりと、会話が途切れたときの続け方を照らした。指摘 T3-1-3
- tasks.md 実装のメモ「Go のモジュールの索引の読み方」、タスク1.7 の本文と「受入基準とテストの対応」、design.md 「Dependabot と公開の時刻の検査と脆弱性の直し」(507行目と509行目)、`.github/scripts/check-release-age.sh`(33行目と206〜208行目)、`.github/scripts/tests/test-check-release-age.sh`(654〜659行目): 索引を区間に分けて同時に読む形と、design の「順に読む」の文と、`toolchain` の行を照らさないことを確かめた。指摘 T3-1-2、前の段階への指摘 T3-1-5、申告2
- tasks.md 実装のメモ「表の形の履歴の BASELINE の行」、タスク2.4、design.md 「migrate」の失敗したとき(343行目)、`backend/internal/platform/migrate/migrate.go`(65行目)と `migrate_test.go`(153行目): BASELINE の行を受け付ける扱いが design の文と合うかを照らした。指摘 T3-1-2、前の段階への指摘 T3-1-6
- tasks.md 実装のメモ「外部のログインの秘密の値の読み方」、タスク2.6、design.md 「config」の環境ごとの値(316〜325行目)と「compat harness」の秘密の値(593行目): `dev` と `test` で外部のログインの秘密の値を Secrets Manager から読む扱いが design の文と合うかを照らした。前の段階への指摘 T3-1-7
- tasks.md 実装のメモ「HTTP の受け口の共通部分」の9つの箇条、design.md 「httpapi」の中間処理の3(367〜373行目)、CB-006〜CB-009、`backend/src/main/java/com/example/keirekipro/presentation/security/config/SecurityConfig.java`(136〜141行目)、`backend/src/main/resources/application-prod.yaml`(3行目)、`backend/internal/httpapi/middleware/csrf.go`(49〜53行目): Cookie `XSRF-TOKEN` の性質を Path=/ だけにする扱いを Java 版と照らした。Java 版は `CookieCsrfTokenRepository` で `Secure` を要求が TLS かで決め、本番は `forward-headers-strategy: none` なので、本番でも `Secure` は付かない。Go 版の Path=/ だけと合う。ほかの箇条も design の文と合う。影響なし
- tasks.md 実装のメモ「Go の検査の外しの検知」、タスク2.3、`backend/.golangci.yml`(6〜8行目、23〜26行目)、`backend/Makefile`(20〜22行目、74〜116行目): gosec が `#nosec` に従わない設定と、設定のファイルを名前で渡すことが入っていることを確かめた。影響なし
- tasks.md 実装のメモ「起動の入口」の gremlins の制約、タスク2.10、2.13: 入口の変異が数えられないことと、PR の CI の `make mutation-diff` の扱いを照らした。申告1
- tasks.md 実装のメモ「depguard の機能のパッケージの規則」、タスク2.3: 規則が広く断ることを、まとまりの spec に任せる扱いを照らした。申告3
- tasks.md 実装のメモ「CodeQL の Go の解析」、タスク2.13 の「完了の確かめ方」: PR 2-2 で確かめることが、2.13 の確かめ方にあるかを照らした。指摘 T3-1-4
- tasks.md 実装のメモのほかの足した箇条(報告の置き場、golangci-lint の版、テストの環境、コードの生成、3つの入口、カバレッジの測り方、BOM と検査の値、testcontainers-go、S3 のパスの形、AWS の部品の版、gosec の G101、ログの形、PDF の部品、本番のイメージ): 前後の文と、名指すタスク(1.5、2.1〜2.11、3.1、3.4、3.8〜3.9)と design の同じ部品の文を読み、タスクの本文と食い違わないことを確かめた。影響なし

### 申告

**1. 起動の入口を `cmd/keirekipro/main.go` に置いたまま、gremlins が入口の変異を数えられないことを受け入れる** — tasks.md 実装のメモ「起動の入口(タスク2.10で分かったこと)」、タスク2.10、2.13

- Issue の記載: あり。「今と同じ種類の自動品質チェックを、Go側にそろえてから切り替える」。入口の置き場所は書いていない
- 決めたこと: 入口を design のとおり `cmd/keirekipro` に置く。gremlins v0.6.0 では、そこの変異がすべて LIVED か NOT COVERED になる。PR の CI の `make mutation-diff` が赤になったら、所有者の判断を受ける
- 他にありえた選択肢: 起動の処理(設定の読み込み、部品のつなぎ、止め方)を、名前が main でない別のパッケージ(例: `internal/app`)に置き、`main.go` には `os.Exit(app.Run(...))` の1行だけを残す。そうすれば、変異のほとんどが数えられるパッケージに入る
- 外れていた場合: PR 2-2 だけでなく、まとまりの spec が機能の受け口を入口につなぐたびに、差分が小さい PR ほど `--threshold-mcover 93` に届かず、`backend-go` が赤になる。そのたびに所有者の判断が要る。あとで別のパッケージに移すと、入口のテストの書き直しが要る

**2. go.mod の `toolchain` の行を、Dependabot の PR の公開の時刻の検査で照らさず、Dependabot がこの行を変えるかを確かめていない** — tasks.md 実装のメモ「Go のモジュールの索引の読み方(タスク1.8で分かったこと)」の最後の2文、タスク1.8、`.github/scripts/check-release-age.sh` 206〜208行目

- Issue の記載: なし(要件3の受入基準1が「公開から72時間たっていない部品を止める検査」を求める)
- 決めたこと: `check-release-age.sh` は `go` と `toolchain` の行を照らさない。`toolchain` の行だけを変える Dependabot の PR は、索引を読まずに予約の判定(reserve)になる(テストの654〜659行目)。Dependabot がこの行を変えるかは、あとに残した
- 他にありえた選択肢: `toolchain` の行の版を、Go の公式の配布の一覧(go.dev の版の一覧)の公開の時刻で照らす。または `toolchain` の行が変わった PR は通知(notify)にする
- 外れていた場合: Dependabot が `toolchain` を上げる PR を作ると、公開から72時間たっていない Go の版が自動でマージされ、CI と本番のイメージの組み立てで使われる。design.md 509行目は、`backend-vuln-fix` が `toolchain` を上げる PR について「公開から72時間たっていなければ公開の時刻の検査で止まる」と書いており、`check-dependency-cooldown.sh` が `toolchain` の行を拾うかも確かめられていない

**3. depguard の規則 `feature` が機能のパッケージから自分の下のパッケージを読むことも断るのを、今は直さず、まとまりの spec で `allow` を足す** — tasks.md 実装のメモ「depguard の機能のパッケージの規則(タスク2.3で分かったこと)」

- Issue の記載: なし
- 決めたこと: PR 2-2 の `.golangci.yml` の規則は広く断ったままにし、機能のパッケージを作るまとまりの spec が、その機能の読み込みの許可を足す
- 他にありえた選択肢: PR 2-2 で、5つのまとまりのパッケージの名前の分の `allow` を先に書く
- 外れていた場合: `.golangci.yml` は承認の対象なので、まとまりの spec の PR ごとに所有者の承認が要る。まとまりの spec がこのメモを読まずに作ると、`make lint` が depguard で落ちてから気づく。手戻りは小さい

**4. テストを省略可能な印(`- [ ]*`)にしたタスク**: 今回の差分には無い

### 指摘

| ID | レベル | 該当箇所 | 内容 | 直し方の案 |
|---|---|---|---|---|
| T3-1-1 | 低 | tasks.md タスク3.5 の本文(「CB-005 の…項目と、CB-007 の…、CB-008 の…、CB-009 の…の3つの項目を、`match` を持たない記録だけの項目にする」)と「受入基準とテストの対応」 | 記録だけの項目は4つだが、本文は4つを並べたあとに「3つの項目」と書くので、CB-005 を数に入れるのかで読み方が2つになる。また、確かめのテストは `TestLoadChangedBehaviors_CB005HasNoMatch` だけで、CB-007〜CB-009 が `match` を持たないことを確かめるテストが無い。どれかに `match` を書いてしまうと、許す範囲が広がっても止まらない。ただし、design ではこの3つの経路と要求を比べる検査が送らないので、実装への影響は小さい | 本文を「CB-005、CB-007、CB-008、CB-009 の4つの項目を、`match` を持たない記録だけの項目にする」と書く。テストを `TestLoadChangedBehaviors_RecordOnlyHaveNoMatch`(4つの項目が `match` を持たない)にする |
| T3-1-2 | 低 | tasks.md タスク1.7 の本文(「73時間前から `since` で順に1度だけ読み」)と、タスク2.4 の本文(「design.md の「migrate」のとおり」)。実装のメモ「Go のモジュールの索引の読み方」「表の形の履歴の BASELINE の行」 | 実装のメモは、1.7 の索引を4時間ずつの区間に分けて約19本を同時に読むことと、2.4 の migrate が BASELINE の行を受け付けることを、design の文と違う扱いとして書いた。一方、2つのタスクの本文はそのまま「順に読む」「design のとおり」と書く。タスクの本文と実装のメモが食い違い、本文だけを読むと今のコードが誤りに見える。2つのタスクは終わっているので、実装は変わらない | 1.7 と 2.4 の本文に「実装のメモの「…」のとおり、…とした」の1文を足す |
| T3-1-3 | 低 | tasks.md 実装のメモ「`.github/` の置き場(タスク1.4で分かったこと)」(「大タスクの最後の小タスクで所有者に置いてもらうまで、同じ会話で進める」) | `.github/` の下のファイルの完成版を、会話ごとの scratchpad に作ると決めた。残りの大タスク5、7、10も `.github/` の下を変える。要件7の受入基準5は、会話が途切れても、リポジトリと GitHub の記録から読み直して続けることを求める。新しい会話は、前の会話の scratchpad の場所を知らないので、前の会話で作った完成版を見つけられず、作り直すことになる。作り直せば済み、実装の中身は変わらない | 大タスクの最初に `.github/` の完成版を作るとき、Claude が scratchpad の絶対パスを `.claude/.state/backend-go-replacement/place-<大タスクの番号>/github-scratchpad.txt` に書き、会話が途切れたら新しい会話でそのパスから読み直す、と1文足す |
| T3-1-4 | 低 | tasks.md タスク2.13「完了の確かめ方」、実装のメモ「CodeQL の Go の解析(タスク1.6で分かったこと)」 | 実装のメモは、`backend/go.mod` を足す PR 2-2 で、CodeQL の `go` の仕事が成功したことを `gh run view` で確かめると決めた。しかし、PR 2-2 を出すタスク2.13 の「完了の確かめ方」は `backend-go` と `backend-test` の成功だけを挙げ、CodeQL の `go` の仕事が無い。2.13 は [x] になっている。CodeQL が必須の検査なら、失敗すれば PR が止まって気づくので、影響は小さい | 2.13 の「完了の確かめ方」に「PR の CI の CodeQL の `go` の仕事が成功する(失敗したら `setup-go` の手順を足す提案を所有者に出す)」を足す |

### 前の段階への指摘

| ID | 対象 | 該当箇所 | 内容 |
|---|---|---|---|
| T3-1-5 | design | 「Dependabot と公開の時刻の検査と脆弱性の直し」の公開の時刻の検査の段落(507行目。「72時間と1時間前から `since` で順に読み」「索引は1回の検査で1度だけ読み」) | タスク1.8 で、index.golang.org は1回の問い合わせに約4秒かかり、順に読むと約10分かかって判定の手順の5分の上限に収まらないと分かった。そのため `lib-gomod-index.sh` は、73時間を4時間ずつの区間に分けて約19本を同時に読む。design の文は「順に読む」のままである。PR の判定の基準は design なので、このスクリプトを直す PR で、design の文と食い違って見える。design の文を、区間に分けて同時に読み、区間の中は順に読む形に直すかを、所有者に確かめてもらう |
| T3-1-6 | design | 「migrate」の失敗したとき(343行目。「記録の版がファイルに無いときは、この部品はエラーを返す」)と、「テストの方針」の migrate(936行目) | Java 版は `baseline-on-migrate: true` と `baseline-version: 0` で動くので、本番の履歴に種類 `BASELINE` で版 `0` の行があるかもしれない。版 `0` のファイルは無いので、design の文のとおりに作ると、Go 版はその行でエラーを返して起動しない。タスク2.4 は BASELINE の行を受け付ける形で作ったが(実装のメモ「表の形の履歴の BASELINE の行」)、design の文は変わっていない。PR 2-2 の判定の基準は design なので、design の失敗したときの文に、BASELINE の行を受け付け、その版以下を適用済みとして扱う一文を足すかを、所有者に確かめてもらう |
| T3-1-7 | design | 「config」の環境ごとの値(325行目。「Go 版は、`dev` と `test` では、秘密の値の代わりに…環境変数…を読む」) | タスク2.6 で、config は `keirekipro/oidc/google` と `keirekipro/oidc/github` を、`dev` と `test` でも Secrets Manager から読むことにした(実装のメモ「外部のログインの秘密の値の読み方」)。Java 版も `dev` でこの2つを localstack から読み、比べる検査も fakeaws に登録する(593行目)ためである。また、`KEIREKIPRO_AWS_ENDPOINT` が無いときの接続先を、`dev` と `test` では `http://localstack:4566` にした。design の325行目は、`dev` と `test` では秘密の値の代わりに環境変数を読むと書き、外部のログインの秘密の値をどこから読むかを書いていない。design の文に、外部のログインの秘密の値は `dev` と `test` でも Secrets Manager から読むことと、接続先の既定を足すかを、所有者に確かめてもらう |

- 往復: 1回で収束 / 未解決: 0件

## サイクル4 往復1(2026-11-09)

### 審査の範囲

範囲: 差分

- tasks.md タスク1.7 の本文と「受入基準とテストの対応」、実装のメモ「Go のモジュールの索引の読み方」、design.md 「Dependabot と公開の時刻の検査と脆弱性の直し」(518行目)、`.github/scripts/tests/test-lib-gomod-index.sh`(195〜201行目、296〜345行目): 1.7 の本文が design の節を名指して「4時間ずつの区間に分けて同時に読み、区間の中は `since` で順に読む」と書くようになった。design の518行目に同じ読み方と理由が書かれ、名指した節の見出しが505行目にあることを確かめた。「1度だけ読み」は design の「索引は1回の検査で1度だけ読み」と合い、テストの「索引を1度だけ読む」の場合もある。実装のメモの「design.md の…にも、この読み方を書いた」も事実と合う。サイクル3の T3-1-2 と T3-1-5 は解消している。影響なし
- tasks.md タスク2.4 の本文と「受入基準とテストの対応」(`TestRun_ValidateOnly_BaselineRow` の追加)、実装のメモ「表の形の履歴の BASELINE の行」、design.md 「migrate」の失敗したとき(354行目)と「テストの方針」の migrate(947行目)、`backend/internal/platform/migrate/migrate_test.go`: 2.4 が design の「migrate」を名指して BASELINE の行を受け付けると書くようになった。design の354行目と947行目に同じ扱いがあり、`migrate_test.go` の150行目に `TestRun_ValidateOnly_BaselineRow` があることを確かめた。サイクル3の T3-1-2 と T3-1-6 は解消している。影響なし
- tasks.md タスク3.5 の本文と「受入基準とテストの対応」、design.md 「変えた動きの一覧の形」(835行目): 記録だけの項目を「CB-005、CB-007、CB-008、CB-009 の4つ」と書くようになり、T3-1-1 の数の読み方の揺れが無くなった。照らし方は design の節を名指して文の位置を前に移しただけで、`operation: "*"`、`status`、`target: header` の読み方は変わっていない。テストは `TestLoadChangedBehaviors_CB005HasNoMatch` のままで、これは T3-1-1 の後半(低)であり、今回の差分では変わっていないので、もう一度出さない
- tasks.md タスク7.1 と 12.x の `_保留:_`(`plan_only` の手順の文を消した)、タスク6.1(349〜355行目)、11.1(515〜521行目)、7.3(378行目)、実装のメモ「`terraform-apply.yaml` の実行の確かめ方」(609行目)、design.md 「runbook.md」の操作1(1022行目): `_保留:_` の行から消した `plan_only` の2回の起動の手順が、6.1 と 11.1 の本文と 7.3 の runbook と design に残っていること、保留の条件(本番に反映したあと)を確かめる手順が609行目の「Terraform Apply」のステップの成功で残っていることを確かめた。手順は失われていない。影響なし
- tasks.md タスク10.3 と design.md 「消す一覧」(1052行目): Java 版と一緒に消えるものの文を分けただけで、並べたものは前と同じである。design の1052行目の並びのうち `docker/backend/Dockerfile` の使われない `COPY` は、10.3 が `docker/backend/` を消すことで扱われる。差分の前からの形で、影響なし
- tasks.md タスク1.1、2.7、3.1、3.7、3.8、3.9、7.2、10.x(`gradle-wrapper` を消すタスク)、実装のメモ「所有者に置いてもらう」「golangci-lint の版」「カバレッジの測り方」「testcontainers-go の使い方」「S3 のパスの形のテスト」「ログの形」「HTTP の受け口の共通部分」の検査するメソッドと経路、「PDF を作る部品」「起動の入口」: 書き方の点検で、主語を足し、長い文と括弧の中の文を分け、語を言い換えた差分。前後の文と、名指す design の部品(「logging」「compat harness」「cross」「perf」「backend-deploy.yaml と release.yaml」「httpapi」)を読み、数・名前・値・条件が前と同じで、中身が変わっていないことを確かめた。影響なし

### 申告

(今回の差分で新しく申告するものはない。差分は、サイクル3の指摘と前の段階への指摘への直しと、書き方の点検の直しであり、新しく決めたことを含まない)

### 指摘

(指摘なし)

### 前の段階への指摘

(なし)

- 往復: 1回で収束 / 未解決: 0件

## サイクル5 往復1(2026-11-10)

### 審査の範囲

範囲: 差分

- tasks.md 冒頭の段落(大タスク15を大タスク4と5の間に置く理由)、タスク5.1 の `_保留:_`、design.md 「移行」の「段階ごとの PR」の表の 2-6(1028行目)と箇条(1038行目): 大タスク15を PR 2-6 に当て、2-5 より先に main に入れる順が design と合うことを確かめた。5.1 の保留の条件が PR 2-6 に替わったので、「5.1 と同じ」を書く 5.2 からのタスクも 2-6 を待つ。影響なし
- tasks.md タスク15.1、design.md 「config」の環境ごとの値(321行目)、「httpapi」の中間処理の順と CORS の処理の5つの箇条(372〜391行目)、「安全」の CORS の箇条(987行目)、`backend/internal/httpapi/server.go`(77〜80行目)、`backend/internal/httpapi/middleware/csrf.go`(25〜45行目)、`backend/internal/platform/config/config.go`(163行目と170行目)、`backend/src/main/java/com/example/keirekipro/presentation/security/config/SecurityConfig.java`(123〜131行目): 15.1 の置き場所、許す送り元、9つのテストの確かめ方を、design と今のコードと Java 版の設定と照らした。指摘 T5-1-2、申告2、前の段階への指摘 T5-1-5
- tasks.md タスク15.2、requirements.md 要件14の受入基準5〜7、design.md 「api-docs」の節(417〜429行目)、「ファイルの構成」の `compose.yaml` と手順の文書(235行目と237行目)、CB-010(893行目)、「compat harness」の使う部品(526行目)、`backend/api/openapi.yaml`(`servers` と `XsrfTokenHeader` を持つ操作)、`backend/compat/harness/match_test.go`(312〜342行目)、`backend/Makefile`(127〜128行目)、`.claude/skills/verify-backend/SKILL.md`(40〜53行目)、`.kiro/specs/backend-go-replacement/progress.md`、`.claude/skills/ship/SKILL.md`(271〜272行目)、`.claude/skills/verify-ui/SKILL.md`(27行目): ブラウザでの2つの確認が受入基準5と7を確かめられるか、CB-010 の追加が今のテストと合うか、受入基準6の後回しの書き場所があるかを照らした。`/api/auth` の下の書き込みの操作は `XsrfTokenHeader` を持たないので、2つ目の確認に使う操作は偽の送信の検査を受ける操作に絞られる。指摘 T5-1-1、T5-1-3、T5-1-4、申告1
- tasks.md 大タスク3と4の箱の [x] と、3.1〜4.2 の `_保留:_` の削除: 実装を進めた印の差分で、タスクの本文と確かめ方は変わっていない。影響なし
- tasks.md 実装のメモに足した箇条(タスク3.1〜3.10 で分かったことと決めたこと、spec 全体の確認で見つけた3つのこと、タスク4.2 で分かったこと): 実装の記録である。名指すタスクの本文と食い違う箇所(3.5 で match を書かなかった項目、spec の約束に届いていない3つのこと)は、所有者に報告することか、所有者が 2026-11-10 に出荷してよいと決めたことと一緒に書かれている。4.2 のメモ(作業フォルダでの `COMPOSE_PROJECT_NAME`)は、15.2 の `start-dev.sh` の起動にも当たり、食い違わない。影響なし
- tasks.md タスク1.4、1.5、2.3、PDF の部品のタスク、3.1、3.4、3.5、3.10、5.1、8.3、実装のメモの「比べる検査」を「Java 版と Go 版を比べる検査」に替えた差分: 書き方の点検で呼び名を替えただけで、名指すファイル・テスト・条件は前と同じである。影響なし

### 申告

**1. 要件14の受入基準6のうち、Go 版がログインした開発者への応答を返すことを、この spec では確かめず、認証のまとまりの spec の確認に回す** — tasks.md タスク15.2 の本文(progress.md に書く決まり)と「受入基準とテストの対応」

- Issue の記載: あり。「開発者向けのAPI説明画面を、開発環境で開ける」。「Try it out」で Go 版を呼べることは、所有者が承認した requirements の要件14の受入基準5〜7にある。いつ確かめるかは、Issue にも requirements にも design にも書いていない
- 決めたこと: 15.2 では、要求に Cookie が付いて送られることだけを確かめる。ログインした応答が返ることは、progress.md に書く決まりで、認証のまとまりの spec の確認に任せる
- 他にありえた選択肢: (a) この spec の後の大タスク(たとえば段階6の、すべてのまとまりを作り終えたあとの PR)に、説明画面でログインしてログインの要る API の応答を確かめる確認を足す。(b) 認証のまとまりの子の Issue #770 の本文に、確かめることを所有者に書き足してもらう
- 外れていた場合: 認証のまとまりの spec の審査と PR の判定は、Issue #770 の本文とその spec を基準にするので、progress.md の決まりが読み落とされると、受入基準6を確かめないまま Issue #445 が閉じる。ログインの状態の Cookie の性質(SameSite など)のために説明画面からの要求にその Cookie が付かなくても、気づかない

**2. Java 版の CORS の応答を記録して正解にし、design の CORS の5つの箇条と食い違えば Java 版に合わせ、食い違いは実装のメモに書く** — tasks.md タスク15.1 の1段落目

- Issue の記載: あり。「Java 版と同じ動きかどうかの正解は、今の Java 版が実際に返す応答と、実際に保存するデータとする」
- 決めたこと: 記録が design の箇条と違えば、コードは Java 版の記録に合わせ、design は直さず、実装のメモに書く
- 他にありえた選択肢: 食い違いを見つけたら作るのを止め、所有者に報告して design を直してから作る。または、合わせたうえで PR の本文にも食い違いを書く
- 外れていた場合: design の箇条と違うコードが main に入る。PR の判定(codex-review)は design を基準にするので、PR で食い違いとして止まり、所有者の判断を待つことになる。実装のメモだけに書くと、PR の本文には食い違いが出ない(CLAUDE.md は、承認済みの spec の合格の条件に届かないときは PR の本文に書くと決めている)。食い違いの1つは、前の段階への指摘 T5-1-5 に書いた

**3. テストを省略可能な印(`- [ ]*`)にしたタスク**: 今回の差分には無い

### 指摘

| ID | レベル | 該当箇所 | 内容 | 直し方の案 |
|---|---|---|---|---|
| T5-1-1 | 中 | tasks.md タスク15.2 の最後の段落(「Claude Code の中のブラウザで `http://localhost:8082` を開いて」)と「完了の確かめ方」 | 2つの確認は、Claude Code の中のブラウザが使えることを前提にしており、使えないときの扱いが無い。`.claude/skills/ship/SKILL.md` の271〜272行目は、中のブラウザが使えないとき(ターミナルの Claude Code など)があることを前提にしている。使えないときに、Claude がこのリポジトリのもう1つのブラウザである Playwright MCP(`/verify-ui`)に替えると、Playwright のブラウザは別のコンテナで動くので、`localhost:8082` でなく `host.docker.internal:8082` で開くことになる(`/verify-ui` の27行目)。すると、送り元が `http://host.docker.internal:8082` になって許す送り元に無く、仕様書の `servers` の `http://localhost:8081` もそのコンテナの中を指すので、1つ目の確認が失敗する。Claude がこれを直そうとして許す送り元に `host.docker.internal` を足すと、design の config の値と CB-010 から外れる。どちらにしても、15.2 を実装する会話で確かめ方を決め直すことになる | 15.2 に「中のブラウザが使えないときは、Claude は Playwright に替えず、開発環境を起動したまま、2つの確認の手順(開く URL、押す場所、入れる値、うまくいったときに見えるもの)を所有者に示して止まり、所有者の結果を受けてから PR を出す」の1文を足す。あわせて、確かめのために許す送り元を design の2つのほかに足さないことを書く |
| T5-1-2 | 中 | tasks.md タスク15.1 の「受入基準とテストの対応」の `TestCORS_RunsBeforeCSRF`(「許す送り元からの `OPTIONS` のプリフライトが、偽の送信の検査で断られずに 200 になる」) | 今の `csrf.go`(27〜30行目)は、`OPTIONS` の要求を検査せずに次の処理へ渡す。そのため、CORS の処理を偽の送信の検査の後ろ(ログインの状態の検査の前)に置いても、プリフライトは CORS の処理に届いて 200 になり、このテストは通る。完了条件の4つ目(対象のコードを壊してテストが赤くなるかを確かめる)でも、中間処理を外して壊せば赤くなるので、順の誤りは見つからない。順を誤ると、偽の送信の検査が返す 403 に CORS のヘッダが付かないので、ブラウザはその 403 を画面のコードに読ませず、CORS のエラーとして扱う。開発環境で別の送り元から呼ぶ画面(`localhost:5173`。段階6からは Go 版を呼ぶ)と説明画面で、偽の送信の検査の 403 が見えなくなる。比べる検査は `Origin` を付けないので、この違いはどの検査でも止まらない | 15.1 の Java 版の記録に、偽の送信の検査を受ける経路(`/api/auth` の下でない経路)への、許す送り元からの `X-XSRF-TOKEN` の無い書き込みの要求を足す。`TestCORS_RunsBeforeCSRF` の確かめ方を、同じ要求に、Go 版が 403 と偽の送信の検査の本文に加えて、Java 版の記録のとおりの CORS のヘッダ(`Access-Control-Allow-Origin` と `Access-Control-Allow-Credentials: true` など)を返すこと、に替えるか足す |
| T5-1-3 | 低 | tasks.md タスク15.2 の本文(「`backend/compat/changed-behaviors.yaml` に CB-010 を…足す」)と「完了の確かめ方」 | 今の `match_test.go` の `TestLoadChangedBehaviors_CB005HasNoMatch`(321〜333行目)は、一覧の項目がちょうど9つであることと、記録だけの項目が CB-005、CB-007〜CB-009 であることを確かめる。CB-010 を足すと、このテストが「一覧の項目は9つのはず」で失敗する。15.2 は、このテストを直すことも、CB-010 が `match` を持たないことを確かめることも書いていない。また「完了の確かめ方」の「自分を確かめる筋書きが…成功する」は流すコマンドを書いておらず、`/verify-backend` の Go 版の手順(`make check`)はビルドタグ `compat` のテストを流さない。CI の `backend-compat` で落ちて気づくので、手戻りは小さい | 15.2 に「`TestLoadChangedBehaviors_CB005HasNoMatch` の項目の数を10にし、`match` を持たない項目に CB-010 を足す」と書き、「完了の確かめ方」に `run-check.sh backend-go make compat` が成功することを足す |
| T5-1-4 | 低 | tasks.md タスク15.2 の本文(「`progress.md` の認証のまとまりの決まりに」) | 今の progress.md には、「認証のまとまりの決まり」という節も箇条も無い。節は、段階の表、まとまりの表、所有者がする操作、PR の本文の決まり、止まって報告するとき、会話が途切れたときの読み直し方の6つである。どこに書くかで読み方が分かれ、まとまりの表の近くに無いと、認証のまとまりの spec を始める会話が読み落としやすい | 書く場所を、たとえば「まとまりの表の下に、まとまりの spec で確かめることの箇条を作り、認証の箇条に書く」のように1つに決める。申告1の扱いと合わせて決める |

### 前の段階への指摘

| ID | 対象 | 該当箇所 | 内容 |
|---|---|---|---|
| T5-1-5 | design | 「httpapi」の CORS の処理の5つ目の箇条(383行目。許す送り元からのプリフライトでない要求には、ヘッダを付けて次の処理に渡す) | 5つ目の箇条は、許す送り元からのプリフライトでない要求に、メソッドによらずヘッダを付けて次の処理に渡すと書く。Java 版の `SecurityConfig` は、許すメソッドを `GET` `POST` `PUT` `DELETE` `PATCH` `OPTIONS` の6つに決めている(126行目)。Spring の CORS の処理は、プリフライトでない要求でも、要求のメソッドをこの一覧と照らすので、許す送り元からの `HEAD` などの要求には、403 と `Invalid CORS request` を返すと読める。tasks の 15.1 は、Java 版の記録に合わせるとして `TestCORS_ActualRequestMethod` を置いたので、実装は Java 版に合う。しかし、design の箇条と食い違うコードになり、design を基準にする PR の判定で食い違いに見える。15.1 の記録で確かめたうえで、design の箇条に、6つのほかのメソッドのプリフライトでない要求の扱いを足すかを、所有者に確かめてもらう |

- 往復: 1回目 / 高0 中2 低2

## サイクル6 往復1(2026-11-10)

### 審査の範囲

範囲: 差分

- tasks.md タスク15.1 の1段落目(Java 版に送る要求の8つの箇条。許す送り元からの、ヘッダ `X-XSRF-TOKEN` の無い `POST` を足し、`GET` と `HEAD` を分けた)と、「受入基準とテストの対応」の `TestCORS_RunsBeforeCSRF`、`backend/internal/httpapi/middleware/csrf.go`(25〜63行目)、`backend/internal/httpapi/server.go`(77〜80行目)、`backend/src/main/java/com/example/keirekipro/presentation/security/config/SecurityConfig.java`(52〜117行目): T5-1-2 の直しで、テストが偽の送信の検査の 403 に `Access-Control-Allow-Origin` が付くことを見るようになった。今の `csrf.go` は `OPTIONS` を検査せずに通し、`OPTIONS` でも `/api/auth` の下でもない `POST` で Cookie かヘッダが無ければ、自分で 403 を書いて次の処理に渡さない。そのため、CORS の処理が偽の送信の検査の外側にあれば、その 403 に CORS の処理が先に付けたヘッダが残り、内側にあればヘッダが付かない。テストは順の誤りを見分けられる。テストの文の「今の偽の送信の検査は、`OPTIONS` の要求を検査せずに次の処理に渡す」は `csrf.go` の27〜30行目と合う。Java 版は Spring Security の CORS の処理が CSRF の処理より前に動き、`accessDeniedHandler`(84〜88行目)は応答を消さずに書くので、Java 版の記録にも同じヘッダが付くと読める。Java 版の記録の要求に経路が書かれていない点は指摘 T6-1-1
- tasks.md タスク15.1 の `TestCORS_ActualRequestMethod`、design.md 「httpapi」の CORS の処理の5つの箇条(378〜383行目)、同じ節の偽の送信の検査の箇条(384〜389行目)、`SecurityConfig.java`(122〜133行目): T5-1-5 の直しで design の5つ目の箇条が、6つのメソッドのほかのプリフライトでない要求に 403 と `Invalid CORS request` を返す形になった。テストの文の、許す送り元からの `HEAD` に 403 と本文 `Invalid CORS request` を返して次の処理に渡さないこと、`GET` には `Access-Control-Allow-Origin` を付けて次の処理に渡すことは、直した design の箇条と、Java 版の許すメソッドの6つ(126行目)と合う。15.1 の1段落目の「記録と design が食い違えば Java 版に合わせ、実装のメモに書く」とも食い違わない(design が Java 版の動きに合わせて直されたので、食い違うのは記録が予想と違ったときだけである)。影響なし
- tasks.md タスク15.1 のほかの7つのテスト(`TestCORS_PreflightAllowed` から `TestCORS_ProdWriteFromAppOrigin`)と「8つのテスト」の数: 差分で変わったのは `TestCORS_ActualRequestMethod` の文だけで、テストの数は8つのまま合う。`TestCORS_ActualRequestHeaders` と `GET` の確かめが重なるが、食い違いではない。影響なし
- tasks.md タスク15.2 の最後の段落(Claude Code の中のブラウザが使えないときの扱い)と「完了の確かめ方」「受入基準とテストの対応」、design.md 「api-docs」の節(417〜429行目)、`.claude/skills/verify-ui/SKILL.md`(23〜28行目): T5-1-1 の直しで、中のブラウザが使えないときは Playwright に替えず、所有者に手順を示して止まると書くようになった。`/verify-ui` の27行目のとおり Playwright のブラウザは別のコンテナで動き `host.docker.internal` の URL を開くので、送り元が design の config の許す送り元(`http://localhost:5173` と `http://localhost:8082`)に当たらないという理由は事実と合う。所有者に手順を示して止まる形は、ルートの `CLAUDE.md` の「所有者が画面などで手で確かめることが残っているときは、確かめの手順を示して止まり、所有者の結果を受けてから出荷する」と合う。「完了の確かめ方」が中のブラウザでの確認だけを挙げる点は指摘 T6-1-2
- requirements.md 要件14の受入基準5〜7: 差分は、受入基準とタスクの対応(15.1 の `_要件: 14.5_`、15.2 の `_要件: 14.5, 14.6, 14.7_`)を変えていない。影響なし

### 申告

(今回の差分で新しく申告するものはない。差分は、サイクル5の T5-1-1 と T5-1-2 への直しと、T5-1-5 で直した design に合わせた直しと、書き方の点検の直しである。15.2 の、中のブラウザが使えないときに所有者の確認を待つ扱いは、ルートの `CLAUDE.md` の決まりで決まっており、ほかの選択肢を書けないので申告しない。サイクル5の申告1と申告2は、差分で変わっていない)

### 指摘

| ID | レベル | 該当箇所 | 内容 | 直し方の案 |
|---|---|---|---|---|
| T6-1-1 | 低 | tasks.md タスク15.1 の1段落目の箇条「許す送り元からの、ヘッダ `X-XSRF-TOKEN` の無い `POST`」 | Java 版に送るこの要求の経路が書かれていない。Java 版は `/api/auth/**` と `/actuator/**` の下を偽の送信の検査から外す(`SecurityConfig.java` の65〜71行目)ので、たとえばログインの API に送ると、偽の送信の検査の 403 が返らず、`TestCORS_RunsBeforeCSRF` の期待(偽の送信の検査の 403 に付く CORS のヘッダ)の正解として使えない記録になる。ただし、テストの文が「偽の送信の検査が返す 403」と書くので、実装する Claude は検査を受ける経路を選ぶと読め、選び直しても手戻りは `curl` を1回送り直すだけである | 箇条を「許す送り元からの、偽の送信の検査を受ける経路(`/api/auth` と `/actuator` の下でない経路)への、ヘッダ `X-XSRF-TOKEN` の無い `POST`」とする |
| T6-1-2 | 低 | tasks.md タスク15.2 の「完了の確かめ方」(「Claude Code の中のブラウザでの2つの確認が上のとおりになり」) | 本文は、中のブラウザが使えないときは所有者が2つの確認をし、その結果を受けて PR を出すと決めた。しかし「完了の確かめ方」は中のブラウザでの確認だけを挙げるので、所有者が確かめたときに、文の字面どおりには完了の条件を満たさない。`/kiro-impl` の確認役が字面どおりに読むと差し戻す余地があるが、本文に扱いが書いてあるので、読めば分かる | 「完了の確かめ方」を「Claude Code の中のブラウザで、または中のブラウザが使えないときは所有者のブラウザで、2つの確認が上のとおりになり」とする |

### 前の段階への指摘

(なし)

- 往復: 1回で収束 / 未解決: 0件
