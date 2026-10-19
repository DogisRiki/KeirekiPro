#!/bin/bash
# =====================================================================
# resume-after-usage-limit.sh(使う量の上限が戻ったら会話を再開させるフック)のテスト
#
# 実行: bash .claude/hooks/tests/test-resume-after-usage-limit.sh
# フックに Claude Code の StopFailure / Stop フックの入力(JSON)と、作った会話の記録(JSONL)を渡して、
# 待つ秒(RESUME_AFTER_LIMIT_DRY_RUN=1 のときの標準出力)と、終了コード(0 は起こさない、2 は起こす)と
# 標準エラーを確かめる。待つ時間は試験のための環境変数で数秒に縮める。
# 前提: bash・perl(JSON::PP、Time::Local)。ホストの Git Bash から流す。
# =====================================================================
set -u

HOOK="$(cd "$(dirname "$0")/.." && pwd)/resume-after-usage-limit.sh"
TMP_ROOT=$(mktemp -d)
trap 'rm -rf "$TMP_ROOT"' EXIT
WORK=$(cd "$TMP_ROOT" && { pwd -W 2>/dev/null || pwd; })
TRANSCRIPT="$WORK/transcript.jsonl"
MARKER='[resume-after-usage-limit]'

# 時刻を読むときの「いま」: この PC の時刻の帯で 2026-10-19(月)13:00:00
NOW=$(perl -MTime::Local -e 'print timelocal(0, 0, 13, 19, 9, 2026)')
MARGIN=180

pass=0
fail=0

die() {
    printf '%s\n' "$*"
    exit 1
}

