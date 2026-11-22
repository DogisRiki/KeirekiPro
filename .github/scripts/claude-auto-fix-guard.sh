#!/usr/bin/env bash
# =====================================================================
# Claude の変更のガード(claude-auto-fix-target.yaml の verify ジョブと ship ジョブから実行)
#
# 2つのコミットの差を調べ、次のどれかがあれば0以外で終わる。仕組みは、0以外で終わった
# 変更を PR にせず、その対象を直せなかったものとして扱う。
#   1. check-escape-hatches.sh が、PR_BODY="" と OWNER_APPROVED=false で0以外になる。
#      ゲートの設定のファイルの変更と、今の escape-hatch が見つける形は、この呼び出しで見つける
#   2. 足した行に、検査から外す注釈がある
#      (codeql[ lgtm istanbul ignore v8 ignore c8 ignore @SuppressWarnings @SuppressFBWarnings
#       NOPMD CHECKSTYLE:OFF nosemgrep)
#   3. 名前が ignore で終わるファイルを足したか、変えたか、消した。
#      .github/container-scan-suppressions.json を変えた
#   4. _test.go のファイルで、assert. require. t.Error t.Fatal を含む行を消した
#
# 見つけた行は標準エラーに出す。種類が codeql のときは、CodeQL の警告の中身が実行の記録に
# 残らないように、見つけた行もファイルの名前も出さず、件数だけを出す。標準出力には何も出さない。
# check-escape-hatches.sh には GITHUB_STEP_SUMMARY を書かせない。
#
# 差は、check-escape-hatches.sh と同じく、2つのコミットの共通の祖先と head で比べる。
# 変えたファイルの一覧は NUL で区切って受け、空白や日本語を含むパスもそのまま扱う。
# .gitattributes で差分を出さない指定があっても足した行を読めるように、差分は --text で読む。
# 名前の変更は --no-renames で見分けない。git diff は既定で名前の変更を見分けて新しい名前だけを
# 一覧に出すので、見分けると、元のファイル(_test.go や名前が ignore で終わるファイル)で消した行と
# 元のファイルの名前を見落とすためである。名前を変えただけでも元のファイルを消した変更として扱う。
#
# 環境変数:
#   CAF_KIND : 対象の種類(npm maven go-stdlib go-module codeql container dependabot)。必須
#
# 今のフォルダは、調べるリポジトリの最上位にする。check-escape-hatches.sh が、今のフォルダの
# backend/build.gradle も確かめるためである。
#
# テスト: .github/scripts/tests/test-claude-auto-fix-guard.sh
# 使い方: claude-auto-fix-guard.sh <base> <head>
# =====================================================================
set -euo pipefail

fail() {
    echo "ガード: $1" >&2
    exit 1
}

[ "$#" -eq 2 ] || fail "使い方: claude-auto-fix-guard.sh <base> <head>"
BASE_SHA="$1"
HEAD_SHA="$2"
KIND="${CAF_KIND:-}"
case "$KIND" in
"") fail "環境変数 CAF_KIND に対象の種類がありません" ;;
npm | maven | go-stdlib | go-module | codeql | container | dependabot) ;;
*) fail "知らない種類です: $KIND" ;;
esac

ESCAPE="$(cd "$(dirname "$0")" && pwd)/check-escape-hatches.sh"
[ -f "$ESCAPE" ] || fail "check-escape-hatches.sh がありません"

MERGE_BASE=$(git merge-base "$BASE_SHA" "$HEAD_SHA") || fail "2つのコミットの共通の祖先を読めません"

# 変えたファイルの一覧。末尾の番兵で、git diff が最後まで成功したことを確かめる。
# 番兵が無いまま進むと、一覧が空のまま「見つからない」で通ってしまう
CHANGED_FILES=()
mapfile -d '' -t CHANGED_FILES < <(
    git diff -z --name-only --no-renames "$MERGE_BASE" "$HEAD_SHA" && printf '__GIT_DIFF_OK__\0'
)
if [ "${#CHANGED_FILES[@]}" -eq 0 ] || [ "${CHANGED_FILES[-1]}" != "__GIT_DIFF_OK__" ]; then
    fail "変えたファイルの一覧を読めません"
fi
unset 'CHANGED_FILES[-1]'

FINDINGS=()
# 使い方: add_finding <見つけたものの名前> <行>
add_finding() {
    FINDINGS+=("[$1] $2")
}

