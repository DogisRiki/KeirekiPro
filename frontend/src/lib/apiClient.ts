import { paths } from "@/config/paths";
import { useErrorMessageStore } from "@/stores";
import axios from "axios";

// 共通のエラーハンドリングインターセプター
const errorHandlerInterceptor = (error: unknown) => {
    if (axios.isAxiosError(error)) {
        // バリデーションエラー
        if (error.response?.status === 400) {
            useErrorMessageStore.getState().setErrors(error.response?.data);
        }
    }
    return Promise.reject(error);
};

// ベースとなるAxiosインスタンス
const baseApiClient = axios.create({
    baseURL: import.meta.env.VITE_API_URL,
    headers: {
        "Content-Type": "application/json",
    },
});

// 共通のエラーハンドリングを適用
baseApiClient.interceptors.response.use((response) => response, errorHandlerInterceptor);

// 認証不要なAPIに使用するクライアント
export const publicApiClient = baseApiClient;

// 認証が必要なAPIに使用するクライアント
export const protectedApiClient = axios.create({
    ...baseApiClient.defaults,
    withCredentials: true,
});

// リクエストインターセプター（認証用）
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

// レスポンスインターセプター（認証用）
protectedApiClient.interceptors.response.use(
    (response) => response,
    async (error) => {
        // 先に共通のエラーハンドリングを実行
        errorHandlerInterceptor(error);

        if (axios.isAxiosError(error)) {
            const originalRequest = error.config;
            // 元のリクエストが存在しない場合、処理を中断
            if (!originalRequest) {
                return Promise.reject(error);
            }
            // 401エラーの場合はリフレッシュトークンでアクセストークンを更新
            if (error.response?.status === 401) {
                try {
                    await protectedApiClient.post("/auth/refresh-token");
                    // 元のリクエストを再試行
                    return protectedApiClient(originalRequest);
                } catch (refreshError) {
                    // リフレッシュ失敗時はログイン画面へリダイレクト
                    window.location.href = paths.login;
                    return Promise.reject(refreshError);
                }
            }
        }
        return Promise.reject(error);
    },
);
