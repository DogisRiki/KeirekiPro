import { paths } from "@/config/paths";
import type { UserRegistrationPayload } from "@/features/auth";
import { userRegister } from "@/features/auth";
import { useErrorMessageStore, useNotificationStore } from "@/stores";
import { useMutation } from "@tanstack/react-query";
import type { AxiosError, AxiosResponse } from "axios";
import { useNavigate } from "react-router";

/**
 * ユーザー新規登録フック
 * @returns ユーザー新規登録ミューテーション
 */
export const useUserRegister = () => {
    const navigate = useNavigate();
    const { setNotification } = useNotificationStore();
    const { clearErrors } = useErrorMessageStore();

    return useMutation<AxiosResponse<void>, AxiosError, UserRegistrationPayload>({
        mutationFn: (payload: UserRegistrationPayload) => userRegister(payload),
        onMutate: () => {
            clearErrors();
        },
        onSuccess: () => {
            clearErrors();
            setNotification(
                "確認のメールを送りました。\nメールの中の確認のリンクを押して、登録を済ませてください。",
                "success",
            );
            navigate(paths.login, { replace: true });
        },
    });
};
