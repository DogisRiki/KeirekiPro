import { paths } from "@/config/paths";
import { useTwoFactorStore, verifyTwoFactor } from "@/features/auth";
import { getUserInfo } from "@/hooks";
import { useErrorMessageStore, useUserAuthStore } from "@/stores";
import { useMutation } from "@tanstack/react-query";
import { useNavigate } from "react-router";

import type { AxiosError, AxiosResponse } from "axios";

/**
 * 二段階認証コード検証フック
 * @returns 二段階認証コード検証ミューテーション
 */
export const useVerifyTwoFactor = () => {
    const navigate = useNavigate();
    const { setLogin } = useUserAuthStore();
    const { userId, clear } = useTwoFactorStore();
    const { clearErrors } = useErrorMessageStore();

    return useMutation<AxiosResponse<void>, AxiosError, string>({
        mutationFn: (code: string) => verifyTwoFactor({ userId: userId as string, code }),
        onMutate: () => {
            clearErrors();
        },
        onSuccess: async () => {
            clearErrors();
            clear();
            const data = await getUserInfo();
            setLogin(data);
            navigate(paths.resume.list, { replace: true });
        },
    });
};
