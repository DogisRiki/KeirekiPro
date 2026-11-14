#!/usr/bin/env bash
# =====================================================================
# check-go-release-age.sh の自動テスト(dependency-review の cooldown から実行)
#
# 一時のフォルダに、分かれ目のコミットと head のブランチを持つリモートを作り、
# head のブランチを履歴の深さ1で取った写しの中で検査を流す。PATH の先頭に偽の gh と
# curl を置き、比較の API の応答と Go の配布元の応答を場合ごとに返す。
# 偽の gh と curl は、呼ばれた取り先を記録する。記録で、配布元に問い合わせたかを確かめる。
#
# 環境変数 KP_TEST_CASE に場合の名前を入れると、その場合だけを流す。
# 外部への問い合わせを行わないため、実行にネットワークを必要としない。
# =====================================================================
set -uo pipefail
# GitHub Actions がジョブに入れる環境変数を消す。消さないと、環境変数が無いときの場合を
# 確かめられず、ジョブの Summary にテストの表が書かれる。場合ごとに要るものだけを入れる
unset GITHUB_REPOSITORY GITHUB_STEP_SUMMARY NOW_EPOCH

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
# 呼ばれた取り先を FAKE_LOG に1行ずつ書く。gh の取り先は「gh <API のパス>」、
# curl の取り先は「curl <URL>」と書く。
# gh は、行の無い取り先に 404 を返す。curl は、行の無い取り先につながらなかったとする。
# curl の応答のファイルは、応答の見出しである(-D のファイルに写す)。

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
out="" hdr="" fmt="" url=""
while [ "$#" -gt 0 ]; do
    case "$1" in
    -o) out="$2"; shift 2 ;;
    -D) hdr="$2"; shift 2 ;;
    -w) fmt="$2"; shift 2 ;;
    --max-time | --retry) shift 2 ;;
    -*) shift ;;
    *) url="$1"; shift ;;
    esac
done
key="curl $url"
printf '%s\n' "$key" >>"$FAKE_LOG"
row=$(awk -F '\t' -v k="$key" '$1 == k { print; exit }' "$FAKE_MAP")
if [ -z "$row" ]; then
    [ -n "$fmt" ] && printf '000'
    echo "curl: (7) Failed to connect to go.test port 443" >&2
    exit 7
fi
st=$(printf '%s\n' "$row" | cut -f2)
[ -n "$hdr" ] && cat "$(printf '%s\n' "$row" | cut -f3)" >"$hdr"
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

D1="sha256:b54b2639de8c1bfe538ec5ffc45f29b1932235ac5f6d63c059853646677112d9"
# 2026-11-14T00:00:00Z
NOW=1794614400
OLD="Tue, 03 Nov 2026 00:00:00 GMT"
YOUNG="Thu, 12 Nov 2026 00:00:00 GMT"
# 今の時刻のちょうど72時間前と、その1秒あと
EDGE="Wed, 11 Nov 2026 00:00:00 GMT"
EDGE1="Wed, 11 Nov 2026 00:00:01 GMT"

# 使い方: fx <取り先> <HTTP の状態> <応答のファイルの中身>
fx() {
    local f
    f="$WORK/fx$N-$(wc -l <"$FAKE_MAP" | tr -d ' ').txt"
    printf '%s' "$3" >"$f"
    printf '%s\t%s\t%s\n' "$1" "$2" "$f" >>"$FAKE_MAP"
}

# 使い方: dl <版> <平台> <HTTP の状態> [<Last-Modified>]。配布元の応答を足す。
# go.dev から dl.google.com への転送を挟み、転送の応答には公開日時と違う Last-Modified を付ける
dl() {
    local lm=""
    [ -n "${4:-}" ] && lm="Last-Modified: $4"$'\r\n'
    fx "curl https://go.test/dl/go$1.$2.tar.gz" "$3" \
        "$(printf 'HTTP/2 302\r\nlocation: https://dl.google.com/go/go%s.%s.tar.gz\r\nlast-modified: Mon, 01 Jan 2024 00:00:00 GMT\r\n\r\nHTTP/2 %s\r\ncontent-type: application/x-gzip\r\n%s\r\n' "$1" "$2" "$3" "$lm")"
}

