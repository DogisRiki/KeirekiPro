import type { Resume } from "@/features/resume";
import { protectedApiClient } from "@/lib";
import type { AxiosResponse } from "axios";

/**
 * 職務経歴書リストアAPI
 * @param file JSONファイル
 * @returns 作成された職務経歴書情報を含むAxiosレスポンス
 */
export const restoreResume = async (file: File): Promise<AxiosResponse<Resume>> => {
    const content = await file.text();
    const jsonData = JSON.parse(content);

    return await protectedApiClient.post<Resume>("/resumes/restore", jsonData);
};
