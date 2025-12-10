import type { Resume } from "@/features/resume";
import { protectedApiClient } from "@/lib";

/**
 * 職務経歴書情報取得API
 * @param resumeId 職務経歴書ID
 * @returns 職務経歴書情報
 */
export const getResumeInfo = async (resumeId: string): Promise<Resume> => {
    const response = await protectedApiClient.get<Resume>(`/resumes/${resumeId}`);
    return response.data;
};
