#!/usr/bin/env bash
# =====================================================================
# lib-ledger-issue.sh の自動テスト(audit-inventory / mutation-report CI から実行)
#
# gh をスタブし、台帳のIssueの探し方・作成・ラベルの作成・コメント・
# 担当者の割り当て・本文への追記と、各関数の戻り値を検証する。
#
# スタブは呼び出しを1行1件で記録し、--body-file で渡した本文は
# 「記録の行番号.txt」に写す。テスト側はその記録を突き合わせる。
# 外部への問い合わせを行わないため、実行にネットワークを必要としない。
#
# ライブラリは呼び出し側と同じ厳しい設定(set -Eeuo pipefail と ERR の trap)の
# 下で source して呼ぶ。関数の中の失敗が呼び出し側の trap に漏れて、
# 警告で済ませるはずの失敗が実行全体を止めないことを確かめるため。
# =====================================================================
set -uo pipefail

LIB="$(cd "$(dirname "$0")/.." && pwd)/lib-ledger-issue.sh"
WORK=$(mktemp -d) || exit 1
[ -n "$WORK" ] && [ -d "$WORK" ] || exit 1
trap 'rm -rf "$WORK"' EXIT
FAILED=0

mkdir -p "$WORK/bin" "$WORK/bodies"
CALLS="$WORK/calls.log"
OUT="$WORK/out.txt"
ERR_OUT="$WORK/err.txt"
TITLE="棚卸し台帳: 版とサポート期限"

# --- gh のスタブ -------------------------------------------------------------
# 呼び出しの種類(STUB_FAIL_ON に指定すると、その種類だけ失敗させる):
#   list    api で Issue 一覧(--paginate)  → $STUB_ISSUES を返す
#   get     api repos/…/issues/<N>        → $STUB_ISSUE に --jq の式を適用する
#   assign  api …/assignees               → $STUB_ASSIGN を返す
#   create  issue create                  → $STUB_CREATE_OUTPUT(既定は Issue のURL)を返す
#   comment issue comment
#   edit    issue edit
#   label   label create
cat >"$WORK/bin/gh" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"${STUB_CALLS:?}"
n=$(wc -l <"$STUB_CALLS" | tr -d ' ')
body_file="" jq_prog="" prev=""
for a in "$@"; do
    [ "$prev" = "--body-file" ] && body_file="$a"
    [ "$prev" = "--jq" ] && jq_prog="$a"
    prev="$a"
done
if [ -n "$body_file" ]; then
    cp "$body_file" "${STUB_BODIES:?}/${n}.txt" || exit 1
fi
kind=""
case "$1 ${2:-}" in
    "issue create") kind=create ;;
    "issue comment") kind=comment ;;
    "issue edit") kind=edit ;;
    "label create") kind=label ;;
    api\ *)
        case " $* " in
            */assignees*) kind=assign ;;
            *--paginate*) kind=list ;;
            *) kind=get ;;
        esac
        ;;
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
    list) cat "${STUB_ISSUES:?}" ;;
    get)
        if [ -n "$jq_prog" ]; then
            jq -r "$jq_prog" "${STUB_ISSUE:?}"
        else
            cat "${STUB_ISSUE:?}"
        fi
        ;;
    assign) cat "${STUB_ASSIGN:?}" ;;
    create) printf '%s\n' "${STUB_CREATE_OUTPUT-https://github.com/owner/repo/issues/100}" ;;
esac
exit 0
STUB
chmod +x "$WORK/bin/gh"

