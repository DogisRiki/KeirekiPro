#!/usr/bin/env bash
# =====================================================================
# CI の道具の公開からの時間の検査(dependency-review の cooldown から実行)
#
# 判定: PR の分かれ目のコミットと head で、4つの道具の CI の版と、Node.js と Terraform の
#   開発環境の版を比べ、変わった版ごとに lib-ci-tool-releases.sh の ci_tool_age_check で、
#   公開から72時間経っているかを調べる。72時間経っていない版と、公開日時を取れなかった
#   版を止める。開発環境の版では、FROM の digest が配布元のイメージのタグの今の digest と
#   違うときも止める。
#   分かれ目のコミットとは、PR のブランチを main から分けたときの main のコミット
#   (base と head の merge-base)である。
#
# 変わった版の見つけ方:
#   CI の版は、head のデータのファイル .github/ci-tool-versions.json の ci の組ごとに、
#   分かれ目の版の集まりに無い head の版を、変わった版とする。行番号では比べない。
#   版の行より上に行を足しただけの PR で、変わっていない版を変わったと読まないためである。
#   開発環境の版は、FROM のタグの版が違うときだけ変わったとする。digest だけの違いは
#   変わったとしない。
#   分かれ目の版も、head のデータのファイルの書き場所で読む。分かれ目のデータのファイルは
#   読まない。データのファイルが main に入る前に分けたブランチの PR でも、版を変えて
#   いなければ通すためである。分かれ目に無いファイルは、空のファイルとして読む。
#
# 例外: PR の本文の記録の目印の行 <!-- ci-tool-cooldown-exception data=<base64> --> を
#   すべて読み、entries の tool と version が CI の版の変更と一致し、signature.result が
#   verified の要素があれば、その CI の版の変更を、公開からの時間を調べずに通す。
#   開発環境の版の変更と、記録に無い道具の変更は、例外にしない。目印の行のどれか1つでも
#   形が違えば、例外を1つも当てない。
#   このスクリプトは、PR の作者とブランチの名前を読まない。更新の PR と、手で版を
#   書き換えた PR を、同じく調べるためである。
#
# 出力: 調べた変更ごとに、道具、場所、版、公開日時、通る日時、結果の表を
#   GITHUB_STEP_SUMMARY と標準出力に書き、止めた変更ごとに ::error:: の行を出す。
#   変わった CI の版を、例外で通したものも含めて、CI_TOOL_CHANGED_FILE に
#   「道具<TAB>版」の形で1行ずつ書く(変わった版が無ければ空のファイルにする)。
#   4つの道具の版が1つも変わらなければ、配布元に問い合わせずに 0 で終わる。
#
# 終了コード: 0 = 止めた変更が無い / 1 = 止めた変更があるか、分かれ目のコミットを
#   取れない / 2 = 引数か環境変数の形が違うか、データのファイルを読めないか、
#   書き場所の版を読めない
#
# 公開日時の問い合わせが失敗したときは、その変更を止める。通る日時を過ぎてから
# ジョブを Re-run すれば、同じ版で通る。
#
# テスト: .github/scripts/tests/test-check-ci-tool-release-age.sh
# 環境変数: GH_TOKEN GITHUB_REPOSITORY PR_NUMBER CI_TOOL_CHANGED_FILE
#   GITHUB_STEP_SUMMARY(無ければ標準出力にだけ書く)
# 使い方: check-ci-tool-release-age.sh <base> <head>(今のフォルダを head の根とする)
# =====================================================================
set -uo pipefail

BASE_SHA="${1:-}"
HEAD_SHA="${2:-}"
REPO="${GITHUB_REPOSITORY:-}"
PR="${PR_NUMBER:-}"
CHANGED="${CI_TOOL_CHANGED_FILE:-}"
SUMMARY="${GITHUB_STEP_SUMMARY:-/dev/null}"
MARKER="ci-tool-cooldown-exception"

# shellcheck source=.github/scripts/lib-ci-tool-releases.sh
source "$(cd "$(dirname "$0")" && pwd)/lib-ci-tool-releases.sh"

usage() {
    echo "::error::$1(使い方: check-ci-tool-release-age.sh <base> <head>。環境変数 GITHUB_REPOSITORY PR_NUMBER CI_TOOL_CHANGED_FILE が要ります)"
    exit 2
}
[[ "$BASE_SHA" =~ ^[0-9a-f]{7,40}$ ]] || usage "base の形が違います: ${BASE_SHA}"
[[ "$HEAD_SHA" =~ ^[0-9a-f]{7,40}$ ]] || usage "head の形が違います: ${HEAD_SHA}"
[[ "$REPO" =~ ^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$ ]] || usage "GITHUB_REPOSITORY の形が違います: ${REPO}"
[[ "$PR" =~ ^[0-9]+$ ]] || usage "PR_NUMBER の形が違います: ${PR}"
[ -n "$CHANGED" ] || usage "CI_TOOL_CHANGED_FILE がありません"
: >"$CHANGED" || usage "CI_TOOL_CHANGED_FILE に書けません: ${CHANGED}"

