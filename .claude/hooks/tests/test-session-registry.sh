#!/bin/bash
# =====================================================================
# session-registry.sh(セッションの記録を付けるフック)のテスト
#
# 実行: bash .claude/hooks/tests/test-session-registry.sh
# 一時的な git のリポジトリ(本体)と worktree を作り、フックに Claude Code のフックの入力(JSON)を渡して、
# 記録 sessions/<session_id>.json と標準出力と終了コードを確かめる。
# 本物のリポジトリの記録(.git/keirekipro-parallel)と git の設定には触れない。
# 前提: bash・perl(JSON::PP)・git。ホストの Git Bash から流す。
# =====================================================================
set -u
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR KP_SESSION_ID

HOOK="$(cd "$(dirname "$0")/.." && pwd)/session-registry.sh"
LIB="$(cd "$(dirname "$0")/../.." && pwd)/scripts/parallel/lib.sh"
TMP_ROOT=$(mktemp -d)
trap 'rm -rf "$TMP_ROOT"' EXIT
# git が返すパス(Windows では C:/...)と同じ形で比べられるようにする
WORK=$(cd "$TMP_ROOT" && { pwd -W 2>/dev/null || pwd; })

# --- 一時的なリポジトリ(本体と worktree)と、別のリポジトリ
MAIN_DIR="$WORK/RepoMain"
WT_DIR="$WORK/RepoWT"
OTHER_DIR="$WORK/RepoOther"
OUTSIDE_DIR="$WORK/outside"
GITC=(-c user.name=t -c user.email=t@example.com -c commit.gpgsign=false)
git init -q "$MAIN_DIR"
git -C "$MAIN_DIR" checkout -q -B main
mkdir -p "$MAIN_DIR/sub/dir"
echo seed >"$MAIN_DIR/sub/dir/seed.txt"
git -C "$MAIN_DIR" add -A
git -C "$MAIN_DIR" "${GITC[@]}" commit -q -m seed
git -C "$MAIN_DIR" worktree add -q "$WT_DIR" -b feat/wt
git init -q "$OTHER_DIR"
mkdir -p "$OUTSIDE_DIR"
MAIN=$(git -C "$MAIN_DIR" rev-parse --show-toplevel)
WT=$(git -C "$WT_DIR" rev-parse --show-toplevel)
STATE="$(git -C "$MAIN_DIR" rev-parse --path-format=absolute --git-common-dir)/keirekipro-parallel"
OTHER_STATE="$(git -C "$OTHER_DIR" rev-parse --path-format=absolute --git-common-dir)/keirekipro-parallel"
WT_GITDIR="$(git -C "$WT_DIR" rev-parse --path-format=absolute --git-dir)"

pass=0
fail=0

die() {
    printf '%s\n' "$*"
    exit 1
}

reset_state() {
    rm -rf "$STATE" "$OTHER_STATE" "$WT_GITDIR/keirekipro-parallel"
}

