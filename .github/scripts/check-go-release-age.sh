#!/usr/bin/env bash
# =====================================================================
# Go の版の公開からの時間の検査(dependency-review の cooldown から実行)
#
# 判定: PR の分かれ目のコミットと head で、リポジトリの中に書いた Go の版を比べ、
#   head で新しく使う版ごとに、公開から72時間経っているかを調べる。72時間経っていない版と、
#   公開日時を取れなかった版と、配布元に無い版と、版を読めない書き方を止める。
#   分かれ目のコミットとは、PR のブランチを main から分けたときの main のコミット
#   (base と head の merge-base)である。
#
# なぜ必要か:
#   check-dependency-cooldown.sh は、依存グラフの差分に出る部品(Go のモジュールを含む)を
#   調べる。Go 自体の版(go.mod の toolchain の行と、Dockerfile の golang のイメージのタグ)は
#   依存グラフに出ないので、公開直後の Go の版に上げる PR が検査を通っていた。
#
# Go の版を読む場所:
#   - git が管理する go.mod の go の行と toolchain の行。go の行の版が「1.27」のように
#     2つの数だけのときは、「1.27.0」として調べる
#   - git が管理する Dockerfile(名前が Dockerfile、Dockerfile.<何か>、<何か>.Dockerfile の
#     ファイル)の FROM の行のうち、イメージが golang のもの。タグの頭の版を読む
#     (例: golang:1.27.4-trixie@sha256:... は 1.27.4)
#   版を読めない書き方(タグの無い golang、golang:1.27-trixie のように版が決まらないタグ、
#   go で始まらない toolchain の行)は、その書き方そのものを1つの版として扱う。
#   head で新しく現れた書き方は、公開日時を調べられないので止める。
#
# 新しく使う版の見つけ方:
#   head のどこかに書いた版のうち、分かれ目のコミットのどこにも書いていない版を、
#   新しく使う版とする。分かれ目のコミットで使っていた版を別のファイルに書き足しただけの
#   PR では、配布元に問い合わせない。分かれ目に無いファイルは、版の無いファイルとして扱う。
#   Go の版が変わらなければ、配布元に問い合わせずに 0 で終わる。
#
# 公開日時の取り方:
#   Go の配布元(https://go.dev/dl/)の go<版>.linux-amd64.tar.gz と go<版>.linux-arm64.tar.gz
#   (CI と本番が使う2つ)を HEAD で問い合わせ、転送先の dl.google.com が返す Last-Modified を
#   読む。2つのうち新しい方を公開日時とする。どちらかが 404 なら、配布元に無い版として止める。
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
# 例外: この検査には、72時間待たずに通す例外が無い。止めたときは、入るようになる時刻を
#   過ぎてから、ジョブを Re-run する。
#
# 出力: 新しく使う版ごとに、版、書いた場所、公開日時、入るようになる時刻、結果の表を
#   GITHUB_STEP_SUMMARY と標準出力に書く。72時間経っていないので止めた版ごとに
#   「::error::72時間の待ちで止めた部品: Go <版>。理由: …。入るようになる時刻: …」の行を出す
#   (/ship がこの行から止めた版と時刻を読む。check-dependency-cooldown.sh と同じ形)。
#   ほかの理由で止めた版には、この形でない ::error:: の行を出す。
#
# 終了コード: 0 = 止めた版が無い / 1 = 止めた版があるか、分かれ目のコミットを取れない /
#   2 = 引数か環境変数の形が違う
#
# テスト: .github/scripts/tests/test-check-go-release-age.sh
# 環境変数: GH_TOKEN GITHUB_REPOSITORY GITHUB_STEP_SUMMARY(無ければ標準出力にだけ書く)
#   COOLDOWN_HOURS(既定 72) NOW_EPOCH(テスト用の時刻の固定)
#   GO_DL_BASE(既定 https://go.dev/dl。テストが差し替える)
# 使い方: check-go-release-age.sh <base> <head>(今のフォルダを head の根とする)
# =====================================================================
set -uo pipefail

