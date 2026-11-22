#!/usr/bin/env bash
# =====================================================================
# claude-auto-fix の dispatch ジョブで、対象を集めて絞り、対象ごとの実行を起動するスクリプト
# (design.md の claude-auto-fix-dispatch.sh の節)
#
# 使い方: claude-auto-fix-dispatch.sh <trigger|manual|retry>
#   trigger  きっかけのワークフローの終わりで、そのワークフローに合う集め方で対象を集める
#   manual   所有者の手での起動で、4つの集め方をすべて使う。vuln-fix の組は、2つの vuln-fix のワークフローの
#            最新の実行の成果物から読み、まだ脆弱な組だけを残す。コンテナの Issue は、扱ったかどうかによらず、
#            修正版のある Issue をすべて対象にする。下の絞り込みの決まりの2を掛けず、決まりの3は待っているか
#            動いている実行だけを見る(要件1の5)
#   retry    1時間ごとの定期実行で、直近4日の対象ごとの実行の結果のファイルから、動かし直す対象を選ぶ。
#            対象ごとに最も新しい結果を見て、結果が unavailable か blocked で、終わった UTC の日が今日より前の
#            対象と、結果が key の対象を選び、結果のファイルに残した入力で起動する(要件6の1と2)。
#            結果を書く前に取り消された実行は unavailable と数え、vuln-fix の種類の入力 detail は、同じ key の
#            前の結果のファイルか、2つの vuln-fix のワークフローの最新の成果物の組から作る。
#            鍵の Issue が閉じてから25時間のうちは、manual と同じ集め方で対象を集め直す。コンテナの Issue は
#            この仕組みがまだ扱っていないものに限り、入力 reason を retry にして決まりの2を掛ける(要件6の4)
#
# 鍵の Issue(github-actions[bot] が起票した、題名が CAF_KEY_TITLE で本文に CAF_KEY_MARKER を持つ開いた Issue)が
# 開いている間は、retry で UTC の1日に1つだけ起動し、trigger と manual では何も起動しない(要件6の3)。
# retry の1つは、結果が key の対象から選び、直近4日に無ければ manual と同じ4つの集め方から選ぶ。
# 4つの集め方から選ぶときは、鍵を確かめられない対象を選ばないよう、決まりの2を掛ける。
#
# 環境変数:
#   GITHUB_REPOSITORY    読むリポジトリ(owner/name。必須)
#   GH_TOKEN             gh が使うトークン(GITHUB_TOKEN。必須)
#   TRIGGER_WORKFLOW     きっかけのワークフローの名前(trigger で必須)。次の4つのどれかである
#                          Frontend Transitive Vulnerability Fix  vuln-fix の組(成果物 vuln-fix-unresolved)
#                          Backend Vulnerability Fix              vuln-fix の組(成果物 vuln-fix-unresolved-java と
#                                                                 vuln-fix-unresolved-go)
#                          Audit Weekly                           main に開いたままの CodeQL の警告と、止まった
#                                                                 Dependabot の PR
#                          Scheduled Container Image Vulnerability Scan
#                                                                 修正版のあるラベル container-vuln の Issue
#   TRIGGER_RUN_ID       きっかけの実行の ID(trigger で必須)
#   GITHUB_STEP_SUMMARY  起動した対象と、起動しなかった対象とその理由を書くファイル(無ければ書かない)
#   CAF_REQUIRED_CHECKS  期待一覧のファイル(既定は .github/audit/required-checks.json)
#   GITHUB_REPOSITORY_OWNER  check-audit-dependabot-stuck.sh が、dependency-cooldown の赤の記録を読むのに使う
#
# 絞り込みの決まり(どの対象にも、この順に掛ける):
#   1. 同じ key の Claude の変更の PR が開いていれば起動しない。vuln-fix の組では、同じ組の vuln-fix の
#      ブランチ(chore/ に、Claude の変更のブランチ名の fix/claude-auto-fix- より後ろを付けた名前)が
#      あるときも起動しない(要件4の3)
#      赤の検査を直す実行(入力 pr を持つ実行)を動かし直すときは、この決まりを掛けない
#   2. github-actions[bot] が起票した、同じ key の目印を本文に持つ開いている知らせの Issue の状態が
#      unfixed なら起動しない(要件4の4)。状態が unavailable なら起動する(要件6の2)。
#      この決まりは、trigger と、retry で集め直した対象と、鍵を確かめる1つを4つの集め方から選ぶときに掛ける
#   3. 同じ表示名の対象ごとの実行が、終わっていないか、UTC の今日に作られていれば起動しない
#      (manual では、終わっていない実行だけを見る)
# 種類が container のときは、trigger と retry の集め直しでは、絞り込みの前に、次の Issue を外す(要件1の3、要件4の4)。
# manual では1つ目だけを、鍵を確かめる1つを選ぶときは1つ目と、kind=unfixed の目印のコメントだけを外す。
#   - github-actions[bot] が書いた最新の container-scan-state の目印の rows に、fixed が true の行が無い
#   - github-actions[bot] が書いた claude-auto-fix-notice の目印のコメントがある(kind=unfixed のときは
#     直せなかったことを書いたコメントがある、ほかの kind のときはこの仕組みが1度扱った、と書く)
#   - その脆弱性の ID を key に持つ Claude の変更の PR が、閉じたものも含めて1つでもある
# 利用者が書いた Issue、PR、コメントの中身は、対象を選ぶ材料にしない。github-actions[bot] が書いた
# 目印だけを読み、PR はこのリポジトリのブランチから出されてラベル claude-auto-fix を持つものだけを数える。
#
# 起動は gh workflow run claude-auto-fix-target.yaml --ref main で行い、入力 kind key reason と、
# 空でなければ pr(赤の検査を直す実行の PR の番号)と checks(種類 dependabot の、5つの検査を除いた赤の検査の
# 名前か、赤の検査を直す実行の赤の検査の名前)と detail(vuln-fix の組)を渡す。
# 入力 reason は、trigger と manual では形の名前、retry では結果のファイルの reason(空なら retry)にする。
# 同じ入力で何度動かしても、起動される実行は増えない。起動する前に、対象ごとの実行の一覧を読み、
# このスクリプトで起動した実行の表示名も覚えておくためである。
#
# 1つの集め方か1つの対象で API が失敗しても、ほかの集め方と対象を続け、::error:: の行を出して
# 最後に1で終わる。このスクリプトは Issue と PR とコメントを書かない。
# 引数と環境の誤りは 2 で終わる。
# =====================================================================
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=.github/scripts/lib-claude-auto-fix.sh
. "$HERE/lib-claude-auto-fix.sh"

