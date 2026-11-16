#!/usr/bin/env bash
# =====================================================================
# Go の版の公開からの時間の検査(dependency-review の cooldown から実行)
#
# 判定: PR の分かれ目のコミットと head で、Go の版を書くすべてのファイルから Go の版を読み、
#   分かれ目に無い head の版ごとに、Go の配布元が公開してから72時間経っているかを調べる。
#   72時間経っていない版と、公開日時を取れなかった版と、版を読めない書き方を止める。
#   分かれ目のコミットとは、PR のブランチを main から分けたときの main のコミット
#   (base と head の merge-base)である。
#
# Go の版を読むファイルと読み方は lib-go-release.sh に従う(go.mod の go と toolchain の行、
#   Dockerfile の FROM golang の行)。ファイルの場所は問わず、コミットのすべてのファイルを見る。
#
# 変わった版の見つけ方:
#   head のすべてのファイルの版の集まりから、分かれ目のすべてのファイルの版の集まりにある版を
#   除いたものを、変わった版とする。ファイルごとには比べない。分かれ目のどこかに書いてあった
#   版は、main に入るときにこの検査を通っているためである。版を読めない書き方も、同じ書き方が
#   分かれ目に無ければ止める。
#
# 例外は無い。Go の版は、セキュリティの修正の版でも、公開から72時間経つまで止める。
#   このスクリプトは、PR の作者とブランチの名前と、所有者の承認を読まない。
#
# 出力: 変わった版ごとに、版、書いた場所、公開日時、通る日時、結果の表を
#   GITHUB_STEP_SUMMARY と標準出力に書き、止めた版ごとに ::error:: の行を出す。
#   Go の版が1つも変わらなければ、配布元に問い合わせずに 0 で終わる。
#
# 終了コード: 0 = 止めた版が無い / 1 = 止めた版があるか、分かれ目のコミットを取れない /
#   2 = 引数か環境変数の形が違うか、コミットのファイルを読めない
#
# 公開日時の問い合わせが失敗したときは、その版を止める。通る日時を過ぎてから、または
# 配布元が答えるようになってから、ジョブを Re-run すれば、同じ版で通る。
#
# テスト: .github/scripts/tests/test-check-go-release-age.sh
# 環境変数: GH_TOKEN GITHUB_REPOSITORY GITHUB_STEP_SUMMARY(無ければ標準出力にだけ書く)
#   NOW_EPOCH(テストが今の時刻を与える。無ければ date +%s)
#   GO_DL_BASE(lib-go-release.sh が読む。テストが配布元を差し替える)
# 使い方: check-go-release-age.sh <base> <head>(今のフォルダを head の写しの根とする)
# =====================================================================
set -uo pipefail

BASE_SHA="${1:-}"
HEAD_SHA="${2:-}"
REPO="${GITHUB_REPOSITORY:-}"
SUMMARY="${GITHUB_STEP_SUMMARY:-/dev/null}"
# 72時間を秒で表す
WAIT=259200

# shellcheck source=.github/scripts/lib-go-release.sh
source "$(cd "$(dirname "$0")" && pwd)/lib-go-release.sh"

usage() {
    echo "::error::$1(使い方: check-go-release-age.sh <base> <head>。環境変数 GITHUB_REPOSITORY が要ります)"
    exit 2
}
[[ "$BASE_SHA" =~ ^[0-9a-f]{7,40}$ ]] || usage "base の形が違います: ${BASE_SHA}"
[[ "$HEAD_SHA" =~ ^[0-9a-f]{7,40}$ ]] || usage "head の形が違います: ${HEAD_SHA}"
[[ "$REPO" =~ ^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$ ]] || usage "GITHUB_REPOSITORY の形が違います: ${REPO}"
NOW="${NOW_EPOCH:-}"
[ -n "$NOW" ] || NOW=$(date +%s)
[[ "$NOW" =~ ^[0-9]+$ ]] || usage "今の時刻の形が違います: ${NOW}"

TMP=$(mktemp -d) || exit 2
[ -n "$TMP" ] && [ -d "$TMP" ] || exit 2
trap 'rm -rf "$TMP"' EXIT

# 使い方: err <文>。::error:: の行を出す。% は GitHub の書式で %25 にする
err() {
    echo "::error::${1//%/%25}"
}

# 使い方: iso <秒>。1970-01-01T00:00:00Z からの秒を 2026-11-10T16:48:48Z の形にする
iso() {
    jq -n -r --argjson e "$1" '$e | todate'
}

