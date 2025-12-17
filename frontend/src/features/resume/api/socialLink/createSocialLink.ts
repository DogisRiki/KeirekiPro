import type { Resume } from "@/features/resume";
import { protectedApiClient } from "@/lib";
import type { AxiosResponse } from "axios";

/**
 * SNS新規作成ペイロード
 */
export interface CreateSocialLinkPayload {
    name: string;
    link: string;
}

/**
 * 職務経歴書 SNS新規作成API
 * @param resumeId 職務経歴書ID
 * @param payload SNS新規作成リクエスト
 * @returns 更新された職務経歴書情報を含むAxiosレスポンス
 */
export const createSocialLink = (resumeId: string, payload: CreateSocialLinkPayload): Promise<AxiosResponse<Resume>> =>
    protectedApiClient.post<Resume>(`/resumes/${resumeId}/social-links`, payload);