# 使い方: release <版> <amd64 の Last-Modified> [<arm64 の Last-Modified>]。
# 2つの平台の配布物を足す。arm64 を省くと amd64 と同じにする
release() {
    dl "$1" linux-amd64 200 "$2"
    dl "$1" linux-arm64 200 "${3:-$2}"
}

# --- リモートの作り方 -------------------------------------------------------
# 作業のリポジトリ $G/work の main に分かれ目のコミットを作り、head のブランチで
# PR の変更をコミットする。両方を $G/remote.git に push し、head のブランチを
# 履歴の深さ1で $G/head に取る。検査は $G/head の中で流す。

# 使い方: new_repo。分かれ目のコミットのファイルを $G/work に置く。
# Go の版は、backend/go.mod の go の行が 1.27.0、toolchain の行が go1.27.4、
# docker/backend-go/Dockerfile の FROM が golang:1.27.4-trixie。
new_repo() {
    N=$((N + 1))
    G="$WORK/g$N"
    FAKE_MAP="$WORK/map$N.tsv"
    FAKE_LOG="$WORK/log$N.txt"
    : >"$FAKE_MAP"
    : >"$FAKE_LOG"
    mkdir -p "$G/work/backend" "$G/work/docker/backend-go"
    git init -q -b main "$G/work"
    printf 'module example.test/x\n\ngo 1.27.0\n\ntoolchain go1.27.4\n' >"$G/work/backend/go.mod"
    printf 'FROM golang:1.27.4-trixie@%s\nRUN go version\n' "$D1" >"$G/work/docker/backend-go/Dockerfile"
    echo "readme" >"$G/work/README.md"
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
    fx "gh repos/o/r/compare/${MAIN_SHA}...${HEAD_SHA}" 200 \
        "{\"status\":\"ahead\",\"merge_base_commit\":{\"sha\":\"${MB}\"}}"
}

# 使い方: put <根からのパス> <中身>。作業のリポジトリにファイルを書く
put() {
    mkdir -p "$(dirname "$G/work/$1")"
    printf '%s\n' "$2" >"$G/work/$1"
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
#   has-out: 標準出力に、値を含む行がある
#   no-out / no-log: そのファイルに、値を含む行が無い
#   lines-log: 呼ばれた取り先の記録の行の数が値と同じ
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
        has-*)
            if ! grep -qF -- "$2" "$f"; then
                fail "$name" "${kind#has-} に「$2」を含む行がありません。中身: $(head -c 800 "$f")"
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

NOCHANGE="Go の版の公開からの時間の検査: Go の版の変更はありません。"
HEADER="| 版 | 書いた場所 | 公開日時 | 通る日時 | 結果 |"
COMPARE_LOG() { printf 'gh repos/o/r/compare/%s...%s' "$MAIN_SHA" "$HEAD_SHA"; }
AMD="curl https://go.test/dl/go1.27.5.linux-amd64.tar.gz"
ARM="curl https://go.test/dl/go1.27.5.linux-arm64.tar.gz"

# 使い方: bump <版>。go.mod の toolchain の行と Dockerfile の FROM の版を <版> にする
bump() {
    put backend/go.mod "$(printf 'module example.test/x\n\ngo 1.27.0\n\ntoolchain go%s' "$1")"
    put docker/backend-go/Dockerfile "$(printf 'FROM golang:%s-trixie@%s\nRUN go version' "$1" "$D1")"
}

# --- Go の版を変えない PR ----------------------------------------------------

if want no_change; then
    new_repo
    base_commit
    branch_head
    # Go の版を読むファイルでないファイルに FROM golang の行を書いても読まない
    put README.md "FROM golang:1.99.0"
    finish
    run
    expect "Go の版を変えない PR が配布元に問い合わせずに通る" 0 \
        out "$NOCHANGE" summary "Go の版の変更はありません。" \
        log "$(COMPARE_LOG)" lines-log 1
