#!/usr/bin/env bash
# =====================================================================
# check-canary-results.sh の自動テスト(canary-verify CI から実行)
#
# gh をスタブし、終了コードと報告の内容を検証する。
#   0 = 緑(通過) / 1 = 赤
#
# gh のスタブは実APIの形のJSONをそのまま返し、応答の解釈(PR検索応答からの
# PR特定・check-runs からの最新結論の選択)は本体側に実行させる。整形済みの
# 値を返すスタブにすると、応答形式の検証が範囲から外れ、解釈を壊しても緑の
# ままになる。
#
# PR検索はURL中のブランチ名から種別を切り出し、種別ごとのファイル
# ($STUB_DIR/pr_<種別>.json)を返す。check-runs はURL中のSHAごとに
# $STUB_DIR/checkruns_<sha>.json を返す(既存テストと同じ方式)。
#
# 対象年月は引数で 202601 に固定する(月の既定値のテストのみ引数を省略し、
# 実行時のUTC年月がブランチ名に使われることを呼び出しログで確認する)。
#
# 外部への問い合わせを行わないため、実行にネットワークを必要としない。
# =====================================================================
set -uo pipefail

SCRIPT="$(cd "$(dirname "$0")/.." && pwd)/check-canary-results.sh"
REAL_CHECKS="$(cd "$(dirname "$0")/../.." && pwd)/audit/required-checks.json"
WORK=$(mktemp -d) || exit 1
[ -n "$WORK" ] && [ -d "$WORK" ] || exit 1
trap 'rm -rf "$WORK"' EXIT
FAILED=0

mkdir -p "$WORK/bin"

# --- gh のスタブ ---------------------------------------------------------------
# 呼び出しの引数を $STUB_CALLS に記録し、URLに応じてcannedな応答を返す。
# PR検索は $STUB_DIR/pr_<種別>.json、check-runs は $STUB_DIR/checkruns_<sha>.json。
# STUB_FAIL_* で各APIの失敗を再現する。
cat >"$WORK/bin/gh" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"${STUB_CALLS:?}"
case "$*" in
*pulls*head=*)
    if [ -n "${STUB_FAIL_PULLS:-}" ]; then
        echo "stub: API failure" >&2
        exit 1
    fi
    type=$(printf '%s' "$*" | sed -n 's|.*canary/\(.*\)-[0-9]\{6\}.*|\1|p')
    cat "${STUB_DIR:?}/pr_${type}.json"
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

# 使い方: run <期待一覧パス> [pulls失敗] [check-runs失敗]
run() {
    : >"$WORK/calls.log"
    : >"$WORK/summary.md"
    PATH="$WORK/bin:$PATH" \
        STUB_CALLS="$WORK/calls.log" STUB_DIR="$WORK" \
        STUB_FAIL_PULLS="${2:-}" STUB_FAIL_CHECKRUNS="${3:-}" \
        GITHUB_REPOSITORY="owner/repo" GH_TOKEN="dummy" \
        GITHUB_STEP_SUMMARY="$WORK/summary.md" \
        bash "$SCRIPT" "$1" "202601" >/dev/null 2>&1
}

# 使い方: check <期待exit> <説明> [期待一覧パス] [pulls失敗] [check-runs失敗]
check() {
    local want="$1" name="$2" checks="${3:-$WORK/checks.json}" got
    run "$checks" "${4:-}" "${5:-}"
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

check_no_summary() {
    if grep -qF -- "$1" "$WORK/summary.md"; then
        echo "FAIL: $2 (Summaryに '$1' が現れてしまう)"
        FAILED=1
    else
        echo "PASS: $2"
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

# 書き込み操作の不在の表明(5.7)。gh api の既定はGETのため、メソッド指定・
# フィールド送信・PRサブコマンドがログに1件も無ければ読み取りのみと言える。
check_readonly_calls() {
    if grep -Eq -- '(^| )(-X|--method|-f|-F|--field|--raw-field|--input)( |$)| pr ' "$WORK/calls.log"; then
        echo "FAIL: $1 (書き込みを示す呼び出しがログに現れる)"
        FAILED=1
    elif grep -Evq '^api repos/' "$WORK/calls.log"; then
        echo "FAIL: $1 (gh api の読み取り以外の呼び出しがログに現れる)"
        FAILED=1
    else
        echo "PASS: $1"
    fi
}

# --- テストデータの組み立て ------------------------------------------------------
set_checks() { printf '%s' "$1" >"$WORK/checks.json"; }
set_pr() { printf '%s' "$2" >"$WORK/pr_$1.json"; }
set_checkruns() { printf '%s' "$2" >"$WORK/checkruns_$1.json"; }

# 使い方: pr <PR番号> <head SHA> [state(既定 open)]
pr() { printf '{"number":%s,"state":"%s","head":{"sha":"%s"},"merge_commit_sha":"mrg%s","base":{"ref":"main"}}' "$1" "${3:-open}" "$2" "$1"; }
# 使い方: crun <id> <context名> <status> <conclusion(JSON。文字列は引用符込み)> <started_at>
crun() { printf '{"id":%s,"name":"%s","status":"%s","conclusion":%s,"started_at":"%s"}' "$1" "$2" "$3" "$4" "$5"; }
# 使い方: runs <crunのカンマ連結>
runs() { printf '{"total_count":0,"check_runs":[%s]}' "$1"; }

TYPES="known-bug assertless-test skipped-test backend-failure vulnerable-dep container-vuln"

# 種別→期待チェックの対応(本体の定数と同じ表。テスト側でスタブ構築に使う)
expected_of() {
    case "$1" in
    known-bug) echo codex-review ;;
    assertless-test) echo frontend-test ;;
    skipped-test) echo escape-hatch ;;
    backend-failure) echo backend-test ;;
    vulnerable-dep) echo dependency-review ;;
    container-vuln) echo container-scan ;;
    esac
}

