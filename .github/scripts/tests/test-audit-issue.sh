#!/usr/bin/env bash
# =====================================================================
# audit-issue.sh の自動テスト
#
# gh をシムして、呼ばれたIssue操作の列と終了コードを検証する。
# シムは呼び出しを1行1件で記録し、本文(--body / --body-file)は呼び出しごとに
# 別ファイルへ保存する。テスト側はその記録を突き合わせる。
#
# 実際のAPIは叩かない。監査の通知は「起票・追記・クローズ」の
# どれが呼ばれるかがすべてなので、状態遷移表の全組み合わせをここで固定する。
# =====================================================================
set -uo pipefail

SCRIPT="$(cd "$(dirname "$0")/.." && pwd)/audit-issue.sh"
WORK=$(mktemp -d) || exit 1
[ -n "$WORK" ] && [ -d "$WORK" ] || exit 1
trap 'rm -rf "$WORK"' EXIT
FAILED=0

mkdir -p "$WORK/bin" "$WORK/bodies"
PATH="$WORK/bin:$PATH"
export PATH

CALLS="$WORK/calls.log"
API_FIXTURE="$WORK/api.json"
REPORT="$WORK/report.md"
OUT="$WORK/out.txt"
RUN_URL="https://github.com/owner/repo/actions/runs/12345"

# gh のシム。
# - 記録の形式:
#     issue create title=<t> label=<l> assignee=<a>
#     issue comment <番号>
#     issue close <番号>
#     label create <名前>
#     api <引数をそのまま空白区切り>
# - --body の中身、または --body-file で渡したファイルの中身を
#   「記録の行番号.txt」に保存する
# - GH_FAIL_ON に「サブコマンド」か「サブコマンド 操作」を指定すると失敗させる。
#   終了コードは GH_FAIL_CODE(既定 1)。api の操作は、引数に /assignees を
#   含めば「assignees」、それ以外は「search」とする
# - 担当者の追加(api .../assignees)の応答は $ASSIGN_FIXTURE_PATH の内容を、
#   それ以外の api の応答は $API_FIXTURE_PATH の内容を返す
# - issue create の出力は GH_CREATE_OUTPUT があればそれ、無ければ Issue のURL
cat >"$WORK/bin/gh" <<'SHIM'
#!/usr/bin/env bash
sub="${1:-}"
action="${2:-}"
title="" label="" assignee="" body="" has_body=0 positional=""
if [ "$sub" = "api" ]; then
    action="search"
    case " $* " in
        */assignees*) action="assignees" ;;
    esac
fi
if [ "$sub" = "issue" ] || [ "$sub" = "label" ]; then
    shift 2
    while [ $# -gt 0 ]; do
        case "$1" in
            --title) title="$2"; shift ;;
            --label) label="$2"; shift ;;
            --assignee) assignee="$2"; shift ;;
            --body) body="$2"; has_body=1; shift ;;
            --body-file) body=$(cat "$2"; printf x); body="${body%x}"; has_body=1; shift ;;
            --*) shift ;;
            *) [ -n "$positional" ] || positional="$1" ;;
        esac
        shift
    done
fi
case "$sub" in
    issue)
        if [ "$action" = "create" ]; then
            line="issue create title=${title} label=${label} assignee=${assignee}"
        else
            line="issue ${action} ${positional}"
        fi
        ;;
    label) line="label ${action} ${positional}" ;;
    *) line="$*" ;;
esac
printf '%s\n' "$line" >>"$CALLS_LOG"
if [ "$has_body" -eq 1 ]; then
    n=$(wc -l <"$CALLS_LOG" | tr -d ' ')
    printf '%s' "$body" >"${BODY_DIR}/${n}.txt"
fi
if [ -n "${GH_FAIL_ON:-}" ] && { [ "$GH_FAIL_ON" = "$sub" ] || [ "$GH_FAIL_ON" = "$sub $action" ]; }; then
    echo "gh: 失敗をシミュレート" >&2
    exit "${GH_FAIL_CODE:-1}"
fi
case "$sub" in
    api)
        if [ "$action" = "assignees" ]; then
            cat "$ASSIGN_FIXTURE_PATH"
        else
            cat "$API_FIXTURE_PATH"
        fi
        ;;
    issue)
        if [ "$action" = "create" ]; then
            printf '%s\n' "${GH_CREATE_OUTPUT-https://github.com/owner/repo/issues/100}"
        fi
        ;;
esac
exit 0
SHIM
chmod +x "$WORK/bin/gh"
ASSIGN_FIXTURE="$WORK/assign.json"
export CALLS_LOG="$CALLS"
export API_FIXTURE_PATH="$API_FIXTURE"
export ASSIGN_FIXTURE_PATH="$ASSIGN_FIXTURE"
export BODY_DIR="$WORK/bodies"

