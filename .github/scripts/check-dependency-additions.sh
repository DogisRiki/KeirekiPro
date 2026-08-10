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
# 環境変数:
#   OWNER_APPROVED : "true" ならリポジトリ所有者のApprove済み
#
# 使い方: check-dependency-additions.sh <base_sha> <head_sha>
# =====================================================================
set -euo pipefail

BASE_SHA="${1:?base sha required}"
HEAD_SHA="${2:?head sha required}"
OWNER_APPROVED="${OWNER_APPROVED:-false}"

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

# --- backend/build.gradle: 依存座標(group:artifact)の集合を比較 ---
gradle_coords() {
    # implementation 'group:artifact:version' / platform('group:artifact:version') 等から
    # group:artifact を抽出する(バージョン部は無視 = 更新は追加扱いにしない)
    grep -oE "(implementation|api|compileOnly|runtimeOnly|developmentOnly|annotationProcessor|testImplementation|testCompileOnly|testRuntimeOnly|testAnnotationProcessor)[^'\"]*['\"][^'\"]+['\"]" 2>/dev/null |
        grep -oE "['\"][^'\"]+['\"]$" |
        tr -d "'\"" |
        awk -F: 'NF >= 2 { print $1 ":" $2 }' |
        sort -u
}

if git diff --name-only "$MERGE_BASE" "$HEAD_SHA" | grep -q '^backend/build\.gradle$'; then
    base_coords=$(git show "$MERGE_BASE:backend/build.gradle" | gradle_coords || true)
    head_coords=$(git show "$HEAD_SHA:backend/build.gradle" | gradle_coords || true)
    new_gradle=$(comm -13 <(echo "$base_coords") <(echo "$head_coords") || true)
    if [ -n "$new_gradle" ]; then
        additions+="[backend/build.gradle]"$'\n'"$new_gradle"$'\n'
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
