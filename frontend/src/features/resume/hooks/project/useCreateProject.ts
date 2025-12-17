import type { CreateProjectPayload, Resume } from "@/features/resume";
import { createProject, useResumeStore } from "@/features/resume";
import { useErrorMessageStore, useNotificationStore } from "@/stores";
import { useMutation } from "@tanstack/react-query";
import type { AxiosError, AxiosResponse } from "axios";

/**
 * プロジェクト新規作成フック
 * @param resumeId 職務経歴書ID
 * @returns プロジェクト新規作成ミューテーション
 */
export const useCreateProject = (resumeId: string) => {
    const { clearErrors } = useErrorMessageStore();
    const { setNotification } = useNotificationStore();

    return useMutation<AxiosResponse<Resume>, AxiosError, { tempId: string; payload: CreateProjectPayload }>({
        mutationFn: ({ payload }) => createProject(resumeId, payload),
        onMutate: () => {
            clearErrors();
        },
        onSuccess: (response, { tempId }) => {
            clearErrors();
            const { projects: serverProjects, updatedAt } = response.data;
            const { resume, dirtyEntryIds, updateResumeFromServer, setDirty, removeDirtyEntryId, setActiveEntryId } =
                useResumeStore.getState();

            if (!resume) return;

            // ローカルのdirtyエントリーをマップ化（保存した一時ID以外）
            const localDirtyMap = new Map(
                resume.projects.filter((p) => p.id !== tempId && dirtyEntryIds.has(p.id)).map((p) => [p.id, p]),
            );

            // ローカルにのみ存在する一時IDエントリー（保存した一時ID以外）
            const serverIds = new Set(serverProjects.map((p) => p.id));
            const localOnlyEntries = resume.projects.filter((p) => p.id !== tempId && !serverIds.has(p.id));

            // APIレスポンスをベースに、dirtyなエントリーはローカルデータで上書き
            const mergedProjects = serverProjects.map((serverEntry) => {
                const localDirty = localDirtyMap.get(serverEntry.id);
                return localDirty ?? serverEntry;
            });

            // ローカルにのみ存在するエントリーを先頭に追加
            const finalProjects = [...localOnlyEntries, ...mergedProjects];

            // 新しく作成されたエントリーのIDを特定
            const createdProject = serverProjects.find(
                (sp) => !resume.projects.some((lp) => lp.id === sp.id && lp.id !== tempId),
            );

            updateResumeFromServer({ projects: finalProjects, updatedAt });

            if (createdProject) {
                setActiveEntryId(createdProject.id);
            }

            removeDirtyEntryId(tempId);
            setDirty(false);
            setNotification("プロジェクトを作成しました。", "success");
        },
    });
};
