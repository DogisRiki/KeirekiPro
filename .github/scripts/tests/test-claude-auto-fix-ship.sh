#!/usr/bin/env bash
# =====================================================================
# claude-auto-fix-ship.sh の自動テスト
#
# 場合ごとに、一時のフォルダに起点のコードの Git のリポジトリ target と、push 先の裸のリポジトリ
# origin を作る。裸のリポジトリとは、作業のファイルを持たず、push を受けるだけのリポジトリである。
# target の main のコミットを origin に push し、起点のコミットと final.patch を作ってから、
# claude-auto-fix-ship.sh を呼ぶ。gh は PATH の先頭に置いた偽物に替える。偽の gh は、受け取った
# 引数を CAP/gh.calls に残し、gh pr create の題名と本文を CAP/pr-title と CAP/pr-body に残す。
# ガードは本物の claude-auto-fix-guard.sh を使う。
#
# 場合の名前を KP_TEST_CASE に入れると、その場合だけを流す(例: KP_TEST_CASE=new-pr)。
# 名前は sha guard-github guard-suppress dependabot new-pr codeql no-claude-text red-check red-skip
# stale-branch open-pr pr-fail push-fail container go urls file-names usage。
# どの場合でも、終わりに、gh pr merge と auto-merge の予約と main への push と PR を閉じる操作と、
# 警告を却下する API と @dependabot を含む呼び出しが無いことを確かめる。
# =====================================================================
set -uo pipefail

HERE="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$HERE/claude-auto-fix-ship.sh"
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

# ブランチ名は、本物の lib-claude-auto-fix.sh の target_names で求める
# shellcheck source=.github/scripts/lib-claude-auto-fix.sh
. "$HERE/lib-claude-auto-fix.sh"
branch_of() { target_names "$1" "$2" | jq -r .branch; }

export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.com GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.com
REPO_NAME="o/r"
SERVER="https://github.com"
MARK="CLAUDE_WROTE_THIS_TEXT"

BIN="$WORK/bin"
mkdir -p "$BIN"
# --- 偽の gh。CAP/pr-mode が fail なら gh pr create が失敗し、CAP/open-pulls.json があれば
# 開いている PR の一覧としてそれを出す。CAP/issues-cv.json は、ラベル container-vuln の Issue の一覧
# (--slurp の形)である
cat >"$BIN/gh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" | tr '\n' ' ' >>"$CAP/gh.calls"
echo >>"$CAP/gh.calls"
case "$1 ${2:-}" in
"auth setup-git") exit 0 ;;
"pr create")
    shift 2
    while [ "$#" -gt 0 ]; do
        case "$1" in
        --title) printf '%s' "$2" >"$CAP/pr-title"; shift 2 ;;
        --body) printf '%s' "$2" >"$CAP/pr-body"; shift 2 ;;
        *) printf '%s\n' "$1" >>"$CAP/pr-args"; shift ;;
        esac
    done
    [ "$(cat "$CAP/pr-mode" 2>/dev/null)" != fail ] || { echo "pull request create failed" >&2; exit 1; }
    echo "Creating pull request for branch into main" >&2
    echo "https://github.com/o/r/pull/99"
    exit 0 ;;
esac
if [ "$1" = api ]; then
    for a in "$@"; do
        case "$a" in
        repos/o/r/pulls\?state=open*) cat "$CAP/open-pulls.json" 2>/dev/null || echo '[]'; exit 0 ;;
        repos/o/r/issues\?labels=container-vuln*) cat "$CAP/issues-cv.json"; exit 0 ;;
        esac
    done
fi
echo "偽の gh が知らない呼び出し: $*" >&2
exit 1
EOF
chmod +x "$BIN/gh"

