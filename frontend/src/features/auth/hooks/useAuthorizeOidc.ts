import { authorizeOidc } from "@/features/auth";
import { useErrorMessageStore } from "@/stores";
import type { AuthProvider } from "@/types";
import { useMutation } from "@tanstack/react-query";
import type { AxiosError } from "axios";

/**
 * OIDC認可URLを取得してリダイレクトするフック
 * @returns OIDC認可ミューテーション
 */
export const useAuthorizeOidc = () => {
    const { clearErrors } = useErrorMessageStore();

    return useMutation<string, AxiosError, AuthProvider>({
        mutationFn: async (provider: AuthProvider) => {
            const response = await authorizeOidc(provider);
            return response.data;
        },
        onMutate: () => {
            clearErrors();
        },
        onSuccess: (authorizationUrl) => {
            clearErrors();
            window.location.href = authorizationUrl;
        },
    });
};
