import { vi } from "vitest";

// use-debounceのモック
const mockCancel = vi.fn();
const mockDebouncedFn = Object.assign(vi.fn(), { cancel: mockCancel });

vi.mock("use-debounce", () => ({
    useDebouncedCallback: (callback: () => void) => {
        mockDebouncedFn.mockImplementation(callback);
        return mockDebouncedFn;
    },
}));

import type { Resume } from "@/features/resume";
import { TEMP_ID_PREFIX, useAutoSave, useResumeStore } from "@/features/resume/";
import { renderHook, waitFor } from "@testing-library/react";

describe("useAutoSave", () => {
    const baseResume: Resume = {
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

    const buildOptions = (overrides?: Partial<Parameters<typeof useAutoSave>[0]>) => {
        const options = {
            enabled: true,
            resumeId: "resume-1",
            updateBasicMutation: createMockMutation(),
            createCareerMutation: createMockMutation(),
            updateCareerMutation: createMockMutation(),
            createProjectMutation: createMockMutation(),
            updateProjectMutation: createMockMutation(),
            createCertificationMutation: createMockMutation(),
            updateCertificationMutation: createMockMutation(),
            createPortfolioMutation: createMockMutation(),
            updatePortfolioMutation: createMockMutation(),
            createSocialLinkMutation: createMockMutation(),
            updateSocialLinkMutation: createMockMutation(),
            createSelfPromotionMutation: createMockMutation(),
            updateSelfPromotionMutation: createMockMutation(),
        } as const;

        return { ...options, ...overrides };
    };

    beforeEach(() => {
        useResumeStore.getState().clearResume();
        mockDebouncedFn.mockClear();
        mockCancel.mockClear();
    });

    it("enabledがtrueでisDirtyがtrueのとき、debouncedSaveが呼ばれ、basicInfoの場合はupdateBasicMutationが呼ばれること", async () => {
        useResumeStore.getState().setResume(baseResume);
        useResumeStore.getState().setDirty(true); // activeSectionは初期値でbasicInfo

        const opts = buildOptions();

        renderHook(() => useAutoSave(opts));

        await waitFor(() => {
            expect(mockDebouncedFn).toHaveBeenCalled();
        });

        await waitFor(() => {
            expect(opts.updateBasicMutation.mutate).toHaveBeenCalledTimes(1);
        });

        expect(opts.updateBasicMutation.mutate).toHaveBeenCalledWith({
            resumeName: "テスト職務経歴書",
            date: "2024-01-01",
            lastName: "山田",
            firstName: "太郎",
        });

        expect(opts.createCareerMutation.mutate).not.toHaveBeenCalled();
        expect(opts.updateCareerMutation.mutate).not.toHaveBeenCalled();
    });

    it("enabledがfalseのとき、debouncedSave.cancelが呼ばれること", async () => {
        const opts = buildOptions({ enabled: false });

        renderHook(() => useAutoSave(opts));

        await waitFor(() => {
            expect(mockCancel).toHaveBeenCalledTimes(1);
        });
    });

    it("isDirtyがfalseのとき、debouncedSaveが呼ばれないこと", async () => {
        useResumeStore.getState().setResume(baseResume);
        useResumeStore.getState().setDirty(false);

        const opts = buildOptions({ enabled: true });

        renderHook(() => useAutoSave(opts));

        // useEffectが走っても条件に合わないため呼ばれない
        await waitFor(() => {
            expect(mockDebouncedFn).not.toHaveBeenCalled();
        });
    });

    it("careerセクションでactiveEntryIdがdirtyの場合、既存IDならupdateCareerMutationが呼ばれること", async () => {
        useResumeStore.getState().setResume(baseResume);
        useResumeStore.getState().setActiveSection("career");
        useResumeStore.getState().setActiveEntryId("career-1");
        useResumeStore.getState().addDirtyEntryId("career-1");
        useResumeStore.getState().setDirty(true);

        const opts = buildOptions();

        renderHook(() => useAutoSave(opts));

        await waitFor(() => {
            expect(opts.updateCareerMutation.mutate).toHaveBeenCalledTimes(1);
        });

        expect(opts.updateCareerMutation.mutate).toHaveBeenCalledWith({
            careerId: "career-1",
            payload: {
                companyName: "株式会社テスト",
                startDate: "2020-04",
                endDate: null,
                isActive: true,
            },
        });

        expect(opts.createCareerMutation.mutate).not.toHaveBeenCalled();
    });

    it("careerセクションでactiveEntryIdがdirtyの場合、一時IDならcreateCareerMutationが呼ばれること", async () => {
        const tempCareerId = `${TEMP_ID_PREFIX}career-temp-1`;
        const resume: Resume = {
            ...baseResume,
            careers: [
                {
                    id: tempCareerId,
                    companyName: "株式会社新規",
                    startDate: "2024-01",
                    endDate: null,
                    active: true,
                },
            ],
        };

        useResumeStore.getState().setResume(resume);
        useResumeStore.getState().setActiveSection("career");
        useResumeStore.getState().setActiveEntryId(tempCareerId);
        useResumeStore.getState().addDirtyEntryId(tempCareerId);
        useResumeStore.getState().setDirty(true);

        const opts = buildOptions();

        renderHook(() => useAutoSave(opts));

        await waitFor(() => {
            expect(opts.createCareerMutation.mutate).toHaveBeenCalledTimes(1);
        });

        expect(opts.createCareerMutation.mutate).toHaveBeenCalledWith({
            tempId: tempCareerId,
            payload: {
                companyName: "株式会社新規",
                startDate: "2024-01",
                endDate: null,
                isActive: true,
            },
        });

        expect(opts.updateCareerMutation.mutate).not.toHaveBeenCalled();
    });

    it("listセクションでactiveEntryIdが未設定、またはdirtyでない場合は保存ミューテーションが呼ばれないこと", async () => {
        useResumeStore.getState().setResume(baseResume);
        useResumeStore.getState().setActiveSection("career");
        useResumeStore.getState().setActiveEntryId("career-1");
        // dirtyEntryIdsに入れない
        useResumeStore.getState().setDirty(true);

        const opts = buildOptions();

        renderHook(() => useAutoSave(opts));

        await waitFor(() => {
            expect(mockDebouncedFn).toHaveBeenCalled();
        });

        expect(opts.createCareerMutation.mutate).not.toHaveBeenCalled();
        expect(opts.updateCareerMutation.mutate).not.toHaveBeenCalled();
    });

    it("いずれかのミューテーションがisPendingの場合は保存処理がスキップされること", async () => {
        useResumeStore.getState().setResume(baseResume);
        useResumeStore.getState().setActiveSection("career");
        useResumeStore.getState().setActiveEntryId("career-1");
        useResumeStore.getState().addDirtyEntryId("career-1");
        useResumeStore.getState().setDirty(true);

        const opts = buildOptions({
            updateCareerMutation: createMockMutation(true), // pending
        });

        renderHook(() => useAutoSave(opts));

        await waitFor(() => {
            expect(mockDebouncedFn).toHaveBeenCalled();
        });

        expect(opts.updateCareerMutation.mutate).not.toHaveBeenCalled();
        expect(opts.createCareerMutation.mutate).not.toHaveBeenCalled();
    });
});
