import { vi } from "vitest";

// モックをセット
vi.mock("@/lib", () => ({
    protectedApiClient: { get: vi.fn() },
}));

import { useGetUserInfo } from "@/hooks";
import { protectedApiClient } from "@/lib";
import { useErrorMessageStore } from "@/stores";
import { createQueryWrapper, resetStoresAndMocks } from "@/test";
import type { User } from "@/types";
import { renderHook, waitFor } from "@testing-library/react";

describe("useGetUserInfo", () => {
    const wrapper = createQueryWrapper();

    // テスト用ユーザー情報
    const mockUser: User = {
        id: "1",
        email: "test-user@example.com",
        username: "test-user",
        profileImage: null,
        twoFactorAuthEnabled: false,
        hasPassword: true,
        authProviders: ["github"],
    };

    beforeEach(() => {
        // Zustandストアとモック関数をリセット
        resetStoresAndMocks([]);
        vi.mocked(protectedApiClient.get).mockReset();
        // clearErrorsをスパイ
        vi.spyOn(useErrorMessageStore.getState(), "clearErrors");
    });

    it("成功時はエラーストアをクリアし、APIが呼び出され、データが返されること", async () => {
        // protectedApiClient.getの成功レスポンスをセット
        const mockResponse = { data: mockUser } as { data: User };
        vi.mocked(protectedApiClient.get).mockResolvedValueOnce(mockResponse);

        // フックをレンダリング
        const { result } = renderHook(() => useGetUserInfo(), { wrapper });

        // 成功状態になるまで待機
        await waitFor(() => expect(result.current.isSuccess).toBe(true));

        // clearErrorsがクエリ実行時に呼び出されること
        expect(useErrorMessageStore.getState().clearErrors).toHaveBeenCalledTimes(1);

        // protectedApiClient.getが正しい引数で呼び出されること
        expect(protectedApiClient.get).toHaveBeenCalledWith("/users/me");

        // 取得したデータが正しいこと
        expect(result.current.data).toEqual(mockUser);
    });
});
