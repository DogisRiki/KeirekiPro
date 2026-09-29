#!/usr/bin/env bash
# =====================================================================
# 棚卸し: 使っている版とサポート期限の表(audit-inventory CI から使う)
#
# 対象の一覧は .github/audit/inventory-targets.json に書く。対象ごとに、
# リポジトリのファイルに書かれた版(宣言)を読み、1対象1行の表にする。
# 値の良し悪しは判定しない。版の食い違いや期限切れにも記号を付けず、
# 事実の列として並べる(要件1-7)。
#
# 使い方: collect-inventory.sh <targets.json のパス>
#   環境変数 GH_TOKEN GITHUB_REPOSITORY GITHUB_REPOSITORY_OWNER GITHUB_SERVER_URL
#   GITHUB_RUN_ID(必須)、ENDOFLIFE_BASE PYPI_BASE DOCKERHUB_BASE(任意。テスト用)
#   宣言のファイルは、このスクリプトの置き場所の2つ上(リポジトリのルート)から読む。
#   表を組み立て、棚卸しの台帳のIssue(タイトル「棚卸し台帳: 版とサポート期限」、
#   ラベル audit)にコメントする。台帳が無ければ作る。台帳の操作は
#   lib-ledger-issue.sh の関数だけで行う(書き込みは台帳の作成・コメント・
#   担当者の割り当てに限る。要件6-3)。
#
# 終了コード:
#   0 = 台帳にコメントを書けた(取得できなかった欄があっても 0。要件2-8)
#   2 = 書けなかった(引数・環境変数の不足、設定ファイルの形の違反、表を
#       組み立てられない、台帳のIssueを探せない・作れない・コメントできない。要件2-7)
#   1 は使わない(値の良し悪しを判定しないため。要件1-7)
#
# コメントの形:
#   1行目は1行の説明にする。lib-ledger-issue.sh の ledger_comment は本文の
#   1行目の頭に「@<所有者> 」を付けるため、1行目が表の見出しだと列の数が
#   合わず、表として表示されない。
#     <1行の説明>
#     (空行)
#     <表>
#     (空行)
#     取得できなかった欄の理由:(あれば)
#     - ...
#     (空行)
#     振り返りのIssue: ...
#     (空行)
#     実行の記録: <実行へのリンク>
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
#   問い合わせる inv_collect_external が作り、記録に足してから inv_table_row に渡す。
#     latest    文字列、または文字列の配列(<br> で並べる)
#     support   {deadline, eol, latest_cycle}。各値は文字列または文字列の配列。
#               support_published が false の対象では使わない
#     failures  取得できなかった欄の理由(文字列の配列)。表の下に並べる
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
# 外部の取得元(設定ファイルの latest.type と support.type):
#   github-release  gh api repos/{repo}/releases/latest の tag_name
#   pypi            GET {PYPI_BASE}/{package}/json の info.version
#   dockerhub-tags  GET {DOCKERHUB_BASE}/namespaces/{ns}/repositories/{repo}/tags
#                   ?page_size=100&ordering=last_updated の results[].name のうち、
#                   tag_pattern に一致するものの版として最大のもの(sort -V)
#   endoflife       GET {ENDOFLIFE_BASE}/products/{product}/releases/{系列}(使っている
#                   系列ごと)と /releases/latest(最新の系列。latest.type が endoflife
#                   なら、その latest.name を最新のリリースにもする)
#   既定の接続先: ENDOFLIFE_BASE=https://endoflife.date/api/v1、
#   PYPI_BASE=https://pypi.org/pypi、DOCKERHUB_BASE=https://hub.docker.com/v2
#   (テストで差し替える)。GitHub 以外は curl -sS --max-time 20 の GET だけで、
#   認証ヘッダを付けない。送るのは URL の中の製品名・パッケージ名だけ(要件6-1)。
#   eolFrom が null は「未定」、isEol は「はい」「いいえ」と書き、isLts が false の
#   最新の系列には「(LTS ではない)」を添える。値は公表されているまま出す。
#   200 以外・タイムアウト・JSON として読めない・期待のキーが無いときは、その欄を
#   「取得できず」にし、理由を表の下に書いて、他の欄と対象の取得を続ける(要件2-5)。
#
# 関数と戻り値(source して使う。シェルの設定と trap を変えない。
# 直接実行したときだけ inv_main を動かす):
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
#   inv_collect_external <record_json> <target_json>
#     外部の取得元に問い合わせ、記録に latest・support・failures を足して出す。
#     取得の失敗では失敗にしない。0 = 出した / 1 = 記録か対象の JSON を扱えなかった
#   inv_build_table <repo_root> <targets.json>
#     全ての対象の表を出し、取得できなかった欄があれば、空行に続けて
#     「取得できなかった欄の理由:」と1件1行の箇条書きを出す。
#     0 = 出した / 1 = 設定ファイルや記録を扱えなかった
#   inv_retrospective_line
#     振り返りのIssueの件数を1行で出す。取得の失敗も1行に書く。常に 0
#   inv_main <targets.json>
#     表を台帳のIssueにコメントする。戻り値は上の終了コードと同じ(0 / 2)
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

