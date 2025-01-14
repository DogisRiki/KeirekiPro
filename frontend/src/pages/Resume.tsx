import { Button } from "@/components/ui";
import { BottomMenu, createCurrentSection, EntryList, sections, SectionTabs, useResumeStore } from "@/features/resume";
import { Resume as ResumeType } from "@/types";
import { Delete as DeleteIcon, Save as SaveIcon } from "@mui/icons-material";
import { Box, Divider, Typography } from "@mui/material";
import Grid from "@mui/material/Grid2";
import { useEffect, useRef, useState } from "react";

// ダミーデータ
const dummyResume: ResumeType = {
    id: "e8a6baf2-79bf-47d2-8f60-90884c9a7b36",
    name: "職務経歴書サンプル",
    date: "2023-01-01T00:00:00",
    lastName: "山田",
    firstName: "太郎",
    autoSaveEnabled: true,
    createdAt: "2023-01-01T00:00:00",
    updatedAt: "2023-01-01T00:00:00",
    careers: [
        {
            id: "1f3c9b9d-f273-40c3-b6e2-9db75f34d132",
            companyName: "株式会社A",
            startDate: "2015-04-01T00:00:00",
            endDate: "2018-03-31T00:00:00",
            isEmployed: false,
            orderNo: 0,
        },
        {
            id: "d8c1a23f-4b0d-4ea4-b073-5dcb59f0d76d",
            companyName: "株式会社B",
            startDate: "2018-04-01T00:00:00",
            endDate: "2021-06-30T00:00:00",
            isEmployed: false,
            orderNo: 1,
        },
        {
            id: "874dc276-bfb1-492f-8433-fbd7b47a4829",
            companyName: "株式会社C",
            startDate: "2021-07-01T00:00:00",
            endDate: null,
            isEmployed: true,
            orderNo: 2,
        },
    ],
    projects: [
        {
            id: "2f4a639a-3b90-445c-b58a-d48179f1a8b6",
            companyName: "株式会社A",
            startDate: "2016-04-01T00:00:00",
            endDate: "2018-03-31T00:00:00",
            isAssigned: false,
            projectName: "顧客管理システム開発",
            overview: "顧客管理システムの要件定義から実装までを担当",
            teamComp: "6人",
            role: "リーダー",
            achievement: "システムの新規導入に成功",
            process: {
                requirements: true,
                basicDesign: true,
                detailedDesign: true,
                implementation: true,
                integrationTest: true,
                systemTest: true,
                maintenance: false,
            },
            techStack: {
                languages: ["Java, Python", "JavaScript, TypeScript"],
                dependencies: {
                    frameworks: ["Spring Framework", "Django", "React"],
                    libraries: ["Jackson", "Flyway", "numpy", "ESLint", "Prettier", "axios", "TanStack Query", "MUI"],
                    testingTools: ["JUnit", "pytest", "Jest", "Vitest", "React Testing Tools", "Playwright"],
                    ormTools: ["MyBatis"],
                    packageManagers: ["npm", "Poetry"],
                },
                infrastructure: {
                    clouds: ["AWS"],
                    containers: ["Docker"],
                    databases: ["PostgreSQL"],
                    webServers: ["Nginx"],
                    ciCdTools: ["Github Actions"],
                    iacTools: ["Terraform"],
                    monitoringTools: ["Datadog", "Grafana"],
                    loggingTools: ["CloudWatch Logs"],
                },
                tools: {
                    sourceControls: ["Git"],
                    projectManagements: ["Jira", "Redmine"],
                    communicationTools: ["Slack", "Microsoft Teams"],
                    documentationTools: ["Confluence"],
                    apiDevelopmentTools: ["Postman", "Swagger"],
                    designTools: ["Figma"],
                },
            },
            orderNo: 0,
        },
    ],
    certifications: [
        {
            id: "d32be9f6-8b3e-4c97-813e-a6c0e72fd993",
            name: "AWS認定ソリューションアーキテクト",
            date: "2020-01-01T00:00:00",
            orderNo: 0,
        },
        {
            id: "e18c20d7-639c-4d83-b760-5b3e3d479e8e",
            name: "基本情報技術者試験",
            date: "2015-04-01T00:00:00",
            orderNo: 1,
        },
        {
            id: "a77e02b1-927e-4cd1-82d4-f67b0d6d947b",
            name: "応用情報技術者試験",
            date: "2017-10-01T00:00:00",
            orderNo: 2,
        },
    ],
    portfolios: [
        {
            id: "1e9f72db-18f5-4c1f-942d-6f2b0c5d2c91",
            name: "ウェブアプリケーション1",
            overview: "Webアプリケーション開発ポートフォリオ",
            link: "https://portfolio1.com",
            teckStack: "React, Node.js, AWS",
            orderNo: 0,
        },
        {
            id: "2f9f73dc-29f6-5d2f-953e-7f3c1d6e3d92",
            name: "モバイルアプリケーション2",
            overview: "モバイルアプリケーション開発ポートフォリオ",
            link: "https://portfolio2.com",
            teckStack: "Flutter, Firebase, GCP",
            orderNo: 1,
        },
        {
            id: "3g0f84ed-39f7-6d3g-964f-8g4d2e7f4e03",
            name: "IoTシステム3",
            overview: "IoTシステム開発ポートフォリオ",
            link: "https://portfolio3.com",
            teckStack: "Go, Docker, Azure",
            orderNo: 2,
        },
    ],
    socialLinks: [
        {
            id: "4h1g95fe-49g8-7d4h-975g-9h5e3f8g5f14",
            name: "LinkedIn",
            link: "https://linkedin.com/in/taro-yamada",
            orderNo: 0,
        },
        {
            id: "5i2h06gf-59h9-8d5i-986h-0i6f4g9h6g25",
            name: "GitHub",
            link: "https://github.com/taro-yamada",
            orderNo: 1,
        },
        {
            id: "6j3i17hg-69i0-9d6j-097i-1j7g5h0i7h36",
            name: "Twitter",
            link: "https://twitter.com/taro_yamada",
            orderNo: 2,
        },
    ],
    selfPromotions: [
        {
            id: "7k4j28ih-79j1-0e7k-1a8j-2k8h6i1j8i47",
            title: "自己PR1",
            content: "新しい技術に積極的に挑戦し、チームに貢献します。",
            orderNo: 0,
        },
        {
            id: "8l5k39ji-89k2-1f8l-2b9k-3l9i7j2k9j58",
            title: "自己PR2",
            content: "問題解決能力に優れ、複雑な課題にも対応可能です。",
            orderNo: 1,
        },
        {
            id: "9m6l40kj-99l3-2g9m-3c0l-4m0j8k3l0k69",
            title: "自己PR3",
            content: "コミュニケーション能力を活かして、チーム内外での調整を得意とします。",
            orderNo: 2,
        },
    ],
};

