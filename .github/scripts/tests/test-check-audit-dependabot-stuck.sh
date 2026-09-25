#!/usr/bin/env bash
# =====================================================================
# check-audit-dependabot-stuck.sh の自動テスト(audit-weekly CI から実行)
#
# gh をスタブし、終了コードと報告の内容を検証する。
#   0 = 逸脱なし / 1 = 逸脱あり / 2 = 判定不能
#
# gh のスタブは実APIの形のJSONをそのまま返し、応答の解釈(配列であることの
# 検査・check-runs の集計・最新の選択)は本体側に実行させる。整形済みの値を
# 返すスタブにすると、応答形式の検証が範囲から外れ、解釈を壊しても緑のまま
# になる。
#
# 外部への問い合わせを行わないため、実行にネットワークを必要としない。
# =====================================================================
set -uo pipefail

SCRIPT="$(cd "$(dirname "$0")/.." && pwd)/check-audit-dependabot-stuck.sh"
REAL_CHECKS="$(cd "$(dirname "$0")/../.." && pwd)/audit/required-checks.json"
WORK=$(mktemp -d) || exit 1
[ -n "$WORK" ] && [ -d "$WORK" ] || exit 1
trap 'rm -rf "$WORK"' EXIT
FAILED=0

mkdir -p "$WORK/bin"

# --- gh のスタブ ---------------------------------------------------------------
# 呼び出しの引数を $STUB_CALLS に記録し、URLに応じてcannedな応答を返す。
# PR一覧は $STUB_PULLS、check-runs はURL中のSHAごとに $STUB_DIR/checkruns_<sha>.json。
# STUB_FAIL_PULLS / STUB_FAIL_CHECKRUNS で各APIの失敗を再現する。
cat >"$WORK/bin/gh" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"${STUB_CALLS:?}"
case "$*" in
*/pulls*)
    if [ -n "${STUB_FAIL_PULLS:-}" ]; then
        echo "stub: API failure" >&2
        exit 1
    fi
    cat "${STUB_PULLS:?}"
    ;;
*/check-runs*)
    if [ -n "${STUB_FAIL_CHECKRUNS:-}" ]; then
        echo "stub: API failure" >&2
        exit 1
    fi
    sha=$(printf '%s' "$*" | sed -n 's|.*commits/\([^/?]*\)/check-runs.*|\1|p')
    cat "${STUB_DIR:?}/checkruns_${sha}.json"
    ;;
*)
    echo "stub: unexpected call: $*" >&2
    exit 1
    ;;
esac
STUB
chmod +x "$WORK/bin/gh"

# --- jq のラッパ -----------------------------------------------------------------
# STUB_JQ_FAIL が設定されているときだけ、滞留の列挙(select(.gated | not))を
# 行う呼び出しを異常終了させる。本体でガードしていないコマンドが想定外に
# 失敗した状況の再現。それ以外の呼び出しは本物の jq に渡す。
REAL_JQ=$(command -v jq) || exit 1
cat >"$WORK/bin/jq" <<STUB
#!/usr/bin/env bash
if [ -n "\${STUB_JQ_FAIL:-}" ]; then
    for arg in "\$@"; do
        case "\$arg" in
        *"select(.gated | not)"*)
            echo "stub: jq failure" >&2
            exit 1
            ;;
        esac
    done
fi
exec "$REAL_JQ" "\$@"
STUB
chmod +x "$WORK/bin/jq"

# 使い方: run <期待一覧パス> [pulls失敗] [check-runs失敗] [jq失敗]
run() {
    : >"$WORK/calls.log"
    : >"$WORK/summary.md"
    PATH="$WORK/bin:$PATH" \
        STUB_CALLS="$WORK/calls.log" STUB_PULLS="$WORK/pulls.json" STUB_DIR="$WORK" \
        STUB_FAIL_PULLS="${2:-}" STUB_FAIL_CHECKRUNS="${3:-}" STUB_JQ_FAIL="${4:-}" \
        GITHUB_REPOSITORY="owner/repo" GH_TOKEN="dummy" \
        GITHUB_STEP_SUMMARY="$WORK/summary.md" \
        bash "$SCRIPT" "$1" >/dev/null 2>&1
}

