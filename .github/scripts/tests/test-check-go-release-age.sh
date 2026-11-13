#!/usr/bin/env bash
# =====================================================================
# check-go-release-age.sh の自動テスト(dependency-review の cooldown から実行)
#
# 一時のフォルダに、分かれ目のコミットと head のブランチを持つリモートを作り、
# head のブランチを履歴の深さ1で取った写しの中で検査を流す。PATH の先頭に偽の gh と
# curl を置き、比較の API の応答と Go の配布元の応答(転送のあとの最後の応答の見出し)を
# 場合ごとに返す。偽の gh と curl は、呼ばれた取り先を記録する。記録で、配布元に
# 問い合わせたかを確かめる。
#
# 環境変数 KP_TEST_CASE に場合の名前を入れると、その場合だけを流す。
# 外部への問い合わせを行わないため、実行にネットワークを必要としない。
# =====================================================================
set -uo pipefail

SCRIPT="$(cd "$(dirname "$0")/.." && pwd)/check-go-release-age.sh"
WORK=$(mktemp -d) || exit 1
[ -n "$WORK" ] && [ -d "$WORK" ] || exit 1
trap 'rm -rf "$WORK"' EXIT
FAILED=0
CASE="${KP_TEST_CASE:-}"
N=0

pass() { echo "PASS: $1"; }
fail() {
    echo "FAIL: $1 ($2)"
    FAILED=1
}

RAN=0
want() {
    if [ -z "$CASE" ] || [ "$CASE" = "$1" ]; then
        RAN=$((RAN + 1))
        return 0
    fi
    return 1
}

# --- 偽の gh と curl --------------------------------------------------------
# どちらも、FAKE_MAP の「取り先<TAB>HTTP の状態<TAB>応答のファイル」の行で応答を返し、
# 呼ばれた取り先を FAKE_LOG に1行ずつ書く。
# gh は、行の無い取り先に 404 を返す。応答のファイルは本文である。
# curl は、行の無い取り先に、つながらなかったときの形(状態 000、終了コード 7)を返す。
# 応答のファイルは、転送を含む応答の見出しで、-D で渡したファイルに書く。

mkdir -p "$WORK/bin"
cat >"$WORK/bin/gh" <<'SH'
#!/usr/bin/env bash
[ "${1:-}" = api ] || { echo "偽の gh: 知らない呼び方です: $*" >&2; exit 9; }
key="gh $2"
printf '%s\n' "$key" >>"$FAKE_LOG"
row=$(awk -F '\t' -v k="$key" '$1 == k { print; exit }' "$FAKE_MAP")
if [ -z "$row" ]; then
    echo '{"message":"Not Found"}'
    echo "gh: Not Found (HTTP 404)" >&2
    exit 1
fi
st=$(printf '%s\n' "$row" | cut -f2)
cat "$(printf '%s\n' "$row" | cut -f3)"
if [ "$st" -ge 400 ]; then
    echo "gh: Server Error (HTTP ${st})" >&2
    exit 1
fi
SH
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
key="curl $url"
printf '%s\n' "$key" >>"$FAKE_LOG"
row=$(awk -F '\t' -v k="$key" '$1 == k { print; exit }' "$FAKE_MAP")
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
chmod +x "$WORK/bin/gh" "$WORK/bin/curl"

export PATH="$WORK/bin:$PATH"
export GO_DL_BASE="https://go.test/dl"
export FAKE_MAP FAKE_LOG
# git の設定は、この PC の設定を読まず、コミットの名前とメールを環境変数で渡す
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.test
export GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.test

D1="sha256:b54b0c5a92c98f60fcbfa81eac2a40fc19e7b3fa7719bccae10ff6111d22524a"
# 2026-11-04T00:00:00Z
NOW=1793750400
# 2026-11-06T01:00:00Z。2026-11-03T00:00:30Z に公開した版が通る時刻のあと
LATER=1793926800
YOUNG="Tue, 03 Nov 2026 00:00:00 GMT"
YOUNG2="Tue, 03 Nov 2026 00:00:30 GMT"
OLD="Thu, 01 Oct 2026 00:00:00 GMT"

