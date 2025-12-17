import type { Resume, UpdateProjectPayload } from "@/features/resume";
import { updateProject, useResumeStore } from "@/features/resume";
import { useErrorMessageStore, useNotificationStore } from "@/stores";
import { useMutation } from "@tanstack/react-query";
import type { AxiosError, AxiosResponse } from "axios";

/**
 * プロジェクト更新フック
 * @param resumeId 職務経歴書ID
 * @returns プロジェクト更新ミューテーション
 */
export const useUpdateProject = (resumeId: string) => {
    const { clearErrors } = useErrorMessageStore();
    const { setNotification } = useNotificationStore();

    return useMutation<AxiosResponse<Resume>, AxiosError, { projectId: string; payload: UpdateProjectPayload }>({
        mutationFn: ({ projectId, payload }) => updateProject(resumeId, projectId, payload),
        onMutate: () => {
            clearErrors();
        },
        onSuccess: (response, { projectId }) => {
            clearErrors();
            const { projects: serverProjects, updatedAt } = response.data;
            const { resume, dirtyEntryIds, updateResumeFromServer, setDirty, removeDirtyEntryId } =
                useResumeStore.getState();

            if (!resume) return;

            // ローカルのdirtyエントリーをマップ化（保存したID以外）
            const localDirtyMap = new Map(
                resume.projects.filter((p) => p.id !== projectId && dirtyEntryIds.has(p.id)).map((p) => [p.id, p]),
            );

            // ローカルにのみ存在する一時IDエントリー
            const serverIds = new Set(serverProjects.map((p) => p.id));
            const localOnlyEntries = resume.projects.filter((p) => !serverIds.has(p.id));

            // APIレスポンスをベースに、dirtyなエントリーはローカルデータで上書き
            const mergedProjects = serverProjects.map((serverEntry) => {
                const localDirty = localDirtyMap.get(serverEntry.id);
                return localDirty ?? serverEntry;
            });

            // ローカルにのみ存在するエントリーを先頭に追加
            const finalProjects = [...localOnlyEntries, ...mergedProjects];

            updateResumeFromServer({ projects: finalProjects, updatedAt });
            removeDirtyEntryId(projectId);
            setDirty(false);
            setNotification("プロジェクトを更新しました。", "success");
        },
    });
};
