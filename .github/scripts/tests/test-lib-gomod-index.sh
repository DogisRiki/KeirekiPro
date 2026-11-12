#!/usr/bin/env bash
# =====================================================================
# lib-gomod-index.sh の自動テスト(dependency-review CI から実行)
#
# curl をスタブし、index.golang.org の索引のページを返す。外部への問い合わせを行わないため、
# 実行にネットワークを必要としない。時刻は NOW_EPOCH で固定する。
# 環境変数 KP_TEST_CASE に場合の名前を入れると、その場合だけを流す。空ならすべてを流す。
# =====================================================================
set -uo pipefail

LIB="$(cd "$(dirname "$0")/.." && pwd)/lib-gomod-index.sh"
WORK=$(mktemp -d) || exit 1
[ -n "$WORK" ] && [ -d "$WORK" ] || exit 1
trap 'rm -rf "$WORK"' EXIT
FAILED=0
CASE="${KP_TEST_CASE:-}"
RAN=0

# 判定の基準時刻。2026-01-10T00:00:00Z
NOW=1768003200
# 索引を読み始める時刻。基準時刻の73時間前
SINCE="2026-01-06T23:00:00Z"
GOMOD_INDEX_BASE="https://index.invalid"
mkdir -p "$WORK/bin" "$WORK/pages"

# --- curl のスタブ ---------------------------------------------------------------
# URL の since の値を名前にしたファイル($STUB_PAGES/<since>)を、-o の先に写す。
# ファイルが無ければ、curl -f が HTTP の誤りの応答を受けたときと同じく 22 で終わる。
# 呼ばれた URL は $STUB_CALLS に1行ずつ記録し、引数のすべては $STUB_ARGS に1行ずつ記録する。
# $STUB_ACTIVE にフォルダを渡すと、問い合わせのたびに 0.3 秒待ち、待つ前に、同時に動いている
# 問い合わせの数を $STUB_ACTIVE.max に1行ずつ記録する
cat >"$WORK/bin/curl" <<'STUB'
#!/usr/bin/env bash
url=""
out=""
prev=""
for a in "$@"; do
    [ "$prev" = "-o" ] && out="$a"
    case "$a" in http*) url="$a" ;; esac
    prev="$a"
done
echo "$url" >>"${STUB_CALLS:?}"
echo "$*" >>"${STUB_ARGS:?}"
if [ -n "${STUB_ACTIVE:-}" ]; then
    : >"$STUB_ACTIVE/$$"
    find "$STUB_ACTIVE" -type f | wc -l >>"$STUB_ACTIVE.max"
    sleep 0.3
    rm -f "$STUB_ACTIVE/$$"
fi
since="${url#*since=}"
since="${since%%&*}"
if [ ! -f "${STUB_PAGES:?}/${since}" ]; then
    echo "curl: (22) The requested URL returned error: 500" >&2
    exit 22
fi
cat "${STUB_PAGES}/${since}" >"${out:?}"
STUB
chmod +x "$WORK/bin/curl"

fail() {
    echo "FAIL: $1"
    FAILED=1
}

want() {
    if [ -z "$CASE" ] || [ "$CASE" = "$1" ]; then
        RAN=$((RAN + 1))
        echo "--- $1 ---"
        rm -f "$WORK/pages/"*
        : >"$WORK/calls.log"
        : >"$WORK/args.log"
        : >"$WORK/wanted.tsv"
        SEG_HOURS=73
        MAX_PAGES=1000
        PARALLEL=8
        ACTIVE=""
        return 0
    fi
    return 1
}

# 使い方: entry <モジュール> <版> <取り込まれた時刻>。索引の1行
entry() {
    printf '{"Path":"%s","Version":"%s","Timestamp":"%s"}\n' "$1" "$2" "$3"
}

# 使い方: page <since の値>。標準入力をそのページにする
page() {
    cat >"$WORK/pages/$1"
}

# 使い方: wanted <モジュール> <版>。照らす組を1つ足す
wanted() {
    printf '%s\t%s\n' "$1" "$2" >>"$WORK/wanted.tsv"
}

