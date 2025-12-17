import type { Resume } from "@/features/resume";
import { protectedApiClient } from "@/lib";
import type { AxiosResponse } from "axios";

/**
 * 自己PR新規作成ペイロード
 */
export interface CreateSelfPromotionPayload {
    title: string;
    content: string;
}

/**
 * 職務経歴書 自己PR新規作成API
 * @param resumeId 職務経歴書ID
 * @param payload 自己PR新規作成リクエスト
 * @returns 更新された職務経歴書情報を含むAxiosレスポンス
 */
export const createSelfPromotion = (
    resumeId: string,
    payload: CreateSelfPromotionPayload,
): Promise<AxiosResponse<Resume>> => protectedApiClient.post<Resume>(`/resumes/${resumeId}/self-promotions`, payload);
