# タスク

- [x] 1. 置き場所を作り、設計が前提にしている外の仕組みの動きを実物で確かめる
- [x] 1.1 置き場所を作り、Claude の CLI を確かめてから入れるアクションとスクリプトを作る

  Claude は、実装のメモの置き場所を作る。Claude は、置き場所に、設計の「verified-claude と install-verified-claude.sh」の部品の節のとおりに、アクション `verified-claude` と、スクリプト `install-verified-claude.sh` と、そのテスト `test-install-verified-claude.sh` を作る。テストは、偽の `curl` と `gpg` と、URL の先頭を差し替える環境変数で配布元を置き換え、ネットワークを使わない。Claude は、テストを `KP_TEST_CASE` で場合を選んで流せる形にする。
  - 完了の確かめ方: 次の3つが起きる
    - Linux のコンテナで流した `test-install-verified-claude.sh` の場合が、すべて通る
    - `KP_TEST_CASE` に場合の名前を1つ入れて流すと、その場合だけが流れる
    - glibc を使う Linux のコンテナで、本物の配布元から版 2.1.323 を入れると、`claude --version` が 2.1.323 を返す。glibc と musl は、どちらも Linux で C のプログラムが使う標準のライブラリで、互いに置き換えて使えない。`linux-x64` の CLI は glibc 向けに作られている。実装のメモの alpine のコンテナは musl を使うので、Claude は、この確認に alpine のコンテナを使わない
  - 受入基準とテストの対応: 要件3の受入基準3のうち、Claude を動かす CLI が配布元の署名で確かめた物であることは、テストの「指紋の違う鍵では PATH に足さずに失敗する」「合わない署名では PATH に足さずに失敗する」「合わない SHA-256 では PATH に足さずに失敗する」「3つとも合えば PATH に足す」で確かめる
  - _要件: 3.3_

- [x] 1.2 Claude の CLI の結果の JSON が、設計の見分け方と合うかを確かめる

  Claude は、設計の「claude-auto-fix-run-claude.sh」の部品の節の「確かめていること」のとおりに、版 2.1.323 を設計と同じ引数と設定で動かして CLI の結果を調べるスクリプトを、置き場所に作る。このスクリプトは、Bash を求める指示、`target/` の外のファイルを読む指示、誤った鍵の3つの場合で CLI を動かし、結果の JSON の欄の名前と値を、鍵の値と会話の本文を除いて置き場所のファイルに書く。Claude は、本物の鍵を要る2つの場合を流すために、所有者に、所有者の端末で1つのコマンドを打つよう頼む。そのコマンドは、所有者が `claude setup-token` で作った鍵を画面に出さずに `read -s` で環境変数に読み、glibc を使う Linux のコンテナを `docker run -e CLAUDE_CODE_OAUTH_TOKEN` で起こす。`-e` に名前だけを書くので、鍵の値はコマンドの引数に現れない。そのコマンドは、コンテナの中で、タスク 1.1 の `install-verified-claude.sh` で版 2.1.323 を入れてから、CLI の結果を調べるスクリプトを動かす。Claude は鍵の値を見ないので、Claude が自分でこの2つの場合を流すことはできない。所有者が打ったあと、Claude は、置き場所の結果のファイルを読み、確かめた日と版と結果を、research.md の見出し `## Claude の CLI の結果の JSON の確認` の下に書く。pnpm のエラーの文を確かめるタスク 1.3 と、一時のブランチの Gradle のスナップショットを確かめるタスク 1.4 は、research.md の別々の見出しに書くので、3つのタスクを並行に進めても、書く箇所は重ならない。
  - 完了の確かめ方: 次の4つが起きる
    - research.md の見出し `## Claude の CLI の結果の JSON の確認` の下に、3つの場合の `subtype` と `is_error` と `result` の文の先頭と `api_error_status` が書いてある
    - Bash を求めた場合と `target/` の外を読もうとした場合で、CLI がコマンドを動かさず、`target/` の外のファイルの中身が結果に出ていない
    - 誤った鍵の場合の結果が、設計の見分け方で `key` になる
    - どれかが設計と違えば、Claude は、設計を見直すきっかけの「Claude の CLI の、`-p` の結果の JSON の形、認証の失敗の見分け方、`--tools` と拒否の決まりの効き方が変わったとき」に当たることを所有者に報告して止まる
  - 受入基準とテストの対応: 要件3の受入基準3のうち、Claude がコマンドを動かせず `target/` の外を読めないことと、要件6の受入基準3のうち、鍵が誤っているときを見分けられることは、このタスクの実物の結果で確かめる。偽の CLI で同じ見分け方を確かめるテストは、Claude を動かすスクリプトを作るタスク 4.2 で作る
  - _要件: 3.3, 6.3_

- [x] 1.3 pnpm が72時間の待ちで版を入れられないときのエラーの文を確かめる (並行可)

  Claude は、設計の「claude-auto-fix-verify.sh」の部品の節の pnpm の項のとおりに、`frontend/` の写しの `package.json` に公開から72時間経っていない版を固定し、`pnpm install --lockfile-only --no-frozen-lockfile --ignore-scripts` を開発環境のコンテナで動かす。Claude は、出たエラーの文と、確かめた日と、使った部品と版を、research.md の見出し `## pnpm が72時間の待ちで止まったときのエラーの文` の下に書く。
  - 完了の確かめ方: research.md の見出し `## pnpm が72時間の待ちで止まったときのエラーの文` の下に、エラーの文と終わり方の番号が書いてある。エラーの文が `ERR_PNPM_NO_MATURE_MATCHING_VERSION` を含まないときは、Claude は、設計を見直すきっかけの「pnpm が `minimumReleaseAge` で版を入れられずに止まったときのエラーの文が、verify の見分け方と違ったとき」に当たることを所有者に報告して止まる
  - 受入基準とテストの対応: 要件2の受入基準9のうち、除外の欄に無い版で pnpm が止まったことを見分ける文は、このタスクの実物の結果で決める。この文で `blocked` にすることは、確認のスクリプトの `apply` の形を作るタスク 4.4 のテストで確かめる
  - _要件: 2.9_
  - _対象の部品: claude-auto-fix-verify.sh_

- [x] 1.4 一時のブランチのコミットの Gradle のスナップショットで、maven の差が返るかを確かめる (並行可)

  Claude は、設計の「プロジェクトの決まりを守っているか」の節の「使う外部の機能がこのリポジトリで使えるか」の maven の項のとおりに、確認に使う2つのブランチと、確認のワークフロー `tmp-gradle-snapshot-check.yaml` を用意する。Claude は、1つ目のブランチ `chore/tmp-gradle-snapshot-target` を作って push し、確認のワークフローを `.claude/.state/claude-auto-fix-unresolved-alerts/gradle-check/` に作る。確認のワークフローは main に入れないので、Claude は、このファイルを置き場所の `place-1/` に置かない。Claude は `.github/` に書けないので、Claude は、所有者に、2つ目のブランチ `chore/tmp-gradle-snapshot-check` に確認のワークフローを置いて push するコマンドを1つ示し、打つよう頼む。確認のワークフローの実行が終わったら、Claude は、差分比較の API の結果と、2つ目のブランチのコミットにスナップショットが結び付いていないことを読み、確かめた日とコミットと結果を、research.md の見出し `## 一時のブランチの Gradle のスナップショットの確認` の下に書く。そのあと、Claude は2つのブランチと `gradle-check/` のフォルダを消す。
  - 完了の確かめ方: 次の3つが起きる
    - research.md の見出し `## 一時のブランチの Gradle のスナップショットの確認` の下に、差分比較の API が main と1つ目のブランチのコミットの maven の差を返したことと、2つ目のブランチのコミットにスナップショットが結び付いていないことが書いてある
    - 2つのブランチと `gradle-check/` のフォルダが残っていない
    - maven の差が返らないときは、Claude は、設計を見直すきっかけの「実装の前の確認で、一時のブランチのコミットに送った Gradle のスナップショットについて、差分比較の API が maven の差を返さなかったとき」に当たることを所有者に報告して止まる
  - 受入基準とテストの対応: 要件2の受入基準9のうち、Claude の変更の PR を dependency-cooldown がどちらに扱うかを PR を作る前に判定できることは、このタスクの実物の結果で確かめる。判定のジョブの組み立ては、2つのワークフローのテストを作るタスク 6.1 のテストで確かめる
  - _要件: 2.9_
  - _対象の部品: claude-auto-fix-target.yaml_

- [x] 2. どのスクリプトも使う共通の関数とガードを作る
- [x] 2.1 種類と識別子の key とブランチ名と表示名を作る関数、目印を書く関数と読む関数、直しても緑にならない検査を除く関数を作る

  Claude は、置き場所に、設計の「lib-claude-auto-fix.sh」の部品の節の10個の関数のうち、key を作る関数、ブランチ名と表示名を作る関数、目印を書く関数、目印を読む関数、`fixable_red_checks` と、そのテスト `test-lib-claude-auto-fix.sh` を作る。Claude は、テストを `KP_TEST_CASE` で場合を選んで流せる形にする。
  - 完了の確かめ方: Linux のコンテナで流した `test-lib-claude-auto-fix.sh` の場合が、すべて通る。`KP_TEST_CASE` に場合の名前を入れると、その場合だけが流れる
  - 受入基準とテストの対応: 次の3つである
    - 要件2の受入基準1(1つの対象につき PR を1つ)と要件4の受入基準3のうち、同じ部品と修正版の組を同じ名前のブランチにすることは、テストの「7種類の key とブランチ名と表示名がデータの形の表のとおりになる」「vuln-fix の種類のブランチ名が今の vuln-fix のブランチ名から chore/ を除いたものと同じになる」で確かめる
    - 要件4の受入基準4のうち、直せなかったことを知らせる Issue の状態を読むことは、テストの「github-actions[bot] が書いた最も新しい目印から Issue の状態を読む」「ほかの利用者が書いた目印を読まない」で確かめる
    - 要件1の受入基準4のうち、Claude が直しても緑にならない5つの検査を除くことは、テストの「dependency-review と approval_gated の4つの検査を除き、ほかの赤の検査を残す」「偽の期待一覧で approval_gated の検査を1つ足すとその検査も除く」で確かめる
  - _要件: 1.4, 2.1, 4.3, 4.4_

- [x] 2.2 Claude の変更の PR を探す関数、実行の結果のファイルを読む関数、対象が消えたかを見分ける関数を足す

  Claude は、置き場所の `lib-claude-auto-fix.sh` に、設計の10個の関数のうち、Claude の変更の PR を探す関数、実行の結果のファイルを読む関数、対象が消えたかを見分ける関数の3つを足し、その場合を `test-lib-claude-auto-fix.sh` に足す。対象が消えたかの見分け方は、設計のデータの形の節の「対象が消えたかの見分け方」の表のとおりにする。テストは、偽の `gh` で GitHub の応答を置き換える。
  - 完了の確かめ方: Linux のコンテナで流した `test-lib-claude-auto-fix.sh` の場合が、すべて通る
  - 受入基準とテストの対応: 次の3つである
    - 要件4の受入基準3のうち、同じ対象の開いている PR を見つけることは、テストの「ブランチ名とラベルと同じリポジトリのブランチがそろった PR だけを Claude の変更の PR とみなす」「fork のブランチの PR とラベルの無い PR を Claude の変更の PR とみなさない」で確かめる
    - 要件2の受入基準6と要件4の受入基準5のうち、対象が消えたことを見分けることは、テストの「7種類ごとに、消えたときに消えたと答え、残っているときに残っていると答える」で確かめる
    - 要件6の受入基準1のうち、実行の結果のファイルを読むことは、テストの「直近4日の結果のファイルを読み、取り消されて結果のファイルが無い実行を unavailable と数える」で確かめる
  - _要件: 2.6, 4.3, 4.5, 6.1_

