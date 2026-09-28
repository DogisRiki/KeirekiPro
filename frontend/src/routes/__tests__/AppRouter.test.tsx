import { ThemeProvider } from "@mui/material";
import { act, render, screen, within } from "@testing-library/react";
import { Suspense } from "react";
import { createMemoryRouter } from "react-router";
import { RouterProvider } from "react-router/dom";
import { vi } from "vitest";

import type * as ErrorsModule from "@/components/errors";
import { lightTheme } from "@/config/theme";
import { ProtectedLoader, PublicLoader } from "@/routes/AppLoader";
import { AppRouter, routes } from "@/routes/AppRouter";
import { stubState } from "@/routes/__tests__/routeStubs";
import { resetStoresAndMocks } from "@/test";

vi.mock("@/routes/AppLoader", () => ({
    ProtectedLoader: vi.fn(),
    PublicLoader: vi.fn(),
}));

vi.mock("@/components/layouts", async () => {
    const { createStubLayout } = await import("@/routes/__tests__/routeStubs");
    return { ProtectedLayout: createStubLayout("protected"), PublicLayout: createStubLayout("public") };
});

vi.mock("@/components/errors", async (importOriginal) => {
    const { createStubPage } = await import("@/routes/__tests__/routeStubs");
    return {
        ...(await importOriginal<typeof ErrorsModule>()),
        NotFound: createStubPage("NotFound"),
        ServerError: createStubPage("ServerError"),
    };
});

vi.mock("@/pages/Backup", async () => ({
    Backup: (await import("@/routes/__tests__/routeStubs")).createStubPage("Backup"),
}));
vi.mock("@/pages/ChangePassword", async () => ({
    ChangePassword: (await import("@/routes/__tests__/routeStubs")).createStubPage("ChangePassword"),
}));
vi.mock("@/pages/Contact", async () => ({
    Contact: (await import("@/routes/__tests__/routeStubs")).createStubPage("Contact"),
}));
vi.mock("@/pages/LandingPage", async () => ({
    LandingPage: (await import("@/routes/__tests__/routeStubs")).createStubPage("LandingPage"),
}));
vi.mock("@/pages/Login", async () => ({
    Login: (await import("@/routes/__tests__/routeStubs")).createStubPage("Login"),
}));
vi.mock("@/pages/Maintenance", async () => ({
    Maintenance: (await import("@/routes/__tests__/routeStubs")).createStubPage("Maintenance"),
}));
vi.mock("@/pages/Privacy", async () => ({
    Privacy: (await import("@/routes/__tests__/routeStubs")).createStubPage("Privacy"),
}));
vi.mock("@/pages/Register", async () => ({
    Register: (await import("@/routes/__tests__/routeStubs")).createStubPage("Register"),
}));
vi.mock("@/pages/RequestPasswordReset", async () => ({
    RequestPasswordReset: (await import("@/routes/__tests__/routeStubs")).createStubPage("RequestPasswordReset"),
}));
vi.mock("@/pages/ResetPassword", async () => ({
    ResetPassword: (await import("@/routes/__tests__/routeStubs")).createStubPage("ResetPassword"),
}));
vi.mock("@/pages/Resume", async () => ({
    Resume: (await import("@/routes/__tests__/routeStubs")).createStubPage("Resume"),
}));
vi.mock("@/pages/ResumeList", async () => ({
    ResumeList: (await import("@/routes/__tests__/routeStubs")).createStubPage("ResumeList"),
}));
vi.mock("@/pages/ResumeNew", async () => ({
    ResumeNew: (await import("@/routes/__tests__/routeStubs")).createStubPage("ResumeNew"),
}));
vi.mock("@/pages/SetEmailAndPassword", async () => ({
    SetEmailAndPassword: (await import("@/routes/__tests__/routeStubs")).createStubPage("SetEmailAndPassword"),
}));
vi.mock("@/pages/SettingUser", async () => ({
    SettingUser: (await import("@/routes/__tests__/routeStubs")).createStubPage("SettingUser"),
}));
vi.mock("@/pages/Terms", async () => ({
    Terms: (await import("@/routes/__tests__/routeStubs")).createStubPage("Terms"),
}));
vi.mock("@/pages/TwoFactor", async () => ({
    TwoFactor: (await import("@/routes/__tests__/routeStubs")).createStubPage("TwoFactor"),
}));

const renderAt = (path: string) => {
    const router = createMemoryRouter(routes, { initialEntries: [path] });
    return render(
        <ThemeProvider theme={lightTheme}>
            <Suspense fallback={<div>loading</div>}>
                <RouterProvider router={router} />
            </Suspense>
        </ThemeProvider>,
    );
};

