# shellcheck shell=bash
# =====================================================================
# Go の版を読み、その版を Go の配布元が公開した日時を調べるライブラリ
# (Go の版の公開からの時間の検査から source して使う)
#
# Go の版を読む場所(go_release_is_target と go_release_versions_of):
#   - go.mod の go の行と toolchain の行。go の行の版が「1.27」のように
#     2つの数だけのときは、「1.27.0」として読む
#   - Dockerfile(名前が Dockerfile、Dockerfile.<何か>、<何か>.Dockerfile のファイル)の
#     FROM の行のうち、イメージが golang のもの。タグの頭の版を読む
#     (例: golang:1.27.4-trixie@sha256:... は 1.27.4)
#   版を読めない書き方(タグの無い golang、golang:1.27-trixie のように版が決まらないタグ、
#   go で始まらない toolchain の行)は、頭に ? を付けて、書き方そのものを出す。
#
# 公開日時の取り方(go_release_published):
#   Go の配布元(https://go.dev/dl/)の go<版>.linux-amd64.tar.gz と go<版>.linux-arm64.tar.gz
#   (CI と本番が使う2つ)を HEAD で問い合わせ、転送先の dl.google.com が返す Last-Modified を
#   読む。2つのうち新しい方を公開日時とする。どちらかが 404 なら、配布元に無い版とする。
#
# なぜ golang.org/toolchain のモジュールの時刻を使わないか:
#   2026-11-14 に、go1.27.4 で次のことを確かめた。
#   - proxy.golang.org の .info の Time は 2026-11-02T20:36:20Z だった。配布物の Last-Modified
#     (2026-11-10 16:48:48 GMT)と go1.27.4 のタグのコミット(2026-11-10T16:47:23Z)より
#     8日早く、公開日時より古い時刻を返す
#   - Go のモジュールの索引(index.golang.org)を 2026-11-02T20:30Z から 2026-11-04T15:11Z まで
#     読んでも、golang.org/toolchain の go1.27.4 の行が無かった。lib-gomod-index.sh は、
#     読んだ範囲に無い版を古い版とするので、この索引で調べると公開直後の版を通してしまう
#
# 環境変数: GO_DL_BASE(既定 https://go.dev/dl。テストが差し替える)
# テスト: .github/scripts/tests/test-lib-go-release.sh
# =====================================================================

GO_DL_BASE="${GO_DL_BASE:-https://go.dev/dl}"
GO_RELEASE_PLATFORMS="linux-amd64 linux-arm64"

