import { Button } from "@/components/ui";
import type { Resume as ResumeType } from "@/features/resume";
import {
    BottomMenu,
    createCurrentSection,
    EntryList,
    getResumeKey,
    sections,
    SectionTabs,
    useResumeStore,
} from "@/features/resume";
import { Delete as DeleteIcon, Save as SaveIcon } from "@mui/icons-material";
import { Box, Divider, Typography } from "@mui/material";
import Grid from "@mui/material/Grid2";
import { useEffect, useRef, useState } from "react";

// ダミーデータ
const dummyResume: ResumeType = {
    id: "e8a6baf2-79bf-47d2-8f60-90884c9a7b36",
    resumeName: "職務経歴書サンプル",
    date: "2023-01-01",
    lastName: "山田",
    firstName: "太郎",
    createdAt: "2023-01-01T00:00:00",
    updatedAt: "2023-01-01T00:00:00",
    careers: [
        {
            id: "1f3c9b9d-f273-40c3-b6e2-9db75f34d132",
            companyName: "株式会社A",
            startDate: "2015-04",
            endDate: "2018-03",
            active: false,
        },
        {
            id: "d8c1a23f-4b0d-4ea4-b073-5dcb59f0d76d",
            companyName: "株式会社B",
            startDate: "2018-04",
            endDate: "2021-06",
            active: false,
        },
        {
            id: "874dc276-bfb1-492f-8433-fbd7b47a4829",
            companyName: "株式会社C",
            startDate: "2021-07",
            endDate: null,
            active: true,
        },
    ],
    projects: [
        {
            id: "2f4a639a-3b90-445c-b58a-d48179f1a8b6",
            companyName: "株式会社A",
            startDate: "2016-04",
            endDate: "2018-03",
            active: false,
            name: "顧客管理システム開発",
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
                frontend: {
                    languages: ["JavaScript", "TypeScript"],
                    frameworks: ["React"],
                    libraries: ["MUI", "axios"],
                    buildTools: ["Vite"],
                    packageManagers: ["npm"],
                    linters: ["ESLint"],
                    formatters: ["Prettier"],
                    testingTools: ["Vitest", "React Testing Library"],
                },
                backend: {
                    languages: ["Java"],
                    frameworks: ["Spring Framework"],
                    libraries: ["Jackson", "Flyway"],
                    buildTools: ["Gradle"],
                    packageManagers: ["npm"],
                    linters: [],
                    formatters: [],
                    testingTools: ["JUnit"],
                    ormTools: ["MyBatis"],
                    auth: [],
                },
                infrastructure: {
                    clouds: ["AWS"],
                    operatingSystems: ["Linux"],
                    containers: ["Docker"],
                    databases: ["PostgreSQL"],
                    webServers: ["Nginx"],
                    ciCdTools: ["GitHub Actions"],
                    iacTools: ["Terraform"],
                    monitoringTools: ["Datadog", "Grafana"],
                    loggingTools: ["CloudWatch Logs"],
                },
                tools: {
                    sourceControls: ["Git"],
                    projectManagements: ["Jira"],
                    communicationTools: ["Slack"],
                    documentationTools: ["Confluence"],
                    apiDevelopmentTools: ["Postman", "Swagger"],
                    designTools: ["Figma"],
                    editors: ["IntelliJ IDEA"],
                    developmentEnvironments: ["Docker"],
                },
            },
        },
    ],
    certifications: [
        {
            id: "d32be9f6-8b3e-4c97-813e-a6c0e72fd993",
            name: "AWS認定ソリューションアーキテクト",
            date: "2020-01",
        },
        {
            id: "e18c20d7-639c-4d83-b760-5b3e3d479e8e",
            name: "基本情報技術者試験",
            date: "2015-04",
        },
        {
            id: "a77e02b1-927e-4cd1-82d4-f67b0d6d947b",
            name: "応用情報技術者試験",
            date: "2017-10",
        },
    ],
    portfolios: [
        {
            id: "1e9f72db-18f5-4c1f-942d-6f2b0c5d2c91",
            name: "ウェブアプリケーション1",
            overview: "Webアプリケーション開発ポートフォリオ",
            link: "https://portfolio1.com",
            techStack: "React, Node.js, AWS",
        },
        {
            id: "2f9f73dc-29f6-5d2f-953e-7f3c1d6e3d92",
            name: "モバイルアプリケーション2",
            overview: "モバイルアプリケーション開発ポートフォリオ",
            link: "https://portfolio2.com",
            techStack: "Flutter, Firebase, GCP",
        },
        {
            id: "3g0f84ed-39f7-6d3g-964f-8g4d2e7f4e03",
            name: "IoTシステム3",
            overview: "IoTシステム開発ポートフォリオ",
            link: "https://portfolio3.com",
            techStack: "Go, Docker, Azure",
        },
    ],
    socialLinks: [
        {
            id: "4h1g95fe-49g8-7d4h-975g-9h5e3f8g5f14",
            name: "LinkedIn",
            link: "https://linkedin.com/in/taro-yamada",
        },
        {
            id: "5i2h06gf-59h9-8d5i-986h-0i6f4g9h6g25",
            name: "GitHub",
            link: "https://github.com/taro-yamada",
        },
        {
            id: "6j3i17hg-69i0-9d6j-097i-1j7g5h0i7h36",
            name: "Twitter",
            link: "https://twitter.com/taro_yamada",
        },
    ],
    selfPromotions: [
        {
            id: "7k4j28ih-79j1-0e7k-1a8j-2k8h6i1j8i47",
            title: "自己PR1",
            content: "新しい技術に積極的に挑戦し、チームに貢献します。",
        },
        {
            id: "8l5k39ji-89k2-1f8l-2b9k-3l9i7j2k9j58",
            title: "自己PR2",
            content: "問題解決能力に優れ、複雑な課題にも対応可能です。",
        },
        {
            id: "9m6l40kj-99l3-2g9m-3c0l-4m0j8k3l0k69",
            title: "自己PR3",
            content: "コミュニケーション能力を活かして、チーム内外での調整を得意とします。",
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
    const resume = useResumeStore((state) => state.resume);
    const activeEntryId = useResumeStore((state) => state.activeEntryId);
    const updateSection = useResumeStore((state) => state.updateSection);
    const setActiveEntryId = useResumeStore((state) => state.setActiveEntryId);

    // タイトル取得
    const title = currentSection.label + "情報";

    // BottomMenuの高さを動的に取得
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

    return (
        <>
            {/* セクション切り替えタブ */}
            <SectionTabs />

            {/* タブ全体の保存ボタン */}
            <Box sx={{ display: "flex", justifyContent: "flex-end", mt: 2 }}>
                <Button color="info" startIcon={<SaveIcon />} onClick={() => alert("保存")}>
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
            <BottomMenu ref={bottomMenuRef} />
        </>
    );
};
