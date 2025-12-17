import type { Resume } from "@/features/resume";
import { protectedApiClient } from "@/lib";
import type { AxiosResponse } from "axios";

/**
 * ポートフォリオ新規作成ペイロード
 */
export interface CreatePortfolioPayload {
    name: string;
    overview: string;
    techStack?: string;
    link: string;
}

/**
 * 職務経歴書 ポートフォリオ新規作成API
 * @param resumeId 職務経歴書ID
 * @param payload ポートフォリオ新規作成リクエスト
 * @returns 更新された職務経歴書情報を含むAxiosレスポンス
 */
export const createPortfolio = (resumeId: string, payload: CreatePortfolioPayload): Promise<AxiosResponse<Resume>> =>
    protectedApiClient.post<Resume>(`/resumes/${resumeId}/portfolios`, payload);
