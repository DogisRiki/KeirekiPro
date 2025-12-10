import type { Resume } from "@/features/resume";
import { protectedApiClient } from "@/lib";
import type { AxiosResponse } from "axios";

/**
 * ソーシャルリンク更新用ペイロード
 */
export interface UpdateSocialLinksPayload {
    socialLinks: {
        id?: string | null;
        name: string;
        link: string;
    }[];
}

/**
 * 職務経歴書ソーシャルリンク更新API
 * @param resumeId 職務経歴書ID
 * @param payload ソーシャルリンク更新リクエスト
 * @returns 更新後の職務経歴書情報を含むAxiosレスポンス
 */
export const updateSocialLinks = (
    resumeId: string,
    payload: UpdateSocialLinksPayload,
): Promise<AxiosResponse<Resume>> => protectedApiClient.put<Resume>(`/resumes/${resumeId}/social-links`, payload);
