# design のレビューの記録

## サイクル1 往復1(2026-11-08)

### 審査の範囲

範囲: 全体

### 申告

**1. Java 版と Go 版で本番の ECS のタスク定義と ALB と秘密の値を共有し、出荷で替えるのはイメージだけにする** — 「概要」「全体の構成」「backend-deploy.yaml と release.yaml」

- Issue の記載: あり。「サービスを止めずに、動いたまま切り替える」と、所有者が受け入れた「切り替えの間と後に操作が失敗せず、保存が消えず、ログアウトされない」
- 決めたこと: Go 版が Java 版と同じ Secrets Manager の読み方、同じ 8080、同じ `/actuator/health` を持ち、タスク定義を共有する。切り替えと戻しは、`release.yaml` の入力 `backend_impl`(既定 `current`)でイメージだけを替える1回の出荷にする
- 他にありえた選択肢: Go 版の ECS サービスとタスク定義を別に作り、ALB の重みで切り替える(blue/green)。または、タスク定義を版ごとに持ち、出荷でタスク定義も替える
- 外れていた場合: タスク定義の共有が崩れる変更(たとえば Chromium のメモリで `memoryReservation` を変えざるをえない)が後から出ると、戻しが「タスク定義も戻す出荷」になり、手順書と出荷のワークフローを作り直す

**2. 表の形の履歴は、`flyway_schema_history` を読み書きする Go の自作の部品で続ける** — 「migrate(表の形の履歴の部品)」

- Issue の記載: あり。「本番の既存データをすべて引き継いでいる」(受入基準 12.4 が履歴の引き継ぎを求める)
- 決めたこと: Flyway の検査の値(CRC32)を Go で計算し、適用済みの行を確かめ、段階6からは未適用のファイルを適用して Flyway と同じ形の行を書く
- 他にありえた選択肢: Flyway の公式のイメージを別のコンテナで動かす。goose などに移し、V1〜V7 を適用済みとして記録する
- 外れていた場合: Flyway の `validate` が Go 版の書いた行を通さない形があると(説明の文字列、`type`、`installed_rank` のずれ)、Java 版に戻したときに Java 版が起動しない。段階6以降は Go 版しか読まないので影響は小さくなるが、段階4〜5の戻しの経路に当たる

**3. 分岐の割合の基準(73%)の代わりを、PR で変えた箇所だけの変異テスト(gremlins、見逃し 20% まで、未到達 7% まで)にする** — 「.golangci.yml と .testcoverage.yml と .gremlins.yaml」

- Issue の記載: あり。「今と同じ種類の自動品質チェックを、Go 側にそろえてから切り替える」。受入基準 3.3 が代わりの検査を理由つきで設計に書くよう求める
- 決めたこと: 文の割合 93% を go-test-coverage で、分岐の守りを `make mutation-diff` で、どちらも必須の検査 `backend-test` の中で止める
- 他にありえた選択肢: gobco で条件の割合を測る。文の割合の下限を上げる。変異テストを Java 版と同じく週次の報告だけにして、ゲートに入れない
- 外れていた場合: gremlins(0.x)の `--diff` の判定が揺れると、PR が不安定に赤くなり、ゲートの指定を緩める提案が繰り返される。ゲート設定の変更は所有者の承認を要する

**4. 必須の検査の名前を増やさず、`backend-test` を Java 版・Go 版・比べる検査の結果をまとめる仕事にする** — 「CI の仕事」

- Issue の記載: なし
- 決めたこと: `backend-java` `backend-go` `backend-compat` の3つを足し、既存の必須の検査 `backend-test` は判定だけをする。期待一覧と ruleset は変えない
- 他にありえた選択肢: `backend-go-test` と `backend-compat` を新しい必須の検査にし、所有者が ruleset と期待一覧に足す
- 外れていた場合: まとめの仕事の `if: always()` と「飛ばされた仕事があれば失敗」の判定に穴があると、Go 版の検査が飛ばされたまま緑で入る。週次監査は `backend-test` の飛ばしだけを見るので、この穴は見つからない

**5. PDF は、Go 版の本番のイメージに Chromium(`chromedp/headless-shell`)を入れ、1つ起動したまま同時2件で作る** — 「pdf(PDF を作る部品)」「Dockerfile.prod」「性能」

- Issue の記載: あり。「PDF の見た目が今と同じ」と、所有者が受け入れた 1〜2pt のずれ
- 決めたこと: 同じイメージに Chromium と Noto のフォントを入れ、`--no-sandbox` で動かし、PDF の同時の数を2までにして `memoryReservation` 1792MB の内側に収める
- 他にありえた選択肢: Chromium を同じタスクの別のコンテナにする(タスク定義が Java 版と変わる)。Go の純粋な PDF の部品で作り直す(見た目の一致を自分で作る)
- 外れていた場合: メモリが 1792MB に収まらないか、arm64 のイメージが無いと(指摘 D1-1-6)、タスク定義の共有(申告1)が崩れるか、PDF の作りからやり直す

**6. 開発環境の API の説明画面は、Swagger UI の公式のイメージを compose のサービスで動かし、Go 版のコードには入れない** — 「api-docs」

- Issue の記載: あり。「Swagger である必要はなく、Go におけるスタンダードなものにする」
- 決めたこと: research で「Go の公式の標準は無く、最も多く使われるのは Swagger UI」と調べ、Swagger UI を選んだ
- 他にありえた選択肢: Scalar、Redoc。Go 版のコードに説明画面の配信を入れる
- 外れていた場合: 所有者が Swagger 以外を望んでいたときは、イメージを替えるだけで済む。影響は小さい

**7. Go のモジュールを Java 版と同じ `backend/` に置く** — 「全体の構成」「ファイルの構成」

- Issue の記載: なし
- 決めたこと: `backend/go.mod` を置き、`backend/src/` の Java 版と同居させる。CI は変わったファイルの種類で仕事を分ける
- 他にありえた選択肢: `backend-go/` に置き、段階6で `backend/` に移す
- 外れていた場合: Java 版の Dockerfile.prod の組み立ての文脈 `./backend` に Go のファイルが入る。Gradle の `check` が `backend/**` の Go の変更で動く。段階6のフォルダの移しは要らなくなる

**8. 出荷の入力 `backend_impl` の既定を `current` にし、今のタスク定義のイメージのタグ(`go-` で始まるか)で版を読む** — 「backend-deploy.yaml と release.yaml」

- Issue の記載: なし
- 決めたこと: 既定では今本番で動いている版を出荷し、所有者が選んだときだけ版が替わる
- 他にありえた選択肢: 既定を `java` にする。版をリポジトリのファイルに書く
- 外れていた場合: タグの読み方を誤ると、切り替えのあとの通常の出荷で本番が Java 版に戻る

**9. 比べる検査の AWS の代わり(S3・SES v1・Secrets Manager の6操作)と、Google と GitHub のログインの代わりを Go で自作する** — 「fakeaws と fakeoidc」

- Issue の記載: なし
- 決めたこと: LocalStack は CI に認証トークンが無く、moto は送ったメールを HTTP で読めないため、自作する
- 他にありえた選択肢: moto の server mode(メールの比べを諦める)。LocalStack のトークンを CI の秘密に足す
- 外れていた場合: Java 版の AWS SDK(Spring Cloud AWS)が自作の代わりの応答を受け付けない形(XML の細部、署名の検査)があると、比べる検査が Java 版を起動できず、代わりを作り直す

**10. Go の部品の公開の時刻を index.golang.org を `since` で順に読んで調べる(72時間分、約190回の問い合わせ)** — 「Dependabot と公開の時刻の検査と脆弱性の直し」

- Issue の記載: なし
- 決めたこと: proxy.golang.org の `.info` は後から古い時刻にできるので使わず、index の取り込みの時刻を使う
- 他にありえた選択肢: GitHub のリリースの `published_at`(GitHub にあるモジュールだけ)。deps.dev の API
- 外れていた場合: 問い合わせの数で検査が遅くなるか、index の読み取りが失敗して PR が止まる

### 指摘

