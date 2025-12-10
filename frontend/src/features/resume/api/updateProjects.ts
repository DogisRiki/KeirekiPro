import type { Resume } from "@/features/resume";
import { protectedApiClient } from "@/lib";
import type { AxiosResponse } from "axios";

/**
 * プロジェクト更新用ペイロード
 */
export interface UpdateProjectsPayload {
    projects: {
        id?: string | null;
        companyName: string;
        startDate: string; // yyyy-MM
        endDate?: string | null; // yyyy-MM
        isActive: boolean;
        name: string;
        overview: string;
        teamComp: string;
        role: string;
        achievement: string;
        // 作業工程
        requirements: boolean;
        basicDesign: boolean;
        detailedDesign: boolean;
        implementation: boolean;
        integrationTest: boolean;
        systemTest: boolean;
        maintenance: boolean;
        // TechStack - Frontend
        frontendLanguages?: string[];
        frontendFrameworks?: string[];
        frontendLibraries?: string[];
        frontendBuildTools?: string[];
        frontendPackageManagers?: string[];
        frontendLinters?: string[];
        frontendFormatters?: string[];
        frontendTestingTools?: string[];
        // TechStack - Backend
        backendLanguages?: string[];
        backendFrameworks?: string[];
        backendLibraries?: string[];
        backendBuildTools?: string[];
        backendPackageManagers?: string[];
        backendLinters?: string[];
        backendFormatters?: string[];
        backendTestingTools?: string[];
        ormTools?: string[];
        auth?: string[];
        // TechStack - Infrastructure
        clouds?: string[];
        operatingSystems?: string[];
        containers?: string[];
        databases?: string[];
        webServers?: string[];
        ciCdTools?: string[];
        iacTools?: string[];
        monitoringTools?: string[];
        loggingTools?: string[];
        // TechStack - Tools
        sourceControls?: string[];
        projectManagements?: string[];
        communicationTools?: string[];
        documentationTools?: string[];
        apiDevelopmentTools?: string[];
        designTools?: string[];
        editors?: string[];
        developmentEnvironments?: string[];
    }[];
}

/**
 * 職務経歴書プロジェクト更新API
 * @param resumeId 職務経歴書ID
 * @param payload プロジェクト更新リクエスト
 * @returns 更新後の職務経歴書情報を含むAxiosレスポンス
 */
export const updateProjects = (resumeId: string, payload: UpdateProjectsPayload): Promise<AxiosResponse<Resume>> =>
    protectedApiClient.put<Resume>(`/resumes/${resumeId}/projects`, payload);
