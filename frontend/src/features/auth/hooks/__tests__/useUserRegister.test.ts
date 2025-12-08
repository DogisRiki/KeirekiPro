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
import type { UserRegistrationPayload } from "@/features/auth";
import { useUserRegister } from "@/features/auth";
import { publicApiClient } from "@/lib";
import { useErrorMessageStore, useNotificationStore } from "@/stores";
import { createQueryWrapper, resetStoresAndMocks } from "@/test";

describe("useUserRegister", () => {
    const wrapper = createQueryWrapper();
    const payload: UserRegistrationPayload = {
        email: "test-user@example.com",
        username: "test-user",
        password: "pass123",
        confirmPassword: "pass123",
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

    it("成功時はエラーストアをクリアし、通知とリダイレクトが実行されること", async () => {
        // publicApiClient.postの成功レスポンスをセット
        const mockResponse = { status: 200, data: undefined } as AxiosResponse<void>;
        vi.mocked(publicApiClient.post).mockResolvedValueOnce(mockResponse);

        // フックをレンダリング
        const { result } = renderHook(() => useUserRegister(), { wrapper });

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
            "新規会員登録が完了しました。\n登録完了の確認メールをお送りいたしましたのでご確認ください。",
            "success",
        );

        // navigateが正しい引数で呼び出されること
        expect(mockedNavigate).toHaveBeenCalledWith(paths.login, { replace: true });
    });
});
