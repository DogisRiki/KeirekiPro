import type { Resume, UpdateCareersPayload } from "@/features/resume";
import { updateCareers, useResumeStore } from "@/features/resume";
import { useErrorMessageStore, useNotificationStore } from "@/stores";
import { useMutation } from "@tanstack/react-query";
import type { AxiosError, AxiosResponse } from "axios";

/**
 * 職務経歴書職歴更新フック
 * @param resumeId 職務経歴書ID
 * @returns 職務経歴書職歴更新ミューテーション
 */
export const useUpdateCareers = (resumeId: string) => {
    const { clearErrors } = useErrorMessageStore();
    const { setNotification } = useNotificationStore();
    const { updateResume, setDirty, clearDirtyEntryIds, resume } = useResumeStore();

    return useMutation<AxiosResponse<Resume>, AxiosError, UpdateCareersPayload>({
        mutationFn: (payload) => updateCareers(resumeId, payload),
        onMutate: () => {
            clearErrors();
        },
        onSuccess: (response) => {
            clearErrors();
            // 保存前のエントリーIDを取得
            const savedEntryIds = resume?.careers.map((c) => c.id) ?? [];
            // 職歴のみ更新（他のセクションの編集中データを保持）
            const { careers, updatedAt } = response.data;
            updateResume({ careers, updatedAt });
            // 保存されたエントリーのdirtyフラグをクリア
            clearDirtyEntryIds(savedEntryIds);
            setDirty(false);
            setNotification("職歴情報を保存しました。", "success");
        },
    });
};
