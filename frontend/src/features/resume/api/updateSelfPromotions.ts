import type { Resume } from "@/features/resume";
import { protectedApiClient } from "@/lib";
import type { AxiosResponse } from "axios";

/**
 * 自己PR更新用ペイロード
 */
export interface UpdateSelfPromotionsPayload {
    selfPromotions: {
        id?: string | null;
        title: string;
        content: string;
    }[];
}

/**
 * 職務経歴書自己PR更新API
 * @param resumeId 職務経歴書ID
 * @param payload 自己PR更新リクエスト
 * @returns 更新後の職務経歴書情報を含むAxiosレスポンス
 */
export const updateSelfPromotions = (
    resumeId: string,
    payload: UpdateSelfPromotionsPayload,
): Promise<AxiosResponse<Resume>> => protectedApiClient.put<Resume>(`/resumes/${resumeId}/self-promotions`, payload);
