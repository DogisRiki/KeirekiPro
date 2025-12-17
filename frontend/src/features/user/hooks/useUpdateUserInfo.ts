import type { UpdateUserInfoPayload } from "@/features/user";
import { updateUserInfo } from "@/features/user";
import { useErrorMessageStore, useNotificationStore, useUserAuthStore } from "@/stores";
import type { User } from "@/types";
import { useMutation } from "@tanstack/react-query";
import type { AxiosError, AxiosResponse } from "axios";

/**
 * ユーザー情報更新フック
 * @returns ユーザー情報更新ミューテーション
 */
export const useUpdateUserInfo = () => {
    const { clearErrors } = useErrorMessageStore();
    const { setNotification } = useNotificationStore();
    const { updateUserInfo: patchUser } = useUserAuthStore();

    return useMutation<AxiosResponse<User>, AxiosError, UpdateUserInfoPayload>({
        mutationFn: (payload) => updateUserInfo(payload),
        onMutate: () => {
            clearErrors();
        },
        onSuccess: (response) => {
            clearErrors();
            patchUser(response.data); // ストアを反映
            setNotification("ユーザー情報を更新しました。", "success");
        },
    });
};
