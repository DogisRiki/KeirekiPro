import { Footer, MainMenu, UserMenu } from "@/components/ui";
import { AppBar, Box, Container, Toolbar, Typography } from "@mui/material";
import { Outlet } from "react-router";

/**
 * ログイン時のみアクセス可能な画面の共通レイアウト
 */
export const ProtectedLayout = () => {
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
            <Container sx={{ mt: 12 }}>
                <Outlet />
            </Container>
            <Footer />
        </Box>
    );
};
