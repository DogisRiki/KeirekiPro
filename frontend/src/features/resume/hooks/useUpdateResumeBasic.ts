import {
    BASIC_INFO_ENTRY_ID,
    isResumeNotFoundError,
    type Resume,
    type ResumeNotFoundHandler,
    updateResumeBasic,
    type UpdateResumeBasicPayload,
    useResumeStore,
} from "@/features/resume";
import { useNotificationStore } from "@/stores";
import type { ErrorResponse } from "@/types";
import { useMutation } from "@tanstack/react-query";
import type { AxiosError, AxiosResponse } from "axios";

/**
 * 職務経歴書基本情報更新フック
 * @param resumeId 職務経歴書ID
 * @returns 職務経歴書基本情報更新ミューテーション
 */
export const useUpdateResumeBasic = (resumeId: string, options?: { onResumeNotFound?: ResumeNotFoundHandler }) => {
    const { setNotification } = useNotificationStore();
    const { updateResumeFromServer, setDirty, setEntryErrors, clearEntryErrors } = useResumeStore();

    return useMutation<AxiosResponse<Resume>, AxiosError<ErrorResponse>, UpdateResumeBasicPayload>({
        mutationFn: (payload) => updateResumeBasic(resumeId, payload),
        onMutate: () => {
            // リクエスト開始時にエラーをクリア
            clearEntryErrors(BASIC_INFO_ENTRY_ID);
        },
        onSuccess: (response) => {
            clearEntryErrors(BASIC_INFO_ENTRY_ID);
            // 基本情報のみ更新（他のセクションの編集中データを保持）
            const { resumeName, date, lastName, firstName, updatedAt } = response.data;
            updateResumeFromServer({ resumeName, date, lastName, firstName, updatedAt });
            setDirty(false);
            setNotification("基本情報を保存しました。", "success");
        },
        onError: (error) => {
            if (isResumeNotFoundError(error)) {
                options?.onResumeNotFound?.();
                return;
            }

            const errorData = error.response?.data;
            if (errorData?.errors) {
                setEntryErrors(BASIC_INFO_ENTRY_ID, errorData.errors);
            }
        },
    });
};
