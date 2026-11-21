# design のレビュー記録

## サイクル1 往復1(2026-11-14)

### 審査の範囲

範囲: 全体

### 実ファイルで確かめた文

- 部品 frontend-vuln-fix.sh と backend-vuln-fix.sh の変更「frontend は7か所で failed=1 にする」: .github/scripts/frontend-vuln-fix.sh 142, 146, 150, 153, 155-156, 166, 168行 / 合っていた
- 同「backend の run は4か所、go_run は組を扱う4か所、組を読む前に止まる2か所、main の依存を解決できずに止まる箇所がある」: .github/scripts/backend-vuln-fix.sh 105, 117, 122, 131, 133, 210, 215, 228, 229, 241, 242行 / 合っていた
- 使う既存の仕組み「backend-vuln-fix.sh の tree、vulncheck、go_bump は今は外から呼べない」: .github/scripts/backend-vuln-fix.sh 246-248行(呼べるのは run、go_run、plan、resolved、vulnerable、decide、pin、go_plan) / 合っていた
- 使う既存の仕組み「frontend-vuln-fix.sh の vulnerable と frontend_test は外から呼べる」: .github/scripts/frontend-vuln-fix.sh 106行、173-176行 / 合っていた
- 部品 claude-auto-fix-verify.sh「go_bump は go.mod の toolchain と4つの Dockerfile の golang のイメージを上げる」: .github/scripts/backend-vuln-fix.sh 139行、161-176行 / 合っていた
- データの形「今の vuln-fix のブランチ名は chore/ で始まる」: .github/scripts/frontend-vuln-fix.sh 136行 / 合っていた
- 部品 claude-auto-fix-sweep.sh「approval_gated が true の検査は escape-hatch、dependency-gate、pre-merge-check、dependency-cooldown の4つ」: .github/audit/required-checks.json 6, 18, 19, 24行 / 合っていた
- 部品 claude-auto-fix-guard.sh「check-escape-hatches.sh は base と head を引数に取り、PR_BODY と OWNER_APPROVED を読み、ゲートの設定のファイルの変更を見つける。Go のアサーションの削除は見ない」: .github/scripts/check-escape-hatches.sh 41-52行、201-203行、217行 / 合っていた
- 部品 check-audit-dependabot-stuck.sh の変更「今は止まった PR の一覧を JSON で書き出さない」: .github/scripts/check-audit-dependabot-stuck.sh 3-18行、150行、194-235行 / 合っていた
- 部品 check-dependency-cooldown.sh の変更「今は PR_NUMBER を求め、流れの1から4が警告との照合、悪意のある部品の一覧、署名した者、pnpm の除外の欄の判定である」: .github/scripts/check-dependency-cooldown.sh 40-41行、47-54行、66行、103-104行 / 合っていた
- 部品 claude-auto-fix-verify.sh「領域の見分けは ci.yaml の detect-changes ジョブの filters と、backend_go と backend_compat を決める手順にある」: .github/workflows/ci.yaml 55-90行、100-127行 / 合っていた
- 同「backend_java は ./gradlew check --configuration-cache」: .github/workflows/ci.yaml 370行 / 合っていた
- 同「backend_go は go-version-file の Go と golangci-lint-action v9.3.0(golangci-lint v2.15.0)で make check と make mutation-diff」: .github/workflows/ci.yaml 432-472行 / 合っていた
- 同「backend_compat は make compat と make compat-cross」: .github/workflows/ci.yaml 474-509行 / 合っていた(ただし同じ箇所が求める `KEIREKIPRO_REPO_ROOT` と poppler-utils が design に無い。D1-1-8)
- 同「docker-smoke は Dockerfile ごとに文脈を分けて docker build する」: .github/workflows/ci.yaml 553-598行 / 合っていた
- 部品 claude-auto-fix-target.yaml cooldown-push「main のほかへの push で動くワークフローもない」: .github/workflows/ の push のきっかけ(ci.yaml 8-9行ほか。どれも branches が main) / 合っていた
- 同 verify「codeql.yaml の analyze は upload: never で動き、languages.tsv にビルドのしかたがある」: .github/workflows/codeql.yaml 64-119行、.github/codeql/languages.tsv 23行、39-44行 / 合っていた
- 部品 claude-auto-fix.yaml「対象のワークフローの名前は Frontend Transitive Vulnerability Fix、Backend Vulnerability Fix、Audit Weekly、Scheduled Container Image Vulnerability Scan」: .github/workflows/frontend-vuln-fix.yaml、backend-vuln-fix.yaml、audit-weekly.yaml、container-scan-scheduled.yaml の name の行 / 合っていた
- 全体の構成「Trivy は 0.76.2、container-scan ジョブは ubuntu-24.04-arm で docker buildx build --platform linux/arm64、文脈は ./backend、2つの Dockerfile.prod」: .github/workflows/container-scan-scheduled.yaml 99行、.github/workflows/container-scan.yaml 153-159行、220-232行 / 合っていた
- 部品 claude-auto-fix-target.yaml verify-image「check-container-scan.sh の report で判定する」: .github/workflows/container-scan-scheduled.yaml 180-186行 / 合っていた
- 部品 claude-auto-fix-dispatch.sh「ラベル container-vuln の Issue は github-actions[bot] が起票し、container-scan-state の目印の行に fixed がある」: .github/scripts/container-scan-issue.sh 63行、66-70行、156-162行 / 合っていた
- 設計を見直すきっかけ・データの形「ラベル container-vuln がある(group other)」: .github/labels.json 88-92行 / 合っていた
- 部品 claude-auto-fix-target.yaml cooldown-generate と cooldown-submit「dependency-review.yaml は generate と submit を分け、productionRuntimeClasspath と detachedConfiguration の除外を渡す。cooldown は vulnerability-alerts: read を持つ」: .github/workflows/dependency-review.yaml 42-111行、171-174行 / 合っていた
- 部品 claude-auto-fix-ship.sh「auto-merge.yaml は bot の PAT の PR に予約を付ける」: .github/workflows/auto-merge.yaml 89-92行 / 合っていた
- 部品 claude-auto-fix-report.sh と sweep「lib-ledger-issue.sh で探し、起票し、割り当てる。lib-notice-comment.sh の notice_post で1回だけ付ける」: .github/scripts/lib-ledger-issue.sh(ledger_find_or_create、ledger_comment、ledger_assign_owner)、.github/scripts/lib-notice-comment.sh(notice_post、notice_last_kind) / 合っていた
- 作らないもの「ci-tool-version-update が上げる道具は Node.js、Trivy、Codex CLI、Terraform の4つ」: .github/ci-tool-versions.json の tools、.github/audit/inventory-targets.json 40-55行、82-86行、150行 / 合っていた
- 部品 基盤構築手順の変更「3-1 の Actions secrets の表と、bot の PAT の復旧の節がある」: doc/開発フロー/基盤構築手順.md 69-76行、313行 / 合っていた
- ファイルの構成「README にワークフローの一覧の表と Mermaid の図がある」: README.md 55行、124-125行 / 合っていた
- prompt.md「Dockerfile はイメージの digest を固定している」: docker/backend/Dockerfile.prod 4行、28行、docker/backend-go/Dockerfile.prod 11行、41行 / 合っていた(ただし digest を作り直す手順が go-stdlib のほかに無い。D1-1-5)
- prompt.md・要件2.9「今の frontend-vuln-fix は修正版の公開日時を読んで除外の欄に足すかを決める」: .github/scripts/frontend-vuln-fix.sh 87-93行、141-143行(公開日時は registry.npmjs.org から読む) / 合っていた(ただし Claude に公開日時を渡す道が無い。D1-1-6)
- プロジェクトの決まり「依存グラフの差分比較の API は今あるワークフローが使っている」: .github/scripts/check-dependency-cooldown.sh 103-104行 / 今ある使い方は PR のコミットの比較だけである。PR の無いブランチでの動きは research.md 225行が「文書に無い」と書く(D1-1-1)
- 性能「2026年8月から11月13日までの container-vuln の Issue の起票は月に1件から74件、vuln-fix の直近100回に失敗は無い」: 審査役が実行できるコマンドは `gh issue view` だけのため、確かめられなかった

### 受入基準ごとの確かめ方

| 受入基準 | 確かめる道具 | 動かす場所 | 動かすのに要るもの | design の箇所 |
|---|---|---|---|---|
| 1.1 | test-claude-auto-fix-dispatch.sh、test-frontend-vuln-fix.sh、test-backend-vuln-fix.sh | コンテナ(alpine に bash と jq) | 偽の gh、成果物の組の JSON | テストの方針 単体テストと結合テスト |
| 1.2 | test-claude-auto-fix-dispatch.sh | コンテナ | 偽の gh(CodeQL の警告の一覧) | テストの方針 結合テスト(番号の範囲だけ。場合の名前は無い) |
| 1.3 | test-claude-auto-fix-dispatch.sh(修正版の無い Issue では起動されず何も書かない) | コンテナ | 偽の gh(container-scan-state の目印つきの Issue) | テストの方針 結合テスト |
| 1.4 | test-claude-auto-fix-dispatch.sh、test-check-audit-dependabot-stuck.sh | コンテナ | 偽の gh、STUCK_JSON_OUT | テストの方針 単体テストと結合テスト |
| 1.5 | test-claude-auto-fix-dispatch.sh(manual の場合) | コンテナ | 偽の gh | テストの方針 結合テスト |
| 1.6 | test-claude-auto-fix-dispatch.sh。ワークフローのきっかけ(on:)の確かめ | コンテナ。ワークフローは main に入ったあとの実行 | 偽の gh | スクリプトはテストの方針。ワークフローは無い(D1-1-9) |
| 2.1 | test-lib-claude-auto-fix.sh | コンテナ | なし | テストの方針 単体テスト |
| 2.2 | test-claude-auto-fix-verify.sh | コンテナ | ci.yaml(filters を読んで比べる)、偽の docker | テストの方針 結合テスト。実際の品質チェックを動かすのに要るものは一部が無い(D1-1-8) |
| 2.3 | Claude の変更の PR に必須の検査と auto-merge の予約が付くことの確かめ | main に入ったあとの実行 | CLAUDE_CODE_OAUTH_TOKEN、BOT_GITHUB_TOKEN、対象の警告 | 無い(D1-1-9) |
| 2.4 | test-claude-auto-fix-sweep.sh、test-claude-auto-fix-ship.sh | コンテナ | 偽の gh、偽の git push | テストの方針 結合テスト |
| 2.5 | test-claude-auto-fix-sweep.sh | コンテナ | 偽の gh(末尾の行つきのコミット) | テストの方針 結合テスト |
| 2.6 | test-claude-auto-fix-sweep.sh。prepare の gone は test-claude-auto-fix-prepare.sh | コンテナ | 偽の gh | sweep はテストの方針。prepare の場合は無い(D1-1-10) |
| 2.7 | test-claude-auto-fix-sweep.sh | コンテナ | 偽の gh | テストの方針 結合テスト |
| 2.8 | test-claude-auto-fix-prepare.sh、test-claude-auto-fix-report.sh | コンテナ | 偽の gh、Trivy の結果の JSON | 無い(D1-1-10)。テストの方針に prepare の項が無く、report の項に gone の場合が無い |
| 2.9 | test-check-dependency-cooldown.sh(predict の場合)。cooldown の4つのジョブの確かめ | コンテナ。ジョブは main に入ったあとの実行 | 偽の gh。実行では一時のブランチと依存グラフの差分比較の API | 単体はテストの方針。ジョブと API は無い(D1-1-1、D1-1-9) |
| 3.1 | test-claude-auto-fix-guard.sh | コンテナ | git のリポジトリ(2つのコミット) | テストの方針 単体テスト |
| 3.2 | test-claude-auto-fix-guard.sh | コンテナ | 同上 | テストの方針 単体テスト |
| 3.3 | test-claude-auto-fix-run-claude.sh(引数と環境)。ジョブごとの権限と、CLI が実際に Bash を拒むことの確かめ | コンテナ。権限と CLI は実物での実行 | 偽の claude。実物では CLI 2.1.323 と鍵 | 引数はテストの方針。権限と実物の CLI は無い(D1-1-2、D1-1-9) |
| 3.4 | test-claude-auto-fix-ship.sh | コンテナ | 偽の gh | テストの方針 結合テスト(dependabot の別の PR の場合は書かれていない) |
| 3.5 | test-claude-auto-fix-materials.sh | コンテナ | 偽の gh | テストの方針 単体テスト |
| 4.1 | test-claude-auto-fix-report.sh | コンテナ | 偽の gh | テストの方針 結合テスト |
| 4.2 | test-claude-auto-fix-report.sh | コンテナ | 偽の gh | テストの方針 結合テスト(番号だけ。場合の名前は無い) |
| 4.3 | test-claude-auto-fix-dispatch.sh、test-lib-claude-auto-fix.sh、test-frontend-vuln-fix.sh、test-backend-vuln-fix.sh | コンテナ | 偽の gh | テストの方針。prepare の場合は無い(D1-1-10) |
| 4.4 | test-claude-auto-fix-dispatch.sh | コンテナ | 偽の gh | テストの方針。prepare の場合は無い(D1-1-10) |
| 4.5 | test-claude-auto-fix-sweep.sh | コンテナ | 偽の gh | テストの方針 結合テスト |
| 5.1 | test-claude-auto-fix-ship.sh、test-claude-auto-fix-report.sh | コンテナ | 偽の gh | テストの方針 結合テスト |
| 5.2 | test-claude-auto-fix-verify.sh。CodeQL の init と analyze は実行での確かめ | コンテナ。CodeQL は main に入ったあとの実行 | 警告の言語、規則の ID、ファイル | 言語と規則の ID とファイルを verify に渡す道が無い(D1-1-3) |
| 6.1 | test-claude-auto-fix-report.sh、test-claude-auto-fix-dispatch.sh、test-claude-auto-fix-run-claude.sh | コンテナ | 偽の gh(直近4日の結果のファイル)、偽の claude | テストの方針 |
| 6.2 | test-claude-auto-fix-report.sh | コンテナ | 偽の gh | テストの方針 結合テスト |
| 6.3 | test-claude-auto-fix-report.sh、test-claude-auto-fix-run-claude.sh | コンテナ | 偽の gh、偽の claude | テストの方針 |
| 6.4 | test-claude-auto-fix-dispatch.sh | コンテナ | 偽の gh | テストの方針 結合テスト(鍵の Issue が閉じたあとにすべて選ぶ場合は書かれていない。D1-1-7) |
| 7.1 | 基盤構築手順を読んで確かめる | 手元 | なし | 無い(D1-1-11) |
| 7.2 | 基盤構築手順を読んで確かめる | 手元 | なし | 無い(D1-1-11) |
| 7.3 | PR の本文を読んで確かめる | 手元 | なし | 無い(D1-1-11) |

### 申告

**1. Claude を1回の実行で1回だけ動かし、確認に落ちた変更は直し直さずに「直せなかった」にする** — design.md 処理の流れ「流れの上の決めごと」

- Issue の記載: なし(「Claude が直し方を考え、警告を消す PR を作る」「Claude も警告を消せなかったときは Issue を起票する」だけ)
- 決めたこと: 仕組みは、品質チェックや対象の確認に落ちた結果を Claude に渡さない。Claude は Bash を持たないので、自分でテストも流せない。1回で通らなければ Issue になる
- 他にありえた選択肢: 確認に落ちた出力を材料に足して、同じ実行の中で Claude を数回動かし直す
- 外れていた場合: 1回で通る直し方が少なく、ほとんどの対象が Issue になる。所有者が受け取るのは PR でなく Issue の列になり、Issue #725 の「Claude が警告を消す PR を作る」が実際にはほとんど起きない

**2. Claude の CLI を claude-code-action を使わずに直接動かす** — design.md 全体の構成

- Issue の記載: なし(費用は Claude の契約で払い、API キーは使わない、だけ)
- 決めたこと: CLI 2.1.323 を署名で確かめて入れ、`claude -p` で動かす。CLI の版は自動では上がらない
- 他にありえた選択肢: Anthropic の claude-code-action を SHA で固定して使う
- 外れていた場合: CLI の結果の JSON の形や道具の絞り方が版で変わると、所有者か Claude が手で追うことになる。版を上げる仕組みは「作らないもの」にある

**3. コンテナの脆弱性は、1度扱った Issue を自動のきっかけでは2度扱わない** — design.md claude-auto-fix-dispatch.sh「コンテナの検査の終わり」

- Issue の記載: 「修正版がある脆弱性について、Claude が脆弱性を消す PR を作る」
- 決めたこと: `claude-auto-fix-notice` のコメントか、その ID の Claude の変更の PR が1つでもあれば、検査の終わりでは起動しない。PR がマージされたあとに所有者がリリースせず Issue が開いたままでも、もう1度は動かさない
- 他にありえた選択肢: Issue が開いていて main のイメージに残る間は、検査のたびに扱う
- 外れていた場合: Claude の変更の PR が閉じられたあと(対象が消えたと誤って判定したときなど)、その脆弱性は所有者が手で起動するまで扱われない

**4. 「記録なしで赤になる見込み」の結果も、3日続いたら Issue にする** — design.md claude-auto-fix-report.sh「unavailable と blocked」

- Issue の記載: なし
- 決めたこと: `blocked`(72時間経っていない版)を `unavailable` と同じに数え、3つの違う日に続けば「動けなかった」Issue を起票する
- 他にありえた選択肢: `blocked` は Issue に数えず、72時間が過ぎるまで黙って動かし直す
- 外れていた場合: 公開から72時間の版しか修正版が無い対象ごとに、3日目に Issue が起票される。要件6.1 は「Claude が動けなかった」ときの Issue で、72時間の待ちは挙げていない

**5. CodeQL の警告が消えたかを「同じ規則の ID の結果が同じファイルに無い」で見る** — design.md claude-auto-fix-verify.sh 4

- Issue の記載: なし
- 決めたこと: SARIF に、警告と同じ規則の ID の結果が警告と同じファイルに1つも無いことを求める
- 他にありえた選択肢: 警告の場所(行)か fingerprint で照らす
- 外れていた場合: 同じファイルに同じ規則の別の警告が開いていると、対象の警告を直しても「直せなかった」になる。Claude が1つの PR でそのファイルの同じ規則の警告を全部直さない限り通らない

**6. 自動のきっかけの実行を、同じ対象について UTC の1日に1回までにする** — design.md 処理の流れ「流れの上の決めごと」

- Issue の記載: なし
- 決めたこと: 必須の検査の赤による動かし直しも、同じ表示名(PR の head の SHA つき)で1日1回まで
- 他にありえた選択肢: 回数を限らず、きっかけのたびに動かす
- 外れていた場合: 所有者の契約の使える量は守られるが、直るまでの日数が延びる

**7. PR を作る前に e2e-smoke を流さない** — design.md claude-auto-fix-verify.sh 3

- Issue の記載: なし
- 決めたこと: 5つの領域の品質チェックだけを流し、e2e-smoke は PR の必須の検査に任せる
- 他にありえた選択肢: frontend を変えたときは e2e-smoke も流す
- 外れていた場合: e2e-smoke で赤になる PR が作られ、sweep の赤の扱い(3回で閉じる)に回る

**8. この spec の変更の多くが `.github/` にあり、所有者が scratchpad から写す** — design.md プロジェクトの決まり

- Issue の記載: なし
- 決めたこと: ワークフロー2つ、アクション1つ、スクリプト11本とそのテスト、今ある4本のスクリプトの変更を、すべて所有者が `cp` で置く
- 他にありえた選択肢: スクリプトを `.github/` の外に置く(その場合も CI が呼ぶスクリプトとして承認は要る)
- 外れていた場合: 所有者の手の作業が多くなる。選択肢の差は小さい

### 指摘

| ID | レベル | 該当箇所 | 内容 | 直し方の案 |
|---|---|---|---|---|
| D1-1-1 | 高 | design.md プロジェクトの決まり「使う外部の機能がこのリポジトリで使えるか」、claude-auto-fix-target.yaml の cooldown-push と cooldown-judge | cooldown-judge は、PR の無い一時のブランチのコミットと main を、依存グラフの差分比較の API で比べる。design は「差分比較の API は今あるワークフローが使っている」と書くが、今ある使い方(check-dependency-cooldown.sh 103-104行)は PR のコミットの比較だけである。research.md 225行は「PR の無いブランチのコミットで、差分比較の API が npm と gomod の差を返すかが文書に無い」と書き、確かめを済ませていない。返さなければ、predict はいつも「判定できない」の1で終わり、依存のファイルを変える変更(npm、maven、go-stdlib、go-module の全部)がいつも `blocked` になり、PR が1つも作られない。テストは偽の gh で流すので、実装が終わるまで誰も気づかない | 承認の前に、このリポジトリの PR の無いブランチ(依存のファイルを変えたコミット)と main で `dependency-graph/compare` を呼び、npm と gomod と Gradle(送信のあと)の差が返るかを確かめる。いつ、どのコミットで、何が返ったかを「プロジェクトの決まり」の項に書く。返らないなら、判定の材料を別の作り方(たとえば、下書きの PR を作らずに lockfile の差から変わった部品を作る)に変える |
| D1-1-2 | 中 | design.md claude-auto-fix-run-claude.sh「起動のしかた」「設定のファイル」「結果の見分け方」、安全「材料に書かれた指示」、verified-claude | design は「Claude は Bash と Web の道具を持たず、target/ のファイルの読み書きしかできない」と言い切るが、research.md 159行は「実装のときに、CLI の --tools と拒否の決まりで Bash が使えないことを、CLI の版 2.1.323 で確かめる」と先送りしている。次のどれも、確かめた日と方法が design に無い。(1) `--tools Read,Edit,Write,Glob,Grep` と `permissions.deny` で Bash が使えず、`target/` の外(最上位に checkout したワークフローのコミット、`$RUNNER_TEMP`)を読み書きできないこと。deny に書くのは `/proc` `/sys` `$RUNNER_TEMP` の読み込みだけで、`target/` の外への書き込みと、そのほかの場所の読み込みを止める決まりは無い。(2) `--output-format json` の結果が、認証の失敗と `rate_limit` と `error_during_execution` をどの欄で見分けられるか。(3) 版 2.1.323 の配布物と `manifest.json` と署名がその URL にあること。あわせて、`--max-turns 60` に届いたとき(結果の種類 `error_max_turns`)を `ok` `key` `unavailable` `unfixed` のどれにするかが書かれていない。見分けを誤ると、鍵の Issue と3日の Issue と直せなかった Issue が入れ替わる | 承認の前に、手元で CLI 2.1.323 を同じ引数と設定で動かし、Bash を求めたとき、`target/` の外を読もうとしたとき、鍵が誤っているときの結果の JSON を見る。確かめた日と結果を design に書く。`target/` の外の読み書きを止める決まりと、`error_max_turns` の分け方を足す |
| D1-1-3 | 中 | design.md claude-auto-fix-target.yaml の verify、claude-auto-fix-verify.sh 4 の codeql、安全「CodeQL の警告の中身」 | verify ジョブの権限は `contents: read` だけで、秘密の値を持たない。ところが verify は「警告の most_recent_instance.category から言語を選び」、SARIF を「警告と同じ規則の ID」「警告と同じファイル」と照らす。Code scanning の警告の API は `security-events: read` が要る。verify.sh の引数は `<kind> <key> <detail> <起点のコミット>` で、言語も規則の ID もファイルも入らない。安全の節は「材料は edit ジョブの中で集め、成果物として受け渡さない」と書く。verify が言語、規則の ID、ファイルを受け取る道が無い | prepare ジョブ(`security-events: read` を持つ)が、言語と規則の ID とファイルを読んでジョブの出力で verify に渡すか、verify に `security-events: read` を足すかを決めて書く。前者なら、ジョブの出力が公開の実行の記録に出ないことも書く |
| D1-1-4 | 中 | design.md claude-auto-fix-prepare.sh「起点のコード」、claude-auto-fix-target.yaml の cooldown-push、claude-auto-fix-verify.sh、claude-auto-fix-ship.sh | 種類 `dependabot` の起点は「main に Dependabot の PR の head をマージしたコード」で、prepare ジョブの中だけにあるコミットである。あとのジョブ(verify、cooldown-push、ship)は「起点のコミット」に差分を当てるが、`base.patch` から起点を作り直す手順と、作り直したコミットが prepare の出した SHA と同じになるのかが書かれていない。また、`final.patch` が起点との差なのか main との差なのかが書かれていない。起点との差なら、Dependabot の版上げは `final.patch` に入らないので、「最後の差分が依存の版を宣言するファイルを変えたときだけ」動く cooldown のジョブが動かない。Claude がコードだけを直した PR にも Dependabot の版上げが入るので、72時間経っていない版なら PR の dependency-cooldown が記録なしで赤にし、要件2.9(どの Dependabot の PR かによらず分ける)に届かない | 起点の作り直し方(たとえば、`base.patch` を main に当てたコミットを各ジョブで作り、SHA でなく差分の SHA-256 で照らす)を書く。cooldown のジョブを動かす条件と predict の比べる相手を、main との差で決めると書く |
| D1-1-5 | 中 | design.md prompt.md「Claude は、lockfile と go.sum とイメージの digest を書かない。これらは verify ジョブが作り直すためである」、claude-auto-fix-verify.sh 1 | verify がイメージの digest を作り直すのは、種類が `go-stdlib` のときの `go_bump` だけである。Dockerfile は土台のイメージを `@sha256:` で固定している(docker/backend/Dockerfile.prod 4行、28行ほか)。種類 `container` の脆弱性のうち、土台のイメージか golang のイメージを上げて消すものは、Claude が digest を書けず(Bash も Web も無い)、verify も作り直さないので、直す道が無い。prompt の文と verify の手順が食い違っている | verify の手順1に、Claude が Dockerfile の FROM のタグを変えたときに digest を引き直す手順(`go_bump` が使う `digest` と同じ引き方)を足すか、土台のイメージの上げは Dependabot の docker の PR に任せて Claude の対象にしないと書き、prompt の文を合わせる |
| D1-1-6 | 中 | design.md prompt.md「frontend の修正版が公開から72時間経っていないときは、Claude は minimumReleaseAgeExclude にその版を足す」、claude-auto-fix-materials.sh の npm | Claude に渡す npm の材料は、組の JSON と警告の説明だけで、修正版の公開日時が入っていない。Claude は Bash も Web も持たないので、72時間経っているかを判断できない。今の frontend-vuln-fix は公開日時を registry から読んでスクリプトが決めている(frontend-vuln-fix.sh 141-143行)。Claude が足さなければ、verify の `pnpm install --lockfile-only` がその版を入れられずに落ちるか古い版を選び、結果は `unfixed` になって Issue が起票される。要件2.9 の「承認を求める扱いなら72時間を待たずに PR を作る」「記録なしで赤なら次の日に動かし直す」のどちらにもならない | 除外の欄に足すかどうかを Claude に任せず、verify の手順1で、今の `decide` と `exclude` を使ってスクリプトが足すようにする。または、材料に修正版の公開日時と今の時刻を入れる |
| D1-1-7 | 中 | design.md claude-auto-fix-dispatch.sh「1時間ごとの定期実行」と絞り込みの「鍵の Issue が開いていれば、retry で選んだ1つのほかは起動しない」、claude-auto-fix-report.sh | 鍵の Issue を閉じるのは、結果が `pr` と `unfixed` のときだけである。(1) 結果が `blocked` のときも Claude は動けているが、Issue は閉じない。要件6.3 は「鍵を取り替えたあとに Claude が動けたら閉じる」である。(2) 鍵の Issue が開いている間に動くのは、直近4日の結果が `key` の対象から選んだ1日1つだけである。その対象が消えて結果が `gone` か `skipped` になると、`key` の結果を持つ対象が無くなる。そのあとは、新しい警告のきっかけも「起動しない」ので、何も動かず、鍵の Issue も閉じない。所有者が鍵を取り替えても、Issue を手で閉じるまで仕組みが止まったままになり、要件6.4(次の日までに動かし直す)に届かない | Claude を動かした実行(edit ジョブが `ok` を出した実行)は、あとの結果によらず鍵の Issue を閉じると書く。鍵の Issue が開いていて `key` の結果を持つ対象が無いときは、新しいきっかけの対象を1日に1つだけ起動すると書く |
| D1-1-8 | 中 | design.md claude-auto-fix-verify.sh 3 の `frontend` と `backend_compat` と `backend_go` | verify が流す品質チェックのうち、動かすのに要るものが書かれていない領域がある。(1) `backend_compat`: ci.yaml の backend-compat ジョブは、環境変数 `KEIREKIPRO_REPO_ROOT` にリポジトリの最上位を渡し、poppler-utils を入れてから `make compat` を流す(ci.yaml 474-509行)。verify ではコードが `target/` にあるので、渡す値は `target/` の場所になる。(2) `frontend`: `frontend_test` は pnpm と Node.js が要る。今は pnpm/action-setup と verified-node で入れている(ci.yaml 209-253行)。(3) `backend_go`: `make mutation-diff BASE=origin/main` は、`target/` に main の履歴があることが要る。`backend_java` と `backend_go` の Go と lint の版は書かれている。書かれていない分は、テストが偽のコマンドで流れるので、実際の対象が来たときに `unfixed` として現れる | 領域ごとに、入れる道具と版の出どころ、渡す環境変数(`KEIREKIPRO_REPO_ROOT=<target の絶対パス>`)、checkout の深さを書く |
| D1-1-9 | 中 | design.md テストの方針、claude-auto-fix.yaml、claude-auto-fix-target.yaml | テストの方針にあるのは、スクリプトごとのシェルのテストだけである。2つのワークフローそのもの(ジョブの順番と `if`、ジョブごとの権限、秘密の値を渡すジョブ、「どのジョブで止まったかから結果を決める」、cooldown の終わり方0と3と1の分け、成果物の受け渡し、`workflow_run` のきっかけ)を確かめる道具が無い。`workflow_dispatch` と `workflow_run` は main に入ったワークフローでしか動かないので、PR の検査でも確かめられない。要件2.3(必須の検査と auto-merge の予約)、3.3(Claude に GitHub を変える権限を渡さない)、1.6、2.9 のジョブの分けは、どの道具でも確かめられないまま出荷される | マージのあとに所有者か Claude が流す確かめの筋書き(たとえば、手で `claude-auto-fix-target.yaml` を1つの対象で起動し、結果のファイル、PR の作り手、予約、ジョブごとの権限を読む)を design に書き、PR の本文の「マージのあとにすること」に載せると書く。権限と秘密の値の置き場所は、ワークフローの YAML を読んで比べるテストで確かめられる |
| D1-1-10 | 中 | design.md テストの方針、ファイルの構成 | ファイルの構成は `test-claude-auto-fix-prepare.sh` を作ると書くが、テストの方針に prepare の項が無く、確かめる場合が1つも書かれていない。prepare は、止める決まり(`skipped`、`gone`)、コンテナの対象が main のイメージに無いときの `gone`、種類ごとの起点のコードを持つ。要件2.8(main で消えていれば PR を作らずコメントを付ける)は、prepare の判定と report の `gone` のコメントで成り立つが、report の項にも `gone` の場合が無い。要件2.8 を確かめる場合がどのテストにも無い | テストの方針に `test-claude-auto-fix-prepare.sh` の項を足し、止める決まりの場合、コンテナの `gone` の場合、種類ごとの起点の場合と要件の番号(2.6, 2.8, 4.3, 4.4)を書く。report の項に `gone` のコメントが1回だけ付く場合を足す |
| D1-1-11 | 低 | design.md 基盤構築手順と PR の本文の変更、テストの方針 | 要件7.1、7.2、7.3 の確かめ方(文書と PR の本文を読んで確かめる)が、design のどこにも書かれていない | テストの方針に、7.1 から 7.3 は文書と PR の本文を読んで確かめると1行足す |

