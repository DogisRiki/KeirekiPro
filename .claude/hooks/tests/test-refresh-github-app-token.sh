#!/bin/bash
# =====================================================================
# refresh-github-app-token.sh(GitHub App のトークンを入れ替えるフック)のテスト
#
# 実行: bash .claude/hooks/tests/test-refresh-github-app-token.sh
# 一時的なディレクトリを CLAUDE_PROJECT_DIR にし、その下の .claude/scripts/github-app/refresh-token.sh に
# 偽物を置いてから、フックに Claude Code のフックの入力(JSON)を渡して、
# 標準出力と終了コードと、偽物が受け取った引数を確かめる。
# 本物の refresh-token.sh と gh の設定(GH_CONFIG_DIR)には触れない。
# 前提: bash・perl(JSON::PP)。ホストの Git Bash から流す。
# =====================================================================
set -u

HOOK="$(cd "$(dirname "$0")/.." && pwd)/refresh-github-app-token.sh"
TMP_ROOT=$(mktemp -d)
trap 'rm -rf "$TMP_ROOT"' EXIT

PROJECT="$TMP_ROOT/project"
FAKE_DIR="$PROJECT/.claude/scripts/github-app"
FAKE="$FAKE_DIR/refresh-token.sh"
CALLS="$TMP_ROOT/calls.txt"
mkdir -p "$FAKE_DIR"

# 偽の refresh-token.sh。呼ばれるたびに、引数の数と引数を CALLS に1行で書き足す。
# FAKE_MODE が fail なら、理由を標準エラーに出して終了コード1で終える
cat >"$FAKE" <<'EOF'
#!/bin/bash
printf '%s:%s\n' "$#" "$*" >>"$FAKE_CALLS"
printf '%s\n' "${GH_CONFIG_DIR-<unset>}" >"$FAKE_CALLS.env"
if [ "${FAKE_MODE:-ok}" = fail ]; then
    echo "refresh-token.sh: インストールトークンを発行できない: 偽物の失敗" >&2
    exit 1
fi
exit 0
EOF

pass=0
fail=0

die() {
    printf '%s\n' "$*"
    exit 1
}

run_test() { # <テスト名> <関数>
    local name="$1" fn="$2" out
    rm -f "$CALLS" "$CALLS.env"
    if out=$("$fn" 2>&1); then
        pass=$((pass + 1))
        printf 'ok: %s\n' "$name"
    else
        fail=$((fail + 1))
        printf 'FAIL: %s\n' "$name"
        printf '%s\n' "$out" | sed 's/^/    /'
    fi
}

# フックの入力の JSON を作る
payload() { # <hook_event_name>
    perl -MJSON::PP -e '
        my %d = (hook_event_name => $ARGV[0], session_id => "s1", cwd => "/tmp",
                 transcript_path => "/tmp/transcript.jsonl");
        $d{tool_name} = "Bash", $d{tool_input} = {command => "gh pr list"} if $ARGV[0] eq "PreToolUse";
        $d{prompt} = "hello" if $ARGV[0] eq "UserPromptSubmit";
        $d{source} = "startup" if $ARGV[0] eq "SessionStart";
        print JSON::PP->new->canonical->encode(\%d);
    ' -- "$1"
}

# フックを呼ぶ。標準出力を $OUT、標準エラーを $ERR、終了コードを $RC に入れる
call_hook() { # <偽物の動き ok|fail> <hook_event_name>
    call_hook_raw "$1" "$(payload "$2")"
}

call_hook_raw() { # <偽物の動き ok|fail> <標準入力にそのまま渡す文字列>
    # 呼ぶ側の GH_CONFIG_DIR を持ち込まない。HOOK_GH_CONFIG_DIR があれば、それを GH_CONFIG_DIR として渡す
    local -a envs=(env -u GH_CONFIG_DIR)
    if [ -n "${HOOK_GH_CONFIG_DIR:-}" ]; then
        envs+=("GH_CONFIG_DIR=$HOOK_GH_CONFIG_DIR")
    fi
    OUT=$(printf '%s' "$2" \
        | "${envs[@]}" CLAUDE_PROJECT_DIR="$PROJECT" FAKE_MODE="$1" FAKE_CALLS="$CALLS" bash "$HOOK" 2>"$TMP_ROOT/stderr.txt")
    RC=$?
    ERR=$(cat "$TMP_ROOT/stderr.txt")
}

expect_rc0() {
    [ "$RC" = 0 ] || die "終了コードが0でない: $RC(標準エラー: $ERR)"
}

expect_no_output() {
    [ -z "$OUT" ] || die "標準出力が空でない: $OUT"
}

# 偽物がちょうど1回、引数なし(--force なし)で呼ばれたこと
expect_called_once_without_args() {
    [ -f "$CALLS" ] || die "refresh-token.sh が呼ばれていない"
    [ "$(wc -l <"$CALLS" | tr -d ' ')" = 1 ] || die "refresh-token.sh が1回でなく呼ばれた: $(cat "$CALLS")"
    [ "$(cat "$CALLS")" = "0:" ] || die "refresh-token.sh に引数が渡された: $(cat "$CALLS")"
}

