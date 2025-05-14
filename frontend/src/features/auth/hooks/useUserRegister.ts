import { paths } from "@/config/paths";
import { userRegister, UserRegistrationPayload } from "@/features/auth";
import { useErrorMessageStore, useNotificationStore } from "@/stores";
import { useMutation } from "@tanstack/react-query";
import { useNavigate } from "react-router";

/**
 * ユーザー新規登録フック
 */
export const useUserRegister = () => {
    const navigate = useNavigate();
    const { setNotification } = useNotificationStore();
    const { clearErrors } = useErrorMessageStore();

    return useMutation({
        mutationFn: (payload: UserRegistrationPayload) => userRegister(payload),
        onMutate: () => {
            clearErrors();
        },
        onSuccess: () => {
            clearErrors();
            setNotification(
                "新規会員登録が完了しました。\n登録完了の確認メールをお送りいたしましたのでご確認ください。",
                "success",
            );
            navigate(paths.login, { replace: true });
        },
    });
};
