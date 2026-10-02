#!/usr/bin/env bash
# =====================================================================
# マージ済み PR に対応する Issue を閉じる(close-linked-issues から実行)
#
# 何をするか:
#   PR 1件について、本文の `Closes #<番号>` に書かれた Issue が開いたままなら閉じ、
#   どの PR のマージで閉じたかを Issue にコメントで記録する。
#   閉じられなかったときと、`Refs: #<番号>` にだけ書かれた Issue が開いたままのときは、
#   その Issue に知らせのコメントを1回だけ付けて、所有者に知らせる。
#   閉じた Issue が、ほかの Issue から分けた Issue(サブIssue)で、親の子がすべて閉じたら、
#   親も閉じて記録する。閉じた親にさらに親があれば、同じことを上へ繰り返す。
#   親を照会できない・閉じられないときは、親に知らせのコメントを1回だけ付けて、所有者に知らせる。
#
# なぜ必要か:
#   Issue が閉じるかどうかは、GitHub が PR 本文の `Closes` を紐づけるかどうかに任されている。
#   紐づかなかったとき(#450 のマージ後も #448 が開いたままだった)に、気づく手段が無い。
#   GitHub の紐づけの成否に依らず、本文に書かれた Issue を閉じる。
#   `Refs:` だけの Issue は、続きの作業が残っていることがあるため閉じない。ただし `Closes` の
#   書き忘れとは見分けられないので、開いたままであることを所有者に知らせる。
#
# 判定(Issue ごと。Closes の Issue、Refs だけの Issue の順):
#   いま閉じている                               → untouched(閉じた時期を問わず、何も書き込まない)
#   開いていて、PR のマージ日時以降に閉じた記録がある → untouched(マージの後に閉じられ、開き直された)
#   開いていて、上のどちらでもない
#     Closes の Issue      → 閉じて記録する(closed)。
#                            閉じる操作が失敗したら、知らせを付ける(close-failed)
#     Refs だけの Issue    → 閉じずに知らせを付ける(refs-only-noticed)。
#                            この PR についての知らせが既にあれば、何も書き込まない(untouched)
#   番号が存在しない、または PR を指している     → not-an-issue(何も書き込まず、ログに残す)
#   PR がマージされていない、または base が main でないときは、何もせず終了コード 0 で終える。
#
# 親の判定(上の書き込みをすべて終えた後。親ごと):
#   対象は、Closes の Issue のうち closed になったものと、照会の時点で閉じていた untouched のもの
#   (Refs だけの Issue と、開き直された Closes の Issue は対象にしない)の親。
#   同じ親を持つ Issue が複数あれば、親は1回だけ判定する(記録には並びの最後の Issue を書く)。
#   親は書き込みの後に照会し直す(閉じた子が子の数に入った状態で判定する)。
#   親が別のリポジトリにある                             → 何もしない(照会も書き込みも知らせもせず、上もたどらない。
#                                                           このリポジトリの同じ番号の Issue・PR に触れないため)
#   親がいま閉じている                                   → 何もしない
#   親が開いていて、PR のマージ日時以降に閉じた記録がある → 何もしない(開き直された親)
#   親が開いていて、子が1件以上あり、子がすべて閉じている → 閉じて記録する(parent-closed)。
#                                                           閉じた親の親についても同じ判定を行う(最大8段)
#   親が開いていて、閉じていない子がある、または子が0件   → 何もしない
#   親を照会できない、応答の形が想定と違う、閉じられない  → 親に知らせを付ける(parent-close-failed。その親より上はたどらない)
#
# 知らせ(Issue へのコメント。所有者へのメンションを付ける):
#   close-failed  目印 <!-- issue-close-notice pr=<PR番号> kind=close-failed -->
#   refs-only     目印 <!-- issue-close-notice pr=<PR番号> kind=refs-only -->
#   parent-close-failed  目印 <!-- issue-close-notice pr=<PR番号> kind=parent-close-failed -->
#                 親の Issue に付ける。文面は失敗の種類で書き分ける。閉じる操作の失敗(子がすべて閉じたと
#                 確かめた後)では「この Issue から分けた Issue はすべて閉じましたが、この Issue を自動で
#                 閉じられませんでした。」と書く。照会できない・応答の形が想定と違うときは、子がすべて閉じたかを
#                 確かめていないため、そう言い切らず、確かめられなかったことと、すべて閉じていれば手で閉じてほしいことを書く。
#                 どちらの種類も同じ目印で、先に付けた知らせがあれば重ねない。
#   同じ目印のコメントが既にあれば重ねない(lib-notice-comment.sh の notice_post)。
#   Issue が閉じたあとの「解消」のコメントは付けない。知らせの場所である Issue 自身が
#   閉じた状態になり、それで分かるため。
#
# なぜ閉じる操作の失敗(親の照会と親を閉じる操作の失敗を含む)を終了コード 0 にするか:
#   所有者への経路は知らせのコメントで、ワークフローの赤は所有者に届かない。
#   知らせを付けられたら役目は果たせているので 0、付けられないときだけ 1(赤)にする。
#
# 本文の読み取り規則:
#   大文字小文字を区別せず `closes`(`:` があってもよい)に続く空白と `#<番号>` をすべて拾う。
#   `refs` も同じ規則で拾う。重複は1回にし、両方にある番号は Closes として扱う。
#   `Fixes` などほかの語と `owner/repo#<番号>` の形は扱わない(出荷手順が定めているのは
#   `Closes` と `Refs` だけ)。`Refs: N/A` は番号が無いため対象にならない。
#   本文は番号の抽出だけに使う(jq の中で読み、シェルのコマンドとして評価しない)。
#   番号は10桁まで拾うが、GraphQL の Int(32ビット)に収まらない番号は照会できないため、
#   照会せずに not-an-issue とする(その番号のせいで、同じ PR のほかの Issue を止めない)。
#
# 書き込みの範囲:
#   Issue のクローズ(gh issue close)、記録のコメント(gh issue comment)、知らせのコメントだけ。
#   PR・ラベル・担当者・Issue の本文には書き込まない。
#   書き込む前に、Closes と Refs だけの Issue をすべて照会する(Refs だけの Issue は、知らせが
#   既にあるかも確かめる)。1つでも照会できなければ、どの Issue にも書き込まない。
#   親の照会だけは書き込みの後に行う(子を閉じる前に照会すると、閉じる子が子の数に入らないため)。
#
# まれに記録が2つ付くこと:
#   マージのイベントのジョブと定期の見直しのジョブが、同じ Issue を同時に「開いている」と読むと、
#   両方が閉じて記録のコメントが2つ付く。同じ内容のコメントが重なるだけで害は小さいため、防がない。
#   同じ競合で、知らせ(close-failed・refs-only・parent-close-failed)も2つ付きうる(どちらも「まだ無い」と読むため)。
#   定期の見直しは直近5分のマージを除くので、実際に重なることはまれで、これも防がない。
#
# 定期の見直し(--sweep):
#   マージのイベントで起動したジョブが動かなかった・途中で失敗したときに備え、マージ済みの PR を
#   まとめて見直す。main へマージされた PR のうち、マージが現在時刻の7日前から5分前まで
#   (どちらの端もちょうどを含む)のものを一覧し、マージの古い順に1件ずつ <PR番号> の形と同じ処理を行う。
#   - 直近5分を除くのは、マージのイベントで起動したジョブと同じ PR を同時に扱わないため。
#   - 一覧は `gh pr list --search "merged:>=<8日前の日付>"` で粗く絞り(最大200件)、7日と5分の境界は
#     一覧の mergedAt をこのスクリプトが秒の単位で判定する(検索条件だけに頼らない)。
#     200件に達したときは古い側が漏れているおそれを標準エラーに出す(7日間で200件を超えるマージは想定しない)。
#   - 1件ごとの処理は、このスクリプト自身を <PR番号> の形で起動して行う(判定を二重に持たない)。
#     1件ごとに時間の上限(120秒)を付け、時間切れはその PR の失敗として数える。
#   - 1件が失敗しても残りを続け、失敗が1件でもあれば終了コード 1。
#     一覧を取れないとき・応答の形が想定と違うときは、どの PR も処理せず終了コード 1。
#
# テスト: .github/scripts/tests/test-close-linked-issues.sh
# 使い方: close-linked-issues.sh <PR番号>
#         close-linked-issues.sh --sweep
#   環境変数 GH_TOKEN / GITHUB_REPOSITORY / GITHUB_REPOSITORY_OWNER(必須)
#   環境変数 NOTICE_AUTHOR(任意。知らせの作成者の名前。lib-notice-comment.sh を参照)
#   環境変数 NOW_EPOCH(任意。--sweep だけが使う。テスト用の時刻固定)
#   環境変数 SWEEP_PR_TIMEOUT(任意。--sweep だけが使う。1件ごとの時間の上限の秒数。テスト用。既定は 120)
# 出力: 標準出力に、Issue ごとに次の1行だけを出す。経過と理由は標準エラーに出す。
#   <PR番号> の形: issue=<番号> result=<untouched|closed|close-failed|refs-only-noticed|not-an-issue>
#                  親を閉じたときは、続けて issue=<親の番号> result=parent-closed
#                  親を閉じられず知らせを付けたときは、続けて issue=<親の番号> result=parent-close-failed
#   --sweep      : pr=<PR番号> issue=<番号> result=<同上>
# 終了コード: 0 = すべての Issue について判定と、必要な操作・知らせを終えた
#                 (close-failed・parent-close-failed でも、知らせを付けられたら 0)
#             1 = PR・Issue を照会できない、応答の形が想定と違う、
#                 クローズの記録または知らせを付けられない(親の記録と親への知らせを含む)、
#                 引数・環境変数の不足。
#                 --sweep では、一覧を取れない、または1件でも PR の処理が失敗・時間切れになった
# =====================================================================
set -euo pipefail

