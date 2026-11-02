#!/usr/bin/env bash
# =====================================================================
# check-audit-cooldown-exceptions.sh の自動テスト(audit-weekly CI から実行)
#
# gh をスタブし、窓の中でマージされた PR の記録が一覧に出ること、窓の外の PR と
# マージした head ではない head の記録が載らないこと、記録を読めないときの
# 終了コードと報告を検証する。
#   0 = 一覧に載せる版が無い / 1 = 一覧に載せる版がある / 2 = 記録を読めなかった
#
# スタブは実際の API の形の JSON を返し、窓の決め方と記録の読み取りは本体に
# させる。記録のコメントの一覧は lib-notice-comment.sh の本物が読む。
# 時刻は NOW_EPOCH で 2026-01-10T00:00:00Z に固定する。前の回の週次監査の実行は、
# 既定では 2026-01-05T12:00:00Z に始まったものとする。
# 環境変数 KP_TEST_CASE に場合の名前を入れると、その場合だけを流す。
# 外部への問い合わせを行わないため、実行にネットワークを必要としない。
# =====================================================================
set -uo pipefail

SCRIPT="$(cd "$(dirname "$0")/.." && pwd)/check-audit-cooldown-exceptions.sh"
WORK=$(mktemp -d) || exit 1
[ -n "$WORK" ] && [ -d "$WORK" ] || exit 1
trap 'rm -rf "$WORK"' EXIT
FAILED=0
CASE="${KP_TEST_CASE:-}"
BOT="github-actions[bot]"

# 判定の基準時刻。2026-01-10T00:00:00Z
NOW=1768003200
RUN_ID=9999

mkdir -p "$WORK/bin" "$WORK/stub"

# --- gh のスタブ -------------------------------------------------------------
# 呼び出しの種類:
#   wfruns    api repos/…/actions/workflows/audit-weekly.yaml/runs…  → $STUB_DIR/wfruns.json
#   search    api search/issues?… --paginate --slurp                → $STUB_DIR/search.json
#   pull      api repos/…/pulls/<N>                                 → $STUB_DIR/pull_<N>.json
#   comments  api --paginate repos/…/issues/<N>/comments            → $STUB_DIR/comments_<N>.json
# $STUB_FAIL_ON に種類を入れると、その種類だけ失敗させる。$STUB_FAIL_PR に PR の番号を
# 入れると、失敗させる種類をその PR の呼び出しに限る。
cat >"$WORK/bin/gh" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"${STUB_CALLS:?}"
kind="" n=""
case " $* " in
*"/actions/workflows/audit-weekly.yaml/runs"*) kind=wfruns ;;
*" search/issues?"*) kind=search ;;
*"/issues/"*"/comments "*)
    kind=comments
    n=$(printf '%s' "$*" | sed -n 's|.*/issues/\([0-9]*\)/comments.*|\1|p')
    ;;
*"/pulls/"*)
    kind=pull
    n=$(printf '%s' "$*" | sed -n 's|.*/pulls/\([0-9]*\).*|\1|p')
    ;;
esac
if [ -z "$kind" ]; then
    echo "stub: unexpected call: $*" >&2
    exit 1
fi
if [ "${STUB_FAIL_ON:-}" = "$kind" ] && { [ -z "${STUB_FAIL_PR:-}" ] || [ "${STUB_FAIL_PR}" = "$n" ]; }; then
    echo "gh: 失敗をシミュレート" >&2
    exit 1
fi
case "$kind" in
wfruns | search) cat "${STUB_DIR:?}/${kind}.json" ;;
*) cat "${STUB_DIR:?}/${kind}_${n}.json" ;;
esac
STUB
chmod +x "$WORK/bin/gh"

# --- 入力の組み立て ---------------------------------------------------------
# 使い方: wfruns <前の回の実行の created_at か none>。今の実行(RUN_ID)を先頭に置く
wfruns() {
    if [ "$1" = none ]; then
        jq -n --argjson id "$RUN_ID" '{workflow_runs: [{id: $id, created_at: "2026-01-10T00:00:00Z"}]}'
    else
        jq -n --argjson id "$RUN_ID" --arg prev "$1" '{workflow_runs: [
            {id: $id, created_at: "2026-01-10T00:00:00Z"},
            {id: ($id - 1), created_at: $prev},
            {id: ($id - 9), created_at: "2025-12-29T00:00:00Z"}]}'
    fi >"$WORK/stub/wfruns.json"
}

