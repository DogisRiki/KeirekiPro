import { protectedApiClient } from "@/lib";

/**
 * 職務経歴書サマリ
 */
export interface ResumeSummary {
    id: string;
    resumeName: string;
    createdAt: string;
    updatedAt: string;
}

/**
 * 職務経歴書一覧レスポンス
 */
export interface GetResumeListResponse {
    resumes: ResumeSummary[];
}

/**
 * 職務経歴書一覧取得API
 * @returns 職務経歴書一覧レスポンス
 */
export const getResumeList = async (): Promise<GetResumeListResponse> => {
    const response = await protectedApiClient.get<GetResumeListResponse>("/resumes");
    return response.data;
};