# 使い方: fx <gh|curl> <取り先> <HTTP の状態> <応答のファイルの中身>
fx() {
    local f
    f="$WORK/fx$N-$(wc -l <"$FAKE_MAP" | tr -d ' ').txt"
    printf '%s\n' "$4" >"$f"
    printf '%s %s\t%s\t%s\n' "$1" "$2" "$3" "$f" >>"$FAKE_MAP"
}

# 使い方: dl <版> <amd64 の Last-Modified> [<arm64 の Last-Modified>]。
# 配布元の2つの配布物の応答を足す。go.dev から dl.google.com への転送を挟み、
# 転送の応答にも、公開日時と違う Last-Modified を付ける(最後の応答の見出しを読むかを確かめる)
dl() {
    local p lm
    for p in linux-amd64 linux-arm64; do
        lm="$2"
        [ "$p" = linux-arm64 ] && lm="${3:-$2}"
        fx curl "https://go.test/dl/go$1.$p.tar.gz" 200 "$(printf 'HTTP/2 302\r\nlocation: https://dl.google.com/go/go%s.%s.tar.gz\r\nlast-modified: Mon, 01 Jan 2024 00:00:00 GMT\r\n\r\nHTTP/2 200\r\ncontent-type: application/x-gzip\r\nLast-Modified: %s\r\n\r' "$1" "$p" "$lm")"
    done
}

# 使い方: dl_status <版> <amd64 の状態> <arm64 の状態>。配布元の2つの配布物に、見出しの無い応答を足す
dl_status() {
    fx curl "https://go.test/dl/go$1.linux-amd64.tar.gz" "$2" "$(printf 'HTTP/2 %s\r\n\r' "$2")"
    fx curl "https://go.test/dl/go$1.linux-arm64.tar.gz" "$3" "$(printf 'HTTP/2 %s\r\n\r' "$3")"
}

# --- リモートの作り方 -------------------------------------------------------
# 作業のリポジトリ $G/work の main に分かれ目のコミットを作り、head のブランチで
# PR の変更をコミットする。両方を $G/remote.git に push し、head のブランチを
# 履歴の深さ1で $G/head に取る。検査は $G/head の中で流す。

# 使い方: new_repo [nogo]。分かれ目のコミットの並びのファイルを $G/work に置く。
# backend/go.mod は go 1.27.0 と toolchain go1.27.4、2つの Dockerfile は golang:1.27.4。
# nogo を渡すと、Go の版を書いたファイルを置かない
new_repo() {
    N=$((N + 1))
    G="$WORK/g$N"
    FAKE_MAP="$WORK/map$N.tsv"
    FAKE_LOG="$WORK/log$N.txt"
    : >"$FAKE_MAP"
    : >"$FAKE_LOG"
    mkdir -p "$G/work/backend" "$G/work/docker/backend-go" "$G/work/docker/frontend"
    git init -q -b main "$G/work"
    echo "readme" >"$G/work/README.md"
    printf 'FROM node:24.1.0-bookworm-slim\n' >"$G/work/docker/frontend/Dockerfile"
    [ "${1:-}" = nogo ] || write_go
}

write_go() {
    printf 'module example.test/backend\n\ngo 1.27.0\n\ntoolchain go1.27.4\n\nrequire example.test/x v1.0.0 // go 1.20\n' >"$G/work/backend/go.mod"
    printf 'FROM golang:1.27.4-trixie@%s AS build\nRUN go build ./...\nFROM gcr.io/distroless/static\n' "$D1" >"$G/work/docker/backend-go/Dockerfile"
    printf "# FROM golang:1.20\nFROM --platform=\$BUILDPLATFORM docker.io/library/golang:1.27.4-trixie@%s AS build\n" "$D1" >"$G/work/docker/backend-go/Dockerfile.prod"
}

# 使い方: commit_as <変数の名前>。作業のリポジトリの変更をコミットし、SHA を変数に入れる
commit_as() {
    git -C "$G/work" add -A
    git -C "$G/work" commit -q -m "$1"
    printf -v "$1" '%s' "$(git -C "$G/work" rev-parse HEAD)"
}

