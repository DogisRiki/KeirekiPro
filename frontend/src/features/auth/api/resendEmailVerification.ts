import { publicApiClient } from "@/lib";
import type { AxiosResponse } from "axios";

/**
 * 確認のメールの送り直しリクエスト
 */
export interface ResendEmailVerificationPayload {
    token: string;
}

/**
 * 使えなくなった確認のリンクから、確認のメールを送り直すAPI
 * @param payload 確認のメールの送り直しリクエスト
 * @returns Axiosレスポンス
 */
export const resendEmailVerification = (payload: ResendEmailVerificationPayload): Promise<AxiosResponse<void>> =>
    publicApiClient.post("/auth/email-verification/resend", payload);
