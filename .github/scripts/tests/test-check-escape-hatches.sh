#!/usr/bin/env bash
# =====================================================================
# check-escape-hatches.sh の自動テスト(guardrails CI から実行)
#
# 一時gitリポジトリにbase/headを作り、終了コードとSummaryの文言を検証する。
#   0 = 緑(通過) / 1 = 赤
#
# 一時リポジトリには core.quotepath=true を明示的に設定する。これはGitの既定値で
# あり、GitHub Actions のランナーもこの状態で動く。開発機に core.quotepath=false が
# 設定されていると非ASCIIのパスが手元でだけ正しく扱われるため、テストが環境に
# 依存しないよう固定する。
#
# 各ケースは「seed → 変更を加える関数 → run_check」の3行で書く。変更を加える関数を
# 引数で渡す形にしないのは、静的解析が引数位置の関数名を参照と数えず、
# 未使用の関数として報告してしまうため。コマンド位置で呼べば抑制指示が要らない。
# =====================================================================
set -uo pipefail

SCRIPT="$(cd "$(dirname "$0")/.." && pwd)/check-escape-hatches.sh"
WORK=$(mktemp -d) || exit 1
[ -n "$WORK" ] && [ -d "$WORK" ] || exit 1
trap 'rm -rf "$WORK"' EXIT
export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.com
export GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.com
FAILED=0

JAVA_TEST_DIR="backend/src/test/java/com/example/keirekipro/unit"
GO_DIR="backend/internal/sample"
REAL_GIT=$(command -v git)

# git diff --name-only だけを失敗させるシム。変更ファイルの一覧が取れないときに
# 「0件 = 検知なし = 緑」で素通りしないこと(fail-closed)を検証する。
mkdir -p "$WORK/bin"
cat >"$WORK/bin/git" <<STUB
#!/usr/bin/env bash
for a in "\$@"; do
    [ "\$a" = "--name-only" ] && exit 128
done
exec "$REAL_GIT" "\$@"
STUB
chmod +x "$WORK/bin/git"

seed() {
    rm -rf "$WORK/repo"
    mkdir -p "$WORK/repo"
    cd "$WORK/repo" || exit 1
    git init -q .
    # ランナーと同じ既定にそろえる(非ASCIIパスの引用が有効な状態)
    git config core.quotepath true

    mkdir -p backend/gradle "frontend/src/some dir" "$JAVA_TEST_DIR" .github/workflows doc
    echo "apply from: 'gradle/quality.gradle'" >backend/build.gradle
    echo "// quality gate" >backend/gradle/quality.gradle

    {
        echo 'it("works", () => {'
        echo '  expect(1).toBe(1);'
        echo '});'
    } >frontend/src/plain.test.ts
    cp frontend/src/plain.test.ts "frontend/src/some dir/spaced.test.ts"
    cp frontend/src/plain.test.ts frontend/src/日本語.test.ts
    echo "export const x = 1;" >frontend/src/app.ts
    # 既にハッチを含むファイル(純リネームの期待値を固定するため)
    {
        echo '// @ts-expect-error 既知の型不一致'
        echo 'export const y: number = "1";'
    } >frontend/src/hatched.ts
    # 監視対象パスの外(パスの絞り込み自体を検証するため)
    cp frontend/src/plain.test.ts doc/sample.test.ts

    {
        echo 'class SampleTest {'
        echo '    void works() { assertTrue(true); }'
        echo '}'
    } >"$JAVA_TEST_DIR/SampleTest.java"

    echo "name: dummy" >.github/workflows/dummy.yaml
    echo "readme" >README.md

    # Go 版のコードとテスト
    mkdir -p "$GO_DIR"
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
        echo 'import "testing"'
        echo ''
        echo 'func TestAdd(t *testing.T) {'
        echo '    if Add(1, 2) != 3 {'
        echo '        t.Fatal("wrong")'
        echo '    }'
        echo '}'
    } >"$GO_DIR/sample_test.go"

    # 一部の欄や行だけが品質チェックを決めるファイル(#826)
    {
        echo '{'
        echo '    "name": "sample",'
        echo '    "packageManager": "pnpm@11.10.0",'
        echo '    "scripts": { "lint": "eslint ./src", "format": "prettier --check ./src" },'
        echo '    "dependencies": { "react": "^19.0.0" },'
        echo '    "devDependencies": { "eslint": "^9.39.4" }'
        echo '}'
    } >frontend/package.json
    mkdir -p docker/terraform
    {
        echo 'FROM ghcr.io/terraform-linters/tflint:v0.66.0@sha256:65b9944a9274c4989492c1d79998c2801664bf8a55fddb4bd3a9e6d73a006ddc AS tflint'
        echo ''
        echo 'FROM hashicorp/terraform:1.17.1@sha256:a5d5a5a892c98f60fcbfa81eac2a40fc19e7b3fa7719bccae10ff6111d22524a'
        echo 'COPY --from=tflint /usr/local/bin/tflint /usr/local/bin/tflint'
        echo 'RUN pip3 install -r /tmp/requirements.txt'
    } >docker/terraform/Dockerfile

    git add -A && git commit -qm base
    BASE=$(git rev-parse HEAD)
    PR_BODY_VAL=""
    OWNER_VAL="false"
}

