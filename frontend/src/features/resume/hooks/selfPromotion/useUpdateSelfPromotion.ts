import type { Resume, UpdateSelfPromotionPayload } from "@/features/resume";
import { updateSelfPromotion, useResumeStore } from "@/features/resume";
import { useErrorMessageStore, useNotificationStore } from "@/stores";
import { useMutation } from "@tanstack/react-query";
import type { AxiosError, AxiosResponse } from "axios";

/**
 * 自己PR更新フック
 * @param resumeId 職務経歴書ID
 * @returns 自己PR更新ミューテーション
 */
export const useUpdateSelfPromotion = (resumeId: string) => {
    const { clearErrors } = useErrorMessageStore();
    const { setNotification } = useNotificationStore();

    return useMutation<
        AxiosResponse<Resume>,
        AxiosError,
        { selfPromotionId: string; payload: UpdateSelfPromotionPayload }
    >({
        mutationFn: ({ selfPromotionId, payload }) => updateSelfPromotion(resumeId, selfPromotionId, payload),
        onMutate: () => {
            clearErrors();
        },
        onSuccess: (response, { selfPromotionId }) => {
            clearErrors();
            const { selfPromotions: serverSelfPromotions, updatedAt } = response.data;
            const { resume, dirtyEntryIds, updateResumeFromServer, setDirty, removeDirtyEntryId } =
                useResumeStore.getState();

            if (!resume) return;

            // ローカルのdirtyエントリーをマップ化（保存したID以外）
            const localDirtyMap = new Map(
                resume.selfPromotions
                    .filter((s) => s.id !== selfPromotionId && dirtyEntryIds.has(s.id))
                    .map((s) => [s.id, s]),
            );

            // ローカルにのみ存在する一時IDエントリー
            const serverIds = new Set(serverSelfPromotions.map((s) => s.id));
            const localOnlyEntries = resume.selfPromotions.filter((s) => !serverIds.has(s.id));

            // APIレスポンスをベースに、dirtyなエントリーはローカルデータで上書き
            const mergedSelfPromotions = serverSelfPromotions.map((serverEntry) => {
                const localDirty = localDirtyMap.get(serverEntry.id);
                return localDirty ?? serverEntry;
            });

            // ローカルにのみ存在するエントリーを先頭に追加
            const finalSelfPromotions = [...localOnlyEntries, ...mergedSelfPromotions];

            updateResumeFromServer({ selfPromotions: finalSelfPromotions, updatedAt });
            removeDirtyEntryId(selfPromotionId);
            setDirty(false);
            setNotification("自己PRを更新しました。", "success");
        },
    });
};
