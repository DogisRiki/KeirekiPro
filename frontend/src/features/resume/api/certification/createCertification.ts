import type { Resume } from "@/features/resume";
import { protectedApiClient } from "@/lib";
import type { AxiosResponse } from "axios";

/**
 * 資格新規作成ペイロード
 */
export interface CreateCertificationPayload {
    name: string;
    date: string; // yyyy-MM
}

/**
 * 職務経歴書 資格新規作成API
 * @param resumeId 職務経歴書ID
 * @param payload 資格新規作成リクエスト
 * @returns 更新された職務経歴書情報を含むAxiosレスポンス
 */
export const createCertification = (
    resumeId: string,
    payload: CreateCertificationPayload,
): Promise<AxiosResponse<Resume>> => protectedApiClient.post<Resume>(`/resumes/${resumeId}/certifications`, payload);
