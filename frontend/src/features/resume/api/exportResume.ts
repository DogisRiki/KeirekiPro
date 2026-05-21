import { protectedApiClient } from "@/lib";
import type { AxiosResponse } from "axios";

/**
 * エクスポート形式
 */
export type ExportFormat = "pdf" | "markdown";

/**
 * PDF出力方法
 */
export type PdfExportDisposition = "inline" | "attachment";

/**
 * PDFフォント種類
 */
export type PdfFontFamily = "NotoSansJP" | "NotoSerifJP";

/**
 * PDF設定
 */
export interface ResumePdfSettings {
    fontFamily: PdfFontFamily;
    fontSizes: {
        title: number;
        date: number;
        fullName: number;
        sectionHeading: number;
    };
    tableHeaderColor: {
        hex?: string;
        rgb?: {
            r: number;
            g: number;
            b: number;
        };
    };
}

/**
 * PDFエクスポートリクエスト
 */
export interface ExportResumePdfPayload {
    format: "pdf";
    disposition: PdfExportDisposition;
    pdfSettings: ResumePdfSettings;
}

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

/**
 * 職務経歴書PDFエクスポートAPI
 * @param resumeId 職務経歴書ID
 * @param payload PDFエクスポートリクエスト
 * @param signal キャンセルシグナル
 * @returns PDF Blobデータを含むAxiosレスポンス
 */
export const exportResumePdf = async (
    resumeId: string,
    payload: ExportResumePdfPayload,
    signal?: AbortSignal,
): Promise<AxiosResponse<Blob>> =>
    await protectedApiClient.post<Blob>(`/resumes/${resumeId}/export`, payload, {
        headers: {
            Accept: "application/pdf, application/json",
        },
        responseType: "blob",
        signal,
    });
