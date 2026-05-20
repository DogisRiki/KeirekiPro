import { screen } from "@testing-library/react";
import type { AxiosResponse } from "axios";
import { Route, Routes } from "react-router";
import { vi } from "vitest";

vi.mock("@/lib", () => ({
    protectedApiClient: {
        post: vi.fn(),
    },
}));

import { MainMenu, UserMenu } from "@/components/ui";
import { paths } from "@/config/paths";
import { protectedApiClient } from "@/lib";
import { useUserAuthStore } from "@/stores";
import { renderWithProviders, resetStoresAndMocks } from "@/test";
import type { User } from "@/types";

const user: User = {
    id: "user-1",
    email: "user@example.com",
    username: "test-user",
    profileImage: null,
    twoFactorAuthEnabled: false,
    hasPassword: true,
    authProviders: [],
    roles: [],
};

describe("navigation menus", () => {
    beforeEach(() => {
        resetStoresAndMocks([]);
        vi.mocked(protectedApiClient.post).mockReset();
        vi.mocked(protectedApiClient.post).mockResolvedValue({ data: undefined } as AxiosResponse<void>);
    });

    it("MainMenuはmenu表示後のclickで対象画面へ遷移すること", async () => {
        const { user } = renderWithProviders(
            <>
                <MainMenu />
                <Routes>
                    <Route path="/" element={<div>top</div>} />
                    <Route path={paths.backup} element={<div>backup destination</div>} />
                </Routes>
            </>,
        );

        await user.click(screen.getByRole("button", { name: "menu" }));
        await user.click(screen.getByRole("menuitem", { name: /バックアップ/ }));

        expect(screen.getByText("backup destination")).toBeInTheDocument();
    });

    it("UserMenuは設定遷移とログアウトを処理すること", async () => {
        useUserAuthStore.getState().setLogin(user);

        const { user: uiUser } = renderWithProviders(
            <>
                <UserMenu />
                <Routes>
                    <Route path="/" element={<div>top</div>} />
                    <Route path={paths.user} element={<div>user destination</div>} />
                    <Route path={paths.login} element={<div>login destination</div>} />
                </Routes>
            </>,
        );

        await uiUser.click(screen.getByText("test-user"));
        await uiUser.click(screen.getByRole("menuitem", { name: /ユーザー設定/ }));
        expect(screen.getByText("user destination")).toBeInTheDocument();

        await uiUser.click(screen.getByText("test-user"));
        await uiUser.click(screen.getByRole("menuitem", { name: /ログアウト/ }));

        expect(await screen.findByText("login destination")).toBeInTheDocument();
        expect(protectedApiClient.post).toHaveBeenCalledWith("/auth/logout");
        expect(useUserAuthStore.getState().isAuthenticated).toBe(false);
    });
});
