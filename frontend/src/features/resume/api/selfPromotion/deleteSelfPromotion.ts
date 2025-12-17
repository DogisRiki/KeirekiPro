import { protectedApiClient } from "@/lib";
import type { AxiosResponse } from "axios";

/**
 * 職務経歴書 自己PR削除API
 * @param resumeId 職務経歴書ID
 * @param selfPromotionId 自己PRID
 * @returns AxiosResponse（204 No Content）
 */
export const deleteSelfPromotion = (resumeId: string, selfPromotionId: string): Promise<AxiosResponse<void>> =>
    protectedApiClient.delete<void>(`/resumes/${resumeId}/self-promotions/${selfPromotionId}`);
