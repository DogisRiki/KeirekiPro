#!/usr/bin/env bash
# =====================================================================
# claude-auto-fix の report ジョブで、対象ごとの実行の結果を残し、所有者に Issue で知らせるスクリプト
# (design.md の claude-auto-fix-report.sh の節)
#
# 使い方: claude-auto-fix-report.sh <record|notify> <outcome> <kind> <key> <reason> <pr> <checks> <detail> <理由の種類> <PR の URL>
#   outcome     実行の結果。pr unfixed unavailable key blocked gone skipped のどれか。
#               record の形では空でもよい(JOB_RESULTS で決める)
#   pr          reason が red-check のときの Claude の変更の PR の番号。そのほかは空
#   checks      reason が red-check のときの赤の検査の名前の JSON の配列。空でもよい
#   detail      対象の詳しい中身の JSON のオブジェクト。空でもよい
#   理由の種類  止まった理由の種類(英小文字と数字とハイフン)。空でもよい
#   PR の URL   outcome が pr のときは作った PR の URL。sweep から呼ぶときは閉じた PR の URL。
#               このリポジトリの PR の URL だけを受け付ける
#
# record の形:
#   $RUNNER_TEMP/outcome/outcome.json に結果のファイルを書き、標準出力に result=<outcome> を書く。
#   GITHUB_STEP_SUMMARY があれば1行を書く。種類が codeql の行には、警告の番号と結果だけを書く。
#   Issue の API を呼ばない。
#   outcome が空のとき(ジョブが結果を出さずに止まったとき)は、JOB_RESULTS で failure か cancelled の
#   ジョブのうち、次の順で最も前のジョブから結果を決める(design.md の claude-auto-fix-target.yaml の
#   「失敗したとき」の表)。理由の種類が空なら、<ジョブの名前>-<failure|cancelled> にする。
#     prepare edit → unavailable / verify verify-image → unfixed /
#     cooldown-push cooldown-generate cooldown-submit cooldown-judge → unavailable / ship → unavailable /
#     そのほかのジョブ → unavailable
#   止まったジョブも無いときは、結果を unavailable、理由の種類を no-outcome にする。結果のファイルが
#   無い実行は、dispatch の動かし直しと3日の数え方が読めないので、どの場合も結果のファイルを書く。
#   outcome が空でなければ、JOB_RESULTS によらず outcome をそのまま使う。
# notify の形:
#   結果のファイルを書かない。次のとおり Issue を起票し、コメントを付け、閉じる。
#   - EDIT_OUTCOME が ok か unfixed のとき(Claude が動けた実行)は、開いている鍵の Issue に、動けたことを
#     書いたコメントを付けて閉じる。結果が blocked や gone でも閉じる
#   - pr: 同じ key の知らせの Issue が開いていて、状態が unavailable なら、PR の URL を書いたコメントを
#     付けて閉じる
#   - unfixed: 種類が container なら、ラベル container-vuln の Issue に、直せなかったことを書いた
#     コメントを、目印 <!-- claude-auto-fix-notice kind=unfixed run=<実行の ID> --> を付けて書く。
#     ほかの種類では、同じ key の知らせの Issue が開いていればコメントを付け、目印の状態を unfixed にする。
#     開いていなければ起票する。reason が red-check のときは、赤の検査を直せなかった PR の URL を書く。
#     PR の URL を渡されたとき(sweep が閉じた PR)は、その URL を書く
#   - key: 鍵の Issue が開いていなければ、「Claude を動かす鍵を取り替えてください」を起票する
#   - unavailable blocked: 同じ key の知らせの Issue が開いていれば何もしない。開いていなければ、
#     直近4日の同じ key の実行の結果(lib-claude-auto-fix.sh の recent_outcomes)にこの実行の結果を足し、
#     最後の3回がどれも unavailable か blocked で、3つの違う UTC の日に終わっていれば、動けなかった日と
#     理由を書いた知らせの Issue を、状態が unavailable の目印を付けて起票する。種類が codeql のときは、
#     理由を決まった文だけで書き、理由の種類を書かない。種類が container の対象の URL は、
#     ラベル container-vuln の Issue の URL にする
#   - gone: 種類が container で理由の種類が gone-on-main(prepare が main から作ったイメージに脆弱性が
#     無いと判定した)なら、ラベル container-vuln の Issue に、main では消えていて、所有者がリリース
#     すれば本番でも消えることを書いたコメントを、目印 <!-- claude-auto-fix-notice kind=gone-on-main -->
#     を付けて1回だけ書く。そのほかの gone では何もしない
#   - skipped: 何もしない
#   Issue の API に失敗したら1で終わる。同じ実行で何度呼んでも、Issue とコメントを重ねない
#   (知らせの目印に実行の ID を入れ、目印が既にあれば書かない)。
#
# 知らせの Issue を開いているものの中からだけ探し、閉じた Issue は使わない。lib-ledger-issue.sh の
# ledger_find_or_create は、閉じた Issue も同じ題名なら使い続けるので、起票には使わない。
# 知らせの題名と本文とコメントは、決まった文と、種類と key と PR の番号と、対象の URL と、理由の種類だけで
# 書く。Claude が書いた文は入れない。種類が codeql のときは、理由の種類も書かない。
# このスクリプトは、PR を閉じること、ブランチを消すこと、PR のマージ、警告の却下、
# Dependabot へのコマンドを行わない。
#
# 環境変数:
#   GITHUB_REPOSITORY        <owner>/<repo>。必須
#   GITHUB_SERVER_URL        既定は https://github.com
#   GITHUB_RUN_ID            この実行の ID。必須
#   RUNNER_TEMP              record の形で必須。結果のファイルを置く
#   GITHUB_STEP_SUMMARY      record の形で、あれば1行を書く
#   CAF_HEAD_SHA             record の形で、起点のコミット(40桁の16進)。無ければ結果のファイルに null を書く
#   JOB_RESULTS              record の形で、needs の各ジョブの result を、ジョブの名前を欄の名前にした
#                            JSON のオブジェクトで。無ければ {} とみなす
#   GH_TOKEN                 notify の形で必須(ワークフローの GITHUB_TOKEN)
#   GITHUB_REPOSITORY_OWNER  notify の形で必須。所有者への呼びかけと担当者に使う
#   EDIT_OUTCOME             notify の形で、edit ジョブの出力 outcome。無ければ鍵の Issue を閉じない
#
# テスト: .github/scripts/tests/test-claude-auto-fix-report.sh
# =====================================================================
set -euo pipefail

