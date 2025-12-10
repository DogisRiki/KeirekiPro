import type { Resume } from "@/features/resume";
import { protectedApiClient } from "@/lib";
import type { AxiosResponse } from "axios";

/**
 * 資格更新用ペイロード
 */
export interface UpdateCertificationsPayload {
    certifications: {
        id?: string | null;
        name: string;
        date: string; // yyyy-MM
    }[];
}

/**
 * 職務経歴書資格更新API
 * @param resumeId 職務経歴書ID
 * @param payload 資格更新リクエスト
 * @returns 更新後の職務経歴書情報を含むAxiosレスポンス
 */
export const updateCertifications = (
    resumeId: string,
    payload: UpdateCertificationsPayload,
): Promise<AxiosResponse<Resume>> => protectedApiClient.put<Resume>(`/resumes/${resumeId}/certifications`, payload);
