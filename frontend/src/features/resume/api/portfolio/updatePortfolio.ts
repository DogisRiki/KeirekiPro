import type { Resume } from "@/features/resume";
import { protectedApiClient } from "@/lib";
import type { AxiosResponse } from "axios";

/**
 * ポートフォリオ更新ペイロード
 */
export interface UpdatePortfolioPayload {
    name: string;
    overview: string;
    techStack?: string;
    link: string;
}

/**
 * 職務経歴書 ポートフォリオ更新API
 * @param resumeId 職務経歴書ID
 * @param portfolioId ポートフォリオID
 * @param payload ポートフォリオ更新リクエスト
 * @returns 更新された職務経歴書情報を含むAxiosレスポンス
 */
export const updatePortfolio = (
    resumeId: string,
    portfolioId: string,
    payload: UpdatePortfolioPayload,
): Promise<AxiosResponse<Resume>> =>
    protectedApiClient.put<Resume>(`/resumes/${resumeId}/portfolios/${portfolioId}`, payload);
