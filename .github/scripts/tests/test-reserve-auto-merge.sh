#!/usr/bin/env bash
# =====================================================================
# reserve-auto-merge.sh の自動テスト
#
# gh を PATH の先頭の偽物で置き換え、標準出力の result= の行・終了コード・
# gh の呼び出し(引数と、そのときの GH_TOKEN の値)を確かめる。
#   終了コード 0 = 判定と、必要な操作・知らせを終えた(標準出力に result= の1行)
#   終了コード 1 = 照会できない・応答の形が違う・知らせを付けられない・使い方の誤り
#                  (result= の行を出さない)
#
# gh の偽物は実APIの形のJSONをそのまま返し、応答の解釈は本体に任せる。
# 呼び出しごとに「GH_TOKEN の値<タブ>引数」を1行で記録する。照会は標準の
# トークン、予約の操作だけ予約用のトークンで行われることを、この記録で確かめる。
# 知らせのコメントは lib-notice-comment.sh が REST の Issue コメントで読み書きする。
# 偽物はその一覧($STUB_COMMENTS の中身)を返し、POST された本文を写して残す。
# 想定していない呼び出しは失敗させ、別の記録に残す。
#
# 見直し(--sweep)の場面では、偽物は開いている PR の一覧と、PR ごとの照会の応答を
# $STUB_SWEEP_DIR から返す。標準出力は pr=<番号> result=<...> の行になる。
#
# 外部への問い合わせを行わないため、実行にネットワークを必要としない。
# =====================================================================
set -uo pipefail

SCRIPT="$(cd "$(dirname "$0")/.." && pwd)/reserve-auto-merge.sh"
WORK=$(mktemp -d) || exit 1
[ -n "$WORK" ] && [ -d "$WORK" ] || exit 1
trap 'rm -rf "$WORK"' EXIT
FAILED=0

QUERY_TOKEN="query-token"
RESERVE_TOKEN_VALUE="reserve-token"
HEAD_SHA="1111111111111111111111111111111111111111"
NEW_SHA="2222222222222222222222222222222222222222"
TAB=$(printf '\t')

mkdir -p "$WORK/bin"

# --- gh の偽物 -------------------------------------------------------------------
# 呼び出しを $STUB_CALLS に「GH_TOKEN の値<タブ>引数」で1行ずつ記録する
# (引数の中の改行は空白にする。GraphQL の照会文が複数行のため)。
#   PR の照会(GraphQL): $STUB_PR の中身(STUB_FAIL_QUERY で失敗)
#   予約の操作: STUB_MERGE_MODE が ok なら成功、fail なら失敗
#     (STUB_MERGE_ERR があれば、そのファイルの中身を失敗のエラーとして返す)
#   head の照会(予約の失敗のあと): STUB_VIEW_MODE が ok なら $STUB_CURRENT_HEAD を
#     headRefOid に入れて返す。fail なら失敗、invalid なら headRefOid の無い応答、
#     empty なら何も出さずに成功、newline なら改行だけを出して成功、
#     double なら JSON を2つ続けて出して成功
#   コメントの一覧(REST): $STUB_COMMENTS の中身(STUB_LIST_MODE が ok でなければ失敗)
#   コメントの POST: -F body=@<ファイル> の中身を $STUB_LAST_POST に写す
#     (STUB_POST_MODE が ok でなければ失敗)
# 見直し(--sweep)の場面だけで使う呼び出し(STUB_SWEEP_DIR があるときだけ応える。
# PR 番号に 7 を使わない。7 の照会は上の <PR番号> の形の場面のものが応える):
#   開いている PR の一覧: $STUB_SWEEP_DIR/list.json(STUB_SWEEP_LIST_MODE が ok で
#     なければ失敗)
#   PR の照会(GraphQL): $STUB_SWEEP_DIR/pr-<番号>.json。ファイルが無ければ失敗。
#     $STUB_SWEEP_DIR/hang-<番号> があれば応答せずに待ち続ける(時間切れの場面)
#   コメントの一覧(REST): 空の一覧
cat >"$WORK/bin/gh" <<'STUB'
#!/usr/bin/env bash
printf '%s\t%s\n' "${GH_TOKEN:-}" "$(printf '%s' "$*" | tr '\n' ' ')" >>"${STUB_CALLS:?}"
case "$*" in
"api graphql -f query="*" -F owner=owner -F name=repo -F number=7")
    if [ -n "${STUB_FAIL_QUERY:-}" ]; then
        echo "gh: Server Error (HTTP 502)" >&2
        exit 1
    fi
    cat "${STUB_PR:?}"
    ;;
"pr merge "*)
    if [ "${STUB_MERGE_MODE:?}" = "ok" ]; then
        # 実物も成功のときに何かを標準出力へ出しうる。本体の標準出力に混ざらないことを確かめる
        echo "✓ Pull request owner/repo#7 will be automatically merged via squash when all requirements are met"
    elif [ -n "${STUB_MERGE_ERR:-}" ]; then
        cat "$STUB_MERGE_ERR" >&2
        exit 1
    else
        echo "GraphQL: Pull request Auto merge is not allowed for this repository (enablePullRequestAutoMerge)" >&2
        exit 1
    fi
    ;;
"pr view 7 --repo owner/repo --json headRefOid")
    case "${STUB_VIEW_MODE:?}" in
    ok) printf '{"headRefOid":"%s"}\n' "${STUB_CURRENT_HEAD:?}" ;;
    invalid) printf '{"message":"unexpected"}\n' ;;
    empty) ;;
    newline) echo ;;
    double) printf '{"headRefOid":"%s"}\n{"headRefOid":"%s"}\n' "${STUB_CURRENT_HEAD:?}" "${STUB_CURRENT_HEAD:?}" ;;
    *)
        echo "gh: Server Error (HTTP 500)" >&2
        exit 1
        ;;
    esac
    ;;
"api --paginate repos/owner/repo/issues/7/comments")
    if [ "${STUB_LIST_MODE:?}" != "ok" ]; then
        echo "gh: Server Error (HTTP 502)" >&2
        exit 1
    fi
    cat "${STUB_COMMENTS:?}"
    ;;
"api -X POST repos/owner/repo/issues/7/comments -F body=@"*)
    if [ "${STUB_POST_MODE:?}" != "ok" ]; then
        echo "gh: Resource not accessible by integration (HTTP 403)" >&2
        exit 1
    fi
    for last in "$@"; do :; done
    cat "${last#body=@}" >"${STUB_LAST_POST:?}" || exit 1
    echo '{"id":1}'
    ;;
*)
    if [ -n "${STUB_SWEEP_DIR:-}" ]; then
        case "$*" in
        "pr list --repo owner/repo --state open --base main --limit 100 --json number")
            if [ "${STUB_SWEEP_LIST_MODE:?}" != "ok" ]; then
                echo "gh: Server Error (HTTP 502)" >&2
                exit 1
            fi
            cat "$STUB_SWEEP_DIR/list.json"
            exit 0
            ;;
        "api graphql -f query="*" -F owner=owner -F name=repo -F number="*)
            for last in "$@"; do :; done
            n="${last#number=}"
            if [ -e "$STUB_SWEEP_DIR/hang-$n" ]; then
                exec sleep 30
            fi
            if [ ! -f "$STUB_SWEEP_DIR/pr-$n.json" ]; then
                echo "gh: Server Error (HTTP 502)" >&2
                exit 1
            fi
            cat "$STUB_SWEEP_DIR/pr-$n.json"
            exit 0
            ;;
        "api --paginate repos/owner/repo/issues/"*"/comments")
            echo '[]'
            exit 0
            ;;
        esac
    fi
    printf '%s\n' "$*" >>"${STUB_UNEXPECTED:?}"
    echo "stub: unexpected call: $*" >&2
    exit 1
    ;;