# 使い方: base_commit。分かれ目のコミットを作り、MB と MAIN_SHA に入れる
base_commit() {
    commit_as MB
    MAIN_SHA="$MB"
}

# 使い方: branch_head。分かれ目のコミットから head のブランチを作る
branch_head() {
    git -C "$G/work" checkout -q -b head "$MB"
}

# 使い方: finish。head のコミットを作り、リモートに push して、head を履歴の深さ1で取る。
# 比較の API の応答に、分かれ目のコミットを返す。
finish() {
    commit_as HEAD_SHA
    git init -q --bare "$G/remote.git"
    git -C "$G/remote.git" config uploadpack.allowAnySHA1InWant true
    git -C "$G/work" push -q "file://$G/remote.git" main head 2>/dev/null
    git clone -q --depth 1 --branch head "file://$G/remote.git" "$G/head" 2>/dev/null
    fx gh "repos/o/r/compare/${MAIN_SHA}...${HEAD_SHA}" 200 \
        "{\"status\":\"ahead\",\"merge_base_commit\":{\"sha\":\"${MB}\"}}"
}

# 使い方: edit <根からのパス> <前の文字> <後の文字>。作業のリポジトリのファイルの中の
# すべての <前の文字> を <後の文字> に替える。そのままの文字で比べる。無ければ失敗にする
edit() {
    local c
    c=$(cat "$G/work/$1")
    if [[ "$c" != *"$2"* ]]; then
        fail "テストの準備" "$1 に「$2」がありません"
        return 1
    fi
    printf '%s\n' "${c//"$2"/"$3"}" >"$G/work/$1"
}

# 使い方: bump <前の版> <後の版>。go.mod の toolchain の行と、2つの Dockerfile の版を替える
bump() {
    edit backend/go.mod "toolchain go$1" "toolchain go$2"
    edit docker/backend-go/Dockerfile "golang:$1-" "golang:$2-"
    edit docker/backend-go/Dockerfile.prod "golang:$1-" "golang:$2-"
}

# 使い方: run [<今の時刻>]。head の写しの中で検査を流す。呼ばれた取り先の記録を空にしてから流す。
# 標準出力を $WORK/out.txt に、終了コードを $RC に入れる
run() {
    : >"$FAKE_LOG"
    : >"$WORK/summary.md"
    (cd "$G/head" && GITHUB_REPOSITORY=o/r GITHUB_STEP_SUMMARY="$WORK/summary.md" NOW_EPOCH="${1:-$NOW}" \
        bash "$SCRIPT" "$MAIN_SHA" "$HEAD_SHA") >"$WORK/out.txt" 2>"$WORK/err.txt"
    RC=$?
}

# 使い方: expect <説明> <終了コード> [<確かめ> <値>]...
# 確かめは次のどれか。値はそのままの文字で比べる。
#   out / summary / log: そのファイルに、値と同じ行がある
#   no-out / no-summary / no-log: そのファイルに、値を含む行が無い
#   lines-log: そのファイルの行の数が値と同じ
expect() {
    local name="$1" rc="$2" kind f
    shift 2
    if [ "$RC" -ne "$rc" ]; then
        fail "$name" "終了コードが ${RC}(期待は ${rc})。出力: $(head -c 800 "$WORK/out.txt") / 標準エラー: $(head -c 300 "$WORK/err.txt")"
        return
    fi
    while [ "$#" -ge 2 ]; do
        kind="$1"
        case "${kind#*-}" in
        out) f="$WORK/out.txt" ;;
        summary) f="$WORK/summary.md" ;;
        log) f="$FAKE_LOG" ;;
        esac
        case "$kind" in
        no-*)
            if grep -qF -- "$2" "$f"; then
                fail "$name" "${kind#no-} に「$2」を含む行があります: $(grep -F -- "$2" "$f" | head -n 1)"
                return
            fi
            ;;
        lines-*)
            if [ "$(grep -c '' "$f" 2>/dev/null)" != "$2" ]; then
                fail "$name" "${kind#lines-} の行の数が $(grep -c '' "$f" 2>/dev/null)(期待は $2)。中身: $(tr '\n' '|' <"$f" 2>/dev/null)"
                return
            fi
            ;;
        *)
            if ! grep -qxF -- "$2" "$f" 2>/dev/null; then
                fail "$name" "${kind} に「$2」の行がありません。中身: $(head -c 800 "$f" 2>/dev/null)"
                return
            fi
            ;;
        esac
        shift 2
    done
    pass "$name"
}