run_test() { # <テスト名> <関数>
    local name="$1" fn="$2" out
    reset_state
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
payload() { # <hook_event_name> <session_id> <cwd> [<追加のキー> <値>]...
    perl -MJSON::PP -e '
        my ($ev, $sid, $cwd, @rest) = @ARGV;
        my %d = (hook_event_name => $ev, session_id => $sid, cwd => $cwd,
                 transcript_path => "/tmp/transcript.jsonl");
        while (@rest) { my $k = shift @rest; $d{$k} = shift @rest; }
        print JSON::PP->new->canonical->encode(\%d);
    ' -- "$@"
}

# フックを呼ぶ。標準出力を $OUT、終了コードを $RC に入れる
call_hook() { # <hook_event_name> <session_id> <cwd> [<追加のキー> <値>]...
    OUT=$(payload "$@" | bash "$HOOK" 2>"$WORK/stderr.txt")
    RC=$?
}

call_hook_raw() { # <標準入力にそのまま渡す文字列>
    OUT=$(printf '%s' "$1" | bash "$HOOK" 2>"$WORK/stderr.txt")
    RC=$?
}

get() { # <ファイル> <キー>
    perl -MJSON::PP -e '
        open my $fh, "<:raw", $ARGV[0] or exit 1;
        local $/; my $d = JSON::PP->new->utf8->decode(<$fh>);
        my $v = $d->{$ARGV[1]};
        print defined $v ? $v : "";
    ' -- "$1" "$2"
}

# 作業フォルダの鍵を lib.sh で求める(フックと同じ求め方であることを確かめるため)
key_of() { # <作業フォルダ>
    # shellcheck source=.claude/scripts/parallel/lib.sh
    (cd "$1" && . "$LIB" && kp_folder_key)
}

# 記録の started_at と last_seen を古い時刻に書き換える
age_record() { # <ファイル> <時刻>
    perl -MJSON::PP -i -0777 -pe '
        my $d = JSON::PP->new->utf8->decode($_);
        $d->{started_at} = $d->{last_seen} = 0 + $ENV{AGE_TO};
        $_ = JSON::PP->new->utf8->canonical->encode($d) . "\n";
    ' "$1"
}

expect_rc0() {
    [ "$RC" = 0 ] || die "終了コードが0でない: $RC($(cat "$WORK/stderr.txt"))"
}

# ---------------------------------------------------------------------

t_session_start_creates_record() {
    local f="$STATE/sessions/s-1.json" now ctx ev
    now=$(date +%s)
    call_hook SessionStart s-1 "$MAIN" source startup
    expect_rc0
    [ -f "$f" ] || die "SessionStart で記録ができていない: $f"
    [ "$(get "$f" session_id)" = s-1 ] || die "session_id が違う: $(cat "$f")"
    [ "$(get "$f" folder)" = "$MAIN" ] || die "folder が本体フォルダでない: $(get "$f" folder)"
    [ "$(get "$f" folder_key)" = "$(key_of "$MAIN")" ] || die "folder_key が lib.sh の鍵と違う: $(cat "$f")"
    case "$(get "$f" started_at)" in '' | *[!0-9]*) die "started_at が UNIX 秒でない: $(cat "$f")" ;; esac
    case "$(get "$f" last_seen)" in '' | *[!0-9]*) die "last_seen が UNIX 秒でない: $(cat "$f")" ;; esac
    [ "$(get "$f" started_at)" -ge "$now" ] || die "started_at がいまの時刻でない: $(cat "$f")"
    [ "$(get "$f" last_seen)" = "$(get "$f" started_at)" ] || die "作ったときの last_seen が started_at と違う: $(cat "$f")"
    # 標準出力は SessionStart の hookSpecificOutput の JSON で、additionalContext にIDが出る
    ev=$(printf '%s' "$OUT" | perl -MJSON::PP -e 'local $/; my $d = JSON::PP->new->utf8->decode(<STDIN>); print $d->{hookSpecificOutput}{hookEventName}') \
        || die "標準出力が JSON でない: $OUT"
    [ "$ev" = SessionStart ] || die "hookEventName が SessionStart でない: $OUT"
    ctx=$(printf '%s' "$OUT" | perl -MJSON::PP -e 'local $/; my $d = JSON::PP->new->utf8->decode(<STDIN>); my $c = $d->{hookSpecificOutput}{additionalContext}; utf8::encode($c); print $c')
    case "$ctx" in
        *"このセッションのID: s-1"*) ;;
        *) die "additionalContext にIDが出ていない: $ctx" ;;
    esac
    case "$ctx" in
        *"--session"*) ;;
        *) die "additionalContext に --session で渡すことが出ていない: $ctx" ;;
    esac
}

t_session_start_existing_updates_last_seen() {
    local f="$STATE/sessions/s-1.json"
    call_hook SessionStart s-1 "$MAIN" source startup
    expect_rc0
    AGE_TO=100 age_record "$f"
    call_hook SessionStart s-1 "$MAIN" source compact
    expect_rc0
    [ "$(get "$f" started_at)" = 100 ] || die "すでにある記録の started_at が書き換わった: $(cat "$f")"
    [ "$(get "$f" last_seen)" -gt 100 ] || die "すでにある記録の last_seen が書き直されていない: $(cat "$f")"
    case "$OUT" in
        *"このセッションのID: s-1"*) ;;
        *) die "すでに記録があるときも additionalContext にIDを出す: $OUT" ;;
    esac
}