### 前の段階への指摘

| ID | 対象 | 該当箇所 | 内容 |
|---|---|---|---|
| D1-1-12 | requirements | 要件1の4、要件2の4 | 要件2の4は、Claude の変更の PR では、escape-hatch、dependency-gate、pre-merge-check、dependency-cooldown の赤で Claude を動かさない(Claude がコードを直しても緑にならないため)と決めている。要件1の4は、止まった Dependabot の PR では、赤が dependency-review だけのときしか外していない。止まった Dependabot の PR の赤が、この4つの検査だけのときも、Claude がコードを直しても緑にならないが、要件のとおりなら Claude が動き、直せなかった Issue が起票される。design は要件のとおりに dependency-review だけを外している |

- 往復: 1回目 / 高1 中9 低1

## サイクル2 往復1(2026-11-14)

### 審査の範囲

範囲: 全体

### 実ファイルで確かめた文

- 使う既存の仕組み「frontend-vuln-fix.sh の vulnerable と frontend_test」: .github/scripts/frontend-vuln-fix.sh 53行、106行、173-176行 / 合っていた(ただし verify の手順1が使う decide と exclude がこの一覧に無い。D2-1-10)
- 使う既存の仕組み「backend-vuln-fix.sh の plan、vulnerable、go_plan は今も呼べ、tree、vulncheck、go_bump、digest はこの spec で呼べるようにする」: .github/scripts/backend-vuln-fix.sh 85行、156行、158行、161行、246-248行 / 合っていた
- 部品 claude-auto-fix-verify.sh「frontend-vuln-fix.sh decide で扱いを決め、exclude で除外の欄に足す。扱いは exclude か wait」: .github/scripts/frontend-vuln-fix.sh 64-69行、87-94行、174行 / 合っていた
- 同「backend-vuln-fix.sh digest <イメージ> で digest を読む」「go_bump は go.mod の toolchain と4つの Dockerfile の golang のイメージを上げる」: .github/scripts/backend-vuln-fix.sh 139行、158行、161-176行 / 合っていた
- 部品 vuln-fix の変更「frontend は7か所、backend の run は4か所、go_run は組を扱う4か所、組を読む前に止まる2か所、main の依存を解決できずに止まる箇所」: .github/scripts/frontend-vuln-fix.sh 142、146、150、153、156、166、168行、.github/scripts/backend-vuln-fix.sh 105、117、122、131、133、210、215、228、229、241、242行 / 合っていた
- データの形「今の vuln-fix のブランチ名は chore/ で始まる」: .github/scripts/frontend-vuln-fix.sh 136行、.github/scripts/backend-vuln-fix.sh 110行、221行、234行 / 合っていた
- 部品 claude-auto-fix-dispatch.sh「期待一覧で approval_gated が true の検査は escape-hatch、dependency-gate、pre-merge-check、dependency-cooldown。dependency-review は期待一覧に載る」: .github/audit/required-checks.json 6行、18行、19行、23行、24行 / 合っていた
- 部品 check-audit-dependabot-stuck.sh の変更「承認待ちの赤だけの PR は、今は止まった PR に数えない。終わり方は0、1、2」「記録のコメントの無い dependency-cooldown の赤は止まった赤に数える」: .github/scripts/check-audit-dependabot-stuck.sh 9-16行、21-22行、209-236行、260-277行 / 合っていた
- 部品 check-dependency-cooldown.sh の変更「今は PR_NUMBER を求め、流れの1から4が警告との照合、悪意のある部品の一覧、署名した者、pnpm の除外の欄の判定である」: .github/scripts/check-dependency-cooldown.sh 40-55行、66行、549-614行 / 合っていた(ただし4の判定が読む除外の欄のファイルを cooldown-judge に渡す道が無い。D2-1-2)
- 部品 claude-auto-fix-dispatch.sh「定期のコンテナの検査は、毎日と、本番のリリースのあとと、backend/ か docker/backend-go/ を変えた main への push のあとに動く」: .github/workflows/container-scan-scheduled.yaml 53-81行 / 合っていた
- 同「ラベル container-vuln の Issue は github-actions[bot] が起票し、container-scan-state の目印の JSON の rows に fixed がある。題名は脆弱性の ID を持つ」: .github/scripts/container-scan-issue.sh 62-70行、156-163行、303-306行 / 合っていた
- 部品 claude-auto-fix-materials.sh「Issue の本文に脆弱性の ID、部品、入っている版、修正版がある」: .github/scripts/container-scan-issue.sh 219-230行、280-285行 / 合っていた
- 部品 claude-auto-fix-target.yaml prepare「container-scan ジョブは ubuntu-24.04-arm で docker buildx build --platform linux/arm64、2つの Dockerfile.prod」「Trivy 0.76.2」: .github/workflows/container-scan.yaml 159行、220-229行、.github/workflows/container-scan-scheduled.yaml 99行 / 合っていた
- 同 verify-image と prepare.sh「check-container-scan.sh の report」: .github/scripts/check-container-scan.sh 52行、75行 / 合っていた
- 同 cooldown-generate と cooldown-submit「dependency-review.yaml と同じく productionRuntimeClasspath と detachedConfiguration の除外を渡す。generate-and-upload と download-and-submit に分ける」: .github/workflows/dependency-review.yaml 62-83行、108-111行 / 合っていた(ただし今の dependency-review.yaml は `GITHUB_DEPENDENCY_GRAPH_SHA` と `GITHUB_DEPENDENCY_GRAPH_REF` を使っていない。D2-1-1)
- 同 cooldown-judge「vulnerability-alerts: read」: .github/workflows/dependency-review.yaml 169-174行 / 合っていた
- 部品 claude-auto-fix-guard.sh「check-escape-hatches.sh <base> <head> を PR_BODY と OWNER_APPROVED で呼ぶと、ゲートの設定のファイルの変更と今の escape-hatch が見つける形を見つける」: .github/scripts/check-escape-hatches.sh 45-52行、157-225行。CODEOWNERS は .github/CODEOWNERS にあり、217行の `.github/` に入る / 合っていた
- 部品 claude-auto-fix-verify.sh 3「frontend は pnpm/action-setup v6.1.1 と Node.js 24.22.2、backend_java は Java 21 で ./gradlew check --configuration-cache、backend_go は golangci-lint-action v9.3.0(v2.15.0)と fetch-depth: 0 で make check と make mutation-diff、backend_compat は poppler-utils と KEIREKIPRO_REPO_ROOT で make compat と make compat-cross」: .github/workflows/ci.yaml 222行、231行、349行、370行、429-472行、481-509行 / 合っていた
- 同 verify「codeql.yaml と同じ版の init と analyze を upload: never で動かし、languages.tsv のビルドのしかたを使う」: .github/workflows/codeql.yaml 88行、105-109行、.github/codeql/languages.tsv 23-44行 / 合っていた
- 部品 claude-auto-fix.yaml「対象のワークフローの名前」「backend-vuln-fix は Java と Go の2つのジョブを持つ」: .github/workflows/frontend-vuln-fix.yaml 1行、backend-vuln-fix.yaml 1行、16行、33行、audit-weekly.yaml 1行、container-scan-scheduled.yaml 1行 / 合っていた
- 部品 claude-auto-fix-ship.sh「bot の PAT の push と PR の作成で、auto-merge.yaml が予約を付ける」: .github/workflows/auto-merge.yaml 63-66行、89-92行、131行 / 合っていた
- 部品 claude-auto-fix-report.sh と sweep「lib-ledger-issue.sh で探し、起票し、割り当てる。lib-notice-comment.sh の notice_post」: .github/scripts/lib-ledger-issue.sh 83行、145行、165行、.github/scripts/lib-notice-comment.sh 113行 / 合っていた
- 作らないもの「ci-tool-version-update が上げる道具は Node.js、Trivy、Codex CLI、Terraform の4つ」、ファイルの構成「ci-tool-versions.json と inventory-targets.json にワークフローの版の行がある」: .github/ci-tool-versions.json 3-53行、.github/audit/inventory-targets.json 40行、82-86行 / 合っていた
- データの形「ラベルの group other」: .github/labels.json 88-89行 / 合っていた
- 部品 基盤構築手順の変更「3-1 の Actions secrets の表(Secret、値、失効したとき)と bot の PAT の復旧の節」: doc/開発フロー/基盤構築手順.md 69-76行、313行 / 合っていた
- ファイルの構成「README にワークフローの一覧の表と Mermaid の図の PR の節がある」: README.md 55行、124-125行 / 合っていた(ただし96行の「Node.jsを使うワークフロー」の並びも、verified-node を使う新しいワークフローで変わる。D2-1-10)
- テストの方針「テストは bash "$SCRIPT" の形で呼ぶ」: .github/CLAUDE.md「シェルのスクリプトのテスト」 / 合っていた
- プロジェクトの決まり「2026-11-13 と 2026-11-14 に差分比較の API を確かめた」、部品 run-claude.sh「版 2.1.323 の配布物があることを 2026-11-13 に確かめた」、性能「Issue の件数と vuln-fix の直近100回」: 審査役が実行できるコマンドは `gh issue view` だけのため、確かめられなかった

### 受入基準ごとの確かめ方

| 受入基準 | 確かめる道具 | 動かす場所 | 動かすのに要るもの | design の箇所 |
|---|---|---|---|---|
| 1.1 | test-claude-auto-fix-dispatch.sh、test-frontend-vuln-fix.sh、test-backend-vuln-fix.sh | コンテナ(alpine に bash と jq) | 偽の gh、成果物の組の JSON、環境変数 VULN_FIX_UNRESOLVED | テストの方針 単体テストと結合テスト、部品 vuln-fix の変更 |
| 1.2 | test-claude-auto-fix-dispatch.sh | コンテナ | 偽の gh(CodeQL の警告の一覧) | テストの方針 結合テスト(番号の範囲 1.1-1.6) |
| 1.3 | test-claude-auto-fix-dispatch.sh(修正版の無い Issue で起動されず何も書かない) | コンテナ | 偽の gh(container-scan-state の目印つきの Issue) | テストの方針 結合テスト |
| 1.4 | test-lib-claude-auto-fix.sh(fixable_red_checks)、test-claude-auto-fix-dispatch.sh、test-claude-auto-fix-prepare.sh、test-check-audit-dependabot-stuck.sh | コンテナ | 偽の gh、偽の期待一覧、STUCK_JSON_OUT | テストの方針 単体テストと結合テスト |
| 1.5 | test-claude-auto-fix-dispatch.sh(manual) | コンテナ | 偽の gh | テストの方針 結合テスト |
| 1.6 | test-claude-auto-fix-dispatch.sh、test-claude-auto-fix-materials.sh、test-claude-auto-fix-workflows.sh(きっかけと if) | コンテナ | 偽の gh、yq | テストの方針。test-claude-auto-fix-workflows.sh はファイルの構成に無い(D2-1-3) |
| 2.1 | test-lib-claude-auto-fix.sh | コンテナ | なし | テストの方針 単体テスト |
| 2.2 | test-claude-auto-fix-verify.sh | コンテナ | ci.yaml、偽の docker と偽の pnpm | 領域の見分けとガードの場合だけがある。対象が残るときの場合は無い(D2-1-9) |
| 2.3 | test-claude-auto-fix-workflows.sh、マージのあとの確認 | コンテナ、main に入ったあとの実行 | yq、鍵、bot の PAT、開いている対象 | テストの方針 結合テストとマージのあとの確認(D2-1-3) |
| 2.4 | test-claude-auto-fix-sweep.sh、test-claude-auto-fix-ship.sh | コンテナ | 偽の gh、偽の git push | テストの方針 結合テスト |
| 2.5 | test-claude-auto-fix-sweep.sh | コンテナ | 偽の gh(末尾の行つきのコミット) | テストの方針 結合テスト |
| 2.6 | test-claude-auto-fix-sweep.sh、test-claude-auto-fix-prepare.sh | コンテナ | 偽の gh | テストの方針 結合テスト |
| 2.7 | test-claude-auto-fix-sweep.sh | コンテナ | 偽の gh | テストの方針 結合テスト |
| 2.8 | test-claude-auto-fix-prepare.sh、test-claude-auto-fix-report.sh | コンテナ | 偽の gh、偽の Trivy の結果 | テストの方針 結合テスト |
| 2.9 | test-check-dependency-cooldown.sh(predict)、test-claude-auto-fix-verify.sh(npm の wait)、cooldown の4つのジョブ | コンテナ、main に入ったあとの実行 | 偽の gh。実行では一時のブランチ、Gradle のスナップショットの送り先のコミットとブランチ、一時のブランチの pnpm-workspace.yaml | predict はテストの方針。スナップショットの送り先は確かめた記載が無い(D2-1-1)。除外の欄のファイルは無い(D2-1-2)。npm の wait と、組のほかの新しい版の場合は無い(D2-1-5、D2-1-9) |
| 3.1 | test-claude-auto-fix-guard.sh、test-claude-auto-fix-verify.sh | コンテナ | git のリポジトリ(2つのコミット) | テストの方針 単体テスト。ガードのあとに変わった差分を見る道具は無い(D2-1-4) |
| 3.2 | test-claude-auto-fix-guard.sh | コンテナ | 同上 | テストの方針 単体テスト(D2-1-4) |
| 3.3 | test-claude-auto-fix-run-claude.sh、test-claude-auto-fix-workflows.sh、実装の前の CLI の確かめ、マージのあとの確認 | コンテナ、手元、main に入ったあとの実行 | 偽の claude、yq、CLI 2.1.323、鍵 | テストの方針、部品 run-claude.sh「確かめていること」(D2-1-3) |
| 3.4 | test-claude-auto-fix-ship.sh | コンテナ | 偽の gh | テストの方針 結合テスト(dependabot の別の PR の場合は書かれていない) |
| 3.5 | test-claude-auto-fix-materials.sh | コンテナ | 偽の gh | テストの方針 単体テスト |
| 4.1 | test-claude-auto-fix-report.sh | コンテナ | 偽の gh | テストの方針 結合テスト |
| 4.2 | test-claude-auto-fix-report.sh | コンテナ | 偽の gh | テストの方針 結合テスト(番号だけ) |
| 4.3 | test-claude-auto-fix-dispatch.sh、test-claude-auto-fix-prepare.sh、test-frontend-vuln-fix.sh、test-backend-vuln-fix.sh | コンテナ | 偽の gh | テストの方針 |
| 4.4 | test-claude-auto-fix-dispatch.sh、test-claude-auto-fix-prepare.sh | コンテナ | 偽の gh | テストの方針 |
| 4.5 | test-claude-auto-fix-sweep.sh | コンテナ | 偽の gh | テストの方針 結合テスト |
| 5.1 | test-claude-auto-fix-ship.sh、test-claude-auto-fix-report.sh、test-claude-auto-fix-materials.sh | コンテナ | 偽の gh | テストの方針 |
| 5.2 | test-claude-auto-fix-verify.sh。CodeQL の init と analyze はマージのあとの実行 | コンテナ、main に入ったあとの実行 | 警告の規則の ID、ファイル、category(verify の最初の手順が読む) | 部品 target.yaml の verify。SARIF と照らす場合はテストの方針に無い(D2-1-9) |
| 6.1 | test-claude-auto-fix-report.sh、test-claude-auto-fix-dispatch.sh、test-claude-auto-fix-run-claude.sh | コンテナ | 偽の gh(直近4日の結果のファイル)、偽の claude | テストの方針 |
| 6.2 | test-claude-auto-fix-report.sh | コンテナ | 偽の gh | テストの方針 結合テスト |
| 6.3 | test-claude-auto-fix-report.sh、test-claude-auto-fix-run-claude.sh | コンテナ | 偽の gh、偽の claude | テストの方針 |
| 6.4 | test-claude-auto-fix-dispatch.sh | コンテナ | 偽の gh(4日より前に key で終わった結果のファイル) | 「鍵の Issue が開いている間は1日に1つ」だけがある。4日より前に key で終わった対象を動かし直す決まりは無い(D2-1-6) |
| 7.1 | 基盤構築手順を読んで確かめる | 手元 | なし | 部品 基盤構築手順と PR の本文の変更(確かめ方は書かれていない。D1-1-11 で記録のみ) |
| 7.2 | 基盤構築手順を読んで確かめる | 手元 | なし | 同上 |
| 7.3 | PR の本文を読んで確かめる | 手元 | なし | 同上 |

### 申告

**1. Claude を1回の実行で1回だけ動かし、確認に落ちた変更は直し直さずに「直せなかった」にする** — design.md 処理の流れ「流れの上の決めごと」

- Issue の記載: なし(「Claude が直し方を考え、警告を消す PR を作る」「Claude も警告を消せなかったときは Issue を起票する」だけ)
- 決めたこと: 仕組みは、品質チェックや対象の確認に落ちた結果を Claude に渡さない。Claude は Bash を持たず、自分でテストを流せない。1回で通らなければ Issue になる
- 他にありえた選択肢: 確認に落ちた出力を材料に足して、同じ実行の中で Claude を数回動かし直す
- 外れていた場合: 1回で通る直し方が少なければ、ほとんどの対象が PR でなく Issue になる

**2. Claude の変更の PR の赤を Claude が直せなかったら、1回目の赤でも PR を閉じる** — design.md claude-auto-fix-report.sh「unfixed」、run-claude.sh「変更が空のときは unfixed」

- Issue の記載: なし。要件2の5は「同じ必須の検査が3回続けて赤になったら閉じる」
- 決めたこと: `red-check` の実行の結果が `unfixed` なら、PR を閉じてブランチを消し、直せなかった Issue を起票する。Claude が何も変えなかったとき(たまたま落ちた検査など)も `unfixed` になる
- 他にありえた選択肢: `red-check` の `unfixed` では PR を閉じず、3回目の赤まで残す。変更が空のときは検査の再実行を待つ
- 外れていた場合: たまたま落ちた検査の赤1回で、通るはずの PR が閉じられ、Issue が起票される

**3. Claude の CLI を直接動かし、道具の絞り方と結果の JSON の形の確かめを実装の最初に回す** — design.md 全体の構成、run-claude.sh「確かめていること」

- Issue の記載: なし
- 決めたこと: CLI 2.1.323 を署名で確かめて入れる。`--tools` と2つの設定と `subtype` は公式の文書で確かめ、実物での確かめは run-claude.sh を作る前に行う
- 他にありえた選択肢: claude-code-action を SHA で固定して使う。承認の前に実物で確かめる
- 外れていた場合: 結果の JSON の欄が違えば、鍵の Issue と3日の Issue と直せなかった Issue の分け方を design に戻って直す

**4. CodeQL の警告を直す差分を、ジョブの間で成果物として受け渡す** — design.md 安全「CodeQL の警告の中身」

- Issue の記載: なし。要件5は、PR、コミット、Issue、コメントの文を挙げる
- 決めたこと: `claude.patch` と `final.patch` を成果物にし、保存の期間を1日にして cleanup ジョブが消す。公開のリポジトリの成果物は、実行の間、ログインした誰でも取れる
- 他にありえた選択肢: 種類が `codeql` のときは差分を成果物にせず、edit と verify を1つのジョブにまとめる(鍵とコードを分ける決まりと両立しない)
- 外れていた場合: 確認に通らなかった直しかけの差分(穴の場所)が、cleanup までの最長で数時間、取れる状態になる

**5. 「記録なしで赤になる見込み」の結果も、3日続いたら Issue にする** — design.md claude-auto-fix-report.sh「unavailable と blocked」

- Issue の記載: なし
- 決めたこと: `blocked` を `unavailable` と同じに数える
- 他にありえた選択肢: `blocked` は Issue に数えず、72時間が過ぎるまで黙って動かし直す
- 外れていた場合: 公開から72時間の版しか修正版が無い対象ごとに、3日目に「動けなかった」Issue が起票される

**6. コンテナの脆弱性は、1度扱った Issue を自動のきっかけでは2度扱わない** — design.md claude-auto-fix-dispatch.sh「コンテナの検査の終わり」

- Issue の記載: 「修正版がある脆弱性について、Claude が脆弱性を消す PR を作る」
- 決めたこと: 目印のコメントか、その ID の Claude の変更の PR が1つでもあれば、検査の終わりでは起動しない
- 他にありえた選択肢: Issue が開いていて main のイメージに残る間は、検査のたびに扱う
- 外れていた場合: Claude の変更の PR が閉じられたあと、その脆弱性は所有者が手で起動するまで扱われない

