import type { Resume, UpdatePortfoliosPayload } from "@/features/resume";
import { updatePortfolios, useResumeStore } from "@/features/resume";
import { useErrorMessageStore, useNotificationStore } from "@/stores";
import { useMutation } from "@tanstack/react-query";
import type { AxiosError, AxiosResponse } from "axios";

/**
 * 職務経歴書ポートフォリオ更新フック
 * @param resumeId 職務経歴書ID
 * @returns 職務経歴書ポートフォリオ更新ミューテーション
 */
export const useUpdatePortfolios = (resumeId: string) => {
    const { clearErrors } = useErrorMessageStore();
    const { setNotification } = useNotificationStore();
    const { updateResume, setDirty, clearDirtyEntryIds, resume } = useResumeStore();

    return useMutation<AxiosResponse<Resume>, AxiosError, UpdatePortfoliosPayload>({
        mutationFn: (payload) => updatePortfolios(resumeId, payload),
        onMutate: () => {
            clearErrors();
        },
        onSuccess: (response) => {
            clearErrors();
            // 保存前のエントリーIDを取得
            const savedEntryIds = resume?.portfolios.map((p) => p.id) ?? [];
            // ポートフォリオのみ更新（他のセクションの編集中データを保持）
            const { portfolios, updatedAt } = response.data;
            updateResume({ portfolios, updatedAt });
            // 保存されたエントリーのdirtyフラグをクリア
            clearDirtyEntryIds(savedEntryIds);
            setDirty(false);
            setNotification("ポートフォリオ情報を保存しました。", "success");
        },
    });
};
