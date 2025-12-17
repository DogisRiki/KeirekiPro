import type { Resume, UpdateCareerPayload } from "@/features/resume";
import { updateCareer, useResumeStore } from "@/features/resume";
import { useErrorMessageStore, useNotificationStore } from "@/stores";
import { useMutation } from "@tanstack/react-query";
import type { AxiosError, AxiosResponse } from "axios";

/**
 * 職歴更新フック
 * @param resumeId 職務経歴書ID
 * @returns 職歴更新ミューテーション
 */
export const useUpdateCareer = (resumeId: string) => {
    const { clearErrors } = useErrorMessageStore();
    const { setNotification } = useNotificationStore();

    return useMutation<AxiosResponse<Resume>, AxiosError, { careerId: string; payload: UpdateCareerPayload }>({
        mutationFn: ({ careerId, payload }) => updateCareer(resumeId, careerId, payload),
        onMutate: () => {
            clearErrors();
        },
        onSuccess: (response, { careerId }) => {
            clearErrors();
            const { careers: serverCareers, updatedAt } = response.data;
            const { resume, dirtyEntryIds, updateResumeFromServer, setDirty, removeDirtyEntryId } =
                useResumeStore.getState();

            if (!resume) return;

            // ローカルのdirtyエントリーをマップ化（保存したID以外）
            const localDirtyMap = new Map(
                resume.careers.filter((c) => c.id !== careerId && dirtyEntryIds.has(c.id)).map((c) => [c.id, c]),
            );

            // ローカルにのみ存在する一時IDエントリー
            const serverIds = new Set(serverCareers.map((c) => c.id));
            const localOnlyEntries = resume.careers.filter((c) => !serverIds.has(c.id));

            // APIレスポンスをベースに、dirtyなエントリーはローカルデータで上書き
            const mergedCareers = serverCareers.map((serverEntry) => {
                const localDirty = localDirtyMap.get(serverEntry.id);
                return localDirty ?? serverEntry;
            });

            // ローカルにのみ存在するエントリーを先頭に追加
            const finalCareers = [...localOnlyEntries, ...mergedCareers];

            updateResumeFromServer({ careers: finalCareers, updatedAt });
            removeDirtyEntryId(careerId);
            setDirty(false);
            setNotification("職歴を更新しました。", "success");
        },
    });
};
