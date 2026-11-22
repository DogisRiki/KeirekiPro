#!/usr/bin/env bash
# =====================================================================
# claude-auto-fix-report.sh の自動テスト
#
# gh は PATH の先頭に置いた偽物に替える。偽の gh は、Issue とコメントを CAP/state.json に持ち、
# gh issue create と gh issue comment と gh issue close と、gh api の Issue の一覧とコメントの一覧と
# コメントの追加と担当者の追加を、そのファイルに反映する。受け取った引数は CAP/gh.calls に残す。
# Issue を探す・起票する・コメントする関数は、本物の lib-ledger-issue.sh と lib-notice-comment.sh を使う。
#
# 場合の名前を KP_TEST_CASE に入れると、その場合だけを流す(例: KP_TEST_CASE=record)。
# 名前は record notify-no-file unfixed-new dependabot container existing sweep red-check codeql
# key key-close pr-close unavailable-to-unfixed many api-fail unavailable-3days unavailable-not-yet blocked-days
# unavailable-open unavailable-codeql unavailable-container gone job-results usage。
# どの場合でも、終わりに、PR を閉じる操作とブランチを消す操作と、マージと却下と @dependabot を含む
# 呼び出しが無いことを確かめる。
# =====================================================================
set -uo pipefail

HERE="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$HERE/claude-auto-fix-report.sh"
WORK=$(mktemp -d) || exit 1
[ -n "$WORK" ] && [ -d "$WORK" ] || exit 1
trap 'rm -rf "$WORK"' EXIT
FAILED=0
CASE="${KP_TEST_CASE:-}"
RAN=0

ok() { echo "  ok: $1"; }
ng() { echo "  NG: $1" >&2; FAILED=1; }
expect_eq() { if [ "$2" = "$3" ]; then ok "$1"; else ng "$1(期待: [$3] 実際: [$2])"; fi; }
expect_has() { if grep -qF -- "$3" <<<"$2"; then ok "$1"; else ng "$1(含むはずの文: [$3] 実際: [$2])"; fi; }
expect_not_has() { if grep -qF -- "$3" <<<"$2"; then ng "$1(含まないはずの文: [$3] 実際: [$2])"; else ok "$1"; fi; }
want() { if [ -z "$CASE" ] || [ "$CASE" = "$1" ]; then RAN=$((RAN + 1)); echo "[$1]"; return 0; fi; return 1; }

# 知らせの Issue の状態は、本物の lib-claude-auto-fix.sh の issue_state で読む
# shellcheck source=.github/scripts/lib-claude-auto-fix.sh
. "$HERE/lib-claude-auto-fix.sh"

BOT="github-actions[bot]"
SERVER="https://github.com"
BASE_URL="$SERVER/o/r"
# バッククォート(期待の文で key をコードの形にした部分を書くのに使う)
BQ=$(printf '\140')
NPM_DETAIL='{"name":"left","version":"1.2.3","alerts":[{"html_url":"https://github.com/o/r/security/dependabot/41","severity":"high","scope":"runtime"},{"html_url":"https://evil.example.com/o/r/security/dependabot/42"}]}'

BIN="$WORK/bin"
mkdir -p "$BIN"
cat >"$BIN/gh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" | tr '\n' ' ' >>"$CAP/gh.calls"
echo >>"$CAP/gh.calls"
S="$CAP/state.json"
[ ! -e "$CAP/fail-all" ] || { echo "偽の gh: 失敗しました" >&2; exit 1; }
save() { mv "$S.tmp" "$S"; }
tick() {
    local t
    t=$(jq '.t' "$S")
    jq '.t += 1' "$S" >"$S.tmp" && save
    printf '2026-11-21T10:%02d:%02dZ' $((t / 60)) $((t % 60))
}
add_comment() {
    local at
    at=$(tick)
    jq --argjson n "$1" --rawfile b "$2" --arg at "$at" \
        '(.issues[] | select(.number == $n) | .comments) += [{user: {login: "github-actions[bot]"}, body: $b, created_at: $at}]' \
        "$S" >"$S.tmp" && save
}
VIEW='{number, title, body, state, labels: [.labels[] | {name: .}], user, created_at,
    html_url: ("https://github.com/o/r/issues/" + (.number | tostring))} + (if .pr then {pull_request: {}} else {} end)'
case "$1 ${2:-}" in
"issue create")
    shift 2
    title="" body="" labels="[]"
    while [ "$#" -gt 0 ]; do
        case "$1" in
        --repo) shift 2 ;;
        --title) title="$2"; shift 2 ;;
        --label) labels=$(jq -c --arg l "$2" '. + [$l]' <<<"$labels"); shift 2 ;;
        --body-file) body="$2"; shift 2 ;;
        *) echo "偽の gh: 知らない引数 $1" >&2; exit 1 ;;
        esac
    done
    at=$(tick)
    n=$(jq '.next' "$S")
    jq --arg t "$title" --rawfile b "$body" --argjson l "$labels" --arg at "$at" \
        '.issues += [{number: .next, title: $t, body: $b, state: "open", labels: $l,
            user: {login: "github-actions[bot]"}, created_at: $at, comments: [], pr: false}] | .next += 1' \
        "$S" >"$S.tmp" && save
    echo "https://github.com/o/r/issues/$n"
    exit 0 ;;
"issue comment")
    n="$3"
    shift 3
    while [ "$#" -gt 0 ]; do
        case "$1" in
        --repo) shift 2 ;;
        --body-file) f="$2"; shift 2 ;;
        *) echo "偽の gh: 知らない引数 $1" >&2; exit 1 ;;
        esac
    done
    add_comment "$n" "$f"
    exit 0 ;;
"issue close")
    jq --argjson n "$3" '(.issues[] | select(.number == $n) | .state) = "closed"' "$S" >"$S.tmp" && save
    echo "Closed issue #$3"
    exit 0 ;;
"run download")
    id="$3"
    shift 3
    dir=""
    while [ "$#" -gt 0 ]; do
        case "$1" in
        -R | -n) shift 2 ;;
        -D) dir="$2"; shift 2 ;;
        *) echo "偽の gh: 知らない引数 $1" >&2; exit 1 ;;
        esac
    done
    jq -e --argjson n "$id" '.runs[] | select(.id == $n) | .outcome | select(. != null)' "$S" >"$dir/outcome.json" || exit 1
    exit 0 ;;
