import type { Resume } from "@/features/resume";
import { protectedApiClient } from "@/lib";
import type { AxiosResponse } from "axios";

/**
 * SNSプラットフォーム新規作成ペイロード
 */
export interface CreateSnsPlatformPayload {
    name: string;
    link: string;
}

/**
 * 職務経歴書 SNSプラットフォーム新規作成API
 * @param resumeId 職務経歴書ID
 * @param payload SNSプラットフォーム新規作成リクエスト
 * @returns 更新された職務経歴書情報を含むAxiosレスポンス
 */
export const createSnsPlatform = (
    resumeId: string,
    payload: CreateSnsPlatformPayload,
): Promise<AxiosResponse<Resume>> => protectedApiClient.post<Resume>(`/resumes/${resumeId}/sns-platforms`, payload);
