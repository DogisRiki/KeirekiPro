import { paths } from "@/config/paths";
import { verifyTwoFactor } from "@/features/auth";
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
    const { clearErrors } = useErrorMessageStore();

    return useMutation<AxiosResponse<void>, AxiosError, string>({
        mutationFn: (code: string) => verifyTwoFactor({ code }),
        onMutate: () => {
            clearErrors();
        },
        onSuccess: async () => {
            clearErrors();
            const data = await getUserInfo();
            setLogin(data);
            navigate(paths.resume.list, { replace: true });
        },
    });
};