# 使い方: seed し、変更を加えてから run_check <期待exit> <説明>
run_check() {
    local want="$1" name="$2" got
    git add -A && git commit -qm head --allow-empty
    : >"$WORK/summary.md"
    PR_BODY="$PR_BODY_VAL" OWNER_APPROVED="$OWNER_VAL" \
        GITHUB_STEP_SUMMARY="$WORK/summary.md" \
        bash "$SCRIPT" "$BASE" "$(git rev-parse HEAD)" >/dev/null 2>&1
    got=$?
    if [ "$got" -eq "$want" ]; then
        echo "PASS: $name"
    else
        echo "FAIL: $name (expected exit $want, got $got)"
        FAILED=1
    fi
}

# 変更ファイルの一覧が取れない状況を作って検査を走らせる
run_check_broken_git() {
    local want="$1" name="$2" got
    git add -A && git commit -qm head --allow-empty
    : >"$WORK/summary.md"
    PATH="$WORK/bin:$PATH" PR_BODY="$PR_BODY_VAL" OWNER_APPROVED="$OWNER_VAL" \
        GITHUB_STEP_SUMMARY="$WORK/summary.md" \
        bash "$SCRIPT" "$BASE" "$(git rev-parse HEAD)" >/dev/null 2>&1
    got=$?
    if [ "$got" -eq "$want" ]; then
        echo "PASS: $name"
    else
        echo "FAIL: $name (expected exit $want, got $got)"
        FAILED=1
    fi
}

check_summary() {
    if grep -qF "$1" "$WORK/summary.md"; then
        echo "PASS: $2"
    else
        echo "FAIL: $2 (Summaryに '$1' が現れない)"
        FAILED=1
    fi
}

# --- 変更を加える関数 -----------------------------------------------------------
touch_unrelated() { echo "note" >>README.md; }

skip_plain() { sed -i 's/^it(/it.skip(/' frontend/src/plain.test.ts; }
skip_spaced() { sed -i 's/^it(/it.skip(/' "frontend/src/some dir/spaced.test.ts"; }
skip_japanese() { sed -i 's/^it(/it.skip(/' frontend/src/日本語.test.ts; }
add_xit() { echo 'xit("x", () => {});' >>frontend/src/plain.test.ts; }

add_disabled() { sed -i 's/^class /@Disabled\nclass /' "$JAVA_TEST_DIR/SampleTest.java"; }
add_ts_ignore() { sed -i '1i // @ts-ignore' frontend/src/app.ts; }
add_eslint_disable() { sed -i '1i // eslint-disable-next-line no-console' frontend/src/app.ts; }

drop_ts_assert() { sed -i '/expect(/d' frontend/src/plain.test.ts; }
drop_java_assert() { sed -i '/assertTrue/d' "$JAVA_TEST_DIR/SampleTest.java"; }
justify() { PR_BODY_VAL="Test-Change-Justification: 仕様変更のため"; }

touch_gate_file() { echo "# changed" >>.github/workflows/dummy.yaml; }
approve() { OWNER_VAL="true"; }

