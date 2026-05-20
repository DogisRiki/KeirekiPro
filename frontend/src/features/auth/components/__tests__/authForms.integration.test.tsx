import { screen, waitFor } from "@testing-library/react";
import type { AxiosResponse } from "axios";
import { Route, Routes } from "react-router";
import { vi } from "vitest";

vi.mock("@/lib", () => ({
    publicApiClient: {
        get: vi.fn(),
        post: vi.fn(),
    },
}));

vi.mock("@/hooks", () => ({
    getUserInfo: vi.fn(),
}));

import { paths } from "@/config/paths";
import {
    LoginContainer,
    LoginForm,
    RequestPasswordResetContainer,
    ResetPasswordContainer,
    TwoFactorContainer,
    UserRegisterContainer,
} from "@/features/auth";
import { getUserInfo } from "@/hooks";
import { publicApiClient } from "@/lib";
import { useErrorMessageStore, useNotificationStore, useUserAuthStore } from "@/stores";
import { renderWithProviders, resetStoresAndMocks } from "@/test";
import type { User } from "@/types";

const user: User = {
    id: "user-1",
    email: "test-user@example.com",
    username: "test-user",
    profileImage: null,
    twoFactorAuthEnabled: false,
    hasPassword: true,
    authProviders: [],
    roles: [],
};