# 実物と同じスキーマの最小の期待一覧。カナリアの期待チェック5件を稼働中で
# 含める。container-scan は意図的に含めない(必須チェック未登録のため実物の
# 一覧にも無い。「一覧に無い期待チェックは稼働中とみなす」契約の検証)。
VALID_CHECKS='{
  "checks": [
    { "context": "codex-review", "mode": "always", "state": "active", "approval_gated": false },
    { "context": "frontend-test", "mode": "conditional", "state": "active", "approval_gated": false },
    { "context": "escape-hatch", "mode": "always", "state": "active", "approval_gated": true },
    { "context": "backend-test", "mode": "conditional", "state": "active", "approval_gated": false },
    { "context": "dependency-review", "mode": "always", "state": "active", "approval_gated": false },
    { "context": "gitleaks", "mode": "always", "state": "active", "approval_gated": false }
  ]
}'

# codex-review を停止中(#166)と記録した変種(5.8の検証用)
PAUSED_CHECKS='{
  "checks": [
    { "context": "codex-review", "mode": "always", "state": "paused", "approval_gated": false,
      "reason": "整備期間中はCIでのレビューを行わない", "issue": 166 },
    { "context": "frontend-test", "mode": "conditional", "state": "active", "approval_gated": false },
    { "context": "escape-hatch", "mode": "always", "state": "active", "approval_gated": true },
    { "context": "backend-test", "mode": "conditional", "state": "active", "approval_gated": false },
    { "context": "dependency-review", "mode": "always", "state": "active", "approval_gated": false }
  ]
}'

# 既定のスタブ状態に戻す。6種すべてPRが存在し、期待チェックがfailure(=正常)。
reset_defaults() {
    local t n=500
    set_checks "$VALID_CHECKS"
    for t in $TYPES; do
        n=$((n + 1))
        set_pr "$t" "[$(pr "$n" "sha_${t}")]"
        set_checkruns "sha_${t}" "$(runs "$(crun 1 "$(expected_of "$t")" completed '"failure"' "2026-01-04T00:00:00Z")")"
    done
}
reset_defaults

echo "--- 全種別が正常(5.1/5.2/5.6) ---"
check 0 "6種すべての期待チェックがfailureなら緑にする"
check_summary "正常" "正常の判定が報告に出る"
for t in $TYPES; do
    check_summary "$t" "判定一覧に種別 $t が出る(全種別の一覧を常に出力)"
done
check_calls "head=owner:canary/known-bug-202601" "ブランチ名 canary/<type>-<YYYYMM> でPRを検索している"
check_calls "state=all" "PR検索はstate=allで行う(closeされていても照合できる)"
check_readonly_calls "書き込みAPI・PR操作を一切呼んでいない(5.7)"

echo "--- container-vuln: 期待一覧に無い期待チェック(container-scan) ---"
# VALID_CHECKS に container-scan は無い。スキーマ検証エラーにせず「稼働中」と
# みなして3値判定されることは、上の緑と以下の赤の両方で確かめる。
set_checkruns sha_container-vuln "$(runs "$(crun 1 container-scan completed '"success"' "2026-01-04T00:00:00Z")")"
check 1 "期待一覧に無いcontainer-scanも稼働中として3値判定される(successなら赤)"
check_summary "判定側の故障" "判定側の故障として報告される"
reset_defaults