# 使い方: search <total_count> <PR番号...>。--paginate --slurp の形(ページの配列)で書く
search() {
    local total="$1"
    shift
    printf '%s\n' "$@" | jq -R 'select(length > 0) | tonumber' | jq -s --argjson t "$total" \
        '[{total_count: $t, incomplete_results: false, items: map({number: .})}]' >"$WORK/stub/search.json"
}

# 使い方: pull <PR番号> <merged_at> <head_sha> [本文]。コメントの一覧は空にしておく
pull() {
    jq -n --argjson n "$1" --arg m "$2" --arg sha "$3" --arg body "${4:-}" \
        '{number: $n, merged_at: $m, head: {sha: $sha}, body: (if $body == "" then null else $body end)}' \
        >"$WORK/stub/pull_$1.json"
    [ -f "$WORK/stub/comments_$1.json" ] || printf '[]\n' >"$WORK/stub/comments_$1.json"
}

# 使い方: sha <1文字>。その文字を40個並べた head の SHA を出す
sha() { printf "%040d" 0 | tr 0 "$1"; }

# 使い方: record_json <PR番号> <head_sha> <部品の名前>。データの形の節の記録の JSON を出す
record_json() {
    jq -cn --argjson pr "$1" --arg head "$2" --arg name "$3" '{
        schema: 1, pr: $pr, head: $head, recorded_at: "2026-01-05T01:02:03Z",
        entries: [
            {ecosystem: "npm", name: $name, version: "1.12.1", published_at: "2026-01-04T10:00:00Z",
             alerts: [
                {number: 210, ghsa_id: "GHSA-aaaa-bbbb-cccc", severity: "high",
                 html_url: "https://github.com/owner/repo/security/dependabot/210"},
                {number: 211, ghsa_id: "GHSA-dddd-eeee-ffff", severity: "critical",
                 html_url: "https://github.com/owner/repo/security/dependabot/211"}]},
            {ecosystem: "maven", name: "org.postgresql:postgresql", version: "42.7.15",
             published_at: "2026-01-04T12:00:00Z",
             alerts: [
                {number: 212, ghsa_id: "GHSA-gggg-hhhh-iiii", severity: "high",
                 html_url: "https://github.com/owner/repo/security/dependabot/212"}]}]}'
}

# 使い方: add_comment <PR番号> <作成者> <本文>。REST の Issue コメントの一覧の1件の形で足す
add_comment() {
    local f="$WORK/stub/comments_$1.json"
    [ -f "$f" ] || printf '[]\n' >"$f"
    jq --arg login "$2" --arg body "$3" \
        '. + [{id: (length + 1), user: {login: $login}, created_at: "2026-01-05T01:02:03Z", body: $body}]' \
        "$f" >"$f.new" && mv "$f.new" "$f"
}

# 使い方: record_comment <PR番号> <作成者> <目印の head> <記録の data の値>
# record-cooldown-exception.sh が書くのと同じ並びのコメントを足す
record_comment() {
    add_comment "$1" "$2" "### 公開から72時間待たずに入れる版

| 部品 | 版 | 公開日時 | 理由になった警告 |
|---|---|---|---|

<!-- cooldown-exception-data data=$4 -->

<!-- cooldown-exception-record kind=exception head=$3 -->"
}

# 使い方: b64 <文字列>。改行の無い base64 にする
b64() { printf '%s' "$1" | base64 | tr -d '\n'; }

# 使い方: ci_json <道具> <公開日時> <確かめた日時>。データの形の節の CI の道具の記録の JSON を出す
ci_json() {
    jq -cn --arg tool "$1" --arg pub "$2" --arg at "$3" '{schema: 1, entries: [{
        tool: $tool, version: "0.69.3", published_at: $pub,
        owner_instruction: "2026-01-05 に所有者が、Trivy を 0.69.3 に上げるよう指示した",
        signature: {result: "verified", method: "cosign verify-blob",
                    signer: "https://github.com/aquasecurity/trivy/.github/workflows/reusable-release.yaml@refs/tags/v0.69.3",
                    checked_at: $at}}]}'
}

# 使い方: ci_body <記録の data の値>。CI の道具の記録を持つ PR の本文を出す
ci_body() {
    printf '## 概要\n\nTrivy の版を上げる。\n\n<!-- ci-tool-cooldown-exception data=%s -->\n' "$1"
}