NOCHANGE="Go の版の公開からの時間の検査: 新しく使う Go の版はありません。"
HEADER="| 版 | 書いた場所 | 公開日時 | 入るようになる時刻 | 結果 |"
PLACES="backend/go.mod, docker/backend-go/Dockerfile, docker/backend-go/Dockerfile.prod"
AMD="curl https://go.test/dl/go1.27.5.linux-amd64.tar.gz"
ARM="curl https://go.test/dl/go1.27.5.linux-arm64.tar.gz"

# --- Go の版を新しく使わない PR -------------------------------------------------

if want no_change; then
    new_repo
    base_commit
    branch_head
    edit README.md readme "readme の変更"
    finish
    run
    expect "Go の版を変えない PR が配布元に問い合わせずに通る" 0 \
        out "$NOCHANGE" summary "新しく使う Go の版はありません。" \
        log "gh repos/o/r/compare/${MAIN_SHA}...${HEAD_SHA}" lines-log 1
fi

if want same_version_elsewhere; then
    new_repo
    base_commit
    branch_head
    # 分かれ目で使っていた版を、新しい Dockerfile に書き足す
    mkdir -p "$G/work/backend/compat/fakeaws"
    printf 'FROM golang:1.27.4-alpine\n' >"$G/work/backend/compat/fakeaws/Dockerfile"
    finish
    run
    expect "分かれ目で使っていた版を別のファイルに書き足しただけの PR は、配布元に問い合わせずに通る" 0 \
        out "$NOCHANGE" lines-log 1
fi

if want lower_or_remove; then
    new_repo
    base_commit
    branch_head
    rm -f "$G/work/docker/backend-go/Dockerfile.prod"
    edit backend/go.mod "toolchain go1.27.4
" ""
    finish
    run
    expect "Go の版を消すだけの PR は、配布元に問い合わせずに通る" 0 out "$NOCHANGE" lines-log 1
fi

if want other_images; then
    new_repo
    base_commit
    branch_head
    edit docker/frontend/Dockerfile "node:24.1.0" "node:24.2.0"
    edit docker/backend-go/Dockerfile "gcr.io/distroless/static" "gcr.io/distroless/static:nonroot"
    edit backend/go.mod "v1.0.0 // go 1.20" "v1.1.0 // go 1.21"
    finish
    run
    expect "golang でないイメージと、go.mod の go と toolchain でない行の変更では、配布元に問い合わせない" 0 \
        out "$NOCHANGE" lines-log 1
fi

# --- 72時間経った版 -----------------------------------------------------------

if want old_pass; then
    new_repo
    base_commit
    branch_head
    bump 1.27.4 1.27.5
    finish
    dl 1.27.5 "$OLD"
    run
    expect "公開から72時間経った版に上げる PR が通る" 0 \
        summary "$HEADER" \
        summary "| 1.27.5 | ${PLACES} | 2026-10-01 00:00 UTC | 2026-10-04 00:00 UTC | 通しました |" \
        log "$AMD" log "$ARM" no-out "::error::"
fi

if want go_line; then
    new_repo
    base_commit
    branch_head
    edit backend/go.mod "go 1.27.0" "go 1.28"
    finish
    dl 1.28.0 "$OLD"
    run
    expect "go の行の2つの数の版を、3つ目を 0 にして調べる" 0 \
        summary "| 1.28.0 | backend/go.mod | 2026-10-01 00:00 UTC | 2026-10-04 00:00 UTC | 通しました |" \
        log "curl https://go.test/dl/go1.28.0.linux-amd64.tar.gz"
