import { paths } from "@/config/paths";
import { Logout as LogoutIcon, ManageAccounts as ManageAccountsIcon, Person as PersonIcon } from "@mui/icons-material";
import { Avatar, Box, ButtonBase, Menu, MenuItem, Typography } from "@mui/material";
import React, { useState } from "react";
import { useNavigate } from "react-router";

const userMenuItems = [
    { label: "ユーザー設定", icon: <ManageAccountsIcon />, path: paths.user },
    { label: "ログアウト", icon: <LogoutIcon />, action: "logout" },
];

/**
 * ユーザーメニュー
 */
export const UserMenu = () => {
    const [anchorEl, setAnchorEl] = useState<HTMLElement | null>(null);
    const navigate = useNavigate();

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
                    <Avatar sx={{ width: 32, height: 32, bgcolor: "#34495E" }}>
                        <PersonIcon fontSize="small" />
                    </Avatar>
                    <Typography variant="body2" sx={{ color: "#ffffff", fontSize: "14px" }}>
                        ユーザー名
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
