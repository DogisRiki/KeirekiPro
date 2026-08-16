#!/usr/bin/env bash
# =====================================================================
# check-dependency-cooldown.sh の自動テスト(dependency-review CI から実行)
#
# gh と curl をスタブし、終了コードと報告の内容を検証する。
#   0 = 緑(通過) / 1 = 赤
#
# gh のスタブは、本体が渡す --jq のプログラムを実際の jq で評価する。
# 整形済みの結果を返すスタブにすると、対象の絞り込み(change_type と ecosystem)が
# 検証範囲から外れ、絞り込みを壊しても緑のままになる。
#
# 外部への問い合わせを行わないため、実行にネットワークを必要としない。
# 時刻は NOW_EPOCH で固定し、境界値を再現可能にする。
# =====================================================================
set -uo pipefail

SCRIPT="$(cd "$(dirname "$0")/.." && pwd)/check-dependency-cooldown.sh"
WORK=$(mktemp -d) || exit 1
[ -n "$WORK" ] && [ -d "$WORK" ] || exit 1
trap 'rm -rf "$WORK"' EXIT
FAILED=0

# 判定の基準時刻。2026-01-10T00:00:00Z
NOW=1768003200

mkdir -p "$WORK/bin"

# --- gh のスタブ ---------------------------------------------------------------
# --jq の後ろに渡されたプログラムを実 jq で $STUB_COMPARE に適用する。
# STUB_GH_FAIL が設定されているときは、標準出力を空にして異常終了する
# (比較APIの応答が得られない状況の再現)。
cat >"$WORK/bin/gh" <<'STUB'
#!/usr/bin/env bash
# --include のときはヘッダだけを返す。スナップショット警告の有無を再現する。
for a in "$@"; do
    if [ "$a" = "--include" ]; then
        if [ -n "${STUB_HDR_FAIL:-}" ]; then
            echo "stub: header fetch failure" >&2
            exit 1
        fi
        echo "HTTP/2.0 200 OK"
        echo "Content-Type: application/json; charset=utf-8"
        printf 'X-Github-Dependency-Graph-Snapshot-Warnings: %s\r\n' "${STUB_WARN_B64:-}"
        echo ""
        exit 0
    fi
done
if [ -n "${STUB_GH_FAIL:-}" ]; then
    echo "stub: compare API failure" >&2
    exit 1
fi
prog=""
want=0
for a in "$@"; do
    if [ "$want" = 1 ]; then
        prog="$a"
        want=0
    fi
    [ "$a" = "--jq" ] && want=1
done
jq -r "$prog" "${STUB_COMPARE:?}"
STUB