fi

if want no_go_at_base; then
    new_repo nogo
    base_commit
    branch_head
    write_go
    finish
    dl 1.27.0 "$OLD"
    dl 1.27.4 "$YOUNG"
    run
    expect "分かれ目に Go の版が1つも無い PR で、head の版をすべて新しく使う版として調べる" 1 \
        summary "| 1.27.0 | backend/go.mod | 2026-10-01 00:00 UTC | 2026-10-04 00:00 UTC | 通しました |" \
        summary "| 1.27.4 | ${PLACES} | 2026-11-03 00:00 UTC | 2026-11-06 00:00 UTC | 止めました(公開から72時間経っていない) |" \
        out "::error::72時間の待ちで止めた部品: Go 1.27.4。理由: 公開から72時間経っていない。入るようになる時刻: 2026-11-06 00:00 UTC"
fi

# --- 72時間経っていない版 ------------------------------------------------------

if want young_stop; then
    new_repo
    base_commit
    branch_head
    bump 1.27.4 1.27.5
    finish
    dl 1.27.5 "$YOUNG"
    run
    expect "公開から72時間経っていない版に上げる PR を止め、/ship が読む形の行を出す" 1 \
        summary "| 1.27.5 | ${PLACES} | 2026-11-03 00:00 UTC | 2026-11-06 00:00 UTC | 止めました(公開から72時間経っていない) |" \
        out "::error::72時間の待ちで止めた部品: Go 1.27.5。理由: 公開から72時間経っていない。入るようになる時刻: 2026-11-06 00:00 UTC"
    run "$LATER"
    expect "今の時刻を入るようになる時刻のあとにすると、同じ版で通る" 0 \
        summary "| 1.27.5 | ${PLACES} | 2026-11-03 00:00 UTC | 2026-11-06 00:00 UTC | 通しました |" \
        no-out "::error::"
fi

if want only_dockerfile; then
    new_repo
    base_commit
    branch_head
    edit docker/backend-go/Dockerfile.prod "golang:1.27.4-" "golang:1.27.5-"
    finish
    dl 1.27.5 "$YOUNG"
    run
    expect "Dockerfile の1か所だけで版を上げても止める" 1 \
        summary "| 1.27.5 | docker/backend-go/Dockerfile.prod | 2026-11-03 00:00 UTC | 2026-11-06 00:00 UTC | 止めました(公開から72時間経っていない) |"
fi

if want newer_platform; then
    new_repo
    base_commit
    branch_head
    bump 1.27.4 1.27.5
    finish
    # amd64 は古く、arm64 は新しい。新しい方の時刻を公開日時とし、入るようになる時刻の分の端数を切り上げる
    dl 1.27.5 "$OLD" "$YOUNG2"
    run
    expect "2つの配布物のうち新しい方の時刻で判定する" 1 \
        summary "| 1.27.5 | ${PLACES} | 2026-11-03 00:00 UTC | 2026-11-06 00:01 UTC | 止めました(公開から72時間経っていない) |" \
        out "::error::72時間の待ちで止めた部品: Go 1.27.5。理由: 公開から72時間経っていない。入るようになる時刻: 2026-11-06 00:01 UTC"
fi

# --- 公開日時を取れないとき ----------------------------------------------------

if want not_found; then
    new_repo
    base_commit
    branch_head
    bump 1.27.4 1.27.99
    finish
    dl_status 1.27.99 404 404
    run
    expect "配布元に無い版を止める" 1 \
        summary "| 1.27.99 | ${PLACES} | 取れなかった | 取れなかった | 止めました(配布元にこの版が無い(https://go.test/dl/go1.27.99.linux-amd64.tar.gz が HTTP 404 を返した)) |" \
        out "::error::Go の版 1.27.99 を止めました: 配布元にこの版が無い(https://go.test/dl/go1.27.99.linux-amd64.tar.gz が HTTP 404 を返した)(${PLACES})。ジョブを Re-run してください"