# 使い方: check <期待exit> <説明> [期待一覧パス] [pulls失敗] [check-runs失敗] [jq失敗]
check() {
    local want="$1" name="$2" checks="${3:-$WORK/checks.json}" got
    run "$checks" "${4:-}" "${5:-}" "${6:-}"
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
# 使い方: check_invocation <期待exit> <説明> <与えない必須環境変数名 または ""> [引数...]
check_invocation() {
    local want="$1" name="$2" omit_var="$3" got
    shift 3
    : >"$WORK/calls.log"
    : >"$WORK/summary.md"
    local required=() var
    for var in GITHUB_REPOSITORY=owner/repo GH_TOKEN=dummy; do
        [ "${var%%=*}" = "$omit_var" ] || required+=("$var")
    done
    env -u GITHUB_REPOSITORY -u GH_TOKEN "${required[@]}" \
        PATH="$WORK/bin:$PATH" \
        STUB_CALLS="$WORK/calls.log" STUB_PULLS="$WORK/pulls.json" STUB_DIR="$WORK" \
        STUB_FAIL_PULLS="" STUB_FAIL_CHECKRUNS="" STUB_JQ_FAIL="" \
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

check_summary() {
    # パターンが「- 」で始まっても引数として扱えるよう -- を挟む
    if grep -qF -- "$1" "$WORK/summary.md"; then
        echo "PASS: $2"
    else
        echo "FAIL: $2 (Summaryに '$1' が現れない)"
        FAILED=1
    fi
}

check_calls() {
    if grep -qF -- "$1" "$WORK/calls.log"; then
        echo "PASS: $2"
    else
        echo "FAIL: $2 (呼び出しログに '$1' が現れない)"
        FAILED=1
    fi
}

check_no_calls() {
    if grep -qF -- "$1" "$WORK/calls.log"; then
        echo "FAIL: $2 (呼び出しログに '$1' が現れてしまう)"
        FAILED=1
    else
        echo "PASS: $2"
    fi
}

# --- テストデータの組み立て ------------------------------------------------------
set_checks() { printf '%s' "$1" >"$WORK/checks.json"; }
set_pulls() { printf '%s' "$1" >"$WORK/pulls.json"; }
set_checkruns() { printf '%s' "$2" >"$WORK/checkruns_$1.json"; }

# 使い方: pull <PR番号> <author> <head SHA>
pull() { printf '{"number":%s,"user":{"login":"%s"},"head":{"sha":"%s"}}' "$1" "$2" "$3"; }
# 使い方: crun <id> <context名> <status> <conclusion(JSON。文字列は引用符込み)> <started_at>
crun() { printf '{"id":%s,"name":"%s","status":"%s","conclusion":%s,"started_at":"%s"}' "$1" "$2" "$3" "$4" "$5"; }
# 使い方: runs <crunのカンマ連結>
runs() { printf '{"total_count":0,"check_runs":[%s]}' "$1"; }

# 実物と同じスキーマの最小の期待一覧。
# 非approval_gated(active/paused)+approval_gated を1件ずつ以上含める。
VALID_CHECKS='{
  "checks": [
    { "context": "backend-test", "mode": "conditional", "state": "active", "approval_gated": false },
    { "context": "gitleaks", "mode": "always", "state": "active", "approval_gated": false },
    { "context": "dependency-gate", "mode": "always", "state": "active", "approval_gated": true },
    { "context": "codex-review", "mode": "always", "state": "paused", "approval_gated": false,
      "reason": "整備期間中はCIでのレビューを行わない", "issue": 166 }
  ]
}'
set_checks "$VALID_CHECKS"

DEPENDABOT="dependabot[bot]"

echo "--- open PRゼロ・対象外PR ---"
set_pulls "[]"
check 0 "openのPRが無ければ緑にする"
check_calls "repos/owner/repo/pulls" "openのPR一覧へ問い合わせている"
check_calls "state=open" "openのPRに絞って問い合わせている"
check_summary "承認待ち" "承認待ち一覧の節は緑でも常に報告に出る"
check_summary "- なし" "承認待ちが無いことが明示される"

set_pulls "[$(pull 900 "renovate[bot]" sha900)]"
check 0 "Dependabot以外のopen PRしか無ければ緑にする"
check_no_calls "check-runs" "対象外PRのcheck-runsは取得しない"

echo "--- 全緑・実行中 ---"
set_pulls "[$(pull 101 "$DEPENDABOT" sha101)]"
set_checkruns sha101 "$(runs "$(crun 1 backend-test completed '"success"' "2026-01-01T00:00:00Z"),$(crun 2 gitleaks completed '"success"' "2026-01-01T00:00:00Z")")"
check 0 "すべて緑なら緑にする"
check_calls "commits/sha101/check-runs" "PRのheadコミットのcheck-runsを取得している"

set_checkruns sha101 "$(runs "$(crun 1 gitleaks in_progress null "2026-01-01T00:00:00Z")")"
check 0 "実行中(結論なし)は滞留として扱わない"

set_checkruns sha101 "$(runs "$(crun 1 backend-test completed '"skipped"' "2026-01-01T00:00:00Z")")"
check 0 "skippedは滞留として扱わない(チェック失敗以外の滞留は見ない)"

echo "--- 滞留(非approval_gatedのfailure) ---"
set_checkruns sha101 "$(runs "$(crun 1 gitleaks completed '"failure"' "2026-01-01T00:00:00Z")")"
check 1 "非approval_gatedのfailureが1件あれば赤にする"
check_summary "#101" "対象のPR番号が報告に出る"
check_summary "gitleaks (failure)" "失敗しているチェック名と結論が報告に出る"

set_checkruns sha101 "$(runs "$(crun 1 gitleaks completed '"failure"' "2026-01-01T00:00:00Z"),$(crun 2 backend-test completed '"failure"' "2026-01-01T00:00:00Z")")"
check 1 "複数のfailureがあれば赤にする"
check_summary "#101: backend-test (failure), gitleaks (failure)" "失敗しているチェック名と結論がすべて列挙される"

set_pulls "[$(pull 101 "$DEPENDABOT" sha101),$(pull 102 "$DEPENDABOT" sha102)]"
set_checkruns sha101 "$(runs "$(crun 1 gitleaks completed '"failure"' "2026-01-01T00:00:00Z")")"
set_checkruns sha102 "$(runs "$(crun 1 dependency-gate completed '"failure"' "2026-01-01T00:00:00Z")")"
check 1 "滞留と承認待ちが混在していれば赤にする(滞留が優先)"
check_summary "#101" "滞留しているPR番号が報告に出る"
check_summary "#102: dependency-gate" "承認待ちのPRも一覧に出る"

echo "--- 滞留(failure以外の滞留結論) ---"
set_pulls "[$(pull 101 "$DEPENDABOT" sha101)]"
set_checkruns sha101 "$(runs "$(crun 1 gitleaks completed '"cancelled"' "2026-01-01T00:00:00Z")")"
check 1 "非approval_gatedのcancelledは滞留として赤にする"
check_summary "#101" "対象のPR番号が報告に出る"
check_summary "gitleaks (cancelled)" "cancelledの結論がチェック名に併記される"

set_checkruns sha101 "$(runs "$(crun 1 gitleaks completed '"timed_out"' "2026-01-01T00:00:00Z")")"
check 1 "非approval_gatedのtimed_outは滞留として赤にする"

set_checkruns sha101 "$(runs "$(crun 1 gitleaks completed '"action_required"' "2026-01-01T00:00:00Z")")"
check 1 "非approval_gatedのaction_requiredは滞留として赤にする"

set_checkruns sha101 "$(runs "$(crun 1 dependency-gate completed '"cancelled"' "2026-01-01T00:00:00Z")")"
check 0 "approval_gatedのcancelledは緑にする(承認待ち扱い)"
check_summary "#101: dependency-gate (cancelled)" "承認待ちのPR番号とチェック名と結論が報告に出る"

set_checkruns sha101 "$(runs "$(crun 1 backend-test completed '"neutral"' "2026-01-01T00:00:00Z")")"
check 0 "neutralは滞留として扱わない"

echo "--- 承認待ちのみ(approval_gatedのfailure) ---"
set_pulls "[$(pull 101 "$DEPENDABOT" sha101)]"
set_checkruns sha101 "$(runs "$(crun 1 dependency-gate completed '"failure"' "2026-01-01T00:00:00Z"),$(crun 2 gitleaks completed '"success"' "2026-01-01T00:00:00Z")")"
check 0 "approval_gatedのfailureのみなら緑にする"
check_summary "承認待ち" "承認待ちとして報告される"
check_summary "#101: dependency-gate" "承認待ちのPR番号とチェック名が報告に出る"

echo "--- 同一contextの複数check-run(最新優先) ---"
set_checkruns sha101 "$(runs "$(crun 1 gitleaks completed '"failure"' "2026-01-01T00:00:00Z"),$(crun 2 gitleaks completed '"success"' "2026-01-02T00:00:00Z")")"
check 0 "古いfailure+新しいsuccessは緑にする(最新の結論で判定)"

set_checkruns sha101 "$(runs "$(crun 2 gitleaks completed '"success"' "2026-01-01T00:00:00Z"),$(crun 3 gitleaks completed '"failure"' "2026-01-02T00:00:00Z")")"
check 1 "古いsuccess+新しいfailureは赤にする(最新の結論で判定)"

echo "--- 期待一覧に載らないcontext ---"
set_checkruns sha101 "$(runs "$(crun 1 container-scan completed '"failure"' "2026-01-01T00:00:00Z")")"
check 0 "期待一覧に載らないcontextのfailureは判定に使わない"

echo "--- 期待一覧のスキーマ検証 ---"
set_pulls "[]"
set_checks '{"checks":[{"context":"gitleaks","mode":"always","state":"active"}]}'
check 2 "必須フィールド(approval_gated)の欠落は判定不能として2を返す"
check_summary "判定不能" "判定不能の見出しが出る"
check_no_calls "pulls" "スキーマ検証はAPIへの問い合わせより先に行われる"

set_checks '{"checks":[{"context":"gitleaks","mode":"always","state":"disabled","approval_gated":false}]}'
check 2 "未知のstateは判定不能として2を返す"
check_summary "判定不能" "判定不能の見出しが出る"

set_checks '{"checks":[{"context":"gitleaks","mode":"sometimes","state":"active","approval_gated":false}]}'
check 2 "未知のmodeは判定不能として2を返す"

set_checks '{"checks":[{"context":"gitleaks","mode":"always","state":"paused","approval_gated":false}]}'
check 2 "pausedなのにreason/issueが無ければ判定不能として2を返す"

set_checks '{"checks":[{"context":"gitleaks","mode":"always","state":"active","approval_gated":false,"note":"x"}]}'
check 2 "未知のフィールドは判定不能として2を返す"

set_checks '{"checks":{"context":"gitleaks"}}'
check 2 "checksが配列でなければ判定不能として2を返す"

set_checks 'not-json'
check 2 "期待一覧をJSONとして解釈できなければ判定不能として2を返す"

check 0 "実物の期待一覧(required-checks.json)はスキーマ検証を通過する" "$REAL_CHECKS"

set_checks "$VALID_CHECKS"

echo "--- 判定不能(API失敗・想定外の応答) ---"
set_pulls "[]"
check 2 "PR一覧APIへの問い合わせに失敗したら判定不能として2を返す(fail closed)" "$WORK/checks.json" "yes"
check_summary "判定不能" "判定不能の見出しが出る"
check_summary "re-run" "失敗したrunのre-runで再実行する指示が出る"

set_pulls '{"message":"Not Found"}'
check 2 "PR一覧の応答が配列でなければ判定不能として2を返す"
check_summary "判定不能" "判定不能の見出しが出る"

set_pulls "[$(pull 101 "$DEPENDABOT" sha101)]"
set_checkruns sha101 "$(runs "$(crun 1 gitleaks completed '"success"' "2026-01-01T00:00:00Z")")"
check 2 "check-runs APIへの問い合わせに失敗したら判定不能として2を返す" "$WORK/checks.json" "" "yes"
check_summary "判定不能" "判定不能の見出しが出る"

set_checkruns sha101 '{"message":"Not Found"}'
check 2 "check-runsの応答を解釈できなければ判定不能として2を返す"
check_summary "判定不能" "判定不能の見出しが出る"

echo "--- 入力の欠落 ---"
set_checks "$VALID_CHECKS"
set_pulls "[]"
check_invocation 2 "期待一覧の引数が無ければ判定不能として2を返す" ""
check_no_calls "repos/" "引数が無ければAPIへ問い合わせない"

check_invocation 2 "期待一覧の引数が空文字なら判定不能として2を返す" "" ""
check_no_calls "repos/" "引数が空文字ならAPIへ問い合わせない"

check_invocation 2 "GITHUB_REPOSITORY が無ければ判定不能として2を返す" GITHUB_REPOSITORY "$WORK/checks.json"
check_no_calls "repos/" "GITHUB_REPOSITORY が無ければAPIへ問い合わせない"

check_invocation 2 "GH_TOKEN が無ければ判定不能として2を返す" GH_TOKEN "$WORK/checks.json"
check_no_calls "repos/" "GH_TOKEN が無ければAPIへ問い合わせない"

check_invocation 0 "引数と環境変数がそろっていれば判定まで進む(入力検査の対照)" "" "$WORK/checks.json"
check_calls "repos/owner/repo/pulls" "入力がそろっていればPR一覧へ問い合わせる"

echo "--- 想定外の失敗 ---"
set_pulls "[$(pull 101 "$DEPENDABOT" sha101)]"
set_checkruns sha101 "$(runs "$(crun 1 gitleaks completed '"failure"' "2026-01-01T00:00:00Z")")"
check 2 "ガードしていないコマンドが失敗したら逸脱ではなく判定不能として2を返す" \
    "$WORK/checks.json" "" "" "yes"
if grep -qF "必須チェックが通らないまま止まっている" "$WORK/summary.md"; then
    echo "FAIL: 想定外の失敗を逸脱として報告しない (逸脱の見出しが出ている)"
    FAILED=1
else
    echo "PASS: 想定外の失敗を逸脱として報告しない"
fi
# 対照: 同じ入力で jq を失敗させなければ逸脱(1)になる。上の2が入力の違いで
# 出たのではなく、想定外の失敗によるものであることを確かめる。
check 1 "同じ入力で想定外の失敗が無ければ逸脱として1を返す(対照)"

if [ "$FAILED" -eq 0 ]; then
    echo "すべてのテストがPASSしました。"
else
    echo "失敗したテストがあります。"
fi
exit "$FAILED"
