# 調べたこと

## Summary

- **Feature**: `claude-auto-fix-unresolved-alerts`
- **Discovery Scope**: Complex Integration(今ある検査とワークフロー、GitHub の API、Claude の CLI をつなぐ新しい仕組み)
- **Key Findings**:
  - claude-code-action を使わず、Claude の CLI を、配布元の署名で確かめてから直接動かす。claude-code-action は、浮動のタグで壊れる変更を取り込み、利用者でない起動者を拒み、GitHub のトークンを用意するためである。CLI は `--tools` と `--settings` の拒否の決まりで、使える道具をファイルの読み書きだけに絞れる
  - Claude を動かすジョブ(秘密の値は Claude の鍵だけ、`contents: read`、リポジトリのコードを動かさない)と、変更を確かめるジョブ(秘密の値を持たない)を分ける。dependency-review.yaml が、PR のビルドスクリプトを動かすジョブと送信するジョブを分けているのと同じ考え方である
  - 状態を別の場所に持たず、実行の記録(1回の実行ごとの結果のファイル)と、bot が書いた Issue とコメントの目印と、コミットの末尾の行から読み直す。今の仕組み(container-scan-issue.sh、lib-notice-comment.sh)と同じ考え方である
  - 止まった Dependabot の PR の赤から、`dependency-review` と期待一覧の `approval_gated` が true の4つの検査を除き、赤が残る PR だけで Claude を動かす(要件1の4)。週次監査の一覧の JSON に承認待ちに分けた赤も書き、dispatch ジョブと prepare ジョブの両方で同じ関数で除く。`retry` は前の実行の入力で動くので、prepare ジョブで実行の時点の赤を読み直す

## 今あるものについて確かめた文

