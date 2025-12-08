import { verifyPasswordResetToken } from "@/features/auth";
import { useErrorMessageStore } from "@/stores";
import type { UseQueryResult } from "@tanstack/react-query";
import { useQuery } from "@tanstack/react-query";
import type { AxiosError, AxiosResponse } from "axios";

/**
 * パスワードリセットトークン検証フック
 * @param token 検証するトークン
 * @returns パスワードリセットトークン検証クエリ結果
 */
export const useVerifyPasswordResetToken = (token: string): UseQueryResult<AxiosResponse<void>, AxiosError> => {
    const { clearErrors } = useErrorMessageStore();

    return useQuery<AxiosResponse<void>, AxiosError>({
        queryKey: ["verifyPasswordResetToken", token],
        queryFn: async () => {
            clearErrors();
            return await verifyPasswordResetToken({ token });
        },
        enabled: !!token,
        retry: false,
    });
};
