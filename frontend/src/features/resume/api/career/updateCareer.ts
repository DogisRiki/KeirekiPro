import type { Resume } from "@/features/resume";
import { protectedApiClient } from "@/lib";
import type { AxiosResponse } from "axios";

/**
 * 職歴更新ペイロード
 */
export interface UpdateCareerPayload {
    companyName: string;
    startDate: string; // yyyy-MM
    endDate: string | null; // yyyy-MM
    isActive: boolean;
}

/**
 * 職務経歴書 職歴更新API
 * @param resumeId 職務経歴書ID
 * @param careerId 職歴ID
 * @param payload 職歴更新リクエスト
 * @returns 更新された職務経歴書情報を含むAxiosレスポンス
 */
export const updateCareer = (
    resumeId: string,
    careerId: string,
    payload: UpdateCareerPayload,
): Promise<AxiosResponse<Resume>> =>
    protectedApiClient.put<Resume>(`/resumes/${resumeId}/careers/${careerId}`, payload);