esac
if [ "$1" = api ]; then
    shift
    method=GET path="" slurp=0 field=""
    while [ "$#" -gt 0 ]; do
        case "$1" in
        -X) method="$2"; shift 2 ;;
        --paginate) shift ;;
        --slurp) slurp=1; shift ;;
        -F | -f) field="$2"; shift 2 ;;
        repos/o/r/*) path="$1"; shift ;;
        *) echo "偽の gh: 知らない引数 $1" >&2; exit 1 ;;
        esac
    done
    p="${path%%\?*}"
    out=""
    case "$method $p" in
    "GET repos/o/r/issues")
        label=$(sed -n 's/.*[?&]labels=\([^&]*\).*/\1/p' <<<"$path")
        out=$(jq -c --arg l "$label" "[.issues[] | select(.state == \"open\" and (.labels | index(\$l))) | $VIEW]" "$S") ;;
    GET\ repos/o/r/issues/*/comments)
        n="${p#repos/o/r/issues/}"
        n="${n%/comments}"
        out=$(jq -c --argjson n "$n" '[.issues[] | select(.number == $n) | .comments[]]' "$S") ;;
    POST\ repos/o/r/issues/*/comments)
        n="${p#repos/o/r/issues/}"
        n="${n%/comments}"
        add_comment "$n" "${field#body=@}"
        echo '{}'
        exit 0 ;;
    POST\ repos/o/r/issues/*/assignees)
        echo '{"assignees":[{"login":"o"}]}'
        exit 0 ;;
    "GET repos/o/r/actions/workflows/claude-auto-fix-target.yaml/runs")
        out=$(jq -c '{workflow_runs: [.runs[] | {id, display_title: .title, status: "completed", conclusion,
            created_at: .at, updated_at: .at, html_url: ("https://github.com/o/r/actions/runs/" + (.id | tostring)),
            event: "workflow_dispatch", head_branch: "claude-auto-fix/run", repository: {full_name: "o/r"}, head_repository: {full_name: "o/r"},
            path: ".github/workflows/claude-auto-fix-target.yaml"}]}' "$S") ;;
    GET\ repos/o/r/actions/runs/*/artifacts)
        n="${p#repos/o/r/actions/runs/}"
        n="${n%/artifacts}"
        out=$(jq -c --argjson n "$n" '{artifacts: [.runs[] | select(.id == $n and .outcome != null) | {name: "outcome", expired: false}]}' "$S") ;;
    *) echo "偽の gh: 知らない呼び出し: $method $path" >&2; exit 1 ;;
    esac
    if [ "$slurp" -eq 1 ]; then printf '[%s]\n' "$out"; else printf '%s\n' "$out"; fi
    exit 0
fi
echo "偽の gh: 知らない呼び出し: $*" >&2
exit 1
EOF
chmod +x "$BIN/gh"

# --- 場合ごとの準備
new_case() {
    CAP="$WORK/cap-$1"
    mkdir -p "$CAP"
    export CAP
    echo '{"t": 0, "next": 100, "issues": [], "runs": []}' >"$CAP/state.json"
    : >"$CAP/gh.calls"
}

# 使い方: seed_issue <番号> <題名> <ラベル> <作り手> <本文>
seed_issue() {
    local at
    at=$(printf '2026-11-20T09:%02d:00Z' "$1")
    jq --argjson n "$1" --arg t "$2" --arg l "$3" --arg u "$4" --arg b "$5" --arg at "$at" \
        '.issues += [{number: $n, title: $t, body: $b, state: "open", labels: [$l], user: {login: $u},
            created_at: $at, comments: [], pr: false}]' "$CAP/state.json" >"$CAP/state.tmp" &&
        mv "$CAP/state.tmp" "$CAP/state.json"
}
# 使い方: seed_comment <番号> <作り手> <本文>
seed_comment() {
    jq --argjson n "$1" --arg u "$2" --arg b "$3" \
        '(.issues[] | select(.number == $n) | .comments) += [{user: {login: $u}, body: $b, created_at: "2026-11-20T09:59:00Z"}]' \
        "$CAP/state.json" >"$CAP/state.tmp" && mv "$CAP/state.tmp" "$CAP/state.json"
}

# 今から <秒> 前の日時。使い方: ago <秒>
ago() { date -u -d "@$(($(date -u +%s) - $1))" +%Y-%m-%dT%H:%M:%SZ; }
# 今日の UTC の 00:00:<秒> の日時。使い方: today_at <秒>
today_at() { printf '%sT00:00:%02dZ' "$(date -u +%Y-%m-%d)" "$1"; }
# 対象ごとの実行を1つ足す。使い方: seed_run <実行の ID> <種類> <key> <結果> <理由の種類> <終わった日時>
seed_run() {
    jq --argjson id "$1" --arg kind "$2" --arg key "$3" --arg r "$4" --arg c "$5" --arg at "$6" '
        .runs += [{id: $id, title: ("claude-auto-fix " + $kind + " " + $key), conclusion: "success", at: $at,
            outcome: {kind: $kind, key: $key, reason: "retry", pr: null, checks: null, detail: null, result: $r,
                cause: (if $c == "" then null else $c end), pr_url: null,
                run_url: ("https://github.com/o/r/actions/runs/" + ($id | tostring)), head_sha: null, finished_at: $at}}]' \
        "$CAP/state.json" >"$CAP/state.tmp" && mv "$CAP/state.tmp" "$CAP/state.json"
}
# 結果のファイルを書く前に取り消された実行を1つ足す。使い方: seed_cancelled <実行の ID> <種類> <key> <終わった日時>
seed_cancelled() {
    jq --argjson id "$1" --arg kind "$2" --arg key "$3" --arg at "$4" '
        .runs += [{id: $id, title: ("claude-auto-fix " + $kind + " " + $key), conclusion: "cancelled", at: $at, outcome: null}]' \
        "$CAP/state.json" >"$CAP/state.tmp" && mv "$CAP/state.tmp" "$CAP/state.json"
}
DAY=86400

created_count() { jq '[.issues[] | select(.number >= 100)] | length' "$CAP/state.json"; }
issue_field() { jq -r --argjson n "$1" ".issues[] | select(.number == \$n) | .$2" "$CAP/state.json"; }
comment_count() { jq --argjson n "$1" '[.issues[] | select(.number == $n) | .comments[]] | length' "$CAP/state.json"; }
last_comment() { jq -r --argjson n "$1" '[.issues[] | select(.number == $n) | .comments[]] | last | .body // ""' "$CAP/state.json"; }
# 本文とコメントを issue_state が読む形にする
thread_of() {
    jq -c --argjson n "$1" '.issues[] | select(.number == $n) | [{user, body, created_at}] + .comments' "$CAP/state.json"
}

# 使い方: run_report <record|notify> <outcome> <kind> <key> <reason> <pr> <checks> <detail> <理由の種類> <PR の URL>
# EDIT に edit ジョブの結果を、RUN_ID に実行の ID を、JOBS に JOB_RESULTS を入れる
run_report() {
    OUT=$(cd "$WORK" && PATH="$BIN:$PATH" GH_TOKEN=t GITHUB_REPOSITORY=o/r GITHUB_REPOSITORY_OWNER=o \
        GITHUB_SERVER_URL="$SERVER" GITHUB_RUN_ID="${RUN_ID-4242}" RUNNER_TEMP="$CAP/rt" \
        GITHUB_STEP_SUMMARY="$CAP/summary" EDIT_OUTCOME="${EDIT-}" CAF_HEAD_SHA="${HEAD_ARG-}" \
        JOB_RESULTS="${JOBS-}" \
        bash "$SCRIPT" "$@" 2>"$CAP/err")
    RC=$?
}

