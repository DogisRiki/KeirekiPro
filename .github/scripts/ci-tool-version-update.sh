#!/usr/bin/env bash
# =====================================================================
# CI の道具の版を上げる更新の PR を作る(ci-tool-version-update.yaml から週1回実行)
#
# 4つの道具(node trivy codex terraform)ごとに、書き換え先の版を決める。
# 書き換え先の版 T は、次の3つのうち最も新しい版である。
#   - 上げる先の版 V: 今の CI の版 C より新しく、同じメジャー版で、公開から72時間
#     経った版のうち最も新しい版。Node.js と Terraform では、その版を入れた配布元の
#     イメージのタグも、公開から72時間経っている版に限る
#   - 今の CI の版 C
#   - 今の開発環境の版 D(Node.js と Terraform だけ)
# T を最も新しい版にするのは、CI の版も開発環境の版も下げないためである。上げる先の版が
# 無くても、C と D が違えば、新しいほうにそろえる。
#
# なぜ PR を作る前に公開からの時間の検査と同じ判定を通すか:
#   T が C か D と同じとき、その版は72時間待たずに手で入れた版のことがある。この
#   スクリプトは記録の目印の行を読まないので、その版で別の場所を書き換えた PR は、
#   公開からの時間の検査で止まる。止まる PR を作らないよう、PR を作る前に
#   ci_tool_age_check で、自分が変える場所を調べる。
#
# テスト: .github/scripts/tests/test-ci-tool-version-update.sh
# 使い方:
#   ci-tool-version-update.sh plan <道具>
#     今のフォルダを main の根として、書き換え先の版を決める。
#     PR を作るときは「T<TAB>C<TAB>D<TAB>T の公開日時<TAB>イメージの digest<TAB>
#     イメージの公開日時」の1行を出して 0 で終わる。開発環境の無い道具では、D と
#     イメージの digest とイメージの公開日時を - にする。
#     PR を作らないとき(書き換えると変わる場所が無いか、まだ72時間経っていないとき)は、
#     何も出さずに 0 で終わる。
#     新しい版を調べられなかったときは、理由を標準エラーに1行出して 1 で終わる。
#     引数の形が違えば 2 で終わる。
#   ci-tool-version-update.sh body <道具> <T> <C> <D> <T の公開日時> <イメージの digest> <イメージの公開日時>
#     plan が出した1行の6つの欄を渡す。1行目に更新の PR の題名を、2行目から本文を出して
#     0 で終わる。渡された版か digest か日時の形が違うか、変更点の文書の一覧を取れなかった
#     ときは、理由を標準エラーに1行出して 1 で終わる。引数の数が違えば 2 で終わる。
#   ci-tool-version-update.sh rewrite <道具> <T> <C> <D> <イメージの digest>
#     今のフォルダの CI の版と開発環境の版を T に書き換えてコミットする。T と同じ版の
#     場所は書き換えない。書き換えられなかったときは、理由を標準エラーに1行出して
#     1 で終わる。引数の数が違えば 2 で終わる。
#   ci-tool-version-update.sh run
#     今のフォルダを origin の写しとして、道具ごとに更新の PR を作るか、開いている
#     更新の PR を書き換える。環境変数 GH_TOKEN と GITHUB_REPOSITORY と
#     CI_TOOL_UPDATE_REPORT を要る。失敗した道具ごとに、CI_TOOL_UPDATE_REPORT の
#     ファイルに「- <名前>: <何に失敗したか>(<理由>)」の1行を足す。すべての道具を
#     終えてから、1つでも失敗があれば 1 で終わる。環境変数が欠けていれば 2 で終わる。
# =====================================================================
set -uo pipefail

# shellcheck source=.github/scripts/lib-ci-tool-releases.sh
source "$(cd "$(dirname "$0")" && pwd)/lib-ci-tool-releases.sh"

VER_RE='^[0-9]+\.[0-9]+\.[0-9]+$'
DIGEST_RE='^sha256:[0-9a-f]{64}$'
TS_RE='^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$'
BOT_NAME=keirekipro-ci-tool-update-bot
BOT_EMAIL=ci-tool-update-bot@users.noreply.github.com

