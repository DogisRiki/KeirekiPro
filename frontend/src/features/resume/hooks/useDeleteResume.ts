import { deleteResume, isResumeNotFoundError } from "@/features/resume";
import { useErrorMessageStore, useNotificationStore } from "@/stores";
import type { ErrorResponse } from "@/types";
import { useMutation, useQueryClient } from "@tanstack/react-query";
import type { AxiosError, AxiosResponse } from "axios";

/**
 * 職務経歴書削除フック
 * @returns 職務経歴書削除ミューテーション
 */
export const useDeleteResume = () => {
    const { clearErrors } = useErrorMessageStore();
    const { setNotification } = useNotificationStore();
    const queryClient = useQueryClient();

    return useMutation<AxiosResponse<void>, AxiosError<ErrorResponse>, string>({
        mutationFn: (resumeId) => deleteResume(resumeId),
        onMutate: () => {
            clearErrors();
        },
        onSuccess: async () => {
            clearErrors();
            setNotification("職務経歴書を削除しました。", "success");
            await queryClient.refetchQueries({ queryKey: ["getResumeList"], type: "active" });
        },
        onError: async (error) => {
            if (!isResumeNotFoundError(error)) {
                return;
            }

            await queryClient.refetchQueries({ queryKey: ["getResumeList"], type: "active" });
        },
    });
};
