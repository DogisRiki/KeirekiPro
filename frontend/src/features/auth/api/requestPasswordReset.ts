import { publicApiClient } from "@/lib";
import { AxiosResponse } from "axios";

/**
 * パスワードリセット要求リクエスト
 */
export interface RequestPasswordResetPayload {
    email: string;
}

/**
 * パスワードリセット要求API
 */
export const requestPasswordReset = (payload: RequestPasswordResetPayload): Promise<AxiosResponse<void>> =>
    publicApiClient.post("/auth/password/reset/request", payload);