CAF_REPORT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=.github/scripts/lib-claude-auto-fix.sh
. "$CAF_REPORT_DIR/lib-claude-auto-fix.sh"
# shellcheck source=.github/scripts/lib-ledger-issue.sh
. "$CAF_REPORT_DIR/lib-ledger-issue.sh"
# shellcheck source=.github/scripts/lib-notice-comment.sh
. "$CAF_REPORT_DIR/lib-notice-comment.sh"

CAF_KEY_HEADING_ANCHOR="claude-を動かす鍵の取り替え"
CAF_SETUP_DOC="doc/開発フロー/基盤構築手順.md"

usage() {
    echo "::error::claude-auto-fix-report: $1" >&2
    echo "使い方: claude-auto-fix-report.sh <record|notify> <outcome> <kind> <key> <reason> <pr> <checks> <detail> <理由の種類> <PR の URL>" >&2
    exit 2
}
fail() {
    echo "::error::claude-auto-fix-report: $1" >&2
    exit 1
}

# 対象を表す決まった文。使い方: subject <plain|md>。md のときは key をコードの形にする
# (npm の key の @ が、本文で人への呼びかけにならないようにするため)。claude-auto-fix-ship.sh と同じ文
subject() {
    local k="$KEY"
    [ "$1" != md ] || k="\`${KEY}\`"
    case "$KIND" in
    npm) printf 'npm の部品 %s の脆弱性' "$k" ;;
    maven) printf 'Maven の部品 %s の脆弱性' "$k" ;;
    go-stdlib) printf 'Go の標準ライブラリの脆弱性(Go %s で直る)' "$k" ;;
    go-module) printf 'Go の部品 %s の脆弱性' "$k" ;;
    codeql) printf 'CodeQL の警告 #%s' "$KEY" ;;
    container) printf 'コンテナの脆弱性 %s' "$k" ;;
    dependabot) printf 'Dependabot の PR #%s の赤の検査' "$KEY" ;;
    esac
}

