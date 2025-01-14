import { paths } from "@/config/paths";
import {
    BusinessCenter,
    ContactMail as ContactMailIcon,
    Home as HomeIcon,
    Menu as MenuIcon,
} from "@mui/icons-material";
import { IconButton, Menu, MenuItem } from "@mui/material";
import React, { useState } from "react";
import { useNavigate } from "react-router";

const menuItems = [
    { label: "ホーム", icon: <HomeIcon />, path: paths.resume.list },
    { label: "職務経歴書作成", icon: <BusinessCenter />, path: paths.resume.new },
    { label: "お問い合わせ", icon: <ContactMailIcon />, path: paths.contact },
];

/**
 * メインメニュー
 */
export const MainMenu = () => {
    const [anchorEl, setAnchorEl] = useState<HTMLElement | null>(null);
    const navigate = useNavigate();

    const handleMenuOpen = (event: React.MouseEvent<HTMLElement>) => setAnchorEl(event.currentTarget);
    const handleMenuClose = () => setAnchorEl(null);

    const navigateTo = (path: string) => {
        navigate(path);
        handleMenuClose();
    };

    return (
        <>
            <IconButton size="large" edge="start" color="inherit" aria-label="menu" onClick={handleMenuOpen}>
                <MenuIcon
                    sx={{
                        "&:hover": {
                            bgcolor: "primary.light",
                        },
                    }}
                />
            </IconButton>
            <Menu anchorEl={anchorEl} open={Boolean(anchorEl)} onClose={handleMenuClose}>
                {menuItems.map((item, index) => (
                    <MenuItem
                        key={index}
                        onClick={() => navigateTo(item.path)}
                        sx={{
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
