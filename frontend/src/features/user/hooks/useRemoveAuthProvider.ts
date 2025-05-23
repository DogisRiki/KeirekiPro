// src/features/user/hooks/useRemoveAuthProvider.ts
import { removeAuthProvider } from "@/features/user";
import { useErrorMessageStore, useNotificationStore, useUserAuthStore } from "@/stores";
import { AuthProvider } from "@/types";
import { useMutation } from "@tanstack/react-query";
import { AxiosError, AxiosResponse } from "axios";

/**
 * 外部認証連携解除フック
 * @returns 外部認証連携解除ミューテーション
 */
export const useRemoveAuthProvider = () => {
    const { user, updateUserInfo } = useUserAuthStore();
    const { setNotification } = useNotificationStore();
    const { clearErrors } = useErrorMessageStore();

    return useMutation<AxiosResponse<void>, AxiosError, AuthProvider>({
        mutationFn: (provider) => removeAuthProvider(provider),
        onMutate: () => {
            clearErrors();
        },
        onSuccess: (_response, provider) => {
            clearErrors();

            // ユーザーストアを最新状態に更新
            if (user) {
                const nextProviders = user.authProviders.filter((p) => p !== provider);

                updateUserInfo({
                    ...user,
                    authProviders: nextProviders,
                });
            }
            setNotification("連携を解除しました。", "success");
        },
    });
};
