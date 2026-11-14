import {
    createProject,
    isResumeNotFoundError,
    useResumeStore,
    type CreateProjectPayload,
    type Resume,
    type ResumeNotFoundHandler,
} from "@/features/resume";
import { useNotificationStore } from "@/stores";
import type { ErrorResponse } from "@/types";
import { useMutation } from "@tanstack/react-query";
import type { AxiosError, AxiosResponse } from "axios";

/**
 * プロジェクト新規作成フック
 * @param resumeId 職務経歴書ID
 * @returns プロジェクト新規作成ミューテーション
 */
export const useCreateProject = (resumeId: string, options?: { onResumeNotFound?: ResumeNotFoundHandler }) => {
    const { setNotification } = useNotificationStore();

    return useMutation<
        AxiosResponse<Resume>,
        AxiosError<ErrorResponse>,
        { tempId: string; payload: CreateProjectPayload },
        { snapshot?: Resume["projects"][number] }
    >({
        mutationFn: ({ payload }) => createProject(resumeId, payload),
        onMutate: ({ tempId }) => {
            // リクエスト開始時にエラーをクリア
            useResumeStore.getState().clearEntryErrors(tempId);
            // 保存を始めたときのエントリーを控える(保存中に打った文字を見分けるため)
            return { snapshot: useResumeStore.getState().resume?.projects.find((e) => e.id === tempId) };
        },
        onSuccess: (response, { tempId }, onMutateResult) => {
            const { projects: serverProjects, updatedAt } = response.data;
            const {
                resume,
                dirtyEntryIds,
                updateResumeFromServer,
                addDirtyEntryId,
                removeDirtyEntryId,
                setActiveEntryId,
                clearEntryErrors,
            } = useResumeStore.getState();

            // 保存完了したエントリーのエラーをクリア
            clearEntryErrors(tempId);

            if (!resume) return;

            // 保存中にこのエントリーへ打った文字があれば、そのエントリーを控える(保存を始めたあとにエントリーが置き換わったか)
            const tempEntry = resume.projects.find((e) => e.id === tempId);
            const editedEntry = tempEntry !== onMutateResult?.snapshot ? tempEntry : undefined;

            // サーバーから返された新規エントリーを特定
            const createdProject = serverProjects.find(
                (sp) => !resume.projects.some((lp) => lp.id === sp.id && lp.id !== tempId),
            );

            // 保存した一時ID以外で、編集中のエントリーをマップ化
            const localDirtyMap = new Map(
                resume.projects.filter((p) => p.id !== tempId && dirtyEntryIds.has(p.id)).map((p) => [p.id, p]),
            );
            // 保存中に打った文字は、作成されたエントリーのIDで残す
            if (editedEntry && createdProject)
                localDirtyMap.set(createdProject.id, { ...editedEntry, id: createdProject.id });

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

            // ストアを更新
            updateResumeFromServer({ projects: finalProjects, updatedAt });

            // 新規作成されたエントリーをアクティブに設定
            if (createdProject) {
                setActiveEntryId(createdProject.id);
            }

            // 後処理: dirty状態のリセットと通知
            removeDirtyEntryId(tempId);
            // 保存中に打った文字があれば、作成されたエントリーを未保存のまま残す
            if (editedEntry && createdProject) addDirtyEntryId(createdProject.id);
            setNotification("プロジェクトを作成しました。", "success");
        },
        onError: (error, { tempId }) => {
            if (isResumeNotFoundError(error)) {
                options?.onResumeNotFound?.();
                return;
            }

            // バリデーションエラーをストアに保存
            const errorData = error.response?.data;
            if (errorData?.errors) {
                useResumeStore.getState().setEntryErrors(tempId, errorData.errors);
            }
        },
    });
};
