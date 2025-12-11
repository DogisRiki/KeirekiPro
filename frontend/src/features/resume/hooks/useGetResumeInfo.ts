import type { Resume } from "@/features/resume";
import { getResumeInfo, useResumeStore } from "@/features/resume";
import { useErrorMessageStore } from "@/stores";
import type { UseQueryResult } from "@tanstack/react-query";
import { useQuery } from "@tanstack/react-query";

/**
 * 職務経歴書詳細情報取得フック
 * @param resumeId 職務経歴書ID
 * @returns 職務経歴書詳細情報取得クエリ
 */
export const useGetResumeInfo = (resumeId: string): UseQueryResult<Resume, unknown> => {
    const { clearErrors } = useErrorMessageStore();
    const { initializeResume } = useResumeStore();

    return useQuery({
        queryKey: ["getResumeInfo", resumeId],
        queryFn: async () => {
            clearErrors();
            const data = await getResumeInfo(resumeId);
            initializeResume(data);
            return data;
        },
        retry: false,
        staleTime: 0,
        refetchOnMount: "always",
        enabled: !!resumeId,
    });
};
