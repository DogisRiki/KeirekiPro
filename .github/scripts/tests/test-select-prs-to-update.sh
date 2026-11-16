#!/usr/bin/env bash
# =====================================================================
# select-prs-to-update.sh の自動テスト
#
# gh を PATH の先頭の偽物で置き換え、標準出力(main の最新に合わせる PR の番号)・
# 終了コード・gh の呼び出しを確かめる。
#   検査が通っていない PR は選ばれない(main を取り込まれない)
#   検査が通っていて main より古い PR は選ばれる(main を取り込まれる)
#
# 対象の PR を決める式(TARGET_FILTER)は、update-pr-branches.yaml から読み取って使う。
# ワークフローが渡す式そのものを確かめるためである。
#
# gh の偽物は $STUB_DIR のファイルを返す。ファイルが無い問い合わせは失敗させる。
#   開いている PR の一覧: pulls.json    検査の結果: runs-<コミット>.json
#   main との比較: compare-<コミット>.json
# 想定していない呼び出し(書き込みを含む)は失敗させ、別の記録に残す。
# 外部への問い合わせを行わないため、実行にネットワークを必要としない。
# =====================================================================
set -uo pipefail

# CI のジョブに入っている環境変数のうち、このテストが確かめないものを消す
unset GITHUB_REPOSITORY GITHUB_STEP_SUMMARY GITHUB_OUTPUT HEAD_SHA REQUIRED_CHECKS_FILE

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SCRIPT="$ROOT/scripts/select-prs-to-update.sh"
WORKFLOW="$ROOT/workflows/update-pr-branches.yaml"
REAL_CHECKS="$ROOT/audit/required-checks.json"
WORK=$(mktemp -d) || exit 1
[ -n "$WORK" ] && [ -d "$WORK" ] || exit 1
trap 'rm -rf "$WORK"' EXIT
FAILED=0

FILTER=$(sed -n "s/^ *TARGET_FILTER='\(.*\)'\$/\1/p" "$WORKFLOW")
if [ -z "$FILTER" ]; then
    echo "FAIL: update-pr-branches.yaml から TARGET_FILTER の式を読み取れない"
    exit 1
fi

SHA_A="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
SHA_B="bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
SHA_C="cccccccccccccccccccccccccccccccccccccccc"

mkdir -p "$WORK/bin" "$WORK/stub"
cat >"$WORK/bin/gh" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"${STUB_CALLS:?}"
serve() {
    if [ ! -f "$1" ]; then
        echo "gh: Server Error (HTTP 502)" >&2
        exit 1
    fi
    cat "$1"
}
case "$*" in
"api repos/owner/repo/pulls?state=open&base=main&per_page=100 --paginate --slurp")
    serve "${STUB_DIR:?}/pulls.json"
    ;;
"api repos/owner/repo/commits/"*"/check-runs?per_page=100 --paginate --slurp")
    sha="${2#repos/owner/repo/commits/}"
    serve "${STUB_DIR:?}/runs-${sha%%/*}.json"
    ;;
"api repos/owner/repo/compare/main..."*)
    serve "${STUB_DIR:?}/compare-${2#repos/owner/repo/compare/main...}.json"
    ;;
*)
    printf '%s\n' "$*" >>"${STUB_UNEXPECTED:?}"
    echo "stub: unexpected call: $*" >&2
    exit 1
    ;;
esac
STUB
chmod +x "$WORK/bin/gh"
: >"$WORK/unexpected.log"

# 期待一覧の見本。数える検査は build と lint。gate は承認で結果が変わる検査、
# paused は止めてある検査で、どちらも数えない。
cat >"$WORK/checks.json" <<'JSON'
{"checks": [
  {"context": "build", "mode": "always", "state": "active", "approval_gated": false},
  {"context": "lint", "mode": "conditional", "state": "active", "approval_gated": false},
  {"context": "gate", "mode": "always", "state": "active", "approval_gated": true},
  {"context": "paused", "mode": "always", "state": "paused", "approval_gated": false}
]}
JSON

