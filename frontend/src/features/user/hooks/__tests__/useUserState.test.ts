import { getUserState, UserState, useUserState } from "@/features/user";
import { useUserAuthStore } from "@/stores";
import { User } from "@/types";
import { act, renderHook } from "@testing-library/react";

describe("getUserState", () => {
    it("userがnullのとき、UNKNOWNを返すこと", () => {
        expect(getUserState(null)).toBe(UserState.UNKNOWN);
    });

    it("メールアドレスあり、パスワードあり、プロバイダーなしのとき、EMAIL_PASSWORDを返すこと", () => {
        const user: User = {
            id: "1",
            email: "test-user1@exmple.com",
            username: "test-user1",
            profileImage: null,
            twoFactorAuthEnabled: false,
            hasPassword: true,
            authProviders: [],
        };
        expect(getUserState(user)).toBe(UserState.EMAIL_PASSWORD);
    });

    it("メールアドレスあり、パスワードなし、プロバイダーありのとき、EMAIL_WITH_PROVIDERを返すこと", () => {
        const user: User = {
            id: "2",
            email: "test-user2@exmple.com",
            username: "test-user2",
            profileImage: null,
            twoFactorAuthEnabled: false,
            hasPassword: false,
            authProviders: ["github"],
        };
        expect(getUserState(user)).toBe(UserState.EMAIL_WITH_PROVIDER);
    });

    it("メールアドレスなし、パスワードなし、プロバイダーありのとき、PROVIDER_ONLYを返すこと", () => {
        const user: User = {
            id: "3",
            email: null,
            username: "test-user3",
            profileImage: null,
            twoFactorAuthEnabled: false,
            hasPassword: false,
            authProviders: ["google"],
        };
        expect(getUserState(user)).toBe(UserState.PROVIDER_ONLY);
    });

    it("メールアドレスあり、パスワードあり、プロバイダーありのとき、EMAIL_PASSWORD_WITH_PROVIDERを返すこと", () => {
        const user: User = {
            id: "4",
            email: "test-user4@exmple.com",
            username: "test-user4",
            profileImage: null,
            twoFactorAuthEnabled: false,
            hasPassword: true,
            authProviders: ["github", "google"],
        };
        expect(getUserState(user)).toBe(UserState.EMAIL_PASSWORD_WITH_PROVIDER);
    });

    it("想定外の組み合わせでもUNKNOWNを返すこと", () => {
        const user: User = {
            id: "5",
            email: null,
            username: "test-user5",
            profileImage: null,
            twoFactorAuthEnabled: false,
            hasPassword: true,
            authProviders: [],
        };
        expect(getUserState(user)).toBe(UserState.UNKNOWN);
    });
});

describe("useUserState", () => {
    beforeEach(() => {
        // ストアをクリア
        useUserAuthStore.getState().setLogout();
    });

    it("userがnullのとき、UNKNOWNを返すこと", () => {
        const { result } = renderHook(() => useUserState());
        expect(result.current).toBe(UserState.UNKNOWN);
    });

    it("EMAIL_PASSWORD状態のユーザーをセットすると EMAIL_PASSWORDを返すこと", () => {
        const user: User = {
            id: "10",
            email: "test-user10@exmple.com",
            username: "test-user10",
            profileImage: null,
            twoFactorAuthEnabled: false,
            hasPassword: true,
            authProviders: [],
        };
        act(() => {
            useUserAuthStore.getState().setLogin(user);
        });
        const { result } = renderHook(() => useUserState());
        expect(result.current).toBe(UserState.EMAIL_PASSWORD);
    });

    it("EMAIL_WITH_PROVIDER状態のユーザーをセットすると EMAIL_WITH_PROVIDERを返すこと", () => {
        const user: User = {
            id: "11",
            email: "test-user11@exmple.com",
            username: "test-user11",
            profileImage: null,
            twoFactorAuthEnabled: false,
            hasPassword: false,
            authProviders: ["github"],
        };
        act(() => {
            useUserAuthStore.getState().setLogin(user);
        });
        const { result } = renderHook(() => useUserState());
        expect(result.current).toBe(UserState.EMAIL_WITH_PROVIDER);
    });

    it("PROVIDER_ONLY状態のユーザーをセットすると PROVIDER_ONLYを返すこと", () => {
        const user: User = {
            id: "12",
            email: null,
            username: "test-user12",
            profileImage: null,
            twoFactorAuthEnabled: false,
            hasPassword: false,
            authProviders: ["google"],
        };
        act(() => {
            useUserAuthStore.getState().setLogin(user);
        });
        const { result } = renderHook(() => useUserState());
        expect(result.current).toBe(UserState.PROVIDER_ONLY);
    });

    it("EMAIL_PASSWORD_WITH_PROVIDER状態のユーザーをセットすると EMAIL_PASSWORD_WITH_PROVIDERを返すこと", () => {
        const user: User = {
            id: "13",
            email: "test-user13@exmple.com",
            username: "test-user13",
            profileImage: null,
            twoFactorAuthEnabled: false,
            hasPassword: true,
            authProviders: ["github", "google"],
        };
        act(() => {
            useUserAuthStore.getState().setLogin(user);
        });
        const { result } = renderHook(() => useUserState());
        expect(result.current).toBe(UserState.EMAIL_PASSWORD_WITH_PROVIDER);
    });
});