usage() {
    echo "::error::claude-auto-fix-dispatch: $1" >&2
    echo "使い方: claude-auto-fix-dispatch.sh <trigger|manual|retry>" >&2
    exit 2
}
FAILED=0
err() {
    echo "::error::claude-auto-fix-dispatch: $1" >&2
    FAILED=1
}
summary() {
    printf '%s\n' "$1" >>"$SUMMARY" || err "GITHUB_STEP_SUMMARY に書けません"
}

[ $# -eq 1 ] || usage "引数は1つです(${#}個でした)"
MODE="$1"
case "$MODE" in
trigger | manual | retry) ;;
*) usage "知らない形です: ${MODE}" ;;
esac
REPO=$(_caf_repo) || usage "GITHUB_REPOSITORY がありません"
[[ "$REPO" =~ ^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$ ]] || usage "GITHUB_REPOSITORY の形が違います"
OWNER="${REPO%%/*}"
[ -n "${GH_TOKEN:-}" ] || usage "GH_TOKEN がありません"
REQUIRED="${CAF_REQUIRED_CHECKS:-$HERE/../audit/required-checks.json}"
[ -f "$REQUIRED" ] || usage "期待一覧がありません: ${REQUIRED}"
SUMMARY="${GITHUB_STEP_SUMMARY:-/dev/null}"
TRIGGER_WORKFLOW="${TRIGGER_WORKFLOW:-}"
TRIGGER_RUN_ID="${TRIGGER_RUN_ID:-}"
if [ "$MODE" = trigger ]; then
    case "$TRIGGER_WORKFLOW" in
    "Frontend Transitive Vulnerability Fix" | "Backend Vulnerability Fix" | "Audit Weekly" | \
        "Scheduled Container Image Vulnerability Scan") ;;
    *) usage "TRIGGER_WORKFLOW が、きっかけの4つのワークフローのどれでもありません: ${TRIGGER_WORKFLOW}" ;;
    esac
    [[ "$TRIGGER_RUN_ID" =~ ^[1-9][0-9]*$ ]] || usage "TRIGGER_RUN_ID の形が違います"
fi
FW_NAME="Frontend Transitive Vulnerability Fix"
BW_NAME="Backend Vulnerability Fix"

TMP=$(mktemp -d) || usage "一時のフォルダを作れません"
trap 'rm -rf -- "$TMP"' EXIT
TODAY=$(date -u +%Y-%m-%d)

# --- どの対象の絞り込みにも使う一覧 ------------------------------------------------------
# 3つの一覧のどれかを読めなければ、どの対象も絞り込めないので、何も起動せずに終わる
if ! claude_prs >"$TMP/prs.json"; then
    echo "::error::claude-auto-fix-dispatch: 開いている Claude の変更の PR を読めないので、何も起動しません" >&2
    exit 1
fi
cutoff=$(date -u -d "@$(($(date -u +%s) - 4 * 86400))" +%Y-%m-%dT%H:%M:%SZ)
# 対象ごとの実行の一覧は、直近4日に作られたものを読む。終わっていない実行と、今日の実行を数えるためである。
# 数えるのは、このリポジトリの main で手で起動された実行だけにする(lib-claude-auto-fix.sh の own_run)。
# fork の PR の実行を数えると、PR の題名にした表示名で、利用者が対象の起動を止められるためである
#   active.txt  終わっていない実行の表示名
#   today.txt   UTC の今日に作られた実行の表示名
if ! gh api --paginate --slurp "repos/${REPO}/actions/workflows/${CAF_TARGET_WORKFLOW}/runs?created=%3E%3D${cutoff}&per_page=100" \
    >"$TMP/target-runs.json" ||
    ! jq -c --arg repo "$REPO" "$_CAF_JQ_OWN_RUN"'
        if type == "array" and all(type == "object" and (.workflow_runs | type) == "array") then [.[].workflow_runs[]]
        else error("x") end
        | map(select(type == "object" and own_run($repo)))' "$TMP/target-runs.json" >"$TMP/target-runs-flat.json" 2>/dev/null ||
    ! jq -r '.[] | select((.status // "") != "completed") | .display_title // empty' "$TMP/target-runs-flat.json" \
        >"$TMP/active.txt" 2>/dev/null ||
    ! jq -r --arg today "$TODAY" '.[] | select((.created_at // "") | startswith($today)) | .display_title // empty' \
        "$TMP/target-runs-flat.json" >"$TMP/today.txt" 2>/dev/null; then
    echo "::error::claude-auto-fix-dispatch: 対象ごとの実行の一覧を読めないので、何も起動しません" >&2
    exit 1
fi
if ! gh api --paginate --slurp "repos/${REPO}/issues?labels=${CAF_LABEL}&state=open&per_page=100" >"$TMP/issues-caf.json" ||
    ! jq -e "$_CAF_JQ_PAGES"'pages | true' "$TMP/issues-caf.json" >/dev/null 2>&1; then
    echo "::error::claude-auto-fix-dispatch: ラベル ${CAF_LABEL} の Issue を読めないので、何も起動しません" >&2
    exit 1