# ---------------------------------------------------------------------
# 外部の取得元への問い合わせ
# ---------------------------------------------------------------------

# 既定の接続先(環境変数 ENDOFLIFE_BASE / PYPI_BASE / DOCKERHUB_BASE で差し替える)
_INV_ENDOFLIFE_DEFAULT='https://endoflife.date/api/v1'
_INV_PYPI_DEFAULT='https://pypi.org/pypi'
_INV_DOCKERHUB_DEFAULT='https://hub.docker.com/v2'

# _inv_json_array <文字列...>  文字列を JSON の配列にする(0個なら [])
_inv_json_array() {
    jq -n -c '$ARGS.positional' --args "$@"
}

# _inv_is_json <文字列>  JSON として読めて、値が1つ以上あれば 0
_inv_is_json() {
    jq -n -e '[inputs] | length > 0' >/dev/null 2>&1 <<<"$1"
}

# _inv_fetch <url>
# GET して、状態コード 200 で JSON として読める本文を出す。認証ヘッダは付けない
# (要件6-1)。0 = 本文を出した / 1 = 失敗(標準出力に理由を出す)
_inv_fetch() {
    local url="$1" out rc=0 code
    out=$(curl -sS --max-time 20 -w '\nHTTP_CODE:%{http_code}' "$url" 2>/dev/null) || rc=$?
    if [ "$rc" -ne 0 ]; then
        printf '接続できない、またはタイムアウト(curl の終了コード %s)' "$rc"
        return 1
    fi
    code="${out##*HTTP_CODE:}"
    case "$code" in
    200) ;;
    '' | *[!0-9]*)
        printf '応答の状態コードを読めない'
        return 1
        ;;
    *)
        printf 'HTTP %s' "$code"
        return 1
        ;;
    esac
    out="${out%$'\n'HTTP_CODE:*}"
    if ! _inv_is_json "$out"; then
        printf '形式が想定と違う(JSON として読めない)'
        return 1
    fi
    printf '%s' "$out"
}

# _inv_pick <json> <jq のパス>
# パスの値が空でない文字列なら出す。0 = 出した / 1 = 無い(標準出力に理由を出す)
_inv_pick() {
    local v
    if v=$(jq -r -e "[$2 | select(type == \"string\" and length > 0)] | first // empty" <<<"$1" 2>/dev/null) \
        && [ -n "$v" ]; then
        printf '%s' "$v"
        return 0
    fi
    printf '形式が想定と違う(%s が無い)' "$2"
    return 1
}

# _inv_github_release <owner/repo>  最新のリリースの tag_name を出す
# GitHub だけは gh api を使う(認証は gh が GH_TOKEN で行う。curl には渡さない)
_inv_github_release() {
    local repo="$1" out rc=0 err errfile
    errfile=$(mktemp) || {
        printf '一時ファイルを作れない'
        return 1
    }
    out=$(gh api "repos/${repo}/releases/latest" 2>"$errfile") || rc=$?
    err=$(grep -oE 'HTTP [0-9]+' "$errfile" | tail -n 1 || true)
    rm -f "$errfile"
    if [ "$rc" -ne 0 ]; then
        printf '%s' "${err:-gh api の失敗(終了コード ${rc})}"
        return 1
    fi
    if ! _inv_is_json "$out"; then
        printf '形式が想定と違う(JSON として読めない)'
        return 1
    fi
    _inv_pick "$out" '.tag_name'
}