**7. CodeQL の警告が消えたかを「同じ規則の ID の結果が同じファイルに無い」で見る** — design.md claude-auto-fix-verify.sh 4

- Issue の記載: なし
- 決めたこと: SARIF に、同じ規則の ID の結果が同じファイルに1つも無いことを求める
- 他にありえた選択肢: 警告の場所(行)か fingerprint で照らす
- 外れていた場合: 同じファイルに同じ規則の別の警告があると、対象を直しても「直せなかった」になる

**8. 自動のきっかけの実行を、同じ対象について UTC の1日に1回までにする** — design.md 処理の流れ「流れの上の決めごと」

- Issue の記載: なし
- 決めたこと: 同じ表示名の実行は1日1回まで。手での起動は数えない
- 他にありえた選択肢: 回数を限らない
- 外れていた場合: 契約の使える量は守られるが、直るまでの日数が延びる

**9. この spec の変更の多くが `.github/` にあり、所有者が scratchpad から写す** — design.md プロジェクトの決まり

- Issue の記載: なし
- 決めたこと: ワークフロー、アクション、スクリプトとテストを、すべて所有者が `cp` で置く
- 他にありえた選択肢: スクリプトを `.github/` の外に置く(その場合も承認は要る)
- 外れていた場合: 所有者の手の作業が多くなる。選択肢の差は小さい

### 指摘

| ID | レベル | 該当箇所 | 内容 | 直し方の案 |
|---|---|---|---|---|
| D2-1-1 | 高 | design.md プロジェクトの決まり「使う外部の機能がこのリポジトリで使えるか」、claude-auto-fix-target.yaml の cooldown-generate と cooldown-submit | maven の判定は、Gradle のスナップショットを一時のブランチのコミットに結び付けて送れることを前提にする。design が 2026-11-14 に一時のブランチで確かめたのは npm と gomod だけで、maven は main のコミット(2026-11-13)でしか確かめていない。対象ごとのワークフローは `workflow_dispatch` で main の上で動くので、何も指定しなければ、送るスナップショットのコミットとブランチは main になる。今の dependency-review.yaml(62-83行、108-111行)は PR のきっかけで動き、`GITHUB_DEPENDENCY_GRAPH_SHA` と `GITHUB_DEPENDENCY_GRAPH_REF` を使っていないので、この指定の効き方は、このリポジトリで1度も確かめられていない。design はこの2つを cooldown-submit(`download-and-submit`)に渡すと書くが、スナップショットのファイルを作るのは cooldown-generate(`generate-and-upload`)である。指定が generate の側でしか効かないなら、スナップショットは main のコミットに結び付いて送られる。そのとき、一時のブランチのコミットには maven の差が出ず、predict は「72時間経っていない版が無い」の0で終わり、PR ができたあとに PR の dependency-cooldown が記録なしで赤にする(要件2の9に届かない)。main のスナップショットも、マージしていない変更の依存で書き換わる。審査役は公式の文書を開けないため、どちらの側で効くかは確かめていない。テストは偽の gh で流れるので、実装が終わっても誰も気づかない | 承認の前に、gradle/actions の公式の文書(docs/dependency-submission.md)で、2つの環境変数が `generate-and-upload` と `download-and-submit` のどちらで読まれるかを確かめる。そのうえで、一時のブランチに `backend/gradle/libs.versions.toml` を変えたコミットを置き、`workflow_dispatch` の実行から送って、差分比較の API が main とそのコミットの maven の差を返すことと、main のスナップショットが変わらないことを確かめる。確かめた日、コミット、結果を「プロジェクトの決まり」に書き、環境変数を渡すジョブを直す |
| D2-1-2 | 中 | design.md claude-auto-fix-target.yaml の cooldown-judge、claude-auto-fix-prepare.sh「起点の作り直し」 | `check-dependency-cooldown.sh` の4つ目の判定は、`PNPM_WORKSPACE_FILE`(既定は `frontend/pnpm-workspace.yaml`)を作業のフォルダから読む(check-dependency-cooldown.sh 81行、600-613行)。対象ごとのワークフローは、最上位に main を checkout する。cooldown-judge は、起点のコードを作り直すジョブの一覧(edit、verify、verify-image、cooldown-push、ship)に入っておらず、一時のブランチの checkout も `PNPM_WORKSPACE_FILE` も書かれていない。design のとおりに作ると、判定は main の除外の欄を読む。verify が除外の欄に足した版はそこに無いので、predict は「除外の欄に、この版の要素が無い」で1になり、本番で動く部品の high か critical の npm の修正版は、72時間が過ぎるまでいつも `blocked` になる。要件2の9の「72時間を待たずに PR を作る」が npm で起きない。predict のテストは、ファイルを環境変数で渡すので通る | cooldown-judge が、一時のブランチのコミットを `target/` に checkout し、`PNPM_WORKSPACE_FILE=target/frontend/pnpm-workspace.yaml` を渡すと書く。test-claude-auto-fix-workflows.sh で、この渡し方を確かめる |
| D2-1-3 | 中 | design.md ファイルの構成、テストの方針の `test-claude-auto-fix-workflows.sh` | テストの方針は `test-claude-auto-fix-workflows.sh` で2つのワークフローの権限、秘密の値、ジョブの順番と `if` を確かめると書く(要件1.4、2.3、3.3)。ところが、ファイルの構成の「Claude が新しく作るファイル」の11本のテストに、このファイルが無い。どのワークフローのどのジョブがこのテストを流すかも書かれていない(部品の節は「各ジョブは、そのスクリプトのテストを流す」だけで、このテストはスクリプトのテストではない)。テストは「ランナーに入っている yq」を使うが、手元のテストのコンテナ(.github/CLAUDE.md の alpine に bash と jq)に yq は無い | ファイルの構成に `test-claude-auto-fix-workflows.sh` を足す。流す場所(たとえば、2つのワークフローの最初のジョブ)と、手元のコンテナで yq を入れて流すことを書く |
| D2-1-4 | 中 | design.md claude-auto-fix-verify.sh の手順2から4と「呼び出し方」、claude-auto-fix-ship.sh、安全「書き込みの権限」 | ガード(手順2)のあとに、同じ verify ジョブの中で、Claude が変えたテストとビルドスクリプトが動く(手順3)。`final.patch` とその SHA-256 を出すのも、同じ verify ジョブである。ship ジョブは、verify ジョブが出した SHA-256 と照らすだけで、ガードを呼ばない。手順3で動いたコードが、作業のフォルダのファイルか `final.patch` を書き換えれば、ガードを通っていない変更(`.github/` の変更、テストを飛ばす変更)が、bot の PAT で PR になる。要件3の1と2は「仕組みは、その変更を PR にしない」であり、要件3の前書きは、守ったかを Claude の側に任せないことを理由にしている。材料(Dependabot の PR の本文、実行の記録、警告の説明)に書かれた指示で Claude がそうしたコードを書いたとき、design の作りでは止まらない。PR の escape-hatch は赤になるが、それは所有者の承認を待つ赤で、sweep は数えない | ship ジョブ(コードを動かさないジョブ)が、`final.patch` を当てたあと、push の前に、`claude-auto-fix-guard.sh` をもう一度呼ぶと書く。0以外なら push せず `unfixed` にする。test-claude-auto-fix-ship.sh に、その場合を足す |
| D2-1-5 | 中 | design.md claude-auto-fix-verify.sh の手順1「npm の公開日時の判定」と「pnpm」、cooldown-judge | verify が公開日時を見るのは、種類が `npm` のときの、組の修正版だけである。Claude が、組の修正版のほかの npm の版(親の部品の版、種類が `codeql` `container` `dependabot` のときに上げた版)を、公開から72時間経っていない版に変えたとき、その版は除外の欄に無いので、`pnpm install --lockfile-only` は `minimumReleaseAge` の決まりでその版を入れられずに失敗する。手順1が通らないので、結果は `unfixed` になり、Issue が起票され、自動のきっかけでは動かし直されない。要件2の9は、この場合(frontend の部品の版が除外の欄に無いので、dependency-cooldown が記録なしで赤にする)を、PR を作らずに次の日に動かし直すと決め、対象の種類によらないと書いている。cooldown-judge は手順1のあとにあるので、この場合を見ることがない | 手順1の `pnpm install` が `minimumReleaseAge` で止まったときは、結果を `blocked` にすると書く。または、verify が、差分で版が変わった npm の部品の公開日時をすべて読み、72時間経っていない版が除外の欄に無ければ `blocked` にすると書く。test-claude-auto-fix-verify.sh にその場合を足す |
| D2-1-6 | 中 | design.md claude-auto-fix-dispatch.sh「1時間ごとの定期実行」と絞り込みの4つ目 | 鍵の Issue が開いている間、`retry` が動かすのは、直近4日に `key` で終わった対象から選ぶ1日1つだけで、ほかのきっかけは起動しない。鍵が切れた日に3つの対象が `key` で終わると、2日目からは1日に1つしか動かないので、選ばれなかった対象の `key` の結果は、5日目に直近4日から外れる。所有者が6日目より後に鍵を取り替えると、鍵の Issue が閉じたあとに「すべて選ぶ」の対象になるのは、直近4日に `key` で終わった対象だけで、外れた対象は選ばれない。外れた対象が CodeQL の警告か止まった Dependabot の PR なら、次に動くのは次の Audit Weekly(最長で7日後)になる。要件6の4は「鍵が切れて動けなかった対象について、次の日までに Claude をもう一度動かす」である。鍵の取り替えは所有者の手の作業なので、4日を超えることは起こりうる | 鍵の Issue が閉じたあとの最初の `retry` は、所有者の手での起動と同じ4つの集め方で対象を集め直すと書く(`reason` は `retry` のままにし、要件4の4の絞り込みは掛ける)。test-claude-auto-fix-dispatch.sh に、4日より前に `key` で終わった対象が、鍵の Issue が閉じた次の `retry` で起動される場合を足す |
| D2-1-7 | 中 | design.md claude-auto-fix-target.yaml「失敗したとき」と claude-auto-fix-ship.sh「失敗したとき」 | target.yaml の節は「verify ジョブ以降で止まったときは `unfixed` にする」と書く。ship.sh の節は「push か PR の作成に失敗したときは、report ジョブは、この失敗を `unavailable` として扱う」と書く。ship ジョブは verify ジョブより後なので、2つの文が食い違う。`unfixed` なら Issue が起票されて自動のきっかけでは動かなくなり、`unavailable` なら次の日に動かし直すので、所有者に見える動きが変わる。cooldown-push、cooldown-generate、cooldown-submit が API の失敗で止まったとき(Claude の直しとは関係がない)も、target.yaml の文では `unfixed` になる | 止まったジョブごとの結果を1つの表にまとめる(たとえば、prepare と edit は `unavailable`、verify と verify-image は `unfixed`、cooldown の4つのジョブと ship は `unavailable`)。2つの節をその表に合わせる |
| D2-1-8 | 中 | design.md claude-auto-fix-prepare.sh「起点のコード」 | 「`red-check` のほかでは `base.patch` は空になる。種類が `dependabot` のときだけ、`base.patch` に Dependabot の版上げが入る」の1つ目の文が、2つ目の文と、テストの方針の「`base.patch` が `dependabot` のときだけ空でない」と食い違う。種類が `dependabot` の実行は `red-check` でないので、1つ目の文のとおりなら空になる。意味が変わる誤記である | 1つ目の文を「種類が `dependabot` のほかでは `base.patch` は空になる」に直す |
| D2-1-9 | 中 | design.md テストの方針の `test-claude-auto-fix-verify.sh` | verify のテストに書かれた場合は、領域の見分けとガードの2つだけである。要件2の2と5の2の中心である「対象の警告や脆弱性が残るときに `unfixed` になる」場合が、7種類のどれについても無い。サイクル1のあとに verify に足した動き(npm の `wait` で `blocked`、`exclude` で除外の欄に足す、Dockerfile の `FROM` に digest を書く、CodeQL の SARIF を規則の ID とファイルで照らす)の場合も無い。サイクル1の D1-1-10(prepare のテストの場合が無い)と同じ抜けである | テストの方針の verify の項に、種類ごとに対象が残るとき `unfixed` になり消えたとき `ok` になる場合、npm の `wait` と `exclude` の場合、`FROM` のタグに digest が足される場合を、要件の番号(2.2、2.9、5.2)と合わせて書く |
| D2-1-10 | 低 | design.md 使う既存の仕組み、ファイルの構成の README.md | (1) 使う既存の仕組みは frontend-vuln-fix.sh の `vulnerable` と `frontend_test` だけを挙げるが、verify の手順1は `decide` と `exclude` も使う(どちらも今も外から呼べる。frontend-vuln-fix.sh 174行)。(2) README.md 96行の「Node.jsを使うワークフロー」の並びも、verified-node を使う新しいワークフローで変わるが、ファイルの構成の README の項は表と Mermaid の図だけを挙げる | 使う既存の仕組みに `decide` と `exclude` を足す。README の項に96行の並びを足す |

### 前の段階への指摘

なし

- 往復: 1回目 / 高1 中8 低1

## サイクル2 往復2(2026-11-14)

### 審査の範囲

範囲: 差分

- design.md 部品 claude-auto-fix-dispatch.sh の「絞り込みの決まり」の2つ目(261行): 差分が足した「鍵の Issue が閉じたあとの最初の `retry`」の箇条が、この絞り込みを `retry` にも掛けると書いたため。語 `retry` と「要件4の4」で検索して見つけた
- design.md 部品 claude-auto-fix-prepare.sh の「止める決まり」(333行)と、処理の流れの「流れの上の決めごと」(217-218行): 集め直した対象が、このあとどこで止まるかを決める箇所のため
- design.md 部品 claude-auto-fix-ship.sh の「役割」(459行。新しい PR は `main_sha` に `base.patch` と `final.patch` を当てた1つのコミット)と、部品 claude-auto-fix-guard.sh(416行): 差分が足した「push の前のガード」が、このコミットと `check-escape-hatches.sh` を使うため。語 `claude-auto-fix-guard.sh` で検索して見つけた
- design.md 部品 claude-auto-fix.yaml の「いつ動くか」(231-233行)と部品 claude-auto-fix-sweep.sh の「赤の検査の扱い」(279行): 差分が `test-claude-auto-fix-workflows.sh` を dispatch ジョブだけに置いたため。対象ごとの実行を起動するもう1つのジョブ(sweep)を見た
- design.md 部品 claude-auto-fix-verify.sh の「役割」の先頭の文と手順1(427-431行)、部品 claude-auto-fix-report.sh の「`unavailable` と `blocked`」(482行): 差分が verify の出力に `blocked` を足したため
- design.md 部品 claude-auto-fix-report.sh、claude-auto-fix-prepare.sh、claude-auto-fix-materials.sh、verified-claude の「失敗したとき」: 差分が足した「止まったジョブごとの結果」の表と同じことを書く箇所のため。表と合っていた
- requirements.md 要件2の9、要件3の1と2、要件4の4、要件6の4: 差分が挙げた要件の番号のため
- research.md 92-101行、147-149行: 差分が「research.md に書く」「文書の URL」と書いたため
- そのほかの節(材料、run-claude、sweep の後始末、データの形、性能)は、差分の語が出てこないので読み直していない

### 実ファイルで確かめた文

- 部品 claude-auto-fix-target.yaml cooldown-judge「`PNPM_WORKSPACE_FILE` を渡さないと、最上位に checkout した main の除外の欄を読む」「4つの判定のうちの pnpm の除外の欄の判定」: .github/scripts/check-dependency-cooldown.sh 45行、47-52行、81行、604行 / 合っていた
- 同 cooldown-generate「設定は dependency-review.yaml と同じ」と、プロジェクトの決まり「maven の差は、一時のブランチのコミットではまだ確かめていない」(今あるワークフローが2つの環境変数を使っていないこと): .github/workflows/dependency-review.yaml 63行、109行、.github/workflows/dependency-graph.yaml 34-36行、61行、101行。`GITHUB_DEPENDENCY_GRAPH` の語は `.github/workflows/` のどこにも無い / 合っていた
- プロジェクトの決まり「`workflow_dispatch` の実行から2つの環境変数を渡してスナップショットを送る」: `gradle/actions/dependency-submission` を使うワークフローは dependency-review.yaml(PR のきっかけ)と dependency-graph.yaml(34-36行。main への push だけ)の2つで、どちらにも `workflow_dispatch` が無い / 今あるワークフローでは、この確かめを動かせない(D2-2-4)
- 部品 claude-auto-fix-ship.sh「push の前に `claude-auto-fix-guard.sh <起点のコミット> <そのコミット>` を呼ぶ」(ガードは `check-escape-hatches.sh <base> <head>` を呼ぶ): .github/scripts/check-escape-hatches.sh 49-50行、54行、64行、217行。このスクリプトは、2つのコミットを直接比べず、`git merge-base` で求めた共通の祖先と head を比べる / 引数の形は合っていた。新しい PR のコミットでは、比べる範囲が design の書く「起点からの差」にならない(D2-2-3)
- テストの方針「手元では、`.github/CLAUDE.md` の alpine のコンテナの `apk add` に `yq` を足して流す」: .github/CLAUDE.md 23行、62行 / 合っていた
- 部品 claude-auto-fix-verify.sh 手順1「pnpm は `minimumReleaseAge` の決まりで入れられずに止まる」: frontend/pnpm-workspace.yaml 8行、17行、22行(`minimumReleaseAge: 4320`。条件を満たす版が無いときに止まる設定である) / 合っていた
- 止まった Dependabot の PR に `.github/` を変えるものがあること(D2-2-3 の前提): .github/dependabot.yml 85行(`github-actions`) / 確かめた
- プロジェクトの決まり「plugin の README と gradle/actions の文書の記載」、部品 verify「pnpm の PR #10618 のエラーの名前」、テストの方針「ランナーのイメージ 20261111.370.1 に yq 4.54.3 がある」: 審査役が実行できるコマンドは `gh issue view` だけのため、確かめられなかった。research.md 99-101行に URL と読んだ日がある

### 受入基準ごとの確かめ方

| 受入基準 | 確かめる道具 | 動かす場所 | 動かすのに要るもの | design の箇所 |
|---|---|---|---|---|
| 1.4 | test-claude-auto-fix-workflows.sh(edit ジョブが prepare の `checks` を使う) | コンテナ(alpine に bash と jq と yq)、dispatch ジョブ | yq | テストの方針 結合テスト、部品 claude-auto-fix.yaml「使う部品」 |
| 2.2 | test-claude-auto-fix-verify.sh(種類ごとの `unfixed` と `ok`、digest)、test-claude-auto-fix-report.sh(止まったジョブごとの結果) | コンテナ | 偽の `vulnerable` `tree` `vulncheck` `go_plan` `digest`、偽の SARIF | テストの方針 結合テスト、部品 target.yaml「失敗したとき」の表 |
| 2.3 | test-claude-auto-fix-workflows.sh、マージのあとの確認 | コンテナ、dispatch ジョブ、main に入ったあとの実行 | yq、鍵、bot の PAT | テストの方針 結合テストとマージのあとの確認 |
| 2.9 | test-claude-auto-fix-verify.sh(`wait`、`exclude`、pnpm の止まり方)、test-claude-auto-fix-workflows.sh(2つの環境変数と `PNPM_WORKSPACE_FILE`)、実装の前の maven の確かめ、実装の前の pnpm のエラーの文の確かめ | コンテナ、手元、GitHub Actions の実行 | 偽の `decide` と偽の pnpm、yq。maven の確かめでは、一時のブランチと、2つの環境変数を渡して Gradle のスナップショットを送る `workflow_dispatch` のワークフロー | テストの方針、部品 verify 手順1、プロジェクトの決まり。maven の確かめに使うワークフローは無い(D2-2-4) |
| 3.1 | test-claude-auto-fix-guard.sh、test-claude-auto-fix-ship.sh(`.github/` の変更で push しない) | コンテナ | git のリポジトリ、偽の git push | テストの方針、部品 ship「push の前のガード」。種類が `dependabot` で `base.patch` が `.github/` を変える場合は無い(D2-2-3) |
| 3.2 | test-claude-auto-fix-guard.sh、test-claude-auto-fix-ship.sh(足した `@SuppressWarnings` で push しない) | コンテナ | 同上 | テストの方針、部品 ship「push の前のガード」 |
| 3.3 | test-claude-auto-fix-workflows.sh | コンテナ、dispatch ジョブ | yq | テストの方針、部品 claude-auto-fix.yaml「使う部品」 |
| 4.4 | test-claude-auto-fix-dispatch.sh | コンテナ | 偽の gh | 集め直しのときに `unfixed` の Issue かコメントがある対象を起動しない場合は無い(D2-2-2) |
| 6.1 | test-claude-auto-fix-report.sh(止まったジョブごとの結果) | コンテナ | 偽の gh | テストの方針、部品 target.yaml「失敗したとき」の表 |
| 6.4 | test-claude-auto-fix-dispatch.sh(4日より前に `key` で終わった対象が最初の `retry` で起動され、2回目では集め直さない) | コンテナ | 偽の gh(鍵の Issue が閉じた日時、`reason` が `retry` の実行の有無) | テストの方針、部品 dispatch「鍵の Issue が閉じたあとの最初の `retry`」。`reason` が `retry` の実行をどこから何日分読むかは無い(D2-2-1) |

### 申告

**1. maven の差を一時のブランチのコミットで確かめることを、承認のあとの実装の最初に回す** — design.md プロジェクトの決まり「使う外部の機能がこのリポジトリで使えるか」、設計を見直すきっかけ

- Issue の記載: なし
- 決めたこと: 2つの環境変数がスナップショットを作る側で効くことは、plugin の README と gradle/actions の文書で確かめた。このリポジトリでの実測は、実装する Claude が cooldown のジョブを作る前に行う。差が返らなければ、設計を見直す
- 他にありえた選択肢: 承認の前に、所有者に一時のワークフローを置いてもらって実測する
- 外れていた場合: maven の対象で、cooldown の4つのジョブの作りを design に戻って直す。npm と gomod の判定には影響しない

**2. pnpm が `minimumReleaseAge` で止まったことを、エラーの文で見分ける** — design.md claude-auto-fix-verify.sh 手順1

- Issue の記載: なし
- 決めたこと: エラーの文(`ERR_PNPM_NO_MATURE_MATCHING_VERSION`)で見分け、`blocked` にする。文は実装の前に実物で確かめる
- 他にありえた選択肢: verify が、差分で版が変わった npm の部品の公開日時をすべて registry から読む
- 外れていた場合: pnpm の版が上がって文が変わると、この止まり方が `unfixed` になり、Issue が起票されて自動では動かし直されない

サイクル2 往復1 の申告の1から9は、差分で変わっていない。

### 指摘