esac
STUB
chmod +x "$WORK/bin/gh"
: >"$WORK/unexpected.log"
: >"$WORK/all-calls.log"
: >"$WORK/sweep-all-calls.log"

# --- 場面の材料 -------------------------------------------------------------------
# 各場面の前に呼び、PR の状態と偽物の振る舞いを既定に戻す。
# 既定は「対象の PR で、予約が無い」(bot が作った main 向けの開いた PR)。
reset_scenario() {
    P_STATE="OPEN"
    P_DRAFT="false"
    P_BASE="main"
    P_AUTHOR='{"login":"DogisRiki-bot"}'
    P_CROSS="false"
    P_HEADREF="feat/some-change"
    P_HEAD="$HEAD_SHA"
    P_LABELS='[]'
    P_ARMED='null'
    P_TIMELINE='[{"__typename":"PullRequestCommit"}]'
    RAW_PR=""
    RAW_PR_FILE=""
    FAIL_QUERY=""
    MERGE_MODE="ok"
    MERGE_ERR=""
    VIEW_MODE="ok"
    CURRENT_HEAD="$HEAD_SHA"
    LIST_MODE="ok"
    POST_MODE="ok"
    echo '[]' >"$WORK/comments.json"
}

# PR のコメントの一覧(REST の応答の形)に1件足す。
# 使い方: add_comment <作成者> <作成日時> <本文>
BOT="github-actions[bot]"
add_comment() {
    jq --arg l "$1" --arg at "$2" --arg b "$3" \
        '. + [{user: {login: $l}, created_at: $at, body: $b}]' "$WORK/comments.json" >"$WORK/comments.tmp" || exit 1
    mv "$WORK/comments.tmp" "$WORK/comments.json" || exit 1
}

# 直前の実行で付いたコメントを、知らせの作成者のコメントとして一覧に戻す
# (2度目の実行の場面を作る)
add_posted_comment() {
    add_comment "$BOT" "$1" "$(cat "$WORK/last-post.md")"
}

# 知らせの目印。使い方: marker <種類> [<head>]
marker() {
    echo "<!-- auto-merge-notice kind=$1 head=${2:-$HEAD_SHA} -->"
}

# GraphQL の応答の形({data:{repository:{pullRequest:{...}}}})で PR を書き出す
write_pr() {
    jq -n --arg state "$P_STATE" --argjson draft "$P_DRAFT" --arg base "$P_BASE" \
        --argjson author "$P_AUTHOR" --argjson cross "$P_CROSS" --arg headref "$P_HEADREF" \
        --arg head "$P_HEAD" --argjson labels "$P_LABELS" --argjson armed "$P_ARMED" \
        --argjson timeline "$P_TIMELINE" '
        {data: {repository: {pullRequest: {
            state: $state, isDraft: $draft, baseRefName: $base, author: $author,
            isCrossRepository: $cross, headRefName: $headref, headRefOid: $head,
            labels: {nodes: ($labels | map({name: .}))},
            autoMergeRequest: $armed,
            timelineItems: {nodes: $timeline}}}}}' >"$WORK/pr.json" || exit 1
}

# RAW_PR が空でなければ、その文字列をそのまま照会の応答にする(形の違う応答の場面)。
# RAW_PR_FILE が空でなければ、そのファイルの中身をそのまま照会の応答にする
# (0バイトや改行だけの応答の場面。文字列では表せないためファイルで渡す)
run() {
    : >"$WORK/calls.log"
    : >"$WORK/last-post.md"
    if [ -n "$RAW_PR_FILE" ]; then
        cat "$RAW_PR_FILE" >"$WORK/pr.json" || exit 1
    elif [ -n "$RAW_PR" ]; then
        printf '%s\n' "$RAW_PR" >"$WORK/pr.json"
    else
        write_pr
    fi
    PATH="$WORK/bin:$PATH" \
        STUB_CALLS="$WORK/calls.log" STUB_UNEXPECTED="$WORK/unexpected.log" \
        STUB_PR="$WORK/pr.json" STUB_FAIL_QUERY="$FAIL_QUERY" \
        STUB_MERGE_MODE="$MERGE_MODE" STUB_MERGE_ERR="$MERGE_ERR" \
        STUB_VIEW_MODE="$VIEW_MODE" STUB_CURRENT_HEAD="$CURRENT_HEAD" \
        STUB_COMMENTS="$WORK/comments.json" STUB_LIST_MODE="$LIST_MODE" \
        STUB_POST_MODE="$POST_MODE" STUB_LAST_POST="$WORK/last-post.md" \
        GITHUB_REPOSITORY="owner/repo" GITHUB_REPOSITORY_OWNER="owner-name" \
        GH_TOKEN="$QUERY_TOKEN" RESERVE_TOKEN="$RESERVE_TOKEN_VALUE" \
        bash "$SCRIPT" 7 >"$WORK/out.txt" 2>"$WORK/err.txt"
    RC=$?
    cat "$WORK/calls.log" >>"$WORK/all-calls.log"
    MERGES=$(grep -c "^[^${TAB}]*${TAB}pr merge " "$WORK/calls.log")
    POSTS=$(grep -c "^[^${TAB}]*${TAB}api -X POST " "$WORK/calls.log")
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

# 終了コード 0 で、標準出力が result=<期待> の1行だけ
expect_result() {
    local name="$1" want="$2"
    if [ "$RC" -ne 0 ]; then
        ng "$name (終了コード 0 のはずが $RC)"
        return
    fi
    if [ "$(cat "$WORK/out.txt")" != "result=${want}" ]; then
        ng "$name (標準出力が result=${want} の1行だけではない)"
        return
    fi
    ok "$name"
}

# 終了コード 1 で、result= の行を出さず、標準エラーに理由がある
expect_error() {
    local name="$1"
    if [ "$RC" -ne 1 ]; then
        ng "$name (終了コード 1 のはずが $RC)"
        return
    fi
    if [ -s "$WORK/out.txt" ]; then
        ng "$name (失敗なのに標準出力に何か出している)"
        return
    fi
    if [ ! -s "$WORK/err.txt" ]; then
        ng "$name (標準エラーに理由が無い)"
        return
    fi
    ok "$name"
}

expect_merges() {
    local name="$1" want="$2"
    if [ "$MERGES" -eq "$want" ]; then
        ok "$name"
    else
        ng "$name (予約の呼び出しの数 期待 $want、実際 $MERGES)"
    fi
}

# 知らせのコメントを付けた回数(失敗した POST の試みも数える)
expect_posts() {
    local name="$1" want="$2"
    if [ "$POSTS" -eq "$want" ]; then
        ok "$name"
    else
        ng "$name (コメントの POST の数 期待 $want、実際 $POSTS)"
    fi
}

# 直前の実行で付いたコメントの本文に、文字列がそのまま含まれている
expect_post_has() {
    local name="$1" want="$2"
    if grep -Fq -- "$want" "$WORK/last-post.md"; then
        ok "$name"
    else
        ng "$name (コメントの本文に「${want}」が無い)"
        echo "  --- コメントの本文 ---"
        sed 's/^/  /' "$WORK/last-post.md"
    fi
}

# 直前の実行で付いたコメントの先頭行が、所有者へのメンションで始まっている
expect_post_mentions_owner() {
    local name="$1"
    case "$(head -n 1 "$WORK/last-post.md")" in
    "@owner-name "*) ok "$name" ;;
    *) ng "$name (コメントの先頭行が @owner-name で始まっていない)" ;;
    esac
}