# 問い合わせの関数の標準エラーを受けるファイルと、npm の registry の応答の写しを置くフォルダ
ERRF=$(mktemp) || exit 1
CACHE=$(mktemp -d) || exit 1
[ -n "$CACHE" ] && [ -d "$CACHE" ] || exit 1
trap 'rm -f "$ERRF"; rm -rf "$CACHE"' EXIT

# npm の registry が返す Codex CLI の JSON は約18MBあるので、1回の実行で1回だけ取る。
# lib の関数が呼ぶ curl を、npm の registry の取り先で、応答をファイルに書く呼び方の
# ときだけ、取った応答の写しで返す。ほかの呼び方は、本物の curl にそのまま渡す
curl() {
    local a prev="" out="" fmt="" url="" key
    for a in "$@"; do
        case "$prev" in
        -o) out="$a" ;;
        -w) fmt="$a" ;;
        esac
        prev="$a"
        url="$a"
    done
    case "$url" in
    "${CTR_NPM_REGISTRY:-https://registry.npmjs.org}"/*) ;;
    *)
        command curl "$@"
        return
        ;;
    esac
    if [ -z "$out" ] || { [ -n "$fmt" ] && [ "$fmt" != '%{http_code}' ]; }; then
        command curl "$@"
        return
    fi
    key="$CACHE/$(printf '%s' "$url" | cksum | cut -d ' ' -f 1)"
    if [ -f "$key" ]; then
        cp "$key" "$out" || return 1
        [ -n "$fmt" ] && printf '200'
        return 0
    fi
    command curl "$@" || return
    cp "$out" "$key"
    return 0
}

usage() {
    echo "使い方: ci-tool-version-update.sh plan <道具> | body <道具> <T> <C> <D> <T の公開日時> <イメージの digest> <イメージの公開日時> | rewrite <道具> <T> <C> <D> <イメージの digest> | run" >&2
    echo "道具: node trivy codex terraform" >&2
    exit 2
}

# 使い方: pr_title <名前> <T> <C>。更新の PR の題名とコミットの1行目
pr_title() {
    if [ "$2" != "$3" ]; then
        printf 'chore: CI の %s を %s に上げる\n' "$1" "$2"
    else
        printf 'chore: %s の開発環境の版を CI の版 %s にそろえる\n' "$1" "$2"
    fi
}

# 使い方: why <理由>。新しい版を調べられなかった理由を標準エラーに1行出す
why() {
    printf '%s\n' "$1" | head -n 1 >&2
}

# 使い方: ci_ver <道具>。今のフォルダの CI の版を出す。CI の版は、どの場所でも
# 同じでなければならない。読めないか、場所によって違えば、理由を標準エラーに1行出して 1 を返す
ci_ver() {
    local tool="$1" cis vals err="$ERRF"
    if ! cis=$(civ_tool_versions . "$tool" 2>"$err"); then
        why "CI の版を読めませんでした($(head -n 1 "$err"))"
        return 1
    fi
    if printf '%s\n' "$cis" | awk -F '\t' '$3 == "-" { found = 1 } END { exit !found }'; then
        why "CI の版の行が見つからない場所があります($(printf '%s\n' "$cis" | awk -F '\t' '$3 == "-" { print $1 }' | paste -sd ' ' -))"
        return 1
    fi
    vals=$(printf '%s\n' "$cis" | awk -F '\t' 'NF { v = $3; sub(/^v/, "", v); print v }' | sort -u)
    if [ -z "$vals" ]; then
        why "データのファイルに CI の書き場所がありません"
        return 1
    fi
    if [ "$(printf '%s\n' "$vals" | wc -l)" -gt 1 ]; then
        why "CI の版が場所によって違います($(printf '%s\n' "$vals" | paste -sd ' ' -))"
        return 1
    fi
    if ! [[ "$vals" =~ $VER_RE ]]; then
        why "CI の版の形が違います(${vals})"
        return 1
    fi
    printf '%s\n' "$vals"
}

# 使い方: plan <道具>
plan() {
    local tool="$1" data C dline D="" hub="" suffix="" list v pub V="" vpub="" vdig="" vipub=""
    local T tpub idig="-" ipub="-" img rc cv dv want out err="$ERRF"
    if ! data=$(_civ_data . 2>"$err"); then
        why "データのファイルを読めませんでした($(head -n 1 "$err"))"
        return 1
    fi

    # --- 今の CI の版 C ---
    C=$(ci_ver "$tool") || return 1

    # --- 今の開発環境の版 D。メジャー版は C と同じでなければならない ---
    if [ -n "$(_civ_dev "$data" "$tool")" ]; then
        if ! dline=$(civ_dev_from . "$tool" 2>"$err"); then
            why "開発環境の版を読めませんでした($(head -n 1 "$err"))"
            return 1
        fi
        D=$(printf '%s\n' "$dline" | cut -f1)
        D="${D#v}"
        if ! [[ "$D" =~ $VER_RE ]]; then
            why "開発環境の版の形が違います(${D})"
            return 1
        fi
        if [ "$(civ_major "$D")" != "$(civ_major "$C")" ]; then
            why "開発環境の版 ${D} のメジャー版が CI の版 ${C} と違います"
            return 1
        fi
        hub=$(jq -r --arg t "$tool" '.tools[$t].dev.hub_repository // ""' "$data")
        suffix=$(jq -r --arg t "$tool" '.tools[$t].dev.tag_suffix // ""' "$data")
        # hub_repository が欠けると、イメージのタグの確かめを黙って飛ばすことになるので、失敗にする
        if ! [[ "$hub" =~ ^[a-z0-9._-]+/[a-z0-9._-]+$ ]] || ! [[ "$suffix" =~ ^[A-Za-z0-9._-]*$ ]]; then
            why "データのファイルの ${tool} の hub_repository か tag_suffix の形が違います(${hub} ${suffix})"
            return 1
        fi
    fi

    # --- 上げる先の版 V。一覧は新しい順に並ぶ ---
    if ! list=$(ctr_list "$tool" "$C" 2>"$err"); then
        why "版の一覧を取れませんでした($(head -n 1 "$err"))"
        return 1
    fi
    while IFS=$'\t' read -r v pub; do
        [ -n "$v" ] || continue
        ctr_age_ok "$pub" 2>"$err"
        rc=$?
        [ "$rc" -eq 1 ] && continue
        if [ "$rc" -ne 0 ]; then
            why "${v} の公開日時を読めませんでした($(head -n 1 "$err"))"
            return 1
        fi
        if [ -n "$hub" ]; then
            # 版が72時間経っていても、イメージのタグが72時間経っていなければ、1つ前の版を確かめる
            if ! img=$(ctr_image "$hub" "${v}${suffix}" 2>"$err"); then
                why "イメージのタグ ${hub}:${v}${suffix} を取れませんでした($(head -n 1 "$err"))"
                return 1
            fi
            ctr_age_ok "$(printf '%s\n' "$img" | cut -f2)" 2>"$err"
            rc=$?
            [ "$rc" -eq 1 ] && continue
            if [ "$rc" -ne 0 ]; then
                why "イメージのタグ ${hub}:${v}${suffix} の公開日時を読めませんでした($(head -n 1 "$err"))"
                return 1
            fi
            vdig=$(printf '%s\n' "$img" | cut -f1)
            vipub=$(printf '%s\n' "$img" | cut -f2)
        fi
        V="$v"
        vpub="$pub"
        break
    done <<<"$list"

    # --- 書き換え先の版 T。C と D と V のうち最も新しい版にし、どちらの版も下げない ---
    T="$C"
    if [ -n "$D" ] && civ_gt "$D" "$T"; then T="$D"; fi
    if [ -n "$V" ] && civ_gt "$V" "$T"; then T="$V"; fi
    if [ "$T" = "$C" ] && { [ -z "$D" ] || [ "$T" = "$D" ]; }; then
        return 0
    fi

    # --- T のイメージのタグ。開発環境の行が変わるかどうかによらず、72時間経っているかを確かめる ---
    if [ -n "$hub" ]; then
        if [ "$T" = "$V" ]; then
            idig="$vdig"
            ipub="$vipub"
        else
            if ! img=$(ctr_image "$hub" "${T}${suffix}" 2>"$err"); then
                why "イメージのタグ ${hub}:${T}${suffix} を取れませんでした($(head -n 1 "$err"))"
                return 1
            fi
            idig=$(printf '%s\n' "$img" | cut -f1)
            ipub=$(printf '%s\n' "$img" | cut -f2)
            ctr_age_ok "$ipub" 2>"$err"
            rc=$?
            [ "$rc" -eq 1 ] && return 0
            if [ "$rc" -ne 0 ]; then
                why "イメージのタグ ${hub}:${T}${suffix} の公開日時を読めませんでした($(head -n 1 "$err"))"
                return 1
            fi
        fi
    fi

    # --- 変える場所が、公開からの時間の検査を通るか ---
    cv=-
    dv=-
    want=-
    [ "$T" != "$C" ] && cv="$T"
    if [ -n "$D" ] && [ "$T" != "$D" ]; then
        dv="$T"
        want="$idig"
    fi
    out=$(ci_tool_age_check . "$tool" "$cv" "$dv" "$want" 2>"$err")
    rc=$?
    if [ "$rc" -eq 2 ] || printf '%s\n' "$out" | awk -F '\t' '$5 == "error" { found = 1 } END { exit !found }'; then
        why "変わる場所が公開からの時間の検査を通るかを調べられませんでした($( {
            printf '%s\n' "$out" | awk -F '\t' '$5 == "error" { print $6 }'
            cat "$err"
        } | head -n 1))"
        return 1
    fi
    # まだ72時間経っていない場所があれば、その週は PR を作らない。ng の行の無い失敗は、
    # 72時間経っていないこととは分けて、調べられなかった失敗にする
    if [ "$rc" -ne 0 ]; then
        if [ "$rc" -eq 1 ] && printf '%s\n' "$out" | awk -F '\t' '$5 == "ng" { found = 1 } END { exit !found }'; then
            return 0
        fi
        why "変わる場所が公開からの時間の検査を通るかを調べられませんでした(終了コード ${rc}。$(head -n 1 "$err"))"
        return 1
    fi

    if [ "$T" = "$V" ]; then
        tpub="$vpub"
    elif ! tpub=$(ctr_published "$tool" "$T" 2>"$err"); then
        why "${T} の公開日時を取れませんでした($(head -n 1 "$err"))"
        return 1
    fi
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$T" "$C" "${D:--}" "$tpub" "$idig" "$ipub"
}

# 使い方: body <道具> <T> <C> <D> <T の公開日時> <イメージの digest> <イメージの公開日時>
# shellcheck disable=SC2016 # 本文の ` は Markdown の印であり、シェルの展開ではない
body() {
    local tool="$1" T="$2" C="$3" D="$4" tpub="$5" idig="$6" ipub="$7" err="$ERRF"
    local data name dev="" dfile="" image="" suffix="" hub="" cifiles low list v pub src links=""
    # 配布元から取った値を、そのまま題名と本文と URL に入れない
    if ! [[ "$T" =~ $VER_RE ]] || ! [[ "$C" =~ $VER_RE ]]; then
        why "版の形が違います(${T} ${C})"
        return 1
    fi
    if ! [[ "$tpub" =~ $TS_RE ]]; then
        why "${T} の公開日時の形が違います(${tpub})"
        return 1
    fi
    if ! data=$(_civ_data . 2>"$err"); then
        why "データのファイルを読めませんでした($(head -n 1 "$err"))"
        return 1
    fi
    name=$(jq -r --arg t "$tool" '.tools[$t].name // $t' "$data")
    cifiles=$(jq -r --arg t "$tool" '[.tools[$t].ci[]?.file] | unique | map("`" + . + "`") | join("、")' "$data")
    dev=$(_civ_dev "$data" "$tool")
    if [ -n "$dev" ]; then
        IFS=$'\t' read -r dfile image suffix <<<"$dev"
        hub=$(jq -r --arg t "$tool" '.tools[$t].dev.hub_repository // ""' "$data")
        if ! [[ "$D" =~ $VER_RE ]] || ! [[ "$idig" =~ $DIGEST_RE ]] || ! [[ "$ipub" =~ $TS_RE ]]; then
            why "開発環境の版かイメージの digest か公開日時の形が違います(${D} ${idig} ${ipub})"
            return 1
        fi
    elif [ "$D" != - ] || [ "$idig" != - ] || [ "$ipub" != - ]; then
        why "${name} には開発環境の書き場所が無いのに、開発環境の版かイメージが渡されました"
        return 1
    fi

    # --- 変更点: C と D の古いほうより新しく、T 以下の正式な版ごとに1行 ---
    low="$C"
    if [ -n "$dev" ] && civ_gt "$C" "$D"; then low="$D"; fi
    if ! list=$(ctr_list "$tool" "$low" 2>"$err"); then
        why "変更点の文書の一覧を作るための版の一覧を取れませんでした($(head -n 1 "$err"))"
        return 1
    fi
    while IFS=$'\t' read -r v pub; do
        [ -n "$v" ] || continue
        civ_gt "$v" "$T" && continue
        links+="- [${v}]($(ctr_notes_url "$tool" "$v"))"$'\n'
    done <<<"$list"
    if ! printf '%s' "$links" | grep -qF -- "- [${T}]("; then
        why "配布元の版の一覧に ${T} がありません"
        return 1
    fi

    case "$tool" in
    node) src="https://api.github.com/repos/nodejs/node/releases/tags/v${T} の \`published_at\`" ;;
    trivy) src="https://api.github.com/repos/aquasecurity/trivy/releases/tags/v${T} の \`published_at\`" ;;
    codex) src="${CTR_NPM_REGISTRY:-https://registry.npmjs.org}/@openai%2fcodex の \`time.${T}\`" ;;
    terraform) src="${CTR_HASHICORP_API:-https://api.releases.hashicorp.com}/v1/releases/terraform/${T} の \`timestamp_created\`" ;;
    esac

    pr_title "$name" "$T" "$C"
    printf '## 概要\n\n'
    printf 'この PR は、週1回の実行のワークフロー `ci-tool-version-update.yaml` が作りました。'
    if [ "$T" != "$C" ]; then
        printf '%s の版を、公開から72時間経った版 %s に書き換えます。\n\n' "$name" "$T"
    else
        printf '開発環境の %s の版を、CI の版 %s にそろえます。\n\n' "$name" "$T"
    fi
    printf '## 版\n\n| 書き場所 | 今の版 | 書き換え先の版 |\n|---|---|---|\n'
    printf '| CI(%s) | %s | %s |\n' "$cifiles" "$C" "$T"
    [ -n "$dev" ] && printf '| 開発環境(`%s`) | %s | %s |\n' "$dfile" "$D" "$T"
    printf '\n## 公開日時\n\n'
    printf -- '- %s の公開日時: %s(取り先: %s)\n' "$T" "$tpub" "$src"
    if [ -n "$dev" ]; then
        printf -- '- 配布元のイメージのタグ `%s:%s%s`\n' "$image" "$T" "$suffix"
        printf -- '  - digest: `%s`\n' "$idig"
        printf -- '  - 公開日時: %s(取り先: %s/v2/namespaces/%s/repositories/%s/tags/%s%s の `tag_last_pushed`)\n' \
            "$ipub" "${CTR_DOCKER_HUB:-https://hub.docker.com}" "${hub%%/*}" "${hub#*/}" "$T" "$suffix"
    fi
    printf '\n## 変更点\n\n%s' "$links"
    if [ "$tool" = terraform ]; then
        printf '\n## 本番に適用する Terraform の版\n\n'
        if [ "$T" != "$C" ]; then
            printf '本番に適用するワークフロー(%s)の Terraform の版が、%s から %s に変わります。' "$cifiles" "$C" "$T"
            printf '新しい版が本番に使われるのは、この PR のマージのあとに、誰かが本番に適用するワークフローを動かしたときです。\n'
        else
            printf '本番に適用するワークフロー(%s)の Terraform の版は、%s のまま変わりません。この PR は開発環境の版だけを変えます。\n' "$cifiles" "$C"
        fi
    fi
    printf '\n## 承認\n\n'
    if [ "$T" != "$C" ]; then
        printf 'この PR は `.github/` の下のファイルを変えるので、所有者の承認が済むまでマージされません。\n'
    else
        printf 'この PR は開発環境の版を変えるので、dependency-gate の検査が所有者の承認を求めます。所有者の承認が済むまでマージされません。\n'
    fi
    printf '\nRefs: N/A\n'
}