# --- 場合ごとの準備。target と origin を作り、main のコミットを MAIN に、起点のコミットを BASE に入れる
new_case() {
    CAP="$WORK/cap-$1"
    R="$WORK/repo-$1"
    ORIGIN="$WORK/origin-$1.git"
    mkdir -p "$CAP" "$R"
    export CAP
    git init -q --bare "$ORIGIN"
    git -C "$R" init -q
    git -C "$R" checkout -q -b main
    mkdir -p "$R/backend/gradle" "$R/backend/src/main/java/com/example" "$R/frontend/src" "$R/.github/workflows" "$R/docs"
    echo "apply from: 'gradle/quality.gradle'" >"$R/backend/build.gradle"
    echo "// quality gate" >"$R/backend/gradle/quality.gradle"
    printf 'package com.example;\nclass Sample {\n}\n' >"$R/backend/src/main/java/com/example/Sample.java"
    echo "export const x = 1;" >"$R/frontend/src/app.ts"
    printf 'name: ci\non: push\njobs: {}\n' >"$R/.github/workflows/ci.yaml"
    echo "# docs" >"$R/docs/readme.md"
    git -C "$R" add -A
    git -C "$R" commit -q -m main
    MAIN=$(git -C "$R" rev-parse HEAD)
    git -C "$R" remote add origin "$ORIGIN"
    git -C "$R" push -q origin main
    BASE="$MAIN"
}

# 起点のコミットを、main の子のコミットにする(Dependabot の版上げか、PR の head)。
# 使い方: base_commit <関数>。関数は、今のフォルダを target にして起点の変更を作る
base_commit() {
    (cd "$R" && "$1") || exit 1
    git -C "$R" add -A
    git -C "$R" commit -q -m base
    BASE=$(git -C "$R" rev-parse HEAD)
}

# final.patch を作る。使い方: make_final <関数>。関数は、今のフォルダを target にして変更を作る。
# 作り終えたら、target の作業のフォルダを起点のコミットに戻す(ship ジョブと同じ形)
make_final() {
    git -C "$R" checkout -q --detach "$BASE"
    (cd "$R" && "$1") || exit 1
    git -C "$R" add -A
    git -C "$R" commit -q -m final
    git -C "$R" diff --binary "$BASE" HEAD >"$WORK/final.patch"
    FINAL_TREE=$(git -C "$R" rev-parse "HEAD^{tree}")
    git -C "$R" checkout -q --detach "$BASE"
    SUM=$(sha256sum <"$WORK/final.patch" | cut -d' ' -f1)
}

# 使い方: run_ship <kind> <key> <reason> <pr> <checks> <detail>。OUT と RC と ERR を入れる
run_ship() {
    OUT=$(cd "$WORK" && PATH="$BIN:$PATH" GITHUB_REPOSITORY="$REPO_NAME" GITHUB_SERVER_URL="$SERVER" \
        CAF_TARGET_DIR="$R" CAF_MAIN_SHA="${MAIN_ARG-$MAIN}" \
        bash "$SCRIPT" "$@" "$WORK/final.patch" "${SUM_ARG:-$SUM}" "$BASE" 2>"$CAP/stderr")
    RC=$?
    ERR=$(cat "$CAP/stderr")
}

remote_ref() { git --git-dir="$ORIGIN" rev-parse --verify -q "refs/heads/$1" 2>/dev/null; }
remote_branches() { git --git-dir="$ORIGIN" for-each-ref --format='%(refname)' refs/heads | sort | tr '\n' ' '; }
calls() { cat "$CAP/gh.calls" 2>/dev/null; }
pr_title() { cat "$CAP/pr-title" 2>/dev/null; }
pr_body() { cat "$CAP/pr-body" 2>/dev/null; }
commit_msg() { git --git-dir="$ORIGIN" log -1 --format=%B "$1"; }

# push も PR の作成もしていないこと
expect_no_push() {
    expect_eq "$1: origin のブランチは main だけのまま" "$(remote_branches)" "refs/heads/main "
    expect_not_has "$1: gh pr create を呼ばない" "$(calls)" "pr create"
}

