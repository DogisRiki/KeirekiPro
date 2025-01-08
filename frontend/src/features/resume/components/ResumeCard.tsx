import {
    DateRange as DateRangeIcon,
    Delete as DeleteIcon,
    Download as DownloadIcon,
    Edit as EditIcon,
    MoreHoriz as MoreHorizIcon,
} from "@mui/icons-material";
import { Box, Card, CardContent, IconButton, Menu, MenuItem, Typography } from "@mui/material";
import React, { useState } from "react";

interface resumeCardProps {
    resumeId: string;
    resumeName: string;
    createdAt: string;
    updatedAt: string;
}

/**
 * カードメニュー
 */
const menuList = [
    { name: "編集", icon: <EditIcon sx={{ mr: 1 }} /> },
    { name: "削除", icon: <DeleteIcon sx={{ mr: 1 }} /> },
    { name: "エクスポート", icon: <DownloadIcon sx={{ mr: 1 }} /> },
];

/**
 * 職務経歴書カード
 */
export const ResumeCard = ({ resumeId, resumeName, createdAt, updatedAt }: resumeCardProps) => {
    const [menuAnchorEl, setMenuAnchorEl] = useState<HTMLElement | null>(null);
    const [openMenuId, setOpenMenuId] = useState<string | null>(null);

    const handleCardMenuClick = (event: React.MouseEvent<HTMLElement>, resumeId: string) => {
        event.stopPropagation();
        setMenuAnchorEl(event.currentTarget);
        setOpenMenuId(resumeId);
    };

    const handleCardMenuClose = () => {
        setMenuAnchorEl(null);
        setOpenMenuId(null);
    };

    return (
        <Card
            key={resumeId}
            sx={{
                cursor: "pointer",
                transition: "0.3s",
                "&:hover": {
                    opacity: 0.7,
                },
            }}
        >
            <CardContent sx={{ position: "relative" }}>
                {/* 3点リーダー */}
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
                            onClick={handleCardMenuClose}
                            sx={{ color: "primary.main", display: "flex", alignItems: "center", gap: 1 }}
                        >
                            {menu.icon}
                            {menu.name}
                        </MenuItem>
                    ))}
                </Menu>
                {/* 職務経歴書名 */}
                <Typography variant="h6" gutterBottom>
                    {resumeName}
                </Typography>
                {/* 作成日時 */}
                <Box sx={{ display: "flex", alignItems: "center", mb: 1 }}>
                    <DateRangeIcon sx={{ mr: 1 }} />
                    <Typography variant="body2" color="text.secondary">
                        作成日時: {createdAt}
                    </Typography>
                </Box>
                {/* 更新日時 */}
                <Box sx={{ display: "flex", alignItems: "center" }}>
                    <DateRangeIcon sx={{ mr: 1 }} />
                    <Typography variant="body2" color="text.secondary">
                        更新日時: {updatedAt}
                    </Typography>
                </Box>
            </CardContent>
        </Card>
    );
};
