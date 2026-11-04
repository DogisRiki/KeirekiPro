# shellcheck shell=bash
# =====================================================================
# CI の道具の版の行を探して書き換えるライブラリ
# (ci-tool-version-update.sh / check-ci-tool-placement.sh /
#  check-ci-tool-release-age.sh から source して使う)
#
# なぜ版の読み方を1か所にまとめるか:
#   週1回の実行と2つの検査が別々に版を読むと、検査が通るのに週1回の実行が
#   書き換えを漏らすことがある。版を読むときも書き換えるときも、このライブラリの
#   関数だけを使う。
#
# このライブラリは外部に問い合わせない。source しても何もしない。関数を定義する
# だけで、シェルの設定(set -e など)と trap を変えない。関数は exit せず、
# 戻り値で成否を返す。失敗の説明は標準エラーに出す。
#
# 関数と戻り値:
#   civ_scan <根のフォルダ>
#     <根>/.github/workflows/*.yml と *.yaml、<根>/.github/actions/*/action.yml と
#     action.yaml を読み、版の行を1行に1つずつ「ファイル<TAB>行番号<TAB>名前<TAB>版」
#     の形で出す。ファイルは根のフォルダからの相対の形で出す。見つける行は次の5種類。
#       1. 名前が version か tag か release を含み(大文字と小文字は区別しない)、
#          値が ^v?[0-9]+(\.[0-9]+)*$ に当たる「名前: 値」の行。値の前後の引用符は外す
#       2. docker run / pull / create の行と、名前が image か container の行にある
#          <イメージ>:<タグ> の語。タグは ^v?[0-9]+(\.[0-9]+)* で始まるものに限る。
#          docker の行では、値に : を書く引数(-p --publish -v ...)の値を除く。
#          \ で次の行に続く行は、続きの行までを1つの行として読み、行番号は語のある行にする
#       3. npm npx pnpm yarn pip pipx go install gem cargo uvx bunx の行にある
#          <パッケージ>@<版> か <パッケージ>==<版> の語
#       4. apt-get install / apt install / apk add / yum install / dnf install の行にある
#          <パッケージ>=<版> の語
#       5. curl / wget の行の URL の版の区切りと、gh release download の版
#     uses: の行、# で始まるコメントの行、${{ を含む行は読まない。
#     0 = 読めた / 2 = 根のフォルダが無いか、ファイルを読めない
#
#   以下の関数は <根>/.github/ci-tool-versions.json(データのファイル)を読む。
#   データのファイルが無いか JSON として読めないとき、道具がデータのファイルに
#   無いときは、どの関数も理由を標準エラーに出して 2 を返す。
#
#   civ_tool_versions <根のフォルダ> <道具>
#     道具の ci の組ごとに、見つけた版を「ファイル<TAB>行番号<TAB>版」で出す。
#     組に当たる行が1つも無いときは「ファイル<TAB>-<TAB>-」を出す。
#   civ_dev_from <根のフォルダ> <道具>
#     開発環境の FROM の行のうち、データのファイルの image で始まる最初の行から
#     「版<TAB>タグ<TAB>digest」を出す(digest が無ければ -)。ほかのイメージの
#     FROM の行(docker/terraform/Dockerfile の tflint など)は読まない。
#     開発環境の無い道具では何も出さず 0 を返す。
#   civ_rewrite_ci <根のフォルダ> <道具> <版>
#     道具の ci の組が指す行の版の値だけを書き換える。値を囲む引用符は残す。
#     当たる行の無い組があれば、どのファイルも変えずに 2 を返す。
#   civ_rewrite_dev <根のフォルダ> <道具> <版> <digest>
#     開発環境の FROM の行の語を <image>:<版><tag_suffix>@<digest> に替える。
#     AS などの、語のあとの文字は残す。
#   書き換えの2つの関数は、版が ^[0-9]+\.[0-9]+\.[0-9]+$ に、digest が
#   ^sha256:[0-9a-f]{64}$ に当たらなければ、ファイルを変えずに 2 を返す。
#
#   civ_gt <版a> <版b>
#     先頭の v を外し、. で分けた数字を左から比べる。版a が新しければ 0、
#     そうでなければ 1、版の形が違えば 2。
#   civ_major <版>
#     先頭の v を外した版の、最初の数字を出す。版の形が違えば 2。
#
# テスト: .github/scripts/tests/test-lib-ci-tool-versions.sh
# =====================================================================