- [x] 2.3 Claude の変更から、ゲートの設定のファイルと検査を弱める変更を見つけるガードを作る (並行可)

  Claude は、置き場所に、設計の「claude-auto-fix-guard.sh」の部品の節のとおりに、ガード `claude-auto-fix-guard.sh` と、そのテスト `test-claude-auto-fix-guard.sh` を作る。テストは、一時のフォルダに Git のリポジトリを作り、2つのコミットの差でガードを呼ぶ。
  - 完了の確かめ方: Linux のコンテナで流した `test-claude-auto-fix-guard.sh` の場合が、すべて通る
  - 受入基準とテストの対応: 次の2つである
    - 要件3の受入基準1(ゲートの設定のファイルを含む変更を PR にしない)は、テストの「`.github/` のファイルの変更で0以外になる」「`backend/config/` のファイルの変更で0以外になる」で確かめる
    - 要件3の受入基準2(検査を弱める変更を PR にしない)は、テストの「足した `codeql[` の行で0以外になる」「足した `@SuppressWarnings` の行で0以外になる」「`.github/container-scan-suppressions.json` の変更で0以外になる」「名前が ignore で終わるファイルの変更で0以外になる」「`_test.go` の `require.` の行の削除で0以外になる」「ふつうのコードの変更で0になる」「種類が codeql のとき見つけた行を出さずに件数だけを出す」で確かめる
  - _要件: 3.1, 3.2_
  - _対象の部品: claude-auto-fix-guard.sh_

- [x] 2.4 dependency-cooldown の判定が要るかを決める関数と、3つの判定の終わり方から扱いを決める関数を足す

  Claude は、置き場所の `lib-claude-auto-fix.sh` に、設計の10個の関数のうち `cooldown_needed` と `cooldown_outcome` を足し、その場合を `test-lib-claude-auto-fix.sh` に足す。`cooldown_needed` は、Go の版を書くファイルを見分けるために、今ある `lib-go-release.sh` を読み込んで `go_release_is_target` をそのまま呼ぶ。テストは、偽の `ci-tool-versions.json` を一時のフォルダに置いて `cooldown_needed` に渡す。
  - 完了の確かめ方: Linux のコンテナで流した `test-lib-claude-auto-fix.sh` の場合が、key とブランチ名と目印を扱う関数を作るタスク 2.1 と、Claude の変更の PR を探す関数などを足すタスク 2.2 で作った場合も含めて、すべて通る
  - 受入基準とテストの対応: 要件2の受入基準9のうち、Claude の変更に dependency-cooldown の判定が要るかを決めることと、3つの判定の終わり方から扱いを決めることは、テストの「cooldown_needed が依存の版を宣言する6つのファイルと backend/go.mod と docker/backend-go/Dockerfile.prod と名前が小文字の <何か>.dockerfile のファイルと偽の ci-tool-versions.json の ci と dev のファイルで true を出し、ふつうのコードのファイルだけでは false を出す」「Go の版を書くファイルの場合ごとに cooldown_needed が go_release_is_target と同じ答えになる」「cooldown_outcome が (0,0,0) と (3,0,0) で ship、(1,0,0) と (0,1,0) と (0,0,1) で blocked、(2,0,0) と (0,2,0) と (0,0,2) と (1,2,0) で fail を出す」で確かめる
  - _要件: 2.9_
  - _依存: 2.2_

- [x] 3. 今ある検査とワークフローに、この仕組みが読む出力を足す
- [x] 3.1 止まった Dependabot の PR の一覧を JSON で書き出す (並行可)

  Claude は、`check-audit-dependabot-stuck.sh` とそのテストの今の版を置き場所に写し、設計の「check-audit-dependabot-stuck.sh の変更」の節のとおりに、環境変数 `STUCK_JSON_OUT` で止まった PR の一覧を書き出す形を足す。Claude は、テストに場合を足す。
  - 完了の確かめ方: Linux のコンテナで流した `test-check-audit-dependabot-stuck.sh` の場合が、前からある場合も含めてすべて通る
  - 受入基準とテストの対応: 要件1の受入基準4のうち、止まった PR と、その PR の赤の検査の全部を読めることは、テストの「STUCK_JSON_OUT に止まった PR の番号と、承認待ちに分けた赤も含む赤の検査の名前と結論が書かれる」「承認待ちの赤だけの PR が書かれない」「STUCK_JSON_OUT が無いときに今の場合の結果が変わらない」で確かめる
  - _要件: 1.4_
  - _対象の部品: check-audit-dependabot-stuck.sh の変更_

- [x] 3.2 dependency-cooldown の判定のスクリプトに、PR を作る前に判定だけを行う形を足す (並行可)

  Claude は、`check-dependency-cooldown.sh` とそのテストの今の版を置き場所に写し、設計の「check-dependency-cooldown.sh の変更」の節のとおりに、環境変数 `COOLDOWN_MODE=predict` の形を足す。Claude は、テストに場合を足す。
  - 完了の確かめ方: Linux のコンテナで流した `test-check-dependency-cooldown.sh` の場合が、前からある場合も含めてすべて通る
  - 受入基準とテストの対応: 要件2の受入基準9のうち、Claude の変更の PR を dependency-cooldown がどちらに扱うかを PR の検査と同じ結果になるように判定することは、テストの「predict で記録のコメントを書かない」「72時間経っていない版が無ければ0で終わる」「承認を求める見込みなら3で終わる」「署名した者が前の版と違えば1で終わる」「pnpm の除外の欄に無い版なら1で終わる」「PR_NUMBER が無くても predict で動く」「COOLDOWN_MODE が無いときに今の場合の結果が変わらない」で確かめる
  - _要件: 2.9_
  - _対象の部品: check-dependency-cooldown.sh の変更_

- [x] 3.3 frontend-vuln-fix が PR を作れなかった組を vuln-fix の結果のファイルに書く (並行可)

  Claude は、`frontend-vuln-fix.sh` と `frontend-vuln-fix.yaml` とそのテストの今の版を置き場所に写し、設計の「frontend-vuln-fix.sh と backend-vuln-fix.sh の変更」の節のとおりに直す。スクリプトは、`failed=1` にする7か所で vuln-fix の結果のファイルに1行を足し、Claude の変更のブランチがある組では PR を作らない。ワークフローは、vuln-fix の結果のファイルを成果物 `vuln-fix-unresolved` として `if: always()` で上げる。
  - 完了の確かめ方: Linux のコンテナで流した `test-frontend-vuln-fix.sh` の場合が、前からある場合も含めてすべて通る。actionlint が、置き場所の `frontend-vuln-fix.yaml` に指摘を出さない
  - 受入基準とテストの対応: 次の2つである
    - 要件1の受入基準1のうち、frontend の消えずに残った組を書き残すことは、テストの「failed=1 にする7か所でそれぞれ結果のファイルに1行が足される」で確かめる
    - 要件4の受入基準3のうち、Claude の変更のブランチがある組で PR を作らないことは、テストの「Claude の変更のブランチがある組で PR を作らない」で確かめる
  - _要件: 1.1, 4.3_
  - _対象の部品: frontend-vuln-fix.sh と backend-vuln-fix.sh の変更_
  - _依存: 2.1_

- [x] 3.4 backend-vuln-fix が PR を作れなかった組を vuln-fix の結果のファイルに書き、確認に使う関数を外から呼べるようにする (並行可)

  Claude は、`backend-vuln-fix.sh` と `backend-vuln-fix.yaml` とそのテストの今の版を置き場所に写し、設計の「frontend-vuln-fix.sh と backend-vuln-fix.sh の変更」の節のとおりに直す。スクリプトは、`run` の4か所と `go_run` の4か所で vuln-fix の結果のファイルに1行を足し、`run` が main の依存を解決できずに止まるときは計画したすべての組を書く。スクリプトは、Claude の変更のブランチがある組では PR を作らない。Claude は、スクリプトの関数 `tree` `vulncheck` `go_bump` `digest` を、引数で呼べるようにする。ワークフローは、vuln-fix の結果のファイルを成果物 `vuln-fix-unresolved-java` と `vuln-fix-unresolved-go` として上げる。
  - 完了の確かめ方: Linux のコンテナで流した `test-backend-vuln-fix.sh` の場合が、前からある場合も含めてすべて通る。actionlint が、置き場所の `backend-vuln-fix.yaml` に指摘を出さない
  - 受入基準とテストの対応: 次の3つである
    - 要件1の受入基準1のうち、Java 版の部品と、Go 版の部品と標準ライブラリの消えずに残った組を書き残すことは、テストの「run の4か所と go_run の4か所でそれぞれ結果のファイルに1行が足される」「main の依存を解決できないときに計画したすべての組を書く」「Go の標準ライブラリの組を1行にまとめる」で確かめる
    - 要件4の受入基準3(同じ対象の Claude の変更の PR が開いていれば、Claude を動かさず、新しい PR も Issue も作らない)は、テストの「Claude の変更のブランチがある組で PR を作らない」で確かめる
    - 外から呼ぶ4つの関数は、テストの「tree vulncheck go_bump digest を引数で呼べる」で確かめる
  - _要件: 1.1, 4.3_
  - _対象の部品: frontend-vuln-fix.sh と backend-vuln-fix.sh の変更_
  - _依存: 2.1_

- [x] 3.5 CI の道具の版の公開からの時間を調べるスクリプトに、PR の本文を読まずに判定する形を足す (並行可)

  Claude は、`check-ci-tool-release-age.sh` とそのテストの今の版を置き場所に写し、設計の「check-ci-tool-release-age.sh の変更」の節のとおりに、環境変数 `COOLDOWN_MODE=predict` の形を足す。Claude は、テストに場合を足す。
  - 完了の確かめ方: Linux のコンテナで流した `test-check-ci-tool-release-age.sh` の場合が、前からある場合も含めてすべて通る
  - 受入基準とテストの対応: 要件2の受入基準9のうち、Claude の変更の PR を dependency-cooldown がどちらに扱うかを、CI の道具の版についても PR の検査と同じ結果になるように判定することは、テストの「predict で PR_NUMBER が無くても2で終わらず PR の API を呼ばない」「predict では PR の本文に記録の目印の行があっても72時間経っていない CI の版で1になる」「COOLDOWN_MODE が無いときに今の場合の結果が変わらない」で確かめる
  - _要件: 2.9_
  - _対象の部品: check-ci-tool-release-age.sh の変更_

- [ ] 4. 1つの対象を直して PR にするまでの各段のスクリプトを作る
- [x] 4.1 Claude に渡す指示の文と、材料を集めるスクリプトを作る (並行可)

  Claude は、置き場所に、設計の「prompt.md」の部品の節の7つのことを書いた指示の文 `prompt.md` と、設計の「claude-auto-fix-materials.sh」の部品の節のとおりに材料を集めるスクリプトと、そのテスト `test-claude-auto-fix-materials.sh` を作る。種類が `container` のとき、スクリプトは、環境変数 `TRIVY_RESULTS_DIR` のフォルダから、設計の「claude-auto-fix-target.yaml」の部品の節の prepare ジョブの項に書いた `trivy-java.json` と `trivy-go.json` を読む。テストは、偽の `gh` で、github-actions[bot]、dependabot[bot]、この仕組みの bot、ほかの利用者が書いた Issue と PR とコメントを返し、`TRIVY_RESULTS_DIR` のフォルダに偽の Trivy の結果を置く。
  - 完了の確かめ方: Linux のコンテナで流した `test-claude-auto-fix-materials.sh` の場合が、すべて通る。`prompt.md` に、設計の7つのことがすべて書いてある
  - 受入基準とテストの対応: 次の2つである
    - 要件3の受入基準5(材料を限り、利用者が書いたものを渡さない)は、テストの「利用者が書いたコメントと Issue が材料に入らない」「7つの種類ごとに設計の材料だけが区切りの行の中に入る」「種類が dependabot のとき5つの検査の名前と記録を渡さない」「実行の記録を検査ごとに末尾の400行に切り詰める」「種類が container のとき TRIVY_RESULTS_DIR の偽の Trivy の結果のうちその脆弱性の ID の行だけが材料に入る」で確かめる。指示の文に材料の指示に従わないことを書くことは、テストの「prompt.md に材料の指示に従わないことが書いてある」で確かめる
    - 要件5の受入基準1のうち CodeQL の警告の中身を外に出さないことは、テストの「種類が codeql のとき材料を標準出力に出さない」で確かめる
  - _要件: 3.5, 5.1_
  - _対象の部品: prompt.md, claude-auto-fix-materials.sh_
  - _依存: 2.1_

