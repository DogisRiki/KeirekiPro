import { sections, useResumeStore } from "@/features/resume";
import KeyboardArrowDownIcon from "@mui/icons-material/KeyboardArrowDown";
import { FormControl, MenuItem, Select, Tab, Tabs, useMediaQuery, useTheme } from "@mui/material";
import { useState } from "react";

/**
 * セクション切り替えタブ
 * - デスクトップ: タブ表示
 * - スマホ: ドロップダウン表示
 */
export const SectionTabs = () => {
    const theme = useTheme();
    const isMobile = useMediaQuery(theme.breakpoints.down("sm"));

    // ドロップダウンの開閉状態
    const [open, setOpen] = useState(false);

    // ストアから必要な状態を取り出す
    const activeSection = useResumeStore((state) => state.activeSection);
    const setActiveSection = useResumeStore((state) => state.setActiveSection);

    /**
     * タブ変更ハンドラー
     */
    const handleTabChange = (_: React.SyntheticEvent, newValue: number) => {
        const targetSection = sections[newValue].key;
        setActiveSection(targetSection);
    };

    /**
     * セレクト変更ハンドラー
     */
    const handleSelectChange = (event: { target: { value: string } }) => {
        const targetSection = event.target.value as (typeof sections)[number]["key"];
        setActiveSection(targetSection);
    };

    // スマホ表示: ドロップダウン
    if (isMobile) {
        return (
            <FormControl fullWidth>
                <Select
                    value={activeSection}
                    onChange={handleSelectChange}
                    open={open}
                    onOpen={() => setOpen(true)}
                    onClose={() => setOpen(false)}
                    IconComponent={(props) => (
                        <KeyboardArrowDownIcon
                            {...props}
                            sx={{
                                transition: "transform 0.2s",
                                transform: open ? "rotate(180deg)" : "rotate(0deg)",
                            }}
                        />
                    )}
                    sx={{
                        bgcolor: "background.paper",
                        borderRadius: 2,
                        boxShadow: 1,
                        "& .MuiSelect-select": {
                            py: 1.5,
                        },
                        "& .MuiOutlinedInput-notchedOutline": {
                            border: "none",
                        },
                        "&:hover .MuiOutlinedInput-notchedOutline": {
                            border: "none",
                        },
                        "&.Mui-focused .MuiOutlinedInput-notchedOutline": {
                            border: "none",
                        },
                    }}
                    MenuProps={{
                        PaperProps: {
                            sx: {
                                mt: 1,
                                borderRadius: 2,
                                boxShadow: 3,
                            },
                        },
                    }}
                >
                    {sections.map((section) => (
                        <MenuItem key={section.key} value={section.key} sx={{ py: 1.5 }}>
                            {section.label}
                        </MenuItem>
                    ))}
                </Select>
            </FormControl>
        );
    }

    // デスクトップ表示: タブ
    return (
        <Tabs
            value={sections.findIndex((section) => section.key === activeSection)}
            onChange={handleTabChange}
            variant="scrollable"
            allowScrollButtonsMobile
            sx={{ bgcolor: "background.paper", borderRadius: 2, boxShadow: 1 }}
        >
            {sections.map((section) => (
                <Tab
                    key={section.key}
                    label={section.label}
                    sx={{
                        transition: "0.3s",
                        "&:hover": {
                            bgcolor: "action.hover",
                        },
                    }}
                />
            ))}
        </Tabs>
    );
};
