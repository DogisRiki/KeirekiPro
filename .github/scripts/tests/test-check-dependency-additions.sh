#!/usr/bin/env bash
# =====================================================================
# check-dependency-additions.sh の自動テスト(dependency-gate CI から実行)
#
# 一時gitリポジトリにbase/headを作り、終了コードを検証する。
#   0 = 緑(通過) / 1 = 赤(所有者の承認を要求)
# =====================================================================
set -uo pipefail

SCRIPT="$(cd "$(dirname "$0")/.." && pwd)/check-dependency-additions.sh"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.com
export GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.com
FAILED=0

seed() {
    rm -rf "$WORK/repo"
    mkdir -p "$WORK/repo/backend/gradle" "$WORK/repo/frontend"
    cd "$WORK/repo" || exit 1
    git init -q .
    cat >backend/build.gradle <<'EOF'
plugins {
    id 'java'
    id 'com.diffplug.spotless' version '7.2.1'
}
dependencies {
    implementation 'org.example:lib:1.0.0'
}
EOF
    echo "rootProject.name = 'test'" >backend/settings.gradle
    echo "dependencies { implementation 'org.quality:only:1.0.0' }" >backend/gradle/quality.gradle
    cat >backend/gradle/libs.versions.toml <<'EOF'
[versions]
v = "1.0"

[libraries]
libA = { module = "org.example:cat", version.ref = "v" }

[plugins]
plugA = { id = "com.example.safe", version.ref = "v" }
EOF
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
m_dep_add() { echo "dependencies { implementation 'org.new:dep:1.0.0' }" >>backend/build.gradle; }
m_dep_bump() { sed -i 's|org.example:lib:1.0.0|org.example:lib:2.0.0|' backend/build.gradle; }
m_plugin_add() { sed -i "s|    id 'java'|    id 'java'\n    id 'com.new.plugin' version '1.0'|" backend/build.gradle; }
m_plugin_bump() { sed -i 's|7.2.1|7.2.2|' backend/build.gradle; }
m_apply() { echo "apply plugin: 'com.new.legacy'" >>backend/build.gradle; }
m_apply_kts() { echo 'apply(plugin = "com.new.kts")' >>backend/build.gradle.kts; }
m_kotlin_dsl() { echo 'plugins { kotlin("jvm") }' >>backend/build.gradle.kts; }
m_alias() { sed -i "s|    id 'java'|    id 'java'\n    alias(libs.plugins.plugA)|" backend/build.gradle; }
m_settings() { echo "pluginManagement { plugins { id 'com.new.settings' version '1.0' } }" >>backend/settings.gradle; }
m_cat_add() { echo 'plugB = { id = "com.new.catalog", version.ref = "v" }' >>backend/gradle/libs.versions.toml; }
m_cat_swap_id() { sed -i 's|com.example.safe|com.example.evil|' backend/gradle/libs.versions.toml; }
m_cat_swap_mod() { sed -i 's|org.example:cat|org.evil:cat|' backend/gradle/libs.versions.toml; }
m_cat_bump() { sed -i 's|^v = "1.0"|v = "1.1"|' backend/gradle/libs.versions.toml; }
m_quality() { sed -i 's|org.quality:only|org.quality:added|' backend/gradle/quality.gradle; }
m_npm_add() { sed -i 's|"react":"\^19.0.0"|"react":"^19.0.0","new-pkg":"^1.0.0"|' frontend/package.json; }
m_npm_bump() { sed -i 's|\^19.0.0|^19.1.0|' frontend/package.json; }

check 0 false "gradle以外のみの変更" m_none
check 1 false "依存ライブラリの追加" m_dep_add
check 0 false "依存ライブラリのバージョン更新のみ" m_dep_bump
check 1 false "プラグインの追加(plugins DSL)" m_plugin_add
check 0 false "プラグインのバージョン更新のみ" m_plugin_bump
check 1 false "apply plugin: での適用" m_apply
check 1 false "apply(plugin = ...) での適用(Kotlin DSL)" m_apply_kts
check 1 false "kotlin(...) での適用(Kotlin DSL)" m_kotlin_dsl
check 1 false "alias(...) での適用" m_alias
check 1 false "settings.gradle 経由の適用" m_settings
check 1 false "version catalog へのプラグイン追加" m_cat_add
check 1 false "version catalog の既存キーのID差し替え" m_cat_swap_id
check 1 false "version catalog の既存キーのmodule差し替え" m_cat_swap_mod
check 0 false "version catalog のバージョン更新のみ" m_cat_bump
check 0 false "quality.gradle のみの変更(走査対象外)" m_quality
check 1 false "npm依存の追加" m_npm_add
check 0 false "npm依存のバージョン更新のみ" m_npm_bump
check 0 true "プラグイン追加 + 所有者Approve済み" m_plugin_add

if [ "$FAILED" -ne 0 ]; then
    echo "::error::check-dependency-additions.sh のテストが失敗しました。"
    exit 1
fi
echo "全ケース成功。"
