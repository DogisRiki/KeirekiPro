import { toastMessage } from "@/config/messages";
import { paths } from "@/config/paths";
import { baseApiClient, createErrorInterceptor } from "@/lib";
import { useUserAuthStore } from "@/stores";
import axios from "axios";
import createAuthRefreshInterceptor from "axios-auth-refresh";

/**
 * 認証が必要なAPI通信に使用するクライアント
 */
export const protectedApiClient = axios.create({
    ...baseApiClient.defaults,
    withCredentials: true,
});

/**
 * レスポンスインターセプタ
 */
protectedApiClient.interceptors.response.use((response) => response, createErrorInterceptor());

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
 * 401受信時のトークンリフレッシュ処理
 */
const refreshAuthLogic = async () => {
    try {
        // リフレッシュトークンを使ってアクセストークンを再取得（interceptorから除外）
        await baseApiClient.post("/auth/token/refresh", null, { withCredentials: true, skipAuthRefresh: true });
    } catch {
        // 失敗時、トースト内容をセッションに保存（後で表示される）
        sessionStorage.setItem("global-toast", JSON.stringify({ m: toastMessage.unauthorized, t: "error" }));
        // ログアウト状態にしてログイン画面へ遷移
        useUserAuthStore.getState().setLogout();
        window.location.replace(paths.login);
        // axios-auth-refresh用に例外を再スロー
        throw new Error("refresh failed");
    }
};

createAuthRefreshInterceptor(protectedApiClient, refreshAuthLogic, {
    statusCodes: [401],
    pauseInstanceWhileRefreshing: true,
});
