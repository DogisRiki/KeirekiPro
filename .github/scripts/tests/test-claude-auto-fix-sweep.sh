#!/usr/bin/env bash
# =====================================================================
# claude-auto-fix-sweep.sh の自動テスト
#
# gh は PATH の先頭に置いた偽物に替える。偽の gh は、PR と PR のコミットと検査の結果と、対象ごとの実行と、
# Issue とコメントと、警告を CAP/state.json に持ち、PR を閉じる操作とブランチを消す操作と、コメントの追加と
# Issue を閉じる操作と、対象ごとの実行の起動を、そのファイルに反映する。書く操作は CAP/ops に1行ずつ残し、
# 受け取った引数はすべて CAP/gh.calls に残す。知らない呼び出しは失敗にする。
# 結果を書くスクリプト(claude-auto-fix-report.sh)は、後始末のスクリプトと共通の部品を写したフォルダの中で
# 偽物に替え、受け取った引数と EDIT_OUTCOME の有無を CAP/report.calls に残す。
#
# どの場合も、後始末のスクリプトを同じ偽の応答で2回呼び、2回目で書く操作が増えないことを確かめる。
# 終わりに、マージと却下と @dependabot を含む呼び出しと、Claude の変更の PR のほかの PR を閉じる操作が無いことを
# 確かめる。
#
# 場合の名前を KP_TEST_CASE に入れると、その場合だけを流す(例: KP_TEST_CASE=red_check)。
# 名前は red_check red_check_ref gated_only pending same_head three_strikes gone_pr merged_container notice_gone fails args。
# =====================================================================
set -uo pipefail

HERE="$(cd "$(dirname "$0")/.." && pwd)"
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

# 後始末のスクリプトと共通の部品を写し、結果を書くスクリプトを偽物に替える
S="$WORK/scripts"
mkdir -p "$S"
cp "$HERE/claude-auto-fix-sweep.sh" "$HERE/lib-claude-auto-fix.sh" "$HERE/lib-go-release.sh" "$HERE/lib-notice-comment.sh" "$S/" ||
    { echo "スクリプトを写せません" >&2; exit 1; }
cat >"$S/claude-auto-fix-report.sh" <<'EOF'
#!/usr/bin/env bash
jq -nc --arg e "${EDIT_OUTCOME-unset}" '{args: $ARGS.positional, edit_outcome: $e}' --args "$@" >>"$CAP/report.calls"
[ ! -e "$CAP/report-fail" ] || exit 1
exit 0
EOF

REQ="$WORK/required-checks.json"
cat >"$REQ" <<'EOF'
{"checks": [
  {"context": "frontend-test", "state": "active", "approval_gated": false},
  {"context": "backend-test", "state": "active", "approval_gated": false},
  {"context": "e2e-smoke", "state": "active", "approval_gated": false},
  {"context": "codex-review", "state": "paused", "approval_gated": false},
  {"context": "escape-hatch", "state": "active", "approval_gated": true},
  {"context": "dependency-cooldown", "state": "active", "approval_gated": true},
  {"context": "dependency-review", "state": "active", "approval_gated": false}
]}
EOF

BIN="$WORK/bin"
mkdir -p "$BIN"
cat >"$BIN/gh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" | tr '\n' ' ' >>"$CAP/gh.calls"
echo >>"$CAP/gh.calls"
ST="$CAP/state.json"
save() { mv "$ST.tmp" "$ST"; }
op() { printf '%s\n' "$1" >>"$CAP/ops"; }
fail_on() { [ -n "${FAIL_EP:-}" ] && grep -qF -- "$FAIL_EP" <<<"$1"; }
OWN='{event: "workflow_dispatch", head_branch: "claude-auto-fix/run", repository: {full_name: "o/r"}, head_repository: {full_name: "o/r"},
    path: ".github/workflows/claude-auto-fix-target.yaml"}'
PRVIEW='{number, state, merged_at, updated_at, html_url: ("https://github.com/o/r/pull/" + (.number | tostring)), body,
    user: {login: .author}, labels: [.labels[] | {name: .}], head: {ref: .branch, sha: .sha, repo: {full_name: .repo}}}'
case "$1 ${2:-}" in
"issue close")
    fail_on "issue close $3" && exit 1
    jq --argjson n "$3" '(.issues[] | select(.number == $n) | .state) = "closed"' "$ST" >"$ST.tmp" && save
    op "close-issue $3"
    exit 0 ;;
"workflow run")
    fail_on "workflow run" && exit 1
    [ "$3" = claude-auto-fix-target.yaml ] || { echo "偽の gh: 知らないワークフロー $3" >&2; exit 1; }
    shift 3
    in='{}'
    while [ "$#" -gt 0 ]; do
        case "$1" in
        --ref) [ "$2" = claude-auto-fix/run ] || { echo "偽の gh: --ref が claude-auto-fix/run でない: $2" >&2; exit 1; }; shift 2 ;;
        -R) shift 2 ;;
        -f) in=$(jq -c --arg k "${2%%=*}" --arg v "${2#*=}" '. + {($k): $v}' <<<"$in"); shift 2 ;;
        *) echo "偽の gh: 知らない引数 $1" >&2; exit 1 ;;
        esac
    done
    printf '%s\n' "$in" >>"$CAP/dispatch.jsonl"
    sha=$(jq -r --argjson n "$(jq -r .pr <<<"$in")" '.pulls[] | select(.number == $n) | .sha' "$ST")
    t=$(jq -r --arg s "${sha:0:12}" '"claude-auto-fix \(.kind) \(.key) pr#\(.pr)@\($s)"' <<<"$in")
    jq --arg t "$t" "(.runs += [$OWN + {id: 0, display_title: \$t, status: \"queued\", created_at: \"2026-11-21T10:00:00Z\"}])" \
        "$ST" >"$ST.tmp" && save
    op "dispatch $t"
    exit 0 ;;
