import { useErrorMessageStore, useNotificationStore } from "@/stores";
import type { ErrorResponse } from "@/types";

describe("useErrorMessageStore", () => {
    beforeEach(() => {
        // テスト前にストアをリセット
        useErrorMessageStore.getState().clearErrors();
        useNotificationStore.getState().clearNotification();
    });

    it("初期状態でmessageがnull、errorsが空オブジェクトであること", () => {
        const { message, errors } = useErrorMessageStore.getState();
        expect(message).toBeNull();
        expect(errors).toEqual({});
    });

    it("setErrorsでエラーレスポンスを設定できること", () => {
        const errorResponse: ErrorResponse = {
            message: "バリデーションエラーが発生しました",
            errors: {
                email: ["メールアドレスは必須です", "メールアドレスの形式が正しくありません"],
                password: ["パスワードは8文字以上である必要があります"],
            },
        };

        // setErrorsを実行
        useErrorMessageStore.getState().setErrors(errorResponse);

        // messageとerrorsが設定されていること
        const { message, errors } = useErrorMessageStore.getState();
        expect(message).toBe(errorResponse.message);
        expect(errors).toEqual(errorResponse.errors);
    });

    it("clearErrorsでmessageとerrorsがリセットされること", () => {
        const errorResponse: ErrorResponse = {
            message: "エラーメッセージ",
            errors: {
                field1: ["エラー1"],
                field2: ["エラー2", "エラー3"],
            },
        };

        // まずエラーを設定
        useErrorMessageStore.getState().setErrors(errorResponse);
        expect(useErrorMessageStore.getState().message).toBe(errorResponse.message);
        expect(useErrorMessageStore.getState().errors).toEqual(errorResponse.errors);

        // clearErrorsを実行
        useErrorMessageStore.getState().clearErrors();

        // messageとerrorsがリセットされていること
        const { message, errors } = useErrorMessageStore.getState();
        expect(message).toBeNull();
        expect(errors).toEqual({});
    });

    it("複数回setErrorsを呼び出しても最後の値が保持されること", () => {
        const firstErrorResponse: ErrorResponse = {
            message: "最初のエラー",
            errors: { field1: ["エラー1"] },
        };
        const secondErrorResponse: ErrorResponse = {
            message: "2番目のエラー",
            errors: { field2: ["エラー2"] },
        };

        // 最初のエラーを設定
        useErrorMessageStore.getState().setErrors(firstErrorResponse);
        expect(useErrorMessageStore.getState().message).toBe(firstErrorResponse.message);
        expect(useErrorMessageStore.getState().errors).toEqual(firstErrorResponse.errors);

        // 2番目のエラーを設定
        useErrorMessageStore.getState().setErrors(secondErrorResponse);
        expect(useErrorMessageStore.getState().message).toBe(secondErrorResponse.message);
        expect(useErrorMessageStore.getState().errors).toEqual(secondErrorResponse.errors);
    });

    it("messageが空文字でerrorsが空のErrorResponseでも正しく設定されること", () => {
        const errorResponse: ErrorResponse = {
            message: "",
            errors: {},
        };

        // 事前に何かエラーを設定
        useErrorMessageStore.getState().setErrors({
            message: "既存のエラー",
            errors: { field: ["エラー"] },
        });

        // 空のエラーレスポンスを設定
        useErrorMessageStore.getState().setErrors(errorResponse);

        // messageとerrorsが正しく設定されていること
        const { message, errors } = useErrorMessageStore.getState();
        expect(message).toBe("");
        expect(errors).toEqual({});
    });
});
