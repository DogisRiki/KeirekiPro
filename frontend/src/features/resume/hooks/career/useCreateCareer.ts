import type { CreateCareerPayload, Resume } from "@/features/resume";
import { createCareer, useResumeStore } from "@/features/resume";
import { useNotificationStore } from "@/stores";
import type { ErrorResponse } from "@/types";
import { useMutation } from "@tanstack/react-query";
import type { AxiosError, AxiosResponse } from "axios";

/**
 * 職歴新規作成フック
 * @param resumeId 職務経歴書ID
 * @returns 職歴新規作成ミューテーション
 */
export const useCreateCareer = (resumeId: string) => {
    const { setNotification } = useNotificationStore();

    return useMutation<
        AxiosResponse<Resume>,
        AxiosError<ErrorResponse>,
        { tempId: string; payload: CreateCareerPayload }
    >({
        mutationFn: ({ payload }) => createCareer(resumeId, payload),
        onMutate: ({ tempId }) => {
            // リクエスト開始時にエラーをクリア
            useResumeStore.getState().clearEntryErrors(tempId);
        },
        onSuccess: (response, { tempId }) => {
            const { careers: serverCareers, updatedAt } = response.data;
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
                resume.careers.filter((c) => c.id !== tempId && dirtyEntryIds.has(c.id)).map((c) => [c.id, c]),
            );

            // サーバーに存在しないローカル専用エントリー（未保存の新規エントリー）を抽出
            const serverIds = new Set(serverCareers.map((c) => c.id));
            const localOnlyEntries = resume.careers.filter((c) => c.id !== tempId && !serverIds.has(c.id));

            // サーバーデータをベースに、編集中のエントリーはローカルデータで上書き
            const mergedCareers = serverCareers.map((serverEntry) => {
                const localDirty = localDirtyMap.get(serverEntry.id);
                return localDirty ?? serverEntry;
            });

            // ローカル専用エントリーを先頭に追加してマージ完了
            const finalCareers = [...localOnlyEntries, ...mergedCareers];

            // サーバーから返された新規エントリーを特定
            const createdCareer = serverCareers.find(
                (sc) => !resume.careers.some((lc) => lc.id === sc.id && lc.id !== tempId),
            );

            // ストアを更新
            updateResumeFromServer({ careers: finalCareers, updatedAt });

            // 新規作成されたエントリーをアクティブに設定
            if (createdCareer) {
                setActiveEntryId(createdCareer.id);
            }

            // 後処理: dirty状態のリセットと通知
            removeDirtyEntryId(tempId);
            setDirty(false);
            setNotification("職歴を作成しました。", "success");
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
