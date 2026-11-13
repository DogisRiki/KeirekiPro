#!/usr/bin/env bash
# =====================================================================
# container-scan-issue.sh の自動テスト
#
# gh をシムして、呼ばれたサブコマンドと終了コードを検証する。
# シムは呼び出しを1行1件で記録し、テスト側はその記録を突き合わせる。
#
# 実際のAPIは叩かない。Issueのクローズは後戻りしにくい操作なので、
# 4分岐のどれが呼ばれるかをここで固定する。
# =====================================================================
set -uo pipefail

SCRIPT="$(cd "$(dirname "$0")/.." && pwd)/container-scan-issue.sh"
WORK=$(mktemp -d) || exit 1
[ -n "$WORK" ] && [ -d "$WORK" ] || exit 1
trap 'rm -rf "$WORK"' EXIT
FAILED=0

mkdir -p "$WORK/bin"
PATH="$WORK/bin:$PATH"
export PATH
export GITHUB_REPOSITORY="owner/repo"

CALLS="$WORK/calls.log"
API_FIXTURE="$WORK/api.json"

# gh のシム。api の応答は $API_FIXTURE から返し、それ以外は記録だけする。
# コメントの取得(パスに /comments を含む api)は $COMMENTS_FIXTURE から返し、
# ファイルが無ければコメント0件を返す。
# GH_FAIL_ON に指定したサブコマンドは失敗させる。
# GH_FAIL_COMMENTS を付けると、コメントの取得だけを失敗させる。
cat >"$WORK/bin/gh" <<'SHIM'
#!/usr/bin/env bash
sub="${1:-}"
{
    printf '%s' "$sub"
    case "$sub" in
        issue) printf ' %s %s' "${2:-}" "${3:-}" ;;
        label) printf ' %s %s' "${2:-}" "${3:-}" ;;
    esac
    printf '\n'
} >>"$CALLS_LOG"
if [ -n "${GH_FAIL_ON:-}" ] && [ "$sub" = "$GH_FAIL_ON" ]; then
    echo "gh: 失敗をシミュレート" >&2
    exit 1
fi
if [ -n "${BODY_OUT:-}" ]; then
    while [ $# -gt 0 ]; do
        if [ "$1" = "--body" ]; then
            shift
            printf '%s' "$1" >>"$BODY_OUT"
        fi
        shift
    done
fi
if [ "$sub" = "api" ]; then
    case "${2:-}" in
        */comments*)
            if [ -n "${GH_FAIL_COMMENTS:-}" ]; then
                echo "gh: コメントの取得の失敗をシミュレート" >&2
                exit 1
            fi
            if [ -f "$COMMENTS_FIXTURE_PATH" ]; then
                cat "$COMMENTS_FIXTURE_PATH"
            else
                printf '[[]]'
            fi
            ;;
        *)
            cat "$API_FIXTURE_PATH"
            ;;
    esac
fi
exit 0
SHIM
chmod +x "$WORK/bin/gh"
COMMENTS_FIXTURE="$WORK/comments.json"
export CALLS_LOG="$CALLS"
export API_FIXTURE_PATH="$API_FIXTURE"
export COMMENTS_FIXTURE_PATH="$COMMENTS_FIXTURE"

# 使い方: setup <blocking json> <detected json> <open issues json>
setup() {
    printf '%s' "$1" >"$WORK/blocking.json"
    printf '%s' "$2" >"$WORK/detected.json"
    # gh api --paginate --slurp は「ページの配列」を返す。
    # ページ1つの中にIssueの配列が入るので2段包む。
    printf '[[%s]]' "$3" >"$API_FIXTURE"
    rm -f "$COMMENTS_FIXTURE"
    : >"$CALLS"
}

# 使い方: set_comments <コメントの JSON をカンマでつないだもの>
set_comments() {
    printf '[[%s]]' "$1" >"$COMMENTS_FIXTURE"
}

# 使い方: comment_json <利用者> <本文のファイル>
comment_json() {
    jq -cn --arg u "$1" --rawfile b "$2" '{user: {login: $u}, body: $b}'
}