# 予約の呼び出しが、予約用のトークンで、決まった引数で1回だけ行われている
EXPECTED_MERGE="${RESERVE_TOKEN_VALUE}${TAB}pr merge --auto --squash --match-head-commit ${HEAD_SHA} 7 --repo owner/repo"
expect_reserved_call() {
    local name="$1"
    if [ "$MERGES" -eq 1 ] && grep -Fqx "$EXPECTED_MERGE" "$WORK/calls.log"; then
        ok "$name"
    else
        ng "$name"
    fi
}

# gh を1度も呼んでいない
expect_no_calls() {
    local name="$1"
    if [ -s "$WORK/calls.log" ]; then
        ng "$name (gh を呼んでいる)"
    else
        ok "$name"
    fi
}

# =====================================================================
# 対象の PR で予約が無ければ、照会したときの head に限って squash で予約する
# (3.5, 3.7, 6.1, 6.3)
# =====================================================================
reset_scenario
run
expect_result "bot が作った対象の PR に予約が無ければ reserved" reserved
expect_reserved_call "予約は --auto --squash --match-head-commit <照会した head> で、予約用のトークンで行う"
if [ "$(wc -l <"$WORK/out.txt" | tr -d ' ')" -eq 1 ]; then
    ok "標準出力は result= の1行だけ(gh の出力を混ぜない)"
else
    ng "標準出力は result= の1行だけ(gh の出力を混ぜない)"
fi
# 予約のあとに、未解消の知らせがあるかを読む(コメントの一覧。標準のトークン)
if [ "$(grep -c "^${QUERY_TOKEN}${TAB}api graphql " "$WORK/calls.log")" -eq 1 ] &&
    grep -Fqx "${QUERY_TOKEN}${TAB}api --paginate repos/owner/repo/issues/7/comments" "$WORK/calls.log" &&
    [ "$(wc -l <"$WORK/calls.log" | tr -d ' ')" -eq 3 ]; then
    ok "照会は標準のトークンで1回だけ行い、呼び出しは照会・予約・知らせの一覧の3回だけ"
else
    ng "照会は標準のトークンで1回だけ行い、呼び出しは照会・予約・知らせの一覧の3回だけ"
fi
expect_posts "知らせが無い PR に予約が付いても、コメントを付けない" 0
if grep "^[^${TAB}]*${TAB}api graphql " "$WORK/calls.log" | grep -q "^${RESERVE_TOKEN_VALUE}${TAB}"; then
    ng "照会に予約用のトークンを使わない"
else
    ok "照会に予約用のトークンを使わない"
fi
# 照会は読み取りだけで、判定に要る項目を含む
query_line=$(grep "${TAB}api graphql " "$WORK/calls.log")
query_ok=1
for field in state isDraft baseRefName author isCrossRepository headRefName headRefOid labels \
    autoMergeRequest PULL_REQUEST_COMMIT AUTO_MERGE_DISABLED_EVENT; do
    case "$query_line" in
    *"$field"*) ;;
    *)
        echo "  照会に ${field} が無い"
        query_ok=0
        ;;
    esac
done
case "$query_line" in
*mutation*) query_ok=0 ;;
esac
if [ "$query_ok" -eq 1 ]; then
    ok "照会は判定に要る項目を含み、書き込み(mutation)を含まない"
else
    ng "照会は判定に要る項目を含み、書き込み(mutation)を含まない"
fi

reset_scenario
P_AUTHOR='{"login":"owner-name"}'
run
expect_result "所有者が作った PR にも予約する(3.5)" reserved
expect_reserved_call "所有者が作った PR への予約も同じ引数とトークンで行う"

# 作成者のアカウントが消えていると author が null になる。Dependabot ではないため対象
reset_scenario
P_AUTHOR='null'
run
expect_result "作成者が分からない(author が null)PR にも予約する" reserved

reset_scenario
P_LABELS='["pre-merge-check"]'
run
expect_result "pre-merge-check ラベルが付いていても予約する(6.4)" reserved
expect_reserved_call "pre-merge-check ラベルが付いた PR への予約も同じ引数とトークンで行う"

# =====================================================================
# 対象外の PR には予約しない(3.4, 3.6, 4.5)
# =====================================================================
check_skipped() {
    local name="$1"
    run
    expect_result "${name}は skipped" skipped
    expect_merges "${name}に予約の呼び出しが無い" 0
}

reset_scenario
P_DRAFT="true"
check_skipped "下書きの PR"

reset_scenario
P_STATE="CLOSED"
check_skipped "閉じた PR"

reset_scenario
P_STATE="MERGED"
check_skipped "マージ済みの PR"

reset_scenario
P_BASE="develop"
check_skipped "base が main でない PR"

# GraphQL の author.login は dependabot、REST とイベントでは dependabot[bot]
reset_scenario
P_AUTHOR='{"login":"dependabot"}'
check_skipped "Dependabot の PR(login が dependabot)"

reset_scenario
P_AUTHOR='{"login":"dependabot[bot]"}'
check_skipped "Dependabot の PR(login が dependabot[bot])"

reset_scenario
P_CROSS="true"
check_skipped "fork からの PR"

reset_scenario
P_HEADREF="canary/escape-hatch-20261001"
check_skipped "ブランチ名が canary/ で始まる PR"

reset_scenario
P_LABELS='["documentation","canary"]'
check_skipped "ラベル canary が付いた PR"

# 対象外の条件に似ているだけの PR は対象のまま
reset_scenario
P_HEADREF="feat/canary/report"
run
expect_result "ブランチ名の途中に canary/ があるだけなら予約する" reserved

reset_scenario
P_HEADREF="canary-report"
P_LABELS='["canary-review"]'
run
expect_result "ブランチ名とラベルが canary で始まるだけ(canary/ でも canary でもない)なら予約する" reserved

# =====================================================================
# 予約済みなら触らない(3.8)
# =====================================================================
reset_scenario
P_ARMED='{"enabledAt":"2026-10-01T00:00:00Z"}'
run
expect_result "予約済みなら already(失敗として扱わない)" already
expect_merges "予約済みなら予約の呼び出しが無い" 0
expect_posts "知らせが無い PR が予約済みでも、コメントを付けない" 0

# =====================================================================
# 外れた理由を問わず予約する(4.1)
# =====================================================================
reset_scenario
P_TIMELINE='[{"__typename":"PullRequestCommit"},{"__typename":"AutoMergeDisabledEvent","reasonCode":"manually_disabled"}]'
run
expect_result "手で外された(manually_disabled)あとでも予約する" reserved
expect_reserved_call "手で外されたあとの予約も同じ引数とトークンで行う"

reset_scenario
P_TIMELINE='[{"__typename":"PullRequestCommit"},{"__typename":"AutoMergeDisabledEvent","reasonCode":"repository_rule_violation"}]'
run
expect_result "ルール違反(repository_rule_violation)で外れたあとでも予約する" reserved
expect_reserved_call "ルール違反で外れたあとの予約も同じ引数とトークンで行う"

# =====================================================================
# 予約の操作が失敗したとき
# =====================================================================
# 照会の後に新しいコミットが積まれていたら、何もしない
reset_scenario
MERGE_MODE="fail"
CURRENT_HEAD="$NEW_SHA"
run
expect_result "予約が失敗し head が変わっていたら head-moved" head-moved
expect_merges "head-moved では予約を繰り返さない(呼び出しは1回)" 1
if grep -Fqx "${QUERY_TOKEN}${TAB}pr view 7 --repo owner/repo --json headRefOid" "$WORK/calls.log"; then
    ok "予約の失敗のあとの head の照会は標準のトークンで行う"
