#!/usr/bin/env bash
# =====================================================================
# claude-auto-fix-dispatch.sh の自動テスト
#
# gh を PATH の先頭に置いた偽物に替える。偽の gh は、API の呼び出しにはフォルダ FX のファイルを返し、
# gh run download には FX の成果物のファイルを置き、gh workflow run には渡された入力を
# DISPATCH_LOG に1行の JSON で残す。止まった Dependabot の PR は、本物の
# check-audit-dependabot-stuck.sh と record-cooldown-exception.sh が、同じ偽の gh を読んで決める。
#
# 場合の名前を KP_TEST_CASE に入れると、その場合だけを流す(例: KP_TEST_CASE=container)。
# 名前は args vuln_fix go_stdlib not_failure codeql container dependabot user_content
# claude_pr vuln_branch unfixed_issue container_unfixed unavailable same_day trigger_source manual manual_vuln
# manual_unfixed manual_stuck retry_unavailable retry_today retry_cancelled retry_origin key_open key_open_none key_closed
# key_closed_late recollect_filters fails。
# =====================================================================
set -uo pipefail

HERE="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$HERE/claude-auto-fix-dispatch.sh"
WORK=$(mktemp -d) || exit 1
[ -n "$WORK" ] && [ -d "$WORK" ] || exit 1
trap 'rm -rf "$WORK"' EXIT
FAILED=0
CASE="${KP_TEST_CASE:-}"
RAN=0

ok() { echo "  ok: $1"; }
ng() { echo "  NG: $1" >&2; FAILED=1; }
expect_eq() { if [ "$2" = "$3" ]; then ok "$1"; else ng "$1(期待: [$3] 実際: [$2])"; fi; }
want() { if [ -z "$CASE" ] || [ "$CASE" = "$1" ]; then RAN=$((RAN + 1)); return 0; fi; return 1; }

FX="$WORK/fx"
BIN="$WORK/bin"
mkdir -p "$FX" "$BIN"
export FX FAKE_LOG="$WORK/gh.log" DISPATCH_LOG="$WORK/dispatch.jsonl"
export GITHUB_REPOSITORY="owner/repo" GITHUB_REPOSITORY_OWNER="owner" GH_TOKEN="fake-token"
export GITHUB_STEP_SUMMARY="$WORK/summary.md"

# --- 偽の gh ----------------------------------------------------------------------------
# api: 呼ばれた先に合う FX のファイルを返す。--slurp があれば、ファイルを1ページの配列で包む。
#      Issue のコメントのファイルが無ければ空の配列を返す。呼ばれた先が FAIL_EP の文字列を含めば失敗する
# run download <ID> -R <repo> -n <名前> -D <フォルダ>: FX/artifact-<ID>-<名前>.jsonl を置く。無ければ失敗する
# workflow run <ワークフロー> --ref <ref> -R <repo> -f k=v ...: 入力を DISPATCH_LOG に残す
cat >"$BIN/gh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$FAKE_LOG"
case "$1" in
run)
    id="$3" name="" dir=""
    while [ $# -gt 0 ]; do
        case "$1" in
        -n) name="$2"; shift ;;
        -D) dir="$2"; shift ;;
        esac
        shift
    done
    if [ "$name" = outcome ]; then
        [ -f "$FX/outcome-${id}.json" ] || exit 1
        mkdir -p "$dir" && cp "$FX/outcome-${id}.json" "$dir/outcome.json"
        exit $?
    fi
    [ -f "$FX/artifact-${id}-${name}.jsonl" ] || exit 1
    mkdir -p "$dir" && cp "$FX/artifact-${id}-${name}.jsonl" "$dir/vuln-fix-unresolved.jsonl"
    exit $?
    ;;
workflow)
    wf="$3" ref="" fields=()
    while [ $# -gt 0 ]; do
        case "$1" in
        --ref) ref="$2"; shift ;;
        -f) fields+=("$2"); shift ;;
        esac
        shift
    done
    [ -z "${FAIL_DISPATCH:-}" ] || exit 1
    line=$(jq -nc --arg wf "$wf" --arg ref "$ref" '{workflow: $wf, ref: $ref}
        + ([$ARGS.positional[] | capture("^(?<k>[^=]+)=(?<v>.*)$"; "s") | {(.k): .v}] | add // {})' \
        --args "${fields[@]}") || exit 1
    printf '%s\n' "$line" >>"$DISPATCH_LOG"
    # GitHub と同じく、起動した実行を、待っている実行として対象ごとの実行の一覧に足す。
    # 表示名は claude-auto-fix-target.yaml と同じ作り方にする(pr があれば head の SHA の先頭12文字を足す)
    title=$(jq -r '"claude-auto-fix \(.kind) \(.key)"' <<<"$line")
    pr=$(jq -r '.pr // empty' <<<"$line")
    if [ -n "$pr" ]; then
        sha=$(jq -r --argjson n "$pr" '.[] | select(.number == $n) | .head.sha' "$FX/pulls.json")
        title="${title} pr#${pr}@${sha:0:12}"
    fi
    jq -c --arg t "$title" --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        '.workflow_runs += [{id: 0, display_title: $t, status: "queued", created_at: $at, event: "workflow_dispatch", head_branch: "main",
          repository: {full_name: "owner/repo"}, head_repository: {full_name: "owner/repo"},
          path: ".github/workflows/claude-auto-fix-target.yaml"}]' "$FX/target-runs.json" >"$FX/target-runs.tmp" &&
        mv "$FX/target-runs.tmp" "$FX/target-runs.json"
    exit 0
    ;;
api) ;;
*) exit 1 ;;
esac
slurp=0 ep=""
for a in "$@"; do
    case "$a" in
    --slurp) slurp=1 ;;
    repos/*) ep="$a" ;;
    esac
done
if [ -n "${FAIL_EP:-}" ] && [[ "$ep" == *"$FAIL_EP"* ]]; then exit 1; fi
case "$ep" in
*/actions/workflows/claude-auto-fix-target.yaml/runs*) f=target-runs.json ;;
*/actions/workflows/frontend-vuln-fix.yaml/runs*) f=fw-runs.json ;;
*/actions/workflows/backend-vuln-fix.yaml/runs*) f=bw-runs.json ;;
*/actions/runs/*/artifacts*)
    # 成果物 outcome の一覧: FX/outcome-<ID>.json があれば1つ、無ければ空を返す
    id="${ep#*/actions/runs/}"
    id="${id%%/*}"
    if [ -f "$FX/outcome-${id}.json" ]; then
        printf '{"artifacts":[{"name":"outcome","expired":false}]}'
    else
        printf '{"artifacts":[]}'
    fi
    exit 0
    ;;
*/actions/runs/*) f="run-${ep##*/}.json" ;;
*/dependabot/alerts*) f=dependabot-alerts.json ;;
*/contents/backend/go.mod*) f=gomod.txt ;;
*/issues\?labels=claude-auto-fix\&state=closed*) f=issues-caf-closed.json ;;
*/code-scanning/alerts*) f=codeql-alerts.json ;;
*/git/matching-refs/*) f=refs.json ;;
*/issues/*/comments*)
    n="${ep#*/issues/}"
    f="comments-${n%%/*}.json"
    [ -f "$FX/$f" ] || printf '[]' >"$FX/$f"
    ;;