t_user_prompt_creates_record() {
    local f="$STATE/sessions/s-2.json"
    call_hook UserPromptSubmit s-2 "$MAIN" prompt hello
    expect_rc0
    [ -f "$f" ] || die "UserPromptSubmit で記録が無いときに作っていない"
    [ "$(get "$f" session_id)" = s-2 ] || die "session_id が違う: $(cat "$f")"
    [ "$(get "$f" folder)" = "$MAIN" ] || die "folder が違う: $(cat "$f")"
    [ "$(get "$f" folder_key)" = "$(key_of "$MAIN")" ] || die "folder_key が違う: $(cat "$f")"
    case "$(get "$f" started_at)" in '' | *[!0-9]*) die "started_at が UNIX 秒でない: $(cat "$f")" ;; esac
    # UserPromptSubmit の標準出力は Claude の文脈に足されるので、何も出さない
    [ -z "$OUT" ] || die "UserPromptSubmit で標準出力に何か出た: $OUT"
}

t_user_prompt_updates_last_seen() {
    local f="$STATE/sessions/s-2.json"
    call_hook SessionStart s-2 "$MAIN" source startup
    AGE_TO=200 age_record "$f"
    call_hook UserPromptSubmit s-2 "$MAIN" prompt hello
    expect_rc0
    [ "$(get "$f" started_at)" = 200 ] || die "UserPromptSubmit が started_at を書き換えた: $(cat "$f")"
    [ "$(get "$f" last_seen)" -gt 200 ] || die "UserPromptSubmit が last_seen を書き直していない: $(cat "$f")"
    [ -z "$OUT" ] || die "UserPromptSubmit で標準出力に何か出た: $OUT"
}

t_session_end_removes_record() {
    call_hook SessionStart s-3 "$MAIN" source startup
    call_hook SessionStart s-4 "$MAIN" source startup
    [ -f "$STATE/sessions/s-3.json" ] || die "前提の記録ができていない"
    call_hook SessionEnd s-3 "$MAIN" reason prompt_input_exit
    expect_rc0
    [ ! -f "$STATE/sessions/s-3.json" ] || die "SessionEnd で記録が消えていない"
    [ -f "$STATE/sessions/s-4.json" ] || die "SessionEnd がほかのセッションの記録まで消した"
    [ -z "$OUT" ] || die "SessionEnd で標準出力に何か出た: $OUT"
    # 記録が無いときの SessionEnd も、作業を止めない
    call_hook SessionEnd s-3 "$MAIN" reason other
    expect_rc0
}

t_worktree_folder() {
    local f="$STATE/sessions/s-wt.json"
    call_hook SessionStart s-wt "$WT" source startup
    expect_rc0
    [ -f "$f" ] || die "worktree の記録が本体の記録の置き場所にできていない"
    [ ! -e "$WT_GITDIR/keirekipro-parallel" ] || die "worktree 用の git のディレクトリに記録を作った"
    [ "$(get "$f" folder)" = "$WT" ] || die "folder が worktree でない: $(get "$f" folder)"
    [ "$(get "$f" folder_key)" = "$(key_of "$WT")" ] || die "folder_key が worktree の鍵でない: $(cat "$f")"
    [ "$(get "$f" folder_key)" != "$(key_of "$MAIN")" ] || die "worktree と本体フォルダの鍵が同じになった"
    # lib.sh の kp_session_id が、worktree ではこの記録のIDを返し、本体フォルダでは返さない
    # shellcheck source=.claude/scripts/parallel/lib.sh
    [ "$(cd "$WT" && . "$LIB" && kp_session_id)" = s-wt ] || die "worktree の kp_session_id がこの記録のIDでない"
    # shellcheck source=.claude/scripts/parallel/lib.sh
    [ -z "$(cd "$MAIN" && . "$LIB" && kp_session_id)" ] || die "本体フォルダの kp_session_id が worktree の記録のIDを返した"
}

