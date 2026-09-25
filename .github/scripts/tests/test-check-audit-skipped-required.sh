#!/usr/bin/env bash
# =====================================================================
# check-audit-skipped-required.sh の自動テスト(audit-weekly CI から実行)
#
# gh をスタブし、終了コードと報告の内容を検証する。
#   0 = 逸脱なし / 1 = 逸脱あり / 2 = 判定不能
#
# gh のスタブは実APIの形のJSONをそのまま返し、応答の解釈(ruleset応答からの
# context抽出・実行一覧からの前回run選択・check-runs の集計)は本体側に実行
# させる。整形済みの値を返すスタブにすると、応答形式の検証が範囲から外れ、
# 解釈を壊しても緑のままになる。
#
# 対象期間の判定は時刻に依存するため、NOW_EPOCH で 2026-01-10T00:00:00Z に
# 固定する(7日窓の下限 = 2026-01-03T00:00:00Z)。
#
# 外部への問い合わせを行わないため、実行にネットワークを必要としない。
# =====================================================================
set -uo pipefail

SCRIPT="$(cd "$(dirname "$0")/.." && pwd)/check-audit-skipped-required.sh"
REAL_CHECKS="$(cd "$(dirname "$0")/../.." && pwd)/audit/required-checks.json"
WORK=$(mktemp -d) || exit 1
[ -n "$WORK" ] && [ -d "$WORK" ] || exit 1
trap 'rm -rf "$WORK"' EXIT
FAILED=0

# 判定の基準時刻。2026-01-10T00:00:00Z
NOW=1768003200

mkdir -p "$WORK/bin"

# --- gh のスタブ ---------------------------------------------------------------
# 呼び出しの引数を $STUB_CALLS に記録し、URLに応じてcannedな応答を返す。
# ruleset は $STUB_RULES、自ワークフローの実行一覧は $STUB_WFRUNS、
# PR一覧は $STUB_PULLS、check-runs はURL中のSHAごとに $STUB_DIR/checkruns_<sha>.json。
# STUB_FAIL_* で各APIの失敗を再現する。
cat >"$WORK/bin/gh" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"${STUB_CALLS:?}"
case "$*" in
*rules/branches/*)
    if [ -n "${STUB_FAIL_RULES:-}" ]; then
        echo "stub: API failure" >&2
        exit 1
    fi
    cat "${STUB_RULES:?}"
    ;;
*actions/workflows/*/runs*)
    if [ -n "${STUB_FAIL_WFRUNS:-}" ]; then
        echo "stub: API failure" >&2
        exit 1
    fi
    cat "${STUB_WFRUNS:?}"
    ;;
*/check-runs*)
    if [ -n "${STUB_FAIL_CHECKRUNS:-}" ]; then
        echo "stub: API failure" >&2
        exit 1
    fi
    sha=$(printf '%s' "$*" | sed -n 's|.*commits/\([^/?]*\)/check-runs.*|\1|p')
    cat "${STUB_DIR:?}/checkruns_${sha}.json"
    ;;
*/pulls*)
    if [ -n "${STUB_FAIL_PULLS:-}" ]; then
        echo "stub: API failure" >&2
        exit 1
    fi
    cat "${STUB_PULLS:?}"
    ;;
*)
    echo "stub: unexpected call: $*" >&2
    exit 1
    ;;
esac
STUB
chmod +x "$WORK/bin/gh"

# 現在のrunのID。テスト側から変更できる(既定 9999)。
RUN_ID=9999

# --- jq のラッパ -----------------------------------------------------------------
# STUB_JQ_FAIL が設定されているときだけ、違反の列挙(.violations | join)を
# 行う呼び出しを異常終了させる。本体でガードしていないコマンドが想定外に
# 失敗した状況の再現。それ以外の呼び出しは本物の jq に渡す。
REAL_JQ=$(command -v jq) || exit 1
cat >"$WORK/bin/jq" <<STUB
#!/usr/bin/env bash
if [ -n "\${STUB_JQ_FAIL:-}" ]; then
    for arg in "\$@"; do
        case "\$arg" in
        *".violations | join"*)
            echo "stub: jq failure" >&2
            exit 1
            ;;
        esac
    done