- [x] 4.2 Claude を動かし、結果を見分け、変更を差分に書き出すスクリプトを作る (並行可)

  Claude は、置き場所に、設計の「claude-auto-fix-run-claude.sh」の部品の節と、本物の CLI の結果を確かめたタスク 1.2 の結果のとおりに、Claude を動かすスクリプトと、そのテスト `test-claude-auto-fix-run-claude.sh` を作る。テストは、偽の `claude` で CLI を置き換え、指示の文のファイルのパスを環境変数で渡す。指示の文を作るタスク 4.1 を待たずにこのタスクを進められるようにするためである。
  - 完了の確かめ方: Linux のコンテナで流した `test-claude-auto-fix-run-claude.sh` の場合が、すべて通る
  - 受入基準とテストの対応: 次の4つである
    - 要件3の受入基準3(Claude に GitHub の中身を変える権限を渡さない)は、テストの「CLI に渡す引数に --tools Read,Edit,Write,Glob,Grep と --strict-mcp-config がある」「CLI の環境に GitHub のトークンが無い」「設定のファイルに blockReadsOutsideWorkingDirectories と blockWritesOutsideWorkingDirectories が true で書かれる」で確かめる
    - 要件3の受入基準5のうち、Claude に渡すものを指示の文と材料に限ることは、テストの「CLI の標準入力に指示の文と材料のファイルをつないだ文だけが渡る」で確かめる
    - 要件6の受入基準3(鍵が無いか切れたとき)は、テストの「鍵が空なら Claude を呼ばずに key になる」「Failed to authenticate で始まる結果で key になる」で確かめる
    - 要件6の受入基準1(上限、時間切れ、Claude の側の障害)は、テストの「You've hit your で始まる結果で unavailable になる」「error_during_execution で unavailable になる」「読めない JSON で unavailable になる」「30分で打ち切ると unavailable になる」で確かめる。あわせて、Claude は、テストの「error_max_turns で unfixed になる」「変更が空なら unfixed になる」「差分に sk-ant- の文字列があれば差分を捨てて unfixed になる」「会話の記録と結果の JSON の本文を標準出力に出さない」を作る
  - _要件: 3.3, 3.5, 6.1, 6.3_
  - _対象の部品: claude-auto-fix-run-claude.sh_
  - _依存: 1.2_

- [x] 4.3 対象を読み直し、作業の起点のコードを作るスクリプトを作る (並行可)

  Claude は、置き場所に、設計の「claude-auto-fix-prepare.sh」の部品の節のとおりに、対象を読み直すスクリプトと、そのテスト `test-claude-auto-fix-prepare.sh` を作る。種類が `container` のとき、スクリプトは、環境変数 `TRIVY_RESULTS_DIR` のフォルダから、設計の「claude-auto-fix-target.yaml」の部品の節の prepare ジョブの項に書いた `trivy-java.json` と `trivy-go.json` を読む。テストは、偽の `gh` と偽の Trivy の結果を使い、一時のフォルダの Git のリポジトリで起点のコードを作る。
  - 完了の確かめ方: Linux のコンテナで流した `test-claude-auto-fix-prepare.sh` の場合が、すべて通る
  - 受入基準とテストの対応: 次の5つである
    - 要件4の受入基準3(同じ対象の Claude の変更の PR が開いていれば、Claude を動かさない)と受入基準4(直せなかったことの知らせがある対象では、4つのきっかけで Claude を動かさない)は、テストの「同じ key の Claude の変更の PR が開いていれば skipped になる」「reason が trigger で状態が unfixed の知らせの Issue があれば skipped になる」「reason が manual なら unfixed の Issue があっても止まらない」で確かめる
    - 要件2の受入基準6のうち実行の時点で対象が消えていることは、テストの「対象が消えていれば gone になる」で確かめる
    - 要件2の受入基準8(main から作ったイメージに脆弱性が無ければ PR を作らず、ラベル container-vuln の Issue にコメントを付ける)は、テストの「種類が container で、TRIVY_RESULTS_DIR の偽の Trivy の結果に脆弱性の ID が無ければ gone になり、コメントを書くことを結果に残す」で確かめる
    - 要件1の受入基準4のうち、実行の時点で赤が5つの検査のどれかだけになった PR で Claude を動かさないことは、テストの「赤の検査が5つの検査のどれかだけになった PR で skipped になる」「止まった PR の一覧に無い PR で skipped になる」「5つのほかの赤が残る PR では残った赤の検査の名前が checks に出る」で確かめる
    - 起点のコードは、テストの「red-check では PR の head が起点になる」「dependabot では Dependabot の PR の head をマージしたコードが起点になる」「そのほかでは main が起点になる」「base.patch が dependabot のときだけ空でない」で確かめる
  - _要件: 1.4, 2.6, 2.8, 4.3, 4.4_
  - _対象の部品: claude-auto-fix-prepare.sh_
  - _依存: 2.2, 3.1_

- [x] 4.4 確認のスクリプトの `apply` の形で、派生のファイルを作り直してガードを呼び、最後の差分を書き出す (並行可)

  Claude は、置き場所に、設計の「claude-auto-fix-verify.sh」の部品の節の `apply` の形を持つ確認のスクリプトと、そのテスト `test-claude-auto-fix-verify.sh` を作る。`apply` の形は、起点のコードに Claude の変更の差分を当て、手順1で、npm の公開日時の判定、pnpm、Go の部品、Go の標準ライブラリ、Dockerfile の digest の順に、派生のファイルを作り直す。派生のファイルとは、Claude が直接書かず、Claude が変えたファイルからコマンドで作り直すファイルである。digest は、コンテナのイメージの中身から計算した SHA-256 の値である。Dockerfile の FROM の行にイメージの名前に続けて `@sha256:` と digest を書くと、その中身のイメージだけが使われる。pnpm が72時間の待ちで止まったことは、タスク 1.3 で確かめたエラーの文で見分ける。`apply` の形は、手順2でガードを呼び、通れば、最後の差分を `final.patch` に書き、変わった領域の名前を `areas` に、最後の差分の SHA-256 を `sha256` に出す。領域の見分けは、ci.yaml の `detect-changes` ジョブと同じにする。`apply` の形は、`base.patch` が変えたパスと最後の差分が変えたパスを並べ、`target/.github/ci-tool-versions.json` とともに `cooldown_needed` に渡して、dependency-cooldown の判定が要るかを `cooldown` に出す。テストは、偽の `pnpm` `go` と、偽の `frontend-vuln-fix.sh` `backend-vuln-fix.sh` を使う。
  - 完了の確かめ方: Linux のコンテナで流した `test-claude-auto-fix-verify.sh` の場合が、すべて通る。`apply` の形を呼ぶと、標準出力に、`outcome` か、`areas` と `sha256` と `cooldown` が出る
  - 受入基準とテストの対応: 次の3つである
    - 要件2の受入基準9(公開から72時間経っていない版に変える変更を、dependency-cooldown の扱いで分ける)は、テストの「種類が npm で decide が wait を返せば blocked になる」「decide が exclude を返せば exclude が呼ばれて除外の欄に足される」「偽の pnpm が72時間の待ちのエラーを返せば blocked になる」「base.patch か最後の差分が依存の版を宣言するファイルを変えたとき cooldown=true を出す」「ふつうのコードだけを変えたとき cooldown=false を出す」で確かめる
    - 要件2の受入基準2のうち派生のファイルを作り直してから確かめることは、テストの「Dockerfile の FROM の行を digest の無いタグに変えたとき偽の digest の値で @sha256: が足される」「go-stdlib で go_bump が呼ばれる」「領域の見分けが ci.yaml の detect-changes ジョブの filters と同じである」「apply が最後の差分を final.patch に書き、変わった領域を areas に、SHA-256 を sha256 に出す」で確かめる
    - 要件3の受入基準1と受入基準2のうち、派生のファイルを作り直したあとの差にもガードを掛けることは、テストの「ガードが0以外のとき unfixed になる」で確かめる
  - _要件: 2.2, 2.9, 3.1, 3.2_
  - _対象の部品: claude-auto-fix-verify.sh_
  - _依存: 1.3, 2.3, 2.4, 3.3, 3.4_

- [x] 4.5 確認のスクリプトに、変えた領域の品質チェックを流す `check` の形と、対象が消えたかを確かめる `confirm` の形を足す

  Claude は、置き場所の確認のスクリプトに、設計の「claude-auto-fix-verify.sh」の部品の節の 手順3の `check` の形と、手順4の `confirm` の形を足し、その場合を `test-claude-auto-fix-verify.sh` に足す。`check` の形は、`final.patch` から変わった領域を決め直し、その領域の品質チェックだけを流して、`outcome` に `ok` か `unfixed` を出す。`confirm` の形は、種類が `codeql` のとき、環境変数 `CODEQL_SARIF_DIR` の SARIF と、設計の verify ジョブの項に書いた警告のファイル `$RUNNER_TEMP/codeql-alert.json` を読み、SARIF の結果のパスの先頭の `target/` を外してから、警告のファイルに書かれた規則の ID とファイルと比べる。SARIF は、CodeQL などの静的解析の道具が、見つけた結果を書く JSON の形式である。テストは、偽の品質チェックのコマンドと、偽の `vulnerable` `tree` `vulncheck` `go_plan` の結果と、偽の SARIF を使う。
  - 完了の確かめ方: Linux のコンテナで流した `test-claude-auto-fix-verify.sh` の場合が、すべて通る
  - 受入基準とテストの対応: 次の3つである
    - 要件2の受入基準2のうち品質チェックに通ることは、テストの「check が apply と同じ領域を決め直し、その領域の品質チェックだけを流す」「5つの領域ごとに設計の品質チェックが呼ばれ、e2e-smoke は呼ばれない」「品質チェックが失敗か打ち切りなら unfixed になる」で確かめる
    - 要件2の受入基準2のうち対象が残らないことは、テストの「npm maven go-stdlib go-module ごとに、偽の結果が対象が残ることを返せば unfixed、消えたことを返せば ok になる」で確かめる
    - 要件5の受入基準2(CodeQL の警告を直す PR は、警告が消えて品質チェックに通ると確かめたときだけ作る)は、テストの「confirm が CODEQL_SARIF_DIR の偽の SARIF を読み、警告と同じ規則の ID の結果が同じファイルにあれば unfixed、無ければ ok になる」「SARIF の結果のパスが target/ で始まるときも同じファイルとみなして unfixed になる」「種類が codeql のとき品質チェックと CodeQL の出力を標準出力に出さない」で確かめる
  - _要件: 2.2, 5.2_

- [x] 4.6 確かめた差分をコミットして push し、PR を作るスクリプトを作る (並行可)

  Claude は、置き場所に、設計の「claude-auto-fix-ship.sh」の部品の節のとおりに、PR を作るスクリプトと、そのテスト `test-claude-auto-fix-ship.sh` を作る。テストは、偽の `gh` と、一時のフォルダの Git のリポジトリと、push 先の裸のリポジトリを使う。裸のリポジトリとは、作業のファイルを持たず、push を受けるだけの Git のリポジトリである。
  - 完了の確かめ方: Linux のコンテナで流した `test-claude-auto-fix-ship.sh` の場合が、すべて通る
  - 受入基準とテストの対応: 次の5つである
    - 要件3の受入基準1と受入基準2のうち push の前にガードをもう一度掛けることは、テストの「final.patch に .github/ のファイルの変更があれば push せずに unfixed になる」「final.patch に足した @SuppressWarnings の行があれば push せずに unfixed になる」「種類が dependabot で base.patch が .github/workflows/ を変え final.patch が変えないときはガードを通って push される」で確かめる
    - 要件3の受入基準3(Claude に GitHub の中身を変える権限を渡さない)と受入基準4(Dependabot の PR を閉じず、Dependabot へのコマンドを打たず、止まった原因を直した変更を別の PR にする)は、テストの「gh pr merge と auto-merge の予約と main への push と Dependabot の PR を閉じる操作を呼ばない」「警告を却下する API と @dependabot を含むコメントを呼ばない」「種類が dependabot で Dependabot の PR とは別の PR を作り、本文に Dependabot の PR の URL を書く」で確かめる
    - 要件5の受入基準1(CodeQL の警告を直す PR と知らせの Issue を、決まった文と警告の URL で書く)は、テストの「種類が codeql の題名と本文とコミットのメッセージが決まった文と警告の URL だけになる」「どの種類でも Claude が書いた文が題名と本文とコミットのメッセージに入らない」で確かめる
    - 要件2の受入基準4(Claude の変更の PR の必須の検査が赤になったら、Claude が直した変更を PR に足す)は、テストの「red-check で赤の検査ごとに Claude-Auto-Fix-Check の行を書く」「red-check でブランチの head が起点と違えば push せずに skipped になる」で確かめる
    - 要件2の受入基準1と受入基準3のうち PR の形は、テストの「差分の SHA-256 が違えば push しない」「新しい PR は main に base.patch と final.patch を当てた1つのコミットで、ラベル claude-auto-fix が付く」で確かめる
  - _要件: 2.1, 2.3, 2.4, 3.1, 3.2, 3.3, 3.4, 5.1_
  - _対象の部品: claude-auto-fix-ship.sh_
  - _依存: 2.1, 2.3_

