import { Dialog } from "@/components/ui";
import { getEntryText, isTempId, useResumeStore } from "@/features/resume";
import DeleteIcon from "@mui/icons-material/Delete";
import FiberManualRecordIcon from "@mui/icons-material/FiberManualRecord";
import { IconButton, ListItem, ListItemButton, ListItemText, Tooltip } from "@mui/material";
import { useState } from "react";

/**
 * エントリーリストアイテムのProps
 */
interface EntryListItemProps {
    entry: { id: string };
    onDeleteEntry: (entryId: string, needsConfirm: boolean) => void;
}

/**
 * エントリーリストアイテム
 */
export const EntryListItem = ({ entry, onDeleteEntry }: EntryListItemProps) => {
    // ストアから必要な状態を取り出す
    const { activeSection, activeEntryId, setActiveEntryId } = useResumeStore();
    const dirtyEntryIds = useResumeStore((state) => state.dirtyEntryIds);

    const [deleteDialogOpen, setDeleteDialogOpen] = useState(false);

    // 未保存のエントリーかどうか
    const isUnsaved = dirtyEntryIds.has(entry.id);

    // 一時IDかどうか（新規追加されたエントリー）
    const isTemp = isTempId(entry.id);

    /**
     * ゴミ箱アイコンクリック
     */
    const handleDeleteClick = (event: React.MouseEvent<HTMLElement>) => {
        event.stopPropagation();

        // 一時IDの場合は確認なしで削除
        if (isTemp) {
            onDeleteEntry(entry.id, false);
            return;
        }

        // 既存エントリーの場合は確認ダイアログを表示
        setDeleteDialogOpen(true);
    };

    /**
     * 削除確認ダイアログのコールバック
     */
    const handleDeleteDialogClose = (confirmed: boolean) => {
        setDeleteDialogOpen(false);
        if (confirmed) {
            onDeleteEntry(entry.id, true);
        }
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
                    {/* ゴミ箱アイコン */}
                    <Tooltip title="削除" placement="top">
                        <IconButton edge="end" onClick={handleDeleteClick}>
                            <DeleteIcon />
                        </IconButton>
                    </Tooltip>
                </ListItemButton>
            </ListItem>

            {/* 削除確認ダイアログ（既存エントリーのみ） */}
            <Dialog
                open={deleteDialogOpen}
                variant="confirm"
                title="削除確認"
                description="このエントリーを削除しますか？この操作は取り消せません。"
                onClose={handleDeleteDialogClose}
            />
        </>
    );
};