else
    ng "予約の失敗のあとの head の照会は標準のトークンで行う"
fi
expect_posts "head-moved では知らせない(5.1)" 0

# head が変わっていなければ、failed の知らせを1回付けて終了コード 0(5.1, 5.2)
reset_scenario
MERGE_MODE="fail"
run
expect_result "予約が失敗し head が変わっていなければ failed(知らせを付けられたら終了コード 0)" failed
expect_merges "failed では予約を繰り返さない(呼び出しは1回)" 1
expect_posts "failed の知らせを1回付ける" 1
expect_post_has "failed の知らせに目印がある" "$(marker failed)"
expect_post_mentions_owner "failed の知らせは所有者へのメンションで始まる"
expect_post_has "failed の知らせに PR 番号がある" "PR #7"
expect_post_has "failed の知らせに失敗した操作がある" "自動マージの予約"
expect_post_has "failed の知らせに gh のエラーの要点がある" "enablePullRequestAutoMerge"
expect_post_has "failed の知らせにしてほしいこと(調査の依頼)がある" "Claude Code"
expect_post_has "failed の知らせにしてほしいこと(トークンの期限)がある" "トークンの期限"
if grep "^[^${TAB}]*${TAB}api " "$WORK/calls.log" | grep -qv "^${QUERY_TOKEN}${TAB}"; then
    ng "知らせの照会とコメントは標準のトークンで行う"
else
    ok "知らせの照会とコメントは標準のトークンで行う"
fi
if grep -q '予約' "$WORK/err.txt" && grep -q 'enablePullRequestAutoMerge' "$WORK/err.txt"; then
    ok "予約の失敗の理由(gh のエラーを含む)を標準エラーに出す"
else
    ng "予約の失敗の理由(gh のエラーを含む)を標準エラーに出す"
fi

# gh のエラーが長いときは、空行を除いた先頭の3行(1行200文字まで)だけを載せ、
# コードの囲みを閉じてしまうバッククォートを除く
reset_scenario
MERGE_MODE="fail"
MERGE_ERR="$WORK/merge-err.txt"
{
    echo "GraphQL: \`enablePullRequestAutoMerge\` was rejected"
    echo
    echo "L2:$(head -c 300 /dev/zero | tr '\0' 'x')"
    echo 'third line ```'
    echo 'FOURTH-LINE-MUST-NOT-APPEAR'
} >"$MERGE_ERR"
run
expect_result "gh のエラーが長くても failed" failed
expect_post_has "エラーの1行目を、バッククォートを除いて載せる" "GraphQL: enablePullRequestAutoMerge was rejected"
expect_post_has "空行は数えず、3行目までを載せる" "third line"
if grep -Fq "FOURTH-LINE-MUST-NOT-APPEAR" "$WORK/last-post.md"; then
    ng "エラーの4行目より後は載せない"
else
    ok "エラーの4行目より後は載せない"
fi
if [ "$(grep '^L2:' "$WORK/last-post.md" | tr -d '\n' | wc -c | tr -d ' ')" -eq 200 ]; then
    ok "エラーの1行は200文字で切り詰める"
else
    ng "エラーの1行は200文字で切り詰める"
fi
# バッククォートを含む行は、コードの囲みの2行(``` だけの行)のほかに無い
if [ "$(grep -c '`' "$WORK/last-post.md")" -eq 2 ] && [ "$(grep -cx '```' "$WORK/last-post.md")" -eq 2 ]; then
    ok "エラーの中のバッククォートを除く(コードの囲みを閉じさせない)"
else
    ng "エラーの中のバッククォートを除く(コードの囲みを閉じさせない)"
fi

# エラーが echo のオプションに見える1語でも、そのまま1行で載せる
reset_scenario
MERGE_MODE="fail"
MERGE_ERR="$WORK/merge-err.txt"
printf '%s\n' '-n' >"$MERGE_ERR"
run
expect_result "gh のエラーが -n の1語でも failed" failed
if [ "$(grep -cx -- '-n' "$WORK/last-post.md")" -eq 1 ] && [ "$(grep -cx '```' "$WORK/last-post.md")" -eq 2 ]; then
    ok "エラーが -n の1語でも、コードの囲みの中に1行で載せる"
else
    ng "エラーが -n の1語でも、コードの囲みの中に1行で載せる"
fi

# head が変わったかを確かめられないときは、head-moved に倒さない
reset_scenario
MERGE_MODE="fail"
VIEW_MODE="fail"
run
expect_error "予約が失敗し head を照会できなければ終了コード 1"

reset_scenario
MERGE_MODE="fail"
VIEW_MODE="invalid"
run
expect_error "予約が失敗し head の応答の形が違えば終了コード 1"
expect_posts "head を確かめられないときは知らせない" 0

# head の照会が成功して何も返さない・JSON を2つ返すときも、head-moved に倒さない
check_bad_view() {
    local name="$1" mode="$2"
    reset_scenario
    MERGE_MODE="fail"
    VIEW_MODE="$mode"
    run
    expect_error "予約が失敗し head の応答が${name}なら終了コード 1"
    expect_posts "head の応答が${name}なら知らせない" 0
}
check_bad_view "空(0バイト)" empty
check_bad_view "改行だけ" newline
check_bad_view "JSON 2件" double

# 2度目の実行(1度目の知らせが一覧にある)では、知らせを増やさない(5.3)
reset_scenario
MERGE_MODE="fail"
run
add_posted_comment "2026-10-01T00:00:00Z"
run
expect_result "failed の知らせが既にあっても failed" failed
expect_posts "同じコミットの failed の知らせを増やさない" 0

# 目印はコミットごと。別のコミットの知らせしか無ければ、いまのコミットの知らせを付ける
reset_scenario
MERGE_MODE="fail"
add_comment "$BOT" "2026-10-01T00:00:00Z" "前のコミットの知らせ $(marker failed "$NEW_SHA")"
run
expect_result "別のコミットの failed の知らせしか無ければ failed" failed
expect_posts "別のコミットの failed の知らせしか無ければ、知らせを付ける" 1

# 知らせを付けられないときは終了コード 1
reset_scenario
MERGE_MODE="fail"
POST_MODE="fail"
run
expect_error "failed の知らせを付けられなければ終了コード 1"

reset_scenario
MERGE_MODE="fail"
LIST_MODE="fail"
run
expect_error "failed の知らせの前にコメントの一覧を読めなければ終了コード 1"
expect_posts "コメントの一覧を読めなければ知らせを付けない" 0

# =====================================================================
# 同じコミットで3回を超えて外れたら、付け直しを止めて知らせる(4.3, 4.4, 5.3)
# =====================================================================
COMMIT='{"__typename":"PullRequestCommit"}'
OFF='{"__typename":"AutoMergeDisabledEvent","reasonCode":"repository_rule_violation"}'
OFF_MANUAL='{"__typename":"AutoMergeDisabledEvent","reasonCode":"manually_disabled"}'

reset_scenario
P_TIMELINE="[${COMMIT},${OFF},${OFF_MANUAL},${OFF}]"
run
expect_result "最後のコミットより後に3回外れていても予約する" reserved
expect_reserved_call "3回外れたあとの予約も同じ引数とトークンで行う"
expect_posts "3回では知らせない" 0

