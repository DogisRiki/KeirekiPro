import { vi } from "vitest";

vi.mock("@/lib", () => ({
    protectedApiClient: { post: vi.fn(), put: vi.fn(), delete: vi.fn() },
}));

import type { Resume } from "@/features/resume";
import { useDeleteProject, useResumeStore } from "@/features/resume";
import { protectedApiClient } from "@/lib";
import { useErrorMessageStore, useNotificationStore } from "@/stores";
import { createQueryWrapper, resetStoresAndMocks } from "@/test";
import { act, renderHook, waitFor } from "@testing-library/react";
import type { AxiosResponse } from "axios";

describe("useDeleteProject", () => {
    const wrapper = createQueryWrapper();

    const baseProject = {
        companyName: "株式会社テスト",
        startDate: "2024-01",
        endDate: null as string | null,
        active: true,
        name: "プロジェクトA",
        overview: "概要",
        teamComp: "3名",
        role: "SE",
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
                languages: ["TypeScript"],
                frameworks: ["React"],
                libraries: ["Redux"],
                buildTools: ["Vite"],
                packageManagers: ["pnpm"],
                linters: ["ESLint"],
                formatters: ["Prettier"],
                testingTools: ["Vitest"],
            },
            backend: {
                languages: ["TypeScript"],
                frameworks: ["NestJS"],
                libraries: ["Prisma"],
                buildTools: ["tsc"],
                packageManagers: ["pnpm"],
                linters: ["ESLint"],
                formatters: ["Prettier"],
                testingTools: ["Jest"],
                ormTools: ["Prisma"],
                auth: ["JWT"],
            },
            infrastructure: {
                clouds: ["AWS"],
                operatingSystems: ["Linux"],
                containers: ["Docker"],
                databases: ["PostgreSQL"],
                webServers: ["Nginx"],
                ciCdTools: ["GitHub Actions"],
                iacTools: ["Terraform"],
                monitoringTools: ["CloudWatch"],
                loggingTools: ["CloudWatch Logs"],
            },
            tools: {
                sourceControls: ["GitHub"],
                projectManagements: ["Jira"],
                communicationTools: ["Slack"],
                documentationTools: ["Confluence"],
                apiDevelopmentTools: ["Postman"],
                designTools: ["Figma"],
                editors: ["VSCode"],
                developmentEnvironments: ["Docker Desktop"],
            },
        },
    };

    const localResume: Resume = {
        id: "resume-1",
        resumeName: "テスト職務経歴書",
        date: "2024-01-01",
        lastName: "山田",
        firstName: "太郎",
        createdAt: "2024-01-01T00:00:00.000Z",
        updatedAt: "2024-01-01T00:00:00.000Z",
        careers: [],
        projects: [
            { id: "project-1", ...baseProject, name: "削除対象" },
            { id: "project-2", ...baseProject, name: "残るプロジェクト" },
        ] as any,
        certifications: [],
        portfolios: [],
        socialLinks: [],
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

    it("成功時はエラーストアをクリアし、project削除・dirty解除・通知が実行されること", async () => {
        const projectId = "project-1";

        // useDeleteProjectはuseResumeStore()を参照するため、render前に状態を入れておく
        useResumeStore.getState().setResume(localResume);
        useResumeStore.getState().setActiveSection("project");
        useResumeStore.getState().setActiveEntryId(projectId);
        useResumeStore.getState().addDirtyEntryId(projectId);

        const mockResponse = { status: 200, data: undefined } as AxiosResponse<void>;
        vi.mocked(protectedApiClient.delete).mockResolvedValueOnce(mockResponse);

        const { result } = renderHook(() => useDeleteProject("resume-1"), { wrapper });

        act(() => {
            result.current.mutate(projectId);
        });

        await waitFor(() => expect(result.current.isSuccess).toBe(true));

        expect(useErrorMessageStore.getState().clearErrors).toHaveBeenCalledTimes(2);
        expect(useResumeStore.getState().updateResume).toHaveBeenCalledWith({
            projects: [localResume.projects.find((p: any) => p.id === "project-2")!],
        });
        expect(useResumeStore.getState().removeDirtyEntryId).toHaveBeenCalledWith(projectId);
        expect(useResumeStore.getState().setActiveEntryId).toHaveBeenCalledWith(null);
        expect(useResumeStore.getState().setDirty).toHaveBeenCalledWith(false);
        expect(useNotificationStore.getState().setNotification).toHaveBeenCalledWith(
            "プロジェクトを削除しました。",
            "success",
        );
    });
});
