import { deleteSocialLink, useResumeStore } from "@/features/resume";
import { useErrorMessageStore, useNotificationStore } from "@/stores";
import { useMutation } from "@tanstack/react-query";
import type { AxiosError, AxiosResponse } from "axios";

/**
 * SNS削除フック
 * @param resumeId 職務経歴書ID
 * @returns SNS削除ミューテーション
 */
export const useDeleteSocialLink = (resumeId: string) => {
    const { clearErrors } = useErrorMessageStore();
    const { setNotification } = useNotificationStore();
    const { resume, updateResume, setDirty, removeDirtyEntryId, setActiveEntryId } = useResumeStore();

    return useMutation<AxiosResponse<void>, AxiosError, string>({
        mutationFn: (socialLinkId) => deleteSocialLink(resumeId, socialLinkId),
        onMutate: () => {
            clearErrors();
        },
        onSuccess: (_, socialLinkId) => {
            clearErrors();
            if (resume) {
                const updatedSocialLinks = resume.socialLinks.filter((s) => s.id !== socialLinkId);
                updateResume({ socialLinks: updatedSocialLinks });
            }
            removeDirtyEntryId(socialLinkId);
            setActiveEntryId(null);
            setDirty(false);
            setNotification("SNSを削除しました。", "success");
        },
    });
};
