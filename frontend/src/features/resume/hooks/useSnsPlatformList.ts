import type { SnsPlatformListResponse } from "@/features/resume";
import { getSnsPlatformList } from "@/features/resume";
import { useErrorMessageStore } from "@/stores";
import type { UseQueryResult } from "@tanstack/react-query";
import { useQuery } from "@tanstack/react-query";

/**
 * SNSプラットフォーム一覧取得フック
 * @returns SNSプラットフォーム一覧取得クエリ
 */
export const useSnsPlatformList = (): UseQueryResult<SnsPlatformListResponse, unknown> => {
    const { clearErrors } = useErrorMessageStore();

    return useQuery({
        queryKey: ["getSnsPlatformList"],
        queryFn: async () => {
            clearErrors();
            return await getSnsPlatformList();
        },
        retry: false,
        staleTime: Infinity,
        gcTime: Infinity,
        refetchOnMount: false,
        refetchOnReconnect: false,
        refetchOnWindowFocus: false,
    });
};
