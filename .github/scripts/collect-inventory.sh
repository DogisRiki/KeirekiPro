#!/usr/bin/env bash
# =====================================================================
# 棚卸し: 使っている版とサポート期限の表(audit-inventory CI から使う)
#
# 対象の一覧は .github/audit/inventory-targets.json に書く。対象ごとに、
# リポジトリのファイルに書かれた版(宣言)を読み、1対象1行の表にする。
# 値の良し悪しは判定しない。版の食い違いや期限切れにも記号を付けず、
# 事実の列として並べる(要件1-7)。
#
# 表の形(要件2-1):
#   | 対象 | 使っている版(書いてある場所) | 最新のリリース | 使っている系列のサポート期限 | 期限切れ | 最新の系列 |
#   「使っている版」の欄は、宣言から読んだ版を、最初に現れた順に <br> で並べる。
#   同じ版が複数の場所にあれば「版(最初の場所 ほかNか所)」とまとめる。
#   読めなかった場所は「読み取れず(ファイル)」と出す(要件2-6)。
#   設定ファイルの support が null の対象(サポート期限の公表が無い対象)は、
#   期限・期限切れ・最新の系列の3列を「公表なし」にする(要件1-5)。
#
# 表の行の材料(記録):
#   inv_read_target が宣言を読んで {name, used, support_published} を作る。
#   最新のリリース(latest)とサポート期限の3列(support)は、外部の取得元に
#   問い合わせる処理が作り、記録に足してから inv_table_row に渡す。
#     latest   文字列、または文字列の配列(<br> で並べる)
#     support  {deadline, eol, latest_cycle}。各値は文字列または文字列の配列。
#              support_published が false の対象では使わない
#   inv_table_row は値の中身を解釈しない。表に入れる前に `|` と改行(CR・LF)を
#   取り除くだけにする。表の崩れと、コメントへの任意の Markdown の差し込みを
#   防ぐため(外部の応答も、リポジトリのファイルから読んだ値も同じ扱い)。
#
# 宣言の正規表現(設定ファイルの pattern):
#   jq の正規表現(Oniguruma)で書き、名前付きグループ version を1つ持たせる。
#   ファイル全体に対して一致を全て取り、version の位置から行番号を数える。
#   jq の正規表現では `^` はテキストの先頭にしか一致しないため、行の先頭に
#   合わせるときは `(?m)^` と書く。複数行にまたがる正規表現も書ける
#   (例: tflint の AWS 用ルールセットは plugin "aws" のブロックの中の version)。
#   ファイルが無い・一致が0件・正規表現の誤り・version が空のときは、その場所を
#   読めなかった場所として残す。正規表現の書き誤りで止めず、表の欄で見せる。
#
# 系列(設定ファイルの support.cycle_pattern):
#   使っている版から、サポート期限を問い合わせる系列を取り出す正規表現。
#   名前付きグループ cycle を1つ持たせる(例: 21-jdk → 21、1.16.4 → 1.16)。
#
# 関数と戻り値(source して使う。シェルの設定と trap を変えない):
#   inv_validate_targets <targets.json>
#     設定ファイルの形を確かめる。0 = 正しい / 1 = 読めない・形が違う
#   inv_read_target <repo_root> <target_json>
#     対象の宣言を読み、記録 {name, used, support_published} を JSON で出す。
#     used は [{file, line, version}]。読めなかった場所は line と version が null
#     0 = 出した / 1 = 対象の JSON を扱えなかった
#   inv_cycle_of <cycle_pattern> <version>
#     系列を出す。0 = 出した / 1 = 取り出せない・正規表現の誤り
#   inv_table_header
#     表の見出しの2行を出す
#   inv_table_row <record_json>
#     記録から表の1行を出す。0 = 出した / 1 = latest が無い、公表がある対象で
#     support の3列がそろっていない、記録が JSON として読めない
#
# テスト: .github/scripts/tests/test-collect-inventory.sh
# =====================================================================

# 設定ファイルの形(design.md の inventory-targets.json の型)。
# jq の and は左が偽なら右を評価しないため、型を先に確かめてから中を見る。
_INV_JQ_VALIDATE='
def nonempty_str: type == "string" and length > 0;
(.targets | type == "array" and length > 0)
and all(.targets[];
    type == "object"
    and (.name | nonempty_str)
    and (.declarations | type == "array" and length > 0
        and all(.[];
            type == "object"
            and (.files | type == "array" and length > 0 and all(.[]; nonempty_str))
            and (.pattern | nonempty_str)))
    and (.latest | type == "object"
        and ((.type == "github-release" and (.repo | nonempty_str))
            or (.type == "pypi" and (.package | nonempty_str))
            or (.type == "dockerhub-tags" and (.repository | nonempty_str) and (.tag_pattern | nonempty_str))
            or (.type == "endoflife" and (.product | nonempty_str))))
    and has("support")
    and (.support == null
        or (.support | type == "object" and .type == "endoflife"
            and (.product | nonempty_str) and (.cycle_pattern | nonempty_str))))