fi
exec "$REAL_JQ" "\$@"
STUB
chmod +x "$WORK/bin/jq"

# 使い方: run <期待一覧パス> [rules失敗] [wfruns失敗] [pulls失敗] [check-runs失敗] [jq失敗]
run() {
    : >"$WORK/calls.log"
    : >"$WORK/summary.md"
    PATH="$WORK/bin:$PATH" \
        STUB_CALLS="$WORK/calls.log" STUB_RULES="$WORK/rules.json" \
        STUB_WFRUNS="$WORK/wfruns.json" STUB_PULLS="$WORK/pulls.json" STUB_DIR="$WORK" \
        STUB_FAIL_RULES="${2:-}" STUB_FAIL_WFRUNS="${3:-}" \
        STUB_FAIL_PULLS="${4:-}" STUB_FAIL_CHECKRUNS="${5:-}" STUB_JQ_FAIL="${6:-}" \
        GITHUB_REPOSITORY="owner/repo" GH_TOKEN="dummy" \
        GITHUB_RUN_ID="$RUN_ID" NOW_EPOCH="$NOW" \
        GITHUB_STEP_SUMMARY="${RUN_SUMMARY-$WORK/summary.md}" \
        bash "$SCRIPT" "$1" >/dev/null 2>&1
}

# 使い方: check <期待exit> <説明> [期待一覧パス] [rules失敗] [wfruns失敗] [pulls失敗] [check-runs失敗] [jq失敗]
check() {
    local want="$1" name="$2" checks="${3:-$WORK/checks.json}" got
    run "$checks" "${4:-}" "${5:-}" "${6:-}" "${7:-}" "${8:-}"
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
    : >"$WORK/calls.log"
    : >"$WORK/summary.md"
    local required=() var
    for var in GITHUB_REPOSITORY=owner/repo GH_TOKEN=dummy "GITHUB_RUN_ID=$RUN_ID"; do
        [ "${var%%=*}" = "$omit_var" ] || required+=("$var")
    done
    env -u GITHUB_REPOSITORY -u GH_TOKEN -u GITHUB_RUN_ID "${required[@]}" \
        PATH="$WORK/bin:$PATH" \
        STUB_CALLS="$WORK/calls.log" STUB_RULES="$WORK/rules.json" \
        STUB_WFRUNS="$WORK/wfruns.json" STUB_PULLS="$WORK/pulls.json" STUB_DIR="$WORK" \
        STUB_FAIL_RULES="" STUB_FAIL_WFRUNS="" STUB_FAIL_PULLS="" STUB_FAIL_CHECKRUNS="" \
        STUB_JQ_FAIL="" NOW_EPOCH="${INVOKE_NOW-$NOW}" \
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
set_rules() { printf '%s' "$1" >"$WORK/rules.json"; }
set_wfruns() { printf '%s' "$1" >"$WORK/wfruns.json"; }
set_pulls() { printf '%s' "$1" >"$WORK/pulls.json"; }
set_checkruns() { printf '%s' "$2" >"$WORK/checkruns_$1.json"; }

# 実APIと同じ形のruleset応答を組み立てる。引数: 必須チェックのcontext名の列。
# required_status_checks 以外のルール(deletion等)も含め、抽出側の選別を検証する。
rules_with() {
    local items="" c
    for c in "$@"; do
        items="${items:+${items},}{\"context\":\"${c}\",\"integration_id\":15368}"
    done
    printf '[{"type":"deletion","ruleset_source_type":"Repository","ruleset_source":"owner/repo","ruleset_id":1},'
    printf '{"type":"required_status_checks","parameters":{"strict_required_status_checks_policy":true,"do_not_enforce_on_create":false,"required_status_checks":[%s]},"ruleset_source_type":"Repository","ruleset_source":"owner/repo","ruleset_id":1}]' "$items"
}

# 使い方: wfrun <run ID> <created_at>
wfrun() { printf '{"id":%s,"created_at":"%s","conclusion":"success"}' "$1" "$2"; }
# 使い方: wfruns <wfrunのカンマ連結>
wfruns() { printf '{"total_count":0,"workflow_runs":[%s]}' "$1"; }

# 使い方: pull <PR番号> <merged_at(JSON。文字列は引用符込み)> <head SHA> <merge_commit SHA>
pull() { printf '{"number":%s,"state":"closed","merged_at":%s,"head":{"sha":"%s"},"merge_commit_sha":"%s","base":{"ref":"main"}}' "$1" "$2" "$3" "$4"; }
# 使い方: crun <id> <context名> <status> <conclusion(JSON。文字列は引用符込み)> <started_at>
crun() { printf '{"id":%s,"name":"%s","status":"%s","conclusion":%s,"started_at":"%s"}' "$1" "$2" "$3" "$4" "$5"; }
# 使い方: runs <crunのカンマ連結>
runs() { printf '{"total_count":0,"check_runs":[%s]}' "$1"; }

# 実物と同じスキーマの最小の期待一覧。
# always/conditional・active/paused・approval_gated を1件ずつ以上含める。
# always+active は gitleaks と dependency-gate の2件。
VALID_CHECKS='{
  "checks": [
    { "context": "backend-test", "mode": "conditional", "state": "active", "approval_gated": false },
    { "context": "gitleaks", "mode": "always", "state": "active", "approval_gated": false },
    { "context": "dependency-gate", "mode": "always", "state": "active", "approval_gated": true },
    { "context": "codex-review", "mode": "always", "state": "paused", "approval_gated": false,
      "reason": "整備期間中はCIでのレビューを行わない", "issue": 166 }
  ]
}'

