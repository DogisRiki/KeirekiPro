import { protectedApiClient } from "@/lib";

/**
 * SNSプラットフォーム一覧レスポンス
 */
export interface SnsPlatformListResponse {
    names: string[];
}

/**
 * SNSプラットフォーム一覧取得API
 * @returns SNSプラットフォーム一覧レスポンス
 */
export const getSnsPlatformList = async (): Promise<SnsPlatformListResponse> => {
    const response = await protectedApiClient.get<SnsPlatformListResponse>("/sns-platforms");
    return response.data;
};
