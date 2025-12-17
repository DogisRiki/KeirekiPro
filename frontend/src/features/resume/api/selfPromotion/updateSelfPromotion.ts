import type { Resume } from "@/features/resume";
import { protectedApiClient } from "@/lib";
import type { AxiosResponse } from "axios";

/**
 * 自己PR更新ペイロード
 */
export interface UpdateSelfPromotionPayload {
    title: string;
    content: string;
}

/**
 * 職務経歴書 自己PR更新API
 * @param resumeId 職務経歴書ID
 * @param selfPromotionId 自己PRID
 * @param payload 自己PR更新リクエスト
 * @returns 更新された職務経歴書情報を含むAxiosレスポンス
 */
export const updateSelfPromotion = (
    resumeId: string,
    selfPromotionId: string,
    payload: UpdateSelfPromotionPayload,
): Promise<AxiosResponse<Resume>> =>
    protectedApiClient.put<Resume>(`/resumes/${resumeId}/self-promotions/${selfPromotionId}`, payload);