if ! data=$(_civ_data .); then
    echo "::error::データのファイル .github/ci-tool-versions.json を読めませんでした"
    exit 2
fi

TMP=$(mktemp -d) || exit 2
[ -n "$TMP" ] && [ -d "$TMP" ] || exit 2
trap 'rm -rf "$TMP"' EXIT

# 使い方: err <文>。::error:: の行を出す。% は GitHub の書式で %25 にする
err() {
    echo "::error::${1//%/%25}"
}

# --- 分かれ目のコミットの書き場所を、一時の根のフォルダに写す ---------------
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

BROOT="$TMP/base"
mkdir -p "$BROOT/.github"
cp "$data" "$BROOT/.github/ci-tool-versions.json"
files=$(jq -r '[.tools[] | ((.ci // [])[].file), (.dev.file // empty)] | unique | .[]' "$data") || {
    err "データのファイルの書き場所のファイルを読めませんでした"
    exit 2
}
while IFS= read -r f; do
    [ -n "$f" ] || continue
    mkdir -p "$BROOT/$(dirname "$f")"
    # 分かれ目に無いファイルは、空のファイルとして読む
    git show "${MB}:${f}" >"$BROOT/$f" 2>/dev/null || : >"$BROOT/$f"
done <<<"$files"

# --- 変わった版を見つける ---------------------------------------------------
# 変わった版を「道具<TAB>場所<TAB>版<TAB>digest」で $TMP/changes に書く。場所は ci か dev
: >"$TMP/changes"
tools=$(jq -r '.tools | keys[]' "$data")
while IFS= read -r t; do
    [ -n "$t" ] || continue
    if ! head_ci=$(_civ_pair_lines . "$t") || ! base_ci=$(_civ_pair_lines "$BROOT" "$t"); then
        err "${t} の CI の版を読めませんでした"
        exit 2
    fi
    # ファイルと名前の組ごとに、分かれ目の版の集まりに無い head の版を出す。先頭の v は外して比べる
    awk -F '\t' -v t="$t" '
        NR == FNR { if ($4 != "-") { v = $4; sub(/^v/, "", v); seen[$1 SUBSEP $3 SUBSEP v] = 1 }; next }
        $4 != "-" { v = $4; sub(/^v/, "", v); if (!((($1 SUBSEP $3 SUBSEP v) in seen)) && !(v in done)) { done[v] = 1; print t "\tci\t" v "\t-" } }
    ' <(printf '%s\n' "$base_ci") <(printf '%s\n' "$head_ci") >>"$TMP/changes"
    if [ -n "$(_civ_dev "$data" "$t")" ]; then
        if ! head_dev=$(civ_dev_from . "$t"); then
            err "${t} の開発環境の版を読めませんでした"
            exit 2
        fi
        base_dev=$(civ_dev_from "$BROOT" "$t" 2>/dev/null) || base_dev=""
        IFS="$(printf '\t')" read -r hv _ hd <<<"$head_dev"
        bv=$(printf '%s\n' "$base_dev" | cut -f1)
        if [ "${hv#v}" != "${bv#v}" ]; then
            printf '%s\tdev\t%s\t%s\n' "$t" "${hv#v}" "$hd" >>"$TMP/changes"
        fi
    fi
done <<<"$tools"

if [ ! -s "$TMP/changes" ]; then
    echo "CI の道具の公開からの時間の検査: 4つの道具の版の変更はありません。"
    {
        echo "## CI の道具の公開からの時間の検査"
        echo ""
        echo "4つの道具の版の変更はありません。"
    } >>"$SUMMARY"
    exit 0
fi
awk -F '\t' '$2 == "ci" { print $1 "\t" $3 }' "$TMP/changes" >"$CHANGED"

# --- 記録の目印の行から、例外にする CI の版を読む ---------------------------
# 例外にする版を「道具<TAB>版」で $TMP/allowed に書く
: >"$TMP/allowed"
if grep -q $'\tci\t' "$TMP/changes"; then
    if ! gh api "repos/${REPO}/pulls/${PR}" >"$TMP/pr.json" 2>"$TMP/err"; then
        echo "::warning::PR #${PR} の本文を読めなかったため、記録の例外を当てずに調べます"
    else
        body=$(jq -r '.body // ""' "$TMP/pr.json" 2>/dev/null)
        mapfile -t marks < <(printf '%s' "$body" |
            jq -Rrs --arg m "$MARKER" '[scan("<!-- " + $m + " data=([^ ]*) -->") | .[0]] | .[]')
        prefixes=$(printf '%s' "$body" | jq -Rrs --arg m "$MARKER" '[scan("<!-- " + $m)] | length')
        ok=true
        [ "$prefixes" -eq "${#marks[@]}" ] || ok=false
        : >"$TMP/allowed.new"
        for m in "${marks[@]}"; do
            "$ok" || break
            if ! raw=$(printf '%s' "$m" | base64 -d 2>/dev/null) ||
                ! printf '%s' "$raw" | jq -er '
                    def str: type == "string" and length > 0;
                    if .schema == 1 and (.entries | type == "array" and length > 0)
                       and all(.entries[]; (.tool | str) and (.version | str)
                           and (.signature | type == "object") and (.signature.result | str))
                    then .entries[] | select(.signature.result == "verified")
                        | "\(.tool)\t\(.version | ltrimstr("v"))"
                    else error("記録の JSON の形が違う") end' >>"$TMP/allowed.new" 2>/dev/null; then
                ok=false
            fi
        done
        if "$ok"; then
            cp "$TMP/allowed.new" "$TMP/allowed"
        elif [ "$prefixes" -gt 0 ]; then
            echo "::warning::PR #${PR} の本文の記録の目印の行の形が違うため、記録の例外を1つも当てずに調べます"
        fi
    fi