fail() {
    echo "中断しました: $1" >&2
    exit 1
}

# shellcheck source=.github/scripts/lib-notice-comment.sh
if ! SELF_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd) ||
    ! source "${SELF_DIR}/lib-notice-comment.sh"; then
    fail "lib-notice-comment.sh を読み込めません"
fi

USAGE="使い方: close-linked-issues.sh <PR番号> | --sweep"
[ $# -eq 1 ] || fail "$USAGE"
PR="$1"
[[ "$PR" =~ ^[1-9][0-9]*$ ]] || [ "$PR" = "--sweep" ] || fail "$USAGE"
REPO="${GITHUB_REPOSITORY:-}"
[[ "$REPO" =~ ^[^/]+/[^/]+$ ]] || fail "GITHUB_REPOSITORY がありません(<所有者>/<リポジトリ> の形)"
[ -n "${GITHUB_REPOSITORY_OWNER:-}" ] || fail "GITHUB_REPOSITORY_OWNER がありません"
[ -n "${GH_TOKEN:-}" ] || fail "GH_TOKEN がありません"
REPO_OWNER="${REPO%%/*}"
REPO_NAME="${REPO#*/}"

TMP=$(mktemp -d) || fail "作業用のディレクトリを作れません"
trap 'rm -rf "$TMP"' EXIT

# --- 定期の見直し(--sweep)----------------------------------------------------------
if [ "$PR" = "--sweep" ]; then
    SWEEP_MAX_AGE=$((7 * 24 * 60 * 60)) # マージからこの秒数を超えた PR は見直さない
    SWEEP_MIN_AGE=$((5 * 60))           # マージからこの秒数に満たない PR は見直さない
    SWEEP_LIMIT=200
    NOW_EPOCH="${NOW_EPOCH:-$(date -u +%s)}"
    [[ "$NOW_EPOCH" =~ ^(0|[1-9][0-9]*)$ ]] || fail "NOW_EPOCH が数字ではありません"
    SWEEP_PR_TIMEOUT="${SWEEP_PR_TIMEOUT:-120}"
    [[ "$SWEEP_PR_TIMEOUT" =~ ^[1-9][0-9]*$ ]] || fail "SWEEP_PR_TIMEOUT が 1 以上の整数ではありません"

    # 検索は日付の単位でしか絞れないため、7日前より1日広く取る。境界は下の jq が秒の単位で判定する。
    if ! since=$(jq -n -r --argjson t "$((NOW_EPOCH - SWEEP_MAX_AGE - 24 * 60 * 60))" '$t | strftime("%Y-%m-%d")'); then
        fail "見直しの対象の日付を計算できません"
    fi
    if ! gh pr list --repo "$REPO" --state merged --base main --search "merged:>=${since}" \
        --json number,mergedAt --limit "$SWEEP_LIMIT" >"$TMP/list.json" 2>"$TMP/list.err"; then
        cat "$TMP/list.err" >&2
        fail "マージ済みの PR の一覧を取れません"
    fi
    # 応答は「配列がちょうど1つ」であることを確かめる(-s で応答の全体を読む)。
    # gh が成功で終わっても、応答が空(0バイト、改行だけ)や JSON が2つ並んだ形なら、
    # 「対象が0件」とはみなさずに中断する(見直しをしないままジョブを緑にしない)。
    # 要素を1つでも読めなければ、対象を選ばずに中断する(読めた分だけを処理しない)。
    # 対象はマージの古い順に並べる(見直しの期間から外れるのが近いものを先に処理する)。
    # 件数と対象は、確かめ終えた1つの結果($TMP/list.one.json)にまとめ、以降はそこから読む。
    if ! jq -c -s --argjson now "$NOW_EPOCH" --argjson min "$SWEEP_MIN_AGE" --argjson max "$SWEEP_MAX_AGE" '
        if length == 1 then .[0] else error("形が想定と違う") end
        | if type == "array"
            and all(.[]; type == "object"
                and (.number | type) == "number" and .number >= 1 and .number == (.number | floor)
                and (.mergedAt | type) == "string")
          then . else error("形が想定と違う") end
        | {listed: length,
           targets: (map({number, age: ($now - (.mergedAt | fromdateiso8601 | floor))})
                     | map(select(.age >= $min and .age <= $max))
                     | sort_by(-.age, .number)
                     | map(.number))}' "$TMP/list.json" >"$TMP/list.one.json" 2>/dev/null; then
        fail "マージ済みの PR の一覧の応答の形が想定と違います"
    fi
    listed=$(jq -r '.listed' "$TMP/list.one.json") || fail "マージ済みの PR の一覧の件数を読めません"
    [[ "$listed" =~ ^(0|[1-9][0-9]*)$ ]] || fail "マージ済みの PR の一覧の件数を読めません"
    targets=$(jq -r '.targets[]' "$TMP/list.one.json") || fail "マージ済みの PR の一覧から見直しの対象を読めません"
    if [ -n "$targets" ] && ! [[ "$targets" =~ ^[1-9][0-9]*($'\n'[1-9][0-9]*)*$ ]]; then
        fail "マージ済みの PR の一覧から見直しの対象を読めません"
    fi
    if [ "$listed" -ge "$SWEEP_LIMIT" ]; then
        echo "一覧が上限の${SWEEP_LIMIT}件に達しました。古い側の PR が見直しから漏れているおそれがあります。" >&2
    fi
    SWEEP_PRS=()
    if [ -n "$targets" ]; then
        mapfile -t SWEEP_PRS <<<"$targets"
    fi
    echo "見直しの対象: ${#SWEEP_PRS[@]}件(一覧 ${listed}件のうち、マージが7日前から5分前までのもの)" >&2

    SELF="${SELF_DIR}/${BASH_SOURCE[0]##*/}"
    SWEEP_FAILED=0
    for pr in "${SWEEP_PRS[@]+"${SWEEP_PRS[@]}"}"; do
        echo "--- PR #${pr} を見直します ---" >&2
        # 子の作業用のディレクトリをこの TMP の下に作らせ、時間切れで子が片付けられなくても残さない。
        # 時間切れのときは TERM を送り、10秒たっても終わらなければ KILL を送る。
        pr_rc=0
        TMPDIR="$TMP" timeout -k 10 "$SWEEP_PR_TIMEOUT" bash "$SELF" "$pr" >"$TMP/sweep-out.txt" || pr_rc=$?
        # 途中で失敗・時間切れになっても、そこまでに終えた Issue の結果は出す。
        sed "s/^/pr=${pr} /" "$TMP/sweep-out.txt"
        case "$pr_rc" in
        0) ;;
        124 | 137)
            echo "PR #${pr} の見直しが時間の上限(${SWEEP_PR_TIMEOUT}秒)を超えました。残りの PR を続けます。" >&2
            SWEEP_FAILED=$((SWEEP_FAILED + 1))
            ;;
        *)
            echo "PR #${pr} の見直しに失敗しました(終了コード ${pr_rc})。残りの PR を続けます。" >&2
            SWEEP_FAILED=$((SWEEP_FAILED + 1))
            ;;
        esac
    done
    if [ "$SWEEP_FAILED" -gt 0 ]; then
        echo "見直しを終えました。${SWEEP_FAILED}件の PR で失敗しました。" >&2
        exit 1
    fi
    echo "見直しを終えました。失敗はありません。" >&2
    exit 0
