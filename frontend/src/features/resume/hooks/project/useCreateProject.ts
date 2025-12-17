import type { CreateProjectPayload, Resume } from "@/features/resume";
import { createProject, useResumeStore } from "@/features/resume";
import { useNotificationStore } from "@/stores";
import type { ErrorResponse } from "@/types";
import { useMutation } from "@tanstack/react-query";
import type { AxiosError, AxiosResponse } from "axios";

/**
 * プロジェクト新規作成フック
 * @param resumeId 職務経歴書ID
 * @returns プロジェクト新規作成ミューテーション
 */
export const useCreateProject = (resumeId: string) => {
    const { setNotification } = useNotificationStore();

    return useMutation<
        AxiosResponse<Resume>,
        AxiosError<ErrorResponse>,
        { tempId: string; payload: CreateProjectPayload }
    >({
        mutationFn: ({ payload }) => createProject(resumeId, payload),
        onMutate: ({ tempId }) => {
            // リクエスト開始時にエラーをクリア
            useResumeStore.getState().clearEntryErrors(tempId);
        },
        onSuccess: (response, { tempId }) => {
            const { projects: serverProjects, updatedAt } = response.data;
            const {
                resume,
                dirtyEntryIds,
                updateResumeFromServer,
                setDirty,
                removeDirtyEntryId,
                setActiveEntryId,
                clearEntryErrors,
            } = useResumeStore.getState();

            // 保存完了したエントリーのエラーをクリア
            clearEntryErrors(tempId);

            if (!resume) return;

            // 保存した一時ID以外で、編集中のエントリーをマップ化
            const localDirtyMap = new Map(
                resume.projects.filter((p) => p.id !== tempId && dirtyEntryIds.has(p.id)).map((p) => [p.id, p]),
            );

            // サーバーに存在しないローカル専用エントリー（未保存の新規エントリー）を抽出
            const serverIds = new Set(serverProjects.map((p) => p.id));
            const localOnlyEntries = resume.projects.filter((p) => p.id !== tempId && !serverIds.has(p.id));

            // サーバーデータをベースに、編集中のエントリーはローカルデータで上書き
            const mergedProjects = serverProjects.map((serverEntry) => {
                const localDirty = localDirtyMap.get(serverEntry.id);
                return localDirty ?? serverEntry;
            });

            // ローカル専用エントリーを先頭に追加してマージ完了
            const finalProjects = [...localOnlyEntries, ...mergedProjects];

            // サーバーから返された新規エントリーを特定
            const createdProject = serverProjects.find(
                (sp) => !resume.projects.some((lp) => lp.id === sp.id && lp.id !== tempId),
            );

            // ストアを更新
            updateResumeFromServer({ projects: finalProjects, updatedAt });

            // 新規作成されたエントリーをアクティブに設定
            if (createdProject) {
                setActiveEntryId(createdProject.id);
            }

            // 後処理: dirty状態のリセットと通知
            removeDirtyEntryId(tempId);
            setDirty(false);
            setNotification("プロジェクトを作成しました。", "success");
        },
        onError: (error, { tempId }) => {
            // バリデーションエラーをストアに保存
            const errorData = error.response?.data;
            if (errorData?.errors) {
                useResumeStore.getState().setEntryErrors(tempId, errorData.errors);
            }
        },
    });
};
