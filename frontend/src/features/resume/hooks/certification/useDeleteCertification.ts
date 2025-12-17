import { deleteCertification, useResumeStore } from "@/features/resume";
import { useErrorMessageStore, useNotificationStore } from "@/stores";
import { useMutation } from "@tanstack/react-query";
import type { AxiosError, AxiosResponse } from "axios";

/**
 * 資格削除フック
 * @param resumeId 職務経歴書ID
 * @returns 資格削除ミューテーション
 */
export const useDeleteCertification = (resumeId: string) => {
    const { clearErrors } = useErrorMessageStore();
    const { setNotification } = useNotificationStore();
    const { resume, updateResume, setDirty, removeDirtyEntryId, setActiveEntryId } = useResumeStore();

    return useMutation<AxiosResponse<void>, AxiosError, string>({
        mutationFn: (certificationId) => deleteCertification(resumeId, certificationId),
        onMutate: () => {
            // リクエスト開始時にエラーをクリア
            clearErrors();
        },
        onSuccess: (_, certificationId) => {
            // エラーをクリア
            clearErrors();
            // ローカルストアから削除したエントリーを除外
            if (resume) {
                const updatedCertifications = resume.certifications.filter((c) => c.id !== certificationId);
                updateResume({ certifications: updatedCertifications });
            }
            // 後処理: dirty状態のリセットと通知
            removeDirtyEntryId(certificationId);
            setActiveEntryId(null);
            setDirty(false);
            setNotification("資格を削除しました。", "success");
        },
    });
};
