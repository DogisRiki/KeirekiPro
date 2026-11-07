#!/usr/bin/env bash
# =====================================================================
# check-audit-codeql-alerts.sh の自動テスト(audit-weekly CI の自己テストから実行)
#
# gh をスタブにし、終了コードと、GITHUB_STEP_SUMMARY に書いた報告を確かめる。
#   0 = 逸脱なし / 1 = 逸脱あり / 2 = 判定不能
#
# gh のスタブは、本物の API の形の警告の一覧の JSON に、スクリプトが渡す --jq の式を
# 本物の jq で当てて返す。整形済みの値を返すスタブにすると、応答の読み方を壊しても
# 緑のままになるためである。--paginate のときに2ページに分けて返す場合も持つ。
# 所有者は、本物の .github/CODEOWNERS から読ませる(今は DogisRiki)。
# 判定の時刻は NOW_EPOCH で固定する。
#
# 外部への問い合わせを行わないため、実行にネットワークを必要としない。
# 実行には jq が要る(Linux のコンテナか CI で流す)。
# 環境変数 KP_TEST_CASE に場合の名前を入れると、その場合だけを流す。
# =====================================================================
set -uo pipefail

SCRIPT="$(cd "$(dirname "$0")/.." && pwd)/check-audit-codeql-alerts.sh"
WORK=$(mktemp -d) || exit 1
[ -n "$WORK" ] && [ -d "$WORK" ] || exit 1
trap 'rm -rf "$WORK"' EXIT
FAILED=0

mkdir -p "$WORK/bin"

