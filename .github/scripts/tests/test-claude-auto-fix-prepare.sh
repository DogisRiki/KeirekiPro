#!/usr/bin/env bash
# =====================================================================
# claude-auto-fix-prepare.sh の自動テスト
#
# gh を PATH の先頭に置いた偽物に替え、PR と検査の結果と Issue とコメントと警告を返す。
# 種類が container の場合は、TRIVY_RESULTS_DIR のフォルダに偽の Trivy の結果を置く。
# 一時のフォルダに、origin にあたる bare のリポジトリと、その clone を作り、
# clone の中でスクリプトを動かして、起点のコード(base.patch)を確かめる。
# Dependabot の PR の head は、bare のリポジトリの refs/pull/<番号>/head に置く。
#
# 場合の名前を KP_TEST_CASE に入れると、その場合だけを流す(例: KP_TEST_CASE=dependabot)。
# 名前は args claude_pr red_check unfixed gone container dependabot main_base readonly。
# =====================================================================
set -uo pipefail

HERE="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$HERE/claude-auto-fix-prepare.sh"
WORK=$(mktemp -d) || exit 1
[ -n "$WORK" ] && [ -d "$WORK" ] || exit 1
trap 'rm -rf "$WORK"' EXIT
FAILED=0
CASE="${KP_TEST_CASE:-}"
RAN=0

ok() { echo "  ok: $1"; }
ng() { echo "  NG: $1" >&2; FAILED=1; }
expect_eq() { if [ "$2" = "$3" ]; then ok "$1"; else ng "$1(期待: [$3] 実際: [$2])"; fi; }
want() { if [ -z "$CASE" ] || [ "$CASE" = "$1" ]; then RAN=$((RAN + 1)); return 0; fi; return 1; }

FX="$WORK/fx"
BIN="$WORK/bin"
mkdir -p "$FX" "$BIN"
export FX FAKE_LOG="$WORK/gh.log"
export GITHUB_REPOSITORY="owner/repo" GH_TOKEN="fake-token"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.test GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.test

