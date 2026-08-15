#!/usr/bin/env bash
# =====================================================================
# 依存追加の人間ゲート(dependency-gate CI から実行)
#
# 判定: 対象の変更あり かつ 所有者のApproveなし -> exit 1(赤)。それ以外は exit 0(緑)
#
# 判定対象(いずれも「変更されたこと自体」を見る。中身は解析しない):
#   - frontend の依存定義ファイル
#     (package.json / pnpm-lock.yaml / pnpm-workspace.yaml / .npmrc / .pnpmfile.cjs / .pnpmfile.mjs)
#   - backend のビルド定義ファイル
#     (*.gradle / *.gradle.kts / *.versions.toml / gradle-wrapper.properties。
#     wrapperを含めるのは、Gradle本体の配布物が変われば実行されるコードも変わるため)
#
# なぜ中身を解析しないのか:
#   backend では以前、正規表現で依存座標とプラグインIDを抽出していたが、Gradleのビルド定義は
#   変数・条件分岐・Kotlin DSL・version catalog・動的な指定を許すため、静的な文字列一致では
#   原理的に網羅できない。実際にレビューで apply(plugin:) / apply false / 同一行の複数宣言 /
#   他ファイルで宣言済みIDの適用 といった迂回経路が次々に見つかり、パターンを足し続ける
#   状態になっていた。このため取りこぼしの生じない「変更されたかどうか」の判定に変えた。
#
#   frontend も同じ理由で同じ方式にした。以前は package.json の dependencies /
#   devDependencies のキー集合だけを比較しており、次の3つが素通りしていた。
#     - バージョン更新(意図的に通していた)
#     - 推移的依存の変化(pnpm-lock.yaml にしか現れない)
#     - overrides による差し替え(pnpm-workspace.yaml。npm alias 構文を使えば
#       任意の依存を別のパッケージに置き換えられる)
#   2026-03-31 の axios 改ざんは、悪意あるコードが推移的依存として入った事例であり、
#   キー集合の比較では検知できない。
#
# 報告について:
#   pnpm-lock.yaml から新しく増えたパッケージ名を抽出してSummaryに出す。所有者が承認する
#   ときに見るべきものを提供するためのもので、判定には一切使わない。解析に漏れがあっても
#   ゲートは緩まない(判定はファイルが変更されたかどうかで既に決まっている)。
#
# テスト: .github/scripts/tests/test-check-dependency-additions.sh
# 環境変数: OWNER_APPROVED が "true" ならリポジトリ所有者のApprove済み
# 使い方: check-dependency-additions.sh <base_sha> <head_sha>
# =====================================================================
set -euo pipefail

BASE_SHA="${1:?base sha required}"
HEAD_SHA="${2:?head sha required}"
OWNER_APPROVED="${OWNER_APPROVED:-false}"

MERGE_BASE=$(git merge-base "$BASE_SHA" "$HEAD_SHA")

detected=""

# --- 変更されたこと自体を検知する対象(grep は -q 無しで全入力を読む) ---
changed_frontend=$(git diff --name-only "$MERGE_BASE" "$HEAD_SHA" |
    grep -E '^frontend/(package\.json|pnpm-lock\.yaml|pnpm-workspace\.yaml|\.npmrc|\.pnpmfile\.(c|m)?js)$' || true)
if [ -n "$changed_frontend" ]; then
    detected+="[変更された frontend の依存定義ファイル]"$'\n'"$changed_frontend"$'\n'
fi

changed_build=$(git diff --name-only "$MERGE_BASE" "$HEAD_SHA" |
    grep -E '^backend/(.*\.(gradle|gradle\.kts|versions\.toml)|gradle/wrapper/gradle-wrapper\.properties)$' || true)
if [ -n "$changed_build" ]; then
    detected+="[変更された backend のビルド定義ファイル]"$'\n'"$changed_build"$'\n'
fi

if [ -z "$detected" ]; then
    echo "承認が必要な変更なし。"
    exit 0
fi

# --- 報告用: pnpm-lock.yaml に新しく現れたパッケージ名(判定には使わない) ---
# packages: セクションのキー "  name@version:" から name を取り出す。
# スコープ付き("@scope/pkg@1.0.0")に対応するため、最後の @ より前を名前とする。
# スコープ付きの名前は lockfile 上で '...' と引用されるため、引用符を剥がしてから返す
# (剥がさないと、承認者が一覧の名前をそのまま npm で検索しても見つからない)。
lock_names() {
    awk -v q="'" '/^packages:/ { inpkg = 1; next }
         /^[a-z]/ { inpkg = 0 }
         inpkg && /^  [^ ].*:$/ {
             line = $0
             sub(/^  /, "", line)
             sub(/:$/, "", line)
             sub("^" q, "", line)
             sub(q "$", "", line)
             pos = 0
             for (i = length(line); i > 1; i--) {
                 if (substr(line, i, 1) == "@") { pos = i; break }
             }
             if (pos > 1) { print substr(line, 1, pos - 1) }
         }' | sort -u
}

case "$changed_frontend" in
*frontend/pnpm-lock.yaml*)
    base_names=$(git show "$MERGE_BASE:frontend/pnpm-lock.yaml" 2>/dev/null | lock_names || true)
    head_names=$(git show "$HEAD_SHA:frontend/pnpm-lock.yaml" 2>/dev/null | lock_names || true)
    new_names=$(comm -13 <(printf '%s\n' "$base_names") <(printf '%s\n' "$head_names") || true)
    if [ -n "$new_names" ]; then
        detected+="[pnpm-lock.yaml に新しく現れたパッケージ(報告のみ・判定には使わない)]"$'\n'"$new_names"$'\n'
    fi
    ;;
esac

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

echo "::error::依存定義ファイルの変更が検出されました。リポジトリ所有者のApproveレビュー後にこのチェックは緑になります。"
echo "$detected"
exit 1
