import type { CreateCareerPayload, Resume } from "@/features/resume";
import { createCareer, useResumeStore } from "@/features/resume";
import { useErrorMessageStore, useNotificationStore } from "@/stores";
import { useMutation } from "@tanstack/react-query";
import type { AxiosError, AxiosResponse } from "axios";

/**
 * 職歴新規作成フック
 * @param resumeId 職務経歴書ID
 * @returns 職歴新規作成ミューテーション
 */
export const useCreateCareer = (resumeId: string) => {
    const { clearErrors } = useErrorMessageStore();
    const { setNotification } = useNotificationStore();

    return useMutation<AxiosResponse<Resume>, AxiosError, { tempId: string; payload: CreateCareerPayload }>({
        mutationFn: ({ payload }) => createCareer(resumeId, payload),
        onMutate: () => {
            clearErrors();
        },
        onSuccess: (response, { tempId }) => {
            clearErrors();
            const { careers: serverCareers, updatedAt } = response.data;
            const { resume, dirtyEntryIds, updateResumeFromServer, setDirty, removeDirtyEntryId, setActiveEntryId } =
                useResumeStore.getState();

            if (!resume) return;

            // ローカルのdirtyエントリーをマップ化（保存した一時ID以外）
            const localDirtyMap = new Map(
                resume.careers.filter((c) => c.id !== tempId && dirtyEntryIds.has(c.id)).map((c) => [c.id, c]),
            );

            // ローカルにのみ存在する一時IDエントリー（保存した一時ID以外）
            const serverIds = new Set(serverCareers.map((c) => c.id));
            const localOnlyEntries = resume.careers.filter((c) => c.id !== tempId && !serverIds.has(c.id));

            // APIレスポンスをベースに、dirtyなエントリーはローカルデータで上書き
            const mergedCareers = serverCareers.map((serverEntry) => {
                const localDirty = localDirtyMap.get(serverEntry.id);
                return localDirty ?? serverEntry;
            });

            // ローカルにのみ存在するエントリーを先頭に追加
            const finalCareers = [...localOnlyEntries, ...mergedCareers];

            // 新しく作成されたエントリーのIDを特定
            const createdCareer = serverCareers.find(
                (sc) => !resume.careers.some((lc) => lc.id === sc.id && lc.id !== tempId),
            );

            updateResumeFromServer({ careers: finalCareers, updatedAt });

            if (createdCareer) {
                setActiveEntryId(createdCareer.id);
            }

            removeDirtyEntryId(tempId);
            setDirty(false);
            setNotification("職歴を作成しました。", "success");
        },
    });
};
