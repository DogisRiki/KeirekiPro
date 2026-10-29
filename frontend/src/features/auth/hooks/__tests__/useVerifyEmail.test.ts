import { vi } from "vitest";

// モックをセット
vi.mock("@/lib", () => ({
    publicApiClient: { post: vi.fn() },
}));

import { renderHook, waitFor } from "@testing-library/react";

import type { VerifyEmailResponse } from "@/features/auth";
import { useVerifyEmail } from "@/features/auth";
import { publicApiClient } from "@/lib";
import { useErrorMessageStore } from "@/stores";
import { createAxiosResponse, createQueryWrapper, resetStoresAndMocks } from "@/test";

describe("useVerifyEmail", () => {
    const token = "verification-token";
    const response: VerifyEmailResponse = { result: "PASSWORD_RESET_READY", passwordResetToken: "reset-token" };

    beforeEach(() => {
        // Zustandストアをクリア
        resetStoresAndMocks([]);
        // publicApiClient.postのモックをリセット
        vi.mocked(publicApiClient.post).mockReset();
        // clearErrorsをスパイ
        vi.spyOn(useErrorMessageStore.getState(), "clearErrors");
    });

    it("tokenが空文字の場合、確認の API を呼ばないこと", () => {
        const { result } = renderHook(() => useVerifyEmail(""), { wrapper: createQueryWrapper() });

        expect(result.current.status).toBe("pending");
        expect(useErrorMessageStore.getState().clearErrors).not.toHaveBeenCalled();
        expect(publicApiClient.post).not.toHaveBeenCalled();
    });

    it("成功時はエラーストアをクリアし、トークンで確認の API を呼び、結果を返すこと", async () => {
        vi.mocked(publicApiClient.post).mockResolvedValueOnce(createAxiosResponse(response));

        const { result } = renderHook(() => useVerifyEmail(token), { wrapper: createQueryWrapper() });

        await waitFor(() => expect(result.current.isSuccess).toBe(true));
        expect(result.current.data).toEqual(response);
        expect(useErrorMessageStore.getState().clearErrors).toHaveBeenCalledTimes(1);
        expect(publicApiClient.post).toHaveBeenCalledWith("/auth/email-verification/verify", { token });
    });

    it("同じトークンで出し直しても、確認の API を2回呼ばないこと", async () => {
        vi.mocked(publicApiClient.post).mockResolvedValue(createAxiosResponse(response));
        const wrapper = createQueryWrapper();

        const { result: firstResult, unmount } = renderHook(() => useVerifyEmail(token), { wrapper });
        await waitFor(() => expect(firstResult.current.isSuccess).toBe(true));
        unmount();

        const { result: secondResult } = renderHook(() => useVerifyEmail(token), { wrapper });

        expect(secondResult.current.data).toEqual(response);
        expect(publicApiClient.post).toHaveBeenCalledTimes(1);
    });

    it("失敗しても、確認の API を呼び直さないこと", async () => {
        vi.mocked(publicApiClient.post).mockRejectedValue(new Error("failed"));

        const { result } = renderHook(() => useVerifyEmail(token), { wrapper: createQueryWrapper() });

        await waitFor(() => expect(result.current.isError).toBe(true));
        expect(publicApiClient.post).toHaveBeenCalledTimes(1);
    });
});