# どの場合でも、してはいけない操作が無いこと
expect_safe() {
    local c
    c=$(calls)
    expect_eq "origin の main が動かない" "$(remote_ref main)" "$MAIN"
    expect_not_has "gh pr merge を呼ばない" "$c" "pr merge"
    expect_not_has "auto-merge を予約しない" "$c" "--auto"
    expect_not_has "PR を閉じない" "$c" "pr close"
    expect_not_has "PR を閉じる API を呼ばない" "$c" "state=closed"
    expect_not_has "警告を却下しない" "$c" "dismiss"
    expect_not_has "PATCH の API を呼ばない" "$c" "PATCH"
    expect_not_has "@dependabot を含む呼び出しをしない" "$c" "@dependabot"
    expect_not_has "コメントを書かない" "$c" "comment"
    expect_eq "target の作業のフォルダを変えない" "$(git -C "$R" status --porcelain)" ""
}

# --- 変更を作る関数
edit_app() { echo "export const y = 2; // ${MARK}" >>frontend/src/app.ts; }
edit_workflow() { echo "# ${MARK}" >>.github/workflows/ci.yaml; }
edit_suppress() { printf 'package com.example;\n@SuppressWarnings("all")\nclass Sample {\n}\n' >backend/src/main/java/com/example/Sample.java; }
bump_workflow() { sed -i 's/jobs: {}/jobs: {} # bumped/' .github/workflows/ci.yaml; }
pr_head_change() { echo "export const z = 3;" >>frontend/src/app.ts; }
edit_names() {
    echo "a" >"docs/plain-name_1.md"
    echo "b" >'docs/back`tick.md'
    echo "c" >"docs/日本語 の名前.md"
}

NPM_DETAIL='{"name":"left","version":"1.2.3","ranges":["<1.2.3"],"urgent":false,"alerts":[{"html_url":"https://github.com/o/r/security/dependabot/5","severity":"high","scope":"runtime"},{"html_url":"https://evil.example.com/o/r/security/dependabot/6","severity":"low","scope":"runtime"},{"html_url":"https://github.com/o/r/security/dependabot/7","severity":"low","scope":"development"}]}'
MAVEN_DETAIL='{"name":"com.example:lib","version":"2.0.0","ranges":["<2.0.0"],"urgent":false,"alerts":[{"html_url":"https://github.com/o/r/security/dependabot/8","severity":"high","scope":"runtime"}]}'
STDLIB_DETAIL='{"version":"1.25.4","osv":["GO-2026-4001","GO-2026-4002"]}'
MODULE_DETAIL='{"module":"golang.org/x/net","version":"0.40.0","osv":["GO-2026-4100"]}'
CV_ISSUES='[[{"number":30,"title":"コンテナ脆弱性: CVE-2026-1111","user":{"login":"github-actions[bot]"},"html_url":"https://github.com/o/r/issues/30"},{"number":12,"title":"コンテナ脆弱性: CVE-2026-1111","user":{"login":"someone"},"html_url":"https://github.com/o/r/issues/12"}]]'

# =====================================================================
if want sha; then
    new_case sha
    make_final edit_app
    SUM_ARG=0000000000000000000000000000000000000000000000000000000000000000 run_ship npm left@1.2.3 trigger "" "" "$NPM_DETAIL"
    expect_eq "差分の SHA-256 が違えば0以外で終わる" "$RC" 1
    expect_has "SHA-256 が違うと書く" "$ERR" "SHA-256"
    expect_eq "outcome を書かない" "$OUT" ""
    expect_no_push "SHA-256 が違う"
    expect_safe
fi

if want guard-github; then
    new_case guard-github
    make_final edit_workflow
    run_ship npm left@1.2.3 trigger "" "" "$NPM_DETAIL"
    expect_eq "final.patch に .github/ の変更があれば0で終わる" "$RC" 0
    expect_eq "final.patch に .github/ の変更があれば unfixed になる" "$OUT" "outcome=unfixed"
    expect_no_push ".github/ の変更"
    expect_safe
fi