# 既定のスタブ状態に戻す。
# 実行一覧: 現在のrun(id 9999, 2026-01-10)+前回run(id 100, 2026-01-08)。
# 前回runのcreated_at(2026-01-08T00:00:00Z)がスキップ検知の下限になる。
reset_defaults() {
    RUN_ID=9999
    set_checks "$VALID_CHECKS"
    set_rules "$(rules_with backend-test codex-review dependency-gate gitleaks)"
    set_wfruns "$(wfruns "$(wfrun 9999 "2026-01-10T00:00:00Z"),$(wfrun 100 "2026-01-08T00:00:00Z")")"
    set_pulls "[]"
}
reset_defaults

echo "--- 集合照合(3.4) ---"
check 0 "rulesetと期待一覧のcontext集合が一致すれば緑にする(pausedも集合には含める=状態を照合に使わない)"
check_calls "rules/branches/main" "rulesetのAPIへ問い合わせている"
check_calls "state=closed" "PR一覧はclosedに絞って問い合わせている"
check_calls "base=main" "PR一覧はbase=mainに絞って問い合わせている"
check_summary "- なし" "停止中スキップが無いことが明示される"

set_rules "$(rules_with backend-test codex-review dependency-gate)"
check 1 "期待一覧のみにあるcontext(rulesetから消えた)は赤にする"
check_summary "一致しません" "集合不一致の見出しが出る"
check_summary "期待一覧のみに存在: gitleaks" "期待一覧側の差分が列挙される"

set_rules "$(rules_with backend-test codex-review dependency-gate gitleaks extra-check)"
check 1 "rulesetのみにあるcontext(期待一覧に未記載)は赤にする"
check_summary "rulesetのみに存在: extra-check" "ruleset側の差分が列挙される"

set_rules "$(rules_with backend-test codex-review dependency-gate extra-check)"
check 1 "双方向に差分があれば赤にする"
check_summary "期待一覧のみに存在: gitleaks" "期待一覧側の差分が列挙される"
check_summary "rulesetのみに存在: extra-check" "ruleset側の差分が列挙される"

