import {
    deleteSnsPlatform,
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
 * SNSプラットフォーム削除フック
 * @param resumeId 職務経歴書ID
 * @returns SNSプラットフォーム削除ミューテーション
 */
export const useDeleteSnsPlatform = (resumeId: string, options?: { onResumeNotFound?: ResumeNotFoundHandler }) => {
    const { clearErrors } = useErrorMessageStore();
    const { setNotification } = useNotificationStore();
    const { resume, updateResume, setDirty, removeDirtyEntryId, setActiveEntryId } = useResumeStore();

    return useMutation<AxiosResponse<void>, AxiosError<ErrorResponse>, string>({
        mutationFn: (snsPlatformId) => deleteSnsPlatform(resumeId, snsPlatformId),
        onMutate: () => {
            // リクエスト開始時にエラーをクリア
            clearErrors();
        },
        onSuccess: (_, snsPlatformId) => {
            // エラーをクリア
            clearErrors();
            // ローカルストアから削除したエントリーを除外
            if (resume) {
                const updatedSnsPlatforms = resume.snsPlatforms.filter((s) => s.id !== snsPlatformId);
                updateResume({ snsPlatforms: updatedSnsPlatforms });
            }
            // 後処理: dirty状態のリセットと通知
            removeDirtyEntryId(snsPlatformId);
            setActiveEntryId(null);
            setDirty(false);
            setNotification("SNSを削除しました。", "success");
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