# --- 入力の組み立て ---------------------------------------------------------
# gh api --paginate(--slurp なし)は、ページごとの配列を続けて出力する。
# 2ページに分けて置き、ページをまたいで探せることも確かめる。
PAGE1="[{\"number\": 2, \"title\": \"${TITLE}\", \"pull_request\": {}},
 {\"number\": 3, \"title\": \"別のIssue\"},
 {\"number\": 4, \"title\": \"${TITLE}(旧)\"},
 {\"number\": 9, \"title\": \"${TITLE}\", \"state\": \"open\"}]"
PAGE2="[{\"number\": 7, \"title\": \"${TITLE}\", \"state\": \"closed\"},
 {\"number\": 5, \"title\": \" ${TITLE}\"}]"

reset() {
    printf '%s\n%s\n' "$PAGE1" "$PAGE2" >"$WORK/issues.json"
    jq -n '{number: 7, body: "台帳の説明\n\n| 列 |\n|---|\n| 1行目 |\n"}' >"$WORK/issue.json"
    printf '{"number":7,"assignees":[{"login":"owner"}]}' >"$WORK/assign.json"
    printf '台帳の説明の1行目\n2行目\n' >"$WORK/initial.md"
    printf '| 対象 | 版 |\n|---|---|\n| tflint | 0.1 |\n' >"$WORK/comment.md"
    printf '| 2026-01-10 | 差分 |\n' >"$WORK/append.md"
    unset STUB_FAIL_ON STUB_CREATE_OUTPUT
    export GH_TOKEN="dummy" GITHUB_REPOSITORY="owner/repo" GITHUB_REPOSITORY_OWNER="owner"
    : >"$CALLS"
    rm -f "$WORK"/bodies/*.txt
}

# 使い方: run_strict <関数名> <引数...>
# 呼び出し側と同じ厳しい設定で source し、関数をそのまま呼ぶ。関数が 0 以外を
# 返すか、関数の中の失敗が trap に漏れると、終了コード 90 で止まる。
LAST_EXIT=0
run_strict() {
    PATH="$WORK/bin:$PATH" STUB_CALLS="$CALLS" STUB_BODIES="$WORK/bodies" \
        STUB_ISSUES="$WORK/issues.json" STUB_ISSUE="$WORK/issue.json" STUB_ASSIGN="$WORK/assign.json" \
        bash -c 'set -Eeuo pipefail; trap "exit 90" ERR; source "$1"; shift; "$@"; echo "呼び出し元が続く" >&2' \
        _ "$LIB" "$@" >"$OUT" 2>"$ERR_OUT"
    LAST_EXIT=$?
}

# 使い方: run_rc <関数名> <引数...>
# 関数の戻り値をそのまま終了コードにする(失敗の戻り値を確かめるため)。
run_rc() {
    PATH="$WORK/bin:$PATH" STUB_CALLS="$CALLS" STUB_BODIES="$WORK/bodies" \
        STUB_ISSUES="$WORK/issues.json" STUB_ISSUE="$WORK/issue.json" STUB_ASSIGN="$WORK/assign.json" \
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

# 使い方: check_warning <説明>
check_warning() {
    if grep -qF "::warning::" "$OUT" "$ERR_OUT"; then
        pass "$1"
    else
        fail "$1"
    fi
}

# 使い方: body_of <呼び出しの記録に一致する正規表現>
# その呼び出しに渡された本文のファイルのパスを出す(無ければ空)
body_of() {
    local n
    n=$(grep -nE -- "$1" "$CALLS" | head -n 1 | cut -d: -f1)
    if [ -n "$n" ] && [ -f "$WORK/bodies/${n}.txt" ]; then
        printf '%s' "$WORK/bodies/${n}.txt"
    fi
}

# 使い方: check_body_equals <呼び出しの正規表現> <期待する本文のファイル> <説明>
check_body_equals() {
    local f
    f=$(body_of "$1")
    if [ -n "$f" ] && cmp -s "$f" "$2"; then
        pass "$3"
    else
        fail "$3"
        [ -z "$f" ] || echo "     実際: $(tr '\n' '|' <"$f")"
        echo "     期待: $(tr '\n' '|' <"$2")"
    fi
}

# Issue 番号を指定する操作(コメント・編集・本文の取得・担当者)が、
# 指定の番号だけに向いていることを確かめる(要件6-4)
# 使い方: check_only_issue <番号> <説明>
check_only_issue() {
    local others
    others=$(grep -E '^(issue (comment|edit) |api .*issues/[0-9]+)' "$CALLS" |
        grep -vE "^issue (comment|edit) $1 |issues/$1(/| |\$)" || true)
    if [ -z "$others" ]; then
        pass "$2"
    else
        fail "$2 (他のIssueへの操作: $(printf '%s' "$others" | tr '\n' '|'))"
    fi
}

echo "--- source しただけでは何もしない ---"
reset
PATH="$WORK/bin:$PATH" STUB_CALLS="$CALLS" STUB_BODIES="$WORK/bodies" \
    bash -c 'set -Eeuo pipefail; before="$-|$(shopt -po)|$(trap -p)"; source "$1"; after="$-|$(shopt -po)|$(trap -p)"; [ "$before" = "$after" ]' \
    _ "$LIB" >"$OUT" 2>"$ERR_OUT"
LAST_EXIT=$?
check_exit 0 "source してもシェルの設定と trap を変えない"
if [ ! -s "$OUT" ] && [ ! -s "$ERR_OUT" ] && [ ! -s "$CALLS" ]; then
    pass "source しただけでは出力も gh の呼び出しも無い"
else
    fail "source しただけでは出力も gh の呼び出しも無い"
fi

echo "--- 台帳を探す(要件2-4・6-4) ---"
reset
run_strict ledger_find_or_create "$TITLE" "$WORK/initial.md" audit
check_exit 0 "台帳があれば 0 を返す"
check_out "7" "タイトルが完全一致するIssueのうち、状態を問わず最小の番号を出す(PR・前後が違うタイトルを除く)"
check_called '^api .*--paginate' "Issue一覧はページ送りで取る"
check_called 'issues\?(.*&)?state=all' "閉じたIssueも探す"
check_not_called '^issue create' "台帳があれば作らない"
check_not_called '^label create' "台帳があればラベルを作らない"
check_not_called '^issue (comment|edit)|assignees' "探すだけでは台帳にもそれ以外のIssueにも書き込まない"

echo "--- 台帳が無ければ作る(要件2-4) ---"
reset
printf '[{"number": 3, "title": "別のIssue"}, {"number": 4, "title": "%s(旧)"}]\n[]\n' "$TITLE" >"$WORK/issues.json"
run_strict ledger_find_or_create "$TITLE" "$WORK/initial.md" audit
check_exit 0 "台帳が無ければ作って 0 を返す"
check_out "100" "作ったIssueの番号を出す"
check_called "^issue create .*--title ${TITLE}( |\$)" "決まったタイトルで作る"
check_called '^issue create .*--label audit( |$)' "指定のラベルを付けて作る"
check_called '^issue create .*--repo owner/repo( |$)' "リポジトリを指定して作る"
check_body_equals '^issue create ' "$WORK/initial.md" "本文はファイルの中身のまま"
check_called '^label create audit( |$)' "ラベルが無いときに備えてラベルを作る"
check_not_called '^issue (comment|edit)|assignees' "作るときに他のIssueに触らない"

reset
printf '[]\n' >"$WORK/issues.json"
run_strict ledger_find_or_create "$TITLE" "$WORK/initial.md" ""
check_exit 0 "ラベルが空でも作って 0 を返す"
check_not_called '^issue create .*--label' "ラベルが空なら付けない"
check_not_called '^label create' "ラベルが空ならラベルを作らない"

reset
printf '[]\n' >"$WORK/issues.json"
export STUB_FAIL_ON=label
run_strict ledger_find_or_create "$TITLE" "$WORK/initial.md" audit
check_exit 0 "ラベルの作成の失敗(既にある場合を含む)は無視して作る"
check_out "100" "ラベルの作成に失敗しても作ったIssueの番号を出す"

reset
printf '[]\n' >"$WORK/issues.json"
export STUB_CREATE_OUTPUT="Creating issue in owner/repo

https://github.com/owner/repo/issues/123"
run_strict ledger_find_or_create "$TITLE" "$WORK/initial.md" audit
check_out "123" "作成の出力の最後のURLから番号を読む"

echo "--- 台帳を探せない・作れない ---"
reset
export STUB_FAIL_ON=list
run_rc ledger_find_or_create "$TITLE" "$WORK/initial.md" audit
check_exit 1 "Issue一覧を取れなければ 1 を返す"
check_not_called '^issue create' "一覧を取れないときは作らない(重複を作らない)"

reset
printf 'not json' >"$WORK/issues.json"
run_rc ledger_find_or_create "$TITLE" "$WORK/initial.md" audit
check_exit 1 "Issue一覧を解釈できなければ 1 を返す"
check_not_called '^issue create' "一覧を解釈できないときは作らない"

reset
printf '[]\n' >"$WORK/issues.json"
export STUB_FAIL_ON=create
run_rc ledger_find_or_create "$TITLE" "$WORK/initial.md" audit
check_exit 1 "作成に失敗したら 1 を返す"
check_out "" "作成に失敗したら番号を出さない"

reset
printf '[]\n' >"$WORK/issues.json"
export STUB_CREATE_OUTPUT="予期しない出力"
run_rc ledger_find_or_create "$TITLE" "$WORK/initial.md" audit
check_exit 1 "作成の出力から番号を読めなければ 1 を返す"

reset
run_rc ledger_find_or_create "$TITLE" "$WORK/missing.md" audit
check_exit 1 "本文のファイルが無ければ 1 を返す"
check_not_called '.' "本文のファイルが無ければ gh を呼ばない"

reset
run_rc ledger_find_or_create "" "$WORK/initial.md" audit
check_exit 1 "タイトルが空なら 1 を返す"
check_not_called '.' "タイトルが空なら gh を呼ばない"

reset
unset GITHUB_REPOSITORY
run_rc ledger_find_or_create "$TITLE" "$WORK/initial.md" audit
check_exit 1 "GITHUB_REPOSITORY が無ければ 1 を返す"
check_not_called '.' "GITHUB_REPOSITORY が無ければ gh を呼ばない"

echo "--- 台帳にコメントする(要件2-2・2-3・3-3) ---"
reset
run_strict ledger_comment 7 "$WORK/comment.md"
check_exit 0 "コメントと担当者の割り当てができれば 0 を返す"
check_called '^issue comment 7 .*--repo owner/repo( |$)' "指定の番号のIssueにコメントする"
printf '@owner | 対象 | 版 |\n|---|---|\n| tflint | 0.1 |\n' >"$WORK/expected-comment.md"
check_body_equals '^issue comment 7 ' "$WORK/expected-comment.md" "先頭行の頭に所有者へのメンションを付け、残りは変えない"
check_called '^api -X POST repos/owner/repo/issues/7/assignees -f assignees\[\]=owner$' "所有者を担当者に割り当てる"
comment_line=$(grep -nE '^issue comment' "$CALLS" | head -n 1 | cut -d: -f1)
assign_line=$(grep -nE 'assignees' "$CALLS" | head -n 1 | cut -d: -f1)
if [ -n "$comment_line" ] && [ -n "$assign_line" ] && [ "$comment_line" -lt "$assign_line" ]; then
    pass "コメントの後に担当者を割り当てる"
else
    fail "コメントの後に担当者を割り当てる"
fi
check_only_issue 7 "指定の番号のIssue以外に書き込まない"
printf '| 対象 | 版 |\n|---|---|\n| tflint | 0.1 |\n' >"$WORK/comment-original.md"
if cmp -s "$WORK/comment.md" "$WORK/comment-original.md"; then
    pass "渡した本文のファイルを書き換えない"
else
    fail "渡した本文のファイルを書き換えない"
fi

reset
export STUB_FAIL_ON=assign
run_strict ledger_comment 7 "$WORK/comment.md"
check_exit 0 "担当者の割り当てのAPIが失敗しても 0 を返す(呼び出し元の trap に漏れない)"
check_warning "担当者の割り当ての失敗は警告を出す"
if grep -qF "呼び出し元が続く" "$ERR_OUT"; then
    pass "担当者の割り当ての失敗の後も呼び出し元が続く"
else
    fail "担当者の割り当ての失敗の後も呼び出し元が続く"
fi

reset
printf '{"number":7,"assignees":[]}' >"$WORK/assign.json"
run_strict ledger_comment 7 "$WORK/comment.md"
check_exit 0 "担当者が付かなかった(無視された)ときも 0 を返す"
check_warning "担当者が付かなかったときは警告を出す"

reset
export STUB_FAIL_ON=comment
run_rc ledger_comment 7 "$WORK/comment.md"
check_exit 1 "コメントに失敗したら 1 を返す"
check_not_called 'assignees' "コメントに失敗したら担当者を割り当てない"

reset
unset GITHUB_REPOSITORY_OWNER
run_rc ledger_comment 7 "$WORK/comment.md"
check_exit 1 "GITHUB_REPOSITORY_OWNER が無ければ 1 を返す"
check_not_called '.' "GITHUB_REPOSITORY_OWNER が無ければ gh を呼ばない"

reset
unset GH_TOKEN
run_rc ledger_comment 7 "$WORK/comment.md"
check_exit 1 "GH_TOKEN が無ければ 1 を返す"
check_not_called '.' "GH_TOKEN が無ければ gh を呼ばない"

reset
run_rc ledger_comment abc "$WORK/comment.md"
check_exit 1 "番号が数字でなければ 1 を返す"
check_not_called '.' "番号が不正なら gh を呼ばない"

reset
run_rc ledger_comment 7 "$WORK/missing.md"
check_exit 1 "コメントの本文のファイルが無ければ 1 を返す"
check_not_called '.' "本文のファイルが無ければ gh を呼ばない"

echo "--- 本文の末尾に追記する(通知なし) ---"
reset
run_strict ledger_append_body 7 "$WORK/append.md"
check_exit 0 "追記できれば 0 を返す"
check_called '^issue edit 7 .*--repo owner/repo( |$)' "指定の番号のIssueの本文を編集する"
printf '台帳の説明\n\n| 列 |\n|---|\n| 1行目 |\n| 2026-01-10 | 差分 |\n' >"$WORK/expected-append.md"
check_body_equals '^issue edit 7 ' "$WORK/expected-append.md" "今の本文を残し、末尾に追記する"
check_not_called '^issue comment|assignees' "追記ではコメントせず、担当者も変えない(通知しない)"
check_only_issue 7 "追記は指定の番号のIssue以外に触らない"

reset
jq -n '{number: 7, body: null}' >"$WORK/issue.json"
run_strict ledger_append_body 7 "$WORK/append.md"
check_exit 0 "本文が空の台帳にも追記できる"
check_body_equals '^issue edit 7 ' "$WORK/append.md" "本文が空なら追記の中身だけになる"

reset
export STUB_FAIL_ON=get
run_rc ledger_append_body 7 "$WORK/append.md"
check_exit 1 "本文を取れなければ 1 を返す"
check_not_called '^issue edit' "本文を取れなければ編集しない(本文を消さない)"

reset
export STUB_FAIL_ON=edit
run_rc ledger_append_body 7 "$WORK/append.md"
check_exit 1 "編集に失敗したら 1 を返す"

reset
run_rc ledger_append_body 7 "$WORK/missing.md"
check_exit 1 "追記の中身のファイルが無ければ 1 を返す"
check_not_called '.' "追記の中身のファイルが無ければ gh を呼ばない"

if [ "$FAILED" -eq 0 ]; then
    echo "すべてのテストがPASSしました。"
else
    echo "失敗したテストがあります。"
fi
exit "$FAILED"
