import { useTheme } from "@mui/material";
import { useQueryClient } from "@tanstack/react-query";
import { render, screen } from "@testing-library/react";
import dayjs from "dayjs";
import { vi } from "vitest";

import { AppProvider } from "@/providers/AppProvider";
import { useErrorMessageStore, useThemeStore, useUserAuthStore } from "@/stores";
import { resetStoresAndMocks } from "@/test";
import type { User } from "@/types";

/** 使われているテーマと、データ取得の仕組みが使えるかを表示する */
const Probe = () => {
    const theme = useTheme();
    const queryClient = useQueryClient();
    return (
        <div>
            テーマ:{theme.palette.mode} / データ取得:{queryClient ? "あり" : "なし"}
        </div>
    );
};

const Broken = () => {
    throw new Error("描画に失敗");
};

describe("AppProvider", () => {
    beforeEach(() => {
        resetStoresAndMocks([]);
    });

    it.each(["light", "dark"] as const)(
        "ログインしていないときは、設定(%s)にかかわらずライトテーマを使うこと",
        (mode) => {
            useThemeStore.setState({ mode });
            useUserAuthStore.setState({ user: null, isAuthenticated: false });

            render(
                <AppProvider>
                    <Probe />
                </AppProvider>,
            );

            expect(screen.getByText("テーマ:light / データ取得:あり")).toBeInTheDocument();
        },
    );

    it.each(["light", "dark"] as const)("ログイン中は、設定のテーマ(%s)を使うこと", (mode) => {
        useThemeStore.setState({ mode });
        useUserAuthStore.setState({ user: { id: "user-1" } as User, isAuthenticated: true });

        render(
            <AppProvider>
                <Probe />
            </AppProvider>,
        );

        expect(screen.getByText(`テーマ:${mode} / データ取得:あり`)).toBeInTheDocument();
    });

    it("日付の表示を日本語にすること", () => {
        expect(dayjs.locale()).toBe("ja");
    });

    it("エラーのメッセージがあるときは、画面にエラーを出すこと", () => {
        useErrorMessageStore.getState().setErrors({ message: "入力内容に誤りがあります", errors: {} });

        render(
            <AppProvider>
                <div>中身</div>
            </AppProvider>,
        );

        expect(screen.getByText("入力内容に誤りがあります")).toBeInTheDocument();
        expect(screen.getByText("中身")).toBeInTheDocument();
    });

    it("中身の描画に失敗したときは、エラーの画面を出すこと", () => {
        vi.spyOn(console, "error").mockImplementation(() => {});

        render(
            <AppProvider>
                <Broken />
            </AppProvider>,
        );

        expect(screen.getByRole("alert")).toHaveTextContent("Ooops, something went wrong :(");
    });
});

describe("AppProvider の Google Analytics", () => {
    afterEach(() => {
        vi.doUnmock("react-ga4");
        vi.doUnmock("@/config/env");
        vi.resetModules();
    });

    it("計測IDがあるときは、そのIDで計測を初期化すること", async () => {
        vi.resetModules();
        const initialize = vi.fn();
        vi.doMock("react-ga4", () => ({ default: { initialize } }));

        await import("@/providers/AppProvider");

        expect(initialize).toHaveBeenCalledWith("G-dummyId");
    });

    it("計測IDが無いときは、計測を初期化しないこと", async () => {
        vi.resetModules();
        const initialize = vi.fn();
        vi.doMock("react-ga4", () => ({ default: { initialize } }));
        vi.doMock("@/config/env", async (importOriginal) => {
            const original = await importOriginal<{ env: Record<string, string | undefined> }>();
            return { env: { ...original.env, GA_MEASUREMENT_ID: "" } };
        });

        await import("@/providers/AppProvider");

        expect(initialize).not.toHaveBeenCalled();
    });
});