# --- gh のスタブ ---------------------------------------------------------------
# 呼び出しの引数を $STUB_CALLS に1行ずつ記録する。
# URL の state が open なら $STUB_DIR/open.json、dismissed なら $STUB_DIR/dismissed.json に
# --jq の式を当てる。<名前>.page2.json があれば、2ページ目として同じ式を別に当てて
# 続けて出す(--paginate と --jq を併せたときの gh と同じく、式はページごとに当たる)。
# STUB_FAIL に open か dismissed を入れると、その一覧の呼び出しだけ失敗させる。
cat >"$WORK/bin/gh" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"${STUB_CALLS:?}"
url=""
prog=""
want=0
for a in "$@"; do
    if [ "$want" = 1 ]; then
        prog="$a"
        want=0
        continue
    fi
    case "$a" in
    --jq) want=1 ;;
    repos/*) url="$a" ;;
    esac
done
case "$url" in
*code-scanning/alerts*state=open*) name=open ;;
*code-scanning/alerts*state=dismissed*) name=dismissed ;;
*)
    echo "stub: unexpected call: $*" >&2
    exit 1
    ;;
esac
if [ "${STUB_FAIL:-}" = "$name" ]; then
    echo "gh: Server Error (HTTP 500)" >&2
    exit 1
fi
jq -r "$prog" "${STUB_DIR:?}/${name}.json" || exit 1
if [ -f "${STUB_DIR}/${name}.page2.json" ]; then
    jq -r "$prog" "${STUB_DIR}/${name}.page2.json" || exit 1
fi
STUB
chmod +x "$WORK/bin/gh"

export PATH="$WORK/bin:$PATH"
export STUB_DIR="$WORK/stub"
export STUB_CALLS="$WORK/calls.txt"
export GITHUB_REPOSITORY="owner/repo"
export GH_TOKEN="dummy"
# 判定の時刻: 2026-11-08T00:00:00Z
export NOW_EPOCH=1794096000
LINK="https://github.com/owner/repo/security/code-scanning?query=is:open+tool:CodeQL+branch:main"

# 本物の API の形の警告を1件作る。
# 引数: 番号 state 重さ(空なら項目なし) created_at dismissed_by の login(空なら null)
# 場所と中身には、報告に出てはいけない目印(secret と 4242 行)を入れる
alert() {
    local by="null" sev=""
    [ -n "$5" ] && by="{\"login\":\"$5\",\"type\":\"User\"}"
    [ -n "$3" ] && sev=",\"security_severity_level\":\"$3\""
    printf '{"number":%s,"created_at":"%s","state":"%s","dismissed_by":%s,"dismissed_reason":null,"rule":{"id":"java/secret-query-id","name":"secret-rule-name","description":"secret-description","severity":"error"%s},"tool":{"name":"CodeQL"},"most_recent_instance":{"ref":"refs/heads/main","state":"%s","location":{"path":"backend/src/SecretPath.java","start_line":4242,"end_line":4242},"message":{"text":"secret-message"}}}' \
        "$1" "$4" "$2" "$by" "$sev" "$2"
}

reset_all() {
    rm -rf "$STUB_DIR"
    mkdir -p "$STUB_DIR"
    echo "[]" >"$STUB_DIR/open.json"
    echo "[]" >"$STUB_DIR/dismissed.json"
    : >"$STUB_CALLS"
    STUB_FAIL=""
    export STUB_FAIL
}

set_list() { printf '[%s]' "$2" >"$STUB_DIR/$1.json"; }
set_list_page2() { printf '[%s]' "$2" >"$STUB_DIR/$1.page2.json"; }

run() {
    : >"$WORK/summary"
    GITHUB_STEP_SUMMARY="$WORK/summary" bash "$SCRIPT" >"$WORK/out" 2>"$WORK/err"
    RC=$?
}

fail() {
    echo "FAIL: $1"
    FAILED=1
}

# どの場合でも、報告と標準出力と標準エラーに、警告の場所と中身を出さない
check_no_leak() {
    if grep -qiE 'secret|4242|java/' "$WORK/summary" "$WORK/out" "$WORK/err"; then
        fail "$1: 警告のファイルの名前か行かクエリの ID か規則の名前か説明が出た"
        grep -hiE 'secret|4242|java/' "$WORK/summary" "$WORK/out" "$WORK/err" | sed 's/^/    leak: /'
    fi
}

check() {
    run
    if [ "$RC" -eq "$1" ]; then
        echo "PASS: $2"
    else
        fail "$2 (終了コード: 期待 $1 / 実際 $RC)"
        sed 's/^/    stderr: /' "$WORK/err"
    fi
    check_no_leak "$2"
}

check_summary() {
    if grep -qxF -- "$1" "$WORK/summary"; then
        echo "PASS: $2"
    else
        fail "$2 (報告に「$1」の行がありません)"
        sed 's/^/    summary: /' "$WORK/summary"
    fi
}

check_summary_lacks() {
    if grep -qF -- "$1" "$WORK/summary"; then
        fail "$2 (報告に「$1」があります)"
    else
        echo "PASS: $2"
    fi
}

check_summary_empty() {
    if [ -s "$WORK/summary" ]; then
        fail "$1 (報告が空ではありません)"
        sed 's/^/    summary: /' "$WORK/summary"
    else
        echo "PASS: $1"
    fi
}

check_calls() {
    if grep -qF -- "$1" "$STUB_CALLS"; then
        echo "PASS: $2"
    else
        fail "$2 (「$1」を含む呼び出しがありません)"
        sed 's/^/    call: /' "$STUB_CALLS"
    fi
}

CASE="${KP_TEST_CASE:-}"
RAN=0
want() {
    if [ -z "$CASE" ] || [ "$CASE" = "$1" ]; then
        RAN=$((RAN + 1))
        echo "--- $1 ---"
        reset_all
        return 0
    fi
    return 1
}

T1="開いた警告を重さごとに数え、直近7日の数とリンクを書いて終了コード1で終わる"
if want open-counts; then
    # 直近7日: 2026-11-01T00:00:00Z ちょうど(7日前)と 2026-11-05 の2件。2026-10-31T23:59:59Z は数えない
    set_list open "$(alert 1 open critical 2026-11-05T10:00:00Z ""),$(alert 2 open high 2026-11-01T00:00:00Z ""),$(alert 3 open high 2026-10-31T23:59:59Z "")"
    # 2ページ目にも警告を置き、ページをまたいで数えることを確かめる
    set_list_page2 open "$(alert 4 open medium 2026-01-01T00:00:00Z ""),$(alert 5 open low 2026-01-01T00:00:00Z ""),$(alert 6 open "" 2026-01-01T00:00:00Z "")"
    check 1 "${T1}: 終了コード1で終わる"
    check_summary "開いたままの警告は 6 件です。重さごとの数は次のとおりです。" "${T1}: 2ページの警告を合わせた数を書く"
    check_summary "- critical: 1 件" "${T1}: critical の数を書く"
    check_summary "- high: 2 件" "${T1}: high の数を書く"
    check_summary "- medium: 1 件" "${T1}: medium の数を書く"
    check_summary "- low: 1 件" "${T1}: low の数を書く"
    check_summary "- 重さなし: 1 件" "${T1}: 重さの無い警告を重さなしの数として別に書く"
    check_summary "このうち、直近7日に見つかった警告は 2 件です。" "${T1}: 判定の時刻から7日以内に作られた警告を数える"
    check_summary "警告の場所と中身は、この報告に書きません。一覧の画面で確かめてください: ${LINK}" "${T1}: 一覧へのリンクを書く"
    check_calls "--paginate repos/owner/repo/code-scanning/alerts?ref=refs/heads/main&tool_name=CodeQL&per_page=100&state=open" "${T1}: main の開いた CodeQL の警告を、全部のページで読む"
    check_calls "--paginate repos/owner/repo/code-scanning/alerts?ref=refs/heads/main&tool_name=CodeQL&per_page=100&state=dismissed" "${T1}: main の却下した CodeQL の警告を、全部のページで読む"
fi

T2="開いた警告も所有者のほかの人の却下も無ければ終了コード0で終わる"
if want nothing; then
    set_list dismissed "$(alert 9 dismissed high 2026-01-01T00:00:00Z DogisRiki)"
    check 0 "${T2}: 終了コード0で終わる"
    check_summary_empty "${T2}: 報告を書かない"
fi

T3="所有者のほかの人の却下だけがあると、番号と却下した人の名前を書いて終了コード1で終わる"
if want others-dismissed; then
    set_list dismissed "$(alert 12 dismissed medium 2026-01-01T00:00:00Z "github-actions[bot]"),$(alert 11 dismissed high 2026-01-01T00:00:00Z DogisRiki-bot)"
    set_list_page2 dismissed "$(alert 13 dismissed critical 2026-01-01T00:00:00Z "")"
    check 1 "${T3}: 終了コード1で終わる"
    check_summary "- 警告の番号 11: 却下した人 \`DogisRiki-bot\`" "${T3}: Claude のアカウントの却下の番号と名前を書く"
    check_summary "- 警告の番号 12: 却下した人 \`github-actions[bot]\`" "${T3}: github-actions[bot] の却下の番号と名前を書く"
    check_summary "- 警告の番号 13: 却下した人の記録がありません" "${T3}: 却下した人の無い却下の番号を書く"
    check_summary_lacks "開いたままの警告は" "${T3}: 開いた警告の数を書かない"
fi

T4="所有者の却下は報告に書かない"
if want owner-dismissed; then
    set_list open "$(alert 1 open high 2026-01-01T00:00:00Z "")"
    set_list dismissed "$(alert 21 dismissed high 2026-01-01T00:00:00Z DogisRiki),$(alert 22 dismissed high 2026-01-01T00:00:00Z DogisRiki-bot)"
    check 1 "${T4}: 終了コード1で終わる"
    check_summary_lacks "警告の番号 21" "${T4}: 所有者が却下した警告の番号を書かない"
    check_summary "- 警告の番号 22: 却下した人 \`DogisRiki-bot\`" "${T4}: 所有者のほかの人の却下は書く"
fi

T5="偽の応答に入れたファイルの名前と行と規則の名前と説明が報告に出ない"
if want no-content; then
    set_list open "$(alert 1 open critical 2026-11-05T00:00:00Z "")"
    set_list dismissed "$(alert 2 dismissed high 2026-01-01T00:00:00Z DogisRiki-bot)"
    check 1 "${T5}: 終了コード1で終わる"
    check_summary "- critical: 1 件" "${T5}: 報告を書いたうえで確かめる"
fi

T6="API が失敗すると終了コード2で終わる"
if want api-failure; then
    set_list open "$(alert 1 open high 2026-01-01T00:00:00Z "")"
    STUB_FAIL=open
    check 2 "${T6}: 開いた警告の一覧"
    check_summary "### :warning: main の CodeQL の警告を数えられませんでした(判定不能)" "${T6}: 開いた警告の一覧: 判定不能を報告に書く"
    STUB_FAIL=dismissed
    check 2 "${T6}: 却下した警告の一覧"
    check_summary_lacks "開いたままの警告は" "${T6}: 却下した警告の一覧: 開いた警告の数を書かない"
    STUB_FAIL=""
fi

if [ "$RAN" -eq 0 ]; then
    echo "FAIL: KP_TEST_CASE=${CASE} に当たる場合がありません"
    FAILED=1
fi

if [ "$FAILED" -eq 0 ]; then
    echo "すべてのテストがPASSしました。"
else
    echo "失敗したテストがあります。"
fi
exit "$FAILED"
