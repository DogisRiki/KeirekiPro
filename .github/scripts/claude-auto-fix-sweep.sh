#!/usr/bin/env bash
# =====================================================================
# claude-auto-fix の sweep ジョブで、1時間ごとに、Claude の変更の PR と知らせの Issue の後始末をするスクリプト
# (design.md の claude-auto-fix-sweep.sh の節)
#
# 使い方: claude-auto-fix-sweep.sh(引数なし)
#   環境変数 GITHUB_REPOSITORY(owner/name)・GITHUB_REPOSITORY_OWNER・GH_TOKEN(sweep ジョブの GITHUB_TOKEN)が要る。
#   期待一覧は CAF_REQUIRED_CHECKS で替えられる(既定は .github/audit/required-checks.json)。
#
# 行うこと(Claude を動かさず、コードを checkout しない):
#   1. 開いている Claude の変更の PR(lib-claude-auto-fix.sh の claude_prs)ごとに、本文の目印
#      <!-- claude-auto-fix-pr kind=<種類> key=<key> --> から対象を読み、次の順に扱う。
#      目印が無い PR と、目印の key から作ったブランチ名が PR のブランチと違う PR は扱わない。
#      a. 対象が消えていれば(target_gone)、消えたことを書いたコメントを付けて PR を閉じ、ブランチを消す
#      b. 期待一覧で state が active で approval_gated でない検査の、head のコミットの最新の結論を読む。
#         どれかがまだ動いていれば何もしない。success・skipped・neutral のほかの結論を赤とする。
#         head のコミットで動いていない検査は数えない(パスの絞り込みで動かない検査がある)。
#         dependency-review は数える(対象ごとの実行が、直せる検査に絞り込む)
#      c. 赤の検査 X について、マージのコミットを除く最後の2つのコミットが、どちらも
#         行 `Claude-Auto-Fix-Check: X` を持てば、3回目の赤とみなす。実行を起動せず、PR を閉じて
#         ブランチを消し、claude-auto-fix-report.sh を notify unfixed の形で、閉じた PR の URL を付けて呼ぶ。
#         EDIT_OUTCOME は渡さない(鍵の Issue は、Claude が動けた実行だけが閉じる)。record の形は呼ばない
#      d. そのほかで赤があり、head のコミットについての対象ごとの実行(表示名が
#         claude-auto-fix <種類> <key> pr#<番号>@<head の SHA の先頭12文字>)が無ければ、
#         reason=red-check と PR の番号と赤の検査の名前と head の SHA の先頭12文字(入力 head)を入力にして、
#         対象ごとの実行を、専用のブランチ claude-auto-fix/run で起動する。対象ごとのワークフローは、入力 head で表示名の末尾を作る。
#         実行は、head のコミットの日時の1時間前より後に作られたものを、このリポジトリの専用のブランチ
#         claude-auto-fix/run で claude-auto-fix-target.yaml を手で起動した実行だけ数える(own_run)
#   2. 直近7日にマージされた、種類が container の Claude の変更の PR ごとに、ラベル container-vuln の
#      Issue に、本番で脆弱性が消えるのは所有者がリリースしたあとであることを書いたコメントを、
#      目印 <!-- claude-auto-fix-notice kind=merged pr=<番号> --> を付けて1回だけ付ける
#   3. 開いている知らせの Issue(ラベル claude-auto-fix で github-actions[bot] が起票した Issue)のうち、
#      目印の状態が unfixed か unavailable の Issue ごとに、対象が消えていれば、消えたことを書いた
#      コメントを付けて閉じる
#
# コメントは、決まった文だけで書き、警告の中身を書かない。PR のマージ、警告の却下、Dependabot へのコマンドを
# 行わない。同じ状態で何度呼んでも、PR と Issue の操作は増えない(コメントは目印で1回だけ付け、閉じた PR と
# Issue は開いているものの一覧に出ない)。
#
# 終わり方: 0 すべて扱えた / 1 どれかの PR か Issue の操作に失敗した(残りは続けて扱う) / 2 呼び方が違う
# =====================================================================
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=.github/scripts/lib-claude-auto-fix.sh
. "$HERE/lib-claude-auto-fix.sh" || exit 2
# shellcheck source=.github/scripts/lib-notice-comment.sh
. "$HERE/lib-notice-comment.sh" || exit 2

