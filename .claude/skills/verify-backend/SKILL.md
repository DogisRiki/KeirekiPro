---
description: backendの品質ゲート(Java 版は spotlessApply→check、Go 版は make check)を順次実行し、結果を要約報告する。backend配下を変更したら完了報告前に必ず実行する。
---

# verify-backend

## Job

backendの品質ゲートを規定の順序で直列実行し、PASS/FAILを判定する。ループの検証端点。

## Java 版と Go 版の見分け

backend には、Java 版と Go 版の2つがある。Claude は、変わったファイルを次の形で見分け、当たった版の手順を動かす。この見分けは、`ci.yaml` の見分け `backend_java` と `backend_go` と同じである。

- Java 版のファイル: `backend/src/**` `backend/*.gradle` `backend/gradle/**` `backend/config/**` `backend/gradlew*` `docker/backend/**`
- Go 版のファイル: `backend/**/*.go` `backend/go.mod` `backend/go.sum` `backend/Makefile` `backend/.golangci.yml` `backend/.testcoverage.yml` `backend/.gremlins.yaml` `backend/api/**` `backend/sqlc.yaml` `backend/assets/**` `backend/src/main/resources/db/migration/**` `docker/backend-go/**`
- Go 版のファイルの見分けは、作業フォルダに `backend/go.mod` があるときだけ当てる。`backend/go.mod` が無いときは、Go 版の品質チェックを動かせないためである
- マイグレーションのファイル(`backend/src/main/resources/db/migration/**`)は、両方に当たる。Java 版と Go 版が同じマイグレーションのファイルを読むためである。Claude は、両方の手順を、Java 版、Go 版の順に動かす
- どちらにも当たらないファイル(`backend/CLAUDE.md` など)だけが変わったときは、Claude はコマンドを動かさず、その旨を報告する

## Steps(Java 版)

以下を**この順で1つずつ**実行する(並列実行禁止)。

```
bash .claude/scripts/parallel/run-check.sh backend ./gradlew spotlessApply
bash .claude/scripts/parallel/run-check.sh backend ./gradlew check
```

`check` の内訳: spotlessCheck + checkstyle + test(JUnit/Testcontainers) + jacocoTestReport +
**jacocoTestCoverageVerification(カバレッジ閾値)** + spotbugsMain/Test。

- `run-check.sh` は、いまの作業フォルダ(worktree のセッションでは worktree の最上位)を読み込んだ1回きりのコンテナで、コマンドを動かす。Claude は、起動したままの常駐コンテナの中で品質チェックを動かさない
- Claude は、`./gradlew check` を、`--wait` を付けないときも Bash の `run_in_background` で呼ぶ。1回きりのコンテナでの最初の1回は約10分かかり、Bash を前面で動かすときの上限(600秒)を超えるおそれがあるためである。前面で時間切れになると、コマンドそのものの失敗と見分けられない
- `check` が失敗したら、Claude は、直したあとに先に `spotlessApply` をかけ、落ちたチェックだけを名前で流し直す(例 `./gradlew checkstyleMain`、`./gradlew test --tests <落ちたテストクラス>`)。Claude は、落ちたチェックが通ってから、`check` を1回だけ流す。`check` は1回に約13分かかり、書式の誤りだけでも全体が落ちるためである
- 単発のテストや検査(`./gradlew test --tests <テストクラス>` など)も、`bash .claude/scripts/parallel/run-check.sh backend ./gradlew test --tests <テストクラス>` のように `run-check.sh` で打つ
- `./gradlew check` が終了コード0で終わったときだけ、`run-check.sh` が作業フォルダの `.claude/.state/gate-run-backend.txt` に品質チェックが通った時刻を書く
- Testcontainers が使う `dind` が止まっていれば、`run-check.sh` が本体フォルダのプロジェクトの `dind` を起こしてからコマンドを動かす。起こせなければ、`run-check.sh` は終了コード69で終わる

## Steps(Go 版)

Go 版の品質チェックは、次の1つのコマンドで動かす。

```
bash .claude/scripts/parallel/run-check.sh backend-go make check
```

`make check` は、書式の検査(`fmt-check`)、生成したコードの食い違いの検査(`generate-check`)、静的な検査と依存の向きの検査(`lint`)、テスト(`test`)、カバレッジの下限の検査(`coverage`)、ビルド(`build`)を順に動かす。

- `run-check.sh` は、Go 版の領域 `backend-go` でも、いまの作業フォルダを読み込んだ1回きりのコンテナでコマンドを動かす。Java 版と比べる検査のために、`run-check.sh` は作業フォルダの最上位を読み取り専用で `/repo` に差し込む
- Claude は、`make check` を Bash の `run_in_background` で呼ぶ。結合テストが testcontainers-go で Postgres と Redis を動かすので、前面で動かすときの上限(600秒)を超えるおそれがあるためである
- `make check` が失敗したら、Claude は、直したあとに、落ちた検査だけを make のターゲットの名前(`lint` `test` など)で流し直す。書式の検査で落ちたときは、`make fmt` で書式を直す。Claude は、落ちた検査が通ってから、`make check` を1回だけ流す
- `make check` が終了コード0で終わったときだけ、`run-check.sh` が作業フォルダの `.claude/.state/gate-run-backend-go.txt` に品質チェックが通った時刻を書く。Java 版の記録 `gate-run-backend.txt` とは別の記録である
- testcontainers-go が使う `dind` が止まっていれば、Java 版と同じく、`run-check.sh` が本体フォルダのプロジェクトの `dind` を起こしてからコマンドを動かす

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
- Go 版のテストへの `t.Skip` の追加
- Go 版のコードへの `//nolint` の追加
- Go 版の検査の設定(`Makefile` `.golangci.yml` `.testcoverage.yml` `.gremlins.yaml`)を緩める変更

カバレッジ閾値に届かない場合は、**テストを追加して**満たす。
新規テストは対象コードを一時的に壊して赤くなることを確認してから戻す。壊す箇所の数と、壊した写しの作り方と流し方は、`.kiro/steering/tech.md` の「テストの完全性」に従う。

## Report

```
backend の品質チェックの結果:
- spotlessApply による書式の整え: <通った、または通らなかった>
- check による品質チェックの全体: <通った、または通らなかった>
  - テストの数: <数>件
  - カバレッジ: <数>%。カバレッジは、テストで動いたコードの割合です
  - SpotBugs の指摘: <数>件
```

Go 版の手順を動かしたときは、Claude は次の形で報告する。両方の手順を動かしたときは、Java 版の報告のあとに続ける。

```
backend の Go 版の品質チェックの結果:
- make check による品質チェックの全体: <通った、または通らなかった>
  - 通らなかった検査: <fmt-check、generate-check、lint、test、coverage、build のうち落ちたもの。全部通ったときは「なし」>
  - カバレッジ: <数>%。カバレッジは、テストで動いたコードの割合です
```

通らなかったチェックがあるときは、Claude は、失敗したクラスやパッケージとテストの名前と、エラーの要点と、どう直すかを添える。