| ID | レベル | 該当箇所 | 内容 | 直し方の案 |
|---|---|---|---|---|
| D2-2-1 | 中 | design.md claude-auto-fix-dispatch.sh「鍵の Issue が閉じたあとの最初の `retry`」 | 最初の `retry` かどうかを「鍵の Issue が閉じた日時より後に、`reason` が `retry` の実行がまだ無いこと」で見分けると書くが、この条件に期限が無い。`reason` は表示名に入らず(表示名は `claude-auto-fix <kind> <key>`)、読めるのは終わった実行の結果のファイルだけで、dispatch が読むのは直近4日である。次のときに、条件がいつまでも成り立つ。(1) 集め直しても起動する対象が無かったとき。(2) 鍵の Issue が閉じてから4日が過ぎ、その間に `retry` の実行が無かったとき(動けない対象が無いふだんの状態)。鍵の Issue が1度でも閉じたあとは、1時間ごとの `retry` が毎回、4つの集め方で集め直すことになる。集め直しはコンテナの Issue を「扱ったかどうかによらず」対象にするので、Claude の変更の PR がマージされてリリースを待つ Issue で、毎日、対象ごとの実行(arm のランナーでの2つのイメージの組み立て)が起きる。「`retry` は対象を新しく集めず」と、コンテナの Issue を自動では1度しか扱わない決まりが効かなくなる。テストの「2回目の `retry` では集め直さない」は、閉じた直後の場合だけを見るので通る | 集め直すのを、鍵の Issue が閉じてから決まった時間のうち(たとえば25時間。要件6の4の「次の日までに」に足りる)の `retry` に限ると書く。その間に何度集め直しても、同じ表示名の実行はその日に1回しか起動されないので、増えない。`reason` が `retry` の実行で見分ける書き方は消す。テストに、閉じてから決まった時間が過ぎたあとは集め直さない場合を足す |
| D2-2-2 | 中 | design.md claude-auto-fix-dispatch.sh「鍵の Issue が閉じたあとの最初の `retry`」と「絞り込みの決まり」の2つ目 | 足した箇条は「`reason` は `retry` のままにし、下の絞り込みの決まりを掛ける。この絞り込みには、要件4の4の決まりも入る」と書く。ところが、絞り込みの決まりの2つ目は「`reason` が `trigger` のときは、次の2つのどちらかに当たる対象を起動しない(4.4)」のままで、`retry` には掛からない。2つの文が食い違う。知らせの Issue がある対象は prepare が `skipped` にする(「`reason` が `manual` でなく」)が、ラベル `container-vuln` の Issue に直せなかったコメントが付いた対象を止める決まりは prepare に無い。絞り込みの文のとおりに作ると、集め直しで、その対象について Claude が動く。テストの方針にも、この場合が無い | 絞り込みの決まりの2つ目を「`reason` が `trigger` のときと、鍵の Issue が閉じたあとに集め直した対象では」に直す。test-claude-auto-fix-dispatch.sh に、集め直しで、`unfixed` の Issue がある key と、直せなかったコメントがあるコンテナの Issue が起動されない場合を足す |
| D2-2-3 | 中 | design.md claude-auto-fix-ship.sh「push の前のガード」と「役割」 | ガードが呼ぶ `check-escape-hatches.sh` は、渡した2つのコミットを直接比べず、`git merge-base` で求めた共通の祖先と head を比べる(check-escape-hatches.sh 54行、64行)。ship は、新しい PR のとき「`main_sha` に `base.patch` と `final.patch` を当てた1つのコミット」を作る。このコミットは、起点のコミット(`main_sha` に `base.patch` を当てたコミット)の子ではないので、`claude-auto-fix-guard.sh <起点のコミット> <そのコミット>` の共通の祖先は `main_sha` になり、比べる範囲に `base.patch`(Dependabot の版上げ)が入る。種類が `dependabot` で、止まった PR が GitHub Actions の版上げ(.github/dependabot.yml 85行。`.github/workflows/` を変える)のとき、Claude の変更に問題が無くても、ガードは `.github/` の変更を見つけて(同 217行)0以外で終わる。Claude を動かし終えたあとに、いつも `unfixed` になる。verify ジョブのガードは、起点のコミットの子を見るので通る。テストは `final.patch` に `.github/` の変更がある場合だけを見るので、気づけない | ship は、起点のコミットの上に `final.patch` だけを当てたコミットを作り、そのコミットでガードを呼んでから、PR にする1つのコミットを作ると書く。test-claude-auto-fix-ship.sh に、`base.patch` が `.github/` のファイルを変え、`final.patch` が変えない場合に push されることを足す |
| D2-2-4 | 中 | design.md プロジェクトの決まり「使う外部の機能がこのリポジトリで使えるか」の maven の箇条 | 実装する Claude が、cooldown のジョブを作る前に「`workflow_dispatch` の実行から2つの環境変数を渡してスナップショットを送る」と書くが、どのワークフローで送るかが無い。Gradle のスナップショットを送るワークフローは dependency-review.yaml(PR のきっかけ)と dependency-graph.yaml(main への push だけ。34-36行)の2つで、どちらも `workflow_dispatch` を持たず、2つの環境変数も渡さない。`workflow_dispatch` は、既定のブランチにあるワークフローでしか起動できない。実装する Claude は `.github/` に書けないので、確かめには、所有者が置くワークフローが要る。それが、確かめのためだけのワークフローを先に main に入れるのか、`workflow_dispatch` を持つ今あるワークフローを一時のブランチで書き換えて、そのブランチで起動するのかで、PR の数と所有者の手の作業が変わる。tasks で、この確かめのタスクを書けない | 確かめに使うワークフロー(名前、置く場所、main に入れるか一時のブランチだけに置くか)、所有者が置く手順、確かめのあとに消すかどうかを、プロジェクトの決まりの箇条に書く。消すワークフローなら、ファイルの構成には載せず、その旨を書く |
| D2-2-5 | 低 | design.md claude-auto-fix.yaml「使う部品」 | `test-claude-auto-fix-workflows.sh` を流すのは dispatch ジョブだけである。`red-check` の実行は sweep ジョブが起動するので、このテストが0以外で終わっても、sweep ジョブは対象ごとの実行を起動する。「権限か秘密の値の渡し方が設計と違うワークフローで、Claude を動かさない」が、sweep の起動には効かない | sweep ジョブも、スクリプトの前にこのテストを流すと書く |

### 前の段階への指摘

なし

- 往復: 2回目 / 高0 中4 低1

## サイクル2 往復3(2026-11-14)

### 審査の範囲

範囲: 差分

- design.md 部品 claude-auto-fix.yaml「いつ動くか」(238行)と、処理の流れ「流れの上の決めごと」(224行): 差分が dispatch の `retry` の箇条(256行、259行)を「鍵の Issue が閉じてから25時間のうち」に直し、同じ表示名の実行を UTC の1日に1回にする決まりを理由に挙げたため。語 `retry` と「UTC」で検索して見つけた
- design.md 部品 claude-auto-fix-dispatch.sh「コンテナの検査の終わり」(254行)と「所有者の手での起動」(255行): 差分が、集め直しのコンテナの Issue を「コンテナの検査の終わりのときと同じく」、ほかの3つを「所有者の手での起動と同じ集め方」と書いたため
- design.md 部品 claude-auto-fix-report.sh「鍵の Issue」(485行)と「`key`」(489行)、データの形の目印(584行): 差分が、鍵の Issue の閉じた日時を Issue の API から読むと書いたため。鍵の Issue を誰がいつ閉じるかを見た
- design.md 部品 claude-auto-fix-prepare.sh「止める決まり」(339行): 集め直した対象が、dispatch の絞り込みのあとにどこで止まるかを見るため
- design.md 部品 claude-auto-fix-guard.sh(420-427行)、claude-auto-fix-verify.sh 手順2(441行)、claude-auto-fix-ship.sh「役割」と「呼び出し方」(465行、475行)、claude-auto-fix-prepare.sh「起点の作り直し」(343行): 差分が ship の「push の前のガード」を、起点のコミットに `final.patch` だけを当てたコミットで呼ぶと直したため。語「ガード」と `claude-auto-fix-guard.sh` で検索して見つけた
- design.md 部品 claude-auto-fix-target.yaml「失敗したとき」の表(322-329行)、claude-auto-fix-report.sh「失敗したとき」: 差分が prepare、materials、verified-claude、ship の「失敗したとき」から「report ジョブは `unavailable` として扱う」の文を消したため。表に同じ決まりが残っていることを確かめた
- design.md 部品 claude-auto-fix-target.yaml の cooldown-push、cooldown-generate、cooldown-submit(312-314行)、設計を見直すきっかけ(61行)、品質チェックの設定(67行)、ファイルの構成: 差分が maven の確認の手順(74-79行)を足し、確認のワークフローのジョブを「cooldown-generate と cooldown-submit と同じ2つ」と書いたため
- design.md 部品 claude-auto-fix-run-claude.sh(374-385行)と verified-claude(410-412行): 差分が、安全の節の「鍵の保護」と「CLI の入手」を、この2つの節を指す文に直したため。消した中身(`env -i`、2つの設定と拒否の決まり、`sk-ant-` の差分を捨てること、指紋と署名と SHA-256、版 2.1.323)が、指す先の節にすべてあることを確かめた
- design.md 作るもの(24-25行): 差分が概要から、vuln-fix の結果のファイルと dependency-cooldown の判定の形の文を消したため。同じことが作るものに残っていることを確かめた
- requirements.md 要件2の9、要件3の1と2、要件4の4、要件6の3と4: 差分が挙げた要件の番号のため
- そのほかの節(sweep、materials の役割、prompt.md、データの形の表、性能)は、差分の語が出てこないので読み直していない

### 実ファイルで確かめた文

- プロジェクトの決まり「Gradle のスナップショットを送る `dependency-review.yaml`(PR のきっかけ)と `dependency-graph.yaml`(main への push のきっかけ)は、どちらも `workflow_dispatch` を持たず、2つの環境変数も渡さない」: .github/workflows/dependency-review.yaml 31-33行、63行、109行、.github/workflows/dependency-graph.yaml 34-36行、61行、101行。`gradle/actions/dependency-submission` を使うワークフローはこの2つだけで、`GITHUB_DEPENDENCY_GRAPH` の語は `.github/workflows/` のどこにも無い / 合っていた
- プロジェクトの決まり「同じ版の `gradle/actions/dependency-submission` を `generate-and-upload` と `download-and-submit` で動かす」(今の版が1つに決まること): .github/workflows/dependency-review.yaml 63行、109行、.github/workflows/dependency-graph.yaml 61行、101行(4か所とも同じ SHA の v6.4.1) / 合っていた
- プロジェクトの決まり「1つ目のブランチは Claude が作って push する」「確認のワークフローは `push` の `branches: [chore/tmp-gradle-snapshot-check]` だけで動く」(2つのブランチの push で、今あるワークフローが動かないこと): `.github/workflows/` の `push` のきっかけは ci.yaml 8-9行、codeql.yaml 31-32行、dependency-graph.yaml 35-36行、sync-labels.yaml 32-33行、update-pr-branches.yaml 36-37行、container-scan-scheduled.yaml 76-77行の6つで、どれも `branches: [main]` である / 合っていた
- プロジェクトの決まり「`chore/tmp-gradle-snapshot-target` と `chore/tmp-gradle-snapshot-check`」(ブランチ名の決まりに合うこと): .branch_name_template 5行、16行、22-23行 / 合っていた
- 部品 claude-auto-fix-ship.sh「ガードは `check-escape-hatches.sh` を使い、`check-escape-hatches.sh` は2つのコミットの共通の祖先と head を比べる」: .github/scripts/check-escape-hatches.sh 49-50行、54行、64行 / 合っていた
- 同「Dependabot の PR が `.github/workflows/` の GitHub Actions の版を上げるときに、ガードが0以外で終わる」: .github/dependabot.yml 85-86行(`github-actions`、`directory: "/"`)、.github/scripts/check-escape-hatches.sh 217行(`.github/` をゲートの設定のファイルに数える) / 合っていた
- プロジェクトの決まり「`push` のきっかけでは、GitHub は push されたブランチのワークフローのファイルを動かす」「`workflow_dispatch` は、main にあるワークフローでしか起動できない」、plugin の README と gradle/actions の文書の記載、pnpm の PR #10618 のエラーの名前: 審査役が実行できるコマンドは `gh issue view` だけのため、確かめられなかった

### 受入基準ごとの確かめ方

| 受入基準 | 確かめる道具 | 動かす場所 | 動かすのに要るもの | design の箇所 |
|---|---|---|---|---|
| 2.9 | 実装の前の maven の確認(差分比較の API が main と1つ目のブランチのコミットの maven の差を返すこと、2つ目のブランチのコミットにスナップショットが結び付いていないこと)、test-claude-auto-fix-workflows.sh(2つの環境変数)、test-claude-auto-fix-verify.sh(pnpm の止まり方) | GitHub Actions の実行(2つ目のブランチへの push)、コンテナ | 2つの一時のブランチ、所有者が置く確認のワークフロー `.github/workflows/tmp-gradle-snapshot-check.yaml`、1つ目のブランチのコミットの SHA と `refs/heads/chore/tmp-gradle-snapshot-target`、yq、偽の pnpm | プロジェクトの決まり「使う外部の機能がこのリポジトリで使えるか」の maven の箇条(73-79行)、テストの方針 結合テスト。確認のワークフローが checkout するコミットは「cooldown-generate と同じ」としか書かれていない(D2-3-1) |
| 3.1 | test-claude-auto-fix-guard.sh、test-claude-auto-fix-ship.sh(`final.patch` に `.github/` の変更があれば push しない。種類が `dependabot` で `base.patch` だけが `.github/workflows/` を変えるときは push する) | コンテナ | git のリポジトリ(起点のコミットと、`final.patch` だけを当てたコミット)、偽の git push、偽の gh | 部品 ship「push の前のガード」(470行)、テストの方針 結合テスト(616行) |
| 3.2 | test-claude-auto-fix-guard.sh、test-claude-auto-fix-ship.sh(足した `@SuppressWarnings` で push しない) | コンテナ | 同上 | 部品 ship「push の前のガード」、テストの方針 結合テスト |
| 4.4 | test-claude-auto-fix-dispatch.sh(集め直しで、`unfixed` の Issue がある key と、直せなかったことを書いたコメントが付いたコンテナの Issue が起動されない) | コンテナ | 偽の gh(鍵の Issue の閉じた日時、知らせの Issue、目印のコメント) | 部品 dispatch「絞り込みの決まり」の2つ目(267行)、テストの方針 結合テスト(610行) |
| 6.4 | test-claude-auto-fix-dispatch.sh(4日より前に `key` で終わった対象が、鍵の Issue が閉じてから25時間のうちの `retry` で起動され、25時間を過ぎると集め直さない。1度扱ったコンテナの Issue は起動されない) | コンテナ | 偽の gh(鍵の Issue の閉じた日時)、今の時刻 | 部品 dispatch「鍵の Issue が閉じてから25時間のうちの `retry`」(259行)、テストの方針 結合テスト(610行) |

### 申告

差分で新しく増えた申告は無い。サイクル2 往復1 の申告の1から9と、往復2 の申告の1と2は、中身が変わっていない。往復2 の申告の1(maven の実測を承認のあとの実装の最初に回す)には、差分で手順が足された。所有者の手の作業は、確認のワークフローのファイルを2つ目のブランチに置いて push する1回である。

### 指摘

| ID | レベル | 該当箇所 | 内容 | 直し方の案 |
|---|---|---|---|---|
| D2-3-1 | 低 | design.md プロジェクトの決まり「使う外部の機能がこのリポジトリで使えるか」の maven の箇条(76行) | 確認のワークフローのジョブを「cooldown-generate と cooldown-submit と同じ2つにし」と書くが、スナップショットを作るジョブがどのコミットを checkout するかを、この箇条では書いていない。`push` のきっかけの既定の checkout は、2つ目のブランチ(main と同じ依存)である。cooldown-generate の節は「一時のブランチを checkout し」と書くので、同じにすれば1つ目のブランチを checkout することになり、読み取れる。既定のまま作ると、1つ目のブランチのコミットに main と同じ依存のスナップショットが結び付き、maven の差が返らず、設計を見直すきっかけに誤って当たる。差が返らないことで必ず気づくので、実装には影響しない | 76行に「スナップショットを作るジョブは、1つ目のブランチのコミットを checkout する」と書く |

### 前の段階への指摘

なし

- 往復: 3回で収束 / 未解決: 0件

## サイクル3 往復1(2026-11-14)

### 審査の範囲

範囲: 差分

- design.md 部品 claude-auto-fix-sweep.sh「赤の検査の扱い」「3回続いた赤の扱い」「対象が消えた PR を閉じる」(291-293行)と「使う部品」(301行): 差分が report の節に「PR を閉じる扱い」(508-511行)を足し、PR を閉じるのは sweep だけで、開いたまま残った PR を sweep が動かし直さないと書いたため。語「PR を閉じ」と「head のコミット」で検索して見つけた
- design.md 部品 claude-auto-fix.yaml「権限」(234行): 差分が、sweep ジョブが `pull-requests: write` と `contents: write` を持つと書いたため。合っていた
- design.md 部品 claude-auto-fix-dispatch.sh「絞り込みの決まり」の1つ目(272行)と、部品 claude-auto-fix-prepare.sh「止める決まり」(350行): `red-check` の `unfixed` のあとに、開いたままの PR と `unfixed` の知らせの Issue の両方がある key が、そのあとどう扱われるかを見るため
- design.md 部品 claude-auto-fix-target.yaml「役割」(309行)と「失敗したとき」の表(333-340行): 差分が report の呼び出し方に `JOB_RESULTS` と `EDIT_OUTCOME` を足したため。表と合っていた
- design.md 部品 claude-auto-fix-materials.sh の `container` の材料(371行)と「呼び出し方」(377行)、claude-auto-fix-target.yaml の edit ジョブ(320行): 差分が prepare の呼び出し方に、Trivy の結果を受け取る `TRIVY_RESULTS_DIR` を足したため。語「Trivy の結果」で検索すると、同じ結果を使う箇所がもう1つ(materials)あった
- design.md 全体の構成(131行、133行)、claude-auto-fix-target.yaml の ship ジョブ(327行)、claude-auto-fix-dispatch.sh「役割」(250行)、claude-auto-fix-materials.sh(375行): 差分が安全の節の「想定する脅威」と「書き込みの権限」を、これらの節を指す文に直したため。消した中身が、指す先の節にすべてあることを確かめた
- design.md 使う既存の仕組み(38行)、vuln-fix の変更(542行): 差分がファイルの構成に `digest` を足したため。3か所とも4つの関数になった
- design.md 処理の流れ「流れの上の決めごと」(223-224行): 差分が、sweep が次の実行を起動する文を消したため。同じことが224行の「必須の検査の赤」と sweep の節に残っていることを確かめた
- requirements.md 要件2の4と5と8、要件4の1と3と4、要件6の2と3: 差分が挙げた要件の番号と、PR を閉じる扱いが関わる要件のため
- tasks.md 320行と325行: 差分が直した置き場所と3つの環境変数が、tasks の実装のメモと同じ名前かを見るため。同じだった
- 箇条に分け直しただけの箇所(dispatch の25時間の `retry`、prepare ジョブ、ship の push の前のガード、テストの方針の5つのテスト)は、分ける前の文と1つずつ比べ、中身が落ちていないことと、「次の6つ」「次の5つ」「次の4つ」「次の3つ」の数が箇条の数と合うことを確かめた
- そのほかの節(run-claude、prompt.md、verified-claude、guard、verify の手順、データの形、性能)は、差分の語が出てこないので、指摘の対象にしていない

### 実ファイルで確かめた文

- プロジェクトの決まり「作業フォルダの中の、Git が無視するフォルダ `.claude/.state/claude-auto-fix-unresolved-alerts/`」: .gitignore 7行(`.claude/.state/`) / 合っていた
- ファイルの構成「backend では `tree` `vulncheck` `go_bump` `digest` を外から呼べるようにする」(4つの関数が今あり、今は外から呼べないこと): .github/scripts/backend-vuln-fix.sh 85行、156行、158行、161行、246-249行(呼べるのは run、go_run、plan、resolved、vulnerable、decide、pin、go_plan) / 合っていた
- 部品 claude-auto-fix-target.yaml prepare「`container-scan.yaml` の `container-scan` ジョブと同じランナー(`ubuntu-24.04-arm`)と組み立て方(`docker buildx build --platform linux/arm64`)、2つの Dockerfile.prod、組み立ての文脈は `./backend`」: .github/workflows/container-scan.yaml 159行、220-232行 / 合っていた
- 同「`verified-trivy` 0.76.2」: .github/workflows/container-scan.yaml 46行、198行、.github/workflows/container-scan-scheduled.yaml 99行 / 合っていた
- 部品 claude-auto-fix-prepare.sh「Trivy の結果を `check-container-scan.sh` の `report` で判定する」: .github/scripts/check-container-scan.sh 75行 / 合っていた
- 部品 claude-auto-fix-ship.sh「`check-escape-hatches.sh` は2つのコミットの共通の祖先と head を比べる」「Dependabot の PR が `.github/workflows/` の GitHub Actions の版を上げるときに、ガードが0以外で終わる」: .github/scripts/check-escape-hatches.sh 54行、217行、.github/dependabot.yml 85行 / 合っていた
- テストの方針 dispatch「frontend-test と escape-hatch が赤の PR は起動され、入力 `checks` が frontend-test だけになる」「dependency-review と escape-hatch の2つの PR が外れる」(検査の名前と `approval_gated` の値): .github/audit/required-checks.json 3行、6行、18行、19行、23行、24行 / 合っていた
- テストの方針 verify「ci.yaml の `detect-changes` ジョブの `filters`」: .github/workflows/ci.yaml 22行、55行 / 合っていた
- テストの方針 workflows「手元では、`.github/CLAUDE.md` の alpine のコンテナの `apk add` に `yq` を足して流す」: .github/CLAUDE.md 23行、62行 / 合っていた
- プロジェクトの決まり「scratchpad が会話ごとに別のフォルダである」、テストの方針「ランナーのイメージ 20261111.370.1 の一覧に、yq 4.54.3 がある」: 審査役が実行できるコマンドは `gh issue view` だけのため、確かめられなかった

### 受入基準ごとの確かめ方

| 受入基準 | 確かめる道具 | 動かす場所 | 動かすのに要るもの | design の箇所 |
|---|---|---|---|---|
| 2.2 | test-claude-auto-fix-report.sh(ジョブが結果を出さずに止まったときの結果が表のとおりになる) | コンテナ(alpine に bash と jq) | 偽の gh、環境変数 `JOB_RESULTS`(ジョブの名前を鍵にした JSON) | 部品 report「呼び出し方」(515行)、部品 target.yaml の report ジョブ(328行)と「失敗したとき」の表、テストの方針 結合テスト(664行) |
| 2.4 | test-claude-auto-fix-sweep.sh | コンテナ | 偽の gh(同じ head のコミットについての実行の一覧) | 部品 sweep「赤の検査の扱い」(291行)、部品 report「PR を閉じる扱い」の3つ目(511行)。同じ head の実行があるときに起動しない場合は、テストの方針に無い(D3-1-2) |
| 2.5 | test-claude-auto-fix-sweep.sh(3回続いた赤で PR を閉じ、閉じた PR の URL を書いた知らせを書く)、test-claude-auto-fix-report.sh(`red-check` の `unfixed` で PR を閉じず、知らせに PR の URL を書く) | コンテナ | 偽の gh(末尾の行つきのコミット) | 部品 sweep「3回続いた赤の扱い」(292行)、部品 report の `unfixed`(502行)と「PR を閉じる扱い」(508-511行)、テストの方針 結合テスト(643行、663行) |
| 2.8 | test-claude-auto-fix-prepare.sh(偽の Trivy の結果に脆弱性の ID が無ければ `gone`)、test-claude-auto-fix-report.sh(`gone` のコメントが1回だけ付く) | コンテナ | 偽の gh、環境変数 `TRIVY_RESULTS_DIR` のフォルダに置く偽の Trivy の結果 | 部品 prepare「呼び出し方」(356行)、テストの方針 結合テスト(651行、660行) |
| 3.3 | test-claude-auto-fix-workflows.sh(ジョブごとの権限が「ジョブごとの権限と動き」と同じ。report ジョブは `pull-requests: read`) | コンテナ(yq を足す)、dispatch ジョブ | yq | 部品 target.yaml の report ジョブ(328行)、テストの方針 結合テスト(674行) |
| 3.5 | test-claude-auto-fix-materials.sh | コンテナ | 偽の gh。種類が `container` のときは、prepare ジョブの Trivy の結果のファイル | 部品 materials の `container`(371行)。edit ジョブと materials が Trivy の結果を受け取る道は無い(D3-1-1) |
| 6.2 | test-claude-auto-fix-report.sh(状態が `unavailable` の知らせの Issue が開いているときの `unfixed` で、新しい Issue を起票せず、コメントを付け、最も新しい目印の状態が `unfixed` になる) | コンテナ | 偽の gh(目印つきの Issue) | 部品 report の `unfixed`(502行)、テストの方針 結合テスト(662行) |
| 6.3 | test-claude-auto-fix-report.sh(edit ジョブが `ok` を出して結果が `blocked` の実行でも、鍵の Issue が閉じられる) | コンテナ | 偽の gh、環境変数 `EDIT_OUTCOME` | 部品 report「鍵の Issue」(500行)と「呼び出し方」(515行)、テストの方針 結合テスト(659行) |

### 申告

**1. Claude の変更の PR の赤を Claude が直せなかったときは、PR を閉じず、開いたまま残す** — design.md claude-auto-fix-report.sh「PR を閉じる扱い」(508-511行)

- Issue の記載: なし。要件2の5は、同じ必須の検査が3回続けて赤になったときに PR を閉じると決めている。1回目か2回目の赤で Claude が直せなかったときの扱いは、要件にも無い
- 決めたこと: `reason` が `red-check` の実行が `unfixed` で終わったときは、PR を閉じない。仕組みは、PR の URL を書いた知らせの Issue を起票する。sweep は、head のコミットが変わらない間、その PR について Claude を動かし直さない。サイクル2 往復1 の申告の2(1回目の赤でも PR を閉じる)は、この決定に置き換わった
- 他にありえた選択肢: `red-check` の `unfixed` でも sweep が PR を閉じる。または、次の日にもう一度 Claude を動かす
- 外れていた場合: 赤のままの PR が、対象が消えるか所有者が手で閉じるまで開いたまま残る。その間、同じ key には開いている Claude の変更の PR があるので、所有者が手で仕組みを動かしても、その対象では Claude が動かない(dispatch の絞り込みの1つ目)。同じ key に、開いている PR と知らせの Issue の両方がある状態になる。Issue #725 は「同じ部品と版の組の PR か Issue が開いているときは、仕組みは新しく作らない」と書いている。たまたま落ちた検査の赤では、所有者が検査を動かし直せば PR は通り、マージのあとに sweep が知らせの Issue を閉じる

**2. `.github/` のファイルを、scratchpad ではなく `.claude/.state/` の下に作る** — design.md プロジェクトの決まり「品質チェックの設定」(67行)

- Issue の記載: なし
- 決めたこと: 実装する Claude は、完成版を `.claude/.state/claude-auto-fix-unresolved-alerts/` の下に作る。`.github/CLAUDE.md` 10行は「完成版を scratchpad で作り」と書いている。design は、会話を開き直すとファイルが失われることを理由に、これと違う場所を選んだ
- 他にありえた選択肢: `.github/CLAUDE.md` のとおり scratchpad に作る
- 外れていた場合: 影響は小さい。フォルダは Git が無視するので、コミットに入らない。worktree を消すとファイルも消えるが、消すのは所有者がファイルを写してマージしたあとである

サイクル2 往復1 の申告の1と3から8、往復2 の申告の1と2は、差分で変わっていない。

### 指摘

