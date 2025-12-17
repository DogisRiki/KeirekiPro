import type { Resume } from "@/features/resume";
import { protectedApiClient } from "@/lib";
import type { AxiosResponse } from "axios";

/**
 * 資格更新ペイロード
 */
export interface UpdateCertificationPayload {
    name: string;
    date: string; // yyyy-MM
}

/**
 * 職務経歴書 資格更新API
 * @param resumeId 職務経歴書ID
 * @param certificationId 資格ID
 * @param payload 資格更新リクエスト
 * @returns 更新された職務経歴書情報を含むAxiosレスポンス
 */
export const updateCertification = (
    resumeId: string,
    certificationId: string,
    payload: UpdateCertificationPayload,
): Promise<AxiosResponse<Resume>> =>
    protectedApiClient.put<Resume>(`/resumes/${resumeId}/certifications/${certificationId}`, payload);
