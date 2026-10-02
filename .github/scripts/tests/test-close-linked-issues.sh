#!/usr/bin/env bash
# =====================================================================
# close-linked-issues.sh の自動テスト(close-linked-issues と guardrails から実行)
#
# gh を PATH の先頭の偽物で置き換え、標準出力(issue=<番号> result=<...> の行)・
# 終了コード・GitHub への書き込みの呼び出しを確かめる。
# 見直しの入口(--sweep)は、現在時刻を NOW_EPOCH で固定し、対象の期間(マージが7日前から
# 5分前まで)の境界と、標準出力(pr=<PR番号> issue=<番号> result=<...> の行)を確かめる。
#   終了コード 0 = すべての Issue について判定と、必要な操作・知らせを終えた
#                  (Issue や親の Issue を閉じる操作・親の照会が失敗しても、知らせを付けられたら 0)
#   終了コード 1 = 照会できない、応答の形が想定と違う、記録または知らせを付けられない、使い方の誤り
#
# gh の偽物は実APIの形のJSONをそのまま返し、応答の解釈は本体に任せる
# (応答の形は 2026-10-01 に実物の GraphQL で確かめたもの。存在しない番号と PR の番号は、
#  どちらも errors に NOT_FOUND を持つ応答と終了コード 1 になる。Issue の子の数と親の番号は
#  2026-10-02 に #472 で確かめたもの。subIssuesSummary は子が無くても {"total":0,"completed":0} で
#  返り、親が無ければ parent は null になる。親のリポジトリ(parent.repository.nameWithOwner)は、同じ日に
#  #472 の repository { nameWithOwner } で欄の形を確かめた。このリポジトリに親を持つ Issue が無いため、
#  親の欄の中の形は GraphQL のスキーマ(parent は Issue 型)に合わせている)。
# 想定していない呼び出しは失敗させ、記録を残す。
#
# 外部への問い合わせを行わないため、実行にネットワークを必要としない。
# =====================================================================
set -uo pipefail

SCRIPT="$(cd "$(dirname "$0")/.." && pwd)/close-linked-issues.sh"
WORK=$(mktemp -d) || exit 1
[ -n "$WORK" ] && [ -d "$WORK" ] || exit 1
trap 'rm -rf "$WORK"' EXIT
FAILED=0

mkdir -p "$WORK/bin"

# --- gh の偽物 -------------------------------------------------------------------
# 呼び出しを $STUB_CALLS に1行ずつ記録する。
#   照会(GraphQL)は「graphql pr <番号>」「graphql issue <番号>」の形で記録する。
#   コメントの一覧の読み取り(REST)は「list comments <番号>」の形で記録する。
#   それ以外(書き込み)は引数をそのまま記録する(コメントの本文のファイル名は除く)。
#   知らせのコメント(REST の POST)は「api POST comments <番号>」の形で記録する。
#   マージ済み PR の一覧(見直し)は「pr list <検索条件>」の形で記録する。
#   PR の照会: STUB_PR_MODE(ok = $STUB_PR の中身 / fail = 失敗 / notfound = 番号が PR でない)
#              見直しの場面では PR ごとに応答を変える。$STUB_PRS/<番号>.json があればその中身、
#              <番号>.fail があれば失敗、<番号>.slow があれば応答を返さず30秒待つ(時間切れの場面)。
#              どれも無ければ、#7 だけを上の STUB_PR_MODE で扱う(ほかの番号は想定していない呼び出し)
#   マージ済み PR の一覧: $STUB_PR_LIST の中身(STUB_PR_LIST_MODE が fail なら失敗)。
#              検索条件では絞らず、ファイルの中身をそのまま返す(期間の判定は本体が行う)
#   Issue の照会: $STUB_ISSUES/<番号>.json があればその中身。
#                 $STUB_ISSUES/<番号>.fail があればその中身を出して失敗。
#                 どちらも無ければ「存在しない、または PR を指している」の応答で失敗。
#                 照会のクエリは $STUB_ISSUE_QUERY に保存する(最後の1件)
#   Issue のクローズ: STUB_FAIL_CLOSE の番号なら失敗。
#                     成功したら $STUB_ISSUES/<番号>.json の state を CLOSED にし、その Issue にこのリポジトリの親があれば、
#                     親の応答の閉じた子の数(subIssuesSummary.completed)を1つ増やす(実物の照会の結果に合わせる)
#   Issue へのコメント: 本文を $STUB_POSTED/comment_<番号>.md に保存(STUB_FAIL_COMMENT の番号なら失敗)
#   コメントの一覧: $STUB_COMMENTS/<番号>.json があればその中身、無ければ [](STUB_FAIL_LIST の番号なら失敗)。
#                   実物の REST の形(.user.login が github-actions[bot]、.created_at、.body)で置く
#   知らせのコメント: 本文を $STUB_POSTED/notice_<番号>.md に保存(STUB_FAIL_NOTICE の番号なら失敗)
#   終了コード 0 で中身の無い応答(0バイト、改行だけ)と、JSON が2つ並んだ応答の場面:
#     PR の照会・マージ済み PR の一覧・Issue の照会は、置いたファイルの中身をそのまま出して成功で終わる。
#     ファイルを空(または改行だけ、JSON を2つ)にすると、gh が成功したのに応答が想定の形でない場面になる
# 想定していない呼び出し(引数の形が違う、mutation を含む照会など)は $STUB_UNEXPECTED に記録して失敗する。
cat >"$WORK/bin/gh" <<'STUB'
#!/usr/bin/env bash
unexpected() {
    printf '%s ' "$@" | tr '\n' ' ' >>"${STUB_UNEXPECTED:?}"
    printf '\n' >>"$STUB_UNEXPECTED"
    echo "stub: unexpected call: $1 $2" >&2
    exit 1
}
not_found() {
    printf '{"data":{"repository":{"%s":null}},"errors":[{"type":"NOT_FOUND","path":["repository","%s"],"locations":[{"line":1,"column":86}],"message":"Could not resolve to %s with the number of %s."}]}' \
        "$1" "$1" "$2" "$3"
    echo "gh: Could not resolve to $2 with the number of $3." >&2
    exit 1
}
if [ "${1:-} ${2:-}" = "api graphql" ]; then
    [ $# -eq 10 ] || unexpected "$@"
    [ "$3 $5 $6 $7 $8 $9" = "-F -f owner=owner -f name=repo -f" ] || unexpected "$@"
    number="${4#number=}"
    query="${10#query=}"
    [ "$4" != "$number" ] && [ "${10}" != "$query" ] || unexpected "$@"
    [[ "$number" =~ ^[1-9][0-9]*$ ]] || unexpected "$@"
    case "$query" in
    *mutation*) unexpected "$@" ;;
    *"pullRequest(number:"*)
        printf 'graphql pr %s\n' "$number" >>"${STUB_CALLS:?}"
        if [ -f "${STUB_PRS:?}/${number}.json" ]; then
            cat "$STUB_PRS/${number}.json"
            exit 0
        elif [ -f "$STUB_PRS/${number}.fail" ]; then
            echo "gh: Server Error (HTTP 500)" >&2
            exit 1
        elif [ -f "$STUB_PRS/${number}.slow" ]; then
            sleep 30
            exit 1
        fi
        [ "$number" = "7" ] || unexpected "$@"
        case "${STUB_PR_MODE:-ok}" in
        fail)
            echo "gh: Server Error (HTTP 500)" >&2
            exit 1
            ;;
        notfound) not_found pullRequest "a PullRequest" "$number" ;;
        *) cat "${STUB_PR:?}" ;;
        esac
        ;;
    *"issue(number:"*)
        printf 'graphql issue %s\n' "$number" >>"${STUB_CALLS:?}"
        printf '%s\n' "$query" >"${STUB_ISSUE_QUERY:?}"
        if [ -f "${STUB_ISSUES:?}/${number}.json" ]; then
            cat "$STUB_ISSUES/${number}.json"
        elif [ -f "$STUB_ISSUES/${number}.fail" ]; then
            cat "$STUB_ISSUES/${number}.fail"
            echo "gh: Server Error (HTTP 500)" >&2
            exit 1
        else
            not_found issue "an Issue" "$number"
        fi
        ;;
    *) unexpected "$@" ;;
    esac
    exit 0
