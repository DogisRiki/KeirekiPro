import { NoData } from "@/components/errors";
import { Button } from "@/components/ui";
import type {
    Career,
    Certification,
    Portfolio,
    Project,
    SectionName,
    SelfPromotion,
    SocialLink,
} from "@/features/resume";
import { EntryListItem, getResumeKey, sections, useResumeStore } from "@/features/resume";
import { Add as AddIcon } from "@mui/icons-material";
import { Box, Divider, List, Typography } from "@mui/material";

/**
 * 新規エントリー生成用の型
 */
type ListEntry = Career | Project | Certification | Portfolio | SocialLink | SelfPromotion;

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
                name: "新しい職務内容",
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
        case "socialLink": {
            const entry: SocialLink = {
                id,
                name: "新しいSNS",
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
 * エントリーリスト
 */
export const EntryList = () => {
    // ストアから必要な状態を取り出す
    const { activeSection, setActiveEntryId, updateSection } = useResumeStore();
    const resume = useResumeStore((state) => state.resume);

    // エントリーデータ取得
    const entries = useResumeStore((state) => {
        const key = getResumeKey(state.activeSection);
        return key ? state.resume?.[key] ?? [] : [];
    });

    // タイトル取得
    const title = sections.find((section) => section.key === activeSection)?.label + "一覧";

    /**
     * 新規追加
     */
    const handleNewClick = () => {
        if (!resume) return;

        const sectionKey = getResumeKey(activeSection);
        if (!sectionKey) return;

        const newId =
            typeof crypto !== "undefined" && "randomUUID" in crypto
                ? crypto.randomUUID()
                : `${Date.now()}-${Math.random().toString(16).slice(2)}`;

        const newEntry = createNewEntry(activeSection, newId);
        if (!newEntry) return;

        const currentList = resume[sectionKey];
        const updatedList = [newEntry, ...currentList] as typeof currentList;

        updateSection(sectionKey, updatedList);
        setActiveEntryId(newId);
    };

    return (
        <Box sx={{ bgcolor: "background.paper", borderRadius: 2, boxShadow: "0px 1px 3px 0px rgba(0, 0, 0, 0.2)" }}>
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
                    <List sx={{ width: "100%" }}>
                        {/* エントリーアイテム */}
                        {entries.map((entry: { id: string }) => (
                            <EntryListItem key={entry.id} entry={entry} />
                        ))}
                    </List>
                ) : (
                    <Box sx={{ my: 20 }}>
                        <NoData variant="body1" message={"表示するデータがありません。"} />
                    </Box>
                )}
            </Box>
        </Box>
    );
};
