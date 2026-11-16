import {
    createCertification,
    isResumeNotFoundError,
    useResumeStore,
    type CreateCertificationPayload,
    type Resume,
    type ResumeNotFoundHandler,
} from "@/features/resume";
import { useNotificationStore } from "@/stores";
import type { ErrorResponse } from "@/types";
import { useMutation } from "@tanstack/react-query";
import type { AxiosError, AxiosResponse } from "axios";

/**
 * 資格新規作成フック
 * @param resumeId 職務経歴書ID
 * @returns 資格新規作成ミューテーション
 */
export const useCreateCertification = (resumeId: string, options?: { onResumeNotFound?: ResumeNotFoundHandler }) => {
    const { setNotification } = useNotificationStore();

    return useMutation<
        AxiosResponse<Resume>,
        AxiosError<ErrorResponse>,
        { tempId: string; payload: CreateCertificationPayload },
        { snapshot?: Resume["certifications"][number] }
    >({
        mutationFn: ({ payload }) => createCertification(resumeId, payload),
        onMutate: ({ tempId }) => {
            // リクエスト開始時にエラーをクリア
            useResumeStore.getState().clearEntryErrors(tempId);
            // 保存を始めたときのエントリーを控える(保存中に打った文字を見分けるため)
            return { snapshot: useResumeStore.getState().resume?.certifications.find((e) => e.id === tempId) };
        },
        onSuccess: (response, { tempId }, onMutateResult) => {
            const { certifications: serverCertifications, updatedAt } = response.data;
            const {
                resume,
                dirtyEntryIds,
                updateResumeFromServer,
                addDirtyEntryId,
                removeDirtyEntryId,
                setActiveEntryId,
                clearEntryErrors,
            } = useResumeStore.getState();

            // 保存完了したエントリーのエラーをクリア
            clearEntryErrors(tempId);

            if (!resume) return;

            // 保存中にこのエントリーへ打った文字があれば、そのエントリーを控える(保存を始めたあとにエントリーが置き換わったか)
            const tempEntry = resume.certifications.find((e) => e.id === tempId);
            const editedEntry = tempEntry !== onMutateResult?.snapshot ? tempEntry : undefined;

            // サーバーから返された新規エントリーを特定
            const createdCertification = serverCertifications.find(
                (sc) => !resume.certifications.some((lc) => lc.id === sc.id && lc.id !== tempId),
            );

            // 保存した一時ID以外で、編集中のエントリーをマップ化
            const localDirtyMap = new Map(
                resume.certifications.filter((c) => c.id !== tempId && dirtyEntryIds.has(c.id)).map((c) => [c.id, c]),
            );
            // 保存中に打った文字は、作成されたエントリーのIDで残す
            if (editedEntry && createdCertification)
                localDirtyMap.set(createdCertification.id, { ...editedEntry, id: createdCertification.id });

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

            // ストアを更新
            updateResumeFromServer({ certifications: finalCertifications, updatedAt });

            // 新規作成されたエントリーをアクティブに設定
            if (createdCertification) {
                setActiveEntryId(createdCertification.id);
            }

            // 後処理: dirty状態のリセットと通知
            removeDirtyEntryId(tempId);
            // 保存中に打った文字があれば、作成されたエントリーを未保存のまま残す
            if (editedEntry && createdCertification) addDirtyEntryId(createdCertification.id);
            setNotification("資格を作成しました。", "success");
        },
        onError: (error, { tempId }) => {
            if (isResumeNotFoundError(error)) {
                options?.onResumeNotFound?.();
                return;
            }

            // バリデーションエラーをストアに保存
            const errorData = error.response?.data;
            if (errorData?.errors) {
                useResumeStore.getState().setEntryErrors(tempId, errorData.errors);
            }
        },
    });
};
