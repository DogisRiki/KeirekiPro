import { protectedApiClient } from "@/lib";
import { useErrorMessageStore } from "@/stores";
import { User } from "@/types";
import { useQuery, UseQueryResult } from "@tanstack/react-query";

/**
 * ユーザー情報取得API
 */
export const getUserInfo = async (): Promise<User> => {
    const response = await protectedApiClient.get<User>("/users/me");
    return response.data;
};

/**
 * ユーザー情報取得フック
 */
export const useGetUserInfo = (): UseQueryResult<User, unknown> => {
    const { clearErrors } = useErrorMessageStore();

    return useQuery({
        queryKey: ["getUserInfo"],
        queryFn: async () => {
            clearErrors();
            return await getUserInfo();
        },
        retry: false,
    });
};
