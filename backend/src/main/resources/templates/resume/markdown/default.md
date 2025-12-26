[# th:inline="text"]
# [[${export.title}]]

**[[${export.asOfDateLabel}]]**

**氏名：[[${export.fullName}]]**

---

## 職歴

| 期間 | 会社名 |
|------|--------|
[# th:each="career : ${export.careers}"]| [[${career['periodLabel']}]] | [[${career['companyName']}]] |
[/]

---

## 職務内容

[# th:each="company : ${export.companySections}"]
### [[${company['companyLabel']}]]


[# th:each="project : ${company['projects']}"]
#### [[${project['projectLabel']}]]


**プロジェクト概要：**
[[${project['overview']}]]


**チーム構成：**
[[${project['teamComp']}]]


**役割：**
[[${project['role']}]]


[# th:if="${project['achievements'] != null and !project['achievements'].isEmpty()}"]
**主な成果：**
[# th:each="a : ${project['achievements']}"]
[[${a}]]
[/]
[/]


**作業工程：**

| 要件定義 | 基本設計 | 詳細設計 | 実装・単体テスト | 結合テスト | 総合テスト | 運用・保守 |
|:--------:|:--------:|:--------:|:----------------:|:----------:|:----------:|:----------:|
| [[${project['process'] != null and project['process'].requirements == true ? '○' : ''}]] | [[${project['process'] != null and project['process'].basicDesign == true ? '○' : ''}]] | [[${project['process'] != null and project['process'].detailedDesign == true ? '○' : ''}]] | [[${project['process'] != null and project['process'].implementation == true ? '○' : ''}]] | [[${project['process'] != null and project['process'].integrationTest == true ? '○' : ''}]] | [[${project['process'] != null and project['process'].systemTest == true ? '○' : ''}]] | [[${project['process'] != null and project['process'].maintenance == true ? '○' : ''}]] |

[# th:if="${project['tech'] != null}"]
**技術スタック：**

[# th:if="${project['tech']['frontend'] != null}"]
- フロントエンド
  [# th:if="${project['tech']['frontend']['languages'] != null and !#lists.isEmpty(project['tech']['frontend']['languages'])}"]
  - 開発言語：[[${#strings.listJoin(project['tech']['frontend']['languages'], ', ')}]]
  [/]
  [# th:if="${project['tech']['frontend']['frameworks'] != null and !#lists.isEmpty(project['tech']['frontend']['frameworks'])}"]
  - フレームワーク：[[${#strings.listJoin(project['tech']['frontend']['frameworks'], ', ')}]]
  [/]
  [# th:if="${project['tech']['frontend']['libraries'] != null and !#lists.isEmpty(project['tech']['frontend']['libraries'])}"]
  - ライブラリ：[[${#strings.listJoin(project['tech']['frontend']['libraries'], ', ')}]]
  [/]
  [# th:if="${project['tech']['frontend']['buildTools'] != null and !#lists.isEmpty(project['tech']['frontend']['buildTools'])}"]
  - ビルドツール：[[${#strings.listJoin(project['tech']['frontend']['buildTools'], ', ')}]]
  [/]
  [# th:if="${project['tech']['frontend']['packageManagers'] != null and !#lists.isEmpty(project['tech']['frontend']['packageManagers'])}"]
  - パッケージマネージャー：[[${#strings.listJoin(project['tech']['frontend']['packageManagers'], ', ')}]]
  [/]
  [# th:if="${project['tech']['frontend']['linters'] != null and !#lists.isEmpty(project['tech']['frontend']['linters'])}"]
  - リンター：[[${#strings.listJoin(project['tech']['frontend']['linters'], ', ')}]]
  [/]
  [# th:if="${project['tech']['frontend']['formatters'] != null and !#lists.isEmpty(project['tech']['frontend']['formatters'])}"]
  - フォーマッター：[[${#strings.listJoin(project['tech']['frontend']['formatters'], ', ')}]]
  [/]
  [# th:if="${project['tech']['frontend']['testingTools'] != null and !#lists.isEmpty(project['tech']['frontend']['testingTools'])}"]
  - テストツール：[[${#strings.listJoin(project['tech']['frontend']['testingTools'], ', ')}]]
  [/]
[/]

[# th:if="${project['tech']['backend'] != null}"]
- バックエンド
  [# th:if="${project['tech']['backend']['languages'] != null and !#lists.isEmpty(project['tech']['backend']['languages'])}"]
  - 開発言語：[[${#strings.listJoin(project['tech']['backend']['languages'], ', ')}]]
  [/]
  [# th:if="${project['tech']['backend']['frameworks'] != null and !#lists.isEmpty(project['tech']['backend']['frameworks'])}"]
  - フレームワーク：[[${#strings.listJoin(project['tech']['backend']['frameworks'], ', ')}]]
  [/]
  [# th:if="${project['tech']['backend']['libraries'] != null and !#lists.isEmpty(project['tech']['backend']['libraries'])}"]
  - ライブラリ：[[${#strings.listJoin(project['tech']['backend']['libraries'], ', ')}]]
  [/]
  [# th:if="${project['tech']['backend']['buildTools'] != null and !#lists.isEmpty(project['tech']['backend']['buildTools'])}"]
  - ビルドツール：[[${#strings.listJoin(project['tech']['backend']['buildTools'], ', ')}]]
  [/]
  [# th:if="${project['tech']['backend']['packageManagers'] != null and !#lists.isEmpty(project['tech']['backend']['packageManagers'])}"]
  - パッケージマネージャー：[[${#strings.listJoin(project['tech']['backend']['packageManagers'], ', ')}]]
  [/]
  [# th:if="${project['tech']['backend']['linters'] != null and !#lists.isEmpty(project['tech']['backend']['linters'])}"]
  - リンター：[[${#strings.listJoin(project['tech']['backend']['linters'], ', ')}]]
  [/]
  [# th:if="${project['tech']['backend']['formatters'] != null and !#lists.isEmpty(project['tech']['backend']['formatters'])}"]
  - フォーマッター：[[${#strings.listJoin(project['tech']['backend']['formatters'], ', ')}]]
  [/]
  [# th:if="${project['tech']['backend']['testingTools'] != null and !#lists.isEmpty(project['tech']['backend']['testingTools'])}"]
  - テストツール：[[${#strings.listJoin(project['tech']['backend']['testingTools'], ', ')}]]
  [/]
  [# th:if="${project['tech']['backend']['ormTools'] != null and !#lists.isEmpty(project['tech']['backend']['ormTools'])}"]
  - ORM：[[${#strings.listJoin(project['tech']['backend']['ormTools'], ', ')}]]
  [/]
  [# th:if="${project['tech']['backend']['auth'] != null and !#lists.isEmpty(project['tech']['backend']['auth'])}"]
  - 認証：[[${#strings.listJoin(project['tech']['backend']['auth'], ', ')}]]
  [/]
[/]

[# th:if="${project['tech']['infrastructure'] != null}"]
- インフラ
  [# th:if="${project['tech']['infrastructure']['clouds'] != null and !#lists.isEmpty(project['tech']['infrastructure']['clouds'])}"]
  - クラウド：[[${#strings.listJoin(project['tech']['infrastructure']['clouds'], ', ')}]]
  [/]
  [# th:if="${project['tech']['infrastructure']['operatingSystems'] != null and !#lists.isEmpty(project['tech']['infrastructure']['operatingSystems'])}"]
  - OS：[[${#strings.listJoin(project['tech']['infrastructure']['operatingSystems'], ', ')}]]
  [/]
  [# th:if="${project['tech']['infrastructure']['containers'] != null and !#lists.isEmpty(project['tech']['infrastructure']['containers'])}"]
  - コンテナ：[[${#strings.listJoin(project['tech']['infrastructure']['containers'], ', ')}]]
  [/]
  [# th:if="${project['tech']['infrastructure']['databases'] != null and !#lists.isEmpty(project['tech']['infrastructure']['databases'])}"]
  - データベース：[[${#strings.listJoin(project['tech']['infrastructure']['databases'], ', ')}]]
  [/]
  [# th:if="${project['tech']['infrastructure']['webServers'] != null and !#lists.isEmpty(project['tech']['infrastructure']['webServers'])}"]
  - Webサーバー：[[${#strings.listJoin(project['tech']['infrastructure']['webServers'], ', ')}]]
  [/]
  [# th:if="${project['tech']['infrastructure']['ciCdTools'] != null and !#lists.isEmpty(project['tech']['infrastructure']['ciCdTools'])}"]
  - CI/CD：[[${#strings.listJoin(project['tech']['infrastructure']['ciCdTools'], ', ')}]]
  [/]
  [# th:if="${project['tech']['infrastructure']['iacTools'] != null and !#lists.isEmpty(project['tech']['infrastructure']['iacTools'])}"]
  - IaC：[[${#strings.listJoin(project['tech']['infrastructure']['iacTools'], ', ')}]]
  [/]
  [# th:if="${project['tech']['infrastructure']['monitoringTools'] != null and !#lists.isEmpty(project['tech']['infrastructure']['monitoringTools'])}"]
  - 監視：[[${#strings.listJoin(project['tech']['infrastructure']['monitoringTools'], ', ')}]]
  [/]
  [# th:if="${project['tech']['infrastructure']['loggingTools'] != null and !#lists.isEmpty(project['tech']['infrastructure']['loggingTools'])}"]
  - ロギング：[[${#strings.listJoin(project['tech']['infrastructure']['loggingTools'], ', ')}]]
  [/]
[/]

[# th:if="${project['tech']['tools'] != null}"]
- 開発支援ツール
  [# th:if="${project['tech']['tools']['sourceControls'] != null and !#lists.isEmpty(project['tech']['tools']['sourceControls'])}"]
  - ソース管理：[[${#strings.listJoin(project['tech']['tools']['sourceControls'], ', ')}]]
  [/]
  [# th:if="${project['tech']['tools']['projectManagements'] != null and !#lists.isEmpty(project['tech']['tools']['projectManagements'])}"]
  - プロジェクト管理：[[${#strings.listJoin(project['tech']['tools']['projectManagements'], ', ')}]]
  [/]
  [# th:if="${project['tech']['tools']['communicationTools'] != null and !#lists.isEmpty(project['tech']['tools']['communicationTools'])}"]
  - コミュニケーション：[[${#strings.listJoin(project['tech']['tools']['communicationTools'], ', ')}]]
  [/]
  [# th:if="${project['tech']['tools']['documentationTools'] != null and !#lists.isEmpty(project['tech']['tools']['documentationTools'])}"]
  - ドキュメント：[[${#strings.listJoin(project['tech']['tools']['documentationTools'], ', ')}]]
  [/]
  [# th:if="${project['tech']['tools']['apiDevelopmentTools'] != null and !#lists.isEmpty(project['tech']['tools']['apiDevelopmentTools'])}"]
  - API開発：[[${#strings.listJoin(project['tech']['tools']['apiDevelopmentTools'], ', ')}]]
  [/]
  [# th:if="${project['tech']['tools']['designTools'] != null and !#lists.isEmpty(project['tech']['tools']['designTools'])}"]
  - デザイン：[[${#strings.listJoin(project['tech']['tools']['designTools'], ', ')}]]
  [/]
  [# th:if="${project['tech']['tools']['editors'] != null and !#lists.isEmpty(project['tech']['tools']['editors'])}"]
  - エディタ：[[${#strings.listJoin(project['tech']['tools']['editors'], ', ')}]]
  [/]
  [# th:if="${project['tech']['tools']['developmentEnvironments'] != null and !#lists.isEmpty(project['tech']['tools']['developmentEnvironments'])}"]
  - 開発環境：[[${#strings.listJoin(project['tech']['tools']['developmentEnvironments'], ', ')}]]
  [/]
[/]

[/]

[/]
[/]

---

[# th:if="${export.certifications != null and !export.certifications.isEmpty()}"]
## 保有資格

| 取得年月 | 資格名 |
|----------|--------|
[# th:each="c : ${export.certifications}"]| [[${c['acquiredAtLabel']}]] | [[${c['name']}]] |
[/]

---

[/]

[# th:if="${export.portfolios != null and !export.portfolios.isEmpty()}"]
## 個人開発・成果物

[# th:each="p : ${export.portfolios}"]
**[[${p['name']}]]**
[[${p['overview']}]]
URL: [[${p['url']}]]
技術スタック：[[${p['techStack']}]]


[/]

---

[/]

[# th:if="${export.snsPlatforms != null and !export.snsPlatforms.isEmpty()}"]
## SNS

[# th:each="s : ${export.snsPlatforms}"]- [[${s['name']}]]: [[${s['url']}]]
[/]

---

[/]

## 自己PR

[# th:each="sp : ${export.selfPromotions}"]
**[[${sp['title']}]]**
[[${sp['content']}]]


[/]
[/]
