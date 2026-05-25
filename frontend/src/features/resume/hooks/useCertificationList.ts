import type { CertificationListResponse } from "@/features/resume";
import { getCertificationList } from "@/features/resume";
import type { UseQueryResult } from "@tanstack/react-query";
import { useQuery } from "@tanstack/react-query";

/**
 * 資格一覧取得フック
 * @returns 資格一覧取得クエリ
 */
export const useCertificationList = (): UseQueryResult<CertificationListResponse, unknown> => {
    return useQuery({
        queryKey: ["getCertificationList"],
        queryFn: getCertificationList,
        retry: false,
        staleTime: Infinity,
        gcTime: Infinity,
        refetchOnMount: false,
        refetchOnReconnect: false,
        refetchOnWindowFocus: false,
    });
};
