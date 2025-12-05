import { paths } from "@/config/paths";
import { createResume, CreateResumePayload } from "@/features/resume";
import { useErrorMessageStore, useNotificationStore } from "@/stores";
import { Resume } from "@/types";
import { useMutation } from "@tanstack/react-query";
import { AxiosError, AxiosResponse } from "axios";
import { useNavigate } from "react-router";

/**
 * 職務経歴書新規作成フック
 * @returns 職務経歴書新規作成ミューテーション
 */
export const useCreateResume = () => {
    const { clearErrors } = useErrorMessageStore();
    const { setNotification } = useNotificationStore();
    const navigate = useNavigate();

    return useMutation<AxiosResponse<Resume>, AxiosError, CreateResumePayload>({
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
    });
};