| ID | レベル | 該当箇所 | 内容 | 直し方の案 |
|---|---|---|---|---|
| D3-1-1 | 中 | design.md claude-auto-fix-materials.sh の `container` の材料(371行)と「呼び出し方」(377行)、claude-auto-fix-target.yaml の prepare ジョブと edit ジョブ(319-320行) | 差分は、prepare の呼び出し方に `TRIVY_RESULTS_DIR` を足して、T1-1-10 の「役割の文が使うと書く入力が、呼び出し方に無い」を直した。同じ Trivy の結果を使う箇所がもう1つ残っている。materials は、種類が `container` のとき「prepare ジョブの Trivy の結果のうちその ID の行」を材料にすると書くが、呼び出し方は `<kind> <key> <reason> <pr> <checks> <detail>` だけで、Trivy の結果のファイルを受け取る入力が無い。materials は edit ジョブで動き、Trivy の結果を作るのは別のジョブ(prepare。`ubuntu-24.04-arm`)である。prepare ジョブが Trivy の結果を成果物として上げることも、edit ジョブがそれを受け取ることも、ジョブの節に書かれていない。今の tasks.md の材料のタスク(105行)と実装のメモ(325行)も、この入力を補っていない。design のとおりに作ると、コンテナの対象の材料に Trivy の行を入れる道が無く、実装のときに design に戻ることになる | prepare ジョブの箇条に、種類が `container` のときは Trivy の結果を成果物として上げると書く。edit ジョブに、その成果物を受け取ると書く。materials の呼び出し方に、種類が `container` のときは結果のファイルのフォルダを環境変数 `TRIVY_RESULTS_DIR` で受け取ると書く。テストの方針の `test-claude-auto-fix-materials.sh` に、種類が `container` のとき、偽の Trivy の結果のうちその ID の行だけが材料に入る場合を足す |
| D3-1-2 | 低 | design.md テストの方針の `test-claude-auto-fix-sweep.sh`(641-646行)と `test-claude-auto-fix-workflows.sh`(673-680行) | (1) 差分が足した「PR を閉じる扱い」の3つ目は、開いたまま残った PR を sweep が動かし直さないことを、sweep の「その head のコミットについての実行がすでにあるときは、何もしない」に頼っている。この場合が、sweep のテストの5つの場合に無い。(2) 差分は、report ジョブが `EDIT_OUTCOME` と `JOB_RESULTS` を、prepare ジョブが `TRIVY_RESULTS_DIR` を渡すと書いたが、ワークフローがこの3つを渡すことを確かめる場合が、workflows のテストに無い。`PNPM_WORKSPACE_FILE` と `GITHUB_DEPENDENCY_GRAPH_SHA` の渡し方は、同じテストで確かめている。今の tasks.md(219行、237行、242行)は、どちらの場合もテストに入れているので、実装には影響しない | sweep のテストに「必須の検査がまだ動いているときと、同じ head のコミットについての実行があるときは起動されないこと」を足す。workflows のテストに「report ジョブが `EDIT_OUTCOME` と `JOB_RESULTS` を渡し、prepare ジョブが `TRIVY_RESULTS_DIR` を渡すこと」を足す |
| D3-1-3 | 低 | design.md claude-auto-fix-report.sh の `unfixed`(502行)と、種類が `codeql` の箇条(506行)、テストの方針(661行、663行) | 502行は、`reason` が `red-check` のときと sweep から受け取ったときに、知らせに PR の URL を書くと書く。506行は、種類が `codeql` の Issue とコメントを「決まった文と警告の URL だけで書く」と書き、テストの方針の661行は「警告の URL のほかの中身が入らないこと」を確かめると書く。種類が `codeql` の PR で `red-check` が `unfixed` になったときに、PR の URL を書くのかが、2つの文で食い違って読める。要件5の1が禁じるのは、Claude が書いた文と、警告のファイルの名前、行、規則の名前、警告の説明で、PR の URL は入っていない。要件2の5は、閉じた PR の URL を書くことを求めている | 506行を「決まった文と、警告の URL と、PR の URL だけで書く」に直し、661行の場合も同じに直す |

### 前の段階への指摘

なし

- 往復: 1回目 / 高0 中1 低2

## サイクル3 往復2(2026-11-14)

### 審査の範囲

範囲: 差分

- design.md 部品 claude-auto-fix-target.yaml の prepare ジョブ(319行)と edit ジョブ(320-325行)、部品 claude-auto-fix-materials.sh の `container` の材料(386行)と「呼び出し方」(392行)、部品 claude-auto-fix-prepare.sh「呼び出し方」(371行): 差分が、prepare ジョブが Trivy の結果を成果物 `trivy-results` として上げ、edit ジョブが受け取って `TRIVY_RESULTS_DIR` で materials に渡すと書いたため(D3-1-1 の直し)。語 `trivy-results` と `TRIVY_RESULTS_DIR` と「Trivy の結果」で検索して見つけた。上げる側、受け取る側、materials の呼び出し方、テストの方針(642行)の4か所が同じ名前でつながっていることを確かめた
- design.md 部品 claude-auto-fix-target.yaml の cleanup ジョブ(344行)、全体の構成(131行)、安全「CodeQL の警告の中身」(708行): 差分が成果物を1つ足したため。語「成果物」で検索して見つけた。cleanup ジョブは `outcome` のほかの成果物をすべて消すので、`trivy-results` も実行の最後に消える。保存の期間の1日は、ほかの受け渡しの成果物(708行)と同じである。edit ジョブの権限(321行)は変わらず、書き込みの権限は足されていない
- design.md 部品 claude-auto-fix-report.sh の `gone`(523行)、requirements.md 要件2の8(92行): 差分が prepare の節の「コンテナの対象」(367行)から、コメントの中身を書いた1文を消したため。語「リリースすれば」で検索し、消した中身(main では消えていて、所有者がリリースすれば本番でも消える)が report の節の `gone` に残っていることを確かめた
- design.md テストの方針の `test-claude-auto-fix-workflows.sh`(691-698行): 差分が edit ジョブに、成果物を受け取って環境変数で渡す動きを足したため。この渡し方を確かめる場合があるかを見た(D3-2-1)
- 箇条に分け直した箇所(edit ジョブ、verify ジョブ、cooldown-judge ジョブ、verify の手順1の pnpm)は、分ける前の文と1つずつ比べ、中身が落ちていないことと、「次の5つ」「次の6つ」「次の4つ」「次の3つ」の数が箇条の数と合うことを確かめた。prepare ジョブの「次の5つ」も、足した文が5つ目の箇条の中にあるので、数は合っている
- 主語を足した文(76行、78行、79行、234行、253行、254行、273行、291行、309行、366行)は、直す前の文と比べ、意味が変わっていないことを確かめた。273行は、決まりを掛ける対象(`reason` が `trigger` のときと、鍵の Issue が閉じてから25時間のうちの `retry` で集め直した対象)が、直す前と同じである。291行は「実行」を「対象ごとの実行」に直しただけで、サイクル3 往復1 で見た sweep の動きと同じである
- そのほかの節(dispatch の集め方、sweep の後始末、run-claude、prompt.md、verified-claude、guard、ship、report のほかの結果、データの形、性能)は、差分の語が出てこないので、読み直していない

### 実ファイルで確かめた文

- 部品 claude-auto-fix-target.yaml prepare「`container-scan.yaml` の `container-scan` ジョブと同じランナー(`ubuntu-24.04-arm`)と組み立て方」「`verified-trivy` 0.76.2」「調べた結果のファイル」(今の検査が、イメージごとに Trivy の結果を JSON のファイルに書くこと): .github/workflows/container-scan.yaml 46行、159行、180行、185行、224行、231行、250行、255行 / 合っていた
- 部品 claude-auto-fix-prepare.sh「Trivy の結果を `check-container-scan.sh` の `report` で判定する」(結果のファイルを引数で受け取ること): .github/scripts/check-container-scan.sh 51行、75行 / 合っていた
- 部品 claude-auto-fix-dispatch.sh「定期のコンテナの検査は、毎日と、本番のリリースのあとと、`backend/` か `docker/backend-go/` を変えた main への push のあとに動く」: .github/workflows/container-scan-scheduled.yaml 53-81行 / 合っていた
- 部品 claude-auto-fix-dispatch.sh と sweep「期待一覧で `approval_gated` が true の検査は escape-hatch、dependency-gate、pre-merge-check、dependency-cooldown。`dependency-review` は期待一覧に載る」: .github/audit/required-checks.json 6行、18行、19行、23行、24行 / 合っていた
- 部品 claude-auto-fix.yaml「GITHUB_TOKEN での `workflow_dispatch` は新しい実行を作る」、プロジェクトの決まり「`push` のきっかけでは、GitHub は push されたブランチのワークフローのファイルを動かす」: 審査役が実行できるコマンドは `gh issue view` だけのため、確かめられなかった。どちらも、差分で文の形だけが変わり、中身は前の往復と同じである

### 受入基準ごとの確かめ方

| 受入基準 | 確かめる道具 | 動かす場所 | 動かすのに要るもの | design の箇所 |
|---|---|---|---|---|
| 2.8 | test-claude-auto-fix-prepare.sh(偽の Trivy の結果に脆弱性の ID が無ければ `gone`)、test-claude-auto-fix-report.sh(`gone` のコメントが1回だけ付く) | コンテナ(alpine に bash と jq) | 偽の gh、環境変数 `TRIVY_RESULTS_DIR` のフォルダに置く偽の Trivy の結果 | 部品 prepare「コンテナの対象」(367行)と「呼び出し方」(371行)、部品 report の `gone`(523行)、テストの方針 結合テスト(669行、678行) |
| 3.3 | test-claude-auto-fix-workflows.sh(ジョブごとの権限が「ジョブごとの権限と動き」と同じ。edit ジョブに書き込みの権限が無い) | コンテナ(yq を足す)、dispatch ジョブ | yq | 部品 target.yaml の edit ジョブ(320-325行)、テストの方針 結合テスト(692-694行) |
| 3.5 | test-claude-auto-fix-materials.sh(種類が `container` のとき、偽の Trivy の結果のうち、その脆弱性の ID の行だけが材料に入る) | コンテナ | 偽の gh、環境変数 `TRIVY_RESULTS_DIR` のフォルダに置く偽の Trivy の結果 | 部品 materials の `container`(386行)と「呼び出し方」(392行)、部品 target.yaml の prepare ジョブ(319行)と edit ジョブ(325行)、テストの方針 単体テスト(642行)。ワークフローが成果物を受け渡すことを確かめる場合は無い(D3-2-1) |

### 申告

差分で新しく増えた申告は無い。サイクル3 往復1 の申告の1と2、サイクル2 往復1 の申告の1と3から8、往復2 の申告の1と2は、差分で変わっていない。

### 指摘

| ID | レベル | 該当箇所 | 内容 | 直し方の案 |
|---|---|---|---|---|
| D3-2-1 | 低 | design.md テストの方針の `test-claude-auto-fix-workflows.sh`(691-698行)、claude-auto-fix-target.yaml の prepare ジョブ(319行)と edit ジョブ(325行) | (1) 差分は、prepare ジョブが成果物 `trivy-results` を上げ、edit ジョブが受け取って `TRIVY_RESULTS_DIR` で materials に渡すと書いたが、ワークフローがこの受け渡しをすることを確かめる場合が、workflows のテストに無い。D3-1-2 の(2)(3つの環境変数を渡すことを確かめる場合が無い)と同じ種類の抜けで、D3-1-2 は、タスクを作り直すときにテストに入れると記録されている。(2) フォルダ `TRIVY_RESULTS_DIR` の中の、2つのイメージの結果のファイルの名前が書かれていない。ワークフロー(上げる側)と prepare.sh と materials.sh(読む側)が同じ名前を使う必要がある。3つとも同じ spec で作るので、タスクで名前を決めれば足り、design に戻ることにはならない | タスクを作り直すときに、workflows のテストに「種類が `container` のとき、prepare ジョブが成果物 `trivy-results` を上げ、edit ジョブが受け取って `TRIVY_RESULTS_DIR` を渡すこと」を足す。2つの結果のファイルの名前を、タスクの実装のメモに書く |

### 前の段階への指摘

なし

- 往復: 2回で収束 / 未解決: 0件

## サイクル4 往復1(2026-11-14)

### 審査の範囲

範囲: 差分

- design.md 部品 claude-auto-fix-target.yaml の verify ジョブ(327-338行)と、部品 claude-auto-fix-verify.sh の「役割」「呼び出し方」(468行、480行、495-501行): 差分が、`claude-auto-fix-verify.sh` を `apply` `check` `confirm` の3つの形に分け、verify ジョブの6つの手順を書いたため。語 `apply` `check` `confirm` `areas` `CODEQL_SARIF_DIR` で検索し、ジョブの手順、スクリプトの呼び出し方、テストの方針(708-709行、720行)の3か所が同じ名前でつながっていることを確かめた
- design.md 部品 claude-auto-fix-verify.sh の手順1(470-478行)と手順4(486-493行)、.github/scripts/backend-vuln-fix.sh の `tree` `vulncheck` `digest` `go_bump`: 差分が、道具を入れる手順を2つ(手順1と手順3)に分け、手順3で入れる道具を「変わった領域の道具だけ」にしたため。`apply` と `confirm` が呼ぶコマンドに要る道具が、その前の手順で入るかを見た。入る(下の「実ファイルで確かめた文」)
- design.md 部品 claude-auto-fix-ship.sh「push の前のガード」(514-518行): 差分が、`final.patch` と SHA-256 を、品質チェックの前の `apply` が書くと直したため。`check` で動いたコードが `final.patch` を書き換えても、ship が SHA-256 を照らし、ガードをもう一度呼ぶ作りは変わっていない
- design.md 部品 claude-auto-fix-target.yaml の report ジョブ(349-352行)と「失敗したとき」(357-366行)、部品 claude-auto-fix-report.sh の「役割」「呼び出し方」(531行、548-553行)、部品 claude-auto-fix-sweep.sh「3回続いた赤の扱い」(293行)、データの形の結果のファイル(638行): 差分が、`claude-auto-fix-report.sh` を `record` と `notify` に分けたため。語 `record` `notify` `outcome.json` `JOB_RESULTS` `EDIT_OUTCOME` で検索して見つけた。366行から消した文(結果のファイルを Issue とコメントを書く前に上げる)は、349行に理由つきで残っている
- design.md ファイルの構成の `.github/actionlint.yaml`(175行)、部品 claude-auto-fix.yaml「権限」(235行)、部品 claude-auto-fix-target.yaml の prepare、edit、cooldown-judge の権限(316行、322行、344行)、プロジェクトの決まり「品質チェックの設定」(67行): 差分が、`.github/actionlint.yaml` に無視の行を足すと書いたため。語 `vulnerability-alerts` で検索し、2つのワークフローのどちらにも、この権限を持つジョブがあることを確かめた
- design.md 安全の節(728-732行)と、指す先の節(dispatch 251行、materials 399行、run-claude 411-412行、verify 501行、ship 512行、report 539行): 差分が、安全の節の3つの箇条を、部品の節を指す文に直したため。消した中身が、指す先の節にすべてあることを確かめた。「書き込みの権限」の箇条(731行)は、本文のファイルの行(`claude-auto-fix-ship.sh` の節を指す)を正として読んだ。この行は差分で変わっていない
- design.md 部品 claude-auto-fix-dispatch.sh「1時間ごとの定期実行」の `unavailable` と `blocked`(258行): 差分が、verify の手順1から「dispatch の `retry` が、次の日にその対象を動かし直す」の文を2か所消したため。同じことが258行に残っていることを確かめた
- requirements.md 要件2の2と5と9、要件5の2、要件6の1: 差分が挙げた要件の番号と、分けた2つのスクリプトが関わる要件のため
- 主語を足しただけの文(67行、273-276行)と、「結果のファイル」を「vuln-fix の結果のファイル」に直した文(168-170行、582行、666行)は、直す前の文と比べ、意味が変わっていないことを確かめた。「次の5つ」(verify ジョブ)、「次の6つの手順」、「次の3つの手順」(report ジョブ)の数は、箇条の数と合っている
- そのほかの節(dispatch の集め方、sweep のほかの後始末、prepare、materials、run-claude、prompt.md、verified-claude、guard、lib、cooldown のジョブ、性能)は、差分の語が出てこないので、読み直していない

### 実ファイルで確かめた文

- ファイルの構成「`.github/actionlint.yaml` に、`dependency-review.yaml` と同じ形で無視の行があり、ファイルの先頭に説明の文がある」: .github/actionlint.yaml 1-10行(説明の文)、11-14行(`paths` の下に、ファイルごとの `ignore` と `'unknown permission scope "vulnerability-alerts"'`) / 合っていた
- 同「CI が使う actionlint 1.7.12 は権限 `vulnerability-alerts` を知らず、足さないと guardrails の actionlint が赤になる」: .github/workflows/guardrails.yaml 40-44行(`rhysd/actionlint:1.7.12`)、.github/actionlint.yaml 3-5行、.github/workflows/dependency-review.yaml 174行、.github/workflows/frontend-vuln-fix.yaml 7行(「GITHUB_TOKEN の vulnerability-alerts は actionlint が知らない」) / 合っていた。`actionlint.yaml` の中身を確かめるテストは、`.github/` の下に無い
- 部品 target.yaml の verify の手順1と verify.sh の手順3の `frontend`「pnpm は `pnpm/action-setup` v6.1.1 に `package_json_file` を渡して入れ、Node.js は `verified-node` で 24.22.2 を入れる」: .github/workflows/ci.yaml 221-231行 / 合っていた
- 部品 target.yaml の verify の手順3「`backend_java` では Java 21、`backend_go` では `go.mod` の Go と `golangci-lint-action` の `install-only`、`backend_compat` では poppler-utils」: .github/workflows/ci.yaml 345-349行、432-446行、499-502行 / 合っていた
- 同 手順3「`apply` が出した変わった領域の道具だけを入れる」(`confirm` が呼ぶコマンドの道具が、変わった領域の道具に入ること): .github/scripts/backend-vuln-fix.sh 85-88行(`tree` は `./gradlew` を動かす)、156行(`vulncheck` は `go tool govulncheck` を `GOTOOLCHAIN=auto` で動かす)、.github/workflows/ci.yaml 67-72行(`backend/gradle/**` は `backend_java` に当たる)、74-77行(`backend/go.mod` は `backend_go` に当たる) / 合っていた。種類が `maven` の変更は `backend_java` に当たるので、`confirm` の前に Java が入る
- 同 手順1「派生のファイルの作り直しに要る道具」(`digest` と `go_bump` が要る道具): .github/scripts/backend-vuln-fix.sh 158行(`docker buildx imagetools inspect` と jq)、161-176行 / 合っていた。docker と jq はランナーにあり、Go は手順1で入る
- 同 手順5「`codeql.yaml` と同じ版の `init` と `analyze`」「`analyze` は `upload: never` と `upload-database: false`」「`category` から言語を選ぶ」「言語の準備とビルドは `codeql.yaml` の analyze ジョブと `.github/codeql/languages.tsv` のとおり」: .github/workflows/codeql.yaml 74-78行(コードを最上位に checkout する)、80-85行(`java-kotlin` のときの JDK 21)、88行と105行(v4.39.3)、95-101行(ビルドの命令)、107行(`/language:<言語>`)、109-111行、.github/codeql/languages.tsv 10行(ビルドの命令は「作業フォルダの最上位で bash が動かす」)、23行、44行 / 書いてある値は合っていた。ただし、今の analyze ジョブは、診断するコードを最上位に checkout している。verify ジョブでは、診断するコードが `target/` にあり、最上位には main のコードがある。この違いを埋める指定が design に無い(D4-1-1)
- 部品 target.yaml の verify「アクションはスクリプトの途中で動かせない」: 審査役が実行できるコマンドは `gh issue view` だけのため、確かめられなかった

### 受入基準ごとの確かめ方

| 受入基準 | 確かめる道具 | 動かす場所 | 動かすのに要るもの | design の箇所 |
|---|---|---|---|---|
| 2.2 | test-claude-auto-fix-verify.sh(`apply` が `final.patch` と `areas` を出す。`check` が同じ領域を決め直し、その領域の品質チェックだけを流す。種類ごとの `unfixed` と `ok`)、test-claude-auto-fix-workflows.sh(verify ジョブの6つの手順の並びと、あとの手順を飛ばすこと) | コンテナ(alpine に bash と jq。workflows は yq を足す)、dispatch ジョブ | 偽の `vulnerable` `tree` `vulncheck` `go_plan` `digest`、偽の pnpm と偽の docker、yq | 部品 target.yaml の verify ジョブ(331-338行)、部品 verify.sh「呼び出し方」(495-499行)、テストの方針 結合テスト(705-709行、720行)。あとの手順を飛ばす条件の書き方が、`check` の `outcome=ok` と合わない(D4-1-2) |
| 2.5 | test-claude-auto-fix-sweep.sh(3回続いた赤で PR を閉じ、`notify unfixed` で閉じた PR の URL を書いた知らせを書く) | コンテナ | 偽の gh | 部品 sweep「3回続いた赤の扱い」(293行)、部品 report「呼び出し方」(553行)、テストの方針 結合テスト(681行) |
| 2.9 | test-claude-auto-fix-verify.sh(npm の `wait` と、pnpm の止まり方で `blocked`) | コンテナ | 偽の `decide`、偽の pnpm | 部品 verify.sh 手順1(471行、474行)と `apply` の出力(497行)、テストの方針 結合テスト(710-711行) |
| 5.2 | test-claude-auto-fix-verify.sh(`confirm` が `CODEQL_SARIF_DIR` の偽の SARIF を読む)、test-claude-auto-fix-workflows.sh(手順の並び)。CodeQL の `init` と `analyze` の実際の動きは、main に入ったあとの実行 | コンテナ、dispatch ジョブ、main に入ったあとの実行 | 偽の SARIF、警告の規則の ID とファイルと `category`(verify の最初の手順が `$RUNNER_TEMP` に書く)、`target/` のコードを診断した SARIF | 部品 target.yaml の verify ジョブの手順5と6(336-337行)、部品 verify.sh 手順4と `confirm`(491行、499行)、テストの方針 結合テスト(708行)。`init` と `analyze` に `target/` のコードを診断させる指定は無い(D4-1-1) |
| 6.1 | test-claude-auto-fix-report.sh(`record` が結果を結果のファイルに書き、Issue の API を呼ばない。`notify` が結果のファイルを書かない。3つの違う日の `unavailable` で Issue が1つだけ起票される)、test-claude-auto-fix-workflows.sh(report ジョブの3つの手順の並び) | コンテナ、dispatch ジョブ | 偽の gh(直近4日の結果のファイル)、環境変数 `JOB_RESULTS` と `EDIT_OUTCOME`、yq | 部品 target.yaml の report ジョブ(349-352行)、部品 report.sh「呼び出し方」(548-553行)、テストの方針 結合テスト(694行、702-703行、721行) |

### 申告

**1. actionlint が権限 `vulnerability-alerts` を知らないことを、新しい2つのワークフローについても、無視の行を足して通す** — design.md ファイルの構成の `.github/actionlint.yaml`(175行)

- Issue の記載: なし
- 決めたこと: `.github/actionlint.yaml` に、新しい2つのワークフローのファイルについて、`unknown permission scope "vulnerability-alerts"` の指摘だけを無視する行を足す。lint の指摘を無視する設定を足す変更で、ゲートの設定の変更にあたる。`.github/` の下なので、所有者の承認を待つ
- 他にありえた選択肢: 今の frontend-vuln-fix.yaml(7行)と同じく、Dependabot の警告を bot の PAT で読み、GITHUB_TOKEN にこの権限を持たせない。この選び方は、bot の PAT を ship ジョブだけに置く design の分け方と両立しない。または、actionlint がこの権限を知る版を出すのを待って版を上げる
- 外れていた場合: 影響は小さい。無視するのは、2つのファイルのこの1種類の指摘だけで、ほかの指摘は今と同じく guardrails を赤にする。actionlint がこの権限を知る版を出したあとは、今の `dependency-review.yaml` の行と同じく、無視の行が要らないまま残る

**2. verify の品質チェックと対象の確認を、`apply` が `final.patch` を書いたあとの別の手順で流す** — design.md 部品 target.yaml の verify ジョブ(331-338行)、部品 verify.sh「呼び出し方」(495-499行)

- Issue の記載: なし
- 決めたこと: `claude-auto-fix-verify.sh` を3つの形に分け、道具を入れる手順と CodeQL の解析を、その間に挟む。変わった領域は、`apply` が出し、`check` がもう一度決め直す。道具は、変わった領域の分だけを入れる
- 他にありえた選択肢: 5つの領域の道具をすべて先に入れ、スクリプトを分けずに1回で呼ぶ(CodeQL の解析だけは別の手順になる)
- 外れていた場合: 影響は小さい。分け方が変わるのは verify ジョブの中の手順とスクリプトの引数だけで、ほかのジョブに渡す `final.patch` と SHA-256 は変わらない

サイクル3 往復1 の申告の1と2、サイクル2 往復1 の申告の1と3から8、往復2 の申告の1と2は、差分で変わっていない。

### 指摘

