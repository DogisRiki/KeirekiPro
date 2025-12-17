import type { Resume, UpdateSocialLinkPayload } from "@/features/resume";
import { updateSocialLink, useResumeStore } from "@/features/resume";
import { useNotificationStore } from "@/stores";
import type { ErrorResponse } from "@/types";
import { useMutation } from "@tanstack/react-query";
import type { AxiosError, AxiosResponse } from "axios";

/**
 * SNS更新フック
 * @param resumeId 職務経歴書ID
 * @returns SNS更新ミューテーション
 */
export const useUpdateSocialLink = (resumeId: string) => {
    const { setNotification } = useNotificationStore();

    return useMutation<
        AxiosResponse<Resume>,
        AxiosError<ErrorResponse>,
        { socialLinkId: string; payload: UpdateSocialLinkPayload }
    >({
        mutationFn: ({ socialLinkId, payload }) => updateSocialLink(resumeId, socialLinkId, payload),
        onMutate: ({ socialLinkId }) => {
            // リクエスト開始時にエラーをクリア
            useResumeStore.getState().clearEntryErrors(socialLinkId);
        },
        onSuccess: (response, { socialLinkId }) => {
            const { socialLinks: serverSocialLinks, updatedAt } = response.data;
            const { resume, dirtyEntryIds, updateResumeFromServer, setDirty, removeDirtyEntryId, clearEntryErrors } =
                useResumeStore.getState();

            // 保存完了したエントリーのエラーをクリア
            clearEntryErrors(socialLinkId);

            if (!resume) return;

            // 保存したID以外で、編集中のエントリーをマップ化
            const localDirtyMap = new Map(
                resume.socialLinks
                    .filter((s) => s.id !== socialLinkId && dirtyEntryIds.has(s.id))
                    .map((s) => [s.id, s]),
            );

            // サーバーに存在しないローカル専用エントリー（未保存の新規エントリー）を抽出
            const serverIds = new Set(serverSocialLinks.map((s) => s.id));
            const localOnlyEntries = resume.socialLinks.filter((s) => !serverIds.has(s.id));

            // サーバーデータをベースに、編集中のエントリーはローカルデータで上書き
            const mergedSocialLinks = serverSocialLinks.map((serverEntry) => {
                const localDirty = localDirtyMap.get(serverEntry.id);
                return localDirty ?? serverEntry;
            });

            // ローカル専用エントリーを先頭に追加してマージ完了
            const finalSocialLinks = [...localOnlyEntries, ...mergedSocialLinks];

            // ストアを更新
            updateResumeFromServer({ socialLinks: finalSocialLinks, updatedAt });

            // 後処理: dirty状態のリセットと通知
            removeDirtyEntryId(socialLinkId);
            setDirty(false);
            setNotification("SNSを更新しました。", "success");
        },
        onError: (error, { socialLinkId }) => {
            // バリデーションエラーをストアに保存
            const errorData = error.response?.data;
            if (errorData?.errors) {
                useResumeStore.getState().setEntryErrors(socialLinkId, errorData.errors);
            }
        },
    });
};