*/issues\?labels=claude-auto-fix\&*) f=issues-caf.json ;;
*/issues\?labels=container-vuln\&*) f=issues-cv.json ;;
*/pulls\?state=all*) f=pulls-all.json ;;
*/pulls\?*) f=pulls.json ;;
*/commits/*/check-runs*) s="${ep#*/commits/}"; f="checkruns-${s%%/*}.json" ;;
*) exit 1 ;;
esac
[ -f "$FX/$f" ] || exit 1
if [ "$slurp" = 1 ]; then
    printf '['
    cat "$FX/$f"
    printf ']'
else
    cat "$FX/$f"
fi
EOF
chmod +x "$BIN/gh"
export PATH="$BIN:$PATH"

# --- 偽の期待一覧: approval_gated が true の4つの検査と dependency-review が、直しても緑にならない5つの検査
cat >"$FX/required.json" <<'EOF'
{"checks": [
  {"context": "frontend-test", "mode": "always", "state": "active", "approval_gated": false},
  {"context": "backend-test", "mode": "always", "state": "active", "approval_gated": false},
  {"context": "dependency-review", "mode": "always", "state": "active", "approval_gated": false},
  {"context": "escape-hatch", "mode": "always", "state": "active", "approval_gated": true},
  {"context": "dependency-gate", "mode": "always", "state": "active", "approval_gated": true},
  {"context": "pre-merge-check", "mode": "always", "state": "active", "approval_gated": true},
  {"context": "dependency-cooldown", "mode": "always", "state": "active", "approval_gated": true}
]}
EOF
export CAF_REQUIRED_CHECKS="$FX/required.json"

BOT='github-actions[bot]'
NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)
YESTERDAY=$(date -u -d "@$(($(date -u +%s) - 86400))" +%Y-%m-%dT%H:%M:%SZ)
FW="Frontend Transitive Vulnerability Fix"
BW="Backend Vulnerability Fix"
AW="Audit Weekly"
CW="Scheduled Container Image Vulnerability Scan"

# --- 補助の関数 -------------------------------------------------------------------------
# 場合ごとに、偽の GitHub を空にする
reset() {
    rm -f "$FX"/*.jsonl "$FX"/run-*.json "$FX"/comments-*.json "$FX"/checkruns-*.json "$FX"/outcome-*.json \
        "$FAKE_LOG" "$DISPATCH_LOG" "$GITHUB_STEP_SUMMARY"
    for f in pulls pulls-all issues-caf issues-caf-closed issues-cv codeql-alerts refs dependabot-alerts; do
        printf '[]' >"$FX/$f.json"
    done
    for f in target-runs fw-runs bw-runs; do printf '{"workflow_runs":[]}' >"$FX/$f.json"; done
    printf 'module example.test/app\n\ngo 1.24.0\n\ntoolchain go1.24.4\n\nrequire (\n\tgolang.org/x/net v0.41.0\n)\n' >"$FX/gomod.txt"
    : >"$DISPATCH_LOG"
    unset FAIL_EP FAIL_DISPATCH
}
# 振り分けを動かす: run_dispatch <きっかけのワークフロー> <きっかけの実行の ID> [引数...]
# Audit Weekly と Scheduled Container Image Vulnerability Scan のきっかけの実行は、場合が FX/run-<ID>.json を
# 書いていなければ、このリポジトリの決まった時刻の実行にする
run_dispatch() {
    local wf="$1" id="$2"
    shift 2
    [ $# -gt 0 ] || set -- trigger
    case "$wf" in
    "$AW" | "$CW")
        if [[ "$id" =~ ^[0-9]+$ ]] && [ ! -f "$FX/run-${id}.json" ]; then
            trigger_run "$wf" success | jq -c --argjson id "$id" '.id = $id' >"$FX/run-${id}.json"
        fi
        ;;
    esac
    TRIGGER_WORKFLOW="$wf" TRIGGER_RUN_ID="$id" bash "$SCRIPT" "$@" >"$WORK/out" 2>"$WORK/err"
    RC=$?
}
# 起動した対象を「種類 key」のカンマ区切りで、並べ替えて出す
dispatched() { jq -rs 'map("\(.kind) \(.key)") | sort | join(",")' "$DISPATCH_LOG"; }
# 起動した対象の入力の1つを出す: input <種類> <key> <入力の名前>
input() { jq -rs --arg k "$1" --arg key "$2" --arg f "$3" 'map(select(.kind == $k and .key == $key)) | .[0][$f] // "(無し)"' "$DISPATCH_LOG"; }
summary_has() { grep -Fq -- "$1" "$GITHUB_STEP_SUMMARY" 2>/dev/null; }
# GitHub に書く呼び出しが無いことを確かめる
no_write() {
    if grep -Eq -- '(^| )(-X|--method)( |$)|^(issue|pr|label) ' "$FAKE_LOG" 2>/dev/null; then
        ng "$1(GitHub に書く呼び出しがありました: $(grep -E -- '(^| )(-X|--method)( |$)|^(issue|pr|label) ' "$FAKE_LOG" | head -1))"
    else
        ok "$1"
    fi
}
# きっかけの実行の JSON: trigger_run <ワークフローの名前> <結論> [きっかけの種類] [head のリポジトリ]
# backend のワークフローの path は、@ と ref を付けた形にする(どちらの形でも読めることを確かめるため)
trigger_run() {
    jq -nc --arg w "$1" --arg c "$2" --arg ev "${3:-schedule}" --arg head "${4:-owner/repo}" --arg br "${5:-main}" '
        {id: 1, name: $w, conclusion: $c, status: "completed", event: $ev, head_branch: $br,
         path: (if $w == "Backend Vulnerability Fix" then ".github/workflows/backend-vuln-fix.yaml@refs/heads/main"
                elif $w == "Audit Weekly" then ".github/workflows/audit-weekly.yaml"
                elif $w == "Scheduled Container Image Vulnerability Scan" then ".github/workflows/container-scan-scheduled.yaml@refs/heads/main"
                else ".github/workflows/frontend-vuln-fix.yaml" end),
         repository: {full_name: "owner/repo"}, head_repository: {full_name: $head}}'
}
# PR の JSON: pull <番号> <作成者> <head の SHA> <状態> <ブランチ> <head のリポジトリ> <ラベルの配列>
pull() {
    jq -nc --argjson n "$1" --arg u "$2" --arg sha "$3" --arg st "$4" --arg ref "$5" --arg repo "$6" --argjson labels "$7" \
        '{number: $n, state: $st, user: {login: $u}, html_url: "https://example.test/pull/\($n)",
          head: {sha: $sha, ref: $ref, repo: {full_name: $repo}}, labels: $labels, body: ""}'
}
CAF_LABELS='[{"name":"claude-auto-fix"}]'
# Issue の JSON: issue <番号> <作成者> <題名> <本文> [作成日時]
issue() {
    jq -nc --argjson n "$1" --arg u "$2" --arg t "$3" --arg b "$4" --arg at "${5:-2026-11-01T00:00:00Z}" \
        '{number: $n, user: {login: $u}, title: $t, body: $b, created_at: $at}'
}
# コメントの JSON: comment <作成者> <本文> <作成日時>
comment() { jq -nc --arg u "$1" --arg b "$2" --arg at "$3" '{user: {login: $u}, body: $b, created_at: $at}'; }
# 配列にする: arr <JSON>...
arr() { jq -sc . <<<"$(printf '%s\n' "$@")"; }
# container-scan-state の目印: state <fixed の値>
state() { printf '<!-- container-scan-state: {"kind":"open","rows":[{"fixed":%s,"severity":"HIGH"}]} -->' "$1"; }
alerts() { jq -nc '[$ARGS.positional[] | {number: tonumber, state: "open"}]' --args "$@"; }
# 検査の結果: checkruns <SHA> <赤の検査の名前>...。期待一覧の7つの検査を返し、名前を渡した検査だけを failure にする
checkruns() {
    local sha="$1"
    shift
    jq -nc '{check_runs: ([ "frontend-test", "backend-test", "dependency-review", "escape-hatch", "dependency-gate",
        "pre-merge-check", "dependency-cooldown" ] | to_entries
        | map({id: (.key + 1), name: .value, started_at: "2026-11-20T00:00:00Z",
            conclusion: (if (.value | IN($ARGS.positional[])) then "failure" else "success" end)}))}' \
        --args "$@" >"$FX/checkruns-${sha}.json"
}
target_run() { # 表示名 状態 作成日時
    jq -nc --arg t "$1" --arg s "$2" --arg at "$3" "$OWN_RUN"' + {display_title: $t, status: $s, created_at: $at}'
}
# 今から指定の秒数だけ前の日時: ago <秒>
ago() { date -u -d "@$(($(date -u +%s) - $1))" +%Y-%m-%dT%H:%M:%SZ; }
TWO_DAYS_AGO=$(ago 172800)
# このリポジトリの main から、対象ごとのワークフローのファイルで手で起動された実行の欄
OWN_RUN='{"event": "workflow_dispatch", "head_branch": "main", "repository": {"full_name": "owner/repo"},
  "head_repository": {"full_name": "owner/repo"}, "path": ".github/workflows/claude-auto-fix-target.yaml"}'
# 振り分けを、きっかけの環境変数を付けずに動かす: run_mode <manual|retry>
run_mode() {
    bash "$SCRIPT" "$@" >"$WORK/out" 2>"$WORK/err"
    RC=$?
}
# 起動した実行の数
count() { jq -s 'length' "$DISPATCH_LOG"; }
# 対象ごとの実行の一覧に実行を足す: add_run <実行の JSON>
# このリポジトリの main から手で起動された実行の欄を、書いていなければ足す
add_run() {
    jq -c --argjson r "$1" --argjson own "$OWN_RUN" '.workflow_runs += [$own + $r]' "$FX/target-runs.json" >"$FX/target-runs.tmp" &&
        mv "$FX/target-runs.tmp" "$FX/target-runs.json"
}
# 結果のファイルの JSON: rec <種類> <key> <結果> <reason> <終わった日時> [足す欄の JSON]
rec() {
    local extra="${6:-}"
    [ -n "$extra" ] || extra='{}'
    jq -nc --arg k "$1" --arg key "$2" --arg r "$3" --arg reason "$4" --arg at "$5" --argjson x "$extra" \
        '{kind: $k, key: $key, reason: $reason, pr: null, checks: null, detail: null, result: $r, cause: "c",
          pr_url: null, run_url: null, head_sha: null, finished_at: $at} + $x'
}
# 結果のファイルのある、終わった対象ごとの実行: outcome <実行の ID> <作成日時> <結果のファイルの JSON>
outcome() {
    local title fin
    title=$(jq -r '"claude-auto-fix \(.kind) \(.key)"' <<<"$3")
    fin=$(jq -r .finished_at <<<"$3")
    add_run "$(jq -nc --argjson id "$1" --arg t "$title" --arg at "$2" --arg fin "$fin" \
        '{id: $id, display_title: $t, status: "completed", conclusion: "success", created_at: $at, updated_at: $fin,
          html_url: "https://example.test/runs/\($id)"}')"
    printf '%s\n' "$3" >"$FX/outcome-$1.json"
}
# 結果を書く前に取り消された実行(結果のファイルが無い): cancelled <実行の ID> <表示名> <作成日時>
cancelled() {
    add_run "$(jq -nc --argjson id "$1" --arg t "$2" --arg at "$3" \
        '{id: $id, display_title: $t, status: "completed", conclusion: "cancelled", created_at: $at, updated_at: $at,
          html_url: "https://example.test/runs/\($id)"}')"
}
# 鍵の Issue: key_issue。閉じた鍵の Issue: closed_key_issue <閉じた日時>
key_issue() { issue 800 "$BOT" "Claude を動かす鍵を取り替えてください" "本文 <!-- claude-auto-fix-key -->"; }
closed_key_issue() { key_issue | jq -c --arg at "$1" '. + {state: "closed", closed_at: $at}'; }
# vuln-fix のワークフローの実行を、決まった時刻に動いて失敗した実行として足す: vuln_runs <fw|bw> <実行の ID>...
# 後ろに書いた ID ほど新しい実行にする
vuln_runs() {
    local which="$1" name i=0 id
    shift
    if [ "$which" = fw ]; then name="$FW"; else name="$BW"; fi
    for id in "$@"; do
        i=$((i + 1))
        trigger_run "$name" failure | jq -c --argjson id "$id" '.id = $id' >"$FX/run-${id}.json"
        jq -c --argjson id "$id" --arg at "2026-11-1${i}T00:00:00Z" '.workflow_runs += [{id: $id, event: "schedule",
            status: "completed", created_at: $at, repository: {full_name: "owner/repo"}, head_repository: {full_name: "owner/repo"}}]' \
            "$FX/${which}-runs.json" >"$FX/${which}-runs.tmp" && mv "$FX/${which}-runs.tmp" "$FX/${which}-runs.json"
    done
}
# 開いている Dependabot の警告: dep_alert <ecosystem> <部品の名前> <修正版>
dep_alert() {
    jq -nc --arg e "$1" --arg n "$2" --arg v "$3" \
        '{state: "open", dependency: {package: {ecosystem: $e, name: $n}}, security_vulnerability: {first_patched_version: {identifier: $v}}}'
}
LODASH='{"name":"lodash","version":"4.17.21","ranges":[],"urgent":false,"alerts":[1]}'
MINIMIST='{"name":"minimist","version":"1.2.8","ranges":[],"urgent":false,"alerts":[2]}'

# --- 引数と環境の誤り --------------------------------------------------------------------
if want args; then
    echo "[args] 引数と環境の誤りは 2 で終わる"
    reset
    TRIGGER_WORKFLOW="$AW" TRIGGER_RUN_ID=1 bash "$SCRIPT" >/dev/null 2>&1
    expect_eq "引数が無ければ 2 で終わる" "$?" 2
    run_dispatch "$AW" 1 bogus
    expect_eq "知らない形では 2 で終わる" "$RC" 2
    run_dispatch "Some Other Workflow" 1
    expect_eq "きっかけの4つのワークフローのどれでもなければ 2 で終わる" "$RC" 2
    run_dispatch "$AW" abc
    expect_eq "TRIGGER_RUN_ID が番号でなければ 2 で終わる" "$RC" 2
    expect_eq "誤りのときは何も起動しない" "$(dispatched)" ""
    run_mode manual
    expect_eq "manual は、きっかけの環境変数が無くても 0 で終わる" "$RC" 0
    run_mode retry
    expect_eq "retry は、きっかけの環境変数が無くても 0 で終わる" "$RC" 0
    run_mode manual extra
    expect_eq "引数が2つなら 2 で終わる" "$RC" 2
fi

# --- vuln-fix の組 -----------------------------------------------------------------------
if want vuln_fix; then
    echo "[vuln_fix] vuln-fix の成果物の組ごとに1つの実行が起動される"
    reset
    trigger_run "$FW" failure >"$FX/run-900.json"
    {
        echo '{"kind":"npm","group":{"name":"lodash","version":"4.17.21","ranges":["<4.17.21"],"urgent":false,"alerts":[1]},"reason":"r"}'
        echo '{"kind":"npm","group":{"name":"@scope/pkg","version":"1.2.3","ranges":["<1.2.3"],"urgent":true,"alerts":[2,3]},"reason":"r"}'
        echo '{"kind":"npm","group":{"name":"lodash","version":"4.17.21","ranges":["<4.17.21"],"urgent":false,"alerts":[1]},"reason":"r"}'
    } >"$FX/artifact-900-vuln-fix-unresolved.jsonl"
    run_dispatch "$FW" 900
    expect_eq "終わり方は 0" "$RC" 0
    expect_eq "組ごとに1つの実行が起動される(同じ組は1つにまとまる)" "$(dispatched)" "npm @scope/pkg@1.2.3,npm lodash@4.17.21"
    expect_eq "対象ごとのワークフローを main で起動する" "$(jq -rs 'map("\(.workflow) \(.ref)") | unique | join(",")' "$DISPATCH_LOG")" \
        "claude-auto-fix-target.yaml main"
    expect_eq "入力 reason は trigger" "$(input npm lodash@4.17.21 reason)" trigger
    expect_eq "入力 detail は組の JSON" "$(input npm @scope/pkg@1.2.3 detail | jq -c .)" \
        '{"name":"@scope/pkg","version":"1.2.3","ranges":["<1.2.3"],"urgent":true,"alerts":[2,3]}'
    expect_eq "vuln-fix の組には入力 checks を渡さない" "$(input npm lodash@4.17.21 checks)" "(無し)"
    expect_eq "vuln-fix の組には入力 pr を渡さない" "$(input npm lodash@4.17.21 pr)" "(無し)"
    if summary_has "起動した: npm lodash@4.17.21"; then ok "起動した対象を GITHUB_STEP_SUMMARY に書く"; else ng "起動した対象を GITHUB_STEP_SUMMARY に書く"; fi
    no_write "Issue と PR とコメントを書かない"
fi

if want go_stdlib; then
    echo "[go_stdlib] Go の標準ライブラリの組が1つの実行になる"
    reset
    trigger_run "$BW" failure >"$FX/run-901.json"
    echo '{"kind":"maven","group":{"name":"com.example:lib","version":"2.0.1","ranges":[],"urgent":false,"alerts":[5]},"reason":"r"}' \
        >"$FX/artifact-901-vuln-fix-unresolved-java.jsonl"
    {
        echo '{"kind":"go-stdlib","group":{"version":"1.24.5","osv":["GO-2026-0001"]},"reason":"r"}'
        echo '{"kind":"go-stdlib","group":{"version":"1.24.6","osv":["GO-2026-0002","GO-2026-0001"]},"reason":"r"}'
        echo '{"kind":"go-module","group":{"module":"golang.org/x/net","version":"0.40.0","osv":["GO-2026-0003"]},"reason":"r"}'
    } >"$FX/artifact-901-vuln-fix-unresolved-go.jsonl"
    run_dispatch "$BW" 901
    expect_eq "終わり方は 0" "$RC" 0
    expect_eq "Java と Go の成果物の組ごとに起動し、標準ライブラリは1つの実行になる" "$(dispatched)" \
        "go-module golang.org/x/net@0.40.0,go-stdlib 1.24.6,maven com.example:lib@2.0.1"
    expect_eq "標準ライブラリの実行の detail は、最も新しい版と OSV の ID のすべて" \
        "$(input go-stdlib 1.24.6 detail | jq -c '{version, osv}')" '{"version":"1.24.6","osv":["GO-2026-0001","GO-2026-0002"]}'
fi

if want not_failure; then
    echo "[not_failure] vuln-fix のワークフローの結論が failure でなければ起動しない"
    reset
    trigger_run "$FW" success >"$FX/run-902.json"
    echo '{"kind":"npm","group":{"name":"lodash","version":"4.17.21","ranges":[],"urgent":false,"alerts":[1]},"reason":"r"}' \
        >"$FX/artifact-902-vuln-fix-unresolved.jsonl"
    run_dispatch "$FW" 902
    expect_eq "終わり方は 0" "$RC" 0
    expect_eq "何も起動しない" "$(dispatched)" ""
    if grep -q '^run download' "$FAKE_LOG"; then ng "成果物を読まない"; else ok "成果物を読まない"; fi
    # 別のワークフローの実行の ID を渡されたときも起動しない
    reset
    trigger_run "$BW" failure >"$FX/run-903.json"
    echo '{"kind":"npm","group":{"name":"lodash","version":"4.17.21","ranges":[],"urgent":false,"alerts":[1]},"reason":"r"}' \
        >"$FX/artifact-903-vuln-fix-unresolved.jsonl"
    run_dispatch "$FW" 903
    expect_eq "きっかけの実行が別のワークフローのものなら起動しない" "$(dispatched)" ""
    expect_eq "きっかけの実行が別のワークフローのものなら 1 で終わる" "$RC" 1
fi

if want trigger_source; then
    echo "[trigger_source] きっかけの実行が、このリポジトリの vuln-fix のワークフローの、決まった時刻か手で起動された実行でなければ起動しない"
    LINE='{"kind":"npm","group":{"name":"lodash","version":"4.17.21","ranges":[],"urgent":false,"alerts":[1]},"reason":"r"}'
    reset
    trigger_run "$FW" failure workflow_dispatch >"$FX/run-904.json"
    echo "$LINE" >"$FX/artifact-904-vuln-fix-unresolved.jsonl"
    run_dispatch "$FW" 904
    expect_eq "手で起動された実行では起動する" "$(dispatched)" "npm lodash@4.17.21"
    reset
    trigger_run "$FW" failure pull_request >"$FX/run-905.json"
    echo "$LINE" >"$FX/artifact-905-vuln-fix-unresolved.jsonl"
    run_dispatch "$FW" 905
    expect_eq "PR で動いた同じ名前のワークフローの実行では起動しない" "$(dispatched)" ""
    expect_eq "PR で動いた実行のときは 1 で終わる" "$RC" 1
    reset
    trigger_run "$FW" failure schedule someone/repo >"$FX/run-906.json"
    echo "$LINE" >"$FX/artifact-906-vuln-fix-unresolved.jsonl"
    run_dispatch "$FW" 906
    expect_eq "ほかのリポジトリのブランチの実行では起動しない" "$(dispatched)" ""
    reset
    trigger_run "$FW" failure | jq -c '.path = ".github/workflows/other.yaml"' >"$FX/run-907.json"
    echo "$LINE" >"$FX/artifact-907-vuln-fix-unresolved.jsonl"
    run_dispatch "$FW" 907
    expect_eq "同じ名前のほかのワークフローのファイルの実行では起動しない" "$(dispatched)" ""
    if grep -q '^run download' "$FAKE_LOG"; then ng "出どころの違う実行の成果物を読まない"; else ok "出どころの違う実行の成果物を読まない"; fi
fi

if want trigger_source_audit; then
    echo "[trigger_source_audit] Audit Weekly と Scheduled Container Image Vulnerability Scan のきっかけの実行が、このリポジトリのそのワークフローの、認める起動のしかたの実行でなければ起動しない(要件1の6)"
    reset
    alerts 30 >"$FX/codeql-alerts.json"
    trigger_run "$AW" success workflow_dispatch | jq -c '.id = 908' >"$FX/run-908.json"
    run_dispatch "$AW" 908
    expect_eq "手で起動された Audit Weekly の実行では起動する" "$(dispatched)" "codeql 30"
    reset
    alerts 30 >"$FX/codeql-alerts.json"
    trigger_run "$AW" success pull_request someone/repo | jq -c '.id = 909' >"$FX/run-909.json"
    run_dispatch "$AW" 909
    expect_eq "PR で動いた同じ名前のワークフローの実行では起動しない" "$(dispatched)" ""
    expect_eq "PR で動いた実行のときは 1 で終わる" "$RC" 1
    if grep -q 'code-scanning/alerts' "$FAKE_LOG"; then ng "PR で動いた実行のときは CodeQL の警告を読まない"; else ok "PR で動いた実行のときは CodeQL の警告を読まない"; fi
    reset
    alerts 30 >"$FX/codeql-alerts.json"
    trigger_run "$AW" success | jq -c '.id = 911 | .path = ".github/workflows/other.yaml"' >"$FX/run-911.json"
    run_dispatch "$AW" 911
    expect_eq "同じ名前のほかのワークフローのファイルの実行では起動しない" "$(dispatched)" ""
    reset
    trigger_run "$CW" success schedule someone/repo | jq -c '.id = 912' >"$FX/run-912.json"
    run_dispatch "$CW" 912
    expect_eq "ほかのリポジトリのブランチの、コンテナの検査の実行のときは 1 で終わる" "$RC" 1
    if grep -Fq 'issues?labels=container-vuln' "$FAKE_LOG"; then ng "ほかのリポジトリのブランチの実行のときはコンテナの検査の Issue を読まない"; else ok "ほかのリポジトリのブランチの実行のときはコンテナの検査の Issue を読まない"; fi
    # コンテナの定期検査は、本番のリリースのあと(workflow_run)と main への push のあとにも動く(要件1の3)
    for ev in push workflow_run; do
        reset
        arr "$(issue 300 "$BOT" "コンテナ脆弱性: CVE-2026-0001" "本文 $(state true)")" >"$FX/issues-cv.json"
        trigger_run "$CW" success "$ev" | jq -c '.id = 913' >"$FX/run-913.json"
        run_dispatch "$CW" 913
        expect_eq "main で動いた ${ev} のコンテナの検査の実行では起動する" "$(dispatched)" "container CVE-2026-0001"
        expect_eq "main で動いた ${ev} のコンテナの検査の実行のときは 0 で終わる" "$RC" 0
    done
    reset
    arr "$(issue 300 "$BOT" "コンテナ脆弱性: CVE-2026-0001" "本文 $(state true)")" >"$FX/issues-cv.json"
    trigger_run "$CW" success push owner/repo feature/x | jq -c '.id = 914' >"$FX/run-914.json"
    run_dispatch "$CW" 914
    expect_eq "main でないブランチの push のコンテナの検査の実行では起動しない" "$(dispatched)" ""
    expect_eq "main でないブランチの push のコンテナの検査の実行のときは 1 で終わる" "$RC" 1
    reset
    arr "$(issue 300 "$BOT" "コンテナ脆弱性: CVE-2026-0001" "本文 $(state true)")" >"$FX/issues-cv.json"
    trigger_run "$CW" success pull_request | jq -c '.id = 915' >"$FX/run-915.json"
    run_dispatch "$CW" 915
    expect_eq "このリポジトリの PR で動いたコンテナの検査の実行では起動しない" "$(dispatched)" ""
    expect_eq "このリポジトリの PR で動いたコンテナの検査の実行のときは 1 で終わる" "$RC" 1
    reset
    alerts 30 >"$FX/codeql-alerts.json"
    trigger_run "$AW" success push | jq -c '.id = 916' >"$FX/run-916.json"
    run_dispatch "$AW" 916
    expect_eq "Audit Weekly は push の実行を認めない" "$(dispatched)" ""
fi

# --- CodeQL の警告 -----------------------------------------------------------------------
if want codeql; then
    echo "[codeql] main に開いたままの CodeQL の警告ごとに1つの実行が起動される"
    reset
    alerts 30 31 >"$FX/codeql-alerts.json"
    run_dispatch "$AW" 910
    expect_eq "終わり方は 0" "$RC" 0
    expect_eq "警告ごとに1つの実行が起動される" "$(dispatched)" "codeql 30,codeql 31"
    if grep -Fq 'code-scanning/alerts?ref=refs/heads/main&tool_name=CodeQL&state=open' "$FAKE_LOG"; then
        ok "main の CodeQL の開いた警告を読む"
    else
        ng "main の CodeQL の開いた警告を読む"
    fi
    expect_eq "CodeQL には入力 detail を渡さない" "$(input codeql 30 detail)" "(無し)"
    if summary_has "起動した: CodeQL の警告 #30"; then ok "GITHUB_STEP_SUMMARY には警告の番号だけを書く"; else ng "GITHUB_STEP_SUMMARY には警告の番号だけを書く"; fi
fi

# --- コンテナの Issue ----------------------------------------------------------------------
if want container; then
    echo "[container] 修正版のあるコンテナの Issue で起動され、修正版の無い Issue と1度扱った Issue では起動されない"
    reset
    arr \
        "$(issue 300 "$BOT" "コンテナ脆弱性: CVE-2026-0001" "本文 $(state true)")" \
        "$(issue 301 "$BOT" "コンテナ脆弱性: CVE-2026-0002" "本文 $(state true)")" \
        "$(issue 302 "$BOT" "コンテナ脆弱性: CVE-2026-0003" "本文 $(state true)")" \
        "$(issue 303 "$BOT" "コンテナ脆弱性: CVE-2026-0004" "本文 $(state true)")" >"$FX/issues-cv.json"
    # 301: 最新の状態の目印では修正版が無い
    arr "$(comment "$BOT" "更新 $(state false)" 2026-11-10T00:00:00Z)" >"$FX/comments-301.json"
    # 302: この仕組みが PR を作ったことを書いたコメントがある
    arr "$(comment "$BOT" '<!-- claude-auto-fix-notice kind=pr run=77 -->' 2026-11-10T00:00:00Z)" >"$FX/comments-302.json"
    # 303: 閉じた Claude の変更の PR がある。300 と同じ名前の fork のブランチの PR は数えない
    arr \
        "$(pull 520 DogisRiki-bot 1111111111111111111111111111111111111111 closed fix/claude-auto-fix-container-cve-2026-0004 owner/repo "$CAF_LABELS")" \
        "$(pull 521 someone 2222222222222222222222222222222222222222 closed fix/claude-auto-fix-container-cve-2026-0001 someone/repo "$CAF_LABELS")" \
        >"$FX/pulls-all.json"
    run_dispatch "$CW" 920
    expect_eq "終わり方は 0" "$RC" 0
    expect_eq "修正版のあるコンテナの Issue で起動される" "$(dispatched)" "container CVE-2026-0001"
    if summary_has "起動しなかった: container CVE-2026-0002(修正版が無い)"; then
        ok "修正版の無いコンテナの Issue では起動されない"
    else
        ng "修正版の無いコンテナの Issue では起動されない"
    fi
    if summary_has "起動しなかった: container CVE-2026-0003(この仕組みが1度扱った)" &&
        summary_has "起動しなかった: container CVE-2026-0004(この仕組みが1度扱った)"; then
        ok "1度扱ったコンテナの Issue では起動されない"
    else
        ng "1度扱ったコンテナの Issue では起動されない"
    fi
    no_write "修正版の無いコンテナの Issue では起動されず何も書かない"
fi

# --- 止まった Dependabot の PR --------------------------------------------------------------
if want dependabot; then
    echo "[dependabot] 直しても緑にならない検査だけが赤の PR が外れる"
    reset
    S60=6000000000000000000000000000000000000000
    S61=6100000000000000000000000000000000000000
    S62=6200000000000000000000000000000000000000
    S63=6300000000000000000000000000000000000000
    arr \
        "$(pull 60 'dependabot[bot]' "$S60" open dependabot/a owner/repo '[]')" \
        "$(pull 61 'dependabot[bot]' "$S61" open dependabot/b owner/repo '[]')" \
        "$(pull 62 'dependabot[bot]' "$S62" open dependabot/c owner/repo '[]')" \
        "$(pull 63 'dependabot[bot]' "$S63" open dependabot/d owner/repo '[]')" >"$FX/pulls.json"
    checkruns "$S60" dependency-review
    checkruns "$S61" dependency-cooldown
    checkruns "$S62" dependency-review escape-hatch
    checkruns "$S63" frontend-test escape-hatch
    run_dispatch "$AW" 930
    expect_eq "終わり方は 0" "$RC" 0
    expect_eq "frontend-test と escape-hatch が赤の PR だけが起動される" "$(dispatched)" "dependabot 63"
    expect_eq "入力 checks が frontend-test だけになる" "$(input dependabot 63 checks)" '["frontend-test"]'
    expect_eq "Dependabot の PR には入力 pr を渡さない(key が PR の番号)" "$(input dependabot 63 pr)" "(無し)"
    if summary_has "起動しなかった: dependabot 60(赤の検査が、直しても緑にならない5つの検査だけ)"; then
        ok "赤の検査が dependency-review だけの PR が外れる"
    else
        ng "赤の検査が dependency-review だけの PR が外れる"
    fi
    if summary_has "起動しなかった: dependabot 61("; then
        ok "記録のコメントの無い dependency-cooldown だけの PR が外れる"
    else
        ng "記録のコメントの無い dependency-cooldown だけの PR が外れる"
    fi
    if summary_has "起動しなかった: dependabot 62("; then
        ok "dependency-review と escape-hatch の2つの PR が外れる"
    else
        ng "dependency-review と escape-hatch の2つの PR が外れる"
    fi
fi

# --- 利用者が書いた中身 -------------------------------------------------------------------
if want user_content; then
    echo "[user_content] 利用者が書いた Issue とコメントの中身を対象を選ぶ材料にしない"
    reset
    alerts 40 41 >"$FX/codeql-alerts.json"
    arr \
        "$(issue 710 someone "知らせ" '<!-- claude-auto-fix-issue key=codeql:40 kind=unfixed run=1 -->')" \
        "$(issue 711 "$BOT" "知らせ" '<!-- claude-auto-fix-issue key=codeql:41 kind=unavailable run=1 -->')" >"$FX/issues-caf.json"
    arr "$(comment someone '<!-- claude-auto-fix-issue key=codeql:41 kind=unfixed run=2 -->' 2026-11-10T00:00:00Z)" >"$FX/comments-711.json"
    # ラベルの無い、利用者のブランチの PR は Claude の変更の PR に数えない
    arr "$(pull 530 someone 3333333333333333333333333333333333333333 open fix/claude-auto-fix-codeql-40 owner/repo '[]')" >"$FX/pulls.json"
    run_dispatch "$AW" 940
    expect_eq "利用者が書いた知らせの Issue とコメントでは止まらない" "$(dispatched)" "codeql 40,codeql 41"

    reset
    arr \
        "$(issue 320 someone "コンテナ脆弱性: CVE-2026-0020" "本文 $(state true)")" \
        "$(issue 321 "$BOT" "コンテナ脆弱性: CVE-2026-0021" "本文 $(state false)")" \
        "$(issue 322 "$BOT" "コンテナ脆弱性: CVE-2026-0022" "本文 $(state true)")" >"$FX/issues-cv.json"
    arr "$(comment someone "書き換え $(state true)" 2026-11-10T00:00:00Z)" >"$FX/comments-321.json"
    arr "$(comment someone '<!-- claude-auto-fix-notice kind=unfixed run=9 -->' 2026-11-10T00:00:00Z)" >"$FX/comments-322.json"
    run_dispatch "$CW" 941
    expect_eq "利用者が起票した Issue と、利用者が書いた状態の目印と知らせの目印を読まない" "$(dispatched)" "container CVE-2026-0022"
fi

# --- 絞り込み ----------------------------------------------------------------------------
if want claude_pr; then
    echo "[claude_pr] 開いている Claude の変更の PR がある key では起動されない"
    reset
    alerts 17 20 25 >"$FX/codeql-alerts.json"
    arr \
        "$(pull 501 DogisRiki-bot 1111111111111111111111111111111111111111 open fix/claude-auto-fix-codeql-17 owner/repo "$CAF_LABELS")" \
        "$(pull 502 someone 2222222222222222222222222222222222222222 open fix/claude-auto-fix-codeql-20 someone/repo "$CAF_LABELS")" \
        "$(pull 503 DogisRiki-bot 4444444444444444444444444444444444444444 open fix/claude-auto-fix-codeql-25 owner/repo '[]')" >"$FX/pulls.json"
    run_dispatch "$AW" 950
    expect_eq "Claude の変更の PR が開いている key だけが外れる(fork とラベルの無い PR は数えない)" "$(dispatched)" "codeql 20,codeql 25"
    if summary_has "起動しなかった: CodeQL の警告 #17(同じ対象の Claude の変更の PR が開いている)"; then
        ok "起動しなかった理由を GITHUB_STEP_SUMMARY に書く"
    else
        ng "起動しなかった理由を GITHUB_STEP_SUMMARY に書く"
    fi
fi

if want vuln_branch; then
    echo "[vuln_branch] 同じ組の vuln-fix のブランチがあれば起動されない"
    reset
    trigger_run "$FW" failure >"$FX/run-960.json"
    {
        echo '{"kind":"npm","group":{"name":"lodash","version":"4.17.21","ranges":[],"urgent":false,"alerts":[1]},"reason":"r"}'
        echo '{"kind":"npm","group":{"name":"@scope/pkg","version":"1.2.3","ranges":[],"urgent":false,"alerts":[2]},"reason":"r"}'
    } >"$FX/artifact-960-vuln-fix-unresolved.jsonl"
    # 名前が前の方だけ同じブランチは、同じ組のブランチに数えない
    jq -nc '[{ref: "refs/heads/chore/frontend-vuln-fix-lodash-4-17-21"}, {ref: "refs/heads/chore/frontend-vuln-fix-scope-pkg-1-2-3-old"}]' \
        >"$FX/refs.json"
    run_dispatch "$FW" 960
    expect_eq "同じ組の vuln-fix のブランチがある組だけが外れる" "$(dispatched)" "npm @scope/pkg@1.2.3"
    if grep -Fq 'git/matching-refs/heads/chore/frontend-vuln-fix-lodash-4-17-21' "$FAKE_LOG"; then
        ok "vuln-fix のブランチの名前で読む"
    else
        ng "vuln-fix のブランチの名前で読む"
    fi
fi

if want unfixed_issue; then
    echo "[unfixed_issue] unfixed の知らせの Issue がある key では trigger で起動されない"
    reset
    alerts 50 53 >"$FX/codeql-alerts.json"
    arr \
        "$(issue 700 "$BOT" "知らせ" '<!-- claude-auto-fix-issue key=codeql:50 kind=unfixed run=1 -->')" \
        "$(issue 702 "$BOT" "知らせ" '<!-- claude-auto-fix-issue key=codeql:530 kind=unfixed run=1 -->')" >"$FX/issues-caf.json"
    run_dispatch "$AW" 970
    expect_eq "unfixed の知らせの Issue がある key だけが外れる(key の前の方だけ同じ Issue は数えない)" "$(dispatched)" "codeql 53"
    if summary_has "起動しなかった: CodeQL の警告 #50(直せなかったことを知らせる Issue が開いている)"; then
        ok "起動しなかった理由を GITHUB_STEP_SUMMARY に書く"
    else
        ng "起動しなかった理由を GITHUB_STEP_SUMMARY に書く"
    fi
fi

if want container_unfixed; then
    echo "[container_unfixed] 直せなかったことを書いたコメントが付いたコンテナの Issue では trigger で起動されない"
    reset
    arr "$(issue 306 "$BOT" "コンテナ脆弱性: CVE-2026-0006" "本文 $(state true)")" >"$FX/issues-cv.json"
    arr "$(comment "$BOT" '<!-- claude-auto-fix-notice kind=unfixed run=5 -->' 2026-11-10T00:00:00Z)" >"$FX/comments-306.json"
    run_dispatch "$CW" 980
    expect_eq "起動しない" "$(dispatched)" ""
    if summary_has "起動しなかった: container CVE-2026-0006(直せなかったことを書いたコメントがある)"; then
        ok "起動しなかった理由を GITHUB_STEP_SUMMARY に書く"
    else
        ng "起動しなかった理由を GITHUB_STEP_SUMMARY に書く"
    fi
fi

if want unavailable; then
    echo "[unavailable] unavailable の知らせの Issue があっても起動される"
    reset
    alerts 51 52 >"$FX/codeql-alerts.json"
    arr \
        "$(issue 701 "$BOT" "知らせ" '<!-- claude-auto-fix-issue key=codeql:51 kind=unfixed run=1 -->')" \
        "$(issue 703 "$BOT" "知らせ" '<!-- claude-auto-fix-issue key=codeql:52 kind=unavailable run=1 -->')" >"$FX/issues-caf.json"
    # 701 は、あとの実行が動けなかったことを書き足し、状態が unavailable になった
    arr "$(comment "$BOT" '<!-- claude-auto-fix-issue key=codeql:51 kind=unavailable run=2 -->' 2026-11-10T00:00:00Z)" >"$FX/comments-701.json"
    run_dispatch "$AW" 990
    expect_eq "状態が unavailable の知らせの Issue の key は起動される" "$(dispatched)" "codeql 51,codeql 52"
fi

if want same_day; then
    echo "[same_day] その日の実行がある表示名では起動されない"
    reset
    alerts 60 61 61 62 63 >"$FX/codeql-alerts.json"
    jq -nc --argjson runs "$(arr \
        "$(target_run 'claude-auto-fix codeql 60' completed "$NOW")" \
        "$(target_run 'claude-auto-fix codeql 61' completed "$YESTERDAY")" \
        "$(target_run 'claude-auto-fix codeql 62' in_progress "$YESTERDAY")" \
        "$(target_run 'claude-auto-fix codeql 63' queued "$YESTERDAY")" \
        "$(target_run 'claude-auto-fix codeql 610' completed "$NOW")")" '{workflow_runs: $runs}' >"$FX/target-runs.json"
    run_dispatch "$AW" 1000
    expect_eq "今日の実行と、終わっていない実行がある表示名は外れ、同じ対象は1回だけ起動する" "$(dispatched)" "codeql 61"
    if grep -Fq 'actions/workflows/claude-auto-fix-target.yaml/runs?created=%3E%3D' "$FAKE_LOG"; then
        ok "対象ごとの実行の一覧を、作られた日時で絞って読む"
    else
        ng "対象ごとの実行の一覧を、作られた日時で絞って読む"
    fi
    if summary_has "起動しなかった: CodeQL の警告 #60(同じ表示名の実行が、待っているか動いているか、今日すでにある)"; then
        ok "起動しなかった理由を GITHUB_STEP_SUMMARY に書く"
    else
        ng "起動しなかった理由を GITHUB_STEP_SUMMARY に書く"
    fi
fi

# --- 所有者の手での起動(manual) ----------------------------------------------------------
if want manual; then
    echo "[manual] manual で4つの集め方をすべて使う"
    reset
    vuln_runs fw 1101
    echo "{\"kind\":\"npm\",\"group\":${LODASH},\"reason\":\"r\"}" >"$FX/artifact-1101-vuln-fix-unresolved.jsonl"
    arr "$(dep_alert npm lodash 4.17.21)" >"$FX/dependabot-alerts.json"
    alerts 30 31 >"$FX/codeql-alerts.json"
    arr "$(pull 63 'dependabot[bot]' 6300000000000000000000000000000000000000 open dependabot/d owner/repo '[]')" >"$FX/pulls.json"
    checkruns 6300000000000000000000000000000000000000 frontend-test
    arr "$(issue 300 "$BOT" "コンテナ脆弱性: CVE-2026-0001" "本文 $(state true)")" >"$FX/issues-cv.json"
    # 300 は、この仕組みが1度扱った Issue である。manual では、扱ったかどうかによらず対象にする
    arr "$(comment "$BOT" '<!-- claude-auto-fix-notice kind=pr run=77 -->' 2026-11-10T00:00:00Z)" >"$FX/comments-300.json"
    # codeql 30 は今日すでに実行がある。codeql 31 は実行が動いている
    add_run "$(target_run 'claude-auto-fix codeql 30' completed "$NOW")"
    add_run "$(target_run 'claude-auto-fix codeql 31' in_progress "$YESTERDAY")"
    run_mode manual
    expect_eq "終わり方は 0" "$RC" 0
    expect_eq "4つの集め方の対象が起動され、今日の実行がある対象も起動される" "$(dispatched)" \
        "codeql 30,container CVE-2026-0001,dependabot 63,npm lodash@4.17.21"
    expect_eq "入力 reason は manual" "$(jq -rs 'map(.reason) | unique | join(",")' "$DISPATCH_LOG")" manual
    expect_eq "Dependabot の PR の入力 checks は、5つの検査を除いた赤の検査" "$(input dependabot 63 checks)" '["frontend-test"]'
    expect_eq "vuln-fix の組の入力 detail は、最新の実行の成果物の組" "$(input npm lodash@4.17.21 detail | jq -c .)" "$LODASH"
    if summary_has "起動しなかった: CodeQL の警告 #31(同じ表示名の実行が、待っているか動いているか、今日すでにある)"; then
        ok "動いている実行がある表示名は、manual でも起動しない"
    else
        ng "動いている実行がある表示名は、manual でも起動しない"
    fi
    no_write "Issue と PR とコメントを書かない"
    run_mode manual
    expect_eq "同じ偽の応答で2回呼んでも、起動される実行が増えない" "$(count)" 4
fi

if want manual_vuln; then
    echo "[manual_vuln] manual でまだ脆弱な vuln-fix の組だけを残す"
    reset
    # 1102 は古い実行なので読まない。1103 が最新の実行である
    vuln_runs fw 1102 1103
    echo '{"kind":"npm","group":{"name":"old","version":"1.0.0","ranges":[],"urgent":false,"alerts":[9]},"reason":"r"}' \
        >"$FX/artifact-1102-vuln-fix-unresolved.jsonl"
    {
        echo "{\"kind\":\"npm\",\"group\":${LODASH},\"reason\":\"r\"}"
        echo "{\"kind\":\"npm\",\"group\":${MINIMIST},\"reason\":\"r\"}"
    } >"$FX/artifact-1103-vuln-fix-unresolved.jsonl"
    # PR で動いた、もっと新しい同じ名前のワークフローの実行は読まない
    jq -c '.workflow_runs += [{id: 1104, event: "pull_request", status: "completed", created_at: "2026-11-30T00:00:00Z",
        repository: {full_name: "owner/repo"}, head_repository: {full_name: "someone/repo"}}]' "$FX/fw-runs.json" >"$FX/fw-runs.tmp" &&
        mv "$FX/fw-runs.tmp" "$FX/fw-runs.json"
    vuln_runs bw 1105
    echo '{"kind":"maven","group":{"name":"com.example:lib","version":"2.0.1","ranges":[],"urgent":false,"alerts":[5]},"reason":"r"}' \
        >"$FX/artifact-1105-vuln-fix-unresolved-java.jsonl"
    {
        echo '{"kind":"go-stdlib","group":{"version":"1.24.6","osv":["GO-2026-0002"]},"reason":"r"}'
        echo '{"kind":"go-module","group":{"module":"golang.org/x/net","version":"0.40.0","osv":["GO-2026-0003"]},"reason":"r"}'
    } >"$FX/artifact-1105-vuln-fix-unresolved-go.jsonl"
    # minimist の警告は閉じている。x/net は main の go.mod で修正版より新しい。標準ライブラリは go1.24.4 で古い
    arr "$(dep_alert npm lodash 4.17.21)" "$(dep_alert maven com.example:lib 2.0.1)" "$(dep_alert npm old 1.0.0)" \
        >"$FX/dependabot-alerts.json"
    run_mode manual
    expect_eq "終わり方は 0" "$RC" 0
    expect_eq "まだ脆弱な組だけが起動される" "$(dispatched)" "go-stdlib 1.24.6,maven com.example:lib@2.0.1,npm lodash@4.17.21"
    if summary_has "起動しなかった: npm minimist@1.2.8(main ではもう脆弱でない)" &&
        summary_has "起動しなかった: go-module golang.org/x/net@0.40.0(main ではもう脆弱でない)"; then
        ok "もう脆弱でない組が外れる"
    else
        ng "もう脆弱でない組が外れる"
    fi
    if grep -Eq '^run download (1102|1104) ' "$FAKE_LOG"; then ng "最新でない実行と PR の実行の成果物を読まない"; else ok "最新でない実行と PR の実行の成果物を読まない"; fi
fi

if want manual_unfixed; then
    echo "[manual_unfixed] manual で unfixed の Issue があっても起動される"
    reset
    alerts 50 >"$FX/codeql-alerts.json"
    arr "$(issue 700 "$BOT" "知らせ" '<!-- claude-auto-fix-issue key=codeql:50 kind=unfixed run=1 -->')" >"$FX/issues-caf.json"
    arr "$(issue 306 "$BOT" "コンテナ脆弱性: CVE-2026-0006" "本文 $(state true)")" >"$FX/issues-cv.json"
    arr "$(comment "$BOT" '<!-- claude-auto-fix-notice kind=unfixed run=5 -->' 2026-11-10T00:00:00Z)" >"$FX/comments-306.json"
    run_mode manual
    expect_eq "unfixed の知らせの Issue と、直せなかったことを書いたコメントがあっても起動される" "$(dispatched)" \
        "codeql 50,container CVE-2026-0006"
fi

if want manual_stuck; then
    echo "[manual_stuck] manual でも5つの検査だけが赤の PR が外れる"
    reset
    arr \
        "$(pull 60 'dependabot[bot]' 6000000000000000000000000000000000000000 open dependabot/a owner/repo '[]')" \
        "$(pull 63 'dependabot[bot]' 6300000000000000000000000000000000000000 open dependabot/d owner/repo '[]')" >"$FX/pulls.json"
    checkruns 6000000000000000000000000000000000000000 dependency-review
    checkruns 6300000000000000000000000000000000000000 frontend-test
    run_mode manual
    expect_eq "5つの検査のほかに赤の検査がある PR だけが起動される" "$(dispatched)" "dependabot 63"
    if summary_has "起動しなかった: dependabot 60(赤の検査が、直しても緑にならない5つの検査だけ)"; then
        ok "赤の検査が dependency-review だけの PR が外れる"
    else
        ng "赤の検査が dependency-review だけの PR が外れる"
    fi
fi

# --- 1時間ごとの動かし直し(retry) --------------------------------------------------------
if want retry_unavailable; then
    echo "[retry_unavailable] 前の日に unavailable か blocked で終わった対象が retry で起動される"
    reset
    outcome 2001 "$YESTERDAY" "$(rec codeql 70 unavailable trigger "$YESTERDAY")"
    outcome 2002 "$YESTERDAY" "$(rec npm lodash@4.17.21 blocked manual "$YESTERDAY" "{\"detail\":${LODASH}}")"
    outcome 2003 "$YESTERDAY" "$(rec dependabot 64 unavailable trigger "$YESTERDAY" '{"checks":["frontend-test"]}')"
    # codeql 73 は、動けなかったあとの実行で PR ができた。codeql 72 は直せなかった
    outcome 2004 "$TWO_DAYS_AGO" "$(rec codeql 73 unavailable trigger "$TWO_DAYS_AGO")"
    outcome 2005 "$YESTERDAY" "$(rec codeql 73 pr trigger "$YESTERDAY")"
    outcome 2006 "$YESTERDAY" "$(rec codeql 72 unfixed trigger "$YESTERDAY")"
    # Claude の変更の PR の赤の検査を直す実行は、PR の今の head で動かし直す
    outcome 2007 "$YESTERDAY" "$(rec codeql 74 unavailable red-check "$YESTERDAY" '{"pr":520,"checks":["frontend-test"]}')"
    arr "$(pull 520 DogisRiki-bot 7474747474747474747474747474747474747474 open fix/claude-auto-fix-codeql-74 owner/repo "$CAF_LABELS")" \
        >"$FX/pulls.json"
    # 3日続けて動けなかったことを知らせる Issue が開いていても起動する(要件6の2)
    arr "$(issue 704 "$BOT" "知らせ" '<!-- claude-auto-fix-issue key=codeql:70 kind=unavailable run=1 -->')" >"$FX/issues-caf.json"
    run_mode retry
    expect_eq "終わり方は 0" "$RC" 0
    expect_eq "前の日に unavailable か blocked で終わった対象だけが起動される" "$(dispatched)" \
        "codeql 70,codeql 74,dependabot 64,npm lodash@4.17.21"
    expect_eq "入力 reason は結果のファイルのまま" "$(input codeql 70 reason),$(input npm lodash@4.17.21 reason)" "trigger,manual"
    expect_eq "入力 detail は結果のファイルのまま" "$(input npm lodash@4.17.21 detail | jq -c .)" "$LODASH"
    expect_eq "入力 checks は結果のファイルのまま" "$(input dependabot 64 checks)" '["frontend-test"]'
    expect_eq "赤の検査を直す実行は、PR の番号と赤の検査を渡す" \
        "$(input codeql 74 reason) $(input codeql 74 pr) $(input codeql 74 checks)" 'red-check 520 ["frontend-test"]'
    expect_eq "赤の検査を直す実行は、表示名に使う PR の今の head の SHA の先頭12文字を渡す" "$(input codeql 74 head)" 747474747474
    no_write "Issue と PR とコメントを書かない"
    run_mode retry
    expect_eq "同じ偽の応答で2回呼んでも、起動される実行が増えない" "$(count)" 4
fi

if want retry_today; then
    echo "[retry_today] 今日すでに実行がある対象は retry で起動されない"
    reset
    outcome 2011 "$YESTERDAY" "$(rec codeql 80 unavailable trigger "$YESTERDAY")"
    add_run "$(target_run 'claude-auto-fix codeql 80' in_progress "$NOW")"
    # codeql 81 は昨日始まって今日終わった。codeql 82 は今日始まって今日終わった
    outcome 2012 "$YESTERDAY" "$(rec codeql 81 unavailable trigger "$NOW")"
    outcome 2013 "$NOW" "$(rec codeql 82 blocked trigger "$NOW")"
    run_mode retry
    expect_eq "終わり方は 0" "$RC" 0
    expect_eq "何も起動しない" "$(dispatched)" ""
    if summary_has "起動しなかった: CodeQL の警告 #80(同じ表示名の実行が、待っているか動いているか、今日すでにある)" &&
        summary_has "起動しなかった: CodeQL の警告 #81(動けなかった実行が終わったのが今日)" &&
        summary_has "起動しなかった: CodeQL の警告 #82(動けなかった実行が終わったのが今日)"; then
        ok "起動しなかった理由を GITHUB_STEP_SUMMARY に書く"
    else
        ng "起動しなかった理由を GITHUB_STEP_SUMMARY に書く"
    fi
fi

if want retry_cancelled; then
    echo "[retry_cancelled] 取り消されて結果のファイルが無い実行を unavailable と数えて入力を作る"
    reset
    outcome 2021 "$TWO_DAYS_AGO" "$(rec npm lodash@4.17.21 unavailable trigger "$TWO_DAYS_AGO" "{\"detail\":${LODASH}}")"
    cancelled 2022 'claude-auto-fix npm lodash@4.17.21' "$YESTERDAY"
    cancelled 2023 'claude-auto-fix codeql 90' "$YESTERDAY"
    cancelled 2024 'claude-auto-fix npm minimist@1.2.8' "$YESTERDAY"
    cancelled 2025 'claude-auto-fix maven com.example:gone@1.0.0' "$YESTERDAY"
    vuln_runs fw 1201
    echo "{\"kind\":\"npm\",\"group\":${MINIMIST},\"reason\":\"r\"}" >"$FX/artifact-1201-vuln-fix-unresolved.jsonl"
    run_mode retry
    expect_eq "終わり方は 0" "$RC" 0
    expect_eq "取り消された実行の対象が起動される" "$(dispatched)" "codeql 90,npm lodash@4.17.21,npm minimist@1.2.8"
    expect_eq "取り消された実行の入力 reason は retry" "$(input codeql 90 reason)" retry
    expect_eq "vuln-fix の種類の入力 detail は、同じ key の前の結果のファイルから作る" \
        "$(input npm lodash@4.17.21 detail | jq -c .)" "$LODASH"
    expect_eq "前の結果のファイルが無ければ、vuln-fix の最新の成果物の組から作る" \
        "$(input npm minimist@1.2.8 detail | jq -c .)" "$MINIMIST"
    if summary_has "起動しなかった: maven com.example:gone@1.0.0(入力 detail を作れない"; then
        ok "入力を作れない対象は起動しない"
    else
        ng "入力を作れない対象は起動しない"
    fi
fi

if want retry_origin; then
    echo "[retry_origin] このリポジトリの main から手で起動された実行だけを数え、赤の検査の名前が無い赤の検査の実行は起動しない"
    reset
    fork='{"event": "pull_request", "head_branch": "fix", "head_repository": {"full_name": "someone/repo"}}'
    # フォークの PR から動いた、表示名が対象ごとの実行と同じ実行。結果のファイルがあってもなくても数えない
    outcome 2041 "$YESTERDAY" "$(rec codeql 110 unavailable trigger "$YESTERDAY")"
    jq -c --argjson f "$fork" '.workflow_runs |= map(if .id == 2041 then . + $f else . end)' "$FX/target-runs.json" >"$FX/target-runs.tmp" &&
        mv "$FX/target-runs.tmp" "$FX/target-runs.json"
    add_run "$(jq -nc --argjson f "$fork" '{id: 2042, display_title: "claude-auto-fix codeql 111", status: "completed",
        conclusion: "failure", created_at: "'"$YESTERDAY"'", updated_at: "'"$YESTERDAY"'",
        html_url: "https://example.test/runs/2042"} + $f')"
    # 対象 codeql 112 は動けなかった。フォークの PR から動いた同じ表示名の実行が今日あっても、起動を止めない
    outcome 2043 "$YESTERDAY" "$(rec codeql 112 unavailable trigger "$YESTERDAY")"
    add_run "$(target_run 'claude-auto-fix codeql 112' in_progress "$NOW" | jq -c --argjson f "$fork" '. + $f + {id: 2044}')"
    # 赤の検査を直す実行が、赤の検査の名前を残さずに取り消された
    arr "$(pull 530 DogisRiki-bot 7575757575757575757575757575757575757575 open fix/claude-auto-fix-codeql-113 owner/repo "$CAF_LABELS")" \
        >"$FX/pulls.json"
    cancelled 2045 'claude-auto-fix codeql 113 pr#530@757575757575' "$YESTERDAY"
    run_mode retry
    expect_eq "終わり方は 0" "$RC" 0
    expect_eq "このリポジトリの main から手で起動された実行の対象だけが起動される" "$(dispatched)" "codeql 112"
    if summary_has "起動しなかった: CodeQL の警告 #113(赤の検査を直す PR #530 の、赤の検査の名前が結果のファイルに無い)"; then
        ok "赤の検査の名前が無い赤の検査の実行は、理由を GITHUB_STEP_SUMMARY に書いて起動しない"
    else
        ng "赤の検査の名前が無い赤の検査の実行は、理由を GITHUB_STEP_SUMMARY に書いて起動しない"
    fi
    if grep -qE 'run download 204[12] |runs/204[12]/' "$FAKE_LOG"; then ng "出どころが違う実行の結果のファイルは読まない"; else ok "出どころが違う実行の結果のファイルは読まない"; fi
fi

# --- 鍵の Issue ---------------------------------------------------------------------------
if want key_open; then
    echo "[key_open] 鍵の Issue が開いている間は1日に1つだけ起動される"
    reset
    arr "$(key_issue)" >"$FX/issues-caf.json"
    outcome 2031 "$YESTERDAY" "$(rec codeql 100 key trigger "$YESTERDAY")"
    outcome 2032 "$YESTERDAY" "$(rec codeql 101 key trigger "$YESTERDAY")"
    outcome 2033 "$YESTERDAY" "$(rec codeql 102 unavailable trigger "$YESTERDAY")"
    alerts 103 >"$FX/codeql-alerts.json"
    run_mode retry
    expect_eq "終わり方は 0" "$RC" 0
    expect_eq "結果が key の対象から1つだけ起動される" "$(dispatched)" "codeql 100"
    run_mode retry
    expect_eq "同じ日の2回目の retry では起動しない" "$(count)" 1
    run_dispatch "$AW" 2034
    expect_eq "鍵の Issue が開いている間は trigger で起動しない" "$(count)" 1
    run_mode manual
    expect_eq "鍵の Issue が開いている間は manual で起動しない" "$(count)" 1
    if summary_has "鍵の Issue が開いている"; then ok "起動しなかった理由を GITHUB_STEP_SUMMARY に書く"; else ng "起動しなかった理由を GITHUB_STEP_SUMMARY に書く"; fi
    # 利用者が起票した同じ題名の Issue は、鍵の Issue に数えない
    reset
    arr "$(issue 801 someone "Claude を動かす鍵を取り替えてください" "<!-- claude-auto-fix-key -->")" >"$FX/issues-caf.json"
    alerts 104 105 >"$FX/codeql-alerts.json"
    run_dispatch "$AW" 2035
    expect_eq "利用者が起票した同じ題名の Issue では止まらない" "$(dispatched)" "codeql 104,codeql 105"
fi

if want key_open_none; then
    echo "[key_open_none] 鍵の Issue が開いていて key の対象が直近4日に無いとき4つの集め方から1つだけ起動される"
    reset
    arr "$(key_issue)" "$(issue 705 "$BOT" "知らせ" '<!-- claude-auto-fix-issue key=codeql:110 kind=unfixed run=1 -->')" \
        >"$FX/issues-caf.json"
    outcome 2041 "$YESTERDAY" "$(rec codeql 112 unavailable trigger "$YESTERDAY")"
    alerts 110 111 113 >"$FX/codeql-alerts.json"
    run_mode retry
    expect_eq "終わり方は 0" "$RC" 0
    expect_eq "1つだけ起動される(unfixed の知らせの Issue がある key は鍵を確かめる対象にしない)" "$(dispatched)" "codeql 111"
    expect_eq "入力 reason は retry" "$(input codeql 111 reason)" retry
    if summary_has "結果が key の対象が直近4日に無い"; then ok "集め方を変えた理由を GITHUB_STEP_SUMMARY に書く"; else ng "集め方を変えた理由を GITHUB_STEP_SUMMARY に書く"; fi
fi

if want key_closed; then
    echo "[key_closed] 4日より前に key で終わった対象が、鍵の Issue が閉じてから25時間のうちの retry で起動される"
    reset
    arr "$(closed_key_issue "$(ago 7200)")" >"$FX/issues-caf-closed.json"
    # codeql 120 は、4日より前に key で終わったので、直近4日の結果のファイルに無い
    alerts 120 >"$FX/codeql-alerts.json"
    outcome 2051 "$YESTERDAY" "$(rec codeql 121 key trigger "$YESTERDAY")"
    run_mode retry
    expect_eq "終わり方は 0" "$RC" 0
    expect_eq "集め直した対象と、結果が key の対象がすべて起動される" "$(dispatched)" "codeql 120,codeql 121"
    expect_eq "集め直した対象の入力 reason は retry" "$(input codeql 120 reason)" retry
    if grep -Fq 'issues?labels=claude-auto-fix&state=closed&since=' "$FAKE_LOG"; then
        ok "閉じた鍵の Issue を、閉じた日時の近いものに絞って読む"
    else
        ng "閉じた鍵の Issue を、閉じた日時の近いものに絞って読む"
    fi
    run_mode retry
    expect_eq "25時間のうちに何度集め直しても、同じ表示名の実行は1日に1回しか起動しない" "$(count)" 2
fi

if want key_closed_late; then
    echo "[key_closed_late] 25時間を過ぎた retry では集め直さない"
    reset
    arr "$(closed_key_issue "$(ago 93600)")" >"$FX/issues-caf-closed.json"
    alerts 130 >"$FX/codeql-alerts.json"
    run_mode retry
    expect_eq "終わり方は 0" "$RC" 0
    expect_eq "何も起動しない" "$(dispatched)" ""
    if grep -Fq 'code-scanning' "$FAKE_LOG"; then ng "CodeQL の警告を読まない"; else ok "CodeQL の警告を読まない"; fi
    # 利用者が起票して閉じた同じ題名の Issue では集め直さない
    reset
    arr "$(issue 802 someone "Claude を動かす鍵を取り替えてください" "<!-- claude-auto-fix-key -->" | jq -c --arg at "$(ago 7200)" '. + {closed_at: $at}')" \
        >"$FX/issues-caf-closed.json"
    alerts 131 >"$FX/codeql-alerts.json"
    run_mode retry
    expect_eq "利用者が起票した Issue が閉じても集め直さない" "$(dispatched)" ""
fi

if want recollect_filters; then
    echo "[recollect_filters] 集め直しで unfixed の Issue がある key と1度扱ったコンテナの Issue が起動されない"
    reset
    arr "$(closed_key_issue "$(ago 7200)")" >"$FX/issues-caf-closed.json"
    alerts 140 141 >"$FX/codeql-alerts.json"
    arr "$(issue 706 "$BOT" "知らせ" '<!-- claude-auto-fix-issue key=codeql:140 kind=unfixed run=1 -->')" >"$FX/issues-caf.json"
    arr \
        "$(issue 330 "$BOT" "コンテナ脆弱性: CVE-2026-0030" "本文 $(state true)")" \
        "$(issue 331 "$BOT" "コンテナ脆弱性: CVE-2026-0031" "本文 $(state true)")" >"$FX/issues-cv.json"
    arr "$(comment "$BOT" '<!-- claude-auto-fix-notice kind=pr run=78 -->' 2026-11-10T00:00:00Z)" >"$FX/comments-331.json"
    run_mode retry
    expect_eq "終わり方は 0" "$RC" 0
    expect_eq "unfixed の Issue がある key と1度扱ったコンテナの Issue が外れる" "$(dispatched)" "codeql 141,container CVE-2026-0030"
    if summary_has "起動しなかった: CodeQL の警告 #140(直せなかったことを知らせる Issue が開いている)" &&
        summary_has "起動しなかった: container CVE-2026-0031(この仕組みが1度扱った)"; then
        ok "起動しなかった理由を GITHUB_STEP_SUMMARY に書く"
    else
        ng "起動しなかった理由を GITHUB_STEP_SUMMARY に書く"
    fi
fi

# --- 読めなかったとき ------------------------------------------------------------------------
if want fails; then
    echo "[fails] 1つの集め方か対象で読めなくても、ほかを続けて 1 で終わる"
    reset
    alerts 30 >"$FX/codeql-alerts.json"
    arr "$(pull 63 'dependabot[bot]' 6300000000000000000000000000000000000000 open dependabot/d owner/repo '[]')" >"$FX/pulls.json"
    checkruns 6300000000000000000000000000000000000000 frontend-test
    export FAIL_EP=code-scanning
    run_dispatch "$AW" 1010
    expect_eq "CodeQL の警告を読めなくても Dependabot の PR は起動される" "$(dispatched)" "dependabot 63"
    expect_eq "読めなかったときは 1 で終わる" "$RC" 1
    if grep -q '^::error::' "$WORK/err"; then ok "::error:: の行を出す"; else ng "::error:: の行を出す"; fi

    reset
    trigger_run "$BW" failure >"$FX/run-1011.json"
    echo '{"kind":"go-module","group":{"module":"golang.org/x/net","version":"0.40.0","osv":["GO-2026-0003"]},"reason":"r"}' \
        >"$FX/artifact-1011-vuln-fix-unresolved-go.jsonl"
    run_dispatch "$BW" 1011
    expect_eq "Java の成果物を読めなくても Go の組は起動される" "$(dispatched)" "go-module golang.org/x/net@0.40.0"
    expect_eq "成果物を読めなかったときは 1 で終わる" "$RC" 1

    reset
    trigger_run "$BW" failure >"$FX/run-1015.json"
    {
        echo '{"kind":"maven","group":{"name":"com.example:lib","version":"2.0.1","ranges":[],"urgent":false,"alerts":[5]},"reason":"r"}'
        echo '{"kind":"maven","group":"broken","reason":"r"}'
    } >"$FX/artifact-1015-vuln-fix-unresolved-java.jsonl"
    echo '{"kind":"go-module","group":{"module":"golang.org/x/net","version":"0.40.0","osv":["GO-2026-0003"]},"reason":"r"}' \
        >"$FX/artifact-1015-vuln-fix-unresolved-go.jsonl"
    run_dispatch "$BW" 1015
    expect_eq "形の違う行のある成果物の組は、前の正しい行も起動しない" "$(dispatched)" "go-module golang.org/x/net@0.40.0"
    expect_eq "形の違う行のある成果物があれば 1 で終わる" "$RC" 1

    reset
    alerts 30 >"$FX/codeql-alerts.json"
    export FAIL_EP='issues?labels=claude-auto-fix'
    run_dispatch "$AW" 1016
    expect_eq "ラベル claude-auto-fix の Issue を読めなければ何も起動しない" "$(dispatched)" ""
    expect_eq "ラベル claude-auto-fix の Issue を読めなければ 1 で終わる" "$RC" 1

    reset
    alerts 30 31 >"$FX/codeql-alerts.json"
    arr "$(issue 700 "$BOT" "知らせ" '<!-- claude-auto-fix-issue key=codeql:30 kind=unfixed run=1 -->')" >"$FX/issues-caf.json"
    export FAIL_EP=issues/700/comments
    run_dispatch "$AW" 1012
    expect_eq "1つの対象の知らせの Issue を読めなくても、ほかの対象は起動される" "$(dispatched)" "codeql 31"
    expect_eq "対象を読めなかったときは 1 で終わる" "$RC" 1

    reset
    alerts 30 >"$FX/codeql-alerts.json"
    export FAIL_EP=actions/workflows
    run_dispatch "$AW" 1013
    expect_eq "対象ごとの実行の一覧を読めなければ何も起動しない" "$(dispatched)" ""
    expect_eq "対象ごとの実行の一覧を読めなければ 1 で終わる" "$RC" 1

    reset
    alerts 30 31 >"$FX/codeql-alerts.json"
    export FAIL_DISPATCH=1
    run_dispatch "$AW" 1014
    expect_eq "起動できなかったときは 1 で終わる" "$RC" 1
    expect_eq "起動できなくても、ほかの対象の起動を試す" "$(grep -c '^workflow run' "$FAKE_LOG")" 2

    reset
    outcome 2061 "$YESTERDAY" "$(rec codeql 150 unavailable trigger "$YESTERDAY")"
    export FAIL_EP=artifacts
    run_mode retry
    expect_eq "結果のファイルを読めなければ retry で何も起動しない" "$(dispatched)" ""
    expect_eq "結果のファイルを読めなければ retry は 1 で終わる" "$RC" 1
fi

if [ "$RAN" -eq 0 ]; then
    echo "KP_TEST_CASE の名前に合う場合がありません: ${CASE}" >&2
    exit 1
fi
if [ "$FAILED" -ne 0 ]; then
    echo "test-claude-auto-fix-dispatch: 失敗があります" >&2
    exit 1
fi
echo "test-claude-auto-fix-dispatch: すべて成功しました"
