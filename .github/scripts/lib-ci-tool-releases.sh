# shellcheck shell=bash
# =====================================================================
# CI の道具の配布元から版と公開日時を取るライブラリ
# (ci-tool-version-update.sh / check-ci-tool-release-age.sh から source して使う)
#
# 道具ごとの取り先:
#   node:      版の一覧は nodejs.org の dist/index.json。公開日時は GitHub の
#              repos/nodejs/node/releases/tags/v<版> の published_at
#   trivy:     版の一覧と公開日時は GitHub の repos/aquasecurity/trivy/releases の
#              tag_name と published_at
#   codex:     版の一覧と公開日時は npm の registry の @openai/codex の time
#   terraform: 版の一覧と公開日時は api.releases.hashicorp.com の version と
#              timestamp_created
#   公開日時の取り先は .claude/scripts/ci-tool-signature/verify-ci-tool.sh と同じにする。
#   同じ版の公開日時が、記録と検査で食い違わないようにするためである。
#   開発環境の FROM に書く配布元のイメージのタグの digest と公開日時は、Docker Hub の
#   v2/namespaces/<名前空間>/repositories/<名前>/tags/<タグ> の digest と tag_last_pushed
#
# なぜ Node.js の公開日時に index.json の date を使わないか:
#   date は日付だけの値で、公開より早いことがある。72時間の数え始めが早まらないよう、
#   GitHub のリリースの published_at を使う。
#
# なぜ一覧をページでたどるか:
#   Trivy の一覧は1ページに100件、Terraform の一覧は1回に20件しか返らない。今の版から
#   離れていても、あいだの版を欠かさないよう、今の版より古い版に届くまでたどる。
#   Trivy は30ページ、Terraform は50ページまでたどり、届かなければ途中までの一覧を
#   出さずに失敗する。あいだの版の欠けた一覧で、上げる先の版を決めないためである。
#
# なぜ日時の計算に date -d を使わないか:
#   date -d が読める日時の形は、GNU の date と busybox の date で違う。どちらの環境でも
#   同じ答えになるよう、暦の計算を bash の算術で行う。
# GitHub の API は gh api で呼び、ほかは curl -fsS --max-time 120 --retry 2 で呼ぶ。
# テストは、次の環境変数で URL の先頭を差し替え、PATH の先頭に偽の gh と curl を置く。
#   CTR_NODE_DIST_URL(既定 https://nodejs.org/dist)
#   CTR_NPM_REGISTRY(既定 https://registry.npmjs.org)
#   CTR_HASHICORP_API(既定 https://api.releases.hashicorp.com)
#   CTR_DOCKER_HUB(既定 https://hub.docker.com)
# 今の時刻は date +%s で取る。テストは、環境変数 NOW_EPOCH で今の時刻を与える。
#
# source しても何もしない。関数を定義するだけで、シェルの設定(set -e など)と
# trap を変えない。関数は exit せず、戻り値で成否を返す。版を比べる関数は
# 同じフォルダの lib-ci-tool-versions.sh のものを使う。
#
# 関数と戻り値:
#   ctr_list <道具> <今の版>
#     今の版より新しく、同じメジャー版の正式な版(^[0-9]+\.[0-9]+\.[0-9]+$)を、
#     「版<TAB>公開日時」の形で新しい順に出す。Trivy は prerelease と draft が false の
#     版に、Terraform は is_prerelease が false の版に限る。
#   ctr_published <道具> <版>
#     その版の公開日時を1行で出す。
#   ctr_notes_url <道具> <版>
#     その版の変更点の文書の URL を出す。
#   ctr_image <名前空間/名前> <タグ>
#     そのタグの digest と公開日時を「digest<TAB>公開日時」の形で出す。タグが無ければ、
#     理由に「HTTP 404。タグがありません」を書く。
#   公開日時は YYYY-MM-DDTHH:MM:SSZ の形にそろえる。
#   0 = 取れた / 1 = 問い合わせが失敗したか、応答が JSON として読めないか、欄が無いか、
#   一覧のページをたどりきれない
#   (標準エラーに「<道具> <版>: <取り先> から <欄> を取れませんでした(<理由>)」を出す。
#   ctr_image は、道具と版の代わりに、イメージの名前とタグを出す)
#   / 2 = 道具の名前か、版か、イメージの名前かタグの形が違う
#
#   ctr_age_ok <公開日時>
#     公開日時から今の時刻までが72時間以上なら 0、そうでなければ 1、日時の形が違えば 2。
#   ctr_pass_at <公開日時>
#     公開日時に72時間を足した日時を出す。日時の形が違えば 2。
#   ci_tool_age_check <根のフォルダ> <道具> <CI の版か -> <開発環境の版か -> <開発環境の digest か ->
#     CI の版を渡したときは、その版の公開日時から72時間経っているかを調べる。
#     開発環境の版を渡したときは、その版の公開日時と、配布元のイメージのタグ
#     <版><tag_suffix> の公開日時の、遅いほうから72時間経っているかを調べる。
#     開発環境の digest を渡したときは、そのタグの今の digest と同じかも調べる。
#     イメージの名前と tag_suffix は、<根のフォルダ>/.github/ci-tool-versions.json の
#     dev の hub_repository と tag_suffix から読む。
#     調べた場所ごとに「場所<TAB>版<TAB>公開日時<TAB>通る日時<TAB>結果<TAB>理由」を出す。
#     場所は ci か dev。結果は ok か ng か error。ng は72時間経っていないか digest が違う
#     こと、error は日時か digest を取れなかったか、イメージのタグが無いことを表す。
#     error の行は、公開日時と通る日時の欄を - にし、理由に取れなかった理由を書く。
#     ok の行は、理由の欄を - にする。
#     0 = すべて ok / 1 = ng か error の行がある / 2 = 引数の形が違うか、データのファイルを
#     読めないか、データのファイルに開発環境の書き場所が無いか、書き場所の hub_repository か
#     tag_suffix の形が違う
#
# テスト: .github/scripts/tests/test-lib-ci-tool-releases.sh
# =====================================================================