esac
[ "$1" = api ] || { echo "偽の gh: 知らない呼び出し: $*" >&2; exit 1; }
shift
method=GET path="" slurp=0 field=""
while [ "$#" -gt 0 ]; do
    case "$1" in
    -X) method="$2"; shift 2 ;;
    -H) shift 2 ;;
    --paginate) shift ;;
    --slurp) slurp=1; shift ;;
    -F | -f) field="$2"; shift 2 ;;
    repos/o/r/*) path="$1"; shift ;;
    *) echo "偽の gh: 知らない引数 $1" >&2; exit 1 ;;
    esac
done
fail_on "$method $path" && { echo "偽の gh: 失敗しました" >&2; exit 1; }
p="${path%%\?*}"
q="${path#"$p"}"
wrap() { if [ "$slurp" = 1 ]; then jq -c '[.]'; else cat; fi; }
case "$method $p" in
"GET repos/o/r/pulls")
    if grep -q 'state=open' <<<"$q"; then
        jq -c "[.pulls[] | select(.state == \"open\") | $PRVIEW]" "$ST" | wrap
    else
        page=$(sed -n 's/.*[?&]page=\([0-9]*\).*/\1/p' <<<"$q")
        if [ "${page:-1}" = 1 ]; then
            jq -c "[.pulls[] | select(.state == \"closed\") | $PRVIEW] | sort_by(.updated_at) | reverse" "$ST"
        else
            echo '[]'
        fi
    fi ;;
GET\ repos/o/r/pulls/*/commits)
    n="${p#repos/o/r/pulls/}"; n="${n%/commits}"
    jq -c --argjson n "$n" '[.pulls[] | select(.number == $n) | .commits[]]' "$ST" | wrap ;;
GET\ repos/o/r/pulls/*)
    n="${p#repos/o/r/pulls/}"
    jq -ce --argjson n "$n" ".pulls[] | select(.number == \$n) | $PRVIEW + {merged: (.merged_at != null)}" "$ST" || exit 1 ;;
PATCH\ repos/o/r/pulls/*)
    n="${p#repos/o/r/pulls/}"
    [ "$field" = state=closed ] || { echo "偽の gh: 知らない欄 $field" >&2; exit 1; }
    jq --argjson n "$n" '(.pulls[] | select(.number == $n) | .state) = "closed"' "$ST" >"$ST.tmp" && save
    op "close-pr $n" ;;
DELETE\ repos/o/r/git/refs/heads/*)
    b="${p#repos/o/r/git/refs/heads/}"
    jq --arg b "$b" '.deleted += [$b]' "$ST" >"$ST.tmp" && save
    op "delete-branch $b" ;;
GET\ repos/o/r/commits/*/check-runs)
    sha="${p#repos/o/r/commits/}"; sha="${sha%/check-runs}"
    jq -c --arg s "$sha" '{total_count: ((.checkruns[$s] // []) | length), check_runs: (.checkruns[$s] // [])}' "$ST" | wrap ;;
"GET repos/o/r/actions/workflows/claude-auto-fix-target.yaml/runs")
    grep -q 'created=%3E%3D' <<<"$q" || { echo "偽の gh: 作成日時の下限が無い" >&2; exit 1; }
    jq -c '{total_count: (.runs | length), workflow_runs: .runs}' "$ST" | wrap ;;
"GET repos/o/r/issues")
    label=$(sed -n 's/.*[?&]labels=\([^&]*\).*/\1/p' <<<"$q")
    jq -c --arg l "$label" '[.issues[] | select(.state == "open" and (.labels | index($l)))
        | {number, title, body, state, user: {login: .author}, created_at: "2026-11-01T00:00:00Z",
           labels: [.labels[] | {name: .}]} + (if .pr then {pull_request: {}} else {} end)]' "$ST" | wrap ;;
GET\ repos/o/r/issues/*/comments)
    n="${p#repos/o/r/issues/}"; n="${n%/comments}"
    jq -c --arg n "$n" '.comments[$n] // []' "$ST" | wrap ;;
POST\ repos/o/r/issues/*/comments)
    n="${p#repos/o/r/issues/}"; n="${n%/comments}"
    f="${field#body=@}"
    jq --arg n "$n" --rawfile b "$f" \
        '.comments[$n] = ((.comments[$n] // []) + [{user: {login: "github-actions[bot]"}, body: $b, created_at: "2026-11-21T10:00:00Z"}])' \
        "$ST" >"$ST.tmp" && save
    op "comment $n $(grep -o '<!-- claude-auto-fix-notice [^>]*-->' "$f" | head -1)"
    echo '{}' ;;
