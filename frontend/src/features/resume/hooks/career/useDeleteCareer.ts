import {
    deleteCareer,
    isResumeNotFoundError,
    isSectionNotFoundError,
    syncResumeInfoFromServer,
    useResumeStore,
    type ResumeNotFoundHandler,
} from "@/features/resume";
import { useErrorMessageStore, useNotificationStore } from "@/stores";
import type { ErrorResponse } from "@/types";
import { useMutation } from "@tanstack/react-query";
import type { AxiosError, AxiosResponse } from "axios";

/**
 * 職歴削除フック
 * @param resumeId 職務経歴書ID
 * @returns 職歴削除ミューテーション
 */
export const useDeleteCareer = (resumeId: string, options?: { onResumeNotFound?: ResumeNotFoundHandler }) => {
    const { clearErrors } = useErrorMessageStore();
    const { setNotification } = useNotificationStore();
    const { resume, updateResume, setDirty, removeDirtyEntryId, setActiveEntryId } = useResumeStore();

    return useMutation<AxiosResponse<void>, AxiosError<ErrorResponse>, string>({
        mutationFn: (careerId) => deleteCareer(resumeId, careerId),
        onMutate: () => {
            // リクエスト開始時にエラーをクリア
            clearErrors();
        },
        onSuccess: (_, careerId) => {
            // エラーをクリア
            clearErrors();
            // ローカルストアから削除したエントリーを除外
            if (resume) {
                const updatedCareers = resume.careers.filter((c) => c.id !== careerId);
                updateResume({ careers: updatedCareers });
            }
            // 後処理: dirty状態のリセットと通知
            removeDirtyEntryId(careerId);
            setActiveEntryId(null);
            setDirty(false);
            setNotification("職歴を削除しました。", "success");
        },
        onError: async (error) => {
            if (isResumeNotFoundError(error)) {
                options?.onResumeNotFound?.();
                return;
            }
            if (isSectionNotFoundError(error)) {
                await syncResumeInfoFromServer(resumeId);
            }
        },
    });
};