fi

if want moved; then
    new_repo
    put "a b/Dockerfile.old" "FROM golang:1.27.3"
    base_commit
    branch_head
    # 分かれ目のほかのファイルにある版を、新しいファイルに書く。空白を含む場所も読む
    put "x y/app.Dockerfile" "$(printf 'FROM golang:1.27.4-alpine AS b\nFROM golang:1.27.3')"
    finish
    run
    expect "分かれ目のどこかにある版だけを書いた PR が配布元に問い合わせずに通る" 0 \
        out "$NOCHANGE" lines-log 1
fi

if want submodule; then
    new_repo
    base_commit
    branch_head
    # 名前が Dockerfile のサブモジュールは、ファイルの中身が無いので読まない
    # 中身を取っていないサブモジュールと同じく、空のフォルダを置く
    mkdir -p "$G/work/vendor/Dockerfile"
    git -C "$G/work" update-index --add --cacheinfo "160000,${MB},vendor/Dockerfile"
    put README.md "readme の変更"
    finish
    if [ "$(git -C "$G/work" ls-tree "$HEAD_SHA" vendor/Dockerfile | cut -c1-6)" != 160000 ]; then
        fail "テストの準備" "head にサブモジュールがありません"
    fi
    run
    expect "サブモジュールを読まずに通る" 0 out "$NOCHANGE" lines-log 1
fi

if want same_unreadable; then
    new_repo
    put tools/Dockerfile "FROM golang:latest"
    base_commit
    branch_head
    put README.md "readme の変更"
    finish
    run
    expect "分かれ目と同じ、版を読めない書き方は止めない" 0 out "$NOCHANGE" lines-log 1
fi

# --- 公開から72時間経った版 --------------------------------------------------

if want old; then
    new_repo
    base_commit
    branch_head
    bump 1.27.5
    finish
    release 1.27.5 "$OLD"
    run
    expect "公開から72時間経った版に上げた PR が通る" 0 \
        out "$HEADER" \
        out "| 1.27.5 | backend/go.mod、docker/backend-go/Dockerfile | 2026-11-03T00:00:00Z | 2026-11-06T00:00:00Z | 通しました |" \
        summary "| 1.27.5 | backend/go.mod、docker/backend-go/Dockerfile | 2026-11-03T00:00:00Z | 2026-11-06T00:00:00Z | 通しました |" \
        log "$AMD" log "$ARM" lines-log 3 no-out "::error::"
fi

if want go_line_dedup; then
    new_repo
    base_commit
    branch_head
    # go の行と toolchain の行が同じ版のときは、1つの版として1回だけ問い合わせる
    put backend/go.mod "$(printf 'module example.test/x\n\ngo 1.27.5\n\ntoolchain go1.27.5')"
    finish
    release 1.27.5 "$OLD"
    run
    expect "go.mod の2つの行の同じ版を、1つの場所として1回だけ調べる" 0 \
        out "| 1.27.5 | backend/go.mod | 2026-11-03T00:00:00Z | 2026-11-06T00:00:00Z | 通しました |" \
        lines-log 3
fi

if want edge; then
    new_repo
    base_commit
    branch_head
    bump 1.27.5
    finish
    release 1.27.5 "$EDGE"
    run
    expect "公開からちょうど72時間経った版を通す" 0 \
        out "| 1.27.5 | backend/go.mod、docker/backend-go/Dockerfile | 2026-11-11T00:00:00Z | 2026-11-14T00:00:00Z | 通しました |"
fi

# --- 止める版 ----------------------------------------------------------------