# 部品を source した別のシェルで gomod_index_ages を呼ぶ。
# 区間の長さ(SEG_HOURS)は、場合ごとに73時間に戻す。73時間なら区間は1つで、ページを順に読む動きを確かめられる
# 同時に読む本数(PARALLEL)は、場合ごとに既定の8本に戻す
run() {
    (
        export PATH="$WORK/bin:$PATH" STUB_CALLS="$WORK/calls.log" STUB_PAGES="$WORK/pages"
        export STUB_ARGS="$WORK/args.log" STUB_ACTIVE="$ACTIVE"
        export NOW_EPOCH="$NOW" GOMOD_INDEX_BASE
        export GOMOD_INDEX_SEGMENT_HOURS="$SEG_HOURS" GOMOD_INDEX_MAX_PAGES="$MAX_PAGES"
        export GOMOD_INDEX_PARALLEL="$PARALLEL"
        # shellcheck source=/dev/null
        . "$LIB"
        gomod_index_ages "$WORK/wanted.tsv" "$WORK/out.tsv"
    ) >"$WORK/stdout.log" 2>"$WORK/err.log"
    RC=$?
}

check_rc() {
    if [ "$RC" -eq "$1" ]; then
        echo "PASS: $2"
    else
        fail "$2 (終了コード: 期待 $1 / 実際 $RC)"
        sed 's/^/    stderr: /' "$WORK/err.log"
    fi
}

# 使い方: check_out <期待の内容> <説明>。出力のファイルの中身を比べる
check_out() {
    local got
    got=$(cat "$WORK/out.tsv" 2>/dev/null)
    if [ "$got" = "$1" ]; then
        echo "PASS: $2"
    else
        fail "$2"
        printf '    期待: %s\n    実際: %s\n' "$1" "$got"
    fi
}

check_calls() {
    local n
    n=$(wc -l <"$WORK/calls.log" | tr -d ' ')
    if [ "$n" -eq "$1" ]; then
        echo "PASS: $2"
    else
        fail "$2 (問い合わせの回数: 期待 $1 / 実際 $n)"
        sed 's/^/    call: /' "$WORK/calls.log"
    fi
}

check_call_line() {
    local got
    got=$(sed -n "${1}p" "$WORK/calls.log")
    if [ "$got" = "$2" ]; then
        echo "PASS: $3"
    else
        fail "$3"
        printf '    期待: %s\n    実際: %s\n' "$2" "$got"
    fi
}

check_err() {
    if grep -qF -- "$1" "$WORK/err.log"; then
        echo "PASS: $2"
    else
        fail "$2 (標準エラーに「$1」がありません)"
        sed 's/^/    stderr: /' "$WORK/err.log"
    fi
}

TAB=$'\t'

if want young; then
    # 基準時刻の71時間59分前に取り込まれた組
    entry example.com/young v1.2.0 2026-01-07T00:01:00Z | page "$SINCE"
    wanted example.com/young 1.2.0
    run
    check_rc 0 "72時間より新しい組を新しいと返す: 成功で終わる"
    check_out "example.com/young${TAB}1.2.0${TAB}new${TAB}1767744060" "72時間より新しい組を新しいと返す: new と取り込まれた時刻を返す"
fi

if want old; then
    {
        # 基準時刻の72時間30分前に取り込まれた組(読み始めの1時間の幅の中)
        entry example.com/margin v2.0.0 2026-01-06T23:30:00Z
        # 基準時刻の72時間ちょうど前に取り込まれた組
        entry example.com/exact v3.0.0 2026-01-07T00:00:00Z
    } | page "$SINCE"
    wanted example.com/margin 2.0.0
    wanted example.com/exact 3.0.0
    # 索引の読んだ範囲に無い組は、読み始めより前に取り込まれている
    wanted example.com/before 1.0.0
    run
    check_rc 0 "72時間より古い組を古いと返す: 成功で終わる"
    check_out "example.com/margin${TAB}2.0.0${TAB}old${TAB}1767742200
example.com/exact${TAB}3.0.0${TAB}old${TAB}1767744000
example.com/before${TAB}1.0.0${TAB}old${TAB}" "72時間より古い組を古いと返す: 読んだ範囲の古い組は時刻を付け、範囲に無い組は時刻を空にして old を返す"
fi