- requirements.md 範囲の前提「frontend-vuln-fix と backend-vuln-fix は毎日動く」: .github/workflows/frontend-vuln-fix.yaml 10-12行、.github/workflows/backend-vuln-fix.yaml 7-9行
- requirements.md 要件1の1「frontend-vuln-fix は、検査に通らない組では PR を作らず、消せなかった警告を実行の記録に出して失敗で終える」: .github/scripts/frontend-vuln-fix.sh 7-9行、150-156行
- requirements.md 要件1の1「backend-vuln-fix は、Java 版の部品の警告と、Go 版の部品と標準ライブラリの脆弱性を扱い、直せないと失敗で終える」: .github/scripts/backend-vuln-fix.sh 1-7行、122行、191行、229行、242行
- requirements.md 要件2の1「今の2つのワークフローは、部品と修正版の組ごとに PR を1つ作り、同じ組のブランチがあれば作らない」: .github/scripts/frontend-vuln-fix.sh 2-3行、10行、137-140行、.github/scripts/backend-vuln-fix.sh 1-3行
- requirements.md 要件1の2・要件5「週次監査は、main に開いたままの CodeQL の警告の数とリンクだけを書き、場所と中身を書かない」: .github/scripts/check-audit-codeql-alerts.sh 3-25行、.github/workflows/audit-weekly.yaml 241行
- requirements.md 要件1の3「仕組みは、本番で動いているイメージに見つかった脆弱性ごとに、ラベル container-vuln の Issue を起票し、検出されなくなったら閉じる」: .github/scripts/container-scan-issue.sh 3-17行、102行、.github/workflows/container-scan-scheduled.yaml 3行、8行、20行
- 決めた方式「修正版がある脆弱性」: 起票の対象は、修正版があり深刻度が CRITICAL か HIGH の脆弱性である。.github/scripts/check-container-scan.sh 251-252行、264-268行
- requirements.md 要件1の4「週次監査は、必須の検査が赤のまま止まった Dependabot の PR を見つける」: .github/scripts/check-audit-dependabot-stuck.sh 3-18行
- requirements.md 要件1の4「新しい脆弱性を見つける検査は dependency-review という名前の必須の検査である」: .github/audit/required-checks.json 23行
- requirements.md 要件2の3「仕組みは、bot が作った main 向けの PR に auto-merge を予約し、必須の検査と承認がそろうとマージされる」: .github/workflows/auto-merge.yaml 4-8行、44-52行
- requirements.md 範囲の決めないこと「codex-review は今は動いていない」: .github/audit/required-checks.json 10-17行、.github/workflows/codex-review.yml 37-44行
- requirements.md 要件2の4「同じ失敗が3回続いたら止める」: CLAUDE.md 52行
- requirements.md 要件3の1・2・3: ゲートの設定のファイルの一覧と、見かけの合格を作らない決まりと、警告の却下の決まりは CLAUDE.md の「自律動作の境界」の節にある
- requirements.md 要件7の1「基盤構築手順に、リポジトリに登録する秘密の値の一覧がある」: doc/開発フロー/基盤構築手順.md 70-76行
- requirements.md 要件7の3「手順書には繰り返し使う手順だけを書き、1回きりの手順は PR の本文に書く」: doc/CLAUDE.md 20-21行
- requirements.md 要件1・要件5「リポジトリは公開されている」: `gh repo view --json visibility` が PUBLIC を返した(2026-11-13)
- 既存の spec の関わり: .kiro/specs/source-code-vulnerability-scanning/design.md 23行は、main に残った CodeQL の警告を直す仕組みを Issue #725 で作ると書いている
- design.md 部品の節 vuln-fix の2つのスクリプト「frontend-vuln-fix.sh は、組ごとの繰り返しの中の7か所で failed=1 にして次の組へ進む」: .github/scripts/frontend-vuln-fix.sh 128-171行(142行、146行、150行、153行、155-156行、166行、168行)
- design.md 部品の節 vuln-fix の2つのスクリプト「backend-vuln-fix.sh の run は、main の依存を解決できないと、組を読んだあとに return 1 で終わる」: .github/scripts/backend-vuln-fix.sh 102-105行
- design.md 部品の節 vuln-fix の2つのスクリプト「backend-vuln-fix.sh の run は4か所、go_run は4か所で failed=1 にする。go_run は govulncheck の JSON を読めないと組を読む前に return 1 で終わる」: .github/scripts/backend-vuln-fix.sh 117行、122行、131行、133行、210行、215行、228-229行、241-242行
- design.md 部品の節 vuln-fix の2つのワークフロー「ワークフローの名前は Frontend Transitive Vulnerability Fix と Backend Vulnerability Fix で、backend には backend-vuln-fix と backend-go-vuln-fix の2つのジョブがある」: .github/workflows/frontend-vuln-fix.yaml 1行、.github/workflows/backend-vuln-fix.yaml 1行、16行、33行
- design.md 部品の節 claude-auto-fix.yaml「GITHUB_TOKEN の vulnerability-alerts: read で Dependabot の警告を読む」: .github/workflows/dependency-review.yaml 168-174行(contents: read、pull-requests: write、vulnerability-alerts: read)
- design.md 部品の節 claude-auto-fix.yaml「GitHub の定期実行は遅れることがあり、GITHUB_TOKEN の workflow_dispatch は新しい実行を作る」: .github/workflows/codeql-recheck.yaml 11-21行(#783 の遅れ)、168行(`gh workflow run codeql-recheck.yaml --repo "$REPO" --ref main`)
- design.md 部品の節 claude-auto-fix-verify.sh「make mutation-diff は BASE を求める」: backend/Makefile 109-112行
- design.md 部品の節 claude-auto-fix-verify.sh「backend-go は setup-go を go-version-file: backend/go.mod で使い、golangci-lint-action v9.3.0 に version v2.15.0 を渡し、make check を流し、pull_request のときだけ make mutation-diff BASE=origin/<base> を流す」: .github/workflows/ci.yaml 412-472行
- design.md 部品の節 claude-auto-fix-verify.sh「backend-compat は make compat と make compat-cross を流す。backend_compat は backend/compat/ があり Java 版か Go 版か compat が変わったときに true になる」: .github/workflows/ci.yaml 96-127行、474-509行
- design.md 部品の節 claude-auto-fix-verify.sh「dockerfile の見分けは docker/**/Dockerfile* である。e2e-smoke は frontend が変わったときに動く」: .github/workflows/ci.yaml 89-90行、276-279行
- design.md 部品の節 claude-auto-fix-verify.sh「frontend-vuln-fix.sh は frontend_test(品質チェック)と vulnerable <lock> <名前> <範囲> を引数で呼べ、ブランチ名は chore/frontend-vuln-fix-… で、同じ名前のブランチを ls-remote で探す」: .github/scripts/frontend-vuln-fix.sh 17-19行、53-62行、96-115行、136行、139行、173-176行
- design.md 部品の節 claude-auto-fix-verify.sh「backend-vuln-fix.sh の引数で呼べるのは run、go_run、plan、resolved、vulnerable、decide、pin、go_plan で、tree、vulncheck、go_bump は呼べない。Java の組のブランチ名は chore/backend-vuln-fix-<スラグ> である」: .github/scripts/backend-vuln-fix.sh 46-61行、71行、85-88行、110行、142-156行、246-248行
- design.md 部品の節 claude-auto-fix-verify.sh「go_bump は go.mod の toolchain の行と、GO_DOCKERFILES の4つの Dockerfile の golang のイメージの版と digest を上げる」: .github/scripts/backend-vuln-fix.sh 139行、161-177行
- design.md 部品の節 claude-auto-fix-target.yaml「main のほかのブランチへの push で動くワークフローは無い」: .github/workflows/ci.yaml 8-9行、codeql.yaml 31-32行、container-scan-scheduled.yaml 76-77行、dependency-graph.yaml 35-36行、sync-labels.yaml 32-33行、update-pr-branches.yaml 36-37行
- design.md 部品の節 claude-auto-fix-target.yaml「CodeQL の analyze ジョブは、書き込みの権限を持たずに PR のコードを動かす」: .github/workflows/codeql.yaml 64-70行、125-128行、157-159行
- design.md 部品の節 claude-auto-fix-target.yaml「Java 版と Go 版の本番のイメージは、container-scan のジョブが ubuntu-24.04-arm で --platform linux/arm64 で組み立てる。定期の検査は Go 版だけを main から組み立て、Java 版は動いているイメージを調べる」: .github/workflows/container-scan.yaml 153-159行、221-229行、.github/workflows/container-scan-scheduled.yaml 110-112行、148-153行、212-216行、294行
- design.md 部品の節 check-dependency-cooldown.sh「流れは、警告との照合、悪意のある部品の一覧、署名した者、pnpm の除外の欄、記録のコメント、所有者の承認の6つで、PR_NUMBER を必須にする」: .github/scripts/check-dependency-cooldown.sh 40-41行、47-55行、62-71行
- design.md 部品の節 claude-auto-fix-guard.sh「名前が ignore で終わるファイルは .gitleaksignore、frontend/.prettierignore、backend/.dockerignore と4つの .gitignore である」: `git ls-files` の結果(2026-11-13)
- design.md 部品の節 frontend-vuln-fix.sh と backend-vuln-fix.sh「frontend-vuln-fix は bot の PAT で警告を読み、PR を作る」: .github/workflows/frontend-vuln-fix.yaml 6行、41行
- design.md 全体の構成「週次監査のワークフローの名前は Audit Weekly で、秘密の値を使わない」: .github/workflows/audit-weekly.yaml 1行、63-72行
- design.md 部品の節 claude-auto-fix-dispatch.sh「CodeQL の警告の一覧は ref=refs/heads/main と tool_name=CodeQL で読む」: .github/scripts/check-audit-codeql-alerts.sh 111-114行
- design.md 部品の節 check-audit-dependabot-stuck.sh「PR ごとに、期待一覧に載る検査の最新の結論を読み、approval_gated の検査の赤を承認待ちに分ける。dependency-cooldown の赤は、記録のコメントが無ければ止まったものに数える」: .github/scripts/check-audit-dependabot-stuck.sh 150行、194-224行、226-235行
- design.md 部品の節 claude-auto-fix-dispatch.sh「approval_gated の必須の検査は escape-hatch、dependency-gate、pre-merge-check、dependency-cooldown の4つである」: .github/audit/required-checks.json 6行、18行、19行、24行
- design.md 部品の節 claude-auto-fix-target.yaml「Go 版の本番のイメージは、ubuntu-24.04-arm で docker buildx の type=docker の出力で組み立て、Trivy で調べ、check-container-scan.sh の report で判定する」: .github/workflows/container-scan-scheduled.yaml 110-112行、143-154行、158-196行
- design.md 部品の節 claude-auto-fix-target.yaml「Java 版と Go 版の本番のイメージの Dockerfile は docker/backend/Dockerfile.prod と docker/backend-go/Dockerfile.prod で、組み立ての文脈は ./backend である」: .github/workflows/container-scan.yaml 4-5行、159行、221-229行
- design.md 部品の節 claude-auto-fix-target.yaml「定期のコンテナの検査のワークフローの名前は Scheduled Container Image Vulnerability Scan で、Trivy の版は 0.76.2 である」: .github/workflows/container-scan-scheduled.yaml 1行、99行
- design.md 部品の節 claude-auto-fix-dispatch.sh「ラベル container-vuln の Issue の題名は『コンテナ脆弱性: <ID>』で、状態は github-actions[bot] が書いた本文とコメントの container-scan-state の目印から読む。状態の行は深刻度と修正版の有無を持つ」: .github/scripts/container-scan-issue.sh 23-30行、63-69行、114-121行、154-162行
- design.md 部品の節 check-dependency-cooldown.sh「今の判定は PR_NUMBER を必須にし、記録のコメントを書いてから所有者の承認を確かめる」: .github/scripts/check-dependency-cooldown.sh 40-58行、62-71行、423-435行、616-631行
- design.md 部品の節 claude-auto-fix-target.yaml「dependency-review は、ビルドスクリプトを動かすジョブ(contents: read)と、スナップショットを送るだけのジョブ(contents: write、checkout しない)を分け、gradle/actions/dependency-submission v6.4.1 に productionRuntimeClasspath と detachedConfiguration の除外を渡す」: .github/workflows/dependency-review.yaml 1-27行、42-91行、93-111行
- design.md 部品の節 claude-auto-fix-guard.sh「escape-hatch の検査は base と head を引数に取り、PR_BODY と OWNER_APPROVED を環境変数で読む。ゲートの設定のファイルの正規表現は Makefile と .golangci.yml などの Go 版の設定も含む」: .github/scripts/check-escape-hatches.sh 41-45行、217行
- design.md 部品の節 claude-auto-fix-guard.sh「escape-hatch は、@Disabled、t.Skip、ts-ignore、eslint-disable、nolint と coverage-ignore、frontend と Java のテストのアサーションの削除を見つける。Go のテストのアサーションの削除は見つけない」: .github/scripts/check-escape-hatches.sh 163-208行
- design.md 部品の節 claude-auto-fix-target.yaml「CI の変更の領域の見分けは frontend、backend_java、backend_go、backend_compat、dockerfile で、それぞれのジョブの手順は frontend-test、backend-java、backend-go、backend-compat、docker-smoke にある」: .github/workflows/ci.yaml 55-89行、209-254行、331-370行、412-449行、474-512行、553-597行
- design.md 部品の節 claude-auto-fix-target.yaml「CodeQL の診断は、言語ごとに .github/codeql/languages.tsv のビルドのしかたで、upload: never で SARIF を作る」: .github/workflows/codeql.yaml 64-119行、.github/codeql/languages.tsv 22-40行
- design.md 部品の節 claude-auto-fix-target.yaml「CodeQL は .github/workflows/ の下と action.yml も actions の言語として診断する」: .github/codeql/languages.tsv 34-37行
- design.md 部品の節 claude-auto-fix-report.sh「Issue を探し・作り・コメントし・所有者に割り当てる共通の関数と、目印つきのコメントを1回だけ付ける共通の関数がある」: .github/scripts/lib-ledger-issue.sh 27-44行、.github/scripts/lib-notice-comment.sh 36-51行
- design.md ファイルの構成「ラベルの一覧は .github/labels.json にあり、container-vuln は group other である」: .github/labels.json 87-92行
- design.md ファイルの構成「CI の道具の版の一覧は tools と excluded を持ち、excluded の組は file と key と reason を持つ。Node.js と Trivy の ci の場所の一覧がある」: .github/ci-tool-versions.json 1-30行、54-60行
- design.md プロジェクトの決まり「版の書き場所の検査は、ワークフローとアクションの版の行が、道具の ci か excluded に無いと赤にし、棚卸しの対象の一覧が道具の ci のファイルを全部含むかも確かめる」: .github/scripts/check-ci-tool-placement.sh 3-19行、.github/audit/inventory-targets.json 37-46行、74-90行
- design.md 部品の節 verified-claude「検証付きの導入の部品は、アクションの中から .github/scripts/install-verified-*.sh を呼ぶ形である」: .github/actions/verified-codex/action.yml 1-17行、.github/scripts/install-verified-codex.sh 1-30行
- design.md 部品の節 claude-auto-fix-target.yaml「update-pr-branches は bot の PAT で、開いている PR のブランチに main を合わせる」: .github/workflows/update-pr-branches.yaml 5-28行
- design.md 部品の節 claude-auto-fix-target.yaml「auto-merge は、Dependabot、カナリア、fork のほかの main 向けの PR に予約を付ける」: .github/workflows/auto-merge.yaml 43-47行、84-92行
- design.md ファイルの構成「基盤構築手順の 3-1 の表は Secret と値と失効したときの3列で、bot の PAT の復旧の節がある」: doc/開発フロー/基盤構築手順.md 62-78行、313-345行
- design.md ファイルの構成「README のワークフローの一覧の表に vuln-fix の2つの行があり、Mermaid の図の PR の節が作り手を並べている」: README.md 53-55行、124-125行
- design.md ファイルの構成「ブランチ名は <type>/<short-description> で、type に fix がある」: .branch_name_template 5-16行

- design.md 部品の節 claude-auto-fix-verify.sh「frontend-vuln-fix.sh は run、plan、vulnerable、decide、override、exclude、frontend_test を外から呼べる」: .github/scripts/frontend-vuln-fix.sh 173-174行
- design.md 部品の節 claude-auto-fix-verify.sh「backend-vuln-fix.sh の digest は docker buildx imagetools inspect でイメージの digest を読み、go_bump は Go の版を上げる」: .github/scripts/backend-vuln-fix.sh 158行、161-176行。外から呼べるのは 246-247行の run、go_run、plan、resolved、vulnerable、decide、pin、go_plan だけである
- design.md 部品の節 claude-auto-fix-verify.sh「frontend-test は pnpm/action-setup v6.1.1 を package_json_file: frontend/package.json で動かし、verified-node 24.22.2 を入れる」: .github/workflows/ci.yaml 209-244行
- design.md 部品の節 claude-auto-fix-verify.sh「mutation-diff は fetch-depth: 0 で checkout する」: .github/workflows/ci.yaml 423-472行
- design.md 部品の節 claude-auto-fix-verify.sh「backend-compat は KEIREKIPRO_REPO_ROOT に github.workspace を渡し、poppler-utils を入れて make compat と make compat-cross を動かす」: .github/workflows/ci.yaml 474-509行
- design.md 部品の節 claude-auto-fix-verify.sh「本番のイメージの FROM は、Java 版が eclipse-temurin、Go 版が golang と chromedp/headless-shell である」: docker/backend/Dockerfile.prod 4行、28行、docker/backend-go/Dockerfile.prod 11行、41行
- design.md プロジェクトの決まり「差分比較の API は、PR の head でない main のコミットにも npm、gomod、maven の差を返した」: 2026-11-13 に `gh api repos/DogisRiki/KeirekiPro/dependency-graph/compare/<親>...<コミット>` を f74a8d15(frontend/pnpm-lock.yaml の npm)、87cf9330(backend/go.mod の gomod)、94036fe7(backend/settings.gradle の maven)で動かした
- design.md 部品の節 claude-auto-fix-run-claude.sh「版 2.1.323 の manifest.json、manifest.json.sig、linux-x64/claude が配布元にある」: 2026-11-13 に https://downloads.claude.ai/claude-code-releases/2.1.323/ の3つのファイルが HTTP 200 を返した
- design.md 部品の節 check-audit-dependabot-stuck.sh の変更「週次監査は、期待一覧に載る検査の最新の結論が failure、cancelled、timed_out、action_required のものを赤と数え、approval_gated の検査の赤を承認待ちに分け、記録のコメントの無い dependency-cooldown の赤を止まったものに数える。承認待ちの赤だけの PR は止まった PR に数えない」: .github/scripts/check-audit-dependabot-stuck.sh 193-207行、209-225行、228-236行(2026-11-14 に開き直した)
- design.md 部品の節 check-audit-dependabot-stuck.sh の変更「終わり方は0が止まった PR 無し、1が止まった PR あり、2が判定できない」: .github/scripts/check-audit-dependabot-stuck.sh 21-25行、260-277行
- design.md 部品の節 claude-auto-fix-dispatch.sh「approval_gated が true の検査は escape-hatch、dependency-gate、pre-merge-check、dependency-cooldown の4つで、dependency-review は false である」: .github/audit/required-checks.json 6行、18行、19行、23行、24行(2026-11-14 に開き直した)
- design.md 部品の節 claude-auto-fix-target.yaml の prepare「PR の head のコミットの検査の結論を読むのに checks: read を使う」: .github/workflows/audit-weekly.yaml 67-71行(週次監査は同じ読み込みに checks: read を持つ)
- design.md 部品の節 claude-auto-fix-dispatch.sh「定期のコンテナの検査は、毎日と、Production Release の完了のあとと、backend/ か docker/backend-go/ を変えた main への push のあとに動く」: .github/workflows/container-scan-scheduled.yaml 1-14行、70-80行(#823 の変更)
- design.md 部品の節 claude-auto-fix-dispatch.sh「container-scan-state の目印の JSON は rows を持ち、行ごとに severity と fixed を持つ。目印は github-actions[bot] が書いた本文とコメントの最後のものから読む」: .github/scripts/container-scan-issue.sh 20-30行、66-70行、154-162行
- design.md 部品の節 claude-auto-fix-target.yaml の cooldown-judge「判定の4つ目は、環境変数 PNPM_WORKSPACE_FILE(既定は frontend/pnpm-workspace.yaml)の除外の欄を読む」: .github/scripts/check-dependency-cooldown.sh 81行、600-613行(2026-11-14 に開いた)
- design.md 部品の節 claude-auto-fix-target.yaml の cooldown-generate「今の dependency-review.yaml と dependency-graph.yaml は GITHUB_DEPENDENCY_GRAPH_SHA と GITHUB_DEPENDENCY_GRAPH_REF を使っていない」: .github/workflows/dependency-review.yaml 72-83行、103-111行、.github/workflows/dependency-graph.yaml(2026-11-14 に開いた)
- design.md テストの方針 test-claude-auto-fix-workflows.sh「手元のテストは alpine のコンテナに apk add で道具を入れて流す」: .github/CLAUDE.md 23行、62行。`.github/` の中に yq を使うスクリプトは無い(2026-11-14 に grep で確かめた)

## 外部の文書で確かめたこと

- GitHub Actions で Claude を動かす方法は、Claude の API キーか、Claude の契約で認証する OAuth のトークンの2つである。OAuth のトークンで動かすと、費用は Claude の契約の使える量から払われる。https://code.claude.com/docs/en/github-actions の「Manual setup」と「Manage costs」
- OAuth のトークンは、Claude の契約を持つ人が手元で `claude setup-token` を打って作り、1年で切れる。https://code.claude.com/docs/en/authentication の「Generate a long-lived token」
- Gradle の依存のスナップショットのコミットとブランチは、環境変数 `GITHUB_DEPENDENCY_GRAPH_SHA` と `GITHUB_DEPENDENCY_GRAPH_REF` で決まる。https://github.com/gradle/github-dependency-graph-gradle-plugin の README の「Required environment variables」。gradle/actions はこの2つをワークフローで上書きできると書く。https://github.com/gradle/actions/blob/main/docs/dependency-submission.md の「Configuration parameters」。`generate-and-upload` と `download-and-submit` のどちらの側で読まれるかは、文書に明記されていない
- pnpm は、`minimumReleaseAge` の決まりで入れられる版が無いときに `ERR_PNPM_NO_MATURE_MATCHING_VERSION` を出す。https://github.com/pnpm/pnpm/pull/10618 。`package.json` に版を固定したときのエラーの文は確かめていない
- GitHub のホストランナー ubuntu-24.04 のイメージ 20261111.370.1 には yq 4.54.3 が入っている。https://github.com/actions/runner-images/blob/main/images/ubuntu/Ubuntu2404-Readme.md(2026-11-14 に読んだ)
- claude-code-action は、`prompt` を渡すと、コメントでの呼び出しを待たずに動く。schedule と workflow_dispatch で動かす例がある。https://github.com/anthropics/claude-code-action/blob/main/docs/solutions.md の「Scheduled Repository Maintenance」

## 件数

- ラベル container-vuln の Issue の起票の数は、2026年8月が74件、9月が4件、10月が7件、11月(13日まで)が1件だった
- frontend-vuln-fix と backend-vuln-fix の直近100回の実行に、失敗で終わったものは無かった(2026-11-13 に確かめた)

## Research Log

### Claude を GitHub Actions の中でどう動かすか

- **Context**: 要件1の6(きっかけを限る)と要件3の3(Claude に GitHub の中身を変える権限を渡さない)を満たす動かし方を選ぶ
- **Sources Consulted**: https://code.claude.com/docs/en/github-actions 、https://github.com/anthropics/claude-code-action/releases/tag/v1.0.273 、https://code.claude.com/docs/en/cli-reference 、https://code.claude.com/docs/en/headless 、https://code.claude.com/docs/en/permissions 、https://code.claude.com/docs/en/settings
- **Findings**:
  - claude-code-action の v1 の浮動のタグは、壊れる変更を取り込んだことがある。起動者が人の利用者でないときに動かない設定があり、GitHub のトークンを自分で用意する
  - CLI の `claude -p` は、`--output-format json` で結果を JSON で出し、`--tools` で使える道具を絞り、`--strict-mcp-config` で MCP の設定を読まず、`--permission-mode acceptEdits` で編集の許可を求めずに進み、`--max-turns` で往復の数を限る
  - `--setting-sources user` と、空のフォルダを指す HOME と `CLAUDE_CONFIG_DIR` で、リポジトリの `.claude/settings.json` とフックを読ませない。`--settings` で渡す設定の `disableAllHooks` と `permissions.deny` で、フックを止め、Bash・WebFetch・WebSearch と特定の場所の読み込みを拒める
- **Implications**: claude-code-action を使わず、CLI を直接動かす。CLI は配布元の署名で確かめてから入れる

### Claude の CLI の入れ方

- **Context**: CI で使う道具は、配布元の署名か来歴を確かめてから入れる(verified-node、verified-codex、verified-trivy、verified-terraform と同じ)
- **Sources Consulted**: https://code.claude.com/docs/en/setup
- **Findings**:
  - 実行ファイルは `https://downloads.claude.ai/claude-code-releases/<版>/linux-x64/claude` から取れる
  - 同じ版の `manifest.json` と、その GPG の署名 `manifest.json.sig` がある。署名の鍵は `https://downloads.claude.ai/keys/claude-code.asc` で、指紋は `31DD DE24 DDFA B679 F42D 7BD2 BAA9 29FF 1A7E CACE` である
  - `manifest.json` の `platforms.linux-x64.checksum` が実行ファイルの SHA-256 である
- **Implications**: `install-verified-claude.sh` は、鍵の指紋を照らし、署名を確かめ、実行ファイルの SHA-256 を照らしてから PATH に足す。版は 2.1.323 に固定する

### Claude の鍵と失敗の見分け方

- **Context**: 要件6の1と3で、鍵が無いか切れたときと、ほかの理由で動けなかったときを分ける
- **Sources Consulted**: https://code.claude.com/docs/en/authentication 、https://code.claude.com/docs/en/errors 、https://code.claude.com/docs/en/legal-and-compliance
- **Findings**:
  - CLI は、環境変数 `CLAUDE_CODE_OAUTH_TOKEN` の OAuth のトークンで認証できる
  - 認証の失敗(`authentication_failed`、OAuth のトークンの期限切れと取り消し)は、使える量の上限(rate_limit)と、実行の失敗(error_during_execution)と分けて報告される
  - `-p` の実行で OAuth のトークンが取り消されたか切れたときの結果の文は `Failed to authenticate` で始まる。使える量の上限の文は `You've hit your session limit` か `weekly limit` を含み、429 は速さの上限である(https://code.claude.com/docs/en/errors)
  - 結果の JSON は `type: result`、`subtype`(`success`、`error_max_turns`、`error_during_execution`、`error_max_budget_usd`、`error_max_structured_output_retries`)、`is_error`、`api_error_status` を持つ。`--max-turns` に達すると `error_max_turns` になり、0以外で終わる(https://code.claude.com/docs/en/agent-sdk/typescript 、https://code.claude.com/docs/en/agent-sdk/agent-loop)。実際に動かした結果では確かめていない
  - `permissions.blockReadsOutsideWorkingDirectories` と `permissions.blockWritesOutsideWorkingDirectories` は、作業のフォルダの外の読み書きを断る。書き込みの設定は版 2.1.314 からある(https://code.claude.com/docs/en/settings)
  - 契約の使える量を自動の処理で使うことについて、Anthropic の利用の決まりは「普通の使い方」を前提にしている
- **Implications**: 秘密の値が空か、結果が認証の失敗なら「鍵」、上限・時間切れ・実行の失敗・結果が読めないときは「動けなかった」に分ける。普通の使い方を超えないよう、1回の実行の往復の数と、同じ対象を動かす回数(自動のきっかけでは1日に1回)を限る

### 依存グラフの送信と差分比較を PR の無いブランチで使えるか

- **Context**: 要件2の9で、PR を作る前に、dependency-cooldown が変更をどう扱うかを同じ結果になるように確かめる
- **Sources Consulted**: https://github.com/gradle/github-dependency-graph-gradle-plugin 、https://github.com/gradle/actions/blob/main/docs/dependency-submission.md 、https://docs.github.com/en/rest/dependency-graph/dependency-review
- **Findings**:
  - gradle/actions/dependency-submission は、環境変数 `GITHUB_DEPENDENCY_GRAPH_SHA` と `GITHUB_DEPENDENCY_GRAPH_REF` で、送るスナップショットのコミットとブランチを指定できる
  - 差分比較の API は、2つのコミットの依存の差を返す。PR の無いブランチのコミットについて、npm と gomod の静的なマニフェストの差を返すかは、文書に書かれていない
  - 2026-11-13 に、PR の head でない main のコミット3つ(f74a8d15、87cf9330、94036fe7)で差分比較の API を動かし、npm、gomod、maven の差が返ることを確かめた。2026-11-14 に、所有者の許しを受けて、main の d2546e6d から backend/go.mod の golang-jwt の版と frontend/pnpm-lock.yaml の zod の版を1つずつ変えたコミット 23d28833 を一時のブランチ chore/tmp-dependency-compare-check に作り、`gh api repos/DogisRiki/KeirekiPro/dependency-graph/compare/d2546e6d...23d28833` を動かした。ブランチを作った直後に、gomod と npm の追加と削除の差が返った。確かめたあと、ブランチを消した。閉じた PR #744 のブランチ feat/trending-vulnerability-impact では空の結果が返ったが、このブランチはテストの見本のロックファイルだけを変えていたので、判定の材料にならない
- **Implications**: 予測の判定は、ブランチを push してから Gradle のスナップショットを送り、差分比較を読む。判定できないときは赤とみなす(fail closed)。静的なマニフェストの扱いは残る危うさとして記録する

### GitHub Actions の起動とトークン

- **Context**: 対象ごとの実行の起動と、PR の作成で CI が動くかを確かめる
- **Sources Consulted**: https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows 、https://docs.github.com/en/actions/concepts/security/github_token 、https://docs.github.com/en/actions/how-tos/write-workflows/choose-what-workflows-do/pass-job-outputs 、https://docs.github.com/en/rest/actions/workflow-jobs
- **Findings**:
  - GITHUB_TOKEN の操作で起きたイベントは、新しい実行を起こさない。ただし、`workflow_dispatch` と `repository_dispatch` は例外で、GITHUB_TOKEN でも実行が起きる
  - `workflow_run` は、名前を書いたワークフローの実行が終わると、既定のブランチのワークフローで動く
  - ジョブの出力は、同じ実行のあとのジョブに渡る。秘密の値を含む出力は渡らない
- **Implications**: 振り分けのワークフローは、GITHUB_TOKEN で対象ごとのワークフローを `workflow_dispatch` で起こす。PR の作成と push は bot の PAT で行い、PR の CI を動かす

## Architecture Pattern Evaluation

| Option | Description | Strengths | Risks / Limitations | Notes |
|--------|-------------|-----------|---------------------|-------|
| claude-code-action | 公式のアクションで Claude を動かす | 書く量が少ない | 浮動のタグ、起動者の制限、GitHub のトークンの用意 | 採らない |
| CLI を1つのジョブで動かす | 鍵と GitHub のトークンを同じジョブに置き、直して確かめて PR を作る | ジョブが少ない | Claude の変更したコード(テスト、ビルドスクリプト)が、鍵と書き込みのトークンのある所で動く | 採らない |
| CLI を直すジョブと確かめるジョブに分ける | 直すジョブは鍵だけを持ちコードを動かさない。確かめるジョブは秘密の値を持たない。PR は別のジョブが作る | 秘密の値と、Claude が変えたコードが同じ所に無い | ジョブの数と、ジョブの間の受け渡しが増える | 採る。dependency-review.yaml の分け方と同じ |
| 状態を Issue の台帳に持つ | 対象ごとの状態を1つの Issue に書き足す | 読むのが速い | 台帳と実際が食い違う。台帳の書き込みが失敗すると止まる | 採らない |
| 状態を実行の記録と目印から読み直す | 実行ごとの結果のファイル、bot の目印、コミットの末尾の行から毎回読む | 食い違いが起きない | 読む API の回数が増える | 採る |

## Design Decisions

### Decision: Claude の CLI を直接動かす

- **Context**: 要件1の6、要件3の3、要件3の5
- **Alternatives Considered**:
  1. claude-code-action — 公式のアクション
  2. CLI を直接動かす
- **Selected Approach**: verified-claude のアクションで CLI を確かめてから入れ、`claude -p` を、道具を Read・Edit・Write・Glob・Grep に絞って動かす
- **Rationale**: 使える道具と読む設定を、このリポジトリの側で決め切れる。GitHub のトークンを Claude のジョブに置かない
- **Trade-offs**: CLI の版の更新は自動でされない(ci-tool-version-update の4つの道具に入らない)
- **Follow-up**: 実装のときに、CLI の `--tools` と拒否の決まりで Bash が使えないことを、CLI の版 2.1.323 で確かめる

### Decision: 直すジョブと確かめるジョブを分け、Claude を1回の実行で1回だけ動かす

- **Context**: 要件2の2、要件3の1・2・3・5
- **Alternatives Considered**:
  1. 1つのジョブで直して確かめる
  2. 直すジョブと確かめるジョブを3組書き並べ、確認に通らなかった結果を材料にして直し直す
  3. 直すジョブと確かめるジョブを1組にし、PR を作ったあとの必須の検査の赤で直し直す
- **Selected Approach**: 3つ目。edit ジョブで Claude を1回動かし、verify ジョブで確かめる。通らなければ unfixed にする。PR を作ったあとは、sweep ジョブが必須の検査の赤を見つけて次の実行を起こす
- **Rationale**: 要件3の5は、Claude に渡す材料を、警告の説明、仕組みが書いた本文、赤になった必須の検査の名前と実行の記録に限る。verify ジョブの出力はこのどれでもないので、Claude に渡せない。必須の検査の赤なら要件2の4のとおりに渡せる
- **Trade-offs**: PR を作る前に直し直せないので、unfixed が増えうる
- **Follow-up**: 無し

### Decision: 1時間ごとの定期実行で、後始末と次の日の動かし直しを行う

- **Context**: 要件2の4から7、要件4の5、要件6の1と4
- **Selected Approach**: 振り分けのワークフローに1時間ごとの定期実行を1つ置き、sweep ジョブ(赤の検査、3回の赤、対象が消えた PR と Issue、マージのあとのコメント)と、dispatch ジョブの動かし直しを行う。定期実行の遅れ(codeql-recheck.yaml の #783)を前提にし、状態はすべて GitHub から読み直す
- **Rationale**: 必須の検査の結果と警告の状態の変化を知らせるイベントを、この仕組みは GITHUB_TOKEN では受け取れない。1つの定期実行で拾えば、きっかけの種類を増やさずに済む

### Decision: 自動のきっかけの実行は、同じ表示名について UTC の1日に1回までにする

- **Context**: 要件6の1、契約の使える量の「普通の使い方」
- **Selected Approach**: dispatch は、同じ表示名の実行が UTC のその日にあれば起動しない。所有者の手での起動はこの回数に数えない
- **Rationale**: 同じ対象を1日に何度も動かすと、使える量の上限に早く届く。必須の検査の赤は head のコミットを表示名に入れるので、新しいコミットごとに1回動く

### Decision: blocked も3日の Issue に数え、key は数えない

- **Context**: 要件2の9、要件6の1と3
- **Selected Approach**: dependency-cooldown が記録なしで赤にする見込みのとき(blocked)は、unavailable と同じく次の日に動かし直し、3つの違う日に続けば知らせの Issue を起票する。鍵の失敗(key)は鍵の Issue で知らせるので数えない
- **Rationale**: blocked は、版が72時間経つか警告が変わるまで続くことがあり、所有者が気づけないまま繰り返さないようにする

### Decision: Go の標準ライブラリの組は verify ジョブで go_bump を動かす

- **Context**: 要件2の2
- **Selected Approach**: Claude は Bash を持たず、イメージの digest を読めない。go-stdlib の組では、verify ジョブが backend-vuln-fix.sh の go_bump(この spec で引数で呼べるようにする)で、go.mod の toolchain と4つの Dockerfile の golang のイメージを上げる
- **Rationale**: 今の backend-vuln-fix と同じ上げ方になり、digest を Claude に書かせない

### Decision: 止まった Dependabot の PR から、Claude が直しても緑にならない5つの検査の赤を除く

- **Context**: 要件1の4(2026-11-14 に直した要件。design の審査の D1-1-12 を受けた)
- **Alternatives Considered**:
  1. 週次監査の今の出力の「止まった赤」だけを見る — 承認待ちに分けた赤(escape-hatch、dependency-gate、pre-merge-check、記録のコメントのある dependency-cooldown)が出力に無いので、赤が5つの検査のどれかだけかを決められない
  2. 週次監査の一覧の JSON に、承認待ちの赤も含めた PR の赤の検査の全部を書き、dispatch と prepare が5つの検査を除く
- **Selected Approach**: 2つ目。除く検査は、`dependency-review` と、期待一覧の `approval_gated` が true の検査にし、`lib-claude-auto-fix.sh` の `fixable_red_checks` が期待一覧から決める。prepare ジョブも実行の時点で読み直し、残った赤の検査の名前を材料に渡す
- **Rationale**: 週次監査の止まった PR の数え方を変えずに済む。`retry` は前の実行の入力で動かし直すので、prepare で読み直さないと、赤が5つの検査のどれかだけになった PR で Claude が動く。除く検査を期待一覧から読むと、Claude の変更の PR の赤から `approval_gated` の検査を除く sweep ジョブと同じ一覧を使える
- **Trade-offs**: prepare ジョブが週次監査のスクリプトを呼ぶので、開いている Dependabot の PR の数だけ API を読む

### Decision: 必須の検査の赤で動かした実行が直せなかったら、PR を閉じる

- **Context**: 要件4の3と要件2の5
- **Selected Approach**: red-check の実行が unfixed で終わったら、report ジョブが PR を閉じてブランチを消し、閉じた PR の URL を書いて直せなかったことを知らせる
- **Rationale**: PR を開いたまま知らせの Issue を起票すると、要件4の3(PR が開いている間は Issue を作らない)と食い違う。PR を開いたまま何もしないと、赤の PR が残り続ける

### Decision: 一般化(5種類の対象を1つの対象の形にまとめる)

- **Context**: 要件1の1から4の対象は、frontend の組、Java の組、Go の組、CodeQL の警告、コンテナの脆弱性、止まった Dependabot の PR の6種類である。どれも「対象を読み直す、材料を集める、直す、消えたかを確かめる、PR を作るか知らせる」の流れが同じである
- **Selected Approach**: 対象を `kind` と `key` の組で表し、1つの対象ごとのワークフローで扱う。種類ごとに違うのは、材料の集め方と、消えたかの確かめ方だけにする
- **Rationale**: 重複の防止(要件4の3)、直せなかったときの Issue(要件4)、動けなかったときの扱い(要件6)を、種類によらず1つの作りで満たせる

### Decision: 作るか使うか

- dependency-cooldown の判定は作り直さず、今のスクリプトに PR を作らない予測の形を足す。判定の結果が PR の検査と同じになるためである
- escape-hatch の判定は作り直さず、今のスクリプトを呼び、足りない形(CodeQL の注釈、Go のテストのアサーションの削除など)だけを足す
- Issue とコメントは、lib-ledger-issue.sh と lib-notice-comment.sh を使う
- コンテナの判定は、check-container-scan.sh と verified-trivy を使う

### Decision: 簡単にする

- 対象の状態を保存する場所を作らない。実行の結果のファイル(7日で消える)、bot の目印、コミットの末尾の行から毎回読み直す
- 振り分けのワークフローに同時実行の組を付けない。同じ対象の実行は対象ごとのワークフローの同時実行の組で1つずつにし、重複は、開いている PR と動いている実行を読んで防ぐ
- コンテナの脆弱性を自動で扱うのは、仕組みがまだ1度も扱っていない Issue だけにする。扱ったあとは所有者の手での起動で扱う

## Risks & Mitigations

- CodeQL の警告を直す実行の途中で、材料と変更が成果物として読める時間がある — 成果物の保存を1日にし、実行の最後のジョブで成果物を消す。標準出力に材料と変更と検査の出力を出さない
- 差分比較の API が一時のブランチのコミットで差を返さなくなる(2026-11-14 には返った) — 予測で判定できないときは赤とみなし、3日続けば Issue で知らせる
- 予測が判定できない状態が続く — 3日続いたら、動けなかったときと同じ Issue を起票する
- 契約の使える量を自動の処理で使うことが、利用の決まりの「普通の使い方」を超えるおそれ — 1回の実行の往復の数を60、同じ対象を自動のきっかけで動かすのを UTC の1日に1回、同じ必須の検査の赤での直し直しを3回に限る
- Claude が読み込みの道具で自分の環境(鍵)を読み、変更に書き込むおそれ — 作業のフォルダの外の読み書きを断る2つの設定と拒否の決まりで、/proc と /sys とランナーの一時フォルダを読ませず、変更に鍵の値か `sk-ant-` で始まる文字列があれば変更を捨てる

## References

- [Claude Code の導入](https://code.claude.com/docs/en/setup) — 実行ファイルと署名の置き場所
- [Claude Code の CLI](https://code.claude.com/docs/en/cli-reference) — `-p` と道具の絞り方
- [Claude Code の認証](https://code.claude.com/docs/en/authentication) — `claude setup-token` と OAuth のトークン
- [Claude Code の非対話の実行](https://code.claude.com/docs/en/headless) — JSON の出力
- [Claude Code の許可の設定](https://code.claude.com/docs/en/permissions) — 拒否の決まり
- [Claude Code の設定](https://code.claude.com/docs/en/settings) — `disableAllHooks` と設定の読み込み元
- [Claude Code のエラー](https://code.claude.com/docs/en/errors) — 失敗の種類
- [Claude Code の法務と規約](https://code.claude.com/docs/en/legal-and-compliance) — 契約の使い方
- [Claude Code の GitHub Actions](https://code.claude.com/docs/en/github-actions) — OAuth のトークンで動かす方法
- [claude-code-action v1.0.273](https://github.com/anthropics/claude-code-action/releases/tag/v1.0.273) — 浮動のタグの変更
- [ワークフローのジョブの API](https://docs.github.com/en/rest/actions/workflow-jobs)
- [ジョブの出力](https://docs.github.com/en/actions/how-tos/write-workflows/choose-what-workflows-do/pass-job-outputs)
- [ワークフローを起こすイベント](https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows)
- [GITHUB_TOKEN](https://docs.github.com/en/actions/concepts/security/github_token)
- [Gradle の依存グラフのプラグイン](https://github.com/gradle/github-dependency-graph-gradle-plugin)
- [gradle/actions の dependency-submission](https://github.com/gradle/actions/blob/main/docs/dependency-submission.md)
- [依存の差分比較の API](https://docs.github.com/en/rest/dependency-graph/dependency-review)

## pnpm が72時間の待ちで止まったときのエラーの文

- 確かめた日: 2026-11-21
- 使った部品と版: 開発環境の frontend のイメージ `keirekipro-frontend:latest`。pnpm 11.10.0(`frontend/package.json` の `packageManager` のとおりに corepack が入れた版)。Node.js v24.16.0
- 確かめ方: main のコミット `2edd4686` の `frontend/` を作業フォルダの外に写し、写しの `package.json` の `typescript` を、2026-11-20T08:08:34Z に公開された `7.1.0-dev.20261120.1` に固定した。写しの `pnpm-workspace.yaml` は変えず、`minimumReleaseAge: 4320` のままにした。写しで `pnpm install --lockfile-only --no-frozen-lockfile --ignore-scripts` を動かした
- 終わり方の番号: 1
- エラーの文: 1行目は `[ERR_PNPM_NO_MATURE_MATCHING_VERSION] 8 versions do not meet the minimumReleaseAge constraint:` だった。続く8行に、版ごとに `<名前>@<版> was published at <公開の日時>, within the minimumReleaseAge cutoff (<境の日時>)` の形で、固定した `typescript@7.1.0-dev.20261120.1` と、その版が持つ7つの部品の版が並んだ
- 結論: エラーの文は `ERR_PNPM_NO_MATURE_MATCHING_VERSION` を含む。design.md の claude-auto-fix-verify.sh の節の pnpm の項の見分け方と合う。設計を見直すきっかけには当たらない

## 一時のブランチの Gradle のスナップショットの確認

- 確かめた日: 2026-11-21
- 確認に使ったコミット: main のコミット `c2661468` から、2つのブランチを作った
  - 1つ目のブランチ `chore/tmp-gradle-snapshot-target` のコミット `03b6fb72` は、`backend/gradle/libs.versions.toml` の `commons-validator` を 1.11.0 から 1.10.0 に変えた
  - 2つ目のブランチ `chore/tmp-gradle-snapshot-check` のコミット `3414652e` は、確認のワークフロー `.github/workflows/tmp-gradle-snapshot-check.yaml` を足した
- 確認のワークフロー: 2つ目のブランチへの push で動いた(実行の番号 44861146192)。generate と submit の2つのジョブは、どちらも成功した。2つのジョブの組み立ては `dependency-review.yaml` の generate と submit と同じで、`gradle/actions/dependency-submission` の版も同じ v6.4.1 である。generate のジョブは1つ目のブランチのコミットを checkout した。2つのジョブには、環境変数 `GITHUB_DEPENDENCY_GRAPH_SHA` に `03b6fb72a6b34d9d03515a5073b8e5204644dc76` を、`GITHUB_DEPENDENCY_GRAPH_REF` に `refs/heads/chore/tmp-gradle-snapshot-target` を渡した
- スナップショットの中身: generate のジョブが作ったスナップショットの `sha` は `03b6fb72a6b34d9d03515a5073b8e5204644dc76`、`ref` は `refs/heads/chore/tmp-gradle-snapshot-target` だった
- 差分比較の API の結果:
  - main のコミット `c2661468` と1つ目のブランチのコミット `03b6fb72` の比較は、maven の差を2行返した。`backend/settings.gradle` の `commons-validator:commons-validator` について、1.10.0 の `added` と 1.11.0 の `removed` で、どちらも scope は `runtime` だった
  - main のコミット `c2661468` と2つ目のブランチのコミット `3414652e` の比較は、`actions` の差を3行だけ返し、maven の差を返さなかった
  - 1つ目のブランチのコミット `03b6fb72` と2つ目のブランチのコミット `3414652e` の比較も、maven の差を返さなかった。2つ目のブランチのコミットに Gradle のスナップショットが結び付いていれば、そのスナップショットの `commons-validator` は 1.10.0 になり、main のコミットとの比較で maven の差が出るはずである。main のコミットとの比較で maven の差が出なかったので、2つ目のブランチのコミットには Gradle のスナップショットが結び付いていない
- 結論: 2つの環境変数を渡すと、Gradle のスナップショットは、ワークフローを動かしたブランチのコミットではなく、渡したコミットとブランチに結び付く。差分比較の API は、main に無く一時のブランチにだけあるコミットでも、maven の差を返す。design.md の cooldown-generate と cooldown-submit の組み立てのとおりでよく、設計を見直すきっかけには当たらない
