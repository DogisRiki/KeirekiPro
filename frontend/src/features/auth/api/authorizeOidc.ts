import { publicApiClient } from "@/lib";
import { AxiosResponse } from "axios";

/**
 * OIDC認可URL取得API
 *
 * @param provider 使用するOIDCプロバイダー（"google" | "github"）
 * @returns 認可URLを含むAxiosレスポンス
 */
export const authorizeOidc = (provider: "google" | "github"): Promise<AxiosResponse<string>> =>
    publicApiClient.get("/auth/oidc/authorize", {
        params: { provider },
    });
