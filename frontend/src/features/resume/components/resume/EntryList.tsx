import { NoData } from "@/components/errors";
import { Button } from "@/components/ui";
import type {
    Career,
    Certification,
    Portfolio,
    Project,
    SectionName,
    SelfPromotion,
    SnsPlatform,
} from "@/features/resume";
import {
    EntryListItem,
    getResumeKey,
    isTempId,
    sections,
    TEMP_ID_PREFIX,
    useDeleteCareer,
    useDeleteCertification,
    useDeletePortfolio,
    useDeleteProject,
    useDeleteSelfPromotion,
    useDeleteSnsPlatform,
    useResumeStore,
} from "@/features/resume";
import AddIcon from "@mui/icons-material/Add";
import { Box, Divider, List, Typography } from "@mui/material";
import { useMemo, useRef } from "react";
import { useParams } from "react-router";

/**
 * 新規エントリー生成用の型
 */
type ListEntry = Career | Project | Certification | Portfolio | SnsPlatform | SelfPromotion;

/**
 * セクションごとに新規エントリーを生成する
 */
const createNewEntry = (section: SectionName, id: string): ListEntry | null => {
    switch (section) {
        case "career": {
            const entry: Career = {
                id,
                companyName: "新しい職歴",
                startDate: "",
                endDate: null,
                active: false,
            };
            return entry;
        }
        case "project": {
            const entry: Project = {
                id,
                companyName: "",
                startDate: "",
                endDate: null,
                active: false,
                name: "新しいプロジェクト",
                overview: "",
                teamComp: "",
                role: "",
                achievement: "",
                process: {
                    requirements: false,
                    basicDesign: false,
                    detailedDesign: false,
                    implementation: false,
                    integrationTest: false,
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
            return entry;
        }
        case "certification": {
            const entry: Certification = {
                id,
                name: "新しい資格",
                date: "",
            };
            return entry;
        }
        case "portfolio": {
            const entry: Portfolio = {
                id,
                name: "新しいポートフォリオ",
                overview: "",
                techStack: "",
                link: "",
            };
            return entry;
        }
        case "snsPlatform": {
            const entry: SnsPlatform = {
                id,
                name: "新しいSNSプラットフォーム",
                link: "",
            };
            return entry;
        }
        case "selfPromotion": {
            const entry: SelfPromotion = {
                id,
                title: "新しい自己PR",
                content: "",
            };
            return entry;
        }
        case "basicInfo":
        default:
            return null;
    }
};

/**
 * スクロール表示に切り替える件数の閾値
 */
const SCROLL_THRESHOLD = 5;

/**
 * スクロール表示時の最大高さ
 */
const MAX_SCROLL_HEIGHT = 400;

/**
 * エントリーリスト
 */
export const EntryList = () => {
    const { id: resumeId } = useParams<{ id: string }>();

    // スクロールコンテナへの参照
    const scrollContainerRef = useRef<HTMLDivElement>(null);

    // ストアから必要な状態を取り出す
    const activeSection = useResumeStore((state) => state.activeSection);
    const resume = useResumeStore((state) => state.resume);
    const setActiveEntryId = useResumeStore((state) => state.setActiveEntryId);
    const updateSection = useResumeStore((state) => state.updateSection);
    const activeEntryId = useResumeStore((state) => state.activeEntryId);
    const removeEntry = useResumeStore((state) => state.removeEntry);

    // 各セクションの削除ミューテーション
    const deleteCareerMutation = useDeleteCareer(resumeId ?? "");
    const deleteProjectMutation = useDeleteProject(resumeId ?? "");
    const deleteCertificationMutation = useDeleteCertification(resumeId ?? "");
    const deletePortfolioMutation = useDeletePortfolio(resumeId ?? "");
    const deleteSnsPlatformMutation = useDeleteSnsPlatform(resumeId ?? "");
    const deleteSelfPromotionMutation = useDeleteSelfPromotion(resumeId ?? "");

    // エントリーデータ取得
    const entries = useMemo(() => {
        if (!resume) return [];
        const key = getResumeKey(activeSection);
        return key ? (resume[key] ?? []) : [];
    }, [resume, activeSection]);

    // タイトル取得
    const title = sections.find((section) => section.key === activeSection)?.label + "一覧";

    // スクロール表示が必要かどうか
    const needsScroll = entries.length > SCROLL_THRESHOLD;

    /**
     * スクロールコンテナを先頭にスクロールする
     */
    const scrollToTop = () => {
        if (scrollContainerRef.current) {
            scrollContainerRef.current.scrollTo({ top: 0, behavior: "smooth" });
        }
    };

    /**
     * 新規追加
     */
    const handleNewClick = () => {
        if (!resume) return;

        const sectionKey = getResumeKey(activeSection);
        if (!sectionKey) return;

        // 一時IDを生成（プレフィックス付き）
        const tempId =
            typeof crypto !== "undefined" && "randomUUID" in crypto
                ? `${TEMP_ID_PREFIX}${crypto.randomUUID()}`
                : `${TEMP_ID_PREFIX}${Date.now()}-${Math.random().toString(16).slice(2)}`;

        const newEntry = createNewEntry(activeSection, tempId);
        if (!newEntry) return;

        const currentList = resume[sectionKey] ?? [];
        const updatedList = [newEntry, ...currentList] as typeof currentList;

        updateSection(sectionKey, updatedList);
        setActiveEntryId(tempId);

        // リストを先頭にスクロール
        scrollToTop();
    };

    /**
     * エントリー削除ハンドラー
     * @param entryId 削除対象のエントリーID
     * @param needsDbSync DBへの同期が必要かどうか（既存エントリーの場合true）
     */
    const handleDeleteEntry = (entryId: string, needsDbSync: boolean) => {
        if (!resume) return;

        const sectionKey = getResumeKey(activeSection);
        if (!sectionKey) return;

        // アクティブなエントリーが削除された場合はクリア
        if (activeEntryId === entryId) {
            setActiveEntryId(null);
        }

        // 一時IDの場合はストアから削除するのみ
        if (!needsDbSync || isTempId(entryId)) {
            removeEntry(sectionKey, entryId);
            return;
        }

        // DBへの同期が必要な場合はAPIを呼び出す
        executeDeleteMutation(entryId);
    };

    /**
     * セクションに応じた削除ミューテーションを実行
     */
    const executeDeleteMutation = (entryId: string) => {
        switch (activeSection) {
            case "career":
                deleteCareerMutation.mutate(entryId);
                break;
            case "project":
                deleteProjectMutation.mutate(entryId);
                break;
            case "certification":
                deleteCertificationMutation.mutate(entryId);
                break;
            case "portfolio":
                deletePortfolioMutation.mutate(entryId);
                break;
            case "snsPlatform":
                deleteSnsPlatformMutation.mutate(entryId);
                break;
            case "selfPromotion":
                deleteSelfPromotionMutation.mutate(entryId);
                break;
        }
    };

    return (
        <Box sx={{ bgcolor: "background.paper", borderRadius: 2, boxShadow: 1 }}>
            {/* ヘッダー */}
            <Box
                sx={{
                    display: "flex",
                    justifyContent: "space-between",
                    alignItems: "center",
                    p: 2,
                }}
            >
                <Typography variant="h6">{title}</Typography>
                {/* 新規追加ボタン */}
                <Button size="small" startIcon={<AddIcon />} onClick={handleNewClick}>
                    新規追加
                </Button>
            </Box>
            <Divider />
            {/* エントリーリスト */}
            <Box sx={{ p: 2 }}>
                {entries.length > 0 ? (
                    <Box
                        ref={scrollContainerRef}
                        sx={{
                            maxHeight: needsScroll ? MAX_SCROLL_HEIGHT : "none",
                            overflowY: needsScroll ? "auto" : "visible",
                        }}
                    >
                        <List sx={{ width: "100%" }}>
                            {/* エントリーアイテム */}
                            {entries.map((entry: { id: string }) => (
                                <EntryListItem
                                    key={entry.id}
                                    entry={entry}
                                    onDeleteEntry={handleDeleteEntry}
                                    onDuplicate={scrollToTop}
                                />
                            ))}
                        </List>
                    </Box>
                ) : (
                    <Box sx={{ my: 20 }}>
                        <NoData variant="body1" message={"表示するデータがありません。"} />
                    </Box>
                )}
            </Box>
        </Box>
    );
};
