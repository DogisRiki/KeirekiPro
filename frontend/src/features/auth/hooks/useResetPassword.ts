import { paths } from "@/config/paths";
import { resetPassword, ResetPasswordPayload } from "@/features/auth";
import { useErrorMessageStore, useNotificationStore } from "@/stores";
import { useMutation } from "@tanstack/react-query";
import { useNavigate } from "react-router";

/**
 * パスワードリセットフック
 */
export const useResetPassword = () => {
    const navigate = useNavigate();
    const { setNotification } = useNotificationStore();
    const { clearErrors } = useErrorMessageStore();

    return useMutation({
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
