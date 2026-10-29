import { vi } from "vitest";

// モックをセット
vi.mock("@/lib", () => ({
    protectedApiClient: { post: vi.fn() },
}));

import { renderHook, waitFor } from "@testing-library/react";
import type { AxiosResponse } from "axios";

import { useSendEmailVerification } from "@/features/user";
import { protectedApiClient } from "@/lib";
import { useErrorMessageStore, useNotificationStore } from "@/stores";
import { createQueryWrapper, resetStoresAndMocks } from "@/test";
import { act } from "react";

describe("useSendEmailVerification", () => {
    const wrapper = createQueryWrapper();

    beforeEach(() => {
        // Zustandストアとモック関数をリセット
        resetStoresAndMocks([]);
        vi.mocked(protectedApiClient.post).mockReset();
        // 各種ストアをスパイ
        vi.spyOn(useErrorMessageStore.getState(), "clearErrors");
        vi.spyOn(useNotificationStore.getState(), "setNotification");
    });

    it("POST /users/me/email-verification を呼び、確認のメールを送ったことを伝える文を出す", async () => {
        const mockResponse = { status: 204, data: undefined } as AxiosResponse<void>;
        vi.mocked(protectedApiClient.post).mockResolvedValueOnce(mockResponse);

        // フックをレンダリング
        const { result } = renderHook(() => useSendEmailVerification(), { wrapper });

        // ミューテート実行
        act(() => {
            result.current.mutate();
        });

        // 成功状態になるまで待機
        await waitFor(() => expect(result.current.isSuccess).toBe(true));

        // 送り先のAPIが呼ばれること
        expect(protectedApiClient.post).toHaveBeenCalledWith("/users/me/email-verification");

        // clearErrorsがonMutateとonSuccessで計2回呼び出されること
        expect(useErrorMessageStore.getState().clearErrors).toHaveBeenCalledTimes(2);

        // setNotificationが正しい引数で呼び出されること
        expect(useNotificationStore.getState().setNotification).toHaveBeenCalledWith(
            "確認のメールを送りました。メールの中の確認のリンクを押してください。",
            "success",
        );
    });

    it("送れなかったときは、確認のメールを送ったことを伝える文を出さない", async () => {
        vi.mocked(protectedApiClient.post).mockRejectedValueOnce(new Error("failed"));

        const { result } = renderHook(() => useSendEmailVerification(), { wrapper });

        act(() => {
            result.current.mutate();
        });

        await waitFor(() => expect(result.current.isError).toBe(true));

        expect(useNotificationStore.getState().setNotification).not.toHaveBeenCalled();
    });
});
