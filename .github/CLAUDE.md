# .github の作業規約

`.github/` の下のワークフロー、スクリプト、テスト、データのファイルを直すときの決まり。ゲート設定の扱いはルートの CLAUDE.md に従う。

## 書き込みと push

- `.github/` への書き込み(Edit・Write と、`cp` `sed` `perl` などのコマンド)と `rm -rf` は、`.claude/settings.json` の deny に当たって毎回止まる。
  `&&` でつないだコマンドの一部に当たっても止まる(https://code.claude.com/docs/en/permissions.md の Compound commands)
- 止められた書き込みを、python や別のコマンドなど、別の経路で通さない
- 完成版を scratchpad で作り、テストまで済ませてから、人間に `cp` のコマンドをまとめて渡す。全文や差分は渡さない。
  `cp` のコマンドの前に、作業フォルダに移る `cd <作業フォルダの絶対パス>` を、別のコマンドとして渡す。
  人間の端末は本体フォルダにいることがあり、worktree のセッションの変更が本体フォルダの main に入ってしまうためである
- 人間が置いたあとは、`cmp` で完成版と同じかを確かめ、リポジトリの場所のままテストを流し直す
- push は `git push -u origin <branch>` の形だけで打つ。`-q` などを前に足すと許可の決まりに当たらず、自動モードの判定に回って止まることがある
- `.claude/hooks/protect-main.sh` は、Bash のコマンドの文字列の中に git の commit や push の形の文字列があると、ヒアドキュメントの中身でも止める。その文字列を含むファイルは Write で書く
- ワークフローを足す・変える・消すときは、README のワークフローの一覧の表と Mermaid の図も直す。README の書き方は `doc/CLAUDE.md` に従う

## シェルのスクリプトのテスト

`.github/scripts/tests/*.sh` は、必ずコンテナの中で流す。

```bash
docker run --rm -v "$(pwd -W):/w:ro" alpine:3 sh -c 'apk add --no-cache bash jq >/dev/null 2>&1 && mkdir -p /t && cp -r /w/.github /t/ && chmod -R a-x /t/.github/scripts && bash /t/.github/scripts/tests/test-XXX.sh'
```

- ホストの前提は bash と perl だけで、`jq` が無いことがある。`jq` の無いホストで直に流すと、スクリプトがいつも失敗で終わり、失敗を期待するテストが誤った理由で通る。終了コードだけでなく、出力の中身も確かめる
- `.github/scripts` のファイルには実行のビットが無い(`core.fileMode=false`)。テストからは `bash "$SCRIPT"` の形で起動する。直に起動すると、新しく clone した CI で `exit 126` になる
- 作業フォルダをつなぐだけでは、CI のファイルの権限が再現しない。コンテナの中に写してから `chmod -R a-x` する

shellcheck は、CI と同じく、すべての `.sh` を一度に渡す。変えたファイルだけを渡すと、`. "$LIB"` で読み込む先のファイルをたどらず、CI だけが警告を出す。CI は info と style の警告も失敗にする。

```bash
git ls-files -z '*.sh' | xargs -0 docker run --rm -v "$(pwd -W):/mnt" koalaman/shellcheck:v0.11.0
```

- まだリポジトリに無いファイルを検査するときは、作業フォルダに `-v` で重ねない。Docker は重ねる先を作るため、作業フォルダに0バイトのファイルが残る。
  `git archive HEAD | tar -x -C <scratchpad の一時フォルダ>` で写した先に置いて流すか、ファイルを引数で直に渡す
- バックスラッシュを含むテストの JSON は、Write でファイルに書いて標準入力に流す。Bash のコマンドの文字列では `\\` が `\` になる

## 期待一覧を変えるとき

- `.github/audit/required-checks.json` か ruleset の本数を変える PR では、期待一覧を読む3本のテスト
  (`test-check-audit-skipped-required.sh` `test-check-audit-dependabot-stuck.sh` `test-check-canary-results.sh`)を PR の前に流す
- 監査が判定不能になったときの「Re-run」は、失敗したときと同じコミットで動く。原因がコードにあるときは効かない。
  そのときは、`check-audit-skipped-required.sh` を手元で `GITHUB_RUN_ID=<失敗した実行>` として流して(読むだけ)調べられなかった区間を確かめ、新しく workflow_dispatch で実行する
