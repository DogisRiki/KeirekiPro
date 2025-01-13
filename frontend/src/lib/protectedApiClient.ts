import { paths } from "@/config/paths";
import { baseApiClient } from "@/lib/baseApiClient";
import { useNotificationStore } from "@/stores";
import axios from "axios";

/**
 * 認証が必要なAPIに使用するクライアント
 */
export const protectedApiClient = axios.create({
    ...baseApiClient.defaults,
    withCredentials: true,
});

// リクエストインターセプター
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

// レスポンスインターセプター
protectedApiClient.interceptors.response.use(
    (response) => response,
    async (error) => {
        if (axios.isAxiosError(error)) {
            const originalRequest = error.config;
            if (!originalRequest) return Promise.reject(error);
            // 認証エラーの場合はリフレッシュトークンでアクセストークンを更新
            if (error.response?.status === 401) {
                try {
                    await protectedApiClient.post("/auth/refresh-token");
                    // 元のリクエストを再試行
                    return protectedApiClient(originalRequest);
                } catch (refreshError) {
                    // リフレッシュ失敗時はログイン画面へリダイレクト
                    useNotificationStore.getState().setNotification(error.response.data?.message, "error");
                    window.location.href = paths.login;
                    return Promise.reject(refreshError);
                }
            }
        }
        return Promise.reject(error);
    },
);
