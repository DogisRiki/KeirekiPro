import type { Resume } from "@/features/resume";
import { protectedApiClient } from "@/lib";
import type { AxiosResponse } from "axios";

/**
 * ポートフォリオ更新用ペイロード
 */
export interface UpdatePortfoliosPayload {
    portfolios: {
        id?: string | null;
        name: string;
        overview: string;
        techStack?: string;
        link: string;
    }[];
}

/**
 * 職務経歴書ポートフォリオ更新API
 * @param resumeId 職務経歴書ID
 * @param payload ポートフォリオ更新リクエスト
 * @returns 更新後の職務経歴書情報を含むAxiosレスポンス
 */
export const updatePortfolios = (resumeId: string, payload: UpdatePortfoliosPayload): Promise<AxiosResponse<Resume>> =>
    protectedApiClient.put<Resume>(`/resumes/${resumeId}/portfolios`, payload);