fi
case "$*" in
"pr list --repo owner/repo --state merged --base main --search merged:>="*" --json number,mergedAt --limit 200")
    [ $# -eq 14 ] && [[ "${10}" =~ ^merged:\>=[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || unexpected "$@"
    printf 'pr list %s\n' "${10}" >>"${STUB_CALLS:?}"
    if [ "${STUB_PR_LIST_MODE:-ok}" = "fail" ]; then
        echo "gh: Server Error (HTTP 500)" >&2
        exit 1
    fi
    cat "${STUB_PR_LIST:?}"
    ;;
"api --paginate repos/owner/repo/issues/"*"/comments")
    number="${3#repos/owner/repo/issues/}"
    number="${number%/comments}"
    [ $# -eq 3 ] && [[ "$number" =~ ^[1-9][0-9]*$ ]] || unexpected "$@"
    printf 'list comments %s\n' "$number" >>"${STUB_CALLS:?}"
    if [ "${STUB_FAIL_LIST:-}" = "$number" ]; then
        echo "gh: Server Error (HTTP 500)" >&2
        exit 1
    fi
    if [ -f "${STUB_COMMENTS:?}/${number}.json" ]; then
        cat "$STUB_COMMENTS/${number}.json"
    else
        printf '[]'
    fi
    ;;
"api -X POST repos/owner/repo/issues/"*"/comments -F body=@"*)
    number="${4#repos/owner/repo/issues/}"
    number="${number%/comments}"
    [ $# -eq 6 ] && [[ "$number" =~ ^[1-9][0-9]*$ ]] && [ -f "${6#body=@}" ] || unexpected "$@"
    printf 'api POST comments %s\n' "$number" >>"${STUB_CALLS:?}"
    if [ "${STUB_FAIL_NOTICE:-}" = "$number" ]; then
        echo "gh: Forbidden (HTTP 403)" >&2
        exit 1
    fi
    cp "${6#body=@}" "${STUB_POSTED:?}/notice_${number}.md" || exit 1
    printf '{"id":1}'
    ;;
"issue close "*" --repo owner/repo")
    [ $# -eq 5 ] && [[ "$3" =~ ^[1-9][0-9]*$ ]] || unexpected "$@"
    printf '%s\n' "$*" >>"${STUB_CALLS:?}"
    if [ "${STUB_FAIL_CLOSE:-}" = "$3" ]; then
        echo "gh: Resource not accessible by integration (HTTP 403)" >&2
        exit 1
    fi
    # 実物と同じく、閉じた Issue のその後の照会は CLOSED を返し、親の閉じた子の数は1つ増える
    issue_file="${STUB_ISSUES:?}/$3.json"
    if [ -f "$issue_file" ]; then
        parent=$(jq -r '.data.repository.issue.parent
            | if . != null and (.repository.nameWithOwner | ascii_downcase) == "owner/repo" then .number else empty end' "$issue_file") &&
            jq '.data.repository.issue.state = "CLOSED"' "$issue_file" >"$issue_file.tmp" &&
            mv "$issue_file.tmp" "$issue_file" || unexpected "$@"
        parent_file="$STUB_ISSUES/${parent}.json"
        if [ -n "$parent" ] && [ -f "$parent_file" ]; then
            jq '.data.repository.issue.subIssuesSummary.completed += 1' "$parent_file" >"$parent_file.tmp" &&
                mv "$parent_file.tmp" "$parent_file" || unexpected "$@"
        fi
    fi
    echo "✓ Closed issue owner/repo#$3" >&2
    ;;
"issue comment "*" --repo owner/repo --body-file "*)
    [ $# -eq 7 ] && [[ "$3" =~ ^[1-9][0-9]*$ ]] && [ -f "$7" ] || unexpected "$@"
    printf 'issue comment %s --repo owner/repo --body-file\n' "$3" >>"${STUB_CALLS:?}"
    if [ "${STUB_FAIL_COMMENT:-}" = "$3" ]; then
        echo "gh: Forbidden (HTTP 403)" >&2
        exit 1
    fi
    cp "$7" "${STUB_POSTED:?}/comment_$3.md" || exit 1
    echo "https://github.com/owner/repo/issues/$3#issuecomment-1"
    ;;
*) unexpected "$@" ;;
esac
STUB
chmod +x "$WORK/bin/gh"
: >"$WORK/unexpected.log"
: >"$WORK/all-calls.log"
: >"$WORK/all-out.log"

# --- 応答の材料 -------------------------------------------------------------------
MERGED_AT="2026-09-30T08:00:00Z"
BEFORE_MERGE="2026-09-30T07:59:59Z"
AFTER_MERGE="2026-09-30T08:00:30Z"

# 使い方: pr_json <merged: true|false> <mergedAt または null> <base> <本文> [<保存先>]
# 保存先を省くと、#7 の応答($WORK/pr.json)にする。
pr_json() {
    jq -n --argjson merged "$1" --arg at "$2" --arg base "$3" --arg body "$4" '
        {data: {repository: {pullRequest: {
            merged: $merged,
            mergedAt: (if $at == "null" then null else $at end),
            baseRefName: $base,
            body: $body}}}}' >"${5:-$WORK/pr.json}"
}

# 使い方: issue <番号> <OPEN|CLOSED> [<閉じた日時> ...]
# 子が0件で親の無い Issue にする(子と親は family で足す)。
issue() {
    local n="$1" state="$2"
    shift 2
    printf '%s\n' "$@" | jq -R -s --arg state "$state" '
        {data: {repository: {issue: {
            state: $state,
            timelineItems: {nodes: (split("\n") | map(select(length > 0) | {createdAt: .}))},
            subIssuesSummary: {total: 0, completed: 0},
            parent: null}}}}' \
        >"$WORK/issues/${n}.json"
}

# 使い方: family <番号> <親の番号、親が無ければ -> <子の数> <閉じた子の数> [<親のリポジトリ>]
# issue で置いた Issue の応答に、親の番号と子の数を書き込む。
# 親のリポジトリを省くと、このリポジトリ(owner/repo)にする。
family() {
    local file="$WORK/issues/$1.json"
    jq --arg parent "$2" --argjson total "$3" --argjson completed "$4" --arg repo "${5:-owner/repo}" '
        .data.repository.issue += {
            subIssuesSummary: {total: $total, completed: $completed},
            parent: (if $parent == "-" then null
                     else {number: ($parent | tonumber), repository: {nameWithOwner: $repo}} end)}' \
        "$file" >"$file.tmp" && mv "$file.tmp" "$file"
}

# 使い方: comments <番号> <作成者> <本文のファイル>
# 番号の Issue のコメントの一覧を、そのファイルの本文のコメント1件にする(REST の応答の形)。
comments() {
    jq -n --arg login "$2" --rawfile body "$3" '
        [{id: 1, user: {login: $login}, created_at: "2026-09-30T08:02:00Z", body: $body}]' \
        >"$WORK/comments/$1.json"
}

# 使い方: keep_notice <番号> [<作成者>]
# 直前の実行が付けた知らせを、コメントの一覧に戻す(2度目の実行の準備)。
# 作成者を省くと、仕組み(github-actions[bot])が書いたコメントとして戻す。
keep_notice() {
    cp "$WORK/posted/notice_$1.md" "$WORK/kept_$1.md" || return 1
    comments "$1" "${2:-github-actions[bot]}" "$WORK/kept_$1.md"
}

# 各場面の前に呼び、偽物の振る舞いを既定に戻す
reset_scenario() {
    rm -rf "$WORK/issues" "$WORK/comments" "$WORK/prs"
    mkdir -p "$WORK/issues" "$WORK/comments" "$WORK/prs"
    pr_json true "$MERGED_AT" main "Closes #21"
    printf '[]' >"$WORK/pr-list.json"
    PR_MODE="ok"
    PR_LIST_MODE="ok"
    FAIL_CLOSE=""
    FAIL_COMMENT=""
    FAIL_LIST=""
    FAIL_NOTICE=""
}

run() {
    : >"$WORK/calls.log"
    : >"$WORK/issue-query.txt"
    rm -rf "$WORK/posted"
    mkdir -p "$WORK/posted"
    PATH="$WORK/bin:$PATH" \
        STUB_CALLS="$WORK/calls.log" STUB_UNEXPECTED="$WORK/unexpected.log" \
        STUB_PR="$WORK/pr.json" STUB_ISSUES="$WORK/issues" STUB_ISSUE_QUERY="$WORK/issue-query.txt" \
        STUB_POSTED="$WORK/posted" \
        STUB_COMMENTS="$WORK/comments" STUB_FAIL_LIST="$FAIL_LIST" STUB_FAIL_NOTICE="$FAIL_NOTICE" \
        STUB_PR_MODE="$PR_MODE" STUB_FAIL_CLOSE="$FAIL_CLOSE" STUB_FAIL_COMMENT="$FAIL_COMMENT" \
        STUB_PRS="$WORK/prs" STUB_PR_LIST="$WORK/pr-list.json" STUB_PR_LIST_MODE="$PR_LIST_MODE" \
        GITHUB_REPOSITORY="owner/repo" GITHUB_REPOSITORY_OWNER="owner-name" GH_TOKEN="dummy" \
        bash "$SCRIPT" "${@:-7}" >"$WORK/out.txt" 2>"$WORK/err.txt"
    RC=$?
    cat "$WORK/calls.log" >>"$WORK/all-calls.log"
    cat "$WORK/out.txt" >>"$WORK/all-out.log"
    WRITES=$(grep -Ev '^(graphql|list comments|pr list) ' "$WORK/calls.log" || true)
    QUERIED=$(sed -n 's/^graphql issue //p' "$WORK/calls.log" | tr '\n' ' ' | sed 's/ $//')
    QUERIED_PRS=$(sed -n 's/^graphql pr //p' "$WORK/calls.log" | tr '\n' ' ' | sed 's/ $//')
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

# 書き込みの呼び出しの期待値を作る。使い方: closing <番号> ...(その順に、クローズと記録のコメント)
closing() {
    local n
    for n in "$@"; do
        printf 'issue close %s --repo owner/repo\nissue comment %s --repo owner/repo --body-file\n' "$n" "$n"
    done
}

# 使い方: check <説明> <終了コード> <標準出力の全文> <書き込みの呼び出しの全文>
check() {
    local name="$1" want_rc="$2" want_out="$3" want_writes="$4"
    if [ "$RC" -ne "$want_rc" ]; then
        ng "$name (終了コード $want_rc のはずが $RC)"
        return
    fi
    if [ "$(cat "$WORK/out.txt")" != "$want_out" ]; then
        ng "$name (標準出力が違う。期待: $(printf '%s' "$want_out" | tr '\n' '|'))"
        return
    fi
    if [ "$WRITES" != "$want_writes" ]; then
        ng "$name (書き込みの呼び出しが違う。期待: $(printf '%s' "$want_writes" | tr '\n' '|'))"
        return
    fi
    ok "$name"
}

# 使い方: expect_queried <説明> <照会した Issue の番号を空白区切りで>
expect_queried() {
    if [ "$QUERIED" = "$2" ]; then
        ok "$1"
    else
        ng "$1 (照会した Issue 期待「$2」、実際「$QUERIED」)"
    fi
}

# 使い方: expect_notice <説明> <番号> <含むはずの文字列> ...
# 番号の Issue に付けた知らせの本文に、文字列がすべて含まれることを確かめる。
expect_notice() {
    local name="$1" file="$WORK/posted/notice_$2.md" want
    shift 2
    for want in "$@"; do
        if ! grep -qF -- "$want" "$file" 2>/dev/null; then
            ng "$name (知らせの本文に「$want」が無い)"
            sed 's/^/  | /' "$file" 2>/dev/null
            return
        fi
    done
    ok "$name"
}

# 使い方: expect_no_notice <説明> <番号> <含まないはずの文字列>
expect_no_notice() {
    if [ -f "$WORK/posted/notice_$2.md" ] && ! grep -qF -- "$3" "$WORK/posted/notice_$2.md"; then
        ok "$1"
    else
        ng "$1 (知らせが無いか、本文に「$3」がある)"
    fi
}

# 使い方: expect_mention <説明> <番号>(知らせの先頭行が所有者へのメンションで始まる)
expect_mention() {
    if head -n 1 "$WORK/posted/notice_$2.md" 2>/dev/null | grep -q '^@owner-name '; then
        ok "$1"
    else
        ng "$1 (知らせの先頭行が「@owner-name 」で始まらない)"
    fi
}

expect_err() {
    if grep -q -- "$2" "$WORK/err.txt"; then
        ok "$1"
    else
        ng "$1 (標準エラーに「$2」が無い)"
    fi
}

# =====================================================================
# 本文の読み取り(1.1, 1.5)
# =====================================================================
reset_scenario
BODY=$(printf '%s\n' \
    '## 概要' \
    'Closes #1' \
    'closes: #2' \
    'CLOSES #3, Closes #4 と closes:  #5' \
    'Closes #1' \
    'Fixes #6' \
    'Resolves #7' \
    'Refs: #8' \
    'refs #9 REFS: #16' \
    'Refs: #2' \
    'Refs: #8' \
    'Refs: N/A' \
    'Closes owner/repo#10' \
    'Refs: other/repo#11' \
    'encloses #12' \
    'Closes #13abc' \
    'Closes#14' \
    'Closes' \
    '#15' \
    'Closes #' \
    'Closes #0')
BODY="${BODY}"$'\n'"Closes"$'\t'"#17"$'\r\n'"Closes #18"$'\r\n'
pr_json true "$MERGED_AT" main "$BODY"
for n in 1 2 3 4 5 17 18; do issue "$n" OPEN; done
for n in 8 9 16; do issue "$n" CLOSED; done
run
check "Closes の各形(大文字小文字・コロン・同じ行に複数・タブ・CRLF)を拾い、重複は1回、ほかの語と別リポジトリの形は扱わない" 0 \
    "$(for n in 1 2 3 4 5 17 18; do echo "issue=$n result=closed"; done
    for n in 8 9 16; do echo "issue=$n result=untouched"; done)" \
    "$(closing 1 2 3 4 5 17 18)"
expect_queried "Closes と Refs の番号だけを照会する(Fixes・Resolves・owner/repo# の番号は照会しない)" "1 2 3 4 5 17 18 8 9 16"
expect_err "Refs だけの番号を読み取る(Closes にもある #2 は除く。重複は1回。N/A と別リポジトリの形は除く)" "Refs だけの Issue: #8 #9 #16\$"
expect_err "Closes の番号を読み取る" "Closes の Issue: #1 #2 #3 #4 #5 #17 #18\$"

reset_scenario
pr_json true "$MERGED_AT" main "$(printf '説明だけの本文\nRefs: N/A\nFixes #6\n')"
run
check "Closes も Refs も無い本文では何もしない" 0 "" ""
expect_queried "Closes が無ければ Issue を照会しない" ""
expect_err "Refs: N/A は対象にならない" "Refs だけの Issue: なし\$"

# GraphQL の Int(32ビット)に収まらない番号は、照会せずに not-an-issue とする
reset_scenario
pr_json true "$MERGED_AT" main "$(printf 'Closes #9999999999\nCloses #2147483648\nCloses #21\nRefs: #3000000000\n')"
issue 21 OPEN
run
check "照会できる範囲を超える番号は not-an-issue とし、同じ PR のほかの Issue は閉じる" 0 \
    "$(printf 'issue=21 result=closed\nissue=2147483648 result=not-an-issue\nissue=9999999999 result=not-an-issue\nissue=3000000000 result=not-an-issue')" \
    "$(closing 21)"
expect_queried "照会できる範囲を超える番号は照会しない" "21"

reset_scenario
pr_json true "$MERGED_AT" main "Closes #2147483647"
run
check "範囲の上限ちょうどの番号は照会する(存在しなければ not-an-issue)" 0 "issue=2147483647 result=not-an-issue" ""
expect_queried "範囲の上限ちょうどの番号を照会する" "2147483647"

# 本文をシェルのコマンドとして評価しない
reset_scenario
# shellcheck disable=SC2016 # 展開させない文字列をそのまま本文に入れる
pr_json true "$MERGED_AT" main "$(printf '%s\n' '$(touch "$PWNED")' '`touch "$PWNED"`' '"; touch "$PWNED"; #' 'Closes #41')"
issue 41 OPEN
PWNED="$WORK/pwned" run
check "コマンドの形の文字列を含む本文でも Closes を読み取って閉じる" 0 "issue=41 result=closed" "$(closing 41)"
if [ -e "$WORK/pwned" ]; then
    ng "本文をシェルのコマンドとして評価しない"
else
    ok "本文をシェルのコマンドとして評価しない"
fi

# =====================================================================
# 開いている Issue を閉じて記録する(1.2, 1.3)
# =====================================================================
reset_scenario
issue 21 OPEN
run
check "開いている Closes の Issue を閉じ、記録のコメントを付ける(クローズが先)" 0 "issue=21 result=closed" "$(closing 21)"
if grep -q 'PR #7 のマージにより閉じました' "$WORK/posted/comment_21.md" 2>/dev/null; then
    ok "記録のコメントに、どの PR のマージで閉じたかが書いてある"
else
    ng "記録のコメントに、どの PR のマージで閉じたかが書いてある"
fi
if [ "$(grep -c '^graphql pr 7$' "$WORK/calls.log")" -eq 1 ]; then
    ok "PR を1回照会する"
else
    ng "PR を1回照会する"
fi

# =====================================================================
# 閉じている Issue には書き込まない(1.4)
# =====================================================================
reset_scenario
issue 21 CLOSED "$AFTER_MERGE"
run
check "閉じている Issue(閉じた記録がマージより後)には書き込まない" 0 "issue=21 result=untouched" ""

reset_scenario
issue 21 CLOSED "$BEFORE_MERGE"
run
check "閉じている Issue(閉じた記録がマージより前だけ。手で閉じていた)には書き込まない" 0 "issue=21 result=untouched" ""

reset_scenario
issue 21 CLOSED
run
check "閉じている Issue(閉じた記録が読めない)にも書き込まない" 0 "issue=21 result=untouched" ""

# =====================================================================
# Issue の照会で子の数と親の番号を読む(9.5, 9.6)
# =====================================================================
reset_scenario
issue 21 OPEN
run
query_text=$(tr -s '[:space:]' ' ' <"$WORK/issue-query.txt")
for want in 'subIssuesSummary { total completed }' 'parent { number repository { nameWithOwner } }'; do
    case "$query_text" in
    *"$want"*) ok "Issue の照会で「$want」を求める" ;;
    *) ng "Issue の照会で「$want」を求める (照会: $query_text)" ;;
    esac