if ! declare -F civ_gt >/dev/null 2>&1; then
    # shellcheck source=.github/scripts/lib-ci-tool-versions.sh
    . "$(dirname "${BASH_SOURCE[0]}")/lib-ci-tool-versions.sh" ||
        echo "lib-ci-tool-releases: lib-ci-tool-versions.sh を読み込めませんでした" >&2
fi

_ctr_fail() {
    echo "$1 $2: $3 から $4 を取れませんでした($5)" >&2
}

# 使い方: _ctr_get <一時のフォルダ> <道具> <版> <欄> gh|curl <パスか URL> [<404 の理由>]
# 応答を <一時のフォルダ>/body に書く。失敗したら、理由を出して 1 を返す。
# <404 の理由> を渡すと、curl の HTTP 404 の理由の後ろに足す。
_ctr_get() {
    local d="$1" tool="$2" ver="$3" field="$4" kind="$5" src="$6" notfound="${7:-}" code reason label
    if [ "$kind" = gh ]; then
        label="GitHub の ${src}"
        if ! gh api "$src" >"$d/body" 2>"$d/err"; then
            reason=$(grep -o 'HTTP [0-9][0-9]*' "$d/err" | head -n 1)
            _ctr_fail "$tool" "$ver" "$label" "$field" "${reason:-gh api が失敗しました}"
            return 1
        fi
    else
        label="$src"
        if ! code=$(curl -fsS --max-time 120 --retry 2 -o "$d/body" -w '%{http_code}' "$src" 2>"$d/err"); then
            if [ -n "$code" ] && [ "$code" != 000 ]; then
                reason="HTTP ${code}"
                [ "$code" = 404 ] && [ -n "$notfound" ] && reason="${reason}。${notfound}"
            else
                reason="curl が失敗しました: $(head -n 1 "$d/err")"
            fi
            _ctr_fail "$tool" "$ver" "$label" "$field" "$reason"
            return 1
        fi
    fi
    if ! jq -e . "$d/body" >/dev/null 2>&1; then
        _ctr_fail "$tool" "$ver" "$label" "$field" "応答が JSON として読めません"
        return 1
    fi
    printf '%s\n' "$label" >"$d/label"
}

