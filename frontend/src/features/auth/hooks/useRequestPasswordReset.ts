import { requestPasswordReset, RequestPasswordResetPayload } from "@/features/auth";
import { useErrorMessageStore, useNotificationStore } from "@/stores";
import { useMutation } from "@tanstack/react-query";
import { AxiosError, AxiosResponse } from "axios";

/**
 * パスワードリセット要求フック
 * @returns パスワードリセット要求ミューテーション
 */
export const useRequestPasswordReset = () => {
    const { setNotification } = useNotificationStore();
    const { clearErrors } = useErrorMessageStore();

    return useMutation<AxiosResponse<void>, AxiosError, RequestPasswordResetPayload>({
        mutationFn: (payload: RequestPasswordResetPayload) => requestPasswordReset(payload),
        onMutate: () => {
            clearErrors();
        },
        onSuccess: () => {
            clearErrors();
            setNotification("パスワードリセット用メールを送信しました。", "success");
        },
    });
};