- [x] 4.7 実行の結果と、直せなかったときの Issue とコメントと、鍵の Issue を書くスクリプトを作る (並行可)

  Claude は、置き場所に、結果を書くスクリプトと、そのテスト `test-claude-auto-fix-report.sh` を作る。このスクリプトは、設計の「claude-auto-fix-report.sh」の部品の節の `record` と `notify` の2つの形を持つ。
  - `record` の形: `record` の形は、結果を `$RUNNER_TEMP/outcome/outcome.json` に書き、標準出力に `result=` を出し、Issue の API を呼ばない。`record` の形は、GITHUB_STEP_SUMMARY に、実行の結果を1行書く。種類が `codeql` の行には、警告の番号と結果だけを書く。
  - `notify` の形: `notify` の形は、鍵の Issue の扱い、結果が `pr` と `unfixed` と `key` のときの扱い、種類が `codeql` のときの題名と本文の書き方を行い、結果のファイルを書かない。`notify` の形は、環境変数 `EDIT_OUTCOME` で、鍵の Issue を閉じるかを決める。鍵の Issue の本文のリンクは、設計の「claude-auto-fix-report.sh」の部品の節の `key` の項に書いた基盤構築手順の見出し `## Claude を動かす鍵の取り替え` を指す。種類が `codeql` で `reason` が `red-check` の `unfixed` の知らせは、同じ節の種類が `codeql` の項のとおりに、決まった文と警告の URL と PR の URL だけで書く。
  - 2つの形に共通のこと: どちらの形も、PR を閉じず、ブランチを消さない。スクリプトは、`lib-ledger-issue.sh` で Issue を探し、起票し、所有者に割り当てる。
  - テスト: テストは、偽の `gh` を使う。
  - 完了の確かめ方: Linux のコンテナで流した `test-claude-auto-fix-report.sh` の場合が、すべて通る
  - 受入基準とテストの対応: 次の9つである
    - 2つの形の分担は、テストの「record が決めた結果を結果のファイルに書き Issue の API を呼ばない」「notify が結果のファイルを書かない」で確かめる
    - 要件5の受入基準1のうち実行の記録に警告の中身を残さないことは、テストの「record が GITHUB_STEP_SUMMARY に1行を書き、種類が codeql では警告の番号と結果だけを書く」で確かめる
    - 要件4の受入基準1(直せなかったものごとに、対象の URL を書いた Issue を起票する)は、テストの「unfixed で知らせの Issue を起票し、対象の URL を書く」「種類が dependabot の知らせの Issue に Dependabot の PR の URL を書く」で確かめる
    - 要件4の受入基準2(ラベル container-vuln の Issue の脆弱性を直せなかったら、その Issue にコメントを付ける)は、テストの「種類が container の unfixed でラベル container-vuln の Issue にコメントを書き、新しい Issue を起票しない」で確かめる
    - 要件4の受入基準4のうち手で動かしてまた直せなかったときは、テストの「同じ key の知らせの Issue が開いていればコメントを付け、新しい Issue を起票しない」で確かめる
    - 要件2の受入基準5(同じ必須の検査が3回続けて赤になったら PR を閉じ、閉じた PR の URL を知らせに書く)は、テストの「sweep から閉じた PR の URL を渡されたら知らせに書く」「reason が red-check の unfixed で、PR を閉じる API とブランチを消す API を呼ばず、知らせに PR の URL を書く」で確かめる
    - 要件5の受入基準1(CodeQL の警告を直す PR と知らせの Issue を、決まった文と警告の URL で書く)は、テストの「種類が codeql の Issue の題名と本文とコメントに、決まった文と警告の URL と、unfixed の項のとおりに書く PR の URL のほかの中身が入らない」「種類が codeql で reason が red-check の unfixed で、知らせに PR の URL が書かれる」で確かめる
    - 要件6の受入基準3(鍵が無いか切れたら、鍵の取り替えを求める Issue を1つだけ起票し、動けたら閉じる)は、テストの「key で鍵の Issue が1つだけになる」「鍵の Issue の本文のリンクが基盤構築手順の見出し『Claude を動かす鍵の取り替え』を指す」「edit ジョブが ok を出して結果が blocked の実行でも鍵の Issue が閉じられる」で確かめる
    - 要件6の受入基準2(3日続けて動けなかった知らせの Issue が開いていても Claude を動かし、PR ができたら閉じる)は、テストの「pr で状態が unavailable の知らせの Issue が閉じられる」「状態が unavailable の知らせの Issue が開いているときの unfixed で、新しい Issue を起票せず、その Issue にコメントが付き、最も新しい目印の状態が unfixed になる」で確かめる
  - _要件: 2.5, 4.1, 4.2, 4.4, 5.1, 6.2, 6.3_
  - _対象の部品: claude-auto-fix-report.sh_
  - _依存: 2.1, 2.2_

- [ ] 4.8 動けなかったことが3日続いたときと、main で消えていたときと、ジョブが結果を出さずに止まったときの扱いを足す

  Claude は、置き場所の結果を書くスクリプトの `notify` の形に、設計の「claude-auto-fix-report.sh」の部品の節の `unavailable` と `blocked` と `gone` の扱いを足す。Claude は、`record` の形に、設計の「claude-auto-fix-target.yaml」の部品の節の「失敗したとき」の表のとおりに、止まったジョブから結果を決める扱いを足す。Claude は、その場合を `test-claude-auto-fix-report.sh` に足す。`record` の形は、結果の引数が空で、環境変数 `JOB_RESULTS` に `failure` か `cancelled` のジョブがあるときに、設計の「失敗したとき」の表で結果を決める。`JOB_RESULTS` は、needs の各ジョブの result を入れた JSON である。
  - 完了の確かめ方: Linux のコンテナで流した `test-claude-auto-fix-report.sh` の場合が、すべて通る
  - 受入基準とテストの対応: 次の4つである
    - 要件6の受入基準1(鍵のほかの理由で動けなかったら次の日に動かし直し、3日続いたら Issue を起票する)は、テストの「3つの違う日の unavailable で知らせの Issue が1つだけ起票され、動けなかった理由が書かれる」「同じ日の3回の unavailable では起票しない」「blocked も3日に数える」で確かめる
    - 要件6の受入基準2(3日続けて動けなかった知らせの Issue が開いていても Claude を動かす)は、テストの「unavailable の知らせの Issue が開いていれば何もしない」で確かめる
    - 要件2の受入基準8(main から作ったイメージに脆弱性が無ければ PR を作らず、ラベル container-vuln の Issue にコメントを付ける)は、テストの「gone でラベル container-vuln の Issue に main では消えていることを書いたコメントが1回だけ付く」で確かめる
    - 要件2の受入基準2のうち確かめられないときに直せなかったものとして扱うことは、テストの「prepare edit cooldown の4つのジョブ ship で止まれば unavailable、verify と verify-image で止まれば unfixed になる」で確かめる
  - _要件: 2.2, 2.8, 6.1, 6.2_

- [ ] 5. 対象を見つけて実行を起こすスクリプトと、後始末のスクリプトを作る
- [ ] 5.1 4つのきっかけで対象を集め、絞り込みの決まりで絞って実行を起動するスクリプトを作る (並行可)

  Claude は、置き場所に、設計の「claude-auto-fix-dispatch.sh」の部品の節のうち、`trigger` の4つの集め方と絞り込みの決まりを行う振り分けのスクリプトと、そのテスト `test-claude-auto-fix-dispatch.sh` を作る。振り分けのスクリプトは、止まった Dependabot の PR を、一覧を書き出す形を足したタスク 3.1 の `STUCK_JSON_OUT` で読む。振り分けのスクリプトは、vuln-fix の組を、frontend-vuln-fix と backend-vuln-fix が PR を作れなかった組を書くタスク 3.3 と 3.4 の vuln-fix の結果のファイルの形で読む。テストは、偽の `gh` で、成果物と API の応答と `gh workflow run` を置き換える。
  - 完了の確かめ方: Linux のコンテナで流した `test-claude-auto-fix-dispatch.sh` の場合が、すべて通る
  - 受入基準とテストの対応: 次の6つである
    - 要件1の受入基準1(frontend-vuln-fix と backend-vuln-fix が警告を消せなかった組ごとに Claude を動かす)は、テストの「vuln-fix の成果物の組ごとに1つの実行が起動される」「Go の標準ライブラリの組が1つの実行になる」「vuln-fix のワークフローの結論が failure でなければ起動しない」で確かめる
    - 要件1の受入基準2(main に開いたままの CodeQL の警告ごとに Claude を動かす)は、テストの「main に開いたままの CodeQL の警告ごとに1つの実行が起動される」で確かめる
    - 要件1の受入基準3(ラベル container-vuln の Issue の脆弱性で Claude を動かし、修正版が無ければ動かさない)は、テストの「修正版のあるコンテナの Issue で起動される」「修正版の無いコンテナの Issue では起動されず何も書かない」「1度扱ったコンテナの Issue では起動されない」で確かめる
    - 要件1の受入基準4(止まった Dependabot の PR ごとに Claude を動かし、5つの検査のどれかだけが赤の PR では動かさない)は、テストの「赤の検査が dependency-review だけの PR が外れる」「記録のコメントの無い dependency-cooldown だけの PR が外れる」「dependency-review と escape-hatch の2つの PR が外れる」「frontend-test と escape-hatch が赤の PR は起動され、入力 checks が frontend-test だけになる」で確かめる
    - 要件1の受入基準6(決めたきっかけのほかでは Claude を動かさず、利用者が書いたものをきっかけにしない)は、テストの「利用者が書いた Issue とコメントの中身を対象を選ぶ材料にしない」で確かめる
    - 要件4の受入基準3(同じ対象の Claude の変更の PR が開いていれば、Claude を動かさない)と受入基準4(直せなかったことの知らせがある対象では、4つのきっかけで Claude を動かさない)は、テストの「開いている Claude の変更の PR がある key では起動されない」「同じ組の vuln-fix のブランチがあれば起動されない」「unfixed の知らせの Issue がある key では trigger で起動されない」「直せなかったことを書いたコメントが付いたコンテナの Issue では trigger で起動されない」「unavailable の知らせの Issue があっても起動される」「その日の実行がある表示名では起動されない」で確かめる
  - _要件: 1.1, 1.2, 1.3, 1.4, 1.6, 4.3, 4.4_
  - _対象の部品: claude-auto-fix-dispatch.sh_
  - _依存: 2.2, 3.1, 3.3, 3.4_

- [ ] 5.2 所有者の手での起動と、1時間ごとの動かし直しを、振り分けのスクリプトに足す

  Claude は、置き場所の振り分けのスクリプトに、設計の「claude-auto-fix-dispatch.sh」の部品の節の `manual` と `retry` の集め方と、鍵の Issue が開いているときの決まりを足し、その場合を `test-claude-auto-fix-dispatch.sh` に足す。
  - 完了の確かめ方: Linux のコンテナで流した `test-claude-auto-fix-dispatch.sh` の場合が、すべて通る。同じ偽の応答で振り分けのスクリプトを2回呼んでも、起動される実行が増えない
  - 受入基準とテストの対応: 次の5つである
    - 要件1の受入基準5(所有者が手で動かすと、残っている対象のすべてで Claude を動かす)は、テストの「manual で4つの集め方をすべて使う」「manual でまだ脆弱な vuln-fix の組だけを残す」「manual で unfixed の Issue があっても起動される」「manual でも5つの検査だけが赤の PR が外れる」で確かめる
    - 要件6の受入基準1(鍵のほかの理由で動けなかったら次の日に動かし直す)と受入基準2(3日続けて動けなかった知らせの Issue が開いていても Claude を動かす)は、テストの「前の日に unavailable か blocked で終わった対象が retry で起動される」「今日すでに実行がある対象は retry で起動されない」「取り消されて結果のファイルが無い実行を unavailable と数えて入力を作る」で確かめる
    - 要件6の受入基準3(鍵が無いか切れたら、鍵の取り替えを求める Issue を1つだけ起票し、動けたら閉じる)は、テストの「鍵の Issue が開いている間は1日に1つだけ起動される」「鍵の Issue が開いていて key の対象が直近4日に無いとき4つの集め方から1つだけ起動される」で確かめる
    - 要件6の受入基準4(鍵を取り替えたら、鍵が切れて動けなかった対象を次の日までに動かし直す)は、テストの「4日より前に key で終わった対象が、鍵の Issue が閉じてから25時間のうちの retry で起動される」「25時間を過ぎた retry では集め直さない」「集め直しで unfixed の Issue がある key と1度扱ったコンテナの Issue が起動されない」で確かめる
    - 要件1の受入基準6のうち次の日の動かし直しは、ここまでの retry の場合で確かめる
  - _要件: 1.5, 1.6, 6.1, 6.2, 6.3, 6.4_

