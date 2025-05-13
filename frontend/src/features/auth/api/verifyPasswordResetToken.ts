import { publicApiClient } from "@/lib";

/**
 * パスワードリセットトークン検証リクエスト
 */
export interface VerifyPasswordResetTokenPayload {
    token: string;
}

/**
 * パスワードリセットトークン検証API
 *
 * @param payload トークン
 */
export const verifyPasswordResetToken = (payload: VerifyPasswordResetTokenPayload): Promise<void> =>
    publicApiClient.post("/auth/password/reset/verify", payload);
