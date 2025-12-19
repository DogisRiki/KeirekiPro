import type * as ReactRouter from "react-router";
import { vi } from "vitest";

// モックをセット
vi.mock("@/lib", () => ({
    publicApiClient: { post: vi.fn() },
}));

vi.mock("@/hooks", () => ({
    getUserInfo: vi.fn(),
}));

const mockedNavigate = vi.hoisted(() => vi.fn());
vi.mock("react-router", async () => {
    const actual = await vi.importActual<typeof ReactRouter>("react-router");
    return {
        ...actual,
        useNavigate: () => mockedNavigate,
    };
});

import { act, renderHook, waitFor } from "@testing-library/react";
import type { AxiosResponse } from "axios";

import { paths } from "@/config/paths";
import type { LoginPayload } from "@/features/auth";
import { useLogin, useTwoFactorStore } from "@/features/auth";
import { getUserInfo } from "@/hooks";
import { publicApiClient } from "@/lib";
import { useErrorMessageStore, useUserAuthStore } from "@/stores";
import { createQueryWrapper, resetStoresAndMocks } from "@/test";

describe("useLogin", () => {
    const wrapper = createQueryWrapper();
    const payload: LoginPayload = { email: "test-user@example.com", password: "pass123" };
    const fakeUser = {
        id: "1",
        email: "test-user@example.com",
        username: "test-user",
        profileImage: null,
        twoFactorAuthEnabled: false,
        hasPassword: true,
        authProviders: [],
    };

    beforeEach(() => {
        // Zustandストアをクリア
        resetStoresAndMocks([]);
        // publicApiClient.postのモックをリセット
        vi.mocked(publicApiClient.post).mockReset();
        // getUserInfoのモックをリセット
        vi.mocked(getUserInfo).mockReset();
        // 各種ストアをスパイ
        vi.spyOn(useErrorMessageStore.getState(), "clearErrors");
        vi.spyOn(useUserAuthStore.getState(), "setLogin");
        vi.spyOn(useTwoFactorStore.getState(), "setUserId");
        // navigateをリセット
        mockedNavigate.mockReset();
    });

    it("ステータス200時は2FA無効としてユーザ情報取得・ログイン・リダイレクトが行われること", async () => {
        // publicApiClient.postの成功レスポンスをセット
        const mockResponse = { status: 200, data: "12345" } as AxiosResponse<string>;
        vi.mocked(publicApiClient.post).mockResolvedValueOnce(mockResponse);
        // getUserInfoの戻り値をセット
        vi.mocked(getUserInfo).mockResolvedValueOnce(fakeUser);

        // フックをレンダリング
        const { result } = renderHook(() => useLogin(), { wrapper });

        // ミューテート実行
        act(() => {
            result.current.mutate(payload);
        });

        // 成功状態になるまで待機
        await waitFor(() => expect(result.current.isSuccess).toBe(true));

        // clearErrorsがonMutateとonSuccessで計2回呼び出されること
        expect(useErrorMessageStore.getState().clearErrors).toHaveBeenCalledTimes(2);

        // getUserInfoが呼び出されること
        expect(getUserInfo).toHaveBeenCalled();

        // setLoginが正しいユーザ情報で呼び出されること
        expect(useUserAuthStore.getState().setLogin).toHaveBeenCalledWith(fakeUser);

        // setUserId は呼ばれないこと
        expect(useTwoFactorStore.getState().setUserId).not.toHaveBeenCalled();

        // リダイレクトが正しい引数で呼び出されること
        expect(mockedNavigate).toHaveBeenCalledWith(paths.resume.list, { replace: true });
    });

    it("ステータス202時は2FA有効としてユーザIDセット・リダイレクトが行われること", async () => {
        // publicApiClient.postの成功レスポンスをセット
        const twoFaUserId = "2";
        const mockResponse = { status: 202, data: twoFaUserId } as AxiosResponse<string>;
        vi.mocked(publicApiClient.post).mockResolvedValueOnce(mockResponse);

        // フックをレンダリング
        const { result } = renderHook(() => useLogin(), { wrapper });

        // ミューテート実行
        act(() => {
            result.current.mutate(payload);
        });

        // 成功状態になるまで待機
        await waitFor(() => expect(result.current.isSuccess).toBe(true));

        // clearErrorsがonMutateとonSuccessで計2回呼び出されること
        expect(useErrorMessageStore.getState().clearErrors).toHaveBeenCalledTimes(2);

        // getUserInfoは呼ばれないこと
        expect(getUserInfo).not.toHaveBeenCalled();

        // setLoginは呼ばれないこと
        expect(useUserAuthStore.getState().setLogin).not.toHaveBeenCalled();

        // setUserIdが正しい引数で呼び出されること
        expect(useTwoFactorStore.getState().setUserId).toHaveBeenCalledWith(twoFaUserId);

        // リダイレクトが正しい引数で呼び出されること
        expect(mockedNavigate).toHaveBeenCalledWith(paths.twoFactor, { replace: true });
    });
});
