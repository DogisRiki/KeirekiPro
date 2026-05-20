import { screen, waitFor, within } from "@testing-library/react";
import type { AxiosResponse } from "axios";
import { Route, Routes } from "react-router";
import { vi } from "vitest";

vi.mock("@/lib", () => ({
    protectedApiClient: {
        get: vi.fn(),
        put: vi.fn(),
        patch: vi.fn(),
        post: vi.fn(),
        delete: vi.fn(),
    },
}));

import { paths } from "@/config/paths";
import {
    ChangePasswordContainer,
    ChangePasswordForm,
    SetEmailAndPasswordContainer,
    SettingUserContainer,
    SettingUserForm,
} from "@/features/user";
import { protectedApiClient } from "@/lib";
import { useErrorMessageStore, useNotificationStore, useUserAuthStore } from "@/stores";
import { renderWithProviders, resetStoresAndMocks } from "@/test";
import type { User } from "@/types";

const baseUser: User = {
    id: "user-1",
    email: "user@example.com",
    username: "current-user",
    profileImage: null,
    twoFactorAuthEnabled: false,
    hasPassword: true,
    authProviders: ["google"],
    roles: [],
};

const messages = {
    emailPasswordStatusLabel: "パスワード設定済み",
    emailPasswordNavigationMessage: "パスワードを変更できます",
    emailPasswordIsWarning: false,
    emailPasswordLinkPath: paths.password.change,
    providerMessage: null,
};

