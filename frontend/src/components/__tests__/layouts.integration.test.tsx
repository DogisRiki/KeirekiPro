import type { ReactNode } from "react";
import { Route, Routes, useNavigate } from "react-router";

import { ProtectedLayout, PublicLayout } from "@/components/layouts";
import { useErrorMessageStore, useUserAuthStore } from "@/stores";
import { renderWithProviders, resetStoresAndMocks } from "@/test";
import type { User } from "@/types";
import { screen } from "@testing-library/react";

const testUser: User = {
    id: "user-1",
    email: "user@example.com",
    username: "test-user",
    profileImage: null,
    twoFactorAuthEnabled: false,
    hasPassword: true,
    authProviders: [],
    roles: [],
};

const NavigateButton = ({ to, children }: { to: string; children: ReactNode }) => {
    const navigate = useNavigate();
    return <button onClick={() => navigate(to)}>{children}</button>;
};

describe("layouts", () => {
    beforeEach(() => {
        resetStoresAndMocks([]);
    });

    it("ProtectedLayoutは子画面を表示しroute change時にエラーをクリアすること", async () => {
        useUserAuthStore.getState().setLogin(testUser);
        useErrorMessageStore.setState({ message: "before route change", errors: {}, errorId: "error-1" });

        const { user: uiUser } = renderWithProviders(
            <Routes>
                <Route path="/protected" element={<ProtectedLayout />}>
                    <Route index element={<NavigateButton to="/protected/next">next protected</NavigateButton>} />
                    <Route path="next" element={<div>protected next page</div>} />
                </Route>
            </Routes>,
            { route: "/protected" },
        );

        expect(screen.getByText("KeirekiPro")).toBeInTheDocument();
        await uiUser.click(screen.getByRole("button", { name: "next protected" }));

        expect(await screen.findByText("protected next page")).toBeInTheDocument();
        expect(useErrorMessageStore.getState().message).toBeNull();
    });

    it("PublicLayoutは子画面を表示しroute change時にエラーをクリアすること", async () => {
        useErrorMessageStore.setState({ message: "before route change", errors: {}, errorId: "error-1" });

        const { user: uiUser } = renderWithProviders(
            <Routes>
                <Route path="/public" element={<PublicLayout />}>
                    <Route index element={<NavigateButton to="/public/next">next public</NavigateButton>} />
                    <Route path="next" element={<div>public next page</div>} />
                </Route>
            </Routes>,
            { route: "/public" },
        );

        await uiUser.click(screen.getByRole("button", { name: "next public" }));

        expect(await screen.findByText("public next page")).toBeInTheDocument();
        expect(useErrorMessageStore.getState().message).toBeNull();
    });
});
