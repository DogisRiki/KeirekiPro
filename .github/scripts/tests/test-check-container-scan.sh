#!/usr/bin/env bash
# =====================================================================
# check-container-scan.sh の自動テスト
#
# Trivy の出力を模した JSON を与え、終了コード・出力ファイル・
# Summary の内容を検証する。
#   0 = 止めるものが無い / 1 = 止めるものがある / 2 = 入力が不正
#
# 1 と 2 を区別するのが要点。週次の監視は 1 でIssueを操作し、
# 2 では一切操作せず失敗させる。2値に潰すと検査不能を検出0件と
# 取り違えてIssueを誤って閉じる。
# =====================================================================
set -uo pipefail

SCRIPT="$(cd "$(dirname "$0")/.." && pwd)/check-container-scan.sh"
WORK=$(mktemp -d) || exit 1
[ -n "$WORK" ] && [ -d "$WORK" ] || exit 1
trap 'rm -rf "$WORK"' EXIT
FAILED=0

SCAN="$WORK/scan.json"
SUP="$WORK/sup.json"
BLK="$WORK/blocking.json"
DET="$WORK/detected.json"
SUM="$WORK/summary.md"

# 使い方: scan_with <Results の中身>
scan_with() {
    cat >"$SCAN" <<JSON
{
  "SchemaVersion": 2,
  "ArtifactName": "image.tar",
  "Metadata": { "ImageConfig": { "architecture": "arm64", "os": "linux" } },
  "Results": $1
}
JSON
}

# 使い方: vuln <id> <severity> <pkg> <追加のJSON断片>
vuln() {
    printf '{"VulnerabilityID":"%s","Severity":"%s","PkgName":"%s","InstalledVersion":"1.0"%s}' \
        "$1" "$2" "$3" "$4"
}

reset_outputs() {
    rm -f "$BLK" "$DET"
    : >"$SUM"
    printf '{"suppressions": []}' >"$SUP"
}

# 使い方: run [apply-mode] [expected-arch]
run() {
    GITHUB_STEP_SUMMARY="$SUM" bash "$SCRIPT" \
        "$SCAN" "${2:-arm64}" "$SUP" "${1:-judge}" "$BLK" "$DET" >/dev/null 2>&1
}

# 使い方: check <期待exit> <説明> [apply-mode] [expected-arch]
check() {
    local want="$1" name="$2" got
    run "${3:-judge}" "${4:-arm64}"
    got=$?
    if [ "$got" -eq "$want" ]; then
        echo "ok   ${name}"
    else
        echo "FAIL ${name} (期待 exit=${want} / 実際 exit=${got})"
        FAILED=1
    fi
}

# 使い方: check_file <ファイル> <jq式> <説明>
check_file() {
    local f="$1" expr="$2" name="$3"
    if [ -f "$f" ] && jq -e "$expr" "$f" >/dev/null 2>&1; then
        echo "ok   ${name}"
    else
        echo "FAIL ${name}"
        FAILED=1
    fi
}

check_no_file() {
    if [ ! -f "$1" ]; then
        echo "ok   $2"
    else
        echo "FAIL $2 (ファイルが生成されている)"
        FAILED=1
    fi
}

check_summary() {
    if grep -qF "$1" "$SUM"; then
        echo "ok   $2"
    else
        echo "FAIL $2 (Summaryに '$1' が出ていない)"
        FAILED=1
    fi
}

# ---------------------------------------------------------------------
# 止める / 止めないの判定
# ---------------------------------------------------------------------
reset_outputs
scan_with "[{\"Target\":\"t\",\"Class\":\"os-pkgs\",\"Vulnerabilities\":[$(vuln CVE-1 CRITICAL pkgA ',"FixedVersion":"1.1"')]}]"
check 1 "修正版のある CRITICAL は止める"
check_summary "マージを止める" "止める判定がSummaryに出る"
# 表の列構成そのものを固定する。列がずれた表が出続けても
# 「マージを止める」の部分一致だけでは気づけない。
check_summary "| ID | 深刻度 | パッケージ | 修正版 | 抑制 | 判定 |" "表のヘッダが6列である"
check_summary "| CVE-1 | CRITICAL | pkgA 1.0 | 1.1 | なし | マージを止める |" "データ行が6セルで各値が入る"

