import type { CreateSelfPromotionPayload, Resume } from "@/features/resume";
import { createSelfPromotion, useResumeStore } from "@/features/resume";
import { useNotificationStore } from "@/stores";
import type { ErrorResponse } from "@/types";
import { useMutation } from "@tanstack/react-query";
import type { AxiosError, AxiosResponse } from "axios";

/**
 * 自己PR新規作成フック
 * @param resumeId 職務経歴書ID
 * @returns 自己PR新規作成ミューテーション
 */
export const useCreateSelfPromotion = (resumeId: string) => {
    const { setNotification } = useNotificationStore();

    return useMutation<
        AxiosResponse<Resume>,
        AxiosError<ErrorResponse>,
        { tempId: string; payload: CreateSelfPromotionPayload }
    >({
        mutationFn: ({ payload }) => createSelfPromotion(resumeId, payload),
        onMutate: ({ tempId }) => {
            // リクエスト開始時にエラーをクリア
            useResumeStore.getState().clearEntryErrors(tempId);
        },
        onSuccess: (response, { tempId }) => {
            const { selfPromotions: serverSelfPromotions, updatedAt } = response.data;
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
                resume.selfPromotions.filter((s) => s.id !== tempId && dirtyEntryIds.has(s.id)).map((s) => [s.id, s]),
            );

            // サーバーに存在しないローカル専用エントリー（未保存の新規エントリー）を抽出
            const serverIds = new Set(serverSelfPromotions.map((s) => s.id));
            const localOnlyEntries = resume.selfPromotions.filter((s) => s.id !== tempId && !serverIds.has(s.id));

            // サーバーデータをベースに、編集中のエントリーはローカルデータで上書き
            const mergedSelfPromotions = serverSelfPromotions.map((serverEntry) => {
                const localDirty = localDirtyMap.get(serverEntry.id);
                return localDirty ?? serverEntry;
            });

            // ローカル専用エントリーを先頭に追加してマージ完了
            const finalSelfPromotions = [...localOnlyEntries, ...mergedSelfPromotions];

            // サーバーから返された新規エントリーを特定
            const createdSelfPromotion = serverSelfPromotions.find(
                (ss) => !resume.selfPromotions.some((ls) => ls.id === ss.id && ls.id !== tempId),
            );

            // ストアを更新
            updateResumeFromServer({ selfPromotions: finalSelfPromotions, updatedAt });

            // 新規作成されたエントリーをアクティブに設定
            if (createdSelfPromotion) {
                setActiveEntryId(createdSelfPromotion.id);
            }

            // 後処理: dirty状態のリセットと通知
            removeDirtyEntryId(tempId);
            setDirty(false);
            setNotification("自己PRを作成しました。", "success");
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