BASE_SHA="${1:-}"
HEAD_SHA="${2:-}"
REPO="${GITHUB_REPOSITORY:-}"
SUMMARY="${GITHUB_STEP_SUMMARY:-/dev/null}"
COOLDOWN_HOURS="${COOLDOWN_HOURS:-72}"
NOW_EPOCH="${NOW_EPOCH:-$(date -u +%s)}"
GO_DL_BASE="${GO_DL_BASE:-https://go.dev/dl}"
PLATFORMS="linux-amd64 linux-arm64"

usage() {
    echo "::error::$1(使い方: check-go-release-age.sh <base> <head>。環境変数 GITHUB_REPOSITORY が要ります)"
    exit 2
}
[[ "$BASE_SHA" =~ ^[0-9a-f]{7,40}$ ]] || usage "base の形が違います: ${BASE_SHA}"
[[ "$HEAD_SHA" =~ ^[0-9a-f]{7,40}$ ]] || usage "head の形が違います: ${HEAD_SHA}"
[[ "$REPO" =~ ^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$ ]] || usage "GITHUB_REPOSITORY の形が違います: ${REPO}"
[[ "$COOLDOWN_HOURS" =~ ^[1-9][0-9]*$ ]] || usage "COOLDOWN_HOURS が正の整数ではありません: ${COOLDOWN_HOURS}"
[[ "$NOW_EPOCH" =~ ^[0-9]+$ ]] || usage "NOW_EPOCH が整数ではありません: ${NOW_EPOCH}"

TMP=$(mktemp -d) || exit 2
[ -n "$TMP" ] && [ -d "$TMP" ] || exit 2
trap 'rm -rf "$TMP"' EXIT

# 使い方: err <文>。::error:: の行を出す。% は GitHub の書式で %25 にする
err() {
    echo "::error::${1//%/%25}"
}

# 使い方: utc <1970-01-01T00:00:00Z からの秒>。「YYYY-MM-DD HH:MM UTC」の形で出す
utc() {
    jq -n -r --argjson t "$1" '$t | strftime("%Y-%m-%d %H:%M UTC")'
}

# 使い方: cell <文字列>。表のマスに入れる。縦棒は表の区切りと読まれないように逃がす
cell() {
    printf '%s' "$1" | sed 's/|/\\|/g'
}