fi

if want arm_missing; then
    new_repo
    base_commit
    branch_head
    bump 1.27.4 1.27.5
    finish
    fx curl "https://go.test/dl/go1.27.5.linux-amd64.tar.gz" 200 "$(printf 'HTTP/2 200\r\nlast-modified: %s\r\n\r' "$OLD")"
    fx curl "https://go.test/dl/go1.27.5.linux-arm64.tar.gz" 404 "$(printf 'HTTP/2 404\r\n\r')"
    run
    expect "片方の配布物が無い版を止める" 1 \
        out "::error::Go の版 1.27.5 を止めました: 配布元にこの版が無い(https://go.test/dl/go1.27.5.linux-arm64.tar.gz が HTTP 404 を返した)(${PLACES})。ジョブを Re-run してください" \
        no-summary "通しました"
fi

if want fetch_fail; then
    new_repo
    base_commit
    branch_head
    bump 1.27.4 1.27.5
    finish
    dl_status 1.27.5 502 502
    run
    expect "配布元が失敗を返すと止める" 1 \
        out "::error::Go の版 1.27.5 を止めました: 配布元に問い合わせられなかった(https://go.test/dl/go1.27.5.linux-amd64.tar.gz: HTTP 502)(${PLACES})。ジョブを Re-run してください"
    : >"$FAKE_MAP"
    fx gh "repos/o/r/compare/${MAIN_SHA}...${HEAD_SHA}" 200 \
        "{\"status\":\"ahead\",\"merge_base_commit\":{\"sha\":\"${MB}\"}}"
    run
    expect "配布元につながらないと止める" 1 \
        out "::error::Go の版 1.27.5 を止めました: 配布元に問い合わせられなかった(https://go.test/dl/go1.27.5.linux-amd64.tar.gz: HTTP 000 curl: (7) Failed to connect to go.test port 443)(${PLACES})。ジョブを Re-run してください"
fi

if want bad_last_modified; then
    new_repo
    base_commit
    branch_head
    bump 1.27.4 1.27.5
    finish
    # 転送の応答には Last-Modified があり、最後の応答には無い
    fx curl "$GO_DL_BASE/go1.27.5.linux-amd64.tar.gz" 200 "$(printf 'HTTP/2 302\r\nlast-modified: %s\r\n\r\nHTTP/2 200\r\n\r' "$OLD")"
    fx curl "$GO_DL_BASE/go1.27.5.linux-arm64.tar.gz" 200 "$(printf 'HTTP/2 200\r\nlast-modified: %s\r\n\r' "$OLD")"
    run
    expect "最後の応答に Last-Modified が無いと、転送の応答の時刻を使わずに止める" 1 \
        out "::error::Go の版 1.27.5 を止めました: 配布元の応答の公開日時を読めなかった(https://go.test/dl/go1.27.5.linux-amd64.tar.gz の Last-Modified: 無し)(${PLACES})。ジョブを Re-run してください"
    : >"$FAKE_MAP"
    fx gh "repos/o/r/compare/${MAIN_SHA}...${HEAD_SHA}" 200 \
        "{\"status\":\"ahead\",\"merge_base_commit\":{\"sha\":\"${MB}\"}}"
    dl 1.27.5 "Thu, 01 Foo 2026 00:00:00 GMT"
    run
    expect "Last-Modified の形が違うと止める" 1 \
        out "::error::Go の版 1.27.5 を止めました: 配布元の応答の公開日時を読めなかった(https://go.test/dl/go1.27.5.linux-amd64.tar.gz の Last-Modified: Thu, 01 Foo 2026 00:00:00 GMT)(${PLACES})。ジョブを Re-run してください"
fi

# --- 版を読めない書き方 ---------------------------------------------------------

