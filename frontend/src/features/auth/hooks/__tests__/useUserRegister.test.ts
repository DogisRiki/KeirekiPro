import type * as ReactRouter from "react-router";
import { vi } from "vitest";

// モックをセット
vi.mock("@/lib", () => ({
    publicApiClient: { post: vi.fn() },
}));

const mockedNavigate = vi.hoisted(() => vi.fn());
vi.mock("react-router", async () => {
    const actual = await vi.importActual<typeof ReactRouter>("react-router");
    return {
        ...actual,
        useNavigate: () => mockedNavigate,
    };
});

import { renderHook, waitFor } from "@testing-library/react";
import type { AxiosResponse } from "axios";

import { paths } from "@/config/paths";
import type { UserRegistrationPayload } from "@/features/auth";
import { useUserRegister } from "@/features/auth";
import { publicApiClient } from "@/lib";
import { useErrorMessageStore, useNotificationStore } from "@/stores";
import { createQueryWrapper, mutateHook, resetStoresAndMocks } from "@/test";

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

    it("登録が 202 で終わると確認のメールを送ったことを伝える文を出す", async () => {
        // publicApiClient.postの成功レスポンスをセット(1分の制限で送らなかったときも 202 が返る)
        const mockResponse = { status: 202, data: undefined } as AxiosResponse<void>;
        vi.mocked(publicApiClient.post).mockResolvedValueOnce(mockResponse);

        // フックをレンダリング
        const { result } = renderHook(() => useUserRegister(), { wrapper });

        // ミューテート実行
        mutateHook(result, payload);

        // 成功状態になるまで待機
        await waitFor(() => expect(result.current.isSuccess).toBe(true));

        // clearErrorsがonMutateとonSuccessで計2回呼び出されること
        expect(useErrorMessageStore.getState().clearErrors).toHaveBeenCalledTimes(2);

        // setNotificationが正しい引数で呼び出されること
        expect(useNotificationStore.getState().setNotification).toHaveBeenCalledWith(
            "確認のメールを送りました。\nメールの中の確認のリンクを押して、登録を済ませてください。",
            "success",
        );

        // navigateが正しい引数で呼び出されること
        expect(mockedNavigate).toHaveBeenCalledWith(paths.login, { replace: true });
    });
});