expect_safe() {
    local calls
    calls=$(cat "$CAP/gh.calls")
    expect_not_has "PR を閉じない" "$calls" "pr close"
    expect_not_has "PR の状態を変えない" "$calls" "pulls/"
    expect_not_has "ブランチを消さない" "$calls" "git/refs"
    expect_not_has "DELETE を呼ばない" "$calls" "DELETE"
    expect_not_has "マージしない" "$calls" "merge"
    expect_not_has "警告を却下しない" "$calls" "dismiss"
    expect_not_has "Dependabot へのコマンドを打たない" "$calls" "@dependabot"
}

if want record; then
    new_case record
    HEAD_ARG=0123456789abcdef0123456789abcdef01234567 run_report record unfixed npm left@1.2.3 trigger "" "" "$NPM_DETAIL" guard ""
    expect_eq "record が0で終わる" "$RC" 0
    expect_eq "record が決めた結果を標準出力に書く" "$OUT" "result=unfixed"
    F="$CAP/rt/outcome/outcome.json"
    expect_eq "record が決めた結果を結果のファイルに書く" "$(jq -r .result "$F")" unfixed
    expect_eq "結果のファイルに種類と key を書く" "$(jq -r '.kind + " " + .key' "$F")" "npm left@1.2.3"
    expect_eq "結果のファイルに入力の reason を残す" "$(jq -r .reason "$F")" trigger
    expect_eq "結果のファイルに入力の detail を JSON で残す" "$(jq -c .detail "$F")" "$(jq -c . <<<"$NPM_DETAIL")"
    expect_eq "pr と checks と pr_url が空なら null にする" "$(jq -c '[.pr, .checks, .pr_url]' "$F")" "[null,null,null]"
    expect_eq "結果のファイルに理由の種類を書く" "$(jq -r .cause "$F")" guard
    expect_eq "結果のファイルに実行の URL を書く" "$(jq -r .run_url "$F")" "$BASE_URL/actions/runs/4242"
    expect_eq "結果のファイルに起点のコミットを書く" "$(jq -r .head_sha "$F")" 0123456789abcdef0123456789abcdef01234567
    expect_has "結果のファイルに終わった日時を書く" "$(jq -r '.finished_at | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$")' "$F")" true
    expect_eq "record が Issue の API を呼ばない" "$(wc -c <"$CAP/gh.calls" | tr -d ' ')" 0
    expect_eq "record が GITHUB_STEP_SUMMARY に1行を書く" "$(wc -l <"$CAP/summary" | tr -d ' ')" 1
    expect_has "まとめの行に種類と key と結果を書く" "$(cat "$CAP/summary")" "npm ${BQ}left@1.2.3${BQ}: unfixed"

    rm -rf "$CAP/rt" "$CAP/summary"
    run_report record pr dependabot 55 red-check 31 '["build","test"]' "" "" "$BASE_URL/pull/31"
    F="$CAP/rt/outcome/outcome.json"
    expect_eq "red-check の結果のファイルに PR の番号と赤の検査を残す" "$(jq -c '[.pr, .checks, .pr_url]' "$F")" "[31,[\"build\",\"test\"],\"$BASE_URL/pull/31\"]"
    expect_eq "起点のコミットが無ければ null にする" "$(jq -c .head_sha "$F")" null
    expect_has "まとめの行に PR の URL を書く" "$(cat "$CAP/summary")" "$BASE_URL/pull/31"

    rm -rf "$CAP/rt" "$CAP/summary"
    run_report record unfixed codeql 12 trigger "" "" "" guard ""
    expect_eq "種類が codeql でも結果のファイルを書く" "$(jq -r .result "$CAP/rt/outcome/outcome.json")" unfixed
    expect_eq "種類が codeql のまとめの行には、警告の番号と結果だけを書く" "$(cat "$CAP/summary")" "- claude-auto-fix codeql #12: unfixed"
    expect_eq "record が Issue の API を呼ばない(codeql)" "$(wc -c <"$CAP/gh.calls" | tr -d ' ')" 0
    expect_safe
fi

if want notify-no-file; then
    new_case notify-no-file
    run_report notify unfixed npm left@1.2.3 trigger "" "" "$NPM_DETAIL" guard ""
    expect_eq "notify が0で終わる" "$RC" 0
    if [ -e "$CAP/rt/outcome" ]; then ng "notify が結果のファイルを書かない"; else ok "notify が結果のファイルを書かない"; fi
    if [ -e "$CAP/summary" ]; then ng "notify が GITHUB_STEP_SUMMARY に書かない"; else ok "notify が GITHUB_STEP_SUMMARY に書かない"; fi
    expect_safe
fi

if want unfixed-new; then
    new_case unfixed-new
    run_report notify unfixed npm left@1.2.3 trigger "" "" "$NPM_DETAIL" guard ""
    expect_eq "unfixed で0で終わる" "$RC" 0
    expect_eq "unfixed で知らせの Issue を1つ起票する" "$(created_count)" 1
    expect_eq "知らせの Issue の題名" "$(issue_field 100 title)" "Claude が直せなかった npm の部品 left@1.2.3 の脆弱性"
    expect_eq "知らせの Issue にラベル claude-auto-fix を付ける" "$(issue_field 100 'labels | join(",")')" claude-auto-fix
    BODY=$(issue_field 100 body)
    expect_has "知らせの Issue に対象の URL を書く" "$BODY" "- $BASE_URL/security/dependabot/41"
    expect_not_has "ほかのホストの URL を書かない" "$BODY" "evil.example.com"
    expect_has "知らせの Issue の key をコードの形で書く" "$BODY" "${BQ}left@1.2.3${BQ}"
    expect_has "知らせの Issue に理由の種類を書く" "$BODY" "止まった理由の種類: ${BQ}guard${BQ}"
    expect_has "知らせの Issue に状態が unfixed の目印を書く" "$BODY" "<!-- claude-auto-fix-issue key=npm:left@1.2.3 kind=unfixed run=4242 -->"
    expect_eq "知らせの Issue の状態が unfixed になる" "$(thread_of 100 | issue_state npm left@1.2.3)" unfixed
    expect_has "起票した Issue を所有者に割り当てる" "$(cat "$CAP/gh.calls")" "repos/o/r/issues/100/assignees"
    run_report notify unfixed npm left@1.2.3 trigger "" "" "$NPM_DETAIL" guard ""
    expect_eq "同じ実行の notify をもう一度呼んでも起票しない" "$(created_count)" 1
    expect_eq "同じ実行の notify をもう一度呼んでもコメントを付けない" "$(comment_count 100)" 0
    run_report notify unfixed go-stdlib 1.25.3 trigger "" "" '{"version":"1.25.3","osv":["GO-2026-4001"]}' "" ""
    expect_has "種類が go-stdlib の知らせの Issue に Go の脆弱性の URL を書く" "$(issue_field 101 body)" "- https://pkg.go.dev/vuln/GO-2026-4001"
    expect_safe
fi

if want dependabot; then
    new_case dependabot
    run_report notify unfixed dependabot 55 trigger "" '["build"]' "" check-failed ""
    expect_eq "種類が dependabot の unfixed で0で終わる" "$RC" 0
    expect_eq "種類が dependabot の知らせの Issue を1つ起票する" "$(created_count)" 1
    expect_has "種類が dependabot の知らせの Issue に Dependabot の PR の URL を書く" "$(issue_field 100 body)" "- $BASE_URL/pull/55"
    expect_eq "種類が dependabot の知らせの Issue の題名" "$(issue_field 100 title)" "Claude が直せなかった Dependabot の PR #55 の赤の検査"
    expect_safe
