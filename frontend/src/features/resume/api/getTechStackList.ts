import type { TechStack } from "@/features/resume";
import { protectedApiClient } from "@/lib";

/**
 * 技術スタック一覧取得API
 * @returns
 */
export const getTechStackList = async (): Promise<TechStack> => {
    const response = await protectedApiClient.get<TechStack>("/tech-stacks");
    return response.data;
};
