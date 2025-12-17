import type { Resume } from "@/features/resume";
import { protectedApiClient } from "@/lib";
import type { AxiosResponse } from "axios";

/**
 * 職歴新規作成ペイロード
 */
export interface CreateCareerPayload {
    companyName: string;
    startDate: string; // yyyy-MM
    endDate: string | null; // yyyy-MM
    isActive: boolean;
}

/**
 * 職務経歴書 職歴新規作成API
 * @param resumeId 職務経歴書ID
 * @param payload 職歴新規作成リクエスト
 * @returns 更新された職務経歴書情報を含むAxiosレスポンス
 */
export const createCareer = (resumeId: string, payload: CreateCareerPayload): Promise<AxiosResponse<Resume>> =>
    protectedApiClient.post<Resume>(`/resumes/${resumeId}/careers`, payload);
