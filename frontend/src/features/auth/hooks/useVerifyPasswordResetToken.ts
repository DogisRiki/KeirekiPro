import { verifyPasswordResetToken } from "@/features/auth";
import { useErrorMessageStore } from "@/stores";
import { useQuery, UseQueryResult } from "@tanstack/react-query";

/**
 * パスワードリセットトークン検証フック
 */
export const useVerifyPasswordResetToken = (token: string): UseQueryResult<void, unknown> => {
    const { clearErrors } = useErrorMessageStore();

    return useQuery<void, unknown>({
        queryKey: ["verifyPasswordResetToken", token],
        queryFn: async () => {
            clearErrors();
            await verifyPasswordResetToken({ token });
        },
        enabled: !!token,
        retry: false,
    });
};
