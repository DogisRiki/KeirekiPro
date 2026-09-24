#!/usr/bin/env bash
# =====================================================================
# check-audit-scan-freshness.sh の自動テスト(audit-weekly CI から実行)
#
# gh をスタブし、終了コードと報告の内容を検証する。
#   0 = 逸脱なし / 1 = 逸脱あり / 2 = 判定不能
#
# gh のスタブは実APIの形のJSONをそのまま返し、応答の解釈(workflow_runs が
# 配列であることの検査・created_at の取り出し)は本体側に実行させる。
# 整形済みの値を返すスタブにすると、応答形式の検証が範囲から外れ、
# 解釈を壊しても緑のままになる。
#
# 外部への問い合わせを行わないため、実行にネットワークを必要としない。
# 時刻は NOW_EPOCH で固定し、8日ちょうどの境界値を再現可能にする。
# =====================================================================
set -uo pipefail

SCRIPT="$(cd "$(dirname "$0")/.." && pwd)/check-audit-scan-freshness.sh"
WORK=$(mktemp -d) || exit 1
[ -n "$WORK" ] && [ -d "$WORK" ] || exit 1
trap 'rm -rf "$WORK"' EXIT
FAILED=0

# 判定の基準時刻。2026-01-10T00:00:00Z
NOW=1768003200

mkdir -p "$WORK/bin"

# --- gh のスタブ ---------------------------------------------------------------
# 呼び出しの引数を $STUB_CALLS に記録し、$STUB_RUNS の内容をそのまま返す。
# STUB_GH_FAIL が設定されているときは、標準出力を空にして異常終了する
# (実行一覧APIの応答が得られない状況の再現)。
cat >"$WORK/bin/gh" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"${STUB_CALLS:?}"
if [ -n "${STUB_GH_FAIL:-}" ]; then
    echo "stub: API failure" >&2
    exit 1
fi
cat "${STUB_RUNS:?}"
STUB
chmod +x "$WORK/bin/gh"

# --- date のラッパ ---------------------------------------------------------------
# STUB_DATE_FAIL が設定されているときだけ、エポック秒からの整形(-d @...)を
# 異常終了させる。本体でガードしていないコマンドが想定外に失敗した状況の再現。
# それ以外の呼び出しは本物の date に渡す。
REAL_DATE=$(command -v date) || exit 1
cat >"$WORK/bin/date" <<STUB
#!/usr/bin/env bash
if [ -n "\${STUB_DATE_FAIL:-}" ]; then
    for arg in "\$@"; do
        case "\$arg" in
        @*)
            echo "stub: date failure" >&2
            exit 1
            ;;
        esac
    done
fi
exec "$REAL_DATE" "\$@"
STUB
chmod +x "$WORK/bin/date"

# 使い方: run <APIレスポンスJSON> [gh失敗] [date失敗]
run() {
    printf '%s' "$1" >"$WORK/runs.json"
    : >"$WORK/calls.log"
    : >"$WORK/summary.md"
    PATH="$WORK/bin:$PATH" \
        STUB_RUNS="$WORK/runs.json" STUB_CALLS="$WORK/calls.log" \
        STUB_GH_FAIL="${2:-}" STUB_DATE_FAIL="${3:-}" \
        GITHUB_REPOSITORY="owner/repo" GH_TOKEN="dummy" NOW_EPOCH="$NOW" \
        GITHUB_STEP_SUMMARY="$WORK/summary.md" \
        bash "$SCRIPT" container-scan-scheduled.yaml 8 >/dev/null 2>&1
}

# 使い方: check <期待exit> <説明> <APIレスポンスJSON> [gh失敗] [date失敗]
check() {
    local want="$1" name="$2" got
    run "$3" "${4:-}" "${5:-}"
    got=$?
    if [ "$got" -eq "$want" ]; then
        echo "PASS: $name"
    else
        echo "FAIL: $name (expected exit $want, got $got)"
        FAILED=1
    fi
}

