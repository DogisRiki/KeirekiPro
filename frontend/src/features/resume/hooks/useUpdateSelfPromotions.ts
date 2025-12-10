import type { Resume, UpdateSelfPromotionsPayload } from "@/features/resume";
import { updateSelfPromotions, useResumeStore } from "@/features/resume";
import { useErrorMessageStore, useNotificationStore } from "@/stores";
import { useMutation } from "@tanstack/react-query";
import type { AxiosError, AxiosResponse } from "axios";

/**
 * 職務経歴書自己PR更新フック
 * @param resumeId 職務経歴書ID
 * @returns 職務経歴書自己PR更新ミューテーション
 */
export const useUpdateSelfPromotions = (resumeId: string) => {
    const { clearErrors } = useErrorMessageStore();
    const { setNotification } = useNotificationStore();
    const { setResume, setDirty } = useResumeStore();

    return useMutation<AxiosResponse<Resume>, AxiosError, UpdateSelfPromotionsPayload>({
        mutationFn: (payload) => updateSelfPromotions(resumeId, payload),
        onMutate: () => {
            clearErrors();
        },
        onSuccess: (response) => {
            clearErrors();
            setResume(response.data);
            setDirty(false);
            setNotification("自己PR情報を保存しました。", "success");
        },
    });
};