done

reset_scenario
issue 21 OPEN
family 21 - 2 1
run
check "子を持つ(親の無い)Closes の Issue も、今と同じく閉じて記録する" 0 "issue=21 result=closed" "$(closing 21)"

reset_scenario
pr_json true "$MERGED_AT" main "Refs: #8"
issue 8 OPEN
family 8 30 0 0
run
check "親を持つ Refs だけの開いた Issue も、今と同じく閉じずに知らせる" 0 \
    "issue=8 result=refs-only-noticed" "api POST comments 8"
expect_queried "Refs だけの Issue の親は照会しない" "8"

# =====================================================================
# 子がすべて閉じた親を閉じる(9.5, 9.6)
# =====================================================================
# 使い方: parent_record <最後に閉じた子の番号> [<PR番号>](親に付ける記録の文面)
parent_record() {
    printf 'この Issue から分けた Issue がすべて閉じたため閉じました(最後に閉じたのは #%s、PR #%s のマージによる)。' "$1" "${2:-7}"
}

# 使い方: expect_record <説明> <番号> <記録の全文>
expect_record() {
    if [ "$(cat "$WORK/posted/comment_$2.md" 2>/dev/null)" = "$3" ]; then
        ok "$1"
    else
        ng "$1 (#$2 の記録の期待: $3)"
        sed 's/^/  | /' "$WORK/posted/comment_$2.md" 2>/dev/null
    fi
}

# 最後の子を閉じると、親の子がすべて閉じる
reset_scenario
issue 21 OPEN
family 21 30 0 0
issue 30 OPEN
family 30 - 2 1
run
check "最後の子の Closes の PR がマージされると、親を閉じて記録を付け、parent-closed を出す(9.6)" 0 \
    "$(printf 'issue=21 result=closed\nissue=30 result=parent-closed')" "$(closing 21 30)"
expect_record "親の記録に、最後に閉じた子と PR の番号が書いてある" 30 "$(parent_record 21)"
expect_queried "親は子を閉じた後に照会する" "21 30"

# 同じ実行をもう一度しても(定期の見直しで同じ PR に再び当たっても)、何も書き込まない
run
check "同じ PR をもう一度処理しても、閉じた子にも閉じた親にも書き込まない" 0 "issue=21 result=untouched" ""
expect_queried "もう一度の処理でも、閉じていた子の親を照会する(閉じていれば何もしない)" "21 30"

# 子が残っている親
reset_scenario
issue 21 OPEN
family 21 30 0 0
issue 30 OPEN
family 30 - 3 1
run
check "閉じていない子が残っている親は閉じず、親に書き込まない(9.5)" 0 "issue=21 result=closed" "$(closing 21)"
expect_queried "子が残っている親も、子を閉じた後に照会して確かめる" "21 30"

# 親がすでに閉じている(子がすべて閉じても何もしない)
reset_scenario
issue 21 OPEN
family 21 30 0 0
issue 30 CLOSED "$BEFORE_MERGE"
family 30 - 1 0
run
check "親がすでに閉じていれば、子がすべて閉じても親に何もしない" 0 "issue=21 result=closed" "$(closing 21)"

# 開き直された親(マージ以後に閉じた記録があり、いまは開いている)
reopened_parent_case() {
    reset_scenario
    issue 21 OPEN
    family 21 30 0 0
    issue 30 OPEN "$2"
    family 30 - 1 0
    run
    check "$1" 0 "issue=21 result=closed" "$(closing 21)"
}
reopened_parent_case "マージより後に閉じた記録がある開いた親(開き直された親)は、子がすべて閉じても閉じない" "$AFTER_MERGE"
reopened_parent_case "親の閉じた記録がマージとちょうど同じ日時でも、開き直された親とみなして閉じない" "$MERGED_AT"

reset_scenario
issue 21 OPEN
family 21 30 0 0
issue 30 OPEN "$BEFORE_MERGE"
family 30 - 1 0
run
check "マージより前の閉じた記録しか無い開いた親は、子がすべて閉じたら閉じる" 0 \
    "$(printf 'issue=21 result=closed\nissue=30 result=parent-closed')" "$(closing 21 30)"

# 子・親・親の親の3段
reset_scenario
issue 21 OPEN
family 21 30 0 0
issue 30 OPEN
family 30 40 1 0
issue 40 OPEN
family 40 - 2 1
run
check "子・親・親の親の3段で、子が閉じると親と親の親を順に閉じる" 0 \
    "$(printf 'issue=21 result=closed\nissue=30 result=parent-closed\nissue=40 result=parent-closed')" \
    "$(closing 21 30 40)"
expect_record "親の親の記録には、最後に閉じた子として親の番号が書いてある" 40 "$(parent_record 30)"
expect_queried "子・親・親の親の順に照会する" "21 30 40"

reset_scenario
issue 21 OPEN
family 21 30 0 0
issue 30 OPEN
family 30 40 1 0
issue 40 OPEN
family 40 - 2 0
run
check "親を閉じても、親の親に閉じていない子が残っていれば親の親は閉じない" 0 \
    "$(printf 'issue=21 result=closed\nissue=30 result=parent-closed')" "$(closing 21 30)"

# GitHub が先に閉じていた子(untouched)
reset_scenario
issue 21 CLOSED "$AFTER_MERGE"
family 21 30 0 0
issue 30 OPEN
family 30 - 2 2
run
check "GitHub が先に閉じていた子(untouched)でも、子がすべて閉じていれば親を閉じる" 0 \
    "$(printf 'issue=21 result=untouched\nissue=30 result=parent-closed')" "$(closing 30)"
expect_record "先に閉じていた子でも、親の記録にその子と PR の番号が書いてある" 30 "$(parent_record 21)"

# 子の数が0件と返る親(閉じた子の数と等しくても、子が1件以上でなければ閉じない)
reset_scenario
issue 21 CLOSED "$AFTER_MERGE"
family 21 30 0 0
issue 30 OPEN
family 30 - 0 0
run
check "子の数が0件と返る親は、閉じた子の数と等しくても閉じない" 0 "issue=21 result=untouched" ""
expect_queried "子の数が0件と返る親も照会して確かめる" "21 30"

# 開き直された子(untouched だが開いている)の親は確かめない
reset_scenario
issue 21 OPEN "$AFTER_MERGE"
family 21 30 0 0
issue 30 OPEN
family 30 - 1 1
run
check "開き直された子の親には何もしない" 0 "issue=21 result=untouched" ""
expect_queried "開き直された子の親は照会しない" "21"

# 同じ親を持つ子が2つ
reset_scenario
pr_json true "$MERGED_AT" main "$(printf 'Closes #21\nCloses #22\n')"
issue 21 OPEN
family 21 30 0 0
issue 22 OPEN
family 22 30 0 0
issue 30 OPEN
family 30 - 2 0
run
check "同じ親を持つ子をどちらも閉じたら、親を1回だけ閉じる" 0 \
    "$(printf 'issue=21 result=closed\nissue=22 result=closed\nissue=30 result=parent-closed')" \
    "$(closing 21 22 30)"
expect_record "同じ親を持つ子が複数なら、親の記録には並びの最後の子を書く" 30 "$(parent_record 22)"
expect_queried "同じ親は1回だけ照会する" "21 22 30"

# 子を閉じられなかった(close-failed)・記録を付けられなかったときは、親を判定しない
reset_scenario
issue 21 OPEN
family 21 30 0 0
issue 30 OPEN
family 30 - 1 0
FAIL_CLOSE=21
run
check "子を閉じられなかったら、親は照会も書き込みもしない" 0 \
    "issue=21 result=close-failed" "$(printf 'issue close 21 --repo owner/repo\napi POST comments 21')"
expect_queried "子を閉じられなかったら、親を照会しない" "21"

reset_scenario
issue 21 OPEN
family 21 30 0 0
issue 30 OPEN
family 30 - 1 0
FAIL_COMMENT=21
run
check "子の記録を付けられなかったら、親は照会も書き込みもしない(終了コード 1)" 1 "" "$(closing 21)"
expect_queried "子の記録を付けられなかったら、親を照会しない" "21"