# 公開日時を YYYY-MM-DDTHH:MM:SSZ の形にそろえる。形が違えば 1 を返す。
_ctr_norm() {
    [[ "${1:-}" =~ ^([0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2})(\.[0-9]+)?Z$ ]] || return 1
    printf '%sZ\n' "${BASH_REMATCH[1]}"
}

# 使い方: _ctr_ts <一時のフォルダ> <道具> <版> <欄> <値>
# 値をそろえて出す。値が空か形が違えば、理由を出して 1 を返す。
_ctr_ts() {
    local t
    if [ -z "$5" ]; then
        _ctr_fail "$2" "$3" "$(cat "$1/label")" "$4" "応答に欄がありません"
        return 1
    fi
    if ! t=$(_ctr_norm "$5"); then
        _ctr_fail "$2" "$3" "$(cat "$1/label")" "$4" "日時の形が違います: $5"
        return 1
    fi
    printf '%s\n' "$t"
}

# 応答の形を確かめる。違えば、理由を出して 1 を返す。
# 使い方: _ctr_shape <一時のフォルダ> <道具> <版> <欄> <jq の条件>
_ctr_shape() {
    if ! jq -e "$5" "$1/body" >/dev/null 2>&1; then
        _ctr_fail "$2" "$3" "$(cat "$1/label")" "$4" "応答に欄がありません"
        return 1
    fi
}

_ctr_check_tool() {
    case "${1:-}" in
    node | trivy | codex | terraform) return 0 ;;
    esac
    echo "lib-ci-tool-releases: 道具の名前が違います: ${1:-}" >&2
    return 2
}

_ctr_check_ver() {
    if ! [[ "${1:-}" =~ ^v?[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo "lib-ci-tool-releases: 版の形が違います: ${1:-}" >&2
        return 2
    fi
}

_ctr_published() {
    local d="$1" tool="$2" ver="${3#v}" field val
    case "$tool" in
    node | trivy)
        field="published_at"
        if [ "$tool" = node ]; then
            _ctr_get "$d" "$tool" "$ver" "$field" gh "repos/nodejs/node/releases/tags/v${ver}" || return 1
        else
            _ctr_get "$d" "$tool" "$ver" "$field" gh "repos/aquasecurity/trivy/releases/tags/v${ver}" || return 1
        fi
        val=$(jq -r '.published_at // empty' "$d/body" 2>/dev/null)
        ;;
    codex)
        field="time.${ver}"
        _ctr_get "$d" "$tool" "$ver" "$field" curl "${CTR_NPM_REGISTRY:-https://registry.npmjs.org}/@openai%2fcodex" || return 1
        val=$(jq -r --arg v "$ver" '.time[$v]? // empty' "$d/body" 2>/dev/null)
        ;;
    terraform)
        field="timestamp_created"
        _ctr_get "$d" "$tool" "$ver" "$field" curl "${CTR_HASHICORP_API:-https://api.releases.hashicorp.com}/v1/releases/terraform/${ver}" || return 1
        val=$(jq -r '.timestamp_created? // empty' "$d/body" 2>/dev/null)
        ;;
    esac
    _ctr_ts "$d" "$tool" "$ver" "$field" "$val"
}

