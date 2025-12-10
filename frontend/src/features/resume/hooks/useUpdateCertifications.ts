import type { Resume, UpdateCertificationsPayload } from "@/features/resume";
import { updateCertifications, useResumeStore } from "@/features/resume";
import { useErrorMessageStore, useNotificationStore } from "@/stores";
import { useMutation } from "@tanstack/react-query";
import type { AxiosError, AxiosResponse } from "axios";

/**
 * 職務経歴書資格更新フック
 * @param resumeId 職務経歴書ID
 * @returns 職務経歴書資格更新ミューテーション
 */
export const useUpdateCertifications = (resumeId: string) => {
    const { clearErrors } = useErrorMessageStore();
    const { setNotification } = useNotificationStore();
    const { setResume, setDirty } = useResumeStore();

    return useMutation<AxiosResponse<Resume>, AxiosError, UpdateCertificationsPayload>({
        mutationFn: (payload) => updateCertifications(resumeId, payload),
        onMutate: () => {
            clearErrors();
        },
        onSuccess: (response) => {
            clearErrors();
            setResume(response.data);
            setDirty(false);
            setNotification("資格情報を保存しました。", "success");
        },
    });
};
