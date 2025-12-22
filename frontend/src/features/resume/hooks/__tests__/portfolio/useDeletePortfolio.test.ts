import { vi } from "vitest";

vi.mock("@/lib", () => ({
    protectedApiClient: { post: vi.fn(), put: vi.fn(), delete: vi.fn() },
}));

import type { Resume } from "@/features/resume";
import { useDeletePortfolio, useResumeStore } from "@/features/resume";
import { protectedApiClient } from "@/lib";
import { useErrorMessageStore, useNotificationStore } from "@/stores";
import { createQueryWrapper, resetStoresAndMocks } from "@/test";
import { act, renderHook, waitFor } from "@testing-library/react";
import type { AxiosResponse } from "axios";

describe("useDeletePortfolio", () => {
    const wrapper = createQueryWrapper();

    const localResume: Resume = {
        id: "resume-1",
        resumeName: "テスト職務経歴書",
        date: "2024-01-01",
        lastName: "山田",
        firstName: "太郎",
        createdAt: "2024-01-01T00:00:00.000Z",
        updatedAt: "2024-01-01T00:00:00.000Z",
        careers: [],
        projects: [],
        certifications: [],
        portfolios: [
            {
                id: "portfolio-1",
                name: "削除対象",
                overview: "削除対象の概要",
                techStack: "React",
                link: "https://example.com/delete",
            },
            {
                id: "portfolio-2",
                name: "残るポートフォリオ",
                overview: "残る概要",
                techStack: "Next.js",
                link: "https://example.com/keep",
            },
        ],
        snsPlatforms: [],
        selfPromotions: [],
    };

    beforeEach(() => {
        resetStoresAndMocks([]);
        useResumeStore.getState().clearResume();
        vi.mocked(protectedApiClient.delete).mockReset();

        vi.spyOn(useErrorMessageStore.getState(), "clearErrors");
        vi.spyOn(useNotificationStore.getState(), "setNotification");

        vi.spyOn(useResumeStore.getState(), "updateResume");
        vi.spyOn(useResumeStore.getState(), "setDirty");
        vi.spyOn(useResumeStore.getState(), "removeDirtyEntryId");
        vi.spyOn(useResumeStore.getState(), "setActiveEntryId");
    });

    it("成功時はエラーストアをクリアし、portfolio削除・dirty解除・通知が実行されること", async () => {
        const portfolioId = "portfolio-1";

        // useDeletePortfolioはuseResumeStore()を参照するため、render前に状態を入れておく
        useResumeStore.getState().setResume(localResume);
        useResumeStore.getState().setActiveSection("portfolio");
        useResumeStore.getState().setActiveEntryId(portfolioId);
        useResumeStore.getState().addDirtyEntryId(portfolioId);

        const mockResponse = { status: 200, data: undefined } as AxiosResponse<void>;
        vi.mocked(protectedApiClient.delete).mockResolvedValueOnce(mockResponse);

        const { result } = renderHook(() => useDeletePortfolio("resume-1"), { wrapper });

        act(() => {
            result.current.mutate(portfolioId);
        });

        await waitFor(() => expect(result.current.isSuccess).toBe(true));

        expect(useErrorMessageStore.getState().clearErrors).toHaveBeenCalledTimes(2);
        expect(useResumeStore.getState().updateResume).toHaveBeenCalledWith({
            portfolios: [localResume.portfolios.find((p) => p.id === "portfolio-2")!],
        });
        expect(useResumeStore.getState().removeDirtyEntryId).toHaveBeenCalledWith(portfolioId);
        expect(useResumeStore.getState().setActiveEntryId).toHaveBeenCalledWith(null);
        expect(useResumeStore.getState().setDirty).toHaveBeenCalledWith(false);
        expect(useNotificationStore.getState().setNotification).toHaveBeenCalledWith(
            "ポートフォリオを削除しました。",
            "success",
        );
    });
});
