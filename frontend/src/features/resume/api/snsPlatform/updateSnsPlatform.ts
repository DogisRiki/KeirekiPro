import type { Resume } from "@/features/resume";
import { protectedApiClient } from "@/lib";
import type { AxiosResponse } from "axios";

/**
 * SNSプラットフォーム更新ペイロード
 */
export interface UpdateSnsPlatformPayload {
    name: string;
    link: string;
}

/**
 * 職務経歴書 SNSプラットフォーム更新API
 * @param resumeId 職務経歴書ID
 * @param snsPlatformId SNSプラットフォームID
 * @param payload SNSプラットフォーム更新リクエスト
 * @returns 更新された職務経歴書情報を含むAxiosレスポンス
 */
export const updateSnsPlatform = (
    resumeId: string,
    snsPlatformId: string,
    payload: UpdateSnsPlatformPayload,
): Promise<AxiosResponse<Resume>> =>
    protectedApiClient.put<Resume>(`/resumes/${resumeId}/sns-platforms/${snsPlatformId}`, payload);
