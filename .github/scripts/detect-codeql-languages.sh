#!/usr/bin/env bash
# =====================================================================
# CodeQL で診断する言語を見つける(codeql.yaml の detect-codeql-languages から実行)
#
# 判定: git が追跡しているファイルを全部読み、言語の対応表の「拡張子か置き場所」と
#       照らして、CodeQL の言語を見つける。テストのコードも外さない。
#       見つけた言語ごとに、言語とビルドのしかたとビルドの命令の組を、
#       言語の名前の順に JSON の配列で1行に出す。例:
#         [{"language":"java-kotlin","build-mode":"manual","build-command":"…"}, …]
#       環境変数 GITHUB_OUTPUT があれば、同じ JSON を `matrix=<JSON>` の形で書き足す。
#
# 終了コード:
#   0 = 成功
#   1 = 対応表でビルドのしかたが空の言語のファイルを見つけた
#       (言語とファイルの例を1つずつ標準エラーに出す。matrix は書かない)
#   2 = それ以外の失敗(引数の欠落、対応表が読めないか形が正しくない、
#       git のリポジトリの中でない、診断する言語が1つも無い)
#   1 は言語を報告したうえでの明示的な exit 1 だけが返す。ガードしていない
#   コマンドの想定外の失敗も 2 に倒す。1 に混ぜると、判定が終わっていないのに
#   「ビルドのしかたを決めていない言語がある」と読まれる。
#
# なぜ必要か:
#   診断の言語を codeql.yaml に固定の一覧で書くと、言語を足した PR で一覧を
#   直し忘れたときに、その言語が診断されないまま main に入る。PR のファイルから
#   毎回見つければ、一覧を直す作業そのものが無くなる。対応表でビルドのしかたを
#   決めていない言語のファイルがあれば、このスクリプトが赤になり、
#   codeql-complete も赤になるので、PR はマージされない。
#
# なぜ「後ろの空の欄」を省いてよいのか:
#   ビルドの命令は manual の行にしか書かない。編集のときに行末のタブが消えても
#   読み違えないよう、欄が4つより少ない行は、足りない欄を空として読む。
#   欄が4つより多い行は、読み違えるおそれがあるので形の誤り(2)にする。
#
# テスト: .github/scripts/tests/test-detect-codeql-languages.sh
# 使い方: detect-codeql-languages.sh <対応表のパス>
# =====================================================================
set -Eeuo pipefail
trap 'exit 2' ERR

TABLE="${1:-}"
if [ -z "$TABLE" ]; then
    echo "使い方: detect-codeql-languages.sh <対応表のパス>" >&2
    exit 2
fi
if [ ! -f "$TABLE" ] || [ ! -r "$TABLE" ]; then
    echo "言語の対応表を読めません: ${TABLE}" >&2
    exit 2
fi
if ! TOP=$(git rev-parse --show-toplevel 2>/dev/null) || [ -z "$TOP" ]; then
    echo "git のリポジトリの中で動かしてください" >&2
    exit 2
fi

table_error() {
    echo "言語の対応表の ${LINE_NO} 行目の形が正しくありません: $1" >&2
    exit 2
}

declare -A MODE=()
declare -A COMMAND=()
declare -A EXAMPLE=()
LINE_NO=0

while IFS= read -r line || [ -n "$line" ]; do
    LINE_NO=$((LINE_NO + 1))
    line="${line%$'\r'}"
    case "$line" in
    '' | '#'*) continue ;;
    esac

    fields=()
    rest="$line"
    while [[ "$rest" == *$'\t'* ]]; do
        fields+=("${rest%%$'\t'*}")
        rest="${rest#*$'\t'}"
    done
    fields+=("$rest")
    if [ "${#fields[@]}" -gt 4 ]; then
        table_error "欄が4つより多い"
    fi
    while [ "${#fields[@]}" -lt 4 ]; do
        fields+=("")
    done
    pattern="${fields[0]}"
    language="${fields[1]}"
    mode="${fields[2]}"
    command="${fields[3]}"

    if [ -z "$pattern" ]; then
        table_error "拡張子か置き場所が空"
    fi
    if ! [[ "$language" =~ ^[a-z][a-z+-]*$ ]]; then
        table_error "CodeQL の言語の名前が空か、使えない文字を含む"
    fi
    case "$mode" in
    '' | none | autobuild) [ -z "$command" ] || table_error "ビルドの命令は manual の行にしか書けない" ;;
    manual) [ -n "$command" ] || table_error "manual の行にビルドの命令が無い" ;;
    *) table_error "ビルドのしかたが none / autobuild / manual / 空のどれでもない" ;;
    esac
    if [[ "$command" == *[[:cntrl:]]* ]]; then
        table_error "ビルドの命令に制御文字がある"
    fi

    if [ -n "${MODE[$language]+set}" ]; then
        if [ "${MODE[$language]}" != "$mode" ] || [ "${COMMAND[$language]}" != "$command" ]; then
            table_error "言語 ${language} のビルドのしかたかビルドの命令が、前の行と違う"
        fi
    else
        MODE[$language]="$mode"
        COMMAND[$language]="$command"
    fi

    if [ -n "${EXAMPLE[$language]+set}" ]; then
        continue
    fi
    files=$(git -C "$TOP" -c core.quotePath=false ls-files -- ":(glob)${pattern}")
    if [ -n "$files" ]; then
        EXAMPLE[$language]="${files%%$'\n'*}"
    fi
done <"$TABLE"

if [ "${#EXAMPLE[@]}" -eq 0 ]; then
    echo "診断する言語のファイルが1つも見つかりません" >&2
    exit 2
fi

languages=$(printf '%s\n' "${!EXAMPLE[@]}" | LC_ALL=C sort)

undecided=0
while IFS= read -r language; do
    if [ -z "${MODE[$language]}" ]; then
        echo "CodeQL の言語 ${language} のファイルがありますが、言語の対応表にビルドのしかたがありません(ファイルの例: ${EXAMPLE[$language]})。.github/codeql/languages.tsv の ${language} の行に、ビルドのしかたを書き足してください。" >&2
        undecided=1
    fi
done <<<"$languages"
if [ "$undecided" -ne 0 ]; then
    exit 1
fi

json_string() {
    local s="$1"
    s="${s//\\/\\\\}"
    s="${s//\"/\\\"}"
    printf '"%s"' "$s"
}

json="["
separator=""
while IFS= read -r language; do
    json+="${separator}{\"language\":$(json_string "$language"),\"build-mode\":$(json_string "${MODE[$language]}"),\"build-command\":$(json_string "${COMMAND[$language]}")}"
    separator=","
done <<<"$languages"
json+="]"

printf '%s\n' "$json"
if [ -n "${GITHUB_OUTPUT:-}" ]; then
    printf 'matrix=%s\n' "$json" >>"$GITHUB_OUTPUT"
fi
exit 0
