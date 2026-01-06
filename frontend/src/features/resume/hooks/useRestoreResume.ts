import { paths } from "@/config/paths";
import type { Resume } from "@/features/resume";
import { restoreResume } from "@/features/resume";
import { useErrorMessageStore, useNotificationStore } from "@/stores";
import { useMutation } from "@tanstack/react-query";
import type { AxiosError, AxiosResponse } from "axios";
import { useNavigate } from "react-router";

/**
 * 職務経歴書リストアフック
 * @returns 職務経歴書リストアミューテーション
 */
export const useRestoreResume = () => {
    const { clearErrors } = useErrorMessageStore();
    const { setNotification } = useNotificationStore();
    const navigate = useNavigate();

    return useMutation<AxiosResponse<Resume>, AxiosError, File>({
        mutationFn: (file) => restoreResume(file),
        onMutate: () => {
            clearErrors();
        },
        onSuccess: (response) => {
            clearErrors();
            setNotification("職務経歴書をリストアしました。", "success");
            const resumeId = response.data.id;
            const editPath = paths.resume.edit.replace(":id", resumeId);
            navigate(editPath);
        },
    });
};