reset_all() {
    rm -f "$WORK/stub/"*.json
    : >"$WORK/calls.log"
    : >"$WORK/summary.md"
    unset STUB_FAIL_ON STUB_FAIL_PR
    wfruns "2026-01-05T12:00:00Z"
    search 0
}

# 使い方: run。報告を $WORK/summary.md に、終了コードを $RC に入れる
run() {
    : >"$WORK/summary.md"
    PATH="$WORK/bin:$PATH" STUB_CALLS="$WORK/calls.log" STUB_DIR="$WORK/stub" \
        STUB_FAIL_ON="${STUB_FAIL_ON:-}" STUB_FAIL_PR="${STUB_FAIL_PR:-}" \
        GH_TOKEN=dummy GITHUB_REPOSITORY=owner/repo GITHUB_REPOSITORY_OWNER=owner \
        GITHUB_RUN_ID="$RUN_ID" NOW_EPOCH="$NOW" GITHUB_STEP_SUMMARY="$WORK/summary.md" \
        bash "$SCRIPT" >"$WORK/out.txt" 2>"$WORK/err.log"
    RC=$?
}

pass() { echo "PASS: $1"; }
fail() {
    echo "FAIL: $1 ($2)"
    FAILED=1
}

expect_rc() {
    if [ "$RC" -eq "$2" ]; then pass "$1"; else fail "$1" "expected exit $2, got $RC / 標準エラー: $(head -c 400 "$WORK/err.log")"; fi
}

# 使い方: expect_line <説明> <行の全体>。報告に、その行がそのままある
expect_line() {
    if grep -qxF -- "$2" "$WORK/summary.md"; then
        pass "$1"
    else
        fail "$1" "行が無い: $2 / 報告: $(head -c 1500 "$WORK/summary.md")"
    fi
}

# 使い方: expect_has <説明> <文字列>。報告に、その文字列がある
expect_has() {
    if grep -qF -- "$2" "$WORK/summary.md"; then
        pass "$1"
    else
        fail "$1" "文字列が無い: $2 / 報告: $(head -c 1500 "$WORK/summary.md")"
    fi
}

# 使い方: expect_lacks <説明> <文字列>。報告に、その文字列が無い
expect_lacks() {
    if grep -qF -- "$2" "$WORK/summary.md"; then
        fail "$1" "文字列がある: $2"
    else
        pass "$1"
    fi
}

expect_empty_summary() {
    if [ -s "$WORK/summary.md" ]; then
        fail "$1" "報告: $(head -c 800 "$WORK/summary.md")"
    else
        pass "$1"
    fi
}

# 使い方: expect_rows <説明> <行の数>。報告の表の、見出しと区切りを除いた行の数
expect_rows() {
    local n
    n=$(grep -c '^| `\|^| #' "$WORK/summary.md")
    if [ "$n" -eq "$2" ]; then pass "$1"; else fail "$1" "表の行が ${n} 行(期待は $2 行) / 報告: $(head -c 1500 "$WORK/summary.md")"; fi
}

# 使い方: expect_calls <説明> <grep の式> <回数>
expect_calls() {
    local n
    n=$(grep -c -- "$2" "$WORK/calls.log")
    if [ "$n" -eq "$3" ]; then pass "$1"; else fail "$1" "「$2」が ${n} 回(期待は $3 回)"; fi
}

RAN=0
want() {
    if [ -z "$CASE" ] || [ "$CASE" = "$1" ]; then
        RAN=$((RAN + 1))
        echo "--- $1 ---"
        reset_all
        return 0
    fi
    return 1
}

HEADER='| 部品か道具の名前 | 版 | 公開日時 | 理由 | 署名を確かめた結果 | PR | マージの日時 |'
AXIOS_ROW="| \`axios\`(npm) | \`1.12.1\` | 2026-01-04T10:00:00Z | \`#210\` GHSA-aaaa-bbbb-cccc(high) https://github.com/owner/repo/security/dependabot/210<br>\`#211\` GHSA-dddd-eeee-ffff(critical) https://github.com/owner/repo/security/dependabot/211 |  | #11 | 2026-01-06T00:00:00Z |"
PG_ROW="| \`org.postgresql:postgresql\`(maven) | \`42.7.15\` | 2026-01-04T12:00:00Z | \`#212\` GHSA-gggg-hhhh-iiii(high) https://github.com/owner/repo/security/dependabot/212 |  | #11 | 2026-01-06T00:00:00Z |"
TRIVY_ROW="| \`trivy\`(CI の道具) | \`0.69.3\` | 2026-01-05T09:00:00Z | 2026-01-05 に所有者が、Trivy を 0.69.3 に上げるよう指示した | verified、cosign verify-blob、\`https://github.com/aquasecurity/trivy/.github/workflows/reusable-release.yaml@refs/tags/v0.69.3\`、2026-01-05T10:00:00Z | #11 | 2026-01-06T00:00:00Z |"

