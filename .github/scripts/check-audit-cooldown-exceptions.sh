#!/usr/bin/env bash
# =====================================================================
# 公開から72時間待たずに入れた版の一覧(audit-weekly CI から実行)
#
# 窓の中でマージされた PR を読み、次の2つの記録を一覧にして報告する。
#   frontend と backend の版: PR のコメントのうち、github-actions[bot] が書いた
#     <!-- cooldown-exception-record kind=exception head=<マージした head> -->
#     のコメントの <!-- cooldown-exception-data data=<base64> --> の記録の JSON
#     (record-cooldown-exception.sh が書く)
#   CI の道具の版: PR の本文の <!-- ci-tool-cooldown-exception data=<base64> --> の記録の JSON
# 窓は、前の回の週次監査の実行の created_at から今の時刻までである。
# このスクリプトは記録を書き換えない。
#
# 終了コード:
#   0 = 一覧に載せる版が無い(報告に何も書かない)
#   1 = 一覧に載せる版がある
#   2 = 記録を読めなかった(読めなかった PR の番号と理由を報告に書く)
#   1 は一覧を報告したうえでの明示的な exit 1 だけが返す。引数・必須の環境変数の
#   欠落と、ガードしていないコマンドの想定外の失敗はすべて 2 に倒す。
#
# なぜ載せる版があると 1 を返すのか:
#   72時間待たずに入れた版は、決まりから外れたものではない。それでも 1 を返すと、
#   audit-issue.sh が所有者を担当者にした Issue「週次監査: 逸脱あり」に一覧を載せる。
#   一覧を所有者に届ける経路を新しく作らずに済む。
#
# 窓の決め方(なぜ今の GITHUB_RUN_ID を除くのか):
#   check-audit-skipped-required.sh と同じく、audit-weekly.yaml の実行の一覧から
#   今の実行を除いた直近の実行の created_at を窓の始まりにする(無ければ7日前)。
#   実行の一覧の先頭は今の実行なので、除かないと窓の始まりが今の時刻になり、
#   一覧がいつも空になる。
#
# なぜマージした head の記録だけを数えるのか:
#   記録のコメントは head ごとに書かれる。前の head の記録の版は、そのあとの
#   変更で入らなくなっていることがある。マージされた中身に入った版だけを載せる。
#
# なぜ github-actions[bot] が書いたコメントだけを数えるのか:
#   誰でもコメントに同じ目印を書ける。書いた者を問わずに数えると、第三者が
#   一覧に偽の版を載せられる。作成者で絞った一覧は lib-notice-comment.sh の
#   _notice_author_comments が返す(record-cooldown-exception.sh と同じ絞り方)。
#
# なぜ CI の道具の記録は PR の本文から読むのか:
#   CI の道具の版を変える PR は Claude が作り、所有者が承認してからマージされる。
#   所有者は承認するときに、本文の記録を読める。どの回の一覧に載るかは、
#   その PR がマージされた日時で決まる。
#
# なぜ読めなかった PR があっても、ほかの PR を読み続けるのか:
#   途中で止めると、読めた PR の版が報告に出ず、判定不能の陰に隠れる。
#   読めなかった PR の番号と理由を並べ、読めた版の一覧と一緒に報告する。
#
# テスト: .github/scripts/tests/test-check-audit-cooldown-exceptions.sh
# 使い方: check-audit-cooldown-exceptions.sh
#   必須の環境変数: GH_TOKEN GITHUB_REPOSITORY GITHUB_REPOSITORY_OWNER GITHUB_RUN_ID
#   (GITHUB_REPOSITORY_OWNER は lib-notice-comment.sh が使う。ランナーが既定で渡す)
#   任意の環境変数: NOW_EPOCH(テスト用の時刻の固定)
# =====================================================================
set -Eeuo pipefail
# ガードしていないコマンドの失敗は、一覧あり(1)ではなく判定不能(2)にする。
# -E で関数・コマンド置換の中の失敗にも当てる。
trap 'exit 2' ERR

for v in GH_TOKEN GITHUB_REPOSITORY GITHUB_REPOSITORY_OWNER GITHUB_RUN_ID; do
    if [ -z "${!v:-}" ]; then
        echo "::error::環境変数 ${v} が必要です"
        exit 2
    fi
done

# shellcheck source=.github/scripts/lib-notice-comment.sh
source "$(cd "$(dirname "$0")" && pwd)/lib-notice-comment.sh"

