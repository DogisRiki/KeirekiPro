import { protectedApiClient } from "@/lib";
import { User } from "@/types";
import { AxiosResponse } from "axios";

/**
 * メールアドレス+パスワード設定用ペイロード
 */
export interface SetEmailAndPasswordPayload {
    email?: string;
    password: string;
    confirmPassword: string;
}

/**
 * メールアドレス+パスワード設定API
 * @param payload メールアドレス+パスワード設定リクエスト
 * @returns Axiosレスポンス
 */
export const setEmailAndPassword = (payload: SetEmailAndPasswordPayload): Promise<AxiosResponse<User>> =>
    protectedApiClient.post("/users/me/email-password", payload);
