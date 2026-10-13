#!/usr/bin/env bash
# =====================================================================
# sync-labels.sh の自動テスト(guardrails と sync-labels.yaml から実行)
#
# gh を PATH の先頭の偽物で置き換え、終了コード・標準出力・標準エラー・gh の呼び出しを確かめる。
# ファイルの検証(--check と、--check 無しで検証に通らないとき)では、gh が1回も呼ばれないことを確かめる。
#   終了コード 2  = ファイルの検証に通らなかった(GitHub のラベルを1つも変えていない)
#   終了コード 64 = 引数の誤り
#
# 検証の場合ごとのファイルは、検証に通る基準のファイルを jq で1か所だけ変えて作る。
# 1か所だけ変えるので、誤りの行がちょうど1行で、その場合の誤りの文を含むことも確かめる
# (ほかの誤りで終了コード2になって、テストが空振りしないようにするため)。
#
# GitHub のラベルの合わせ込み(--check 無し)では、偽物の gh が GitHub のラベルの一覧を持ち、
# GET に一覧を返し、POST・PATCH・DELETE を経路と本文ごとに記録して一覧に反映する。
#   終了コード 0 = 合わせ込みに成功した
#   終了コード 1 = ラベルを読めなかった、書き込みが失敗した、前の名前と新しい名前のラベルが両方あった
#
# 外部への問い合わせを行わないため、実行にネットワークを必要としない。jq と timeout が要る。
# =====================================================================
set -uo pipefail

SCRIPT="$(cd "$(dirname "$0")/.." && pwd)/sync-labels.sh"
REPO_ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
REPO_LABELS="${REPO_ROOT}/.github/labels.json"
WORK=$(mktemp -d) || exit 1
[ -n "$WORK" ] && [ -d "$WORK" ] || exit 1
trap 'rm -rf "$WORK"' EXIT
FAILED=0

command -v jq >/dev/null 2>&1 || {
    echo "jq がありません。jq のある環境で流してください。"
    exit 1
}

mkdir -p "$WORK/bin"

# --- gh の偽物 -------------------------------------------------------------------
# 呼び出しを $STUB_CALLS に、引数をそのまま1行ずつ記録する。
# $STUB_STATE が無いときは、記録して失敗する(ファイルの検証の場面では、gh が呼ばれないことを確かめる)。
# $STUB_STATE があるときは、そのファイルの JSON の配列を GitHub のラベルの一覧として、ラベルの API の
# ふりをする。
#   GET   repos/owner/repo/labels?per_page=100(--paginate 付き): 一覧を5件ずつのページに分け、
#         ページごとの配列を続けて出す(gh api --paginate の出し方と同じ)。
#         $STUB_FAIL_GET が 1 なら失敗する。$STUB_GET_BODY があれば、一覧の代わりにそれを出す
#   POST  repos/owner/repo/labels: 本文(--input -)の name・description・color のラベルを足す
#   PATCH repos/owner/repo/labels/<符号化した名前>: 本文の new_name・description・color で直す
#   DELETE repos/owner/repo/labels/<符号化した名前>: 消す
# 書き込みは「メソッド 経路 本文」を1行ずつ $STUB_WRITES に記録する。$STUB_FAIL のファイルに
# 「メソッド 経路」の行があれば、その書き込みを一覧に反映せずに失敗させる。経路の名前に符号化されて
# いない / や空白があれば失敗する。名前は GitHub と同じく大文字と小文字を区別せずに比べる。
cat >"$WORK/bin/gh" <<'STUB'
#!/usr/bin/env bash
printf '%s ' "$@" >>"${STUB_CALLS:?}"
printf '\n' >>"$STUB_CALLS"
if [ -z "${STUB_STATE:-}" ]; then
    echo "stub: gh はこのテストでは呼ばれないはずです" >&2
    exit 1
fi

fail() {
    echo "stub: $1" >&2
    exit 1
}
[ "${1:-}" = "api" ] || fail "gh api 以外の呼び出しです: $*"
shift
method=GET path="" input="" paginate=0
while [ $# -gt 0 ]; do
    case "$1" in
    --paginate)
        paginate=1
        shift
        ;;
    --silent) shift ;;
    -X | --method)
        [ $# -ge 2 ] || fail "-X の値がありません"
        method="$2"
        shift 2
        ;;
    --input)
        [ $# -ge 2 ] || fail "--input の値がありません"
        input="$2"
        shift 2
        ;;
    -*) fail "偽物の知らない引数です: $1" ;;
    *)
        [ -z "$path" ] || fail "経路が2つあります: $1"
        path="$1"
        shift
        ;;
    esac
done
body=""
if [ "$input" = "-" ]; then
    body=$(jq -c .) || fail "送られた本文が JSON ではありません"
elif [ -n "$input" ]; then
    fail "--input は - だけを想定しています: $input"
fi
if [ "$method" != "GET" ]; then
    printf '%s %s %s\n' "$method" "$path" "$body" >>"${STUB_WRITES:?}"
    if [ -n "${STUB_FAIL:-}" ] && grep -qxF -- "$method $path" "$STUB_FAIL"; then
        fail "HTTP 422: 書き込みに失敗しました ($method $path)"
    fi
fi