const protectedPages = [
    ["/resume/list", "ResumeList"],
    ["/resume/new", "ResumeNew"],
    ["/resume/resume-1", "Resume"],
    ["/backup", "Backup"],
    ["/user", "SettingUser"],
    ["/password/change", "ChangePassword"],
    ["/email-password/set", "SetEmailAndPassword"],
    ["/contact", "Contact"],
] as const;

const publicPages = [
    ["/login", "Login"],
    ["/two-factor", "TwoFactor"],
    ["/register", "Register"],
    ["/password/reset", "RequestPasswordReset"],
    ["/password/reset/reset-token", "ResetPassword"],
] as const;

const openPages = [
    ["/terms", "Terms"],
    ["/privacy", "Privacy"],
    ["/500", "ServerError"],
    ["/maintenance", "Maintenance"],
] as const;

describe("routes", () => {
    beforeEach(() => {
        resetStoresAndMocks([]);
        stubState.throwInPage = false;
        vi.mocked(ProtectedLoader).mockResolvedValue(null);
        vi.mocked(PublicLoader).mockResolvedValue(null);
    });

    it.each(protectedPages)("%sは、ログインが必要な判定の下で%sを表示すること", async (path, page) => {
        renderAt(path);

        const layout = await screen.findByTestId("layout:protected");
        expect(within(layout).getByText(`page:${page}`)).toBeInTheDocument();
        expect(ProtectedLoader).toHaveBeenCalledTimes(1);
        expect(PublicLoader).not.toHaveBeenCalled();
    });

    it.each(publicPages)("%sは、ログイン済みなら入れない判定の下で%sを表示すること", async (path, page) => {
        renderAt(path);

        const layout = await screen.findByTestId("layout:public");
        expect(within(layout).getByText(`page:${page}`)).toBeInTheDocument();
        expect(PublicLoader).toHaveBeenCalledTimes(1);
        expect(ProtectedLoader).not.toHaveBeenCalled();
    });

    it("トップ画面は、ログイン済みなら入れない判定の下で、レイアウトを使わずに表示すること", async () => {
        renderAt("/");

        expect(await screen.findByText("page:LandingPage")).toBeInTheDocument();
        expect(screen.queryByTestId("layout:public")).not.toBeInTheDocument();
        expect(PublicLoader).toHaveBeenCalledTimes(1);
        expect(ProtectedLoader).not.toHaveBeenCalled();
    });

    it.each(openPages)("%sは、ログインの有無に関係なく%sを表示すること", async (path, page) => {
        renderAt(path);

        expect(await screen.findByText(`page:${page}`)).toBeInTheDocument();
        expect(screen.queryByTestId("layout:public")).not.toBeInTheDocument();
        expect(screen.queryByTestId("layout:protected")).not.toBeInTheDocument();
        expect(PublicLoader).not.toHaveBeenCalled();
        expect(ProtectedLoader).not.toHaveBeenCalled();
    });

    it.each(["/no-such-page", "/resume", "/resume/resume-1/extra"])(
        "定義の無いURL(%s)では、見つからない画面を表示すること",
        async (path) => {
            renderAt(path);

            expect(await screen.findByText("page:NotFound")).toBeInTheDocument();
            expect(PublicLoader).not.toHaveBeenCalled();
            expect(ProtectedLoader).not.toHaveBeenCalled();
        },
    );

    it("ログインが必要な判定で弾かれたときは、画面を表示しないこと", async () => {
        vi.mocked(ProtectedLoader).mockRejectedValue(new Error("unauthorized"));

        renderAt("/resume/list");

        expect(await screen.findByRole("alert")).toHaveTextContent("Ooops, something went wrong :(");
        expect(screen.queryByText("page:ResumeList")).not.toBeInTheDocument();
    });

    it.each([
        ...protectedPages,
        ...publicPages,
        ...openPages,
        ["/", "LandingPage"] as const,
        ["/no-such-page", "NotFound"] as const,
    ])("%sの描画に失敗したときは、エラー画面を表示すること", async (path) => {
        vi.spyOn(console, "error").mockImplementation(() => {});
        stubState.throwInPage = true;

        renderAt(path);

        expect(await screen.findByRole("alert")).toHaveTextContent("Ooops, something went wrong :(");
    });
});

describe("AppRouter", () => {
    beforeEach(() => {
        resetStoresAndMocks([]);
        stubState.throwInPage = false;
        vi.mocked(ProtectedLoader).mockResolvedValue(null);
        vi.mocked(PublicLoader).mockResolvedValue(null);
    });

    it("ブラウザのURLに合わせて画面を表示すること", async () => {
        render(
            <ThemeProvider theme={lightTheme}>
                <AppRouter />
            </ThemeProvider>,
        );

        act(() => {
            window.history.pushState({}, "", "/terms");
            window.dispatchEvent(new PopStateEvent("popstate"));
        });

        expect(await screen.findByText("page:Terms")).toBeInTheDocument();
    });
});
