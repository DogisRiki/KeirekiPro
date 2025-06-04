// src/features/auth/hooks/__tests__/useAuthorizeOidc.test.ts
import { vi } from "vitest";

// モックをセット（HTTP クライアント層のみ）
vi.mock("@/lib", () => ({
    publicApiClient: { get: vi.fn() },
}));

import { act, renderHook, waitFor } from "@testing-library/react";
import { AxiosResponse } from "axios";

import { useAuthorizeOidc } from "@/features/auth";
import { publicApiClient } from "@/lib";
import { useErrorMessageStore } from "@/stores";
import { createQueryWrapper, resetStoresAndMocks } from "@/test";
import { AuthProvider } from "@/types";

describe("useAuthorizeOidc", () => {
    const wrapper = createQueryWrapper();
    const mockUrl = "https://example.com/auth";

    beforeEach(() => {
        // Zustandストアをクリア
        resetStoresAndMocks([]);
        // publicApiClient.getのモックをリセット
        vi.mocked(publicApiClient.get).mockReset();
        // clearErrorsをスパイ
        vi.spyOn(useErrorMessageStore.getState(), "clearErrors");
        // window.location.hrefを再定義
        // @ts-expect-error book-keeping for test
        delete window.location;
        // @ts-expect-error book-keeping for test
        window.location = { href: "" };
    });

    it("成功時はエラーストアをクリアし、window.location.href が設定されること", async () => {
        // publicApiClient.getの成功レスポンスをセット
        const mockResponse = { data: mockUrl } as AxiosResponse<string>;
        vi.mocked(publicApiClient.get).mockResolvedValueOnce(mockResponse);

        // フックをレンダリング
        const { result } = renderHook(() => useAuthorizeOidc(), { wrapper });

        // ミューテート実行
        act(() => {
            result.current.mutate("github" as AuthProvider);
        });

        // 成功状態になるまで待機
        await waitFor(() => expect(result.current.isSuccess).toBe(true));

        // clearErrorsがonMutateとonSuccessで計2回呼び出されること
        expect(useErrorMessageStore.getState().clearErrors).toHaveBeenCalledTimes(2);

        // window.location.hrefが正しく設定されること
        expect(window.location.href).toBe(mockUrl);

        // publicApiClient.getが正しいパラメータで呼び出されること
        expect(publicApiClient.get).toHaveBeenCalledWith("/auth/oidc/authorize", { params: { provider: "github" } });
    });
});