if want edge_young; then
    new_repo
    base_commit
    branch_head
    bump 1.27.5
    finish
    release 1.27.5 "$EDGE1"
    run
    expect "公開から72時間に1秒足りない版を止める" 1 \
        out "| 1.27.5 | backend/go.mod、docker/backend-go/Dockerfile | 2026-11-11T00:00:01Z | 2026-11-14T00:00:01Z | 止めました(公開から72時間経っていません) |" \
        has-out "::error::Go の版 1.27.5 を止めました: 公開から72時間経っていません。公開日時は 2026-11-11T00:00:01Z、検査が通るようになる日時は 2026-11-14T00:00:01Z です。"
fi

if want young_arm; then
    new_repo
    base_commit
    branch_head
    bump 1.27.5
    finish
    # amd64 は古く、arm64 だけが公開から72時間経っていない。新しいほうで判定する
    release 1.27.5 "$OLD" "$YOUNG"
    run
    expect "2つの平台のうち新しいほうが公開から72時間経っていなければ止める" 1 \
        out "| 1.27.5 | backend/go.mod、docker/backend-go/Dockerfile | 2026-11-12T00:00:00Z | 2026-11-15T00:00:00Z | 止めました(公開から72時間経っていません) |" \
        summary "| 1.27.5 | backend/go.mod、docker/backend-go/Dockerfile | 2026-11-12T00:00:00Z | 2026-11-15T00:00:00Z | 止めました(公開から72時間経っていません) |" \
        has-out "::error::Go の版 1.27.5 を止めました"
    # 通る日時を過ぎてから流し直すと、同じ版で通る(2026-11-15T00:00:00Z)
    run 1794787200
    expect "通る日時を過ぎてから流し直すと、同じ版で通る" 0 \
        out "| 1.27.5 | backend/go.mod、docker/backend-go/Dockerfile | 2026-11-12T00:00:00Z | 2026-11-15T00:00:00Z | 通しました |"
fi

if want mixed; then
    new_repo
    base_commit
    branch_head
    put backend/go.mod "$(printf 'module example.test/x\n\ngo 1.27.0\n\ntoolchain go1.27.5')"
    put docker/backend-go/Dockerfile "$(printf 'FROM golang:1.28rc1-trixie@%s' "$D1")"
    finish
    release 1.27.5 "$OLD"
    release 1.28rc1 "$YOUNG"
    run
    expect "古い版と若い版を混ぜた PR は、若い版だけを止め、両方を表に書く" 1 \
        out "| 1.27.5 | backend/go.mod | 2026-11-03T00:00:00Z | 2026-11-06T00:00:00Z | 通しました |" \
        out "| 1.28rc1 | docker/backend-go/Dockerfile | 2026-11-12T00:00:00Z | 2026-11-15T00:00:00Z | 止めました(公開から72時間経っていません) |" \
        has-out "::error::Go の版 1.28rc1 を止めました" no-out "::error::Go の版 1.27.5"
fi

if want unreadable; then
    new_repo
    base_commit
    branch_head
    put docker/backend-go/Dockerfile "FROM golang:1.27-trixie"
    finish
    run
    expect "版を読めない書き方を、配布元に問い合わせずに止める" 1 \
        out "| golang:1.27-trixie | docker/backend-go/Dockerfile | - | - | 止めました(版を読めない書き方です) |" \
        has-out "::error::docker/backend-go/Dockerfile の Go の版の書き方「golang:1.27-trixie」を止めました" \
        no-log "curl " lines-log 1
fi

if want unreadable_gomod; then
    new_repo
    base_commit
    branch_head
    put backend/go.mod "$(printf 'module example.test/x\n\ngo 1.27.0\n\ntoolchain default')"
    finish
    run
    expect "go.mod の版を読めない toolchain の行を止める" 1 \
        out "| toolchain default | backend/go.mod | - | - | 止めました(版を読めない書き方です) |"
fi

if want not_found; then
    new_repo
    base_commit
    branch_head
    bump 1.27.5
    finish
    dl 1.27.5 linux-amd64 404
    run
    expect "配布元に無い版を止める" 1 \
        has-out "| 1.27.5 | backend/go.mod、docker/backend-go/Dockerfile | 取れなかった | 取れなかった | 止めました(配布元にこの版が無い" \
        has-out "::error::Go の版 1.27.5 を止めました: 公開日時を取れませんでした(配布元にこの版が無い"
