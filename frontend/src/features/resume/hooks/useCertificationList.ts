import type { CertificationListResponse } from "@/features/resume";
import { getCertificationList } from "@/features/resume";
import { useErrorMessageStore } from "@/stores";
import type { UseQueryResult } from "@tanstack/react-query";
import { useQuery } from "@tanstack/react-query";

/**
 * 資格一覧取得フック
 * @returns 資格一覧取得クエリ
 */
export const useCertificationList = (): UseQueryResult<CertificationListResponse, unknown> => {
    const { clearErrors } = useErrorMessageStore();

    return useQuery({
        queryKey: ["getCertificationList"],
        queryFn: async () => {
            clearErrors();
            return await getCertificationList();
        },
        retry: false,
        staleTime: Infinity,
        gcTime: Infinity,
        refetchOnMount: false,
        refetchOnReconnect: false,
        refetchOnWindowFocus: false,
    });
};
