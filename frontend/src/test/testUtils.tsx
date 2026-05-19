import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { act, waitFor } from "@testing-library/react";
import type { ReactNode } from "react";
import { vi } from "vitest";

import { useErrorMessageStore, useNotificationStore } from "@/stores";

type MockItem = (() => void) | { mockReset: () => void };

type MutationHookResult<TPayload> = {
    current: {
        mutate: (payload: TPayload) => void;
    };
};

type AsyncHookResult<TStatus extends "isSuccess" | "isError"> = {
    current: Record<TStatus, boolean>;
};

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
