import { vi } from "vitest";

vi.mock("@/lib", () => ({
    protectedApiClient: { post: vi.fn(), put: vi.fn(), delete: vi.fn() },
}));

import type { Resume } from "@/features/resume";
import { TEMP_ID_PREFIX, useCreateProject, useResumeStore } from "@/features/resume";
import { protectedApiClient } from "@/lib";
import { useNotificationStore } from "@/stores";
import { createQueryWrapper, resetStoresAndMocks } from "@/test";
import type { ErrorResponse } from "@/types";
import { act, renderHook, waitFor } from "@testing-library/react";

describe("useCreateProject", () => {
    const wrapper = createQueryWrapper();

    const tempId = `${TEMP_ID_PREFIX}project-temp-1`;
    const localOnlyTempId = `${TEMP_ID_PREFIX}project-temp-2`;

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
            { id: tempId, ...baseProject },
            {
                id: "project-1",
                ...baseProject,
                name: "ローカル（dirty）プロジェクト",
                overview: "ローカル概要（dirty）",
            },
            {
                id: localOnlyTempId,
                ...baseProject,
                name: "ローカルのみ（temp）プロジェクト",
                overview: "ローカルのみ概要",
            },
        ] as any,
        certifications: [],
        portfolios: [],
        snsPlatforms: [],
        selfPromotions: [],
    };

    beforeEach(() => {
        resetStoresAndMocks([]);
        useResumeStore.getState().clearResume();
        vi.mocked(protectedApiClient.post).mockReset();
        vi.spyOn(useNotificationStore.getState(), "setNotification");
        vi.spyOn(useResumeStore.getState(), "updateResumeFromServer");
        vi.spyOn(useResumeStore.getState(), "setDirty");
        vi.spyOn(useResumeStore.getState(), "removeDirtyEntryId");
        vi.spyOn(useResumeStore.getState(), "setActiveEntryId");
        vi.spyOn(useResumeStore.getState(), "setEntryErrors");
        vi.spyOn(useResumeStore.getState(), "clearEntryErrors");
    });

    it("成功時はエントリエラーをクリアし、projectsをマージしてストア更新・activeEntryId更新・dirty解除・通知が実行されること", async () => {
        // store準備
        useResumeStore.getState().setResume(localResume);
        useResumeStore.getState().setActiveSection("project");
        useResumeStore.getState().setActiveEntryId(tempId);
        useResumeStore.getState().addDirtyEntryId(tempId);
        useResumeStore.getState().addDirtyEntryId("project-1"); // serverから返るIDをdirtyとして上書き対象にする

        const serverResume: Resume = {
            ...localResume,
            updatedAt: "2024-02-01T00:00:00.000Z",
            projects: [
                {
                    id: "project-1",
                    ...baseProject,
                    name: "サーバープロジェクト（上書きされる想定）",
                    overview: "サーバー概要",
                },
                {
                    id: "project-2",
                    ...baseProject,
                    name: "新規作成されたプロジェクト",
                    overview: "新規概要",
                },
            ] as any,
        };

        const mockResponse = { status: 201, data: serverResume };
        vi.mocked(protectedApiClient.post).mockResolvedValueOnce(mockResponse);

        const { result } = renderHook(() => useCreateProject("resume-1"), { wrapper });

        act(() => {
            result.current.mutate({
                tempId,
                payload: {
                    companyName: baseProject.companyName,
                    startDate: baseProject.startDate,
                    endDate: baseProject.endDate,
                    isActive: baseProject.active,
                    name: baseProject.name,
                    overview: baseProject.overview,
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

        // projectsのマージ結果：
        // - 保存対象のtempIdは除外
        // - ローカルのみのエントリー（localOnlyTempId）を先頭へ
        // - server projectsをベースに、dirtyなproject-1はローカルデータで上書き
        const expectedProjects = [
            localResume.projects.find((p: any) => p.id === localOnlyTempId)!,
            localResume.projects.find((p: any) => p.id === "project-1")!, // dirtyなのでローカルが優先
            serverResume.projects.find((p: any) => p.id === "project-2")!,
        ];

        // clearEntryErrorsはonMutateとonSuccessで計2回呼ばれる
        expect(useResumeStore.getState().clearEntryErrors).toHaveBeenCalledTimes(2);
        expect(useResumeStore.getState().clearEntryErrors).toHaveBeenNthCalledWith(1, tempId);
        expect(useResumeStore.getState().clearEntryErrors).toHaveBeenNthCalledWith(2, tempId);

        expect(useResumeStore.getState().updateResumeFromServer).toHaveBeenCalledWith({
            projects: expectedProjects,
            updatedAt: serverResume.updatedAt,
        });
        expect(useResumeStore.getState().setActiveEntryId).toHaveBeenCalledWith("project-2");
        expect(useResumeStore.getState().removeDirtyEntryId).toHaveBeenCalledWith(tempId);
        expect(useResumeStore.getState().setDirty).toHaveBeenCalledWith(false);
        expect(useNotificationStore.getState().setNotification).toHaveBeenCalledWith(
            "プロジェクトを作成しました。",
            "success",
        );
    });

    it("失敗時はエラーレスポンスのerrorsが存在する場合に、該当エントリへエラーが設定されること", async () => {
        useResumeStore.getState().setResume(localResume);
        useResumeStore.getState().setActiveSection("project");
        useResumeStore.getState().setActiveEntryId(tempId);

        const mockErrorResponse: ErrorResponse = {
            message: "入力内容に誤りがあります",
            errors: {
                name: ["入力してください。"],
            },
        };
        const mockError = {
            response: {
                data: mockErrorResponse,
            },
        };

        vi.mocked(protectedApiClient.post).mockRejectedValueOnce(mockError);

        const { result } = renderHook(() => useCreateProject("resume-1"), { wrapper });

        act(() => {
            result.current.mutate({
                tempId,
                payload: {
                    companyName: baseProject.companyName,
                    startDate: baseProject.startDate,
                    endDate: baseProject.endDate,
                    isActive: baseProject.active,
                    name: "",
                    overview: baseProject.overview,
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

        await waitFor(() => expect(result.current.isError).toBe(true));

        // clearEntryErrorsはonMutateで1回呼ばれる
        expect(useResumeStore.getState().clearEntryErrors).toHaveBeenCalledTimes(1);
        expect(useResumeStore.getState().clearEntryErrors).toHaveBeenCalledWith(tempId);

        expect(useResumeStore.getState().setEntryErrors).toHaveBeenCalledWith(tempId, mockErrorResponse.errors);

        expect(useResumeStore.getState().updateResumeFromServer).not.toHaveBeenCalled();
        expect(useResumeStore.getState().setDirty).not.toHaveBeenCalled();
        expect(useNotificationStore.getState().setNotification).not.toHaveBeenCalled();
    });
});