| ID | レベル | 該当箇所 | 内容 | 直し方の案 |
|---|---|---|---|---|
| D4-1-1 | 中 | design.md claude-auto-fix-target.yaml の verify ジョブの手順5(336行)、claude-auto-fix-verify.sh の手順4の `codeql`(491行)と `confirm`(499行) | 差分は、手順5を「言語の準備とビルドは `codeql.yaml` の analyze ジョブと `.github/codeql/languages.tsv` のとおりにする」と書いた。今の analyze ジョブは、診断するコードを作業フォルダの最上位に checkout する(codeql.yaml 74-78行)。`init` に診断するフォルダの指定は無く、ビルドの命令は最上位で動く(languages.tsv 10行、23行と44行の `cd backend && …`)。verify ジョブでは、最上位にあるのは main のコード(ワークフローのコミット)で、Claude の変更を当てたコードは `target/` にある(133行)。今の analyze ジョブのとおりに作ると、次のどちらかになる。(1) ビルドなしの言語(`javascript-typescript`)では、CodeQL は最上位から下のすべてを診断するので、main のコードの警告が SARIF に残り、`confirm` はいつも `unfixed` にする。(2) ビルドの命令を最上位で動かす言語(`java-kotlin`、`go`)では、診断されるのは main のコードで、同じくいつも `unfixed` になる。ビルドの命令だけを `target/` で動かすと、SARIF のファイルのパスが `target/backend/…` になり、警告のファイル(`backend/…`)と合わないので、`confirm` は警告が残っていても `ok` にする。そのとき、警告が消えたと確かめていない変更が PR になり、要件2の2と5の2に届かない。ほかの手順は、`target/` との違いを1つずつ書いている(`package_json_file: target/frontend/package.json`、`go-version-file: target/backend/go.mod`、`KEIREKIPRO_REPO_ROOT` に `target/` の絶対パス)が、CodeQL の手順には無い。`test-claude-auto-fix-verify.sh` は偽の SARIF で、`test-claude-auto-fix-workflows.sh` は手順の並びで確かめるので、どちらも気づけない。マージのあとの確認は、開いている対象の1つで行うので、種類が `codeql` とは限らない。D1-1-8(`backend_compat` に `target/` の場所を渡す指定が無い)と同じ種類の抜けである | 手順5に、`init` に診断するフォルダを `target/` と指定する(codeql-action の `init` の入力 `source-root`。入力の名前は、公式の action.yml で確かめる)ことと、ビルドの命令を `target/` で動かすことを書く。verify.sh の `confirm` に、SARIF のファイルのパスを、診断するフォルダからの相対のパスとして、警告のファイルと照らすと書く。テストの方針の workflows のテストに、`init` が `target/` を指すことと、ビルドの手順が `target/` で動くことを確かめる場合を足す |
| D4-1-2 | 低 | design.md claude-auto-fix-target.yaml の verify ジョブ(331行)、claude-auto-fix-verify.sh「呼び出し方」(497-499行)、テストの方針の `test-claude-auto-fix-workflows.sh`(720行) | 331行は「どれかの形が `outcome` を出して止まったときは、あとの手順を飛ばす」と書き、720行は「前の形が `outcome` を出したときに、あとの手順が飛ばされること」と書く。`apply` は、通ったときに `outcome` を書かない(497行)が、`check` は、通ったときも `outcome=ok` を書く(498行)。720行を文字どおりに読むと、`check` が `outcome=ok` を出したあとの CodeQL の手順と `confirm` も飛ばすことになる。331行の「止まった」と手順の並びから、飛ばすのは `outcome` が `ok` でないときだと読み取れるので、実装には影響しない。あわせて、verify ジョブがあとのジョブに渡す結果を、3つの形の `outcome` からどう決めるか(最後に動いた形の `outcome`)が書かれていない | 331行と720行を「どれかの形が `ok` でない `outcome` を出したときは、あとの手順を飛ばす」に直す。verify ジョブの結果は、最後に動いた形の `outcome` にすると書く |

### 前の段階への指摘

なし

- 往復: 1回目 / 高0 中1 低1

## サイクル4 往復2(2026-11-14)

### 審査の範囲

範囲: 差分

- design.md 部品 claude-auto-fix-target.yaml の verify ジョブの手順5と6(336-337行)、部品 claude-auto-fix-verify.sh の手順4の `codeql`(491行)と `confirm`(499行)、テストの方針の verify と workflows(708行、721行): 差分が、`init` に `source-root: target`、ビルドの命令に `working-directory: target`、`analyze` に `checkout_path` を渡すと書き、`confirm` が SARIF のパスの先頭の `target/` を除いてから比べると書いたため(D4-1-1 の直し)。語 `source-root` `checkout_path` `working-directory` `CODEQL_SARIF_DIR` `SARIF` `target/` で検索して見つけた。ジョブの手順、スクリプトの `confirm`、2つのテストの場合の4か所が、同じ指定でつながっていることを確かめた
- design.md 全体の構成(133行)、verify ジョブの手順1と3(332行、334行)、verify.sh の手順3(481-484行): 手順5が「最上位には main のコードがあり、Claude の変更を当てたコードは `target/` にある」を理由にしたため。133行と合っている。ほかの手順の `target/` の渡し方(`go-version-file: target/backend/go.mod` など)と食い違わない
- requirements.md 要件2の2、要件5の2: 差分が挙げた要件の番号のため
- 主語を足した文(225行)、「5つの検査」を2つの文に分けた文(254行)、「依存の版を宣言するファイル」を2つの文に分けた文(340行)は、直す前の文と比べ、意味が変わっていないことを確かめた。254行の「4つの検査」と340行の「6つ」は、挙げた名前の数と合っている
- そのほかの節は、差分の語が出てこないので、読み直していない

### 実ファイルで確かめた文

- 部品 target.yaml の verify の手順5「`codeql.yaml` の analyze ジョブと違い、作業フォルダの最上位には main のコードがあり」(今の analyze ジョブが、コードを最上位に checkout し、`init` に診断するフォルダを渡さず、ビルドの命令を最上位で動かすこと): .github/workflows/codeql.yaml 74-78行、87-93行(`init` に渡すのは `languages` と `build-mode` だけ)、95-101行(`working-directory` の指定が無い)、103-111行(`analyze` に渡すのは `category` と `upload` と `upload-database` だけ)、.github/codeql/languages.tsv 10行、23行、44行 / 合っていた
- 同「`codeql.yaml` が使う版 v4.39.3」: .github/workflows/codeql.yaml 88行、105行 / 合っていた
- 同「`source-root` と `checkout_path` は、版 v4.39.3 の `init` と `analyze` の action.yml にある入力である」: action.yml はリポジトリの中に無い。審査役が実行できるコマンドは `gh issue view` だけのため、確かめられなかった。codeql.yaml 19-23行は、v4.39.2 の action.yml で入力の名前を確かめたと書くが、この2つの入力は今のワークフローで使っていない
- 部品 verify.sh の `confirm`「SARIF の結果のファイルのパスの先頭に `target/` があれば除いてから比べる」(リポジトリの最上位に `target/` で始まるファイルが無く、除いても別のファイルと取り違えないこと): リポジトリの最上位に `target/` のフォルダは無い(`target/**` で検索して0件) / 合っていた
- 同「警告のファイルのパスは、リポジトリの最上位からの相対のパスである」: 審査役が実行できるコマンドは `gh issue view` だけのため、確かめられなかった
- 部品 dispatch「期待一覧 `required-checks.json` で `approval_gated` が true の4つの検査は、escape-hatch、dependency-gate、pre-merge-check、dependency-cooldown である。`dependency-review` は別に除く」: .github/audit/required-checks.json 6行、18行、19行、24行(true はこの4つだけ)、23行(`dependency-review` は false) / 合っていた

### 受入基準ごとの確かめ方

| 受入基準 | 確かめる道具 | 動かす場所 | 動かすのに要るもの | design の箇所 |
|---|---|---|---|---|
| 2.2 | test-claude-auto-fix-verify.sh(`confirm` が、偽の SARIF の結果のパスが `target/` で始まるときも同じファイルとみなして `unfixed` にする)、test-claude-auto-fix-workflows.sh(`init` に `source-root: target`、ビルドの手順に `working-directory: target`、`analyze` に `checkout_path` として `target/` のパス) | コンテナ(alpine に bash と jq。workflows は yq を足す)、dispatch ジョブ | 偽の SARIF(パスが `target/` で始まるものと始まらないもの)、yq | 部品 target.yaml の verify ジョブの手順5(336行)、部品 verify.sh の `confirm`(499行)、テストの方針 結合テスト(708行、721行) |
| 5.2 | 同上。CodeQL の `init` と `analyze` の実際の動きは、main に入ったあとの実行 | コンテナ、dispatch ジョブ、main に入ったあとの実行 | 偽の SARIF、警告の規則の ID とファイルと `category`(verify の最初の手順が `$RUNNER_TEMP` に書く)、`target/` のコードを診断した SARIF(`init` の `source-root: target` と、`target/` で動かすビルドの命令で作る) | 部品 target.yaml の verify ジョブの手順5と6(336-337行)、部品 verify.sh 手順4と `confirm`(491行、499行)、テストの方針 結合テスト(708行、721行) |

### 申告

差分で新しく増えた申告は無い。サイクル4 往復1 の申告の1と2、サイクル3 往復1 の申告の1と2、サイクル2 往復1 の申告の1と3から8、往復2 の申告の1と2は、差分で変わっていない。

### 指摘

なし

### 前の段階への指摘

なし

- 往復: 2回で収束 / 未解決: 0件

## サイクル5 往復1(2026-11-14)

### 審査の範囲

範囲: 差分

- design.md 部品 claude-auto-fix-target.yaml の verify ジョブ(330-331行)、部品 claude-auto-fix-verify.sh「呼び出し方」(497-499行)、テストの方針の workflows と verify(708-709行、720行): 差分が、あとの手順を飛ばす条件を「`ok` 以外の `outcome`」に直し、ジョブの結果を最後に動いた形の `outcome` と決め、`$RUNNER_TEMP/codeql-alert.json` の形と読み手、`check` が領域を決め直す元(`final.patch`)を書いたため。語 `outcome` `ok` `codeql-alert.json` `final.patch` `areas` で検索した。`apply` は通ったときに `outcome` を書かず(497行)、`check` と `confirm` は `ok` を書く(498-499行)ので、331行と720行の条件は3つの形の出力と合っている
- design.md 部品 claude-auto-fix-target.yaml「役割」(310行): 同じ語 `outcome` で、ジョブの間の飛ばし方を書く文のため(D5-1-2)
- design.md 部品 claude-auto-fix-report.sh の `unfixed` の項(535行)、種類が `codeql` の項(539行)、テストの方針の report(699行、701行)、部品 sweep「3回続いた赤の扱い」(293行)、部品 ship の種類が `codeql` の PR の文(512行)、安全の節(733行): 差分が、種類が `codeql` の知らせに PR の URL を書くと決めたため。語「PR の URL」「警告の URL」で検索した。699行が直っていない(D5-1-1)
- design.md 部品 claude-auto-fix-target.yaml の prepare ジョブ(320行)と edit ジョブ(326行)、部品 prepare.sh「呼び出し方」(380行)、部品 materials.sh(395行、401行)、テストの方針の materials と prepare(662行、689行): 差分が、Trivy の結果のファイルの名前 `trivy-java.json` と `trivy-go.json` を書いたため。語 `trivy-results` `TRIVY_RESULTS_DIR` で検索した。成果物のフォルダを `TRIVY_RESULTS_DIR` で渡す流れと食い違わない
- design.md 部品 claude-auto-fix-report.sh の `key` の項(537行)、部品「基盤構築手順と PR の本文の変更」(608行): 差分が、節の見出し `## Claude を動かす鍵の取り替え` を書いたため。2か所の見出しの文は同じである
- requirements.md 要件2の2と5、要件4の1、要件5の1と2、要件6の3、要件7の2: 差分が挙げた要件と、直した部品が関わる要件のため。要件5の1が入れないと決めているのは、Claude が書いた文と、警告のファイルの名前、行、規則の名前、説明で、PR の URL は入っていない。要件2の5は、閉じた PR の URL を知らせに書くと決めている。539行の決め方は、この2つと合っている
- 書き方の点検で直した文(254行、445行、516行、521行、550-551行、624行、659行、663行、729行)は、直す前の文と比べ、意味が変わっていないことを確かめた。729行が指す「材料に入れる Issue、PR、コメントの書き手」は、materials の節の399行にある
- そのほかの節(dispatch のほかの集め方、sweep のほかの後始末、run-claude、prompt.md、guard、lib、cooldown のジョブ、性能)は、差分の語が出てこないので、読み直していない

### 実ファイルで確かめた文

- 部品 target.yaml の prepare「`container-scan.yaml` の `container-scan` ジョブと同じランナー(`ubuntu-24.04-arm`)と組み立て方(`docker buildx build --platform linux/arm64`)。2つのイメージは `docker/backend/Dockerfile.prod` と `docker/backend-go/Dockerfile.prod` から作り、組み立ての文脈は `./backend`。Trivy は 0.76.2」: .github/workflows/container-scan.yaml 46行、159行、196-198行、220-232行 / 合っていた。今の container-scan ジョブの結果のファイルの名前(180行、185行の `container-scan-result.json` と `container-scan-go-result.json`)は、design の新しい名前と違うが、design は今の名前に合わせるとは書いていない
- 部品 prepare.sh と verify-image「`check-container-scan.sh` の `report`」: .github/scripts/check-container-scan.sh 51行、75行(`judge | report`) / 合っていた
- 部品 dispatch「期待一覧で `approval_gated` が true の4つの検査は、escape-hatch、dependency-gate、pre-merge-check、dependency-cooldown。`dependency-review` は別に除く」: .github/audit/required-checks.json 6行、18行、19行、24行、23行 / 合っていた
- 部品 ship「`check-escape-hatches.sh` は、2つのコミットの共通の祖先と head を比べる」: .github/scripts/check-escape-hatches.sh 45行、54行(`git merge-base`) / 合っていた
- 部品 ship「bot の PAT で push して PR を作るので、PR の必須の検査が動く。`auto-merge.yaml` は、その PR に auto-merge の予約を付ける」: .github/workflows/auto-merge.yaml 63-66行、90-92行(このリポジトリのブランチの PR で、作り手が dependabot[bot] でないとき) / 合っていた
- データの形とテストの方針「今の vuln-fix のブランチ名から `chore/` を除いたもの」: .github/scripts/frontend-vuln-fix.sh 136行、.github/scripts/backend-vuln-fix.sh 110行、221行、234行(`chore/frontend-vuln-fix-`、`chore/backend-vuln-fix-`、`chore/backend-vuln-fix-go-stdlib-`、`chore/backend-vuln-fix-go-`) / 合っていた
- 部品 target.yaml の verify「警告の規則の ID、ファイルのパス、`most_recent_instance.category`」: .github/scripts/tests/test-check-audit-codeql-alerts.sh 86行(偽の警告に `rule.id` と `most_recent_instance.location.path` がある)、.github/workflows/codeql.yaml 107行(`category` は `/language:<言語>`) / `rule.id` と `location.path` は合っていた。`most_recent_instance.category` は、リポジトリの中に読む箇所が無く、審査役が実行できるコマンドは `gh issue view` だけのため、確かめられなかった
- 部品「基盤構築手順と PR の本文の変更」「3-1 の Actions secrets の表」「bot の PAT の復旧の節と同じ形で、見出し `## Claude を動かす鍵の取り替え`」: doc/開発フロー/基盤構築手順.md 69-76行(表の欄は Secret、値、失効したとき)、313行(`## botのPATが期限切れになったときの復旧`。見出しの深さは同じ `##`) / 合っていた
- 部品 verified-claude「`https://downloads.claude.ai/keys/claude-code.asc` の GPG の公開鍵の指紋」: リポジトリの外のため、確かめられなかった。差分は「鍵」を「GPG の公開鍵」に直しただけである

### 受入基準ごとの確かめ方

| 受入基準 | 確かめる道具 | 動かす場所 | 動かすのに要るもの | design の箇所 |
|---|---|---|---|---|
| 2.2 | test-claude-auto-fix-workflows.sh(前の形が `ok` 以外の `outcome` を出したらあとの手順が飛ばされ、`ok` なら次の手順が動く)、test-claude-auto-fix-verify.sh(`check` が `apply` と同じ領域を決め直す) | コンテナ(alpine に bash と jq と yq)、dispatch ジョブ | yq、`apply` が書いた `final.patch`、偽の品質チェックのコマンド | 部品 target.yaml の verify ジョブ(331行)、部品 verify.sh「呼び出し方」(497-498行)、テストの方針(709行、720行) |
| 2.5 | test-claude-auto-fix-report.sh(`reason` が `red-check` の `unfixed` で、PR を閉じず、知らせに PR の URL を書く)、test-claude-auto-fix-sweep.sh(閉じた PR の URL を書いた知らせ) | コンテナ | 偽の gh | 部品 report の `unfixed` の項(535行)と種類が `codeql` の項(539行)、テストの方針(681行、701行) |
| 2.8 | test-claude-auto-fix-prepare.sh(偽の Trivy の結果に ID が無ければ `gone`)、test-claude-auto-fix-materials.sh(その ID の行だけが材料に入る) | コンテナ | `TRIVY_RESULTS_DIR` の下の偽の `trivy-java.json` と `trivy-go.json` | 部品 target.yaml の prepare ジョブ(320行)、部品 prepare.sh「呼び出し方」(380行)、テストの方針(662行、689行) |
| 4.1 | test-claude-auto-fix-report.sh(知らせの Issue に対象の URL を書く) | コンテナ | 偽の gh | 部品 report の `unfixed` の項(535行) |
| 5.1 | test-claude-auto-fix-report.sh(種類が `codeql` の Issue の題名と本文とコメントに入る中身)、test-claude-auto-fix-ship.sh(題名と本文とコミットのメッセージ) | コンテナ | 偽の gh、種類が `codeql` で PR の URL を渡した呼び出し | 部品 report の種類が `codeql` の項(539行)、テストの方針(699行、724行)。699行の場合が、539行の決め方と合わず、種類が `codeql` で PR の URL を書く場合が無い(D5-1-1) |
| 5.2 | test-claude-auto-fix-verify.sh(`confirm` が偽の SARIF と `codeql-alert.json` を読む)、test-claude-auto-fix-workflows.sh(手順の並び) | コンテナ、dispatch ジョブ | 偽の SARIF、`rule_id` `path` `category` を持つ偽の `$RUNNER_TEMP/codeql-alert.json` | 部品 target.yaml の verify ジョブ(330行、336-337行)、部品 verify.sh の `confirm`(499行)、テストの方針(708行) |
| 6.3 | test-claude-auto-fix-report.sh(`key` の Issue が1つだけ。本文に基盤構築手順の見出しへのリンク) | コンテナ | 偽の gh | 部品 report の `key` の項(537行)、部品「基盤構築手順と PR の本文の変更」(608行)、テストの方針(696行) |
| 7.2 | 基盤構築手順の差分を読む | PR の差分 | なし | 部品「基盤構築手順と PR の本文の変更」(608行) |

### 申告

**1. 種類が `codeql` の知らせにも、PR の URL を書く** — design.md 部品 claude-auto-fix-report.sh の種類が `codeql` の項(539行)

- Issue の記載: なし。Issue は「Issue には、消せなかった警告の URL が書いてある」とだけ書く
- 決めたこと: `reason` が `red-check` の `unfixed` のときと、sweep が閉じた PR の URL を渡したときは、種類が `codeql` でも、知らせに PR の URL を書く
- 他にありえた選択肢: 種類が `codeql` では、`reason` が `red-check` で PR が開いたまま残るときに、PR の URL を書かない(閉じた PR の URL は、要件2の5が書くと決めているので、選ぶ余地が無い)
- 外れていた場合: 影響は小さい。PR は公開されていて、題名と本文は決まった文と警告の URL だけである。書かない形に変えるときは、report の `notify` と、そのテストの1つの場合を直す

サイクル4 往復1 の申告の1と2、サイクル3 往復1 の申告の1と2、サイクル2 往復1 の申告の1と3から8、往復2 の申告の1と2は、差分で変わっていない。

### 指摘

| ID | レベル | 該当箇所 | 内容 | 直し方の案 |
|---|---|---|---|---|
| D5-1-1 | 中 | design.md テストの方針の `test-claude-auto-fix-report.sh`(699行)、部品 claude-auto-fix-report.sh の種類が `codeql` の項(539行) | 差分は、539行を「`unfixed` の項のとおりに PR の URL を書くときは、種類が `codeql` でも PR の URL を書く」に直した。699行は「種類が `codeql` の Issue の題名と本文に、警告の URL のほかの中身が入らないこと」のままで、差分で変わっていない。知らせの Issue が開いていないときは、`notify` は Issue を起票する(535行)ので、種類が `codeql` で `reason` が `red-check` の `unfixed` か、sweep から呼ばれた `unfixed` では、Issue の本文に PR の URL が入る。699行のとおりにテストを書くと、539行のとおりに作った `notify` が通らない。T2-1-7 は、食い違いの箇所として、report の節の2つの文に加えて、この行も挙げていた。直ったのは report の節だけである。tasks.md 180行は、すでに「決まった文と警告の URL と PR の URL のほかの中身が入らない」と書いていて、design の699行だけが合っていない。あわせて、テストの方針に、種類が `codeql` で PR の URL を書く場合が無い(701行は種類を決めていない) | 699行を「種類が `codeql` の Issue の題名と本文とコメントに、決まった文と警告の URL と、`unfixed` の項のとおりに書く PR の URL のほかの中身が入らないこと」に直す。種類が `codeql` で `reason` が `red-check` の `unfixed` のときに、知らせに PR の URL が書かれる場合を足す |
| D5-1-2 | 低 | design.md 部品 claude-auto-fix-target.yaml「役割」(310行) | 310行は「前のジョブが結果(outcome)を出して止まったときは、あとのジョブを飛ばして report ジョブに進む」と書く。差分で、verify ジョブは、通ったときも結果 `ok` を出すと決まった(331行)。edit ジョブも、通ったときに `ok` を出す(423行)。「止まった」の語と、ジョブの並びから、飛ばすのは結果が `ok` でないときだと読み取れるので、実装には影響しない。T2-1-6 が直した verify ジョブの中の文と同じ書き方が、ジョブの間の文に残っている | 310行を「前のジョブが `ok` 以外の結果(outcome)を出したときは」に直す |

### 前の段階への指摘

なし

- 往復: 1回目 / 高0 中1 低1

## サイクル5 往復2(2026-11-14)

### 審査の範囲

範囲: 差分

- design.md テストの方針の `test-claude-auto-fix-report.sh`(699-700行、702行)、部品 claude-auto-fix-report.sh の `unfixed` の項(535行)と種類が `codeql` の項(539行): 差分が D5-1-1 の直しとして、699行を直し、700行を足したため。語「PR の URL」「警告の URL」で design.md と requirements.md を検索した。699行は539行の決め方と合い、700行は535行の「`reason` が `red-check` のときは、知らせに、赤の検査を直せなかった PR の URL を書く」と539行の「種類が `codeql` でも PR の URL を書く」を確かめる場合になっている
- design.md 部品 claude-auto-fix-target.yaml の report ジョブ(349行、352行)、部品 claude-auto-fix-report.sh「役割」の `unavailable` と `blocked` の項(536行)と「呼び出し方」(548-553行): 差分が「report の3日の数え方」を「同じ対象で3日続けて動けなかったかを数える `claude-auto-fix-report.sh notify`」に言い換え、550-551行から report ジョブが環境変数に値を入れる文を消したため。語「3日」`EDIT_OUTCOME` `JOB_RESULTS` で検索した。3日を数えるのは `notify` である(536行: 直近4日の同じ key の実行の結果を読み、最後の3回が3つの違う UTC の日に終わっていれば起票する)ので、言い換えは合っている。report ジョブが `actions: read` を持つ(349行)ことと、結果のファイルを `notify` の前に上げる手順の並び(350-352行)とも合っている。550-551行から消した文(report ジョブが `JOB_RESULTS` と `EDIT_OUTCOME` に値を入れること、`record` が出した結果を `<outcome>` に渡すこと)は、350行と352行に残っている
- design.md 部品 sweep「3回続いた赤の扱い」(293行)、部品 report の `unfixed` の項(535行)と sweep からの呼び出しの文(553行)、テストの方針の sweep(681行)、requirements.md 要件2の5(89行): 差分が293行から「知らせには閉じた PR の URL を書く」を消したため。語「閉じた PR」「notify unfixed」で検索した。閉じた PR の URL を知らせに書くことは、535行、553行、681行に残っていて、要件2の5を満たす決め方は消えていない。293行の末尾に句点が残った(D5-2-1)
- design.md ファイルの構成の `.github/actionlint.yaml`(175行)、部品 dispatch のコンテナの検査の終わり(255行)、verify ジョブの手順5(336行)、cooldown-generate(342行)、cooldown-judge(346行)、部品「基盤構築手順と PR の本文の変更」(608行): 書き方の点検で直した文。直す前の文と比べ、意味が変わっていないことを確かめた。今あるものについて書いた部分は、下の小見出しのとおり実ファイルで確かめた
- requirements.md 要件2の5、要件4の1、要件5の1、要件6の1と2: 差分の行が挙げた要件と、直した文が関わる要件のため。要件5の1が入れないと決めているのは、Claude が書いた文と、警告のファイルの名前、行、規則の名前、説明で、PR の URL は入っていない。要件6の1は、同じ対象で3日続けて動けなかったら Issue を起票すると決めていて、349行と536行はこれと合っている
- そのほかの節は、差分の語が出てこないので、読み直していない

### 実ファイルで確かめた文

- ファイルの構成(175行)「CI が使う actionlint 1.7.12 は、権限 `vulnerability-alerts` を知らない。`dependency-review.yaml` と同じ形で無視する行を足す。ファイルの先頭の説明の文」: .github/workflows/guardrails.yaml 44行(`rhysd/actionlint:1.7.12`)、.github/actionlint.yaml 1-14行(先頭の説明は dependency-review.yaml だけを指し、`paths` に `unknown permission scope "vulnerability-alerts"` の無視が1件ある) / 合っていた
- 部品 dispatch(255行)「定期のコンテナの検査は、毎日と、本番のリリースのあとと、`backend/` か `docker/backend-go/` を変えた main への push のあとに動く」: .github/workflows/container-scan-scheduled.yaml 64行(cron は毎日)、71-73行(`workflow_run` の Production Release の completed)、74-80行(main への push で、`backend/` を文脈にする組み立てと `docker/backend-go/**`) / 合っていた
- verify ジョブの手順5(336行)「`codeql.yaml` が使う版 v4.39.3 の `init` と `analyze`」: .github/workflows/codeql.yaml 88行、105行(どちらも `# v4.39.3`) / 合っていた。`source-root` と `checkout_path` が action.yml の入力にあることは、リポジトリの外のため、確かめられなかった。差分はこの部分を変えていない
- cooldown-generate(342行)「`dependency-review.yaml` と同じく、`productionRuntimeClasspath` と `detachedConfiguration` の除外の設定を渡す。`dependency-graph: generate-and-upload`」: .github/workflows/dependency-review.yaml 71行、74行、83行、111行(`download-and-submit`) / 合っていた
- cooldown-judge(346行)「`PNPM_WORKSPACE_FILE` を渡さないと、pnpm の除外の欄の判定は、最上位に checkout した main の除外の欄を読む」: .github/scripts/check-dependency-cooldown.sh 45行、81行(既定は `frontend/pnpm-workspace.yaml`)、604行(`cooldown-check-pnpm-exclude.sh` にこの値を渡す) / 合っていた
- 部品「基盤構築手順と PR の本文の変更」(608行): 差分は、コマンドを打つ者を主語にした文に分けただけで、今あるファイルについての文は変わっていない。3-1 の表と bot の PAT の復旧の節は、サイクル5 往復1 で確かめてある

