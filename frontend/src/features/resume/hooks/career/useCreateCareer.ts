import {
    createCareer,
    isResumeNotFoundError,
    useResumeStore,
    type CreateCareerPayload,
    type Resume,
    type ResumeNotFoundHandler,
} from "@/features/resume";
import { useNotificationStore } from "@/stores";
import type { ErrorResponse } from "@/types";
import { useMutation } from "@tanstack/react-query";
import type { AxiosError, AxiosResponse } from "axios";

/**
 * 職歴新規作成フック
 * @param resumeId 職務経歴書ID
 * @returns 職歴新規作成ミューテーション
 */
export const useCreateCareer = (resumeId: string, options?: { onResumeNotFound?: ResumeNotFoundHandler }) => {
    const { setNotification } = useNotificationStore();

    return useMutation<
        AxiosResponse<Resume>,
        AxiosError<ErrorResponse>,
        { tempId: string; payload: CreateCareerPayload },
        { snapshot?: Resume["careers"][number] }
    >({
        mutationFn: ({ payload }) => createCareer(resumeId, payload),
        onMutate: ({ tempId }) => {
            // リクエスト開始時にエラーをクリア
            useResumeStore.getState().clearEntryErrors(tempId);
            // 保存を始めたときのエントリーを控える(保存中に打った文字を見分けるため)
            return { snapshot: useResumeStore.getState().resume?.careers.find((e) => e.id === tempId) };
        },
        onSuccess: (response, { tempId }, onMutateResult) => {
            const { careers: serverCareers, updatedAt } = response.data;
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
            const tempEntry = resume.careers.find((e) => e.id === tempId);
            const editedEntry = tempEntry !== onMutateResult?.snapshot ? tempEntry : undefined;

            // サーバーから返された新規エントリーを特定
            const createdCareer = serverCareers.find(
                (sc) => !resume.careers.some((lc) => lc.id === sc.id && lc.id !== tempId),
            );

            // 保存した一時ID以外で、編集中のエントリーをマップ化
            const localDirtyMap = new Map(
                resume.careers.filter((c) => c.id !== tempId && dirtyEntryIds.has(c.id)).map((c) => [c.id, c]),
            );
            // 保存中に打った文字は、作成されたエントリーのIDで残す
            if (editedEntry && createdCareer)
                localDirtyMap.set(createdCareer.id, { ...editedEntry, id: createdCareer.id });

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

            // ストアを更新
            updateResumeFromServer({ careers: finalCareers, updatedAt });

            // 新規作成されたエントリーをアクティブに設定
            if (createdCareer) {
                setActiveEntryId(createdCareer.id);
            }

            // 後処理: dirty状態のリセットと通知
            removeDirtyEntryId(tempId);
            // 保存中に打った文字があれば、作成されたエントリーを未保存のまま残す
            if (editedEntry && createdCareer) addDirtyEntryId(createdCareer.id);
            setNotification("職歴を作成しました。", "success");
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
