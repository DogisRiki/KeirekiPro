import { expect, test, type Page } from "@playwright/test";

/**
 * 確認のリンクの画面、ログインの画面、ユーザー設定の画面で、メールアドレスの確認の文とボタンが出ることを確かめる
 *
 * スモークテストと同じく、バックエンドを起動せず、page.route で API の応答を作る。
 */

/**
 * 認証チェックAPI(GET /users/me)に未認証(401)を返させる
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
 * 認証チェックAPI(GET /users/me)に、ログイン済みの利用者を返させる
 */
const mockAuthenticated = async (
    page: Page,
    user: { email: string | null; emailVerified: boolean; pendingEmail: string | null; authProviders?: string[] },
): Promise<void> => {
    await page.route("**/users/me", (route) =>
        route.fulfill({
            status: 200,
            contentType: "application/json",
            body: JSON.stringify({
                id: "11111111-1111-1111-1111-111111111111",
                username: "テスト利用者",
                profileImage: null,
                twoFactorAuthEnabled: false,
                hasPassword: true,
                authProviders: [],
                roles: ["USER"],
                ...user,
            }),
        }),
    );
};

/**
 * 確認のリンクの結果ごとに、画面に出る文とボタン
 */
const verificationCases = [
    {
        result: "VERIFIED",
        passwordResetToken: null,
        message: "メールアドレスの確認が済み、手続きが完了しました。ログインしてください。",
        button: "ログイン画面へ",
    },
    {
        result: "PASSWORD_RESET_READY",
        passwordResetToken: "reset-token",
        message: "メールアドレスの確認が済みました。続けて新しいパスワードを設定してください。",
        button: "パスワードを変更",
    },
    {
        result: "ALREADY_VERIFIED",
        passwordResetToken: null,
        message: "メールアドレスの確認はすでに済んでいます。ログインしてください。",
        button: "ログイン画面へ",
    },
    {
        result: "EXPIRED",
        passwordResetToken: null,
        message: "このリンクは使えなくなっています。確認のメールを送り直してください。",
        button: "確認のメールを送り直す",
    },
    {
        result: "REGISTRATION_GONE",
        passwordResetToken: null,
        message: "このリンクは使えなくなっています。お手数ですが、もう一度登録してください。",
        link: "登録の画面へ",
    },
    {
        result: "EMAIL_TAKEN",
        passwordResetToken: null,
        message: "このメールアドレスは、すでにほかのアカウントが使っているため、使えません。",
    },
    {
        result: "INVALID",
        passwordResetToken: null,
        message: "このリンクは正しくありません。",
    },
] as const;

test.describe("メールアドレスの確認", () => {
    test.describe("確認のリンクの画面が result ごとに決まった文とボタンを出す", () => {
        for (const c of verificationCases) {
            test(`${c.result} の文とボタンを出し、リンクのトークンを API に送ること`, async ({ page }) => {
                const pageErrors: Error[] = [];
                page.on("pageerror", (error) => pageErrors.push(error));

                const sentTokens: string[] = [];
                await page.route("**/auth/email-verification/verify", (route) => {
                    sentTokens.push((route.request().postDataJSON() as { token: string }).token);
                    return route.fulfill({
                        status: 200,
                        contentType: "application/json",
                        body: JSON.stringify({ result: c.result, passwordResetToken: c.passwordResetToken }),
                    });
                });

                await page.goto("/email/verify#link-token");

                await expect(page.getByText(c.message)).toBeVisible();
                if ("button" in c) {
                    await expect(page.getByRole("button", { name: c.button, exact: true })).toBeVisible();
                }
                if ("link" in c) {
                    await expect(page.getByRole("link", { name: c.link, exact: true })).toBeVisible();
                }
                expect(sentTokens).toEqual(["link-token"]);
                // トークンをアドレスバーに残さない
                expect(new URL(page.url()).hash).toBe("");
                expect(pageErrors).toEqual([]);
            });
        }
    });

    test.describe("ログインの画面が 409 の kind ごとに確認がまだである文とボタンを出す", () => {
        const loginCases = [
            {
                kind: "PENDING_REGISTRATION",
                message: "登録はまだ済んでいません。確認のメールの中のリンクを押して、登録を済ませてください。",
                button: "確認のメールを送り直す",
            },
            {
                kind: "UNVERIFIED_ACCOUNT_EMAIL",
                message: "確認のメールを送り、メールの中のリンクを押して、メールアドレスの確認を済ませてください。",
                button: "確認のメールを送る",
            },
        ] as const;

        for (const c of loginCases) {
            test(`${c.kind} の文とボタンを出すこと`, async ({ page }) => {
                const pageErrors: Error[] = [];
                page.on("pageerror", (error) => pageErrors.push(error));

                await mockUnauthenticated(page);
                await page.route("**/auth/login", (route) =>
                    route.fulfill({
                        status: 409,
                        contentType: "application/json",
                        body: JSON.stringify({ kind: c.kind }),
                    }),
                );

                await page.goto("/login");
                await page.getByLabel("メールアドレス", { exact: true }).fill("user@example.com");
                await page.getByLabel("パスワード", { exact: true }).fill("Password123!");
                await page.getByRole("button", { name: "ログイン", exact: true }).click();

                await expect(page.getByText("メールアドレスの確認が済んでいません。")).toBeVisible();
                await expect(page.getByText(c.message)).toBeVisible();
                await expect(page.getByRole("button", { name: c.button, exact: true })).toBeVisible();
                expect(pageErrors).toEqual([]);
            });
        }
    });

    test.describe("ユーザー設定の画面が emailVerified と pendingEmail に応じて確認待ちの表示とボタンを出す", () => {
        test("設定待ちのメールアドレスを確認待ちとして出し、ボタンで確認のメールを送ること", async ({ page }) => {
            const pageErrors: Error[] = [];
            page.on("pageerror", (error) => pageErrors.push(error));

            await mockAuthenticated(page, {
                email: null,
                emailVerified: false,
                pendingEmail: "new@example.com",
                authProviders: ["google"],
            });
            let sendCount = 0;
            await page.route("**/users/me/email-verification", (route) => {
                sendCount += 1;
                return route.fulfill({ status: 204 });
            });

            await page.goto("/user");

            await expect(page.getByText("確認待ちのメールアドレス: new@example.com")).toBeVisible();
            await page.getByRole("button", { name: "確認のメールを送る", exact: true }).click();
            await expect(
                page.getByText("確認のメールを送りました。メールの中の確認のリンクを押してください。"),
            ).toBeVisible();
            expect(sendCount).toBe(1);
            expect(pageErrors).toEqual([]);
        });

        test("確認がまだのメールアドレスを確認待ちとして出すこと", async ({ page }) => {
            await mockAuthenticated(page, {
                email: "unverified@example.com",
                emailVerified: false,
                pendingEmail: null,
            });

            await page.goto("/user");

            await expect(page.getByText("確認待ちのメールアドレス: unverified@example.com")).toBeVisible();
            await expect(page.getByRole("button", { name: "確認のメールを送る", exact: true })).toBeVisible();
        });

        test("確認済みで設定待ちが無ければ確認待ちの表示を出さないこと", async ({ page }) => {
            await mockAuthenticated(page, {
                email: "verified@example.com",
                emailVerified: true,
                pendingEmail: null,
            });

            await page.goto("/user");

            await expect(page.getByLabel("ユーザー名")).toHaveValue("テスト利用者");
            await expect(page.getByText(/確認待ちのメールアドレス/)).toHaveCount(0);
            await expect(page.getByRole("button", { name: "確認のメールを送る", exact: true })).toHaveCount(0);
        });
    });
});