describe("auth forms", () => {
    beforeEach(() => {
        resetStoresAndMocks([]);
        vi.mocked(publicApiClient.get).mockReset();
        vi.mocked(publicApiClient.post).mockReset();
        vi.mocked(getUserInfo).mockReset();
    });

    it("LoginContainerはログイン成功後に認証ストアを更新し職務経歴書一覧へ遷移すること", async () => {
        vi.mocked(publicApiClient.post).mockResolvedValueOnce({ status: 200, data: "" } as AxiosResponse<string>);
        vi.mocked(getUserInfo).mockResolvedValueOnce(user);

        const { user: uiUser } = renderWithProviders(
            <Routes>
                <Route path={paths.login} element={<LoginContainer />} />
                <Route path={paths.resume.list} element={<div>resume list destination</div>} />
            </Routes>,
            { route: paths.login },
        );

        await uiUser.type(screen.getByLabelText("メールアドレス"), "test-user@example.com");
        await uiUser.type(screen.getByLabelText("パスワード"), "pass1234");
        await uiUser.click(screen.getByRole("button", { name: "ログイン" }));

        expect(await screen.findByText("resume list destination")).toBeInTheDocument();
        expect(publicApiClient.post).toHaveBeenCalledWith("/auth/login", {
            email: "test-user@example.com",
            password: "pass1234",
        });
        expect(useUserAuthStore.getState().isAuthenticated).toBe(true);
        expect(useUserAuthStore.getState().user).toEqual(user);
    });

    it("LoginFormはloading中に送信できずfield errorが表示されること", () => {
        useErrorMessageStore.setState({
            message: "ログインに失敗しました。",
            errors: {
                email: ["メールアドレスを入力してください。"],
                password: ["パスワードを入力してください。"],
            },
        });

        renderWithProviders(
            <LoginForm
                email=""
                password=""
                onEmailChange={vi.fn()}
                onPasswordChange={vi.fn()}
                onSubmit={vi.fn()}
                onOidcLogin={vi.fn()}
                loading
            />,
        );

        expect(screen.getByRole("button", { name: "ログイン" })).toBeDisabled();
        expect(screen.getByText(/メールアドレスを入力してください。/)).toBeInTheDocument();
        expect(screen.getByText(/パスワードを入力してください。/)).toBeInTheDocument();
    });

    it("UserRegisterContainerは規約同意後に登録しログイン画面へ遷移してsuccess通知を設定すること", async () => {
        vi.mocked(publicApiClient.post).mockResolvedValueOnce({ data: undefined } as AxiosResponse<void>);

        const { user: uiUser } = renderWithProviders(
            <Routes>
                <Route path={paths.register} element={<UserRegisterContainer />} />
                <Route path={paths.login} element={<div>login destination</div>} />
            </Routes>,
            { route: paths.register },
        );

        const submitButton = screen.getByRole("button", { name: "登録" });
        expect(submitButton).toBeDisabled();

        await uiUser.type(screen.getByRole("textbox", { name: /メールアドレス/ }), "new-user@example.com");
        await uiUser.type(screen.getByRole("textbox", { name: /ユーザー名/ }), "new-user");
        const passwordInputs = screen.getAllByLabelText(/パスワード/);
        await uiUser.type(passwordInputs[0], "pass1234");
        await uiUser.type(passwordInputs[1], "pass1234");
        await uiUser.click(screen.getByRole("checkbox", { name: /利用規約/ }));
        await uiUser.click(screen.getByRole("checkbox", { name: /プライバシーポリシー/ }));
        await uiUser.click(submitButton);

        expect(await screen.findByText("login destination")).toBeInTheDocument();
        expect(publicApiClient.post).toHaveBeenCalledWith("/auth/register", {
            email: "new-user@example.com",
            username: "new-user",
            password: "pass1234",
            confirmPassword: "pass1234",
        });
        expect(useNotificationStore.getState()).toMatchObject({
            type: "success",
            isShow: true,
        });
    });

    it("RequestPasswordResetContainerは送信後にsuccess通知を設定すること", async () => {
        vi.mocked(publicApiClient.post).mockResolvedValueOnce({ data: undefined } as AxiosResponse<void>);

        const { user: uiUser } = renderWithProviders(<RequestPasswordResetContainer />);

        await uiUser.type(screen.getByRole("textbox", { name: /メールアドレス/ }), "reset@example.com");
        await uiUser.click(screen.getByRole("button", { name: "送信" }));

        await waitFor(() =>
            expect(publicApiClient.post).toHaveBeenCalledWith("/auth/password/reset/request", {
                email: "reset@example.com",
            }),
        );
        expect(useNotificationStore.getState()).toMatchObject({
            message: "パスワードリセット用メールを送信しました。",
            type: "success",
            isShow: true,
        });
    });

    it("ResetPasswordContainerはtoken検証後にパスワード変更しログイン画面へ遷移すること", async () => {
        vi.mocked(publicApiClient.post)
            .mockResolvedValueOnce({ data: undefined } as AxiosResponse<void>)
            .mockResolvedValueOnce({ data: undefined } as AxiosResponse<void>);

        const { user: uiUser } = renderWithProviders(
            <Routes>
                <Route path={paths.password.reset} element={<ResetPasswordContainer />} />
                <Route path={paths.login} element={<div>login destination</div>} />
            </Routes>,
            { route: "/password/reset/reset-token" },
        );

        await screen.findByPlaceholderText("新しいパスワード");
        await uiUser.type(screen.getByPlaceholderText("新しいパスワード"), "new-pass123");
        await uiUser.type(screen.getByPlaceholderText("新しいパスワード(確認)"), "new-pass123");
        await uiUser.click(screen.getByRole("button", { name: "パスワードを変更" }));

        expect(await screen.findByText("login destination")).toBeInTheDocument();
        expect(publicApiClient.post).toHaveBeenNthCalledWith(1, "/auth/password/reset/verify", {
            token: "reset-token",
        });
        expect(publicApiClient.post).toHaveBeenNthCalledWith(2, "/auth/password/reset", {
            token: "reset-token",
            password: "new-pass123",
            confirmPassword: "new-pass123",
        });
    });

    it("TwoFactorContainerは6桁入力後に認証しログイン状態を反映して一覧へ遷移すること", async () => {
        vi.mocked(publicApiClient.post).mockResolvedValueOnce({ data: undefined } as AxiosResponse<void>);
        vi.mocked(getUserInfo).mockResolvedValueOnce(user);

        const { user: uiUser } = renderWithProviders(
            <Routes>
                <Route path={paths.twoFactor} element={<TwoFactorContainer />} />
                <Route path={paths.resume.list} element={<div>resume list destination</div>} />
            </Routes>,
            { route: paths.twoFactor },
        );

        const submitButton = screen.getByRole("button", { name: "認証" });
        expect(submitButton).toBeDisabled();

        await uiUser.type(screen.getByRole("textbox"), "123456");
        await uiUser.click(submitButton);

        expect(await screen.findByText("resume list destination")).toBeInTheDocument();
        expect(publicApiClient.post).toHaveBeenCalledWith("/auth/2fa/verify", { code: "123456" });
        expect(useUserAuthStore.getState().user).toEqual(user);
    });
});