add_second_apply() { echo "apply from: 'gradle/extra.gradle'" >>backend/build.gradle; }
drop_quality_apply() { echo "// nothing" >backend/build.gradle; }
add_apply_elsewhere() { echo "apply from: 'other.gradle'" >backend/gradle/quality.gradle; }
add_violation_rules() { echo "violationRules { }" >>backend/build.gradle; }

rename_only() { git mv frontend/src/plain.test.ts frontend/src/renamed.test.ts; }
rename_hatched() { git mv frontend/src/hatched.ts frontend/src/moved.ts; }
delete_test_file() { git rm -q frontend/src/plain.test.ts; }

skip_outside_scope() { sed -i 's/^it(/it.skip(/' doc/sample.test.ts; }
add_plusplus_disable() { echo '++counter; // eslint-disable-line no-plusplus' >>frontend/src/app.ts; }

# Go 版のテストの飛ばしと検査の外し
go_skip() { sed -i 's/^func TestAdd(t \*testing.T) {/&\n    t.Skip("later")/' "$GO_DIR/sample_test.go"; }
go_skip_now() { sed -i 's/^func TestAdd(t \*testing.T) {/&\n    t.SkipNow()/' "$GO_DIR/sample_test.go"; }
go_skipf() { sed -i 's/^func TestAdd(t \*testing.T) {/&\n    t.Skipf("later %d", 1)/' "$GO_DIR/sample_test.go"; }
# テストの外の助けの関数で、t 以外の名前の値から飛ばす
go_skip_helper() { printf 'package sample\n\nimport "testing"\n\nfunc needDocker(tb testing.TB) {\n    tb.Skip("no docker")\n}\n' >"$GO_DIR/helper.go"; }
go_nolint() { sed -i 's/^    return a + b$/    return a + b \/\/nolint:gosec/' "$GO_DIR/sample.go"; }
go_nolint_spaced() { sed -i '1i // nolint' "$GO_DIR/sample.go"; }
go_coverage_ignore() { sed -i 's/^func Add(a, b int) int {$/& \/\/ coverage-ignore/' "$GO_DIR/sample.go"; }
go_plain_change() { sed -i 's/^    return a + b$/    sum := a + b\n    return sum/' "$GO_DIR/sample.go"; }
# backend の外の Go のファイルは見ない
go_skip_outside() { mkdir -p tools && printf 'package tools\n\nfunc f(t T) { t.Skip() }\n' >tools/x_test.go; }

# Go 版の品質チェックとコード生成の設定(所有者の承認があれば通るゲート隣接ファイル)
go_testcoverage_in_base() {
    printf 'threshold:\n  total: 93\n' >backend/.testcoverage.yml
    git add -A && git commit -qm base2
    BASE=$(git rev-parse HEAD)
}
go_testcoverage_exclude() { printf 'exclude:\n  paths:\n    - ^internal/sample\n' >>backend/.testcoverage.yml; }
go_testcoverage_new() { printf 'threshold:\n  total: 93\n' >backend/.testcoverage.yml; }
go_makefile() { printf 'check:\n\tgo test ./...\n' >backend/Makefile; }
go_golangci() { printf 'version: "2"\n' >backend/.golangci.yml; }
go_gremlins() { printf 'unleash:\n  threshold:\n    efficacy: 80\n' >backend/.gremlins.yaml; }
go_oapi() { mkdir -p backend/api && printf 'package: gen\n' >backend/api/oapi-codegen.yaml; }
go_sqlc() { printf 'version: "2"\n' >backend/sqlc.yaml; }
go_nested_makefile() { mkdir -p backend/tools && printf 'all:\n' >backend/tools/Makefile; }

# 品質チェックが何を調べるかを決めるファイル(#826)
# 使い方: touch_path <パス>。ファイルが無ければフォルダごと作る
touch_path() { mkdir -p "$(dirname "$1")" && echo "# changed" >>"$1"; }