reset_defaults

echo "--- 対象期間(3.5): 現在runの除外 ---"
# 前回run(2026-01-08)以降にマージされたPRのスキップが検知される。
# 現在のrun(id 9999, created_at=現在時刻)の除外を壊すと下限が現在時刻になり、
# このPRが対象期間から漏れて緑になる(=このテストがFAILする)。
set_pulls "[$(pull 201 '"2026-01-09T00:00:00Z"' sha201 mrg201)]"
set_checkruns sha201 "$(runs "$(crun 1 gitleaks completed '"skipped"' "2026-01-09T00:00:00Z"),$(crun 2 dependency-gate completed '"success"' "2026-01-09T00:00:00Z")")"
check 1 "前回run以降にマージされたPRのスキップを検知する(現在のGITHUB_RUN_IDを除外して下限を決める)"
check_summary "#201" "対象のPR番号が報告に出る"
check_summary "gitleaks" "スキップされたチェック名が報告に出る"
check_calls "actions/workflows/audit-weekly.yaml/runs" "自ワークフローの実行一覧へ問い合わせている"

set_pulls "[$(pull 201 '"2026-01-09T00:00:00Z"' sha201 mrg201),$(pull 200 '"2026-01-07T00:00:00Z"' sha200 mrg200)]"
set_checkruns sha201 "$(runs "$(crun 1 gitleaks completed '"success"' "2026-01-09T00:00:00Z"),$(crun 2 dependency-gate completed '"success"' "2026-01-09T00:00:00Z")")"
check 0 "前回runより前にマージされたPRは走査しない(境界前のPRの除外)"
check_no_calls "commits/sha200" "境界前のPRのcheck-runsは取得しない"

echo "--- 対象期間(3.5): 初回は7日窓 ---"
# 実行一覧に現在のrunしか無い場合と1件も無い場合は、直近7日間
# (2026-01-03T00:00:00Z以降)を対象とする。
SEVEN_DAY_PULLS="[$(pull 210 '"2026-01-04T00:00:00Z"' sha210 mrg210),$(pull 211 '"2026-01-02T00:00:00Z"' sha211 mrg211)]"
set_pulls "$SEVEN_DAY_PULLS"
set_checkruns sha210 "$(runs "$(crun 1 gitleaks completed '"skipped"' "2026-01-04T00:00:00Z"),$(crun 2 dependency-gate completed '"success"' "2026-01-04T00:00:00Z")")"

set_wfruns "$(wfruns "$(wfrun 9999 "2026-01-10T00:00:00Z")")"
check 1 "実行一覧が現在のrun自身のみなら直近7日間を対象とする(7日窓内のスキップを検知)"
check_summary "#210" "7日窓内のPR番号が報告に出る"
check_no_calls "commits/sha211" "7日窓より前のPRのcheck-runsは取得しない"

set_wfruns "$(wfruns "")"
check 1 "実行が1件も無ければ直近7日間を対象とする"
check_summary "#210" "7日窓内のPR番号が報告に出る"
check_no_calls "commits/sha211" "7日窓より前のPRのcheck-runsは取得しない"

reset_defaults

echo "--- スキップ検知(3.6): always+active ---"
set_pulls "[$(pull 301 '"2026-01-09T00:00:00Z"' sha301 mrg301)]"
set_checkruns sha301 "$(runs "$(crun 1 gitleaks completed '"skipped"' "2026-01-09T00:00:00Z"),$(crun 2 gitleaks completed '"skipped"' "2026-01-09T01:00:00Z"),$(crun 3 dependency-gate completed '"success"' "2026-01-09T00:00:00Z")")"
check 1 "always+activeのcontextが全check-runでskippedなら赤にする"
check_summary "#301: gitleaks" "PR番号とチェック名が報告に出る"

