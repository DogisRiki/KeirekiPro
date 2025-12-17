import { publicApiClient } from "@/lib";
import type { AxiosResponse } from "axios";

/**
 * パスワードリセット要求リクエスト
 */
export interface RequestPasswordResetPayload {
    email: string;
}

/**
 * パスワードリセット要求API
 * @param payload パスワードリセット要求リクエスト
 * @returns Axiosレスポンス
 */
export const requestPasswordReset = (payload: RequestPasswordResetPayload): Promise<AxiosResponse<void>> =>
    publicApiClient.post("/auth/password/reset/request", payload);