# 使い方: rewrite <道具> <T> <C> <D> <イメージの digest>
rewrite() {
    local tool="$1" T="$2" C="$3" D="$4" idig="$5" err="$ERRF" data name dfile changes="" reason msg
    if ! [[ "$T" =~ $VER_RE ]] || ! [[ "$C" =~ $VER_RE ]]; then
        why "版の形が違います(${T} ${C})"
        return 1
    fi
    if ! data=$(_civ_data . 2>"$err"); then
        why "データのファイルを読めませんでした($(head -n 1 "$err"))"
        return 1
    fi
    name=$(jq -r --arg t "$tool" '.tools[$t].name // $t' "$data")
    if [ "$T" != "$C" ]; then
        if ! civ_rewrite_ci . "$tool" "$T" 2>"$err"; then
            why "CI の版を書き換えられませんでした($(head -n 1 "$err"))"
            return 1
        fi
        changes+="- CI の ${name} の版を ${C} から ${T} に書き換える"$'\n'
    fi
    dfile=$(_civ_dev "$data" "$tool" | cut -f 1)
    if [ -n "$dfile" ] && [ "$D" != "$T" ]; then
        if ! [[ "$D" =~ $VER_RE ]]; then
            why "開発環境の版の形が違います(${D})"
            return 1
        fi
        if ! civ_rewrite_dev . "$tool" "$T" "$idig" 2>"$err"; then
            why "開発環境の版を書き換えられませんでした($(head -n 1 "$err"))"
            return 1
        fi
        changes+="- 開発環境(${dfile})の ${name} の版を ${D} から ${T} に書き換え、FROM の行に配布元のイメージの digest を書く"$'\n'
    fi
    if [ -z "$changes" ]; then
        why "${name} には、${T} に書き換える場所がありません"
        return 1
    fi
    if [ "$T" != "$C" ]; then
        reason="- CI の ${name} を、公開から72時間経った版に上げるため(ci-tool-version-update が自動で作った)"
    else
        reason="- 開発環境の ${name} の版を、CI の版にそろえるため(ci-tool-version-update が自動で作った)"
    fi
    msg="$(pr_title "$name" "$T" "$C")"$'\n\n'"Changes:"$'\n'"${changes}Reason:"$'\n'"${reason}"$'\n'
    msg+="BREAKING CHANGE: N/A"$'\n'"Related: N/A"$'\n'"Refs: N/A"
    if ! git add -u 2>"$err" || ! printf '%s\n' "$msg" |
        GIT_AUTHOR_NAME="$BOT_NAME" GIT_AUTHOR_EMAIL="$BOT_EMAIL" \
            GIT_COMMITTER_NAME="$BOT_NAME" GIT_COMMITTER_EMAIL="$BOT_EMAIL" \
            git commit -q -F - 2>"$err"; then
        why "書き換えをコミットできませんでした($(head -n 1 "$err"))"
        return 1
    fi
}

