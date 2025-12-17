import type { Resume } from "@/features/resume";
import { protectedApiClient } from "@/lib";
import type { AxiosResponse } from "axios";

/**
 * SNS更新ペイロード
 */
export interface UpdateSocialLinkPayload {
    name: string;
    link: string;
}

/**
 * 職務経歴書 SNS更新API
 * @param resumeId 職務経歴書ID
 * @param socialLinkId SNSID
 * @param payload SNS更新リクエスト
 * @returns 更新された職務経歴書情報を含むAxiosレスポンス
 */
export const updateSocialLink = (
    resumeId: string,
    socialLinkId: string,
    payload: UpdateSocialLinkPayload,
): Promise<AxiosResponse<Resume>> =>
    protectedApiClient.put<Resume>(`/resumes/${resumeId}/social-links/${socialLinkId}`, payload);