# 使い方: issue_json <番号> <利用者> <本文のファイル>
issue_json() {
    jq -cn --argjson n "$1" --arg u "$2" --rawfile b "$3" \
        '{number: $n, title: "コンテナ脆弱性: CVE-2026-1", user: {login: $u}, body: $b}'
}

# 使い方: state_file <状態の JSON> <書き出すファイル>
# 本文の末尾に状態の記録を置いた文を書く。
state_file() {
    printf '本文\n\n<!-- container-scan-state: %s -->\n' "$1" >"$2"
}

run_script() {
    bash "$SCRIPT" "$WORK/blocking.json" "$WORK/detected.json" "sha256:abc" >/dev/null 2>&1
}

# 使い方: check <期待exit> <説明>
check() {
    local want="$1" name="$2" got
    run_script
    got=$?
    if [ "$got" -eq "$want" ]; then
        echo "ok   ${name}"
    else
        echo "FAIL ${name} (期待 exit=${want} / 実際 exit=${got})"
        FAILED=1
    fi
}

# 使い方: check_calls <期待する呼び出し(改行区切り)> <説明>
# gh api と gh label は毎回呼ばれるので比較から外す。
check_calls() {
    local want="$1" name="$2" got
    got=$(grep -E '^issue ' "$CALLS" || true)
    if [ "$got" = "$want" ]; then
        echo "ok   ${name}"
    else
        echo "FAIL ${name}"
        echo "     期待: $(printf '%s' "$want" | tr '\n' '|')"
        echo "     実際: $(printf '%s' "$got" | tr '\n' '|')"
        FAILED=1
    fi
}

# 使い方: check_calls_after_run <期待する呼び出し(改行区切り)> <説明>
# スクリプトを流してから、呼び出しを突き合わせる。
check_calls_after_run() {
    run_script
    check_calls "$@"
}

ROW='{"id":"CVE-2026-1","severity":"HIGH","pkgName":"pkg","installedVersion":"1.0","fixedVersion":"1.1"}'
ISSUE='{"number":42,"title":"コンテナ脆弱性: CVE-2026-1"}'
PR_ITEM='{"number":99,"title":"コンテナ脆弱性: CVE-2026-9","pull_request":{"url":"x"}}'

# ---------------------------------------------------------------------
# 1. blocking にある新規のID -> 起票
# ---------------------------------------------------------------------
setup "[${ROW}]" "[${ROW}]" ""
check 0 "新規のIDで正常終了する"
check_calls "issue create --title" "新規のIDでは起票が呼ばれる"

# ---------------------------------------------------------------------
# 2. blocking にあり既存のオープンIssueがある -> 追記のみ
# ---------------------------------------------------------------------
setup "[${ROW}]" "[${ROW}]" "${ISSUE}"
check 0 "既存Issueがあっても正常終了する"
check_calls "issue comment 42" "既存Issueでは起票が呼ばれず追記される"

# ---------------------------------------------------------------------
# 3. blocking に無いが detected にある -> 追記のみ、閉じない
#    修正版の取り下げや深刻度の格下げで起きる。脆弱性は残っている。
# ---------------------------------------------------------------------
DOWNGRADED='{"id":"CVE-2026-1","severity":"MEDIUM","pkgName":"pkg","installedVersion":"1.0","fixedVersion":null}'
setup "[]" "[${DOWNGRADED}]" "${ISSUE}"
check 0 "条件から外れても正常終了する"
check_calls "issue comment 42" "条件から外れただけならクローズしない"

# ---------------------------------------------------------------------
# 4. detected にも無い -> 追記してクローズ
# ---------------------------------------------------------------------
setup "[]" "[]" "${ISSUE}"
check 0 "解消時に正常終了する"
check_calls "issue comment 42
issue close 42" "検出されなくなったら追記してクローズする"

# ---------------------------------------------------------------------
# 5. 両方空かつオープンIssueも0件 -> 何も呼ばれない
# ---------------------------------------------------------------------
setup "[]" "[]" ""
check 0 "両方空でも正常終了する"
check_calls "" "何も検出されず既存Issueも無ければ何も呼ばない"