# 理由を問わず数える(手動とルール違反が混ざっていても4回)
reset_scenario
P_TIMELINE="[${COMMIT},${OFF},${OFF_MANUAL},${OFF},${OFF_MANUAL}]"
run
expect_result "最後のコミットより後に4回外れていたら stopped" stopped
expect_merges "stopped では予約の呼び出しが無い" 0
expect_posts "stopped の知らせを1回付ける" 1
expect_post_has "stopped の知らせに目印がある" "$(marker stopped)"
expect_post_mentions_owner "stopped の知らせは所有者へのメンションで始まる"
expect_post_has "stopped の知らせに PR 番号がある" "PR #7"
expect_post_has "stopped の知らせに外れた回数がある" "4回"
expect_post_has "stopped の知らせに付け直しを止めたことがある" "付け直しを止めました"
expect_post_has "stopped の知らせにしてほしいこと(PR の状態を確かめる)がある" "PR の状態"
expect_post_has "stopped の知らせに新しいコミットで再開することがある" "新しいコミット"

# 2度目の実行(定期の見直しなど)でも付け直さず、知らせも増やさない
add_posted_comment "2026-10-01T00:00:00Z"
run
expect_result "stopped の知らせが既にあっても stopped" stopped
expect_merges "2度目の実行でも予約の呼び出しが無い" 0
expect_posts "同じコミットの stopped の知らせを増やさない" 0

# 最後のコミットより前の外れは数えない。新しいコミットが積まれると 0 に戻る(4.4)
reset_scenario
P_TIMELINE="[${COMMIT},${OFF},${OFF},${OFF},${OFF},${OFF},${COMMIT}]"
run
expect_result "外れた5回がすべて最後のコミットより前なら予約する" reserved
expect_posts "最後のコミットより前の外れでは知らせない" 0

reset_scenario
P_TIMELINE="[${COMMIT},${OFF},${OFF},${OFF},${OFF},${COMMIT},${OFF},${OFF},${OFF}]"
run
expect_result "最後のコミットより前に4回、後に3回なら予約する" reserved

reset_scenario
P_TIMELINE="[${COMMIT},${OFF},${COMMIT},${OFF},${OFF},${OFF},${OFF}]"
run
expect_result "最後のコミットより前に1回、後に4回なら stopped" stopped
expect_merges "最後のコミットより後の4回で stopped なら予約の呼び出しが無い" 0

# 予約済みなら、外れた回数が多くても触らず、止めた知らせも付けない
reset_scenario
P_ARMED='{"enabledAt":"2026-10-01T00:00:00Z"}'
P_TIMELINE="[${COMMIT},${OFF},${OFF},${OFF},${OFF}]"
run
expect_result "4回外れていても、いま予約済みなら already" already
expect_posts "いま予約済みなら stopped の知らせを付けない" 0

# 対象外の PR は、外れた回数が多くても知らせない
reset_scenario
P_DRAFT="true"
P_TIMELINE="[${COMMIT},${OFF},${OFF},${OFF},${OFF}]"
run
expect_result "4回外れていても、下書きなら skipped" skipped
expect_posts "対象外の PR には知らせを付けない" 0

reset_scenario
P_TIMELINE="[${COMMIT},${OFF},${OFF},${OFF},${OFF}]"
POST_MODE="fail"
run
expect_error "stopped の知らせを付けられなければ終了コード 1"
expect_merges "stopped の知らせを付けられないときも予約の呼び出しが無い" 0

# =====================================================================
# 知らせを出した PR に予約が付いたら、resolved を1回付ける(5.4)
# =====================================================================
ARMED_NOW='{"enabledAt":"2026-10-01T03:00:00Z"}'

# 最新が failed で、予約できた
reset_scenario
add_comment "$BOT" "2026-10-01T00:00:00Z" "予約を付けられませんでした $(marker failed)"
run
expect_result "failed の知らせのあとに予約できたら reserved" reserved
expect_posts "failed の知らせのあとに予約できたら resolved を1回付ける" 1
expect_post_has "resolved のコメントに目印がある" "$(marker resolved)"
expect_post_has "resolved のコメントに予約が付いたことがある" "予約が付きました"
expect_post_has "resolved のコメントに対応が要らないことがある" "対応は要りません"
if grep -q '@' "$WORK/last-post.md"; then
    ng "resolved のコメントにメンションが無い"
else
    ok "resolved のコメントにメンションが無い"
fi

# 2度目の実行(予約済み。resolved が一覧にある)では増やさない
add_posted_comment "2026-10-01T01:00:00Z"
P_ARMED="$ARMED_NOW"
run
expect_result "resolved を付けたあとの実行は already" already
expect_posts "resolved を増やさない" 0

# 最新が stopped で、予約が付いていた(所有者が手で予約したなど)
reset_scenario
P_ARMED="$ARMED_NOW"
P_TIMELINE="[${COMMIT},${OFF},${OFF},${OFF},${OFF}]"
add_comment "$BOT" "2026-10-01T00:00:00Z" "付け直しを止めました $(marker stopped)"
run
expect_result "stopped の知らせのあとに予約が付いていたら already" already
expect_merges "stopped の知らせのあとに予約が付いていても予約の呼び出しが無い" 0
expect_posts "stopped の知らせのあとに予約が付いていたら resolved を1回付ける" 1
expect_post_has "already のときの resolved にも目印がある" "$(marker resolved)"

# 最新が failed で、予約が付いていた
reset_scenario
P_ARMED="$ARMED_NOW"
add_comment "$BOT" "2026-10-01T00:00:00Z" "予約を付けられませんでした $(marker failed)"
run
expect_result "failed の知らせのあとに予約が付いていたら already" already
expect_posts "failed の知らせのあとに予約が付いていたら resolved を1回付ける" 1

# 最新が stopped で、新しいコミットのあとに予約できた(知らせは前のコミットのもの)
reset_scenario
add_comment "$BOT" "2026-10-01T00:00:00Z" "付け直しを止めました $(marker stopped "$NEW_SHA")"
run
expect_result "前のコミットの stopped の知らせのあとに予約できたら reserved" reserved
expect_posts "前のコミットの stopped の知らせのあとに予約できたら resolved を1回付ける" 1
expect_post_has "resolved の目印の head は、予約したコミットである" "$(marker resolved)"

# 最新が resolved なら付けない(一覧の並びではなく作成日時で新旧を比べる)
reset_scenario
add_comment "$BOT" "2026-10-01T02:00:00Z" "予約が付きました $(marker resolved "$NEW_SHA")"
add_comment "$BOT" "2026-10-01T00:00:00Z" "予約を付けられませんでした $(marker failed "$NEW_SHA")"
run
expect_result "最新の知らせが resolved の PR に予約できたら reserved" reserved
expect_posts "最新の知らせが resolved なら、予約できても resolved を付けない" 0

P_ARMED="$ARMED_NOW"
run
expect_result "最新の知らせが resolved の PR が予約済みなら already" already
expect_posts "最新の知らせが resolved なら、予約済みでも resolved を付けない" 0

# resolved のあとに、新しい知らせが出ていたら未解消
reset_scenario
add_comment "$BOT" "2026-10-01T00:00:00Z" "予約を付けられませんでした $(marker failed "$NEW_SHA")"
add_comment "$BOT" "2026-10-01T01:00:00Z" "予約が付きました $(marker resolved "$NEW_SHA")"
add_comment "$BOT" "2026-10-01T02:00:00Z" "予約を付けられませんでした $(marker failed)"
run
expect_result "resolved のあとに failed の知らせが出た PR に予約できたら reserved" reserved
expect_posts "resolved のあとに failed の知らせが出ていたら resolved を付ける" 1

