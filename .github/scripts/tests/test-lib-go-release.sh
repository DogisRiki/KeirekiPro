#!/usr/bin/env bash
# =====================================================================
# lib-go-release.sh の自動テスト
#
# ライブラリを source し、関数ごとに入力と出力を確かめる。
# go_release_published は、PATH の先頭に置いた偽の curl に問い合わせる。偽の curl は、
# FAKE_MAP の「取り先<TAB>HTTP の状態<TAB>応答の見出しのファイル」の行で応答を返し、
# 呼ばれた取り先を FAKE_LOG に1行ずつ書く。
#
# 環境変数 KP_TEST_CASE に場合の名前を入れると、その場合だけを流す。
# 外部への問い合わせを行わないため、実行にネットワークを必要としない。
# =====================================================================
set -uo pipefail

LIB="$(cd "$(dirname "$0")/.." && pwd)/lib-go-release.sh"
WORK=$(mktemp -d) || exit 1
[ -n "$WORK" ] && [ -d "$WORK" ] || exit 1
trap 'rm -rf "$WORK"' EXIT
FAILED=0
CASE="${KP_TEST_CASE:-}"
RAN=0

pass() { echo "PASS: $1"; }
fail() {
    echo "FAIL: $1 ($2)"
    FAILED=1
}
want() {
    if [ -z "$CASE" ] || [ "$CASE" = "$1" ]; then
        RAN=$((RAN + 1))
        return 0
    fi
    return 1
}
# 使い方: same <名前> <期待> <実際>
same() {
    if [ "$2" = "$3" ]; then pass "$1"; else fail "$1" "期待: $(printf '%q' "$2") 実際: $(printf '%q' "$3")"; fi
}

mkdir -p "$WORK/bin" "$WORK/tmp"
cat >"$WORK/bin/curl" <<'SH'
#!/usr/bin/env bash
out="" hdr="" fmt="" url="" head=0 follow=0
while [ "$#" -gt 0 ]; do
    case "$1" in
    -o) out="$2"; shift 2 ;;
    -D) hdr="$2"; shift 2 ;;
    -w) fmt="$2"; shift 2 ;;
    --max-time | --retry) shift 2 ;;
    -I) head=1; shift ;;
    -L) follow=1; shift ;;
    -*) shift ;;
    *) url="$1"; shift ;;
    esac
done
if [ "$head" -ne 1 ] || [ "$follow" -ne 1 ] || [ -z "$hdr" ]; then
    echo "偽の curl: -I と -L と -D を付けずに呼ばれました" >&2
    exit 9
fi
printf '%s\n' "$url" >>"$FAKE_LOG"
row=$(awk -F '\t' -v k="$url" '$1 == k { print; exit }' "$FAKE_MAP")
if [ -z "$row" ]; then
    [ -n "$fmt" ] && printf '000'
    echo "curl: (7) Failed to connect to go.test port 443" >&2
    exit 7
fi
st=$(printf '%s\n' "$row" | cut -f2)
cat "$(printf '%s\n' "$row" | cut -f3)" >"$hdr"
[ -n "$out" ] && : >"$out"
[ -n "$fmt" ] && printf '%s' "$st"
exit 0
SH
chmod +x "$WORK/bin/curl"
export PATH="$WORK/bin:$PATH"
export GO_DL_BASE="https://go.test/dl"
# go_release_published が作る一時のフォルダを、このフォルダの中に作らせ、消し忘れを数える
export TMPDIR="$WORK/tmp"
FAKE_MAP="$WORK/map.tsv"
FAKE_LOG="$WORK/log.txt"
export FAKE_MAP FAKE_LOG

# shellcheck source=.github/scripts/lib-go-release.sh
. "$LIB"

