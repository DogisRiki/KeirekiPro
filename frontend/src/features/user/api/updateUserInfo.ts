import { protectedApiClient } from "@/lib";
import type { User } from "@/types";
import type { AxiosResponse } from "axios";

/**
 * ユーザー情報更新用ペイロード
 */
export interface UpdateUserInfoPayload {
    username?: string;
    profileImage?: File;
    twoFactorAuthEnabled?: boolean;
}

/**
 * ユーザー情報更新 API
 * @param payload 更新内容
 * @returns 更新後のUserを含むAxiosレスポンス
 */
export const updateUserInfo = (payload: UpdateUserInfoPayload): Promise<AxiosResponse<User>> => {
    const formData = new FormData();

    if (payload.username !== undefined) {
        formData.append("username", payload.username);
    }
    if (payload.profileImage !== undefined) {
        formData.append("profileImage", payload.profileImage);
    }
    if (payload.twoFactorAuthEnabled !== undefined) {
        formData.append("twoFactorAuthEnabled", String(payload.twoFactorAuthEnabled));
    }

    return protectedApiClient.put("/users/me", formData, {
        headers: { "Content-Type": "multipart/form-data" },
    });
};
