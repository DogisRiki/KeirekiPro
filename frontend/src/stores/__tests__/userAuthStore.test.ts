import { useUserAuthStore } from "@/stores";
import type { AuthProvider, User, UserPatch } from "@/types";

// localStorageのモック
const localStorageMock = {
    getItem: vi.fn(),
    setItem: vi.fn(),
    removeItem: vi.fn(),
    clear: vi.fn(),
};

Object.defineProperty(window, "localStorage", {
    value: localStorageMock,
});

describe("useUserAuthStore", () => {
    const mockUser: User = {
        id: "1",
        email: "test-user@example.com",
        username: "test-user",
        profileImage: "https://example.com/avatar.jpg",
        twoFactorAuthEnabled: false,
        hasPassword: true,
        authProviders: ["github"],
    };

    beforeEach(() => {
        // テスト前にストアをリセット
        useUserAuthStore.getState().setLogout();
        // localStorageのモックをリセット
        vi.clearAllMocks();
    });

    it("初期状態でuserがnull、isAuthenticatedがfalseであること", () => {
        const { user, isAuthenticated } = useUserAuthStore.getState();
        expect(user).toBeNull();
        expect(isAuthenticated).toBe(false);
    });

    it("setLoginでユーザー情報とログイン状態を設定できること", () => {
        // setLoginを実行
        useUserAuthStore.getState().setLogin(mockUser);

        // userとisAuthenticatedが正しく設定されていること
        const { user, isAuthenticated } = useUserAuthStore.getState();
        expect(user).toEqual(mockUser);
        expect(isAuthenticated).toBe(true);
    });

    it("setLogoutでユーザー情報とログイン状態がリセットされること", () => {
        // まずログイン状態にする
        useUserAuthStore.getState().setLogin(mockUser);
        expect(useUserAuthStore.getState().user).toEqual(mockUser);
        expect(useUserAuthStore.getState().isAuthenticated).toBe(true);

        // setLogoutを実行
        useUserAuthStore.getState().setLogout();

        // userとisAuthenticatedがリセットされていること
        const { user, isAuthenticated } = useUserAuthStore.getState();
        expect(user).toBeNull();
        expect(isAuthenticated).toBe(false);
    });

    it("setRefreshでisAuthenticatedのみがtrueに設定されること", () => {
        // 初期状態を確認
        expect(useUserAuthStore.getState().isAuthenticated).toBe(false);
        expect(useUserAuthStore.getState().user).toBeNull();

        // setRefreshを実行
        useUserAuthStore.getState().setRefresh();

        // isAuthenticatedのみがtrueになり、userはnullのまま
        const { user, isAuthenticated } = useUserAuthStore.getState();
        expect(isAuthenticated).toBe(true);
        expect(user).toBeNull();
    });

    it("updateUserInfoでユーザー情報の一部を更新できること", () => {
        // まずユーザーをログイン状態にする
        useUserAuthStore.getState().setLogin(mockUser);

        const patch: UserPatch = {
            username: "updateduser",
            profileImage: "https://example.com/new-avatar.jpg",
            twoFactorAuthEnabled: true,
        };

        // updateUserInfoを実行
        useUserAuthStore.getState().updateUserInfo(patch);

        // ユーザー情報が部分的に更新されていること
        const { user } = useUserAuthStore.getState();
        expect(user).toEqual({
            ...mockUser,
            ...patch,
        });
    });

    it("updateUserInfoでユーザーがnullの場合は何も更新されないこと", () => {
        // ユーザーがnullの状態で実行
        const patch: UserPatch = {
            username: "shouldnotupdate",
        };

        // updateUserInfoを実行
        useUserAuthStore.getState().updateUserInfo(patch);

        // userはnullのまま
        const { user } = useUserAuthStore.getState();
        expect(user).toBeNull();
    });

    it("複数のフィールドを段階的に更新できること", () => {
        // まずユーザーをログイン状態にする
        useUserAuthStore.getState().setLogin(mockUser);

        // 最初の更新
        useUserAuthStore.getState().updateUserInfo({ username: "new-username" });
        expect(useUserAuthStore.getState().user?.username).toBe("new-username");

        // 2回目の更新
        useUserAuthStore.getState().updateUserInfo({ twoFactorAuthEnabled: true });
        expect(useUserAuthStore.getState().user?.twoFactorAuthEnabled).toBe(true);
        expect(useUserAuthStore.getState().user?.username).toBe("new-username"); // 前の更新が保持されている

        // 3回目の更新
        useUserAuthStore.getState().updateUserInfo({ email: "new-email@example.com" });
        const { user } = useUserAuthStore.getState();
        expect(user?.email).toBe("new-email@example.com");
        expect(user?.username).toBe("new-username");
        expect(user?.twoFactorAuthEnabled).toBe(true);
    });

    it("authProvidersの配列も正しく更新できること", () => {
        // まずユーザーをログイン状態にする
        useUserAuthStore.getState().setLogin(mockUser);

        // authProvidersを更新
        const newAuthProviders = ["github", "google"] as AuthProvider[];
        useUserAuthStore.getState().updateUserInfo({ authProviders: newAuthProviders });

        // authProvidersが更新されていること
        const { user } = useUserAuthStore.getState();
        expect(user?.authProviders).toEqual(newAuthProviders);
    });
});
