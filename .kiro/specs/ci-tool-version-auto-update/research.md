# 調べの記録

## まとめ

- 機能: `ci-tool-version-auto-update`
- 調べの種類: 既存の仕組みを広げる(Extension)。配布元の API の仕様は、実際に呼んで確かめた(2026-11-03)
- 設計を決めた発見:
  - Docker Hub には、タグが初めて公開された日時を返す欄が無い。返るのは、タグを最後に公開し直した日時(`tag_last_pushed`)と、そのときの中身の digest(`digest`)だけである。Node.js のイメージは、同じ版のタグが公開し直される(`24.22.1-bookworm-slim` は、Node.js 24.22.1 の公開から7日後に公開し直されていた)。そこで、配布元のイメージの公開日時は、`FROM` に書く digest がタグの今の digest と同じときに限り、`tag_last_pushed` とみなす
  - Dependabot は、docker の `ignore` で版のマイナーとパッチの更新を除いても、同じタグの digest だけが変わる PR を作り続ける。Dependabot の作りを読んで確かめた。そのため、開発環境の版を CI と別に上げる PR だけを止め、中身だけを新しくする PR を残せる
  - Terraform の CI の版を使う `terraform-apply.yaml` は、PR では動かない。今のままでは、更新の PR の検査で Terraform の署名が確かめられない。そこで、PR で変わった CI の版の署名を、変わった道具ごとに、必須の検査 `dependency-cooldown` の中で確かめる

## 調べたこと

### 今の版の書き場所

- きっかけ: 版の書き場所の一覧の最初の中身と、週1回の実行が書き換える場所を決めるため
- 調べたもの: `.github/workflows/*.y*ml` と `.github/actions/*/action.yml` を、`*-version:` `*_VERSION:` の形の行、`docker run` のイメージのタグ、道具を入れるコマンドの `@版` `==版` で探した
- 分かったこと:
  - Node.js: `node-version: '24.22.1'` が `ci.yaml`(2か所)、`codex-review.yml`、`frontend-vuln-fix.yaml`、`guardrails.yaml`、`mutation-report.yaml` にある。開発環境は `FROM node:24.22.2-bookworm-slim@sha256:…`(`docker/frontend/Dockerfile`)で、今すでに CI と違う
  - Trivy: `TRIVY_VERSION: '0.74.0'` が `container-scan.yaml` と `container-scan-scheduled.yaml` の `env:` にある
  - Codex CLI: `codex-version: '0.147.0'` が `codex-review.yml` にある
  - Terraform: `TF_VERSION: '1.9.0'` が `terraform-apply.yaml` の `env:` にある。開発環境は `FROM hashicorp/terraform:1.17.1@sha256:…`(`docker/terraform/Dockerfile`)である。`terraform-plan.yaml` は開発環境のイメージ(`keirekipro-terraform`)で動くので、今は書式と構文と静的な検査を 1.17.1 で、本番の状態に対する plan と apply を 1.9.0 で動かしている。`terraform-plan.yaml` は、名前に反して本番の状態を読まず、plan を流さない(`terraform-plan.yaml` のジョブ `terraform-static` の前のコメントと、`terraform-apply.yaml` の先頭のコメント)
  - 4つの道具のほかに見つかった版: `java-version: '21'`(6つのファイル)、`rhysd/actionlint:1.7.12` と `koalaman/shellcheck:v0.11.0`(`guardrails.yaml` の `docker run`)。`npx --yes jscpd`(`guardrails.yaml`)は版を書いていないので、版の書き場所の検査の対象にならない
  - 4つのアクション `verified-*` の `action.yml` は、入力の名前(`node-version:` など)に値を書いていない。説明の文の「例: 24.22.1」は値の行ではない
  - `trusted-signers.json` の Node.js の `locations` には `frontend-vuln-fix.yaml` が無い。`locations` を読むのは、ci-tool-fast-update のスキルの Step 4 だけである
- 設計への影響: 版の書き場所の一覧を1つのデータのファイルにし、ci-tool-fast-update のスキルもそのファイルを読むようにする。`locations` は消す

### Docker Hub のタグの API

