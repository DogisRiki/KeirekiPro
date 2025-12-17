// src/features/auth/hooks/__tests__/useVerifyTwoFactor.test.ts
import { vi } from "vitest";

// モックをセット（HTTP クライアント層のみ）
vi.mock("@/lib", () => ({
    publicApiClient: { post: vi.fn() },
    protectedApiClient: { get: vi.fn() },
}));
const mockedNavigate = vi.fn();
vi.mock("react-router", () => ({
    useNavigate: () => mockedNavigate,
}));

import { act, renderHook, waitFor } from "@testing-library/react";
import type { AxiosResponse } from "axios";

import { paths } from "@/config/paths";
import { useTwoFactorStore, useVerifyTwoFactor } from "@/features/auth";
import { protectedApiClient, publicApiClient } from "@/lib";
import { useErrorMessageStore, useUserAuthStore } from "@/stores";
import { createQueryWrapper, resetStoresAndMocks } from "@/test";

describe("useVerifyTwoFactor", () => {
    const wrapper = createQueryWrapper();
    const dummyCode = "123456";
    const dummyUser = {
        id: "1",
        email: null,
        username: "test-user",
        profileImage: null,
        twoFactorAuthEnabled: false,
        hasPassword: true,
        authProviders: [],
    };

    beforeEach(() => {
        // Zustandストアをクリア
        resetStoresAndMocks([]);
        // HTTPモックをリセット
        vi.mocked(publicApiClient.post).mockReset();
        vi.mocked(protectedApiClient.get).mockReset();
        // ストアメソッドをスパイ
        vi.spyOn(useErrorMessageStore.getState(), "clearErrors");
        vi.spyOn(useTwoFactorStore.getState(), "clear");
        vi.spyOn(useUserAuthStore.getState(), "setLogin");
        // TwoFactorStoreにuserIdをセット
        useTwoFactorStore.getState().setUserId("uid");
        mockedNavigate.mockReset();
    });

    it("成功時はエラーストアをクリア・TwoFactorStore.clear・ログイン情報取得・認証ストア更新・リダイレクトが実行されること", async () => {
        // verifyTwoFactorの成功レスポンスをセット
        const postResponse = { status: 204, data: undefined } as AxiosResponse<void>;
        vi.mocked(publicApiClient.post).mockResolvedValueOnce(postResponse);
        // getUserInfoの成功レスポンスをセット
        vi.mocked(protectedApiClient.get).mockResolvedValueOnce({ data: dummyUser } as AxiosResponse<typeof dummyUser>);

        // フックをレンダリング
        const { result } = renderHook(() => useVerifyTwoFactor(), { wrapper });

        // ミューテート実行
        act(() => {
            result.current.mutate(dummyCode);
        });

        // 成功状態になるまで待機
        await waitFor(() => expect(result.current.isSuccess).toBe(true));

        // clearErrorsがonMutateとonSuccessで計2回呼び出されること
        expect(useErrorMessageStore.getState().clearErrors).toHaveBeenCalledTimes(2);

        // TwoFactorStore.clearが呼び出されること
        expect(useTwoFactorStore.getState().clear).toHaveBeenCalled();

        // getUserInfoが呼び出されること
        expect(protectedApiClient.get).toHaveBeenCalledWith("/users/me");

        // setLoginが取得したユーザー情報で呼び出されること
        expect(useUserAuthStore.getState().setLogin).toHaveBeenCalledWith(dummyUser);

        // navigateが正しい引数で呼び出されること
        expect(mockedNavigate).toHaveBeenCalledWith(paths.resume.list, { replace: true });
    });
});
