import type { Resume, UpdateResumeBasicPayload } from "@/features/resume";
import { updateResumeBasic, useResumeStore } from "@/features/resume";
import { useErrorMessageStore, useNotificationStore } from "@/stores";
import { useMutation } from "@tanstack/react-query";
import type { AxiosError, AxiosResponse } from "axios";

/**
 * 職務経歴書基本情報更新フック
 * @param resumeId 職務経歴書ID
 * @returns 職務経歴書基本情報更新ミューテーション
 */
export const useUpdateResumeBasic = (resumeId: string) => {
    const { clearErrors } = useErrorMessageStore();
    const { setNotification } = useNotificationStore();
    const { updateResumeFromServer, setDirty } = useResumeStore();

    return useMutation<AxiosResponse<Resume>, AxiosError, UpdateResumeBasicPayload>({
        mutationFn: (payload) => updateResumeBasic(resumeId, payload),
        onMutate: () => {
            clearErrors();
        },
        onSuccess: (response) => {
            clearErrors();
            // 基本情報のみ更新（他のセクションの編集中データを保持）
            const { resumeName, date, lastName, firstName, updatedAt } = response.data;
            updateResumeFromServer({ resumeName, date, lastName, firstName, updatedAt });
            setDirty(false);
            setNotification("基本情報を保存しました。", "success");
        },
    });
};