# _inv_pypi_latest <パッケージ>  PyPI の info.version を出す
_inv_pypi_latest() {
    local body
    body=$(_inv_fetch "${PYPI_BASE:-$_INV_PYPI_DEFAULT}/$1/json") || {
        printf '%s' "$body"
        return 1
    }
    _inv_pick "$body" '.info.version'
}

# _inv_dockerhub_latest <namespace/repository> <tag_pattern>
# 最終更新の新しい順の100件のタグから、tag_pattern に一致するものを版として比べ、
# 最大のものを出す(sort -V)。別名(2026.08.4)や -arm64 付きは tag_pattern で除く
_inv_dockerhub_latest() {
    local repository="$1" pattern="$2" base body tags top
    base="${DOCKERHUB_BASE:-$_INV_DOCKERHUB_DEFAULT}"
    if ! jq -n --arg p "$pattern" '"" | test($p)' >/dev/null 2>&1; then
        printf 'tag_pattern の正規表現を使えない'
        return 1
    fi
    body=$(_inv_fetch "${base}/namespaces/${repository%%/*}/repositories/${repository#*/}/tags?page_size=100&ordering=last_updated") || {
        printf '%s' "$body"
        return 1
    }
    if ! tags=$(jq -r --arg p "$pattern" \
        '.results | if type == "array" then .[] | .name? | strings | select(test($p)) else error("results") end' \
        <<<"$body" 2>/dev/null); then
        printf '形式が想定と違う(.results[].name が無い)'
        return 1
    fi
    top=$(printf '%s\n' "$tags" | sed '/^$/d' | sort -V | tail -n 1)
    if [ -z "$top" ]; then
        printf 'tag_pattern に一致するタグが無い'
        return 1
    fi
    printf '%s' "$top"
}

# _inv_eol_url <product> <系列 または latest>
_inv_eol_url() {
    printf '%s/products/%s/releases/%s' "${ENDOFLIFE_BASE:-$_INV_ENDOFLIFE_DEFAULT}" "$1" "$2"
}

