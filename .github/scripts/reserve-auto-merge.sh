#!/usr/bin/env bash
# =====================================================================
# PR 1件について、自動マージの予約が要るかを判定し、要るなら予約する。
# 予約できないときは、PR へのコメントで所有者に知らせる
# (auto-merge.yaml から実行)
#
# 判定: その時点の PR の状態を照会して決める。起点のイベントは見ない。
#   対象の PR でない          → skipped(何も書き込まない)
#   対象で、予約が付いている  → already(予約に触らない)
#   対象で、予約が無い
#     最後のコミットより後に予約が3回を超えて外れている
#                                       → stopped(予約せず、知らせを1回付ける)
#     それ以外は、照会したときの head のコミットに限って squash で予約する
#       予約できた                      → reserved
#       失敗し、head が変わっていた     → head-moved(何もしない。新しいコミットの
#                                         イベントか次の見直しに任せる)
#       失敗し、head が変わっていない   → failed(知らせを1回付ける)
#
# 知らせ(PR へのコメント。lib-notice-comment.sh の関数で付ける):
#   failed    予約の操作が失敗した。所有者へのメンションを付ける
#   stopped   付け直しを止めた。所有者へのメンションを付ける
#   resolved  failed か stopped を知らせた PR に予約が付いた(already と reserved の
#             とき)。対応が要らなくなったことを同じ PR で伝える。メンションは付けない
#   目印は <!-- auto-merge-notice kind=<種類> head=<コミット> --> で、同じ目印の
#   コメントが既にあれば重ねない。同じコミットの同じ知らせは1回だけになる。
#   resolved を付けるのは、最新の知らせが failed か stopped のときだけである。
#
# なぜ3回を超えたら止めるか:
#   予約しても外れることを繰り返す PR に付け直し続けると、外れるたびにこの仕組みが
#   起動して終わらない。回数は、最後のコミットより後に外れた回数を理由を問わず数える。
#   新しいコミットが積まれると 0 に戻り、予約を再開する。
#
# なぜ予約の失敗を終了コード 0 にするか:
#   ワークフローの失敗(赤)は所有者に届かない。所有者への経路は知らせのコメントで
#   あり、知らせを付けられたら役目を果たしている。知らせを付けられないときは
#   終了コード 1 にする。
#
# 対象の PR(すべて満たすもの):
#   開いている・下書きでない・base が main・作成者が Dependabot でない・
#   fork からでない・ブランチ名が canary/ で始まらない・ラベル canary が無い
#   Dependabot の PR は dependabot-auto-merge.yaml が予約の時期を決めている。
#   カナリアPR(canary/ のブランチとラベル canary)はマージしてはならない。
#   作成者が bot か所有者かは問わない。予約が外れた理由も問わない。
#
# なぜ pre-merge-check ラベルを見ないか:
#   保留は既存の必須チェック(pre-merge-check)が行う。予約が付いていても、
#   必須チェックと承認が揃うまで PR はマージされない。ここでラベルを見て予約を
#   控えると、保留の判定が2か所に分かれる。
#
# なぜ予約の操作だけ RESERVE_TOKEN を使うか:
#   ワークフローの標準のトークンで予約すると、マージの push が後続のワークフロー
#   (依存関係の記録など)を起動しない(#326)。予約だけ bot のトークンで行い、
#   照会と知らせは標準のトークン(GH_TOKEN)で行う。bot のトークンを渡す範囲を
#   予約の操作1つに絞るためである。
#
# なぜ --match-head-commit を付けるか:
#   照会の後にコミットが積まれていたら、判定していないコミットに予約が付く。
#   照会したときの head と違えば gh が失敗し、予約は付かない。
#   PR がすでにマージできる状態なら、gh は予約せずその場でマージする。
#   --admin など迂回の指定は使わないため、必須チェックと承認は飛ばない。
#     https://cli.github.com/manual/gh_pr_merge
#
# 照会できない・応答の形が想定と違うとき:
#   予約にも対象外にも倒さず、何も書き込まずに終了コード 1 で終える。
#
# 見直し(--sweep。auto-merge.yaml の定期実行から呼ぶ):
#   予約が外れたことのイベントを受け取れなかった PR を拾うため、開いている main 向けの
#   PR(最大100件)を一覧し、1件ずつ <PR番号> の形でこのスクリプト自身を呼ぶ。
#   判定は <PR番号> の形の1か所だけにあり、ここでは PR を選ばない(一覧の段階で
#   Dependabot や下書きを除かない。対象かどうかは1件ごとの判定が決める)。
#   1件ごとに時間の上限(120秒)を付ける。1件が止まっても残りの PR を見直すためである。
#   1件が失敗・時間切れになっても残りを続け、失敗が1件でもあれば終了コード 1 にする。
#   一覧を取れないとき・応答の形が想定と違うときは、何もせず終了コード 1 で終える。
#   一覧は標準のトークン(GH_TOKEN)で取る。
#     https://cli.github.com/manual/gh_pr_list
#
# テスト: .github/scripts/tests/test-reserve-auto-merge.sh
# 使い方: reserve-auto-merge.sh <PR番号>
#         reserve-auto-merge.sh --sweep
#   環境変数(必須): GH_TOKEN / RESERVE_TOKEN / GITHUB_REPOSITORY / GITHUB_REPOSITORY_OWNER
#   環境変数(任意): NOTICE_AUTHOR(lib-notice-comment.sh を参照)
#                   SWEEP_PR_TIMEOUT_SECONDS(--sweep の1件ごとの時間の上限。既定 120。
#                   テストで短くするためのもの)
# 出力(<PR番号>): 標準出力に result=<skipped|already|reserved|stopped|failed|head-moved> の
#       1行だけを出す。経過と理由は標準エラーに出す。
# 出力(--sweep): 標準出力に、1件ごとに pr=<番号> result=<...> の1行を出す。
#       result は <PR番号> の形の値か、error(その PR の処理が失敗した)、
#       timeout(時間の上限を超えた)。経過と理由は標準エラーに出す。
# 終了コード(<PR番号>): 0 = 判定と、必要な操作・知らせを終えた
#                 (failed・stopped でも知らせを付けられたら 0)
#             1 = PR を照会できない、応答の形が想定と違う、知らせを付けられない、
#                 引数・環境変数の不足(result= の行を出さない)
# 終了コード(--sweep): 0 = 一覧の全ての PR が終了コード 0 で終わった(一覧が空のときを含む)
#             1 = 一覧を取れない、応答の形が想定と違う、error か timeout の PR が
#                 1件でもある、引数・環境変数の不足
# =====================================================================
set -euo pipefail