if want guard-suppress; then
    new_case guard-suppress
    make_final edit_suppress
    run_ship maven com.example:lib@2.0.0 trigger "" "" "$MAVEN_DETAIL"
    expect_eq "final.patch に足した @SuppressWarnings があれば0で終わる" "$RC" 0
    expect_eq "final.patch に足した @SuppressWarnings があれば unfixed になる" "$OUT" "outcome=unfixed"
    expect_no_push "@SuppressWarnings の行"
    expect_safe
fi

if want dependabot; then
    new_case dependabot
    base_commit bump_workflow
    make_final edit_app
    run_ship dependabot 42 trigger 42 '["ci / test"]' ""
    b=$(branch_of dependabot 42)
    expect_eq "base.patch が .github/workflows/ を変え final.patch が変えないときは0で終わる" "$RC" 0
    expect_eq "ガードを通って PR を作る" "$OUT" "$(printf 'outcome=pr\npr_url=https://github.com/o/r/pull/99')"
    h=$(remote_ref "$b")
    expect_eq "Dependabot の PR とは別のブランチに push する" "$([ -n "$h" ] && echo yes)" yes
    expect_eq "新しい PR のコミットの親は main" "$(git --git-dir="$ORIGIN" rev-parse "$h^@" 2>/dev/null)" "$MAIN"
    expect_eq "新しい PR のコミットに Dependabot の版上げと final.patch が入る" \
        "$(git --git-dir="$ORIGIN" rev-parse "$h^{tree}")" "$FINAL_TREE"
    expect_has "本文に Dependabot の PR の URL を書く" "$(pr_body)" "https://github.com/o/r/pull/42"
    expect_eq "題名は決まった文" "$(pr_title)" "fix: Dependabot の PR #42 の赤の検査を直す"
    expect_has "head は新しいブランチ" "$(cat "$CAP/pr-args")" "$b"
    expect_not_has "Dependabot のブランチに push しない" "$(remote_branches)" "dependabot/"
    expect_safe
fi

if want new-pr; then
    new_case new-pr
    make_final edit_app
    run_ship npm left@1.2.3 manual "" "" "$NPM_DETAIL"
    b=$(branch_of npm left@1.2.3)
    expect_eq "新しい PR で0で終わる" "$RC" 0
    expect_eq "outcome=pr と pr_url を書く" "$OUT" "$(printf 'outcome=pr\npr_url=https://github.com/o/r/pull/99')"
    h=$(remote_ref "$b")
    expect_eq "main からの1つのコミット" "$(git --git-dir="$ORIGIN" rev-list --count "$MAIN..$h" 2>/dev/null)" 1
    expect_eq "コミットの親は main" "$(git --git-dir="$ORIGIN" rev-parse "$h^@" 2>/dev/null)" "$MAIN"
    expect_eq "コミットの木は main に final.patch を当てた木" "$(git --git-dir="$ORIGIN" rev-parse "$h^{tree}")" "$FINAL_TREE"
    expect_eq "作り手は claude-auto-fix-bot" "$(git --git-dir="$ORIGIN" log -1 --format='%an <%ae>|%cn <%ce>' "$h")" \
        "claude-auto-fix-bot <claude-auto-fix-bot@users.noreply.github.com>|claude-auto-fix-bot <claude-auto-fix-bot@users.noreply.github.com>"
    msg=$(commit_msg "$h")
    expect_eq "メッセージの末尾は Claude-Auto-Fix-Key の行" "$(printf '%s\n' "$msg" | sed '/^$/d' | tail -n 1)" "Claude-Auto-Fix-Key: npm left@1.2.3"
    expect_eq "メッセージは .commit_template の欄を持つ" \
        "$(printf '%s\n' "$msg" | grep -E '^(Changes:|Reason:|BREAKING CHANGE: N/A|Related: |Refs: N/A)' | cut -d: -f1 | tr '\n' ' ')" \
        "Changes Reason BREAKING CHANGE Related Refs "
    expect_eq "題名" "$(printf '%s\n' "$msg" | head -n 1)" "fix: npm の部品 left@1.2.3 の脆弱性を直す"
    args=$(cat "$CAP/pr-args")
    expect_eq "gh pr create の引数" "$(printf '%s\n' "$args" | tr '\n' ' ')" "--base main --head $b --label claude-auto-fix "
    body=$(pr_body)
    expect_has "本文に PR の目印を書く" "$body" "<!-- claude-auto-fix-pr kind=npm key=left@1.2.3 -->"
    expect_eq "本文の最初の行は決まった文で、key をコードの形で書く" "$(printf '%s\n' "$body" | head -n 1)" \
        "claude-auto-fix の仕組みが、npm の部品 \`left@1.2.3\` の脆弱性を直すために作った PR です。中身は、仕組みが確かめた変更だけです。"
    d=$(printf '%s\n' "$body" | sed -n 's/^<!-- claude-auto-fix-detail \([A-Za-z0-9+\/=]*\) -->$/\1/p' | base64 -d 2>/dev/null)
    expect_eq "本文の detail の目印を読み直すと入力の detail になる" "$d" "$NPM_DETAIL"
    expect_has "本文に変えたファイルを書く" "$body" "- \`frontend/src/app.ts\`"
    expect_has "本文に組の警告の URL を書く" "$body" "- https://github.com/o/r/security/dependabot/5"
    expect_has "本文に組の2つ目の警告の URL を書く" "$body" "- https://github.com/o/r/security/dependabot/7"
    expect_not_has "このリポジトリの警告でない URL を書かない" "$body" "evil.example.com"
    expect_has "開いている PR を調べる" "$(calls)" "pulls?state=open"
    expect_safe
