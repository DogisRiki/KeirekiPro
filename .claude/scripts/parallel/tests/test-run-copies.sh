#!/bin/bash
# =====================================================================
# run-copies.pl(壊した写しのテストを、写しごとに時間の上限を付けて同時に流すスクリプト)のテスト
#
# 実行: bash .claude/scripts/parallel/tests/test-run-copies.sh
# 場合を選んで流す: KP_TEST_CASE='timeout stdin' bash .claude/scripts/parallel/tests/test-run-copies.sh
#   KP_TEST_CASE に空白で区切って書いた名前の場合だけを流す。知らない名前があれば何も流さずに失敗する
# 一時的なフォルダに写しの代わりのフォルダと一覧のファイルを作り、run-copies.pl を呼ぶ。
# 前提: bash・perl。ホストの Git Bash から流す。
# =====================================================================
set -u

RUNNER="$(cd "$(dirname "$0")/.." && pwd)/run-copies.pl"
TMP_ROOT=$(mktemp -d)
trap 'rm -rf "$TMP_ROOT"' EXIT

PASS=0
FAIL=0
ok() { PASS=$((PASS + 1)); echo "ok   $1"; }
ng() { FAIL=$((FAIL + 1)); echo "NG   $1"; }
check() { if [ "$2" -eq 0 ]; then ok "$1"; else ng "$1"; fi; }
# 直前に呼んだスクリプトの終了コードを比べる: rc_is <終了コード> <名前>
rc_is() { if [ "$RC" -eq "$1" ]; then ok "$2"; else ng "$2"; fi; }

# 場合ごとに空のフォルダ $D を作り、その中の写し $D/a を用意する
fresh() {
    D="$TMP_ROOT/$1"
    mkdir -p "$D/a"
}

# $D/list.txt の一覧でスクリプトを呼ぶ: run <引数>...
run() {
    OUT=$(perl "$RUNNER" "$@" "$D/list.txt" "$D/logs" 2>"$D/err.txt")
    RC=$?
}

case_finish() {
    fresh finish
    printf 'one\t%s\techo out; echo err >&2; exit 3\ntwo\t%s\tpwd >where.txt\n' "$D/a" "$D/a" >"$D/list.txt"; run
    rc_is 0 "finish: 全部が上限の前に終われば0で終わる"
    printf "%s\n" "$OUT" | grep -qx "one rc=3 [0-9]*s" && printf "%s\n" "$OUT" | grep -qx "two rc=0 [0-9]*s"; check "finish: 写しの終了コードを1行ずつ出す" $?
    [ "$(cat "$D/logs/one.log")" = "$(printf "out\nerr")" ]; check "finish: 標準出力と標準エラーを写しの記録に書く" $?
    [ -s "$D/a/where.txt" ]; check "finish: 写しのフォルダに移ってコマンドを動かす" $?
    grep -q "^one 開始 [0-9:]* 上限 300s$" "$D/logs/progress.txt" && grep -q "^one 終了 [0-9:]* rc=3 " "$D/logs/progress.txt"; check "finish: 進み具合に開始と終了の時刻を書く" $?
}

case_stdin() {
    fresh stdin
    # スクリプトの標準入力を、10秒は終わらない入力にする。写しがそれを読むと上限まで待つことになる
    printf 'reader\t%s\tcat; echo read-end\n' "$D/a" >"$D/list.txt"; run --timeout 5 < <(sleep 10)
    [ "$RC" -eq 0 ] && grep -qx "read-end" "$D/logs/reader.log"; check "stdin: 標準入力を読むコマンドは待たずに終わる" $?
}

case_timeout() {
    fresh timeout
    printf 'hang\t%s\tsleep 300 & echo $! >gc.pid; sleep 300\nquick\t%s\texit 1\n' "$D/a" "$D/a" >"$D/list.txt"; run --timeout 2
    rc_is 75 "timeout: 上限で打ち切った写しがあれば75で終わる"
    printf "%s\n" "$OUT" | grep -qx "hang 打ち切り [0-9]*s" && printf "%s\n" "$OUT" | grep -qx "quick rc=1 [0-9]*s"; check "timeout: 打ち切った写しを出す" $?
    grep -q "^hang 終了 [0-9:]* 打ち切り " "$D/logs/progress.txt"; check "timeout: 進み具合に打ち切りを書く" $?
    local gc i
    gc=$(cat "$D/a/gc.pid")
    for i in 1 2 3 4 5 6 7 8 9 10; do kill -0 "$gc" 2>/dev/null || break; sleep 0.5; done
    ! kill -0 "$gc" 2>/dev/null; check "timeout: 孫のプロセスまで止める" $?
}

case_parallel() {
    fresh parallel
    local start
    start=$(date +%s)
    printf 'p1\t%s\tsleep 2\np2\t%s\tsleep 2\np3\t%s\tsleep 2\n' "$D/a" "$D/a" "$D/a" >"$D/list.txt"; run --timeout 20
    [ "$RC" -eq 0 ] && [ $(( $(date +%s) - start )) -lt 5 ]; check "parallel: 写しを同時に流す" $?
}

case_too_many() {
    fresh too_many
    local i
    for i in 1 2 3 4 5 6 7 8 9 10 11; do printf 'c%s\t%s\ttouch ran%s\n' "$i" "$D/a" "$i"; done >"$D/list.txt"; run
    [ "$RC" -eq 64 ] && [ -z "$(ls "$D/a")" ] && grep -q "10個まで" "$D/err.txt"; check "too_many: 写しが11個なら64で終わり、何も流さない" $?
}

case_bad_timeout() {
    fresh bad_timeout
    printf 'one\t%s\ttrue\n' "$D/a" >"$D/list.txt"; run --timeout 541
    rc_is 64 "bad_timeout: 上限が540秒を超えれば64で終わる"
    printf 'one\t%s\ttrue\n' "$D/a" >"$D/list.txt"; run --timeout 0
    rc_is 64 "bad_timeout: 上限が0秒なら64で終わる"
}

case_bad_list() {
    fresh bad_list
    printf 'one only-two-fields\n' >"$D/list.txt"; run
    rc_is 64 "bad_list: タブで3つに分かれない行があれば64で終わる"
    printf 'one\t%s\ttrue\none\t%s\ttrue\n' "$D/a" "$D/a" >"$D/list.txt"; run
    rc_is 64 "bad_list: 名前が重なれば64で終わる"
    printf 'one\t%s\ttrue\n' "$D/missing" >"$D/list.txt"; run
    rc_is 64 "bad_list: 写しのフォルダが無ければ64で終わる"
    printf '# comment\n\n' >"$D/list.txt"; run
    rc_is 64 "bad_list: 写しが1つも無ければ64で終わる"
}

ALL="finish stdin timeout parallel too_many bad_timeout bad_list"
CASES=${KP_TEST_CASE:-$ALL}
for c in $CASES; do
    case " $ALL " in
    *" $c "*) ;;
    *) echo "知らない場合の名前: $c(場合: $ALL)" >&2; exit 2 ;;
    esac
done
for c in $CASES; do "case_$c"; done

echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
