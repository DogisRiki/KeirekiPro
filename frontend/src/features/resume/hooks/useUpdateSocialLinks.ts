import type { Resume, UpdateSocialLinksPayload } from "@/features/resume";
import { updateSocialLinks, useResumeStore } from "@/features/resume";
import { useErrorMessageStore, useNotificationStore } from "@/stores";
import { useMutation } from "@tanstack/react-query";
import type { AxiosError, AxiosResponse } from "axios";

/**
 * 職務経歴書ソーシャルリンク更新フック
 * @param resumeId 職務経歴書ID
 * @returns 職務経歴書ソーシャルリンク更新ミューテーション
 */
export const useUpdateSocialLinks = (resumeId: string) => {
    const { clearErrors } = useErrorMessageStore();
    const { setNotification } = useNotificationStore();
    const { updateResume, setDirty } = useResumeStore();

    return useMutation<AxiosResponse<Resume>, AxiosError, UpdateSocialLinksPayload>({
        mutationFn: (payload) => updateSocialLinks(resumeId, payload),
        onMutate: () => {
            clearErrors();
        },
        onSuccess: (response) => {
            clearErrors();
            // ソーシャルリンクのみ更新（他のセクションの編集中データを保持）
            const { socialLinks, updatedAt } = response.data;
            updateResume({ socialLinks, updatedAt });
            setDirty(false);
            setNotification("SNS情報を保存しました。", "success");
        },
    });
};
