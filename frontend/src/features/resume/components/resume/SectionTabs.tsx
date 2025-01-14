import { sections, useResumeStore } from "@/features/resume";
import { Tab, Tabs } from "@mui/material";

/**
 * セクション切り替えタブ
 */
export const SectionTabs = () => {
    // ストアから必要な状態を取り出す
    const { activeSection, setActiveSection } = useResumeStore();

    // セクション変更ハンドラー
    const handleChange = (_: React.SyntheticEvent, newValue: number) => {
        setActiveSection(sections[newValue].key);
    };

    return (
        <Tabs
            value={sections.findIndex((section) => section.key === activeSection)}
            onChange={handleChange}
            variant="scrollable"
            allowScrollButtonsMobile
            sx={{ bgcolor: "background.paper", borderRadius: 2, boxShadow: "0px 1px 3px 0px rgba(0, 0, 0, 0.2)" }}
        >
            {sections.map((section) => (
                <Tab
                    key={section.key}
                    label={section.label}
                    sx={{
                        transition: "0.3s",
                        "&:hover": {
                            bgcolor: "rgba(0, 0, 0, 0.04)",
                        },
                    }}
                />
            ))}
        </Tabs>
    );
};
