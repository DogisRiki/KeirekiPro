import { protectedApiClient } from "@/lib";
import type { AxiosResponse } from "axios";

/**
 * エクスポート形式
 */
export type ExportFormat = "pdf" | "markdown";

/**
 * 職務経歴書エクスポートAPI
 * @param resumeId 職務経歴書ID
 * @param format エクスポート形式
 * @returns ファイルのBlobデータを含むAxiosレスポンス
 */
export const exportResume = async (resumeId: string, format: ExportFormat): Promise<AxiosResponse<Blob>> => {
    const acceptHeader = format === "pdf" ? "application/pdf, application/json" : "text/markdown, application/json";

    return await protectedApiClient.get<Blob>(`/resumes/${resumeId}/export`, {
        headers: {
            Accept: acceptHeader,
        },
        responseType: "blob",
    });
};
