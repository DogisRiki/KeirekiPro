---
description: backendの品質ゲート(spotlessApply→check)を順次実行し、結果を要約報告する。backend配下を変更したら完了報告前に必ず実行する。
---

# verify-backend

## Job

backendの品質ゲートを規定の順序で直列実行し、PASS/FAILを判定する。ループの検証端点。

## Steps

以下を**この順で1つずつ**実行する(並列実行禁止)。

```
bash .claude/scripts/parallel/run-check.sh backend ./gradlew spotlessApply
bash .claude/scripts/parallel/run-check.sh backend ./gradlew check
```

`check` の内訳: spotlessCheck + checkstyle + test(JUnit/Testcontainers) + jacocoTestReport +
**jacocoTestCoverageVerification(カバレッジ閾値)** + spotbugsMain/Test。

- `run-check.sh` は、いまの作業フォルダ(worktree のセッションでは worktree の最上位)を読み込んだ1回きりのコンテナで、コマンドを動かす。Claude は、起動したままの常駐コンテナの中で品質チェックを動かさない
- Claude は、`./gradlew check` を、`--wait` を付けないときも Bash の `run_in_background` で呼ぶ。1回きりのコンテナでの最初の1回は約10分かかり、Bash を前面で動かすときの上限(600秒)を超えるおそれがあるためである。前面で時間切れになると、コマンドそのものの失敗と見分けられない
- 失敗したら修正して `check` を再実行する
- 単発のテストや検査(`./gradlew test --tests <テストクラス>` など)も、`bash .claude/scripts/parallel/run-check.sh backend ./gradlew test --tests <テストクラス>` のように `run-check.sh` で打つ
- `./gradlew check` が終了コード0で終わったときだけ、`run-check.sh` が作業フォルダの `.claude/.state/gate-run-backend.txt` に品質チェックが通った時刻を書く
- CI環境では `bash .claude/scripts/parallel/run-check.sh backend` を外し、`backend/` で `./gradlew check` をネイティブ実行する
- Testcontainers が使う `dind` が止まっていれば、`run-check.sh` が本体フォルダのプロジェクトの `dind` を起こしてからコマンドを動かす。起こせなければ、`run-check.sh` は終了コード69で終わる

## 順番待ちと検査できないとき

`run-check.sh` は、コマンドの終了コードをそのまま返す。ただし、次の3つの終了コードのときは、`run-check.sh` はコマンドを動かしていない。

- 終了コード10(枠が埋まっていて待たなかった): Claude は、出された `[parallel] 順番待ち:` の行(どのIssueのチェックを待つか)を所有者に伝え、同じコマンドに `--wait` を付けて(例 `bash .claude/scripts/parallel/run-check.sh --wait backend ./gradlew check`)、Bash の `run_in_background` で呼び直す。Claude は、このときの Bash の `timeout` を、待ちの上限(1800秒)とそのコマンドの実行時間の和より長くする(目安は3600000ミリ秒)。`--wait` は、待ったあとに同じ呼び出しの中でコマンドを動かすので、`run_in_background` の既定の30分では足りない(`./gradlew check` では最悪で約40分になる)。呼び直した結果の終了コードを、そのコマンドの結果として扱う
- 終了コード69(検査の環境を用意できなかった): Claude は、そのコマンドを不合格として扱い、出された `[parallel] 検査できない:` の理由を所有者に報告する。コードを直しても解けないので、Claude は修正の繰り返しに入らない
- 終了コード75(待ちの上限に達した): Claude は、そのコマンドを不合格として扱い、どのIssueのチェックを待っていたか(出された `[parallel] 順番待ち:` の行)を所有者に報告する。Claude は修正の繰り返しに入らない

これら以外の0でない終了コードは、コマンドそのものの失敗である。Claude は、上の手順のとおり修正してからやり直す。

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