# frontend/package.json の欄を書き換える。jq でなく sed で書くのは、テストが検査と同じ道具に
# 頼らないようにするため
pkg_bump_versions() { sed -i -e 's/"\^19.0.0"/"^19.1.0"/' -e 's/"\^9.39.4"/"^9.40.0"/' frontend/package.json; }
pkg_bump_package_manager() { sed -i 's/pnpm@11.10.0/pnpm@11.11.0/' frontend/package.json; }
pkg_add_dependency() { sed -i 's/"react": "\^19.0.0"/"react": "^19.0.0", "zod": "^4.0.0"/' frontend/package.json; }
pkg_change_script() { sed -i 's/"eslint .\/src"/"echo ok"/' frontend/package.json; }
pkg_add_tool_config() { sed -i 's/"name": "sample",/"name": "sample", "prettier": { "printWidth": 400 },/' frontend/package.json; }
pkg_break_json() { echo '{' >frontend/package.json; }
pkg_delete() { git rm -q frontend/package.json; }

docker_bump_tag() { sed -i 's/tflint:v0.66.0/tflint:v0.67.0/' docker/terraform/Dockerfile; }
docker_bump_digest() { sed -i 's/@sha256:a5d5a5a8[0-9a-f]*/@sha256:0000000000000000000000000000000000000000000000000000000000000000/' docker/terraform/Dockerfile; }
docker_add_platform() { sed -i 's/^FROM hashicorp\/terraform:1.17.1/FROM --platform=linux\/amd64 hashicorp\/terraform:1.17.2/' docker/terraform/Dockerfile; }
docker_change_image() { sed -i 's/hashicorp\/terraform:/example\/terraform:/' docker/terraform/Dockerfile; }
docker_change_run() { echo 'RUN ln -sf /bin/true /usr/local/bin/tflint' >>docker/terraform/Dockerfile; }

# 検査から一部を外す注釈と、依存を別の部品に差し替える書き方(#856)
# 使い方: add_line <パス> <行>。ファイルが無ければフォルダごと作る
add_line() { mkdir -p "$(dirname "$2")" && echo "$1" >>"$2"; }
# いまの作業の状態を base にする。base にすでにある書き方を、消すか変える変更を試すため
commit_as_base() {
    git add -A && git commit -qm base2
    BASE=$(git rev-parse HEAD)
}
# frontend/package.json の react の版の欄を、引数の文字に書き換える
pkg_set_react() { sed -i "s#\"react\": \"\\^19.0.0\"#\"react\": \"$1\"#" frontend/package.json; }
pkg_set_eslint() { sed -i "s#\"eslint\": \"\\^9.39.4\"#\"eslint\": \"$1\"#" frontend/package.json; }
pkg_add_alias_dependency() { sed -i 's#"react": "\^19.0.0"#"react": "^19.0.0", "zod": "npm:zod-fork@^4.0.0"#' frontend/package.json; }
# base にある npm: の書き方の、版か名前を書き換える
pkg_alias_version_up() { sed -i 's#npm:preact-compat@3.0.0#npm:preact-compat@3.1.0#' frontend/package.json; }
pkg_alias_rename() { sed -i 's#npm:preact-compat@3.0.0#npm:other-compat@3.0.0#' frontend/package.json; }
pkg_alias_back_to_plain() { sed -i 's#"npm:preact-compat@3.0.0"#"^19.0.0"#' frontend/package.json; }
pkg_url_version_up() { sed -i 's#react-19.0.0.tgz#react-19.1.0.tgz#' frontend/package.json; }

echo "--- 対象外の変更 ---"
seed
touch_unrelated
run_check 0 "検知対象のない変更は通す"

echo "--- 2. テストの skip/only 追加 ---"
seed
skip_plain
run_check 1 "通常のパスで skip 追加を検知する"
check_summary "テストの skip/only 追加" "skip追加が報告される"

seed
skip_spaced
run_check 1 "空白を含むパスでも skip 追加を検知する"
check_summary "some dir/spaced.test.ts" "空白入りパスがファイル名として報告される"

seed
skip_japanese
run_check 1 "非ASCIIを含むパスでも skip 追加を検知する"
check_summary "日本語.test.ts" "非ASCIIパスがファイル名として報告される"

seed
add_xit
run_check 1 "xit の追加を検知する"

echo "--- 2b. Javaテストの @Disabled 追加 ---"
seed
add_disabled
run_check 1 "@Disabled の追加を検知する"
check_summary "@Disabled 追加" "@Disabled が報告される"

echo "--- 3. TypeScript 型チェック抑止 ---"
seed
add_ts_ignore
run_check 1 "@ts-ignore の追加を検知する"
check_summary "TypeScript 型チェック抑止の追加" "型チェック抑止が報告される"