fi

if [ "$MODE" = trigger ]; then
    summary "## claude-auto-fix の振り分け(${MODE}: ${TRIGGER_WORKFLOW})"
else
    summary "## claude-auto-fix の振り分け(${MODE})"
fi
summary ""

# 鍵の Issue が開いているか。github-actions[bot] が起票した、題名と本文の目印が合う Issue だけを数える
KEY_OPEN=no
key_numbers=$(key_issues <"$TMP/issues-caf.json") || {
    echo "::error::claude-auto-fix-dispatch: 鍵の Issue が開いているかを読めないので、何も起動しません" >&2
    exit 1
}
[ -z "$key_numbers" ] || KEY_OPEN=yes
# 鍵の Issue が開いている間に retry で起動してよい1つが残っていれば yes。1つ起動したら PROBED を yes にする
PROBE_SLOT=no
PROBED=no
probe_done() { [ "$PROBED" = yes ]; }
if [ "$KEY_OPEN" = yes ] && [ "$MODE" != retry ]; then
    summary "- 鍵の Issue が開いているので、何も起動しない(鍵を確かめる1つは、1時間ごとの動かし直しで起動する)"
    exit 0
fi

# 対象の呼び名。CodeQL の警告は、番号だけを書く(要件5の1)
label_of() {
    if [ "$1" = codeql ]; then
        printf 'CodeQL の警告 #%s' "$2"
    else
        printf '%s %s' "$1" "$2"
    fi
}
skip() {
    summary "- 起動しなかった: $(label_of "$1" "$2")($3)"
}