if want window_in; then
    pull 11 "2026-01-06T00:00:00Z" "$(sha a)" \
        "$(ci_body "$(b64 "$(ci_json trivy 2026-01-05T09:00:00Z 2026-01-05T10:00:00Z)")")"
    record_comment 11 "$BOT" "$(sha a)" "$(b64 "$(record_json 11 "$(sha a)" axios)")"
    search 1 11
    run
    expect_rc "窓の中でマージされた PR の記録があれば終了コード 1 になる" 1
    expect_line "見出しが出る" "### 72時間待たずに入れた版"
    expect_line "表の見出しが出る" "$HEADER"
    expect_line "npm の部品の版が、すべての欄とともに一覧に出る" "$AXIOS_ROW"
    expect_line "maven の部品の版が、すべての欄とともに一覧に出る" "$PG_ROW"
    expect_line "CI の道具の版が、すべての欄とともに一覧に出る" "$TRIVY_ROW"
    expect_rows "一覧の行は記録の版の数だけある" 3
    expect_has "窓の始まりが報告に出る" "2026-01-05T12:00:00Z"
    expect_calls "今の実行を除いた前の回の実行の日付で検索する" 'search/issues?q=repo:owner/repo+is:pr+is:merged+merged:>=2026-01-05&per_page=100 --paginate --slurp' 1
fi

if want ci_merged_at; then
    # 公開と確かめた日時は窓の前でも、マージが窓の中なら載る
    pull 12 "2026-01-07T00:00:00Z" "$(sha b)" \
        "$(ci_body "$(b64 "$(ci_json trivy 2025-12-01T00:00:00Z 2025-12-02T00:00:00Z)")")"
    # 公開と確かめた日時は窓の中でも、マージが窓の前(検索の日付には当たる)なら載らない
    pull 13 "2026-01-05T11:00:00Z" "$(sha c)" \
        "$(ci_body "$(b64 "$(ci_json terraform 2026-01-06T00:00:00Z 2026-01-06T01:00:00Z)")")"
    search 2 12 13
    run
    expect_rc "CI の道具の記録は PR がマージされた日時で窓に入る(終了コード)" 1
    expect_has "CI の道具の記録は PR がマージされた日時で窓に入る(窓の中のマージ)" "| \`trivy\`(CI の道具) | \`0.69.3\` | 2025-12-01T00:00:00Z |"
    expect_lacks "CI の道具の記録は PR がマージされた日時で窓に入る(窓の前のマージ)" 'terraform'
    expect_rows "CI の道具の記録は PR がマージされた日時で窓に入る(行の数)" 1
fi

if want outside; then
    pull 11 "2026-01-06T00:00:00Z" "$(sha a)"
    record_comment 11 "$BOT" "$(sha a)" "$(b64 "$(record_json 11 "$(sha a)" axios)")"
    # 窓の始まりの1秒前にマージされた PR
    pull 14 "2026-01-05T11:59:59Z" "$(sha d)"
    record_comment 14 "$BOT" "$(sha d)" "$(b64 "$(record_json 14 "$(sha d)" left-pad)")"
    # 窓の中でマージされたが、記録はマージした head の前の head のもの
    pull 15 "2026-01-08T00:00:00Z" "$(sha e)"
    record_comment 15 "$BOT" "$(sha f)" "$(b64 "$(record_json 15 "$(sha f)" lodash)")"
    search 3 11 14 15
    run
    expect_rc "窓の外でマージされた PR と、マージした head ではない head の記録は載らない(終了コード)" 1
    expect_line "窓の外でマージされた PR と、マージした head ではない head の記録は載らない(窓の中の記録は載る)" "$AXIOS_ROW"
    expect_lacks "窓の外でマージされた PR と、マージした head ではない head の記録は載らない(窓の外)" 'left-pad'
    expect_lacks "窓の外でマージされた PR と、マージした head ではない head の記録は載らない(前の head)" 'lodash'
    expect_rows "窓の外でマージされた PR と、マージした head ではない head の記録は載らない(行の数)" 2