fi

# shellcheck disable=SC2016 # $owner などは GraphQL の変数で、シェルの変数ではない
PR_QUERY='query($owner: String!, $name: String!, $number: Int!) {
  repository(owner: $owner, name: $name) {
    pullRequest(number: $number) { merged mergedAt baseRefName body }
  }
}'
# 閉じた記録は新しい側から100件を読む。マージ日時以降の記録があるかを見るには、新しい側で足りる。
# 子の数(subIssuesSummary)と親の番号(parent)は、子がすべて閉じた親を閉じるために読む。
# 親の照会にも同じクエリを使う。子が無ければ total と completed は 0、親が無ければ parent は null で返る。
# サブIssueの親は別のリポジトリにあることがあるため、親のリポジトリ(nameWithOwner)も読む。
# 番号だけでこのリポジトリを引くと、同じ番号の無関係な Issue・PR に書き込むおそれがある。
# shellcheck disable=SC2016
ISSUE_QUERY='query($owner: String!, $name: String!, $number: Int!) {
  repository(owner: $owner, name: $name) {
    issue(number: $number) {
      state
      timelineItems(itemTypes: [CLOSED_EVENT], last: 100) {
        nodes { ... on ClosedEvent { createdAt } }
      }
      subIssuesSummary { total completed }
      parent { number repository { nameWithOwner } }
    }
  }
}'
# Issue の応答(.data.repository.issue)から親の番号を取り出す jq の関数(--arg repo に <所有者>/<リポジトリ> を渡す)。
# 親が無ければ "-"、親が別のリポジトリにあれば "other-repo" を返す(どちらも親を扱わない)。
# リポジトリの名前は GitHub では大文字小文字を区別しないため、小文字にそろえて比べる。
# parent の欄が無い・番号が正の整数でない・親のリポジトリの名前が文字列でないときは、
# 形が想定と違うものとして失敗させる。
# shellcheck disable=SC2016 # $repo は jq の変数で、シェルの変数ではない
JQ_PARENT_NUMBER='def parent_number:
    if has("parent") | not then error("形が想定と違う")
    elif .parent == null then "-"
    elif (.parent | type) == "object" and (.parent.number | type) == "number"
        and .parent.number >= 1 and .parent.number == (.parent.number | floor)
        and (.parent.repository | type) == "object"
        and (.parent.repository.nameWithOwner | type) == "string"
    then (if (.parent.repository.nameWithOwner | ascii_downcase) == ($repo | ascii_downcase)
          then .parent.number | tostring else "other-repo" end)
    else error("形が想定と違う") end;'

