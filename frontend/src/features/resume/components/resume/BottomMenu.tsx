import { Button, Dialog, Switch } from "@/components/ui";
import { paths } from "@/config/paths";
import { useDeleteResume, useExportResume, useResumeStore } from "@/features/resume";
import DeleteIcon from "@mui/icons-material/Delete";
import FileDownloadIcon from "@mui/icons-material/FileDownload";
import KeyboardArrowDownIcon from "@mui/icons-material/KeyboardArrowDown";
import KeyboardArrowUpIcon from "@mui/icons-material/KeyboardArrowUp";
import SaveIcon from "@mui/icons-material/Save";
import {
    alpha,
    Box,
    FormControlLabel,
    FormGroup,
    IconButton,
    Menu,
    MenuItem,
    Paper,
    Tooltip,
    useMediaQuery,
    useTheme,
} from "@mui/material";
import React, { useState } from "react";
import { useNavigate } from "react-router";

interface BottomMenuProps {
    /** 自動保存が有効かどうか */
    autoSaveEnabled: boolean;
    /** 自動保存の有効/無効を切り替えるハンドラー */
    onAutoSaveToggle: (enabled: boolean) => void;
    /** 保存ハンドラー */
    onSave: () => void;
    /** 保存中かどうか */
    isSaving: boolean;
    /** 保存可能かどうか */
    canSave: boolean;
}

/**
 * 下部に固定されたメニューバー
 */