# Refs だけの Issue は、閉じていても親を判定する対象にしない
reset_scenario
pr_json true "$MERGED_AT" main "$(printf 'Closes #21\nRefs: #8\n')"
issue 21 OPEN
issue 8 CLOSED "$BEFORE_MERGE"
family 8 30 0 0
issue 30 OPEN
family 30 - 1 1
run
check "閉じている Refs だけの Issue の親は、子がすべて閉じていても閉じない" 0 \
    "$(printf 'issue=21 result=closed\nissue=8 result=untouched')" "$(closing 21)"
expect_queried "閉じている Refs だけの Issue の親は照会しない" "21 8"

# 親は8段までたどる(子 #21 の上に、#31 から #39 の9段の親)
reset_scenario
issue 21 OPEN
family 21 31 0 0
for n in 31 32 33 34 35 36 37 38 39; do
    issue "$n" OPEN
    if [ "$n" -lt 39 ]; then family "$n" "$((n + 1))" 1 0; else family "$n" - 1 0; fi
done
run
check "親は8段までたどり、9段目の親は閉じない" 0 \
    "$(echo "issue=21 result=closed"; for n in 31 32 33 34 35 36 37 38; do echo "issue=$n result=parent-closed"; done)" \
    "$(closing 21 31 32 33 34 35 36 37 38)"
expect_queried "9段目の親は照会しない" "21 31 32 33 34 35 36 37 38"
expect_err "たどる段の上限に達したことを標準エラーに出す" "親を8段たどりました"

# 親が別のリポジトリにあるときは、その親を扱わない(このリポジトリの同じ番号の Issue・PR に触れない)
# 使い方: keep_stub <番号>(実行の前の偽物の Issue の応答を残す)
keep_stub() { cp "$WORK/issues/$1.json" "$WORK/before_$1.json"; }
# 使い方: expect_untouched_stub <説明> <番号>
# 偽物の Issue の応答が、keep_stub で残した実行の前と同じ(閉じられず、閉じた子の数も増えていない)ことを確かめる。
expect_untouched_stub() {
    if cmp -s "$WORK/before_$2.json" "$WORK/issues/$2.json"; then
        ok "$1"
    else
        ng "$1 (#$2 の状態が変わった)"
    fi
}

reset_scenario
issue 21 OPEN
family 21 30 0 0 other-owner/other-repo
# このリポジトリの #30 は、照会されれば閉じる条件を満たす無関係な Issue
issue 30 OPEN
family 30 - 1 1
keep_stub 30
run
check "親が別のリポジトリにあれば、子だけを閉じ、親を照会も書き込みもしない" 0 "issue=21 result=closed" "$(closing 21)"
expect_queried "別のリポジトリの親の番号で、このリポジトリの Issue を照会しない" "21"
expect_untouched_stub "このリポジトリの同じ番号の Issue に触れない" 30
expect_err "親が別のリポジトリにあることを標準エラーに出す" "Issue #21 の親は別のリポジトリにあります"

reset_scenario
issue 21 CLOSED "$AFTER_MERGE"
family 21 30 0 0 other-owner/other-repo
issue 30 OPEN
family 30 - 1 1
run
check "閉じていた子の親が別のリポジトリにあっても、親を照会も書き込みもしない" 0 "issue=21 result=untouched" ""
expect_queried "閉じていた子でも、別のリポジトリの親の番号で照会しない" "21"

reset_scenario
issue 21 OPEN
family 21 30 0 0
issue 30 OPEN
family 30 40 1 0 other-owner/other-repo
issue 40 OPEN
family 40 - 1 1
keep_stub 40
run
check "閉じた親の親が別のリポジトリにあれば、親までを閉じ、それより上を照会も書き込みもしない" 0 \
    "$(printf 'issue=21 result=closed\nissue=30 result=parent-closed')" "$(closing 21 30)"
expect_queried "別のリポジトリの親の親の番号で、このリポジトリの Issue を照会しない" "21 30"
expect_untouched_stub "このリポジトリの、親の親と同じ番号の Issue に触れない" 40

reset_scenario
issue 21 OPEN
family 21 30 0 0 Owner/Repo
issue 30 OPEN
family 30 - 1 0
run
check "親のリポジトリの名前は大文字小文字を区別せずに比べ、このリポジトリなら親を閉じる" 0 \
    "$(printf 'issue=21 result=closed\nissue=30 result=parent-closed')" "$(closing 21 30)"

# 親を照会できない・応答の形が違う・閉じられない: 子の結果は出し、親に知らせを1回だけ付ける(9.6)
# 知らせを付けられたら parent-close-failed を出して終了コード 0、付けられなければ終了コード 1。
PARENT_CLOSE_FAILED_MARKER='<!-- issue-close-notice pr=7 kind=parent-close-failed -->'
# 子がすべて閉じたと確かめられたとき(閉じる操作の失敗)の文面
PARENT_ALL_CLOSED_TEXT='この Issue から分けた Issue はすべて閉じましたが、この Issue を自動で閉じられませんでした。'
# 親を照会できない・応答の形が違うとき(子がすべて閉じたかを確かめられていない)の文面
PARENT_UNCHECKED_TEXT='分けた Issue がすべて閉じたかを自動で確かめられなかったため、この Issue を閉じていません。'

reset_scenario
issue 21 OPEN
family 21 30 0 0
: >"$WORK/issues/30.fail"
run
check "親を照会できなければ、親に知らせを付けて parent-close-failed を出し終了コード 0(子は閉じる)" 0 \
    "$(printf 'issue=21 result=closed\nissue=30 result=parent-close-failed')" \
    "$(printf '%s\napi POST comments 30' "$(closing 21)")"
expect_err "親を照会できないことを標準エラーに出す" "親の Issue #30 を照会できません"
expect_notice "親を照会できないときの知らせに、閉じた子・PR 番号・確かめられなかったこと・してほしいこと・目印がある" 30 \
    '#21' 'PR #7' "$PARENT_UNCHECKED_TEXT" 'すべて閉じていれば、この Issue を手で閉じてください' "$PARENT_CLOSE_FAILED_MARKER"
expect_no_notice "親を照会できないときの知らせは、子がすべて閉じたと言い切らない" 30 'すべて閉じましたが'
expect_mention "親を照会できないときの知らせは所有者へのメンションで始まる" 30

# 2度目の実行(1度目の知らせが一覧にある。子は閉じていて、親はまた照会できない)
keep_notice 30
run
check "2度目の実行では、親を照会できなくても知らせを増やさない(終了コード 0)" 0 \
    "$(printf 'issue=21 result=untouched\nissue=30 result=parent-close-failed')" ""

reset_scenario
issue 21 OPEN
family 21 30 0 0
printf '%s\n' '{"data":{"repository":{"issue":{"state":"OPEN","timelineItems":{"nodes":[]},"parent":null}}}}' >"$WORK/issues/30.json"
run
check "親の応答に子の数が無ければ、親を閉じずに知らせを付けて parent-close-failed を出し終了コード 0" 0 \
    "$(printf 'issue=21 result=closed\nissue=30 result=parent-close-failed')" \
    "$(printf '%s\napi POST comments 30' "$(closing 21)")"
expect_err "親の応答の形が想定と違うことを標準エラーに出す" "親の Issue #30 の応答の形が想定と違います"
expect_notice "親の応答の形が違うときの知らせに、確かめられなかったことと目印がある" 30 \
    '#21' 'PR #7' "$PARENT_UNCHECKED_TEXT" "$PARENT_CLOSE_FAILED_MARKER"
expect_no_notice "親の応答の形が違うときの知らせは、子がすべて閉じたと言い切らない" 30 'すべて閉じましたが'
expect_mention "親の応答の形が違うときの知らせは所有者へのメンションで始まる" 30

keep_notice 30
run
check "2度目の実行では、親の応答の形が違っても知らせを増やさない(終了コード 0)" 0 \
    "$(printf 'issue=21 result=untouched\nissue=30 result=parent-close-failed')" ""

reset_scenario
issue 21 OPEN
family 21 30 0 0
issue 30 OPEN
family 30 - 1 0
FAIL_CLOSE=30
run
check "親を閉じられなければ、記録を付けずに知らせを付けて parent-close-failed を出し終了コード 0" 0 \
    "$(printf 'issue=21 result=closed\nissue=30 result=parent-close-failed')" \
    "$(printf '%s\nissue close 30 --repo owner/repo\napi POST comments 30' "$(closing 21)")"
expect_err "親を閉じられないことを標準エラーに出す" "親の Issue #30 を閉じられません"
expect_notice "親を閉じられないときの知らせに、起きたこと・閉じた子・PR 番号・してほしいこと・目印がある" 30 \
    "$PARENT_ALL_CLOSED_TEXT" '#21' 'PR #7' 'この Issue を手で閉じてください' "$PARENT_CLOSE_FAILED_MARKER"
expect_no_notice "親を閉じられないときの知らせは、確かめられなかったとは書かない" 30 '確かめられなかった'
expect_mention "親を閉じられないときの知らせは所有者へのメンションで始まる" 30

# 親を閉じられなければ、その親より上はたどらない(親の親は照会も書き込みもしない)
reset_scenario
issue 21 OPEN
family 21 30 0 0
issue 30 OPEN
family 30 40 1 0
issue 40 OPEN
family 40 - 1 1
FAIL_CLOSE=30
run
check "親を閉じられなければ、親の親を閉じない" 0 \
    "$(printf 'issue=21 result=closed\nissue=30 result=parent-close-failed')" \
    "$(printf '%s\nissue close 30 --repo owner/repo\napi POST comments 30' "$(closing 21)")"
expect_queried "親を閉じられなければ、親の親を照会しない" "21 30"

# 2度目の実行(1度目の知らせが一覧にある。親はまだ開いていて、閉じる操作はまた失敗する)
reset_scenario
issue 21 OPEN
family 21 30 0 0
issue 30 OPEN
family 30 - 1 0
FAIL_CLOSE=30
run
keep_notice 30
run
check "2度目の実行では、親を閉じられなくても知らせを増やさない(終了コード 0)" 0 \
    "$(printf 'issue=21 result=untouched\nissue=30 result=parent-close-failed')" \
    "issue close 30 --repo owner/repo"

# 閉じた親の親を閉じられないときは、親の親に知らせる(最後に閉じた子として親の番号を書く)
reset_scenario
issue 21 OPEN
family 21 30 0 0
issue 30 OPEN
family 30 40 1 0
issue 40 OPEN
family 40 - 1 0
FAIL_CLOSE=40
run
check "親の親を閉じられなければ、親の親に知らせを付けて parent-close-failed を出す(終了コード 0)" 0 \
    "$(printf 'issue=21 result=closed\nissue=30 result=parent-closed\nissue=40 result=parent-close-failed')" \
    "$(printf '%s\nissue close 40 --repo owner/repo\napi POST comments 40' "$(closing 21 30)")"
expect_notice "親の親への知らせには、最後に閉じた子として親の番号が書いてある" 40 \
    "$PARENT_ALL_CLOSED_TEXT" '#30' "$PARENT_CLOSE_FAILED_MARKER"

# 知らせを付けられない: parent-close-failed と出さず終了コード 1
parent_notice_fails() {
    run
    check "$1" 1 "issue=21 result=closed" "$2"
    expect_err "$1(理由を標準エラーに出す)" "親の Issue #30 に知らせのコメントを付けられません"
}
reset_scenario
issue 21 OPEN
family 21 30 0 0
issue 30 OPEN
family 30 - 1 0
FAIL_CLOSE=30
FAIL_NOTICE=30
parent_notice_fails "親を閉じられず、知らせも付けられなければ終了コード 1(parent-close-failed と出さない)" \
    "$(printf '%s\nissue close 30 --repo owner/repo\napi POST comments 30' "$(closing 21)")"

