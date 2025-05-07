import { toastMessage } from "@/config/messages";
import { paths } from "@/config/paths";
import { baseApiClient } from "@/lib";
import { useNotificationStore, useUserAuthStore } from "@/stores";
import axios from "axios";

/**
 * 認証が必要なAPI通信に使用するクライアント
 */
export const protectedApiClient = axios.create({
    ...baseApiClient.defaults,
    withCredentials: true,
});

/**
 * リクエストインターセプタ
 */
protectedApiClient.interceptors.request.use((config) => {
    const xsrfToken = document.cookie
        .split("; ")
        .find((row) => row.startsWith("XSRF-TOKEN"))
        ?.split("=")[1];
    if (xsrfToken) {
        config.headers["X-XSRF-TOKEN"] = decodeURIComponent(xsrfToken);
    }
    return config;
});

/**
 * レスポンスインターセプタ
 */
protectedApiClient.interceptors.response.use(
    (response) => response,
    async (error) => {
        if (axios.isAxiosError(error)) {
            const originalRequest = error.config;

            if (!originalRequest) {
                // リクエスト情報が無い場合はそのまま例外を伝播
                return Promise.reject(error);
            }

            // 401の場合、トークンリフレッシュ試行
            if (error.response?.status === 401) {
                try {
                    // アクセストークンのリフレッシュを試行
                    await protectedApiClient.post("/api/auth/token/refresh");
                    // リフレッシュに成功した時点で認証フラグを維持
                    useUserAuthStore.getState().setRefresh();
                    // 元のリクエストを再試行して結果を返す
                    return protectedApiClient(originalRequest);
                } catch {
                    // リフレッシュに失敗した場合、エラー通知+ログイン画面遷移
                    useNotificationStore.getState().setNotification(toastMessage.unauthorized, "error");
                    window.location.href = paths.login;
                    return Promise.reject(error);
                }
            }
        }
        return Promise.reject(error);
    },
);