set_checkruns sha301 "$(runs "$(crun 1 gitleaks completed '"skipped"' "2026-01-09T00:00:00Z"),$(crun 2 gitleaks completed '"success"' "2026-01-09T01:00:00Z"),$(crun 3 dependency-gate completed '"success"' "2026-01-09T00:00:00Z")")"
check 0 "同一contextにskipped以外の結論が1件でもあれば実行済みとして緑にする(pull_request_review多重発火の偽赤防止)"

set_checkruns sha301 "$(runs "$(crun 1 dependency-gate completed '"success"' "2026-01-09T00:00:00Z")")"
check 1 "always+activeのcontextにcheck-runが1件も無ければ赤にする(実行なし=違反)"
check_summary "gitleaks" "実行されなかったチェック名が報告に出る"

echo "--- スキップ検知(3.7): paused ---"
set_checkruns sha301 "$(runs "$(crun 1 gitleaks completed '"success"' "2026-01-09T00:00:00Z"),$(crun 2 dependency-gate completed '"success"' "2026-01-09T00:00:00Z"),$(crun 3 codex-review completed '"skipped"' "2026-01-09T00:00:00Z")")"
check 0 "pausedと記録されたcontextのスキップは違反にしない"
check_summary "停止中" "停止中である旨が報告に明示される"
check_summary "#166" "停止の参照Issueが報告に出る"
check_summary "codex-review" "停止中のチェック名が報告に出る"

echo "--- スキップ検知(3.8): conditional ---"
set_checkruns sha301 "$(runs "$(crun 1 gitleaks completed '"success"' "2026-01-09T00:00:00Z"),$(crun 2 dependency-gate completed '"success"' "2026-01-09T00:00:00Z"),$(crun 3 backend-test completed '"skipped"' "2026-01-09T00:00:00Z")")"
check 0 "conditionalのcontextのスキップは違反にしない(変更検知による正当なスキップ)"

echo "--- 対象PRの絞り込み ---"
set_pulls "[$(pull 301 '"2026-01-09T00:00:00Z"' sha301 mrg301),$(pull 302 'null' sha302 mrg302)]"
set_checkruns sha301 "$(runs "$(crun 1 gitleaks completed '"success"' "2026-01-09T00:00:00Z"),$(crun 2 dependency-gate completed '"success"' "2026-01-09T00:00:00Z")")"
check 0 "merged_atがnullのPR(マージされずcloseされた)は対象外"
check_no_calls "commits/sha302" "マージされていないPRのcheck-runsは取得しない"

set_pulls "[$(pull 303 '"2026-01-09T00:00:00Z"' sha303h sha303m)]"
set_checkruns sha303h "$(runs "$(crun 1 gitleaks completed '"success"' "2026-01-09T00:00:00Z"),$(crun 2 dependency-gate completed '"success"' "2026-01-09T00:00:00Z")")"
check 0 "PRのheadコミット(head.sha)のcheck-runsで判定する"
check_calls "commits/sha303h/check-runs" "head.shaのcheck-runsを取得している"
check_no_calls "sha303m" "merge_commit_shaは使わない(squashマージでは全PRが偽赤になる)"

reset_defaults

echo "--- 期待一覧のスキーマ検証 ---"
set_checks '{"checks":[{"context":"gitleaks","mode":"always","state":"active"}]}'
check 2 "必須フィールド(approval_gated)の欠落は判定不能として2を返す"
check_summary "判定不能" "判定不能の見出しが出る"
check_no_calls "rules/branches" "スキーマ検証はAPIへの問い合わせより先に行われる"

set_checks '{"checks":[{"context":"gitleaks","mode":"always","state":"disabled","approval_gated":false}]}'
check 2 "未知のstateは判定不能として2を返す"

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