# 使い方: diff_lines <+ か -> <ファイル>
# そのファイルの足した行か消した行を、1行に1つずつ出す
diff_lines() {
    local out
    out=$(git diff --text --no-ext-diff --no-textconv --no-renames --unified=0 \
        "$MERGE_BASE" "$HEAD_SHA" -- ":(literal)$2") || fail "差分を読めません"
    printf '%s\n' "$out" | SIGN="$1" awk '
        BEGIN { sign = ENVIRON["SIGN"] }
        /^@@/ { inhunk = 1; next }
        /^diff --git / { inhunk = 0; next }
        inhunk && substr($0, 1, 1) == sign { print substr($0, 2) }
    '
}

ANNOTATIONS=(
    'codeql['
    'lgtm'
    'istanbul ignore'
    'v8 ignore'
    'c8 ignore'
    '@SuppressWarnings'
    '@SuppressFBWarnings'
    'NOPMD'
    'CHECKSTYLE:OFF'
    'nosemgrep'
)
GO_ASSERTIONS=(
    'assert.'
    'require.'
    't.Error'
    't.Fatal'
)

grep_args() {
    local p
    for p in "$@"; do
        printf '%s\0' -e "$p"
    done
}
mapfile -d '' -t ANNOTATION_ARGS < <(grep_args "${ANNOTATIONS[@]}")
mapfile -d '' -t GO_ASSERTION_ARGS < <(grep_args "${GO_ASSERTIONS[@]}")

# 使い方: add_matches <見つけたものの名前> <ファイル> <行の一覧>
add_matches() {
    local line
    while IFS= read -r line; do
        if [ -n "$line" ]; then
            add_finding "$1" "$2: $line"
        fi
    done <<<"$3"
}

# 差分はプロセス置換で読まない。プロセス置換の中の失敗は set -e に拾われず、
# 差分を読めないまま「見つからない」で通ってしまうためである
for f in ${CHANGED_FILES[@]+"${CHANGED_FILES[@]}"}; do
    # --- 2. 足した行の、検査から外す注釈 ---
    added=$(diff_lines '+' "$f")
    add_matches "検査から外す注釈の追加" "$f" \
        "$(printf '%s\n' "$added" | grep -F "${ANNOTATION_ARGS[@]}" || true)"

    # --- 3. 名前が ignore で終わるファイルと、コンテナの脆弱性の抑制 ---
    case "${f##*/}" in
    *ignore) add_finding "名前が ignore で終わるファイルの変更" "$f" ;;
    esac
    if [ "$f" = ".github/container-scan-suppressions.json" ]; then
        add_finding "コンテナの脆弱性の抑制の変更" "$f"
    fi

    # --- 4. Go のテストのアサーションの削除 ---
    case "$f" in
    *_test.go)
        removed=$(diff_lines '-' "$f")
        add_matches "Go のテストのアサーションの削除" "$f" \
            "$(printf '%s\n' "$removed" | grep -F "${GO_ASSERTION_ARGS[@]}" || true)"
        ;;
    esac
done

# --- 1. check-escape-hatches.sh ---
escape_rc=0
escape_out=$(PR_BODY="" OWNER_APPROVED=false GITHUB_STEP_SUMMARY=/dev/null \
    bash "$ESCAPE" "$BASE_SHA" "$HEAD_SHA" 2>&1) || escape_rc=$?
escape_count=0
if [ "$escape_rc" -ne 0 ]; then
    escape_count=$(printf '%s\n' "$escape_out" | grep -c '^::error::' || true)
    [ "$escape_count" -gt 0 ] || escape_count=1
fi

total=$((escape_count + ${#FINDINGS[@]}))
if [ "$total" -eq 0 ]; then
    exit 0
fi

if [ "$KIND" = "codeql" ]; then
    echo "ガード: ${total} 件を見つけました。種類が codeql のため、見つけた行とファイルの名前は出しません。" >&2
    exit 1
fi

{
    if [ "$escape_rc" -ne 0 ]; then
        echo "check-escape-hatches.sh が ${escape_count} 件を見つけました。"
        printf '%s\n' "$escape_out"
    fi
    for item in ${FINDINGS[@]+"${FINDINGS[@]}"}; do
        echo "$item"
    done
    echo "ガード: ${total} 件を見つけました。"
} >&2
exit 1
