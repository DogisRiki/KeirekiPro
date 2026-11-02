# 調べの記録

## まとめ

- 機能: `security-fix-cooldown-exception`
- 調べの種類: 既存の仕組みを広げる(Extension)。外部の仕様が多いので、外部の仕様は詳しく調べた
- 設計を決めた発見:
  - backend の脆弱性の警告には、本番で動くか開発のときだけ使うかが載っていない。このリポジトリの maven の警告49件は、すべて `dependency.scope` が `null` だった。Gradle の依存グラフのプラグインは、設定をしないと scope を付けない。そこで、依存グラフを作るときに、本番の組み立てに入る部品だけを `runtime` にする設定を足す
  - 72時間の待ちの判定は、今は backend だけを PR の検査で見ている。依存グラフの比較の API は frontend の部品(`frontend/pnpm-lock.yaml`)も返すので、同じ検査を frontend に広げられる
  - 署名した者を比べる材料は、npm では SLSA の来歴の証明書、Maven では PGP の主鍵の指紋である。npm の registry の署名は、どの部品にも同じ鍵で付くので、比べる材料にならない

## 調べたこと

### 依存グラフの比較の API が返す部品

- きっかけ: frontend の部品も PR の検査で見られるかを確かめるため
- 調べたもの: `repos/{owner}/{repo}/dependency-graph/compare/{base}...{head}`(PR #637 と PR #670 の base と head で実際に呼んだ)
- 分かったこと:
  - PR #637(frontend の Dependabot の PR)では、`ecosystem: npm`、`manifest: frontend/pnpm-lock.yaml` の部品が `added` と `removed` で返った。推移的な部品も返る
  - npm の部品には `scope` が付く(`runtime` か `development`)
  - PR #670(backend)では、maven の部品534件のうち532件が `runtime`、2件(`org.gradle:gradle-core`)が `development` だった。`com.diffplug.spotless:spotless-lib` のような組み立ての道具も `runtime` になる。比較の API は、scope の無い部品を `runtime` として返しているとみられる
- 設計への影響: 検査の入力は今と同じ比較の API にし、npm と maven の両方を見る

### Dependabot の警告の API

- きっかけ: 72時間待たずに入れてよい版を、警告から決めるため
- 調べたもの:
  - https://docs.github.com/en/rest/dependabot/alerts
  - https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax
  - https://github.blog/changelog/2026-09-03-github-actions-early-september-2026-updates/
  - このリポジトリの警告の一覧(`gh api repos/{owner}/{repo}/dependabot/alerts`)
- 分かったこと:
  - 使う欄は、`state`、`dependency.package.ecosystem`、`dependency.package.name`、`dependency.scope`(`runtime` `development` `null`)、`security_advisory.severity`、`security_advisory.ghsa_id`、`security_vulnerability.first_patched_version.identifier`、`html_url`、`number` である
  - 絞り込みの引数に `state` `severity` `ecosystem` `package` `scope` `per_page`(最大100)がある。`scope=runtime` で絞ると `null` の警告が落ちる
  - ワークフローの標準のトークンで読める。権限は `vulnerability-alerts: read` である(2026年9月に足された。`read` と `none` だけ)
  - Dependabot が起こした `pull_request` の実行でも、`permissions` で権限を足せる。ただし、Dependabot の PR の実行で `vulnerability-alerts: read` が通るかは、実際には確かめていない
  - このリポジトリの maven の警告49件は、すべて `dependency.scope` が `null`、`manifest_path` が `backend/settings.gradle` だった。npm の警告には `development` か `runtime` が付いていた
- 設計への影響: 警告は、検査のたびに API で読む。backend の警告に scope を付けるため、依存グラフの作り方を変える(次の節)

### Gradle の依存グラフに scope を付ける

- きっかけ: backend の警告に scope が載らないため
- 調べたもの:
  - https://github.com/gradle/github-dependency-graph-gradle-plugin(README の「Controlling the scope of dependencies in the dependency graph」)
  - https://github.com/gradle/actions/blob/main/docs/dependency-submission.md
- 分かったこと:
  - プラグインは、既定では scope を付けない(「By default, no scope is assigned」)
  - 環境変数 `DEPENDENCY_GRAPH_RUNTIME_INCLUDE_CONFIGURATIONS` などのどれか1つを設定すると scope が付く。設定に一致する読み込み(configuration)で解決された部品は `runtime`、それ以外は `development` になる。1つでも `runtime` の読み込みで解決されれば `runtime` になる
  - 値は正規表現で、名前全体と照らす
- 設計への影響: 依存グラフを作る2つのワークフロー(PR の `dependency-review.yaml` と main の `dependency-graph.yaml`)に、`DEPENDENCY_GRAPH_RUNTIME_INCLUDE_CONFIGURATIONS: productionRuntimeClasspath` を足す。`productionRuntimeClasspath` は、Spring Boot の Gradle プラグインが作る読み込みで、本番の jar に入る部品を持つ
- 確かめ残し: 送った依存グラフの scope が、Dependabot の警告の `dependency.scope` に載るかは、文書で確かめられなかった。実装の PR で、main に送ったあとの警告の scope を確かめる

### Dependabot のクールダウンとセキュリティの更新

- 調べたもの:
  - https://docs.github.com/en/code-security/reference/supply-chain-security/dependabot-options-reference
  - https://github.blog/changelog/2026-07-14-dependabot-version-updates-introduce-default-package-cooldown/
  - https://docs.github.com/en/code-security/dependabot/dependabot-security-updates/about-dependabot-security-updates
- 分かったこと:
  - Dependabot の既定の3日のクールダウンは、版の更新だけに効き、セキュリティの更新には効かない
  - セキュリティの更新は、修正を含む最も低い版に上げる。ただし、npm の推移的な部品では、親の部品を上げることがある
- 設計への影響: 今の検査は Dependabot の PR を対象から外しているので、Dependabot のセキュリティの更新は72時間の待ちを受けていない。この spec で Dependabot の PR も対象にする。親の部品を上げたセキュリティの更新では、親の新しい版が最初の修正版ではないので、72時間待つ

### pnpm の除外の欄 `minimumReleaseAgeExclude`

- きっかけ: 72時間待たずに入れた frontend の版を、マージのあとの CI と開発者の環境と本番の組み立てが入れられるようにするため
- 調べたもの:
  - https://pnpm.io/settings/dependency-resolution
  - https://github.com/pnpm/pnpm/releases/tag/v10.19.0
  - pnpm 11.10.0 のソース(`config/version-policy/src/index.ts`、`createNpmResolutionVerifier.ts`)と CHANGELOG
- 分かったこと:
  - 要素の書き方は、`name`(すべての版)、`'@scope/*'`(名前のパターン)、`nx@21.6.5`(1つの版)、`webpack@4.47.0 || 5.102.1`(いくつかの版)である。範囲の指定は拒否される
  - 推移的な部品にも効く。`--frozen-lockfile` の install でも効き、名前と版の完全一致で判定する
  - pnpm 11.9.0 より前は、同じ部品を別々の要素に書くと最初の要素しか効かなかった。11.10.0 では直っている
  - `minimumReleaseAge` を明示しないと、pnpm が若い版を除外の欄に自分で書き足す。このリポジトリは `minimumReleaseAge: 4320` を明示している
- 設計への影響: frontend の版を72時間待たずに入れる変更は、除外の欄に `name@version` の要素を足す。検査は、足してあるかを確かめる。PR の検査は版の公開日時を registry から読むので、除外の欄の中身で PR の検査の判定は変わらない

### 悪意のある部品の一覧

- 調べたもの:
  - https://google.github.io/osv.dev/post-v1-querybatch/
  - https://google.github.io/osv.dev/post-v1-query/
  - https://google.github.io/osv.dev/faq/
  - https://github.com/ossf/malicious-packages
  - https://docs.github.com/en/code-security/security-advisories/working-with-global-security-advisories-from-the-github-advisory-database/about-the-github-advisory-database
- 分かったこと:
  - OSV の `POST https://api.osv.dev/v1/querybatch` は、`{"queries":[{"package":{"name","ecosystem"},"version"}]}` を受け取り、入力と同じ順に `{"results":[{"vulns":[{"id","modified"}]}]}` を返す。一致が無い要素は `{}` になる
  - 1回に送れるのは1000件までである。一部の要素に `next_page_token` が付くことがあり、その要素だけ送り直す
  - 呼び出しの回数の制限は無い
  - ecosystem の名前は `npm` と `Maven` である。Maven の名前は `groupId:artifactId` である
  - OpenSSF の悪意のある部品の一覧の項目は、`MAL-` で始まる ID を持つ。古い GitHub の悪意のある部品の勧告は `GHSA-` の ID で出ることがあり、そのときは `database_specific.cwe_ids` に `CWE-506` がある
  - 個々の項目の中身は `GET https://api.osv.dev/v1/vulns/{id}` で読める
- 設計への影響: 悪意のある部品の確認には OSV を使う。OSV は、GitHub の勧告と OpenSSF の一覧の両方を取り込んでいる。`MAL-` の ID か、中身の `CWE-506` で悪意のある部品と判定する

### npm の署名と、署名した者

- 調べたもの:
  - https://docs.npmjs.com/about-registry-signatures
  - https://docs.npmjs.com/generating-provenance-statements
  - https://github.com/sigstore/fulcio/blob/main/docs/oid-info.md
  - https://cli.github.com/manual/gh_attestation_verify
- 分かったこと:
  - `dist.signatures` は registry の共通の鍵(`SHA256:DhQ8wR5APBvFHLF/+Tc+AYvPOdTpcIDqOhxsBHRwC7U`)で付く。公開した者を見分けられない
  - `https://registry.npmjs.org/-/npm/v1/attestations/<name>@<version>` の `attestations[]` のうち、predicateType が `https://slsa.dev/provenance/v1` のものが SLSA の来歴である。Sigstore の bundle で、Fulcio の証明書が付く。もう1つの publish attestation は registry の共通の鍵で付くので、見分けに使えない
  - 証明書から、OIDC の発行元(拡張 1.3.6.1.4.1.57264.1.8)、元のリポジトリの ID(1.15)、組み立ての設定の URI(1.18)が読める。組み立ての設定の URI には `@refs/...` が付き、タグで公開すると版ごとに変わる
  - `gh attestation verify <tgz> --bundle <bundle> --digest-alg sha512 --repo <owner>/<repo>` で、bundle の署名と中身の一致と元のリポジトリを確かめられる。ubuntu-latest には gh が入っている
- 設計への影響: npm では、SLSA の来歴の証明書の3つの欄(発行元、元のリポジトリの ID、`@` より前の組み立ての設定の URI)が前の版と同じことを、署名した者が同じことと見なす。前の版に SLSA の来歴が無ければ、前の版に署名が無いものとして扱う

### Maven Central と Gradle Plugin Portal の署名

- 調べたもの:
  - https://central.sonatype.org/publish/requirements/gpg/
  - https://central.sonatype.org/news/20250128_sigstore_signature_validation_via_portal/
  - https://github.com/gradle/gradle/issues/10182
- 分かったこと:
  - Maven Central では PGP の署名が必須で、`.pom.asc` がある
  - 公開鍵は、指紋で `https://keyserver.ubuntu.com/pks/lookup?op=get&options=mr&search=0x<指紋>` から取れる
  - Gradle Plugin Portal では、署名は任意である。plugin の marker の POM には `.asc` が無い
- 設計への影響: Maven では、POM の `.asc` を `gpg --verify` で確かめ、検証に成功した署名の主鍵の指紋(`VALIDSIG` の最後の欄)を、前の版と比べる。Plugin Portal の部品は、本番の組み立てに入らないので、72時間待たずに入れる版にならない

### CI の道具の署名

- 調べたもの:
  - https://github.com/actions/setup-node/blob/main/docs/advanced-usage.md
  - https://github.com/actions/node-versions
  - https://github.com/nodejs/node#verifying-binaries
  - https://github.com/nodejs/release-keys
  - https://trivy.dev/docs/latest/getting-started/signature-verification
  - https://docs.npmjs.com/verifying-registry-signatures
  - https://www.hashicorp.com/en/trust/security
  - https://github.com/hashicorp/setup-terraform
- 分かったこと:
  - Node.js: CI の `actions/setup-node` は、`actions/node-versions` の一覧にある `download_url` から、nodejs.org の tarball を詰め直したものを入れる。setup-node は署名を確かめない。nodejs.org の `SHASUMS256.txt.asc` は、Node.js のリリースの担当者の鍵で署名されている。鍵の指紋は `nodejs/release-keys` の README にある
  - Trivy: `aquasecurity/setup-trivy` は GitHub のリリースから tarball を入れ、同じリリースのチェックサムの一覧とだけ照らす。リリースの各ファイルに `<ファイル>.sigstore.json` があり、`cosign verify-blob --bundle` で確かめられる。証明書の身元は `https://github.com/aquasecurity/trivy/.github/workflows/reusable-release.yaml@refs/tags/v<版>`、発行元は `https://token.actions.githubusercontent.com` である
  - Codex CLI: `@openai/codex@<版>` と、本体を持つ `@openai/codex@<版>-linux-x64` の2つの版が入る。どちらにも SLSA の来歴があり、元のリポジトリは `openai/codex`、組み立てのワークフローは `.github/workflows/rust-release.yml` である
  - Terraform: `hashicorp/setup-terraform` は releases.hashicorp.com から zip を入れ、署名を確かめない。`terraform_<版>_SHA256SUMS.sig` は、HashiCorp の鍵(指紋 `C874011F0AB405110D02105534365D9472D7468F`)で署名されている
  - 公開日時は、Node.js は `actions/node-versions` のリリースの `published_at`、Trivy は GitHub のリリースの `published_at`、Codex CLI は npm の `time`、Terraform は `https://api.releases.hashicorp.com/v1/releases/terraform/<版>` の `timestamp_created` で読める
- 設計への影響: CI の道具ごとに、確かめ方と信頼する署名した者をデータのファイルに持たせ、確かめのスクリプトが読む。Node.js は、nodejs.org の tarball を署名で確かめたうえで、CI が入れる詰め直しの tarball の `bin/node` と同じ中身かを比べる

## 比べた案

| 案 | 中身 | よいところ | 困るところ |
|---|---|---|---|
| 今の検査 `dependency-cooldown` を広げる | 1つの検査が、72時間の待ち、例外の条件、悪意のある部品、署名した者、記録を受け持つ | 判定の場所が1つで、止めた理由をすべて1か所に出せる | 検査のスクリプトが大きくなる |
| 例外を別のワークフローにする | 例外の判定だけを別のワークフローで行い、今の検査はそのまま | 今の検査を変えない | 今の検査が先に赤になり、2つの結果の組み合わせで判定することになる。frontend は今の検査の対象でもない |
| pnpm の install の失敗だけで frontend を止める | PR の検査を足さず、除外の欄があるかどうかで決める | 足すものが少ない | 止めた理由と入れる時刻を検査の結果に出せない。除外の欄を書けば何でも通る |

今の検査を広げる案を選んだ。止めた理由を1か所に出すことと、frontend と backend で同じ判定にすることを優先した。スクリプトは役割ごとにファイルを分けて、大きさを抑える。

## 決めたこと

### 決めたこと: 所有者の承認を、検査 `dependency-cooldown` の中で求める

- きっかけ: 72時間待たずに入れる変更を、所有者が承認するまでマージさせないため(要件1の2)
- 比べた案:
  1. `dependency-gate` に判定させる。`dependency-gate` は `pull_request_review` でも動く
  2. 検査 `dependency-cooldown` が、例外を使うときに所有者の承認を見る。承認のあとは、`rerun-approval-gated-checks.yaml` が失敗した実行を再実行する
- 選んだ案: 2
- 理由: 案1では、例外を使うかどうかを `dependency-gate` も計算することになる。記録のコメントで受け渡すと、`dependency-gate` が記録の書き込みより先に動いたときに承認なしで緑になる。案2は、承認で緑になる今の型(`escape-hatch` など)と同じで、再実行の仕組みもある
- 確かめ残し: 再実行で検査を作り直すと、そのときに公開から72時間経った版は例外にならない。そこで、記録のコメントがあれば、そのときの判定によらず承認を求める

### 決めたこと: 記録は、PR のコメントと、PR のマージの日時を合わせたものにする

- 比べた案:
  1. リポジトリの中のファイルに記録を書く
  2. PR に、目印つきのコメントで記録を書き、マージの日時は GitHub の PR の `merged_at` から読む
  3. Issue に記録を書き足す
- 選んだ案: 2
- 理由: 案1は、検査がリポジトリに書き込む権限を要る。案3は、Issue を新しく使うことになる。案2は、既存の `lib-notice-comment.sh` の目印つきのコメントの型を使える。所有者は、承認するときに同じ PR でコメントを読める

### 決めたこと: 判定の時点(要件の審査の記録 R1-1-5)

- 選んだ案: 検査が動いた時点で判定する。検査は、PR の push、再実行のたびに判定し直す
- 理由: 今の検査と同じである。72時間経つ時刻は検査の結果に出すので、変更を作った人は、その時刻のあとに再実行すればよい

### 決めたこと: 承認を待つあいだに72時間経った版の記録(要件の審査の記録 R3-1-2)

- 選んだ案: マージした head に対する記録があれば、週次監査の一覧に載せる。マージした head に対する記録が無ければ載せない
- 理由: 検査は、head ごとに、初めて判定したときに記録を書く。同じ head のまま承認を待って72時間経った版は、記録があるので一覧に載る。72時間経ったあとに新しい head を push したときは、新しい head では例外を使わないので、記録は無い。この版は72時間経ってから入ったので、悪意のある版を見落とさない
- 採らなかった案: 前の head の記録を新しい head に引き継ぐ案は、引き継ぐ版がまだ変更に含まれるかを照らす作りが要り、見落としを減らさないので採らなかった

### 決めたこと: 確認で止めた変更が72時間経ったあとの扱い(要件の審査の記録 R3-2-1)

- 選んだ案: 止めた変更には記録が無いので、72時間経ったあとは、今と同じ決まりで入る。記録が無いので、所有者の承認も新しくは求めない
- 理由: 範囲の「決めないこと」のとおり、すべての版が72時間経った変更には、悪意のある部品の確認と署名した者の確認を足さない。悪意のある部品として止めたときは、検査の結果に公表の記載が出るので、変更を作った人は変更を取り下げられる

### 決めたこと: CI の道具の手順は Claude のスキルにする

- 比べた案:
  1. CLAUDE.md に手順の全部を書く
  2. 新しいスキルに手順を書き、CLAUDE.md には1行だけ書く
- 選んだ案: 2
- 理由: CLAUDE.md の大きさの上限(21000 バイト)まで、残りは約1300バイトしかない。所有者の指示が無いときに変えない決まり(要件6の2)は、スキルが呼ばれないときにも効く必要があるので、その1行だけを CLAUDE.md に置く

## まとめ方の工夫

- 一般化: 今の `lib-notice-comment.sh` の目印つきのコメントの関数を、記録のコメントにも使う。所有者の承認の読み方は、`dependency-gate.yaml` の承認の読み方と同じ jq の式を使う
- 作るか使うか: 悪意のある部品の一覧は OSV を使い、自分で一覧を持たない。npm の来歴の検証は `gh attestation verify` を使い、Sigstore の検証を自分で書かない。Maven の署名の検証は gpg を使う
- 減らしたこと: 除外の欄の新しい要素を検査で止める案は採らなかった。PR の検査は registry の公開日時で判定するので、除外の欄の中身が判定を変えないためである

## おそれと手当て

- 送った依存グラフの scope が警告に載らなければ、backend の版は72時間待たずには入らない。72時間待つ側に倒れるので、悪意のある版は入らない。実装の PR で main に送ったあとに確かめ、載らなければ所有者に報告する
- Dependabot の PR の実行で警告を読めなければ、Dependabot の PR は72時間待つ。検査の結果に「警告を読めなかった」と出す
- Dependabot の PR も検査の対象にすると、72時間経っていない推移的な部品を含む Dependabot の PR が赤で止まる。72時間経ったあとは再実行が要る。滞留は、週次監査の `dependabot-stuck` の項目が見つける
- Dependabot の frontend の PR は、除外の欄の要素を足せない。検査の結果に、足す1行を出す。足す人を決めるのは、この spec の範囲の外(Issue #630)である
- 公開から間もない版の tarball が大きいと、来歴の検証に時間がかかる。検査のジョブ全体を30分で打ち切る

## 調べのついでに見つけたこと

- Terraform は、`terraform-apply.yaml` の `TF_VERSION: '1.9.0'` と、`docker/terraform/Dockerfile` の `hashicorp/terraform:1.17.0` の2つの版を使っている。この spec の範囲の外なので、報告だけにする

## 出典

- [GitHub REST API: Dependabot alerts](https://docs.github.com/en/rest/dependabot/alerts) — 警告の欄と絞り込みの引数
- [GitHub REST API: Dependency review](https://docs.github.com/en/rest/dependency-graph/dependency-review) — 依存グラフの比較の API
- [github-dependency-graph-gradle-plugin](https://github.com/gradle/github-dependency-graph-gradle-plugin) — Gradle の依存グラフの scope の設定
- [pnpm settings: dependency resolution](https://pnpm.io/settings/dependency-resolution) — `minimumReleaseAgeExclude`
- [OSV API](https://google.github.io/osv.dev/post-v1-querybatch/) — 悪意のある部品の一覧の照会
- [npm provenance](https://docs.npmjs.com/generating-provenance-statements) — npm の来歴
- [gh attestation verify](https://cli.github.com/manual/gh_attestation_verify) — 来歴の検証
- [Central GPG requirements](https://central.sonatype.org/publish/requirements/gpg/) — Maven の署名
- [Trivy signature verification](https://trivy.dev/docs/latest/getting-started/signature-verification) — Trivy の署名
- [Node.js verifying binaries](https://github.com/nodejs/node#verifying-binaries) — Node.js の署名
- [HashiCorp security](https://www.hashicorp.com/en/trust/security) — Terraform の署名