# 使い方: graphql <番号> <クエリ> <応答の保存先> <エラーの保存先>
graphql() {
    gh api graphql -F "number=$1" -f "owner=${REPO_OWNER}" -f "name=${REPO_NAME}" -f "query=$2" >"$3" 2>"$4"
}

# --- PR の照会 --------------------------------------------------------------------
if ! graphql "$PR" "$PR_QUERY" "$TMP/pr.json" "$TMP/pr.err"; then
    cat "$TMP/pr.err" >&2
    fail "PR #${PR} を照会できません"
fi
# 応答は「JSON がちょうど1つ」であることを確かめる(-s で応答の全体を読む)。
# gh が成功で終わっても、応答が空(0バイト、改行だけ)や JSON が2つ並んだ形なら、
# 「マージされていない」とはみなさずに中断する(Issue を閉じないままジョブを緑にしない)。
# マージ済みなら mergedAt を日時として読めること(読めなければ jq が失敗する)までを確かめる。
# 確かめ終えた1つの応答から、以降で使う値(マージ日時・base・本文)を $TMP/pr.one.json にまとめ、
# base と本文もそこから読む(応答を読み直して、別々に判定しない)。
# merged には、マージ済みならマージ日時(秒)、マージされていなければ "not-merged" を明示して入れる。
if ! jq -c -s '
    if length == 1 then .[0] else error("形が想定と違う") end
    | .data.repository.pullRequest
    | if type == "object"
        and (.merged | type) == "boolean"
        and (.baseRefName | type) == "string"
        and (.body | type) == "string"
      then . else error("形が想定と違う") end
    | {merged: (if .merged then (.mergedAt | fromdateiso8601 | floor) else "not-merged" end),
       base: .baseRefName,
       body: .body}' "$TMP/pr.json" >"$TMP/pr.one.json" 2>/dev/null; then
    fail "PR #${PR} の応答の形が想定と違います"