die() {
    echo "::error::$1" >&2
    exit 1
}

log() {
    echo "$1" >&2
}

# --- 引数と環境変数 ---------------------------------------------------------------
USAGE="使い方: reserve-auto-merge.sh <PR番号> | reserve-auto-merge.sh --sweep"
[ "$#" -eq 1 ] || die "$USAGE"
SWEEP=false
PR=""
if [ "$1" = "--sweep" ]; then
    SWEEP=true
else
    PR="$1"
    [[ "$PR" =~ ^[1-9][0-9]*$ ]] || die "PR番号が不正です: '${PR}'(${USAGE})"
fi
for v in GH_TOKEN RESERVE_TOKEN GITHUB_REPOSITORY GITHUB_REPOSITORY_OWNER; do
    [ -n "${!v:-}" ] || die "環境変数 ${v} が必要です。"
done
REPO="$GITHUB_REPOSITORY"
[[ "$REPO" =~ ^[^/[:space:]]+/[^/[:space:]]+$ ]] || die "GITHUB_REPOSITORY が <所有者>/<名前> の形ではありません: '${REPO}'"
REPO_OWNER="${REPO%%/*}"
REPO_NAME="${REPO#*/}"
command -v jq >/dev/null 2>&1 || die "jq が見つかりません。"

# 最後のコミットより後に予約が外れた回数が、これを超えたら付け直しを止める
MAX_REARMS=3
# 知らせの目印の名前(目印は <!-- auto-merge-notice kind=<種類> head=<コミット> -->)
NOTICE_NAME="auto-merge-notice"

# 知らせのコメントを付ける関数(notice_post / notice_last_kind)
SELF_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd) || die "スクリプトの場所を特定できません。"
# shellcheck source=.github/scripts/lib-notice-comment.sh
source "${SELF_DIR}/lib-notice-comment.sh" || die "lib-notice-comment.sh を読み込めません。"