# 使い方: first <ファイル>。コマンドの標準エラーから、理由に書く1行を出す。
# git push が最初に出す「To <リモート>」の行と空の行は飛ばす
first() {
    local l
    l=$(grep -v -e '^To ' -e '^[[:space:]]*$' "$1" 2>/dev/null | head -n 1)
    printf '%s\n' "${l:-理由を読めませんでした}"
}

# 使い方: report <道具> <何に失敗したか> <理由>。報告のファイルに、失敗した道具の1行を書く
report() {
    local name="" data
    if data=$(_civ_data . 2>/dev/null); then
        name=$(jq -r --arg t "$1" '.tools[$t].name // empty' "$data" 2>/dev/null)
    fi
    printf -- '- %s: %s(%s)\n' "${name:-$1}" "$2" "$3" >>"$CI_TOOL_UPDATE_REPORT"
}

# 使い方: update <道具> <T> <C> <D> <イメージの digest> <題名と本文> <PR の番号> <headRefOid> <mergeable>
# 開いている更新の PR を、次の3つのどれかに当たるときだけ、main から作り直して書き換える。
#   - 書き換え先の版 T が PR の CI の版 P より新しい
#   - T が P と同じで、PR のブランチの開発環境の FROM の行が、今書き換えると書く行と違う
#     (配布元がタグを公開し直して digest が変わったとき)
#   - GitHub が PR を CONFLICTING と返す(Dependabot の digest だけの更新が main に入ったとき)
# どれにも当たらなければ push しない。書き換えられなければ、理由を標準エラーに1行出して 1 を返す
update() {
    local tool="$1" T="$2" C="$3" D="$4" idig="$5" text="$6" num="$7" oid="$8" mer="$9"
    local branch="chore/ci-tool-version-update-$1" err="$ERRF" P bfrom nfrom
    if ! [[ "$num" =~ ^[0-9]+$ ]] || ! [[ "$oid" =~ ^[0-9a-f]{40}$ ]]; then
        why "開いている PR の番号か headRefOid の形が違います(${num} ${oid})"
        return 1
    fi
    if ! git fetch -q origin "+refs/heads/${branch}:refs/remotes/origin/${branch}" 2>"$err" </dev/null ||
        ! git switch -q -f --detach "origin/${branch}" 2>"$err"; then
        why "PR のブランチを取れませんでした($(first "$err"))"
        return 1
    fi
    if ! P=$(ci_ver "$tool" 2>"$err"); then
        why "PR のブランチの版を読めませんでした($(first "$err"))"
        return 1
    fi
    if ! bfrom=$(civ_dev_from . "$tool" 2>"$err"); then
        why "PR のブランチの開発環境の版を読めませんでした($(first "$err"))"
        return 1
    fi
    if ! git switch -q -f --detach origin/main 2>"$err"; then
        why "main に戻れませんでした($(first "$err"))"
        return 1
    fi
    rewrite "$tool" "$T" "$C" "$D" "$idig" || return 1
    if ! nfrom=$(civ_dev_from . "$tool" 2>"$err"); then
        why "書き換えた開発環境の版を読めませんでした($(first "$err"))"
        return 1
    fi
    if ! civ_gt "$T" "$P" && ! { [ "$T" = "$P" ] && [ "$bfrom" != "$nfrom" ]; } && [ "$mer" != CONFLICTING ]; then
        return 0
    fi
    # PR を見たあとにほかのワークフローがブランチを更新していれば、push は失敗する
    if ! git push -q --force-with-lease="refs/heads/${branch}:${oid}" origin "HEAD:refs/heads/${branch}" 2>"$err" </dev/null; then
        why "ブランチを push できませんでした($(first "$err"))"
        return 1
    fi
    if ! gh pr edit "$num" --repo "$GITHUB_REPOSITORY" --title "$(head -n 1 <<<"$text")" \
        --body "$(tail -n +2 <<<"$text")" 2>"$err" </dev/null; then
        why "PR の題名と本文を書き換えられませんでした($(first "$err"))"
        return 1
    fi
}