fi
MERGED_EPOCH=$(jq -r '.merged' "$TMP/pr.one.json") || fail "PR #${PR} のマージ日時を読めません"
# 「マージされていない」は、上の jq が明示して出した値でだけ判定する。空の出力は失敗として扱う。
if [ "$MERGED_EPOCH" = "not-merged" ]; then
    echo "PR #${PR} はマージされていないため、何もしません。" >&2
    exit 0
fi
[[ "$MERGED_EPOCH" =~ ^[0-9]+$ ]] || fail "PR #${PR} のマージ日時を読めません"
BASE=$(jq -r '.base' "$TMP/pr.one.json") || fail "PR #${PR} の base を読めません"
[ -n "$BASE" ] || fail "PR #${PR} の base を読めません"
if [ "$BASE" != "main" ]; then
    echo "PR #${PR} は main 向けではないため、何もしません。" >&2
    exit 0
fi

# --- 本文の読み取り ----------------------------------------------------------------
# 使い方: parse_numbers <closes|refs>
# 本文から、語に続く `#<番号>` を小さい順に、重複なく、1行に1つずつ出す。
# 語の前と番号の後ろに英数字が続くもの(encloses、#13abc)は拾わない。
# 語と `#` の間が空白でないもの(owner/repo#<番号>、改行)も拾わない。
parse_numbers() {
    jq -r --arg word "$1" '
        .body
        | [match("(?<![A-Za-z0-9_])" + $word + ":?[ \\t]+#([1-9][0-9]{0,9})(?![A-Za-z0-9_])"; "gi")
           | .captures[0].string | tonumber]
        | unique | .[]' "$TMP/pr.one.json"
}
closes_text=$(parse_numbers closes) || fail "PR #${PR} の本文から Closes の番号を読み取れません"
refs_text=$(parse_numbers refs) || fail "PR #${PR} の本文から Refs の番号を読み取れません"
CLOSES=()
REFS_ONLY=()
if [ -n "$closes_text" ]; then
    mapfile -t CLOSES <<<"$closes_text"
fi
if [ -n "$refs_text" ]; then
    # 両方にある番号は Closes として扱う
    while IFS= read -r n; do
        if ! printf '%s\n' "${CLOSES[@]+"${CLOSES[@]}"}" | grep -qx -- "$n"; then
            REFS_ONLY+=("$n")
        fi
    done <<<"$refs_text"
fi

