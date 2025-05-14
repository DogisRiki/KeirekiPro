import { authorizeOidc } from "@/features/auth";
import { useErrorMessageStore } from "@/stores";
import { AuthProvider } from "@/types";
import { useMutation } from "@tanstack/react-query";

/**
 * OIDC認可URLを取得してリダイレクトするフック
 */
export const useAuthorizeOidc = () => {
    const { clearErrors } = useErrorMessageStore();

    return useMutation({
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