# 使い方: reset。偽の curl の応答と記録を空にする
reset() {
    : >"$FAKE_MAP"
    : >"$FAKE_LOG"
}
# 使い方: dl <版> <平台> <HTTP の状態> <最後の応答の Last-Modified(空なら付けない)>。
# go.dev から dl.google.com への転送を挟み、転送の応答にも公開日時と違う Last-Modified を付ける
# (最後の応答の見出しを読むかを確かめる)
dl() {
    local f lm=""
    f="$WORK/h$(wc -l <"$FAKE_MAP" | tr -d ' ').txt"
    [ -n "$4" ] && lm="Last-Modified: $4"$'\r\n'
    printf 'HTTP/2 302\r\nlocation: https://dl.google.com/go/go%s.%s.tar.gz\r\nlast-modified: Mon, 01 Jan 2024 00:00:00 GMT\r\n\r\nHTTP/2 %s\r\ncontent-type: application/x-gzip\r\n%s\r\n' "$1" "$2" "$3" "$lm" >"$f"
    printf '%s\t%s\t%s\n' "https://go.test/dl/go$1.$2.tar.gz" "$3" "$f" >>"$FAKE_MAP"
}

# --- Go の版を読むファイル ------------------------------------------------------
if want is_target; then
    got=""
    for p in go.mod backend/go.mod Dockerfile docker/backend-go/Dockerfile Dockerfile.dev x/app.Dockerfile x/app.dockerfile \
        go.sum backend/go.mod.bak Dockerfile-old README.md docker/Dockerfiles/x; do
        if go_release_is_target "$p"; then got="$got $p:y"; else got="$got $p:n"; fi
    done
    same "go.mod と Dockerfile の名前だけを読む" \
        " go.mod:y backend/go.mod:y Dockerfile:y docker/backend-go/Dockerfile:y Dockerfile.dev:y x/app.Dockerfile:y x/app.dockerfile:y go.sum:n backend/go.mod.bak:n Dockerfile-old:n README.md:n docker/Dockerfiles/x:n" "$got"
fi

# --- go.mod の版 ----------------------------------------------------------------
if want gomod_versions; then
    got=$(printf 'module x\r\n\r\ngo 1.27 // 2つの数\r\n\r\ntoolchain go1.27.4\r\n' | go_release_versions_of go.mod)
    same "go.mod の go の行の2つの数を .0 で読み、toolchain の行の go を外す(CRLF とコメントを除く)" $'1.27.0\n1.27.4' "$got"
    got=$(printf 'module x\n\ngo 1.28rc1\n\ntoolchain go1.28beta2\n' | go_release_versions_of backend/go.mod)
    same "rc と beta の版を読み、パスの最後の部分で go.mod と見分ける" $'1.28rc1\n1.28beta2' "$got"
    got=$(printf 'module x\n\ngo 1\n\ntoolchain default\n\nrequire golang.org/x/net v0.1.0 // go 1.30\n' | go_release_versions_of go.mod)
    same "版を読めない go の行と toolchain の行は、頭に ? を付けて書き方を出す" $'?go 1\n?toolchain default' "$got"
fi

# --- Dockerfile の版 ------------------------------------------------------------
if want dockerfile_versions; then
    got=$(printf '%s\r\n' \
        'FROM golang:1.27.4-trixie@sha256:b54b0c5a92c98f60fcbfa81eac2a40fc19e7b3fa7719bccae10ff6111d22524a AS build' \
        "from --platform=\$BUILDPLATFORM docker.io/library/golang:1.27.3 AS b2" \
        'FROM index.docker.io/golang:1.27.2-alpine' \
        'FROM node:22-alpine' \
        'FROM localhost:5000/golang:1.9.9' \
        'FROM ghcr.io/x/golang:1.9.8' \
        '# FROM golang:1.0.0' \
        'RUN echo FROM golang:1.0.1' | go_release_versions_of Dockerfile)
    same "golang のイメージのタグの頭の版だけを読み、ほかのイメージと行を読まない" $'1.27.4\n1.27.3\n1.27.2' "$got"
    got=$(printf '%s\n' 'FROM golang AS a' 'FROM golang:1.27-trixie' 'FROM golang@sha256:aa' 'FROM golang:latest' | go_release_versions_of x.Dockerfile)
    same "版の決まらない golang のイメージは、頭に ? を付けて書き方を出す" $'?golang\n?golang:1.27-trixie\n?golang@sha256:aa\n?golang:latest' "$got"
fi