fi

if want container; then
    new_case container
    seed_issue 7 "コンテナ脆弱性: CVE-2026-1234" container-vuln "$BOT" "本番のイメージに脆弱性があります"
    seed_issue 8 "コンテナ脆弱性: CVE-2026-1234" container-vuln someone "偽物"
    run_report notify unfixed container CVE-2026-1234 trigger "" "" "" check-failed ""
    expect_eq "種類が container の unfixed で0で終わる" "$RC" 0
    expect_eq "種類が container の unfixed で新しい Issue を起票しない" "$(created_count)" 0
    expect_eq "ラベル container-vuln の Issue にコメントを1つ書く" "$(comment_count 7)" 1
    C=$(last_comment 7)
    expect_has "コメントに Claude が直せなかったことを書く" "$C" "直せませんでした"
    expect_has "コメントに目印を付ける" "$C" "<!-- claude-auto-fix-notice kind=unfixed run=4242 -->"
    expect_has "コメントで所有者に知らせる" "$C" "@o "
    expect_eq "github-actions[bot] が起票していない Issue にはコメントしない" "$(comment_count 8)" 0
    run_report notify unfixed container CVE-2026-1234 trigger "" "" "" check-failed ""
    expect_eq "同じ実行の notify をもう一度呼んでもコメントを重ねない" "$(comment_count 7)" 1
    RUN_ID=5000 run_report notify unfixed container CVE-2026-9999 trigger "" "" "" check-failed ""
    expect_eq "ラベル container-vuln の Issue が無ければ0以外で終わる" "$RC" 1
    expect_safe
fi

if want existing; then
    new_case existing
    seed_issue 19 "Claude が直せなかった npm の部品 left@1.2.3 の脆弱性" claude-auto-fix someone \
        "<!-- claude-auto-fix-issue key=npm:left@1.2.3 kind=unfixed -->"
    seed_issue 20 "Claude が直せなかった npm の部品 left@1.2.3 の脆弱性" claude-auto-fix "$BOT" \
        "前の本文
<!-- claude-auto-fix-issue key=npm:left@1.2.3 kind=unfixed run=1000 -->"
    seed_issue 18 "Claude が直せなかった npm の部品 left@1.2.30 の脆弱性" claude-auto-fix "$BOT" \
        "<!-- claude-auto-fix-issue key=npm:left@1.2.30 kind=unfixed run=1000 -->"
    run_report notify unfixed npm left@1.2.3 manual "" "" "$NPM_DETAIL" check-failed ""
    expect_eq "知らせの Issue が開いているときの unfixed で0で終わる" "$RC" 0
    expect_eq "同じ key の知らせの Issue が開いていれば、新しい Issue を起票しない" "$(created_count)" 0
    expect_eq "同じ key の知らせの Issue が開いていればコメントを付ける" "$(comment_count 20)" 1
    C=$(last_comment 20)
    expect_has "コメントで所有者に知らせる" "$C" "@o "
    expect_has "コメントに対象の URL を書く" "$C" "- $BASE_URL/security/dependabot/41"
    expect_has "コメントに状態が unfixed の目印を書く" "$C" "<!-- claude-auto-fix-issue key=npm:left@1.2.3 kind=unfixed run=4242 -->"
    expect_eq "github-actions[bot] が書いていない Issue にはコメントしない" "$(comment_count 19)" 0
    expect_eq "key が前で一致するだけの Issue にはコメントしない" "$(comment_count 18)" 0
    run_report notify unfixed npm left@1.2.3 manual "" "" "$NPM_DETAIL" check-failed ""
    expect_eq "同じ実行の notify をもう一度呼んでもコメントを重ねない" "$(comment_count 20)" 1
    expect_safe
fi

if want sweep; then
    new_case sweep
    EDIT="" run_report notify unfixed npm left@1.2.3 red-check 31 '["build"]' "$NPM_DETAIL" "" "$BASE_URL/pull/31"
    expect_eq "sweep から呼ばれた notify が0で終わる" "$RC" 0
    expect_eq "sweep から呼ばれた notify が知らせの Issue を起票する" "$(created_count)" 1
    expect_has "sweep から閉じた PR の URL を渡されたら知らせに書く" "$(issue_field 100 body)" \
        "同じ必須の検査が3回続けて赤になったので、仕組みが閉じた PR: $BASE_URL/pull/31"
    expect_safe
fi

if want red-check; then
    new_case red-check
    run_report notify unfixed npm left@1.2.3 red-check 31 '["build"]' "$NPM_DETAIL" check-failed ""
    expect_eq "reason が red-check の unfixed で0で終わる" "$RC" 0
    expect_has "reason が red-check の unfixed で、知らせに PR の URL を書く" "$(issue_field 100 body)" \
        "赤の検査を直せなかった Claude の変更の PR(開いたまま残ります): $BASE_URL/pull/31"
    expect_safe
fi

if want codeql; then
    new_case codeql
    run_report notify unfixed codeql 12 trigger "" "" "" guard ""
    expect_eq "種類が codeql の unfixed で0で終わる" "$RC" 0
    expect_eq "種類が codeql の Issue の題名は決まった文と警告の番号だけ" "$(issue_field 100 title)" "Claude が直せなかった CodeQL の警告 #12"
    EXPECT_BODY="claude-auto-fix の仕組みで、Claude が、CodeQL の警告 #12を直せませんでした。所有者が手で仕組みを動かすと、もう一度 Claude を動かせます。

## 対象

- $BASE_URL/security/code-scanning/12

<!-- claude-auto-fix-issue key=codeql:12 kind=unfixed run=4242 -->"
    expect_eq "種類が codeql の Issue の本文は決まった文と警告の URL だけ" "$(issue_field 100 body)" "$EXPECT_BODY"
    RUN_ID=4343 run_report notify unfixed codeql 12 manual "" "" "" check-failed ""
    EXPECT_COMMENT="@o claude-auto-fix の仕組みで、Claude が、CodeQL の警告 #12を直せませんでした。所有者が手で仕組みを動かすと、もう一度 Claude を動かせます。

## 対象

- $BASE_URL/security/code-scanning/12

<!-- claude-auto-fix-issue key=codeql:12 kind=unfixed run=4343 -->"
    expect_eq "種類が codeql のコメントは決まった文と警告の URL だけ" "$(last_comment 100)" "$EXPECT_COMMENT"
    RUN_ID=4444 run_report notify unfixed codeql 12 red-check 31 '["CodeQL"]' "" check-failed ""
    EXPECT_COMMENT="@o claude-auto-fix の仕組みで、Claude が、CodeQL の警告 #12を直せませんでした。所有者が手で仕組みを動かすと、もう一度 Claude を動かせます。

赤の検査を直せなかった Claude の変更の PR(開いたまま残ります): $BASE_URL/pull/31

## 対象

- $BASE_URL/security/code-scanning/12