reset_scenario
issue 21 OPEN
family 21 30 0 0
: >"$WORK/issues/30.fail"
FAIL_NOTICE=30
parent_notice_fails "親を照会できず、知らせも付けられなければ終了コード 1(parent-close-failed と出さない)" \
    "$(printf '%s\napi POST comments 30' "$(closing 21)")"

reset_scenario
issue 21 OPEN
family 21 30 0 0
issue 30 OPEN
family 30 - 1 0
FAIL_CLOSE=30
FAIL_LIST=30
parent_notice_fails "親を閉じられず、親のコメントの一覧を読めなければ知らせを付けず終了コード 1" \
    "$(printf '%s\nissue close 30 --repo owner/repo' "$(closing 21)")"

# 他人が同じ目印を書いていても、親への知らせは抑えられない
reset_scenario
issue 21 OPEN
family 21 30 0 0
issue 30 OPEN
family 30 - 1 0
FAIL_CLOSE=30
printf '%s\n' "$PARENT_CLOSE_FAILED_MARKER" >"$WORK/forged.md"
comments 30 'someone-else' "$WORK/forged.md"
run
check "他人が書いた同じ目印のコメントがあっても、親に知らせを付ける" 0 \
    "$(printf 'issue=21 result=closed\nissue=30 result=parent-close-failed')" \
    "$(printf '%s\nissue close 30 --repo owner/repo\napi POST comments 30' "$(closing 21)")"

reset_scenario
issue 21 OPEN
family 21 30 0 0
issue 30 OPEN
family 30 40 1 0
issue 40 OPEN
family 40 - 1 0
FAIL_COMMENT=30
run
check "親の記録を付けられなくても、閉じた親の親は判定して閉じる(終了コード 1)" 1 \
    "$(printf 'issue=21 result=closed\nissue=40 result=parent-closed')" "$(closing 21 30 40)"
expect_err "親の記録を付けられないことを標準エラーに出す" "親の Issue #30 に記録のコメントを付けられません"

# 子の応答の親の欄が想定と違えば、どの Issue にも書き込まない
bad_parent_field() {
    reset_scenario
    issue 21 OPEN
    jq "$2" "$WORK/issues/21.json" >"$WORK/issues/21.tmp" && mv "$WORK/issues/21.tmp" "$WORK/issues/21.json"
    run
    check "$1" 1 "" ""
}
bad_parent_field "Issue の応答に parent の欄が無ければ、何も書き込まず終了コード 1" 'del(.data.repository.issue.parent)'
bad_parent_field "Issue の応答の親の番号が数でなければ、何も書き込まず終了コード 1" \
    '.data.repository.issue.parent = {number: "30", repository: {nameWithOwner: "owner/repo"}}'
bad_parent_field "Issue の応答の親にリポジトリの欄が無ければ、何も書き込まず終了コード 1" \
    '.data.repository.issue.parent = {number: 30}'
bad_parent_field "Issue の応答の親のリポジトリが null なら、何も書き込まず終了コード 1" \
    '.data.repository.issue.parent = {number: 30, repository: null}'
bad_parent_field "Issue の応答の親のリポジトリに nameWithOwner が無ければ、何も書き込まず終了コード 1" \
    '.data.repository.issue.parent = {number: 30, repository: {}}'
bad_parent_field "Issue の応答の親のリポジトリの名前が文字列でなければ、何も書き込まず終了コード 1" \
    '.data.repository.issue.parent = {number: 30, repository: {nameWithOwner: 1}}'

# 親の親の欄の形が想定と違うときは、閉じた子の親の照会の失敗として親に知らせる
reset_scenario
issue 21 OPEN
family 21 30 0 0
issue 30 OPEN
family 30 40 1 0
jq '.data.repository.issue.parent.repository = {}' "$WORK/issues/30.json" >"$WORK/issues/30.tmp" &&
    mv "$WORK/issues/30.tmp" "$WORK/issues/30.json"
run
check "親の応答の親のリポジトリの名前が無ければ、親を閉じずに知らせを付ける" 0 \
    "$(printf 'issue=21 result=closed\nissue=30 result=parent-close-failed')" \
    "$(printf '%s\napi POST comments 30' "$(closing 21)")"
expect_queried "親の応答の形が違えば、親の親を照会しない" "21 30"

# =====================================================================
# 複数の Issue(1.5)、存在しない番号・PR を指す番号
# =====================================================================
reset_scenario
pr_json true "$MERGED_AT" main "$(printf 'Closes #24\nCloses #22, closes #23\nCloses #21\nCloses #25\n')"
issue 21 OPEN
issue 22 CLOSED "$AFTER_MERGE"
issue 24 OPEN "$BEFORE_MERGE"
issue 25 OPEN "$AFTER_MERGE"
run
check "複数の Issue をそれぞれ判定し、開いているものをすべて閉じる" 0 \
    "$(printf 'issue=21 result=closed\nissue=22 result=untouched\nissue=23 result=not-an-issue\nissue=24 result=closed\nissue=25 result=untouched')" \
    "$(closing 21 24)"
expect_err "存在しない、または PR を指している番号をログに残す" "#23"

reset_scenario
pr_json true "$MERGED_AT" main "Closes #23"
run
check "番号が存在しない、または PR を指しているときは何も書き込まず not-an-issue" 0 "issue=23 result=not-an-issue" ""

# =====================================================================
# マージされていない PR、base が main 以外の PR(1.7)
# =====================================================================
reset_scenario
pr_json false null main "Closes #21"
issue 21 OPEN
run
check "マージされずに閉じた PR では何もしない" 0 "" ""
expect_queried "マージされていない PR では Issue を照会しない" ""

reset_scenario
pr_json true "$MERGED_AT" develop "Closes #21"
issue 21 OPEN
run
check "base が main 以外の PR では何もしない" 0 "" ""
expect_queried "base が main 以外の PR では Issue を照会しない" ""

# =====================================================================
# マージの後に閉じられ、開き直された Issue には触らない(2.6)
# =====================================================================
reset_scenario
issue 21 OPEN "$AFTER_MERGE"
run
check "開いていて、マージより後に閉じた記録がある Issue(開き直された)は閉じない" 0 "issue=21 result=untouched" ""

reset_scenario
issue 21 OPEN "$MERGED_AT"
run
check "閉じた記録がマージとちょうど同じ日時でも、マージの後に閉じられたとみなす" 0 "issue=21 result=untouched" ""

reset_scenario
issue 21 OPEN "2026-09-01T00:00:00Z" "$BEFORE_MERGE" "$AFTER_MERGE"
run
check "マージの前と後の両方に閉じた記録がある開いた Issue は閉じない" 0 "issue=21 result=untouched" ""

reset_scenario
issue 21 OPEN "2026-09-01T00:00:00Z" "$BEFORE_MERGE"
run
check "マージより前の閉じた記録しか無い開いた Issue は閉じる" 0 "issue=21 result=closed" "$(closing 21)"

# =====================================================================
# 照会できない・応答の形が違う: 何も書き込まずに終了コード 1
# =====================================================================
reset_scenario
issue 21 OPEN
PR_MODE="fail"
run
check "PR を照会できなければ何も書き込まず終了コード 1" 1 "" ""
expect_queried "PR を照会できなければ Issue を照会しない" ""

reset_scenario
issue 21 OPEN
PR_MODE="notfound"
run
check "番号が PR でなければ何も書き込まず終了コード 1" 1 "" ""

bad_pr() {
    reset_scenario
    issue 21 OPEN
    printf '%s\n' "$2" >"$WORK/pr.json"
    run
    check "$1" 1 "" ""
}
bad_pr "PR の応答が JSON でなければ終了コード 1" 'not json'
bad_pr "PR の応答に pullRequest が無ければ終了コード 1" '{"data":{"repository":{"pullRequest":null}}}'
bad_pr "PR の応答に merged が無ければ終了コード 1" \
    '{"data":{"repository":{"pullRequest":{"mergedAt":"2026-09-30T08:00:00Z","baseRefName":"main","body":"Closes #21"}}}}'
bad_pr "PR の応答の merged が真偽値でなければ終了コード 1" \
    '{"data":{"repository":{"pullRequest":{"merged":"true","mergedAt":"2026-09-30T08:00:00Z","baseRefName":"main","body":"Closes #21"}}}}'
bad_pr "マージ済みなのに mergedAt が無ければ終了コード 1" \
    '{"data":{"repository":{"pullRequest":{"merged":true,"mergedAt":null,"baseRefName":"main","body":"Closes #21"}}}}'
bad_pr "mergedAt が日時の形でなければ終了コード 1" \
    '{"data":{"repository":{"pullRequest":{"merged":true,"mergedAt":"yesterday","baseRefName":"main","body":"Closes #21"}}}}'
bad_pr "PR の応答に baseRefName が無ければ終了コード 1" \
    '{"data":{"repository":{"pullRequest":{"merged":true,"mergedAt":"2026-09-30T08:00:00Z","body":"Closes #21"}}}}'
bad_pr "PR の応答の body が文字列でなければ終了コード 1" \
    '{"data":{"repository":{"pullRequest":{"merged":true,"mergedAt":"2026-09-30T08:00:00Z","baseRefName":"main","body":null}}}}'

# PR の照会が成功(終了コード 0)したのに、応答が「JSON がちょうど1つ」でない。
# 「マージされていない」とみなして終了コード 0 にしない(照会できなかったものとして終了コード 1)。
# 使い方: odd_pr <説明> <printf の書式(応答の中身)>
odd_pr() {
    reset_scenario
    issue 21 OPEN
    # shellcheck disable=SC2059 # 書式そのものを応答の中身として渡す(改行だけ、などを書き分けるため)
    printf "$2" >"$WORK/pr.json"
    run
    check "$1" 1 "" ""
    expect_queried "$1(Issue を照会しない)" ""
    expect_err "$1(応答の形が想定と違うことを標準エラーに出す)" "PR #7 の応答の形が想定と違います"
}
PR_DOC_MERGED='{"data":{"repository":{"pullRequest":{"merged":true,"mergedAt":"2026-09-30T08:00:00Z","baseRefName":"main","body":"Closes #21"}}}}'
PR_DOC_NOT_MERGED='{"data":{"repository":{"pullRequest":{"merged":false,"mergedAt":null,"baseRefName":"main","body":"Closes #21"}}}}'
odd_pr "PR の照会が成功したのに応答が空(0バイト)なら終了コード 1" ''
odd_pr "PR の照会が成功したのに応答が改行だけなら終了コード 1" '\n'
odd_pr "PR の応答に JSON が2つ並んでいれば(マージ済みと、マージされていない)終了コード 1" \
    "${PR_DOC_MERGED}\n${PR_DOC_NOT_MERGED}\n"
odd_pr "PR の応答に JSON が2つ並んでいれば(どちらもマージされていない)終了コード 1" \
    "${PR_DOC_NOT_MERGED}\n${PR_DOC_NOT_MERGED}\n"
odd_pr "PR の応答に JSON が2つ並んでいれば(どちらもマージ済み)終了コード 1" \
    "${PR_DOC_MERGED}\n${PR_DOC_MERGED}\n"

# Issue を1つでも照会できなければ、ほかの Issue にも書き込まない
reset_scenario
pr_json true "$MERGED_AT" main "$(printf 'Closes #21\nCloses #22\n')"
issue 21 OPEN
: >"$WORK/issues/22.fail"
run
check "2つ目の Issue を照会できなければ、1つ目の開いている Issue にも書き込まず終了コード 1" 1 "" ""

