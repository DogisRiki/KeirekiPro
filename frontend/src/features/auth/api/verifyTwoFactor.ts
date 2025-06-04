import { publicApiClient } from "@/lib";
import { AxiosResponse } from "axios";

/**
 * 二段階認証コード検証リクエスト
 */
export interface VerifyTwoFactorPayload {
    userId: string;
    code: string;
}

/**
 * 二段階認証コード検証API
 * @param payload 二段階認証コード検証リクエスト
 * @returns Axiosレスポンス
 */
export const verifyTwoFactor = (payload: VerifyTwoFactorPayload): Promise<AxiosResponse<void>> =>
    publicApiClient.post("/auth/2fa/verify", payload);
