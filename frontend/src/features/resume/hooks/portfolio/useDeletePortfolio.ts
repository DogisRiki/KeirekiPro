import { deletePortfolio, useResumeStore } from "@/features/resume";
import { useErrorMessageStore, useNotificationStore } from "@/stores";
import { useMutation } from "@tanstack/react-query";
import type { AxiosError, AxiosResponse } from "axios";

/**
 * ポートフォリオ削除フック
 * @param resumeId 職務経歴書ID
 * @returns ポートフォリオ削除ミューテーション
 */
export const useDeletePortfolio = (resumeId: string) => {
    const { clearErrors } = useErrorMessageStore();
    const { setNotification } = useNotificationStore();
    const { resume, updateResume, setDirty, removeDirtyEntryId, setActiveEntryId } = useResumeStore();

    return useMutation<AxiosResponse<void>, AxiosError, string>({
        mutationFn: (portfolioId) => deletePortfolio(resumeId, portfolioId),
        onMutate: () => {
            // リクエスト開始時にエラーをクリア
            clearErrors();
        },
        onSuccess: (_, portfolioId) => {
            // エラーをクリア
            clearErrors();
            // ローカルストアから削除したエントリーを除外
            if (resume) {
                const updatedPortfolios = resume.portfolios.filter((p) => p.id !== portfolioId);
                updateResume({ portfolios: updatedPortfolios });
            }
            // 後処理: dirty状態のリセットと通知
            removeDirtyEntryId(portfolioId);
            setActiveEntryId(null);
            setDirty(false);
            setNotification("ポートフォリオを削除しました。", "success");
        },
    });
};
