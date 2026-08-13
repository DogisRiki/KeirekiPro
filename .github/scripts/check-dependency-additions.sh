#!/usr/bin/env bash
# =====================================================================
# 依存追加の人間ゲート(dependency-gate CI から実行)
#
# 判定:
#   対象の変更なし                      -> exit 0(緑)
#   対象の変更あり + 所有者Approveなし   -> exit 1(赤)
#   対象の変更あり + 所有者Approveあり   -> exit 0(緑)
#
# 判定対象:
#   - frontend/package.json
#     dependencies と devDependencies のキー集合を比較し、増えた場合に検知する。
#     JSONを構造化して読むため、書き方による取りこぼしは生じない。
#     バージョン更新のみは検知しない。
#   - backend のビルド定義ファイル
#     (*.gradle / *.gradle.kts / *.versions.toml / gradle/wrapper/gradle-wrapper.properties)
#     中身は解析せず、変更されたこと自体を検知する。バージョン更新も対象になる。
#     wrapper のプロパティを含めるのは、Gradle本体の配布物が変われば実行される
#     コードも変わり、ビルド定義と同じ性質を持つため。
#
# なぜ backend は中身を解析しないのか:
#   以前は正規表現で依存座標とプラグインIDを抽出していた。しかしGradleのビルド定義は
#   変数・条件分岐・Kotlin DSL・version catalog・動的な指定を許すため、静的な文字列
#   一致では原理的に網羅できない。実際にレビューで apply(plugin:) / apply false /
#   同一行の複数宣言 / 他ファイルで宣言済みIDの適用 といった迂回経路が次々に見つかり、
#   パターンを足し続ける状態になっていた。
#
#   Gradle自身に解決結果を出力させる方式(buildEnvironment や dependency locking)も
#   検討したが、apply false の区別ができず、環境依存の条件分岐も残る。加えて判定対象の
#   ビルドに自己申告させる構造になり、判定根拠がPR側の制御下に入る。
#
#   バージョン更新を緑に保つ設計は、削除済みの週次自動更新レーン(claude.yml)のための
#   ものだった。現在のDependabotのPRは所有者の手動マージであり、承認を求めても
#   運用は止まらない。このため取りこぼしの生じない「変更されたかどうか」の判定に変えた。
#
# テスト: .github/scripts/tests/test-check-dependency-additions.sh
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
    echo "::error::jq が見つかりません。判定ができないため fail-closed で失敗します。"
    exit 1
fi

MERGE_BASE=$(git merge-base "$BASE_SHA" "$HEAD_SHA")
changed_files=$(git diff --name-only "$MERGE_BASE" "$HEAD_SHA")

detected=""

# --- frontend/package.json: dependencies + devDependencies のキー集合を比較 ---
pkg_keys() {
    jq -r '((.dependencies // {}) + (.devDependencies // {})) | keys[]' 2>/dev/null | sort -u
}

if printf '%s\n' "$changed_files" | grep -q '^frontend/package\.json$'; then
    base_keys=$(git show "$MERGE_BASE:frontend/package.json" | pkg_keys || true)
    head_keys=$(git show "$HEAD_SHA:frontend/package.json" | pkg_keys || true)
    new_npm=$(comm -13 <(echo "$base_keys") <(echo "$head_keys") || true)
    if [ -n "$new_npm" ]; then
        detected+="[frontend/package.json に追加された依存]"$'\n'"$new_npm"$'\n'
    fi
fi

# --- backend のビルド定義ファイル: 変更されたこと自体を検知する ---
changed_build=$(printf '%s\n' "$changed_files" |
    grep -E '^backend/(.*\.(gradle|gradle\.kts|versions\.toml)|gradle/wrapper/gradle-wrapper\.properties)$' || true)
if [ -n "$changed_build" ]; then
    detected+="[変更された backend のビルド定義ファイル]"$'\n'"$changed_build"$'\n'
fi

if [ -z "$detected" ]; then
    echo "承認が必要な変更なし。"
    exit 0
fi

{
    echo "### :package: 承認が必要な変更を検出"
    echo ""
    echo '```'
    echo "$detected"
    echo '```'
} >>"${GITHUB_STEP_SUMMARY:-/dev/null}"

if [ "$OWNER_APPROVED" = "true" ]; then
    echo "変更を検出しましたが、リポジトリ所有者のApprove済みのため通過します。"
    echo "$detected"
    exit 0
fi

echo "::error::依存の追加、またはbackendのビルド定義の変更が検出されました。リポジトリ所有者のApproveレビュー後にこのチェックは緑になります。"
echo "$detected"
exit 1
