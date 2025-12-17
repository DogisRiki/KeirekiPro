import { protectedApiClient } from "@/lib";
import type { AxiosResponse } from "axios";

/**
 * 職務経歴書 SNS削除API
 * @param resumeId 職務経歴書ID
 * @param socialLinkId SNSID
 * @returns AxiosResponse（204 No Content）
 */
export const deleteSocialLink = (resumeId: string, socialLinkId: string): Promise<AxiosResponse<void>> =>
    protectedApiClient.delete<void>(`/resumes/${resumeId}/social-links/${socialLinkId}`);
