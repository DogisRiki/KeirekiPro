import type { Resume, UpdateCertificationPayload } from "@/features/resume";
import { updateCertification, useResumeStore } from "@/features/resume";
import { useNotificationStore } from "@/stores";
import type { ErrorResponse } from "@/types";
import { useMutation } from "@tanstack/react-query";
import type { AxiosError, AxiosResponse } from "axios";

/**
 * 資格更新フック
 * @param resumeId 職務経歴書ID
 * @returns 資格更新ミューテーション
 */
export const useUpdateCertification = (resumeId: string) => {
    const { setNotification } = useNotificationStore();

    return useMutation<
        AxiosResponse<Resume>,
        AxiosError<ErrorResponse>,
        { certificationId: string; payload: UpdateCertificationPayload }
    >({
        mutationFn: ({ certificationId, payload }) => updateCertification(resumeId, certificationId, payload),
        onMutate: ({ certificationId }) => {
            // リクエスト開始時にエラーをクリア
            useResumeStore.getState().clearEntryErrors(certificationId);
        },
        onSuccess: (response, { certificationId }) => {
            const { certifications: serverCertifications, updatedAt } = response.data;
            const { resume, dirtyEntryIds, updateResumeFromServer, setDirty, removeDirtyEntryId, clearEntryErrors } =
                useResumeStore.getState();

            // 保存完了したエントリーのエラーをクリア
            clearEntryErrors(certificationId);

            if (!resume) return;

            // 保存したID以外で、編集中のエントリーをマップ化
            const localDirtyMap = new Map(
                resume.certifications
                    .filter((c) => c.id !== certificationId && dirtyEntryIds.has(c.id))
                    .map((c) => [c.id, c]),
            );

            // サーバーに存在しないローカル専用エントリー（未保存の新規エントリー）を抽出
            const serverIds = new Set(serverCertifications.map((c) => c.id));
            const localOnlyEntries = resume.certifications.filter((c) => !serverIds.has(c.id));

            // サーバーデータをベースに、編集中のエントリーはローカルデータで上書き
            const mergedCertifications = serverCertifications.map((serverEntry) => {
                const localDirty = localDirtyMap.get(serverEntry.id);
                return localDirty ?? serverEntry;
            });

            // ローカル専用エントリーを先頭に追加してマージ完了
            const finalCertifications = [...localOnlyEntries, ...mergedCertifications];

            // ストアを更新
            updateResumeFromServer({ certifications: finalCertifications, updatedAt });

            // 後処理: dirty状態のリセットと通知
            removeDirtyEntryId(certificationId);
            setDirty(false);
            setNotification("資格を更新しました。", "success");
        },
        onError: (error, { certificationId }) => {
            // バリデーションエラーをストアに保存
            const errorData = error.response?.data;
            if (errorData?.errors) {
                useResumeStore.getState().setEntryErrors(certificationId, errorData.errors);
            }
        },
    });
};