fi

if want codeql; then
    new_case codeql
    make_final edit_app
    run_ship codeql 7 trigger "" "" ""
    b=$(branch_of codeql 7)
    expect_eq "codeql で0で終わる" "$RC" 0
    expect_eq "題名は決まった文" "$(pr_title)" "fix: CodeQL の警告 #7 を直す"
    expect_eq "本文は決まった文と警告の URL だけ" "$(pr_body)" "$(printf '%s\n' \
        "claude-auto-fix の仕組みが、CodeQL の警告を直すために作った PR です。中身は、仕組みが確かめた変更だけです。" \
        "<!-- claude-auto-fix-pr kind=codeql key=7 -->" \
        "" \
        "## 対象" \
        "" \
        "- https://github.com/o/r/security/code-scanning/7")"
    expect_eq "コミットのメッセージは決まった文と警告の URL だけ" "$(commit_msg "$(remote_ref "$b")")" "$(printf '%s\n' \
        "fix: CodeQL の警告 #7 を直す" \
        "" \
        "Changes:" \
        "- CodeQL の警告 #7 を直す変更を、claude-auto-fix の仕組みが確かめてコミットした" \
        "" \
        "Reason:" \
        "- CodeQL の警告 #7 を、所有者の手を借りずに直すため" \
        "" \
        "BREAKING CHANGE: N/A" \
        "Related: https://github.com/o/r/security/code-scanning/7" \
        "Refs: N/A" \
        "" \
        "Claude-Auto-Fix-Key: codeql 7")"
    expect_not_has "本文に変えたファイルを書かない" "$(pr_body)" "frontend/src/app.ts"
    expect_not_has "標準エラーに変えたファイルを書かない" "$ERR" "frontend/src/app.ts"
    expect_safe
fi

if want no-claude-text; then
    for spec in "npm|left@1.2.3|$NPM_DETAIL" "maven|com.example:lib@2.0.0|$MAVEN_DETAIL" \
        "go-stdlib|1.25.4|$STDLIB_DETAIL" "go-module|golang.org/x/net@0.40.0|$MODULE_DETAIL" \
        "codeql|7|" "container|CVE-2026-1111|" "dependabot|42|"; do
        kind="${spec%%|*}"
        rest="${spec#*|}"
        key="${rest%%|*}"
        detail="${rest#*|}"
        new_case "text-$kind"
        printf '%s' "$CV_ISSUES" >"$CAP/issues-cv.json"
        make_final edit_app
        pr=""
        [ "$kind" != dependabot ] || pr=42
        run_ship "$kind" "$key" trigger "$pr" "" "$detail"
        expect_eq "$kind: 0で終わる" "$RC" 0
        expect_not_has "$kind: 題名に Claude が書いた文が入らない" "$(pr_title)" "$MARK"
        expect_not_has "$kind: 本文に Claude が書いた文が入らない" "$(pr_body)" "$MARK"
        expect_not_has "$kind: コミットのメッセージに Claude が書いた文が入らない" \
            "$(commit_msg "$(remote_ref "$(branch_of "$kind" "$key")")")" "$MARK"
        expect_safe
    done