# --- 場面の材料 -------------------------------------------------------------------
reset_scenario() {
    rm -f "$WORK"/stub/*
    echo '[]' >"$WORK/prs.json"
    HEAD_FILTER=""
    CHECKS_FILE="$WORK/checks.json"
    USE_FILTER="$FILTER"
}

# 開いている PR を1件足す。使い方: add_pr <番号> <コミット> [<jq で上書きする欄>]
add_pr() {
    jq --argjson n "$1" --arg sha "$2" \
        ". + [({number: \$n, draft: false, labels: [], head: {sha: \$sha, ref: \"feat/x\", repo: {full_name: \"owner/repo\"}}} | ${3:-.})]" \
        "$WORK/prs.json" >"$WORK/prs.tmp" || exit 1
    mv "$WORK/prs.tmp" "$WORK/prs.json" || exit 1
}

# コミットの検査の結果を書く。使い方: set_runs <コミット> <名前:状態:結果:id>...
# 結果が - のときは null にする(実行中の検査)。
set_runs() {
    local sha="$1" spec name status conclusion id runs='[]'
    shift
    for spec in "$@"; do
        IFS=: read -r name status conclusion id <<<"$spec"
        runs=$(jq -c --arg n "$name" --arg s "$status" --arg c "$conclusion" --argjson id "$id" \
            '. + [{id: $id, name: $n, status: $s, conclusion: (if $c == "-" then null else $c end)}]' <<<"$runs") || exit 1
    done
    jq -n --argjson runs "$runs" '[{total_count: ($runs | length), check_runs: $runs}]' >"$WORK/stub/runs-$sha.json" || exit 1
}

# main より何コミット古いかを書く。使い方: set_behind <コミット> <数>
set_behind() {
    printf '{"behind_by": %s, "ahead_by": 1}\n' "$2" >"$WORK/stub/compare-$1.json"
}

run() {
    : >"$WORK/calls.log"
    jq -c '[.]' "$WORK/prs.json" >"$WORK/stub/pulls.json" || exit 1
    [ -z "${NO_PULLS:-}" ] || rm -f "$WORK/stub/pulls.json"
    [ -z "${PULLS_FILE:-}" ] || cp "$PULLS_FILE" "$WORK/stub/pulls.json"
    PATH="$WORK/bin:$PATH" STUB_DIR="$WORK/stub" STUB_CALLS="$WORK/calls.log" \
        STUB_UNEXPECTED="$WORK/unexpected.log" GH_TOKEN="${TOKEN-read-token}" REPO="owner/repo" \
        TARGET_FILTER="$USE_FILTER" HEAD_SHA="$HEAD_FILTER" REQUIRED_CHECKS_FILE="$CHECKS_FILE" \
        bash "$SCRIPT" >"$WORK/out.txt" 2>"$WORK/err.txt"
    RC=$?
    OUT=$(tr '\n' ' ' <"$WORK/out.txt" | sed 's/ $//')
}

# --- 確かめ方 ---------------------------------------------------------------------
ok() { echo "PASS: $1"; }
ng() {
    echo "FAIL: $1"
    echo "  --- 標準出力 ---"
    sed 's/^/  /' "$WORK/out.txt"
    echo "  --- 標準エラー ---"
    sed 's/^/  /' "$WORK/err.txt"
    echo "  --- gh の呼び出し ---"
    sed 's/^/  /' "$WORK/calls.log"
    FAILED=1
}

# 終了コードと、選ばれた PR の番号(空白でつないだもの)が期待どおりか
expect() {
    local name="$1" want_rc="$2" want_out="$3"
    if [ "$RC" -eq "$want_rc" ] && [ "$OUT" = "$want_out" ]; then
        ok "$name"
    else
        ng "$name (終了コード ${want_rc}・出力 '${want_out}' のはずが、終了コード ${RC}・出力 '${OUT}')"
    fi
}

# 標準エラーに文字列が出ているか
expect_err() {
    if grep -qF -- "$2" "$WORK/err.txt"; then ok "$1"; else ng "$1 (標準エラーに '$2' が無い)"; fi
}

# gh の呼び出しに、文字列を含む行が無いか
expect_no_call() {
    if grep -qF -- "$2" "$WORK/calls.log"; then ng "$1 ('$2' を含む呼び出しがある)"; else ok "$1"; fi
}

# === 検査が通っていない PR は選ばれない ============================================
reset_scenario
add_pr 11 "$SHA_A"
set_runs "$SHA_A" build:completed:success:1 lint:in_progress:-:2
set_behind "$SHA_A" 3
run
expect "検査の途中の PR は選ばれない" 0 ""
expect_err "検査の途中の PR は、通っていない検査の名前を出す" "#11: 検査が通っていないため、合わせません(lint)"
expect_no_call "検査の途中の PR は、main より古いかを調べない" "compare"

reset_scenario
add_pr 11 "$SHA_A"
set_runs "$SHA_A" build:completed:failure:1 lint:completed:success:2
set_behind "$SHA_A" 3
run
expect "検査が赤の PR は選ばれない" 0 ""

for conclusion in cancelled timed_out action_required stale; do
    reset_scenario
    add_pr 11 "$SHA_A"
    set_runs "$SHA_A" "build:completed:${conclusion}:1" lint:completed:success:2
    set_behind "$SHA_A" 3
    run
    expect "検査の結果が ${conclusion} の PR は選ばれない" 0 ""
done

reset_scenario
add_pr 11 "$SHA_A"
set_runs "$SHA_A" build:completed:success:1
set_behind "$SHA_A" 3
run
expect "検査の結果がまだ1つ出ていない PR は選ばれない" 0 ""

reset_scenario
add_pr 11 "$SHA_A"
set_runs "$SHA_A"
set_behind "$SHA_A" 3
run
expect "検査の結果が1つも無い PR は選ばれない" 0 ""

reset_scenario
add_pr 11 "$SHA_A"
set_runs "$SHA_A" build:completed:success:1 lint:completed:success:2 lint:queued:-:9
set_behind "$SHA_A" 3
run
expect "通った検査のあとに同じ名前の検査が動き直している PR は選ばれない" 0 ""

# === 検査が通った PR は選ばれる ====================================================
reset_scenario
add_pr 11 "$SHA_A"
set_runs "$SHA_A" build:completed:success:1 lint:completed:success:2
set_behind "$SHA_A" 3
run
expect "検査が通っていて main より古い PR は選ばれる" 0 "11"
expect_err "選んだ PR は理由を出す" "#11: 検査が通っていて main より古いため、合わせます"

reset_scenario
add_pr 11 "$SHA_A"
set_runs "$SHA_A" build:completed:skipped:1 lint:completed:neutral:2
set_behind "$SHA_A" 1
run
expect "検査の結果が skipped と neutral の PR は選ばれる" 0 "11"

reset_scenario
add_pr 11 "$SHA_A"
set_runs "$SHA_A" build:completed:failure:1 build:completed:success:7 lint:completed:success:2
set_behind "$SHA_A" 1
run
expect "赤のあとに動かし直して通った PR は選ばれる" 0 "11"

reset_scenario
add_pr 11 "$SHA_A"
set_runs "$SHA_A" build:completed:success:1 lint:completed:success:2 gate:completed:failure:3 paused:completed:failure:4 other:completed:failure:5
set_behind "$SHA_A" 1
run
expect "承認で結果が変わる検査・止めてある検査・必須でない検査だけが赤の PR は選ばれる" 0 "11"

reset_scenario
add_pr 11 "$SHA_A"
set_runs "$SHA_A" build:completed:success:1 lint:completed:success:2
set_behind "$SHA_A" 0
run
expect "検査が通っていても main の最新を含む PR は選ばれない" 0 ""
expect_err "main の最新を含む PR は、最新だと出す" "#11: すでに最新です"

# === 複数の PR ===================================================================
reset_scenario
add_pr 11 "$SHA_A"
add_pr 12 "$SHA_B"
add_pr 13 "$SHA_C"
set_runs "$SHA_A" build:completed:success:1 lint:completed:success:2
set_runs "$SHA_B" build:in_progress:-:3 lint:completed:success:4
set_runs "$SHA_C" build:completed:success:5 lint:completed:success:6
set_behind "$SHA_A" 2
set_behind "$SHA_B" 2
set_behind "$SHA_C" 2
run
expect "検査が通った PR が複数あれば、すべて選ばれ、通っていない PR は選ばれない" 0 "11 13"

HEAD_FILTER="$SHA_C"
run
expect "HEAD_SHA があるときは、最新のコミットが同じ PR だけを見る" 0 "13"
expect_no_call "HEAD_SHA と違う PR の検査の結果は読まない" "$SHA_A"

HEAD_FILTER="dddddddddddddddddddddddddddddddddddddddd"
run
expect "HEAD_SHA が最新のコミットの PR が無ければ、何も選ばない" 0 ""

# === 対象の PR でないものは選ばれない =============================================
reset_scenario
add_pr 21 "$SHA_A" '.draft = true'
add_pr 22 "$SHA_A" '.head.repo.full_name = "someone/repo"'
add_pr 23 "$SHA_A" '.head.ref = "canary/escape-hatch"'
add_pr 24 "$SHA_A" '.labels = [{name: "canary"}]'
set_runs "$SHA_A" build:completed:success:1 lint:completed:success:2
set_behind "$SHA_A" 2
run
expect "下書き・fork・カナリアPR(ブランチ名とラベル)は選ばれない" 0 ""
expect_no_call "対象でない PR の検査の結果は読まない" "check-runs"

reset_scenario
run
expect "開いている PR が無ければ、何も選ばない" 0 ""

# === 本物の期待一覧 ===============================================================
# 数える検査の名前を期待一覧から取り、すべて通った結果を作る
real_specs() {
    jq -r --arg skip "$1" '.checks | to_entries[]
        | select(.value.state == "active" and .value.approval_gated == false and .value.context != $skip)
        | "\(.value.context):completed:success:\(.key + 1)"' "$REAL_CHECKS"
}
reset_scenario
CHECKS_FILE=""
add_pr 11 "$SHA_A"
mapfile -t specs < <(real_specs "")
set_runs "$SHA_A" "${specs[@]}" escape-hatch:completed:failure:901 dependency-gate:completed:failure:902 pre-merge-check:completed:failure:903 dependency-cooldown:completed:failure:904
set_behind "$SHA_A" 1
run
expect "本物の期待一覧で、承認で結果が変わる4つの検査だけが赤の PR は選ばれる" 0 "11"

mapfile -t specs < <(real_specs "backend-test")
set_runs "$SHA_A" "${specs[@]}"
run
expect "本物の期待一覧で、backend-test の結果が出ていない PR は選ばれない" 0 ""
expect_err "本物の期待一覧で、通っていない検査の名前を出す" "(backend-test)"

# === 判定できないとき =============================================================
reset_scenario
add_pr 11 "$SHA_A"
NO_PULLS=1 run
expect "PR の一覧を取れなければ、何も選ばず失敗にする" 1 ""

for raw in '' '{"message":"Bad credentials"}'; do
    reset_scenario
    printf '%s' "$raw" >"$WORK/raw-pulls.json"
    PULLS_FILE="$WORK/raw-pulls.json" run
    expect "PR の一覧の応答の形が違えば、何も選ばず失敗にする('${raw}')" 1 ""
done

reset_scenario
add_pr 11 "$SHA_A"
add_pr 12 "$SHA_B"
set_runs "$SHA_B" build:completed:success:1 lint:completed:success:2
set_behind "$SHA_B" 1
run
expect "検査の結果を取れない PR は選ばず、ほかの PR を選んでから失敗にする" 1 "12"
expect_err "検査の結果を取れない PR の番号を出す" "#11 を判定できませんでした"

for raw in '' '[{"message":"Not Found"}]' '{"check_runs":[]}'; do
    reset_scenario
    add_pr 11 "$SHA_A"
    printf '%s' "$raw" >"$WORK/stub/runs-$SHA_A.json"
    set_behind "$SHA_A" 1
    run
    expect "検査の結果の応答の形が違えば、選ばず失敗にする('${raw}')" 1 ""
done

reset_scenario
add_pr 11 "$SHA_A"
set_runs "$SHA_A" build:completed:success:1 lint:completed:success:2
run
expect "main より古いかを調べられなければ、選ばず失敗にする" 1 ""

reset_scenario
add_pr 11 "$SHA_A"
set_runs "$SHA_A" build:completed:success:1 lint:completed:success:2
echo '{"message":"Not Found"}' >"$WORK/stub/compare-$SHA_A.json"
run
expect "main との比較の応答の形が違えば、選ばず失敗にする" 1 ""
expect_err "main との比較の応答の形が違えば、調べられないと出す" "main より古いかを調べられない"

for bad in '{"checks": []}' '{"checks": [{"context": "build", "state": "active"}]}' '{"checks": [{"context": "gate", "state": "active", "approval_gated": true}]}' 'not json'; do
    reset_scenario
    add_pr 11 "$SHA_A"
    set_runs "$SHA_A" build:completed:success:1 lint:completed:success:2
    set_behind "$SHA_A" 1
    printf '%s\n' "$bad" >"$WORK/bad-checks.json"
    CHECKS_FILE="$WORK/bad-checks.json"
    run
    expect "期待一覧の形が違えば、何も選ばず失敗にする(${bad})" 1 ""
    expect_err "期待一覧の形が違えば、期待一覧を読めないと出す(${bad})" "期待一覧を読めません"
done

reset_scenario
add_pr 11 "$SHA_A"
HEAD_FILTER="main"
run
expect "HEAD_SHA がコミットの形でなければ、失敗にする" 1 ""
expect_no_call "HEAD_SHA がコミットの形でなければ、gh を呼ばない" "api"

reset_scenario
TOKEN="" run
expect "GH_TOKEN が無ければ、失敗にする" 1 ""
unset TOKEN

reset_scenario
USE_FILTER=""
run
expect "TARGET_FILTER が無ければ、失敗にする" 1 ""

# === 全体 ========================================================================
if [ -s "$WORK/unexpected.log" ]; then
    echo "FAIL: 想定していない gh の呼び出しがある"
    sed 's/^/  /' "$WORK/unexpected.log"
    FAILED=1
else
    ok "想定していない gh の呼び出し(書き込みを含む)が無い"
fi

if [ "$FAILED" -ne 0 ]; then
    echo "失敗したテストがあります。"
    exit 1
fi
echo "すべてのテストが通りました。"