if want read_once; then
    # 1ページ目は2000件ちょうどなので、最後の行の時刻から2ページ目を読む
    {
        entry example.com/a v1.0.0 2026-01-06T23:30:00Z
        awk 'BEGIN { for (i = 1; i <= 1998; i++) printf "{\"Path\":\"example.com/filler%d\",\"Version\":\"v0.0.1\",\"Timestamp\":\"2026-01-07T02:00:00Z\"}\n", i }'
        entry example.com/last v1.0.0 2026-01-08T00:00:00.123456Z
    } | page "$SINCE"
    {
        entry example.com/last v1.0.0 2026-01-08T00:00:00.123456Z
        entry example.com/b v2.0.0 2026-01-09T00:00:00Z
    } | page "2026-01-08T00:00:00.123456Z"
    wanted example.com/a 1.0.0
    wanted example.com/b 2.0.0
    wanted example.com/c 3.0.0
    run
    check_rc 0 "索引を1度だけ読む: 成功で終わる"
    check_calls 2 "索引を1度だけ読む: 3つの組に対して、ページの数の2回だけ問い合わせる"
    check_call_line 1 "${GOMOD_INDEX_BASE}/index?since=${SINCE}&limit=2000" "索引を1度だけ読む: 基準時刻の73時間前から読み始める"
    check_call_line 2 "${GOMOD_INDEX_BASE}/index?since=2026-01-08T00:00:00.123456Z&limit=2000" "索引を1度だけ読む: 2ページ目は、1ページ目の最後の行の時刻から読む"
    check_out "example.com/a${TAB}1.0.0${TAB}old${TAB}1767742200
example.com/b${TAB}2.0.0${TAB}new${TAB}1767916800
example.com/c${TAB}3.0.0${TAB}old${TAB}" "索引を1度だけ読む: 2つのページの組を、照らす組の順に返す"
fi

if want stop_at_now; then
    # 2000件ちょうどでも、最後の行が基準時刻より後なら次のページを読まない
    {
        awk 'BEGIN { for (i = 1; i <= 1999; i++) printf "{\"Path\":\"example.com/filler%d\",\"Version\":\"v0.0.1\",\"Timestamp\":\"2026-01-08T00:00:00Z\"}\n", i }'
        entry example.com/future v1.0.0 2026-01-10T00:00:01Z
    } | page "$SINCE"
    wanted example.com/future 1.0.0
    run
    check_rc 0 "最後の行が基準時刻より後なら読み終える: 成功で終わる"
    check_calls 1 "最後の行が基準時刻より後なら読み終える: 1回だけ問い合わせる"
    check_out "example.com/future${TAB}1.0.0${TAB}new${TAB}1768003201" "最後の行が基準時刻より後なら読み終える: 基準時刻より後に取り込まれた組を new と返す"
fi

if want version_form; then
    {
        entry example.com/plain v1.0.0 2026-01-08T00:00:00Z
        entry example.com/pseudo v0.0.0-20260108000000-abcdef123456 2026-01-08T00:00:00Z
        entry example.com/incompat v2.0.0+incompatible 2026-01-08T00:00:00Z
    } | page "$SINCE"
    wanted example.com/plain v1.0.0
    wanted example.com/pseudo 0.0.0-20260108000000-abcdef123456
    wanted example.com/incompat 2.0.0+incompatible
    run
    check_rc 0 "版の先頭の v の有無によらず照らす: 成功で終わる"
    check_out "example.com/plain${TAB}v1.0.0${TAB}new${TAB}1767830400
example.com/pseudo${TAB}0.0.0-20260108000000-abcdef123456${TAB}new${TAB}1767830400
example.com/incompat${TAB}2.0.0+incompatible${TAB}new${TAB}1767830400" "版の先頭の v の有無によらず照らす: 照らす組の版の書き方のまま返す"
fi

if want case_fold; then
    # 大文字と小文字だけが違うモジュールは、新しい方の時刻を使う
    {
        entry github.com/Example/Tool v1.0.0 2026-01-06T23:10:00Z
        entry github.com/example/tool v1.0.0 2026-01-08T00:00:00Z
    } | page "$SINCE"
    wanted github.com/EXAMPLE/tool 1.0.0
    run
    check_rc 0 "モジュールの名前の大文字と小文字を区別せずに照らす: 成功で終わる"
    check_out "github.com/EXAMPLE/tool${TAB}1.0.0${TAB}new${TAB}1767830400" "モジュールの名前の大文字と小文字を区別せずに照らす: 当たった組のうち新しい方の時刻を返す"
fi

if want fraction; then
    # 秒の端数があれば、取り込まれた時刻を次の秒に切り上げる。72時間の数え始めを早めないため
    entry example.com/frac v1.0.0 2026-01-07T00:00:00.000001Z | page "$SINCE"
    wanted example.com/frac 1.0.0
    run
    check_rc 0 "秒の端数を切り上げる: 成功で終わる"
    check_out "example.com/frac${TAB}1.0.0${TAB}new${TAB}1767744001" "秒の端数を切り上げる: 72時間ちょうど前の端数のある組を new と返す"