# 知らせの作成者でない人が書いた目印は、知らせとして数えない
reset_scenario
add_comment "someone-else" "2026-10-01T00:00:00Z" "$(marker failed)"
run
expect_result "他人が目印を書いた PR に予約できたら reserved" reserved
expect_posts "他人が書いた目印では resolved を付けない" 0

# resolved を付けられない・未解消かを読めないときは終了コード 1
reset_scenario
add_comment "$BOT" "2026-10-01T00:00:00Z" "予約を付けられませんでした $(marker failed)"
POST_MODE="fail"
run
expect_error "resolved を付けられなければ終了コード 1"

reset_scenario
P_ARMED="$ARMED_NOW"
LIST_MODE="fail"
run
expect_error "予約済みの PR の知らせを読めなければ終了コード 1"
expect_posts "知らせを読めなければコメントを付けない" 0

# =====================================================================
# 照会できない・応答の形が違うときは、何も書き込まずに終了コード 1
# =====================================================================
reset_scenario
FAIL_QUERY=1
run
expect_error "PR を照会できなければ終了コード 1"
expect_merges "PR を照会できなければ予約の呼び出しが無い" 0

check_bad_shape() {
    local name="$1"
    run
    expect_error "${name}なら終了コード 1"
    expect_merges "${name}なら予約の呼び出しが無い" 0
}

reset_scenario
RAW_PR='<html><body>oops</body></html>'
check_bad_shape "応答が JSON でない"

reset_scenario
RAW_PR='{"data":{"repository":{"pullRequest":null}}}'
check_bad_shape "PR が見つからない(pullRequest が null)"

reset_scenario
RAW_PR='{"data":{"repository":null}}'
check_bad_shape "リポジトリが見つからない(repository が null)"

reset_scenario
P_STATE="UNKNOWN"
check_bad_shape "state が想定に無い値"

reset_scenario
P_DRAFT='"false"'
check_bad_shape "isDraft が真偽値でない"

reset_scenario
P_CROSS='null'
check_bad_shape "isCrossRepository が真偽値でない"

reset_scenario
P_HEAD="not-a-sha"
check_bad_shape "headRefOid がコミットの形でない"

reset_scenario
P_AUTHOR='"DogisRiki-bot"'
check_bad_shape "author がオブジェクトでない"

reset_scenario
P_ARMED='"yes"'
check_bad_shape "autoMergeRequest がオブジェクトでも null でもない"

reset_scenario
P_TIMELINE='"none"'
check_bad_shape "timelineItems の nodes が配列でない"

# 項目そのものが欠けている応答を「予約が無い」「ラベルが無い」と読まない
reset_scenario
write_pr
RAW_PR=$(jq -c 'del(.data.repository.pullRequest.autoMergeRequest)' "$WORK/pr.json")
check_bad_shape "autoMergeRequest の項目が無い"

reset_scenario
write_pr
RAW_PR=$(jq -c 'del(.data.repository.pullRequest.labels)' "$WORK/pr.json")
check_bad_shape "labels の項目が無い"

reset_scenario
write_pr
RAW_PR=$(jq -c 'del(.data.repository.pullRequest.author)' "$WORK/pr.json")
check_bad_shape "author の項目が無い"

# 照会が成功して何も返さない応答を「開いていない PR」と読まない
reset_scenario
: >"$WORK/raw-empty.txt"
RAW_PR_FILE="$WORK/raw-empty.txt"
check_bad_shape "照会の応答が空(0バイト)"

reset_scenario
printf '\n' >"$WORK/raw-newline.txt"
RAW_PR_FILE="$WORK/raw-newline.txt"
check_bad_shape "照会の応答が改行だけ"

# JSON が2つ並んだ応答は、どちらも正しい形でも読まない
reset_scenario
write_pr
{
    jq -c . "$WORK/pr.json"
    jq -c . "$WORK/pr.json"
} >"$WORK/raw-double.txt" || exit 1
RAW_PR_FILE="$WORK/raw-double.txt"
check_bad_shape "照会の応答が JSON 2件"

# =====================================================================
# 見直し(--sweep): 開いている PR を一覧し、1件ずつ同じ判定を行う(4.2)
# =====================================================================
# 場面の作り方: reset_sweep のあと、P_* で PR の状態を決めて sweep_pr <番号> で
# 一覧に足す(足すたびに P_* は既定に戻る)。run_sweep で実行する。
reset_sweep() {
    reset_scenario
    rm -rf "$WORK/sweep"
    mkdir -p "$WORK/sweep"
    echo '[]' >"$WORK/sweep/list.json"
    SWEEP_LIST_MODE="ok"
    SWEEP_TIMEOUT=""
}

# 使い方: sweep_pr <番号> [query-fail|hang]
#   query-fail: 一覧にはあるが、その PR の照会が失敗する
#   hang: その PR の照会が応答しない
sweep_pr() {
    jq --argjson n "$1" '. + [{number: $n}]' "$WORK/sweep/list.json" >"$WORK/sweep/list.tmp" || exit 1
    mv "$WORK/sweep/list.tmp" "$WORK/sweep/list.json" || exit 1
    case "${2:-}" in
    query-fail) ;;
    hang) : >"$WORK/sweep/hang-$1" ;;
    *)
        write_pr
        cp "$WORK/pr.json" "$WORK/sweep/pr-$1.json" || exit 1
        ;;
    esac
    reset_scenario
}

run_sweep() {
    : >"$WORK/calls.log"
    : >"$WORK/last-post.md"
    PATH="$WORK/bin:$PATH" \
        STUB_CALLS="$WORK/calls.log" STUB_UNEXPECTED="$WORK/unexpected.log" \
        STUB_SWEEP_DIR="$WORK/sweep" STUB_SWEEP_LIST_MODE="$SWEEP_LIST_MODE" \
        STUB_MERGE_MODE="ok" STUB_VIEW_MODE="ok" STUB_CURRENT_HEAD="$HEAD_SHA" \
        STUB_LIST_MODE="ok" STUB_POST_MODE="ok" STUB_LAST_POST="$WORK/last-post.md" \
        GITHUB_REPOSITORY="owner/repo" GITHUB_REPOSITORY_OWNER="owner-name" \
        GH_TOKEN="$QUERY_TOKEN" RESERVE_TOKEN="$RESERVE_TOKEN_VALUE" \
        SWEEP_PR_TIMEOUT_SECONDS="$SWEEP_TIMEOUT" \
        bash "$SCRIPT" --sweep >"$WORK/out.txt" 2>"$WORK/err.txt"
    RC=$?
    cat "$WORK/calls.log" >>"$WORK/sweep-all-calls.log"
    MERGES=$(grep -c "^[^${TAB}]*${TAB}pr merge " "$WORK/calls.log")
    POSTS=$(grep -c "^[^${TAB}]*${TAB}api -X POST " "$WORK/calls.log")
}

# 終了コードが期待どおりで、標準出力が期待の行だけ(PR ごとに pr=<番号> result=<...>)
expect_sweep() {
    local name="$1" want_rc="$2" want_out="$3"
    if [ "$RC" -ne "$want_rc" ]; then
        ng "$name (終了コード $want_rc のはずが $RC)"
        return
    fi
    if [ "$(cat "$WORK/out.txt")" != "$want_out" ]; then
        ng "$name (標準出力が期待と違う)"
        return
    fi
    ok "$name"
}

