import type { Resume, UpdateProjectPayload } from "@/features/resume";
import { updateProject, useResumeStore } from "@/features/resume";
import { useNotificationStore } from "@/stores";
import type { ErrorResponse } from "@/types";
import { useMutation } from "@tanstack/react-query";
import type { AxiosError, AxiosResponse } from "axios";

/**
 * プロジェクト更新フック
 * @param resumeId 職務経歴書ID
 * @returns プロジェクト更新ミューテーション
 */
export const useUpdateProject = (resumeId: string) => {
    const { setNotification } = useNotificationStore();

    return useMutation<
        AxiosResponse<Resume>,
        AxiosError<ErrorResponse>,
        { projectId: string; payload: UpdateProjectPayload }
    >({
        mutationFn: ({ projectId, payload }) => updateProject(resumeId, projectId, payload),
        onMutate: ({ projectId }) => {
            // リクエスト開始時にエラーをクリア
            useResumeStore.getState().clearEntryErrors(projectId);
        },
        onSuccess: (response, { projectId }) => {
            const { projects: serverProjects, updatedAt } = response.data;
            const { resume, dirtyEntryIds, updateResumeFromServer, setDirty, removeDirtyEntryId, clearEntryErrors } =
                useResumeStore.getState();

            // 保存完了したエントリーのエラーをクリア
            clearEntryErrors(projectId);

            if (!resume) return;

            // 保存したID以外で、編集中のエントリーをマップ化
            const localDirtyMap = new Map(
                resume.projects.filter((p) => p.id !== projectId && dirtyEntryIds.has(p.id)).map((p) => [p.id, p]),
            );

            // サーバーに存在しないローカル専用エントリー（未保存の新規エントリー）を抽出
            const serverIds = new Set(serverProjects.map((p) => p.id));
            const localOnlyEntries = resume.projects.filter((p) => !serverIds.has(p.id));

            // サーバーデータをベースに、編集中のエントリーはローカルデータで上書き
            const mergedProjects = serverProjects.map((serverEntry) => {
                const localDirty = localDirtyMap.get(serverEntry.id);
                return localDirty ?? serverEntry;
            });

            // ローカル専用エントリーを先頭に追加してマージ完了
            const finalProjects = [...localOnlyEntries, ...mergedProjects];

            // ストアを更新
            updateResumeFromServer({ projects: finalProjects, updatedAt });

            // 後処理: dirty状態のリセットと通知
            removeDirtyEntryId(projectId);
            setDirty(false);
            setNotification("プロジェクトを更新しました。", "success");
        },
        onError: (error, { projectId }) => {
            // バリデーションエラーをストアに保存
            const errorData = error.response?.data;
            if (errorData?.errors) {
                useResumeStore.getState().setEntryErrors(projectId, errorData.errors);
            }
        },
    });
};