| ID | レベル | 該当箇所 | 内容 | 直し方の案 |
|---|---|---|---|---|
| D1-1-1 | 中 | design.md 「Dockerfile.prod」「CI の仕事」「perf」「Makefile」 | Dockerfile.prod の1段目が `GOARCH=arm64` を直書きしている。一方で、`backend-compat` の仕事は runs-on を書いておらず(ci.yaml の既定は `ubuntu-latest` = x86_64)、`docker-smoke` も `ubuntu-latest` で動き、`make compat` と `make compat-perf` は開発者の PC(多くは x86_64)の dind で動かす。x86_64 の Docker では arm64 の実行ファイルは動かず、比べる検査は Go 版のコンテナを起動できない。Java 版の Dockerfile.prod を x86_64 で arm64 向けに組み立てると十数分かかることも backend-deploy.yaml のコメント(#749)にある | `GOARCH` を Docker の `TARGETARCH` から取る(`ARG TARGETARCH` と `GOARCH=$TARGETARCH`)。`backend-compat` が動く機械(`ubuntu-24.04-arm` か、x86_64 で両方のイメージをその機械の CPU 向けに組み立てる)を書く。開発環境の `make compat` は、ホストの CPU 向けに組み立てると書く |
| D1-1-2 | 中 | design.md 「所有者に提案するゲート設定の変更」の表(2-1)、「移行」の「段階ごとの PR」 | 2-1 で `container-scan.yaml` に Go 版のイメージの組み立てを足すが、`docker/backend-go/Dockerfile.prod` と `go.mod` は 2-2 で作る。container-scan.yaml の変更の判定(`run` のフィルタ)は `.github/workflows/container-scan.yaml` 自身を含むので、2-1 の PR で container-scan が動き、無い Dockerfile を組み立てようとして失敗する。2-1 自身が main に入らない。Dependabot の `gomod` の項目も、`go.mod` の無い間は manifest が見つからないエラーになる | Go 版のイメージの組み立てを、Dockerfile.prod があるときだけ動かす形にする。または、`container-scan` と Dependabot の gomod の変更を 2-2 のあとの承認つき PR(2-5 など)に移す。「2-1 は Go のファイルを含まない」の前提は残してよい |
| D1-1-3 | 中 | design.md 「compat harness」の比べるものの表(データベース)と箇条書き | データベースは「すべての表を主キーの順に読む」としてから UUID を置き換える。主キーが UUID の表では、Java 版と Go 版がそれぞれ新しく作る行の UUID は別の乱数なので、主キーの順が両方で違い、同じ内容でも行の並びが違って「同じ」にならない。筋書きで行を1件でも作る操作のすべてが偽の違いで失敗する | 読み出した行を、UUID と日時を置き換えたあとに、置き換え後の値(応答で先に現れた順の番号)か、主キー以外の安定した列の組で並べ替えてから比べると書く |
| D1-1-4 | 中 | design.md 「compat harness」「fakeaws と fakeoidc」の使う部品、「config」 | 比べる検査で Java 版を動かすプロファイルと環境変数が書かれていない。Java 版の `prod` は Redis を TLS でつなぎ(`spring.data.redis.ssl.enabled: true`)、Cookie を `Secure`、CORS を本番の送り元にする。`dev` は Cookie を `Secure` なし、CORS を `http://localhost:5173`、AWS の接続先を `http://localstack:4566`(`SPRING_CLOUD_AWS_ENDPOINT` で替えられる)にする。Go 版の `test` の既定の値は「Java 版の application*.yaml と同じ」とあるが、Java 版に `test` は無く、どの値になるかが決まらない。比べる検査は `Set-Cookie` の `Secure` を比べるので、両方の版の設定が揃っていないと偽の違いが出る。research も「XSRF-TOKEN の Cookie の `Secure` の付き方」を確かめきれていないとしている | 比べる検査では Java 版を `dev` プロファイルで動かし、`SPRING_CLOUD_AWS_ENDPOINT` と `OIDC_PROVIDERS_*` の環境変数で代わりにつなぐと書く。Go 版の `test` の既定の値は Java 版の `dev` と同じ(Cookie の `Secure` なし、CORS `http://localhost:5173`、Redis は TLS なし)と書く |
| D1-1-5 | 中 | design.md 「段階6の削除と書き換え」の 6-4 の検査 | `git grep -n -i -E 'java\|spring\|...'` を、言語を書いてよいファイルと `.kiro/specs/` を除いて動かし「0件」を PR に書くとある。`-i 'java'` は `JavaScript` と `javascript-typescript`(`.github/codeql/languages.tsv`)、frontend の `package.json` の `javascript` などにも当たるので、0件にはならない。同じ節で「`flyway_schema_history` のように残る名前は、残す理由を添えて並べる」とも書いており、0件と並べる一覧が両立しない。受入基準 15.4 が求めるのは「Java 版だけが使う言語と道具の名前が残っていない」ことで、JavaScript は対象でない | 語の境目を付けた形(`\bjava\b` など)にし、`javascript` を除く。検査の合格の条件を「見つかった行のすべてに、残す理由が PR の本文に付いていること」に直す |
| D1-1-6 | 中 | design.md 「プロジェクトの決まりを守っているか」の7項目目、「Dockerfile.prod」、research.md 「Go の部品と道具」 | 本番は ECS の `ARM64` で動くが、`chromedp/headless-shell` に `linux/arm64` のイメージがあることを、design も research も確かめた記録が無い。research の試作は `golang:1.27-bookworm` に Chromium を入れた別のイメージで行っている。7項目目は GitHub の属性(`owner.type` と `visibility`)だけを確かめている。arm64 が無ければ、PDF の部品と本番のイメージ(申告5)を作り直すことになり、気づくのは release の組み立て(段階4〜5)になる | `docker manifest inspect chromedp/headless-shell:<タグ>` で `linux/arm64` があることと、その digest を research に書き、design の7項目目に「いつ何をどう確かめたか」を足す。無いときは、代わりの土台(Debian の `chromium` パッケージなど)を比べてから design を直す |
| D1-1-7 | 中 | design.md 「runbook.md」(対応する要件 7.3)、「progress.md」 | 要件 7.3(所有者の承認が要る PR を作ったとき、承認が要る理由と、main に入れたときに本番で何が起きるかを1つの返事で示す)の対応が runbook.md にだけ振られているが、runbook は切り替えの3つの場面の操作を書くファイルで、PR を作るたびの返事の決まりは書かれていない。7.3 を実現する部品が無いので、tasks で 7.3 に対応するタスクを書けない | progress.md の「進め方の決まり」(PR の区切りの決まりの段)に、承認が要る PR を作るときの返事の中身(承認が要る理由、本番で起きること、起きないときは起きないこと)を書き、7.3 を progress.md の対応する要件に移す |
| D1-1-8 | 低 | design.md 「httpapi」の呼び出し方 | 「経路は仕様書の経路だけを登録する。仕様書に無い経路は 404 を返す」の直後に、仕様書に無い `/actuator/health` と `/healthz` を登録している | 「仕様書の経路と、生きているかの確認の2つの経路だけを登録する」に直す |
| D1-1-9 | 低 | design.md 「作らないもの」(frontend のコードは変えない)、「消す一覧」(`@react-router/node` と `@react-router/dev`) | 消す一覧が `frontend/package.json` と `pnpm-lock.yaml` を変える。「作らないもの」の「frontend のコードは変えない」と読み合わせると境目が曖昧である。また、`frontend/knip.json` の `ignoreDependencies` がこの2つを名指ししており、消すなら knip.json も直す必要があるが、消す一覧に無い | 「作らないもの」を「frontend のソースコードは変えない。依存の宣言の整理は消す一覧に限る」と書く。消す一覧に `frontend/knip.json` の `ignoreDependencies` の2行を足す |
| D1-1-10 | 低 | design.md 「プロジェクトの決まりを守っているか」の「品質チェックの設定」と「所有者に提案するゲート設定の変更」の表、「段階6の書き換え」 | 「変更は、すべて下の表に分けて書き」とあるが、段階6で変える `.claude/settings.json`、`.claude/hooks/check-encoding.sh`、`.claude/scripts/` の `ui.sh` `session.sh`、`.github/` の Java 版の仕事とスクリプトの削除は表に無く、「段階6の書き換え」の文にだけある | 表に段階6の行(6-1、6-4、6-5)を足すか、「すべて」を「段階2〜4の変更はすべて」に直して、段階6の分は「段階6の書き換え」を指す |
| D1-1-11 | 低 | design.md 「所有者に提案するゲート設定の変更」の `.github/dependabot.yml` の行、「Dependabot と公開の時刻の検査と脆弱性の直し」 | `docker` の項目は今の `dependabot.yml` で `directories: - "/docker/*"` になっており、`docker/backend-go/` と `docker/api-docs/` は追加なしで対象になる。「docker の項目の追加」は要らない | 行を「gomod の項目の追加」に直す |
| D1-1-12 | 低 | design.md 「所有者に提案するゲート設定の変更」の `check-release-age.sh` の行と箇条書き | `check-release-age.sh` は、Dependabot の docker の PR で、イメージの `FROM` の版の GitHub のリリースの公開日時を見て自動マージの予約を決めるスクリプトであり、部品のエコシステムは扱わない。gomod の公開の時刻の検査は `check-dependency-cooldown.sh`(表の別の行)の役目で、この行は二重になる。Dependabot 自身の gomod の待ち期間(`cooldown`)も使える | この行を外す。Go 版の土台のイメージの版の待ちは、今の `check-release-age.sh` の対象の表に `chromedp/headless-shell` と `golang` を足す形なら、その中身に書き直す |
| D1-1-13 | 低 | design.md 「config」の `KEIREKIPRO_OIDC_<GOOGLE\|GITHUB>_<AUTH\|TOKEN\|USERINFO>_URL`、「fakeaws と fakeoidc」 | fakeoidc は GitHub の `/user` と `/user/emails` を返すが、Go 版が `/user/emails` の URL を替える環境変数が無い(`USERINFO` は `/user` に当たる)。GitHub のメールアドレスの取得だけが本物の api.github.com に向く | `KEIREKIPRO_OIDC_GITHUB_EMAILS_URL` を足すか、GitHub は API の土台の URL を1つの環境変数で替える形にする |

### 前の段階への指摘

| ID | 対象 | 該当箇所 | 内容 |
|---|---|---|---|
| (なし) | | | |

- 往復: 1回目 / 高0 中7 低6

## サイクル1 往復2(2026-11-08)

### 審査の範囲

範囲: 差分

- design.md 「config」「fakeaws と fakeoidc」の使う部品、「compat harness」: D1-1-4 の直しで、比べる検査が Java 版を `dev` のプロファイルで動かすことになったので、`backend/src/main/resources/application.yaml` `application-dev.yaml` `application-prod.yaml` と `docker/localstack/init-localstack.sh` を読み、`dev` で Java 版が何をどこから読むかを確かめた
- design.md 「段階6の削除と書き換え」の 6-4 の検査: `-w` を足す直しなので、`-w` で拾えなくなる語がリポジトリの書き換えの対象のファイルにあるかを `git grep` で確かめた
- design.md 「runbook.md」と requirements.md 要件5 の受入基準 5.3: 差分で runbook の役割の文が1つ消えたので、消えた文が受入基準の求めることかを確かめた
- design.md 「変えた動きの一覧」の候補の表と requirements.md 要件9 の 9.6: 差分で候補の表の前の文が消えたので、決める主体が本文のほかの箇所に残っているかを確かめた
- design.md 「ファイルの構成」の `backend/compat/` と「安全」: 差分でビルドタグの説明が harness の行に移り、fakeaws の節の「`compat` のビルドタグの中にだけあり」の文が消えたので、「安全」の節の同じ主張が成り立つかを確かめた
- design.md 「所有者に提案するゲート設定の変更」の表、「段階ごとの PR」の 2-5、「CodeQL とイメージの検査と組み立てて動かす検査」: 2-5 への移動と、`languages.tsv` を 2-1 に残す理由を、`.github/codeql/languages.tsv` と `.github/scripts/detect-codeql-languages.sh` で確かめた(Go の行は `git ls-files` で Go のファイルが見つかったときだけ選ばれるので、2-1 に残してよい)
- design.md 「プロジェクトの決まりを守っているか」の7項目目と research.md 「Go の部品と道具」: `chromedp/headless-shell` の確認の記録(日付、コマンド、索引の digest)が両方にあることを確かめた
- design.md 「Dockerfile.prod」「CI の仕事」「compat harness」の使う部品: `GOARCH=$TARGETARCH` と「検査を動かす機械の CPU 向け」が、`backend-compat` の仕事(runs-on の指定なし)と矛盾しないことを確かめた
- design.md 「全体の構成」: 「プロジェクトの決まりを守っているか」が参照先に変わったので、依存の向きの文が「全体の構成」にあることを確かめた
- design.md 「progress.md」と requirements.md 7.3: 7.3 の移動先に、承認が要る PR の返事の決まりがあることを確かめた
- design.md 「段階ごとの PR」の箇条の 4-1 と 4-3 の削除: 同じ内容が「段階4の本番の設定の変更」「runbook.md」の1番、「perf」のいつ動くか、にあることを確かめた。影響なし
- design.md 「Java 版の削除」の 6-1 の言い換え、「消す一覧」の 6-1 の言い換え: 「段階6の削除と書き換え」の表の 6-1 の中身と同じであることを確かめた。影響なし

### 申告

**1. 比べる検査で Java 版を `dev` のプロファイルで動かし、両方の版の設定を `application-dev.yaml` の値にそろえる** — 「fakeaws と fakeoidc」の使う部品、「config」

- Issue の記載: なし
- 決めたこと: Java 版を `SPRING_PROFILES_ACTIVE=dev`、Go 版を `KEIREKIPRO_ENV=dev` で動かし、Cookie の `Secure` なし、CORS `http://localhost:5173`、Redis は TLS なしでそろえる
- 他にありえた選択肢: Java 版を `prod` のプロファイルで動かし、Redis の TLS と Cookie の `Secure` を環境変数で1つずつ外す。または、比べる検査のための第3のプロファイルを Java 版に足す
- 外れていた場合: `dev` には本番で動かない設定(Actuator の全部の接続先の公開、Swagger の配信、デバッグのログ)が入るので、`prod` でだけ起きる動き(Redis の TLS の接続、`Secure` 付きの Cookie の性質)は比べる検査の外になる。切り替えのあと本番でだけ違いが見つかる

**2. 比べる検査の Java 版と Go 版のイメージを、検査を動かす機械の CPU 向けに組み立てる** — 「compat harness」の使う部品、「Dockerfile.prod」

- Issue の記載: なし
- 決めたこと: Dockerfile.prod は `GOARCH=$TARGETARCH` にし、`backend-compat` の仕事(x86_64)と開発者の PC では、その機械の CPU 向けのイメージを比べる
- 他にありえた選択肢: `backend-compat` を `ubuntu-24.04-arm` で動かし、本番と同じ arm64 のイメージを比べる
- 外れていた場合: 本番(arm64)の Chromium と検査(x86_64)の Chromium で PDF の文字の配置が違うと、比べる検査が通っても本番の PDF が許す幅の外になり、気づくのは段階5の所有者の確認になる

**3. `container-scan` と Dependabot の gomod の項目の変更を、2-1 から 2-5 に移す** — 「所有者に提案するゲート設定の変更」「段階ごとの PR」

- Issue の記載: なし
- 決めたこと: Go のファイルがあることを前提にするゲート設定の変更を、2-2 のあとの承認つき PR 2-5 にまとめる
- 他にありえた選択肢: `container-scan.yaml` で Go 版の組み立てを Dockerfile があるときだけ動かす形にし、2-1 に残す
- 外れていた場合: 2-2 から 2-5 が main に入るまでの間、Go 版の本番のイメージは Trivy で調べられず、Go の部品の版の上げ方は Dependabot に任せられない。2-5 が長く承認を待つと、その間の Go のコードの脆弱性の網が無い

### 指摘

| ID | レベル | 該当箇所 | 内容 | 直し方の案 |
|---|---|---|---|---|
| D1-2-1 | 中 | design.md 「段階6の削除と書き換え」の 6-4 の検査(D1-1-5 の直し) | `git grep -w` は、語の前後が英数字か `_` だと拾わない。そのため、`_` でつながる名前と、別の語がくっついた名前が、検査から外れる。書き換えの対象の「設定とスクリプト」に、今、`-w` で拾えない行がある。`.claude/scripts/parallel/run-check.sh` 125行目の `"backend:./gradlew check"`、`.claude/scripts/parallel/ui.sh` 214〜215行目の `SPRING_APPLICATION_JSON` と `./gradlew bootRun`、`.claude/commands/goal-fix-tests.md` 12行目の `./gradlew test`(`gradlew` は `gradle` の直後に `w` が付くので `-w` に当たらない)。`jacocoTestReport` のような Gradle のタスクの名前と `JAVA_TOOL_OPTIONS` のような環境変数の名前も同じ理由で外れる。さらに、残してよい行の例に挙げた `flyway_schema_history` も、`flyway` の直後が `_` なので `-w` では見つからず、例と検査が合わない。受入基準 15.4 は「Java 版だけが使う言語と道具の名前が残っていない」ことを求めるが、この検査では `gradlew` と `SPRING_*` が残っても検査に出ず、誰も気づかずに 6-4 が main に入る | `-w` を外し、語の境目を「英数字でない文字か行の端」にした形にする。例: `git grep -n -i -E '(^|[^[:alnum:]])(java|spring|gradle|jdk|jacoco|pitest|pmd|spotbugs|checkstyle|archunit|flyway|openhtmltopdf|thymeleaf|lombok)' \| grep -v -i -E 'javascript'` のように、`_` を境目として扱い、`JavaScript` は別の除外で外す。または `-w` のまま、`gradlew` `SPRING_` `JAVA_` のような `_` と接尾の付く形を2つ目の `git grep` で拾うと書く。残してよい行の例は、直した検査で実際に見つかる形(`flyway_schema_history` なら `_` を境目にする形で見つかる)に合わせる |
| D1-2-2 | 中 | design.md 「fakeaws と fakeoidc」の使う部品、「config」の `dev` と `test` の段(D1-1-4 の直し) | Java 版の `application-dev.yaml` は `spring.config.import: aws-secretsmanager:keirekipro/rds;keirekipro/redis;keirekipro/jwt` で始まり、データベースと Redis と JWT の値を Secrets Manager から読む(`${host}` `${redis-host}` `${jwt-secret}`)。`DB_HOST` などの環境変数は `application.yaml` の既定であって、`dev` では使われない(開発環境では `docker/localstack/init-localstack.sh` が3つの秘密の値を作っている)。`optional:` が無いので、読めなければ Java 版は起動しない。よって、比べる検査で Java 版を `dev` で動かすには、fakeaws が Java 版の起動の前に `keirekipro/rds` `keirekipro/redis` `keirekipro/jwt`(と `keirekipro/oidc/*`)の `GetSecretValue` に、比べる検査が起こした Postgres と Redis の接続先と、Go 版の `JWT_SECRET` と同じ値を返す必要がある。本文は、fakeaws の役割を「受けたオブジェクトとメールを覚えて返す」とだけ書き、Java 版の起動のために返す秘密の値と、JWT の秘密を Go 版とそろえることを書いていない。JWT の秘密がそろわないと、版をまたぐ確認(cross)で Java 版が出したトークンを Go 版が受け付けず、「ログアウトされない」の確認が全部失敗する。「config」の「`dev` と `test` では、Java 版と同じ名前の環境変数を読む」も、Java 版の `dev` の読み方とは合わない | 「fakeaws と fakeoidc」の役割か使う部品に、比べる検査が Java 版を起こす前に fakeaws に5つの秘密の値を登録し、`keirekipro/rds` と `keirekipro/redis` は検査が起こした Postgres と Redis の接続先、`keirekipro/jwt` は Go 版の `JWT_SECRET` と同じ値、`keirekipro/oidc/*` は fakeoidc の `client_id` と `client_secret` にする、と書く。「config」の文は「Go 版の `dev` と `test` は、Java 版の `application.yaml` の既定と同じ名前の環境変数を読む」のように、Java 版の `dev` が Secrets Manager から読むことと食い違わない形に直す |
| D1-2-3 | 中 | design.md 「runbook.md」の役割(差分で消えた文) | 往復1の本文にあった「各操作には、押す場所か打つコマンドと、うまくいったかの見分け方を書く」が消えた。受入基準 5.3 は「操作ごとに、押す場所か打つコマンドと、うまくいったかの見分け方を書く」ことを求める。残った5つの操作のうち、見分け方があるのは1と2だけで、3(Claude への報告の依頼)、4(画面での確認)、5(Java 版に戻す出荷)には無い。とくに5は戻しの操作であり、見分け方が無いと、所有者は戻せたかを確かめられない。消えた文が「操作ごとに見分け方を書く」決まりの唯一の記述だったので、5.3 を裏付ける記述が design から無くなった | 消えた文を戻す。あわせて、3〜5の操作にも見分け方を書く(5 は「ワークフローの要約の版が `java` で、`backend` の仕事が成功したこと」のように) |
| D1-2-4 | 低 | design.md 「変えた動きの一覧」の候補の表の前の文(差分で消えた文) | 「まとまりの spec は、これらの動きを Go の標準の形(4xx)に変えるかを決める。変えると決めたら、Claude は、変えた動きの一覧に項目を足す」が消え、候補の表が、誰がいつ決めるかの無い表になった。要件 9.6 で、変えたら一覧に足すことは読めるが、「変えるかを決めるのはまとまりの spec」と「決める時期」が本文から読めない | 消えた文を1文で戻す(「まとまりの spec が、変えるかを決め、変えると決めた動きを一覧に足す」) |
| D1-2-5 | 低 | design.md 「ファイルの構成」の `backend/compat/` の行、「安全」の2つ目の箇条 | ビルドタグ `compat` を付けると書いたのは `backend/compat/harness/` の行だけになり、fakeaws の節の「どちらも `compat` のビルドタグの中にだけあり、本番のイメージには入らない」が消えた。「安全」は「`compat` のビルドタグの中にある AWS とログインの代わりは、本番の実行ファイルに入らない」と書いたままで、根拠の記述が無い。実際には `cmd/keirekipro` が `compat/` のパッケージを読まないので入らないが、本文の理由と合っていない | 「ファイルの構成」で、ビルドタグを付けるのを `backend/compat/` の下の Go のファイルの全部にする(harness の行から `backend/compat/` の見出しの文に移す)か、「安全」の理由を「`cmd/keirekipro` が `backend/compat/` を読まず、本番の組み立ては `-tags` を付けないので」に直す |

### 前の段階への指摘

| ID | 対象 | 該当箇所 | 内容 |
|---|---|---|---|
| (なし) | | | |

- 往復: 2回目 / 高0 中3 低2

## サイクル1 往復3(2026-11-08)

### 審査の範囲

範囲: 差分

- design.md 「fakeaws と fakeoidc」の使う部品、「config」の `dev` と `test` の段、「cross」: D1-2-2 の直しで足した秘密の値の登録の段が、Java 版の `application-dev.yaml`(`spring.config.import: aws-secretsmanager:keirekipro/rds;keirekipro/redis;keirekipro/jwt`)と `application.yaml`(`oidc.providers.*.secretName`、`DB_HOST` などの既定)と合うかを、両方のファイルと `docker/localstack/init-localstack.sh`(秘密の値のキーの名前)で確かめた。cross の「1つの Postgres と1つの Redis と1つの fakeaws」とも矛盾しない。影響なし
- design.md 「段階6の削除と書き換え」の 6-4 の検査、「移行」の「段階6の書き換え」、requirements.md 15.2 と 15.4: D1-2-1 の直しで `git grep` の形と、言語を書いてよいファイルの参照先が変わったので、参照先の一覧が 15.2 と合うことと、新しい形が `gradlew` `SPRING_APPLICATION_JSON` `flyway_schema_history` を拾うことを確かめた。あわせて、書き換えの対象のファイルに、新しい形の語の一覧に無い Java 版だけの道具の名前が今あるかを Grep で確かめた(指摘 D1-3-1)
- design.md 「runbook.md」の役割と操作3〜5、requirements.md 5.3、`.github/workflows/release.yaml`: D1-2-3 の直しで戻した文と足した見分け方が 5.3 の求めることと合うか、操作5の見分け方(`backend` の仕事の成功)が release.yaml の仕事の分け方(`deploy_backend` `deploy_frontend` の入力)と矛盾しないかを確かめた。影響なし
- design.md 「段階6の削除と書き換え」の 6-3 の箇条と表、「本番の設定の値の変わり方」の表: 6-3 の言い換えで PR の中身(`/actuator/health` の削除)と順番(6-2 の反映のあと)が表と合うことを確かめた。影響なし
- design.md 「消す一覧」の冒頭と「段階6の削除と書き換え」の表の 6-5: 6-5 の言い換えが表の中身と合うことを確かめた。影響なし
- design.md 「使う既存の仕組み」の「品質の仕組み」: 足した説明が `backend-vuln-fix.yaml` と `mutation-report.yaml` の冒頭の説明と合うことを確かめた。影響なし
- design.md 「作るもの」「httpapi」「CI の仕事」「pdfcmp」「research.md の段階1の記録」「変えた動きの一覧の形」の CB-005、「テストの方針」「安全」: 書き方の点検の言い換えで、主語の追加と語の説明の追加だけであり、設計の中身が変わっていないことを前後の文で確かめた。影響なし

### 申告

(今回の差分で新しく申告するものはない)

### 指摘

| ID | レベル | 該当箇所 | 内容 | 直し方の案 |
|---|---|---|---|---|
| D1-3-1 | 中 | design.md 「段階6の削除と書き換え」の 6-4 の検査(D1-2-1 の直しの行) | 検査の形は直ったが、語の一覧(`java` `spring` `gradle` `jdk` `jacoco` `pitest` `pmd` `spotbugs` `checkstyle` `archunit` `flyway` `openhtmltopdf` `thymeleaf` `lombok`)に、Java 版だけが使う道具の名前で、今、書き換えの対象のファイルにあるものが入っていない。`.kiro/steering/structure.md`(言語に依存しない書き方にする文書)の52〜53行目の `MyBatis〜Repository` `MyBatis〜Query` と96行目の `Mockito単体` `MockMvc契約テスト` は、同じ行に一覧の語が無いので、この検査では出ない。`.claude/scripts/parallel/ui.sh` の228行目と232行目と `.claude/scripts/parallel/tests/test-ui.sh` の330行目と466行目の `actuator/health` も同じである(段階6で Go 版の `/actuator/health` を消すのは 6-3 で、ui.sh の書き換えは 6-4 なので、ここが残ると開発環境の起動の健康の確かめが通らなくなる)。受入基準 15.4 は「Java、Spring、Gradle のように Java 版だけが使う言語と道具の名前が残っていない」ことを求め、この検査がその唯一の機械の確かめである。一覧に無い名前は、6-4 の書き換えで取りこぼしても検査に出ず、誰も気づかずに 6-4 が main に入る。D1-2-1 と同じ種類の穴である | 語の一覧に、Java 版だけが使う道具の名前を足す。少なくとも `mybatis` `mockito` `mockmvc` `junit` `freemarker` `temurin` `actuator` `jackson` `maven` を足し、「Java 版の `libs.versions.toml` と `build.gradle` と `application*.yaml` に出る部品と道具の名前を、6-4 の PR を作るときに一覧に足す」と1文を書く。`testcontainers` は Go 版も testcontainers-go で使うので足さない |

### 前の段階への指摘

| ID | 対象 | 該当箇所 | 内容 |
|---|---|---|---|
| (なし) | | | |

- 往復: 3回 / 未解決: 1件

## サイクル2 往復1(2026-11-08)

### 審査の範囲

範囲: 全体

### 申告

**1. Java 版と Go 版で本番の ECS のタスク定義と ALB と秘密の値を共有し、出荷で替えるのはイメージだけにする。出荷の入力 `backend_impl` の既定は `current` で、今のイメージのタグ(`go-` で始まるか)で版を読む** — 「概要」「全体の構成」「backend-deploy.yaml と release.yaml」

- Issue の記載: あり。「サービスを止めずに、動いたまま切り替える」と、所有者が受け入れた「切り替えの間と後に操作が失敗せず、保存が消えず、ログアウトされない」
- 決めたこと: Go 版が Java 版と同じ秘密の値の読み方、同じ 8080、同じ `/actuator/health` を持ち、タスク定義を共有する。切り替えと戻しは、`release.yaml` の入力でイメージだけを替える1回の出荷にする。既定では今本番で動いている版を出荷する
- 他にありえた選択肢: Go 版の ECS サービスとタスク定義を別に作り、ALB の重みで切り替える。既定を `java` にするか、版をリポジトリのファイルに書く
- 外れていた場合: タスク定義の共有が崩れる変更(Chromium のメモリなど)が後から出ると、戻しが「タスク定義も戻す出荷」になり、手順書と出荷のワークフローを作り直す。タグの読み方を誤ると、切り替えのあとの通常の出荷で本番が Java 版に戻る

**2. 表の形の履歴は、`flyway_schema_history` を読み書きする Go の自作の部品で続ける** — 「migrate(表の形の履歴の部品)」

- Issue の記載: あり。「本番の既存データをすべて引き継いでいる」(受入基準 12.4)
- 決めたこと: Flyway の検査の値(CRC32)を Go で計算し、適用済みの行を確かめ、段階6からは未適用のファイルを適用して Flyway と同じ形の行を書く
- 他にありえた選択肢: Flyway の公式のイメージを別のコンテナで動かす。goose などに移し、V1〜V7 を適用済みとして記録する
- 外れていた場合: Flyway の `validate` が Go 版の書いた行を通さない形があると、Java 版に戻したときに Java 版が起動しない(段階4〜5の戻しの経路に当たる)

**3. 分岐の割合の基準(73%)の代わりを、PR で変えた箇所だけの変異テスト(gremlins、見逃し 20% まで、未到達 7% まで)にし、必須の検査 `backend-test` の中で止める** — 「.golangci.yml と .testcoverage.yml と .gremlins.yaml」「Makefile」

- Issue の記載: あり。「今と同じ種類の自動品質チェックを、Go 側にそろえてから切り替える」(受入基準 3.3 が代わりの検査を理由つきで設計に書くよう求める)
- 決めたこと: 文の割合 93% を go-test-coverage で、分岐の守りを `make mutation-diff` で止める
- 他にありえた選択肢: gobco で条件の割合を測る。文の割合の下限を上げる。変異テストを Java 版と同じく週次の報告だけにする
- 外れていた場合: gremlins(0.x)の `--diff` の判定が揺れると PR が不安定に赤くなり、ゲートの指定を緩める提案が繰り返される。ゲート設定の変更は所有者の承認を要する

**4. 必須の検査の名前を増やさず、`backend-test` を Java 版・Go 版・比べる検査の結果をまとめる仕事にする。期待一覧と ruleset は変えない** — 「CI の仕事」「所有者に提案するゲート設定の変更」「作らないもの」

- Issue の記載: なし
- 決めたこと: `backend-java` `backend-go` `backend-compat` の3つを足し、既存の必須の検査 `backend-test` は判定だけをする
- 他にありえた選択肢: `backend-go-test` と `backend-compat` を新しい必須の検査にし、所有者が ruleset と期待一覧に足す
- 外れていた場合: まとめの仕事の判定に穴があると、Go 版の検査が飛ばされたまま緑で入り、週次監査は `backend-test` の飛ばしだけを見るので見つからない。また、段階6で Gradle を前提にした必須の検査をどうするかは、指摘 D2-1-2 のとおり本文で決まっていない

**5. PDF は、Go 版の本番のイメージに Chromium(`chromedp/headless-shell`)を入れ、`--no-sandbox` で1つ起動したまま同時2件で作る** — 「pdf(PDF を作る部品)」「Dockerfile.prod」「性能」

- Issue の記載: あり。「PDF の見た目が今と同じ」と、所有者が受け入れた 1〜2pt のずれ
- 決めたこと: 同じイメージに Chromium と Noto のフォントを入れ、PDF の同時の数を2までにして `memoryReservation` 1792MB の内側に収める。収まらなければ同時の数を1に下げる
- 他にありえた選択肢: Chromium を同じタスクの別のコンテナにする(タスク定義が変わる)。Go の純粋な PDF の部品で作り直す
- 外れていた場合: メモリが 1792MB に収まらないと、タスク定義の共有(申告1)が崩れるか、PDF の作りからやり直す

**6. `go.mod` と `go.sum` を、CLAUDE.md が承認の対象の外とした「依存のバージョン宣言」として扱い、所有者の承認の対象に入れない** — 「プロジェクトの決まりを守っているか」の「新しいライブラリの追加」

- Issue の記載: なし
- 決めたこと: CLAUDE.md の承認の対象の一覧は Go のファイルを名指していないので、`go.mod` `go.sum` は承認なしで変えられるものとし、`Makefile` と検査の設定ファイルとコード生成の設定だけを `check-dependency-additions.sh` の対象に足す
- 他にありえた選択肢: `go.mod` は `toolchain` と `tool` の指定(道具の版と組み立ての指定)も持つので、Gradle の `*.gradle` と同じく「backend のビルドの手順のファイル」として承認の対象に入れる
- 外れていた場合: 所有者が `go.mod` の `tool` の指定(golangci-lint、govulncheck、sqlc などの道具の版)を承認の対象と考えていたときは、2-1 の `check-dependency-additions.sh` と CODEOWNERS の対象を直し、承認なしで入った `go.mod` の変更を見直すことになる

**7. 比べる検査で Java 版を `dev` のプロファイルで動かし、両方の版の設定を `application-dev.yaml` の値にそろえる。fakeaws が Java 版の起動の前に5つの秘密の値を返す** — 「fakeaws と fakeoidc」の使う部品、「config」

- Issue の記載: なし
- 決めたこと: Java 版を `SPRING_PROFILES_ACTIVE=dev`、Go 版を `KEIREKIPRO_ENV=dev` で動かし、Cookie の `Secure` なし、CORS `http://localhost:5173`、Redis は TLS なしでそろえる
- 他にありえた選択肢: Java 版を `prod` のプロファイルで動かし、Redis の TLS と Cookie の `Secure` を環境変数で外す。比べる検査のための第3のプロファイルを Java 版に足す
- 外れていた場合: `prod` でだけ起きる動き(Redis の TLS の接続、`Secure` 付きの Cookie)は比べる検査の外になり、切り替えのあと本番でだけ違いが見つかる

**8. 比べる検査の Java 版と Go 版のイメージを、検査を動かす機械の CPU 向けに組み立てる(`GOARCH=$TARGETARCH`)** — 「compat harness」の使う部品、「Dockerfile.prod」

- Issue の記載: なし
- 決めたこと: `backend-compat` の仕事(x86_64)と開発者の PC では、その機械の CPU 向けのイメージを比べる。本番は arm の機械で arm64 向けに組み立てる
- 他にありえた選択肢: `backend-compat` を `ubuntu-24.04-arm` で動かし、本番と同じ arm64 のイメージを比べる
- 外れていた場合: 本番(arm64)と検査(x86_64)の Chromium で PDF の文字の配置が違うと、比べる検査が通っても本番の PDF が許す幅の外になり、気づくのは段階5の所有者の確認になる

**9. 比べる検査の AWS の代わり(S3・SES v1・Secrets Manager)と、Google と GitHub のログインの代わりを Go で自作する** — 「fakeaws と fakeoidc」

- Issue の記載: なし
- 決めたこと: LocalStack は CI に認証トークンが無く、moto は送ったメールを HTTP で読めないため、自作する。fakeaws は署名と権限を調べない
- 他にありえた選択肢: moto の server mode(メールの比べを諦める)。LocalStack のトークンを CI の秘密に足す
- 外れていた場合: Java 版の Spring Cloud AWS が自作の代わりの応答を受け付けない形(XML の細部など)があると、比べる検査が Java 版を起動できず、代わりを作り直す

**10. Go の部品の公開の時刻を index.golang.org を `since` で順に読んで調べる** — 「Dependabot と公開の時刻の検査と脆弱性の直し」

- Issue の記載: なし
- 決めたこと: proxy.golang.org の `.info` は後から古い時刻にできるので使わず、索引の取り込みの時刻を使う
- 他にありえた選択肢: GitHub のリリースの `published_at`。deps.dev の API
- 外れていた場合: 問い合わせの数で検査が遅くなるか、索引の読み取りが失敗して PR が止まる

**11. Go のモジュールを Java 版と同じ `backend/` に置く** — 「全体の構成」「ファイルの構成」

- Issue の記載: なし
- 決めたこと: `backend/go.mod` を置き、`backend/src/` の Java 版と同居させる。CI は変わったファイルの種類で仕事を分ける
- 他にありえた選択肢: `backend-go/` に置き、段階6で `backend/` に移す
- 外れていた場合: Java 版の Dockerfile.prod の組み立ての文脈 `./backend` に Go のファイルが入る。段階6のフォルダの移しは要らなくなる

### 指摘

| ID | レベル | 該当箇所 | 内容 | 直し方の案 |
|---|---|---|---|---|
| D2-1-1 | 中 | design.md 「CodeQL とイメージの検査と組み立てて動かす検査」(`docker-smoke` の文)、「所有者に提案するゲート設定の変更」の表の `ci.yaml` の行(2-1)、「backend-deploy.yaml と release.yaml」(組み立ての文脈はどちらも `./backend`) | `docker-smoke` は「今の Java 版のイメージと同じく、Go 版の本番のイメージを組み立てられることを確かめる」とあるが、今の `ci.yaml` の `docker-smoke`(379〜382行目)は、組み立ての文脈を `case "$f" in docker/backend/Dockerfile.prod) context="./backend" ;; *) context="." ;;` で決めている。`docker/backend-go/Dockerfile.prod` は `*` に当たり、文脈 `.`(リポジトリの最上位)で組み立てられる。設計の Dockerfile.prod は文脈 `./backend` を前提にする(`go.mod` やフォントを `backend/` の中の相対の場所から写す)ので、2-2 の PR で `docker-smoke`(`docker/**/Dockerfile*` の変更で動く必須の検査)が失敗し、2-2 が main に入らない。直すには `ci.yaml`(ゲート設定)の変更が要るが、2-1 の `ci.yaml` の変更は「backend の仕事の分割」だけで、`docker-smoke` の文脈の分岐の追加が無い。承認済みの 2-1 のあとに、ゲート設定の PR をもう1つ足して戻ることになる | 2-1 の `ci.yaml` の変更に、`docker-smoke` の文脈の分岐に `docker/backend-go/Dockerfile.prod) context="./backend"` を足すことを書く(段階6で `docker/backend/` に戻すときはこの分岐も戻す)。「CodeQL とイメージの検査と組み立てて動かす検査」の `docker-smoke` の文に、この分岐を足す理由(文脈は `backend-deploy.yaml` と同じにする、と ci.yaml 377〜378行目のコメントが求めている)を書く |
| D2-1-2 | 中 | design.md 「作らないもの」(GitHub の ruleset の変更)、「所有者に提案するゲート設定の変更」の最後の段(期待一覧は変えない)、「使う既存の仕組み」の「品質の仕組み」、「Dependabot と公開の時刻の検査と脆弱性の直し」(dependency-review は設定を変えずに Go の部品も調べる)、「段階6の削除と書き換え」の 6-1、「段階6の書き換え」の「設定とスクリプト」(`.github/` のワークフローとスクリプトと設定) | 必須の検査の期待一覧 `.github/audit/required-checks.json` には、Gradle を前提にした必須の検査が `always` で載っている。`gradle-wrapper`(`guardrails.yaml`。`check-gradle-wrapper.sh` は `gradle/wrapper/` の差分を対象にし、`gradle-wrapper.properties` が1つも見つからないと失敗にする。89行目)と、`dependency-graph-generate`(`dependency-review.yaml`。`actions/setup-java` と `gradle/actions/dependency-submission` を `build-root-directory: backend` で動かし、`check-dependency-snapshot.sh` が空なら失敗にする)である。`dependency-review`(`always`)は `needs.generate.result == 'success'` を条件にするので、`generate` が失敗すると動かず、必須の検査の結果が無いままになる。6-1 で Gradle の設定と wrapper を消すと、6-1 の PR でこの3つが赤か結果なしになり、6-1 自身が main に入らない。本文は、`.github/` の扱いを「Go 版の道具に替えるか、Java 版の分を消す」と一括りに書くだけで、この3つを(a)名前を残して中身を Go 版に替えるのか、(b)消して所有者が ruleset と期待一覧から外すのかを決めていない。(b)は「作らないもの」の「ruleset の変更」と「期待一覧は変えない」に反し、要件 7.1 の6つの操作にも無い(7.2 で理由を添えて頼む操作になる)。`gradle-wrapper` は Gradle が無いと中身を替えようが無いので、(a)だけでは済まない。main への push で動く `dependency-graph.yaml` も同じ Gradle の仕事を持つ。設計の「dependency-review は `go.mod` を読むので設定を変えずに Go の部品も調べる」は、`generate` が成功している間だけ成り立つ | 「段階6の削除と書き換え」か「段階6の書き換え」に、必須の検査のうち Gradle を前提にするもの(`gradle-wrapper` `dependency-graph-generate` `dependency-graph-submit` `dependency-review`)の扱いを1つずつ書く。たとえば、`dependency-graph-generate` と `dependency-graph-submit` と `dependency-review` は名前を残し、中身を Go 版(GitHub が `go.mod` を自分で読むので、生成と送信は要らない。`dependency-review` の `needs` と条件を直す)に替える。`gradle-wrapper` は、所有者が ruleset から外し、期待一覧から消す操作を、6-1 の所有者の操作として表に足し、「作らないもの」の「ruleset の変更」を「必須の検査の名前を増やす変更はしない。段階6で Java 版だけの検査の名前を外す操作は所有者がする」に直す。`dependency-graph.yaml` の Gradle の仕事の扱いも同じ節に書く |
| D2-1-3 | 低 | design.md 「api-docs」(「Try it out」の宛先は仕様書の `servers` の `http://localhost:8081`)、「openapi.yaml」(比べる検査で食い違った箇所だけ直す)、「config」と「fakeaws と fakeoidc」(dev の CORS は `http://localhost:5173`) | 今の `backend/api/openapi.yaml` の `servers` は `url: /` であり、`http://localhost:8081` ではない。仕様書を直すのは「比べる検査で Java 版の応答と食い違った箇所だけ」と書いているので、`servers` の変更がどの PR に入るかが本文から読めない。また、説明画面(`localhost:8082`)から Go 版(`localhost:8081`)へ送る要求は送り元が違うので、Go 版の `dev` の CORS が `http://localhost:5173` だけを許す設定のままだと、ブラウザが応答を読まず「Try it out」は動かない。要件 14 は説明画面を開けることだけを求めるので、実装には影響しない | 「api-docs」に、`servers` を `http://localhost:8081` にする変更を 2-4 で入れると書く。「Try it out」を使えるようにするなら、`dev` の CORS の許す送り元に `http://localhost:8082` を足すと書き、使えなくてよいなら「Try it out」の文を消す |
| D2-1-4 | 低 | design.md 「CI の仕事」の見分けの一覧と「マイグレーションのファイルの変更は3つのすべてに当たる」の文 | `backend_java` は `backend/src/**` を含むが、`backend_go` の形(`backend/**/*.go` `go.mod` `go.sum` `Makefile` 検査の設定 `backend/api/**` `sqlc.yaml` `docker/backend-go/**`)には `backend/src/main/resources/db/migration/**` が無い。マイグレーションのファイルを変えても `backend_go` は当たらず、「3つのすべてに当たる」と合わない。Go 版は `migrations.go` でこのファイルを埋め込み、migrate の単体テストが検査の値を計算するので、Go 版の品質チェックも動くべき箇所である。この spec ではマイグレーションを足さない(1.5)ので、実装には影響しない | `backend_go` の形に `backend/src/main/resources/db/migration/**` を足す(段階6で `backend/db/migrations/**` に直す) |
| D2-1-5 | 低 | design.md 「perf」の比べる操作(11個)と「テストの方針」の「perf の12の操作」 | 「perf」の比べる操作は、ログイン、トークンの更新、利用者の情報の取得、経歴書の一覧・取得・基本情報の保存・職歴の追加、PDF の出力、Markdown の出力、バックアップの書き出し・戻しの11個である。「テストの方針」は「perf の12の操作」と書く。数が合わない | どちらかに合わせる(操作を1つ足すか、「11の操作」に直す) |
| D2-1-6 | 低 | design.md 「Dockerfile.prod」(フォントは `backend/src/main/resources/fonts/` から写す)、「段階6の削除と書き換え」の 6-1 | 6-1 で Java 版のコードを消し、マイグレーションのファイルは `backend/db/migrations/` に移すと書いているが、Go 版の本番のイメージが写すフォントのファイル(`backend/src/main/resources/fonts/` の4つ)の移し先が書かれていない。`backend/src/` を消すと Dockerfile.prod の `COPY` が失敗する。6-1 の組み立てで必ず失敗し、同じ PR で直せるので、実装には影響しない | 6-1 の箇条に、フォントのファイルを `backend/fonts/` などに移し、Dockerfile.prod の `COPY` も直すことを書く |
| D2-1-7 | 低 | design.md のサイクル1で「記録のみ」とされた低の指摘の箇所 | 作り直した本文にも、サイクル1の低の指摘がそのまま残っている。D1-1-8(「httpapi」: 仕様書に無い経路は 404 と書いた直後に `/actuator/health` と `/healthz` を登録)、D1-1-9(「作らないもの」の「frontend のコードを変えない」と「消す一覧」の `@react-router/*` の削除、`knip.json` の2行)、D1-1-10(「変更は、すべて下の表に分けて書き」と段階6の変更が表に無いこと)、D1-1-11(`dependabot.yml` の「docker の項目の追加」は `directories: - "/docker/*"` で追加が要らない)、D1-1-12(`check-release-age.sh` は `dependency-review.yaml` の「Check CI tool release age」で CI の道具のイメージの公開日時を見るスクリプトで、gomod の公開の時刻の検査は `check-dependency-cooldown.sh` の行と二重)、D1-1-13(GitHub の `/user/emails` の URL を替える環境変数が無い)、D1-2-4(候補の表に、変えるかを決める主体と時期が無い)、D1-2-5(ビルドタグを付けるのは `harness/` だけなのに「安全」は AWS とログインの代わりがタグの中にあると書く)。どれも実装には影響しない | サイクル1の各指摘の直し方の案のとおり |

### 前の段階への指摘

| ID | 対象 | 該当箇所 | 内容 |
|---|---|---|---|
| (なし) | | | |

- 往復: 1回目 / 高0 中2 低5

## サイクル2 往復2(2026-11-08)

### 審査の範囲

範囲: 差分

- design.md 「段階6の削除と書き換え」の 6-1 の表と、Gradle を前提にする必須の検査の表と箇条(D2-1-2 の直し): `.github/audit/required-checks.json`(`dependency-graph-generate` `dependency-review` `gradle-wrapper` が `always`、`dependency-graph-submit` `dependency-cooldown` が `conditional`)、`.github/workflows/dependency-review.yaml`(`review` は `needs.generate.result == 'success' && needs.submit.result != 'failure'`、`cooldown` は両方の `success` を条件にする)、`.github/workflows/dependency-graph.yaml`(main への push で Gradle の生成と送信をする)、`.github/workflows/guardrails.yaml` の `gradle-wrapper` の仕事(`check-gradle-wrapper.sh` とそのテストと `wrapper-validation`)を読み、4つの検査の名前と条件と、「今の中身のままでは失敗するか結果を出さず」が事実と合うことを確かめた。合っている
- design.md 「作らないもの」の必須の検査の行、「所有者に提案するゲート設定の変更」の最後の段、「設計を見直すきっかけ」の ruleset の行: 6-1 で期待一覧から `gradle-wrapper` の行を消し、所有者が ruleset から外すことと食い違わないかを確かめた。「作らないもの」は「足さない」に限る書き方になり、最後の段は「段階5まで変えない」と段階6の参照に直され、食い違いは無い。「設計を見直すきっかけ」の行は外から ruleset が変わったときの決まりで、6-1 の計画した変更と矛盾しない
- requirements.md 要件7 の 7.1 と 7.2: ruleset から `gradle-wrapper` を外す操作が 7.1 の6つの操作に無いので、7.2 の「操作が要る理由と、Claude が自分でできない理由を添えて頼む」を 6-1 の箇条が満たすかを確かめた。理由(ruleset を変えられるのが所有者だけ)と頼み方(PR の本文の「承認が要る理由」の欄)が書かれている。対応する要件の番号の付け方は指摘 D2-2-1
- design.md 「CodeQL とイメージの検査と組み立てて動かす検査」の `docker-smoke` の文、「所有者に提案するゲート設定の変更」の `ci.yaml` の行、6-1 の分岐を消す文(D2-1-1 の直し): `.github/workflows/ci.yaml` 377〜382行目(説明が compose.yaml と backend-deploy.yaml の指定に合わせるよう求め、`docker/backend/Dockerfile.prod` だけ `./backend`)と `compose.yaml`(開発用の Dockerfile はすべて文脈 `.`)を読み、足す分岐が `Dockerfile.prod` だけでよいことと、6-1 で `docker/backend-go/` を `docker/backend/` に戻せば今の分岐がそのまま当たるので分岐の行を消してよいことを確かめた。影響なし
- design.md 「使う既存の仕組み」の「品質の仕組み」: 「次の11個」と箇条の数(11)が合うことを確かめた。影響なし
- design.md 「段階6の削除と書き換え」の 6-4 の検査の「次の5つ」と、箇条の外に出した2つの段: 箇条が5つであることと、外に出した2つの段(検索の形が拾う語、確かめた結果)の中身が往復1と同じであることを確かめた。影響なし
- design.md 「runbook.md」の操作1、requirements.md 5.3: 言い換えのあとも、打つコマンド(`terraform apply`)と見分け方(`keirekipro/redis` にキー `redis-username` があること)が残っていることを確かめた。影響なし
- design.md 「概要」「依存の向きの制約」「migrate」「httpapi」「pdf」「openapi.yaml」「変えた動きの一覧」「Dockerfile.prod」「まとまりの分け方と順番」「性能」「安全」「残すもの」の `REVIEW.md`: 主語の追加と文の分割だけで、設計の中身が変わっていないことを前後の文で確かめた。影響なし

### 申告

**1. 段階6で、`dependency-graph-submit` の中身を `actions/go-dependency-submission` に替え、PR の merge commit を取り出して `go list` を動かす仕事を、送信の権限(`contents: write`)を持つ仕事の中で動かす** — 「段階6の削除と書き換え」の 6-1 の必須の検査の表と箇条

- Issue の記載: なし
- 決めたこと: `dependency-graph-generate` は `go mod verify` だけにし、部品の一覧の作成と送信は `dependency-graph-submit` の `actions/go-dependency-submission` が1つの仕事で行う
- 他にありえた選択肢: 今の `dependency-review.yaml` の冒頭の説明にある分け方(読み取りの権限の仕事で一覧を作り、取り出しをしない仕事で送るだけ)を Go 版でも保つ。GitHub は `go.mod` を自分で読むので、送信をやめて `dependency-graph-submit` を一覧の有無の確かめだけにする
- 外れていた場合: `go list` は Gradle のビルドスクリプトのように PR のコードを実行しないので、今の分け方の理由(PR が持ち込んだビルドスクリプトを書き込みの権限で実行しない)は Go 版では弱くなる。ただし、`submit` は同じリポジトリの PR だけで動くので、影響は小さい。所有者がこの分け方を Go 版でも守りたいときは、6-1 の `dependency-review.yaml` の形を直すことになる

### 指摘

| ID | レベル | 該当箇所 | 内容 | 直し方の案 |
|---|---|---|---|---|
| D2-2-1 | 低 | design.md 「段階6の削除と書き換え」の対応する要件(6.1, 6.2, 6.3, 6.4, 15.1〜15.4, 16.1〜16.3)と、「progress.md」の対応する要件(7.2 を含む) | 6-1 で所有者が ruleset から `gradle-wrapper` を外す操作は、要件 7.1 の6つの操作に無い操作で、7.2(理由と、Claude が自分でできない理由を添えて頼む)に当たる。この操作の理由と頼み方は「段階6の削除と書き換え」に書かれているが、その節の対応する要件に 7.2 が無く、7.2 は「progress.md」の対応する要件にだけある。「progress.md」の本文には 7.2 の操作を頼む決まりの文が無い。tasks で 7.2 のタスクを「段階6の削除と書き換え」に結びつけにくいだけで、実装には影響しない | 「段階6の削除と書き換え」の対応する要件に 7.2 を足す |
| D2-2-2 | 低 | design.md 「段階6の削除と書き換え」の `gradle-wrapper` の箇条(所有者は、6-1 の PR を承認するときに、GitHub の ruleset から `gradle-wrapper` を外す) | 所有者が ruleset から `gradle-wrapper` を外してから 6-1 が main に入るまでの間、main の期待一覧には `gradle-wrapper` の行が残る。CLAUDE.md のとおり、週次監査は期待一覧と ruleset の食い違いを報告するので、この間に週次監査が動くと、食い違いを1回報告する。6-1 が入れば解消し、実装には影響しない | `gradle-wrapper` の箇条に、外してから 6-1 が入るまでの間に週次監査が食い違いを報告することがあり、6-1 が入れば解消する、と1文を足す。または、外す時期を「6-1 の PR のほかの検査がすべて通ったあと」と書く |

### 前の段階への指摘

| ID | 対象 | 該当箇所 | 内容 |
|---|---|---|---|
| (なし) | | | |

- 往復: 2回で収束 / 未解決: 0件

## サイクル3 往復1(2026-11-08)

### 審査の範囲

範囲: 差分

- design.md 「compat harness」の「イメージの組み立て方」の表と箇条(fakeaws と fakeoidc の Dockerfile、`golang:1.27.3-trixie`、distroless の土台)、「Dependabot と公開の時刻の検査と脆弱性の直し」(`backend-vuln-fix` が上げる版の置き場所)、`.github/dependabot.yml`(docker の項目は `directories: - "/docker/*"`): 差分で golang の工程を持つ Dockerfile が `backend/compat/` の下に2つ増えたので、その中の版を上げる仕組みがあるかを確かめた(指摘 D3-1-1)
- design.md 「作るもの」の Go 版の土台の行、「ファイルの構成」の `server.go` の行、「httpapi」の役割: 差分で 501 の仮の実装の記述が2か所から消えたので、3か所目(httpapi の役割)と合うかを確かめた(指摘 D3-1-2)
- design.md 「CI の仕事」の `backend-compat` の箇条と、「compat harness」の「イメージの組み立ての方」の冒頭の段: 差分で「比べる検査が毎回6つのイメージを組み立てる」が足されたので、CI の仕事の「本番のイメージを組み立て」と重ならないかを確かめた(指摘 D3-1-3)
- design.md 「runbook.md」の役割と操作1〜5、requirements.md 5.3: 差分で「操作ごとに、押す場所か打つコマンドと、うまくいったかの見分け方を書く」の文が消えたので、5つの操作に見分け方が残っているかと、5.3 の求めることとの関係を確かめた(指摘 D3-1-4)
- design.md 「段階6の削除と書き換え」の `gradle-wrapper` の箇条、requirements.md 7.2: 差分で「ruleset を変えられるのが所有者だけ」の理由の文が消えたので、7.2 の「Claude が自分でできない理由を添えて頼む」の裏付けが残っているかを確かめた(指摘 D3-1-5)
- design.md 「ファイルの構成」の `backend/compat/` の4行(ビルドタグ `compat` を全部に付ける)、「Makefile」の `make check` の中身と `.golangci.yml`: 差分で `backend/compat/` の全部のコードがビルドタグの中に入ったので、`make check` の `fmt-check` `lint` `build` がこのコードを読むかを確かめた(指摘 D3-1-6)
- design.md 「所有者に提案するゲート設定の変更」の表の `check-verify-before-stop.sh` の行と箇条、`.claude/hooks/check-verify-before-stop.sh` と `.claude/hooks/tests/test-check-verify-before-stop.sh`: 「今は `backend/` の下のファイルが変わると `./gradlew check` の記録を求める」が事実と合うか(フックは `backend/*` の変更に `.claude/.state/gate-run-backend.txt` を求め、この記録は `run-check.sh` が `./gradlew check` のときだけ書く)と、テストのファイルがあることを確かめた。合っている。影響なし
- design.md 「所有者に提案するゲート設定の変更」の `run-check.sh` の箇条、「backend-go(開発環境と品質チェックのサービス)」、`.claude/scripts/parallel/run-check.sh`: `/repo` の読み取り専用の差し込みと `make check` の記録の書き方が、今の `run-check.sh` の形(領域ごとの `-v` の追加、最後の検査のコマンドの照合で記録を書く、`backend` のときだけ dind を起こす)に足せるものかを確かめた。足せる。影響なし
- design.md 「compat harness」の「イメージの組み立て方」の表(Postgres と Redis の組み立ての材料の場所)、`docker/db/Dockerfile` `docker/redis/Dockerfile` `compose.yaml`: compose はこの2つを文脈 `.` で組み立てるが、どちらの Dockerfile も `FROM` だけで `COPY` が無いので、文脈を `docker/db/` `docker/redis/` にしても組み立てられることを確かめた。影響なし
- design.md 「ファイルの構成」の `backend/assets/fonts.conf`、「Dockerfile.prod」、6-1 の箇条(`backend/assets/fonts/`)、`backend/.dockerignore`: `assets/` が `.dockerignore` で除かれないことと、3か所の置き場所が合うことを確かめた。影響なし
- design.md 「CI の仕事」の `backend_compat` の見分けと理由の段、「段階ごとの PR」の 2-1〜2-3、`.github/workflows/ci.yaml` の `detect-changes`(`dorny/paths-filter`): 「2-1 から 2-3 の間に `backend-compat` が動いて失敗する」が、今の見分けの形(paths-filter はファイルの変更だけを見る)と段階ごとの PR の中身から事実と合うことを確かめた。フォルダの有無は paths-filter で書けないので `detect-changes` に1つステップを足す形になるが、本文の決めごとと矛盾しない。影響なし
- design.md 「ファイルの構成」の `docker/backend-go/Dockerfile`(Debian の `chromium` と `fonts-noto-cjk`)、「CI の仕事」の PDF の単体テストの箇条、「pdf」(chromedp): 3つの環境(開発環境の `chromium`、CI の Google Chrome、本番の `headless-shell`)で PDF の部品が Chromium を見つけられるかを確かめた。chromedp の既定の探し方は `headless-shell` `chromium` `google-chrome` を PATH から探すので、本文に実行ファイルの場所の指定が無くても成り立つ。影響なし
- design.md 「変えた動きの一覧の形」の候補の表(まとまりの列が番号から名前に変わった)、「まとまりの分け方と順番」の表: 1=認証、2=利用者、3=マスタと経歴書、5=バックアップの対応が合うことを確かめた。影響なし
- design.md 「段階4の本番の設定の変更」(値を足すとした2つの行)、「本番の設定の値の変わり方」の表: 段階4の列で足すのは `KEIREKIPRO_ENV` と `redis-username` の2行であることを確かめた。影響なし
- design.md 「Java 版に戻す条件」の見出し: 旧の見出し「戻す条件」を参照する箇所が本文に無いことを Grep で確かめた。影響なし
- design.md 「作らないもの」「使う既存の仕組み」の dependency-cooldown、「プロジェクトの決まりを守っているか」の ArchUnit と関係のない項目、「httpapi」「pdf」「api-docs」「Dependabot」「CodeQL とイメージの検査と組み立てて動かす検査」の3つの箇条、「backend-deploy.yaml」、「本番の設定の値の変わり方」の表の見出し: 主語の追加、語の説明の追加、箇条への分け直しだけで、設計の中身が変わっていないことを前後の文で確かめた。影響なし

### 申告

**1. 比べる検査の fakeaws と fakeoidc を、`golang:1.27.3-trixie` の工程と distroless の土台を持つ Dockerfile から、比べる検査が毎回組み立てるコンテナのイメージにする** — 「compat harness」の「イメージの組み立て方」、「ファイルの構成」の `backend/compat/fakeaws/` `backend/compat/fakeoidc/`

- Issue の記載: なし
- 決めたこと: 代わりのサーバを Docker のネットワークの中のコンテナにし、Java 版と Go 版が `fakeaws` `fakeoidc` の名前で呼べるようにする。イメージは Dockerfile の中で `go build -tags compat` して作る
- 他にありえた選択肢: 比べる検査の処理(`go test`)の中で `go build -tags compat` して実行ファイルを作り、golang の工程を持たない Dockerfile(distroless に実行ファイルを置くだけ)で組み立てる。または、代わりのサーバをテストの処理の中(ホスト側)で動かし、コンテナからは `host.docker.internal` などで呼ぶ
- 外れていた場合: golang の版が `go.mod` と `docker/backend-go/` の2つの Dockerfile と `backend/compat/` の2つの Dockerfile に重なり、上げ忘れた Dockerfile で組み立てが失敗する(指摘 D3-1-1)。ホスト側で動かす形に替えると、転送先の URL の比べ方(「`fakeoidc` の名前を元のまま比べる」)も作り直す

**2. 比べる検査が、Java 版と Go 版と Postgres と Redis と fakeaws と fakeoidc の6つのイメージを、検査のたびに testcontainers-go で Docker に組み立てさせる。そのために `run-check.sh` がリポジトリの最上位を読み取り専用で `/repo` に差し込む** — 「compat harness」の「イメージの組み立て方」、「所有者に提案するゲート設定の変更」の `run-check.sh`

- Issue の記載: なし
- 決めたこと: 組み立て済みのイメージを使わず、`KEIREKIPRO_REPO_ROOT` の下の Dockerfile から毎回組み立てる。開発環境ではホストの Docker のイメージが dind から見えないためである
- 他にありえた選択肢: ホストで組み立てたイメージを `docker save | docker load` で dind に写す。dind をやめてホストの Docker のソケットを差し込む
- 外れていた場合: Java 版のイメージの組み立て(Dockerfile.prod の中の Gradle のビルド)が、開発環境の dind で毎回数分かかり、`make compat` が開発者の手で回しにくくなる。Docker の組み立てのキャッシュが dind の中に残る間は短く済むが、dind を作り直すと最初からになる

**3. PDF を作る部品の単体テストは、その機械にある Chromium(開発環境のイメージは Debian の `chromium`、CI は GitHub の機械の Google Chrome)を、版を固定せずに使う** — 「ファイルの構成」の `docker/backend-go/Dockerfile`、「CI の仕事」の PDF の単体テストの箇条

- Issue の記載: なし
- 決めたこと: 単体テストは PDF を作れることと同時の数と時間切れの扱いだけを確かめ、本番と同じ Chromium での見た目は比べる検査が本番のイメージで確かめる
- 他にありえた選択肢: 開発環境のイメージと CI に本番と同じ `chromedp/headless-shell` の実行ファイルを入れ、同じ版で単体テストを動かす。単体テストを本番のイメージの中で動かす
- 外れていた場合: GitHub の機械の Google Chrome の版が上がったときに、起動の引数(`--headless` など)の扱いが変わると、`backend-go` の仕事だけが Go 版のコードの変更と無関係に赤くなり、直すまで Go 版の PR が止まる

**4. 作業を終えるときのフック `check-verify-before-stop.sh` を、変わったファイルを Java 版と Go 版に分けて、それぞれの記録を求める形にする(見分けは CI の `backend_java` `backend_go` と同じ)** — 「所有者に提案するゲート設定の変更」の `check-verify-before-stop.sh` の行と箇条

- Issue の記載: なし
- 決めたこと: Java 版のファイルが変わったときは `./gradlew check` の記録、Go 版のファイルが変わったときは `make check` の記録、マイグレーションのファイルが変わったときは両方の記録を求める。段階6で元の1つの形に戻す
- 他にありえた選択肢: `backend/` の下の変更に両方の記録を求める(単純だが、Go 版だけの会話でも Java 版の品質チェックが要る)。領域を `backend` の1つのままにし、`run-check.sh backend` が両方の品質チェックを動かす
- 外れていた場合: 見分けのどちらにも当たらないファイル(`backend/compat/` の筋書きと初めのデータ、`backend/assets/`、`backend/*.md`)の変更は、どの記録も求められずに作業を終えられる。今は `backend/` の下のすべての変更に Java 版の記録を求めているので、この分だけ守りが狭くなる。守りを保ちたければ、どちらにも当たらないファイルに Go 版の記録を求める形にする

### 指摘

| ID | レベル | 該当箇所 | 内容 | 直し方の案 |
|---|---|---|---|---|
| D3-1-1 | 中 | design.md 「compat harness」の「イメージの組み立て方」の箇条(fakeaws と fakeoidc の Dockerfile は `golang:1.27.3-trixie` で `go build -tags compat` を動かし、`gcr.io/distroless/static-debian13:nonroot` に置く。2つの土台は digest で固定する)、「Dependabot と公開の時刻の検査と脆弱性の直し」(`backend-vuln-fix` の Go の仕事は `go.mod` の `toolchain` と `docker/backend-go/` のイメージの版を上げる)、「所有者に提案するゲート設定の変更」の `.github/dependabot.yml` の行 | 差分で足した2つの Dockerfile は `backend/compat/` の下にあり、`FROM` の版を上げる仕組みのどれにも入っていない。今の `dependabot.yml` の docker の項目は `directories: - "/docker/*"` で、`backend/compat/fakeaws/` と `backend/compat/fakeoidc/` を見ない(設計の 2-5 の変更も「gomod と docker の項目の追加」で、この2つのフォルダを足すとは書いていない)。`backend-vuln-fix` の Go の仕事が Go の標準ライブラリの脆弱性で上げるのも「`go.mod` の `toolchain` と `docker/backend-go/` のイメージの版」だけである。公式の `golang` のイメージは `GOTOOLCHAIN=local` を設定しているので、`go.mod` の `go` か `toolchain` の版が 1.27.3 を超えた時点で、この2つの Dockerfile の `go build -tags compat` は「go.mod requires go >= …」で失敗し、`backend-compat` が失敗して必須の検査 `backend-test` が赤になる。Go の版を上げる PR(Dependabot の gomod、`backend-vuln-fix` の PR、Claude が手で上げる PR)のたびに、この2つの Dockerfile を手で直す作業が本文に無いまま残り、最初に上げる PR で必ず発覚して戻って直すことになる。distroless の digest も同じく、どの仕組みも上げない | 次のどちらかにする。(a)golang の版の重なりを無くす: 比べる検査の処理が `go build -tags compat` で fakeaws と fakeoidc の実行ファイルを作り、Dockerfile は distroless の土台に実行ファイルを置くだけにする。この Dockerfile を `docker/fakeaws/` `docker/fakeoidc/` に置けば、distroless の digest は今の docker の項目(`/docker/*`)で Dependabot が上げる。(b)重なりを残して上げる仕組みに入れる: 2-5 の `dependabot.yml` の docker の項目の `directories` に `/backend/compat/fakeaws` と `/backend/compat/fakeoidc` を足し、`backend-vuln-fix` の Go の仕事が上げるイメージの版の置き場所にこの2つの Dockerfile を足すと書く。あわせて「所有者に提案するゲート設定の変更」の `dependabot.yml` の行の中身を直す |
| D3-1-2 | 低 | design.md 「作るもの」の Go 版の土台の行(「…`backend/api/openapi.yaml` からコードを生成し」で文が終わる)、「ファイルの構成」の `backend/internal/httpapi/server.go` の行、「httpapi」の役割 | 「作るもの」の文が「コードを生成し」で途切れている。差分で、この文の後半(まだ作っていない操作に 501 を返す仮の実装を置く)と、`server.go` の行の「まだ作っていない操作は 501 を返す」が消えたが、「httpapi」の役割には「まだ作っていない操作は、501 と `{"message":"未実装です。"}` を返す仮の実装で満たす」が残っている。親の起動の文では、今回の直しは7つの足りない点と中身の変わらない直しであり、501 の仮の実装を消す意図は無い。部品の節に残っているので実装には影響しないが、「作るもの」と「ファイルの構成」からは読めない | 「作るもの」の文を「…からコードを生成し、まだ作っていない操作には 501 を返す仮の実装を置く」に戻し、`server.go` の行にも「まだ作っていない操作は 501 を返す」を戻す。仮の実装を消す意図なら、「httpapi」の役割の文も消し、2-2 から 2-3 の間に Go 版がどう組み立てられるか(生成した `StrictServerInterface` のすべての操作を何で満たすか)を書く |
| D3-1-3 | 低 | design.md 「CI の仕事」の `backend-compat` の箇条(poppler-utils を apt で入れ、Java 版と Go 版の本番のイメージを組み立て、`make compat` と `make compat-cross` を動かす)、「compat harness」の「イメージの組み立て方」の冒頭の段(比べる検査は、検査の始めに、6つのイメージを組み立てる。組み立て済みのイメージを使わず、毎回 Docker に組み立てさせる) | 差分で「比べる検査自身が毎回6つのイメージを組み立て、組み立て済みのイメージを使わない」と決めたのに、`backend-compat` の仕事の箇条は、仕事の側で「Java 版と Go 版の本番のイメージを組み立て」てから `make compat` を動かすと読める。仕事の側で組み立てても比べる検査は使わないので、二重の組み立てになるか、本文のどちらかが誤っている。`make compat` と `make compat-cross` を別の `go test` として動かすので、比べる検査の側の組み立ても2回ある(Docker の組み立てのキャッシュで2回目は短い)。実装には影響しない | `backend-compat` の箇条を「poppler-utils を apt で入れ、`KEIREKIPRO_REPO_ROOT` にチェックアウトしたフォルダを渡して `make compat` と `make compat-cross` を動かす。イメージは比べる検査が組み立てる」に直す |
| D3-1-4 | 低 | design.md 「runbook.md」の役割(差分で消えた文「手順書は、操作ごとに、押す場所か打つコマンドと、うまくいったかの見分け方を書く」)、requirements.md 5.3 | この文は、サイクル1 往復2の指摘 D1-2-3(中)への直しで戻した文であり、受入基準 5.3 の「操作ごとに、押す場所か打つコマンドと、うまくいったかの見分け方を書く」を裏付ける唯一の一般の決まりだった。今回の差分で再び消えた。今は5つの操作のそれぞれに見分け方が書かれているので、D1-2-3 のときと違い、本文に書いた操作に見分け方の無いものは無い。ただし「手順書には次の操作を含める」なので、手順書の3つの場面(切り替え、Java 版に戻す、もう一度切り替える)には5つのほかの操作も入りうる。その操作に見分け方を書く決まりが design から無くなった。実装(手順書の書き方)への影響は小さい | 消えた文を1文で戻す(「手順書は、5つの操作のほかの操作にも、押す場所か打つコマンドと、うまくいったかの見分け方を書く」) |
| D3-1-5 | 低 | design.md 「段階6の削除と書き換え」の `gradle-wrapper` の箇条(差分で消えた文「所有者が外すのは、ruleset を変えられるのが所有者だけだからである」)、requirements.md 7.2 | ruleset から `gradle-wrapper` を外す操作は、7.1 の6つの操作に無い操作なので、7.2 が「操作が要る理由と、Claude が自分でできない理由を添えて、所有者に頼む」ことを求める。サイクル2 往復2では、消えた文がその「Claude が自分でできない理由」であることを確かめて通した。今回の差分でこの文が消え、PR の本文に書く項目(この操作と、GitHub の画面で押す場所と、外せたかの見分け方)にも「Claude が自分でできない理由」が無い。6-1 の PR の本文に理由を書く根拠が design から無くなった。手順書と PR の本文の書き方の問題で、実装には影響しない | `gradle-wrapper` の箇条の PR の本文に書く項目に「Claude が自分で外せない理由(ruleset を変えられるのは所有者だけ)」を足す。または消えた1文を戻す |
| D3-1-6 | 低 | design.md 「ファイルの構成」の `backend/compat/` の4行(harness、fakeaws、fakeoidc、pdfcmp のすべてにビルドタグ `compat` を付ける)、「Makefile」の `make check`(`fmt-check` `generate-check` `lint` `test` `coverage` `build`)、「.golangci.yml と .testcoverage.yml と .gremlins.yaml」 | 差分で `backend/compat/` の下の Go のコードがすべてビルドタグ `compat` の中に入った。golangci-lint は、`run.build-tags` に `compat` を書かないと、ビルドタグで除かれるファイルを読まない。`make check` の `fmt-check` と `lint` と `build` はビルドタグを付けないので、比べる検査の本体と代わりのサーバと PDF の比べ方のコード(段階2以降ずっと保守するコード)は、書式の検査、静的な検査、gosec などの検査、組み立ての確認のどれにも掛からず、`backend-compat` の `go test -tags compat` で組み立てられるときにだけ誤りが分かる。`.golangci.yml` は所有者の承認の対象なので、あとから足すとゲート設定の PR がもう1つ要る。本文は、このコードを検査の対象に入れるか、入れない判断かを書いていない | 「.golangci.yml と .testcoverage.yml と .gremlins.yaml」に、`.golangci.yml` の `run.build-tags` に `compat` を書き、`make lint` と `make fmt-check` が `backend/compat/` のコードも読むようにすると書く。`make build` にも `go build -tags compat ./compat/...` を足すか、`make lint` の `go vet` で代える。検査の対象に入れないなら、入れない理由を書く |

### 前の段階への指摘

| ID | 対象 | 該当箇所 | 内容 |
|---|---|---|---|
| (なし) | | | |

- 往復: 1回目 / 高0 中1 低5

## サイクル3 往復2(2026-11-08)

### 審査の範囲

範囲: 差分

- design.md 「Dependabot と公開の時刻の検査と脆弱性の直し」の役割の段と `backend-vuln-fix` の段(D3-1-1 の直し)、`.github/dependabot.yml` の docker の項目(88〜118行目): 「今の docker の項目は `docker/` の下のフォルダだけを見る」が `directories: - "/docker/*"` と合うこと、足す2つのフォルダに Dockerfile があること(「ファイルの構成」の `backend/compat/fakeaws/` `backend/compat/fakeoidc/` の行と「イメージの組み立て方」の表)、`open-pull-requests-limit: 10` とその上のコメント(digest の更新はフォルダごとの個別の PR になるので、上限はフォルダの数を下回らない値にする)が、足したあとのフォルダの数と合うかを確かめた(指摘 D3-2-2)
- design.md 「段階6の削除と書き換え」の 6-1 の2つの箇条(消すものの一覧と、移行のための条件を消す一覧)、「ファイルの構成」の `backend/compat/`: 差分で `backend/compat/` の下の2つのフォルダが `dependabot.yml` の docker の項目に入ったので、6-1 で `backend/compat/` を消すときに、この2つのフォルダを `dependabot.yml` から消すことが書かれているかを確かめた(指摘 D3-2-1)
- design.md 「所有者に提案するゲート設定の変更」の表の `dependabot.yml` の行(「gomod と docker の項目の追加」、2-5)と「段階ごとの PR」の 2-5 の箇条: 足す中身は docker の項目の `directories` の2行の追加で、「docker の項目の追加」の中に収まる。中身と理由は部品の節に書くと最後の段にある。影響なし
- design.md 「CI の仕事」の見分け `backend_compat`(`backend/compat/**`)と `backend_go`(`docker/backend-go/**`): Dependabot の docker の PR が `backend/compat/*/Dockerfile` だけを変えるとき、`backend_compat` が当たって `backend-compat` が動き、上げた版でイメージを組み立てられるかを確かめることを確かめた。影響なし
- design.md 「プロジェクトの決まりを守っているか」の frontend の2行、`.kiro/settings/templates/specs/design.md` の42行目と55行目: 差分で「関係のない項目: …」の1行が理由つきの2行に分かれたので、雛形の決めた書き方と合うかを確かめた(指摘 D3-2-3)
- design.md 「ファイルの構成」の `backend/assets/fonts.conf`、「イメージの組み立て方」の表の見出し、「backend-deploy.yaml と release.yaml」の役割(「組み立ての材料の場所」から「組み立ての文脈」への言い換えと、役割の段からの定義の文の削除): 定義の文(Docker がイメージを組み立てるときに読めるファイルを置いたフォルダ)が「CodeQL とイメージの検査と組み立てて動かす検査」の `docker-smoke` の箇条に残っていることを確かめた。影響なし
- design.md 「cross」の10の筋書き、requirements.md 13.1〜13.6 と 5.6: 箇条が10であること、13.1 の7つの操作のうち複数の要求からなるもの、13.4 の途中の手順をまたぐ操作(外部のアカウントでのログイン、2段階認証、パスワードの再設定、メールアドレスの確認)、5.6 のバックアップの両向きが入っていることを確かめた。影響なし
- design.md 「perf」の役割の段と「テストの方針」の「perf の12の操作」の行: 言い換えのあとも、役割の段の操作の列挙は11で、「12の操作」と合わない。サイクル2 往復1の D2-1-5(低、記録のみ)で記録した箇所がそのまま残っているだけなので、新しい指摘にしない。「段階4で1回、Claude が開発環境で動かす」の削除は、「いつ動くか」の段に同じ内容が残っている。影響なし
- design.md 「作るもの」の Go 版の土台の行の文末、「CI の仕事」の `backend_compat` の理由の段と PDF の単体テストの箇条、「compat harness」の状態の持ち方、「所有者に提案するゲート設定の変更」の `check-verify-before-stop.sh` の箇条、6-1 の `/healthz` の箇条、「backend-deploy.yaml と release.yaml」の入力の文: 途切れた文の直し、文の分割、主語の追加だけで、設計の中身が変わっていないことを前後の文で確かめた。影響なし

### 申告

**1. D3-1-1 の直し方として、fakeaws と fakeoidc の Dockerfile に `golang` の工程を残したまま、`dependabot.yml` の docker の項目と `backend-vuln-fix` の Go の仕事に2つのフォルダを足す(往復1の直し方の案の(b))を選んだ** — 「Dependabot と公開の時刻の検査と脆弱性の直し」の役割の段と `backend-vuln-fix` の段

- Issue の記載: なし
- 決めたこと: `golang` の版を書く場所を `go.mod` と `docker/backend-go/` の2つの Dockerfile と `backend/compat/` の2つの Dockerfile に重ねたままにし、Dependabot の docker の項目と `backend-vuln-fix` の Go の仕事が、`backend/compat/` の2つの Dockerfile の版も上げる
- 他にありえた選択肢: 比べる検査の処理が `go build -tags compat` で実行ファイルを作り、Dockerfile は distroless の土台に実行ファイルを置くだけにして、`golang` の版の重なりを無くす(往復1の案の(a))
- 外れていた場合: Dependabot の docker と gomod は別々の PR を出すので、`go.mod` の `go` の行を上げる PR(Dependabot の gomod が部品の求めで上げるときと、Claude が手で上げるとき)は、4つの Dockerfile を同じ PR で上げないと `backend-compat` が赤になる。これは `docker/backend-go/` の2つの Dockerfile と同じ扱いなので新しい穴ではないが、同じ PR で上げる箇所が2つ増える。段階6で `backend/compat/` を消すときに `dependabot.yml` からも消す作業が要る(指摘 D3-2-1)

### 指摘

| ID | レベル | 該当箇所 | 内容 | 直し方の案 |
|---|---|---|---|---|
| D3-2-1 | 中 | design.md 「段階6の削除と書き換え」の 6-1 の2つの箇条(「6-1 で、Claude は、Java 版のコード、…、`backend/compat/` の部品、…、Dependabot の `gradle` の項目、Java 版だけの検査のスクリプトを消す」と「6-1 で、Claude は、段階2で足した移行のための条件を、次のように消すか元の1つの形に戻す」)、「Dependabot と公開の時刻の検査と脆弱性の直し」の役割の段(D3-1-1 の直し) | D3-1-1 の直しで、2-5 の `dependabot.yml` の docker の項目に `backend/compat/fakeaws/` と `backend/compat/fakeoidc/` を足すことになった。この2つのフォルダは 6-1 で `backend/compat/` ごと消える。しかし、6-1 の消すものの一覧は Dependabot について「`gradle` の項目」だけを挙げ、移行のための条件を消す一覧にも docker の項目の2つのフォルダが無い。6-1 のあと、`dependabot.yml` の docker の項目は Dockerfile の無いフォルダを2つ指し続け、Dependabot はその項目で「Dockerfile が見つからない」誤りを報告する。`.github/dependabot.yml` はゲート設定なので、6-1 のあとに気づいて直すには、所有者の承認が要る PR をもう1つ出すことになる。6-1 は所有者の承認が要る PR なので、同じ PR に入れれば承認は1回で済む | 6-1 の消すものの一覧の「Dependabot の `gradle` の項目」を「Dependabot の `gradle` の項目と、docker の項目の `backend/compat/fakeaws/` と `backend/compat/fakeoidc/` のフォルダ」に直す。あわせて、「Dependabot と公開の時刻の検査と脆弱性の直し」の役割の段に「この2つのフォルダは、6-1 で `backend/compat/` を消すときに docker の項目から消す」と1文を足す |
| D3-2-2 | 低 | design.md 「Dependabot と公開の時刻の検査と脆弱性の直し」の役割の段(D3-1-1 の直し)、`.github/dependabot.yml` の docker の項目(`open-pull-requests-limit: 10` と、その上のコメント「digest更新はgroupsに入らず、ディレクトリごとの個別PRになる。上限はディレクトリ数を下回らない値にする」) | 今の docker の項目が見るフォルダは `docker/` の下の7つ(`backend` `db` `dind` `frontend` `localstack` `redis` `terraform`)である。この spec で `docker/backend-go/` と `docker/api-docs/` が増え(`/docker/*` で自動で入る)、D3-1-1 の直しで `backend/compat/` の2つが入るので、2-5 から 6-1 までの間、docker の項目のフォルダは11になり、`open-pull-requests-limit: 10` を超える。digest の更新はフォルダごとの個別の PR になるので、11個の digest の更新が同時に出ると、1つが上限で待つ。設計は 2-5 の `dependabot.yml` の変更にこの上限の変更を書いていない。待つだけで止まりはせず、6-1 で `docker/backend/` と `backend/compat/` が消えると9に戻るので、実装には影響しない | 「Dependabot と公開の時刻の検査と脆弱性の直し」の役割の段に、2-5 で docker の項目の `open-pull-requests-limit` をフォルダの数(11)以上に上げ、6-1 で戻すと書く。または、上げない判断とその理由(待つだけで止まらない)を書く |
| D3-2-3 | 低 | design.md 「プロジェクトの決まりを守っているか」の「frontend の機能ごとの境界: この spec は frontend のコードを変えないので、関係しない」と「frontend の状態の持ち方: この spec は frontend のコードを変えないので、関係しない」の2行 | 雛形 `.kiro/settings/templates/specs/design.md` の42行目は「Claude は、関係のない項目を、理由を書かずに名前だけ『関係のない項目:』の1行に並べる」と決め、55行目に `- 関係のない項目: {{UNRELATED_ITEM_NAMES}}` の形を示す。差分で、往復1までの「関係のない項目: frontend の機能ごとの境界と、frontend の状態の持ち方。…」の1行が、項目ごとの理由つきの2行に分かれ、雛形の書き方から外れた。中身(2つの項目が関係しないこと)は変わっておらず、実装には影響しない | 2行を「- 関係のない項目: frontend の機能ごとの境界、frontend の状態の持ち方」の1行に戻す(理由は書かない) |

### 前の段階への指摘

| ID | 対象 | 該当箇所 | 内容 |
|---|---|---|---|
| (なし) | | | |

- 往復: 2回目 / 高0 中1 低2

## サイクル3 往復3(2026-11-08)

### 審査の範囲

範囲: 差分

- design.md 「段階6の削除と書き換え」の 6-1 の消すものの一覧(D3-2-1 の直し)と「Dependabot と公開の時刻の検査と脆弱性の直し」の役割の段の最後の2文、`.github/dependabot.yml` の docker の項目(`directories: - "/docker/*"`): 6-1 で消すフォルダが、2-5 で足す2つのフォルダと同じであること、6-1 で `docker/backend-go/` を `docker/backend/` に戻したあとも `/docker/*` に当たるので docker の項目にそれ以上の直しが要らないこと、「所有者の承認が要る PR がもう1つ要る」の理由がゲート設定の扱い(CLAUDE.md)と合うことを確かめた。合っている
- design.md 「Dependabot と公開の時刻の検査と脆弱性の直し」の `backend-vuln-fix` の段(Go の仕事が `golang` のイメージの版を上げる場所に `docker/backend-go/` と `backend/compat/fakeaws/` と `backend/compat/fakeoidc/` を挙げる)、6-1 の2つの箇条、「所有者に提案するゲート設定の変更」の表の `backend-vuln-fix.yaml` の行、`.github/scripts/backend-vuln-fix.sh`: 差分の語 `backend/compat/fakeaws/` `backend/compat/fakeoidc/` で design を検索し、D3-2-1 の直しと同じ2つのフォルダを挙げるこの段を見つけた。6-1 がこの段の3つの場所をどう扱うかを確かめた(指摘 D3-3-1)。今の `backend-vuln-fix.sh` は Dockerfile を扱っていないので、Go の仕事の場所の一覧は 2-5 で新しく書くものである
- design.md 「所有者に提案するゲート設定の変更」の表の `dependabot.yml` の行(2-5)と表の下の段: 6-1 の `dependabot.yml` の変更が表に無いのは、6-1 の `gradle` の項目の削除と同じ扱いで、サイクル2 往復1の D2-1-7 が引く D1-1-10(低、記録のみ)の範囲である。新しい指摘にしない
- design.md 「migrate」の状態の持ち方(行の列と値の書き方の分け直し、`pg_advisory_lock` とトランザクションの定義の追加)、research.md 「Flyway の検査の値」、`backend/src/main/resources/db/migration/` の7つのファイル名: 列の名前(10個)と値の書き方が直す前と同じであること、research.md の節があり計算の方法が合うことを確かめた。`description` の書き方は、分け直しの前から同じ文だが、7つのファイル名に照らすと `.sql` の扱いが読めない(指摘 D3-3-2)。`pg_advisory_lock` の説明は、同じ鍵の番号のセッションの鍵を取る呼び出しが鍵が放されるまで待つという PostgreSQL の動きと合う
- design.md 「ファイルの構成」の `backend/compat/pdfcmp/` の行(ビルドタグの理由の言い換え)、「Makefile」の `make test`(`go test -race -coverprofile=coverage.out ./...`)と「比べる検査の3つのタスクは `go test -tags compat` で動く」: `make check` が `-tags compat` を付けないので pdfcmp のテストが `make test` で動かないことと合う。影響なし。`make lint` と `make fmt-check` がこのコードを読むかは D3-1-6(低、記録のみ)の範囲
- design.md 「ファイルの構成」の `backend/assets/fonts.conf`(fontconfig の定義の追加)、「Dockerfile.prod」、6-1 の `backend/assets/fonts/`: 定義の追加だけで、置き場所と組み立ての文脈(`./backend`)は変わっていない。影響なし
- design.md 「使う技術」の Redis の行(TLS の定義の追加)、「database と redisstore と awsclient」の役割(本番は TLS、`dev` と `test` は1台の形)、「fakeaws と fakeoidc」の使う部品(比べる検査は TLS なし): 定義の追加だけで、3か所の TLS の使い分けは変わっていない。影響なし
- design.md 「api-docs」の役割(`swaggerapi/swagger-ui` を digest で固定する文の分け直し)、「ファイルの構成」の `docker/api-docs/Dockerfile` と `compose.yaml` の行: イメージの土台と、読み取りだけの差し込みと、ポート 8082 は変わっていない。影響なし
- design.md 「.golangci.yml と .testcoverage.yml と .gremlins.yaml」の `.testcoverage.yml` の段(文の割合の定義の追加)、「Makefile」の `make coverage`: 下限 93% と数えない対象は変わっていない。影響なし
- design.md 「消す一覧」の `@react-router/node` と `@react-router/dev` の行: 主語の位置の言い換えだけで、確かめた内容と消すファイルは変わっていない。影響なし

### 申告

(今回の差分で新しく申告するものはない)

### 指摘

| ID | レベル | 該当箇所 | 内容 | 直し方の案 |
|---|---|---|---|---|
| D3-3-1 | 中 | design.md 「Dependabot と公開の時刻の検査と脆弱性の直し」の `backend-vuln-fix` の段(「脆弱性が Go の標準ライブラリにあるときは、この仕事は、`go.mod` の `toolchain` と、`docker/backend-go/` と `backend/compat/fakeaws/` と `backend/compat/fakeoidc/` の `golang` のイメージの版を、1つの PR で上げて直す」)、「段階6の削除と書き換え」の 6-1 の2つの箇条(消すものの一覧と、移行のための条件を消すか元の形に戻す一覧) | D3-2-1 の直しで、6-1 は Dependabot の docker の項目から `backend/compat/` の2つのフォルダを消すことになった。しかし、同じ2つのフォルダを挙げるもう1つの場所、`backend-vuln-fix` の Go の仕事が `golang` のイメージの版を上げる場所の一覧(`docker/backend-go/` `backend/compat/fakeaws/` `backend/compat/fakeoidc/`)は、6-1 のどちらの箇条にも無い。6-1 で `backend/compat/` は消え、`docker/backend-go/` は `docker/backend/` に名前が戻るので、6-1 のあと、この一覧の3つの場所はどれもリポジトリに無い。Go の標準ライブラリの脆弱性が見つかったとき、この仕事は、無い Dockerfile の版を上げようとして PR を作れないか、`go.mod` の `toolchain` だけを上げた PR を出して `docker/backend/` の `golang` のイメージの版が上がらず、`backend-test` の組み立てが「go.mod requires go >= …」で止まる(公式の `golang` のイメージは新しい Go を取りに行かない。D3-1-1 で確かめた)。`backend-vuln-fix.yaml` と `.github/scripts/backend-vuln-fix.sh` はゲート設定なので、6-1 のあとに気づいて直すには、所有者の承認が要る PR をもう1つ出すことになる。D3-2-1 と同じ穴が、同じ節の隣の段に残っている | 6-1 の「移行のための条件を消すか元の1つの形に戻す」箇条に、「`backend-vuln-fix` の Go の仕事が `golang` のイメージの版を上げる場所を、`docker/backend/` の2つの Dockerfile だけにする」を足す。あわせて、`backend-vuln-fix` の段の最後に「6-1 で `backend/compat/` を消し `docker/backend-go/` を `docker/backend/` に戻すときに、この一覧も直す」と1文を足す。6-1 で `backend-vuln-fix.yaml` の Java 版の仕事をどう扱うか(消すのか、「Java 版だけの検査のスクリプト」に含むのか)も、同じ箇条で名指しすると、6-1 の PR の中身が一覧から読める |
| D3-3-2 | 低 | design.md 「migrate」の状態の持ち方(「この部品は、…`description` にファイル名の `__` の後ろの `_` を空白にしたものを書く」) | Flyway が書く `description` は、ファイル名から `V<版>__` と `.sql` を除き、`_` を空白にしたものである(`V1__create_tables.sql` なら `create tables`)。本文の「ファイル名の `__` の後ろの `_` を空白にしたもの」を字のとおりに読むと `create tables.sql` になり、`.sql` を除くかが読めない。この文は分け直しの前から同じで、`ValidateOnly` は `description` を照らさないので、違いが出るのは段階6の `Apply` で新しい行を書くときだけである。そのときは Java 版が無く、`description` を読むものも無いので、実装には影響しない | 「`description` に、ファイル名から `V<版>__` と `.sql` を除き、`_` を空白にしたものを書く」に直す |

### 前の段階への指摘

| ID | 対象 | 該当箇所 | 内容 |
|---|---|---|---|
| (なし) | | | |

- 往復: 3回 / 未解決: 1件

## サイクル4 往復1(2026-11-08)

### 審査の範囲

範囲: 差分

- design.md 「移行」の「段階ごとの PR」の表の 4-1(「要らない」)と表の下の新しい箇条(4-1 と 6-2 は terraform のファイルだけを変える)、「段階6の削除と書き換え」の表の 6-2(`terraform apply` だけ)、`.github/CODEOWNERS`: CODEOWNERS が terraform のうち `/terraform/.checkov.baseline` だけを守ることを確かめた。合っている。4-1 と 6-2 が変えるファイルが terraform だけであることを、「ファイルの構成」の `terraform/main.tf` `terraform/modules/ecs/main.tf` `terraform/modules/alb/` の3行と「本番の設定の値の変わり方」の表(段階4は `KEIREKIPRO_ENV` と `redis-username` の2行を足す、段階6は Spring の環境変数と `spring.data.redis.*` を消し、生きているかの確認の経路を `/healthz` にする)を、`terraform/main.tf` 93〜102行目(`keirekipro/redis` の秘密の値は terraform が書く)と `terraform/modules/ecs/main.tf` 56〜86行目(環境変数と `healthCheck`)と `terraform/modules/alb/main.tf` 32行目(`health_check`)で確かめた。合っている。`.github/workflows/terraform-plan.yaml`(PR では静的な検査だけ)と `terraform-apply.yaml`(所有者が起動し、`environment: production` の承認を経て、差分を出してから適用する)を読み、新しい箇条の `terraform-apply.yaml` の説明が事実と合うかを確かめた(指摘 D4-1-1)
- design.md 「所有者に提案するゲート設定の変更」の表、requirements.md 7.1〜7.3、「progress.md」の PR の本文の決まり: 4-1 と 6-2 が承認が要る PR の表に無いこと、7.1 の6つの操作に「本番の設定の変更の反映(terraform apply)」が残り、承認を「要らない」にしても 7.1 と食い違わないこと、7.3 の「承認が要る PR」の返事の決まりから 4-1 と 6-2 が外れても矛盾しないことを確かめた。影響なし
- design.md 「段階4の本番の設定の変更」の役割の最後の文(`backend-deploy.yaml` が、今の出荷の手順のまま、新しいタスク定義を元にしてイメージだけを替えたタスク定義を登録する)、`.github/workflows/backend-deploy.yaml` 87〜115行目、`terraform/modules/ecs/main.tf` 128〜130行目: `backend-deploy.yaml` は `describe-task-definition` で家族の最新の版を読み、イメージだけを替えて登録する。ECS のサービスは `ignore_changes = [task_definition]` なので、`terraform apply` は新しい版のタスク定義を登録するだけでサービスを更新しない。文のとおりである。影響なし
- design.md 「段階6の削除と書き換え」の 6-1 の消すものの一覧(足した「`backend-deploy.yaml` が今のイメージのタグから版を決める処理」)、「backend-deploy.yaml と release.yaml」の役割: 消す処理は、役割に書いた「`current` のときは、今のイメージのタグが `go-` で始まれば Go 版」の処理を指し、同じ箇条で消す入力 `backend_impl` と一緒に消すことと矛盾しない。影響なし
- design.md 「Dependabot と公開の時刻の検査と脆弱性の直し」の役割の箇条への分け直し: 4つの箇条の中身(gomod、docker の項目に足す2つのフォルダと理由、Java 版の項目を残す期間、6-1 で消すもの)が、分け直す前の段と同じであることを確かめた。影響なし
- design.md 「CI の仕事」のマイグレーションの文(3つの見分けを名指しにした): 言い換えだけである。`backend_go` の形にマイグレーションのパスが無いことは、サイクル2 往復1の D2-1-4(低、記録のみ)の範囲で、新しい指摘にしない
- design.md 「概要」(「比べる検査」「まとまりの spec」の呼び方の文)、「全体の構成」の depguard の文、「ファイルの構成」の `backend/assets/fonts.conf`(組み立ての文脈の定義)と `backend/compat/scenarios/`、「logging」「httpapi」の中間処理の4、「pdf」、「pdfcmp」の経歴書のデータ、「テストの方針」: 主語の追加と語の説明の追加だけで、設計の中身が変わっていないことを前後の文で確かめた。影響なし

### 申告

**1. 本番の設定を変える terraform の PR(4-1 と 6-2)を、所有者の承認なしに main に入れる形にし、CODEOWNERS に `terraform/` を足さない** — 「移行」の「段階ごとの PR」の表と箇条、「段階6の削除と書き換え」の表の 6-2

- Issue の記載: なし(Issue は、本番の反映を所有者が行うことだけを前提にしている)
- 決めたこと: 4-1 と 6-2 は品質チェックに通れば自動で main に入り、所有者が見るのは `terraform-apply.yaml` を動かすときだけにする
- 他にありえた選択肢: 2-1 の `CODEOWNERS` の変更に `/terraform/` を足し、terraform の PR にも所有者の承認を機械で求める。承認を求めないまま、PR を作ったときの返事で所有者に差分を見てもらうよう頼む
- 外れていた場合: 所有者が terraform の変更を main に入る前に見たいと考えていたときは、2-1 のあとに `CODEOWNERS` を直すゲート設定の PR がもう1つ要る。main に入った terraform の変更は、`terraform-apply.yaml` で差分を見る場面(指摘 D4-1-1)まで、人の目を通らない

### 指摘

| ID | レベル | 該当箇所 | 内容 | 直し方の案 |
|---|---|---|---|---|
| D4-1-1 | 中 | design.md 「移行」の「段階ごとの PR」の表の下の箇条(「所有者は、`terraform-apply.yaml` が適用の直前に出す本番との差分を見てから、本番に反映するかを決める」)、「runbook.md」の操作1(所有者は `terraform apply` を打つ)、`.github/workflows/terraform-apply.yaml` | 今の `terraform-apply.yaml` は、所有者が `workflow_dispatch` で起動し、`environment: production` の承認が通ってから仕事を始め、`terraform plan -out=tfplan` で差分をログに出した直後に `terraform apply -auto-approve tfplan` で適用する(74〜86行目)。差分を出したところで止まるのは、起動のときに入力 `plan_only` にチェックを付けたときだけである(9〜11行目、85行目)。所有者が「反映するかを決める」場面は `environment: production` の承認であり、その時点では差分はまだ出ていない。よって、この箇条の「差分を見てから、本番に反映するかを決める」は、今のワークフローのとおりでない。この箇条は、4-1 と 6-2 の承認を「要らない」にする理由として、所有者が本番の反映の前に差分を見ることを挙げているので、所有者がこの文を頼りに承認なしを受け入れると、実際には差分を見ずに反映する手順になる。runbook の操作1も `plan_only` の手順を含まないので、4-2 で作る手順書もこのまま書かれ、所有者が手順書のとおり操作しても、差分を見る場面は無い | 箇条を事実に合わせる。例: 「`terraform-apply.yaml` は、所有者が起動し、production の承認が通ったあとに、本番との差分をログに出してそのまま適用する。差分を見てから反映するかを決めるには、所有者は、先に入力 `plan_only` にチェックを付けて動かして差分を見てから、チェックを外してもう一度動かす」。runbook の操作1(と、6-2 の反映の操作)に、`plan_only` で差分を見る手順と、その見分け方(実行の概要に「差分を出したところで止めました」が出ること)を足す。差分を見る手順を要らないと判断するなら、箇条の最後の文を消し、所有者が見るのは PR の差分だけだと書く |

### 前の段階への指摘

| ID | 対象 | 該当箇所 | 内容 |
|---|---|---|---|
| (なし) | | | |

- 往復: 1回目 / 高0 中1 低0

## サイクル4 往復2(2026-11-08)

### 審査の範囲

範囲: 差分

- design.md 「移行」の「段階ごとの PR」の表の下の 4-1 と 6-2 の箇条と、その下の2つの手順(D4-1-1 の直し)、`.github/workflows/terraform-apply.yaml`: 「`environment: production` の承認が通ったあとに、本番との差分をログに出し、そのまま適用する」が47行目と74〜86行目と合うこと、`plan_only` の入力が13〜19行目にあること、「実行の概要に『本番には適用していません』が出る」が89〜97行目の `$GITHUB_STEP_SUMMARY` に書く文(「本番には適用していません。」)と合うことを確かめた。合っている。`gh run view --log` で読む差分は「Terraform Plan (差分の事前表示)」のステップのログにある。影響なし
- design.md 「runbook.md」の操作1(「段階ごとの PR」の2回の手順を参照する形に変わった)、「段階6の削除と書き換え」の表の 6-2(「`terraform-apply.yaml` の2回の起動」)、「段階4の本番の設定の変更」の役割、「移行」の図の `Apply1`、requirements.md 5.1 と 6.2 と 7.1: 操作1の参照先が「段階ごとの PR」の箇条にあること、6-2 の表と箇条が同じ2回の手順を指すこと、5.1 と 6.2 の「所有者が本番に反映する(terraform apply)」と 7.1 の6つの操作の「本番の設定の変更の反映(terraform apply)」に、2回に分けて動かすことが収まることを確かめた。「段階4の本番の設定の変更」の役割と図の「所有者の terraform apply」は、2回目の起動が `terraform apply` を動かすので食い違わない。影響なし
- design.md 「runbook.md」の役割の文(差分で「所有者が切り替えの出荷を平日の 08:00 から 20:00 の間に起動し」が消えた)、requirements.md 5.3 と「作らないもの」の時間割の段(94行目): 消えた句が 5.3 の求めることかを確かめ、同じ内容が design のほかの箇所にあるかを `平日` `08:00` `本番が動いている` `時間割` で Grep した。「使う既存の仕組み」と「作らないもの」の時間割の2行だけが見つかり、手順書に書く決まりとしては残っていない(指摘 D4-2-1)
- design.md 「main(入口)」のいつ動くか(90秒と `stopTimeout` の説明の追加)、`backend/src/main/resources/application-prod.yaml` 2行目と7行目(`shutdown: graceful`、`timeout-per-shutdown-phase: 90s`)、`terraform/modules/ecs/main.tf` 89行目(`stopTimeout = 120`): 足した説明の数値が実ファイルと合うことと、「`stopTimeout` の時間がたってもコンテナが終わらなければ強制的に止める」が ECS の `stopTimeout` の動きと合うことを確かめた。影響なし
- design.md 「使う既存の仕組み」の本番の行(デプロイのサーキットブレーカーの説明の追加)、`terraform/modules/ecs/main.tf` 123行目(`deployment_circuit_breaker`)、「backend-deploy.yaml と release.yaml」の失敗したとき: 説明が、失敗したときの段の「サーキットブレーカーが前のタスク定義に戻す」と同じ動きを指すことを確かめた。影響なし
- design.md 「migrate」の状態の持ち方(BOM と CRC32 の説明の追加): BOM が3バイト(EF BB BF)であること、CRC32(IEEE)が Go の `hash/crc32` の既定の多項式の名前であることと合う。計算の手順と列の書き方は変わっていない。影響なし
- design.md 「CodeQL とイメージの検査と組み立てて動かす検査」の `docker-smoke` の箇条(組み立ての文脈の定義の文を消した)、「ファイルの構成」の `backend/assets/fonts.conf` の行: 定義の文が「ファイルの構成」の行(211行目)に残り、`docker-smoke` の箇条より前に出ることを確かめた。影響なし
- design.md 「compat harness」の比べるものの箇条(「両方の版で同じ時刻にするのはむずかしいため、比べる検査は時刻を比べない」を JSON の箇条に移し、状態の持ち方から消した): 「日時は、形を確かめてから記号に置き換える」と同じ箇条に移っただけで、比べ方は変わっていない。影響なし
- design.md 「段階6の削除と書き換え」の 6-1 の最初の箇条(1つの段を6つの箇条に分け直した): 消すものの11個と、2〜6の中身が、分け直す前の段と同じであることを確かめた。影響なし
- design.md 「config」「httpapi」「Makefile」「CI の仕事」「Dependabot と公開の時刻の検査と脆弱性の直し」の 6-1 の箇条、「compat harness」の使う部品と失敗したとき、「changed-behaviors.yaml」「Dockerfile.prod」「backend-deploy.yaml と release.yaml」の権限、6-1 の `dependency-graph-generate` の箇条、「消す一覧」の `@react-router/*` の行: 主語の追加と語の説明の追加と言い換えだけで、設計の中身が変わっていないことを前後の文で確かめた。影響なし

### 申告

**1. 4-1 と 6-2 の本番への反映を、`plan_only` を付けた1回目と、チェックを外した2回目の、`terraform-apply.yaml` の2回の起動にする** — 「移行」の「段階ごとの PR」の 4-1 と 6-2 の箇条の下の2つの手順、「runbook.md」の操作1、「段階6の削除と書き換え」の表の 6-2

- Issue の記載: なし(Issue は、本番の反映を所有者が行うことだけを前提にしている)
- 決めたこと: 所有者は、`environment: production` の承認を2回行い、1回目のログの差分を Claude が PR の本文と照らしてから、2回目で適用する
- 他にありえた選択肢: 1回目を省き、所有者が見るのは PR の差分だけにする(D4-1-1 の直し方の案の最後の形)。または、`terraform-apply.yaml` を、差分を出したところで承認を待つ2つの仕事に分ける(ゲート設定の変更が要る)
- 外れていた場合: 所有者が1回目を省いて動かしても、本番は PR のとおりに変わるので、作り直しは起きない。手順書と「段階ごとの PR」の箇条を1回の起動の形に直すだけで済む

### 指摘

| ID | レベル | 該当箇所 | 内容 | 直し方の案 |
|---|---|---|---|---|
| D4-2-1 | 中 | design.md 「runbook.md」の役割の文(差分で「手順書には、所有者が切り替えの出荷を平日の 08:00 から 20:00 の間に起動し、20:00 に本番が止まる30分前までに出荷を終えることも書く」が「手順書には、所有者が、20:00 に本番が止まる30分前までに切り替えの出荷を終えることも書く」に変わった)、requirements.md 5.3 | 受入基準 5.3 は「手順書には、切り替えの出荷を、本番が動いている平日の 08:00 から 20:00 の間に行うことも書く。本番が止まっている時間には、データベースも止まっているので、Go 版が動き始められないためである」と求める。差分で「平日の 08:00 から 20:00 の間に起動し」の句が消え、残った「20:00 に本番が止まる30分前までに終える」だけでは、平日に限ることと、08:00 より前に起動しないことが読めない。親の起動の文はこの直しを「重なった文の削除」としているが、`平日` `08:00` `本番が動いている` `時間割` で design を Grep すると、時間割に触れる行は「使う既存の仕組み」の「EventBridge Scheduler の時間割」と「作らないもの」の「時間割を変えない」の2行だけで、手順書に書く決まりとして同じ内容を持つ箇所は無い。重なりではなく、5.3 を裏付ける唯一の記述が消えた。「runbook.md」は 5.3 を対応する要件に挙げる唯一の部品なので、tasks は design のこの文から手順書の中身を決める。手順書が平日の 08:00〜20:00 の窓を書かないまま 4-2 で作られると、所有者が休日や 08:00 より前に切り替えの出荷を起動したとき、本番のタスクとデータベースが止まっているので Go 版は起動できず、出荷は失敗する。切り替えのあとの手順書で見つかるが、そのとき 4-2 の手順書を直す PR が要る | 消えた句を戻す。例: 「手順書には、所有者が切り替えの出荷を、本番が動いている平日の 08:00 から 20:00 の間に起動し、20:00 に本番が止まる30分前までに終えることも書く」。重なりを無くす意図なら、「30分前」の句のほうを削り、5.3 の「平日の 08:00 から 20:00 の間」を残す |

### 前の段階への指摘

| ID | 対象 | 該当箇所 | 内容 |
|---|---|---|---|
| (なし) | | | |

- 往復: 2回目 / 高0 中1 低0

## サイクル4 往復3(2026-11-08)

### 審査の範囲

範囲: 差分

- design.md 「runbook.md」の役割の文(D4-2-1 の直しで「所有者が切り替えの出荷を平日の 08:00 から 20:00 の間に起動し」を戻した)、requirements.md 5.3(172行目)と「作らないもの」の時間割の段(94行目): 戻した句が 5.3 の「本番が動いている平日の 08:00 から 20:00 の間に行う」と合うこと、残した「20:00 に本番が止まる30分前までに終える」が requirements の時間割(backend は 20:00 に止まる)と矛盾しないことを確かめた。操作1〜5の見分け方は往復1〜2のまま変わっていない。影響なし
- design.md 「概要」(「Claude は、出荷のワークフローに、どちらの版を出荷するかを選ぶ入力を足す」の1文を消した)、「作るもの」の出荷の仕組みの箇条(16行目)、「所有者に提案するゲート設定の変更」の表の `release.yaml` と `backend-deploy.yaml` の行(91行目)、「backend-deploy.yaml と release.yaml」、「Java 版に戻す条件」(892行目): 消した文と同じ内容が「作るもの」の「出荷のワークフローが出荷する版を選ぶ仕組み」と表の「入力 `backend_impl` の追加」に残り、入力 `backend_impl` を使う箇所(251〜252行目、673行目、676行目、742行目、892行目)はどれも変わっていないことを確かめた。概要の重なりの削除で、設計の中身は減っていない。影響なし
- design.md 「作らないもの」の1つ目と「設計を見直すきっかけ」の1つ目(「まとまりごとの spec」を「まとまりの spec」に替えた)、「概要」7行目: 7行目が「機能のまとまりごとの spec を『まとまりの spec』と呼ぶ」と定義しており、替えた2箇所はこの定義に合わせた言い換えである。`まとまりごとの spec` で design を Grep すると、残るのは定義の7行目だけで、呼び方が揃った。影響なし
- design.md 「CI の仕事」のいつ動くか(主語の追加)、`.github/workflows/ci.yaml` 7〜11行目: 「`pull_request` と main への `push` で動く」が今の ci.yaml の `on:`(`push: branches: [main]`、`pull_request: branches: [main]`)と合うことを確かめた。言い換えだけで、設計の中身は変わっていない。影響なし
- design.md 「Dependabot と公開の時刻の検査と脆弱性の直し」の `backend-vuln-fix.yaml` の段(最後の文の言い換え): 「所有者が、`ci-tool-fast-update` の決まりで、止まった PR をどう扱うかを判断する」は、言い換える前の「所有者が `ci-tool-fast-update` の決まりで判断する」と同じ内容である。影響なし
- design.md 「fakeaws と fakeoidc」の使う部品(JWT の説明の追加)、`backend/src/main/java/com/example/keirekipro/presentation/security/jwt/JwtProvider.java` 59〜64行目と `application*.yaml` の `jwt.secret`: Java 版は `Algorithm.HMAC256(jwtProperties.getSecret())` でアクセストークンを署名しており、「backend がログインの状態を表すために署名して渡すトークンの形式」と「JWT の値とは、その署名に使う秘密の値」が事実と合うことを確かめた。同じ段の次の文「JWT の秘密の値を両方の版でそろえるのは、版をまたぐ確認で、一方の版が出したトークンをもう一方の版が受け付けるようにするため」とも矛盾しない。影響なし
- design.md 「cross(版をまたぐ確認)」の役割(1文を2文に分けた): 「応答は比べず、各段の応答が筋書きの期待(ステータスと、本文の必須の項目)に合い、操作が最後まで終わることを確かめる」と、分けたあとの2文の中身が同じであることを確かめた。影響なし
- design.md 「移行」の「段階ごとの PR」の表の下の段(2-1 と 2-2 に説明の語を足した)、同じ節の表の 2-1 と 2-2 の行(958〜959行目)と箇条(969〜970行目): 足した「ゲート設定を Go に対応させる PR 2-1」と「Go 版の土台を入れる PR 2-2」が、表の「ゲート設定の Go への対応」と「Go 版の土台と品質チェックの設定と開発環境」と合うことを確かめた。影響なし

### 申告

(今回の差分で新しく申告するものはない)

### 指摘

| ID | レベル | 該当箇所 | 内容 | 直し方の案 |
|---|---|---|---|---|
| (なし) | | | | |

### 前の段階への指摘

| ID | 対象 | 該当箇所 | 内容 |
|---|---|---|---|
| (なし) | | | |

- 往復: 3回で収束 / 未解決: 0件

## サイクル5 往復1(2026-11-08)

### 審査の範囲

範囲: 差分

- design.md 「Dependabot と公開の時刻の検査と脆弱性の直し」の `backend-vuln-fix` の段の下に足した段(D3-3-1 の直し)、「段階6の削除と書き換え」の 6-1 の「移行のための条件を消すか元の1つの形に戻す」箇条、「ファイルの構成」の `docker/backend-go/Dockerfile` と `Dockerfile.prod` の行(207〜208行目)、「所有者に提案するゲート設定の変更」の表の `backend-vuln-fix.yaml` の行(88行目): 足した段と 6-1 の箇条が同じ内容(`docker/backend/` の Dockerfile だけにする)を指すこと、`docker/backend-go/` の2つの Dockerfile がどちらも `golang` のイメージを使うので「`docker/backend/` の Dockerfile」がその2つを指して読めること、理由(6-1 のあとに直すと無い Dockerfile を指す。ゲート設定なので承認が要る PR がもう1つ要る)が CLAUDE.md のゲート設定の扱いと合うことを確かめた。合っている。6-1 の変更が表に無いのは、サイクル3 往復3で確かめたとおり D1-1-10(低、記録のみ)の範囲で、新しい指摘にしない。同じ yaml の Java 版の仕事の扱いは指摘 D5-1-1
- design.md 「CI の仕事」のいつ動くか(「main への push で動くのは今の ci.yaml と同じ」「main の必須の検査は、PR が最新の main を取り込んでいることを求める」)、`doc/開発フロー/基盤構築手順.md` 48〜55行目、`.github/workflows/update-pr-branches.yaml` の冒頭の説明、「CI の仕事」の見分け `backend_compat`: ruleset の `Require branches to be up to date before merging` が有効(✅)であること、`update-pr-branches.yaml` がその前提で PR を最新化していることを確かめた。一方の版だけを直した PR は `backend_java` か `backend_go` に当たるので `backend_compat` も当たり、PR の検査で `backend-compat` が動く。文のとおりである。影響なし
- design.md 「使う既存の仕組み」の出荷の行、`.github/workflows/backend-deploy.yaml` と `frontend-deploy.yaml` の `on:`: どちらも `workflow_call` だけであることを確かめた。合っている。影響なし
- design.md 「テストの方針」の「perf が比べる11の操作」、「perf」の役割(608行目): 役割に列挙した操作は、ログイン、トークンの更新、利用者の情報の取得、経歴書の一覧・取得・基本情報の保存・職歴の追加、PDF の出力、Markdown の出力、バックアップの書き出し・戻しの11で、数が合った(サイクル2 往復1の D2-1-5 が解消した)。影響なし
- design.md 「テストの方針」のシェルのテストの行、`.github/scripts/tests/*.sh`: 今のテストのファイルが `KP_TEST_CASE` を使っていること(16ファイル)を確かめた。言い換えだけで中身は変わっていない。影響なし
- design.md 「安全」の5つの文字 `<` `>` `&` `"` `'`、`backend/src/main/resources/templates/resume/pdf/simple.html` と `markdown/default.md`、`ThymeleafResumePdfExporter.java`: Java 版は Thymeleaf で、`th:text` と `[[...]]` の既定の置き換えは `&` `<` `>` `"` `'` の5文字である。テンプレートで置き換えない `[(...)]` は `pdfSettings.tableHeaderColor` の2箇所だけで、利用者が入力する文の項目は置き換えられている。文のとおりである。影響なし
- design.md 「残すもの」のシェルのテストの行、`.claude/hooks/tests/*.sh`、`.claude/scripts/parallel/tests/` `usage/tests/` `memory/tests/` `vuln-watch/tests/` のテスト、`.claude/scripts/ci-tool-signature/verify-ci-tool.sh` 51行目: テストのファイルの先頭に「実行: bash …」の行があること(hooks、parallel、usage、memory、vuln-watch)と、`test-verify-ci-tool.sh` の起動の仕方が `verify-ci-tool.sh` のコメント(「テスト: .claude/scripts/ci-tool-signature/test-verify-ci-tool.sh」)にあることを確かめた。合っている。影響なし
- design.md 「progress.md」の役割(「1つの表」から「段階の表」と「まとまりの表」の2つに直した)、同じ節の状態の持ち方: 状態の持ち方は直す前から「まとまりの表」と「段階の表」を別に書いており、役割の文がそれに合った。影響なし
- design.md 「変えた動きの一覧の形」の「CB-001 から CB-004 の4つ」、同じ節の表と箇条、Issue #445 の「決めた方式」: 表は CB-001〜CB-005 の5つで、CB-001〜CB-004 は Issue の「決めた方式」で所有者が受け入れた4つの違い(並び順、プロフィール画像、入力の足りない経歴書の書き出し、PDF の文字の位置と「〜」)と合う。影響なし
- design.md 「config」の環境ごとの値、「CI の仕事」の `backend_compat` の理由の段、「変えた動きの一覧の形」の CB-005、「テストの方針」の比べる検査の行: 主語の追加と語の説明の追加だけで、設計の中身が変わっていないことを前後の文で確かめた。影響なし

### 申告

(今回の差分で新しく申告するものはない)

### 指摘

| ID | レベル | 該当箇所 | 内容 | 直し方の案 |
|---|---|---|---|---|
| D5-1-1 | 低 | design.md 「Dependabot と公開の時刻の検査と脆弱性の直し」の 6-1 の段(D3-3-1 の直しで足した段)、「段階6の削除と書き換え」の 6-1 の消すものの一覧(「Java 版だけの検査のスクリプト」)と「段階6の書き換え」の表の「設定とスクリプト」(6-4 の「Java 版の分を消す」) | 足した段は、6-1 で `backend-vuln-fix.yaml` の Go の仕事が上げる場所を直すと決めたが、同じ yaml にある今の Java 版の仕事(毎日 `schedule` で動き、Gradle で部品の一覧を読む)を 6-1 で消すのか、6-4 の「`.github/` のワークフローとスクリプトの Java 版の分を消す」に残すのかは、どちらの箇条にも名指しが無い。6-1 で Gradle を消したあと 6-4 が main に入るまでのあいだ、Java 版の仕事は毎日失敗する。必須の検査ではないので PR は止まらず、6-1 で同じ yaml を直すときに一緒に消せる。D3-3-1 の直し方の案の最後の文(6-1 で Java 版の仕事をどう扱うかを同じ箇条で名指しする)に当たる | 足した段の最後か、6-1 の消すものの一覧に「`backend-vuln-fix.yaml` の Java 版の仕事と、`backend-vuln-fix.sh` の Java 版の処理」を1つ足す |

### 前の段階への指摘

| ID | 対象 | 該当箇所 | 内容 |
|---|---|---|---|
| (なし) | | | |

- 往復: 1回で収束 / 未解決: 0件

## サイクル6 往復1(2026-11-08)

### 審査の範囲

範囲: 差分

- design.md 「CI の仕事」の見分け `backend_go` の行と、その下に足した理由の段とマイグレーションの段(D2-1-4 の直し。`backend/go.mod` があることの条件と、`backend/assets/**` `backend/src/main/resources/db/migration/**` の形の追加)、`.github/workflows/ci.yaml` の `detect-changes`(53〜58行目): `dorny/paths-filter` はファイルの変更だけを見るので、`go.mod` の有無の条件は `backend_compat` の `backend/compat/` の条件と同じく1つステップを足す形で書ける(サイクル3 往復1で確かめた形と同じ)。2-2 の PR では検査するコミットに `backend/go.mod` があるので、2-2 自身で `backend-go` が動く。影響なし
- design.md 「CI の仕事」の見分け `backend_compat`(変わったファイルが `backend_java` か `backend_go` か `backend/compat/**` に当たるとき): `backend_go` に `go.mod` の条件が付いたので、`backend_compat` の判定が変わらないかを確かめた。`backend/compat/` は 2-3 で初めて main に入り、そのとき `backend/go.mod` は 2-2 で入っているので、判定は変わらない。影響なし
- design.md 「CI の仕事」の `backend-test` の箇条(見分けが当たったのに飛ばされた仕事があれば失敗)と「段階ごとの PR」の最後の段(2-1 から 2-2 のあいだは `backend_go` が当たらず、Java 版の結果だけで決まる): 2-1 から 2-2 のあいだに `backend/api/**` だけを変えた PR では、どの見分けも当たらず、`backend-test` は判定する仕事が無いまま成功する。段の文と矛盾しない。影響なし
- design.md 「所有者に提案するゲート設定の変更」の `check-verify-before-stop.sh` の箇条(見分け方は CI の `backend_java` `backend_go` と同じ。マイグレーションのファイルが変わったときは両方の記録を求める): `backend_go` の形にマイグレーションのファイルが入ったので、「両方の記録」の文と食い違わないかを確かめた。マイグレーションのファイルは `backend_java`(`backend/src/**`)と `backend_go` の両方に当たるので、同じ意味になり食い違わない。`go.mod` の有無の条件は、フックが動く作業フォルダでは、Go 版の形のファイルを変える会話が 2-2 以降であり、そのとき `backend/go.mod` はあるので、どちらに読んでも結果は変わらない。影響なし
- design.md 「段階6の削除と書き換え」の 6-1 の「段階2で足した移行のための条件を、次の5つのとおりに消すか元の1つの形に戻す」の箇条: 差分で `backend_go` に 2-1 から 2-2 のあいだのための条件が足されたので、6-1 がその条件を消すかを確かめた(指摘 D6-1-1)。6-1 の1つ目の箇条の4(マイグレーションのファイルを `backend/db/migrations/` に移す)と、「CI の仕事」のマイグレーションの段で形を `backend/db/migrations/**` に替える文は、同じ PR を指す。影響なし
- requirements.md 要件3 の 3.2(Go 版のコードを変えた PR では Go 版の品質チェックが必ず動く)と 3.5: Go 版のコードを変えた PR には `backend/go.mod` があるので、条件を足しても 3.2 は満たされる。影響なし
- design.md 「失敗したときの扱い」の2つ目の箇条(理由を「CI の仕事」の「いつ動くか」の参照に替えた): 参照先(480行目)に、PR が最新の main を取り込んでいることを求めることと、一方だけを直した PR が `backend-compat` に止められることが書かれている。影響なし
- design.md 「migrate」の失敗したとき、「httpapi」の要求の形の誤りの段、6-1 の箇条の番号つきへの分け直し: 主語の追加と語の説明の追加と分け直しだけで、設計の中身が変わっていないことを前後の文で確かめた。影響なし

### 申告

(今回の差分で新しく申告するものはない)

### 指摘

| ID | レベル | 該当箇所 | 内容 | 直し方の案 |
|---|---|---|---|---|
| D6-1-1 | 低 | design.md 「段階6の削除と書き換え」の 6-1 の「段階2で足した移行のための条件を、次の5つのとおりに消すか元の1つの形に戻す」の箇条、「CI の仕事」の `backend_go` の行と理由の段 | 差分で `backend_go` に足した「検査するコミットに `backend/go.mod` があり」の条件は、理由の段のとおり、PR 2-1 が main に入ってから PR 2-2 が入るまでのあいだのための条件であり、段階2で足す移行のための条件に当たる。しかし 6-1 の5つの一覧に、この条件を消すことが無い。`backend_compat` は 6-1 で見分けごと消えるのに対し、`backend_go` は残るので、この条件だけが残る。6-1 のあと `backend/go.mod` は常にあるので判定は変わらず、実装には影響しない | 6-1 の一覧の1に「`backend_go` の `backend/go.mod` があることの条件を消す」を足す。または、「CI の仕事」の理由の段に「この条件は 6-1 で消す」と1文を足す |

### 前の段階への指摘

| ID | 対象 | 該当箇所 | 内容 |
|---|---|---|---|
| (なし) | | | |

- 往復: 1回で収束 / 未解決: 0件

## サイクル7 往復1(2026-11-08)

### 審査の範囲

範囲: 差分

- design.md 「所有者に提案するゲート設定の変更」の `check-verify-before-stop.sh` の箇条(96行目。T2-1-2 の直しで足した「作業フォルダに `backend/go.mod` があるときだけ Go 版の記録を求める」の2文)、`.claude/hooks/check-verify-before-stop.sh` の実ファイル、tasks.md タスク1.2 と 10.5: 今のフックは `git status --porcelain -z` で変わったファイルを読み、`backend/` の下の変更に領域 `backend` の記録(`gate-run-backend.txt`)を求める形であり、箇条の「今は」の説明と合う。作業フォルダに `backend/go.mod` があるかの条件は、フックが作業フォルダで動くので足せる。条件の理由(`go.mod` が無いと Go 版の品質チェックを動かせず記録を書けない)は、2-1 が main に入ってから 2-2 が入るまでのあいだにマイグレーションのファイルを変える会話に当たり、tasks の T2-1-1 の内容と合う。タスク1.2 の「同じ形」はこの条件を含む読みに決まった。影響なし
- design.md 「段階6の削除と書き換え」の 6-1 の「段階2で足した移行のための条件を、次の6つのとおりに消すか元の1つの形に戻す」の一覧(768〜776行目)と、「CI の仕事」の見分け `backend_go` の行と理由の段(458行目、463行目)、tasks.md タスク10.5: 足した6つ目(`ci.yaml` の見分け `backend_go` から `backend/go.mod` があることの条件を消す)と理由の文は、463行目の条件を足した理由(2-1 から 2-2 のあいだのため)と対になり、タスク10.5 の「見分け `backend_go` から、`backend/go.mod` があることの条件を消す」と一致した。D6-1-1(低)は解消した。フックの `go.mod` の条件は6つ目に名指しされていないが、3つ目の「記録の分け方を消す」と、96行目の「`backend/` の下の変更に Go 版の記録だけを求める形に戻す」が、条件の無い元の形を終わりの状態として定めており、タスク10.5 も同じ終わりの状態を書いているので、実装で条件が残る余地は無い。指摘にしない
- design.md 「段階ごとの PR」の箇条(993行目。消えた最後の段と、2-1 の箇条に足した「2-1 は Go のファイルを含まない」)、「CI の仕事」の 463行目、requirements.md 要件3 の受入基準5、tasks.md タスク1.4 の「受入基準とテストの対応」(33行目): 消えた段の中身のうち、2-1 に Go のファイルが無いことは 993行目に、2-1 から 2-2 のあいだに `backend_go` が当たらないことと `backend-test` が失敗しないことは 463行目にあり、受入基準5(Go 版のコードが main に入るのは品質チェックを足す PR かそれより後)の裏付けは残っている。タスク1.4 の「`backend_go` と `backend_compat` が当たらず `backend-java` が success なら成功する」の場合も、463行目と `backend-test` の判定の文から読める。影響なし
- design.md 「段階6の削除と書き換え」の必須の検査の箇条(788行目。`dependency-cooldown` を「公開の時刻の検査」に言い換えた)、`.github/workflows/dependency-review.yaml` 113〜121行目と 148〜150行目: `dependency-review` と `dependency-cooldown` の仕事はどちらも `needs: [generate, submit]` であり、文のとおりである。41行目で「この設計は、dependency-cooldown を『公開の時刻の検査』と呼ぶ」と決めているので、言い換えで指す先は変わらない。影響なし
- design.md 「pdf」の状態の持ち方(382行目。利用者の入力の置き換えを「安全」の節の参照に替えた)、「安全」の節(946行目): 参照先に、出力のまとまりの spec で作る Go 版のコードが、Java 版のテンプレートと同じ5つの文字を置き換えることが書かれている。元の文の「すべて」より参照先のほうが正確で、食い違いは無くなった。影響なし
- design.md 「作らないもの」の最後の箇条(28行目。「すでに書かれた spec」を「この spec が main に入った時点ですでに書かれていた spec」に直した)、「ファイルの構成」の `.kiro/specs/backend-go-replacement/` のファイル(225〜237行目)、「段階6の削除と書き換え」の 6-4 の検査(796行目)、進み具合の表の `.kiro/specs/<名前>`(898行目): この spec が自分のフォルダに書く progress.md、runbook.md、research.md、`changed-behaviors.yaml` と、段階3で新しく作るまとまりの spec は、いずれも「すでに書かれていた spec」に当たらない。6-4 の検査は `.kiro/specs/` を除いている。時点を定めたことで境目がはっきりし、本文と矛盾しない。影響なし
- design.md 「Dockerfile.prod」の役割(658〜664行目。1つの段を5つの箇条に分けた)、「migrate」の状態の持ち方(337〜341行目。3つの箇条に分けた)、「compat harness」の比べ方の箇条(557〜560行目)、「pdfcmp」の比べ方の箇条(637〜640行目)、「api-docs」「backend-deploy.yaml と release.yaml」「まとまりの順番」「ファイルの構成」の3つの見出しの文、「作らないもの」の1つ目: 分け直しと主語の追加だけであり、設計の中身(工程の中身、フォントの写し元と段階6の移し先、uid 10001、`EXPOSE 8080`、生きているかの確認の経路、CRC32 の計算、書く列、`pg_advisory_lock`、比べるヘッダと UUID と日時の置き換え、`pdffonts` と `pdftotext -bbox-layout` の比べ方、タグの形と要約への記録)が変わっていないことを前後の文で確かめた。影響なし

### 申告

(今回の差分で新しく申告するものはない)

### 指摘

| ID | レベル | 該当箇所 | 内容 | 直し方の案 |
|---|---|---|---|---|
| (なし) | | | | |

### 前の段階への指摘

| ID | 対象 | 該当箇所 | 内容 |
|---|---|---|---|
| (なし) | | | |

- 往復: 1回で収束 / 未解決: 0件

## サイクル8 往復1(2026-11-09)

### 審査の範囲

範囲: 差分

- design.md 「httpapi」の中間処理の3(367行目。`/api/auth` の下を検査しない文と、トークンを `crypto/rand.Text` で作る文を足した)、`backend/src/main/java/com/example/keirekipro/presentation/security/config/SecurityConfig.java` 57〜71行目と116〜117行目、同じフォルダの `CsrfCookieFilter.java`、`frontend/src/lib/protectedApiClient.ts` 25〜30行目と `publicApiClient.ts`: Java 版が偽の送信の検査から外す経路と、Java 版が Cookie `XSRF-TOKEN` を付ける場面を、Go 版の文と照らした。`/api/auth` の下を外す理由(ログインに使う通信の部品はヘッダを写さない)は、ヘッダを写すのが `protectedApiClient.ts` だけであることと合う。Cookie を付ける場面は指摘 D8-1-1、Swagger の経路は指摘 D8-1-3、トークンの値の形は指摘 D8-1-5
- design.md 「変えた動きの一覧の形」の表の CB-006〜CB-008 と、同じ節の箇条、`match` の形(823〜836行目)、「compat harness」の比べるヘッダの箇条(557行目)と `match` の照らし方(562行目)、「テストの方針」の比べる検査の筋書き(939行目。まとまりごとに偽の送信の検査に通らない要求を送る): CB-006 の `match` を今の `match` の形で書けるかを確かめた(指摘 D8-1-2)。CB-006 の Java 版の動き(Cookie が無いときだけ付ける)は、Spring Security の CsrfFilter が断るときに、遅れて読むトークンを Cookie が無いときだけ作って保存する動きと合う。CB-007 の Java 版の動きは指摘 D8-1-4。CB-008 の Java 版の動きは `ignoringRequestMatchers` の `/actuator/**` と合い、Go 版が受け付ける経路が `GET /actuator/health` だけであることは「httpapi」の呼び出し方(372行目)と合う
- design.md 「安全」の1つ目の箇条(951行目): 「3つは、Go 版の動きが Java 版と違う」が、上の2つの照らしの結果と合うかを確かめた(指摘 D8-1-3)
- design.md 「テストの方針」の httpapi の偽の送信の検査の単体テスト(930行目): 中間処理の3の動きが増えたので、足した動きを確かめるテストが方針にあるかを確かめた(指摘 D8-1-1 に含めた)
- design.md 「変えた動きの一覧の形」の表の前の文(838行目。CB-006〜CB-008 を所有者が 2026-11-09 に受け入れた): 起動の文の背景と合う。CB-005 は記録だけの項目で、所有者が受け入れた違いの数に入らないことは、サイクル5 往復1で確かめたとおりである。影響なし
- requirements.md 要件9の受入基準1・4・5・6: 4(偽の要求を断ることを Java 版と同じに守る)について、`/api/auth` の下を外すのは Java 版と同じで、CB-007 と CB-008 は検査を広げる向きなので、対策を弱めない。6(変えた動きを1つずつ一覧にし、変えた動き・Java 版の動き・Go 版の動き・画面に影響が無い理由を書く)について、CB-006〜CB-008 はどれも4つの欄を持つ。一覧に無い違いは指摘 D8-1-3 と D8-1-5。1(画面は直さずに動く)は指摘 D8-1-1
- tasks.md タスク3.5(CB-001 から CB-008 の8つ): 項目の数は design の表と合う。tasks の審査は範囲の外なので、D8-1-2 と D8-1-3 の直しで tasks が変わりうることだけを記す
- `backend/internal/httpapi/middleware/csrf.go`: 指摘 D8-1-1 の事実(今の実装は、検査を通った要求と検査しない要求にも、Cookie が無ければ新しい Cookie を付けている)を確かめるために読んだ。実装の審査はしていない

### 申告

(今回の差分で新しく申告するものはない)

### 指摘

| ID | レベル | 該当箇所 | 内容 | 直し方の案 |
|---|---|---|---|---|
| D8-1-1 | 中 | design.md 「httpapi」の中間処理の3(367行目)、「テストの方針」の httpapi の偽の送信の検査(930行目) | 中間処理の3は、新しい `XSRF-TOKEN` の Cookie を付ける場面を、検査で断るときだけ書いている。Java 版は、`CsrfCookieFilter`(SecurityConfig.java 116〜117行目)で、`OPTIONS` のほかのすべての要求について、要求に Cookie `XSRF-TOKEN` が無ければ新しい Cookie を付ける。検査を通った要求と、検査しない `GET` と、`/api/auth` の下の要求も含む。画面は、ログインや `GET` の応答でこの Cookie を受け取り、次の書き込みの要求でヘッダに写す(protectedApiClient.ts 25〜30行目)。この動きが無いと、Cookie を持たない利用者(初めてログインした利用者、Cookie を消した利用者)の最初の書き込みの操作は、必ず 403 になり、画面にエラーが出る。要件9の受入基準1(画面は直さずに動く)を支える動きが、design に無い。今の `csrf.go` はこの Cookie を付けているが、PR の判定の基準は design なので、design に無い動きは codex-review の照らしの外になる。認証のまとまりの spec で中間処理を直すときにこの動きを落としても、design とは食い違わない。比べる検査は `Set-Cookie` の名前と性質を比べる(557行目)ので、落とせば比べる検査で見つかり、戻って直すことになる。テストの方針の単体テストも、断るときの Cookie と `GET` を通すことだけを挙げ、Cookie を付ける動きと `/api/auth` の下を検査しない動きを挙げていない | 中間処理の3に、たとえば「この中間処理は、`OPTIONS` のほかの要求で、要求に Cookie `XSRF-TOKEN` が無いか空なら、検査を通った要求と検査しない要求にも新しい Cookie を付ける。画面は、この Cookie を受け取ってから書き込みの要求を送るためである。Java 版も同じ動きをする」を足す。テストの方針の httpapi の行に、Cookie の無い `GET` と `/api/auth` の下の `POST` に新しい Cookie を付けて通すこと、Cookie のある要求と `OPTIONS` には付けないこと、`/api/auth` の下の `POST` を検査しないことを足す |
| D8-1-2 | 中 | design.md 「変えた動きの一覧の形」の CB-006 の箇条(「Claude は、CB-006 の `match` を、403 の応答の `Set-Cookie` のヘッダの違いだけを許す範囲にする」)、同じ節の `match` の形(823〜836行目)、「compat harness」の `match` の照らし方(562行目)、「テストの方針」の比べる検査の筋書き(939行目) | `match` の形は、1つの操作の名前(`operation`)と、比べるもの(`target`)と、JSON の場所(`path`)と、`order_only` の組である。ステータスで絞る欄も、すべての操作に当てる書き方も無い。CB-006 の違いは、偽の送信の検査で断られる要求のすべてで出る。939行目のとおり、まとまりの spec は、まとまりごとに偽の送信の検査に通らない要求を送る筋書きを足す。harness は Cookie を版ごとに覚えるので、Cookie を持ったまま断られる段では、Java 版の応答に `Set-Cookie` が無く、Go 版の応答にはある。この違いが毎回出る。今の形で書くと、操作ごとに項目を足すか、`operation` を書かずにすべての応答の `Set-Cookie` の違いを許すことになる。前者では CB-006 が1つの項目でなくなる。後者では、断らない応答の `Set-Cookie` の違いも許すので、D8-1-1 の動きを落としても比べる検査が見つけられなくなる。タスク3.5 で `changed-behaviors.yaml` を書くときに必ず突き当たり、design の形を直しに戻る | `match` の形に、ステータスで絞る欄(例: `status: 403`)と、すべての操作に当てる書き方(例: `operation: "*"`)を足す。CB-006 の `match` を、たとえば `{operation: "*", status: 403, target: header, path: Set-Cookie}` と書くと決める。`target: header` のときの `path` はヘッダの名前と読むことも書く。あわせて、「テストの方針」の比べる検査の土台(936行目)に、ステータスで絞った項目が、ほかのステータスの応答の違いを許さないことの確かめを足す |
| D8-1-3 | 中 | design.md 「httpapi」の中間処理の3(`/api/auth` の下だけを検査しない)、「変えた動きの一覧の形」の表と CB-008、「安全」の1つ目の箇条(「この3つは、変えた動きの一覧の CB-006 から CB-008 に載せた」) | Java 版は、`/api/auth/**` と `/actuator/**` のほかに、`/swagger-ui/**` と `/swagger-ui.html` と `/v3/api-docs` と `/v3/api-docs/**` も、偽の送信の検査から外している(SecurityConfig.java 65〜71行目)。Go 版はこれらの経路も検査する。たとえば、Cookie もヘッダも無い `POST /v3/api-docs` に、Java 版は検査をせずに先の処理の応答を返し、Go 版は 403 を返す。CB-008 と同じ種類の違いだが、一覧に無い。「安全」の箇条は、偽の送信の検査の違いを3つと言い切っている。要件9の受入基準6は変えた動きを1つずつ一覧にすることを求め、所有者は設計の承認のときに、この一覧で違いを確かめる。比べる検査はこれらの経路に要求を送らないので、一覧に無いままでも、後の工程の誰も気づかない。画面への影響は無い | CB-009 を足すか、CB-008 に含める。例: 「Java 版は、`/swagger-ui` と `/v3/api-docs` の下の経路への要求を、偽の送信の検査にかけない。Go 版は、この経路を受け付けず、`GET` `HEAD` `OPTIONS` のほかの要求を検査する。API の説明画面は開発環境の `api-docs` のサービスに移り、画面はこの経路を呼ばないので、画面の動きは変わらない。比べる検査はこの経路に要求を送らないので、記録だけの項目にする」。所有者の受け入れが要る。「安全」の箇条の数と、表の前の文と、タスク3.5 の項目の数も合わせて直す |
| D8-1-4 | 低 | design.md 「変えた動きの一覧の形」の CB-007 の箇条(「Java 版は、`TRACE` の要求を偽の送信の検査にかけない」) | Spring Security の既定の検査は `GET` `HEAD` `TRACE` `OPTIONS` を外すので、文は Spring Security の設定としては正しい。ただし、Spring Boot に入っている Tomcat は、既定(コネクタの `allowTrace` が false)では、`TRACE` の要求を Spring Security の検査より前に 405 で断ると考える。そうであれば、Java 版の動きは「405 で断る」と書くほうが正確である。Go 版は、Cookie とヘッダの無い `TRACE` に 403 を返す。違いがあることも画面に影響が無いことも変わらず、`match` も持たないので、実装には影響しない。私は実測していない | 比べる検査の Java 版に `TRACE` を1回送って確かめ、CB-007 の Java 版の動きの欄を、確かめた結果に合わせる |
| D8-1-5 | 低 | design.md 「httpapi」の中間処理の3(「Cookie `XSRF-TOKEN` の値を、Go の標準ライブラリの関数 `crypto/rand.Text` で作る」)、「変えた動きの一覧の形」 | Java 版の `CookieCsrfTokenRepository` はトークンを UUID の文字列(36文字)で作る。Go 版の `crypto/rand.Text` は base32 の26文字を返す。Cookie の値の形が変わるが、一覧に無い。画面は値をそのまま写し、両方の版とも Cookie とヘッダが一致するかだけを見るので、切り替えの途中に版をまたいでも通る。比べる検査も Cookie の値を比べない(557行目)。実装には影響しない | 一覧に記録だけの項目として足す。または、値の形は利用者が目にしない動きに当たらないと判断した理由を、中間処理の3に1文で書く |

### 前の段階への指摘

| ID | 対象 | 該当箇所 | 内容 |
|---|---|---|---|
| (なし) | | | |

- 往復: 1回目 / 高0 中3 低2

## サイクル8 往復2(2026-11-09)

### 審査の範囲

範囲: 差分

- design.md 「httpapi」の中間処理の3(367〜373行目。6つの箇条に分け、Cookie を付ける場面と `OPTIONS` の扱いを足した)、`backend/src/main/java/com/example/keirekipro/presentation/security/config/CsrfCookieFilter.java`、`SecurityConfig.java` 57〜71行目と110〜117行目、`backend/src/main/java/com/example/keirekipro/presentation/security/jwt/JwtAuthenticationFilter.java`: 足した2つ目と3つ目の箇条を Java 版の動きと照らした。Java 版の `CsrfCookieFilter` は `OPTIONS` を除くすべての要求で、Cookie が無ければトークンを作って保存する。値が空の Cookie も、`CookieCsrfTokenRepository.loadToken` が無いものとして扱うので、新しい Cookie が付く。`/api/auth/**` のような検査から外す経路では、`CsrfFilter` が属性を置いたあとに `getToken()` が呼ばれる。Go 版の「無いか値が空なら付ける」「`OPTIONS` には付けない」と合う。D8-1-1 は解消した。6つ目の箇条(ログインの状態の検査より前に置く)は、Java 版の `JwtAuthenticationFilter` が `CsrfFilter` より前に動くことと照らした。結果は指摘 D8-2-1 に含めた
- design.md 「変えた動きの一覧の形」の `match` の説明(842行目)、CB-006 の箇条(863行目)、「compat harness」の比べるヘッダの箇条(563行目)と `match` の照らし方(568行目)、「テストの方針」の比べる検査の土台(944行目): `operation: "*"` と `status` と、`target: header` のときの `path` の読み方を、CB-006 の `match` で書けるかを確かめた。Cookie を持ったまま断られる要求では、Java 版の 403 に `Set-Cookie` が無く、Go 版の 403 にはある。この違いを許すことと、200 の応答の Cookie を付ける動きの違いを許さないことは書けている。D8-1-2 は解消した。ほかの Cookie の違いも許す範囲が残る点は指摘 D8-2-1
- design.md 「変えた動きの一覧の形」の表の CB-009 と箇条(856行目、866行目)、「api-docs」(400〜404行目。対応する要件 14.1, 14.3, 14.4、Go 版のコードに説明画面も仕様書の配信も入れない)、`backend/src/main/resources/application-dev.yaml` の springdoc、requirements.md 要件14の受入基準3・4: CB-009 の Java 版の経路4つは `ignoringRequestMatchers` と合う。Go 版がこれらの経路を受け付けないことは「api-docs」の節の決定と合い、要件14の受入基準3を挙げるのは、「api-docs」が 14.3 を受け持つ書き方と食い違わない。4つの欄(変えた動き、Java 版、Go 版、画面に影響が無い理由)がある。D8-1-3 は解消した
- design.md 「変えた動きの一覧の形」の表の前の文(844行目。CB-006〜CB-008 を所有者が 2026-11-09 に受け入れた): CB-009 はこの文に入っていない。response のとおり、所有者が設計の承認のときに確かめる項目であり、本文はまだ受け入れたとは書いていないので、食い違わない。影響なし
- design.md 「安全」の1つ目の箇条(959行目): 数を4つにし、CB-006 から CB-009 を挙げることが、表と合う。前の往復で照らしたほかの経路(`/api/auth`、`/actuator`)と合わせて、Java 版が検査から外す経路はすべて一覧で扱われた。影響なし
- design.md 「テストの方針」の httpapi の偽の送信の検査(938行目): 中間処理の3の箇条とテストの文を照らした。指摘 D8-2-2
- requirements.md 要件9の受入基準1・4・5・6: 1は、Cookie を持たない利用者の最初の書き込みが 403 にならない動きが design に入り、満たされた。4は、足した動きが Cookie を付けるだけで検査を弱めないので満たされる。6は、CB-009 で一覧が埋まった。5は、変えた動きがどれも利用者が目にしない動きに当たる。CB-006 の Java 版の欄の細かい書き方は指摘 D8-2-3
- tasks.md タスク3.5(227行目。CB-001 から CB-008 の8つ、記録だけの項目に CB-009 が無い): CB-009 を足したので、design と食い違う。tasks の審査は範囲の外なので、tasks を直す必要があることだけを記す

### 申告

(今回の差分で新しく申告するものはない)

### 指摘

| ID | レベル | 該当箇所 | 内容 | 直し方の案 |
|---|---|---|---|---|
| D8-2-1 | 低 | design.md CB-006 の箇条(863行目。`path: Set-Cookie`)、`match` の説明(842行目)、中間処理の3の6つ目の箇条(373行目) | 比べる検査は `Set-Cookie` を Cookie の名前ごとに比べる(563行目)。一方、CB-006 の `match` は、ヘッダの名前 `Set-Cookie` で当てる。そのため、403 の応答なら、`XSRF-TOKEN` のほかの Cookie の違いも許す。たとえば、Java 版の `JwtAuthenticationFilter` は `CsrfFilter` より前に動き、ログインの状態のトークンが不正なら、偽の送信の検査で断る 403 の応答にも、`accessToken` を消す `Set-Cookie` を付ける。Go 版は、偽の送信の検査をログインの状態の検査より前に置くので、この Cookie を付けないことがありうる。この違いは CB-006 の `match` に当たるので、比べる検査が見つけず、一覧にも載らない。どちらの版でも次の要求でこの Cookie は消えるので、画面の動きは変わらず、実装には影響しない | `target: header` で `Set-Cookie` を当てるときは Cookie の名前まで書ける形にし(例: `path: Set-Cookie`、`cookie: XSRF-TOKEN`)、CB-006 の `match` を `XSRF-TOKEN` に絞る。あわせて、認証のまとまりの spec で、断る 403 の応答で `accessToken` を消すかを Java 版と照らすと1文足す |
| D8-2-2 | 低 | design.md 「テストの方針」の httpapi の偽の送信の検査(938行目。「Cookie のある要求と `OPTIONS` の要求に Cookie を付けないこと」) | 同じ行の1つ目の文と中間処理の3の1つ目の箇条では、Cookie とヘッダが一致しない `POST` には、要求が Cookie を持っていても新しい Cookie を付ける。文字どおりに読むと、「Cookie のある要求に Cookie を付けない」と食い違う。中間処理の3の2つ目の箇条から、検査を通った要求と検査しない要求のことだと読めるので、実装には影響しない | 「Cookie のある要求のうち、検査を通った要求と検査しない要求と、`OPTIONS` の要求に Cookie を付けないこと」と書く |
| D8-2-3 | 低 | design.md CB-006 の箇条(863行目。「要求に Cookie `XSRF-TOKEN` が無い場合だけ、新しい Cookie を付ける」) | Java 版の `CookieCsrfTokenRepository.loadToken` は、値が空の Cookie も無いものとして扱う。そのため、Java 版は、値が空の Cookie で断られる要求にも新しい Cookie を付ける。中間処理の3の2つ目の箇条は「無いか値が空なら」と書いており、CB-006 の Java 版の欄だけが空の場合を落としている。比べる検査は Cookie の値を比べず、`match` も 403 の `Set-Cookie` を許すので、実装には影響しない | CB-006 の Java 版の欄を「要求に Cookie `XSRF-TOKEN` が無いか値が空の場合だけ」にする |

### 前の段階への指摘

| ID | 対象 | 該当箇所 | 内容 |
|---|---|---|---|
| (なし) | | | |

- 往復: 2回で収束 / 未解決: 0件

## サイクル9 往復1(2026-11-09)

### 審査の範囲

範囲: 差分

- design.md 「所有者に提案するゲート設定の変更」の `check-verify-before-stop.sh` の箇条(96〜101行目。1つの段を5つの箇条に分けた): 分ける前の段の中身(記録を分けること、見分け方を CI の `backend_java` `backend_go` と同じにすること、`backend/go.mod` があるときだけ Go 版の記録を求めることとその理由、マイグレーションのファイルで両方の記録を求めること、段階6で戻すこと)が5つの箇条にすべてあることを確かめた。「Go 版だけを直す会話で…止められることが無いようにするため」の理由の文は、分ける前はマイグレーションの文の後ろにあり、「記録を分ける」の箇条に移った。この理由は記録を分けることの理由であり、マイグレーションのファイルで両方を求めることの理由ではないので、移した先は正しい。サイクル6 往復1とサイクル7 往復1で照らした中身は変わっていない。影響なし
- design.md 「Dependabot と公開の時刻の検査と脆弱性の直し」の公開の時刻の検査の段(518行目。T3-1-5 の直し)、`.github/scripts/lib-gomod-index.sh` 1〜40行目と129〜171行目、`check-dependency-cooldown.sh` 83〜84行目と `check-release-age.sh` 82〜83行目(どちらも `lib-gomod-index.sh` を読み込む)、`.github/workflows/dependabot-auto-merge.yaml` 110〜112行目(`Check release age` の `timeout-minutes: 5`)、`dependency-review.yaml` 152行目(`timeout-minutes: 30`): 読み始め(検査の時刻の73時間前)、4時間ずつの区間に分けて同時に読むこと、区間の中を `since` で順に読むこと、1回の問い合わせに約4秒、73時間を順に読むと約10分は、ライブラリの説明と処理に合う。「索引は1回の検査で1度だけ読み」も、区間ごとに1度ずつ読む形と矛盾しない(区間の境の行を2度読むことはあるが、照らし方で新しい方の時刻を使う)。5分の上限がどの手順のものかは指摘 D9-1-1
- design.md 「所有者に提案するゲート設定の変更」の `check-release-age.sh` の箇条(103行目。「公開の時刻の検査と同じ方法で調べる」): 同じライブラリを読み込む実装と合うので、区間に分けて読む形はこの箇条にもそのまま当たる。影響なし
- design.md 「migrate」の失敗したとき(354行目。T3-1-6 の直し)、同じ節の役割(344行目)と状態の持ち方の書く行(351行目)、「テストの方針」の migrate(947行目)、`backend/internal/platform/migrate/migrate.go` 62〜65行目と321〜364行目、`backend/src/main/resources/application.yaml` 21〜22行目: Java 版が `baseline-on-migrate: true` と `baseline-version: 0` で動くこと、実装が種類 `BASELINE` の行を版の照らしから外し、その版以下のファイルを未適用に数えないことを確かめた。本文と合う。役割の「適用済みの版の検査の値が合わなければ、起動を止める」とは、BASELINE の行がファイルに当たる適用済みの版でないので食い違わない。書く行の `type` が `SQL` だけであることは、この部品が BASELINE の行を書かないことと合う。テストの方針にも同じ動きが足された。影響なし
- design.md 「config」の `dev` と `test` の5つの箇条(330〜336行目。T3-1-7 の直し)、同じ節の失敗したとき(338行目)、`backend/internal/platform/config/config.go` 84〜142行目と230〜249行目、`docker/localstack/init-localstack.sh` 40〜49行目、「fakeaws と fakeoidc」の使う部品(598〜606行目)、「database と redisstore と awsclient」の役割(360行目)、「使う既存の仕組み」の本番の行(32行目): 実装が外部のログインの2つの秘密の値をどの環境でも Secrets Manager から読むこと、`KEIREKIPRO_AWS_ENDPOINT` が無いときの既定を `dev` と `test` で `http://localstack:4566`、`prod` で空にすることを確かめた。本文と合う。開発環境の localstack は2つの秘密の値を作るので、`dev` で Go 版を起こしても失敗したときの「読めない秘密の値」のエラーにはならない。比べる検査が fakeaws に2つの秘密の値を置くこと(604行目)と、Go 版を `KEIREKIPRO_AWS_ENDPOINT` で fakeaws につなぐこと(606行目)とも合う。理由の「Java 版も `dev` でこの2つを localstack から読み」は、600行目の Java 版の `dev` が Secrets Manager から読むことと合う。2つ目の箇条の「秘密の値の代わりに」は、挙げた環境変数が `keirekipro/rds` `keirekipro/redis` `keirekipro/jwt` の分だけで、3つ目の箇条が外部のログインの分を名指しするので、読み違えない。テストの方針との関係は指摘 D9-1-2
- design.md 「使う技術」の Redis の行(172行目。「本番(`prod`)」と「`dev` と `test`」に言い換えた)、「ファイルの構成」の `terraform/modules/alb/` の行(「ターゲットグループ」に言い換えた)、「段階6の削除と書き換え」の 6-4 の検査の文(764行目の表の 6-4 の名前を足した)、CB-009 の箇条(要件14の受入基準3の中身を足した。requirements.md 267行目): 言い換えと語の説明の追加だけで、設計の中身が変わっていないことを、前後の文と参照先(360行目の redisstore、764行目の表、requirements.md 267行目)で確かめた。影響なし
- tasks.md: tasks の審査は範囲の外。今回の design の3つの直しは、tasks-review のサイクル3 往復1の T3-1-5〜T3-1-7 が求めた中身と合う

### 申告

(今回の差分で新しく申告するものはない)

### 指摘

| ID | レベル | 該当箇所 | 内容 | 直し方の案 |
|---|---|---|---|---|
| D9-1-1 | 低 | design.md 「Dependabot と公開の時刻の検査と脆弱性の直し」の公開の時刻の検査の段(518行目。「判定の手順の5分の上限に収まらないためである」) | この段の主語は公開の時刻の検査(dependency-cooldown。41行目の呼び方)で、その仕事の上限は `dependency-review.yaml` 152行目の30分である。順に読んで約10分でも、この仕事は30分に収まる。5分の上限は、`dependabot-auto-merge.yaml` の判定の手順 `Check release age`(110〜112行目)のもので、この手順が動かす `check-release-age.sh` も同じ `lib-gomod-index.sh` で索引を読む(`lib-gomod-index.sh` 29行目の説明もこの手順の上限を理由に挙げている)。本文の「判定の手順」は design のどこにも定義が無く、公開の時刻の検査の手順と読める。そのため、区間に分けて読む理由が、主語の検査について事実と合わない。実装は同じライブラリで両方を区間に分けて読んでおり、design の文で実装が変わることはないので、実装には影響しない | 理由の文を「73時間を順に読むと約10分かかり、同じ読み方を使う Dependabot の PR の自動マージの判定(`dependabot-auto-merge.yaml` の `Check release age`。103行目の `check-release-age.sh`)の5分の上限に収まらないためである」のように、どの手順の上限かを名指しする形にする |
| D9-1-2 | 低 | design.md 「テストの方針」の config の行(948行目)、「config」の `dev` と `test` の3つ目と4つ目の箇条(334〜335行目) | 今回の直しで、config に、`dev` と `test` でも外部のログインの2つの秘密の値を Secrets Manager から読む動きと、`KEIREKIPRO_AWS_ENDPOINT` が無いときの接続先の既定が `dev` と `test` で `http://localstack:4566`(`prod` では空)になる動きが足された。同じ直しで migrate のテストの方針には BASELINE の行の動きが足されたが、config のテストの方針は「`prod` で5つの秘密の値」「`dev` で環境変数」のままで、足した2つの動きを確かめるテストを挙げていない。実装は済んでおり、design の文で実装が変わることはないので、実装には影響しない | config の行に「`dev` と `test` でも外部のログインの2つの秘密の値を Secrets Manager から読むこと。`KEIREKIPRO_AWS_ENDPOINT` が無いとき、`dev` と `test` は `http://localstack:4566` に、`prod` は AWS の既定の接続先につなぐこと」を足す |

### 前の段階への指摘

| ID | 対象 | 該当箇所 | 内容 |
|---|---|---|---|
| (なし) | | | |

- 往復: 1回で収束 / 未解決: 0件

## サイクル10 往復1(2026-11-10)

### 審査の範囲

範囲: 差分

- design.md 「httpapi」の対応する要件(372行目)と中間処理の3(378〜383行目。CORS の処理の5つの箇条)と、番号が繰り下がった4と5(384〜391行目)、`backend/src/main/java/com/example/keirekipro/presentation/security/config/SecurityConfig.java` 52〜55行目と122〜133行目: 足した CORS の処理を、Java 版の CORS の設定(許す送り元は `cors.allowed-origins`、6つのメソッド、ヘッダはすべて、Cookie を付けた要求を許す、ブラウザに見せるヘッダ `Content-Disposition` と `X-Request-Id`、プリフライトの結果を覚える時間は決めない)と、Spring の CORS の処理(`DefaultCorsProcessor`)の動きに照らした。すべての応答に `Vary` の3つの値を付けること、`Origin` が無い要求と同じ送り元の要求を CORS の要求として扱わないこと、許さない送り元とメソッドに 403 と本文 `Invalid CORS request` を返すこと、プリフライトに 200 を返して先に渡さないこと、`Access-Control-Expose-Headers` をプリフライトでない応答だけに付けること、`Access-Control-Max-Age` を付けないことは合う。Spring の動きは私の知る Spring Framework 6 のソースによるもので、実測していない。プリフライトでない要求のメソッドの照らしと、`Access-Control-Request-Headers` が無いプリフライトの扱いは指摘 D10-1-3。CORS の処理を偽の送信の検査とログインの状態の検査より前に置く順は、Java 版の Spring Security で CORS の処理が `CsrfFilter` より前に動くことと合う。中間処理の4の `OPTIONS` の扱い(検査せず、Cookie を付けない)は、許す送り元のプリフライトが3で返るので食い違わない
- design.md 「config」の環境ごとの値(321行目)と `dev` と `test` の1つ目の箇条(332行目)、`backend/src/main/resources/application-dev.yaml` 29〜30行目と `application-prod.yaml` 34〜35行目: Java 版の `dev` の許す送り元が `http://localhost:5173`、`prod` が `https://app.keirekipro.click` であることと合う。`test` の既定の値を `dev` と同じにすることと、`test` にも `http://localhost:8082` を足すことは食い違わない。影響なし
- design.md 「api-docs」の対応する要件と Go 版を呼ぶ設定(419〜429行目)、「作るもの」(19行目)、「ファイルの構成」の `compose.yaml` と `doc/開発フロー/参加者セットアップ手順.md` の行(235行目、237行目)、`backend/api/openapi.yaml` 74〜77行目(`servers` は `http://localhost:8081`)と1398〜1405行目(`XsrfTokenHeader` は `in: header` の `X-XSRF-TOKEN`)、`compose.yaml` 76〜87行目、`backend/src/main/java/com/example/keirekipro/presentation/shared/utils/CookieUtil.java`(ログインの状態の Cookie は `SameSite=Lax`)、`backend/internal/httpapi/middleware/csrf.go`(`XSRF-TOKEN` は `Path=/` だけで `HttpOnly` を付けない): 「Try it out」の3つの手順が成り立つかを確かめた。`localhost:8082` と `localhost:8081` は送り元が違うがサイトは同じ(サイトはポートを見ない)なので、Cookie を付けて送らせれば `SameSite=Lax` の Cookie も送られる。Swagger UI の公式のイメージが環境変数 `WITH_CREDENTIALS` を設定 `withCredentials` に写すことは、私の知る Swagger UI の文書によるもので、このリポジトリでは実測していない。Go 版のログインの API が、段階3の認証のまとまりの spec まで 501 を返すことは指摘 D10-1-2
- design.md 「fakeaws と fakeoidc」の使う部品(612行目)、「compat harness」の比べるヘッダの箇条(588行目)、`backend/compat/harness/` を `Origin` と `Vary` で Grep した結果: harness に `Origin` を付ける処理は無く(`Vary` は `compare_test.go` 257行目の比べないヘッダの試験だけ)、`Vary` は比べるヘッダに入っていないので、「CORS の許す送り元の違いは比べる結果に出ない」は事実と合う。影響なし
- design.md 「変えた動きの一覧の形」の表の前の文と CB-010 の行と箇条(869行目、882行目、893行目)、requirements.md 要件9の受入基準5・6: CB-010 は4つの欄(変えた動き、Java 版、Go 版、画面に影響が無い理由)を持ち、`match` を持たない理由(比べる検査は `Origin` を付けない)は上の照らしと合う。本番の許す送り元は両方の版で同じなので、利用者が目にしない動きに当たる。影響なし
- design.md 「安全」の2つ目の箇条(987行目)と「テストの方針」の単体テスト(962〜967行目)、`frontend/.env.production`(`VITE_API_URL=https://app.keirekipro.click/api/`)、`terraform/modules/alb/main.tf`(聞き口は `HTTPS`、ターゲットグループは `HTTP`): 「CORS の処理が Java 版と同じ応答を返すことを Go 版の単体テストで確かめる」を、テストの方針が裏付けるかを確かめた。本番の画面と API は同じ送り元だが、ブラウザは同じ送り元への書き込みの要求にも `Origin` を付け、ALB が TLS を終えるので Go 版からは方式が `http` に見え、同じ送り元と判定されない。そのため、本番でも画面の書き込みの要求は許す送り元の照らしを通る(指摘 D10-1-1)
- design.md 「作るもの」(13行目)、「ファイルの構成」の `middleware/` の行(203行目)、「段階ごとの PR」の表の 2-6 と箇条(1028行目、1038行目)、「所有者に提案するゲート設定の変更」の表、`.kiro/specs/backend-go-replacement/progress.md` 17行目: 2-6 が変えるファイル(Go 版のコード、`compose.yaml`、`changed-behaviors.yaml`、手順の文書)にゲート設定のファイルが無く、承認が「要らない」と合うこと、「作るもの」「ファイルの構成」「2-6 の箇条」の中身がそろうことを確かめた。progress.md 17行目の「段階2の PR は 2-1〜2-5」は 2-6 を含まないが、progress.md は実装で書き換えるファイルで、design の誤りではない。影響なし
- requirements.md 要件14の受入基準5〜7: 5(読み取りと書き込みを止めない)は CORS の処理の4つ目と5つ目の箇条と `WITH_CREDENTIALS` が、6(ログインの状態を付けて送る)は Cookie を付けた要求を許すことと Cookie がポートで分かれないことが、7(ヘッダを付けられる。`/api/auth` の下は除く)は `XsrfTokenHeader` の入力の欄と中間処理の4が裏付ける。「httpapi」と「api-docs」の対応する要件に3つとも載っている。確かめる時期は指摘 D10-1-2

### 申告

**1. 説明画面から Go 版を呼ぶために、開発環境の Go 版の CORS の許す送り元に説明画面の送り元を足す** — 「config」の環境ごとの値、「httpapi」の中間処理の3、CB-010

- Issue の記載: あり。「開発者向けのAPI説明画面を、開発環境で開ける」。要件14の受入基準5〜7は、所有者の指示で足された
- 決めたこと: `dev` と `test` の許す送り元を `http://localhost:5173` と `http://localhost:8082` の2つにし、Swagger UI に Cookie を付けて送らせる。Java 版との違いは CB-010 に載せる
- 他にありえた選択肢: `api-docs` のサービスに、Go 版への要求を同じ送り元のまま中継させる(説明画面の配信と同じ送り元の `/api` を Go 版に転送する)。この形なら CORS の処理に開発環境だけの送り元が要らず、CB-010 も要らない。ただし、`servers` の宛先と、中継の設定を持つ自作の設定ファイルが要る
- 外れていた場合: 所有者が Java 版との違いを増やしたくないと考えていたときは、config の既定の値と CB-010 を戻し、`api-docs` に中継の設定を足すことになる。手戻りは開発環境の設定と config の2行に限られ、本番の動きは変わらない

**2. 偽の送信の検査のヘッダの値を、開発者がブラウザの開発者ツールで読んで手で写す形にし、Swagger UI に自動で写させない** — 「api-docs」の Go 版を呼ぶ設定

- Issue の記載: なし。要件14の受入基準7は、ヘッダを付けられることだけを求める
- 決めたこと: 初期化のファイルを足さず、手順の文書に、Cookie の値を読んでヘッダの欄に入れる手順を書く
- 他にありえた選択肢: Swagger UI の要求の前の処理(`requestInterceptor`)で Cookie の値をヘッダに写す初期化のファイルを足す
- 外れていた場合: 書き込みの「Try it out」のたびに開発者が値を写す手間が残る。土台のイメージの更新で動かなくなるおそれのあるファイルは増えないので、手戻りは小さい

### 指摘

| ID | レベル | 該当箇所 | 内容 | 直し方の案 |
|---|---|---|---|---|
| D10-1-1 | 低 | design.md 「テストの方針」の単体テスト(962〜967行目)、「安全」の2つ目の箇条(987行目)、「config」の環境ごとの値(321行目) | 「安全」は、比べる検査が `Origin` を付けないので、CORS の処理が Java 版と同じ応答を返すことを Go 版の単体テストで確かめると書く。しかし、「テストの方針」の単体テストには CORS の処理の行が無く、config の行にも環境ごとの許す送り元(`prod` は `https://app.keirekipro.click` だけ、`dev` と `test` は2つ)を確かめることが無い。本番の画面と API は同じ送り元(`frontend/.env.production`)だが、ブラウザは書き込みの要求に `Origin` を付け、ALB が TLS を終えるので Go 版からは方式が `http` に見え、同じ送り元と判定されない。そのため、本番の画面の書き込みの要求はすべて許す送り元の照らしを通る。`prod` の許す送り元か照らし方を誤ると、切り替えのあと本番の書き込みの操作がすべて 403 になるが、比べる検査はこれを見つけない。単体テストがこの唯一の機械の確かめである。「安全」に単体テストで確かめると書いてあるので、tasks で拾える見込みは高く、低とする | 「テストの方針」の単体テストに、たとえば「httpapi の CORS の処理: 許す送り元のプリフライトに 200 と4つのヘッダを返して先に渡さず、`Access-Control-Max-Age` を付けないこと。許さない送り元と、6つのほかのメソッドのプリフライトに 403 と `Invalid CORS request` を返すこと。プリフライトでない要求に3つのヘッダを付けて先に渡すこと。`Origin` の無い要求と同じ送り元の要求に `Vary` だけを付けること。偽の送信の検査より前に動くこと」を足す。config の行に「`prod` の許す送り元が `https://app.keirekipro.click` だけで、`dev` と `test` が2つであること」を足す。あわせて、方式が `http` に見える要求に `Origin: https://app.keirekipro.click` を付けた `prod` の書き込みの要求が通ることも確かめると書く |
| D10-1-2 | 低 | design.md 「api-docs」の Go 版を呼ぶ設定(423〜429行目)、「段階ごとの PR」の 2-6 の箇条(1038行目)、「httpapi」の役割(374行目。まだ作っていない操作は 501 を返す)、requirements.md 要件14の受入基準6・7 | 2-6 は段階2の PR であり、Go 版のログインの API `POST /api/auth/login` は、段階3の認証のまとまりの spec で作るまで、501 と `{"message":"未実装です。"}` を返す仮の実装である。そのため、2-6 で手順の文書に書く「Try it out」の手順1(ログインする)は、2-6 が main に入ってから認証のまとまりが入るまで、手順どおりに動かない。また、design は、受入基準6(ログインした開発者の要求にログインの状態を付けて送り、その開発者への応答を返す)と7を、いつ、誰が、どう確かめるかを書いていない。比べる検査は `Origin` を付けないので、この確かめは機械には無い。Swagger UI と Cookie の扱いはブラウザの標準の動きで、外れる見込みは小さいので、低とする | 2-6 の箇条に、2-6 で確かめること(説明画面から仮の実装の操作に送った要求の 501 の応答が画面に出ること、書き込みの要求のプリフライトが通ること)を書く。受入基準6と7は、認証のまとまりの spec が終わったあとに確かめると書く(たとえば、認証のまとまりの spec の確かめに含めるか、progress.md の段階3の決まりに書く)。手順の文書には、認証のまとまりが入るまでログインの手順が使えないことを書く |
| D10-1-3 | 低 | design.md 「httpapi」の中間処理の3の4つ目と5つ目の箇条(382〜383行目)、「安全」の2つ目の箇条(987行目) | Spring の `DefaultCorsProcessor` は、プリフライトでない CORS の要求でも、要求のメソッドを許すメソッドの一覧と照らす。一覧に無いメソッドの要求には 403 と `Invalid CORS request` を返す。たとえば `HEAD` がそうで、Java 版の一覧は `GET` `POST` `PUT` `DELETE` `PATCH` `OPTIONS` の6つで `HEAD` を含まない。5つ目の箇条は、許す送り元からのプリフライトでない要求を、メソッドによらずヘッダを付けて先に渡すので、Java 版と違う。また、Spring は、プリフライトに `Access-Control-Request-Headers` が無いときは `Access-Control-Allow-Headers` を付けないが、4つ目の箇条は無いときも付けると読める。「安全」は、本番で許すメソッドを Java 版と同じにすると書く。画面は `HEAD` を送らず、比べる検査は `Origin` を付けないので、画面の動きは変わらず、実装には影響しない。Spring の動きは私の知る Spring Framework 6 のソースによるもので、実測していない | 5つ目の箇条に「要求のメソッドが6つのメソッドのどれでもなければ、403 と `Invalid CORS request` を返し、先に渡さない」を足す。4つ目の箇条を「要求に `Access-Control-Request-Headers` があれば、`Access-Control-Allow-Headers` にその値を付ける」にする。直す前に Java 版に `Origin` 付きの `HEAD` を1回送って動きを確かめるとよい。違いを残すなら、CB-010 と同じく記録だけの項目にする |

### 前の段階への指摘

| ID | 対象 | 該当箇所 | 内容 |
|---|---|---|---|
| (なし) | | | |

- 往復: 1回で収束 / 未解決: 0件

## サイクル11 往復1(2026-11-10)

### 審査の範囲

範囲: 差分

- design.md 「httpapi」の中間処理の3の5つ目の箇条(383行目。T5-1-5 の直し)、`backend/src/main/java/com/example/keirekipro/presentation/security/config/SecurityConfig.java` 123〜131行目: Java 版の許すメソッドは `GET` `POST` `PUT` `DELETE` `PATCH` `OPTIONS` の6つで、`HEAD` を含まない。Spring の `DefaultCorsProcessor` は、許す送り元の照らしのあと、プリフライトでない要求ではその要求のメソッドを許すメソッドの一覧と照らし、無ければ 403 と本文 `Invalid CORS request` を返して先に渡さない。一覧にあれば、`Access-Control-Allow-Origin` と `Access-Control-Expose-Headers` と `Access-Control-Allow-Credentials` を付けて先に渡す。直した箇条はこの動きと合い、D10-1-3 の前半(プリフライトでない要求のメソッドの照らし)は解消した。Spring の動きは私の知る Spring Framework 6 のソースによるもので、実測していない。`Access-Control-Request-Method` の無い `OPTIONS` は、プリフライトでない要求として照らされ、`OPTIONS` が6つに入るので先に渡る。これも Java 版と同じである。箇条の数は「次の5つのことをする」と合う
- design.md 「httpapi」の中間処理の4(偽の送信の検査。384〜390行目): 5つ目の箇条の直しで、許す送り元からの `HEAD` は CORS の処理で 403 になり、偽の送信の検査に届かない。偽の送信の検査が `GET` `HEAD` `OPTIONS` を検査しないことと食い違わない。`Origin` の無い `HEAD`(ALB とコンテナの生きているかの確認を含む)は CORS の要求でないので、今までどおり先に渡る。影響なし
- design.md 「安全」の2つ目の箇条(987行目)と「テストの方針」: 「本番で許すメソッドを Java 版と同じにする」は、直した5つ目の箇条で、プリフライトでない要求についても裏付けられた。「テストの方針」に CORS の処理の行が無いことは D10-1-1(低、記録のみ)の範囲で、新しい指摘にしない。4つ目の箇条の `Access-Control-Request-Headers` が無いプリフライトの扱い(D10-1-3 の後半)は、今回の差分で直されていない箇所で、D10-1-3(低、記録のみ)の範囲である。新しい指摘にしない
- requirements.md 要件14の受入基準5(269行目)、`backend/api/openapi.yaml`: 説明画面の「Try it out」が送るのは仕様書の操作のメソッドである。仕様書に `head` `trace` `options` の操作は無い(Grep で0件)ので、説明画面から Go 版への読み取りと書き込みの要求は、どれも6つのメソッドに入り、5つ目の箇条で止められない。受入基準5は満たされたままである。影響なし
- design.md 「httpapi」の中間処理の3の1〜3つ目の箇条(379〜381行目。`Vary` の説明の追加と、文の分け直し)、「api-docs」の最後の段(429行目。手順の文書に書く中身を「上の3つの手順」と名指しした)、「fakeaws と fakeoidc」の使う部品(612行目。文の分け直し)、「安全」の2つ目の箇条(987行目。主語の言い換え): 語の説明の追加と文の分け直しだけで、設計の中身が変わっていないことを前後の文で確かめた。429行目の「上の3つの手順」は、425〜427行目の3つの手順と合う。影響なし
- design.md 「変えた動きの一覧の形」の表の前の文(869行目。CB-001〜CB-004、CB-006〜CB-008、CB-010 に中身の名前を足した)、同じ節の表(871〜882行目): 足した名前が、表の CB-001〜CB-004、CB-006〜CB-008、CB-010 の「変えた動き」の欄と合うことを確かめた。どの項目を所有者がいつ受け入れたかは変わっていない。影響なし
- design.md 「段階ごとの PR」の 2-6 の箇条(1038行目。2-4、2-5、CB-010 に中身の名前を足した)、同じ節の表(1022〜1029行目): 足した名前が、表の 2-4「API の説明画面と開発の手順の文書」、2-5「Go のファイルがあることを前提にするゲート設定の Go への対応」、CB-010「開発環境の CORS の許す送り元」と合うことを確かめた。2-6 の中身と承認の要否は変わっていない。影響なし

### 申告

(今回の差分で新しく申告するものはない)

### 指摘

| ID | レベル | 該当箇所 | 内容 | 直し方の案 |
|---|---|---|---|---|
| (なし) | | | | |

### 前の段階への指摘

| ID | 対象 | 該当箇所 | 内容 |
|---|---|---|---|
| (なし) | | | |

- 往復: 1回で収束 / 未解決: 0件