<!-- claude-auto-fix-issue key=codeql:12 kind=unfixed run=4444 -->"
    expect_eq "種類が codeql で reason が red-check の unfixed で、知らせに PR の URL が書かれる" "$(last_comment 100)" "$EXPECT_COMMENT"
    ALL=$(jq -r '.issues[] | .title, .body, (.comments[] | .body)' "$CAP/state.json")
    expect_not_has "種類が codeql の知らせに理由の種類を書かない" "$ALL" "check-failed"
    expect_not_has "種類が codeql の知らせに理由の種類を書かない(guard)" "$ALL" "guard"
    expect_safe
fi

if want key; then
    new_case key
    EDIT=key run_report notify key npm left@1.2.3 trigger "" "" "$NPM_DETAIL" no-key ""
    expect_eq "key で0で終わる" "$RC" 0
    expect_eq "key で鍵の Issue を起票する" "$(created_count)" 1
    expect_eq "鍵の Issue の題名" "$(issue_field 100 title)" "Claude を動かす鍵を取り替えてください"
    BODY=$(issue_field 100 body)
    expect_has "鍵の Issue の本文のリンクが基盤構築手順の見出し『Claude を動かす鍵の取り替え』を指す" "$BODY" \
        "($BASE_URL/blob/main/doc/開発フロー/基盤構築手順.md#claude-を動かす鍵の取り替え)"
    expect_has "鍵の Issue の本文に目印を書く" "$BODY" "<!-- claude-auto-fix-key -->"
    expect_has "鍵の Issue を所有者に割り当てる" "$(cat "$CAP/gh.calls")" "repos/o/r/issues/100/assignees"
    RUN_ID=5000 EDIT=key run_report notify key codeql 12 trigger "" "" "" no-key ""
    expect_eq "key で鍵の Issue が1つだけになる" "$(created_count)" 1
    expect_not_has "鍵の Issue に対象を書かない" "$BODY" "left"
    expect_safe
fi

if want key-close; then
    new_case key-close
    seed_issue 30 "Claude を動かす鍵を取り替えてください" claude-auto-fix "$BOT" "本文
<!-- claude-auto-fix-key -->"
    seed_issue 31 "Claude を動かす鍵を取り替えてください" claude-auto-fix someone "<!-- claude-auto-fix-key -->"
    EDIT=key run_report notify key npm left@1.2.3 trigger "" "" "$NPM_DETAIL" no-key ""
    expect_eq "edit ジョブが key を出した実行では鍵の Issue を閉じない" "$(issue_field 30 state)" open
    expect_eq "鍵の Issue が開いていれば起票しない" "$(created_count)" 0
    EDIT="" run_report notify blocked npm left@1.2.3 trigger "" "" "$NPM_DETAIL" "" ""
    expect_eq "edit ジョブが動かなかった実行では鍵の Issue を閉じない" "$(issue_field 30 state)" open
    EDIT=ok run_report notify blocked npm left@1.2.3 trigger "" "" "$NPM_DETAIL" cooldown ""
    expect_eq "edit ジョブが ok を出して結果が blocked の実行でも0で終わる" "$RC" 0
    expect_eq "edit ジョブが ok を出して結果が blocked の実行でも鍵の Issue が閉じられる" "$(issue_field 30 state)" closed
    expect_has "鍵の Issue に動けたことを書いたコメントを付ける" "$(last_comment 30)" "動けた"
    expect_eq "github-actions[bot] が起票していない Issue は閉じない" "$(issue_field 31 state)" open
    new_case key-close-unfixed
    seed_issue 30 "Claude を動かす鍵を取り替えてください" claude-auto-fix "$BOT" "<!-- claude-auto-fix-key -->"
    EDIT=unfixed run_report notify unfixed codeql 12 trigger "" "" "" claude-unfixed ""
    expect_eq "edit ジョブが unfixed を出した実行で鍵の Issue が閉じられる" "$(issue_field 30 state)" closed
    expect_safe
fi

if want pr-close; then
    new_case pr-close
    seed_issue 40 "Claude が3日続けて動けなかった npm の部品 left@1.2.3 の脆弱性" claude-auto-fix "$BOT" \
        "<!-- claude-auto-fix-issue key=npm:left@1.2.3 kind=unavailable run=900 -->"
    seed_comment 40 someone "<!-- claude-auto-fix-issue key=npm:left@1.2.3 kind=unfixed run=901 -->"
    seed_issue 41 "Claude が直せなかった Maven の部品 a:b@2.0 の脆弱性" claude-auto-fix "$BOT" \
        "<!-- claude-auto-fix-issue key=maven:a:b@2.0 kind=unfixed run=900 -->"
    EDIT=ok run_report notify pr npm left@1.2.3 trigger "" "" "$NPM_DETAIL" "" "$BASE_URL/pull/99"
    expect_eq "pr で0で終わる" "$RC" 0
    expect_eq "pr で状態が unavailable の知らせの Issue が閉じられる" "$(issue_field 40 state)" closed
    expect_has "閉じる Issue に PR の URL を書いたコメントを付ける" "$(last_comment 40)" "$BASE_URL/pull/99"
    EDIT=ok run_report notify pr maven a:b@2.0 trigger "" "" '{"alerts":[]}' "" "$BASE_URL/pull/98"
    expect_eq "pr でも状態が unfixed の知らせの Issue は閉じない" "$(issue_field 41 state)" open
    expect_eq "pr で状態が unfixed の知らせの Issue にコメントしない" "$(comment_count 41)" 0
    expect_eq "pr で Issue を起票しない" "$(created_count)" 0
    expect_safe
fi

if want unavailable-to-unfixed; then
    new_case unavailable-to-unfixed
    seed_issue 50 "Claude が3日続けて動けなかった CodeQL の警告 #12" claude-auto-fix "$BOT" \
        "<!-- claude-auto-fix-issue key=codeql:12 kind=unavailable run=900 -->"
    expect_eq "準備: 知らせの Issue の状態が unavailable" "$(thread_of 50 | issue_state codeql 12)" unavailable
    run_report notify unfixed codeql 12 retry "" "" "" check-failed ""
    expect_eq "状態が unavailable の知らせの Issue が開いているときの unfixed で0で終わる" "$RC" 0
    expect_eq "状態が unavailable の知らせの Issue が開いているときの unfixed で、新しい Issue を起票しない" "$(created_count)" 0
    expect_eq "状態が unavailable の知らせの Issue にコメントが付く" "$(comment_count 50)" 1
    expect_eq "最も新しい目印の状態が unfixed になる" "$(thread_of 50 | issue_state codeql 12)" unfixed
    expect_eq "知らせの Issue は開いたまま残る" "$(issue_field 50 state)" open
    expect_safe
fi