fi

if want red-check; then
    new_case red-check
    b=$(branch_of npm left@1.2.3)
    base_commit pr_head_change
    git -C "$R" push -q origin "HEAD:refs/heads/$b"
    make_final edit_app
    run_ship npm left@1.2.3 red-check 77 '["ci / test","lint"]' "$NPM_DETAIL"
    expect_eq "red-check で0で終わる" "$RC" 0
    expect_eq "PR の URL を書く" "$OUT" "$(printf 'outcome=pr\npr_url=https://github.com/o/r/pull/77')"
    h=$(remote_ref "$b")
    expect_eq "PR のブランチに起点の子のコミットを足す" "$(git --git-dir="$ORIGIN" rev-parse "$h^@" 2>/dev/null)" "$BASE"
    expect_eq "足したコミットの木は起点に final.patch を当てた木" "$(git --git-dir="$ORIGIN" rev-parse "$h^{tree}")" "$FINAL_TREE"
    msg=$(commit_msg "$h")
    expect_eq "赤の検査ごとに Claude-Auto-Fix-Check の行を書く" "$(printf '%s\n' "$msg" | grep '^Claude-Auto-Fix-' | tr '\n' '|')" \
        "Claude-Auto-Fix-Key: npm left@1.2.3|Claude-Auto-Fix-Check: ci / test|Claude-Auto-Fix-Check: lint|"
    expect_eq "題名は決まった文" "$(printf '%s\n' "$msg" | head -n 1)" "fix: claude-auto-fix の PR #77 の赤の検査を直す"
    expect_not_has "新しい PR を作らない" "$(calls)" "pr create"
    expect_safe
fi

if want red-skip; then
    new_case red-skip
    b=$(branch_of npm left@1.2.3)
    base_commit pr_head_change
    git -C "$R" push -q origin "HEAD:refs/heads/$b"
    echo "moved" >"$R/docs/moved.md"
    git -C "$R" add -A
    git -C "$R" commit -q -m moved
    git -C "$R" push -q origin "HEAD:refs/heads/$b"
    moved=$(git -C "$R" rev-parse HEAD)
    git -C "$R" checkout -q --detach "$BASE"
    make_final edit_app
    run_ship npm left@1.2.3 red-check 77 '["lint"]' "$NPM_DETAIL"
    expect_eq "ブランチの head が起点と違えば0で終わる" "$RC" 0
    expect_eq "ブランチの head が起点と違えば skipped になる" "$OUT" "outcome=skipped"
    expect_eq "ブランチの head を変えない" "$(remote_ref "$b")" "$moved"
    expect_safe
fi

if want stale-branch; then
    new_case stale-branch
    b=$(branch_of npm left@1.2.3)
    base_commit pr_head_change
    git -C "$R" push -q origin "HEAD:refs/heads/$b"
    stale=$(git -C "$R" rev-parse HEAD)
    git -C "$R" checkout -q --detach "$MAIN"
    BASE="$MAIN"
    make_final edit_app
    run_ship npm left@1.2.3 retry "" "" "$NPM_DETAIL"
    expect_eq "閉じた PR のブランチが残っていても0で終わる" "$RC" 0
    h=$(remote_ref "$b")
    expect_eq "残っていたブランチを新しい PR のコミットに置き換える" "$(git --git-dir="$ORIGIN" rev-parse "$h^@" 2>/dev/null)" "$MAIN"
    expect_not_has "残っていたコミットを新しい PR に含めない" "$(git --git-dir="$ORIGIN" rev-list "$h")" "$stale"
    expect_safe