# _inv_eol_cycle_values <本文>
# 系列の応答から、期限(eolFrom。null は「未定」)と期限切れ(isEol を「はい」
# 「いいえ」)を1行ずつ出す。0 = 出した / 1 = キーが無い(理由を出す)
_inv_eol_cycle_values() {
    local v
    if v=$(jq -r -e '.result | select(type == "object")
            | select((.isEol | type) == "boolean"
                and has("eolFrom") and (.eolFrom == null or (.eolFrom | type) == "string"))
            | ((.eolFrom // "未定") | gsub("[\r\n]"; "")), (if .isEol then "はい" else "いいえ" end)' \
        <<<"$1" 2>/dev/null); then
        printf '%s' "$v"
        return 0
    fi
    printf '形式が想定と違う(.result.isEol または .result.eolFrom が無い)'
    return 1
}

# _inv_eol_latest_cycle <本文>
# 最新の系列の名前を出す。isLts が false なら「(LTS ではない)」を添える
_inv_eol_latest_cycle() {
    local v
    if v=$(jq -r -e '.result | select(type == "object")
            | select((.name | type) == "string" and (.name | length) > 0 and (.isLts | type) == "boolean")
            | (.name | gsub("[\r\n]"; "")) + (if .isLts then "" else "(LTS ではない)" end)' \
        <<<"$1" 2>/dev/null); then
        printf '%s' "$v"
        return 0
    fi
    printf '形式が想定と違う(.result.name または .result.isLts が無い)'
    return 1
}

# inv_collect_external <record_json> <target_json>
# 記録に、最新のリリース(latest)、サポート期限の3列(support)、取得できなかった
# 欄の理由(failures)を足して出す。取得の失敗は、その欄を「取得できず」にして
# 理由を failures に足し、他の欄の取得を続ける(要件2-5・5-3)。
#   support の deadline と eol は「系列: 値」の配列で、使っている版から作った
#   系列ごとに1つ(系列を取り出せない版は「版: 取得できず」)。latest_cycle は文字列。
#   support が null の対象は support を null にし、endoflife.date に問い合わせない。
# 0 = 出した / 1 = 記録または対象の JSON を扱えなかった
inv_collect_external() {
    local record="$1" target="$2" name ltype latest lrc=0 v c body reason vals
    local sproduct cpattern lcycle="" support="null" versions
    local lp_product="" lp_body="" lp_rc=0
    local -a failures=() deadlines=() eols=()
    local -A seen=()
    name=$(jq -r '.name' <<<"$record") || return 1
    ltype=$(jq -r '.latest.type' <<<"$target") || return 1

    # 最新のリリース(要件1-3)
    case "$ltype" in
    github-release)
        latest=$(_inv_github_release "$(jq -r '.latest.repo' <<<"$target")") || lrc=1
        ;;
    pypi)
        latest=$(_inv_pypi_latest "$(jq -r '.latest.package' <<<"$target")") || lrc=1
        ;;
    dockerhub-tags)
        latest=$(_inv_dockerhub_latest "$(jq -r '.latest.repository' <<<"$target")" \
            "$(jq -r '.latest.tag_pattern' <<<"$target")") || lrc=1
        ;;
    endoflife)
        # 最新の系列の latest.name。応答はサポート期限の最新の系列でも使う
        lp_product=$(jq -r '.latest.product' <<<"$target")
        lp_body=$(_inv_fetch "$(_inv_eol_url "$lp_product" latest)") || lp_rc=1
        if [ "$lp_rc" -eq 0 ]; then
            latest=$(_inv_pick "$lp_body" '.result.latest.name') || lrc=1
        else
            latest="$lp_body"
            lrc=1
        fi
        ;;
    *)
        latest="取得元の種類が不明(${ltype})"
        lrc=1
        ;;
    esac
    if [ "$lrc" -ne 0 ]; then
        failures+=("${name} の最新のリリース: ${latest}")
        latest="取得できず"
    fi

    # 使っている系列のサポート期限と期限切れ、最新の系列(要件1-4)
    if [ "$(jq -r '.support != null' <<<"$target")" = "true" ]; then
        sproduct=$(jq -r '.support.product' <<<"$target")
        cpattern=$(jq -r '.support.cycle_pattern' <<<"$target")
        versions=$(jq -r '[.used[] | select(.version != null) | .version | gsub("[\r\n]"; "")]
            | reduce .[] as $v ([]; if any(.[]; . == $v) then . else . + [$v] end) | .[]' <<<"$record") || return 1
        while IFS= read -r v; do
            [ -n "$v" ] || continue
            if ! c=$(inv_cycle_of "$cpattern" "$v"); then
                deadlines+=("${v}: 取得できず")
                eols+=("${v}: 取得できず")
                failures+=("${name} のサポート期限と期限切れ: 版 ${v} から系列を取り出せない")
                continue
            fi
            [ -z "${seen[$c]:-}" ] || continue
            seen[$c]=1
            if ! body=$(_inv_fetch "$(_inv_eol_url "$sproduct" "$c")"); then
                reason="$body"
            elif ! vals=$(_inv_eol_cycle_values "$body"); then
                reason="$vals"
            else
                deadlines+=("${c}: $(sed -n 1p <<<"$vals")")
                eols+=("${c}: $(sed -n 2p <<<"$vals")")
                continue
            fi
            deadlines+=("${c}: 取得できず")
            eols+=("${c}: 取得できず")
            failures+=("${name} の ${c} 系列のサポート期限と期限切れ: ${reason}")
        done <<<"$versions"
        if [ "${#deadlines[@]}" -eq 0 ]; then
            deadlines=("取得できず")
            eols=("取得できず")
            failures+=("${name} のサポート期限と期限切れ: 使っている版を読み取れないため、系列を決められない")
        fi

        if [ "$sproduct" != "$lp_product" ]; then
            lp_product="$sproduct"
            lp_rc=0
            lp_body=$(_inv_fetch "$(_inv_eol_url "$sproduct" latest)") || lp_rc=1
        fi
        if [ "$lp_rc" -ne 0 ]; then
            failures+=("${name} の最新の系列: ${lp_body}")
            lcycle="取得できず"
        elif ! lcycle=$(_inv_eol_latest_cycle "$lp_body"); then
            failures+=("${name} の最新の系列: ${lcycle}")
            lcycle="取得できず"
        fi
        support=$(jq -n -c --argjson d "$(_inv_json_array "${deadlines[@]}")" \
            --argjson e "$(_inv_json_array "${eols[@]}")" --arg l "$lcycle" \
            '{deadline: $d, eol: $e, latest_cycle: $l}') || return 1
    fi

    jq -c --arg latest "$latest" --argjson support "$support" \
        --argjson failures "$(_inv_json_array "${failures[@]}")" \
        '. + {latest: $latest, support: $support, failures: $failures}' <<<"$record" || return 1
}

