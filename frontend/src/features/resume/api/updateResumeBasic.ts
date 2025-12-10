import type { Resume } from "@/features/resume";
import { protectedApiClient } from "@/lib";
import type { AxiosResponse } from "axios";

/**
 * 職務経歴書 基本情報更新用ペイロード
 */
export interface UpdateResumeBasicPayload {
    resumeName: string;
    date: string; // yyyy-MM-dd
    lastName: string;
    firstName: string;
}

/**
 * 職務経歴書 基本情報更新API
 * @param resumeId 職務経歴書ID（URLパスで指定）
 * @param payload  基本情報更新リクエスト
 * @returns 更新後の職務経歴書情報を含むAxiosレスポンス
 */
export const updateResumeBasic = (
    resumeId: string,
    payload: UpdateResumeBasicPayload,
): Promise<AxiosResponse<Resume>> => {
    return protectedApiClient.put<Resume>(`/resumes/${resumeId}/basic`, payload);
};
