import type { Resume, UpdateSnsPlatformPayload } from "@/features/resume";
import { updateSnsPlatform, useResumeStore } from "@/features/resume";
import { useNotificationStore } from "@/stores";
import type { ErrorResponse } from "@/types";
import { useMutation } from "@tanstack/react-query";
import type { AxiosError, AxiosResponse } from "axios";

/**
 * SNSプラットフォーム更新フック
 * @param resumeId 職務経歴書ID
 * @returns SNSプラットフォーム更新ミューテーション
 */
export const useUpdateSnsPlatform = (resumeId: string) => {
    const { setNotification } = useNotificationStore();

    return useMutation<
        AxiosResponse<Resume>,
        AxiosError<ErrorResponse>,
        { snsPlatformId: string; payload: UpdateSnsPlatformPayload }
    >({
        mutationFn: ({ snsPlatformId, payload }) => updateSnsPlatform(resumeId, snsPlatformId, payload),
        onMutate: ({ snsPlatformId }) => {
            // リクエスト開始時にエラーをクリア
            useResumeStore.getState().clearEntryErrors(snsPlatformId);
        },
        onSuccess: (response, { snsPlatformId }) => {
            const { snsPlatforms: serverSnsPlatforms, updatedAt } = response.data;
            const { resume, dirtyEntryIds, updateResumeFromServer, setDirty, removeDirtyEntryId, clearEntryErrors } =
                useResumeStore.getState();

            // 保存完了したエントリーのエラーをクリア
            clearEntryErrors(snsPlatformId);

            if (!resume) return;

            // 保存したID以外で、編集中のエントリーをマップ化
            const localDirtyMap = new Map(
                resume.snsPlatforms
                    .filter((s) => s.id !== snsPlatformId && dirtyEntryIds.has(s.id))
                    .map((s) => [s.id, s]),
            );

            // サーバーに存在しないローカル専用エントリー（未保存の新規エントリー）を抽出
            const serverIds = new Set(serverSnsPlatforms.map((s) => s.id));
            const localOnlyEntries = resume.snsPlatforms.filter((s) => !serverIds.has(s.id));

            // サーバーデータをベースに、編集中のエントリーはローカルデータで上書き
            const mergedSnsPlatforms = serverSnsPlatforms.map((serverEntry) => {
                const localDirty = localDirtyMap.get(serverEntry.id);
                return localDirty ?? serverEntry;
            });

            // ローカル専用エントリーを先頭に追加してマージ完了
            const finalSnsPlatforms = [...localOnlyEntries, ...mergedSnsPlatforms];

            // ストアを更新
            updateResumeFromServer({ snsPlatforms: finalSnsPlatforms, updatedAt });

            // 後処理: dirty状態のリセットと通知
            removeDirtyEntryId(snsPlatformId);
            setDirty(false);
            setNotification("SNSを更新しました。", "success");
        },
        onError: (error, { snsPlatformId }) => {
            // バリデーションエラーをストアに保存
            const errorData = error.response?.data;
            if (errorData?.errors) {
                useResumeStore.getState().setEntryErrors(snsPlatformId, errorData.errors);
            }
        },
    });
};