echo "--- success = 判定側の故障(5.3) ---"
set_checkruns sha_backend-failure "$(runs "$(crun 1 backend-test completed '"success"' "2026-01-04T00:00:00Z")")"
check 1 "期待チェックの結論がsuccessなら赤にする"
check_summary "判定側の故障" "実行されたが検知しなかった(判定側の故障)と報告される"
check_summary "backend-failure" "対象の種別が報告に出る"
reset_defaults

echo "--- skipped・実行なし = 実行されていない(5.4) ---"
set_checkruns sha_assertless-test "$(runs "$(crun 1 frontend-test completed '"skipped"' "2026-01-04T00:00:00Z")")"
check 1 "期待チェックが全check-runでskippedなら赤にする"
check_summary "実行されていない" "検査が実行されていないと報告される"
check_no_summary "判定側の故障" "実行されていない判定は判定側の故障と区別される"

set_checkruns sha_assertless-test "$(runs "$(crun 1 gitleaks completed '"success"' "2026-01-04T00:00:00Z")")"
check 1 "期待チェックのcheck-runが1件も無ければ赤にする(実行なし)"
check_summary "実行されていない" "実行なしも「実行されていない」として報告される"
reset_defaults

echo "--- 最新の結論で判定(同一SHAに複数check-run) ---"
# 後発のskippedは実行の証拠を上書きしない(週次と同じ多重発火対策)
set_checkruns sha_known-bug "$(runs "$(crun 1 codex-review completed '"failure"' "2026-01-04T00:00:00Z"),$(crun 2 codex-review completed '"skipped"' "2026-01-04T01:00:00Z")")"
check 0 "failureの後にskippedが追加されても実行の証拠(failure)で判定する"

# skipped以外が複数あれば最新の結論を採る(判定側を直して再実行した場合など)
set_checkruns sha_known-bug "$(runs "$(crun 1 codex-review completed '"success"' "2026-01-04T00:00:00Z"),$(crun 2 codex-review completed '"failure"' "2026-01-04T01:00:00Z")")"
check 0 "successの後にfailureがあれば最新の結論(failure)で正常と判定する"

set_checkruns sha_known-bug "$(runs "$(crun 1 codex-review completed '"failure"' "2026-01-04T00:00:00Z"),$(crun 2 codex-review completed '"success"' "2026-01-04T01:00:00Z")")"
check 1 "failureの後にsuccessがあれば最新の結論(success)で赤にする"
reset_defaults

echo "--- 想定外の結論 ---"
set_checkruns sha_skipped-test "$(runs "$(crun 1 escape-hatch completed '"cancelled"' "2026-01-04T00:00:00Z")")"
check 1 "failureでもsuccessでもskippedでもない結論(cancelled)は成功に倒さず赤にする"
check_summary "想定外の結論" "想定外の結論である旨が報告に出る"
reset_defaults

echo "--- paused = 停止中(記録済み)(5.8) ---"
set_checks "$PAUSED_CHECKS"
check 0 "期待チェックがpausedの種別は失敗と区別され、他が全て正常なら全体は緑にする"
check_summary "停止中(記録済み・#166)" "停止中(記録済み・参照Issue)として報告される"
check_summary "known-bug" "停止中の種別が判定一覧に出る"
check_no_calls "commits/sha_known-bug" "pausedの種別はcheck-runsを取得しない(判定は記録で決まる)"

# pausedでも他の種別の失敗は独立に赤にする
set_checkruns sha_vulnerable-dep "$(runs "$(crun 1 dependency-review completed '"success"' "2026-01-04T00:00:00Z")")"
check 1 "pausedの種別があっても、他の種別の失敗は赤にする"
check_summary "停止中(記録済み・#166)" "赤のときも停止中の種別は失敗と区別して報告される"
reset_defaults

echo "--- 6件未満 = 生成側異常(5.5) ---"
set_pr container-vuln "[]"
check 1 "PRが5件しか無ければ赤にする"
check_summary "PR欠落" "欠落した種別がPR欠落として報告される"
check_summary "生成側" "生成側の異常である旨が報告に出る"
check_summary "5件" "見つかった件数が報告に出る"

set_pr known-bug "[]"
set_pr container-vuln "[]"
check 1 "複数欠落しても赤にする"
check_summary "4件" "見つかった件数が報告に出る"
reset_defaults

echo "--- 同一ブランチに複数PR ---"
set_pr known-bug "[$(pr 601 sha_old closed),$(pr 602 sha_new)]"
set_checkruns sha_new "$(runs "$(crun 1 codex-review completed '"failure"' "2026-01-04T00:00:00Z")")"
check 0 "同一ブランチにPRが複数あれば最新(番号最大)のPRで判定する"
check_calls "commits/sha_new" "最新PRのheadのcheck-runsを取得している"
check_no_calls "commits/sha_old" "古いPRのcheck-runsは取得しない"