bad_issue() {
    reset_scenario
    pr_json true "$MERGED_AT" main "$(printf 'Closes #21\nCloses #22\n')"
    issue 21 OPEN
    printf '%s\n' "$3" >"$WORK/issues/22.$2"
    run
    check "$1" 1 "" ""
}
bad_issue "Issue の応答が JSON でなければ終了コード 1" json 'not json'
bad_issue "Issue の応答に issue が無ければ終了コード 1" json '{"data":{"repository":{"issue":null}}}'
bad_issue "Issue の state が想定と違えば終了コード 1" json \
    '{"data":{"repository":{"issue":{"state":"LOCKED","timelineItems":{"nodes":[]},"subIssuesSummary":{"total":0,"completed":0},"parent":null}}}}'
bad_issue "Issue の応答に閉じた記録の一覧が無ければ終了コード 1" json \
    '{"data":{"repository":{"issue":{"state":"OPEN","subIssuesSummary":{"total":0,"completed":0},"parent":null}}}}'
bad_issue "閉じた記録の日時を読めなければ終了コード 1(閉じる側に倒さない)" json \
    '{"data":{"repository":{"issue":{"state":"OPEN","timelineItems":{"nodes":[{"createdAt":null}]},"subIssuesSummary":{"total":0,"completed":0},"parent":null}}}}'
bad_issue "照会の失敗が NOT_FOUND 以外の理由を含むなら、not-an-issue にせず終了コード 1" fail \
    '{"data":{"repository":{"issue":null}},"errors":[{"type":"NOT_FOUND","path":["repository","issue"],"message":"x"},{"type":"RATE_LIMITED","message":"y"}]}'
bad_issue "リポジトリごと見つからない応答は、not-an-issue にせず終了コード 1" fail \
    '{"data":{"repository":null},"errors":[{"type":"NOT_FOUND","path":["repository"],"message":"x"}]}'
ISSUE_DOC_OPEN='{"data":{"repository":{"issue":{"state":"OPEN","timelineItems":{"nodes":[]},"subIssuesSummary":{"total":0,"completed":0},"parent":null}}}}'
ISSUE_DOC_NOT_FOUND='{"data":{"repository":{"issue":null}},"errors":[{"type":"NOT_FOUND","path":["repository","issue"],"message":"x"}]}'
bad_issue "Issue の照会が成功したのに応答が空(改行だけ)なら終了コード 1" json ''
bad_issue "Issue の応答に JSON が2つ並んでいれば終了コード 1" json "$(printf '%s\n%s' "$ISSUE_DOC_OPEN" "$ISSUE_DOC_OPEN")"
bad_issue "照会の失敗の応答に JSON が2つ並んでいれば、not-an-issue にせず終了コード 1" fail \
    "$(printf '%s\n%s' "$ISSUE_DOC_OPEN" "$ISSUE_DOC_NOT_FOUND")"
reset_scenario
pr_json true "$MERGED_AT" main "$(printf 'Closes #21\nCloses #22\n')"
issue 21 OPEN
: >"$WORK/issues/22.json"
run
check "Issue の照会が成功したのに応答が空(0バイト)なら終了コード 1" 1 "" ""

# =====================================================================
# 閉じる操作の失敗: 知らせを1回付けて終了コード 0(2.1, 2.3, 2.8)
# =====================================================================
CLOSE_FAILED_MARKER='<!-- issue-close-notice pr=7 kind=close-failed -->'
REFS_ONLY_MARKER='<!-- issue-close-notice pr=7 kind=refs-only -->'

reset_scenario
pr_json true "$MERGED_AT" main "$(printf 'Closes #21\nCloses #22\n')"
issue 21 OPEN
issue 22 OPEN
FAIL_CLOSE=21
run
check "閉じる操作が失敗したら知らせを付けて終了コード 0。その Issue に記録を付けず、残りの Issue は閉じる" 0 \
    "$(printf 'issue=21 result=close-failed\nissue=22 result=closed')" \
    "$(printf 'issue close 21 --repo owner/repo\napi POST comments 21\n%s' "$(closing 22)")"
expect_err "閉じる操作が失敗した理由を標準エラーに出す" "Issue #21 を閉じられません"
expect_notice "close-failed の知らせに PR 番号・Issue 番号・起きたこと・してほしいこと・目印がある" 21 \
    'PR #7' '#21' 'マージされました' '閉じられませんでした' 'この Issue を手で閉じてください' "$CLOSE_FAILED_MARKER"
expect_mention "close-failed の知らせは所有者へのメンションで始まる" 21

# 2度目の実行(1度目の知らせが一覧にある。Issue はまだ開いていて、閉じる操作はまた失敗する)
keep_notice 21
issue 22 CLOSED "$AFTER_MERGE"
run
check "2度目の実行では close-failed の知らせを増やさない(終了コード 0)" 0 \
    "$(printf 'issue=21 result=close-failed\nissue=22 result=untouched')" \
    "issue close 21 --repo owner/repo"

# 他人が同じ目印を書いていても、知らせは抑えられない
reset_scenario
issue 21 OPEN
FAIL_CLOSE=21
printf '%s\n' "$CLOSE_FAILED_MARKER" >"$WORK/forged.md"
comments 21 'someone-else' "$WORK/forged.md"
run
check "他人が書いた同じ目印のコメントがあっても close-failed の知らせを付ける" 0 \
    "issue=21 result=close-failed" \
    "$(printf 'issue close 21 --repo owner/repo\napi POST comments 21')"

# 知らせを付けられない: 終了コード 1
reset_scenario
pr_json true "$MERGED_AT" main "$(printf 'Closes #21\nCloses #22\n')"
issue 21 OPEN
issue 22 OPEN
FAIL_CLOSE=21
FAIL_NOTICE=21
run
check "close-failed の知らせを付けられなければ終了コード 1(close-failed と出さない)。残りの Issue は閉じる" 1 \
    "issue=22 result=closed" \
    "$(printf 'issue close 21 --repo owner/repo\napi POST comments 21\n%s' "$(closing 22)")"
expect_err "知らせを付けられない理由を標準エラーに出す" "Issue #21 に知らせのコメントを付けられません"

reset_scenario
issue 21 OPEN
FAIL_CLOSE=21
FAIL_LIST=21
run
check "コメントの一覧を読めなければ close-failed の知らせを付けず終了コード 1" 1 "" "issue close 21 --repo owner/repo"

# =====================================================================
# Refs だけの Issue: 閉じずに知らせを1回付ける(2.2, 2.3, 2.8)
# =====================================================================
reset_scenario
pr_json true "$MERGED_AT" main "$(printf 'Closes #21\nRefs: #8\nRefs: #21\n')"
issue 21 OPEN
issue 8 OPEN
run
check "Refs だけの開いた Issue は閉じず、refs-only の知らせを付ける(Closes の Issue は閉じる)" 0 \
    "$(printf 'issue=21 result=closed\nissue=8 result=refs-only-noticed')" \
    "$(printf '%s\napi POST comments 8' "$(closing 21)")"
expect_notice "refs-only の知らせに PR 番号・Issue 番号・起きたこと・してほしいこと・目印がある" 8 \
    'PR #7' '#8' 'マージされました' 'Closes #8' '開いたまま' '手で閉じてください' '何もしなくて' "$REFS_ONLY_MARKER"
expect_mention "refs-only の知らせは所有者へのメンションで始まる" 8
expect_no_notice "refs-only の知らせに close-failed の目印を付けない" 8 'kind=close-failed'

# 2度目の実行(1度目の知らせが一覧にある)
keep_notice 8
issue 21 CLOSED "$AFTER_MERGE"
run
check "2度目の実行では refs-only の知らせを増やさず untouched" 0 \
    "$(printf 'issue=21 result=untouched\nissue=8 result=untouched')" ""

reset_scenario
pr_json true "$MERGED_AT" main "Refs: #8"
issue 8 OPEN "2026-09-01T00:00:00Z" "$BEFORE_MERGE"
run
check "マージより前の閉じた記録しか無い、Refs だけの開いた Issue には知らせる(閉じない)" 0 \
    "issue=8 result=refs-only-noticed" "api POST comments 8"

# 知らせが既にあるかは、同じ PR・同じ種類の、仕組みが書いた目印だけで決める
refs_marker_case() {
    reset_scenario
    pr_json true "$MERGED_AT" main "Refs: #8"
    issue 8 OPEN
    printf '%s\n' "$3" >"$WORK/other.md"
    comments 8 "$2" "$WORK/other.md"
    run
    check "$1" 0 "issue=8 result=refs-only-noticed" "api POST comments 8"
}
refs_marker_case "他人が書いた同じ目印のコメントがあっても refs-only の知らせを付ける" 'someone-else' "$REFS_ONLY_MARKER"
refs_marker_case "別の PR(#77)の refs-only の知らせがあっても、この PR の知らせを付ける" 'github-actions[bot]' \
    '<!-- issue-close-notice pr=77 kind=refs-only -->'
refs_marker_case "同じ PR の close-failed の知らせがあっても、refs-only の知らせを付ける" 'github-actions[bot]' \
    "$CLOSE_FAILED_MARKER"

# いま閉じている・マージの後に閉じた記録がある Refs だけの Issue には、どの操作もしない(Invariants)
refs_untouched_case() {
    local name="$1"
    shift
    reset_scenario
    pr_json true "$MERGED_AT" main "Refs: #8"
    issue 8 "$@"
    run
    check "$name" 0 "issue=8 result=untouched" ""
}
refs_untouched_case "Refs だけの Issue がいま閉じている(閉じた記録がマージより後)なら、クローズも知らせもしない" CLOSED "$AFTER_MERGE"
refs_untouched_case "Refs だけの Issue がいま閉じている(閉じた記録がマージより前だけ)なら、クローズも知らせもしない" CLOSED "$BEFORE_MERGE"
refs_untouched_case "Refs だけの Issue が開き直されている(マージより後に閉じた記録がある)なら、クローズも知らせもしない" OPEN "$AFTER_MERGE"
refs_untouched_case "Refs だけの Issue の閉じた記録がマージとちょうど同じ日時でも、クローズも知らせもしない" OPEN "$MERGED_AT"

reset_scenario
pr_json true "$MERGED_AT" main "Refs: #23"
run
check "Refs だけの番号が存在しない、または PR を指しているときは何も書き込まず not-an-issue" 0 "issue=23 result=not-an-issue" ""

# 知らせを付けられない・確かめられない: 終了コード 1
reset_scenario
pr_json true "$MERGED_AT" main "$(printf 'Refs: #8\nRefs: #9\n')"
issue 8 OPEN
issue 9 OPEN
FAIL_NOTICE=8
run
check "refs-only の知らせを付けられなければ終了コード 1(refs-only-noticed と出さない)。残りの Issue には知らせる" 1 \
    "issue=9 result=refs-only-noticed" "$(printf 'api POST comments 8\napi POST comments 9')"
expect_err "refs-only の知らせを付けられない理由を標準エラーに出す" "Issue #8 に知らせのコメントを付けられません"

reset_scenario
pr_json true "$MERGED_AT" main "$(printf 'Closes #21\nRefs: #8\n')"
issue 21 OPEN
issue 8 OPEN
FAIL_LIST=8
run
check "Refs だけの Issue の知らせが既にあるかを確かめられなければ、どの Issue にも書き込まず終了コード 1" 1 "" ""

reset_scenario
pr_json true "$MERGED_AT" main "$(printf 'Closes #21\nRefs: #8\n')"
issue 21 OPEN
: >"$WORK/issues/8.fail"
run
check "Refs だけの Issue を照会できなければ、Closes の開いている Issue にも書き込まず終了コード 1" 1 "" ""