set_env() {
    export GH_TOKEN="dummy-token"
    export GITHUB_REPOSITORY="owner/repo"
    export GITHUB_REPOSITORY_OWNER="owner"
    export GITHUB_SERVER_URL="https://github.com"
    export GITHUB_RUN_ID="12345"
}
set_env

# 使い方: setup <open issues json(カンマ区切りの要素列)>
setup() {
    # gh api --paginate --slurp は「ページの配列」を返す。
    # ページ1つの中にIssueの配列が入るので2段包む。
    printf '[[%s]]' "$1" >"$API_FIXTURE"
    # 担当者の追加の応答は、既定では所有者が付いた Issue を返す
    printf '{"number":100,"assignees":[{"login":"owner"}]}' >"$ASSIGN_FIXTURE"
    printf '## 判定項目\n\nREPORT-MARKER-7f3a: PR #342 が滞留している\n' >"$REPORT"
    : >"$CALLS"
    rm -f "$WORK"/bodies/*.txt
}

# 使い方: run <kind> <result> [report-file]
LAST_EXIT=0
run() {
    bash "$SCRIPT" "$@" >"$OUT" 2>&1
    LAST_EXIT=$?
}

pass() { echo "ok   $1"; }
fail() {
    echo "FAIL $1"
    FAILED=1
}

# 使い方: check_exit <期待exit> <説明>
check_exit() {
    if [ "$LAST_EXIT" -eq "$1" ]; then
        pass "$2"
    else
        fail "$2 (期待 exit=$1 / 実際 exit=${LAST_EXIT})"
        sed 's/^/     | /' "$OUT"
    fi
}

# 使い方: check_calls <期待する呼び出し(改行区切り)> <説明>
# 比較するのは起票・追記・クローズの3種だけ。検索とラベル作成は別に検証する。
check_calls() {
    local want="$1" name="$2" got
    got=$(grep -E '^issue (create|comment|close) ' "$CALLS" || true)
    if [ "$got" = "$want" ]; then
        pass "$name"
    else
        fail "$name"
        echo "     期待: $(printf '%s' "$want" | tr '\n' '|')"
        echo "     実際: $(printf '%s' "$got" | tr '\n' '|')"
    fi
}

# 使い方: check_no_gh <説明>
# 入力が不正なら gh を一度も呼ばない(ラベル作成も検索もしない)
check_no_gh() {
    if [ ! -s "$CALLS" ]; then
        pass "$1"
    else
        fail "$1"
        echo "     実際: $(tr '\n' '|' <"$CALLS")"
    fi
}

# 使い方: body_file_of <記録の行に完全一致する文字列>
# その呼び出しに渡された本文を保存したファイルのパスを出力する(無ければ失敗)。
# 検索はファイルに対して行う。printf "$body" | grep -q の形は、grep が
# 一致した時点で抜けて printf が SIGPIPE を受け、pipefail で偽になりうる
# (本文が大きい切り詰めのケースで起きる)
body_file_of() {
    local n
    n=$(grep -nxF "$1" "$CALLS" | head -n 1 | cut -d: -f1)
    [ -n "$n" ] && [ -f "$WORK/bodies/${n}.txt" ] && printf '%s' "$WORK/bodies/${n}.txt"
}

# 使い方: check_body_has <記録の行> <含むべき文字列> <説明>
check_body_has() {
    local f
    f=$(body_file_of "$1" || true)
    if [ -n "$f" ] && grep -qF -- "$2" "$f"; then
        pass "$3"
    else
        fail "$3"
        [ -z "$f" ] || echo "     本文: $(head -c 300 "$f" | tr '\n' '|')"
    fi
}

W_DEV="週次監査: 逸脱あり"
W_UND="週次監査: 判定不能"
C_DEV="カナリア照合: 逸脱あり"
C_UND="カナリア照合: 判定不能"

DEV='{"number":10,"title":"週次監査: 逸脱あり"}'
UND='{"number":20,"title":"週次監査: 判定不能"}'

# 起票では --assignee を渡さない(assignee= が空)。担当者は起票の後に
# REST で追加する。--assignee は担当者を解決できないと起票そのものを
# 失敗させうるため(2.2 で変更)
CREATE_W_DEV="issue create title=${W_DEV} label=audit assignee="
CREATE_W_UND="issue create title=${W_UND} label=audit assignee="
CREATE_C_DEV="issue create title=${C_DEV} label=audit assignee="
CREATE_C_UND="issue create title=${C_UND} label=audit assignee="

# ---------------------------------------------------------------------
# 1. 状態遷移表: 結果「逸脱なし」(要件 2.4, 3.4)
# ---------------------------------------------------------------------
setup ""
run weekly none "$REPORT"
check_exit 0 "逸脱なし・既存なし: 正常終了する"
check_calls "" "逸脱なし・既存なし: 何も操作しない"

setup "$DEV"
run weekly none "$REPORT"
check_exit 0 "逸脱なし・逸脱のIssueあり: 正常終了する"
check_calls "issue comment 10
issue close 10" "逸脱なし・逸脱のIssueあり: 解消を追記して閉じる"

setup "$UND"
run weekly none "$REPORT"
check_exit 0 "逸脱なし・判定不能のIssueあり: 正常終了する"
check_calls "issue comment 20
issue close 20" "逸脱なし・判定不能のIssueあり: 解消を追記して閉じる"

setup "${DEV}, ${UND}"
run weekly none "$REPORT"
check_exit 0 "逸脱なし・両方あり: 正常終了する"
check_calls "issue comment 10
issue close 10
issue comment 20
issue close 20" "逸脱なし・両方あり: 両方に解消を追記して閉じる"

# ---------------------------------------------------------------------
# 2. 状態遷移表: 結果「逸脱あり」(要件 2.1, 2.2, 3.4)
# ---------------------------------------------------------------------
setup ""
run weekly deviation "$REPORT"
check_exit 0 "逸脱あり・既存なし: 正常終了する"
check_calls "$CREATE_W_DEV" "逸脱あり・既存なし: ラベルを付けて逸脱のIssueを起票する"

setup "$DEV"
run weekly deviation "$REPORT"
check_exit 0 "逸脱あり・逸脱のIssueあり: 正常終了する"
check_calls "issue comment 10" "逸脱あり・逸脱のIssueあり: 起票せず追記する"

setup "$UND"
run weekly deviation "$REPORT"
check_exit 0 "逸脱あり・判定不能のIssueあり: 正常終了する"
check_calls "${CREATE_W_DEV}
issue comment 20
issue close 20" "逸脱あり・判定不能のIssueあり: 起票し、判定不能のIssueを閉じる"

setup "${DEV}, ${UND}"
run weekly deviation "$REPORT"
check_exit 0 "逸脱あり・両方あり: 正常終了する"
check_calls "issue comment 10
issue comment 20
issue close 20" "逸脱あり・両方あり: 逸脱に追記し、判定不能を閉じる"

# ---------------------------------------------------------------------
# 3. 状態遷移表: 結果「判定不能」(要件 3.1, 3.2)
#    逸脱の有無が確定しないので、逸脱のIssueには一切触らない
# ---------------------------------------------------------------------
setup ""
run weekly undecidable "$REPORT"
check_exit 0 "判定不能・既存なし: 正常終了する"
check_calls "$CREATE_W_UND" "判定不能・既存なし: ラベルを付けて判定不能のIssueを起票する"

setup "$DEV"
run weekly undecidable "$REPORT"
check_exit 0 "判定不能・逸脱のIssueあり: 正常終了する"
check_calls "$CREATE_W_UND" "判定不能・逸脱のIssueあり: 起票し、逸脱のIssueには触らない"

setup "$UND"
run weekly undecidable "$REPORT"
check_exit 0 "判定不能・判定不能のIssueあり: 正常終了する"
check_calls "issue comment 20" "判定不能・判定不能のIssueあり: 起票せず追記する"

setup "${DEV}, ${UND}"
run weekly undecidable "$REPORT"
check_exit 0 "判定不能・両方あり: 正常終了する"
check_calls "issue comment 20" "判定不能・両方あり: 判定不能にだけ追記し、逸脱のIssueには触らない"

# ---------------------------------------------------------------------
# 4. 種類ごとのタイトル(要件 6.3)
#    カナリア照合は自分のタイトルだけを扱い、週次監査のIssueには触らない
# ---------------------------------------------------------------------
setup "${DEV}, ${UND}"
run canary deviation "$REPORT"
check_exit 0 "カナリア・逸脱あり: 正常終了する"
check_calls "$CREATE_C_DEV" "カナリア・逸脱あり: カナリアのタイトルで起票し、週次のIssueには触らない"

setup "${DEV}, ${UND}"
run canary undecidable "$REPORT"
check_exit 0 "カナリア・判定不能: 正常終了する"
check_calls "$CREATE_C_UND" "カナリア・判定不能: カナリアのタイトルで起票し、週次のIssueには触らない"

C_DEV_ISSUE='{"number":30,"title":"カナリア照合: 逸脱あり"}'
C_UND_ISSUE='{"number":31,"title":"カナリア照合: 判定不能"}'
setup "${DEV}, ${UND}, ${C_DEV_ISSUE}, ${C_UND_ISSUE}"
run canary none "$REPORT"
check_exit 0 "カナリア・逸脱なし: 正常終了する"
check_calls "issue comment 30
issue close 30
issue comment 31
issue close 31" "カナリア・逸脱なし: カナリアのIssueだけを閉じる"

setup "${C_DEV_ISSUE}, ${C_UND_ISSUE}"
run weekly none "$REPORT"
check_exit 0 "週次・逸脱なし・カナリアのIssueのみ: 正常終了する"
check_calls "" "週次の実行はカナリアのIssueに触らない"

# ---------------------------------------------------------------------
# 5. PR とタイトルが一致しないIssueには触らない(要件 6.3)
# ---------------------------------------------------------------------
PR_ITEM='{"number":99,"title":"週次監査: 逸脱あり","pull_request":{"url":"x"}}'
LOOSE='{"number":50,"title":"週次監査: 逸脱あり (手動で追記)"}'
PREFIXED='{"number":51,"title":"再: 週次監査: 逸脱あり"}'
setup "${PR_ITEM}, ${LOOSE}, ${PREFIXED}"
run weekly none "$REPORT"
check_exit 0 "PRと不一致タイトルのみ・逸脱なし: 正常終了する"
check_calls "" "PRと不一致タイトルのIssueは閉じない"

setup "${PR_ITEM}, ${LOOSE}, ${PREFIXED}"
run weekly deviation "$REPORT"
check_exit 0 "PRと不一致タイトルのみ・逸脱あり: 正常終了する"
check_calls "$CREATE_W_DEV" "PRと不一致タイトルは既存のIssueと見なさず起票する"

# ---------------------------------------------------------------------
# 6. 同じタイトルが複数開いていれば、警告して全部を対象にする
# ---------------------------------------------------------------------
DEV_B='{"number":11,"title":"週次監査: 逸脱あり"}'
setup "${DEV}, ${DEV_B}"
run weekly none "$REPORT"
check_exit 0 "重複・逸脱なし: 正常終了する"
check_calls "issue comment 10
issue close 10
issue comment 11
issue close 11" "重複・逸脱なし: 重複したIssueをすべて閉じる"
if grep -qF "::warning::" "$OUT" && grep -qF "$W_DEV" "$OUT"; then
    pass "重複: タイトルを添えて警告を出す"
else
    fail "重複: タイトルを添えて警告を出す"
fi

setup "${DEV}, ${DEV_B}"
run weekly deviation "$REPORT"
check_exit 0 "重複・逸脱あり: 正常終了する"
check_calls "issue comment 10
issue comment 11" "重複・逸脱あり: 重複したIssueすべてに追記する"

setup "$DEV"
run weekly none "$REPORT"
if grep -qF "::warning::" "$OUT"; then
    fail "重複が無ければ警告を出さない"
else
    pass "重複が無ければ警告を出さない"
fi

# ---------------------------------------------------------------------
# 7. 検索とラベル作成の呼び出し
# ---------------------------------------------------------------------
setup ""
run weekly none "$REPORT"
if grep -qxF "label create audit" "$CALLS"; then
    pass "ラベル audit の作成が呼ばれる"
else
    fail "ラベル audit の作成が呼ばれる"
fi
if grep -qxF "api repos/owner/repo/issues?labels=audit&state=open&per_page=100 --paginate --slurp" "$CALLS"; then
    pass "検索はラベル付きの open をページ送りで全件取る"
else
    fail "検索はラベル付きの open をページ送りで全件取る"
    echo "     実際: $(tr '\n' '|' <"$CALLS")"
fi

# 2ページ目にあるIssueも対象にする
printf '[[%s],[%s]]' "$UND" "$DEV" >"$API_FIXTURE"
: >"$CALLS"
run weekly none "$REPORT"
check_exit 0 "複数ページ: 正常終了する"
check_calls "issue comment 10
issue close 10
issue comment 20
issue close 20" "複数ページ: 2ページ目のIssueも対象にする"

# ---------------------------------------------------------------------
# 8. 本文(要件 2.3, 2.5, 3.3)
# ---------------------------------------------------------------------
# 監査手順書(main の doc/開発フロー/監査手順.md)へのリンク。日本語のパスは
# パーセントエンコードする
DOC_URL="https://github.com/owner/repo/blob/main/doc/%E9%96%8B%E7%99%BA%E3%83%95%E3%83%AD%E3%83%BC/%E7%9B%A3%E6%9F%BB%E6%89%8B%E9%A0%86.md"
DOC_SECTION="「監査の通知Issueを受けたとき」"
RERUN_HEADING="## 再実行の方法"
W_RERUN="失敗した実行を Re-run で再実行する。新規の手動実行(workflow_dispatch)は使わない(skipped-required の対象期間に穴が空くため)"
C_RERUN="Re-run と新規の手動実行のどちらでもよい"

# 使い方: check_body_lacks <記録の行> <含まないべき文字列> <説明>
check_body_lacks() {
    local f
    f=$(body_file_of "$1" || true)
    if [ -z "$f" ] || [ ! -s "$f" ]; then
        fail "$3 (本文が見つからない)"
    elif grep -qF -- "$2" "$f"; then
        fail "$3"
        echo "     本文: $(head -c 300 "$f" | tr '\n' '|')"
    else
        pass "$3"
    fi
}

# 使い方: check_first_line <記録の行> <1行目の先頭に来るべき文字列> <説明>
check_first_line() {
    local f first=""
    f=$(body_file_of "$1" || true)
    [ -z "$f" ] || first=$(head -n 1 "$f")
    case "$first" in
        "$2"*) pass "$3" ;;
        *)
            fail "$3"
            echo "     1行目: ${first}"
            ;;
    esac
}

# 8-1. 起票の本文(種類 × 結果)
for kind in weekly canary; do
    for result in deviation undecidable; do
        case "$kind" in
            weekly) kname="週次監査" own_rerun="$W_RERUN" other_rerun="$C_RERUN" ;;
            canary) kname="カナリア照合" own_rerun="$C_RERUN" other_rerun="$W_RERUN" ;;
        esac
        case "$result" in
            deviation) title="${kname}: 逸脱あり" summary="${kname}で逸脱が見つかった。" ;;
            undecidable) title="${kname}: 判定不能" summary="${kname}が判定できなかった" ;;
        esac
        line="issue create title=${title} label=audit assignee="
        tag="起票(${kind}・${result})"
        setup ""
        run "$kind" "$result" "$REPORT"
        check_exit 0 "${tag}: 正常終了する"
        check_first_line "$line" "@owner " "${tag}: 1行目の先頭で所有者にメンションする"
        check_body_has "$line" "$summary" "${tag}: 結果の1行要約が入る"
        check_body_has "$line" "$RUN_URL" "${tag}: 実行へのリンクが入る"
        check_body_has "$line" "REPORT-MARKER-7f3a" "${tag}: 報告の内容が入る"
        check_body_has "$line" "$DOC_URL" "${tag}: 監査手順書へのリンクが入る"
        check_body_has "$line" "$DOC_SECTION" "${tag}: 監査手順書の節の名前が入る"
        if [ "$result" = "undecidable" ]; then
            check_body_has "$line" "$RERUN_HEADING" "${tag}: 再実行の方法が入る"
            check_body_has "$line" "$own_rerun" "${tag}: 種類に合った再実行の方法が入る"
            check_body_lacks "$line" "$other_rerun" "${tag}: 他の種類の再実行の方法は入らない"
        else
            check_body_lacks "$line" "$RERUN_HEADING" "${tag}: 再実行の方法は入らない"
            check_body_lacks "$line" "Re-run" "${tag}: Re-run の案内は入らない"
        fi
    done
done

# 承認待ちの一覧は報告の一部なので、報告全体が本文に入れば一覧も入る(要件 2.5)
setup ""
printf '## 所有者の承認待ち\n\n- PR #346 APPROVAL-PENDING-MARKER\n' >"$REPORT"
run weekly deviation "$REPORT"
check_body_has "$CREATE_W_DEV" "APPROVAL-PENDING-MARKER" "起票の本文に承認待ちの一覧が入る"

# 8-2. 追記の本文(起票と同じ構成。メンションも付ける)
setup "$DEV"
run weekly deviation "$REPORT"
check_first_line "issue comment 10" "@owner " "逸脱の追記: 1行目の先頭で所有者にメンションする"
check_body_has "issue comment 10" "週次監査で逸脱が見つかった。" "逸脱の追記: 結果の1行要約が入る"
check_body_has "issue comment 10" "REPORT-MARKER-7f3a" "逸脱の追記: 今回の報告の内容が入る"
check_body_has "issue comment 10" "$RUN_URL" "逸脱の追記: 実行へのリンクが入る"
check_body_has "issue comment 10" "$DOC_URL" "逸脱の追記: 監査手順書へのリンクが入る"
check_body_lacks "issue comment 10" "$RERUN_HEADING" "逸脱の追記: 再実行の方法は入らない"

setup "$UND"
run weekly undecidable "$REPORT"
check_first_line "issue comment 20" "@owner " "判定不能の追記: 1行目の先頭で所有者にメンションする"
check_body_has "issue comment 20" "REPORT-MARKER-7f3a" "判定不能の追記: 今回の報告の内容が入る"
check_body_has "issue comment 20" "$RUN_URL" "判定不能の追記: 実行へのリンクが入る"
check_body_has "issue comment 20" "$RERUN_HEADING" "判定不能の追記: 再実行の方法の節が入る"
check_body_has "issue comment 20" "$W_RERUN" "判定不能の追記(週次): 週次の再実行の方法が入る"

setup '{"number":31,"title":"カナリア照合: 判定不能"}'
run canary undecidable "$REPORT"
check_body_has "issue comment 31" "$C_RERUN" "判定不能の追記(カナリア): カナリアの再実行の方法が入る"
check_body_lacks "issue comment 31" "$W_RERUN" "判定不能の追記(カナリア): 週次の再実行の方法は入らない"

# 8-3. 解消の追記
for fixture in "$DEV" "$UND"; do
    setup "$fixture"
    run weekly none "$REPORT"
    n=$(printf '%s' "$fixture" | jq -r .number)
    check_body_has "issue comment ${n}" "今回の実行で解消を確認した" "解消の追記(#${n}): 解消を確認した旨が入る"
    check_body_has "issue comment ${n}" "$RUN_URL" "解消の追記(#${n}): 実行へのリンクが入る"
    check_body_lacks "issue comment ${n}" "REPORT-MARKER-7f3a" "解消の追記(#${n}): 報告は入らない"
    # 対処の要らない知らせなので、メンションで改めて呼び出さない
    check_body_lacks "issue comment ${n}" "@owner" "解消の追記(#${n}): 所有者へのメンションは付けない"
done

# ---------------------------------------------------------------------
# 8-4. 報告の切り詰め(60,000文字。バイト数ではなく文字数で数える)
# ---------------------------------------------------------------------
TRUNC_NOTE="Job Summary"

# 使い方: repeat <回数> <文字>
repeat() {
    local i=0 s=""
    while [ "$i" -lt "$1" ]; do
        s="${s}$2"
        i=$((i + 1))
    done
    printf '%s' "$s"
}
# 1000文字の塊を組み立ててから繰り返し、ループの回数を抑える
# 使い方: make_report <文字> <文字数(1000の倍数+余り)> (末尾に目印 Z を1文字足す)
make_report() {
    local ch="$1" total="$2" block rest i=0
    block=$(repeat 1000 "$ch")
    {
        while [ "$i" -lt $((total / 1000)) ]; do
            printf '%s' "$block"
            i=$((i + 1))
        done
        repeat $((total % 1000)) "$ch"
        printf 'Z'
    } >"$REPORT"
}

# 使い方: count_of <記録の行> <文字>
count_of() {
    # busybox の grep -o は1行に複数の一致を数えないので jq で数える。
    # jq は UTF-8 として読むので、文字の途中で切れていれば一致しない
    local f
    f=$(body_file_of "$1") || return 0
    jq -Rs --arg c "$2" '(split($c) | length) - 1' <"$f"
}

# ASCII: 59,999 + 目印 = 60,000文字は切り詰めない
setup ""
make_report q 59999
run weekly deviation "$REPORT"
check_exit 0 "60,000文字の報告: 正常終了する"
check_body_has "$CREATE_W_DEV" "qZ" "60,000文字の報告: 切り詰めず末尾まで入る"
check_body_lacks "$CREATE_W_DEV" "$TRUNC_NOTE" "60,000文字の報告: 切り詰めの案内は入らない"

# ASCII: 60,000 + 目印 = 60,001文字は先頭の60,000文字に切り詰める
setup ""
make_report q 60000
run weekly deviation "$REPORT"
check_exit 0 "60,001文字の報告: 正常終了する"
check_body_lacks "$CREATE_W_DEV" "qZ" "60,001文字の報告: 60,001文字目以降は入らない"
got=$(count_of "$CREATE_W_DEV" q)
if [ "$got" = "60000" ]; then
    pass "60,001文字の報告: 先頭の60,000文字が入る"
else
    fail "60,001文字の報告: 先頭の60,000文字が入る (実際 ${got})"
fi
check_body_has "$CREATE_W_DEV" "$TRUNC_NOTE" "60,001文字の報告: Job Summary を見るよう案内する"
check_body_has "$CREATE_W_DEV" "$RUN_URL" "60,001文字の報告: 実行へのリンクは残る"
check_body_has "$CREATE_W_DEV" "$DOC_URL" "60,001文字の報告: 監査手順書へのリンクは残る"

# 多バイト文字(UTF-8 で3バイト)。60,000文字は180,000バイトだが切り詰めない
MB="鱻"
setup ""
make_report "$MB" 59999
run weekly deviation "$REPORT"
check_exit 0 "多バイト60,000文字の報告: 正常終了する"
check_body_has "$CREATE_W_DEV" "${MB}Z" "多バイト60,000文字の報告: 切り詰めず末尾まで入る"
check_body_lacks "$CREATE_W_DEV" "$TRUNC_NOTE" "多バイト60,000文字の報告: 切り詰めの案内は入らない"

setup ""
make_report "$MB" 60000
run weekly deviation "$REPORT"
check_exit 0 "多バイト60,001文字の報告: 正常終了する"
check_body_lacks "$CREATE_W_DEV" "${MB}Z" "多バイト60,001文字の報告: 60,001文字目以降は入らない"
got=$(count_of "$CREATE_W_DEV" "$MB")
if [ "$got" = "60000" ]; then
    pass "多バイト60,001文字の報告: 文字の途中で切らずに先頭の60,000文字が入る"
else
    fail "多バイト60,001文字の報告: 文字の途中で切らずに先頭の60,000文字が入る (実際 ${got})"
fi
check_body_has "$CREATE_W_DEV" "$TRUNC_NOTE" "多バイト60,001文字の報告: Job Summary を見るよう案内する"

# 追記でも同じく切り詰める
setup "$UND"
make_report q 60000
run weekly undecidable "$REPORT"
check_exit 0 "追記・60,001文字の報告: 正常終了する"
check_body_lacks "issue comment 20" "qZ" "追記・60,001文字の報告: 切り詰める"
check_body_has "issue comment 20" "$TRUNC_NOTE" "追記・60,001文字の報告: Job Summary を見るよう案内する"
check_body_has "issue comment 20" "$W_RERUN" "追記・60,001文字の報告: 再実行の方法は残る"

# ---------------------------------------------------------------------
# 8-5. 担当者の割り当て(要件 2.1, 3.1)
#   起票の後に REST で所有者を追加し、応答の assignees を読み戻す。
#   付いていなくても通知は起票とメンションで届いているので、警告だけで exit 0
# ---------------------------------------------------------------------
ASSIGN_CALL="api -X POST repos/owner/repo/issues/100/assignees -f assignees[]=owner"

# 使い方: check_output_has <文字列> <説明> / check_output_lacks <文字列> <説明>
check_output_has() {
    if grep -qF -- "$1" "$OUT"; then
        pass "$2"
    else
        fail "$2"
        sed 's/^/     | /' "$OUT"
    fi
}
check_output_lacks() {
    if grep -qF -- "$1" "$OUT"; then
        fail "$2"
        sed 's/^/     | /' "$OUT"
    else
        pass "$2"
    fi
}
check_assign_called() {
    if grep -qxF "$1" "$CALLS"; then
        pass "$2"
    else
        fail "$2"
        echo "     実際: $(tr '\n' '|' <"$CALLS")"
    fi
}

setup ""
run weekly deviation "$REPORT"
check_exit 0 "担当者が付く: 正常終了する"
check_assign_called "$ASSIGN_CALL" "担当者が付く: 起票したIssueに所有者を追加する"
check_output_lacks "::warning::" "担当者が付く: 警告を出さない"
if [ "$(grep -n -xF "$CREATE_W_DEV" "$CALLS" | cut -d: -f1)" -lt "$(grep -n -xF "$ASSIGN_CALL" "$CALLS" | cut -d: -f1)" ]; then
    pass "担当者が付く: 追加は起票の後に行う"
else
    fail "担当者が付く: 追加は起票の後に行う"
fi

setup ""
run weekly undecidable "$REPORT"
check_assign_called "$ASSIGN_CALL" "判定不能の起票でも所有者を追加する"

setup ""
printf '{"number":100,"assignees":[]}' >"$ASSIGN_FIXTURE"
run weekly deviation "$REPORT"
check_exit 0 "割り当てが黙って無視された: exit 0"
check_calls "$CREATE_W_DEV" "割り当てが黙って無視された: 起票は済んでいる"
check_output_has "::warning::" "割り当てが黙って無視された: 警告を出す"
check_output_has "owner" "割り当てが黙って無視された: 警告に所有者の名前が入る"

setup ""
printf '{"number":100,"assignees":[{"login":"someone-else"}]}' >"$ASSIGN_FIXTURE"
run weekly deviation "$REPORT"
check_exit 0 "所有者以外だけが付いた: exit 0"
check_output_has "::warning::" "所有者以外だけが付いた: 警告を出す"

setup ""
GH_FAIL_ON="api assignees" run weekly deviation "$REPORT"
check_exit 0 "担当者の追加が失敗: exit 0"
check_calls "$CREATE_W_DEV" "担当者の追加が失敗: 起票は済んでいる"
check_output_has "::warning::" "担当者の追加が失敗: 警告を出す"

setup ""
printf 'not json' >"$ASSIGN_FIXTURE"
run weekly deviation "$REPORT"
check_exit 0 "担当者の追加の応答が解釈できない: exit 0"
check_output_has "::warning::" "担当者の追加の応答が解釈できない: 警告を出す"

setup ""
GH_CREATE_OUTPUT="https://github.com/owner/repo/issues/7" run weekly deviation "$REPORT"
check_assign_called "api -X POST repos/owner/repo/issues/7/assignees -f assignees[]=owner" \
    "起票の出力のURLから番号を取り、そのIssueに所有者を追加する"

setup ""
GH_CREATE_OUTPUT="起票しました" run weekly deviation "$REPORT"
check_exit 0 "起票の出力から番号を取れない: exit 0"
check_output_has "::warning::" "起票の出力から番号を取れない: 警告を出す"
if grep -qF "/assignees" "$CALLS"; then
    fail "起票の出力から番号を取れない: 担当者の追加を呼ばない"
else
    pass "起票の出力から番号を取れない: 担当者の追加を呼ばない"
fi

setup "$DEV"
run weekly deviation "$REPORT"
if grep -qF "/assignees" "$CALLS"; then
    fail "追記では担当者の追加を呼ばない"
else
    pass "追記では担当者の追加を呼ばない"
fi

setup ""
GH_FAIL_ON="issue create" run weekly deviation "$REPORT"
if grep -qF "/assignees" "$CALLS"; then
    fail "起票が失敗したら担当者の追加を呼ばない"
else
    pass "起票が失敗したら担当者の追加を呼ばない"
fi

# ---------------------------------------------------------------------
# 9. gh の失敗(要件 3.5)
# ---------------------------------------------------------------------
setup "$DEV"
GH_FAIL_ON=api run weekly none "$REPORT"
check_exit 1 "検索が失敗したら exit 1"
check_calls "" "検索が失敗したらIssueを操作しない"

printf 'not json' >"$API_FIXTURE"
: >"$CALLS"
run weekly none "$REPORT"
check_exit 1 "検索の応答を解釈できなければ exit 1"
check_calls "" "検索の応答を解釈できなければIssueを操作しない"

setup ""
GH_FAIL_ON="issue create" run weekly deviation "$REPORT"
check_exit 1 "起票が失敗したら exit 1"

setup "$DEV"
GH_FAIL_ON="issue comment" run weekly deviation "$REPORT"
check_exit 1 "追記が失敗したら exit 1"

setup "$DEV"
GH_FAIL_ON="issue close" run weekly none "$REPORT"
check_exit 1 "クローズが失敗したら exit 1"

# gh の終了コードが1以外でも契約どおり1に揃える
setup "$DEV"
GH_FAIL_ON="issue close" GH_FAIL_CODE=4 run weekly none "$REPORT"
check_exit 1 "gh が1以外の終了コードで失敗しても exit 1"

# 解消の追記に失敗したら、閉じない(記録の無いクローズを作らない)
setup "$DEV"
GH_FAIL_ON="issue comment" run weekly none "$REPORT"
check_exit 1 "解消の追記が失敗したら exit 1"
check_calls "issue comment 10" "解消の追記が失敗したら閉じない"

# 既存ラベルに対して gh label create は非ゼロで終わる。
# ここで赤にすると、2回目以降の実行が必ず失敗する。
setup ""
GH_FAIL_ON=label run weekly deviation "$REPORT"
check_exit 0 "ラベルの作成が失敗しても exit 0"
check_calls "$CREATE_W_DEV" "ラベルの作成が失敗しても起票を続ける"

# ---------------------------------------------------------------------
# 10. 引数・環境変数の不正(gh を一度も呼ばない)
# ---------------------------------------------------------------------
setup "$DEV"
run daily none "$REPORT"
check_exit 1 "未知の kind は exit 1"
check_no_gh "未知の kind では gh を呼ばない"

setup "$DEV"
run weekly ok "$REPORT"
check_exit 1 "未知の result は exit 1"
check_no_gh "未知の result では gh を呼ばない"

setup "$DEV"
run
check_exit 1 "引数が無ければ exit 1"
check_no_gh "引数が無ければ gh を呼ばない"

for r in deviation undecidable; do
    setup "$DEV"
    run weekly "$r" "$WORK/no-such-report.md"
    check_exit 1 "${r}: 報告ファイルが無ければ exit 1"
    check_no_gh "${r}: 報告ファイルが無ければ gh を呼ばない"

    setup "$DEV"
    run weekly "$r"
    check_exit 1 "${r}: 報告ファイルの指定が無ければ exit 1"
    check_no_gh "${r}: 報告ファイルの指定が無ければ gh を呼ばない"
done

# 逸脱なしでは報告は使わないので、報告ファイルが無くても動く
setup "$DEV"
run weekly none
check_exit 0 "逸脱なしは報告ファイルの指定が無くても動く"
check_calls "issue comment 10
issue close 10" "逸脱なしは報告ファイルの指定が無くても閉じる"

for v in GH_TOKEN GITHUB_REPOSITORY GITHUB_REPOSITORY_OWNER GITHUB_SERVER_URL GITHUB_RUN_ID; do
    setup "$DEV"
    unset "$v"
    run weekly none "$REPORT"
    check_exit 1 "${v} が無ければ exit 1"
    check_no_gh "${v} が無ければ gh を呼ばない"
    set_env

    setup "$DEV"
    export "$v="
    run weekly none "$REPORT"
    check_exit 1 "${v} が空なら exit 1"
    check_no_gh "${v} が空なら gh を呼ばない"
    set_env
done

# ---------------------------------------------------------------------
if [ "$FAILED" -ne 0 ]; then
    echo "::error::audit-issue.sh のテストに失敗しました。"
    exit 1
fi
echo "全ケース成功。"