expect_not_called() {
    [ ! -f "$CALLS" ] || die "refresh-token.sh が呼ばれた: $(cat "$CALLS")"
}

expect_reason_in_output() {
    case "$OUT" in
        *'GitHub App のトークンを入れ替えられなかった'*'偽物の失敗'*) ;;
        *) die "標準出力に入れ替えられなかった理由が無い: $OUT" ;;
    esac
}

# --- 入れ替えが成功すれば終了コード0で終える
t_success_session_start() {
    call_hook ok SessionStart
    expect_rc0
    expect_no_output
    expect_called_once_without_args
}

t_success_user_prompt_submit() {
    call_hook ok UserPromptSubmit
    expect_rc0
    expect_no_output
    expect_called_once_without_args
}

t_success_pre_tool_use() {
    call_hook ok PreToolUse
    expect_rc0
    expect_no_output
    expect_called_once_without_args
}

# --- 入れ替えに失敗しても Claude の操作を止めない
t_fail_session_start() {
    call_hook fail SessionStart
    expect_rc0
    expect_reason_in_output
    expect_called_once_without_args
}

t_fail_user_prompt_submit() {
    call_hook fail UserPromptSubmit
    expect_rc0
    expect_reason_in_output
    expect_called_once_without_args
}

t_fail_pre_tool_use() {
    call_hook fail PreToolUse
    expect_rc0
    expect_no_output
    [ -z "$ERR" ] || die "PreToolUse で標準エラーに出した: $ERR"
    expect_called_once_without_args
}

# --- 3つのイベントのほかでは呼ばない
t_other_event() {
    call_hook ok Stop
    expect_rc0
    expect_no_output
    expect_not_called
}

t_not_json() {
    call_hook_raw ok 'not json'
    expect_rc0
    expect_no_output
    expect_not_called
}

# --- refresh-token.sh が無い作業フォルダ(古いブランチ)では何もしない
t_script_missing() {
    mv "$FAKE" "$FAKE.bak"
    call_hook ok SessionStart
    local rc="$RC" out="$OUT"
    mv "$FAKE.bak" "$FAKE"
    [ "$rc" = 0 ] || die "終了コードが0でない: $rc"
    [ -z "$out" ] || die "標準出力が空でない: $out"
    expect_not_called
}

# --- GH_CONFIG_DIR が環境に無ければ settings.local.json の env から読んで渡す
expect_seen_config_dir() { # <期待する値>
    [ "$(cat "$CALLS.env" 2>/dev/null)" = "$1" ] || die "refresh-token.sh が受け取った GH_CONFIG_DIR が違う: $(cat "$CALLS.env" 2>/dev/null)(期待: $1)"
}

t_config_dir_from_local_settings() {
    printf '%s' '{"env":{"GH_CONFIG_DIR":"C:\\Users\\someone\\.gh-bot"}}' >"$PROJECT/.claude/settings.local.json"
    call_hook ok SessionStart
    rm -f "$PROJECT/.claude/settings.local.json"
    expect_rc0
    expect_called_once_without_args
    expect_seen_config_dir 'C:\Users\someone\.gh-bot'
}

t_config_dir_env_wins() {
    printf '%s' '{"env":{"GH_CONFIG_DIR":"C:/from-settings"}}' >"$PROJECT/.claude/settings.local.json"
    HOOK_GH_CONFIG_DIR='C:/from-env' call_hook ok UserPromptSubmit
    rm -f "$PROJECT/.claude/settings.local.json"
    expect_rc0
    expect_seen_config_dir 'C:/from-env'
}

t_config_dir_absent() {
    call_hook ok PreToolUse
    expect_rc0
    expect_seen_config_dir '<unset>'
}

run_test "GH_CONFIG_DIR が環境に無ければ settings.local.json の env から読んで渡す" t_config_dir_from_local_settings
run_test "GH_CONFIG_DIR が環境にあれば、settings.local.json より環境を使う" t_config_dir_env_wins
run_test "GH_CONFIG_DIR が環境にも settings.local.json にも無ければ、無いまま呼ぶ" t_config_dir_absent
run_test "SessionStart: 入れ替えが成功すれば終了コード0で終え、何も出さない" t_success_session_start
run_test "UserPromptSubmit: 入れ替えが成功すれば終了コード0で終え、何も出さない" t_success_user_prompt_submit
run_test "PreToolUse: 入れ替えが成功すれば終了コード0で終え、何も出さない" t_success_pre_tool_use
run_test "SessionStart: 入れ替えに失敗したら理由を標準出力に出し、終了コード0で終える" t_fail_session_start
run_test "UserPromptSubmit: 入れ替えに失敗したら理由を標準出力に出し、終了コード0で終える" t_fail_user_prompt_submit
run_test "PreToolUse: 入れ替えに失敗しても何も出さず、終了コード0で終える" t_fail_pre_tool_use
run_test "3つのイベントのほかでは refresh-token.sh を呼ばない" t_other_event
run_test "入力が JSON でなければ refresh-token.sh を呼ばずに終了コード0で終える" t_not_json
run_test "refresh-token.sh が無ければ何も出さずに終了コード0で終える" t_script_missing

echo
echo "結果: ${pass} 件成功 / ${fail} 件失敗"
[ "$fail" -eq 0 ]