TMP=$(mktemp -d) || die "作業用のディレクトリを作れません。"
trap 'rm -rf "$TMP"' EXIT

# --- 見直し(--sweep。一覧は GH_TOKEN)-----------------------------------------------
# 一覧に載せる PR の数の上限
SWEEP_LIMIT=100

sweep() {
    local seconds="${SWEEP_PR_TIMEOUT_SECONDS:-120}"
    [[ "$seconds" =~ ^[1-9][0-9]*$ ]] || die "SWEEP_PR_TIMEOUT_SECONDS が正の整数ではありません: '${seconds}'"
    command -v timeout >/dev/null 2>&1 || die "timeout が見つかりません。"

    if ! gh pr list --repo "$REPO" --state open --base main --limit "$SWEEP_LIMIT" --json number \
        >"$TMP/list.json" 2>"$TMP/list.err"; then
        cat "$TMP/list.err" >&2
        die "開いている PR の一覧を取れませんでした。"
    fi
    # 番号が正の整数の配列であることを確かめる。形の違う応答を「PR が無い」と読まない。
    # 本物の「PR が無い」は [] である。gh が成功して何も返さないとき(0バイト・改行だけ)は、
    # jq が何も出さずに成功して 0 件と読めてしまうため、-s で束ねて JSON がちょうど1件で
    # あることを先に確かめる(JSON が複数つながった応答も失敗にする)。
    if ! jq -r -s '
        if length == 1 then .[0] else error("応答が JSON 1件でない") end
        | if type == "array" and all(.[]; type == "object" and (.number | type == "number" and . >= 1 and . == floor))
        then .[].number else error("一覧が PR 番号の配列でない") end' \
        "$TMP/list.json" >"$TMP/numbers.txt" 2>"$TMP/list-parse.err"; then
        cat "$TMP/list-parse.err" >&2
        die "開いている PR の一覧の応答の形が想定と違います。"
    fi

    local total
    total=$(wc -l <"$TMP/numbers.txt" | tr -d ' ')
    log "見直し: 開いている main 向けの PR は ${total} 件です。"
    if [ "$total" -ge "$SWEEP_LIMIT" ]; then
        log "::warning::開いている PR が一覧の上限(${SWEEP_LIMIT} 件)に達しています。上限を超えた分は見直していません。"
    fi

    # 1件ずつ、<PR番号> の形でこのスクリプト自身を呼ぶ(判定を二重に持たない)。
    # timeout は時間切れで 124 を返す。TERM で止まらなければ 10 秒後に KILL し、137 を返す。
    # 一覧は fd 3 から読み、子には標準入力を渡さない(子が一覧を読み進めないようにする)。
    local n rc out failures=0
    while read -r n <&3; do
        [[ "$n" =~ ^[1-9][0-9]*$ ]] || die "開いている PR の一覧に不正な番号があります: '${n}'"
        rc=0
        timeout -k 10 "$seconds" bash "${BASH_SOURCE[0]}" "$n" >"$TMP/one.out" </dev/null || rc=$?
        out=$(cat "$TMP/one.out")
        if [ "$rc" -eq 0 ] && [[ "$out" =~ ^result=(skipped|already|reserved|stopped|failed|head-moved)$ ]]; then
            echo "pr=${n} ${out}"
        elif [ "$rc" -eq 124 ] || [ "$rc" -eq 137 ]; then
            echo "::error::PR #${n} の処理が ${seconds} 秒で終わらなかったため、打ち切りました。残りの PR を続けます。" >&2
            echo "pr=${n} result=timeout"
            failures=$((failures + 1))
        else
            echo "::error::PR #${n} の処理が失敗しました(終了コード ${rc})。残りの PR を続けます。" >&2
            echo "pr=${n} result=error"
            failures=$((failures + 1))
        fi
    done 3<"$TMP/numbers.txt"

    if [ "$failures" -gt 0 ]; then
        die "見直しで ${failures} 件の PR の処理が失敗しました(${total} 件中)。"
    fi
    log "見直しを終えました(${total} 件)。"
}

if [ "$SWEEP" = "true" ]; then
    sweep
    exit 0
fi

