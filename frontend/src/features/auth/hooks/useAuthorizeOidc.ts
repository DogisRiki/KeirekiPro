import { authorizeOidc } from "@/features/auth";
import { useMutation } from "@tanstack/react-query";

/**
 * OIDC認可URLを取得してリダイレクトするフック
 */
export const useAuthorizeOidc = () => {
    return useMutation({
        mutationFn: async (provider: "google" | "github") => {
            const response = await authorizeOidc(provider);
            return response.data;
        },
        onSuccess: (authorizationUrl) => {
            window.location.href = authorizationUrl;
        },
    });
};