echo "--- 4. eslint-disable インライン ---"
seed
add_eslint_disable
run_check 1 "eslint-disable の追加を検知する"
check_summary "eslint-disable インライン追加" "eslint-disable が報告される"

echo "--- 5. アサーションの削除 ---"
seed
drop_ts_assert
run_check 1 "TSのアサーション削除を検知する"
check_summary "既存テストのアサーション変更・削除" "アサーション削除が報告される"

seed
drop_java_assert
run_check 1 "Javaのアサーション削除を検知する"

seed
drop_ts_assert
justify
run_check 0 "PR本文に理由があればアサーション削除を通す"

echo "--- 6. ゲート設定ファイルの変更 ---"
seed
touch_gate_file
run_check 1 "所有者未承認ならゲート設定の変更を落とす"
check_summary "ゲート設定ファイルの変更(所有者未承認)" "ゲート設定の変更が報告される"

seed
touch_gate_file
approve
run_check 0 "所有者承認済みならゲート設定の変更を通す"

echo "--- 1. 品質ゲート配線 ---"
seed
add_second_apply
run_check 1 "build.gradle の apply from が2本になったら落とす"
check_summary "品質ゲート配線の改変" "配線の改変が報告される"

seed
drop_quality_apply
run_check 1 "quality.gradle の読み込みが消えたら落とす"

seed
add_apply_elsewhere
run_check 1 "build.gradle 以外での apply from を落とす"
check_summary "build.gradle以外でのapply from" "別ファイルの apply from が報告される"

seed
add_violation_rules
run_check 1 "build.gradle への violationRules 記述を落とす"
check_summary "カバレッジ閾値の上書き" "閾値の上書きが報告される"

echo "--- 監視対象パスの絞り込み ---"
seed
skip_outside_scope
run_check 0 "監視対象パスの外での skip 追加は通す"

echo "--- ハンク先頭からの走査 ---"
seed
add_plusplus_disable
run_check 1 "内容が ++ で始まる追加行でも検知する"
check_summary "eslint-disable インライン追加" "++ で始まる行が報告される"

echo "--- リネームと削除の意味論 ---"
seed
rename_only
run_check 0 "ハッチを含まないファイルのリネームは通す"

seed
rename_hatched
run_check 1 "ハッチを含むファイルのリネームは赤にする"
check_summary "TypeScript 型チェック抑止の追加" "リネームで全行が追加として扱われる"

seed
delete_test_file
run_check 1 "アサーションを含むテストファイルの削除を検知する"

echo "--- 2c. Go のテストの飛ばしの追加 ---"
seed
go_skip
run_check 1 "t.Skip の追加を見つける"
check_summary "Go のテストの飛ばしの追加" "t.Skip の追加が報告される"
check_summary "sample_test.go" "t.Skip を足したファイルの名前が報告される"

seed
go_skip_now
run_check 1 "t.SkipNow の追加を見つける"

seed
go_skipf
run_check 1 "t.Skipf の追加を見つける"

seed
go_skip_helper
run_check 1 "テストの外の助けの関数での t 以外の名前の Skip の追加を見つける"

seed
go_skip_outside
run_check 0 "backend の外の Go のファイルの Skip の追加は通す"

seed
go_plain_change
run_check 0 "飛ばしと外しを含まない Go のコードの変更は通す"

echo "--- 4b. Go の検査の外しとカバレッジの除外の追加 ---"
seed
go_nolint
run_check 1 "nolint の追加を見つける"
check_summary "Go の検査の外しの追加" "nolint の追加が報告される"

seed
go_nolint_spaced
run_check 1 "空白を挟んだ nolint の追加を見つける"

seed
go_coverage_ignore
run_check 1 "coverage-ignore の追加を見つける"
check_summary "Go の検査の外しの追加" "coverage-ignore の追加が報告される"

echo "--- 6b. Go 版の品質チェックとコード生成の設定 ---"
seed
go_testcoverage_in_base
go_testcoverage_exclude
run_check 1 ".testcoverage.yml の変更は所有者の承認が無ければ失敗する"
check_summary "backend/.testcoverage.yml" ".testcoverage.yml がゲート設定ファイルとして報告される"