- [ ] 5.3 Claude の変更の PR の赤と、対象の消えた PR と Issue を扱う後始末のスクリプトを作る (並行可)

  Claude は、置き場所に、設計の「claude-auto-fix-sweep.sh」の部品の節の5つの扱いを行う後始末のスクリプトと、そのテスト `test-claude-auto-fix-sweep.sh` を作る。後始末のスクリプトは、直せなかったことの知らせを、結果を書くスクリプトを `notify unfixed` の形で呼んで書き、閉じた PR の URL を渡し、`EDIT_OUTCOME` を渡さない。後始末のスクリプトは、`record` の形を呼ばない。テストは、偽の `gh` を使う。
  - 完了の確かめ方: Linux のコンテナで流した `test-claude-auto-fix-sweep.sh` の場合が、すべて通る。同じ偽の応答で後始末のスクリプトを2回呼んでも、PR と Issue の操作が増えない
  - 受入基準とテストの対応: 次の6つである
    - 要件2の受入基準4(Claude の変更の PR の必須の検査が赤になったら、4つの検査のほかの赤で Claude を動かす)は、テストの「必須の検査の赤で reason=red-check の実行を起動し、赤の検査の名前を渡す」「approval_gated の検査の赤では起動されない」「必須の検査がまだ動いているときは何もしない」「同じ head のコミットについての対象ごとの実行があるときは何もしない」で確かめる。最後の場合は、red-check の実行が unfixed で終わって開いたまま残った PR で、head が変わらない間は Claude を動かし直さないことも確かめる
    - 要件2の受入基準5(同じ必須の検査が3回続けて赤になったら PR を閉じ、閉じた PR の URL を知らせに書く)は、テストの「同じ検査の赤が3回続いたら PR を閉じてブランチを消し、閉じた PR の URL を渡して notify unfixed を呼ぶ」「notify を呼ぶときに EDIT_OUTCOME を渡さず、record を呼ばない」で確かめる
    - 要件2の受入基準6(マージの前に対象が消えたら PR を閉じる)は、テストの「対象が消えた PR に消えたことを書いたコメントを付けて閉じる」で確かめる
    - 要件2の受入基準7(ラベル container-vuln の Issue の PR がマージされたら、リリースのあとに本番で消えることを書いたコメントを付ける)は、テストの「マージされたコンテナの PR のコメントが1回だけ付く」で確かめる
    - 要件4の受入基準5(知らせの Issue の対象が消えたら、コメントを付けて閉じる)は、テストの「対象が消えた知らせの Issue に消えたことを書いたコメントを付けて閉じる」「対象が残る知らせの Issue を閉じない」で確かめる
    - 要件6の受入基準2のうち、状態が unavailable の Issue も対象が消えたら閉じることは、テストの「状態が unavailable の知らせの Issue も対象が消えたら閉じる」で確かめる
  - _要件: 2.4, 2.5, 2.6, 2.7, 4.5, 6.2_
  - _対象の部品: claude-auto-fix-sweep.sh_
  - _依存: 2.2, 4.7_

- [ ] 6. 2つのワークフローを作り、スクリプトをつなぐ
- [ ] 6.1 2つのワークフローのジョブの権限と秘密の値と順番を確かめるテストを作る

  Claude は、置き場所に、設計の「テストの方針」の `test-claude-auto-fix-workflows.sh` の項のとおりに、対象ごとのワークフロー `claude-auto-fix-target.yaml` と振り分けのワークフロー `claude-auto-fix.yaml` の YAML を `yq` で読むテストを作る。このテストは、ワークフローを作るタスク 6.2、6.3、6.4 の完了を確かめる道具なので、Claude は、ワークフローより先に、2つのワークフローの場合をすべてこのタスクで作る。Claude は、テストを、ワークフローのファイルのパスを環境変数で受け取れる形にする。Claude は、偽の YAML をテストに読ませて、テストが、設計と違う権限と秘密の値の渡し方ときっかけと環境変数の渡し方を見つけることを確かめる。
  - 完了の確かめ方: `yq` を入れた Linux のコンテナで、次の2つが起きる
    - 偽の正しい2つの YAML で、テストのすべての場合が通る
    - 次の28の偽の YAML のそれぞれで、テストが失敗する
      - 対象ごとのワークフローの edit ジョブに `contents: write` を足した YAML
      - edit ジョブに `secrets.BOT_GITHUB_TOKEN` を渡した YAML
      - cooldown-generate ジョブから `GITHUB_DEPENDENCY_GRAPH_SHA` を消した YAML
      - report ジョブに `JOB_RESULTS` を渡さない YAML
      - report ジョブの `JOB_RESULTS` から cooldown-judge ジョブの結果を消した YAML
      - edit ジョブが `TRIVY_RESULTS_DIR` を渡さない YAML
      - verify ジョブの `check` の手順を `apply` の手順より前に置いた YAML
      - verify ジョブの `confirm` の手順に、前の形が `ok` 以外の `outcome` を出したときに飛ばす `if` が無い YAML
      - verify ジョブの `confirm` の手順を、`check` が `ok` を出したときにも飛ばす `if` にした YAML
      - verify ジョブの出力 `outcome` を `apply` の手順の出力だけから取る YAML
      - 種類が `container` のとき、prepare ジョブが Trivy の結果を `trivy-java.json` と `trivy-go.json` と違う名前で書く YAML
      - 種類が `codeql` のとき、verify ジョブの最初の手順が警告のファイルを `$RUNNER_TEMP/codeql-alert.json` と違うパスに書く YAML
      - 種類が `container` のとき、verify-image ジョブから、`check-container-scan.sh` の `report` の結果に入力 `key` の脆弱性の ID があれば失敗する手順を消した YAML
      - verify ジョブの `analyze` に `checkout_path` を渡さない YAML
      - verify ジョブの `apply` の手順に GITHUB_TOKEN を渡した YAML
      - ship ジョブから、`base.patch` の SHA-256 を prepare ジョブの出力 `base_sha256` と比べる手順を消した YAML
      - verify ジョブの `target/` の checkout から `fetch-depth: 0` を消した YAML
      - report ジョブの `notify` の手順を、成果物 `outcome` を上げる手順より前に置いた YAML
      - 振り分けのワークフローに `issue_comment` のきっかけを足した YAML
      - 振り分けのワークフローに `secrets.CLAUDE_CODE_OAUTH_TOKEN` を渡した YAML
      - cooldown-judge ジョブから `check-go-release-age.sh` を呼ぶ手順を消した YAML
      - cooldown-judge ジョブが `check-ci-tool-release-age.sh` に `COOLDOWN_MODE=predict` を渡さない YAML
      - cooldown-judge ジョブの2つ目の判定の手順を、前の手順が0以外で終わったときに飛ばす形にした YAML
      - cooldown-judge ジョブの3つ目の判定の手順を、前の手順が0以外で終わったときに飛ばす形にした YAML
      - cooldown-judge ジョブから、`check-ci-tool-release-age.sh` が書いた版の配布元の署名を `install-verified-<道具>.sh` で確かめる手順を消した YAML
      - cooldown-judge ジョブが、署名を確かめた結果を、`cooldown_outcome` に渡す3つ目の終わり方に入れない YAML
      - cooldown-push ジョブの `if` を、verify ジョブの出力 `cooldown` を読まない形にした YAML
      - verify ジョブの出力 `cooldown` を、`apply` のほかの手順の出力から取る YAML
  - 受入基準とテストの対応: 次の11である
    - 要件2の受入基準2のうち、種類が `container` のときにイメージに脆弱性が残らないことを確かめる verify-image ジョブの組み立ては、テストの「種類が container のとき verify-image ジョブが、final.patch を当てたコードから2つのイメージを作って Trivy で調べ、check-container-scan.sh の report の結果に入力 key の脆弱性の ID があれば失敗する」で確かめる
    - 要件2の受入基準2と要件5の受入基準2のうち verify ジョブの組み立ては、テストの「verify ジョブの手順が、作り直しの道具、apply、変わった領域の道具、check、CodeQL の init と analyze、confirm の順に並び、前の形が ok 以外の outcome を出したときに、あとの手順が飛ばされ、ok を出したときは次の手順が動く」「verify ジョブの出力 outcome が、最後に動いた形の outcome になる」「verify ジョブの CodeQL の手順で、init に source-root: target が渡され、ビルドの手順が working-directory: target で動き、analyze に checkout_path として target/ のパスが渡される」「種類が codeql のとき GITHUB_TOKEN が verify ジョブの最初の手順にだけ渡され、checkout が persist-credentials: false である」「種類が codeql のとき verify ジョブの最初の手順が $RUNNER_TEMP/codeql-alert.json に書く」で確かめる
    - 要件2の受入基準1と受入基準3のうち、どのジョブも同じ起点のコードで動くことは、テストの「edit verify verify-image cooldown-push ship の各ジョブが、red-check では base_sha を、そのほかでは main_sha に base.patch を当てたコードを起点にし、base.patch の SHA-256 を prepare ジョブの出力 base_sha256 と比べる」「verify ジョブが target/ を fetch-depth: 0 で checkout する」で確かめる
    - 要件2の受入基準2と要件5の受入基準2と要件6の受入基準1のうち report ジョブの組み立ては、テストの「report ジョブの手順が、record、成果物 outcome を上げる手順、notify の順に並ぶ」「cleanup ジョブの権限が actions: write で、if: always() で report ジョブのあとに動く」で確かめる
    - 要件3の受入基準3(Claude に GitHub の中身を変える権限を渡さない)は、テストの「secrets.CLAUDE_CODE_OAUTH_TOKEN が対象ごとのワークフローの edit ジョブにだけ現れる」「secrets.BOT_GITHUB_TOKEN が ship ジョブにだけ現れる」「edit ジョブに書き込みの権限が無い」「振り分けのワークフローに secrets.CLAUDE_CODE_OAUTH_TOKEN が現れない」で確かめる
    - 要件2の受入基準3(Claude の変更の PR は、必須の検査と所有者の承認がそろったときにだけ自動でマージされる)は、テストの「ジョブの順番と if が設計の『ジョブごとの権限と動き』と同じである」「前のジョブが結果を出して止まったとき、あとのジョブを飛ばして report ジョブに進む」「report ジョブが EDIT_OUTCOME に edit ジョブの結果を渡す」「report ジョブの JOB_RESULTS に、cooldown の4つのジョブを含む prepare から ship までのすべてのジョブの結果が入る」で確かめる
    - 要件2の受入基準8と要件3の受入基準5のうち、Trivy の結果を受け渡すことは、テストの「種類が container のとき prepare ジョブが Trivy の結果のフォルダを TRIVY_RESULTS_DIR で prepare.sh に渡し、成果物 trivy-results を保存の期間1日で上げる」「種類が container のとき prepare ジョブが trivy-java.json と trivy-go.json を成果物 trivy-results のフォルダの最上位に書く」「種類が container のとき edit ジョブが成果物 trivy-results を受け取り、TRIVY_RESULTS_DIR で materials.sh に渡す」で確かめる
    - 要件2の受入基準9(公開から72時間経っていない版に変える変更を、dependency-cooldown の扱いで分ける)は、テストの「cooldown-generate と cooldown-submit に GITHUB_DEPENDENCY_GRAPH_SHA と GITHUB_DEPENDENCY_GRAPH_REF が渡される」「cooldown-judge が PNPM_WORKSPACE_FILE=target/frontend/pnpm-workspace.yaml を渡す」「cooldown-judge が target/ の中で check-go-release-age.sh と check-ci-tool-release-age.sh を呼び、check-dependency-cooldown.sh と check-ci-tool-release-age.sh に COOLDOWN_MODE=predict を渡し、3つの判定の手順が前の手順の終わり方によらず動き、3つの終わり方を cooldown_outcome に渡す」「cooldown-judge が check-ci-tool-release-age.sh の書いた版ごとに install-verified-<道具>.sh で配布元の署名を確かめる」「cooldown-judge が、署名を確かめられなかったときに、cooldown_outcome に渡す3つ目の終わり方を1にする」「cooldown-push の if が verify ジョブの出力 cooldown を読む」「verify ジョブの出力 cooldown が apply の手順の出力から取られる」で確かめる
    - 要件1の受入基準4のうち実行の時点の赤の検査を使うことは、テストの「種類が dependabot のとき edit ジョブが材料の checks に prepare ジョブの出力を渡す」で確かめる
    - 要件1の受入基準1から受入基準6のうちきっかけを限ることは、テストの「on に workflow_run の4つのワークフローと cron 17 * * * * と入力の無い workflow_dispatch だけがある」「vuln-fix の2つのワークフローでは結論が failure のときだけ dispatch ジョブが動く」で確かめる
    - 要件2の受入基準4から受入基準7と要件4の受入基準5と要件6の受入基準4のうち後始末と動かし直しが1時間ごとに動くことは、テストの「定期実行で dispatch ジョブと sweep ジョブが動き、手での起動では dispatch ジョブだけが動く」で確かめる
  - _要件: 1.1, 1.2, 1.3, 1.4, 1.5, 1.6, 2.1, 2.2, 2.3, 2.4, 2.5, 2.6, 2.7, 2.8, 2.9, 3.3, 3.5, 4.5, 5.2, 6.1, 6.4_