# 「版<TAB>公開日時」の行から、今の版より新しく、同じメジャー版の正式な版の行だけを残す。
_ctr_pick() {
    local cur="$1" major v t
    major=$(civ_major "$cur") || return 2
    while IFS="$(printf '\t')" read -r v t; do
        [[ "$v" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || continue
        [ "${v%%.*}" = "$major" ] || continue
        civ_gt "$v" "$cur" || continue
        printf '%s\t%s\n' "$v" "$t"
    done
}

# 標準入力の版に、今の版以下の正式な版があれば 0 を返す。
_ctr_has_older() {
    local v
    while read -r v; do
        [[ "$v" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || continue
        civ_gt "$v" "$1" || return 0
    done
    return 1
}

# 版の新しい順に並べ、同じ版を1行にまとめる。
_ctr_sort() {
    sort -t. -k1,1nr -k2,2nr -k3,3nr | awk -F '\t' '!seen[$1]++'
}

_ctr_list() {
    local d="$1" tool="$2" cur="${3#v}" lines="" picked v t page last cur_ts n
    case "$tool" in
    node)
        _ctr_get "$d" node "$cur" "version" curl "${CTR_NODE_DIST_URL:-https://nodejs.org/dist}/index.json" || return 1
        _ctr_shape "$d" node "$cur" "version" 'type == "array" and all(.[]; .version | type == "string")' || return 1
        picked=$(jq -r '.[].version | sub("^v"; "")' "$d/body" | _ctr_pick "$cur") || return 2
        while IFS="$(printf '\t')" read -r v _; do
            [ -n "$v" ] || continue
            t=$(_ctr_published "$d" node "$v") || return 1
            lines+="${v}"$'\t'"${t}"$'\n'
        done <<<"$picked"
        ;;
    trivy)
        page=1
        while :; do
            if [ "$page" -gt 30 ]; then
                _ctr_fail trivy "$cur" "$(cat "$d/label")" "tag_name" "30 ページをたどっても今の版に届きません"
                return 1
            fi
            _ctr_get "$d" trivy "$cur" "tag_name" gh "repos/aquasecurity/trivy/releases?per_page=100&page=${page}" || return 1
            _ctr_shape "$d" trivy "$cur" "tag_name" 'type == "array" and all(.[]; .tag_name | type == "string")' || return 1
            n=$(jq 'length' "$d/body")
            [ "$n" -gt 0 ] || break
            while IFS="$(printf '\t')" read -r v t; do
                t=$(_ctr_ts "$d" trivy "$v" "published_at" "$t") || return 1
                lines+="${v}"$'\t'"${t}"$'\n'
            done < <(jq -r '.[] | select(.draft == false and .prerelease == false)
                | [(.tag_name | sub("^v"; "")), (.published_at // "")] | @tsv' "$d/body" | _ctr_pick "$cur")
            # 一覧は新しい順に返る。このページに今の版以下の版があれば、次のページは要らない。
            jq -r '.[].tag_name | sub("^v"; "")' "$d/body" | _ctr_has_older "$cur" && break
            page=$((page + 1))
        done
        ;;
    codex)
        _ctr_get "$d" codex "$cur" "time" curl "${CTR_NPM_REGISTRY:-https://registry.npmjs.org}/@openai%2fcodex" || return 1
        _ctr_shape "$d" codex "$cur" "time" '.time | type == "object"' || return 1
        while IFS="$(printf '\t')" read -r v t; do
            t=$(_ctr_ts "$d" codex "$v" "time.${v}" "$t") || return 1
            lines+="${v}"$'\t'"${t}"$'\n'
        done < <(jq -r '.time | to_entries[] | [.key, (.value | tostring)] | @tsv' "$d/body" | _ctr_pick "$cur")
        ;;
    terraform)
        cur_ts=$(_ctr_published "$d" terraform "$cur") || return 1
        last=""
        page=1
        while :; do
            if [ "$page" -gt 50 ]; then
                _ctr_fail terraform "$cur" "$(cat "$d/label")" "version" "50 ページをたどっても今の版に届きません"
                return 1
            fi
            _ctr_get "$d" terraform "$cur" "version" curl \
                "${CTR_HASHICORP_API:-https://api.releases.hashicorp.com}/v1/releases/terraform?limit=20${last:+&after=${last}}" || return 1
            _ctr_shape "$d" terraform "$cur" "version" 'type == "array" and all(.[]; .version | type == "string")' || return 1
            _ctr_shape "$d" terraform "$cur" "timestamp_created" 'all(.[]; .timestamp_created | type == "string")' || return 1
            n=$(jq 'length' "$d/body")
            [ "$n" -gt 0 ] || break
            while IFS="$(printf '\t')" read -r v t; do
                t=$(_ctr_ts "$d" terraform "$v" "timestamp_created" "$t") || return 1
                lines+="${v}"$'\t'"${t}"$'\n'
            done < <(jq -r '.[] | select(.is_prerelease == false) | [.version, .timestamp_created] | @tsv' "$d/body" | _ctr_pick "$cur")
            # 一覧は新しい順に返る。今の版の公開日時より古い版に届いたら止める。
            t=$(jq -r '.[-1].timestamp_created' "$d/body")
            t=$(_ctr_ts "$d" terraform "$cur" "timestamp_created" "$t") || return 1
            [[ "$t" < "$cur_ts" ]] && break
            [ "$n" -ge 20 ] || break
            last=$(jq -r '.[-1].timestamp_created' "$d/body")
            page=$((page + 1))
        done
        ;;
    esac
    printf '%s' "$lines" | _ctr_sort
}

ctr_list() {
    local d rc
    _ctr_check_tool "${1:-}" || return 2
    _ctr_check_ver "${2:-}" || return 2
    d=$(mktemp -d) || return 1
    _ctr_list "$d" "$1" "$2"
    rc=$?
    rm -rf "$d"
    return "$rc"
}

ctr_published() {
    local d rc
    _ctr_check_tool "${1:-}" || return 2
    _ctr_check_ver "${2:-}" || return 2
    d=$(mktemp -d) || return 1
    _ctr_published "$d" "$1" "$2"
    rc=$?
    rm -rf "$d"
    return "$rc"
}

ctr_notes_url() {
    local v="${2#v}"
    _ctr_check_tool "${1:-}" || return 2
    _ctr_check_ver "${2:-}" || return 2
    case "$1" in
    node) printf 'https://github.com/nodejs/node/releases/tag/v%s\n' "$v" ;;
    trivy) printf 'https://github.com/aquasecurity/trivy/releases/tag/v%s\n' "$v" ;;
    codex) printf 'https://github.com/openai/codex/releases/tag/rust-v%s\n' "$v" ;;
    terraform) printf 'https://github.com/hashicorp/terraform/releases/tag/v%s\n' "$v" ;;
    esac
}

