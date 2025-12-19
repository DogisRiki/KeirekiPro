import { Dialog } from "@/components/ui";
import { paths } from "@/config/paths";
import { useDeleteResume } from "@/features/resume";
import DeleteIcon from "@mui/icons-material/Delete";
import EditIcon from "@mui/icons-material/Edit";
import ExpandMoreIcon from "@mui/icons-material/ExpandMore";
import FileDownloadIcon from "@mui/icons-material/FileDownload";
import MoreHorizIcon from "@mui/icons-material/MoreHoriz";
import { Box, IconButton, Menu, MenuItem } from "@mui/material";
import { useRef, useState } from "react";
import { useNavigate } from "react-router";

const exportMenuList = [
    { label: "PDFでエクスポート", icon: <FileDownloadIcon sx={{ mr: 1 }} />, action: () => alert("PDFでエクスポート") },
    {
        label: "Markdownでエクスポート",
        icon: <FileDownloadIcon sx={{ mr: 1 }} />,
        action: () => alert("Markdownでエクスポート"),
    },
];

interface ResumeCardMenuProps {
    resumeId: string;
    resumeName: string;
}

/**
 * 職務経歴書カードメニュー
 */
export const ResumeCardMenu = ({ resumeId, resumeName }: ResumeCardMenuProps) => {
    const navigate = useNavigate();

    // 削除ミューテーション
    const deleteMutation = useDeleteResume();

    // メインメニューの表示位置を制御する要素
    const [menuAnchorEl, setMenuAnchorEl] = useState<HTMLElement | null>(null);
    // エクスポートメニューの表示位置を制御する要素
    const [exportMenuAnchorEl, setExportMenuAnchorEl] = useState<HTMLElement | null>(null);
    // 開いているメニューのID
    const [openMenuId, setOpenMenuId] = useState<string | null>(null);
    // マウスイベントのタイミング制御用タイマー
    const timeoutRef = useRef<ReturnType<typeof setTimeout> | null>(null);
    // 削除確認ダイアログの開閉状態
    const [deleteDialogOpen, setDeleteDialogOpen] = useState(false);

    /**
     * 編集画面へ遷移
     */
    const handleEdit = (event: React.MouseEvent) => {
        event.stopPropagation();
        handleCardMenuClose();
        const editPath = paths.resume.edit.replace(":id", resumeId);
        navigate(editPath);
    };

    /**
     * 削除確認ダイアログを開く
     */
    const handleDeleteClick = (event: React.MouseEvent) => {
        event.stopPropagation();
        handleCardMenuClose();
        setDeleteDialogOpen(true);
    };

    /**
     * 削除確認ダイアログのコールバック
     */
    const handleDeleteDialogClose = (confirmed: boolean) => {
        setDeleteDialogOpen(false);
        if (confirmed) {
            deleteMutation.mutate(resumeId);
        }
    };

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

    // エクスポート項目クリック時の処理
    const handleExportItemClick = (event: React.MouseEvent, action: () => void) => {
        event.stopPropagation();
        action();
        handleCardMenuClose();
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
                {/* 編集 */}
                <MenuItem
                    onClick={handleEdit}
                    onMouseEnter={handleExportMouseLeave}
                    sx={{ color: "primary.main", display: "flex", alignItems: "center", gap: 1 }}
                >
                    <EditIcon sx={{ mr: 1 }} />
                    編集
                </MenuItem>
                {/* 削除 */}
                <MenuItem
                    onClick={handleDeleteClick}
                    onMouseEnter={handleExportMouseLeave}
                    sx={{ color: "primary.main", display: "flex", alignItems: "center", gap: 1 }}
                >
                    <DeleteIcon sx={{ mr: 1 }} />
                    削除
                </MenuItem>
                {/* エクスポート */}
                <MenuItem
                    onMouseEnter={handleExportMouseEnter}
                    onMouseLeave={handleExportMouseLeave}
                    sx={{ color: "primary.main", display: "flex", alignItems: "center", gap: 1 }}
                >
                    <ExpandMoreIcon sx={{ mr: 1 }} />
                    エクスポート
                </MenuItem>
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
                        onClick={(event) => handleExportItemClick(event, menu.action)}
                        sx={{ color: "primary.main", display: "flex", alignItems: "center", gap: 1 }}
                    >
                        {menu.icon}
                        {menu.label}
                    </MenuItem>
                ))}
            </Menu>
            {/* 削除確認ダイアログ(イベント伝播を止めるためBoxでラップ) */}
            <Box onClick={(e) => e.stopPropagation()}>
                <Dialog
                    open={deleteDialogOpen}
                    variant="confirm"
                    title="削除確認"
                    description={`「${resumeName}」を削除しますか？この操作は取り消せません。`}
                    onClose={handleDeleteDialogClose}
                />
            </Box>
        </>
    );
};
