import type { ResendEmailVerificationForLoginPayload } from "@/features/auth";
import { resendEmailVerificationForLogin } from "@/features/auth";
import { useErrorMessageStore, useNotificationStore } from "@/stores";
import { useMutation } from "@tanstack/react-query";
import type { AxiosError, AxiosResponse } from "axios";

/**
 * ログインの画面から、確認のメールを送るフック
 * @returns ログインの画面から確認のメールを送るミューテーション
 */
export const useResendEmailVerificationForLogin = () => {
    const { setNotification } = useNotificationStore();
    const { clearErrors } = useErrorMessageStore();

    return useMutation<AxiosResponse<void>, AxiosError, ResendEmailVerificationForLoginPayload>({
        mutationFn: (payload: ResendEmailVerificationForLoginPayload) => resendEmailVerificationForLogin(payload),
        onMutate: () => {
            clearErrors();
        },
        onSuccess: () => {
            clearErrors();
            setNotification("確認のメールを送りました。メールの中の確認のリンクを押してください。", "success");
        },
    });
};