REPO="$GITHUB_REPOSITORY"
RUN_ID="$GITHUB_RUN_ID"
NOW_EPOCH="${NOW_EPOCH:-$(date -u +%s)}"
# 窓の始まりの算術展開に入るため、API に問い合わせる前に形を確かめる。
# 先頭の 0 は8進数として読まれ、桁が多すぎると64ビットを溢れる。
if ! [[ "$NOW_EPOCH" =~ ^[1-9][0-9]{0,11}$ ]]; then
    echo "::error::NOW_EPOCH はエポック秒(先頭0なし・12桁まで)で指定してください: ${NOW_EPOCH}"
    exit 2
fi
SUMMARY="${GITHUB_STEP_SUMMARY:-/dev/null}"
AUDIT_WORKFLOW_FILE="audit-weekly.yaml"
# 検索の API が返す結果の上限。超えた分は読めない
SEARCH_LIMIT=1000

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
: >"$TMP/rows.tsv"
: >"$TMP/unreadable.md"

# 窓を決める前の失敗の報告と終了。同じ実行の再実行で解消しうる。
report_undecidable() {
    {
        echo "### :warning: 72時間待たずに入れた版の記録を読めませんでした(判定不能)"
        echo ""
        echo "$1"
        echo ""
        echo "**成功に倒さず赤にしています。**"
        echo "失敗したこの実行を re-run(同じ実行の再実行)してください。"
        echo "新しく手動で実行(workflow_dispatch)すると、窓の始まりが前へ進み、"
        echo "読めなかった期間の版が一覧から漏れます。"
        echo ""
    } >>"$SUMMARY"
    echo "72時間待たずに入れた版の記録を読めませんでした(判定不能): $1" >&2
    exit 2
}

# 使い方: unreadable <PR番号> <理由>。読めなかった PR を控え、ほかの PR を読み続ける
unreadable() {
    printf -- '- #%s: %s\n' "$1" "$2" >>"$TMP/unreadable.md"
    echo "::error::#$1 の記録を読めませんでした: $2" >&2
}

# 使い方: decode <base64>。記録の JSON を標準出力に出す。base64 か JSON が壊れていれば 1
decode() {
    local raw
    raw=$(printf '%s' "$1" | base64 -d 2>/dev/null) || return 1
    printf '%s' "$raw" | jq -c . 2>/dev/null
}

# 表のマスに入れる jq の関数。| は表の区切りにならないように \| にし、改行とタブは空白にする。
# 名前は @ で始まるもの(npm のスコープ付きの名前)が Issue で誰かへの呼びかけに
# ならないように、コードの書式にする。
# 名前の中のバッククォートは、コードの書式が途中で閉じないように ' にする。
# バッククォートは \u0060、' は \u0027 と jq の書き方で書く(シェルの変数に入れる
# 文字列にバッククォートを書くと、shellcheck がコマンドの置き換えの書き誤りとして指摘する)。
# 並べ替えの列とはタブで区切る。@tsv は \ を \\ にして \| を壊すので使わない。
JQ_CELLS='
    def cell: tostring | gsub("[\r\n\t]+"; " ") | gsub("\\|"; "\\|");
    def code: "\u0060" + (cell | gsub("\u0060"; "\u0027")) + "\u0060";'

# --- 窓の決定 ---------------------------------------------------------------
wfruns_json=""
if ! wfruns_json=$(gh api "repos/${REPO}/actions/workflows/${AUDIT_WORKFLOW_FILE}/runs?per_page=100" 2>/dev/null); then
    report_undecidable "週次監査の実行の一覧の API に問い合わせられませんでした。"
