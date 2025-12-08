import type { Resume } from "@/features/resume";
import { protectedApiClient } from "@/lib";
import type { AxiosResponse } from "axios";

/**
 * 職務経歴書新規作成用ペイロード
 */
export interface CreateResumePayload {
    resumeName: string;
    resumeId?: string | null; // コピー元職務経歴書ID(未指定の場合は空の職務経歴書として作成する)
}

/**
 * 職務経歴書新規作成API
 * @param payload 職務経歴書新規作成リクエスト
 * @returns 作成された職務経歴書情報を含むAxiosレスポンス
 */
export const createResume = (payload: CreateResumePayload): Promise<AxiosResponse<Resume>> =>
    protectedApiClient.post<Resume>("/resumes", payload);
