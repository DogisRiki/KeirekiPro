import { vi } from "vitest";

vi.mock("@/lib", () => ({
    protectedApiClient: { get: vi.fn() },
}));

import type { Resume } from "@/features/resume";
import { useGetResumeInfo, useResumeStore } from "@/features/resume";
import { protectedApiClient } from "@/lib";
import { useErrorMessageStore } from "@/stores";
import { createQueryWrapper, resetStoresAndMocks } from "@/test";
import { renderHook, waitFor } from "@testing-library/react";
import type { AxiosResponse } from "axios";

describe("useGetResumeInfo", () => {
    const wrapper = createQueryWrapper();

    const mockResume: Resume = {
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
        portfolios: [],
        snsPlatforms: [],
        selfPromotions: [],
    };

    beforeEach(() => {
        resetStoresAndMocks([]);
        useResumeStore.getState().clearResume();
        vi.mocked(protectedApiClient.get).mockReset();
        vi.spyOn(useErrorMessageStore.getState(), "clearErrors");
        vi.spyOn(useResumeStore.getState(), "initializeResume");
    });

    it("成功時はエラーストアをクリアし、initializeResumeが呼ばれること", async () => {
        const mockResponse = { status: 200, data: mockResume } as AxiosResponse<Resume>;
        vi.mocked(protectedApiClient.get).mockResolvedValueOnce(mockResponse);

        const { result } = renderHook(() => useGetResumeInfo("resume-1"), { wrapper });

        await waitFor(() => expect(result.current.isSuccess).toBe(true));

        expect(useErrorMessageStore.getState().clearErrors).toHaveBeenCalled();
        expect(useResumeStore.getState().initializeResume).toHaveBeenCalledWith(mockResume);
        expect(result.current.data).toEqual(mockResume);
    });

    it("resumeIdが空文字の場合はクエリが実行されないこと", async () => {
        const { result } = renderHook(() => useGetResumeInfo(""), { wrapper });

        await waitFor(() => expect(result.current.isFetching).toBe(false));

        expect(protectedApiClient.get).not.toHaveBeenCalled();
    });
});