# inv_build_table <repo_root> <targets.json>
# 全ての対象の表と、表の下の「取得できなかった欄の理由」を出す。理由が無ければ
# 表だけを出す。取得の失敗では止めない。
# 0 = 出した / 1 = 設定ファイルや記録を扱えなかった
inv_build_table() {
    local root="$1" file="$2" targets target record reasons="[]"
    targets=$(jq -c '.targets[]' "$file") || return 1
    inv_table_header
    while IFS= read -r target; do
        [ -n "$target" ] || continue
        record=$(inv_read_target "$root" "$target") || return 1
        record=$(inv_collect_external "$record" "$target") || return 1
        inv_table_row "$record" || return 1
        reasons=$(jq -c --argjson r "$record" '. + $r.failures' <<<"$reasons") || return 1
    done <<<"$targets"
    jq -r 'if length > 0 then "", "取得できなかった欄の理由:", (.[] | "- " + gsub("[|\r\n]"; "")) else empty end' \
        <<<"$reasons" || return 1
}

# ---------------------------------------------------------------------
# 振り返りのIssueの件数と、台帳へのコメント
# ---------------------------------------------------------------------

_INV_LEDGER_TITLE='棚卸し台帳: 版とサポート期限'
_INV_LEDGER_LABEL='audit'
_INV_LEDGER_INITIAL_BODY='月1回、audit-inventory.yaml がコメントで表を届ける。人が編集しない。'
_INV_COMMENT_LEAD='棚卸しの結果です。値の良し悪しは判定していません。'
_INV_WORK=""