if want many; then
    new_case many
    # 開いている知らせの Issue が多く、一覧の全体が1つの引数の上限(128KiB)を超えても動くこと
    BIG=$(head -c 6000 /dev/zero | tr '\0' 'x')
    jq --arg big "$BIG" --arg bot "$BOT" '.issues += [range(1; 41) as $i | {number: $i,
        title: ("Claude が直せなかった CodeQL の警告 #" + ($i + 1000 | tostring)), state: "open", labels: ["claude-auto-fix"],
        body: ($big + "\n<!-- claude-auto-fix-issue key=codeql:" + ($i + 1000 | tostring) + " kind=unfixed run=900 -->"),
        user: {login: $bot}, created_at: "2026-11-20T08:00:00Z", comments: [], pr: false}]' \
        "$CAP/state.json" >"$CAP/state.tmp" && mv "$CAP/state.tmp" "$CAP/state.json"
    expect_has "準備: 一覧が128KiBを超える" "$(jq '[.issues[].body | length] | add > 131072' "$CAP/state.json")" true
    seed_issue 45 "Claude が3日続けて動けなかった npm の部品 left@1.2.3 の脆弱性" claude-auto-fix "$BOT" \
        "<!-- claude-auto-fix-issue key=npm:left@1.2.3 kind=unavailable run=900 -->"
    seed_issue 46 "Claude が3日続けて動けなかった Maven の部品 a:b@2.0 の脆弱性" claude-auto-fix "$BOT" \
        "<!-- claude-auto-fix-issue key=maven:a:b@2.0 kind=unavailable run=900 -->"
    run_report notify unfixed npm left@1.2.3 trigger "" "" "$NPM_DETAIL" guard ""
    expect_eq "知らせの Issue が多くても、開いている Issue へのコメントで0で終わる" "$RC" 0
    expect_eq "知らせの Issue が多くても、開いている Issue にコメントが付く" "$(comment_count 45)" 1
    expect_eq "知らせの Issue が多くても、最も新しい目印の状態が unfixed になる" "$(thread_of 45 | issue_state npm left@1.2.3)" unfixed
    EDIT=ok run_report notify pr maven a:b@2.0 trigger "" "" '{"alerts":[]}' "" "$BASE_URL/pull/98"
    expect_eq "知らせの Issue が多くても、pr で0で終わる" "$RC" 0
    expect_eq "知らせの Issue が多くても、pr で状態が unavailable の知らせの Issue が閉じられる" "$(issue_field 46 state)" closed
    expect_eq "知らせの Issue が多くても起票しない" "$(created_count)" 0
    expect_safe
fi

if want api-fail; then
    new_case api-fail
    touch "$CAP/fail-all"
    run_report notify unfixed npm left@1.2.3 trigger "" "" "$NPM_DETAIL" guard ""
    expect_eq "Issue の API が失敗したら1で終わる" "$RC" 1
    rm -f "$CAP/fail-all"
    run_report record unfixed npm left@1.2.3 trigger "" "" "$NPM_DETAIL" guard ""
    expect_eq "record は Issue の API が無くても0で終わる" "$RC" 0
    expect_safe
fi

if want unavailable-3days; then
    new_case unavailable-3days
    D2=$(ago $((2 * DAY)))
    D1=$(ago "$DAY")
    seed_run 11 npm left@1.2.3 unavailable usage-limit "$D2"
    seed_run 12 npm other@1.0.0 pr "" "$(ago $((DAY + 60)))"
    seed_run 13 npm left@1.2.3 unavailable timeout "$D1"
    run_report notify unavailable npm left@1.2.3 retry "" "" "$NPM_DETAIL" claude-error ""
    expect_eq "3つの違う日の unavailable で0で終わる" "$RC" 0
    expect_eq "3つの違う日の unavailable で知らせの Issue を1つだけ起票する" "$(created_count)" 1
    expect_eq "動けなかった知らせの Issue の題名" "$(issue_field 100 title)" "Claude が3日続けて動けなかった npm の部品 left@1.2.3 の脆弱性"
    expect_eq "動けなかった知らせの Issue にラベル claude-auto-fix を付ける" "$(issue_field 100 'labels | join(",")')" claude-auto-fix
    BODY=$(issue_field 100 body)
    expect_has "動けなかった知らせに3つの違う日に動けなかったことを書く" "$BODY" "3つの違う日に続けて"
    expect_has "動けなかった知らせに対象の URL を書く" "$BODY" "- $BASE_URL/security/dependabot/41"
    expect_has "動けなかった知らせに1つ目の日と理由を書く" "$BODY" "- ${D2:0:10}: Claude を動かせませんでした(理由の種類: ${BQ}usage-limit${BQ})"
    expect_has "動けなかった知らせに2つ目の日と理由を書く" "$BODY" "- ${D1:0:10}: Claude を動かせませんでした(理由の種類: ${BQ}timeout${BQ})"
    expect_has "動けなかった知らせにこの実行の日と理由を書く" "$BODY" "- $(date -u +%Y-%m-%d): Claude を動かせませんでした(理由の種類: ${BQ}claude-error${BQ})"
    expect_not_has "ほかの key の実行を書かない" "$BODY" "${BQ}other"
    expect_has "動けなかった知らせに状態が unavailable の目印を書く" "$BODY" "<!-- claude-auto-fix-issue key=npm:left@1.2.3 kind=unavailable run=4242 -->"
    expect_eq "動けなかった知らせの Issue の状態が unavailable になる" "$(thread_of 100 | issue_state npm left@1.2.3)" unavailable
    expect_has "動けなかった知らせの Issue を所有者に割り当てる" "$(cat "$CAP/gh.calls")" "repos/o/r/issues/100/assignees"
    run_report notify unavailable npm left@1.2.3 retry "" "" "$NPM_DETAIL" claude-error ""
    expect_eq "同じ実行の notify をもう一度呼んでも起票しない" "$(created_count)" 1
    RUN_ID=4243 run_report notify unavailable npm left@1.2.3 retry "" "" "$NPM_DETAIL" claude-error ""
    expect_eq "次の実行でも、知らせの Issue が開いていれば起票しない" "$(created_count)" 1
    expect_eq "次の実行でも、知らせの Issue が開いていればコメントしない" "$(comment_count 100)" 0
    expect_safe
fi

if want unavailable-not-yet; then
    new_case unavailable-not-yet
    seed_run 21 npm left@1.2.3 unavailable usage-limit "$(today_at 1)"
    seed_run 22 npm left@1.2.3 unavailable usage-limit "$(today_at 2)"
    run_report notify unavailable npm left@1.2.3 retry "" "" "$NPM_DETAIL" usage-limit ""
    expect_eq "同じ日の3回の unavailable で0で終わる" "$RC" 0
    expect_eq "同じ日の3回の unavailable では起票しない" "$(created_count)" 0
    new_case unavailable-not-yet-pr
    seed_run 23 npm left@1.2.3 unavailable usage-limit "$(ago $((2 * DAY)))"
    seed_run 24 npm left@1.2.3 pr "" "$(ago "$DAY")"
    run_report notify unavailable npm left@1.2.3 retry "" "" "$NPM_DETAIL" usage-limit ""
    expect_eq "最後の3回に pr があれば起票しない" "$(created_count)" 0
    new_case unavailable-not-yet-two
    seed_run 25 npm left@1.2.3 unavailable usage-limit "$(ago "$DAY")"
    seed_run 26 npm right@2.0.0 unavailable usage-limit "$(ago $((2 * DAY)))"
    run_report notify unavailable npm left@1.2.3 retry "" "" "$NPM_DETAIL" usage-limit ""
    expect_eq "同じ key の実行が2回だけなら起票しない(ほかの key の実行を数えない)" "$(created_count)" 0
    new_case unavailable-not-yet-api
    seed_run 27 npm left@1.2.3 unavailable usage-limit "$(ago "$DAY")"
    jq '.runs[0].outcome = null' "$CAP/state.json" >"$CAP/state.tmp" && mv "$CAP/state.tmp" "$CAP/state.json"
    run_report notify unavailable npm left@1.2.3 retry "" "" "$NPM_DETAIL" usage-limit ""
    expect_eq "実行の結果を読めなければ0以外で終わる" "$RC" 1
    expect_eq "実行の結果を読めなければ起票しない" "$(created_count)" 0
    expect_safe
