#!/usr/bin/env bash
# =====================================================================
# claude-auto-fix-run-claude.sh の自動テスト
#
# claude を、PATH の先頭に置いた偽の CLI に替える。偽の CLI は env -i で環境を消されて動くので、
# 動き方は、偽の CLI に書き込んだフォルダ CAP の中の mode のファイルで選び、
# 受け取った引数・環境・標準入力・作業のフォルダ・設定のファイルを CAP に写す。
# timeout も PATH の先頭の偽物に替え、渡された引数を残す。CAP に expire があれば、そこに書いた番号(空なら時間切れの 124)で終わる。
# 指示の文のファイルは、環境変数 CAF_PROMPT で、テストが作ったファイルを渡す。
#
# 場合の名前を KP_TEST_CASE に入れると、その場合だけを流す(例: KP_TEST_CASE=args)。
# 名前は args nokey auth limit execerr badjson timeout maxturns nochange secret ok quiet usage。
# =====================================================================
set -uo pipefail

HERE="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$HERE/claude-auto-fix-run-claude.sh"
WORK=$(mktemp -d) || exit 1
[ -n "$WORK" ] && [ -d "$WORK" ] || exit 1
trap 'rm -rf "$WORK"' EXIT
FAILED=0
CASE="${KP_TEST_CASE:-}"
RAN=0

ok() { echo "  ok: $1"; }
ng() { echo "  NG: $1" >&2; FAILED=1; }
expect_eq() { if [ "$2" = "$3" ]; then ok "$1"; else ng "$1(期待: [$3] 実際: [$2])"; fi; }
want() { if [ -z "$CASE" ] || [ "$CASE" = "$1" ]; then RAN=$((RAN + 1)); return 0; fi; return 1; }

BIN="$WORK/bin"
CAP="$WORK/cap"
mkdir -p "$BIN" "$CAP"
export CAP

# 実行のたびに変わらない、偽の鍵の値。差分に入ったら捨てることを確かめるのにも使う
KEY_VALUE="fake-oauth-value-7f3a9c"
SENTINEL="SENTINEL-conversation-4b1e"

# --- 偽の claude: CAP の場所を書き込んで作る(env -i で環境変数が消えるため)
cat >"$BIN/claude" <<EOF
#!/usr/bin/env bash
CAP="$CAP"
EOF
cat >>"$BIN/claude" <<'EOF'
: >"$CAP/called"
printf '%s\n' "$@" >"$CAP/args"
env | sort >"$CAP/env"
pwd >"$CAP/pwd"
cat >"$CAP/stdin"
prev=""
for a in "$@"; do
    [ "$prev" = --settings ] && cp "$a" "$CAP/settings.json"
    prev="$a"
done
ls -A "$HOME" >"$CAP/home-ls" 2>&1
ls -A "$CLAUDE_CONFIG_DIR" >"$CAP/config-ls" 2>&1
printf '%s\n%s\n' "$HOME" "$CLAUDE_CONFIG_DIR" >"$CAP/dirs"
echo "conversation $(cat "$CAP/sentinel" 2>/dev/null)" >&2
mode=$(cat "$CAP/mode")
s=$(cat "$CAP/sentinel" 2>/dev/null)
case "$mode" in
edit)
    echo "changed by claude $s" >>tracked.txt
    mkdir -p sub
    echo "new file" >sub/new.txt
    printf '{"type":"result","subtype":"success","is_error":false,"api_error_status":null,"result":"done %s","num_turns":3}\n' "$s"
    ;;
noedit)
    printf '{"type":"result","subtype":"success","is_error":false,"api_error_status":null,"result":"nothing %s","num_turns":1}\n' "$s"
    ;;
auth)
    echo "auth edit" >>tracked.txt
    printf '{"type":"result","subtype":"success","is_error":true,"api_error_status":null,"result":"Failed to authenticate. API Error: 401 OAuth access token is invalid.","num_turns":1}\n'
    exit 1
    ;;
auth401)
    printf '{"type":"result","subtype":"success","is_error":true,"api_error_status":401,"result":"other text","num_turns":1}\n'
    exit 1
    ;;
limit)
    echo "limit edit" >>tracked.txt
    printf '{"type":"result","subtype":"success","is_error":true,"api_error_status":null,"result":"You%sve hit your session limit","num_turns":1}\n' "'"
    exit 1
    ;;
