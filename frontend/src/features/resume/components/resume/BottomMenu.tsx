import { Button, Switch } from "@/components/ui";
import {
    Delete as DeleteIcon,
    ExpandMore as ExpandMoreIcon,
    FileDownload as FileDownloadIcon,
} from "@mui/icons-material";
import { Box, FormControlLabel, FormGroup, Menu, MenuItem, Paper, useMediaQuery, useTheme } from "@mui/material";
import React from "react";

const exportMenuItems = [
    { label: "PDFでエクスポート", icon: <FileDownloadIcon />, action: () => alert("PDFでエクスポート") },
    { label: "Markdownでエクスポート", icon: <FileDownloadIcon />, action: () => alert("Markdownでエクスポート") },
];

/**
 * 下部に固定されたメニューバー
 */
export const BottomMenu = React.forwardRef<HTMLDivElement>((_, ref) => {
    const theme = useTheme();
    const isXs = useMediaQuery(theme.breakpoints.down("sm"));

    const [anchorEl, setAnchorEl] = React.useState<null | HTMLElement>(null);

    const handleExportButtonClick = (event: React.MouseEvent<HTMLElement>) => {
        setAnchorEl(event.currentTarget);
    };

    const handleExportButtonClose = () => {
        setAnchorEl(null);
    };

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
                alignItems: "center", // 縦方向の中央揃えを追加
                gap: 3, // ボタン間の間隔を設定
                p: 2,
                bgcolor: "rgba(255, 255, 255, 0.5)",
            }}
        >
            {/* 自動保存 */}
            <FormGroup>
                <FormControlLabel control={<Switch color="success" defaultChecked />} label="自動保存" />
            </FormGroup>
            <Box sx={{ display: "flex", gap: 2, marginLeft: "auto" }}>
                {/* エクスポートボタン */}
                <Button
                    startIcon={<ExpandMoreIcon />}
                    size={isXs ? "small" : "medium"}
                    onClick={handleExportButtonClick}
                >
                    エクスポート
                </Button>
                {/* エクスポートメニュー */}
                <Menu anchorEl={anchorEl} open={Boolean(anchorEl)} onClose={handleExportButtonClose}>
                    {exportMenuItems.map((item, index) => (
                        <MenuItem
                            key={index}
                            onClick={item.action}
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
                {/* 職務経歴書を削除ボタン */}
                <Button color="error" startIcon={<DeleteIcon />} size={isXs ? "small" : "medium"}>
                    職務経歴書を削除
                </Button>
            </Box>
        </Paper>
    );
});

BottomMenu.displayName = "BottomMenu";
