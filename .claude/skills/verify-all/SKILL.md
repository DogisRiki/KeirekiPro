---
description: 変更領域を判定して該当するverify(shellcheck/frontend/backend/terraform)を直列実行する。コミット・PR作成前の標準ゲート。
---

# verify-all

## Job

`git diff` から変更領域を判定し、該当する verify Skill を直列実行する。
コミット前・PR作成前(/ship-it)の標準ゲート。ゴールベースループ(/goal)の判定端点。

## Steps

1. 変更領域を判定する:

```
git status --porcelain
```

```
git diff --name-only origin/main...HEAD
```

   (未コミット変更とブランチ差分の両方を見る)

2. 変更されたパスに応じて、該当領域のverifyを**この順で直列**に実行する(並列実行禁止):
   - `.sh` のファイルに変更あり(消したファイルも含む) → 下の「シェルスクリプトの検査」の手順
   - `frontend/` に変更あり → `/verify-frontend` の手順
   - Java 版のファイルに変更あり → `/verify-backend` の Java 版の手順
   - Go 版のファイルに変更あり → `/verify-backend` の Go 版の手順。コマンドは `bash .claude/scripts/parallel/run-check.sh backend-go make check` の1つである
   - `terraform/` に変更あり → `/verify-terraform` の手順
   - 上記以外のみ(doc/.github等) → コマンド実行は不要。その旨を報告する

   Java 版のファイルと Go 版のファイルは、`ci.yaml` の見分け `backend_java` と `backend_go` と同じ形で見分ける。

   - Java 版のファイル: `backend/src/**` `backend/*.gradle` `backend/gradle/**` `backend/config/**` `backend/gradlew*` `docker/backend/**`
   - Go 版のファイル: `backend/**/*.go` `backend/go.mod` `backend/go.sum` `backend/Makefile` `backend/.golangci.yml` `backend/.testcoverage.yml` `backend/.gremlins.yaml` `backend/api/**` `backend/sqlc.yaml` `backend/db/queries/**` `backend/assets/**` `backend/src/main/resources/db/migration/**` `backend/src/main/resources/mail/**` `docker/backend-go/**`。作業フォルダに `backend/go.mod` があるときだけ当てる
   - マイグレーションのファイル(`backend/src/main/resources/db/migration/**`)とメールのひな形(`backend/src/main/resources/mail/**`)は両方に当たるので、Claude は Java 版、Go 版の順に両方の手順を動かす
   - `backend/` の下でも、どちらにも当たらないファイル(`backend/CLAUDE.md` など)だけが変わったときは、backend のコマンドは動かさない

   各verifyの手順は、コマンドを `bash .claude/scripts/parallel/run-check.sh <領域> <コマンド>` で呼び、いまの作業フォルダ(worktree のセッションでは worktree の最上位)を1回きりのコンテナで検査する。
   変更領域の判定の `git` も、いまの作業フォルダで打つ。

   **シェルスクリプトの検査**: Claude は、次のコマンドで、作業フォルダのすべての `.sh` のファイルを、一度に shellcheck に渡す。

   ```bash
   cd "$(git rev-parse --show-toplevel)" && git ls-files -z --cached --others --exclude-standard -- '*.sh' | perl -0 -ne 'chomp; print "$_\0" if -f' | xargs -0 docker run --rm -v "$(pwd -W 2>/dev/null || pwd):/mnt" koalaman/shellcheck:v0.11.0
   ```

   - 終了コードが0なら通った、0でなければ通らなかったとする。CI の escape-hatch の shellcheck(`.github/workflows/guardrails.yaml` の「Lint shell scripts (shellcheck)」)と同じく、info と style の警告も通らなかったとする
   - 変えたファイルだけでなく、すべての `.sh` のファイルを渡すのは、CI と同じ判定にするためである。変えたファイルだけを渡すと、shellcheck が `. "$LIB"` で読み込む先のファイルをたどらず、CI だけが警告を出す
   - `--others --exclude-standard` は、まだコミットしていない新しい `.sh` のファイルを検査に入れる。verify-all はコミットの前に動くので、入れないと新しいファイルの誤りを見落とす。`perl` は、作業フォルダから消したファイルを渡さないために使う。消したファイルを渡すと、shellcheck がファイルを読めずに失敗する
   - shellcheck のイメージの版は、`guardrails.yaml` の版と同じにする。`guardrails.yaml` の版を変えるときは、このコマンドの版も同じ変更で変える。版が違うと、手元と CI とで、どの書き方を誤りとするかが変わる
   - このコマンドは `run-check.sh` を通さない。shellcheck は数秒で終わり、compose のサービスも作業フォルダのボリュームも使わないので、同時に走らせる数を抑える必要が無いためである
   - Docker につながらずに失敗したとき(`docker run` が Docker のデーモンにつながらないという文を出したとき)は、コードを直しても解けない。Claude は、その文を所有者に報告し、修正の繰り返しに入らない

3. いずれかがFAILなら修正し、**修正した領域のverifyを最初から**やり直す。
   ただし、`run-check.sh` の終了コード69(検査の環境を用意できなかった)と75(待ちの上限に達した)によるFAILは、コードを直しても解けない。
   Claude は、そのFAILの理由を所有者に報告し、修正の繰り返しに入らない。終了コード10(順番待ち)の扱いは、各verifyの「順番待ちと検査できないとき」に従う。

## Rules

- 各verify Skillのゴールハック禁止則をすべて適用する
- 「時間がかかるから」という理由でcoverage/checkを省略しない(buildでの代替も不可)

## Report

```
品質チェックの結果:
- 変更があった領域: frontend、backend
- シェルスクリプトの shellcheck による検査: <通った、または通らなかった、または .sh のファイルの変更が無いので動かしていない>
- /verify-frontend による frontend の品質チェック: <通った、または通らなかった>
- /verify-backend による backend の Java 版の品質チェック: <通った、または通らなかった>
- /verify-backend による backend の Go 版の品質チェック: <通った、または通らなかった、または Go 版のファイルの変更が無いので動かしていない>
- /verify-terraform による terraform の品質チェック: 変更が無いので動かしていない
```

Claude は、領域ごとの詳しい結果を、その領域の verify のスキルの「Report」の節の形で添える。