# 使い方: http_epoch <HTTP の日時>。「Tue, 10 Nov 2026 16:48:48 GMT」の形を
# 1970-01-01T00:00:00Z からの秒にする。形が違えば 1 を返す
http_epoch() {
    local d m y t mon
    read -r _ d m y t _ <<<"$1"
    mon=$(awk -v m="$m" 'BEGIN { i = index("JanFebMarAprMayJunJulAugSepOctNovDec", m); if (length(m) == 3 && i % 3 == 1) printf "%02d", (i + 2) / 3 }')
    [[ "$d" =~ ^[0-9]{1,2}$ && -n "$mon" && "$y" =~ ^[0-9]{4}$ && "$t" =~ ^[0-9]{2}:[0-9]{2}:[0-9]{2}$ ]] || return 1
    jq -n -r --arg s "$(printf '%s-%s-%02dT%sZ' "$y" "$mon" "$((10#$d))" "$t")" '$s | fromdateiso8601'
}

# 使い方: is_target <パス>。Go の版を読むファイルなら 0
is_target() {
    local b="${1##*/}"
    [ "$b" = go.mod ] && return 0
    [[ "$b" =~ ^Dockerfile(\..+)?$ ]] && return 0
    [[ "$b" =~ \.[Dd]ockerfile$ ]] && return 0
    return 1
}

# 使い方: versions_of <ファイルの名前(パスの最後の部分)>。標準入力のファイルの中身から、Go の版を1行に1つ出す。
# 版を読めない書き方は、頭に ? を付けて、書き方そのものを出す
versions_of() {
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

# --- 分かれ目のコミットを取る -----------------------------------------------
if ! gh api "repos/${REPO}/compare/${BASE_SHA}...${HEAD_SHA}" >"$TMP/compare.json" 2>"$TMP/err"; then
    err "分かれ目のコミットを取れませんでした(比較の API が失敗しました: $(head -n 1 "$TMP/err"))。ジョブを Re-run してください"
    exit 1
fi
MB=$(jq -r '.merge_base_commit.sha? // empty' "$TMP/compare.json" 2>/dev/null)
if ! [[ "$MB" =~ ^[0-9a-f]{40}$ ]]; then
    err "分かれ目のコミットを取れませんでした(比較の API の応答に merge_base_commit.sha がありません)"
    exit 1
fi
if ! git fetch --quiet --no-tags --depth=1 origin "$MB" 2>"$TMP/err"; then
    err "分かれ目のコミット ${MB} を取れませんでした(git fetch が失敗しました: $(head -n 1 "$TMP/err"))"
    exit 1
fi

# --- 両方の Go の版を読む ---------------------------------------------------
# 「版<TAB>パス」を1行ずつ書く
: >"$TMP/head.tsv"
: >"$TMP/base.tsv"
if ! git ls-files -z >"$TMP/head.files" 2>"$TMP/err"; then
    err "head のファイルの一覧を読めませんでした: $(head -n 1 "$TMP/err")"
    exit 1
fi
while IFS= read -r -d '' f; do
    is_target "$f" || continue
    [ -f "$f" ] || continue
    versions_of "${f##*/}" <"$f" | awk -v f="$f" 'NF { print $0 "\t" f }' >>"$TMP/head.tsv"
done <"$TMP/head.files"
if ! git ls-tree -r -z --name-only "$MB" >"$TMP/base.files" 2>"$TMP/err"; then
    err "分かれ目のコミット ${MB} のファイルの一覧を読めませんでした: $(head -n 1 "$TMP/err")"
    exit 1
fi
while IFS= read -r -d '' f; do
    is_target "$f" || continue
    if ! git show "${MB}:${f}" >"$TMP/blob" 2>"$TMP/err"; then
        err "分かれ目のコミット ${MB} の ${f} を読めませんでした: $(head -n 1 "$TMP/err")"
        exit 1
    fi
    versions_of "${f##*/}" <"$TMP/blob" | awk -v f="$f" 'NF { print $0 "\t" f }' >>"$TMP/base.tsv"
done <"$TMP/base.files"

# 新しく使う版を「版<TAB>書いた場所(, でつなぐ)」で書く。分かれ目に Go の版が1つも無いと
# base.tsv が空になり、NR == FNR では head の行を分かれ目の行と取り違えるので、ファイルの名前で分ける
awk -F '\t' '
    FILENAME == ARGV[1] { seen[$1] = 1; next }
    !($1 in seen) {
        if (!($1 in where)) { order[++n] = $1; where[$1] = $2 }
        else if (index(", " where[$1] ", ", ", " $2 ", ") == 0) where[$1] = where[$1] ", " $2
    }
    END { for (i = 1; i <= n; i++) print order[i] "\t" where[order[i]] }
' "$TMP/base.tsv" "$TMP/head.tsv" >"$TMP/new.tsv"

TITLE="## Go の版の公開からの時間の検査"
if [ ! -s "$TMP/new.tsv" ]; then
    echo "Go の版の公開からの時間の検査: 新しく使う Go の版はありません。"
    {
        echo "$TITLE"
        echo ""
        echo "新しく使う Go の版はありません。"
    } >>"$SUMMARY"
    exit 0
fi

# 使い方: published <版>。配布物の公開日時を 1970-01-01T00:00:00Z からの秒で出す。
# 取れなければ、止める理由を標準エラーに出して 1 を返す
published() {
    local v="$1" p url code ce lm e latest=0
    for p in $PLATFORMS; do
        url="${GO_DL_BASE}/go${v}.${p}.tar.gz"
        code=$(curl -sS -I -L --max-time 60 --retry 2 -o "$TMP/body" -D "$TMP/hdr" -w '%{http_code}' "$url" 2>"$TMP/cerr") || code="000"
        case "$code" in
        200) ;;
        404 | 410)
            echo "配布元にこの版が無い(${url} が HTTP ${code} を返した)" >&2
            return 1
            ;;
        *)
            ce=$(head -n 1 "$TMP/cerr")
            echo "配布元に問い合わせられなかった(${url}: HTTP ${code}${ce:+ ${ce}})" >&2
            return 1
            ;;
        esac
        # 転送のあとの最後の応答の Last-Modified を読む
        lm=$(tr -d '\r' <"$TMP/hdr" | awk 'tolower($0) ~ /^http\// { v = "" } tolower($1) == "last-modified:" { sub(/^[^:]*:[ \t]*/, ""); v = $0 } END { print v }')
        if [ -z "$lm" ] || ! e=$(http_epoch "$lm") || ! [[ "$e" =~ ^[0-9]+$ ]]; then
            echo "配布元の応答の公開日時を読めなかった(${url} の Last-Modified: ${lm:-無し})" >&2
            return 1
        fi
        [ "$e" -le "$latest" ] || latest="$e"
    done
    echo "$latest"
}