- [ ] 6.2 1つの対象を直して PR にする対象ごとのワークフローの、cooldown のジョブのほかのジョブを作る

  Claude は、置き場所に、設計の「claude-auto-fix-target.yaml」の部品の節のとおりに、ワークフロー `claude-auto-fix-target.yaml` の、prepare、edit、verify、verify-image、ship、report、cleanup の各ジョブを作る。各ジョブは、それぞれのスクリプトのテストを流してからスクリプトを呼ぶ。
  - prepare ジョブ: 種類が `container` のとき、prepare ジョブは、2つのイメージの Trivy の結果を、設計の prepare ジョブの項のとおりに `trivy-java.json` と `trivy-go.json` に書き、成果物 `trivy-results` として上げる。
  - 起点のコード: edit、verify、verify-image、ship の各ジョブは、設計の「claude-auto-fix-prepare.sh」の部品の節の「起点の作り直し」のとおりに起点のコードを作り、`base.patch` の SHA-256 が prepare ジョブの出力 `base_sha256` と違えば失敗する。
  - verify ジョブ: verify ジョブは、`target/` を `fetch-depth: 0` で checkout する。verify ジョブは、種類が `codeql` のときだけ、Claude の変更を当てる前の最初の手順で、GITHUB_TOKEN を使って警告を読み、設計の verify ジョブの項のとおりに警告のファイル `$RUNNER_TEMP/codeql-alert.json` を書く。そのあと、verify ジョブは、設計の6つの手順を順に動かし、前の形が `ok` 以外の `outcome` を出したときだけ、あとの手順を飛ばす。verify ジョブは、設計の verify の項のとおりに、最後に動いた形の `outcome` をジョブの結果として出す。6つの手順は、作り直しの道具を入れる手順、`apply`、変わった領域の道具を入れる手順、`check`、種類が `codeql` のときの CodeQL の `init` と `analyze`、`confirm` である。verify ジョブは、`apply` が出した `cooldown` も出力する。
  - verify-image ジョブ: 種類が `container` のときだけ、verify-image ジョブは、設計の verify-image の項のとおりに、`final.patch` を当てたコードから、prepare ジョブと同じランナーと組み立て方で2つのイメージを作って Trivy で調べ、`check-container-scan.sh` の `report` の結果に入力 `key` の脆弱性の ID があれば失敗する。verify-image ジョブが失敗すると、report ジョブは、設計の「失敗したとき」の表のとおりに結果を `unfixed` にする。
  - report ジョブ: report ジョブは、各ジョブの `needs.<ジョブ>.result` を `JOB_RESULTS` に入れて `record` の形を呼び、成果物 `outcome` を上げ、edit ジョブの結果を `EDIT_OUTCOME` に入れて `notify` の形を呼ぶ。
  - cleanup ジョブ: cleanup ジョブは、この実行の成果物のうち `outcome` のほかを消す。
  - actionlint の設定: Claude は、actionlint を流す前に、置き場所の `dot-github/actionlint.yaml` に今の `.github/actionlint.yaml` を写し、2つの新しいワークフローの `unknown permission scope "vulnerability-alerts"` を除く行を、dependency-review.yaml の行と同じ形で足し、先頭のコメントを設計の「ファイルの構成」の節のとおりに直す。
  - ship ジョブの順番: このタスクでは、Claude は、ship ジョブを verify ジョブと verify-image ジョブのあとに動く形にしておく。Claude は、cooldown のジョブを挟む作業を、cooldown の4つのジョブを足すタスク 6.3 で行う。
  - 完了の確かめ方: 置き場所の `claude-auto-fix-target.yaml` で、`test-claude-auto-fix-workflows.sh` の対象ごとのワークフローの場合のうち、次の9つのほかがすべて通り、actionlint が指摘を出さない。9つの場合は、cooldown のジョブを足すタスク 6.3 のあとに通る
    - 「ジョブの順番と if が設計の『ジョブごとの権限と動き』と同じである」
    - 「edit verify verify-image cooldown-push ship の各ジョブが、red-check では base_sha を、そのほかでは main_sha に base.patch を当てたコードを起点にし、base.patch の SHA-256 を prepare ジョブの出力 base_sha256 と比べる」
    - 「report ジョブの JOB_RESULTS に、cooldown の4つのジョブを含む prepare から ship までのすべてのジョブの結果が入る」
    - 「cooldown-generate と cooldown-submit に GITHUB_DEPENDENCY_GRAPH_SHA と GITHUB_DEPENDENCY_GRAPH_REF が渡される」
    - 「cooldown-judge が PNPM_WORKSPACE_FILE=target/frontend/pnpm-workspace.yaml を渡す」
    - 「cooldown-judge が target/ の中で check-go-release-age.sh と check-ci-tool-release-age.sh を呼び、check-dependency-cooldown.sh と check-ci-tool-release-age.sh に COOLDOWN_MODE=predict を渡し、3つの判定の手順が前の手順の終わり方によらず動き、3つの終わり方を cooldown_outcome に渡す」
    - 「cooldown-judge が check-ci-tool-release-age.sh の書いた版ごとに install-verified-<道具>.sh で配布元の署名を確かめる」
    - 「cooldown-judge が、署名を確かめられなかったときに、cooldown_outcome に渡す3つ目の終わり方を1にする」
    - 「cooldown-push の if が verify ジョブの出力 cooldown を読む」
  - 受入基準とテストの対応: 次の3つである
    - 要件3の受入基準3(Claude に GitHub の中身を変える権限を渡さない)と、要件2の受入基準3のうちワークフローの組み立ては、`test-claude-auto-fix-workflows.sh` の場合で確かめる
    - 要件2の受入基準1、受入基準2、受入基準8と要件5の受入基準2のうち、各ジョブがスクリプトの結果に従って次のジョブか report ジョブに進むことは、テストの「前のジョブが結果を出して止まったとき、あとのジョブを飛ばして report ジョブに進む」で確かめる
    - 実物の実行は、マージのあとに本物の実行を確かめるタスク 8.3 で確かめる
  - _要件: 2.1, 2.2, 2.3, 2.8, 3.3, 5.2_
  - _依存: 4.8_

- [ ] 6.3 1つの対象を直して PR にする対象ごとのワークフローに、cooldown の4つのジョブを足す

  Claude は、置き場所の `claude-auto-fix-target.yaml` に、設計の「claude-auto-fix-target.yaml」の部品の節の cooldown-push、cooldown-generate、cooldown-submit、cooldown-judge の4つのジョブを足し、ship ジョブを cooldown-judge ジョブのあとに動かす。cooldown-push ジョブは、verify ジョブの出力 `cooldown` が `true` のときだけ動き、タスク 6.2 のほかのジョブと同じ形で起点のコードを作り、`base.patch` の SHA-256 を確かめる。cooldown-judge ジョブは、判定の手順の前に、dependency-review の手順「Test dependency cooldown check」が流すテストと `test-lib-claude-auto-fix.sh` を流す。cooldown-judge ジョブは、設計の cooldown-judge の項のとおりに、`check-dependency-cooldown.sh` と `check-go-release-age.sh` と `check-ci-tool-release-age.sh` の3つの判定の手順を、前の手順の終わり方によらずすべて動かし、`check-ci-tool-release-age.sh` が書いた版の配布元の署名を確かめ、署名を確かめられなかったときは3つ目の判定の終わり方を1にする。cooldown-judge ジョブは、3つの終わり方を `cooldown_outcome` に渡して、ship に進むか、結果を `blocked` にするか、ジョブを失敗にするかを決める。Claude は、report ジョブの `needs` と `JOB_RESULTS` に、4つのジョブを足す。cooldown-generate ジョブと cooldown-submit ジョブへの環境変数の渡し方は、一時のブランチのコミットの Gradle のスナップショットを確かめたタスク 1.4 で確かめた渡し方にする。
  - 完了の確かめ方: 置き場所の `claude-auto-fix-target.yaml` で、`test-claude-auto-fix-workflows.sh` の対象ごとのワークフローの場合がすべて通り、actionlint が指摘を出さない
  - 受入基準とテストの対応: 次の3つである
    - 要件2の受入基準9(公開から72時間経っていない版に変える変更を、dependency-cooldown の扱いで分ける)は、テストの「cooldown-generate と cooldown-submit に GITHUB_DEPENDENCY_GRAPH_SHA と GITHUB_DEPENDENCY_GRAPH_REF が渡される」「cooldown-judge が PNPM_WORKSPACE_FILE=target/frontend/pnpm-workspace.yaml を渡す」「cooldown-judge が target/ の中で check-go-release-age.sh と check-ci-tool-release-age.sh を呼び、check-dependency-cooldown.sh と check-ci-tool-release-age.sh に COOLDOWN_MODE=predict を渡し、3つの判定の手順が前の手順の終わり方によらず動き、3つの終わり方を cooldown_outcome に渡す」「cooldown-judge が check-ci-tool-release-age.sh の書いた版ごとに install-verified-<道具>.sh で配布元の署名を確かめる」「cooldown-judge が、署名を確かめられなかったときに、cooldown_outcome に渡す3つ目の終わり方を1にする」「cooldown-push の if が verify ジョブの出力 cooldown を読む」「ジョブの順番と if が設計の『ジョブごとの権限と動き』と同じである」で確かめる
    - 要件2の受入基準3のうち、cooldown のジョブで止まったときも report ジョブが結果を決められることは、テストの「report ジョブの JOB_RESULTS に、cooldown の4つのジョブを含む prepare から ship までのすべてのジョブの結果が入る」で確かめる
    - 要件2の受入基準1と受入基準3のうち、cooldown-push ジョブもほかのジョブと同じ起点のコードで動くことは、テストの「edit verify verify-image cooldown-push ship の各ジョブが、red-check では base_sha を、そのほかでは main_sha に base.patch を当てたコードを起点にし、base.patch の SHA-256 を prepare ジョブの出力 base_sha256 と比べる」で確かめる
  - _要件: 2.1, 2.3, 2.9_
  - _依存: 1.4, 2.4, 3.2, 3.5_

- [ ] 6.4 対象を見つけて対象ごとの実行を起こす振り分けのワークフローを作る

  Claude は、置き場所に、設計の「claude-auto-fix.yaml」の部品の節のとおりに、ワークフロー `claude-auto-fix.yaml` を作る。dispatch ジョブは、`test-claude-auto-fix-workflows.sh` と、振り分けのスクリプトと共通の関数のテストを流してから、振り分けのスクリプトを呼ぶ。sweep ジョブは、後始末のスクリプトと共通の関数のテストを流してから、後始末のスクリプトを呼ぶ。
  - 完了の確かめ方: 置き場所の `claude-auto-fix.yaml` で、`test-claude-auto-fix-workflows.sh` の振り分けのワークフローの場合がすべて通り、actionlint が指摘を出さない
  - 受入基準とテストの対応: 次の3つである
    - 要件1の受入基準1から受入基準6のうちきっかけを限ることは、テストの「on に workflow_run の4つのワークフローと cron 17 * * * * と入力の無い workflow_dispatch だけがある」「vuln-fix の2つのワークフローでは結論が failure のときだけ dispatch ジョブが動く」で確かめる
    - 要件3の受入基準3のうちこのワークフローが Claude の鍵を持たないことは、テストの「振り分けのワークフローに secrets.CLAUDE_CODE_OAUTH_TOKEN が現れない」で確かめる
    - 要件2の受入基準4から受入基準7(Claude の変更の PR の赤と、対象が消えたときと、マージされたときの扱い)と要件4の受入基準5(知らせの Issue の対象が消えたら閉じる)と要件6の受入基準4(鍵を取り替えたあとの動かし直し)は、テストの「定期実行で dispatch ジョブと sweep ジョブが動き、手での起動では dispatch ジョブだけが動く」で確かめる
  - _要件: 1.1, 1.2, 1.3, 1.4, 1.5, 1.6, 2.4, 2.5, 2.6, 2.7, 3.3, 4.5, 6.4_
  - _依存: 5.2, 5.3_

