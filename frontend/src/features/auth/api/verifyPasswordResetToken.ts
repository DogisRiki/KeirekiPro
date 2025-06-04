import { publicApiClient } from "@/lib";
import { AxiosResponse } from "axios";

/**
 * パスワードリセットトークン検証リクエスト
 */
export interface VerifyPasswordResetTokenPayload {
    token: string;
}

/**
 * パスワードリセットトークン検証API
 * @param payload パスワードリセットトークン検証リクエスト
 * @returns Axiosレスポンス
 */
export const verifyPasswordResetToken = (payload: VerifyPasswordResetTokenPayload): Promise<AxiosResponse<void>> =>
    publicApiClient.post("/auth/password/reset/verify", payload);
