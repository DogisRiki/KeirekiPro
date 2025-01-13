import { useNotificationStore } from "@/stores";
import { SuccessResponse } from "@/types";
import axios, { AxiosResponse } from "axios";

/**
 * ベースとなるAPIクライアント
 */
export const baseApiClient = axios.create({
    baseURL: import.meta.env.VITE_API_URL,
    headers: {
        "Content-Type": "application/json",
    },
});

// 成功メッセージを通知するインターセプター
const successHandlerInterceptor = <T>(response: AxiosResponse<SuccessResponse<T>>) => {
    // 200番台かつメッセージが存在する場合に、メッセージをストアに格納する
    if (response.status >= 200 && response.status < 300) {
        const message = response.data?.message;
        if (message) {
            useNotificationStore.getState().setNotification(message, "success");
        }
    }
    return response;
};

// 共通のエラーハンドリングインターセプター
const errorHandlerInterceptor = (error: unknown) => {
    if (axios.isAxiosError(error)) {
        if (error.response?.status === 400) {
            useNotificationStore.getState().setNotification(error.response.data?.message, "error");
        } else if (error.response?.status === 500) {
            useNotificationStore
                .getState()
                .setNotification(
                    "システムエラーが発生しました。\nお手数ですが、時間をおいて再度お試しください。",
                    "error",
                );
        }
    }
    return Promise.reject(error);
};

baseApiClient.interceptors.response.use(successHandlerInterceptor, errorHandlerInterceptor);
