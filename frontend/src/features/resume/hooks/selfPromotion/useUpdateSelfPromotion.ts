import {
    isResumeNotFoundError,
    isSectionNotFoundError,
    syncResumeInfoFromServer,
    updateSelfPromotion,
    useResumeStore,
    type Resume,
    type ResumeNotFoundHandler,
    type UpdateSelfPromotionPayload,
} from "@/features/resume";
import { useNotificationStore } from "@/stores";
import type { ErrorResponse } from "@/types";
import { useMutation } from "@tanstack/react-query";
import type { AxiosError, AxiosResponse } from "axios";

/**
 * 自己PR更新フック
 * @param resumeId 職務経歴書ID
 * @returns 自己PR更新ミューテーション
 */
export const useUpdateSelfPromotion = (resumeId: string, options?: { onResumeNotFound?: ResumeNotFoundHandler }) => {
    const { setNotification } = useNotificationStore();

    return useMutation<
        AxiosResponse<Resume>,
        AxiosError<ErrorResponse>,
        { selfPromotionId: string; payload: UpdateSelfPromotionPayload },
        { snapshot?: Resume["selfPromotions"][number] }
    >({
        mutationFn: ({ selfPromotionId, payload }) => updateSelfPromotion(resumeId, selfPromotionId, payload),
        onMutate: ({ selfPromotionId }) => {
            // リクエスト開始時にエラーをクリア
            useResumeStore.getState().clearEntryErrors(selfPromotionId);
            // 保存を始めたときのエントリーを控える(保存中に打った文字を見分けるため)
            return { snapshot: useResumeStore.getState().resume?.selfPromotions.find((e) => e.id === selfPromotionId) };
        },
        onSuccess: (response, { selfPromotionId }, onMutateResult) => {
            const { selfPromotions: serverSelfPromotions, updatedAt } = response.data;
            const { resume, dirtyEntryIds, updateResumeFromServer, removeDirtyEntryId, clearEntryErrors } =
                useResumeStore.getState();

            // 保存完了したエントリーのエラーをクリア
            clearEntryErrors(selfPromotionId);

            if (!resume) return;

            // 保存中にこのエントリーへ打った文字があるか(保存を始めたあとにエントリーが置き換わったか)
            const editedDuringSave = resume.selfPromotions.some(
                (e) => e.id === selfPromotionId && e !== onMutateResult?.snapshot,
            );

            // 保存したID以外で、編集中のエントリーをマップ化
            const localDirtyMap = new Map(
                resume.selfPromotions
                    .filter((s) => (s.id !== selfPromotionId || editedDuringSave) && dirtyEntryIds.has(s.id))
                    .map((s) => [s.id, s]),
            );

            // サーバーに存在しないローカル専用エントリー（未保存の新規エントリー）を抽出
            const serverIds = new Set(serverSelfPromotions.map((s) => s.id));
            const localOnlyEntries = resume.selfPromotions.filter((s) => !serverIds.has(s.id));

            // サーバーデータをベースに、編集中のエントリーはローカルデータで上書き
            const mergedSelfPromotions = serverSelfPromotions.map((serverEntry) => {
                const localDirty = localDirtyMap.get(serverEntry.id);
                return localDirty ?? serverEntry;
            });

            // ローカル専用エントリーを先頭に追加してマージ完了
            const finalSelfPromotions = [...localOnlyEntries, ...mergedSelfPromotions];

            // ストアを更新
            updateResumeFromServer({ selfPromotions: finalSelfPromotions, updatedAt });

            // 後処理: dirty状態のリセットと通知
            // 保存中に打った文字があれば、未保存のまま残す
            if (!editedDuringSave) removeDirtyEntryId(selfPromotionId);
            setNotification("自己PRを更新しました。", "success");
        },
        onError: async (error, { selfPromotionId }) => {
            if (isResumeNotFoundError(error)) {
                options?.onResumeNotFound?.();
                return;
            }
            if (isSectionNotFoundError(error)) {
                await syncResumeInfoFromServer(resumeId);
                return;
            }

            // バリデーションエラーをストアに保存
            const errorData = error.response?.data;
            if (errorData?.errors) {
                useResumeStore.getState().setEntryErrors(selfPromotionId, errorData.errors);
            }
        },
    });
};
