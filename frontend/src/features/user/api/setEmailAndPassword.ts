import { protectedApiClient } from "@/lib";
import type { User } from "@/types";
import type { AxiosResponse } from "axios";

/**
 * メールアドレス+パスワード設定用ペイロード
 */
export interface SetEmailAndPasswordPayload {
    email?: string;
    /**
     * 今のパスワード(パスワードを持つアカウントが設定待ちのメールアドレスを置き換えるときに送る)
     */
    currentPassword?: string;
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
