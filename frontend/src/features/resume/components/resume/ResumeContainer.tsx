import { Button, Dialog } from "@/components/ui";
import type { SectionName } from "@/features/resume";
import {
    BottomMenu,
    createCurrentSection,
    EntryList,
    getApiId,
    getResumeKey,
    sections,
    SectionTabs,
    useAutoSave,
    useGetResumeInfo,
    useNavigationBlocker,
    useResumeStore,
    useUpdateCareers,
    useUpdateCertifications,
    useUpdatePortfolios,
    useUpdateProjects,
    useUpdateResumeBasic,
    useUpdateSelfPromotions,
    useUpdateSocialLinks,
} from "@/features/resume";
import { Delete as DeleteIcon, Save as SaveIcon } from "@mui/icons-material";
import { Box, Divider, Typography } from "@mui/material";
import Grid from "@mui/material/Grid2";
import dayjs from "dayjs";
import { useState } from "react";
import { useParams } from "react-router";

/**
 * 職務経歴書詳細コンテナ
 */
export const ResumeContainer = () => {
    const { id: resumeId } = useParams<{ id: string }>();

    // 離脱防止フック
    const { dialogProps } = useNavigationBlocker();

    // 現在のセクションを監視
    const activeSection = useResumeStore((state) => state.activeSection);
    const currentSection = sections.find((section) => section.key === activeSection)!;

    const resume = useResumeStore((state) => state.resume);
    const activeEntryId = useResumeStore((state) => state.activeEntryId);
    const updateSection = useResumeStore((state) => state.updateSection);
    const setActiveEntryId = useResumeStore((state) => state.setActiveEntryId);

    // タイトル取得
    const title = currentSection.label + "情報";

    // BottomMenuの高さを動的に取得
    const [bottomMenuHeight, setBottomMenuHeight] = useState(0);

    // 自動保存の有効/無効状態
    const [autoSaveEnabled, setAutoSaveEnabled] = useState(false);

    // 職務経歴書詳細情報取得
    const { isLoading } = useGetResumeInfo(resumeId ?? "");

    // 各セクションの更新ミューテーション
    const updateBasicMutation = useUpdateResumeBasic(resumeId ?? "");
    const updateCareersMutation = useUpdateCareers(resumeId ?? "");
    const updateProjectsMutation = useUpdateProjects(resumeId ?? "");
    const updateCertificationsMutation = useUpdateCertifications(resumeId ?? "");
    const updatePortfoliosMutation = useUpdatePortfolios(resumeId ?? "");
    const updateSocialLinksMutation = useUpdateSocialLinks(resumeId ?? "");
    const updateSelfPromotionsMutation = useUpdateSelfPromotions(resumeId ?? "");

    // 自動保存フック
    useAutoSave({
        enabled: autoSaveEnabled,
        resumeId: resumeId ?? "",
        updateBasicMutation,
        updateCareersMutation,
        updateProjectsMutation,
        updateCertificationsMutation,
        updatePortfoliosMutation,
        updateSocialLinksMutation,
        updateSelfPromotionsMutation,
    });

    // BottomMenuの高さ計測
    const measuredRef = (node: HTMLDivElement | null) => {
        if (node !== null) {
            setBottomMenuHeight(node.offsetHeight);
        }
    };

    /**
     * 現在アクティブなエントリを削除（ストアのみ更新）
     */
    const handleDeleteCurrentEntry = () => {
        if (!activeEntryId) return;
        if (!resume) return;

        const sectionKey = getResumeKey(activeSection);
        if (!sectionKey) return;

        const list = resume[sectionKey];
        const updated = list.filter((item) => item.id !== activeEntryId) as typeof list;

        updateSection(sectionKey, updated);
        setActiveEntryId(null);
    };

    /**
     * 保存ボタン押下時のハンドラー
     */
    const handleSave = () => {
        if (!resume || !resumeId) return;

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
    };

    // ローディング状態
    const isSaving =
        updateBasicMutation.isPending ||
        updateCareersMutation.isPending ||
        updateProjectsMutation.isPending ||
        updateCertificationsMutation.isPending ||
        updatePortfoliosMutation.isPending ||
        updateSocialLinksMutation.isPending ||
        updateSelfPromotionsMutation.isPending;

    // データ取得中またはresumeがnullの場合は何も表示しない
    if (isLoading || !resume) {
        return null;
    }

    return (
        <>
            {/* セクション切り替えタブ */}
            <SectionTabs />

            {/* タブ全体の保存ボタン */}
            <Box sx={{ display: "flex", justifyContent: "flex-end", mt: 2 }}>
                <Button color="info" startIcon={<SaveIcon />} onClick={handleSave} disabled={isSaving}>
                    このタブの情報を保存
                </Button>
            </Box>

            <Grid container spacing={3} sx={{ mt: 2, mb: `${bottomMenuHeight}px` }}>
                {currentSection.type === "list" && (
                    <Grid size={{ xs: 12, md: 4 }}>
                        {/* エントリーリスト */}
                        <EntryList />
                    </Grid>
                )}
                <Grid size={{ xs: 12, md: currentSection.type === "list" ? 8 : 12 }}>
                    {/* セクション */}
                    <Box
                        sx={{
                            bgcolor: "background.paper",
                            borderRadius: 2,
                            boxShadow: "0px 1px 3px 0px rgba(0, 0, 0, 0.2)",
                        }}
                    >
                        <Box
                            sx={{
                                display: "flex",
                                alignItems: "center",
                                justifyContent: "space-between",
                                p: 2,
                            }}
                        >
                            {/* コンテンツタイトル */}
                            <Typography variant="h6">{title}</Typography>
                            <Box>
                                {/* 削除ボタン（複数エントリーを持つセクションのみ表示） */}
                                {currentSection.type === "list" && (
                                    <Button
                                        color="error"
                                        size="small"
                                        startIcon={<DeleteIcon />}
                                        onClick={handleDeleteCurrentEntry}
                                    >
                                        削除
                                    </Button>
                                )}
                            </Box>
                        </Box>
                        <Divider />
                        <Box sx={{ display: "flex", flexDirection: "column", justifyContent: "center", p: 3 }}>
                            {createCurrentSection(activeSection)}
                        </Box>
                    </Box>
                </Grid>
            </Grid>
            {/* 下部メニュー */}
            <BottomMenu ref={measuredRef} autoSaveEnabled={autoSaveEnabled} onAutoSaveToggle={setAutoSaveEnabled} />
            {/* 離脱防止ダイアログ */}
            <Dialog
                open={dialogProps.open}
                variant="confirm"
                title="このページを離れますか？"
                description="保存されていない変更があります。このまま離れると、変更内容は失われます。"
                onClose={dialogProps.onClose}
            />
        </>
    );
};
