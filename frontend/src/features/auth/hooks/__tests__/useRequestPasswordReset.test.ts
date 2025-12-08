import { vi } from "vitest";

// モックをセット
vi.mock("@/lib", () => ({
    publicApiClient: { post: vi.fn() },
}));

import { act, renderHook, waitFor } from "@testing-library/react";
import type { AxiosResponse } from "axios";

import type { RequestPasswordResetPayload } from "@/features/auth";
import { useRequestPasswordReset } from "@/features/auth";
import { publicApiClient } from "@/lib";
import { useErrorMessageStore, useNotificationStore } from "@/stores";
import { createQueryWrapper, resetStoresAndMocks } from "@/test";

describe("useRequestPasswordReset", () => {
    const wrapper = createQueryWrapper();
    const payload: RequestPasswordResetPayload = { email: "test-user@example.com" };

    beforeEach(() => {
        // Zustandストアをクリア
        resetStoresAndMocks([]);
        // publicApiClient.post のモックをリセット
        vi.mocked(publicApiClient.post).mockReset();
        // 各種ストアをスパイ
        vi.spyOn(useErrorMessageStore.getState(), "clearErrors");
        vi.spyOn(useNotificationStore.getState(), "setNotification");
    });

    it("成功時はエラーストアをクリアし、通知が設定されること", async () => {
        // publicApiClient.post の成功レスポンスをセット
        const mockResponse = { status: 200, data: undefined } as AxiosResponse<void>;
        vi.mocked(publicApiClient.post).mockResolvedValueOnce(mockResponse);

        // フックをレンダリング
        const { result } = renderHook(() => useRequestPasswordReset(), { wrapper });

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
            "パスワードリセット用メールを送信しました。",
            "success",
        );
    });
});