### 受入基準ごとの確かめ方

| 受入基準 | 確かめる道具 | 動かす場所 | 動かすのに要るもの | design の箇所 |
|---|---|---|---|---|
| 2.5 | test-claude-auto-fix-report.sh(`reason` が `red-check` の `unfixed` で、PR を閉じず、知らせに PR の URL を書く。種類が `codeql` でも書く)、test-claude-auto-fix-sweep.sh(同じ検査の赤が3回続いたら PR を閉じ、閉じた PR の URL を書いた知らせを書く) | コンテナ(alpine に bash と jq) | 偽の gh、引数 `<PR の URL>` を渡した `notify unfixed` の呼び出し | 部品 sweep「3回続いた赤の扱い」(293行)、部品 report の `unfixed` の項(535行)と sweep からの呼び出しの文(553行)、テストの方針(681行、700行、702行) |
| 5.1 | test-claude-auto-fix-report.sh(種類が `codeql` の Issue の題名と本文とコメントに、決まった文と警告の URL と PR の URL のほかの中身が入らない。種類が `codeql` で `reason` が `red-check` の `unfixed` で PR の URL が書かれる) | コンテナ | 偽の gh、種類が `codeql` で PR の URL を渡した呼び出し | 部品 report の種類が `codeql` の項(539行)、テストの方針(699-700行) |
| 6.1 | test-claude-auto-fix-report.sh(3つの違う日の `unavailable` で Issue が1つだけ起票される。ジョブが結果を出さずに止まったときの結果) | コンテナ | 偽の gh が返す、直近4日の同じ key の実行の結果のファイル(3つの違う UTC の日) | 部品 target.yaml の report ジョブ(349-352行)、部品 report の `unavailable` と `blocked` の項(536行)、テストの方針(694行、703行) |

### 申告

差分で新しく決めたことは無い。サイクル5 往復1 の申告の1(種類が `codeql` の知らせにも、PR の URL を書く)は、差分で変わっていない。その前のサイクルの申告も、差分で変わっていない。

### 指摘

| ID | レベル | 該当箇所 | 内容 | 直し方の案 |
|---|---|---|---|---|
| D5-2-1 | 低 | design.md 部品 sweep「3回続いた赤の扱い」(293行) | 差分が末尾の文「知らせには閉じた PR の URL を書く」を消したあとに、箇条の末尾に句点が残り、「…直せなかったことを知らせる。」で終わっている。同じ並びのほかの4つの箇条は、句点なしで終わる。意味は変わらず、実装に影響しない | 293行の末尾の句点を消す |

### 前の段階への指摘

なし

- 往復: 2回で収束 / 未解決: 0件

## サイクル6 往復1(2026-11-21)

### 審査の範囲

範囲: 差分

- design.md 使う既存の仕組み(41行)、設計を見直すきっかけ(57行)、使う技術(143行)、処理の流れの図(201行、204行)、部品 claude-auto-fix-target.yaml の cooldown-push(342-348行)と cooldown-judge(351-356行)、部品「check-dependency-cooldown.sh の変更」(613行)、テストの方針(732-733行): 差分が Go の版の公開からの時間の検査を足した行そのもの。語 `check-go-release-age` `lib-go-release` `go_release_is_target` `cooldown-judge` `cooldown-push` で design.md と requirements.md と research.md を検索した
- design.md 部品 claude-auto-fix-target.yaml「失敗したとき」の表(366-373行): 差分の356行が「失敗したときの結果は、下の表のとおり `unavailable`」と挙げたため。表の cooldown-judge の行は `unavailable` で、合っている
- design.md 部品 claude-auto-fix-verify.sh の手順1「Go の標準ライブラリ」(486行)と「Dockerfile の digest」(487行)、prompt.md の節(447行): 差分の346行が、`go_bump` と、Claude が Dockerfile の golang のイメージを上げる変更を、cooldown-push を動かす理由に挙げたため
- design.md 部品 report の `unavailable` と `blocked` の項(545行)、部品 dispatch の `retry`(260行): 差分が、Go の版で止まったときの結果を `blocked` と決めたため。`blocked` は次の日に動かし直され、3日続けば知らせの Issue になる
- design.md 部品 claude-auto-fix-verify.sh の手順3の `frontend`(490行)、verify ジョブの手順1と3(334行、336行): 差分が Node.js の版を 24.22.3 に直したため。語 `24.22` で検索した。design.md に 24.22.2 は残っていない
- requirements.md 要件2の9(93-95行): 差分のテストの方針の行と cooldown のジョブが対応する要件のため。reviews/requirements-response.md の R2-2-2(Go の版と golang のイメージの版を、どの検査が72時間で止めるかは design で決める)は、差分の cooldown-judge の行に書かれたので、記録しない
- .github/workflows/dependency-review.yaml の cooldown ジョブの全部の手順(148-276行): 差分の41行と355行が「dependency-cooldown の検査が、このスクリプトを別の手順で呼ぶので、このジョブも両方を呼ぶ」と書き、40-41行が「PR の検査と同じ結果になるように判定する」と書くため。cooldown ジョブが判定に使う手順を全部読んだ(D6-1-1)
- 書き方の点検で直した行(69行、73行、78行、131行、137行、226行、282行、349行、383行、389行、425行、477行、480行、506行、508行、521行、548行、619行): 直す前の文と比べ、意味が変わっていないことを確かめた。今あるものについて書いた部分のうち、差分で文が変わった箇所は、下の小見出しのとおり実ファイルで確かめた
- そのほかの節は、差分の語が出てこないので、読み直していない

### 実ファイルで確かめた文

- 使う既存の仕組み(41行)、cooldown-judge(355行)「dependency-review の dependency-cooldown の検査は、`check-go-release-age.sh` を、`check-dependency-cooldown.sh` と別の手順で呼ぶ」: .github/workflows/dependency-review.yaml 148-149行(ジョブの名前 `dependency-cooldown`)、221-230行(Check dependency cooldown)、269-276行(Check Go release age) / 合っていた
- 使う既存の仕組み(40-41行)、cooldown-judge(355行)「PR の検査と同じ結果になるように判定する」「このジョブも両方を呼ぶ」: .github/workflows/dependency-review.yaml 232-244行(Check CI tool release age)、.github/scripts/check-ci-tool-release-age.sh 5-9行、17-18行、26行、131-142行、.github/ci-tool-versions.json 15-16行、46-47行 / 食い違っていた(D6-1-1)。dependency-cooldown の検査は、判定のスクリプトを2つではなく3つ呼ぶ
- cooldown-push(345行)「Go の版を書くファイルとは、`go_release_is_target` が Go の版を読むファイルとするもので、場所によらず、名前が `go.mod` のファイルと、名前が `Dockerfile`、`Dockerfile.<何か>`、`<何か>.Dockerfile` のファイルである」: .github/scripts/lib-go-release.sh 47-53行、.github/scripts/check-go-release-age.sh 78-91行(コミットのすべてのファイルを見る) / 食い違っていた(D6-1-2)。51行は `\.[Dd]ockerfile$` で、名前が `<何か>.dockerfile`(小文字)のファイルも読む
- cooldown-push(346行)「種類が `go-stdlib` のときの `go_bump` が Go の版を書くファイルを変える」、verify の手順1(486行)「`go.mod` の toolchain と4つの Dockerfile の golang のイメージを上げる」: .github/scripts/backend-vuln-fix.sh 138-139行(`GO_DOCKERFILES` は4つ)、159-161行 / 合っていた
- cooldown-push(348行)「main のほかへの push で動くワークフローもない」: .github/workflows/ の `push:` を持つ6つのワークフロー(ci.yaml 8-9行、codeql.yaml 31-32行、container-scan-scheduled.yaml 76-77行、dependency-graph.yaml 35-36行、sync-labels.yaml 32-33行、update-pr-branches.yaml 44-45行)は、どれも `branches: [main]` / 合っていた
- cooldown-judge(355行)「このスクリプトが今のフォルダを head の写しの根として、コミットのファイルを読む」「環境変数 `GH_TOKEN` を渡す」: .github/scripts/check-go-release-age.sh 34行、37行、81行、88行、94行(`gh api` の比較)、103-104行(分かれ目のコミットを今のフォルダの Git で取る) / 合っていた
- cooldown-judge(355行)、部品「check-dependency-cooldown.sh の変更」(613行)「このスクリプトには例外が無い」「記録のコメントを書かず、所有者の承認も読まない」: .github/scripts/check-go-release-age.sh 20-21行、24行(出力は Summary と標準出力だけ) / 合っていた
- cooldown-judge(356行)、設計を見直すきっかけ(57行)「`check-go-release-age.sh` の終わり方は0と1と2」: .github/scripts/check-go-release-age.sh 27-28行、53行、96行、112行、116行、138行、179-180行 / 合っていた
- 部品「check-dependency-cooldown.sh の変更」(613行)「Go の版の公開からの時間は、このスクリプトの4つの判定に入らない」: .github/scripts/check-dependency-cooldown.sh を `go-release` `go_release` で検索し、0件 / 合っていた
- verify の手順3の `frontend`(490行)「ci.yaml の frontend-test ジョブと同じく `pnpm/action-setup` v6.1.1、Node.js は `verified-node` で 24.22.3」: .github/workflows/ci.yaml 216行、229行、236-238行 / 合っていた
- requirements.md 要件2の9(95行)「今の backend-vuln-fix の Go 版のジョブは、公開からの時間を見ずに PR を作る」: .github/scripts/backend-vuln-fix.sh 181行(72時間たっていなければ公開の時刻の検査が PR を止める、と PR の本文に書く) / 合っていた。main の取り込みのあとも変わっていない

### 受入基準ごとの確かめ方

| 受入基準 | 確かめる道具 | 動かす場所 | 動かすのに要るもの | design の箇所 |
|---|---|---|---|---|
| 2.9(Go の版を72時間経っていない版に変える変更を PR にしない) | test-claude-auto-fix-workflows.sh(cooldown-judge が `target/` の中で `check-go-release-age.sh` を呼ぶ。偽のスクリプトが1で終われば `blocked`。2つの終わり方がそろったときだけ ship に進む) | CI は dispatch ジョブのランナー `ubuntu-24.04`、手元は alpine のコンテナ(yq を足す) | yq(737行)。偽の `check-go-release-age.sh` と偽の `check-dependency-cooldown.sh` を、ワークフローの手順にどう呼ばせるか | yq は737行。偽のスクリプトの呼ばせ方は無い(D6-1-3)。667行が偽のコマンドに置き換えると決めているのは、PATH の `gh`、`git` の push、`claude`、`docker` だけである |
| 2.9(cooldown のジョブが動く条件) | test-claude-auto-fix-workflows.sh(cooldown-push が動くかを決めるファイルが、部品の節と同じ) | 同じ | yq。条件を決める手順がどのジョブにあり、何で名前を見分けるか | 733行、342-345行。名前の一覧が実ファイルと違う(D6-1-2) |
| 2.9(Go の版の判定そのもの) | 今ある test-check-go-release-age.sh と test-lib-go-release.sh | dependency-review.yaml の cooldown ジョブ(190-195行)と、cooldown-judge(364行「各ジョブは、スクリプトを呼ぶ前に、そのスクリプトのテストを流す」) | git(ランナーにある) | 364行、613行(スクリプトを変えない) |
| 2.9(Node.js と Terraform の開発環境の版を72時間経っていない版に変える変更) | 無い | 無い | 無い | 無い(D6-1-1) |

### 申告

**1. Go の版で止まる変更を、Claude を動かして確かめたあとに `blocked` にする** — 部品 claude-auto-fix-target.yaml の cooldown-judge(355-356行)

- Issue の記載: なし。要件2の9は、dependency-cooldown が記録なしで赤にする変更を PR にせず、次の日に動かし直すと決めている
- 決めたこと: Go の版の公開からの時間は、edit(Claude)と verify(最長120分)が終わったあとの cooldown-judge で判定する。72時間経っていなければ `blocked` にし、次の日に Claude をもう一度動かす。`check-go-release-age.sh` には例外が無いので、種類が `go-stdlib` の対象は、修正版の公開から72時間は、毎日 Claude を動かしては `blocked` で終わる。`blocked` が3つの違う UTC の日に続くと、知らせの Issue が起票される(545行)
- 他にありえた選択肢: 種類が `go-stdlib` では key が Go の版なので、prepare ジョブか verify の `apply`(npm の `decide` と同じ場所)で公開日時を先に調べ、72時間経っていなければ Claude を動かさずに `blocked` にする
- 外れていた場合: Go のセキュリティの修正の版が出るたびに、所有者の Claude の契約の使える量を、PR にならない実行に最大3日分使う。72時間の待ちの3日目に、動けなかったことを知らせる Issue が起票され、次の日に PR ができて閉じる

**2. 名前が Dockerfile のファイルを変えた変更は、どれも cooldown の4つのジョブを通す** — 部品 claude-auto-fix-target.yaml の cooldown-push(343-346行)

- Issue の記載: なし
- 決めたこと: cooldown-push を動かす条件に、場所によらない `go.mod` と Dockerfile を足した。golang のイメージを使わない Dockerfile(たとえば `docker/backend/Dockerfile.prod` の eclipse-temurin)だけを変えた変更でも、一時のブランチの push、Gradle のスナップショットの作成と送信、判定の4つのジョブが動く
- 他にありえた選択肢: 変更の前後で `go_release_versions_of` の結果が変わったファイルがあるときだけ動かす。または、Go の版の判定だけを、Gradle のスナップショットを要らない別のジョブにする
- 外れていた場合: 種類が `container` の対象の多くで、PR までの時間が cooldown のジョブの分だけ延びる。判定の結果は変わらない

**3. `check-go-release-age.sh` が1で終わる場合を、理由によらず `blocked` にする** — cooldown-judge(356行)

- Issue の記載: なし
- 決めたこと: 終わり方の1には、72時間経っていない版のほかに、版を読めない書き方(`golang:1.27-trixie` など)、配布元に無い版、比較の API と配布元への問い合わせの失敗が入る(check-go-release-age.sh 27行、94-107行、151-165行)。どれも `blocked` にして次の日に動かし直す
- 他にありえた選択肢: 版を読めない書き方と配布元に無い版は、Claude の変更の誤りなので `unfixed` にする
- 外れていた場合: Claude が版を読めない書き方を書いた対象は、直せなかったことを知らせる Issue ではなく、3日後に、動けなかったことを知らせる Issue になる

### 指摘

| ID | レベル | 該当箇所 | 内容 | 直し方の案 |
|---|---|---|---|---|
| D6-1-1 | 中 | design.md 使う既存の仕組み(40-41行)、部品 claude-auto-fix-target.yaml の cooldown-push(343-346行)と cooldown-judge(355-356行) | 355行は「dependency-cooldown の検査が、このスクリプトを `check-dependency-cooldown.sh` と別の手順で呼ぶので、このジョブも両方を呼ぶ」と書くが、dependency-cooldown のジョブが判定に使うスクリプトは3つである。3つ目は .github/workflows/dependency-review.yaml 232-244行の「Check CI tool release age」が呼ぶ `check-ci-tool-release-age.sh` で、design はこれを呼ばない。このスクリプトは、`.github/ci-tool-versions.json` 15-16行と46-47行の `dev.file`(`docker/frontend/Dockerfile` の node のイメージと、`docker/terraform/Dockerfile` の terraform のイメージ)の FROM のタグの版が変わると、公開から72時間経っていない版を止める(check-ci-tool-release-age.sh 5-9行、131-142行)。開発環境の版には記録の例外が無い(同26行)。この2つのファイルの FROM の版は、ゲートの設定のファイルではないので、ガードは止めない。そのため、Claude の変更か、種類が `dependabot` のときの `base.patch` が、この2つの FROM の版を72時間経っていない版に変えると、cooldown-judge は通し、PR の dependency-cooldown が記録なしで赤になる。sweep は dependency-cooldown の赤を数えないので、PR は誰かが検査を動かし直すまで止まる。今回 Go の版で直した穴と同じ形の穴で、要件2の9の「dependency-cooldown の検査と同じ結果になるように確かめる」を満たさない。偽のコマンドのテストでは見つからない | 次のどれかに決めて書く。(a) cooldown-judge が `check-ci-tool-release-age.sh` も呼ぶ。このスクリプトは今は `PR_NUMBER` と `CI_TOOL_CHANGED_FILE` が無いと2で終わる(同63-70行)ので、PR を作る前に呼べる形を足すなら、「Claude が変えるファイル」とテストの方針にも書く。(b) ガードが、`ci-tool-versions.json` の `dev.file` の FROM のタグの版を変える変更を `unfixed` にする。種類が `dependabot` の `base.patch` の扱いも書く。(c) 判定に入れないと決め、入れない理由と、そのとき PR がどう止まり、誰がどう気づくかを書く。あわせて、355行の「両方」を、dependency-cooldown のジョブの判定の手順の数に合う書き方に直す |
| D6-1-2 | 中 | design.md 部品 claude-auto-fix-target.yaml の cooldown-push(345行)、テストの方針(733行) | 345行は、Go の版を書くファイルの名前を「`go.mod`、`Dockerfile`、`Dockerfile.<何か>`、`<何か>.Dockerfile`」と並べるが、.github/scripts/lib-go-release.sh 51行は `\.[Dd]ockerfile$` で、名前が `<何か>.dockerfile`(小文字)のファイルも Go の版を読むファイルとする。733行のテストは、ワークフローの条件を345行の一覧と比べるので、一覧のとおりに作ると、小文字の名前のファイルだけを変えた変更で cooldown のジョブが動かず、PR の Go の版の検査とずれる。また、342-345行は、cooldown-push が動くかを、どのジョブのどの手順が決めるかを書いていない。名前が場所によらないので、ジョブの `if` の式だけでは決められない | 345行の一覧に `<何か>.dockerfile` を足す。または、一覧を並べるのをやめ、「verify の `apply`(か別の手順)が、`base.patch` と `final.patch` の変えたパスごとに `lib-go-release.sh` の `go_release_is_target` を呼んで決め、出力に出す」と、決める場所と決め方を書く。733行のテストも、同じ関数の結果と比べる形に直す |
| D6-1-3 | 中 | design.md テストの方針(732行、667行) | 732行は、test-claude-auto-fix-workflows.sh が「偽のスクリプトが1で終われば結果が `blocked` になる」ことを確かめると書く。このテストは yq で YAML を読むテスト(726行)で、667行が偽のコマンドに置き換えると決めているのは PATH の `gh`、`git` の push、`claude`、`docker` だけである。ワークフローの手順がパスで呼ぶ2つのスクリプトを、テストがどう偽のスクリプトに置き換え、手順の `run` をどう動かすかが、design のどこにも無い。書かれていないと、テストは「YAML に `check-go-release-age.sh` の文字がある」ことだけを確かめる形になり、2つの終わり方から `blocked` と ship を決める処理が確かめられないまま残る。終わり方が2のときにジョブが失敗する場合も、732行に無い | 次のどちらかを書く。(a) テストが、yq で cooldown-judge の判定の手順の `run` を取り出し、偽の `.github/scripts/check-dependency-cooldown.sh` と `check-go-release-age.sh` を置いた一時のフォルダで bash で動かし、`GITHUB_OUTPUT` の `outcome` を読む。(b) 2つの終わり方から結果を決める処理を、今ある部品のスクリプトか `lib-claude-auto-fix.sh` の関数に置き、そのテストで確かめる。732行に、`check-go-release-age.sh` が2で終わったときにジョブが失敗する場合と、`check-dependency-cooldown.sh` が1で終わった場合を足す |
| D6-1-4 | 低 | design.md cooldown-judge(356行) | `check-dependency-cooldown.sh` が1で終わり、`check-go-release-age.sh` が2で終わったときに、「どちらかの終わり方が1なら `blocked`」と「2ならこのジョブを失敗にする」のどちらに従うかが書かれていない。`check-dependency-cooldown.sh` が1で終わったあとに `check-go-release-age.sh` を呼ぶかも書かれていない。どちらの結果でも次の日に動かし直すので、実装への影響は小さい | 356行に、2つのスクリプトをどちらも呼ぶことと、`check-go-release-age.sh` が2で終わったときは、もう一方の終わり方によらずジョブを失敗にすること(か、その逆)を書く |

### 前の段階への指摘

なし

- 往復: 1回目 / 高0 中3 低1

## サイクル6 往復2(2026-11-21)

### 審査の範囲

範囲: 差分

- design.md 使う既存の仕組み(42行)、設計を見直すきっかけ(59-60行)、使う技術(146行)、ファイルの構成(178行)、処理の流れの図(205行、208行)、部品 claude-auto-fix-target.yaml の verify の出力(344行)と cooldown-push(346-349行)と cooldown-judge(352-359行)、部品 claude-auto-fix-verify.sh の `apply`(509行)、部品 lib-claude-auto-fix.sh(571-591行)、部品「check-ci-tool-release-age.sh の変更」(627-633行)、テストの方針(691-692行、698行、744行、755-756行): 差分が、3つ目の判定のスクリプトと、`cooldown_needed` と `cooldown_outcome` を足した行そのもの。語 `check-ci-tool` `ci-tool-versions` `cooldown_needed` `cooldown_outcome` `install-verified-` `両方` `2つのスクリプト` `8つの関数` で design.md を検索した。直す前の数え方(「両方」「8つの関数」)は残っていない
- design.md 部品 claude-auto-fix-target.yaml「失敗したとき」の表(371-376行): 差分の359行が、`cooldown_outcome` が `fail` を出したときの結果を「下の表のとおり `unavailable`」と挙げたため。表の cooldown-judge の行は `unavailable` で、合っている
- design.md 部品 claude-auto-fix-guard.sh(467-474行)、テストの方針の test-claude-auto-fix-ship.sh(761行): CI の版を書くファイル(`.github/workflows/` のファイル)を Claude が変えられるかで、3つ目の判定が効く場面が決まるため。Claude の変更はガードが止め、種類が `dependabot` の `base.patch` だけが変えうる
- design.md 使う既存の仕組みの依存の向き(49行)、部品「frontend-vuln-fix.sh と backend-vuln-fix.sh の変更」(601行): `lib-claude-auto-fix.sh` が `lib-go-release.sh` を読み込むようになり、vuln-fix の2つのスクリプトも間接に読み込むため。`lib-go-release.sh` は、読み込んだときに変数を2つ決めるだけで、ほかの処理をしない(同33-34行)ので、影響は無い
- requirements.md 要件2の9(93-95行)、要件3の1(101行): 差分の節が対応する要件のため
- reviews/requirements-review.md と requirements-response.md: `design` で検索した。後ろの段階で書くと記録された食い違いのうち、差分に関わるのは R2-2-2(Go の版と golang のイメージの版を、どの検査が72時間で止めるか)で、cooldown-judge(357行)に書かれている。記録しない
- 言い回しだけを直した行(31行、67行、140行、467行、617行、625行、766行): 直す前の文と比べ、意味が変わっていないことを確かめた
- そのほかの節は、差分の語が出てこないので、読み直していない

### 実ファイルで確かめた文

- 使う既存の仕組み(42行)「`check-ci-tool-release-age.sh` と、その下の `lib-ci-tool-releases.sh` と、データのファイル `.github/ci-tool-versions.json`」「CI の道具の版と、開発環境の Node.js と Terraform の版を変える変更」: .github/scripts/check-ci-tool-release-age.sh 5-9行、59-60行、73行、.github/ci-tool-versions.json 15-20行、46-51行(`dev` を持つのは node と terraform だけ) / 合っていた
- 使う既存の仕組み(42行)、cooldown-judge(355行)「dependency-cooldown の検査は、3つのスクリプトを別々の手順で呼び、どの手順も前の手順の結果によらず動く」: .github/workflows/dependency-review.yaml 221-230行(Check dependency cooldown)、234-244行(Check CI tool release age。`if` は `!cancelled()` とテストの手順の成功)、269-276行(Check Go release age。同じ `if`) / 合っていた。2つ目と3つ目の判定の手順は、前の判定の手順が失敗しても動く
- cooldown-judge(358行)「dependency-review の手順「Verify CI tool signatures」と同じく、版ごとに `install-verified-<道具>.sh` を使い捨ての `GITHUB_PATH` で呼ぶ」「このスクリプトが0で終わったときに確かめる」: .github/workflows/dependency-review.yaml 248-264行(`if` は `steps.ci_tool_age.outcome == 'success'`、262行が `GITHUB_PATH="$(mktemp)"`)、.github/scripts/install-verified-node.sh 38-40行、install-verified-trivy.sh 49-51行、install-verified-codex.sh 47-50行、install-verified-terraform.sh 40-42行(4つとも、自分の置き場所から最上位を決めるので、`target/` の中から main の写しを呼んでも動く) / 合っていた
- cooldown-judge(358行)「`target/` の中で、`GH_TOKEN` と `CI_TOOL_CHANGED_FILE` を渡して `check-ci-tool-release-age.sh <main_sha> <head の SHA>` を呼ぶ」: .github/scripts/check-ci-tool-release-age.sh 45-47行(今のフォルダを head の根とする)、73行(`_civ_data .`)、88行(`gh api` の比較)、97行(今のフォルダの Git で分かれ目のコミットを取る)、.github/scripts/lib-ci-tool-versions.sh 229-240行 / 合っていた
- 部品「check-ci-tool-release-age.sh の変更」(631行)「今は `PR_NUMBER` を求め、PR の本文の記録の目印の行を読んで例外を当てる」: .github/scripts/check-ci-tool-release-age.sh 69行、156-190行、206-209行 / 合っていた
- 部品 lib-claude-auto-fix.sh の `cooldown_outcome`(589行)、設計を見直すきっかけ(59行)「`check-ci-tool-release-age.sh` の終わり方は0と1と2」「`CI_TOOL_CHANGED_FILE` に変わった CI の版を書く」: .github/scripts/check-ci-tool-release-age.sh 33-39行、154行、257-259行 / 合っていた
- 部品 lib-claude-auto-fix.sh の `cooldown_needed`(585行)「`go_release_is_target` が0で終わるパス」、テストの方針(691行)「名前が小文字の `<何か>.dockerfile` のファイルと `docker/backend-go/Dockerfile.prod` で `true`」: .github/scripts/lib-go-release.sh 47-53行 / 合っていた
- 部品 lib-claude-auto-fix.sh の `cooldown_needed`(586行)「`ci-tool-versions.json` の `.tools[].ci[].file` と `.tools[].dev.file`。開発環境の版のファイルは `docker/frontend/Dockerfile` と `docker/terraform/Dockerfile`」: .github/ci-tool-versions.json 3-52行、.github/scripts/check-ci-tool-release-age.sh 105行(同じ2つの欄から書き場所のファイルを読む) / 合っていた
- テストの方針(698行)「`test-check-ci-tool-release-age.sh` に足す」: .github/scripts/tests/test-check-ci-tool-release-age.sh がある。.github/workflows/dependency-review.yaml 190-195行のテストの手順が、このテストを流す / 合っていた

