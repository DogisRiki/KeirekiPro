#!/usr/bin/env bash
# =====================================================================
# frontend/pnpm-workspace.yaml の minimumReleaseAgeExclude に、渡された npm の版ごとに、
# その版を指す要素があるかを返す(check-dependency-cooldown.sh から呼ばれる)
#
# なぜ版を指す要素が要るのか:
#   pnpm は --frozen-lockfile のインストールでも、公開から72時間経っていない版を拒む。
#   72時間待たずに入れた版を、マージのあとの CI と開発者の環境と本番の組み立てで
#   入れられるようにするには、除外の欄にその版を指す要素が要る。
#
# 版を指す要素: '<名前>@<版>' か '<名前>@<版1> || <版2>' の形で、版の1つが一致する要素。
#   名前だけの要素と名前のパターンの要素は、その部品のすべての版を除外するので数えない。
#
# 読み方: minimumReleaseAgeExclude: の行の下の、- で始まる行を、次のキーの行まで読む。
#   コメントの行と空の行は飛ばす。要素を囲む ' と " は外す。
#   キーと同じ行に値がある書き方([...] の中に並べる書き方を含む)は、読めないものとする。
#   除外の欄が無ければ、要素が無いものとする。
#
# テスト: .github/scripts/tests/test-cooldown-check-pnpm-exclude.sh
# 使い方: cooldown-check-pnpm-exclude.sh <pnpm-workspace.yaml> <入力のファイル>
#   入力: [{"name","version"}]
#   出力(標準出力): 入力と同じ順の配列 [{"name","version","present":true|false,"line":"  - '<名前>@<版>'"}]
#     line は、版を指す要素が無いときに足すべき1行である
#   終了コード 0 = 読めた / 2 = ファイルを読めない、キーと同じ行に値がある、引数か入力の誤り
# =====================================================================
set -euo pipefail

usage() {
    echo "使い方: cooldown-check-pnpm-exclude.sh <pnpm-workspace.yaml> <入力のファイル>" >&2
    exit 2
}
[ "$#" -eq 2 ] || usage
WS="$1"
INPUT="$2"
if [ ! -f "$WS" ] || [ ! -r "$WS" ]; then
    echo "pnpm-workspace.yaml を読めません: ${WS}" >&2
    exit 2
fi
[ -f "$INPUT" ] || usage
if ! jq -e 'type == "array" and all(.[]; type == "object"
        and (.name | type) == "string" and (.version | type) == "string")' "$INPUT" >/dev/null 2>&1; then
    echo "入力が [{\"name\",\"version\"}] の形の JSON の配列ではありません: ${INPUT}" >&2
    exit 2
fi

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# 要素を1行に1つずつ書き出す。awk の終了コード 3 = キーと同じ行に値がある
rc=0
awk '
    /^minimumReleaseAgeExclude:/ {
        rest = $0
        sub(/^minimumReleaseAgeExclude:[ \t]*/, "", rest)
        sub(/^#.*$/, "", rest)
        sub(/[ \t]+#.*$/, "", rest)
        if (rest != "") { bad = 1; exit }
        inlist = 1
        next
    }
    inlist && /^[ \t]*(#.*)?$/ { next }
    inlist && /^[ \t]*- / {
        v = $0
        sub(/^[ \t]*- [ \t]*/, "", v)
        if (v ~ /^'\''/) { sub(/^'\''/, "", v); sub(/'\''.*$/, "", v) }
        else if (v ~ /^"/) { sub(/^"/, "", v); sub(/".*$/, "", v) }
        else { sub(/[ \t]+#.*$/, "", v); sub(/[ \t]+$/, "", v) }
        print v
        next
    }
    inlist { inlist = 0 }
    END { if (bad) exit 3 }
' "$WS" >"$TMP/elements.txt" || rc=$?
case "$rc" in
0) ;;
3)
    echo "minimumReleaseAgeExclude の値が、キーと同じ行に書かれています([...] の中に並べる書き方を含む)。1行に1つの要素を - で始めて書いてください: ${WS}" >&2
    exit 2
    ;;
*)
    echo "pnpm-workspace.yaml を読めません: ${WS}" >&2
    exit 2
    ;;
esac

# shellcheck disable=SC2016 # jq の変数であり、シェルの展開ではない
jq -c --rawfile el "$TMP/elements.txt" '
    [ $el | split("\n")[] | select(length > 0)
      | capture("^(?<name>@?[^@]+)@(?<vers>.+)$")
      | {name, vers: [.vers | splits("\\|\\|") | gsub("^\\s+|\\s+$"; "")]} ] as $elements
    | map(.name as $n | .version as $v
        | {name: $n, version: $v,
           present: any($elements[]; .name == $n and any(.vers[]; . == $v)),
           line: "  - '\''\($n)@\($v)'\''"})
' "$INPUT"
