import { paths } from "@/config/paths";
import { useTwoFactorStore, verifyTwoFactor } from "@/features/auth";
import { getUserInfo } from "@/hooks";
import { useErrorMessageStore, useUserAuthStore } from "@/stores";
import { useMutation } from "@tanstack/react-query";
import { useNavigate } from "react-router";

/**
 * 二段階認証コード検証フック
 */
export const useVerifyTwoFactor = () => {
    const navigate = useNavigate();
    const { setLogin } = useUserAuthStore();
    const { userId, clear } = useTwoFactorStore();
    const { clearErrors } = useErrorMessageStore();

    return useMutation({
        mutationFn: (code: string) => verifyTwoFactor({ userId: userId as string, code }),
        onSuccess: async () => {
            clearErrors();
            clear();
            const data = await getUserInfo();
            setLogin(data);
            navigate(paths.resume.list, { replace: true });
        },
    });
};
