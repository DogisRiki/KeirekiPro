import { deleteProject, useResumeStore } from "@/features/resume";
import { useErrorMessageStore, useNotificationStore } from "@/stores";
import { useMutation } from "@tanstack/react-query";
import type { AxiosError, AxiosResponse } from "axios";

/**
 * プロジェクト削除フック
 * @param resumeId 職務経歴書ID
 * @returns プロジェクト削除ミューテーション
 */
export const useDeleteProject = (resumeId: string) => {
    const { clearErrors } = useErrorMessageStore();
    const { setNotification } = useNotificationStore();
    const { resume, updateResume, setDirty, removeDirtyEntryId, setActiveEntryId } = useResumeStore();

    return useMutation<AxiosResponse<void>, AxiosError, string>({
        mutationFn: (projectId) => deleteProject(resumeId, projectId),
        onMutate: () => {
            // リクエスト開始時にエラーをクリア
            clearErrors();
        },
        onSuccess: (_, projectId) => {
            // エラーをクリア
            clearErrors();
            // ローカルストアから削除したエントリーを除外
            if (resume) {
                const updatedProjects = resume.projects.filter((p) => p.id !== projectId);
                updateResume({ projects: updatedProjects });
            }
            // 後処理: dirty状態のリセットと通知
            removeDirtyEntryId(projectId);
            setActiveEntryId(null);
            setDirty(false);
            setNotification("プロジェクトを削除しました。", "success");
        },
    });
};