/**
 * 職務経歴書作成&編集画面
 */
export const Resume = () => {
    // 現在のセクションを監視
    const activeSection = useResumeStore((state) => state.activeSection);
    const currentSection = sections.find((section) => section.key === activeSection)!;
    const setResume = useResumeStore((state) => state.setResume);

    // タイトル取得
    const title = currentSection.label + "情報";

    // BottomMenu の高さを動的に取得
    const bottomMenuRef = useRef<HTMLDivElement>(null);
    const [bottomMenuHeight, setBottomMenuHeight] = useState(0);

    // 初期化
    useEffect(() => {
        setResume(dummyResume);
    }, [setResume]);

    useEffect(() => {
        if (bottomMenuRef.current) {
            setBottomMenuHeight(bottomMenuRef.current.offsetHeight);
        }
    }, [bottomMenuRef]);

    return (
        <>
            {/* セクション切り替えタブ */}
            <SectionTabs />
            <Grid container spacing={3} sx={{ mt: 4, mb: `${bottomMenuHeight}px` }}>
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
                                {/* 保存ボタン */}
                                <Button color="info" size="small" startIcon={<SaveIcon />} sx={{ mr: 2 }}>
                                    保存
                                </Button>
                                {/* 削除ボタン */}
                                <Button color="error" size="small" startIcon={<DeleteIcon />}>
                                    削除
                                </Button>
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
            <BottomMenu ref={bottomMenuRef} />
        </>
    );
};
