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
OUT="$WORK/output.txt"

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

# 使い方: sup_with <suppressions 配列のJSON>
# reset_outputs のあとに呼ぶ。空の記録を上書きする。
sup_with() {
    printf '{"suppressions": %s}' "$1" >"$SUP"
}

# 使い方: run [apply-mode] [expected-arch]
run() {
    GITHUB_STEP_SUMMARY="$SUM" bash "$SCRIPT" \
        "$SCAN" "${2:-arm64}" "$SUP" "${1:-judge}" "$BLK" "$DET" >"$OUT" 2>&1
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

# 使い方: check_output <期待する文字列> <説明>
# 注釈の種別(::error:: か ::warning:: か)まで含めて突き合わせる。
# 終了コードだけでは judge と report の書き分けが崩れても気づけない。
check_output() {
    if grep -qF "$1" "$OUT"; then
        echo "ok   $2"
    else
        echo "FAIL $2 (出力に '$1' が無い)"
        FAILED=1
    fi
}

# 使い方: check_no_output <出てはいけない文字列> <説明>
check_no_output() {
    if grep -qF "$1" "$OUT"; then
        echo "FAIL $2 (出力に '$1' が出ている)"
        FAILED=1
    else
        echo "ok   $2"
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
# 赤の原因を実行結果から特定できること(要件 3.2)。件数まで固定する。
check_output "::error::修正版のある CRITICAL / HIGH の脆弱性が 1 件あります。"     "judge では ::error:: で件数を出す"
check_no_output "::warning::修正版のある" "judge では ::warning:: に落とさない"
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
# 抑制の適用
#
# 有効期限内は 2099-12-31、期限切れは 2000-01-01 を使う。実行日を挟んで
# 動かない値にすることで、テストが日付演算を持たなくて済む。境界(実行日
# と同じ日)だけは本体と同じ式で求める。
# ---------------------------------------------------------------------
TODAY=$(date -u +%Y-%m-%d)

reset_outputs
sup_with '[{"id":"CVE-10","reason":"上流に修正版が無い","expires":"2099-12-31"}]'
scan_with "[{\"Target\":\"t\",\"Vulnerabilities\":[$(vuln CVE-10 CRITICAL pkgJ ',"FixedVersion":"1.1"')]}]"
check 0 "judge では有効期限内の抑制で止めない"
check_summary "| CVE-10 | CRITICAL | pkgJ 1.0 | 1.1 | 有効期限内(2099-12-31 まで) | 止めない |" \
    "抑制列が有効期限内、判定列が止めない"
check_file "$BLK" 'length == 0' "抑制した件は blocking-out に入らない"
check_file "$DET" 'length == 1' "抑制しても detected-out には残る"

reset_outputs
sup_with '[{"id":"CVE-11","reason":"期限が切れている","expires":"2000-01-01"}]'
scan_with "[{\"Target\":\"t\",\"Vulnerabilities\":[$(vuln CVE-11 CRITICAL pkgK ',"FixedVersion":"1.1"')]}]"
check 1 "期限切れの抑制は止める側に戻る"
check_summary "| CVE-11 | CRITICAL | pkgK 1.0 | 1.1 | 期限切れ(2000-01-01) | マージを止める |" \
    "抑制列が期限切れ、判定列がマージを止める"
check_file "$BLK" 'length == 1 and .[0].id == "CVE-11"' "期限切れは blocking-out に入る"

reset_outputs
sup_with "[{\"id\":\"CVE-12\",\"reason\":\"当日は有効\",\"expires\":\"${TODAY}\"}]"
scan_with "[{\"Target\":\"t\",\"Vulnerabilities\":[$(vuln CVE-12 CRITICAL pkgL ',"FixedVersion":"1.1"')]}]"
check 0 "expires が実行日と同じなら有効"
check_summary "有効期限内(${TODAY} まで)" "当日の抑制も有効期限内と表示される"

reset_outputs
sup_with '[{"id":"CVE-13","reason":"別のIDの抑制","expires":"2099-12-31"}]'
scan_with "[{\"Target\":\"t\",\"Vulnerabilities\":[$(vuln CVE-14 CRITICAL pkgM ',"FixedVersion":"1.1"')]}]"
check 1 "IDが一致しない抑制は効かない"
check_summary "| CVE-14 | CRITICAL | pkgM 1.0 | 1.1 | なし | マージを止める |" "一致しなければ抑制列はなし"

# ---------------------------------------------------------------------
# report モードは抑制を判定に用いない(要件 4.4)。ただし表には出す(要件 3.1)。
# ---------------------------------------------------------------------
reset_outputs
sup_with '[{"id":"CVE-10","reason":"上流に修正版が無い","expires":"2099-12-31"}]'
scan_with "[{\"Target\":\"t\",\"Vulnerabilities\":[$(vuln CVE-10 CRITICAL pkgJ ',"FixedVersion":"1.1"')]}]"
check 1 "report では有効期限内の抑制でも止める" report
# 週次は終了コード1でもジョブを成功で終える。成功した run に ::error:: が並ぶと
# 結論と注釈が食い違って読めるため、report では注釈を ::warning:: に落とす。
check_output "::warning::修正版のある CRITICAL / HIGH の脆弱性が 1 件あります。"     "report では ::warning:: で件数を出す"
check_no_output "::error::修正版のある" "report では ::error:: を出さない"
check_summary "| CVE-10 | CRITICAL | pkgJ 1.0 | 1.1 | 有効期限内(2099-12-31 まで) | マージを止める |" \
    "report でも抑制列は有効期限内のまま"
check_file "$BLK" 'length == 1 and .[0].id == "CVE-10"' "report では抑制した件も blocking-out に入る"

# report は抑制の記録が読めなくても止まらない。週次で止めると、再検査が
# 完走しているのに起票が行われない状態が生じる。
reset_outputs
printf 'not json' >"$SUP"
scan_with "[{\"Target\":\"t\",\"Vulnerabilities\":[$(vuln CVE-15 CRITICAL pkgN ',"FixedVersion":"1.1"')]}]"
check 1 "report では抑制の記録が不正でも続行する" report
check_output "::warning::抑制の記録が不正です" "report は ::warning:: を残して続ける"
check_summary "| CVE-15 | CRITICAL | pkgN 1.0 | 1.1 | 取得できず | マージを止める |" \
    "読めないときは抑制列が取得できず"

reset_outputs
rm -f "$SUP"
scan_with "[{\"Target\":\"t\",\"Vulnerabilities\":[$(vuln CVE-16 CRITICAL pkgO ',"FixedVersion":"1.1"')]}]"
check 1 "report では抑制の記録が無くても続行する" report
check_summary "取得できず" "記録が無いときも抑制列が取得できず"

reset_outputs
sup_with '[{"id":"CVE-17","reason":"","expires":"2099-12-31"}]'
scan_with "[{\"Target\":\"t\",\"Vulnerabilities\":[$(vuln CVE-17 CRITICAL pkgP ',"FixedVersion":"1.1"')]}]"
check 1 "report では記録の不備でも続行する" report
check_summary "取得できず" "不備のあるときも抑制列が取得できず"

# ---------------------------------------------------------------------
# 抑制の記録の検証。judge ではいずれも入力不正(要件 4.1)。
# ---------------------------------------------------------------------
reset_outputs
scan_with '[]'
sup_with '[{"reason":"idが無い","expires":"2099-12-31"}]'
check 2 "id が無ければ入力不正"
check_output "::error::抑制の記録が不正です: 1 件目: id が無い、または空です"     "judge は ::error:: で位置と理由を名指しする"
check_no_file "$DET" "記録の不備のとき detected-out を生成しない"
check_no_file "$BLK" "記録の不備のとき blocking-out を生成しない"

reset_outputs
scan_with '[]'
sup_with '[{"id":"","reason":"idが空","expires":"2099-12-31"}]'
check 2 "id が空文字列なら入力不正"

reset_outputs
scan_with '[]'
sup_with '[{"id":"CVE-18","expires":"2099-12-31"}]'
check 2 "reason が無ければ入力不正"

reset_outputs
scan_with '[]'
sup_with '[{"id":"CVE-18","reason":"","expires":"2099-12-31"}]'
check 2 "reason が空文字列なら入力不正"

reset_outputs
scan_with '[]'
sup_with '[{"id":"CVE-18","reason":"期限が無い"}]'
check 2 "expires が無ければ入力不正"

reset_outputs
scan_with '[]'
sup_with '[{"id":"CVE-18","reason":"重複","expires":"2099-12-31"},{"id":"CVE-18","reason":"重複","expires":"2099-01-01"}]'
check 2 "id が重複すれば入力不正"

reset_outputs
scan_with '[]'
sup_with '[{"id":"CVE-18","reason":"要素が文字列","expires":"2099-12-31"},"x"]'
check 2 "要素がオブジェクトでなければ入力不正"
check_output "::error::抑制の記録が不正です: 2 件目: オブジェクトではありません"     "オブジェクトでない要素をその位置で名指しする"

# ---------------------------------------------------------------------
# 日付の妥当性。形式だけの検査では 2026-13-45 を通してしまう。
# ---------------------------------------------------------------------
reset_outputs
scan_with '[]'
sup_with '[{"id":"CVE-19","reason":"存在しない日付","expires":"2026-13-45"}]'
check 2 "存在しない日付なら入力不正"

reset_outputs
scan_with '[]'
sup_with '[{"id":"CVE-19","reason":"2月30日","expires":"2026-02-30"}]'
check 2 "その月に無い日なら入力不正"

reset_outputs
scan_with '[]'
sup_with '[{"id":"CVE-19","reason":"0月","expires":"2026-00-15"}]'
check 2 "月が 00 なら入力不正"

reset_outputs
scan_with '[]'
sup_with '[{"id":"CVE-19","reason":"13月","expires":"2026-13-01"}]'
check 2 "月が 13 なら入力不正"

reset_outputs
scan_with '[]'
sup_with '[{"id":"CVE-19","reason":"平年の2月29日","expires":"2100-02-29"}]'
check 2 "100年で割り切れる年は閏年でない"

reset_outputs
scan_with '[]'
sup_with '[{"id":"CVE-19","reason":"閏年の2月29日","expires":"2400-02-29"}]'
check 0 "400年で割り切れる年は閏年"

reset_outputs
scan_with '[]'
sup_with '[{"id":"CVE-19","reason":"区切りが違う","expires":"2099/12/31"}]'
check 2 "区切りが違えば入力不正"

reset_outputs
scan_with '[]'
sup_with '[{"id":"CVE-19","reason":"桁が足りない","expires":"2099-1-1"}]'
check 2 "桁が揃っていなければ入力不正"

reset_outputs
scan_with '[]'
sup_with '[{"id":"CVE-19","reason":"日付でない","expires":20991231}]'
check 2 "expires が文字列でなければ入力不正"

# 修正版が無い、あるいは深刻度が低い件に抑制が付いていても、
# 判定は変わらず表にも状態が出る。
reset_outputs
sup_with '[{"id":"CVE-20","reason":"修正版が無い件への抑制","expires":"2099-12-31"}]'
scan_with "[{\"Target\":\"t\",\"Vulnerabilities\":[$(vuln CVE-20 CRITICAL pkgQ '')]}]"
check 0 "修正版が無ければ抑制の有無によらず止めない"
check_summary "| CVE-20 | CRITICAL | pkgQ 1.0 | なし | 有効期限内(2099-12-31 まで) | 止めない |" \
    "抑制の状態は判定に関わらず表に出る"

# ---------------------------------------------------------------------
# 入力不正のときは注釈の文言まで固定する。終了コードだけでは、
# 理由が入れ替わっても気づけない。
# ---------------------------------------------------------------------
reset_outputs
scan_with '[]'
rm -f "$SUP"
check 2 "抑制の記録が無ければ入力不正(再掲・文言つき)"
check_output "::error::抑制の記録が不正です: 抑制の記録がありません" "記録の不在を名指しする"

reset_outputs
scan_with '[]'
sup_with '[{"id":"CVE-21","reason":"重複","expires":"2099-12-31"},{"id":"CVE-21","reason":"重複","expires":"2099-01-01"}]'
check 2 "id の重複(文言つき)"
check_output "::error::抑制の記録が不正です: id が重複しています: CVE-21" "重複した id を名指しする"

reset_outputs
scan_with '[]'
sup_with '[{"id":"CVE-21","reason":"日付が不正","expires":"2026-13-45"}]'
check 2 "日付が不正(文言つき)"
check_output "expires が YYYY-MM-DD の実在する日付ではありません: 2026-13-45" "不正な日付をそのまま示す"

reset_outputs
cat >"$SCAN" <<'JSON'
{"SchemaVersion":2,"Metadata":{"ImageConfig":{"architecture":"amd64"}},"Results":[]}
JSON
check 2 "アーキテクチャ不一致(文言つき)"
check_output "::error::検査対象のアーキテクチャが期待と一致しません。期待=arm64 実際=amd64" \
    "期待と実際の両方を出す"

# ---------------------------------------------------------------------
# 終了コード2のときは、どの経路でも出力ファイルを作らない。
# 検証を通す前に書き出す実装に変わると、週次が古い結果でIssueを操作する。
# ---------------------------------------------------------------------
for bad in \
    '{"Results":[]}' \
    'not json' \
    '{"SchemaVersion":2,"Metadata":{"ImageConfig":{}},"Results":[]}' \
    '{"SchemaVersion":2,"Metadata":{"ImageConfig":{"architecture":"arm64"}},"Results":"str"}'; do
    reset_outputs
    printf '%s' "$bad" >"$SCAN"
    check 2 "入力不正: ${bad}"
    check_no_file "$DET" "この経路で detected-out を作らない"
    check_no_file "$BLK" "この経路で blocking-out を作らない"
done

reset_outputs
scan_with '[]'
check 2 "未知の apply-mode でも出力ファイルを作らない" bogus
check_no_file "$DET" "apply-mode 不正で detected-out を作らない"
check_no_file "$BLK" "apply-mode 不正で blocking-out を作らない"

# .Results が配列でない場合を検出0件の緑にしない。
# .Results[]? は器の型が崩れていても黙って空を返す。
reset_outputs
printf '{"SchemaVersion":2,"Metadata":{"ImageConfig":{"architecture":"arm64"}},"Results":"str"}' >"$SCAN"
check 2 "Results が配列でなければ入力不正"
check_output "::error::スキャン結果の Results が配列ではありません" "器の型崩れを名指しする"

# ---------------------------------------------------------------------
# Summary が書けない場合。設定されていて書けないと、表の追記で
# リダイレクトが失敗し、判定に関わらず終了コード1が漏れる。
# ---------------------------------------------------------------------
reset_outputs
scan_with '[]'
GITHUB_STEP_SUMMARY="$WORK/nodir/summary.md" bash "$SCRIPT" \
    "$SCAN" arm64 "$SUP" judge "$BLK" "$DET" >/dev/null 2>&1
if [ $? -eq 2 ]; then
    echo "ok   Summary が書けなければ入力不正"
else
    echo "FAIL Summary が書けなければ入力不正"
    FAILED=1
fi

# ---------------------------------------------------------------------
# 終了コード0で検出がある状態(抑制で止めなかった場合)の出力の契約。
# 5キーの検証を exit 1 の経路だけに置くと、exit 0 側の書き出しが
# 崩れても気づけない。
# ---------------------------------------------------------------------
reset_outputs
sup_with '[{"id":"CVE-22","reason":"上流に修正版が無い","expires":"2099-12-31"}]'
scan_with "[{\"Target\":\"t\",\"Vulnerabilities\":[$(vuln CVE-22 CRITICAL pkgR ',"FixedVersion":"1.1"')]}]"
check 0 "抑制により終了コード0になる"
check_file "$DET" 'length == 1 and all(keys | length == 5)' "終了コード0でも detected-out は5キー"
check_file "$DET" 'all(has("id") and has("severity") and has("pkgName") and has("installedVersion") and has("fixedVersion"))' \
    "終了コード0でもキー名が契約どおり"
check_file "$BLK" 'length == 0' "抑制した件は blocking-out に残らない"

# ---------------------------------------------------------------------
# expires の末尾の改行。jq の正規表現は $ が末尾の改行の手前にも
# マッチするため、形式検証だけでは通ってしまう。
# ---------------------------------------------------------------------
reset_outputs
sup_with '[{"id":"CVE-23","reason":"末尾に改行","expires":"2099-12-31\n"}]'
scan_with "[{\"Target\":\"t\",\"Vulnerabilities\":[$(vuln CVE-23 CRITICAL pkgS ',"FixedVersion":"1.1"')]}]"
check 2 "expires の末尾に改行があれば入力不正"

reset_outputs
scan_with '[]'
sup_with '[{"id":"CVE-23","reason":"前後に空白","expires":" 2099-12-31"}]'
check 2 "expires の前に空白があれば入力不正"
# ---------------------------------------------------------------------
if [ "$FAILED" -ne 0 ]; then
    echo "::error::check-container-scan.sh のテストに失敗しました。"
    exit 1
fi
echo "全ケース成功。"