fi

if want fetch_fail; then
    # ページのファイルを置かないので、curl が失敗する
    wanted example.com/x 1.0.0
    run
    check_rc 1 "索引を読めなければ失敗で終わる: 失敗で終わる"
    check_err "index.golang.org の索引を読めませんでした" "索引を読めなければ失敗で終わる: 理由を標準エラーに出す"
fi

if want bad_line; then
    {
        entry example.com/x v1.0.0 2026-01-08T00:00:00Z
        printf '{"Path":"example.com/y","Version":"v1.0.0"}\n'
    } | page "$SINCE"
    wanted example.com/x 1.0.0
    run
    check_rc 1 "形の違う行があれば失敗で終わる: 失敗で終わる"
    check_err "index.golang.org の索引の形が違います" "形の違う行があれば失敗で終わる: 理由を標準エラーに出す"

    printf '<html>busy</html>\n' | page "$SINCE"
    run
    check_rc 1 "JSON でない応答なら失敗で終わる: 失敗で終わる"
fi

if want stuck; then
    # 2000件すべてが読み始めと同じ時刻だと、次のページの since が進まない
    awk 'BEGIN { for (i = 1; i <= 2000; i++) printf "{\"Path\":\"example.com/filler%d\",\"Version\":\"v0.0.1\",\"Timestamp\":\"2026-01-06T23:00:00Z\"}\n", i }' |
        page "$SINCE"
    wanted example.com/x 1.0.0
    run
    check_rc 1 "次のページの読み始めが進まなければ失敗で終わる: 失敗で終わる"
    check_calls 1 "次のページの読み始めが進まなければ失敗で終わる: 同じページを読み直さない"
    check_err "読み始めの時刻が進みません" "次のページの読み始めが進まなければ失敗で終わる: 理由を標準エラーに出す"
fi

if want no_wanted; then
    run
    check_rc 0 "照らす組が無ければ成功で終わる: 成功で終わる"
    check_calls 0 "照らす組が無ければ索引を読まない"
    check_out "" "照らす組が無ければ何も出さない"
fi

if want segments; then
    # 24時間ずつの区間に分けると、読み始めは 01-06T23:00、01-07T23:00、01-08T23:00、01-09T23:00 の4つになる
    SEG_HOURS=24
    {
        entry example.com/a v1.0.0 2026-01-06T23:30:00Z
        awk 'BEGIN { for (i = 1; i <= 1998; i++) printf "{\"Path\":\"example.com/filler%d\",\"Version\":\"v0.0.1\",\"Timestamp\":\"2026-01-07T12:00:00Z\"}\n", i }'
        # 区間の終わり(01-07T23:00)を過ぎた行。2000件ちょうどでも、この区間の次のページは読まない
        entry example.com/b v2.0.0 2026-01-08T01:00:00Z
    } | page "$SINCE"
    entry example.com/b v2.0.0 2026-01-08T01:00:00Z | page "2026-01-07T23:00:00Z"
    : | page "2026-01-08T23:00:00Z"
    entry example.com/c v3.0.0 2026-01-09T23:30:00Z | page "2026-01-09T23:00:00Z"
    wanted example.com/a 1.0.0
    wanted example.com/b 2.0.0
    wanted example.com/c 3.0.0
    run
    check_rc 0 "区間に分けて読む: 成功で終わる"
    check_calls 4 "区間に分けて読む: 4つの区間を1ページずつ読む"
    got=$(sed 's/.*since=//; s/&.*//' "$WORK/calls.log" | sort | tr '\n' ' ')
    if [ "$got" = "2026-01-06T23:00:00Z 2026-01-07T23:00:00Z 2026-01-08T23:00:00Z 2026-01-09T23:00:00Z " ]; then
        echo "PASS: 区間に分けて読む: 区間ごとの読み始めの時刻から読む"
    else
        fail "区間に分けて読む: 区間ごとの読み始めの時刻から読む (実際: ${got})"
    fi
    check_out "example.com/a${TAB}1.0.0${TAB}old${TAB}1767742200
example.com/b${TAB}2.0.0${TAB}new${TAB}1767834000
example.com/c${TAB}3.0.0${TAB}new${TAB}1768001400" "区間に分けて読む: すべての区間の組を、照らす組の順に返す"
fi

