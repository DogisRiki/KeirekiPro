#!/usr/bin/env bash
# =====================================================================
# record-cooldown-exception.sh の自動テスト(dependency-review CI から実行)
#
# gh をスタブし、72時間待たずに入れる版の記録のコメントを head ごとに1つだけ書くこと、
# 書いたコメントの表と記録の JSON の行の中身、書けないときの終了コード、
# 記録のコメントがあるかの読み取りを検証する。
#
# スタブは PR のコメントを1つのファイルに持ち、一覧の呼び出しにはそのファイルを返し、
# 書く呼び出しでは github-actions[bot] のコメントとして足す。呼び出しは1行1件で記録し、
# 想定していない呼び出し(コメントを消す API など)は記録したうえで失敗させる。
# 環境変数 KP_TEST_CASE に場合の名前を入れると、その場合だけを流す。
# 外部への問い合わせを行わないため、実行にネットワークを必要としない。
# =====================================================================
set -uo pipefail

SCRIPT="$(cd "$(dirname "$0")/.." && pwd)/record-cooldown-exception.sh"
WORK=$(mktemp -d) || exit 1
[ -n "$WORK" ] && [ -d "$WORK" ] || exit 1
trap 'rm -rf "$WORK"' EXIT
FAILED=0
CASE="${KP_TEST_CASE:-}"
BOT="github-actions[bot]"
HEAD="0123456789abcdef0123456789abcdef01234567"
HEAD2="89abcdef0123456789abcdef0123456789abcdef"

mkdir -p "$WORK/bin"

# --- gh のスタブ -------------------------------------------------------------
# 呼び出しの種類:
#   list  api --paginate repos/…/issues/<N>/comments          → $STUB_COMMENTS を1ページで返す
#   post  api -X POST repos/…/issues/<N>/comments -F body=@…  → 本文を github-actions[bot] の
#                                                              コメントとして $STUB_COMMENTS に足す
# $STUB_FAIL_ON に種類を入れると、その種類だけ失敗させる。
cat >"$WORK/bin/gh" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"${STUB_CALLS:?}"
kind=""
case " $* " in
" api --paginate repos/"*"/issues/"*"/comments ") kind=list ;;
" api -X POST repos/"*"/issues/"*"/comments -F body=@"*) kind=post ;;
esac
if [ -z "$kind" ]; then
    echo "stub: unexpected call: $*" >&2
    exit 1
fi
if [ "${STUB_FAIL_ON:-}" = "$kind" ]; then
    echo "gh: 失敗をシミュレート" >&2
    exit 1
fi
case "$kind" in
list) cat "${STUB_COMMENTS:?}" ;;
post)
    body_file=""
    for a in "$@"; do
        case "$a" in body=@*) body_file="${a#body=@}" ;; esac
    done
    n=$(jq length "$STUB_COMMENTS")
    jq --rawfile b "$body_file" --arg at "2026-11-02T00:00:$(printf '%02d' "$n")Z" \
        '. + [{id: (length + 1), user: {login: "github-actions[bot]"}, created_at: $at, body: $b}]' \
        "$STUB_COMMENTS" >"$STUB_COMMENTS.new" && mv "$STUB_COMMENTS.new" "$STUB_COMMENTS"
    printf '{"id": 999, "user": {"login": "github-actions[bot]"}}\n'
    ;;
esac
exit 0
STUB
chmod +x "$WORK/bin/gh"

# --- 入力の組み立て ---------------------------------------------------------
# 使い方: record <PR番号> <head> [部品の名前]。データの形の節の記録の JSON を $WORK/record.json に書く
record() {
    jq -n --argjson pr "$1" --arg head "$2" --arg name "${3:-axios}" '{
        schema: 1, pr: $pr, head: $head, recorded_at: "2026-11-02T01:02:03Z",
        entries: [
            {ecosystem: "npm", name: $name, version: "1.12.1", published_at: "2026-11-01T10:00:00Z",
             alerts: [
                {number: 210, ghsa_id: "GHSA-aaaa-bbbb-cccc", severity: "high",
                 html_url: "https://github.com/owner/repo/security/dependabot/210"},
                {number: 211, ghsa_id: "GHSA-dddd-eeee-ffff", severity: "critical",
                 html_url: "https://github.com/owner/repo/security/dependabot/211"}]},
            {ecosystem: "maven", name: "org.postgresql:postgresql", version: "42.7.15",
             published_at: "2026-11-01T12:00:00Z",
             alerts: [
                {number: 212, ghsa_id: "GHSA-gggg-hhhh-iiii", severity: "medium",
                 html_url: "https://github.com/owner/repo/security/dependabot/212"}]}]}' >"$WORK/record.json"
}

