#!/usr/bin/env bash
# =====================================================================
# detect-codeql-languages.sh の自動テスト(codeql.yaml の detect-codeql-languages から実行)
#
# 一時のフォルダに git のリポジトリを作り、ファイルを置いて git に追跡させてから、
# 本物の言語の対応表(.github/codeql/languages.tsv)でスクリプトを動かす。
#   0 = 成功 / 1 = ビルドのしかたを決めていない言語がある / 2 = それ以外の失敗
#
# 外部への問い合わせを行わないため、実行にネットワークを必要としない。
# 環境変数 KP_TEST_CASE に場合の名前を入れると、その場合だけを流す。
# =====================================================================
set -uo pipefail

SCRIPT="$(cd "$(dirname "$0")/.." && pwd)/detect-codeql-languages.sh"
REAL_TABLE="$(cd "$(dirname "$0")/../.." && pwd)/codeql/languages.tsv"
WORK=$(mktemp -d) || exit 1
[ -n "$WORK" ] && [ -d "$WORK" ] || exit 1
trap 'rm -rf "$WORK"' EXIT
FAILED=0

JAVA_BUILD='cd backend && ./gradlew --no-daemon testClasses'
ACTIONS_ROW='{"language":"actions","build-mode":"none","build-command":""}'
JAVA_ROW="{\"language\":\"java-kotlin\",\"build-mode\":\"manual\",\"build-command\":\"${JAVA_BUILD}\"}"
JS_ROW='{"language":"javascript-typescript","build-mode":"none","build-command":""}'
PYTHON_ROW='{"language":"python","build-mode":"none","build-command":""}'
GO_BUILD='cd backend && go build ./...'
GO_ROW="{\"language\":\"go\",\"build-mode\":\"manual\",\"build-command\":\"${GO_BUILD}\"}"

REPO_NO=0
# 新しい空の git のリポジトリを作り、REPO に入れる
new_repo() {
    REPO_NO=$((REPO_NO + 1))
    REPO="$WORK/repo-$REPO_NO"
    mkdir -p "$REPO"
    git -C "$REPO" init -q
}

# ファイルを置き、git に追跡させる
add_file() {
    mkdir -p "$(dirname "$REPO/$1")"
    printf 'x\n' >"$REPO/$1"
    git -C "$REPO" add -- "$1"
}

# REPO で、本物の対応表を渡してスクリプトを動かす。
# 標準出力を $WORK/out、標準エラーを $WORK/err、GITHUB_OUTPUT を $WORK/github_output に残す
run_real() {
    : >"$WORK/github_output"
    (cd "$REPO" && GITHUB_OUTPUT="$WORK/github_output" bash "$SCRIPT" "$REAL_TABLE") >"$WORK/out" 2>"$WORK/err"
    RC=$?
}

fail() {
    echo "FAIL: $1"
    FAILED=1
}

check_rc() {
    if [ "$RC" -eq "$1" ]; then
        echo "PASS: $2"
    else
        fail "$2 (終了コード: 期待 $1 / 実際 $RC)"
        sed 's/^/    stderr: /' "$WORK/err"
    fi
}

check_out() {
    local actual
    actual=$(cat "$WORK/out")
    if [ "$actual" = "$1" ]; then
        echo "PASS: $2"
    else
        fail "$2"
        echo "    期待: $1"
        echo "    実際: $actual"
    fi
}

check_out_lines() {
    local n
    n=$(wc -l <"$WORK/out" | tr -d ' ')
    if [ "$n" = "$1" ]; then
        echo "PASS: $2"
    else
        fail "$2 (行の数: 期待 $1 / 実際 $n)"
    fi
}

check_err() {
    if grep -qF -- "$1" "$WORK/err"; then
        echo "PASS: $2"
    else
        fail "$2 (標準エラーに「$1」がありません)"
        sed 's/^/    stderr: /' "$WORK/err"
    fi
}

check_err_lacks() {
    if grep -qF -- "$1" "$WORK/err"; then
        fail "$2 (標準エラーに「$1」があります)"
    else
        echo "PASS: $2"
    fi
}

check_github_output() {
    local actual
    actual=$(cat "$WORK/github_output")
    if [ "$actual" = "$1" ]; then
        echo "PASS: $2"
    else
        fail "$2"
        echo "    期待: $1"
        echo "    実際: $actual"
    fi
}

CASE="${KP_TEST_CASE:-}"
RAN=0
want() {
    if [ -z "$CASE" ] || [ "$CASE" = "$1" ]; then
        RAN=$((RAN + 1))
        echo "--- $1 ---"
        return 0
    fi
    return 1
}