fi

if want blocked-days; then
    new_case blocked-days
    seed_cancelled 31 npm left@1.2.3 "$(ago $((2 * DAY)))"
    seed_run 32 npm left@1.2.3 blocked cooldown "$(ago "$DAY")"
    run_report notify blocked npm left@1.2.3 retry "" "" "$NPM_DETAIL" cooldown ""
    expect_eq "blocked を含む3つの違う日で0で終わる" "$RC" 0
    expect_eq "blocked も3日に数えて知らせの Issue を起票する" "$(created_count)" 1
    BODY=$(issue_field 100 body)
    expect_has "blocked の日に、PR にするのを待ったことを書く" "$BODY" "公開から72時間経っていない版を使う変更なので、PR にするのを待ちました(理由の種類: ${BQ}cooldown${BQ})"
    expect_has "取り消された実行を動けなかった日に数える" "$BODY" "Claude を動かせませんでした(理由の種類: ${BQ}cancelled${BQ})"
    expect_safe
fi

if want unavailable-open; then
    new_case unavailable-open
    seed_issue 40 "Claude が3日続けて動けなかった npm の部品 left@1.2.3 の脆弱性" claude-auto-fix "$BOT" "本文
<!-- claude-auto-fix-issue key=npm:left@1.2.3 kind=unavailable run=1 -->"
    seed_run 41 npm left@1.2.3 unavailable usage-limit "$(ago $((2 * DAY)))"
    seed_run 42 npm left@1.2.3 unavailable usage-limit "$(ago "$DAY")"
    run_report notify unavailable npm left@1.2.3 retry "" "" "$NPM_DETAIL" usage-limit ""
    expect_eq "unavailable の知らせの Issue が開いていれば0で終わる" "$RC" 0
    expect_eq "unavailable の知らせの Issue が開いていれば起票しない" "$(created_count)" 0
    expect_eq "unavailable の知らせの Issue が開いていればコメントしない" "$(comment_count 40)" 0
    expect_eq "unavailable の知らせの Issue を開いたままにする" "$(issue_field 40 state)" open
    expect_safe
fi

if want unavailable-codeql; then
    new_case unavailable-codeql
    seed_run 51 codeql 12 unavailable usage-limit "$(ago $((2 * DAY)))"
    seed_run 52 codeql 12 blocked cooldown "$(ago "$DAY")"
    run_report notify unavailable codeql 12 retry "" "" "" timeout ""
    expect_eq "種類が codeql の3日の unavailable で起票する" "$(created_count)" 1
    expect_eq "種類が codeql の動けなかった知らせの題名" "$(issue_field 100 title)" "Claude が3日続けて動けなかった CodeQL の警告 #12"
    BODY=$(issue_field 100 body)
    expect_has "種類が codeql の知らせに警告の URL を書く" "$BODY" "- $BASE_URL/security/code-scanning/12"
    expect_has "種類が codeql の知らせに、決まった文で動けなかった理由を書く" "$BODY" "Claude を動かせませんでした"
    expect_not_has "種類が codeql の知らせに理由の種類を書かない" "$BODY" "理由の種類"
    expect_not_has "種類が codeql の知らせに理由の種類の名前を書かない" "$BODY" "usage-limit"
    expect_safe
fi

if want unavailable-container; then
    new_case unavailable-container
    seed_issue 7 "コンテナ脆弱性: CVE-2026-1234" container-vuln "$BOT" "本番のイメージに脆弱性があります"
    seed_run 61 container CVE-2026-1234 unavailable usage-limit "$(ago $((2 * DAY)))"
    seed_run 62 container CVE-2026-1234 unavailable usage-limit "$(ago "$DAY")"
    run_report notify unavailable container CVE-2026-1234 retry "" "" "" usage-limit ""
    expect_eq "種類が container の3日の unavailable で0で終わる" "$RC" 0
    expect_eq "種類が container の3日の unavailable で知らせの Issue を起票する" "$(created_count)" 1
    expect_has "種類が container の知らせに、ラベル container-vuln の Issue の URL を書く" "$(issue_field 100 body)" "- $BASE_URL/issues/7"
    expect_eq "種類が container の3日の unavailable で、ラベル container-vuln の Issue にコメントしない" "$(comment_count 7)" 0
    expect_safe
fi

if want gone; then
    new_case gone
    seed_issue 7 "コンテナ脆弱性: CVE-2026-1234" container-vuln "$BOT" "本番のイメージに脆弱性があります"
    seed_issue 8 "コンテナ脆弱性: CVE-2026-1234" container-vuln someone "偽物"
    run_report notify gone container CVE-2026-1234 trigger "" "" "" gone-on-main ""
    expect_eq "gone-on-main で0で終わる" "$RC" 0
    expect_eq "gone-on-main で Issue を起票しない" "$(created_count)" 0
    expect_eq "gone-on-main でラベル container-vuln の Issue にコメントを1つ付ける" "$(comment_count 7)" 1
    C=$(last_comment 7)
    expect_has "コメントに main では消えていることを書く" "$C" "main では消えています"
    expect_has "コメントに所有者がリリースすれば本番でも消えることを書く" "$C" "所有者がリリースすれば、本番でも消えます"
    expect_has "コメントに目印を付ける" "$C" "<!-- claude-auto-fix-notice kind=gone-on-main -->"
    expect_has "コメントで所有者に知らせる" "$C" "@o "
    expect_eq "github-actions[bot] が起票していない Issue にはコメントしない" "$(comment_count 8)" 0
    RUN_ID=5001 run_report notify gone container CVE-2026-1234 trigger "" "" "" gone-on-main ""
    expect_eq "次の実行の gone-on-main でもコメントは1回だけ" "$(comment_count 7)" 1
    run_report notify gone container CVE-2026-1234 trigger "" "" "" target-gone ""
    expect_eq "対象が消えた gone ではコメントしない" "$(comment_count 7)" 1
    run_report notify gone npm left@1.2.3 trigger "" "" "$NPM_DETAIL" target-gone ""
    expect_eq "種類が container でない gone で0で終わる" "$RC" 0
    expect_eq "種類が container でない gone では何も書かない" "$(created_count)" 0
    expect_safe
fi

