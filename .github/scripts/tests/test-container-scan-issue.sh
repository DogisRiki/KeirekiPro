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
# GH_FAIL_ON に指定したサブコマンドは失敗させる。
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
    cat "$API_FIXTURE_PATH"
fi
exit 0
SHIM
chmod +x "$WORK/bin/gh"
export CALLS_LOG="$CALLS"
export API_FIXTURE_PATH="$API_FIXTURE"

# 使い方: setup <blocking json> <detected json> <open issues json>
setup() {
    printf '%s' "$1" >"$WORK/blocking.json"
    printf '%s' "$2" >"$WORK/detected.json"
    # gh api --paginate --slurp は「ページの配列」を返す。
    # ページ1つの中にIssueの配列が入るので2段包む。
    printf '[[%s]]' "$3" >"$API_FIXTURE"
    : >"$CALLS"
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
if [ "$FAILED" -ne 0 ]; then
    echo "::error::container-scan-issue.sh のテストに失敗しました。"
    exit 1
fi
echo "全ケース成功。"
