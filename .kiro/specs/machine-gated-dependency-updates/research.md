# Research & Design Decisions

## Summary

- **Feature**: `machine-gated-dependency-updates`
- **Discovery Scope**: Extension(既存のCI基盤への追加)
- **Key Findings**:
  - dependency graph の compare API は、推移的依存だけでなく **Gradle プラグインの成果物も
    maven エコシステムとして返す**。プラグイン更新もクールダウン検査の対象にできる
  - プラグインの成果物は Maven Central と Gradle Plugin Portal に分かれており、
    片方だけを見ると取得できないものがある。フォールバックが必須
  - フォークPRでは head 側のスナップショットが送信されないため、compare API では
    追加パッケージを特定できない。検査の対象外にするしかない

## Research Log

### compare API の応答形状と対象範囲

- **Context**: クールダウン検査が「そのPRで新しく追加されたパッケージ」を推移的依存を含めて
  特定できるかを確かめる必要があった
- **Sources Consulted**: `GET /repos/{owner}/{repo}/dependency-graph/compare/{basehead}` を
  本リポジトリの実データに対して実行
- **Findings**:
  - PR #183 のマージ前後で 640 件の差分が返る。1件の形は次のとおり

    ```json
    {
      "change_type": "added",
      "ecosystem": "maven",
      "name": "org.springframework:spring-expression",
      "version": "6.2.7",
      "package_url": "pkg:maven/org.springframework/spring-expression@6.2.7",
      "manifest": "backend/settings.gradle",
      "scope": "runtime",
      "vulnerabilities": [ ... ]
    }
    ```

  - `manifest` は `backend/settings.gradle`(maven)と `.github/workflows/*.yaml`
    (github-actions)の2種類のみ。エコシステムで絞れば backend だけを対象にできる
  - **Gradle プラグインの成果物が含まれる**。実際に次が返った

    | 成果物 | 対応するプラグイン |
    |---|---|
    | `org.springframework.boot:spring-boot-gradle-plugin` | Spring Boot |
    | `io.spring.gradle:dependency-management-plugin` | dependency-management |
    | `com.diffplug.spotless:spotless-plugin-gradle` | Spotless |
    | `com.github.spotbugs.snom:spotbugs-gradle-plugin` | SpotBugs |
    | `info.solidsoft.gradle.pitest:gradle-pitest-plugin` | PIT |
    | `gradle.plugin.org.flywaydb:gradle-plugin-publishing` | Flyway |

- **Implications**: 検査の入力は compare API のみでよい。`libs.versions.toml` を解析する必要はなく、
  backend で最も頻繁な更新であるプラグインのバージョン変更も自動的に対象に入る。
  ライブラリとプラグインを別経路で扱う設計は不要になった

### 公開時刻の取得元

- **Context**: 要件1の受入基準6は「実際の公開時刻に基づく判定」を求めている。
  取得元によって結果が変わるため確定が必要だった
- **Sources Consulted**: `repo1.maven.org`、`plugins.gradle.org/m2`、`search.maven.org` の実測
- **Findings**:
  - pom への HEAD リクエストは `Last-Modified` を返す。例:
    `com.diffplug.spotless:spotless-plugin-gradle:7.2.1` → `Mon, 21 Jul 2025 19:16:02 GMT`
  - **配布元が分かれている。** 片方にしか無い成果物が実在する

    | 成果物 | repo1.maven.org | plugins.gradle.org/m2 |
    |---|---|---|
    | `com.diffplug.spotless:spotless-plugin-gradle` | 200 | — |
    | `info.solidsoft.gradle.pitest:gradle-pitest-plugin` | 200 | — |
    | `org.springframework.boot:spring-boot-gradle-plugin` | 200 | — |
    | `com.github.spotbugs.snom:spotbugs-gradle-plugin` | **404** | 200 |
    | `gradle.plugin.org.flywaydb:gradle-plugin-publishing` | **404** | 200 |

  - `search.maven.org` の Solr 検索APIは索引が正典より遅れる。`org.slf4j:slf4j-api 2.0.18`
    (2026-05-12公開)が `repo1.maven.org` の `maven-metadata.xml` とディレクトリ一覧には
    存在するのに、検索APIの結果には現れず 2.0.x の最新が 2.0.17 として返った
- **Implications**: Maven Central を先に引き、404 のときに Gradle Plugin Portal へ
  フォールバックする。どちらでも取得できない場合は判定不能として赤にする(要件1の受入基準4)。
  検索APIは使わない

### Gradle 配布物のチェックサム

- **Context**: 要件2の受入基準3が「公式に公表された値との一致」を求めている
- **Sources Consulted**: `services.gradle.org` の実測
- **Findings**:
  - `https://services.gradle.org/distributions/gradle-<version>-bin.zip.sha256` で取得できるが、
    **301 リダイレクトを返す**。追従しないとHTML断片を掴む
  - 追従した場合、`gradle-8.14.5-bin.zip.sha256` は
    `6f74b601422d6d6fc4e1f9a1ab6522f642c2fdcbc15ae33ebd30ba3d7198e854` を返す