# --- 偽の gh: 呼ばれた引数を FAKE_LOG に残し、FX のファイルを返す。
# --slurp があれば、ファイルの配列を1ページの配列で包む。ファイルが無いか、
# 呼ばれた先が FAIL_EP の文字列を含めば失敗する
cat >"$BIN/gh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$FAKE_LOG"
slurp=0 ep=""
for a in "$@"; do
    case "$a" in
    --slurp) slurp=1 ;;
    repos/*) ep="$a" ;;
    esac
done
if [ -n "${FAIL_EP:-}" ] && [[ "$ep" == *"$FAIL_EP"* ]]; then exit 1; fi
case "$ep" in
*/dependabot/alerts*) f=alerts.json ;;
*/code-scanning/alerts/*) f="codeql-${ep##*/}.json" ;;
*/contents/backend/go.mod*) f=go.mod ;;
*/issues/*/comments*) n="${ep#*/issues/}"; f="comments-${n%%/*}.json" ;;
*/issues\?labels=claude-auto-fix\&*) f=issues-caf.json ;;
*/issues\?labels=container-vuln\&*) f=issues-cv.json ;;
*/pulls\?*) f=pulls.json ;;
*/pulls/*) f="pull-${ep##*/}.json" ;;
*/commits/*/check-runs*) s="${ep#*/commits/}"; f="checkruns-${s%%/*}.json" ;;
*) exit 1 ;;
esac
[ -f "$FX/$f" ] || exit 1
if [ "$slurp" = 1 ]; then
    printf '['
    cat "$FX/$f"
    printf ']'
else
    cat "$FX/$f"
fi
EOF
chmod +x "$BIN/gh"
export PATH="$BIN:$PATH"

# --- 偽の期待一覧: approval_gated が true の4つの検査と dependency-review が、直しても緑にならない5つの検査
cat >"$FX/required.json" <<'EOF'
{"checks": [
  {"context": "frontend-test", "mode": "always", "state": "active", "approval_gated": false},
  {"context": "backend-test", "mode": "always", "state": "active", "approval_gated": false},
  {"context": "dependency-review", "mode": "always", "state": "active", "approval_gated": false},
  {"context": "escape-hatch", "mode": "always", "state": "active", "approval_gated": true},
  {"context": "dependency-gate", "mode": "always", "state": "active", "approval_gated": true},
  {"context": "pre-merge-check", "mode": "always", "state": "active", "approval_gated": true},
  {"context": "dependency-cooldown", "mode": "always", "state": "active", "approval_gated": true}
]}
EOF
export CAF_REQUIRED_CHECKS="$FX/required.json"

# --- Git のリポジトリ: origin(bare)と、スクリプトを動かす clone
ORIGIN="$WORK/origin.git"
SEED="$WORK/seed"
REPO="$WORK/repo"
git init -q --bare "$ORIGIN"
git -C "$ORIGIN" symbolic-ref HEAD refs/heads/main
git init -q -b main "$SEED"
(
    cd "$SEED" || exit 1
    printf 'version = 1.0.0\n' >deps.txt
    printf 'line\n' >shared.txt
    git add deps.txt shared.txt && git commit -q -m base
    git remote add origin "$ORIGIN" && git push -q origin main
) || exit 1
BASE_SHA=$(git -C "$SEED" rev-parse HEAD)
git clone -q "$ORIGIN" "$REPO" || exit 1

# Dependabot の PR の head を作る: pr_head <番号> <ファイル> <中身>。head の SHA を出す
pr_head() {
    (
        cd "$SEED" || exit 1
        git checkout -q -b "pr-$1" "$BASE_SHA"
        printf '%s\n' "$3" >"$2"
        git add "$2" && git commit -q -m "bump $1"
        git push -q origin "HEAD:refs/pull/$1/head"
        git rev-parse HEAD
        git checkout -q main
    )
}
H42=$(pr_head 42 deps.txt 'version = 2.0.0')
H43=$(pr_head 43 deps.txt 'version = 2.1.0')
H44=$(pr_head 44 deps.txt 'version = 2.2.0')
H46=$(pr_head 46 shared.txt 'pr-change')
# PR 47 の refs/pull/47/head は、API が返す head(H47_API)と違うコミットにする
pr_head 47 deps.txt 'version = 2.7.0' >/dev/null
# PR 48 は、red-check で確かめる。refs/pull/48/head は main とぶつかり、API が返す head とも違う
pr_head 48 shared.txt 'pr-change-48' >/dev/null

# clone を作ったあとに main を進める。スクリプトが実行の時点の main を読むことを確かめるため
(
    cd "$SEED" || exit 1
    printf 'main-change\n' >shared.txt
    printf 'new\n' >main-only.txt
    git add shared.txt main-only.txt && git commit -q -m main2 && git push -q origin main
) || exit 1
MAIN_SHA=$(git -C "$SEED" rev-parse main)

# --- PR の一覧と、PR ごとの中身と検査の結果
CLAUDE_HEAD=1111111111111111111111111111111111111111
CLAUDE_HEAD_48=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
pull() { # number user head_sha state merged ref repo labels
    printf '{"number":%s,"state":"%s","merged":%s,"user":{"login":"%s"},"html_url":"https://example.test/pull/%s",
      "head":{"sha":"%s","ref":"%s","repo":{"full_name":"%s"}},"labels":%s,"body":""}' \
        "$1" "$4" "$5" "$2" "$1" "$3" "$6" "$7" "$8"
}
CAF_LABELS='[{"name":"claude-auto-fix"}]'
for n in 42 43 44 46; do
    h="H$n"
    pull "$n" 'dependabot[bot]' "${!h}" open false "dependabot/x-$n" owner/repo '[]' >"$FX/pull-$n.json"
done
# PR 47 は、API の head の SHA が refs/pull/47/head と違う(読んだあとに head が進んだ)
H47_API=4444444444444444444444444444444444444444
pull 47 'dependabot[bot]' "$H47_API" open false dependabot/x-47 owner/repo '[]' >"$FX/pull-47.json"
# PR 48 と PR 49 は、Claude の変更の PR(504 と 505)が開いている Dependabot の PR
H48_API=8888888888888888888888888888888888888888
H49=9999999999999999999999999999999999999999
pull 48 'dependabot[bot]' "$H48_API" open false dependabot/x-48 owner/repo '[]' >"$FX/pull-48.json"
pull 49 'dependabot[bot]' "$H49" open false dependabot/x-49 owner/repo '[]' >"$FX/pull-49.json"
pull 45 'dependabot[bot]' 5555555555555555555555555555555555555555 closed false dependabot/x-45 owner/repo '[]' >"$FX/pull-45.json"
# PR の一覧。PR 47 の head は API の値にする
{
    printf '['
    pull 501 DogisRiki-bot "$CLAUDE_HEAD" open false fix/claude-auto-fix-codeql-17 owner/repo "$CAF_LABELS"
    printf ','
    # fork の PR は、同じブランチ名とラベルでも Claude の変更の PR に数えない
    pull 502 someone 2222222222222222222222222222222222222222 open false fix/claude-auto-fix-codeql-20 someone/repo "$CAF_LABELS"
    printf ","
    pull 503 DogisRiki-bot 6666666666666666666666666666666666666666 open false fix/claude-auto-fix-codeql-25 owner/repo "$CAF_LABELS"
    for n in 42 43 44 46; do
        h="H$n"
        printf ','
        pull "$n" 'dependabot[bot]' "${!h}" open false "dependabot/x-$n" owner/repo '[]'
    done
    printf ','
    pull 47 'dependabot[bot]' "$H47_API" open false dependabot/x-47 owner/repo '[]'
    printf ','
    pull 48 'dependabot[bot]' "$H48_API" open false dependabot/x-48 owner/repo '[]'
    printf ','
    pull 49 'dependabot[bot]' "$H49" open false dependabot/x-49 owner/repo '[]'
    printf ','
    pull 504 DogisRiki-bot "$CLAUDE_HEAD_48" open false fix/claude-auto-fix-dependabot-pr-48 owner/repo "$CAF_LABELS"
    printf ','
    pull 505 DogisRiki-bot 7777777777777777777777777777777777777777 open false fix/claude-auto-fix-dependabot-pr-49 owner/repo "$CAF_LABELS"
    printf ']'
} >"$FX/pulls.json"

run() { # name conclusion
    printf '{"id":%s,"name":"%s","status":"completed","conclusion":"%s","started_at":"2026-11-20T00:00:00Z"}' \
        "$RANDOM" "$1" "$2"
}
# checkruns <SHA> <赤の検査の名前…>: 期待一覧の検査のうち、名前を渡した検査を failure、ほかを success にする
checkruns() {
    local sha="$1" first=1 c concl
    shift
    {
        printf '{"total_count":7,"check_runs":['
        for c in frontend-test backend-test dependency-review escape-hatch dependency-gate pre-merge-check dependency-cooldown; do
            concl=success
            for r in "$@"; do [ "$r" = "$c" ] && concl=failure; done
            [ "$first" = 1 ] || printf ','
            first=0
            run "$c" "$concl"
        done
        printf ']}'
    } >"$FX/checkruns-$sha.json"
}
checkruns "$H42" frontend-test escape-hatch
checkruns "$H43" dependency-review escape-hatch
checkruns "$H44" escape-hatch
checkruns "$H46" backend-test
checkruns "$H47_API" frontend-test
checkruns "$H48_API" frontend-test escape-hatch
checkruns "$H49" dependency-review

# --- Issue とコメント
issue() { # number user title body
    printf '{"number":%s,"user":{"login":"%s"},"title":"%s","body":"%s","created_at":"2026-11-1%sT00:00:00Z"}' \
        "$1" "$2" "$3" "$4" "${5:-0}"
}
comment() { # user body day
    printf '{"user":{"login":"%s"},"body":"%s","created_at":"2026-11-%sT00:00:00Z"}' "$1" "$2" "$3"
}
BOT='github-actions[bot]'
{
    printf '['
    # 18: 本文は unavailable、あとの bot のコメントで unfixed になった
    issue 18 "$BOT" t18 '<!-- claude-auto-fix-issue key=codeql:18 kind=unavailable -->'
    printf ','
    # 21: bot の目印は unavailable のままで、ほかの利用者が unfixed の目印をコメントに書いた
    issue 21 "$BOT" t21 '<!-- claude-auto-fix-issue key=codeql:21 kind=unavailable -->'
    printf ','
    # 22: ほかの利用者が起票した Issue の本文の unfixed は読まない
    issue 22 someone t22 '<!-- claude-auto-fix-issue key=codeql:22 kind=unfixed -->'
    printf ','
    # 23: PR は Issue に数えない
    printf '{"number":23,"user":{"login":"%s"},"title":"t23","body":"<!-- claude-auto-fix-issue key=codeql:23 kind=unfixed -->","created_at":"2026-11-10T00:00:00Z","pull_request":{}}' "$BOT"
    printf ','
    # 24: 本文が unfixed。key が codeql:2 の対象に当たらないことを確かめるため、key の前の部分が同じにする
    issue 24 "$BOT" t24 '<!-- claude-auto-fix-issue key=codeql:24 kind=unfixed -->'
    printf ','
    # 25: Claude の変更の PR 503 が開いている対象の unfixed の Issue(red-check で確かめる)
    issue 25 "$BOT" t25 '<!-- claude-auto-fix-issue key=codeql:25 kind=unfixed -->'
    printf ']'
} >"$FX/issues-caf.json"
printf '[%s]' "$(comment "$BOT" '<!-- claude-auto-fix-issue key=codeql:18 kind=unfixed -->' 15)" >"$FX/comments-18.json"
printf '[%s]' "$(comment someone '<!-- claude-auto-fix-issue key=codeql:21 kind=unfixed -->' 15)" >"$FX/comments-21.json"
printf '[]' >"$FX/comments-22.json"
printf '[]' >"$FX/comments-23.json"
printf '[]' >"$FX/comments-24.json"
printf '[]' >"$FX/comments-25.json"

{
    printf '['
    issue 31 "$BOT" 'コンテナ脆弱性: CVE-2025-0001' 'b'
    printf ','
    issue 32 "$BOT" 'コンテナ脆弱性: CVE-2025-0002' 'b'
    printf ']'
} >"$FX/issues-cv.json"

# --- CodeQL の警告と Dependabot の警告と go.mod
for n in 2 17 18 20 21 22 23 24 25; do
    printf '{"number":%s,"state":"open"}' "$n" >"$FX/codeql-$n.json"
done
printf '{"number":19,"state":"fixed"}' >"$FX/codeql-19.json"
printf '[{"number":1,"state":"open","dependency":{"package":{"ecosystem":"npm","name":"lodash"}},"security_vulnerability":{"first_patched_version":{"identifier":"4.17.21"}}}]' >"$FX/alerts.json"
printf 'module example.test/x\n\ngo 1.25.0\n\ntoolchain go1.25.3\n' >"$FX/go.mod"

# --- Trivy の結果: java には CVE-2025-0001、go には CVE-2025-0003 がある
TRIVY="$WORK/trivy"
mkdir -p "$TRIVY"
trivy() { # file id
    printf '{"SchemaVersion":2,"ArtifactName":"image.tar","Metadata":{"ImageConfig":{"architecture":"arm64","os":"linux"}},
      "Results":[{"Target":"t","Vulnerabilities":[{"VulnerabilityID":"%s","Severity":"HIGH","PkgName":"p","InstalledVersion":"1.0","FixedVersion":"1.1"}]}]}' \
        "$2" >"$TRIVY/$1"
}
trivy trivy-java.json CVE-2025-0001
trivy trivy-go.json CVE-2025-0003

# --- スクリプトを動かす: prepare <名前> <引数…>。
# 出力を $WORK/<名前>.out に、標準エラーを $WORK/<名前>.err に、終わり方を $WORK/<名前>.rc に、
# RUNNER_TEMP を $WORK/<名前>.rt に置く
prepare() {
    local name="$1" rc=0
    shift
    mkdir -p "$WORK/$name.rt"
    (cd "$REPO" && RUNNER_TEMP="$WORK/$name.rt" TRIVY_RESULTS_DIR="${TRIVY_DIR-$TRIVY}" bash "$SCRIPT" "$@") \
        >"$WORK/$name.out" 2>"$WORK/$name.err" || rc=$?
    echo "$rc" >"$WORK/$name.rc"
}
out() { # name key: 出力の key= の値
    sed -n "s/^$2=//p" "$WORK/$1.out" | head -n 1
}
rc() { cat "$WORK/$1.rc"; }
expect_stop() { # 説明 name outcome cause
    expect_eq "$1: 終わり方" "$(rc "$2")" 0
    expect_eq "$1: outcome" "$(out "$2" outcome)" "$3"
    expect_eq "$1: cause" "$(out "$2" cause)" "$4"
    expect_eq "$1: 起点の SHA を出さない" "$(out "$2" main_sha)" ""
}
expect_go() { # 説明 name: 止めずに起点を出す
    expect_eq "$1: 終わり方" "$(rc "$2")" 0
    expect_eq "$1: outcome を出さない" "$(out "$2" outcome)" ""
    expect_eq "$1: main_sha は実行の時点の main" "$(out "$2" main_sha)" "$MAIN_SHA"
    local patch
    patch=$(out "$2" base_patch)
    if [ -n "$patch" ] && [ -f "$patch" ]; then
        ok "$1: base.patch がある"
        expect_eq "$1: base_sha256 は base.patch の SHA-256" "$(out "$2" base_sha256)" "$(sha256sum "$patch" | cut -d' ' -f1)"
    else
        ng "$1: base.patch がありません([${patch}])"
    fi
}
EMPTY_SHA256=$(printf '' | sha256sum | cut -d' ' -f1)

# =====================================================================
if want args; then
    echo "[args] 引数と環境の誤り"
    prepare a1 unknown 17 trigger ""
    expect_eq "知らない種類は 2" "$(rc a1)" 2
    prepare a2 codeql 17 later ""
    expect_eq "知らない reason は 2" "$(rc a2)" 2
    prepare a3 codeql 17 red-check abc
    expect_eq "red-check で PR の番号が数でなければ 2" "$(rc a3)" 2
    prepare a4 codeql 17 trigger
    expect_eq "引数が3つなら 2" "$(rc a4)" 2
    prepare a5 codeql 'bad key' trigger ""
    expect_eq "key の形が違えば 2" "$(rc a5)" 2
    rc=0
    (cd "$REPO" && env -u RUNNER_TEMP bash "$SCRIPT" codeql 2 trigger "") >/dev/null 2>&1 || rc=$?
    expect_eq "RUNNER_TEMP が無ければ 2" "$rc" 2
    rc=0
    git clone -q --depth 1 --branch main "file://$ORIGIN" "$WORK/shallow" 2>/dev/null
    mkdir -p "$WORK/sh.rt"
    (cd "$WORK/shallow" && RUNNER_TEMP="$WORK/sh.rt" bash "$SCRIPT" codeql 2 trigger "") >/dev/null 2>&1 || rc=$?
    expect_eq "履歴の浅い clone なら 2" "$rc" 2
    TRIVY_DIR="$WORK/none" prepare a7 container CVE-2025-0001 trigger ""
    expect_eq "container で TRIVY_RESULTS_DIR のファイルが無ければ 0 以外" "$([ "$(rc a7)" != 0 ] && echo yes)" yes
    expect_eq "container で Trivy の結果を読めないときは outcome を出さない" "$(out a7 outcome)" ""
fi

if want claude_pr; then
    echo "[claude_pr] 同じ key の Claude の変更の PR"
    prepare c1 codeql 17 trigger ""
    expect_stop "同じ key の Claude の変更の PR が開いていれば skipped" c1 skipped claude-pr-open
    for r in manual retry; do
        prepare "c-$r" codeql 17 "$r" ""
        expect_stop "reason が ${r} でも、同じ key の Claude の変更の PR が開いていれば skipped" "c-$r" skipped claude-pr-open
    done
    prepare c2 codeql 20 trigger ""
    expect_go "fork の PR は Claude の変更の PR に数えない" c2
    FAIL_EP='pulls?' prepare c3 codeql 2 trigger ""
    expect_eq "PR の一覧を読めなければ 0 以外" "$([ "$(rc c3)" != 0 ] && echo yes)" yes
    expect_eq "PR の一覧を読めなければ outcome を出さない" "$(out c3 outcome)" ""
fi

if want red_check; then
    echo "[red_check] red-check の起点"
    prepare r1 codeql 17 red-check 501
    expect_go "red-check で、その PR が開いていれば止めない" r1
    expect_eq "red-check では PR の head が起点になる" "$(out r1 base_sha)" "$CLAUDE_HEAD"
    expect_eq "red-check の base.patch は空" "$(out r1 base_sha256)" "$EMPTY_SHA256"
    prepare r2 codeql 17 red-check 999
    expect_stop "red-check で、開いている Claude の変更の PR が別の番号なら skipped" r2 skipped pr-not-open
    prepare r3 codeql 2 red-check 501
    expect_stop "red-check で、同じ key の Claude の変更の PR が無ければ skipped" r3 skipped pr-not-open
    # Dependabot の PR 48 は、refs/pull/48/head が API の head と違い、main ともぶつかる。
    # red-check の起点は Claude の変更の PR の head なので、どちらでも止めない
    prepare r4 dependabot 48 red-check 504
    expect_go "種類が dependabot の red-check で、その PR が開いていれば止めない" r4
    expect_eq "種類が dependabot の red-check でも Claude の変更の PR の head が起点になる" "$(out r4 base_sha)" "$CLAUDE_HEAD_48"
    expect_eq "種類が dependabot の red-check の base.patch は空" "$(out r4 base_sha256)" "$EMPTY_SHA256"
    expect_eq "種類が dependabot の red-check では checks を出さない" "$(grep -c '^checks=' "$WORK/r4.out")" 0
    prepare r5 dependabot 49 red-check 505
    expect_stop "種類が dependabot の red-check でも、Dependabot の PR の赤が5つの検査のどれかだけなら skipped" r5 skipped no-fixable-check
fi

if want unfixed; then
    echo "[unfixed] 直せなかったことの知らせ"
    for r in trigger retry; do
        prepare "u-$r" codeql 18 "$r" ""
        expect_stop "reason が ${r} で状態が unfixed の知らせの Issue があれば skipped" "u-$r" skipped unfixed-issue
    done
    # 要件4の4が知らせの Issue で止めるのは要件1の1から4のきっかけだけで、red-check は止めない
    prepare u-red codeql 25 red-check 503
    expect_go "reason が red-check なら unfixed の Issue があっても止まらない" u-red
    prepare u-red2 codeql 25 trigger ""
    expect_stop "Claude の変更の PR が開いていれば、unfixed の Issue より先に claude-pr-open で止める" u-red2 skipped claude-pr-open
    prepare u-manual codeql 18 manual ""
    expect_go "reason が manual なら unfixed の Issue があっても止まらない" u-manual
    prepare u2 codeql 21 trigger ""
    expect_go "ほかの利用者が書いた unfixed の目印は読まない" u2
    : >"$FAKE_LOG"
    prepare u3 codeql 22 trigger ""
    expect_go "ほかの利用者が起票した Issue は読まない" u3
    if grep -qF "issues/22/comments" "$FAKE_LOG"; then ng "ほかの利用者が起票した Issue のコメントを読んでいる"; else ok "ほかの利用者が起票した Issue のコメントを読まない"; fi
    prepare u4 codeql 23 trigger ""
    expect_go "PR は知らせの Issue に数えない" u4
    prepare u5 codeql 2 trigger ""
    expect_go "key の前の部分が同じほかの対象の Issue を読まない" u5
    FAIL_EP='/comments' prepare u6 codeql 18 trigger ""
    expect_eq "コメントを読めなければ 0 以外" "$([ "$(rc u6)" != 0 ] && echo yes)" yes
fi

if want gone; then
    echo "[gone] 対象が消えたとき"
    prepare g1 codeql 19 trigger ""
    expect_stop "CodeQL の警告が open でなければ gone" g1 gone target-gone
    prepare g2 npm lodash@9.9.9 trigger ""
    expect_stop "組の Dependabot の警告が開いていなければ gone" g2 gone target-gone
    prepare g3 go-stdlib 1.25.3 trigger ""
    expect_stop "main の toolchain が修正版以上なら gone" g3 gone target-gone
    prepare g4 container CVE-2025-0009 trigger ""
    expect_stop "ラベル container-vuln の Issue が閉じていれば gone" g4 gone target-gone
    FAIL_EP='code-scanning' prepare g5 codeql 19 trigger ""
    expect_eq "警告を読めなければ 0 以外" "$([ "$(rc g5)" != 0 ] && echo yes)" yes
fi

if want container; then
    echo "[container] main から作ったイメージの Trivy の結果"
    prepare k1 container CVE-2025-0001 trigger ""
    expect_go "main のイメージに脆弱性の ID があれば止めない" k1
    expect_eq "container の起点は main" "$(out k1 base_sha)" "$MAIN_SHA"
    expect_eq "container の base.patch は空" "$(out k1 base_sha256)" "$EMPTY_SHA256"
    prepare k2 container CVE-2025-0002 trigger ""
    expect_stop "main のイメージに脆弱性の ID が無ければ gone になり、コメントを書くことを結果に残す" k2 gone gone-on-main
    printf '{"SchemaVersion":2,"Metadata":{"ImageConfig":{"architecture":"amd64"}},"Results":[]}' >"$WORK/bad-go.json"
    mkdir -p "$WORK/trivy-bad"
    cp "$TRIVY/trivy-java.json" "$WORK/trivy-bad/"
    cp "$WORK/bad-go.json" "$WORK/trivy-bad/trivy-go.json"
    TRIVY_DIR="$WORK/trivy-bad" prepare k3 container CVE-2025-0002 trigger ""
    expect_eq "Trivy の結果を判定できなければ 0 以外" "$([ "$(rc k3)" != 0 ] && echo yes)" yes
    expect_eq "Trivy の結果を判定できなければ outcome を出さない" "$(out k3 outcome)" ""
fi

if want dependabot; then
    echo "[dependabot] 止まった Dependabot の PR"
    prepare d1 dependabot 42 trigger ""
    expect_go "5つのほかの赤が残る PR では止めない" d1
    expect_eq "残った赤の検査の名前が checks に出る" "$(out d1 checks)" '["frontend-test"]'
    expect_eq "dependabot の base_sha は main" "$(out d1 base_sha)" "$MAIN_SHA"
    patch=$(out d1 base_patch)
    if [ -s "$patch" ]; then ok "dependabot の base.patch は空でない"; else ng "dependabot の base.patch が空です"; fi
    rm -rf "$WORK/apply"
    git clone -q "$ORIGIN" "$WORK/apply"
    if git -C "$WORK/apply" apply --index "$patch" 2>/dev/null; then
        expect_eq "base.patch を main に当てると Dependabot の版上げが入る" "$(cat "$WORK/apply/deps.txt")" 'version = 2.0.0'
        expect_eq "base.patch を main に当てても main の変更が残る" "$(cat "$WORK/apply/shared.txt")" 'main-change'
        expect_eq "base.patch を main に当てても main だけのファイルが残る" "$(cat "$WORK/apply/main-only.txt")" 'new'
    else
        ng "base.patch を main に当てられません"
    fi
    prepare d2 dependabot 43 trigger ""
    expect_stop "赤の検査が5つの検査のどれかだけになった PR で skipped" d2 skipped no-fixable-check
    prepare d3 dependabot 44 trigger ""
    expect_stop "止まった PR の一覧に無い PR で skipped" d3 skipped not-stuck
    prepare d4 dependabot 45 trigger ""
    expect_stop "閉じた Dependabot の PR は gone" d4 gone target-gone
    prepare d5 dependabot 46 trigger ""
    expect_stop "main とぶつかる Dependabot の PR は skipped" d5 skipped merge-conflict
    prepare d6 dependabot 47 trigger ""
    expect_stop "API の head と取り込んだ head が違えば skipped" d6 skipped head-moved
    FAIL_EP="commits/$H42" prepare d7 dependabot 42 trigger ""
    expect_eq "検査の結果を読めなければ 0 以外" "$([ "$(rc d7)" != 0 ] && echo yes)" yes
    expect_eq "検査の結果を読めなければ outcome を出さない" "$(out d7 outcome)" ""
fi

if want main_base; then
    echo "[main_base] そのほかの種類の起点"
    prepare m1 npm lodash@4.17.21 trigger ""
    expect_go "npm は止めない" m1
    expect_eq "npm の起点は main" "$(out m1 base_sha)" "$MAIN_SHA"
    expect_eq "npm の base.patch は空" "$(out m1 base_sha256)" "$EMPTY_SHA256"
    expect_eq "npm では checks を出さない" "$(out m1 checks)" ""
    prepare m2 go-stdlib 1.25.4 trigger ""
    expect_go "go-stdlib は止めない" m2
    expect_eq "go-stdlib の base.patch は空" "$(out m2 base_sha256)" "$EMPTY_SHA256"
    prepare m3 codeql 2 manual ""
    expect_go "codeql は止めない" m3
    expect_eq "codeql の起点は main" "$(out m3 base_sha)" "$MAIN_SHA"
    expect_eq "codeql の base.patch は空" "$(out m3 base_sha256)" "$EMPTY_SHA256"
    bad=$(grep -cvE '^(main_sha|base_sha|base_sha256|base_patch|checks)=' "$WORK/m3.out")
    expect_eq "続けるときの標準出力には決まった欄の行だけを書く" "$bad" 0
    prepare m4 codeql 19 trigger ""
    expect_eq "止める場合の outcome" "$(out m4 outcome)" gone
    bad=$(grep -cvE '^(outcome|cause)=' "$WORK/m4.out")
    expect_eq "止めるときの標準出力には outcome と cause の行だけを書く" "$bad" 0
fi

if want readonly; then
    echo "[readonly] GitHub の中身を変えない"
    : >"$FAKE_LOG"
    prepare w1 dependabot 42 trigger ""
    prepare w2 codeql 18 trigger ""
    prepare w3 container CVE-2025-0001 trigger ""
    for w in w1 w2 w3; do
        expect_eq "読む形の確かめの場合 ${w} が最後まで動く" "$(rc "$w")" 0
    done
    if grep -qE '(^| )(-X|--method|-f|-F|--field|--raw-field|--input)( |$)' "$FAKE_LOG"; then
        ng "gh で GitHub の中身を変える形の呼び出しがある"
    else
        ok "gh は読む形でしか呼ばない"
    fi
    if grep -qvE '^api ' "$FAKE_LOG"; then
        ng "gh を api のほかの形で呼んでいる"
    else
        ok "gh は api の形でしか呼ばない"
    fi
fi

if [ "$RAN" -eq 0 ]; then
    echo "知らない場合の名前です: ${CASE}" >&2
    exit 1
fi
if [ "$FAILED" -ne 0 ]; then
    echo "失敗した確かめがあります" >&2
    exit 1
fi
echo "すべての確かめが通りました"
