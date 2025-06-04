import { vi } from "vitest";

// モックをセット
vi.mock("@/lib", () => ({
    publicApiClient: { post: vi.fn() },
}));

import { renderHook, waitFor } from "@testing-library/react";
import { AxiosResponse } from "axios";

import { useVerifyPasswordResetToken } from "@/features/auth";
import { publicApiClient } from "@/lib";
import { useErrorMessageStore } from "@/stores";
import { createQueryWrapper, resetStoresAndMocks } from "@/test";

describe("useVerifyPasswordResetToken", () => {
    const wrapper = createQueryWrapper();
    const token = "valid-token";

    beforeEach(() => {
        // Zustandストアをクリア
        resetStoresAndMocks([]);
        // publicApiClient.postのモックをリセット
        vi.mocked(publicApiClient.post).mockReset();
        // clearErrorsをスパイ
        vi.spyOn(useErrorMessageStore.getState(), "clearErrors");
    });

    it("tokenが空文字の場合、クエリが実行されないこと", async () => {
        // フックをレンダリング（enabled=falseのため実行されない）
        const { result } = renderHook(() => useVerifyPasswordResetToken(""), { wrapper });

        // statusが'pending'であること（enabled=falseでも初期状態はpending）
        expect(result.current.status).toBe("pending");

        // clearErrorsは呼ばれないこと
        expect(useErrorMessageStore.getState().clearErrors).not.toHaveBeenCalled();

        // API呼び出しは行われないこと
        expect(publicApiClient.post).not.toHaveBeenCalled();
    });

    it("成功時はエラーストアをクリアし、API が呼び出されること", async () => {
        // publicApiClient.postの成功レスポンスをセット
        const mockResponse = { status: 200, data: undefined } as AxiosResponse<void>;
        vi.mocked(publicApiClient.post).mockResolvedValueOnce(mockResponse);

        // フックをレンダリング（enabled=true）
        const { result } = renderHook(() => useVerifyPasswordResetToken(token), { wrapper });

        // 成功状態になるまで待機
        await waitFor(() => expect(result.current.isSuccess).toBe(true));

        // clearErrorsが1回呼び出されること
        expect(useErrorMessageStore.getState().clearErrors).toHaveBeenCalledTimes(1);

        // APIが正しい引数で呼び出されること
        expect(publicApiClient.post).toHaveBeenCalledWith("/auth/password/reset/verify", { token });
    });
});
