import type { Resume, UpdateCareersPayload } from "@/features/resume";
import { updateCareers, useResumeStore } from "@/features/resume";
import { useErrorMessageStore, useNotificationStore } from "@/stores";
import { useMutation } from "@tanstack/react-query";
import type { AxiosError, AxiosResponse } from "axios";

/**
 * 職務経歴書職歴更新フック
 * @param resumeId 職務経歴書ID
 * @returns 職務経歴書職歴更新ミューテーション
 */
export const useUpdateCareers = (resumeId: string) => {
    const { clearErrors } = useErrorMessageStore();
    const { setNotification } = useNotificationStore();
    const { setResume } = useResumeStore();

    return useMutation<AxiosResponse<Resume>, AxiosError, UpdateCareersPayload>({
        mutationFn: (payload) => updateCareers(resumeId, payload),
        onMutate: () => {
            clearErrors();
        },
        onSuccess: (response) => {
            clearErrors();
            setResume(response.data);
            setNotification("職歴情報を保存しました。", "success");
        },
    });
};
