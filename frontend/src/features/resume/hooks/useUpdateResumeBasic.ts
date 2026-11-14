import {
    BASIC_INFO_ENTRY_ID,
    isResumeNotFoundError,
    type Resume,
    type ResumeNotFoundHandler,
    updateResumeBasic,
    type UpdateResumeBasicPayload,
    useResumeStore,
} from "@/features/resume";
import { useNotificationStore } from "@/stores";
import type { ErrorResponse } from "@/types";
import { useMutation } from "@tanstack/react-query";
import type { AxiosError, AxiosResponse } from "axios";

/**
 * 基本情報の欄
 */
const BASIC_INFO_KEYS = ["resumeName", "date", "lastName", "firstName"] as const;

type BasicInfoFields = Pick<Resume, (typeof BASIC_INFO_KEYS)[number]>;

/**
 * 職務経歴書から基本情報の欄だけを取り出す
 */
const pickBasicInfo = ({ resumeName, date, lastName, firstName }: Resume): BasicInfoFields => ({
    resumeName,
    date,
    lastName,
    firstName,
});

/**
 * 職務経歴書基本情報更新フック
 * @param resumeId 職務経歴書ID
 * @returns 職務経歴書基本情報更新ミューテーション
 */
export const useUpdateResumeBasic = (resumeId: string, options?: { onResumeNotFound?: ResumeNotFoundHandler }) => {
    const { setNotification } = useNotificationStore();
    const { updateResumeFromServer, removeDirtyEntryId, setEntryErrors, clearEntryErrors } = useResumeStore();

    return useMutation<
        AxiosResponse<Resume>,
        AxiosError<ErrorResponse>,
        UpdateResumeBasicPayload,
        { snapshot?: BasicInfoFields }
    >({
        mutationFn: (payload) => updateResumeBasic(resumeId, payload),
        onMutate: () => {
            // リクエスト開始時にエラーをクリア
            clearEntryErrors(BASIC_INFO_ENTRY_ID);
            // 保存を始めたときの基本情報を控える(保存中に打った文字を見分けるため)
            const resume = useResumeStore.getState().resume;
            return { snapshot: resume ? pickBasicInfo(resume) : undefined };
        },
        onSuccess: (response, _payload, onMutateResult) => {
            clearEntryErrors(BASIC_INFO_ENTRY_ID);
            const { resumeName, date, lastName, firstName, updatedAt } = response.data;
            // 保存中に基本情報へ打った文字があるか
            const current = useResumeStore.getState().resume;
            const snapshot = onMutateResult?.snapshot;
            const editedDuringSave =
                !!current && !!snapshot && BASIC_INFO_KEYS.some((key) => current[key] !== snapshot[key]);
            if (editedDuringSave) {
                // 保存中に打った文字を残し、基本情報を未保存のまま残す
                updateResumeFromServer({ updatedAt });
            } else {
                // 基本情報のみ更新（他のセクションの編集中データを保持）
                updateResumeFromServer({ resumeName, date, lastName, firstName, updatedAt });
                removeDirtyEntryId(BASIC_INFO_ENTRY_ID);
            }
            setNotification("基本情報を保存しました。", "success");
        },
        onError: (error) => {
            if (isResumeNotFoundError(error)) {
                options?.onResumeNotFound?.();
                return;
            }

            const errorData = error.response?.data;
            if (errorData?.errors) {
                setEntryErrors(BASIC_INFO_ENTRY_ID, errorData.errors);
            }
        },
    });
};
