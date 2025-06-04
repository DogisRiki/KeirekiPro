import { publicApiClient } from "@/lib";
import { AxiosResponse } from "axios";

/**
 * ユーザー新規登録リクエスト
 */
export interface UserRegistrationPayload {
    email: string;
    username: string;
    password: string;
    confirmPassword: string;
}

/**
 * ユーザー新規登録API
 * @param payload ユーザー新規登録リクエスト
 * @returns Axiosレスポンス
 */
export const userRegister = (payload: UserRegistrationPayload): Promise<AxiosResponse<void>> =>
    publicApiClient.post("/auth/register", payload);
