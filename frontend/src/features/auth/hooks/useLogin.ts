import { paths } from "@/config/paths";
import type { LoginPayload } from "@/features/auth";
import { login, useTwoFactorStore } from "@/features/auth";
import { getUserInfo } from "@/hooks";
import { useErrorMessageStore, useUserAuthStore } from "@/stores";
import { useMutation } from "@tanstack/react-query";
import type { AxiosError, AxiosResponse } from "axios";
import { useNavigate } from "react-router";

/**
 * ログインフック
 * @returns ログインミューテーション
 */
export const useLogin = () => {
    const navigate = useNavigate();
    const { setLogin } = useUserAuthStore();
    const { setUserId } = useTwoFactorStore();
    const { clearErrors } = useErrorMessageStore();

    return useMutation<AxiosResponse<string>, AxiosError, LoginPayload>({
        mutationFn: (payload: LoginPayload) => login(payload),
        onMutate: () => {
            clearErrors();
        },
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
