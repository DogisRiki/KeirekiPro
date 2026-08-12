#!/usr/bin/env bash
# =====================================================================
# 依存パッケージ追加の検知(dependency-gate CI から実行)
#
# 「追加」のみを人間ゲートにする。既存依存のバージョン更新は検知しない
# (週次の自動更新レーンを妨げないため)。
#
# 判定:
#   依存追加なし                        -> exit 0(緑)
#   依存追加あり + 所有者Approveなし     -> exit 1(赤)
#   依存追加あり + 所有者Approveあり     -> exit 0(緑)
#
# 走査対象:
#   - frontend/package.json(dependencies + devDependencies)
#   - backend/**/*.gradle と *.gradle.kts(quality.gradle を除く全gradleファイル。
#     新規gradleファイル経由の依存追加も検知する)
#
# 環境変数:
#   OWNER_APPROVED : "true" ならリポジトリ所有者のApprove済み
#
# 使い方: check-dependency-additions.sh <base_sha> <head_sha>
# =====================================================================
set -euo pipefail

BASE_SHA="${1:?base sha required}"
HEAD_SHA="${2:?head sha required}"
OWNER_APPROVED="${OWNER_APPROVED:-false}"

# fail-closed: 解析ツールが無い環境で黙って合格させない
if ! command -v jq >/dev/null 2>&1; then
    echo "::error::jq が見つかりません。依存追加の判定ができないため fail-closed で失敗します。"
    exit 1
fi

MERGE_BASE=$(git merge-base "$BASE_SHA" "$HEAD_SHA")

additions=""

# --- frontend/package.json: dependencies + devDependencies のキー集合を比較 ---
pkg_keys() {
    jq -r '((.dependencies // {}) + (.devDependencies // {})) | keys[]' 2>/dev/null | sort -u
}

if git diff --name-only "$MERGE_BASE" "$HEAD_SHA" | grep -q '^frontend/package\.json$'; then
    base_keys=$(git show "$MERGE_BASE:frontend/package.json" | pkg_keys || true)
    head_keys=$(git show "$HEAD_SHA:frontend/package.json" | pkg_keys || true)
    new_npm=$(comm -13 <(echo "$base_keys") <(echo "$head_keys") || true)
    if [ -n "$new_npm" ]; then
        additions+="[frontend/package.json]"$'\n'"$new_npm"$'\n'
    fi
fi

# --- backend/**/*.gradle: 依存座標(group:artifact)の集合を比較 ---
gradle_coords() {
    # implementation 'group:artifact:version' / classpath / platform(...) 等から
    # group:artifact を抽出する(バージョン部は無視 = 更新は追加扱いにしない)
    grep -oE "(implementation|api|compileOnly|runtimeOnly|developmentOnly|annotationProcessor|testImplementation|testCompileOnly|testRuntimeOnly|testAnnotationProcessor|classpath)[^'\"]*['\"][^'\"]+['\"]" 2>/dev/null |
        grep -oE "['\"][^'\"]+['\"]$" |
        tr -d "'\"" |
        awk -F: 'NF >= 2 { print $1 ":" $2 }' |
        sort -u
}

# 指定リビジョンの backend 配下の全gradleファイル(quality.gradle除く)を連結して座標を抽出する
gradle_coords_at() {
    local ref="$1"
    git ls-tree -r --name-only "$ref" -- backend 2>/dev/null |
        grep -E '\.gradle(\.kts)?$' |
        grep -v '^backend/gradle/quality\.gradle$' |
        while IFS= read -r f; do
            git show "$ref:$f" 2>/dev/null || true
        done | gradle_coords
}

gradle_changed=$(git diff --name-only "$MERGE_BASE" "$HEAD_SHA" | grep -E '^backend/.*\.gradle(\.kts)?$' | grep -v '^backend/gradle/quality\.gradle$' || true)
if [ -n "$gradle_changed" ]; then
    base_coords=$(gradle_coords_at "$MERGE_BASE" || true)
    head_coords=$(gradle_coords_at "$HEAD_SHA" || true)
    new_gradle=$(comm -13 <(echo "$base_coords") <(echo "$head_coords") || true)
    if [ -n "$new_gradle" ]; then
        additions+="[backend/**/*.gradle]"$'\n'"$new_gradle"$'\n'
    fi
fi

if [ -z "$additions" ]; then
    echo "依存パッケージの追加なし。"
    exit 0
fi

{
    echo "### :package: 依存パッケージの追加を検出"
    echo ""
    echo '```'
    echo "$additions"
    echo '```'
} >>"${GITHUB_STEP_SUMMARY:-/dev/null}"

if [ "$OWNER_APPROVED" = "true" ]; then
    echo "依存追加を検出しましたが、リポジトリ所有者のApprove済みのため通過します。"
    echo "$additions"
    exit 0
fi

echo "::error::依存パッケージの追加が検出されました。リポジトリ所有者のApproveレビュー後にこのチェックは緑になります。"
echo "$additions"
exit 1
