#!/usr/bin/env bash
# =====================================================================
# check-audit-trivy-version.sh の自動テスト(audit-weekly CI から実行)
#
# 一時ディレクトリにワークフローの断片を書き、終了コードと報告の内容を検証する。
#   0 = 逸脱なし / 1 = 逸脱あり / 2 = 判定不能
#
# 外部への問い合わせを行わないため、実行にネットワークを必要としない。
# =====================================================================
set -uo pipefail

SCRIPTS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="${SCRIPTS_DIR}/check-audit-trivy-version.sh"
WORKFLOWS_DIR="$(cd "${SCRIPTS_DIR}/../workflows" && pwd)"
WORK=$(mktemp -d) || exit 1
[ -n "$WORK" ] && [ -d "$WORK" ] || exit 1
trap 'rm -rf "$WORK"' EXIT
FAILED=0

# 使い方: wf <ファイル名> <env 節に置く行(空なら TRIVY_VERSION を置かない)>
# 実物と同じく、先頭の env: に2字下げで置き、ステップからは env 経由で参照する
wf() {
    {
        echo "name: Sample"
        echo ""
        echo "env:"
        echo "  IMAGE_NAME: sample"
        if [ -n "$2" ]; then
            printf '%s\n' "$2"
        fi
        echo ""
        echo "jobs:"
        echo "  scan:"
        echo "    runs-on: ubuntu-latest"
        echo "    steps:"
        echo "      - uses: aquasecurity/setup-trivy@0000000000000000000000000000000000000000 # v0.0.0"
        echo "        with:"
        # shellcheck disable=SC2016 # 式をそのまま書き出す
        echo '          version: v${{ env.TRIVY_VERSION }}'
    } >"$WORK/$1"
}

# 使い方: check <期待exit> <説明> <引数...>
check() {
    local want="$1" name="$2" got
    shift 2
    : >"$WORK/summary.md"
    GITHUB_STEP_SUMMARY="$WORK/summary.md" bash "$SCRIPT" "$@" >/dev/null 2>&1
    got=$?
    if [ "$got" -eq "$want" ]; then
        echo "PASS: $name"
    else
        echo "FAIL: $name (expected exit $want, got $got)"
        FAILED=1
    fi
}

check_summary() {
    if grep -qF -- "$1" "$WORK/summary.md"; then
        echo "PASS: $2"
    else
        echo "FAIL: $2 (Summaryに '$1' が現れない)"
        FAILED=1
    fi
}

check_summary_empty() {
    if [ ! -s "$WORK/summary.md" ]; then
        echo "PASS: $1"
    else
        echo "FAIL: $1 (Summaryに報告が出ている)"
        FAILED=1
    fi
}

echo "--- 一致 ---"
wf a.yaml "  TRIVY_VERSION: '0.74.0'"
wf b.yaml "  TRIVY_VERSION: '0.74.0'"
check 0 "版が一致していれば逸脱なしとして0を返す" "$WORK/a.yaml" "$WORK/b.yaml"
check_summary_empty "一致していれば報告を出さない"

wf c.yaml "  TRIVY_VERSION: '0.74.0'"
check 0 "3本以上でもすべて一致していれば0を返す" "$WORK/a.yaml" "$WORK/b.yaml" "$WORK/c.yaml"

echo "--- 食い違い ---"
wf b.yaml "  TRIVY_VERSION: '0.75.0'"
check 1 "版が食い違えば逸脱ありとして1を返す" "$WORK/a.yaml" "$WORK/b.yaml"
check_summary "Trivy の版が食い違っています" "食い違いの見出しが出る"
check_summary "a.yaml\`: 0.74.0" "1本目の版が報告に出る"
check_summary "b.yaml\`: 0.75.0" "2本目の版が報告に出る"

wf b.yaml "  TRIVY_VERSION: '0.74.0'"
wf c.yaml "  TRIVY_VERSION: '0.73.2'"
check 1 "3本のうち1本だけ食い違っても1を返す" "$WORK/a.yaml" "$WORK/b.yaml" "$WORK/c.yaml"

echo "--- 判定不能 ---"
wf b.yaml ""
check 2 "TRIVY_VERSION の定義が無ければ判定不能として2を返す" "$WORK/a.yaml" "$WORK/b.yaml"
check_summary "判定不能" "判定不能の見出しが出る"
check_summary "0件" "定義の件数が報告に出る"

wf b.yaml "  TRIVY_VERSION: '0.74.0'
  TRIVY_VERSION: '0.75.0'"
check 2 "TRIVY_VERSION の定義が2件あれば判定不能として2を返す" "$WORK/a.yaml" "$WORK/b.yaml"
check_summary "2件" "定義の件数が報告に出る"

wf b.yaml "  TRIVY_VERSION: latest"
check 2 "版の形が不正(引用符なし・非数値)なら判定不能として2を返す" "$WORK/a.yaml" "$WORK/b.yaml"
check_summary "形を解釈できません" "形の不正が報告に出る"

wf b.yaml "  TRIVY_VERSION: '0.74'"
check 2 "版が3つの数字でなければ判定不能として2を返す" "$WORK/a.yaml" "$WORK/b.yaml"

wf b.yaml "  TRIVY_VERSION: \"0.74.0\""
check 2 "二重引用符の書き方に変わったら判定不能として2を返す" "$WORK/a.yaml" "$WORK/b.yaml"

wf b.yaml "  IMAGE_TAG: x"
printf '%s\n' "          TRIVY_VERSION: '0.74.0'" >>"$WORK/b.yaml"
check 2 "ステップ内の字下げの深い定義は数えない(env の定義が無い扱い)" "$WORK/a.yaml" "$WORK/b.yaml"

check 2 "ファイルが読めなければ判定不能として2を返す" "$WORK/a.yaml" "$WORK/missing.yaml"
check_summary "ファイルを読めません" "読めないファイルが報告に出る"

check 2 "引数が1個なら判定不能として2を返す" "$WORK/a.yaml"
check 2 "引数が無ければ判定不能として2を返す"

echo "--- 実物 ---"
# 実物の2本が今の書き方で解釈できることを確かめる。版の一致そのものは
# 本判定の役目のため、ここでは判定不能(2)にならないことだけを見る。
check_real() {
    : >"$WORK/summary.md"
    GITHUB_STEP_SUMMARY="$WORK/summary.md" bash "$SCRIPT" \
        "${WORKFLOWS_DIR}/container-scan.yaml" "${WORKFLOWS_DIR}/container-scan-scheduled.yaml" >/dev/null 2>&1
    local got=$?
    if [ "$got" -eq 0 ] || [ "$got" -eq 1 ]; then
        echo "PASS: 実物の2本は解釈できる(判定不能にならない)"
    else
        echo "FAIL: 実物の2本は解釈できる(判定不能にならない) (got $got)"
        FAILED=1
    fi
}
check_real

if [ "$FAILED" -eq 0 ]; then
    echo "すべてのテストがPASSしました。"
else
    echo "失敗したテストがあります。"
fi
exit "$FAILED"