# 予約の呼び出しが、並べた番号の PR にだけ、この順で、予約用のトークンと決まった引数で
# 1回ずつ行われている
expect_sweep_merges() {
    local name="$1" n
    shift
    for n in "$@"; do
        echo "${RESERVE_TOKEN_VALUE}${TAB}pr merge --auto --squash --match-head-commit ${HEAD_SHA} ${n} --repo owner/repo"
    done >"$WORK/want-merges.txt"
    if grep "^[^${TAB}]*${TAB}pr merge " "$WORK/calls.log" | cmp -s - "$WORK/want-merges.txt"; then
        ok "$name"
    else
        ng "$name"
    fi
}

# 呼び出しが一覧の1回だけ(標準のトークンで、開いている main 向けの PR を最大100件)
SWEEP_LIST_CALL="${QUERY_TOKEN}${TAB}pr list --repo owner/repo --state open --base main --limit 100 --json number"
expect_only_list_call() {
    local name="$1"
    if [ "$(cat "$WORK/calls.log")" = "$SWEEP_LIST_CALL" ]; then
        ok "$name"
    else
        ng "$name"
    fi
}

# 一覧の中の対象の PR だけに予約する。対象外と予約済みには触らない
reset_sweep
sweep_pr 11
P_DRAFT="true"
sweep_pr 12
P_AUTHOR='{"login":"dependabot"}'
sweep_pr 13
P_HEADREF="canary/escape-hatch-20261001"
sweep_pr 14
P_ARMED='{"enabledAt":"2026-10-01T00:00:00Z"}'
sweep_pr 15
P_AUTHOR='{"login":"owner-name"}'
sweep_pr 16
run_sweep
expect_sweep "見直しは PR ごとに結果を1行ずつ出し、全て終われば終了コード 0" 0 "pr=11 result=reserved
pr=12 result=skipped
pr=13 result=skipped
pr=14 result=skipped
pr=15 result=already
pr=16 result=reserved"
expect_sweep_merges "見直しは対象の PR(11 と 16)だけに予約し、下書き・Dependabot・カナリア・予約済みには予約しない" 11 16
expect_posts "見直しで知らせの無い PR にコメントを付けない" 0
if [ "$(grep -c "${TAB}pr list " "$WORK/calls.log")" -eq 1 ] && [ "$(head -n 1 "$WORK/calls.log")" = "$SWEEP_LIST_CALL" ]; then
    ok "一覧は最初に1回だけ、標準のトークンで、開いている main 向けの PR を最大100件取る"
else
    ng "一覧は最初に1回だけ、標準のトークンで、開いている main 向けの PR を最大100件取る"
fi
if [ "$(grep -c "^${QUERY_TOKEN}${TAB}api graphql " "$WORK/calls.log")" -eq 6 ]; then
    ok "一覧の全ての PR を1件ずつ照会する(一覧の段階で対象外を除かない)"
else
    ng "一覧の全ての PR を1件ずつ照会する(一覧の段階で対象外を除かない)"
fi

# 1件の照会が失敗しても残りを処理し、終了コード 1
reset_sweep
sweep_pr 11
sweep_pr 12 query-fail
sweep_pr 16
run_sweep
expect_sweep "1件の照会が失敗しても残りを処理し、終了コード 1" 1 "pr=11 result=reserved
pr=12 result=error
pr=16 result=reserved"
expect_sweep_merges "照会が失敗した PR の前後の PR(11 と 16)には予約する" 11 16
if grep -q 'PR #12' "$WORK/err.txt"; then
    ok "失敗した PR の番号を標準エラーに出す"
else
    ng "失敗した PR の番号を標準エラーに出す"
fi

# 1件が時間の上限を超えたら打ち切り、残りを処理し、終了コード 1
reset_sweep
sweep_pr 11
sweep_pr 12 hang
sweep_pr 16
SWEEP_TIMEOUT=1
run_sweep
expect_sweep "1件が時間の上限を超えても残りを処理し、終了コード 1" 1 "pr=11 result=reserved
pr=12 result=timeout
pr=16 result=reserved"
expect_sweep_merges "時間切れの PR の前後の PR(11 と 16)には予約する" 11 16

# 一覧を取れないときは、何もせず終了コード 1
reset_sweep
sweep_pr 11
SWEEP_LIST_MODE="fail"
run_sweep
expect_error "一覧を取れなければ終了コード 1"
expect_merges "一覧を取れなければ予約の呼び出しが無い" 0
expect_only_list_call "一覧を取れなければ、一覧のほかの呼び出しが無い"

# 一覧の応答の形が違うときも、PR が無いとは読まず、何もせず終了コード 1
check_bad_list() {
    local name="$1" raw="$2"
    reset_sweep
    sweep_pr 11
    printf '%s\n' "$raw" >"$WORK/sweep/list.json"
    run_sweep
    expect_error "${name}なら終了コード 1"
    expect_only_list_call "${name}なら、一覧のほかの呼び出しが無い"
}
check_bad_list "一覧の応答が JSON でない" '<html><body>oops</body></html>'
check_bad_list "一覧の応答が配列でない" '{"message":"Bad credentials"}'
check_bad_list "一覧の番号が文字列" '[{"number":"11"}]'
check_bad_list "一覧の番号が 0" '[{"number":11},{"number":0}]'
check_bad_list "一覧の要素に番号が無い" '[{"number":11},{"title":"x"}]'

# 一覧が成功して何も返さない応答を「PR が無い」と読まない(本物の「無い」は [])
check_bad_list "一覧の応答が改行だけ" ''
reset_sweep
sweep_pr 11
: >"$WORK/sweep/list.json"
run_sweep
expect_error "一覧の応答が空(0バイト)なら終了コード 1"
expect_only_list_call "一覧の応答が空(0バイト)なら、一覧のほかの呼び出しが無い"

# JSON が2つ並んだ一覧は、どちらも正しい形でも読まない
check_bad_list "一覧の応答が JSON 2件(番号の配列が2つ)" '[{"number":11}]
[{"number":16}]'
check_bad_list "一覧の応答が JSON 2件(空の配列が2つ)" '[]
[]'

# 1件の照会が成功して何も返さないときは、その PR を skipped と数えず error にする
check_sweep_empty_query() {
    local name="$1" content="$2"
    reset_sweep
    sweep_pr 11
    sweep_pr 12
    printf '%s' "$content" >"$WORK/sweep/pr-12.json"
    sweep_pr 16
    run_sweep
    expect_sweep "1件の照会の応答が${name}でも残りを処理し、終了コード 1" 1 "pr=11 result=reserved
pr=12 result=error
pr=16 result=reserved"
    expect_sweep_merges "照会の応答が${name}の PR の前後の PR(11 と 16)には予約する" 11 16
}
check_sweep_empty_query "空(0バイト)" ''
check_sweep_empty_query "改行だけ" '
'

# 一覧が上限の100件に達したら、見直していない PR がありうることを警告する
reset_sweep
P_DRAFT="true"
write_pr
jq -n '[range(101; 201) | {number: .}]' >"$WORK/sweep/list.json" || exit 1
for n in $(seq 101 200); do
    cp "$WORK/pr.json" "$WORK/sweep/pr-$n.json" || exit 1
done
reset_scenario
run_sweep
if [ "$RC" -eq 0 ] && [ "$(grep -c '^pr=[0-9]* result=skipped$' "$WORK/out.txt")" -eq 100 ] &&
    [ "$(wc -l <"$WORK/out.txt" | tr -d ' ')" -eq 100 ]; then
    ok "一覧が100件でも全ての PR を見直し、終了コード 0"
else
    ng "一覧が100件でも全ての PR を見直し、終了コード 0"
