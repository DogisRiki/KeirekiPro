import { ThemeProvider } from "@mui/material";
import { LocalizationProvider } from "@mui/x-date-pickers";
import { AdapterDayjs } from "@mui/x-date-pickers/AdapterDayjs";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { act, render, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import type { AxiosResponse } from "axios";
import { AxiosHeaders } from "axios";
import type { ReactNode } from "react";
import { MemoryRouter } from "react-router";
import { vi } from "vitest";

import { lightTheme } from "@/config/theme";
import { useResumeStore } from "@/features/resume";
import { useErrorMessageStore, useNotificationStore } from "@/stores";
import { useThemeStore } from "@/stores/themeStore";
import { useUserAuthStore } from "@/stores/userAuthStore";

type MockItem = (() => void) | { mockReset: () => void };

type MutationHookResult<TPayload> = {
    current: {
        mutate: (payload: TPayload) => void;
    };
};

type AsyncHookResult<TStatus extends "isSuccess" | "isError"> = {
    current: Record<TStatus, boolean>;
};

export const createAxiosResponse = <T,>(
    data: T,
    overrides: Partial<Omit<AxiosResponse<T>, "data">> = {},
): AxiosResponse<T> => ({
    data,
    status: 200,
    statusText: "OK",
    headers: {},
    config: {
        headers: new AxiosHeaders(),
    },
    ...overrides,
});

/**
 * React Queryのテスト用ラッパーを生成する
 * ※ retryを無効化し、テスト中の自動リトライでタイムアウトしないようにする
 * @returns QueryClientProviderを子要素でラップするReactコンポーネント
 */
export const createQueryWrapper = () => {
    const queryClient = new QueryClient({
        defaultOptions: {
            queries: {
                retry: false,
            },
            mutations: {
                retry: false,
            },
        },
    });

    const Wrapper = ({ children }: { children: ReactNode }) => (
        <QueryClientProvider client={queryClient}>{children}</QueryClientProvider>
    );

    Wrapper.displayName = "TestQueryClientProviderWrapper";

    return Wrapper;
};

export const createTestQueryClient = () =>
    new QueryClient({
        defaultOptions: {
            queries: {
                retry: false,
            },
            mutations: {
                retry: false,
            },
        },
    });

export const renderWithProviders = (ui: ReactNode, { route = "/" }: { route?: string } = {}) => {
    const queryClient = createTestQueryClient();
    const user = userEvent.setup();

    const utils = render(
        <QueryClientProvider client={queryClient}>
            <ThemeProvider theme={lightTheme}>
                <LocalizationProvider dateAdapter={AdapterDayjs}>
                    <MemoryRouter initialEntries={[route]}>{ui}</MemoryRouter>
                </LocalizationProvider>
            </ThemeProvider>
        </QueryClientProvider>,
    );

    return { user, queryClient, ...utils };
};

export function mutateHook<TPayload>(result: MutationHookResult<TPayload>, payload: TPayload) {
    act(() => {
        result.current.mutate(payload);
    });
}

export async function waitForHookSuccess(result: AsyncHookResult<"isSuccess">) {
    await waitFor(() => expect(result.current.isSuccess).toBe(true));
}

export async function waitForHookError(result: AsyncHookResult<"isError">) {
    await waitFor(() => expect(result.current.isError).toBe(true));
}

/**
 * beforeEachで呼び出し、テスト前にストアをクリアし、引数に渡したモック関数（または spyOn の戻り値）をリセットする
 * @param mocks リセット対象の配列。
 * - () => vi.mocked(fn).mockReset()を直接渡す
 * - spyOnの戻り値（.mockReset()を持つオブジェクト）
 */
export const resetStoresAndMocks = (mocks: MockItem[]) => {
    // すべてのモック・スパイの呼び出し履歴をクリア
    vi.clearAllMocks();

    // すべてのスパイを元の実装に戻す（前のテストで設定されたスパイを削除）
    vi.restoreAllMocks();

    // Zustandストアをクリア（action を呼ばずに setState で部分更新）
    useErrorMessageStore.setState({ message: null, errors: {} });
    useNotificationStore.setState({ message: null, type: undefined, isShow: false });
    useUserAuthStore.setState({ user: null, isAuthenticated: false });
    useThemeStore.setState({ mode: "light" });
    useResumeStore.getState().clearResume();

    mocks.forEach((m: MockItem) => {
        // 関数型でmockResetプロパティを持たない場合は直接実行
        if (typeof m === "function" && !(m as { mockReset?: () => void }).mockReset) {
            m();
        }
        // mockResetを持つオブジェクトの場合はmockReset()を呼ぶ
        else if ((m as { mockReset?: () => void }).mockReset) {
            (m as { mockReset: () => void }).mockReset();
        }
    });
};