seed
go_testcoverage_in_base
go_testcoverage_exclude
approve
run_check 0 ".testcoverage.yml の変更は所有者の承認があれば通る"

seed
go_testcoverage_new
approve
run_check 0 ".testcoverage.yml を新しく作る変更は所有者の承認があれば通る"

seed
go_testcoverage_new
run_check 1 ".testcoverage.yml を新しく作る変更は所有者の承認が無ければ失敗する"

seed
go_makefile
run_check 1 "Makefile の変更は所有者の承認が無ければ失敗する"

seed
go_golangci
run_check 1 ".golangci.yml の変更は所有者の承認が無ければ失敗する"

seed
go_gremlins
run_check 1 ".gremlins.yaml の変更は所有者の承認が無ければ失敗する"

seed
go_oapi
run_check 1 "api/oapi-codegen.yaml の変更は所有者の承認が無ければ失敗する"

seed
go_sqlc
run_check 1 "sqlc.yaml の変更は所有者の承認が無ければ失敗する"

seed
go_nested_makefile
run_check 0 "backend の直下でない Makefile の変更は通す"

echo "--- 6c. 品質チェックが何を調べるかを決めるファイル ---"
for p in \
    .gitleaksignore \
    .gitleaks.toml \
    .editorconfig \
    frontend/eslint.config.js \
    frontend/src/feature/eslint.config.mjs \
    frontend/vite.config.ts \
    frontend/vite.config.js \
    frontend/vitest.config.ts \
    frontend/vitest.workspace.ts \
    frontend/playwright.config.ts \
    frontend/playwright.config.js \
    frontend/tsconfig.json \
    frontend/tsconfig.app.json \
    frontend/tsconfig.node.json \
    frontend/src/feature/tsconfig.json \
    frontend/.prettierrc \
    frontend/.prettierrc.json \
    frontend/src/feature/.prettierrc \
    frontend/prettier.config.js \
    frontend/.prettierignore \
    frontend/.editorconfig \
    frontend/knip.json \
    frontend/.knip.jsonc \
    frontend/knip.config.ts \
    frontend/stryker.config.json \
    frontend/stryker.conf.mjs \
    backend/gradle/quality.gradle \
    backend/config/checkstyle.xml \
    backend/src/test/java/com/example/keirekipro/unit/architecture/ArchTest.java \
    terraform/.checkov.yaml \
    terraform/modules/x/.checkov.yml \
    terraform/.tflint.hcl \
    terraform/modules/x/.tflint.hcl \
    terraform/.checkov.baseline; do
    seed
    touch_path "$p"
    run_check 1 "$p の変更は所有者の承認が無ければ失敗する"
    check_summary "$p" "$p がゲート設定ファイルとして報告される"
done

seed
touch_path frontend/tsconfig.app.json
approve
run_check 0 "tsconfig.app.json の変更は所有者の承認があれば通る"

for p in \
    frontend/src/knip.json \
    frontend/src/stryker.config.json \
    frontend/src/vite.config.ts \
    doc/tsconfig.json \
    doc/.prettierrc \
    backend/.checkov.yaml \
    frontend/vitest-setup.ts; do
    seed
    touch_path "$p"
    run_check 0 "$p は品質チェックの設定でないので通す"
done

echo "--- 6d. frontend/package.json の依存の版のほかの欄 ---"
seed
pkg_bump_versions
run_check 0 "依存の版だけを上げる変更は通す"

seed
pkg_bump_package_manager
run_check 0 "packageManager の版だけを上げる変更は通す"

seed
pkg_add_dependency
run_check 0 "依存を足す変更は通す(依存の検査が別に見る)"

seed
pkg_change_script
run_check 1 "scripts の欄の変更は所有者の承認が無ければ失敗する"
check_summary "frontend/package.json(依存の版の欄と packageManager のほかの欄)" "package.json がゲート設定ファイルとして報告される"

seed
pkg_change_script
pkg_bump_versions
run_check 1 "依存の版と一緒に scripts の欄を変えても失敗する"

seed
pkg_change_script
approve
run_check 0 "scripts の欄の変更は所有者の承認があれば通る"

seed
pkg_add_tool_config
run_check 1 "道具の設定の欄を足す変更は所有者の承認が無ければ失敗する"

