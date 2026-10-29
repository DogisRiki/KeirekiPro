import { paths } from "@/config/paths";
import type { SetEmailAndPasswordPayload } from "@/features/user";
import { setEmailAndPassword } from "@/features/user";
import { useErrorMessageStore, useNotificationStore, useUserAuthStore } from "@/stores";
import type { User } from "@/types";
import { useMutation } from "@tanstack/react-query";
import type { AxiosError, AxiosResponse } from "axios";
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
            // メールアドレスは確認を済ませるまで設定待ちになる(1分の制限で送らなかったときも同じ文を出す)
            const message = variables.email
                ? "確認のメールを送りました。\nメールの中の確認のリンクを押すまで、メールアドレスは設定待ちです。"
                : "パスワードを設定しました。";
            setNotification(message, "success");
            patchUser(response.data); // ストアを反映
            navigate(paths.user, { replace: true });
        },
    });
};