# 使い方: expect_job <説明> <JOB_RESULTS> <期待の結果> <期待の理由の種類>
expect_job() {
    rm -rf "$CAP/rt" "$CAP/summary"
    JOBS="$2" run_report record "" npm left@1.2.3 trigger "" "" "$NPM_DETAIL" "" ""
    expect_eq "$1: 0で終わる" "$RC" 0
    expect_eq "$1: 標準出力の結果" "$OUT" "result=$3"
    expect_eq "$1: 結果のファイルの結果と理由の種類" "$(jq -r '.result + " " + (.cause // "null")' "$CAP/rt/outcome/outcome.json" 2>/dev/null)" "$3 $4"
}

if want job-results; then
    new_case job-results
    expect_job "prepare で止まる" '{"prepare":"failure","edit":"skipped","verify":"skipped","ship":"skipped"}' unavailable prepare-failure
    expect_job "edit で止まる" '{"prepare":"success","edit":"failure","verify":"skipped"}' unavailable edit-failure
    expect_job "edit が取り消される" '{"prepare":"success","edit":"cancelled"}' unavailable edit-cancelled
    expect_job "verify で止まる" '{"prepare":"success","edit":"success","verify":"failure","ship":"skipped"}' unfixed verify-failure
    expect_job "verify-image で止まる" '{"prepare":"success","edit":"success","verify":"success","verify-image":"failure"}' unfixed verify-image-failure
    expect_job "verify が取り消される" '{"verify":"cancelled"}' unfixed verify-cancelled
    for j in cooldown-push cooldown-generate cooldown-submit cooldown-judge; do
        expect_job "$j で止まる" "{\"prepare\":\"success\",\"edit\":\"success\",\"verify\":\"success\",\"$j\":\"failure\",\"ship\":\"skipped\"}" unavailable "$j-failure"
    done
    expect_job "ship で止まる" '{"prepare":"success","edit":"success","verify":"success","ship":"failure"}' unavailable ship-failure
    expect_job "verify と ship で止まれば先のジョブで決める" '{"ship":"cancelled","verify":"failure"}' unfixed verify-failure
    expect_job "止まったジョブが無く結果も無い" '{"prepare":"success","edit":"success"}' unavailable no-outcome
    expect_job "JOB_RESULTS が無く結果も無い" "" unavailable no-outcome
    rm -rf "$CAP/rt"
    JOBS='{"ship":"failure"}' run_report record pr npm left@1.2.3 trigger "" "" "$NPM_DETAIL" "" "$BASE_URL/pull/31"
    expect_eq "結果の引数があれば、止まったジョブがあっても結果を変えない" "$OUT" "result=pr"
    rm -rf "$CAP/rt"
    JOBS='{"edit":"failure"}' run_report record "" npm left@1.2.3 trigger "" "" "$NPM_DETAIL" claude-error ""
    expect_eq "理由の種類の引数があれば、それを残す" "$(jq -r .cause "$CAP/rt/outcome/outcome.json")" claude-error
    expect_eq "止まったジョブから結果を決めても Issue の API を呼ばない" "$(wc -c <"$CAP/gh.calls" | tr -d ' ')" 0
    expect_safe
fi

if want usage; then
    new_case usage
    run_report other unfixed npm left@1.2.3 trigger "" "" "$NPM_DETAIL" "" ""
    expect_eq "知らない形で2で終わる" "$RC" 2
    run_report record "done" npm left@1.2.3 trigger "" "" "$NPM_DETAIL" "" ""
    expect_eq "知らない結果で2で終わる" "$RC" 2
    run_report notify "" npm left@1.2.3 trigger "" "" "$NPM_DETAIL" "" ""
    expect_eq "notify で結果が空なら2で終わる" "$RC" 2
    JOBS='[1]' run_report record "" npm left@1.2.3 trigger "" "" "$NPM_DETAIL" "" ""
    expect_eq "JOB_RESULTS が JSON のオブジェクトでなければ2で終わる" "$RC" 2
    JOBS='{"edit":1}' run_report record "" npm left@1.2.3 trigger "" "" "$NPM_DETAIL" "" ""
    expect_eq "JOB_RESULTS の値が文字列でなければ2で終わる" "$RC" 2
    run_report record unfixed other 1 trigger "" "" "" "" ""
    expect_eq "知らない種類で2で終わる" "$RC" 2
    run_report record unfixed npm "a b" trigger "" "" "" "" ""
    expect_eq "key の形が違えば2で終わる" "$RC" 2
    run_report record unfixed npm left@1.2.3 later "" "" "$NPM_DETAIL" "" ""
    expect_eq "知らない reason で2で終わる" "$RC" 2
    run_report record unfixed npm left@1.2.3 red-check "" "" "$NPM_DETAIL" "" ""
    expect_eq "red-check で PR の番号が無ければ2で終わる" "$RC" 2
    run_report record unfixed npm left@1.2.3 trigger "" "not json" "$NPM_DETAIL" "" ""
    expect_eq "checks が JSON の配列でなければ2で終わる" "$RC" 2
    run_report record unfixed npm left@1.2.3 trigger "" "" "[1]" "" ""
    expect_eq "detail が JSON のオブジェクトでなければ2で終わる" "$RC" 2
    run_report record unfixed npm left@1.2.3 trigger "" "" "$NPM_DETAIL" "Bad Cause" ""
    expect_eq "理由の種類の形が違えば2で終わる" "$RC" 2
    run_report record pr npm left@1.2.3 trigger "" "" "$NPM_DETAIL" "" "https://evil.example.com/o/r/pull/1"
    expect_eq "PR の URL がこのリポジトリのものでなければ2で終わる" "$RC" 2
    run_report notify pr npm left@1.2.3 trigger "" "" "$NPM_DETAIL" "" ""
    expect_eq "結果が pr で PR の URL が無ければ2で終わる" "$RC" 2
    RUN_ID="" run_report notify unfixed npm left@1.2.3 trigger "" "" "$NPM_DETAIL" "" ""
    expect_eq "実行の ID が無ければ2で終わる" "$RC" 2
    HEAD_ARG=abc run_report record unfixed npm left@1.2.3 trigger "" "" "$NPM_DETAIL" "" ""
    expect_eq "起点のコミットの形が違えば2で終わる" "$RC" 2
    OUT=$(cd "$WORK" && PATH="$BIN:$PATH" GITHUB_REPOSITORY=o/r RUNNER_TEMP="$CAP/rt" bash "$SCRIPT" record unfixed npm 2>/dev/null)
    expect_eq "引数が足りなければ2で終わる" "$?" 2
    if [ -e "$CAP/rt/outcome" ]; then ng "使い方が違えば結果のファイルを書かない"; else ok "使い方が違えば結果のファイルを書かない"; fi
    expect_eq "使い方が違えば Issue の API を呼ばない" "$(wc -c <"$CAP/gh.calls" | tr -d ' ')" 0
    expect_safe
fi

if [ "$RAN" -eq 0 ]; then
    echo "KP_TEST_CASE に合う場合がありません: $CASE" >&2
    exit 1
fi
if [ "$FAILED" -ne 0 ]; then
    echo "test-claude-auto-fix-report: 失敗があります" >&2
    exit 1
fi
echo "test-claude-auto-fix-report: すべて通りました(${RAN} の場合)"