# 実物の期待一覧はrulesetの現行19コンテキストと一致する前提(design該当節)。
set_rules "$(rules_with frontend-test backend-test e2e-smoke escape-hatch size-check gitleaks codex-review dependency-gate pre-merge-check terraform-static dependency-graph-generate dependency-graph-submit dependency-review dependency-cooldown gradle-wrapper docker-smoke detect-changes detect-terraform-changes container-scan-script-tests)"
check 0 "実物の期待一覧(required-checks.json)はスキーマ検証と集合照合を通過する" "$REAL_CHECKS"

reset_defaults

echo "--- 判定不能(API失敗・想定外の応答) ---"
check 2 "ruleset APIへの問い合わせに失敗したら判定不能として2を返す(fail closed)" "$WORK/checks.json" "yes"
check_summary "判定不能" "判定不能の見出しが出る"
check_summary "re-run" "失敗したrunのre-runで再実行する指示が出る"
check_summary "新規の手動実行" "新規dispatchが検知の窓を狭めることの説明が出る"

set_rules '{"message":"Not Found"}'
check 2 "rulesetの応答が配列でなければ判定不能として2を返す"
check_summary "判定不能" "判定不能の見出しが出る"
reset_defaults

check 2 "実行一覧APIへの問い合わせに失敗したら判定不能として2を返す" "$WORK/checks.json" "" "yes"
check_summary "判定不能" "判定不能の見出しが出る"

set_wfruns '{"message":"Not Found"}'
check 2 "実行一覧の応答を解釈できなければ判定不能として2を返す"
check_summary "判定不能" "判定不能の見出しが出る"
reset_defaults

check 2 "PR一覧APIへの問い合わせに失敗したら判定不能として2を返す" "$WORK/checks.json" "" "" "yes"
check_summary "判定不能" "判定不能の見出しが出る"

set_pulls '{"message":"Not Found"}'
check 2 "PR一覧の応答が配列でなければ判定不能として2を返す"
check_summary "判定不能" "判定不能の見出しが出る"
reset_defaults

set_pulls "[$(pull 401 '"2026-01-09T00:00:00Z"' sha401 mrg401)]"
set_checkruns sha401 "$(runs "$(crun 1 gitleaks completed '"success"' "2026-01-09T00:00:00Z"),$(crun 2 dependency-gate completed '"success"' "2026-01-09T00:00:00Z")")"
check 2 "check-runs APIへの問い合わせに失敗したら判定不能として2を返す" "$WORK/checks.json" "" "" "" "yes"
check_summary "判定不能" "判定不能の見出しが出る"

set_checkruns sha401 '{"message":"Not Found"}'
check 2 "check-runsの応答を解釈できなければ判定不能として2を返す"
check_summary "判定不能" "判定不能の見出しが出る"

echo "--- 入力の欠落・不正 ---"
reset_defaults
check_invocation 2 "期待一覧の引数が無ければ判定不能として2を返す" ""
check_no_calls "repos/" "引数が無ければAPIへ問い合わせない"

check_invocation 2 "期待一覧の引数が空文字なら判定不能として2を返す" "" ""
check_no_calls "repos/" "引数が空文字ならAPIへ問い合わせない"

check_invocation 2 "GITHUB_REPOSITORY が無ければ判定不能として2を返す" GITHUB_REPOSITORY "$WORK/checks.json"
check_no_calls "repos/" "GITHUB_REPOSITORY が無ければAPIへ問い合わせない"

check_invocation 2 "GH_TOKEN が無ければ判定不能として2を返す" GH_TOKEN "$WORK/checks.json"
check_no_calls "repos/" "GH_TOKEN が無ければAPIへ問い合わせない"

check_invocation 2 "GITHUB_RUN_ID が無ければ判定不能として2を返す" GITHUB_RUN_ID "$WORK/checks.json"
check_no_calls "repos/" "GITHUB_RUN_ID が無ければAPIへ問い合わせない"

