import { Dialog } from "@/components/ui";
import { checkCareerDeletable, getEntryText, getResumeKey, useResumeStore } from "@/features/resume";
import { FiberManualRecord as FiberManualRecordIcon, MoreVert as MoreVertIcon } from "@mui/icons-material";
import { IconButton, ListItem, ListItemButton, ListItemText, Menu, MenuItem, Tooltip } from "@mui/material";
import { useState } from "react";

/**
 * エントリーリストアイテムのProps
 */
interface EntryListItemProps {
    entry: { id: string };
}

/**
 * エントリーリストアイテム
 */
export const EntryListItem = ({ entry }: EntryListItemProps) => {
    // ストアから必要な状態を取り出す
    const { activeSection, activeEntryId, setActiveEntryId, updateSection } = useResumeStore();
    const resume = useResumeStore((state) => state.resume);
    const dirtyEntryIds = useResumeStore((state) => state.dirtyEntryIds);

    const [anchorEl, setAnchorEl] = useState<null | HTMLElement>(null);
    const open = Boolean(anchorEl);

    // 警告ダイアログの状態
    const [warningDialogOpen, setWarningDialogOpen] = useState(false);
    const [warningMessage, setWarningMessage] = useState("");

    // 未保存のエントリーかどうか
    const isUnsaved = dirtyEntryIds.has(entry.id);

    /**
     * メニューオープン
     */
    const handleMenuOpen = (event: React.MouseEvent<HTMLElement>) => {
        event.stopPropagation();
        setAnchorEl(event.currentTarget);
    };

    /**
     * メニュークローズ（Menu.onClose 用）
     */
    const handleMenuClose = () => {
        setAnchorEl(null);
    };

    /**
     * エントリー削除処理
     */
    const handleDelete = (event: React.MouseEvent<HTMLElement>) => {
        event.stopPropagation();
        setAnchorEl(null);

        if (!resume) {
            return;
        }

        const sectionKey = getResumeKey(activeSection);
        if (!sectionKey) {
            return;
        }

        // 職歴の場合、プロジェクトで使用されているかチェック
        if (sectionKey === "careers") {
            const checkResult = checkCareerDeletable(resume, entry.id);
            if (!checkResult.canDelete) {
                setWarningMessage(checkResult.warningMessage ?? "");
                setWarningDialogOpen(true);
                return;
            }
        }

        const list = resume[sectionKey];
        const updated = list.filter((item) => item.id !== entry.id) as typeof list;

        updateSection(sectionKey, updated);

        if (activeEntryId === entry.id) {
            setActiveEntryId(null);
        }
    };

    /**
     * 警告ダイアログを閉じる
     */
    const handleWarningDialogClose = () => {
        setWarningDialogOpen(false);
        setWarningMessage("");
    };

    return (
        <>
            <ListItem disablePadding sx={{ mb: 1 }}>
                <ListItemButton
                    selected={activeEntryId === entry.id}
                    onClick={() => setActiveEntryId(entry.id)}
                    sx={{
                        display: "flex",
                        justifyContent: "space-between",
                        alignItems: "center",
                    }}
                >
                    {/* 未保存アイコン */}
                    {isUnsaved && (
                        <Tooltip title="未保存" placement="top">
                            <FiberManualRecordIcon
                                sx={{
                                    fontSize: 12,
                                    color: "warning.main",
                                    mr: 1,
                                    flexShrink: 0,
                                }}
                            />
                        </Tooltip>
                    )}
                    <ListItemText
                        primary={getEntryText(activeSection, entry)?.primary || ""}
                        secondary={getEntryText(activeSection, entry)?.secondary || ""}
                        slotProps={{
                            primary: {
                                sx: {
                                    fontWeight: activeEntryId === entry.id ? "bold" : "normal",
                                    whiteSpace: "nowrap",
                                    overflow: "hidden",
                                    textOverflow: "ellipsis",
                                },
                            },
                            secondary: {
                                sx: {
                                    whiteSpace: "nowrap",
                                    overflow: "hidden",
                                    textOverflow: "ellipsis",
                                },
                            },
                        }}
                    />
                    {/* メニューアイコン */}
                    <IconButton edge="end" onClick={handleMenuOpen}>
                        <MoreVertIcon />
                    </IconButton>
                </ListItemButton>
            </ListItem>

            {/* メニュー */}
            <Menu
                anchorEl={anchorEl}
                open={open}
                onClose={handleMenuClose}
                anchorOrigin={{
                    vertical: "bottom",
                    horizontal: "right",
                }}
                transformOrigin={{
                    vertical: "top",
                    horizontal: "right",
                }}
            >
                <MenuItem onClick={handleDelete} sx={{ color: "error.main" }}>
                    削除
                </MenuItem>
            </Menu>

            {/* 警告ダイアログ */}
            <Dialog
                open={warningDialogOpen}
                variant="warning"
                title="削除できません"
                description={warningMessage}
                onClose={handleWarningDialogClose}
            />
        </>
    );
};
