#!/usr/bin/env bash
# =====================================================================
# ラベルの一覧のファイル(.github/labels.json)を検証し、GitHub のラベルをファイルのとおりにする
# (--check は guardrails から、--check 無しは sync-labels.yaml から実行)
#
# 何をするか:
#   ラベルの一覧のファイルが、決まった形で書かれているかを確かめる。
#   誤りがあれば、どこが誤りかを標準エラーに1行ずつ出して、終了コード 2 で終わる。
#   検証では GitHub の API を呼ばない。
#   --check を付けないときは、検証に通ったあと、GitHub のラベルを作り、直し、名前を変え、消す。
#
# なぜ必要か:
#   このファイルは、GitHub のラベルの合わせ込みと、ラベルが足りない起票を止めるフックの
#   よりどころになる。誤ったファイルが main に入ると、ラベルを誤って消したり、
#   フックが起票を止め続けたりするため、PR の時点で止める。
#
# 検証の決まり(どれかに当たれば誤り):
#   ファイルが無い、読めない、JSON として読めない(JSON の値がちょうど1つでないときも含む)
#   最上位に配列 labels が無い、または labels が空
#   ラベルがオブジェクトでない。ラベルに name・group・description・color のどれかが無い、または文字列でない
#   group が kind・area・other のどれでもない
#   color が6桁の16進数でない(先頭の # は誤りとする。大文字と小文字はどちらでもよい)
#   description が100文字を超える(GitHub の上限。バイトではなく文字で数える)
#   previous_names があって、文字列の配列でない
#   selection_rule があって、空でない文字列でない(空白だけの文字列も空とする)
#   group が kind のラベルに area_required が無いか、真偽値でない。
#   group が kind でないラベルに area_required がある
#   名前が重なる(名前と前の名前のすべてを、大文字と小文字を区別せずに比べる)
#   group が kind のラベルが1つも無い。または、area_required が true の種類のラベルがあるのに、
#   group が area のラベルが1つも無い(どちらもフックが起票を止め続けてしまうため)
#
# GitHub のラベルの合わせ込み(--check 無し):
#   GitHub のラベルを gh api --paginate で全部読んでから、名前を大文字と小文字を区別せずに比べて、
#   次の順に書き込む。読めなければ、書き込みを1回も呼ばずに終了コード 1 で終わる。
#   どれを書き込むかは、最初に読んだ GitHub のラベルだけで決める。
#   1. 名前の変更: ファイルの名前のラベルが GitHub に無く、previous_names の名前のラベルがあれば、
#      その名前を変える(PATCH に new_name・description・color)。前の名前のラベルが2つ以上あれば、
#      previous_names の並びで先のものの名前を変え、残りは 2 の食い違いとして扱う
#   2. 前の名前と新しい名前の食い違い: 両方のラベルが GitHub にあれば、前の名前のラベルを変えず、
#      消さず、そのことを標準エラーと実行の要約に出して、最後に終了コード 1 で終わる
#   3. 作成と直し: GitHub に無いラベルを作る(POST)。ただし、1 で名前を変える対象にしたラベルは、
#      名前の変更に失敗しても作らない。GitHub にあって、説明か色が違うか、名前の大文字と小文字だけが
#      違うラベルを直す(PATCH)。色は大文字と小文字を区別せずに比べる
#   4. 削除: GitHub のラベルのうち、ファイルのどの名前とも、どの previous_names とも一致しないものを
#      消す(DELETE)。消したラベルは、GitHub が Issue と PR から外す
#   名前を経路に入れるときは jq の @uri で符号化する(kind/bug は kind%2Fbug)。
#   GitHub に送る欄は name(名前の変更と直しでは new_name)・description・color だけで、
#   area_required と selection_rule は送らない。
#   作った・直した・名前を変えた・消したラベルを、1件ずつ標準出力と実行の要約($GITHUB_STEP_SUMMARY)に書く。
#   書き込みが失敗したら、失敗したラベルと gh の文を標準エラーと実行の要約に出し、残りの書き込みを
#   続け、最後に終了コード 1 で終わる。gh の1回の呼び出しは60秒で打ち切る。
#
# テスト: .github/scripts/tests/test-sync-labels.sh
# 使い方: sync-labels.sh --check [--file <パス>]
#         sync-labels.sh [--file <パス>]
#   --file を付けないときは、作業フォルダの .github/labels.json を読む。
#   jq が要る。--check 無しでは、gh と timeout と、次の環境変数が要る。
#     GITHUB_REPOSITORY(必須): ラベルを合わせるリポジトリ(<owner>/<repo>)
#     GH_TOKEN(必須): gh の認証に使うトークン
#     GITHUB_STEP_SUMMARY(任意): 実行の要約のファイル。無ければ要約を書かない
# 終了コード: 0  = 検証に通った(--check)。または、合わせ込みに成功した(--check 無し)
#             1  = GitHub のラベルを読めなかった、書き込みが1件以上失敗した、
#                  または前の名前と新しい名前のラベルが両方あった(--check 無し)
#             2  = ファイルの検証に通らなかった(GitHub のラベルを1つも変えていない)
#             64 = 引数の誤り。または、--check 無しで GITHUB_REPOSITORY か GH_TOKEN が無いか、
#                  GITHUB_REPOSITORY の形が誤っている(GitHub のラベルを1つも変えていない)
# =====================================================================
set -euo pipefail

