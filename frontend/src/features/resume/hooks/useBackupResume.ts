import { backupResume } from "@/features/resume";
import { useErrorMessageStore } from "@/stores";
import { extractFileName } from "@/utils";
import { useMutation } from "@tanstack/react-query";
import type { AxiosError, AxiosResponse } from "axios";
import { saveAs } from "file-saver";

/**
 * 職務経歴書バックアップフック
 * @returns 職務経歴書バックアップミューテーション
 */
export const useBackupResume = () => {
    const { clearErrors } = useErrorMessageStore();

    return useMutation<AxiosResponse<Blob>, AxiosError, string>({
        mutationFn: (resumeId) => backupResume(resumeId),
        onSuccess: (response) => {
            clearErrors();
            const defaultFileName = "resume_backup.json";
            const fileName = extractFileName(response.headers["content-disposition"]) ?? defaultFileName;
            const blob = new Blob([response.data], { type: "application/json" });
            saveAs(blob, fileName);
        },
    });
};