describe("user forms", () => {
    beforeEach(() => {
        resetStoresAndMocks([]);
        vi.mocked(protectedApiClient.get).mockReset();
        vi.mocked(protectedApiClient.put).mockReset();
        vi.mocked(protectedApiClient.patch).mockReset();
        vi.mocked(protectedApiClient.post).mockReset();
        vi.mocked(protectedApiClient.delete).mockReset();
        vi.mocked(protectedApiClient.get).mockResolvedValue({ data: baseUser } as AxiosResponse<User>);
    });

    it("SettingUserContainerは保存後に更新後ユーザーをストアとsuccess通知へ反映すること", async () => {
        const updatedUser = { ...baseUser, username: "updated-user", twoFactorAuthEnabled: true };
        useUserAuthStore.getState().setLogin(baseUser);
        vi.mocked(protectedApiClient.put).mockResolvedValueOnce({ data: updatedUser } as AxiosResponse<User>);

        const { user } = renderWithProviders(<SettingUserContainer />);

        const usernameInput = await screen.findByRole("textbox", { name: /ユーザー名/ });
        await user.clear(usernameInput);
        await user.type(usernameInput, "updated-user");
        await user.click(screen.getByRole("checkbox", { name: /二段階認証/ }));
        await user.click(screen.getByRole("button", { name: "保存" }));

        await waitFor(() =>
            expect(protectedApiClient.put).toHaveBeenCalledWith("/users/me", expect.any(FormData), expect.any(Object)),
        );
        const formData = vi.mocked(protectedApiClient.put).mock.calls[0][1] as FormData;
        expect(formData.get("username")).toBe("updated-user");
        expect(formData.get("twoFactorAuthEnabled")).toBe("true");
        expect(useUserAuthStore.getState().user).toEqual(updatedUser);
        expect(useNotificationStore.getState()).toMatchObject({
            message: "ユーザー情報を更新しました。",
            type: "success",
            isShow: true,
        });
    });

    it("SettingUserContainerはプロバイダー解除をUIから反映すること", async () => {
        useUserAuthStore.getState().setLogin(baseUser);
        vi.mocked(protectedApiClient.delete).mockResolvedValueOnce({ data: undefined } as AxiosResponse<void>);

        const { user } = renderWithProviders(<SettingUserContainer />);

        await user.click(await screen.findByRole("button", { name: "解除する" }));

        await waitFor(() => expect(protectedApiClient.delete).toHaveBeenCalledWith("/users/me/auth-provider/google"));
        expect(useUserAuthStore.getState().user?.authProviders).toEqual([]);
        expect(useNotificationStore.getState()).toMatchObject({
            message: "連携を解除しました。",
            type: "success",
            isShow: true,
        });
    });

    it("SettingUserContainerは退会確認のcancelでは削除せずconfirmでログアウトしてログイン画面へ遷移すること", async () => {
        useUserAuthStore.getState().setLogin(baseUser);
        vi.mocked(protectedApiClient.delete).mockResolvedValueOnce({ data: undefined } as AxiosResponse<void>);

        const { user } = renderWithProviders(
            <Routes>
                <Route path={paths.user} element={<SettingUserContainer />} />
                <Route path={paths.login} element={<div>login destination</div>} />
            </Routes>,
            { route: paths.user },
        );

        await user.click(await screen.findByRole("button", { name: "退会" }));
        await user.click(within(screen.getByRole("dialog")).getByRole("button", { name: "いいえ" }));
        await waitFor(() => expect(screen.queryByRole("dialog")).not.toBeInTheDocument());
        expect(protectedApiClient.delete).not.toHaveBeenCalled();

        await user.click(screen.getByRole("button", { name: "退会" }));
        await user.click(within(screen.getByRole("dialog")).getByRole("button", { name: "はい" }));

        expect(await screen.findByText("login destination")).toBeInTheDocument();
        expect(protectedApiClient.delete).toHaveBeenCalledWith("/users/me");
        expect(useUserAuthStore.getState().isAuthenticated).toBe(false);
    });

    it("SettingUserFormはloading中に保存できずfield errorが表示されること", () => {
        useErrorMessageStore.setState({
            message: null,
            errors: {
                username: ["ユーザー名を入力してください。"],
                authProviders: ["連携を解除できません。"],
            },
        });

        renderWithProviders(
            <SettingUserForm
                email="user@example.com"
                username=""
                onUsernameChange={vi.fn()}
                profileImageUrl={null}
                onProfileImageChange={vi.fn()}
                twoFactorEnabled={false}
                twoFactorDisabled={false}
                onToggleTwoFactor={vi.fn()}
                authProviders={[]}
                canRemoveProvider={false}
                onRemoveProvider={vi.fn()}
                messages={messages}
                onSave={vi.fn()}
                onDelete={vi.fn()}
                loading
            />,
        );

        expect(screen.getByRole("button", { name: "保存" })).toBeDisabled();
        expect(screen.getByText(/ユーザー名を入力してください。/)).toBeInTheDocument();
        expect(screen.getByText(/連携を解除できません。/)).toBeInTheDocument();
    });

    it("ChangePasswordContainerは成功後に入力値をクリアしsuccess通知を設定すること", async () => {
        useUserAuthStore.getState().setLogin({ ...baseUser, authProviders: [] });
        vi.mocked(protectedApiClient.patch).mockResolvedValueOnce({ data: undefined } as AxiosResponse<void>);

        const { user } = renderWithProviders(<ChangePasswordContainer />);

        const nowPasswordInput = screen.getByPlaceholderText("現在のパスワード");
        const newPasswordInput = screen.getByPlaceholderText("新しいパスワード");
        await user.type(nowPasswordInput, "current-pass");
        await user.type(newPasswordInput, "next-pass");
        await user.click(screen.getByRole("button", { name: "変更" }));

        await waitFor(() =>
            expect(protectedApiClient.patch).toHaveBeenCalledWith("/users/me/password", {
                nowPassword: "current-pass",
                newPassword: "next-pass",
            }),
        );
        expect(nowPasswordInput).toHaveValue("");
        expect(newPasswordInput).toHaveValue("");
        expect(useNotificationStore.getState()).toMatchObject({
            message: "パスワードを変更しました。",
            type: "success",
            isShow: true,
        });
    });

    it("ChangePasswordFormはloading中に送信できずfield errorが表示されること", () => {
        useErrorMessageStore.setState({
            message: null,
            errors: {
                nowPassword: ["現在のパスワードを入力してください。"],
                newPassword: ["新しいパスワードを入力してください。"],
            },
        });

        renderWithProviders(
            <ChangePasswordForm
                nowPassword=""
                newPassword=""
                onNowPasswordChange={vi.fn()}
                onNewPasswordChange={vi.fn()}
                onSubmit={vi.fn()}
                loading
            />,
        );

        expect(screen.getByRole("button", { name: "変更" })).toBeDisabled();
        expect(screen.getByText(/現在のパスワードを入力してください。/)).toBeInTheDocument();
        expect(screen.getByText(/新しいパスワードを入力してください。/)).toBeInTheDocument();
    });

    it("SetEmailAndPasswordContainerはprovider onlyではemailを含めて送信し更新後ユーザーを反映すること", async () => {
        const providerOnlyUser = {
            ...baseUser,
            email: null,
            hasPassword: false,
            authProviders: ["google" as const],
        };
        const updatedUser = {
            ...baseUser,
            email: "provider@example.com",
            hasPassword: true,
            authProviders: ["google" as const],
        };
        useUserAuthStore.getState().setLogin(providerOnlyUser);
        vi.mocked(protectedApiClient.post).mockResolvedValueOnce({ data: updatedUser } as AxiosResponse<User>);

        const { user } = renderWithProviders(
            <Routes>
                <Route path={paths.emailPassword.set} element={<SetEmailAndPasswordContainer />} />
                <Route path={paths.user} element={<div>user destination</div>} />
                <Route path={paths.login} element={<div>login destination</div>} />
            </Routes>,
            { route: paths.emailPassword.set },
        );

        await user.type(screen.getByRole("textbox", { name: /メールアドレス/ }), "provider@example.com");
        const passwordInputs = screen.getAllByLabelText(/パスワード/);
        await user.type(passwordInputs[0], "pass1234");
        await user.type(passwordInputs[1], "pass1234");
        await user.click(screen.getByRole("button", { name: "設定" }));

        await waitFor(() =>
            expect(protectedApiClient.post).toHaveBeenCalledWith("/users/me/email-password", {
                email: "provider@example.com",
                password: "pass1234",
                confirmPassword: "pass1234",
            }),
        );
        expect(useUserAuthStore.getState().user).toEqual(updatedUser);
        expect(useNotificationStore.getState()).toMatchObject({
            message: "メールアドレスとパスワードを設定しました。",
            type: "success",
            isShow: true,
        });
    });
});
