import { vi } from "vitest";

vi.mock("@/lib", () => ({
    protectedApiClient: { put: vi.fn() },
}));

import type { Resume } from "@/features/resume";
import { useResumeStore, useUpdatePortfolios } from "@/features/resume";
import { protectedApiClient } from "@/lib";
import { useErrorMessageStore, useNotificationStore } from "@/stores";
import { createQueryWrapper, resetStoresAndMocks } from "@/test";
import { act, renderHook, waitFor } from "@testing-library/react";
import type { AxiosResponse } from "axios";

describe("useUpdatePortfolios", () => {
    const wrapper = createQueryWrapper();

    const mockResume: Resume = {
        id: "resume-1",
        resumeName: "テスト職務経歴書",
        date: "2024-01-01",
        lastName: "山田",
        firstName: "太郎",
        createdAt: "2024-01-01T00:00:00.000Z",
        updatedAt: "2024-01-02T00:00:00.000Z",
        careers: [],
        projects: [],
        certifications: [],
        portfolios: [
            {
                id: "portfolio-1",
                name: "個人ブログ",
                overview: "技術ブログ",
                techStack: "Next.js",
                link: "https://example.com",
            },
        ],
        socialLinks: [],
        selfPromotions: [],
    };

    beforeEach(() => {
        resetStoresAndMocks([]);
        useResumeStore.getState().clearResume();
        useResumeStore.getState().setResume(mockResume);
        vi.mocked(protectedApiClient.put).mockReset();
        vi.spyOn(useErrorMessageStore.getState(), "clearErrors");
        vi.spyOn(useNotificationStore.getState(), "setNotification");
        vi.spyOn(useResumeStore.getState(), "updateResume");
        vi.spyOn(useResumeStore.getState(), "setDirty");
        vi.spyOn(useResumeStore.getState(), "clearDirtyEntryIds");
    });

    it("成功時はエラーストアをクリアし、ストア更新と成功通知が実行されること", async () => {
        const mockResponse = { status: 200, data: mockResume } as AxiosResponse<Resume>;
        vi.mocked(protectedApiClient.put).mockResolvedValueOnce(mockResponse);

        const { result } = renderHook(() => useUpdatePortfolios("resume-1"), { wrapper });

        act(() => {
            result.current.mutate({
                portfolios: [
                    {
                        id: null,
                        name: "個人ブログ",
                        overview: "技術ブログ",
                        techStack: "Next.js",
                        link: "https://example.com",
                    },
                ],
            });
        });

        await waitFor(() => expect(result.current.isSuccess).toBe(true));

        expect(useErrorMessageStore.getState().clearErrors).toHaveBeenCalledTimes(2);
        expect(useResumeStore.getState().updateResume).toHaveBeenCalledWith({
            portfolios: mockResume.portfolios,
            updatedAt: mockResume.updatedAt,
        });
        expect(useResumeStore.getState().clearDirtyEntryIds).toHaveBeenCalledWith(["portfolio-1"]);
        expect(useResumeStore.getState().setDirty).toHaveBeenCalledWith(false);
        expect(useNotificationStore.getState().setNotification).toHaveBeenCalledWith(
            "ポートフォリオ情報を保存しました。",
            "success",
        );
    });
});
