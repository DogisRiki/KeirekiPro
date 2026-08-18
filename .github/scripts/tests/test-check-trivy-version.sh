#!/usr/bin/env bash
# =====================================================================
# check-trivy-version.sh の自動テスト
#
# trivy をシムして終了コードと報告の内容を検証する。
#   0 = 一致 / 1 = 不一致または取得できない
#
# シムは PATH の先頭に置く。実物の trivy がランナーに入っていても
# そちらを呼ばないため、テストは Trivy の導入有無に依存しない。
#
# 終了コードだけでなく Summary の内容も見るのは、赤の理由を区別するため。
# jq が無い環境やシムが置けていない場合も exit 1 になるので、
# 終了コードだけでは「不一致を検知した」ことを確かめられない。
# =====================================================================
set -uo pipefail

SCRIPT="$(cd "$(dirname "$0")/.." && pwd)/check-trivy-version.sh"
# 一時領域の確保に失敗したまま進むと rm -rf が意図しない絶対パスを対象にするため、
# ディレクトリが実在することを確認してから trap を設定する
WORK=$(mktemp -d) || exit 1
[ -n "$WORK" ] && [ -d "$WORK" ] || exit 1
trap 'rm -rf "$WORK"' EXIT
FAILED=0

mkdir -p "$WORK/bin"
PATH="$WORK/bin:$PATH"
export PATH

# trivy のシムを差し替える。
# 使い方: shim_trivy <終了コード> <標準出力に出す内容>
shim_trivy() {
    local rc="$1" out="$2"
    cat >"$WORK/bin/trivy" <<SHIM
#!/usr/bin/env bash
cat <<'PAYLOAD'
${out}
PAYLOAD
exit ${rc}
SHIM
    chmod +x "$WORK/bin/trivy"
}

# 使い方: check <期待exit> <説明> <期待値>
# スクリプトは bash で起動する。リポジトリは core.fileMode=false で、
# .github/scripts は全件 100644(実行ビット無し)で記録されるため、
# 直接起動すると fresh clone で exit 126 になる。
check() {
    local want="$1" name="$2" expected="$3"
    local got
    GITHUB_STEP_SUMMARY=/dev/null bash "$SCRIPT" "$expected" >/dev/null 2>&1
    got=$?
    if [ "$got" -eq "$want" ]; then
        echo "ok   ${name}"
    else
        echo "FAIL ${name} (期待 exit=${want} / 実際 exit=${got})"
        FAILED=1
    fi
}

# 使い方: check_summary <期待文字列> <説明> <期待値>
check_summary() {
    local needle="$1" name="$2" expected="$3"
    local out="$WORK/summary.md"
    : >"$out"
    GITHUB_STEP_SUMMARY="$out" bash "$SCRIPT" "$expected" >/dev/null 2>&1
    if grep -qF "$needle" "$out"; then
        echo "ok   ${name}"
    else
        echo "FAIL ${name} (Summaryに '${needle}' が出ていない)"
        FAILED=1
    fi
}

# ---------------------------------------------------------------------
# 1. 指定と一致する
# ---------------------------------------------------------------------
shim_trivy 0 '{"Version":"0.74.0"}'
check 0 "一致すれば通す" "0.74.0"

# 先頭の v は落として突き合わせる。setup-trivy の version 入力には v 付きを
# 渡す一方、trivy --version の出力には v が付かないため。
check 0 "期待値に v が付いていても一致を判定できる" "v0.74.0"

# trivy 側が将来 v 付きで返すようになっても吸収する
shim_trivy 0 '{"Version":"v0.74.0"}'
check 0 "trivy の出力に v が付いていても一致を判定できる" "0.74.0"

# v だけを渡された場合は空の期待値になるため赤にする
shim_trivy 0 '{"Version":""}'
check 1 "期待値が v のみなら赤" "v"

# ---------------------------------------------------------------------
# 2. 部分一致では通さない
#    0.74.1 の指定で 0.74.10 が入っていたら赤にする。
#    前方一致で比較すると誤って通る組み合わせ。
# ---------------------------------------------------------------------
shim_trivy 0 '{"Version":"0.74.10"}'
check 1 "部分一致では通さない" "0.74.1"
check_summary "Trivy のバージョンが指定と一致しません" "不一致の理由がSummaryに出る" "0.74.1"
# バッククォートは Summary に出る Markdown の一部で、展開させたくない。
# shellcheck disable=SC2016
check_summary '| 実際 | `0.74.10` |' "実際の版がSummaryに出る" "0.74.1"

# ---------------------------------------------------------------------
# 3. DB のバージョンに誤爆しない
#    実物の出力にはトップレベルの .Version のほかに
#    .VulnerabilityDB.Version(=2)と .JavaDB.Version(=1)が含まれる。
#    再帰的に拾う実装だとこれらに引っかかる。
# ---------------------------------------------------------------------
shim_trivy 0 '{"Version":"0.74.0","VulnerabilityDB":{"Version":2,"UpdatedAt":"2026-08-18T00:00:00Z"},"JavaDB":{"Version":1}}'
check 0 "DBのバージョンが同居していても一致を判定できる" "0.74.0"

shim_trivy 0 '{"Version":"0.74.0","VulnerabilityDB":{"Version":2},"JavaDB":{"Version":1}}'
check 1 "DBのバージョンに一致しても通さない" "2"

# ---------------------------------------------------------------------
# 4. 取得できない場合は不一致と同じ扱いにする
# ---------------------------------------------------------------------
shim_trivy 1 ''
check 1 "trivy が失敗したら赤" "0.74.0"
check_summary "trivy のバージョンを取得できませんでした" "取得失敗の理由がSummaryに出る" "0.74.0"

shim_trivy 0 'not json'
check 1 "出力が JSON でなければ赤" "0.74.0"
check_summary "trivy のバージョン出力を解析できませんでした" "解析失敗の理由がSummaryに出る" "0.74.0"

shim_trivy 0 '{"VulnerabilityDB":{"Version":2}}'
check 1 "Version キーが無ければ赤" "0.74.0"

# ---------------------------------------------------------------------
if [ "$FAILED" -ne 0 ]; then
    echo "::error::check-trivy-version.sh のテストに失敗しました。"
    exit 1
fi
echo "全ケース成功。"
