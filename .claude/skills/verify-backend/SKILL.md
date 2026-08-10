---
description: backendの品質ゲート(spotlessApply→check)を順次実行し、結果を要約報告する。backend配下を変更したら完了報告前に必ず実行する。
---

# verify-backend

## Job

backendの品質ゲートを規定の順序で直列実行し、PASS/FAILを判定する。ループの検証端点。

## Steps

以下を**この順で1つずつ**実行する(並列実行禁止)。

```
docker compose exec -w /home/spring/app backend ./gradlew spotlessApply
docker compose exec -w /home/spring/app backend ./gradlew check
```

`check` の内訳: spotlessCheck + checkstyle + test(JUnit/Testcontainers) + jacocoTestReport +
**jacocoTestCoverageVerification(カバレッジ閾値)** + spotbugsMain/Test。

- 失敗したら修正して `check` を再実行する
- CI環境では `backend/` で `./gradlew check` をネイティブ実行する
- Testcontainers起因の失敗(dindコンテナ停止等)は `docker compose up -d dind` で復旧を試みる

## Rules(ゴールハック禁止則)

「見かけの合格」を作る次の行為を**絶対に行わない**(escape-hatch CIも機械検知する):

- テストへの `@Disabled` の追加
- 既存テストのアサーション削除・弱体化(意図的な変更はPR本文に `Test-Change-Justification:` を記載)
- `gradle/quality.gradle`(閾値)・`config/`(checkstyle/spotbugs除外)・ArchUnitテストの変更(CODEOWNERS保護対象)
- `build.gradle` の `apply from: 'gradle/quality.gradle'` 行の削除・violationRulesの上書き

カバレッジ閾値に届かない場合は、**テストを追加して**満たす。
新規テストは対象コードを一時的に壊して赤くなることを確認してから戻す。

## Report

```
verify-backend:
- spotlessApply -> PASS/FAIL
- check         -> PASS/FAIL (test件数 / カバレッジ% / spotbugs指摘数)
```

FAILがある場合は、失敗ログの要点(クラス・テスト名・エラー概要)と修正方針を添える。
