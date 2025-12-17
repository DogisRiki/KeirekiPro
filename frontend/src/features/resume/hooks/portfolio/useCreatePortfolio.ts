import type { CreatePortfolioPayload, Resume } from "@/features/resume";
import { createPortfolio, useResumeStore } from "@/features/resume";
import { useNotificationStore } from "@/stores";
import type { ErrorResponse } from "@/types";
import { useMutation } from "@tanstack/react-query";
import type { AxiosError, AxiosResponse } from "axios";

/**
 * ポートフォリオ新規作成フック
 * @param resumeId 職務経歴書ID
 * @returns ポートフォリオ新規作成ミューテーション
 */
export const useCreatePortfolio = (resumeId: string) => {
    const { setNotification } = useNotificationStore();

    return useMutation<
        AxiosResponse<Resume>,
        AxiosError<ErrorResponse>,
        { tempId: string; payload: CreatePortfolioPayload }
    >({
        mutationFn: ({ payload }) => createPortfolio(resumeId, payload),
        onMutate: ({ tempId }) => {
            // リクエスト開始時にエラーをクリア
            useResumeStore.getState().clearEntryErrors(tempId);
        },
        onSuccess: (response, { tempId }) => {
            const { portfolios: serverPortfolios, updatedAt } = response.data;
            const {
                resume,
                dirtyEntryIds,
                updateResumeFromServer,
                setDirty,
                removeDirtyEntryId,
                setActiveEntryId,
                clearEntryErrors,
            } = useResumeStore.getState();

            // 保存完了したエントリーのエラーをクリア
            clearEntryErrors(tempId);

            if (!resume) return;

            // 保存した一時ID以外で、編集中のエントリーをマップ化
            const localDirtyMap = new Map(
                resume.portfolios.filter((p) => p.id !== tempId && dirtyEntryIds.has(p.id)).map((p) => [p.id, p]),
            );

            // サーバーに存在しないローカル専用エントリー（未保存の新規エントリー）を抽出
            const serverIds = new Set(serverPortfolios.map((p) => p.id));
            const localOnlyEntries = resume.portfolios.filter((p) => p.id !== tempId && !serverIds.has(p.id));

            // サーバーデータをベースに、編集中のエントリーはローカルデータで上書き
            const mergedPortfolios = serverPortfolios.map((serverEntry) => {
                const localDirty = localDirtyMap.get(serverEntry.id);
                return localDirty ?? serverEntry;
            });

            // ローカル専用エントリーを先頭に追加してマージ完了
            const finalPortfolios = [...localOnlyEntries, ...mergedPortfolios];

            // サーバーから返された新規エントリーを特定
            const createdPortfolio = serverPortfolios.find(
                (sp) => !resume.portfolios.some((lp) => lp.id === sp.id && lp.id !== tempId),
            );

            // ストアを更新
            updateResumeFromServer({ portfolios: finalPortfolios, updatedAt });

            // 新規作成されたエントリーをアクティブに設定
            if (createdPortfolio) {
                setActiveEntryId(createdPortfolio.id);
            }

            // 後処理: dirty状態のリセットと通知
            removeDirtyEntryId(tempId);
            setDirty(false);
            setNotification("ポートフォリオを作成しました。", "success");
        },
        onError: (error, { tempId }) => {
            // バリデーションエラーをストアに保存
            const errorData = error.response?.data;
            if (errorData?.errors) {
                useResumeStore.getState().setEntryErrors(tempId, errorData.errors);
            }
        },
    });
};