# --- 知らせ(GH_TOKEN)--------------------------------------------------------------
# 使い方: post_notice <種類> <本文のファイル> <mention: yes|no>
# 同じコミットの同じ種類の知らせが既にあれば重ねない。付けられなければ終了コード 1。
post_notice() {
    local kind="$1" body_file="$2" mention="$3"
    notice_post "$PR" "<!-- ${NOTICE_NAME} kind=${kind} head=${HEAD} -->" "$body_file" "$mention" ||
        die "PR #${PR} に知らせ(${kind})のコメントを付けられませんでした。"
}

# 予約が付いた(付いていた)ときに呼ぶ。最新の知らせが failed か stopped なら、
# 対応が要らなくなったことを同じ PR に1回だけ書く。最新が resolved のとき、
# 知らせが無いときは何もしない。
post_resolved_if_pending() {
    local last
    last=$(notice_last_kind "$PR" "$NOTICE_NAME") ||
        die "PR #${PR} の知らせのコメントを読めませんでした。"
    if [ "$last" != "failed" ] && [ "$last" != "stopped" ]; then
        return 0
    fi
    log "PR #${PR} には未解消の知らせ(${last})があります。予約が付いたことを書きます。"
    printf '%s\n' \
        "PR #${PR} に自動マージの予約が付きました。先にお知らせした件への対応は要りません。" \
        >"$TMP/resolved.md"
    post_notice resolved "$TMP/resolved.md" no
}

# --- PR の照会(GH_TOKEN)----------------------------------------------------------
# timelineItems は、最後のコミットより後に予約が外れた回数と理由を読むために取る。
# GraphQL の author.login は、Dependabot では dependabot になる
# (REST とイベントでは dependabot[bot])。
# shellcheck disable=SC2016
QUERY='query($owner:String!,$name:String!,$number:Int!){
  repository(owner:$owner,name:$name){
    pullRequest(number:$number){
      state isDraft baseRefName isCrossRepository headRefName headRefOid
      author{login}
      labels(first:100){nodes{name}}
      autoMergeRequest{enabledAt}
      timelineItems(last:100,itemTypes:[PULL_REQUEST_COMMIT,AUTO_MERGE_DISABLED_EVENT]){
        nodes{__typename ... on AutoMergeDisabledEvent{reasonCode}}
      }
    }
  }
}'
if ! gh api graphql -f query="$QUERY" -F owner="$REPO_OWNER" -F name="$REPO_NAME" -F number="$PR" \
    >"$TMP/pr.json" 2>"$TMP/pr.err"; then
    cat "$TMP/pr.err" >&2
    die "PR #${PR} を照会できませんでした。"
fi

