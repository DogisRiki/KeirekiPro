import { expect, test } from "@playwright/test";

/**
 * スモークテスト: アプリが起動して主要導線が描画されること
 *
 * バックエンド無しで成立する検証に限定する。
 * (認証チェックAPIの失敗はローダーが握りつぶし、ログイン画面はそのまま描画される)
 */
test.describe("スモーク", () => {
    test("ログイン画面が描画され、未捕捉エラーが発生しないこと", async ({ page }) => {
        const pageErrors: Error[] = [];
        page.on("pageerror", (error) => pageErrors.push(error));

        await page.goto("/login");

        await expect(page.getByRole("button", { name: "ログイン", exact: true })).toBeVisible();
        expect(pageErrors).toEqual([]);
    });

    test("利用規約ページが描画されること", async ({ page }) => {
        const pageErrors: Error[] = [];
        page.on("pageerror", (error) => pageErrors.push(error));

        await page.goto("/terms");

        await expect(page.getByText("利用規約").first()).toBeVisible();
        expect(pageErrors).toEqual([]);
    });
});
