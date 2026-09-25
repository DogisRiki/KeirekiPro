#!/usr/bin/env bash
# =====================================================================
# audit-issue.sh の自動テスト
#
# gh をシムして、呼ばれたIssue操作の列と終了コードを検証する。
# シムは呼び出しを1行1件で記録し、--body の中身は呼び出しごとに
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
# - --body の中身は「記録の行番号.txt」に保存する
# - GH_FAIL_ON に「サブコマンド」か「サブコマンド 操作」を指定すると失敗させる。
#   終了コードは GH_FAIL_CODE(既定 1)
# - api の応答は $API_FIXTURE_PATH の内容を返す
cat >"$WORK/bin/gh" <<'SHIM'
#!/usr/bin/env bash
sub="${1:-}"
action="${2:-}"
title="" label="" assignee="" body="" has_body=0 positional=""
if [ "$sub" = "issue" ] || [ "$sub" = "label" ]; then
    shift 2
    while [ $# -gt 0 ]; do
        case "$1" in
            --title) title="$2"; shift ;;
            --label) label="$2"; shift ;;
            --assignee) assignee="$2"; shift ;;
            --body) body="$2"; has_body=1; shift ;;
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
    api) cat "$API_FIXTURE_PATH" ;;
    issue) [ "$action" = "create" ] && echo "https://github.com/owner/repo/issues/100" ;;
esac
exit 0
SHIM
chmod +x "$WORK/bin/gh"
export CALLS_LOG="$CALLS"
export API_FIXTURE_PATH="$API_FIXTURE"
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

# 使い方: body_of <記録の行に完全一致する文字列>
# その呼び出しに渡された --body の中身を出力する
body_of() {
    local n
    n=$(grep -nxF "$1" "$CALLS" | head -n 1 | cut -d: -f1)
    [ -n "$n" ] && [ -f "$WORK/bodies/${n}.txt" ] && cat "$WORK/bodies/${n}.txt"
}

# 使い方: check_body_has <記録の行> <含むべき文字列> <説明>
check_body_has() {
    local body
    body=$(body_of "$1" || true)
    if printf '%s' "$body" | grep -qF -- "$2"; then
        pass "$3"
    else
        fail "$3"
        echo "     本文: $(printf '%s' "$body" | head -c 300 | tr '\n' '|')"
    fi
}

W_DEV="週次監査: 逸脱あり"
W_UND="週次監査: 判定不能"
C_DEV="カナリア照合: 逸脱あり"
C_UND="カナリア照合: 判定不能"

DEV='{"number":10,"title":"週次監査: 逸脱あり"}'
UND='{"number":20,"title":"週次監査: 判定不能"}'

CREATE_W_DEV="issue create title=${W_DEV} label=audit assignee=owner"
CREATE_W_UND="issue create title=${W_UND} label=audit assignee=owner"
CREATE_C_DEV="issue create title=${C_DEV} label=audit assignee=owner"

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
check_calls "$CREATE_W_DEV" "逸脱あり・既存なし: ラベルと担当者を付けて逸脱のIssueを起票する"

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
check_calls "$CREATE_W_UND" "判定不能・既存なし: ラベルと担当者を付けて判定不能のIssueを起票する"

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
check_calls "issue create title=${C_UND} label=audit assignee=owner" "カナリア・判定不能: カナリアのタイトルで起票し、週次のIssueには触らない"

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
# 8. 本文(2.2 で内容を拡充する。ここでは報告と実行へのリンクだけ確かめる)
# ---------------------------------------------------------------------
setup ""
run weekly deviation "$REPORT"
check_body_has "$CREATE_W_DEV" "REPORT-MARKER-7f3a" "起票の本文に報告の内容が入る"
check_body_has "$CREATE_W_DEV" "$RUN_URL" "起票の本文に実行へのリンクが入る"

setup "$DEV"
run weekly deviation "$REPORT"
check_body_has "issue comment 10" "REPORT-MARKER-7f3a" "追記の本文に報告の内容が入る"
check_body_has "issue comment 10" "$RUN_URL" "追記の本文に実行へのリンクが入る"

setup "$UND"
run weekly undecidable "$REPORT"
check_body_has "issue comment 20" "REPORT-MARKER-7f3a" "判定不能の追記の本文に報告の内容が入る"

setup "$UND"
run weekly none "$REPORT"
check_body_has "issue comment 20" "$RUN_URL" "解消の追記に実行へのリンクが入る"

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
