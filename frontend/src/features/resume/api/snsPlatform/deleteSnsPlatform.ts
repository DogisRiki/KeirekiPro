import { protectedApiClient } from "@/lib";
import type { AxiosResponse } from "axios";

/**
 * 職務経歴書 SNSプラットフォーム削除API
 * @param resumeId 職務経歴書ID
 * @param snsPlatformId SNSプラットフォームID
 * @returns AxiosResponse（204 No Content）
 */
export const deleteSnsPlatform = (resumeId: string, snsPlatformId: string): Promise<AxiosResponse<void>> =>
    protectedApiClient.delete<void>(`/resumes/${resumeId}/sns-platforms/${snsPlatformId}`);
