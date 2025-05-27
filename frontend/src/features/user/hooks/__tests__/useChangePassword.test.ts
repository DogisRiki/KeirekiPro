import { vi } from "vitest";

// モックをセット
vi.mock("@/lib", () => ({
    protectedApiClient: { patch: vi.fn() },
}));

import { act, renderHook, waitFor } from "@testing-library/react";
import { AxiosResponse } from "axios";

import { ChangePasswordPayload, useChangePassword } from "@/features/user";
import { protectedApiClient } from "@/lib";
import { useErrorMessageStore, useNotificationStore } from "@/stores";
import { createQueryWrapper, resetStoresAndMocks } from "@/test/testUtils";

describe("useChangePassword", () => {
    const wrapper = createQueryWrapper();
    const payload: ChangePasswordPayload = {
        nowPassword: "current-pass",
        newPassword: "new-pass",
    };

    beforeEach(() => {
        // Zustandストアをクリア
        resetStoresAndMocks([]);
        // protectedApiClient.patchのモックをリセット
        vi.mocked(protectedApiClient.patch).mockReset();
        // 各種ストアをスパイ
        vi.spyOn(useErrorMessageStore.getState(), "clearErrors");
        vi.spyOn(useNotificationStore.getState(), "setNotification");
    });

    it("成功時はエラーストアをクリアし、成功通知がセットされること", async () => {
        // protectedApiClient.patchの成功レスポンスをセット
        const mockResponse = { status: 204, data: undefined } as AxiosResponse<void>;
        vi.mocked(protectedApiClient.patch).mockResolvedValueOnce(mockResponse);

        // フックをレンダリング
        const { result } = renderHook(() => useChangePassword(), { wrapper });

        // ミューテート実行
        act(() => {
            result.current.mutate(payload);
        });

        // 成功状態になるまで待機
        await waitFor(() => expect(result.current.isSuccess).toBe(true));

        // clearErrorsがonMutateとonSuccessで計2回呼び出されること
        expect(useErrorMessageStore.getState().clearErrors).toHaveBeenCalledTimes(2);

        // setNotificationが正しい引数で呼び出されること
        expect(useNotificationStore.getState().setNotification).toHaveBeenCalledWith(
            "パスワードを変更しました。",
            "success",
        );
    });
});
