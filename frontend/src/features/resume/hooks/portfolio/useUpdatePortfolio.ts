import type { Resume, UpdatePortfolioPayload } from "@/features/resume";
import { updatePortfolio, useResumeStore } from "@/features/resume";
import { useNotificationStore } from "@/stores";
import type { ErrorResponse } from "@/types";
import { useMutation } from "@tanstack/react-query";
import type { AxiosError, AxiosResponse } from "axios";

/**
 * ポートフォリオ更新フック
 * @param resumeId 職務経歴書ID
 * @returns ポートフォリオ更新ミューテーション
 */
export const useUpdatePortfolio = (resumeId: string) => {
    const { setNotification } = useNotificationStore();

    return useMutation<
        AxiosResponse<Resume>,
        AxiosError<ErrorResponse>,
        { portfolioId: string; payload: UpdatePortfolioPayload }
    >({
        mutationFn: ({ portfolioId, payload }) => updatePortfolio(resumeId, portfolioId, payload),
        onMutate: ({ portfolioId }) => {
            // リクエスト開始時にエラーをクリア
            useResumeStore.getState().clearEntryErrors(portfolioId);
        },
        onSuccess: (response, { portfolioId }) => {
            const { portfolios: serverPortfolios, updatedAt } = response.data;
            const { resume, dirtyEntryIds, updateResumeFromServer, setDirty, removeDirtyEntryId, clearEntryErrors } =
                useResumeStore.getState();

            // 保存完了したエントリーのエラーをクリア
            clearEntryErrors(portfolioId);

            if (!resume) return;

            // 保存したID以外で、編集中のエントリーをマップ化
            const localDirtyMap = new Map(
                resume.portfolios.filter((p) => p.id !== portfolioId && dirtyEntryIds.has(p.id)).map((p) => [p.id, p]),
            );

            // サーバーに存在しないローカル専用エントリー（未保存の新規エントリー）を抽出
            const serverIds = new Set(serverPortfolios.map((p) => p.id));
            const localOnlyEntries = resume.portfolios.filter((p) => !serverIds.has(p.id));

            // サーバーデータをベースに、編集中のエントリーはローカルデータで上書き
            const mergedPortfolios = serverPortfolios.map((serverEntry) => {
                const localDirty = localDirtyMap.get(serverEntry.id);
                return localDirty ?? serverEntry;
            });

            // ローカル専用エントリーを先頭に追加してマージ完了
            const finalPortfolios = [...localOnlyEntries, ...mergedPortfolios];

            // ストアを更新
            updateResumeFromServer({ portfolios: finalPortfolios, updatedAt });

            // 後処理: dirty状態のリセットと通知
            removeDirtyEntryId(portfolioId);
            setDirty(false);
            setNotification("ポートフォリオを更新しました。", "success");
        },
        onError: (error, { portfolioId }) => {
            // バリデーションエラーをストアに保存
            const errorData = error.response?.data;
            if (errorData?.errors) {
                useResumeStore.getState().setEntryErrors(portfolioId, errorData.errors);
            }
        },
    });
};