# 応答の形を確かめながら、判定に使う値だけを取り出す。項目が欠けている応答を
# 「予約が無い」「ラベルが無い」と読むと誤って予約するため、欠けていれば失敗にする。
# 作成者のアカウントが消えていると author は null になる(Dependabot ではない)。
# gh が成功して何も返さないとき(0バイト・改行だけ)は、jq が何も出さずに成功し、
# 全ての値が空のまま「開いていない PR」と読めてしまう。-s で束ねて JSON がちょうど
# 1件であることを先に確かめる(JSON が複数つながった応答も失敗にする)。
if ! jq -c -s '
    def bool(what): if type == "boolean" then . else error(what + " が真偽値でない") end;
    def str(what): if type == "string" and length > 0 then . else error(what + " が文字列でない") end;
    if length == 1 then .[0] else error("応答が JSON 1件でない") end
    | .data.repository.pullRequest
    | if type == "object" then . else error("pullRequest がオブジェクトでない") end
    | if has("author") and has("autoMergeRequest") then . else error("項目が欠けている") end
    | {
        state: (.state | if . == "OPEN" or . == "CLOSED" or . == "MERGED" then . else error("state が想定に無い値") end),
        draft: (.isDraft | bool("isDraft")),
        base: (.baseRefName | str("baseRefName")),
        cross: (.isCrossRepository | bool("isCrossRepository")),
        head_ref: (.headRefName | str("headRefName")),
        head: (.headRefOid | if type == "string" and test("^[0-9a-f]{40,64}$") then . else error("headRefOid がコミットの形でない") end),
        author: (.author | if . == null then "" elif type == "object" then (.login | str("author.login")) else error("author がオブジェクトでない") end),
        labels: (.labels | if type == "object" then .nodes else error("labels がオブジェクトでない") end
            | if type == "array" and all(.[]; type == "object" and (.name | type) == "string") then map(.name) else error("labels の形が想定と違う") end),
        armed: (.autoMergeRequest | if . == null then false elif type == "object" then true else error("autoMergeRequest の形が想定と違う") end),
        disabled: (.timelineItems | if type == "object" then .nodes else error("timelineItems がオブジェクトでない") end
            | if type == "array" and all(.[]; type == "object" and (.__typename | type) == "string") then . else error("timelineItems の形が想定と違う") end
            | (map(.__typename) | rindex("PullRequestCommit") // -1) as $i
            | .[($i + 1):]
            | map(select(.__typename == "AutoMergeDisabledEvent"))
            | {count: length, reason: ((last // {}) | .reasonCode // "" | tostring)})
    }' "$TMP/pr.json" >"$TMP/pr.parsed" 2>"$TMP/parse.err"; then
    cat "$TMP/parse.err" >&2
    die "PR #${PR} の照会の応答の形が想定と違います。"
fi

field() {
    jq -r "$1" "$TMP/pr.parsed"
}
STATE=$(field '.state')
DRAFT=$(field '.draft')
BASE=$(field '.base')
CROSS=$(field '.cross')
HEAD_REF=$(field '.head_ref')
HEAD=$(field '.head')
AUTHOR=$(field '.author')
HAS_CANARY_LABEL=$(field '.labels | any(. == "canary")')
ARMED=$(field '.armed')
DISABLED_COUNT=$(field '.disabled.count')
DISABLED_REASON=$(field '.disabled.reason')

log "PR #${PR}: state=${STATE} draft=${DRAFT} base=${BASE} author=${AUTHOR:-(不明)} fork=${CROSS} branch=${HEAD_REF} head=${HEAD} armed=${ARMED} 最後のコミットより後に予約が外れた回数=${DISABLED_COUNT} 直近の理由=${DISABLED_REASON:-(なし)}"

# --- 対象の PR かどうか -------------------------------------------------------------
# 対象外なら理由を標準出力に出して 0、対象なら何も出さずに 1 を返す。
# pre-merge-check ラベルは見ない(冒頭の説明を参照)。
skip_reason() {
    if [ "$STATE" != "OPEN" ]; then
        echo "開いていない(${STATE})"
    elif [ "$DRAFT" = "true" ]; then
        echo "下書きである"
    elif [ "$BASE" != "main" ]; then
        echo "base が main でない(${BASE})"
    elif [ "$AUTHOR" = "dependabot" ] || [ "$AUTHOR" = "dependabot[bot]" ]; then
        echo "Dependabot の PR である(dependabot-auto-merge.yaml が受け持つ)"
    elif [ "$CROSS" = "true" ]; then
        echo "fork からの PR である"
    elif [[ "$HEAD_REF" == canary/* ]]; then
        echo "カナリアPRである(ブランチ名が canary/ で始まる)"
    elif [ "$HAS_CANARY_LABEL" = "true" ]; then
        echo "カナリアPRである(ラベル canary が付いている)"
    else
        return 1
    fi
    return 0
}

if reason=$(skip_reason); then
    log "PR #${PR} は対象の PR ではないため、予約しません: ${reason}"
    echo "result=skipped"
    exit 0
fi

# --- 予約済みなら触らない -----------------------------------------------------------
if [ "$ARMED" = "true" ]; then
    log "PR #${PR} には自動マージが予約済みです。予約に触りません。"
    post_resolved_if_pending
    echo "result=already"
    exit 0
fi

# --- 同じコミットで3回を超えて外れていたら、付け直しを止めて知らせる -------------------
# 定期の見直しでも同じ判定を通るため、止めた PR は新しいコミットが積まれるまで
# 付け直されない。
if [ "$DISABLED_COUNT" -gt "$MAX_REARMS" ]; then
    log "PR #${PR} は同じコミットで予約が ${DISABLED_COUNT} 回外れているため、付け直しを止めます(${MAX_REARMS} 回を超えると止める)。"
    {
        echo "PR #${PR} の自動マージの予約の付け直しを止めました。"
        echo
        echo "同じコミットのまま、予約が${DISABLED_COUNT}回外れたためです(${MAX_REARMS}回を超えると、付け直しを止めます)。このままでは、チェックが通ってもこの PR はマージされません。"
        echo
        echo "してほしいこと:"
        echo
        echo "1. PR の状態を確かめてください(チェックが失敗していないか、承認待ちになっていないか)。原因が分からないときは、Claude Code に「PR #${PR} の自動マージの予約が外れ続ける原因を調べて」と依頼してください。"
        echo "2. 原因を直した新しいコミットが積まれると、予約の付け直しは自動で再開します。"
    } >"$TMP/stopped.md"
    post_notice stopped "$TMP/stopped.md" yes
    echo "result=stopped"
    exit 0
fi

# --- 予約する(RESERVE_TOKEN)-------------------------------------------------------
# この呼び出しだけ GH_TOKEN を予約用のトークンに差し替える。
# gh の出力は標準エラーへ回す(標準出力は result= の1行だけにするため)。
if GH_TOKEN="$RESERVE_TOKEN" gh pr merge --auto --squash --match-head-commit "$HEAD" "$PR" --repo "$REPO" \
    >"$TMP/merge.out" 2>"$TMP/merge.err"; then
    cat "$TMP/merge.out" "$TMP/merge.err" >&2
    log "PR #${PR} に自動マージを予約しました(head=${HEAD})。"
    post_resolved_if_pending
    echo "result=reserved"
    exit 0
fi
cat "$TMP/merge.out" "$TMP/merge.err" >&2

# --- 予約に失敗した: head が変わったかを確かめる(GH_TOKEN)--------------------------
# 変わったかを確かめられないときは、head-moved に倒さず失敗にする。
if ! gh pr view "$PR" --repo "$REPO" --json headRefOid >"$TMP/view.json" 2>"$TMP/view.err"; then
    cat "$TMP/view.err" >&2
    die "PR #${PR} の自動マージの予約に失敗し、head のコミットも照会できませんでした。"
fi
# 応答が空のときに「head が変わった」と読まないよう、ここでも JSON がちょうど1件で
# あることを先に確かめる。
if ! CURRENT=$(jq -r -s 'if length == 1 then .[0] else error("応答が JSON 1件でない") end
    | .headRefOid | if type == "string" and test("^[0-9a-f]{40,64}$") then . else error("headRefOid がコミットの形でない") end' \
    "$TMP/view.json" 2>/dev/null); then
    die "PR #${PR} の自動マージの予約に失敗し、head のコミットの応答の形も想定と違います。"
fi
if [ "$CURRENT" != "$HEAD" ]; then
    log "PR #${PR} に新しいコミットが積まれたため、予約を見送りました(照会時 ${HEAD}、現在 ${CURRENT})。"
    echo "result=head-moved"
    exit 0
fi

# --- 予約に失敗し、head は変わっていない: 知らせる ------------------------------------
log "PR #${PR} の自動マージの予約に失敗しました(head=${HEAD})。gh のエラーは上のとおりです。"
# gh のエラーの要点として、先頭の3行(1行200文字まで)を知らせに載せる。
# コードの囲みを閉じてしまう記号(バッククォート)は除く。
ERROR_SUMMARY=$(grep -v '^[[:space:]]*$' "$TMP/merge.err" | head -n 3 | cut -c 1-200 | tr -d '`' || true)
{
    echo "PR #${PR} に自動マージの予約を付けられませんでした。"
    echo
    echo "失敗した操作は「自動マージの予約」です。予約が付かないままでは、チェックが通ってもこの PR はマージされません。"
    echo
    echo "GitHub から返ったエラー:"
    echo
    echo '```'
    printf '%s\n' "${ERROR_SUMMARY:-(エラーの文面を取得できませんでした)}"
    echo '```'
    echo
    echo "してほしいこと:"
    echo
    echo "1. Claude Code に「PR #${PR} の自動マージの予約が失敗した原因を調べて」と依頼してください。"
    echo "2. bot のトークンの期限が切れていないかを確かめてください(予約は bot のトークンで行っています)。"
} >"$TMP/failed.md"
post_notice failed "$TMP/failed.md" yes
echo "result=failed"
exit 0
