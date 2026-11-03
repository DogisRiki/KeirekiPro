#!/bin/bash
# =====================================================================
# .claude/scripts/ship/wait-approval.sh(/ship の承認待ちで裏で動かすスクリプト)のテスト
#
# 実行: bash .claude/hooks/tests/test-wait-approval.sh
# このスクリプトは Stop フック check-ship-watch-before-stop.sh と組で動くので、テストをフックのテストと同じ場所に置く。
# 一時的な git のリポジトリを作り、PATH の先頭に偽の gh を置いて、gh pr view が呼ばれるたびに返す PR の状態を差し替える。
# 本物のリポジトリの記録(.claude/.state)と GitHub には触れない。
# 前提: bash・perl(JSON::PP)・git。ホストの Git Bash から流す。
# =====================================================================
set -u
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR

SCRIPT="$(cd "$(dirname "$0")/../.." && pwd)/scripts/ship/wait-approval.sh"
TMP_ROOT=$(mktemp -d)
trap 'rm -rf "$TMP_ROOT"' EXIT
WORK=$(cd "$TMP_ROOT" && { pwd -W 2>/dev/null || pwd; })

REPO="$WORK/repo"
BIN="$WORK/bin"
FIX="$WORK/fixture"
BEAT="$REPO/.claude/.state/ship-watch/approval-wait-42"
mkdir -p "$BIN" "$FIX"
git init -q "$REPO"

# 偽の gh: n 回目の呼び出しで fixture の pr.<n>.json を出す。無ければ、n より前で最後に置いた番号のファイルを出す。
# pr.<n>.exit があればその終了コードで終わる。呼ばれたときの心拍のファイルの中身を beats.txt に残す
cat >"$BIN/gh" <<'GH'
#!/bin/bash
n=$(( $(cat "$FAKE_GH_DIR/count" 2>/dev/null || echo 0) + 1 ))
echo "$n" >"$FAKE_GH_DIR/count"
printf '%s\n' "$*" >>"$FAKE_GH_DIR/calls.txt"
printf '%s\n' "$(cat "$FAKE_BEAT" 2>/dev/null)" >>"$FAKE_GH_DIR/beats.txt"
k=$n
while [ "$k" -gt 1 ] && [ ! -f "$FAKE_GH_DIR/pr.$k.json" ] && [ ! -f "$FAKE_GH_DIR/pr.$k.exit" ]; do k=$((k - 1)); done
[ -f "$FAKE_GH_DIR/pr.$k.json" ] && cat "$FAKE_GH_DIR/pr.$k.json"
code=0
[ -f "$FAKE_GH_DIR/pr.$k.exit" ] && code=$(cat "$FAKE_GH_DIR/pr.$k.exit")
exit "$code"
GH
chmod +x "$BIN/gh"
export FAKE_GH_DIR="$FIX" FAKE_BEAT="$BEAT" SHIP_WAIT_INTERVAL=0
# PATH は : で区切るので、ドライブ文字の形(C:/...)ではなく mktemp が返した形で足す
export PATH="$TMP_ROOT/bin:$PATH"
[ "$(command -v gh)" = "$TMP_ROOT/bin/gh" ] || {
    printf '偽の gh が PATH の先頭に来ていない: %s\n' "$(command -v gh)"
    exit 1
}

pass=0
fail=0

die() {
    printf '%s\n' "$*"
    exit 1
}