reset_scenario
pr_json true "$MERGED_AT" main "$(printf 'Closes #21\nRefs: #8\n')"
issue 21 OPEN
printf '%s\n' '{"data":{"repository":{"issue":{"state":"OPEN","subIssuesSummary":{"total":0,"completed":0},"parent":null}}}}' >"$WORK/issues/8.json"
run
check "Refs だけの Issue の応答の形が想定と違えば、何も書き込まず終了コード 1" 1 "" ""

# =====================================================================
# 記録を付けられない: 終了コード 1
# =====================================================================
reset_scenario
pr_json true "$MERGED_AT" main "$(printf 'Closes #21\nCloses #22\n')"
issue 21 OPEN
issue 22 OPEN
FAIL_COMMENT=21
run
check "記録のコメントを付けられなければ終了コード 1(closed と出さない)。残りの Issue は閉じる" 1 \
    "issue=22 result=closed" "$(closing 21 22)"
expect_err "記録を付けられない理由を標準エラーに出す" "Issue #21 に記録のコメントを付けられません"

# =====================================================================
# 見直しの入口 --sweep(2.4, 2.5, 2.7)
# =====================================================================
# 現在時刻を固定する。一覧の検索条件は、その8日前の日付(2026-09-23)になる。
NOW=$(jq -n '"2026-10-01T12:00:00Z" | fromdateiso8601')
DAY=86400
WEEK=$((7 * DAY))

# 使い方: ago <秒>(固定した現在時刻から、その秒数だけ前の日時)
ago() {
    jq -n -r --argjson t "$((NOW - $1))" '$t | todate'
}

# 使い方: sweep_pr <PR番号> <何秒前にマージしたか> <本文> [<base>]
# PR の応答を置き、マージ済み PR の一覧に足す。
sweep_pr() {
    local at
    at=$(ago "$2")
    pr_json true "$at" "${4:-main}" "$3" "$WORK/prs/$1.json"
    jq --argjson n "$1" --arg at "$at" '. + [{number: $n, mergedAt: $at}]' "$WORK/pr-list.json" >"$WORK/pr-list.tmp" &&
        mv "$WORK/pr-list.tmp" "$WORK/pr-list.json"
}

sweep() {
    NOW_EPOCH="$NOW" run --sweep
}

# 使い方: expect_queried_prs <説明> <照会した PR の番号を空白区切りで>
expect_queried_prs() {
    if [ "$QUERIED_PRS" = "$2" ]; then
        ok "$1"
    else
        ng "$1 (照会した PR 期待「$2」、実際「$QUERIED_PRS」)"
    fi
}

# 使い方: expect_calls <説明> <gh の呼び出しの全文>
expect_calls() {
    if [ "$(cat "$WORK/calls.log")" = "$2" ]; then
        ok "$1"
    else
        ng "$1 (gh の呼び出しが違う。期待: $(printf '%s' "$2" | tr '\n' '|'))"
    fi
}

# --- 対象の期間(2.7)---------------------------------------------------------------
# 境界の前後を1件ずつ。一覧は古い順に並べずに置く(本体がマージの古い順に処理する)。
reset_scenario
sweep_pr 106 299 "Closes #206"
sweep_pr 103 $((WEEK - 1)) "Closes #203"
sweep_pr 101 $((WEEK + 1)) "Closes #201"
sweep_pr 105 300 "Closes #205"
sweep_pr 108 -60 "Closes #208"
sweep_pr 102 "$WEEK" "Closes #202"
sweep_pr 104 301 "Closes #204"
sweep_pr 107 0 "Closes #207"
sweep_pr 109 $((8 * DAY)) "Closes #209"
for n in 201 202 203 204 205 206 207 208 209; do issue "$n" OPEN; done
sweep
check "マージが7日前から5分前までの PR だけを処理する(ちょうど7日前とちょうど5分前は処理する)" 0 \
    "$(printf 'pr=102 issue=202 result=closed\npr=103 issue=203 result=closed\npr=104 issue=204 result=closed\npr=105 issue=205 result=closed')" \
    "$(closing 202 203 204 205)"
expect_queried_prs "7日前より古い PR(7日と1秒・8日)と、5分以内の PR(4分59秒・0秒・未来)は照会しない。マージの古い順に処理する" "102 103 104 105"
expect_queried "対象外の PR の Issue は照会しない" "202 203 204 205"
if [ "$(sed -n '1p' "$WORK/calls.log")" = "pr list merged:>=2026-09-23" ] &&
    [ "$(grep -c '^pr list ' "$WORK/calls.log")" -eq 1 ]; then
    ok "一覧は1回だけ取り、検索は現在時刻の8日前の日付で粗く絞る"
else
    ng "一覧は1回だけ取り、検索は現在時刻の8日前の日付で粗く絞る"
fi

# --- マージのイベントの処理が動かなかった PR(2.4, 2.5)--------------------------------
reset_scenario
sweep_pr 110 $((2 * 3600)) "$(printf 'Closes #21\nRefs: #8\n')"
sweep_pr 111 $((3 * 3600)) "$(printf 'Closes #22\nRefs: #9\n')"
issue 21 OPEN
issue 8 OPEN
issue 22 CLOSED "$(ago $((3 * 3600 - 1)))"
issue 9 CLOSED "$(ago 3600)"
sweep
check "見直しで、開いたままの Closes の Issue を閉じ、Refs だけの Issue に知らせる。処理が済んでいる PR には書き込まない" 0 \
    "$(printf 'pr=111 issue=22 result=untouched\npr=111 issue=9 result=untouched\npr=110 issue=21 result=closed\npr=110 issue=8 result=refs-only-noticed')" \
    "$(printf '%s\napi POST comments 8' "$(closing 21)")"
if grep -q 'PR #110 のマージにより閉じました' "$WORK/posted/comment_21.md" 2>/dev/null; then
    ok "見直しで閉じた記録のコメントに、その PR の番号が書いてある"
else
    ng "見直しで閉じた記録のコメントに、その PR の番号が書いてある"
fi
expect_notice "見直しで付けた refs-only の知らせに、その PR の番号と目印がある" 8 \
    'PR #110' '#8' '<!-- issue-close-notice pr=110 kind=refs-only -->'
expect_err "どの PR を見直しているかを標準エラーに出す" "PR #110"

# 次の見直し(1度目の知らせが一覧にある。Closes の Issue は閉じている)
keep_notice 8
issue 21 CLOSED "$(ago 60)"
sweep
check "次の見直しでは、何も書き込まない(記録も知らせも増やさない)" 0 \
    "$(printf 'pr=111 issue=22 result=untouched\npr=111 issue=9 result=untouched\npr=110 issue=21 result=untouched\npr=110 issue=8 result=untouched')" ""

# 見直しでも、マージの後に閉じられ開き直された Issue には触らない(2.6)
reset_scenario
sweep_pr 112 3600 "$(printf 'Closes #21\nRefs: #8\n')"
issue 21 OPEN "$(ago 1800)"
issue 8 OPEN "$(ago 1800)"
sweep
check "見直しでも、マージの後に閉じられ開き直された Issue には閉じも知らせもしない" 0 \
    "$(printf 'pr=112 issue=21 result=untouched\npr=112 issue=8 result=untouched')" ""

# 見直しでも、閉じる操作が失敗したら知らせて終了コード 0(2.4 の括弧書き)
reset_scenario
sweep_pr 113 3600 "Closes #21"
issue 21 OPEN
FAIL_CLOSE=21
sweep
check "見直しで閉じる操作が失敗したら close-failed の知らせを付けて終了コード 0" 0 \
    "pr=113 issue=21 result=close-failed" "$(printf 'issue close 21 --repo owner/repo\napi POST comments 21')"
expect_notice "見直しで付けた close-failed の知らせに、その PR の番号と目印がある" 21 \
    'PR #113' '<!-- issue-close-notice pr=113 kind=close-failed -->'

# 見直しでも、子がすべて閉じた親を閉じる。次の見直しでは何も書き込まない(9.6)
reset_scenario
sweep_pr 150 3600 "Closes #21"
issue 21 OPEN
family 21 30 0 0
issue 30 OPEN
family 30 - 1 0
sweep
check "見直しでも、子がすべて閉じた親を閉じる(行の先頭に pr=<PR番号> が付く)" 0 \
    "$(printf 'pr=150 issue=21 result=closed\npr=150 issue=30 result=parent-closed')" "$(closing 21 30)"
expect_record "見直しで閉じた親の記録に、その PR の番号が書いてある" 30 "$(parent_record 21 150)"
sweep
check "次の見直しでは、閉じた子にも閉じた親にも書き込まない" 0 "pr=150 issue=21 result=untouched" ""

# 一覧に base が main でない PR が混ざっても、PR ごとの処理が何もしない(判定は PR ごとの経路に任せる)
reset_scenario
sweep_pr 114 3600 "Closes #21" develop
issue 21 OPEN
sweep
check "一覧に main 向けでない PR があっても何もしない(終了コード 0)" 0 "" ""
expect_queried_prs "main 向けかどうかは PR ごとの照会で確かめる" "114"

# NOW_EPOCH を渡さなければ、実際の現在時刻で期間を判定する
reset_scenario
SAVED_NOW="$NOW"
NOW=$(date -u +%s)
sweep_pr 115 3600 "Closes #21"
sweep_pr 116 60 "Closes #22"
NOW="$SAVED_NOW"
issue 21 OPEN
issue 22 OPEN
run --sweep
check "NOW_EPOCH が無ければ実際の現在時刻で判定する(1時間前のマージは処理し、1分前は処理しない)" 0 \
    "pr=115 issue=21 result=closed" "$(closing 21)"

# --- 1件の失敗でも残りを続ける ---------------------------------------------------------
reset_scenario
sweep_pr 120 $((3 * 3600)) "Closes #21"
sweep_pr 121 $((2 * 3600)) "Closes #22"
sweep_pr 122 3600 "Closes #23"
rm "$WORK/prs/121.json"
: >"$WORK/prs/121.fail"
for n in 21 22 23; do issue "$n" OPEN; done
sweep
check "1件の PR を照会できなくても残りの PR を処理し、終了コード 1" 1 \
    "$(printf 'pr=120 issue=21 result=closed\npr=122 issue=23 result=closed')" "$(closing 21 23)"
expect_queried_prs "失敗した PR の後ろの PR も照会する" "120 121 122"
expect_err "失敗した PR の番号を標準エラーに出す" "PR #121 の見直しに失敗しました"

# PR の照会が成功(終了コード 0)したのに応答が空のときも、その PR の失敗として数える
# (「マージされていない」とみなして、見直しを緑で終えない)
# 使い方: sweep_empty_pr <説明> <printf の書式(真ん中の PR の応答の中身)>
sweep_empty_pr() {
    reset_scenario
    sweep_pr 120 $((3 * 3600)) "Closes #21"
    sweep_pr 121 $((2 * 3600)) "Closes #22"
    sweep_pr 122 3600 "Closes #23"
    # shellcheck disable=SC2059 # 書式そのものを応答の中身として渡す
    printf "$2" >"$WORK/prs/121.json"
    for n in 21 22 23; do issue "$n" OPEN; done
    sweep
    check "$1" 1 \
        "$(printf 'pr=120 issue=21 result=closed\npr=122 issue=23 result=closed')" "$(closing 21 23)"
    expect_queried_prs "$1(前後の PR は照会する)" "120 121 122"
    expect_queried "$1(応答が空の PR の Issue は照会しない)" "21 23"
    expect_err "$1(失敗した PR の番号を標準エラーに出す)" "PR #121 の見直しに失敗しました"
}
sweep_empty_pr "3件のうち真ん中の PR の照会の応答が空(0バイト)なら、前後の2件を処理して終了コード 1" ''
sweep_empty_pr "3件のうち真ん中の PR の照会の応答が改行だけなら、前後の2件を処理して終了コード 1" '\n'

