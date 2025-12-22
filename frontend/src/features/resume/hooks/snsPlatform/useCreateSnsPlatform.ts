import type { CreateSnsPlatformPayload, Resume } from "@/features/resume";
import { createSnsPlatform, useResumeStore } from "@/features/resume";
import { useNotificationStore } from "@/stores";
import type { ErrorResponse } from "@/types";
import { useMutation } from "@tanstack/react-query";
import type { AxiosError, AxiosResponse } from "axios";

/**
 * SNSプラットフォーム新規作成フック
 * @param resumeId 職務経歴書ID
 * @returns SNSプラットフォーム新規作成ミューテーション
 */
export const useCreateSnsPlatform = (resumeId: string) => {
    const { setNotification } = useNotificationStore();

    return useMutation<
        AxiosResponse<Resume>,
        AxiosError<ErrorResponse>,
        { tempId: string; payload: CreateSnsPlatformPayload }
    >({
        mutationFn: ({ payload }) => createSnsPlatform(resumeId, payload),
        onMutate: ({ tempId }) => {
            // リクエスト開始時にエラーをクリア
            useResumeStore.getState().clearEntryErrors(tempId);
        },
        onSuccess: (response, { tempId }) => {
            const { snsPlatforms: serverSnsPlatforms, updatedAt } = response.data;
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
                resume.snsPlatforms.filter((s) => s.id !== tempId && dirtyEntryIds.has(s.id)).map((s) => [s.id, s]),
            );

            // サーバーに存在しないローカル専用エントリー（未保存の新規エントリー）を抽出
            const serverIds = new Set(serverSnsPlatforms.map((s) => s.id));
            const localOnlyEntries = resume.snsPlatforms.filter((s) => s.id !== tempId && !serverIds.has(s.id));

            // サーバーデータをベースに、編集中のエントリーはローカルデータで上書き
            const mergedSnnPlatforms = serverSnsPlatforms.map((serverEntry) => {
                const localDirty = localDirtyMap.get(serverEntry.id);
                return localDirty ?? serverEntry;
            });

            // ローカル専用エントリーを先頭に追加してマージ完了
            const finalSnsPlatforms = [...localOnlyEntries, ...mergedSnnPlatforms];

            // サーバーから返された新規エントリーを特定
            const createdSnsPlatform = serverSnsPlatforms.find(
                (ss) => !resume.snsPlatforms.some((ls) => ls.id === ss.id && ls.id !== tempId),
            );

            // ストアを更新
            updateResumeFromServer({ snsPlatforms: finalSnsPlatforms, updatedAt });

            // 新規作成されたエントリーをアクティブに設定
            if (createdSnsPlatform) {
                setActiveEntryId(createdSnsPlatform.id);
            }

            // 後処理: dirty状態のリセットと通知
            removeDirtyEntryId(tempId);
            setDirty(false);
            setNotification("SNSを作成しました。", "success");
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