export const BottomMenu = React.forwardRef<HTMLDivElement, BottomMenuProps>(
    ({ autoSaveEnabled, onAutoSaveToggle, onSave, isSaving, canSave }, ref) => {
        const theme = useTheme();
        const isXs = useMediaQuery(theme.breakpoints.down("sm"));
        const navigate = useNavigate();

        const resume = useResumeStore((state) => state.resume);
        const deleteMutation = useDeleteResume();
        const exportMutation = useExportResume();

        const [anchorEl, setAnchorEl] = useState<null | HTMLElement>(null);
        const [deleteDialogOpen, setDeleteDialogOpen] = useState(false);
        const [isCollapsed, setIsCollapsed] = useState(false);

        const handleExportButtonClick = (event: React.MouseEvent<HTMLElement>) => {
            setAnchorEl(event.currentTarget);
        };

        const handleExportButtonClose = () => {
            setAnchorEl(null);
        };

        /**
         * PDFでエクスポート
         */
        const handleExportPdf = () => {
            handleExportButtonClose();
            if (resume) {
                exportMutation.mutate({ resumeId: resume.id, format: "pdf" });
            }
        };

        /**
         * Markdownでエクスポート
         */
        const handleExportMarkdown = () => {
            handleExportButtonClose();
            if (resume) {
                exportMutation.mutate({ resumeId: resume.id, format: "markdown" });
            }
        };

        // エクスポートメニュー項目
        const exportMenuItems = [
            {
                label: "PDFでエクスポート",
                icon: <FileDownloadIcon />,
                action: handleExportPdf,
            },
            {
                label: "Markdownでエクスポート",
                icon: <FileDownloadIcon />,
                action: handleExportMarkdown,
            },
        ];

        /**
         * 削除確認ダイアログを開く
         */
        const handleDeleteClick = () => {
            setDeleteDialogOpen(true);
        };

        /**
         * 削除確認ダイアログのコールバック
         */
        const handleDeleteDialogClose = (confirmed: boolean) => {
            setDeleteDialogOpen(false);
            if (confirmed && resume) {
                deleteMutation.mutate(resume.id, {
                    onSuccess: () => {
                        navigate(paths.resume.list);
                    },
                });
            }
        };

        /**
         * 自動保存スイッチの変更ハンドラー
         */
        const handleAutoSaveChange = (event: React.ChangeEvent<HTMLInputElement>) => {
            onAutoSaveToggle(event.target.checked);
        };

        /**
         * 折りたたみ/展開の切り替え
         */
        const handleToggleCollapse = () => {
            setIsCollapsed(!isCollapsed);
        };

        // 折りたたみ時の表示
        if (isCollapsed) {
            return (
                <Paper
                    ref={ref}
                    elevation={3}
                    sx={{
                        position: "fixed",
                        bottom: 0,
                        left: 0,
                        right: 0,
                        zIndex: 1200,
                        display: "flex",
                        alignItems: "center",
                        justifyContent: "center",
                        p: 0.5,
                        bgcolor: alpha(theme.palette.background.paper, 0.9),
                    }}
                >
                    <Tooltip title="メニューを展開">
                        <IconButton onClick={handleToggleCollapse} size="small">
                            <KeyboardArrowUpIcon />
                        </IconButton>
                    </Tooltip>
                </Paper>
            );
        }

        // スマホ表示: アイコンボタンのみ
        if (isXs) {
            return (
                <>
                    <Paper
                        ref={ref}
                        elevation={3}
                        sx={{
                            position: "fixed",
                            bottom: 0,
                            left: 0,
                            right: 0,
                            zIndex: 1200,
                            display: "flex",
                            alignItems: "center",
                            justifyContent: "space-around",
                            p: 1,
                            bgcolor: alpha(theme.palette.background.paper, 0.95),
                        }}
                    >
                        {/* 折りたたみボタン */}
                        <IconButton
                            onClick={handleToggleCollapse}
                            size="small"
                            sx={{
                                position: "absolute",
                                left: "50%",
                                top: -16,
                                transform: "translateX(-50%)",
                                bgcolor: "background.paper",
                                boxShadow: 1,
                                width: 24,
                                height: 24,
                                "&:hover": {
                                    bgcolor: "grey.100",
                                },
                            }}
                        >
                            <KeyboardArrowDownIcon fontSize="small" />
                        </IconButton>

                        {/* 削除 */}
                        <Tooltip title="職務経歴書を削除">
                            <IconButton color="error" onClick={handleDeleteClick} disabled={deleteMutation.isPending}>
                                <DeleteIcon />
                            </IconButton>
                        </Tooltip>

                        {/* 保存 */}
                        <Tooltip title="保存">
                            <span>
                                <IconButton color="info" onClick={onSave} disabled={isSaving || !canSave}>
                                    <SaveIcon />
                                </IconButton>
                            </span>
                        </Tooltip>

                        {/* エクスポート */}
                        <Tooltip title="エクスポート">
                            <IconButton
                                color="primary"
                                onClick={handleExportButtonClick}
                                disabled={exportMutation.isPending}
                            >
                                <FileDownloadIcon />
                            </IconButton>
                        </Tooltip>

                        {/* 自動保存 */}
                        <FormGroup>
                            <FormControlLabel
                                control={
                                    <Switch
                                        color="success"
                                        checked={autoSaveEnabled}
                                        onChange={handleAutoSaveChange}
                                        size="small"
                                    />
                                }
                                label="自動"
                                sx={{
                                    m: 0,
                                    "& .MuiFormControlLabel-label": {
                                        fontSize: "0.75rem",
                                    },
                                }}
                            />
                        </FormGroup>
                    </Paper>

                    {/* エクスポートメニュー */}
                    <Menu anchorEl={anchorEl} open={Boolean(anchorEl)} onClose={handleExportButtonClose}>
                        {exportMenuItems.map((item, index) => (
                            <MenuItem
                                key={index}
                                onClick={item.action}
                                disabled={exportMutation.isPending}
                                sx={{
                                    color: "primary.main",
                                    display: "flex",
                                    alignItems: "center",
                                    gap: 1,
                                }}
                            >
                                {item.icon}
                                {item.label}
                            </MenuItem>
                        ))}
                    </Menu>

                    {/* 削除確認ダイアログ */}
                    <Dialog
                        open={deleteDialogOpen}
                        variant="confirm"
                        title="削除確認"
                        description={`「${resume?.resumeName ?? ""}」を削除しますか？この操作は取り消せません。`}
                        onClose={handleDeleteDialogClose}
                    />
                </>
            );
        }

        // PC表示: 従来のボタン表示
        return (
            <>
                <Paper
                    ref={ref}
                    elevation={3}
                    sx={{
                        position: "fixed",
                        bottom: 0,
                        left: 0,
                        right: 0,
                        zIndex: 1200,
                        display: "flex",
                        alignItems: "center",
                        gap: 3,
                        p: 2,
                        bgcolor: alpha(theme.palette.background.paper, 0.5),
                    }}
                >
                    {/* 折りたたみボタン */}
                    <Tooltip title="メニューを折りたたむ">
                        <IconButton
                            onClick={handleToggleCollapse}
                            size="small"
                            sx={{
                                position: "absolute",
                                left: "50%",
                                top: -20,
                                transform: "translateX(-50%)",
                                bgcolor: "background.paper",
                                boxShadow: 1,
                                "&:hover": {
                                    bgcolor: "grey.100",
                                },
                            }}
                        >
                            <KeyboardArrowDownIcon />
                        </IconButton>
                    </Tooltip>

                    {/* 職務経歴書を削除 */}
                    <Button
                        color="error"
                        startIcon={<DeleteIcon />}
                        size="medium"
                        onClick={handleDeleteClick}
                        disabled={deleteMutation.isPending}
                    >
                        職務経歴書を削除
                    </Button>

                    <Box sx={{ display: "flex", gap: 2, marginLeft: "auto", alignItems: "center" }}>
                        {/* 保存ボタン */}
                        <Button
                            color="info"
                            startIcon={<SaveIcon />}
                            size="medium"
                            onClick={onSave}
                            disabled={isSaving || !canSave}
                        >
                            保存
                        </Button>

                        {/* エクスポートボタン */}
                        <Button
                            startIcon={<FileDownloadIcon />}
                            size="medium"
                            onClick={handleExportButtonClick}
                            disabled={exportMutation.isPending}
                        >
                            エクスポート
                        </Button>

                        {/* エクスポートメニュー */}
                        <Menu anchorEl={anchorEl} open={Boolean(anchorEl)} onClose={handleExportButtonClose}>
                            {exportMenuItems.map((item, index) => (
                                <MenuItem
                                    key={index}
                                    onClick={item.action}
                                    disabled={exportMutation.isPending}
                                    sx={{
                                        color: "primary.main",
                                        display: "flex",
                                        alignItems: "center",
                                        gap: 1,
                                    }}
                                >
                                    {item.icon}
                                    {item.label}
                                </MenuItem>
                            ))}
                        </Menu>

                        {/* 自動保存 */}
                        <FormGroup>
                            <FormControlLabel
                                control={
                                    <Switch color="success" checked={autoSaveEnabled} onChange={handleAutoSaveChange} />
                                }
                                label="自動保存"
                            />
                        </FormGroup>
                    </Box>
                </Paper>

                {/* 削除確認ダイアログ */}
                <Dialog
                    open={deleteDialogOpen}
                    variant="confirm"
                    title="削除確認"
                    description={`「${resume?.resumeName ?? ""}」を削除しますか？この操作は取り消せません。`}
                    onClose={handleDeleteDialogClose}
                />
            </>
        );
    },
);

BottomMenu.displayName = "BottomMenu";
