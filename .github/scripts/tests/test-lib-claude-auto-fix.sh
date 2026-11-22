#!/usr/bin/env bash
# =====================================================================
# lib-claude-auto-fix.sh の自動テスト
#
# ネットワークも GitHub の権限も使わない。関数に JSON を渡し、出力を決まった値と比べる。
#
# vuln-fix の種類のブランチ名は、今の frontend-vuln-fix.sh と backend-vuln-fix.sh の
# ブランチ名の作り方をそのスクリプトから読み出して同じ組で動かし、`chore/` を除いたものと比べる。
# 2つのスクリプトのブランチ名の作り方が変わると、このテストが落ちる。
#
# 環境変数 KP_TEST_CASE に場合の名前を入れると、その場合だけを流す(例: KP_TEST_CASE=fixable_fake)。
# =====================================================================
set -uo pipefail

DIR="$(cd "$(dirname "$0")/.." && pwd)"
LIB="$DIR/lib-claude-auto-fix.sh"
CASE="${KP_TEST_CASE:-}"
WORK=$(mktemp -d) || exit 1
[ -n "$WORK" ] && [ -d "$WORK" ] || exit 1
trap 'rm -rf "$WORK"' EXIT
FAILED=0
CASES_RUN=0

# shellcheck source=.github/scripts/lib-claude-auto-fix.sh
. "$LIB" || { echo "NG: $LIB を読み込めませんでした"; exit 1; }

selected() {
    if [ -z "$CASE" ] || [ "$CASE" = "$1" ]; then
        CASES_RUN=$((CASES_RUN + 1))
        return 0
    fi
    return 1
}
ok() { echo "OK: $1"; }
ng() {
    echo "NG: $1"
    FAILED=1
}
# 使い方: expect_eq <説明> <期待する値> <実際の値>
expect_eq() {
    if [ "$2" = "$3" ]; then ok "$1"; else ng "$1(期待: $2 / 実際: $3)"; fi
}
# 使い方: expect_rc1 <説明> <コマンド...>  (終了コードが1で、標準出力が空であることを確かめる)
expect_rc1() {
    local desc="$1" out rc
    shift
    out=$("$@" 2>"$WORK/err")
    rc=$?
    if [ "$rc" -eq 1 ] && [ -z "$out" ] && [ -s "$WORK/err" ]; then ok "$desc"; else ng "$desc(終了コード $rc、出力 '$out')"; fi
}

if selected keys_and_names; then
    # データの形の節の「対象の種類と識別子とブランチ名」の表の7種類
    while IFS='|' read -r kind group want_key want_branch; do
        key=$(target_key "$kind" "$group")
        expect_eq "${kind} の key" "$want_key" "$key"
        names=$(target_names "$kind" "$key")
        expect_eq "${kind} のブランチ名" "$want_branch" "$(jq -r .branch <<<"$names")"
        expect_eq "${kind} の表示名" "claude-auto-fix ${kind} ${want_key}" "$(jq -r .run_name <<<"$names")"
    done <<'EOF'
npm|{"name":"@babel/core","version":"7.26.10","ranges":[],"urgent":false,"alerts":[]}|@babel/core@7.26.10|fix/claude-auto-fix-frontend-vuln-fix-babel-core-7-26-10
maven|{"name":"org.apache.commons:commons-lang3","version":"3.18.0","alerts":[]}|org.apache.commons:commons-lang3@3.18.0|fix/claude-auto-fix-backend-vuln-fix-org-apache-commons-commons-lang3-3-18-0
go-stdlib|{"version":"1.25.4","osv":["GO-2025-4010"]}|1.25.4|fix/claude-auto-fix-backend-vuln-fix-go-stdlib-1-25-4
go-module|{"module":"golang.org/x/net","version":"0.47.0","osv":["GO-2025-3595"]}|golang.org/x/net@0.47.0|fix/claude-auto-fix-backend-vuln-fix-go-golang-org-x-net-0-47-0
codeql|{"number":42}|42|fix/claude-auto-fix-codeql-42
container|{"id":"CVE-2025-12345"}|CVE-2025-12345|fix/claude-auto-fix-container-cve-2025-12345
dependabot|{"number":877}|877|fix/claude-auto-fix-dependabot-pr-877
EOF
    names=$(target_names dependabot 877 912 0123456789abcdef0123456789abcdef01234567)
    expect_eq "red-check の表示名は PR の番号と head の SHA の先頭12文字を足す" \
        "claude-auto-fix dependabot 877 pr#912@0123456789ab" "$(jq -r .run_name <<<"$names")"
fi

if selected vuln_fix_branch_compat; then
    # 今の2つのスクリプトのブランチ名の作り方を読み出す
    fe_line=$(grep -m1 'branch="chore/frontend-vuln-fix-' "$DIR/frontend-vuln-fix.sh" | sed -E 's/^[[:space:]]+//')
    be_slug=$(grep -m1 '^slug() {' "$DIR/backend-vuln-fix.sh")
    be_lib=$(grep -m1 'branch="chore/backend-vuln-fix-[^g]' "$DIR/backend-vuln-fix.sh" | sed -E 's/^[[:space:]]+//; s/; title=.*$//')
    be_std=$(grep -m1 'branch="chore/backend-vuln-fix-go-stdlib-' "$DIR/backend-vuln-fix.sh" | sed -E 's/^.*(branch="chore\/backend-vuln-fix-go-stdlib-)/\1/')
    be_mod=$(grep -m1 'branch="chore/backend-vuln-fix-go-[^s]' "$DIR/backend-vuln-fix.sh" | sed -E 's/^[[:space:]]+//; s/; title=.*$//')
    if [ -z "$fe_line" ] || [ -z "$be_slug" ] || [ -z "$be_lib" ] || [ -z "$be_std" ] || [ -z "$be_mod" ]; then
        ng "今の vuln-fix のブランチ名の作り方を読み出せませんでした"
    else
        eval "$be_slug"
        # 大文字、点、アンダースコア、スコープ付きの名前、プレリリースの版を混ぜた組
        while IFS='|' read -r kind name ver; do
            branch=""
            case "$kind" in
            npm) eval "$fe_line" ;;
            maven) eval "$be_lib" ;;
            go-stdlib) eval "$be_std" ;;
            go-module) export mod="$name"; eval "$be_mod" ;;
            esac
            case "$kind" in
            npm | maven) group=$(jq -nc --arg n "$name" --arg v "$ver" '{name: $n, version: $v}') ;;
            go-stdlib) group=$(jq -nc --arg v "$ver" '{version: $v}') ;;
            go-module) group=$(jq -nc --arg n "$name" --arg v "$ver" '{module: $n, version: $v}') ;;
            esac
            got=$(target_names "$kind" "$(target_key "$kind" "$group")" | jq -r .branch)
            expect_eq "${kind} ${name} ${ver} のブランチ名が今の vuln-fix のブランチ名から chore/ を除いたものと同じ" \
                "fix/claude-auto-fix-${branch#chore/}" "$got"
        done <<'EOF'
