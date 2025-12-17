import type { CreateCertificationPayload, Resume } from "@/features/resume";
import { createCertification, useResumeStore } from "@/features/resume";
import { useNotificationStore } from "@/stores";
import type { ErrorResponse } from "@/types";
import { useMutation } from "@tanstack/react-query";
import type { AxiosError, AxiosResponse } from "axios";

/**
 * 資格新規作成フック
 * @param resumeId 職務経歴書ID
 * @returns 資格新規作成ミューテーション
 */
export const useCreateCertification = (resumeId: string) => {
    const { setNotification } = useNotificationStore();

    return useMutation<
        AxiosResponse<Resume>,
        AxiosError<ErrorResponse>,
        { tempId: string; payload: CreateCertificationPayload }
    >({
        mutationFn: ({ payload }) => createCertification(resumeId, payload),
        onMutate: ({ tempId }) => {
            // リクエスト開始時にエラーをクリア
            useResumeStore.getState().clearEntryErrors(tempId);
        },
        onSuccess: (response, { tempId }) => {
            const { certifications: serverCertifications, updatedAt } = response.data;
            const {
                resume,
                dirtyEntryIds,
                updateResumeFromServer,
                setDirty,
                removeDirtyEntryId,
                setActiveEntryId,
                clearEntryErrors,
            } = useResumeStore.getState();

            // 保存完了したエントリーのエラーをクリア
            clearEntryErrors(tempId);

            if (!resume) return;

            // 保存した一時ID以外で、編集中のエントリーをマップ化
            const localDirtyMap = new Map(
                resume.certifications.filter((c) => c.id !== tempId && dirtyEntryIds.has(c.id)).map((c) => [c.id, c]),
            );

            // サーバーに存在しないローカル専用エントリー（未保存の新規エントリー）を抽出
            const serverIds = new Set(serverCertifications.map((c) => c.id));
            const localOnlyEntries = resume.certifications.filter((c) => c.id !== tempId && !serverIds.has(c.id));

            // サーバーデータをベースに、編集中のエントリーはローカルデータで上書き
            const mergedCertifications = serverCertifications.map((serverEntry) => {
                const localDirty = localDirtyMap.get(serverEntry.id);
                return localDirty ?? serverEntry;
            });

            // ローカル専用エントリーを先頭に追加してマージ完了
            const finalCertifications = [...localOnlyEntries, ...mergedCertifications];

            // サーバーから返された新規エントリーを特定
            const createdCertification = serverCertifications.find(
                (sc) => !resume.certifications.some((lc) => lc.id === sc.id && lc.id !== tempId),
            );

            // ストアを更新
            updateResumeFromServer({ certifications: finalCertifications, updatedAt });

            // 新規作成されたエントリーをアクティブに設定
            if (createdCertification) {
                setActiveEntryId(createdCertification.id);
            }

            // 後処理: dirty状態のリセットと通知
            removeDirtyEntryId(tempId);
            setDirty(false);
            setNotification("資格を作成しました。", "success");
        },
        onError: (error, { tempId }) => {
            // バリデーションエラーをストアに保存
            const errorData = error.response?.data;
            if (errorData?.errors) {
                useResumeStore.getState().setEntryErrors(tempId, errorData.errors);
            }
        },
    });
};