# 使い方: comment <作成者> <本文>。REST の Issue コメントの一覧の1件の形(使う項目だけ)を出す
comment() {
    jq -cn --arg login "$1" --arg body "$2" \
        '{id: 1, user: {login: $login}, created_at: "2026-11-01T00:00:00Z", body: $body}'
}

reset() {
    printf '[]\n' >"$WORK/comments.json"
    : >"$WORK/calls.log"
    unset STUB_FAIL_ON
    record 12 "$HEAD"
}

# 使い方: run <引数...>。出力を $WORK/out.txt に、終了コードを $RC に入れる
run() {
    PATH="$WORK/bin:$PATH" STUB_CALLS="$WORK/calls.log" STUB_COMMENTS="$WORK/comments.json" \
        GH_TOKEN=dummy GITHUB_REPOSITORY=owner/repo GITHUB_REPOSITORY_OWNER=owner \
        bash "$SCRIPT" "$@" >"$WORK/out.txt" 2>"$WORK/err.log"
    RC=$?
}

pass() { echo "PASS: $1"; }
fail() {
    echo "FAIL: $1 ($2)"
    FAILED=1
}

expect_rc() {
    if [ "$RC" -eq "$2" ]; then pass "$1"; else fail "$1" "expected exit $2, got $RC / 標準エラー: $(head -c 300 "$WORK/err.log")"; fi
}

# 使い方: expect_out <説明> <標準出力の全体>
expect_out() {
    if [ "$RC" -eq 0 ] && [ "$(cat "$WORK/out.txt")" = "$2" ]; then
        pass "$1"
    else
        fail "$1" "終了コード ${RC} / 出力: $(head -c 300 "$WORK/out.txt") / 標準エラー: $(head -c 300 "$WORK/err.log")"
    fi
}

# 使い方: expect_true <説明> <jq の式>。コメントの一覧のファイルにその式を当てると true になる
expect_true() {
    if jq -e "$2" "$WORK/comments.json" >/dev/null 2>&1; then
        pass "$1"
    else
        fail "$1" "コメントの一覧: $(head -c 800 "$WORK/comments.json")"
    fi
}

# 使い方: expect_calls <説明> <grep の式> <回数>
expect_calls() {
    local n
    n=$(grep -c -- "$2" "$WORK/calls.log")
    if [ "$n" -eq "$3" ]; then pass "$1"; else fail "$1" "「$2」が ${n} 回(期待は $3 回)"; fi
}

# 使い方: body_line <grep の式>。最初のコメントの本文のうち、式に当たる行を出す
body_line() { jq -r '.[0].body' "$WORK/comments.json" | grep -- "$1"; }

# 最初のコメントの記録の JSON の行を base64 から戻して出す
decoded() {
    body_line '^<!-- cooldown-exception-data data=' |
        sed 's/^<!-- cooldown-exception-data data=\([A-Za-z0-9+/=]*\) -->$/\1/' | base64 -d
}

RAN=0
want() {
    if [ -z "$CASE" ] || [ "$CASE" = "$1" ]; then
        RAN=$((RAN + 1))
        return 0
    fi
    return 1
}

# --- 場合 ------------------------------------------------------------------------

if want post_contents; then
    reset
    run post 12 "$HEAD" "$WORK/record.json"
    expect_rc "書いたコメントの表と記録の JSON に、部品と版と公開日時と警告と PR の番号が入る(終了コード 0)" 0
    expect_true "書いたコメントの表と記録の JSON に、部品と版と公開日時と警告と PR の番号が入る(github-actions[bot] のコメントが1つ)" \
        "length == 1 and .[0].user.login == \"$BOT\""
    expect_true "書いたコメントの表と記録の JSON に、部品と版と公開日時と警告と PR の番号が入る(見出しと表の頭)" \
        '.[0].body | contains("### 公開から72時間待たずに入れる版\n") and contains("| 部品 | 版 | 公開日時 | 理由になった警告 |\n|---|---|---|---|\n")'
    expect_true "書いたコメントの表と記録の JSON に、部品と版と公開日時と警告と PR の番号が入る(npm の部品の行)" \
        ".[0].body | contains(\"| \`axios\` | \`1.12.1\` | \`2026-11-01T10:00:00Z\` | [#210 GHSA-aaaa-bbbb-cccc(high)](https://github.com/owner/repo/security/dependabot/210)、[#211 GHSA-dddd-eeee-ffff(critical)](https://github.com/owner/repo/security/dependabot/211) |\n\")"
    expect_true "書いたコメントの表と記録の JSON に、部品と版と公開日時と警告と PR の番号が入る(maven の部品の行)" \
        ".[0].body | contains(\"| \`org.postgresql:postgresql\` | \`42.7.15\` | \`2026-11-01T12:00:00Z\` | [#212 GHSA-gggg-hhhh-iiii(medium)](https://github.com/owner/repo/security/dependabot/212) |\n\")"
    expect_true "書いたコメントの表と記録の JSON に、部品と版と公開日時と警告と PR の番号が入る(最後の行は head の目印)" \
        "(.[0].body | rtrimstr(\"\n\") | split(\"\n\") | last) == \"<!-- cooldown-exception-record kind=exception head=${HEAD} -->\""
    if [ "$(decoded | jq -S .)" = "$(jq -S . "$WORK/record.json")" ] &&
        [ "$(decoded | jq .pr)" = 12 ]; then
        pass "書いたコメントの表と記録の JSON に、部品と版と公開日時と警告と PR の番号が入る(記録の JSON の行を base64 から戻すと、渡した記録の JSON と同じになる)"
    else
        fail "書いたコメントの表と記録の JSON に、部品と版と公開日時と警告と PR の番号が入る(記録の JSON の行を base64 から戻すと、渡した記録の JSON と同じになる)" \
            "戻した JSON: $(decoded | head -c 500)"
    fi