npm|@types/node_utils|22.10.0-beta.1
npm|lodash.merge|4.6.2
maven|com.fasterxml.jackson.core:jackson-databind|2.18.2
maven|org.Example_Group:My-Artifact|1.0.0.RELEASE
go-stdlib||1.24.11
go-module|github.com/Go-Chi/chi/v5|5.2.2
EOF
    fi
fi

if selected key_errors; then
    expect_rc1 "知らない種類では失敗する" target_key pypi '{"name":"x","version":"1"}'
    expect_rc1 "npm の組に版が無ければ失敗する" target_key npm '{"name":"lodash"}'
    expect_rc1 "codeql の番号が数でなければ失敗する" target_key codeql '{"number":"1;rm"}'
    expect_rc1 "組が JSON でなければ失敗する" target_key npm 'not json'
    expect_rc1 "知らない種類ではブランチ名を作らない" target_names pypi x@1
    expect_rc1 "dependabot の key が数でなければブランチ名を作らない" target_names dependabot 'abc'
    expect_rc1 "key が空ならブランチ名を作らない" target_names npm ''
    expect_rc1 "key に空白があればブランチ名を作らない" target_names container 'CVE-1 x'
    expect_rc1 "head の SHA が40桁の16進数でなければ表示名を作らない" target_names dependabot 877 912 abc
fi

if selected marker_write; then
    expect_eq "知らせの Issue の目印を書く" \
        "<!-- claude-auto-fix-issue key=npm:lodash@4.17.21 kind=unfixed -->" \
        "$(marker_line issue key=npm:lodash@4.17.21 kind=unfixed)"
    expect_eq "Claude の変更の PR の目印を書く" \
        "<!-- claude-auto-fix-pr kind=maven key=org.apache.commons:commons-lang3@3.18.0 -->" \
        "$(marker_line pr kind=maven key=org.apache.commons:commons-lang3@3.18.0)"
    expect_rc1 "値に空白があれば目印を書かない" marker_line issue "key=npm:a b" kind=unfixed
    expect_rc1 "値に > があれば目印を書かない" marker_line issue "key=npm:a-->x" kind=unfixed
    expect_rc1 "欄の形が違えば目印を書かない" marker_line issue keyonly
    expect_rc1 "目印の名前の形が違えば目印を書かない" marker_line 'issue x'
fi

# 知らせの Issue の本文とコメント(REST の形。古い順に並んでいるとは限らない)
cat >"$WORK/items.json" <<'EOF'
[
  {"user": {"login": "github-actions[bot]"}, "created_at": "2026-11-10T00:00:00Z",
   "body": "直せませんでした。\n<!-- claude-auto-fix-issue key=npm:lodash@4.17.21 kind=unavailable -->"},
  {"user": {"login": "github-actions[bot]"}, "created_at": "2026-11-12T00:00:00Z",
   "body": "<!-- claude-auto-fix-issue key=npm:lodash@4.17.21 kind=unfixed -->"},
  {"user": {"login": "github-actions[bot]"}, "created_at": "2026-11-11T00:00:00Z",
   "body": "<!-- claude-auto-fix-issue key=npm:lodash@4.17.21 kind=unavailable -->"},
  {"user": {"login": "github-actions[bot]"}, "created_at": "2026-11-13T00:00:00Z",
   "body": "別の対象の目印 <!-- claude-auto-fix-issue key=npm:other@1.0.0 kind=unavailable -->"},
  {"user": {"login": "someone"}, "created_at": "2026-11-14T00:00:00Z",
   "body": "<!-- claude-auto-fix-issue key=npm:lodash@4.17.21 kind=unavailable -->"}
]
EOF

if selected issue_state_latest; then
    expect_eq "github-actions[bot] が書いた最も新しい目印から Issue の状態を読む" \
        unfixed "$(issue_state npm lodash@4.17.21 <"$WORK/items.json")"
    expect_eq "別の対象の目印は読まない" unavailable "$(issue_state npm other@1.0.0 <"$WORK/items.json")"
    expect_eq "目印が無ければ空を出す" "" "$(issue_state npm none@1.0.0 <"$WORK/items.json")"
    jq '.[0].body += "\n<!-- claude-auto-fix-issue key=npm:lodash@4.17.21 kind=unfixed -->" | .[0].created_at = "2026-11-20T00:00:00Z"' \
        "$WORK/items.json" >"$WORK/items2.json"
    jq '.[0].body = "<!-- claude-auto-fix-issue key=npm:lodash@4.17.21 kind=unfixed -->\n<!-- claude-auto-fix-issue key=npm:lodash@4.17.21 kind=unavailable -->" | .[0].created_at = "2026-11-20T00:00:00Z"' \
        "$WORK/items.json" >"$WORK/items3.json"
    expect_eq "1つの本文に目印が2つあれば後ろの目印を読む" unavailable "$(issue_state npm lodash@4.17.21 <"$WORK/items3.json")"
    expect_eq "最も新しい目印が本文にあっても読む" unfixed "$(issue_state npm lodash@4.17.21 <"$WORK/items2.json")"
    expect_eq "目印の欄を JSON で読む" '{"key":"npm:lodash@4.17.21","kind":"unfixed"}' \
        "$(latest_marker issue key=npm:lodash@4.17.21 <"$WORK/items.json")"
fi

if selected issue_state_other_user; then
    # ほかの利用者だけが目印を書いた
    jq '[.[] | select(.user.login != "github-actions[bot]")]' "$WORK/items.json" >"$WORK/user-only.json"
    expect_eq "ほかの利用者が書いた目印を読まない" "" "$(issue_state npm lodash@4.17.21 <"$WORK/user-only.json")"
    # ほかの利用者が github-actions という名前の利用者で書いた
    jq '[.[] | .user.login = "github-actions"]' "$WORK/items.json" >"$WORK/lookalike.json"
    expect_eq "github-actions[bot] でない名前の目印を読まない" "" "$(issue_state npm lodash@4.17.21 <"$WORK/lookalike.json")"
    expect_rc1 "本文とコメントの一覧が配列でなければ失敗する" issue_state npm lodash@4.17.21 <<<'{"body": "x"}'
