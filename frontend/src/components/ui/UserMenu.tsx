import { paths } from "@/config/paths";
import { useUserAuthStore } from "@/stores";
import {
    Lock as LockIcon,
    Logout as LogoutIcon,
    ManageAccounts as ManageAccountsIcon,
    Person as PersonIcon,
} from "@mui/icons-material";
import { Avatar, Box, ButtonBase, Menu, MenuItem, Typography } from "@mui/material";
import React, { useState } from "react";
import { useNavigate } from "react-router";

/**
 * ユーザーメニュー
 */
export const UserMenu = () => {
    const { user } = useUserAuthStore();
    const [anchorEl, setAnchorEl] = useState<HTMLElement | null>(null);
    const navigate = useNavigate();

    const userMenuItems = [
        { label: "ユーザー設定", icon: <ManageAccountsIcon />, path: paths.user },
        {
            label: user?.hasPassword ? "パスワード変更" : "パスワード設定",
            icon: <LockIcon />,
            path: paths.password.change,
        },
        { label: "ログアウト", icon: <LogoutIcon />, action: "logout" },
    ];

    const handleMenuOpen = (event: React.MouseEvent<HTMLElement>) => setAnchorEl(event.currentTarget);

    const handleMenuClose = () => setAnchorEl(null);

    const handleLogout = () => {
        navigate(paths.login);
        handleMenuClose();
    };

    const handleMenuItemClick = (item: (typeof userMenuItems)[0]) => {
        if (item.action === "logout") {
            handleLogout();
        } else if (item.path) {
            navigate(item.path);
            handleMenuClose();
        }
    };

    return (
        <>
            <ButtonBase
                onClick={handleMenuOpen}
                sx={{
                    cursor: "pointer",
                    transition: "0.3s",
                    borderRadius: 2,
                    border: "6px solid transparent",
                    "&:hover": {
                        bgcolor: "primary.light",
                    },
                }}
            >
                <Box
                    sx={{
                        display: "flex",
                        alignItems: "center",
                        gap: 1,
                        justifyContent: "center",
                    }}
                >
                    {/* プロフィール画像 */}
                    <Avatar src={user?.profileImage || undefined} sx={{ width: 32, height: 32, bgcolor: "#34495E" }}>
                        {/* srcがない場合に表示するデフォルトのアイコン */}
                        {user?.profileImage || <PersonIcon />}
                    </Avatar>
                    <Typography variant="body2" sx={{ color: "#ffffff", fontSize: "14px" }}>
                        {user?.username}
                    </Typography>
                </Box>
            </ButtonBase>
            <Menu anchorEl={anchorEl} open={Boolean(anchorEl)} onClose={handleMenuClose}>
                {userMenuItems.map((item, index) => (
                    <MenuItem
                        key={index}
                        onClick={() => handleMenuItemClick(item)}
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
        </>
    );
};
