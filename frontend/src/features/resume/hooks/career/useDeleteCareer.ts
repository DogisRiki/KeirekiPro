import { deleteCareer, useResumeStore } from "@/features/resume";
import { useErrorMessageStore, useNotificationStore } from "@/stores";
import { useMutation } from "@tanstack/react-query";
import type { AxiosError, AxiosResponse } from "axios";

/**
 * 職歴削除フック
 * @param resumeId 職務経歴書ID
 * @returns 職歴削除ミューテーション
 */
export const useDeleteCareer = (resumeId: string) => {
    const { clearErrors } = useErrorMessageStore();
    const { setNotification } = useNotificationStore();
    const { resume, updateResume, setDirty, removeDirtyEntryId, setActiveEntryId } = useResumeStore();

    return useMutation<AxiosResponse<void>, AxiosError, string>({
        mutationFn: (careerId) => deleteCareer(resumeId, careerId),
        onMutate: () => {
            clearErrors();
        },
        onSuccess: (_, careerId) => {
            clearErrors();
            if (resume) {
                const updatedCareers = resume.careers.filter((c) => c.id !== careerId);
                updateResume({ careers: updatedCareers });
            }
            removeDirtyEntryId(careerId);
            setActiveEntryId(null);
            setDirty(false);
            setNotification("職歴を削除しました。", "success");
        },
    });
};