usage() {
    echo "::error::claude-auto-fix-sweep: $1" >&2
    echo "使い方: claude-auto-fix-sweep.sh(引数なし)" >&2
    exit 2
}
FAILED=0
err() {
    echo "::error::claude-auto-fix-sweep: $1" >&2
    FAILED=1
}
note() {
    echo "claude-auto-fix-sweep: $1" >&2
}

[ $# -eq 0 ] || usage "引数は要りません(${#}個でした)"
REPO="${GITHUB_REPOSITORY:-}"
[[ "$REPO" =~ ^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$ ]] || usage "GITHUB_REPOSITORY が無いか、形が違います"
[ -n "${GH_TOKEN:-}" ] || usage "GH_TOKEN がありません"
[ -n "${GITHUB_REPOSITORY_OWNER:-}" ] || usage "GITHUB_REPOSITORY_OWNER がありません"
REQUIRED="${CAF_REQUIRED_CHECKS:-$HERE/../audit/required-checks.json}"
[ -f "$REQUIRED" ] || usage "期待一覧がありません: ${REQUIRED}"
jq -e '(.checks | type) == "array"' "$REQUIRED" >/dev/null 2>&1 || usage "期待一覧の checks が配列ではありません: ${REQUIRED}"

TMP=$(mktemp -d) || usage "一時のフォルダを作れません"
trap 'rm -rf -- "$TMP"' EXIT

# コメントの文(決まった文だけで書く)
printf '%s\n' "この PR が直そうとした対象は、すでに消えています。そのため、claude-auto-fix の仕組みがこの PR を閉じ、ブランチを消しました。" \
    >"$TMP/gone-pr.txt" || usage "一時のファイルを書けません"
printf '%s\n' "この Issue で知らせた対象は、すでに消えています。そのため、claude-auto-fix の仕組みがこの Issue を閉じました。" \
    >"$TMP/gone-issue.txt" || usage "一時のファイルを書けません"
GONE_MARK="<!-- claude-auto-fix-notice kind=gone -->"

# PR の本文から目印の種類と key を読む: pr_marker <本文> → "<種類> <key>"
pr_marker() {
    tr -d '\r' <<<"$1" | sed -nE 's/^<!-- claude-auto-fix-pr kind=([a-z-]+) key=([^ >]+) -->$/\1 \2/p' | head -n 1
}

# PR の本文の detail の目印を JSON のオブジェクトにする。目印が無ければ空を出す。形が違えば失敗する
pr_detail() {
    local b64 json
    b64=$(tr -d '\r' <<<"$1" | sed -nE 's/^<!-- claude-auto-fix-detail ([A-Za-z0-9+\/=]+) -->$/\1/p' | head -n 1)
    [ -n "$b64" ] || return 0
    json=$(printf '%s' "$b64" | base64 -d 2>/dev/null) || return 1
    jq -ce 'if type == "object" then . else error("x") end' <<<"$json" 2>/dev/null
}

close_pr() {
    local n="$1" branch="$2"
    gh api -X PATCH "repos/${REPO}/pulls/${n}" -f state=closed >/dev/null || {
        err "PR #${n} を閉じられません"
        return 1
    }
    gh api -X DELETE "repos/${REPO}/git/refs/heads/${branch}" >/dev/null || {
        err "PR #${n} のブランチを消せません"
        return 1
    }
}

# head のコミットの赤の検査の名前を JSON の配列で出す。まだ動いている検査があれば pending を出す
red_checks() {
    local sha="$1" raw
    raw=$(gh api --paginate --slurp "repos/${REPO}/commits/${sha}/check-runs?per_page=100") || return 1
    jq -cr --slurpfile req "$REQUIRED" '
        if type == "array" and all(.[]; type == "object" and (.check_runs | type) == "array") then . else error("x") end
        | ($req[0].checks | map(select(.state == "active" and .approval_gated != true) | .context)) as $need
        | [.[].check_runs[] | select((.name | type) == "string" and (.name | IN($need[])))]
        | group_by(.name) | map(max_by([(.started_at // ""), (.id // 0)]))
        | if any(.[]; .status != "completed") then "pending"
          else [.[] | select(.conclusion | IN("success", "skipped", "neutral") | not) | .name] | unique | tojson
          end' <<<"$raw" 2>/dev/null
}

sweep_pr() {
    local pr="$1" n branch sha url body mk kind key names detail red commits strike head_date cutoff run_name raw seen inputs
    n=$(jq -r .number <<<"$pr")
    branch=$(jq -r .branch <<<"$pr")
    sha=$(jq -r .head_sha <<<"$pr")
    url=$(jq -r .url <<<"$pr")
    body=$(jq -r .body <<<"$pr")
    if ! [[ "$n" =~ ^[1-9][0-9]*$ ]] || ! [[ "$sha" =~ ^[0-9a-f]{40}$ ]]; then
        err "PR #${n} の番号か head の SHA の形が違います"
        return 1
    fi
    mk=$(pr_marker "$body")
    if [ -z "$mk" ]; then
        note "PR #${n} の本文に目印が無いため、扱いません"
        return 0
    fi
    read -r kind key <<<"$mk"
    names=$(target_names "$kind" "$key") || {
        err "PR #${n} の目印の種類か key の形が違います"
        return 1
    }
    if [ "$(jq -r .branch <<<"$names")" != "$branch" ]; then
        note "PR #${n} の目印から作ったブランチ名が、PR のブランチと違うため、扱いません"
        return 0
    fi
    detail=$(pr_detail "$body") || {
        err "PR #${n} の本文の detail の目印の形が違います"
        return 1
    }

    # a. 対象が消えた PR を閉じる
    case "$(target_gone "$kind" "$key" "$REQUIRED")" in
    true)
        notice_post "$n" "$GONE_MARK" "$TMP/gone-pr.txt" no || {
            err "PR #${n} にコメントを付けられません"
            return 1
        }
        close_pr "$n" "$branch" || return 1
        note "PR #${n} の対象が消えたため、PR を閉じました"
        return 0
        ;;
    false) ;;
    *)
        err "PR #${n} の対象が消えたかを読めません"
        return 1
        ;;
    esac

    # b. 赤の検査を読む
    red=$(red_checks "$sha") || {
        err "PR #${n} の検査の結果を読めないか、形が違います"
        return 1
    }
    if [ "$red" = pending ]; then
        note "PR #${n} の必須の検査がまだ動いているため、何もしません"
        return 0
    fi
    if [ "$red" = "[]" ]; then
        return 0
    fi

    # c. 3回続いた赤
    raw=$(gh api --paginate --slurp "repos/${REPO}/pulls/${n}/commits?per_page=100") || {
        err "PR #${n} のコミットの一覧を読めません"
        return 1
    }
    commits=$(jq -c --arg sha "$sha" "$_CAF_JQ_PAGES"'
        pages
        | if all(.[]; type == "object" and (.parents | type) == "array" and (.commit.message | type) == "string") then . else error("x") end
        | {head_date: (map(select(.sha == $sha)) | first | .commit.committer.date // ""),
           last2: (map(select((.parents | length) <= 1)) | .[-2:] | map(.commit.message | split("\n") | map(rtrimstr("\r"))))}' \
        <<<"$raw" 2>/dev/null) || {
        err "PR #${n} のコミットの一覧の形が違います"
        return 1
    }
    strike=$(jq -c --argjson red "$red" '
        . as $c
        | if ($c.last2 | length) < 2 then []
          else [$red[] | . as $x | select(all($c.last2[]; any(.[]; . == "Claude-Auto-Fix-Check: " + $x)))]
          end' <<<"$commits") || {
        err "PR #${n} の3回続いた赤を数えられません"
        return 1
    }
    if [ "$strike" != "[]" ]; then
        close_pr "$n" "$branch" || return 1
        note "PR #${n} の同じ検査の赤が3回続いたため、PR を閉じました"
        env -u EDIT_OUTCOME bash "$HERE/claude-auto-fix-report.sh" notify unfixed "$kind" "$key" red-check "$n" "$red" "$detail" "" "$url" \
            </dev/null || {
            err "PR #${n} の直せなかったことの知らせを書けません"
            return 1
        }
        return 0
    fi

    # d. 同じ head のコミットについての実行が無ければ、起動する
    head_date=$(jq -r .head_date <<<"$commits")
    cutoff=$(jq -nr --arg d "$head_date" '($d | fromdateiso8601) - 3600 | todateiso8601' 2>/dev/null) || {
        err "PR #${n} の head のコミットの日時を読めません"
        return 1
    }
    run_name=$(target_names "$kind" "$key" "$n" "$sha" | jq -r .run_name) || {
        err "PR #${n} の実行の表示名を作れません"
        return 1
    }
    raw=$(gh api --paginate --slurp "repos/${REPO}/actions/workflows/${CAF_TARGET_WORKFLOW}/runs?created=%3E%3D${cutoff}&per_page=100") || {
        err "PR #${n} の対象ごとの実行の一覧を読めません"
        return 1
    }
    seen=$(jq -r --arg repo "$REPO" --arg t "$run_name" "$_CAF_JQ_OWN_RUN"'
        if type == "array" and all(.[]; (.workflow_runs | type) == "array") then . else error("x") end
        | [.[].workflow_runs[] | select(own_run($repo))] | any(.[]; .display_title == $t)' <<<"$raw" 2>/dev/null) || {
        err "PR #${n} の対象ごとの実行の一覧の形が違います"
        return 1
    }
    if [ "$seen" = true ]; then
        note "PR #${n} の head のコミットについての対象ごとの実行があるため、何もしません"
        return 0
    fi
    inputs=(-f "kind=${kind}" -f "key=${key}" -f "reason=red-check" -f "pr=${n}" -f "checks=${red}" -f "head=${sha:0:12}")
    [ -z "$detail" ] || inputs+=(-f "detail=${detail}")
    gh workflow run "$CAF_TARGET_WORKFLOW" --ref "$CAF_RUN_BRANCH" -R "$REPO" "${inputs[@]}" </dev/null >/dev/null || {
        err "PR #${n} の赤の検査を直す実行を起動できません"
        return 1
    }
    note "PR #${n} の赤の検査を直す実行を起動しました"
}

# ---------------------------------------------------------------------
# 1. 開いている Claude の変更の PR
# ---------------------------------------------------------------------
if PRS=$(claude_prs); then
    count=$(jq 'length' <<<"$PRS")
    for ((i = 0; i < count; i++)); do
        sweep_pr "$(jq -c ".[$i]" <<<"$PRS")" || true
    done
else
    err "開いている Claude の変更の PR の一覧を読めません"
fi

# ---------------------------------------------------------------------
# 2. 直近7日にマージされた、種類が container の Claude の変更の PR
# ---------------------------------------------------------------------
SINCE=$(jq -nr 'now - 604800 | todate')
merged='[]'
merged_ok=1
for ((page = 1; page <= 10; page++)); do
    raw=$(gh api "repos/${REPO}/pulls?state=closed&sort=updated&direction=desc&per_page=100&page=${page}") || {
        err "閉じた PR の一覧を読めません"
        merged_ok=0
        break
    }
    step=$(jq -c --arg repo "$REPO" --arg prefix "$CAF_BRANCH_PREFIX" --arg label "$CAF_LABEL" --arg since "$SINCE" '
        if type == "array" then . else error("x") end
        | {more: (length == 100 and ((last.updated_at // "") >= $since)),
           prs: [.[] | select((.merged_at | type) == "string" and .merged_at >= $since
                and ((.head.ref? // "") | type) == "string" and ((.head.ref? // "") | startswith($prefix))
                and (.head.repo.full_name? // "") == $repo and any(.labels[]?; .name? == $label))
              | {number, branch: .head.ref, body: (.body // "")}]}' <<<"$raw" 2>/dev/null) || {
        err "閉じた PR の一覧の形が違います"
        merged_ok=0
        break
    }
    merged=$(jq -c --argjson a "$merged" '$a + .prs' <<<"$step")
    [ "$(jq -r .more <<<"$step")" = true ] || break
done
CONTAINER_ISSUES=""
container_issue() {
    local title="$1" raw
    if [ -z "$CONTAINER_ISSUES" ]; then
        raw=$(gh api --paginate --slurp "repos/${REPO}/issues?labels=container-vuln&state=open&per_page=100") || return 1
        CONTAINER_ISSUES=$(jq -c --arg bot "$CAF_BOT_LOGIN" "$_CAF_JQ_PAGES"'
            pages | map(select((has("pull_request") | not) and (.user.login? // "") == $bot) | {number, title})' <<<"$raw" 2>/dev/null) ||
            return 1
    fi
    jq -r --arg t "$title" 'map(select(.title == $t) | .number) | min // empty' <<<"$CONTAINER_ISSUES"
}
if [ "$merged_ok" = 1 ]; then
    count=$(jq 'length' <<<"$merged")
    for ((i = 0; i < count; i++)); do
        pr=$(jq -c ".[$i]" <<<"$merged")
        n=$(jq -r .number <<<"$pr")
        mk=$(pr_marker "$(jq -r .body <<<"$pr")")
        read -r kind key <<<"${mk:-x x}"
        [ "$kind" = container ] || continue
        names=$(target_names "$kind" "$key") || continue
        [ "$(jq -r .branch <<<"$names")" = "$(jq -r .branch <<<"$pr")" ] || continue
        issue=$(container_issue "${CAF_CONTAINER_TITLE_PREFIX}${key}") || {
            err "ラベル container-vuln の Issue を読めません"
            continue
        }
        if [ -z "$issue" ]; then
            note "PR #${n} の脆弱性の Issue が開いていないため、コメントを付けません"
            continue
        fi
        printf '%s\n' "claude-auto-fix の仕組みが作った PR #${n} がマージされました。本番のコンテナイメージからこの脆弱性が消えるのは、所有者がリリースしたあとです。" \
            >"$TMP/merged.txt" || {
            err "一時のファイルを書けません"
            continue
        }
        notice_post "$issue" "<!-- claude-auto-fix-notice kind=merged pr=${n} -->" "$TMP/merged.txt" yes ||
            err "Issue #${issue} に PR #${n} のマージのコメントを付けられません"
    done
fi

# ---------------------------------------------------------------------
# 3. 開いている知らせの Issue
# ---------------------------------------------------------------------
sweep_issue() {
    local issue="$1" n raw thread latest state k kind key
    n=$(jq -r .number <<<"$issue")
    raw=$(gh api --paginate --slurp "repos/${REPO}/issues/${n}/comments?per_page=100") || {
        err "Issue #${n} のコメントを読めません"
        return 1
    }
    thread=$(jq -c --argjson issue "$issue" "$_CAF_JQ_PAGES"'[$issue] + pages' <<<"$raw" 2>/dev/null) || {
        err "Issue #${n} のコメントの一覧の形が違います"
        return 1
    }
    latest=$(latest_marker issue <<<"$thread") || {
        err "Issue #${n} の目印を読めません"
        return 1
    }
    [ -n "$latest" ] || return 0
    state=$(jq -r '.kind // ""' <<<"$latest")
    case "$state" in
    unfixed | unavailable) ;;
    *) return 0 ;;
    esac
    k=$(jq -r '.key // ""' <<<"$latest")
    kind="${k%%:*}"
    key="${k#*:}"
    if [ -z "$kind" ] || [ "$kind" = "$k" ] || [ -z "$key" ]; then
        err "Issue #${n} の目印の key の形が違います"
        return 1
    fi
    case "$(target_gone "$kind" "$key" "$REQUIRED")" in
    true) ;;
    false) return 0 ;;
    *)
        err "Issue #${n} の対象が消えたかを読めません"
        return 1
        ;;
    esac
    notice_post "$n" "$GONE_MARK" "$TMP/gone-issue.txt" no || {
        err "Issue #${n} にコメントを付けられません"
        return 1
    }
    gh issue close "$n" --repo "$REPO" >/dev/null || {
        err "Issue #${n} を閉じられません"
        return 1
    }
    note "Issue #${n} の対象が消えたため、Issue を閉じました"
}
if raw=$(gh api --paginate --slurp "repos/${REPO}/issues?labels=${CAF_LABEL}&state=open&per_page=100") &&
    ISSUES=$(jq -c --arg bot "$CAF_BOT_LOGIN" "$_CAF_JQ_PAGES"'
        pages | map(select((has("pull_request") | not) and (.user.login? // "") == $bot and (.number | type) == "number"))' \
        <<<"$raw" 2>/dev/null); then
    count=$(jq 'length' <<<"$ISSUES")
    for ((i = 0; i < count; i++)); do
        sweep_issue "$(jq -c ".[$i]" <<<"$ISSUES")" || true
    done
else
    err "開いている知らせの Issue の一覧を読めません"
fi

exit "$FAILED"
