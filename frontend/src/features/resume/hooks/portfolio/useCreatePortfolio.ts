import type { CreatePortfolioPayload, Resume } from "@/features/resume";
import { createPortfolio, useResumeStore } from "@/features/resume";
import { useErrorMessageStore, useNotificationStore } from "@/stores";
import { useMutation } from "@tanstack/react-query";
import type { AxiosError, AxiosResponse } from "axios";

/**
 * ポートフォリオ新規作成フック
 * @param resumeId 職務経歴書ID
 * @returns ポートフォリオ新規作成ミューテーション
 */
export const useCreatePortfolio = (resumeId: string) => {
    const { clearErrors } = useErrorMessageStore();
    const { setNotification } = useNotificationStore();

    return useMutation<AxiosResponse<Resume>, AxiosError, { tempId: string; payload: CreatePortfolioPayload }>({
        mutationFn: ({ payload }) => createPortfolio(resumeId, payload),
        onMutate: () => {
            clearErrors();
        },
        onSuccess: (response, { tempId }) => {
            clearErrors();
            const { portfolios: serverPortfolios, updatedAt } = response.data;
            const { resume, dirtyEntryIds, updateResumeFromServer, setDirty, removeDirtyEntryId, setActiveEntryId } =
                useResumeStore.getState();

            if (!resume) return;

            // ローカルのdirtyエントリーをマップ化（保存した一時ID以外）
            const localDirtyMap = new Map(
                resume.portfolios.filter((p) => p.id !== tempId && dirtyEntryIds.has(p.id)).map((p) => [p.id, p]),
            );

            // ローカルにのみ存在する一時IDエントリー（保存した一時ID以外）
            const serverIds = new Set(serverPortfolios.map((p) => p.id));
            const localOnlyEntries = resume.portfolios.filter((p) => p.id !== tempId && !serverIds.has(p.id));

            // APIレスポンスをベースに、dirtyなエントリーはローカルデータで上書き
            const mergedPortfolios = serverPortfolios.map((serverEntry) => {
                const localDirty = localDirtyMap.get(serverEntry.id);
                return localDirty ?? serverEntry;
            });

            // ローカルにのみ存在するエントリーを先頭に追加
            const finalPortfolios = [...localOnlyEntries, ...mergedPortfolios];

            // 新しく作成されたエントリーのIDを特定
            const createdPortfolio = serverPortfolios.find(
                (sp) => !resume.portfolios.some((lp) => lp.id === sp.id && lp.id !== tempId),
            );

            updateResumeFromServer({ portfolios: finalPortfolios, updatedAt });

            if (createdPortfolio) {
                setActiveEntryId(createdPortfolio.id);
            }

            removeDirtyEntryId(tempId);
            setDirty(false);
            setNotification("ポートフォリオを作成しました。", "success");
        },
    });
};
