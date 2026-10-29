import { sendEmailVerification } from "@/features/user";
import { useErrorMessageStore, useNotificationStore } from "@/stores";
import { useMutation } from "@tanstack/react-query";
import type { AxiosError, AxiosResponse } from "axios";

/**
 * 確認のメールを送るフック
 * @returns 確認のメールを送るミューテーション
 */
export const useSendEmailVerification = () => {
    const { clearErrors } = useErrorMessageStore();
    const { setNotification } = useNotificationStore();

    return useMutation<AxiosResponse<void>, AxiosError, void>({
        mutationFn: () => sendEmailVerification(),
        onMutate: () => {
            clearErrors();
        },
        onSuccess: () => {
            clearErrors();
            // 1分の制限で送れなかったときはAPIが400を返し、共通のエラー表示が文を出す
            setNotification("確認のメールを送りました。メールの中の確認のリンクを押してください。", "success");
        },
    });
};
