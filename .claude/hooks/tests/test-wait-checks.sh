#!/bin/bash
# =====================================================================
# .claude/scripts/ship/wait-checks.sh(/ship-it の検査の結果を待つ間に裏で動かすスクリプト)のテスト
#
# 実行: bash .claude/hooks/tests/test-wait-checks.sh
# このスクリプトは Stop フック check-ship-watch-before-stop.sh と組で動くので、テストをフックのテストと同じ場所に置く。
# 一時的な git のリポジトリを作り、PATH の先頭に偽の gh を置いて、呼ばれるたびに返す PR の状態と検査を差し替える。
# 本物のリポジトリの記録(.claude/.state)と GitHub には触れない。
# 前提: bash・perl(JSON::PP)・git。ホストの Git Bash から流す。
# =====================================================================
set -u
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR

SCRIPT="$(cd "$(dirname "$0")/../.." && pwd)/scripts/ship/wait-checks.sh"
TMP_ROOT=$(mktemp -d)
trap 'rm -rf "$TMP_ROOT"' EXIT
WORK=$(cd "$TMP_ROOT" && { pwd -W 2>/dev/null || pwd; })

REPO="$WORK/repo"
BIN="$WORK/bin"
FIX="$WORK/fixture"
BEAT="$REPO/.claude/.state/ship-watch/checks-wait-42"
mkdir -p "$BIN" "$FIX"
git init -q "$REPO"

# 偽の gh: 「pr view」の n 回目の呼び出しで fixture の view.<n>.out を、「pr checks」の n 回目の呼び出しで
# checks.<n>.out を標準出力に出す。<種類>.<n>.err があれば標準エラーに出し、<種類>.<n>.exit があればその終了コードで終わる。
# n 回目のファイルが1つも無ければ、n より前で最後に置いた番号のファイルを使う。
# 呼ばれたときの心拍のファイルの中身を beats.txt に残す
cat >"$BIN/gh" <<'GH'
#!/bin/bash
case "$1 $2" in
    'pr view') kind=view ;;
    'pr checks') kind=checks ;;
    *) echo "偽の gh が知らない呼び方: $*" >&2; exit 99 ;;
esac
n=$(( $(cat "$FAKE_GH_DIR/$kind.count" 2>/dev/null || echo 0) + 1 ))
echo "$n" >"$FAKE_GH_DIR/$kind.count"
printf '%s\n' "$*" >>"$FAKE_GH_DIR/calls.txt"
printf '%s\n' "$(cat "$FAKE_BEAT" 2>/dev/null)" >>"$FAKE_GH_DIR/beats.txt"
k=$n
while [ "$k" -gt 1 ] && [ ! -f "$FAKE_GH_DIR/$kind.$k.out" ] && [ ! -f "$FAKE_GH_DIR/$kind.$k.err" ] && [ ! -f "$FAKE_GH_DIR/$kind.$k.exit" ]; do k=$((k - 1)); done
[ -f "$FAKE_GH_DIR/$kind.$k.out" ] && cat "$FAKE_GH_DIR/$kind.$k.out"
[ -f "$FAKE_GH_DIR/$kind.$k.err" ] && cat "$FAKE_GH_DIR/$kind.$k.err" >&2
code=0
[ -f "$FAKE_GH_DIR/$kind.$k.exit" ] && code=$(cat "$FAKE_GH_DIR/$kind.$k.exit")
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

# n 回目の gh pr view が返す PR の状態を書く
set_state() { # <n> <state>
    printf '{"state":"%s"}\n' "$2" >"$FIX/view.$1.out"
}