# 使い方: go_release_http_epoch <HTTP の日時>。「Tue, 10 Nov 2026 16:48:48 GMT」の形を
# 1970-01-01T00:00:00Z からの秒にする。形が違えば 1 を返す
go_release_http_epoch() {
    local d m y t mon
    read -r _ d m y t _ <<<"$1"
    mon=$(awk -v m="$m" 'BEGIN { i = index("JanFebMarAprMayJunJulAugSepOctNovDec", m); if (length(m) == 3 && i % 3 == 1) printf "%02d", (i + 2) / 3 }')
    [[ "$d" =~ ^[0-9]{1,2}$ && -n "$mon" && "$y" =~ ^[0-9]{4}$ && "$t" =~ ^[0-9]{2}:[0-9]{2}:[0-9]{2}$ ]] || return 1
    jq -n -r --arg s "$(printf '%s-%s-%02dT%sZ' "$y" "$mon" "$((10#$d))" "$t")" '$s | fromdateiso8601'
}

# 使い方: go_release_is_target <パス>。Go の版を読むファイルなら 0
go_release_is_target() {
    local b="${1##*/}"
    [ "$b" = go.mod ] && return 0
    [[ "$b" =~ ^Dockerfile(\..+)?$ ]] && return 0
    [[ "$b" =~ \.[Dd]ockerfile$ ]] && return 0
    return 1
}

# 使い方: go_release_versions_of <ファイルの名前(パスの最後の部分)>。標準入力のファイルの中身から、
# Go の版を1行に1つ出す。版を読めない書き方は、頭に ? を付けて、書き方そのものを出す
go_release_versions_of() {
    local b="${1##*/}"
    if [ "$b" = go.mod ]; then
        awk '
            { sub(/\r$/, ""); sub(/\/\/.*/, "") }
            $1 == "go" && NF >= 2 {
                v = $2
                if (v ~ /^[0-9]+\.[0-9]+$/) v = v ".0"
                if (v ~ /^[0-9]+\.[0-9]+(\.[0-9]+|(rc|beta)[0-9]+)$/) print v
                else print "?go " $2
            }
            $1 == "toolchain" && NF >= 2 {
                v = $2
                if (v ~ /^go[0-9]+\.[0-9]+(\.[0-9]+|(rc|beta)[0-9]+)$/) print substr(v, 3)
                else print "?toolchain " $2
            }'
    else
        awk '
            { sub(/\r$/, "") }
            toupper($1) == "FROM" {
                ref = ""
                for (i = 2; i <= NF; i++) if ($i !~ /^--/) { ref = $i; break }
                if (ref == "") next
                name = ref; tag = ""
                at = index(name, "@"); if (at > 0) name = substr(name, 1, at - 1)
                # 最後の / より後ろの : から後ろがタグ(レジストリのポートの : と見分ける)
                slash = 0
                for (i = length(name); i > 0; i--) if (substr(name, i, 1) == "/") { slash = i; break }
                rest = substr(name, slash + 1)
                colon = index(rest, ":")
                if (colon > 0) { tag = substr(rest, colon + 1); name = substr(name, 1, slash + colon - 1) }
                sub(/^(docker\.io|index\.docker\.io|registry-1\.docker\.io)\//, "", name)
                sub(/^library\//, "", name)
                if (name != "golang") next
                v = tag; sub(/-.*/, "", v)
                if (v ~ /^[0-9]+\.[0-9]+(\.[0-9]+|(rc|beta)[0-9]+)$/) print v
                else print "?" ref
            }'
    fi
}

# 使い方: go_release_published <版>。配布物の公開日時を 1970-01-01T00:00:00Z からの秒で出す。
# 取れなければ、理由を標準エラーに出して 1 を返す
go_release_published() {
    local v="$1" w p url code ce lm e latest=0 rc=0
    w=$(mktemp -d) || return 1
    for p in $GO_RELEASE_PLATFORMS; do
        url="${GO_DL_BASE}/go${v}.${p}.tar.gz"
        code=$(curl -sS -I -L --max-time 60 --retry 2 -o "$w/body" -D "$w/hdr" -w '%{http_code}' "$url" 2>"$w/cerr") || code="000"
        case "$code" in
        200) ;;
        404 | 410)
            echo "配布元にこの版が無い(${url} が HTTP ${code} を返した)" >&2
            rc=1
            break
            ;;
        *)
            ce=$(head -n 1 "$w/cerr")
            echo "配布元に問い合わせられなかった(${url}: HTTP ${code}${ce:+ ${ce}})" >&2
            rc=1
            break
            ;;
        esac
        # 転送のあとの最後の応答の Last-Modified を読む
        lm=$(tr -d '\r' <"$w/hdr" | awk 'tolower($0) ~ /^http\// { v = "" } tolower($1) == "last-modified:" { sub(/^[^:]*:[ \t]*/, ""); v = $0 } END { print v }')
        if [ -z "$lm" ] || ! e=$(go_release_http_epoch "$lm") || ! [[ "$e" =~ ^[0-9]+$ ]]; then
            echo "配布元の応答の公開日時を読めなかった(${url} の Last-Modified: ${lm:-無し})" >&2
            rc=1
            break
        fi
        [ "$e" -le "$latest" ] || latest="$e"
    done
    rm -rf "$w"
    [ "$rc" -eq 0 ] || return 1
    echo "$latest"
}