limit429)
    printf '{"type":"result","subtype":"success","is_error":true,"api_error_status":429,"result":"slow down","num_turns":1}\n'
    exit 1
    ;;
iserror)
    echo "iserror edit" >>tracked.txt
    printf '{"type":"result","subtype":"success","is_error":true,"api_error_status":500,"result":"API Error: 500","num_turns":1}\n'
    exit 1
    ;;
maxturns)
    echo "maxturns edit" >>tracked.txt
    printf '{"type":"result","subtype":"error_max_turns","is_error":true,"api_error_status":null,"num_turns":60}\n'
    exit 1
    ;;
execerr)
    echo "execerr edit" >>tracked.txt
    printf '{"type":"result","subtype":"error_during_execution","is_error":true,"api_error_status":null,"num_turns":2}\n'
    exit 1
    ;;
othersub)
    printf '{"type":"result","subtype":"error_max_budget_usd","is_error":true,"api_error_status":null,"num_turns":2}\n'
    exit 1
    ;;
badjson)
    echo "badjson edit" >>tracked.txt
    printf 'not a json {\n'
    ;;
twojson)
    printf '{"type":"result","subtype":"success","is_error":false}\n{"type":"result","subtype":"success","is_error":false}\n'
    ;;
notresult)
    printf '{"type":"assistant","subtype":"success","is_error":false}\n'
    ;;
skant)
    echo "token sk-ant-oat01-abcdef" >>tracked.txt
    printf '{"type":"result","subtype":"success","is_error":false,"api_error_status":null,"result":"done","num_turns":2}\n'
    ;;
keyleak)
    echo "token $CLAUDE_CODE_OAUTH_TOKEN" >>tracked.txt
    printf '{"type":"result","subtype":"success","is_error":false,"api_error_status":null,"result":"done","num_turns":2}\n'
    ;;
esac
exit 0
EOF
# --- 偽の timeout: 引数を残す。CAP/expire があれば、コマンドを動かさずに時間切れの 124 で終わる
cat >"$BIN/timeout" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" >"$CAP/timeout-args"
if [ -f "$CAP/expire" ]; then
    code=$(cat "$CAP/expire")
    exit "${code:-124}"
fi
while [ $# -gt 0 ]; do
    case "$1" in
    -*) shift ;;
    *) shift; break ;;
    esac
done
exec "$@"
EOF
chmod +x "$BIN/claude" "$BIN/timeout"
export PATH="$BIN:$PATH"

PROMPT_FILE="$WORK/prompt.md"
printf '# 指示の文\n決まりを守ってください。\n' >"$PROMPT_FILE"
MAT="$WORK/materials.txt"
printf -- '----- claude-auto-fix 材料の始まり 0123 target -----\n種類: npm\n----- claude-auto-fix 材料の終わり 0123 target -----\n' >"$MAT"

# 1つの場合のための作業のフォルダ(Git のリポジトリ)と、RUNNER_TEMP と、偽の CLI の記録を作り直す
N=0
fresh() {
    N=$((N + 1))
    T="$WORK/target-$N"
    RT="$WORK/rt-$N"
    mkdir -p "$T" "$RT"
    git -C "$T" init -q
    git -C "$T" config user.email t@example.com
    git -C "$T" config user.name t
    echo "base" >"$T/tracked.txt"
    echo "keep" >"$T/other.txt"
    git -C "$T" add tracked.txt other.txt
    git -C "$T" commit -qm base
    # 起点のコードの差分は、index に入れた形で置く(Claude の変更だけが差分に出ることを確かめる)
    echo "base change" >>"$T/other.txt"
    git -C "$T" add other.txt
    find "$CAP" -mindepth 1 -delete
    echo "$1" >"$CAP/mode"
    echo "$SENTINEL" >"$CAP/sentinel"
    PATCH="$RT/claude.patch"
    OUT="$WORK/out-$N"
    ERR="$WORK/err-$N"
}
# run [鍵] … 鍵を省くと KEY_VALUE を使う。GitHub のトークンも環境に置いて、CLI に渡らないことを確かめる
run() {
    local key="${1-$KEY_VALUE}"
    (cd "$WORK" && env CLAUDE_CODE_OAUTH_TOKEN="$key" GITHUB_TOKEN=ghs_fake GH_TOKEN=gho_fake \
        BOT_GITHUB_TOKEN=bot_fake ACTIONS_RUNTIME_TOKEN=rt_fake RUNNER_TEMP="$RT" \
        CAF_PROMPT="$PROMPT_FILE" CAF_TARGET_DIR="$T" bash "$SCRIPT" "$MAT" "$PATCH" >"$OUT" 2>"$ERR")
    RC=$?
}
expect_result() {
    expect_eq "$1 の終わり方" "$RC" 0
    expect_eq "$1 の標準出力" "$(cat "$OUT")" "$(printf 'outcome=%s\nreason=%s' "$2" "$3")"
}
expect_no_patch() {
    if [ -e "$PATCH" ]; then ng "$1 で差分のファイルが残っています"; else ok "$1 で差分のファイルを書かない"; fi
}

