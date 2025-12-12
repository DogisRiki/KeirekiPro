import { vi } from "vitest";

vi.mock("@/lib", () => ({
    protectedApiClient: { put: vi.fn() },
}));

import type { Project, Resume } from "@/features/resume";
import { useResumeStore, useUpdateProjects } from "@/features/resume";
import { protectedApiClient } from "@/lib";
import { useErrorMessageStore, useNotificationStore } from "@/stores";
import { createQueryWrapper, resetStoresAndMocks } from "@/test";
import { act, renderHook, waitFor } from "@testing-library/react";
import type { AxiosResponse } from "axios";

describe("useUpdateProjects", () => {
    const wrapper = createQueryWrapper();

    const mockProject: Project = {
        id: "project-1",
        companyName: "株式会社テスト",
        startDate: "2020-04-01",
        endDate: null,
        active: true,
        name: "テストプロジェクト",
        overview: "概要",
        teamComp: "5名",
        role: "エンジニア",
        achievement: "成果",
        process: {
            requirements: true,
            basicDesign: true,
            detailedDesign: true,
            implementation: true,
            integrationTest: true,
            systemTest: false,
            maintenance: false,
        },
        techStack: {
            frontend: {
                languages: [],
                frameworks: [],
                libraries: [],
                buildTools: [],
                packageManagers: [],
                linters: [],
                formatters: [],
                testingTools: [],
            },
            backend: {
                languages: [],
                frameworks: [],
                libraries: [],
                buildTools: [],
                packageManagers: [],
                linters: [],
                formatters: [],
                testingTools: [],
                ormTools: [],
                auth: [],
            },
            infrastructure: {
                clouds: [],
                operatingSystems: [],
                containers: [],
                databases: [],
                webServers: [],
                ciCdTools: [],
                iacTools: [],
                monitoringTools: [],
                loggingTools: [],
            },
            tools: {
                sourceControls: [],
                projectManagements: [],
                communicationTools: [],
                documentationTools: [],
                apiDevelopmentTools: [],
                designTools: [],
                editors: [],
                developmentEnvironments: [],
            },
        },
    };

    const mockResume: Resume = {
        id: "resume-1",
        resumeName: "テスト職務経歴書",
        date: "2024-01-01",
        lastName: "山田",
        firstName: "太郎",
        createdAt: "2024-01-01T00:00:00.000Z",
        updatedAt: "2024-01-02T00:00:00.000Z",
        careers: [],
        projects: [mockProject],
        certifications: [],
        portfolios: [],
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

        const { result } = renderHook(() => useUpdateProjects("resume-1"), { wrapper });

        act(() => {
            result.current.mutate({ projects: [] });
        });

        await waitFor(() => expect(result.current.isSuccess).toBe(true));

        expect(useErrorMessageStore.getState().clearErrors).toHaveBeenCalledTimes(2);
        expect(useResumeStore.getState().updateResume).toHaveBeenCalledWith({
            projects: mockResume.projects,
            updatedAt: mockResume.updatedAt,
        });
        expect(useResumeStore.getState().clearDirtyEntryIds).toHaveBeenCalledWith(["project-1"]);
        expect(useResumeStore.getState().setDirty).toHaveBeenCalledWith(false);
        expect(useNotificationStore.getState().setNotification).toHaveBeenCalledWith(
            "プロジェクト情報を保存しました。",
            "success",
        );
    });
});
