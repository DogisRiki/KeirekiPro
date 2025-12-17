import type { Resume, UpdatePortfolioPayload } from "@/features/resume";
import { updatePortfolio, useResumeStore } from "@/features/resume";
import { useErrorMessageStore, useNotificationStore } from "@/stores";
import { useMutation } from "@tanstack/react-query";
import type { AxiosError, AxiosResponse } from "axios";

/**
 * ポートフォリオ更新フック
 * @param resumeId 職務経歴書ID
 * @returns ポートフォリオ更新ミューテーション
 */
export const useUpdatePortfolio = (resumeId: string) => {
    const { clearErrors } = useErrorMessageStore();
    const { setNotification } = useNotificationStore();

    return useMutation<AxiosResponse<Resume>, AxiosError, { portfolioId: string; payload: UpdatePortfolioPayload }>({
        mutationFn: ({ portfolioId, payload }) => updatePortfolio(resumeId, portfolioId, payload),
        onMutate: () => {
            clearErrors();
        },
        onSuccess: (response, { portfolioId }) => {
            clearErrors();
            const { portfolios: serverPortfolios, updatedAt } = response.data;
            const { resume, dirtyEntryIds, updateResumeFromServer, setDirty, removeDirtyEntryId } =
                useResumeStore.getState();

            if (!resume) return;

            // ローカルのdirtyエントリーをマップ化（保存したID以外）
            const localDirtyMap = new Map(
                resume.portfolios.filter((p) => p.id !== portfolioId && dirtyEntryIds.has(p.id)).map((p) => [p.id, p]),
            );

            // ローカルにのみ存在する一時IDエントリー
            const serverIds = new Set(serverPortfolios.map((p) => p.id));
            const localOnlyEntries = resume.portfolios.filter((p) => !serverIds.has(p.id));

            // APIレスポンスをベースに、dirtyなエントリーはローカルデータで上書き
            const mergedPortfolios = serverPortfolios.map((serverEntry) => {
                const localDirty = localDirtyMap.get(serverEntry.id);
                return localDirty ?? serverEntry;
            });

            // ローカルにのみ存在するエントリーを先頭に追加
            const finalPortfolios = [...localOnlyEntries, ...mergedPortfolios];

            updateResumeFromServer({ portfolios: finalPortfolios, updatedAt });
            removeDirtyEntryId(portfolioId);
            setDirty(false);
            setNotification("ポートフォリオを更新しました。", "success");
        },
    });
};