fi

if want none; then
    pull 17 "2026-01-08T00:00:00Z" "$(sha 1)" "記録の無い本文"
    add_comment 17 "$BOT" "<!-- auto-merge-notice kind=reserved head=$(sha 1) -->"
    search 1 17
    run
    expect_rc "載せる版が無ければ終了コード 0 になる" 0
    expect_empty_summary "載せる版が無ければ報告に何も書かない"
    search 0
    run
    expect_rc "窓の中でマージされた PR が無ければ終了コード 0 になる" 0
    expect_empty_summary "窓の中でマージされた PR が無ければ報告に何も書かない"
fi

if want broken; then
    pull 18 "2026-01-08T00:00:00Z" "$(sha 2)"
    record_comment 18 "$BOT" "$(sha 2)" '@@@'
    search 1 18
    run
    expect_rc "記録の base64 が壊れていれば終了コード 2 になる" 2
    expect_has "記録の base64 が壊れていれば PR の番号が報告に出る" "#18"
    expect_has "記録の base64 が壊れていれば、壊れていると報告に出る" "記録の JSON が壊れています"

    reset_all
    pull 19 "2026-01-08T00:00:00Z" "$(sha 3)"
    record_comment 19 "$BOT" "$(sha 3)" "$(b64 '{"schema": 1, "entries": [')"
    search 1 19
    run
    expect_rc "記録の JSON が壊れていれば終了コード 2 になる" 2
    expect_has "記録の JSON が壊れていれば PR の番号が報告に出る" "#19"

    reset_all
    pull 19 "2026-01-08T00:00:00Z" "$(sha 3)"
    record_comment 19 "$BOT" "$(sha 3)" "$(b64 '{"schema": 1, "entries": []}')"
    search 1 19
    run
    expect_rc "記録の JSON の形が違えば終了コード 2 になる" 2
    expect_has "記録の JSON の形が違えば PR の番号が報告に出る" "#19"

    reset_all
    pull 19 "2026-01-08T00:00:00Z" "$(sha 3)"
    add_comment 19 "$BOT" "<!-- cooldown-exception-record kind=exception head=$(sha 3) -->"
    search 1 19
    run
    expect_rc "記録のコメントに記録の JSON の行が無ければ終了コード 2 になる" 2
    expect_has "記録のコメントに記録の JSON の行が無ければ PR の番号が報告に出る" "#19"
    expect_has "記録のコメントに記録の JSON の行が無ければ、行が無いと報告に出る" "記録の JSON の行がありません"

    reset_all
    pull 19 "2026-01-08T00:00:00Z" "$(sha 3)"
    record_comment 19 "$BOT" "$(sha 3)" "$(b64 "$(record_json 99 "$(sha 3)" axios)")"
    search 1 19
    run
    expect_rc "記録の JSON の PR の番号が違えば終了コード 2 になる" 2
    expect_has "記録の JSON の PR の番号が違えば PR の番号が報告に出る" "#19"

    reset_all
    pull 19 "2026-01-08T00:00:00Z" "$(sha 3)"
    record_comment 19 "$BOT" "$(sha 3)" "$(b64 "$(record_json 19 "$(sha 9)" axios)")"
    search 1 19
    run
    expect_rc "記録の JSON の head がマージした head と違えば終了コード 2 になる" 2
    expect_has "記録の JSON の head がマージした head と違えば PR の番号が報告に出る" "#19"

    reset_all
    pull 20 "2026-01-08T00:00:00Z" "$(sha 4)" "<!-- ci-tool-cooldown-exception -->"
    search 1 20
    run
    expect_rc "CI の道具の記録の目印に data が無ければ終了コード 2 になる" 2
    expect_has "CI の道具の記録の目印に data が無ければ PR の番号が報告に出る" "#20"

    reset_all
    pull 20 "2026-01-08T00:00:00Z" "$(sha 4)" "$(ci_body '<base64>')"
    # 読める PR の記録は、読めない PR があっても報告に出る
    pull 11 "2026-01-06T00:00:00Z" "$(sha a)"
    record_comment 11 "$BOT" "$(sha a)" "$(b64 "$(record_json 11 "$(sha a)" axios)")"
    search 2 20 11
    run
    expect_rc "CI の道具の記録が壊れていれば終了コード 2 になる" 2
    expect_has "CI の道具の記録が壊れていれば PR の番号が報告に出る" "#20"
    expect_line "読めない PR があっても、読めた PR の記録は一覧に出る" "$AXIOS_ROW"
