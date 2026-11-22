#!/usr/bin/env bash
# =====================================================================
# claude-auto-fix-guard.sh の自動テスト
#
# 一時のフォルダに Git のリポジトリを作り、base のコミットと、変更を足した head のコミットの
# 差でガードを呼ぶ。終了コードと、標準エラーに出た行と、標準出力が空であることを確かめる。
#
# ガードは check-escape-hatches.sh を呼ぶ。check-escape-hatches.sh は、差に関係なく、
# 今のフォルダの backend/build.gradle が gradle/quality.gradle だけを読み込むことを確かめるので、
# base のコミットにこの形の backend/build.gradle を置く。
#
# 環境変数 KP_TEST_CASE に場合の名前を入れると、その場合だけを流す(例: KP_TEST_CASE=plain)。
# =====================================================================
set -uo pipefail

SCRIPT="$(cd "$(dirname "$0")/.." && pwd)/claude-auto-fix-guard.sh"
CASE="${KP_TEST_CASE:-}"
WORK=$(mktemp -d) || exit 1
[ -n "$WORK" ] && [ -d "$WORK" ] || exit 1
trap 'rm -rf "$WORK"' EXIT
export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.com
export GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.com
FAILED=0
CASES_RUN=0

GO_DIR="backend/internal/sample"
JAVA_MAIN="backend/src/main/java/com/example/Sample.java"

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

# base のコミットを作り、BASE に SHA を入れる。今のフォルダはリポジトリの最上位になる
seed() {
    rm -rf "$WORK/repo"
    mkdir -p "$WORK/repo"
    cd "$WORK/repo" || exit 1
    git init -q .
    git config core.quotepath true

    mkdir -p backend/gradle backend/config "$GO_DIR" "$(dirname "$JAVA_MAIN")" \
        "frontend/src/some dir" .github/workflows doc
    echo "apply from: 'gradle/quality.gradle'" >backend/build.gradle
    echo "// quality gate" >backend/gradle/quality.gradle
    echo "<module/>" >backend/config/checkstyle.xml
    echo "export const x = 1;" >frontend/src/app.ts
    echo "export const y = 1;" >"frontend/src/some dir/日本語.ts"
    {
        echo 'package com.example;'
        echo 'class Sample {}'
    } >"$JAVA_MAIN"
    {
        echo 'package sample'
        echo ''
        echo 'func Add(a, b int) int {'
        echo '    return a + b'
        echo '}'
    } >"$GO_DIR/sample.go"
    {
        echo 'package sample'
        echo ''
        echo 'func TestAdd(t *testing.T) {'
        echo '    // 足し算を確かめる'
        echo '    got := Add(1, 2)'
        echo '    require.NotZero(t, got)'
        echo '    assert.Equal(t, 3, got)'
        echo '    if got != 3 {'
        echo '        t.Errorf("got %d", got)'
        echo '        t.Fatalf("got %d", got)'
        echo '    }'
        echo '}'
    } >"$GO_DIR/sample_test.go"
    echo '{"suppressions": []}' >.github/container-scan-suppressions.json
    echo "name: dummy" >.github/workflows/dummy.yaml
    echo "node_modules/" >.gitignore
    echo "readme" >README.md

    git add -A
    git commit -qm base
    BASE=$(git rev-parse HEAD)
}

# 今のフォルダの変更をすべてコミットし、HEAD_SHA に SHA を入れる
commit_head() {
    git add -A
    git commit -qm head --allow-empty
    HEAD_SHA=$(git rev-parse HEAD)
}

# 使い方: run_guard <種類>(- なら CAF_KIND を渡さない)
# RC に終了コード、OUT に標準出力、ERR に標準エラー、SUMMARY に GITHUB_STEP_SUMMARY の中身を入れる
run_guard() {
    : >"$WORK/summary"
    if [ "$1" = "-" ]; then
        OUT=$(env -u CAF_KIND GITHUB_STEP_SUMMARY="$WORK/summary" \
            bash "$SCRIPT" "$BASE" "$HEAD_SHA" 2>"$WORK/err")
    else
        OUT=$(CAF_KIND="$1" GITHUB_STEP_SUMMARY="$WORK/summary" \
            bash "$SCRIPT" "$BASE" "$HEAD_SHA" 2>"$WORK/err")
    fi
    RC=$?
    ERR=$(cat "$WORK/err")
    SUMMARY=$(cat "$WORK/summary")
}