fi

if want unreachable; then
    new_repo
    base_commit
    branch_head
    bump 1.27.5
    finish
    run
    expect "配布元につながらないときは止める" 1 \
        has-out "止めました(配布元に問い合わせられなかった" \
        has-out "::error::Go の版 1.27.5 を止めました: 公開日時を取れませんでした" \
        has-out "ジョブを Re-run してください"
fi

if want no_last_modified; then
    new_repo
    base_commit
    branch_head
    bump 1.27.5
    finish
    dl 1.27.5 linux-amd64 200 ""
    dl 1.27.5 linux-arm64 200 "$OLD"
    run
    expect "配布元の応答に公開日時が無いときは止める" 1 \
        has-out "止めました(配布元の応答の公開日時を読めなかった"
fi

# --- 分かれ目のコミットと引数 ------------------------------------------------

if want compare_fail; then
    new_repo
    base_commit
    branch_head
    bump 1.27.5
    commit_as HEAD_SHA
    git init -q --bare "$G/remote.git"
    git -C "$G/work" push -q "file://$G/remote.git" main head 2>/dev/null
    git clone -q --depth 1 --branch head "file://$G/remote.git" "$G/head" 2>/dev/null
    fx "gh repos/o/r/compare/${MAIN_SHA}...${HEAD_SHA}" 500 '{"message":"boom"}'
    run
    expect "比較の API が失敗したら止める" 1 \
        has-out "::error::分かれ目のコミットを取れませんでした(比較の API が失敗しました" no-log "curl "
fi

if want no_merge_base; then
    new_repo
    base_commit
    branch_head
    bump 1.27.5
    commit_as HEAD_SHA
    git init -q --bare "$G/remote.git"
    git -C "$G/work" push -q "file://$G/remote.git" main head 2>/dev/null
    git clone -q --depth 1 --branch head "file://$G/remote.git" "$G/head" 2>/dev/null
    fx "gh repos/o/r/compare/${MAIN_SHA}...${HEAD_SHA}" 200 '{"status":"ahead"}'
    run
    expect "比較の API の応答に分かれ目のコミットが無ければ止める" 1 \
        has-out "merge_base_commit.sha がありません" no-log "curl "
fi

if want bad_args; then
    new_repo
    base_commit
    branch_head
    put README.md "readme の変更"
    finish
    : >"$WORK/summary.md"
    (cd "$G/head" && GITHUB_REPOSITORY=o/r bash "$SCRIPT" "not-a-sha" "$HEAD_SHA") >"$WORK/out.txt" 2>&1
    RC=$?
    expect "base の形が違えば 2 で終わる" 2 has-out "::error::base の形が違います: not-a-sha"
    (cd "$G/head" && bash "$SCRIPT" "$MAIN_SHA" "$HEAD_SHA") >"$WORK/out.txt" 2>&1
    RC=$?
    expect "GITHUB_REPOSITORY が無ければ 2 で終わる" 2 has-out "::error::GITHUB_REPOSITORY の形が違います"
    (cd "$G/head" && GITHUB_REPOSITORY=o/r NOW_EPOCH=abc bash "$SCRIPT" "$MAIN_SHA" "$HEAD_SHA") >"$WORK/out.txt" 2>&1
    RC=$?
    expect "今の時刻の形が違えば 2 で終わる" 2 has-out "::error::今の時刻の形が違います: abc"
fi

if [ "$RAN" -eq 0 ]; then
    echo "FAIL: KP_TEST_CASE=${CASE} に当たる場合がありません"
    exit 1
fi
if [ "$FAILED" -ne 0 ]; then
    echo "check-go-release-age.sh のテストに失敗がありました"
    exit 1
fi
echo "check-go-release-age.sh のテストはすべて通りました"