# 使い方: numbers_for_log <番号> ...
numbers_for_log() {
    if [ $# -eq 0 ]; then
        printf 'なし'
    else
        printf '#%s' "$1"
        shift
        [ $# -eq 0 ] || printf ' #%s' "$@"
    fi
}
echo "PR #${PR} の Closes の Issue: $(numbers_for_log "${CLOSES[@]+"${CLOSES[@]}"}")" >&2
echo "PR #${PR} の Refs だけの Issue: $(numbers_for_log "${REFS_ONLY[@]+"${REFS_ONLY[@]}"}")" >&2

# --- 知らせ ------------------------------------------------------------------------
CLOSE_FAILED_MARKER="<!-- issue-close-notice pr=${PR} kind=close-failed -->"
REFS_ONLY_MARKER="<!-- issue-close-notice pr=${PR} kind=refs-only -->"
PARENT_CLOSE_FAILED_MARKER="<!-- issue-close-notice pr=${PR} kind=parent-close-failed -->"

# 使い方: notice_exists <番号> <目印>
# 番号の Issue に、目印を含む知らせが既にあるかを確かめる。
# notice_post は「付けた」と「既にあった」を同じ戻り値で返すため、Refs だけの Issue の結果
# (refs-only-noticed か untouched か)を決めるには、付ける前にここで見分ける。
# notice_post と同じ一覧の読み方(知らせの作成者が書いたコメントだけを数える)を使う。
# 0 = 既にある / 1 = 無い / 2 = 確かめられない
notice_exists() {
    local listed found
    if ! listed=$(_notice_author_comments "$1"); then
        return 2
    fi
    if ! found=$(printf '%s' "$listed" | jq -r --arg m "$2" 'any(.[]; .body | contains($m))' 2>/dev/null); then
        return 2
    fi
    if [ "$found" = "true" ]; then
        return 0
    fi
    return 1
}

# --- Issue の判定(書き込む前に、すべて照会する)--------------------------------------
# NUMBERS に Closes の Issue、Refs だけの Issue の順で番号を、KINDS に同じ並びで closes / refs を入れる。
# 結果は DECISIONS に、同じ並びで close / notice / untouched / not-an-issue を入れる。
# 照会の時点の状態(OPEN / CLOSED、照会しなければ -)を STATES に、親の番号(無ければ -、別のリポジトリなら other-repo)を PARENTS に入れる。
NUMBERS=()
KINDS=()
for n in "${CLOSES[@]+"${CLOSES[@]}"}"; do
    NUMBERS+=("$n")
    KINDS+=(closes)
done
for n in "${REFS_ONLY[@]+"${REFS_ONLY[@]}"}"; do
    NUMBERS+=("$n")
    KINDS+=(refs)
done
# GraphQL の Int は 32 ビットで、これを超える番号は照会そのものが失敗する。
MAX_NUMBER=2147483647
DECISIONS=()
STATES=()
PARENTS=()
i=0
for n in "${NUMBERS[@]+"${NUMBERS[@]}"}"; do
    kind="${KINDS[$i]}"
    i=$((i + 1))
    state="-"
    parent="-"
    if [ "$n" -gt "$MAX_NUMBER" ]; then
        DECISIONS+=("not-an-issue")
        STATES+=("$state")
        PARENTS+=("$parent")
        continue
    fi
    if graphql "$n" "$ISSUE_QUERY" "$TMP/issue.json" "$TMP/issue.err"; then
        # 応答は「JSON がちょうど1つ」であることを確かめる(PR の照会と同じ。空・2つ並んだ形は中断する)。
        # 閉じた記録の日時を1つでも読めなければ、閉じる側・知らせる側に倒さず中断する。
        # 判定・状態・親の番号を、空白区切りの1行で出す。
        if ! judged=$(jq -r -s --argjson merged "$MERGED_EPOCH" --arg repo "$REPO" "$JQ_PARENT_NUMBER"'
            if length == 1 then .[0] else error("形が想定と違う") end
            | .data.repository.issue
            | if type == "object" and (.timelineItems.nodes | type) == "array"
              then . else error("形が想定と違う") end
            | (.timelineItems.nodes | map(.createdAt | fromdateiso8601)) as $closed
            | parent_number as $parent
            | (if .state == "CLOSED" then "untouched"
               elif .state == "OPEN" then
                 (if any($closed[]; . >= $merged) then "untouched" else "close" end)
               else error("state が想定と違う") end) as $decision
            | "\($decision) \(.state) \($parent)"' "$TMP/issue.json" 2>/dev/null); then
            fail "Issue #${n} の応答の形が想定と違います"
        fi
        [[ "$judged" =~ ^(close|untouched)\ (OPEN|CLOSED)\ (-|other-repo|[1-9][0-9]*)$ ]] ||
            fail "Issue #${n} の判定を読めません"
        decision="${BASH_REMATCH[1]}"
        state="${BASH_REMATCH[2]}"
        parent="${BASH_REMATCH[3]}"
        # Refs だけの Issue は閉じない。開いたままなら、知らせがまだ無いときだけ知らせる。
        if [ "$kind" = "refs" ] && [ "$decision" = "close" ]; then
            exists=0
            notice_exists "$n" "$REFS_ONLY_MARKER" || exists=$?
            case "$exists" in
            0) decision="untouched" ;;
            1) decision="notice" ;;
            *) fail "Issue #${n} に知らせが既にあるかを確かめられません" ;;
            esac
        fi
    else
        # 番号が存在しない、または PR を指しているとき、GraphQL は errors に NOT_FOUND
        # (path は repository.issue)だけを持つ応答を返し、gh は失敗で終わる。
        # それ以外の失敗(応答が「JSON がちょうど1つ」でない場合を含む)は、照会できなかったものとして中断する。
        if jq -e -s '
            length == 1
            and (.[0]
                | (.data.repository | type) == "object" and .data.repository.issue == null
                  and (.errors | type) == "array" and (.errors | length) > 0
                  and all(.errors[]; .type == "NOT_FOUND" and .path == ["repository", "issue"]))' \
            "$TMP/issue.json" >/dev/null 2>&1; then
            decision="not-an-issue"
        else
            cat "$TMP/issue.err" >&2
            fail "Issue #${n} を照会できません"
        fi
    fi
    case "$decision" in
    close | notice | untouched | not-an-issue) DECISIONS+=("$decision") ;;
    *) fail "Issue #${n} の判定を読めません" ;;
    esac
    STATES+=("$state")
    PARENTS+=("$parent")
done

