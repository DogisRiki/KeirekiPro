#!/usr/bin/env bash
# =====================================================================
# check-dependency-additions.sh の自動テスト(dependency-gate CI から実行)
#
# 一時gitリポジトリにbase/headを作り、終了コードを検証する。
#   0 = 緑(通過) / 1 = 赤(所有者の承認を要求)
# 併せて、Summaryへ出す報告の内容も検証する。
# =====================================================================
set -uo pipefail

SCRIPT="$(cd "$(dirname "$0")/.." && pwd)/check-dependency-additions.sh"
# 一時領域の確保に失敗したまま進むと rm -rf が意図しない絶対パスを対象にするため、
# ディレクトリが実在することを確認してから trap を設定する
WORK=$(mktemp -d) || exit 1
[ -n "$WORK" ] && [ -d "$WORK" ] || exit 1
trap 'rm -rf "$WORK"' EXIT
export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.com
export GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.com
FAILED=0

seed() {
    rm -rf "$WORK/repo"
    mkdir -p "$WORK/repo/backend/gradle/wrapper" "$WORK/repo/frontend"
    cd "$WORK/repo" || exit 1
    git init -q .
    printf "plugins {\n    id 'java'\n}\ndependencies {\n    implementation 'org.example:lib:1.0.0'\n}\n" >backend/build.gradle
    echo "rootProject.name = 'test'" >backend/settings.gradle
    echo "dependencies { implementation 'org.quality:only:1.0.0' }" >backend/gradle/quality.gradle
    echo "distributionUrl=https\://example.invalid/gradle-9.0.0-bin.zip" >backend/gradle/wrapper/gradle-wrapper.properties
    echo '{"dependencies":{"react":"^19.0.0"},"devDependencies":{}}' >frontend/package.json
    printf 'packages:\n  - .\n\noverrides:\n  follow-redirects: ">=1.16.0"\n' >frontend/pnpm-workspace.yaml
    printf "lockfileVersion: '9.0'\n\npackages:\n\n  react@19.0.0:\n    resolution: {integrity: sha512-aaa}\n\n  '@scope/dep@1.0.0':\n    resolution: {integrity: sha512-bbb}\n" >frontend/pnpm-lock.yaml
    git add -A && git commit -qm base
    BASE=$(git rev-parse HEAD)
}

# 使い方: check <期待exit> <所有者Approve> <説明> <変更を加える関数>
check() {
    local want="$1" approved="$2" name="$3" mutate="$4" got
    seed
    "$mutate"
    git add -A && git commit -qm head --allow-empty
    OWNER_APPROVED="$approved" bash "$SCRIPT" "$BASE" "$(git rev-parse HEAD)" >/dev/null 2>&1
    got=$?
    if [ "$got" = "$want" ]; then
        printf 'ok   %s\n' "$name"
    else
        printf 'FAIL %s (期待 exit=%s / 実際 exit=%s)\n' "$name" "$want" "$got"
        FAILED=1
    fi
}

# 使い方: check_summary <期待する文字列> <期待しない文字列(空なら検査しない)> <説明> <変更を加える関数>
check_summary() {
    local want="$1" unwanted="$2" name="$3" mutate="$4" summary
    seed
    "$mutate"
    git add -A && git commit -qm head --allow-empty
    summary="$WORK/summary.md"
    : >"$summary"
    GITHUB_STEP_SUMMARY="$summary" OWNER_APPROVED=false \
        bash "$SCRIPT" "$BASE" "$(git rev-parse HEAD)" >/dev/null 2>&1
    if ! grep -q "$want" "$summary"; then
        printf 'FAIL %s (Summaryに "%s" が無い)\n' "$name" "$want"
        FAILED=1
        return
    fi
    if [ -n "$unwanted" ] && grep -q "$unwanted" "$summary"; then
        printf 'FAIL %s (Summaryに "%s" が出てはいけない)\n' "$name" "$unwanted"
        FAILED=1
        return
    fi
    printf 'ok   %s\n' "$name"
}

