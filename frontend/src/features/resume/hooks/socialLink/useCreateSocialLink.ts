import type { CreateSocialLinkPayload, Resume } from "@/features/resume";
import { createSocialLink, useResumeStore } from "@/features/resume";
import { useErrorMessageStore, useNotificationStore } from "@/stores";
import { useMutation } from "@tanstack/react-query";
import type { AxiosError, AxiosResponse } from "axios";

/**
 * SNS新規作成フック
 * @param resumeId 職務経歴書ID
 * @returns SNS新規作成ミューテーション
 */
export const useCreateSocialLink = (resumeId: string) => {
    const { clearErrors } = useErrorMessageStore();
    const { setNotification } = useNotificationStore();

    return useMutation<AxiosResponse<Resume>, AxiosError, { tempId: string; payload: CreateSocialLinkPayload }>({
        mutationFn: ({ payload }) => createSocialLink(resumeId, payload),
        onMutate: () => {
            clearErrors();
        },
        onSuccess: (response, { tempId }) => {
            clearErrors();
            const { socialLinks: serverSocialLinks, updatedAt } = response.data;
            const { resume, dirtyEntryIds, updateResumeFromServer, setDirty, removeDirtyEntryId, setActiveEntryId } =
                useResumeStore.getState();

            if (!resume) return;

            // ローカルのdirtyエントリーをマップ化（保存した一時ID以外）
            const localDirtyMap = new Map(
                resume.socialLinks.filter((s) => s.id !== tempId && dirtyEntryIds.has(s.id)).map((s) => [s.id, s]),
            );

            // ローカルにのみ存在する一時IDエントリー（保存した一時ID以外）
            const serverIds = new Set(serverSocialLinks.map((s) => s.id));
            const localOnlyEntries = resume.socialLinks.filter((s) => s.id !== tempId && !serverIds.has(s.id));

            // APIレスポンスをベースに、dirtyなエントリーはローカルデータで上書き
            const mergedSocialLinks = serverSocialLinks.map((serverEntry) => {
                const localDirty = localDirtyMap.get(serverEntry.id);
                return localDirty ?? serverEntry;
            });

            // ローカルにのみ存在するエントリーを先頭に追加
            const finalSocialLinks = [...localOnlyEntries, ...mergedSocialLinks];

            // 新しく作成されたエントリーのIDを特定
            const createdSocialLink = serverSocialLinks.find(
                (ss) => !resume.socialLinks.some((ls) => ls.id === ss.id && ls.id !== tempId),
            );

            updateResumeFromServer({ socialLinks: finalSocialLinks, updatedAt });

            if (createdSocialLink) {
                setActiveEntryId(createdSocialLink.id);
            }

            removeDirtyEntryId(tempId);
            setDirty(false);
            setNotification("SNSを作成しました。", "success");
        },
    });
};
