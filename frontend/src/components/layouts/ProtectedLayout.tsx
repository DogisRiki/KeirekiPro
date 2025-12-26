import { Footer, MainMenu, ScrollToTopButton, UserMenu } from "@/components/ui";
import { paths } from "@/config/paths";
import { useGoogleAnalytics } from "@/hooks";
import { useErrorMessageStore } from "@/stores";
import { AppBar, Box, Container, Toolbar, Typography } from "@mui/material";
import { useEffect } from "react";
import { Outlet, useLocation, useNavigate } from "react-router";

/**
 * ログイン時のみアクセス可能な画面の共通レイアウト
 */
export const ProtectedLayout = () => {
    const { clearErrors } = useErrorMessageStore();
    const { pathname } = useLocation();
    const navigate = useNavigate();

    useEffect(() => {
        clearErrors();
    }, [pathname, clearErrors]);

    useGoogleAnalytics();

    /**
     * ホームへ遷移
     */
    const handleLogoClick = () => {
        navigate(paths.resume.list);
    };

    return (
        <Box>
            <AppBar position="fixed">
                <Toolbar>
                    <MainMenu />
                    <Typography
                        variant="h6"
                        onClick={handleLogoClick}
                        sx={{
                            flexGrow: 1,
                            cursor: "pointer",
                            "&:hover": {
                                opacity: 0.7,
                            },
                        }}
                    >
                        KeirekiPro
                    </Typography>
                    <UserMenu />
                </Toolbar>
            </AppBar>
            <Container sx={{ mt: 12, mb: 4 }}>
                <Outlet />
            </Container>
            <Footer />
            <ScrollToTopButton />
        </Box>
    );
};
