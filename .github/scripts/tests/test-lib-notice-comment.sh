#!/usr/bin/env bash
# =====================================================================
# lib-notice-comment.sh の自動テスト(guardrails CI の escape-hatch から実行)
#
# gh をスタブし、目印つきの知らせのコメントを「同じ目印が無いときだけ」付けること
# (要件 2.8・5.3)、目印を数える相手が知らせの作成者だけであること、メンションの
# 有無、コメントの一覧を読めないときに付けないこと、最新の知らせの種類の取り出しを
# 検証する。
#
# スタブは呼び出しを1行1件で記録し、コメントの本文(-F body=@<ファイル>)は
# 「記録の行番号.txt」に写す。想定していない呼び出しは記録したうえで失敗させる。
# コメントの一覧は REST の応答の形(.user.login が github-actions[bot])で返す。
# 外部への問い合わせを行わないため、実行にネットワークを必要としない。
#
# ライブラリは呼び出し側と同じ厳しい設定(set -Eeuo pipefail と ERR の trap)の
# 下で source して呼ぶ。関数の中の失敗が呼び出し側の trap に漏れないことを
# 確かめるため。
# =====================================================================
set -uo pipefail

LIB="$(cd "$(dirname "$0")/.." && pwd)/lib-notice-comment.sh"
WORK=$(mktemp -d) || exit 1
[ -n "$WORK" ] && [ -d "$WORK" ] || exit 1
trap 'rm -rf "$WORK"' EXIT
FAILED=0

mkdir -p "$WORK/bin" "$WORK/bodies"
CALLS="$WORK/calls.log"
OUT="$WORK/out.txt"
ERR_OUT="$WORK/err.txt"
BOT="github-actions[bot]"
MARKER="<!-- auto-merge-notice kind=failed head=abc123 -->"

# --- gh のスタブ -------------------------------------------------------------
# 呼び出しの種類(STUB_FAIL_ON に指定すると、その種類だけ失敗させる):
#   list  api --paginate repos/…/issues/<N>/comments          → $STUB_COMMENTS を返す
#   post  api -X POST repos/…/issues/<N>/comments -F body=@…  → 作ったコメントを返す
cat >"$WORK/bin/gh" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"${STUB_CALLS:?}"
n=$(wc -l <"$STUB_CALLS" | tr -d ' ')
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
        cp "$body_file" "${STUB_BODIES:?}/${n}.txt" || exit 1
        printf '{"id": 999, "user": {"login": "github-actions[bot]"}}\n'
        ;;
esac
exit 0
STUB
chmod +x "$WORK/bin/gh"

# --- 入力の組み立て ---------------------------------------------------------
# 使い方: comment <id> <作成者> <作成日時> <本文>
# REST の Issue コメントの一覧の1件の形(使う項目だけ)を出す。
comment() {
    jq -cn --argjson id "$1" --arg login "$2" --arg at "$3" --arg body "$4" \
        '{id: $id, user: {login: $login}, created_at: $at, body: $body}'
}

# 使い方: pages <1ページ目の要素...> [-- <2ページ目の要素...>]
# gh api --paginate(--slurp なし)は、ページごとの配列を続けて出力する。
pages() {
    local -a cur=()
    local a
    for a in "$@"; do
        if [ "$a" = "--" ]; then
            printf '%s\n' "${cur[@]}" | jq -cs '.'
            cur=()
        else
            cur+=("$a")
        fi
    done
    if [ "${#cur[@]}" -gt 0 ]; then
        printf '%s\n' "${cur[@]}" | jq -cs '.'
    else
        printf '[]\n'
    fi
}