# 使い方: run
run() {
    local tool line T C D tpub idig ipub text branch prs n failed=0 e="$CACHE/run-err"
    if [ -z "${GH_TOKEN:-}" ] || [ -z "${GITHUB_REPOSITORY:-}" ] || [ -z "${CI_TOOL_UPDATE_REPORT:-}" ]; then
        echo "環境変数 GH_TOKEN と GITHUB_REPOSITORY と CI_TOOL_UPDATE_REPORT を渡してください" >&2
        return 2
    fi
    # push にも GH_TOKEN の bot の PAT を使う。GitHub の標準のトークンで push した PR では、
    # ほかのワークフローが動かないためである
    if ! gh auth setup-git 2>"$e" </dev/null || ! git fetch -q origin main 2>"$e" </dev/null; then
        report "すべての道具" "更新の PR を作れなかった" "$(first "$e")"
        return 1
    fi
    # 1つの道具の失敗では止まらず、残りの道具を続ける
    for tool in node trivy codex terraform; do
        if ! git switch -q -f --detach origin/main 2>"$e"; then
            report "$tool" "新しい版を調べられなかった" "main に戻れませんでした($(first "$e"))"
            failed=1
            continue
        fi
        if ! line=$(plan "$tool" 2>"$e"); then
            report "$tool" "新しい版を調べられなかった" "$(first "$e")"
            failed=1
            continue
        fi
        [ -n "$line" ] || continue
        IFS=$'\t' read -r T C D tpub idig ipub <<<"$line"
        if ! text=$(body "$tool" "$T" "$C" "$D" "$tpub" "$idig" "$ipub" 2>"$e"); then
            report "$tool" "新しい版を調べられなかった" "$(first "$e")"
            failed=1
            continue
        fi
        branch="chore/ci-tool-version-update-${tool}"
        if ! prs=$(gh pr list --repo "$GITHUB_REPOSITORY" --head "$branch" --state open \
            --json number,headRefOid,mergeable 2>"$e" </dev/null) ||
            ! n=$(jq 'length' <<<"$prs" 2>/dev/null) || ! [[ "$n" =~ ^[0-9]+$ ]]; then
            report "$tool" "更新の PR を作れなかった" "開いている PR を調べられませんでした($(first "$e"))"
            failed=1
            continue
        fi
        # 開いている PR があれば、新しい PR を作らず、書き換えが要るときだけ書き換える
        if [ "$n" -gt 0 ]; then
            if ! update "$tool" "$T" "$C" "$D" "$idig" "$text" "$(jq -r '.[0].number' <<<"$prs")" \
                "$(jq -r '.[0].headRefOid' <<<"$prs")" "$(jq -r '.[0].mergeable' <<<"$prs")" 2>"$e"; then
                report "$tool" "更新の PR を書き換えられなかった" "$(first "$e")"
                failed=1
            fi
            continue
        fi
        # 所有者が閉じた PR のブランチが残っていても、main から作り直して push する
        if ! rewrite "$tool" "$T" "$C" "$D" "$idig" 2>"$e"; then
            report "$tool" "更新の PR を作れなかった" "$(first "$e")"
            failed=1
            continue
        fi
        if ! git push -q --force origin "HEAD:refs/heads/${branch}" 2>"$e" </dev/null; then
            report "$tool" "更新の PR を作れなかった" "ブランチを push できませんでした($(first "$e"))"
            failed=1
            continue
        fi
        if ! gh pr create --repo "$GITHUB_REPOSITORY" --base main --head "$branch" \
            --title "$(head -n 1 <<<"$text")" --body "$(tail -n +2 <<<"$text")" 2>"$e" </dev/null; then
            report "$tool" "更新の PR を作れなかった" "PR を作る操作が失敗しました($(first "$e"))"
            failed=1
        fi
    done
    # すべての道具を終えてから、1つでも失敗があれば 1 で終わる
    return "$failed"
}

case "${1:-}" in
plan)
    [ "$#" -eq 2 ] || usage
    case "$2" in
    node | trivy | codex | terraform) ;;
    *) usage ;;
    esac
    plan "$2"
    ;;
body)
    [ "$#" -eq 8 ] || usage
    case "$2" in
    node | trivy | codex | terraform) ;;
    *) usage ;;
    esac
    body "${@:2}"
    ;;
rewrite)
    [ "$#" -eq 6 ] || usage
    case "$2" in
    node | trivy | codex | terraform) ;;
    *) usage ;;
    esac
    rewrite "${@:2}"
    ;;
run)
    [ "$#" -eq 1 ] || usage
    run
    ;;
*) usage ;;
esac
