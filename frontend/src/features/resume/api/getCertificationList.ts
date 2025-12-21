import { protectedApiClient } from "@/lib";

/**
 * 資格一覧レスポンス
 */
export interface CertificationListResponse {
    names: string[];
}

/**
 * 資格一覧取得API
 * @returns 資格一覧レスポンス
 */
export const getCertificationList = async (): Promise<CertificationListResponse> => {
    const response = await protectedApiClient.get<CertificationListResponse>("/certifications");
    return response.data;
};