reset() {
    printf '[]\n' >"$WORK/comments.json"
    printf 'PR #12 の自動マージを予約できませんでした。\n\nしてほしいこと: 調べてください。\n' >"$WORK/body.md"
    unset STUB_FAIL_ON NOTICE_AUTHOR
    export GH_TOKEN="dummy" GITHUB_REPOSITORY="owner/repo" GITHUB_REPOSITORY_OWNER="owner"
    : >"$CALLS"
    rm -f "$WORK"/bodies/*.txt
}

# 使い方: run_strict <関数名> <引数...>
# 呼び出し側と同じ厳しい設定で source し、関数をそのまま呼ぶ。関数が 0 以外を
# 返すか、関数の中の失敗が trap に漏れると、終了コード 90 で止まる。
LAST_EXIT=0
run_strict() {
    PATH="$WORK/bin:$PATH" STUB_CALLS="$CALLS" STUB_BODIES="$WORK/bodies" STUB_COMMENTS="$WORK/comments.json" \
        bash -c 'set -Eeuo pipefail; trap "exit 90" ERR; source "$1"; shift; "$@"' \
        _ "$LIB" "$@" >"$OUT" 2>"$ERR_OUT"
    LAST_EXIT=$?
}

# 使い方: run_rc <関数名> <引数...>
# 関数の戻り値をそのまま終了コードにする(失敗の戻り値を確かめるため)。
run_rc() {
    PATH="$WORK/bin:$PATH" STUB_CALLS="$CALLS" STUB_BODIES="$WORK/bodies" STUB_COMMENTS="$WORK/comments.json" \
        bash -c 'set -uo pipefail; source "$1"; shift; "$@"' \
        _ "$LIB" "$@" >"$OUT" 2>"$ERR_OUT"
    LAST_EXIT=$?
}

pass() { echo "PASS: $1"; }
fail() {
    echo "FAIL: $1"
    FAILED=1
}

# 使い方: check_exit <期待する終了コード> <説明>
check_exit() {
    if [ "$LAST_EXIT" -eq "$1" ]; then
        pass "$2"
    else
        fail "$2 (期待 $1 / 実際 ${LAST_EXIT})"
        sed 's/^/     | /' "$OUT" "$ERR_OUT"
    fi
}

# 使い方: check_out <期待する標準出力> <説明>
check_out() {
    local got
    got=$(cat "$OUT")
    if [ "$got" = "$1" ]; then
        pass "$2"
    else
        fail "$2 (期待 '$1' / 実際 '${got}')"
    fi
}

# 使い方: check_called <正規表現> <説明>  /  check_not_called <正規表現> <説明>
check_called() {
    if grep -qE -- "$1" "$CALLS"; then
        pass "$2"
    else
        fail "$2 (呼び出しが無い: $1)"
        echo "     実際: $(tr '\n' '|' <"$CALLS")"
    fi
}
check_not_called() {
    if grep -qE -- "$1" "$CALLS"; then
        fail "$2 (呼ばれた: $(grep -E -- "$1" "$CALLS" | tr '\n' '|'))"
    else
        pass "$2"
    fi
}

# 使い方: check_post_count <期待する件数> <説明>
check_post_count() {
    local got
    got=$(grep -cE -- '^api -X POST ' "$CALLS" || true)
    if [ "$got" -eq "$1" ]; then
        pass "$2"
    else
        fail "$2 (期待 $1 件 / 実際 ${got} 件)"
        echo "     実際: $(tr '\n' '|' <"$CALLS")"
    fi
}

# 使い方: check_posted_body <期待する本文のファイル> <説明>
# 最初のコメントの呼び出しに渡された本文が、期待と1バイトも違わないことを確かめる。
check_posted_body() {
    local n f=""
    n=$(grep -nE -- '^api -X POST ' "$CALLS" | head -n 1 | cut -d: -f1)
    if [ -n "$n" ] && [ -f "$WORK/bodies/${n}.txt" ]; then
        f="$WORK/bodies/${n}.txt"
    fi
    if [ -n "$f" ] && cmp -s "$f" "$1"; then
        pass "$2"
    else
        fail "$2"
        [ -z "$f" ] || echo "     実際: $(tr '\n' '|' <"$f")"
        echo "     期待: $(tr '\n' '|' <"$1")"
    fi
}

POST_RE='^api -X POST '

echo "--- source しただけでは何もしない ---"
reset
PATH="$WORK/bin:$PATH" STUB_CALLS="$CALLS" STUB_BODIES="$WORK/bodies" STUB_COMMENTS="$WORK/comments.json" \
    bash -c 'set -Eeuo pipefail; before="$-|$(shopt -po)|$(trap -p)"; source "$1"; after="$-|$(shopt -po)|$(trap -p)"; [ "$before" = "$after" ]' \
    _ "$LIB" >"$OUT" 2>"$ERR_OUT"
LAST_EXIT=$?
check_exit 0 "source してもシェルの設定と trap を変えない"
if [ ! -s "$OUT" ] && [ ! -s "$ERR_OUT" ] && [ ! -s "$CALLS" ]; then
    pass "source しただけでは出力も gh の呼び出しも無い"
else
    fail "source しただけでは出力も gh の呼び出しも無い"
fi
PATH="$WORK/bin:$PATH" STUB_CALLS="$CALLS" STUB_BODIES="$WORK/bodies" STUB_COMMENTS="$WORK/comments.json" \
    bash -c 'set -uo pipefail; source "$1"; notice_post abc x y z; echo "呼び出し元が続く"' \
    _ "$LIB" >"$OUT" 2>"$ERR_OUT"
if grep -qF "呼び出し元が続く" "$OUT"; then
    pass "関数は失敗しても exit せず、呼び出し元が続く"
else
    fail "関数は失敗しても exit せず、呼び出し元が続く"
fi

echo "--- 目印が無ければ付ける(要件 2.8・5.3) ---"
reset
pages "$(comment 1 "$BOT" 2026-01-01T00:00:00Z "関係のないコメント")" >"$WORK/comments.json"
run_strict notice_post 12 "$MARKER" "$WORK/body.md" yes
check_exit 0 "目印のコメントが無ければ付けて 0 を返す"
check_called '^api --paginate repos/owner/repo/issues/12/comments$' "コメントの一覧は REST の Issue コメントの一覧をページ送りで読む"
check_called '^api -X POST repos/owner/repo/issues/12/comments -F body=@' "指定の番号にコメントする"
check_post_count 1 "コメントは1回だけ"
printf '@owner PR #12 の自動マージを予約できませんでした。\n\nしてほしいこと: 調べてください。\n\n%s\n' "$MARKER" >"$WORK/expected.md"
check_posted_body "$WORK/expected.md" "mention が yes なら先頭行の頭に所有者へのメンションを付け、末尾に目印を付ける"
check_out "" "標準出力には何も出さない(呼び出し側の result= の行を汚さない)"
others=$(grep -vE '^api (--paginate|-X POST) repos/owner/repo/issues/12/comments( |$)' "$CALLS" || true)
if [ -z "$others" ]; then
    pass "指定の番号のコメントの一覧とコメントのほかに gh を呼ばない"
else
    fail "指定の番号のコメントの一覧とコメントのほかに gh を呼ばない (${others})"
fi
printf 'PR #12 の自動マージを予約できませんでした。\n\nしてほしいこと: 調べてください。\n' >"$WORK/body-original.md"
if cmp -s "$WORK/body.md" "$WORK/body-original.md"; then
    pass "渡した本文のファイルを書き換えない"
else
    fail "渡した本文のファイルを書き換えない"
fi

reset
run_strict notice_post 12 "$MARKER" "$WORK/body.md" no
check_exit 0 "コメントが1件も無い PR にも付けて 0 を返す"
printf 'PR #12 の自動マージを予約できませんでした。\n\nしてほしいこと: 調べてください。\n\n%s\n' "$MARKER" >"$WORK/expected.md"
check_posted_body "$WORK/expected.md" "mention が no ならメンションを付けない(本文と目印だけ)"
if grep -qF "@owner" "$WORK"/bodies/*.txt 2>/dev/null; then
    fail "mention が no のコメントに所有者へのメンションが無い"
else
    pass "mention が no のコメントに所有者へのメンションが無い"
fi

echo "--- 目印があれば付けない(要件 2.8・5.3) ---"
reset
pages "$(comment 1 "$BOT" 2026-01-01T00:00:00Z "@owner 予約できませんでした。

${MARKER}")" >"$WORK/comments.json"
run_strict notice_post 12 "$MARKER" "$WORK/body.md" yes
check_exit 0 "同じ目印のコメントが既にあれば 0 を返す"
check_not_called "$POST_RE" "同じ目印のコメントが既にあれば付けない"

reset
pages "$(comment 1 someone 2026-01-01T00:00:00Z "1ページ目")" -- \
    "$(comment 2 "$BOT" 2026-01-02T00:00:00Z "本文 ${MARKER}")" >"$WORK/comments.json"
run_strict notice_post 12 "$MARKER" "$WORK/body.md" yes
check_exit 0 "目印が2ページ目にあっても 0 を返す"
check_not_called "$POST_RE" "目印が2ページ目にあっても見つけて付けない"

echo "--- 2度続けて呼んでも知らせは1件(要件 2.8・5.3) ---"
reset
run_strict notice_post 12 "$MARKER" "$WORK/body.md" yes
posted=""
for f in "$WORK"/bodies/*.txt; do
    [ -f "$f" ] && posted="$f"
done
if [ -n "$posted" ]; then
    pages "$(comment 5 "$BOT" 2026-01-03T00:00:00Z "$(cat "$posted")")" >"$WORK/comments.json"
fi
run_strict notice_post 12 "$MARKER" "$WORK/body.md" yes
check_exit 0 "1度目に付けたコメントが一覧にあれば、2度目は 0 を返す"
check_post_count 1 "1度目に付けたコメントを2度目が見つけ、知らせを増やさない"

echo "--- 別の目印・他人が書いた目印は数えない(目印の偽装) ---"
reset
pages "$(comment 1 "$BOT" 2026-01-01T00:00:00Z "<!-- auto-merge-notice kind=failed head=000000 -->")" \
    "$(comment 2 "$BOT" 2026-01-01T00:00:00Z "<!-- auto-merge-notice kind=stopped head=abc123 -->")" >"$WORK/comments.json"
run_strict notice_post 12 "$MARKER" "$WORK/body.md" yes
check_exit 0 "別のコミット・別の種類の目印しか無ければ付けて 0 を返す"
check_post_count 1 "別のコミット・別の種類の目印は同じ知らせとして数えない"

reset
pages "$(comment 1 someone 2026-01-01T00:00:00Z "$MARKER")" \
    "$(comment 2 github-actions 2026-01-01T00:00:00Z "$MARKER")" \
    "$(comment 3 owner 2026-01-01T00:00:00Z "$MARKER")" >"$WORK/comments.json"
run_strict notice_post 12 "$MARKER" "$WORK/body.md" yes
check_exit 0 "他人が同じ目印を書いていても付けて 0 を返す"
check_post_count 1 "他人(名前が似た利用者・所有者を含む)が書いた同じ目印は数えない"

reset
export NOTICE_AUTHOR="keirekipro-bot"
pages "$(comment 1 "$BOT" 2026-01-01T00:00:00Z "$MARKER")" >"$WORK/comments.json"
run_strict notice_post 12 "$MARKER" "$WORK/body.md" yes
check_post_count 1 "NOTICE_AUTHOR を指定したら、既定の作成者が書いた目印は数えない"
reset
export NOTICE_AUTHOR="keirekipro-bot"
pages "$(comment 1 keirekipro-bot 2026-01-01T00:00:00Z "$MARKER")" >"$WORK/comments.json"
run_strict notice_post 12 "$MARKER" "$WORK/body.md" yes
check_exit 0 "NOTICE_AUTHOR が書いた目印があれば 0 を返す"
check_not_called "$POST_RE" "NOTICE_AUTHOR が書いた目印があれば付けない"

echo "--- コメントの一覧を読めないときは付けない ---"
reset
export STUB_FAIL_ON=list
run_rc notice_post 12 "$MARKER" "$WORK/body.md" yes
check_exit 1 "コメントの一覧を取れなければ 1 を返す"
check_not_called "$POST_RE" "コメントの一覧を取れなければ付けない(重複を作らない)"

reset
printf 'not json' >"$WORK/comments.json"
run_rc notice_post 12 "$MARKER" "$WORK/body.md" yes
check_exit 1 "コメントの一覧を解釈できなければ 1 を返す"
check_not_called "$POST_RE" "コメントの一覧を解釈できなければ付けない"

reset
printf '{"message": "Not Found"}\n' >"$WORK/comments.json"
run_rc notice_post 12 "$MARKER" "$WORK/body.md" yes
check_exit 1 "コメントの一覧が配列でなければ 1 を返す"
check_not_called "$POST_RE" "コメントの一覧が配列でなければ付けない"

reset
: >"$WORK/comments.json"
run_rc notice_post 12 "$MARKER" "$WORK/body.md" yes
check_exit 1 "コメントの一覧の応答が空なら 1 を返す"
check_not_called "$POST_RE" "コメントの一覧の応答が空なら付けない"

reset
printf '[{"id": 1, "body": 5}]\n' >"$WORK/comments.json"
run_rc notice_post 12 "$MARKER" "$WORK/body.md" yes
check_exit 1 "コメントの形が想定と違えば 1 を返す"
check_not_called "$POST_RE" "コメントの形が想定と違えば付けない"

echo "--- コメントを付けられない・引数や環境変数の不足 ---"
reset
export STUB_FAIL_ON=post
run_rc notice_post 12 "$MARKER" "$WORK/body.md" yes
check_exit 1 "コメントに失敗したら 1 を返す"

reset
run_rc notice_post abc "$MARKER" "$WORK/body.md" yes
check_exit 1 "番号が数字でなければ 1 を返す"
check_not_called '.' "番号が不正なら gh を呼ばない"

reset
run_rc notice_post 12 "" "$WORK/body.md" yes
check_exit 1 "目印が空なら 1 を返す"
check_not_called '.' "目印が空なら gh を呼ばない"

reset
run_rc notice_post 12 "$MARKER" "$WORK/missing.md" yes
check_exit 1 "本文のファイルが無ければ 1 を返す"
check_not_called '.' "本文のファイルが無ければ gh を呼ばない"

reset
run_rc notice_post 12 "$MARKER" "$WORK/body.md" maybe
check_exit 1 "mention が yes でも no でもなければ 1 を返す"
check_not_called '.' "mention が不正なら gh を呼ばない"

for v in GH_TOKEN GITHUB_REPOSITORY GITHUB_REPOSITORY_OWNER; do
    reset
    unset "$v"
    run_rc notice_post 12 "$MARKER" "$WORK/body.md" no
    check_exit 1 "${v} が無ければ 1 を返す"
    check_not_called '.' "${v} が無ければ gh を呼ばない"
done

echo "--- 最新の知らせの種類を取り出す ---"
# 一覧の並びと作成日時の順をわざとずらし、作成日時で新旧を比べることを確かめる
reset
pages "$(comment 4 "$BOT" 2026-01-04T00:00:00Z "@owner 止めました。

<!-- auto-merge-notice kind=stopped head=def456 -->")" \
    "$(comment 1 "$BOT" 2026-01-01T00:00:00Z "<!-- auto-merge-notice kind=failed head=abc123 -->")" -- \
    "$(comment 3 "$BOT" 2026-01-03T00:00:00Z "予約が付きました。

<!-- auto-merge-notice kind=resolved head=abc123 -->")" \
    "$(comment 2 "$BOT" 2026-01-02T00:00:00Z "目印の無いコメント")" >"$WORK/comments.json"
run_strict notice_last_kind 12 auto-merge-notice
check_exit 0 "一覧を読めれば 0 を返す"
check_out "stopped" "作成日時がいちばん新しい知らせの kind を出す(ページをまたぐ)"
check_called '^api --paginate repos/owner/repo/issues/12/comments$' "種類の取り出しも REST の Issue コメントの一覧で読む"
check_not_called "$POST_RE" "種類の取り出しでは何も書き込まない"

reset
pages "$(comment 1 "$BOT" 2026-01-01T00:00:00Z "<!-- auto-merge-notice kind=failed head=abc123 -->")" \
    "$(comment 2 someone 2026-01-05T00:00:00Z "<!-- auto-merge-notice kind=resolved head=abc123 -->")" \
    "$(comment 3 "$BOT" 2026-01-06T00:00:00Z "<!-- issue-close-notice pr=12 kind=refs-only -->")" \
    "$(comment 4 "$BOT" 2026-01-07T00:00:00Z "<!-- auto-merge-notice-extra kind=other head=abc123 -->")" >"$WORK/comments.json"
run_strict notice_last_kind 12 auto-merge-notice
check_out "failed" "他人が書いた目印と、接頭辞が違う目印は数えない"
run_strict notice_last_kind 12 issue-close-notice
check_out "refs-only" "kind が目印の途中にあっても、ハイフンを含んでいても取り出す"

reset
pages "$(comment 1 "$BOT" 2026-01-01T00:00:00Z "関係のないコメント")" >"$WORK/comments.json"
run_strict notice_last_kind 12 auto-merge-notice
check_exit 0 "知らせが無くても 0 を返す"
check_out "" "知らせが無ければ何も出さない"

reset
export STUB_FAIL_ON=list
run_rc notice_last_kind 12 auto-merge-notice
check_exit 1 "種類の取り出しで一覧を取れなければ 1 を返す"
check_out "" "一覧を取れなければ何も出さない"

reset
printf '{"message": "Not Found"}\n' >"$WORK/comments.json"
run_rc notice_last_kind 12 auto-merge-notice
check_exit 1 "種類の取り出しで一覧が配列でなければ 1 を返す"

reset
run_rc notice_last_kind 12 ""
check_exit 1 "接頭辞が空なら 1 を返す"
check_not_called '.' "接頭辞が空なら gh を呼ばない"

reset
run_rc notice_last_kind 12 'auto.*'
check_exit 1 "接頭辞に英数字・ハイフン・下線以外があれば 1 を返す"
check_not_called '.' "接頭辞が不正なら gh を呼ばない"

reset
run_rc notice_last_kind abc auto-merge-notice
check_exit 1 "種類の取り出しで番号が数字でなければ 1 を返す"
check_not_called '.' "種類の取り出しで番号が不正なら gh を呼ばない"

if [ "$FAILED" -eq 0 ]; then
    echo "すべてのテストがPASSしました。"
else
    echo "失敗したテストがあります。"
fi
exit "$FAILED"
