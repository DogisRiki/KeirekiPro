import { paths } from "@/config/paths";
import { setEmailAndPassword, SetEmailAndPasswordPayload } from "@/features/user";
import { useErrorMessageStore, useNotificationStore, useUserAuthStore } from "@/stores";
import { User } from "@/types";
import { useMutation } from "@tanstack/react-query";
import { AxiosError, AxiosResponse } from "axios";
import { useNavigate } from "react-router";

/**
 * メールアドレス+パスワード設定フック
 * @returns メールアドレス+パスワード設定ミューテーション
 */
export const useSetEmailAndPassword = () => {
    const navigate = useNavigate();
    const { clearErrors } = useErrorMessageStore();
    const { setNotification } = useNotificationStore();
    const { updateUserInfo: patchUser } = useUserAuthStore();

    return useMutation<AxiosResponse<User>, AxiosError, SetEmailAndPasswordPayload>({
        mutationFn: (payload) => setEmailAndPassword(payload),
        onMutate: () => {
            clearErrors();
        },
        onSuccess: (response, variables) => {
            clearErrors();
            const message = variables.email
                ? "メールアドレスとパスワードを設定しました。"
                : "パスワードを設定しました。";
            setNotification(message, "success");
            patchUser(response.data); // ストアを反映
            navigate(paths.user, { replace: true });
        },
    });
};
