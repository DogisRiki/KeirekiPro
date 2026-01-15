import { paths } from "@/config/paths";
import { useLogout } from "@/hooks";
import { useUserAuthStore } from "@/stores";
import LockIcon from "@mui/icons-material/Lock";
import LogoutIcon from "@mui/icons-material/Logout";
import ManageAccountsIcon from "@mui/icons-material/ManageAccounts";
import PersonIcon from "@mui/icons-material/Person";
import { Avatar, Box, ButtonBase, Menu, MenuItem, Typography } from "@mui/material";
import React, { useState } from "react";
import { useNavigate } from "react-router";

/**
 * ユーザーメニュー
 */
export const UserMenu = () => {
    const { user } = useUserAuthStore();
    const [imgError, setImgError] = useState(false);
    const [anchorEl, setAnchorEl] = useState<HTMLElement | null>(null);
    const navigate = useNavigate();
    const logoutMutation = useLogout();

    const userMenuItems = [
        { label: "ユーザー設定", icon: <ManageAccountsIcon />, path: paths.user },
        {
            label: user?.hasPassword ? "パスワード変更" : "パスワード設定",
            icon: <LockIcon />,
            path: user?.hasPassword ? paths.password.change : paths.emailPassword.set,
        },
        { label: "ログアウト", icon: <LogoutIcon />, action: "logout" },
    ];

    const handleMenuOpen = (event: React.MouseEvent<HTMLElement>) => setAnchorEl(event.currentTarget);

    const handleMenuClose = () => setAnchorEl(null);

    const handleLogout = () => {
        handleMenuClose();
        logoutMutation.mutate();
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
                    <Avatar
                        src={!imgError ? (user?.profileImage ?? undefined) : undefined}
                        onError={() => setImgError(true)}
                        sx={{ width: 32, height: 32, bgcolor: "primary.main" }}
                    >
                        <PersonIcon />
                    </Avatar>
                    <Typography variant="body2" sx={{ color: "primary.contrastText", fontSize: "14px" }}>
                        {user?.username}
                    </Typography>
                </Box>
            </ButtonBase>
            <Menu anchorEl={anchorEl} open={Boolean(anchorEl)} onClose={handleMenuClose}>
                {userMenuItems.map((item, index) => (
                    <MenuItem
                        key={index}
                        disabled={logoutMutation.isPending}
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