if want segment_edge; then
    # 1つ目の区間のページが、区間の終わり(01-07T23:00)の1秒前の中の行で終わる。
    # 切り上げると区間の終わりと同じ時刻になるが、同じ1秒の中の続きの行が次のページにあるので、次のページも読む
    SEG_HOURS=24
    awk 'BEGIN { for (i = 1; i <= 1999; i++) printf "{\"Path\":\"example.com/filler%d\",\"Version\":\"v0.0.1\",\"Timestamp\":\"2026-01-07T12:00:00Z\"}\n", i }
        END { printf "{\"Path\":\"example.com/edge\",\"Version\":\"v0.0.1\",\"Timestamp\":\"2026-01-07T22:59:59.5Z\"}\n" }' </dev/null |
        page "$SINCE"
    {
        entry example.com/edge v0.0.1 2026-01-07T22:59:59.5Z
        entry example.com/young v1.0.0 2026-01-07T22:59:59.8Z
    } | page "2026-01-07T22:59:59.5Z"
    : | page "2026-01-07T23:00:00Z"
    : | page "2026-01-08T23:00:00Z"
    : | page "2026-01-09T23:00:00Z"
    wanted example.com/young 1.0.0
    run
    check_rc 0 "区間の終わりの1秒前の中の行でページが終わる: 成功で終わる"
    check_calls 5 "区間の終わりの1秒前の中の行でページが終わる: その区間の次のページも読む"
    if grep -qxF "${GOMOD_INDEX_BASE}/index?since=2026-01-07T22:59:59.5Z&limit=2000" "$WORK/calls.log"; then
        echo "PASS: 区間の終わりの1秒前の中の行でページが終わる: 最後の行の元の時刻から次のページを読む"
    else
        fail "区間の終わりの1秒前の中の行でページが終わる: 最後の行の元の時刻から次のページを読む"
        sed 's/^/    call: /' "$WORK/calls.log"
    fi
    check_out "example.com/young${TAB}1.0.0${TAB}new${TAB}1767826800" "区間の終わりの1秒前の中の行でページが終わる: 次のページの組を新しいとして返す"
fi

if want segment_fail; then
    # 3つ目の区間のページを置かないので、その区間の読み取りだけが失敗する
    SEG_HOURS=24
    entry example.com/a v1.0.0 2026-01-06T23:30:00Z | page "$SINCE"
    entry example.com/b v2.0.0 2026-01-08T01:00:00Z | page "2026-01-07T23:00:00Z"
    entry example.com/c v3.0.0 2026-01-09T23:30:00Z | page "2026-01-09T23:00:00Z"
    wanted example.com/a 1.0.0
    run
    check_rc 1 "1つの区間を読めなければ失敗で終わる: 失敗で終わる"
    check_err "索引を読めませんでした(${GOMOD_INDEX_BASE}/index?since=2026-01-08T23:00:00Z&limit=2000" "1つの区間を読めなければ失敗で終わる: 読めなかった区間の URL を標準エラーに出す"
    check_out "" "1つの区間を読めなければ失敗で終わる: 何も出さない"
fi

if want bad_segment; then
    SEG_HOURS=0
    wanted example.com/a 1.0.0
    run
    check_rc 1 "区間の長さが正の整数でなければ失敗で終わる: 失敗で終わる"
    check_calls 0 "区間の長さが正の整数でなければ失敗で終わる: 索引を読まない"
    check_err "GOMOD_INDEX_SEGMENT_HOURS=0" "区間の長さが正の整数でなければ失敗で終わる: 理由を標準エラーに出す"
fi

if want retry_args; then
    # 問い合わせが多すぎると断られたとき(429)に、待ちを倍にしながら6回まで再試行する
    entry example.com/a v1.0.0 2026-01-08T00:00:00Z | page "$SINCE"
    wanted example.com/a 1.0.0
    run
    check_rc 0 "断られたときに再試行する: 成功で終わる"
    if grep -qF -- "--retry 6 --retry-max-time 120" "$WORK/args.log"; then
        echo "PASS: 断られたときに再試行する: 6回まで、最初の問い合わせから120秒までの間、再試行するよう curl に渡す"
    else
        fail "断られたときに再試行する: 6回まで、最初の問い合わせから120秒までの間、再試行するよう curl に渡す"
        sed 's/^/    args: /' "$WORK/args.log"
    fi
fi

