import type { Resume, UpdateProjectsPayload } from "@/features/resume";
import { updateProjects, useResumeStore } from "@/features/resume";
import { useErrorMessageStore, useNotificationStore } from "@/stores";
import { useMutation } from "@tanstack/react-query";
import type { AxiosError, AxiosResponse } from "axios";

/**
 * 職務経歴書プロジェクト更新フック
 * @param resumeId 職務経歴書ID
 * @returns 職務経歴書プロジェクト更新ミューテーション
 */
export const useUpdateProjects = (resumeId: string) => {
    const { clearErrors } = useErrorMessageStore();
    const { setNotification } = useNotificationStore();
    const { setResume } = useResumeStore();

    return useMutation<AxiosResponse<Resume>, AxiosError, UpdateProjectsPayload>({
        mutationFn: (payload) => updateProjects(resumeId, payload),
        onMutate: () => {
            clearErrors();
        },
        onSuccess: (response) => {
            clearErrors();
            setResume(response.data);
            setNotification("職務内容情報を保存しました。", "success");
        },
    });
};