- **Implications**: 取得時にリダイレクト追従を必須にする。追従しないと常に不一致となり、
  検査が恒久的に赤になる

### Dependabot によるチェックサムの維持

- **Context**: `distributionSha256Sum` を追加したあと、バージョン更新のたびに正しい値へ
  差し替わることが前提になる
- **Sources Consulted**: dependabot-core の実ソース
- **Findings**:
  - `file_updater/wrapper/properties_reconciler.rb` に
    `MANAGED_KEYS = %w(distributionUrl distributionSha256Sum).freeze`
  - `file_parser/distributions_finder.rb` は `if checksum` の条件でチェックサム要件を生成する。
    **元ファイルにキーが無ければ管理対象にならない**
  - `update_checker/requirements_updater.rb` が新バージョンの公式 `.sha256` を解決し、
    `file_updater/wrapper/command_builder.rb` が wrapper タスクへ渡す
- **Implications**: キーの追加は必須の前提条件であり、検査の追加と同じ変更で行う。
  追加しない限り Dependabot はチェックサムを更新せず、バージョンだけが進んで検査が赤になる

### スキップされたジョブと必須チェックの関係

- **Context**: 対象外の条件をどう表現するかが、検査の実効性を左右する
- **Sources Consulted**: GitHub Docs(Troubleshooting required status checks)
- **Findings**:
  - `if` 条件でスキップされたジョブは **Success として報告され、必須チェックを満たす**
  - path/branch フィルタでワークフローごとスキップされた場合は Pending のまま残りマージを止める
- **Implications**: 対象外はジョブ単位の `if` で表現する。ワークフロー単位の paths フィルタは
  使わない。また、依存するジョブが失敗したときに後続がスキップ(= Success)になる経路を
  塞ぐため、直列に並ぶジョブはすべて必須チェックに登録する

## Architecture Pattern Evaluation

| Option | Description | Strengths | Risks / Limitations | 採否 |
|---|---|---|---|---|
| compare API を入力にする | GitHubが解決済みの追加パッケージ一覧を使う | 推移的依存とプラグインを取りこぼさない。パーサ不要 | head 側スナップショットに依存する | **採用** |
| `libs.versions.toml` を解析する | TOMLを読んで差分を取る | 外部APIに依存しない | 推移的依存を取れない。BOM管理の版が見えない | 不採用 |
| Gradle の dependency verification | Gradleの標準機能で検証する | 標準機構 | 初回信頼モデルにしかならない。クールダウンは扱えない | 不採用(将来の強化余地) |

## Design Decisions

### 1. クールダウン検査の入力を compare API に一本化する

**Generalization**: 「ライブラリの追加」と「プラグインの更新」は別の問題に見えたが、
compare API はどちらも maven の追加パッケージとして返す。1つの入力で両方を扱える。

**却下した案**: エコシステムごとに解析器を持つ設計。実装量が増えるうえ、
推移的依存を自前で解決する必要が生じる。

### 2. 検査の配置を2つのワークフローに分ける

クールダウン検査は head 側のスナップショット送信が完了していることを要求するため、
`dependency-review.yaml` の `submit` の後段に置く。

wrapper 検査は依存グラフを必要としない。既存の `check-action-pinning`(アクション参照の
SHA固定検査)と目的が同じ「ビルドが取得する外部成果物の同一性の検証」であるため、
`guardrails.yaml` に置く。

### 3. 対象外の表現をジョブ単位の `if` に統一する

Dependabot のPRとフォークPRは、いずれもジョブ単位の `if` でスキップする。
スキップが Success 扱いになる仕様により、必須チェックを満たしたまま対象外にできる。

### 4. 判定不能を赤にする(fail closed)

外部ホストへの問い合わせが失敗した場合、判定できないまま通すと「検査があるのに
守られていない」状態が静かに続く。ただし外部要因の赤はエージェントが自力で解消できないため、
報告に原因の区別を含める(要件5)。

### 5. Simplification: 除外リストを設けない

pnpm の `minimumReleaseAgeExclude` に相当する仕組みは作らない。除外リストはゲートの
抜け穴になり、`escape-hatch` 検知の思想と競合する。緊急時に急ぐ必要がある経路は
Dependabot の security update であり、そちらは検査の対象外にすることで解決している。

## Risks

| リスク | 影響 | 緩和 |
|---|---|---|
| 配布元の応答形式が変わる | 検査が恒久的に赤になる | fail closed のため気づける。3回連続失敗で人間へ |
| Spring Boot 更新で多数が一斉に該当する | 報告が読めなくなる | 待機が明ける最も遅い時刻を明示する(要件1の受入基準7) |
| 検査1と検査2の信頼の根が同じ | 配布元が侵害されると両方偽装される | 残余リスクとして運用文書に記録する(要件6の受入基準4) |
| フォークPRのbackend差分が未検査 | 外部からの寄与が検査を通らない | 受容済み。#183 で同じ判断をしている |