- [ ] 6.5 ラベル、版の書き場所の一覧、棚卸しの対象、README に新しいワークフローを載せる

  Claude は、`labels.json` と `ci-tool-versions.json` と `inventory-targets.json` の今の版を置き場所に写し、設計の「ファイルの構成」の節のとおりに、ラベル `claude-auto-fix` と、新しいワークフローとアクションの版の行を載せる。版の行には、2つのワークフローが使う Node.js の版と Trivy の版の行を含める。Claude は、README のワークフローの一覧の表に2つの行を足し、Mermaid の図の PR の節に作り手を足す。このタスクで流す検査は2つのワークフローのファイルを読むので、Claude は、このタスクを、2つのワークフローを作り終えてから行う。
  - 完了の確かめ方: 次の3つが起きる
    - 置き場所の `labels.json` を読む今あるラベルのテストが通る
    - リポジトリの写しに置き場所のファイルを重ねて流した `check-ci-tool-placement.sh` が、新しいワークフローとアクションの版の行について指摘を出さずに0で終わる
    - README の表と図に2つのワークフローが載っている
  - 受入基準とテストの対応: 要件4の受入基準3のうち Claude の変更の PR をラベルで見分けることは、共通の関数を足したタスク 2.2 のテストで確かめ、このタスクではラベルが `labels.json` にあることを `jq` で確かめる
  - _要件: 4.3_
  - _依存: 6.3, 6.4_

- [ ] 7. 基盤構築手順に、Claude を動かす鍵の登録と取り替えの手順を書く (並行可)

  Claude は、設計の「基盤構築手順と PR の本文の変更」の部品の節のとおりに、`doc/開発フロー/基盤構築手順.md` の 3-1 の Actions secrets の表に Secret `CLAUDE_CODE_OAUTH_TOKEN` の行を足し、bot の PAT の復旧の節と同じ形で、鍵を作り直して登録し直す節を、設計の同じ節に書いた見出し `## Claude を動かす鍵の取り替え` で足す。PAT は、GitHub の個人用のアクセストークンである。
  - 完了の確かめ方: 次の5つが起きる
    - 表の行に、値の作り方と、鍵が無いときや切れたときに Claude の変更の PR が作られなくなり、仕組みが鍵を取り替えるよう求める Issue を起票することが書いてある
    - 鍵を作り直す節のコマンドが `claude setup-token` と `gh secret set CLAUDE_CODE_OAUTH_TOKEN --repo <owner>/<repo>` で、Windows・macOS・Linux で同じに打てる形である
    - 初めて鍵を登録する1回きりの手順が手順書に無い
    - 鍵を作り直す節の見出しが、設計に書いた見出しと1文字も違わない
    - 結果を書くスクリプトの鍵の Issue の本文は、タスク 4.7 のテストで同じ見出しを指すことを確かめるので、2つのタスクはどちらを先に進めてもよい
  - 受入基準とテストの対応: 要件7の受入基準1(基盤構築手順の秘密の値の一覧に、鍵と鍵の作り方を書く)と受入基準2(鍵を作り直して登録し直す手順を基盤構築手順に書く)は、このタスクの完了の確かめ方で、手順書の表と節を読んで確かめる
  - _要件: 7.1, 7.2_
  - _対象の部品: 基盤構築手順と PR の本文の変更_

- [ ] 8. 所有者が置いたファイルで全体を確かめ、出荷し、マージのあとに本物の実行を確かめる
- [ ] 8.1 所有者にファイルを置いてもらい、置いた場所ですべてのテストと検査を流す

  Claude は、置き場所の `dot-github/` のファイルを本来の場所に写すコマンドを1つ所有者に示し、そのコマンドでファイルを置くよう所有者に頼む。依頼には、Claude が `.github/` に書けないことを添える。所有者が置いたら、Claude は、置いたファイルが置き場所のファイルと同じかを `cmp` で確かめ、本来の場所で、この spec で作るか変えた `.github/scripts/tests/` のテストのすべてと、shellcheck と、actionlint と、版の書き場所の検査を流す。
  - 完了の確かめ方: 次の6つが起きる
    - 所有者が置いたファイルが、置き場所のファイルとすべて同じである
    - Linux のコンテナで流した、この spec で作るか変えたテストが、すべて通る
    - shellcheck と actionlint の指摘が0件である
    - 本来の場所で流した `check-ci-tool-placement.sh` が指摘を出さずに0で終わる
    - `.github/CLAUDE.md` の「CI で動くスクリプトを手元で確かめる」のとおり、ランナーと同じ arm64 の CPU の形で流した verify-image ジョブの判定の手順が、入力 `key` の脆弱性の ID を含む Trivy の結果では0以外で終わり、含まない結果では0で終わる
    - 同じ arm64 の CPU の形で流した prepare ジョブの Trivy を呼ぶ処理が、`trivy-java.json` と `trivy-go.json` を書く
  - 受入基準とテストの対応: ほかの受入基準は、各タスクの受入基準とテストの対応のとおりである。このタスクでは、それらのテストを、所有者が置いた本来の場所でまとめて流し直す
  - _要件: 1.1, 1.2, 1.3, 1.4, 1.5, 1.6, 2.1, 2.2, 2.3, 2.4, 2.5, 2.6, 2.7, 2.8, 2.9, 3.1, 3.2, 3.3, 3.4, 3.5, 4.1, 4.2, 4.3, 4.4, 4.5, 5.1, 5.2, 6.1, 6.2, 6.3, 6.4_

- [ ] 8.2 実装の PR の本文に、鍵の初めての登録と、マージのあとの確認の手順を書いて出荷する

  Claude は、`/ship` で実装の PR を作る。Claude は、PR の本文の「マージのあとにすること」に、今のリポジトリに初めて鍵を登録する手順と、設計の「テストの方針」の「マージのあとの確認」の手順を書く。この PR は `.github/` を変えるので、所有者が承認するまでマージされない。
  - 完了の確かめ方: 次の3つが起きる
    - 実装の PR の本文に、`Spec: .kiro/specs/claude-auto-fix-unresolved-alerts` と `Refs: #725` と、「マージのあとにすること」の2つの手順が書いてある
    - 初めて鍵を登録する手順は、所有者が `claude setup-token` で作った鍵を `gh secret set CLAUDE_CODE_OAUTH_TOKEN` で登録し、成功したときに `gh secret list` に名前が出ることまで書いてある
    - 実装の PR の必須の検査のうち、所有者の承認を待つ検査のほかが緑である
  - 受入基準とテストの対応: 要件7の受入基準3(この仕組みを入れる PR の本文に、初めて鍵を登録する手順を書く)は、このタスクの完了の確かめ方で PR の本文を読んで確かめる。要件2の受入基準3のうち、この仕組みを入れる PR 自身も必須の検査と所有者の承認を通ることは、実装の PR の検査の結果で確かめる
  - _要件: 2.3, 7.3_

- [ ] 8.3 マージと鍵の登録のあとに、本物の実行を1回動かして確かめる

  Claude は、実装の PR がマージされ、所有者が鍵を登録したあとに、設計の「テストの方針」の「マージのあとの確認」のとおりに、`claude-auto-fix-target.yaml` を開いている対象の1つで手で起動する。Claude は、実行の結果の成果物の `outcome` と、PR ができたときはその PR の作り手が bot であることと auto-merge の予約と、ジョブごとの権限が実行の記録のとおりであることを読み、読んだ結果を Issue #725 にコメントで書く。開いている対象が1つも無いときは、Claude は、起動せずに、対象が無いことを所有者に報告し、このタスクを未完了のまま残す。次に対象が出たときに、Claude はこのタスクを進める。
  - 完了の確かめ方: 次の3つが起きる
    - Issue #725 に、実行の URL と、成果物の `outcome` の結果と、ジョブごとの権限を読んだ結果を書いたコメントがある
    - 結果が `pr` のときは、その PR の作り手が bot で、auto-merge の予約が付いていることも書いてある
    - 結果が設計と違うときは、Claude は、違いを所有者に報告して止まる
  - 受入基準とテストの対応: 要件2の受入基準3と要件3の受入基準3のうち、本物の鍵と bot の PAT での権限の分け方は、この実行の記録で確かめる
  - _要件: 2.3, 3.3_

## 完了条件(全タスク共通)

Claude は、どのタスクでも、タスクの箇条書きの欄を書いたうえで、次の4つを満たしたときにタスクを完了とする。

1. Claude は、タスクが満たす requirements.md の受入基準(要件の番号付きの項目)ごとに、それを確かめるテストのファイル名とテスト名を「受入基準とテストの対応」の行に書く。Claude は、確かめるテストの無い受入基準を残さない。
2. タスクで変えたファイルを使うテストが、すべて成功している。`1.` や `2.` の見出しのタスクを大きなまとまりと呼ぶ。大きなまとまりの最後のタスクでは、加えて、そのまとまりのタスクで変えた領域の verify のスキル(`/verify-frontend` `/verify-backend` `/verify-terraform`)が、すべて成功している。
3. Claude は、テストを飛ばす設定、アサーションの削除、カバレッジや lint の対象からの除外を足して、完了条件を満たしたように見せない。CI の escape-hatch の検査が、これらの追加を機械で見つける。
4. Claude は、新しく書いたテストについて、テストの対象のコードを一時的に壊してテストが失敗することを確かめる。Claude は、新しいテスト1件につき1か所だけを、作業フォルダの外の写しで壊し、そのテストだけを流す。壊した写しの作り方と流し方は、`.kiro/steering/tech.md` の「テストの完全性」に従う。

## 実装のメモ