base="repos/owner/repo/labels"
# 経路の最後の部分を、符号化された名前として戻す
label_in_path() {
    local seg="${path#"$base/"}"
    case "$seg" in "" | */* | *" "*) fail "経路の名前が符号化されていません: $path" ;; esac
    printf '%b' "$(printf '%s' "$seg" | sed 's/%\([0-9A-Fa-f][0-9A-Fa-f]\)/\\x\1/g')"
}
has_label() {
    jq -e --arg n "$1" 'any(.[]; (.name | ascii_downcase) == ($n | ascii_downcase))' "$STUB_STATE" >/dev/null
}
update_state() {
    jq "$@" "$STUB_STATE" >"$STUB_STATE.new" && mv "$STUB_STATE.new" "$STUB_STATE"
}

case "$method $path" in
"GET $base?per_page=100")
    [ "${STUB_FAIL_GET:-}" != "1" ] || fail "HTTP 502: Bad Gateway"
    [ "$paginate" -eq 1 ] || fail "--paginate がありません"
    if [ -n "${STUB_GET_BODY:-}" ]; then
        printf '%s\n' "$STUB_GET_BODY"
    else
        jq -c 'if length == 0 then [] else . as $a | range(0; length; 5) as $i | $a[$i:$i + 5] end' "$STUB_STATE"
    fi
    ;;
"POST $base")
    name=$(jq -r '.name // ""' <<<"$body")
    [ -n "$name" ] || fail "HTTP 422: name がありません"
    ! has_label "$name" || fail "HTTP 422: already_exists ($name)"
    update_state --argjson b "$body" '. + [{name: $b.name, description: ($b.description // ""), color: $b.color}]'
    ;;
"PATCH $base/"* | "DELETE $base/"*)
    name=$(label_in_path) || exit 1
    has_label "$name" || fail "HTTP 404: Not Found ($name)"
    if [ "$method" = "DELETE" ]; then
        update_state --arg n "$name" 'map(select((.name | ascii_downcase) != ($n | ascii_downcase)))'
    else
        jq -e --arg n "$name" --argjson b "$body" '
            ($b.new_name // "" | ascii_downcase) as $nn
            | any(.[]; $nn != "" and (.name | ascii_downcase) == $nn
                       and (.name | ascii_downcase) != ($n | ascii_downcase)) | not' \
            "$STUB_STATE" >/dev/null || fail "HTTP 422: already_exists"
        update_state --arg n "$name" --argjson b "$body" '
            map(if (.name | ascii_downcase) == ($n | ascii_downcase)
                then .name = ($b.new_name // .name)
                     | .description = ($b.description // .description)
                     | .color = ($b.color // .color)
                else . end)'
    fi
    ;;
*) fail "偽物の知らない呼び出しです: $method $path" ;;
esac
exit 0
STUB
chmod +x "$WORK/bin/gh"

# 偽物が PATH の先頭で呼ばれ、呼び出しを記録できることを先に確かめる
# (下の「gh が呼ばれていない」の確かめが空振りしないようにするため)
: >"$WORK/calls.log"
PATH="$WORK/bin:$PATH" STUB_CALLS="$WORK/calls.log" gh probe 2>/dev/null
if [ "$(cat "$WORK/calls.log")" = "probe " ]; then
    echo "PASS: gh の偽物が呼び出しを記録する"
else
    echo "FAIL: gh の偽物が呼び出しを記録する"
    FAILED=1
fi
: >"$WORK/all-calls.log"

# --- 基準のファイル(検証に通る)-----------------------------------------------------
cat >"$WORK/base.json" <<'JSON'
{
  "labels": [
    {
      "name": "kind/bug",
      "group": "kind",
      "description": "今ある機能が本来の動きをしていないので、本来の動きに直す",
      "color": "d73a4a",
      "area_required": true,
      "previous_names": ["bug"]
    },
    {
      "name": "retrospective",
      "group": "kind",
      "description": "ゲートすり抜けの振り返り",
      "color": "0e8a16",
      "area_required": false,
      "selection_rule": "振り返りの手順で起票する Issue にだけ付ける"
    },
    {
      "name": "area/app",
      "group": "area",
      "description": "利用者が使う画面・API・データベースの中身",
      "color": "f9d0c4"
    },
    {
      "name": "blocked",
      "group": "other",
      "description": "人間の判断待ち",
      "color": "B60205"
    }
  ]
}
JSON

# 基準のファイルを jq の式で変えたファイルを $WORK/case.json に作る。使い方: mutate <jq の式>
mutate() {
    if ! jq "$1" "$WORK/base.json" >"$WORK/case.json"; then
        echo "FAIL: テストのファイルを作れません: $1"
        FAILED=1
        return 1
    fi
}

# スクリプトを動かす。使い方: run <引数>...
# 作業フォルダは $RUN_DIR(既定は $WORK)。
run() {
    : >"$WORK/calls.log"
    (cd "${RUN_DIR:-$WORK}" &&
        PATH="$WORK/bin:$PATH" STUB_CALLS="$WORK/calls.log" \
            GITHUB_REPOSITORY="owner/repo" GH_TOKEN="dummy" \
            bash "$SCRIPT" "$@" >"$WORK/out.txt" 2>"$WORK/err.txt")
    RC=$?
    cat "$WORK/calls.log" >>"$WORK/all-calls.log"
}

# --- 確かめ方 ---------------------------------------------------------------------
ok() { echo "PASS: $1"; }
ng() {
    echo "FAIL: $1"
    echo "  --- 標準出力 ---"
    sed 's/^/  /' "$WORK/out.txt"
    echo "  --- 標準エラー ---"
    sed 's/^/  /' "$WORK/err.txt"
    echo "  --- gh の呼び出し ---"
    sed 's/^/  /' "$WORK/calls.log"
    if [ -s "$WORK/writes.log" ]; then
        echo "  --- 書き込み ---"
        sed 's/^/  /' "$WORK/writes.log"
    fi
    FAILED=1
}

# 使い方: check <説明> <終了コード> [<標準エラーに含まれるはずの文>]
#   gh が1回も呼ばれていないことも確かめる。
check() {
    local name="$1" want_rc="$2" want_err="${3:-}"
    if [ "$RC" -ne "$want_rc" ]; then
        ng "$name (終了コード $want_rc のはずが $RC)"
        return
    fi
    if [ -s "$WORK/calls.log" ]; then
        ng "$name (gh が呼ばれた)"
        return
    fi
    if [ -n "$want_err" ] && ! grep -qF -- "$want_err" "$WORK/err.txt"; then
        ng "$name (標準エラーに「$want_err」が無い)"
        return
    fi
    ok "$name"
}

# 使い方: check_invalid <説明> <標準エラーの誤りの行に含まれるはずの文>
#   終了コード2、gh の呼び出し無し、誤りの行がちょうど1行でその文を含むことを確かめる。
check_invalid() {
    local name="$1" want_err="$2" lines
    check "$name" 2 "$want_err"
    [ "$RC" -eq 2 ] || return
    lines=$(grep -c . "$WORK/err.txt")
    if [ "$lines" -ne 1 ]; then
        ng "$name (誤りの行が1行のはずが ${lines}行)"
    fi
}

# --- 検証に通るファイル -----------------------------------------------------------------
run --check --file "$WORK/base.json"
check "基準のファイルが検証に通る" 0

run --check --file "$REPO_LABELS"
check "リポジトリの labels.json が検証に通る" 0

mkdir -p "$WORK/repo/.github"
cp "$REPO_LABELS" "$WORK/repo/.github/labels.json"
RUN_DIR="$WORK/repo" run --check
check "--file が無いときは作業フォルダの .github/labels.json を検証する" 0

mutate '.labels[0].description = ("あ" * 100)' &&
    run --check --file "$WORK/case.json"
check "説明が100文字(上限ちょうど)なら通る" 0

mutate '.labels[0].color = "D73A4A"' &&
    run --check --file "$WORK/case.json"
check "色の16進数は大文字でも通る" 0

mutate '.labels |= map(select(.name != "kind/bug"))' &&
    run --check --file "$WORK/case.json"
check "area_required が true の種類のラベルが無ければ、場所のラベルが無くても通る(場所のラベルはある)" 0

mutate '.labels |= map(select(.name != "kind/bug" and .group != "area"))' &&
    run --check --file "$WORK/case.json"
check "area_required が false の種類のラベルだけなら、場所のラベルが無くても通る" 0

# --- 検証に通らないファイル(終了コード2、gh を呼ばない)-------------------------------------
run --check --file "$WORK/none.json"
check_invalid "ファイルが無い" "ファイルがありません"

mkdir -p "$WORK/dir.json"
run --check --file "$WORK/dir.json"
check_invalid "ファイルの代わりにフォルダがある" "ファイルがありません"

printf '{"labels": [' >"$WORK/case.json"
run --check --file "$WORK/case.json"
check_invalid "JSON でない" "JSON として読めません"

: >"$WORK/case.json"
run --check --file "$WORK/case.json"
check_invalid "空のファイル" "JSON の値が1つではありません"

cat "$WORK/base.json" "$WORK/base.json" >"$WORK/case.json"
run --check --file "$WORK/case.json"
check_invalid "JSON の値が2つ並んでいる" "JSON の値が1つではありません"

printf '[]' >"$WORK/case.json"
run --check --file "$WORK/case.json"
check_invalid "最上位がオブジェクトでない" "最上位に配列 labels がありません"

mutate '{items: .labels}' &&
    run --check --file "$WORK/case.json"
check_invalid "最上位に labels が無い" "最上位に配列 labels がありません"

mutate '.labels = {}' &&
    run --check --file "$WORK/case.json"
check_invalid "labels が配列でない" "最上位に配列 labels がありません"

mutate '.labels = []' &&
    run --check --file "$WORK/case.json"
check_invalid "labels が空" "labels が空です"

mutate '.labels += ["blocked"]' &&
    run --check --file "$WORK/case.json"
check_invalid "ラベルがオブジェクトでない" "labels[4]: ラベルがオブジェクトではありません"

mutate 'del(.labels[2].name)' &&
    run --check --file "$WORK/case.json"
check_invalid "名前が無い" "labels[2]: name が無いか、文字列ではありません"

mutate '.labels[2].description = 1' &&
    run --check --file "$WORK/case.json"
check_invalid "説明が文字列でない" "labels[2](\"area/app\"): description が無いか、文字列ではありません"

mutate 'del(.labels[3].color)' &&
    run --check --file "$WORK/case.json"
check_invalid "色が無い" "labels[3](\"blocked\"): color が無いか、文字列ではありません"

mutate 'del(.labels[3].group)' &&
    run --check --file "$WORK/case.json"
check_invalid "組が無い" "labels[3](\"blocked\"): group が無いか、文字列ではありません"

mutate '.labels[3].group = "misc"' &&
    run --check --file "$WORK/case.json"
check_invalid "組が kind・area・other のどれでもない" "group が kind・area・other のどれでもありません"

mutate '.labels |= map(select(.group != "kind"))' &&
    run --check --file "$WORK/case.json"
check_invalid "kind が無い" "group が kind のラベル(種類のラベル)がありません"

mutate '.labels |= map(select(.group != "area"))' &&
    run --check --file "$WORK/case.json"
check_invalid "area_required が true の種類があるのに area が無い" "group が area のラベル(場所のラベル)がありません"

mutate '.labels[0].color = "#d73a4a"' &&
    run --check --file "$WORK/case.json"
check_invalid "色に # が付いている" "labels[0](\"kind/bug\"): color が6桁の16進数ではありません"

mutate '.labels[0].color = "d73a4"' &&
    run --check --file "$WORK/case.json"
check_invalid "色が5桁" "color が6桁の16進数ではありません"

mutate '.labels[0].color = "d73a4g"' &&
    run --check --file "$WORK/case.json"
check_invalid "色に16進数でない文字がある" "color が6桁の16進数ではありません"

mutate '.labels[0].description = ("あ" * 101)' &&
    run --check --file "$WORK/case.json"
check_invalid "説明が101文字" "labels[0](\"kind/bug\"): description が100文字を超えています(101文字)"

mutate '.labels[1].previous_names = ["kind/bug"]' &&
    run --check --file "$WORK/case.json"
check_invalid "名前と前の名前が重なる" "名前が重なっています(大文字と小文字を区別しない): \"kind/bug\""

mutate '.labels[2].previous_names = ["BUG"]' &&
    run --check --file "$WORK/case.json"
check_invalid "前の名前どうしが大文字と小文字の違いだけで重なる" "名前が重なっています(大文字と小文字を区別しない): \"bug\""

mutate '.labels[3].name = "Area/App"' &&
    run --check --file "$WORK/case.json"
check_invalid "名前どうしが大文字と小文字の違いだけで重なる" "名前が重なっています(大文字と小文字を区別しない): \"area/app\""

mutate '.labels[0].previous_names = "bug"' &&
    run --check --file "$WORK/case.json"
check_invalid "前の名前が配列でない" "labels[0](\"kind/bug\"): previous_names が文字列の配列ではありません"

mutate '.labels[0].previous_names = ["bug", 1]' &&
    run --check --file "$WORK/case.json"
check_invalid "前の名前に文字列でないものがある" "previous_names が文字列の配列ではありません"

mutate 'del(.labels[0].area_required)' &&
    run --check --file "$WORK/case.json"
check_invalid "種類のラベルに area_required が無い" "labels[0](\"kind/bug\"): 種類のラベルに area_required(真偽値)がありません"

mutate '.labels[0].area_required = "true"' &&
    run --check --file "$WORK/case.json"
check_invalid "種類のラベルの area_required が真偽値でない" "種類のラベルに area_required(真偽値)がありません"

mutate '.labels[2].area_required = false' &&
    run --check --file "$WORK/case.json"
check_invalid "種類でないラベルに area_required がある" "labels[2](\"area/app\"): 種類のラベルでないのに area_required があります"

mutate '.labels[1].selection_rule = ""' &&
    run --check --file "$WORK/case.json"
check_invalid "selection_rule が空" "labels[1](\"retrospective\"): selection_rule が空でない文字列ではありません"

mutate '.labels[1].selection_rule = " \t"' &&
    run --check --file "$WORK/case.json"
check_invalid "selection_rule が空白だけ" "selection_rule が空でない文字列ではありません"

mutate '.labels[1].selection_rule = null' &&
    run --check --file "$WORK/case.json"
check_invalid "selection_rule が文字列でない" "selection_rule が空でない文字列ではありません"

# 誤りが2か所あれば、2行出す
mutate '.labels[0].color = "#d73a4a" | .labels[2].area_required = false' &&
    run --check --file "$WORK/case.json"
check "誤りが2か所あるファイル" 2
if [ "$RC" -eq 2 ] && [ "$(grep -c . "$WORK/err.txt")" -eq 2 ] &&
    grep -qF 'color が6桁の16進数ではありません' "$WORK/err.txt" &&
    grep -qF '種類のラベルでないのに area_required があります' "$WORK/err.txt"; then
    ok "誤りを1行ずつ、すべて標準エラーに出す"
else
    ng "誤りを1行ずつ、すべて標準エラーに出す"
fi

# --check 無しでも、検証に通らなければ gh を呼ばずに2で終わる
mutate '.labels = []' &&
    run --file "$WORK/case.json"
check_invalid "--check 無しでも、検証に通らないファイルでは gh を呼ばずに2で終わる" "labels が空です"

# --- 引数の誤り(終了コード64、gh を呼ばない)----------------------------------------------
run --check --unknown
check "知らない引数" 64 "使い方:"

run --check --file
check "--file のあとにパスが無い" 64 "使い方:"

run --check --file ""
check "--file のパスが空" 64 "使い方:"

run --check --check --file "$WORK/base.json"
check "--check が2回ある" 64 "使い方:"

run --check --file "$WORK/base.json" --file "$WORK/base.json"
check "--file が2回ある" 64 "使い方:"

run --check "$WORK/base.json"
check "--file を付けずにパスを渡す" 64 "使い方:"

# --- 検証と引数の誤りの全体 -------------------------------------------------------------
if [ -s "$WORK/all-calls.log" ]; then
    echo "FAIL: 検証と引数の誤りのどの場面でも gh が呼ばれていない"
    sed 's/^/  /' "$WORK/all-calls.log"
    FAILED=1
else
    ok "検証と引数の誤りのどの場面でも gh が呼ばれていない"
fi

# =====================================================================
# GitHub のラベルの合わせ込み(--check 無し)
# =====================================================================
STATE="$WORK/state.json"
WRITES="$WORK/writes.log"
FAILS="$WORK/fail.txt"
SUMMARY="$WORK/summary.md"
API="repos/owner/repo/labels"

# GitHub のラベルの一覧を $STATE に置き、失敗させる書き込みを空にする。
# 一覧は、基準のファイルのラベルと同じ名前・説明・色の一覧を、jq の式で変えて作る。
# 使い方: github_labels <jq の式>
github_labels() {
    : >"$FAILS"
    if ! jq "[.labels[] | {name, description, color}] | $1" "$WORK/base.json" >"$STATE"; then
        echo "FAIL: GitHub のラベルの一覧を作れません: $1"
        FAILED=1
        return 1
    fi
}

# スクリプトを --check 無しで動かす。使い方: run_sync <引数>...
# 次の変数を前に付けると、偽物の gh と環境変数を変えられる。
#   STUB_FAIL_GET=1、STUB_GET_BODY=<GET の応答>、SYNC_REPO=<GITHUB_REPOSITORY>、
#   SYNC_TOKEN=<GH_TOKEN>、SYNC_SUMMARY=<GITHUB_STEP_SUMMARY>(空なら要約を書かない)、
#   SYNC_EXTRA_BIN=<PATH の先頭に足すフォルダ>
run_sync() {
    : >"$WORK/calls.log"
    : >"$WRITES"
    : >"$SUMMARY"
    (cd "$WORK" &&
        PATH="${SYNC_EXTRA_BIN:+$SYNC_EXTRA_BIN:}$WORK/bin:$PATH" STUB_CALLS="$WORK/calls.log" STUB_STATE="$STATE" \
            STUB_WRITES="$WRITES" STUB_FAIL="$FAILS" \
            STUB_FAIL_GET="${STUB_FAIL_GET:-}" STUB_GET_BODY="${STUB_GET_BODY:-}" \
            GITHUB_REPOSITORY="${SYNC_REPO-owner/repo}" GH_TOKEN="${SYNC_TOKEN-dummy}" \
            GITHUB_STEP_SUMMARY="${SYNC_SUMMARY-$SUMMARY}" \
            bash "$SCRIPT" "$@" >"$WORK/out.txt" 2>"$WORK/err.txt")
    RC=$?
}

# 使い方: expect_writes <説明> <終了コード> <「メソッド 経路」の行を改行でつないだもの(無ければ空)>
#   終了コードと、書き込みがこの順でちょうどこれだけであることを確かめる。
expect_writes() {
    local name="$1" want_rc="$2" want="$3" got
    got=$(awk '{ print $1, $2 }' "$WRITES")
    if [ "$RC" -ne "$want_rc" ]; then
        ng "$name (終了コード $want_rc のはずが $RC)"
    elif [ "$got" != "$want" ]; then
        ng "$name (書き込みが期待と違う。期待: $(printf '%s' "$want" | tr '\n' ';'))"
    else
        ok "$name"
    fi
}

# 使い方: expect <説明> <コマンド>...   コマンドが成功すれば合格
expect() {
    local name="$1"
    shift
    if "$@"; then
        ok "$name"
    else
        ng "$name"
    fi
}

# 書き込みの本文を出す。使い方: body_of <メソッド> <経路>
body_of() {
    awk -v m="$1" -v p="$2" '$1 == m && $2 == p { sub(/^[^ ]+ [^ ]+ /, ""); print; exit }' "$WRITES"
}
# 書き込みの本文に jq -e の式を当てる。使い方: body_is <メソッド> <経路> <jq の式>
body_is() {
    body_of "$1" "$2" | jq -e --slurpfile f "$WORK/base.json" "$3" >/dev/null
}
# GitHub のラベルの一覧に jq -e の式を当てる。使い方: state_is <jq の式>
state_is() {
    jq -e "$1" "$STATE" >/dev/null
}
# 文が標準出力と実行の要約の両方にある
reported() {
    grep -qF -- "$1" "$WORK/out.txt" && grep -qF -- "$1" "$SUMMARY"
}
# 文が標準エラーと実行の要約の両方にある
reported_err() {
    grep -qF -- "$1" "$WORK/err.txt" && grep -qF -- "$1" "$SUMMARY"
}
# 文がすべて標準エラーにある。使い方: err_has <文>...
err_has() {
    local s
    for s in "$@"; do
        grep -qF -- "$s" "$WORK/err.txt" || return 1
    done
}
# GitHub に送った欄が name(または new_name)・description・color だけである
sent_fields_only() {
    local method body
    [ -s "$WRITES" ] || return 1
    while read -r method _ body; do
        case "$method" in
        POST) jq -e 'keys == ["color", "description", "name"]' <<<"$body" >/dev/null || return 1 ;;
        PATCH) jq -e '(keys - ["color", "description", "new_name"]) == [] and has("description") and has("color")' \
            <<<"$body" >/dev/null || return 1 ;;
        DELETE) [ -z "$body" ] || return 1 ;;
        *) return 1 ;;
        esac
    done <"$WRITES"
}

BUG_ON_GITHUB='{name: "bug", description: "Something is not working", color: "d73a4a"}'
QUESTION_ON_GITHUB='{name: "question", description: "Further information is requested", color: "d876e3"}'

# --- 作成と直し ---------------------------------------------------------------------
github_labels 'map(select(.name != "area/app"))' &&
    run_sync --file "$WORK/base.json"
expect_writes "GitHub に無いラベルを作る" 0 "POST $API"
# shellcheck disable=SC2016 # $ は jq の変数で、シェルで展開しない
expect "作る本文が、ファイルの名前・説明・色である" \
    body_is POST "$API" '. == ($f[0].labels[2] | {name, description, color})'
expect "作ったラベルが GitHub の一覧に入る" \
    state_is 'any(.[]; .name == "area/app" and .color == "f9d0c4") and length == 4'
expect "作ったラベルを標準出力と実行の要約に書く" reported "作りました: area/app"

github_labels '(.[] | select(.name == "retrospective") | .description) = "古い説明"
               | (.[] | select(.name == "blocked") | .color) = "000000"' &&
    run_sync --file "$WORK/base.json"
expect_writes "説明か色が違うラベルを直す" 0 "PATCH $API/retrospective
PATCH $API/blocked"
# shellcheck disable=SC2016 # $ は jq の変数で、シェルで展開しない
expect "説明を直す本文が、ファイルの説明と色である" \
    body_is PATCH "$API/retrospective" '. == ($f[0].labels[1] | {description, color})'
# shellcheck disable=SC2016 # $ は jq の変数で、シェルで展開しない
expect "色を直す本文が、ファイルの説明と色である" \
    body_is PATCH "$API/blocked" '. == ($f[0].labels[3] | {description, color})'
expect "直したラベルを標準出力と実行の要約に書く" reported "直しました: blocked"

github_labels '(.[] | select(.name == "blocked") | .color) = "b60205"
               | (.[] | select(.name == "kind/bug") | .color) = "D73A4A"' &&
    run_sync --file "$WORK/base.json"
expect_writes "色の大文字と小文字だけの違いは直さない" 0 ""
expect "変えるラベルが無いことを標準出力と実行の要約に書く" reported "変える必要のあるラベルはありませんでした"

github_labels '(.[] | select(.name == "area/app") | .name) = "Area/App"' &&
    run_sync --file "$WORK/base.json"
expect_writes "名前の大文字と小文字だけが違うラベルを直す" 0 "PATCH $API/Area%2FApp"
expect "名前の大文字と小文字を直す本文の new_name が、ファイルの名前である" \
    body_is PATCH "$API/Area%2FApp" '.new_name == "area/app"'
expect "名前の大文字と小文字を直したラベルが GitHub の一覧に入る" \
    state_is 'any(.[]; .name == "area/app") and length == 4'

# --- 削除 -------------------------------------------------------------------------
github_labels ". + [$QUESTION_ON_GITHUB, {name: \"手で足したラベル\", description: \"\", color: \"ededed\"}]" &&
    run_sync --file "$WORK/base.json"
expect_writes "ファイルに無いラベルに DELETE を呼ぶ" 0 "DELETE $API/question
DELETE $API/%E6%89%8B%E3%81%A7%E8%B6%B3%E3%81%97%E3%81%9F%E3%83%A9%E3%83%99%E3%83%AB"
expect "ファイルに無いラベルを消す" \
    state_is '(map(.name) | sort) == ["area/app", "blocked", "kind/bug", "retrospective"]'
expect "消したラベルを標準出力と実行の要約に書く" reported "消しました: 手で足したラベル"

# --- 符号化 -------------------------------------------------------------------------
github_labels "(.[] | select(.name == \"kind/bug\") | .description) = \"古い説明\"
               | . + [{name: \"good first issue\", description: \"Good for newcomers\", color: \"7057ff\"}]" &&
    run_sync --file "$WORK/base.json"
expect_writes "経路の名前を符号化する(kind%2Fbug、good%20first%20issue)" 0 "PATCH $API/kind%2Fbug
DELETE $API/good%20first%20issue"

# --- ページに分かれた一覧 ------------------------------------------------------------------
# 偽物は5件ずつのページで返す。area/app を2ページ目に置き、2ページ目のラベルも読むことを確かめる
github_labels "map(select(.name != \"area/app\"))
               + [{name: \"extra1\", description: \"\", color: \"ededed\"},
                  {name: \"extra2\", description: \"\", color: \"ededed\"},
                  {name: \"extra3\", description: \"\", color: \"ededed\"}]
               + map(select(.name == \"area/app\"))" &&
    jq -e 'length == 7 and .[6].name == "area/app"' "$STATE" >/dev/null &&
    run_sync --file "$WORK/base.json"
expect_writes "ページに分かれた一覧を全部読む" 0 "DELETE $API/extra1
DELETE $API/extra2
DELETE $API/extra3"

# --- 名前の変更 ---------------------------------------------------------------------
github_labels "map(if .name == \"kind/bug\" then $BUG_ON_GITHUB else . end)" &&
    run_sync --file "$WORK/base.json"
expect_writes "前の名前のラベルだけがあるときは名前を変えて消さない" 0 "PATCH $API/bug"
# shellcheck disable=SC2016 # $ は jq の変数で、シェルで展開しない
expect "名前を変える本文が、ファイルの名前(new_name)・説明・色である" \
    body_is PATCH "$API/bug" '. == ($f[0].labels[0] | {new_name: .name, description, color})'
expect "名前を変えたラベルが新しい名前で GitHub の一覧にある" \
    state_is 'any(.[]; .name == "kind/bug") and (any(.[]; .name == "bug") | not) and length == 4'
expect "名前を変えたラベルを標準出力と実行の要約に書く" reported "名前を変えました: bug を kind/bug に"

github_labels "map(if .name == \"kind/bug\" then {name: \"Bug\", description: \"x\", color: \"d73a4a\"} else . end)" &&
    run_sync --file "$WORK/base.json"
expect_writes "前の名前を大文字と小文字を区別せずに見つけて名前を変える" 0 "PATCH $API/Bug"

github_labels ". + [$BUG_ON_GITHUB, $QUESTION_ON_GITHUB]" &&
    run_sync --file "$WORK/base.json"
expect_writes "両方あるときは変えず消さず1で終わる" 1 "DELETE $API/question"
expect "両方あるときの文を標準エラーと実行の要約に出す" \
    reported_err "前の名前 bug と新しい名前 kind/bug のラベルが両方あります"
expect "両方あるときは前の名前と新しい名前のラベルが GitHub に残る" \
    state_is 'any(.[]; .name == "bug") and any(.[]; .name == "kind/bug")'

mutate '.labels[0].previous_names = ["bug", "defect"]' &&
    github_labels "map(if .name == \"kind/bug\" then $BUG_ON_GITHUB else . end)
                   + [{name: \"defect\", description: \"x\", color: \"d73a4a\"}]" &&
    run_sync --file "$WORK/case.json"
expect_writes "前の名前のラベルが2つあるときは1つ目の名前を変え、もう1つは変えず消さず1で終わる" 1 "PATCH $API/bug"
expect "前の名前のラベルが2つあるときの文を標準エラーと実行の要約に出す" \
    reported_err "前の名前 defect と新しい名前 kind/bug のラベルが両方あります"

github_labels "map(if .name == \"kind/bug\" then $BUG_ON_GITHUB else . end)" &&
    echo "PATCH $API/bug" >"$FAILS" &&
    run_sync --file "$WORK/base.json"
expect_writes "名前の変更が失敗しても同じ実行で新しい名前のラベルを作らない" 1 "PATCH $API/bug"
expect "名前の変更に失敗したラベルと gh の文を標準エラーに出す" \
    err_has "名前を変えられませんでした: bug を kind/bug に" "HTTP 422"
expect "名前の変更に失敗したときは前の名前のラベルが GitHub に残る" \
    state_is 'any(.[]; .name == "bug") and (any(.[]; .name == "kind/bug") | not)'

# --- 順番と、2回目の実行 ---------------------------------------------------------------
github_labels "map(if .name == \"kind/bug\" then $BUG_ON_GITHUB else . end)
               | map(select(.name != \"retrospective\"))
               | (.[] | select(.name == \"blocked\") | .color) = \"000000\"
               | . + [$QUESTION_ON_GITHUB]" &&
    run_sync --file "$WORK/base.json"
expect_writes "名前の変更、作成と直し、削除の順に書き込む" 0 "PATCH $API/bug
POST $API
PATCH $API/blocked
DELETE $API/question"
expect "送る欄が name・description・color だけである" sent_fields_only
# shellcheck disable=SC2016 # $ は jq の変数で、シェルで展開しない
expect "area_required と selection_rule を送らない" \
    body_is POST "$API" '. == ($f[0].labels[1] | {name, description, color}) and (has("area_required") | not) and (has("selection_rule") | not)'
for line in "名前を変えました: bug を kind/bug に" "作りました: retrospective" "直しました: blocked" "消しました: question"; do
    expect "「${line}」を標準出力と実行の要約に1件ずつ書く" reported "$line"
done
expect "合わせ込んだあとの GitHub の一覧がファイルのとおりになる" \
    state_is "(map(.name) | sort) == ([\"area/app\", \"blocked\", \"kind/bug\", \"retrospective\"])"

run_sync --file "$WORK/base.json"
expect_writes "2回目の実行は何も書き込まない" 0 ""

# --- 失敗 -------------------------------------------------------------------------
github_labels "map(select(.name != \"area/app\"))
               | (.[] | select(.name == \"blocked\") | .color) = \"000000\"
               | . + [$QUESTION_ON_GITHUB]" &&
    echo "PATCH $API/blocked" >"$FAILS" &&
    run_sync --file "$WORK/base.json"
expect_writes "書き込みの1件が失敗しても残りを続けて1で終わる" 1 "POST $API
PATCH $API/blocked
DELETE $API/question"
expect "失敗した書き込みのほかは GitHub の一覧に反映される" \
    state_is 'any(.[]; .name == "area/app") and (any(.[]; .name == "question") | not)'
expect "失敗したラベルと gh の文を標準エラーに出す" err_has "直せませんでした: blocked" "HTTP 422"

github_labels ". + [$QUESTION_ON_GITHUB]" &&
    STUB_FAIL_GET=1 run_sync --file "$WORK/base.json"
expect_writes "ラベルを読めないときは書き込まずに1で終わる" 1 ""
expect "ラベルを読めないことと gh の文を標準エラーに出す" err_has "GitHub のラベルを読めません" "HTTP 502"

STUB_GET_BODY='not json' run_sync --file "$WORK/base.json"
expect_writes "ラベルの一覧が JSON でないときは書き込まずに1で終わる" 1 ""

STUB_GET_BODY='{"message": "Not Found"}' run_sync --file "$WORK/base.json"
expect_writes "ラベルの一覧が配列でないときは書き込まずに1で終わる" 1 ""

STUB_GET_BODY='[{"description": "x", "color": "ededed"}]' run_sync --file "$WORK/base.json"
expect_writes "ラベルの一覧に名前の無いものがあるときは書き込まずに1で終わる" 1 ""

# --- 環境変数 -----------------------------------------------------------------------
github_labels 'map(select(.name != "area/app"))' &&
    SYNC_SUMMARY="" run_sync --file "$WORK/base.json"
expect_writes "GITHUB_STEP_SUMMARY が無くても合わせ込む" 0 "POST $API"
expect "GITHUB_STEP_SUMMARY が無いときも標準出力に書く" grep -qF "作りました: area/app" "$WORK/out.txt"
expect "GITHUB_STEP_SUMMARY が無いときは要約のファイルに書かない" test ! -s "$SUMMARY"

SYNC_REPO="" run_sync --file "$WORK/base.json"
check "GITHUB_REPOSITORY が無いときは gh を呼ばずに64で終わる" 64 "環境変数 GITHUB_REPOSITORY(<owner>/<repo>)がありません"

SYNC_REPO="owner" run_sync --file "$WORK/base.json"
check "GITHUB_REPOSITORY が <owner>/<repo> の形でないときは gh を呼ばずに64で終わる" 64 "環境変数 GITHUB_REPOSITORY が <owner>/<repo> の形ではありません(owner)"

SYNC_REPO="owner/.." run_sync --file "$WORK/base.json"
check "GITHUB_REPOSITORY のリポジトリの名前が .. のときは gh を呼ばずに64で終わる" 64 "環境変数 GITHUB_REPOSITORY が <owner>/<repo> の形ではありません(owner/..)"

SYNC_TOKEN="" run_sync --file "$WORK/base.json"
check "GH_TOKEN が無いときは gh を呼ばずに64で終わる" 64 "環境変数 GH_TOKEN がありません"

# --- gh の呼び出しの時間の上限 -----------------------------------------------------------
# timeout を、引数を記録してから本物の timeout を呼ぶ偽物に置き換え、gh の呼び出しがすべて
# 60秒の上限つきで呼ばれることを確かめる
REAL_TIMEOUT=$(command -v timeout) || {
    echo "timeout がありません。timeout のある環境で流してください。"
    exit 1
}
mkdir -p "$WORK/tbin"
cat >"$WORK/tbin/timeout" <<STUB
#!/usr/bin/env bash
printf '%s\n' "\$*" >>"$WORK/timeout.log"
exec "$REAL_TIMEOUT" "\$@"
STUB
chmod +x "$WORK/tbin/timeout"
: >"$WORK/timeout.log"
github_labels "map(if .name == \"kind/bug\" then $BUG_ON_GITHUB else . end)
               | map(select(.name != \"retrospective\")) | . + [$QUESTION_ON_GITHUB]" &&
    SYNC_EXTRA_BIN="$WORK/tbin" run_sync --file "$WORK/base.json"
# GET・名前の変更・作成・削除の4回の gh の呼び出しが、どれも timeout -k 10 60 を通っている
all_gh_calls_time_limited() {
    [ "$RC" -eq 0 ] &&
        [ "$(grep -c . "$WORK/calls.log")" -eq 4 ] &&
        [ "$(grep -c . "$WORK/timeout.log")" -eq 4 ] &&
        [ "$(grep -c '^-k 10 60 gh api ' "$WORK/timeout.log")" -eq 4 ]
}
expect "gh の呼び出しをすべて60秒で打ち切る" all_gh_calls_time_limited

# --- リポジトリの labels.json で、今の GitHub のラベルを合わせる(design の「移行」)-----------------
# 今の GitHub: 最初からある9個(bug など)と、そのほかのラベル(7個は色が大文字)
cat >"$WORK/defaults.json" <<'JSON'
[
  {"name": "bug", "description": "Something isn't working", "color": "d73a4a"},
  {"name": "documentation", "description": "Improvements or additions to documentation", "color": "0075ca"},
  {"name": "duplicate", "description": "This issue or pull request already exists", "color": "cfd3d7"},
  {"name": "enhancement", "description": "New feature or request", "color": "a2eeef"},
  {"name": "good first issue", "description": "Good for newcomers", "color": "7057ff"},
  {"name": "help wanted", "description": "Extra attention is needed", "color": "008672"},
  {"name": "invalid", "description": "This doesn't seem right", "color": "e4e669"},
  {"name": "question", "description": "Further information is requested", "color": "d876e3"},
  {"name": "wontfix", "description": "This will not be worked on", "color": "ffffff"}
]
JSON
: >"$FAILS"
jq -s '.[0] + [.[1].labels[] | select(.group == "other")
               | {name, description,
                  color: (if IN(.name; "blocked", "audit", "container-vuln", "canary",
                                       "pre-merge-check", "migration", "codex-overruled")
                          then (.color | ascii_upcase) else .color end)}]' \
    "$WORK/defaults.json" "$REPO_LABELS" >"$STATE"
run_sync --file "$REPO_LABELS"
expect_writes "リポジトリの labels.json で今の GitHub のラベルを合わせる(名前の変更3つ、作成7つ、削除6つ)" 0 "PATCH $API/bug
PATCH $API/enhancement
PATCH $API/documentation
POST $API
POST $API
POST $API
POST $API
POST $API
POST $API
POST $API
DELETE $API/duplicate
DELETE $API/good%20first%20issue
DELETE $API/help%20wanted
DELETE $API/invalid
DELETE $API/question
DELETE $API/wontfix"
expect "リポジトリの labels.json で作るラベルが、種類と場所の7つである" \
    test "$(awk '$1 == "POST" { sub(/^[^ ]+ [^ ]+ /, ""); print }' "$WRITES" | jq -r .name | tr '\n' ' ')" \
    = "kind/feature kind/cleanup kind/dependency retrospective area/app area/infra area/dev-platform "
# shellcheck disable=SC2016 # $ は jq の変数で、シェルで展開しない
expect "リポジトリの labels.json で合わせたあとの GitHub の一覧がファイルのとおりになる" \
    jq -e -n --slurpfile s "$STATE" --slurpfile f "$REPO_LABELS" \
    '($s[0] | map({name, description, color: (.color | ascii_downcase)}) | sort_by(.name))
     == ($f[0].labels | map({name, description, color: (.color | ascii_downcase)}) | sort_by(.name))'

run_sync --file "$REPO_LABELS"
expect_writes "リポジトリの labels.json で2回目の実行は何も書き込まない" 0 ""

if [ "$FAILED" -ne 0 ]; then
    echo "テストに失敗があります。"
    exit 1
fi
echo "全てのテストが通りました。"
