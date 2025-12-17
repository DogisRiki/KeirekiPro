import { protectedApiClient } from "@/lib";
import type { AxiosResponse } from "axios";

/**
 * 職務経歴書 プロジェクト削除API
 * @param resumeId 職務経歴書ID
 * @param projectId プロジェクトID
 * @returns AxiosResponse（204 No Content）
 */
export const deleteProject = (resumeId: string, projectId: string): Promise<AxiosResponse<void>> =>
    protectedApiClient.delete<void>(`/resumes/${resumeId}/projects/${projectId}`);
