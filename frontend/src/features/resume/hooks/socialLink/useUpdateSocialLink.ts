import type { Resume, UpdateSocialLinkPayload } from "@/features/resume";
import { updateSocialLink, useResumeStore } from "@/features/resume";
import { useErrorMessageStore, useNotificationStore } from "@/stores";
import { useMutation } from "@tanstack/react-query";
import type { AxiosError, AxiosResponse } from "axios";

/**
 * SNS更新フック
 * @param resumeId 職務経歴書ID
 * @returns SNS更新ミューテーション
 */
export const useUpdateSocialLink = (resumeId: string) => {
    const { clearErrors } = useErrorMessageStore();
    const { setNotification } = useNotificationStore();

    return useMutation<AxiosResponse<Resume>, AxiosError, { socialLinkId: string; payload: UpdateSocialLinkPayload }>({
        mutationFn: ({ socialLinkId, payload }) => updateSocialLink(resumeId, socialLinkId, payload),
        onMutate: () => {
            clearErrors();
        },
        onSuccess: (response, { socialLinkId }) => {
            clearErrors();
            const { socialLinks: serverSocialLinks, updatedAt } = response.data;
            const { resume, dirtyEntryIds, updateResumeFromServer, setDirty, removeDirtyEntryId } =
                useResumeStore.getState();

            if (!resume) return;

            // ローカルのdirtyエントリーをマップ化（保存したID以外）
            const localDirtyMap = new Map(
                resume.socialLinks
                    .filter((s) => s.id !== socialLinkId && dirtyEntryIds.has(s.id))
                    .map((s) => [s.id, s]),
            );

            // ローカルにのみ存在する一時IDエントリー
            const serverIds = new Set(serverSocialLinks.map((s) => s.id));
            const localOnlyEntries = resume.socialLinks.filter((s) => !serverIds.has(s.id));

            // APIレスポンスをベースに、dirtyなエントリーはローカルデータで上書き
            const mergedSocialLinks = serverSocialLinks.map((serverEntry) => {
                const localDirty = localDirtyMap.get(serverEntry.id);
                return localDirty ?? serverEntry;
            });

            // ローカルにのみ存在するエントリーを先頭に追加
            const finalSocialLinks = [...localOnlyEntries, ...mergedSocialLinks];

            updateResumeFromServer({ socialLinks: finalSocialLinks, updatedAt });
            removeDirtyEntryId(socialLinkId);
            setDirty(false);
            setNotification("SNSを更新しました。", "success");
        },
    });
};