# 引数・環境変数を任意に与えて起動する。gh は正常な応答を返す状態にしておき、
# 終了コードが入力の検査だけで決まることを確かめる。
# 時刻固定の値は INVOKE_NOW で差し替えられる(既定は $NOW)。
# 使い方: [INVOKE_NOW=<値>] check_invocation <期待exit> <説明> <与えない必須環境変数名 または ""> [引数...]
check_invocation() {
    local want="$1" name="$2" omit_var="$3" got
    shift 3
    runs_json "$CREATED_JUST_UNDER_8D" >"$WORK/runs.json"
    : >"$WORK/calls.log"
    : >"$WORK/summary.md"
    local required=() var
    for var in GITHUB_REPOSITORY=owner/repo GH_TOKEN=dummy; do
        [ "${var%%=*}" = "$omit_var" ] || required+=("$var")
    done
    env -u GITHUB_REPOSITORY -u GH_TOKEN "${required[@]}" \
        PATH="$WORK/bin:$PATH" \
        STUB_RUNS="$WORK/runs.json" STUB_CALLS="$WORK/calls.log" \
        STUB_GH_FAIL="" STUB_DATE_FAIL="" NOW_EPOCH="${INVOKE_NOW-$NOW}" \
        GITHUB_STEP_SUMMARY="$WORK/summary.md" \
        bash "$SCRIPT" "$@" >/dev/null 2>&1
    got=$?
    if [ "$got" -eq "$want" ]; then
        echo "PASS: $name"
    else
        echo "FAIL: $name (expected exit $want, got $got)"
        FAILED=1
    fi
}

check_no_calls() {
    if [ ! -s "$WORK/calls.log" ]; then
        echo "PASS: $1"
    else
        echo "FAIL: $1 (APIへの問い合わせが行われた)"
        FAILED=1
    fi
}

check_summary() {
    if grep -qF "$1" "$WORK/summary.md"; then
        echo "PASS: $2"
    else
        echo "FAIL: $2 (Summaryに '$1' が現れない)"
        FAILED=1
    fi
}

check_calls() {
    if grep -qF "$1" "$WORK/calls.log"; then
        echo "PASS: $2"
    else
        echo "FAIL: $2 (呼び出しログに '$1' が現れない)"
        FAILED=1
    fi
}

check_single_call() {
    if [ "$(wc -l <"$WORK/calls.log")" -eq 1 ]; then
        echo "PASS: $1"
    else
        echo "FAIL: $1 (APIへの問い合わせが1回でない)"
        FAILED=1
    fi
}

# --- 実行一覧APIの応答(canned) --------------------------------------------------
runs_json() {
    printf '{"total_count":1,"workflow_runs":[{"id":123,"conclusion":"success","created_at":"%s"}]}' "$1"
}
EMPTY_RUNS='{"total_count":0,"workflow_runs":[]}'

# 2026-01-10T00:00:00Z のちょうど8日前
CREATED_EXACTLY_8D="2026-01-02T00:00:00Z"
# 7日23時間59分前
CREATED_JUST_UNDER_8D="2026-01-02T00:01:00Z"
# 十分に古い
CREATED_OLD="2025-12-01T00:00:00Z"

echo "--- 鮮度の判定 ---"
check 0 "直近の成功が8日未満なら緑にする" "$(runs_json "$CREATED_JUST_UNDER_8D")"
check_calls "actions/workflows/container-scan-scheduled.yaml/runs" "引数のワークフローの実行一覧へ問い合わせている"
check_calls "status=success" "成功した実行に絞って問い合わせている"
check_calls "per_page=1" "最新1件だけを要求している"
check_single_call "問い合わせは1リクエストで済んでいる"

echo "--- 境界値 ---"
check 1 "8日ちょうどなら赤にする(8日以上=赤)" "$(runs_json "$CREATED_EXACTLY_8D")"
check_summary "2026-01-02 00:00 UTC" "最終成功日時が報告される"
check_summary "8 日以上" "判定の基準が報告される"

check 1 "直近の成功が十分に古ければ赤にする" "$(runs_json "$CREATED_OLD")"
check_summary "2025-12-01 00:00 UTC" "最終成功日時が報告される"

echo "--- 成功ゼロ ---"
check 1 "成功した実行が一度も存在しなければ赤にする" "$EMPTY_RUNS"
check_summary "成功した実行が存在しません" "成功ゼロの旨が報告される"

echo "--- 判定不能 ---"
check 2 "APIへの問い合わせに失敗したら判定不能として2を返す(fail closed)" "" "yes"
check_summary "判定不能" "判定不能の見出しが出る"
check_summary "re-run" "失敗したrunのre-runで再実行する指示が出る"

