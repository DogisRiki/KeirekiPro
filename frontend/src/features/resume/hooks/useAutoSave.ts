import type { SectionName } from "@/features/resume";
import { AUTO_SAVE_INTERVAL_MS, getApiId, useResumeStore } from "@/features/resume";
import dayjs from "dayjs";
import { useEffect } from "react";
import { useDebouncedCallback } from "use-debounce";

/**
 * 自動保存フックのオプション
 */
interface UseAutoSaveOptions {
    /** 自動保存が有効かどうか */
    enabled: boolean;
    /** 職務経歴書ID */
    resumeId: string;
    /** 基本情報更新ミューテーション */
    updateBasicMutation: { mutate: (payload: any) => void; isPending: boolean };
    /** 職歴更新ミューテーション */
    updateCareersMutation: { mutate: (payload: any) => void; isPending: boolean };
    /** プロジェクト更新ミューテーション */
    updateProjectsMutation: { mutate: (payload: any) => void; isPending: boolean };
    /** 資格更新ミューテーション */
    updateCertificationsMutation: { mutate: (payload: any) => void; isPending: boolean };
    /** ポートフォリオ更新ミューテーション */
    updatePortfoliosMutation: { mutate: (payload: any) => void; isPending: boolean };
    /** SNS更新ミューテーション */
    updateSocialLinksMutation: { mutate: (payload: any) => void; isPending: boolean };
    /** 自己PR更新ミューテーション */
    updateSelfPromotionsMutation: { mutate: (payload: any) => void; isPending: boolean };
}

/**
 * 自動保存フック（デバウンス方式）
 * 最後の編集から一定時間経過後に現在アクティブなセクションの情報を自動保存する
 */