- きっかけ: 配布元のイメージの公開日時と digest を取るため
- 調べたもの: `https://hub.docker.com/v2/namespaces/library/repositories/node/tags/24.22.2-bookworm-slim`、`https://hub.docker.com/v2/namespaces/hashicorp/repositories/terraform/tags/1.17.1`、レジストリの `docker-content-digest` のヘッダ
- 分かったこと:
  - 応答の最上位の `digest` は、複数の CPU の中身をまとめた一覧の digest で、`FROM …@sha256:` に書く digest と一致した(node は OCI の index、terraform は manifest list)
  - `tag_last_pushed` と `last_updated` は同じ値で、タグを最後に公開し直した日時である。初めて公開した日時の欄は無い
  - タグの一覧 `…/tags?page_size=100&name=24.` の `name` は部分一致である
- 設計への影響:
  - 公開日時は `tag_last_pushed` を使う。公開し直すと日時は新しくなるだけなので、待ちが短くなる向きには働かない
  - `FROM` の digest がタグの今の digest と違うときは、その digest の公開日時を取れないものとして扱う(検査を失敗にする)
  - 公開し直しが続くと、その版のイメージがなかなか72時間に届かず、更新の PR が遅れる。この遅れは受け入れる

### Dependabot の docker の ignore と digest だけの更新

- きっかけ: 開発環境の版を CI と別に上げる PR を止めて、中身だけを新しくする PR を残せるかを確かめるため
- 調べたもの:
  - https://docs.github.com/en/code-security/dependabot/working-with-dependabot/dependabot-options-reference
  - https://github.com/dependabot/dependabot-core/blob/main/docker/lib/dependabot/docker/update_checker.rb(2026-10-23 のコミット d78cafe)
  - https://github.com/dependabot/dependabot-core/pull/15103