# 「YYYY-MM-DDTHH:MM:SSZ」の日時を、1970-01-01T00:00:00Z からの秒に直す。形が違えば 1 を返す。
# date -d の読める形は GNU と busybox で違うため、暦の計算を自分で行う。
_ctr_epoch() {
    local y m d era yoe doy doe
    [[ "${1:-}" =~ ^([0-9]{4})-([0-9]{2})-([0-9]{2})T([0-9]{2}):([0-9]{2}):([0-9]{2})Z$ ]] || return 1
    y=$((10#${BASH_REMATCH[1]}))
    m=$((10#${BASH_REMATCH[2]}))
    d=$((10#${BASH_REMATCH[3]}))
    [ "$m" -gt 2 ] || y=$((y - 1))
    era=$((y / 400))
    yoe=$((y - era * 400))
    doy=$(((153 * (m > 2 ? m - 3 : m + 9) + 2) / 5 + d - 1))
    doe=$((yoe * 365 + yoe / 4 - yoe / 100 + doy))
    echo $(((era * 146097 + doe - 719468) * 86400 + 10#${BASH_REMATCH[4]} * 3600 + 10#${BASH_REMATCH[5]} * 60 + 10#${BASH_REMATCH[6]}))
}

# 1970-01-01T00:00:00Z からの秒を、「YYYY-MM-DDTHH:MM:SSZ」の日時に直す。
_ctr_iso() {
    local s="$1" z era doe yoe y doy mp d m
    z=$((s / 86400 + 719468))
    era=$((z / 146097))
    doe=$((z - era * 146097))
    yoe=$(((doe - doe / 1460 + doe / 36524 - doe / 146096) / 365))
    y=$((yoe + era * 400))
    doy=$((doe - (365 * yoe + yoe / 4 - yoe / 100)))
    mp=$(((5 * doy + 2) / 153))
    d=$((doy - (153 * mp + 2) / 5 + 1))
    m=$((mp < 10 ? mp + 3 : mp - 9))
    [ "$m" -gt 2 ] || y=$((y + 1))
    printf '%04d-%02d-%02dT%02d:%02d:%02dZ\n' "$y" "$m" "$d" $((s % 86400 / 3600)) $((s % 3600 / 60)) $((s % 60))
}

# 72時間を秒で出す。
_ctr_wait() {
    echo 259200
}

_ctr_image() {
    local d="$1" repo="$2" tag="$3" digest t
    _ctr_get "$d" "$repo" "$tag" "digest" curl \
        "${CTR_DOCKER_HUB:-https://hub.docker.com}/v2/namespaces/${repo%%/*}/repositories/${repo#*/}/tags/${tag}" \
        "タグがありません" || return 1
    digest=$(jq -r '.digest? // empty' "$d/body" 2>/dev/null)
    if [ -z "$digest" ]; then
        _ctr_fail "$repo" "$tag" "$(cat "$d/label")" "digest" "応答に欄がありません"
        return 1
    fi
    if ! [[ "$digest" =~ ^sha256:[0-9a-f]{64}$ ]]; then
        _ctr_fail "$repo" "$tag" "$(cat "$d/label")" "digest" "digest の形が違います: ${digest}"
        return 1
    fi
    t=$(_ctr_ts "$d" "$repo" "$tag" "tag_last_pushed" "$(jq -r '.tag_last_pushed? // empty' "$d/body" 2>/dev/null)") || return 1
    printf '%s\t%s\n' "$digest" "$t"
}

ctr_image() {
    local d rc
    if ! [[ "${1:-}" =~ ^[a-z0-9._-]+/[a-z0-9._-]+$ ]] || ! [[ "${2:-}" =~ ^[A-Za-z0-9._-]+$ ]]; then
        echo "lib-ci-tool-releases: イメージの名前かタグの形が違います: ${1:-}:${2:-}" >&2
        return 2
    fi
    d=$(mktemp -d) || return 1
    _ctr_image "$d" "$1" "$2"
    rc=$?
    rm -rf "$d"
    return "$rc"
}

ctr_age_ok() {
    local e now="${NOW_EPOCH:-}"
    if ! e=$(_ctr_epoch "${1:-}"); then
        echo "lib-ci-tool-releases: 日時の形が違います: ${1:-}" >&2
        return 2
    fi
    [ -n "$now" ] || now=$(date +%s)
    if ! [[ "$now" =~ ^[0-9]+$ ]]; then
        echo "lib-ci-tool-releases: 今の時刻の形が違います: ${now}" >&2
        return 2
    fi
    [ $((now - e)) -ge "$(_ctr_wait)" ]
}

ctr_pass_at() {
    local e
    if ! e=$(_ctr_epoch "${1:-}"); then
        echo "lib-ci-tool-releases: 日時の形が違います: ${1:-}" >&2
        return 2
    fi
    _ctr_iso $((e + $(_ctr_wait)))
}

# 使い方: _ctr_row <場所> <版> <公開日時> <通る日時> <結果> <理由>
_ctr_row() {
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4" "$5" "$6"
}

# 一時のフォルダの why に書いた標準エラーを、1行にして出す。
_ctr_why() {
    tr '\t\n' '  ' <"$1/why" | sed 's/ *$//'
}

# 使い方: _ctr_judge <一時のフォルダ> <場所> <版> <数え始めの日時> <ng の理由の前置き>
# 数え始めの日時から72時間経っていれば ok の行を、そうでなければ ng の行を出す。
_ctr_judge() {
    local d="$1" place="$2" v="$3" t="$4" pre="$5" pass rc
    pass=$(ctr_pass_at "$t")
    ctr_age_ok "$t" 2>"$d/why"
    rc=$?
    case "$rc:$pre" in
    0:) _ctr_row "$place" "$v" "$t" "$pass" ok - ;;
    0:*) _ctr_row "$place" "$v" "$t" "$pass" ng "$pre" ;;
    1:*) _ctr_row "$place" "$v" "$t" "$pass" ng "${pre:+${pre}。}公開から72時間経っていません" ;;
    *) _ctr_row "$place" "$v" - - error "$(_ctr_why "$d")" ;;
    esac
    [ "$rc" -eq 0 ] && [ -z "$pre" ]
}

_ctr_age_ci() {
    local d="$1" tool="$2" v="$3" pub
    if ! pub=$(_ctr_published "$d" "$tool" "$v" 2>"$d/why"); then
        _ctr_row ci "$v" - - error "$(_ctr_why "$d")"
        return 1
    fi
    _ctr_judge "$d" ci "$v" "$pub" ""
}

_ctr_age_dev() {
    local d="$1" tool="$2" v="$3" want="$4" repo="$5" suffix="$6" pub img digest pushed t pre=""
    if ! pub=$(_ctr_published "$d" "$tool" "$v" 2>"$d/why"); then
        _ctr_row dev "$v" - - error "$(_ctr_why "$d")"
        return 1
    fi
    if ! img=$(_ctr_image "$d" "$repo" "${v}${suffix}" 2>"$d/why"); then
        _ctr_row dev "$v" - - error "$(_ctr_why "$d")"
        return 1
    fi
    IFS="$(printf '\t')" read -r digest pushed <<<"$img"
    if [ "$want" != - ] && [ "$want" != "$digest" ]; then
        pre="digest が配布元のイメージのタグ ${repo}:${v}${suffix} の今の digest ${digest} と違います"
    fi
    # 版の公開とイメージのタグの公開の、遅いほうから72時間を数える。
    t="$pub"
    [[ "$pushed" > "$t" ]] && t="$pushed"
    _ctr_judge "$d" dev "$v" "$t" "$pre"
}

ci_tool_age_check() {
    local root="${1:-}" tool="${2:-}" cv="${3:--}" dv="${4:--}" want="${5:--}" data dev repo="" suffix="" d bad=0
    _ctr_check_tool "$tool" || return 2
    if [ "$cv" != - ]; then
        _ctr_check_ver "$cv" || return 2
        cv="${cv#v}"
    fi
    if [ "$dv" != - ]; then
        _ctr_check_ver "$dv" || return 2
        dv="${dv#v}"
        if [ "$want" != - ] && ! [[ "$want" =~ ^sha256:[0-9a-f]{64}$ ]]; then
            echo "lib-ci-tool-releases: digest の形が違います: ${want}" >&2
            return 2
        fi
        data=$(_civ_data "$root") || return 2
        dev=$(jq -r --arg t "$tool" '.tools[$t].dev // empty | "\(.hub_repository // "")|\(.tag_suffix // "")"' "$data") || return 2
        if [ -z "$dev" ]; then
            echo "lib-ci-tool-releases: データのファイルに ${tool} の開発環境の書き場所がありません" >&2
            return 2
        fi
        # 区切りの | は、hub_repository にも tag_suffix にも書けない文字である。
        repo="${dev%%|*}"
        suffix="${dev#*|}"
        if ! [[ "$repo" =~ ^[a-z0-9._-]+/[a-z0-9._-]+$ ]] || ! [[ "$suffix" =~ ^[A-Za-z0-9._-]*$ ]]; then
            echo "lib-ci-tool-releases: データのファイルの ${tool} の hub_repository か tag_suffix の形が違います: hub_repository は「${repo}」、tag_suffix は「${suffix}」です" >&2
            return 2
        fi
    fi
    d=$(mktemp -d) || return 1
    if [ "$cv" != - ]; then
        _ctr_age_ci "$d" "$tool" "$cv" || bad=1
    fi
    if [ "$dv" != - ]; then
        _ctr_age_dev "$d" "$tool" "$dv" "$want" "$repo" "$suffix" || bad=1
    fi
    rm -rf "$d"
    return "$bad"
}