USAGE="使い方: sync-labels.sh [--check] [--file <パス>]"

usage_error() {
    echo "引数の誤り: $1" >&2
    echo "$USAGE" >&2
    exit 64
}

# --- 引数の読み取り -------------------------------------------------------------------
CHECK=0
FILE=".github/labels.json"
FILE_SET=0
while [ $# -gt 0 ]; do
    case "$1" in
    --check)
        [ "$CHECK" -eq 0 ] || usage_error "--check が2回あります"
        CHECK=1
        shift
        ;;
    --file)
        [ "$FILE_SET" -eq 0 ] || usage_error "--file が2回あります"
        [ $# -ge 2 ] && [ -n "$2" ] || usage_error "--file のあとにパスがありません"
        FILE="$2"
        FILE_SET=1
        shift 2
        ;;
    *)
        usage_error "知らない引数です: $1"
        ;;
    esac
done

# --- ファイルの検証 -------------------------------------------------------------------
invalid() {
    echo "${FILE}: $1" >&2
    exit 2
}

command -v jq >/dev/null 2>&1 || invalid "jq が無いため、検証できません"
[ -f "$FILE" ] && [ -r "$FILE" ] || invalid "ファイルがありません、または読めません"

# 誤りの文を1行ずつ出す jq の式。誤りが無ければ何も出さない。
# -s で読むので、入力はファイルの JSON の値の配列になる(値がちょうど1つであることを確かめる)。
# ファイルに書かれた文字列は tojson で引用符付きにして出す(改行を含んでも1行に収める)。
# shellcheck disable=SC2016 # $ は jq の変数で、シェルで展開しない
VALIDATE='
def obj: select(type == "object");
def at($i; $l):
  if ($l | type) == "object" and ($l.name | type) == "string"
  then "labels[\($i)](\($l.name | tojson))" else "labels[\($i)]" end;
def label_errors($i; $l):
  at($i; $l) as $at
  | if ($l | type) != "object" then "\($at): ラベルがオブジェクトではありません"
    else
      (("name", "group", "description", "color") as $k
        | select(($l[$k] | type) != "string")
        | "\($at): \($k) が無いか、文字列ではありません"),
      (select(($l.group | type) == "string" and ($l.group | IN("kind", "area", "other") | not))
        | "\($at): group が kind・area・other のどれでもありません(\($l.group | tojson))"),
      (select(($l.color | type) == "string" and ($l.color | test("^[0-9A-Fa-f]{6}$") | not))
        | "\($at): color が6桁の16進数ではありません(先頭の # は付けません)(\($l.color | tojson))"),
      (select(($l.description | type) == "string" and ($l.description | length) > 100)
        | "\($at): description が100文字を超えています(\($l.description | length)文字)"),
      (select($l | has("previous_names"))
        | select(if ($l.previous_names | type) == "array"
                 then all($l.previous_names[]; type == "string") else false end | not)
        | "\($at): previous_names が文字列の配列ではありません"),
      (select($l | has("selection_rule"))
        | select(if ($l.selection_rule | type) == "string"
                 then ($l.selection_rule | test("\\S")) else false end | not)
        | "\($at): selection_rule が空でない文字列ではありません"),
      (if $l.group == "kind" then
         select(($l.area_required | type) != "boolean")
         | "\($at): 種類のラベルに area_required(真偽値)がありません"
       else
         select($l | has("area_required"))
         | "\($at): 種類のラベルでないのに area_required があります"
       end)
    end;

if length != 1 then "JSON の値が1つではありません(\(length)個)"
else .[0]
  | if type != "object" then "最上位に配列 labels がありません"
    elif (.labels | type) != "array" then "最上位に配列 labels がありません"
    elif (.labels | length) == 0 then "labels が空です"
    else
      .labels as $labels
      | ($labels | to_entries[] | label_errors(.key; .value)),
        ([$labels[] | obj
          | (select((.name | type) == "string") | .name),
            (select((.previous_names | type) == "array") | .previous_names[] | select(type == "string"))]
         | map(ascii_downcase) | group_by(.) | map(select(length > 1) | .[0])[]
         | "名前が重なっています(大文字と小文字を区別しない): \(tojson)"),
        (select(any($labels[] | obj; .group == "kind") | not)
         | "group が kind のラベル(種類のラベル)がありません"),
        (select(any($labels[] | obj; .group == "kind" and .area_required == true)
                and (any($labels[] | obj; .group == "area") | not))
         | "area_required が true の種類のラベルがあるのに、group が area のラベル(場所のラベル)がありません")
    end
