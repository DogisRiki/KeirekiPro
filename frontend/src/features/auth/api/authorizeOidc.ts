import { publicApiClient } from "@/lib";
import { AuthProvider } from "@/types";
import { AxiosResponse } from "axios";

/**
 * OIDC認可URL取得API
 *
 * @param provider 使用するOIDCプロバイダー
 * @returns 認可URLを含むAxiosレスポンス
 */
export const authorizeOidc = (provider: AuthProvider): Promise<AxiosResponse<string>> =>
    publicApiClient.get("/auth/oidc/authorize", {
        params: { provider },
    });
