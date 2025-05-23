import { protectedApiClient } from "@/lib";
import { AxiosResponse } from "axios";

/**
 * パスワード変更用ペイロード
 */
export interface ChangePasswordPayload {
    nowPassword: string;
    newPassword: string;
}

/**
 * パスワード変更API
 * @param payload パスワード変更リクエスト
 * @returns Axiosレスポンス
 */
export const changePassword = (payload: ChangePasswordPayload): Promise<AxiosResponse<void>> =>
    protectedApiClient.patch("/users/me/password", payload);
