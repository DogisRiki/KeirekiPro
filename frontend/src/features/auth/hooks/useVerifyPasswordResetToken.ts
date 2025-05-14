import { verifyPasswordResetToken } from "@/features/auth";
import { useErrorMessageStore } from "@/stores";
import { useQuery, UseQueryResult } from "@tanstack/react-query";
import { AxiosError } from "axios";

/**
 * パスワードリセットトークン検証フック
 * @param token 検証するトークン
 * @returns パスワードリセットトークン検証クエリ結果
 */
export const useVerifyPasswordResetToken = (token: string): UseQueryResult<void, AxiosError> => {
    const { clearErrors } = useErrorMessageStore();

    return useQuery<void, AxiosError>({
        queryKey: ["verifyPasswordResetToken", token],
        queryFn: async () => {
            clearErrors();
            await verifyPasswordResetToken({ token });
        },
        enabled: !!token,
        retry: false,
    });
};
