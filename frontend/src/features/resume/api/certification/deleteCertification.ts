import { protectedApiClient } from "@/lib";
import type { AxiosResponse } from "axios";

/**
 * 職務経歴書 資格削除API
 * @param resumeId 職務経歴書ID
 * @param certificationId 資格ID
 * @returns AxiosResponse（204 No Content）
 */
export const deleteCertification = (resumeId: string, certificationId: string): Promise<AxiosResponse<void>> =>
    protectedApiClient.delete<void>(`/resumes/${resumeId}/certifications/${certificationId}`);
