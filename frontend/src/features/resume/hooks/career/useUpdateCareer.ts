import type { Resume, UpdateCareerPayload } from "@/features/resume";
import { updateCareer, useResumeStore } from "@/features/resume";
import { useNotificationStore } from "@/stores";
import type { ErrorResponse } from "@/types";
import { useMutation } from "@tanstack/react-query";
import type { AxiosError, AxiosResponse } from "axios";

/**
 * 職歴更新フック
 * @param resumeId 職務経歴書ID
 * @returns 職歴更新ミューテーション
 */
export const useUpdateCareer = (resumeId: string) => {
    const { setNotification } = useNotificationStore();

    return useMutation<
        AxiosResponse<Resume>,
        AxiosError<ErrorResponse>,
        { careerId: string; payload: UpdateCareerPayload }
    >({
        mutationFn: ({ careerId, payload }) => updateCareer(resumeId, careerId, payload),
        onMutate: ({ careerId }) => {
            // リクエスト開始時にエラーをクリア
            useResumeStore.getState().clearEntryErrors(careerId);
        },
        onSuccess: (response, { careerId }) => {
            const { careers: serverCareers, updatedAt } = response.data;
            const { resume, dirtyEntryIds, updateResumeFromServer, setDirty, removeDirtyEntryId, clearEntryErrors } =
                useResumeStore.getState();

            // 保存完了したエントリーのエラーをクリア
            clearEntryErrors(careerId);

            if (!resume) return;

            // 保存したID以外で、編集中のエントリーをマップ化
            const localDirtyMap = new Map(
                resume.careers.filter((c) => c.id !== careerId && dirtyEntryIds.has(c.id)).map((c) => [c.id, c]),
            );

            // サーバーに存在しないローカル専用エントリー（未保存の新規エントリー）を抽出
            const serverIds = new Set(serverCareers.map((c) => c.id));
            const localOnlyEntries = resume.careers.filter((c) => !serverIds.has(c.id));

            // サーバーデータをベースに、編集中のエントリーはローカルデータで上書き
            const mergedCareers = serverCareers.map((serverEntry) => {
                const localDirty = localDirtyMap.get(serverEntry.id);
                return localDirty ?? serverEntry;
            });

            // ローカル専用エントリーを先頭に追加してマージ完了
            const finalCareers = [...localOnlyEntries, ...mergedCareers];

            // ストアを更新
            updateResumeFromServer({ careers: finalCareers, updatedAt });

            // 後処理: dirty状態のリセットと通知
            removeDirtyEntryId(careerId);
            setDirty(false);
            setNotification("職歴を更新しました。", "success");
        },
        onError: (error, { careerId }) => {
            // バリデーションエラーをストアに保存
            const errorData = error.response?.data;
            if (errorData?.errors) {
                useResumeStore.getState().setEntryErrors(careerId, errorData.errors);
            }
        },
    });
};