reset_scenario
sweep_pr 120 $((3 * 3600)) "$(printf 'Closes #21\nCloses #22\n')"
sweep_pr 122 3600 "Closes #23"
for n in 21 22 23; do issue "$n" OPEN; done
FAIL_COMMENT=21
sweep
check "1件の PR の途中で失敗しても、済んだ分の結果を出し、残りの PR を処理して終了コード 1" 1 \
    "$(printf 'pr=120 issue=22 result=closed\npr=122 issue=23 result=closed')" "$(closing 21 22 23)"

# 1件ごとの時間の上限(時間切れはその PR の失敗として数え、残りを続ける)
reset_scenario
sweep_pr 130 $((2 * 3600)) "Closes #21"
sweep_pr 131 3600 "Closes #22"
rm "$WORK/prs/130.json"
: >"$WORK/prs/130.slow"
issue 21 OPEN
issue 22 OPEN
STARTED=$(date +%s)
SWEEP_PR_TIMEOUT=1 sweep
ELAPSED=$(($(date +%s) - STARTED))
check "1件の PR が時間の上限を超えたら打ち切り、残りの PR を処理して終了コード 1" 1 \
    "pr=131 issue=22 result=closed" "$(closing 22)"
expect_err "時間切れを標準エラーに出す" "PR #130 の見直しが時間の上限(1秒)を超えました"
if [ "$ELAPSED" -lt 20 ]; then
    ok "時間切れの PR を、応答を待ち続けずに打ち切る"
else
    ng "時間切れの PR を、応答を待ち続けずに打ち切る (${ELAPSED}秒かかった)"
fi

# --- 一覧が空・一覧を取れない・応答の形が違う --------------------------------------------
reset_scenario
issue 21 OPEN
sweep
check "一覧が空なら何もせず終了コード 0" 0 "" ""
expect_calls "一覧が空なら、一覧のほかに gh を呼ばない" "pr list merged:>=2026-09-23"

reset_scenario
sweep_pr 140 3600 "Closes #21"
issue 21 OPEN
PR_LIST_MODE="fail"
sweep
check "一覧を取れなければ何も書き込まず終了コード 1" 1 "" ""
expect_calls "一覧を取れなければ、PR も Issue も照会しない" "pr list merged:>=2026-09-23"
expect_err "一覧を取れない理由を標準エラーに出す" "マージ済みの PR の一覧を取れません"

bad_list() {
    reset_scenario
    pr_json true "$(ago 3600)" main "Closes #21" "$WORK/prs/140.json"
    issue 21 OPEN
    printf '%s\n' "$2" >"$WORK/pr-list.json"
    sweep
    check "$1" 1 "" ""
    expect_calls "$1(PR も Issue も照会しない)" "pr list merged:>=2026-09-23"
}
GOOD_ITEM="{\"number\":140,\"mergedAt\":\"$(ago 3600)\"}"
bad_list "一覧の応答が JSON でなければ終了コード 1" 'not json'
bad_list "一覧の応答が配列でなければ終了コード 1" "$GOOD_ITEM"
bad_list "一覧の要素に mergedAt が無ければ、ほかの要素も処理せず終了コード 1" "[$GOOD_ITEM,{\"number\":141}]"
bad_list "一覧の要素の mergedAt が日時の形でなければ終了コード 1" "[$GOOD_ITEM,{\"number\":141,\"mergedAt\":\"yesterday\"}]"
bad_list "一覧の要素に number が無ければ終了コード 1" "[$GOOD_ITEM,{\"mergedAt\":\"$(ago 3600)\"}]"
bad_list "一覧の要素の number が正の整数でなければ終了コード 1" "[$GOOD_ITEM,{\"number\":\"141\",\"mergedAt\":\"$(ago 3600)\"}]"
bad_list "一覧の要素の number が 0 なら終了コード 1" "[$GOOD_ITEM,{\"number\":0,\"mergedAt\":\"$(ago 3600)\"}]"
# 一覧が成功(終了コード 0)したのに、応答が「配列がちょうど1つ」でない。
# 「対象が0件」とみなして終了コード 0 にしない([] は上の「一覧が空」で、こちらは応答そのものが無い)。
bad_list "一覧が成功したのに応答が改行だけなら終了コード 1" ''
bad_list "一覧の応答に JSON が2つ並んでいれば(対象のある配列と空の配列)終了コード 1" "$(printf '[%s]\n[]' "$GOOD_ITEM")"
bad_list "一覧の応答に JSON が2つ並んでいれば(どちらも空の配列)終了コード 1" "$(printf '[]\n[]')"
reset_scenario
pr_json true "$(ago 3600)" main "Closes #21" "$WORK/prs/140.json"
issue 21 OPEN
: >"$WORK/pr-list.json"
sweep
check "一覧が成功したのに応答が空(0バイト)なら終了コード 1" 1 "" ""
expect_calls "一覧の応答が空(0バイト)なら、一覧のほかに gh を呼ばない" "pr list merged:>=2026-09-23"
expect_err "一覧の応答が空(0バイト)なら、応答の形が想定と違うことを標準エラーに出す" "マージ済みの PR の一覧の応答の形が想定と違います"

# 一覧が上限(200件)に達したら、古い側が漏れているおそれを標準エラーに出す
reset_scenario
jq -n --arg at "$(ago $((8 * DAY)))" '[range(0; 200) | {number: (. + 1000), mergedAt: $at}]' >"$WORK/pr-list.json"
sweep
check "一覧が上限の200件でも、期間の外の PR は処理しない(終了コード 0)" 0 "" ""
expect_err "一覧が上限に達したことを標準エラーに出す" "一覧が上限の200件に達しました"

# =====================================================================
# 使い方の誤り
# =====================================================================
check_invocation() {
    local name="$1" omit="$2"
    shift 2
    reset_scenario
    issue 21 OPEN
    : >"$WORK/calls.log"
    local envs=() var
    for var in GITHUB_REPOSITORY=owner/repo GITHUB_REPOSITORY_OWNER=owner-name GH_TOKEN=dummy; do
        [ "${var%%=*}" = "$omit" ] || envs+=("$var")
    done
    env -u GITHUB_REPOSITORY -u GITHUB_REPOSITORY_OWNER -u GH_TOKEN "${envs[@]}" \
        PATH="$WORK/bin:$PATH" \
        STUB_CALLS="$WORK/calls.log" STUB_UNEXPECTED="$WORK/unexpected.log" \
        STUB_PR="$WORK/pr.json" STUB_ISSUES="$WORK/issues" STUB_ISSUE_QUERY="$WORK/issue-query.txt" \
        STUB_POSTED="$WORK/posted" \
        STUB_PRS="$WORK/prs" STUB_PR_LIST="$WORK/pr-list.json" \
        bash "$SCRIPT" "$@" >"$WORK/out.txt" 2>"$WORK/err.txt"
    RC=$?
    if [ "$RC" -eq 1 ] && [ ! -s "$WORK/out.txt" ] && [ ! -s "$WORK/calls.log" ]; then
        ok "$name"
    else
        ng "$name (終了コード 1・出力なし・gh の呼び出しなしのはず。終了コード $RC)"
    fi
}
check_invocation "PR番号が無ければ終了コード 1" ""
check_invocation "PR番号が数字でなければ終了コード 1" "" "7;rm"
check_invocation "PR番号が 0 なら終了コード 1" "" 0
check_invocation "引数が多ければ終了コード 1" "" 7 8
check_invocation "GITHUB_REPOSITORY が無ければ終了コード 1" GITHUB_REPOSITORY 7
check_invocation "GITHUB_REPOSITORY_OWNER が無ければ終了コード 1" GITHUB_REPOSITORY_OWNER 7
check_invocation "GH_TOKEN が無ければ終了コード 1" GH_TOKEN 7
check_invocation "--sweep に余分な引数があれば終了コード 1" "" --sweep 7
check_invocation "--sweep でも GH_TOKEN が無ければ終了コード 1" GH_TOKEN --sweep
check_invocation "--sweep でも GITHUB_REPOSITORY が無ければ終了コード 1" GITHUB_REPOSITORY --sweep
check_invocation "知らない形の引数(--all)は終了コード 1" "" --all
NOW_EPOCH="yesterday" check_invocation "NOW_EPOCH が数字でなければ --sweep は終了コード 1" "" --sweep
SWEEP_PR_TIMEOUT="0" check_invocation "SWEEP_PR_TIMEOUT が 1 以上の整数でなければ --sweep は終了コード 1" "" --sweep

# =====================================================================
# 全ての場面を通して: 書き込みは Issue のクローズ・記録のコメント・知らせのコメントだけ(6.5)
# =====================================================================
other_writes=$(grep -Ev '^(graphql|list comments|pr list) ' "$WORK/all-calls.log" |
    grep -Ev '^issue close [1-9][0-9]* --repo owner/repo$|^issue comment [1-9][0-9]* --repo owner/repo --body-file$|^api POST comments [1-9][0-9]*$' || true)
if [ -z "$other_writes" ]; then
    ok "書き込みの呼び出しは Issue のクローズ・記録のコメント・知らせのコメントだけ"
else
    echo "FAIL: 書き込みの呼び出しは Issue のクローズ・記録のコメント・知らせのコメントだけ"
    printf '%s\n' "$other_writes" | sed 's/^/  /'
    FAILED=1
fi
if [ -s "$WORK/unexpected.log" ]; then
    echo "FAIL: 想定していない gh の呼び出しが無い(PR・ラベル・担当者・本文への書き込み、mutation を含む照会など)"
    sed 's/^/  /' "$WORK/unexpected.log"
    FAILED=1
else
    ok "想定していない gh の呼び出しが無い(PR・ラベル・担当者・本文への書き込み、mutation を含む照会など)"
fi
if [ "$(grep -c '^issue close ' "$WORK/all-calls.log")" -gt 0 ] && [ "$(grep -c '^graphql ' "$WORK/all-calls.log")" -gt 0 ] &&
    [ "$(grep -c '^api POST comments ' "$WORK/all-calls.log")" -gt 0 ] && [ "$(grep -c '^list comments ' "$WORK/all-calls.log")" -gt 0 ]; then
    ok "gh の呼び出しが記録されている(上の確認が空振りしていない)"
else
    echo "FAIL: gh の呼び出しが記録されている(上の確認が空振りしていない)"
    FAILED=1
fi
# 見直し(--sweep)の行だけ、先頭に pr=<PR番号> が付く
bad_lines=$(grep -Ev '^(pr=[1-9][0-9]* )?issue=[1-9][0-9]* result=(untouched|closed|close-failed|refs-only-noticed|not-an-issue|parent-closed|parent-close-failed)$' "$WORK/all-out.log" || true)
if [ -z "$bad_lines" ] && [ -s "$WORK/all-out.log" ]; then
    ok "標準出力は [pr=<PR番号> ]issue=<番号> result=<untouched|closed|close-failed|refs-only-noticed|not-an-issue|parent-closed|parent-close-failed> の行だけ"
else
    echo "FAIL: 標準出力は [pr=<PR番号> ]issue=<番号> result=<untouched|closed|close-failed|refs-only-noticed|not-an-issue|parent-closed|parent-close-failed> の行だけ"
    printf '%s\n' "$bad_lines" | sed 's/^/  /'
    FAILED=1
fi

if [ "$FAILED" -ne 0 ]; then
    echo "テストに失敗があります。"
    exit 1
fi
echo "全てのテストが通りました。"