fi

RED_JSON='["dependency-review","escape-hatch","frontend-test","dependency-gate","pre-merge-check","dependency-cooldown","gitleaks"]'

if selected fixable_real; then
    expect_eq "dependency-review と approval_gated の4つの検査を除き、ほかの赤の検査を残す" \
        '["frontend-test","gitleaks"]' "$(fixable_red_checks "$DIR/../audit/required-checks.json" "$RED_JSON")"
    expect_eq "期待一覧の approval_gated の検査は escape-hatch と dependency-gate と pre-merge-check と dependency-cooldown の4つ" \
        '["dependency-cooldown","dependency-gate","escape-hatch","pre-merge-check"]' \
        "$(jq -c '[.checks[] | select(.approval_gated == true) | .context] | sort' "$DIR/../audit/required-checks.json")"
    expect_eq "除く検査だけなら空の配列を出す" '[]' \
        "$(fixable_red_checks "$DIR/../audit/required-checks.json" '["dependency-review","escape-hatch"]')"
fi

if selected fixable_fake; then
    # 期待一覧に approval_gated の検査を1つ足す。関数を書き換えずに、足した検査も除くことを確かめる
    jq '.checks += [{"context": "extra-gated-check", "mode": "always", "state": "active", "approval_gated": true}]' \
        "$DIR/../audit/required-checks.json" >"$WORK/fake-required.json"
    RED_EXTRA=$(jq -c '. + ["extra-gated-check"]' <<<"$RED_JSON")
    expect_eq "本物の期待一覧には extra-gated-check が無いので、赤の検査に残る" \
        '["frontend-test","extra-gated-check","gitleaks"]' \
        "$(fixable_red_checks "$DIR/../audit/required-checks.json" "$(jq -c '.[0:3] + ["extra-gated-check"] + .[3:]' <<<"$RED_JSON")")"
    expect_eq "偽の期待一覧で approval_gated の検査を1つ足すとその検査も除く" \
        '["frontend-test","gitleaks"]' "$(fixable_red_checks "$WORK/fake-required.json" "$RED_EXTRA")"
    expect_rc1 "期待一覧が無ければ失敗する" fixable_red_checks "$WORK/missing.json" "$RED_JSON"
    printf '{"checks": "x"}\n' >"$WORK/bad-required.json"
    expect_rc1 "期待一覧の形が違えば失敗する" fixable_red_checks "$WORK/bad-required.json" "$RED_JSON"
    expect_rc1 "赤の検査が文字列の配列でなければ失敗する" fixable_red_checks "$DIR/../audit/required-checks.json" '[1]'
fi

# --- gh のスタブ(claude_prs・claude_pr・recent_outcomes・target_gone の場合で使う) -----
# api: 引数のうち repos/ で始まるパスを、英数字以外を _ にした名前で $STUB_FX から探して返す。
#      問い合わせの文字列(? より後ろ)つきの名前が無ければ、外した名前を探す。
#      どちらも無ければ、想定していない呼び出しとして失敗する(API の失敗の代わりにもなる)。
# run download <ID> ... -D <フォルダ>: $STUB_FX/outcome-<ID>.json を <フォルダ>/outcome.json に写す。
# 呼び出しは1行1件で $STUB_CALLS に記録する。
mkdir -p "$WORK/bin"
cat >"$WORK/bin/gh" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"${STUB_CALLS:?}"
if [ "${1:-}" = run ] && [ "${2:-}" = download ]; then
    id="$3" dir=""
    while [ "$#" -gt 0 ]; do
        if [ "$1" = -D ]; then dir="$2"; shift; fi
        shift
    done
    [ -n "$dir" ] && [ -f "${STUB_FX:?}/outcome-${id}.json" ] || { echo "stub: 成果物がありません: ${id}" >&2; exit 1; }
    mkdir -p "$dir" && cp "$STUB_FX/outcome-${id}.json" "$dir/outcome.json"
    exit $?