# --- クローズ・記録・知らせ ----------------------------------------------------------
# 1件が失敗しても残りの Issue を続け、失敗が1件でもあれば終了コード 1 で終える。
# 親を判定する対象(closed になった Closes の Issue と、照会の時点で閉じていた Closes の Issue)の
# 並びの位置を CLOSED_CHILDREN に入れる。
RC=0
CLOSED_CHILDREN=()
i=0
for n in "${NUMBERS[@]+"${NUMBERS[@]}"}"; do
    decision="${DECISIONS[$i]}"
    i=$((i + 1))
    case "$decision" in
    not-an-issue)
        echo "#${n} は存在しないか、PR を指しています。何も書き込みません。" >&2
        printf 'issue=%s result=not-an-issue\n' "$n"
        ;;
    untouched)
        echo "Issue #${n} は閉じているか、PR #${PR} のマージの後に一度閉じられているか、知らせが既にあります。何も書き込みません。" >&2
        printf 'issue=%s result=untouched\n' "$n"
        if [ "${KINDS[$((i - 1))]}" = "closes" ] && [ "${STATES[$((i - 1))]}" = "CLOSED" ]; then
            CLOSED_CHILDREN+=("$((i - 1))")
        fi
        ;;
    notice)
        {
            echo "PR #${PR} はマージされましたが、この Issue(#${n})は開いたままにしています。"
            echo ""
            echo "PR の本文にこの Issue の番号は書かれていますが、\`Closes #${n}\` という書き方ではなかったため、自動では閉じていません。"
            echo ""
            echo "**してほしいこと**"
            echo "- この Issue の作業がすべて終わっていれば、この Issue を手で閉じてください。"
            echo "- 続きの作業が残っていれば、何もしなくて大丈夫です。"
        } >"$TMP/notice.md"
        if ! notice_post "$n" "$REFS_ONLY_MARKER" "$TMP/notice.md" yes; then
            echo "Issue #${n} に知らせのコメントを付けられません(PR #${PR} の Refs だけの Issue)。" >&2
            RC=1
            continue
        fi
        printf 'issue=%s result=refs-only-noticed\n' "$n"
        ;;
    close)
        if ! gh issue close "$n" --repo "$REPO" >&2; then
            echo "Issue #${n} を閉じられません(PR #${PR} のマージに対応する Issue)。知らせを付けます。" >&2
            {
                echo "PR #${PR} はマージされましたが、この Issue(#${n})を自動で閉じられませんでした。"
                echo ""
                echo "**してほしいこと**"
                echo "- この Issue を手で閉じてください。"
            } >"$TMP/notice.md"
            # 同じ知らせが既にあれば notice_post は重ねない(2度目以降の実行でも 0 を返す)。
            if ! notice_post "$n" "$CLOSE_FAILED_MARKER" "$TMP/notice.md" yes; then
                echo "Issue #${n} に知らせのコメントを付けられません(閉じられなかったことを所有者に知らせられません)。" >&2
                RC=1
                continue
            fi
            printf 'issue=%s result=close-failed\n' "$n"
            continue
        fi
        {
            echo "PR #${PR} のマージにより閉じました。"
            echo ""
            echo "PR の本文に \`Closes #${n}\` と書かれていますが、マージの後も開いたままだったため、自動で閉じています。"
        } >"$TMP/record.md"
        if ! gh issue comment "$n" --repo "$REPO" --body-file "$TMP/record.md" >&2; then
            echo "Issue #${n} に記録のコメントを付けられません(Issue は閉じました)。" >&2
            RC=1
            continue
        fi
        printf 'issue=%s result=closed\n' "$n"
        CLOSED_CHILDREN+=("$((i - 1))")
        ;;
    esac
done

# --- 親の Issue を閉じる(書き込みの後に動く)----------------------------------------
# 親を閉じた Issue の親を、さらにたどる段の数の上限
MAX_PARENT_DEPTH=8
# 判定する親の番号を、最初に現れた順に PARENT_ORDER に、記録に書く子の番号(並びの最後の子)を LAST_CHILD に入れる。
PARENT_ORDER=()
declare -A LAST_CHILD=()

# 使い方: queue_parent <子の番号> <親の番号、無ければ -、別のリポジトリなら other-repo>
queue_parent() {
    [ "$2" != "-" ] || return 0
    if [ "$2" = "other-repo" ]; then
        echo "Issue #$1 の親は別のリポジトリにあります。親を照会も書き込みもしません。" >&2
        return 0
    fi
    [ -n "${LAST_CHILD[$2]+set}" ] || PARENT_ORDER+=("$2")
    LAST_CHILD[$2]="$1"
}

# 使い方: parent_failed <親の番号> <最後に閉じた子の番号> <all-closed|unchecked> <標準エラーに出す文>
# 親を照会できない・閉じられないときの扱い。呼び出し側は、その親より上をたどらない。
# all-closed は子がすべて閉じたと確かめた後(閉じる操作の失敗)、unchecked は確かめられなかったとき
# (照会できない・応答の形が想定と違う)。unchecked の文面では、子がすべて閉じたと言い切らない。
# 知らせを付けられたら parent-close-failed を出し、付けられなければ終了コード 1 にする
# (子の close-failed と同じ扱い)。
parent_failed() {
    local parent="$1" child="$2"
    echo "$4(PR #${PR} のマージで閉じた Issue の親 #${parent})。知らせを付けます。" >&2
    {
        if [ "$3" = "all-closed" ]; then
            echo "この Issue から分けた Issue はすべて閉じましたが、この Issue を自動で閉じられませんでした。"
            echo ""
            echo "最後に閉じたのは #${child} です(PR #${PR} のマージによる)。"
            echo ""
            echo "**してほしいこと**"
            echo "- 分けた Issue がすべて閉じていることを確かめて、この Issue を手で閉じてください。"
        else
            echo "この Issue から分けた Issue のうち、#${child} が閉じました(PR #${PR} のマージによる)。"
            echo "分けた Issue がすべて閉じたかを自動で確かめられなかったため、この Issue を閉じていません。"
            echo ""
            echo "**してほしいこと**"
            echo "- 分けた Issue がすべて閉じていれば、この Issue を手で閉じてください。"
            echo "- まだ閉じていない Issue があれば、何もしなくて大丈夫です。"
        fi
    } >"$TMP/parent-notice.md"
    # 同じ知らせが既にあれば notice_post は重ねない(2度目以降の実行でも 0 を返す)。
    if ! notice_post "$parent" "$PARENT_CLOSE_FAILED_MARKER" "$TMP/parent-notice.md" yes; then
        echo "親の Issue #${parent} に知らせのコメントを付けられません(閉じられなかったことを所有者に知らせられません)。" >&2
        RC=1
        return
    fi
    printf 'issue=%s result=parent-close-failed\n' "$parent"
}

