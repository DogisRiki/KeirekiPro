import { requestPasswordReset, RequestPasswordResetPayload } from "@/features/auth";
import { useErrorMessageStore, useNotificationStore } from "@/stores";
import { useMutation } from "@tanstack/react-query";

/**
 * パスワードリセット要求フック
 */
export const useRequestPasswordReset = () => {
    const { setNotification } = useNotificationStore();
    const { clearErrors } = useErrorMessageStore();

    return useMutation({
        mutationFn: (payload: RequestPasswordResetPayload) => requestPasswordReset(payload),
        onSuccess: () => {
            clearErrors();
            setNotification("パスワードリセット用メールを送信しました。", "success");
        },
    });
};
