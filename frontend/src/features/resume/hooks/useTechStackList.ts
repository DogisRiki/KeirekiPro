import { getTechStackList } from "@/features/resume";
import { useErrorMessageStore } from "@/stores";
import { TechStack } from "@/types";
import { useQuery, UseQueryResult } from "@tanstack/react-query";

/**
 * 技術スタック一覧を取得フック
 * @returns 技術スタック一覧取得クエリ
 */
export const useTechStackList = (): UseQueryResult<TechStack, unknown> => {
    const { clearErrors } = useErrorMessageStore();

    return useQuery({
        queryKey: ["getTechStackList"],
        queryFn: async () => {
            clearErrors();
            return await getTechStackList();
        },
        retry: false,
        staleTime: Infinity, // 常にfresh扱い
        gcTime: Infinity, // キャッシュを破棄しない
        refetchOnMount: false,
        refetchOnReconnect: false,
        refetchOnWindowFocus: false,
    });
};
