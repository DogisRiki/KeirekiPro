import { protectedApiClient } from "@/lib";
import type { AxiosResponse } from "axios";

/**
 * 職務経歴書バックアップAPI
 * @param resumeId 職務経歴書ID
 * @returns JSONファイルのBlobデータを含むAxiosレスポンス
 */
export const backupResume = async (resumeId: string): Promise<AxiosResponse<Blob>> => {
    return await protectedApiClient.get<Blob>(`/resumes/${resumeId}/backup`, {
        headers: {
            Accept: "application/json",
        },
        responseType: "blob",
    });
};
