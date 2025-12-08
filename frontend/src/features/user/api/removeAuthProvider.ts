import { protectedApiClient } from "@/lib";
import type { AuthProvider } from "@/types";
import type { AxiosResponse } from "axios";

/**
 * 外部認証連携解除API
 * @param provider 解除する認証プロバイダー
 * @returns Axiosレスポンス
 */
export const removeAuthProvider = (provider: AuthProvider): Promise<AxiosResponse<void>> =>
    protectedApiClient.delete(`/users/me/auth-provider/${provider}`);