seed
pkg_break_json
run_check 1 "JSON として読めない package.json は承認を求める"

seed
pkg_delete
run_check 1 "package.json を消す変更は承認を求める"

echo "--- 6e. docker/terraform/Dockerfile の FROM の行の版のほかの行 ---"
seed
docker_bump_tag
run_check 0 "FROM の行のタグだけを上げる変更は通す"

seed
docker_bump_digest
run_check 0 "FROM の行の digest だけを変える変更は通す"

seed
docker_add_platform
run_check 1 "FROM の行に指定を足す変更は所有者の承認が無ければ失敗する"

seed
docker_change_image
run_check 1 "FROM の行のイメージの名前を変える変更は所有者の承認が無ければ失敗する"

seed
docker_change_run
run_check 1 "FROM のほかの行の変更は所有者の承認が無ければ失敗する"
check_summary "docker/terraform/Dockerfile(FROM の行のイメージの版のほかの行)" "Dockerfile がゲート設定ファイルとして報告される"

seed
docker_change_run
approve
run_check 0 "FROM のほかの行の変更は所有者の承認があれば通る"

echo "--- 7. 検査から一部を外す注釈 ---"
# 使い方: <期待exit> <パス> <足す行>
for c in \
    "1|terraform/main.tf|# checkov:skip=CKV_AWS_18: 理由" \
    "1|terraform/modules/x/main.tf|  #checkov:skip=CKV_AWS_18" \
    "1|terraform/main.tf|# bridgecrew:skip=CKV_AWS_18" \
    "1|terraform/main.tf|# tflint-ignore: aws_instance_invalid_type" \
    "1|terraform/modules/x/main.tf|# tflint-ignore-file: terraform_naming_convention" \
    "1|README.md|token = \"abc\" # gitleaks:allow" \
    "1|frontend/src/app.ts|const t = 'abc'; // gitleaks:allow" \
    "1|backend/internal/sample/x.go|// GITLEAKS:ALLOW" \
    "1|frontend/src/app.ts|// prettier-ignore" \
    "1|frontend/src/feature/a.tsx|{/* prettier-ignore */}" \
    "1|frontend/src/doc.md|<!-- prettier-ignore-start -->" \
    "0|doc/main.tf|# checkov:skip=CKV_AWS_18" \
    "0|doc/main.tf|# tflint-ignore: all" \
    "0|doc/note.md|<!-- prettier-ignore -->" \
    "0|frontend/e2e/a.spec.ts|// prettier-ignore" \
    "0|terraform/main.tf|# checkov のことを書いた普通のコメント"; do
    IFS='|' read -r want path line <<<"$c"
    seed
    add_line "$line" "$path"
    run_check "$want" "$path に「$line」を足す変更は exit $want"
done

seed
add_line "# checkov:skip=CKV_AWS_18" terraform/main.tf
run_check 1 "checkov の注釈は所有者の承認が無ければ失敗する"
check_summary "検査から外す注釈と依存の差し替え(所有者未承認)" "注釈が承認を求める変更として報告される"
check_summary "checkov の検査を外す注釈" "checkov の注釈の見出しが報告される"
check_summary "terraform/main.tf: # checkov:skip=CKV_AWS_18" "注釈を足したファイルと行が報告される"

seed
add_line "# tflint-ignore: all" terraform/main.tf
run_check 1 "tflint の注釈は所有者の承認が無ければ失敗する"
check_summary "tflint の検査を外す注釈" "tflint の注釈の見出しが報告される"

seed
add_line "x = 1 # gitleaks:allow" README.md
run_check 1 "gitleaks の注釈は所有者の承認が無ければ失敗する"
check_summary "gitleaks の検査を外す注釈" "gitleaks の注釈の見出しが報告される"

seed
add_line "// prettier-ignore" frontend/src/app.ts
run_check 1 "prettier の注釈は所有者の承認が無ければ失敗する"
check_summary "prettier の検査を外す注釈" "prettier の注釈の見出しが報告される"

seed
add_line "# checkov:skip=CKV_AWS_18" terraform/main.tf
add_line "// prettier-ignore" frontend/src/app.ts
approve
run_check 0 "注釈は所有者の承認があれば通る"

