import { paths } from "@/config/paths";
import { ChangePasswordContainer } from "@/features/user";
import { useUserAuthStore } from "@/stores";
import { renderWithProviders, resetStoresAndMocks } from "@/test";
import type { User } from "@/types";
import { screen } from "@testing-library/react";
import { Route, Routes } from "react-router";

/**
 * テスト用のユーザーを作る
 */
const createUser = (overrides: Partial<User>): User => ({
    id: "user-1",
    email: "test-user@example.com",
    username: "test-user",
    profileImage: null,
    twoFactorAuthEnabled: false,
    hasPassword: true,
    authProviders: [],
    roles: ["USER"],
    emailVerified: true,
    pendingEmail: null,
    ...overrides,
});

/**
 * パスワードの変更の画面を、ログインの画面への移動が見える形で描く
 */
const renderChangePassword = () =>
    renderWithProviders(
        <Routes>
            <Route path={paths.password.change} element={<ChangePasswordContainer />} />
            <Route path={paths.login} element={<div>ログインの画面</div>} />
        </Routes>,
        { route: paths.password.change },
    );

describe("ChangePasswordContainer", () => {
    beforeEach(() => {
        resetStoresAndMocks([]);
    });

    it("PASSWORD_WITH_PROVIDER ではログインの画面へ移さない", () => {
        // メールアドレスが設定待ちで、パスワードと外部連携があるアカウント
        useUserAuthStore.getState().setLogin(
            createUser({
                email: null,
                emailVerified: false,
                pendingEmail: "pending@example.com",
                authProviders: ["google"],
            }),
        );

        renderChangePassword();

        expect(screen.getByPlaceholderText("現在のパスワード")).toBeInTheDocument();
        expect(screen.queryByText("ログインの画面")).not.toBeInTheDocument();
    });

    it("EMAIL_PASSWORD ではパスワードの変更の画面を出す", () => {
        useUserAuthStore.getState().setLogin(createUser({}));

        renderChangePassword();

        expect(screen.getByPlaceholderText("現在のパスワード")).toBeInTheDocument();
        expect(screen.queryByText("ログインの画面")).not.toBeInTheDocument();
    });

    it("パスワードが無いアカウントではログインの画面へ移す", () => {
        useUserAuthStore.getState().setLogin(createUser({ hasPassword: false, authProviders: ["github"] }));

        renderChangePassword();

        expect(screen.getByText("ログインの画面")).toBeInTheDocument();
        expect(screen.queryByPlaceholderText("現在のパスワード")).not.toBeInTheDocument();
    });
});
