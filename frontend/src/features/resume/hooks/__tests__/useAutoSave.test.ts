import { vi } from "vitest";

// useDebouncedCallbackのモック
const mockCancel = vi.fn();
const mockDebouncedFn = Object.assign(vi.fn(), { cancel: mockCancel });
vi.mock("use-debounce", () => ({
    useDebouncedCallback: (callback: () => void) => {
        mockDebouncedFn.mockImplementation(callback);
        return mockDebouncedFn;
    },
}));

import type { Resume } from "@/features/resume";
import { useAutoSave, useResumeStore } from "@/features/resume/";
import { renderHook } from "@testing-library/react";

describe("useAutoSave", () => {
    const mockResume: Resume = {
        id: "resume-1",
        resumeName: "テスト職務経歴書",
        date: "2024-01-01",
        lastName: "山田",
        firstName: "太郎",
        createdAt: "2024-01-01T00:00:00.000Z",
        updatedAt: "2024-01-01T00:00:00.000Z",
        careers: [
            {
                id: "career-1",
                companyName: "株式会社テスト",
                startDate: "2020-04",
                endDate: null,
                active: true,
            },
        ],
        projects: [],
        certifications: [],
        portfolios: [],
        socialLinks: [],
        selfPromotions: [],
    };

    const createMockMutation = (isPending = false) => ({
        mutate: vi.fn(),
        isPending,
    });

    beforeEach(() => {
        useResumeStore.getState().clearResume();
        mockDebouncedFn.mockClear();
        mockCancel.mockClear();
    });

    it("enabledがtrueでisDirtyがtrueのとき、debouncedSaveが呼ばれること", () => {
        useResumeStore.getState().setResume(mockResume);
        useResumeStore.getState().setDirty(true);

        renderHook(() =>
            useAutoSave({
                enabled: true,
                resumeId: "resume-1",
                updateBasicMutation: createMockMutation(),
                updateCareersMutation: createMockMutation(),
                updateProjectsMutation: createMockMutation(),
                updateCertificationsMutation: createMockMutation(),
                updatePortfoliosMutation: createMockMutation(),
                updateSocialLinksMutation: createMockMutation(),
                updateSelfPromotionsMutation: createMockMutation(),
            }),
        );

        expect(mockDebouncedFn).toHaveBeenCalled();
    });

    it("enabledがfalseのとき、debouncedSave.cancelが呼ばれること", () => {
        renderHook(() =>
            useAutoSave({
                enabled: false,
                resumeId: "resume-1",
                updateBasicMutation: createMockMutation(),
                updateCareersMutation: createMockMutation(),
                updateProjectsMutation: createMockMutation(),
                updateCertificationsMutation: createMockMutation(),
                updatePortfoliosMutation: createMockMutation(),
                updateSocialLinksMutation: createMockMutation(),
                updateSelfPromotionsMutation: createMockMutation(),
            }),
        );

        expect(mockCancel).toHaveBeenCalled();
    });

    it("isDirtyがfalseのとき、debouncedSaveが呼ばれないこと", () => {
        useResumeStore.getState().setResume(mockResume);
        useResumeStore.getState().setDirty(false);

        renderHook(() =>
            useAutoSave({
                enabled: true,
                resumeId: "resume-1",
                updateBasicMutation: createMockMutation(),
                updateCareersMutation: createMockMutation(),
                updateProjectsMutation: createMockMutation(),
                updateCertificationsMutation: createMockMutation(),
                updatePortfoliosMutation: createMockMutation(),
                updateSocialLinksMutation: createMockMutation(),
                updateSelfPromotionsMutation: createMockMutation(),
            }),
        );

        // isDirtyがfalseなのでdebouncedFnは呼ばれない
        expect(mockDebouncedFn).not.toHaveBeenCalled();
    });
});