# 使い方: expect_reject <説明> [標準エラーに含まれるはずの文字列...]
# 直前の run_guard の結果が、0以外で終わり、標準出力が空で、文字列をすべて標準エラーに含むことを確かめる
expect_reject() {
    local desc="$1" want
    shift
    if [ "$RC" -eq 0 ]; then
        ng "$desc(0で終わった。標準エラー: '$ERR')"
        return
    fi
    if [ -n "$OUT" ]; then
        ng "$desc(標準出力が空でない: '$OUT')"
        return
    fi
    for want in "$@"; do
        if ! printf '%s\n' "$ERR" | grep -qF -- "$want"; then
            ng "$desc(標準エラーに '$want' が無い: '$ERR')"
            return
        fi
    done
    ok "$desc"
}

# 使い方: expect_pass <説明>
expect_pass() {
    if [ "$RC" -eq 0 ] && [ -z "$OUT" ]; then
        ok "$1"
    else
        ng "$1(終了コード $RC、標準出力 '$OUT'、標準エラー '$ERR')"
    fi
}

# --- ゲートの設定のファイルの変更(要件3の1) ---
if selected gate_github; then
    seed
    echo "name: changed" >.github/workflows/dummy.yaml
    commit_head
    run_guard npm
    expect_reject ".github/ のファイルの変更で0以外になる" ".github/workflows/dummy.yaml"
fi

if selected gate_backend_config; then
    seed
    echo "<module name='x'/>" >backend/config/checkstyle.xml
    commit_head
    run_guard maven
    expect_reject "backend/config/ のファイルの変更で0以外になる" "backend/config/checkstyle.xml"
fi

# --- 検査を弱める変更(要件3の2) ---
if selected codeql_annotation; then
    seed
    echo "export const z = 1; // codeql[js/xss] 誤検知" >>frontend/src/app.ts
    commit_head
    run_guard npm
    expect_reject "足した codeql[ の行で0以外になる" "frontend/src/app.ts" "codeql[js/xss]"
fi

if selected suppress_warnings; then
    seed
    {
        echo 'package com.example;'
        echo '@SuppressWarnings("unchecked")'
        echo 'class Sample {}'
    } >"$JAVA_MAIN"
    commit_head
    run_guard maven
    expect_reject "足した @SuppressWarnings の行で0以外になる" "$JAVA_MAIN" '@SuppressWarnings("unchecked")'
fi

# 設計が挙げた、検査から外す注釈のほかの8つ。どれも足した行にあれば0以外になる
if selected other_annotations; then
    for token in 'lgtm[js/xss]' 'istanbul ignore next' 'v8 ignore next' 'c8 ignore next' \
        '@SuppressFBWarnings' 'NOPMD' 'CHECKSTYLE:OFF' 'nosemgrep'; do
        seed
        echo "export const z = 1; // $token" >>frontend/src/app.ts
        commit_head
        run_guard npm
        expect_reject "足した '$token' の行で0以外になる" "frontend/src/app.ts" "$token"
    done
fi

# 空白と日本語を含むパスでも、足した行を見落とさない
if selected annotation_unusual_path; then
    seed
    echo "export const z = 1; // nosemgrep" >>"frontend/src/some dir/日本語.ts"
    commit_head
    run_guard npm
    expect_reject "空白と日本語を含むパスのファイルに足した注釈で0以外になる" "nosemgrep"
fi

# .gitattributes で差分を出さない指定を足しても、足した行を見落とさない
if selected annotation_hidden_by_attributes; then
    seed
    echo "*.ts -diff" >.gitattributes
    echo "export const z = 1; // codeql[js/xss]" >>frontend/src/app.ts
    commit_head
    run_guard npm
    expect_reject ".gitattributes で差分を隠しても足した codeql[ の行で0以外になる" "codeql[js/xss]"
fi

# 注釈の言葉を消す変更は、検査を弱めない
if selected annotation_removed_ok; then
    seed
    echo "export const z = 1; // NOPMD" >>frontend/src/app.ts
    git add -A
    git commit -qm with-annotation
    BASE=$(git rev-parse HEAD)
    echo "export const x = 1;" >frontend/src/app.ts
    commit_head
    run_guard npm
    expect_pass "注釈の行を消す変更では0になる"
fi