seed
add_line "// prettier-ignore" frontend/src/app.ts
add_line "# tflint-ignore: all" terraform/main.tf
commit_as_base
sed -i '/prettier-ignore/d' frontend/src/app.ts
sed -i '/tflint-ignore/d' terraform/main.tf
run_check 0 "注釈を消す変更は承認なしで通る"

seed
add_line "# tflint-ignore: all" terraform/main.tf
commit_as_base
add_line "resource \"x\" \"y\" {}" terraform/main.tf
run_check 0 "注釈がすでにあるファイルのほかの行を変える変更は承認なしで通る"

echo "--- 7b. 依存を別の部品に差し替える書き方 ---"
# 使い方: <期待exit> <react の版の欄に書く文字>
for c in \
    "1|npm:evil-react@^19.0.0" \
    "1|npm:@evil/react@^19.0.0" \
    "1|npm:evil-react" \
    "1|npm:react@github:evil/react" \
    "1|github:evil/react" \
    "1|evil/react" \
    "1|git+https://example.com/evil/react.git" \
    "1|https://example.com/react-19.0.0.tgz" \
    "1|file:../vendor/react" \
    "1|link:../vendor/react" \
    "1|workspace:*" \
    "1|catalog:" \
    "1|react-19.0.0.tgz" \
    "1|react-19.0.0.tar.gz" \
    "0|npm:react@^19.1.0" \
    "0|^19.1.0" \
    "0|19.1.0" \
    "0|~19.1.0" \
    "0|>=19.0.0 <20.0.0" \
    "0|19.x || 20.x" \
    "0|19.1.0-rc.1" \
    "0|latest" \
    "0|*"; do
    # 版の欄の文字が | を含むことがあるので、最初の | だけで分ける
    want=${c%%|*}
    spec=${c#*|}
    seed
    pkg_set_react "$spec"
    run_check "$want" "依存の版の欄を「$spec」に変える変更は exit $want"
done

seed
pkg_set_react "npm:evil-react@^19.0.0"
run_check 1 "npm: で別の名前を指す変更は所有者の承認が無ければ失敗する"
check_summary "frontend/package.json の依存を別の部品に差し替える書き方" "差し替えの見出しが報告される"
check_summary '["dependencies","react","evil-react"]' "差し替えた欄と依存と、差し替えた先の名前が報告される"

seed
pkg_set_eslint "npm:evil-eslint@^9.39.4"
run_check 1 "devDependencies の差し替えも所有者の承認が無ければ失敗する"

seed
pkg_add_alias_dependency
run_check 1 "npm: で別の名前を指す依存を足す変更は所有者の承認が無ければ失敗する"

seed
pkg_set_react "npm:evil-react@^19.0.0"
approve
run_check 0 "依存の差し替えは所有者の承認があれば通る"

seed
pkg_set_react "npm:preact-compat@3.0.0"
commit_as_base
pkg_alias_version_up
run_check 0 "npm: で指す名前を変えずに版だけを上げる変更は承認なしで通る"

seed
pkg_set_react "npm:preact-compat@3.0.0"
commit_as_base
pkg_alias_rename
run_check 1 "npm: で指す名前を変える変更は所有者の承認が無ければ失敗する"

seed
pkg_set_react "npm:preact-compat@3.0.0"
commit_as_base
pkg_bump_versions
run_check 0 "差し替えがすでにあるときに、ほかの依存の版を上げる変更は承認なしで通る"

seed
pkg_set_react "npm:preact-compat@3.0.0"
commit_as_base
pkg_alias_back_to_plain
run_check 0 "差し替えを普通の版に戻す変更は承認なしで通る"

seed
pkg_set_react "https://example.com/react-19.0.0.tgz"
commit_as_base
pkg_url_version_up
run_check 1 "URL の指定は版の部分だけを変えても所有者の承認が無ければ失敗する"

echo "--- 変更ファイルの一覧が取れない場合 ---"
seed
touch_unrelated
run_check_broken_git 1 "一覧の取得に失敗したら素通りせず落とす"

if [ "$FAILED" -eq 0 ]; then
    echo "すべてのテストがPASSしました。"
else
    echo "失敗したテストがあります。"
fi
exit "$FAILED"
