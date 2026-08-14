#!/usr/bin/env bash
# =====================================================================
# check-dependency-additions.sh の自動テスト(dependency-gate CI から実行)
#
# 一時gitリポジトリにbase/headを作り、終了コードを検証する。
#   0 = 緑(通過) / 1 = 赤(所有者の承認を要求)
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

m_none() { echo "# comment" >>README.md; }
m_src_only() { mkdir -p backend/src && echo "class A {}" >backend/src/A.java; }
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

check 0 false "ビルド定義以外のみの変更" m_none
check 0 false "backendのソースのみの変更" m_src_only
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
check 0 false "npm依存のバージョン更新のみ" m_npm_bump
check 0 true "build.gradle の変更 + 所有者Approve済み" m_dep_add

if [ "$FAILED" -ne 0 ]; then
    echo "::error::check-dependency-additions.sh のテストが失敗しました。"
    exit 1
fi
echo "全ケース成功。"