'

# 1つのファイルから version を全て取り出す。行番号は version の開始位置より前の
# 改行の数 + 1(match の offset と文字列の切り出しは、どちらも文字単位)。
# $text $p $f は jq の変数(シェルでは展開しない)。
# shellcheck disable=SC2016
_INV_JQ_MATCH='
[ $text | match($p; "g") | .captures[]
  | select(.name == "version" and .string != null and .string != "")
  | {file: $f,
     line: (($text[0:.offset] | explode | map(select(. == 10)) | length) + 1),
     version: .string} ]
'

# 表の組み立て。$r(記録)と $e $i は jq の変数(シェルでは展開しない)。
# shellcheck disable=SC2016
_INV_JQ_ROW='
def inv_clean: tostring | gsub("[|\r\n]"; "");
def inv_cell: if type == "array" then map(inv_clean) | join("<br>") else inv_clean end;
def inv_used_lines:
    ( [ .[] | select(.version != null) ]
      | reduce .[] as $e ([];
            (map(.version) | index($e.version)) as $i
            | if $i == null then . + [{version: $e.version, places: [$e]}]
              else .[$i].places += [$e] end)
      | map("\(.version | inv_clean)(\(.places[0].file | inv_clean):\(.places[0].line)"
            + (if (.places | length) > 1 then " ほか\((.places | length) - 1)か所" else "" end)
            + ")") )
    + [ .[] | select(.version == null) | "読み取れず(\(.file | inv_clean))" ];
$r
| if .latest == null then error("記録に latest がありません") else . end
| if .support_published != false
     and ((.support | type) != "object"
          or .support.deadline == null or .support.eol == null or .support.latest_cycle == null)
  then error("記録に support の3列がそろっていません") else . end
| [ (.name | inv_clean),
    (.used | inv_used_lines | join("<br>")),
    (.latest | inv_cell) ]
  + (if .support_published == false then ["公表なし", "公表なし", "公表なし"]
     else [ (.support.deadline | inv_cell), (.support.eol | inv_cell), (.support.latest_cycle | inv_cell) ] end)
| "| " + join(" | ") + " |"
'

inv_validate_targets() {
    local file="${1:-}"
    if [ -z "$file" ] || [ ! -f "$file" ]; then
        echo "::error::設定ファイルがありません: ${file}" >&2
        return 1
    fi
    if ! jq -e "$_INV_JQ_VALIDATE" "$file" >/dev/null 2>&1; then
        echo "::error::設定ファイルの形が想定と違います: ${file}" >&2
        return 1
    fi
    return 0
}

inv_read_target() {
    local root="$1" target="$2" items item file pattern found used="[]"
    items=$(jq -c '.declarations[] | .pattern as $p | .files[] | {file: ., pattern: $p}' <<<"$target") || return 1
    while IFS= read -r item; do
        [ -n "$item" ] || continue
        file=$(jq -r '.file' <<<"$item") || return 1
        pattern=$(jq -r '.pattern' <<<"$item") || return 1
        found="[]"
        if [ -f "${root}/${file}" ]; then
            if ! found=$(jq -n -c --rawfile text "${root}/${file}" --arg p "$pattern" --arg f "$file" \
                "$_INV_JQ_MATCH" 2>/dev/null); then
                echo "::warning::宣言の正規表現を使えませんでした: ${file}" >&2
                found="[]"
            fi
        fi
        if [ "$found" = "[]" ]; then
            found=$(jq -n -c --arg f "$file" '[{file: $f, line: null, version: null}]') || return 1
        fi
        used=$(jq -c --argjson add "$found" '. + $add' <<<"$used") || return 1
    done <<<"$items"
    jq -n -c --argjson t "$target" --argjson used "$used" \
        '{name: $t.name, used: $used, support_published: ($t.support != null)}' || return 1
}

inv_cycle_of() {
    local cycle
    cycle=$(jq -n -r --arg p "$1" --arg v "$2" \
        '[$v | match($p) | .captures[] | select(.name == "cycle" and .string != null and .string != "") | .string] | first // empty' \
        2>/dev/null) || return 1
    [ -n "$cycle" ] || return 1
    printf '%s\n' "$cycle"
}

inv_table_header() {
    printf '%s\n' '| 対象 | 使っている版(書いてある場所) | 最新のリリース | 使っている系列のサポート期限 | 期限切れ | 最新の系列 |'
    printf '%s\n' '|---|---|---|---|---|---|'
}

inv_table_row() {
    jq -n -r --argjson r "$1" "$_INV_JQ_ROW" || return 1
}