GET\ repos/o/r/code-scanning/alerts/*)
    n="${p#repos/o/r/code-scanning/alerts/}"
    jq -ce --arg n "$n" '.codeql[$n] // empty | {number: ($n | tonumber), state: .}' "$ST" || exit 1 ;;
"GET repos/o/r/dependabot/alerts")
    jq -c '.dalerts' "$ST" | wrap ;;
"GET repos/o/r/contents/backend/go.mod")
    jq -r '.gomod' "$ST" ;;
*) echo "偽の gh: 知らない呼び出し: $method $path" >&2; exit 1 ;;
esac
EOF
chmod +x "$BIN/gh"
export PATH="$BIN:$PATH"
export GITHUB_REPOSITORY="o/r" GITHUB_REPOSITORY_OWNER="o" GH_TOKEN="fake-token" CAF_REQUIRED_CHECKS="$REQ"
# 後始末のスクリプトが結果を書くスクリプトに EDIT_OUTCOME を渡さないことを確かめるため、わざと付けておく
export EDIT_OUTCOME=ok

CAP="$WORK/cap"
export CAP
BOT="github-actions[bot]"
SHA_A=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
SHA_B=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
SHA_C=cccccccccccccccccccccccccccccccccccccccc
SHA_D=dddddddddddddddddddddddddddddddddddddddd
SHA_E=eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee
ago() { date -u -d "@$(($(date -u +%s) - $1))" +%Y-%m-%dT%H:%M:%SZ; }

reset() {
    rm -rf "$CAP"
    mkdir -p "$CAP"
    : >"$CAP/ops"
    : >"$CAP/gh.calls"
    : >"$CAP/report.calls"
    : >"$CAP/dispatch.jsonl"
    jq -n '{pulls: [], checkruns: {}, runs: [], issues: [], comments: {}, codeql: {}, dalerts: [],
        gomod: "module example.com/x\n\ngo 1.25.0\n", deleted: []}' >"$CAP/state.json"
}
# 状態のファイルを、標準入力の JSON で置き換える(使い方: jq <引数...> <式> "$CAP/state.json" | store)
store() {
    local s
    if ! s=$(cat) || [ -z "$s" ]; then
        echo "状態のファイルを書けません" >&2
        return 1
    fi
    printf '%s\n' "$s" >"$CAP/state.json"
}
# 状態のファイルを、引数を取らない jq の式で変える: put <jq の式>
put() { jq "$1" "$CAP/state.json" | store; }
# PR の本文: pr_body <種類> <key> [detail の JSON]
pr_body() {
    printf 'claude-auto-fix の仕組みが作った PR です。\n<!-- claude-auto-fix-pr kind=%s key=%s -->\n' "$1" "$2"
    [ -z "${3:-}" ] || printf '<!-- claude-auto-fix-detail %s -->\n' "$(printf '%s' "$3" | base64 -w0)"
    printf '\n## 対象\n\n- https://github.com/o/r/security/code-scanning/1\n'
}
# Claude の変更の PR を足す: add_pr <番号> <ブランチ> <head の SHA> <本文> [状態 マージした日時 更新した日時 リポジトリ ラベル 作った人]
add_pr() {
    jq --arg n "$1" --arg b "$2" --arg s "$3" --arg body "$4" --arg st "${5:-open}" --arg m "${6:-}" \
        --arg u "${7:-$(ago 7200)}" --arg repo "${8:-o/r}" --arg l "${9-claude-auto-fix}" --arg a "${10:-DogisRiki-bot}" \
        '.pulls += [{number: ($n | tonumber), branch: $b, sha: $s, body: $body, state: $st,
        merged_at: (if $m == "" then null else $m end), updated_at: $u, repo: $repo,
        labels: ($l | split(",") | map(select(length > 0))), author: $a,
        commits: [{sha: $s, parents: [{sha: "p"}], commit: {message: "fix: 直す\n", committer: {date: $u}}}]}]' \
        "$CAP/state.json" | store
}
# PR のコミットを、古い順に置き換える: set_commits <番号> <コミットの JSON の配列>
set_commits() { jq --arg n "$1" --argjson c "$2" '(.pulls[] | select(.number == ($n | tonumber)) | .commits) = $c' "$CAP/state.json" | store; }
# コミットの JSON: commit <SHA> <メッセージ> [親の数]
commit() {
    jq -nc --arg s "$1" --arg m "$2" --argjson np "${3:-1}" --arg d "$(ago 7200)" \
        '{sha: $s, parents: [range($np) | {sha: "p\(.)"}], commit: {message: $m, committer: {date: $d}}}'
}
# head のコミットの検査の結果: checks <SHA> <名前:状態:結論>...(後ろに書いたほど新しく始まった)
checks() {
    local sha="$1" i=0 spec arr='[]'
    shift
    for spec in "$@"; do
        i=$((i + 1))
        arr=$(jq -c --arg n "${spec%%:*}" --arg s "$(cut -d: -f2 <<<"$spec")" --arg c "$(cut -d: -f3 <<<"$spec")" --argjson i "$i" \
            '. + [{id: $i, name: $n, status: $s, conclusion: (if $c == "" then null else $c end),
                started_at: "2026-11-21T09:00:\($i | tostring | if length == 1 then "0" + . else . end)Z"}]' <<<"$arr")
    done
    jq --arg s "$sha" --argjson a "$arr" '.checkruns[$s] = $a' "$CAP/state.json" | store
}
OWN_RUN='{"event": "workflow_dispatch", "head_branch": "claude-auto-fix/run", "repository": {"full_name": "o/r"},
  "head_repository": {"full_name": "o/r"}, "path": ".github/workflows/claude-auto-fix-target.yaml"}'
# 対象ごとの実行を足す: add_run <表示名> <状態> [足す欄の JSON]
add_run() {
    jq --argjson own "$OWN_RUN" --arg t "$1" --arg s "$2" --arg at "$(ago 3600)" --argjson x "${3:-{\}}" \
        '.runs += [$own + {id: 1, display_title: $t, status: $s, conclusion: "success", created_at: $at} + $x]' \
        "$CAP/state.json" | store
}
# Issue を足す: add_issue <番号> <作った人> <題名> <本文> <ラベル(カンマ区切り)> [PR か(true|false)]
add_issue() {
    jq --arg n "$1" --arg a "$2" --arg t "$3" --arg b "$4" --arg l "$5" --arg pr "${6:-false}" \
        '.issues += [{number: ($n | tonumber), author: $a, title: $t, body: $b, state: "open",
        labels: ($l | split(",")), pr: ($pr == "true")}]' "$CAP/state.json" | store
}
run_sweep() {
    bash "$S/claude-auto-fix-sweep.sh" "$@" >"$WORK/out" 2>"$WORK/err"
    RC=$?
}
# 同じ偽の応答で2回呼び、書く操作が増えないことを確かめる
run_twice() {
    run_sweep
    RC1=$RC
    cp "$CAP/ops" "$WORK/ops1"
    cp "$CAP/report.calls" "$WORK/report1"
    run_sweep
    expect_eq "同じ偽の応答で2回呼んでも、PR と Issue の操作が増えない" "$(cat "$CAP/ops")" "$(cat "$WORK/ops1")"
    expect_eq "同じ偽の応答で2回呼んでも、結果を書くスクリプトの呼び出しが増えない" "$(cat "$CAP/report.calls")" "$(cat "$WORK/report1")"
    RC=$RC1
}
ops() { cat "$CAP/ops"; }
dispatched() { jq -r '"\(.kind) \(.key)"' "$CAP/dispatch.jsonl" | sort | paste -sd, -; }
input() { jq -r --arg k "$1" --arg key "$2" --arg f "$3" 'select(.kind == $k and .key == $key) | .[$f] // ""' "$CAP/dispatch.jsonl"; }
# どの場合でも守る決まり
safety() {
    local calls
    calls=$(cat "$CAP/gh.calls")
    expect_not_has "マージしない" "$calls" "merge"
    expect_not_has "警告を却下しない" "$calls" "dismiss"
    expect_not_has "Dependabot へのコマンドを打たない" "$calls" "@dependabot"
    expect_not_has "Dependabot の警告を変えない" "$calls" "-X PATCH repos/o/r/dependabot"
    expect_not_has "CodeQL の警告を変えない" "$calls" "-X PATCH repos/o/r/code-scanning"
    if jq -e 'any(.args[]; . == "record")' "$CAP/report.calls" >/dev/null 2>&1; then
        ng "record の形を呼ばない"
    else
        ok "record の形を呼ばない"
    fi
}

if want args; then
    reset
    run_sweep extra
    expect_eq "引数を付けると2で終わる" "$RC" 2
    GITHUB_REPOSITORY="" run_sweep
    expect_eq "GITHUB_REPOSITORY が無ければ2で終わる" "$RC" 2
    CAF_REQUIRED_CHECKS="$WORK/none.json" run_sweep
    expect_eq "期待一覧が無ければ2で終わる" "$RC" 2
    expect_eq "誤った呼び方では何も操作しない" "$(ops)" ""
fi

if want red_check; then
    reset
    # PR 501: 必須の検査の赤。approval_gated の検査の赤と、dependency-review の赤もある
    add_pr 501 fix/claude-auto-fix-codeql-10 "$SHA_A" "$(pr_body codeql 10)"
    put '.codeql["10"] = "open"'
    checks "$SHA_A" frontend-test:completed:failure backend-test:completed:success escape-hatch:completed:failure \
        dependency-review:completed:failure codex-review:completed:failure
    # PR 502: ラベルの無い PR は Claude の変更の PR に数えない。PR 503: fork から出た同じ名前のブランチも数えない
    add_pr 502 fix/claude-auto-fix-codeql-11 "$SHA_B" "$(pr_body codeql 11)" open "" "" o/r ""
    add_pr 503 fix/claude-auto-fix-codeql-12 "$SHA_C" "$(pr_body codeql 12)" open "" "" someone/r
    checks "$SHA_B" frontend-test:completed:failure
    checks "$SHA_C" frontend-test:completed:failure
    # PR 504: 目印の key とブランチ名が合わない PR は扱わない
    add_pr 504 fix/claude-auto-fix-codeql-13 "$SHA_D" "$(pr_body codeql 99)"
    put '.codeql["99"] = "open"'
    checks "$SHA_D" frontend-test:completed:failure
    # PR 505: 種類が npm の PR は、本文の detail を入力に渡す
    add_pr 505 fix/claude-auto-fix-frontend-vuln-fix-lodash-4-17-21 "$SHA_E" \
        "$(pr_body npm lodash@4.17.21 '{"name":"lodash","version":"4.17.20"}')"
    put '.dalerts = [{state: "open", dependency: {package: {ecosystem: "npm", name: "lodash"}},
        security_vulnerability: {first_patched_version: {identifier: "4.17.21"}}}]'
    checks "$SHA_E" backend-test:completed:timed_out
    run_twice
    expect_eq "終わり方は 0" "$RC" 0
    expect_eq "Claude の変更の PR の必須の検査の赤で、reason=red-check の実行を起動する" "$(dispatched)" "codeql 10,npm lodash@4.17.21"
    expect_eq "入力 reason は red-check で、PR の番号を渡す" "$(input codeql 10 reason) $(input codeql 10 pr)" "red-check 501"
    expect_eq "入力 head に、PR ごとの head の SHA の先頭12文字を渡す" "$(input codeql 10 head) $(input npm lodash@4.17.21 head)" \
        "${SHA_A:0:12} ${SHA_E:0:12}"
    expect_eq "赤の検査の名前を渡す(approval_gated の検査と、期待一覧で動いていない検査を除く)" \
        "$(input codeql 10 checks)" '["dependency-review","frontend-test"]'
    expect_eq "種類が codeql の PR では detail を渡さない" "$(input codeql 10 detail)" ""
    expect_eq "種類が npm の PR では、本文の detail を渡す" "$(input npm lodash@4.17.21 detail)" '{"name":"lodash","version":"4.17.20"}'
    expect_eq "timed_out も赤に数える" "$(input npm lodash@4.17.21 checks)" '["backend-test"]'
    expect_not_has "PR を閉じない" "$(ops)" "close-pr"
    expect_eq "結果を書くスクリプトを呼ばない" "$(cat "$CAP/report.calls")" ""
    safety
fi

if want red_check_ref; then
    reset
    # 赤の検査で起動する実行は、専用のブランチ claude-auto-fix/run で起動する(偽の gh は、ほかの --ref では失敗する)
    add_pr 506 fix/claude-auto-fix-codeql-14 "$SHA_A" "$(pr_body codeql 14)"
    put '.codeql["14"] = "open"'
    checks "$SHA_A" frontend-test:completed:failure
    run_sweep
    refs=$(grep '^workflow run ' "$CAP/gh.calls" | grep -oE -- '--ref [^ ]+' | sort -u | paste -sd, -)
    expect_eq "赤の検査で起動する実行が --ref claude-auto-fix/run で起動される" "$(dispatched) / ${refs}" \
        "codeql 14 / --ref claude-auto-fix/run"
    safety
fi

if want gated_only; then
    reset
    add_pr 510 fix/claude-auto-fix-codeql-20 "$SHA_A" "$(pr_body codeql 20)"
    put '.codeql["20"] = "open"'
    # approval_gated の検査だけが赤で、approval_gated の検査はまだ動いていてもよい
    checks "$SHA_A" frontend-test:completed:success escape-hatch:completed:failure dependency-cooldown:in_progress:
    # PR 511: 前に赤だった検査が、動かし直して緑になった(最新の結論だけを読む)
    add_pr 511 fix/claude-auto-fix-codeql-21 "$SHA_B" "$(pr_body codeql 21)"
    put '.codeql["21"] = "open"'
    checks "$SHA_B" frontend-test:completed:failure frontend-test:completed:success
    run_twice
    expect_eq "終わり方は 0" "$RC" 0
    expect_eq "approval_gated の検査の赤と、緑になった検査では起動されない" "$(dispatched)" ""
    expect_eq "何も操作しない" "$(ops)" ""
    safety
fi

if want pending; then
    reset
    add_pr 520 fix/claude-auto-fix-codeql-30 "$SHA_A" "$(pr_body codeql 30)"
    put '.codeql["30"] = "open"'
    checks "$SHA_A" frontend-test:completed:failure backend-test:in_progress:
    add_pr 521 fix/claude-auto-fix-codeql-31 "$SHA_B" "$(pr_body codeql 31)"
    put '.codeql["31"] = "open"'
    checks "$SHA_B" frontend-test:completed:failure backend-test:queued:
    run_twice
    expect_eq "終わり方は 0" "$RC" 0
    expect_eq "必須の検査がまだ動いているときは何もしない" "$(dispatched)" ""
    expect_eq "何も操作しない" "$(ops)" ""
    safety
fi

if want same_head; then
    reset
    # PR 530: 同じ head のコミットについての対象ごとの実行が、unfixed で終わって PR が開いたまま残った
    add_pr 530 fix/claude-auto-fix-codeql-40 "$SHA_A" "$(pr_body codeql 40)"
    put '.codeql["40"] = "open"'
    checks "$SHA_A" frontend-test:completed:failure
    add_run "claude-auto-fix codeql 40 pr#530@${SHA_A:0:12}" completed
    # PR 531: 前の head のコミットについての実行はあるが、今の head についての実行は無い
    add_pr 531 fix/claude-auto-fix-codeql-41 "$SHA_B" "$(pr_body codeql 41)"
    put '.codeql["41"] = "open"'
    checks "$SHA_B" frontend-test:completed:failure
    add_run "claude-auto-fix codeql 41 pr#531@${SHA_C:0:12}" completed
    # PR 532: 同じ表示名の実行が、fork の PR から動いた実行だけ(数えない)
    add_pr 532 fix/claude-auto-fix-codeql-42 "$SHA_D" "$(pr_body codeql 42)"
    put '.codeql["42"] = "open"'
    checks "$SHA_D" frontend-test:completed:failure
    add_run "claude-auto-fix codeql 42 pr#532@${SHA_D:0:12}" completed \
        '{"event": "pull_request", "head_branch": "x", "head_repository": {"full_name": "someone/r"}}'
    run_twice
    expect_eq "終わり方は 0" "$RC" 0
    expect_eq "同じ head のコミットについての対象ごとの実行があるときは何もしない" "$(dispatched)" "codeql 41,codeql 42"
    if grep -q 'actions/workflows/claude-auto-fix-target.yaml/runs?created=%3E%3D' "$CAP/gh.calls"; then
        ok "head のコミットの日時をもとにした下限で、対象ごとの実行の一覧を読む"
    else
        ng "head のコミットの日時をもとにした下限で、対象ごとの実行の一覧を読む"
    fi
    safety
fi

if want three_strikes; then
    reset
    detail='{"name":"lodash","version":"4.17.20"}'
    put '.dalerts = [{state: "open", dependency: {package: {ecosystem: "npm", name: "lodash"}},
        security_vulnerability: {first_patched_version: {identifier: "4.17.21"}}}]'
    add_pr 540 fix/claude-auto-fix-frontend-vuln-fix-lodash-4-17-21 "$SHA_C" "$(pr_body npm lodash@4.17.21 "$detail")"
    # 最後の2つのコミット(マージのコミットを除く)が、どちらも同じ赤の検査の行を持つ
    set_commits 540 "[$(commit 1111111111111111111111111111111111111111 $'fix: 直す\n\nClaude-Auto-Fix-Key: npm lodash@4.17.21\n'),
        $(commit "$SHA_A" $'fix: 赤を直す\n\nClaude-Auto-Fix-Key: npm lodash@4.17.21\nClaude-Auto-Fix-Check: frontend-test\n'),
        $(commit "$SHA_B" $'Merge branch main\n\nClaude-Auto-Fix-Check: backend-test\n' 2),
        $(commit "$SHA_C" $'fix: 赤を直す\n\nClaude-Auto-Fix-Key: npm lodash@4.17.21\nClaude-Auto-Fix-Check: e2e-smoke\nClaude-Auto-Fix-Check: frontend-test\n')]"
    checks "$SHA_C" frontend-test:completed:failure e2e-smoke:completed:success
    # PR 541: 最後の2つのコミットが持つ行の検査と、今の赤の検査が違う
    add_pr 541 fix/claude-auto-fix-codeql-50 "$SHA_E" "$(pr_body codeql 50)"
    put '.codeql["50"] = "open"'
    set_commits 541 "[$(commit "$SHA_D" $'fix: 赤を直す\n\nClaude-Auto-Fix-Check: backend-test\n'),
        $(commit "$SHA_E" $'fix: 赤を直す\n\nClaude-Auto-Fix-Check: backend-test\n')]"
    checks "$SHA_E" frontend-test:completed:failure
    run_twice
    expect_eq "終わり方は 0" "$RC" 0
    expect_eq "同じ検査の赤が3回続いたら、PR を閉じてブランチを消す" "$(ops)" \
        "close-pr 540
delete-branch fix/claude-auto-fix-frontend-vuln-fix-lodash-4-17-21
dispatch claude-auto-fix codeql 50 pr#541@${SHA_E:0:12}"
    expect_eq "3回目の赤では実行を起動しない" "$(dispatched)" "codeql 50"
    expect_eq "閉じた PR の URL を渡して notify unfixed を呼ぶ" "$(jq -c '.args' "$CAP/report.calls")" \
        "[\"notify\",\"unfixed\",\"npm\",\"lodash@4.17.21\",\"red-check\",\"540\",\"[\\\"frontend-test\\\"]\",\"$(jq -c . <<<"$detail" | sed 's/"/\\"/g')\",\"\",\"https://github.com/o/r/pull/540\"]"
    expect_eq "notify を呼ぶときに EDIT_OUTCOME を渡さない" "$(jq -r '.edit_outcome' "$CAP/report.calls")" "unset"
    safety
fi

if want gone_pr; then
    reset
    add_pr 550 fix/claude-auto-fix-codeql-60 "$SHA_A" "$(pr_body codeql 60)"
    put '.codeql["60"] = "fixed"'
    checks "$SHA_A" frontend-test:completed:failure
    add_pr 551 fix/claude-auto-fix-codeql-61 "$SHA_B" "$(pr_body codeql 61)"
    put '.codeql["61"] = "open"'
    checks "$SHA_B" frontend-test:completed:success
    # 種類が go-stdlib の PR は、main の go.mod の go の版で消えたかを見る
    add_pr 552 fix/claude-auto-fix-backend-vuln-fix-go-stdlib-1-25-0 "$SHA_C" "$(pr_body go-stdlib 1.25.0)"
    checks "$SHA_C" frontend-test:completed:success
    run_twice
    expect_eq "終わり方は 0" "$RC" 0
    expect_eq "対象が消えた PR に消えたことを書いたコメントを付けて閉じ、ブランチを消す" "$(ops)" \
        "comment 550 <!-- claude-auto-fix-notice kind=gone -->
close-pr 550
delete-branch fix/claude-auto-fix-codeql-60
comment 552 <!-- claude-auto-fix-notice kind=gone -->
close-pr 552
delete-branch fix/claude-auto-fix-backend-vuln-fix-go-stdlib-1-25-0"
    expect_eq "対象が消えた PR では、赤の検査でも実行を起動しない" "$(dispatched)" ""
    body=$(jq -r '.comments["550"][0].body' "$CAP/state.json")
    expect_has "コメントに、対象が消えたことを書く" "$body" "消えています"
    expect_not_has "コメントで所有者に呼びかけない" "$body" "@o "
    safety
fi

if want merged_container; then
    reset
    key=CVE-2026-1111
    add_pr 560 fix/claude-auto-fix-container-cve-2026-1111 "$SHA_A" "$(pr_body container "$key")" closed "$(ago 86400)" "$(ago 86400)"
    # 7日より前にマージした PR、マージせずに閉じた PR、fork の PR、種類が container でない PR は扱わない
    add_pr 561 fix/claude-auto-fix-container-cve-2026-2222 "$SHA_B" "$(pr_body container CVE-2026-2222)" closed "$(ago 864000)" "$(ago 864000)"
    add_pr 562 fix/claude-auto-fix-container-cve-2026-3333 "$SHA_C" "$(pr_body container CVE-2026-3333)" closed "" "$(ago 3600)"
    add_pr 563 fix/claude-auto-fix-container-cve-2026-4444 "$SHA_D" "$(pr_body container CVE-2026-4444)" closed "$(ago 3600)" "$(ago 3600)" someone/r
    add_pr 564 fix/claude-auto-fix-codeql-70 "$SHA_E" "$(pr_body codeql 70)" closed "$(ago 3600)" "$(ago 3600)"
    add_issue 80 "$BOT" "コンテナ脆弱性: $key" "本文" container-vuln
    add_issue 81 someone "コンテナ脆弱性: $key" "本文" container-vuln
    for k in CVE-2026-2222 CVE-2026-3333 CVE-2026-4444; do add_issue "8${k: -1}" "$BOT" "コンテナ脆弱性: $k" "本文" container-vuln; done
    run_twice
    expect_eq "終わり方は 0" "$RC" 0
    expect_eq "マージされたコンテナの PR のコメントが、ラベル container-vuln の Issue に1回だけ付く" "$(ops)" \
        "comment 80 <!-- claude-auto-fix-notice kind=merged pr=560 -->"
    body=$(jq -r '.comments["80"][0].body' "$CAP/state.json")
    expect_has "コメントに、本番で消えるのはリリースのあとであることを書く" "$body" "リリース"
    expect_has "コメントで所有者に呼びかける" "$body" "@o "
    if grep -q 'pulls?state=closed&sort=updated&direction=desc&per_page=100&page=1' "$CAP/gh.calls"; then
        ok "閉じた PR を、更新の新しい順に読む"
    else
        ng "閉じた PR を、更新の新しい順に読む"
    fi
    safety
fi

if want notice_gone; then
    reset
    put '.codeql["90"] = "fixed" | .codeql["91"] = "dismissed" | .codeql["92"] = "open" | .codeql["93"] = "fixed"'
    add_issue 100 "$BOT" "Claude が直せなかった CodeQL の警告 #90" '本文 <!-- claude-auto-fix-issue key=codeql:90 kind=unfixed run=1 -->' claude-auto-fix
    add_issue 101 "$BOT" "Claude が3日続けて動けなかった CodeQL の警告 #91" '本文 <!-- claude-auto-fix-issue key=codeql:91 kind=unavailable run=1 -->' claude-auto-fix
    add_issue 102 "$BOT" "Claude が直せなかった CodeQL の警告 #92" '本文 <!-- claude-auto-fix-issue key=codeql:92 kind=unfixed run=1 -->' claude-auto-fix
    # 利用者が起票した、同じ目印の Issue は扱わない
    add_issue 103 someone "偽の知らせ" '本文 <!-- claude-auto-fix-issue key=codeql:93 kind=unfixed run=1 -->' claude-auto-fix
    # 鍵の Issue と、ラベル claude-auto-fix の PR は扱わない
    add_issue 104 "$BOT" "Claude を動かす鍵を取り替えてください" '本文 <!-- claude-auto-fix-key -->' claude-auto-fix
    add_issue 105 "$BOT" "PR" '本文 <!-- claude-auto-fix-issue key=codeql:93 kind=unfixed run=1 -->' claude-auto-fix true
    # key に : を含む種類 maven の Issue。Dependabot の警告が無いので消えている
    add_issue 106 "$BOT" "Claude が直せなかった maven の脆弱性" '本文 <!-- claude-auto-fix-issue key=maven:com.example:lib@1.2.3 kind=unfixed run=1 -->' claude-auto-fix
    # 本文は unfixed でも、github-actions[bot] のあとのコメントで状態が変わった。利用者のコメントの目印は読まない
    add_issue 107 "$BOT" "Claude が直せなかった CodeQL の警告 #93" '本文 <!-- claude-auto-fix-issue key=codeql:93 kind=unavailable run=1 -->' claude-auto-fix
    put '.comments["107"] = [{user: {login: "someone"}, body: "<!-- claude-auto-fix-issue key=codeql:92 kind=unfixed run=9 -->", created_at: "2026-11-02T00:00:00Z"}]'
    run_twice
    expect_eq "終わり方は 0" "$RC" 0
    expect_eq "対象が消えた知らせの Issue に、消えたことを書いたコメントを付けて閉じる(状態が unavailable の Issue も)" "$(ops)" \
        "comment 100 <!-- claude-auto-fix-notice kind=gone -->
close-issue 100
comment 101 <!-- claude-auto-fix-notice kind=gone -->
close-issue 101
comment 106 <!-- claude-auto-fix-notice kind=gone -->
close-issue 106
comment 107 <!-- claude-auto-fix-notice kind=gone -->
close-issue 107"
    expect_not_has "対象が残る知らせの Issue を閉じない" "$(ops)" "close-issue 102"
    body=$(jq -r '.comments["100"][0].body' "$CAP/state.json")
    expect_has "コメントに、対象が消えたことを書く" "$body" "消えています"
    expect_not_has "コメントに、CodeQL の警告の中身を書かない" "$body" "codeql:90"
    safety
fi

if want fails; then
    reset
    add_pr 570 fix/claude-auto-fix-codeql-71 "$SHA_A" "$(pr_body codeql 71)"
    put '.codeql["71"] = "open"'
    checks "$SHA_A" frontend-test:completed:failure
    add_pr 571 fix/claude-auto-fix-codeql-72 "$SHA_B" "$(pr_body codeql 72)"
    put '.codeql["72"] = "open"'
    checks "$SHA_B" frontend-test:completed:failure
    add_issue 110 "$BOT" "知らせ" '本文 <!-- claude-auto-fix-issue key=codeql:73 kind=unfixed run=1 -->' claude-auto-fix
    put '.codeql["73"] = "fixed"'
    # PR 570 の検査の結果を読めない
    FAIL_EP="commits/$SHA_A/check-runs" run_sweep
    expect_eq "1件の PR の操作に失敗したら、0以外で終わる" "$RC" 1
    expect_eq "1件の PR の操作に失敗しても、残りの PR と Issue を続ける" "$(dispatched)" "codeql 72"
    expect_has "残りの Issue も扱う" "$(ops)" "close-issue 110"
    expect_has "失敗の理由を書く" "$(cat "$WORK/err")" "::error::"
    # 3回目の赤の知らせを書けない
    reset
    add_pr 572 fix/claude-auto-fix-codeql-74 "$SHA_C" "$(pr_body codeql 74)"
    put '.codeql["74"] = "open"'
    set_commits 572 "[$(commit "$SHA_B" $'fix\n\nClaude-Auto-Fix-Check: frontend-test\n'), $(commit "$SHA_C" $'fix\n\nClaude-Auto-Fix-Check: frontend-test\n')]"
    checks "$SHA_C" frontend-test:completed:failure
    touch "$CAP/report-fail"
    run_sweep
    expect_eq "知らせを書けなければ、0以外で終わる" "$RC" 1
    # PR の一覧を読めない
    reset
    add_issue 111 "$BOT" "知らせ" '本文 <!-- claude-auto-fix-issue key=codeql:75 kind=unfixed run=1 -->' claude-auto-fix
    put '.codeql["75"] = "fixed"'
    FAIL_EP="pulls?state=open" run_sweep
    expect_eq "PR の一覧を読めなければ、0以外で終わる" "$RC" 1
    expect_has "PR の一覧を読めなくても、知らせの Issue を扱う" "$(ops)" "close-issue 111"
    # 検査の結果の形が違う
    reset
    add_pr 573 fix/claude-auto-fix-codeql-76 "$SHA_D" "$(pr_body codeql 76)"
    jq --arg s "$SHA_D" '.codeql["76"] = "open" | .checkruns[$s] = "x"' "$CAP/state.json" | store
    run_sweep
    expect_eq "検査の結果の形が違えば、0以外で終わる" "$RC" 1
    expect_eq "検査の結果の形が違えば、起動しない" "$(dispatched)" ""
    safety
fi

if [ -n "$CASE" ] && [ "$RAN" -eq 0 ]; then
    echo "知らない場合の名前です: $CASE" >&2
    exit 1
fi
if [ "$FAILED" -ne 0 ]; then
    echo "test-claude-auto-fix-sweep: 失敗した確かめがあります" >&2
    exit 1
fi
echo "test-claude-auto-fix-sweep: すべて通りました(${RAN} の場合)"