# n 回目の gh pr checks が返す検査を書く。引数は「名前=bucket」を並べる
set_checks() { # <n> [<名前=bucket>...]
    local n="$1"
    shift
    perl -MJSON::PP -e '
        print JSON::PP->new->canonical->encode([ map { my ($name, $bucket) = split /=/, $_, 2; { name => $name, bucket => $bucket } } @ARGV ]);
    ' -- "$@" >"$FIX/checks.$n.out"
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

expect_count() { # <種類> <期待する呼び出しの回数> <説明>
    local got
    got=$(cat "$FIX/$1.count" 2>/dev/null || echo 0)
    [ "$got" = "$2" ] || die "$3: gh pr $1 を呼んだ回数が $got で、$2 ではない"
}

expect_beat_removed() {
    [ ! -e "$BEAT" ] || die "終わったあとに心拍のファイルが残っている"
}

t_all_results_out() {
    set_state 1 OPEN
    set_checks 1 a=pass b=pending
    set_checks 3 a=pass b=pass c=skipping
    run_script 42
    expect_rc 0 "結果がすべて出た"
    expect_out "PR #42 の必須の検査の結果がすべて出た。"
    expect_count checks 3 "3回目で結果がすべて出た"
    grep -q 'pr view 42 --json state' "$FIX/calls.txt" || die "gh pr view の呼び方が違う: $(cat "$FIX/calls.txt")"
    grep -q 'pr checks 42 --required --json name,bucket' "$FIX/calls.txt" || die "gh pr checks の呼び方が違う: $(cat "$FIX/calls.txt")"
    expect_beat_removed
}

t_red_counts_as_result() {
    set_state 1 OPEN
    set_checks 1 a=fail b=cancel c=pass
    run_script 42
    expect_rc 0 "赤の検査も結果に数える"
    expect_out "PR #42 の必須の検査の結果がすべて出た。"
}

t_merged_while_check_stays_pending() {
    # マージのあとも GitHub に「実行中」のまま残る検査があっても、マージで終わる(Issue #960 の PR #958 の場面)
    set_state 1 OPEN
    set_state 3 MERGED
    set_checks 1 size-check=pass size-check=pending
    run_script 42
    expect_rc 0 "検査が実行中のままでもマージで終わる"
    expect_out "PR #42 がマージされた。"
    expect_count view 3 "3回目にマージされた"
    expect_count checks 2 "マージに気づいたあとは検査を読まない"
    expect_beat_removed
}

t_merged_at_start() {
    set_state 1 MERGED
    run_script 42
    expect_rc 0 "動かしたときにマージ済み"
    expect_out "PR #42 がマージされた。"
    expect_count checks 0 "検査を読まずに終わる"
}

t_closed() {
    set_state 1 OPEN
    set_state 2 CLOSED
    set_checks 1 a=pending
    run_script 42
    expect_rc 0 "閉じられた"
    expect_out "PR #42 が閉じられた。"
}

t_no_checks_reported() {
    set_state 1 OPEN
    echo "no required checks reported on the 'fix/x' branch" >"$FIX/checks.1.err"
    echo 1 >"$FIX/checks.1.exit"
    run_script 42
    expect_rc 0 "必須の検査がまだ無い"
    expect_out "PR #42 の必須の検査がまだ1つも報告されていない。"
    expect_count checks 1 "すぐ終わる"
}

t_beat_written_while_waiting() {
    set_state 1 OPEN
    set_checks 1 a=pending
    set_checks 2 a=pass
    run_script 42
    expect_rc 0 "結果が出た"
    local now first
    now=$(date +%s)
    first=$(head -n 1 "$FIX/beats.txt")
    case "$first" in
        '' | *[!0-9]*) die "1回目に読む前に心拍のファイルに時刻が無い: 「$first」" ;;
    esac
    [ $((now - first)) -le 30 ] || die "心拍の時刻が古い: $first"
    expect_beat_removed
}

t_transient_failure_continues() {
    set_state 1 OPEN
    echo 1 >"$FIX/view.2.exit"
    set_state 3 OPEN
    set_checks 1 a=pending
    echo "HTTP 502" >"$FIX/checks.2.err"
    echo 1 >"$FIX/checks.2.exit"
    set_checks 3 a=pass
    run_script 42
    expect_rc 0 "読めない回をはさんでも待ち続ける"
    expect_out "PR #42 の必須の検査の結果がすべて出た。"
}

t_repeated_view_failure_stops() {
    echo 1 >"$FIX/view.1.exit"
    run_script 42
    expect_rc 1 "PR を続けて読めない"
    expect_out "PR #42 の状態か必須の検査を続けて5回読めなかった。"
    expect_count view 5 "5回で諦める"
    expect_beat_removed
}

t_repeated_checks_failure_stops() {
    set_state 1 OPEN
    echo "HTTP 502" >"$FIX/checks.1.err"
    echo 1 >"$FIX/checks.1.exit"
    run_script 42
    expect_rc 1 "検査を続けて読めない"
    expect_out "PR #42 の状態か必須の検査を続けて5回読めなかった。"
    expect_count checks 5 "5回で諦める"
}

t_bad_argument() {
    run_script abc
    expect_rc 64 "PR番号でない引数"
    [ ! -f "$FIX/calls.txt" ] || die "引数が誤っているのに gh を呼んだ"
    run_script
    expect_rc 64 "引数が無い"
}

run_test "必須の検査の結果がすべて出たら終わる" t_all_results_out
run_test "赤の検査も結果が出たものに数える" t_red_counts_as_result
run_test "実行中のまま残る検査があっても、マージされたら終わる" t_merged_while_check_stays_pending
run_test "動かしたときにマージ済みならすぐ終わる" t_merged_at_start
run_test "閉じられたら終わる" t_closed
run_test "必須の検査がまだ1つも無ければすぐ終わる" t_no_checks_reported
run_test "待っている間は心拍のファイルに時刻を書き、終わったら消す" t_beat_written_while_waiting
run_test "1回読めなくても待ち続ける" t_transient_failure_continues
run_test "PR を続けて5回読めなければ 1 で終わる" t_repeated_view_failure_stops
run_test "検査を続けて5回読めなければ 1 で終わる" t_repeated_checks_failure_stops
run_test "PR番号でない引数は 64 で終わる" t_bad_argument

printf '\n%d 件成功、%d 件失敗\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
