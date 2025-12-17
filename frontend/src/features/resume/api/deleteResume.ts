import { protectedApiClient } from "@/lib";
import type { AxiosResponse } from "axios";

/**
 * 職務経歴書削除API
 * @param resumeId 職務経歴書ID
 * @returns AxiosResponse（204 No Content）
 */
export const deleteResume = (resumeId: string): Promise<AxiosResponse<void>> =>
    protectedApiClient.delete<void>(`/resumes/${resumeId}`);
