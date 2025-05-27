import { vi } from "vitest";

// モックをセット
vi.mock("@/lib", () => ({
    protectedApiClient: { delete: vi.fn() },
}));

import { act, renderHook, waitFor } from "@testing-library/react";
import { AxiosResponse } from "axios";

import { useRemoveAuthProvider } from "@/features/user/hooks/useRemoveAuthProvider";
import { protectedApiClient } from "@/lib";
import { useErrorMessageStore, useNotificationStore, useUserAuthStore } from "@/stores";
import { createQueryWrapper, resetStoresAndMocks } from "@/test/testUtils";
import { AuthProvider, User } from "@/types";

describe("useRemoveAuthProvider", () => {
    const wrapper = createQueryWrapper();

    // テスト用の初期ユーザー情報
    const initialUser: User = {
        id: "1",
        email: "test-user@example.com",
        username: "test-user",
        profileImage: null,
        twoFactorAuthEnabled: false,
        hasPassword: true,
        authProviders: ["github", "google"],
    };

    beforeEach(() => {
        // ストア・モック関数のリセット
        resetStoresAndMocks([]);
        vi.mocked(protectedApiClient.delete).mockReset();
        // 各種ストアをスパイ
        vi.spyOn(useErrorMessageStore.getState(), "clearErrors");
        vi.spyOn(useUserAuthStore.getState(), "updateUserInfo");
        vi.spyOn(useNotificationStore.getState(), "setNotification");
        // 認証ストアに初期ユーザーをセット
        useUserAuthStore.getState().setLogin(initialUser);
    });

    it("成功時はエラーストアがクリアされ、ユーザー情報と通知が更新されること", async () => {
        // protectedApiClient.deleteの成功レスポンスをセット
        const mockResponse = { status: 204, data: undefined } as AxiosResponse<void>;
        vi.mocked(protectedApiClient.delete).mockResolvedValueOnce(mockResponse);

        // フックをレンダリング
        const { result } = renderHook(() => useRemoveAuthProvider(), { wrapper });

        // ミューテート実行（"google"を解除）
        act(() => {
            result.current.mutate("google" as AuthProvider);
        });

        // 成功状態になるまで待機
        await waitFor(() => expect(result.current.isSuccess).toBe(true));

        // clearErrorsがonMutateとonSuccessで計2回呼び出されること
        expect(useErrorMessageStore.getState().clearErrors).toHaveBeenCalledTimes(2);

        // updateUserInfoが呼ばれ、authProvidersから"google"が削除される
        expect(useUserAuthStore.getState().updateUserInfo).toHaveBeenCalledWith({
            ...initialUser,
            authProviders: ["github"],
        });

        // setNotificationが正しい引数で呼び出されること
        expect(useNotificationStore.getState().setNotification).toHaveBeenCalledWith("連携を解除しました。", "success");
    });
});
