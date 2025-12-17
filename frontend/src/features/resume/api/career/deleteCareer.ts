import { protectedApiClient } from "@/lib";
import type { AxiosResponse } from "axios";

/**
 * 職務経歴書 職歴削除API
 * @param resumeId 職務経歴書ID
 * @param careerId 職歴ID
 * @returns AxiosResponse（204 No Content）
 */
export const deleteCareer = (resumeId: string, careerId: string): Promise<AxiosResponse<void>> =>
    protectedApiClient.delete<void>(`/resumes/${resumeId}/careers/${careerId}`);