if selected container_suppressions; then
    seed
    echo '{"suppressions": [{"id": "CVE-2026-0001"}]}' >.github/container-scan-suppressions.json
    commit_head
    run_guard container
    expect_reject ".github/container-scan-suppressions.json の変更で0以外になる" \
        "コンテナの脆弱性の抑制の変更" ".github/container-scan-suppressions.json"
fi

if selected ignore_files; then
    seed
    echo "dist/" >>.gitignore
    commit_head
    run_guard npm
    expect_reject "名前が ignore で終わるファイルの変更で0以外になる(.gitignore を変える)" \
        "名前が ignore で終わるファイルの変更" ".gitignore"

    seed
    echo "*.log" >backend/.dockerignore
    commit_head
    run_guard go-module
    expect_reject "名前が ignore で終わるファイルの変更で0以外になる(backend/.dockerignore を足す)" \
        "名前が ignore で終わるファイルの変更" "backend/.dockerignore"

    seed
    git rm -q .gitignore
    commit_head
    run_guard npm
    expect_reject "名前が ignore で終わるファイルの変更で0以外になる(.gitignore を消す)" \
        "名前が ignore で終わるファイルの変更" ".gitignore"
fi

# 名前の途中に ignore があるだけのファイルは、ふつうのファイルとして扱う
if selected ignore_in_middle_ok; then
    seed
    echo "export const ignored = 1;" >frontend/src/ignoreList.ts
    commit_head
    run_guard npm
    expect_pass "名前の途中に ignore があるファイルの変更では0になる"
fi

# _test.go のアサーションの行の削除。4つの形のどれも0以外になる
if selected go_assert_removed; then
    for token in 'require.NotZero' 'assert.Equal' 't.Errorf' 't.Fatalf'; do
        seed
        grep -vF "$token" "$GO_DIR/sample_test.go" >"$WORK/tmp.go"
        cp "$WORK/tmp.go" "$GO_DIR/sample_test.go"
        commit_head
        run_guard go-module
        expect_reject "_test.go の '$token' の行の削除で0以外になる" \
            "Go のテストのアサーションの削除" "$GO_DIR/sample_test.go" "$token"
    done
fi

# ファイルの名前を変える変更でも、元のファイルで消した行を見落とさない。
# git diff は既定で名前の変更を見分け、新しい名前だけを一覧に出すので、ガードはそれを止めて読む
if selected go_assert_removed_by_rename; then
    seed
    git mv "$GO_DIR/sample_test.go" "$GO_DIR/renamed_test.go"
    grep -vF 'require.NotZero' "$GO_DIR/renamed_test.go" >"$WORK/tmp.go"
    cp "$WORK/tmp.go" "$GO_DIR/renamed_test.go"
    commit_head
    run_guard go-module
    expect_reject "名前を変えた _test.go で require. の行を消すと0以外になる" \
        "Go のテストのアサーションの削除" "$GO_DIR/sample_test.go" "require.NotZero"

    seed
    git mv "$GO_DIR/sample_test.go" "$GO_DIR/sample_test.go.txt"
    commit_head
    run_guard go-module
    expect_reject "_test.go の名前を _test.go でない名前に変えると0以外になる" \
        "Go のテストのアサーションの削除" "$GO_DIR/sample_test.go"

    seed
    git mv .gitignore doc/gitignore.txt
    commit_head
    run_guard npm
    expect_reject "名前が ignore で終わるファイルの名前を変えると0以外になる" \
        "名前が ignore で終わるファイルの変更" ".gitignore"
fi

# _test.go でも、アサーションを足す変更と、アサーションでない行を消す変更は、検査を弱めない
if selected go_assert_ok; then
    seed
    sed -i 's#^}$#    require.Equal(t, 3, Add(1, 2))\n}#' "$GO_DIR/sample_test.go"
    commit_head
    run_guard go-module
    expect_pass "_test.go にアサーションの行を足す変更では0になる"

    seed
    grep -vF '// 足し算を確かめる' "$GO_DIR/sample_test.go" >"$WORK/tmp.go"
    cp "$WORK/tmp.go" "$GO_DIR/sample_test.go"
    commit_head
    run_guard go-module
    expect_pass "_test.go のアサーションでない行を消す変更では0になる"
fi