# 使い方: close_ancestors <親の番号> <最後に閉じた子の番号>
# 親を照会し直し、開いていて子がすべて閉じていれば閉じて記録する。閉じたら、その親の親について繰り返す。
close_ancestors() {
    local parent="$1" child="$2" depth judged
    for ((depth = 1; depth <= MAX_PARENT_DEPTH; depth++)); do
        if ! graphql "$parent" "$ISSUE_QUERY" "$TMP/parent.json" "$TMP/parent.err"; then
            cat "$TMP/parent.err" >&2
            parent_failed "$parent" "$child" unchecked "親の Issue #${parent} を照会できません"
            return
        fi
        # 子の Issue の照会と同じく、応答は「JSON がちょうど1つ」で、閉じた記録の日時をすべて読めることを確かめる。
        # 判定と親の親の番号を、空白区切りの1行で出す。
        if ! judged=$(jq -r -s --argjson merged "$MERGED_EPOCH" --arg repo "$REPO" "$JQ_PARENT_NUMBER"'
            if length == 1 then .[0] else error("形が想定と違う") end
            | .data.repository.issue
            | if type == "object" and (.timelineItems.nodes | type) == "array"
                and (.subIssuesSummary.total | type) == "number"
                and (.subIssuesSummary.completed | type) == "number"
              then . else error("形が想定と違う") end
            | (.timelineItems.nodes | map(.createdAt | fromdateiso8601)) as $closed
            | parent_number as $parent
            | (if .state == "CLOSED" then "already-closed"
               elif .state == "OPEN" then
                 (if any($closed[]; . >= $merged) then "reopened"
                  elif .subIssuesSummary.total >= 1
                    and .subIssuesSummary.completed == .subIssuesSummary.total then "close"
                  else "remaining" end)
               else error("state が想定と違う") end) as $decision
            | "\($decision) \($parent)"' "$TMP/parent.json" 2>/dev/null) ||
            ! [[ "$judged" =~ ^(already-closed|reopened|close|remaining)\ (-|other-repo|[1-9][0-9]*)$ ]]; then
            parent_failed "$parent" "$child" unchecked "親の Issue #${parent} の応答の形が想定と違います"
            return
        fi
        case "${BASH_REMATCH[1]}" in
        already-closed)
            echo "親の Issue #${parent} は閉じています。何も書き込みません。" >&2
            return
            ;;
        reopened)
            echo "親の Issue #${parent} は PR #${PR} のマージの後に一度閉じられ、開き直されています。何も書き込みません。" >&2
            return
            ;;
        remaining)
            echo "親の Issue #${parent} には閉じていない子があります(または子がありません)。何も書き込みません。" >&2
            return
            ;;
        esac
        local grandparent="${BASH_REMATCH[2]}"
        if ! gh issue close "$parent" --repo "$REPO" >&2; then
            parent_failed "$parent" "$child" all-closed "親の Issue #${parent} を閉じられません"
            return
        fi
        echo "この Issue から分けた Issue がすべて閉じたため閉じました(最後に閉じたのは #${child}、PR #${PR} のマージによる)。" >"$TMP/parent-record.md"
        if gh issue comment "$parent" --repo "$REPO" --body-file "$TMP/parent-record.md" >&2; then
            printf 'issue=%s result=parent-closed\n' "$parent"
        else
            # 親は閉じたので、親の親の判定は続ける(次の見直しでは、閉じた親より上をたどらないため)。
            echo "親の Issue #${parent} に記録のコメントを付けられません(親の Issue は閉じました)。" >&2
            RC=1
        fi
        [ "$grandparent" != "-" ] || return 0
        if [ "$grandparent" = "other-repo" ]; then
            echo "親の Issue #${parent} の親は別のリポジトリにあります。それより上を照会も書き込みもしません。" >&2
            return 0
        fi
        child="$parent"
        parent="$grandparent"
    done
    echo "親を${MAX_PARENT_DEPTH}段たどりました。それより上の Issue(#${parent})は確かめません。" >&2
}

for idx in "${CLOSED_CHILDREN[@]+"${CLOSED_CHILDREN[@]}"}"; do
    queue_parent "${NUMBERS[$idx]}" "${PARENTS[$idx]}"
done
for p in "${PARENT_ORDER[@]+"${PARENT_ORDER[@]}"}"; do
    close_ancestors "$p" "${LAST_CHILD[$p]}"
done
exit "$RC"
