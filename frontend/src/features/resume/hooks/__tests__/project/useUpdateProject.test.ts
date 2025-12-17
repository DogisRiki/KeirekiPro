import { vi } from "vitest";

vi.mock("@/lib", () => ({
    protectedApiClient: { post: vi.fn(), put: vi.fn(), delete: vi.fn() },
}));

import type { Resume } from "@/features/resume";
import { TEMP_ID_PREFIX, useResumeStore, useUpdateProject } from "@/features/resume";
import { protectedApiClient } from "@/lib";
import { useErrorMessageStore, useNotificationStore } from "@/stores";
import { createQueryWrapper, resetStoresAndMocks } from "@/test";
import { act, renderHook, waitFor } from "@testing-library/react";
import type { AxiosResponse } from "axios";

describe("useUpdateProject", () => {
    const wrapper = createQueryWrapper();

    const localOnlyTempId = `${TEMP_ID_PREFIX}project-temp-99`;

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
            {
                id: "project-1",
                ...baseProject,
                name: "ローカル（更新対象・dirty）",
                overview: "ローカル概要1",
            },
            {
                id: "project-3",
                ...baseProject,
                name: "ローカル（別dirty）",
                overview: "ローカル概要3",
            },
            {
                id: localOnlyTempId,
                ...baseProject,
                name: "ローカルのみ（temp）",
                overview: "ローカルのみ概要",
            },
        ] as any,
        certifications: [],
        portfolios: [],
        socialLinks: [],
        selfPromotions: [],
    };

    beforeEach(() => {
        resetStoresAndMocks([]);
        useResumeStore.getState().clearResume();
        vi.mocked(protectedApiClient.put).mockReset();

        vi.spyOn(useErrorMessageStore.getState(), "clearErrors");
        vi.spyOn(useNotificationStore.getState(), "setNotification");

        vi.spyOn(useResumeStore.getState(), "updateResumeFromServer");
        vi.spyOn(useResumeStore.getState(), "setDirty");
        vi.spyOn(useResumeStore.getState(), "removeDirtyEntryId");
    });

    it("成功時はprojectsをマージしてupdateResumeFromServerが呼ばれ、dirty解除・通知が実行されること", async () => {
        const projectId = "project-1";

        // store準備
        useResumeStore.getState().setResume(localResume);
        useResumeStore.getState().addDirtyEntryId(projectId);
        useResumeStore.getState().addDirtyEntryId("project-3");
        useResumeStore.getState().addDirtyEntryId(localOnlyTempId);

        const serverResume: Resume = {
            ...localResume,
            updatedAt: "2024-02-10T00:00:00.000Z",
            projects: [
                {
                    id: "project-1",
                    ...baseProject,
                    name: "サーバー（更新後）",
                    overview: "サーバー概要1",
                },
                {
                    id: "project-2",
                    ...baseProject,
                    name: "サーバー（別エントリー）",
                    overview: "サーバー概要2",
                },
                {
                    id: "project-3",
                    ...baseProject,
                    name: "サーバー（dirtyで上書きされる想定）",
                    overview: "サーバー概要3",
                },
            ] as any,
        };

        const mockResponse = { status: 200, data: serverResume } as AxiosResponse<Resume>;
        vi.mocked(protectedApiClient.put).mockResolvedValueOnce(mockResponse);

        const { result } = renderHook(() => useUpdateProject("resume-1"), { wrapper });

        act(() => {
            result.current.mutate({
                projectId,
                payload: {
                    companyName: baseProject.companyName,
                    startDate: baseProject.startDate,
                    endDate: baseProject.endDate,
                    isActive: baseProject.active,
                    name: localResume.projects.find((p: any) => p.id === projectId)!.name,
                    overview: localResume.projects.find((p: any) => p.id === projectId)!.overview,
                    teamComp: baseProject.teamComp,
                    role: baseProject.role,
                    achievement: baseProject.achievement,
                    requirements: baseProject.process.requirements,
                    basicDesign: baseProject.process.basicDesign,
                    detailedDesign: baseProject.process.detailedDesign,
                    implementation: baseProject.process.implementation,
                    integrationTest: baseProject.process.integrationTest,
                    systemTest: baseProject.process.systemTest,
                    maintenance: baseProject.process.maintenance,
                    frontendLanguages: baseProject.techStack.frontend.languages,
                    frontendFrameworks: baseProject.techStack.frontend.frameworks,
                    frontendLibraries: baseProject.techStack.frontend.libraries,
                    frontendBuildTools: baseProject.techStack.frontend.buildTools,
                    frontendPackageManagers: baseProject.techStack.frontend.packageManagers,
                    frontendLinters: baseProject.techStack.frontend.linters,
                    frontendFormatters: baseProject.techStack.frontend.formatters,
                    frontendTestingTools: baseProject.techStack.frontend.testingTools,
                    backendLanguages: baseProject.techStack.backend.languages,
                    backendFrameworks: baseProject.techStack.backend.frameworks,
                    backendLibraries: baseProject.techStack.backend.libraries,
                    backendBuildTools: baseProject.techStack.backend.buildTools,
                    backendPackageManagers: baseProject.techStack.backend.packageManagers,
                    backendLinters: baseProject.techStack.backend.linters,
                    backendFormatters: baseProject.techStack.backend.formatters,
                    backendTestingTools: baseProject.techStack.backend.testingTools,
                    ormTools: baseProject.techStack.backend.ormTools,
                    auth: baseProject.techStack.backend.auth,
                    clouds: baseProject.techStack.infrastructure.clouds,
                    operatingSystems: baseProject.techStack.infrastructure.operatingSystems,
                    containers: baseProject.techStack.infrastructure.containers,
                    databases: baseProject.techStack.infrastructure.databases,
                    webServers: baseProject.techStack.infrastructure.webServers,
                    ciCdTools: baseProject.techStack.infrastructure.ciCdTools,
                    iacTools: baseProject.techStack.infrastructure.iacTools,
                    monitoringTools: baseProject.techStack.infrastructure.monitoringTools,
                    loggingTools: baseProject.techStack.infrastructure.loggingTools,
                    sourceControls: baseProject.techStack.tools.sourceControls,
                    projectManagements: baseProject.techStack.tools.projectManagements,
                    communicationTools: baseProject.techStack.tools.communicationTools,
                    documentationTools: baseProject.techStack.tools.documentationTools,
                    apiDevelopmentTools: baseProject.techStack.tools.apiDevelopmentTools,
                    designTools: baseProject.techStack.tools.designTools,
                    editors: baseProject.techStack.tools.editors,
                    developmentEnvironments: baseProject.techStack.tools.developmentEnvironments,
                },
            });
        });

        await waitFor(() => expect(result.current.isSuccess).toBe(true));

        // マージ結果：
        // - ローカルのみのエントリー（temp）は先頭へ
        // - server projectsをベースにdirtyな project-3はローカルデータで上書き
        // - 更新対象（projectId=project-1）はローカル上書き対象から除外されるため、serverが優先
        const expectedProjects = [
            localResume.projects.find((p: any) => p.id === localOnlyTempId)!,
            serverResume.projects.find((p: any) => p.id === "project-1")!, // server優先
            serverResume.projects.find((p: any) => p.id === "project-2")!,
            localResume.projects.find((p: any) => p.id === "project-3")!, // dirtyなのでローカル優先
        ];

        expect(useErrorMessageStore.getState().clearErrors).toHaveBeenCalledTimes(2);
        expect(useResumeStore.getState().updateResumeFromServer).toHaveBeenCalledWith({
            projects: expectedProjects,
            updatedAt: serverResume.updatedAt,
        });
        expect(useResumeStore.getState().removeDirtyEntryId).toHaveBeenCalledWith(projectId);
        expect(useResumeStore.getState().setDirty).toHaveBeenCalledWith(false);
        expect(useNotificationStore.getState().setNotification).toHaveBeenCalledWith(
            "プロジェクトを更新しました。",
            "success",
        );
    });
});
