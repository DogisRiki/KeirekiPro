import type { ExportFormat, ResumeNotFoundHandler } from "@/features/resume";
import { exportResume, isResumeNotFoundError } from "@/features/resume";
import { useErrorMessageStore } from "@/stores";
import type { ErrorResponse } from "@/types";
import { extractFileName } from "@/utils";
import { useMutation, useQueryClient } from "@tanstack/react-query";
import type { AxiosError, AxiosResponse } from "axios";
import { saveAs } from "file-saver";

/**
 * 職務経歴書エクスポートフック
 * @returns 職務経歴書エクスポートミューテーション
 */
export const useExportResume = (options?: { onResumeNotFound?: ResumeNotFoundHandler }) => {
    const { clearErrors } = useErrorMessageStore();
    const queryClient = useQueryClient();

    return useMutation<AxiosResponse<Blob>, AxiosError<ErrorResponse>, { resumeId: string; format: ExportFormat }>({
        mutationFn: ({ resumeId, format }) => exportResume(resumeId, format),
        onSuccess: (response, { format }) => {
            clearErrors();
            const contentType = format === "pdf" ? "application/pdf" : "text/markdown";
            const defaultFileName = format === "pdf" ? "resume.pdf" : "resume.md";
            const fileName = extractFileName(response.headers["content-disposition"]) ?? defaultFileName;
            const blob = new Blob([response.data], { type: contentType });
            saveAs(blob, fileName);
        },
        onError: async (error) => {
            if (!isResumeNotFoundError(error)) {
                return;
            }

            const errorData = error.response?.data;
            if (errorData) {
                await queryClient.refetchQueries({ queryKey: ["getResumeList"], type: "active" });
                await options?.onResumeNotFound?.(errorData);
            }
        },
    });
};