- 置き場所: Claude は、design.md の「プロジェクトの決まりを守っているか」の節のとおりに、`.github/` のファイルを `.claude/.state/claude-auto-fix-unresolved-alerts/` の下に作る。Claude は、その下の `place-1/` を置き場所にする。このフォルダは `.gitignore` の `.claude/.state/` に当たるので、コミットされない
- Claude は、`.github/` の下に置くファイルを、置き場所の `dot-github/` に、`.github/` と同じ並びで作る。`settings.json` の `deny` の `.github/**` が、置き場所の中の `.github/` にも当たるためである。今あるファイルを変えるときは、Claude は、今の版を Read で読み、Write で置き場所に写してから変える
- `README.md` と `doc/` の下の文書と `.kiro/specs/` の下の research.md は、Claude が本来の場所に書く
- テストを流す環境: `.github/scripts/` のテストは `jq` を使い、この PC の Git Bash には `jq` が無い。そのため、この spec の `.github/scripts/tests/` のテストでは、`/kiro-impl` が言う「実装する PC のシェル」を、Git Bash ではなく Linux のコンテナとする。Claude は、テストを、`.github/CLAUDE.md` の形の alpine のコンテナで流す。Claude は、`.github/CLAUDE.md` の `apk add` の `bash` `jq` `coreutils` に、`git` `curl` `gnupg` を足して入れる。テストが GitHub Actions の環境変数で動きを変えるかを確かめるときは、Claude は、`.github/CLAUDE.md` の、GitHub Actions の環境変数を渡す形で流す。ワークフローのテストと、ci.yaml の `detect-changes` ジョブを読む確認のスクリプトのテストのときは、`yq` も入れる。Claude は、リポジトリの写しを scratchpad に作り、置き場所のファイルを重ねてから、その写しをコンテナに読ませる。ただし、タスク 1.1 で本物の配布元から CLI を入れて版を確かめる手順は、glibc を使う Linux のコンテナで流す
- 静的解析の道具: actionlint は、guardrails.yaml と同じ `rhysd/actionlint:1.7.12` のイメージで流す。shellcheck は、`.github/CLAUDE.md` と同じ `koalaman/shellcheck:v0.11.0` のイメージで流す
- この spec は `frontend/` `backend/` `terraform/` を変えないので、大きなまとまりの最後のタスクで流す verify のスキルは無い。代わりに、Claude は、シェルのスクリプトを作るか変えたタスクごとに、`.github/CLAUDE.md` のとおり、置き場所とリポジトリの写しの中のすべての `.sh` を一度に shellcheck に渡し、指摘が0件であることをタスクの完了の確かめ方に加える。変えたファイルだけを渡すと、shellcheck が `. "$LIB"` で読み込む先のファイルをたどらず、CI だけが警告を出すためである。
- 実物での確認のために Claude が所有者に頼むことは、本物の鍵が要る CLI の確認のタスク 1.2 のコマンド、Gradle のスナップショットの確認のタスク 1.4 の push、ファイルを置くタスク 8.1 のコマンドの3つである。Claude は、1回の返事に依頼を1つだけ書く
- 所有者に push を頼むとき: このリポジトリへの push は、bot のアカウント DogisRiki-bot の gh の設定でしか通らない。所有者の個人のアカウントでは 403 で断られた(タスク 1.4 の確認のブランチの push)。Claude は、所有者に push か GitHub の操作を頼むコマンドの先頭で、`$env:GH_CONFIG_DIR = "$env:USERPROFILE\.gh-bot"` を設定する(タスク 8.1 のコマンドも同じ)
- `lib-claude-auto-fix.sh` の目印の関数(タスク 2.1): `marker_line` と `latest_marker` は `<欄>=<値>` の形の目印だけを扱う。PR の本文の `<!-- claude-auto-fix-detail <base64 の JSON> -->` は値だけの形なので、PR を作るタスクで別に書いて読む。`latest_marker` は `created_at` が同じ項目を渡された順で並べるので、呼び出す側は Issue の本文を先に、コメントをその後ろに並べて渡す
- ガードの種類の渡し方(タスク 2.3): `claude-auto-fix-guard.sh <base> <head>` は、対象の種類を環境変数 `CAF_KIND` で受け取る。`CAF_KIND` が無いか知らない種類のときは、ガードは調べずに失敗する。種類が `codeql` のときに見つけた行を出さないことを、呼び出す側が種類を渡し忘れても破らないためである。確認のスクリプトの `apply` の形と出荷のスクリプトは、ガードを呼ぶときに `CAF_KIND` を渡し、今のフォルダを調べるリポジトリの最上位にする
- Go の版を書くファイルの見分け方(タスク 2.4): `go_release_is_target` は、名前が `Dockerfile.<何か>` のファイルをすべて Go の版を書くファイルとみなす。`Dockerfile.md` のような説明のファイルも当たるので、`cooldown_needed` は、そのファイルだけを変えた変更でも dependency-cooldown の判定が要るとする。テストで「判定が要らない」場合のファイルに、この形の名前を使わない
- dependency-cooldown の判定の予測の形(タスク 3.2): `COOLDOWN_MODE=predict` の `check-dependency-cooldown.sh` は、PR の番号を求めず、72時間経っていない版が無ければ0、判定の4つをすべて通れば3、止める版があるか判定できなければ1で終わる。`COOLDOWN_MODE` が空か predict のほかの値なら、何も読まずに1で終わる。`test-check-dependency-cooldown.sh` を Linux のコンテナで流すときは、bash と jq のほかに openssl と gzip と perl が要る(来歴の証明書を作るのと、署名した者を比べるため)
- vuln-fix の PR を作る処理のテスト(タスク 3.3): `test-frontend-vuln-fix.sh` は、偽の gh・git・curl・pnpm を PATH の先頭に置き、環境変数で成功と失敗を選んで `run` を流す。偽の git は `ls-remote` の5つ目の引数をブランチ名として読む。backend の同じテストを足すときも、この形にそろえる
- origin のブランチの有無の確かめ(タスク 3.4): `git ls-remote --exit-code` は、ブランチが無いときに 2 で終わる。ほかの失敗を 2 で返す関数の中で使うときは、ブランチが無いときを 1 などの別の値に直してから返す
- 材料を集めるスクリプト(タスク 4.1): `claude-auto-fix-materials.sh` は、材料を `$RUNNER_TEMP/claude-auto-fix-materials.txt` に書き、標準出力に `materials=<場所>` の1行だけを書く。`red-check` の PR は、作り手が環境変数 `CAF_SHIP_LOGIN`(既定は DogisRiki-bot)のときだけ読む。edit ジョブを書くタスクでは、この環境変数をワークフローに明示する。期待一覧は `CAF_REQUIRED_CHECKS` で替えられる
- Claude を動かすスクリプト(タスク 4.2): `claude-auto-fix-run-claude.sh` は、作業のフォルダの index と作業のフォルダの違いを Claude の変更として書き出し、追っていない新しいファイルは intent-to-add で差分に入れる。そのため、edit ジョブは、起点のコードの差分 `base.patch` を `git apply --index` で当てる(またはコミットする)ことを、このスクリプトを呼ぶ前に行う。指示の文は環境変数 `CAF_PROMPT`、作業のフォルダは `CAF_TARGET_DIR`(既定は `target`)で替えられる
- 対象を読み直すスクリプト(タスク 4.3): `claude-auto-fix-prepare.sh` は、`$RUNNER_TEMP/claude-auto-fix-base.patch` を書き、続けるときは `main_sha` `base_sha` `base_sha256` `base_patch` を出し、止めるときは `outcome` と `cause` の2行だけを出す。origin から main と `refs/pull/<番号>/head` を取り込むので、prepare ジョブは fetch-depth: 0 で checkout する。止める理由は claude-pr-open、pr-not-open、unfixed-issue、not-stuck、no-fixable-check、head-moved、merge-conflict、target-gone、gone-on-main で、gone-on-main のときに report ジョブがラベル `container-vuln` の Issue にコメントを書く
- red-check と種類 dependabot の組(タスク 4.3): reason が red-check のときは、種類が dependabot でも起点は Claude の変更の PR の head で、base.patch は空にし、`checks` を出さない。design.md の prepare ジョブの項と prepare.sh の節の呼び出し方は「種類が dependabot なら checks を出す」と書くが、red-check の赤の検査は Claude の変更の PR のものなので、ワークフローのタスクでは、種類が dependabot で reason が red-check でないときだけ prepare の出力の `checks` を使い、red-check では入力の `checks` を使う
- 設計と要件の食い違い(タスク 4.3、PR の本文に書いて所有者に決めてもらう): design.md の prepare.sh の節の止める決まりは「reason が manual でなく、知らせの Issue の状態が unfixed なら skipped」と書くが、実装は reason が trigger か retry のときだけ止める。要件4の4が止めるのは要件1の1から4の4つのきっかけだけで、要件2の4は Claude の変更の PR の赤で Claude を動かすと決めているためである。設計の文のとおりにすると、unfixed の Issue が開いたまま所有者が手で動かして作った PR が赤になったときに、Claude がその赤を直せない
- 確認のスクリプトの apply の形(タスク 4.4): `claude-auto-fix-verify.sh apply` は、ガードと vuln-fix のスクリプトを作業のフォルダではなく自分と同じフォルダから呼ぶ。`base.patch` のファイルは必須で、空なら起点のコードに変更が無いものとして扱う。種類が codeql のときは説明の文を `$RUNNER_TEMP/claude-auto-fix-verify.log` に書く。領域の見分けは配列 `CAF_AREA_FILTERS` に ci.yaml の filters を写してあり、テストの filters の場合が ci.yaml と食い違えば落ちるので、ci.yaml の filters を変えるときは配列も直す。名前を変えた差分の元のパスは `git apply --numstat` では取れないので、一時の index に `base.patch` を逆に当てて取る
- 設計の文との食い違い(タスク 4.4、PR の本文に書く): design.md の verify.sh の節の pnpm のコマンドは `pnpm install --lockfile-only --no-frozen-lockfile --ignore-scripts` だが、実装は `--ignore-pnpmfile` を足した。`--ignore-scripts` だけでは Claude が書いた `.pnpmfile.cjs` が apply の中で読み込まれて動き、同じ節の「Claude が変えたコードは apply の出力を書き換えられない」が成り立たないためである(pnpm の docs/cli/install.md)。リポジトリに pnpmfile は無いので、今の動きは変わらない
- 確認のスクリプトの check と confirm の形(タスク 4.5): `check` と `confirm` は、起点のコミットに `final.patch` を当てた木を一時の index で作り、動かす前に作業のフォルダをその木に戻す。追跡するファイルは `read-tree -u --reset` で戻し、追跡しないファイルと無視するファイルは `clean -ffdxq` で消す。`check` は終わりにももう一度戻す。品質チェックやビルドが作業のフォルダのファイルを変えても、CodeQL と `confirm` が PR にする木を診断するためである。そのため、verify ジョブは、ログインのトークンや道具や SARIF を `target/` の外に置く
- reason の渡し方(タスク 4.5): `confirm` は、対象ごとの実行の reason を環境変数 `CAF_REASON` で受け取り、`red-check` のときは対象を調べずに `ok` を出す。5つの引数の形には reason の欄が無いためである。verify ジョブを書くタスクでは、`confirm` を呼ぶ手順に `CAF_REASON` を渡す。渡し忘れたときは対象を調べるので、Claude の変更の PR の赤を直した実行が `unfixed` で止まる
- Dockerfile の組み立て(タスク 4.5): `check` は、ci.yaml の docker-smoke と同じ文脈で `docker build` を流すが、terraform の Dockerfile に `github_token` の secret を渡さない。verify ジョブは秘密の値を持たないためである。terraform の Dockerfile の secret の mount は必須ではないので組み立ては進むが、ログインしない問い合わせの回数の上限に当たると tflint の準備が失敗し、`unfixed` になることがある
- frontend の対象の確かめ(タスク 4.5): `frontend-vuln-fix.sh vulnerable` は、lockfile が無いときも「範囲に入る版が無い」と同じ1で終わる。そのため、`confirm` は、`frontend/pnpm-lock.yaml` が無いときを `unfixed` にする
- ship の起点の main(タスク 4.6): `claude-auto-fix-ship.sh` は、新しい PR のコミットの親にする main のコミットを、環境変数 `CAF_MAIN_SHA` で受け取る。9つの引数の形に main_sha の欄が無いためである。red-check のとき以外は必須で、起点のコミットの祖先でなければ失敗する。ワークフローのタスク 6.2 は、prepare ジョブの出力の `main_sha` を ship の手順に `CAF_MAIN_SHA` として渡す
- detail の目印の読み方(タスク 4.6): ship は、`<!-- claude-auto-fix-detail … -->` の目印を、detail が空でないとき(種類が npm・maven・go のとき)だけ本文に書く。dispatch で本文から detail を読む関数(タスク 5.x)は、目印が無ければ detail を空として扱い、行の始めから始まる最初の目印だけを読む。本文の後ろの変えたファイルの一覧には、Claude が作ったファイルの名前が入るためである
- ship ジョブの checkout(タスク 4.6): ship ジョブが `target/` を取り出す `actions/checkout` には `persist-credentials: false` を付ける。既定のままだと GITHUB_TOKEN が http.extraheader に残り、`gh auth setup-git` の資格情報より先に使われて、push が bot の PAT にならないためである
- 知らせの Issue の起票(タスク 4.7): `claude-auto-fix-report.sh` は、知らせの Issue と鍵の Issue を、`lib-ledger-issue.sh` の `ledger_find_or_create` を使わずに、`gh issue create` で起票し、`ledger_assign_owner` で所有者を担当者にする。`ledger_find_or_create` は、閉じた Issue でも題名が同じなら使い続けるため、「開いていなければ起票する」決まりを守れないからである。コメントは `ledger_comment` と `lib-notice-comment.sh` の `notice_post` で付ける。タスクの本文と design の「lib-ledger-issue.sh で探し、起票し」との食い違いとして、PR の本文に書く
- report の起点のコミット(タスク 4.7): `claude-auto-fix-report.sh record` は、結果のファイルの `head_sha` を、環境変数 `CAF_HEAD_SHA`(40桁の16進)から読む。10の引数の形に欄が無いためである。無ければ null を書く。ワークフローのタスク 6.2 は、prepare ジョブの出力の起点のコミットを report の手順に `CAF_HEAD_SHA` として渡す
- Issue の一覧の渡し方(タスク 4.7): 開いている Issue の一覧とコメントの一覧は、jq に引数(`--argjson`)で渡さず、標準入力かファイル(`--slurpfile`)で渡す。Linux の1つの引数の長さの上限は 128KiB で、知らせの Issue が20件ほど開くと超えるためである