if want unreadable; then
    new_repo
    base_commit
    branch_head
    edit docker/backend-go/Dockerfile "golang:1.27.4-trixie@$D1" "golang:1.27-trixie"
    edit docker/backend-go/Dockerfile.prod "docker.io/library/golang:1.27.4-trixie@$D1" "golang:\${GO_VERSION}"
    edit backend/go.mod "toolchain go1.27.4" "toolchain default"
    finish
    run
    expect "版を読めない書き方を、配布元に問い合わせずに止める" 1 \
        summary "| golang:1.27-trixie | docker/backend-go/Dockerfile | 取れなかった | 取れなかった | 止めました(版を読めない書き方) |" \
        out "::error::Go の版を読めない書き方「golang:1.27-trixie」を止めました(docker/backend-go/Dockerfile)。golang:1.27.4-trixie や toolchain go1.27.4 のように、Go の版を3つの数で書いてください" \
        out "::error::Go の版を読めない書き方「golang:\${GO_VERSION}」を止めました(docker/backend-go/Dockerfile.prod)。golang:1.27.4-trixie や toolchain go1.27.4 のように、Go の版を3つの数で書いてください" \
        out "::error::Go の版を読めない書き方「toolchain default」を止めました(backend/go.mod)。golang:1.27.4-trixie や toolchain go1.27.4 のように、Go の版を3つの数で書いてください" \
        lines-log 1
fi

if want no_tag; then
    new_repo
    base_commit
    branch_head
    edit docker/backend-go/Dockerfile "golang:1.27.4-trixie@$D1" "golang@$D1"
    finish
    run
    expect "タグの無い golang を止める" 1 \
        out "::error::Go の版を読めない書き方「golang@${D1}」を止めました(docker/backend-go/Dockerfile)。golang:1.27.4-trixie や toolchain go1.27.4 のように、Go の版を3つの数で書いてください"
fi

if want rc_version; then
    new_repo
    base_commit
    branch_head
    bump 1.27.4 1.28rc1
    finish
    dl 1.28rc1 "$YOUNG"
    run
    expect "rc の版も配布元で調べる" 1 \
        out "::error::72時間の待ちで止めた部品: Go 1.28rc1。理由: 公開から72時間経っていない。入るようになる時刻: 2026-11-06 00:00 UTC" \
        log "curl https://go.test/dl/go1.28rc1.linux-arm64.tar.gz"
fi

# --- 調べられないとき -----------------------------------------------------------

if want bad_args; then
    new_repo
    base_commit
    branch_head
    edit README.md readme "readme の変更"
    finish
    (cd "$G/head" && GITHUB_REPOSITORY=o/r bash "$SCRIPT") >"$WORK/out.txt" 2>&1
    RC=$?
    expect "引数が無いと終了コード 2 になる" 2 lines-log 0
    (cd "$G/head" && GITHUB_REPOSITORY="" bash "$SCRIPT" "$MAIN_SHA" "$HEAD_SHA") >"$WORK/out.txt" 2>&1
    RC=$?
    expect "GITHUB_REPOSITORY が無いと終了コード 2 になる" 2 lines-log 0
fi

if want compare_fail; then
    new_repo
    base_commit
    branch_head
    bump 1.27.4 1.27.5
    finish
    : >"$FAKE_MAP"
    run
    expect "分かれ目のコミットを取れないと止める" 1 \
        out "::error::分かれ目のコミットを取れませんでした(比較の API が失敗しました: gh: Not Found (HTTP 404))。ジョブを Re-run してください" \
        lines-log 1
fi

if want fetch_base_fail; then
    new_repo
    base_commit
    branch_head
    bump 1.27.4 1.27.5
    finish
    mv "$G/remote.git" "$G/gone.git"
    run
    expect "分かれ目のコミットを git fetch で取れないと止める" 1 \
        out "::error::分かれ目のコミット ${MB} を取れませんでした(git fetch が失敗しました: $(cd "$G/head" && git fetch --quiet --no-tags --depth=1 origin "$MB" 2>&1 | head -n 1))"
fi

if [ "$RAN" -eq 0 ]; then
    echo "FAIL: 場合「${CASE}」はありません"
    exit 1
fi
if [ "$FAILED" -ne 0 ]; then
    echo "失敗したテストがあります。"
    exit 1
fi
echo "すべてのテストが通りました。"