fi
if grep -q '^::warning::.*上限(100 件)' "$WORK/err.txt"; then
    ok "一覧が上限の100件に達したら ::warning:: を出す"
else
    ng "一覧が上限の100件に達したら ::warning:: を出す"
fi

reset_sweep
P_DRAFT="true"
sweep_pr 11
run_sweep
if [ "$RC" -eq 0 ] && ! grep -q '::warning::' "$WORK/err.txt"; then
    ok "一覧が上限に達していなければ ::warning:: を出さない"
else
    ng "一覧が上限に達していなければ ::warning:: を出さない"
fi

# 一覧が空なら、何もせず終了コード 0
reset_sweep
run_sweep
expect_sweep "一覧が空なら終了コード 0 で、標準出力に何も出さない" 0 ""
expect_only_list_call "一覧が空なら、一覧のほかの呼び出しが無い"

# 時間の上限の指定が正の整数でなければ、gh を呼ばずに終了コード 1
reset_sweep
sweep_pr 11
SWEEP_TIMEOUT="soon"
run_sweep
expect_error "時間の上限の指定が正の整数でなければ終了コード 1"
expect_no_calls "時間の上限の指定が正の整数でなければ gh を呼ばない"

# =====================================================================
# 使い方の誤り(gh を1度も呼ばない)
# =====================================================================
check_invocation() {
    local name="$1" omit="$2" repo="$3"
    shift 3
    reset_scenario
    write_pr
    : >"$WORK/calls.log"
    local envs=() var
    for var in "GITHUB_REPOSITORY=${repo}" GITHUB_REPOSITORY_OWNER=owner-name \
        "GH_TOKEN=${QUERY_TOKEN}" "RESERVE_TOKEN=${RESERVE_TOKEN_VALUE}"; do
        [ "${var%%=*}" = "$omit" ] || envs+=("$var")
    done
    env -u GITHUB_REPOSITORY -u GITHUB_REPOSITORY_OWNER -u GH_TOKEN -u RESERVE_TOKEN "${envs[@]}" \
        PATH="$WORK/bin:$PATH" \
        STUB_CALLS="$WORK/calls.log" STUB_UNEXPECTED="$WORK/unexpected.log" \
        STUB_PR="$WORK/pr.json" STUB_MERGE_MODE=ok STUB_VIEW_MODE=ok STUB_CURRENT_HEAD="$HEAD_SHA" \
        STUB_COMMENTS="$WORK/comments.json" STUB_LIST_MODE=ok STUB_POST_MODE=ok STUB_LAST_POST="$WORK/last-post.md" \
        bash "$SCRIPT" "$@" >"$WORK/out.txt" 2>"$WORK/err.txt"
    RC=$?
    cat "$WORK/calls.log" >>"$WORK/all-calls.log"
    expect_error "${name}なら終了コード 1"
    expect_no_calls "${name}なら gh を呼ばない"
}
check_invocation "PR番号が無い" "" owner/repo
check_invocation "PR番号が数字でない" "" owner/repo "7;rm"
check_invocation "PR番号が 0" "" owner/repo 0
check_invocation "引数が2つ以上" "" owner/repo 7 8
check_invocation "GH_TOKEN が無い" GH_TOKEN owner/repo 7
check_invocation "RESERVE_TOKEN が無い" RESERVE_TOKEN owner/repo 7
check_invocation "GITHUB_REPOSITORY が無い" GITHUB_REPOSITORY owner/repo 7
check_invocation "GITHUB_REPOSITORY_OWNER が無い" GITHUB_REPOSITORY_OWNER owner/repo 7
check_invocation "GITHUB_REPOSITORY が <所有者>/<名前> の形でない" "" "owner-repo" 7
check_invocation "--sweep に PR番号を付けた" "" owner/repo --sweep 7
check_invocation "知らない指定(--all)" "" owner/repo --all
check_invocation "--sweep で GH_TOKEN が無い" GH_TOKEN owner/repo --sweep
check_invocation "--sweep で RESERVE_TOKEN が無い" RESERVE_TOKEN owner/repo --sweep

# =====================================================================
# 全ての場面を通して: 迂回の指定を使わず、決まった呼び出しのほかを行わない
# =====================================================================
all_merges=$(grep "^[^${TAB}]*${TAB}pr merge " "$WORK/all-calls.log")
if [ -n "$all_merges" ]; then
    ok "予約の呼び出しが記録されている(下の確認が空振りしていない)"
else
    echo "FAIL: 予約の呼び出しが記録されている(下の確認が空振りしていない)"
    FAILED=1
fi
if printf '%s\n' "$all_merges" | grep -Fvx "$EXPECTED_MERGE" | grep -q .; then
    echo "FAIL: 予約の呼び出しは、全て予約用のトークンと決まった引数で行う(--admin などを含まない)"
    printf '%s\n' "$all_merges" | grep -Fvx "$EXPECTED_MERGE" | sed 's/^/  /'
    FAILED=1
else
    ok "予約の呼び出しは、全て予約用のトークンと決まった引数で行う(--admin などを含まない)"
fi
if grep -q -- '--admin' "$WORK/all-calls.log"; then
    echo "FAIL: どの呼び出しにも --admin が無い"
    FAILED=1
else
    ok "どの呼び出しにも --admin が無い"
fi
# 予約用のトークンを使うのは予約の操作だけ
if grep "^${RESERVE_TOKEN_VALUE}${TAB}" "$WORK/all-calls.log" | grep -qv "^${RESERVE_TOKEN_VALUE}${TAB}pr merge "; then
    echo "FAIL: 予約用のトークンを使うのは予約の操作だけ"
    FAILED=1
else
    ok "予約用のトークンを使うのは予約の操作だけ"
fi
# 見直しの場面でも同じ(PR 番号だけが違う)
sweep_merges=$(grep "^[^${TAB}]*${TAB}pr merge " "$WORK/sweep-all-calls.log")
if [ -n "$sweep_merges" ] &&
    ! printf '%s\n' "$sweep_merges" |
        grep -Evq "^${RESERVE_TOKEN_VALUE}${TAB}pr merge --auto --squash --match-head-commit ${HEAD_SHA} [1-9][0-9]* --repo owner/repo\$"; then
    ok "見直しの予約の呼び出しも、全て予約用のトークンと決まった引数で行う"
else
    echo "FAIL: 見直しの予約の呼び出しも、全て予約用のトークンと決まった引数で行う"
    FAILED=1
fi
if grep -v "${TAB}pr merge " "$WORK/sweep-all-calls.log" | grep -qv "^${QUERY_TOKEN}${TAB}"; then
    echo "FAIL: 見直しの一覧・照会・知らせの一覧は標準のトークンで行う"
    FAILED=1
else
    ok "見直しの一覧・照会・知らせの一覧は標準のトークンで行う"
fi
if grep -q -- '--admin' "$WORK/sweep-all-calls.log"; then
    echo "FAIL: 見直しのどの呼び出しにも --admin が無い"
    FAILED=1
else
    ok "見直しのどの呼び出しにも --admin が無い"
fi
if [ -s "$WORK/unexpected.log" ]; then
    echo "FAIL: 想定していない gh の呼び出しが無い"
    sed 's/^/  /' "$WORK/unexpected.log"
    FAILED=1
else
    ok "想定していない gh の呼び出しが無い(照会・予約・head の照会・知らせの一覧とコメントだけ)"
fi

if [ "$FAILED" -ne 0 ]; then
    echo "テストに失敗があります。"
    exit 1
fi
echo "全てのテストが通りました。"