echo "--- closedのPRも照合できる ---"
set_pr known-bug "[$(pr 603 sha_closed closed)]"
set_checkruns sha_closed "$(runs "$(crun 1 codex-review completed '"failure"' "2026-01-04T00:00:00Z")")"
check 0 "closeされたカナリアPRでも照合できる(state=all検索)"
reset_defaults

echo "--- 対象年月の既定値 ---"
# 引数を省略したときは実行時のUTC年月をブランチ名に使う。スタブは月を見ずに
# 種別ファイルを返すため、呼び出しログのブランチ名で確認する。
CUR_MONTH=$(date -u +%Y%m)
: >"$WORK/calls.log"
: >"$WORK/summary.md"
PATH="$WORK/bin:$PATH" \
    STUB_CALLS="$WORK/calls.log" STUB_DIR="$WORK" \
    GITHUB_REPOSITORY="owner/repo" GH_TOKEN="dummy" \
    GITHUB_STEP_SUMMARY="$WORK/summary.md" \
    bash "$SCRIPT" "$WORK/checks.json" >/dev/null 2>&1
if [ $? -eq 0 ]; then
    echo "PASS: 対象年月を省略しても実行できる"
else
    echo "FAIL: 対象年月を省略しても実行できる"
    FAILED=1
fi
check_calls "canary/known-bug-${CUR_MONTH}" "省略時は実行時のUTC年月がブランチ名に使われる"

echo "--- 期待一覧のスキーマ検証 ---"
set_checks '{"checks":[{"context":"gitleaks","mode":"always","state":"active"}]}'
check 1 "必須フィールド(approval_gated)の欠落は判定不能として赤にする"
check_summary "判定不能" "判定不能の見出しが出る"
check_no_calls "pulls" "スキーマ検証はAPIへの問い合わせより先に行われる"

set_checks '{"checks":[{"context":"gitleaks","mode":"always","state":"disabled","approval_gated":false}]}'
check 1 "未知のstateは判定不能として赤にする"

set_checks '{"checks":[{"context":"gitleaks","mode":"sometimes","state":"active","approval_gated":false}]}'
check 1 "未知のmodeは判定不能として赤にする"

set_checks '{"checks":[{"context":"gitleaks","mode":"always","state":"paused","approval_gated":false}]}'
check 1 "pausedなのにreason/issueが無ければ判定不能として赤にする"

set_checks '{"checks":[{"context":"gitleaks","mode":"always","state":"active","approval_gated":false,"note":"x"}]}'
check 1 "未知のフィールドは判定不能として赤にする"

set_checks '{"checks":{"context":"gitleaks"}}'
check 1 "checksが配列でなければ判定不能として赤にする"

set_checks 'not-json'
check 1 "期待一覧をJSONとして解釈できなければ判定不能として赤にする"

# 実物の期待一覧(codex-review が paused)でも動く。known-bug は停止中扱い、
# 他5種が正常なら緑(container-scan が一覧に無くてもスキーマ検証を通過する)。
reset_defaults
check 0 "実物の期待一覧(required-checks.json)はスキーマ検証を通過し、pausedの記録が反映される" "$REAL_CHECKS"
check_summary "停止中(記録済み・#166)" "実物の期待一覧のpaused記録(codex-review)が反映される"

reset_defaults

echo "--- 判定不能(API失敗・想定外の応答) ---"
check 1 "PR検索APIへの問い合わせに失敗したら判定不能として赤にする(fail closed)" "$WORK/checks.json" "yes"
check_summary "判定不能" "判定不能の見出しが出る"
check_summary "再実行" "re-runまたはworkflow_dispatchで再実行する指示が出る"

set_pr known-bug '{"message":"Not Found"}'
check 1 "PR検索の応答が配列でなければ判定不能として赤にする"
check_summary "判定不能" "判定不能の見出しが出る"
reset_defaults

check 1 "check-runs APIへの問い合わせに失敗したら判定不能として赤にする" "$WORK/checks.json" "" "yes"
check_summary "判定不能" "判定不能の見出しが出る"

set_checkruns sha_known-bug '{"message":"Not Found"}'
check 1 "check-runsの応答を解釈できなければ判定不能として赤にする"
check_summary "判定不能" "判定不能の見出しが出る"
reset_defaults

if [ "$FAILED" -eq 0 ]; then
    echo "すべてのテストがPASSしました。"
else
    echo "失敗したテストがあります。"
fi
exit "$FAILED"
