import {
    isResumeNotFoundError,
    isSectionNotFoundError,
    syncResumeInfoFromServer,
    updateSnsPlatform,
    useResumeStore,
    type Resume,
    type ResumeNotFoundHandler,
    type UpdateSnsPlatformPayload,
} from "@/features/resume";
import { useNotificationStore } from "@/stores";
import type { ErrorResponse } from "@/types";
import { useMutation } from "@tanstack/react-query";
import type { AxiosError, AxiosResponse } from "axios";

/**
 * SNSプラットフォーム更新フック
 * @param resumeId 職務経歴書ID
 * @returns SNSプラットフォーム更新ミューテーション
 */
export const useUpdateSnsPlatform = (resumeId: string, options?: { onResumeNotFound?: ResumeNotFoundHandler }) => {
    const { setNotification } = useNotificationStore();

    return useMutation<
        AxiosResponse<Resume>,
        AxiosError<ErrorResponse>,
        { snsPlatformId: string; payload: UpdateSnsPlatformPayload },
        { snapshot?: Resume["snsPlatforms"][number] }
    >({
        mutationFn: ({ snsPlatformId, payload }) => updateSnsPlatform(resumeId, snsPlatformId, payload),
        onMutate: ({ snsPlatformId }) => {
            // リクエスト開始時にエラーをクリア
            useResumeStore.getState().clearEntryErrors(snsPlatformId);
            // 保存を始めたときのエントリーを控える(保存中に打った文字を見分けるため)
            return { snapshot: useResumeStore.getState().resume?.snsPlatforms.find((e) => e.id === snsPlatformId) };
        },
        onSuccess: (response, { snsPlatformId }, onMutateResult) => {
            const { snsPlatforms: serverSnsPlatforms, updatedAt } = response.data;
            const { resume, dirtyEntryIds, updateResumeFromServer, removeDirtyEntryId, clearEntryErrors } =
                useResumeStore.getState();

            // 保存完了したエントリーのエラーをクリア
            clearEntryErrors(snsPlatformId);

            if (!resume) return;

            // 保存中にこのエントリーへ打った文字があるか(保存を始めたあとにエントリーが置き換わったか)
            const editedDuringSave = resume.snsPlatforms.some(
                (e) => e.id === snsPlatformId && e !== onMutateResult?.snapshot,
            );

            // 保存したID以外で、編集中のエントリーをマップ化
            const localDirtyMap = new Map(
                resume.snsPlatforms
                    .filter((s) => (s.id !== snsPlatformId || editedDuringSave) && dirtyEntryIds.has(s.id))
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
            // 保存中に打った文字があれば、未保存のまま残す
            if (!editedDuringSave) removeDirtyEntryId(snsPlatformId);
            setNotification("SNSを更新しました。", "success");
        },
        onError: async (error, { snsPlatformId }) => {
            if (isResumeNotFoundError(error)) {
                options?.onResumeNotFound?.();
                return;
            }
            if (isSectionNotFoundError(error)) {
                await syncResumeInfoFromServer(resumeId);
                return;
            }

            // バリデーションエラーをストアに保存
            const errorData = error.response?.data;
            if (errorData?.errors) {
                useResumeStore.getState().setEntryErrors(snsPlatformId, errorData.errors);
            }
        },
    });
};