if want args; then
    echo "args: CLI に渡す引数・環境・標準入力・設定のファイル"
    fresh noedit
    run
    expect_eq "CLI の引数" "$(sed '$d' "$CAP/args" | tr '\n' ' ')" \
        "-p --output-format json --tools Read,Edit,Write,Glob,Grep --strict-mcp-config --permission-mode acceptEdits --max-turns 60 --setting-sources user --settings "
    last=$(tail -n 1 "$CAP/args")
    case "$last" in
    "$RT"/*) ok "設定のファイルは RUNNER_TEMP の下にある" ;;
    *) ng "設定のファイルの場所が RUNNER_TEMP の下にありません: $last" ;;
    esac
    expect_eq "作業のフォルダで動かす" "$(cat "$CAP/pwd")" "$(cd "$T" && pwd)"
    expect_eq "標準入力は指示の文と材料をつないだ文だけ" "$(cmp -s "$CAP/stdin" <(cat "$PROMPT_FILE" "$MAT") && echo same)" same
    names=$(sed 's/=.*//' "$CAP/env" | grep -vxE 'PWD|SHLVL|_|OLDPWD' | tr '\n' ' ')
    expect_eq "CLI の環境の変数は4つだけ" "$names" "CLAUDE_CODE_OAUTH_TOKEN CLAUDE_CONFIG_DIR HOME PATH "
    if grep -qE '^(GITHUB_TOKEN|GH_TOKEN|BOT_GITHUB_TOKEN|ACTIONS_RUNTIME_TOKEN)=' "$CAP/env"; then
        ng "CLI の環境に GitHub のトークンがあります"
    else
        ok "CLI の環境に GitHub のトークンが無い"
    fi
    expect_eq "鍵の値は CLAUDE_CODE_OAUTH_TOKEN でだけ渡る" "$(grep -c 'fake' "$CAP/env")" 1
    expect_eq "鍵の値" "$(grep '^CLAUDE_CODE_OAUTH_TOKEN=' "$CAP/env")" "CLAUDE_CODE_OAUTH_TOKEN=$KEY_VALUE"
    path_line=$(grep '^PATH=' "$CAP/env")
    expect_eq "PATH の先頭は CLI の場所" "${path_line#PATH=}" "$BIN:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
    home=$(sed -n 1p "$CAP/dirs")
    conf=$(sed -n 2p "$CAP/dirs")
    case "$home" in "$RT"/*) ok "HOME は RUNNER_TEMP の下" ;; *) ng "HOME の場所: $home" ;; esac
    case "$conf" in "$RT"/*) ok "CLAUDE_CONFIG_DIR は RUNNER_TEMP の下" ;; *) ng "CLAUDE_CONFIG_DIR の場所: $conf" ;; esac
    if [ "$home" != "$conf" ]; then ok "HOME と CLAUDE_CONFIG_DIR は別のフォルダ"; else ng "HOME と CLAUDE_CONFIG_DIR が同じです"; fi
    expect_eq "HOME は空" "$(cat "$CAP/home-ls")" ""
    expect_eq "CLAUDE_CONFIG_DIR は空" "$(cat "$CAP/config-ls")" ""
    S="$CAP/settings.json"
    expect_eq "disableAllHooks" "$(jq -r '.disableAllHooks' "$S")" true
    expect_eq "blockReadsOutsideWorkingDirectories" "$(jq -r '.permissions.blockReadsOutsideWorkingDirectories' "$S")" true
    expect_eq "blockWritesOutsideWorkingDirectories" "$(jq -r '.permissions.blockWritesOutsideWorkingDirectories' "$S")" true
    rt_abs=$(cd "$RT" && pwd)
    expect_eq "deny の決まり" "$(jq -c '.permissions.deny' "$S")" \
        "[\"Bash\",\"WebFetch\",\"WebSearch\",\"Read(//proc/**)\",\"Read(//sys/**)\",\"Read(/${rt_abs}/**)\"]"
    expect_eq "時間切れは30分" "$(grep -c -x '30m' "$CAP/timeout-args")" 1
    left=$(find "$RT" -mindepth 1 -maxdepth 1 ! -name claude.patch)
    if [ -z "$left" ]; then ok "終わったあとに RUNNER_TEMP に一時のフォルダを残さない"; else ng "RUNNER_TEMP に残ったもの: $left"; fi
fi

if want nokey; then
    echo "nokey: 鍵が空なら Claude を呼ばずに key"
    fresh edit
    run ""
    expect_result "鍵が空" key key-missing
    if [ -e "$CAP/called" ]; then ng "鍵が空でも CLI が呼ばれました"; else ok "鍵が空なら CLI を呼ばない"; fi
    expect_no_patch "鍵が空"
fi

if want auth; then
    echo "auth: 認証の失敗は key"
    fresh auth
    run
    expect_result "Failed to authenticate で始まる結果" key auth-failed
    expect_no_patch "Failed to authenticate"
    fresh auth401
    run
    expect_result "api_error_status が 401" key auth-failed
fi

if want limit; then
    echo "limit: 使える量の上限は unavailable"
    fresh limit
    run
    expect_result "You've hit your で始まる結果" unavailable usage-limit
    expect_no_patch "You've hit your"
    fresh limit429
    run
    expect_result "api_error_status が 429" unavailable usage-limit
fi

if want execerr; then
    echo "execerr: 実行の失敗は unavailable"
    fresh execerr
    run
    expect_result "error_during_execution" unavailable execution-error
    expect_no_patch "error_during_execution"
    fresh othersub
    run
    expect_result "そのほかの subtype" unavailable execution-error
    fresh iserror
    run
    expect_result "success で is_error が true" unavailable execution-error
    expect_no_patch "success で is_error が true"
fi

if want badjson; then
    echo "badjson: 読めない結果は unavailable"
    fresh badjson
    run
    expect_result "読めない JSON" unavailable unreadable-result
    expect_no_patch "読めない JSON"
    fresh twojson
    run
    expect_result "JSON が2つ" unavailable unreadable-result
    fresh notresult
    run
    expect_result "type が result でない" unavailable unreadable-result
fi

if want timeout; then
    echo "timeout: 30分で打ち切ると unavailable"
    fresh edit
    : >"$CAP/expire"
    run
    expect_result "時間切れ" unavailable timeout
    expect_eq "timeout に30分を渡す" "$(grep -c -x '30m' "$CAP/timeout-args")" 1
    expect_no_patch "時間切れ"
    # TERM で止まらずに KILL で止めたときは、timeout は 137 で終わる
    fresh edit
    echo 137 >"$CAP/expire"
    run
    expect_result "KILL で止めた時間切れ" unavailable timeout
    expect_no_patch "KILL で止めた時間切れ"
fi

if want maxturns; then
    echo "maxturns: 往復の上限は unfixed"
    fresh maxturns
    run
    expect_result "error_max_turns" unfixed max-turns
    expect_no_patch "error_max_turns"
fi

if want nochange; then
    echo "nochange: 変更が空なら unfixed"
    fresh noedit
    run
    expect_result "変更が空" unfixed no-change
    expect_no_patch "変更が空"
fi

if want secret; then
    echo "secret: 差分に鍵の文字列があれば捨てて unfixed"
    fresh skant
    run
    expect_result "sk-ant- の文字列" unfixed secret-in-diff
    expect_no_patch "sk-ant- の文字列"
    fresh keyleak
    run
    expect_result "鍵の値" unfixed secret-in-diff
    expect_no_patch "鍵の値"
fi

if want ok; then
    echo "ok: 変更を差分に書き出す"
    fresh edit
    run
    expect_result "変更がある" ok changed
    if [ -s "$PATCH" ]; then ok "差分のファイルを書く"; else ng "差分のファイルがありません"; fi
    if grep -q '^+++ b/tracked.txt' "$PATCH" && grep -q '^+++ b/sub/new.txt' "$PATCH"; then
        ok "変えたファイルと新しく作ったファイルが差分に入る"
    else
        ng "差分に変えたファイルか新しいファイルがありません"
    fi
    if grep -q 'other.txt' "$PATCH"; then ng "起点のコードの差分が入っています"; else ok "起点のコードの差分は入らない"; fi
    # 起点のコードに当てられることを、別の写しで確かめる
    C="$WORK/clone-$N"
    git clone -q "$T" "$C"
    echo "base change" >>"$C/other.txt"
    if git -C "$C" apply --index --check "$PATCH"; then ok "差分は起点のコードに当たる"; else ng "差分が起点のコードに当たりません"; fi
fi

if want quiet; then
    echo "quiet: 会話の記録と結果の JSON の本文を出さない"
    for m in edit noedit auth execerr badjson; do
        fresh "$m"
        run
        if grep -qF "$SENTINEL" "$OUT" "$ERR"; then ng "$m で会話か結果の文が出ています"; else ok "$m で会話と結果の文を出さない"; fi
        if grep -qF "$KEY_VALUE" "$OUT" "$ERR"; then ng "$m で鍵の値が出ています"; else ok "$m で鍵の値を出さない"; fi
        expect_eq "$m の標準出力は2行" "$(grep -cE '^(outcome|reason)=' "$OUT")/$(wc -l <"$OUT" | tr -d ' ')" "2/2"
    done
fi

if want usage; then
    echo "usage: 引数と環境の誤り"
    fresh noedit
    (cd "$WORK" && env CLAUDE_CODE_OAUTH_TOKEN=x RUNNER_TEMP="$RT" CAF_PROMPT="$PROMPT_FILE" CAF_TARGET_DIR="$T" \
        bash "$SCRIPT" "$MAT" >/dev/null 2>&1)
    expect_eq "引数が1つ" "$?" 2
    (cd "$WORK" && env CLAUDE_CODE_OAUTH_TOKEN=x RUNNER_TEMP="$RT" CAF_PROMPT="$PROMPT_FILE" CAF_TARGET_DIR="$T" \
        bash "$SCRIPT" "$WORK/missing.txt" "$PATCH" >/dev/null 2>&1)
    expect_eq "材料のファイルが無い" "$?" 2
    (cd "$WORK" && env CLAUDE_CODE_OAUTH_TOKEN=x RUNNER_TEMP="$RT" CAF_PROMPT="$WORK/missing.md" CAF_TARGET_DIR="$T" \
        bash "$SCRIPT" "$MAT" "$PATCH" >/dev/null 2>&1)
    expect_eq "指示の文のファイルが無い" "$?" 2
    (cd "$WORK" && env -u RUNNER_TEMP CLAUDE_CODE_OAUTH_TOKEN=x CAF_PROMPT="$PROMPT_FILE" CAF_TARGET_DIR="$T" \
        bash "$SCRIPT" "$MAT" "$PATCH" >/dev/null 2>&1)
    expect_eq "RUNNER_TEMP が無い" "$?" 2
    (cd "$WORK" && env CLAUDE_CODE_OAUTH_TOKEN=x RUNNER_TEMP="$RT" CAF_PROMPT="$PROMPT_FILE" CAF_TARGET_DIR="$WORK/none" \
        bash "$SCRIPT" "$MAT" "$PATCH" >/dev/null 2>&1)
    expect_eq "作業のフォルダが無い" "$?" 2
    if [ -e "$CAP/called" ]; then ng "引数の誤りで CLI が呼ばれました"; else ok "引数の誤りでは CLI を呼ばない"; fi
fi

if [ "$RAN" -eq 0 ]; then
    echo "知らない場合の名前です: $CASE" >&2
    exit 1
fi
if [ "$FAILED" -ne 0 ]; then
    echo "失敗した確かめがあります" >&2
    exit 1
fi
echo "すべて通りました"