export const useAutoSave = ({
    enabled,
    resumeId,
    updateBasicMutation,
    updateCareersMutation,
    updateProjectsMutation,
    updateCertificationsMutation,
    updatePortfoliosMutation,
    updateSocialLinksMutation,
    updateSelfPromotionsMutation,
}: UseAutoSaveOptions) => {
    const resume = useResumeStore((state) => state.resume);
    const isDirty = useResumeStore((state) => state.isDirty);

    // デバウンスされた保存処理
    const debouncedSave = useDebouncedCallback(() => {
        const { resume, activeSection, isDirty } = useResumeStore.getState();

        if (!resume || !resumeId || !isDirty) {
            return;
        }

        // いずれかのミューテーションが実行中の場合はスキップ
        const isPending =
            updateBasicMutation.isPending ||
            updateCareersMutation.isPending ||
            updateProjectsMutation.isPending ||
            updateCertificationsMutation.isPending ||
            updatePortfoliosMutation.isPending ||
            updateSocialLinksMutation.isPending ||
            updateSelfPromotionsMutation.isPending;

        if (isPending) {
            return;
        }

        switch (activeSection as SectionName) {
            case "basicInfo":
                updateBasicMutation.mutate({
                    resumeName: resume.resumeName,
                    date: dayjs(resume.date).format("YYYY-MM-DD"),
                    lastName: resume.lastName ?? "",
                    firstName: resume.firstName ?? "",
                });
                break;
            case "career":
                updateCareersMutation.mutate({
                    careers: resume.careers.map((c) => ({
                        id: getApiId(c.id),
                        companyName: c.companyName,
                        startDate: c.startDate,
                        endDate: c.endDate,
                        isActive: c.active,
                    })),
                });
                break;
            case "project":
                updateProjectsMutation.mutate({
                    projects: resume.projects.map((p) => ({
                        id: getApiId(p.id),
                        companyName: p.companyName,
                        startDate: p.startDate,
                        endDate: p.endDate,
                        isActive: p.active,
                        name: p.name,
                        overview: p.overview,
                        teamComp: p.teamComp,
                        role: p.role,
                        achievement: p.achievement,
                        requirements: p.process.requirements,
                        basicDesign: p.process.basicDesign,
                        detailedDesign: p.process.detailedDesign,
                        implementation: p.process.implementation,
                        integrationTest: p.process.integrationTest,
                        systemTest: p.process.systemTest,
                        maintenance: p.process.maintenance,
                        frontendLanguages: p.techStack.frontend.languages,
                        frontendFrameworks: p.techStack.frontend.frameworks,
                        frontendLibraries: p.techStack.frontend.libraries,
                        frontendBuildTools: p.techStack.frontend.buildTools,
                        frontendPackageManagers: p.techStack.frontend.packageManagers,
                        frontendLinters: p.techStack.frontend.linters,
                        frontendFormatters: p.techStack.frontend.formatters,
                        frontendTestingTools: p.techStack.frontend.testingTools,
                        backendLanguages: p.techStack.backend.languages,
                        backendFrameworks: p.techStack.backend.frameworks,
                        backendLibraries: p.techStack.backend.libraries,
                        backendBuildTools: p.techStack.backend.buildTools,
                        backendPackageManagers: p.techStack.backend.packageManagers,
                        backendLinters: p.techStack.backend.linters,
                        backendFormatters: p.techStack.backend.formatters,
                        backendTestingTools: p.techStack.backend.testingTools,
                        ormTools: p.techStack.backend.ormTools,
                        auth: p.techStack.backend.auth,
                        clouds: p.techStack.infrastructure.clouds,
                        operatingSystems: p.techStack.infrastructure.operatingSystems,
                        containers: p.techStack.infrastructure.containers,
                        databases: p.techStack.infrastructure.databases,
                        webServers: p.techStack.infrastructure.webServers,
                        ciCdTools: p.techStack.infrastructure.ciCdTools,
                        iacTools: p.techStack.infrastructure.iacTools,
                        monitoringTools: p.techStack.infrastructure.monitoringTools,
                        loggingTools: p.techStack.infrastructure.loggingTools,
                        sourceControls: p.techStack.tools.sourceControls,
                        projectManagements: p.techStack.tools.projectManagements,
                        communicationTools: p.techStack.tools.communicationTools,
                        documentationTools: p.techStack.tools.documentationTools,
                        apiDevelopmentTools: p.techStack.tools.apiDevelopmentTools,
                        designTools: p.techStack.tools.designTools,
                        editors: p.techStack.tools.editors,
                        developmentEnvironments: p.techStack.tools.developmentEnvironments,
                    })),
                });
                break;
            case "certification":
                updateCertificationsMutation.mutate({
                    certifications: resume.certifications.map((c) => ({
                        id: getApiId(c.id),
                        name: c.name,
                        date: c.date,
                    })),
                });
                break;
            case "portfolio":
                updatePortfoliosMutation.mutate({
                    portfolios: resume.portfolios.map((p) => ({
                        id: getApiId(p.id),
                        name: p.name,
                        overview: p.overview,
                        techStack: p.techStack,
                        link: p.link,
                    })),
                });
                break;
            case "socialLink":
                updateSocialLinksMutation.mutate({
                    socialLinks: resume.socialLinks.map((s) => ({
                        id: getApiId(s.id),
                        name: s.name,
                        link: s.link,
                    })),
                });
                break;
            case "selfPromotion":
                updateSelfPromotionsMutation.mutate({
                    selfPromotions: resume.selfPromotions.map((s) => ({
                        id: getApiId(s.id),
                        title: s.title,
                        content: s.content,
                    })),
                });
                break;
        }
    }, AUTO_SAVE_INTERVAL_MS);

    // resumeが変更されたらデバウンス保存をトリガー
    useEffect(() => {
        if (enabled && isDirty) {
            debouncedSave();
        }
    }, [enabled, resume, isDirty, debouncedSave]);

    // enabledがfalseになったらキャンセル
    useEffect(() => {
        if (!enabled) {
            debouncedSave.cancel();
        }
    }, [enabled, debouncedSave]);
};
