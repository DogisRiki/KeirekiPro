#!/usr/bin/env bash
# =====================================================================
# カナリアPR生成(ゲートの健康診断・月次)
#
# 3種の「わざと問題のある変更」をPRとして作成し、ゲート群が全て赤に
# できることを確認する。検出漏れは retrospective 経由でゲート追加が必須。
#
#   1. known-bug        : もっともらしいロジックバグ(+バグと整合するテスト)
#                         -> Codexレビュー(コード品質軸)が検出できるか
#   2. assertless-test  : アサーション無しテスト
#                         -> ESLint(sonarjs/assertions-in-tests)が検出できるか
#   3. skipped-test     : .skip付きテストの追加
#                         -> escape-hatchチェックが検出できるか
#
# 注意: カナリアPRには auto-merge を設定しない(絶対にマージしない)。
# 実行には workflow が bot の PAT(BOT_GITHUB_TOKEN)を使う
# (デフォルトのGITHUB_TOKENではPRのCIが発火しないため)。
# =====================================================================
set -euo pipefail

STAMP=$(date +%Y%m)
CANARY_DIR="frontend/src/utils"

git fetch origin main

# 既存の open なカナリアPRをクローズ
for pr in $(gh pr list --label canary --state open --json number --jq '.[].number'); do
    gh pr close "$pr" --comment "新しいカナリアサイクルの開始に伴いクローズ" --delete-branch || true
done

create_canary() {
    local name="$1"
    local file="$2"
    local content="$3"
    local title="$4"
    local expected="$5"
    local branch="canary/${name}-${STAMP}"

    git switch -c "$branch" origin/main
    printf '%s\n' "$content" > "$file"
    git add "$file"
    git commit -m "test: canary ${name} (${STAMP})" \
        -m "Changes:
- ゲート健康診断用のカナリア変更(${name})
Reason:
- 月次のゲート検出能力確認
BREAKING CHANGE: N/A
Related: N/A
Refs: N/A"
    git push -u origin "$branch"

    gh label create canary --description "ゲート健康診断用カナリアPR(マージ禁止)" --color 5319E7 2>/dev/null || true
    gh pr create \
        --title "[canary] ${title}" \
        --label canary \
        --body "## カナリアPR(マージ禁止)

ゲート健康診断(月次)の自動生成PR。**マージしないこと**。

- 種別: ${name}
- 期待される検出: ${expected}
- 監査手順: doc/開発フロー/監査手順.md

Refs: N/A"
    git switch - >/dev/null
}

# --- 1. known-bug: もっともらしいロジックバグ ---
# 年齢計算に見せかけて誕生日を考慮しない+1のバグ。テストはバグと整合しているため
# CI(テスト・lint)は通過する。Codexレビューのコード品質軸が検出すべき対象。
create_canary "known-bug" "$CANARY_DIR/canaryAgeUtils.ts" \
'/**
 * 生年月日から現在の年齢を計算する
 */
export const calcCanaryAge = (birthDate: Date): number => {
    const now = new Date();
    return now.getFullYear() - birthDate.getFullYear() + 1;
};' \
    "年齢計算ユーティリティの追加" \
    "codex-review(コード品質軸)がロジックバグ(誕生日未考慮・+1の誤り)を検出して赤になること"

# known-bug用のバグと整合するテスト(アサーションはあるが検証内容が誤り)
git switch "canary/known-bug-${STAMP}"
cat > "$CANARY_DIR/canaryAgeUtils.test.ts" <<'TEST_EOF'
import { calcCanaryAge } from "./canaryAgeUtils";

describe("calcCanaryAge", () => {
    it("生年から年齢を計算できること", () => {
        const birth = new Date(2000, 0, 1);
        const expected = new Date().getFullYear() - 2000 + 1;
        expect(calcCanaryAge(birth)).toBe(expected);
    });
});
TEST_EOF
git add "$CANARY_DIR/canaryAgeUtils.test.ts"
git commit -m "test: canary known-bug companion test (${STAMP})" \
    -m "Changes:
- カナリアバグと整合するテストの追加
Reason:
- CIを通過させ、Codexレビューの検出能力を測るため
BREAKING CHANGE: N/A
Related: N/A
Refs: N/A"
git push origin "canary/known-bug-${STAMP}"
git switch - >/dev/null

# --- 2. assertless-test: アサーション無しテスト ---
create_canary "assertless-test" "$CANARY_DIR/canaryAssertless.test.ts" \
'describe("canary assertless", () => {
    it("何も検証しないテスト", () => {
        const value = 1 + 1;
        console.log(value);
    });
});' \
    "ユーティリティテストの追加" \
    "frontend-test(ESLint sonarjs/assertions-in-tests)が赤になること"

# --- 3. skipped-test: .skip付きテストの追加 ---
create_canary "skipped-test" "$CANARY_DIR/canarySkipped.test.ts" \
'describe("canary skipped", () => {
    it.skip("スキップされたテスト", () => {
        expect(1 + 1).toBe(2);
    });
});' \
    "テストの追加" \
    "escape-hatchチェック(.skip追加の検知)が赤になること"

echo "カナリアPRを3件作成しました。各PRのチェックが期待通り赤になることを監査で確認してください。"