run_test() { # <テスト名> <関数>
    local name="$1" fn="$2" out
    rm -rf "${FIX:?}"/* "$REPO/.claude"
    if out=$("$fn" 2>&1); then
        pass=$((pass + 1))
        printf 'ok: %s\n' "$name"
    else
        fail=$((fail + 1))
        printf 'FAIL: %s\n' "$name"
        printf '%s\n' "$out" | sed 's/^/    /'
    fi
}

# n 回目の gh pr view が返す PR を書く
set_pr() { # <n> <state> [<head>] [<レビューの状態をカンマ区切り>] [<コメントの数>]
    perl -MJSON::PP -e '
        my ($state, $head, $reviews, $comments) = @ARGV;
        print JSON::PP->new->canonical->encode({
            state => $state, headRefOid => $head,
            reviews => [ map { { state => $_, author => { login => "owner" } } } grep { length } split /,/, $reviews ],
            comments => [ map { { body => "c$_" } } 1 .. $comments ],
        });
    ' -- "$2" "${3:-aaa111}" "${4-}" "${5:-0}" >"$FIX/pr.$1.json"
}

# スクリプトを動かし、終了コードを RC に、標準出力を OUT に、標準エラーを ERR に入れる
run_script() { # [<引数>...]
    local errf="$WORK/err.txt"
    OUT=$(cd "$REPO" && timeout 30 bash "$SCRIPT" "$@" 2>"$errf")
    RC=$?
    ERR=$(cat "$errf")
}

expect_rc() { # <期待する終了コード> <説明>
    [ "$RC" = "$1" ] || die "$2: 終了コードが $RC で、$1 ではない。標準出力: $OUT 標準エラー: $ERR"
}

expect_out() { # <期待する標準出力>
    [ "$OUT" = "$1" ] || die "標準出力が「$OUT」で、「$1」ではない"
}

expect_count() { # <期待する gh の呼び出しの回数> <説明>
    [ "$(cat "$FIX/count")" = "$1" ] || die "$2: gh を呼んだ回数が $(cat "$FIX/count") で、$1 ではない"
}

expect_beat_removed() {
    [ ! -e "$BEAT" ] || die "終わったあとに心拍のファイルが残っている"
}

t_approved() {
    set_pr 1 OPEN aaa111 "COMMENTED"
    set_pr 3 OPEN aaa111 "COMMENTED,APPROVED"
    run_script 42
    expect_rc 0 "承認された"
    expect_out "PR #42 が承認された。"
    expect_count 3 "3回目で承認された"
    grep -q 'pr view 42 --json state,headRefOid,reviews,comments' "$FIX/calls.txt" || die "gh pr view の呼び方が違う: $(cat "$FIX/calls.txt")"
    expect_beat_removed
}

t_beat_written_while_waiting() {
    set_pr 1 OPEN
    set_pr 2 OPEN aaa111 "APPROVED"
    run_script 42
    expect_rc 0 "承認された"
    local now first
    now=$(date +%s)
    first=$(head -n 1 "$FIX/beats.txt")
    case "$first" in
        '' | *[!0-9]*) die "1回目に読む前に心拍のファイルに時刻が無い: 「$first」" ;;
    esac
    [ $((now - first)) -le 30 ] || die "心拍の時刻が古い: $first"
    expect_beat_removed
}

t_already_approved_waits_for_new_approval() {
    set_pr 1 OPEN aaa111 "APPROVED"
    set_pr 3 OPEN aaa111 "APPROVED,APPROVED"
    run_script 42
    expect_rc 0 "前の承認のあとに承認し直された"
    expect_out "PR #42 が承認された。"
    expect_count 3 "前からあった承認では終わらない"
}

t_merged() {
    set_pr 1 OPEN
    set_pr 2 MERGED
    run_script 42
    expect_rc 0 "マージされた"
    expect_out "PR #42 がマージされた。"
    expect_beat_removed
}

t_merged_at_start() {
    set_pr 1 MERGED
    run_script 42
    expect_rc 0 "動かしたときにマージ済み"
    expect_out "PR #42 がマージされた。"
    expect_count 1 "すぐ終わる"
}

t_closed() {
    set_pr 1 OPEN
    set_pr 2 CLOSED
    run_script 42
    expect_rc 0 "閉じられた"
    expect_out "PR #42 が閉じられた。"
}

t_changes_requested() {
    set_pr 1 OPEN
    set_pr 2 OPEN aaa111 "CHANGES_REQUESTED"
    run_script 42
    expect_rc 0 "変更を求めるレビュー"
    expect_out "PR #42 に承認のほかのレビューが付いた。"
}

t_comment() {
    set_pr 1 OPEN aaa111 "" 1
    set_pr 2 OPEN aaa111 "" 2
    run_script 42
    expect_rc 0 "コメントが付いた"
    expect_out "PR #42 にコメントが付いた。"
}

t_head_changed() {
    set_pr 1 OPEN aaa111
    set_pr 2 OPEN bbb222
    run_script 42
    expect_rc 0 "head が変わった"
    expect_out "PR #42 の head が変わった。"
}

t_transient_failure_continues() {
    set_pr 1 OPEN
    echo 1 >"$FIX/pr.2.exit"
    set_pr 3 OPEN aaa111 "APPROVED"
    run_script 42
    expect_rc 0 "1回読めなかったあとに承認された"
    expect_out "PR #42 が承認された。"
}

t_repeated_failure_stops() {
    echo 1 >"$FIX/pr.1.exit"
    run_script 42
    expect_rc 1 "続けて読めない"
    expect_out "PR #42 の状態を続けて5回読めなかった。"
    expect_count 5 "5回で諦める"
    expect_beat_removed
}

t_bad_argument() {
    run_script abc
    expect_rc 64 "PR番号でない引数"
    [ ! -f "$FIX/count" ] || die "引数が誤っているのに gh を呼んだ"
    run_script
    expect_rc 64 "引数が無い"
}

run_test "承認のレビューが新しく付いたら終わる" t_approved
run_test "待っている間は心拍のファイルに時刻を書き、終わったら消す" t_beat_written_while_waiting
run_test "前からある承認では終わらず、新しい承認で終わる" t_already_approved_waits_for_new_approval
run_test "マージされたら終わる" t_merged
run_test "動かしたときにマージ済みならすぐ終わる" t_merged_at_start
run_test "閉じられたら終わる" t_closed
run_test "変更を求めるレビューが付いたら終わる" t_changes_requested
run_test "コメントが付いたら終わる" t_comment
run_test "head が変わったら終わる" t_head_changed
run_test "1回読めなくても待ち続ける" t_transient_failure_continues
run_test "続けて5回読めなければ 1 で終わる" t_repeated_failure_stops
run_test "PR番号でない引数は 64 で終わる" t_bad_argument

printf '\n%d 件成功、%d 件失敗\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
