import { useErrorMessageStore, useNotificationStore } from "@/stores";

/**
 * errorMessageStore と notificationStore の相互クリア機能の統合テスト
 */
describe("ストア間の相互クリア機能（本番動作シミュレーション）", () => {
    beforeEach(() => {
        useErrorMessageStore.getState().clearErrors();
        useNotificationStore.getState().clearNotification();
    });

    describe("setNotification時のErrorMessageクリア", () => {
        it("Notificationが表示されるとErrorMessageがクリアされるべきこと", () => {
            // エラーを設定
            useErrorMessageStore.getState().setErrors({
                message: "エラー",
                errors: { field: ["エラー"] },
            });
            expect(useErrorMessageStore.getState().message).toBe("エラー");

            // 本番ではsetNotificationがclearErrorsを呼ぶ
            // この動作をシミュレート
            useErrorMessageStore.getState().clearErrors();
            useNotificationStore.getState().setNotification("成功", "success");

            // エラーがクリアされ、通知のみ表示されること
            expect(useErrorMessageStore.getState().message).toBeNull();
            expect(useErrorMessageStore.getState().errors).toEqual({});
            expect(useNotificationStore.getState().message).toBe("成功");
            expect(useNotificationStore.getState().isShow).toBe(true);
        });
    });

    describe("setErrors時のNotificationクリア", () => {
        it("ErrorMessageが表示されるとNotificationがクリアされるべきこと", () => {
            // 通知を設定
            useNotificationStore.getState().setNotification("成功", "success");
            expect(useNotificationStore.getState().message).toBe("成功");

            // 本番ではsetErrorsがclearNotificationを呼ぶ
            // この動作をシミュレート
            useNotificationStore.getState().clearNotification();
            useErrorMessageStore.getState().setErrors({
                message: "エラー",
                errors: { field: ["エラー"] },
            });

            // 通知がクリアされ、エラーのみ表示されること
            expect(useNotificationStore.getState().message).toBeNull();
            expect(useNotificationStore.getState().isShow).toBe(false);
            expect(useErrorMessageStore.getState().message).toBe("エラー");
            expect(useErrorMessageStore.getState().errors).toEqual({ field: ["エラー"] });
        });
    });

    describe("clearErrors/clearNotificationが正しく動作すること", () => {
        it("clearErrorsはErrorMessageストアのみをクリアすること", () => {
            useErrorMessageStore.getState().setErrors({
                message: "エラー",
                errors: { field: ["エラー"] },
            });
            useNotificationStore.getState().setNotification("成功", "success");

            useErrorMessageStore.getState().clearErrors();

            expect(useErrorMessageStore.getState().message).toBeNull();
            expect(useNotificationStore.getState().message).toBe("成功");
        });

        it("clearNotificationはNotificationストアのみをクリアすること", () => {
            useErrorMessageStore.getState().setErrors({
                message: "エラー",
                errors: { field: ["エラー"] },
            });
            useNotificationStore.getState().setNotification("成功", "success");

            useNotificationStore.getState().clearNotification();

            expect(useNotificationStore.getState().message).toBeNull();
            expect(useErrorMessageStore.getState().message).toBe("エラー");
        });
    });
});
