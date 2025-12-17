import { paths } from "@/config/paths";
import type { ResetPasswordPayload } from "@/features/auth";
import { resetPassword } from "@/features/auth";
import { useErrorMessageStore, useNotificationStore } from "@/stores";
import { useMutation } from "@tanstack/react-query";
import type { AxiosError, AxiosResponse } from "axios";
import { useNavigate } from "react-router";

/**
 * パスワードリセットフック
 * @returns パスワードリセットミューテーション
 */
export const useResetPassword = () => {
    const navigate = useNavigate();
    const { setNotification } = useNotificationStore();
    const { clearErrors } = useErrorMessageStore();

    return useMutation<AxiosResponse<void>, AxiosError, ResetPasswordPayload>({
        mutationFn: (payload: ResetPasswordPayload) => resetPassword(payload),
        onMutate: () => {
            clearErrors();
        },
        onSuccess: () => {
            clearErrors();
            setNotification("パスワードを変更しました。ログインしてください。", "success");
            navigate(paths.login, { replace: true });
        },
    });
};