# 使い方: collect <コミット> <出力のファイル>。コミットの、Go の版を読むファイルごとに、
# 「版<TAB>パス」を1行ずつ書く。コミットのファイルを読めなければ 1 を返す
collect() {
    local c="$1" out="$2" line meta f
    : >"$out"
    git ls-tree -r -z "$c" >"$TMP/tree" 2>"$TMP/err" || return 1
    while IFS= read -r -d '' line; do
        meta="${line%%$'\t'*}"
        f="${line#*$'\t'}"
        # ファイルの中身だけを読む。サブモジュールとシンボリックリンクは読まない
        [[ "$meta" =~ ^100[0-9]{3}\ blob\  ]] || continue
        go_release_is_target "$f" || continue
        git cat-file blob "${c}:${f}" >"$TMP/blob" 2>"$TMP/err" || return 1
        go_release_versions_of "$f" <"$TMP/blob" | awk -v f="$f" 'NF { print $0 "\t" f }' >>"$out"
    done <"$TMP/tree"
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
if ! git cat-file -e "${MB}^{commit}" 2>/dev/null &&
    ! git fetch --quiet --no-tags --depth=1 origin "$MB" 2>"$TMP/err"; then
    err "分かれ目のコミット ${MB} を取れませんでした(git fetch が失敗しました: $(head -n 1 "$TMP/err"))"
    exit 1
fi

# --- 変わった版を見つける ---------------------------------------------------
if ! collect "$HEAD_SHA" "$TMP/head.tsv"; then
    err "head のコミット ${HEAD_SHA} のファイルを読めませんでした: $(head -n 1 "$TMP/err")"
    exit 2
fi
if ! collect "$MB" "$TMP/base.tsv"; then
    err "分かれ目のコミット ${MB} のファイルを読めませんでした: $(head -n 1 "$TMP/err")"
    exit 2
fi
# 分かれ目に無い head の版を、見つけた順に「版<TAB>書いた場所(、で区切る)」で書く
awk -F '\t' '
    NR == FNR { seen[$1] = 1; next }
    !($1 in seen) {
        if (!($1 in at)) { n++; order[n] = $1; at[$1] = "" }
        if (!(($1 SUBSEP $2) in pair)) {
            pair[$1 SUBSEP $2] = 1
            at[$1] = at[$1] (at[$1] == "" ? "" : "、") $2
        }
    }
    END { for (i = 1; i <= n; i++) print order[i] "\t" at[order[i]] }
' "$TMP/base.tsv" "$TMP/head.tsv" >"$TMP/changes"

if [ ! -s "$TMP/changes" ]; then
    echo "Go の版の公開からの時間の検査: Go の版の変更はありません。"
    {
        echo "## Go の版の公開からの時間の検査"
        echo ""
        echo "Go の版の変更はありません。"
    } >>"$SUMMARY"
    exit 0
fi

# --- 変わった版ごとに判定する -----------------------------------------------
{
    echo "## Go の版の公開からの時間の検査"
    echo ""
    echo "| 版 | 書いた場所 | 公開日時 | 通る日時 | 結果 |"
    echo "|---|---|---|---|---|"
} >"$TMP/table"
stopped=0
while IFS="$(printf '\t')" read -r v where; do
    [ -n "$v" ] || continue
    if [ "${v:0:1}" = "?" ]; then
        raw="${v:1}"
        printf '| %s | %s | - | - | 止めました(版を読めない書き方です) |\n' "$raw" "$where" >>"$TMP/table"
        err "${where} の Go の版の書き方「${raw}」を止めました: 版を読めない書き方です。golang:1.27.4-trixie や toolchain go1.27.4 のように、版を決めて書いてください"
        stopped=1
        continue
    fi
    if ! pub=$(go_release_published "$v" 2>"$TMP/err") || ! [[ "$pub" =~ ^[0-9]+$ ]]; then
        why=$(tr '\n' ' ' <"$TMP/err" | sed 's/ *$//')
        [ -n "$why" ] || why="理由の出力はありません"
        printf '| %s | %s | 取れなかった | 取れなかった | 止めました(%s) |\n' "$v" "$where" "$why" >>"$TMP/table"
        err "Go の版 ${v} を止めました: 公開日時を取れませんでした(${why})。書いた場所は ${where} です。ジョブを Re-run してください"
        stopped=1
        continue
    fi
    pub_at=$(iso "$pub")
    pass_at=$(iso $((pub + WAIT)))
    if [ $((NOW - pub)) -ge "$WAIT" ]; then
        printf '| %s | %s | %s | %s | 通しました |\n' "$v" "$where" "$pub_at" "$pass_at" >>"$TMP/table"
    else
        printf '| %s | %s | %s | %s | 止めました(公開から72時間経っていません) |\n' "$v" "$where" "$pub_at" "$pass_at" >>"$TMP/table"
        err "Go の版 ${v} を止めました: 公開から72時間経っていません。公開日時は ${pub_at}、検査が通るようになる日時は ${pass_at} です。書いた場所は ${where} です。その日時を過ぎてから、ジョブを Re-run してください"
        stopped=1
    fi
done <"$TMP/changes"

cat "$TMP/table" >>"$SUMMARY"
cat "$TMP/table"
[ "$stopped" -eq 0 ] || exit 1
exit 0
