import { publicApiClient } from "@/lib";
import type { AxiosResponse } from "axios";

/**
 * 確認のリンクを受け付けた結果
 */
export type EmailVerificationResult =
    | "VERIFIED"
    | "PASSWORD_RESET_READY"
    | "ALREADY_VERIFIED"
    | "EXPIRED"
    | "REGISTRATION_GONE"
    | "EMAIL_TAKEN"
    | "INVALID";

/**
 * 確認のリンクの受け付けリクエスト
 */
export interface VerifyEmailPayload {
    token: string;
}

/**
 * 確認のリンクの受け付けレスポンス
 */
export interface VerifyEmailResponse {
    result: EmailVerificationResult;
    /** 結果が PASSWORD_RESET_READY のときだけ入る、パスワードの再設定のトークン */
    passwordResetToken: string | null;
}

/**
 * 確認のリンクの受け付けAPI
 * @param payload 確認のリンクの受け付けリクエスト
 * @returns Axiosレスポンス
 */
export const verifyEmail = (payload: VerifyEmailPayload): Promise<AxiosResponse<VerifyEmailResponse>> =>
    publicApiClient.post("/auth/email-verification/verify", payload);
