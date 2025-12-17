import { protectedApiClient } from "@/lib";
import type { AxiosResponse } from "axios";

/**
 * 職務経歴書 ポートフォリオ削除API
 * @param resumeId 職務経歴書ID
 * @param portfolioId ポートフォリオID
 * @returns AxiosResponse（204 No Content）
 */
export const deletePortfolio = (resumeId: string, portfolioId: string): Promise<AxiosResponse<void>> =>
    protectedApiClient.delete<void>(`/resumes/${resumeId}/portfolios/${portfolioId}`);