if want parallel_limit; then
    # 12時間ずつの区間に分けると7つの区間になる。同時に読む本数を2本にすると、
    # 2本の読み手が、1本目は1、3、5、7番目の区間を、2本目は2、4、6番目の区間を順に読む
    SEG_HOURS=12
    PARALLEL=2
    ACTIVE="$WORK/active"
    mkdir -p "$ACTIVE"
    : >"$ACTIVE.max"
    for s in 2026-01-06T23:00:00Z 2026-01-07T11:00:00Z 2026-01-07T23:00:00Z 2026-01-08T11:00:00Z \
        2026-01-08T23:00:00Z 2026-01-09T11:00:00Z; do
        : | page "$s"
    done
    entry example.com/a v1.0.0 2026-01-09T23:30:00Z | page "2026-01-09T23:00:00Z"
    wanted example.com/a 1.0.0
    run
    check_rc 0 "同時に読む本数を上限までにする: 成功で終わる"
    check_calls 7 "同時に読む本数を上限までにする: 7つの区間をすべて読む"
    most=$(sort -n "$ACTIVE.max" | tail -n 1)
    if [ -n "$most" ] && [ "$most" -le 2 ]; then
        echo "PASS: 同時に読む本数を上限までにする: 同時に動く問い合わせは2本まで"
    else
        fail "同時に読む本数を上限までにする: 同時に動く問い合わせは2本まで (実際: ${most})"
    fi
    check_out "example.com/a${TAB}1.0.0${TAB}new${TAB}1768001400" "同時に読む本数を上限までにする: 最後の区間の組を返す"
fi

if want parallel_fail; then
    # 24時間ずつの4つの区間を2本で読む。2本目の読み手が受け持つ2番目の区間のページを置かないので、
    # 2本目は失敗し、受け持ちの残りの4番目の区間を読まない
    SEG_HOURS=24
    PARALLEL=2
    entry example.com/a v1.0.0 2026-01-06T23:30:00Z | page "$SINCE"
    : | page "2026-01-08T23:00:00Z"
    entry example.com/c v3.0.0 2026-01-09T23:30:00Z | page "2026-01-09T23:00:00Z"
    wanted example.com/a 1.0.0
    run
    check_rc 1 "読み手の1本が区間を読めなければ失敗で終わる: 失敗で終わる"
    check_err "索引を読めませんでした(${GOMOD_INDEX_BASE}/index?since=2026-01-07T23:00:00Z&limit=2000" "読み手の1本が区間を読めなければ失敗で終わる: 読めなかった区間の URL を標準エラーに出す"
    if grep -qF "since=2026-01-09T23:00:00Z" "$WORK/calls.log"; then
        fail "読み手の1本が区間を読めなければ失敗で終わる: 失敗した読み手は受け持ちの残りの区間を読まない"
        sed 's/^/    call: /' "$WORK/calls.log"
    else
        echo "PASS: 読み手の1本が区間を読めなければ失敗で終わる: 失敗した読み手は受け持ちの残りの区間を読まない"
    fi
    check_out "" "読み手の1本が区間を読めなければ失敗で終わる: 何も出さない"
fi

if want bad_parallel; then
    PARALLEL=0
    wanted example.com/a 1.0.0
    run
    check_rc 1 "同時に読む本数が正の整数でなければ失敗で終わる: 失敗で終わる"
    check_calls 0 "同時に読む本数が正の整数でなければ失敗で終わる: 索引を読まない"
    check_err "GOMOD_INDEX_PARALLEL=0" "同時に読む本数が正の整数でなければ失敗で終わる: 理由を標準エラーに出す"
fi

if want page_cap; then
    # 1ページだけ読んでよいとき、2000件ちょうどで最後の行が判定の時刻より前なら、読み終えられない
    MAX_PAGES=1
    awk 'BEGIN { for (i = 1; i <= 2000; i++) printf "{\"Path\":\"example.com/filler%d\",\"Version\":\"v0.0.1\",\"Timestamp\":\"2026-01-07T12:00:00Z\"}\n", i }' |
        page "$SINCE"
    wanted example.com/x 1.0.0
    run
    check_rc 1 "ページの上限を超えたら失敗で終わる: 失敗で終わる"
    check_calls 1 "ページの上限を超えたら失敗で終わる: 上限の1ページだけを読む"
    check_err "索引を 1 ページ読んでも、区間の終わりの時刻に届きませんでした" "ページの上限を超えたら失敗で終わる: 理由を標準エラーに出す"
    check_out "" "ページの上限を超えたら失敗で終わる: 何も出さない"
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