# --- curl のスタブ ---------------------------------------------------------------
# $STUB_TIMES の各行は "<pomパス>\t<Centralのコード>\t<Portalのコード>\t<Last-Modified>"。
# 該当行が無いパスは両方 404 を返す。呼ばれたURLは $STUB_CALLS に記録する。
cat >"$WORK/bin/curl" <<'STUB'
#!/usr/bin/env bash
url=""
for a in "$@"; do case "$a" in http*) url="$a" ;; esac; done
echo "$url" >>"${STUB_CALLS:?}"
code=404
lm=""
while IFS=$'\t' read -r p central portal l; do
    [ -n "$p" ] || continue
    case "$url" in
    *"$p")
        case "$url" in
        "${MAVEN_CENTRAL_BASE}"/*) code="$central" ;;
        "${PLUGIN_PORTAL_BASE}"/*) code="$portal" ;;
        esac
        lm="$l"
        ;;
    esac
done <"${STUB_TIMES:?}"
if [ "$code" = "000" ]; then exit 7; fi
if [ "$code" = "200" ]; then
    printf 'HTTP/2 200\r\nlast-modified: %s\r\n\r\n' "$lm"
fi
printf '\nHTTP_CODE:%s\n' "$code"
STUB

chmod +x "$WORK/bin/gh" "$WORK/bin/curl"

# 使い方: run <compare.jsonの内容> <times.tsvの内容> [gh失敗] [警告base64] [ヘッダ取得失敗]
run() {
    printf '%s' "$1" >"$WORK/compare.json"
    printf '%s' "$2" >"$WORK/times.tsv"
    : >"$WORK/calls.log"
    : >"$WORK/summary.md"
    PATH="$WORK/bin:$PATH" \
        STUB_COMPARE="$WORK/compare.json" STUB_TIMES="$WORK/times.tsv" \
        STUB_CALLS="$WORK/calls.log" STUB_GH_FAIL="${3:-}" STUB_WARN_B64="${4:-}" \
        STUB_HDR_FAIL="${5:-}" \
        GITHUB_REPOSITORY="owner/repo" GH_TOKEN="dummy" NOW_EPOCH="$NOW" \
        MAVEN_CENTRAL_BASE="https://central.invalid/maven2" \
        PLUGIN_PORTAL_BASE="https://portal.invalid/m2" \
        GITHUB_STEP_SUMMARY="$WORK/summary.md" \
        bash "$SCRIPT" base head >/dev/null 2>&1
}

# 使い方: check <期待exit> <説明> <compare.json> <times.tsv> [gh失敗] [警告base64] [ヘッダ取得失敗]
check() {
    local want="$1" name="$2" got
    run "$3" "$4" "${5:-}" "${6:-}" "${7:-}"
    got=$?
    if [ "$got" -eq "$want" ]; then
        echo "PASS: $name"
    else
        echo "FAIL: $name (expected exit $want, got $got)"
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

check_no_call_to() {
    if grep -qF "$1" "$WORK/calls.log"; then
        echo "FAIL: $2 ('$1' への問い合わせが発生した)"
        FAILED=1
    else
        echo "PASS: $2"
    fi
}

check_no_calls() {
    if [ ! -s "$WORK/calls.log" ]; then
        echo "PASS: $1"
    else
        echo "FAIL: $1 (外部への問い合わせが発生した)"
        FAILED=1
    fi
}

# --- 比較APIの応答(canned) ------------------------------------------------------
entry() {
    printf '{"change_type":"%s","ecosystem":"%s","name":"%s","version":"%s","manifest":"backend/settings.gradle"}' \
        "$1" "$2" "$3" "$4"
}

# 2026-01-10T00:00:00Z ちょうど72時間前
LM_EXACTLY_72="Wed, 07 Jan 2026 00:00:00 GMT"
# 71時間59分前
LM_JUST_UNDER_72="Wed, 07 Jan 2026 00:01:00 GMT"
# 十分に古い
LM_OLD="Mon, 01 Dec 2025 00:00:00 GMT"
# 48時間前
LM_48="Thu, 08 Jan 2026 00:00:00 GMT"

echo "--- スナップショットが揃っていない場合 ---"
# 実際のAPIが返した警告文をbase64にしたもの
WARN_B64="VGhlIG51bWJlciBvZiBzbmFwc2hvdHMgY29tcGFyZWQgZm9yIHRoZSBiYXNlIFNIQSAoMSkgYW5kIHRoZSBoZWFkIFNIQSAoMCkgZG8gbm90IG1hdGNoLg=="
check 1 "スナップショット数が一致しなければ赤にする" "[]" "" "" "$WARN_B64"
check_summary "スナップショットが揃っていません" "取り込み不足の見出しが出る"
check_summary "do not match" "APIの警告文がそのまま出る"
check_summary "少し置いてから" "再実行で解消しうる旨が出る"
check_no_calls "判定不能なら配布元へ問い合わせない"

check 0 "警告ヘッダが空なら通常どおり判定する" "[]" "" "" ""

check 1 "ヘッダの取得に失敗したら赤にする(fail closed)" "[]" "" "" "" "yes"
check_summary "スナップショットの状況を確認できませんでした" "ヘッダ取得失敗が報告される"
check_summary "外部要因による失敗です" "外部要因である旨が出る"
check_no_calls "ヘッダ取得に失敗したら配布元へ問い合わせない"

echo "--- 比較APIの取得に失敗した場合 ---"
check 1 "比較APIが失敗したら赤にする(fail closed)" "[]" "" "yes"
check_summary "追加パッケージの一覧を取得できませんでした" "取得失敗が報告される"
check_summary "外部要因による失敗です" "外部要因である旨が出る"
check_summary "スナップショットが送信されていない" "未送信の可能性が示される"

echo "--- 追加が無い場合 ---"
check 0 "追加パッケージが0件なら成功する" "[]" ""
check_no_calls "追加が0件なら配布元へ問い合わせない"

echo "--- 対象の絞り込み ---"
check 0 "removed のエントリは対象にしない" \
    "[$(entry removed maven org.example:removed 9.9.9)]" ""
check_no_calls "removed だけなら配布元へ問い合わせない"

check 0 "maven 以外のエコシステムは対象にしない" \
    "[$(entry added github-actions actions/checkout v9.9.9),$(entry added npm left-pad 1.0.0)]" ""
check_no_calls "非maven だけなら配布元へ問い合わせない"

check 1 "混在していても added かつ maven のものだけを見る" \
    "[$(entry added github-actions actions/checkout v9.9.9),$(entry removed maven org.example:old 1.0.0),$(entry added maven org.example:lib 1.0.0)]" \
    "org/example/lib/1.0.0/lib-1.0.0.pom	200	404	$LM_JUST_UNDER_72
"
check_summary "org.example:lib:1.0.0" "対象の1件だけが報告される"

echo "--- 境界値 ---"
check 0 "公開から72時間ちょうどなら通す" \
    "[$(entry added maven org.example:lib 1.0.0)]" \
    "org/example/lib/1.0.0/lib-1.0.0.pom	200	404	$LM_EXACTLY_72
"
check 1 "公開から71時間59分なら落とす" \
    "[$(entry added maven org.example:lib 1.0.0)]" \
    "org/example/lib/1.0.0/lib-1.0.0.pom	200	404	$LM_JUST_UNDER_72
"
check_summary "公開から 72 時間を経過していないパッケージ" "クールダウンの見出しが出る"
check_summary "時間の経過によって解消します" "時間で解消する旨が出る"

echo "--- 判定不能 ---"
check 1 "公開時刻を取得できないものが1件でもあれば落とす" \
    "[$(entry added maven org.example:lib 1.0.0),$(entry added maven org.example:missing 2.0.0)]" \
    "org/example/lib/1.0.0/lib-1.0.0.pom	200	404	$LM_OLD
"
check_summary "判定不能" "判定不能の見出しが出る"
check_summary "時間の経過では解消しません" "時間で解消しない旨が出る"

echo "--- フォールバック ---"
check 0 "Centralが404ならPortalへフォールバックする" \
    "[$(entry added maven com.github.spotbugs.snom:spotbugs-gradle-plugin 6.5.10)]" \
    "com/github/spotbugs/snom/spotbugs-gradle-plugin/6.5.10/spotbugs-gradle-plugin-6.5.10.pom	404	200	$LM_OLD
"
check_calls "https://portal.invalid/m2" "Portal へ問い合わせている"

check 1 "Centralが404以外の失敗ならフォールバックせず判定不能にする" \
    "[$(entry added maven org.example:lib 1.0.0)]" \
    "org/example/lib/1.0.0/lib-1.0.0.pom	500	200	$LM_OLD
"
check_no_call_to "https://portal.invalid/m2" "404以外ではPortalへ問い合わせない"

check 1 "Centralへの問い合わせ自体が失敗したら判定不能にする" \
    "[$(entry added maven org.example:lib 1.0.0)]" \
    "org/example/lib/1.0.0/lib-1.0.0.pom	000	200	$LM_OLD
"

echo "--- 多数該当時の報告 ---"
check 1 "複数が該当したとき最も遅い待機明け時刻を出す" \
    "[$(entry added maven org.example:a 1.0.0),$(entry added maven org.example:b 1.0.0)]" \
    "org/example/a/1.0.0/a-1.0.0.pom	200	404	$LM_48
org/example/b/1.0.0/b-1.0.0.pom	200	404	$LM_JUST_UNDER_72
"
check_summary "待機が明ける時刻: 2026-01-11 00:00 UTC" "最も遅い時刻が明示される"

echo "--- 推移的依存を含む複数件 ---"
check 0 "すべて経過していれば件数に関わらず通す" \
    "[$(entry added maven org.example:a 1.0.0),$(entry added maven org.example:b 2.0.0),$(entry added maven org.example:c 3.0.0)]" \
    "org/example/a/1.0.0/a-1.0.0.pom	200	404	$LM_OLD
org/example/b/2.0.0/b-2.0.0.pom	200	404	$LM_OLD
org/example/c/3.0.0/c-3.0.0.pom	200	404	$LM_OLD
"

if [ "$FAILED" -eq 0 ]; then
    echo "すべてのテストがPASSしました。"
else
    echo "失敗したテストがあります。"
fi
exit "$FAILED"