# unfixed_issue <種類> <key>
#   状態が unfixed の知らせの Issue が開いていれば yes、無ければ no を出す。読めなければ1を返す
unfixed_issue() {
    local kind="$1" key="$2" numbers n comments list state
    numbers=$(jq -r --arg bot "$CAF_BOT_LOGIN" --arg mark "claude-auto-fix-issue key=${kind}:${key} " "$_CAF_JQ_PAGES"'
        pages
        | .[] | select((has("pull_request") | not) and (.user.login? // "") == $bot
            and ((.body // "") | type) == "string" and ((.body // "") | contains($mark)))
        | .number | tostring' "$TMP/issues-caf.json" 2>/dev/null) || return 1
    while IFS= read -r n; do
        [ -n "$n" ] || continue
        [[ "$n" =~ ^[1-9][0-9]*$ ]] || return 1
        comments=$(gh api --paginate --slurp "repos/${REPO}/issues/${n}/comments?per_page=100") || return 1
        # latest_marker は created_at が同じ項目を渡した順に並べるので、本文を先に、コメントを後ろに並べる
        list=$(jq -c --argjson n "$n" --slurpfile issues "$TMP/issues-caf.json" "$_CAF_JQ_PAGES"'
            ($issues[0] | pages | map(select(.number == $n))[0:1]) + pages' <<<"$comments" 2>/dev/null) || return 1
        state=$(issue_state "$kind" "$key" <<<"$list") || return 1
        if [ "$state" = unfixed ]; then
            echo yes
            return 0
        fi
    done <<<"$numbers"
    echo no
}

# branch_exists <ブランチ名>
#   origin にそのブランチがあれば yes、無ければ no を出す。読めなければ1を返す
branch_exists() {
    local out
    out=$(gh api --paginate --slurp "repos/${REPO}/git/matching-refs/heads/$1?per_page=100") || return 1
    jq -r --arg ref "refs/heads/$1" "$_CAF_JQ_PAGES"'pages | if any(.[]; .ref? == $ref) then "yes" else "no" end' \
        <<<"$out" 2>/dev/null
}

# consider <種類> <key> <checks> <detail> <reason> <決まりの2を掛けるか(yes|no)> [<PR の番号> <head の SHA>]
#   絞り込みの決まりを掛け、残れば対象ごとの実行を起動する
consider() {
    local kind="$1" key="$2" checks="$3" detail="$4" reason="$5" unfixed="$6" pr="${7:-}" sha="${8:-}"
    local names branch name st label
    local -a inputs
    label=$(label_of "$kind" "$key")
    if [ "$KEY_OPEN" = yes ] && [ "$PROBE_SLOT" != yes ]; then
        skip "$kind" "$key" "鍵の Issue が開いている間は、鍵を確かめる1つのほかは起動しない"
        return 0
    fi
    if [ -n "$pr" ]; then
        names=$(target_names "$kind" "$key" "$pr" "$sha")
    else
        names=$(target_names "$kind" "$key")
    fi || {
        err "${label}: ブランチ名と表示名を作れません"
        return 0
    }
    branch=$(jq -r .branch <<<"$names")
    name=$(jq -r .run_name <<<"$names")
    # 赤の検査を直す実行は、開いている Claude の変更の PR の上で動くので、決まりの1を掛けない
    if [ -z "$pr" ]; then
        if jq -e --arg b "$branch" 'any(.[]; .branch == $b)' "$TMP/prs.json" >/dev/null; then
            skip "$kind" "$key" "同じ対象の Claude の変更の PR が開いている"
            return 0
        fi
        case "$kind" in
        npm | maven | go-stdlib | go-module)
            st=$(branch_exists "chore/${branch#"$CAF_BRANCH_PREFIX"}") || {
                err "${label}: 同じ組の vuln-fix のブランチがあるかを読めません"
                return 0
            }
            if [ "$st" = yes ]; then
                skip "$kind" "$key" "同じ組の vuln-fix のブランチがある"
                return 0
            fi
            ;;
        esac
    fi
    if [ "$unfixed" = yes ]; then
        st=$(unfixed_issue "$kind" "$key") || {
            err "${label}: 直せなかったことを知らせる Issue を読めません"
            return 0
        }
        if [ "$st" = yes ]; then
            skip "$kind" "$key" "直せなかったことを知らせる Issue が開いている"
            return 0
        fi
    fi
    if grep -Fxq -- "$name" "$TMP/active.txt" || { [ "$MODE" != manual ] && grep -Fxq -- "$name" "$TMP/today.txt"; }; then
        skip "$kind" "$key" "同じ表示名の実行が、待っているか動いているか、今日すでにある"
        return 0
    fi
    inputs=(-f "kind=${kind}" -f "key=${key}" -f "reason=${reason}")
    [ -z "$pr" ] || inputs+=(-f "pr=${pr}")
    [ -z "$checks" ] || inputs+=(-f "checks=${checks}")
    [ -z "$detail" ] || inputs+=(-f "detail=${detail}")
    # 赤の検査を直す実行の表示名は、PR の head の SHA の先頭12文字を持つ。対象ごとの実行は、SHA を表示名にだけ使う
    [ -z "$sha" ] || inputs+=(-f "head=${sha:0:12}")
    if ! gh workflow run "$CAF_TARGET_WORKFLOW" --ref main -R "$REPO" "${inputs[@]}" </dev/null >/dev/null; then
        err "${label}: 対象ごとの実行を起動できません"
        return 0
    fi
    printf '%s\n' "$name" >>"$TMP/active.txt"
    printf '%s\n' "$name" >>"$TMP/today.txt"
    if [ "$KEY_OPEN" = yes ]; then
        PROBE_SLOT=no
        PROBED=yes
    fi
    summary "- 起動した: ${label}"
}

# --- きっかけの実行 ------------------------------------------------------------------------
# own_trigger_run <実行の ID> <ワークフローの名前> <ワークフローのファイル> [認める起動のしかた]
#   きっかけの実行が、このリポジトリのそのワークフローのファイルの、認める起動のしかたの実行のときだけ、
#   実行の結論を TRIGGER_CONCLUSION に入れる。そうでなければ、理由を書いて1を返す。ワークフローの名前は、ほかのリポジトリからの
#   PR のワークフローでも同じ名前を付けられるので、名前だけで実行を信じると、利用者が書いた PR をきっかけにして
#   Claude を動かすおそれがあるためである(要件1の6)。err の FAILED=1 を残すため、$(...) の中で呼ばない
#   認める起動のしかたは、空白で区切った event の名前で、既定は決まった時刻(schedule)と手の起動(workflow_dispatch)。
#   push と workflow_run は、このリポジトリの main のブランチで動いた実行だけを認める。コンテナの定期検査は、
#   本番のリリースのあとと main への push のあとにも動くためである
own_trigger_run() {
    local id="$1" wname="$2" file="$3" events="${4:-schedule workflow_dispatch}" run
    TRIGGER_CONCLUSION=
    run=$(gh api "repos/${REPO}/actions/runs/${id}") || {
        err "${wname} の実行 ${id} を読めません"
        return 1
    }
    TRIGGER_CONCLUSION=$(jq -r --arg w "$wname" --arg repo "$REPO" --arg path ".github/workflows/${file}" --arg events "$events" '
        ($events | split(" ")) as $evs
        | if .name == $w and ((.event // "") | type) == "string" and (.event as $e | $evs | index($e)) != null
            and ((.event | IN("push", "workflow_run") | not) or (.head_branch // "") == "main")
            and (.repository.full_name? // "") == $repo and (.head_repository.full_name? // "") == $repo
            and ((.path // "") | type) == "string" and ((.path // "") | split("@")[0]) == $path
        then (.conclusion // "") else error("x") end' <<<"$run" 2>/dev/null) || {
        err "実行 ${id} は、このリポジトリの ${file} の、認める起動のしかた(${events})の実行ではありません"
        return 1
    }
}

# --- vuln-fix の組 -------------------------------------------------------------------------
# read_vuln_run <実行の ID> <ワークフローの名前> <ワークフローのファイル> <出すファイル> <成果物の名前>...
#   実行が、このリポジトリのそのワークフローのファイルの、決まった時刻か手で起動された実行のときだけ(own_trigger_run)、
#   成果物を読み、組を1行に1つの {kind, group} で出すファイルに書く。名前だけで実行を信じると、利用者が作った
#   成果物を対象を選ぶ材料にするおそれがあるためである(要件1の6)。実行の結論が failure でなければ、組を書かない
read_vuln_run() {
    local id="$1" wname="$2" file="$3" out="$4" conclusion art dir kinds
    shift 4
    : >"$out"
    own_trigger_run "$id" "$wname" "$file" || return 0
    conclusion=$TRIGGER_CONCLUSION
    if [ "$conclusion" != failure ]; then
        summary "- ${wname} の実行 ${id} の結論が failure でない(${conclusion:-未定})ので、vuln-fix の組を集めません"
        return 0
    fi
    for art in "$@"; do
        case "$art" in
        vuln-fix-unresolved) kinds='["npm"]' ;;
        vuln-fix-unresolved-java) kinds='["maven"]' ;;
        *) kinds='["go-stdlib","go-module"]' ;;
        esac
        dir="$TMP/art-${id}-${art}"
        mkdir -p "$dir"
        if ! gh run download "$id" -R "$REPO" -n "$art" -D "$dir" >/dev/null 2>&1 ||
            [ ! -f "$dir/vuln-fix-unresolved.jsonl" ]; then
            err "実行 ${id} の成果物 ${art} を読めません"
            continue
        fi
        # 形の違う行が1つでもあれば、その成果物の組を1つも起動しない。成果物ごとに一時のファイルに書き、
        # すべての行を読めたときだけ足す
        if ! jq -c --argjson kinds "$kinds" '
            if type == "object" and (.kind | IN($kinds[])) and (.group | type) == "object" then {kind, group}
            else error("x") end' "$dir/vuln-fix-unresolved.jsonl" >"$dir/groups.jsonl" 2>/dev/null; then
            err "実行 ${id} の成果物 ${art} の形が違うので、この成果物の組を起動しません"
            continue
        fi
        cat "$dir/groups.jsonl" >>"$out" || {
            err "実行 ${id} の成果物 ${art} の組を書き写せません"
            continue
        }
    done
}

# key_vuln_groups <{kind, group} のファイル> <出すファイル>
#   Go の標準ライブラリの組は、修正版の最も新しい版と、OSV の ID のすべてで1つの対象にする(要件1の1)。
#   ほかの組は、種類と key が同じものを1つにする。1行に1つの {kind, key, group} で書く
key_vuln_groups() {
    local in="$1" out="$2" entries entry kind group key
    : >"$out"
    entries=$(jq -cs "$_CAF_JQ_VKEY"'
        (map(select(.kind == "go-stdlib")) | if length == 0 then []
            else map(.group) as $g
                | [{kind: "go-stdlib", group: (($g | max_by(.version | vkey)) + {osv: ($g | map(.osv // []) | add | unique)})}] end)
        + map(select(.kind != "go-stdlib"))
        | .[]' "$in" 2>/dev/null) || {
        err "vuln-fix の組をまとめられません"
        return 0
    }
    while IFS= read -r entry; do
        [ -n "$entry" ] || continue
        kind=$(jq -r .kind <<<"$entry")
        group=$(jq -c .group <<<"$entry")
        key=$(target_key "$kind" "$group") || {
            err "vuln-fix の組から key を作れません(種類 ${kind})"
            continue
        }
        if jq -e --arg k "$kind" --arg key "$key" 'select(.kind == $k and .key == $key)' "$out" >/dev/null 2>&1; then
            continue
        fi
        jq -nc --arg k "$kind" --arg key "$key" --argjson g "$group" '{kind: $k, key: $key, group: $g}' >>"$out"
    done <<<"$entries"
}

# start_vuln <{kind, key, group} のファイル> <まだ脆弱かを確かめるか(yes|no)> <reason> <決まりの2を掛けるか>
start_vuln() {
    local file="$1" check="$2" reason="$3" unfixed="$4" line kind key group gone
    while IFS= read -r line; do
        probe_done && return 0
        [ -n "$line" ] || continue
        kind=$(jq -r .kind <<<"$line")
        key=$(jq -r .key <<<"$line")
        group=$(jq -c .group <<<"$line")
        if [ "$check" = yes ]; then
            gone=$(target_gone "$kind" "$key") || {
                err "$(label_of "$kind" "$key"): main でまだ脆弱かを読めません"
                continue
            }
            if [ "$gone" = true ]; then
                skip "$kind" "$key" "main ではもう脆弱でない"
                continue
            fi
        fi
        consider "$kind" "$key" "" "$group" "$reason" "$unfixed"
    done <"$file"
}

# trigger: きっかけの実行の成果物から集める。collect_vuln_trigger <ワークフローのファイル> <成果物の名前>...
collect_vuln_trigger() {
    local file="$1"
    shift
    read_vuln_run "$TRIGGER_RUN_ID" "$TRIGGER_WORKFLOW" "$file" "$TMP/vuln.jsonl" "$@"
    key_vuln_groups "$TMP/vuln.jsonl" "$TMP/vuln-keyed.jsonl"
    start_vuln "$TMP/vuln-keyed.jsonl" no "$MODE" yes
}

# latest_vuln_run <ワークフローの名前> <ワークフローのファイル> <出すファイル> <成果物の名前>...
#   そのワークフローの、このリポジトリの main で決まった時刻か手で起動された、終わった実行のうち、最も新しい
#   実行の成果物を読む
latest_vuln_run() {
    local wname="$1" file="$2" out="$3" raw id
    shift 3
    : >"$out"
    raw=$(gh api --paginate --slurp "repos/${REPO}/actions/workflows/${file}/runs?branch=main&status=completed&per_page=30") || {
        err "${wname} の実行の一覧を読めません"
        return 0
    }
    id=$(jq -r --arg repo "$REPO" '
        if type == "array" and all(type == "object" and (.workflow_runs | type) == "array") then [.[].workflow_runs[]]
        else error("x") end
        | map(select((.event // "" | IN("schedule", "workflow_dispatch")) and .status == "completed"
            and (.repository.full_name? // "") == $repo and (.head_repository.full_name? // "") == $repo))
        | sort_by(.created_at // "", .id) | last | .id // empty
        | if type == "number" and . == floor and . > 0 then tostring else error("x") end' <<<"$raw" 2>/dev/null) || {
        err "${wname} の実行の一覧の形が違います"
        return 0
    }
    if [ -z "$id" ]; then
        summary "- ${wname} の、決まった時刻か手で起動された main の実行が無いので、その vuln-fix の組を集めません"
        return 0
    fi
    read_vuln_run "$id" "$wname" "$file" "$out" "$@"
}

# latest_vuln
#   2つの vuln-fix のワークフローの最新の実行の成果物の組を、1行に1つの {kind, key, group} で
#   $TMP/latest-vuln-keyed.jsonl に書く。1回の振り分けで1度だけ読む
latest_vuln() {
    [ ! -f "$TMP/latest-vuln-keyed.jsonl" ] || return 0
    latest_vuln_run "$FW_NAME" frontend-vuln-fix.yaml "$TMP/latest-fw.jsonl" vuln-fix-unresolved
    latest_vuln_run "$BW_NAME" backend-vuln-fix.yaml "$TMP/latest-bw.jsonl" vuln-fix-unresolved-java vuln-fix-unresolved-go
    cat "$TMP/latest-fw.jsonl" "$TMP/latest-bw.jsonl" >"$TMP/latest-vuln.jsonl"
    key_vuln_groups "$TMP/latest-vuln.jsonl" "$TMP/latest-vuln-keyed.jsonl"
}

# manual と retry の集め直し: 最新の実行の成果物の組のうち、まだ脆弱な組を起動する
# collect_vuln_latest <reason> <決まりの2を掛けるか>
collect_vuln_latest() {
    latest_vuln
    start_vuln "$TMP/latest-vuln-keyed.jsonl" yes "$1" "$2"
}

# --- CodeQL の警告(trigger: Audit Weekly、manual、retry の集め直し) ---------------------------
# collect_codeql <reason> <決まりの2を掛けるか>
collect_codeql() {
    local reason="$1" unfixed="$2" raw numbers n
    probe_done && return 0
    raw=$(gh api --paginate --slurp "repos/${REPO}/code-scanning/alerts?ref=refs/heads/main&tool_name=CodeQL&state=open&per_page=100") || {
        err "main の CodeQL の警告を読めません"
        return 0
    }
    numbers=$(jq -r "$_CAF_JQ_PAGES"'pages | .[] | select(.state == "open") | .number
        | if type == "number" and . == floor and . > 0 then tostring else error("x") end' <<<"$raw" 2>/dev/null) || {
        err "main の CodeQL の警告の形が違います"
        return 0
    }
    while IFS= read -r n; do
        probe_done && return 0
        [ -n "$n" ] || continue
        consider codeql "$n" "" "" "$reason" "$unfixed"
    done <<<"$numbers"
}

# --- 止まった Dependabot の PR(trigger: Audit Weekly、manual、retry の集め直し) ---------------------
# collect_stuck <reason> <決まりの2を掛けるか>
collect_stuck() {
    local reason="$1" unfixed="$2" rc=0 entries entry n red checks
    probe_done && return 0
    STUCK_JSON_OUT="$TMP/stuck.json" GITHUB_STEP_SUMMARY=/dev/null \
        bash "$HERE/check-audit-dependabot-stuck.sh" "$REQUIRED" >&2 || rc=$?
    case "$rc" in
    0 | 1) ;;
    *)
        err "止まった Dependabot の PR を判定できません(終わり方 ${rc})"
        return 0
        ;;
    esac
    entries=$(jq -c 'if type == "array" then .[] else error("x") end' "$TMP/stuck.json" 2>/dev/null) || {
        err "止まった PR の一覧の形が違います"
        return 0
    }
    while IFS= read -r entry; do
        probe_done && return 0
        [ -n "$entry" ] || continue
        if ! n=$(jq -r '.number | if type == "number" and . == floor and . > 0 then tostring else error("x") end' \
            <<<"$entry" 2>/dev/null) || ! red=$(jq -c '[.red[].name] | unique' <<<"$entry" 2>/dev/null); then
            err "止まった PR の一覧の要素の形が違います"
            continue
        fi
        checks=$(fixable_red_checks "$REQUIRED" "$red") || {
            err "PR #${n} の赤の検査から5つの検査を除けません"
            continue
        }
        if [ "$(jq 'length' <<<"$checks")" -eq 0 ]; then
            skip dependabot "$n" "赤の検査が、直しても緑にならない5つの検査だけ"
            continue
        fi
        consider dependabot "$n" "$checks" "" "$reason" "$unfixed"
    done <<<"$entries"
}

# --- ラベル container-vuln の Issue(trigger: 定期のコンテナの検査) -----------------------------
# handled_pr <脆弱性の ID>
#   その ID を key に持つ Claude の変更の PR が、閉じたものも含めてあれば yes、無ければ no を出す
handled_pr() {
    local names branch out
    names=$(target_names container "$1") || return 1
    branch=$(jq -r .branch <<<"$names")
    out=$(gh api --paginate --slurp "repos/${REPO}/pulls?state=all&head=${OWNER}:${branch}&per_page=100") || return 1
    jq -r --arg b "$branch" --arg repo "$REPO" --arg label "$CAF_LABEL" "$_CAF_JQ_PAGES"'
        pages
        | if any(.[]; .head.ref? == $b and (.head.repo.full_name? // "") == $repo and any(.labels[]?; .name? == $label))
          then "yes" else "no" end' <<<"$out" 2>/dev/null
}

# collect_container <外し方> <reason> <決まりの2を掛けるか>
#   外し方は次の3つである
#     unhandled    修正版の無い Issue と、この仕組みが1度扱った Issue を外す(trigger と retry の集め直し)
#     all          修正版の無い Issue だけを外す(manual)
#     not-unfixed  修正版の無い Issue と、直せなかったことを書いたコメントのある Issue を外す(鍵を確かめる1つ)
collect_container() {
    local how="$1" reason="$2" unfixed="$3" raw issues issue n id comments list fixed mark st
    probe_done && return 0
    raw=$(gh api --paginate --slurp "repos/${REPO}/issues?labels=container-vuln&state=open&per_page=100") || {
        err "ラベル container-vuln の Issue を読めません"
        return 0
    }
    # github-actions[bot] が起票した、題名が「コンテナ脆弱性: <ID>」の Issue だけを読む
    issues=$(jq -c --arg bot "$CAF_BOT_LOGIN" --arg p "$CAF_CONTAINER_TITLE_PREFIX" "$_CAF_JQ_PAGES"'
        pages
        | .[] | select((has("pull_request") | not) and (.user.login? // "") == $bot
            and ((.title // "") | type) == "string" and ((.title // "") | startswith($p)))
        | {number, id: (.title | ltrimstr($p)), user, body: (.body // ""), created_at}' <<<"$raw" 2>/dev/null) || {
        err "ラベル container-vuln の Issue の形が違います"
        return 0
    }
    while IFS= read -r issue; do
        probe_done && return 0
        [ -n "$issue" ] || continue
        n=$(jq -r '.number | tostring' <<<"$issue")
        id=$(jq -r .id <<<"$issue")
        [[ "$n" =~ ^[1-9][0-9]*$ ]] || {
            err "ラベル container-vuln の Issue の番号の形が違います"
            continue
        }
        _caf_valid_key "$id" || {
            summary "- 起動しなかった: Issue #${n}(題名の脆弱性の ID の形が違う)"
            continue
        }
        comments=$(gh api --paginate --slurp "repos/${REPO}/issues/${n}/comments?per_page=100") || {
            err "Issue #${n} のコメントを読めません"
            continue
        }
        list=$(jq -c --argjson issue "$issue" "$_CAF_JQ_PAGES"'[$issue] + pages' <<<"$comments" 2>/dev/null) || {
            err "Issue #${n} のコメントの形が違います"
            continue
        }
        # github-actions[bot] が書いた本文とコメントのうち最も新しい container-scan-state の目印の rows を読む
        fixed=$(jq -r --arg bot "$CAF_BOT_LOGIN" '
            [.[] | select((.user.login? // "") == $bot and (.body | type) == "string")]
            | sort_by(.created_at // "")
            | [.[] | .body | scan("<!-- container-scan-state: (\\{[^\\n]*\\}) -->") | .[0]]
            | (last // "{}") | (fromjson? // {})
            | if any(.rows[]?; .fixed? == true) then "true" else "false" end' <<<"$list" 2>/dev/null) || {
            err "Issue #${n} の状態の目印を読めません"
            continue
        }
        if [ "$fixed" != true ]; then
            skip container "$id" "修正版が無い"
            continue
        fi
        if [ "$how" = all ]; then
            consider container "$id" "" "" "$reason" "$unfixed"
            continue
        fi
        mark=$(latest_marker notice kind=unfixed <<<"$list") || {
            err "Issue #${n} の目印を読めません"
            continue
        }
        if [ -n "$mark" ]; then
            skip container "$id" "直せなかったことを書いたコメントがある"
            continue
        fi
        if [ "$how" = not-unfixed ]; then
            consider container "$id" "" "" "$reason" "$unfixed"
            continue
        fi
        mark=$(latest_marker notice <<<"$list") || {
            err "Issue #${n} の目印を読めません"
            continue
        }
        if [ -n "$mark" ]; then
            skip container "$id" "この仕組みが1度扱った"
            continue
        fi
        st=$(handled_pr "$id") || {
            err "${id} の Claude の変更の PR を読めません"
            continue
        }
        if [ "$st" = yes ]; then
            skip container "$id" "この仕組みが1度扱った"
            continue
        fi
        consider container "$id" "" "" "$reason" "$unfixed"
    done <<<"$issues"
}

# --- 1時間ごとの動かし直し(retry) --------------------------------------------------------
# retry_outcome <結果のファイルの JSON> <決まりの2を掛けるか>
#   結果のファイルに残した入力で、対象ごとの実行を起動する。reason が空なら retry にする。
#   vuln-fix の種類で detail が無ければ、2つの vuln-fix のワークフローの最新の成果物の組から作る。
#   赤の検査を直す実行(pr を持つ実行)は、その PR が開いていれば、今の head の SHA で起動する
retry_outcome() {
    local rec="$1" unfixed="$2" kind key label reason checks detail pr names branch sha
    if ! kind=$(jq -r .kind <<<"$rec") || ! key=$(jq -r .key <<<"$rec") ||
        ! reason=$(jq -r '(.reason // "") | if . == "" then "retry" else . end' <<<"$rec") ||
        ! checks=$(jq -c '.checks // empty' <<<"$rec") || ! detail=$(jq -c '.detail // empty' <<<"$rec") ||
        ! pr=$(jq -r '.pr // empty | tostring' <<<"$rec"); then
        err "結果のファイルの入力を読めません"
        return 0
    fi
    label=$(label_of "$kind" "$key")
    case "$kind" in
    npm | maven | go-stdlib | go-module)
        if [ -z "$detail" ]; then
            latest_vuln
            detail=$(jq -cs --arg k "$kind" --arg key "$key" \
                'map(select(.kind == $k and .key == $key)) | first | .group // empty' "$TMP/latest-vuln-keyed.jsonl") || {
                err "${label}: vuln-fix の最新の成果物の組を読めません"
                return 0
            }
            if [ -z "$detail" ]; then
                skip "$kind" "$key" "入力 detail を作れない(前の結果のファイルにも、vuln-fix の最新の成果物にも同じ組が無い)"
                return 0
            fi
        fi
        ;;
    esac
    if [ -z "$pr" ]; then
        consider "$kind" "$key" "$checks" "$detail" "$reason" "$unfixed"
        return 0
    fi
    [[ "$pr" =~ ^[1-9][0-9]*$ ]] || {
        err "${label}: 結果のファイルの PR の番号の形が違います"
        return 0
    }
    # 赤の検査を直す実行は、入力 checks の赤の検査を直すので、checks が無ければ起動しない
    # (結果を書く前に取り消され、同じ PR の前の結果も直近4日に無いとき)
    if [ -z "$checks" ] || [ "$checks" = "[]" ]; then
        skip "$kind" "$key" "赤の検査を直す PR #${pr} の、赤の検査の名前が結果のファイルに無い"
        return 0
    fi
    names=$(target_names "$kind" "$key") || {
        err "${label}: ブランチ名と表示名を作れません"
        return 0
    }
    branch=$(jq -r .branch <<<"$names")
    sha=$(jq -r --argjson n "$pr" --arg b "$branch" \
        'map(select(.number == $n and .branch == $b)) | first | .head_sha // empty' "$TMP/prs.json") || {
        err "${label}: 開いている Claude の変更の PR を読めません"
        return 0
    }
    if [ -z "$sha" ]; then
        skip "$kind" "$key" "赤の検査を直す PR #${pr} が開いていない"
        return 0
    fi
    consider "$kind" "$key" "$checks" "$detail" "$reason" "$unfixed" "$pr" "$sha"
}

# key_closed_recently
#   github-actions[bot] が起票した鍵の Issue が、今から25時間のうちに閉じていれば yes、無ければ no を出す。
#   読めなければ1を返す
key_closed_recently() {
    local since raw numbers
    since=$(date -u -d "@$(($(date -u +%s) - 25 * 3600))" +%Y-%m-%dT%H:%M:%SZ) || return 1
    # since は更新の日時で絞る。閉じると更新されるので、25時間のうちに閉じた Issue は必ず読める
    raw=$(gh api --paginate --slurp "repos/${REPO}/issues?labels=${CAF_LABEL}&state=closed&since=${since}&per_page=100") || return 1
    numbers=$(key_issues "$since" <<<"$raw") || return 1
    if [ -n "$numbers" ]; then echo yes; else echo no; fi
}

run_retry() {
    local outcomes latest keys rec result fin st
    outcomes=$(recent_outcomes) || {
        echo "::error::claude-auto-fix-dispatch: 直近4日の結果のファイルを読めないので、何も起動しません" >&2
        exit 1
    }
    # 対象ごとに最も新しい結果を、終わった順に並べる。最も新しい結果に checks か detail が無ければ、同じ対象の
    # 同じ PR の前の結果から補う(結果を書く前に取り消された実行には、入力が残っていないため)
    latest=$(jq -c '
        group_by([.kind, .key])
        | map(sort_by(.finished_at // "") | . as $g | last as $l
            | $l + {checks: ($l.checks // ($g | map(select(.pr == $l.pr and .checks != null)) | last | .checks)),
                    detail: ($l.detail // ($g | map(select(.pr == $l.pr and .detail != null)) | last | .detail))})
        | sort_by(.finished_at // "") | .[]' <<<"$outcomes" 2>/dev/null) || {
        echo "::error::claude-auto-fix-dispatch: 直近4日の結果のファイルの形が違うので、何も起動しません" >&2
        exit 1
    }
    if [ "$KEY_OPEN" = yes ]; then
        if [ -s "$TMP/active.txt" ] || [ -s "$TMP/today.txt" ]; then
            summary "- 鍵の Issue が開いている間は UTC の1日に1つだけ起動する。待っているか動いているか、今日すでにある対象ごとの実行があるので、何も起動しない"
            return 0
        fi
        PROBE_SLOT=yes
        keys=$(jq -c 'select(.result == "key")' <<<"$latest")
        if [ -n "$keys" ]; then
            while IFS= read -r rec; do
                probe_done && break
                retry_outcome "$rec" no
            done <<<"$keys"
        else
            summary "- 鍵の Issue が開いていて、結果が key の対象が直近4日に無いので、鍵を確かめる1つを4つの集め方から1つだけ選ぶ"
            collect_vuln_latest retry yes
            collect_codeql retry yes
            collect_stuck retry yes
            collect_container not-unfixed retry yes
        fi
        return 0
    fi
    while IFS= read -r rec; do
        [ -n "$rec" ] || continue
        result=$(jq -r .result <<<"$rec")
        fin=$(jq -r '.finished_at // ""' <<<"$rec")
        case "$result" in
        unavailable | blocked)
            if [ -n "$fin" ] && ! [[ "${fin:0:10}" < "$TODAY" ]]; then
                skip "$(jq -r .kind <<<"$rec")" "$(jq -r .key <<<"$rec")" "動けなかった実行が終わったのが今日"
                continue
            fi
            retry_outcome "$rec" no
            ;;
        key) retry_outcome "$rec" no ;;
        esac
    done <<<"$latest"
    st=$(key_closed_recently) || {
        err "閉じた鍵の Issue を読めないので、対象を集め直しません"
        return 0
    }
    if [ "$st" = yes ]; then
        summary "- 鍵の Issue が閉じてから25時間のうちなので、4つの集め方で対象を集め直す"
        collect_vuln_latest retry yes
        collect_codeql retry yes
        collect_stuck retry yes
        collect_container unhandled retry yes
    fi
}

case "$MODE" in
trigger)
    case "$TRIGGER_WORKFLOW" in
    "Frontend Transitive Vulnerability Fix") collect_vuln_trigger frontend-vuln-fix.yaml vuln-fix-unresolved ;;
    "Backend Vulnerability Fix") collect_vuln_trigger backend-vuln-fix.yaml vuln-fix-unresolved-java vuln-fix-unresolved-go ;;
    "Audit Weekly")
        if own_trigger_run "$TRIGGER_RUN_ID" "$TRIGGER_WORKFLOW" audit-weekly.yaml; then
            collect_codeql trigger yes
            collect_stuck trigger yes
        fi
        ;;
    "Scheduled Container Image Vulnerability Scan")
        if own_trigger_run "$TRIGGER_RUN_ID" "$TRIGGER_WORKFLOW" container-scan-scheduled.yaml "schedule workflow_dispatch push workflow_run"; then
            collect_container unhandled trigger yes
        fi
        ;;
    esac
    ;;
manual)
    collect_vuln_latest manual no
    collect_codeql manual no
    collect_stuck manual no
    collect_container all manual no
    ;;
retry) run_retry ;;
esac

exit "$FAILED"
