#!/usr/bin/env bash
# =====================================================================
# push の前に、CI の dependency-review と同じ判定を手元で流す(/ship の手順1が呼ぶ)
#
# 使い方: bash .claude/scripts/ship/pre-push-dependency-review.sh [--base <コミット>] [--head <コミット>]
#   作業フォルダの中で動かす。
#   --base  比べる元のコミット。既定は git merge-base origin/main HEAD(PR の比べる先に当たる)
#   --head  調べるコミット。既定は作業フォルダのファイル(まだ commit していない変更を含む)。
#           過去の push の前の変更を手元で確かめ直すときに渡す
#
# CI の dependency-review(.github/workflows/dependency-review.yaml)は、PR で増えた部品に
# moderate 以上の脆弱性があれば赤になる。ここでは、増えた部品(名前と版の組)を pre-push-deps.pl で求め、
# CI と同じ GitHub の脆弱性の一覧(GET /advisories)に照らし、medium(CI の moderate)以上があれば止まったとする。
# 増えた部品は backend/go.mod と frontend/pnpm-lock.yaml を比べて求める(maven を読まない理由は pre-push-deps.pl)。
#
# 終了コード: 0 = 通った / 1 = 止まった / 2 = 調べられなかった / 3 = 使い方の誤りか、調べる準備ができなかった
# 前提: bash・git・perl・gh(ログイン済み)。jq には依存しない。
# 問い合わせる先: api.github.com(gh)。部品の名前と版を問い合わせに使う。読むだけで、何も書き込まない。
# =====================================================================
set -uo pipefail

usage() { echo "使い方: bash .claude/scripts/ship/pre-push-dependency-review.sh [--base <コミット>] [--head <コミット>]" >&2; exit 3; }
fail_setup() { echo "準備ができませんでした: $*" >&2; exit 3; }

BASE_ARG=""
HEAD_ARG=""
while [ $# -gt 0 ]; do
    case "$1" in
    --base) [ $# -ge 2 ] || usage; BASE_ARG="$2"; shift 2 ;;
    --head) [ $# -ge 2 ] || usage; HEAD_ARG="$2"; shift 2 ;;
    *) usage ;;
    esac
done

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
TOP=$(git rev-parse --show-toplevel 2>/dev/null) || fail_setup "git の作業フォルダの中で動かしてください"

if [ -n "$BASE_ARG" ]; then
    BASE=$(git -C "$TOP" rev-parse --verify --quiet "${BASE_ARG}^{commit}") || fail_setup "比べる元のコミット $BASE_ARG が無い"
else
    BASE=$(git -C "$TOP" merge-base origin/main HEAD) || fail_setup "origin/main との分かれ目を求められない"
fi
if [ -n "$HEAD_ARG" ]; then
    HEAD_SHA=$(git -C "$TOP" rev-parse --verify --quiet "${HEAD_ARG}^{commit}") || fail_setup "調べるコミット $HEAD_ARG が無い"
fi

TMP=$(mktemp -d) || fail_setup "一時のフォルダを作れない"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/base" "$TMP/head"

# 比べる元はコミットから、調べる側は --head のコミットか作業フォルダのファイルから取り出す
for f in backend/go.mod frontend/pnpm-lock.yaml; do
    name=$(basename "$f")
    git -C "$TOP" show "${BASE}:${f}" >"$TMP/base/$name" 2>/dev/null || rm -f "$TMP/base/$name"
    if [ -n "$HEAD_ARG" ]; then
        git -C "$TOP" show "${HEAD_SHA}:${f}" >"$TMP/head/$name" 2>/dev/null || rm -f "$TMP/head/$name"
    elif [ -f "$TOP/$f" ]; then
        cp "$TOP/$f" "$TMP/head/$name" || fail_setup "$f を読めない"
    fi
done

echo "比べる元: ${BASE}"
echo "調べる側: ${HEAD_SHA:-作業フォルダのファイル(まだ commit していない変更を含む)}"

ADDED="$TMP/added.tsv"
perl "$HERE/pre-push-deps.pl" "$TMP/base" "$TMP/head" >"$ADDED" || fail_setup "増えた部品を求められない"
added_count=$(grep -c . "$ADDED" || true)
echo "増えた部品: ${added_count} 組"
if [ "$added_count" -eq 0 ]; then
    echo "dependency-review: 通った(増えた部品が無い)"
    exit 0
fi

# 増えた部品を、種類ごとに30組ずつまとめて一覧に照らし、名前が出た組を候補にする。
# 候補は1組ずつ照らし直す。まとめて照らした結果からは、どの組の版が当たったかを読めないためである。
# 一覧の種類の名前は、go.mod の部品が go、pnpm の部品が npm である
fail_check() { echo "dependency-review: 調べられなかった"; echo "  GitHub の脆弱性の一覧を読めない: $(head -n 1 "$TMP/gh.err")"; exit 2; }
hits=""
notes=""
for eco in gomod npm; do
    awk -F'\t' -v e="$eco" '$1 == e { print $2 "@" $3 }' "$ADDED" >"$TMP/affects-$eco.txt"
    [ -s "$TMP/affects-$eco.txt" ] || continue
    api_eco=$eco
    [ "$eco" = gomod ] && api_eco=go
    : >"$TMP/candidates-$eco.txt"
    split -l 30 "$TMP/affects-$eco.txt" "$TMP/chunk-$eco-"
    for chunk in "$TMP"/chunk-"$eco"-*; do
        names=$(gh api -X GET advisories -f ecosystem="$api_eco" -f affects="$(paste -sd, "$chunk")" -f per_page=100 --paginate \
            --jq '.[] | select(.withdrawn_at == null) | .vulnerabilities[]? | .package.name' 2>"$TMP/gh.err") || fail_check
        printf '%s\n' "$names" | sort -u |
            awk 'NR == FNR { n[$0] = 1; next } { p = $0; sub(/@[^@]*$/, "", p); if (p in n) print }' - "$chunk" >>"$TMP/candidates-$eco.txt"
    done
    while IFS= read -r pv; do
        [ -n "$pv" ] || continue
        rows=$(gh api -X GET advisories -f ecosystem="$api_eco" -f affects="$pv" -f per_page=100 --paginate \
            --jq '.[] | select(.withdrawn_at == null) | "\(.ghsa_id) \(.severity) \(.html_url)"' 2>"$TMP/gh.err") || fail_check
        while read -r ghsa sev url; do
            [ -n "$ghsa" ] || continue
            case "$sev" in
            medium | high | critical) hits+="  - ${eco} ${pv}: ${ghsa}(${sev}) ${url}"$'\n' ;;
            *) notes+="  - ${eco} ${pv}: ${ghsa}(${sev}。CI は moderate 未満では止めない)"$'\n' ;;
            esac
        done <<<"$rows"
    done <"$TMP/candidates-$eco.txt"
done

if [ -n "$hits" ]; then
    echo "dependency-review: 止まった(増えた部品に moderate 以上の脆弱性がある)"
    printf '%s' "$hits"
else
    echo "dependency-review: 通った"
fi
[ -z "$notes" ] || printf '  止めない脆弱性:\n%s' "$notes"
[ -z "$hits" ] || exit 1
