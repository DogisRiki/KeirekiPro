import { toastMessage } from "@/config/messages";
import { useErrorMessageStore, useNotificationStore } from "@/stores";
import { ErrorResponse } from "@/types";
import axios from "axios";

/**
 * 共通エラーインターセプタ
 */
export const createErrorInterceptor =
    () =>
    (error: unknown): Promise<never> => {
        if (axios.isAxiosError(error)) {
            const { response } = error;

            // 400(バリデーションエラー)
            if (response?.status === 400 && response.data) {
                useErrorMessageStore.getState().setErrors(response.data as ErrorResponse);
            }

            // 500(サーバーエラー)
            if (response?.status === 500) {
                useNotificationStore.getState().setNotification(toastMessage.serverError, "error");
            }
        }
        return Promise.reject(error);
    };