# ---------------------------------------------------------------------
# 6. Issues API が返すPRは無視する
# ---------------------------------------------------------------------
setup "[]" "[]" "${PR_ITEM}"
check 0 "PRが混ざっていても正常終了する"
check_calls "" "Issues API が返すPRには触らない"

# ---------------------------------------------------------------------
# 7. 入力が不正
# ---------------------------------------------------------------------
setup '{"not":"an array"}' "[]" ""
check 1 "blocking が配列でなければ赤"

setup "[]" '"string"' ""
check 1 "detected が配列でなければ赤"

printf '%s' "[]" >"$WORK/blocking.json"
rm -f "$WORK/detected.json"
: >"$CALLS"
bash "$SCRIPT" "$WORK/blocking.json" "$WORK/detected.json" "sha256:abc" >/dev/null 2>&1
if [ $? -eq 1 ]; then
    echo "ok   入力ファイルが無ければ赤"
else
    echo "FAIL 入力ファイルが無ければ赤"
    FAILED=1
fi

# ---------------------------------------------------------------------
# 8. gh が失敗したら赤
# ---------------------------------------------------------------------
setup "[${ROW}]" "[${ROW}]" ""
GH_FAIL_ON=issue check 1 "gh issue が失敗したら赤"

setup "[]" "[]" ""
GH_FAIL_ON=api check 1 "gh api が失敗したら赤"

# ---------------------------------------------------------------------
# 9. ラベルの作成
# ---------------------------------------------------------------------
setup "[]" "[]" ""
run_script
if grep -qxF "label create container-vuln" "$CALLS"; then
    echo "ok   ラベルの作成が呼ばれる"
else
    echo "FAIL ラベルの作成が呼ばれる"
    FAILED=1
fi

# 既存ラベルに対して gh label create は非ゼロで終わる。
# ここで赤にすると、2回目以降の実行が必ず失敗する。
setup "[]" "[]" ""
GH_FAIL_ON=label check 0 "ラベルが既にあっても赤にしない"

# ---------------------------------------------------------------------
# 10. 起票の本文に識別子と対象イメージが入る(要件 2.2)
# ---------------------------------------------------------------------
setup "[${ROW}]" "[${ROW}]" ""
: >"$WORK/body.txt"
BODY_OUT="$WORK/body.txt" run_script
if grep -qF "CVE-2026-1" "$WORK/body.txt" && grep -qF "sha256:abc" "$WORK/body.txt"; then
    echo "ok   本文に識別子と対象イメージが入る"
else
    echo "FAIL 本文に識別子と対象イメージが入る"
    FAILED=1
fi

# ---------------------------------------------------------------------
# 11. タイトルが規約から外れたIssueは操作しない
#     人手で追記されたタイトルを別物と見なすと、
#     「検出されなくなった」と誤判定して閉じてしまう
# ---------------------------------------------------------------------
IRREGULAR_ISSUE='{"number":50,"title":"コンテナ脆弱性: CVE-2026-1 (再発)"}'
setup "[${ROW}]" "[${ROW}]" "${IRREGULAR_ISSUE}"
check 0 "規約外のタイトルがあっても正常終了する"
check_calls "issue create --title" "規約外のタイトルのIssueはクローズしない"

# ---------------------------------------------------------------------
# 12. 同じ識別子のIssueが複数あればすべて扱う
# ---------------------------------------------------------------------
ISSUE_B='{"number":43,"title":"コンテナ脆弱性: CVE-2026-1"}'
setup "[]" "[]" "${ISSUE}, ${ISSUE_B}"
check 0 "重複したIssueがあっても正常終了する"
check_calls "issue comment 42
issue close 42
issue comment 43
issue close 43" "重複したIssueをすべて閉じる"

# 追記経路も全件を対象にする。numbers_for が1件しか返さないと
# 片方が更新されないまま残る。
setup "[${ROW}]" "[${ROW}]" "${ISSUE}, ${ISSUE_B}"
check 0 "重複したIssueへの追記が正常終了する"
check_calls "issue comment 42
issue comment 43" "重複したIssueすべてに追記する"