if want three-languages; then
    new_repo
    add_file backend/src/main/java/com/example/App.java
    add_file frontend/src/main.ts
    add_file .github/workflows/ci.yaml
    run_real
    check_rc 0 "Java と TypeScript とワークフローのファイルから3つの言語を出す: 終了コード0で終わる"
    check_out "[${ACTIONS_ROW},${JAVA_ROW},${JS_ROW}]" "Java と TypeScript とワークフローのファイルから3つの言語を出す: 言語の名前の順の JSON になる"
    check_out_lines 1 "Java と TypeScript とワークフローのファイルから3つの言語を出す: JSON を1行で出す"
fi

if want test-code-only; then
    new_repo
    add_file backend/src/test/java/com/example/AppTest.java
    add_file frontend/src/features/x/__tests__/x.test.tsx
    run_real
    check_rc 0 "テストのコードの置き場所にだけある言語のファイルも数える: 終了コード0で終わる"
    check_out "[${JAVA_ROW},${JS_ROW}]" "テストのコードの置き場所にだけある言語のファイルも数える: Java と TypeScript を出す"
fi

if want python-none; then
    new_repo
    add_file backend/src/main/java/com/example/App.java
    add_file tools/report.py
    run_real
    check_rc 0 ".py のファイルを足すと python を none で出す: 終了コード0で終わる"
    check_out "[${JAVA_ROW},${PYTHON_ROW}]" ".py のファイルを足すと python を none で出す: python の組が none で出る"
fi

if want go-manual; then
    new_repo
    add_file backend/src/main/java/com/example/App.java
    add_file backend/cmd/api/main.go
    add_file backend/internal/server/server.go
    run_real
    check_rc 0 ".go のファイルを含む変更で go の行を manual で選ぶ: 終了コード0で終わる"
    check_out "[${GO_ROW},${JAVA_ROW}]" ".go のファイルを含む変更で go の行を manual で選ぶ: go の組が manual と go build の命令で出る"
    check_github_output "matrix=[${GO_ROW},${JAVA_ROW}]" ".go のファイルを含む変更で go の行を manual で選ぶ: GITHUB_OUTPUT に matrix を書く"
fi

# ビルドのしかたを決めていない言語の例には、このリポジトリに無い Rust を使う
if want rust-undecided; then
    new_repo
    add_file backend/src/main/java/com/example/App.java
    add_file tools/src/main.rs
    add_file tools/src/lib.rs
    run_real
    check_rc 1 ".rs のファイルがあると、言語とファイルの例を1つ出して終了コード1で終わる: 終了コード1で終わる"
    check_err "CodeQL の言語 rust のファイルがあります" ".rs のファイルがあると、言語とファイルの例を1つ出して終了コード1で終わる: 言語の名前が出る"
    check_err "ファイルの例: tools/src/lib.rs" ".rs のファイルがあると、言語とファイルの例を1つ出して終了コード1で終わる: ファイルの例が出る"
    check_err_lacks "tools/src/main.rs" ".rs のファイルがあると、言語とファイルの例を1つ出して終了コード1で終わる: ファイルの例は1つだけ出る"
    check_err_lacks "java-kotlin" ".rs のファイルがあると、言語とファイルの例を1つ出して終了コード1で終わる: ビルドのしかたがある言語は報告しない"
    check_out "" ".rs のファイルがあると、言語とファイルの例を1つ出して終了コード1で終わる: 標準出力に JSON を出さない"
    check_github_output "" ".rs のファイルがあると、言語とファイルの例を1つ出して終了コード1で終わる: GITHUB_OUTPUT に matrix を書かない"
fi

if want github-output; then
    new_repo
    add_file backend/src/main/java/com/example/App.java
    add_file frontend/src/main.ts
    add_file .github/workflows/ci.yaml
    run_real
    check_rc 0 "GITHUB_OUTPUT に matrix を書く: 終了コード0で終わる"
    check_github_output "matrix=[${ACTIONS_ROW},${JAVA_ROW},${JS_ROW}]" "GITHUB_OUTPUT に matrix を書く: 標準出力と同じ JSON を1行で書く"

    (cd "$REPO" && env -u GITHUB_OUTPUT bash "$SCRIPT" "$REAL_TABLE") >"$WORK/out" 2>"$WORK/err"
    RC=$?
    check_rc 0 "GITHUB_OUTPUT が無くても終了コード0で終わる"
    check_out "[${ACTIONS_ROW},${JAVA_ROW},${JS_ROW}]" "GITHUB_OUTPUT が無くても標準出力に JSON を出す"
fi

if [ "$RAN" -eq 0 ]; then
    echo "FAIL: KP_TEST_CASE=${CASE} に当たる場合がありません"
    FAILED=1
fi

if [ "$FAILED" -eq 0 ]; then
    echo "すべてのテストがPASSしました。"
else
    echo "失敗したテストがあります。"
fi
exit "$FAILED"
