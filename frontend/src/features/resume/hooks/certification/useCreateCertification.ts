import type { CreateCertificationPayload, Resume } from "@/features/resume";
import { createCertification, useResumeStore } from "@/features/resume";
import { useErrorMessageStore, useNotificationStore } from "@/stores";
import { useMutation } from "@tanstack/react-query";
import type { AxiosError, AxiosResponse } from "axios";

/**
 * 資格新規作成フック
 * @param resumeId 職務経歴書ID
 * @returns 資格新規作成ミューテーション
 */
export const useCreateCertification = (resumeId: string) => {
    const { clearErrors } = useErrorMessageStore();
    const { setNotification } = useNotificationStore();

    return useMutation<AxiosResponse<Resume>, AxiosError, { tempId: string; payload: CreateCertificationPayload }>({
        mutationFn: ({ payload }) => createCertification(resumeId, payload),
        onMutate: () => {
            clearErrors();
        },
        onSuccess: (response, { tempId }) => {
            clearErrors();
            const { certifications: serverCertifications, updatedAt } = response.data;
            const { resume, dirtyEntryIds, updateResumeFromServer, setDirty, removeDirtyEntryId, setActiveEntryId } =
                useResumeStore.getState();

            if (!resume) return;

            // ローカルのdirtyエントリーをマップ化（保存した一時ID以外）
            const localDirtyMap = new Map(
                resume.certifications.filter((c) => c.id !== tempId && dirtyEntryIds.has(c.id)).map((c) => [c.id, c]),
            );

            // ローカルにのみ存在する一時IDエントリー（保存した一時ID以外）
            const serverIds = new Set(serverCertifications.map((c) => c.id));
            const localOnlyEntries = resume.certifications.filter((c) => c.id !== tempId && !serverIds.has(c.id));

            // APIレスポンスをベースに、dirtyなエントリーはローカルデータで上書き
            const mergedCertifications = serverCertifications.map((serverEntry) => {
                const localDirty = localDirtyMap.get(serverEntry.id);
                return localDirty ?? serverEntry;
            });

            // ローカルにのみ存在するエントリーを先頭に追加
            const finalCertifications = [...localOnlyEntries, ...mergedCertifications];

            // 新しく作成されたエントリーのIDを特定
            const createdCertification = serverCertifications.find(
                (sc) => !resume.certifications.some((lc) => lc.id === sc.id && lc.id !== tempId),
            );

            updateResumeFromServer({ certifications: finalCertifications, updatedAt });

            if (createdCertification) {
                setActiveEntryId(createdCertification.id);
            }

            removeDirtyEntryId(tempId);
            setDirty(false);
            setNotification("資格を作成しました。", "success");
        },
    });
};