# civ_scan が1つのファイルに使う awk のプログラム。変数 file に、出力に書くファイルの名前を渡す。
_CIV_SCAN_AWK=$(
    cat <<'AWK'
function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t\r]+$/, "", s); return s }
function emit(ln, name, ver) { printf "%s\t%d\t%s\t%s\n", file, ln, name, ver }
function isver(v) { return v ~ /^v?[0-9]+(\.[0-9]+)*$/ }
function startsver(v) { return v ~ /^v?[0-9]+(\.[0-9]+)*/ }
function unquote(s) { gsub(/["'();]/, "", s); return s }

# <イメージ>:<タグ> の語なら、イメージの名前とタグを出す。digest(@sha256:...)は外す。
function imgtag(w, ln,   img, tag, p) {
    w = unquote(w)
    sub(/@sha256:[0-9a-fA-F]*$/, "", w)
    if (w !~ /^([A-Za-z0-9.-]+(:[0-9]+)?\/)?[A-Za-z0-9._\/-]+:[^:\/@]+$/) return
    p = length(w)
    while (p > 0 && substr(w, p, 1) != ":") p--
    img = substr(w, 1, p - 1)
    tag = substr(w, p + 1)
    if (img != "" && startsver(tag)) emit(ln, img, tag)
}

# 「名前: 値」の行を読む。名前が image か container なら値をイメージとして読む。
function namevalue(s, ln,   name, val, lname) {
    if (!match(s, /^[ \t]*(-[ \t]+)?[A-Za-z0-9_.\/-]+[ \t]*:([ \t]|$)/)) return
    name = substr(s, 1, RLENGTH)
    val = substr(s, RLENGTH + 1)
    sub(/^[ \t]*(-[ \t]+)?/, "", name)
    sub(/[ \t]*:[ \t]*$/, "", name)
    sub(/[ \t]+#.*$/, "", val)
    val = trim(val)
    if (val ~ /^".*"$/ || val ~ /^'.*'$/) val = substr(val, 2, length(val) - 2)
    lname = tolower(name)
    if (lname == "image" || lname == "container") { imgtag(val, ln); return }
    if (lname ~ /version|tag|release/ && isver(val)) emit(ln, name, val)
}

# docker の行で、次の語を値に取る引数か。
function dockerarg(w) {
    return w ~ /^(-p|--publish|-v|--volume|--mount|-e|--env|--add-host|--device|--tmpfs|--expose|--link|--security-opt)$/
}
function dockerargeq(w) {
    return w ~ /^(--publish|--volume|--mount|--env|--add-host|--device|--tmpfs|--expose|--link|--security-opt)=/
}

# URL の版の区切りを出す。名前は GitHub なら <持ち主>/<リポジトリ>、ほかは版の前のホストとパス。
function urlver(w, ln,   n, seg, k, name, j) {
    w = unquote(w)
    if (w !~ /^[A-Za-z]+:\/\//) return
    sub(/^[A-Za-z]+:\/\//, "", w)
    sub(/[?#].*$/, "", w)
    n = split(w, seg, "/")
    for (k = 2; k <= n; k++) {
        if (seg[k] !~ /^v?[0-9]+(\.[0-9]+)+$/) continue
        if (seg[1] == "github.com" && n >= 3) {
            name = seg[2] "/" seg[3]
        } else {
            name = seg[1]
            for (j = 2; j < k; j++) name = name "/" seg[j]
        }
        emit(ln, name, seg[k])
    }
}

# 1つの行(\ で続く行はまとめた行)の語を読む。W[i] が語、L[i] がその語のある行番号。
function logical(   i, w, isdocker, ispkg, isapt, isfetch, isghrel, repo, p, pkg, ver) {
    isdocker = ispkg = isapt = isfetch = isghrel = 0
    repo = "-"
    for (i = 1; i <= nw; i++) {
        w = W[i]
        if (w == "docker" && W[i + 1] ~ /^(run|pull|create)$/) isdocker = 1
        if (w ~ /^(npm|npx|pnpm|yarn|pip|pipx|gem|cargo|uvx|bunx)$/) ispkg = 1
        if (w == "go" && W[i + 1] == "install") ispkg = 1
        if (w ~ /^(apt-get|apt|yum|dnf)$/ && sawafter(i, "install")) isapt = 1
        if (w == "apk" && sawafter(i, "add")) isapt = 1
        if (w == "curl" || w == "wget") isfetch = 1
        if (w == "gh" && W[i + 1] == "release" && W[i + 2] == "download") isghrel = 1
        if ((w == "--repo" || w == "-R") && i < nw) repo = unquote(W[i + 1])
        if (w ~ /^--repo=/) { repo = unquote(w); sub(/^--repo=/, "", repo) }
    }
    for (i = 1; i <= nw; i++) {
        w = W[i]
        if (isdocker) {
            if (dockerarg(w)) { i++; continue }
            if (!dockerargeq(w)) imgtag(w, L[i])
        }
        if (ispkg) {
            p = unquote(w)
            if (p ~ /^@?[A-Za-z0-9._\/-]+@[^@\/]+$/) {
                ver = p; sub(/^.*@/, "", ver)
                pkg = substr(p, 1, length(p) - length(ver) - 1)
                if (pkg != "" && startsver(ver)) emit(L[i], pkg, ver)
            } else if (p ~ /^[A-Za-z0-9._-]+(\[[^]]*\])?==[^=]+$/) {
                ver = p; sub(/^.*==/, "", ver)
                pkg = substr(p, 1, length(p) - length(ver) - 2)
                if (startsver(ver)) emit(L[i], pkg, ver)
            }
        }
        if (isapt) {
            p = unquote(w)
            if (p ~ /^[A-Za-z0-9][A-Za-z0-9.+_:-]*=[^=]+$/) {
                ver = p; sub(/^[^=]*=/, "", ver)
                pkg = substr(p, 1, length(p) - length(ver) - 1)
                if (startsver(ver)) emit(L[i], pkg, ver)
            }
        }
        if (isfetch) urlver(w, L[i])
        if (isghrel && unquote(w) ~ /^v?[0-9]+(\.[0-9]+)+$/) emit(L[i], repo, unquote(w))
    }
}
function sawafter(i, want,   j) {
    for (j = i + 1; j <= nw; j++) if (W[j] == want) return 1
    return 0
}

{
    line = $0
    sub(/\r$/, "", line)
    skip = (line ~ /^[ \t]*#/) || index(line, "${{") > 0 || (line ~ /^[ \t]*(-[ \t]+)?uses[ \t]*:/)
    cont = (line ~ /\\[ \t]*$/)
    if (cont) sub(/\\[ \t]*$/, "", line)
    if (!skip) {
        if (!incont) namevalue(line, NR)
        n = split(line, parts, /[ \t]+/)
        for (k = 1; k <= n; k++) {
            if (parts[k] == "") continue
            nw++
            W[nw] = parts[k]
            L[nw] = NR
        }
    }
    if (!cont) {
        if (nw > 0) logical()
        for (k = 1; k <= nw; k++) { delete W[k]; delete L[k] }
        nw = 0
    }
    incont = cont
}
END { if (nw > 0) logical() }
AWK
)

civ_scan() {
    local root="${1:-}" f rel
    if [ -z "$root" ] || [ ! -d "$root" ]; then
        echo "civ_scan: 根のフォルダがありません: ${root}" >&2
        return 2
    fi
    while IFS= read -r f; do
        [ -f "$f" ] || continue
        rel="${f#"$root"/}"
        if ! awk -v file="$rel" "$_CIV_SCAN_AWK" "$f"; then
            echo "civ_scan: ${rel} を読めませんでした" >&2
            return 2
        fi
    done < <(
        for f in "$root"/.github/workflows/*.yml "$root"/.github/workflows/*.yaml \
            "$root"/.github/actions/*/action.yml "$root"/.github/actions/*/action.yaml; do
            [ -f "$f" ] && printf '%s\n' "$f"
        done | LC_ALL=C sort
    )
    return 0
}

# データのファイルのパスを出す。無いか JSON として読めなければ、理由を出して 2 を返す。
_civ_data() {
    local data="${1:-}/.github/ci-tool-versions.json"
    if [ ! -f "$data" ]; then
        echo "lib-ci-tool-versions: データのファイルがありません: ${data}" >&2
        return 2
    fi
    if ! jq -e '.tools | type == "object"' "$data" >/dev/null 2>&1; then
        echo "lib-ci-tool-versions: データのファイルを JSON として読めません: ${data}" >&2
        return 2
    fi
    printf '%s\n' "$data"
}

# 道具がデータのファイルにあるかを確かめる。無ければ、理由を出して 2 を返す。
_civ_tool() {
    if ! jq -e --arg t "$2" '.tools[$t] | type == "object"' "$1" >/dev/null 2>&1; then
        echo "lib-ci-tool-versions: データのファイルに道具 ${2} がありません" >&2
        return 2
    fi
}

# 道具の ci の組ごとに、見つけた版の行を「ファイル<TAB>行番号<TAB>名前<TAB>版」で出す。
# 組に当たる行が無いときは「ファイル<TAB>-<TAB>名前<TAB>-」を出す。
_civ_pair_lines() {
    local root="$1" tool="$2" data pairs scan f k found
    data=$(_civ_data "$root") || return 2
    _civ_tool "$data" "$tool" || return 2
    pairs=$(jq -r --arg t "$tool" '[.tools[$t].ci[]? | [.file, .key]] | unique | .[] | @tsv' "$data") || return 2
    scan=$(civ_scan "$root") || return 2
    while IFS="$(printf '\t')" read -r f k; do
        [ -n "$f" ] || continue
        found=$(printf '%s\n' "$scan" | awk -F '\t' -v f="$f" -v k="$k" '$1 == f && $3 == k')
        if [ -n "$found" ]; then
            printf '%s\n' "$found"
        else
            printf '%s\t-\t%s\t-\n' "$f" "$k"
        fi
    done <<<"$pairs"
}

# 開発環境の書き場所を「ファイル<TAB>イメージ<TAB>タグの後ろの文字」で出す。無ければ何も出さない。
_civ_dev() {
    jq -r --arg t "$2" '.tools[$t].dev // empty | [.file, .image, .tag_suffix // ""] | @tsv' "$1"
}

civ_tool_versions() {
    local lines
    lines=$(_civ_pair_lines "${1:-}" "${2:-}") || return 2
    printf '%s\n' "$lines" | awk -F '\t' 'NF { print $1 "\t" $2 "\t" $4 }'
}

civ_dev_from() {
    local root="${1:-}" tool="${2:-}" data dev file image suffix ref tag digest ver
    data=$(_civ_data "$root") || return 2
    _civ_tool "$data" "$tool" || return 2
    dev=$(_civ_dev "$data" "$tool") || return 2
    [ -n "$dev" ] || return 0
    IFS="$(printf '\t')" read -r file image suffix <<<"$dev"
    ref=$(awk -v img="$image" '$1 == "FROM" && index($2, img ":") == 1 { print $2; exit }' "$root/$file" 2>/dev/null)
    if [ -z "$ref" ]; then
        echo "lib-ci-tool-versions: ${file} に FROM ${image}: の行がありません" >&2
        return 2
    fi
    ref="${ref#"$image":}"
    tag="${ref%%@*}"
    digest="-"
    [ "$tag" != "$ref" ] && digest="${ref#*@}"
    ver="${tag%"$suffix"}"
    if [ -n "$suffix" ] && [ "$ver" = "$tag" ]; then
        echo "lib-ci-tool-versions: ${file} の FROM のタグ ${tag} が ${suffix} で終わっていません" >&2
        return 2
    fi
    printf '%s\t%s\t%s\n' "$ver" "$tag" "$digest"
}

# 書き換えに渡された版を確かめる。形が違えば、理由を出して 2 を返す。
_civ_check_ver() {
    if ! [[ "${1:-}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo "lib-ci-tool-versions: 版の形が違います: ${1:-}" >&2
        return 2
    fi
}

# ファイルの行番号の行で、名前より後ろにある最初の古い版を新しい版に替える。
_civ_rewrite_line() {
    local file="$1" ln="$2" key="$3" old="$4" new="$5" tmp="$1.civ-tmp"
    if ! awk -v ln="$ln" -v key="$key" -v old="$old" -v new="$new" '
        NR == ln {
            p = index($0, key)
            if (p > 0) {
                head = substr($0, 1, p + length(key) - 1)
                rest = substr($0, p + length(key))
                q = index(rest, old)
                if (q > 0) {
                    $0 = head substr(rest, 1, q - 1) new substr(rest, q + length(old))
                    done = 1
                }
            }
        }
        { print }
        END { if (!done) exit 3 }' "$file" >"$tmp"; then
        rm -f "$tmp"
        echo "lib-ci-tool-versions: ${file} の ${ln} 行目の ${key} の版を書き換えられませんでした" >&2
        return 2
    fi
    cat "$tmp" >"$file" && rm -f "$tmp"
}

civ_rewrite_ci() {
    local root="${1:-}" tool="${2:-}" ver="${3:-}" lines f ln k old
    _civ_check_ver "$ver" || return 2
    lines=$(_civ_pair_lines "$root" "$tool") || return 2
    # 書き換える前に、どの組にも行があることを確かめる。一部だけ書き換わるのを防ぐため。
    if printf '%s\n' "$lines" | awk -F '\t' '$2 == "-" { bad = 1 } END { exit !bad }'; then
        echo "lib-ci-tool-versions: ${tool} の書き場所に当たる行の無いファイルがあります" >&2
        return 2
    fi
    while IFS="$(printf '\t')" read -r f ln k old; do
        [ -n "$f" ] || continue
        _civ_rewrite_line "$root/$f" "$ln" "$k" "$old" "$ver" || return 2
    done <<<"$lines"
}

civ_rewrite_dev() {
    local root="${1:-}" tool="${2:-}" ver="${3:-}" digest="${4:-}" data dev file image suffix tmp
    _civ_check_ver "$ver" || return 2
    if ! [[ "$digest" =~ ^sha256:[0-9a-f]{64}$ ]]; then
        echo "lib-ci-tool-versions: digest の形が違います: ${digest}" >&2
        return 2
    fi
    data=$(_civ_data "$root") || return 2
    _civ_tool "$data" "$tool" || return 2
    dev=$(_civ_dev "$data" "$tool") || return 2
    if [ -z "$dev" ]; then
        echo "lib-ci-tool-versions: ${tool} には開発環境の書き場所がありません" >&2
        return 2
    fi
    IFS="$(printf '\t')" read -r file image suffix <<<"$dev"
    tmp="$root/$file.civ-tmp"
    if ! awk -v img="$image" -v ref="$image:$ver$suffix@$digest" '
        !done && $1 == "FROM" && index($2, img ":") == 1 {
            p = index($0, $2)
            $0 = substr($0, 1, p - 1) ref substr($0, p + length($2))
            done = 1
        }
        { print }
        END { if (!done) exit 3 }' "$root/$file" >"$tmp" 2>/dev/null; then
        rm -f "$tmp"
        echo "lib-ci-tool-versions: ${file} に FROM ${image}: の行がありません" >&2
        return 2
    fi
    cat "$tmp" >"$root/$file" && rm -f "$tmp"
}

civ_gt() {
    local a="${1#v}" b="${2#v}" i x y
    local -a pa pb
    if ! [[ "$a" =~ ^[0-9]+(\.[0-9]+)*$ ]] || ! [[ "$b" =~ ^[0-9]+(\.[0-9]+)*$ ]]; then
        echo "civ_gt: 版の形が違います: ${1:-} ${2:-}" >&2
        return 2
    fi
    IFS=. read -r -a pa <<<"$a"
    IFS=. read -r -a pb <<<"$b"
    for ((i = 0; i < ${#pa[@]} || i < ${#pb[@]}; i++)); do
        x=$((10#${pa[i]:-0}))
        y=$((10#${pb[i]:-0}))
        [ "$x" -gt "$y" ] && return 0
        [ "$x" -lt "$y" ] && return 1
    done
    return 1
}

civ_major() {
    local v="${1#v}"
    if ! [[ "$v" =~ ^[0-9]+(\.[0-9]+)*$ ]]; then
        echo "civ_major: 版の形が違います: ${1:-}" >&2
        return 2
    fi
    printf '%s\n' "${v%%.*}"
}
