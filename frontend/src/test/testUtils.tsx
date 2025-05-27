import { useErrorMessageStore, useNotificationStore } from "@/stores";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import React from "react";

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

    const Wrapper: React.FC<{ children: React.ReactNode }> = ({ children }) => (
        <QueryClientProvider client={queryClient}>{children}</QueryClientProvider>
    );
    Wrapper.displayName = "TestQueryClientProviderWrapper";
    return Wrapper;
};

/**
 * beforeEachで呼び出し、テスト前にストアをクリアし、引数に渡したモック関数（または spyOn の戻り値）をリセットする
 * @param mocks リセット対象の配列。
 *              - () => vi.mocked(fn).mockReset()を直接渡す
 *              - spyOnの戻り値（.mockReset()を持つオブジェクト）
 */
export const resetStoresAndMocks = (mocks: Array<() => void | { mockReset: () => void }>) => {
    // Zustandストアをクリア
    useErrorMessageStore.getState().clearErrors();
    useNotificationStore.getState().clearNotification();

    mocks.forEach((m) => {
        // 関数型でmockResetプロパティを持たない場合は直接実行
        if (typeof m === "function" && !(m as any).mockReset) {
            m();
        }
        // mockResetを持つオブジェクトの場合はmockReset()を呼ぶ
        else if ((m as any).mockReset) {
            (m as any).mockReset();
        }
    });
};
