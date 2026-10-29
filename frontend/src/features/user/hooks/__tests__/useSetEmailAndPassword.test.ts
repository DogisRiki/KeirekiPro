import type * as ReactRouter from "react-router";
import { vi } from "vitest";

// モックをセット
vi.mock("@/lib", () => ({
    protectedApiClient: { post: vi.fn() },
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
import type { SetEmailAndPasswordPayload } from "@/features/user";
import { useSetEmailAndPassword } from "@/features/user";
import { protectedApiClient } from "@/lib";
import { useErrorMessageStore, useNotificationStore, useUserAuthStore } from "@/stores";
import { createQueryWrapper, mutateHook, resetStoresAndMocks } from "@/test";
import type { User } from "@/types";

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

    it("成功すると確認のメールを送ったことと設定待ちであることを伝える文を出す", async () => {
        const payload: SetEmailAndPasswordPayload = {
            email: "new@example.com",
            password: "pass123",
            confirmPassword: "pass123",
        };
        // モックレスポンス(設定したメールアドレスは、確認を済ませるまで設定待ちになる)
        const returnedUser: User = {
            id: "1",
            email: null,
            username: "test-user",
            profileImage: null,
            twoFactorAuthEnabled: false,
            hasPassword: true,
            authProviders: ["google"],
            roles: ["USER"],
            emailVerified: false,
            pendingEmail: "new@example.com",
        };
        const mockResponse = { status: 200, data: returnedUser } as AxiosResponse<User>;
        vi.mocked(protectedApiClient.post).mockResolvedValueOnce(mockResponse);

        // フックをレンダリング
        const { result } = renderHook(() => useSetEmailAndPassword(), { wrapper });

        // ミューテート実行
        mutateHook(result, payload);

        // 成功状態になるまで待機
        await waitFor(() => expect(result.current.isSuccess).toBe(true));

        // clearErrorsがonMutateとonSuccessで計2回呼び出されること
        expect(useErrorMessageStore.getState().clearErrors).toHaveBeenCalledTimes(2);

        // setNotificationが正しい引数で呼び出されること
        expect(useNotificationStore.getState().setNotification).toHaveBeenCalledWith(
            "確認のメールを送りました。\nメールの中の確認のリンクを押すまで、メールアドレスは設定待ちです。",
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
            roles: ["USER"],
            emailVerified: true,
            pendingEmail: null,
        };
        const mockResponse = { status: 200, data: returnedUser } as AxiosResponse<User>;
        vi.mocked(protectedApiClient.post).mockResolvedValueOnce(mockResponse);

        // フックをレンダリング
        const { result } = renderHook(() => useSetEmailAndPassword(), { wrapper });

        // ミューテート実行
        mutateHook(result, payload);

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
