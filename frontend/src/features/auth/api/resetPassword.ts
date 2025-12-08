import { publicApiClient } from "@/lib";
import type { AxiosResponse } from "axios";

/**
 * パスワードリセット実行リクエスト
 */
export interface ResetPasswordPayload {
    token: string;
    password: string;
    confirmPassword: string;
}

/**
 * パスワードリセット実行API
 * @param payload パスワードリセット実行リクエスト
 * @returns Axiosレスポンス
 */
export const resetPassword = (payload: ResetPasswordPayload): Promise<AxiosResponse<void>> =>
    publicApiClient.post("/auth/password/reset", payload);
