import {
    deleteProject,
    isResumeNotFoundError,
    isSectionNotFoundError,
    syncResumeInfoFromServer,
    useResumeStore,
    type ResumeNotFoundHandler,
} from "@/features/resume";
import { useErrorMessageStore, useNotificationStore } from "@/stores";
import type { ErrorResponse } from "@/types";
import { useMutation } from "@tanstack/react-query";
import type { AxiosError, AxiosResponse } from "axios";

/**
 * プロジェクト削除フック
 * @param resumeId 職務経歴書ID
 * @returns プロジェクト削除ミューテーション
 */
export const useDeleteProject = (resumeId: string, options?: { onResumeNotFound?: ResumeNotFoundHandler }) => {
    const { clearErrors } = useErrorMessageStore();
    const { setNotification } = useNotificationStore();
    const { removeEntry, setActiveEntryId } = useResumeStore();

    return useMutation<AxiosResponse<void>, AxiosError<ErrorResponse>, string>({
        mutationFn: (projectId) => deleteProject(resumeId, projectId),
        onMutate: () => {
            // リクエスト開始時にエラーをクリア
            clearErrors();
        },
        onSuccess: (_, projectId) => {
            // エラーをクリア
            clearErrors();
            // ローカルストアから削除したエントリーを除外（未保存の印とエラーも外す）
            removeEntry("projects", projectId);
            // 削除したエントリーを選択中だったときだけ選択を解除する
            if (useResumeStore.getState().activeEntryId === projectId) {
                setActiveEntryId(null);
            }
            setNotification("プロジェクトを削除しました。", "success");
        },
        onError: async (error) => {
            if (isResumeNotFoundError(error)) {
                options?.onResumeNotFound?.();
                return;
            }
            if (isSectionNotFoundError(error)) {
                await syncResumeInfoFromServer(resumeId);
            }
        },
    });
};
