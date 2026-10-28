import type { VerifyEmailResponse } from "@/features/auth";
import { verifyEmail } from "@/features/auth";
import { useErrorMessageStore } from "@/stores";
import type { UseQueryResult } from "@tanstack/react-query";
import { useQuery } from "@tanstack/react-query";
import type { AxiosError } from "axios";

/**
 * 確認のリンクの受け付けフック
 * 確認のリンクは1回だけ使えるため、同じトークンでは画面を出し直しても API を呼び直さない
 * @param token 確認のリンクのトークン
 * @returns 確認のリンクの受け付けクエリ結果
 */
export const useVerifyEmail = (token: string): UseQueryResult<VerifyEmailResponse, AxiosError> => {
    const { clearErrors } = useErrorMessageStore();

    return useQuery<VerifyEmailResponse, AxiosError>({
        queryKey: ["verifyEmail", token],
        queryFn: async () => {
            clearErrors();
            const response = await verifyEmail({ token });
            return response.data;
        },
        enabled: !!token,
        retry: false,
        staleTime: Infinity,
        gcTime: Infinity,
    });
};
