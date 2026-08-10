#!/usr/bin/env bash
# =====================================================================
# 逃げ道封鎖チェック(guardrails CI から実行)
#
# 「見かけの合格」を作る変更を機械的に拒否する。
#   1. 品質ゲート配線の改変(apply from 行の削除 / violationRules の上書き)
#   2. テストの skip/only/@Disabled 追加
#   3. @ts-ignore / @ts-expect-error / @ts-nocheck の追加
#   4. eslint-disable インラインコメントの追加
#   5. 既存テストのアサーション変更・削除(PR本文に Test-Change-Justification: が無ければ赤)
#   6. ゲート隣接ファイルの変更(リポジトリ所有者のApproveが無ければ赤。
#      CODEOWNERSの必須レビューと二重の防御)
#
# 環境変数:
#   PR_BODY        : PR本文(5の理由記載チェックに使用)
#   OWNER_APPROVED : "true" なら所有者Approve済み(6の判定に使用)
#
# 使い方: check-escape-hatches.sh <base_sha> <head_sha>
# =====================================================================
set -euo pipefail

BASE_SHA="${1:?base sha required}"
HEAD_SHA="${2:?head sha required}"
PR_BODY="${PR_BODY:-}"
OWNER_APPROVED="${OWNER_APPROVED:-false}"

MERGE_BASE=$(git merge-base "$BASE_SHA" "$HEAD_SHA")
DIFF=$(git diff --unified=0 "$MERGE_BASE" "$HEAD_SHA")

violations=0

report() {
    violations=$((violations + 1))
    echo "::error::[$1] $2"
    {
        echo "### :no_entry: $1"
        echo ""
        echo '```'
        echo "$2"
        echo '```'
    } >>"${GITHUB_STEP_SUMMARY:-/dev/null}"
}

# 追加行(+ で始まり +++ でない)を「ファイル名: 行」形式で抽出する
# 注: 正規表現は -v ではなく環境変数で渡す(-v はバックスラッシュを二重処理するため)
added_lines_for() {
    PATH_REGEX="$1" awk '
        BEGIN { pat = ENVIRON["PATH_REGEX"] }
        /^diff --git/ { file=$4; sub(/^b\//, "", file); matched = (file ~ pat) }
        matched && /^\+/ && !/^\+\+\+/ { print file ": " substr($0, 2) }
    ' <<<"$DIFF"
}

# 削除行(- で始まり --- でない)を「ファイル名: 行」形式で抽出する
removed_lines_for() {
    PATH_REGEX="$1" awk '
        BEGIN { pat = ENVIRON["PATH_REGEX"] }
        /^diff --git/ { file=$4; sub(/^b\//, "", file); matched = (file ~ pat) }
        matched && /^-/ && !/^---/ { print file ": " substr($0, 2) }
    ' <<<"$DIFF"
}

changed_files=$(git diff --name-only "$MERGE_BASE" "$HEAD_SHA")

# --- 1. 品質ゲート配線(差分の有無に関係なく常時検証) ---
if ! grep -q "apply from: 'gradle/quality.gradle'" backend/build.gradle; then
    report "品質ゲート配線の破壊" "backend/build.gradle に apply from: 'gradle/quality.gradle' がありません。品質ゲート定義(quality.gradle)が無効化されています。"
fi

if grep -qE 'violationRules|jacocoTestCoverageVerification' backend/build.gradle; then
    report "カバレッジ閾値の上書き" "backend/build.gradle に violationRules / jacocoTestCoverageVerification の記述があります。閾値定義は gradle/quality.gradle のみで行ってください。"
fi

# --- 2. テストの skip/only 追加(TS/JS) ---
found=$(added_lines_for '^frontend/.*\.(ts|tsx|js|jsx)$' | grep -E '\.(skip|only)\s*\(|\b(xit|xdescribe|xtest)\s*\(' || true)
if [ -n "$found" ]; then
    report "テストの skip/only 追加" "$found"
fi

# --- 2b. @Disabled の追加(Java) ---
found=$(added_lines_for '^backend/src/test/.*\.java$' | grep -E '@Disabled' || true)
if [ -n "$found" ]; then
    report "Javaテストの @Disabled 追加" "$found"
fi

# --- 3. TypeScript 型チェック抑止の追加 ---
found=$(added_lines_for '^frontend/.*\.(ts|tsx)$' | grep -E '@ts-ignore|@ts-expect-error|@ts-nocheck' || true)
if [ -n "$found" ]; then
    report "TypeScript 型チェック抑止の追加" "$found"
fi

# --- 4. eslint-disable インラインの追加 ---
found=$(added_lines_for '^frontend/src/.*\.(ts|tsx|js|jsx)$' | grep -E 'eslint-disable' || true)
if [ -n "$found" ]; then
    report "eslint-disable インライン追加" "$found
例外が必要な場合はインラインではなく eslint.config.js(所有者承認必須)へ理由付きで定義してください。"
fi

# --- 5. 既存テストのアサーション変更・削除 ---
ts_asserts=$(removed_lines_for '^frontend/.*\.test\.(ts|tsx)$' | grep -E '\bexpect\s*\(' || true)
java_asserts=$(removed_lines_for '^backend/src/test/.*\.java$' | grep -E '\bassert[A-Za-z]*\s*\(|\bverify\s*\(|\bassertThatThrownBy' || true)
if [ -n "$ts_asserts$java_asserts" ]; then
    if ! echo "$PR_BODY" | grep -q 'Test-Change-Justification:'; then
        report "既存テストのアサーション変更・削除" "アサーションを含む行の変更・削除が検出されました。意図的な変更であれば PR 本文に「Test-Change-Justification: <理由>」を記載してください。
${ts_asserts}
${java_asserts}"
    else
        echo "アサーション変更を検出しましたが、PR本文に Test-Change-Justification: の記載があるため通過します。" >>"${GITHUB_STEP_SUMMARY:-/dev/null}"
    fi
fi

# --- 6. ゲート隣接ファイルの変更(所有者Approveが必要) ---
gate_files=$(echo "$changed_files" | grep -E '^(\.github/|\.claude/|frontend/eslint\.config\.js|frontend/vite\.config\.ts|backend/gradle/quality\.gradle|backend/config/|backend/src/test/java/com/example/keirekipro/unit/architecture/)' || true)
if [ -n "$gate_files" ]; then
    if [ "$OWNER_APPROVED" != "true" ]; then
        report "ゲート設定ファイルの変更(所有者未承認)" "以下のゲート設定ファイルが変更されています。リポジトリ所有者のApproveレビュー後にこのチェックは緑になります。
$gate_files"
    else
        echo "ゲート設定ファイルの変更は所有者Approve済みのため通過します。" >>"${GITHUB_STEP_SUMMARY:-/dev/null}"
    fi
fi

if [ "$violations" -gt 0 ]; then
    echo ""
    echo "逃げ道封鎖チェック: ${violations} 件の違反を検出しました。"
    exit 1
fi

echo "逃げ道封鎖チェック: 違反なし"
