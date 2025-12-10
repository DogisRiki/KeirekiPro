import type { Resume, UpdatePortfoliosPayload } from "@/features/resume";
import { updatePortfolios, useResumeStore } from "@/features/resume";
import { useErrorMessageStore, useNotificationStore } from "@/stores";
import { useMutation } from "@tanstack/react-query";
import type { AxiosError, AxiosResponse } from "axios";

/**
 * 職務経歴書ポートフォリオ更新フック
 * @param resumeId 職務経歴書ID
 * @returns 職務経歴書ポートフォリオ更新ミューテーション
 */
export const useUpdatePortfolios = (resumeId: string) => {
    const { clearErrors } = useErrorMessageStore();
    const { setNotification } = useNotificationStore();
    const { setResume, setDirty } = useResumeStore();

    return useMutation<AxiosResponse<Resume>, AxiosError, UpdatePortfoliosPayload>({
        mutationFn: (payload) => updatePortfolios(resumeId, payload),
        onMutate: () => {
            clearErrors();
        },
        onSuccess: (response) => {
            clearErrors();
            setResume(response.data);
            setDirty(false);
            setNotification("ポートフォリオ情報を保存しました。", "success");
        },
    });
};
