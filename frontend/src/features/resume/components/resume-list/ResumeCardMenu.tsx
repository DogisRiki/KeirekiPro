import {
    Delete as DeleteIcon,
    Edit as EditIcon,
    ExpandMore as ExpandMoreIcon,
    FileDownload as FileDownloadIcon,
    MoreHoriz as MoreHorizIcon,
} from "@mui/icons-material";
import { IconButton, Menu, MenuItem } from "@mui/material";
import { useRef, useState } from "react";

const exportMenuList = [
    { label: "PDFでエクスポート", icon: <FileDownloadIcon sx={{ mr: 1 }} />, action: () => alert("PDFでエクスポート") },
    {
        label: "Markdownでエクスポート",
        icon: <FileDownloadIcon sx={{ mr: 1 }} />,
        action: () => alert("Markdownでエクスポート"),
    },
];

const menuList = [
    { name: "編集", icon: <EditIcon sx={{ mr: 1 }} />, action: () => alert("編集") },
    { name: "削除", icon: <DeleteIcon sx={{ mr: 1 }} />, action: () => alert("削除") },
    { name: "エクスポート", icon: <ExpandMoreIcon sx={{ mr: 1 }} />, isNested: true },
];

interface ResumeCardMenuProps {
    resumeId: string;
}

/**
 * 職務経歴書カードメニュー
 */
export const ResumeCardMenu = ({ resumeId }: ResumeCardMenuProps) => {
    // メインメニューの表示位置を制御する要素
    const [menuAnchorEl, setMenuAnchorEl] = useState<HTMLElement | null>(null);
    // エクスポートメニューの表示位置を制御する要素
    const [exportMenuAnchorEl, setExportMenuAnchorEl] = useState<HTMLElement | null>(null);
    // 開いているメニューのID
    const [openMenuId, setOpenMenuId] = useState<string | null>(null);
    // マウスイベントのタイミング制御用タイマー
    const timeoutRef = useRef<NodeJS.Timeout>();

    // メニューを開く
    const handleCardMenuClick = (event: React.MouseEvent<HTMLElement>, resumeId: string) => {
        event.stopPropagation();
        setMenuAnchorEl(event.currentTarget);
        setOpenMenuId(resumeId);
    };

    // 全てのメニューを閉じる
    const handleCardMenuClose = () => {
        setMenuAnchorEl(null);
        setExportMenuAnchorEl(null);
        setOpenMenuId(null);
    };

    // メニュー項目クリック時の処理
    const handleMenuItemClick = (action?: () => void) => {
        if (action) {
            action();
        }
        handleCardMenuClose();
    };

    // エクスポートメニューを表示する
    const handleExportMouseEnter = (event: React.MouseEvent<HTMLElement>) => {
        if (timeoutRef.current) {
            clearTimeout(timeoutRef.current);
        }
        setExportMenuAnchorEl(event.currentTarget);
    };

    // エクスポートメニューを100ms後に非表示にする
    const handleExportMouseLeave = () => {
        if (timeoutRef.current) {
            clearTimeout(timeoutRef.current);
        }
        timeoutRef.current = setTimeout(() => {
            setExportMenuAnchorEl(null);
        }, 100);
    };

    // エクスポートメニューの非表示タイマーをキャンセル
    const handlePaperMouseEnter = () => {
        if (timeoutRef.current) {
            clearTimeout(timeoutRef.current);
        }
    };

    return (
        <>
            {/* 3点アイコン */}
            <IconButton
                onClick={(event) => handleCardMenuClick(event, resumeId)}
                sx={{
                    position: "absolute",
                    top: 8,
                    right: 8,
                }}
            >
                <MoreHorizIcon />
            </IconButton>
            {/* メニュー */}
            <Menu
                anchorEl={menuAnchorEl}
                open={openMenuId === resumeId}
                onClose={handleCardMenuClose}
                anchorOrigin={{
                    vertical: "bottom",
                    horizontal: "right",
                }}
                transformOrigin={{
                    vertical: "top",
                    horizontal: "right",
                }}
            >
                {menuList.map((menu, index) => (
                    <MenuItem
                        key={resumeId + index}
                        onClick={menu.isNested ? undefined : () => handleMenuItemClick(menu.action)}
                        onMouseEnter={(event) => {
                            if (menu.isNested) {
                                handleExportMouseEnter(event);
                            } else {
                                handleExportMouseLeave();
                            }
                        }}
                        onMouseLeave={menu.isNested ? handleExportMouseLeave : undefined}
                        sx={{ color: "primary.main", display: "flex", alignItems: "center", gap: 1 }}
                    >
                        {menu.icon}
                        {menu.name}
                    </MenuItem>
                ))}
            </Menu>
            {/* ネストメニュー */}
            <Menu
                anchorEl={exportMenuAnchorEl}
                open={Boolean(exportMenuAnchorEl)}
                onClose={() => setExportMenuAnchorEl(null)}
                onMouseEnter={handlePaperMouseEnter}
                onMouseLeave={handleExportMouseLeave}
                anchorOrigin={{
                    vertical: "bottom",
                    horizontal: "left",
                }}
                transformOrigin={{
                    vertical: "top",
                    horizontal: "left",
                }}
                slotProps={{
                    paper: {
                        onMouseLeave: handleExportMouseLeave,
                        onMouseEnter: handlePaperMouseEnter,
                    },
                }}
            >
                {exportMenuList.map((menu, index) => (
                    <MenuItem
                        key={`export-${index}`}
                        onClick={() => handleMenuItemClick(menu.action)}
                        sx={{ color: "primary.main", display: "flex", alignItems: "center", gap: 1 }}
                    >
                        {menu.icon}
                        {menu.label}
                    </MenuItem>
                ))}
            </Menu>
        </>
    );
};
