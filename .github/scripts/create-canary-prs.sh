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
#   4. backend-failure  : 意図的に失敗するJavaテスト
#                         -> detect-changes が backend の変更を拾い、
#                            backend-test が実際に実行されて赤になるか
#   5. vulnerable-dep   : 脆弱な推移的依存を引く版への差し替え
#                         -> 依存グラフの生成から送信・取り込み・比較・
#                            アドバイザリ照合までの全区間が動いているか
#
# 4と5は1〜3と役割が違う。1〜3は検査そのものの検出能力を見るが、
# 4と5は「検査が実行されているか」を見る。
#
# 4: ci.yaml の paths-filter が backend/** を拾わなくなると backend-test は
#    スキップされ、スキップは Success として報告されるため、テストが1本も
#    走らないままマージできてしまう。カナリア1〜3は全て frontend を触るため
#    この経路は覆われていない。
#
# 5: 依存グラフが空でも送信は成功し、dependency-review は「追加0件」と判定して
#    緑になる。生成の空洞化は毎PRの check-dependency-snapshot.sh が見るが、
#    送信より後(GitHubへの取り込み・compare API・アドバイザリ照合)は
#    実データで通してみるまで分からない。
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
    mkdir -p "$(dirname "$file")"
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

# --- 4. backend-failure: 意図的に失敗するJavaテスト ---
# アーキテクチャテストのディレクトリは置き場所にしない(ゲート設定ファイル扱いになり、
# escape-hatch の別系統で赤になって理由が判別できなくなるため)。
create_canary "backend-failure" \
    "backend/src/test/java/com/example/keirekipro/unit/shared/CanaryFailingTest.java" \
'package com.example.keirekipro.unit.shared;

import static org.assertj.core.api.Assertions.assertThat;

import org.junit.jupiter.api.Test;

/**
 * ゲート健康診断用のカナリア。意図的に失敗する。
 */
class CanaryFailingTest {

    @Test
    void 意図的に失敗するカナリアテスト() {
        assertThat(1 + 1).isEqualTo(3);
    }
}' \
    "backendテストの追加" \
    "backend-test が実行されて赤になること(スキップは検出漏れ)"

# --- 5. vulnerable-dep: 脆弱な推移的依存を引く版への差し替え ---
# openhtmltopdf 1.0.7 は pdfbox 2.0.22 を引く。2.0.22 には medium のアドバイザリが
# 4件あり(GHSA-fg3j-q579-v8x4 / GHSA-7grw-6pjh-jpc9 / GHSA-2h3j-m7gr-25xj /
# GHSA-6vqp-h455-42mr)、fail-on-severity: moderate に掛かる。
#
# 1.0.9 は pdfbox 2.0.24 を引くため不発になる。版を変えるときはPOMとアドバイザリの
# 対応を必ず確認すること。
#
# カタログのみの差分なので dependency-gate の対象外。旧版は2021年公開のため
# dependency-cooldown も緑になる。
CANARY_DEP_VERSION="1.0.7"
branch="canary/vulnerable-dep-${STAMP}"
git switch -c "$branch" origin/main
sed -i "s/^openhtmltopdf = \".*\"/openhtmltopdf = \"${CANARY_DEP_VERSION}\"/" backend/gradle/libs.versions.toml
# キー名が変わると sed が空振りし、差分が無いまま commit で落ちる。
# 5件目だけ欠けた状態は監査の件数確認で捕捉されるが、原因が分かるのは翌月に
# なるため、ここで即座に止める
if ! grep -q "^openhtmltopdf = \"${CANARY_DEP_VERSION}\"" backend/gradle/libs.versions.toml; then
    echo "::error::openhtmltopdf の行を書き換えられませんでした。キー名が変わっていないか確認してください。"
    exit 1
fi
git add backend/gradle/libs.versions.toml
git commit -m "test: canary vulnerable-dep (${STAMP})" \
    -m "Changes:
- ゲート健康診断用のカナリア変更(vulnerable-dep)
Reason:
- 月次のゲート検出能力確認
BREAKING CHANGE: N/A
Related: N/A
Refs: N/A"
git push -u origin "$branch"
gh pr create \
    --title "[canary] 依存バージョンの差し替え" \
    --label canary \
    --body "## カナリアPR(マージ禁止)

ゲート健康診断(月次)の自動生成PR。**マージしないこと**。

- 種別: vulnerable-dep
- 期待される検出: dependency-review が pdfbox のアドバイザリで赤になること(スキップは検出漏れ)
- 監査手順: doc/開発フロー/監査手順.md

Refs: N/A"
git switch - >/dev/null

echo "カナリアPRを5件作成しました。各PRのチェックが期待通り赤になることを監査で確認してください。"
