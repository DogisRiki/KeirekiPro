import { vi } from "vitest";

// モックをセット
vi.mock("@/lib", () => ({
    publicApiClient: { post: vi.fn() },
}));

const mockedNavigate = vi.fn();
vi.mock("react-router", () => ({
    useNavigate: () => mockedNavigate,
}));

import { act, renderHook, waitFor } from "@testing-library/react";
import type { AxiosResponse } from "axios";

import { paths } from "@/config/paths";
import type { ResetPasswordPayload } from "@/features/auth";
import { useResetPassword } from "@/features/auth";
import { publicApiClient } from "@/lib";
import { useErrorMessageStore, useNotificationStore } from "@/stores";
import { createQueryWrapper, resetStoresAndMocks } from "@/test";

describe("useResetPassword", () => {
    const wrapper = createQueryWrapper();
    const payload: ResetPasswordPayload = {
        token: "tok",
        password: "newpass",
        confirmPassword: "newpass",
    };

    beforeEach(() => {
        // Zustandストアをクリア
        resetStoresAndMocks([]);
        // publicApiClient.postのモックをリセット
        vi.mocked(publicApiClient.post).mockReset();
        // 各種ストアをスパイ
        vi.spyOn(useErrorMessageStore.getState(), "clearErrors");
        vi.spyOn(useNotificationStore.getState(), "setNotification");
        // navigateをリセット
        mockedNavigate.mockReset();
    });

    it("成功時はエラーストアをクリアし、通知とリダイレクトが行われること", async () => {
        // publicApiClient.postの成功レスポンスをセット
        const mockResponse = { status: 200, data: undefined } as AxiosResponse<void>;
        vi.mocked(publicApiClient.post).mockResolvedValueOnce(mockResponse);

        // フックをレンダリング
        const { result } = renderHook(() => useResetPassword(), { wrapper });

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
            "パスワードを変更しました。ログインしてください。",
            "success",
        );

        // navigateが正しい引数で呼び出されること
        expect(mockedNavigate).toHaveBeenCalledWith(paths.login, { replace: true });
    });
});