# NOW_EPOCH は7日窓の下限の算術展開に入る。英字は未定義変数、先頭0は8進数と
# して扱われ、変更前は終了コード1で止まっていた(010 のように別の値として
# 黙って通るものもある)。前回runの無い実行一覧にして、算術展開まで到達する
# 状態で確かめる。検査はAPIへの問い合わせより前に行うため、問い合わせが
# 無いことで入力検査が止めたこと(算術展開の失敗で止まったのではないこと)を
# 確かめる。
set_wfruns "$(wfruns "$(wfrun 9999 "2026-01-10T00:00:00Z")")"
INVOKE_NOW=abc check_invocation 2 "NOW_EPOCH が数値でなければ判定不能として2を返す" "" "$WORK/checks.json"
check_no_calls "repos/" "NOW_EPOCH が数値でなければAPIへ問い合わせない"

INVOKE_NOW=1e5 check_invocation 2 "NOW_EPOCH が指数表記なら判定不能として2を返す" "" "$WORK/checks.json"
check_no_calls "repos/" "NOW_EPOCH が指数表記ならAPIへ問い合わせない"

INVOKE_NOW=01768003200 check_invocation 2 "NOW_EPOCH が先頭0なら判定不能として2を返す" "" "$WORK/checks.json"
check_no_calls "repos/" "NOW_EPOCH が先頭0ならAPIへ問い合わせない"

INVOKE_NOW=123456789012345678901 check_invocation 2 "NOW_EPOCH の桁数が上限を超えれば判定不能として2を返す" "" \
    "$WORK/checks.json"
check_no_calls "repos/" "NOW_EPOCH の桁数が上限を超えればAPIへ問い合わせない"

check_invocation 0 "引数と環境変数がそろっていれば判定まで進む(入力検査の対照)" "" "$WORK/checks.json"
check_calls "repos/owner/repo/rules/branches/main" "入力がそろっていればrulesetへ問い合わせる"
check_summary "直近7日間" "NOW_EPOCH から7日窓の下限を求めている"
reset_defaults

echo "--- 想定外の失敗 ---"
set_pulls "[$(pull 501 '"2026-01-09T00:00:00Z"' sha501 mrg501)]"
set_checkruns sha501 "$(runs "$(crun 1 gitleaks completed '"skipped"' "2026-01-09T00:00:00Z"),$(crun 2 dependency-gate completed '"success"' "2026-01-09T00:00:00Z")")"
check 2 "ガードしていないコマンドが失敗したら逸脱ではなく判定不能として2を返す" \
    "$WORK/checks.json" "" "" "" "" "yes"
if grep -qF "スキップのままマージされたPRがあります" "$WORK/summary.md"; then
    echo "FAIL: 想定外の失敗を逸脱として報告しない (逸脱の見出しが出ている)"
    FAILED=1
else
    echo "PASS: 想定外の失敗を逸脱として報告しない"
fi
# 対照: 同じ入力で jq を失敗させなければ逸脱(1)になる。上の2が入力の違いで
# 出たのではなく、想定外の失敗によるものであることを確かめる。
check 1 "同じ入力で想定外の失敗が無ければ逸脱として1を返す(対照)"
check_summary "#501: gitleaks" "対照では違反のPR番号とチェック名が報告に出る"

# 関数の中で起きた失敗も2にする(set -E が無いと ERR トラップが関数へ
# 引き継がれず、errexit により終了コード1で止まる)。逸脱の無い入力で、
# 報告の書き込み(関数 emit_scope_and_paused_sections の中)だけを失敗させる。
reset_defaults
mkdir -p "$WORK/summary_dir"
RUN_SUMMARY="$WORK/summary_dir" check 2 "関数の中でガードしていないコマンドが失敗しても判定不能として2を返す"
# 対照: 書き込める報告先なら同じ入力で逸脱なし(0)になる。
check 0 "同じ入力で報告先に書き込めれば逸脱なしとして0を返す(対照)"

if [ "$FAILED" -eq 0 ]; then
    echo "すべてのテストがPASSしました。"
else
    echo "失敗したテストがあります。"
fi
exit "$FAILED"