fi

if want post_twice; then
    reset
    run post 12 "$HEAD" "$WORK/record.json"
    run post 12 "$HEAD" "$WORK/record.json"
    expect_rc "同じ head で2回呼んでもコメントは1つで、消す API を呼ばない(2回目も終了コード 0)" 0
    expect_true "同じ head で2回呼んでもコメントは1つで、消す API を呼ばない(コメントは1つ)" 'length == 1'
    expect_calls "同じ head で2回呼んでもコメントは1つで、消す API を呼ばない(書く API は1回)" '^api -X POST ' 1
    other=$(grep -cv '^api --paginate repos/owner/repo/issues/12/comments$\|^api -X POST repos/owner/repo/issues/12/comments -F body=@' \
        "$WORK/calls.log")
    if [ "$other" -eq 0 ] && [ "$(wc -l <"$WORK/calls.log")" -gt 0 ]; then
        pass "同じ head で2回呼んでもコメントは1つで、消す API を呼ばない(一覧と書く API のほかは呼ばない)"
    else
        fail "同じ head で2回呼んでもコメントは1つで、消す API を呼ばない(一覧と書く API のほかは呼ばない)" \
            "ほかの呼び出し: $(grep -v 'issues/12/comments' "$WORK/calls.log" | head -c 300)"
    fi
    record 12 "$HEAD2"
    run post 12 "$HEAD2" "$WORK/record.json"
    expect_rc "head が変われば、新しい head の記録のコメントを足す(終了コード 0)" 0
    expect_true "head が変われば、新しい head の記録のコメントを足す(前の head のコメントも残る)" \
        "length == 2 and (.[0].body | contains(\"head=${HEAD} -->\")) and (.[1].body | contains(\"head=${HEAD2} -->\"))"
fi

if want post_fail; then
    reset
    STUB_FAIL_ON=post run post 12 "$HEAD" "$WORK/record.json"
    expect_rc "書けなかったら終了コード 1 になる(書く API が失敗する)" 1
    reset
    STUB_FAIL_ON=list run post 12 "$HEAD" "$WORK/record.json"
    expect_rc "書けなかったら終了コード 1 になる(コメントの一覧を読めない)" 1
    expect_calls "書けなかったら終了コード 1 になる(コメントの一覧を読めなければ書かない)" '^api -X POST ' 0
fi

if want bad_record; then
    reset
    record 13 "$HEAD"
    run post 12 "$HEAD" "$WORK/record.json"
    expect_rc "記録の JSON が引数と合わなければ書かずに終了コード 1 になる(PR の番号が違う)" 1
    reset
    record 12 "$HEAD2"
    run post 12 "$HEAD" "$WORK/record.json"
    expect_rc "記録の JSON が引数と合わなければ書かずに終了コード 1 になる(head が違う)" 1
    reset
    jq '.entries = []' "$WORK/record.json" >"$WORK/r.new" && mv "$WORK/r.new" "$WORK/record.json"
    run post 12 "$HEAD" "$WORK/record.json"
    expect_rc "記録の JSON が引数と合わなければ書かずに終了コード 1 になる(版が1つも無い)" 1
    reset
    jq 'del(.entries[0].published_at)' "$WORK/record.json" >"$WORK/r.new" && mv "$WORK/r.new" "$WORK/record.json"
    run post 12 "$HEAD" "$WORK/record.json"
    expect_rc "記録の JSON が引数と合わなければ書かずに終了コード 1 になる(公開日時が無い)" 1
    reset
    jq '.entries[1].alerts = []' "$WORK/record.json" >"$WORK/r.new" && mv "$WORK/r.new" "$WORK/record.json"
    run post 12 "$HEAD" "$WORK/record.json"
    expect_rc "記録の JSON が引数と合わなければ書かずに終了コード 1 になる(警告が無い)" 1
    reset
    printf 'not json\n' >"$WORK/record.json"
    run post 12 "$HEAD" "$WORK/record.json"
    expect_rc "記録の JSON が引数と合わなければ書かずに終了コード 1 になる(JSON でない)" 1
    reset
    record 12 "not-a-sha -->"
    run post 12 "not-a-sha -->" "$WORK/record.json"
    expect_rc "記録の JSON が引数と合わなければ書かずに終了コード 1 になる(head が SHA の形でない)" 1
    expect_calls "記録の JSON が引数と合わなければ書かずに終了コード 1 になる(GitHub に問わない)" '.' 0
