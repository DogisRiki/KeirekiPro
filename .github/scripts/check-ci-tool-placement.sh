#!/usr/bin/env bash
# =====================================================================
# 版の書き場所の検査(guardrails CI の escape-hatch から実行)
#
# 判定: ワークフローとアクションに直接書いた道具の版の行を、lib-ci-tool-versions.sh の
#   civ_scan で見つけ、データのファイル .github/ci-tool-versions.json と棚卸しの対象の
#   一覧 .github/audit/inventory-targets.json に照らす。次のどれかに当たれば、当たった
#   行ごとに ::error file=<ファイル>,line=<行番号>::<理由> を出し、全部を調べてから
#   exit 1(赤)。どれにも当たらなければ exit 0(緑)。
#     1. 版の行のファイルと名前の組が、どの道具の ci にも excluded にも無い。
#        名前が4つの道具の keys に入っていれば、その道具の ci に足す必要があると書き、
#        そうでなければ、tools か excluded に足す必要があると書く
#     2. excluded の組の名前が、4つの道具の keys に入っている
#     3. 1つの道具の ci の場所で、版が1種類でない。版ごとの場所を並べる
#     4. ci か excluded の組が指す行が、ファイルに1つも無い
#     5. excluded の組に reason が無いか、空である
#     6. 棚卸しの対象の一覧に、道具の inventory_name の対象が無いか、対象の宣言の
#        ファイルが、道具の ci と開発環境のファイルを全部は含まない
#   データのファイルか棚卸しの対象の一覧を読めないときは exit 2。
#   2、4、5 はデータのファイルの組の行を、6 は棚卸しの対象の行を、エラーの行にする。
#
# なぜ検査するか:
#   ワークフローに新しく道具を足しても、データのファイルに載せなければ、その道具は
#   週1回の実行で上がらず、古い版のまま動き続ける。4つの道具の版を、データのファイルに
#   載っていない場所に書いたときも、その場所だけが古い版のまま残る。どちらも、マージの
#   前に気づけるよう、PR ごとに今の状態の全体を調べる。
#
# 外部には問い合わせない。所有者の承認では、この検査の結果は変わらない。
# テスト: .github/scripts/tests/test-check-ci-tool-placement.sh
# 使い方: check-ci-tool-placement.sh [<根のフォルダ>](既定は今のフォルダ)
# =====================================================================
set -uo pipefail

ROOT="${1:-.}"
DATA_REL=.github/ci-tool-versions.json
INV_REL=.github/audit/inventory-targets.json

# shellcheck source=.github/scripts/lib-ci-tool-versions.sh
source "$(cd "$(dirname "$0")" && pwd)/lib-ci-tool-versions.sh"

if ! scan=$(civ_scan "$ROOT"); then
    echo "::error::版の行を読めませんでした(根のフォルダ: ${ROOT})"
    exit 2
fi
if ! data=$(_civ_data "$ROOT"); then
    echo "::error::データのファイル ${DATA_REL} を読めませんでした"
    exit 2
fi
inv="$ROOT/$INV_REL"
if ! jq -e '.targets | type == "array"' "$inv" >/dev/null 2>&1; then
    echo "::error::棚卸しの対象の一覧 ${INV_REL} が無いか、JSON として読めません"
    exit 2
fi

