import { vi } from "vitest";

// モックをセット
vi.mock("@/lib", () => ({
    protectedApiClient: { delete: vi.fn() },
}));
const mockedNavigate = vi.fn();
vi.mock("react-router", () => ({
    useNavigate: () => mockedNavigate,
}));

import { act, renderHook, waitFor } from "@testing-library/react";
import { AxiosResponse } from "axios";

import { paths } from "@/config/paths";
import { useDeleteUser } from "@/features/user";
import { protectedApiClient } from "@/lib";
import { useErrorMessageStore, useNotificationStore, useUserAuthStore } from "@/stores";
import { createQueryWrapper, resetStoresAndMocks } from "@/test";

describe("useDeleteUser", () => {
    const wrapper = createQueryWrapper();

    beforeEach(() => {
        // Zustandストアをクリアし、モック関数をリセット
        resetStoresAndMocks([]);
        vi.mocked(protectedApiClient.delete).mockReset();
        mockedNavigate.mockReset();
        // 各種ストアをスパイ
        vi.spyOn(useErrorMessageStore.getState(), "clearErrors");
        vi.spyOn(useNotificationStore.getState(), "setNotification");
        vi.spyOn(useUserAuthStore.getState(), "setLogout");
    });

    it("成功時はエラーストアクリア後、ログアウト・通知・リダイレクトが実行されること", async () => {
        // protectedApiClient.deleteの成功レスポンスをセット
        const mockResponse = { status: 204, data: undefined } as AxiosResponse<void>;
        vi.mocked(protectedApiClient.delete).mockResolvedValueOnce(mockResponse);

        // フックをレンダリング
        const { result } = renderHook(() => useDeleteUser(), { wrapper });

        // ミューテート実行
        act(() => {
            result.current.mutate();
        });

        // 成功状態になるまで待機
        await waitFor(() => expect(result.current.isSuccess).toBe(true));

        // clearErrorsがonMutateとonSuccessで計2回呼び出されること
        expect(useErrorMessageStore.getState().clearErrors).toHaveBeenCalledTimes(2);

        // setLogoutが呼ばれること
        expect(useUserAuthStore.getState().setLogout).toHaveBeenCalled();

        // setNotificationが正しい引数で呼び出されること
        expect(useNotificationStore.getState().setNotification).toHaveBeenCalledWith(
            "退会が完了しました。ご利用ありがとうございました。",
            "success",
        );

        // navigateが正しい引数で呼び出されること
        expect(mockedNavigate).toHaveBeenCalledWith(paths.login, { replace: true });
    });
});