fi

if want total_over; then
    search 1001 11
    pull 11 "2026-01-06T00:00:00Z" "$(sha a)"
    run
    expect_rc "検索の total_count が1000を超えたら終了コード 2 になる" 2
    expect_has "検索の total_count が1000を超えたら件数が報告に出る" "1001"
    expect_calls "検索の total_count が1000を超えたら PR を読まない" '/pulls/' 0
fi

if want other_author; then
    pull 21 "2026-01-08T00:00:00Z" "$(sha 5)"
    record_comment 21 "someone" "$(sha 5)" "$(b64 "$(record_json 21 "$(sha 5)" axios)")"
    search 1 21
    run
    expect_rc "github-actions[bot] 以外が書いた記録のコメントは数えない(終了コード)" 0
    expect_empty_summary "github-actions[bot] 以外が書いた記録のコメントは数えない(報告)"
fi

if want no_prev_run; then
    wfruns none
    pull 22 "2026-01-04T00:00:00Z" "$(sha 6)"
    record_comment 22 "$BOT" "$(sha 6)" "$(b64 "$(record_json 22 "$(sha 6)" axios)")"
    search 1 22
    run
    expect_rc "前の回の実行が無ければ7日前を窓の始まりにする(終了コード)" 1
    expect_has "前の回の実行が無ければ7日前を窓の始まりにする(窓の中の記録)" '| #22 | 2026-01-04T00:00:00Z |'
    expect_has "前の回の実行が無ければ7日前を窓の始まりにする(窓の始まり)" "2026-01-03T00:00:00Z"
    expect_calls "前の回の実行が無ければ7日前の日付で検索する" 'merged:>=2026-01-03&' 1
    # 前の回の実行(2026-01-05T12:00:00Z)があれば、同じ PR は窓の外になる
    wfruns "2026-01-05T12:00:00Z"
    run
    expect_rc "前の回の実行があれば、その始まりを窓の始まりにする" 0
fi

if want api_fail; then
    pull 11 "2026-01-06T00:00:00Z" "$(sha a)"
    record_comment 11 "$BOT" "$(sha a)" "$(b64 "$(record_json 11 "$(sha a)" axios)")"
    search 1 11
    STUB_FAIL_ON=wfruns run
    expect_rc "週次監査の実行の一覧を読めなければ終了コード 2 になる" 2
    STUB_FAIL_ON=search run
    expect_rc "検索が失敗したら終了コード 2 になる" 2
    STUB_FAIL_ON=pull run
    expect_rc "PR を読めなければ終了コード 2 になる" 2
    expect_has "PR を読めなければ PR の番号が報告に出る" "#11"
    STUB_FAIL_ON=comments run
    expect_rc "PR のコメントの一覧を読めなければ終了コード 2 になる" 2
    expect_has "PR のコメントの一覧を読めなければ PR の番号が報告に出る" "#11"
    printf '{"workflow_runs": "x"}\n' >"$WORK/stub/wfruns.json"
    run
    expect_rc "週次監査の実行の一覧の形が違えば終了コード 2 になる" 2
fi

if want env; then
    # GitHub Actions のランナーは GITHUB_REPOSITORY を渡すので、env -u で明示して外す。
    # 前に書いた代入は変数を足すだけで、引き継いだ変数を消さない
    env -u GITHUB_REPOSITORY \
        PATH="$WORK/bin:$PATH" STUB_CALLS="$WORK/calls.log" STUB_DIR="$WORK/stub" \
        GH_TOKEN=dummy GITHUB_REPOSITORY_OWNER=owner GITHUB_RUN_ID="$RUN_ID" NOW_EPOCH="$NOW" \
        GITHUB_STEP_SUMMARY="$WORK/summary.md" bash "$SCRIPT" >/dev/null 2>"$WORK/err.log"
    RC=$?
    expect_rc "GITHUB_REPOSITORY が無ければ終了コード 2 になる" 2
    expect_calls "GITHUB_REPOSITORY が無ければ GitHub に問わない" '.' 0
fi

if [ "$RAN" -eq 0 ]; then
    echo "FAIL: KP_TEST_CASE=${CASE} に当たる場合がありません"
    FAILED=1
fi

exit "$FAILED"