fi

if want open-pr; then
    new_case open-pr
    echo '[{"number":5,"head":{"ref":"x"}}]' >"$CAP/open-pulls.json"
    make_final edit_app
    run_ship npm left@1.2.3 trigger "" "" "$NPM_DETAIL"
    expect_eq "同じブランチの開いている PR があれば0以外で終わる" "$RC" 1
    expect_no_push "開いている PR がある"
    expect_safe
fi

if want pr-fail; then
    new_case pr-fail
    echo fail >"$CAP/pr-mode"
    make_final edit_app
    run_ship npm left@1.2.3 trigger "" "" "$NPM_DETAIL"
    expect_eq "PR を作れなければ0以外で終わる" "$RC" 1
    expect_not_has "PR を作れなければ outcome=pr を書かない" "$OUT" "outcome=pr"
    expect_safe
fi

if want push-fail; then
    new_case push-fail
    make_final edit_app
    git -C "$R" remote set-url origin "$WORK/no-such-origin.git"
    run_ship npm left@1.2.3 trigger "" "" "$NPM_DETAIL"
    expect_eq "push できなければ0以外で終わる" "$RC" 1
    expect_not_has "push できなければ PR を作らない" "$(calls)" "pr create"
    git -C "$R" remote set-url origin "$ORIGIN"
    expect_safe
fi

if want container; then
    new_case container
    printf '%s' "$CV_ISSUES" >"$CAP/issues-cv.json"
    make_final edit_app
    run_ship container CVE-2026-1111 trigger "" "" ""
    expect_eq "container で0で終わる" "$RC" 0
    expect_has "本文に github-actions[bot] の Issue の URL を書く" "$(pr_body)" "- https://github.com/o/r/issues/30"
    expect_not_has "ほかの人が書いた Issue の URL を書かない" "$(pr_body)" "issues/12"
    expect_eq "題名は決まった文" "$(pr_title)" "fix: コンテナの脆弱性 CVE-2026-1111 を直す"
    expect_safe

    new_case container-none
    echo '[[]]' >"$CAP/issues-cv.json"
    make_final edit_app
    run_ship container CVE-2026-1111 trigger "" "" ""
    expect_eq "Issue が無ければ0以外で終わる" "$RC" 1
    expect_no_push "Issue が無い"
    expect_safe
fi

if want go; then
    new_case go
    make_final edit_app
    run_ship go-stdlib 1.25.4 trigger "" "" "$STDLIB_DETAIL"
    expect_eq "go-stdlib で0で終わる" "$RC" 0
    expect_has "本文に1つ目の Go の脆弱性の URL を書く" "$(pr_body)" "- https://pkg.go.dev/vuln/GO-2026-4001"
    expect_has "本文に2つ目の Go の脆弱性の URL を書く" "$(pr_body)" "- https://pkg.go.dev/vuln/GO-2026-4002"
    expect_eq "go-stdlib の題名" "$(pr_title)" "fix: Go の標準ライブラリの脆弱性を Go 1.25.4 で直す"
    expect_safe

    new_case go-module
    make_final edit_app
    run_ship go-module golang.org/x/net@0.40.0 trigger "" "" "$MODULE_DETAIL"
    expect_eq "go-module で0で終わる" "$RC" 0
    expect_has "本文に Go の部品の脆弱性の URL を書く" "$(pr_body)" "- https://pkg.go.dev/vuln/GO-2026-4100"
    expect_eq "go-module の題名" "$(pr_title)" "fix: Go の部品 golang.org/x/net@0.40.0 の脆弱性を直す"
    expect_safe
fi