# --- HTTP の日時 ----------------------------------------------------------------
if want http_epoch; then
    same "HTTP の日時を秒にする" 1794329328 "$(go_release_http_epoch 'Tue, 10 Nov 2026 16:48:48 GMT')"
    same "1桁の日を読む" 1790812800 "$(go_release_http_epoch 'Thu, 1 Oct 2026 00:00:00 GMT')"
    bad=""
    for s in 'Tue, 10 Foo 2026 16:48:48 GMT' 'Tue, 10 Nov 2026 16:48 GMT' '' 'Tue, 10 ov 2026 16:48:48 GMT' 'Tue, 10 anF 2026 16:48:48 GMT''Tue, x Nov 2026 16:48:48 GMT'; do
        if out=$(go_release_http_epoch "$s"); then bad="$bad [$s]=$out"; fi
    done
    same "形の違う日時は 1 を返す" "" "$bad"
fi

# --- 公開日時 -------------------------------------------------------------------
if want published_newer; then
    reset
    dl 1.27.4 linux-amd64 200 'Tue, 10 Nov 2026 16:48:48 GMT'
    dl 1.27.4 linux-arm64 200 'Tue, 10 Nov 2026 16:50:00 GMT'
    out=$(go_release_published 1.27.4 2>"$WORK/err")
    rc=$?
    same "2つの配布物のうち新しい方の、転送のあとの Last-Modified を出す" "0 1794329400" "$rc $out"
    same "amd64 と arm64 の配布物を問い合わせる" $'https://go.test/dl/go1.27.4.linux-amd64.tar.gz\nhttps://go.test/dl/go1.27.4.linux-arm64.tar.gz' "$(cat "$FAKE_LOG")"
    same "一時のフォルダを消す" "" "$(ls -A "$WORK/tmp")"
fi

# 使い方: stops <名前> <版> <理由に含む文>。go_release_published が 1 を返し、理由を出すかを確かめる
stops() {
    local out rc
    out=$(go_release_published "$2" 2>"$WORK/err")
    rc=$?
    if [ "$rc" -eq 1 ] && [ -z "$out" ] && grep -qF -- "$3" "$WORK/err"; then
        pass "$1"
    else
        fail "$1" "終了コード: $rc 標準出力: $out 標準エラー: $(cat "$WORK/err")"
    fi
    same "$1: 一時のフォルダを消す" "" "$(ls -A "$WORK/tmp")"
}

if want published_not_found; then
    reset
    dl 1.27.98 linux-amd64 404 ''
    stops "配布元に無い版" 1.27.98 "配布元にこの版が無い(https://go.test/dl/go1.27.98.linux-amd64.tar.gz が HTTP 404 を返した)"
    reset
    dl 1.27.5 linux-amd64 200 'Tue, 10 Nov 2026 16:48:48 GMT'
    dl 1.27.5 linux-arm64 410 ''
    stops "arm64 の配布物だけが無い版" 1.27.5 "配布元にこの版が無い(https://go.test/dl/go1.27.5.linux-arm64.tar.gz が HTTP 410 を返した)"
fi

if want published_fetch_fail; then
    reset
    stops "配布元につながらない" 1.27.4 "配布元に問い合わせられなかった(https://go.test/dl/go1.27.4.linux-amd64.tar.gz: HTTP 000 curl: (7) Failed to connect to go.test port 443)"
    reset
    dl 1.27.4 linux-amd64 502 ''
    stops "配布元がエラーを返す" 1.27.4 "配布元に問い合わせられなかった(https://go.test/dl/go1.27.4.linux-amd64.tar.gz: HTTP 502)"
    if grep -qF 'HTTP 502 ' "$WORK/err"; then fail "エラーの文の後ろに空白を付けない" "$(cat "$WORK/err")"; else pass "エラーの文の後ろに空白を付けない"; fi
fi

if want published_bad_date; then
    reset
    dl 1.27.4 linux-amd64 200 ''
    stops "Last-Modified が無い" 1.27.4 "配布元の応答の公開日時を読めなかった(https://go.test/dl/go1.27.4.linux-amd64.tar.gz の Last-Modified: 無し)"
    reset
    dl 1.27.4 linux-amd64 200 'yesterday'
    stops "Last-Modified の形が違う" 1.27.4 "の Last-Modified: yesterday)"
fi

if [ "$RAN" -eq 0 ]; then
    echo "FAIL: 場合「${CASE}」はありません"
    exit 1
fi
if [ "$FAILED" -ne 0 ]; then
    echo "失敗したテストがあります"
    exit 1
fi
echo "すべてのテストが通りました"
