import { useErrorMessageStore, useNotificationStore } from "@/stores";

describe("useNotificationStore", () => {
    beforeEach(() => {
        // テスト前にストアをリセット
        useNotificationStore.getState().clearNotification();
        useErrorMessageStore.getState().clearErrors();
    });

    it("初期状態でmessageがnull、typeがundefined、isShowがfalseであること", () => {
        const { message, type, isShow } = useNotificationStore.getState();
        expect(message).toBeNull();
        expect(type).toBeUndefined();
        expect(isShow).toBe(false);
    });

    it("setNotificationでsuccessタイプの通知を設定できること", () => {
        const testMessage = "処理が正常に完了しました";

        // setNotificationを実行
        useNotificationStore.getState().setNotification(testMessage, "success");

        // message、type、isShowが正しく設定されていること
        const { message, type, isShow } = useNotificationStore.getState();
        expect(message).toBe(testMessage);
        expect(type).toBe("success");
        expect(isShow).toBe(true);
    });

    it("setNotificationでerrorタイプの通知を設定できること", () => {
        const testMessage = "エラーが発生しました";

        // setNotificationを実行
        useNotificationStore.getState().setNotification(testMessage, "error");

        // message、type、isShowが正しく設定されていること
        const { message, type, isShow } = useNotificationStore.getState();
        expect(message).toBe(testMessage);
        expect(type).toBe("error");
        expect(isShow).toBe(true);
    });

    it("clearNotificationで通知がリセットされること", () => {
        // まず通知を設定
        useNotificationStore.getState().setNotification("テストメッセージ", "success");
        expect(useNotificationStore.getState().message).toBe("テストメッセージ");
        expect(useNotificationStore.getState().type).toBe("success");
        expect(useNotificationStore.getState().isShow).toBe(true);

        // clearNotificationを実行
        useNotificationStore.getState().clearNotification();

        // すべての値がリセットされていること
        const { message, type, isShow } = useNotificationStore.getState();
        expect(message).toBeNull();
        expect(type).toBeUndefined();
        expect(isShow).toBe(false);
    });

    it("複数回setNotificationを呼び出しても最後の値が保持されること", () => {
        const firstMessage = "最初のメッセージ";
        const secondMessage = "2番目のメッセージ";

        // 最初の通知を設定
        useNotificationStore.getState().setNotification(firstMessage, "success");
        expect(useNotificationStore.getState().message).toBe(firstMessage);
        expect(useNotificationStore.getState().type).toBe("success");

        // 2番目の通知を設定
        useNotificationStore.getState().setNotification(secondMessage, "error");
        expect(useNotificationStore.getState().message).toBe(secondMessage);
        expect(useNotificationStore.getState().type).toBe("error");
        expect(useNotificationStore.getState().isShow).toBe(true);
    });

    it("successからerror、errorからsuccessへの切り替えが正しく動作すること", () => {
        // success通知を設定
        useNotificationStore.getState().setNotification("成功メッセージ", "success");
        expect(useNotificationStore.getState().type).toBe("success");

        // error通知に切り替え
        useNotificationStore.getState().setNotification("エラーメッセージ", "error");
        expect(useNotificationStore.getState().type).toBe("error");

        // 再びsuccess通知に切り替え
        useNotificationStore.getState().setNotification("再度成功メッセージ", "success");
        expect(useNotificationStore.getState().type).toBe("success");
    });
});
