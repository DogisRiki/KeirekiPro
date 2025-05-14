import { Footer, MainMenu, UserMenu } from "@/components/ui";
import { useErrorMessageStore } from "@/stores";
import { AppBar, Box, Container, Toolbar, Typography } from "@mui/material";
import { useEffect } from "react";
import { Outlet, useLocation } from "react-router";

/**
 * ログイン時のみアクセス可能な画面の共通レイアウト
 */
export const ProtectedLayout = () => {
    const { clearErrors } = useErrorMessageStore();
    const { pathname } = useLocation();

    useEffect(() => {
        clearErrors();
    }, [pathname, clearErrors]);

    return (
        <Box>
            <AppBar position="fixed">
                <Toolbar>
                    <MainMenu />
                    <Typography variant="h6" sx={{ flexGrow: 1 }}>
                        KeirekiPro
                    </Typography>
                    <UserMenu />
                </Toolbar>
            </AppBar>
            <Container sx={{ mt: 12, mb: 4 }}>
                <Outlet />
            </Container>
            <Footer />
        </Box>
    );
};
