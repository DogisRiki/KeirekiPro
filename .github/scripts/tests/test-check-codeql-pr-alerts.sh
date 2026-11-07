#!/usr/bin/env bash
# =====================================================================
# check-codeql-pr-alerts.sh の自動テスト(codeql.yaml の codeql-complete から実行)
#
# gh をスタブにし、終了コードと標準出力を確かめる。
#   0 = マージを止める警告が0件 / 1 = 1件以上 / 2 = 判定不能
#
# gh のスタブは、本物の API の形の警告の一覧の JSON に、スクリプトが渡す --jq の式を
# 本物の jq で当てて返す。整形済みの値を返すスタブにすると、応答の読み方を壊しても
# 緑のままになるためである。--paginate のときに2ページに分けて返す場合も持つ。
# 所有者は、本物の .github/CODEOWNERS から読ませる(今は DogisRiki)。
#
# 外部への問い合わせを行わないため、実行にネットワークを必要としない。
# 実行には jq が要る(Linux のコンテナか CI で流す)。
# 環境変数 KP_TEST_CASE に場合の名前を入れると、その場合だけを流す。
# =====================================================================
set -uo pipefail

SCRIPT="$(cd "$(dirname "$0")/.." && pwd)/check-codeql-pr-alerts.sh"
WORK=$(mktemp -d) || exit 1
[ -n "$WORK" ] && [ -d "$WORK" ] || exit 1
trap 'rm -rf "$WORK"' EXIT
FAILED=0

mkdir -p "$WORK/bin"