# --- 版ごとに判定する -------------------------------------------------------
{
    echo "$TITLE"
    echo ""
    echo "| 版 | 書いた場所 | 公開日時 | 入るようになる時刻 | 結果 |"
    echo "|---|---|---|---|---|"
} >"$TMP/table"
stopped=0
wait_s=$((COOLDOWN_HOURS * 3600))
while IFS=$'\t' read -r v places; do
    if [[ "$v" == \?* ]]; then
        shown="${v#\?}"
        printf '| %s | %s | 取れなかった | 取れなかった | 止めました(版を読めない書き方) |\n' \
            "$(cell "$shown")" "$(cell "$places")" >>"$TMP/table"
        err "Go の版を読めない書き方「${shown}」を止めました(${places})。golang:1.27.4-trixie や toolchain go1.27.4 のように、Go の版を3つの数で書いてください"
        stopped=1
        continue
    fi
    if ! pub=$(published "$v" 2>"$TMP/why"); then
        why=$(head -n 1 "$TMP/why")
        printf '| %s | %s | 取れなかった | 取れなかった | 止めました(%s) |\n' \
            "$v" "$(cell "$places")" "$(cell "$why")" >>"$TMP/table"
        err "Go の版 ${v} を止めました: ${why}(${places})。ジョブを Re-run してください"
        stopped=1
        continue
    fi
    pub_at=$(utc "$pub")
    # 分の端数を切り上げ、書いた時刻を過ぎれば通るようにする
    pass_at=$(utc "$(((pub + wait_s + 59) / 60 * 60))")
    if [ $((NOW_EPOCH - pub)) -lt "$wait_s" ]; then
        printf '| %s | %s | %s | %s | 止めました(公開から%s時間経っていない) |\n' \
            "$v" "$(cell "$places")" "$pub_at" "$pass_at" "$COOLDOWN_HOURS" >>"$TMP/table"
        err "${COOLDOWN_HOURS}時間の待ちで止めた部品: Go ${v}。理由: 公開から${COOLDOWN_HOURS}時間経っていない。入るようになる時刻: ${pass_at}"
        stopped=1
    else
        printf '| %s | %s | %s | %s | 通しました |\n' "$v" "$(cell "$places")" "$pub_at" "$pass_at" >>"$TMP/table"
    fi
done <"$TMP/new.tsv"

cat "$TMP/table" >>"$SUMMARY"
cat "$TMP/table"
[ "$stopped" -eq 0 ] || exit 1
exit 0
