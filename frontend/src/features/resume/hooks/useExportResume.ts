import type { ExportFormat } from "@/features/resume";
import { exportResume } from "@/features/resume";
import { useErrorMessageStore } from "@/stores";
import { extractFileName } from "@/utils";
import { useMutation } from "@tanstack/react-query";
import type { AxiosError, AxiosResponse } from "axios";
import { saveAs } from "file-saver";

/**
 * 職務経歴書エクスポートフック
 * @returns 職務経歴書エクスポートミューテーション
 */
export const useExportResume = () => {
    const { clearErrors } = useErrorMessageStore();

    return useMutation<AxiosResponse<Blob>, AxiosError, { resumeId: string; format: ExportFormat }>({
        mutationFn: ({ resumeId, format }) => exportResume(resumeId, format),
        onSuccess: (response, { format }) => {
            clearErrors();
            const contentType = format === "pdf" ? "application/pdf" : "text/markdown";
            const defaultFileName = format === "pdf" ? "resume.pdf" : "resume.md";
            const fileName = extractFileName(response.headers["content-disposition"]) ?? defaultFileName;
            const blob = new Blob([response.data], { type: contentType });
            saveAs(blob, fileName);
        },
    });
};