if want urls; then
    new_case urls
    make_final edit_app
    run_ship npm left@1.2.3 trigger "" "" '{"name":"left","version":"1.2.3","urgent":false,"alerts":[{"html_url":"https://github.com/o/r/security/dependabot/5x"}]}'
    expect_eq "このリポジトリの警告の URL が1つも無ければ0以外で終わる" "$RC" 1
    expect_no_push "警告の URL が無い"
    expect_safe

    new_case urls-go
    make_final edit_app
    run_ship go-stdlib 1.25.4 trigger "" "" '{"version":"1.25.4","osv":["GO-2026-4001 @dependabot"]}'
    expect_eq "Go の脆弱性の ID の形が違えば0以外で終わる" "$RC" 1
    expect_no_push "Go の脆弱性の ID の形が違う"
    expect_safe
fi

if want file-names; then
    new_case file-names
    make_final edit_names
    run_ship maven com.example:lib@2.0.0 trigger "" "" "$MAVEN_DETAIL"
    body=$(pr_body)
    expect_eq "ファイルの名前の場合で0で終わる" "$RC" 0
    expect_has "ふつうの名前はそのまま書く" "$body" "- \`docs/plain-name_1.md\`"
    expect_has "日本語と空白の名前はそのまま書く" "$body" "- \`docs/日本語 の名前.md\`"
    expect_not_has "バッククォートを含む名前を書かない" "$body" 'back`tick'
    expect_has "バッククォートを含む名前は決まった文に替える" "$body" "- (表示できない名前のファイル)"
    expect_safe
fi

if want usage; then
    new_case usage
    make_final edit_app
    run_ship npm left@1.2.3 other "" "" "$NPM_DETAIL"
    expect_eq "知らない reason で2で終わる" "$RC" 2
    run_ship npm left@1.2.3 red-check 77 "" "$NPM_DETAIL"
    expect_eq "red-check で checks が空なら2で終わる" "$RC" 2
    run_ship npm left@1.2.3 red-check 77 "[]" "$NPM_DETAIL"
    expect_eq "red-check で checks が空の配列なら2で終わる" "$RC" 2
    run_ship npm left@1.2.3 red-check "" '["lint"]' "$NPM_DETAIL"
    expect_eq "red-check で pr が空なら2で終わる" "$RC" 2
    run_ship npm left@1.2.3 red-check 77 "$(printf '["a\\nb"]')" "$NPM_DETAIL"
    expect_eq "検査の名前に改行があれば2で終わる" "$RC" 2
    run_ship other 1 trigger "" "" ""
    expect_eq "知らない種類で2で終わる" "$RC" 2
    run_ship npm "" trigger "" "" "$NPM_DETAIL"
    expect_eq "key が空なら2で終わる" "$RC" 2
    run_ship npm left@1.2.3 trigger "" "" "not json"
    expect_eq "detail が JSON でなければ2で終わる" "$RC" 2
    MAIN_ARG="" run_ship npm left@1.2.3 trigger "" "" "$NPM_DETAIL"
    expect_eq "CAF_MAIN_SHA が無ければ2で終わる" "$RC" 2
    other=$(git -C "$R" commit-tree "$(git -C "$R" rev-parse "HEAD^{tree}")" -m other)
    MAIN_ARG="$other" run_ship npm left@1.2.3 trigger "" "" "$NPM_DETAIL"
    expect_eq "CAF_MAIN_SHA が起点の祖先でなければ2で終わる" "$RC" 2
    SUM_ARG=abc run_ship npm left@1.2.3 trigger "" "" "$NPM_DETAIL"
    expect_eq "sha256 の形が違えば2で終わる" "$RC" 2
    OUT=$(cd "$WORK" && PATH="$BIN:$PATH" bash "$SCRIPT" npm left@1.2.3 trigger "" "" "" 2>/dev/null)
    expect_eq "引数が足りなければ2で終わる" "$?" 2
    expect_no_push "使い方が違う"
    expect_safe
fi

if [ "$RAN" -eq 0 ]; then
    echo "KP_TEST_CASE に合う場合がありません: $CASE" >&2
    exit 1
fi
if [ "$FAILED" -ne 0 ]; then
    echo "test-claude-auto-fix-ship: 失敗があります" >&2
    exit 1
fi
echo "test-claude-auto-fix-ship: すべて通りました(${RAN} の場合)"
