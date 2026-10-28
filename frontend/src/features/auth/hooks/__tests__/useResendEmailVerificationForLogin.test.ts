import { renderHook, waitFor } from "@testing-library/react";
import type { AxiosResponse } from "axios";
import { vi } from "vitest";

// モックをセット
vi.mock("@/lib", () => ({
    publicApiClient: { post: vi.fn() },
}));

import { useResendEmailVerificationForLogin } from "@/features/auth";
import { publicApiClient } from "@/lib";
import { useErrorMessageStore, useNotificationStore } from "@/stores";
import { createQueryWrapper, mutateHook, resetStoresAndMocks } from "@/test";

describe("useResendEmailVerificationForLogin", () => {
    const wrapper = createQueryWrapper();

    beforeEach(() => {
        // Zustandストアをクリア
        resetStoresAndMocks([]);
        // publicApiClient.postのモックをリセット
        vi.mocked(publicApiClient.post).mockReset();
        // 各種ストアをスパイ
        vi.spyOn(useErrorMessageStore.getState(), "clearErrors");
        vi.spyOn(useNotificationStore.getState(), "setNotification");
    });

    it("成功時はメールアドレスとパスワードでログインの画面から送る API を呼び、送ったことを通知すること", async () => {
        vi.mocked(publicApiClient.post).mockResolvedValueOnce({ status: 204, data: undefined } as AxiosResponse<void>);

        const { result } = renderHook(() => useResendEmailVerificationForLogin(), { wrapper });

        mutateHook(result, { email: "test@example.com", password: "pass1234" });

        await waitFor(() => expect(result.current.isSuccess).toBe(true));
        expect(publicApiClient.post).toHaveBeenCalledWith("/auth/email-verification/resend-for-login", {
            email: "test@example.com",
            password: "pass1234",
        });
        // clearErrorsがonMutateとonSuccessで計2回呼び出されること
        expect(useErrorMessageStore.getState().clearErrors).toHaveBeenCalledTimes(2);
        expect(useNotificationStore.getState().setNotification).toHaveBeenCalledWith(
            "確認のメールを送りました。メールの中の確認のリンクを押してください。",
            "success",
        );
    });

    it("失敗時は通知を出さないこと", async () => {
        vi.mocked(publicApiClient.post).mockRejectedValueOnce(new Error("failed"));

        const { result } = renderHook(() => useResendEmailVerificationForLogin(), { wrapper });

        mutateHook(result, { email: "test@example.com", password: "pass1234" });

        await waitFor(() => expect(result.current.isError).toBe(true));
        expect(useNotificationStore.getState().setNotification).not.toHaveBeenCalled();
    });
});