reset_outputs
scan_with "[{\"Target\":\"t\",\"Vulnerabilities\":[$(vuln CVE-2 CRITICAL pkgB '')]}]"
check 0 "修正版が無ければ深刻度によらず止めない"
check_summary "CVE-2" "止めないものも全件に出る"

reset_outputs
scan_with "[{\"Target\":\"t\",\"Vulnerabilities\":[$(vuln CVE-3 MEDIUM pkgC ',"FixedVersion":"1.1"')]}]"
check 0 "MEDIUM は止めない"
check_summary "CVE-3" "MEDIUM も全件に出る"

reset_outputs
scan_with "[{\"Target\":\"t\",\"Vulnerabilities\":[$(vuln CVE-4 HIGH pkgD ',"FixedVersion":"1.1"')]}]"
check 1 "HIGH も止める"

reset_outputs
scan_with "[{\"Target\":\"t\",\"Vulnerabilities\":[$(vuln CVE-5 CRITICAL pkgE ',"FixedVersion":""')]}]"
check 0 "FixedVersion が空文字列なら止めない"

reset_outputs
scan_with "[{\"Target\":\"t\",\"Vulnerabilities\":[$(vuln CVE-6 CRITICAL pkgF ',"FixedVersion":"6.0.3.1, 5.2.4.3"')]}]"
check 1 "カンマ区切りの修正版でも止める"
check_file "$BLK" '.[0].fixedVersion == "6.0.3.1, 5.2.4.3"' "カンマ区切りをそのまま保持する"

# ---------------------------------------------------------------------
# 脆弱性0件の2つの形。どちらも正常。
# .Results も .Vulnerabilities も omitempty でキーごと欠落しうる。
# ---------------------------------------------------------------------
reset_outputs
cat >"$SCAN" <<'JSON'
{"SchemaVersion":2,"Metadata":{"ImageConfig":{"architecture":"arm64"}}}
JSON
check 0 "Results キーが不在でも正常に扱う"
check_file "$DET" 'length == 0' "検出0件が空配列で書き出される"

reset_outputs
scan_with '[{"Target":"t","Class":"os-pkgs","Type":"ubuntu"}]'
check 0 "Vulnerabilities キーが不在でも正常に扱う"
check_file "$DET" 'length == 0' "この形でも検出0件になる"

# ---------------------------------------------------------------------
# 前提の不一致と入力の不正はすべて exit 2
# ---------------------------------------------------------------------
reset_outputs
cat >"$SCAN" <<'JSON'
{"SchemaVersion":2,"Metadata":{"ImageConfig":{"architecture":"amd64"}},"Results":[]}
JSON
check 2 "アーキテクチャが期待と違えば入力不正"
check_summary "アーキテクチャが期待と一致しません" "不一致の理由がSummaryに出る"
check_no_file "$DET" "不一致のとき detected-out を生成しない"
check_no_file "$BLK" "不一致のとき blocking-out を生成しない"

reset_outputs
cat >"$SCAN" <<'JSON'
{"SchemaVersion":2,"Metadata":{"ImageConfig":{}},"Results":[]}
JSON
check 2 "アーキテクチャが不在なら入力不正"

reset_outputs
printf 'not json' >"$SCAN"
check 2 "スキャン結果が JSON でなければ入力不正"

reset_outputs
printf '{"Results":[]}' >"$SCAN"
check 2 "SchemaVersion が無ければ入力不正"

reset_outputs
scan_with '[]'
rm -f "$SCAN"
check 2 "スキャン結果が無ければ入力不正"

# ---------------------------------------------------------------------
# 出力ファイルの契約
# ---------------------------------------------------------------------
reset_outputs
scan_with "[{\"Target\":\"t\",\"Vulnerabilities\":[$(vuln CVE-7 CRITICAL pkgG ',"FixedVersion":"1.1"'),$(vuln CVE-8 LOW pkgH '')]}]"
check 1 "止めるものがあれば1を返す"
check_file "$DET" 'length == 2' "detected-out に全件が入る"
check_file "$DET" 'all(has("id") and has("severity") and has("pkgName") and has("installedVersion") and has("fixedVersion"))' "detected-out の各要素が5キーを持つ"
check_file "$DET" 'all(keys | length == 5)' "detected-out に余分なキーが入らない"
check_file "$BLK" 'length == 1 and .[0].id == "CVE-7"' "blocking-out には止めるものだけが入る"

