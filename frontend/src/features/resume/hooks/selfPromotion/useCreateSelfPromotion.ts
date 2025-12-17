import type { CreateSelfPromotionPayload, Resume } from "@/features/resume";
import { createSelfPromotion, useResumeStore } from "@/features/resume";
import { useErrorMessageStore, useNotificationStore } from "@/stores";
import { useMutation } from "@tanstack/react-query";
import type { AxiosError, AxiosResponse } from "axios";

/**
 * 自己PR新規作成フック
 * @param resumeId 職務経歴書ID
 * @returns 自己PR新規作成ミューテーション
 */
export const useCreateSelfPromotion = (resumeId: string) => {
    const { clearErrors } = useErrorMessageStore();
    const { setNotification } = useNotificationStore();

    return useMutation<AxiosResponse<Resume>, AxiosError, { tempId: string; payload: CreateSelfPromotionPayload }>({
        mutationFn: ({ payload }) => createSelfPromotion(resumeId, payload),
        onMutate: () => {
            clearErrors();
        },
        onSuccess: (response, { tempId }) => {
            clearErrors();
            const { selfPromotions: serverSelfPromotions, updatedAt } = response.data;
            const { resume, dirtyEntryIds, updateResumeFromServer, setDirty, removeDirtyEntryId, setActiveEntryId } =
                useResumeStore.getState();

            if (!resume) return;

            // ローカルのdirtyエントリーをマップ化（保存した一時ID以外）
            const localDirtyMap = new Map(
                resume.selfPromotions.filter((s) => s.id !== tempId && dirtyEntryIds.has(s.id)).map((s) => [s.id, s]),
            );

            // ローカルにのみ存在する一時IDエントリー（保存した一時ID以外）
            const serverIds = new Set(serverSelfPromotions.map((s) => s.id));
            const localOnlyEntries = resume.selfPromotions.filter((s) => s.id !== tempId && !serverIds.has(s.id));

            // APIレスポンスをベースに、dirtyなエントリーはローカルデータで上書き
            const mergedSelfPromotions = serverSelfPromotions.map((serverEntry) => {
                const localDirty = localDirtyMap.get(serverEntry.id);
                return localDirty ?? serverEntry;
            });

            // ローカルにのみ存在するエントリーを先頭に追加
            const finalSelfPromotions = [...localOnlyEntries, ...mergedSelfPromotions];

            // 新しく作成されたエントリーのIDを特定
            const createdSelfPromotion = serverSelfPromotions.find(
                (ss) => !resume.selfPromotions.some((ls) => ls.id === ss.id && ls.id !== tempId),
            );

            updateResumeFromServer({ selfPromotions: finalSelfPromotions, updatedAt });

            if (createdSelfPromotion) {
                setActiveEntryId(createdSelfPromotion.id);
            }

            removeDirtyEntryId(tempId);
            setDirty(false);
            setNotification("自己PRを作成しました。", "success");
        },
    });
};