# --- gh のスタブ ---------------------------------------------------------------
# 呼び出しの引数を $STUB_CALLS に1行ずつ記録する。
# URL の ref が refs/heads/main なら $STUB_DIR/main.json、refs/pull/<番号>/merge なら
# $STUB_DIR/pr.json に --jq の式を当てる。<名前>.page2.json があれば、2ページ目として
# 同じ式を別に当てて続けて出す(--paginate と --jq を併せたときの gh と同じく、
# 式はページごとに当たる)。
# STUB_FAIL に main か pr を入れると、その一覧の呼び出しだけ失敗させる。
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
*code-scanning/alerts*ref=refs/heads/main*) name=main ;;
*code-scanning/alerts*ref=refs/pull/*/merge*) name=pr ;;
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
PR=42

# 本物の API の形の警告を1件作る。
# 引数: 番号 state dismissed_by の login(空なら null) most_recent_instance.state 重さ(空なら項目なし)
alert() {
    local by="null" sev=""
    [ -n "$3" ] && by="{\"login\":\"$3\",\"type\":\"User\"}"
    [ -n "$5" ] && sev=",\"security_severity_level\":\"$5\""
    printf '{"number":%s,"state":"%s","dismissed_by":%s,"dismissed_reason":null,"rule":{"id":"java/secret-rule-%s","name":"secret-rule-name","description":"secret-description","severity":"error"%s},"tool":{"name":"CodeQL"},"most_recent_instance":{"ref":"refs/heads/x","state":"%s","location":{"path":"backend/src/SecretPath.java","start_line":77},"message":{"text":"secret-message"}}}' \
        "$1" "$2" "$by" "$1" "$sev" "$4"
}

reset_all() {
    rm -rf "$STUB_DIR"
    mkdir -p "$STUB_DIR"
    echo "[]" >"$STUB_DIR/main.json"
    echo "[]" >"$STUB_DIR/pr.json"
    : >"$STUB_CALLS"
    STUB_FAIL=""
    export STUB_FAIL
}

set_main() { printf '[%s]' "$1" >"$STUB_DIR/main.json"; }
set_pr() { printf '[%s]' "$1" >"$STUB_DIR/pr.json"; }
set_pr_page2() { printf '[%s]' "$1" >"$STUB_DIR/pr.page2.json"; }

run() {
    bash "$SCRIPT" "$PR" >"$WORK/out" 2>"$WORK/err"
    RC=$?
}

fail() {
    echo "FAIL: $1"
    FAILED=1
}

check() {
    run
    if [ "$RC" -eq "$1" ]; then
        echo "PASS: $2"
    else
        fail "$2 (終了コード: 期待 $1 / 実際 $RC)"
        sed 's/^/    stderr: /' "$WORK/err"
    fi
    check_only_number_and_severity "$2"
}

# どの場合でも、標準出力には「<番号> <重さ>」の行のほかを出さず、
# 標準出力と標準エラーに警告の場所と中身を出さない
check_only_number_and_severity() {
    if grep -qvE '^[0-9]+ (critical|high|medium)$' "$WORK/out"; then
        fail "$1: 標準出力に警告の番号と重さのほかの文字列が出た"
        sed 's/^/    stdout: /' "$WORK/out"
    fi
    if grep -q 'secret' "$WORK/out" "$WORK/err"; then
        fail "$1: 警告の場所か中身が出た"
    fi
}

check_out() {
    local actual
    actual=$(cat "$WORK/out")
    if [ "$actual" = "$1" ]; then
        echo "PASS: $2"
    else
        fail "$2"
        echo "    期待: $1"
        echo "    実際: $actual"
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

if want introduced; then
    set_pr "$(alert 3 open "" open critical),$(alert 1 open "" open high),$(alert 2 open "" open medium)"
    check 1 "PR が持ち込んだ critical と high と medium の開いた警告で終了コード1になり、番号と重さだけを出す: 終了コード1で終わる"
    check_out "1 high
2 medium
3 critical" "PR が持ち込んだ critical と high と medium の開いた警告で終了コード1になり、番号と重さだけを出す: 3件の番号と重さを番号の順に出す"
fi

if want main-existing; then
    set_main "$(alert 5 open "" open high)"
    set_pr "$(alert 5 open "" open high)"
    check 0 "main の一覧で fixed でない警告と同じ番号の警告では終了コード0になる"

    set_main "$(alert 5 open "" fixed high)"
    check 1 "main の一覧で fixed の警告と同じ番号の警告は、PR が持ち込んだ警告として終了コード1になる"
    check_out "5 high" "main で fixed の警告は、PR が持ち込んだ警告として番号と重さを出す"
fi

if want low-only; then
    set_pr "$(alert 7 open "" open low),$(alert 8 open "" open "")"
    check 0 "low と重さの無い警告だけでは終了コード0になる"
fi

if want owner-dismissed; then
    set_pr "$(alert 9 dismissed DogisRiki open high)"
    check 0 "所有者が却下した警告は、most_recent_instance.state が open のままでも数えない"
fi

if want other-dismissed; then
    set_pr "$(alert 11 dismissed DogisRiki-bot dismissed high),$(alert 12 dismissed "github-actions[bot]" dismissed medium),$(alert 13 dismissed "" dismissed critical)"
    check 1 "Claude のアカウントと github-actions[bot] と却下した人の無い却下を数える: 終了コード1で終わる"
    check_out "11 high
12 medium
13 critical" "Claude のアカウントと github-actions[bot] と却下した人の無い却下を数える: 3件の番号と重さを出す"
fi

if want api-failure; then
    set_pr "$(alert 1 open "" open high)"
    STUB_FAIL="pr"
    check 2 "API が失敗すると終了コード2で終わる: PR の一覧"
    STUB_FAIL="main"
    check 2 "API が失敗すると終了コード2で終わる: main の一覧"
    STUB_FAIL=""
fi

if want paginate; then
    set_pr "$(alert 1 open "" open low)"
    set_pr_page2 "$(alert 21 open "" open high)"
    check 1 "2ページにまたがる警告を数え漏らさない: 2ページ目の警告で終了コード1になる"
    check_out "21 high" "2ページにまたがる警告を数え漏らさない: 2ページ目の警告の番号と重さを出す"
    # スタブは --paginate の有無によらず2ページを返すため、全部のページを読む指定は呼び出しの記録で確かめる
    check_calls "--paginate repos/owner/repo/code-scanning/alerts?tool_name=CodeQL&per_page=100&ref=refs/pull/42/merge" "2ページにまたがる警告を数え漏らさない: PR の一覧を CodeQL の警告に絞って、全部のページを読む"
    check_calls "--paginate repos/owner/repo/code-scanning/alerts?tool_name=CodeQL&per_page=100&ref=refs/heads/main" "2ページにまたがる警告を数え漏らさない: main の一覧を CodeQL の警告に絞って、全部のページを読む"
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