reset_outputs
scan_with '[]'
check 0 "止めるものが無ければ0を返す"
check_file "$BLK" 'length == 0' "止めるものが無ければ blocking-out は空配列"

# ---------------------------------------------------------------------
# 抑制の記録が読めないまま通さない
# ---------------------------------------------------------------------
reset_outputs
scan_with '[]'
rm -f "$SUP"
check 2 "抑制の記録が無ければ入力不正"

reset_outputs
scan_with '[]'
printf 'not json' >"$SUP"
check 2 "抑制の記録が JSON でなければ入力不正"

reset_outputs
scan_with '[]'
printf '{"suppressions": "x"}' >"$SUP"
check 2 "suppressions が配列でなければ入力不正"

# ---------------------------------------------------------------------
# 契約外の終了コードを漏らさない
# ---------------------------------------------------------------------
reset_outputs
printf '{"SchemaVersion":2,"Metadata":"x","Results":[]}' >"$SCAN"
check 2 "Metadata が非オブジェクトでも入力不正"

reset_outputs
printf '{"SchemaVersion":2,"Metadata":{"ImageConfig":"x"},"Results":[]}' >"$SCAN"
check 2 "ImageConfig が非オブジェクトでも入力不正"

reset_outputs
printf '{"SchemaVersion":2,"Metadata":{"ImageConfig":{"architecture":"arm64"}},"Results":[1,2]}' >"$SCAN"
check 0 "Results の要素が非オブジェクトでも落ちない"

reset_outputs
printf '{"SchemaVersion":2,"Metadata":{"ImageConfig":{"architecture":"arm64"}},"Results":[{"Vulnerabilities":["x"]}]}' >"$SCAN"
check 0 "Vulnerabilities の要素が非オブジェクトでも落ちない"

# 引数不足は入力不正。${n:?} に任せると1になり、
# 週次が「止めるものがある」と解釈してIssue操作へ進む。
reset_outputs
scan_with '[]'
GITHUB_STEP_SUMMARY="$SUM" bash "$SCRIPT" >/dev/null 2>&1
if [ $? -eq 2 ]; then
    echo "ok   引数が無ければ入力不正"
else
    echo "FAIL 引数が無ければ入力不正"
    FAILED=1
fi

GITHUB_STEP_SUMMARY="$SUM" bash "$SCRIPT" "$SCAN" arm64 "$SUP" judge "$BLK" >/dev/null 2>&1
if [ $? -eq 2 ]; then
    echo "ok   引数が5個なら入力不正"
else
    echo "FAIL 引数が5個なら入力不正"
    FAILED=1
fi

# 出力先が書けない場合も入力不正
reset_outputs
scan_with '[]'
GITHUB_STEP_SUMMARY="$SUM" bash "$SCRIPT" "$SCAN" arm64 "$SUP" judge "$WORK/nodir/b.json" "$DET" >/dev/null 2>&1
if [ $? -eq 2 ]; then
    echo "ok   出力先が書けなければ入力不正"
else
    echo "FAIL 出力先が書けなければ入力不正"
    FAILED=1
fi

reset_outputs
scan_with '[]'
GITHUB_STEP_SUMMARY="$SUM" bash "$SCRIPT" "$SCAN" arm64 "$SUP" judge "" "$DET" >/dev/null 2>&1
if [ $? -eq 2 ]; then
    echo "ok   出力先が空文字列なら入力不正"
else
    echo "FAIL 出力先が空文字列なら入力不正"
    FAILED=1
fi

# ---------------------------------------------------------------------
# apply-mode
# ---------------------------------------------------------------------
reset_outputs
scan_with '[]'
check 0 "report モードでも動く" report
check 2 "未知の apply-mode は入力不正" bogus

# ---------------------------------------------------------------------
if [ "$FAILED" -ne 0 ]; then
    echo "::error::check-container-scan.sh のテストに失敗しました。"
    exit 1
fi
echo "全ケース成功。"