# inv_retrospective_line
# 振り返り(retrospective ラベル)のIssueの件数を1行で出す(要件1-6)。
#   ラベルがある  振り返りのIssue: 全N件(未完了M件)  PR は数えない
#   ラベルが無い  振り返りのIssue: 0件(retrospective ラベルが存在しない)
#   取得の失敗    振り返りのIssue: 取得できず(理由)
# ラベルの有無は labels/retrospective の応答が 404 かで見分ける。Issue の一覧は
# ラベルが無くても空で返るため、一覧だけでは「ラベルが無い」と「0件」を区別できない。
# gh api は 400 以上の応答で、標準エラーに「gh: <メッセージ> (HTTP <状態コード>)」を出す
#   https://github.com/cli/cli/blob/trunk/pkg/cmd/api/api.go
# 取得の失敗は表の欄と同じく事実として書き、実行を失敗にしない。常に 0
inv_retrospective_line() {
    local repo="${GITHUB_REPOSITORY:-}" prefix='振り返りのIssue: ' out rc=0 err errfile counts
    errfile=$(mktemp) || {
        printf '%s取得できず(一時ファイルを作れない)\n' "$prefix"
        return 0
    }
    gh api "repos/${repo}/labels/retrospective" >/dev/null 2>"$errfile" || rc=$?
    err=$(grep -oE 'HTTP [0-9]+' "$errfile" | tail -n 1 || true)
    if [ "$rc" -ne 0 ]; then
        rm -f "$errfile"
        if [ "$err" = "HTTP 404" ]; then
            printf '%s0件(retrospective ラベルが存在しない)\n' "$prefix"
        else
            printf '%s取得できず(%s)\n' "$prefix" "${err:-gh api の失敗(終了コード ${rc})}"
        fi
        return 0
    fi
    # Issues API は PR も返すため pull_request を持つ要素を除く。--paginate(--slurp なし)は
    # ページごとの配列を続けて出すので、jq -s で束ねる
    out=$(gh api --paginate "repos/${repo}/issues?labels=retrospective&state=all&per_page=100" 2>"$errfile") || rc=$?
    err=$(grep -oE 'HTTP [0-9]+' "$errfile" | tail -n 1 || true)
    rm -f "$errfile"
    if [ "$rc" -ne 0 ]; then
        printf '%s取得できず(%s)\n' "$prefix" "${err:-gh api の失敗(終了コード ${rc})}"
        return 0
    fi
    if ! counts=$(jq -s -r -e '
        if length > 0 and all(.[]; type == "array") then
            [.[][] | select(type == "object" and .pull_request == null)]
            | "全\(length)件(未完了\(map(select(.state == "open")) | length)件)"
        else error("配列でない") end' <<<"$out" 2>/dev/null); then
        printf '%s取得できず(形式が想定と違う(Issue の一覧が配列でない))\n' "$prefix"
        return 0
    fi
    printf '%s%s\n' "$prefix" "$counts"
}

# inv_main <targets.json>
# 表を組み立て、棚卸しの台帳のIssueにコメントする。戻り値は 0 / 2(ファイルの頭の
# 終了コードを参照)。台帳に触る前に、引数・環境変数・設定ファイル・表を確かめる
# (足りないまま gh を呼ばない)。
inv_main() {
    local targets self_dir root v table retro number
    if [ "$#" -ne 1 ]; then
        echo "::error::引数は1個必要です: <targets.json のパス>" >&2
        return 2
    fi
    targets="$1"
    for v in GH_TOKEN GITHUB_REPOSITORY GITHUB_REPOSITORY_OWNER GITHUB_SERVER_URL GITHUB_RUN_ID; do
        if [ -z "${!v:-}" ]; then
            echo "::error::環境変数 ${v} が必要です" >&2
            return 2
        fi
    done
    if ! self_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd) \
        || ! root=$(cd "${self_dir}/../.." && pwd); then
        echo "::error::スクリプトの置き場所からリポジトリのルートを決められません" >&2
        return 2
    fi
    # shellcheck source=.github/scripts/lib-ledger-issue.sh
    if ! source "${self_dir}/lib-ledger-issue.sh"; then
        echo "::error::lib-ledger-issue.sh を読み込めません" >&2
        return 2
    fi
    inv_validate_targets "$targets" || return 2

    if ! table=$(inv_build_table "$root" "$targets"); then
        echo "::error::表を組み立てられませんでした(設定ファイルか記録を扱えない)" >&2
        return 2
    fi
    retro=$(inv_retrospective_line)

    if ! _INV_WORK=$(mktemp -d) || [ -z "$_INV_WORK" ]; then
        echo "::error::一時ディレクトリを作れませんでした" >&2
        return 2
    fi
    # 1行目は説明にする(ledger_comment が1行目の頭にメンションを付けるため)。
    # 箇条書きの直後に続けて書くと箇条書きの一部になるため、段ごとに空行を挟む
    if ! {
        printf '%s\n\n' "$_INV_COMMENT_LEAD"
        printf '%s\n\n' "$table"
        printf '%s\n\n' "$retro"
        printf '実行の記録: %s/%s/actions/runs/%s\n' "$GITHUB_SERVER_URL" "$GITHUB_REPOSITORY" "$GITHUB_RUN_ID"
    } >"${_INV_WORK}/comment.md" \
        || ! printf '%s\n' "$_INV_LEDGER_INITIAL_BODY" >"${_INV_WORK}/initial.md"; then
        echo "::error::コメントの本文を組み立てられませんでした" >&2
        return 2
    fi
    echo "--- コメントの本文 ---"
    cat "${_INV_WORK}/comment.md"
    echo "---"

    if ! number=$(ledger_find_or_create "$_INV_LEDGER_TITLE" "${_INV_WORK}/initial.md" "$_INV_LEDGER_LABEL"); then
        echo "::error::棚卸しの台帳のIssueを探せない、または作れませんでした" >&2
        return 2
    fi
    if ! ledger_comment "$number" "${_INV_WORK}/comment.md"; then
        echo "::error::棚卸しの台帳のIssue #${number} に表を書けませんでした" >&2
        return 2
    fi
    return 0
}

# 終了時の後始末。一時ディレクトリを消し、0 以外の終わり方を 2 にそろえる
# (set -u の未定義の変数など、想定外の終わり方でも 1 を使わないため)
_inv_on_exit() {
    local rc=$?
    rm -rf "${_INV_WORK:-}"
    if [ "$rc" -ne 0 ]; then
        exit 2
    fi
}

# 直接実行したときだけ動かす(テストは source して関数だけを使う)。
# set -e は使わない。取得の失敗は欄に閉じ込め、台帳に書けない失敗だけを
# inv_main が 2 で返すため。
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    set -uo pipefail
    trap _inv_on_exit EXIT
    inv_main "$@"
    exit $?
fi