- 分かったこと:
  - `ignore` の `update-types` は版の比較にだけ効く。新しいタグを除いたあと、Dependabot は今のタグに戻り、今のタグの digest と `FROM` の digest を比べて、違えば digest だけの PR を作る
  - digest だけの更新を止める仕組みは、Dependabot の中の実験の旗(`docker_digest_only_update_suppression`)にしか無く、`dependabot.yml` からは設定できない
  - 今の Dependabot の PR では、node の digest だけの更新(例 PR #550)と、版を上げる更新(グループ `docker-base-images`)の両方が届いている
- 設計への影響: `dependabot.yml` の docker の `ignore` に、`node` と `hashicorp/terraform` の `version-update:semver-minor` と `version-update:semver-patch` を足す

### 版の一覧と公開日時の取り先

- きっかけ: 上げる先の版を選ぶための版の一覧と、公開からの時間の検査に使う公開日時を取るため
- 調べたもの:
  - Node.js: `https://nodejs.org/dist/index.json`、`https://api.github.com/repos/nodejs/node/releases/tags/v24.22.1`、`https://api.github.com/repos/actions/node-versions/releases`
  - Trivy: `https://api.github.com/repos/aquasecurity/trivy/releases`
  - Codex CLI: `https://registry.npmjs.org/@openai%2fcodex`、`https://api.github.com/repos/openai/codex/releases`
  - Terraform: `https://api.releases.hashicorp.com/v1/releases/terraform?limit=20`、`…/v1/releases/terraform/1.9.0`
  - spec `security-fix-cooldown-exception` の `verify-ci-tool.sh` が使う取り先
- 分かったこと:
  - Node.js の `index.json` は、版ごとに `version` `date` `lts` `security` を返し、試作の版(`v27.0.0-alpha.0.0.0`)も含む。`date` は日付だけで、公開より早いことがある(24.22.1 は `2026-10-20` だが、公開は 2026-10-21T10:38:25Z)。`nodejs/node` の GitHub のリリースの `published_at` は時刻まで正しい
  - `actions/node-versions` のリリースは、Node.js の公開より4〜8時間遅れる。配布元の公開日時ではない
  - Trivy のタグは `vX.Y.Z` で、直近の95件に試作の版は無い
  - Codex CLI の npm の文書は約18MBで、`time` に版ごとの公開日時がある。版の一覧には、試作の版(`0.167.0-alpha.4`、`0.147.0-alpha.6.1`)と CPU ごとの部品の版(`0.147.0-linux-x64` など)が混ざる。`^[0-9]+\.[0-9]+\.[0-9]+$` で絞ると、正式な版だけが残る。短い文書(`application/vnd.npm.install-v1+json`)と版ごとの文書には `time` が無い。`…/@openai%2fcodex/latest` は `dist-tags.latest` の版の文書を返す
  - HashiCorp の一覧は、1回に20件までで(`limit` が21以上だと 422)、`timestamp_created` の新しい順に並び、`after=<日時>` でそれより前の版を返す。試作の版には `is_prerelease: true` が付く
  - spec `security-fix-cooldown-exception` は、Node.js と Trivy を GitHub のリリースの `published_at`、Codex CLI を npm の `time`、Terraform を HashiCorp の `timestamp_created` で数える
- 設計への影響:
  - 公開日時の取り先は、spec `security-fix-cooldown-exception` と同じにする。同じ版の公開日時が、記録と検査で食い違わないようにするためである
  - Node.js の版の一覧は `index.json` から取り、公開日時は候補の版ごとに GitHub のリリースから取る。`index.json` の `date` は使わない

### 変更点の文書の URL

- きっかけ: 更新の PR の本文に、版ごとの変更点の文書のリンクを書くため
- 調べたもの: 次の URL を実際に開いた(どれも 200 で、転送されない)
  - `https://github.com/nodejs/node/releases/tag/v24.22.1`
  - `https://github.com/aquasecurity/trivy/releases/tag/v0.74.0`
  - `https://github.com/openai/codex/releases/tag/rust-v0.147.0`
  - `https://github.com/hashicorp/terraform/releases/tag/v1.9.0`
- 設計への影響: 4つの道具とも、配布元の GitHub のリリースの URL を、版から組み立てる

### 更新の PR を作るトークンとブランチの決まり

- きっかけ: 週1回の実行が、ワークフローのファイルを変えたブランチを push し、開いている PR のブランチを作り直せるかを確かめるため
- 調べたもの: `doc/開発フロー/基盤構築手順.md`、`gh api repos/:owner/:repo/rulesets/2986186`、`gh api repos/:owner/:repo`、`.github/CODEOWNERS`、`frontend-vuln-fix.yaml`
- 分かったこと:
  - `BOT_GITHUB_TOKEN` は bot の classic PAT で、scope は `repo` `read:org` `workflow` である。`.github/workflows/` の下のファイルを変えたコミットを push するには `workflow` の scope が要り、この PAT は持っている
  - リポジトリの決まり(ruleset)は既定のブランチ(main)だけに掛かる。main 以外のブランチは、作り直して強制的に push できる
  - main の決まりには、`require_code_owner_review: true` と `dismiss_stale_reviews_on_push: true` がある。`.github/` は CODEOWNERS で所有者のものなので、`.github/` を変える PR は所有者の承認が要り、push のたびに承認が外れる
  - `docker/` は CODEOWNERS に無い。開発環境の `FROM` だけを変える PR は、今のままでは所有者の承認なしにマージされる
  - リポジトリは個人の持ち物(`owner.type: User`)で公開されている。`delete_branch_on_merge: true` なので、マージした PR のブランチは消える。閉じた PR のブランチは残る
  - GitHub の標準のトークンで作った PR では、ほかのワークフローが動かない。今の定期実行(frontend-vuln-fix など)は `BOT_GITHUB_TOKEN` で PR を作っている
- 設計への影響:
  - 週1回の実行は `BOT_GITHUB_TOKEN` で push し、PR を作る
  - 開発環境の `FROM` の版だけを変える PR にも所有者の承認が要るよう、`dependency-gate` が見る変更に、開発環境の Node.js と Terraform の `FROM` の版(タグ)の変更を足す

### PR の検査で4つの道具の署名を確かめる場所

- きっかけ: 更新の PR の検査で、上げる先の版の署名が確かめられるかを確かめるため
- 調べたもの: 4つの道具を入れるワークフローの起動の条件と、`install-verified-*.sh` の中身
- 分かったこと:
  - Terraform の CI の版を入れる `terraform-apply.yaml` は、`workflow_dispatch` でしか動かない
  - `codex-review.yml` は、リポジトリの変数 `CODEX_REVIEW_ENABLED` が `true` のときだけ動く
  - `container-scan.yaml` は、ジョブの中の paths の絞り込みに当たったときだけ Trivy を入れる
  - `install-verified-*.sh` は、署名を確かめて展開し、置き場を `GITHUB_PATH` に足すだけで、道具を動かさない。Codex CLI のスクリプトは、`gh attestation verify` のために `GH_TOKEN` を使う
- 設計への影響: 公開からの時間の検査が見つけた、PR で変わった CI の版を、`dependency-cooldown` のジョブの中で、道具ごとの `install-verified-*.sh` に渡して確かめる。必須の検査の一覧と ruleset は変えずに済む

### 公開からの時間の検査を置くジョブ

- きっかけ: 必須の検査の一覧(`.github/audit/required-checks.json`)と ruleset を変えずに、新しい検査を必須にするため
- 調べたもの: `dependency-review.yaml`、`guardrails.yaml`、`check-release-age.sh`
- 分かったこと:
  - `dependency-review.yaml` は paths の絞り込みが無く、main に向けたすべての PR で動く。ジョブ `cooldown`(検査の名前 `dependency-cooldown`)は、同じリポジトリのブランチの PR で動き、PR の head を深さ1で checkout する
  - `guardrails.yaml` のジョブ `escape-hatch` は、すべての PR で動き、actionlint と shellcheck と `check-action-pinning.sh` を流している
  - `check-release-age.sh` は、イメージの中の作成日時(image config の `created`)を、公開した側が自由に付けられるので使わないと決めている
- 設計への影響: 公開からの時間の検査は `dependency-cooldown` に、版の書き場所の検査は `escape-hatch` に、ステップとして足す

### 週1回の実行の失敗の知らせ

- きっかけ: 失敗の知らせを、ほかの監査の知らせと同じ形にするため
- 調べたもの: `.github/scripts/audit-issue.sh`、`audit-weekly.yaml`、`doc/開発フロー/監査手順.md`
- 分かったこと:
  - `audit-issue.sh <種類> <結果> [報告のファイル]` は、種類ごとに「逸脱あり」と「判定不能」の Issue を1つずつ持つ。結果が `none` なら開いている Issue を閉じ、`undecidable` なら「判定不能」の Issue を作るか追記する。本文には失敗した実行へのリンクが入る
  - 種類は `weekly`(週次監査)と `canary`(カナリア照合)の2つである
- 設計への影響: 種類 `ci-tool-update`(CI の道具の版の更新)を足し、失敗を `undecidable` で、成功を `none` で渡す

### 棚卸しの表への Codex CLI の追加

- きっかけ: 棚卸しの表に Codex CLI が無いため
- 調べたもの: `.github/audit/inventory-targets.json`、`.github/scripts/collect-inventory.sh`
- 分かったこと:
  - 最新の版の取り方には `github-release` `pypi` `dockerhub-tags` `endoflife` がある。`github-release` は `releases/latest` の `tag_name` をそのまま出すので、Codex CLI では `rust-v0.166.0` と出る
  - Node.js と Terraform は、開発環境と CI の両方の書き場所を宣言している
- 設計への影響: 最新の版の取り方に `npm`(`<registry>/<部品>/latest` の `version`)を足し、Codex CLI を対象に足す

## 構成の案の比べ

| 案 | 中身 | よい点 | 弱い点 | 結論 |
|---|---|---|---|---|
| Renovate を自分のワークフローで動かす | `customManagers` の正規表現で版を探し、`minimumReleaseAge: "3 days"` で待つ | 版の書き換えと PR の作り直しを作らずに済む | Node.js の取り先(`node-version`)が日付だけの `index.json` を使い、72時間より早く通ることがある。Docker Hub の digest にもタグの公開日時を当てる。古いほうを新しいほうにそろえる PR と、監査の知らせを作れない。公開からの時間の検査と版の書き場所の検査は、結局作る。Renovate 自身の版と署名を確かめる仕組みが新たに要る | 採らない |
| 週1回の実行をこのリポジトリのスクリプトで作る | frontend-vuln-fix と同じ形で、版を選び、書き換え、PR を作る | 既存の定期実行と同じ形で、取り先を spec `security-fix-cooldown-exception` とそろえられる | 版の書き換えと PR の作り直しを作る | 採る |
| 公開からの時間の検査を新しいワークフローにする | 新しい必須の検査を足す | 責任が分かれる | 必須の検査の一覧と ruleset の変更が要る | 採らない |
| 公開からの時間の検査を `dependency-cooldown` のステップにする | 既存の必須の検査に足す | 一覧と ruleset を変えずに済む。72時間の待ちの検査が1か所にまとまる | ジョブが少し長くなる | 採る |

## 設計の決めごと

### 決めごと: 版の書き場所を1つのデータのファイルにまとめる

- きっかけ: 週1回の実行、公開からの時間の検査、版の書き場所の検査、ci-tool-fast-update のスキルが、同じ書き場所の一覧を使う
- 比べた案:
  1. それぞれのスクリプトに書き場所を書く
  2. `.github/ci-tool-versions.json` に1つにまとめる
- 選んだ案: 2。ファイルは、道具ごとの CI の書き場所(ファイルと、版を書いた行の名前)と開発環境の書き場所と、対象外の一覧を持つ。行番号は持たず、探すライブラリが行を見つける
- 理由: 一覧が複数あると、`trusted-signers.json` の `locations` のように1つだけ書き漏れる
- 引き換え: `trusted-signers.json` から `locations` を消し、ci-tool-fast-update のスキルの Step 4 を書き換える
- 実装のときに確かめること: 版の書き場所の検査が、棚卸しの対象の宣言(`inventory-targets.json`)とも食い違わないこと

### 決めごと: 探す処理と書き換える処理を1つのライブラリにする(一般化)

- きっかけ: 週1回の実行は版を読んで書き換え、2つの検査は版を読む。読み方がずれると、検査が通るのに週1回の実行が書き換え漏れを起こす
- 選んだ案: `lib-ci-tool-versions.sh` が、ワークフローとアクションの版の行を探す関数、書き場所の一覧を読む関数、版を書き換える関数を持つ。週1回の実行と2つの検査は、このライブラリだけを使って版を読む
- 理由: 呼び出し方を1つにしておけば、版の書き方の形が増えたときも、ライブラリだけを直せばよい

### 決めごと: 下げない、そろえるときは新しいほうに合わせる

- きっかけ: 要件の段階の審査で、開発環境の版が手でその週の上げる先の版より上に上げられた場合が残った(指摘 R1-2-2)
- 選んだ案: Node.js と Terraform は、その週の上げる先の版と、今の CI の版と、今の開発環境の版のうち、最も新しい版を書き換え先にする。ただし、開発環境の版が CI の版とメジャー版が違うときは、更新の PR を作らず、失敗として知らせる
- 理由: どの組み合わせでも、CI の版も開発環境の版も下がらず、2つが同じ版になる。メジャー版の違う版にそろえると、メジャー版の更新の PR を自動で届けることになるため、そろえない

### 決めごと: 公開し直されたイメージの公開日時(簡素化)

- きっかけ: Docker Hub に、digest ごとの公開日時が無い
- 選んだ案: `FROM` の digest がタグの今の digest と同じときだけ、`tag_last_pushed` を公開日時とする。違うときは、公開日時を取れないものとして検査を失敗にする
- 理由: 古い digest の公開日時を推し量る仕組みを作らずに済む。検査は失敗の側に倒れる
- 引き換え: PR を出したあとに配布元がタグを公開し直すと、その PR の検査は、digest を今のものに直すまで失敗する

## 危うい点と対策

- Node.js のイメージの公開し直しが続くと、上げる先の版がなかなか決まらない。対策: 1つ前の版で条件を満たせば、その版を上げる先にする(条件を満たす版のうち最も新しい版を選ぶので、自然にそうなる)
- 最初の Terraform の更新の PR は、本番に適用する版を 1.9.0 から 1.17 の系列まで一度に上げる。対策: PR の本文に本番の適用の版が変わることを書き、所有者が承認してから入る。移行の節に、最初の PR の扱いを書く
- Codex CLI の npm の文書は約18MBある。対策: 週1回の実行と、Codex CLI の版を変えた PR の検査でだけ取る。時間の上限はワークフローで決める
- 配布元の API が一時的に失敗する。対策: その道具だけを失敗にし、ほかの道具を続ける。次の週の実行か、手での起動でやり直す

## 参考

- [Dependabot options reference](https://docs.github.com/en/code-security/dependabot/working-with-dependabot/dependabot-options-reference) — `ignore` の `update-types`
- [dependabot-core docker update_checker.rb](https://github.com/dependabot/dependabot-core/blob/main/docker/lib/dependabot/docker/update_checker.rb) — 版を除いても digest だけの更新が続く作り
- [dependabot-core PR #15103](https://github.com/dependabot/dependabot-core/pull/15103) — digest だけの更新を止める実験の旗
- [Renovate configuration options](https://docs.renovatebot.com/configuration-options/) — `customManagers` と `minimumReleaseAge`
- [Renovate issue #38659](https://github.com/renovatebot/renovate/issues/38659) — Docker Hub の digest にタグの公開日時が当たる
- [HashiCorp Releases API](https://api.releases.hashicorp.com/v1/releases/terraform?limit=20) — 版の一覧と `timestamp_created`
- [Node.js dist index](https://nodejs.org/dist/index.json) — 版の一覧