fi
prev_created=""
if ! prev_created=$(printf '%s' "$wfruns_json" | jq -er --arg rid "$RUN_ID" '
    if (.workflow_runs | type) == "array"
       and ([.workflow_runs[] | ((.id? | type) == "number") and ((.created_at? | type) == "string")] | all)
    then ([.workflow_runs[] | select((.id | tostring) != $rid)]
          | if length == 0 then "none" else (max_by(.created_at) | .created_at) end)
    else empty end' 2>/dev/null); then
    report_undecidable "週次監査の実行の一覧の API の応答を解釈できませんでした。"
fi
if [ "$prev_created" = "none" ]; then
    boundary_epoch=$((NOW_EPOCH - 7 * 86400))
    boundary=$(date -u -d "@${boundary_epoch}" +%Y-%m-%dT%H:%M:%SZ)
    window_desc="直近7日間(前の回の週次監査の実行が無い)。${boundary} から"
else
    if ! boundary_epoch=$(date -u -d "$prev_created" +%s 2>/dev/null); then
        report_undecidable "前の回の実行の日時を解釈できません: ${prev_created}"
    fi
    boundary="$prev_created"
    window_desc="前の回の週次監査の実行の始まり(${boundary})から"
fi
now_iso=$(date -u -d "@${NOW_EPOCH}" +%Y-%m-%dT%H:%M:%SZ)

# --- 窓の中でマージされた PR の一覧 -------------------------------------------
# 検索は日付の単位で絞るので、窓の始まりより前の同じ日のマージも返る。
# PR ごとに merged_at を読み、窓の中のものだけを残す。
search_json=""
if ! search_json=$(gh api "search/issues?q=repo:${REPO}+is:pr+is:merged+merged:>=${boundary%%T*}&per_page=100" \
    --paginate --slurp 2>/dev/null); then
    report_undecidable "マージされた PR の検索の API に問い合わせられませんでした。"
fi
search_result=""
if ! search_result=$(printf '%s' "$search_json" | jq -ec '
    if type == "array" and length > 0
       and all(.[]; (.total_count | type) == "number" and (.incomplete_results | type) == "boolean"
                    and (.items | type) == "array" and all(.items[]; (.number | type) == "number"))
    then {total: .[0].total_count, incomplete: any(.[]; .incomplete_results),
          numbers: ([.[].items[].number] | unique)}
    else empty end' 2>/dev/null); then
    report_undecidable "マージされた PR の検索の API の応答を解釈できませんでした。"
fi
total=$(jq -r '.total' <<<"$search_result")
if [ "$total" -gt "$SEARCH_LIMIT" ]; then
    report_undecidable "窓の中でマージされた PR が ${total} 件あり、検索の API が返す上限の ${SEARCH_LIMIT} 件を超えるため、すべてを読めません。"
fi
if [ "$(jq -r '.incomplete' <<<"$search_result")" = true ]; then
    report_undecidable "マージされた PR の検索が時間内に終わらず、結果がそろっていません。"
fi
mapfile -t numbers < <(jq -r '.numbers[]' <<<"$search_result")

# --- PR ごとに記録を読む --------------------------------------------------------
for n in "${numbers[@]}"; do
    pr_json=""
    if ! pr_json=$(gh api "repos/${REPO}/pulls/${n}" 2>/dev/null); then
        unreadable "$n" "PR の情報を読めませんでした。"
        continue
    fi
    fields=""
    if ! fields=$(printf '%s' "$pr_json" | jq -ec '
        if (.merged_at | type) == "string" and (.head.sha | type) == "string"
           and ((.body | type) == "string" or .body == null)
        then {merged_at, sha: .head.sha, body: (.body // "")}
        else empty end' 2>/dev/null); then
        unreadable "$n" "PR の情報の形が想定と違います。"
        continue
    fi
    merged_at=$(jq -r '.merged_at' <<<"$fields")
    sha=$(jq -r '.sha' <<<"$fields")
    merged_epoch=""
    if ! merged_epoch=$(date -u -d "$merged_at" +%s 2>/dev/null); then
        unreadable "$n" "マージの日時を解釈できません: ${merged_at}"
        continue
    fi
    if [ "$merged_epoch" -lt "$boundary_epoch" ] || [ "$merged_epoch" -gt "$NOW_EPOCH" ]; then
        continue
    fi
    if [[ ! "$sha" =~ ^([0-9a-f]{40}|[0-9a-f]{64})$ ]]; then
        unreadable "$n" "head が SHA の形ではありません。"
        continue
    fi

    # frontend と backend の版: マージした head の記録のコメントのうち最新のもの
    comments=""
    if ! comments=$(_notice_author_comments "$n"); then
        unreadable "$n" "PR のコメントの一覧を読めませんでした。"
        continue
    fi
    marker="<!-- cooldown-exception-record kind=exception head=${sha} -->"
    data=""
    if ! data=$(printf '%s' "$comments" | jq -r --arg m "$marker" '
        [.[] | select(.body | contains($m))] | sort_by(.at) | last
        | if . == null then "none"
          else ([.body | capture("<!-- cooldown-exception-data data=(?<d>[^ ]*) -->") | .d] | last // "missing")
          end' 2>/dev/null); then
        unreadable "$n" "記録のコメントを解釈できませんでした。"
        continue
    fi
    if [ "$data" = missing ]; then
        unreadable "$n" "記録のコメントに、記録の JSON の行がありません。"
        continue
    fi
    if [ "$data" != none ]; then
        record=""
        if ! record=$(decode "$data"); then
            unreadable "$n" "記録のコメントの記録の JSON が壊れています。"
            continue
        fi
        rows=""
        if ! rows=$(printf '%s' "$record" | jq -er --argjson pr "$n" --arg head "$sha" --arg merged "$merged_at" "$JQ_CELLS"'
            def str: type == "string" and length > 0;
            if .schema == 1 and .pr == $pr and .head == $head
               and (.entries | type == "array" and length > 0)
               and all(.entries[];
                   (.ecosystem | str) and (.name | str) and (.version | str) and (.published_at | str)
                   and (.alerts | type == "array" and length > 0)
                   and all(.alerts[]; (.number | type == "number") and (.ghsa_id | str)
                       and (.severity | str) and (.html_url | str)))
            then .entries[]
                | [$merged, ($pr | tostring),
                   "| \(.name | code)(\(.ecosystem | cell)) | \(.version | code) | \(.published_at | cell) | "
                   + ([.alerts[] | "\u0060#\(.number)\u0060 \(.ghsa_id | cell)(\(.severity | cell)) \(.html_url | cell)"] | join("<br>"))
                   + " |  | #\($pr) | \($merged | cell) |"]
                | join("	")
            else error("記録の JSON の形が違う") end' 2>/dev/null); then
            unreadable "$n" "記録のコメントの記録の JSON の形が違うか、PR の番号か head が合いません。"
            continue
        fi
        printf '%s\n' "$rows" >>"$TMP/rows.tsv"
    fi

    # CI の道具の版: PR の本文の記録。目印の数と読めた記録の数が合わなければ読めなかったとする
    body=$(jq -r '.body' <<<"$fields")
    mapfile -t ci_data < <(printf '%s' "$body" |
        jq -Rrs '[scan("<!-- ci-tool-cooldown-exception data=([^ ]*) -->") | .[0]] | .[]')
    prefixes=$(printf '%s' "$body" | jq -Rrs '[scan("<!-- ci-tool-cooldown-exception")] | length')
    if [ "$prefixes" -ne "${#ci_data[@]}" ]; then
        unreadable "$n" "PR の本文の CI の道具の記録の目印の形が違います。"
        continue
    fi
    ci_ok=true
    ci_rows=""
    for d in "${ci_data[@]}"; do
        ci=""
        if ! ci=$(decode "$d"); then
            ci_ok=false
            break
        fi
        r=""
        if ! r=$(printf '%s' "$ci" | jq -er --argjson pr "$n" --arg merged "$merged_at" "$JQ_CELLS"'
            def str: type == "string" and length > 0;
            if .schema == 1 and (.entries | type == "array" and length > 0)
               and all(.entries[];
                   (.tool | str) and (.version | str) and (.published_at | str) and (.owner_instruction | str)
                   and (.signature | type == "object")
                   and (.signature.result | str) and (.signature.method | str)
                   and (.signature.signer | str) and (.signature.checked_at | str))
            then .entries[]
                | [$merged, ($pr | tostring),
                   "| \(.tool | code)(CI の道具) | \(.version | code) | \(.published_at | cell) | \(.owner_instruction | cell) | "
                   + "\(.signature.result | cell)、\(.signature.method | cell)、\(.signature.signer | code)、\(.signature.checked_at | cell)"
                   + " | #\($pr) | \($merged | cell) |"]
                | join("	")
            else error("記録の JSON の形が違う") end' 2>/dev/null); then
            ci_ok=false
            break
        fi
        ci_rows+="${r}"$'\n'
    done
    if [ "$ci_ok" != true ]; then
        unreadable "$n" "PR の本文の CI の道具の記録の JSON が壊れているか、形が違います。"
        continue
    fi
    printf '%s' "$ci_rows" >>"$TMP/rows.tsv"
done

# --- 報告 ---------------------------------------------------------------------
# 行はマージの日時と PR の番号の順に並べる。同じ PR の中は記録の順のまま残す。
rows_count=$(grep -c . "$TMP/rows.tsv" || true)
if [ "$rows_count" -gt 0 ]; then
    {
        echo "### 72時間待たずに入れた版"
        echo ""
        echo "対象の期間: ${window_desc} ${now_iso} までにマージされた PR"
        echo ""
        echo "| 部品か道具の名前 | 版 | 公開日時 | 理由 | 署名を確かめた結果 | PR | マージの日時 |"
        echo "|---|---|---|---|---|---|---|"
        grep . "$TMP/rows.tsv" | sort -s -t $'\t' -k1,1 -k2,2n | cut -f3-
        echo ""
    } >>"$SUMMARY"
fi
if [ -s "$TMP/unreadable.md" ]; then
    {
        echo "### :warning: 72時間待たずに入れた版の記録を読めませんでした(判定不能)"
        echo ""
        echo "対象の期間: ${window_desc} ${now_iso} までにマージされた PR"
        echo ""
        cat "$TMP/unreadable.md"
        echo ""
        echo "**成功に倒さず赤にしています。**"
        echo "失敗したこの実行を re-run(同じ実行の再実行)してください。"
        echo "繰り返し読めないときは、上の PR の記録を人間が確かめてください。"
        echo ""
    } >>"$SUMMARY"
    exit 2
fi
if [ "$rows_count" -gt 0 ]; then
    exit 1
fi
exit 0