t_subdir_and_backslash_cwd() {
    local win
    call_hook SessionStart s-sub "$MAIN/sub/dir" source startup
    expect_rc0
    [ "$(get "$STATE/sessions/s-sub.json" folder)" = "$MAIN" ] || die "cwd が下のディレクトリのとき folder が最上位でない"
    # Windows の Claude Code が渡す \ 区切りの cwd でも同じ作業フォルダになる
    win=${WT//\//\\}
    call_hook UserPromptSubmit s-bs "$win" prompt hi
    expect_rc0
    [ "$(get "$STATE/sessions/s-bs.json" folder)" = "$WT" ] || die "\\ 区切りの cwd で folder が worktree にならない: $(cat "$STATE/sessions/s-bs.json" 2>/dev/null)"
}

t_ignores_claude_project_dir() {
    OUT=$(payload SessionStart s-cpd "$WT" source startup | CLAUDE_PROJECT_DIR="$OTHER_DIR" bash "$HOOK" 2>/dev/null)
    RC=$?
    expect_rc0
    [ "$(get "$STATE/sessions/s-cpd.json" folder)" = "$WT" ] || die "CLAUDE_PROJECT_DIR ではなく cwd から作業フォルダを決めていない"
    [ ! -e "$OTHER_STATE" ] || die "CLAUDE_PROJECT_DIR のリポジトリに記録を作った"
}

t_outside_git_does_nothing() {
    call_hook SessionStart s-out "$OUTSIDE_DIR" source startup
    expect_rc0
    [ -z "$OUT" ] || die "git のリポジトリの外で標準出力に何か出た: $OUT"
    [ ! -e "$OUTSIDE_DIR/.git" ] || die "git のリポジトリの外に何か作った"
    [ ! -e "$STATE" ] || die "git のリポジトリの外で記録を作った"
    call_hook SessionStart s-out "$WORK/no-such-dir" source startup
    expect_rc0
    [ -z "$OUT" ] || die "無い cwd で標準出力に何か出た: $OUT"
}

t_bad_input_does_nothing() {
    call_hook_raw 'not json'
    expect_rc0
    [ -z "$OUT" ] || die "JSON でない入力で標準出力に何か出た: $OUT"
    call_hook SessionStart "" "$MAIN" source startup
    expect_rc0
    [ -z "$OUT" ] || die "session_id が空で標準出力に何か出た: $OUT"
    call_hook SessionStart "../evil" "$MAIN" source startup
    expect_rc0
    [ -z "$OUT" ] || die "パスを含む session_id で標準出力に何か出た: $OUT"
    call_hook UserPromptSubmit 'a\b' "$MAIN" prompt hi
    expect_rc0
    call_hook SessionEnd ".." "$MAIN" reason other
    expect_rc0
    [ ! -e "$STATE/evil.json" ] || die "パスを含む session_id で記録の置き場所の外に書いた"
    [ -z "$(ls -A "$STATE/sessions" 2>/dev/null)" ] || die "誤った session_id で記録を書いた: $(ls -A "$STATE/sessions")"
    # 知らないイベントでは何もしない
    call_hook Stop s-x "$MAIN"
    expect_rc0
    [ ! -e "$STATE/sessions/s-x.json" ] || die "登録していないイベントで記録を作った"
}

t_write_failure_does_nothing() {
    mkdir -p "$STATE"
    # sessions をファイルにして、記録を書けなくする
    : >"$STATE/sessions"
    call_hook SessionStart s-f "$MAIN" source startup
    expect_rc0
    [ -z "$OUT" ] || die "記録を書けなかったのに標準出力に何か出た: $OUT"
    call_hook UserPromptSubmit s-f "$MAIN" prompt hi
    expect_rc0
    call_hook SessionEnd s-f "$MAIN" reason other
    expect_rc0
}

# ---------------------------------------------------------------------

echo "--- 記録を作る・書き直す・消す(要件3.6・4.3・5.1)"
run_test "SessionStart で記録ができ additionalContext にIDが出る" t_session_start_creates_record
run_test "SessionStart で記録がすでにあれば last_seen だけを書き直す" t_session_start_existing_updates_last_seen
run_test "UserPromptSubmit で記録が無ければ作る" t_user_prompt_creates_record
run_test "UserPromptSubmit で記録があれば last_seen だけを書き直す" t_user_prompt_updates_last_seen
run_test "SessionEnd で記録が消える" t_session_end_removes_record

echo "--- 作業フォルダの決め方"
run_test "cwd が worktree なら記録の folder が worktree になる" t_worktree_folder
run_test "cwd が下のディレクトリでも \\ 区切りでも、最上位を作業フォルダにする" t_subdir_and_backslash_cwd
run_test "CLAUDE_PROJECT_DIR を使わず cwd から作業フォルダを決める" t_ignores_claude_project_dir

echo "--- 作業を止めない"
run_test "git のリポジトリの外では何もせずに終了コード0で終わる" t_outside_git_does_nothing
run_test "誤った入力では何もせずに終了コード0で終わる" t_bad_input_does_nothing
run_test "記録を書けないときは何もせずに終了コード0で終わる" t_write_failure_does_nothing

echo
echo "結果: 成功 $pass / 失敗 $fail"
[ "$fail" -eq 0 ]
