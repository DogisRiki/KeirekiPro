import { vi } from "vitest";

// モックをセット
vi.mock("@/lib", () => ({
    protectedApiClient: { put: vi.fn() },
}));

import { act, renderHook, waitFor } from "@testing-library/react";
import { AxiosResponse } from "axios";

import { UpdateUserInfoPayload, useUpdateUserInfo } from "@/features/user";
import { protectedApiClient } from "@/lib";
import { useErrorMessageStore, useNotificationStore, useUserAuthStore } from "@/stores";
import { createQueryWrapper, resetStoresAndMocks } from "@/test";
import { User } from "@/types";

describe("useUpdateUserInfo", () => {
    const wrapper = createQueryWrapper();

    beforeEach(() => {
        // Zustandストアとモック関数をリセット
        resetStoresAndMocks([]);
        vi.mocked(protectedApiClient.put).mockReset();
        // 各種ストアをスパイ
        vi.spyOn(useErrorMessageStore.getState(), "clearErrors");
        vi.spyOn(useUserAuthStore.getState(), "updateUserInfo");
        vi.spyOn(useNotificationStore.getState(), "setNotification");
    });

    it("成功時はエラーストアがクリアされ、ストア更新・通知が実行されること", async () => {
        const payload: UpdateUserInfoPayload = {
            username: "newuser",
        };
        // APIレスポンス
        const returnedUser: User = {
            id: "123",
            email: "test-user@example.com",
            username: "test-user",
            profileImage: null,
            twoFactorAuthEnabled: false,
            hasPassword: true,
            authProviders: ["github"],
        };
        const mockResponse = { status: 200, data: returnedUser } as AxiosResponse<User>;
        vi.mocked(protectedApiClient.put).mockResolvedValueOnce(mockResponse);

        // フックをレンダリング
        const { result } = renderHook(() => useUpdateUserInfo(), { wrapper });

        // ミューテート実行
        act(() => {
            result.current.mutate(payload);
        });

        // 成功状態になるまで待機
        await waitFor(() => expect(result.current.isSuccess).toBe(true));

        // clearErrors が onMutate と onSuccess で呼ばれていること
        expect(useErrorMessageStore.getState().message).toBeNull();
        expect(useErrorMessageStore.getState().errors).toEqual({});

        // ストア更新が呼ばれていること
        expect(useUserAuthStore.getState().updateUserInfo).toHaveBeenCalledWith(returnedUser);

        // 通知がセットされていること
        expect(useNotificationStore.getState().message).toBe("ユーザー情報を更新しました。");
        expect(useNotificationStore.getState().type).toBe("success");
        expect(useNotificationStore.getState().isShow).toBe(true);
    });
});
