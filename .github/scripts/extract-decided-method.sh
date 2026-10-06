#!/usr/bin/env bash
# =====================================================================
# 判定の基準の文書から「決めた方式」の節を抜き出す
# (codex-review の Prepare review context から実行)
#
# 判定の基準の文書(spec.md。Issue本文を書き出したもの)を読み、
# `## 決めた方式` の見出しの節の中身を標準出力に出す。節の中身は解釈しない。
#
# 抜き出しの規則:
#   - 各行の末尾の \r を取り除いてから判定する(出力にも \r を残さない)
#   - 節の始まり: `##` と1つ以上の空白と `決めた方式` で始まり、そのあとに空白だけが続く行。
#     見出しの行そのものは出さない
#   - 節の終わり: `#` か `##` と空白で始まる行(1段目か2段目の見出し)の手前。
#     `###` より深い見出しは中身に含める。次の見出しが無ければ文書の終わり
#   - コードブロック: 行頭が ``` か ~~~ の行で内と外を切り替える。コードブロックの中の行は
#     節の始まりにも終わりにもしない。節の中にあれば、そのまま中身に含める
#   - 節ごとに前後の空白だけの行を出さない。節が2つ以上あれば、中身のある節を文書の順に
#     空行1つで区切ってつなげて出す
#
# 終了コード:
#   0  = 抜き出しが終わった(節が無いときと中身が空白だけのときは何も出さない)
#   64 = 引数の数が1つでない
#   66 = 文書が無いか読めない
#   64 と 66 のときは、理由を [extract-decided-method] で始まる1行で標準エラーに出す。
#   読み込みの途中で awk が失敗したときも0以外で終わる。
#
# awk は POSIX の範囲の機能だけを使う(mawk・gawk・busybox awk のどれでも動かすため)。
#
# テスト: .github/scripts/tests/test-extract-decided-method.sh
# 使い方: extract-decided-method.sh <文書のパス>
# =====================================================================
set -euo pipefail

if [ "$#" -ne 1 ]; then
    echo "[extract-decided-method] 引数には文書のパスを1つだけ渡してください(渡された数: $#)" >&2
    exit 64
fi

DOC="$1"
if [ ! -f "$DOC" ] || [ ! -r "$DOC" ]; then
    echo "[extract-decided-method] 文書が無いか読めません: $DOC" >&2
    exit 66
fi

# 文書は標準入力から渡す(パスに = があると awk が変数の代入として読むため)。
# LC_ALL=C にして、awk の種類と環境のロケールに依らずバイト単位で比べる。
LC_ALL=C awk '
# 節の始まりの見出しかどうか
function is_decided_heading(line,    t) {
    if (line !~ /^##[ \t]+/) {
        return 0
    }
    t = line
    sub(/^##[ \t]+/, "", t)
    sub(/[ \t]+$/, "", t)
    return t == "決めた方式"
}

# 集めた節の中身を、前後の空白だけの行を除いて出す
function flush_section(    first, last, i) {
    first = 1
    last = n
    while (first <= last && buf[first] ~ /^[ \t]*$/) {
        first++
    }
    while (last >= first && buf[last] ~ /^[ \t]*$/) {
        last--
    }
    if (first <= last) {
        if (printed) {
            print ""
        }
        for (i = first; i <= last; i++) {
            print buf[i]
        }
        printed = 1
    }
    n = 0
}

BEGIN {
    in_section = 0
    in_fence = 0
    printed = 0
    n = 0
}

{
    sub(/\r$/, "")

    # コードブロックの外の行だけを、節の始まりと終わりとして扱う
    if (!in_fence) {
        if (is_decided_heading($0)) {
            if (in_section) {
                flush_section()
            }
            in_section = 1
            next
        }
        if (in_section && $0 ~ /^##?[ \t]/) {
            flush_section()
            in_section = 0
            next
        }
    }

    if ($0 ~ /^```/ || $0 ~ /^~~~/) {
        in_fence = !in_fence
    }

    if (in_section) {
        buf[++n] = $0
    }
}

END {
    if (in_section) {
        flush_section()
    }
}
' <"$DOC"