# ---------------------------------------------------------------------
# 13. id を欠く要素は受け付けない
# ---------------------------------------------------------------------
setup '[{"severity":"HIGH","pkgName":"pkg"}]' "[]" ""
check 1 "id を欠く要素があれば赤"

# ---------------------------------------------------------------------
# 14. 状態が前回の記録と同じなら追記しない(#820)
#     検査は毎日動く。変わらない状態を毎回追記すると、
#     深刻度や修正版の変化が同じ内容のコメントに埋もれる。
# ---------------------------------------------------------------------
BOT="github-actions[bot]"
SAME_STATE='{"kind":"recheck","rows":[{"fixed":true,"severity":"HIGH"}]}'
CRITICAL_STATE='{"kind":"recheck","rows":[{"fixed":true,"severity":"CRITICAL"}]}'
state_file "$SAME_STATE" "$WORK/same.txt"
state_file "$CRITICAL_STATE" "$WORK/critical.txt"

setup "[${ROW}]" "[${ROW}]" "${ISSUE}"
set_comments "$(comment_json "$BOT" "$WORK/same.txt")"
check 0 "記録が同じでも正常終了する"
check_calls "" "bot の記録と状態が同じなら追記しない"

setup "[${ROW}]" "[${ROW}]" "${ISSUE}"
set_comments "$(comment_json "$BOT" "$WORK/critical.txt")"
check 0 "深刻度が変わっても正常終了する"
check_calls "issue comment 42" "深刻度が前回の記録と違えば追記する"

# 修正版の有無だけが変わったときも追記する
NOFIX_STATE='{"kind":"recheck","rows":[{"fixed":false,"severity":"HIGH"}]}'
state_file "$NOFIX_STATE" "$WORK/nofix.txt"
setup "[${ROW}]" "[${ROW}]" "${ISSUE}"
set_comments "$(comment_json "$BOT" "$WORK/nofix.txt")"
check_calls_after_run "issue comment 42" "修正版の有無が前回の記録と違えば追記する"

# 公開のリポジトリでは誰でもコメントを書ける。bot 以外が書いた記録で
# 追記を止められないようにする。
setup "[${ROW}]" "[${ROW}]" "${ISSUE}"
set_comments "$(comment_json "someone" "$WORK/same.txt")"
check_calls_after_run "issue comment 42" "bot 以外の利用者の記録は読まずに追記する"

# bot の記録が違い、そのあとに bot 以外が同じ状態を書いても追記する
setup "[${ROW}]" "[${ROW}]" "${ISSUE}"
set_comments "$(comment_json "$BOT" "$WORK/critical.txt"),$(comment_json "someone" "$WORK/same.txt")"
check_calls_after_run "issue comment 42" "bot 以外があとから書いた記録で追記を止められない"

# 記録が複数あるときは最後のものを使う
setup "[${ROW}]" "[${ROW}]" "${ISSUE}"
set_comments "$(comment_json "$BOT" "$WORK/critical.txt"),$(comment_json "$BOT" "$WORK/same.txt")"
check_calls_after_run "" "最後の記録が同じなら追記しない"

setup "[${ROW}]" "[${ROW}]" "${ISSUE}"
set_comments "$(comment_json "$BOT" "$WORK/same.txt"),$(comment_json "$BOT" "$WORK/critical.txt")"
check_calls_after_run "issue comment 42" "最後の記録が違えば追記する"

# 読めない記録は、無いものとして扱い追記する
printf '本文\n\n<!-- container-scan-state: {broken -->\n<!-- container-scan-state: {"kind": } -->\n' >"$WORK/broken.txt"
setup "[${ROW}]" "[${ROW}]" "${ISSUE}"
set_comments "$(comment_json "$BOT" "$WORK/broken.txt")"
check 0 "読めない記録があっても正常終了する"
check_calls "issue comment 42" "読めない記録は無いものとして追記する"

