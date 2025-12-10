import { Dialog } from "@/components/ui";
import { sections, useResumeStore } from "@/features/resume";
import { Tab, Tabs } from "@mui/material";
import { useState } from "react";

/**
 * セクション切り替えタブ
 */
export const SectionTabs = () => {
    // ストアから必要な状態を取り出す
    const activeSection = useResumeStore((state) => state.activeSection);
    const resume = useResumeStore((state) => state.resume);
    const setActiveSection = useResumeStore((state) => state.setActiveSection);
    const setActiveEntryId = useResumeStore((state) => state.setActiveEntryId);

    // 警告ダイアログの開閉状態
    const [alertDialogOpen, setAlertDialogOpen] = useState(false);

    /**
     * タブ変更ハンドラー
     */
    const handleChange = (_: React.SyntheticEvent, newValue: number) => {
        const targetSection = sections[newValue].key;

        // プロジェクトタブに移動しようとしたとき、職歴が空の場合は警告
        if (targetSection === "project") {
            const hasCareers = resume?.careers && resume.careers.length > 0;
            if (!hasCareers) {
                setAlertDialogOpen(true);
                return;
            }
        }

        setActiveSection(targetSection);
        setActiveEntryId(null);
    };

    /**
     * 警告ダイアログのコールバック
     */
    const handleAlertDialogClose = () => {
        setAlertDialogOpen(false);
        // 職歴タブへ移動
        setActiveSection("career");
        setActiveEntryId(null);
    };

    return (
        <>
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
            {/* 職歴未入力警告ダイアログ */}
            <Dialog
                open={alertDialogOpen}
                variant="warning"
                title="警告"
                description="職務内容を入力するには、先に職歴を登録してください。"
                onClose={handleAlertDialogClose}
            />
        </>
    );
};
