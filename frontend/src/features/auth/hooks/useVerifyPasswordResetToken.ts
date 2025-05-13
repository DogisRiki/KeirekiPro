import { verifyPasswordResetToken } from "@/features/auth";
import { useQuery, UseQueryResult } from "@tanstack/react-query";

/**
 * パスワードリセットトークン検証フック
 */
export const useVerifyPasswordResetToken = (token: string): UseQueryResult<void, unknown> => {
    return useQuery({
        queryKey: ["verifyPasswordResetToken", token],
        queryFn: () => verifyPasswordResetToken({ token }),
        enabled: !!token,
        retry: false,
    });
};
