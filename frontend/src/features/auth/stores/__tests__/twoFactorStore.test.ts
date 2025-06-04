import { useTwoFactorStore } from "@/features/auth";

describe("useTwoFactorStore", () => {
    beforeEach(() => {
        // テスト前にストアをリセット
        useTwoFactorStore.getState().clear();
    });

    it("初期状態でuserIdがnullであること", () => {
        const { userId } = useTwoFactorStore.getState();
        expect(userId).toBeNull();
    });

    it("setUserIdでユーザーIDを設定できること", () => {
        const testUserId = "test-user-123";

        // setUserIdを実行
        useTwoFactorStore.getState().setUserId(testUserId);

        // userIdが設定されていること
        const { userId } = useTwoFactorStore.getState();
        expect(userId).toBe(testUserId);
    });

    it("clearでuserIdがnullにリセットされること", () => {
        const testUserId = "test-user-123";

        // まずuserIdを設定
        useTwoFactorStore.getState().setUserId(testUserId);
        expect(useTwoFactorStore.getState().userId).toBe(testUserId);

        // clearを実行
        useTwoFactorStore.getState().clear();

        // userIdがnullになっていること
        const { userId } = useTwoFactorStore.getState();
        expect(userId).toBeNull();
    });

    it("複数回setUserIdを呼び出しても最後の値が保持されること", () => {
        const firstUserId = "first-user";
        const secondUserId = "second-user";

        // 最初のuserIdを設定
        useTwoFactorStore.getState().setUserId(firstUserId);
        expect(useTwoFactorStore.getState().userId).toBe(firstUserId);

        // 2番目のuserIdを設定
        useTwoFactorStore.getState().setUserId(secondUserId);
        expect(useTwoFactorStore.getState().userId).toBe(secondUserId);
    });
});
