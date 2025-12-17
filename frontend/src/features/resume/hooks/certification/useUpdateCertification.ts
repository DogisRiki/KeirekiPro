import type { Resume, UpdateCertificationPayload } from "@/features/resume";
import { updateCertification, useResumeStore } from "@/features/resume";
import { useErrorMessageStore, useNotificationStore } from "@/stores";
import { useMutation } from "@tanstack/react-query";
import type { AxiosError, AxiosResponse } from "axios";

/**
 * 資格更新フック
 * @param resumeId 職務経歴書ID
 * @returns 資格更新ミューテーション
 */
export const useUpdateCertification = (resumeId: string) => {
    const { clearErrors } = useErrorMessageStore();
    const { setNotification } = useNotificationStore();

    return useMutation<
        AxiosResponse<Resume>,
        AxiosError,
        { certificationId: string; payload: UpdateCertificationPayload }
    >({
        mutationFn: ({ certificationId, payload }) => updateCertification(resumeId, certificationId, payload),
        onMutate: () => {
            clearErrors();
        },
        onSuccess: (response, { certificationId }) => {
            clearErrors();
            const { certifications: serverCertifications, updatedAt } = response.data;
            const { resume, dirtyEntryIds, updateResumeFromServer, setDirty, removeDirtyEntryId } =
                useResumeStore.getState();

            if (!resume) return;

            // ローカルのdirtyエントリーをマップ化（保存したID以外）
            const localDirtyMap = new Map(
                resume.certifications
                    .filter((c) => c.id !== certificationId && dirtyEntryIds.has(c.id))
                    .map((c) => [c.id, c]),
            );

            // ローカルにのみ存在する一時IDエントリー
            const serverIds = new Set(serverCertifications.map((c) => c.id));
            const localOnlyEntries = resume.certifications.filter((c) => !serverIds.has(c.id));

            // APIレスポンスをベースに、dirtyなエントリーはローカルデータで上書き
            const mergedCertifications = serverCertifications.map((serverEntry) => {
                const localDirty = localDirtyMap.get(serverEntry.id);
                return localDirty ?? serverEntry;
            });

            // ローカルにのみ存在するエントリーを先頭に追加
            const finalCertifications = [...localOnlyEntries, ...mergedCertifications];

            updateResumeFromServer({ certifications: finalCertifications, updatedAt });
            removeDirtyEntryId(certificationId);
            setDirty(false);
            setNotification("資格を更新しました。", "success");
        },
    });
};
