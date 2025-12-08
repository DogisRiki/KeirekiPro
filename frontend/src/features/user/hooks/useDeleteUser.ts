import { paths } from "@/config/paths";
import { deleteUser } from "@/features/user";
import { useErrorMessageStore, useNotificationStore, useUserAuthStore } from "@/stores";
import { useMutation } from "@tanstack/react-query";
import type { AxiosError, AxiosResponse } from "axios";
import { useNavigate } from "react-router";

/**
 * ユーザー退会フック
 * @returns ユーザー退会ミューテーション
 */
export const useDeleteUser = () => {
    const { setLogout } = useUserAuthStore();
    const { setNotification } = useNotificationStore();
    const { clearErrors } = useErrorMessageStore();
    const navigate = useNavigate();

    return useMutation<AxiosResponse<void>, AxiosError>({
        mutationFn: () => deleteUser(),
        onMutate: () => {
            clearErrors();
        },
        onSuccess: () => {
            clearErrors();
            setLogout();
            setNotification("退会が完了しました。ご利用ありがとうございました。", "success");
            navigate(paths.login, { replace: true });
        },
    });
};
