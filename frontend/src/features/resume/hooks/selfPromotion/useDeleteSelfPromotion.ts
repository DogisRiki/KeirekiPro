import { deleteSelfPromotion, useResumeStore } from "@/features/resume";
import { useErrorMessageStore, useNotificationStore } from "@/stores";
import { useMutation } from "@tanstack/react-query";
import type { AxiosError, AxiosResponse } from "axios";

/**
 * 自己PR削除フック
 * @param resumeId 職務経歴書ID
 * @returns 自己PR削除ミューテーション
 */
export const useDeleteSelfPromotion = (resumeId: string) => {
    const { clearErrors } = useErrorMessageStore();
    const { setNotification } = useNotificationStore();
    const { resume, updateResume, setDirty, removeDirtyEntryId, setActiveEntryId } = useResumeStore();

    return useMutation<AxiosResponse<void>, AxiosError, string>({
        mutationFn: (selfPromotionId) => deleteSelfPromotion(resumeId, selfPromotionId),
        onMutate: () => {
            clearErrors();
        },
        onSuccess: (_, selfPromotionId) => {
            clearErrors();
            if (resume) {
                const updatedSelfPromotions = resume.selfPromotions.filter((s) => s.id !== selfPromotionId);
                updateResume({ selfPromotions: updatedSelfPromotions });
            }
            removeDirtyEntryId(selfPromotionId);
            setActiveEntryId(null);
            setDirty(false);
            setNotification("自己PRを削除しました。", "success");
        },
    });
};
