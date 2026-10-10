#!/bin/bash
# =====================================================================
# SessionStart / UserPromptSubmit / Stop / StopFailure / Notification / SessionEnd hook:
# セッションの記録を付ける
#
# 並行作業のスクリプト(.claude/scripts/parallel/)が作業中のセッションを見分けるための
# 記録 sessions/<session_id>.json を、本体の .git/keirekipro-parallel/ の下に付ける。
#   SessionStart      記録を作る(すでにあれば last_seen を書き直す)。responding は偽にする
#                     (source が compact のときは、返答の途中で起きることがあるので responding を変えない)。
#                     additionalContext でセッションのIDを Claude に渡す
#   UserPromptSubmit  記録の last_seen を書き直し、responding を真にする(無ければ SessionStart と同じく作る)
#   Stop              返答を終えた。記録があれば responding を偽にする
#   StopFailure       API の失敗で返答を終えた。Stop と同じ
#   Notification      notification_type が idle_prompt(返答を終えて入力を待っている)のときだけ、
#                     記録があれば responding を偽にする。所有者が返答を止めたときは Stop が動かないため
#   SessionEnd        記録を消す
# 記録の欄: session_id folder folder_key started_at last_seen(時刻は UNIX 秒)
#           responding(返答している途中なら真。session.sh check-start の capacity が数える)
# 作業フォルダは入力の cwd から git -C <cwd> rev-parse --show-toplevel で決める
# (CLAUDE_PROJECT_DIR は使わない。worktree で開いたセッションをその worktree の記録にするため)。
# 記録の置き場所と JSON の読み書きは lib.sh を使う。
# 作業を止めない: git のリポジトリの外で呼ばれたときと、記録を書けなかったときは、
# 何もせずに終了コード0で終わる。
# 前提: bash と perl(JSON::PP)と git。jqには依存しない。
# Windowsでは Git for Windows(Git Bash同梱)がこれらを提供する。macOS/Linuxは標準。
# =====================================================================
set -u
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR

payload=$(cat)

extract() {
    printf '%s' "$payload" | perl -MJSON::PP -e '
        local $/; my $d = eval { JSON::PP::decode_json(<STDIN>) };
        exit 0 unless ref $d eq "HASH";
        my $v = $d->{$ARGV[0]};
        if (defined $v && !ref $v) { utf8::encode($v) if utf8::is_utf8($v); print $v }
    ' -- "$1" 2>/dev/null
}

event=$(extract hook_event_name)
sid=$(extract session_id)
cwd=$(extract cwd)

case "$event" in
    SessionStart | UserPromptSubmit | Stop | StopFailure | SessionEnd) ;;
    Notification)
        [ "$(extract notification_type)" = idle_prompt ] || exit 0
        ;;
    *) exit 0 ;;
esac

# セッションのIDはファイル名に使うので、空とパスの区切りを含むものは受け付けない
case "$sid" in
    '' | . | .. | */* | *\\*) exit 0 ;;
esac

[ -n "$cwd" ] || exit 0
cwd=${cwd//\\//}
[ -d "$cwd" ] || exit 0
top=$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null) || exit 0
[ -n "$top" ] || exit 0
cd "$top" 2>/dev/null || exit 0

lib="$(dirname "$0")/../scripts/parallel/lib.sh"
[ -f "$lib" ] || exit 0
# shellcheck source=.claude/scripts/parallel/lib.sh
. "$lib" || exit 0

# lib.sh の関数は失敗すると exit 69 で終わるので、サブシェルで呼ぶ
state=$(kp_state_dir 2>/dev/null) || exit 0
record="$state/sessions/$sid.json"

if [ "$event" = SessionEnd ]; then
    rm -f "$record" 2>/dev/null
    exit 0
fi

has_record=0
[ -f "$record" ] && [ -n "$(kp_json_get "$record" session_id 2>/dev/null)" ] && has_record=1

# 返答を終えた: 記録があるときだけ responding を偽にする(記録は作らない)
case "$event" in
    Stop | StopFailure | Notification)
        [ "$has_record" = 1 ] || exit 0
        kp_json_write "$record" responding:=false 2>/dev/null
        exit 0
        ;;
esac

now=$(date +%s)
if [ "$event" = UserPromptSubmit ]; then
    responding=true
elif [ "$(extract source)" = compact ]; then
    responding=""
else
    responding=false
fi
if [ "$has_record" = 1 ]; then
    if [ -n "$responding" ]; then
        kp_json_write "$record" last_seen:="$now" responding:="$responding" 2>/dev/null || exit 0
    else
        kp_json_write "$record" last_seen:="$now" 2>/dev/null || exit 0
    fi
else
    folder=$(kp_folder 2>/dev/null) || exit 0
    key=$(kp_folder_key 2>/dev/null) || exit 0
    mkdir -p "$state/sessions" 2>/dev/null || exit 0
    kp_json_write "$record" session_id="$sid" folder="$folder" folder_key="$key" \
        started_at:="$now" last_seen:="$now" responding:="${responding:-false}" 2>/dev/null || exit 0
fi

# UserPromptSubmit の標準出力は Claude の文脈に足されるので、SessionStart のときだけ出す
if [ "$event" = SessionStart ]; then
    perl -MJSON::PP -e '
        my $sid = $ARGV[0];
        my $ctx = "[parallel] このセッションのID: $sid(並行作業のスクリプトに --session で渡す)";
        utf8::decode($ctx);
        print JSON::PP->new->utf8->canonical->encode({
            hookSpecificOutput => {
                hookEventName => "SessionStart",
                additionalContext => $ctx,
            },
        }), "\n";
    ' -- "$sid" 2>/dev/null
fi

exit 0