# 対象の URL を1行に1つ書く。このリポジトリの URL と、Go の脆弱性の公開の URL だけを書く。
# claude-auto-fix-ship.sh と同じ作り方(種類が container のときは呼ばない)
target_urls() {
    local base="${SERVER}/${REPO}"
    case "$KIND" in
    npm | maven)
        jq -r --arg prefix "${base}/security/dependabot/" '
            [.alerts[]?.html_url? | select(type == "string" and startswith($prefix)
                and (ltrimstr($prefix) | test("^[1-9][0-9]*$")))] | unique | .[]' <<<"$DETAIL" ||
            fail "detail の警告の URL を読めません"
        ;;
    go-stdlib | go-module)
        jq -r '.osv | if type == "array" and length > 0 and all(type == "string" and test("^GO-[0-9]{4}-[0-9]{4,}$"))
            then unique | .[] | "https://pkg.go.dev/vuln/" + . else error("x") end' <<<"$DETAIL" 2>/dev/null ||
            fail "detail の Go の脆弱性の ID の形が違います"
        ;;
    codeql) printf '%s/security/code-scanning/%s\n' "$base" "$KEY" ;;
    dependabot) printf '%s/pull/%s\n' "$base" "$KEY" ;;
    esac
}

# ---------------------------------------------------------------------
# record の形
# ---------------------------------------------------------------------
# JOB_RESULTS で failure か cancelled の、順で最も前のジョブから、「<結果> <理由の種類>」を書く。
# 止まったジョブが無ければ何も書かない
job_outcome() {
    jq -r '
        ["prepare", "edit", "verify", "verify-image", "cooldown-push", "cooldown-generate",
         "cooldown-submit", "cooldown-judge", "ship"] as $order
        | [to_entries[] | select(.value == "failure" or .value == "cancelled")
            | . as $e | . + {i: (($order | indices($e.key))[0] // 999)}]
        | sort_by(.i, .key) | first // empty
        | (if .key == "verify" or .key == "verify-image" then "unfixed" else "unavailable" end) + " "
            + (if .key | test("^[a-z0-9]+(-[a-z0-9]+)*$") then .key else "job" end) + "-" + .value' <<<"$JOBS"
}

record() {
    [ -n "${RUNNER_TEMP:-}" ] || usage "RUNNER_TEMP がありません"
    local dir="${RUNNER_TEMP}/outcome" now line derived
    if [ -z "$OUTCOME" ]; then
        derived=$(job_outcome) || fail "JOB_RESULTS から結果を決められません"
        if [ -n "$derived" ]; then
            OUTCOME="${derived%% *}"
            [ -n "$CAUSE" ] || CAUSE="${derived#* }"
        else
            OUTCOME=unavailable
            [ -n "$CAUSE" ] || CAUSE=no-outcome
        fi
    fi
    now=$(date -u +%Y-%m-%dT%H:%M:%SZ) || fail "今の日時を読めません"
    mkdir -p "$dir" || fail "結果のファイルのフォルダを作れません"
    jq -n --arg kind "$KIND" --arg key "$KEY" --arg reason "$REASON" --arg pr "$PR" --arg checks "$CHECKS" \
        --arg detail "$DETAIL" --arg result "$OUTCOME" --arg cause "$CAUSE" --arg pr_url "$PR_URL" \
        --arg run_url "${SERVER}/${REPO}/actions/runs/${RUN_ID}" --arg head_sha "$HEAD_SHA" --arg at "$now" '
        def opt: if . == "" then null else . end;
        {kind: $kind, key: $key, reason: $reason,
         pr: (if $pr == "" then null else ($pr | tonumber) end),
         checks: (if $checks == "" then null else ($checks | fromjson) end),
         detail: (if $detail == "" then null else ($detail | fromjson) end),
         result: $result, cause: ($cause | opt), pr_url: ($pr_url | opt),
         run_url: $run_url, head_sha: ($head_sha | opt), finished_at: $at}' >"$dir/outcome.json" ||
        fail "結果のファイルを書けません"
    printf 'result=%s\n' "$OUTCOME"

    [ -n "${GITHUB_STEP_SUMMARY:-}" ] || return 0
    if [ "$KIND" = codeql ]; then
        line="- claude-auto-fix codeql #${KEY}: ${OUTCOME}"
    else
        line="- claude-auto-fix ${KIND} \`${KEY}\`: ${OUTCOME}"
        [ -z "$CAUSE" ] || line="${line}(理由の種類: \`${CAUSE}\`)"
        [ -z "$PR_URL" ] || line="${line} ${PR_URL}"
    fi
    printf '%s\n' "$line" >>"$GITHUB_STEP_SUMMARY" || fail "GITHUB_STEP_SUMMARY に書けません"
}

# ---------------------------------------------------------------------
# notify の形
# ---------------------------------------------------------------------

# 開いている、ラベル claude-auto-fix の、github-actions[bot] が起票した Issue を読む(PR を除く)。
# このスクリプトが使う欄だけを残す
open_issues() {
    local raw
    raw=$(gh api --paginate --slurp "repos/${REPO}/issues?labels=${CAF_LABEL}&state=open&per_page=100") ||
        fail "ラベル ${CAF_LABEL} の Issue を読めません"
    jq -c --arg bot "$CAF_BOT_LOGIN" "$_CAF_JQ_PAGES"'
        [pages | .[] | select((has("pull_request") | not) and (.user.login? // "") == $bot
            and (.number | type) == "number" and ((.body // "") | type) == "string")
            | {number, title, body: (.body // ""), user: {login: .user.login}, created_at}]' <<<"$raw" 2>/dev/null ||
        fail "ラベル ${CAF_LABEL} の Issue の形が違います"
}

# 番号の Issue の本文とコメントを、本文を先にした1つの配列にする。使い方: thread <番号>
# Issue の一覧とコメントは、引数の長さの上限(1つの引数で 128KiB)を超えうるので、
# jq の引数で渡さず、標準入力とファイルで渡す
thread() {
    local raw
    raw=$(gh api --paginate --slurp "repos/${REPO}/issues/${1}/comments?per_page=100") ||
        fail "Issue #${1} のコメントを読めません"
    jq -c --argjson n "$1" 'map(select(.number == $n))[0:1]' <<<"$ISSUES" >"$W/one" ||
        fail "Issue #${1} を一覧から読めません"
    jq -c --slurpfile one "$W/one" "$_CAF_JQ_PAGES"'$one[0] + pages' <<<"$raw" 2>/dev/null ||
        fail "Issue #${1} のコメントの形が違います"
}

# github-actions[bot] が書いた本文かコメントに、目印があるか。使い方: has_marker <目印> <thread の出力>
has_marker() {
    jq -e --arg m "$1" --arg bot "$CAF_BOT_LOGIN" \
        'any(.[]; (.user.login? // "") == $bot and ((.body // "") | type) == "string" and ((.body // "") | contains($m)))' \
        >/dev/null <<<"$2"
}

# 同じ key の開いている知らせの Issue の番号を、小さい順に書く
notice_numbers() {
    jq -r --arg mark "claude-auto-fix-issue key=${KIND}:${KEY} " \
        '.[] | select((.body // "") | contains($mark)) | .number' <<<"$1" | sort -n
}

# 開いている鍵の Issue の番号を、小さい順に書く
key_numbers() {
    jq -r --arg title "$CAF_KEY_TITLE" --arg mark "$CAF_KEY_MARKER" \
        '.[] | select(.title == $title and ((.body // "") | contains($mark))) | .number' <<<"$1" | sort -n
}

# 使い方: create_issue <題名> <本文のファイル>。起票し、所有者を担当者にする
create_issue() {
    local out n
    out=$(gh issue create --repo "$REPO" --title "$1" --label "$CAF_LABEL" --body-file "$2") ||
        fail "Issue を起票できません: $1"
    n=$(printf '%s\n' "$out" | sed -n 's#^.*/issues/\([1-9][0-9]*\)[[:space:]]*$#\1#p' | tail -n 1)
    [ -n "$n" ] || fail "起票した Issue の番号を読めません"
    ledger_assign_owner "$n" >&2
    echo "claude-auto-fix-report: Issue #${n} を起票しました" >&2
}

close_issue() {
    gh issue close "$1" --repo "$REPO" >&2 || fail "Issue #${1} を閉じられません"
}

# Claude が動けた実行で、開いている鍵の Issue を閉じる
close_key_issues() {
    case "${EDIT_OUTCOME:-}" in
    ok | unfixed) ;;
    *) return 0 ;;
    esac
    local n
    while IFS= read -r n; do
        [ -n "$n" ] || continue
        printf '%s\n' "claude-auto-fix の仕組みで、Claude が動けたので、この Issue を閉じます。" >"$W/key-ok"
        notice_post "$n" "<!-- claude-auto-fix-notice kind=key-ok run=${RUN_ID} -->" "$W/key-ok" no >&2 ||
            fail "鍵の Issue #${n} にコメントできません"
        close_issue "$n"
    done < <(key_numbers "$ISSUES")
}

# 直せなかったことを知らせる文を書く。使い方: unfixed_text <ファイル>
unfixed_text() {
    {
        printf 'claude-auto-fix の仕組みで、Claude が、%sを直せませんでした。所有者が手で仕組みを動かすと、もう一度 Claude を動かせます。\n' "$(subject md)"
        if [ "$KIND" != codeql ] && [ -n "$CAUSE" ]; then
            printf '\n止まった理由の種類: \140%s\140\n' "$CAUSE"
        fi
        if [ -n "$PR_URL" ]; then
            printf '\n同じ必須の検査が3回続けて赤になったので、仕組みが閉じた PR: %s\n' "$PR_URL"
        elif [ "$REASON" = red-check ]; then
            printf '\n赤の検査を直せなかった Claude の変更の PR(開いたまま残ります): %s/%s/pull/%s\n' "$SERVER" "$REPO" "$PR"
        fi
    } >"$1"
}

# 種類が container の key の、github-actions[bot] が起票した開いているラベル container-vuln の Issue のうち、
# 最も小さい番号を書く。無ければ失敗する
container_issue() {
    local raw n
    raw=$(gh api --paginate --slurp "repos/${REPO}/issues?labels=container-vuln&state=open&per_page=100") ||
        fail "ラベル container-vuln の Issue を読めません"
    n=$(jq -r --arg title "${CAF_CONTAINER_TITLE_PREFIX}${KEY}" --arg bot "$CAF_BOT_LOGIN" "$_CAF_JQ_PAGES"'
        [pages | .[] | select((has("pull_request") | not) and (.user.login? // "") == $bot and .title? == $title)
            | .number | select(type == "number")] | min // empty' <<<"$raw" 2>/dev/null) ||
        fail "ラベル container-vuln の Issue の形が違います"
    [ -n "$n" ] || fail "github-actions[bot] が起票した ${KEY} の Issue がありません"
    printf '%s\n' "$n"
}

# 知らせの Issue の本文を書く。使い方: notice_body <文のファイル> <目印> <出力のファイル>
# 種類が container の対象の URL は、ラベル container-vuln の Issue の URL にする
notice_body() {
    local n
    if [ "$KIND" = container ]; then
        n=$(container_issue)
        printf '%s/%s/issues/%s\n' "$SERVER" "$REPO" "$n" >"$W/urls"
    else
        target_urls >"$W/urls"
    fi
    [ -s "$W/urls" ] || fail "対象の URL がありません"
    {
        cat "$1"
        printf '\n## 対象\n\n'
        sed 's/^/- /' "$W/urls"
        printf '\n%s\n' "$2"
    } >"$3"
}

notify_unfixed() {
    local n list marker title
    unfixed_text "$W/text"
    if [ "$KIND" = container ]; then
        n=$(container_issue)
        notice_post "$n" "<!-- claude-auto-fix-notice kind=unfixed run=${RUN_ID} -->" "$W/text" yes >&2 ||
            fail "ラベル container-vuln の Issue #${n} にコメントできません"
        return 0
    fi

    marker=$(marker_line issue "key=${KIND}:${KEY}" kind=unfixed "run=${RUN_ID}") || fail "目印を作れません"
    notice_body "$W/text" "$marker" "$W/body"

    n=$(notice_numbers "$ISSUES" | head -n 1)
    if [ -n "$n" ]; then
        list=$(thread "$n")
        if has_marker "$marker" "$list"; then
            echo "claude-auto-fix-report: Issue #${n} には、この実行の知らせが既にあります" >&2
            return 0
        fi
        ledger_comment "$n" "$W/body" >&2 || fail "知らせの Issue #${n} にコメントできません"
        return 0
    fi
    title="Claude が直せなかった $(subject plain)"
    create_issue "$title" "$W/body"
}

notify_pr() {
    local n list state
    while IFS= read -r n; do
        [ -n "$n" ] || continue
        list=$(thread "$n")
        state=$(issue_state "$KIND" "$KEY" <<<"$list") || fail "Issue #${n} の状態を読めません"
        [ "$state" = unavailable ] || continue
        printf 'claude-auto-fix の仕組みで、Claude が%sを直す PR を作ったので、この Issue を閉じます。\n\n- %s\n' \
            "$(subject md)" "$PR_URL" >"$W/pr"
        notice_post "$n" "<!-- claude-auto-fix-notice kind=pr run=${RUN_ID} -->" "$W/pr" no >&2 ||
            fail "知らせの Issue #${n} にコメントできません"
        close_issue "$n"
    done < <(notice_numbers "$ISSUES")
}

notify_key() {
    if [ -n "$(key_numbers "$ISSUES")" ]; then
        echo "claude-auto-fix-report: 鍵の Issue が既に開いています" >&2
        return 0
    fi
    {
        printf 'claude-auto-fix の仕組みで、Claude を動かす鍵が使えなかったため、Claude を動かせませんでした。'
        printf '[基盤構築手順の「Claude を動かす鍵の取り替え」](%s/%s/blob/main/%s#%s)のとおりに、鍵を取り替えてください。' \
            "$SERVER" "$REPO" "$CAF_SETUP_DOC" "$CAF_KEY_HEADING_ANCHOR"
        printf 'Claude が動けた実行のあとに、仕組みがこの Issue を閉じます。\n\n%s\n' "$CAF_KEY_MARKER"
    } >"$W/key"
    create_issue "$CAF_KEY_TITLE" "$W/key"
}

# 直近4日の同じ key の実行の結果にこの実行の結果を足し、最後の3回がどれも unavailable か blocked で、
# 3つの違う UTC の日に終わっていれば、動けなかったことを知らせる Issue を起票する
notify_unavailable() {
    local runs now marker codeql=""
    if [ -n "$(notice_numbers "$ISSUES")" ]; then
        echo "claude-auto-fix-report: 同じ key の知らせの Issue が開いているので、起票しません" >&2
        return 0
    fi
    runs=$(recent_outcomes) || fail "直近4日の実行の結果を読めません"
    printf '%s\n' "$runs" >"$W/runs"
    now=$(date -u +%Y-%m-%dT%H:%M:%SZ) || fail "今の日時を読めません"
    jq -c -n --slurpfile runs "$W/runs" --arg kind "$KIND" --arg key "$KEY" \
        --arg url "${SERVER}/${REPO}/actions/runs/${RUN_ID}" --arg result "$OUTCOME" --arg cause "$CAUSE" --arg at "$now" '
        ($runs[0] | if type == "array" then . else error("x") end
            | map(select(.kind == $kind and .key == $key and .run_url != $url)))
        + [{result: $result, cause: (if $cause == "" then null else $cause end), finished_at: $at}]
        | .[-3:]' >"$W/last" 2>/dev/null || fail "直近4日の実行の結果の形が違います"
    if ! jq -e 'length == 3
        and all(.[]; (.result == "unavailable" or .result == "blocked")
            and ((.finished_at | type) == "string") and (.finished_at | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T")))
        and (map(.finished_at[0:10]) | unique | length) == 3' "$W/last" >/dev/null 2>&1; then
        echo "claude-auto-fix-report: 3つの違う日に続けて動けなかったわけではないので、起票しません" >&2
        return 0
    fi

    [ "$KIND" != codeql ] || codeql=yes
    {
        printf 'claude-auto-fix の仕組みで、3つの違う日に続けて、Claude が%sを直すところまで進めませんでした。' "$(subject md)"
        printf '仕組みは、次の日からも Claude を動かします。Claude の変更の PR ができたら、仕組みがこの Issue を閉じます。\n'
        printf '\n## 動けなかった理由\n\n'
        jq -r --arg codeql "$codeql" --arg bq "$(printf '\140')" '.[]
            | "- " + .finished_at[0:10] + ": "
            + (if .result == "blocked" then "公開から72時間経っていない版を使う変更なので、PR にするのを待ちました"
               else "Claude を動かせませんでした" end)
            + (if $codeql == "" and (.cause | type) == "string" and (.cause | test("^[a-z0-9]+(-[a-z0-9]+)*$"))
               then "(理由の種類: " + $bq + .cause + $bq + ")" else "" end)' "$W/last"
    } >"$W/text" || fail "動けなかった理由を書けません"
    marker=$(marker_line issue "key=${KIND}:${KEY}" kind=unavailable "run=${RUN_ID}") || fail "目印を作れません"
    notice_body "$W/text" "$marker" "$W/body"
    create_issue "Claude が3日続けて動けなかった $(subject plain)" "$W/body"
}

# 種類が container で、main から作ったイメージに脆弱性が無いときに、ラベル container-vuln の Issue に1回だけ書く
notify_gone() {
    [ "$KIND" = container ] && [ "$CAUSE" = gone-on-main ] || return 0
    local n
    n=$(container_issue)
    printf 'claude-auto-fix の仕組みで、main から作ったイメージを調べたところ、脆弱性 \140%s\140 は見つかりませんでした。main では消えています。Claude の変更の PR は作りません。所有者がリリースすれば、本番でも消えます。\n' \
        "$KEY" >"$W/gone"
    notice_post "$n" "<!-- claude-auto-fix-notice kind=gone-on-main -->" "$W/gone" yes >&2 ||
        fail "ラベル container-vuln の Issue #${n} にコメントできません"
}

notify() {
    [ -n "${GH_TOKEN:-}" ] || usage "GH_TOKEN がありません"
    [[ "${GITHUB_REPOSITORY_OWNER:-}" =~ ^[A-Za-z0-9][A-Za-z0-9-]*$ ]] || usage "GITHUB_REPOSITORY_OWNER の形が違います"
    W=$(mktemp -d) || fail "一時のフォルダを作れません"
    trap 'rm -rf "$W"' EXIT
    ISSUES=$(open_issues)
    close_key_issues
    case "$OUTCOME" in
    pr) notify_pr ;;
    unfixed) notify_unfixed ;;
    key) notify_key ;;
    unavailable | blocked) notify_unavailable ;;
    gone) notify_gone ;;
    *) ;;
    esac
}

main() {
    [ "$#" -eq 10 ] || usage "引数の数が違います"
    MODE="$1"
    OUTCOME="$2"
    KIND="$3"
    KEY="$4"
    REASON="$5"
    PR="$6"
    CHECKS="$7"
    DETAIL="$8"
    CAUSE="$9"
    PR_URL="${10}"
    case "$MODE" in
    record | notify) ;;
    *) usage "知らない形です: ${MODE}" ;;
    esac
    case "$OUTCOME" in
    pr | unfixed | unavailable | key | blocked | gone | skipped) ;;
    "") [ "$MODE" = record ] || usage "notify の形では結果が要ります" ;;
    *) usage "知らない結果です: ${OUTCOME}" ;;
    esac
    case "$KIND" in
    npm | maven | go-stdlib | go-module | codeql | container | dependabot) ;;
    *) usage "知らない種類です: ${KIND}" ;;
    esac
    _caf_valid_key "$KEY" || usage "key の形が違います"
    case "$KIND" in
    codeql | dependabot) [[ "$KEY" =~ ^[1-9][0-9]*$ ]] || usage "key の番号の形が違います" ;;
    esac
    case "$REASON" in
    trigger | manual | retry) ;;
    red-check) [ -n "$PR" ] || usage "red-check の PR の番号がありません" ;;
    *) usage "知らない reason です: ${REASON}" ;;
    esac
    [ -z "$PR" ] || [[ "$PR" =~ ^[1-9][0-9]*$ ]] || usage "PR の番号の形が違います"
    if [ -n "$CHECKS" ]; then
        jq -e 'type == "array" and all(type == "string")' >/dev/null 2>&1 <<<"$CHECKS" ||
            usage "checks が文字列の JSON の配列ではありません"
    fi
    if [ -n "$DETAIL" ]; then
        jq -e 'type == "object"' >/dev/null 2>&1 <<<"$DETAIL" || usage "detail が JSON のオブジェクトではありません"
    fi
    [ -z "$CAUSE" ] || [[ "$CAUSE" =~ ^[a-z0-9]+(-[a-z0-9]+)*$ ]] || usage "理由の種類の形が違います"
    REPO="${GITHUB_REPOSITORY:-}"
    [[ "$REPO" =~ ^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$ ]] || usage "GITHUB_REPOSITORY の形が違います"
    SERVER="${GITHUB_SERVER_URL:-https://github.com}"
    [[ "$SERVER" =~ ^https://[A-Za-z0-9.-]+$ ]] || usage "GITHUB_SERVER_URL の形が違います"
    if [ -n "$PR_URL" ]; then
        [[ "$PR_URL" == "${SERVER}/${REPO}/pull/"* ]] && [[ "${PR_URL#"${SERVER}/${REPO}/pull/"}" =~ ^[1-9][0-9]*$ ]] ||
            usage "PR の URL がこのリポジトリの PR の URL ではありません"
    fi
    [ "$OUTCOME" != pr ] || [ -n "$PR_URL" ] || usage "結果が pr なのに PR の URL がありません"
    RUN_ID="${GITHUB_RUN_ID:-}"
    [[ "$RUN_ID" =~ ^[1-9][0-9]*$ ]] || usage "GITHUB_RUN_ID の形が違います"
    HEAD_SHA="${CAF_HEAD_SHA:-}"
    [ -z "$HEAD_SHA" ] || [[ "$HEAD_SHA" =~ ^[0-9a-f]{40}$ ]] || usage "CAF_HEAD_SHA の形が違います"
    JOBS="${JOB_RESULTS:-}"
    [ -n "$JOBS" ] || JOBS='{}'
    if [ "$MODE" = record ]; then
        jq -e 'type == "object" and all(.[]; type == "string")' >/dev/null 2>&1 <<<"$JOBS" ||
            usage "JOB_RESULTS が、値が文字列の JSON のオブジェクトではありません"
    fi

    case "$MODE" in
    record) record ;;
    notify) notify ;;
    esac
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    main "$@"
fi
