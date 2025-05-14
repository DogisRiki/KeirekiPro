import { paths } from "@/config/paths";
import { login, LoginPayload, useTwoFactorStore } from "@/features/auth";
import { getUserInfo } from "@/hooks";
import { useErrorMessageStore, useUserAuthStore } from "@/stores";
import { useMutation } from "@tanstack/react-query";
import { useNavigate } from "react-router";

/**
 * ログインフック
 */
export const useLogin = () => {
    const navigate = useNavigate();
    const { setLogin } = useUserAuthStore();
    const { setUserId } = useTwoFactorStore();
    const { clearErrors } = useErrorMessageStore();

    return useMutation({
        mutationFn: (payload: LoginPayload) => login(payload),
        onSuccess: async (response) => {
            clearErrors();
            // 2FAが無効
            if (response.status === 200) {
                const data = await getUserInfo();
                setLogin(data);
                navigate(paths.resume.list, { replace: true });
            }
            // 2FAが有効
            if (response.status === 202) {
                setUserId(response.data);
                navigate(paths.twoFactor, { replace: true });
            }
        },
    });
};