fi
[ "${1:-}" = api ] || { echo "stub: unexpected call: $*" >&2; exit 1; }
path=""
for a in "$@"; do
    case "$a" in repos/*) path="$a" ;; esac
done
[ -n "$path" ] || { echo "stub: unexpected call: $*" >&2; exit 1; }
for p in "$path" "${path%%\?*}"; do
    f="${STUB_FX:?}/$(printf '%s' "$p" | tr -c 'A-Za-z0-9' '_').json"
    if [ -f "$f" ]; then cat "$f"; exit 0; fi
done
echo "stub: unexpected call: $*" >&2
exit 1
STUB
chmod +x "$WORK/bin/gh"
export PATH="$WORK/bin:$PATH" STUB_FX="$WORK/fx" STUB_CALLS="$WORK/calls.log" GITHUB_REPOSITORY="owner/repo"

reset_fx() {
    rm -rf "$WORK/fx"
    mkdir -p "$WORK/fx"
    : >"$STUB_CALLS"
}
# 使い方: fx <repos/ で始まるパス> <応答の本文>
fx() { printf '%s\n' "$2" >"$WORK/fx/$(printf '%s' "$1" | tr -c 'A-Za-z0-9' '_').json"; }
# 使い方: pull <番号> <ブランチ名> <head のリポジトリ(空なら消えた fork)> <ラベルの名前の JSON の配列>
# REST の PR の一覧の1件の形(使う項目だけ)を出す
pull() {
    jq -cn --argjson n "$1" --arg ref "$2" --arg repo "$3" --argjson labels "$4" '
        {number: $n, html_url: "https://github.com/owner/repo/pull/\($n)", body: "本文 \($n)",
         head: {ref: $ref, sha: "0123456789abcdef0123456789abcdef0123456\($n % 10)",
                repo: (if $repo == "" then null else {full_name: $repo} end)},
         labels: ($labels | map({name: .}))}'
}
# 使い方: expect_out <説明> <期待する標準出力> <コマンド...>  (終了コードが0であることも確かめる)
expect_out() {
    local desc="$1" want="$2" out rc
    shift 2
    out=$("$@" 2>"$WORK/err")
    rc=$?
    if [ "$rc" -eq 0 ] && [ "$out" = "$want" ]; then ok "$desc"; else ng "$desc(期待: '$want' / 実際: '$out'、終了コード $rc、$(head -c 300 "$WORK/err"))"; fi
}
PULLS_PATH="repos/owner/repo/pulls?state=open&per_page=100"
# 使い方: prs_field <jq の式>  (claude_prs の出力から、式の値を出す)
prs_field() { claude_prs | jq -c "$1"; }
# 使い方: pr_number <種類> <key>  (claude_pr の出力から PR の番号を出す)
pr_number() { claude_pr "$1" "$2" | jq -r .number; }

if selected claude_pr_match; then
    # ブランチ名とラベルと同じリポジトリのブランチがそろった PR だけを Claude の変更の PR とみなす
    reset_fx
    fx "$PULLS_PATH" "[[$(pull 1 fix/claude-auto-fix-codeql-42 owner/repo '["claude-auto-fix"]'),$(pull 2 feature/other owner/repo '["claude-auto-fix"]')],[$(pull 3 fix/claude-auto-fix-dependabot-pr-7 owner/repo '["dependencies","claude-auto-fix"]')]]"
    expect_out "ブランチ名とラベルと同じリポジトリのブランチがそろった PR だけを一覧に出す(2ページ目も読む)" '[1,3]' \
        prs_field 'map(.number)'
    expect_out "一覧の欄は番号とブランチ名と head の SHA と URL と本文" \
        '{"number":1,"branch":"fix/claude-auto-fix-codeql-42","head_sha":"0123456789abcdef0123456789abcdef01234561","url":"https://github.com/owner/repo/pull/1","body":"本文 1"}' \
        prs_field '.[0]'
    expect_out "key のブランチ名の PR を Claude の変更の PR として出す" '1' \
        pr_number codeql 42
    expect_out "dependabot の key でも探せる" '3' \
        pr_number dependabot 7
    expect_out "同じ key の PR が無ければ何も出さずに0で終わる" '' claude_pr codeql 43
    if grep -qF "api --paginate --slurp $PULLS_PATH" "$STUB_CALLS"; then ok "開いている PR を全ページ読む"; else ng "開いている PR を全ページ読む($(cat "$STUB_CALLS"))"; fi
fi

if selected claude_pr_reject; then
    # fork のブランチの PR とラベルの無い PR を Claude の変更の PR とみなさない
    reset_fx
    fx "$PULLS_PATH" "[[$(pull 4 fix/claude-auto-fix-codeql-42 someone/repo '["claude-auto-fix"]'),$(pull 5 fix/claude-auto-fix-codeql-42 '' '["claude-auto-fix"]'),$(pull 6 fix/claude-auto-fix-codeql-42 owner/repo '[]'),$(pull 7 fix/claude-auto-fix-codeql-42 owner/repo '["other"]')]]"
    expect_out "fork のブランチの PR とラベルの無い PR は一覧に入らない" '[]' claude_prs
    expect_out "同じブランチ名でも fork とラベルの無い PR は Claude の変更の PR とみなさない" '' claude_pr codeql 42
    reset_fx
    expect_rc1 "PR の一覧を読めなければ失敗する" claude_prs
    expect_rc1 "PR の一覧を読めなければ探すのも失敗する" claude_pr codeql 42
    fx "$PULLS_PATH" '{"message": "Bad credentials"}'
    expect_rc1 "PR の一覧の応答の形が違えば失敗する" claude_prs
    reset_fx
    fx "$PULLS_PATH" '[[]]'
    expect_rc1 "知らない種類では探さずに失敗する" claude_pr unknown 42
    (
        unset GITHUB_REPOSITORY
        expect_rc1 "GITHUB_REPOSITORY が無ければ失敗する" claude_prs
        exit "$FAILED"
    ) || FAILED=1
fi

if selected target_gone_each; then
    # 7種類ごとに、消えたときに消えたと答え、残っているときに残っていると答える
    reset_fx
    alert() {
        jq -cn --arg eco "$1" --arg name "$2" --arg fix "$3" '
            {state: "open", dependency: {package: {ecosystem: $eco, name: $name}},
             security_vulnerability: {first_patched_version: (if $fix == "" then null else {identifier: $fix} end)}}'
    }
    fx "repos/owner/repo/dependabot/alerts?state=open&ecosystem=npm&per_page=100" \
        "[[$(alert npm @scope/pkg 1.0.0),$(alert npm lodash 4.17.20)],[$(alert npm nofix '')]]"
    fx "repos/owner/repo/dependabot/alerts?state=open&ecosystem=maven&per_page=100" \
        "[[$(alert maven org.example:lib 2.0.1)]]"
    expect_out "npm: 組の警告が開いていれば残っている" false target_gone npm @scope/pkg@1.0.0
    expect_out "npm: 同じ部品でも修正版が違う警告しか無ければ消えた" true target_gone npm lodash@4.17.21
    expect_out "maven: 組の警告が開いていれば残っている" false target_gone maven org.example:lib@2.0.1
    expect_out "maven: 組の警告が1つも開いていなければ消えた" true target_gone maven org.example:lib@2.0.2

    fx "repos/owner/repo/contents/backend/go.mod?ref=main" "$(printf '%s\n' 'module example.com/app' '' 'go 1.27.0' '' 'toolchain go1.27.4' '' 'require github.com/single/mod v1.2.0' '' 'require (' '	golang.org/x/net v0.35.0 // indirect' '	example.com/pre v1.3.0-rc.1' ')')"
    expect_out "go-stdlib: toolchain が修正版と同じなら消えた" true target_gone go-stdlib 1.27.4
    expect_out "go-stdlib: toolchain が修正版より新しければ消えた" true target_gone go-stdlib 1.27.3
    expect_out "go-stdlib: toolchain が修正版より古ければ残っている(版は数で比べる)" false target_gone go-stdlib 1.27.10
    expect_out "go-module: require の塊の部品の版が修正版と同じなら消えた" true target_gone go-module golang.org/x/net@v0.35.0
    expect_out "go-module: require の塊の部品の版が修正版より古ければ残っている" false target_gone go-module golang.org/x/net@v0.36.0
    expect_out "go-module: 1行の require の部品の版が修正版以上なら消えた" true target_gone go-module github.com/single/mod@v1.1.9
    expect_out "go-module: 1行の require の部品の版が修正版より古ければ残っている(版は数で比べる)" false target_gone go-module github.com/single/mod@v1.10.0
    expect_out "go-module: プレリリースの版は同じ番号の正式な版より古い" false target_gone go-module example.com/pre@v1.3.0
    expect_out "go-module: go.mod に無い部品は消えた" true target_gone go-module example.com/removed@v1.0.0
    if grep -qF 'Accept: application/vnd.github.raw+json' "$STUB_CALLS"; then ok "go.mod は main の中身をそのまま読む"; else ng "go.mod は main の中身をそのまま読む($(cat "$STUB_CALLS"))"; fi

    fx "repos/owner/repo/code-scanning/alerts/7" '{"number": 7, "state": "open"}'
    fx "repos/owner/repo/code-scanning/alerts/8" '{"number": 8, "state": "fixed"}'
    fx "repos/owner/repo/code-scanning/alerts/9" '{"number": 9, "state": "dismissed"}'
    expect_out "codeql: 警告が open なら残っている" false target_gone codeql 7
    expect_out "codeql: 警告が fixed なら消えた" true target_gone codeql 8
    expect_out "codeql: 警告が dismissed なら消えた" true target_gone codeql 9

    fx "repos/owner/repo/issues?labels=container-vuln&state=open&per_page=100" \
        '[[{"number": 1, "title": "コンテナ脆弱性: CVE-2026-1111", "user": {"login": "github-actions[bot]"}},
           {"number": 2, "title": "コンテナ脆弱性: CVE-2026-2222", "user": {"login": "someone"}},
           {"number": 3, "title": "コンテナ脆弱性: CVE-2026-3333", "user": {"login": "github-actions[bot]"}, "pull_request": {}}]]'
    expect_out "container: 仕組みが起票した Issue が開いていれば残っている" false target_gone container CVE-2026-1111
    expect_out "container: 利用者が書いた同じ題名の Issue しか開いていなければ消えた" true target_gone container CVE-2026-2222
    expect_out "container: PR は Issue に数えない" true target_gone container CVE-2026-3333
    expect_out "container: Issue が閉じていれば消えた" true target_gone container CVE-2026-4444

    REQ="$DIR/../audit/required-checks.json"
    run_of() { jq -cn --arg n "$1" --arg c "$2" --arg at "$3" --argjson id "$4" '{id: $id, name: $n, conclusion: $c, started_at: $at}'; }
    ACTIVE=$(jq -r '.checks[] | select(.state == "active") | .context' "$REQ")
    all_green=$(while IFS= read -r c; do run_of "$c" success 2026-11-20T00:00:00Z 1; done <<<"$ACTIVE" | jq -cs .)
    pr_of() { jq -cn --argjson n "$1" --arg s "$2" --argjson merged "$3" '{number: $n, state: $s, merged: $merged, head: {sha: ("sha\($n)")}}'; }
    fx "repos/owner/repo/pulls/10" "$(pr_of 10 closed false)"
    fx "repos/owner/repo/pulls/11" "$(pr_of 11 closed true)"
    fx "repos/owner/repo/pulls/12" "$(pr_of 12 open false)"
    fx "repos/owner/repo/pulls/13" "$(pr_of 13 open false)"
    fx "repos/owner/repo/pulls/14" "$(pr_of 14 open false)"
    fx "repos/owner/repo/pulls/15" "$(pr_of 15 open false)"
    first_active=$(head -n 1 <<<"$ACTIVE")
    # 12: 期待一覧の検査がすべて通り、期待一覧に載らない検査と止めている検査は赤
    fx "repos/owner/repo/commits/sha12/check-runs?per_page=100" "$(jq -c --argjson more "[$(run_of not-listed failure 2026-11-20T00:00:00Z 2),$(run_of codex-review failure 2026-11-20T00:00:00Z 3)]" '{check_runs: (. + $more)}' <<<"$all_green")"
    # 13: 期待一覧の検査が1つ赤
    fx "repos/owner/repo/commits/sha13/check-runs?per_page=100" "$(jq -c --arg c "$first_active" '{check_runs: map(if .name == $c then .conclusion = "failure" else . end)}' <<<"$all_green")"
    # 14: 期待一覧の検査が1つまだ動いていない
    fx "repos/owner/repo/commits/sha14/check-runs?per_page=100" "$(jq -c --arg c "$first_active" '{check_runs: map(select(.name != $c))}' <<<"$all_green")"
    # 15: 古い赤のあとに動かし直して通った
    fx "repos/owner/repo/commits/sha15/check-runs?per_page=100" "$(jq -c --argjson old "$(run_of "$first_active" failure 2026-11-19T00:00:00Z 9)" '{check_runs: (. + [$old])}' <<<"$all_green")"
    expect_out "dependabot: PR が閉じていれば消えた" true target_gone dependabot 10 "$REQ"
    expect_out "dependabot: PR がマージされていれば消えた" true target_gone dependabot 11 "$REQ"
    expect_out "dependabot: 期待一覧の必須の検査がすべて通っていれば消えた(止めている検査と一覧に無い検査は見ない)" true target_gone dependabot 12 "$REQ"
    expect_out "dependabot: 期待一覧の必須の検査に赤があれば残っている" false target_gone dependabot 13 "$REQ"
    expect_out "dependabot: 期待一覧の必須の検査がまだ無ければ残っている" false target_gone dependabot 14 "$REQ"
    expect_out "dependabot: 同じ検査は最も新しい結論で見る" true target_gone dependabot 15 "$REQ"

    expect_rc1 "知らない種類では失敗する" target_gone unknown 1
    expect_rc1 "codeql の key が番号でなければ失敗する" target_gone codeql abc
    expect_rc1 "npm の key に版が無ければ失敗する" target_gone npm lodash
    expect_rc1 "dependabot で期待一覧が無ければ失敗する" target_gone dependabot 12 "$WORK/missing.json"
    expect_rc1 "応答を読めなければ失敗する(codeql)" target_gone codeql 99
    fx "repos/owner/repo/pulls/16" "$(pr_of 16 open false)"
    expect_rc1 "応答を読めなければ失敗する(dependabot の検査)" target_gone dependabot 16 "$REQ"
    fx "repos/owner/repo/code-scanning/alerts/98" '{"message": "Not Found"}'
    expect_rc1 "応答の形が違えば失敗する" target_gone codeql 98
    fx "repos/owner/repo/contents/backend/go.mod?ref=main" 'module example.com/app'
    expect_rc1 "go.mod に go の版が無ければ失敗する" target_gone go-stdlib 1.27.4
fi

# 結果のファイルを読む関数(recent_outcomes)の場合が使う、偽の対象ごとの実行と結果のファイルを作る関数
now=$(date -u +%s)
ago() { date -u -d "@$((now - $1 * 3600))" +%Y-%m-%dT%H:%M:%SZ; }
# 仕組みが専用のブランチ claude-auto-fix/run で起動した実行: wrun <実行の ID> <表示名> <状態> <結論> <日時>
wrun() {
    jq -cn --argjson id "$1" --arg title "$2" --arg status "$3" --arg c "$4" --arg at "$5" '
        {id: $id, display_title: $title, status: $status, conclusion: (if $c == "" then null else $c end),
         created_at: $at, updated_at: $at, html_url: "https://github.com/owner/repo/actions/runs/\($id)",
         event: "workflow_dispatch", head_branch: "claude-auto-fix/run", repository: {full_name: "owner/repo"},
         head_repository: {full_name: "owner/repo"}, path: ".github/workflows/claude-auto-fix-target.yaml"}'
}
# 別のリポジトリ(フォークの PR)から動いた実行: fork_run <実行の ID> <表示名> <結論> <日時>
fork_run() {
    wrun "$1" "$2" completed "$3" "$4" | jq -c '. + {event: "pull_request", head_branch: "fix",
        head_repository: {full_name: "someone/repo"}}'
}
outcome() {
    jq -cn --arg kind "$1" --arg key "$2" --arg result "$3" '
        {kind: $kind, key: $key, reason: "trigger", pr: null, checks: null, detail: null, result: $result,
         cause: null, pr_url: null, run_url: null, head_sha: null, finished_at: "2026-11-20T00:00:00Z"}'
}
RUNS_PATH="repos/owner/repo/actions/workflows/claude-auto-fix-target.yaml/runs"

if selected recent_outcomes; then
    # 直近4日の結果のファイルを読み、取り消されて結果のファイルが無い実行を unavailable と数える
    reset_fx
    fx "$RUNS_PATH" "[{\"workflow_runs\": [$(wrun 101 'claude-auto-fix npm lodash@4.17.21' completed success "$(ago 48)"),$(wrun 102 'claude-auto-fix codeql 42' completed cancelled "$(ago 24)"),$(wrun 103 'claude-auto-fix codeql 43' completed success "$(ago 120)")]},
        {\"workflow_runs\": [$(wrun 104 'claude-auto-fix codeql 44' in_progress '' "$(ago 3)"),$(wrun 105 'claude-auto-fix container CVE-2026-1111' completed cancelled "$(ago 12)"),$(wrun 106 'claude-auto-fix dependabot 7 pr#99@0123456789ab' completed cancelled "$(ago 6)")]}]"
    for id in 101 105; do fx "repos/owner/repo/actions/runs/${id}/artifacts?name=outcome" '{"artifacts": [{"name": "outcome", "expired": false}]}'; done
    for id in 102 106; do fx "repos/owner/repo/actions/runs/${id}/artifacts?name=outcome" '{"artifacts": []}'; done
    outcome npm lodash@4.17.21 unfixed >"$WORK/fx/outcome-101.json"
    jq -c '.run_url = "https://github.com/owner/repo/actions/runs/105"' <<<"$(outcome container CVE-2026-1111 pr)" >"$WORK/fx/outcome-105.json"
    out=$(recent_outcomes 2>"$WORK/err")
    rc=$?
    expect_eq "結果のファイルを読めれば0で終わる" "0" "$rc"
    expect_eq "直近4日の終わった実行だけを、始まった順に、結果のファイルか取り消しから読む" \
        'npm:lodash@4.17.21:unfixed codeql:42:unavailable container:CVE-2026-1111:pr dependabot:7:unavailable' \
        "$(jq -r 'map("\(.kind):\(.key):\(.result)") | join(" ")' <<<"$out")"
    expect_eq "結果のファイルに実行の URL が無ければ実行の URL を足す" "https://github.com/owner/repo/actions/runs/101" "$(jq -r '.[0].run_url' <<<"$out")"
    expect_eq "取り消されて結果のファイルが無い実行は、表示名から種類と key を読み、unavailable と数える" \
        '{"kind":"codeql","key":"42","reason":null,"pr":null,"checks":null,"detail":null,"result":"unavailable","cause":"cancelled","pr_url":null,"run_url":"https://github.com/owner/repo/actions/runs/102","head_sha":null}' \
        "$(jq -c '.[1] | del(.finished_at)' <<<"$out")"
    expect_eq "取り消された赤の検査の実行は、表示名から PR の番号を読む" 'red-check 99' "$(jq -r '.[3] | "\(.reason) \(.pr)"' <<<"$out")"
    expect_eq "取り消されても結果のファイルがあれば結果のファイルを使う" "pr" "$(jq -r '.[2].result' <<<"$out")"
    if grep -qE "/runs\?created=%3E%3D$(date -u -d "@$((now - 4 * 86400))" +%Y-%m-%d)T" "$STUB_CALLS"; then ok "4日前より後に始まった実行を問い合わせる"; else ng "4日前より後に始まった実行を問い合わせる($(cat "$STUB_CALLS"))"; fi
    if grep -qE 'runs/10[34]/' "$STUB_CALLS"; then ng "4日より前の実行と終わっていない実行の結果のファイルは読まない"; else ok "4日より前の実行と終わっていない実行の結果のファイルは読まない"; fi

    fx "$RUNS_PATH" "[{\"workflow_runs\": [$(wrun 107 'claude-auto-fix codeql 45' completed failure "$(ago 2)")]}]"
    fx "repos/owner/repo/actions/runs/107/artifacts?name=outcome" '{"artifacts": []}'
    expect_rc1 "取り消されていない実行に結果のファイルが無ければ失敗する" recent_outcomes
    fx "repos/owner/repo/actions/runs/107/artifacts?name=outcome" '{"artifacts": [{"name": "outcome", "expired": false}]}'
    outcome unknown 45 unfixed >"$WORK/fx/outcome-107.json"
    expect_rc1 "結果のファイルの形が違えば失敗する" recent_outcomes
    fx "$RUNS_PATH" "[{\"workflow_runs\": [$(wrun 108 'something else' completed cancelled "$(ago 2)")]}]"
    fx "repos/owner/repo/actions/runs/108/artifacts?name=outcome" '{"artifacts": []}'
    expect_rc1 "取り消された実行の表示名が形から外れていれば失敗する" recent_outcomes
    # フォークの PR から動いた実行と、claude-auto-fix/run 以外や別のファイルから動いた実行は、結果のファイルがあってもなくても数えない
    fx "$RUNS_PATH" "[{\"workflow_runs\": [$(fork_run 109 'claude-auto-fix codeql 46' failure "$(ago 2)"),$(fork_run 110 'claude-auto-fix codeql 47' success "$(ago 2)"),$(wrun 111 'claude-auto-fix codeql 48' completed cancelled "$(ago 2)" | jq -c '.head_branch = "fix"'),$(wrun 112 'claude-auto-fix codeql 49' completed cancelled "$(ago 2)" | jq -c '.path = ".github/workflows/other.yaml@main"'),$(wrun 113 'claude-auto-fix codeql 50' completed cancelled "$(ago 1)" | jq -c '.path = ".github/workflows/claude-auto-fix-target.yaml@refs/heads/claude-auto-fix/run"')]}]"
    fx "repos/owner/repo/actions/runs/109/artifacts?name=outcome" '{"artifacts": []}'
    fx "repos/owner/repo/actions/runs/110/artifacts?name=outcome" '{"artifacts": [{"name": "outcome", "expired": false}]}'
    outcome codeql 47 unavailable >"$WORK/fx/outcome-110.json"
    for id in 111 112 113; do fx "repos/owner/repo/actions/runs/${id}/artifacts?name=outcome" '{"artifacts": []}'; done
    out=$(recent_outcomes 2>"$WORK/err")
    rc=$?
    expect_eq "このリポジトリの claude-auto-fix/run から手で起動された実行でなければ、数えずに0で終わる" "0" "$rc"
    expect_eq "数えるのは、対象ごとのワークフローのファイルから claude-auto-fix/run で手で起動された実行だけ(@ の後ろは見ない)" 'codeql:50:unavailable' \
        "$(jq -r 'map("\(.kind):\(.key):\(.result)") | join(" ")' <<<"$out")"
    if grep -qE 'runs/1(09|10|11|12)/' "$STUB_CALLS"; then ng "出どころが違う実行の結果のファイルは読まない"; else ok "出どころが違う実行の結果のファイルは読まない"; fi
    reset_fx
    expect_rc1 "実行の一覧を読めなければ失敗する" recent_outcomes
fi

if selected recent_outcomes_run_branch; then
    # 実行のブランチが main の実行は、結果のファイルがあっても読まない。main で手で起動された実行は、
    # 仕組みが起動した実行ではなく、ref-check ジョブで止まるためである。ほかのワークフローの実行も読まない
    reset_fx
    fx "$RUNS_PATH" "[{\"workflow_runs\": [$(wrun 121 'claude-auto-fix codeql 61' completed failure "$(ago 3)" | jq -c '.head_branch = "main"'),$(wrun 122 'claude-auto-fix codeql 62' completed success "$(ago 2)" | jq -c '.path = ".github/workflows/other.yaml"'),$(wrun 123 'claude-auto-fix codeql 63' completed success "$(ago 1)")]}]"
    for id in 121 122 123; do fx "repos/owner/repo/actions/runs/${id}/artifacts?name=outcome" '{"artifacts": [{"name": "outcome", "expired": false}]}'; done
    outcome codeql 61 pr >"$WORK/fx/outcome-121.json"
    outcome codeql 62 pr >"$WORK/fx/outcome-122.json"
    outcome codeql 63 unfixed >"$WORK/fx/outcome-123.json"
    out=$(recent_outcomes 2>"$WORK/err")
    rc=$?
    if [ "$rc" -eq 0 ] && [ "$(jq -r 'map("\(.kind):\(.key):\(.result)") | join(" ")' <<<"$out")" = 'codeql:63:unfixed' ] &&
        ! grep -qE 'runs/12[12]/' "$STUB_CALLS"; then
        ok "結果のファイルを読む関数が、実行のブランチが claude-auto-fix/run の実行だけを読み、実行のブランチが main の実行と、ほかのワークフローの実行を読まない"
    else
        ng "結果のファイルを読む関数が、実行のブランチが claude-auto-fix/run の実行だけを読み、実行のブランチが main の実行と、ほかのワークフローの実行を読まない(終了コード $rc、出力 '$out'、呼び出し $(tr '\n' ' ' <"$STUB_CALLS"))"
    fi
fi

# --- 鍵の取り替えを求める Issue(key_issues) -------------------------------------------------
if selected key_issues; then
    KEY_PAGES=$(jq -nc --arg t "$CAF_KEY_TITLE" --arg m "$CAF_KEY_MARKER" '[[
        {number: 1, user: {login: "github-actions[bot]"}, title: $t, body: "本文 \($m)", closed_at: "2026-11-20T10:00:00Z"},
        {number: 2, user: {login: "someone"}, title: $t, body: "本文 \($m)", closed_at: "2026-11-20T10:00:00Z"},
        {number: 3, user: {login: "github-actions[bot]"}, title: $t, body: "目印が無い", closed_at: "2026-11-20T10:00:00Z"},
        {number: 4, user: {login: "github-actions[bot]"}, title: "別の題名", body: $m, closed_at: "2026-11-20T10:00:00Z"},
        {number: 5, user: {login: "github-actions[bot]"}, title: $t, body: $m, pull_request: {}, closed_at: "2026-11-20T10:00:00Z"}
    ], [
        {number: 6, user: {login: "github-actions[bot]"}, title: $t, body: $m, closed_at: "2026-11-18T10:00:00Z"},
        {number: 7, user: {login: "github-actions[bot]"}, title: $t, body: null, closed_at: null}
    ]]')
    expect_eq "key_issues: github-actions[bot] が起票した、題名と目印が合う Issue だけを出す" "1 6" \
        "$(key_issues <<<"$KEY_PAGES" | tr '\n' ' ' | sed 's/ $//')"
    expect_eq "key_issues: 閉じた日時の下限を渡すと、その日時より後に閉じた Issue だけを出す" "1" \
        "$(key_issues 2026-11-19T00:00:00Z <<<"$KEY_PAGES" | tr '\n' ' ' | sed 's/ $//')"
    if key_issues <<<'{"x":1}' >/dev/null; then
        ng "key_issues: 一覧の形が違えば失敗する"
    else
        ok "key_issues: 一覧の形が違えば失敗する"
    fi
fi

# --- dependency-cooldown の判定が要るか(cooldown_needed)と、3つの判定の終わり方(cooldown_outcome) ---

# 偽の ci-tool-versions.json。リポジトリの本物の一覧に無いパスを書き、関数が渡された一覧を読むことを確かめる。
# 開発環境の版のファイルは、Go の版を書くファイルと区別できるように、Dockerfile でない名前にする
FAKE_VERSIONS="$WORK/ci-tool-versions.json"
cat >"$FAKE_VERSIONS" <<'EOF'
{
  "schema": 1,
  "tools": {
    "alpha": {
      "ci": [
        { "file": ".github/workflows/fake-alpha.yaml", "key": "alpha-version" },
        { "file": ".github/workflows/fake-alpha-2.yaml", "key": "alpha-version" }
      ],
      "dev": { "file": "tools/fake-alpha-dev.txt", "image": "alpha" }
    },
    "beta": {
      "ci": [{ "file": ".github/workflows/fake-beta.yaml", "key": "BETA_VERSION" }]
    }
  }
}
EOF

# 使い方: needed_for <パス...>。パスを1行に1つ書いた一覧のファイルを作り、cooldown_needed の出力を出す
needed_for() {
    printf '%s\n' "$@" >"$WORK/paths.txt"
    cooldown_needed "$FAKE_VERSIONS" "$WORK/paths.txt"
}

if selected cooldown_needed_files; then
    for p in frontend/package.json frontend/pnpm-lock.yaml frontend/pnpm-workspace.yaml \
        backend/gradle/libs.versions.toml backend/go.mod backend/go.sum \
        docker/backend-go/Dockerfile.prod docker/sample/app.dockerfile \
        .github/workflows/fake-alpha.yaml .github/workflows/fake-alpha-2.yaml \
        tools/fake-alpha-dev.txt .github/workflows/fake-beta.yaml; do
        expect_eq "cooldown_needed: ${p} が変われば true" "true" "$(needed_for frontend/src/app.ts "$p" README.md)"
    done
    expect_eq "cooldown_needed: ふつうのコードのファイルだけなら false" "false" \
        "$(needed_for frontend/src/app.ts backend/internal/sample/sample.go README.md \
            frontend/src/package.json frontend/package.json.bak backend/go.mod.orig)"
    expect_eq "cooldown_needed: 渡された一覧に無い CI のファイルだけなら false" "false" \
        "$(needed_for .github/workflows/ci.yaml .github/workflows/container-scan.yaml docker/frontend/README.md)"
    expect_eq "cooldown_needed: 空白を含むパスも1行を1つのパスとして読む" "false" \
        "$(needed_for "frontend/src/some dir/package.json")"
    printf 'README.md\r\nfrontend/package.json\r\n' >"$WORK/paths.txt"
    expect_eq "cooldown_needed: 行の末尾の CR を除いて比べる" "true" \
        "$(cooldown_needed "$FAKE_VERSIONS" "$WORK/paths.txt")"
    : >"$WORK/paths.txt"
    expect_eq "cooldown_needed: 変えたパスが無ければ false" "false" \
        "$(cooldown_needed "$FAKE_VERSIONS" "$WORK/paths.txt")"

    expect_rc1 "cooldown_needed: ci-tool-versions.json が無ければ失敗する" \
        cooldown_needed "$WORK/none.json" "$WORK/paths.txt"
    echo '{"tools": "x"}' >"$WORK/bad-versions.json"
    expect_rc1 "cooldown_needed: ci-tool-versions.json の形が違えば失敗する" \
        cooldown_needed "$WORK/bad-versions.json" "$WORK/paths.txt"
    echo 'not json' >"$WORK/bad-versions.json"
    expect_rc1 "cooldown_needed: ci-tool-versions.json を JSON として読めなければ失敗する" \
        cooldown_needed "$WORK/bad-versions.json" "$WORK/paths.txt"
    expect_rc1 "cooldown_needed: 変えたパスの一覧のファイルが無ければ失敗する" \
        cooldown_needed "$FAKE_VERSIONS" "$WORK/none.txt"
    expect_rc1 "cooldown_needed: 引数が足りなければ失敗する" cooldown_needed "$FAKE_VERSIONS"
fi

# Go の版を書くファイルの場合ごとに、cooldown_needed が go_release_is_target と同じ答えになる。
# go_release_is_target は、このテストが lib-go-release.sh を読み込んで直接呼ぶ
if selected cooldown_needed_go_parity; then
    # shellcheck source=.github/scripts/lib-go-release.sh
    . "$DIR/lib-go-release.sh"
    for p in go.mod tools/go.mod backend/go.mod Dockerfile docker/backend-go/Dockerfile \
        docker/backend-go/Dockerfile.prod docker/sample/Dockerfile.dev docker/sample/app.Dockerfile \
        docker/sample/app.dockerfile docker/sample/dockerfile docker/sample/Dockerfile-old \
        docker/sample/notDockerfile go.mod.bak go.modx; do
        if go_release_is_target "$p"; then want=true; else want=false; fi
        expect_eq "cooldown_needed: ${p} の答えが go_release_is_target(${want})と同じ" \
            "$want" "$(needed_for "$p")"
    done
fi

if selected cooldown_outcome; then
    while read -r dep go ci want; do
        expect_eq "cooldown_outcome: (${dep},${go},${ci}) は ${want}" "$want" "$(cooldown_outcome "$dep" "$go" "$ci")"
    done <<'EOF'
0 0 0 ship
3 0 0 ship
1 0 0 blocked
0 1 0 blocked
0 0 1 blocked
3 1 0 blocked
1 1 1 blocked
2 0 0 fail
0 2 0 fail
0 0 2 fail
1 2 0 fail
0 3 0 fail
0 0 3 fail
3 0 2 fail
EOF
    expect_eq "cooldown_outcome: 数でない終わり方は fail" "fail" "$(cooldown_outcome x 0 0)"
    expect_eq "cooldown_outcome: 空の終わり方は fail" "fail" "$(cooldown_outcome 0 '' 1)"
    expect_eq "cooldown_outcome: 先頭に 0 を付けた終わり方は fail" "fail" "$(cooldown_outcome 01 0 0)"
    expect_rc1 "cooldown_outcome: 引数が3つでなければ失敗する" cooldown_outcome 0 0
fi

if [ "$CASES_RUN" -eq 0 ]; then
    echo "NG: 場合 ${CASE} はありません"
    exit 1
fi
if [ "$FAILED" -ne 0 ]; then
    echo "lib-claude-auto-fix.sh のテストに失敗しました"
    exit 1
fi
echo "lib-claude-auto-fix.sh のテストはすべて通りました"
