import { deleteResume, useGetResumeList } from "@/features/resume";
import { useErrorMessageStore, useNotificationStore } from "@/stores";
import { useMutation } from "@tanstack/react-query";
import type { AxiosError, AxiosResponse } from "axios";

/**
 * 職務経歴書削除フック
 * @returns 職務経歴書削除ミューテーション
 */
export const useDeleteResume = () => {
    const { clearErrors } = useErrorMessageStore();
    const { setNotification } = useNotificationStore();
    const { refetch } = useGetResumeList();

    return useMutation<AxiosResponse<void>, AxiosError, string>({
        mutationFn: (resumeId) => deleteResume(resumeId),
        onMutate: () => {
            clearErrors();
        },
        onSuccess: () => {
            clearErrors();
            setNotification("職務経歴書を削除しました。", "success");
            refetch();
        },
    });
};
