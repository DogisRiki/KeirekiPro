import { publicApiClient } from "@/lib";
import type { AxiosResponse } from "axios";

/**
 * ログインの画面から確認のメールを送るリクエスト
 */
export interface ResendEmailVerificationForLoginPayload {
    email: string;
    password: string;
}

/**
 * ログインの画面で入力したメールアドレスとパスワードで、確認のメールを送るAPI
 * @param payload ログインの画面から確認のメールを送るリクエスト
 * @returns Axiosレスポンス
 */
export const resendEmailVerificationForLogin = (
    payload: ResendEmailVerificationForLoginPayload,
): Promise<AxiosResponse<void>> => publicApiClient.post("/auth/email-verification/resend-for-login", payload);
