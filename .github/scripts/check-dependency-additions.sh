#!/usr/bin/env bash
# =====================================================================
# 依存追加の人間ゲート(dependency-gate CI から実行)
#
# 判定: 対象の変更あり かつ 所有者のApproveなし -> exit 1(赤)。それ以外は exit 0(緑)
#
# 判定対象(いずれも「変更されたこと自体」を見る。中身は解析しない):
#   - frontend の取得元と防御設定
#     (pnpm-workspace.yaml / .npmrc / .pnpmfile.cjs / .pnpmfile.mjs)
#   - backend のビルドスクリプト
#     (*.gradle / *.gradle.kts。取得元の定義 repositories {} を含むため)
#
# 判定対象から外したもの(#182 で機械の関門に置き換えた):
#   - frontend/package.json / frontend/pnpm-lock.yaml
#   - backend の version catalog(*.versions.toml)
#   - backend/gradle/wrapper/gradle-wrapper.properties
#
#   これらは依存のバージョン宣言であり、次の3つが承認の代わりを務める。
#     - dependency-review: このPRで新しく増えた脆弱性を落とす
#     - dependency-cooldown: 公開から72時間を経過していないパッケージを落とす
#     - gradle-wrapper: 配布元のホストと公表チェックサムの一致を検証する
#
#   残した対象にはこれらの関門が効かない。dependency-review はレジストリを検証せず、
#   pnpm-workspace.yaml は overrides と供給網対策の設定そのものを含み、
#   ビルドスクリプトは任意コードで取得元の定義を持つ。
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
    grep -E '^frontend/(pnpm-workspace\.yaml|\.npmrc|\.pnpmfile\.(c|m)?js)$' || true)
if [ -n "$changed_frontend" ]; then
    detected+="[変更された frontend の取得元・防御設定]"$'\n'"$changed_frontend"$'\n'
fi

changed_build=$(git diff --name-only "$MERGE_BASE" "$HEAD_SHA" |
    grep -E '^backend/.*\.(gradle|gradle\.kts)$' || true)
if [ -n "$changed_build" ]; then
    detected+="[変更された backend のビルドスクリプト]"$'\n'"$changed_build"$'\n'
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

echo "::error::依存定義ファイルの変更が検出されました。リポジトリ所有者のApproveレビュー後にこのチェックは緑になります。"
echo "$detected"
exit 1
