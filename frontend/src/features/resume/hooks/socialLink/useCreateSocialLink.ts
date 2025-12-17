import type { CreateSocialLinkPayload, Resume } from "@/features/resume";
import { createSocialLink, useResumeStore } from "@/features/resume";
import { useNotificationStore } from "@/stores";
import type { ErrorResponse } from "@/types";
import { useMutation } from "@tanstack/react-query";
import type { AxiosError, AxiosResponse } from "axios";

/**
 * SNS新規作成フック
 * @param resumeId 職務経歴書ID
 * @returns SNS新規作成ミューテーション
 */
export const useCreateSocialLink = (resumeId: string) => {
    const { setNotification } = useNotificationStore();

    return useMutation<
        AxiosResponse<Resume>,
        AxiosError<ErrorResponse>,
        { tempId: string; payload: CreateSocialLinkPayload }
    >({
        mutationFn: ({ payload }) => createSocialLink(resumeId, payload),
        onMutate: ({ tempId }) => {
            // リクエスト開始時にエラーをクリア
            useResumeStore.getState().clearEntryErrors(tempId);
        },
        onSuccess: (response, { tempId }) => {
            const { socialLinks: serverSocialLinks, updatedAt } = response.data;
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
                resume.socialLinks.filter((s) => s.id !== tempId && dirtyEntryIds.has(s.id)).map((s) => [s.id, s]),
            );

            // サーバーに存在しないローカル専用エントリー（未保存の新規エントリー）を抽出
            const serverIds = new Set(serverSocialLinks.map((s) => s.id));
            const localOnlyEntries = resume.socialLinks.filter((s) => s.id !== tempId && !serverIds.has(s.id));

            // サーバーデータをベースに、編集中のエントリーはローカルデータで上書き
            const mergedSocialLinks = serverSocialLinks.map((serverEntry) => {
                const localDirty = localDirtyMap.get(serverEntry.id);
                return localDirty ?? serverEntry;
            });

            // ローカル専用エントリーを先頭に追加してマージ完了
            const finalSocialLinks = [...localOnlyEntries, ...mergedSocialLinks];

            // サーバーから返された新規エントリーを特定
            const createdSocialLink = serverSocialLinks.find(
                (ss) => !resume.socialLinks.some((ls) => ls.id === ss.id && ls.id !== tempId),
            );

            // ストアを更新
            updateResumeFromServer({ socialLinks: finalSocialLinks, updatedAt });

            // 新規作成されたエントリーをアクティブに設定
            if (createdSocialLink) {
                setActiveEntryId(createdSocialLink.id);
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