# 当たった問題を1行に1つずつ「ファイル<TAB>行番号<TAB>探す文字1<TAB>探す文字2<TAB>理由」で出す。
# 行番号が - のときは、探す文字を2つとも含む最初の行を、あとでファイルから探す。
# shellcheck disable=SC2016 # jq の式の $ は jq の変数
problems=$(jq -r --arg scan "$scan" --slurpfile inv "$inv" \
    --arg data "$DATA_REL" --arg invf "$INV_REL" '
    def pair($f; $k): "{\"file\": \"\($f)\", \"key\": \"\($k)\"}";
    def same($a; $b): $a.file == $b.file and $a.key == $b.key;
    ($scan | split("\n") | map(select(length > 0) | split("\t")
        | {file: .[0], line: .[1], key: .[2], ver: .[3]})) as $rows
    | .tools as $tools
    | (.excluded // []) as $ex
    | [$tools | to_entries[] | .key as $t | (.value.ci // [])[] | {tool: $t, file, key}] as $ci
    | def keytool($k): [$tools | to_entries[] | select(any((.value.keys // [])[]; . == $k)) | .key] | first;
    (
        # 1. どの一覧にも無い組
        ($rows[] | . as $r
            | select(any($ci[]; same(.; $r)) | not)
            | select(any($ex[]; same(.; $r)) | not)
            | keytool($r.key) as $t
            | [$r.file, $r.line, "-", "-",
                if $t then
                    "\($tools[$t].name) の版 \($r.ver)(\($r.key))が、自動で上がる対象に入っていない場所にあります。\($data) の tools.\($t).ci に \(pair($r.file; $r.key)) を足してください"
                else
                    "道具の版 \($r.key) \($r.ver) が、\($data) の tools(自動で上がる対象)にも excluded(対象外の一覧)にもありません。どちらかに \(pair($r.file; $r.key)) を足してください。excluded に足すときは reason に自動で上げない理由を書いてください"
                end]),
        # 2. 4つの道具の名前を対象外にした組
        ($ex[] | . as $e | keytool($e.key) as $t | select($t)
            | [$data, "-", "\"\($e.file)\"", "\"\($e.key)\"",
                "excluded の組 \(pair($e.file; $e.key)) の名前は、\($tools[$t].name) の keys に入っています。\($tools[$t].name) の版は対象外にできません。tools.\($t).ci に移してください"]),
        # 3. 場所によって違う版
        ($tools | keys[] as $t
            | [$rows[] | . as $r | select(any($ci[]; .tool == $t and same(.; $r)))] as $own
            | ($own | map(.ver | ltrimstr("v")) | unique) as $vers
            | select(($vers | length) > 1)
            | ($vers | map(. as $v | "\(.)(\([$own[] | select((.ver | ltrimstr("v")) == $v) | "\(.file):\(.line)"] | join("、")))") | join(" / ")) as $where
            | $own[]
            | [.file, .line, "-", "-",
                "\($tools[$t].name) の CI の版が、場所によって違います。版ごとの場所: \($where)"]),
        # 4. 組が指す行が無い
        (($ci[], $ex[]) | . as $p | select(any($rows[]; same(.; $p)) | not)
            | [$data, "-", "\"\($p.file)\"", "\"\($p.key)\"",
                "組 \(pair($p.file; $p.key)) が指す版の行が \($p.file) にありません。組を消すか、ファイルと名前を直してください"]),
        # 5. 理由の無い対象外
        ($ex[] | select((.reason | type) != "string" or ((.reason | gsub("\\s"; "")) == ""))
            | [$data, "-", "\"\(.file)\"", "\"\(.key)\"",
                "excluded の組 \(pair(.file; .key)) に、自動で上げない理由の reason がありません"]),
        # 6. 棚卸しの対象
        ($tools | to_entries[] | .key as $t | .value as $v
            | ($v.inventory_name // $v.name) as $n
            | [$inv[0].targets[] | select(.name == $n)] as $tg
            | if ($tg | length) == 0 then
                [$data, "-", "\"inventory_name\"", "\"\($n)\"",
                    "\($invf) に、\($v.name) の棚卸しの対象 \($n) がありません。targets に足してください"]
              else
                ([$ci[] | select(.tool == $t) | .file] + [($v.dev.file // empty)] | unique) as $need
                | ([$tg[].declarations[]?.files[]?]) as $have
                | ($need - $have) as $miss
                | select(($miss | length) > 0)
                | [$invf, "-", "\"name\"", "\"\($n)\"",
                    "棚卸しの対象 \($n) の宣言のファイルに、\($miss | join("、")) がありません。declarations の files に足してください"]
              end)
    ) | @tsv
' "$data")
rc=$?
if [ "$rc" -ne 0 ]; then
    echo "::error::${DATA_REL} か ${INV_REL} の形が違うため、検査できませんでした"
    exit 2
fi

count=0
while IFS="$(printf '\t')" read -r file line a b why; do
    [ -n "$file" ] || continue
    if [ "$line" = "-" ]; then
        line=$(awk -v a="$a" -v b="$b" 'index($0, a) && index($0, b) { print NR; exit }' "$ROOT/$file" 2>/dev/null)
        [ -n "$line" ] || line=1
    fi
    echo "::error file=${file},line=${line}::${why//%/%25}"
    count=$((count + 1))
done <<<"$problems"

if [ "$count" -gt 0 ]; then
    echo "版の書き場所の検査: ${count} 件の問題があります。"
    exit 1
fi
echo "版の書き場所の検査: 問題はありません(版の行 $(printf '%s' "$scan" | grep -c .) 件)。"
exit 0