### 受入基準ごとの確かめ方

| 受入基準 | 確かめる道具 | 動かす場所 | 動かすのに要るもの | design の箇所 |
|---|---|---|---|---|
| 2.9(cooldown のジョブが動く条件) | test-lib-claude-auto-fix.sh の `cooldown_needed` の場合、test-claude-auto-fix-verify.sh の `apply` の `cooldown` の場合、test-claude-auto-fix-workflows.sh(cooldown-push の `if` が出力 `cooldown` を読む) | CI は dispatch ジョブと、スクリプトを呼ぶ各ジョブ(249行、367行)。手元は alpine のコンテナ | 偽の `ci-tool-versions.json`、今ある `lib-go-release.sh`、変えたパスの一覧のファイル、yq | 583-587行、509行、347行、691行、744行、756行、760行 |
| 2.9(3つの判定の終わり方から ship と `blocked` と失敗を決める) | test-lib-claude-auto-fix.sh の `cooldown_outcome` の場合(9つの組) | 同じ | 終わり方の数の組だけ | 588-591行、692行 |
| 2.9(CI の道具と開発環境の版を72時間経っていない版に変える変更を PR にしない) | test-check-ci-tool-release-age.sh に足す `COOLDOWN_MODE=predict` の場合、test-claude-auto-fix-workflows.sh(cooldown-judge が `target/` の中で呼び、`COOLDOWN_MODE=predict` を渡す) | dependency-review.yaml の cooldown ジョブのテストの手順と、cooldown-judge(367行) | 今のテストが持つ偽の `gh` と `curl` と今の時刻の環境変数(lib-ci-tool-releases.sh 33-38行)、yq | 627-633行、358行、698行、755行 |
| 2.9(変わった CI の版の署名を確かめ、確かめられなければ `blocked`) | 無い | 無い | 無い | 手順は358行にあるが、確かめる道具は無い(D6-2-1。低) |

### 申告

**1. 開発環境の版を読めない書き方の変更は、`unfixed` でなく `unavailable` になる** — 部品 lib-claude-auto-fix.sh の `cooldown_outcome`(589行)

- Issue の記載: なし
- 決めたこと: `check-ci-tool-release-age.sh` の終わり方が2のときは、ジョブを失敗にし、結果を `unavailable` にする。終わり方の2には、Claude が `docker/frontend/Dockerfile` か `docker/terraform/Dockerfile` の FROM の行を、版を読めない書き方に変えた場合も入る(check-ci-tool-release-age.sh 132-135行)
- 他にありえた選択肢: 終わり方の2のうち、head の書き場所の版を読めない場合を `unfixed` にする
- 外れていた場合: その対象は、毎日 Claude を動かしては `unavailable` で終わり、3日後に、直せなかったことではなく、動けなかったことを知らせる Issue になる

**2. ゲートの設定のファイル `check-ci-tool-release-age.sh` に、PR を作る前の判定の形を足す** — 部品「check-ci-tool-release-age.sh の変更」(627-633行)

- Issue の記載: なし
- 決めたこと: 必須の検査 dependency-cooldown が呼ぶスクリプトに、環境変数 `COOLDOWN_MODE=predict` の分かれ道を足す。この環境変数があると、PR の本文の記録の例外を読まない
- 他にありえた選択肢: スクリプトを変えず、ガードが、`ci-tool-versions.json` の書き場所のファイルの版を変える変更を `unfixed` にする
- 外れていた場合: PR の検査の手順に誤って `COOLDOWN_MODE` が渡ると、週1回の CI の道具の更新の PR で記録の例外が当たらなくなる。今の dependency-review.yaml は、この環境変数を渡していない(234-244行)

### 指摘

| ID | レベル | 該当箇所 | 内容 | 直し方の案 |
|---|---|---|---|---|
| D6-2-1 | 低 | design.md テストの方針の test-claude-auto-fix-workflows.sh(755行)、cooldown-judge(358行) | 358行は、変わった CI の版の署名を `install-verified-<道具>.sh` で確かめ、確かめられなければ判定の終わり方を1にすると決めるが、755行のテストは、この手順があることも、終わり方を1にすることも確かめない。CI の版を書くファイルは `.github/workflows/` の中にあり、Claude の変更はガードが止めるので、この手順が動くのは、種類が `dependabot` の `base.patch` が CI の版を変えたときだけである。そのため、実装への影響は小さい | 755行に、「cooldown-judge が、`check-ci-tool-release-age.sh` の手順のあとに、`install-verified-` で始まるスクリプトを呼ぶ手順を持つこと」を足す |
| D6-2-2 | 低 | design.md 部品 claude-auto-fix-verify.sh の「対応する要件」(478行) | `apply` は、`cooldown` の出力と、npm の公開日時と pnpm の止まり方からの `blocked` を決め、テストの方針(744行、746行)も 2.9 を挙げるが、478行の対応する要件に 2.9 が無い。作るものは変わらない | 478行に 2.9 を足す |

### 前の段階への指摘

なし

- 往復: 2回で収束 / 未解決: 0件

## サイクル7 往復1(2026-11-21)

### 審査の範囲

範囲: 差分

- design.md 全体の構成(136行)、部品 claude-auto-fix-target.yaml の cooldown-push(346-349行)、テストの方針の test-claude-auto-fix-workflows.sh(755行)、安全の「書き込みの権限」(774行): 差分が、一時のブランチの push を GITHUB_TOKEN から bot の PAT に変えた行そのもの。語 `cooldown-push` `一時のブランチ` `BOT_GITHUB_TOKEN` `bot の PAT` `SHA-256` で design.md を検索した
- design.md 部品 claude-auto-fix-target.yaml の verify の出力(344行)、ship(360行)、部品 claude-auto-fix-prepare.sh の「起点の作り直し」(390行)、部品 claude-auto-fix-verify.sh の `apply`(509行)、部品 claude-auto-fix-ship.sh の役割と「push の前のガード」(521行、526-530行): bot の PAT で push する前に、push するコミットの中身を何で確かめるかを、ship ジョブと比べるため(D7-1-1)
- design.md プロジェクトの決まりを守っているか(81行): 「`push` のきっかけでは、GitHub は push されたブランチのワークフローのファイルを動かす」と書いてあり、差分の349行の「一時のブランチへの push で動くワークフローはない」の理由に関わるため(D7-1-1)
- design.md 全体の構成の図(104-111行): ジョブごとに持つ秘密の値を書いた札が、差分の136行と合うかを見るため(D7-1-2)
- design.md 部品 claude-auto-fix-target.yaml の cooldown-judge(353行、359行)と「失敗したとき」の表(371-376行): 一時のブランチを消すのは GITHUB_TOKEN のままで、cooldown-push が bot の PAT の失効で止まったときの結果が表のとおり `unavailable` になるかを見るため。表は合っている
- requirements.md 要件3の受入基準3(103行)、要件2の9: 差分の節が関わる受入基準のため。語 `PAT` `GITHUB_TOKEN` `権限` で requirements.md を検索した。受入基準は、仕組みがどのトークンで push するかを決めていないので、差分と食い違わない
- reviews/requirements-review.md と requirements-response.md: 差分に関わる、後ろの段階で書くと記録された食い違いは無い(語 `cooldown-push` `一時のブランチ` `bot の PAT` で検索し、0件)
- 言い回しだけを直した行(357行、503行、589行、639-644行、765行): 直す前の文と比べ、意味が変わっていないことを確かめた。503行から消した SARIF の説明は、342行に残っている
- そのほかの節は、差分の語が出てこないので、読み直していない

### 実ファイルで確かめた文

- cooldown-push(349行)「bot の PAT は、基盤構築手順のとおり `workflow` の権限を持つ」: doc/開発フロー/基盤構築手順.md 17-22行(classic PAT、scopes は `repo`、`read:org`、`workflow`)、76行(Secret `BOT_GITHUB_TOKEN`) / 合っていた
- cooldown-push(349行)「push で動くワークフローは、どれも main への push だけで動く」: .github/workflows/ の `push:` を持つ6つのワークフロー(ci.yaml 8-9行、codeql.yaml 31-32行、container-scan-scheduled.yaml 76-77行、dependency-graph.yaml 35-36行、sync-labels.yaml 32-33行、update-pr-branches.yaml 44-45行)は、どれも `branches: [main]`。`create:` と `delete:` のきっかけを持つワークフローは無い / main にあるワークフローについては合っていた。push するコミットの中のワークフローのファイルについては、349行の理由が足りない(D7-1-1)
- cooldown-push(349行)「GitHub が、`.github/workflows/` のファイルを変えるコミットを GITHUB_TOKEN で push させず、ワークフローの権限の欄にもそれを許す権限が無い」: リポジトリの実ファイルでは確かめられない(GitHub の側の動き)。tasks.md 498行に、タスク 6.3 の審査で分かったこととして同じことが書いてある。食い違う実ファイルは無い
- cooldown-push(349行)「ワークフローのファイルを変える Dependabot の PR の対象」: .github/scripts/check-audit-dependabot-stuck.sh 154-167行(止まった PR は、作り手が `dependabot[bot]` の PR に絞る) / 合っていた
- テストの方針(765行)「`.github/CLAUDE.md` の alpine のコンテナの `apk add`」: .github/CLAUDE.md 23行(`apk add --no-cache bash jq coreutils`。yq は無い) / 合っていた
- cooldown-judge(357行)「このスクリプトは、公開から72時間経っていない Go の版に変える変更を、例外なく止める」: サイクル6 往復1で .github/scripts/check-go-release-age.sh 20-21行、24行を確かめた文と同じ意味で、この差分は言い回しだけを変えた / 合っていた

### 受入基準ごとの確かめ方

| 受入基準 | 確かめる道具 | 動かす場所 | 動かすのに要るもの | design の箇所 |
|---|---|---|---|---|
| 3.3(Claude に GitHub の中身を変える権限を渡さない。bot の PAT を Claude が変えたコードに渡さない) | test-claude-auto-fix-workflows.sh(`secrets.BOT_GITHUB_TOKEN` が ship ジョブと cooldown-push ジョブの push の手順にだけ現れる。ジョブごとの権限が部品の節と同じ) | CI は dispatch ジョブのランナー `ubuntu-24.04`、手元は alpine のコンテナ(yq を足す) | yq | 755行、754行、765行、348行 |
| 3.1、3.2、3.3(ガードを通っていない変更を、bot の PAT で push しない) | 無い | 無い | 無い | 無い(D7-1-1)。ship ジョブでは521行と527行と766行にあるが、cooldown-push ジョブには、push の前に `final.patch` を確かめる手順も、それを確かめるテストも無い |
| 2.9(ワークフローのファイルを変えるコミットでも、一時のブランチを push して判定できる) | マージのあとの確認(767行)。偽のコマンドのテストでは、GitHub が push を断るかを確かめられない | 対象ごとのワークフローの手での起動 | bot の PAT、開いている対象 | 767行。ただし、767行は、ワークフローのファイルを変える対象で確かめるとは決めていない(D7-1-3。低) |

### 申告

なし。一時のブランチを bot の PAT で push することは、所有者が決めた(tasks.md 498行)。

### 指摘

| ID | レベル | 該当箇所 | 内容 | 直し方の案 |
|---|---|---|---|---|
| D7-1-1 | 高 | design.md 部品 claude-auto-fix-target.yaml の cooldown-push(348-349行)、安全の「書き込みの権限」(774行)、テストの方針の test-claude-auto-fix-workflows.sh(753-765行) | cooldown-push は、`final.patch` を当てたコミットを bot の PAT で push するが、push の前に `final.patch` を確かめる手順が design に無い。390行が決めているのは `base.patch` の SHA-256 だけで、`final.patch` の SHA-256 を verify ジョブの出力と比べるのは ship(521行)だけである。529行は「verify ジョブでは、ガードのあとに Claude が変えたテストとビルドスクリプトが動くので、そのコードが `final.patch` を書き換えるおそれがある」と書く。GITHUB_TOKEN のときは、書き換えられた `final.patch` がワークフローのファイルを足しても、GitHub が push を断り、push でワークフローも動かなかった。bot の PAT は `workflow` の権限を持ち、PAT の push はワークフローを動かす。81行のとおり、`push` のきっかけでは、GitHub は push されたブランチのワークフローのファイルを動かす。そのため、Claude が変えたコードが verify ジョブの `check` で `final.patch` を書き換え、`on: push` のワークフローのファイルを足すと、cooldown-push がそれを push し、そのワークフローが、リポジトリの秘密の値(bot の PAT と Claude の鍵)を読める実行として動く。ship は SHA-256 の違いで止まるが、そのときには動いたあとである。349行の理由「このジョブは Claude が変えたコードを動かさないので、Claude の変更が bot の PAT を読み出すことはない」「push で動くワークフローは、どれも main への push だけで動く」は、main にあるワークフローのファイルだけを見ていて、push するコミットの中のワークフローのファイルを見ていない。774行は「push の前の確かめ方は、ship ジョブと cooldown-push ジョブ…の節のとおり」と書くが、cooldown-push の節に確かめ方が無い。偽のコマンドのテストでは見つからず、design のとおりに作っても誰も気づかない。置き場所にある実装(`.claude/.state/claude-auto-fix-unresolved-alerts/place-1/dot-github/workflows/claude-auto-fix-target.yaml` 676行、682行)は `final.patch` の SHA-256 を比べているが、design とテストの方針が求めていないので、あとの変更でこの手順が消えても、テストも codex-review も止めない | cooldown-push の節に、次を書く。(a) このジョブは、bot の PAT を渡す前に、`final.patch` の SHA-256 が verify ジョブの出力(`apply` が、Claude が変えたコードを動かす前に書いた値)と同じであることを確かめ、違えば push せずに失敗する。(b) 349行の理由を、「SHA-256 が同じ `final.patch` は `apply` のガードを通っているので、`.github/` のファイルを変えない。そのため、push するコミットのワークフローのファイルの変更は、prepare ジョブの出力の SHA-256 で確かめた `base.patch`(dependabot[bot] の PR の変更)か、`red-check` の起点の PR の head にあるものだけである」という形に直す。ship と同じく push の前にガードをもう一度呼ぶかも決めて書く。(c) テストの方針の test-claude-auto-fix-workflows.sh に、「cooldown-push が、push の手順で `final.patch` の SHA-256 を verify ジョブの出力と比べ、違えば push しないこと」を足す |
| D7-1-2 | 低 | design.md 全体の構成の図(108-109行) | 図は、秘密の値を持つジョブに札を付けている(`ship ジョブ bot の PAT`、`edit ジョブ Claude の鍵だけ`)。`cooldown のジョブ` には札が無く、136行と348行(cooldown-push が bot の PAT を持つ)と合わない。実装には影響しない | 108行を `Cooldown[cooldown のジョブ push だけ bot の PAT]` のように直す |
| D7-1-3 | 低 | design.md cooldown-judge(353行、359行)、マージのあとの確認(767行) | cooldown-judge は、一時のブランチを GITHUB_TOKEN(`contents: write`)で消す。この差分で、一時のブランチに、ワークフローのファイルを変えるコミットが載るようになった。GitHub が断るのはワークフローのファイルを作るか変える push で、ブランチを消す操作は断らないと考えられるが、リポジトリの実ファイルでは確かめられず、design にも確かめた記録が無い。断られたときは、cooldown-judge が失敗して結果が `unavailable` になり、3日後に知らせの Issue で分かる | 767行のマージのあとの確認に、ワークフローのファイルを変える Dependabot の PR の対象があるときに、cooldown-push の push と cooldown-judge のブランチの削除が通ることを読む、と足す |

### 前の段階への指摘

なし

- 往復: 1回目 / 高1 中0 低2

## サイクル7 往復2(2026-11-21)

### 審査の範囲

範囲: 差分

- design.md 部品 claude-auto-fix-target.yaml の cooldown-push(346-353行)、テストの方針の test-claude-auto-fix-workflows.sh(766行): 差分が、D7-1-1 の直しとして足した行そのもの。語 `final_sha256` `成果物に上げ` `cooldown-push` で design.md と tasks.md を検索した
- design.md verify ジョブの6つの手順と出力(337-344行)、部品 claude-auto-fix-verify.sh の `apply` の出力(513行)、部品 claude-auto-fix-ship.sh の役割と「push の前のガード」(525行、530-534行)、部品 claude-auto-fix-guard.sh(471-478行): 349行の「`final_sha256` は `apply` の手順がガードを通した `final.patch` から出す値」「`check` は `apply` のあとに動く」と、353行の「`.github/` のファイルの変更はガードが止める」が、これらの節と合うかを見るため。合っている
- design.md 部品 claude-auto-fix-prepare.sh の「起点のコード」「起点の作り直し」(393-394行)、lib-claude-auto-fix.sh の節の Claude の変更の PR の見分け方(597行): 353行の「push するコミットのワークフローのファイルは、main のワークフローのファイルに `base.patch` と `final.patch` の変更を足したもの」が、`red-check` の起点(PR の head)でも成り立つかを見るため(D7-2-1)
- design.md 概要(7行)と claude-auto-fix.yaml の「いつ動くか」(243-247行): 概要から消した、きっかけの3つが、部品の節に残っているかを見るため。残っている
- design.md claude-auto-fix.yaml と dispatch と sweep の「失敗したとき」(251行、290行、310行): claude-auto-fix.yaml から消した文が、2つのスクリプトの節に同じ意味で残っているかを見るため。残っている
- design.md 失敗したときの扱い(691行)と、dispatch の `retry`(263行)と「失敗したとき」(290行): 書き換えた文が、dispatch の節と合うかを見るため(D7-2-2)
- design.md 安全の「想定する脅威」(781行)と、claude-auto-fix.yaml の「いつ動くか」、sweep の「赤の検査の扱い」(298行)、マージのあとの確認(777行): きっかけの並びを節の名前に替えた文が、もとの4つのきっかけと同じものを指すかを見るため(D7-2-3)
- design.md cooldown-judge(360行)と check-dependency-cooldown.sh の変更(621行、629行)、check-ci-tool-release-age.sh の変更(635行)と ship の「新しい PR」(528行): スクリプトの名前を足した文が、もとの意味のままかを見るため。意味は変わっていない
- design.md テストの方針の test-claude-auto-fix-ship.sh(771-776行): 1つの文を5つの箇条に分けた直しで、場合の数と要件の番号が変わっていないことを確かめた
- requirements.md 要件3の1と3: 差分の節が関わる受入基準のため。受入基準は、push の前の確かめ方を決めていないので、差分と食い違わない
- reviews/requirements-review.md と requirements-response.md: 語 `design` で検索した。差分に関わる、後ろの段階で書くと記録された食い違いは無い
- そのほかの節は、差分の語が出てこないので、読み直していない

### 実ファイルで確かめた文

- cooldown-push(353行)「main のワークフローは、どれも main への push だけで動く」: .github/workflows/ の `push:` のきっかけを持つ6つのワークフロー(ci.yaml 8-9行、codeql.yaml 31-32行、container-scan-scheduled.yaml 76-77行、dependency-graph.yaml 35-36行、sync-labels.yaml 32-33行、update-pr-branches.yaml 44-45行)は、どれも `branches: [main]`。`create:` `delete:` のきっかけと、`on: push` を1行で書いたワークフローは無い / 合っていた
- cooldown-push(353行)「`final.patch` の `.github/` のファイルの変更は、ガードが止める」: .github/scripts/check-escape-hatches.sh 237行(ゲートの設定のファイルの一覧に `\.github/`) / 合っていた
- cooldown-push(353行)「Dependabot は、ワークフローのファイルの中では版だけを変える」: .github/dependabot.yml 85-86行(`package-ecosystem: "github-actions"`、`directory: "/"`)。Dependabot が版のほかを変えないことは GitHub の側の動きで、リポジトリの実ファイルでは確かめられない。食い違う実ファイルは無い
- cooldown-push(349行)「`final_sha256` は、verify ジョブの `apply` の手順が…出す値」「`check` の手順は、`apply` の手順と、`final.patch` を成果物に上げる手順のあとに動く」: 置き場所の .claude/.state/claude-auto-fix-unresolved-alerts/place-1/dot-github/workflows/claude-auto-fix-target.yaml 292行(`final_sha256: ${{ steps.apply.outputs.sha256 }}`)、380行(Apply Claude patch)、390行(Upload final patch)、432行(Check changed areas)、672-682行(push の手順が `final.patch` の SHA-256 を `FINAL_SHA256` と比べる) / 合っていた
- design-response.md サイクル7 往復1 D7-1-1「置き場所のテストには、この場合が既にある」: 置き場所の scripts/tests/test-claude-auto-fix-workflows.sh 721行、939-940行 / 合っていた
- lib-claude-auto-fix.sh の節(597行)「Claude の変更の PR とみなすのは、このリポジトリのブランチから出され…」: 置き場所の scripts/lib-claude-auto-fix.sh 281-296行(head のリポジトリがこのリポジトリであることを求める) / 合っていた

### 受入基準ごとの確かめ方

| 受入基準 | 確かめる道具 | 動かす場所 | 動かすのに要るもの | design の箇所 |
|---|---|---|---|---|
| 3.1、3.3(ガードを通っていない変更を、bot の PAT で一時のブランチに push しない) | test-claude-auto-fix-workflows.sh(cooldown-push の push の手順が、`final.patch` の SHA-256 を verify ジョブの出力 `final_sha256` と比べ、同じときだけ当てて push する。`secrets.BOT_GITHUB_TOKEN` が ship ジョブと cooldown-push ジョブの push の手順にだけ現れる) | CI は dispatch ジョブのランナー `ubuntu-24.04`、手元は alpine のコンテナ(yq を足す) | yq、偽の `git` の push | 766行、759行、770行、349行 |
| 3.1、3.2(ship ジョブが、ガードを通っていない変更を push しない) | test-claude-auto-fix-ship.sh(差分の SHA-256 が違えば push しない。`.github/` の変更か `@SuppressWarnings` の行でガードが止める) | 同じ | 偽の `gh` と `git` の push | 771-774行。箇条に分けただけで、場合は変わっていない |

### 申告

なし。この往復の差分は、前の往復の指摘の直しと、書き方の直しだけである。

### 指摘

| ID | レベル | 該当箇所 | 内容 | 直し方の案 |
|---|---|---|---|---|
| D7-2-1 | 低 | design.md 部品 claude-auto-fix-target.yaml の cooldown-push(353行) | 353行は「このジョブが push するコミットのワークフローのファイルは、main のワークフローのファイルに、`base.patch` と `final.patch` の変更を足したものである」と書く。`reason` が `red-check` のときは、393-394行のとおり、cooldown-push は `base_sha`(Claude の変更の PR の head)を checkout し、`base.patch` は無い。このときの push するコミットのワークフローのファイルは、PR の head のファイルに `final.patch` の変更を足したものである。PR の head は、597行のとおり、このリポジトリのブランチにあり、ship ジョブがガードを通して push したコミットと、main の取り込みでできている。そのため、「一時のブランチへの push で動くワークフローはない」という結論は変わらず、SHA-256 の比較とガードの作りも変わらない。理由の文が `red-check` の場合を書いていないだけで、実装には影響しない | 353行に、「`red-check` のときは、起点が Claude の変更の PR の head で、その head のワークフローのファイルは、ship ジョブがガードを通して push したコミットと main の取り込みでできている」を足す |
| D7-2-2 | 低 | design.md 失敗したときの扱い(691行) | 書き換えた文は「前の実行が扱えなかった対象も、次の実行で扱う」と書く。dispatch の節は、起動しなかった対象を「次のきっかけか所有者の手での起動で動いたときに扱う」と書き(290行)、1時間ごとの定期実行は「ふだんは対象を新しく集めず」、結果のファイルから選ぶと書く(263行)。起動できなかった対象には結果のファイルが無いので、次の1時間ごとの実行では扱われない。691行の「次の実行」は、290行より広く読める。作るものは部品の節が決めるので、実装には影響しない | 691行の終わりを、「前の実行が起動できなかった対象は、dispatch の節の「失敗したとき」のとおり、次のきっかけか所有者の手での起動で扱う」のように、290行と同じ範囲にする |
| D7-2-3 | 低 | design.md 安全の「想定する脅威」(781行) | 書き換えた文は、きっかけを「claude-auto-fix.yaml の節の「いつ動くか」と、claude-auto-fix-sweep.sh の節の「赤の検査の扱い」に書いたものに限る」と書く。対象ごとのワークフローは `workflow_dispatch` で動き(318行)、777行は、この spec を実装した Claude が claude-auto-fix-target.yaml を手で起動すると書く。この手での起動は、挙げた2つの節のどちらにも書かれていない。直す前の文の「所有者の手での起動」は、これも含めて読めた。書き込みの権限を持つ者しか `workflow_dispatch` を起動できないので、想定する脅威の範囲は変わらず、実装には影響しない | 781行に、「claude-auto-fix-target.yaml を、書き込みの権限を持つ者が手で起動したとき」を足す |

### 前の段階への指摘

なし

- 往復: 2回で収束 / 未解決: 0件