end
'

# 読めないときは jq の文を同じ1行に添える(成功したときの jq は標準エラーに何も出さない)
if ! errors=$(jq -r -s "$VALIDATE" "$FILE" 2>&1); then
    invalid "JSON として読めません($(printf '%s' "$errors" | tr '\n' ' '))"
fi
if [ -n "$errors" ]; then
    while IFS= read -r line; do
        echo "${FILE}: ${line}" >&2
    done <<<"$errors"
    exit 2
fi

if [ "$CHECK" -eq 1 ]; then
    echo "${FILE}: 検証に通りました" >&2
    exit 0
fi

# --- GitHub のラベルの合わせ込み -----------------------------------------------------------
setup_error() {
    echo "呼び出しの誤り: $1。GitHub のラベルを1つも変えずに終わります。" >&2
    exit 64
}

REPO="${GITHUB_REPOSITORY:-}"
[ -n "$REPO" ] || setup_error "環境変数 GITHUB_REPOSITORY(<owner>/<repo>)がありません"
[[ "$REPO" =~ ^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$ ]] ||
    setup_error "環境変数 GITHUB_REPOSITORY が <owner>/<repo> の形ではありません(${REPO})"
case "/${REPO}/" in
*/./* | */../*) setup_error "環境変数 GITHUB_REPOSITORY が <owner>/<repo> の形ではありません(${REPO})" ;;
esac
[ -n "${GH_TOKEN:-}" ] || setup_error "環境変数 GH_TOKEN がありません"

SUMMARY_FILE="${GITHUB_STEP_SUMMARY:-}"
GH_TIMEOUT=60
FAILURES=0
CHANGES=0

# 標準出力と実行の要約に1行書く
note() {
    echo "$1"
    if [ -n "$SUMMARY_FILE" ]; then echo "- $1" >>"$SUMMARY_FILE"; fi
}
# 失敗か食い違いを、標準エラーと実行の要約に1行書いて数える
problem() {
    echo "$1" >&2
    if [ -n "$SUMMARY_FILE" ]; then echo "- $1" >>"$SUMMARY_FILE"; fi
    FAILURES=$((FAILURES + 1))
}
cannot_read() {
    echo "GitHub のラベルを読めません($1)。ラベルを1つも変えずに、終了コード 1 で終わります。" >&2
    exit 1
}

command -v timeout >/dev/null 2>&1 || cannot_read "timeout が見つかりません"
TMP=$(mktemp -d) || cannot_read "一時フォルダを作れません"
trap 'rm -rf "$TMP"' EXIT

# gh を60秒で打ち切って呼ぶ。TERM で止まらなければ、さらに10秒後に KILL する
gh_call() {
    timeout -k 10 "$GH_TIMEOUT" gh "$@"
}
# gh の失敗の文を1行にする。使い方: gh_error <gh の終了コード>
gh_error() {
    local text
    text=$(tr '\n' ' ' <"$TMP/err.txt" | sed 's/[[:space:]]*$//')
    case "$1" in
    124 | 137) text="${GH_TIMEOUT}秒で打ち切りました${text:+。$text}" ;;
    esac
    printf '%s' "${text:-gh が終了コード $1 で終わりました}"
}

if [ -n "$SUMMARY_FILE" ]; then
    printf '## ラベルの合わせ込み(%s)\n\n' "$REPO" >>"$SUMMARY_FILE"
fi

# --- GitHub のラベルを全部読む ---------------------------------------------------------------
# gh api --paginate は、ページごとの配列を続けて出すので、-s で読んでつなぐ。
rc=0
gh_call api --paginate "repos/${REPO}/labels?per_page=100" </dev/null >"$TMP/remote.raw" 2>"$TMP/err.txt" || rc=$?
[ "$rc" -eq 0 ] || cannot_read "$(gh_error "$rc")"
# shellcheck disable=SC2016 # $ は jq の変数で、シェルで展開しない
NORMALIZE='
if length == 0 then error("応答が空です")
elif all(.[]; type == "array") | not then error("応答がラベルの配列ではありません")
else add
  | map(if type == "object" and (.name | type) == "string" and .name != ""
        then {name, description: (.description // "" | tostring), color: (.color // "" | tostring)}
        else error("応答に名前の無いラベルがあります") end)
end
'
if ! jq -s "$NORMALIZE" "$TMP/remote.raw" >"$TMP/remote.json" 2>"$TMP/err.txt"; then
    cannot_read "$(tr '\n' ' ' <"$TMP/err.txt")"
fi

# --- 書き込みを決める --------------------------------------------------------------------
# 最初に読んだ GitHub のラベルだけで、書き込みを順に決める。1行に1つ、JSON で出す。
#   op: rename(名前の変更)・conflict(前の名前と新しい名前の食い違い)・create・update・delete
# shellcheck disable=SC2016 # $ は jq の変数で、シェルで展開しない
PLAN='
def key: ascii_downcase;
def label_path($name): "repos/\($repo)/labels/\($name | @uri)";
$file[0].labels as $wanted
| $remote[0] as $current
| (reduce $current[] as $c ({}; .[$c.name | key] = $c)) as $by_key
| ([$wanted[] | .name, (.previous_names // [])[] | key] | map({(.): true}) | add) as $keep
| [$wanted[] as $l
   | {l: $l,
      cur: $by_key[$l.name | key],
      prevs: [($l.previous_names // [])[] | $by_key[key] | select(. != null)]}] as $items
| ($items[] | select(.cur == null and (.prevs | length) > 0)
   | {op: "rename", method: "PATCH", path: label_path(.prevs[0].name),
      from: .prevs[0].name, name: .l.name,
      body: {new_name: .l.name, description: .l.description, color: .l.color}}),
  ($items[] | .l.name as $n
   | (if .cur == null then .prevs[1:] else .prevs end)[]
   | {op: "conflict", from: .name, name: $n}),
  ($items[] | select(.cur != null or (.prevs | length) == 0)
   | if .cur == null then
       {op: "create", method: "POST", path: "repos/\($repo)/labels", name: .l.name,
        body: {name: .l.name, description: .l.description, color: .l.color}}
     elif .cur.name != .l.name or .cur.description != .l.description
          or (.cur.color | key) != (.l.color | key) then
       {op: "update", method: "PATCH", path: label_path(.cur.name), name: .l.name,
        body: ({description: .l.description, color: .l.color}
               + (if .cur.name != .l.name then {new_name: .l.name} else {} end))}
     else empty end),
  ($current[] | select($keep[.name | key] | not)
   | {op: "delete", method: "DELETE", path: label_path(.name), name: .name})
'
if ! jq -n -c --arg repo "$REPO" --slurpfile file "$FILE" --slurpfile remote "$TMP/remote.json" \
    "$PLAN" >"$TMP/plan.jsonl" 2>"$TMP/err.txt"; then
    cannot_read "書き込みを決められません: $(tr '\n' ' ' <"$TMP/err.txt")"
fi

# --- 書き込む ---------------------------------------------------------------------------
# 1件ずつ書き込み、失敗しても残りを続ける。使い方: write <書き込みの JSON>
write() {
    local method path rc=0
    method=$(jq -r '.method' <<<"$1")
    path=$(jq -r '.path' <<<"$1")
    if [ "$method" = "DELETE" ]; then
        gh_call api --silent -X DELETE "$path" </dev/null >/dev/null 2>"$TMP/err.txt" || rc=$?
    else
        jq -c '.body' <<<"$1" |
            gh_call api --silent -X "$method" "$path" --input - >/dev/null 2>"$TMP/err.txt" || rc=$?
    fi
    WRITE_RC=$rc
}

while IFS= read -r action <&3; do
    [ -n "$action" ] || continue
    op=$(jq -r '.op' <<<"$action")
    name=$(jq -r '.name' <<<"$action")
    from=$(jq -r '.from // ""' <<<"$action")
    case "$op" in
    conflict)
        problem "前の名前 ${from} と新しい名前 ${name} のラベルが両方あります。前の名前のラベルが付いた Issue と PR を新しい名前に付け替えてから、前の名前のラベルを GitHub の画面で消してください。"
        continue
        ;;
    rename) done_text="名前を変えました: ${from} を ${name} に" fail_text="名前を変えられませんでした: ${from} を ${name} に" ;;
    create) done_text="作りました: ${name}" fail_text="作れませんでした: ${name}" ;;
    update) done_text="直しました: ${name}" fail_text="直せませんでした: ${name}" ;;
    *) done_text="消しました: ${name}" fail_text="消せませんでした: ${name}" ;;
    esac
    write "$action"
    if [ "$WRITE_RC" -eq 0 ]; then
        note "$done_text"
        CHANGES=$((CHANGES + 1))
    else
        problem "${fail_text}($(gh_error "$WRITE_RC"))"
    fi
done 3<"$TMP/plan.jsonl"

if [ "$CHANGES" -eq 0 ] && [ "$FAILURES" -eq 0 ]; then
    note "変える必要のあるラベルはありませんでした"
fi
if [ "$FAILURES" -gt 0 ]; then
    echo "失敗か食い違いが ${FAILURES} 件ありました。終了コード 1 で終わります。" >&2
    exit 1
fi
exit 0
