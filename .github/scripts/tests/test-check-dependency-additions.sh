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
    mkdir -p "$WORK/repo/backend/gradle" "$WORK/repo/frontend"
    cd "$WORK/repo" || exit 1
    git init -q .
    cat >backend/build.gradle <<'EOF'
plugins {
    id 'java'
    id 'com.diffplug.spotless' version '7.2.1'
    id 'com.deferred.only' version '1.0' apply false
}
dependencies {
    implementation 'org.example:lib:1.0.0'
}
EOF
    cat >backend/settings.gradle <<'EOF'
rootProject.name = 'test'
pluginManagement {
    plugins {
        id 'com.declared.only' version '1.0'
    }
}
EOF
    echo "dependencies { implementation 'org.quality:only:1.0.0' }" >backend/gradle/quality.gradle
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
m_apply_paren() { echo "apply(plugin: 'com.new.parenapply')" >>backend/build.gradle; }
m_plugin_add_paren() { sed -i "s|    id 'java'|    id 'java'\n    id(\"com.new.paren\")|" backend/build.gradle; }
m_apply_deferred() { echo "apply plugin: 'com.deferred.only'" >>backend/build.gradle; }
m_drop_apply_false() { sed -i "s|    id 'com.deferred.only' version '1.0' apply false|    id 'com.deferred.only' version '1.0'|" backend/build.gradle; }
m_apply_declared() { sed -i "s|    id 'java'|    id 'java'\n    id 'com.declared.only'|" backend/build.gradle; }
m_settings() { sed -i "s|        id 'com.declared.only' version '1.0'|        id 'com.declared.only' version '1.0'\n        id 'com.new.settings' version '1.0'|" backend/settings.gradle; }
m_quality() { echo "apply plugin: 'com.new.inquality'" >>backend/gradle/quality.gradle; }
m_npm_add() { sed -i 's|"react":"\^19.0.0"|"react":"^19.0.0","new-pkg":"^1.0.0"|' frontend/package.json; }
m_npm_bump() { sed -i 's|\^19.0.0|^19.1.0|' frontend/package.json; }

check 0 false "gradle以外のみの変更" m_none
check 1 false "依存ライブラリの追加" m_dep_add
check 0 false "依存ライブラリのバージョン更新のみ" m_dep_bump
check 1 false "プラグインの追加(plugins DSL)" m_plugin_add
check 1 false "プラグインの追加(id(\"x\") 形式)" m_plugin_add_paren
check 1 false "他ファイルで宣言済みのIDの適用" m_apply_declared
check 1 false "同一ファイルの apply false 宣言の適用" m_apply_deferred
check 1 false "apply false の削除による適用" m_drop_apply_false
check 0 false "プラグインのバージョン更新のみ" m_plugin_bump
check 1 false "apply plugin: での適用" m_apply
check 1 false "apply(plugin: ...) での適用" m_apply_paren
check 1 false "settings.gradle 経由の適用" m_settings
check 1 false "quality.gradle へのプラグイン追加" m_quality
check 1 false "npm依存の追加" m_npm_add
check 0 false "npm依存のバージョン更新のみ" m_npm_bump
check 0 true "プラグイン追加 + 所有者Approve済み" m_plugin_add

if [ "$FAILED" -ne 0 ]; then
    echo "::error::check-dependency-additions.sh のテストが失敗しました。"
    exit 1
fi
echo "全ケース成功。"
