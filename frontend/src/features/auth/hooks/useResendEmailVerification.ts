import type { ResendEmailVerificationPayload } from "@/features/auth";
import { resendEmailVerification } from "@/features/auth";
import { useErrorMessageStore, useNotificationStore } from "@/stores";
import { useMutation } from "@tanstack/react-query";
import type { AxiosError, AxiosResponse } from "axios";

/**
 * 使えなくなった確認のリンクから、確認のメールを送り直すフック
 * @returns 確認のメールの送り直しミューテーション
 */
export const useResendEmailVerification = () => {
    const { setNotification } = useNotificationStore();
    const { clearErrors } = useErrorMessageStore();

    return useMutation<AxiosResponse<void>, AxiosError, ResendEmailVerificationPayload>({
        mutationFn: (payload: ResendEmailVerificationPayload) => resendEmailVerification(payload),
        onMutate: () => {
            clearErrors();
        },
        onSuccess: () => {
            clearErrors();
            setNotification("確認のメールを送り直しました。メールの中の確認のリンクを押してください。", "success");
        },
    });
};
