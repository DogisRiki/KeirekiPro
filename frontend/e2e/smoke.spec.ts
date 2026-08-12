import { expect, test, type Page } from "@playwright/test";

/**
 * 認証チェックAPI(GET /users/me)に未認証(401)を返させる
 *
 * バックエンドを起動しないため、モックしないとこのリクエストはネットワークエラーになる。
 * その場合、axiosの共通エラーインターセプタがサーバーエラー画面へ遷移させてしまい、
 * 目的の画面が描画されない。401であればリクエスト元がスキップ指定付きのため
 * トークンリフレッシュも走らず、未認証としてそのまま画面が描画される。
 */
const mockUnauthenticated = async (page: Page): Promise<void> => {
    await page.route("**/users/me", (route) =>
        route.fulfill({
            status: 401,
            contentType: "application/json",
            body: JSON.stringify({ message: "Unauthorized" }),
        }),
    );
};

/**
 * スモークテスト: アプリが起動して主要導線が描画されること
 *
 * バックエンド無しで成立する検証に限定する。
 */
test.describe("スモーク", () => {
    test("ログイン画面が描画され、未捕捉エラーが発生しないこと", async ({ page }) => {
        const pageErrors: Error[] = [];
        page.on("pageerror", (error) => pageErrors.push(error));

        await mockUnauthenticated(page);
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
