// src/lib/axiosInterceptors.ts
import { toastMessage } from "@/config/messages";
import { paths } from "@/config/paths";
import { useErrorMessageStore, useNotificationStore, useUserAuthStore } from "@/stores";
import type { ErrorResponse } from "@/types";
import axios from "axios";

/**
 * 404ページへリダイレクトするエラーメッセージ
 */
const notFoundMessages = ["職務経歴書が存在しません。"];

/**
 * 共通エラーインターセプタ
 */
export const createErrorInterceptor =
    () =>
    async (error: unknown): Promise<never> => {
        if (axios.isAxiosError(error)) {
            const { response } = error;

            // サーバー無応答／ネットワークエラー
            if (!response) {
                window.location.assign(paths.serverError);
                return Promise.reject(error);
            }

            // 400(バリデーションエラー)
            if (response?.status === 400 && response.data) {
                const contentType = String(response.headers?.["content-type"] ?? "");

                let errorData: ErrorResponse | null = null;

                // responseTypeが"blob"のAPIは、エラーJSONもBlobで来る
                if (response.data instanceof Blob && contentType.includes("application/json")) {
                    try {
                        const text = await response.data.text();
                        errorData = JSON.parse(text) as ErrorResponse;
                    } catch {
                        // JSONとして復元できない場合は何もしない（既存挙動維持）
                        errorData = null;
                    }
                } else {
                    // 通常のJSON API
                    errorData = response.data as ErrorResponse;
                }

                if (errorData) {
                    // 404ページへリダイレクトするエラーメッセージの場合
                    if (notFoundMessages.includes(errorData.message)) {
                        window.location.href = "/not-found";
                        return Promise.reject(error);
                    }

                    useErrorMessageStore.getState().setErrors(errorData);
                }
            }

            // 403(アクセス不正)
            if (response?.status === 403) {
                useUserAuthStore.getState().setLogout();
                window.location.replace(paths.top);
            }

            // 500(サーバーエラー)
            if (response?.status === 500) {
                useNotificationStore.getState().setNotification(toastMessage.serverError, "error");
            }
        }
        return Promise.reject(error);
    };