run_test() { # <テスト名> <関数>
    local name="$1" fn="$2" out
    rm -f "$TRANSCRIPT"
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
payload() { # <hook_event_name> <last_assistant_message> [<追加のキー> <値>]...
    perl -MJSON::PP -e '
        my ($event, $msg, @rest) = @ARGV;
        utf8::decode($_) for $msg, @rest;
        my %d = (session_id => "s-1", hook_event_name => $event,
                 transcript_path => $ENV{TRANSCRIPT}, last_assistant_message => $msg);
        $d{error} = "rate_limit" if $event eq "StopFailure";
        while (@rest) { my ($k, $v) = splice(@rest, 0, 2); $d{$k} = $v eq "-" ? undef : $v; }
        delete $d{$_} for grep { !defined $d{$_} } keys %d;
        print JSON::PP->new->utf8->canonical->encode(\%d);
    ' -- "$@"
}

# 会話の記録に1行足す
#   prompt <文>        所有者の指示
#   assistant <文>     Claude の返答
#   apierror <文>      上限で断られた返答(isApiErrorMessage)
#   tool <文>          道具の結果
#   notify <文>        知らせ(task-notification)
#   notifyarr <文>     知らせ(本文が文の塊の配列の形)
#   meta <文>          補足(isMeta)
add_row() { # <種類> <文>
    TRANSCRIPT="$TRANSCRIPT" perl -MJSON::PP -e '
        my ($kind, $text) = @ARGV;
        utf8::decode($text);
        my $d;
        if ($kind eq "prompt") { $d = {type => "user", message => {role => "user", content => [{type => "text", text => $text}]}} }
        elsif ($kind eq "assistant") { $d = {type => "assistant", message => {role => "assistant", content => [{type => "text", text => $text}]}} }
        elsif ($kind eq "apierror") { $d = {type => "assistant", isApiErrorMessage => JSON::PP::true, message => {role => "assistant", content => [{type => "text", text => $text}]}} }
        elsif ($kind eq "tool") { $d = {type => "user", message => {role => "user", content => [{type => "tool_result", tool_use_id => "t1", content => $text}]}} }
        elsif ($kind eq "notify") { $d = {type => "user", message => {role => "user", content => "<task-notification>\n$text"}} }
        elsif ($kind eq "notifyarr") { $d = {type => "user", message => {role => "user", content => [{type => "text", text => "<task-notification>\n$text"}]}} }
        elsif ($kind eq "meta") { $d = {type => "user", isMeta => JSON::PP::true, message => {role => "user", content => $text}} }
        else { die "unknown kind $kind" }
        open my $fh, ">>", $ENV{TRANSCRIPT} or die;
        print $fh JSON::PP->new->utf8->canonical->encode($d), "\n";
    ' -- "$1" "$2"
}

# 待つ秒だけを求める(待たずに終える)
dry_run() { # <入力の JSON>
    printf '%s' "$1" | RESUME_AFTER_LIMIT_DRY_RUN=1 RESUME_AFTER_LIMIT_NOW="$NOW" \
        RESUME_AFTER_LIMIT_MARGIN="$MARGIN" bash "$HOOK"
}

expect_delay() { # <入力の JSON> <期待する秒(空なら何も出さない)>
    local out code
    out=$(dry_run "$1")
    code=$?
    [ "$code" -eq 0 ] || die "終了コードが0でない: $code"
    [ "$out" = "$2" ] || die "待つ秒が違う: 期待 '$2' / 実際 '$out'"
}

limit_line() { # <種類> <時刻>
    printf "You've hit your %s limit · resets %s" "$1" "$2"
}

# --- 上限の時刻の読み方(StopFailure)
t_session_time_today() {
    expect_delay "$(payload StopFailure "$(limit_line session '5:20pm (Asia/Tokyo)')")" $((4 * 3600 + 20 * 60 + MARGIN))
}
t_session_hour_only_tomorrow() {
    expect_delay "$(payload StopFailure "$(limit_line session '11am (Asia/Tokyo)')")" $((22 * 3600 + MARGIN))
}
t_just_reset_waits_margin() {
    expect_delay "$(payload StopFailure "$(limit_line session '12:30pm')")" "$MARGIN"
}
t_noon_and_midnight() {
    expect_delay "$(payload StopFailure "$(limit_line session '12pm')")" "$MARGIN" || return 1
    expect_delay "$(payload StopFailure "$(limit_line session '12am')")" $((11 * 3600 + MARGIN))
}
t_24h_clock() {
    expect_delay "$(payload StopFailure "$(limit_line session '17:20')")" $((4 * 3600 + 20 * 60 + MARGIN))
}
t_weekly_weekday() {
    # 月曜の 13:00 に「Mon 12:00am」は次の月曜の 0:00
    expect_delay "$(payload StopFailure "$(limit_line weekly 'Mon 12:00am')")" $((7 * 86400 - 13 * 3600 + MARGIN)) || return 1
    expect_delay "$(payload StopFailure "$(limit_line weekly 'Wed 9am')")" $((2 * 86400 - 4 * 3600 + MARGIN))
}
t_month_day() {
    expect_delay "$(payload StopFailure "$(limit_line weekly 'Oct 21, 10am (Asia/Tokyo)')")" $((2 * 86400 - 3 * 3600 + MARGIN))
}
t_model_limits_and_apostrophe() {
    expect_delay "$(payload StopFailure "$(limit_line Opus '5:20pm')")" $((4 * 3600 + 20 * 60 + MARGIN)) || return 1
    expect_delay "$(payload StopFailure "You’ve hit your Sonnet limit · resets 5:20pm")" $((4 * 3600 + 20 * 60 + MARGIN))
}
t_last_match_wins() {
    expect_delay "$(payload StopFailure "$(limit_line session '2pm')
$(limit_line session '5:20pm')")" $((4 * 3600 + 20 * 60 + MARGIN))
}
t_other_error_ignored() {
    expect_delay "$(payload StopFailure "$(limit_line session '5:20pm')" error server_error)" ""
}
t_unreadable_time_ignored() {
    expect_delay "$(payload StopFailure "$(limit_line session 'soon')")" "" || return 1
    expect_delay "$(payload StopFailure "API Error: 429 rate limited")" "" || return 1
    expect_delay "$(payload StopFailure "$(limit_line session '25:00')")" ""
}
t_other_event_ignored() {
    expect_delay "$(payload SessionEnd "$(limit_line session '5:20pm')")" ""
}

# --- Stop: 最後の返答の中の上限の文
t_stop_tool_result() {
    add_row prompt "テストを流して"
    add_row assistant "流します"
    add_row tool "$(limit_line session '5:20pm (Asia/Tokyo)')"
    expect_delay "$(payload Stop "子の Claude が使う量の上限で止まりました")" $((4 * 3600 + 20 * 60 + MARGIN))
}
t_stop_notification_and_meta() {
    add_row prompt "テストを流して"
    add_row notify "Agent terminated early due to an API error: $(limit_line session '5:20pm')"
    expect_delay "$(payload Stop "補助役が usage limit で止まった")" $((4 * 3600 + 20 * 60 + MARGIN)) || return 1
    rm -f "$TRANSCRIPT"
    add_row prompt "テストを流して"
    add_row meta "$(limit_line weekly 'Wed 9am')"
    expect_delay "$(payload Stop "上限です")" $((2 * 86400 - 4 * 3600 + MARGIN))
}
t_stop_needs_limit_word() {
    add_row prompt "テストを流して"
    add_row tool "$(limit_line session '5:20pm')"
    expect_delay "$(payload Stop "終わりました")" ""
}
t_stop_earlier_turn_ignored() {
    add_row prompt "テストを流して"
    add_row tool "$(limit_line session '5:20pm')"
    add_row assistant "上限で止まりました"
    add_row prompt "続けて"
    add_row tool "ok"
    expect_delay "$(payload Stop "上限の話はもう済みました")" ""
}
t_stop_owner_prompt_ignored() {
    add_row prompt "この文の意味は? $(limit_line session '5:20pm')"
    add_row tool "ok"
    expect_delay "$(payload Stop "上限が戻る時刻の知らせです")" ""
}
t_stop_turn_started_by_notification() {
    add_row prompt "補助役に任せて"
    add_row assistant "任せました"
    add_row notify "Agent terminated early due to an API error: $(limit_line session '5:20pm')"
    expect_delay "$(payload Stop "補助役が上限で止まりました")" $((4 * 3600 + 20 * 60 + MARGIN))
}
t_stop_assistant_text_ignored() {
    add_row prompt "上限の文の形を教えて"
    add_row assistant "$(limit_line session '5:20pm')"
    expect_delay "$(payload Stop "$(limit_line session '5:20pm')")" ""
}
t_stop_no_transcript() {
    expect_delay "$(payload Stop "上限で止まりました" transcript_path "$WORK/none.jsonl")" ""
}
t_stop_backslash_path() {
    add_row prompt "テストを流して"
    add_row tool "$(limit_line session '5:20pm')"
    expect_delay "$(payload Stop "上限で止まりました" transcript_path "${TRANSCRIPT//\//\\}")" $((4 * 3600 + 20 * 60 + MARGIN))
}

# --- 待ってから起こすか(待つ時間を数秒に縮めて流す)
# いまより少し前に戻った上限の文(待つ秒は余白の秒になる)
recent_limit() {
    limit_line session "$(perl -e '
        my @t = localtime(time - 600); my $h = $t[2] % 12 || 12;
        printf "%d:%02d%s", $h, $t[1], $t[2] < 12 ? "am" : "pm";')"
}

# 起こすまで待って、終了コードと標準エラーを控える(背景で流し、途中で記録に行を足せるようにする)
start_hook() { # <入力の JSON>
    printf '%s' "$1" | RESUME_AFTER_LIMIT_MARGIN=3 RESUME_AFTER_LIMIT_SETTLE=1 RESUME_AFTER_LIMIT_POLL=1 \
        bash "$HOOK" 2>"$WORK/stderr.txt" &
    HOOK_PID=$!
}
finish_hook() { # <期待する終了コード>
    local code waited=0
    # 待つ秒を読み違えたフックは何時間も待つので、30秒で打ち切って失敗にする
    while kill -0 "$HOOK_PID" 2>/dev/null; do
        if [ "$waited" -ge 30 ]; then
            kill "$HOOK_PID" 2>/dev/null
            wait "$HOOK_PID" 2>/dev/null
            die "30秒たってもフックが終わらない"
        fi
        sleep 1
        waited=$((waited + 1))
    done
    wait "$HOOK_PID"
    code=$?
    [ "$code" -eq "$1" ] || die "終了コードが違う: 期待 $1 / 実際 $code / 標準エラー: $(cat "$WORK/stderr.txt")"
    if [ "$1" -eq 2 ]; then
        grep -qF "$MARKER" "$WORK/stderr.txt" || die "起こす文に目印が無い: $(cat "$WORK/stderr.txt")"
    else
        [ ! -s "$WORK/stderr.txt" ] || die "起こさないのに標準エラーがある: $(cat "$WORK/stderr.txt")"
    fi
}

t_wakes_when_no_progress() {
    add_row prompt "続けて"
    add_row apierror "$(recent_limit)"
    start_hook "$(payload StopFailure "$(recent_limit)")"
    finish_hook 2
}
t_api_error_is_not_progress() {
    add_row prompt "続けて"
    start_hook "$(payload StopFailure "$(recent_limit)")"
    sleep 2
    add_row apierror "$(recent_limit)"
    finish_hook 2
}
t_progress_by_owner_skips() {
    add_row prompt "続けて"
    start_hook "$(payload StopFailure "$(recent_limit)")"
    sleep 2
    add_row prompt "まだ止まってる?"
    finish_hook 0
}
t_progress_by_assistant_skips() {
    add_row prompt "続けて"
    start_hook "$(payload StopFailure "$(recent_limit)")"
    sleep 2
    add_row assistant "自分で続けました"
    finish_hook 0
}
t_wake_limit() {
    add_row prompt "続けて"
    add_row notify "<summary>Stop hook feedback</summary> $MARKER 1"
    add_row notify "<summary>Stop hook feedback</summary> $MARKER 2"
    start_hook "$(payload StopFailure "$(recent_limit)")"
    finish_hook 2 || return 1
    add_row notify "<summary>Stop hook feedback</summary> $MARKER 3"
    start_hook "$(payload StopFailure "$(recent_limit)")"
    finish_hook 0
}
t_wake_limit_array_content() {
    add_row prompt "続けて"
    add_row notifyarr "<summary>Stop hook feedback</summary> $MARKER 1"
    add_row notifyarr "other task finished"
    add_row notifyarr "<summary>Stop hook feedback</summary> $MARKER 2"
    add_row notifyarr "<summary>Stop hook feedback</summary> $MARKER 3"
    start_hook "$(payload StopFailure "$(recent_limit)")"
    finish_hook 0
}
t_owner_prompt_resets_wake_count() {
    add_row prompt "続けて"
    add_row notify "<summary>Stop hook feedback</summary> $MARKER 1"
    add_row notify "<summary>Stop hook feedback</summary> $MARKER 2"
    add_row notify "other task finished"
    add_row notify "<summary>Stop hook feedback</summary> $MARKER 3"
    add_row prompt "もう一度続けて"
    start_hook "$(payload StopFailure "$(recent_limit)")"
    finish_hook 2
}
t_wakes_without_transcript() {
    start_hook "$(payload StopFailure "$(recent_limit)" transcript_path -)"
    finish_hook 2
}
t_stop_path_wakes() {
    add_row prompt "テストを流して"
    add_row tool "$(recent_limit)"
    add_row assistant "子の Claude が上限で止まりました"
    start_hook "$(payload Stop "子の Claude が上限で止まりました")"
    finish_hook 2
}

export TRANSCRIPT

echo "--- 上限の時刻の読み方(StopFailure)"
run_test "時と分の時刻は今日のその時刻" t_session_time_today
run_test "過ぎた時刻は明日のその時刻" t_session_hour_only_tomorrow
run_test "戻る時刻を過ぎたばかりなら余白の秒だけ待つ" t_just_reset_waits_margin
run_test "12pm は正午、12am は夜中の0時" t_noon_and_midnight
run_test "24時間の形の時刻" t_24h_clock
run_test "曜日つきの時刻は次のその曜日" t_weekly_weekday
run_test "月と日つきの時刻" t_month_day
run_test "Opus と Sonnet の上限、曲がった引用符" t_model_limits_and_apostrophe
run_test "上限の文が複数あれば最後のもの" t_last_match_wins
run_test "rate_limit でない失敗は扱わない" t_other_error_ignored
run_test "時刻が読めなければ何もしない" t_unreadable_time_ignored
run_test "StopFailure と Stop でない入力は扱わない" t_other_event_ignored

echo "--- Stop: 最後の返答の中の上限の文"
run_test "道具の結果の上限の文" t_stop_tool_result
run_test "知らせと補足の上限の文" t_stop_notification_and_meta
run_test "最後の返答の文が上限に触れなければ扱わない" t_stop_needs_limit_word
run_test "前の返答の上限の文は扱わない" t_stop_earlier_turn_ignored
run_test "所有者の指示の中の上限の文は扱わない" t_stop_owner_prompt_ignored
run_test "知らせで始まった返答の知らせの上限の文" t_stop_turn_started_by_notification
run_test "Claude の返答の中の上限の文は扱わない" t_stop_assistant_text_ignored
run_test "会話の記録が無ければ扱わない" t_stop_no_transcript
run_test "会話の記録のパスが \\ 区切りでも読む" t_stop_backslash_path

echo "--- 待ってから起こすか"
run_test "会話が進んでいなければ起こす" t_wakes_when_no_progress
run_test "上限で断られた返答は進んだとみなさない" t_api_error_is_not_progress
run_test "所有者が話しかけたら起こさない" t_progress_by_owner_skips
run_test "Claude が返答したら起こさない" t_progress_by_assistant_skips
run_test "所有者の指示のあとに3回起こしたら起こさない" t_wake_limit
run_test "配列の形の知らせも起こした回数に数える" t_wake_limit_array_content
run_test "所有者の新しい指示で起こした回数を数え直す" t_owner_prompt_resets_wake_count
run_test "StopFailure で会話の記録が無くても起こす" t_wakes_without_transcript
run_test "Stop の道具の結果の上限でも起こす" t_stop_path_wakes

echo
echo "結果: 成功 $pass / 失敗 $fail"
[ "$fail" -eq 0 ]
