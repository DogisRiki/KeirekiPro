import { vi } from "vitest";

// モックをセット
vi.mock("@/lib", () => ({
    protectedApiClient: { post: vi.fn() },
}));
const mockedNavigate = vi.fn();
vi.mock("react-router", () => ({
    useNavigate: () => mockedNavigate,
}));

import { act, renderHook, waitFor } from "@testing-library/react";
import { AxiosResponse } from "axios";

import { paths } from "@/config/paths";
import { SetEmailAndPasswordPayload, useSetEmailAndPassword } from "@/features/user";
import { protectedApiClient } from "@/lib";
import { useErrorMessageStore, useNotificationStore, useUserAuthStore } from "@/stores";
import { createQueryWrapper, resetStoresAndMocks } from "@/test";
import { User } from "@/types";

describe("useSetEmailAndPassword", () => {
    const wrapper = createQueryWrapper();

    beforeEach(() => {
        // Zustandストアとモック関数をリセット
        resetStoresAndMocks([]);
        vi.mocked(protectedApiClient.post).mockReset();
        mockedNavigate.mockReset();
        // 各種ストアをスパイ
        vi.spyOn(useErrorMessageStore.getState(), "clearErrors");
        vi.spyOn(useNotificationStore.getState(), "setNotification");
        vi.spyOn(useUserAuthStore.getState(), "updateUserInfo");
    });

    it("メールアドレス付きペイロードの場合、ストア更新・通知・リダイレクトが実行されること", async () => {
        const payload: SetEmailAndPasswordPayload = {
            email: "new@example.com",
            password: "pass123",
            confirmPassword: "pass123",
        };
        // モックレスポンス
        const returnedUser: User = {
            id: "1",
            email: "test-user@exmple.com@example.com",
            username: "test-user",
            profileImage: null,
            twoFactorAuthEnabled: false,
            hasPassword: true,
            authProviders: [],
        };
        const mockResponse = { status: 200, data: returnedUser } as AxiosResponse<User>;
        vi.mocked(protectedApiClient.post).mockResolvedValueOnce(mockResponse);

        // フックをレンダリング
        const { result } = renderHook(() => useSetEmailAndPassword(), { wrapper });

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
            "メールアドレスとパスワードを設定しました。",
            "success",
        );

        // updateUserInfoが正しい引数で呼び出されること
        expect(useUserAuthStore.getState().updateUserInfo).toHaveBeenCalledWith(returnedUser);

        // navigateが正しい引数で呼び出されること
        expect(mockedNavigate).toHaveBeenCalledWith(paths.user, { replace: true });
    });

    it("メールアドレスなしペイロードの場合、ストア更新・通知・リダイレクトが実行されること", async () => {
        const payload: SetEmailAndPasswordPayload = {
            password: "pass123",
            confirmPassword: "pass123",
        };
        const returnedUser: User = {
            id: "1",
            email: null,
            username: "test-user",
            profileImage: null,
            twoFactorAuthEnabled: false,
            hasPassword: true,
            authProviders: [],
        };
        const mockResponse = { status: 200, data: returnedUser } as AxiosResponse<User>;
        vi.mocked(protectedApiClient.post).mockResolvedValueOnce(mockResponse);

        // フックをレンダリング
        const { result } = renderHook(() => useSetEmailAndPassword(), { wrapper });

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
            "パスワードを設定しました。",
            "success",
        );

        // updateUserInfoが正しい引数で呼び出されること
        expect(useUserAuthStore.getState().updateUserInfo).toHaveBeenCalledWith(returnedUser);

        // navigateが正しい引数で呼び出されること
        expect(mockedNavigate).toHaveBeenCalledWith(paths.user, { replace: true });
    });
});