check 2 "JSONを解釈できなければ判定不能として2を返す" "not-json"
check_summary "判定不能" "判定不能の見出しが出る"

check 2 "workflow_runs が配列でない応答は判定不能として2を返す" '{"message":"Not Found"}'
check_summary "判定不能" "判定不能の見出しが出る"

check 2 "created_at の書式を解釈できなければ判定不能として2を返す" "$(runs_json "bogus-date")"
check_summary "判定不能" "判定不能の見出しが出る"

echo "--- 入力の欠落 ---"
check_invocation 2 "引数がひとつも無ければ判定不能として2を返す" ""
check_no_calls "引数が無ければAPIへ問い合わせない"

check_invocation 2 "しきい値日数の引数が欠けていれば判定不能として2を返す" "" container-scan-scheduled.yaml
check_no_calls "引数が欠けていればAPIへ問い合わせない"

# 算術展開に英字を渡すと、bash は未定義変数として ERR トラップを経ずに
# 終了コード1で止まる。数値でない入力は算術に入る前に2へ倒す。
check_invocation 2 "しきい値日数が数値でなければ判定不能として2を返す" "" container-scan-scheduled.yaml abc
check_no_calls "しきい値日数が数値でなければAPIへ問い合わせない"

# 先頭が0の値は算術展開で8進数として読まれる。08・09 は8進数の範囲外で
# ERR トラップを経ずに終了コード1になり、010 は8日として黙って通る。
check_invocation 2 "しきい値日数が先頭0(08)なら判定不能として2を返す" "" container-scan-scheduled.yaml 08
check_no_calls "しきい値日数が先頭0ならAPIへ問い合わせない"

check_invocation 2 "しきい値日数が先頭0(010)なら判定不能として2を返す" "" container-scan-scheduled.yaml 010

check_invocation 2 "しきい値日数が0なら判定不能として2を返す" "" container-scan-scheduled.yaml 0

check_invocation 2 "しきい値日数の桁数が上限を超えれば判定不能として2を返す" "" \
    container-scan-scheduled.yaml 123456789012345678901

INVOKE_NOW=abc check_invocation 2 "NOW_EPOCH が数値でなければ判定不能として2を返す" "" container-scan-scheduled.yaml 8
check_no_calls "NOW_EPOCH が数値でなければAPIへ問い合わせない"

INVOKE_NOW=1e5 check_invocation 2 "NOW_EPOCH が指数表記なら判定不能として2を返す" "" container-scan-scheduled.yaml 8

INVOKE_NOW=01768003200 check_invocation 2 "NOW_EPOCH が先頭0なら判定不能として2を返す" "" container-scan-scheduled.yaml 8

INVOKE_NOW=123456789012345678901 check_invocation 2 "NOW_EPOCH の桁数が上限を超えれば判定不能として2を返す" "" \
    container-scan-scheduled.yaml 8

check_invocation 2 "GITHUB_REPOSITORY が無ければ判定不能として2を返す" GITHUB_REPOSITORY container-scan-scheduled.yaml 8
check_no_calls "GITHUB_REPOSITORY が無ければAPIへ問い合わせない"

check_invocation 2 "GH_TOKEN が無ければ判定不能として2を返す" GH_TOKEN container-scan-scheduled.yaml 8
check_no_calls "GH_TOKEN が無ければAPIへ問い合わせない"

check_invocation 0 "引数と環境変数がそろっていれば判定まで進む(入力検査の対照)" "" container-scan-scheduled.yaml 8

echo "--- 想定外の失敗 ---"
check 2 "ガードしていないコマンドが失敗したら逸脱ではなく判定不能として2を返す" \
    "$(runs_json "$CREATED_EXACTLY_8D")" "" "yes"
if grep -qF "定期スキャンが止まっています" "$WORK/summary.md"; then
    echo "FAIL: 想定外の失敗を逸脱として報告しない (逸脱の見出しが出ている)"
    FAILED=1
else
    echo "PASS: 想定外の失敗を逸脱として報告しない"
fi

if [ "$FAILED" -eq 0 ]; then
    echo "すべてのテストがPASSしました。"
else
    echo "失敗したテストがあります。"
fi
exit "$FAILED"
