import type { ChangePasswordPayload } from "@/features/user";
import { changePassword } from "@/features/user";
import { useErrorMessageStore, useNotificationStore } from "@/stores";
import { useMutation } from "@tanstack/react-query";
import type { AxiosError, AxiosResponse } from "axios";

/**
 * パスワード変更フック
 * @returns パスワード変更ミューテーション
 */
export const useChangePassword = () => {
    const { clearErrors } = useErrorMessageStore();
    const { setNotification } = useNotificationStore();

    return useMutation<AxiosResponse<void>, AxiosError, ChangePasswordPayload>({
        mutationFn: (payload: ChangePasswordPayload) => changePassword(payload),
        onMutate: () => {
            clearErrors();
        },
        onSuccess: () => {
            clearErrors();
            setNotification("パスワードを変更しました。", "success");
        },
    });
};
