import type { GetResumeListResponse } from "@/features/resume";
import { getResumeList } from "@/features/resume";
import type { UseQueryResult } from "@tanstack/react-query";
import { useQuery } from "@tanstack/react-query";

/**
 * 職務経歴書一覧取得フック
 * @returns 職務経歴書一覧取得クエリ
 */
export const useGetResumeList = (): UseQueryResult<GetResumeListResponse, unknown> => {
    return useQuery({
        queryKey: ["getResumeList"],
        queryFn: getResumeList,
        retry: false,
        staleTime: 60_000, // 1分間キャッシュ
        refetchOnMount: "always", // マウントのたびにフェッチする
    });
};