fi

# --- 変わった版ごとに判定する -----------------------------------------------
{
    echo "## CI の道具の公開からの時間の検査"
    echo ""
    echo "| 道具 | 場所 | 版 | 公開日時 | 通る日時 | 結果 |"
    echo "|---|---|---|---|---|---|"
} >"$TMP/table"
stopped=0
broken=0
while IFS="$(printf '\t')" read -r t place v digest; do
    [ -n "$t" ] || continue
    name=$(jq -r --arg t "$t" '.tools[$t].name // $t' "$data")
    where="CI" wm="CI の"
    [ "$place" = dev ] && where="開発環境" wm="開発環境の"
    if [ "$place" = ci ] && awk -F '\t' -v t="$t" -v v="$v" '$1 == t && $2 == v { f = 1 } END { exit !f }' "$TMP/allowed"; then
        printf '| %s | %s | %s | - | - | 記録の例外で通しました |\n' "$name" "$where" "$v" >>"$TMP/table"
        continue
    fi
    if [ "$place" = ci ]; then
        rows=$(ci_tool_age_check . "$t" "$v" - - 2>"$TMP/err")
    else
        rows=$(ci_tool_age_check . "$t" - "$v" "$digest" 2>"$TMP/err")
    fi
    rc=$?
    if [ "$rc" -eq 2 ]; then
        err "${wm} ${name} の版 ${v} を調べられませんでした: $(tr '\n' ' ' <"$TMP/err")"
        printf '| %s | %s | %s | - | - | 調べられませんでした |\n' "$name" "$where" "$v" >>"$TMP/table"
        broken=1
        continue
    fi
    seen=0
    hit=0
    while IFS="$(printf '\t')" read -r _ rv pub pass result why; do
        [ -n "$result" ] || continue
        seen=$((seen + 1))
        [ "$result" = ok ] || hit=$((hit + 1))
        case "$result" in
        ok)
            printf '| %s | %s | %s | %s | %s | 通しました |\n' "$name" "$where" "$rv" "$pub" "$pass" >>"$TMP/table"
            ;;
        ng)
            printf '| %s | %s | %s | %s | %s | 止めました(%s) |\n' "$name" "$where" "$rv" "$pub" "$pass" "$why" >>"$TMP/table"
            err "${wm} ${name} の版 ${rv} を止めました: ${why}。公開日時は ${pub}、検査が通るようになる日時は ${pass} です。その日時を過ぎてから、ジョブを Re-run してください"
            stopped=1
            ;;
        *)
            printf '| %s | %s | %s | 取れなかった | 取れなかった | 止めました(%s) |\n' "$name" "$where" "$rv" "$why" >>"$TMP/table"
            err "${wm} ${name} の版 ${rv} を止めました: 公開日時か digest を取れませんでした(${why})。ジョブを Re-run してください"
            stopped=1
            ;;
        esac
    done <<<"$rows"
    # 判定の関数が結果の行を出さないか、失敗を返したのに止める行を出さないときも、
    # 判定を確かめられないまま通さずに止める
    if [ "$seen" -eq 0 ] || { [ "$rc" -ne 0 ] && [ "$hit" -eq 0 ]; }; then
        why=$(tr '\n' ' ' <"$TMP/err" | sed 's/ *$//')
        [ -n "$why" ] || why="理由の出力はありません"
        printf '| %s | %s | %s | 取れなかった | 取れなかった | 止めました(判定の結果を読めませんでした) |\n' "$name" "$where" "$v" >>"$TMP/table"
        err "${wm} ${name} の版 ${v} を止めました: 判定の結果を読めませんでした(${why})。ジョブを Re-run してください"
        stopped=1
    fi
done <"$TMP/changes"

cat "$TMP/table" >>"$SUMMARY"
cat "$TMP/table"
[ "$broken" -eq 0 ] || exit 2
[ "$stopped" -eq 0 ] || exit 1
exit 0