# _test.go でないファイルの require. の行の削除は、テストのアサーションの削除ではない
if selected go_non_test_ok; then
    seed
    echo '// require.X の説明' >>"$GO_DIR/sample.go"
    git add -A
    git commit -qm with-comment
    BASE=$(git rev-parse HEAD)
    grep -vF 'require.X' "$GO_DIR/sample.go" >"$WORK/tmp.go"
    cp "$WORK/tmp.go" "$GO_DIR/sample.go"
    commit_head
    run_guard go-module
    expect_pass "_test.go でないファイルの require. の行の削除では0になる"
fi

# check-escape-hatches.sh が見つける形も、ガードが0以外で終わる理由になる
if selected escape_hatch_detected; then
    seed
    sed -i 's#^    got := Add(1, 2)$#    t.Skip("あとで")\n    got := Add(1, 2)#' "$GO_DIR/sample_test.go"
    commit_head
    run_guard go-module
    expect_reject "check-escape-hatches.sh が見つける t.Skip の追加で0以外になる" "t.Skip"
fi

if selected plain; then
    seed
    echo "export const x = 2;" >frontend/src/app.ts
    sed -i 's#return a + b#return b + a#' "$GO_DIR/sample.go"
    echo "readme 2" >README.md
    commit_head
    run_guard npm
    expect_pass "ふつうのコードの変更で0になる"
    if [ -z "$ERR" ]; then
        ok "ふつうのコードの変更では標準エラーに何も出さない"
    else
        ng "ふつうのコードの変更では標準エラーに何も出さない(標準エラー: '$ERR')"
    fi
fi

# 種類が codeql のときは、見つけた行もファイルの名前も出さず、件数だけを出す(要件5)
if selected codeql_count_only; then
    seed
    echo "export const z = 1; // codeql[js/sql-injection] HIDDEN-LINE-MARK" >>frontend/src/app.ts
    echo "name: changed" >.github/workflows/dummy.yaml
    commit_head
    run_guard codeql
    expect_reject "種類が codeql のとき見つけた行を出さずに件数だけを出す(0以外で終わる)" "2 件"
    leaked=""
    for secret in HIDDEN-LINE-MARK "codeql[" frontend/src/app.ts dummy.yaml; do
        if printf '%s\n%s\n' "$ERR" "$SUMMARY" | grep -qF -- "$secret"; then
            leaked="$leaked $secret"
        fi
    done
    if [ -z "$leaked" ]; then
        ok "種類が codeql のとき見つけた行を出さずに件数だけを出す(行もパスも標準エラーと GITHUB_STEP_SUMMARY に出ない)"
    else
        ng "種類が codeql のとき見つけた行を出さずに件数だけを出す(出てしまったもの:$leaked)"
    fi
fi

# 種類が codeql でないときも、check-escape-hatches.sh に GITHUB_STEP_SUMMARY を書かせない
if selected summary_untouched; then
    seed
    echo "name: changed" >.github/workflows/dummy.yaml
    commit_head
    run_guard npm
    if [ "$RC" -ne 0 ] && [ -z "$SUMMARY" ]; then
        ok "見つけた行を GITHUB_STEP_SUMMARY に書かない"
    else
        ng "見つけた行を GITHUB_STEP_SUMMARY に書かない(終了コード $RC、SUMMARY '$SUMMARY')"
    fi
fi

# --- 呼び出し方の誤り ---
if selected bad_usage; then
    seed
    echo "export const x = 2;" >frontend/src/app.ts
    commit_head
    run_guard -
    expect_reject "CAF_KIND が無ければ調べずに失敗する" "CAF_KIND"
    run_guard unknown
    expect_reject "知らない種類では調べずに失敗する" "unknown"

    OUT=$(CAF_KIND=npm bash "$SCRIPT" "$BASE" 2>"$WORK/err")
    RC=$?
    ERR=$(cat "$WORK/err")
    expect_reject "引数が足りなければ失敗する"

    OUT=$(CAF_KIND=npm bash "$SCRIPT" "$BASE" 0123456789abcdef0123456789abcdef01234567 2>"$WORK/err")
    RC=$?
    ERR=$(cat "$WORK/err")
    expect_reject "コミットを読めなければ失敗する"
fi

if [ "$CASES_RUN" -eq 0 ]; then
    echo "NG: KP_TEST_CASE='$CASE' に当たる場合がありません"
    exit 1
fi
if [ "$FAILED" -ne 0 ]; then
    echo "claude-auto-fix-guard.sh のテストに失敗した場合があります"
    exit 1
fi
echo "claude-auto-fix-guard.sh のテストはすべて通りました"
