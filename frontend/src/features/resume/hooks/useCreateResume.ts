import { paths } from "@/config/paths";
import type { CreateResumePayload, Resume } from "@/features/resume";
import { createResume, isResumeNotFoundError } from "@/features/resume";
import { useErrorMessageStore, useNotificationStore } from "@/stores";
import type { ErrorResponse } from "@/types";
import { useMutation, useQueryClient } from "@tanstack/react-query";
import type { AxiosError, AxiosResponse } from "axios";
import { useNavigate } from "react-router";

/**
 * 職務経歴書新規作成フック
 * @returns 職務経歴書新規作成ミューテーション
 */
export const useCreateResume = (options?: { onCopySourceNotFound?: () => void }) => {
    const { clearErrors } = useErrorMessageStore();
    const { setNotification } = useNotificationStore();
    const queryClient = useQueryClient();
    const navigate = useNavigate();

    return useMutation<AxiosResponse<Resume>, AxiosError<ErrorResponse>, CreateResumePayload>({
        mutationFn: (payload) => createResume(payload),
        onMutate: () => {
            clearErrors();
        },
        onSuccess: (response) => {
            clearErrors();
            setNotification("職務経歴書を作成しました。", "success");
            const resumeId = response.data.id;
            const editPath = paths.resume.edit.replace(":id", resumeId);
            navigate(editPath, { replace: true });
        },
        onError: async (error) => {
            if (!isResumeNotFoundError(error)) {
                return;
            }

            options?.onCopySourceNotFound?.();
            await queryClient.refetchQueries({ queryKey: ["getResumeList"], type: "active" });
        },
    });
};