# ---------------------------------------------------------------------
# 15. 起票の本文の記録を前回の記録として使う
# ---------------------------------------------------------------------
setup "[${ROW}]" "[${ROW}]" "$(issue_json 42 "$BOT" "$WORK/same.txt")"
check_calls_after_run "" "起票の本文の記録が同じでコメントが無ければ追記しない"

setup "[${ROW}]" "[${ROW}]" "$(issue_json 42 "someone" "$WORK/same.txt")"
check_calls_after_run "issue comment 42" "bot 以外が起票した本文の記録は読まない"

# コメントの記録は本文の記録より新しい
setup "[${ROW}]" "[${ROW}]" "$(issue_json 42 "$BOT" "$WORK/same.txt")"
set_comments "$(comment_json "$BOT" "$WORK/critical.txt")"
check_calls_after_run "issue comment 42" "コメントの記録があれば本文の記録より優先する"

# ---------------------------------------------------------------------
# 16. 書いた本文の記録を次の検査が前回の記録として読める
#     書く形と読む形が食い違うと、毎回追記するか、ずっと追記しなくなる。
# ---------------------------------------------------------------------
# 起票 -> 次の検査
setup "[${ROW}]" "[${ROW}]" ""
: >"$WORK/created.txt"
BODY_OUT="$WORK/created.txt" run_script
setup "[${ROW}]" "[${ROW}]" "$(issue_json 42 "$BOT" "$WORK/created.txt")"
check_calls_after_run "" "起票した本文の記録で、次の検査は追記しない"

# 追記 -> 次の検査
setup "[${ROW}]" "[${ROW}]" "${ISSUE}"
: >"$WORK/rechecked.txt"
BODY_OUT="$WORK/rechecked.txt" run_script
setup "[${ROW}]" "[${ROW}]" "${ISSUE}"
set_comments "$(comment_json "$BOT" "$WORK/rechecked.txt")"
check_calls_after_run "" "追記した記録で、次の検査は追記しない"

# 条件から外れた追記 -> 次の検査
setup "[]" "[${DOWNGRADED}]" "${ISSUE}"
: >"$WORK/downgraded.txt"
BODY_OUT="$WORK/downgraded.txt" run_script
setup "[]" "[${DOWNGRADED}]" "${ISSUE}"
set_comments "$(comment_json "$BOT" "$WORK/downgraded.txt")"
check_calls_after_run "" "条件から外れた状態が同じなら追記しない"

# 条件から外れた状態の記録のまま、ふたたび条件に当たったら追記する
setup "[${ROW}]" "[${ROW}]" "${ISSUE}"
set_comments "$(comment_json "$BOT" "$WORK/downgraded.txt")"
check_calls_after_run "issue comment 42" "条件に当たるかが変われば追記する"

# 条件に当たる状態の記録のまま、条件から外れたら追記する
setup "[]" "[${DOWNGRADED}]" "${ISSUE}"
set_comments "$(comment_json "$BOT" "$WORK/rechecked.txt")"
check_calls_after_run "issue comment 42" "条件から外れれば追記する"

# 記録が同じでも、検出されなくなれば追記して閉じる
setup "[]" "[]" "${ISSUE}"
set_comments "$(comment_json "$BOT" "$WORK/rechecked.txt")"
check_calls_after_run "issue comment 42
issue close 42" "記録があっても、検出されなくなれば追記して閉じる"

# ---------------------------------------------------------------------
# 17. コメントを取得できなければ赤
#     追記するかを決められないまま進めると、変化を見落とす。
# ---------------------------------------------------------------------
setup "[${ROW}]" "[${ROW}]" "${ISSUE}"
GH_FAIL_COMMENTS=1 check 1 "コメントの取得に失敗したら赤"
check_calls "" "コメントの取得に失敗したら追記しない"

setup "[]" "[${DOWNGRADED}]" "${ISSUE}"
GH_FAIL_COMMENTS=1 check 1 "条件から外れた側でもコメントの取得に失敗したら赤"

# ---------------------------------------------------------------------
if [ "$FAILED" -ne 0 ]; then
    echo "::error::container-scan-issue.sh のテストに失敗しました。"
    exit 1
fi
echo "全ケース成功。"
