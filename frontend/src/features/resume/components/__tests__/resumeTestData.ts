import type { GetResumeListResponse, Resume, TechStack } from "@/features/resume";

export const resumeSummaries: GetResumeListResponse["resumes"] = [
    {
        id: "resume-1",
        resumeName: "Alpha Resume",
        createdAt: "2024-01-01T00:00:00.000Z",
        updatedAt: "2024-01-02T00:00:00.000Z",
    },
    {
        id: "resume-2",
        resumeName: "Beta Resume",
        createdAt: "2024-02-01T00:00:00.000Z",
        updatedAt: "2024-02-02T00:00:00.000Z",
    },
];

export const emptyTechStack: TechStack = {
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
};

export const resume: Resume = {
    id: "resume-1",
    resumeName: "Alpha Resume",
    date: "2024-01-01",
    lastName: "Yamada",
    firstName: "Taro",
    createdAt: "2024-01-01T00:00:00.000Z",
    updatedAt: "2024-01-02T00:00:00.000Z",
    careers: [
        {
            id: "career-1",
            companyName: "Company A",
            startDate: "2020-01",
            endDate: null,
            active: true,
        },
    ],
    projects: [
        {
            id: "project-1",
            companyName: "Company A",
            startDate: "2020-01",
            endDate: null,
            active: true,
            name: "Project A",
            overview: "Project overview",
            teamComp: "Team A",
            role: "Developer",
            achievement: "Delivered features",
            process: {
                requirements: true,
                basicDesign: false,
                detailedDesign: false,
                implementation: true,
                integrationTest: false,
                systemTest: false,
                maintenance: false,
            },
            techStack: emptyTechStack,
        },
    ],
    certifications: [],
    portfolios: [],
    snsPlatforms: [],
    selfPromotions: [],
};

export const cloneResume = (overrides: Partial<Resume> = {}): Resume => ({
    ...structuredClone(resume),
    ...overrides,
});