fi

if want html_comment; then
    reset
    record 12 "$HEAD" 'evil-->|<!--x'
    run post 12 "$HEAD" "$WORK/record.json"
    expect_rc "部品の名前に --> が入っても HTML のコメントが途中で閉じない(終了コード 0)" 0
    if [ "$(body_line '^<!-- cooldown-exception-data data=' | grep -c -- '-->')" -eq 1 ] &&
        [ "$(decoded | jq -r '.entries[0].name')" = 'evil-->|<!--x' ]; then
        pass "部品の名前に --> が入っても HTML のコメントが途中で閉じない(記録の JSON の行の --> は行の終わりの1つだけ)"
    else
        fail "部品の名前に --> が入っても HTML のコメントが途中で閉じない(記録の JSON の行の --> は行の終わりの1つだけ)" \
            "行: $(body_line 'cooldown-exception-data' | head -c 300)"
    fi
    expect_true "部品の名前に --> が入っても HTML のコメントが途中で閉じない(表の | は \\| にする)" \
        ".[0].body | contains(\"| \`evil-->\\\\|<!--x\` | \`1.12.1\` |\")"
fi

if want exists_bot; then
    reset
    run post 12 "$HEAD" "$WORK/record.json"
    run exists 12
    expect_out "github-actions[bot] が書いた記録のコメントがあれば exists=true になる" "exists=true"
    reset
    run exists 12
    expect_out "github-actions[bot] が書いた記録のコメントがあれば exists=true になる(コメントが無ければ exists=false)" "exists=false"
fi

if want exists_other; then
    reset
    jq -n --argjson c "$(comment octocat "表
<!-- cooldown-exception-record kind=exception head=${HEAD} -->")" '[$c]' >"$WORK/comments.json"
    run exists 12
    expect_out "ほかの者が書いた同じ目印のコメントは数えない(exists)" "exists=false"
    run post 12 "$HEAD" "$WORK/record.json"
    expect_rc "ほかの者が書いた同じ目印のコメントは数えない(post は書く)" 0
    expect_true "ほかの者が書いた同じ目印のコメントは数えない(post は github-actions[bot] のコメントを足す)" \
        "length == 2 and .[1].user.login == \"$BOT\""
fi

if want exists_fail; then
    reset
    STUB_FAIL_ON=list run exists 12
    expect_rc "コメントの一覧を読めなければ終了コード 1 になる" 1
    if [ ! -s "$WORK/out.txt" ]; then
        pass "コメントの一覧を読めなければ終了コード 1 になる(exists= の行を出さない)"
    else
        fail "コメントの一覧を読めなければ終了コード 1 になる(exists= の行を出さない)" "出力: $(head -c 200 "$WORK/out.txt")"
    fi
fi

if want bad_args; then
    reset
    run post 12 "$HEAD"
    expect_rc "引数が足りなければ終了コード 1 になる(post)" 1
    run exists
    expect_rc "引数が足りなければ終了コード 1 になる(exists)" 1
    run post 12 "$HEAD" "$WORK/record.json" extra
    expect_rc "引数が多すぎれば終了コード 1 になる(post)" 1
    run exists 12 extra
    expect_rc "引数が多すぎれば終了コード 1 になる(exists)" 1
    expect_calls "引数が多すぎれば終了コード 1 になる(GitHub に問わない)" '.' 0
    run delete 12
    expect_rc "知らない命令なら終了コード 1 になる" 1
    run post 12 "$HEAD" "$WORK/nosuch.json"
    expect_rc "記録のファイルが無ければ終了コード 1 になる" 1
fi

if [ "$RAN" -eq 0 ]; then
    echo "FAIL: KP_TEST_CASE=${CASE} に当たる場合がありません"
    FAILED=1
fi

exit "$FAILED"