m_none() { echo "# comment" >>README.md; }
m_src_only() { mkdir -p backend/src && echo "class A {}" >backend/src/A.java; }
m_front_src_only() { mkdir -p frontend/src && echo "export const a = 1;" >frontend/src/a.ts; }
m_dep_add() { sed -i "s|^dependencies {|dependencies {\n    implementation 'org.new:dep:1.0.0'|" backend/build.gradle; }
m_dep_bump() { sed -i 's|org.example:lib:1.0.0|org.example:lib:2.0.0|' backend/build.gradle; }
m_comment_only() { echo "// コメントのみ" >>backend/build.gradle; }
m_settings() { echo "// settings の変更" >>backend/settings.gradle; }
m_quality() { echo "// quality.gradle の変更" >>backend/gradle/quality.gradle; }
m_kts_new() { echo 'plugins { kotlin("jvm") }' >backend/build.gradle.kts; }
m_catalog_new() { printf '[plugins]\nevil = { id = "com.evil", version = "1.0" }\n' >backend/gradle/libs.versions.toml; }
m_wrapper() { sed -i 's|gradle-9.0.0-bin.zip|gradle-9.1.0-bin.zip|' backend/gradle/wrapper/gradle-wrapper.properties; }
m_npm_add() { sed -i 's|"react":"\^19.0.0"|"react":"^19.0.0","new-pkg":"^1.0.0"|' frontend/package.json; }
# 変更ファイル一覧を数百KBにする。パイプ経由で判定しているとSIGPIPEで見落とす
m_npm_add_many() { m_npm_add; d="frontend/src/$(printf 'x%.0s' $(seq 1 120))"; mkdir -p "$d"; for i in $(seq 1 2000); do echo x >"$d/f$i.ts"; done; }
m_npm_bump() { sed -i 's|\^19.0.0|^19.1.0|' frontend/package.json; }
m_lock_only() { sed -i 's|react@19.0.0|react@19.1.0|' frontend/pnpm-lock.yaml; }
m_workspace_override() { sed -i 's|follow-redirects: ">=1.16.0"|follow-redirects: ">=1.16.0"\n  evil: "npm:totally-different@1.0.0"|' frontend/pnpm-workspace.yaml; }
# 推移的依存として見慣れないパッケージが増える(axios改ざんの形)
m_lock_new_transitive() { sed -i "s|  react@19.0.0:|  plain-crypto-js@4.2.1:\n    resolution: {integrity: sha512-ccc}\n\n  react@19.0.0:|" frontend/pnpm-lock.yaml; }
# スコープ付きの新規パッケージ。lockfile 上では '...' と引用される
m_lock_new_scoped() { sed -i "s|  react@19.0.0:|  '@evil/crypto-helper@1.0.0':\n    resolution: {integrity: sha512-ddd}\n\n  react@19.0.0:|" frontend/pnpm-lock.yaml; }
m_npmrc_add() { echo "minimum-release-age=0" >frontend/.npmrc; }
m_pnpmfile_add() { echo "module.exports = { hooks: {} };" >frontend/.pnpmfile.cjs; }

check 0 false "依存定義以外のみの変更" m_none
check 0 false "backendのソースのみの変更" m_src_only
check 0 false "frontendのソースのみの変更" m_front_src_only
check 1 false "build.gradle への依存追加" m_dep_add
check 1 false "build.gradle のバージョン更新のみ" m_dep_bump
check 1 false "build.gradle のコメントのみの変更" m_comment_only
check 1 false "settings.gradle の変更" m_settings
check 1 false "quality.gradle の変更" m_quality
check 1 false "build.gradle.kts の追加" m_kts_new
check 1 false "version catalog の追加" m_catalog_new
check 1 false "gradle-wrapper.properties の変更" m_wrapper
check 1 false "npm依存の追加" m_npm_add
check 1 false "npm依存の追加(変更ファイルが大量)" m_npm_add_many
check 1 false "npm依存のバージョン更新のみ" m_npm_bump
check 1 false "pnpm-lock.yaml のみの変更" m_lock_only
check 1 false "pnpm-workspace.yaml の overrides 変更" m_workspace_override
check 0 true "build.gradle の変更 + 所有者Approve済み" m_dep_add
check 0 true "pnpm-lock.yaml の変更 + 所有者Approve済み" m_lock_only
check 1 false ".npmrc の追加" m_npmrc_add
check 1 false ".pnpmfile.cjs の追加" m_pnpmfile_add

check_summary "plain-crypto-js" "" "推移的依存が増えたときSummaryに名前が出る" m_lock_new_transitive
check_summary "pnpm-workspace.yaml" "新しく現れたパッケージ" "lockfile以外の変更では報告の節を出さない" m_workspace_override
# 引用符が残ると承認者が名前をそのまま検索できないため、剥がれていることを検証する
check_summary "@evil/crypto-helper" "'@evil/crypto-helper" "スコープ付きの新規パッケージが引用符なしで出る" m_lock_new_scoped

if [ "$FAILED" -ne 0 ]; then
    echo "::error::check-dependency-additions.sh のテストが失敗しました。"
    exit 1
fi
echo "全ケース成功。"
